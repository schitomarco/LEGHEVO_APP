-- LEGHEVO · schema iniziale
-- PostgreSQL / Supabase. Tutti gli identificativi sono UUID.

create extension if not exists pgcrypto;

create type public.league_mode as enum ('classic', 'mantra');
create type public.league_status as enum ('draft', 'active', 'completed', 'archived');
create type public.member_role as enum ('admin', 'manager');
create type public.auction_status as enum ('scheduled', 'live', 'paused', 'completed');
create type public.auction_item_status as enum ('queued', 'bidding', 'sold', 'unsold');
create type public.lineup_status as enum ('draft', 'submitted', 'locked');
create type public.subscription_tier as enum ('free', 'premium');

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null,
  avatar_url text,
  subscription subscription_tier not null default 'free',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.leagues (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles(id),
  name text not null,
  invite_code text not null unique,
  mode league_mode not null,
  status league_status not null default 'draft',
  team_limit smallint not null check (team_limit between 2 and 20),
  starting_credits integer not null default 500 check (starting_credits > 0),
  roster_size smallint not null default 25 check (roster_size between 11 and 50),
  scoring_rules jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.league_members (
  league_id uuid not null references public.leagues(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  role member_role not null default 'manager',
  joined_at timestamptz not null default now(),
  primary key (league_id, user_id)
);

create table public.fantasy_teams (
  id uuid primary key default gen_random_uuid(),
  league_id uuid not null references public.leagues(id) on delete cascade,
  manager_id uuid not null references public.profiles(id),
  name text not null,
  crest_url text,
  credits_remaining integer not null,
  created_at timestamptz not null default now(),
  unique (league_id, manager_id),
  unique (league_id, name)
);

create table public.athletes (
  id uuid primary key default gen_random_uuid(),
  provider text not null,
  provider_player_id text not null,
  first_name text,
  last_name text not null,
  club_name text not null,
  shirt_number smallint,
  active boolean not null default true,
  payload jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now(),
  unique (provider, provider_player_id)
);

create table public.athlete_roles (
  athlete_id uuid not null references public.athletes(id) on delete cascade,
  mode league_mode not null,
  role_code text not null,
  primary key (athlete_id, mode, role_code)
);

create table public.roster_entries (
  id uuid primary key default gen_random_uuid(),
  league_id uuid not null references public.leagues(id) on delete cascade,
  fantasy_team_id uuid not null references public.fantasy_teams(id) on delete cascade,
  athlete_id uuid not null references public.athletes(id),
  purchase_price integer not null check (purchase_price >= 0),
  acquired_at timestamptz not null default now(),
  released_at timestamptz,
  unique nulls not distinct (fantasy_team_id, athlete_id, released_at)
);

create unique index roster_active_athlete_per_league_idx
  on public.roster_entries (league_id, athlete_id)
  where released_at is null;

create table public.auctions (
  id uuid primary key default gen_random_uuid(),
  league_id uuid not null references public.leagues(id) on delete cascade,
  status auction_status not null default 'scheduled',
  current_item_id uuid,
  bid_increment integer not null default 1 check (bid_increment > 0),
  bid_seconds smallint not null default 15 check (bid_seconds between 5 and 120),
  starts_at timestamptz,
  ended_at timestamptz,
  created_at timestamptz not null default now()
);

create table public.auction_items (
  id uuid primary key default gen_random_uuid(),
  auction_id uuid not null references public.auctions(id) on delete cascade,
  athlete_id uuid not null references public.athletes(id),
  nominated_by_team_id uuid references public.fantasy_teams(id),
  winning_team_id uuid references public.fantasy_teams(id),
  status auction_item_status not null default 'queued',
  opening_price integer not null default 1,
  winning_price integer,
  expires_at timestamptz,
  created_at timestamptz not null default now()
);

alter table public.auctions
  add constraint auctions_current_item_fk
  foreign key (current_item_id) references public.auction_items(id);

create table public.bids (
  id uuid primary key default gen_random_uuid(),
  auction_item_id uuid not null references public.auction_items(id) on delete cascade,
  fantasy_team_id uuid not null references public.fantasy_teams(id),
  amount integer not null check (amount > 0),
  created_at timestamptz not null default now()
);

create index bids_item_created_idx
  on public.bids (auction_item_id, created_at desc);

create table public.matchdays (
  id uuid primary key default gen_random_uuid(),
  competition_code text not null,
  season text not null,
  number smallint not null,
  starts_at timestamptz not null,
  locks_at timestamptz not null,
  ends_at timestamptz,
  unique (competition_code, season, number)
);

create table public.lineups (
  id uuid primary key default gen_random_uuid(),
  fantasy_team_id uuid not null references public.fantasy_teams(id) on delete cascade,
  matchday_id uuid not null references public.matchdays(id),
  formation text not null,
  status lineup_status not null default 'draft',
  submitted_at timestamptz,
  unique (fantasy_team_id, matchday_id)
);

create table public.lineup_entries (
  lineup_id uuid not null references public.lineups(id) on delete cascade,
  athlete_id uuid not null references public.athletes(id),
  slot smallint not null,
  is_starter boolean not null,
  captain boolean not null default false,
  primary key (lineup_id, slot),
  unique (lineup_id, athlete_id)
);

create table public.fantasy_fixtures (
  id uuid primary key default gen_random_uuid(),
  league_id uuid not null references public.leagues(id) on delete cascade,
  matchday_id uuid not null references public.matchdays(id),
  home_team_id uuid not null references public.fantasy_teams(id),
  away_team_id uuid not null references public.fantasy_teams(id),
  home_points numeric(6,2),
  away_points numeric(6,2),
  home_goals smallint,
  away_goals smallint,
  finalized_at timestamptz,
  unique (league_id, matchday_id, home_team_id, away_team_id),
  check (home_team_id <> away_team_id)
);

create table public.player_match_scores (
  id uuid primary key default gen_random_uuid(),
  athlete_id uuid not null references public.athletes(id),
  matchday_id uuid not null references public.matchdays(id),
  provider_rating numeric(4,2),
  fantasy_score numeric(5,2),
  bonuses jsonb not null default '{}'::jsonb,
  maluses jsonb not null default '{}'::jsonb,
  is_final boolean not null default false,
  provider_payload jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now(),
  unique (athlete_id, matchday_id)
);

create table public.team_transactions (
  id uuid primary key default gen_random_uuid(),
  league_id uuid not null references public.leagues(id) on delete cascade,
  fantasy_team_id uuid not null references public.fantasy_teams(id),
  athlete_id uuid not null references public.athletes(id),
  transaction_type text not null check (
    transaction_type in ('auction_purchase', 'market_purchase', 'release', 'trade')
  ),
  credit_delta integer not null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

-- Sicurezza e funzioni atomiche: database/002_security_and_functions.sql


-- ============================================================

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


-- ============================================================

-- LEGHEVO · integrazione dati API-Football
-- Eseguire dopo 001_initial_schema.sql e 002_security_and_functions.sql.

alter table public.athletes
  add column photo_url text,
  add column position_code text;

alter table public.player_match_scores
  add column provider_fixture_id text,
  add column raw_statistics jsonb not null default '{}'::jsonb;

create unique index player_scores_provider_fixture_idx
  on public.player_match_scores (athlete_id, provider_fixture_id)
  where provider_fixture_id is not null;

create table public.provider_fixtures (
  id uuid primary key default gen_random_uuid(),
  provider text not null,
  provider_fixture_id text not null,
  competition_code text not null,
  season text not null,
  matchday_id uuid references public.matchdays(id),
  kickoff_at timestamptz not null,
  status text not null,
  home_team_provider_id text not null,
  home_team_name text not null,
  away_team_provider_id text not null,
  away_team_name text not null,
  home_goals smallint,
  away_goals smallint,
  payload jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now(),
  unique (provider, provider_fixture_id)
);

create index provider_fixtures_matchday_idx
  on public.provider_fixtures (matchday_id, kickoff_at);

create table public.provider_sync_runs (
  id uuid primary key default gen_random_uuid(),
  provider text not null,
  sync_type text not null,
  requested_for jsonb not null default '{}'::jsonb,
  status text not null check (status in ('running', 'completed', 'failed')),
  records_processed integer not null default 0,
  error_message text,
  started_at timestamptz not null default now(),
  finished_at timestamptz
);

create trigger provider_fixtures_set_updated_at
before update on public.provider_fixtures
for each row execute function public.set_updated_at();

alter table public.provider_fixtures enable row level security;
alter table public.provider_sync_runs enable row level security;

create policy provider_fixtures_read_authenticated
on public.provider_fixtures for select to authenticated
using (true);

grant select on public.provider_fixtures to authenticated;

comment on table public.provider_fixtures is
  'Partite normalizzate dal provider sportivo; il payload originale resta disponibile per audit.';

comment on table public.provider_sync_runs is
  'Registro tecnico delle sincronizzazioni server-side con il provider dati.';

comment on column public.player_match_scores.provider_rating is
  'Rating base 0-10 restituito dal provider, prima di bonus e malus LEGHEVO.';

comment on column public.player_match_scores.fantasy_score is
  'Fantavoto standard LEGHEVO; le regole personalizzate di lega vengono applicate dal motore risultati.';
