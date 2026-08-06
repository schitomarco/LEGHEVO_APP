-- LEGHEVO · record storici e statistiche carriera dei manager
-- Eseguire nel SQL Editor di Supabase dopo 041.
-- Lo script legge soltanto stagioni concluse e risultati congelati:
-- non modifica leghe, classifiche, rose o partite.

create or replace function public.get_league_records(
  p_league_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_root_league_id uuid;
  v_completed_seasons integer := 0;
  v_season_records jsonb := '[]'::jsonb;
  v_match_records jsonb := '[]'::jsonb;
  v_career_leaders jsonb := '[]'::jsonb;
begin
  if auth.uid() is null then
    raise exception 'Devi effettuare l''accesso.';
  end if;

  if not public.is_league_member(p_league_id)
    and not public.is_league_admin(p_league_id) then
    raise exception 'Non fai parte di questa lega.';
  end if;

  if not exists (
    select 1
    from public.leagues league
    where league.id = p_league_id
  ) then
    raise exception 'Lega non trovata.';
  end if;

  with recursive ancestors as (
    select
      league.id,
      league.previous_league_id
    from public.leagues league
    where league.id = p_league_id

    union

    select
      previous.id,
      previous.previous_league_id
    from ancestors current_season
    join public.leagues previous
      on previous.id = current_season.previous_league_id
  )
  select ancestor.id
  into v_root_league_id
  from ancestors ancestor
  where ancestor.previous_league_id is null
  limit 1;

  if v_root_league_id is null then
    raise exception 'La catena delle stagioni non è valida.';
  end if;

  with recursive season_chain as (
    select league.id
    from public.leagues league
    where league.id = v_root_league_id

    union all

    select renewed.id
    from season_chain current_season
    join public.leagues renewed
      on renewed.previous_league_id = current_season.id
  )
  select count(*)::integer
  into v_completed_seasons
  from season_chain chain
  join public.league_season_summaries summary
    on summary.league_id = chain.id;

  with recursive season_chain as (
    select league.id
    from public.leagues league
    where league.id = v_root_league_id

    union all

    select renewed.id
    from season_chain current_season
    join public.leagues renewed
      on renewed.previous_league_id = current_season.id
  ),
  completed_standings as (
    select
      summary.league_id,
      summary.season,
      summary.completed_at,
      coalesce(
        (standing.item ->> 'position')::integer,
        standing.ordinality::integer
      ) as position,
      team.id as team_id,
      team.manager_id,
      standing.item ->> 'teamName' as team_name,
      coalesce(
        profile.display_name,
        standing.item ->> 'managerName'
      ) as manager_name,
      coalesce((standing.item ->> 'played')::integer, 0) as played,
      coalesce((standing.item ->> 'won')::integer, 0) as won,
      coalesce((standing.item ->> 'drawn')::integer, 0) as drawn,
      coalesce((standing.item ->> 'lost')::integer, 0) as lost,
      coalesce((standing.item ->> 'goalsFor')::integer, 0) as goals_for,
      coalesce((standing.item ->> 'goalsAgainst')::integer, 0)
        as goals_against,
      coalesce((standing.item ->> 'goalDifference')::integer, 0)
        as goal_difference,
      coalesce((standing.item ->> 'pointsFor')::numeric, 0)
        as fantasy_points,
      coalesce((standing.item ->> 'leaguePoints')::integer, 0)
        as league_points
    from season_chain chain
    join public.league_season_summaries summary
      on summary.league_id = chain.id
    cross join lateral jsonb_array_elements(
      summary.final_standings
    ) with ordinality as standing(item, ordinality)
    join public.fantasy_teams team
      on team.id = (standing.item ->> 'teamId')::uuid
    left join public.profiles profile
      on profile.id = team.manager_id
  ),
  record_candidates as (
    select
      'league_points'::text as record_key,
      1 as display_order,
      standing.league_points::numeric as record_value,
      standing.*
    from completed_standings standing

    union all

    select
      'fantasy_points',
      2,
      standing.fantasy_points,
      standing.*
    from completed_standings standing

    union all

    select
      'wins',
      3,
      standing.won::numeric,
      standing.*
    from completed_standings standing

    union all

    select
      'goals_for',
      4,
      standing.goals_for::numeric,
      standing.*
    from completed_standings standing

    union all

    select
      'goal_difference',
      5,
      standing.goal_difference::numeric,
      standing.*
    from completed_standings standing
  ),
  ranked_records as (
    select
      candidate.*,
      row_number() over (
        partition by candidate.record_key
        order by
          candidate.record_value desc,
          candidate.completed_at,
          candidate.team_name,
          candidate.team_id
      ) as record_rank
    from record_candidates candidate
  )
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'key', record.record_key,
        'value', record.record_value,
        'season', record.season,
        'teamId', record.team_id,
        'teamName', record.team_name,
        'managerId', record.manager_id,
        'managerName', record.manager_name
      )
      order by record.display_order
    ),
    '[]'::jsonb
  )
  into v_season_records
  from ranked_records record
  where record.record_rank = 1;

  with recursive season_chain as (
    select league.id
    from public.leagues league
    where league.id = v_root_league_id

    union all

    select renewed.id
    from season_chain current_season
    join public.leagues renewed
      on renewed.previous_league_id = current_season.id
  ),
  completed_standings as (
    select
      summary.league_id,
      summary.season,
      coalesce(
        (standing.item ->> 'position')::integer,
        standing.ordinality::integer
      ) as position,
      team.manager_id,
      standing.item ->> 'teamName' as team_name,
      standing.item ->> 'managerName' as snapshot_manager_name,
      coalesce((standing.item ->> 'played')::integer, 0) as played,
      coalesce((standing.item ->> 'won')::integer, 0) as won,
      coalesce((standing.item ->> 'drawn')::integer, 0) as drawn,
      coalesce((standing.item ->> 'lost')::integer, 0) as lost,
      coalesce((standing.item ->> 'goalsFor')::integer, 0) as goals_for,
      coalesce((standing.item ->> 'goalsAgainst')::integer, 0)
        as goals_against,
      coalesce((standing.item ->> 'pointsFor')::numeric, 0)
        as fantasy_points,
      coalesce((standing.item ->> 'leaguePoints')::integer, 0)
        as league_points
    from season_chain chain
    join public.league_season_summaries summary
      on summary.league_id = chain.id
    cross join lateral jsonb_array_elements(
      summary.final_standings
    ) with ordinality as standing(item, ordinality)
    join public.fantasy_teams team
      on team.id = (standing.item ->> 'teamId')::uuid
  ),
  careers as (
    select
      standing.manager_id,
      coalesce(
        profile.display_name,
        max(standing.snapshot_manager_name)
      ) as manager_name,
      count(distinct standing.league_id)::integer as seasons,
      count(*) filter (where standing.position = 1)::integer as titles,
      count(*) filter (where standing.position <= 3)::integer as podiums,
      min(standing.position)::integer as best_finish,
      sum(standing.played)::integer as played,
      sum(standing.won)::integer as won,
      sum(standing.drawn)::integer as drawn,
      sum(standing.lost)::integer as lost,
      sum(standing.goals_for)::integer as goals_for,
      sum(standing.goals_against)::integer as goals_against,
      round(sum(standing.fantasy_points), 2) as fantasy_points,
      sum(standing.league_points)::integer as league_points,
      round(
        case
          when sum(standing.played) > 0 then
            sum(standing.won)::numeric
              * 100
              / sum(standing.played)::numeric
          else 0
        end,
        1
      ) as win_rate,
      to_jsonb(
        array_agg(
          distinct standing.team_name
          order by standing.team_name
        )
      ) as team_names
    from completed_standings standing
    left join public.profiles profile
      on profile.id = standing.manager_id
    group by
      standing.manager_id,
      profile.display_name
  ),
  ranked_careers as (
    select
      career.*,
      row_number() over (
        order by
          career.titles desc,
          career.league_points desc,
          career.won desc,
          career.fantasy_points desc,
          career.manager_name,
          career.manager_id
      ) as career_rank
    from careers career
  )
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'rank', career.career_rank,
        'managerId', career.manager_id,
        'managerName', career.manager_name,
        'seasons', career.seasons,
        'titles', career.titles,
        'podiums', career.podiums,
        'bestFinish', career.best_finish,
        'played', career.played,
        'won', career.won,
        'drawn', career.drawn,
        'lost', career.lost,
        'goalsFor', career.goals_for,
        'goalsAgainst', career.goals_against,
        'fantasyPoints', career.fantasy_points,
        'leaguePoints', career.league_points,
        'winRate', career.win_rate,
        'teamNames', career.team_names
      )
      order by career.career_rank
    ),
    '[]'::jsonb
  )
  into v_career_leaders
  from ranked_careers career;

  with recursive season_chain as (
    select league.id
    from public.leagues league
    where league.id = v_root_league_id

    union all

    select renewed.id
    from season_chain current_season
    join public.leagues renewed
      on renewed.previous_league_id = current_season.id
  ),
  completed_fixtures as (
    select
      fixture.id as fixture_id,
      summary.season,
      summary.completed_at,
      matchday.number::integer as matchday_number,
      fixture.home_team_id,
      home_team.name as home_team_name,
      home_team.manager_id as home_manager_id,
      coalesce(home_profile.display_name, 'Manager') as home_manager_name,
      fixture.away_team_id,
      away_team.name as away_team_name,
      away_team.manager_id as away_manager_id,
      coalesce(away_profile.display_name, 'Manager') as away_manager_name,
      fixture.home_points,
      fixture.away_points,
      fixture.home_goals::integer as home_goals,
      fixture.away_goals::integer as away_goals
    from season_chain chain
    join public.league_season_summaries summary
      on summary.league_id = chain.id
    join public.fantasy_fixtures fixture
      on fixture.league_id = chain.id
      and fixture.finalized_at is not null
      and fixture.home_points is not null
      and fixture.away_points is not null
      and fixture.home_goals is not null
      and fixture.away_goals is not null
    join public.matchdays matchday
      on matchday.id = fixture.matchday_id
    join public.fantasy_teams home_team
      on home_team.id = fixture.home_team_id
    join public.fantasy_teams away_team
      on away_team.id = fixture.away_team_id
    left join public.profiles home_profile
      on home_profile.id = home_team.manager_id
    left join public.profiles away_profile
      on away_profile.id = away_team.manager_id
  ),
  highest_score_candidates as (
    select
      'highest_score'::text as record_key,
      1 as display_order,
      fixture.home_points::numeric as record_value,
      fixture.*,
      fixture.home_team_id as team_id,
      fixture.home_team_name as team_name,
      fixture.home_manager_id as manager_id,
      fixture.home_manager_name as manager_name,
      fixture.away_team_name as opponent_name
    from completed_fixtures fixture

    union all

    select
      'highest_score',
      1,
      fixture.away_points::numeric,
      fixture.*,
      fixture.away_team_id,
      fixture.away_team_name,
      fixture.away_manager_id,
      fixture.away_manager_name,
      fixture.home_team_name
    from completed_fixtures fixture
  ),
  biggest_win_candidates as (
    select
      'biggest_win'::text as record_key,
      2 as display_order,
      abs(fixture.home_goals - fixture.away_goals)::numeric
        as record_value,
      fixture.*,
      case
        when fixture.home_goals > fixture.away_goals
          then fixture.home_team_id
        else fixture.away_team_id
      end as team_id,
      case
        when fixture.home_goals > fixture.away_goals
          then fixture.home_team_name
        else fixture.away_team_name
      end as team_name,
      case
        when fixture.home_goals > fixture.away_goals
          then fixture.home_manager_id
        else fixture.away_manager_id
      end as manager_id,
      case
        when fixture.home_goals > fixture.away_goals
          then fixture.home_manager_name
        else fixture.away_manager_name
      end as manager_name,
      case
        when fixture.home_goals > fixture.away_goals
          then fixture.away_team_name
        else fixture.home_team_name
      end as opponent_name
    from completed_fixtures fixture
    where fixture.home_goals <> fixture.away_goals
  ),
  highest_total_candidates as (
    select
      'highest_total_goals'::text as record_key,
      3 as display_order,
      (fixture.home_goals + fixture.away_goals)::numeric
        as record_value,
      fixture.*,
      fixture.home_team_id as team_id,
      fixture.home_team_name as team_name,
      fixture.home_manager_id as manager_id,
      fixture.home_manager_name as manager_name,
      fixture.away_team_name as opponent_name
    from completed_fixtures fixture
  ),
  match_candidates as (
    select * from highest_score_candidates
    union all
    select * from biggest_win_candidates
    union all
    select * from highest_total_candidates
  ),
  ranked_matches as (
    select
      candidate.*,
      row_number() over (
        partition by candidate.record_key
        order by
          candidate.record_value desc,
          candidate.completed_at,
          candidate.matchday_number,
          candidate.fixture_id
      ) as record_rank
    from match_candidates candidate
  )
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'key', record.record_key,
        'value', record.record_value,
        'fixtureId', record.fixture_id,
        'season', record.season,
        'matchdayNumber', record.matchday_number,
        'teamId', record.team_id,
        'teamName', record.team_name,
        'managerId', record.manager_id,
        'managerName', record.manager_name,
        'opponentName', record.opponent_name,
        'homeTeamName', record.home_team_name,
        'awayTeamName', record.away_team_name,
        'homePoints', record.home_points,
        'awayPoints', record.away_points,
        'homeGoals', record.home_goals,
        'awayGoals', record.away_goals
      )
      order by record.display_order
    ),
    '[]'::jsonb
  )
  into v_match_records
  from ranked_matches record
  where record.record_rank = 1;

  return jsonb_build_object(
    'completedSeasons', v_completed_seasons,
    'seasonRecords', v_season_records,
    'matchRecords', v_match_records,
    'careerLeaders', v_career_leaders
  );
end;
$$;

revoke all on function public.get_league_records(uuid)
from public, anon, authenticated;

grant execute on function public.get_league_records(uuid)
to authenticated;

select
  to_regprocedure(
    'public.get_league_records(uuid)'
  ) is not null as league_records_ready,
  has_function_privilege(
    'authenticated',
    'public.get_league_records(uuid)',
    'EXECUTE'
  ) as league_records_access_ready,
  not has_function_privilege(
    'anon',
    'public.get_league_records(uuid)',
    'EXECUTE'
  ) as anonymous_records_blocked,
  (
    select routine_type = 'FUNCTION'
    from information_schema.routines
    where routine_schema = 'public'
      and routine_name = 'get_league_records'
  ) as league_records_is_function,
  (
    select data_type = 'jsonb'
    from information_schema.routines
    where routine_schema = 'public'
      and routine_name = 'get_league_records'
  ) as league_records_returns_json,
  (
    select security_type = 'DEFINER'
    from information_schema.routines
    where routine_schema = 'public'
      and routine_name = 'get_league_records'
  ) as league_records_security_ready,
  (
    select provolatile = 's'
    from pg_proc
    where oid = 'public.get_league_records(uuid)'::regprocedure
  ) as league_records_stable,
  (
    select count(*) = 1
    from information_schema.parameters
    where specific_schema = 'public'
      and specific_name in (
        select routine.specific_name
        from information_schema.routines routine
        where routine.routine_schema = 'public'
          and routine.routine_name = 'get_league_records'
      )
      and parameter_mode = 'IN'
      and udt_name = 'uuid'
  ) as league_records_signature_ready,
  to_regclass(
    'public.league_season_summaries'
  ) is not null as season_summaries_ready,
  exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'league_season_summaries'
      and column_name = 'final_standings'
      and udt_name = 'jsonb'
  ) as frozen_standings_ready,
  exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'leagues'
      and column_name = 'previous_league_id'
  ) as season_chain_ready,
  to_regclass(
    'public.fantasy_fixtures'
  ) is not null as finalized_fixtures_ready;
