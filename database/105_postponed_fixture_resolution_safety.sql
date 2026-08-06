-- LEGHEVO v0.62.1 · Gestione protetta di rinvii e sospensioni
-- Migrazione interna: database/105_postponed_fixture_resolution_safety.sql
--
-- Obiettivi:
-- - applicazione e revoca idempotenti del voto d'ufficio;
-- - revisione ottimistica contro operazioni concorrenti;
-- - registro immutabile delle azioni;
-- - continuità con l'arrivo del risultato definitivo del provider;
-- - compatibilità con le RPC storiche;
-- - diagnostica strutturale finale di 20 controlli.

begin;

-- Preflight dettagliato: non esegue modifiche se manca una dipendenza.
do $preflight$
declare
  v_missing text[] := array[]::text[];
  v_expected record;
begin
  for v_expected in
    select *
    from (values
      ('leagues', 'id'),
      ('leagues', 'owner_id'),
      ('leagues', 'status'),
      ('league_members', 'league_id'),
      ('league_members', 'user_id'),
      ('provider_fixtures', 'id'),
      ('provider_fixtures', 'matchday_id'),
      ('provider_fixtures', 'status'),
      ('provider_fixtures', 'home_team_name'),
      ('provider_fixtures', 'away_team_name'),
      ('league_fixture_resolutions', 'id'),
      ('league_fixture_resolutions', 'league_id'),
      ('league_fixture_resolutions', 'provider_fixture_id'),
      ('league_fixture_resolutions', 'political_score'),
      ('league_fixture_resolutions', 'reason'),
      ('league_fixture_resolutions', 'decided_by'),
      ('league_fixture_resolutions', 'decided_at'),
      ('league_fixture_resolutions', 'revoked_by'),
      ('league_fixture_resolutions', 'revoked_at'),
      ('league_fixture_resolutions', 'revocation_reason'),
      ('league_fixture_resolution_events', 'id'),
      ('league_fixture_resolution_events', 'resolution_id'),
      ('league_fixture_resolution_events', 'league_id'),
      ('league_fixture_resolution_events', 'provider_fixture_id'),
      ('league_fixture_resolution_events', 'event_type'),
      ('league_fixture_resolution_events', 'actor_id'),
      ('league_fixture_resolution_events', 'details'),
      ('league_fixture_resolution_events', 'created_at')
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

  if to_regprocedure('public.is_league_member(uuid)') is null then
    v_missing := array_append(v_missing, 'function public.is_league_member(uuid)');
  end if;
  if to_regprocedure('public.is_league_admin(uuid)') is null then
    v_missing := array_append(v_missing, 'function public.is_league_admin(uuid)');
  end if;
  if to_regprocedure('public.get_league_postponement_center(uuid)') is null then
    v_missing := array_append(
      v_missing,
      'function public.get_league_postponement_center(uuid)'
    );
  end if;
  if to_regprocedure(
    'public.apply_league_fixture_political_score_legacy_v1(uuid,uuid,numeric,text)'
  ) is null
  and to_regprocedure(
    'public.apply_league_fixture_political_score(uuid,uuid,numeric,text)'
  ) is null then
    v_missing := array_append(
      v_missing,
      'function public.apply_league_fixture_political_score(uuid,uuid,numeric,text)'
    );
  end if;
  if to_regprocedure(
    'public.revoke_league_fixture_political_score_legacy_v1(uuid,uuid,text)'
  ) is null
  and to_regprocedure(
    'public.revoke_league_fixture_political_score(uuid,uuid,text)'
  ) is null then
    v_missing := array_append(
      v_missing,
      'function public.revoke_league_fixture_political_score(uuid,uuid,text)'
    );
  end if;
  if to_regprocedure(
    'public.refresh_league_after_fixture_resolution(uuid,uuid)'
  ) is null then
    v_missing := array_append(
      v_missing,
      'function public.refresh_league_after_fixture_resolution(uuid,uuid)'
    );
  end if;

  if coalesce(array_length(v_missing, 1), 0) > 0 then
    raise exception
      'Preflight v0.62.1 non superato. Oggetti mancanti: %',
      array_to_string(v_missing, '; ');
  end if;
end;
$preflight$;

alter table public.league_fixture_resolutions
  add column if not exists revision bigint not null default 1,
  add column if not exists state_fingerprint text;

create or replace function public.fixture_resolution_state_fingerprint_v1(
  p_league_id uuid,
  p_provider_fixture_id uuid,
  p_political_score numeric,
  p_reason text,
  p_decided_by uuid,
  p_decided_at timestamptz,
  p_revoked_by uuid,
  p_revoked_at timestamptz,
  p_revocation_reason text,
  p_revision bigint
)
returns text
language sql
immutable
set search_path = ''
as $$
  select pg_catalog.md5(
    coalesce(p_league_id::text, '') || E'\n' ||
    coalesce(p_provider_fixture_id::text, '') || E'\n' ||
    coalesce(round(p_political_score, 2)::text, '') || E'\n' ||
    coalesce(trim(p_reason), '') || E'\n' ||
    coalesce(p_decided_by::text, '') || E'\n' ||
    coalesce(p_decided_at::text, '') || E'\n' ||
    coalesce(p_revoked_by::text, '') || E'\n' ||
    coalesce(p_revoked_at::text, '') || E'\n' ||
    coalesce(trim(p_revocation_reason), '') || E'\n' ||
    coalesce(p_revision, 1)::text
  )
$$;

revoke all on function public.fixture_resolution_state_fingerprint_v1(
  uuid, uuid, numeric, text, uuid, timestamptz, uuid, timestamptz, text, bigint
) from public, anon, authenticated;

update public.league_fixture_resolutions resolution
set state_fingerprint = public.fixture_resolution_state_fingerprint_v1(
  resolution.league_id,
  resolution.provider_fixture_id,
  resolution.political_score,
  resolution.reason,
  resolution.decided_by,
  resolution.decided_at,
  resolution.revoked_by,
  resolution.revoked_at,
  resolution.revocation_reason,
  resolution.revision
)
where resolution.state_fingerprint is null
   or char_length(resolution.state_fingerprint) <> 32;

alter table public.league_fixture_resolutions
  alter column state_fingerprint set not null;

alter table public.league_fixture_resolutions
  drop constraint if exists league_fixture_resolutions_revision_check;
alter table public.league_fixture_resolutions
  add constraint league_fixture_resolutions_revision_check
  check (revision > 0);

alter table public.league_fixture_resolutions
  drop constraint if exists league_fixture_resolutions_fingerprint_check;
alter table public.league_fixture_resolutions
  add constraint league_fixture_resolutions_fingerprint_check
  check (char_length(state_fingerprint) = 32);

create or replace function public.prepare_fixture_resolution_revision_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    new.revision := greatest(coalesce(new.revision, 1), 1);
  elsif row(
    new.political_score,
    new.reason,
    new.revoked_by,
    new.revoked_at,
    new.revocation_reason
  ) is distinct from row(
    old.political_score,
    old.reason,
    old.revoked_by,
    old.revoked_at,
    old.revocation_reason
  ) then
    new.revision := old.revision + 1;
  else
    new.revision := old.revision;
  end if;

  new.state_fingerprint := public.fixture_resolution_state_fingerprint_v1(
    new.league_id,
    new.provider_fixture_id,
    new.political_score,
    new.reason,
    new.decided_by,
    new.decided_at,
    new.revoked_by,
    new.revoked_at,
    new.revocation_reason,
    new.revision
  );

  return new;
end;
$$;

revoke all on function public.prepare_fixture_resolution_revision_v1()
from public, anon, authenticated;

drop trigger if exists fixture_resolution_revision_guard
on public.league_fixture_resolutions;
create trigger fixture_resolution_revision_guard
before insert or update on public.league_fixture_resolutions
for each row execute function public.prepare_fixture_resolution_revision_v1();

create table if not exists public.fixture_resolution_action_runs (
  id uuid primary key,
  league_id uuid not null,
  provider_fixture_id uuid not null,
  resolution_id uuid not null,
  actor_id uuid not null,
  action_type text not null check (action_type in ('apply', 'revoke')),
  idempotency_key uuid not null,
  expected_revision bigint,
  result_revision bigint not null check (result_revision > 0),
  payload_fingerprint text not null check (
    char_length(payload_fingerprint) = 32
  ),
  result_snapshot jsonb not null check (
    jsonb_typeof(result_snapshot) = 'object'
  ),
  created_at timestamptz not null default now(),
  unique (actor_id, idempotency_key)
);

create index if not exists fixture_resolution_action_runs_league_idx
  on public.fixture_resolution_action_runs (league_id, created_at desc);
create index if not exists fixture_resolution_action_runs_resolution_idx
  on public.fixture_resolution_action_runs (resolution_id, created_at desc);

alter table public.fixture_resolution_action_runs enable row level security;
alter table public.fixture_resolution_action_runs replica identity full;
alter table public.league_fixture_resolutions replica identity full;
alter table public.league_fixture_resolution_events replica identity full;

drop policy if exists fixture_resolution_action_runs_read_members
on public.fixture_resolution_action_runs;
create policy fixture_resolution_action_runs_read_members
on public.fixture_resolution_action_runs
for select to authenticated
using (
  public.is_league_member(league_id)
  or public.is_league_admin(league_id)
);

revoke all on table public.fixture_resolution_action_runs
from public, anon, authenticated;
grant select on table public.fixture_resolution_action_runs
to authenticated;

create or replace function public.prevent_fixture_resolution_action_mutation_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  raise exception
    'Decisione su rinvio certificata: modifica o cancellazione diretta non consentita.';
end;
$$;

revoke all on function public.prevent_fixture_resolution_action_mutation_v1()
from public, anon, authenticated;

drop trigger if exists fixture_resolution_action_runs_immutable
on public.fixture_resolution_action_runs;
create trigger fixture_resolution_action_runs_immutable
before update or delete on public.fixture_resolution_action_runs
for each row execute function public.prevent_fixture_resolution_action_mutation_v1();

-- Conserva le implementazioni storiche come componenti interne. La rinomina
-- avviene una sola volta ed è idempotente sulle riesecuzioni della migrazione.
do $legacy$
begin
  if to_regprocedure(
    'public.apply_league_fixture_political_score_legacy_v1(uuid,uuid,numeric,text)'
  ) is null then
    execute
      'alter function public.apply_league_fixture_political_score(uuid,uuid,numeric,text) '
      'rename to apply_league_fixture_political_score_legacy_v1';
  end if;

  if to_regprocedure(
    'public.revoke_league_fixture_political_score_legacy_v1(uuid,uuid,text)'
  ) is null then
    execute
      'alter function public.revoke_league_fixture_political_score(uuid,uuid,text) '
      'rename to revoke_league_fixture_political_score_legacy_v1';
  end if;
end;
$legacy$;

revoke all on function public.apply_league_fixture_political_score_legacy_v1(
  uuid, uuid, numeric, text
) from public, anon, authenticated;
revoke all on function public.revoke_league_fixture_political_score_legacy_v1(
  uuid, uuid, text
) from public, anon, authenticated;

create or replace function public.apply_league_fixture_political_score_guarded_v1(
  p_league_id uuid,
  p_provider_fixture_id uuid,
  p_political_score numeric,
  p_reason text,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid := auth.uid();
  v_payload_fingerprint text;
  v_run public.fixture_resolution_action_runs%rowtype;
  v_league public.leagues%rowtype;
  v_provider_fixture public.provider_fixtures%rowtype;
  v_resolution public.league_fixture_resolutions%rowtype;
  v_resolution_id uuid;
  v_run_id uuid := pg_catalog.gen_random_uuid();
  v_result jsonb;
begin
  if v_actor_id is null then
    raise exception 'Devi effettuare l''accesso.';
  end if;
  if p_idempotency_key is null then
    raise exception 'Identificativo della richiesta mancante.';
  end if;

  v_payload_fingerprint := pg_catalog.md5(
    'apply' || E'\n' ||
    coalesce(p_league_id::text, '') || E'\n' ||
    coalesce(p_provider_fixture_id::text, '') || E'\n' ||
    coalesce(round(p_political_score, 2)::text, '') || E'\n' ||
    trim(coalesce(p_reason, ''))
  );

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'leghevo:postponement:key:' || v_actor_id::text || ':' ||
      p_idempotency_key::text,
      0::bigint
    )
  );
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'leghevo:postponement:fixture:' || p_league_id::text || ':' ||
      p_provider_fixture_id::text,
      0::bigint
    )
  );

  select action_run.*
  into v_run
  from public.fixture_resolution_action_runs action_run
  where action_run.actor_id = v_actor_id
    and action_run.idempotency_key = p_idempotency_key;

  if found then
    if v_run.action_type <> 'apply'
      or v_run.payload_fingerprint <> v_payload_fingerprint then
      raise exception
        'Identificativo già utilizzato per una richiesta differente.';
    end if;
    return v_run.result_snapshot || jsonb_build_object('idempotent', true);
  end if;

  select league.*
  into v_league
  from public.leagues league
  where league.id = p_league_id
  for update;

  if not found then
    raise exception 'Lega non trovata.';
  end if;
  if v_league.owner_id <> v_actor_id then
    raise exception 'Solo il Presidente può assegnare il voto d''ufficio.';
  end if;
  if v_league.status in ('completed', 'archived') then
    raise exception 'La stagione è già conclusa.';
  end if;
  if p_political_score is null
    or p_political_score < 0
    or p_political_score > 10 then
    raise exception 'Il voto d''ufficio deve essere compreso tra 0 e 10.';
  end if;
  if char_length(trim(coalesce(p_reason, ''))) < 10
    or char_length(trim(coalesce(p_reason, ''))) > 280 then
    raise exception 'Inserisci una motivazione da 10 a 280 caratteri.';
  end if;

  select provider_fixture.*
  into v_provider_fixture
  from public.provider_fixtures provider_fixture
  where provider_fixture.id = p_provider_fixture_id
  for update;

  if not found then
    raise exception 'Partita del provider non trovata.';
  end if;
  if v_provider_fixture.status not in (
    'PST', 'SUSP', 'INT', 'CANC', 'ABD', 'TBD'
  ) then
    raise exception 'La partita non risulta rinviata o sospesa.';
  end if;

  select resolution.*
  into v_resolution
  from public.league_fixture_resolutions resolution
  where resolution.league_id = p_league_id
    and resolution.provider_fixture_id = p_provider_fixture_id
    and resolution.revoked_at is null
  for update;

  if found then
    if round(v_resolution.political_score, 2) <> round(p_political_score, 2)
      or trim(v_resolution.reason) <> trim(coalesce(p_reason, '')) then
      raise exception 'Un voto d''ufficio differente è già attivo per questa partita.';
    end if;

    v_result := jsonb_build_object(
      'actionRunId', v_run_id,
      'resolutionId', v_resolution.id,
      'revision', v_resolution.revision,
      'stateFingerprint', v_resolution.state_fingerprint,
      'protected', true,
      'idempotent', true
    );

    insert into public.fixture_resolution_action_runs (
      id,
      league_id,
      provider_fixture_id,
      resolution_id,
      actor_id,
      action_type,
      idempotency_key,
      expected_revision,
      result_revision,
      payload_fingerprint,
      result_snapshot
    ) values (
      v_run_id,
      p_league_id,
      p_provider_fixture_id,
      v_resolution.id,
      v_actor_id,
      'apply',
      p_idempotency_key,
      null,
      v_resolution.revision,
      v_payload_fingerprint,
      v_result
    );

    return v_result;
  end if;

  v_resolution_id := public.apply_league_fixture_political_score_legacy_v1(
    p_league_id,
    p_provider_fixture_id,
    p_political_score,
    p_reason
  );

  select resolution.*
  into strict v_resolution
  from public.league_fixture_resolutions resolution
  where resolution.id = v_resolution_id;

  v_result := jsonb_build_object(
    'actionRunId', v_run_id,
    'resolutionId', v_resolution.id,
    'revision', v_resolution.revision,
    'stateFingerprint', v_resolution.state_fingerprint,
    'protected', true,
    'idempotent', false
  );

  insert into public.fixture_resolution_action_runs (
    id,
    league_id,
    provider_fixture_id,
    resolution_id,
    actor_id,
    action_type,
    idempotency_key,
    expected_revision,
    result_revision,
    payload_fingerprint,
    result_snapshot
  ) values (
    v_run_id,
    p_league_id,
    p_provider_fixture_id,
    v_resolution.id,
    v_actor_id,
    'apply',
    p_idempotency_key,
    null,
    v_resolution.revision,
    v_payload_fingerprint,
    v_result
  );

  return v_result;
end;
$$;

create or replace function public.revoke_league_fixture_political_score_guarded_v1(
  p_league_id uuid,
  p_resolution_id uuid,
  p_reason text,
  p_expected_revision bigint,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid := auth.uid();
  v_payload_fingerprint text;
  v_run public.fixture_resolution_action_runs%rowtype;
  v_league public.leagues%rowtype;
  v_provider_fixture public.provider_fixtures%rowtype;
  v_resolution public.league_fixture_resolutions%rowtype;
  v_run_id uuid := pg_catalog.gen_random_uuid();
  v_result jsonb;
begin
  if v_actor_id is null then
    raise exception 'Devi effettuare l''accesso.';
  end if;
  if p_idempotency_key is null then
    raise exception 'Identificativo della richiesta mancante.';
  end if;

  v_payload_fingerprint := pg_catalog.md5(
    'revoke' || E'\n' ||
    coalesce(p_league_id::text, '') || E'\n' ||
    coalesce(p_resolution_id::text, '') || E'\n' ||
    coalesce(p_expected_revision::text, '') || E'\n' ||
    trim(coalesce(p_reason, ''))
  );

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'leghevo:postponement:key:' || v_actor_id::text || ':' ||
      p_idempotency_key::text,
      0::bigint
    )
  );
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'leghevo:postponement:resolution:' || p_resolution_id::text,
      0::bigint
    )
  );

  select action_run.*
  into v_run
  from public.fixture_resolution_action_runs action_run
  where action_run.actor_id = v_actor_id
    and action_run.idempotency_key = p_idempotency_key;

  if found then
    if v_run.action_type <> 'revoke'
      or v_run.payload_fingerprint <> v_payload_fingerprint then
      raise exception
        'Identificativo già utilizzato per una richiesta differente.';
    end if;
    return v_run.result_snapshot || jsonb_build_object('idempotent', true);
  end if;

  select league.*
  into v_league
  from public.leagues league
  where league.id = p_league_id
  for update;

  if not found then
    raise exception 'Lega non trovata.';
  end if;
  if v_league.owner_id <> v_actor_id then
    raise exception 'Solo il Presidente può revocare il voto d''ufficio.';
  end if;
  if char_length(trim(coalesce(p_reason, ''))) < 3
    or char_length(trim(coalesce(p_reason, ''))) > 280 then
    raise exception 'Inserisci una motivazione da 3 a 280 caratteri.';
  end if;

  select resolution.*
  into v_resolution
  from public.league_fixture_resolutions resolution
  where resolution.id = p_resolution_id
    and resolution.league_id = p_league_id
  for update;

  if not found then
    raise exception 'Voto d''ufficio non trovato.';
  end if;

  if p_expected_revision is not null
    and v_resolution.revision <> p_expected_revision then
    raise exception
      'La decisione è stata aggiornata su un altro dispositivo. Aggiorna e riprova.';
  end if;

  select provider_fixture.*
  into v_provider_fixture
  from public.provider_fixtures provider_fixture
  where provider_fixture.id = v_resolution.provider_fixture_id;

  if not found then
    raise exception 'Partita del provider non trovata.';
  end if;

  if v_resolution.revoked_at is null
    and public.league_matchday_results_are_locked(
      p_league_id,
      v_provider_fixture.matchday_id
    ) then
    raise exception
      'Riapri prima i risultati ufficiali della giornata interessata.';
  end if;

  if v_resolution.revoked_at is not null then
    if v_resolution.revoked_by is distinct from v_actor_id
      or trim(coalesce(v_resolution.revocation_reason, '')) <>
        trim(coalesce(p_reason, '')) then
      raise exception 'Il voto d''ufficio non è più attivo.';
    end if;

    v_result := jsonb_build_object(
      'actionRunId', v_run_id,
      'resolutionId', v_resolution.id,
      'revision', v_resolution.revision,
      'stateFingerprint', v_resolution.state_fingerprint,
      'revokedAt', v_resolution.revoked_at,
      'protected', true,
      'idempotent', true
    );
  else
    perform public.revoke_league_fixture_political_score_legacy_v1(
      p_league_id,
      p_resolution_id,
      p_reason
    );

    select resolution.*
    into strict v_resolution
    from public.league_fixture_resolutions resolution
    where resolution.id = p_resolution_id;

    v_result := jsonb_build_object(
      'actionRunId', v_run_id,
      'resolutionId', v_resolution.id,
      'revision', v_resolution.revision,
      'stateFingerprint', v_resolution.state_fingerprint,
      'revokedAt', v_resolution.revoked_at,
      'protected', true,
      'idempotent', false
    );
  end if;

  insert into public.fixture_resolution_action_runs (
    id,
    league_id,
    provider_fixture_id,
    resolution_id,
    actor_id,
    action_type,
    idempotency_key,
    expected_revision,
    result_revision,
    payload_fingerprint,
    result_snapshot
  ) values (
    v_run_id,
    p_league_id,
    v_resolution.provider_fixture_id,
    v_resolution.id,
    v_actor_id,
    'revoke',
    p_idempotency_key,
    p_expected_revision,
    v_resolution.revision,
    v_payload_fingerprint,
    v_result
  );

  return v_result;
end;
$$;

revoke all on function public.apply_league_fixture_political_score_guarded_v1(
  uuid, uuid, numeric, text, uuid
) from public, anon, authenticated;
grant execute on function public.apply_league_fixture_political_score_guarded_v1(
  uuid, uuid, numeric, text, uuid
) to authenticated;

revoke all on function public.revoke_league_fixture_political_score_guarded_v1(
  uuid, uuid, text, bigint, uuid
) from public, anon, authenticated;
grant execute on function public.revoke_league_fixture_political_score_guarded_v1(
  uuid, uuid, text, bigint, uuid
) to authenticated;

-- Compatibilità con client precedenti: anche le vecchie firme transitano dal
-- percorso protetto. Il riuso dello stesso stato attivo resta idempotente.
create or replace function public.apply_league_fixture_political_score(
  p_league_id uuid,
  p_provider_fixture_id uuid,
  p_political_score numeric,
  p_reason text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_result jsonb;
begin
  v_result := public.apply_league_fixture_political_score_guarded_v1(
    p_league_id,
    p_provider_fixture_id,
    p_political_score,
    p_reason,
    pg_catalog.gen_random_uuid()
  );
  return (v_result ->> 'resolutionId')::uuid;
end;
$$;

create or replace function public.revoke_league_fixture_political_score(
  p_league_id uuid,
  p_resolution_id uuid,
  p_reason text
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_revision bigint;
begin
  select resolution.revision
  into v_revision
  from public.league_fixture_resolutions resolution
  where resolution.id = p_resolution_id
    and resolution.league_id = p_league_id;

  perform public.revoke_league_fixture_political_score_guarded_v1(
    p_league_id,
    p_resolution_id,
    p_reason,
    v_revision,
    pg_catalog.gen_random_uuid()
  );
  return true;
end;
$$;

revoke all on function public.apply_league_fixture_political_score(
  uuid, uuid, numeric, text
) from public, anon, authenticated;
grant execute on function public.apply_league_fixture_political_score(
  uuid, uuid, numeric, text
) to authenticated;

revoke all on function public.revoke_league_fixture_political_score(
  uuid, uuid, text
) from public, anon, authenticated;
grant execute on function public.revoke_league_fixture_political_score(
  uuid, uuid, text
) to authenticated;

create or replace function public.get_league_postponement_resolution_integrity_v1(
  p_league_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_active_count integer := 0;
  v_invalid_resolution_count integer := 0;
  v_action_count integer := 0;
  v_invalid_action_count integer := 0;
  v_duplicate_active_count integer := 0;
begin
  if auth.uid() is null then
    raise exception 'Devi effettuare l''accesso.';
  end if;
  if not public.is_league_member(p_league_id)
    and not public.is_league_admin(p_league_id) then
    raise exception 'Non fai parte di questa lega.';
  end if;

  select
    count(*) filter (where resolution.revoked_at is null)::integer,
    count(*) filter (
      where resolution.revision <= 0
         or resolution.state_fingerprint is null
         or char_length(resolution.state_fingerprint) <> 32
    )::integer
  into v_active_count, v_invalid_resolution_count
  from public.league_fixture_resolutions resolution
  where resolution.league_id = p_league_id;

  select count(*)::integer
  into v_duplicate_active_count
  from (
    select resolution.provider_fixture_id
    from public.league_fixture_resolutions resolution
    where resolution.league_id = p_league_id
      and resolution.revoked_at is null
    group by resolution.provider_fixture_id
    having count(*) > 1
  ) duplicate_row;

  select
    count(*)::integer,
    count(*) filter (
      where action_run.result_revision <= 0
         or char_length(action_run.payload_fingerprint) <> 32
         or jsonb_typeof(action_run.result_snapshot) <> 'object'
    )::integer
  into v_action_count, v_invalid_action_count
  from public.fixture_resolution_action_runs action_run
  where action_run.league_id = p_league_id;

  return jsonb_build_object(
    'healthy',
      v_invalid_resolution_count = 0
      and v_invalid_action_count = 0
      and v_duplicate_active_count = 0,
    'activeResolutionCount', v_active_count,
    'certifiedActionCount', v_action_count,
    'invalidResolutionCount', v_invalid_resolution_count,
    'invalidActionCount', v_invalid_action_count,
    'duplicateActiveCount', v_duplicate_active_count,
    'idempotencyReady', true,
    'revisionReady', true,
    'providerFinalContinuityReady', exists (
      select 1
      from pg_trigger trigger_row
      where trigger_row.tgname = 'provider_fixture_close_political_scores'
        and not trigger_row.tgisinternal
    )
  );
end;
$$;

revoke all on function public.get_league_postponement_resolution_integrity_v1(uuid)
from public, anon, authenticated;
grant execute on function public.get_league_postponement_resolution_integrity_v1(uuid)
to authenticated;

create or replace function public.get_league_postponement_center_v2(
  p_league_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_center jsonb;
  v_issues jsonb := '[]'::jsonb;
  v_action_count integer := 0;
  v_last_certified_at timestamptz;
begin
  v_center := public.get_league_postponement_center(p_league_id);

  select coalesce(
    jsonb_agg(
      case
        when jsonb_typeof(issue.item -> 'resolution') = 'object'
          and resolution.id is not null then
          jsonb_set(
            issue.item,
            '{resolution}',
            (issue.item -> 'resolution') || jsonb_build_object(
              'revision', resolution.revision,
              'stateFingerprint', resolution.state_fingerprint,
              'protected', true
            ),
            true
          )
        else issue.item
      end
      order by issue.ordinality
    ),
    '[]'::jsonb
  )
  into v_issues
  from jsonb_array_elements(
    coalesce(v_center -> 'issues', '[]'::jsonb)
  ) with ordinality as issue(item, ordinality)
  left join public.league_fixture_resolutions resolution
    on resolution.id = nullif(issue.item #>> '{resolution,id}', '')::uuid;

  select count(*)::integer, max(action_run.created_at)
  into v_action_count, v_last_certified_at
  from public.fixture_resolution_action_runs action_run
  where action_run.league_id = p_league_id;

  return (v_center - 'issues') || jsonb_build_object(
    'issues', v_issues,
    'protected', true,
    'idempotencyReady', true,
    'revisionReady', true,
    'certifiedActionCount', coalesce(v_action_count, 0),
    'lastCertifiedAt', v_last_certified_at,
    'integrity', public.get_league_postponement_resolution_integrity_v1(
      p_league_id
    )
  );
end;
$$;

revoke all on function public.get_league_postponement_center_v2(uuid)
from public, anon, authenticated;
grant execute on function public.get_league_postponement_center_v2(uuid)
to authenticated;

-- Pubblicazione Realtime idempotente del nuovo registro.
do $realtime$
begin
  if not exists (
    select 1
    from pg_publication_tables publication_table
    where publication_table.pubname = 'supabase_realtime'
      and publication_table.schemaname = 'public'
      and publication_table.tablename = 'fixture_resolution_action_runs'
  ) then
    alter publication supabase_realtime
      add table public.fixture_resolution_action_runs;
  end if;
end;
$realtime$;

create or replace function public.get_postponement_resolution_schema_readiness_v1()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'resolution_table_ready',
      to_regclass('public.league_fixture_resolutions') is not null,
    'resolution_events_ready',
      to_regclass('public.league_fixture_resolution_events') is not null,
    'revision_column_ready',
      exists (
        select 1 from information_schema.columns column_row
        where column_row.table_schema = 'public'
          and column_row.table_name = 'league_fixture_resolutions'
          and column_row.column_name = 'revision'
      ),
    'fingerprint_column_ready',
      exists (
        select 1 from information_schema.columns column_row
        where column_row.table_schema = 'public'
          and column_row.table_name = 'league_fixture_resolutions'
          and column_row.column_name = 'state_fingerprint'
      ),
    'action_runs_table_ready',
      to_regclass('public.fixture_resolution_action_runs') is not null,
    'action_runs_rls_ready',
      coalesce((
        select class_row.relrowsecurity
        from pg_class class_row
        join pg_namespace namespace_row
          on namespace_row.oid = class_row.relnamespace
        where namespace_row.nspname = 'public'
          and class_row.relname = 'fixture_resolution_action_runs'
      ), false),
    'action_runs_immutable_ready',
      exists (
        select 1 from pg_trigger trigger_row
        where trigger_row.tgname = 'fixture_resolution_action_runs_immutable'
          and not trigger_row.tgisinternal
      ),
    'resolution_revision_trigger_ready',
      exists (
        select 1 from pg_trigger trigger_row
        where trigger_row.tgname = 'fixture_resolution_revision_guard'
          and not trigger_row.tgisinternal
      ),
    'legacy_apply_internal_ready',
      to_regprocedure(
        'public.apply_league_fixture_political_score_legacy_v1(uuid,uuid,numeric,text)'
      ) is not null,
    'legacy_revoke_internal_ready',
      to_regprocedure(
        'public.revoke_league_fixture_political_score_legacy_v1(uuid,uuid,text)'
      ) is not null,
    'guarded_apply_ready',
      to_regprocedure(
        'public.apply_league_fixture_political_score_guarded_v1(uuid,uuid,numeric,text,uuid)'
      ) is not null,
    'guarded_revoke_ready',
      to_regprocedure(
        'public.revoke_league_fixture_political_score_guarded_v1(uuid,uuid,text,bigint,uuid)'
      ) is not null,
    'legacy_apply_routed',
      pg_get_functiondef(to_regprocedure(
        'public.apply_league_fixture_political_score(uuid,uuid,numeric,text)'
      )) ilike '%apply_league_fixture_political_score_guarded_v1%',
    'legacy_revoke_routed',
      pg_get_functiondef(to_regprocedure(
        'public.revoke_league_fixture_political_score(uuid,uuid,text)'
      )) ilike '%revoke_league_fixture_political_score_guarded_v1%',
    'center_v2_ready',
      to_regprocedure('public.get_league_postponement_center_v2(uuid)')
        is not null,
    'league_diagnostic_ready',
      to_regprocedure(
        'public.get_league_postponement_resolution_integrity_v1(uuid)'
      ) is not null,
    'authenticated_guarded_apply_ready',
      has_function_privilege(
        'authenticated',
        'public.apply_league_fixture_political_score_guarded_v1(uuid,uuid,numeric,text,uuid)',
        'EXECUTE'
      ),
    'authenticated_guarded_revoke_ready',
      has_function_privilege(
        'authenticated',
        'public.revoke_league_fixture_political_score_guarded_v1(uuid,uuid,text,bigint,uuid)',
        'EXECUTE'
      ),
    'anonymous_guarded_endpoints_blocked',
      not has_function_privilege(
        'anon',
        'public.apply_league_fixture_political_score_guarded_v1(uuid,uuid,numeric,text,uuid)',
        'EXECUTE'
      )
      and not has_function_privilege(
        'anon',
        'public.revoke_league_fixture_political_score_guarded_v1(uuid,uuid,text,bigint,uuid)',
        'EXECUTE'
      ),
    'action_runs_realtime_ready',
      exists (
        select 1
        from pg_publication_tables publication_table
        where publication_table.pubname = 'supabase_realtime'
          and publication_table.schemaname = 'public'
          and publication_table.tablename = 'fixture_resolution_action_runs'
      )
  )
$$;

revoke all on function public.get_postponement_resolution_schema_readiness_v1()
from public, anon, authenticated;

-- Verifica transazionale: in caso di regressione mostra i nomi dei controlli
-- falsi e annulla integralmente la migrazione.
do $validation$
declare
  v_failed text[];
begin
  select array_agg(check_row.key order by check_row.key)
  into v_failed
  from jsonb_each(
    public.get_postponement_resolution_schema_readiness_v1()
  ) check_row
  where check_row.value <> 'true'::jsonb;

  if coalesce(array_length(v_failed, 1), 0) > 0 then
    raise exception
      'Validazione v0.62.1 non superata. Controlli falsi: %',
      array_to_string(v_failed, '; ');
  end if;
end;
$validation$;

commit;

-- Diagnostica finale: devono risultare 20 valori true.
select
  (public.get_postponement_resolution_schema_readiness_v1()
    ->> 'resolution_table_ready')::boolean
    as resolution_table_ready,
  (public.get_postponement_resolution_schema_readiness_v1()
    ->> 'resolution_events_ready')::boolean
    as resolution_events_ready,
  (public.get_postponement_resolution_schema_readiness_v1()
    ->> 'revision_column_ready')::boolean
    as revision_column_ready,
  (public.get_postponement_resolution_schema_readiness_v1()
    ->> 'fingerprint_column_ready')::boolean
    as fingerprint_column_ready,
  (public.get_postponement_resolution_schema_readiness_v1()
    ->> 'action_runs_table_ready')::boolean
    as action_runs_table_ready,
  (public.get_postponement_resolution_schema_readiness_v1()
    ->> 'action_runs_rls_ready')::boolean
    as action_runs_rls_ready,
  (public.get_postponement_resolution_schema_readiness_v1()
    ->> 'action_runs_immutable_ready')::boolean
    as action_runs_immutable_ready,
  (public.get_postponement_resolution_schema_readiness_v1()
    ->> 'resolution_revision_trigger_ready')::boolean
    as resolution_revision_trigger_ready,
  (public.get_postponement_resolution_schema_readiness_v1()
    ->> 'legacy_apply_internal_ready')::boolean
    as legacy_apply_internal_ready,
  (public.get_postponement_resolution_schema_readiness_v1()
    ->> 'legacy_revoke_internal_ready')::boolean
    as legacy_revoke_internal_ready,
  (public.get_postponement_resolution_schema_readiness_v1()
    ->> 'guarded_apply_ready')::boolean
    as guarded_apply_ready,
  (public.get_postponement_resolution_schema_readiness_v1()
    ->> 'guarded_revoke_ready')::boolean
    as guarded_revoke_ready,
  (public.get_postponement_resolution_schema_readiness_v1()
    ->> 'legacy_apply_routed')::boolean
    as legacy_apply_routed,
  (public.get_postponement_resolution_schema_readiness_v1()
    ->> 'legacy_revoke_routed')::boolean
    as legacy_revoke_routed,
  (public.get_postponement_resolution_schema_readiness_v1()
    ->> 'center_v2_ready')::boolean
    as center_v2_ready,
  (public.get_postponement_resolution_schema_readiness_v1()
    ->> 'league_diagnostic_ready')::boolean
    as league_diagnostic_ready,
  (public.get_postponement_resolution_schema_readiness_v1()
    ->> 'authenticated_guarded_apply_ready')::boolean
    as authenticated_guarded_apply_ready,
  (public.get_postponement_resolution_schema_readiness_v1()
    ->> 'authenticated_guarded_revoke_ready')::boolean
    as authenticated_guarded_revoke_ready,
  (public.get_postponement_resolution_schema_readiness_v1()
    ->> 'anonymous_guarded_endpoints_blocked')::boolean
    as anonymous_guarded_endpoints_blocked,
  (public.get_postponement_resolution_schema_readiness_v1()
    ->> 'action_runs_realtime_ready')::boolean
    as action_runs_realtime_ready;
