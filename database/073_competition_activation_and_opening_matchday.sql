-- LEGHEVO · attivazione certificata e inizializzazione della prima giornata
-- Versione applicativa: 0.58.3
-- Eseguire dopo 072_precompetition_snapshot_and_guarded_start.sql.
-- Script idempotente: può essere eseguito più volte.

begin;

alter table public.leagues
  add column if not exists competition_revision bigint not null default 0,
  add column if not exists current_matchday_id uuid references public.matchdays(id) on delete set null,
  add column if not exists current_matchday_number smallint,
  add column if not exists competition_opening_verified_at timestamptz,
  add column if not exists competition_opening_version smallint;

alter table public.leagues
  drop constraint if exists leagues_competition_revision_check;
alter table public.leagues
  add constraint leagues_competition_revision_check
  check (competition_revision >= 0);

alter table public.leagues
  drop constraint if exists leagues_current_matchday_number_check;
alter table public.leagues
  add constraint leagues_current_matchday_number_check
  check (
    current_matchday_number is null
    or current_matchday_number > 0
  );

alter table public.leagues
  drop constraint if exists leagues_competition_opening_version_check;
alter table public.leagues
  add constraint leagues_competition_opening_version_check
  check (
    competition_opening_version is null
    or competition_opening_version >= 1
  );

create table if not exists public.league_competition_events (
  id uuid primary key default gen_random_uuid(),
  league_id uuid not null references public.leagues(id) on delete cascade,
  event_type text not null check (
    event_type in (
      'competition_started',
      'competition_start_reconciled'
    )
  ),
  actor_id uuid references public.profiles(id) on delete set null,
  revision bigint not null check (revision > 0),
  matchday_id uuid references public.matchdays(id) on delete set null,
  dedupe_key text not null,
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique (league_id, dedupe_key)
);

create index if not exists league_competition_events_league_created_idx
  on public.league_competition_events (league_id, created_at desc);

alter table public.league_competition_events enable row level security;

drop policy if exists league_competition_events_read
on public.league_competition_events;
create policy league_competition_events_read
on public.league_competition_events
for select
to authenticated
using (
  public.is_league_member(league_id)
  or exists (
    select 1
    from public.leagues league
    where league.id = league_competition_events.league_id
      and league.owner_id = auth.uid()
  )
);

-- Le colonne di attivazione non possono essere manipolate con update diretti.
-- Solo la RPC certificata imposta il flag locale della transazione.
create or replace function public.guard_competition_activation_columns()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if (
    new.competition_started_at is distinct from old.competition_started_at
    or new.competition_started_by is distinct from old.competition_started_by
    or new.competition_start_fingerprint is distinct from old.competition_start_fingerprint
    or new.competition_integrity_verified_at is distinct from old.competition_integrity_verified_at
    or new.competition_start_version is distinct from old.competition_start_version
    or new.competition_revision is distinct from old.competition_revision
    or new.current_matchday_id is distinct from old.current_matchday_id
    or new.current_matchday_number is distinct from old.current_matchday_number
    or new.competition_opening_verified_at is distinct from old.competition_opening_verified_at
    or new.competition_opening_version is distinct from old.competition_opening_version
  ) and coalesce(
    current_setting('leghevo.competition_activation', true),
    ''
  ) <> 'allowed' then
    raise exception
      'L''attivazione della competizione può essere modificata soltanto dalla procedura protetta.';
  end if;

  return new;
end;
$$;

drop trigger if exists leagues_competition_activation_guard
on public.leagues;
create trigger leagues_competition_activation_guard
before update on public.leagues
for each row execute function public.guard_competition_activation_columns();

create or replace function public.get_league_competition_lifecycle_v1(
  p_league_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_league public.leagues%rowtype;
  v_first_matchday public.matchdays%rowtype;
  v_first_fixture_count integer := 0;
  v_expected_first_fixture_count integer := 0;
  v_event_count integer := 0;
  v_guard_ready boolean := false;
  v_opening_ready boolean := false;
begin
  if auth.uid() is null then
    raise exception 'Devi effettuare l''accesso.';
  end if;

  if not public.is_league_member(p_league_id)
    and not exists (
      select 1
      from public.leagues league
      where league.id = p_league_id
        and league.owner_id = auth.uid()
    ) then
    raise exception 'Non fai parte di questa lega.';
  end if;

  select league.*
  into v_league
  from public.leagues league
  where league.id = p_league_id;

  if not found then
    raise exception 'Lega non trovata.';
  end if;

  select matchday.*
  into v_first_matchday
  from public.fantasy_fixtures fixture
  join public.matchdays matchday on matchday.id = fixture.matchday_id
  where fixture.league_id = p_league_id
  group by matchday.id
  order by matchday.number, matchday.starts_at, matchday.id
  limit 1;

  if found then
    select count(*)::integer
    into v_first_fixture_count
    from public.fantasy_fixtures fixture
    where fixture.league_id = p_league_id
      and fixture.matchday_id = v_first_matchday.id;
  end if;

  v_expected_first_fixture_count := floor(v_league.team_limit / 2.0)::integer;
  v_opening_ready :=
    v_first_matchday.id is not null
    and v_first_fixture_count = v_expected_first_fixture_count
    and v_first_matchday.number = v_league.calendar_start_matchday
    and (
      v_league.calendar_season is null
      or v_first_matchday.season = v_league.calendar_season
    );

  select count(*)::integer
  into v_event_count
  from public.league_competition_events event_row
  where event_row.league_id = p_league_id;

  select exists (
    select 1
    from pg_catalog.pg_trigger trigger_row
    where not trigger_row.tgisinternal
      and trigger_row.tgname = 'leagues_competition_activation_guard'
  )
  into v_guard_ready;

  return jsonb_build_object(
    'started', v_league.competition_started_at is not null,
    'startedAt', v_league.competition_started_at,
    'startedBy', v_league.competition_started_by,
    'revision', v_league.competition_revision,
    'startVersion', v_league.competition_start_version,
    'openingVersion', v_league.competition_opening_version,
    'openingVerifiedAt', v_league.competition_opening_verified_at,
    'currentMatchdayId', v_league.current_matchday_id,
    'currentMatchdayNumber', v_league.current_matchday_number,
    'openingMatchdayId', v_first_matchday.id,
    'openingMatchdayNumber', v_first_matchday.number,
    'openingStartsAt', v_first_matchday.starts_at,
    'openingLocksAt', v_first_matchday.locks_at,
    'openingFixtureCount', v_first_fixture_count,
    'expectedOpeningFixtureCount', v_expected_first_fixture_count,
    'openingReady', v_opening_ready,
    'activationProtected', v_guard_ready,
    'eventCount', v_event_count
  );
end;
$$;

create or replace function public.start_league_competition_guarded_v2(
  p_league_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_base jsonb;
  v_league public.leagues%rowtype;
  v_first_matchday public.matchdays%rowtype;
  v_first_fixture_count integer;
  v_expected_first_fixture_count integer;
  v_revision bigint;
  v_verified_at timestamptz := now();
  v_event_type text;
begin
  if auth.uid() is null then
    raise exception 'Devi effettuare l''accesso.';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('competition:' || p_league_id::text, 0)
  );

  -- Consente alla funzione v1 già verificata di aggiornare le colonne protette.
  perform set_config('leghevo.competition_activation', 'allowed', true);
  v_base := public.start_league_competition_guarded(p_league_id);

  select league.*
  into v_league
  from public.leagues league
  where league.id = p_league_id
  for update;

  if not found then
    raise exception 'Lega non trovata.';
  end if;

  -- Una seconda pressione restituisce lo stesso esito senza creare revisioni
  -- o eventi duplicati. Le vecchie competizioni prive dei nuovi metadati
  -- proseguono invece con la riconciliazione una tantum.
  if v_league.competition_started_at is not null
    and v_league.competition_opening_verified_at is not null
    and v_league.current_matchday_id is not null
    and v_league.current_matchday_number is not null then
    return v_base || jsonb_build_object(
      'competitionRevision', v_league.competition_revision,
      'currentMatchdayId', v_league.current_matchday_id,
      'currentMatchdayNumber', v_league.current_matchday_number,
      'openingVerifiedAt', v_league.competition_opening_verified_at,
      'openingVersion', v_league.competition_opening_version,
      'activationProtected', true,
      'alreadyInitialized', true
    );
  end if;

  select matchday.*
  into v_first_matchday
  from public.fantasy_fixtures fixture
  join public.matchdays matchday on matchday.id = fixture.matchday_id
  where fixture.league_id = p_league_id
  group by matchday.id
  order by matchday.number, matchday.starts_at, matchday.id
  limit 1;

  if not found then
    raise exception 'Il calendario non contiene una giornata iniziale valida.';
  end if;

  select count(*)::integer
  into v_first_fixture_count
  from public.fantasy_fixtures fixture
  where fixture.league_id = p_league_id
    and fixture.matchday_id = v_first_matchday.id;

  v_expected_first_fixture_count := floor(v_league.team_limit / 2.0)::integer;
  if v_first_fixture_count <> v_expected_first_fixture_count then
    raise exception
      'La prima giornata non contiene il numero corretto di partite.';
  end if;

  if v_first_matchday.number is distinct from v_league.calendar_start_matchday then
    raise exception
      'La prima giornata non coincide con l''inizio configurato del calendario.';
  end if;

  if v_league.calendar_season is not null
    and v_first_matchday.season is distinct from v_league.calendar_season then
    raise exception
      'La stagione della prima giornata non coincide con il calendario.';
  end if;

  v_event_type := case
    when v_league.competition_opening_verified_at is null
      then 'competition_started'
    else 'competition_start_reconciled'
  end;
  v_revision := greatest(v_league.competition_revision, 0) + 1;

  update public.leagues
  set
    competition_revision = v_revision,
    current_matchday_id = v_first_matchday.id,
    current_matchday_number = v_first_matchday.number,
    competition_opening_verified_at = v_verified_at,
    competition_opening_version = 1,
    updated_at = v_verified_at
  where id = p_league_id;

  insert into public.league_competition_events (
    league_id,
    event_type,
    actor_id,
    revision,
    matchday_id,
    dedupe_key,
    payload
  ) values (
    p_league_id,
    v_event_type,
    auth.uid(),
    v_revision,
    v_first_matchday.id,
    'competition-opening:v1',
    jsonb_build_object(
      'startedAt', v_league.competition_started_at,
      'matchdayNumber', v_first_matchday.number,
      'matchdayStartsAt', v_first_matchday.starts_at,
      'matchdayLocksAt', v_first_matchday.locks_at,
      'fixtureCount', v_first_fixture_count,
      'openingVersion', 1
    )
  )
  on conflict (league_id, dedupe_key) do update
  set
    actor_id = excluded.actor_id,
    revision = excluded.revision,
    matchday_id = excluded.matchday_id,
    payload = excluded.payload,
    created_at = now();

  return v_base || jsonb_build_object(
    'competitionRevision', v_revision,
    'currentMatchdayId', v_first_matchday.id,
    'currentMatchdayNumber', v_first_matchday.number,
    'openingVerifiedAt', v_verified_at,
    'openingVersion', 1,
    'openingFixtureCount', v_first_fixture_count,
    'activationProtected', true
  );
end;
$$;

create or replace function public.get_league_management_state_v9(
  p_league_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_state jsonb;
  v_lifecycle jsonb;
  v_checks jsonb;
begin
  v_state := public.get_league_management_state_v8(p_league_id);
  v_lifecycle := public.get_league_competition_lifecycle_v1(p_league_id);
  v_checks := coalesce(v_state -> 'checks', '{}'::jsonb);

  return v_state || jsonb_build_object(
    'competitionLifecycle', v_lifecycle,
    'checks', v_checks || jsonb_build_object(
      'competitionActivationReady',
        coalesce((v_lifecycle ->> 'openingReady')::boolean, false)
        and coalesce((v_lifecycle ->> 'activationProtected')::boolean, false)
    )
  );
end;
$$;

revoke all on table public.league_competition_events
from public, anon;
revoke insert, update, delete on table public.league_competition_events
from authenticated;
grant select on table public.league_competition_events
to authenticated;

revoke all on function public.guard_competition_activation_columns()
from public, anon, authenticated;
revoke all on function public.get_league_competition_lifecycle_v1(uuid)
from public, anon;
revoke all on function public.start_league_competition_guarded_v2(uuid)
from public, anon;
revoke all on function public.get_league_management_state_v9(uuid)
from public, anon;
revoke all on function public.start_league_competition_guarded(uuid)
from public, anon, authenticated;

grant execute on function public.get_league_competition_lifecycle_v1(uuid)
to authenticated;
grant execute on function public.start_league_competition_guarded_v2(uuid)
to authenticated;
grant execute on function public.get_league_management_state_v9(uuid)
to authenticated;

commit;

-- Controllo finale: attesi 20 valori true.
select
  (
    select count(*) = 5
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'leagues'
      and column_name in (
        'competition_revision',
        'current_matchday_id',
        'current_matchday_number',
        'competition_opening_verified_at',
        'competition_opening_version'
      )
  ) as competition_lifecycle_columns_ready,
  to_regclass('public.league_competition_events') is not null
    as competition_events_table_ready,
  (
    select relrowsecurity
    from pg_catalog.pg_class
    where oid = 'public.league_competition_events'::regclass
  ) as competition_events_rls_ready,
  (
    select count(*) = 1
    from pg_catalog.pg_policies
    where schemaname = 'public'
      and tablename = 'league_competition_events'
      and policyname = 'league_competition_events_read'
  ) as competition_events_read_policy_ready,
  to_regprocedure('public.guard_competition_activation_columns()') is not null
    as activation_guard_function_ready,
  (
    select count(*) = 1
    from pg_catalog.pg_trigger trigger_row
    where not trigger_row.tgisinternal
      and trigger_row.tgname = 'leagues_competition_activation_guard'
  ) as activation_guard_trigger_ready,
  to_regprocedure(
    'public.get_league_competition_lifecycle_v1(uuid)'
  ) is not null as lifecycle_diagnostic_ready,
  to_regprocedure(
    'public.start_league_competition_guarded_v2(uuid)'
  ) is not null as guarded_start_v2_ready,
  to_regprocedure(
    'public.get_league_management_state_v9(uuid)'
  ) is not null as management_state_v9_ready,
  has_function_privilege(
    'authenticated',
    'public.get_league_competition_lifecycle_v1(uuid)',
    'EXECUTE'
  ) as authenticated_lifecycle_access_ready,
  has_function_privilege(
    'authenticated',
    'public.start_league_competition_guarded_v2(uuid)',
    'EXECUTE'
  ) as authenticated_guarded_start_v2_access_ready,
  has_function_privilege(
    'authenticated',
    'public.get_league_management_state_v9(uuid)',
    'EXECUTE'
  ) as authenticated_management_v9_access_ready,
  not has_function_privilege(
    'authenticated',
    'public.start_league_competition_guarded(uuid)',
    'EXECUTE'
  ) as legacy_guarded_start_blocked,
  has_table_privilege(
    'authenticated',
    'public.league_competition_events',
    'SELECT'
  ) as authenticated_competition_events_read_ready,
  not has_table_privilege(
    'authenticated',
    'public.league_competition_events',
    'INSERT'
  ) as authenticated_competition_events_insert_blocked,
  coalesce(
    pg_get_functiondef(
      to_regprocedure('public.start_league_competition_guarded_v2(uuid)')
    ) ilike '%pg_advisory_xact_lock%',
    false
  ) as activation_advisory_lock_ready,
  coalesce(
    pg_get_functiondef(
      to_regprocedure('public.start_league_competition_guarded_v2(uuid)')
    ) ilike '%current_matchday_id%',
    false
  ) as opening_matchday_initialization_ready,
  coalesce(
    pg_get_functiondef(
      to_regprocedure('public.start_league_competition_guarded_v2(uuid)')
    ) ilike '%on conflict (league_id, dedupe_key)%',
    false
  ) as activation_event_idempotency_ready,
  coalesce(
    pg_get_functiondef(
      to_regprocedure('public.get_league_competition_lifecycle_v1(uuid)')
    ) ilike '%expectedOpeningFixtureCount%',
    false
  ) as opening_fixture_diagnostic_ready,
  coalesce(
    pg_get_functiondef(
      to_regprocedure('public.get_league_management_state_v9(uuid)')
    ) ilike '%competitionActivationReady%',
    false
  ) as management_activation_check_ready;
