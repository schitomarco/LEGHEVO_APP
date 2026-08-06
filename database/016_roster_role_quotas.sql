-- LEGHEVO · composizione rosa e limiti per reparto
-- Eseguire nel SQL Editor di Supabase dopo 015.

create or replace function public.athlete_roster_group(
  p_athlete_id uuid,
  p_mode public.league_mode
)
returns text
language sql
stable
set search_path = ''
as $$
  select
    case
      when p_mode = 'classic' and role.role_code = 'P'
        then 'goalkeepers'
      when p_mode = 'classic' and role.role_code = 'D'
        then 'defenders'
      when p_mode = 'classic' and role.role_code = 'C'
        then 'midfielders'
      when p_mode = 'classic' and role.role_code = 'A'
        then 'attackers'
      when p_mode = 'mantra' and role.role_code = 'Por'
        then 'goalkeepers'
      when p_mode = 'mantra'
        and role.role_code in ('Dc', 'Dd', 'Ds', 'E')
        then 'defenders'
      when p_mode = 'mantra'
        and role.role_code in ('M', 'C', 'W', 'T')
        then 'midfielders'
      when p_mode = 'mantra'
        and role.role_code in ('A', 'Pc')
        then 'attackers'
      else null
    end
  from public.athlete_roles role
  where role.athlete_id = p_athlete_id
    and role.mode = p_mode
  order by
    case
      when role.role_code in ('P', 'Por') then 1
      when role.role_code in ('D', 'Dc', 'Dd', 'Ds', 'E') then 2
      when role.role_code in ('C', 'M', 'W', 'T') then 3
      when role.role_code in ('A', 'Pc') then 4
      else 5
    end
  limit 1;
$$;

create or replace function public.default_roster_quota(
  p_roster_size integer,
  p_group text
)
returns integer
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_goalkeepers integer;
  v_defenders integer;
  v_midfielders integer;
  v_attackers integer;
  v_remaining integer;
begin
  if p_roster_size is null or p_roster_size < 11 then
    raise exception 'Dimensione rosa non valida.';
  end if;

  v_goalkeepers := greatest(
    1,
    round(p_roster_size * 0.12)::integer
  );
  v_remaining := p_roster_size - v_goalkeepers;
  v_defenders := greatest(3, round(v_remaining * 0.36)::integer);
  v_midfielders := greatest(3, round(v_remaining * 0.36)::integer);
  v_attackers :=
    p_roster_size - v_goalkeepers - v_defenders - v_midfielders;

  return case lower(trim(coalesce(p_group, '')))
    when 'goalkeepers' then v_goalkeepers
    when 'defenders' then v_defenders
    when 'midfielders' then v_midfielders
    when 'attackers' then v_attackers
    else null
  end;
end;
$$;

create or replace function public.league_roster_quota(
  p_league_id uuid,
  p_group text
)
returns integer
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    case lower(trim(coalesce(p_group, '')))
      when 'goalkeepers' then
        (league.scoring_rules ->> 'roster_quota_goalkeepers')::integer
      when 'defenders' then
        (league.scoring_rules ->> 'roster_quota_defenders')::integer
      when 'midfielders' then
        (league.scoring_rules ->> 'roster_quota_midfielders')::integer
      when 'attackers' then
        (league.scoring_rules ->> 'roster_quota_attackers')::integer
      else null
    end,
    public.default_roster_quota(
      league.roster_size,
      lower(trim(coalesce(p_group, '')))
    )
  )
  from public.leagues league
  where league.id = p_league_id;
$$;

create or replace function public.assert_team_can_add_athlete(
  p_fantasy_team_id uuid,
  p_athlete_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_team public.fantasy_teams%rowtype;
  v_mode public.league_mode;
  v_group text;
  v_current_count integer;
  v_quota integer;
  v_group_label text;
begin
  select team.*
  into v_team
  from public.fantasy_teams team
  where team.id = p_fantasy_team_id;

  if not found then
    raise exception 'Squadra non trovata.';
  end if;

  select league.mode
  into v_mode
  from public.leagues league
  where league.id = v_team.league_id;

  v_group := public.athlete_roster_group(p_athlete_id, v_mode);
  if v_group is null then
    raise exception 'Il calciatore non ha un ruolo compatibile con questa lega.';
  end if;

  select count(*)::integer
  into v_current_count
  from public.roster_entries roster
  where roster.fantasy_team_id = p_fantasy_team_id
    and roster.released_at is null
    and public.athlete_roster_group(roster.athlete_id, v_mode) = v_group;

  v_quota := public.league_roster_quota(v_team.league_id, v_group);
  v_group_label := case v_group
    when 'goalkeepers' then 'portieri'
    when 'defenders' then 'difensori'
    when 'midfielders' then 'centrocampisti'
    when 'attackers' then 'attaccanti'
    else 'calciatori'
  end;

  if v_current_count >= v_quota then
    raise exception
      'Limite raggiunto: la rosa può avere al massimo % %.',
      v_quota,
      v_group_label;
  end if;
end;
$$;

create or replace function public.assert_team_roster_quotas(
  p_fantasy_team_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_team public.fantasy_teams%rowtype;
  v_mode public.league_mode;
  v_total integer;
  v_goalkeepers integer;
  v_defenders integer;
  v_midfielders integer;
  v_attackers integer;
begin
  select team.*
  into v_team
  from public.fantasy_teams team
  where team.id = p_fantasy_team_id;

  if not found then
    raise exception 'Squadra non trovata.';
  end if;

  select league.mode
  into v_mode
  from public.leagues league
  where league.id = v_team.league_id;

  select
    count(*)::integer,
    count(*) filter (
      where public.athlete_roster_group(
        roster.athlete_id,
        v_mode
      ) = 'goalkeepers'
    )::integer,
    count(*) filter (
      where public.athlete_roster_group(
        roster.athlete_id,
        v_mode
      ) = 'defenders'
    )::integer,
    count(*) filter (
      where public.athlete_roster_group(
        roster.athlete_id,
        v_mode
      ) = 'midfielders'
    )::integer,
    count(*) filter (
      where public.athlete_roster_group(
        roster.athlete_id,
        v_mode
      ) = 'attackers'
    )::integer
  into
    v_total,
    v_goalkeepers,
    v_defenders,
    v_midfielders,
    v_attackers
  from public.roster_entries roster
  where roster.fantasy_team_id = p_fantasy_team_id
    and roster.released_at is null;

  if v_total <>
    v_goalkeepers + v_defenders + v_midfielders + v_attackers then
    raise exception 'La rosa contiene un calciatore senza reparto valido.';
  end if;

  if v_goalkeepers >
    public.league_roster_quota(v_team.league_id, 'goalkeepers') then
    raise exception 'La rosa supera il limite dei portieri.';
  end if;
  if v_defenders >
    public.league_roster_quota(v_team.league_id, 'defenders') then
    raise exception 'La rosa supera il limite dei difensori.';
  end if;
  if v_midfielders >
    public.league_roster_quota(v_team.league_id, 'midfielders') then
    raise exception 'La rosa supera il limite dei centrocampisti.';
  end if;
  if v_attackers >
    public.league_roster_quota(v_team.league_id, 'attackers') then
    raise exception 'La rosa supera il limite degli attaccanti.';
  end if;
end;
$$;

create or replace function public.guard_bid_roster_quota()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_athlete_id uuid;
begin
  select item.athlete_id
  into v_athlete_id
  from public.auction_items item
  where item.id = new.auction_item_id;

  if not found then
    raise exception 'Lotto asta non trovato.';
  end if;

  perform public.assert_team_can_add_athlete(
    new.fantasy_team_id,
    v_athlete_id
  );
  return new;
end;
$$;

drop trigger if exists bid_roster_quota_guard on public.bids;

create trigger bid_roster_quota_guard
before insert on public.bids
for each row execute function public.guard_bid_roster_quota();

create or replace function public.guard_roster_role_quotas()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.released_at is null then
    perform public.assert_team_roster_quotas(new.fantasy_team_id);
  end if;
  return null;
end;
$$;

drop trigger if exists roster_role_quota_guard
on public.roster_entries;

create constraint trigger roster_role_quota_guard
after insert or update on public.roster_entries
deferrable initially deferred
for each row execute function public.guard_roster_role_quotas();

create or replace function public.update_league_settings_v3(
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
  p_roster_attackers integer
)
returns public.leagues
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_league public.leagues%rowtype;
  v_team_id uuid;
  v_total integer;
  v_goalkeepers integer;
  v_defenders integer;
  v_midfielders integer;
  v_attackers integer;
begin
  if auth.uid() is null then
    raise exception 'Devi effettuare l''accesso.';
  end if;

  if not public.is_league_admin(p_league_id) then
    raise exception 'Solo il Presidente può cambiare le regole della lega.';
  end if;

  select league.*
  into v_league
  from public.leagues league
  where league.id = p_league_id
  for update;

  if not found then
    raise exception 'Lega non trovata.';
  end if;

  if p_roster_goalkeepers is null
    or p_roster_goalkeepers < 1
    or p_roster_defenders is null
    or p_roster_defenders < 3
    or p_roster_midfielders is null
    or p_roster_midfielders < 3
    or p_roster_attackers is null
    or p_roster_attackers < 1 then
    raise exception
      'Servono almeno 1 portiere, 3 difensori, 3 centrocampisti e 1 attaccante.';
  end if;

  if p_roster_goalkeepers
      + p_roster_defenders
      + p_roster_midfielders
      + p_roster_attackers
      <> v_league.roster_size then
    raise exception
      'Le quote dei reparti devono totalizzare % calciatori.',
      v_league.roster_size;
  end if;

  for v_team_id in
    select team.id
    from public.fantasy_teams team
    where team.league_id = p_league_id
  loop
    select
      count(*)::integer,
      count(*) filter (
        where public.athlete_roster_group(
          roster.athlete_id,
          v_league.mode
        ) = 'goalkeepers'
      )::integer,
      count(*) filter (
        where public.athlete_roster_group(
          roster.athlete_id,
          v_league.mode
        ) = 'defenders'
      )::integer,
      count(*) filter (
        where public.athlete_roster_group(
          roster.athlete_id,
          v_league.mode
        ) = 'midfielders'
      )::integer,
      count(*) filter (
        where public.athlete_roster_group(
          roster.athlete_id,
          v_league.mode
        ) = 'attackers'
      )::integer
    into
      v_total,
      v_goalkeepers,
      v_defenders,
      v_midfielders,
      v_attackers
    from public.roster_entries roster
    where roster.fantasy_team_id = v_team_id
      and roster.released_at is null;

    if v_total <>
      v_goalkeepers + v_defenders + v_midfielders + v_attackers then
      raise exception 'Una rosa contiene un calciatore senza reparto valido.';
    end if;

    if v_goalkeepers > p_roster_goalkeepers
      or v_defenders > p_roster_defenders
      or v_midfielders > p_roster_midfielders
      or v_attackers > p_roster_attackers then
      raise exception
        'Una rosa esistente supera le nuove quote. Prima sistema i reparti.';
    end if;
  end loop;

  select updated.*
  into v_league
  from public.update_league_settings_v2(
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
    p_malus_goal_conceded
  ) as updated;

  update public.leagues
  set
    scoring_rules = coalesce(scoring_rules, '{}'::jsonb)
      || jsonb_build_object(
        'roster_quota_goalkeepers', p_roster_goalkeepers,
        'roster_quota_defenders', p_roster_defenders,
        'roster_quota_midfielders', p_roster_midfielders,
        'roster_quota_attackers', p_roster_attackers
      ),
    updated_at = now()
  where id = p_league_id
  returning * into v_league;

  return v_league;
end;
$$;

revoke all on function public.update_league_settings_v3(
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
  integer
) from public;

grant execute on function public.update_league_settings_v3(
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
  integer
) to authenticated;

select
  to_regprocedure(
    'public.athlete_roster_group(uuid,public.league_mode)'
  ) is not null as role_groups_ready,
  to_regprocedure(
    'public.default_roster_quota(integer,text)'
  ) is not null as quota_defaults_ready,
  to_regprocedure(
    'public.league_roster_quota(uuid,text)'
  ) is not null as league_quotas_ready,
  exists (
    select 1
    from pg_trigger
    where tgname = 'bid_roster_quota_guard'
      and not tgisinternal
  ) as auction_quota_guard_ready,
  exists (
    select 1
    from pg_trigger
    where tgname = 'roster_role_quota_guard'
      and not tgisinternal
  ) as roster_quota_guard_ready,
  to_regprocedure(
    'public.update_league_settings_v3(uuid,boolean,integer,integer,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,integer,integer,integer,integer)'
  ) is not null as roster_settings_ready;
