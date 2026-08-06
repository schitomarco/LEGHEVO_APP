-- LEGHEVO · centro partita Live della lega
-- Eseguire nel SQL Editor di Supabase dopo 016.

create or replace function public.get_team_live_players(
  p_fantasy_team_id uuid,
  p_matchday_id uuid,
  p_mode public.league_mode,
  p_scoring_rules jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_lineup_id uuid;
  v_starter record;
  v_effective_athlete_id uuid;
  v_effective_role text;
  v_effective_name text;
  v_replaced_player_name text;
  v_provider_rating numeric;
  v_fantasy_score numeric;
  v_bonuses jsonb;
  v_maluses jsonb;
  v_raw_statistics jsonb;
  v_is_final boolean;
  v_is_substitute boolean;
  v_used_bench_ids uuid[] := array[]::uuid[];
  v_players jsonb := '[]'::jsonb;
begin
  select lineup.id
  into v_lineup_id
  from public.lineups lineup
  where lineup.fantasy_team_id = p_fantasy_team_id
    and lineup.matchday_id = p_matchday_id
    and lineup.status in ('submitted', 'locked');

  if not found then
    return v_players;
  end if;

  for v_starter in
    select
      entry.athlete_id,
      entry.slot,
      concat_ws(
        ' ',
        nullif(trim(athlete.first_name), ''),
        athlete.last_name
      ) as player_name
    from public.lineup_entries entry
    join public.athletes athlete on athlete.id = entry.athlete_id
    where entry.lineup_id = v_lineup_id
      and entry.is_starter
    order by entry.slot
  loop
    v_effective_athlete_id := v_starter.athlete_id;
    v_replaced_player_name := null;
    v_provider_rating := null;
    v_fantasy_score := null;
    v_bonuses := '{}'::jsonb;
    v_maluses := '{}'::jsonb;
    v_raw_statistics := '{}'::jsonb;
    v_is_final := false;
    v_is_substitute := false;

    select
      score.provider_rating,
      public.calculate_league_fantasy_score(
        score.provider_rating,
        score.fantasy_score,
        score.raw_statistics,
        p_scoring_rules
      ),
      score.bonuses,
      score.maluses,
      score.raw_statistics,
      score.is_final
    into
      v_provider_rating,
      v_fantasy_score,
      v_bonuses,
      v_maluses,
      v_raw_statistics,
      v_is_final
    from public.player_match_scores score
    where score.athlete_id = v_starter.athlete_id
      and score.matchday_id = p_matchday_id
      and score.provider_rating is not null;

    if not found then
      select
        bench.athlete_id,
        score.provider_rating,
        public.calculate_league_fantasy_score(
          score.provider_rating,
          score.fantasy_score,
          score.raw_statistics,
          p_scoring_rules
        ),
        score.bonuses,
        score.maluses,
        score.raw_statistics,
        score.is_final
      into
        v_effective_athlete_id,
        v_provider_rating,
        v_fantasy_score,
        v_bonuses,
        v_maluses,
        v_raw_statistics,
        v_is_final
      from public.lineup_entries bench
      join public.player_match_scores score
        on score.athlete_id = bench.athlete_id
        and score.matchday_id = p_matchday_id
        and score.provider_rating is not null
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
            and starter_role.mode = p_mode
        )
      order by bench.slot
      limit 1;

      if found then
        v_used_bench_ids :=
          array_append(v_used_bench_ids, v_effective_athlete_id);
        v_replaced_player_name := v_starter.player_name;
        v_is_substitute := true;
      else
        v_effective_athlete_id := v_starter.athlete_id;
      end if;
    end if;

    select
      concat_ws(
        ' ',
        nullif(trim(athlete.first_name), ''),
        athlete.last_name
      ),
      coalesce(
        (
          select string_agg(role.role_code, '/' order by role.role_code)
          from public.athlete_roles role
          where role.athlete_id = athlete.id
            and role.mode = p_mode
        ),
        '—'
      )
    into v_effective_name, v_effective_role
    from public.athletes athlete
    where athlete.id = v_effective_athlete_id;

    v_players := v_players || jsonb_build_array(
      jsonb_build_object(
        'athleteId', v_effective_athlete_id,
        'name', v_effective_name,
        'role', v_effective_role,
        'slot', v_starter.slot,
        'providerRating', v_provider_rating,
        'fantasyScore', v_fantasy_score,
        'bonuses', coalesce(v_bonuses, '{}'::jsonb),
        'maluses', coalesce(v_maluses, '{}'::jsonb),
        'rawStatistics', coalesce(v_raw_statistics, '{}'::jsonb),
        'isFinal', coalesce(v_is_final, false),
        'isSubstitute', v_is_substitute,
        'replacedPlayerName', v_replaced_player_name
      )
    );
  end loop;

  return v_players;
end;
$$;

revoke all on function public.get_team_live_players(
  uuid,
  uuid,
  public.league_mode,
  jsonb
) from public, anon, authenticated;

create or replace function public.get_my_live_match(
  p_league_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_league public.leagues%rowtype;
  v_my_team public.fantasy_teams%rowtype;
  v_fixture record;
  v_home_calculation record;
  v_away_calculation record;
  v_home_points numeric;
  v_away_points numeric;
  v_home_goals integer;
  v_away_goals integer;
  v_home_bonus numeric;
  v_match_status text;
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
    raise exception 'Non hai una squadra in questa lega.';
  end if;

  select
    fixture.id,
    fixture.matchday_id,
    fixture.home_team_id,
    fixture.away_team_id,
    fixture.finalized_at,
    matchday.number as matchday_number,
    matchday.starts_at,
    matchday.locks_at,
    matchday.ends_at,
    home_team.name as home_team_name,
    away_team.name as away_team_name
  into v_fixture
  from public.fantasy_fixtures fixture
  join public.matchdays matchday on matchday.id = fixture.matchday_id
  join public.fantasy_teams home_team on home_team.id = fixture.home_team_id
  join public.fantasy_teams away_team on away_team.id = fixture.away_team_id
  where fixture.league_id = p_league_id
    and (
      fixture.home_team_id = v_my_team.id
      or fixture.away_team_id = v_my_team.id
    )
  order by
    case
      when now() >= matchday.starts_at
        and now() <= coalesce(
          matchday.ends_at,
          matchday.starts_at + interval '4 days'
        ) then 0
      when matchday.starts_at <= now()
        and fixture.finalized_at is null then 1
      when matchday.starts_at > now() then 2
      else 3
    end,
    case
      when matchday.starts_at > now() then matchday.starts_at
      else null
    end,
    case
      when matchday.starts_at <= now() then matchday.starts_at
      else null
    end desc
  limit 1;

  if not found then
    return null;
  end if;

  select calculation.*
  into v_home_calculation
  from public.calculate_team_matchday_points(
    v_fixture.home_team_id,
    v_fixture.matchday_id
  ) calculation;

  select calculation.*
  into v_away_calculation
  from public.calculate_team_matchday_points(
    v_fixture.away_team_id,
    v_fixture.matchday_id
  ) calculation;

  v_home_bonus :=
    coalesce((v_league.scoring_rules ->> 'home_bonus')::numeric, 0);
  v_home_points := v_home_calculation.total_points;
  v_away_points := v_away_calculation.total_points;

  if v_home_points is not null then
    v_home_points := round(v_home_points + v_home_bonus, 2);
  end if;

  v_home_goals := public.fantasy_goals_from_points(
    v_home_points,
    v_league.scoring_rules
  );
  v_away_goals := public.fantasy_goals_from_points(
    v_away_points,
    v_league.scoring_rules
  );

  v_match_status := case
    when v_fixture.finalized_at is not null then 'final'
    when now() < v_fixture.starts_at then 'upcoming'
    when now() <= coalesce(
      v_fixture.ends_at,
      v_fixture.starts_at + interval '4 days'
    ) then 'live'
    else 'pending'
  end;

  return jsonb_build_object(
    'leagueId', v_league.id,
    'leagueName', v_league.name,
    'mode', v_league.mode,
    'status', v_match_status,
    'fixtureId', v_fixture.id,
    'myTeamId', v_my_team.id,
    'matchday', jsonb_build_object(
      'id', v_fixture.matchday_id,
      'number', v_fixture.matchday_number,
      'startsAt', v_fixture.starts_at,
      'locksAt', v_fixture.locks_at,
      'endsAt', v_fixture.ends_at
    ),
    'home', jsonb_build_object(
      'teamId', v_fixture.home_team_id,
      'name', v_fixture.home_team_name,
      'points', v_home_points,
      'goals', v_home_goals,
      'countedPlayers', coalesce(
        v_home_calculation.counted_players,
        0
      ),
      'ready', coalesce(v_home_calculation.is_ready, false)
    ),
    'away', jsonb_build_object(
      'teamId', v_fixture.away_team_id,
      'name', v_fixture.away_team_name,
      'points', v_away_points,
      'goals', v_away_goals,
      'countedPlayers', coalesce(
        v_away_calculation.counted_players,
        0
      ),
      'ready', coalesce(v_away_calculation.is_ready, false)
    ),
    'players', public.get_team_live_players(
      v_my_team.id,
      v_fixture.matchday_id,
      v_league.mode,
      v_league.scoring_rules
    )
  );
end;
$$;

revoke all on function public.get_my_live_match(uuid) from public;
grant execute on function public.get_my_live_match(uuid) to authenticated;

select
  to_regprocedure(
    'public.get_team_live_players(uuid,uuid,public.league_mode,jsonb)'
  ) is not null as live_players_ready,
  to_regprocedure(
    'public.get_my_live_match(uuid)'
  ) is not null as live_match_ready,
  has_function_privilege(
    'authenticated',
    'public.get_my_live_match(uuid)',
    'EXECUTE'
  ) as live_access_ready,
  exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'fantasy_fixtures'
  ) as live_realtime_ready;
