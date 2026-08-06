-- LEGHEVO · sicurezza atomica dell'Asta Live
-- Eseguire nel SQL Editor di Supabase dopo 067.

begin;

alter table public.auction_items
  add column if not exists bid_revision bigint not null default 0,
  add column if not exists last_bid_at timestamptz,
  add column if not exists finalized_at timestamptz;

alter table public.auction_items
  drop constraint if exists auction_items_bid_revision_nonnegative;

alter table public.auction_items
  add constraint auction_items_bid_revision_nonnegative
  check (bid_revision >= 0);

-- Allinea i nuovi metadati con lo storico esistente.
update public.auction_items item
set
  bid_revision = bid_state.bid_count,
  last_bid_at = bid_state.last_bid_at
from (
  select
    bid.auction_item_id,
    count(*)::bigint as bid_count,
    max(bid.created_at) as last_bid_at
  from public.bids bid
  group by bid.auction_item_id
) bid_state
where bid_state.auction_item_id = item.id
  and (
    item.bid_revision is distinct from bid_state.bid_count
    or item.last_bid_at is distinct from bid_state.last_bid_at
  );

update public.auction_items
set finalized_at = coalesce(finalized_at, created_at)
where status in ('sold', 'unsold')
  and finalized_at is null;

-- Rimuove riferimenti correnti chiaramente obsoleti.
update public.auctions auction
set current_item_id = null
where auction.current_item_id is not null
  and not exists (
    select 1
    from public.auction_items item
    where item.id = auction.current_item_id
      and item.auction_id = auction.id
      and item.status = 'bidding'
  );

-- Conserva un solo lotto attivo per stanza, privilegiando quello già corrente.
with ranked as (
  select
    item.id,
    row_number() over (
      partition by item.auction_id
      order by
        case when auction.current_item_id = item.id then 0 else 1 end,
        item.created_at desc,
        item.id
    ) as position
  from public.auction_items item
  join public.auctions auction on auction.id = item.auction_id
  where item.status = 'bidding'
)
update public.auction_items item
set
  status = 'unsold',
  expires_at = coalesce(item.expires_at, now()),
  paused_seconds_remaining = null,
  finalized_at = coalesce(item.finalized_at, now())
from ranked
where ranked.id = item.id
  and ranked.position > 1;

-- Riallinea current_item_id al solo lotto bidding rimasto.
update public.auctions auction
set current_item_id = (
  select item.id
  from public.auction_items item
  where item.auction_id = auction.id
    and item.status = 'bidding'
  order by item.created_at desc, item.id
  limit 1
)
where auction.status <> 'completed'
  and auction.current_item_id is distinct from (
    select item.id
    from public.auction_items item
    where item.auction_id = auction.id
      and item.status = 'bidding'
    order by item.created_at desc, item.id
    limit 1
  );

-- Chiude eventuali stanze duplicate soltanto se non hanno un lotto attivo.
with ranked as (
  select
    auction.id,
    row_number() over (
      partition by auction.league_id
      order by
        case when auction.current_item_id is not null then 0 else 1 end,
        auction.created_at desc,
        auction.id
    ) as position
  from public.auctions auction
  where auction.status <> 'completed'
)
update public.auctions auction
set
  status = 'completed',
  current_item_id = null,
  ended_at = coalesce(auction.ended_at, now())
from ranked
where ranked.id = auction.id
  and ranked.position > 1
  and auction.current_item_id is null;

create unique index if not exists auctions_one_open_per_league_idx
  on public.auctions (league_id)
  where status <> 'completed';

create unique index if not exists auction_items_one_bidding_per_auction_idx
  on public.auction_items (auction_id)
  where status = 'bidding';

create index if not exists bids_item_amount_created_idx
  on public.bids (auction_item_id, amount desc, created_at asc, id asc);

create index if not exists auction_items_athlete_status_idx
  on public.auction_items (athlete_id, status, created_at desc);

-- Crediti già promessi in scambi pendenti. Rimane compatibile anche senza 067.
create or replace function public.team_pending_trade_credits(
  p_fantasy_team_id uuid
)
returns integer
language plpgsql
security definer
stable
set search_path = ''
as $$
declare
  v_reserved integer := 0;
begin
  if to_regclass('public.trade_credit_reservations') is null then
    return 0;
  end if;

  execute $query$
    select coalesce(sum(reservation.amount), 0)::integer
    from public.trade_credit_reservations reservation
    where reservation.fantasy_team_id = $1
  $query$
  into v_reserved
  using p_fantasy_team_id;

  return coalesce(v_reserved, 0);
end;
$$;

revoke all on function public.team_pending_trade_credits(uuid) from public;
grant execute on function public.team_pending_trade_credits(uuid)
to authenticated;

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

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('auction-room:' || p_league_id::text, 0)
  );

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

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('auction:' || p_auction_id::text, 0)
  );

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

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('auction:' || p_auction_id::text, 0)
  );

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
          ceil(extract(epoch from coalesce(item.expires_at, now()) - now()))::integer
        )
      )
      into v_remaining_seconds
      from public.auction_items item
      where item.id = v_auction.current_item_id
        and item.status = 'bidding'
      for update;

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
      expires_at = coalesce(expires_at, now()),
      paused_seconds_remaining = null,
      finalized_at = now()
    where id = v_auction.current_item_id
      and status = 'bidding';

    if not found then
      raise exception 'Il lotto non può essere annullato.';
    end if;

  elsif v_action = 'complete' then
    if v_auction.status = 'completed' then
      return v_auction;
    end if;

    if v_auction.current_item_id is not null then
      raise exception 'Prima chiudi o annulla il calciatore sul banco.';
    end if;

    update public.auctions
    set
      status = 'completed',
      current_item_id = null,
      ended_at = coalesce(ended_at, now())
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

  if p_opening_price is null or p_opening_price < 1 then
    raise exception 'La base d''asta deve essere almeno 1.';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('auction:' || p_auction_id::text, 0)
  );

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

  if v_auction.current_item_id is not null
    or exists (
      select 1
      from public.auction_items item
      where item.auction_id = v_auction.id
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

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      v_auction.league_id::text || ':' || p_athlete_id::text,
      0
    )
  );

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
    and team.manager_id = auth.uid()
  limit 1;

  insert into public.auction_items (
    auction_id,
    athlete_id,
    nominated_by_team_id,
    status,
    opening_price,
    expires_at,
    bid_revision
  )
  values (
    v_auction.id,
    p_athlete_id,
    v_nominating_team_id,
    'bidding',
    p_opening_price,
    now() + make_interval(secs => v_auction.bid_seconds),
    0
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
  v_auction_id uuid;
  v_item record;
  v_team public.fantasy_teams%rowtype;
  v_current_bid public.bids%rowtype;
  v_has_current_bid boolean;
  v_minimum_bid integer;
  v_roster_count integer;
  v_required_roster_reserve integer;
  v_trade_reserved integer;
  v_maximum_bid integer;
  v_bid public.bids%rowtype;
begin
  if v_user_id is null then
    raise exception 'Devi effettuare l''accesso.';
  end if;

  if p_amount is null or p_amount < 1 then
    raise exception 'L''offerta deve essere almeno 1 credito.';
  end if;

  select item.auction_id
  into v_auction_id
  from public.auction_items item
  where item.id = p_auction_item_id;

  if not found then
    raise exception 'Calciatore non trovato nell''asta.';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('auction:' || v_auction_id::text, 0)
  );

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
  for update of item, auction;

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

  select bid.*
  into v_current_bid
  from public.bids bid
  where bid.auction_item_id = p_auction_item_id
  order by bid.amount desc, bid.created_at asc, bid.id asc
  limit 1;

  v_has_current_bid := found;
  v_minimum_bid := case
    when not v_has_current_bid then v_item.opening_price
    else v_current_bid.amount + v_item.bid_increment
  end;

  if p_amount < v_minimum_bid then
    raise exception 'Offerta minima: % crediti.', v_minimum_bid;
  end if;

  v_required_roster_reserve := public.team_minimum_roster_reserve(
    v_team.id,
    1
  );
  v_trade_reserved := public.team_pending_trade_credits(v_team.id);
  v_maximum_bid :=
    v_team.credits_remaining
    - v_required_roster_reserve
    - v_trade_reserved;

  if p_amount > v_maximum_bid then
    raise exception
      'Offerta massima: % crediti. Devi coprire rosa e trattative già aperte.',
      greatest(v_maximum_bid, 0);
  end if;

  insert into public.bids (auction_item_id, fantasy_team_id, amount)
  values (p_auction_item_id, v_team.id, p_amount)
  returning * into v_bid;

  update public.auction_items
  set
    bid_revision = bid_revision + 1,
    last_bid_at = now(),
    expires_at = case
      when expires_at < now() + interval '5 seconds'
      then now() + make_interval(secs => v_item.bid_seconds)
      else expires_at
    end
  where id = p_auction_item_id;

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
  v_auction_id uuid;
  v_item record;
  v_winning_bid public.bids%rowtype;
  v_has_winner boolean;
  v_team public.fantasy_teams%rowtype;
  v_roster_count integer;
  v_required_roster_reserve integer;
  v_trade_reserved integer;
  v_result public.auction_items%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Devi effettuare l''accesso.';
  end if;

  select item.auction_id
  into v_auction_id
  from public.auction_items item
  where item.id = p_auction_item_id;

  if not found then
    raise exception 'Elemento d''asta non trovato.';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('auction:' || v_auction_id::text, 0)
  );

  select
    item.*,
    auction.league_id,
    auction.status as auction_status,
    auction.current_item_id,
    league.roster_size
  into v_item
  from public.auction_items item
  join public.auctions auction on auction.id = item.auction_id
  join public.leagues league on league.id = auction.league_id
  where item.id = p_auction_item_id
  for update of item, auction;

  if not found then
    raise exception 'Elemento d''asta non trovato.';
  end if;

  if not public.is_league_admin(v_item.league_id) then
    raise exception 'Solo un amministratore può chiudere il lotto.';
  end if;

  if v_item.status in ('sold', 'unsold') then
    select item.*
    into v_result
    from public.auction_items item
    where item.id = p_auction_item_id;
    return v_result;
  end if;

  if v_item.auction_status <> 'live'
    or v_item.status <> 'bidding'
    or v_item.current_item_id is distinct from p_auction_item_id
    or v_item.expires_at is null
    or v_item.expires_at > now() then
    raise exception 'Il lotto non può ancora essere chiuso.';
  end if;

  select bid.*
  into v_winning_bid
  from public.bids bid
  where bid.auction_item_id = p_auction_item_id
  order by bid.amount desc, bid.created_at asc, bid.id asc
  limit 1;

  v_has_winner := found;

  if not v_has_winner then
    update public.auction_items
    set
      status = 'unsold',
      paused_seconds_remaining = null,
      finalized_at = now()
    where id = p_auction_item_id
    returning * into v_result;
    return v_result;
  end if;

  select team.*
  into v_team
  from public.fantasy_teams team
  where team.id = v_winning_bid.fantasy_team_id
    and team.league_id = v_item.league_id
  for update;

  if not found then
    raise exception 'La squadra vincente non è più disponibile.';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      v_item.league_id::text || ':' || v_item.athlete_id::text,
      0
    )
  );

  if exists (
    select 1
    from public.roster_entries roster
    where roster.league_id = v_item.league_id
      and roster.athlete_id = v_item.athlete_id
      and roster.released_at is null
  ) then
    raise exception 'Il calciatore è già presente in una rosa.';
  end if;

  select count(*)::integer
  into v_roster_count
  from public.roster_entries roster
  where roster.fantasy_team_id = v_team.id
    and roster.released_at is null;

  if v_roster_count >= v_item.roster_size then
    raise exception 'La rosa della squadra vincente è già completa.';
  end if;

  perform public.assert_team_can_add_athlete(v_team.id, v_item.athlete_id);

  v_required_roster_reserve := public.team_minimum_roster_reserve(
    v_team.id,
    1
  );
  v_trade_reserved := public.team_pending_trade_credits(v_team.id);

  if v_team.credits_remaining - v_winning_bid.amount
      < v_required_roster_reserve + v_trade_reserved then
    raise exception
      'La squadra vincente non può coprire rosa e trattative già aperte.';
  end if;

  update public.fantasy_teams
  set credits_remaining = credits_remaining - v_winning_bid.amount
  where id = v_team.id
    and credits_remaining >= v_winning_bid.amount
  returning * into v_team;

  if not found then
    raise exception 'Crediti insufficienti per completare l''assegnazione.';
  end if;

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
    jsonb_build_object(
      'auction_item_id', p_auction_item_id,
      'bid_id', v_winning_bid.id,
      'bid_revision', v_item.bid_revision,
      'integrity_version', 3
    )
  );

  update public.auction_items
  set
    status = 'sold',
    winning_team_id = v_team.id,
    winning_price = v_winning_bid.amount,
    paused_seconds_remaining = null,
    finalized_at = now()
  where id = p_auction_item_id
  returning * into v_result;

  return v_result;
end;
$$;

create or replace function public.get_league_auction_integrity_v1(
  p_league_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_open_auctions integer;
  v_bidding_items integer;
  v_orphan_current_items integer;
  v_orphan_bidding_items integer;
  v_invalid_winners integer;
  v_invalid_bid_sequences integer;
  v_issue_count integer;
  v_current jsonb;
begin
  if auth.uid() is null then
    raise exception 'Devi effettuare l''accesso.';
  end if;

  if not public.is_league_member(p_league_id) then
    raise exception 'Non fai parte di questa lega.';
  end if;

  select count(*)::integer
  into v_open_auctions
  from public.auctions auction
  where auction.league_id = p_league_id
    and auction.status <> 'completed';

  select count(*)::integer
  into v_bidding_items
  from public.auction_items item
  join public.auctions auction on auction.id = item.auction_id
  where auction.league_id = p_league_id
    and item.status = 'bidding';

  select count(*)::integer
  into v_orphan_current_items
  from public.auctions auction
  where auction.league_id = p_league_id
    and auction.current_item_id is not null
    and not exists (
      select 1
      from public.auction_items item
      where item.id = auction.current_item_id
        and item.auction_id = auction.id
        and item.status = 'bidding'
    );

  select count(*)::integer
  into v_orphan_bidding_items
  from public.auction_items item
  join public.auctions auction on auction.id = item.auction_id
  where auction.league_id = p_league_id
    and item.status = 'bidding'
    and auction.current_item_id is distinct from item.id;

  select count(*)::integer
  into v_invalid_winners
  from public.auction_items item
  join public.auctions auction on auction.id = item.auction_id
  where auction.league_id = p_league_id
    and item.status = 'sold'
    and (
      item.winning_team_id is null
      or item.winning_price is null
      or item.finalized_at is null
      or not exists (
        select 1
        from public.roster_entries roster
        where roster.league_id = p_league_id
          and roster.fantasy_team_id = item.winning_team_id
          and roster.athlete_id = item.athlete_id
      )
    );

  select count(*)::integer
  into v_invalid_bid_sequences
  from (
    select item.id
    from public.auction_items item
    join public.auctions auction on auction.id = item.auction_id
    left join public.bids bid on bid.auction_item_id = item.id
    where auction.league_id = p_league_id
    group by item.id, item.opening_price, item.bid_revision
    having
      count(bid.id) <> count(distinct bid.amount)
      or coalesce(min(bid.amount), item.opening_price) < item.opening_price
      or item.bid_revision <> count(bid.id)
  ) invalid_item;

  select jsonb_build_object(
    'auctionId', auction.id,
    'status', auction.status,
    'currentItemId', auction.current_item_id,
    'bidIncrement', auction.bid_increment,
    'bidSeconds', auction.bid_seconds,
    'currentBidRevision', coalesce(item.bid_revision, 0),
    'lastBidAt', item.last_bid_at,
    'expiresAt', item.expires_at
  )
  into v_current
  from public.auctions auction
  left join public.auction_items item on item.id = auction.current_item_id
  where auction.league_id = p_league_id
    and auction.status <> 'completed'
  order by auction.created_at desc
  limit 1;

  v_issue_count :=
    greatest(v_open_auctions - 1, 0)
    + greatest(v_bidding_items - 1, 0)
    + v_orphan_current_items
    + v_orphan_bidding_items
    + v_invalid_winners
    + v_invalid_bid_sequences;

  return jsonb_build_object(
    'version', 1,
    'safetyEnabled', true,
    'leagueId', p_league_id,
    'checkedAt', now(),
    'ok', v_issue_count = 0,
    'issueCount', v_issue_count,
    'openAuctions', v_open_auctions,
    'biddingItems', v_bidding_items,
    'orphanCurrentItems', v_orphan_current_items,
    'orphanBiddingItems', v_orphan_bidding_items,
    'invalidWinners', v_invalid_winners,
    'invalidBidSequences', v_invalid_bid_sequences,
    'current', v_current
  );
end;
$$;

revoke all on function public.create_or_get_auction(uuid, integer, smallint)
from public;
revoke all on function public.configure_auction(uuid, integer, smallint)
from public;
revoke all on function public.control_auction(uuid, text) from public;
revoke all on function public.nominate_auction_player(uuid, uuid, integer)
from public;
revoke all on function public.place_bid(uuid, integer) from public;
revoke all on function public.finalize_auction_item(uuid) from public;
revoke all on function public.get_league_auction_integrity_v1(uuid)
from public;

grant execute on function public.create_or_get_auction(uuid, integer, smallint)
to authenticated;
grant execute on function public.configure_auction(uuid, integer, smallint)
to authenticated;
grant execute on function public.control_auction(uuid, text)
to authenticated;
grant execute on function public.nominate_auction_player(uuid, uuid, integer)
to authenticated;
grant execute on function public.place_bid(uuid, integer) to authenticated;
grant execute on function public.finalize_auction_item(uuid)
to authenticated;
grant execute on function public.get_league_auction_integrity_v1(uuid)
to authenticated;

commit;

-- Controllo finale: attesi 18 valori true.
select
  exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'auction_items'
      and column_name = 'bid_revision'
  ) as bid_revision_ready,
  exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'auction_items'
      and column_name = 'last_bid_at'
  ) as last_bid_at_ready,
  exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'auction_items'
      and column_name = 'finalized_at'
  ) as finalized_at_ready,
  to_regclass('public.auctions_one_open_per_league_idx') is not null
    as one_open_auction_index_ready,
  to_regclass('public.auction_items_one_bidding_per_auction_idx') is not null
    as one_bidding_item_index_ready,
  to_regclass('public.bids_item_amount_created_idx') is not null
    as bid_order_index_ready,
  to_regprocedure('public.team_pending_trade_credits(uuid)') is not null
    as trade_reserve_helper_ready,
  to_regprocedure(
    'public.create_or_get_auction(uuid,integer,smallint)'
  ) is not null as auction_room_v3_ready,
  to_regprocedure(
    'public.configure_auction(uuid,integer,smallint)'
  ) is not null as atomic_configuration_ready,
  to_regprocedure('public.control_auction(uuid,text)') is not null
    as atomic_controls_ready,
  to_regprocedure(
    'public.nominate_auction_player(uuid,uuid,integer)'
  ) is not null as atomic_nomination_ready,
  to_regprocedure('public.place_bid(uuid,integer)') is not null
    as atomic_bid_ready,
  to_regprocedure('public.finalize_auction_item(uuid)') is not null
    as idempotent_assignment_ready,
  to_regprocedure('public.get_league_auction_integrity_v1(uuid)') is not null
    as auction_diagnostics_ready,
  not exists (
    select 1
    from public.auctions auction
    where auction.status <> 'completed'
    group by auction.league_id
    having count(*) > 1
  ) as no_duplicate_open_auctions,
  not exists (
    select 1
    from public.auction_items item
    where item.status = 'bidding'
    group by item.auction_id
    having count(*) > 1
  ) as no_duplicate_bidding_items,
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
  ) as current_items_consistent,
  not exists (
    select 1
    from public.auction_items item
    where item.status = 'sold'
      and (item.winning_team_id is null or item.winning_price is null)
  ) as sold_items_have_winner;
