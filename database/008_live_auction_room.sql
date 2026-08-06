-- LEGHEVO · stanza asta live collegata alla lega
-- Eseguire nel SQL Editor di Supabase dopo 007.

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
    raise exception 'Solo il presidente può aprire la stanza asta.';
  end if;

  if p_bid_increment < 1 then
    raise exception 'Il rilancio minimo deve essere almeno 1.';
  end if;

  if p_bid_seconds < 5 or p_bid_seconds > 120 then
    raise exception 'Il timer deve essere compreso tra 5 e 120 secondi.';
  end if;

  select auction.*
  into v_auction
  from public.auctions auction
  where auction.league_id = p_league_id
    and auction.status <> 'completed'
  order by auction.created_at desc
  limit 1;

  if found then
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
    raise exception 'Solo il presidente può nominare un calciatore.';
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

create or replace function public.clear_completed_auction_item()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.status in ('sold', 'unsold')
    and old.status is distinct from new.status then
    update public.auctions
    set current_item_id = null
    where id = new.auction_id
      and current_item_id = new.id;
  end if;

  return new;
end;
$$;

drop trigger if exists auction_item_clear_current
on public.auction_items;

create trigger auction_item_clear_current
after update of status on public.auction_items
for each row execute function public.clear_completed_auction_item();

revoke all on function public.create_or_get_auction(
  uuid,
  integer,
  smallint
) from public;

revoke all on function public.nominate_auction_player(
  uuid,
  uuid,
  integer
) from public;

grant execute on function public.create_or_get_auction(
  uuid,
  integer,
  smallint
) to authenticated;

grant execute on function public.nominate_auction_player(
  uuid,
  uuid,
  integer
) to authenticated;

do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'auctions'
  ) then
    alter publication supabase_realtime add table public.auctions;
  end if;

  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'auction_items'
  ) then
    alter publication supabase_realtime add table public.auction_items;
  end if;
end;
$$;

select
  to_regprocedure(
    'public.create_or_get_auction(uuid,integer,smallint)'
  ) is not null as auction_room_ready,
  to_regprocedure(
    'public.nominate_auction_player(uuid,uuid,integer)'
  ) is not null as nomination_ready;
