-- LEGHEVO · Bacheca unificata di campionato, Coppa e Supercoppa
-- Eseguire nel SQL Editor di Supabase dopo 045.
-- Lo script aggiunge una lettura protetta dei verdetti già ufficiali:
-- non crea trofei e non modifica leghe, classifiche o tabelloni.

create or replace function public.get_league_trophy_cabinet(
  p_league_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_requested_league public.leagues%rowtype;
  v_root_league_id uuid;
  v_latest_league_id uuid;
  v_total_trophies integer := 0;
  v_league_titles integer := 0;
  v_cup_titles integer := 0;
  v_super_cup_titles integer := 0;
  v_unique_winners integer := 0;
  v_double_count integer := 0;
  v_leaders jsonb := '[]'::jsonb;
  v_timeline jsonb := '[]'::jsonb;
begin
  if auth.uid() is null then
    raise exception 'Devi effettuare l''accesso.';
  end if;

  if not public.is_league_member(p_league_id)
    and not public.is_league_admin(p_league_id) then
    raise exception 'Non fai parte di questa lega.';
  end if;

  select league.*
  into v_requested_league
  from public.leagues league
  where league.id = p_league_id;

  if not found then
    raise exception 'Lega non trovata.';
  end if;

  with recursive ancestors as (
    select league.id, league.previous_league_id
    from public.leagues league
    where league.id = p_league_id

    union

    select previous.id, previous.previous_league_id
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
    select league.id, league.previous_league_id, 1 as sequence
    from public.leagues league
    where league.id = v_root_league_id

    union all

    select
      renewed.id,
      renewed.previous_league_id,
      current_season.sequence + 1
    from season_chain current_season
    join public.leagues renewed
      on renewed.previous_league_id = current_season.id
  )
  select chain.id
  into v_latest_league_id
  from season_chain chain
  order by chain.sequence desc
  limit 1;

  with recursive season_chain as (
    select league.id, league.previous_league_id, 1 as sequence
    from public.leagues league
    where league.id = v_root_league_id

    union all

    select
      renewed.id,
      renewed.previous_league_id,
      current_season.sequence + 1
    from season_chain current_season
    join public.leagues renewed
      on renewed.previous_league_id = current_season.id
  ),
  league_honours as (
    select
      'league'::text as competition,
      summary.league_id::text as trophy_id,
      chain.sequence,
      league.id as league_id,
      coalesce(summary.season, league.calendar_season) as season,
      null::text as source_season,
      summary.completed_at,
      winner_team.id as winner_team_id,
      winner_team.name as winner_team_name,
      winner_team.manager_id as winner_manager_id,
      coalesce(
        winner_profile.display_name,
        summary.champion_manager_name,
        'Manager'
      ) as winner_manager_name,
      runner_team.id as runner_team_id,
      coalesce(
        runner_team.name,
        summary.final_standings -> 1 ->> 'teamName'
      ) as runner_team_name,
      runner_team.manager_id as runner_manager_id,
      coalesce(
        runner_profile.display_name,
        summary.final_standings -> 1 ->> 'managerName',
        'Manager'
      ) as runner_manager_name
    from season_chain chain
    join public.leagues league on league.id = chain.id
    join public.league_season_summaries summary
      on summary.league_id = league.id
    join public.fantasy_teams winner_team
      on winner_team.id = summary.champion_team_id
    left join public.profiles winner_profile
      on winner_profile.id = winner_team.manager_id
    left join public.fantasy_teams runner_team
      on runner_team.id = nullif(
        summary.final_standings -> 1 ->> 'teamId',
        ''
      )::uuid
    left join public.profiles runner_profile
      on runner_profile.id = runner_team.manager_id
  ),
  cup_honours as (
    select
      'cup'::text as competition,
      cup.id::text as trophy_id,
      chain.sequence,
      league.id as league_id,
      coalesce(summary.season, league.calendar_season) as season,
      null::text as source_season,
      cup.completed_at,
      winner_team.id as winner_team_id,
      winner_team.name as winner_team_name,
      winner_team.manager_id as winner_manager_id,
      coalesce(winner_profile.display_name, 'Manager')
        as winner_manager_name,
      runner_team.id as runner_team_id,
      runner_team.name as runner_team_name,
      runner_team.manager_id as runner_manager_id,
      coalesce(runner_profile.display_name, 'Manager')
        as runner_manager_name
    from season_chain chain
    join public.leagues league on league.id = chain.id
    join public.league_cups cup
      on cup.league_id = league.id
      and cup.status = 'completed'
    left join public.league_season_summaries summary
      on summary.league_id = league.id
    join public.fantasy_teams winner_team
      on winner_team.id = cup.champion_team_id
    left join public.profiles winner_profile
      on winner_profile.id = winner_team.manager_id
    left join public.fantasy_teams runner_team
      on runner_team.id = cup.runner_up_team_id
    left join public.profiles runner_profile
      on runner_profile.id = runner_team.manager_id
  ),
  super_cup_honours as (
    select
      'super_cup'::text as competition,
      super_cup.id::text as trophy_id,
      chain.sequence,
      league.id as league_id,
      league.calendar_season as season,
      source_summary.season as source_season,
      super_cup.completed_at,
      winner_team.id as winner_team_id,
      winner_team.name as winner_team_name,
      winner_team.manager_id as winner_manager_id,
      coalesce(winner_profile.display_name, 'Manager')
        as winner_manager_name,
      runner_team.id as runner_team_id,
      runner_team.name as runner_team_name,
      runner_team.manager_id as runner_manager_id,
      coalesce(runner_profile.display_name, 'Manager')
        as runner_manager_name
    from season_chain chain
    join public.leagues league on league.id = chain.id
    join public.league_super_cups super_cup
      on super_cup.league_id = league.id
      and super_cup.status = 'completed'
    left join public.league_season_summaries source_summary
      on source_summary.league_id = super_cup.source_league_id
    join public.fantasy_teams winner_team
      on winner_team.id = super_cup.winner_team_id
    left join public.profiles winner_profile
      on winner_profile.id = winner_team.manager_id
    left join public.fantasy_teams runner_team
      on runner_team.id = super_cup.runner_up_team_id
    left join public.profiles runner_profile
      on runner_profile.id = runner_team.manager_id
  ),
  title_rows as (
    select * from league_honours
    union all
    select * from cup_honours
    union all
    select * from super_cup_honours
  )
  select
    count(*)::integer,
    count(*) filter (
      where title.competition = 'league'
    )::integer,
    count(*) filter (
      where title.competition = 'cup'
    )::integer,
    count(*) filter (
      where title.competition = 'super_cup'
    )::integer,
    count(distinct title.winner_manager_id)::integer,
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'id', title.competition || '-' || title.trophy_id,
          'competition', title.competition,
          'leagueId', title.league_id,
          'season', title.season,
          'sourceSeason', title.source_season,
          'completedAt', title.completed_at,
          'winner', jsonb_build_object(
            'teamId', title.winner_team_id,
            'teamName', title.winner_team_name,
            'managerId', title.winner_manager_id,
            'managerName', title.winner_manager_name
          ),
          'runnerUp',
            case
              when title.runner_team_id is null then null
              else jsonb_build_object(
                'teamId', title.runner_team_id,
                'teamName', title.runner_team_name,
                'managerId', title.runner_manager_id,
                'managerName', title.runner_manager_name
              )
            end
        )
        order by
          title.completed_at desc nulls last,
          title.sequence desc,
          case title.competition
            when 'league' then 1
            when 'cup' then 2
            else 3
          end
      ),
      '[]'::jsonb
    )
  into
    v_total_trophies,
    v_league_titles,
    v_cup_titles,
    v_super_cup_titles,
    v_unique_winners,
    v_timeline
  from title_rows title;

  with recursive season_chain as (
    select league.id, league.previous_league_id, 1 as sequence
    from public.leagues league
    where league.id = v_root_league_id

    union all

    select
      renewed.id,
      renewed.previous_league_id,
      current_season.sequence + 1
    from season_chain current_season
    join public.leagues renewed
      on renewed.previous_league_id = current_season.id
  ),
  managers as (
    select distinct team.manager_id
    from season_chain chain
    join public.fantasy_teams team on team.league_id = chain.id
  ),
  manager_teams as (
    select
      team.manager_id,
      array_agg(distinct team.name order by team.name) as team_names
    from season_chain chain
    join public.fantasy_teams team on team.league_id = chain.id
    group by team.manager_id
  ),
  league_winners as (
    select
      summary.league_id,
      coalesce(summary.season, league.calendar_season) as season,
      team.manager_id
    from season_chain chain
    join public.leagues league on league.id = chain.id
    join public.league_season_summaries summary
      on summary.league_id = league.id
    join public.fantasy_teams team
      on team.id = summary.champion_team_id
  ),
  cup_winners as (
    select
      cup.league_id,
      coalesce(summary.season, league.calendar_season) as season,
      team.manager_id
    from season_chain chain
    join public.leagues league on league.id = chain.id
    join public.league_cups cup
      on cup.league_id = league.id
      and cup.status = 'completed'
    left join public.league_season_summaries summary
      on summary.league_id = league.id
    join public.fantasy_teams team
      on team.id = cup.champion_team_id
  ),
  super_cup_winners as (
    select
      super_cup.league_id,
      league.calendar_season as season,
      team.manager_id
    from season_chain chain
    join public.leagues league on league.id = chain.id
    join public.league_super_cups super_cup
      on super_cup.league_id = league.id
      and super_cup.status = 'completed'
    join public.fantasy_teams team
      on team.id = super_cup.winner_team_id
  ),
  league_title_counts as (
    select winner.manager_id, count(*)::integer as titles
    from league_winners winner
    group by winner.manager_id
  ),
  cup_title_counts as (
    select winner.manager_id, count(*)::integer as titles
    from cup_winners winner
    group by winner.manager_id
  ),
  super_cup_title_counts as (
    select winner.manager_id, count(*)::integer as titles
    from super_cup_winners winner
    group by winner.manager_id
  ),
  league_podium_counts as (
    select
      team.manager_id,
      count(*)::integer as podiums
    from season_chain chain
    join public.league_season_summaries summary
      on summary.league_id = chain.id
    cross join lateral jsonb_array_elements(
      summary.final_standings
    ) with ordinality as standing(item, ordinality)
    join public.fantasy_teams team
      on team.id = nullif(standing.item ->> 'teamId', '')::uuid
    where standing.ordinality <= 3
    group by team.manager_id
  ),
  cup_finalists as (
    select champion.manager_id
    from season_chain chain
    join public.league_cups cup
      on cup.league_id = chain.id
      and cup.status = 'completed'
    join public.fantasy_teams champion
      on champion.id = cup.champion_team_id

    union all

    select runner_up.manager_id
    from season_chain chain
    join public.league_cups cup
      on cup.league_id = chain.id
      and cup.status = 'completed'
    join public.fantasy_teams runner_up
      on runner_up.id = cup.runner_up_team_id
  ),
  cup_final_counts as (
    select finalist.manager_id, count(*)::integer as finals
    from cup_finalists finalist
    group by finalist.manager_id
  ),
  super_cup_finalists as (
    select champion.manager_id
    from season_chain chain
    join public.league_super_cups super_cup
      on super_cup.league_id = chain.id
      and super_cup.status = 'completed'
    join public.fantasy_teams champion
      on champion.id = super_cup.winner_team_id

    union all

    select runner_up.manager_id
    from season_chain chain
    join public.league_super_cups super_cup
      on super_cup.league_id = chain.id
      and super_cup.status = 'completed'
    join public.fantasy_teams runner_up
      on runner_up.id = super_cup.runner_up_team_id
  ),
  super_cup_final_counts as (
    select finalist.manager_id, count(*)::integer as finals
    from super_cup_finalists finalist
    group by finalist.manager_id
  ),
  double_counts as (
    select
      league_winner.manager_id,
      count(*)::integer as doubles
    from league_winners league_winner
    join cup_winners cup_winner
      on cup_winner.league_id = league_winner.league_id
      and cup_winner.manager_id = league_winner.manager_id
    group by league_winner.manager_id
  ),
  winner_seasons as (
    select winner.manager_id, winner.season from league_winners winner
    union all
    select winner.manager_id, winner.season from cup_winners winner
    union all
    select winner.manager_id, winner.season from super_cup_winners winner
  ),
  title_seasons as (
    select
      winner.manager_id,
      coalesce(
        array_agg(
          distinct winner.season
          order by winner.season
        ) filter (where winner.season is not null),
        array[]::text[]
      ) as seasons
    from winner_seasons winner
    group by winner.manager_id
  ),
  scored as (
    select
      manager.manager_id,
      coalesce(profile.display_name, 'Manager') as manager_name,
      coalesce(league_titles.titles, 0) as league_titles,
      coalesce(cup_titles.titles, 0) as cup_titles,
      coalesce(super_cup_titles.titles, 0) as super_cup_titles,
      coalesce(league_podiums.podiums, 0) as league_podiums,
      coalesce(cup_finals.finals, 0) as cup_finals,
      coalesce(super_cup_finals.finals, 0) as super_cup_finals,
      coalesce(doubles.doubles, 0) as doubles,
      coalesce(teams.team_names, array[]::text[]) as team_names,
      coalesce(seasons.seasons, array[]::text[]) as seasons,
      coalesce(league_titles.titles, 0)
        + coalesce(cup_titles.titles, 0)
        + coalesce(super_cup_titles.titles, 0)
        as total_trophies
    from managers manager
    left join public.profiles profile
      on profile.id = manager.manager_id
    left join manager_teams teams
      on teams.manager_id = manager.manager_id
    left join league_title_counts league_titles
      on league_titles.manager_id = manager.manager_id
    left join cup_title_counts cup_titles
      on cup_titles.manager_id = manager.manager_id
    left join super_cup_title_counts super_cup_titles
      on super_cup_titles.manager_id = manager.manager_id
    left join league_podium_counts league_podiums
      on league_podiums.manager_id = manager.manager_id
    left join cup_final_counts cup_finals
      on cup_finals.manager_id = manager.manager_id
    left join super_cup_final_counts super_cup_finals
      on super_cup_finals.manager_id = manager.manager_id
    left join double_counts doubles
      on doubles.manager_id = manager.manager_id
    left join title_seasons seasons
      on seasons.manager_id = manager.manager_id
  ),
  ranked as (
    select
      scored.*,
      dense_rank() over (
        order by
          scored.total_trophies desc,
          scored.league_titles desc,
          scored.cup_titles desc,
          scored.super_cup_titles desc
      )::integer as rank
    from scored
    where scored.total_trophies > 0
      or scored.league_podiums > 0
      or scored.cup_finals > 0
      or scored.super_cup_finals > 0
  )
  select
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'rank', leader.rank,
          'managerId', leader.manager_id,
          'managerName', leader.manager_name,
          'totalTrophies', leader.total_trophies,
          'leagueTitles', leader.league_titles,
          'cupTitles', leader.cup_titles,
          'superCupTitles', leader.super_cup_titles,
          'leaguePodiums', leader.league_podiums,
          'cupFinals', leader.cup_finals,
          'superCupFinals', leader.super_cup_finals,
          'doubles', leader.doubles,
          'teamNames', leader.team_names,
          'seasons', leader.seasons
        )
        order by leader.rank, leader.manager_name, leader.manager_id
      ),
      '[]'::jsonb
    ),
    coalesce(sum(leader.doubles), 0)::integer
  into v_leaders, v_double_count
  from ranked leader;

  return jsonb_build_object(
    'leagueName', v_requested_league.name,
    'selectedLeagueId', p_league_id,
    'latestLeagueId', v_latest_league_id,
    'totalTrophies', v_total_trophies,
    'leagueTitles', v_league_titles,
    'cupTitles', v_cup_titles,
    'superCupTitles', v_super_cup_titles,
    'uniqueWinners', v_unique_winners,
    'doubles', v_double_count,
    'leaders', v_leaders,
    'timeline', v_timeline
  );
end;
$$;

revoke all on function public.get_league_trophy_cabinet(uuid)
from public, anon, authenticated;

grant execute on function public.get_league_trophy_cabinet(uuid)
to authenticated;

select
  to_regprocedure(
    'public.get_league_trophy_cabinet(uuid)'
  ) is not null as trophy_cabinet_function_ready,
  exists (
    select 1
    from information_schema.routines routine
    where routine.routine_schema = 'public'
      and routine.routine_name = 'get_league_trophy_cabinet'
      and routine.security_type = 'DEFINER'
  ) as trophy_cabinet_security_ready,
  exists (
    select 1
    from pg_proc procedure
    join pg_namespace namespace
      on namespace.oid = procedure.pronamespace
    where namespace.nspname = 'public'
      and procedure.proname = 'get_league_trophy_cabinet'
      and procedure.provolatile = 's'
  ) as trophy_cabinet_stable_ready,
  has_function_privilege(
    'authenticated',
    'public.get_league_trophy_cabinet(uuid)',
    'EXECUTE'
  ) as trophy_cabinet_member_access_ready,
  not has_function_privilege(
    'anon',
    'public.get_league_trophy_cabinet(uuid)',
    'EXECUTE'
  ) as anonymous_trophy_cabinet_blocked,
  to_regclass('public.league_season_summaries') is not null
    as league_titles_source_ready,
  to_regclass('public.league_cups') is not null
    as cup_titles_source_ready,
  to_regclass('public.league_super_cups') is not null
    as super_cup_titles_source_ready,
  exists (
    select 1
    from information_schema.columns column_info
    where column_info.table_schema = 'public'
      and column_info.table_name = 'leagues'
      and column_info.column_name = 'previous_league_id'
  ) as season_chain_ready,
  exists (
    select 1
    from information_schema.columns column_info
    where column_info.table_schema = 'public'
      and column_info.table_name = 'league_season_summaries'
      and column_info.column_name = 'final_standings'
  ) as league_podium_source_ready,
  exists (
    select 1
    from information_schema.columns column_info
    where column_info.table_schema = 'public'
      and column_info.table_name = 'league_cups'
      and column_info.column_name = 'runner_up_team_id'
  ) as cup_finalists_source_ready,
  exists (
    select 1
    from information_schema.columns column_info
    where column_info.table_schema = 'public'
      and column_info.table_name = 'league_super_cups'
      and column_info.column_name = 'runner_up_team_id'
  ) as super_cup_finalists_source_ready;
