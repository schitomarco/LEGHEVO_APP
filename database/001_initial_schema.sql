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
