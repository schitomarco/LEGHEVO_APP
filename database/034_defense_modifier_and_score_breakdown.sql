-- LEGHEVO · modificatore difesa e dettaglio del punteggio
-- Eseguire nel SQL Editor di Supabase dopo 033.

alter table public.fantasy_fixtures
  add column if not exists home_base_points numeric(7,2),
  add column if not exists away_base_points numeric(7,2),
  add column if not exists home_defense_modifier numeric(5,2)
    not null default 0,
  add column if not exists away_defense_modifier numeric(5,2)
    not null default 0,
  add column if not exists home_bonus_applied numeric(5,2)
    not null default 0;

create or replace function public.calculate_defense_modifier(
  p_resolution jsonb,
  p_mode public.league_mode,
  p_scoring_rules jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_enabled boolean := false;
  v_min_defenders integer := 4;
  v_goalkeeper_rating numeric;
  v_defender_count integer := 0;
  v_selected_defenders integer := 0;
  v_best_defenders_total numeric := 0;
  v_average numeric;
  v_bonus numeric := 0;
  v_eligible boolean := false;
begin
  v_enabled :=
    p_mode = 'classic'
    and lower(
      coalesce(
        p_scoring_rules ->> 'defense_modifier_enabled',
        'false'
      )
    ) = 'true';

  if coalesce(
    p_scoring_rules ->> 'defense_modifier_min_defenders',
    ''
  ) ~ '^[0-9]+$' then
    v_min_defenders := least(
      greatest(
        (
          p_scoring_rules
            ->> 'defense_modifier_min_defenders'
        )::integer,
        4
      ),
      5
    );
  end if;

  if not v_enabled then
    return jsonb_build_object(
      'enabled', false,
      'eligible', false,
      'minimumDefenders', v_min_defenders,
      'defenderCount', 0,
      'averageRating', null,
      'bonus', 0
    );
  end if;

  select max((player.item ->> 'providerRating')::numeric)
  into v_goalkeeper_rating
  from jsonb_array_elements(
    coalesce(p_resolution -> 'players', '[]'::jsonb)
  ) as player(item)
  where player.item ->> 'role' = 'P'
    and coalesce(player.item ->> 'providerRating', '')
      ~ '^-?[0-9]+([.][0-9]+)?$';

  select count(*)::integer
  into v_defender_count
  from jsonb_array_elements(
    coalesce(p_resolution -> 'players', '[]'::jsonb)
  ) as player(item)
  where player.item ->> 'role' = 'D'
    and coalesce(player.item ->> 'providerRating', '')
      ~ '^-?[0-9]+([.][0-9]+)?$';

  select
    count(*)::integer,
    coalesce(sum(best.rating), 0)
  into
    v_selected_defenders,
    v_best_defenders_total
  from (
    select (player.item ->> 'providerRating')::numeric as rating
    from jsonb_array_elements(
      coalesce(p_resolution -> 'players', '[]'::jsonb)
    ) as player(item)
    where player.item ->> 'role' = 'D'
      and coalesce(player.item ->> 'providerRating', '')
        ~ '^-?[0-9]+([.][0-9]+)?$'
    order by rating desc
    limit 3
  ) as best;

  v_eligible :=
    v_goalkeeper_rating is not null
    and v_defender_count >= v_min_defenders
    and v_selected_defenders = 3;

  if v_eligible then
    v_average := round(
      (v_goalkeeper_rating + v_best_defenders_total) / 4,
      2
    );
    v_bonus := case
      when v_average >= 7 then 6
      when v_average >= 6.75 then 4
      when v_average >= 6.5 then 3
      when v_average >= 6.25 then 2
      when v_average >= 6 then 1
      else 0
    end;
  end if;

  return jsonb_build_object(
    'enabled', true,
    'eligible', v_eligible,
    'minimumDefenders', v_min_defenders,
    'defenderCount', v_defender_count,
    'averageRating', v_average,
    'bonus', v_bonus
  );
end;
$$;

revoke all on function public.calculate_defense_modifier(
  jsonb,
  public.league_mode,
  jsonb
) from public, anon, authenticated;

create or replace function public.get_team_matchday_breakdown(
  p_fantasy_team_id uuid,
  p_matchday_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_mode public.league_mode;
  v_scoring_rules jsonb := '{}'::jsonb;
  v_resolution jsonb;
  v_modifier jsonb;
  v_base_points numeric;
  v_modifier_bonus numeric := 0;
  v_total_points numeric;
begin
  select
    league.mode,
    league.scoring_rules
  into
    v_mode,
    v_scoring_rules
  from public.fantasy_teams team
  join public.leagues league on league.id = team.league_id
  where team.id = p_fantasy_team_id;

  if not found then
    return jsonb_build_object(
      'available', false,
      'basePoints', null,
      'totalPoints', null,
      'isReady', false,
      'countedPlayers', 0,
      'defenseModifier',
        jsonb_build_object(
          'enabled', false,
          'eligible', false,
          'minimumDefenders', 4,
          'defenderCount', 0,
          'averageRating', null,
          'bonus', 0
        )
    );
  end if;

  v_resolution := public.resolve_team_matchday_lineup(
    p_fantasy_team_id,
    p_matchday_id
  );
  v_modifier := public.calculate_defense_modifier(
    v_resolution,
    v_mode,
    v_scoring_rules
  );

  if nullif(v_resolution ->> 'totalPoints', '') is not null then
    v_base_points := (v_resolution ->> 'totalPoints')::numeric;
  end if;

  v_modifier_bonus := coalesce(
    nullif(v_modifier ->> 'bonus', '')::numeric,
    0
  );
  v_total_points := case
    when v_base_points is null then null
    else round(v_base_points + v_modifier_bonus, 2)
  end;

  return jsonb_build_object(
    'available',
      coalesce((v_resolution ->> 'available')::boolean, false),
    'basePoints', v_base_points,
    'totalPoints', v_total_points,
    'isReady',
      coalesce((v_resolution ->> 'isReady')::boolean, false),
    'countedPlayers',
      coalesce((v_resolution ->> 'countedPlayers')::integer, 0),
    'defenseModifier', v_modifier
  );
end;
$$;

revoke all on function public.get_team_matchday_breakdown(uuid, uuid)
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
  v_breakdown jsonb;
begin
  v_breakdown := public.get_team_matchday_breakdown(
    p_fantasy_team_id,
    p_matchday_id
  );

  total_points :=
    nullif(v_breakdown ->> 'totalPoints', '')::numeric;
  is_ready := coalesce(
    (v_breakdown ->> 'isReady')::boolean,
    false
  );
  counted_players := coalesce(
    (v_breakdown ->> 'countedPlayers')::integer,
    0
  );

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
  v_home_breakdown jsonb;
  v_away_breakdown jsonb;
  v_home_base_points numeric;
  v_away_base_points numeric;
  v_home_modifier numeric;
  v_away_modifier numeric;
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
    if v_fixture.finalized_at is not null then
      continue;
    end if;

    v_home_breakdown := public.get_team_matchday_breakdown(
      v_fixture.home_team_id,
      p_matchday_id
    );
    v_away_breakdown := public.get_team_matchday_breakdown(
      v_fixture.away_team_id,
      p_matchday_id
    );

    v_home_base_points :=
      nullif(v_home_breakdown ->> 'basePoints', '')::numeric;
    v_away_base_points :=
      nullif(v_away_breakdown ->> 'basePoints', '')::numeric;
    v_home_modifier := coalesce(
      nullif(
        v_home_breakdown
          #>> '{defenseModifier,bonus}',
        ''
      )::numeric,
      0
    );
    v_away_modifier := coalesce(
      nullif(
        v_away_breakdown
          #>> '{defenseModifier,bonus}',
        ''
      )::numeric,
      0
    );
    v_home_points :=
      nullif(v_home_breakdown ->> 'totalPoints', '')::numeric;
    v_away_points :=
      nullif(v_away_breakdown ->> 'totalPoints', '')::numeric;
    v_home_ready := coalesce(
      (v_home_breakdown ->> 'isReady')::boolean,
      false
    );
    v_away_ready := coalesce(
      (v_away_breakdown ->> 'isReady')::boolean,
      false
    );
    v_home_counted := coalesce(
      (v_home_breakdown ->> 'countedPlayers')::integer,
      0
    );
    v_away_counted := coalesce(
      (v_away_breakdown ->> 'countedPlayers')::integer,
      0
    );
    v_home_bonus :=
      coalesce((v_fixture.scoring_rules ->> 'home_bonus')::numeric, 0);

    if v_home_points is not null then
      v_home_points := round(v_home_points + v_home_bonus, 2);
    end if;

    update public.fantasy_fixtures
    set
      home_base_points = v_home_base_points,
      away_base_points = v_away_base_points,
      home_defense_modifier = v_home_modifier,
      away_defense_modifier = v_away_modifier,
      home_bonus_applied =
        case when v_home_points is null then 0 else v_home_bonus end,
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
        greatest(v_home_counted, 0),
        11
      ),
      away_counted_players = least(
        greatest(v_away_counted, 0),
        11
      ),
      home_ready = v_home_ready,
      away_ready = v_away_ready
    where id = v_fixture.id;

    v_updated := v_updated + 1;
  end loop;

  return v_updated;
end;
$$;

revoke all on function public.refresh_matchday_results_internal(uuid)
from public, anon, authenticated;

create or replace function public.get_my_live_match_v3(
  p_league_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_match jsonb;
  v_home_breakdown jsonb;
  v_away_breakdown jsonb;
  v_home_bonus numeric := 0;
  v_home_team_id uuid;
  v_away_team_id uuid;
  v_matchday_id uuid;
begin
  v_match := public.get_my_live_match_v2(p_league_id);

  if v_match is null then
    return null;
  end if;

  v_home_team_id := (v_match #>> '{home,teamId}')::uuid;
  v_away_team_id := (v_match #>> '{away,teamId}')::uuid;
  v_matchday_id := (v_match #>> '{matchday,id}')::uuid;

  v_home_breakdown := public.get_team_matchday_breakdown(
    v_home_team_id,
    v_matchday_id
  );
  v_away_breakdown := public.get_team_matchday_breakdown(
    v_away_team_id,
    v_matchday_id
  );

  select coalesce((league.scoring_rules ->> 'home_bonus')::numeric, 0)
  into v_home_bonus
  from public.leagues league
  where league.id = p_league_id;

  return v_match || jsonb_build_object(
    'home',
      (v_match -> 'home') || jsonb_build_object(
        'basePoints', v_home_breakdown -> 'basePoints',
        'defenseModifier',
          v_home_breakdown -> 'defenseModifier',
        'homeBonus', v_home_bonus
      ),
    'away',
      (v_match -> 'away') || jsonb_build_object(
        'basePoints', v_away_breakdown -> 'basePoints',
        'defenseModifier',
          v_away_breakdown -> 'defenseModifier',
        'homeBonus', 0
      )
  );
end;
$$;

revoke all on function public.get_my_live_match_v3(uuid)
from public, anon, authenticated;

grant execute on function public.get_my_live_match_v3(uuid)
to authenticated;

create or replace function public.get_league_results_center_v2(
  p_league_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_center jsonb;
  v_matchday jsonb;
  v_fixture jsonb;
  v_matchdays jsonb := '[]'::jsonb;
  v_fixtures jsonb;
  v_fixture_row record;
begin
  v_center := public.get_league_results_center(p_league_id);

  for v_matchday in
    select item
    from jsonb_array_elements(
      coalesce(v_center -> 'matchdays', '[]'::jsonb)
    ) as matchday(item)
  loop
    v_fixtures := '[]'::jsonb;

    for v_fixture in
      select item
      from jsonb_array_elements(
        coalesce(v_matchday -> 'fixtures', '[]'::jsonb)
      ) as fixture(item)
    loop
      select
        fixture.home_base_points,
        fixture.away_base_points,
        fixture.home_defense_modifier,
        fixture.away_defense_modifier,
        fixture.home_bonus_applied
      into v_fixture_row
      from public.fantasy_fixtures fixture
      where fixture.id = (v_fixture ->> 'id')::uuid;

      v_fixtures := v_fixtures || jsonb_build_array(
        v_fixture || jsonb_build_object(
          'homeBasePoints', v_fixture_row.home_base_points,
          'awayBasePoints', v_fixture_row.away_base_points,
          'homeDefenseModifier',
            coalesce(v_fixture_row.home_defense_modifier, 0),
          'awayDefenseModifier',
            coalesce(v_fixture_row.away_defense_modifier, 0),
          'homeBonusApplied',
            coalesce(v_fixture_row.home_bonus_applied, 0)
        )
      );
    end loop;

    v_matchdays := v_matchdays || jsonb_build_array(
      v_matchday || jsonb_build_object('fixtures', v_fixtures)
    );
  end loop;

  return v_center || jsonb_build_object('matchdays', v_matchdays);
end;
$$;

revoke all on function public.get_league_results_center_v2(uuid)
from public, anon, authenticated;

grant execute on function public.get_league_results_center_v2(uuid)
to authenticated;

create or replace function public.update_league_settings_v5(
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
  p_defense_modifier_min_defenders integer
)
returns public.leagues
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_league public.leagues%rowtype;
  v_matchday_id uuid;
  v_enabled boolean;
begin
  if p_defense_modifier_min_defenders not in (4, 5) then
    raise exception
      'Il modificatore difesa richiede almeno 4 o 5 difensori.';
  end if;

  select updated.*
  into v_league
  from public.update_league_settings_v4(
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
    p_max_substitutions
  ) as updated;

  v_enabled :=
    coalesce(p_defense_modifier_enabled, false)
    and v_league.mode = 'classic';

  update public.leagues
  set
    scoring_rules = coalesce(scoring_rules, '{}'::jsonb)
      || jsonb_build_object(
        'defense_modifier_enabled', v_enabled,
        'defense_modifier_min_defenders',
          p_defense_modifier_min_defenders
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

revoke all on function public.update_league_settings_v5(
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
  integer
) from public, anon, authenticated;

grant execute on function public.update_league_settings_v5(
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
  integer
) to authenticated;

select
  exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'fantasy_fixtures'
      and column_name = 'home_base_points'
  ) as base_points_ready,
  exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'fantasy_fixtures'
      and column_name = 'home_defense_modifier'
  ) as modifier_storage_ready,
  to_regprocedure(
    'public.calculate_defense_modifier(jsonb,public.league_mode,jsonb)'
  ) is not null as modifier_engine_ready,
  pg_get_functiondef(
    'public.calculate_defense_modifier(jsonb,public.league_mode,jsonb)'::regprocedure
  ) ilike '%v_average >= 7%'
    as modifier_tiers_ready,
  to_regprocedure(
    'public.get_team_matchday_breakdown(uuid,uuid)'
  ) is not null as score_breakdown_ready,
  pg_get_functiondef(
    'public.calculate_team_matchday_points(uuid,uuid)'::regprocedure
  ) ilike '%get_team_matchday_breakdown%'
    as scoring_engine_connected,
  pg_get_functiondef(
    'public.refresh_matchday_results_internal(uuid)'::regprocedure
  ) ilike '%home_defense_modifier%'
    as result_refresh_connected,
  to_regprocedure(
    'public.get_my_live_match_v3(uuid)'
  ) is not null as live_breakdown_ready,
  to_regprocedure(
    'public.get_league_results_center_v2(uuid)'
  ) is not null as results_breakdown_ready,
  to_regprocedure(
    'public.update_league_settings_v5(uuid,boolean,integer,integer,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,integer,integer,integer,integer,integer,boolean,integer)'
  ) is not null as modifier_settings_ready,
  has_function_privilege(
    'authenticated',
    'public.get_my_live_match_v3(uuid)',
    'EXECUTE'
  ) as live_access_ready,
  has_function_privilege(
    'authenticated',
    'public.update_league_settings_v5(uuid,boolean,integer,integer,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,integer,integer,integer,integer,integer,boolean,integer)',
    'EXECUTE'
  ) as settings_access_ready;
