-- LEGHEVO · storico, record e carriera dei Playoff Scudetto
-- Eseguire nel SQL Editor di Supabase dopo 047.
-- Lo script legge esclusivamente Playoff e tabelloni esistenti:
-- non configura competizioni e non modifica risultati, rose o classifiche.

create or replace function public.get_league_playoff_history(
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
  v_latest_league_id uuid;
  v_league_name text;
  v_completed_playoffs integer := 0;
  v_active_playoffs integer := 0;
  v_configured_playoffs integer := 0;
  v_seasons jsonb := '[]'::jsonb;
  v_title_leaders jsonb := '[]'::jsonb;
  v_career_leaders jsonb := '[]'::jsonb;
  v_match_records jsonb := '[]'::jsonb;
begin
  if auth.uid() is null then
    raise exception 'Devi effettuare l''accesso.';
  end if;

  if not public.is_league_member(p_league_id)
    and not public.is_league_admin(p_league_id) then
    raise exception 'Non fai parte di questa lega.';
  end if;

  select league.name
  into v_league_name
  from public.leagues league
  where league.id = p_league_id;

  if not found then
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
    select
      league.id,
      league.previous_league_id,
      1 as sequence
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
    select
      league.id,
      league.previous_league_id,
      1 as sequence
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
  season_rows as (
    select
      chain.sequence,
      league.id as league_id,
      coalesce(summary.season, league.calendar_season) as season,
      league.status as league_status,
      playoff.id as playoff_id,
      playoff.status as playoff_status,
      playoff.configured_at,
      playoff.started_at,
      playoff.completed_at,
      coalesce(playoff.participant_count, 0) as participant_count,
      coalesce(playoff.round_count, 0) as round_count,
      coalesce(playoff.current_round, 0) as current_round,
      champion.id as champion_team_id,
      champion.name as champion_team_name,
      champion.manager_id as champion_manager_id,
      coalesce(champion_profile.display_name, 'Manager')
        as champion_manager_name,
      champion_entry.seed as champion_seed,
      champion_entry.regular_season_position
        as champion_regular_position,
      runner_up.id as runner_up_team_id,
      runner_up.name as runner_up_team_name,
      runner_up.manager_id as runner_up_manager_id,
      coalesce(runner_up_profile.display_name, 'Manager')
        as runner_up_manager_name,
      runner_up_entry.seed as runner_up_seed,
      runner_up_entry.regular_season_position
        as runner_up_regular_position,
      regular_leader.id as regular_leader_team_id,
      regular_leader.name as regular_leader_team_name,
      regular_leader.manager_id as regular_leader_manager_id,
      coalesce(regular_leader_profile.display_name, 'Manager')
        as regular_leader_manager_name,
      (
        select count(*)::integer
        from public.league_playoff_rounds playoff_round
        join public.league_playoff_ties tie
          on tie.round_id = playoff_round.id
        where playoff_round.playoff_id = playoff.id
      ) as total_tie_count,
      (
        select count(*)::integer
        from public.league_playoff_rounds playoff_round
        join public.league_playoff_ties tie
          on tie.round_id = playoff_round.id
        where playoff_round.playoff_id = playoff.id
          and tie.finalized_at is not null
      ) as official_tie_count
    from season_chain chain
    join public.leagues league on league.id = chain.id
    left join public.league_season_summaries summary
      on summary.league_id = league.id
    left join public.league_playoffs playoff
      on playoff.league_id = league.id
    left join public.fantasy_teams champion
      on champion.id = playoff.champion_team_id
    left join public.profiles champion_profile
      on champion_profile.id = champion.manager_id
    left join public.league_playoff_entries champion_entry
      on champion_entry.playoff_id = playoff.id
      and champion_entry.fantasy_team_id = champion.id
    left join public.fantasy_teams runner_up
      on runner_up.id = playoff.runner_up_team_id
    left join public.profiles runner_up_profile
      on runner_up_profile.id = runner_up.manager_id
    left join public.league_playoff_entries runner_up_entry
      on runner_up_entry.playoff_id = playoff.id
      and runner_up_entry.fantasy_team_id = runner_up.id
    left join public.league_playoff_entries regular_leader_entry
      on regular_leader_entry.playoff_id = playoff.id
      and regular_leader_entry.seed = 1
    left join public.fantasy_teams regular_leader
      on regular_leader.id = regular_leader_entry.fantasy_team_id
    left join public.profiles regular_leader_profile
      on regular_leader_profile.id = regular_leader.manager_id
  )
  select
    count(*) filter (
      where season_row.playoff_status = 'completed'
    )::integer,
    count(*) filter (
      where season_row.playoff_status = 'active'
    )::integer,
    count(*) filter (
      where season_row.playoff_status = 'configured'
    )::integer,
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'leagueId', season_row.league_id,
          'season', season_row.season,
          'leagueStatus', season_row.league_status,
          'playoffExists', season_row.playoff_id is not null,
          'playoffId', season_row.playoff_id,
          'playoffStatus',
            coalesce(season_row.playoff_status, 'not_configured'),
          'configuredAt', season_row.configured_at,
          'startedAt', season_row.started_at,
          'completedAt', season_row.completed_at,
          'participantCount', season_row.participant_count,
          'roundCount', season_row.round_count,
          'currentRound', season_row.current_round,
          'totalTieCount', coalesce(season_row.total_tie_count, 0),
          'officialTieCount', coalesce(season_row.official_tie_count, 0),
          'champion',
            case
              when season_row.champion_team_id is null then null
              else jsonb_build_object(
                'teamId', season_row.champion_team_id,
                'teamName', season_row.champion_team_name,
                'managerId', season_row.champion_manager_id,
                'managerName', season_row.champion_manager_name,
                'seed', season_row.champion_seed,
                'regularSeasonPosition',
                  season_row.champion_regular_position
              )
            end,
          'runnerUp',
            case
              when season_row.runner_up_team_id is null then null
              else jsonb_build_object(
                'teamId', season_row.runner_up_team_id,
                'teamName', season_row.runner_up_team_name,
                'managerId', season_row.runner_up_manager_id,
                'managerName', season_row.runner_up_manager_name,
                'seed', season_row.runner_up_seed,
                'regularSeasonPosition',
                  season_row.runner_up_regular_position
              )
            end,
          'regularSeasonLeader',
            case
              when season_row.regular_leader_team_id is null then null
              else jsonb_build_object(
                'teamId', season_row.regular_leader_team_id,
                'teamName', season_row.regular_leader_team_name,
                'managerId', season_row.regular_leader_manager_id,
                'managerName', season_row.regular_leader_manager_name,
                'seed', 1,
                'regularSeasonPosition', 1
              )
            end,
          'isSelected', season_row.league_id = p_league_id,
          'isLatest', season_row.league_id = v_latest_league_id
        )
        order by season_row.sequence desc
      ),
      '[]'::jsonb
    )
  into
    v_completed_playoffs,
    v_active_playoffs,
    v_configured_playoffs,
    v_seasons
  from season_rows season_row;

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
  completed_playoffs as (
    select
      playoff.id,
      playoff.champion_team_id,
      playoff.runner_up_team_id,
      coalesce(summary.season, league.calendar_season) as season
    from season_chain chain
    join public.leagues league on league.id = chain.id
    join public.league_playoffs playoff
      on playoff.league_id = league.id
      and playoff.status = 'completed'
    left join public.league_season_summaries summary
      on summary.league_id = league.id
  ),
  finalists as (
    select
      playoff.id as playoff_id,
      playoff.season,
      team.manager_id,
      coalesce(profile.display_name, 'Manager') as manager_name,
      team.name as team_name,
      entry.seed,
      true as champion
    from completed_playoffs playoff
    join public.fantasy_teams team
      on team.id = playoff.champion_team_id
    join public.league_playoff_entries entry
      on entry.playoff_id = playoff.id
      and entry.fantasy_team_id = team.id
    left join public.profiles profile
      on profile.id = team.manager_id

    union all

    select
      playoff.id,
      playoff.season,
      team.manager_id,
      coalesce(profile.display_name, 'Manager'),
      team.name,
      entry.seed,
      false
    from completed_playoffs playoff
    join public.fantasy_teams team
      on team.id = playoff.runner_up_team_id
    join public.league_playoff_entries entry
      on entry.playoff_id = playoff.id
      and entry.fantasy_team_id = team.id
    left join public.profiles profile
      on profile.id = team.manager_id
  ),
  leader_rows as (
    select
      finalist.manager_id,
      max(finalist.manager_name) as manager_name,
      count(*) filter (where finalist.champion)::integer as titles,
      count(*)::integer as finals,
      count(*) filter (
        where finalist.champion and finalist.seed > 1
      )::integer as lower_seed_titles,
      array_agg(distinct finalist.team_name order by finalist.team_name)
        as team_names,
      array_agg(distinct finalist.season order by finalist.season)
        filter (where finalist.season is not null) as seasons
    from finalists finalist
    group by finalist.manager_id
  )
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'managerId', leader.manager_id,
        'managerName', leader.manager_name,
        'titles', leader.titles,
        'finals', leader.finals,
        'lowerSeedTitles', leader.lower_seed_titles,
        'teamNames', to_jsonb(leader.team_names),
        'seasons', to_jsonb(coalesce(leader.seasons, array[]::text[]))
      )
      order by
        leader.titles desc,
        leader.finals desc,
        leader.lower_seed_titles desc,
        leader.manager_name,
        leader.manager_id
    ),
    '[]'::jsonb
  )
  into v_title_leaders
  from leader_rows leader;

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
  completed_playoffs as (
    select
      playoff.id,
      playoff.champion_team_id,
      playoff.runner_up_team_id
    from season_chain chain
    join public.league_playoffs playoff
      on playoff.league_id = chain.id
      and playoff.status = 'completed'
  ),
  team_tie_rows as (
    select
      playoff_round.playoff_id,
      tie.home_team_id as team_id,
      1 as ties_played,
      case when tie.winner_team_id = tie.home_team_id then 1 else 0 end
        as ties_won
    from completed_playoffs playoff
    join public.league_playoff_rounds playoff_round
      on playoff_round.playoff_id = playoff.id
    join public.league_playoff_ties tie
      on tie.round_id = playoff_round.id
    where tie.finalized_at is not null
      and tie.home_team_id is not null

    union all

    select
      playoff_round.playoff_id,
      tie.away_team_id,
      1,
      case when tie.winner_team_id = tie.away_team_id then 1 else 0 end
    from completed_playoffs playoff
    join public.league_playoff_rounds playoff_round
      on playoff_round.playoff_id = playoff.id
    join public.league_playoff_ties tie
      on tie.round_id = playoff_round.id
    where tie.finalized_at is not null
      and tie.away_team_id is not null
  ),
  team_tie_totals as (
    select
      tie_row.playoff_id,
      tie_row.team_id,
      sum(tie_row.ties_played)::integer as ties_played,
      sum(tie_row.ties_won)::integer as ties_won
    from team_tie_rows tie_row
    group by tie_row.playoff_id, tie_row.team_id
  ),
  entry_rows as (
    select
      playoff.id as playoff_id,
      team.id as team_id,
      team.manager_id,
      coalesce(profile.display_name, 'Manager') as manager_name,
      team.name as team_name,
      entry.seed,
      playoff.champion_team_id,
      playoff.runner_up_team_id,
      coalesce(totals.ties_played, 0) as ties_played,
      coalesce(totals.ties_won, 0) as ties_won
    from completed_playoffs playoff
    join public.league_playoff_entries entry
      on entry.playoff_id = playoff.id
    join public.fantasy_teams team
      on team.id = entry.fantasy_team_id
    left join public.profiles profile
      on profile.id = team.manager_id
    left join team_tie_totals totals
      on totals.playoff_id = playoff.id
      and totals.team_id = team.id
  ),
  career_rows as (
    select
      entry.manager_id,
      max(entry.manager_name) as manager_name,
      count(distinct entry.playoff_id)::integer as participations,
      count(*) filter (
        where entry.team_id = entry.champion_team_id
      )::integer as titles,
      count(*) filter (
        where entry.team_id in (
          entry.champion_team_id,
          entry.runner_up_team_id
        )
      )::integer as finals,
      count(*) filter (
        where entry.team_id = entry.champion_team_id
          and entry.seed > 1
      )::integer as lower_seed_titles,
      sum(entry.ties_played)::integer as ties_played,
      sum(entry.ties_won)::integer as ties_won,
      round(
        case
          when sum(entry.ties_played) > 0
            then (
              sum(entry.ties_won)::numeric
              / sum(entry.ties_played)::numeric
            ) * 100
          else 0
        end,
        1
      ) as win_rate,
      array_agg(distinct entry.team_name order by entry.team_name)
        as team_names
    from entry_rows entry
    group by entry.manager_id
  ),
  ranked_careers as (
    select
      dense_rank() over (
        order by
          career.titles desc,
          career.finals desc,
          career.ties_won desc,
          career.win_rate desc
      )::integer as rank,
      career.*
    from career_rows career
  )
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'rank', career.rank,
        'managerId', career.manager_id,
        'managerName', career.manager_name,
        'participations', career.participations,
        'titles', career.titles,
        'finals', career.finals,
        'lowerSeedTitles', career.lower_seed_titles,
        'tiesPlayed', career.ties_played,
        'tiesWon', career.ties_won,
        'winRate', career.win_rate,
        'teamNames', to_jsonb(career.team_names)
      )
      order by
        career.rank,
        career.manager_name,
        career.manager_id
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
  tie_rows as (
    select
      tie.id as tie_id,
      coalesce(summary.season, league.calendar_season) as season,
      playoff.completed_at,
      playoff_round.round_number,
      playoff_round.name as round_name,
      matchday.number as matchday_number,
      tie.bracket_position,
      tie.home_team_id,
      home_team.name as home_team_name,
      home_team.manager_id as home_manager_id,
      coalesce(home_profile.display_name, 'Manager')
        as home_manager_name,
      tie.away_team_id,
      away_team.name as away_team_name,
      away_team.manager_id as away_manager_id,
      coalesce(away_profile.display_name, 'Manager')
        as away_manager_name,
      tie.home_points,
      tie.away_points,
      tie.home_goals,
      tie.away_goals,
      tie.winner_team_id,
      tie.decided_by
    from season_chain chain
    join public.leagues league on league.id = chain.id
    join public.league_playoffs playoff
      on playoff.league_id = league.id
      and playoff.status = 'completed'
    left join public.league_season_summaries summary
      on summary.league_id = league.id
    join public.league_playoff_rounds playoff_round
      on playoff_round.playoff_id = playoff.id
    join public.matchdays matchday
      on matchday.id = playoff_round.matchday_id
    join public.league_playoff_ties tie
      on tie.round_id = playoff_round.id
    join public.fantasy_teams home_team
      on home_team.id = tie.home_team_id
    left join public.profiles home_profile
      on home_profile.id = home_team.manager_id
    join public.fantasy_teams away_team
      on away_team.id = tie.away_team_id
    left join public.profiles away_profile
      on away_profile.id = away_team.manager_id
    where tie.finalized_at is not null
  ),
  record_candidates as (
    select
      'highest_score'::text as record_key,
      1 as display_order,
      match_row.home_points as record_value,
      match_row.*,
      match_row.home_team_id as team_id,
      match_row.home_team_name as team_name,
      match_row.home_manager_id as manager_id,
      match_row.home_manager_name as manager_name,
      match_row.away_team_name as opponent_name
    from tie_rows match_row

    union all

    select
      'highest_score',
      1,
      match_row.away_points,
      match_row.*,
      match_row.away_team_id,
      match_row.away_team_name,
      match_row.away_manager_id,
      match_row.away_manager_name,
      match_row.home_team_name
    from tie_rows match_row

    union all

    select
      'biggest_win',
      2,
      abs(match_row.home_goals - match_row.away_goals)::numeric,
      match_row.*,
      match_row.winner_team_id,
      case
        when match_row.winner_team_id = match_row.home_team_id
          then match_row.home_team_name
        else match_row.away_team_name
      end,
      case
        when match_row.winner_team_id = match_row.home_team_id
          then match_row.home_manager_id
        else match_row.away_manager_id
      end,
      case
        when match_row.winner_team_id = match_row.home_team_id
          then match_row.home_manager_name
        else match_row.away_manager_name
      end,
      case
        when match_row.winner_team_id = match_row.home_team_id
          then match_row.away_team_name
        else match_row.home_team_name
      end
    from tie_rows match_row

    union all

    select
      'highest_total_goals',
      3,
      (match_row.home_goals + match_row.away_goals)::numeric,
      match_row.*,
      match_row.winner_team_id,
      case
        when match_row.winner_team_id = match_row.home_team_id
          then match_row.home_team_name
        else match_row.away_team_name
      end,
      case
        when match_row.winner_team_id = match_row.home_team_id
          then match_row.home_manager_id
        else match_row.away_manager_id
      end,
      case
        when match_row.winner_team_id = match_row.home_team_id
          then match_row.home_manager_name
        else match_row.away_manager_name
      end,
      case
        when match_row.winner_team_id = match_row.home_team_id
          then match_row.away_team_name
        else match_row.home_team_name
      end
    from tie_rows match_row
  ),
  ranked_records as (
    select
      candidate.*,
      row_number() over (
        partition by candidate.record_key
        order by
          candidate.record_value desc,
          candidate.completed_at,
          candidate.season,
          candidate.round_number,
          candidate.bracket_position,
          candidate.tie_id,
          candidate.team_id
      ) as record_rank
    from record_candidates candidate
    where candidate.record_value is not null
  )
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'key', record.record_key,
        'value', record.record_value,
        'tieId', record.tie_id,
        'season', record.season,
        'matchdayNumber', record.matchday_number,
        'roundName', record.round_name,
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
        'awayGoals', record.away_goals,
        'decidedBy', record.decided_by
      )
      order by record.display_order
    ),
    '[]'::jsonb
  )
  into v_match_records
  from ranked_records record
  where record.record_rank = 1;

  return jsonb_build_object(
    'leagueName', v_league_name,
    'selectedLeagueId', p_league_id,
    'latestLeagueId', v_latest_league_id,
    'completedPlayoffs', v_completed_playoffs,
    'activePlayoffs', v_active_playoffs,
    'configuredPlayoffs', v_configured_playoffs,
    'seasons', v_seasons,
    'titleLeaders', v_title_leaders,
    'careerLeaders', v_career_leaders,
    'matchRecords', v_match_records
  );
end;
$$;

revoke all on function public.get_league_playoff_history(uuid)
from public, anon, authenticated;

grant execute on function public.get_league_playoff_history(uuid)
to authenticated;

select
  to_regprocedure(
    'public.get_league_playoff_history(uuid)'
  ) is not null as playoff_history_function_ready,
  exists (
    select 1
    from information_schema.routines routine
    where routine.routine_schema = 'public'
      and routine.routine_name = 'get_league_playoff_history'
      and routine.security_type = 'DEFINER'
  ) as playoff_history_security_ready,
  exists (
    select 1
    from pg_proc procedure
    join pg_namespace namespace
      on namespace.oid = procedure.pronamespace
    where namespace.nspname = 'public'
      and procedure.proname = 'get_league_playoff_history'
      and procedure.provolatile = 's'
  ) as playoff_history_stable_ready,
  has_function_privilege(
    'authenticated',
    'public.get_league_playoff_history(uuid)',
    'EXECUTE'
  ) as playoff_history_member_access_ready,
  not has_function_privilege(
    'anon',
    'public.get_league_playoff_history(uuid)',
    'EXECUTE'
  ) as anonymous_playoff_history_blocked,
  to_regclass('public.league_playoffs') is not null
    as playoff_history_playoffs_ready,
  to_regclass('public.league_playoff_entries') is not null
    as playoff_history_entries_ready,
  to_regclass('public.league_playoff_rounds') is not null
    as playoff_history_rounds_ready,
  to_regclass('public.league_playoff_ties') is not null
    as playoff_history_ties_ready,
  exists (
    select 1
    from information_schema.columns column_info
    where column_info.table_schema = 'public'
      and column_info.table_name = 'league_playoffs'
      and column_info.column_name = 'champion_team_id'
  ) as playoff_champion_history_ready,
  exists (
    select 1
    from information_schema.columns column_info
    where column_info.table_schema = 'public'
      and column_info.table_name = 'league_playoffs'
      and column_info.column_name = 'runner_up_team_id'
  ) as playoff_runner_up_history_ready,
  exists (
    select 1
    from information_schema.columns column_info
    where column_info.table_schema = 'public'
      and column_info.table_name = 'league_playoff_entries'
      and column_info.column_name = 'seed'
  ) as playoff_seed_history_ready;
