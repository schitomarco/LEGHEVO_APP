-- LEGHEVO · fasce gol personalizzate
-- Eseguire nel SQL Editor di Supabase dopo 035.

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
  v_custom_enabled boolean :=
    lower(
      coalesce(p_scoring_rules ->> 'goal_bands_enabled', 'false')
    ) = 'true';
  v_bands jsonb := coalesce(
    p_scoring_rules -> 'goal_bands',
    '[]'::jsonb
  );
  v_valid boolean := false;
  v_band_text text;
  v_band numeric;
  v_previous_band numeric;
  v_first_band numeric;
  v_last_band numeric;
  v_last_step numeric;
  v_band_count integer := 0;
  v_custom_goals integer := 0;
begin
  if p_points is null then
    return null;
  end if;

  if v_custom_enabled
    and jsonb_typeof(v_bands) = 'array'
    and jsonb_array_length(v_bands) = 6 then
    v_valid := true;

    for v_band_text in
      select band.value
      from jsonb_array_elements_text(v_bands)
        with ordinality as band(value, position)
      order by band.position
    loop
      if v_band_text !~ '^-?[0-9]+([.][0-9]+)?$' then
        v_valid := false;
        exit;
      end if;

      v_band := v_band_text::numeric;
      v_band_count := v_band_count + 1;

      if v_band < 50
        or v_band > 150
        or (
          v_previous_band is not null
          and v_band <= v_previous_band
        ) then
        v_valid := false;
        exit;
      end if;

      if v_band_count = 1 then
        v_first_band := v_band;
      end if;

      if p_points >= v_band then
        v_custom_goals := v_band_count;
      end if;

      v_previous_band := v_band;
      v_last_band := v_band;
    end loop;

    v_valid :=
      v_valid
      and v_band_count = 6
      and v_first_band between 50 and 100;

    if v_valid then
      select
        (v_bands ->> 5)::numeric - (v_bands ->> 4)::numeric
      into v_last_step;

      if p_points >= v_last_band and v_last_step > 0 then
        v_custom_goals :=
          v_band_count
          + floor((p_points - v_last_band) / v_last_step)::integer;
      end if;

      return least(v_custom_goals, 32767)::smallint;
    end if;
  end if;

  if v_step <= 0 then
    v_step := 6;
  end if;

  if p_points < v_threshold then
    return 0;
  end if;

  return least(
    floor((p_points - v_threshold) / v_step) + 1,
    32767
  )::smallint;
end;
$$;

revoke all on function public.fantasy_goals_from_points(
  numeric,
  jsonb
) from public, anon, authenticated;

create or replace function public.get_my_live_match_v5(
  p_league_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_match jsonb;
  v_rules jsonb := '{}'::jsonb;
  v_enabled boolean := false;
  v_threshold numeric := 66;
  v_step numeric := 6;
  v_bands jsonb;
begin
  v_match := public.get_my_live_match_v4(p_league_id);

  if v_match is null then
    return null;
  end if;

  select coalesce(league.scoring_rules, '{}'::jsonb)
  into v_rules
  from public.leagues league
  where league.id = p_league_id;

  v_enabled :=
    lower(coalesce(v_rules ->> 'goal_bands_enabled', 'false')) = 'true';
  v_threshold :=
    coalesce((v_rules ->> 'goal_threshold')::numeric, 66);
  v_step :=
    coalesce((v_rules ->> 'goal_step')::numeric, 6);

  v_bands := case
    when jsonb_typeof(v_rules -> 'goal_bands') = 'array'
      and jsonb_array_length(v_rules -> 'goal_bands') = 6
      then v_rules -> 'goal_bands'
    else jsonb_build_array(
      v_threshold,
      v_threshold + v_step,
      v_threshold + v_step * 2,
      v_threshold + v_step * 3,
      v_threshold + v_step * 4,
      v_threshold + v_step * 5
    )
  end;

  return v_match || jsonb_build_object(
    'goalBands',
      jsonb_build_object(
        'enabled', v_enabled,
        'thresholds', v_bands
      )
  );
end;
$$;

revoke all on function public.get_my_live_match_v5(uuid)
from public, anon, authenticated;

grant execute on function public.get_my_live_match_v5(uuid)
to authenticated;

create or replace function public.get_league_results_center_v4(
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
  v_rules jsonb := '{}'::jsonb;
  v_enabled boolean := false;
  v_threshold numeric := 66;
  v_step numeric := 6;
  v_bands jsonb;
begin
  v_center := public.get_league_results_center_v3(p_league_id);

  select coalesce(league.scoring_rules, '{}'::jsonb)
  into v_rules
  from public.leagues league
  where league.id = p_league_id;

  v_enabled :=
    lower(coalesce(v_rules ->> 'goal_bands_enabled', 'false')) = 'true';
  v_threshold :=
    coalesce((v_rules ->> 'goal_threshold')::numeric, 66);
  v_step :=
    coalesce((v_rules ->> 'goal_step')::numeric, 6);

  v_bands := case
    when jsonb_typeof(v_rules -> 'goal_bands') = 'array'
      and jsonb_array_length(v_rules -> 'goal_bands') = 6
      then v_rules -> 'goal_bands'
    else jsonb_build_array(
      v_threshold,
      v_threshold + v_step,
      v_threshold + v_step * 2,
      v_threshold + v_step * 3,
      v_threshold + v_step * 4,
      v_threshold + v_step * 5
    )
  end;

  return v_center || jsonb_build_object(
    'goalBandsEnabled', v_enabled,
    'goalBands', v_bands
  );
end;
$$;

revoke all on function public.get_league_results_center_v4(uuid)
from public, anon, authenticated;

grant execute on function public.get_league_results_center_v4(uuid)
to authenticated;

create or replace function public.update_league_settings_v7(
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
  p_goal_bands numeric[]
)
returns public.leagues
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_league public.leagues%rowtype;
  v_matchday_id uuid;
  v_index integer;
begin
  if p_goal_bands is null
    or cardinality(p_goal_bands) <> 6 then
    raise exception 'Inserisci esattamente sei fasce gol.';
  end if;

  for v_index in 1..6 loop
    if p_goal_bands[v_index] is null
      or p_goal_bands[v_index] < 50
      or p_goal_bands[v_index] > 150 then
      raise exception 'Ogni fascia gol deve essere tra 50 e 150 punti.';
    end if;

    if v_index > 1
      and p_goal_bands[v_index] <= p_goal_bands[v_index - 1] then
      raise exception 'Le fasce gol devono essere strettamente crescenti.';
    end if;
  end loop;

  if p_goal_bands[1] > 100 then
    raise exception 'La soglia del primo gol deve essere tra 50 e 100.';
  end if;

  select updated.*
  into v_league
  from public.update_league_settings_v6(
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
    p_goal_margin
  ) as updated;

  update public.leagues
  set
    scoring_rules = coalesce(scoring_rules, '{}'::jsonb)
      || jsonb_build_object(
        'goal_bands_enabled',
          coalesce(p_goal_bands_enabled, false),
        'goal_bands',
          to_jsonb(p_goal_bands)
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

revoke all on function public.update_league_settings_v7(
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
  numeric[]
) from public, anon, authenticated;

grant execute on function public.update_league_settings_v7(
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
  numeric[]
) to authenticated;

select
  to_regprocedure(
    'public.fantasy_goals_from_points(numeric,jsonb)'
  ) is not null as goal_band_engine_ready,
  pg_get_functiondef(
    'public.fantasy_goals_from_points(numeric,jsonb)'::regprocedure
  ) ilike '%jsonb_array_elements_text%'
    as custom_thresholds_ready,
  pg_get_functiondef(
    'public.fantasy_goals_from_points(numeric,jsonb)'::regprocedure
  ) ilike '%v_last_step%'
    as extra_goals_ready,
  pg_get_functiondef(
    'public.fantasy_goals_from_points(numeric,jsonb)'::regprocedure
  ) ilike '%v_threshold%'
    as standard_fallback_ready,
  to_regprocedure(
    'public.get_my_live_match_v5(uuid)'
  ) is not null as live_goal_bands_ready,
  to_regprocedure(
    'public.get_league_results_center_v4(uuid)'
  ) is not null as results_goal_bands_ready,
  to_regprocedure(
    'public.update_league_settings_v7(uuid,boolean,integer,integer,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,integer,integer,integer,integer,integer,boolean,integer,boolean,numeric,boolean,numeric[])'
  ) is not null as goal_band_settings_ready,
  has_function_privilege(
    'authenticated',
    'public.get_my_live_match_v5(uuid)',
    'EXECUTE'
  ) as live_access_ready,
  has_function_privilege(
    'authenticated',
    'public.get_league_results_center_v4(uuid)',
    'EXECUTE'
  ) as results_access_ready,
  has_function_privilege(
    'authenticated',
    'public.update_league_settings_v7(uuid,boolean,integer,integer,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,integer,integer,integer,integer,integer,boolean,integer,boolean,numeric,boolean,numeric[])',
    'EXECUTE'
  ) as settings_access_ready,
  pg_get_functiondef(
    'public.update_league_settings_v7(uuid,boolean,integer,integer,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,integer,integer,integer,integer,integer,boolean,integer,boolean,numeric,boolean,numeric[])'::regprocedure
  ) ilike '%cardinality(p_goal_bands) <> 6%'
    as six_thresholds_validation_ready,
  pg_get_functiondef(
    'public.update_league_settings_v7(uuid,boolean,integer,integer,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,integer,integer,integer,integer,integer,boolean,integer,boolean,numeric,boolean,numeric[])'::regprocedure
  ) ilike '%fixture.finalized_at is null%'
    as official_results_protected;
