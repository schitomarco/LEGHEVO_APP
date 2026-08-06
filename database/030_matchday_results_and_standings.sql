-- LEGHEVO · risultati di giornata, chiusura ufficiale e classifica
-- Eseguire nel SQL Editor di Supabase dopo 029.

alter table public.fantasy_fixtures
  add column if not exists home_counted_players smallint not null default 0,
  add column if not exists away_counted_players smallint not null default 0,
  add column if not exists home_ready boolean not null default false,
  add column if not exists away_ready boolean not null default false,
  add column if not exists finalized_by uuid,
  add column if not exists reopened_at timestamptz,
  add column if not exists reopened_by uuid;

alter table public.fantasy_fixtures
  drop constraint if exists fantasy_fixtures_home_counted_players_check;

alter table public.fantasy_fixtures
  add constraint fantasy_fixtures_home_counted_players_check
  check (home_counted_players between 0 and 11);

alter table public.fantasy_fixtures
  drop constraint if exists fantasy_fixtures_away_counted_players_check;

alter table public.fantasy_fixtures
  add constraint fantasy_fixtures_away_counted_players_check
  check (away_counted_players between 0 and 11);

create or replace function public.refresh_matchday_results_internal(
  p_matchday_id uuid
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_fixture record;
  v_home_points numeric;
  v_away_points numeric;
  v_home_ready boolean;
  v_away_ready boolean;
  v_home_counted integer;
  v_away_counted integer;
  v_home_bonus numeric;
  v_updated integer := 0;
begin
  for v_fixture in
    select
      fixture.id,
      fixture.home_team_id,
      fixture.away_team_id,
      fixture.finalized_at,
      league.scoring_rules
    from public.fantasy_fixtures fixture
    join public.leagues league on league.id = fixture.league_id
    where fixture.matchday_id = p_matchday_id
    for update of fixture
  loop
    -- Un risultato ufficiale resta immutabile finché il Presidente
    -- non riapre esplicitamente la giornata.
    if v_fixture.finalized_at is not null then
      continue;
    end if;

    select
      calculation.total_points,
      calculation.is_ready,
      calculation.counted_players
    into
      v_home_points,
      v_home_ready,
      v_home_counted
    from public.calculate_team_matchday_points(
      v_fixture.home_team_id,
      p_matchday_id
    ) calculation;

    select
      calculation.total_points,
      calculation.is_ready,
      calculation.counted_players
    into
      v_away_points,
      v_away_ready,
      v_away_counted
    from public.calculate_team_matchday_points(
      v_fixture.away_team_id,
      p_matchday_id
    ) calculation;

    v_home_bonus :=
      coalesce((v_fixture.scoring_rules ->> 'home_bonus')::numeric, 0);

    if v_home_points is not null then
      v_home_points := round(v_home_points + v_home_bonus, 2);
    end if;

    update public.fantasy_fixtures
    set
      home_points = v_home_points,
      away_points = v_away_points,
      home_goals = public.fantasy_goals_from_points(
        v_home_points,
        v_fixture.scoring_rules
      ),
      away_goals = public.fantasy_goals_from_points(
        v_away_points,
        v_fixture.scoring_rules
      ),
      home_counted_players = least(
        greatest(coalesce(v_home_counted, 0), 0),
        11
      ),
      away_counted_players = least(
        greatest(coalesce(v_away_counted, 0), 0),
        11
      ),
      home_ready = coalesce(v_home_ready, false),
      away_ready = coalesce(v_away_ready, false)
    where id = v_fixture.id;

    v_updated := v_updated + 1;
  end loop;

  return v_updated;
end;
$$;

revoke all on function public.refresh_matchday_results_internal(uuid)
from public, anon, authenticated;

create or replace function public.recalculate_league_matchday(
  p_league_id uuid,
  p_matchday_id uuid
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_owner_id uuid;
  v_fixture_count integer;
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

  if v_owner_id <> auth.uid() then
    raise exception 'Solo il Presidente può ricalcolare la giornata.';
  end if;

  select count(*)::integer
  into v_fixture_count
  from public.fantasy_fixtures fixture
  where fixture.league_id = p_league_id
    and fixture.matchday_id = p_matchday_id;

  if v_fixture_count = 0 then
    raise exception 'Giornata non trovata nel calendario della lega.';
  end if;

  perform public.refresh_matchday_results_internal(p_matchday_id);
  return v_fixture_count;
end;
$$;

revoke all on function public.recalculate_league_matchday(uuid, uuid)
from public, anon, authenticated;

grant execute on function public.recalculate_league_matchday(uuid, uuid)
to authenticated;

create or replace function public.get_league_results_center(
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
  v_matchdays jsonb;
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

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', summary.id,
        'number', summary.number,
        'startsAt', summary.starts_at,
        'endsAt', summary.ends_at,
        'fixtureCount', summary.fixture_count,
        'readyCount', summary.ready_count,
        'officialCount', summary.official_count,
        'status',
          case
            when summary.official_count = summary.fixture_count
              then 'official'
            when summary.starts_at > now()
              then 'upcoming'
            when now() <= coalesce(
              summary.ends_at,
              summary.starts_at + interval '4 days'
            )
              then 'live'
            when summary.ready_count = summary.fixture_count
              then 'ready'
            else 'pending'
          end,
        'canFinalize',
          v_league.owner_id = auth.uid()
          and v_league.competition_started_at is not null
          and now() >= coalesce(
            summary.ends_at,
            summary.starts_at + interval '4 days'
          )
          and summary.ready_count = summary.fixture_count
          and summary.official_count = 0,
        'canReopen',
          v_league.owner_id = auth.uid()
          and summary.official_count = summary.fixture_count,
        'fixtures',
          coalesce(
            (
              select jsonb_agg(
                jsonb_build_object(
                  'id', fixture.id,
                  'homeTeamId', fixture.home_team_id,
                  'homeTeamName', home_team.name,
                  'awayTeamId', fixture.away_team_id,
                  'awayTeamName', away_team.name,
                  'homePoints', fixture.home_points,
                  'awayPoints', fixture.away_points,
                  'homeGoals', fixture.home_goals,
                  'awayGoals', fixture.away_goals,
                  'homeCountedPlayers', fixture.home_counted_players,
                  'awayCountedPlayers', fixture.away_counted_players,
                  'homeReady', fixture.home_ready,
                  'awayReady', fixture.away_ready,
                  'finalizedAt', fixture.finalized_at,
                  'status',
                    case
                      when fixture.finalized_at is not null
                        then 'official'
                      when fixture.home_ready and fixture.away_ready
                        then 'ready'
                      when fixture.home_points is not null
                        or fixture.away_points is not null
                        then 'provisional'
                      else 'waiting'
                    end
                )
                order by home_team.name, away_team.name
              )
              from public.fantasy_fixtures fixture
              join public.fantasy_teams home_team
                on home_team.id = fixture.home_team_id
              join public.fantasy_teams away_team
                on away_team.id = fixture.away_team_id
              where fixture.league_id = p_league_id
                and fixture.matchday_id = summary.id
            ),
            '[]'::jsonb
          )
      )
      order by summary.number
    ),
    '[]'::jsonb
  )
  into v_matchdays
  from (
    select
      matchday.id,
      matchday.number,
      matchday.starts_at,
      matchday.ends_at,
      count(fixture.id)::integer as fixture_count,
      count(*) filter (
        where fixture.home_ready
          and fixture.away_ready
          and fixture.home_points is not null
          and fixture.away_points is not null
          and fixture.home_goals is not null
          and fixture.away_goals is not null
      )::integer as ready_count,
      count(*) filter (
        where fixture.finalized_at is not null
      )::integer as official_count
    from public.fantasy_fixtures fixture
    join public.matchdays matchday
      on matchday.id = fixture.matchday_id
    where fixture.league_id = p_league_id
    group by
      matchday.id,
      matchday.number,
      matchday.starts_at,
      matchday.ends_at
  ) summary;

  return jsonb_build_object(
    'leagueId', v_league.id,
    'leagueName', v_league.name,
    'isOwner', v_league.owner_id = auth.uid(),
    'competitionStartedAt', v_league.competition_started_at,
    'goalThreshold',
      coalesce((v_league.scoring_rules ->> 'goal_threshold')::numeric, 66),
    'goalStep',
      coalesce((v_league.scoring_rules ->> 'goal_step')::numeric, 6),
    'matchdays', v_matchdays
  );
end;
$$;

create or replace function public.finalize_league_matchday(
  p_league_id uuid,
  p_matchday_id uuid
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_league public.leagues%rowtype;
  v_matchday public.matchdays%rowtype;
  v_fixture_count integer;
  v_ready_count integer;
  v_updated integer;
begin
  if auth.uid() is null then
    raise exception 'Devi effettuare l''accesso.';
  end if;

  select league.*
  into v_league
  from public.leagues league
  where league.id = p_league_id
  for update;

  if not found then
    raise exception 'Lega non trovata.';
  end if;

  if v_league.owner_id <> auth.uid() then
    raise exception 'Solo il Presidente può ufficializzare la giornata.';
  end if;

  if v_league.competition_started_at is null then
    raise exception 'Avvia la competizione prima di chiudere una giornata.';
  end if;

  select matchday.*
  into v_matchday
  from public.matchdays matchday
  where matchday.id = p_matchday_id;

  if not found then
    raise exception 'Giornata non trovata.';
  end if;

  if now() < coalesce(
    v_matchday.ends_at,
    v_matchday.starts_at + interval '4 days'
  ) then
    raise exception 'La giornata reale non è ancora terminata.';
  end if;

  perform public.refresh_matchday_results_internal(p_matchday_id);

  select
    count(*)::integer,
    count(*) filter (
      where fixture.home_ready
        and fixture.away_ready
        and fixture.home_points is not null
        and fixture.away_points is not null
        and fixture.home_goals is not null
        and fixture.away_goals is not null
    )::integer
  into v_fixture_count, v_ready_count
  from public.fantasy_fixtures fixture
  where fixture.league_id = p_league_id
    and fixture.matchday_id = p_matchday_id;

  if v_fixture_count = 0 then
    raise exception 'Giornata non trovata nel calendario della lega.';
  end if;

  if v_ready_count <> v_fixture_count then
    raise exception
      'Mancano ancora voti definitivi: % partite pronte su %.',
      v_ready_count,
      v_fixture_count;
  end if;

  update public.fantasy_fixtures
  set
    finalized_at = coalesce(finalized_at, now()),
    finalized_by = coalesce(finalized_by, auth.uid())
  where league_id = p_league_id
    and matchday_id = p_matchday_id
    and finalized_at is null;

  get diagnostics v_updated = row_count;
  return v_updated;
end;
$$;

create or replace function public.reopen_league_matchday(
  p_league_id uuid,
  p_matchday_id uuid
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_league public.leagues%rowtype;
  v_matchday_number integer;
  v_member_user_id uuid;
  v_reopen_token uuid := gen_random_uuid();
  v_updated integer;
begin
  if auth.uid() is null then
    raise exception 'Devi effettuare l''accesso.';
  end if;

  select league.*
  into v_league
  from public.leagues league
  where league.id = p_league_id
  for update;

  if not found then
    raise exception 'Lega non trovata.';
  end if;

  if v_league.owner_id <> auth.uid() then
    raise exception 'Solo il Presidente può riaprire la giornata.';
  end if;

  select matchday.number
  into v_matchday_number
  from public.matchdays matchday
  where matchday.id = p_matchday_id;

  if not found then
    raise exception 'Giornata non trovata.';
  end if;

  update public.fantasy_fixtures
  set
    finalized_at = null,
    finalized_by = null,
    reopened_at = now(),
    reopened_by = auth.uid()
  where league_id = p_league_id
    and matchday_id = p_matchday_id
    and finalized_at is not null;

  get diagnostics v_updated = row_count;

  if v_updated = 0 then
    raise exception 'La giornata non è ancora ufficiale.';
  end if;

  perform public.refresh_matchday_results_internal(p_matchday_id);

  for v_member_user_id in
    select member.user_id
    from public.league_members member
    where member.league_id = p_league_id
  loop
    perform public.create_user_notification(
      v_member_user_id,
      p_league_id,
      'result',
      'Giornata riaperta',
      'I risultati della giornata '
        || v_matchday_number
        || ' sono nuovamente in verifica.',
      'standings',
      jsonb_build_object(
        'event', 'matchday_reopened',
        'matchday_id', p_matchday_id,
        'matchday_number', v_matchday_number
      ),
      'results:reopened:'
        || p_matchday_id::text
        || ':'
        || v_reopen_token::text
        || ':'
        || v_member_user_id::text
    );
  end loop;

  return v_updated;
end;
$$;

create or replace function public.notify_final_fantasy_result()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_home public.fantasy_teams%rowtype;
  v_away public.fantasy_teams%rowtype;
  v_matchday_number integer;
  v_result text;
begin
  if new.finalized_at is null or old.finalized_at is not null then
    return new;
  end if;

  select team.* into v_home
  from public.fantasy_teams team
  where team.id = new.home_team_id;

  select team.* into v_away
  from public.fantasy_teams team
  where team.id = new.away_team_id;

  select matchday.number
  into v_matchday_number
  from public.matchdays matchday
  where matchday.id = new.matchday_id;

  v_result := v_home.name || ' ' || coalesce(new.home_goals, 0)
    || '–' || coalesce(new.away_goals, 0) || ' ' || v_away.name;

  perform public.create_user_notification(
    v_home.manager_id,
    new.league_id,
    'result',
    'Risultato ufficiale · Giornata ' || v_matchday_number,
    v_result || '. Classifica aggiornata.',
    'standings',
    jsonb_build_object(
      'fixture_id', new.id,
      'matchday_id', new.matchday_id
    ),
    'result:' || new.id::text || ':' || v_home.manager_id::text
  );

  perform public.create_user_notification(
    v_away.manager_id,
    new.league_id,
    'result',
    'Risultato ufficiale · Giornata ' || v_matchday_number,
    v_result || '. Classifica aggiornata.',
    'standings',
    jsonb_build_object(
      'fixture_id', new.id,
      'matchday_id', new.matchday_id
    ),
    'result:' || new.id::text || ':' || v_away.manager_id::text
  );

  return new;
end;
$$;

revoke all on function public.get_league_results_center(uuid)
from public, anon, authenticated;

revoke all on function public.finalize_league_matchday(uuid, uuid)
from public, anon, authenticated;

revoke all on function public.reopen_league_matchday(uuid, uuid)
from public, anon, authenticated;

revoke all on function public.notify_final_fantasy_result()
from public, anon, authenticated;

grant execute on function public.get_league_results_center(uuid)
to authenticated;

grant execute on function public.finalize_league_matchday(uuid, uuid)
to authenticated;

grant execute on function public.reopen_league_matchday(uuid, uuid)
to authenticated;

update public.fantasy_fixtures
set
  home_counted_players = case
    when home_points is null then 0
    else 11
  end,
  away_counted_players = case
    when away_points is null then 0
    else 11
  end,
  home_ready = home_points is not null
    and home_goals is not null,
  away_ready = away_points is not null
    and away_goals is not null
where finalized_at is not null;

do $$
declare
  v_matchday_id uuid;
begin
  for v_matchday_id in
    select distinct fixture.matchday_id
    from public.fantasy_fixtures fixture
    where fixture.finalized_at is null
  loop
    perform public.refresh_matchday_results_internal(v_matchday_id);
  end loop;
end;
$$;

select
  (
    select count(*) = 7
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'fantasy_fixtures'
      and column_name in (
        'home_counted_players',
        'away_counted_players',
        'home_ready',
        'away_ready',
        'finalized_by',
        'reopened_at',
        'reopened_by'
      )
  ) as fixture_readiness_columns_ready,
  to_regprocedure(
    'public.get_league_results_center(uuid)'
  ) is not null as results_center_ready,
  to_regprocedure(
    'public.refresh_matchday_results_internal(uuid)'
  ) is not null as protected_refresh_ready,
  to_regprocedure(
    'public.finalize_league_matchday(uuid,uuid)'
  ) is not null as finalize_ready,
  to_regprocedure(
    'public.reopen_league_matchday(uuid,uuid)'
  ) is not null as reopen_ready,
  has_function_privilege(
    'authenticated',
    'public.get_league_results_center(uuid)',
    'EXECUTE'
  ) as results_center_access_ready,
  has_function_privilege(
    'authenticated',
    'public.finalize_league_matchday(uuid,uuid)',
    'EXECUTE'
  ) as finalize_access_ready,
  has_function_privilege(
    'authenticated',
    'public.reopen_league_matchday(uuid,uuid)',
    'EXECUTE'
  ) as reopen_access_ready,
  (
    not has_function_privilege(
      'anon',
      'public.finalize_league_matchday(uuid,uuid)',
      'EXECUTE'
    )
    and not has_function_privilege(
      'anon',
      'public.reopen_league_matchday(uuid,uuid)',
      'EXECUTE'
    )
  ) as anonymous_blocked,
  (
    pg_get_functiondef(
      'public.finalize_league_matchday(uuid,uuid)'::regprocedure
    ) ilike '%v_league.owner_id <> auth.uid()%'
    and pg_get_functiondef(
      'public.reopen_league_matchday(uuid,uuid)'::regprocedure
    ) ilike '%v_league.owner_id <> auth.uid()%'
  ) as president_guards_ready,
  exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'fantasy_fixtures'
  ) as results_realtime_ready,
  pg_get_functiondef(
    'public.notify_final_fantasy_result()'::regprocedure
  ) ilike '%standings%' as result_notifications_ready;
