-- LEGHEVO development helper
-- Completa esclusivamente la rosa vuota di "Pippolandia" nella lega
-- "Serie A da Divano" usando il parco calciatori fittizi dello script 057.
--
-- Sicurezza:
-- - non cancella dati;
-- - non modifica Diavoli del Sud o altre squadre;
-- - si interrompe se Pippolandia possiede già rosa o movimenti;
-- - è pensato solo per l'ambiente di sviluppo/collaudo.

begin;

create temporary table leghevo_pippolandia_seed (
  athlete_id uuid primary key,
  role_code text not null,
  purchase_price integer not null
) on commit drop;

do $$
declare
  v_league public.leagues%rowtype;
  v_team public.fantasy_teams%rowtype;
  v_active_roster integer;
  v_transactions integer;
  v_selected integer;
  v_total_spent integer;
begin
  select league_row.*
  into v_league
  from public.leagues league_row
  where league_row.name in ('Serie A da Divano', 'Seria A da Divano')
  order by
    case when league_row.name = 'Serie A da Divano' then 0 else 1 end,
    league_row.created_at desc
  limit 1;

  if v_league.id is null then
    raise exception 'Lega "Serie A da Divano" non trovata.';
  end if;

  select team_row.*
  into v_team
  from public.fantasy_teams team_row
  where team_row.league_id = v_league.id
    and team_row.name = 'Pippolandia'
  limit 1;

  if v_team.id is null then
    raise exception 'Squadra "Pippolandia" non trovata nella lega selezionata.';
  end if;

  select count(*)::integer
  into v_active_roster
  from public.roster_entries roster
  where roster.fantasy_team_id = v_team.id
    and roster.released_at is null;

  select count(*)::integer
  into v_transactions
  from public.team_transactions transaction_row
  where transaction_row.fantasy_team_id = v_team.id;

  if v_active_roster > 0 or v_transactions > 0 then
    raise exception using
      message = 'Pippolandia possiede già rosa o movimenti: seed annullato per sicurezza.',
      detail = format(
        'Rosa attiva: %s, movimenti: %s.',
        v_active_roster,
        v_transactions
      );
  end if;

  insert into leghevo_pippolandia_seed (
    athlete_id,
    role_code,
    purchase_price
  )
  select
    ranked.athlete_id,
    ranked.role_code,
    case ranked.role_code
      when 'P' then (array[5, 4, 3])[ranked.role_rank]
      when 'D' then (array[8, 7, 6, 5, 4, 3, 2, 1])[ranked.role_rank]
      when 'C' then (array[8, 7, 6, 5, 4, 3, 2, 1])[ranked.role_rank]
      when 'A' then (array[10, 8, 6, 5, 4, 3])[ranked.role_rank]
    end as purchase_price
  from (
    select
      athlete.id as athlete_id,
      role.role_code,
      row_number() over (
        partition by role.role_code
        order by athlete.provider_player_id
      )::integer as role_rank
    from public.athletes athlete
    join public.athlete_roles role
      on role.athlete_id = athlete.id
     and role.mode = 'classic'
     and role.role_code in ('P', 'D', 'C', 'A')
    where athlete.provider = 'leghevo-development-pool'
      and athlete.active = true
      and not exists (
        select 1
        from public.roster_entries occupied
        where occupied.league_id = v_league.id
          and occupied.athlete_id = athlete.id
          and occupied.released_at is null
      )
  ) ranked
  where
    (ranked.role_code = 'P' and ranked.role_rank <= 3)
    or (ranked.role_code = 'D' and ranked.role_rank <= 8)
    or (ranked.role_code = 'C' and ranked.role_rank <= 8)
    or (ranked.role_code = 'A' and ranked.role_rank <= 6);

  select count(*)::integer, coalesce(sum(seed.purchase_price), 0)::integer
  into v_selected, v_total_spent
  from leghevo_pippolandia_seed seed;

  if v_selected <> 25 then
    raise exception using
      message = 'Parco calciatori insufficiente per completare Pippolandia.',
      detail = format('Attesi 25 calciatori, selezionati %s.', v_selected);
  end if;

  if v_league.starting_credits < v_total_spent then
    raise exception 'Crediti iniziali insufficienti per applicare il seed.';
  end if;

  insert into public.roster_entries (
    league_id,
    fantasy_team_id,
    athlete_id,
    purchase_price,
    acquired_at
  )
  select
    v_league.id,
    v_team.id,
    seed.athlete_id,
    seed.purchase_price,
    now()
  from leghevo_pippolandia_seed seed
  order by
    case seed.role_code
      when 'P' then 1
      when 'D' then 2
      when 'C' then 3
      else 4
    end,
    seed.purchase_price desc;

  insert into public.team_transactions (
    league_id,
    fantasy_team_id,
    athlete_id,
    transaction_type,
    credit_delta,
    metadata
  )
  select
    v_league.id,
    v_team.id,
    seed.athlete_id,
    'market_purchase',
    -seed.purchase_price,
    jsonb_build_object(
      'source', 'development_seed',
      'script', '058_development_pippolandia_roster'
    )
  from leghevo_pippolandia_seed seed;

  update public.fantasy_teams
  set credits_remaining = v_league.starting_credits - v_total_spent
  where id = v_team.id;

  raise notice 'Pippolandia completata: 25 calciatori, % crediti spesi, % residui.',
    v_total_spent,
    v_league.starting_credits - v_total_spent;
end;
$$;

commit;

-- Controllo finale atteso: 25 totali, 3 P, 8 D, 8 C, 6 A.
select
  team.name as squadra,
  team.credits_remaining as crediti_residui,
  count(*)::integer as totale_calciatori,
  count(*) filter (where role.role_code = 'P')::integer as portieri,
  count(*) filter (where role.role_code = 'D')::integer as difensori,
  count(*) filter (where role.role_code = 'C')::integer as centrocampisti,
  count(*) filter (where role.role_code = 'A')::integer as attaccanti,
  sum(roster.purchase_price)::integer as crediti_spesi
from public.fantasy_teams team
join public.leagues league
  on league.id = team.league_id
join public.roster_entries roster
  on roster.fantasy_team_id = team.id
 and roster.released_at is null
join public.athlete_roles role
  on role.athlete_id = roster.athlete_id
 and role.mode = 'classic'
where league.name in ('Serie A da Divano', 'Seria A da Divano')
  and team.name = 'Pippolandia'
group by team.id, team.name, team.credits_remaining;
