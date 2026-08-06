-- LEGHEVO · giornate reali, scadenze formazione e stato provider
-- Eseguire nel SQL Editor di Supabase dopo 030.

alter table public.matchdays
  add column if not exists schedule_source text not null default 'estimated',
  add column if not exists schedule_synced_at timestamptz,
  add column if not exists provider_fixture_count smallint not null default 0,
  add column if not exists provider_final_fixture_count smallint not null default 0;

alter table public.matchdays
  drop constraint if exists matchdays_schedule_source_check;

alter table public.matchdays
  add constraint matchdays_schedule_source_check
  check (schedule_source in ('estimated', 'provider'));

alter table public.matchdays
  drop constraint if exists matchdays_provider_fixture_count_check;

alter table public.matchdays
  add constraint matchdays_provider_fixture_count_check
  check (provider_fixture_count between 0 and 30);

alter table public.matchdays
  drop constraint if exists matchdays_provider_final_fixture_count_check;

alter table public.matchdays
  add constraint matchdays_provider_final_fixture_count_check
  check (
    provider_final_fixture_count between 0 and provider_fixture_count
  );

comment on column public.matchdays.schedule_source is
  'provider quando date e scadenze derivano dalle partite reali; estimated durante il fallback.';

comment on column public.matchdays.locks_at is
  'Scadenza formazione: coincide con il primo calcio di inizio reale della giornata.';

create or replace function public.refresh_matchday_schedule_from_provider(
  p_matchday_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_fixture_count integer;
  v_final_fixture_count integer;
  v_first_kickoff timestamptz;
  v_last_kickoff timestamptz;
begin
  if p_matchday_id is null then
    return false;
  end if;

  select
    count(*)::integer,
    count(*) filter (
      where fixture.status in ('FT', 'AET', 'PEN')
    )::integer,
    min(fixture.kickoff_at),
    max(fixture.kickoff_at)
  into
    v_fixture_count,
    v_final_fixture_count,
    v_first_kickoff,
    v_last_kickoff
  from public.provider_fixtures fixture
  where fixture.matchday_id = p_matchday_id;

  if v_fixture_count = 0 then
    update public.matchdays
    set
      schedule_source = 'estimated',
      schedule_synced_at = null,
      provider_fixture_count = 0,
      provider_final_fixture_count = 0
    where id = p_matchday_id;

    return found;
  end if;

  update public.matchdays
  set
    starts_at = v_first_kickoff,
    locks_at = v_first_kickoff,
    ends_at = v_last_kickoff + interval '3 hours',
    schedule_source = 'provider',
    schedule_synced_at = now(),
    provider_fixture_count = least(v_fixture_count, 30)::smallint,
    provider_final_fixture_count =
      least(v_final_fixture_count, v_fixture_count, 30)::smallint
  where id = p_matchday_id;

  return found;
end;
$$;

revoke all on function public.refresh_matchday_schedule_from_provider(uuid)
from public, anon, authenticated;

create or replace function public.refresh_schedule_after_provider_fixture()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    perform public.refresh_matchday_schedule_from_provider(old.matchday_id);
    return old;
  end if;

  if tg_op = 'UPDATE'
    and old.matchday_id is distinct from new.matchday_id then
    perform public.refresh_matchday_schedule_from_provider(old.matchday_id);
  end if;

  perform public.refresh_matchday_schedule_from_provider(new.matchday_id);
  return new;
end;
$$;

revoke all on function public.refresh_schedule_after_provider_fixture()
from public, anon, authenticated;

drop trigger if exists provider_fixtures_refresh_matchday_schedule
on public.provider_fixtures;

create trigger provider_fixtures_refresh_matchday_schedule
after insert or update of matchday_id, kickoff_at, status or delete
on public.provider_fixtures
for each row execute function
  public.refresh_schedule_after_provider_fixture();

do $$
declare
  v_matchday_id uuid;
begin
  for v_matchday_id in
    select distinct fixture.matchday_id
    from public.provider_fixtures fixture
    where fixture.matchday_id is not null
  loop
    perform public.refresh_matchday_schedule_from_provider(v_matchday_id);
  end loop;
end;
$$;

create or replace function public.get_league_schedule_health(
  p_league_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_matchday_count integer;
  v_provider_aligned integer;
  v_estimated integer;
  v_last_sync timestamptz;
  v_next_matchday jsonb;
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

  if not exists (
    select 1
    from public.leagues league
    where league.id = p_league_id
  ) then
    raise exception 'Lega non trovata.';
  end if;

  select
    count(*)::integer,
    count(*) filter (
      where schedule.schedule_source = 'provider'
    )::integer,
    count(*) filter (
      where schedule.schedule_source <> 'provider'
    )::integer,
    max(schedule.schedule_synced_at)
  into
    v_matchday_count,
    v_provider_aligned,
    v_estimated,
    v_last_sync
  from (
    select distinct
      matchday.id,
      matchday.schedule_source,
      matchday.schedule_synced_at
    from public.fantasy_fixtures fixture
    join public.matchdays matchday
      on matchday.id = fixture.matchday_id
    where fixture.league_id = p_league_id
  ) schedule;

  select jsonb_build_object(
    'id', next_matchday.id,
    'number', next_matchday.number,
    'startsAt', next_matchday.starts_at,
    'locksAt', next_matchday.locks_at,
    'endsAt', next_matchday.ends_at,
    'scheduleSource', next_matchday.schedule_source,
    'providerFixtureCount', next_matchday.provider_fixture_count,
    'providerFinalFixtureCount',
      next_matchday.provider_final_fixture_count
  )
  into v_next_matchday
  from (
    select distinct
      matchday.id,
      matchday.number,
      matchday.starts_at,
      matchday.locks_at,
      matchday.ends_at,
      matchday.schedule_source,
      matchday.provider_fixture_count,
      matchday.provider_final_fixture_count
    from public.fantasy_fixtures fixture
    join public.matchdays matchday
      on matchday.id = fixture.matchday_id
    where fixture.league_id = p_league_id
      and coalesce(
        matchday.ends_at,
        matchday.starts_at + interval '4 days'
      ) >= now()
    order by matchday.starts_at, matchday.number
    limit 1
  ) next_matchday;

  return jsonb_build_object(
    'matchdayCount', coalesce(v_matchday_count, 0),
    'providerAlignedMatchdays', coalesce(v_provider_aligned, 0),
    'estimatedMatchdays', coalesce(v_estimated, 0),
    'lastScheduleSyncAt', v_last_sync,
    'nextMatchday', v_next_matchday
  );
end;
$$;

revoke all on function public.get_league_schedule_health(uuid)
from public, anon, authenticated;

grant execute on function public.get_league_schedule_health(uuid)
to authenticated;

do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'matchdays'
  ) then
    alter publication supabase_realtime
      add table public.matchdays;
  end if;
end;
$$;

select
  exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'matchdays'
      and column_name = 'schedule_source'
  ) as schedule_source_ready,
  exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'matchdays'
      and column_name = 'schedule_synced_at'
  ) as schedule_sync_ready,
  exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'matchdays'
      and column_name = 'provider_fixture_count'
  ) as provider_count_ready,
  exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'matchdays'
      and column_name = 'provider_final_fixture_count'
  ) as provider_final_count_ready,
  to_regprocedure(
    'public.refresh_matchday_schedule_from_provider(uuid)'
  ) is not null as schedule_refresh_ready,
  to_regprocedure(
    'public.refresh_schedule_after_provider_fixture()'
  ) is not null as schedule_trigger_function_ready,
  to_regprocedure(
    'public.get_league_schedule_health(uuid)'
  ) is not null as schedule_health_ready,
  exists (
    select 1
    from pg_trigger
    where tgname = 'provider_fixtures_refresh_matchday_schedule'
      and not tgisinternal
  ) as schedule_trigger_ready,
  not has_function_privilege(
    'authenticated',
    'public.refresh_matchday_schedule_from_provider(uuid)',
    'EXECUTE'
  ) and not has_function_privilege(
    'anon',
    'public.refresh_matchday_schedule_from_provider(uuid)',
    'EXECUTE'
  ) as internal_refresh_protected,
  has_function_privilege(
    'authenticated',
    'public.get_league_schedule_health(uuid)',
    'EXECUTE'
  ) as schedule_health_access_ready,
  exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'matchdays'
  ) as schedule_realtime_ready;
