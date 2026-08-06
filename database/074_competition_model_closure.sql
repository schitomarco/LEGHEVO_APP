-- LEGHEVO · chiusura del modello competizione e calendario immutabile
-- Versione applicativa: 0.59.0
-- Eseguire dopo 073_competition_activation_and_opening_matchday.sql.
-- Script idempotente: può essere eseguito più volte.

begin;

alter table public.leagues
  add column if not exists competition_model_closed_at timestamptz,
  add column if not exists competition_model_version smallint,
  add column if not exists competition_calendar_fingerprint text,
  add column if not exists competition_structure_verified_at timestamptz;

alter table public.leagues
  drop constraint if exists leagues_competition_model_version_check;
alter table public.leagues
  add constraint leagues_competition_model_version_check
  check (
    competition_model_version is null
    or competition_model_version >= 1
  );

-- Impronta deterministica del calendario ufficiale. Non contiene risultati:
-- i punteggi possono quindi evolvere senza alterare la struttura sportiva.
create or replace function public.compute_league_calendar_fingerprint(
  p_league_id uuid
)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_fingerprint text;
begin
  select md5(
    jsonb_build_object(
      'league', jsonb_build_object(
        'id', league.id,
        'teamLimit', league.team_limit,
        'season', league.calendar_season,
        'startMatchday', league.calendar_start_matchday,
        'returnLeg', league.calendar_return_leg,
        'drawSeed', league.calendar_draw_seed,
        'expectedFixtures', league.calendar_expected_fixture_count,
        'expectedMatchdays', league.calendar_expected_matchday_count
      ),
      'matchdays', coalesce((
        select jsonb_agg(
          jsonb_build_object(
            'id', matchday_row.id,
            'competitionCode', matchday_row.competition_code,
            'season', matchday_row.season,
            'number', matchday_row.number
          )
          order by
            matchday_row.number,
            matchday_row.id
        )
        from (
          select distinct
            matchday.id,
            matchday.competition_code,
            matchday.season,
            matchday.number
          from public.fantasy_fixtures fixture
          join public.matchdays matchday
            on matchday.id = fixture.matchday_id
          where fixture.league_id = league.id
        ) matchday_row
      ), '[]'::jsonb),
      'fixtures', coalesce((
        select jsonb_agg(
          jsonb_build_object(
            'id', fixture.id,
            'matchdayId', fixture.matchday_id,
            'homeTeamId', fixture.home_team_id,
            'awayTeamId', fixture.away_team_id
          )
          order by
            fixture.matchday_id,
            fixture.home_team_id,
            fixture.away_team_id,
            fixture.id
        )
        from public.fantasy_fixtures fixture
        where fixture.league_id = league.id
      ), '[]'::jsonb)
    )::text
  )
  into v_fingerprint
  from public.leagues league
  where league.id = p_league_id;

  if v_fingerprint is null then
    raise exception 'Lega non trovata.';
  end if;

  return v_fingerprint;
end;
$$;

-- Dopo l'avvio, i parametri che definiscono la competizione non possono
-- cambiare tramite update diretti. Restano consentiti risultati, regolamento
-- versionato, trasferimento della presidenza e chiusura della stagione.
create or replace function public.guard_started_competition_league_structure()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.competition_started_at is not null
    and (
      new.team_limit is distinct from old.team_limit
      or new.starting_credits is distinct from old.starting_credits
      or new.roster_size is distinct from old.roster_size
      or new.mode is distinct from old.mode
      or new.calendar_season is distinct from old.calendar_season
      or new.calendar_start_matchday is distinct from old.calendar_start_matchday
      or new.calendar_return_leg is distinct from old.calendar_return_leg
      or new.calendar_generated_at is distinct from old.calendar_generated_at
      or new.calendar_draw_seed is distinct from old.calendar_draw_seed
      or new.calendar_roster_fingerprint is distinct from old.calendar_roster_fingerprint
      or new.calendar_expected_fixture_count is distinct from old.calendar_expected_fixture_count
      or new.calendar_expected_matchday_count is distinct from old.calendar_expected_matchday_count
      or new.calendar_preflight_version is distinct from old.calendar_preflight_version
      or new.calendar_snapshot_locked_at is distinct from old.calendar_snapshot_locked_at
    )
    and coalesce(
      current_setting('leghevo.competition_lifecycle', true),
      ''
    ) <> 'allowed' then
    raise exception
      'La struttura della competizione è definitiva dopo il fischio d''inizio.';
  end if;

  if (
    new.competition_model_closed_at is distinct from old.competition_model_closed_at
    or new.competition_model_version is distinct from old.competition_model_version
    or new.competition_calendar_fingerprint is distinct from old.competition_calendar_fingerprint
    or new.competition_structure_verified_at is distinct from old.competition_structure_verified_at
  ) and coalesce(
    current_setting('leghevo.competition_lifecycle', true),
    ''
  ) <> 'allowed' then
    raise exception
      'La chiusura del modello competizione può essere modificata soltanto dalla procedura protetta.';
  end if;

  return new;
end;
$$;

drop trigger if exists leagues_started_competition_structure_guard
on public.leagues;
create trigger leagues_started_competition_structure_guard
before update on public.leagues
for each row execute function public.guard_started_competition_league_structure();

-- I risultati delle partite restano aggiornabili. Sono invece bloccati
-- inserimenti, cancellazioni e cambi di giornata/avversari dopo l'avvio.
create or replace function public.guard_started_competition_fixture_structure()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_league_id uuid;
  v_started_at timestamptz;
begin
  if tg_op = 'DELETE' then
    v_league_id := old.league_id;
  else
    v_league_id := new.league_id;
  end if;

  select league.competition_started_at
  into v_started_at
  from public.leagues league
  where league.id = v_league_id;

  if v_started_at is null then
    if tg_op = 'DELETE' then
      return old;
    end if;
    return new;
  end if;

  if coalesce(
    current_setting('leghevo.competition_lifecycle', true),
    ''
  ) = 'allowed' then
    if tg_op = 'DELETE' then
      return old;
    end if;
    return new;
  end if;

  if tg_op = 'INSERT' or tg_op = 'DELETE' then
    raise exception
      'Il calendario è definitivo: non puoi aggiungere o rimuovere partite.';
  end if;

  if new.league_id is distinct from old.league_id
    or new.matchday_id is distinct from old.matchday_id
    or new.home_team_id is distinct from old.home_team_id
    or new.away_team_id is distinct from old.away_team_id then
    raise exception
      'Giornata e avversari sono definitivi dopo l''avvio della competizione.';
  end if;

  return new;
end;
$$;

drop trigger if exists fantasy_fixtures_started_structure_guard
on public.fantasy_fixtures;
create trigger fantasy_fixtures_started_structure_guard
before insert or update or delete on public.fantasy_fixtures
for each row execute function public.guard_started_competition_fixture_structure();

alter table public.league_competition_events
  drop constraint if exists league_competition_events_event_type_check;
alter table public.league_competition_events
  add constraint league_competition_events_event_type_check
  check (
    event_type in (
      'competition_started',
      'competition_start_reconciled',
      'competition_model_closed',
      'competition_model_reconciled'
    )
  );

create or replace function public.get_league_competition_integrity_v1(
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
  v_fixture_count integer := 0;
  v_matchday_count integer := 0;
  v_team_matchday_issue_count integer := 0;
  v_current_matchday_valid boolean := false;
  v_fixture_guard_ready boolean := false;
  v_league_guard_ready boolean := false;
  v_fingerprint text;
  v_fingerprint_stable boolean := false;
  v_counts_ready boolean := false;
  v_model_closed boolean := false;
  v_healthy boolean := false;
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

  select
    count(*)::integer,
    count(distinct fixture.matchday_id)::integer
  into
    v_fixture_count,
    v_matchday_count
  from public.fantasy_fixtures fixture
  where fixture.league_id = p_league_id;

  select count(*)::integer
  into v_team_matchday_issue_count
  from (
    select
      fixture.matchday_id,
      team_id
    from public.fantasy_fixtures fixture
    cross join lateral (
      values (fixture.home_team_id), (fixture.away_team_id)
    ) team_ref(team_id)
    where fixture.league_id = p_league_id
    group by fixture.matchday_id, team_id
    having count(*) <> 1
  ) issue;

  v_current_matchday_valid :=
    v_league.current_matchday_id is not null
    and exists (
      select 1
      from public.fantasy_fixtures fixture
      where fixture.league_id = p_league_id
        and fixture.matchday_id = v_league.current_matchday_id
    );

  select exists (
    select 1
    from pg_catalog.pg_trigger trigger_row
    where not trigger_row.tgisinternal
      and trigger_row.tgname = 'fantasy_fixtures_started_structure_guard'
  ) into v_fixture_guard_ready;

  select exists (
    select 1
    from pg_catalog.pg_trigger trigger_row
    where not trigger_row.tgisinternal
      and trigger_row.tgname = 'leagues_started_competition_structure_guard'
  ) into v_league_guard_ready;

  v_fingerprint := public.compute_league_calendar_fingerprint(p_league_id);
  v_fingerprint_stable :=
    v_league.competition_started_at is null
    or (
      v_league.competition_calendar_fingerprint is not null
      and v_league.competition_calendar_fingerprint = v_fingerprint
    );

  v_counts_ready :=
    coalesce(v_league.calendar_expected_fixture_count, v_fixture_count) = v_fixture_count
    and coalesce(v_league.calendar_expected_matchday_count, v_matchday_count) = v_matchday_count
    and v_team_matchday_issue_count = 0;

  v_model_closed :=
    v_league.competition_model_closed_at is not null
    and coalesce(v_league.competition_model_version, 0) >= 1
    and v_league.competition_structure_verified_at is not null
    and v_league.competition_calendar_fingerprint is not null;

  v_healthy :=
    v_fixture_guard_ready
    and v_league_guard_ready
    and (
      v_league.competition_started_at is null
      or (
        v_model_closed
        and v_fingerprint_stable
        and v_counts_ready
        and v_current_matchday_valid
      )
    );

  return jsonb_build_object(
    'healthy', v_healthy,
    'started', v_league.competition_started_at is not null,
    'modelClosed', v_model_closed,
    'modelClosedAt', v_league.competition_model_closed_at,
    'modelVersion', v_league.competition_model_version,
    'structureVerifiedAt', v_league.competition_structure_verified_at,
    'fixtureCount', v_fixture_count,
    'expectedFixtureCount', v_league.calendar_expected_fixture_count,
    'matchdayCount', v_matchday_count,
    'expectedMatchdayCount', v_league.calendar_expected_matchday_count,
    'teamMatchdayIssueCount', v_team_matchday_issue_count,
    'currentMatchdayValid', v_current_matchday_valid,
    'fixtureStructureProtected', v_fixture_guard_ready,
    'leagueStructureProtected', v_league_guard_ready,
    'calendarFingerprint', v_fingerprint,
    'storedCalendarFingerprint', v_league.competition_calendar_fingerprint,
    'calendarFingerprintStable', v_fingerprint_stable,
    'calendarCountsReady', v_counts_ready
  );
end;
$$;

create or replace function public.start_league_competition_guarded_v3(
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
  v_fingerprint text;
  v_verified_at timestamptz := now();
  v_event_type text;
begin
  if auth.uid() is null then
    raise exception 'Devi effettuare l''accesso.';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('competition:' || p_league_id::text, 0)
  );

  perform set_config('leghevo.competition_activation', 'allowed', true);
  perform set_config('leghevo.competition_lifecycle', 'allowed', true);

  v_base := public.start_league_competition_guarded_v2(p_league_id);

  select league.*
  into v_league
  from public.leagues league
  where league.id = p_league_id
  for update;

  if not found then
    raise exception 'Lega non trovata.';
  end if;

  if v_league.current_matchday_id is null
    or not exists (
      select 1
      from public.fantasy_fixtures fixture
      where fixture.league_id = p_league_id
        and fixture.matchday_id = v_league.current_matchday_id
    ) then
    raise exception
      'La giornata corrente non appartiene al calendario della lega.';
  end if;

  v_fingerprint := public.compute_league_calendar_fingerprint(p_league_id);

  if v_league.competition_model_closed_at is not null then
    if v_league.competition_calendar_fingerprint is distinct from v_fingerprint then
      raise exception
        'Il calendario non coincide con l''impronta certificata della competizione.';
    end if;

    return v_base || jsonb_build_object(
      'competitionModelClosed', true,
      'competitionModelVersion', v_league.competition_model_version,
      'competitionModelClosedAt', v_league.competition_model_closed_at,
      'competitionStructureVerifiedAt', v_league.competition_structure_verified_at,
      'calendarFingerprintStable', true,
      'alreadyClosed', true
    );
  end if;

  v_event_type := case
    when v_league.competition_structure_verified_at is null
      then 'competition_model_closed'
    else 'competition_model_reconciled'
  end;

  update public.leagues
  set
    competition_model_closed_at = v_verified_at,
    competition_model_version = 1,
    competition_calendar_fingerprint = v_fingerprint,
    competition_structure_verified_at = v_verified_at,
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
    greatest(v_league.competition_revision, 1),
    v_league.current_matchday_id,
    'competition-model:v1',
    jsonb_build_object(
      'modelVersion', 1,
      'fixtureCount', v_league.calendar_expected_fixture_count,
      'matchdayCount', v_league.calendar_expected_matchday_count,
      'calendarFingerprint', v_fingerprint,
      'currentMatchdayNumber', v_league.current_matchday_number
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
    'competitionModelClosed', true,
    'competitionModelVersion', 1,
    'competitionModelClosedAt', v_verified_at,
    'competitionStructureVerifiedAt', v_verified_at,
    'calendarFingerprintStable', true
  );
end;
$$;

create or replace function public.get_league_competition_lifecycle_v2(
  p_league_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_lifecycle jsonb;
  v_integrity jsonb;
begin
  v_lifecycle := public.get_league_competition_lifecycle_v1(p_league_id);
  v_integrity := public.get_league_competition_integrity_v1(p_league_id);

  return v_lifecycle || jsonb_build_object(
    'modelClosed', coalesce((v_integrity ->> 'modelClosed')::boolean, false),
    'modelClosedAt', v_integrity ->> 'modelClosedAt',
    'modelVersion', coalesce((v_integrity ->> 'modelVersion')::integer, 0),
    'structureVerifiedAt', v_integrity ->> 'structureVerifiedAt',
    'fixtureStructureProtected', coalesce(
      (v_integrity ->> 'fixtureStructureProtected')::boolean,
      false
    ),
    'leagueStructureProtected', coalesce(
      (v_integrity ->> 'leagueStructureProtected')::boolean,
      false
    ),
    'calendarFingerprintStable', coalesce(
      (v_integrity ->> 'calendarFingerprintStable')::boolean,
      false
    ),
    'calendarCountsReady', coalesce(
      (v_integrity ->> 'calendarCountsReady')::boolean,
      false
    ),
    'integrityHealthy', coalesce((v_integrity ->> 'healthy')::boolean, false),
    'integrity', v_integrity
  );
end;
$$;

create or replace function public.get_league_management_state_v10(
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
  v_state := public.get_league_management_state_v9(p_league_id);
  v_lifecycle := public.get_league_competition_lifecycle_v2(p_league_id);
  v_checks := coalesce(v_state -> 'checks', '{}'::jsonb);

  return v_state || jsonb_build_object(
    'competitionLifecycle', v_lifecycle,
    'checks', v_checks || jsonb_build_object(
      'competitionModelClosed',
        coalesce((v_lifecycle ->> 'integrityHealthy')::boolean, false)
    )
  );
end;
$$;

revoke all on function public.compute_league_calendar_fingerprint(uuid)
from public, anon, authenticated;
revoke all on function public.guard_started_competition_league_structure()
from public, anon, authenticated;
revoke all on function public.guard_started_competition_fixture_structure()
from public, anon, authenticated;
revoke all on function public.get_league_competition_integrity_v1(uuid)
from public, anon;
revoke all on function public.start_league_competition_guarded_v3(uuid)
from public, anon;
revoke all on function public.get_league_competition_lifecycle_v2(uuid)
from public, anon;
revoke all on function public.get_league_management_state_v10(uuid)
from public, anon;
revoke all on function public.start_league_competition_guarded_v2(uuid)
from public, anon, authenticated;

grant execute on function public.get_league_competition_integrity_v1(uuid)
to authenticated;
grant execute on function public.start_league_competition_guarded_v3(uuid)
to authenticated;
grant execute on function public.get_league_competition_lifecycle_v2(uuid)
to authenticated;
grant execute on function public.get_league_management_state_v10(uuid)
to authenticated;

commit;

-- Controllo finale: attesi 20 valori true.
select
  (
    select count(*) = 4
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'leagues'
      and column_name in (
        'competition_model_closed_at',
        'competition_model_version',
        'competition_calendar_fingerprint',
        'competition_structure_verified_at'
      )
  ) as competition_model_columns_ready,
  to_regprocedure(
    'public.compute_league_calendar_fingerprint(uuid)'
  ) is not null as calendar_fingerprint_function_ready,
  to_regprocedure(
    'public.guard_started_competition_league_structure()'
  ) is not null as league_structure_guard_function_ready,
  to_regprocedure(
    'public.guard_started_competition_fixture_structure()'
  ) is not null as fixture_structure_guard_function_ready,
  (
    select count(*) = 1
    from pg_catalog.pg_trigger trigger_row
    where not trigger_row.tgisinternal
      and trigger_row.tgname = 'leagues_started_competition_structure_guard'
  ) as league_structure_guard_trigger_ready,
  (
    select count(*) = 1
    from pg_catalog.pg_trigger trigger_row
    where not trigger_row.tgisinternal
      and trigger_row.tgname = 'fantasy_fixtures_started_structure_guard'
  ) as fixture_structure_guard_trigger_ready,
  to_regprocedure(
    'public.get_league_competition_integrity_v1(uuid)'
  ) is not null as competition_integrity_diagnostic_ready,
  to_regprocedure(
    'public.start_league_competition_guarded_v3(uuid)'
  ) is not null as guarded_start_v3_ready,
  to_regprocedure(
    'public.get_league_competition_lifecycle_v2(uuid)'
  ) is not null as lifecycle_v2_ready,
  to_regprocedure(
    'public.get_league_management_state_v10(uuid)'
  ) is not null as management_state_v10_ready,
  has_function_privilege(
    'authenticated',
    'public.get_league_competition_integrity_v1(uuid)',
    'EXECUTE'
  ) as authenticated_integrity_access_ready,
  has_function_privilege(
    'authenticated',
    'public.start_league_competition_guarded_v3(uuid)',
    'EXECUTE'
  ) as authenticated_guarded_start_v3_access_ready,
  has_function_privilege(
    'authenticated',
    'public.get_league_competition_lifecycle_v2(uuid)',
    'EXECUTE'
  ) as authenticated_lifecycle_v2_access_ready,
  has_function_privilege(
    'authenticated',
    'public.get_league_management_state_v10(uuid)',
    'EXECUTE'
  ) as authenticated_management_v10_access_ready,
  not has_function_privilege(
    'authenticated',
    'public.start_league_competition_guarded_v2(uuid)',
    'EXECUTE'
  ) as legacy_guarded_start_v2_blocked,
  coalesce(
    pg_get_functiondef(
      to_regprocedure('public.start_league_competition_guarded_v3(uuid)')
    ) ilike '%pg_advisory_xact_lock%',
    false
  ) as competition_closure_lock_ready,
  coalesce(
    pg_get_functiondef(
      to_regprocedure('public.start_league_competition_guarded_v3(uuid)')
    ) ilike '%competition_calendar_fingerprint%',
    false
  ) as competition_fingerprint_seal_ready,
  coalesce(
    pg_get_functiondef(
      to_regprocedure('public.guard_started_competition_fixture_structure()')
    ) ilike '%home_points%',
    false
  ) = false as fixture_results_remain_mutable_ready,
  coalesce(
    pg_get_functiondef(
      to_regprocedure('public.get_league_competition_integrity_v1(uuid)')
    ) ilike '%calendarFingerprintStable%',
    false
  ) as competition_integrity_fingerprint_ready,
  coalesce(
    pg_get_functiondef(
      to_regprocedure('public.get_league_management_state_v10(uuid)')
    ) ilike '%competitionModelClosed%',
    false
  ) as management_model_closure_check_ready;
