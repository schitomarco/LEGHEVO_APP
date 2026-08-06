-- LEGHEVO v0.61.5 · Accettazione documenti legali protetta
-- Migrazione interna: database/099_legal_acceptance_and_age_gate_safety.sql
--
-- Obiettivi:
-- - accettazione atomica, idempotente e revisionata dei documenti pubblicati;
-- - certificazione della dichiarazione sul requisito minimo di età;
-- - continuità multi-dispositivo e blocco delle scritture dirette;
-- - registro immutabile delle accettazioni;
-- - compatibilità con registrazione e RPC storiche.

begin;

-- Preflight dettagliato. La transazione non esegue modifiche quando manca una
-- dipendenza realmente necessaria al percorso protetto.
do $preflight$
declare
  v_missing text[] := array[]::text[];
  v_expected record;
begin
  if to_regclass('public.legal_document_releases') is null then
    v_missing := array_append(v_missing, 'table public.legal_document_releases');
  end if;
  if to_regclass('public.user_privacy_preferences') is null then
    v_missing := array_append(v_missing, 'table public.user_privacy_preferences');
  end if;
  if to_regclass('public.privacy_consent_events') is null then
    v_missing := array_append(v_missing, 'table public.privacy_consent_events');
  end if;
  if to_regclass('public.profiles') is null then
    v_missing := array_append(v_missing, 'table public.profiles');
  end if;
  if to_regclass('auth.users') is null then
    v_missing := array_append(v_missing, 'table auth.users');
  end if;
  if to_regprocedure('public.leghevo_sha256_hex_v1(text)') is null then
    v_missing := array_append(v_missing, 'function public.leghevo_sha256_hex_v1(text)');
  end if;
  if to_regprocedure('public.save_my_privacy_preferences(text,text,boolean)') is null then
    v_missing := array_append(v_missing, 'function public.save_my_privacy_preferences(text,text,boolean)');
  end if;
  if to_regprocedure('public.handle_new_user()') is null then
    v_missing := array_append(v_missing, 'function public.handle_new_user()');
  end if;

  for v_expected in
    select *
    from (values
      ('public', 'legal_document_releases', 'release_key'),
      ('public', 'legal_document_releases', 'privacy_policy_version'),
      ('public', 'legal_document_releases', 'terms_version'),
      ('public', 'legal_document_releases', 'minimum_age_version'),
      ('public', 'legal_document_releases', 'minimum_age'),
      ('public', 'legal_document_releases', 'market'),
      ('public', 'legal_document_releases', 'status'),
      ('public', 'user_privacy_preferences', 'user_id'),
      ('public', 'user_privacy_preferences', 'privacy_policy_version'),
      ('public', 'user_privacy_preferences', 'privacy_acknowledged_at'),
      ('public', 'user_privacy_preferences', 'terms_version'),
      ('public', 'user_privacy_preferences', 'terms_accepted_at'),
      ('public', 'user_privacy_preferences', 'marketing_consent'),
      ('public', 'user_privacy_preferences', 'marketing_updated_at'),
      ('public', 'user_privacy_preferences', 'minimum_age_version'),
      ('public', 'user_privacy_preferences', 'minimum_age_confirmed_at'),
      ('public', 'user_privacy_preferences', 'created_at'),
      ('public', 'user_privacy_preferences', 'updated_at'),
      ('public', 'privacy_consent_events', 'user_id'),
      ('public', 'privacy_consent_events', 'purpose'),
      ('public', 'privacy_consent_events', 'granted'),
      ('public', 'privacy_consent_events', 'document_version'),
      ('public', 'privacy_consent_events', 'source'),
      ('public', 'privacy_consent_events', 'occurred_at'),
      ('auth', 'users', 'id'),
      ('auth', 'users', 'email'),
      ('auth', 'users', 'raw_user_meta_data')
    ) as expected(table_schema, table_name, column_name)
  loop
    if not exists (
      select 1
      from information_schema.columns column_row
      where column_row.table_schema = v_expected.table_schema
        and column_row.table_name = v_expected.table_name
        and column_row.column_name = v_expected.column_name
    ) then
      v_missing := array_append(
        v_missing,
        format(
          'column %I.%I.%I',
          v_expected.table_schema,
          v_expected.table_name,
          v_expected.column_name
        )
      );
    end if;
  end loop;

  if coalesce(array_length(v_missing, 1), 0) > 0 then
    raise exception
      'Preflight v0.61.5 non superato. Oggetti mancanti: %',
      array_to_string(v_missing, '; ');
  end if;
end;
$preflight$;

alter table public.user_privacy_preferences
  add column if not exists revision bigint not null default 1,
  add column if not exists acceptance_fingerprint text,
  add column if not exists last_acceptance_request_id uuid,
  add column if not exists release_key text;

alter table public.user_privacy_preferences
  drop constraint if exists user_privacy_preferences_revision_check;
alter table public.user_privacy_preferences
  add constraint user_privacy_preferences_revision_check
  check (revision > 0);

alter table public.user_privacy_preferences
  drop constraint if exists user_privacy_preferences_release_key_fkey;
alter table public.user_privacy_preferences
  add constraint user_privacy_preferences_release_key_fkey
  foreign key (release_key)
  references public.legal_document_releases(release_key)
  on delete restrict
  not valid;

update public.user_privacy_preferences preferences
set release_key = release.release_key
from public.legal_document_releases release
where release.market = 'IT'
  and release.privacy_policy_version = preferences.privacy_policy_version
  and release.terms_version = preferences.terms_version
  and release.minimum_age_version = preferences.minimum_age_version
  and preferences.release_key is distinct from release.release_key;

alter table public.user_privacy_preferences
  validate constraint user_privacy_preferences_release_key_fkey;

create or replace function public.legal_acceptance_fingerprint_v1(
  p_user_id uuid,
  p_release_key text,
  p_privacy_policy_version text,
  p_terms_version text,
  p_minimum_age_version text,
  p_marketing_consent boolean,
  p_revision bigint
)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select public.leghevo_sha256_hex_v1(
    concat_ws(
      E'\n',
      coalesce(p_user_id::text, ''),
      coalesce(p_release_key, 'unmatched-release'),
      coalesce(p_privacy_policy_version, ''),
      coalesce(p_terms_version, ''),
      coalesce(p_minimum_age_version, ''),
      case when coalesce(p_marketing_consent, false) then 'marketing:on' else 'marketing:off' end,
      greatest(coalesce(p_revision, 1), 1)::text
    )
  )
$$;

revoke all on function public.legal_acceptance_fingerprint_v1(
  uuid, text, text, text, text, boolean, bigint
) from public, anon, authenticated;

update public.user_privacy_preferences preferences
set
  revision = greatest(preferences.revision, 1),
  acceptance_fingerprint = public.legal_acceptance_fingerprint_v1(
    preferences.user_id,
    preferences.release_key,
    preferences.privacy_policy_version,
    preferences.terms_version,
    preferences.minimum_age_version,
    preferences.marketing_consent,
    greatest(preferences.revision, 1)
  )
where preferences.acceptance_fingerprint is null
   or char_length(preferences.acceptance_fingerprint) <> 64
   or preferences.revision <= 0;

alter table public.user_privacy_preferences
  alter column acceptance_fingerprint set not null;

alter table public.user_privacy_preferences
  drop constraint if exists user_privacy_preferences_fingerprint_check;
alter table public.user_privacy_preferences
  add constraint user_privacy_preferences_fingerprint_check
  check (char_length(acceptance_fingerprint) = 64);

create table if not exists public.legal_acceptance_action_runs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  action_type text not null check (
    action_type in ('acceptance', 'registration', 'migration_backfill')
  ),
  idempotency_key uuid not null,
  previous_revision bigint not null check (previous_revision >= 0),
  result_revision bigint not null check (result_revision > 0),
  release_key text not null references public.legal_document_releases(release_key)
    on delete restrict,
  privacy_policy_version text not null,
  terms_version text not null,
  minimum_age_version text not null,
  request_fingerprint text not null check (char_length(request_fingerprint) = 64),
  result_fingerprint text not null check (char_length(result_fingerprint) = 64),
  result_snapshot jsonb not null check (jsonb_typeof(result_snapshot) = 'object'),
  created_at timestamptz not null default now(),
  unique (user_id, idempotency_key)
);

create index if not exists legal_acceptance_action_runs_user_idx
  on public.legal_acceptance_action_runs (user_id, created_at desc);

alter table public.legal_acceptance_action_runs enable row level security;
alter table public.legal_acceptance_action_runs replica identity full;

drop policy if exists legal_acceptance_action_runs_read_own
on public.legal_acceptance_action_runs;
create policy legal_acceptance_action_runs_read_own
on public.legal_acceptance_action_runs
for select to authenticated
using (user_id = auth.uid());

revoke all on table public.legal_acceptance_action_runs
from public, anon, authenticated;
grant select on table public.legal_acceptance_action_runs
to authenticated;

create or replace function public.prevent_legal_acceptance_action_run_mutation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- Le cancellazioni a cascata dovute alla rimozione definitiva dell'account
  -- devono poter completare il diritto all'oblio.
  if pg_trigger_depth() > 1 then
    return old;
  end if;

  raise exception
    'Accettazione legale certificata: modifica o cancellazione diretta non consentita.';
end;
$$;

revoke all on function public.prevent_legal_acceptance_action_run_mutation()
from public, anon, authenticated;

drop trigger if exists legal_acceptance_action_runs_immutable
on public.legal_acceptance_action_runs;
create trigger legal_acceptance_action_runs_immutable
before update or delete on public.legal_acceptance_action_runs
for each row execute function public.prevent_legal_acceptance_action_run_mutation();

create or replace function public.legal_acceptance_payload_v1(
  p_user_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_preferences public.user_privacy_preferences%rowtype;
  v_release public.legal_document_releases%rowtype;
  v_current boolean := false;
  v_action_count integer := 0;
  v_last_certified_at timestamptz;
begin
  select release.*
  into v_release
  from public.legal_document_releases release
  where release.market = 'IT'
    and release.status = 'published'
  order by release.published_at desc, release.release_key desc
  limit 1;

  select preferences.*
  into v_preferences
  from public.user_privacy_preferences preferences
  where preferences.user_id = p_user_id;

  if v_preferences.user_id is not null and v_release.release_key is not null then
    v_current :=
      v_preferences.release_key = v_release.release_key
      and v_preferences.privacy_policy_version = v_release.privacy_policy_version
      and v_preferences.terms_version = v_release.terms_version
      and v_preferences.minimum_age_version = v_release.minimum_age_version
      and v_preferences.minimum_age_confirmed_at is not null;
  end if;

  select count(*)::integer, max(action_run.created_at)
  into v_action_count, v_last_certified_at
  from public.legal_acceptance_action_runs action_run
  where action_run.user_id = p_user_id;

  return jsonb_build_object(
    'privacyPolicyVersion', v_preferences.privacy_policy_version,
    'privacyAcknowledgedAt', v_preferences.privacy_acknowledged_at,
    'termsVersion', v_preferences.terms_version,
    'termsAcceptedAt', v_preferences.terms_accepted_at,
    'marketingConsent', coalesce(v_preferences.marketing_consent, false),
    'marketingUpdatedAt', v_preferences.marketing_updated_at,
    'minimumAgeVersion', v_preferences.minimum_age_version,
    'minimumAgeConfirmedAt', v_preferences.minimum_age_confirmed_at,
    'releaseKey', v_preferences.release_key,
    'revision', coalesce(v_preferences.revision, 0),
    'acceptanceFingerprint', v_preferences.acceptance_fingerprint,
    'currentDocumentsAccepted', v_current,
    'protected', true,
    'certifiedActionCount', coalesce(v_action_count, 0),
    'lastCertifiedAt', v_last_certified_at,
    'currentRelease', jsonb_build_object(
      'releaseKey', v_release.release_key,
      'privacyPolicyVersion', v_release.privacy_policy_version,
      'termsVersion', v_release.terms_version,
      'minimumAgeVersion', v_release.minimum_age_version,
      'minimumAge', v_release.minimum_age,
      'market', v_release.market,
      'publishedAt', v_release.published_at
    )
  );
end;
$$;

revoke all on function public.legal_acceptance_payload_v1(uuid)
from public, anon, authenticated;

create or replace function public.get_my_privacy_center_v3()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
begin
  if v_user_id is null then
    raise exception 'Devi effettuare l''accesso.';
  end if;

  return public.legal_acceptance_payload_v1(v_user_id)
    || jsonb_build_object('generatedAt', now());
end;
$$;

create or replace function public.save_my_privacy_preferences_guarded_v1(
  p_privacy_policy_version text,
  p_terms_version text,
  p_minimum_age_version text,
  p_expected_revision bigint,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_now timestamptz := now();
  v_release public.legal_document_releases%rowtype;
  v_previous public.user_privacy_preferences%rowtype;
  v_current_revision bigint := 0;
  v_result_revision bigint;
  v_changed boolean := false;
  v_request_fingerprint text;
  v_result_fingerprint text;
  v_snapshot jsonb;
  v_existing_run public.legal_acceptance_action_runs%rowtype;
begin
  if v_user_id is null then
    raise exception 'Devi effettuare l''accesso.';
  end if;
  if p_idempotency_key is null then
    raise exception 'Identificativo operazione mancante.';
  end if;
  if coalesce(p_expected_revision, -1) < 0 then
    raise exception 'Revisione dei documenti non valida.';
  end if;

  select release.*
  into v_release
  from public.legal_document_releases release
  where release.status = 'published'
    and release.market = 'IT'
    and release.privacy_policy_version = trim(coalesce(p_privacy_policy_version, ''))
    and release.terms_version = trim(coalesce(p_terms_version, ''))
    and release.minimum_age_version = trim(coalesce(p_minimum_age_version, ''))
  order by release.published_at desc, release.release_key desc
  limit 1;

  if v_release.release_key is null then
    raise exception 'Versione dei documenti non valida.';
  end if;

  v_request_fingerprint := public.leghevo_sha256_hex_v1(
    concat_ws(
      E'\n',
      v_user_id::text,
      v_release.release_key,
      v_release.privacy_policy_version,
      v_release.terms_version,
      v_release.minimum_age_version,
      greatest(coalesce(p_expected_revision, 0), 0)::text,
      p_idempotency_key::text
    )
  );

  select action_run.*
  into v_existing_run
  from public.legal_acceptance_action_runs action_run
  where action_run.user_id = v_user_id
    and action_run.idempotency_key = p_idempotency_key;

  if v_existing_run.id is not null then
    if v_existing_run.request_fingerprint <> v_request_fingerprint then
      raise exception 'Identificativo operazione già usato con dati diversi.';
    end if;
    return v_existing_run.result_snapshot;
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended('leghevo:legal-acceptance:' || v_user_id::text, 0)
  );

  -- Ricontrollo dopo il lock per rendere sicuro anche il caso concorrente.
  select action_run.*
  into v_existing_run
  from public.legal_acceptance_action_runs action_run
  where action_run.user_id = v_user_id
    and action_run.idempotency_key = p_idempotency_key;

  if v_existing_run.id is not null then
    if v_existing_run.request_fingerprint <> v_request_fingerprint then
      raise exception 'Identificativo operazione già usato con dati diversi.';
    end if;
    return v_existing_run.result_snapshot;
  end if;

  select preferences.*
  into v_previous
  from public.user_privacy_preferences preferences
  where preferences.user_id = v_user_id
  for update;

  v_current_revision := coalesce(v_previous.revision, 0);

  if v_current_revision <> p_expected_revision then
    raise exception
      'I documenti sono stati aggiornati su un altro dispositivo. Ricarica e riprova.';
  end if;

  v_changed :=
    v_previous.user_id is null
    or v_previous.release_key is distinct from v_release.release_key
    or v_previous.privacy_policy_version is distinct from v_release.privacy_policy_version
    or v_previous.terms_version is distinct from v_release.terms_version
    or v_previous.minimum_age_version is distinct from v_release.minimum_age_version
    or v_previous.minimum_age_confirmed_at is null
    or v_previous.marketing_consent is distinct from false;

  v_result_revision := case
    when v_changed then v_current_revision + 1
    else greatest(v_current_revision, 1)
  end;

  if v_changed then
    if v_previous.user_id is null
      or v_previous.privacy_policy_version is distinct from v_release.privacy_policy_version then
      insert into public.privacy_consent_events (
        user_id, purpose, granted, document_version, source, occurred_at
      ) values (
        v_user_id, 'privacy_notice', true,
        v_release.privacy_policy_version, 'privacy_center_guarded', v_now
      );
    end if;

    if v_previous.user_id is null
      or v_previous.terms_version is distinct from v_release.terms_version then
      insert into public.privacy_consent_events (
        user_id, purpose, granted, document_version, source, occurred_at
      ) values (
        v_user_id, 'terms', true,
        v_release.terms_version, 'privacy_center_guarded', v_now
      );
    end if;

    if v_previous.user_id is null
      or v_previous.minimum_age_version is distinct from v_release.minimum_age_version
      or v_previous.minimum_age_confirmed_at is null then
      insert into public.privacy_consent_events (
        user_id, purpose, granted, document_version, source, occurred_at
      ) values (
        v_user_id, 'age_requirement', true,
        v_release.minimum_age_version, 'privacy_center_guarded', v_now
      );
    end if;

    if v_previous.user_id is null
      or v_previous.marketing_consent is distinct from false then
      insert into public.privacy_consent_events (
        user_id, purpose, granted, document_version, source, occurred_at
      ) values (
        v_user_id, 'marketing', false,
        v_release.privacy_policy_version, 'privacy_center_guarded', v_now
      );
    end if;

    v_result_fingerprint := public.legal_acceptance_fingerprint_v1(
      v_user_id,
      v_release.release_key,
      v_release.privacy_policy_version,
      v_release.terms_version,
      v_release.minimum_age_version,
      false,
      v_result_revision
    );

    insert into public.user_privacy_preferences (
      user_id,
      privacy_policy_version,
      privacy_acknowledged_at,
      terms_version,
      terms_accepted_at,
      marketing_consent,
      marketing_updated_at,
      minimum_age_version,
      minimum_age_confirmed_at,
      created_at,
      updated_at,
      revision,
      acceptance_fingerprint,
      last_acceptance_request_id,
      release_key
    ) values (
      v_user_id,
      v_release.privacy_policy_version,
      v_now,
      v_release.terms_version,
      v_now,
      false,
      v_now,
      v_release.minimum_age_version,
      v_now,
      v_now,
      v_now,
      v_result_revision,
      v_result_fingerprint,
      p_idempotency_key,
      v_release.release_key
    )
    on conflict (user_id)
    do update set
      privacy_policy_version = excluded.privacy_policy_version,
      privacy_acknowledged_at = case
        when public.user_privacy_preferences.privacy_policy_version
          is distinct from excluded.privacy_policy_version
        then excluded.privacy_acknowledged_at
        else public.user_privacy_preferences.privacy_acknowledged_at
      end,
      terms_version = excluded.terms_version,
      terms_accepted_at = case
        when public.user_privacy_preferences.terms_version
          is distinct from excluded.terms_version
        then excluded.terms_accepted_at
        else public.user_privacy_preferences.terms_accepted_at
      end,
      marketing_consent = false,
      marketing_updated_at = case
        when public.user_privacy_preferences.marketing_consent is distinct from false
        then excluded.marketing_updated_at
        else public.user_privacy_preferences.marketing_updated_at
      end,
      minimum_age_version = excluded.minimum_age_version,
      minimum_age_confirmed_at = case
        when public.user_privacy_preferences.minimum_age_version
          is distinct from excluded.minimum_age_version
          or public.user_privacy_preferences.minimum_age_confirmed_at is null
        then excluded.minimum_age_confirmed_at
        else public.user_privacy_preferences.minimum_age_confirmed_at
      end,
      updated_at = excluded.updated_at,
      revision = excluded.revision,
      acceptance_fingerprint = excluded.acceptance_fingerprint,
      last_acceptance_request_id = excluded.last_acceptance_request_id,
      release_key = excluded.release_key;
  else
    v_result_fingerprint := v_previous.acceptance_fingerprint;
  end if;

  v_snapshot := public.legal_acceptance_payload_v1(v_user_id)
    || jsonb_build_object('generatedAt', v_now);
  v_snapshot := v_snapshot || jsonb_build_object(
    'certifiedActionCount',
    coalesce((v_snapshot ->> 'certifiedActionCount')::integer, 0) + 1,
    'lastCertifiedAt',
    v_now
  );

  insert into public.legal_acceptance_action_runs (
    user_id,
    action_type,
    idempotency_key,
    previous_revision,
    result_revision,
    release_key,
    privacy_policy_version,
    terms_version,
    minimum_age_version,
    request_fingerprint,
    result_fingerprint,
    result_snapshot,
    created_at
  ) values (
    v_user_id,
    'acceptance',
    p_idempotency_key,
    v_current_revision,
    v_result_revision,
    v_release.release_key,
    v_release.privacy_policy_version,
    v_release.terms_version,
    v_release.minimum_age_version,
    v_request_fingerprint,
    v_result_fingerprint,
    v_snapshot,
    v_now
  );

  return v_snapshot;
end;
$$;

-- Compatibilità: la vecchia RPC usa ora il percorso protetto e mantiene
-- disattivato il marketing diretto, come previsto dai documenti pubblicati.
create or replace function public.save_my_privacy_preferences(
  p_privacy_policy_version text,
  p_terms_version text,
  p_marketing_consent boolean
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_revision bigint := 0;
  v_age_version text;
begin
  if v_user_id is null then
    raise exception 'Devi effettuare l''accesso.';
  end if;

  select coalesce(preferences.revision, 0)
  into v_revision
  from public.user_privacy_preferences preferences
  where preferences.user_id = v_user_id;

  select release.minimum_age_version
  into v_age_version
  from public.legal_document_releases release
  where release.status = 'published'
    and release.market = 'IT'
    and release.privacy_policy_version = trim(coalesce(p_privacy_policy_version, ''))
    and release.terms_version = trim(coalesce(p_terms_version, ''))
  order by release.published_at desc, release.release_key desc
  limit 1;

  if v_age_version is null then
    raise exception 'Versione dei documenti non valida.';
  end if;

  return public.save_my_privacy_preferences_guarded_v1(
    p_privacy_policy_version,
    p_terms_version,
    v_age_version,
    coalesce(v_revision, 0),
    gen_random_uuid()
  );
end;
$$;

-- Il trigger di registrazione certifica soltanto metadati corrispondenti a una
-- release pubblicata. Non usa auth.uid(), perché viene eseguito sull'evento Auth.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_privacy_version text := new.raw_user_meta_data ->> 'privacy_policy_version';
  v_terms_version text := new.raw_user_meta_data ->> 'terms_version';
  v_age_version text := new.raw_user_meta_data ->> 'minimum_age_version';
  v_privacy_acknowledged boolean :=
    lower(coalesce(new.raw_user_meta_data ->> 'privacy_acknowledged', 'false')) = 'true';
  v_terms_accepted boolean :=
    lower(coalesce(new.raw_user_meta_data ->> 'terms_accepted', 'false')) = 'true';
  v_age_confirmed boolean :=
    lower(coalesce(new.raw_user_meta_data ->> 'minimum_age_confirmed', 'false')) = 'true';
  v_now timestamptz := now();
  v_release public.legal_document_releases%rowtype;
  v_request_id uuid := gen_random_uuid();
  v_fingerprint text;
  v_snapshot jsonb;
begin
  insert into public.profiles (id, display_name)
  values (
    new.id,
    coalesce(
      nullif(trim(new.raw_user_meta_data ->> 'display_name'), ''),
      split_part(coalesce(new.email, 'mister'), '@', 1)
    )
  )
  on conflict (id) do nothing;

  if v_privacy_acknowledged and v_terms_accepted and v_age_confirmed then
    select release.*
    into v_release
    from public.legal_document_releases release
    where release.status = 'published'
      and release.market = 'IT'
      and release.privacy_policy_version = v_privacy_version
      and release.terms_version = v_terms_version
      and release.minimum_age_version = v_age_version
    order by release.published_at desc, release.release_key desc
    limit 1;
  end if;

  if v_release.release_key is not null then
    v_fingerprint := public.legal_acceptance_fingerprint_v1(
      new.id,
      v_release.release_key,
      v_release.privacy_policy_version,
      v_release.terms_version,
      v_release.minimum_age_version,
      false,
      1
    );

    insert into public.user_privacy_preferences (
      user_id,
      privacy_policy_version,
      privacy_acknowledged_at,
      terms_version,
      terms_accepted_at,
      marketing_consent,
      marketing_updated_at,
      minimum_age_version,
      minimum_age_confirmed_at,
      created_at,
      updated_at,
      revision,
      acceptance_fingerprint,
      last_acceptance_request_id,
      release_key
    ) values (
      new.id,
      v_release.privacy_policy_version,
      v_now,
      v_release.terms_version,
      v_now,
      false,
      v_now,
      v_release.minimum_age_version,
      v_now,
      v_now,
      v_now,
      1,
      v_fingerprint,
      v_request_id,
      v_release.release_key
    )
    on conflict (user_id) do nothing;

    insert into public.privacy_consent_events (
      user_id, purpose, granted, document_version, source, occurred_at
    ) values
      (new.id, 'privacy_notice', true, v_release.privacy_policy_version, 'registration_guarded', v_now),
      (new.id, 'terms', true, v_release.terms_version, 'registration_guarded', v_now),
      (new.id, 'age_requirement', true, v_release.minimum_age_version, 'registration_guarded', v_now),
      (new.id, 'marketing', false, v_release.privacy_policy_version, 'registration_guarded', v_now);

    v_snapshot := public.legal_acceptance_payload_v1(new.id)
      || jsonb_build_object(
        'generatedAt', v_now,
        'certifiedActionCount', 1,
        'lastCertifiedAt', v_now
      );

    insert into public.legal_acceptance_action_runs (
      user_id,
      action_type,
      idempotency_key,
      previous_revision,
      result_revision,
      release_key,
      privacy_policy_version,
      terms_version,
      minimum_age_version,
      request_fingerprint,
      result_fingerprint,
      result_snapshot,
      created_at
    ) values (
      new.id,
      'registration',
      v_request_id,
      0,
      1,
      v_release.release_key,
      v_release.privacy_policy_version,
      v_release.terms_version,
      v_release.minimum_age_version,
      public.leghevo_sha256_hex_v1(
        concat_ws(E'\n', new.id::text, v_release.release_key, 'registration', v_request_id::text)
      ),
      v_fingerprint,
      v_snapshot,
      v_now
    )
    on conflict (user_id, idempotency_key) do nothing;
  end if;

  return new;
end;
$$;

-- Certificazione non distruttiva delle accettazioni già correnti.
insert into public.legal_acceptance_action_runs (
  user_id,
  action_type,
  idempotency_key,
  previous_revision,
  result_revision,
  release_key,
  privacy_policy_version,
  terms_version,
  minimum_age_version,
  request_fingerprint,
  result_fingerprint,
  result_snapshot,
  created_at
)
select
  preferences.user_id,
  'migration_backfill',
  (
    substr(md5(preferences.user_id::text || ':legal-backfill-v1'), 1, 8) || '-' ||
    substr(md5(preferences.user_id::text || ':legal-backfill-v1'), 9, 4) || '-' ||
    substr(md5(preferences.user_id::text || ':legal-backfill-v1'), 13, 4) || '-' ||
    substr(md5(preferences.user_id::text || ':legal-backfill-v1'), 17, 4) || '-' ||
    substr(md5(preferences.user_id::text || ':legal-backfill-v1'), 21, 12)
  )::uuid,
  greatest(preferences.revision - 1, 0),
  preferences.revision,
  preferences.release_key,
  preferences.privacy_policy_version,
  preferences.terms_version,
  preferences.minimum_age_version,
  public.leghevo_sha256_hex_v1(
    concat_ws(E'\n', preferences.user_id::text, preferences.release_key, 'migration-backfill-v1')
  ),
  preferences.acceptance_fingerprint,
  public.legal_acceptance_payload_v1(preferences.user_id)
    || jsonb_build_object(
      'generatedAt', now(),
      'certifiedActionCount', 1,
      'lastCertifiedAt', coalesce(preferences.updated_at, preferences.created_at, now())
    ),
  coalesce(preferences.updated_at, preferences.created_at, now())
from public.user_privacy_preferences preferences
join public.legal_document_releases release
  on release.release_key = preferences.release_key
where release.status = 'published'
  and release.market = 'IT'
  and preferences.minimum_age_confirmed_at is not null
on conflict (user_id, idempotency_key) do nothing;

revoke all on table public.user_privacy_preferences
from public, anon, authenticated;
revoke all on table public.privacy_consent_events
from public, anon, authenticated;
grant select on table public.user_privacy_preferences to authenticated;
grant select on table public.privacy_consent_events to authenticated;

revoke all on function public.get_my_privacy_center_v3()
from public, anon;
grant execute on function public.get_my_privacy_center_v3()
to authenticated;

revoke all on function public.save_my_privacy_preferences_guarded_v1(
  text, text, text, bigint, uuid
) from public, anon;
grant execute on function public.save_my_privacy_preferences_guarded_v1(
  text, text, text, bigint, uuid
) to authenticated;

revoke all on function public.save_my_privacy_preferences(
  text, text, boolean
) from public, anon;
grant execute on function public.save_my_privacy_preferences(
  text, text, boolean
) to authenticated;

-- Pubblicazione Realtime idempotente. Se la publication non esiste in questo
-- ambiente, la diagnostica considera correttamente il canale non applicabile.
do $realtime$
declare
  v_table_name text;
begin
  if exists (
    select 1
    from pg_catalog.pg_publication publication
    where publication.pubname = 'supabase_realtime'
  ) then
    foreach v_table_name in array array[
      'user_privacy_preferences',
      'privacy_consent_events',
      'legal_acceptance_action_runs'
    ] loop
      execute format('alter table public.%I replica identity full', v_table_name);

      if not exists (
        select 1
        from pg_catalog.pg_publication_tables publication_table
        where publication_table.pubname = 'supabase_realtime'
          and publication_table.schemaname = 'public'
          and publication_table.tablename = v_table_name
      ) then
        execute format(
          'alter publication supabase_realtime add table public.%I',
          v_table_name
        );
      end if;
    end loop;
  end if;
end;
$realtime$;

create or replace function public.get_legal_acceptance_safety_integrity_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_realtime_ready boolean;
begin
  select
    not exists (
      select 1
      from pg_catalog.pg_publication publication
      where publication.pubname = 'supabase_realtime'
    )
    or (
      select count(*) = 3
      from (values
        ('user_privacy_preferences'),
        ('privacy_consent_events'),
        ('legal_acceptance_action_runs')
      ) expected(table_name)
      where exists (
        select 1
        from pg_catalog.pg_publication_tables publication_table
        where publication_table.pubname = 'supabase_realtime'
          and publication_table.schemaname = 'public'
          and publication_table.tablename = expected.table_name
      )
    )
  into v_realtime_ready;

  return jsonb_build_object(
    'preferencesRevisionReady', exists (
      select 1 from information_schema.columns column_row
      where column_row.table_schema = 'public'
        and column_row.table_name = 'user_privacy_preferences'
        and column_row.column_name = 'revision'
        and column_row.is_nullable = 'NO'
    ),
    'preferencesFingerprintReady', exists (
      select 1 from information_schema.columns column_row
      where column_row.table_schema = 'public'
        and column_row.table_name = 'user_privacy_preferences'
        and column_row.column_name = 'acceptance_fingerprint'
        and column_row.is_nullable = 'NO'
    ),
    'preferencesReleaseKeyReady', exists (
      select 1 from information_schema.columns column_row
      where column_row.table_schema = 'public'
        and column_row.table_name = 'user_privacy_preferences'
        and column_row.column_name = 'release_key'
    ),
    'preferencesRequestKeyReady', exists (
      select 1 from information_schema.columns column_row
      where column_row.table_schema = 'public'
        and column_row.table_name = 'user_privacy_preferences'
        and column_row.column_name = 'last_acceptance_request_id'
    ),
    'actionRunsReady', to_regclass('public.legal_acceptance_action_runs') is not null,
    'actionRunsColumnsReady', (
      select count(*) = 13
      from information_schema.columns column_row
      where column_row.table_schema = 'public'
        and column_row.table_name = 'legal_acceptance_action_runs'
        and column_row.column_name in (
          'id', 'user_id', 'action_type', 'idempotency_key',
          'previous_revision', 'result_revision', 'release_key',
          'privacy_policy_version', 'terms_version', 'minimum_age_version',
          'request_fingerprint', 'result_fingerprint', 'result_snapshot'
        )
    ),
    'actionRunsRlsReady', coalesce((
      select class.relrowsecurity
      from pg_catalog.pg_class class
      where class.oid = to_regclass('public.legal_acceptance_action_runs')
    ), false),
    'actionRunsReadPolicyReady', exists (
      select 1 from pg_catalog.pg_policies policy
      where policy.schemaname = 'public'
        and policy.tablename = 'legal_acceptance_action_runs'
        and policy.policyname = 'legal_acceptance_action_runs_read_own'
    ),
    'actionRunsImmutable', exists (
      select 1 from pg_catalog.pg_trigger trigger_row
      where trigger_row.tgrelid = to_regclass('public.legal_acceptance_action_runs')
        and trigger_row.tgname = 'legal_acceptance_action_runs_immutable'
        and not trigger_row.tgisinternal
    ),
    'payloadAndFingerprintReady',
      to_regprocedure(
        'public.legal_acceptance_fingerprint_v1(uuid,text,text,text,text,boolean,bigint)'
      ) is not null
      and to_regprocedure('public.legal_acceptance_payload_v1(uuid)') is not null,
    'guardedSaveReady', to_regprocedure(
      'public.save_my_privacy_preferences_guarded_v1(text,text,text,bigint,uuid)'
    ) is not null,
    'centerV3Ready', to_regprocedure('public.get_my_privacy_center_v3()') is not null,
    'legacyRoutesGuarded', coalesce(
      pg_get_functiondef(
        to_regprocedure('public.save_my_privacy_preferences(text,text,boolean)')
      ) ilike '%save_my_privacy_preferences_guarded_v1%',
      false
    ),
    'registrationGateProtected', coalesce(
      pg_get_functiondef(to_regprocedure('public.handle_new_user()'))
        ilike '%legal_acceptance_action_runs%'
      and pg_get_functiondef(to_regprocedure('public.handle_new_user()'))
        ilike '%minimum_age_confirmed%',
      false
    ),
    'currentReleaseReady', (
      select count(*) = 1
      from public.legal_document_releases release
      where release.status = 'published'
        and release.market = 'IT'
    ),
    'preferenceRowsConsistent', not exists (
      select 1
      from public.user_privacy_preferences preferences
      where preferences.revision <= 0
         or preferences.acceptance_fingerprint is null
         or char_length(preferences.acceptance_fingerprint) <> 64
         or (
           exists (
             select 1
             from public.legal_document_releases release
             where release.status = 'published'
               and release.market = 'IT'
               and release.privacy_policy_version = preferences.privacy_policy_version
               and release.terms_version = preferences.terms_version
               and release.minimum_age_version = preferences.minimum_age_version
           )
           and preferences.release_key is null
         )
    ),
    'authenticatedAccessReady',
      has_function_privilege(
        'authenticated',
        'public.save_my_privacy_preferences_guarded_v1(text,text,text,bigint,uuid)',
        'EXECUTE'
      )
      and has_function_privilege(
        'authenticated',
        'public.get_my_privacy_center_v3()',
        'EXECUTE'
      ),
    'anonymousBlocked',
      not has_function_privilege(
        'anon',
        'public.save_my_privacy_preferences_guarded_v1(text,text,text,bigint,uuid)',
        'EXECUTE'
      )
      and not has_function_privilege(
        'anon',
        'public.get_my_privacy_center_v3()',
        'EXECUTE'
      ),
    'directWritesBlocked',
      not has_table_privilege(
        'authenticated', 'public.user_privacy_preferences', 'INSERT,UPDATE,DELETE'
      )
      and not has_table_privilege(
        'authenticated', 'public.privacy_consent_events', 'INSERT,UPDATE,DELETE'
      )
      and not has_table_privilege(
        'authenticated', 'public.legal_acceptance_action_runs', 'INSERT,UPDATE,DELETE'
      ),
    'realtimeReady', v_realtime_ready
  );
end;
$$;

revoke all on function public.get_legal_acceptance_safety_integrity_v1()
from public, anon;
grant execute on function public.get_legal_acceptance_safety_integrity_v1()
to authenticated, service_role;

-- Validazione transazionale con dettaglio delle eventuali condizioni false.
do $validation$
declare
  v_integrity jsonb;
  v_failures jsonb;
begin
  v_integrity := public.get_legal_acceptance_safety_integrity_v1();

  select coalesce(jsonb_object_agg(entry.key, entry.value), '{}'::jsonb)
  into v_failures
  from jsonb_each(v_integrity) entry
  where entry.value <> 'true'::jsonb;

  if v_failures <> '{}'::jsonb then
    raise exception
      'Validazione v0.61.5 non superata. Controlli falsi: %',
      v_failures;
  end if;
end;
$validation$;

commit;

-- Diagnostica finale: devono comparire esattamente 20 valori true.
select
  (integrity ->> 'preferencesRevisionReady')::boolean
    as privacy_revision_ready,
  (integrity ->> 'preferencesFingerprintReady')::boolean
    as privacy_fingerprint_ready,
  (integrity ->> 'preferencesReleaseKeyReady')::boolean
    as privacy_release_key_ready,
  (integrity ->> 'preferencesRequestKeyReady')::boolean
    as privacy_request_key_ready,
  (integrity ->> 'actionRunsReady')::boolean
    as legal_action_runs_ready,
  (integrity ->> 'actionRunsColumnsReady')::boolean
    as legal_action_runs_columns_ready,
  (integrity ->> 'actionRunsRlsReady')::boolean
    as legal_action_runs_rls_ready,
  (integrity ->> 'actionRunsReadPolicyReady')::boolean
    as legal_action_runs_read_policy_ready,
  (integrity ->> 'actionRunsImmutable')::boolean
    as legal_action_runs_immutable,
  (integrity ->> 'payloadAndFingerprintReady')::boolean
    as legal_helpers_ready,
  (integrity ->> 'guardedSaveReady')::boolean
    as legal_guarded_save_ready,
  (integrity ->> 'centerV3Ready')::boolean
    as privacy_center_v3_ready,
  (integrity ->> 'legacyRoutesGuarded')::boolean
    as legal_legacy_route_ready,
  (integrity ->> 'registrationGateProtected')::boolean
    as registration_gate_protected,
  (integrity ->> 'currentReleaseReady')::boolean
    as current_legal_release_ready,
  (integrity ->> 'preferenceRowsConsistent')::boolean
    as privacy_rows_consistent,
  (integrity ->> 'authenticatedAccessReady')::boolean
    as legal_authenticated_access_ready,
  (integrity ->> 'anonymousBlocked')::boolean
    as legal_anonymous_blocked,
  (integrity ->> 'directWritesBlocked')::boolean
    as legal_direct_writes_blocked,
  (integrity ->> 'realtimeReady')::boolean
    as legal_realtime_ready
from (
  select public.get_legal_acceptance_safety_integrity_v1() as integrity
) diagnostics;
