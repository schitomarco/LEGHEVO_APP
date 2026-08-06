-- LEGHEVO · scarto minimo nei pareggi e tracciamento del gol aggiuntivo
-- Eseguire nel SQL Editor di Supabase dopo 034.

alter table public.fantasy_fixtures
  add column if not exists home_goal_margin_bonus smallint
    not null default 0,
  add column if not exists away_goal_margin_bonus smallint
    not null default 0;

alter table public.fantasy_fixtures
  drop constraint if exists fantasy_fixtures_home_goal_margin_bonus_check;

alter table public.fantasy_fixtures
  add constraint fantasy_fixtures_home_goal_margin_bonus_check
  check (home_goal_margin_bonus in (0, 1));

alter table public.fantasy_fixtures
  drop constraint if exists fantasy_fixtures_away_goal_margin_bonus_check;

alter table public.fantasy_fixtures
  add constraint fantasy_fixtures_away_goal_margin_bonus_check
  check (away_goal_margin_bonus in (0, 1));

create or replace function public.resolve_fantasy_fixture_goals(
  p_home_points numeric,
  p_away_points numeric,
  p_scoring_rules jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_home_base smallint;
  v_away_base smallint;
  v_home_goals smallint;
  v_away_goals smallint;
  v_home_bonus smallint := 0;
  v_away_bonus smallint := 0;
  v_enabled boolean := false;
  v_margin numeric := 4;
begin
  v_home_base := public.fantasy_goals_from_points(
    p_home_points,
    p_scoring_rules
  );
  v_away_base := public.fantasy_goals_from_points(
    p_away_points,
    p_scoring_rules
  );
  v_home_goals := v_home_base;
  v_away_goals := v_away_base;

  v_enabled :=
    lower(
      coalesce(p_scoring_rules ->> 'goal_margin_enabled', 'false')
    ) = 'true';

  if coalesce(p_scoring_rules ->> 'goal_margin', '')
    ~ '^[0-9]+([.][0-9]+)?$' then
    v_margin := least(
      greatest(
        (p_scoring_rules ->> 'goal_margin')::numeric,
        1
      ),
      20
    );
  end if;

  if v_enabled
    and p_home_points is not null
    and p_away_points is not null
    and v_home_base = v_away_base
    and abs(p_home_points - p_away_points) >= v_margin then
    if p_home_points > p_away_points then
      v_home_bonus := 1;
      v_home_goals := v_home_goals + 1;
    elsif p_away_points > p_home_points then
      v_away_bonus := 1;
      v_away_goals := v_away_goals + 1;
    end if;
  end if;

  return jsonb_build_object(
    'enabled', v_enabled,
    'minimum', v_margin,
    'applied', v_home_bonus = 1 or v_away_bonus = 1,
    'baseHomeGoals', v_home_base,
    'baseAwayGoals', v_away_base,
    'homeGoals', v_home_goals,
    'awayGoals', v_away_goals,
    'homeBonus', v_home_bonus,
    'awayBonus', v_away_bonus
  );
end;
$$;

revoke all on function public.resolve_fantasy_fixture_goals(
  numeric,
  numeric,
  jsonb
) from public, anon, authenticated;

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
  v_goal_resolution jsonb;
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
  v_home_goals smallint;
  v_away_goals smallint;
  v_home_goal_margin_bonus smallint;
  v_away_goal_margin_bonus smallint;
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
        v_home_breakdown #>> '{defenseModifier,bonus}',
        ''
      )::numeric,
      0
    );
    v_away_modifier := coalesce(
      nullif(
        v_away_breakdown #>> '{defenseModifier,bonus}',
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

    v_goal_resolution := public.resolve_fantasy_fixture_goals(
      v_home_points,
      v_away_points,
      v_fixture.scoring_rules
    );
    v_home_goals :=
      nullif(v_goal_resolution ->> 'homeGoals', '')::smallint;
    v_away_goals :=
      nullif(v_goal_resolution ->> 'awayGoals', '')::smallint;
    v_home_goal_margin_bonus := coalesce(
      nullif(v_goal_resolution ->> 'homeBonus', '')::smallint,
      0
    );
    v_away_goal_margin_bonus := coalesce(
      nullif(v_goal_resolution ->> 'awayBonus', '')::smallint,
      0
    );

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
      home_goals = v_home_goals,
      away_goals = v_away_goals,
      home_goal_margin_bonus = v_home_goal_margin_bonus,
      away_goal_margin_bonus = v_away_goal_margin_bonus,
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

create or replace function public.get_my_live_match_v4(
  p_league_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_match jsonb;
  v_enabled boolean := false;
  v_margin numeric := 4;
  v_home_bonus smallint := 0;
  v_away_bonus smallint := 0;
begin
  v_match := public.get_my_live_match_v3(p_league_id);

  if v_match is null then
    return null;
  end if;

  select
    lower(
      coalesce(league.scoring_rules ->> 'goal_margin_enabled', 'false')
    ) = 'true',
    coalesce((league.scoring_rules ->> 'goal_margin')::numeric, 4),
    fixture.home_goal_margin_bonus,
    fixture.away_goal_margin_bonus
  into
    v_enabled,
    v_margin,
    v_home_bonus,
    v_away_bonus
  from public.fantasy_fixtures fixture
  join public.leagues league on league.id = fixture.league_id
  where fixture.id = (v_match ->> 'fixtureId')::uuid;

  return v_match || jsonb_build_object(
    'goalMargin',
      jsonb_build_object(
        'enabled', v_enabled,
        'minimum', v_margin,
        'applied', v_home_bonus = 1 or v_away_bonus = 1,
        'homeBonus', v_home_bonus,
        'awayBonus', v_away_bonus
      )
  );
end;
$$;

revoke all on function public.get_my_live_match_v4(uuid)
from public, anon, authenticated;

grant execute on function public.get_my_live_match_v4(uuid)
to authenticated;

create or replace function public.get_league_results_center_v3(
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
  v_enabled boolean := false;
  v_margin numeric := 4;
begin
  v_center := public.get_league_results_center_v2(p_league_id);

  select
    lower(
      coalesce(league.scoring_rules ->> 'goal_margin_enabled', 'false')
    ) = 'true',
    coalesce((league.scoring_rules ->> 'goal_margin')::numeric, 4)
  into v_enabled, v_margin
  from public.leagues league
  where league.id = p_league_id;

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
        fixture.home_goal_margin_bonus,
        fixture.away_goal_margin_bonus
      into v_fixture_row
      from public.fantasy_fixtures fixture
      where fixture.id = (v_fixture ->> 'id')::uuid;

      v_fixtures := v_fixtures || jsonb_build_array(
        v_fixture || jsonb_build_object(
          'homeGoalMarginBonus',
            coalesce(v_fixture_row.home_goal_margin_bonus, 0),
          'awayGoalMarginBonus',
            coalesce(v_fixture_row.away_goal_margin_bonus, 0)
        )
      );
    end loop;

    v_matchdays := v_matchdays || jsonb_build_array(
      v_matchday || jsonb_build_object('fixtures', v_fixtures)
    );
  end loop;

  return v_center || jsonb_build_object(
    'goalMarginEnabled', v_enabled,
    'goalMargin', v_margin,
    'matchdays', v_matchdays
  );
end;
$$;

revoke all on function public.get_league_results_center_v3(uuid)
from public, anon, authenticated;

grant execute on function public.get_league_results_center_v3(uuid)
to authenticated;

create or replace function public.update_league_settings_v6(
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
  p_goal_margin numeric
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
  if p_goal_margin is null
    or p_goal_margin < 1
    or p_goal_margin > 20 then
    raise exception 'Lo scarto minimo deve essere tra 1 e 20 punti.';
  end if;

  select updated.*
  into v_league
  from public.update_league_settings_v5(
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
    p_defense_modifier_min_defenders
  ) as updated;

  update public.leagues
  set
    scoring_rules = coalesce(scoring_rules, '{}'::jsonb)
      || jsonb_build_object(
        'goal_margin_enabled',
          coalesce(p_goal_margin_enabled, false),
        'goal_margin',
          p_goal_margin
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

revoke all on function public.update_league_settings_v6(
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
  numeric
) from public, anon, authenticated;

grant execute on function public.update_league_settings_v6(
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
  numeric
) to authenticated;

select
  exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'fantasy_fixtures'
      and column_name = 'home_goal_margin_bonus'
  ) as margin_storage_ready,
  to_regprocedure(
    'public.resolve_fantasy_fixture_goals(numeric,numeric,jsonb)'
  ) is not null as margin_engine_ready,
  pg_get_functiondef(
    'public.resolve_fantasy_fixture_goals(numeric,numeric,jsonb)'::regprocedure
  ) ilike '%v_home_base = v_away_base%'
    as equal_band_rule_ready,
  pg_get_functiondef(
    'public.resolve_fantasy_fixture_goals(numeric,numeric,jsonb)'::regprocedure
  ) ilike '%abs(p_home_points - p_away_points) >= v_margin%'
    as minimum_margin_rule_ready,
  pg_get_functiondef(
    'public.refresh_matchday_results_internal(uuid)'::regprocedure
  ) ilike '%home_goal_margin_bonus%'
    as result_refresh_connected,
  to_regprocedure(
    'public.get_my_live_match_v4(uuid)'
  ) is not null as live_margin_ready,
  to_regprocedure(
    'public.get_league_results_center_v3(uuid)'
  ) is not null as results_margin_ready,
  to_regprocedure(
    'public.update_league_settings_v6(uuid,boolean,integer,integer,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,integer,integer,integer,integer,integer,boolean,integer,boolean,numeric)'
  ) is not null as margin_settings_ready,
  has_function_privilege(
    'authenticated',
    'public.get_my_live_match_v4(uuid)',
    'EXECUTE'
  ) as live_access_ready,
  has_function_privilege(
    'authenticated',
    'public.get_league_results_center_v3(uuid)',
    'EXECUTE'
  ) as results_access_ready,
  has_function_privilege(
    'authenticated',
    'public.update_league_settings_v6(uuid,boolean,integer,integer,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,integer,integer,integer,integer,integer,boolean,integer,boolean,numeric)',
    'EXECUTE'
  ) as settings_access_ready,
  pg_get_functiondef(
    'public.update_league_settings_v6(uuid,boolean,integer,integer,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,integer,integer,integer,integer,integer,boolean,integer,boolean,numeric)'::regprocedure
  ) ilike '%fixture.finalized_at is null%'
    as official_results_protected;
