-- LEGHEVO · sostituzioni automatiche complete e priorità panchina
-- Eseguire nel SQL Editor di Supabase dopo 032.

create or replace function public.lineup_players_are_substitution_compatible(
  p_outgoing_athlete_id uuid,
  p_incoming_athlete_id uuid,
  p_mode public.league_mode
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when p_mode = 'classic' then exists (
      select 1
      from public.athlete_roles outgoing_role
      join public.athlete_roles incoming_role
        on incoming_role.mode = outgoing_role.mode
        and incoming_role.role_code = outgoing_role.role_code
      where outgoing_role.athlete_id = p_outgoing_athlete_id
        and incoming_role.athlete_id = p_incoming_athlete_id
        and outgoing_role.mode = 'classic'
    )
    else exists (
      select 1
      from (
        values ('POR'), ('DEF'), ('MID'), ('TRE'), ('ATT')
      ) as compatible_slot(slot_code)
      where public.mantra_athlete_fits_slot(
        p_outgoing_athlete_id,
        compatible_slot.slot_code
      )
        and public.mantra_athlete_fits_slot(
          p_incoming_athlete_id,
          compatible_slot.slot_code
        )
    )
  end;
$$;

revoke all on function public.lineup_players_are_substitution_compatible(
  uuid,
  uuid,
  public.league_mode
) from public, anon, authenticated;

create or replace function public.resolve_team_matchday_lineup(
  p_fantasy_team_id uuid,
  p_matchday_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_lineup record;
  v_matchday_complete boolean := false;
  v_max_substitutions integer := 5;
  v_substitutions_used integer := 0;
  v_counted_players integer := 0;
  v_unavailable_starters integer := 0;
  v_total_points numeric := 0;
  v_is_ready boolean := false;
  v_starter record;
  v_candidate record;
  v_effective_athlete_id uuid;
  v_effective_name text;
  v_effective_role text;
  v_provider_rating numeric;
  v_fantasy_score numeric;
  v_bonuses jsonb;
  v_maluses jsonb;
  v_raw_statistics jsonb;
  v_is_final boolean;
  v_is_substitute boolean;
  v_replaced_player_name text;
  v_blocked_reason text;
  v_used_bench_ids uuid[] := array[]::uuid[];
  v_players jsonb := '[]'::jsonb;
begin
  select
    case
      when matchday.provider_fixture_count > 0 then
        matchday.provider_final_fixture_count
          = matchday.provider_fixture_count
      else
        now() >= coalesce(
          matchday.ends_at,
          matchday.starts_at + interval '4 days'
        )
    end
  into v_matchday_complete
  from public.matchdays matchday
  where matchday.id = p_matchday_id;

  v_matchday_complete := coalesce(v_matchday_complete, false);
  v_is_ready := v_matchday_complete;

  select
    lineup.id,
    lineup.formation,
    league.mode,
    league.scoring_rules
  into v_lineup
  from public.fantasy_teams team
  join public.leagues league
    on league.id = team.league_id
  left join public.lineups lineup
    on lineup.fantasy_team_id = team.id
    and lineup.matchday_id = p_matchday_id
    and lineup.status in ('submitted', 'locked')
  where team.id = p_fantasy_team_id;

  if not found then
    return jsonb_build_object(
      'available', false,
      'matchdayComplete', v_matchday_complete,
      'totalPoints',
        case when v_matchday_complete then 0 else null end,
      'isReady', v_matchday_complete,
      'countedPlayers', 0,
      'maxSubstitutions', v_max_substitutions,
      'substitutionsUsed', 0,
      'unavailableStarters', 0,
      'players', v_players
    );
  end if;

  if coalesce(v_lineup.scoring_rules ->> 'max_substitutions', '')
      ~ '^[0-9]+$' then
    v_max_substitutions := least(
      greatest(
        (v_lineup.scoring_rules ->> 'max_substitutions')::integer,
        0
      ),
      11
    );
  end if;

  if v_lineup.id is null then
    return jsonb_build_object(
      'available', false,
      'matchdayComplete', v_matchday_complete,
      'totalPoints',
        case when v_matchday_complete then 0 else null end,
      'isReady', v_matchday_complete,
      'countedPlayers', 0,
      'maxSubstitutions', v_max_substitutions,
      'substitutionsUsed', 0,
      'unavailableStarters', 0,
      'players', v_players
    );
  end if;

  for v_starter in
    select
      entry.athlete_id,
      entry.slot,
      concat_ws(
        ' ',
        nullif(trim(athlete.first_name), ''),
        athlete.last_name
      ) as player_name,
      coalesce(
        (
          select string_agg(
            role.role_code,
            '/' order by role.role_code
          )
          from public.athlete_roles role
          where role.athlete_id = athlete.id
            and role.mode = v_lineup.mode
        ),
        '—'
      ) as player_role
    from public.lineup_entries entry
    join public.athletes athlete
      on athlete.id = entry.athlete_id
    where entry.lineup_id = v_lineup.id
      and entry.is_starter
    order by entry.slot
  loop
    v_effective_athlete_id := v_starter.athlete_id;
    v_effective_name := v_starter.player_name;
    v_effective_role := v_starter.player_role;
    v_provider_rating := null;
    v_fantasy_score := null;
    v_bonuses := '{}'::jsonb;
    v_maluses := '{}'::jsonb;
    v_raw_statistics := '{}'::jsonb;
    v_is_final := false;
    v_is_substitute := false;
    v_replaced_player_name := null;
    v_blocked_reason := null;

    select
      score.provider_rating,
      public.calculate_league_fantasy_score(
        score.provider_rating,
        score.fantasy_score,
        score.raw_statistics,
        v_lineup.scoring_rules
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
      if not v_matchday_complete then
        v_blocked_reason := 'awaiting_score';
      elsif v_substitutions_used >= v_max_substitutions then
        v_blocked_reason := 'limit_reached';
      else
        select
          bench.athlete_id,
          concat_ws(
            ' ',
            nullif(trim(athlete.first_name), ''),
            athlete.last_name
          ) as player_name,
          coalesce(
            (
              select string_agg(
                role.role_code,
                '/' order by role.role_code
              )
              from public.athlete_roles role
              where role.athlete_id = athlete.id
                and role.mode = v_lineup.mode
            ),
            '—'
          ) as player_role,
          score.provider_rating,
          public.calculate_league_fantasy_score(
            score.provider_rating,
            score.fantasy_score,
            score.raw_statistics,
            v_lineup.scoring_rules
          ) as fantasy_score,
          score.bonuses,
          score.maluses,
          score.raw_statistics,
          score.is_final
        into v_candidate
        from public.lineup_entries bench
        join public.athletes athlete
          on athlete.id = bench.athlete_id
        join public.player_match_scores score
          on score.athlete_id = bench.athlete_id
          and score.matchday_id = p_matchday_id
          and score.provider_rating is not null
        where bench.lineup_id = v_lineup.id
          and not bench.is_starter
          and not (bench.athlete_id = any(v_used_bench_ids))
          and public.lineup_players_are_substitution_compatible(
            v_starter.athlete_id,
            bench.athlete_id,
            v_lineup.mode
          )
        order by bench.slot
        limit 1;

        if found then
          v_effective_athlete_id := v_candidate.athlete_id;
          v_effective_name := v_candidate.player_name;
          v_effective_role := v_candidate.player_role;
          v_provider_rating := v_candidate.provider_rating;
          v_fantasy_score := v_candidate.fantasy_score;
          v_bonuses := v_candidate.bonuses;
          v_maluses := v_candidate.maluses;
          v_raw_statistics := v_candidate.raw_statistics;
          v_is_final := v_candidate.is_final;
          v_is_substitute := true;
          v_replaced_player_name := v_starter.player_name;
          v_used_bench_ids := array_append(
            v_used_bench_ids,
            v_candidate.athlete_id
          );
          v_substitutions_used := v_substitutions_used + 1;
        else
          v_blocked_reason := 'no_compatible_bench';
        end if;
      end if;
    end if;

    if v_provider_rating is not null then
      v_total_points := v_total_points + v_fantasy_score;
      v_counted_players := v_counted_players + 1;
      v_is_ready := v_is_ready and coalesce(v_is_final, false);
    elsif v_matchday_complete then
      v_unavailable_starters := v_unavailable_starters + 1;
    end if;

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
        'replacedPlayerName', v_replaced_player_name,
        'blockedReason', v_blocked_reason
      )
    );
  end loop;

  if v_counted_players = 0 then
    v_total_points := case
      when v_matchday_complete then 0
      else null
    end;
  else
    v_total_points := round(v_total_points, 2);
  end if;

  return jsonb_build_object(
    'available', true,
    'matchdayComplete', v_matchday_complete,
    'totalPoints', v_total_points,
    'isReady', v_is_ready,
    'countedPlayers', v_counted_players,
    'maxSubstitutions', v_max_substitutions,
    'substitutionsUsed', v_substitutions_used,
    'unavailableStarters', v_unavailable_starters,
    'players', v_players
  );
end;
$$;

revoke all on function public.resolve_team_matchday_lineup(uuid, uuid)
from public, anon, authenticated;

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
  v_resolution jsonb;
begin
  v_resolution := public.resolve_team_matchday_lineup(
    p_fantasy_team_id,
    p_matchday_id
  );

  total_points := (v_resolution ->> 'totalPoints')::numeric;
  is_ready := coalesce(
    (v_resolution ->> 'isReady')::boolean,
    false
  );
  counted_players := coalesce(
    (v_resolution ->> 'countedPlayers')::integer,
    0
  );

  return next;
end;
$$;

revoke all on function public.calculate_team_matchday_points(uuid, uuid)
from public, anon, authenticated;

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
  v_resolution jsonb;
begin
  v_resolution := public.resolve_team_matchday_lineup(
    p_fantasy_team_id,
    p_matchday_id
  );

  return coalesce(v_resolution -> 'players', '[]'::jsonb);
end;
$$;

revoke all on function public.get_team_live_players(
  uuid,
  uuid,
  public.league_mode,
  jsonb
) from public, anon, authenticated;

create or replace function public.get_my_live_match_v2(
  p_league_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_match jsonb;
  v_resolution jsonb;
  v_team_id uuid;
  v_matchday_id uuid;
begin
  v_match := public.get_my_live_match(p_league_id);

  if v_match is null then
    return null;
  end if;

  v_team_id := (v_match ->> 'myTeamId')::uuid;
  v_matchday_id := (v_match #>> '{matchday,id}')::uuid;
  v_resolution := public.resolve_team_matchday_lineup(
    v_team_id,
    v_matchday_id
  );

  return v_match || jsonb_build_object(
    'substitutions',
    jsonb_build_object(
      'used',
        coalesce(
          (v_resolution ->> 'substitutionsUsed')::integer,
          0
        ),
      'limit',
        coalesce(
          (v_resolution ->> 'maxSubstitutions')::integer,
          5
        ),
      'unavailableStarters',
        coalesce(
          (v_resolution ->> 'unavailableStarters')::integer,
          0
        ),
      'applied',
        coalesce(
          (v_resolution ->> 'matchdayComplete')::boolean,
          false
        )
    )
  );
end;
$$;

revoke all on function public.get_my_live_match_v2(uuid)
from public, anon, authenticated;

grant execute on function public.get_my_live_match_v2(uuid)
to authenticated;

create or replace function public.update_league_settings_v4(
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
  p_max_substitutions integer
)
returns public.leagues
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_league public.leagues%rowtype;
  v_matchday_id uuid;
begin
  if p_max_substitutions is null
    or p_max_substitutions < 0
    or p_max_substitutions > 11 then
    raise exception 'Il limite dei cambi deve essere compreso tra 0 e 11.';
  end if;

  select updated.*
  into v_league
  from public.update_league_settings_v3(
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
    p_roster_attackers
  ) as updated;

  update public.leagues
  set
    scoring_rules = coalesce(scoring_rules, '{}'::jsonb)
      || jsonb_build_object(
        'max_substitutions',
        p_max_substitutions
      ),
    updated_at = now()
  where id = p_league_id
  returning * into v_league;

  for v_matchday_id in
    select distinct fixture.matchday_id
    from public.fantasy_fixtures fixture
    where fixture.league_id = p_league_id
      and fixture.finalized_at is null
  loop
    perform public.refresh_matchday_results_internal(v_matchday_id);
  end loop;

  return v_league;
end;
$$;

revoke all on function public.update_league_settings_v4(
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
  integer
) from public, anon, authenticated;

grant execute on function public.update_league_settings_v4(
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
  integer
) to authenticated;

select
  to_regprocedure(
    'public.lineup_players_are_substitution_compatible(uuid,uuid,public.league_mode)'
  ) is not null as substitution_compatibility_ready,
  to_regprocedure(
    'public.resolve_team_matchday_lineup(uuid,uuid)'
  ) is not null as lineup_resolution_ready,
  pg_get_functiondef(
    'public.resolve_team_matchday_lineup(uuid,uuid)'::regprocedure
  ) ilike '%max_substitutions%'
    as substitution_limit_ready,
  pg_get_functiondef(
    'public.resolve_team_matchday_lineup(uuid,uuid)'::regprocedure
  ) ilike '%order by bench.slot%'
    as bench_priority_ready,
  pg_get_functiondef(
    'public.resolve_team_matchday_lineup(uuid,uuid)'::regprocedure
  ) ilike '%matchdaycomplete%'
    as final_matchday_guard_ready,
  pg_get_functiondef(
    'public.calculate_team_matchday_points(uuid,uuid)'::regprocedure
  ) ilike '%resolve_team_matchday_lineup%'
    as score_engine_connected,
  pg_get_functiondef(
    'public.get_team_live_players(uuid,uuid,public.league_mode,jsonb)'::regprocedure
  ) ilike '%resolve_team_matchday_lineup%'
    as live_players_connected,
  to_regprocedure(
    'public.get_my_live_match_v2(uuid)'
  ) is not null as live_substitution_summary_ready,
  to_regprocedure(
    'public.update_league_settings_v4(uuid,boolean,integer,integer,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,integer,integer,integer,integer,integer)'
  ) is not null as substitution_settings_ready,
  has_function_privilege(
    'authenticated',
    'public.get_my_live_match_v2(uuid)',
    'EXECUTE'
  ) as live_access_ready,
  has_function_privilege(
    'authenticated',
    'public.update_league_settings_v4(uuid,boolean,integer,integer,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,integer,integer,integer,integer,integer)',
    'EXECUTE'
  ) as settings_access_ready,
  (
    not has_function_privilege(
      'authenticated',
      'public.resolve_team_matchday_lineup(uuid,uuid)',
      'EXECUTE'
    )
    and not has_function_privilege(
      'anon',
      'public.resolve_team_matchday_lineup(uuid,uuid)',
      'EXECUTE'
    )
  ) as internal_resolution_protected;
