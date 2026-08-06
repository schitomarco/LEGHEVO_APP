-- LEGHEVO · archivio storico multi-stagione e albo della lega
-- Eseguire nel SQL Editor di Supabase dopo 040.
-- Lo script aggiunge una lettura dello storico: non modifica leghe o risultati.

create or replace function public.get_league_history(
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
  v_total_seasons integer := 0;
  v_completed_seasons integer := 0;
  v_seasons jsonb := '[]'::jsonb;
  v_title_leaders jsonb := '[]'::jsonb;
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
      league.status,
      coalesce(
        summary.season,
        league.calendar_season
      ) as season,
      league.competition_started_at,
      coalesce(
        summary.completed_at,
        league.competition_completed_at
      ) as completed_at,
      summary.champion_team_id,
      summary.champion_team_name,
      summary.champion_manager_name,
      summary.final_standings,
      (
        select count(*)::integer
        from public.league_members member
        where member.league_id = league.id
      ) as member_count,
      (
        select count(*)::integer
        from public.fantasy_fixtures fixture
        where fixture.league_id = league.id
      ) as fixture_count,
      (
        select count(*)::integer
        from public.fantasy_fixtures fixture
        where fixture.league_id = league.id
          and fixture.finalized_at is not null
      ) as official_fixture_count
    from season_chain chain
    join public.leagues league
      on league.id = chain.id
    left join public.league_season_summaries summary
      on summary.league_id = league.id
  )
  select
    count(*)::integer,
    count(*) filter (
      where row.champion_team_id is not null
    )::integer,
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'leagueId', row.league_id,
          'season', row.season,
          'status', row.status,
          'startedAt', row.competition_started_at,
          'completedAt', row.completed_at,
          'memberCount', row.member_count,
          'fixtureCount', row.fixture_count,
          'officialFixtureCount', row.official_fixture_count,
          'champion',
            case
              when row.champion_team_id is null then null
              else jsonb_build_object(
                'teamId', row.champion_team_id,
                'teamName', row.champion_team_name,
                'managerName', row.champion_manager_name,
                'leaguePoints',
                  coalesce(
                    (
                      row.final_standings
                        -> 0
                        ->> 'leaguePoints'
                    )::integer,
                    0
                  ),
                'pointsFor',
                  coalesce(
                    (
                      row.final_standings
                        -> 0
                        ->> 'pointsFor'
                    )::numeric,
                    0
                  )
              )
            end,
          'podium',
            coalesce(
              (
                select jsonb_agg(
                  jsonb_build_object(
                    'position',
                      coalesce(
                        (standing.item ->> 'position')::integer,
                        standing.ordinality::integer
                      ),
                    'teamId', standing.item ->> 'teamId',
                    'teamName', standing.item ->> 'teamName',
                    'managerName', standing.item ->> 'managerName',
                    'leaguePoints',
                      coalesce(
                        (standing.item ->> 'leaguePoints')::integer,
                        0
                      ),
                    'pointsFor',
                      coalesce(
                        (standing.item ->> 'pointsFor')::numeric,
                        0
                      )
                  )
                  order by standing.ordinality
                )
                from jsonb_array_elements(
                  coalesce(row.final_standings, '[]'::jsonb)
                ) with ordinality as standing(item, ordinality)
                where standing.ordinality <= 3
              ),
              '[]'::jsonb
            ),
          'isSelected', row.league_id = p_league_id,
          'isLatest', row.league_id = v_latest_league_id
        )
        order by row.sequence desc
      ),
      '[]'::jsonb
    )
  into
    v_total_seasons,
    v_completed_seasons,
    v_seasons
  from season_rows row;

  with recursive season_chain as (
    select
      league.id,
      league.previous_league_id
    from public.leagues league
    where league.id = v_root_league_id

    union all

    select
      renewed.id,
      renewed.previous_league_id
    from season_chain current_season
    join public.leagues renewed
      on renewed.previous_league_id = current_season.id
  ),
  title_counts as (
    select
      champion_team.manager_id,
      coalesce(
        profile.display_name,
        max(summary.champion_manager_name)
      ) as manager_name,
      count(*)::integer as title_count,
      to_jsonb(
        array_agg(
          distinct summary.champion_team_name
          order by summary.champion_team_name
        )
      ) as team_names
    from season_chain chain
    join public.league_season_summaries summary
      on summary.league_id = chain.id
    join public.fantasy_teams champion_team
      on champion_team.id = summary.champion_team_id
    left join public.profiles profile
      on profile.id = champion_team.manager_id
    group by
      champion_team.manager_id,
      profile.display_name
  )
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'managerId', leader.manager_id,
        'managerName', leader.manager_name,
        'titles', leader.title_count,
        'teamNames', leader.team_names
      )
      order by
        leader.title_count desc,
        leader.manager_name,
        leader.manager_id
    ),
    '[]'::jsonb
  )
  into v_title_leaders
  from title_counts leader;

  return jsonb_build_object(
    'leagueName', v_requested_league.name,
    'selectedLeagueId', p_league_id,
    'latestLeagueId', v_latest_league_id,
    'totalSeasons', v_total_seasons,
    'completedSeasons', v_completed_seasons,
    'seasons', v_seasons,
    'titleLeaders', v_title_leaders
  );
end;
$$;

revoke all on function public.get_league_history(uuid)
from public, anon, authenticated;

grant execute on function public.get_league_history(uuid)
to authenticated;

select
  to_regprocedure(
    'public.get_league_history(uuid)'
  ) is not null as league_history_ready,
  has_function_privilege(
    'authenticated',
    'public.get_league_history(uuid)',
    'EXECUTE'
  ) as league_history_access_ready,
  not has_function_privilege(
    'anon',
    'public.get_league_history(uuid)',
    'EXECUTE'
  ) as anonymous_history_blocked,
  (
    select routine_type = 'FUNCTION'
    from information_schema.routines
    where routine_schema = 'public'
      and routine_name = 'get_league_history'
  ) as league_history_is_function,
  (
    select data_type = 'jsonb'
    from information_schema.routines
    where routine_schema = 'public'
      and routine_name = 'get_league_history'
  ) as league_history_returns_json,
  (
    select security_type = 'DEFINER'
    from information_schema.routines
    where routine_schema = 'public'
      and routine_name = 'get_league_history'
  ) as league_history_security_ready,
  (
    select provolatile = 's'
    from pg_proc
    where oid = 'public.get_league_history(uuid)'::regprocedure
  ) as league_history_stable,
  exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'leagues'
      and column_name = 'previous_league_id'
  ) as previous_league_link_ready,
  to_regclass(
    'public.leagues_previous_league_unique_idx'
  ) is not null as season_chain_unique,
  to_regclass(
    'public.league_season_summaries'
  ) is not null as season_summaries_ready,
  to_regclass(
    'public.league_season_rollovers'
  ) is not null as season_rollovers_ready,
  (
    select count(*) = 1
    from information_schema.parameters
    where specific_schema = 'public'
      and specific_name in (
        select routine.specific_name
        from information_schema.routines routine
        where routine.routine_schema = 'public'
          and routine.routine_name = 'get_league_history'
      )
      and parameter_mode = 'IN'
      and udt_name = 'uuid'
  ) as league_history_signature_ready;
