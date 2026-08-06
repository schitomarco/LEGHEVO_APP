-- LEGHEVO · bonus e malus configurabili per lega
-- Eseguire nel SQL Editor di Supabase dopo 013.

create or replace function public.calculate_league_fantasy_score(
  p_provider_rating numeric,
  p_standard_fantasy_score numeric,
  p_raw_statistics jsonb,
  p_scoring_rules jsonb default '{}'::jsonb
)
returns numeric
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_goals numeric;
  v_assists numeric;
  v_penalties_saved numeric;
  v_yellow_cards numeric;
  v_red_cards numeric;
  v_penalties_missed numeric;
  v_goals_conceded numeric;
  v_result numeric;
begin
  if p_provider_rating is null then
    return null;
  end if;

  -- I vecchi dati dimostrativi non contengono la struttura completa
  -- del provider: in quel caso conserviamo il fantavoto già calcolato.
  if p_raw_statistics is null
    or not (p_raw_statistics ? 'games') then
    return coalesce(p_standard_fantasy_score, p_provider_rating);
  end if;

  v_goals :=
    coalesce((p_raw_statistics #>> '{goals,total}')::numeric, 0);
  v_assists :=
    coalesce((p_raw_statistics #>> '{goals,assists}')::numeric, 0);
  v_penalties_saved :=
    coalesce((p_raw_statistics #>> '{penalty,saved}')::numeric, 0);
  v_yellow_cards :=
    coalesce((p_raw_statistics #>> '{cards,yellow}')::numeric, 0);
  v_red_cards :=
    coalesce((p_raw_statistics #>> '{cards,red}')::numeric, 0);
  v_penalties_missed :=
    coalesce((p_raw_statistics #>> '{penalty,missed}')::numeric, 0);
  v_goals_conceded :=
    case
      when p_raw_statistics #>> '{games,position}' = 'G' then
        coalesce((p_raw_statistics #>> '{goals,conceded}')::numeric, 0)
      else 0
    end;

  v_result :=
    p_provider_rating
    + v_goals
      * coalesce((p_scoring_rules ->> 'bonus_goal')::numeric, 3)
    + v_assists
      * coalesce((p_scoring_rules ->> 'bonus_assist')::numeric, 1)
    + v_penalties_saved
      * coalesce((p_scoring_rules ->> 'bonus_penalty_saved')::numeric, 3)
    - v_yellow_cards
      * coalesce((p_scoring_rules ->> 'malus_yellow_card')::numeric, 0.5)
    - v_red_cards
      * coalesce((p_scoring_rules ->> 'malus_red_card')::numeric, 1)
    - v_penalties_missed
      * coalesce((p_scoring_rules ->> 'malus_penalty_missed')::numeric, 3)
    - v_goals_conceded
      * coalesce((p_scoring_rules ->> 'malus_goal_conceded')::numeric, 1);

  return round(v_result, 2);
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
  v_scoring_rules jsonb;
  v_starter_count integer;
  v_starter record;
  v_score record;
  v_substitute record;
  v_used_bench_ids uuid[] := array[]::uuid[];
begin
  total_points := 0;
  is_ready := true;
  counted_players := 0;

  select lineup.id, league.mode, league.scoring_rules
  into v_lineup_id, v_mode, v_scoring_rules
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
      public.calculate_league_fantasy_score(
        score.provider_rating,
        score.fantasy_score,
        score.raw_statistics,
        v_scoring_rules
      ) as fantasy_score,
      score.is_final
    into v_score
    from public.player_match_scores score
    where score.athlete_id = v_starter.athlete_id
      and score.matchday_id = p_matchday_id
      and score.provider_rating is not null;

    if found then
      total_points := total_points + v_score.fantasy_score;
      counted_players := counted_players + 1;
      is_ready := is_ready and v_score.is_final;
      continue;
    end if;

    select
      bench.athlete_id,
      public.calculate_league_fantasy_score(
        score.provider_rating,
        score.fantasy_score,
        score.raw_statistics,
        v_scoring_rules
      ) as fantasy_score,
      score.is_final
    into v_substitute
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

create or replace function public.update_league_settings_v2(
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
  p_malus_goal_conceded numeric
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
  if auth.uid() is null then
    raise exception 'Devi effettuare l''accesso.';
  end if;

  if not public.is_league_admin(p_league_id) then
    raise exception 'Solo il Presidente può cambiare le regole della lega.';
  end if;

  if p_market_open is null then
    raise exception 'Lo stato del mercato è obbligatorio.';
  end if;

  if p_market_min_price is null
    or p_market_min_price < 1
    or p_market_min_price > 1000 then
    raise exception 'Il prezzo minimo deve essere tra 1 e 1000 crediti.';
  end if;

  if p_release_refund_percent is null
    or p_release_refund_percent < 0
    or p_release_refund_percent > 100 then
    raise exception 'Il rimborso deve essere una percentuale tra 0 e 100.';
  end if;

  if p_goal_threshold is null
    or p_goal_threshold < 50
    or p_goal_threshold > 100 then
    raise exception 'La soglia del primo gol deve essere tra 50 e 100.';
  end if;

  if p_goal_step is null
    or p_goal_step < 1
    or p_goal_step > 20 then
    raise exception 'La fascia gol deve essere tra 1 e 20 punti.';
  end if;

  if p_home_bonus is null
    or p_home_bonus < 0
    or p_home_bonus > 10 then
    raise exception 'Il bonus casa deve essere tra 0 e 10 punti.';
  end if;

  if p_bonus_goal is null
    or p_bonus_goal < 0
    or p_bonus_goal > 10
    or p_bonus_assist is null
    or p_bonus_assist < 0
    or p_bonus_assist > 5
    or p_bonus_penalty_saved is null
    or p_bonus_penalty_saved < 0
    or p_bonus_penalty_saved > 10 then
    raise exception 'Controlla i valori dei bonus.';
  end if;

  if p_malus_yellow_card is null
    or p_malus_yellow_card < 0
    or p_malus_yellow_card > 5
    or p_malus_red_card is null
    or p_malus_red_card < 0
    or p_malus_red_card > 10
    or p_malus_penalty_missed is null
    or p_malus_penalty_missed < 0
    or p_malus_penalty_missed > 10
    or p_malus_goal_conceded is null
    or p_malus_goal_conceded < 0
    or p_malus_goal_conceded > 5 then
    raise exception 'Controlla i valori dei malus.';
  end if;

  update public.leagues
  set
    scoring_rules = coalesce(scoring_rules, '{}'::jsonb)
      || jsonb_build_object(
        'market_open', p_market_open,
        'market_min_price', p_market_min_price,
        'release_refund_percent', p_release_refund_percent,
        'goal_threshold', p_goal_threshold,
        'goal_step', p_goal_step,
        'home_bonus', p_home_bonus,
        'bonus_goal', p_bonus_goal,
        'bonus_assist', p_bonus_assist,
        'bonus_penalty_saved', p_bonus_penalty_saved,
        'malus_yellow_card', p_malus_yellow_card,
        'malus_red_card', p_malus_red_card,
        'malus_penalty_missed', p_malus_penalty_missed,
        'malus_goal_conceded', p_malus_goal_conceded
      ),
    updated_at = now()
  where id = p_league_id
  returning * into v_league;

  if not found then
    raise exception 'Lega non trovata.';
  end if;

  for v_matchday_id in
    select distinct fixture.matchday_id
    from public.fantasy_fixtures fixture
    where fixture.league_id = p_league_id
  loop
    perform public.refresh_matchday_results_internal(v_matchday_id);
  end loop;

  return v_league;
end;
$$;

revoke all on function public.update_league_settings_v2(
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
  numeric
) from public;

grant execute on function public.update_league_settings_v2(
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
  numeric
) to authenticated;

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
    'public.calculate_league_fantasy_score(numeric,numeric,jsonb,jsonb)'
  ) is not null as custom_scoring_ready,
  to_regprocedure(
    'public.calculate_team_matchday_points(uuid,uuid)'
  ) is not null as team_totals_ready,
  to_regprocedure(
    'public.update_league_settings_v2(uuid,boolean,integer,integer,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric)'
  ) is not null as scoring_settings_ready;
