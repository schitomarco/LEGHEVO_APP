-- LEGHEVO · fondazione multi-provider, cache autorevole e quota API
-- Migrazione append-only successiva alla v0.62.49.
-- Non attiva cron, non contiene segreti e non modifica dati di produzione.

begin;

set local statement_timeout = '10min';

create table if not exists public.canonical_football_entities (
  id uuid primary key default gen_random_uuid(),
  entity_type text not null check (
    entity_type in ('competition', 'club', 'player', 'fixture')
  ),
  canonical_key text not null,
  display_name text not null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (entity_type, canonical_key),
  check (canonical_key = lower(trim(canonical_key))),
  check (char_length(trim(display_name)) > 0)
);

create table if not exists public.provider_entity_mappings (
  id uuid primary key default gen_random_uuid(),
  canonical_entity_id uuid not null
    references public.canonical_football_entities(id) on delete restrict,
  provider text not null,
  entity_type text not null check (
    entity_type in ('competition', 'club', 'player', 'fixture')
  ),
  external_id text not null,
  mapping_status text not null default 'confirmed' check (
    mapping_status in ('confirmed', 'probable', 'conflict', 'quarantined')
  ),
  confidence numeric(5,4) not null default 1 check (
    confidence >= 0 and confidence <= 1
  ),
  evidence jsonb not null default '{}'::jsonb,
  payload_fingerprint text,
  verified_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (provider, entity_type, external_id),
  unique (canonical_entity_id, provider),
  check (provider = lower(trim(provider))),
  check (char_length(trim(external_id)) > 0),
  check (
    payload_fingerprint is null
    or payload_fingerprint ~ '^[a-f0-9]{64}$'
  )
);

create table if not exists public.provider_identity_conflicts (
  id uuid primary key default gen_random_uuid(),
  entity_type text not null check (
    entity_type in ('competition', 'club', 'player', 'fixture')
  ),
  provider text not null,
  external_id text not null,
  candidate_canonical_ids uuid[] not null,
  reason_code text not null,
  evidence jsonb not null default '{}'::jsonb,
  status text not null default 'open' check (
    status in ('open', 'resolved', 'dismissed')
  ),
  resolved_canonical_id uuid
    references public.canonical_football_entities(id) on delete restrict,
  created_at timestamptz not null default now(),
  resolved_at timestamptz,
  check (coalesce(array_length(candidate_canonical_ids, 1), 0) > 0),
  check (
    (status = 'open' and resolved_at is null)
    or (status <> 'open' and resolved_at is not null)
  )
);

create unique index if not exists provider_identity_conflicts_open_uidx
  on public.provider_identity_conflicts (provider, entity_type, external_id)
  where status = 'open';

create table if not exists public.provider_quota_policies (
  provider text primary key,
  daily_limit integer not null check (daily_limit > 0),
  reserved_p0_units integer not null default 0 check (
    reserved_p0_units >= 0 and reserved_p0_units < daily_limit
  ),
  minute_limit integer check (minute_limit is null or minute_limit > 0),
  enabled boolean not null default true,
  updated_at timestamptz not null default now(),
  check (provider = lower(trim(provider)))
);

create table if not exists public.provider_field_authority (
  resource_type text not null,
  field_name text not null,
  primary_provider text not null,
  fallback_provider text,
  conflict_policy text not null default 'quarantine' check (
    conflict_policy in ('quarantine', 'primary_wins_after_validation')
  ),
  updated_at timestamptz not null default now(),
  primary key (resource_type, field_name),
  check (primary_provider = lower(trim(primary_provider))),
  check (
    fallback_provider is null
    or fallback_provider = lower(trim(fallback_provider))
  )
);

insert into public.provider_field_authority (
  resource_type,
  field_name,
  primary_provider,
  fallback_provider,
  conflict_policy
) values
  ('competition', '*', 'football-data', 'api-football', 'quarantine'),
  ('club', '*', 'football-data', 'api-football', 'quarantine'),
  ('fixture', 'kickoff_at', 'football-data', 'api-football', 'quarantine'),
  ('fixture', 'status', 'football-data', 'api-football', 'quarantine'),
  ('fixture', 'result', 'football-data', 'api-football', 'quarantine'),
  ('player', '*', 'api-football', null, 'quarantine'),
  ('lineup', '*', 'api-football', null, 'quarantine'),
  ('event', '*', 'api-football', null, 'quarantine'),
  ('player_statistics', '*', 'api-football', null, 'quarantine')
on conflict (resource_type, field_name) do nothing;

insert into public.provider_quota_policies (
  provider,
  daily_limit,
  reserved_p0_units,
  minute_limit
) values
  ('api-football', 100, 20, 10),
  ('football-data', 100000, 0, 10)
on conflict (provider) do nothing;

create table if not exists public.provider_daily_quota_usage (
  provider text not null
    references public.provider_quota_policies(provider) on delete restrict,
  quota_date date not null,
  daily_limit integer not null check (daily_limit > 0),
  reserved_p0_units integer not null check (
    reserved_p0_units >= 0 and reserved_p0_units < daily_limit
  ),
  consumed_units integer not null default 0 check (consumed_units >= 0),
  rejected_requests integer not null default 0 check (rejected_requests >= 0),
  provider_reported_limit integer,
  provider_reported_remaining integer,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (provider, quota_date),
  check (consumed_units <= daily_limit),
  check (
    provider_reported_remaining is null
    or provider_reported_remaining >= 0
  )
);

create table if not exists public.provider_request_ledger (
  id uuid primary key default gen_random_uuid(),
  provider text not null,
  endpoint text not null,
  request_hash text not null check (request_hash ~ '^[a-f0-9]{64}$'),
  priority text not null check (priority in ('P0', 'P1', 'P2', 'P3')),
  quota_date date not null,
  quota_units integer not null default 0 check (quota_units in (0, 1)),
  cache_status text not null check (cache_status in ('hit', 'miss', 'bypass')),
  reason_code text not null default 'unspecified',
  retry_no integer not null default 0 check (retry_no >= 0),
  fallback_provider text,
  request_context jsonb not null default '{}'::jsonb,
  external_request_avoided boolean not null default false,
  status text not null check (
    status in ('started', 'completed', 'failed', 'rejected')
  ),
  run_id uuid references public.provider_sync_runs(id) on delete set null,
  http_status integer,
  provider_reported_limit integer,
  provider_reported_remaining integer,
  error_code text,
  started_at timestamptz not null default now(),
  finished_at timestamptz,
  check (endpoint like '/%'),
  check (
    (status = 'started' and finished_at is null)
    or (status <> 'started' and finished_at is not null)
  )
);

alter table public.provider_request_ledger
  add column if not exists reason_code text not null default 'unspecified',
  add column if not exists retry_no integer not null default 0,
  add column if not exists fallback_provider text,
  add column if not exists request_context jsonb not null default '{}'::jsonb,
  add column if not exists external_request_avoided boolean not null default false;

alter table public.provider_request_ledger
  drop constraint if exists provider_request_ledger_cache_status_check;
alter table public.provider_request_ledger
  add constraint provider_request_ledger_cache_status_check
  check (cache_status in ('hit', 'miss', 'bypass'));

create index if not exists provider_request_ledger_timeline_idx
  on public.provider_request_ledger (provider, started_at desc);

create index if not exists provider_request_ledger_run_idx
  on public.provider_request_ledger (run_id, started_at)
  where run_id is not null;

create table if not exists public.provider_response_cache (
  provider text not null,
  endpoint text not null,
  request_hash text not null check (request_hash ~ '^[a-f0-9]{64}$'),
  response_payload jsonb not null,
  payload_fingerprint text not null check (
    payload_fingerprint ~ '^[a-f0-9]{32}$'
  ),
  etag text,
  last_modified text,
  stored_at timestamptz not null default now(),
  expires_at timestamptz not null,
  last_hit_at timestamptz,
  hit_count bigint not null default 0 check (hit_count >= 0),
  primary key (provider, endpoint, request_hash),
  check (endpoint like '/%'),
  check (expires_at > stored_at)
);

create index if not exists provider_response_cache_expiry_idx
  on public.provider_response_cache (expires_at);

alter table public.athletes
  add column if not exists canonical_entity_id uuid
    references public.canonical_football_entities(id) on delete restrict;

alter table public.provider_fixtures
  add column if not exists canonical_entity_id uuid
    references public.canonical_football_entities(id) on delete restrict;

alter table public.player_match_scores
  add column if not exists provider text not null default 'api-football';

create index if not exists athletes_canonical_entity_idx
  on public.athletes (canonical_entity_id)
  where canonical_entity_id is not null;

create index if not exists provider_fixtures_canonical_entity_idx
  on public.provider_fixtures (canonical_entity_id)
  where canonical_entity_id is not null;

create unique index if not exists player_scores_provider_identity_uidx
  on public.player_match_scores (athlete_id, provider, provider_fixture_id)
  where provider_fixture_id is not null;

create or replace function public.ensure_provider_entity_mapping_v1(
  p_provider text,
  p_entity_type text,
  p_external_id text,
  p_display_name text,
  p_metadata jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_provider text := lower(trim(coalesce(p_provider, '')));
  v_entity_type text := lower(trim(coalesce(p_entity_type, '')));
  v_external_id text := trim(coalesce(p_external_id, ''));
  v_display_name text := trim(coalesce(p_display_name, ''));
  v_canonical_key text;
  v_canonical_id uuid;
begin
  if v_provider = '' or v_external_id = '' then
    raise exception 'Provider e ID esterno sono obbligatori.';
  end if;
  if v_entity_type not in ('competition', 'club', 'player', 'fixture') then
    raise exception 'Tipo identità provider non valido.';
  end if;
  if v_display_name = '' then
    v_display_name := initcap(v_entity_type) || ' ' || v_external_id;
  end if;

  v_canonical_key := v_provider || ':' || v_entity_type || ':'
    || lower(v_external_id);

  insert into public.canonical_football_entities (
    entity_type,
    canonical_key,
    display_name,
    metadata
  ) values (
    v_entity_type,
    v_canonical_key,
    v_display_name,
    coalesce(p_metadata, '{}'::jsonb)
  )
  on conflict (entity_type, canonical_key) do nothing;

  select canonical.id
  into v_canonical_id
  from public.canonical_football_entities canonical
  where canonical.entity_type = v_entity_type
    and canonical.canonical_key = v_canonical_key;

  insert into public.provider_entity_mappings (
    canonical_entity_id,
    provider,
    entity_type,
    external_id,
    mapping_status,
    confidence,
    evidence,
    verified_at
  ) values (
    v_canonical_id,
    v_provider,
    v_entity_type,
    v_external_id,
    'confirmed',
    1,
    jsonb_build_object('source', 'automatic-ingestion'),
    now()
  )
  on conflict (provider, entity_type, external_id) do nothing;

  select mapping.canonical_entity_id
  into v_canonical_id
  from public.provider_entity_mappings mapping
  where mapping.provider = v_provider
    and mapping.entity_type = v_entity_type
    and mapping.external_id = v_external_id;

  return v_canonical_id;
end;
$function$;

create or replace function public.canonicalize_athlete_provider_identity_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_player_id uuid;
begin
  v_player_id := public.ensure_provider_entity_mapping_v1(
    new.provider,
    'player',
    new.provider_player_id,
    trim(concat_ws(' ', new.first_name, new.last_name)),
    jsonb_build_object('athleteId', new.id)
  );

  if nullif(trim(coalesce(new.provider_team_id, '')), '') is not null then
    perform public.ensure_provider_entity_mapping_v1(
      new.provider,
      'club',
      new.provider_team_id,
      new.club_name,
      jsonb_build_object('source', 'athlete')
    );
  end if;

  update public.athletes athlete
  set canonical_entity_id = v_player_id
  where athlete.id = new.id
    and athlete.canonical_entity_id is distinct from v_player_id;
  return new;
end;
$function$;

create or replace function public.canonicalize_fixture_provider_identity_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_fixture_id uuid;
begin
  v_fixture_id := public.ensure_provider_entity_mapping_v1(
    new.provider,
    'fixture',
    new.provider_fixture_id,
    new.home_team_name || ' - ' || new.away_team_name,
    jsonb_build_object(
      'competitionCode', new.competition_code,
      'season', new.season,
      'kickoffAt', new.kickoff_at
    )
  );

  perform public.ensure_provider_entity_mapping_v1(
    new.provider,
    'competition',
    new.competition_code,
    new.competition_code,
    jsonb_build_object('source', 'provider-fixture')
  );
  perform public.ensure_provider_entity_mapping_v1(
    new.provider,
    'club',
    new.home_team_provider_id,
    new.home_team_name,
    jsonb_build_object('source', 'provider-fixture-home')
  );
  perform public.ensure_provider_entity_mapping_v1(
    new.provider,
    'club',
    new.away_team_provider_id,
    new.away_team_name,
    jsonb_build_object('source', 'provider-fixture-away')
  );

  update public.provider_fixtures fixture
  set canonical_entity_id = v_fixture_id
  where fixture.id = new.id
    and fixture.canonical_entity_id is distinct from v_fixture_id;
  return new;
end;
$function$;

-- Canonicalizzazione iniziale conservativa: ogni identità già certificata
-- diventa canonica senza tentare fusioni euristiche tra persone o club.
insert into public.canonical_football_entities (
  entity_type,
  canonical_key,
  display_name,
  metadata
)
select
  'player',
  lower(athlete.provider) || ':player:' || lower(athlete.provider_player_id),
  trim(concat_ws(' ', athlete.first_name, athlete.last_name)),
  jsonb_build_object('bootstrapProvider', athlete.provider)
from public.athletes athlete
where char_length(trim(concat_ws(' ', athlete.first_name, athlete.last_name))) > 0
on conflict (entity_type, canonical_key) do nothing;

insert into public.provider_entity_mappings (
  canonical_entity_id,
  provider,
  entity_type,
  external_id,
  mapping_status,
  confidence,
  evidence,
  verified_at
)
select
  canonical.id,
  lower(athlete.provider),
  'player',
  athlete.provider_player_id,
  'confirmed',
  1,
  jsonb_build_object('source', 'athletes', 'athleteId', athlete.id),
  now()
from public.athletes athlete
join public.canonical_football_entities canonical
  on canonical.entity_type = 'player'
 and canonical.canonical_key =
   lower(athlete.provider) || ':player:' || lower(athlete.provider_player_id)
on conflict (provider, entity_type, external_id) do nothing;

update public.athletes athlete
set canonical_entity_id = mapping.canonical_entity_id
from public.provider_entity_mappings mapping
where mapping.provider = lower(athlete.provider)
  and mapping.entity_type = 'player'
  and mapping.external_id = athlete.provider_player_id
  and athlete.canonical_entity_id is null;

insert into public.canonical_football_entities (
  entity_type,
  canonical_key,
  display_name,
  metadata
)
select
  'fixture',
  lower(fixture.provider) || ':fixture:' || lower(fixture.provider_fixture_id),
  fixture.home_team_name || ' - ' || fixture.away_team_name,
  jsonb_build_object(
    'competitionCode', fixture.competition_code,
    'season', fixture.season,
    'kickoffAt', fixture.kickoff_at
  )
from public.provider_fixtures fixture
on conflict (entity_type, canonical_key) do nothing;

insert into public.provider_entity_mappings (
  canonical_entity_id,
  provider,
  entity_type,
  external_id,
  mapping_status,
  confidence,
  evidence,
  verified_at
)
select
  canonical.id,
  lower(fixture.provider),
  'fixture',
  fixture.provider_fixture_id,
  'confirmed',
  1,
  jsonb_build_object('source', 'provider_fixtures', 'fixtureId', fixture.id),
  now()
from public.provider_fixtures fixture
join public.canonical_football_entities canonical
  on canonical.entity_type = 'fixture'
 and canonical.canonical_key =
   lower(fixture.provider) || ':fixture:' || lower(fixture.provider_fixture_id)
on conflict (provider, entity_type, external_id) do nothing;

update public.provider_fixtures fixture
set canonical_entity_id = mapping.canonical_entity_id
from public.provider_entity_mappings mapping
where mapping.provider = lower(fixture.provider)
  and mapping.entity_type = 'fixture'
  and mapping.external_id = fixture.provider_fixture_id
  and fixture.canonical_entity_id is null;

select public.ensure_provider_entity_mapping_v1(
  club.provider,
  'club',
  club.external_id,
  club.display_name,
  jsonb_build_object('source', 'bootstrap')
)
from (
  select distinct
    lower(athlete.provider) as provider,
    athlete.provider_team_id as external_id,
    athlete.club_name as display_name
  from public.athletes athlete
  where nullif(trim(coalesce(athlete.provider_team_id, '')), '') is not null
  union
  select distinct
    lower(fixture.provider),
    fixture.home_team_provider_id,
    fixture.home_team_name
  from public.provider_fixtures fixture
  union
  select distinct
    lower(fixture.provider),
    fixture.away_team_provider_id,
    fixture.away_team_name
  from public.provider_fixtures fixture
) club;

select public.ensure_provider_entity_mapping_v1(
  competition.provider,
  'competition',
  competition.competition_code,
  competition.competition_code,
  jsonb_build_object('source', 'bootstrap')
)
from (
  select distinct
    lower(fixture.provider) as provider,
    fixture.competition_code
  from public.provider_fixtures fixture
) competition;

drop trigger if exists athletes_canonicalize_provider_identity
  on public.athletes;
create trigger athletes_canonicalize_provider_identity
after insert or update of provider, provider_player_id, provider_team_id,
  first_name, last_name, club_name
on public.athletes
for each row execute function public.canonicalize_athlete_provider_identity_v1();

drop trigger if exists provider_fixtures_canonicalize_provider_identity
  on public.provider_fixtures;
create trigger provider_fixtures_canonicalize_provider_identity
after insert or update of provider, provider_fixture_id, competition_code,
  season, kickoff_at, home_team_provider_id, home_team_name,
  away_team_provider_id, away_team_name
on public.provider_fixtures
for each row execute function public.canonicalize_fixture_provider_identity_v1();

create or replace function public.claim_provider_request_budget_v1(
  p_provider text,
  p_endpoint text,
  p_request_hash text,
  p_priority text,
  p_run_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_provider text := lower(trim(coalesce(p_provider, '')));
  v_endpoint text := trim(coalesce(p_endpoint, ''));
  v_priority text := upper(trim(coalesce(p_priority, '')));
  v_today date := (now() at time zone 'UTC')::date;
  v_policy public.provider_quota_policies%rowtype;
  v_usage public.provider_daily_quota_usage%rowtype;
  v_request_id uuid := gen_random_uuid();
  v_threshold integer;
  v_allowed boolean;
begin
  if v_endpoint !~ '^/[a-z0-9/_-]+$' then
    raise exception 'Endpoint provider non valido.';
  end if;
  if coalesce(p_request_hash, '') !~ '^[a-f0-9]{64}$' then
    raise exception 'Fingerprint richiesta provider non valida.';
  end if;
  if v_priority not in ('P0', 'P1', 'P2', 'P3') then
    raise exception 'Priorità provider non valida.';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext(v_provider || ':' || v_today::text)
  );

  select policy.*
  into v_policy
  from public.provider_quota_policies policy
  where policy.provider = v_provider
    and policy.enabled;

  if not found then
    raise exception 'Policy quota provider assente o disabilitata: %.', v_provider;
  end if;

  insert into public.provider_daily_quota_usage (
    provider,
    quota_date,
    daily_limit,
    reserved_p0_units
  ) values (
    v_provider,
    v_today,
    v_policy.daily_limit,
    v_policy.reserved_p0_units
  )
  on conflict (provider, quota_date) do update
  set
    daily_limit = excluded.daily_limit,
    reserved_p0_units = excluded.reserved_p0_units,
    updated_at = now()
  returning * into v_usage;

  -- La riserva è accessibile soltanto a HIGH e CRITICAL. Il nome fisico
  -- reserved_p0_units resta stabile per compatibilità con la prima bozza
  -- locale della migrazione, ma il comportamento copre P0 e P1.
  v_threshold := case
    when v_priority in ('P0', 'P1') then v_usage.daily_limit
    else v_usage.daily_limit - v_usage.reserved_p0_units
  end;
  v_allowed := v_usage.consumed_units < v_threshold;

  if v_allowed then
    update public.provider_daily_quota_usage usage
    set
      consumed_units = usage.consumed_units + 1,
      updated_at = now()
    where usage.provider = v_provider
      and usage.quota_date = v_today
    returning * into v_usage;
  else
    update public.provider_daily_quota_usage usage
    set
      rejected_requests = usage.rejected_requests + 1,
      updated_at = now()
    where usage.provider = v_provider
      and usage.quota_date = v_today
    returning * into v_usage;
  end if;

  insert into public.provider_request_ledger (
    id,
    provider,
    endpoint,
    request_hash,
    priority,
    quota_date,
    quota_units,
    cache_status,
    status,
    run_id,
    finished_at,
    error_code
  ) values (
    v_request_id,
    v_provider,
    v_endpoint,
    p_request_hash,
    v_priority,
    v_today,
    case when v_allowed then 1 else 0 end,
    'miss',
    case when v_allowed then 'started' else 'rejected' end,
    p_run_id,
    case when v_allowed then null else now() end,
    case when v_allowed then null else 'quota.daily_budget_exhausted' end
  );

  return jsonb_build_object(
    'allowed', v_allowed,
    'requestId', v_request_id,
    'provider', v_provider,
    'priority', v_priority,
    'dailyLimit', v_usage.daily_limit,
    'reservedHighPriorityUnits', v_usage.reserved_p0_units,
    'consumedUnits', v_usage.consumed_units,
    'remainingUnits', greatest(v_usage.daily_limit - v_usage.consumed_units, 0),
    'ordinaryRemainingUnits', greatest(
      v_usage.daily_limit - v_usage.reserved_p0_units - v_usage.consumed_units,
      0
    )
  );
end;
$function$;

create or replace function public.finish_provider_request_v1(
  p_request_id uuid,
  p_succeeded boolean,
  p_http_status integer default null,
  p_provider_reported_limit integer default null,
  p_provider_reported_remaining integer default null,
  p_error_code text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_request public.provider_request_ledger%rowtype;
begin
  select request.*
  into v_request
  from public.provider_request_ledger request
  where request.id = p_request_id
  for update;

  if not found then
    raise exception 'Richiesta provider non trovata.';
  end if;
  if v_request.status <> 'started' then
    return;
  end if;

  update public.provider_request_ledger request
  set
    status = case when p_succeeded then 'completed' else 'failed' end,
    http_status = p_http_status,
    provider_reported_limit = p_provider_reported_limit,
    provider_reported_remaining = p_provider_reported_remaining,
    error_code = case
      when p_succeeded then null
      else left(coalesce(nullif(trim(p_error_code), ''), 'provider.request_failed'), 160)
    end,
    finished_at = now()
  where request.id = p_request_id;

  if p_provider_reported_limit is not null
    or p_provider_reported_remaining is not null then
    update public.provider_daily_quota_usage usage
    set
      provider_reported_limit = coalesce(
        p_provider_reported_limit,
        usage.provider_reported_limit
      ),
      provider_reported_remaining = coalesce(
        p_provider_reported_remaining,
        usage.provider_reported_remaining
      ),
      updated_at = now()
    where usage.provider = v_request.provider
      and usage.quota_date = v_request.quota_date;
  end if;
end;
$function$;

create or replace function public.claim_provider_request_budget_v2(
  p_provider text,
  p_endpoint text,
  p_request_hash text,
  p_priority text,
  p_run_id uuid default null,
  p_reason_code text default 'scheduled-sync',
  p_retry_no integer default 0,
  p_fallback_provider text default null,
  p_request_context jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_result jsonb;
  v_request_id uuid;
begin
  if coalesce(p_retry_no, 0) < 0 then
    raise exception 'Numero retry provider non valido.';
  end if;
  if jsonb_typeof(coalesce(p_request_context, '{}'::jsonb)) <> 'object' then
    raise exception 'Contesto richiesta provider non valido.';
  end if;

  v_result := public.claim_provider_request_budget_v1(
    p_provider,
    p_endpoint,
    p_request_hash,
    p_priority,
    p_run_id
  );
  v_request_id := (v_result ->> 'requestId')::uuid;

  update public.provider_request_ledger request
  set
    reason_code = left(
      coalesce(nullif(trim(p_reason_code), ''), 'scheduled-sync'),
      120
    ),
    retry_no = coalesce(p_retry_no, 0),
    fallback_provider = nullif(lower(trim(p_fallback_provider)), ''),
    request_context = coalesce(p_request_context, '{}'::jsonb)
  where request.id = v_request_id;

  return v_result;
end;
$function$;

create or replace function public.record_provider_cache_hit_v1(
  p_provider text,
  p_endpoint text,
  p_request_hash text,
  p_priority text,
  p_run_id uuid default null,
  p_reason_code text default 'scheduled-sync',
  p_retry_no integer default 0,
  p_fallback_provider text default null,
  p_request_context jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_request_id uuid := gen_random_uuid();
  v_priority text := upper(trim(coalesce(p_priority, '')));
begin
  if v_priority not in ('P0', 'P1', 'P2', 'P3') then
    raise exception 'Priorità provider non valida.';
  end if;
  if coalesce(p_request_hash, '') !~ '^[a-f0-9]{64}$' then
    raise exception 'Fingerprint richiesta provider non valida.';
  end if;
  if coalesce(p_retry_no, 0) < 0 then
    raise exception 'Numero retry provider non valido.';
  end if;

  insert into public.provider_request_ledger (
    id,
    provider,
    endpoint,
    request_hash,
    priority,
    quota_date,
    quota_units,
    cache_status,
    reason_code,
    retry_no,
    fallback_provider,
    request_context,
    external_request_avoided,
    status,
    run_id,
    finished_at
  ) values (
    v_request_id,
    lower(trim(p_provider)),
    trim(p_endpoint),
    p_request_hash,
    v_priority,
    (now() at time zone 'UTC')::date,
    0,
    'hit',
    left(coalesce(nullif(trim(p_reason_code), ''), 'scheduled-sync'), 120),
    coalesce(p_retry_no, 0),
    nullif(lower(trim(p_fallback_provider)), ''),
    coalesce(p_request_context, '{}'::jsonb),
    true,
    'completed',
    p_run_id,
    now()
  );

  return v_request_id;
end;
$function$;

create or replace function public.read_provider_response_cache_v1(
  p_provider text,
  p_endpoint text,
  p_request_hash text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_cache public.provider_response_cache%rowtype;
begin
  update public.provider_response_cache cache
  set
    hit_count = cache.hit_count + 1,
    last_hit_at = now()
  where cache.provider = lower(trim(p_provider))
    and cache.endpoint = trim(p_endpoint)
    and cache.request_hash = p_request_hash
    and cache.expires_at > now()
  returning * into v_cache;

  if not found then
    return jsonb_build_object('cacheHit', false);
  end if;

  return jsonb_build_object(
    'cacheHit', true,
    'payload', v_cache.response_payload,
    'storedAt', v_cache.stored_at,
    'expiresAt', v_cache.expires_at,
    'hitCount', v_cache.hit_count
  );
end;
$function$;

create or replace function public.write_provider_response_cache_v1(
  p_provider text,
  p_endpoint text,
  p_request_hash text,
  p_payload jsonb,
  p_ttl_seconds integer,
  p_etag text default null,
  p_last_modified text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_now timestamptz := now();
begin
  if p_ttl_seconds < 1 or p_ttl_seconds > 604800 then
    raise exception 'TTL cache provider fuori intervallo.';
  end if;
  if coalesce(p_request_hash, '') !~ '^[a-f0-9]{64}$' then
    raise exception 'Fingerprint richiesta provider non valida.';
  end if;

  insert into public.provider_response_cache (
    provider,
    endpoint,
    request_hash,
    response_payload,
    payload_fingerprint,
    etag,
    last_modified,
    stored_at,
    expires_at,
    hit_count,
    last_hit_at
  ) values (
    lower(trim(p_provider)),
    trim(p_endpoint),
    p_request_hash,
    p_payload,
    pg_catalog.md5(p_payload::text),
    nullif(trim(p_etag), ''),
    nullif(trim(p_last_modified), ''),
    v_now,
    v_now + make_interval(secs => p_ttl_seconds),
    0,
    null
  )
  on conflict (provider, endpoint, request_hash) do update
  set
    response_payload = excluded.response_payload,
    payload_fingerprint = excluded.payload_fingerprint,
    etag = excluded.etag,
    last_modified = excluded.last_modified,
    stored_at = excluded.stored_at,
    expires_at = excluded.expires_at,
    hit_count = 0,
    last_hit_at = null;
end;
$function$;

create or replace function public.get_provider_quota_status_v1()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $function$
  select coalesce(jsonb_agg(jsonb_build_object(
    'provider', policy.provider,
    'date', (now() at time zone 'UTC')::date,
    'dailyLimit', policy.daily_limit,
    'reservedHighPriorityUnits', policy.reserved_p0_units,
    'consumedUnits', coalesce(usage.consumed_units, 0),
    'remainingUnits', greatest(
      policy.daily_limit - coalesce(usage.consumed_units, 0),
      0
    ),
    'ordinaryRemainingUnits', greatest(
      policy.daily_limit - policy.reserved_p0_units
      - coalesce(usage.consumed_units, 0),
      0
    ),
    'rejectedRequests', coalesce(usage.rejected_requests, 0),
    'providerReportedRemaining', usage.provider_reported_remaining,
    'cacheEntries', (
      select count(*)
      from public.provider_response_cache cache
      where cache.provider = policy.provider
        and cache.expires_at > now()
    ),
    'cacheHits', (
      select coalesce(sum(cache.hit_count), 0)
      from public.provider_response_cache cache
      where cache.provider = policy.provider
    )
  ) order by policy.provider), '[]'::jsonb)
  from public.provider_quota_policies policy
  left join public.provider_daily_quota_usage usage
    on usage.provider = policy.provider
   and usage.quota_date = (now() at time zone 'UTC')::date
  where policy.enabled
$function$;

create or replace function public.get_multi_provider_diagnostics_v1()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $function$
  select jsonb_build_object(
    'canonicalEntitiesTable',
      to_regclass('public.canonical_football_entities') is not null,
    'providerMappingsTable',
      to_regclass('public.provider_entity_mappings') is not null,
    'identityConflictsTable',
      to_regclass('public.provider_identity_conflicts') is not null,
    'quotaPoliciesTable',
      to_regclass('public.provider_quota_policies') is not null,
    'fieldAuthorityTable',
      to_regclass('public.provider_field_authority') is not null,
    'dailyQuotaTable',
      to_regclass('public.provider_daily_quota_usage') is not null,
    'requestLedgerTable',
      to_regclass('public.provider_request_ledger') is not null,
    'responseCacheTable',
      to_regclass('public.provider_response_cache') is not null,
    'athleteCanonicalColumn', exists (
      select 1 from information_schema.columns column_row
      where column_row.table_schema = 'public'
        and column_row.table_name = 'athletes'
        and column_row.column_name = 'canonical_entity_id'
    ),
    'fixtureCanonicalColumn', exists (
      select 1 from information_schema.columns column_row
      where column_row.table_schema = 'public'
        and column_row.table_name = 'provider_fixtures'
        and column_row.column_name = 'canonical_entity_id'
    ),
    'scoreProviderColumn', exists (
      select 1 from information_schema.columns column_row
      where column_row.table_schema = 'public'
        and column_row.table_name = 'player_match_scores'
        and column_row.column_name = 'provider'
    ),
    'budgetClaimFunction', to_regprocedure(
      'public.claim_provider_request_budget_v1(text,text,text,text,uuid)'
    ) is not null,
    'requestFinishFunction', to_regprocedure(
      'public.finish_provider_request_v1(uuid,boolean,integer,integer,integer,text)'
    ) is not null,
    'budgetClaimV2Function', to_regprocedure(
      'public.claim_provider_request_budget_v2(text,text,text,text,uuid,text,integer,text,jsonb)'
    ) is not null,
    'cacheHitAuditFunction', to_regprocedure(
      'public.record_provider_cache_hit_v1(text,text,text,text,uuid,text,integer,text,jsonb)'
    ) is not null,
    'costMetricsFunction', to_regprocedure(
      'public.get_provider_cost_metrics_v1(date)'
    ) is not null,
    'leagueBudgetCenterFunction', to_regprocedure(
      'public.get_league_provider_budget_center_v1(uuid)'
    ) is not null,
    'cacheReadFunction', to_regprocedure(
      'public.read_provider_response_cache_v1(text,text,text)'
    ) is not null,
    'cacheWriteFunction', to_regprocedure(
      'public.write_provider_response_cache_v1(text,text,text,jsonb,integer,text,text)'
    ) is not null,
    'athleteCanonicalTrigger', exists (
      select 1
      from pg_catalog.pg_trigger trigger_row
      where trigger_row.tgname = 'athletes_canonicalize_provider_identity'
        and not trigger_row.tgisinternal
    ),
    'fixtureCanonicalTrigger', exists (
      select 1
      from pg_catalog.pg_trigger trigger_row
      where trigger_row.tgname = 'provider_fixtures_canonicalize_provider_identity'
        and not trigger_row.tgisinternal
    ),
    'apiFootballPolicyConfigured', exists (
      select 1
      from public.provider_quota_policies policy
      where policy.provider = 'api-football'
        and policy.daily_limit = 100
        and policy.reserved_p0_units = 20
        and policy.enabled
    ),
    'footballDataPolicyConfigured', exists (
      select 1
      from public.provider_quota_policies policy
      where policy.provider = 'football-data'
        and policy.enabled
    ),
    'openIdentityConflicts', (
      select count(*)
      from public.provider_identity_conflicts conflict
      where conflict.status = 'open'
    ),
    'quota', public.get_provider_quota_status_v1()
  )
$function$;

create or replace function public.get_provider_cost_metrics_v1(
  p_from_date date default ((now() at time zone 'UTC')::date - 29)
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $function$
  with request_data as (
    select request.*
    from public.provider_request_ledger request
    where request.quota_date >= coalesce(
      p_from_date,
      (now() at time zone 'UTC')::date - 29
    )
  ),
  daily as (
    select
      request.provider,
      request.quota_date,
      sum(request.quota_units)::integer as external_requests,
      count(*) filter (where request.cache_status = 'hit')::integer as cache_hits,
      count(*) filter (where request.status = 'failed')::integer as failures
    from request_data request
    group by request.provider, request.quota_date
  ),
  endpoint as (
    select
      request.provider,
      request.endpoint,
      sum(request.quota_units)::integer as external_requests,
      count(*) filter (where request.cache_status = 'hit')::integer as cache_hits,
      count(*) filter (where request.status = 'failed')::integer as failures
    from request_data request
    group by request.provider, request.endpoint
  ),
  fixture as (
    select
      request.provider,
      coalesce(
        request.request_context ->> 'fixture',
        request.request_context ->> 'fixtureId'
      ) as fixture_id,
      sum(request.quota_units)::integer as external_requests,
      count(*) filter (where request.cache_status = 'hit')::integer as cache_hits
    from request_data request
    where coalesce(
      request.request_context ->> 'fixture',
      request.request_context ->> 'fixtureId'
    ) is not null
    group by request.provider, coalesce(
      request.request_context ->> 'fixture',
      request.request_context ->> 'fixtureId'
    )
  ),
  aggregates as (
    select
      coalesce(sum(request.quota_units), 0)::integer as external_requests,
      count(*) filter (where request.status = 'completed')::integer as succeeded,
      count(*) filter (where request.status = 'failed')::integer as failed,
      count(*) filter (where request.status = 'rejected')::integer as rejected,
      count(*) filter (where request.cache_status = 'hit')::integer as cache_hits,
      count(*) filter (where request.cache_status = 'miss')::integer as cache_misses,
      count(*) filter (where request.external_request_avoided)::integer as avoided,
      count(*) filter (where request.retry_no > 0)::integer as retries,
      count(*) filter (where request.fallback_provider is not null)::integer as fallbacks
    from request_data request
  ),
  daily_summary as (
    select
      coalesce(max(day.external_requests), 0)::integer as peak_daily,
      coalesce(round(avg(day.external_requests), 2), 0) as average_daily
    from daily day
  )
  select jsonb_build_object(
    'fromDate', coalesce(p_from_date, (now() at time zone 'UTC')::date - 29),
    'throughDate', (now() at time zone 'UTC')::date,
    'externalRequests', aggregates.external_requests,
    'succeeded', aggregates.succeeded,
    'failed', aggregates.failed,
    'rejected', aggregates.rejected,
    'cacheHits', aggregates.cache_hits,
    'cacheMisses', aggregates.cache_misses,
    'externalRequestsAvoided', aggregates.avoided,
    'retries', aggregates.retries,
    'fallbacks', aggregates.fallbacks,
    'peakDaily', daily_summary.peak_daily,
    'averageDaily', daily_summary.average_daily,
    'forecast30Days', round(daily_summary.average_daily * 30, 2),
    'byDay', coalesce((
      select jsonb_agg(to_jsonb(day) order by day.quota_date, day.provider)
      from daily day
    ), '[]'::jsonb),
    'byEndpoint', coalesce((
      select jsonb_agg(to_jsonb(item) order by item.provider, item.endpoint)
      from endpoint item
    ), '[]'::jsonb),
    'byFixture', coalesce((
      select jsonb_agg(to_jsonb(item) order by item.provider, item.fixture_id)
      from fixture item
    ), '[]'::jsonb)
  )
  from aggregates
  cross join daily_summary
$function$;

create or replace function public.get_league_provider_budget_center_v1(
  p_league_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_user_id uuid := auth.uid();
begin
  if v_user_id is null then
    raise exception 'Devi effettuare l''accesso.';
  end if;
  if not exists (
    select 1
    from public.leagues league
    where league.id = p_league_id
      and (
        league.owner_id = v_user_id
        or public.is_league_admin(league.id)
      )
  ) then
    raise exception 'Il Centro Operativo è riservato alla Direzione della lega.';
  end if;

  return jsonb_build_object(
    'generatedAt', now(),
    'providers', public.get_provider_quota_status_v1(),
    'metrics', public.get_provider_cost_metrics_v1(
      (now() at time zone 'UTC')::date - 29
    ),
    'authority', coalesce((
      select jsonb_agg(jsonb_build_object(
        'resourceType', authority.resource_type,
        'fieldName', authority.field_name,
        'primaryProvider', authority.primary_provider,
        'fallbackProvider', authority.fallback_provider,
        'conflictPolicy', authority.conflict_policy
      ) order by authority.resource_type, authority.field_name)
      from public.provider_field_authority authority
    ), '[]'::jsonb),
    'openIdentityConflicts', (
      select count(*)
      from public.provider_identity_conflicts conflict
      where conflict.status = 'open'
    ),
    'runningWorkers', (
      select count(*)
      from public.provider_sync_runs run
      where run.status = 'running'
    ),
    'lastSyncAt', (
      select max(coalesce(run.finished_at, run.started_at))
      from public.provider_sync_runs run
    ),
    'lastError', (
      select run.error_message
      from public.provider_sync_runs run
      where run.status = 'failed'
      order by coalesce(run.finished_at, run.started_at) desc
      limit 1
    )
  );
end;
$function$;

alter table public.canonical_football_entities enable row level security;
alter table public.provider_entity_mappings enable row level security;
alter table public.provider_identity_conflicts enable row level security;
alter table public.provider_quota_policies enable row level security;
alter table public.provider_field_authority enable row level security;
alter table public.provider_daily_quota_usage enable row level security;
alter table public.provider_request_ledger enable row level security;
alter table public.provider_response_cache enable row level security;

revoke all on public.canonical_football_entities
from public, anon, authenticated;
revoke all on public.provider_entity_mappings
from public, anon, authenticated;
revoke all on public.provider_identity_conflicts
from public, anon, authenticated;
revoke all on public.provider_quota_policies
from public, anon, authenticated;
revoke all on public.provider_field_authority
from public, anon, authenticated;
revoke all on public.provider_daily_quota_usage
from public, anon, authenticated;
revoke all on public.provider_request_ledger
from public, anon, authenticated;
revoke all on public.provider_response_cache
from public, anon, authenticated;

revoke all on function public.claim_provider_request_budget_v1(text,text,text,text,uuid)
from public, anon, authenticated;
revoke all on function public.ensure_provider_entity_mapping_v1(text,text,text,text,jsonb)
from public, anon, authenticated;
revoke all on function public.canonicalize_athlete_provider_identity_v1()
from public, anon, authenticated;
revoke all on function public.canonicalize_fixture_provider_identity_v1()
from public, anon, authenticated;
revoke all on function public.finish_provider_request_v1(uuid,boolean,integer,integer,integer,text)
from public, anon, authenticated;
revoke all on function public.claim_provider_request_budget_v2(text,text,text,text,uuid,text,integer,text,jsonb)
from public, anon, authenticated;
revoke all on function public.record_provider_cache_hit_v1(text,text,text,text,uuid,text,integer,text,jsonb)
from public, anon, authenticated;
revoke all on function public.read_provider_response_cache_v1(text,text,text)
from public, anon, authenticated;
revoke all on function public.write_provider_response_cache_v1(text,text,text,jsonb,integer,text,text)
from public, anon, authenticated;
revoke all on function public.get_provider_quota_status_v1()
from public, anon, authenticated;
revoke all on function public.get_multi_provider_diagnostics_v1()
from public, anon, authenticated;
revoke all on function public.get_provider_cost_metrics_v1(date)
from public, anon, authenticated;
revoke all on function public.get_league_provider_budget_center_v1(uuid)
from public, anon;

grant execute on function public.claim_provider_request_budget_v1(text,text,text,text,uuid)
to service_role;
grant execute on function public.ensure_provider_entity_mapping_v1(text,text,text,text,jsonb)
to service_role;
grant execute on function public.finish_provider_request_v1(uuid,boolean,integer,integer,integer,text)
to service_role;
grant execute on function public.claim_provider_request_budget_v2(text,text,text,text,uuid,text,integer,text,jsonb)
to service_role;
grant execute on function public.record_provider_cache_hit_v1(text,text,text,text,uuid,text,integer,text,jsonb)
to service_role;
grant execute on function public.read_provider_response_cache_v1(text,text,text)
to service_role;
grant execute on function public.write_provider_response_cache_v1(text,text,text,jsonb,integer,text,text)
to service_role;
grant execute on function public.get_provider_quota_status_v1()
to service_role;
grant execute on function public.get_multi_provider_diagnostics_v1()
to service_role;
grant execute on function public.get_provider_cost_metrics_v1(date)
to service_role;
grant execute on function public.get_league_provider_budget_center_v1(uuid)
to authenticated;

comment on table public.canonical_football_entities is
  'Identità LEGHEVO stabili e indipendenti dai provider esterni.';
comment on table public.provider_entity_mappings is
  'Collegamenti verificabili tra identità LEGHEVO e ID esterni.';
comment on table public.provider_response_cache is
  'Cache server-side autorevole consultata prima di consumare quota provider.';
comment on table public.provider_request_ledger is
  'Audit append-only delle richieste provider, incluse quelle rifiutate per quota.';

do $postflight$
declare
  v_diagnostics jsonb := public.get_multi_provider_diagnostics_v1();
  v_check record;
begin
  for v_check in
    select item.key, item.value
    from jsonb_each(v_diagnostics) item
    where jsonb_typeof(item.value) = 'boolean'
  loop
    if v_check.value <> 'true'::jsonb then
      raise exception
        'Postflight multi-provider non superato: controllo % = %.',
        v_check.key,
        v_check.value;
    end if;
  end loop;
end;
$postflight$;

commit;
