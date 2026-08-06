-- LEGHEVO v0.62.14
-- Staging isolato e pubblicazione atomica dei dati provider.
-- Eseguire dopo database/117_provider_delivery_completeness_safety.sql.

begin;

-- Preflight esplicito: nessuna dipendenza viene presunta.
do $preflight$
declare
  v_missing text[] := array[]::text[];
  v_required_columns text;
  v_active_run boolean := false;
begin
  if to_regprocedure('public.get_provider_delivery_completeness_integrity_v1()') is null then
    v_missing := array_append(v_missing, 'function public.get_provider_delivery_completeness_integrity_v1()');
  end if;
  if to_regprocedure('public.assert_provider_sync_worker_lease_v1(uuid,uuid)') is null then
    v_missing := array_append(v_missing, 'function public.assert_provider_sync_worker_lease_v1(uuid,uuid)');
  end if;
  if to_regprocedure('public.validate_provider_sync_write_contract_v1(text,jsonb)') is null then
    v_missing := array_append(v_missing, 'function public.validate_provider_sync_write_contract_v1(text,jsonb)');
  end if;
  if to_regprocedure('public.finish_provider_sync_run_guarded_v3(uuid,text,integer,text,bigint,uuid)') is null then
    v_missing := array_append(v_missing, 'function public.finish_provider_sync_run_guarded_v3(uuid,text,integer,text,bigint,uuid)');
  end if;
  if to_regprocedure('public.provider_recovery_retry_policy_v1(text,integer,text)') is null then
    v_missing := array_append(v_missing, 'function public.provider_recovery_retry_policy_v1(text,integer,text)');
  end if;
  if to_regprocedure('public.is_league_admin(uuid)') is null then
    v_missing := array_append(v_missing, 'function public.is_league_admin(uuid)');
  end if;
  if to_regprocedure('gen_random_uuid()') is null then
    v_missing := array_append(v_missing, 'function gen_random_uuid()');
  end if;
  if to_regtype('public.league_mode') is null then
    v_missing := array_append(v_missing, 'type public.league_mode');
  end if;

  if to_regclass('public.provider_sync_runs') is null then
    v_missing := array_append(v_missing, 'table public.provider_sync_runs');
  end if;
  if to_regclass('public.provider_sync_worker_leases') is null then
    v_missing := array_append(v_missing, 'table public.provider_sync_worker_leases');
  end if;
  if to_regclass('public.provider_sync_delivery_certificates') is null then
    v_missing := array_append(v_missing, 'table public.provider_sync_delivery_certificates');
  end if;

  if to_regclass('public.provider_sync_delivery_units') is null then
    v_missing := array_append(v_missing, 'table public.provider_sync_delivery_units');
  end if;
  if to_regclass('public.provider_recovery_requests') is null then
    v_missing := array_append(v_missing, 'table public.provider_recovery_requests');
  end if;
  if to_regclass('public.leagues') is null then
    v_missing := array_append(v_missing, 'table public.leagues');
  end if;
  if to_regclass('public.athletes') is null then
    v_missing := array_append(v_missing, 'table public.athletes');
  end if;
  if to_regclass('public.athlete_roles') is null then
    v_missing := array_append(v_missing, 'table public.athlete_roles');
  end if;
  if to_regclass('public.matchdays') is null then
    v_missing := array_append(v_missing, 'table public.matchdays');
  end if;
  if to_regclass('public.provider_fixtures') is null then
    v_missing := array_append(v_missing, 'table public.provider_fixtures');
  end if;
  if to_regclass('public.player_match_scores') is null then
    v_missing := array_append(v_missing, 'table public.player_match_scores');
  end if;

  for v_required_columns in
    select required.table_name || '.' || required.column_name
    from (values
      ('provider_sync_runs','id'),('provider_sync_runs','provider'),
      ('provider_sync_runs','sync_type'),('provider_sync_runs','status'),
      ('provider_sync_runs','revision'),('provider_sync_runs','records_processed'),
      ('provider_sync_runs','error_message'),
      ('provider_sync_worker_leases','run_id'),
      ('provider_sync_worker_leases','recovery_request_id'),
      ('provider_sync_worker_leases','league_id'),
      ('provider_sync_worker_leases','lease_token'),
      ('provider_sync_worker_leases','lease_epoch'),
      ('provider_sync_worker_leases','status'),
      ('provider_sync_worker_leases','lease_expires_at'),
      ('provider_sync_delivery_certificates','id'),
      ('provider_sync_delivery_certificates','run_id'),
      ('provider_sync_delivery_certificates','status'),
      ('provider_sync_delivery_certificates','expected_unit_count'),
      ('provider_sync_delivery_certificates','observed_unit_count'),
      ('provider_sync_delivery_certificates','observed_record_count'),
      ('provider_sync_delivery_certificates','unique_entity_count'),
      ('provider_sync_delivery_certificates','revision'),
      ('athletes','id'),('athletes','provider'),('athletes','provider_player_id'),
      ('athletes','first_name'),('athletes','last_name'),('athletes','club_name'),
      ('athletes','provider_team_id'),('athletes','photo_url'),
      ('athletes','position_code'),('athletes','active'),('athletes','payload'),
      ('athletes','updated_at'),
      ('athlete_roles','athlete_id'),('athlete_roles','mode'),('athlete_roles','role_code'),
      ('matchdays','id'),('matchdays','competition_code'),('matchdays','season'),
      ('matchdays','number'),('matchdays','starts_at'),('matchdays','locks_at'),
      ('matchdays','ends_at'),
      ('provider_fixtures','provider'),('provider_fixtures','provider_fixture_id'),
      ('provider_fixtures','competition_code'),('provider_fixtures','season'),
      ('provider_fixtures','matchday_id'),('provider_fixtures','kickoff_at'),
      ('provider_fixtures','status'),('provider_fixtures','home_team_provider_id'),
      ('provider_fixtures','home_team_name'),('provider_fixtures','away_team_provider_id'),
      ('provider_fixtures','away_team_name'),('provider_fixtures','home_goals'),
      ('provider_fixtures','away_goals'),('provider_fixtures','payload'),
      ('provider_fixtures','updated_at'),
      ('player_match_scores','athlete_id'),('player_match_scores','matchday_id'),
      ('player_match_scores','provider_fixture_id'),
      ('player_match_scores','provider_rating'),('player_match_scores','fantasy_score'),
      ('player_match_scores','bonuses'),('player_match_scores','maluses'),
      ('player_match_scores','raw_statistics'),
      ('player_match_scores','provider_payload'),('player_match_scores','is_final'),
      ('player_match_scores','updated_at')
    ) as required(table_name,column_name)
    where not exists (
      select 1
      from information_schema.columns column_row
      where column_row.table_schema = 'public'
        and column_row.table_name = required.table_name
        and column_row.column_name = required.column_name
    )
  loop
    v_missing := array_append(v_missing, 'column public.' || v_required_columns);
  end loop;

  if to_regclass('public.provider_sync_runs') is not null
    and exists (
      select 1
      from information_schema.columns column_row
      where column_row.table_schema = 'public'
        and column_row.table_name = 'provider_sync_runs'
        and column_row.column_name = 'status'
    ) then
    execute
      'select exists (select 1 from public.provider_sync_runs where status = ''running'')'
    into v_active_run;
    if v_active_run then
      v_missing := array_append(
        v_missing,
        'operational condition: no provider_sync_runs row may be running during installation'
      );
    end if;
  end if;

  if to_regprocedure('auth.uid()') is null then
    v_missing := array_append(v_missing, 'function auth.uid()');
  end if;
  if to_regprocedure('pg_catalog.md5(text)') is null then
    v_missing := array_append(v_missing, 'function pg_catalog.md5(text)');
  end if;
  if to_regprocedure('pg_catalog.hashtext(text)') is null then
    v_missing := array_append(v_missing, 'function pg_catalog.hashtext(text)');
  end if;
  if to_regprocedure('pg_catalog.pg_advisory_xact_lock(bigint)') is null then
    v_missing := array_append(
      v_missing,
      'function pg_catalog.pg_advisory_xact_lock(bigint)'
    );
  end if;
  if to_regprocedure('public.get_league_provider_sync_health_v12(uuid)') is null then
    v_missing := array_append(
      v_missing,
      'function public.get_league_provider_sync_health_v12(uuid)'
    );
  end if;
  if to_regclass('public.athletes_provider_provider_player_id_key') is null then
    v_missing := array_append(
      v_missing,
      'unique constraint public.athletes(provider,provider_player_id)'
    );
  end if;
  if to_regclass('public.athlete_roles_pkey') is null then
    v_missing := array_append(v_missing, 'primary key public.athlete_roles');
  end if;
  if to_regclass('public.matchdays_competition_code_season_number_key') is null then
    v_missing := array_append(
      v_missing,
      'unique constraint public.matchdays(competition_code,season,number)'
    );
  end if;
  if to_regclass('public.provider_fixtures_provider_provider_fixture_id_key') is null then
    v_missing := array_append(
      v_missing,
      'unique constraint public.provider_fixtures(provider,provider_fixture_id)'
    );
  end if;
  if to_regclass('public.player_match_scores_athlete_id_matchday_id_key') is null then
    v_missing := array_append(
      v_missing,
      'unique constraint public.player_match_scores(athlete_id,matchday_id)'
    );
  end if;

  if coalesce(array_length(v_missing, 1), 0) > 0 then
    raise exception
      'Preflight v0.62.14 non superato. Dipendenze mancanti: %',
      array_to_string(v_missing, '; ');
  end if;
end;
$preflight$;

create table if not exists public.provider_sync_publications (
  id uuid primary key default gen_random_uuid(),
  run_id uuid not null unique
    references public.provider_sync_runs(id) on delete restrict,
  recovery_request_id uuid
    references public.provider_recovery_requests(id) on delete set null,
  league_id uuid references public.leagues(id) on delete set null,
  provider text not null,
  sync_type text not null,
  status text not null default 'collecting',
  staged_row_count integer not null default 0,
  staged_primary_record_count integer not null default 0,
  published_primary_record_count integer not null default 0,
  summary text not null default 'Dati provider isolati nello staging.',
  run_revision bigint not null,
  lease_epoch bigint not null,
  revision bigint not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  published_at timestamptz,
  discarded_at timestamptz,
  constraint provider_sync_publications_sync_type_check check (
    sync_type in ('sync-season-players','sync-fixtures','sync-fixture-players')
  ),
  constraint provider_sync_publications_status_check check (
    status in ('collecting','published','discarded')
  ),
  constraint provider_sync_publications_counts_check check (
    staged_row_count between 0 and 3000000
    and staged_primary_record_count between 0 and 1000000
    and published_primary_record_count between 0 and 1000000
  ),
  constraint provider_sync_publications_summary_check check (
    length(summary) between 1 and 500 and summary !~ E'[\r\n]'
  ),
  constraint provider_sync_publications_revision_check check (
    run_revision > 0 and lease_epoch > 0 and revision > 0
  ),
  constraint provider_sync_publications_terminal_check check (
    (status = 'collecting' and published_at is null and discarded_at is null)
    or (status = 'published' and published_at is not null and discarded_at is null)
    or (status = 'discarded' and published_at is null and discarded_at is not null)
  )
);

create table if not exists public.provider_sync_stage_athletes (
  publication_id uuid not null
    references public.provider_sync_publications(id) on delete cascade,
  athlete_id uuid not null,
  provider text not null,
  provider_player_id text not null,
  first_name text,
  last_name text not null,
  club_name text not null,
  provider_team_id text,
  photo_url text,
  position_code text,
  active boolean not null,
  payload jsonb not null,
  source_updated_at timestamptz not null,
  primary key (publication_id, provider, provider_player_id),
  unique (publication_id, athlete_id)
);

create table if not exists public.provider_sync_stage_roles (
  publication_id uuid not null
    references public.provider_sync_publications(id) on delete cascade,
  athlete_id uuid not null,
  mode public.league_mode not null,
  role_code text not null,
  primary key (publication_id, athlete_id, mode, role_code)
);

create table if not exists public.provider_sync_stage_matchdays (
  publication_id uuid not null
    references public.provider_sync_publications(id) on delete cascade,
  matchday_id uuid not null,
  competition_code text not null,
  season text not null,
  number smallint not null,
  starts_at timestamptz not null,
  locks_at timestamptz not null,
  ends_at timestamptz,
  primary key (publication_id, competition_code, season, number),
  unique (publication_id, matchday_id)
);

create table if not exists public.provider_sync_stage_fixtures (
  publication_id uuid not null
    references public.provider_sync_publications(id) on delete cascade,
  provider text not null,
  provider_fixture_id text not null,
  competition_code text not null,
  season text not null,
  matchday_id uuid,
  kickoff_at timestamptz not null,
  status text not null,
  home_team_provider_id text not null,
  home_team_name text not null,
  away_team_provider_id text not null,
  away_team_name text not null,
  home_goals smallint,
  away_goals smallint,
  payload jsonb not null,
  source_updated_at timestamptz not null,
  primary key (publication_id, provider, provider_fixture_id)
);

create table if not exists public.provider_sync_stage_scores (
  publication_id uuid not null
    references public.provider_sync_publications(id) on delete cascade,
  athlete_id uuid not null,
  matchday_id uuid not null,
  provider_fixture_id text,
  provider_rating numeric(4,2),
  fantasy_score numeric(5,2),
  bonuses jsonb not null,
  maluses jsonb not null,
  raw_statistics jsonb not null,
  provider_payload jsonb not null,
  is_final boolean not null,
  source_updated_at timestamptz not null,
  primary key (publication_id, athlete_id, matchday_id)
);

create table if not exists public.provider_sync_publication_events (
  id uuid primary key default gen_random_uuid(),
  publication_id uuid not null
    references public.provider_sync_publications(id) on delete restrict,
  run_id uuid not null references public.provider_sync_runs(id) on delete restrict,
  league_id uuid references public.leagues(id) on delete set null,
  event_type text not null check (
    event_type in ('collecting','published','discarded')
  ),
  revision bigint not null check (revision > 0),
  primary_record_count integer not null check (
    primary_record_count between 0 and 1000000
  ),
  event_fingerprint text not null check (
    event_fingerprint ~ '^[0-9a-f]{32}$'
  ),
  created_at timestamptz not null default now(),
  unique (publication_id, revision)
);

create index if not exists provider_sync_publications_league_idx
  on public.provider_sync_publications (league_id, updated_at desc);
create index if not exists provider_sync_publications_status_idx
  on public.provider_sync_publications (status, updated_at desc);
create index if not exists provider_sync_stage_athletes_run_idx
  on public.provider_sync_stage_athletes (publication_id, athlete_id);
create index if not exists provider_sync_stage_fixtures_matchday_idx
  on public.provider_sync_stage_fixtures (publication_id, matchday_id);
create index if not exists provider_sync_stage_scores_fixture_idx
  on public.provider_sync_stage_scores (publication_id, provider_fixture_id);
create index if not exists provider_sync_publication_events_league_idx
  on public.provider_sync_publication_events (league_id, created_at desc);

alter table public.provider_sync_publications enable row level security;
alter table public.provider_sync_publications replica identity full;
alter table public.provider_sync_stage_athletes enable row level security;
alter table public.provider_sync_stage_roles enable row level security;
alter table public.provider_sync_stage_matchdays enable row level security;
alter table public.provider_sync_stage_fixtures enable row level security;
alter table public.provider_sync_stage_scores enable row level security;
alter table public.provider_sync_publication_events enable row level security;
alter table public.provider_sync_publication_events replica identity full;

revoke all on table public.provider_sync_publications
from public, anon, authenticated;
revoke all on table public.provider_sync_stage_athletes
from public, anon, authenticated;
revoke all on table public.provider_sync_stage_roles
from public, anon, authenticated;
revoke all on table public.provider_sync_stage_matchdays
from public, anon, authenticated;
revoke all on table public.provider_sync_stage_fixtures
from public, anon, authenticated;
revoke all on table public.provider_sync_stage_scores
from public, anon, authenticated;
revoke all on table public.provider_sync_publication_events
from public, anon, authenticated;
-- Supabase applica al service_role privilegi predefiniti sulle nuove tabelle.
-- La revoca esplicita rimuove tali ACL prima del grant minimo necessario.
revoke all on table public.provider_sync_publication_events
from service_role;

grant select on table public.provider_sync_publications to authenticated;
grant select on table public.provider_sync_publication_events to authenticated;
grant select, insert, update on table public.provider_sync_publications to service_role;
grant select, insert, update, delete on table public.provider_sync_stage_athletes to service_role;
grant select, insert, update, delete on table public.provider_sync_stage_roles to service_role;
grant select, insert, update, delete on table public.provider_sync_stage_matchdays to service_role;
grant select, insert, update, delete on table public.provider_sync_stage_fixtures to service_role;
grant select, insert, update, delete on table public.provider_sync_stage_scores to service_role;
grant select, insert on table public.provider_sync_publication_events to service_role;

drop policy if exists provider_sync_publications_read_directors
on public.provider_sync_publications;
create policy provider_sync_publications_read_directors
on public.provider_sync_publications
for select to authenticated
using (
  (
    league_id is not null
    and exists (
      select 1
      from public.leagues league_row
      where league_row.id = provider_sync_publications.league_id
        and (
          league_row.owner_id = auth.uid()
          or public.is_league_admin(league_row.id)
        )
    )
  )
  or (
    league_id is null
    and exists (
      select 1
      from public.leagues league_row
      where league_row.owner_id = auth.uid()
        or public.is_league_admin(league_row.id)
    )
  )
);

drop policy if exists provider_sync_publication_events_read_directors
on public.provider_sync_publication_events;
create policy provider_sync_publication_events_read_directors
on public.provider_sync_publication_events
for select to authenticated
using (
  (
    league_id is not null
    and exists (
      select 1
      from public.leagues league_row
      where league_row.id = provider_sync_publication_events.league_id
        and (
          league_row.owner_id = auth.uid()
          or public.is_league_admin(league_row.id)
        )
    )
  )
  or (
    league_id is null
    and exists (
      select 1
      from public.leagues league_row
      where league_row.owner_id = auth.uid()
        or public.is_league_admin(league_row.id)
    )
  )
);

create or replace function public.touch_provider_sync_publication_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.status is distinct from old.status
    or new.staged_row_count is distinct from old.staged_row_count
    or new.staged_primary_record_count is distinct from old.staged_primary_record_count
    or new.published_primary_record_count is distinct from old.published_primary_record_count
    or new.summary is distinct from old.summary then
    new.revision := old.revision + 1;
    new.updated_at := now();
  end if;

  if new.status = 'published' and old.status <> 'published' then
    new.published_at := now();
    new.discarded_at := null;
  elsif new.status = 'discarded' and old.status <> 'discarded' then
    new.discarded_at := now();
    new.published_at := null;
  end if;

  return new;
end;
$$;

revoke all on function public.touch_provider_sync_publication_v1()
from public, anon, authenticated;

drop trigger if exists provider_sync_publications_touch
on public.provider_sync_publications;
create trigger provider_sync_publications_touch
before update on public.provider_sync_publications
for each row execute function public.touch_provider_sync_publication_v1();

create or replace function public.write_provider_sync_publication_event_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'UPDATE'
    and new.revision = old.revision then
    return new;
  end if;

  insert into public.provider_sync_publication_events (
    publication_id,
    run_id,
    league_id,
    event_type,
    revision,
    primary_record_count,
    event_fingerprint,
    created_at
  ) values (
    new.id,
    new.run_id,
    new.league_id,
    new.status,
    new.revision,
    case
      when new.status = 'published' then new.published_primary_record_count
      else new.staged_primary_record_count
    end,
    pg_catalog.md5(
      new.id::text || E'\n'
      || new.run_id::text || E'\n'
      || new.status || E'\n'
      || new.revision::text || E'\n'
      || new.staged_primary_record_count::text || E'\n'
      || new.published_primary_record_count::text || E'\n'
      || new.summary
    ),
    new.updated_at
  )
  on conflict (publication_id, revision) do nothing;

  return new;
end;
$$;

revoke all on function public.write_provider_sync_publication_event_v1()
from public, anon, authenticated;

drop trigger if exists provider_sync_publication_event_writer
on public.provider_sync_publications;
create trigger provider_sync_publication_event_writer
after insert or update on public.provider_sync_publications
for each row execute function public.write_provider_sync_publication_event_v1();

create or replace function public.prevent_provider_sync_publication_event_mutation_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  raise exception 'Lo storico delle pubblicazioni provider è immutabile.';
end;
$$;

revoke all on function public.prevent_provider_sync_publication_event_mutation_v1()
from public, anon, authenticated;

drop trigger if exists provider_sync_publication_events_immutable
on public.provider_sync_publication_events;
create trigger provider_sync_publication_events_immutable
before update or delete on public.provider_sync_publication_events
for each row execute function public.prevent_provider_sync_publication_event_mutation_v1();

alter table public.provider_sync_publication_events
enable always trigger provider_sync_publication_events_immutable;

create or replace function public.ensure_provider_sync_publication_v1(
  p_run_id uuid,
  p_lease_token uuid
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_run public.provider_sync_runs%rowtype;
  v_lease public.provider_sync_worker_leases%rowtype;
  v_publication public.provider_sync_publications%rowtype;
begin
  perform public.assert_provider_sync_worker_lease_v1(
    p_run_id,
    p_lease_token
  );

  select run_row.*
  into v_run
  from public.provider_sync_runs run_row
  where run_row.id = p_run_id
  for update;

  if not found then
    raise exception 'Run provider non trovato durante la creazione dello staging.';
  end if;
  if v_run.status <> 'running' then
    raise exception 'Staging provider rifiutato: run nello stato %.', v_run.status;
  end if;

  select lease_row.*
  into v_lease
  from public.provider_sync_worker_leases lease_row
  where lease_row.run_id = p_run_id
    and lease_row.lease_token = p_lease_token
  for update;

  if not found or v_lease.status <> 'active'
    or v_lease.lease_expires_at <= now() then
    raise exception 'Staging provider rifiutato: lease worker non attiva.';
  end if;

  insert into public.provider_sync_publications (
    run_id,
    recovery_request_id,
    league_id,
    provider,
    sync_type,
    run_revision,
    lease_epoch
  ) values (
    v_run.id,
    v_lease.recovery_request_id,
    v_lease.league_id,
    v_run.provider,
    v_run.sync_type,
    v_run.revision,
    v_lease.lease_epoch
  )
  on conflict (run_id) do nothing;

  select publication_row.*
  into v_publication
  from public.provider_sync_publications publication_row
  where publication_row.run_id = p_run_id
  for update;

  if not found then
    raise exception 'Manifest di pubblicazione provider non creato.';
  end if;
  if v_publication.status <> 'collecting' then
    raise exception
      'Staging provider rifiutato: pubblicazione nello stato %.',
      v_publication.status;
  end if;
  if v_publication.lease_epoch <> v_lease.lease_epoch then
    raise exception 'Staging provider rifiutato: epoca lease non coerente.';
  end if;

  return v_publication.id;
end;
$$;

revoke all on function public.ensure_provider_sync_publication_v1(uuid,uuid)
from public, anon, authenticated;
grant execute on function public.ensure_provider_sync_publication_v1(uuid,uuid)
to service_role;

create or replace function public.refresh_provider_sync_publication_counts_v1(
  p_publication_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_publication public.provider_sync_publications%rowtype;
  v_athletes integer;
  v_roles integer;
  v_matchdays integer;
  v_fixtures integer;
  v_scores integer;
  v_primary integer;
begin
  select publication_row.*
  into v_publication
  from public.provider_sync_publications publication_row
  where publication_row.id = p_publication_id
  for update;

  if not found then
    raise exception 'Manifest di pubblicazione provider non trovato.';
  end if;

  select count(*)::integer into v_athletes
  from public.provider_sync_stage_athletes row_item
  where row_item.publication_id = p_publication_id;
  select count(*)::integer into v_roles
  from public.provider_sync_stage_roles row_item
  where row_item.publication_id = p_publication_id;
  select count(*)::integer into v_matchdays
  from public.provider_sync_stage_matchdays row_item
  where row_item.publication_id = p_publication_id;
  select count(*)::integer into v_fixtures
  from public.provider_sync_stage_fixtures row_item
  where row_item.publication_id = p_publication_id;
  select count(*)::integer into v_scores
  from public.provider_sync_stage_scores row_item
  where row_item.publication_id = p_publication_id;

  v_primary := case v_publication.sync_type
    when 'sync-season-players' then v_athletes
    when 'sync-fixtures' then v_fixtures
    when 'sync-fixture-players' then v_scores
    else 0
  end;

  update public.provider_sync_publications publication_row
  set
    staged_row_count = v_athletes + v_roles + v_matchdays + v_fixtures + v_scores,
    staged_primary_record_count = v_primary,
    summary = format(
      'Staging provider isolato: %s record primari, %s righe normalizzate.',
      v_primary,
      v_athletes + v_roles + v_matchdays + v_fixtures + v_scores
    )
  where publication_row.id = p_publication_id
  returning * into v_publication;

  return jsonb_build_object(
    'publicationId', v_publication.id,
    'stagedRowCount', v_publication.staged_row_count,
    'stagedPrimaryRecordCount', v_publication.staged_primary_record_count,
    'revision', v_publication.revision
  );
end;
$$;

revoke all on function public.refresh_provider_sync_publication_counts_v1(uuid)
from public, anon, authenticated;
grant execute on function public.refresh_provider_sync_publication_counts_v1(uuid)
to service_role;

create or replace function public.stage_provider_sync_write_guarded_v1(
  p_run_id uuid,
  p_lease_token uuid,
  p_operation text,
  p_payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_operation text := lower(trim(coalesce(p_operation, '')));
  v_contract jsonb;
  v_publication_id uuid;
  v_result jsonb;
  v_counts jsonb;
begin
  perform public.assert_provider_sync_worker_lease_v1(
    p_run_id,
    p_lease_token
  );
  v_contract := public.validate_provider_sync_write_contract_v1(
    v_operation,
    p_payload
  );
  v_publication_id := public.ensure_provider_sync_publication_v1(
    p_run_id,
    p_lease_token
  );

  if v_operation = 'upsert-athletes' then
    with incoming as (
      select item.*
      from jsonb_to_recordset(p_payload) as item(
        provider text,
        provider_player_id text,
        first_name text,
        last_name text,
        club_name text,
        provider_team_id text,
        photo_url text,
        position_code text,
        active boolean,
        payload jsonb,
        updated_at timestamptz
      )
    ), resolved as (
      select
        coalesce(stage_row.athlete_id, athlete_row.id, gen_random_uuid()) as athlete_id,
        incoming.*
      from incoming
      left join public.provider_sync_stage_athletes stage_row
        on stage_row.publication_id = v_publication_id
       and stage_row.provider = incoming.provider
       and stage_row.provider_player_id = incoming.provider_player_id
      left join public.athletes athlete_row
        on athlete_row.provider = incoming.provider
       and athlete_row.provider_player_id = incoming.provider_player_id
    ), upserted as (
      insert into public.provider_sync_stage_athletes (
        publication_id, athlete_id, provider, provider_player_id,
        first_name, last_name, club_name, provider_team_id, photo_url,
        position_code, active, payload, source_updated_at
      )
      select
        v_publication_id, resolved.athlete_id, resolved.provider,
        resolved.provider_player_id, resolved.first_name, resolved.last_name,
        resolved.club_name, resolved.provider_team_id, resolved.photo_url,
        resolved.position_code, coalesce(resolved.active, true),
        coalesce(resolved.payload, '{}'::jsonb),
        coalesce(resolved.updated_at, now())
      from resolved
      on conflict (publication_id, provider, provider_player_id) do update
      set
        first_name = excluded.first_name,
        last_name = excluded.last_name,
        club_name = excluded.club_name,
        provider_team_id = excluded.provider_team_id,
        photo_url = excluded.photo_url,
        position_code = excluded.position_code,
        active = excluded.active,
        payload = excluded.payload,
        source_updated_at = excluded.source_updated_at
      returning athlete_id as id, provider_player_id, position_code
    )
    select jsonb_build_object(
      'count', count(*),
      'records', coalesce(jsonb_agg(to_jsonb(upserted)), '[]'::jsonb)
    )
    into v_result
    from upserted;

  elsif v_operation = 'upsert-athlete-roles' then
    with upserted as (
      insert into public.provider_sync_stage_roles (
        publication_id, athlete_id, mode, role_code
      )
      select
        v_publication_id,
        item.athlete_id,
        item.mode::public.league_mode,
        item.role_code
      from jsonb_to_recordset(p_payload) as item(
        athlete_id uuid,
        mode text,
        role_code text
      )
      on conflict (publication_id, athlete_id, mode, role_code) do nothing
      returning athlete_id
    )
    select jsonb_build_object('count', count(*))
    into v_result
    from upserted;

  elsif v_operation = 'upsert-matchday' then
    with incoming as (
      select item.*
      from jsonb_to_record(p_payload) as item(
        competition_code text,
        season text,
        number smallint,
        starts_at timestamptz,
        locks_at timestamptz,
        ends_at timestamptz
      )
    ), resolved as (
      select
        coalesce(stage_row.matchday_id, matchday_row.id, gen_random_uuid()) as matchday_id,
        incoming.*
      from incoming
      left join public.provider_sync_stage_matchdays stage_row
        on stage_row.publication_id = v_publication_id
       and stage_row.competition_code = incoming.competition_code
       and stage_row.season = incoming.season
       and stage_row.number = incoming.number
      left join public.matchdays matchday_row
        on matchday_row.competition_code = incoming.competition_code
       and matchday_row.season = incoming.season
       and matchday_row.number = incoming.number
    ), upserted as (
      insert into public.provider_sync_stage_matchdays (
        publication_id, matchday_id, competition_code, season, number,
        starts_at, locks_at, ends_at
      )
      select
        v_publication_id, resolved.matchday_id, resolved.competition_code,
        resolved.season, resolved.number, resolved.starts_at,
        resolved.locks_at, resolved.ends_at
      from resolved
      on conflict (publication_id, competition_code, season, number) do update
      set
        starts_at = excluded.starts_at,
        locks_at = excluded.locks_at,
        ends_at = excluded.ends_at
      returning matchday_id as id
    )
    select jsonb_build_object('record', to_jsonb(upserted))
    into v_result
    from upserted;

  elsif v_operation = 'upsert-provider-fixtures' then
    with upserted as (
      insert into public.provider_sync_stage_fixtures (
        publication_id, provider, provider_fixture_id, competition_code,
        season, matchday_id, kickoff_at, status, home_team_provider_id,
        home_team_name, away_team_provider_id, away_team_name, home_goals,
        away_goals, payload, source_updated_at
      )
      select
        v_publication_id, item.provider, item.provider_fixture_id,
        item.competition_code, item.season, item.matchday_id,
        item.kickoff_at, item.status, item.home_team_provider_id,
        item.home_team_name, item.away_team_provider_id,
        item.away_team_name, item.home_goals, item.away_goals,
        coalesce(item.payload, '{}'::jsonb), coalesce(item.updated_at, now())
      from jsonb_to_recordset(p_payload) as item(
        provider text,
        provider_fixture_id text,
        competition_code text,
        season text,
        matchday_id uuid,
        kickoff_at timestamptz,
        status text,
        home_team_provider_id text,
        home_team_name text,
        away_team_provider_id text,
        away_team_name text,
        home_goals smallint,
        away_goals smallint,
        payload jsonb,
        updated_at timestamptz
      )
      on conflict (publication_id, provider, provider_fixture_id) do update
      set
        competition_code = excluded.competition_code,
        season = excluded.season,
        matchday_id = excluded.matchday_id,
        kickoff_at = excluded.kickoff_at,
        status = excluded.status,
        home_team_provider_id = excluded.home_team_provider_id,
        home_team_name = excluded.home_team_name,
        away_team_provider_id = excluded.away_team_provider_id,
        away_team_name = excluded.away_team_name,
        home_goals = excluded.home_goals,
        away_goals = excluded.away_goals,
        payload = excluded.payload,
        source_updated_at = excluded.source_updated_at
      returning provider_fixture_id
    )
    select jsonb_build_object('count', count(*))
    into v_result
    from upserted;

  elsif v_operation = 'upsert-player-scores' then
    with upserted as (
      insert into public.provider_sync_stage_scores (
        publication_id, athlete_id, matchday_id, provider_fixture_id,
        provider_rating, fantasy_score, bonuses, maluses, raw_statistics,
        provider_payload, is_final, source_updated_at
      )
      select
        v_publication_id, item.athlete_id, item.matchday_id,
        item.provider_fixture_id, item.provider_rating, item.fantasy_score,
        coalesce(item.bonuses, '{}'::jsonb),
        coalesce(item.maluses, '{}'::jsonb),
        coalesce(item.raw_statistics, '{}'::jsonb),
        coalesce(item.provider_payload, '{}'::jsonb),
        coalesce(item.is_final, false), coalesce(item.updated_at, now())
      from jsonb_to_recordset(p_payload) as item(
        athlete_id uuid,
        matchday_id uuid,
        provider_fixture_id text,
        provider_rating numeric(4,2),
        fantasy_score numeric(5,2),
        bonuses jsonb,
        maluses jsonb,
        raw_statistics jsonb,
        provider_payload jsonb,
        is_final boolean,
        updated_at timestamptz
      )
      on conflict (publication_id, athlete_id, matchday_id) do update
      set
        provider_fixture_id = excluded.provider_fixture_id,
        provider_rating = excluded.provider_rating,
        fantasy_score = excluded.fantasy_score,
        bonuses = excluded.bonuses,
        maluses = excluded.maluses,
        raw_statistics = excluded.raw_statistics,
        provider_payload = excluded.provider_payload,
        is_final = excluded.is_final,
        source_updated_at = excluded.source_updated_at
      returning athlete_id
    )
    select jsonb_build_object('count', count(*))
    into v_result
    from upserted;
  else
    raise exception 'Operazione di staging provider non riconosciuta: %.', v_operation;
  end if;

  v_counts := public.refresh_provider_sync_publication_counts_v1(
    v_publication_id
  );

  return coalesce(v_result, jsonb_build_object('count', 0))
    || jsonb_build_object(
      'atomicStaging', true,
      'publicationId', v_publication_id,
      'contractVersion', v_contract ->> 'contractVersion',
      'stagedRowCount', (v_counts ->> 'stagedRowCount')::integer,
      'stagedPrimaryRecordCount',
        (v_counts ->> 'stagedPrimaryRecordCount')::integer
    );
end;
$$;

revoke all on function public.stage_provider_sync_write_guarded_v1(
  uuid,uuid,text,jsonb
)
from public, anon, authenticated;
grant execute on function public.stage_provider_sync_write_guarded_v1(
  uuid,uuid,text,jsonb
)
to service_role;

-- Compatibilità server-side: anche worker v0.62.11/v0.62.12 già attivi
-- vengono instradati nello staging e non possono più scrivere direttamente live.
create or replace function public.apply_provider_sync_write_guarded_v1(
  p_run_id uuid,
  p_lease_token uuid,
  p_operation text,
  p_payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  return public.stage_provider_sync_write_guarded_v1(
    p_run_id,
    p_lease_token,
    p_operation,
    p_payload
  );
end;
$$;

revoke all on function public.apply_provider_sync_write_guarded_v1(
  uuid,uuid,text,jsonb
)
from public, anon, authenticated;
grant execute on function public.apply_provider_sync_write_guarded_v1(
  uuid,uuid,text,jsonb
)
to service_role;

create or replace function public.apply_provider_sync_write_guarded_v2(
  p_run_id uuid,
  p_lease_token uuid,
  p_operation text,
  p_payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  return public.stage_provider_sync_write_guarded_v1(
    p_run_id,
    p_lease_token,
    p_operation,
    p_payload
  ) || jsonb_build_object('payloadContract', true);
end;
$$;

revoke all on function public.apply_provider_sync_write_guarded_v2(
  uuid,uuid,text,jsonb
)
from public, anon, authenticated;
grant execute on function public.apply_provider_sync_write_guarded_v2(
  uuid,uuid,text,jsonb
)
to service_role;

create or replace function public.guard_provider_sync_atomic_completion_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_publication_status text;
begin
  if new.status <> 'completed'
    or new.status is not distinct from old.status then
    return new;
  end if;

  select publication_row.status
  into v_publication_status
  from public.provider_sync_publications publication_row
  where publication_row.run_id = new.id;

  if not found then
    raise exception
      'Chiusura provider rifiutata [publication.missing]: pubblicazione atomica assente.';
  end if;
  if v_publication_status <> 'published' then
    raise exception
      'Chiusura provider rifiutata [publication.not_published]: stato %.',
      v_publication_status;
  end if;

  return new;
end;
$$;

revoke all on function public.guard_provider_sync_atomic_completion_v1()
from public, anon, authenticated;

drop trigger if exists provider_sync_atomic_completion_guard
on public.provider_sync_runs;
create trigger provider_sync_atomic_completion_guard
before update of status on public.provider_sync_runs
for each row execute function public.guard_provider_sync_atomic_completion_v1();

create or replace function public.discard_provider_sync_staging_on_failure_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_publication public.provider_sync_publications%rowtype;
begin
  if new.status <> 'failed'
    or new.status is not distinct from old.status then
    return new;
  end if;

  select publication_row.*
  into v_publication
  from public.provider_sync_publications publication_row
  where publication_row.run_id = new.id
    and publication_row.status = 'collecting'
  for update;

  if not found then
    return new;
  end if;

  delete from public.provider_sync_stage_scores row_item
  where row_item.publication_id = v_publication.id;
  delete from public.provider_sync_stage_fixtures row_item
  where row_item.publication_id = v_publication.id;
  delete from public.provider_sync_stage_roles row_item
  where row_item.publication_id = v_publication.id;
  delete from public.provider_sync_stage_matchdays row_item
  where row_item.publication_id = v_publication.id;
  delete from public.provider_sync_stage_athletes row_item
  where row_item.publication_id = v_publication.id;

  update public.provider_sync_publications publication_row
  set
    status = 'discarded',
    summary = left(
      'Staging provider scartato automaticamente dopo il fallimento del run: '
      || regexp_replace(
        coalesce(nullif(trim(new.error_message), ''), 'errore provider non specificato'),
        E'[\r\n]+', ' ', 'g'
      ),
      500
    )
  where publication_row.id = v_publication.id;

  return new;
end;
$$;

revoke all on function public.discard_provider_sync_staging_on_failure_v1()
from public, anon, authenticated;

drop trigger if exists provider_sync_staging_failure_discard
on public.provider_sync_runs;
create trigger provider_sync_staging_failure_discard
after update of status on public.provider_sync_runs
for each row execute function public.discard_provider_sync_staging_on_failure_v1();

create or replace function public.certify_provider_sync_delivery_before_publication_v1(
  p_run_id uuid,
  p_records_processed integer
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_certificate public.provider_sync_delivery_certificates%rowtype;
  v_unit_count integer;
  v_min_unit integer;
  v_max_unit integer;
begin
  select certificate_row.*
  into v_certificate
  from public.provider_sync_delivery_certificates certificate_row
  where certificate_row.run_id = p_run_id
  for update;

  if not found then
    raise exception 'Consegna provider incompleta [delivery.certificate_missing].';
  end if;
  if v_certificate.status = 'certified' then
    if v_certificate.observed_record_count = coalesce(p_records_processed, 0) then
      return jsonb_build_object(
        'deliveryCertificateId', v_certificate.id,
        'deliveryRevision', v_certificate.revision,
        'deliveryStatus', v_certificate.status
      );
    end if;
    raise exception 'Consegna provider già certificata con un conteggio differente.';
  end if;
  if v_certificate.status <> 'collecting' then
    raise exception 'Consegna provider non certificabile nello stato %.', v_certificate.status;
  end if;

  select count(*)::integer, min(unit_row.unit_no), max(unit_row.unit_no)
  into v_unit_count, v_min_unit, v_max_unit
  from public.provider_sync_delivery_units unit_row
  where unit_row.certificate_id = v_certificate.id;

  if v_certificate.expected_unit_count is null
    or v_certificate.observed_unit_count <> v_certificate.expected_unit_count
    or v_unit_count <> v_certificate.expected_unit_count
    or v_min_unit <> 1
    or v_max_unit <> v_certificate.expected_unit_count then
    raise exception
      'Consegna provider incompleta [delivery.units_missing]: attese %, osservate %.',
      v_certificate.expected_unit_count,
      v_certificate.observed_unit_count;
  end if;
  if v_certificate.observed_record_count <> coalesce(p_records_processed, 0) then
    raise exception
      'Consegna provider incompleta [delivery.records_mismatch]: certificati %, run %.',
      v_certificate.observed_record_count,
      coalesce(p_records_processed, 0);
  end if;
  if v_certificate.unique_entity_count <> v_certificate.observed_record_count then
    raise exception 'Consegna provider incompleta [delivery.unique_mismatch].';
  end if;

  update public.provider_sync_delivery_certificates certificate_row
  set
    status = 'certified',
    summary = format(
      'Consegna provider certificata prima della pubblicazione atomica: %s unità, %s record univoci.',
      v_certificate.observed_unit_count,
      v_certificate.observed_record_count
    )
  where certificate_row.id = v_certificate.id
  returning * into v_certificate;

  return jsonb_build_object(
    'deliveryCertificateId', v_certificate.id,
    'deliveryRevision', v_certificate.revision,
    'deliveryStatus', v_certificate.status
  );
end;
$$;

revoke all on function public.certify_provider_sync_delivery_before_publication_v1(
  uuid,integer
)
from public, anon, authenticated;
grant execute on function public.certify_provider_sync_delivery_before_publication_v1(
  uuid,integer
)
to service_role;

create or replace function public.finish_provider_sync_run_guarded_v4(
  p_run_id uuid,
  p_status text,
  p_records_processed integer,
  p_error_message text default null,
  p_expected_revision bigint default null,
  p_lease_token uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_status text := lower(trim(coalesce(p_status, '')));
  v_run public.provider_sync_runs%rowtype;
  v_lease public.provider_sync_worker_leases%rowtype;
  v_publication public.provider_sync_publications%rowtype;
  v_publication_id uuid;
  v_counts jsonb;
  v_delivery jsonb;
  v_result jsonb;
  v_published_primary integer := 0;
begin
  if p_run_id is null or p_lease_token is null then
    raise exception
      'Pubblicazione provider rifiutata: run e token worker sono obbligatori.';
  end if;
  if v_status not in ('completed','failed') then
    raise exception 'Stato finale del run provider non valido.';
  end if;

  select run_row.*
  into v_run
  from public.provider_sync_runs run_row
  where run_row.id = p_run_id
  for update;

  if not found then
    raise exception 'Run provider non trovato durante la pubblicazione atomica.';
  end if;

  select lease_row.*
  into v_lease
  from public.provider_sync_worker_leases lease_row
  where lease_row.run_id = p_run_id
  for update;

  if not found then
    raise exception 'Lease worker provider non trovata durante la pubblicazione atomica.';
  end if;
  if v_lease.lease_token is distinct from p_lease_token then
    raise exception 'Pubblicazione provider rifiutata: token worker non più proprietario.';
  end if;
  if v_run.status = 'running' then
    if v_lease.status <> 'active' then
      raise exception 'Pubblicazione provider rifiutata: lease nello stato %.', v_lease.status;
    end if;
    if v_lease.lease_expires_at <= now() then
      raise exception 'Pubblicazione provider rifiutata: lease worker scaduta.';
    end if;
  end if;

  select publication_row.*
  into v_publication
  from public.provider_sync_publications publication_row
  where publication_row.run_id = p_run_id
  for update;

  if v_status = 'failed' then
    if found and v_publication.status = 'collecting' then
      delete from public.provider_sync_stage_scores row_item
      where row_item.publication_id = v_publication.id;
      delete from public.provider_sync_stage_fixtures row_item
      where row_item.publication_id = v_publication.id;
      delete from public.provider_sync_stage_roles row_item
      where row_item.publication_id = v_publication.id;
      delete from public.provider_sync_stage_matchdays row_item
      where row_item.publication_id = v_publication.id;
      delete from public.provider_sync_stage_athletes row_item
      where row_item.publication_id = v_publication.id;

      update public.provider_sync_publications publication_row
      set
        status = 'discarded',
        summary = left(
          'Staging provider scartato senza pubblicare dati operativi: '
          || regexp_replace(
            coalesce(nullif(trim(p_error_message), ''), 'run provider non completato'),
            E'[\r\n]+', ' ', 'g'
          ),
          500
        )
      where publication_row.id = v_publication.id
      returning * into v_publication;
    end if;

    v_result := public.finish_provider_sync_run_guarded_v3(
      p_run_id,
      p_status,
      p_records_processed,
      p_error_message,
      p_expected_revision,
      p_lease_token
    );

    return v_result || jsonb_build_object(
      'atomicPublication', true,
      'publicationId', v_publication.id,
      'publicationStatus', coalesce(v_publication.status, 'discarded'),
      'publishedPrimaryRecordCount', 0
    );
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext('provider-atomic-publication:' || v_run.provider)
  );

  v_delivery := public.certify_provider_sync_delivery_before_publication_v1(
    p_run_id,
    p_records_processed
  );

  if v_publication.id is null then
    v_publication_id := public.ensure_provider_sync_publication_v1(
      p_run_id,
      p_lease_token
    );
    select publication_row.*
    into v_publication
    from public.provider_sync_publications publication_row
    where publication_row.id = v_publication_id
    for update;
  end if;

  if v_publication.status = 'published' then
    if v_publication.published_primary_record_count = coalesce(p_records_processed, 0) then
      v_result := public.finish_provider_sync_run_guarded_v3(
        p_run_id,
        p_status,
        p_records_processed,
        p_error_message,
        p_expected_revision,
        p_lease_token
      );
      return v_result || jsonb_build_object(
        'atomicPublication', true,
        'publicationId', v_publication.id,
        'publicationStatus', v_publication.status,
        'publishedPrimaryRecordCount', v_publication.published_primary_record_count
      ) || v_delivery;
    end if;
    raise exception 'Pubblicazione provider già completata con un conteggio differente.';
  end if;
  if v_publication.status <> 'collecting' then
    raise exception 'Pubblicazione provider non eseguibile nello stato %.', v_publication.status;
  end if;

  v_counts := public.refresh_provider_sync_publication_counts_v1(v_publication.id);
  select publication_row.*
  into v_publication
  from public.provider_sync_publications publication_row
  where publication_row.id = v_publication.id
  for update;

  if v_publication.staged_primary_record_count <> coalesce(p_records_processed, 0) then
    raise exception
      'Pubblicazione provider incompleta [publication.records_mismatch]: staging %, run %.',
      v_publication.staged_primary_record_count,
      coalesce(p_records_processed, 0);
  end if;

  insert into public.athletes as athlete_target (
    id, provider, provider_player_id, first_name, last_name, club_name,
    provider_team_id, photo_url, position_code, active, payload, updated_at
  )
  select
    stage_row.athlete_id, stage_row.provider, stage_row.provider_player_id,
    stage_row.first_name, stage_row.last_name, stage_row.club_name,
    stage_row.provider_team_id, stage_row.photo_url, stage_row.position_code,
    stage_row.active, stage_row.payload, stage_row.source_updated_at
  from public.provider_sync_stage_athletes stage_row
  where stage_row.publication_id = v_publication.id
  on conflict (provider, provider_player_id) do update
  set
    first_name = coalesce(excluded.first_name, athlete_target.first_name),
    last_name = excluded.last_name,
    club_name = excluded.club_name,
    provider_team_id = excluded.provider_team_id,
    photo_url = excluded.photo_url,
    position_code = excluded.position_code,
    active = excluded.active,
    payload = excluded.payload,
    updated_at = excluded.updated_at;

  insert into public.matchdays as matchday_target (
    id, competition_code, season, number, starts_at, locks_at, ends_at
  )
  select
    stage_row.matchday_id, stage_row.competition_code, stage_row.season,
    stage_row.number, stage_row.starts_at, stage_row.locks_at, stage_row.ends_at
  from public.provider_sync_stage_matchdays stage_row
  where stage_row.publication_id = v_publication.id
  on conflict (competition_code, season, number) do update
  set
    starts_at = excluded.starts_at,
    locks_at = excluded.locks_at,
    ends_at = excluded.ends_at;

  insert into public.athlete_roles (athlete_id, mode, role_code)
  select
    coalesce(athlete_row.id, stage_row.athlete_id),
    stage_row.mode,
    stage_row.role_code
  from public.provider_sync_stage_roles stage_row
  left join public.provider_sync_stage_athletes staged_athlete
    on staged_athlete.publication_id = stage_row.publication_id
   and staged_athlete.athlete_id = stage_row.athlete_id
  left join public.athletes athlete_row
    on athlete_row.provider = staged_athlete.provider
   and athlete_row.provider_player_id = staged_athlete.provider_player_id
  where stage_row.publication_id = v_publication.id
  on conflict (athlete_id, mode, role_code) do nothing;

  insert into public.provider_fixtures as fixture_target (
    provider, provider_fixture_id, competition_code, season, matchday_id,
    kickoff_at, status, home_team_provider_id, home_team_name,
    away_team_provider_id, away_team_name, home_goals, away_goals,
    payload, updated_at
  )
  select
    stage_row.provider, stage_row.provider_fixture_id,
    stage_row.competition_code, stage_row.season,
    coalesce(matchday_row.id, stage_row.matchday_id),
    stage_row.kickoff_at, stage_row.status, stage_row.home_team_provider_id,
    stage_row.home_team_name, stage_row.away_team_provider_id,
    stage_row.away_team_name, stage_row.home_goals, stage_row.away_goals,
    stage_row.payload, stage_row.source_updated_at
  from public.provider_sync_stage_fixtures stage_row
  left join public.provider_sync_stage_matchdays staged_matchday
    on staged_matchday.publication_id = stage_row.publication_id
   and staged_matchday.matchday_id = stage_row.matchday_id
  left join public.matchdays matchday_row
    on matchday_row.competition_code = staged_matchday.competition_code
   and matchday_row.season = staged_matchday.season
   and matchday_row.number = staged_matchday.number
  where stage_row.publication_id = v_publication.id
  on conflict (provider, provider_fixture_id) do update
  set
    competition_code = excluded.competition_code,
    season = excluded.season,
    matchday_id = excluded.matchday_id,
    kickoff_at = excluded.kickoff_at,
    status = excluded.status,
    home_team_provider_id = excluded.home_team_provider_id,
    home_team_name = excluded.home_team_name,
    away_team_provider_id = excluded.away_team_provider_id,
    away_team_name = excluded.away_team_name,
    home_goals = excluded.home_goals,
    away_goals = excluded.away_goals,
    payload = excluded.payload,
    updated_at = excluded.updated_at;

  insert into public.player_match_scores as score_target (
    athlete_id, matchday_id, provider_fixture_id, provider_rating,
    fantasy_score, bonuses, maluses, raw_statistics, provider_payload,
    is_final, updated_at
  )
  select
    coalesce(athlete_row.id, stage_row.athlete_id),
    coalesce(matchday_row.id, stage_row.matchday_id),
    stage_row.provider_fixture_id, stage_row.provider_rating,
    stage_row.fantasy_score, stage_row.bonuses, stage_row.maluses,
    stage_row.raw_statistics, stage_row.provider_payload,
    stage_row.is_final, stage_row.source_updated_at
  from public.provider_sync_stage_scores stage_row
  left join public.provider_sync_stage_athletes staged_athlete
    on staged_athlete.publication_id = stage_row.publication_id
   and staged_athlete.athlete_id = stage_row.athlete_id
  left join public.athletes athlete_row
    on athlete_row.provider = staged_athlete.provider
   and athlete_row.provider_player_id = staged_athlete.provider_player_id
  left join public.provider_sync_stage_matchdays staged_matchday
    on staged_matchday.publication_id = stage_row.publication_id
   and staged_matchday.matchday_id = stage_row.matchday_id
  left join public.matchdays matchday_row
    on matchday_row.competition_code = staged_matchday.competition_code
   and matchday_row.season = staged_matchday.season
   and matchday_row.number = staged_matchday.number
  where stage_row.publication_id = v_publication.id
  on conflict (athlete_id, matchday_id) do update
  set
    provider_fixture_id = excluded.provider_fixture_id,
    provider_rating = excluded.provider_rating,
    fantasy_score = excluded.fantasy_score,
    bonuses = excluded.bonuses,
    maluses = excluded.maluses,
    raw_statistics = excluded.raw_statistics,
    provider_payload = excluded.provider_payload,
    is_final = excluded.is_final,
    updated_at = excluded.updated_at;

  v_published_primary := v_publication.staged_primary_record_count;

  delete from public.provider_sync_stage_scores row_item
  where row_item.publication_id = v_publication.id;
  delete from public.provider_sync_stage_fixtures row_item
  where row_item.publication_id = v_publication.id;
  delete from public.provider_sync_stage_roles row_item
  where row_item.publication_id = v_publication.id;
  delete from public.provider_sync_stage_matchdays row_item
  where row_item.publication_id = v_publication.id;
  delete from public.provider_sync_stage_athletes row_item
  where row_item.publication_id = v_publication.id;

  update public.provider_sync_publications publication_row
  set
    status = 'published',
    published_primary_record_count = v_published_primary,
    summary = format(
      'Pubblicazione provider atomica completata: %s record primari resi visibili in un unico commit.',
      v_published_primary
    )
  where publication_row.id = v_publication.id
  returning * into v_publication;

  v_result := public.finish_provider_sync_run_guarded_v3(
    p_run_id,
    p_status,
    p_records_processed,
    p_error_message,
    p_expected_revision,
    p_lease_token
  );

  return v_result || jsonb_build_object(
    'atomicPublication', true,
    'publicationId', v_publication.id,
    'publicationStatus', v_publication.status,
    'publishedPrimaryRecordCount', v_publication.published_primary_record_count
  ) || v_delivery;
end;
$$;

revoke all on function public.finish_provider_sync_run_guarded_v4(
  uuid,text,integer,text,bigint,uuid
)
from public, anon, authenticated;
grant execute on function public.finish_provider_sync_run_guarded_v4(
  uuid,text,integer,text,bigint,uuid
)
to service_role;

create or replace function public.get_league_provider_atomic_publication_center_v1(
  p_league_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_owner_id uuid;
  v_collecting integer := 0;
  v_published_24h integer := 0;
  v_discarded_24h integer := 0;
  v_total integer := 0;
  v_latest_at timestamptz;
  v_latest jsonb;
begin
  select league_row.owner_id
  into v_owner_id
  from public.leagues league_row
  where league_row.id = p_league_id;

  if not found then
    raise exception 'Lega non trovata per il controllo delle pubblicazioni provider.';
  end if;
  if auth.uid() is null
    or not (
      v_owner_id = auth.uid()
      or public.is_league_admin(p_league_id)
    ) then
    raise exception 'Solo Presidente e Admin possono leggere le pubblicazioni provider.';
  end if;

  select
    count(*)::integer,
    count(*) filter (where publication_row.status = 'collecting')::integer,
    count(*) filter (
      where publication_row.status = 'published'
        and publication_row.published_at >= now() - interval '24 hours'
    )::integer,
    count(*) filter (
      where publication_row.status = 'discarded'
        and publication_row.discarded_at >= now() - interval '24 hours'
    )::integer,
    max(publication_row.updated_at)
  into v_total, v_collecting, v_published_24h, v_discarded_24h, v_latest_at
  from public.provider_sync_publications publication_row
  where publication_row.league_id = p_league_id
    or publication_row.league_id is null;

  select jsonb_build_object(
    'id', publication_row.id,
    'runId', publication_row.run_id,
    'requestId', publication_row.recovery_request_id,
    'syncType', publication_row.sync_type,
    'status', publication_row.status,
    'stagedRowCount', publication_row.staged_row_count,
    'stagedPrimaryRecordCount', publication_row.staged_primary_record_count,
    'publishedPrimaryRecordCount', publication_row.published_primary_record_count,
    'summary', publication_row.summary,
    'updatedAt', publication_row.updated_at
  )
  into v_latest
  from public.provider_sync_publications publication_row
  where publication_row.league_id = p_league_id
    or publication_row.league_id is null
  order by publication_row.updated_at desc, publication_row.id desc
  limit 1;

  return jsonb_build_object(
    'protected', true,
    'healthy', coalesce(v_discarded_24h, 0) = 0,
    'atomicStagingActive', true,
    'singleCommitPublicationActive', true,
    'partialLiveWritesDisabled', true,
    'stagingPayloadPurgedAfterFinish', true,
    'collectingCount', coalesce(v_collecting, 0),
    'publishedLast24h', coalesce(v_published_24h, 0),
    'discardedLast24h', coalesce(v_discarded_24h, 0),
    'totalPublicationCount', coalesce(v_total, 0),
    'latestPublicationAt', v_latest_at,
    'latest', v_latest
  );
end;
$$;

revoke all on function public.get_league_provider_atomic_publication_center_v1(uuid)
from public, anon, authenticated;
grant execute on function public.get_league_provider_atomic_publication_center_v1(uuid)
to authenticated;

create or replace function public.get_league_provider_sync_health_v13(
  p_league_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_health jsonb;
  v_publication jsonb;
  v_healthy boolean;
  v_status text;
begin
  v_health := public.get_league_provider_sync_health_v12(p_league_id);
  v_publication := public.get_league_provider_atomic_publication_center_v1(
    p_league_id
  );
  v_healthy := coalesce((v_health ->> 'healthy')::boolean, false)
    and coalesce((v_publication ->> 'healthy')::boolean, false);
  v_status := case
    when not v_healthy then 'attention'
    else coalesce(v_health ->> 'status', 'idle')
  end;

  return v_health || jsonb_build_object(
    'protected',
      coalesce((v_health ->> 'protected')::boolean, false)
      and coalesce((v_publication ->> 'protected')::boolean, false),
    'healthy', v_healthy,
    'status', v_status,
    'atomicPublication', v_publication
  );
end;
$$;

revoke all on function public.get_league_provider_sync_health_v13(uuid)
from public, anon, authenticated;
grant execute on function public.get_league_provider_sync_health_v13(uuid)
to authenticated;

-- Solo manifest ed eventi sintetici sono pubblicabili in realtime.
do $realtime$
begin
  if exists (
    select 1
    from pg_catalog.pg_publication publication_row
    where publication_row.pubname = 'supabase_realtime'
  ) then
    if not exists (
      select 1
      from pg_catalog.pg_publication_tables publication_table
      where publication_table.pubname = 'supabase_realtime'
        and publication_table.schemaname = 'public'
        and publication_table.tablename = 'provider_sync_publications'
    ) then
      alter publication supabase_realtime
        add table public.provider_sync_publications;
    end if;
    if not exists (
      select 1
      from pg_catalog.pg_publication_tables publication_table
      where publication_table.pubname = 'supabase_realtime'
        and publication_table.schemaname = 'public'
        and publication_table.tablename = 'provider_sync_publication_events'
    ) then
      alter publication supabase_realtime
        add table public.provider_sync_publication_events;
    end if;
  end if;
end;
$realtime$;

create or replace function public.get_provider_atomic_publication_integrity_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_predecessor jsonb;
  v_finish_definition text;
  v_apply_v1_definition text;
  v_apply_v2_definition text;
  v_retry_policy jsonb;
begin
  v_predecessor := public.get_provider_delivery_completeness_integrity_v1();
  v_finish_definition := pg_catalog.pg_get_functiondef(
    'public.finish_provider_sync_run_guarded_v4(uuid,text,integer,text,bigint,uuid)'::regprocedure
  );
  v_apply_v1_definition := pg_catalog.pg_get_functiondef(
    'public.apply_provider_sync_write_guarded_v1(uuid,uuid,text,jsonb)'::regprocedure
  );
  v_apply_v2_definition := pg_catalog.pg_get_functiondef(
    'public.apply_provider_sync_write_guarded_v2(uuid,uuid,text,jsonb)'::regprocedure
  );

  v_retry_policy := public.provider_recovery_retry_policy_v1(
    'Pubblicazione provider incompleta [publication.records_mismatch].',
    1,
    'sync-season-players'
  );

  return jsonb_build_object(
    'predecessor_ready',
      not exists (
        select 1 from jsonb_each(v_predecessor) check_row
        where check_row.value is distinct from 'true'::jsonb
      ),
    'publication_table_ready',
      to_regclass('public.provider_sync_publications') is not null,
    'staging_tables_ready',
      to_regclass('public.provider_sync_stage_athletes') is not null
      and to_regclass('public.provider_sync_stage_roles') is not null
      and to_regclass('public.provider_sync_stage_matchdays') is not null
      and to_regclass('public.provider_sync_stage_fixtures') is not null
      and to_regclass('public.provider_sync_stage_scores') is not null,
    'event_table_ready',
      to_regclass('public.provider_sync_publication_events') is not null,
    'publication_columns_ready',
      (
        select count(*) = 18
        from information_schema.columns column_row
        where column_row.table_schema = 'public'
          and column_row.table_name = 'provider_sync_publications'
          and column_row.column_name in (
            'id','run_id','recovery_request_id','league_id','provider','sync_type',
            'status','staged_row_count','staged_primary_record_count',
            'published_primary_record_count','summary','run_revision',
            'lease_epoch','revision','created_at','updated_at','published_at',
            'discarded_at'
          )
      ),
    'staging_constraints_ready',
      to_regclass('public.provider_sync_stage_athletes_pkey') is not null
      and to_regclass('public.provider_sync_stage_roles_pkey') is not null
      and to_regclass('public.provider_sync_stage_matchdays_pkey') is not null
      and to_regclass('public.provider_sync_stage_fixtures_pkey') is not null
      and to_regclass('public.provider_sync_stage_scores_pkey') is not null,
    'publication_indexes_ready',
      to_regclass('public.provider_sync_publications_league_idx') is not null
      and to_regclass('public.provider_sync_publications_status_idx') is not null
      and to_regclass('public.provider_sync_publication_events_league_idx') is not null,
    'rls_ready',
      coalesce((select relrowsecurity from pg_catalog.pg_class where oid = 'public.provider_sync_publications'::regclass), false)
      and coalesce((select relrowsecurity from pg_catalog.pg_class where oid = 'public.provider_sync_stage_athletes'::regclass), false)
      and coalesce((select relrowsecurity from pg_catalog.pg_class where oid = 'public.provider_sync_stage_roles'::regclass), false)
      and coalesce((select relrowsecurity from pg_catalog.pg_class where oid = 'public.provider_sync_stage_matchdays'::regclass), false)
      and coalesce((select relrowsecurity from pg_catalog.pg_class where oid = 'public.provider_sync_stage_fixtures'::regclass), false)
      and coalesce((select relrowsecurity from pg_catalog.pg_class where oid = 'public.provider_sync_stage_scores'::regclass), false)
      and coalesce((select relrowsecurity from pg_catalog.pg_class where oid = 'public.provider_sync_publication_events'::regclass), false),
    'authenticated_staging_blocked',
      not has_table_privilege('authenticated','public.provider_sync_stage_athletes','SELECT')
      and not has_table_privilege('authenticated','public.provider_sync_stage_roles','SELECT')
      and not has_table_privilege('authenticated','public.provider_sync_stage_matchdays','SELECT')
      and not has_table_privilege('authenticated','public.provider_sync_stage_fixtures','SELECT')
      and not has_table_privilege('authenticated','public.provider_sync_stage_scores','SELECT'),
    'service_role_staging_ready',
      has_table_privilege('service_role','public.provider_sync_stage_athletes','INSERT')
      and has_table_privilege('service_role','public.provider_sync_stage_athletes','DELETE')
      and has_table_privilege('service_role','public.provider_sync_stage_fixtures','INSERT')
      and has_table_privilege('service_role','public.provider_sync_stage_scores','INSERT'),
    'director_policy_ready',
      exists (
        select 1 from pg_catalog.pg_policies policy_row
        where policy_row.schemaname = 'public'
          and policy_row.tablename = 'provider_sync_publications'
          and policy_row.policyname = 'provider_sync_publications_read_directors'
      )
      and exists (
        select 1 from pg_catalog.pg_policies policy_row
        where policy_row.schemaname = 'public'
          and policy_row.tablename = 'provider_sync_publication_events'
          and policy_row.policyname = 'provider_sync_publication_events_read_directors'
      ),
    'event_immutability_ready',
      has_table_privilege('authenticated','public.provider_sync_publication_events','SELECT')
      and not has_table_privilege('authenticated','public.provider_sync_publication_events','INSERT')
      and not has_table_privilege('authenticated','public.provider_sync_publication_events','UPDATE')
      and not has_table_privilege('authenticated','public.provider_sync_publication_events','DELETE')
      and has_table_privilege('service_role','public.provider_sync_publication_events','SELECT')
      and has_table_privilege('service_role','public.provider_sync_publication_events','INSERT')
      and to_regprocedure('public.prevent_provider_sync_publication_event_mutation_v1()') is not null
      and exists (
        select 1
        from pg_catalog.pg_proc function_row
        where function_row.oid =
          'public.prevent_provider_sync_publication_event_mutation_v1()'::regprocedure
          and function_row.prosecdef
          and position(
            'raise exception' in lower(
              pg_catalog.pg_get_functiondef(function_row.oid)
            )
          ) > 0
      )
      and exists (
        select 1
        from pg_catalog.pg_trigger trigger_row
        where trigger_row.tgrelid = 'public.provider_sync_publication_events'::regclass
          and trigger_row.tgname = 'provider_sync_publication_events_immutable'
          and trigger_row.tgfoid =
            'public.prevent_provider_sync_publication_event_mutation_v1()'::regprocedure
          and trigger_row.tgenabled = 'A'
          and (trigger_row.tgtype::integer & 1) = 1
          and (trigger_row.tgtype::integer & 2) = 2
          and (trigger_row.tgtype::integer & 8) = 8
          and (trigger_row.tgtype::integer & 16) = 16
          and not trigger_row.tgisinternal
      ),
    'ensure_publication_rpc_ready',
      to_regprocedure('public.ensure_provider_sync_publication_v1(uuid,uuid)') is not null
      and has_function_privilege(
        'service_role',
        'public.ensure_provider_sync_publication_v1(uuid,uuid)',
        'EXECUTE'
      ),
    'stage_write_rpc_ready',
      to_regprocedure('public.stage_provider_sync_write_guarded_v1(uuid,uuid,text,jsonb)') is not null
      and has_function_privilege(
        'service_role',
        'public.stage_provider_sync_write_guarded_v1(uuid,uuid,text,jsonb)',
        'EXECUTE'
      )
      and position('stage_provider_sync_write_guarded_v1' in lower(v_apply_v1_definition)) > 0
      and position('stage_provider_sync_write_guarded_v1' in lower(v_apply_v2_definition)) > 0,
    'delivery_precommit_gate_ready',
      to_regprocedure('public.certify_provider_sync_delivery_before_publication_v1(uuid,integer)') is not null
      and has_function_privilege(
        'service_role',
        'public.certify_provider_sync_delivery_before_publication_v1(uuid,integer)',
        'EXECUTE'
      )
      and coalesce((v_retry_policy ->> 'retryable')::boolean, false)
      and coalesce(v_retry_policy ->> 'failureClass', '') = 'provider',
    'finish_v4_ready',
      to_regprocedure('public.finish_provider_sync_run_guarded_v4(uuid,text,integer,text,bigint,uuid)') is not null
      and has_function_privilege(
        'service_role',
        'public.finish_provider_sync_run_guarded_v4(uuid,text,integer,text,bigint,uuid)',
        'EXECUTE'
      )
      and exists (
        select 1 from pg_catalog.pg_trigger trigger_row
        where trigger_row.tgrelid = 'public.provider_sync_runs'::regclass
          and trigger_row.tgname = 'provider_sync_atomic_completion_guard'
          and not trigger_row.tgisinternal
      )
      and exists (
        select 1 from pg_catalog.pg_trigger trigger_row
        where trigger_row.tgrelid = 'public.provider_sync_runs'::regclass
          and trigger_row.tgname = 'provider_sync_staging_failure_discard'
          and not trigger_row.tgisinternal
      ),
    'atomic_publish_body_ready',
      position('insert into public.athletes' in lower(v_finish_definition)) > 0
      and position('insert into public.provider_fixtures' in lower(v_finish_definition)) > 0
      and position('insert into public.player_match_scores' in lower(v_finish_definition)) > 0
      and position('delete from public.provider_sync_stage_athletes' in lower(v_finish_definition)) > 0
      and position('finish_provider_sync_run_guarded_v3' in lower(v_finish_definition)) > 0,
    'publication_center_ready',
      to_regprocedure('public.get_league_provider_atomic_publication_center_v1(uuid)') is not null
      and has_function_privilege(
        'authenticated',
        'public.get_league_provider_atomic_publication_center_v1(uuid)',
        'EXECUTE'
      ),
    'provider_health_v13_ready',
      to_regprocedure('public.get_league_provider_sync_health_v13(uuid)') is not null
      and has_function_privilege(
        'authenticated',
        'public.get_league_provider_sync_health_v13(uuid)',
        'EXECUTE'
      ),
    'realtime_manifest_only_ready',
      (
        not exists (
          select 1 from pg_catalog.pg_publication publication_row
          where publication_row.pubname = 'supabase_realtime'
        )
        or (
          exists (
            select 1 from pg_catalog.pg_publication_tables publication_table
            where publication_table.pubname = 'supabase_realtime'
              and publication_table.schemaname = 'public'
              and publication_table.tablename = 'provider_sync_publications'
          )
          and exists (
            select 1 from pg_catalog.pg_publication_tables publication_table
            where publication_table.pubname = 'supabase_realtime'
              and publication_table.schemaname = 'public'
              and publication_table.tablename = 'provider_sync_publication_events'
          )
          and not exists (
            select 1 from pg_catalog.pg_publication_tables publication_table
            where publication_table.pubname = 'supabase_realtime'
              and publication_table.schemaname = 'public'
              and publication_table.tablename in (
                'provider_sync_stage_athletes','provider_sync_stage_roles',
                'provider_sync_stage_matchdays','provider_sync_stage_fixtures',
                'provider_sync_stage_scores'
              )
          )
        )
      )
  );
end;
$$;

revoke all on function public.get_provider_atomic_publication_integrity_v1()
from public, anon, authenticated;
grant execute on function public.get_provider_atomic_publication_integrity_v1()
to authenticated, service_role;

-- Arresta la transazione indicando il controllo preciso eventualmente fallito.
do $validation$
declare
  v_checks jsonb := public.get_provider_atomic_publication_integrity_v1();
  v_failed text[];
begin
  select array_agg(check_row.key order by check_row.key)
  into v_failed
  from jsonb_each(v_checks) check_row
  where jsonb_typeof(check_row.value) is distinct from 'boolean'
    or check_row.value is distinct from 'true'::jsonb;

  if coalesce(array_length(v_failed, 1), 0) > 0 then
    raise exception
      'Validazione v0.62.14 non superata. Controlli falsi: %',
      array_to_string(v_failed, '; ');
  end if;
end;
$validation$;

commit;

-- Diagnostica finale: devono comparire esattamente 20 valori true.
select
  (checks ->> 'predecessor_ready')::boolean as predecessor_ready,
  (checks ->> 'publication_table_ready')::boolean as publication_table_ready,
  (checks ->> 'staging_tables_ready')::boolean as staging_tables_ready,
  (checks ->> 'event_table_ready')::boolean as event_table_ready,
  (checks ->> 'publication_columns_ready')::boolean as publication_columns_ready,
  (checks ->> 'staging_constraints_ready')::boolean as staging_constraints_ready,
  (checks ->> 'publication_indexes_ready')::boolean as publication_indexes_ready,
  (checks ->> 'rls_ready')::boolean as rls_ready,
  (checks ->> 'authenticated_staging_blocked')::boolean as authenticated_staging_blocked,
  (checks ->> 'service_role_staging_ready')::boolean as service_role_staging_ready,
  (checks ->> 'director_policy_ready')::boolean as director_policy_ready,
  (checks ->> 'event_immutability_ready')::boolean as event_immutability_ready,
  (checks ->> 'ensure_publication_rpc_ready')::boolean as ensure_publication_rpc_ready,
  (checks ->> 'stage_write_rpc_ready')::boolean as stage_write_rpc_ready,
  (checks ->> 'delivery_precommit_gate_ready')::boolean as delivery_precommit_gate_ready,
  (checks ->> 'finish_v4_ready')::boolean as finish_v4_ready,
  (checks ->> 'atomic_publish_body_ready')::boolean as atomic_publish_body_ready,
  (checks ->> 'publication_center_ready')::boolean as publication_center_ready,
  (checks ->> 'provider_health_v13_ready')::boolean as provider_health_v13_ready,
  (checks ->> 'realtime_manifest_only_ready')::boolean as realtime_manifest_only_ready
from (
  select public.get_provider_atomic_publication_integrity_v1() as checks
) diagnostic;
