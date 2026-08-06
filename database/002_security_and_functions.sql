-- LEGHEVO · sicurezza e funzioni applicative
-- Eseguire dopo 001_initial_schema.sql in un progetto Supabase.

create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger profiles_set_updated_at
before update on public.profiles
for each row execute function public.set_updated_at();

create trigger leagues_set_updated_at
before update on public.leagues
for each row execute function public.set_updated_at();

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, display_name)
  values (
    new.id,
    coalesce(
      nullif(trim(new.raw_user_meta_data ->> 'display_name'), ''),
      split_part(coalesce(new.email, 'mister'), '@', 1)
    )
  )
  on conflict (id) do nothing;

  return new;
end;
$$;

create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_user();

create or replace function public.is_league_member(p_league_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.league_members member
    where member.league_id = p_league_id
      and member.user_id = auth.uid()
  );
$$;

create or replace function public.is_league_admin(p_league_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.leagues league
    where league.id = p_league_id
      and league.owner_id = auth.uid()
  ) or exists (
    select 1
    from public.league_members member
    where member.league_id = p_league_id
      and member.user_id = auth.uid()
      and member.role = 'admin'
  );
$$;

create or replace function public.can_manage_lineup(p_lineup_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.lineups lineup
    join public.fantasy_teams team on team.id = lineup.fantasy_team_id
    join public.matchdays matchday on matchday.id = lineup.matchday_id
    where lineup.id = p_lineup_id
      and matchday.locks_at > now()
      and (
        team.manager_id = auth.uid()
        or public.is_league_admin(team.league_id)
      )
  );
$$;

create or replace function public.create_league(
  p_name text,
  p_mode public.league_mode,
  p_team_limit smallint default 8,
  p_starting_credits integer default 500,
  p_roster_size smallint default 25
)
returns public.leagues
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_league public.leagues%rowtype;
begin
  if v_user_id is null then
    raise exception 'Devi effettuare l''accesso.';
  end if;

  if nullif(trim(p_name), '') is null then
    raise exception 'Il nome della lega è obbligatorio.';
  end if;

  insert into public.leagues (
    owner_id,
    name,
    invite_code,
    mode,
    team_limit,
    starting_credits,
    roster_size
  )
  values (
    v_user_id,
    trim(p_name),
    upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 10)),
    p_mode,
    p_team_limit,
    p_starting_credits,
    p_roster_size
  )
  returning * into v_league;

  insert into public.league_members (league_id, user_id, role)
  values (v_league.id, v_user_id, 'admin');

  return v_league;
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
    auction.bid_seconds
  into v_item
  from public.auction_items item
  join public.auctions auction on auction.id = item.auction_id
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

  if p_amount > v_team.credits_remaining then
    raise exception 'Crediti insufficienti. Il bilancio piange.';
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
  v_result public.auction_items%rowtype;
begin
  select
    item.auction_id,
    item.athlete_id,
    item.status as item_status,
    item.expires_at,
    auction.league_id,
    auction.status as auction_status
  into v_item
  from public.auction_items item
  join public.auctions auction on auction.id = item.auction_id
  where item.id = p_auction_item_id
  for update of item;

  if not found then
    raise exception 'Elemento d''asta non trovato.';
  end if;

  if not public.is_league_admin(v_item.league_id) then
    raise exception 'Solo un amministratore può chiudere il lotto.';
  end if;

  if v_item.item_status <> 'bidding' or v_item.expires_at > now() then
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
    set status = 'unsold'
    where id = p_auction_item_id
    returning * into v_result;

    return v_result;
  end if;

  select team.*
  into v_team
  from public.fantasy_teams team
  where team.id = v_winning_bid.fantasy_team_id
  for update;

  if v_team.credits_remaining < v_winning_bid.amount then
    raise exception 'La squadra vincente non ha crediti sufficienti.';
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
    winning_price = v_winning_bid.amount
  where id = p_auction_item_id
  returning * into v_result;

  return v_result;
end;
$$;

alter table public.profiles enable row level security;
alter table public.leagues enable row level security;
alter table public.league_members enable row level security;
alter table public.fantasy_teams enable row level security;
alter table public.athletes enable row level security;
alter table public.athlete_roles enable row level security;
alter table public.roster_entries enable row level security;
alter table public.auctions enable row level security;
alter table public.auction_items enable row level security;
alter table public.bids enable row level security;
alter table public.matchdays enable row level security;
alter table public.lineups enable row level security;
alter table public.lineup_entries enable row level security;
alter table public.fantasy_fixtures enable row level security;
alter table public.player_match_scores enable row level security;
alter table public.team_transactions enable row level security;

create policy profiles_read_authenticated
on public.profiles for select to authenticated
using (true);

create policy profiles_update_own
on public.profiles for update to authenticated
using (id = auth.uid())
with check (id = auth.uid());

create policy leagues_read_members
on public.leagues for select to authenticated
using (owner_id = auth.uid() or public.is_league_member(id));

create policy leagues_create_own
on public.leagues for insert to authenticated
with check (owner_id = auth.uid());

create policy leagues_update_admin
on public.leagues for update to authenticated
using (public.is_league_admin(id))
with check (public.is_league_admin(id));

create policy leagues_delete_owner
on public.leagues for delete to authenticated
using (owner_id = auth.uid());

create policy members_read_league
on public.league_members for select to authenticated
using (public.is_league_member(league_id) or public.is_league_admin(league_id));

create policy members_add_by_admin
on public.league_members for insert to authenticated
with check (public.is_league_admin(league_id));

create policy members_update_by_admin
on public.league_members for update to authenticated
using (public.is_league_admin(league_id))
with check (public.is_league_admin(league_id));

create policy members_remove_self_or_admin
on public.league_members for delete to authenticated
using (user_id = auth.uid() or public.is_league_admin(league_id));

create policy teams_read_members
on public.fantasy_teams for select to authenticated
using (public.is_league_member(league_id));

create policy teams_create_member
on public.fantasy_teams for insert to authenticated
with check (
  public.is_league_member(league_id)
  and (manager_id = auth.uid() or public.is_league_admin(league_id))
);

create policy teams_update_manager_or_admin
on public.fantasy_teams for update to authenticated
using (manager_id = auth.uid() or public.is_league_admin(league_id))
with check (manager_id = auth.uid() or public.is_league_admin(league_id));

create policy teams_delete_admin
on public.fantasy_teams for delete to authenticated
using (public.is_league_admin(league_id));

create policy athletes_read_authenticated
on public.athletes for select to authenticated
using (true);

create policy athlete_roles_read_authenticated
on public.athlete_roles for select to authenticated
using (true);

create policy roster_read_members
on public.roster_entries for select to authenticated
using (public.is_league_member(league_id));

create policy auctions_read_members
on public.auctions for select to authenticated
using (public.is_league_member(league_id));

create policy auctions_manage_admin
on public.auctions for all to authenticated
using (public.is_league_admin(league_id))
with check (public.is_league_admin(league_id));

create policy auction_items_read_members
on public.auction_items for select to authenticated
using (
  exists (
    select 1
    from public.auctions auction
    where auction.id = auction_id
      and public.is_league_member(auction.league_id)
  )
);

create policy auction_items_manage_admin
on public.auction_items for all to authenticated
using (
  exists (
    select 1
    from public.auctions auction
    where auction.id = auction_id
      and public.is_league_admin(auction.league_id)
  )
)
with check (
  exists (
    select 1
    from public.auctions auction
    where auction.id = auction_id
      and public.is_league_admin(auction.league_id)
  )
);

create policy bids_read_members
on public.bids for select to authenticated
using (
  exists (
    select 1
    from public.auction_items item
    join public.auctions auction on auction.id = item.auction_id
    where item.id = auction_item_id
      and public.is_league_member(auction.league_id)
  )
);

create policy matchdays_read_authenticated
on public.matchdays for select to authenticated
using (true);

create policy lineups_read_members
on public.lineups for select to authenticated
using (
  exists (
    select 1
    from public.fantasy_teams team
    where team.id = fantasy_team_id
      and public.is_league_member(team.league_id)
  )
);

create policy lineups_create_manager
on public.lineups for insert to authenticated
with check (
  exists (
    select 1
    from public.fantasy_teams team
    join public.matchdays matchday on matchday.id = matchday_id
    where team.id = fantasy_team_id
      and matchday.locks_at > now()
      and (
        team.manager_id = auth.uid()
        or public.is_league_admin(team.league_id)
      )
  )
);

create policy lineups_update_manager
on public.lineups for update to authenticated
using (public.can_manage_lineup(id))
with check (public.can_manage_lineup(id));

create policy lineups_delete_manager
on public.lineups for delete to authenticated
using (public.can_manage_lineup(id));

create policy lineup_entries_read_members
on public.lineup_entries for select to authenticated
using (
  exists (
    select 1
    from public.lineups lineup
    join public.fantasy_teams team on team.id = lineup.fantasy_team_id
    where lineup.id = lineup_id
      and public.is_league_member(team.league_id)
  )
);

create policy lineup_entries_manage_before_lock
on public.lineup_entries for all to authenticated
using (public.can_manage_lineup(lineup_id))
with check (public.can_manage_lineup(lineup_id));

create policy fixtures_read_members
on public.fantasy_fixtures for select to authenticated
using (public.is_league_member(league_id));

create policy scores_read_authenticated
on public.player_match_scores for select to authenticated
using (true);

create policy transactions_read_members
on public.team_transactions for select to authenticated
using (public.is_league_member(league_id));

grant usage on schema public to authenticated;
grant select, insert, update, delete
on all tables in schema public
to authenticated;

revoke all on function public.create_league(
  text,
  public.league_mode,
  smallint,
  integer,
  smallint
) from public;
revoke all on function public.place_bid(uuid, integer) from public;
revoke all on function public.finalize_auction_item(uuid) from public;

grant execute on function public.create_league(
  text,
  public.league_mode,
  smallint,
  integer,
  smallint
) to authenticated;
grant execute on function public.place_bid(uuid, integer) to authenticated;
grant execute on function public.finalize_auction_item(uuid) to authenticated;

do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'bids'
  ) then
    alter publication supabase_realtime add table public.bids;
  end if;
end;
$$;
