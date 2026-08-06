-- LEGHEVO · criteri di spareggio della classifica
-- Eseguire nel SQL Editor di Supabase dopo 036.

create or replace function public.get_league_standings_v2(
  p_league_id uuid
)
returns table (
  "position" integer,
  fantasy_team_id uuid,
  team_name text,
  played integer,
  won integer,
  drawn integer,
  lost integer,
  goals_for integer,
  goals_against integer,
  goal_difference integer,
  points_for numeric,
  league_points integer,
  standings_tiebreaker text,
  head_to_head_played integer,
  head_to_head_points integer,
  head_to_head_goal_difference integer,
  head_to_head_eligible boolean
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tiebreaker text := 'goal_difference';
begin
  if auth.uid() is null then
    raise exception 'Devi effettuare l''accesso.';
  end if;

  if not public.is_league_member(p_league_id)
    and not public.is_league_admin(p_league_id) then
    raise exception 'Non fai parte di questa lega.';
  end if;

  select case
    when lower(
      coalesce(
        league.scoring_rules ->> 'standings_tiebreaker',
        'goal_difference'
      )
    ) in ('goal_difference', 'fantasy_points', 'head_to_head')
      then lower(
        coalesce(
          league.scoring_rules ->> 'standings_tiebreaker',
          'goal_difference'
        )
      )
    else 'goal_difference'
  end
  into v_tiebreaker
  from public.leagues league
  where league.id = p_league_id;

  if not found then
    raise exception 'Lega non trovata.';
  end if;

  return query
  with team_results as (
    select
      fixture.home_team_id as team_id,
      fixture.away_team_id as opponent_id,
      fixture.home_goals as scored,
      fixture.away_goals as conceded,
      fixture.home_points as fantasy_points,
      case when fixture.home_goals > fixture.away_goals then 1 else 0 end
        as win,
      case when fixture.home_goals = fixture.away_goals then 1 else 0 end
        as draw,
      case when fixture.home_goals < fixture.away_goals then 1 else 0 end
        as loss
    from public.fantasy_fixtures fixture
    where fixture.league_id = p_league_id
      and fixture.finalized_at is not null

    union all

    select
      fixture.away_team_id as team_id,
      fixture.home_team_id as opponent_id,
      fixture.away_goals as scored,
      fixture.home_goals as conceded,
      fixture.away_points as fantasy_points,
      case when fixture.away_goals > fixture.home_goals then 1 else 0 end,
      case when fixture.away_goals = fixture.home_goals then 1 else 0 end,
      case when fixture.away_goals < fixture.home_goals then 1 else 0 end
    from public.fantasy_fixtures fixture
    where fixture.league_id = p_league_id
      and fixture.finalized_at is not null
  ),
  totals as (
    select
      result.team_id,
      count(*)::integer as played,
      sum(result.win)::integer as won,
      sum(result.draw)::integer as drawn,
      sum(result.loss)::integer as lost,
      sum(result.scored)::integer as goals_for,
      sum(result.conceded)::integer as goals_against,
      round(sum(result.fantasy_points)::numeric, 2) as points_for,
      (sum(result.win) * 3 + sum(result.draw))::integer as league_points
    from team_results result
    group by result.team_id
  ),
  standings as (
    select
      team.id as team_id,
      team.name,
      coalesce(total.played, 0)::integer as played,
      coalesce(total.won, 0)::integer as won,
      coalesce(total.drawn, 0)::integer as drawn,
      coalesce(total.lost, 0)::integer as lost,
      coalesce(total.goals_for, 0)::integer as goals_for,
      coalesce(total.goals_against, 0)::integer as goals_against,
      (
        coalesce(total.goals_for, 0)
        - coalesce(total.goals_against, 0)
      )::integer as goal_difference,
      coalesce(total.points_for, 0)::numeric as points_for,
      coalesce(total.league_points, 0)::integer as league_points
    from public.fantasy_teams team
    left join totals total on total.team_id = team.id
    where team.league_id = p_league_id
  ),
  head_to_head_totals as (
    select
      result.team_id,
      count(*)::integer as played,
      sum(result.win * 3 + result.draw)::integer as league_points,
      sum(result.scored)::integer as goals_for,
      (
        sum(result.scored) - sum(result.conceded)
      )::integer as goal_difference
    from team_results result
    join standings team
      on team.team_id = result.team_id
    join standings opponent
      on opponent.team_id = result.opponent_id
      and opponent.league_points = team.league_points
    group by result.team_id
  ),
  head_to_head_readiness as (
    select
      standing.league_points,
      count(*)::integer as team_count,
      min(coalesce(head_to_head.played, 0))::integer as minimum_played,
      max(coalesce(head_to_head.played, 0))::integer as maximum_played
    from standings standing
    left join head_to_head_totals head_to_head
      on head_to_head.team_id = standing.team_id
    group by standing.league_points
  ),
  enriched as (
    select
      standing.*,
      coalesce(head_to_head.played, 0)::integer as head_to_head_played,
      coalesce(head_to_head.league_points, 0)::integer
        as head_to_head_points,
      coalesce(head_to_head.goals_for, 0)::integer
        as head_to_head_goals_for,
      coalesce(head_to_head.goal_difference, 0)::integer
        as head_to_head_goal_difference,
      (
        readiness.team_count > 1
        and readiness.minimum_played > 0
        and readiness.minimum_played = readiness.maximum_played
      ) as head_to_head_eligible
    from standings standing
    join head_to_head_readiness readiness
      on readiness.league_points = standing.league_points
    left join head_to_head_totals head_to_head
      on head_to_head.team_id = standing.team_id
  ),
  ranked as (
    select
      row_number() over (
        order by
          standing.league_points desc,
          case
            when v_tiebreaker = 'head_to_head'
              and standing.head_to_head_eligible
              then standing.head_to_head_points
            else 0
          end desc,
          case
            when v_tiebreaker = 'head_to_head'
              and standing.head_to_head_eligible
              then standing.head_to_head_goal_difference
            else 0
          end desc,
          case
            when v_tiebreaker = 'head_to_head'
              and standing.head_to_head_eligible
              then standing.head_to_head_goals_for
            else 0
          end desc,
          case
            when v_tiebreaker = 'fantasy_points'
              then standing.points_for
            else 0
          end desc,
          case
            when v_tiebreaker in ('goal_difference', 'head_to_head')
              then standing.goal_difference
            else 0
          end desc,
          case
            when v_tiebreaker = 'fantasy_points'
              then standing.goal_difference
            else 0
          end desc,
          standing.goals_for desc,
          standing.points_for desc,
          standing.name
      )::integer as calculated_position,
      standing.*
    from enriched standing
  )
  select
    standing.calculated_position,
    standing.team_id,
    standing.name,
    standing.played,
    standing.won,
    standing.drawn,
    standing.lost,
    standing.goals_for,
    standing.goals_against,
    standing.goal_difference,
    standing.points_for,
    standing.league_points,
    v_tiebreaker,
    standing.head_to_head_played,
    standing.head_to_head_points,
    standing.head_to_head_goal_difference,
    standing.head_to_head_eligible
  from ranked standing
  order by standing.calculated_position;
end;
$$;

revoke all on function public.get_league_standings_v2(uuid)
from public, anon, authenticated;

grant execute on function public.get_league_standings_v2(uuid)
to authenticated;

create or replace function public.get_league_standings(
  p_league_id uuid
)
returns table (
  "position" integer,
  fantasy_team_id uuid,
  team_name text,
  played integer,
  won integer,
  drawn integer,
  lost integer,
  goals_for integer,
  goals_against integer,
  points_for numeric,
  league_points integer
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    standing.position,
    standing.fantasy_team_id,
    standing.team_name,
    standing.played,
    standing.won,
    standing.drawn,
    standing.lost,
    standing.goals_for,
    standing.goals_against,
    standing.points_for,
    standing.league_points
  from public.get_league_standings_v2(p_league_id) standing
  order by standing.position
$$;

revoke all on function public.get_league_standings(uuid)
from public, anon, authenticated;

grant execute on function public.get_league_standings(uuid)
to authenticated;

create or replace function public.update_league_settings_v8(
  p_league_id uuid,
  p_market_open boolean,
  p_market_min_price integer,
  p_release_refund_percent integer,
  p_goal_threshold numeric,
  p_goal_step numeric,
  p_home_bonus numeric,
  p_bonus_goal numeric,
  p_bonus_assist numeric,
  p_bonus_penalty_saved numeric,
  p_malus_yellow_card numeric,
  p_malus_red_card numeric,
  p_malus_penalty_missed numeric,
  p_malus_goal_conceded numeric,
  p_roster_goalkeepers integer,
  p_roster_defenders integer,
  p_roster_midfielders integer,
  p_roster_attackers integer,
  p_max_substitutions integer,
  p_defense_modifier_enabled boolean,
  p_defense_modifier_min_defenders integer,
  p_goal_margin_enabled boolean,
  p_goal_margin numeric,
  p_goal_bands_enabled boolean,
  p_goal_bands numeric[],
  p_standings_tiebreaker text
)
returns public.leagues
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_league public.leagues%rowtype;
  v_tiebreaker text := lower(
    trim(coalesce(p_standings_tiebreaker, 'goal_difference'))
  );
begin
  if v_tiebreaker not in (
    'goal_difference',
    'fantasy_points',
    'head_to_head'
  ) then
    raise exception 'Criterio di classifica non valido.';
  end if;

  select updated.*
  into v_league
  from public.update_league_settings_v7(
    p_league_id,
    p_market_open,
    p_market_min_price,
    p_release_refund_percent,
    p_goal_threshold,
    p_goal_step,
    p_home_bonus,
    p_bonus_goal,
    p_bonus_assist,
    p_bonus_penalty_saved,
    p_malus_yellow_card,
    p_malus_red_card,
    p_malus_penalty_missed,
    p_malus_goal_conceded,
    p_roster_goalkeepers,
    p_roster_defenders,
    p_roster_midfielders,
    p_roster_attackers,
    p_max_substitutions,
    p_defense_modifier_enabled,
    p_defense_modifier_min_defenders,
    p_goal_margin_enabled,
    p_goal_margin,
    p_goal_bands_enabled,
    p_goal_bands
  ) as updated;

  update public.leagues
  set
    scoring_rules = coalesce(scoring_rules, '{}'::jsonb)
      || jsonb_build_object(
        'standings_tiebreaker',
        v_tiebreaker
      ),
    updated_at = now()
  where id = p_league_id
  returning * into v_league;

  return v_league;
end;
$$;

revoke all on function public.update_league_settings_v8(
  uuid,
  boolean,
  integer,
  integer,
  numeric,
  numeric,
  numeric,
  numeric,
  numeric,
  numeric,
  numeric,
  numeric,
  numeric,
  numeric,
  integer,
  integer,
  integer,
  integer,
  integer,
  boolean,
  integer,
  boolean,
  numeric,
  boolean,
  numeric[],
  text
) from public, anon, authenticated;

grant execute on function public.update_league_settings_v8(
  uuid,
  boolean,
  integer,
  integer,
  numeric,
  numeric,
  numeric,
  numeric,
  numeric,
  numeric,
  numeric,
  numeric,
  numeric,
  numeric,
  integer,
  integer,
  integer,
  integer,
  integer,
  boolean,
  integer,
  boolean,
  numeric,
  boolean,
  numeric[],
  text
) to authenticated;

select
  to_regprocedure(
    'public.get_league_standings_v2(uuid)'
  ) is not null as standings_v2_ready,
  has_function_privilege(
    'authenticated',
    'public.get_league_standings_v2(uuid)',
    'EXECUTE'
  ) as standings_access_ready,
  not has_function_privilege(
    'anon',
    'public.get_league_standings_v2(uuid)',
    'EXECUTE'
  ) as anonymous_blocked,
  pg_get_functiondef(
    'public.get_league_standings_v2(uuid)'::regprocedure
  ) ilike '%head_to_head_eligible%'
    as head_to_head_ready,
  pg_get_functiondef(
    'public.get_league_standings_v2(uuid)'::regprocedure
  ) ilike '%minimum_played = readiness.maximum_played%'
    as balanced_matches_ready,
  pg_get_functiondef(
    'public.get_league_standings_v2(uuid)'::regprocedure
  ) ilike '%fantasy_points%'
    as fantasy_points_ready,
  pg_get_functiondef(
    'public.get_league_standings_v2(uuid)'::regprocedure
  ) ilike '%goal_difference%'
    as goal_difference_ready,
  pg_get_functiondef(
    'public.get_league_standings(uuid)'::regprocedure
  ) ilike '%get_league_standings_v2%'
    as legacy_consumers_aligned,
  to_regprocedure(
    'public.update_league_settings_v8(uuid,boolean,integer,integer,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,integer,integer,integer,integer,integer,boolean,integer,boolean,numeric,boolean,numeric[],text)'
  ) is not null as settings_v8_ready,
  has_function_privilege(
    'authenticated',
    'public.update_league_settings_v8(uuid,boolean,integer,integer,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,integer,integer,integer,integer,integer,boolean,integer,boolean,numeric,boolean,numeric[],text)',
    'EXECUTE'
  ) as settings_access_ready,
  pg_get_functiondef(
    'public.update_league_settings_v8(uuid,boolean,integer,integer,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,integer,integer,integer,integer,integer,boolean,integer,boolean,numeric,boolean,numeric[],text)'::regprocedure
  ) ilike '%Criterio di classifica non valido%'
    as tiebreaker_validation_ready,
  pg_get_functiondef(
    'public.update_league_settings_v8(uuid,boolean,integer,integer,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,integer,integer,integer,integer,integer,boolean,integer,boolean,numeric,boolean,numeric[],text)'::regprocedure
  ) ilike '%standings_tiebreaker%'
    as tiebreaker_persistence_ready;
