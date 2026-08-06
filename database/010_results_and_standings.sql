-- LEGHEVO · risultati automatici e classifica
-- Eseguire nel SQL Editor di Supabase dopo 009.

create or replace function public.fantasy_goals_from_points(
  p_points numeric,
  p_scoring_rules jsonb default '{}'::jsonb
)
returns smallint
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_threshold numeric :=
    coalesce((p_scoring_rules ->> 'goal_threshold')::numeric, 66);
  v_step numeric :=
    coalesce((p_scoring_rules ->> 'goal_step')::numeric, 6);
begin
  if p_points is null then
    return null;
  end if;

  if v_step <= 0 then
    v_step := 6;
  end if;

  if p_points < v_threshold then
    return 0;
  end if;

  return (
    floor((p_points - v_threshold) / v_step) + 1
  )::smallint;
end;
$$;

create or replace function public.calculate_team_matchday_points(
  p_fantasy_team_id uuid,
  p_matchday_id uuid
)
returns table (
  total_points numeric,
  is_ready boolean,
  counted_players integer
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_lineup_id uuid;
  v_mode public.league_mode;
  v_starter_count integer;
  v_starter record;
  v_score record;
  v_substitute record;
  v_used_bench_ids uuid[] := array[]::uuid[];
begin
  total_points := 0;
  is_ready := true;
  counted_players := 0;

  select lineup.id, league.mode
  into v_lineup_id, v_mode
  from public.lineups lineup
  join public.fantasy_teams team
    on team.id = lineup.fantasy_team_id
  join public.leagues league
    on league.id = team.league_id
  where lineup.fantasy_team_id = p_fantasy_team_id
    and lineup.matchday_id = p_matchday_id
    and lineup.status in ('submitted', 'locked');

  if not found then
    total_points := null;
    is_ready := false;
    return next;
    return;
  end if;

  select count(*)::integer
  into v_starter_count
  from public.lineup_entries entry
  where entry.lineup_id = v_lineup_id
    and entry.is_starter;

  if v_starter_count <> 11 then
    is_ready := false;
  end if;

  for v_starter in
    select entry.athlete_id, entry.slot
    from public.lineup_entries entry
    where entry.lineup_id = v_lineup_id
      and entry.is_starter
    order by entry.slot
  loop
    select
      score.athlete_id,
      score.fantasy_score,
      score.is_final
    into v_score
    from public.player_match_scores score
    where score.athlete_id = v_starter.athlete_id
      and score.matchday_id = p_matchday_id
      and score.fantasy_score is not null;

    if found then
      total_points := total_points + v_score.fantasy_score;
      counted_players := counted_players + 1;
      is_ready := is_ready and v_score.is_final;
      continue;
    end if;

    select
      bench.athlete_id,
      score.fantasy_score,
      score.is_final
    into v_substitute
    from public.lineup_entries bench
    join public.player_match_scores score
      on score.athlete_id = bench.athlete_id
      and score.matchday_id = p_matchday_id
      and score.fantasy_score is not null
    where bench.lineup_id = v_lineup_id
      and not bench.is_starter
      and not (bench.athlete_id = any(v_used_bench_ids))
      and exists (
        select 1
        from public.athlete_roles starter_role
        join public.athlete_roles bench_role
          on bench_role.mode = starter_role.mode
          and bench_role.role_code = starter_role.role_code
        where starter_role.athlete_id = v_starter.athlete_id
          and bench_role.athlete_id = bench.athlete_id
          and starter_role.mode = v_mode
      )
    order by bench.slot
    limit 1;

    if found then
      v_used_bench_ids :=
        array_append(v_used_bench_ids, v_substitute.athlete_id);
      total_points := total_points + v_substitute.fantasy_score;
      counted_players := counted_players + 1;
      is_ready := is_ready and v_substitute.is_final;
    else
      is_ready := false;
    end if;
  end loop;

  if counted_players = 0 then
    total_points := null;
  else
    total_points := round(total_points, 2);
  end if;

  if counted_players <> 11 then
    is_ready := false;
  end if;

  return next;
end;
$$;

revoke all on function public.calculate_team_matchday_points(uuid, uuid)
from public, anon, authenticated;

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
  v_home_bonus numeric;
  v_updated integer := 0;
begin
  for v_fixture in
    select
      fixture.id,
      fixture.home_team_id,
      fixture.away_team_id,
      league.scoring_rules
    from public.fantasy_fixtures fixture
    join public.leagues league on league.id = fixture.league_id
    where fixture.matchday_id = p_matchday_id
    for update of fixture
  loop
    select calculation.total_points, calculation.is_ready
    into v_home_points, v_home_ready
    from public.calculate_team_matchday_points(
      v_fixture.home_team_id,
      p_matchday_id
    ) calculation;

    select calculation.total_points, calculation.is_ready
    into v_away_points, v_away_ready
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
      finalized_at = case
        when v_home_ready and v_away_ready then
          coalesce(finalized_at, now())
        else null
      end
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
    from public.fantasy_fixtures fixture
    where fixture.league_id = p_league_id
      and fixture.matchday_id = p_matchday_id
  ) then
    raise exception 'Giornata non trovata nel calendario della lega.';
  end if;

  return public.refresh_matchday_results_internal(p_matchday_id);
end;
$$;

revoke all on function public.recalculate_league_matchday(uuid, uuid)
from public;

grant execute on function public.recalculate_league_matchday(uuid, uuid)
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
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'Devi effettuare l''accesso.';
  end if;

  if not public.is_league_member(p_league_id)
    and not public.is_league_admin(p_league_id) then
    raise exception 'Non fai parte di questa lega.';
  end if;

  return query
  with team_results as (
    select
      fixture.home_team_id as team_id,
      fixture.home_goals as scored,
      fixture.away_goals as conceded,
      fixture.home_points as fantasy_points,
      case when fixture.home_goals > fixture.away_goals then 1 else 0 end as win,
      case when fixture.home_goals = fixture.away_goals then 1 else 0 end as draw,
      case when fixture.home_goals < fixture.away_goals then 1 else 0 end as loss
    from public.fantasy_fixtures fixture
    where fixture.league_id = p_league_id
      and fixture.finalized_at is not null

    union all

    select
      fixture.away_team_id as team_id,
      fixture.away_goals as scored,
      fixture.home_goals as conceded,
      fixture.away_points as fantasy_points,
      case when fixture.away_goals > fixture.home_goals then 1 else 0 end as win,
      case when fixture.away_goals = fixture.home_goals then 1 else 0 end as draw,
      case when fixture.away_goals < fixture.home_goals then 1 else 0 end as loss
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
      coalesce(total.points_for, 0)::numeric as points_for,
      coalesce(total.league_points, 0)::integer as league_points
    from public.fantasy_teams team
    left join totals total on total.team_id = team.id
    where team.league_id = p_league_id
  )
  select
    row_number() over (
      order by
        standing.league_points desc,
        (standing.goals_for - standing.goals_against) desc,
        standing.goals_for desc,
        standing.points_for desc,
        standing.name
    )::integer,
    standing.team_id,
    standing.name,
    standing.played,
    standing.won,
    standing.drawn,
    standing.lost,
    standing.goals_for,
    standing.goals_against,
    standing.points_for,
    standing.league_points
  from standings standing
  order by 1;
end;
$$;

revoke all on function public.get_league_standings(uuid) from public;
grant execute on function public.get_league_standings(uuid) to authenticated;

create or replace function public.refresh_results_after_score_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_matchday_id uuid;
begin
  if tg_op = 'DELETE' then
    v_matchday_id := old.matchday_id;
  else
    v_matchday_id := new.matchday_id;
  end if;

  perform public.refresh_matchday_results_internal(v_matchday_id);

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

revoke all on function public.refresh_results_after_score_change()
from public, anon, authenticated;

drop trigger if exists player_scores_refresh_fantasy_results
on public.player_match_scores;

create trigger player_scores_refresh_fantasy_results
after insert or update of fantasy_score, is_final or delete
on public.player_match_scores
for each row execute function public.refresh_results_after_score_change();

create or replace function public.refresh_results_after_lineup_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_lineup_id uuid;
  v_matchday_id uuid;
begin
  if tg_op = 'DELETE' then
    v_lineup_id := old.lineup_id;
  else
    v_lineup_id := new.lineup_id;
  end if;

  select lineup.matchday_id
  into v_matchday_id
  from public.lineups lineup
  where lineup.id = v_lineup_id;

  if v_matchday_id is not null then
    perform public.refresh_matchday_results_internal(v_matchday_id);
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

revoke all on function public.refresh_results_after_lineup_change()
from public, anon, authenticated;

drop trigger if exists lineup_entries_refresh_fantasy_results
on public.lineup_entries;

create trigger lineup_entries_refresh_fantasy_results
after insert or update or delete
on public.lineup_entries
for each row execute function public.refresh_results_after_lineup_change();

do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'fantasy_fixtures'
  ) then
    alter publication supabase_realtime
      add table public.fantasy_fixtures;
  end if;
end;
$$;

do $$
declare
  v_matchday_id uuid;
begin
  for v_matchday_id in
    select distinct fixture.matchday_id
    from public.fantasy_fixtures fixture
  loop
    perform public.refresh_matchday_results_internal(v_matchday_id);
  end loop;
end;
$$;

select
  to_regprocedure(
    'public.recalculate_league_matchday(uuid,uuid)'
  ) is not null as results_engine_ready,
  to_regprocedure(
    'public.get_league_standings(uuid)'
  ) is not null as standings_engine_ready,
  to_regprocedure(
    'public.calculate_team_matchday_points(uuid,uuid)'
  ) is not null as substitutions_ready,
  exists (
    select 1
    from pg_trigger
    where tgname = 'player_scores_refresh_fantasy_results'
      and not tgisinternal
  ) as score_automation_ready,
  exists (
    select 1
    from pg_trigger
    where tgname = 'lineup_entries_refresh_fantasy_results'
      and not tgisinternal
  ) as lineup_automation_ready;
