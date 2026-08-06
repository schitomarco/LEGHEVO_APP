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
