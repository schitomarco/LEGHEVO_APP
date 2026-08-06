-- LEGHEVO · regia completa dell'asta live
-- Eseguire nel SQL Editor di Supabase dopo 014.

alter table public.auction_items
  add column if not exists paused_seconds_remaining integer;

alter table public.auction_items
  drop constraint if exists auction_items_paused_seconds_check;

alter table public.auction_items
  add constraint auction_items_paused_seconds_check
  check (
    paused_seconds_remaining is null
    or paused_seconds_remaining between 1 and 120
  );

create or replace function public.create_or_get_auction(
  p_league_id uuid,
  p_bid_increment integer default 1,
  p_bid_seconds smallint default 15
)
returns public.auctions
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_auction public.auctions%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Devi effettuare l''accesso.';
  end if;

  if not public.is_league_admin(p_league_id) then
    raise exception 'Solo il Presidente può aprire la stanza asta.';
  end if;

  if p_bid_increment is null
    or p_bid_increment < 1
    or p_bid_increment > 100 then
    raise exception 'Il rilancio minimo deve essere tra 1 e 100 crediti.';
  end if;

  if p_bid_seconds is null
    or p_bid_seconds < 5
    or p_bid_seconds > 120 then
    raise exception 'Il timer deve essere compreso tra 5 e 120 secondi.';
  end if;

  select auction.*
  into v_auction
  from public.auctions auction
  where auction.league_id = p_league_id
    and auction.status <> 'completed'
  order by auction.created_at desc
  limit 1
  for update;

  if found then
    if v_auction.current_item_id is null then
      update public.auctions
      set
        bid_increment = p_bid_increment,
        bid_seconds = p_bid_seconds
      where id = v_auction.id
      returning * into v_auction;
    end if;

    return v_auction;
  end if;

  insert into public.auctions (
    league_id,
    status,
    bid_increment,
    bid_seconds
  )
  values (
    p_league_id,
    'scheduled',
    p_bid_increment,
    p_bid_seconds
  )
  returning * into v_auction;

  return v_auction;
end;
$$;

create or replace function public.configure_auction(
  p_auction_id uuid,
  p_bid_increment integer,
  p_bid_seconds smallint
)
returns public.auctions
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_auction public.auctions%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Devi effettuare l''accesso.';
  end if;

  select auction.*
  into v_auction
  from public.auctions auction
  where auction.id = p_auction_id
  for update;

  if not found then
    raise exception 'Stanza asta non trovata.';
  end if;

  if not public.is_league_admin(v_auction.league_id) then
    raise exception 'Solo il Presidente può configurare l''asta.';
  end if;

  if v_auction.status = 'completed' then
    raise exception 'Questa asta è già terminata.';
  end if;

  if v_auction.current_item_id is not null then
    raise exception 'Puoi cambiare le impostazioni soltanto tra due chiamate.';
  end if;

  if p_bid_increment is null
    or p_bid_increment < 1
    or p_bid_increment > 100 then
    raise exception 'Il rilancio minimo deve essere tra 1 e 100 crediti.';
  end if;

  if p_bid_seconds is null
    or p_bid_seconds < 5
    or p_bid_seconds > 120 then
    raise exception 'Il timer deve essere compreso tra 5 e 120 secondi.';
  end if;

  update public.auctions
  set
    bid_increment = p_bid_increment,
    bid_seconds = p_bid_seconds
  where id = p_auction_id
  returning * into v_auction;

  return v_auction;
end;
$$;

create or replace function public.control_auction(
  p_auction_id uuid,
  p_action text
)
returns public.auctions
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_auction public.auctions%rowtype;
  v_action text := lower(trim(coalesce(p_action, '')));
  v_remaining_seconds integer;
begin
  if auth.uid() is null then
    raise exception 'Devi effettuare l''accesso.';
  end if;

  select auction.*
  into v_auction
  from public.auctions auction
  where auction.id = p_auction_id
  for update;

  if not found then
    raise exception 'Stanza asta non trovata.';
  end if;

  if not public.is_league_admin(v_auction.league_id) then
    raise exception 'Solo il Presidente può comandare l''asta.';
  end if;

  if v_action = 'pause' then
    if v_auction.status not in ('scheduled', 'live') then
      raise exception 'L''asta non può essere messa in pausa adesso.';
    end if;

    if v_auction.current_item_id is not null then
      select greatest(
        1,
        least(
          120,
          ceil(
            extract(
              epoch from coalesce(item.expires_at, now()) - now()
            )
          )::integer
        )
      )
      into v_remaining_seconds
      from public.auction_items item
      where item.id = v_auction.current_item_id
        and item.status = 'bidding';

      update public.auction_items
      set
        paused_seconds_remaining = coalesce(
          v_remaining_seconds,
          v_auction.bid_seconds
        ),
        expires_at = null
      where id = v_auction.current_item_id
        and status = 'bidding';
    end if;

    update public.auctions
    set status = 'paused'
    where id = p_auction_id;

  elsif v_action = 'resume' then
    if v_auction.status <> 'paused' then
      raise exception 'L''asta non è in pausa.';
    end if;

    if v_auction.current_item_id is not null then
      update public.auction_items
      set
        expires_at = now() + make_interval(
          secs => coalesce(paused_seconds_remaining, v_auction.bid_seconds)
        ),
        paused_seconds_remaining = null
      where id = v_auction.current_item_id
        and status = 'bidding';
    end if;

    update public.auctions
    set
      status = 'live',
      starts_at = coalesce(starts_at, now())
    where id = p_auction_id;

  elsif v_action = 'cancel_item' then
    if v_auction.current_item_id is null then
      raise exception 'Non c''è nessun calciatore da annullare.';
    end if;

    update public.auction_items
    set
      status = 'unsold',
      expires_at = now(),
      paused_seconds_remaining = null
    where id = v_auction.current_item_id
      and status = 'bidding';

    if not found then
      raise exception 'Il lotto non può essere annullato.';
    end if;

  elsif v_action = 'complete' then
    if v_auction.status = 'completed' then
      raise exception 'Questa asta è già terminata.';
    end if;

    if v_auction.current_item_id is not null then
      raise exception 'Prima chiudi o annulla il calciatore sul banco.';
    end if;

    update public.auctions
    set
      status = 'completed',
      current_item_id = null,
      ended_at = now()
    where id = p_auction_id;

    update public.leagues
    set
      status = 'active',
      updated_at = now()
    where id = v_auction.league_id
      and status = 'draft';

  else
    raise exception 'Comando asta non riconosciuto.';
  end if;

  select auction.*
  into v_auction
  from public.auctions auction
  where auction.id = p_auction_id;

  return v_auction;
end;
$$;

create or replace function public.nominate_auction_player(
  p_auction_id uuid,
  p_athlete_id uuid,
  p_opening_price integer default 1
)
returns public.auction_items
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_auction public.auctions%rowtype;
  v_item public.auction_items%rowtype;
  v_nominating_team_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Devi effettuare l''accesso.';
  end if;

  if p_opening_price < 1 then
    raise exception 'La base d''asta deve essere almeno 1.';
  end if;

  select auction.*
  into v_auction
  from public.auctions auction
  where auction.id = p_auction_id
  for update;

  if not found then
    raise exception 'Stanza asta non trovata.';
  end if;

  if not public.is_league_admin(v_auction.league_id) then
    raise exception 'Solo il Presidente può nominare un calciatore.';
  end if;

  if v_auction.status = 'paused' then
    raise exception 'L''asta è in pausa.';
  end if;

  if v_auction.status = 'completed' then
    raise exception 'Questa asta è già terminata.';
  end if;

  if exists (
    select 1
    from public.auction_items item
    where item.id = v_auction.current_item_id
      and item.status = 'bidding'
  ) then
    raise exception 'C''è già un calciatore all''asta.';
  end if;

  if not exists (
    select 1
    from public.athletes athlete
    where athlete.id = p_athlete_id
      and athlete.active = true
  ) then
    raise exception 'Calciatore non disponibile.';
  end if;

  if exists (
    select 1
    from public.roster_entries roster
    where roster.league_id = v_auction.league_id
      and roster.athlete_id = p_athlete_id
      and roster.released_at is null
  ) then
    raise exception 'Questo calciatore è già stato acquistato.';
  end if;

  select team.id
  into v_nominating_team_id
  from public.fantasy_teams team
  where team.league_id = v_auction.league_id
    and team.manager_id = auth.uid();

  insert into public.auction_items (
    auction_id,
    athlete_id,
    nominated_by_team_id,
    status,
    opening_price,
    expires_at
  )
  values (
    v_auction.id,
    p_athlete_id,
    v_nominating_team_id,
    'bidding',
    p_opening_price,
    now() + make_interval(secs => v_auction.bid_seconds)
  )
  returning * into v_item;

  update public.auctions
  set
    status = 'live',
    current_item_id = v_item.id,
    starts_at = coalesce(starts_at, now())
  where id = v_auction.id;

  return v_item;
end;
$$;

create or replace function public.place_bid(
  p_auction_item_id uuid,
  p_amount integer
)
returns public.bids
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_item record;
  v_team public.fantasy_teams%rowtype;
  v_current_bid integer;
  v_minimum_bid integer;
  v_roster_count integer;
  v_reserved_credits integer;
  v_maximum_bid integer;
  v_bid public.bids%rowtype;
begin
  if v_user_id is null then
    raise exception 'Devi effettuare l''accesso.';
  end if;

  select
    item.auction_id,
    item.status as item_status,
    item.opening_price,
    item.expires_at,
    auction.league_id,
    auction.status as auction_status,
    auction.current_item_id,
    auction.bid_increment,
    auction.bid_seconds,
    league.roster_size
  into v_item
  from public.auction_items item
  join public.auctions auction on auction.id = item.auction_id
  join public.leagues league on league.id = auction.league_id
  where item.id = p_auction_item_id
  for update of item;

  if not found then
    raise exception 'Calciatore non trovato nell''asta.';
  end if;

  if v_item.auction_status <> 'live'
    or v_item.item_status <> 'bidding'
    or v_item.current_item_id is distinct from p_auction_item_id then
    raise exception 'Questo calciatore non è disponibile per i rilanci.';
  end if;

  if v_item.expires_at is null or v_item.expires_at <= now() then
    raise exception 'Tempo scaduto. Il VAR conferma.';
  end if;

  select team.*
  into v_team
  from public.fantasy_teams team
  where team.league_id = v_item.league_id
    and team.manager_id = v_user_id
  for update;

  if not found then
    raise exception 'Non hai una squadra in questa lega.';
  end if;

  select count(*)::integer
  into v_roster_count
  from public.roster_entries roster
  where roster.fantasy_team_id = v_team.id
    and roster.released_at is null;

  if v_roster_count >= v_item.roster_size then
    raise exception 'La tua rosa è già completa.';
  end if;

  select max(bid.amount)
  into v_current_bid
  from public.bids bid
  where bid.auction_item_id = p_auction_item_id;

  v_minimum_bid := case
    when v_current_bid is null then v_item.opening_price
    else v_current_bid + v_item.bid_increment
  end;

  if p_amount < v_minimum_bid then
    raise exception 'Offerta minima: % crediti.', v_minimum_bid;
  end if;

  v_reserved_credits :=
    greatest(v_item.roster_size - v_roster_count - 1, 0);
  v_maximum_bid := v_team.credits_remaining - v_reserved_credits;

  if p_amount > v_maximum_bid then
    raise exception
      'Offerta massima: % crediti. Devi conservare un credito per ogni posto libero.',
      greatest(v_maximum_bid, 0);
  end if;

  insert into public.bids (auction_item_id, fantasy_team_id, amount)
  values (p_auction_item_id, v_team.id, p_amount)
  returning * into v_bid;

  if v_item.expires_at < now() + interval '5 seconds' then
    update public.auction_items
    set expires_at = now() + make_interval(secs => v_item.bid_seconds)
    where id = p_auction_item_id;
  end if;

  return v_bid;
end;
$$;

create or replace function public.finalize_auction_item(
  p_auction_item_id uuid
)
returns public.auction_items
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_item record;
  v_winning_bid public.bids%rowtype;
  v_team public.fantasy_teams%rowtype;
  v_roster_count integer;
  v_reserved_credits integer;
  v_result public.auction_items%rowtype;
begin
  select
    item.auction_id,
    item.athlete_id,
    item.status as item_status,
    item.expires_at,
    auction.league_id,
    auction.status as auction_status,
    league.roster_size
  into v_item
  from public.auction_items item
  join public.auctions auction on auction.id = item.auction_id
  join public.leagues league on league.id = auction.league_id
  where item.id = p_auction_item_id
  for update of item;

  if not found then
    raise exception 'Elemento d''asta non trovato.';
  end if;

  if not public.is_league_admin(v_item.league_id) then
    raise exception 'Solo un amministratore può chiudere il lotto.';
  end if;

  if v_item.auction_status <> 'live'
    or v_item.item_status <> 'bidding'
    or v_item.expires_at is null
    or v_item.expires_at > now() then
    raise exception 'Il lotto non può ancora essere chiuso.';
  end if;

  select bid.*
  into v_winning_bid
  from public.bids bid
  where bid.auction_item_id = p_auction_item_id
  order by bid.amount desc, bid.created_at asc
  limit 1;

  if not found then
    update public.auction_items
    set
      status = 'unsold',
      paused_seconds_remaining = null
    where id = p_auction_item_id
    returning * into v_result;

    return v_result;
  end if;

  select team.*
  into v_team
  from public.fantasy_teams team
  where team.id = v_winning_bid.fantasy_team_id
  for update;

  select count(*)::integer
  into v_roster_count
  from public.roster_entries roster
  where roster.fantasy_team_id = v_team.id
    and roster.released_at is null;

  if v_roster_count >= v_item.roster_size then
    raise exception 'La rosa della squadra vincente è già completa.';
  end if;

  v_reserved_credits :=
    greatest(v_item.roster_size - v_roster_count - 1, 0);

  if v_team.credits_remaining - v_winning_bid.amount < v_reserved_credits then
    raise exception
      'La squadra vincente non può coprire i posti ancora liberi.';
  end if;

  update public.fantasy_teams
  set credits_remaining = credits_remaining - v_winning_bid.amount
  where id = v_team.id;

  insert into public.roster_entries (
    league_id,
    fantasy_team_id,
    athlete_id,
    purchase_price
  )
  values (
    v_item.league_id,
    v_team.id,
    v_item.athlete_id,
    v_winning_bid.amount
  );

  insert into public.team_transactions (
    league_id,
    fantasy_team_id,
    athlete_id,
    transaction_type,
    credit_delta,
    metadata
  )
  values (
    v_item.league_id,
    v_team.id,
    v_item.athlete_id,
    'auction_purchase',
    -v_winning_bid.amount,
    jsonb_build_object('auction_item_id', p_auction_item_id)
  );

  update public.auction_items
  set
    status = 'sold',
    winning_team_id = v_team.id,
    winning_price = v_winning_bid.amount,
    paused_seconds_remaining = null
  where id = p_auction_item_id
  returning * into v_result;

  return v_result;
end;
$$;

revoke all on function public.configure_auction(uuid, integer, smallint)
from public;

revoke all on function public.control_auction(uuid, text)
from public;

grant execute on function public.configure_auction(uuid, integer, smallint)
to authenticated;

grant execute on function public.control_auction(uuid, text)
to authenticated;

select
  exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'auction_items'
      and column_name = 'paused_seconds_remaining'
  ) as auction_pause_ready,
  to_regprocedure(
    'public.create_or_get_auction(uuid,integer,smallint)'
  ) is not null as auction_room_ready,
  to_regprocedure(
    'public.configure_auction(uuid,integer,smallint)'
  ) is not null as auction_settings_ready,
  to_regprocedure(
    'public.control_auction(uuid,text)'
  ) is not null as auction_controls_ready,
  to_regprocedure(
    'public.place_bid(uuid,integer)'
  ) is not null as protected_bids_ready,
  to_regprocedure(
    'public.finalize_auction_item(uuid)'
  ) is not null as protected_assignment_ready;
