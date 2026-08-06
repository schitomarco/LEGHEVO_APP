-- LEGHEVO v0.62.3 · Provider Data Freshness and Coverage Safety
-- Eseguire dopo database/106_provider_sync_safety.sql.
-- La migrazione non modifica voti, partite o risultati sportivi esistenti.

begin;

do $preflight$
declare
  v_missing text[];
begin
  select array_agg(required.item order by required.item)
  into v_missing
  from (
    values
      ('table:public.leagues', to_regclass('public.leagues') is not null),
      ('table:public.matchdays', to_regclass('public.matchdays') is not null),
      ('table:public.fantasy_fixtures', to_regclass('public.fantasy_fixtures') is not null),
      ('table:public.provider_fixtures', to_regclass('public.provider_fixtures') is not null),
      ('table:public.player_match_scores', to_regclass('public.player_match_scores') is not null),
      ('table:public.athletes', to_regclass('public.athletes') is not null),
      ('table:public.athlete_roles', to_regclass('public.athlete_roles') is not null),
      ('table:public.provider_sync_runs', to_regclass('public.provider_sync_runs') is not null),
      ('table:public.provider_sync_run_events', to_regclass('public.provider_sync_run_events') is not null),
      ('function:public.is_league_admin(uuid)', to_regprocedure('public.is_league_admin(uuid)') is not null),
      ('function:public.get_league_provider_sync_health_v1(uuid)', to_regprocedure('public.get_league_provider_sync_health_v1(uuid)') is not null)
  ) as required(item, ready)
  where not required.ready;

  if coalesce(array_length(v_missing, 1), 0) > 0 then
    raise exception
      'Preflight v0.62.3 non superato. Dipendenze mancanti: %',
      array_to_string(v_missing, ', ');
  end if;

  select array_agg(required.item order by required.item)
  into v_missing
  from (
    values
      ('matchdays.provider_fixture_count', exists (
        select 1 from information_schema.columns
        where table_schema = 'public' and table_name = 'matchdays'
          and column_name = 'provider_fixture_count'
      )),
      ('matchdays.provider_final_fixture_count', exists (
        select 1 from information_schema.columns
        where table_schema = 'public' and table_name = 'matchdays'
          and column_name = 'provider_final_fixture_count'
      )),
      ('matchdays.schedule_source', exists (
        select 1 from information_schema.columns
        where table_schema = 'public' and table_name = 'matchdays'
          and column_name = 'schedule_source'
      )),
      ('provider_sync_runs.requested_for', exists (
        select 1 from information_schema.columns
        where table_schema = 'public' and table_name = 'provider_sync_runs'
          and column_name = 'requested_for'
      )),
      ('provider_sync_runs.records_processed', exists (
        select 1 from information_schema.columns
        where table_schema = 'public' and table_name = 'provider_sync_runs'
          and column_name = 'records_processed'
      )),
      ('provider_sync_runs.result_fingerprint', exists (
        select 1 from information_schema.columns
        where table_schema = 'public' and table_name = 'provider_sync_runs'
          and column_name = 'result_fingerprint'
      )),
      ('provider_sync_run_events.event_type', exists (
        select 1 from information_schema.columns
        where table_schema = 'public' and table_name = 'provider_sync_run_events'
          and column_name = 'event_type'
      )),
      ('provider_fixtures.matchday_id', exists (
        select 1 from information_schema.columns
        where table_schema = 'public' and table_name = 'provider_fixtures'
          and column_name = 'matchday_id'
      )),
      ('player_match_scores.provider_fixture_id', exists (
        select 1 from information_schema.columns
        where table_schema = 'public' and table_name = 'player_match_scores'
          and column_name = 'provider_fixture_id'
      ))
  ) as required(item, ready)
  where not required.ready;

  if coalesce(array_length(v_missing, 1), 0) > 0 then
    raise exception
      'Preflight v0.62.3 non superato. Colonne mancanti: %',
      array_to_string(v_missing, ', ');
  end if;
end;
$preflight$;

create table if not exists public.provider_data_quality_snapshots (
  id uuid primary key default gen_random_uuid(),
  run_id uuid not null unique
    references public.provider_sync_runs(id) on delete cascade,
  provider text not null,
  sync_type text not null,
  status text not null check (status in ('healthy', 'attention', 'idle')),
  anomaly_count integer not null default 0 check (anomaly_count >= 0),
  metrics jsonb not null default '{}'::jsonb,
  latest_source_at timestamptz,
  snapshot_fingerprint text not null
    check (char_length(snapshot_fingerprint) = 32),
  created_at timestamptz not null default now()
);

create index if not exists provider_data_quality_snapshots_latest_idx
  on public.provider_data_quality_snapshots (created_at desc);
create index if not exists provider_data_quality_snapshots_action_idx
  on public.provider_data_quality_snapshots
  (provider, sync_type, created_at desc);

alter table public.provider_data_quality_snapshots enable row level security;
alter table public.provider_data_quality_snapshots replica identity full;

revoke all on table public.provider_data_quality_snapshots
from public, anon, authenticated;
grant select on table public.provider_data_quality_snapshots to authenticated;
grant select, insert on table public.provider_data_quality_snapshots to service_role;

drop policy if exists provider_data_quality_snapshots_read_authenticated
on public.provider_data_quality_snapshots;
create policy provider_data_quality_snapshots_read_authenticated
on public.provider_data_quality_snapshots
for select to authenticated
using (true);

create or replace function public.build_provider_data_quality_metrics_v1(
  p_run_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_run public.provider_sync_runs%rowtype;
  v_fixture_id text;
  v_fixture_count integer := 0;
  v_linked_fixture_count integer := 0;
  v_final_fixture_count integer := 0;
  v_live_fixture_count integer := 0;
  v_final_without_goals_count integer := 0;
  v_same_team_count integer := 0;
  v_score_count integer := 0;
  v_final_score_count integer := 0;
  v_invalid_score_count integer := 0;
  v_nonfinal_score_on_final_fixture_count integer := 0;
  v_active_athlete_count integer := 0;
  v_missing_role_count integer := 0;
  v_records_mismatch integer := 0;
  v_anomaly_count integer := 0;
  v_latest_fixture_at timestamptz;
  v_latest_score_at timestamptz;
  v_latest_data_at timestamptz;
  v_status text := 'healthy';
begin
  select run_row.*
  into v_run
  from public.provider_sync_runs run_row
  where run_row.id = p_run_id;

  if not found then
    raise exception 'Run provider non trovato.';
  end if;

  if v_run.status <> 'completed' then
    raise exception 'La qualità può essere certificata solo per un run completato.';
  end if;

  if v_run.sync_type = 'sync-fixtures' then
    select
      count(*)::integer,
      count(*) filter (where fixture.matchday_id is not null)::integer,
      count(*) filter (
        where fixture.status in ('FT', 'AET', 'PEN')
      )::integer,
      count(*) filter (
        where fixture.status in ('1H', 'HT', '2H', 'ET', 'BT', 'P', 'LIVE')
      )::integer,
      count(*) filter (
        where fixture.status in ('FT', 'AET', 'PEN')
          and (fixture.home_goals is null or fixture.away_goals is null)
      )::integer,
      count(*) filter (
        where fixture.home_team_provider_id = fixture.away_team_provider_id
      )::integer,
      max(fixture.updated_at)
    into
      v_fixture_count,
      v_linked_fixture_count,
      v_final_fixture_count,
      v_live_fixture_count,
      v_final_without_goals_count,
      v_same_team_count,
      v_latest_fixture_at
    from public.provider_fixtures fixture
    where fixture.provider = v_run.provider
      and fixture.season = coalesce(v_run.requested_for ->> 'season', fixture.season)
      and (
        not (v_run.requested_for ? 'date')
        or (fixture.kickoff_at at time zone 'UTC')::date
          = (v_run.requested_for ->> 'date')::date
      );

    v_records_mismatch := abs(
      coalesce(v_run.records_processed, 0) - coalesce(v_fixture_count, 0)
    );
    v_anomaly_count :=
      greatest(v_fixture_count - v_linked_fixture_count, 0)
      + v_final_without_goals_count
      + v_same_team_count
      + v_records_mismatch;
    v_latest_data_at := v_latest_fixture_at;
  elsif v_run.sync_type = 'sync-fixture-players' then
    v_fixture_id := v_run.requested_for ->> 'fixtureId';

    select
      count(*)::integer,
      count(*) filter (where score.is_final)::integer,
      count(*) filter (
        where (score.provider_rating is not null
          and (score.provider_rating < 0 or score.provider_rating > 10))
          or (score.fantasy_score is not null
          and (score.fantasy_score < -10 or score.fantasy_score > 30))
      )::integer,
      max(score.updated_at)
    into
      v_score_count,
      v_final_score_count,
      v_invalid_score_count,
      v_latest_score_at
    from public.player_match_scores score
    where score.provider_fixture_id = v_fixture_id;

    select count(*)::integer
    into v_nonfinal_score_on_final_fixture_count
    from public.player_match_scores score
    join public.provider_fixtures fixture
      on fixture.provider = v_run.provider
      and fixture.provider_fixture_id = score.provider_fixture_id
    where score.provider_fixture_id = v_fixture_id
      and fixture.status in ('FT', 'AET', 'PEN')
      and not score.is_final;

    select max(fixture.updated_at)
    into v_latest_fixture_at
    from public.provider_fixtures fixture
    where fixture.provider = v_run.provider
      and fixture.provider_fixture_id = v_fixture_id;

    v_records_mismatch := abs(
      coalesce(v_run.records_processed, 0) - coalesce(v_score_count, 0)
    );
    v_anomaly_count := v_invalid_score_count
      + v_nonfinal_score_on_final_fixture_count
      + v_records_mismatch
      + case when v_latest_fixture_at is null then 1 else 0 end;
    v_latest_data_at := greatest(v_latest_fixture_at, v_latest_score_at);
  elsif v_run.sync_type = 'sync-season-players' then
    select count(*)::integer
    into v_active_athlete_count
    from public.athletes athlete
    where athlete.provider = v_run.provider
      and athlete.active;

    select count(*)::integer
    into v_missing_role_count
    from public.athletes athlete
    where athlete.provider = v_run.provider
      and athlete.active
      and (
        not exists (
          select 1
          from public.athlete_roles role_row
          where role_row.athlete_id = athlete.id
            and role_row.mode::text = 'classic'
        )
        or not exists (
          select 1
          from public.athlete_roles role_row
          where role_row.athlete_id = athlete.id
            and role_row.mode::text = 'mantra'
        )
      );

    select max(athlete.updated_at)
    into v_latest_data_at
    from public.athletes athlete
    where athlete.provider = v_run.provider;

    v_anomaly_count := v_missing_role_count
      + case when coalesce(v_run.records_processed, 0) = 0 then 1 else 0 end;
  else
    v_status := 'idle';
  end if;

  if v_status <> 'idle' and v_anomaly_count > 0 then
    v_status := 'attention';
  end if;

  return jsonb_build_object(
    'provider', v_run.provider,
    'action', v_run.sync_type,
    'status', v_status,
    'anomalyCount', v_anomaly_count,
    'recordsProcessed', coalesce(v_run.records_processed, 0),
    'recordsMismatch', v_records_mismatch,
    'fixtureCount', v_fixture_count,
    'linkedFixtureCount', v_linked_fixture_count,
    'finalFixtureCount', v_final_fixture_count,
    'liveFixtureCount', v_live_fixture_count,
    'finalWithoutGoalsCount', v_final_without_goals_count,
    'sameTeamCount', v_same_team_count,
    'scoreCount', v_score_count,
    'finalScoreCount', v_final_score_count,
    'invalidScoreCount', v_invalid_score_count,
    'nonFinalScoreOnFinalFixtureCount',
      v_nonfinal_score_on_final_fixture_count,
    'activeAthleteCount', v_active_athlete_count,
    'missingRoleCount', v_missing_role_count,
    'latestDataAt', v_latest_data_at
  );
end;
$$;

revoke all on function public.build_provider_data_quality_metrics_v1(uuid)
from public, anon, authenticated;
grant execute on function public.build_provider_data_quality_metrics_v1(uuid)
to service_role;

create or replace function public.record_provider_data_quality_snapshot_v1(
  p_run_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_existing_id uuid;
  v_run public.provider_sync_runs%rowtype;
  v_metrics jsonb;
  v_snapshot_id uuid;
  v_latest_source_at timestamptz;
begin
  select snapshot.id
  into v_existing_id
  from public.provider_data_quality_snapshots snapshot
  where snapshot.run_id = p_run_id;

  if found then
    return v_existing_id;
  end if;

  select run_row.*
  into v_run
  from public.provider_sync_runs run_row
  where run_row.id = p_run_id;

  if not found then
    raise exception 'Run provider non trovato.';
  end if;

  v_metrics := public.build_provider_data_quality_metrics_v1(p_run_id);
  if nullif(v_metrics ->> 'latestDataAt', '') is not null then
    v_latest_source_at := (v_metrics ->> 'latestDataAt')::timestamptz;
  end if;

  insert into public.provider_data_quality_snapshots (
    run_id,
    provider,
    sync_type,
    status,
    anomaly_count,
    metrics,
    latest_source_at,
    snapshot_fingerprint
  ) values (
    p_run_id,
    v_run.provider,
    v_run.sync_type,
    coalesce(v_metrics ->> 'status', 'attention'),
    greatest(coalesce((v_metrics ->> 'anomalyCount')::integer, 0), 0),
    v_metrics,
    v_latest_source_at,
    pg_catalog.md5(
      p_run_id::text || E'\n'
      || coalesce(v_run.result_fingerprint, '') || E'\n'
      || v_metrics::text
    )
  )
  on conflict (run_id) do nothing
  returning id into v_snapshot_id;

  if v_snapshot_id is null then
    select snapshot.id
    into v_snapshot_id
    from public.provider_data_quality_snapshots snapshot
    where snapshot.run_id = p_run_id;
  end if;

  return v_snapshot_id;
end;
$$;

revoke all on function public.record_provider_data_quality_snapshot_v1(uuid)
from public, anon, authenticated;
grant execute on function public.record_provider_data_quality_snapshot_v1(uuid)
to service_role;

create or replace function public.capture_provider_data_quality_snapshot_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.event_type = 'completed' then
    begin
      perform public.record_provider_data_quality_snapshot_v1(new.run_id);
    exception when others then
      -- La sincronizzazione resta conclusa anche se il monitor qualità non
      -- riesce a produrre la fotografia. Il Centro Operativo lo rileverà come
      -- assenza del certificato al controllo successivo.
      null;
    end;
  end if;
  return new;
end;
$$;

revoke all on function public.capture_provider_data_quality_snapshot_v1()
from public, anon, authenticated;

drop trigger if exists provider_sync_quality_snapshot_writer
on public.provider_sync_run_events;
create trigger provider_sync_quality_snapshot_writer
after insert on public.provider_sync_run_events
for each row
execute function public.capture_provider_data_quality_snapshot_v1();

create or replace function public.prevent_provider_data_quality_mutation_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  raise exception 'Registro qualità provider immutabile: modifica diretta non consentita.';
end;
$$;

revoke all on function public.prevent_provider_data_quality_mutation_v1()
from public, anon, authenticated;

drop trigger if exists provider_data_quality_snapshots_immutable
on public.provider_data_quality_snapshots;
create trigger provider_data_quality_snapshots_immutable
before update or delete on public.provider_data_quality_snapshots
for each row
execute function public.prevent_provider_data_quality_mutation_v1();

-- Fotografia non distruttiva dell'ultimo run completato per ciascun flusso.
do $backfill$
declare
  v_run record;
begin
  for v_run in
    select distinct on (run_row.provider, run_row.sync_type)
      run_row.id
    from public.provider_sync_runs run_row
    where run_row.status = 'completed'
    order by
      run_row.provider,
      run_row.sync_type,
      run_row.finished_at desc nulls last,
      run_row.started_at desc
  loop
    begin
      perform public.record_provider_data_quality_snapshot_v1(v_run.id);
    exception when others then
      null;
    end;
  end loop;
end;
$backfill$;

create or replace function public.get_league_provider_data_quality_v1(
  p_league_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_owner_id uuid;
  v_matchday public.matchdays%rowtype;
  v_fixture_count integer := 0;
  v_final_fixture_count integer := 0;
  v_live_fixture_count integer := 0;
  v_score_count integer := 0;
  v_final_score_count integer := 0;
  v_invalid_score_count integer := 0;
  v_final_fixture_without_score_count integer := 0;
  v_schedule_mismatch_count integer := 0;
  v_latest_fixture_at timestamptz;
  v_latest_score_at timestamptz;
  v_stale boolean := false;
  v_status text := 'idle';
  v_anomaly_count integer := 0;
  v_latest_snapshot jsonb;
  v_latest_completed_run_id uuid;
  v_snapshot_missing_count integer := 0;
begin
  if auth.uid() is null then
    raise exception 'Devi effettuare l''accesso.';
  end if;

  select league.owner_id
  into v_owner_id
  from public.leagues league
  where league.id = p_league_id;

  if not found then
    raise exception 'Lega non trovata.';
  end if;

  if v_owner_id <> auth.uid()
    and not public.is_league_admin(p_league_id) then
    raise exception 'Il monitor qualità provider è riservato alla Direzione.';
  end if;

  select matchday.*
  into v_matchday
  from public.matchdays matchday
  where exists (
    select 1
    from public.fantasy_fixtures fixture
    where fixture.league_id = p_league_id
      and fixture.matchday_id = matchday.id
  )
  order by
    case when exists (
      select 1
      from public.fantasy_fixtures fixture
      where fixture.league_id = p_league_id
        and fixture.matchday_id = matchday.id
        and fixture.finalized_at is null
    ) then 0 else 1 end,
    case when matchday.ends_at is null or matchday.ends_at >= now()
      then 0 else 1 end,
    case when exists (
      select 1
      from public.fantasy_fixtures fixture
      where fixture.league_id = p_league_id
        and fixture.matchday_id = matchday.id
        and fixture.finalized_at is null
    ) then matchday.number end asc,
    matchday.number desc
  limit 1;

  select run_row.id
  into v_latest_completed_run_id
  from public.provider_sync_runs run_row
  where run_row.provider = 'api-football'
    and run_row.status = 'completed'
  order by run_row.finished_at desc nulls last, run_row.started_at desc
  limit 1;

  select jsonb_build_object(
    'runId', snapshot.run_id,
    'action', snapshot.sync_type,
    'status', snapshot.status,
    'anomalyCount', snapshot.anomaly_count,
    'latestSourceAt', snapshot.latest_source_at,
    'createdAt', snapshot.created_at
  )
  into v_latest_snapshot
  from public.provider_data_quality_snapshots snapshot
  where snapshot.provider = 'api-football'
  order by snapshot.created_at desc
  limit 1;

  if v_latest_completed_run_id is not null
    and (v_latest_snapshot is null
      or nullif(v_latest_snapshot ->> 'runId', '')::uuid
        is distinct from v_latest_completed_run_id) then
    v_snapshot_missing_count := 1;
  end if;

  if v_matchday.id is not null then
    select
      count(*)::integer,
      count(*) filter (
        where provider_fixture.status in ('FT', 'AET', 'PEN')
      )::integer,
      count(*) filter (
        where provider_fixture.status in (
          '1H', 'HT', '2H', 'ET', 'BT', 'P', 'LIVE'
        )
      )::integer,
      max(provider_fixture.updated_at)
    into
      v_fixture_count,
      v_final_fixture_count,
      v_live_fixture_count,
      v_latest_fixture_at
    from public.provider_fixtures provider_fixture
    where provider_fixture.provider = 'api-football'
      and provider_fixture.matchday_id = v_matchday.id;

    select
      count(*)::integer,
      count(*) filter (where score.is_final)::integer,
      count(*) filter (
        where (score.provider_rating is not null
          and (score.provider_rating < 0 or score.provider_rating > 10))
          or (score.fantasy_score is not null
          and (score.fantasy_score < -10 or score.fantasy_score > 30))
      )::integer,
      max(score.updated_at)
    into
      v_score_count,
      v_final_score_count,
      v_invalid_score_count,
      v_latest_score_at
    from public.player_match_scores score
    where score.matchday_id = v_matchday.id;

    select count(*)::integer
    into v_final_fixture_without_score_count
    from public.provider_fixtures provider_fixture
    where provider_fixture.provider = 'api-football'
      and provider_fixture.matchday_id = v_matchday.id
      and provider_fixture.status in ('FT', 'AET', 'PEN')
      and not exists (
        select 1
        from public.player_match_scores score
        where score.matchday_id = v_matchday.id
          and score.provider_fixture_id = provider_fixture.provider_fixture_id
          and score.is_final
      );

    v_schedule_mismatch_count :=
      case when coalesce(v_matchday.provider_fixture_count, 0)
        <> v_fixture_count then 1 else 0 end
      + case when coalesce(v_matchday.provider_final_fixture_count, 0)
        <> v_final_fixture_count then 1 else 0 end;

    v_stale := (
      v_live_fixture_count > 0
      and (
        v_latest_score_at is null
        or v_latest_score_at < now() - interval '3 minutes'
      )
    ) or (
      v_fixture_count > v_final_fixture_count
      and v_latest_fixture_at is not null
      and v_latest_fixture_at < now() - interval '20 minutes'
    );

    v_anomaly_count := v_invalid_score_count
      + v_final_fixture_without_score_count
      + v_schedule_mismatch_count
      + v_snapshot_missing_count
      + case when v_stale then 1 else 0 end;

    if v_fixture_count = 0 and v_matchday.schedule_source <> 'provider' then
      v_status := 'idle';
    elsif v_anomaly_count > 0
      or coalesce(v_latest_snapshot ->> 'status', 'healthy') = 'attention' then
      v_status := 'attention';
    else
      v_status := 'healthy';
    end if;
  elsif v_latest_snapshot is not null then
    v_status := coalesce(v_latest_snapshot ->> 'status', 'idle');
    v_anomaly_count := greatest(
      coalesce((v_latest_snapshot ->> 'anomalyCount')::integer, 0),
      0
    ) + v_snapshot_missing_count;
    if v_snapshot_missing_count > 0 then
      v_status := 'attention';
    end if;
  end if;

  return jsonb_build_object(
    'protected', true,
    'status', v_status,
    'healthy', v_status <> 'attention',
    'stale', v_stale,
    'anomalyCount', v_anomaly_count,
    'matchdayId', v_matchday.id,
    'matchdayNumber', v_matchday.number,
    'scheduleSource', v_matchday.schedule_source,
    'fixtureCount', v_fixture_count,
    'finalFixtureCount', v_final_fixture_count,
    'liveFixtureCount', v_live_fixture_count,
    'scoreCount', v_score_count,
    'finalScoreCount', v_final_score_count,
    'invalidScoreCount', v_invalid_score_count,
    'finalFixtureWithoutScoreCount', v_final_fixture_without_score_count,
    'scheduleMismatchCount', v_schedule_mismatch_count,
    'snapshotMissingCount', v_snapshot_missing_count,
    'latestFixtureAt', v_latest_fixture_at,
    'latestScoreAt', v_latest_score_at,
    'latestSnapshot', v_latest_snapshot
  );
end;
$$;

revoke all on function public.get_league_provider_data_quality_v1(uuid)
from public, anon, authenticated;
grant execute on function public.get_league_provider_data_quality_v1(uuid)
to authenticated;

create or replace function public.get_league_provider_sync_health_v2(
  p_league_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_sync jsonb;
  v_quality jsonb;
  v_attention boolean;
begin
  v_sync := public.get_league_provider_sync_health_v1(p_league_id);
  v_quality := public.get_league_provider_data_quality_v1(p_league_id);
  v_attention := coalesce(v_sync ->> 'status', 'idle') = 'attention'
    or coalesce(v_quality ->> 'status', 'idle') = 'attention';

  return v_sync || jsonb_build_object(
    'healthy', not v_attention,
    'status', case
      when v_attention then 'attention'
      when coalesce(v_sync ->> 'status', 'idle') = 'idle'
        and coalesce(v_quality ->> 'status', 'idle') = 'idle'
        then 'idle'
      else 'healthy'
    end,
    'dataQuality', v_quality
  );
end;
$$;

revoke all on function public.get_league_provider_sync_health_v2(uuid)
from public, anon, authenticated;
grant execute on function public.get_league_provider_sync_health_v2(uuid)
to authenticated;

do $realtime$
begin
  if exists (
    select 1 from pg_catalog.pg_publication publication
    where publication.pubname = 'supabase_realtime'
  ) and not exists (
    select 1
    from pg_catalog.pg_publication_tables publication_table
    where publication_table.pubname = 'supabase_realtime'
      and publication_table.schemaname = 'public'
      and publication_table.tablename = 'provider_data_quality_snapshots'
  ) then
    alter publication supabase_realtime
      add table public.provider_data_quality_snapshots;
  end if;
end;
$realtime$;

create or replace function public.get_provider_data_freshness_integrity_v1()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'snapshots_table_ready',
      to_regclass('public.provider_data_quality_snapshots') is not null,
    'snapshot_columns_ready',
      (
        select count(*) = 10
        from information_schema.columns column_row
        where column_row.table_schema = 'public'
          and column_row.table_name = 'provider_data_quality_snapshots'
          and column_row.column_name in (
            'id', 'run_id', 'provider', 'sync_type', 'status',
            'anomaly_count', 'metrics', 'latest_source_at',
            'snapshot_fingerprint', 'created_at'
          )
      ),
    'snapshot_indexes_ready',
      to_regclass('public.provider_data_quality_snapshots_latest_idx') is not null
      and to_regclass('public.provider_data_quality_snapshots_action_idx') is not null,
    'metrics_builder_ready',
      to_regprocedure('public.build_provider_data_quality_metrics_v1(uuid)') is not null
      and has_function_privilege(
        'service_role',
        'public.build_provider_data_quality_metrics_v1(uuid)',
        'EXECUTE'
      ),
    'snapshot_recorder_ready',
      to_regprocedure('public.record_provider_data_quality_snapshot_v1(uuid)') is not null
      and has_function_privilege(
        'service_role',
        'public.record_provider_data_quality_snapshot_v1(uuid)',
        'EXECUTE'
      ),
    'snapshot_writer_ready',
      exists (
        select 1 from pg_trigger trigger_row
        where trigger_row.tgname = 'provider_sync_quality_snapshot_writer'
          and trigger_row.tgrelid = 'public.provider_sync_run_events'::regclass
          and not trigger_row.tgisinternal
      ),
    'immutable_function_ready',
      to_regprocedure('public.prevent_provider_data_quality_mutation_v1()') is not null,
    'immutable_trigger_ready',
      exists (
        select 1 from pg_trigger trigger_row
        where trigger_row.tgname = 'provider_data_quality_snapshots_immutable'
          and trigger_row.tgrelid = 'public.provider_data_quality_snapshots'::regclass
          and not trigger_row.tgisinternal
      ),
    'quality_rpc_ready',
      to_regprocedure('public.get_league_provider_data_quality_v1(uuid)') is not null,
    'health_v2_rpc_ready',
      to_regprocedure('public.get_league_provider_sync_health_v2(uuid)') is not null,
    'snapshots_rls_ready',
      coalesce((
        select class_row.relrowsecurity
        from pg_class class_row
        join pg_namespace namespace_row
          on namespace_row.oid = class_row.relnamespace
        where namespace_row.nspname = 'public'
          and class_row.relname = 'provider_data_quality_snapshots'
      ), false)
      and exists (
        select 1
        from pg_policies policy_row
        where policy_row.schemaname = 'public'
          and policy_row.tablename = 'provider_data_quality_snapshots'
          and policy_row.policyname =
            'provider_data_quality_snapshots_read_authenticated'
      ),
    'authenticated_snapshot_read_ready',
      has_table_privilege(
        'authenticated', 'public.provider_data_quality_snapshots', 'SELECT'
      ),
    'anonymous_snapshot_blocked',
      not has_table_privilege(
        'anon', 'public.provider_data_quality_snapshots', 'SELECT'
      ),
    'authenticated_snapshot_writes_blocked',
      not has_table_privilege(
        'authenticated', 'public.provider_data_quality_snapshots', 'INSERT'
      )
      and not has_table_privilege(
        'authenticated', 'public.provider_data_quality_snapshots', 'UPDATE'
      )
      and not has_table_privilege(
        'authenticated', 'public.provider_data_quality_snapshots', 'DELETE'
      ),
    'service_snapshot_insert_ready',
      has_table_privilege(
        'service_role', 'public.provider_data_quality_snapshots', 'INSERT'
      ),
    'authenticated_quality_rpc_ready',
      has_function_privilege(
        'authenticated',
        'public.get_league_provider_data_quality_v1(uuid)',
        'EXECUTE'
      ),
    'authenticated_health_v2_ready',
      has_function_privilege(
        'authenticated',
        'public.get_league_provider_sync_health_v2(uuid)',
        'EXECUTE'
      ),
    'anonymous_quality_rpc_blocked',
      not has_function_privilege(
        'anon',
        'public.get_league_provider_data_quality_v1(uuid)',
        'EXECUTE'
      ),
    'anonymous_health_v2_blocked',
      not has_function_privilege(
        'anon',
        'public.get_league_provider_sync_health_v2(uuid)',
        'EXECUTE'
      ),
    'snapshots_realtime_ready',
      exists (
        select 1
        from pg_catalog.pg_publication_tables publication_table
        where publication_table.pubname = 'supabase_realtime'
          and publication_table.schemaname = 'public'
          and publication_table.tablename = 'provider_data_quality_snapshots'
      )
  )
$$;

revoke all on function public.get_provider_data_freshness_integrity_v1()
from public, anon, authenticated;

do $validate$
declare
  v_checks jsonb;
  v_failed text[];
begin
  v_checks := public.get_provider_data_freshness_integrity_v1();

  select array_agg(check_row.key order by check_row.key)
  into v_failed
  from jsonb_each(v_checks) check_row
  where check_row.value is distinct from 'true'::jsonb;

  if coalesce(array_length(v_failed, 1), 0) > 0 then
    raise exception
      'Validazione v0.62.3 non superata. Controlli falsi: %',
      array_to_string(v_failed, ', ');
  end if;
end;
$validate$;

commit;

-- Diagnostica finale: devono comparire esattamente 20 valori true.
select
  coalesce((public.get_provider_data_freshness_integrity_v1() ->> 'snapshots_table_ready')::boolean, false)
    as snapshots_table_ready,
  coalesce((public.get_provider_data_freshness_integrity_v1() ->> 'snapshot_columns_ready')::boolean, false)
    as snapshot_columns_ready,
  coalesce((public.get_provider_data_freshness_integrity_v1() ->> 'snapshot_indexes_ready')::boolean, false)
    as snapshot_indexes_ready,
  coalesce((public.get_provider_data_freshness_integrity_v1() ->> 'metrics_builder_ready')::boolean, false)
    as metrics_builder_ready,
  coalesce((public.get_provider_data_freshness_integrity_v1() ->> 'snapshot_recorder_ready')::boolean, false)
    as snapshot_recorder_ready,
  coalesce((public.get_provider_data_freshness_integrity_v1() ->> 'snapshot_writer_ready')::boolean, false)
    as snapshot_writer_ready,
  coalesce((public.get_provider_data_freshness_integrity_v1() ->> 'immutable_function_ready')::boolean, false)
    as immutable_function_ready,
  coalesce((public.get_provider_data_freshness_integrity_v1() ->> 'immutable_trigger_ready')::boolean, false)
    as immutable_trigger_ready,
  coalesce((public.get_provider_data_freshness_integrity_v1() ->> 'quality_rpc_ready')::boolean, false)
    as quality_rpc_ready,
  coalesce((public.get_provider_data_freshness_integrity_v1() ->> 'health_v2_rpc_ready')::boolean, false)
    as health_v2_rpc_ready,
  coalesce((public.get_provider_data_freshness_integrity_v1() ->> 'snapshots_rls_ready')::boolean, false)
    as snapshots_rls_ready,
  coalesce((public.get_provider_data_freshness_integrity_v1() ->> 'authenticated_snapshot_read_ready')::boolean, false)
    as authenticated_snapshot_read_ready,
  coalesce((public.get_provider_data_freshness_integrity_v1() ->> 'anonymous_snapshot_blocked')::boolean, false)
    as anonymous_snapshot_blocked,
  coalesce((public.get_provider_data_freshness_integrity_v1() ->> 'authenticated_snapshot_writes_blocked')::boolean, false)
    as authenticated_snapshot_writes_blocked,
  coalesce((public.get_provider_data_freshness_integrity_v1() ->> 'service_snapshot_insert_ready')::boolean, false)
    as service_snapshot_insert_ready,
  coalesce((public.get_provider_data_freshness_integrity_v1() ->> 'authenticated_quality_rpc_ready')::boolean, false)
    as authenticated_quality_rpc_ready,
  coalesce((public.get_provider_data_freshness_integrity_v1() ->> 'authenticated_health_v2_ready')::boolean, false)
    as authenticated_health_v2_ready,
  coalesce((public.get_provider_data_freshness_integrity_v1() ->> 'anonymous_quality_rpc_blocked')::boolean, false)
    as anonymous_quality_rpc_blocked,
  coalesce((public.get_provider_data_freshness_integrity_v1() ->> 'anonymous_health_v2_blocked')::boolean, false)
    as anonymous_health_v2_blocked,
  coalesce((public.get_provider_data_freshness_integrity_v1() ->> 'snapshots_realtime_ready')::boolean, false)
    as snapshots_realtime_ready;
