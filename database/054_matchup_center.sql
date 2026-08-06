-- LEGHEVO · Centro Sfida, forma e precedenti diretti
-- Eseguire nel SQL Editor di Supabase dopo 053.
-- Lo script aggiunge soltanto una lettura protetta: non modifica leghe,
-- formazioni, risultati o dati della lega di prova.

create or replace function public.get_league_matchup_center(
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
  v_my_team public.fantasy_teams%rowtype;
  v_opponent public.fantasy_teams%rowtype;
  v_focus record;
  v_my_standing record;
  v_opponent_standing record;
  v_my_manager_name text := 'Manager';
  v_opponent_manager_name text := 'Manager';
  v_my_form jsonb := '[]'::jsonb;
  v_opponent_form jsonb := '[]'::jsonb;
  v_my_unbeaten_streak integer := 0;
  v_opponent_unbeaten_streak integer := 0;
  v_current_played integer := 0;
  v_current_my_wins integer := 0;
  v_current_draws integer := 0;
  v_current_opponent_wins integer := 0;
  v_current_my_goals integer := 0;
  v_current_opponent_goals integer := 0;
  v_current_my_points numeric := 0;
  v_current_opponent_points numeric := 0;
  v_all_time_played integer := 0;
  v_all_time_my_wins integer := 0;
  v_all_time_draws integer := 0;
  v_all_time_opponent_wins integer := 0;
  v_all_time_my_goals integer := 0;
  v_all_time_opponent_goals integer := 0;
  v_all_time_my_points numeric := 0;
  v_all_time_opponent_points numeric := 0;
  v_all_time_seasons integer := 0;
  v_last_meetings jsonb := '[]'::jsonb;
  v_my_lineup_status text := 'missing';
  v_opponent_lineup_status text := 'missing';
  v_focus_status text := 'upcoming';
begin
  if auth.uid() is null then
    raise exception 'Devi effettuare l''accesso.';
  end if;

  if not public.is_league_member(p_league_id)
    and not public.is_league_admin(p_league_id) then
    raise exception 'Non fai parte di questa lega.';
  end if;

  select league.*
  into v_league
  from public.leagues league
  where league.id = p_league_id;

  if not found then
    raise exception 'Lega non trovata.';
  end if;

  select team.*
  into v_my_team
  from public.fantasy_teams team
  where team.league_id = p_league_id
    and team.manager_id = auth.uid();

  if not found then
    raise exception 'La tua squadra non è ancora disponibile.';
  end if;

  select coalesce(
    (
      select nullif(trim(profile.display_name), '')
      from public.profiles profile
      where profile.id = v_my_team.manager_id
    ),
    'Manager'
  )
  into v_my_manager_name
  ;

  select standing.*
  into v_my_standing
  from public.get_league_standings_v2(p_league_id) standing
  where standing.fantasy_team_id = v_my_team.id;

  with team_results as (
    select
      matchday.starts_at,
      case
        when fixture.home_team_id = v_my_team.id
          and fixture.home_goals > fixture.away_goals then 'W'
        when fixture.away_team_id = v_my_team.id
          and fixture.away_goals > fixture.home_goals then 'W'
        when fixture.home_goals = fixture.away_goals then 'D'
        else 'L'
      end as outcome
    from public.fantasy_fixtures fixture
    join public.matchdays matchday
      on matchday.id = fixture.matchday_id
    where fixture.league_id = p_league_id
      and fixture.finalized_at is not null
      and (
        fixture.home_team_id = v_my_team.id
        or fixture.away_team_id = v_my_team.id
      )
    order by matchday.starts_at desc, fixture.id
    limit 5
  )
  select coalesce(
    jsonb_agg(result.outcome order by result.starts_at desc),
    '[]'::jsonb
  )
  into v_my_form
  from team_results result;

  with team_results as (
    select
      case
        when fixture.home_team_id = v_my_team.id
          and fixture.home_goals > fixture.away_goals then 'W'
        when fixture.away_team_id = v_my_team.id
          and fixture.away_goals > fixture.home_goals then 'W'
        when fixture.home_goals = fixture.away_goals then 'D'
        else 'L'
      end as outcome,
      row_number() over (
        order by matchday.starts_at desc, fixture.id
      )::integer as result_number
    from public.fantasy_fixtures fixture
    join public.matchdays matchday
      on matchday.id = fixture.matchday_id
    where fixture.league_id = p_league_id
      and fixture.finalized_at is not null
      and (
        fixture.home_team_id = v_my_team.id
        or fixture.away_team_id = v_my_team.id
      )
  ),
  result_stop as (
    select
      count(*)::integer as result_count,
      min(result.result_number) filter (
        where result.outcome = 'L'
      )::integer as first_loss
    from team_results result
  )
  select case
    when stop.first_loss is null then stop.result_count
    else greatest(stop.first_loss - 1, 0)
  end
  into v_my_unbeaten_streak
  from result_stop stop;

  select
    fixture.id as fixture_id,
    fixture.matchday_id,
    fixture.home_team_id,
    fixture.away_team_id,
    fixture.home_points,
    fixture.away_points,
    fixture.home_goals,
    fixture.away_goals,
    fixture.home_ready,
    fixture.away_ready,
    fixture.finalized_at,
    matchday.number::integer as matchday_number,
    matchday.starts_at,
    matchday.locks_at,
    matchday.ends_at
  into v_focus
  from public.fantasy_fixtures fixture
  join public.matchdays matchday
    on matchday.id = fixture.matchday_id
  where fixture.league_id = p_league_id
    and fixture.finalized_at is null
    and (
      fixture.home_team_id = v_my_team.id
      or fixture.away_team_id = v_my_team.id
    )
  order by
    case when matchday.starts_at <= now() then 0 else 1 end,
    case
      when matchday.starts_at <= now() then matchday.starts_at
    end desc,
    case
      when matchday.starts_at > now() then matchday.starts_at
    end,
    matchday.number
  limit 1;

  if not found then
    select
      fixture.id as fixture_id,
      fixture.matchday_id,
      fixture.home_team_id,
      fixture.away_team_id,
      fixture.home_points,
      fixture.away_points,
      fixture.home_goals,
      fixture.away_goals,
      fixture.home_ready,
      fixture.away_ready,
      fixture.finalized_at,
      matchday.number::integer as matchday_number,
      matchday.starts_at,
      matchday.locks_at,
      matchday.ends_at
    into v_focus
    from public.fantasy_fixtures fixture
    join public.matchdays matchday
      on matchday.id = fixture.matchday_id
    where fixture.league_id = p_league_id
      and fixture.finalized_at is not null
      and (
        fixture.home_team_id = v_my_team.id
        or fixture.away_team_id = v_my_team.id
      )
    order by matchday.starts_at desc, fixture.finalized_at desc
    limit 1;
  end if;

  if v_focus.fixture_id is null then
    return jsonb_build_object(
      'leagueId', v_league.id,
      'leagueName', v_league.name,
      'season', v_league.calendar_season,
      'generatedAt', now(),
      'myTeam', jsonb_build_object(
        'id', v_my_team.id,
        'name', v_my_team.name,
        'managerName', v_my_manager_name,
        'position', coalesce(v_my_standing.position, 0),
        'played', coalesce(v_my_standing.played, 0),
        'won', coalesce(v_my_standing.won, 0),
        'drawn', coalesce(v_my_standing.drawn, 0),
        'lost', coalesce(v_my_standing.lost, 0),
        'goalsFor', coalesce(v_my_standing.goals_for, 0),
        'goalsAgainst', coalesce(v_my_standing.goals_against, 0),
        'pointsFor', coalesce(v_my_standing.points_for, 0),
        'leaguePoints', coalesce(v_my_standing.league_points, 0),
        'recentForm', v_my_form,
        'unbeatenStreak', v_my_unbeaten_streak
      ),
      'opponent', null,
      'fixture', null,
      'currentSeason', jsonb_build_object(
        'played', 0,
        'myWins', 0,
        'draws', 0,
        'opponentWins', 0,
        'myGoals', 0,
        'opponentGoals', 0,
        'myPoints', 0,
        'opponentPoints', 0
      ),
      'allTime', jsonb_build_object(
        'played', 0,
        'seasons', 0,
        'myWins', 0,
        'draws', 0,
        'opponentWins', 0,
        'myGoals', 0,
        'opponentGoals', 0,
        'myPoints', 0,
        'opponentPoints', 0,
        'leader', 'level'
      ),
      'lastMeetings', '[]'::jsonb
    );
  end if;

  select team.*
  into v_opponent
  from public.fantasy_teams team
  where team.id = case
    when v_focus.home_team_id = v_my_team.id
      then v_focus.away_team_id
    else v_focus.home_team_id
  end;

  select coalesce(
    (
      select nullif(trim(profile.display_name), '')
      from public.profiles profile
      where profile.id = v_opponent.manager_id
    ),
    'Manager'
  )
  into v_opponent_manager_name
  ;

  select standing.*
  into v_opponent_standing
  from public.get_league_standings_v2(p_league_id) standing
  where standing.fantasy_team_id = v_opponent.id;

  with team_results as (
    select
      matchday.starts_at,
      case
        when fixture.home_team_id = v_opponent.id
          and fixture.home_goals > fixture.away_goals then 'W'
        when fixture.away_team_id = v_opponent.id
          and fixture.away_goals > fixture.home_goals then 'W'
        when fixture.home_goals = fixture.away_goals then 'D'
        else 'L'
      end as outcome
    from public.fantasy_fixtures fixture
    join public.matchdays matchday
      on matchday.id = fixture.matchday_id
    where fixture.league_id = p_league_id
      and fixture.finalized_at is not null
      and (
        fixture.home_team_id = v_opponent.id
        or fixture.away_team_id = v_opponent.id
      )
    order by matchday.starts_at desc, fixture.id
    limit 5
  )
  select coalesce(
    jsonb_agg(result.outcome order by result.starts_at desc),
    '[]'::jsonb
  )
  into v_opponent_form
  from team_results result;

  with team_results as (
    select
      case
        when fixture.home_team_id = v_opponent.id
          and fixture.home_goals > fixture.away_goals then 'W'
        when fixture.away_team_id = v_opponent.id
          and fixture.away_goals > fixture.home_goals then 'W'
        when fixture.home_goals = fixture.away_goals then 'D'
        else 'L'
      end as outcome,
      row_number() over (
        order by matchday.starts_at desc, fixture.id
      )::integer as result_number
    from public.fantasy_fixtures fixture
    join public.matchdays matchday
      on matchday.id = fixture.matchday_id
    where fixture.league_id = p_league_id
      and fixture.finalized_at is not null
      and (
        fixture.home_team_id = v_opponent.id
        or fixture.away_team_id = v_opponent.id
      )
  ),
  result_stop as (
    select
      count(*)::integer as result_count,
      min(result.result_number) filter (
        where result.outcome = 'L'
      )::integer as first_loss
    from team_results result
  )
  select case
    when stop.first_loss is null then stop.result_count
    else greatest(stop.first_loss - 1, 0)
  end
  into v_opponent_unbeaten_streak
  from result_stop stop;

  select case
    when lineup.id is null then 'missing'
    when lineup.submission_source = 'carried' then 'carried'
    when lineup.status in ('submitted', 'locked') then 'submitted'
    else 'draft'
  end
  into v_my_lineup_status
  from (select 1) placeholder
  left join public.lineups lineup
    on lineup.fantasy_team_id = v_my_team.id
    and lineup.matchday_id = v_focus.matchday_id;

  select case
    when lineup.id is null then 'missing'
    when lineup.submission_source = 'carried' then 'carried'
    when lineup.status in ('submitted', 'locked') then 'submitted'
    else 'draft'
  end
  into v_opponent_lineup_status
  from (select 1) placeholder
  left join public.lineups lineup
    on lineup.fantasy_team_id = v_opponent.id
    and lineup.matchday_id = v_focus.matchday_id;

  if v_focus.finalized_at is not null then
    v_focus_status := 'final';
  elsif now() < v_focus.locks_at then
    v_focus_status := 'upcoming';
  elsif now() <= coalesce(
    v_focus.ends_at,
    v_focus.starts_at + interval '4 days'
  ) then
    v_focus_status := 'live';
  else
    v_focus_status := 'pending';
  end if;

  with rivalry as (
    select
      fixture.home_team_id = v_my_team.id as my_home,
      fixture.home_goals,
      fixture.away_goals,
      fixture.home_points,
      fixture.away_points
    from public.fantasy_fixtures fixture
    where fixture.league_id = p_league_id
      and fixture.finalized_at is not null
      and (
        (
          fixture.home_team_id = v_my_team.id
          and fixture.away_team_id = v_opponent.id
        )
        or (
          fixture.home_team_id = v_opponent.id
          and fixture.away_team_id = v_my_team.id
        )
      )
  ),
  normalized as (
    select
      case when match.my_home then match.home_goals else match.away_goals end
        as my_goals,
      case when match.my_home then match.away_goals else match.home_goals end
        as opponent_goals,
      case when match.my_home then match.home_points else match.away_points end
        as my_points,
      case when match.my_home then match.away_points else match.home_points end
        as opponent_points
    from rivalry match
  )
  select
    count(*)::integer,
    count(*) filter (
      where result.my_goals > result.opponent_goals
    )::integer,
    count(*) filter (
      where result.my_goals = result.opponent_goals
    )::integer,
    count(*) filter (
      where result.my_goals < result.opponent_goals
    )::integer,
    coalesce(sum(result.my_goals), 0)::integer,
    coalesce(sum(result.opponent_goals), 0)::integer,
    round(coalesce(sum(result.my_points), 0), 2),
    round(coalesce(sum(result.opponent_points), 0), 2)
  into
    v_current_played,
    v_current_my_wins,
    v_current_draws,
    v_current_opponent_wins,
    v_current_my_goals,
    v_current_opponent_goals,
    v_current_my_points,
    v_current_opponent_points
  from normalized result;

  with recursive ancestors as (
    select league.id, league.previous_league_id
    from public.leagues league
    where league.id = p_league_id

    union

    select previous.id, previous.previous_league_id
    from ancestors current_season
    join public.leagues previous
      on previous.id = current_season.previous_league_id
  ),
  root as (
    select ancestor.id
    from ancestors ancestor
    where ancestor.previous_league_id is null
    limit 1
  ),
  season_chain as (
    select league.id
    from public.leagues league
    join root on root.id = league.id

    union all

    select renewed.id
    from season_chain current_season
    join public.leagues renewed
      on renewed.previous_league_id = current_season.id
  ),
  rivalry as (
    select
      fixture.league_id,
      home_team.manager_id = v_my_team.manager_id as my_home,
      fixture.home_goals,
      fixture.away_goals,
      fixture.home_points,
      fixture.away_points
    from season_chain chain
    join public.fantasy_fixtures fixture
      on fixture.league_id = chain.id
    join public.fantasy_teams home_team
      on home_team.id = fixture.home_team_id
    join public.fantasy_teams away_team
      on away_team.id = fixture.away_team_id
    where fixture.finalized_at is not null
      and (
        (
          home_team.manager_id = v_my_team.manager_id
          and away_team.manager_id = v_opponent.manager_id
        )
        or (
          home_team.manager_id = v_opponent.manager_id
          and away_team.manager_id = v_my_team.manager_id
        )
      )
  ),
  normalized as (
    select
      match.league_id,
      case when match.my_home then match.home_goals else match.away_goals end
        as my_goals,
      case when match.my_home then match.away_goals else match.home_goals end
        as opponent_goals,
      case when match.my_home then match.home_points else match.away_points end
        as my_points,
      case when match.my_home then match.away_points else match.home_points end
        as opponent_points
    from rivalry match
  )
  select
    count(*)::integer,
    count(distinct result.league_id)::integer,
    count(*) filter (
      where result.my_goals > result.opponent_goals
    )::integer,
    count(*) filter (
      where result.my_goals = result.opponent_goals
    )::integer,
    count(*) filter (
      where result.my_goals < result.opponent_goals
    )::integer,
    coalesce(sum(result.my_goals), 0)::integer,
    coalesce(sum(result.opponent_goals), 0)::integer,
    round(coalesce(sum(result.my_points), 0), 2),
    round(coalesce(sum(result.opponent_points), 0), 2)
  into
    v_all_time_played,
    v_all_time_seasons,
    v_all_time_my_wins,
    v_all_time_draws,
    v_all_time_opponent_wins,
    v_all_time_my_goals,
    v_all_time_opponent_goals,
    v_all_time_my_points,
    v_all_time_opponent_points
  from normalized result;

  with recursive ancestors as (
    select league.id, league.previous_league_id
    from public.leagues league
    where league.id = p_league_id

    union

    select previous.id, previous.previous_league_id
    from ancestors current_season
    join public.leagues previous
      on previous.id = current_season.previous_league_id
  ),
  root as (
    select ancestor.id
    from ancestors ancestor
    where ancestor.previous_league_id is null
    limit 1
  ),
  season_chain as (
    select league.id
    from public.leagues league
    join root on root.id = league.id

    union all

    select renewed.id
    from season_chain current_season
    join public.leagues renewed
      on renewed.previous_league_id = current_season.id
  ),
  recent_matches as (
    select
      fixture.id,
      fixture.league_id,
      coalesce(summary.season, league.calendar_season) as season,
      matchday.number::integer as matchday_number,
      matchday.starts_at,
      home_team.name as home_team_name,
      away_team.name as away_team_name,
      home_team.manager_id = v_my_team.manager_id as my_home,
      fixture.home_points,
      fixture.away_points,
      fixture.home_goals,
      fixture.away_goals
    from season_chain chain
    join public.leagues league
      on league.id = chain.id
    join public.fantasy_fixtures fixture
      on fixture.league_id = chain.id
    join public.matchdays matchday
      on matchday.id = fixture.matchday_id
    join public.fantasy_teams home_team
      on home_team.id = fixture.home_team_id
    join public.fantasy_teams away_team
      on away_team.id = fixture.away_team_id
    left join public.league_season_summaries summary
      on summary.league_id = league.id
    where fixture.finalized_at is not null
      and (
        (
          home_team.manager_id = v_my_team.manager_id
          and away_team.manager_id = v_opponent.manager_id
        )
        or (
          home_team.manager_id = v_opponent.manager_id
          and away_team.manager_id = v_my_team.manager_id
        )
      )
    order by matchday.starts_at desc, fixture.id
    limit 5
  )
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'fixtureId', match.id,
        'leagueId', match.league_id,
        'season', match.season,
        'matchdayNumber', match.matchday_number,
        'startsAt', match.starts_at,
        'homeTeamName', match.home_team_name,
        'awayTeamName', match.away_team_name,
        'myHome', match.my_home,
        'myPoints',
          case
            when match.my_home then match.home_points
            else match.away_points
          end,
        'opponentPoints',
          case
            when match.my_home then match.away_points
            else match.home_points
          end,
        'myGoals',
          case
            when match.my_home then match.home_goals
            else match.away_goals
          end,
        'opponentGoals',
          case
            when match.my_home then match.away_goals
            else match.home_goals
          end,
        'outcome',
          case
            when (
              case
                when match.my_home then match.home_goals
                else match.away_goals
              end
            ) > (
              case
                when match.my_home then match.away_goals
                else match.home_goals
              end
            ) then 'W'
            when match.home_goals = match.away_goals then 'D'
            else 'L'
          end
      )
      order by match.starts_at desc
    ),
    '[]'::jsonb
  )
  into v_last_meetings
  from recent_matches match;

  return jsonb_build_object(
    'leagueId', v_league.id,
    'leagueName', v_league.name,
    'season', v_league.calendar_season,
    'generatedAt', now(),
    'myTeam', jsonb_build_object(
      'id', v_my_team.id,
      'name', v_my_team.name,
      'managerName', v_my_manager_name,
      'position', coalesce(v_my_standing.position, 0),
      'played', coalesce(v_my_standing.played, 0),
      'won', coalesce(v_my_standing.won, 0),
      'drawn', coalesce(v_my_standing.drawn, 0),
      'lost', coalesce(v_my_standing.lost, 0),
      'goalsFor', coalesce(v_my_standing.goals_for, 0),
      'goalsAgainst', coalesce(v_my_standing.goals_against, 0),
      'pointsFor', coalesce(v_my_standing.points_for, 0),
      'leaguePoints', coalesce(v_my_standing.league_points, 0),
      'recentForm', v_my_form,
      'unbeatenStreak', v_my_unbeaten_streak
    ),
    'opponent', jsonb_build_object(
      'id', v_opponent.id,
      'name', v_opponent.name,
      'managerName', v_opponent_manager_name,
      'position', coalesce(v_opponent_standing.position, 0),
      'played', coalesce(v_opponent_standing.played, 0),
      'won', coalesce(v_opponent_standing.won, 0),
      'drawn', coalesce(v_opponent_standing.drawn, 0),
      'lost', coalesce(v_opponent_standing.lost, 0),
      'goalsFor', coalesce(v_opponent_standing.goals_for, 0),
      'goalsAgainst', coalesce(v_opponent_standing.goals_against, 0),
      'pointsFor', coalesce(v_opponent_standing.points_for, 0),
      'leaguePoints', coalesce(v_opponent_standing.league_points, 0),
      'recentForm', v_opponent_form,
      'unbeatenStreak', v_opponent_unbeaten_streak
    ),
    'fixture', jsonb_build_object(
      'id', v_focus.fixture_id,
      'matchdayId', v_focus.matchday_id,
      'matchdayNumber', v_focus.matchday_number,
      'startsAt', v_focus.starts_at,
      'locksAt', v_focus.locks_at,
      'endsAt', v_focus.ends_at,
      'status', v_focus_status,
      'homeTeamId', v_focus.home_team_id,
      'awayTeamId', v_focus.away_team_id,
      'myHome', v_focus.home_team_id = v_my_team.id,
      'myPoints',
        case
          when v_focus.home_team_id = v_my_team.id
            then v_focus.home_points
          else v_focus.away_points
        end,
      'opponentPoints',
        case
          when v_focus.home_team_id = v_my_team.id
            then v_focus.away_points
          else v_focus.home_points
        end,
      'myGoals',
        case
          when v_focus.home_team_id = v_my_team.id
            then v_focus.home_goals
          else v_focus.away_goals
        end,
      'opponentGoals',
        case
          when v_focus.home_team_id = v_my_team.id
            then v_focus.away_goals
          else v_focus.home_goals
        end,
      'myLineupStatus', v_my_lineup_status,
      'opponentLineupStatus', v_opponent_lineup_status,
      'lineupsLocked', now() >= v_focus.locks_at
    ),
    'currentSeason', jsonb_build_object(
      'played', v_current_played,
      'myWins', v_current_my_wins,
      'draws', v_current_draws,
      'opponentWins', v_current_opponent_wins,
      'myGoals', v_current_my_goals,
      'opponentGoals', v_current_opponent_goals,
      'myPoints', v_current_my_points,
      'opponentPoints', v_current_opponent_points
    ),
    'allTime', jsonb_build_object(
      'played', v_all_time_played,
      'seasons', v_all_time_seasons,
      'myWins', v_all_time_my_wins,
      'draws', v_all_time_draws,
      'opponentWins', v_all_time_opponent_wins,
      'myGoals', v_all_time_my_goals,
      'opponentGoals', v_all_time_opponent_goals,
      'myPoints', v_all_time_my_points,
      'opponentPoints', v_all_time_opponent_points,
      'leader',
        case
          when v_all_time_my_wins > v_all_time_opponent_wins then 'me'
          when v_all_time_my_wins < v_all_time_opponent_wins
            then 'opponent'
          else 'level'
        end
    ),
    'lastMeetings', v_last_meetings
  );
end;
$$;

revoke all on function public.get_league_matchup_center(uuid)
from public, anon, authenticated;

grant execute on function public.get_league_matchup_center(uuid)
to authenticated;

select
  to_regprocedure(
    'public.get_league_matchup_center(uuid)'
  ) is not null as matchup_center_ready,
  has_function_privilege(
    'authenticated',
    'public.get_league_matchup_center(uuid)',
    'EXECUTE'
  ) as authenticated_access_ready,
  not has_function_privilege(
    'anon',
    'public.get_league_matchup_center(uuid)',
    'EXECUTE'
  ) as anonymous_access_blocked,
  (
    select routine_type = 'FUNCTION'
    from information_schema.routines
    where routine_schema = 'public'
      and routine_name = 'get_league_matchup_center'
  ) as matchup_center_is_function,
  (
    select data_type = 'jsonb'
    from information_schema.routines
    where routine_schema = 'public'
      and routine_name = 'get_league_matchup_center'
  ) as matchup_center_returns_json,
  (
    select security_type = 'DEFINER'
    from information_schema.routines
    where routine_schema = 'public'
      and routine_name = 'get_league_matchup_center'
  ) as matchup_center_is_protected,
  (
    select procedure.provolatile = 's'
    from pg_proc procedure
    join pg_namespace namespace
      on namespace.oid = procedure.pronamespace
    where namespace.nspname = 'public'
      and procedure.proname = 'get_league_matchup_center'
      and pg_get_function_identity_arguments(procedure.oid) = 'p_league_id uuid'
  ) as matchup_center_is_read_only,
  position(
    'is_league_member'
    in pg_get_functiondef(
      'public.get_league_matchup_center(uuid)'::regprocedure
    )
  ) > 0 as membership_check_ready,
  position(
    'finalized_at is not null'
    in lower(
      pg_get_functiondef(
        'public.get_league_matchup_center(uuid)'::regprocedure
      )
    )
  ) > 0 as official_results_only,
  position(
    'previous_league_id'
    in pg_get_functiondef(
      'public.get_league_matchup_center(uuid)'::regprocedure
    )
  ) > 0 as linked_seasons_ready,
  position(
    'lineup_entries'
    in lower(
      pg_get_functiondef(
        'public.get_league_matchup_center(uuid)'::regprocedure
      )
    )
  ) = 0 as lineup_contents_hidden,
  position(
    '''formation'''
    in lower(
      pg_get_functiondef(
        'public.get_league_matchup_center(uuid)'::regprocedure
      )
    )
  ) = 0 as formation_hidden;
