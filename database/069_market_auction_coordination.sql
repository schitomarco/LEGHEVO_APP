-- LEGHEVO · coordinamento Mercato libero e Asta Live
-- Versione applicativa: 0.57.4
-- Eseguire dopo 068_live_auction_safety.sql.
-- Script idempotente: può essere eseguito più volte.

begin;

-- Ricerca rapida del calciatore attualmente bloccato da un lotto live.
create index if not exists auction_items_live_athlete_idx
  on public.auction_items (athlete_id, auction_id)
  where status = 'bidding';

create or replace function public.athlete_in_live_auction(
  p_league_id uuid,
  p_athlete_id uuid
)
returns boolean
language sql
security definer
stable
set search_path = ''
as $$
  select exists (
    select 1
    from public.auction_items item
    join public.auctions auction on auction.id = item.auction_id
    where auction.league_id = p_league_id
      and auction.status in ('live', 'paused')
      and auction.current_item_id = item.id
      and item.athlete_id = p_athlete_id
      and item.status = 'bidding'
  );
$$;

revoke all on function public.athlete_in_live_auction(uuid, uuid)
from public;
grant execute on function public.athlete_in_live_auction(uuid, uuid)
to authenticated;

-- Acquisto dal mercato libero coordinato con il banco dell'Asta Live.
-- Il blocco advisory condiviso con la nomina rende atomica la decisione anche
-- quando due dispositivi provano le due operazioni nello stesso istante.
create or replace function public.sign_free_agent(
  p_fantasy_team_id uuid,
  p_athlete_id uuid
)
returns public.roster_entries
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_team public.fantasy_teams%rowtype;
  v_league public.leagues%rowtype;
  v_roster_count integer;
  v_price integer;
  v_required_reserve integer;
  v_result public.roster_entries%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Devi effettuare l''accesso.';
  end if;

  select team.*
  into v_team
  from public.fantasy_teams team
  where team.id = p_fantasy_team_id
  for update;

  if not found then
    raise exception 'Squadra non trovata.';
  end if;

  if v_team.manager_id <> auth.uid()
    and not public.is_league_admin(v_team.league_id) then
    raise exception 'Puoi acquistare soltanto per la tua squadra.';
  end if;

  select league.*
  into v_league
  from public.leagues league
  where league.id = v_team.league_id;

  if v_league.status in ('completed', 'archived') then
    raise exception 'Il mercato di questa lega è chiuso.';
  end if;

  if coalesce(v_league.scoring_rules ->> 'market_open', 'true') = 'false' then
    raise exception 'Il Presidente ha chiuso il mercato.';
  end if;

  if not exists (
    select 1
    from public.athletes athlete
    where athlete.id = p_athlete_id
      and athlete.active
  ) then
    raise exception 'Calciatore non disponibile.';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      v_team.league_id::text || ':' || p_athlete_id::text,
      0
    )
  );

  if public.athlete_in_live_auction(v_team.league_id, p_athlete_id) then
    raise exception
      'Questo calciatore è attualmente sul banco dell''Asta Live.';
  end if;

  if exists (
    select 1
    from public.roster_entries roster
    where roster.league_id = v_team.league_id
      and roster.athlete_id = p_athlete_id
      and roster.released_at is null
  ) then
    raise exception 'Questo calciatore appartiene già a una squadra.';
  end if;

  select count(*)::integer
  into v_roster_count
  from public.roster_entries roster
  where roster.fantasy_team_id = v_team.id
    and roster.released_at is null;

  if v_roster_count >= v_league.roster_size then
    raise exception 'Rosa completa: prima devi svincolare un calciatore.';
  end if;

  perform public.assert_team_can_add_athlete(v_team.id, p_athlete_id);

  v_price := greatest(
    coalesce((v_league.scoring_rules ->> 'market_min_price')::integer, 1),
    1
  );
  v_required_reserve := public.team_minimum_roster_reserve(v_team.id, 1);

  if v_team.credits_remaining < v_price then
    raise exception 'Crediti insufficienti per completare l''acquisto.';
  end if;

  if v_team.credits_remaining - v_price < v_required_reserve then
    raise exception
      'Devi conservare almeno % crediti per completare i posti liberi della rosa.',
      v_required_reserve;
  end if;

  update public.fantasy_teams
  set credits_remaining = credits_remaining - v_price
  where id = v_team.id;

  insert into public.roster_entries (
    league_id,
    fantasy_team_id,
    athlete_id,
    purchase_price
  )
  values (
    v_team.league_id,
    v_team.id,
    p_athlete_id,
    v_price
  )
  returning * into v_result;

  insert into public.team_transactions (
    league_id,
    fantasy_team_id,
    athlete_id,
    transaction_type,
    credit_delta,
    metadata
  )
  values (
    v_team.league_id,
    v_team.id,
    p_athlete_id,
    'market_purchase',
    -v_price,
    jsonb_build_object(
      'source', 'free_agent_market',
      'roster_entry_id', v_result.id,
      'integrity_version', 4
    )
  );

  return v_result;
end;
$$;

revoke all on function public.sign_free_agent(uuid, uuid) from public;
grant execute on function public.sign_free_agent(uuid, uuid)
to authenticated;

-- Diagnostica incrociata tra mercato, rose, Asta Live e registro crediti.
create or replace function public.get_league_market_integrity_v3(
  p_league_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_base jsonb;
  v_auction_locked_athletes integer;
  v_market_auction_conflicts integer;
  v_sold_auction_ledger_mismatches integer;
  v_additional_issues integer;
  v_base_issue_count integer;
  v_base_ok boolean;
begin
  if auth.uid() is null then
    raise exception 'Devi effettuare l''accesso.';
  end if;

  if not public.is_league_member(p_league_id) then
    raise exception 'Non fai parte di questa lega.';
  end if;

  v_base := public.get_league_market_integrity_v2(p_league_id);

  select count(distinct item.athlete_id)::integer
  into v_auction_locked_athletes
  from public.auction_items item
  join public.auctions auction on auction.id = item.auction_id
  where auction.league_id = p_league_id
    and auction.status in ('live', 'paused')
    and auction.current_item_id = item.id
    and item.status = 'bidding';

  select count(*)::integer
  into v_market_auction_conflicts
  from public.auction_items item
  join public.auctions auction on auction.id = item.auction_id
  where auction.league_id = p_league_id
    and item.status = 'bidding'
    and exists (
      select 1
      from public.roster_entries roster
      where roster.league_id = p_league_id
        and roster.athlete_id = item.athlete_id
        and roster.released_at is null
    );

  select count(*)::integer
  into v_sold_auction_ledger_mismatches
  from public.auction_items item
  join public.auctions auction on auction.id = item.auction_id
  where auction.league_id = p_league_id
    and item.status = 'sold'
    and (
      item.winning_team_id is null
      or item.winning_price is null
      or (
        select count(*)
        from public.team_transactions transaction_row
        where transaction_row.league_id = p_league_id
          and transaction_row.transaction_type = 'auction_purchase'
          and transaction_row.fantasy_team_id = item.winning_team_id
          and transaction_row.athlete_id = item.athlete_id
          and transaction_row.credit_delta = -item.winning_price
          and transaction_row.metadata ->> 'auction_item_id' = item.id::text
      ) <> 1
    );

  v_additional_issues :=
    v_market_auction_conflicts + v_sold_auction_ledger_mismatches;
  v_base_issue_count := coalesce((v_base ->> 'issueCount')::integer, 0);
  v_base_ok := coalesce((v_base ->> 'ok')::boolean, false);

  return v_base || jsonb_build_object(
    'version', 3,
    'ok', v_base_ok and v_additional_issues = 0,
    'issueCount', v_base_issue_count + v_additional_issues,
    'marketAuctionSafetyEnabled', true,
    'auctionLockedAthletes', v_auction_locked_athletes,
    'marketAuctionConflicts', v_market_auction_conflicts,
    'soldAuctionLedgerMismatches', v_sold_auction_ledger_mismatches
  );
end;
$$;

revoke all on function public.get_league_market_integrity_v3(uuid)
from public;
grant execute on function public.get_league_market_integrity_v3(uuid)
to authenticated;

commit;

-- Controllo finale: attesi 14 valori true.
select
  to_regclass('public.auction_items_live_athlete_idx') is not null
    as active_auction_athlete_index_ready,
  to_regprocedure('public.athlete_in_live_auction(uuid,uuid)') is not null
    as live_auction_helper_ready,
  to_regprocedure('public.sign_free_agent(uuid,uuid)') is not null
    as coordinated_free_agent_purchase_ready,
  to_regprocedure('public.get_league_market_integrity_v3(uuid)') is not null
    as cross_channel_diagnostics_ready,
  has_function_privilege(
    'authenticated',
    'public.sign_free_agent(uuid,uuid)',
    'EXECUTE'
  ) as authenticated_market_execute_ready,
  has_function_privilege(
    'authenticated',
    'public.get_league_market_integrity_v3(uuid)',
    'EXECUTE'
  ) as authenticated_diagnostics_execute_ready,
  to_regprocedure('public.get_league_market_integrity_v2(uuid)') is not null
    as trade_diagnostics_dependency_ready,
  to_regprocedure('public.get_league_auction_integrity_v1(uuid)') is not null
    as auction_diagnostics_dependency_ready,
  to_regclass('public.auction_items_one_bidding_per_auction_idx') is not null
    as one_live_item_guard_ready,
  to_regclass('public.auctions_one_open_per_league_idx') is not null
    as one_open_room_guard_ready,
  not exists (
    select 1
    from public.auction_items item
    join public.auctions auction on auction.id = item.auction_id
    join public.roster_entries roster
      on roster.league_id = auction.league_id
     and roster.athlete_id = item.athlete_id
     and roster.released_at is null
    where item.status = 'bidding'
  ) as no_market_auction_conflicts,
  not exists (
    select 1
    from public.auction_items item
    join public.auctions auction on auction.id = item.auction_id
    where item.status = 'sold'
      and (
        item.winning_team_id is null
        or item.winning_price is null
        or (
          select count(*)
          from public.team_transactions transaction_row
          where transaction_row.league_id = auction.league_id
            and transaction_row.transaction_type = 'auction_purchase'
            and transaction_row.fantasy_team_id = item.winning_team_id
            and transaction_row.athlete_id = item.athlete_id
            and transaction_row.credit_delta = -item.winning_price
            and transaction_row.metadata ->> 'auction_item_id' = item.id::text
        ) <> 1
      )
  ) as sold_auction_ledger_consistent,
  not exists (
    select 1
    from public.roster_entries roster
    where roster.released_at is null
    group by roster.league_id, roster.athlete_id
    having count(*) > 1
  ) as no_duplicate_active_players,
  not exists (
    select 1
    from public.auctions auction
    where auction.current_item_id is not null
      and not exists (
        select 1
        from public.auction_items item
        where item.id = auction.current_item_id
          and item.auction_id = auction.id
          and item.status = 'bidding'
      )
  ) as current_auction_items_consistent;
