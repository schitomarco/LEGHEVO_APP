-- LEGHEVO v0.61.8 · Esportazione dati personali protetta e certificata
-- Migrazione interna: database/102_personal_data_export_safety.sql
--
-- Obiettivi:
-- - proteggere l'esportazione JSON con chiave idempotente e lock per account;
-- - certificare revisione, impronta e versione senza duplicare il contenuto esportato;
-- - impedire l'uso diretto delle vecchie RPC di esportazione;
-- - sincronizzare il Centro Privacy tra dispositivi;
-- - non modificare profilo, consensi, leghe o dati sportivi esistenti.

begin;

-- Preflight dettagliato: lo script non esegue scritture se manca una
-- dipendenza già validata nelle versioni precedenti.
do $preflight$
declare
  v_missing text[] := array[]::text[];
  v_expected record;
begin
  if to_regclass('public.profiles') is null then
    v_missing := array_append(v_missing, 'table public.profiles');
  end if;
  if to_regprocedure('public.export_my_personal_data_v5()') is null then
    v_missing := array_append(v_missing, 'function public.export_my_personal_data_v5()');
  end if;
  if to_regprocedure('public.get_my_privacy_center_v3()') is null then
    v_missing := array_append(v_missing, 'function public.get_my_privacy_center_v3()');
  end if;
  if to_regprocedure('public.leghevo_sha256_hex_v1(text)') is null then
    v_missing := array_append(v_missing, 'function public.leghevo_sha256_hex_v1(text)');
  end if;

  for v_expected in
    select *
    from (values
      ('profiles', 'id'),
      ('profiles', 'deleted_at')
    ) as expected(table_name, column_name)
  loop
    if not exists (
      select 1
      from information_schema.columns column_row
      where column_row.table_schema = 'public'
        and column_row.table_name = v_expected.table_name
        and column_row.column_name = v_expected.column_name
    ) then
      v_missing := array_append(
        v_missing,
        format('column public.%I.%I', v_expected.table_name, v_expected.column_name)
      );
    end if;
  end loop;

  if coalesce(array_length(v_missing, 1), 0) > 0 then
    raise exception
      'Preflight v0.61.8 non superato. Oggetti mancanti: %',
      array_to_string(v_missing, '; ');
  end if;
end;
$preflight$;

create table if not exists public.personal_data_export_runs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  idempotency_key uuid not null,
  export_revision bigint not null check (export_revision > 0),
  source_export_version integer not null check (source_export_version > 0),
  payload_fingerprint text not null check (char_length(payload_fingerprint) = 64),
  top_level_sections integer not null check (top_level_sections >= 0),
  result_snapshot jsonb not null check (jsonb_typeof(result_snapshot) = 'object'),
  created_at timestamptz not null default now(),
  unique (user_id, idempotency_key),
  unique (user_id, export_revision)
);

create index if not exists personal_data_export_runs_user_idx
  on public.personal_data_export_runs (user_id, created_at desc);

alter table public.personal_data_export_runs enable row level security;
alter table public.personal_data_export_runs replica identity full;

drop policy if exists personal_data_export_runs_read_own
on public.personal_data_export_runs;
create policy personal_data_export_runs_read_own
on public.personal_data_export_runs
for select to authenticated
using (user_id = auth.uid());

revoke all on table public.personal_data_export_runs
from public, anon, authenticated;
grant select on table public.personal_data_export_runs
to authenticated;

create or replace function public.prevent_personal_data_export_run_mutation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- La cancellazione definitiva dell'account marca prima il profilo come
  -- eliminato e poi rimuove l'utente Auth. In quel solo caso il CASCADE può
  -- cancellare anche il registro, evitando di conservare copie riferibili a
  -- un account non più esistente.
  if tg_op = 'DELETE' and not exists (
    select 1
    from public.profiles profile
    where profile.id = old.user_id
      and profile.deleted_at is null
  ) then
    return old;
  end if;

  raise exception
    'Esportazione certificata: modifica o cancellazione diretta non consentita.';
end;
$$;

revoke all on function public.prevent_personal_data_export_run_mutation()
from public, anon, authenticated;

drop trigger if exists personal_data_export_runs_immutable
on public.personal_data_export_runs;
create trigger personal_data_export_runs_immutable
before update or delete on public.personal_data_export_runs
for each row execute function public.prevent_personal_data_export_run_mutation();

create or replace function public.personal_data_export_fingerprint_v1(
  p_export jsonb
)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_canonical jsonb := coalesce(p_export, '{}'::jsonb)
    - 'generated_at'
    - 'generatedAt';
begin
  -- Le vecchie esportazioni includono timestamp di generazione dinamici.
  -- Vengono esclusi soltanto dall'impronta, non dal file consegnato all'utente.
  if jsonb_typeof(v_canonical -> 'data_rights_center') = 'object' then
    v_canonical := jsonb_set(
      v_canonical,
      '{data_rights_center}',
      (v_canonical -> 'data_rights_center') - 'generatedAt',
      false
    );
  end if;

  if jsonb_typeof(v_canonical -> 'supportCenter') = 'object' then
    v_canonical := jsonb_set(
      v_canonical,
      '{supportCenter}',
      (v_canonical -> 'supportCenter') - 'generatedAt',
      false
    );
  end if;

  return public.leghevo_sha256_hex_v1(v_canonical::text);
end;
$$;

revoke all on function public.personal_data_export_fingerprint_v1(jsonb)
from public, anon, authenticated;

create or replace function public.export_my_personal_data_guarded_v1(
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_profile_id uuid;
  v_export jsonb;
  v_fingerprint text;
  v_top_level_sections integer := 0;
  v_source_export_version integer := 5;
  v_export_revision bigint;
  v_certificate jsonb;
  v_existing public.personal_data_export_runs%rowtype;
begin
  if v_user_id is null then
    raise exception 'Devi effettuare l''accesso.';
  end if;
  if p_idempotency_key is null then
    raise exception 'Identificativo operazione mancante.';
  end if;

  select profile.id
  into v_profile_id
  from public.profiles profile
  where profile.id = v_user_id
    and profile.deleted_at is null;

  if v_profile_id is null then
    raise exception 'Profilo non trovato o non più attivo.';
  end if;

  select export_run.*
  into v_existing
  from public.personal_data_export_runs export_run
  where export_run.user_id = v_user_id
    and export_run.idempotency_key = p_idempotency_key;

  if v_existing.id is not null then
    v_export := public.export_my_personal_data_v5();
    if v_export is null or jsonb_typeof(v_export) <> 'object' then
      raise exception 'La copia dati prodotta non è valida.';
    end if;

    v_fingerprint := public.personal_data_export_fingerprint_v1(v_export);
    if v_fingerprint <> v_existing.payload_fingerprint then
      raise exception
        'I dati sono cambiati durante il tentativo. Avvia una nuova esportazione.';
    end if;

    return v_export || jsonb_build_object(
      'exportVersion', 6,
      'exportCertificate', v_existing.result_snapshot
    );
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'leghevo:personal-data-export:' || v_user_id::text,
      0
    )
  );

  -- Ricontrollo dopo il lock per gestire due richieste concorrenti con la
  -- stessa chiave senza produrre due revisioni.
  select export_run.*
  into v_existing
  from public.personal_data_export_runs export_run
  where export_run.user_id = v_user_id
    and export_run.idempotency_key = p_idempotency_key;

  if v_existing.id is not null then
    v_export := public.export_my_personal_data_v5();
    if v_export is null or jsonb_typeof(v_export) <> 'object' then
      raise exception 'La copia dati prodotta non è valida.';
    end if;

    v_fingerprint := public.personal_data_export_fingerprint_v1(v_export);
    if v_fingerprint <> v_existing.payload_fingerprint then
      raise exception
        'I dati sono cambiati durante il tentativo. Avvia una nuova esportazione.';
    end if;

    return v_export || jsonb_build_object(
      'exportVersion', 6,
      'exportCertificate', v_existing.result_snapshot
    );
  end if;

  v_export := public.export_my_personal_data_v5();
  if v_export is null or jsonb_typeof(v_export) <> 'object' then
    raise exception 'La copia dati prodotta non è valida.';
  end if;

  begin
    v_source_export_version := greatest(
      coalesce((v_export ->> 'exportVersion')::integer, 5),
      1
    );
  exception
    when invalid_text_representation then
      v_source_export_version := 5;
  end;

  select count(*)::integer
  into v_top_level_sections
  from jsonb_object_keys(v_export);

  v_fingerprint := public.personal_data_export_fingerprint_v1(v_export);

  select coalesce(max(export_run.export_revision), 0) + 1
  into v_export_revision
  from public.personal_data_export_runs export_run
  where export_run.user_id = v_user_id;

  v_certificate := jsonb_build_object(
    'protected', true,
    'idempotent', true,
    'exportRevision', v_export_revision,
    'sourceExportVersion', v_source_export_version,
    'payloadFingerprint', v_fingerprint,
    'topLevelSections', v_top_level_sections,
    'generatedAt', now()
  );

  insert into public.personal_data_export_runs (
    user_id,
    idempotency_key,
    export_revision,
    source_export_version,
    payload_fingerprint,
    top_level_sections,
    result_snapshot
  ) values (
    v_user_id,
    p_idempotency_key,
    v_export_revision,
    v_source_export_version,
    v_fingerprint,
    v_top_level_sections,
    v_certificate
  );

  return v_export || jsonb_build_object(
    'exportVersion', 6,
    'exportCertificate', v_certificate
  );
end;
$$;

create or replace function public.get_my_privacy_center_v4()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_base jsonb;
  v_export_count bigint := 0;
  v_last_revision bigint := 0;
  v_last_exported_at timestamptz;
  v_last_fingerprint text;
begin
  if v_user_id is null then
    raise exception 'Devi effettuare l''accesso.';
  end if;

  v_base := public.get_my_privacy_center_v3();

  select
    count(*),
    coalesce(max(export_run.export_revision), 0)
  into v_export_count, v_last_revision
  from public.personal_data_export_runs export_run
  where export_run.user_id = v_user_id;

  select export_run.created_at, export_run.payload_fingerprint
  into v_last_exported_at, v_last_fingerprint
  from public.personal_data_export_runs export_run
  where export_run.user_id = v_user_id
  order by export_run.export_revision desc
  limit 1;

  return v_base || jsonb_build_object(
    'exportProtected', true,
    'certifiedExportCount', v_export_count,
    'exportRevision', v_last_revision,
    'lastExportedAt', v_last_exported_at,
    'lastExportFingerprint', v_last_fingerprint,
    'generatedAt', now()
  );
end;
$$;

-- Le RPC storiche restano disponibili soltanto come componenti interne del
-- wrapper security-definer. L'account autenticato non può più bypassare il
-- registro certificato chiamandole direttamente.
do $revoke_legacy_exports$
declare
  v_function record;
begin
  for v_function in
    select
      procedure_row.proname as function_name,
      pg_catalog.pg_get_function_identity_arguments(procedure_row.oid)
        as identity_arguments
    from pg_catalog.pg_proc procedure_row
    join pg_catalog.pg_namespace namespace_row
      on namespace_row.oid = procedure_row.pronamespace
    where namespace_row.nspname = 'public'
      and procedure_row.proname ~ '^export_my_personal_data(_v[0-9]+)?$'
  loop
    execute format(
      'revoke all on function public.%I(%s) from public, anon, authenticated',
      v_function.function_name,
      v_function.identity_arguments
    );
  end loop;
end;
$revoke_legacy_exports$;

revoke all on function public.export_my_personal_data_guarded_v1(uuid)
from public, anon, authenticated;
revoke all on function public.get_my_privacy_center_v4()
from public, anon, authenticated;

grant execute on function public.export_my_personal_data_guarded_v1(uuid)
to authenticated;
grant execute on function public.get_my_privacy_center_v4()
to authenticated;

-- Pubblicazione Realtime idempotente del registro personale.
do $realtime$
begin
  if exists (
    select 1
    from pg_catalog.pg_publication publication_row
    where publication_row.pubname = 'supabase_realtime'
  ) and not exists (
    select 1
    from pg_catalog.pg_publication_tables publication_table
    where publication_table.pubname = 'supabase_realtime'
      and publication_table.schemaname = 'public'
      and publication_table.tablename = 'personal_data_export_runs'
  ) then
    alter publication supabase_realtime
      add table public.personal_data_export_runs;
  end if;
end;
$realtime$;

create or replace function public.get_personal_data_export_safety_integrity_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_table oid := to_regclass('public.personal_data_export_runs');
  v_guarded oid := to_regprocedure(
    'public.export_my_personal_data_guarded_v1(uuid)'
  );
  v_center oid := to_regprocedure('public.get_my_privacy_center_v4()');
  v_legacy oid := to_regprocedure('public.export_my_personal_data_v5()');
begin
  return jsonb_build_object(
    'exportRunsReady', v_table is not null,
    'exportRunsRlsReady', coalesce((
      select class.relrowsecurity
      from pg_catalog.pg_class class
      where class.oid = v_table
    ), false),
    'exportRunsImmutable', exists (
      select 1
      from pg_catalog.pg_trigger trigger_row
      where trigger_row.tgrelid = v_table
        and trigger_row.tgname = 'personal_data_export_runs_immutable'
        and not trigger_row.tgisinternal
    ),
    'idempotencyUniqueReady', exists (
      select 1
      from pg_catalog.pg_index index_row
      where index_row.indrelid = v_table
        and index_row.indisunique
        and pg_catalog.pg_get_indexdef(index_row.indexrelid)
          ilike '%user_id, idempotency_key%'
    ),
    'revisionUniqueReady', exists (
      select 1
      from pg_catalog.pg_index index_row
      where index_row.indrelid = v_table
        and index_row.indisunique
        and pg_catalog.pg_get_indexdef(index_row.indexrelid)
          ilike '%user_id, export_revision%'
    ),
    'guardedExportReady', v_guarded is not null,
    'privacyCenterV4Ready', v_center is not null,
    'diagnosticReady', to_regprocedure(
      'public.get_personal_data_export_safety_integrity_v1()'
    ) is not null,
    'authenticatedGuardedExecuteReady', coalesce(
      pg_catalog.has_function_privilege('authenticated', v_guarded, 'EXECUTE'),
      false
    ),
    'anonymousGuardedBlocked', not coalesce(
      pg_catalog.has_function_privilege('anon', v_guarded, 'EXECUTE'),
      false
    ),
    'legacyAuthenticatedBlocked', not coalesce(
      pg_catalog.has_function_privilege('authenticated', v_legacy, 'EXECUTE'),
      false
    ),
    'legacyAnonymousBlocked', not coalesce(
      pg_catalog.has_function_privilege('anon', v_legacy, 'EXECUTE'),
      false
    ),
    'directWritesBlocked',
      not coalesce(pg_catalog.has_table_privilege('authenticated', v_table, 'INSERT'), false)
      and not coalesce(pg_catalog.has_table_privilege('authenticated', v_table, 'UPDATE'), false)
      and not coalesce(pg_catalog.has_table_privilege('authenticated', v_table, 'DELETE'), false),
    'ownReadPolicyReady', exists (
      select 1
      from pg_catalog.pg_policies policy_row
      where policy_row.schemaname = 'public'
        and policy_row.tablename = 'personal_data_export_runs'
        and policy_row.policyname = 'personal_data_export_runs_read_own'
    ),
    'realtimeReady', exists (
      select 1
      from pg_catalog.pg_publication_tables publication_table
      where publication_table.pubname = 'supabase_realtime'
        and publication_table.schemaname = 'public'
        and publication_table.tablename = 'personal_data_export_runs'
    ),
    'sha256FingerprintReady',
      to_regprocedure('public.personal_data_export_fingerprint_v1(jsonb)') is not null
      and pg_catalog.pg_get_functiondef(
        'public.personal_data_export_fingerprint_v1(jsonb)'::regprocedure
      ) ilike '%leghevo_sha256_hex_v1%'
      and v_guarded is not null
      and pg_catalog.pg_get_functiondef(v_guarded)
        ilike '%personal_data_export_fingerprint_v1%',
    'accountLockReady', v_guarded is not null and
      pg_catalog.pg_get_functiondef(v_guarded)
        ilike '%pg_advisory_xact_lock%',
    'sourceExportWrapped', v_guarded is not null and
      pg_catalog.pg_get_functiondef(v_guarded)
        ilike '%export_my_personal_data_v5%',
    'profileCascadeReady', exists (
      select 1
      from pg_catalog.pg_constraint constraint_row
      where constraint_row.conrelid = v_table
        and constraint_row.contype = 'f'
        and constraint_row.confrelid = to_regclass('public.profiles')
        and constraint_row.confdeltype = 'c'
    ),
    'certificateChecksReady', exists (
      select 1
      from pg_catalog.pg_constraint constraint_row
      where constraint_row.conrelid = v_table
        and constraint_row.contype = 'c'
        and pg_catalog.pg_get_constraintdef(constraint_row.oid)
          ilike '%payload_fingerprint%64%'
    ) and exists (
      select 1
      from pg_catalog.pg_constraint constraint_row
      where constraint_row.conrelid = v_table
        and constraint_row.contype = 'c'
        and pg_catalog.pg_get_constraintdef(constraint_row.oid)
          ilike '%jsonb_typeof%result_snapshot%object%'
    )
  );
end;
$$;

revoke all on function public.get_personal_data_export_safety_integrity_v1()
from public, anon, authenticated;

-- Validazione transazionale dettagliata: in caso di anomalia la transazione
-- viene annullata indicando i controlli precisi, senza errori generici.
do $validation$
declare
  v_diagnostic jsonb;
  v_failed text[];
  v_item record;
begin
  v_diagnostic := public.get_personal_data_export_safety_integrity_v1();

  for v_item in
    select entry.key, entry.value
    from jsonb_each_text(v_diagnostic) entry
    where entry.value <> 'true'
    order by entry.key
  loop
    v_failed := array_append(v_failed, v_item.key);
  end loop;

  if coalesce(array_length(v_failed, 1), 0) > 0 then
    raise exception
      'Validazione v0.61.8 non superata. Controlli falsi: %',
      array_to_string(v_failed, '; ');
  end if;
end;
$validation$;

commit;

with diagnostic as (
  select public.get_personal_data_export_safety_integrity_v1() as value
)
select
  (value ->> 'exportRunsReady')::boolean as export_runs_ready,
  (value ->> 'exportRunsRlsReady')::boolean as export_runs_rls_ready,
  (value ->> 'exportRunsImmutable')::boolean as export_runs_immutable,
  (value ->> 'idempotencyUniqueReady')::boolean as idempotency_unique_ready,
  (value ->> 'revisionUniqueReady')::boolean as revision_unique_ready,
  (value ->> 'guardedExportReady')::boolean as guarded_export_ready,
  (value ->> 'privacyCenterV4Ready')::boolean as privacy_center_v4_ready,
  (value ->> 'diagnosticReady')::boolean as diagnostic_ready,
  (value ->> 'authenticatedGuardedExecuteReady')::boolean as authenticated_guarded_execute_ready,
  (value ->> 'anonymousGuardedBlocked')::boolean as anonymous_guarded_blocked,
  (value ->> 'legacyAuthenticatedBlocked')::boolean as legacy_authenticated_blocked,
  (value ->> 'legacyAnonymousBlocked')::boolean as legacy_anonymous_blocked,
  (value ->> 'directWritesBlocked')::boolean as direct_writes_blocked,
  (value ->> 'ownReadPolicyReady')::boolean as own_read_policy_ready,
  (value ->> 'realtimeReady')::boolean as realtime_ready,
  (value ->> 'sha256FingerprintReady')::boolean as sha256_fingerprint_ready,
  (value ->> 'accountLockReady')::boolean as account_lock_ready,
  (value ->> 'sourceExportWrapped')::boolean as source_export_wrapped,
  (value ->> 'profileCascadeReady')::boolean as profile_cascade_ready,
  (value ->> 'certificateChecksReady')::boolean as certificate_checks_ready
from diagnostic;
