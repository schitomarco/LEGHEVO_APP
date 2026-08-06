-- LEGHEVO v0.62.11 · Lease e fencing protetto del worker provider
-- Migrazione interna: database/115_provider_worker_lease_fencing_safety.sql
--
-- Obiettivi:
-- - assegnare ogni run provider a una sola esecuzione tramite token non riutilizzabile;
-- - rinnovare una lease temporale durante gli heartbeat del worker;
-- - impedire a un worker scaduto o sostituito di scrivere o concludere il run;
-- - chiudere automaticamente le lease quando il run termina o viene revocato;
-- - preservare coda, watchdog, retry, circuit breaker e certificati di efficacia;
-- - terminare con una diagnostica strutturale di esattamente 20 controlli.

begin;

-- Preflight esplicito delle sole dipendenze realmente usate.
do $preflight$
declare
  v_missing text[] := array[]::text[];
  v_expected record;
begin
  for v_expected in
    select *
    from (values
      ('leagues', 'id'),
      ('leagues', 'owner_id'),
      ('provider_sync_runs', 'id'),
      ('provider_sync_runs', 'provider'),
      ('provider_sync_runs', 'sync_type'),
      ('provider_sync_runs', 'status'),
      ('provider_sync_runs', 'revision'),
      ('provider_sync_runs', 'records_processed'),
      ('provider_sync_runs', 'heartbeat_at'),
      ('provider_sync_runs', 'last_updated_at'),
      ('provider_sync_runs', 'finished_at'),
      ('provider_recovery_requests', 'id'),
      ('provider_recovery_requests', 'league_id'),
      ('provider_recovery_requests', 'incident_id'),
      ('provider_recovery_requests', 'status'),
      ('provider_recovery_requests', 'revision'),
      ('provider_recovery_requests', 'recovery_run_id'),
      ('athletes', 'id'),
      ('athletes', 'provider'),
      ('athletes', 'provider_player_id'),
      ('athletes', 'first_name'),
      ('athletes', 'last_name'),
      ('athletes', 'club_name'),
      ('athletes', 'provider_team_id'),
      ('athletes', 'photo_url'),
      ('athletes', 'position_code'),
      ('athletes', 'active'),
      ('athletes', 'payload'),
      ('athletes', 'updated_at'),
      ('athlete_roles', 'athlete_id'),
      ('athlete_roles', 'mode'),
      ('athlete_roles', 'role_code'),
      ('matchdays', 'id'),
      ('matchdays', 'competition_code'),
      ('matchdays', 'season'),
      ('matchdays', 'number'),
      ('matchdays', 'starts_at'),
      ('matchdays', 'locks_at'),
      ('matchdays', 'ends_at'),
      ('provider_fixtures', 'provider'),
      ('provider_fixtures', 'provider_fixture_id'),
      ('provider_fixtures', 'competition_code'),
      ('provider_fixtures', 'season'),
      ('provider_fixtures', 'matchday_id'),
      ('provider_fixtures', 'kickoff_at'),
      ('provider_fixtures', 'status'),
      ('provider_fixtures', 'home_team_provider_id'),
      ('provider_fixtures', 'home_team_name'),
      ('provider_fixtures', 'away_team_provider_id'),
      ('provider_fixtures', 'away_team_name'),
      ('provider_fixtures', 'home_goals'),
      ('provider_fixtures', 'away_goals'),
      ('provider_fixtures', 'payload'),
      ('provider_fixtures', 'updated_at'),
      ('player_match_scores', 'athlete_id'),
      ('player_match_scores', 'matchday_id'),
      ('player_match_scores', 'provider_fixture_id'),
      ('player_match_scores', 'provider_rating'),
      ('player_match_scores', 'fantasy_score'),
      ('player_match_scores', 'bonuses'),
      ('player_match_scores', 'maluses'),
      ('player_match_scores', 'raw_statistics'),
      ('player_match_scores', 'provider_payload'),
      ('player_match_scores', 'is_final'),
      ('player_match_scores', 'updated_at')
    ) as expected(table_name, column_name)
  loop
    if not exists (
      select 1
      from information_schema.columns column_row
      where column_row.table_schema = 'public'
        and column_row.table_name = v_expected.table_name
        and column_row.column_name = v_expected.column_name
    ) then
      v_missing := array_append(
        v_missing,
        format('column public.%I.%I', v_expected.table_name, v_expected.column_name)
      );
    end if;
  end loop;

  if to_regprocedure('auth.uid()') is null then
    v_missing := array_append(v_missing, 'function auth.uid()');
  end if;
  if to_regprocedure('gen_random_uuid()') is null then
    v_missing := array_append(v_missing, 'function gen_random_uuid()');
  end if;
  if to_regprocedure('pg_catalog.md5(text)') is null then
    v_missing := array_append(v_missing, 'function pg_catalog.md5(text)');
  end if;
  if to_regprocedure('pg_catalog.hashtext(text)') is null then
    v_missing := array_append(v_missing, 'function pg_catalog.hashtext(text)');
  end if;
  if to_regtype('public.league_mode') is null then
    v_missing := array_append(v_missing, 'type public.league_mode');
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
  if to_regprocedure('pg_catalog.pg_advisory_xact_lock(bigint)') is null then
    v_missing := array_append(
      v_missing,
      'function pg_catalog.pg_advisory_xact_lock(bigint)'
    );
  end if;
  if to_regprocedure('public.is_league_admin(uuid)') is null then
    v_missing := array_append(v_missing, 'function public.is_league_admin(uuid)');
  end if;
  if to_regprocedure('public.start_provider_sync_run_guarded_v1(jsonb)') is null then
    v_missing := array_append(
      v_missing,
      'function public.start_provider_sync_run_guarded_v1(jsonb)'
    );
  end if;
  if to_regprocedure(
    'public.finish_provider_sync_run_guarded_v1(uuid,text,integer,text,bigint)'
  ) is null then
    v_missing := array_append(
      v_missing,
      'function public.finish_provider_sync_run_guarded_v1(uuid,text,integer,text,bigint)'
    );
  end if;
  if to_regprocedure(
    'public.heartbeat_provider_sync_run_guarded_v1(uuid,integer,text,integer,integer,bigint)'
  ) is null then
    v_missing := array_append(
      v_missing,
      'function public.heartbeat_provider_sync_run_guarded_v1(uuid,integer,text,integer,integer,bigint)'
    );
  end if;
  if to_regprocedure(
    'public.claim_provider_recovery_request_v2(uuid,bigint)'
  ) is null then
    v_missing := array_append(
      v_missing,
      'function public.claim_provider_recovery_request_v2(uuid,bigint)'
    );
  end if;
  if to_regprocedure(
    'public.claim_next_provider_recovery_request_v3()'
  ) is null then
    v_missing := array_append(
      v_missing,
      'function public.claim_next_provider_recovery_request_v3()'
    );
  end if;
  if to_regprocedure(
    'public.get_league_provider_recovery_center_v6(uuid)'
  ) is null then
    v_missing := array_append(
      v_missing,
      'function public.get_league_provider_recovery_center_v6(uuid)'
    );
  end if;
  if to_regprocedure(
    'public.get_league_provider_sync_health_v9(uuid)'
  ) is null then
    v_missing := array_append(
      v_missing,
      'function public.get_league_provider_sync_health_v9(uuid)'
    );
  end if;
  if to_regprocedure(
    'public.get_provider_recovery_outcome_verification_integrity_v1()'
  ) is null then
    v_missing := array_append(
      v_missing,
      'function public.get_provider_recovery_outcome_verification_integrity_v1()'
    );
  end if;

  if not exists (
    select 1 from pg_catalog.pg_roles role_row where role_row.rolname = 'anon'
  ) then
    v_missing := array_append(v_missing, 'role anon');
  end if;
  if not exists (
    select 1 from pg_catalog.pg_roles role_row where role_row.rolname = 'authenticated'
  ) then
    v_missing := array_append(v_missing, 'role authenticated');
  end if;
  if not exists (
    select 1 from pg_catalog.pg_roles role_row where role_row.rolname = 'service_role'
  ) then
    v_missing := array_append(v_missing, 'role service_role');
  end if;
  if not exists (
    select 1
    from pg_catalog.pg_publication publication_row
    where publication_row.pubname = 'supabase_realtime'
  ) then
    v_missing := array_append(v_missing, 'publication supabase_realtime');
  end if;

  if coalesce(array_length(v_missing, 1), 0) > 0 then
    raise exception
      'Preflight v0.62.11 non superato. Oggetti mancanti: %',
      array_to_string(v_missing, '; ');
  end if;
end;
$preflight$;

create table if not exists public.provider_sync_worker_leases (
  id uuid primary key default gen_random_uuid(),
  run_id uuid not null unique
    references public.provider_sync_runs(id) on delete cascade,
  recovery_request_id uuid
    references public.provider_recovery_requests(id) on delete set null,
  league_id uuid references public.leagues(id) on delete cascade,
  provider text not null,
  sync_type text not null,
  lease_token uuid not null unique,
  lease_epoch bigint not null default 1 check (lease_epoch > 0),
  status text not null default 'active' check (
    status in ('active', 'released', 'revoked', 'expired')
  ),
  lease_expires_at timestamptz not null,
  last_heartbeat_at timestamptz not null default now(),
  revision bigint not null default 1 check (revision > 0),
  revoke_reason text,
  acquired_at timestamptz not null default now(),
  released_at timestamptz,
  updated_at timestamptz not null default now(),
  check (lease_expires_at > acquired_at),
  check (
    (status = 'active' and released_at is null and revoke_reason is null)
    or
    (status in ('released', 'revoked', 'expired') and released_at is not null)
  )
);

create index if not exists provider_sync_worker_leases_league_idx
  on public.provider_sync_worker_leases (league_id, updated_at desc);
create index if not exists provider_sync_worker_leases_active_expiry_idx
  on public.provider_sync_worker_leases (lease_expires_at)
  where status = 'active';
create index if not exists provider_sync_worker_leases_request_idx
  on public.provider_sync_worker_leases (recovery_request_id)
  where recovery_request_id is not null;

create table if not exists public.provider_sync_worker_lease_events (
  id uuid primary key default gen_random_uuid(),
  lease_id uuid not null
    references public.provider_sync_worker_leases(id) on delete cascade,
  run_id uuid not null,
  recovery_request_id uuid,
  league_id uuid,
  event_type text not null check (
    event_type in ('acquired', 'heartbeat', 'released', 'revoked', 'expired')
  ),
  lease_epoch bigint not null check (lease_epoch > 0),
  revision bigint not null check (revision > 0),
  lease_expires_at timestamptz not null,
  event_fingerprint text not null check (char_length(event_fingerprint) = 32),
  created_at timestamptz not null default now(),
  unique (lease_id, revision)
);

create index if not exists provider_sync_worker_lease_events_league_idx
  on public.provider_sync_worker_lease_events (league_id, created_at desc);
create index if not exists provider_sync_worker_lease_events_run_idx
  on public.provider_sync_worker_lease_events (run_id, created_at desc);

alter table public.provider_sync_worker_leases enable row level security;
alter table public.provider_sync_worker_leases replica identity full;
alter table public.provider_sync_worker_lease_events enable row level security;
alter table public.provider_sync_worker_lease_events replica identity full;

revoke all on table public.provider_sync_worker_leases
from public, anon, authenticated;
revoke all on table public.provider_sync_worker_lease_events
from public, anon, authenticated;
grant select, insert, update on table public.provider_sync_worker_leases
to service_role;
grant select on table public.provider_sync_worker_lease_events
to authenticated;
grant select, insert on table public.provider_sync_worker_lease_events
to service_role;

drop policy if exists provider_sync_worker_lease_events_read_directors
on public.provider_sync_worker_lease_events;
create policy provider_sync_worker_lease_events_read_directors
on public.provider_sync_worker_lease_events
for select
to authenticated
using (
  exists (
    select 1
    from public.leagues league_row
    where league_row.id = provider_sync_worker_lease_events.league_id
      and (
        league_row.owner_id = auth.uid()
        or public.is_league_admin(league_row.id)
      )
  )
);

create or replace function public.provider_sync_worker_lease_seconds_v1(
  p_sync_type text
)
returns integer
language sql
immutable
set search_path = ''
as $$
  select case lower(trim(coalesce(p_sync_type, '')))
    when 'sync-fixture-players' then 300
    when 'sync-fixtures' then 300
    when 'sync-season-players' then 600
    else 300
  end
$$;

revoke all on function public.provider_sync_worker_lease_seconds_v1(text)
from public, anon, authenticated;
grant execute on function public.provider_sync_worker_lease_seconds_v1(text)
to service_role;

create or replace function public.prepare_provider_sync_worker_lease_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    new.provider := lower(trim(coalesce(new.provider, '')));
    new.sync_type := lower(trim(coalesce(new.sync_type, '')));
    if new.provider = '' or new.sync_type = '' then
      raise exception 'Identità della lease worker provider non valida.';
    end if;
    if new.lease_token is null then
      raise exception 'Token della lease worker provider mancante.';
    end if;
    new.status := 'active';
    new.lease_epoch := greatest(coalesce(new.lease_epoch, 1), 1);
    new.revision := 1;
    new.acquired_at := coalesce(new.acquired_at, now());
    new.last_heartbeat_at := coalesce(new.last_heartbeat_at, new.acquired_at);
    new.updated_at := new.acquired_at;
    new.released_at := null;
    new.revoke_reason := null;
    if new.lease_expires_at <= new.acquired_at then
      raise exception 'Scadenza della lease worker provider non valida.';
    end if;
    return new;
  end if;

  if row(
    new.run_id,
    new.recovery_request_id,
    new.league_id,
    new.provider,
    new.sync_type,
    new.lease_token,
    new.lease_epoch,
    new.acquired_at
  ) is distinct from row(
    old.run_id,
    old.recovery_request_id,
    old.league_id,
    old.provider,
    old.sync_type,
    old.lease_token,
    old.lease_epoch,
    old.acquired_at
  ) then
    raise exception 'Identità della lease worker provider non modificabile.';
  end if;

  if old.status <> 'active' then
    if row(
      new.status,
      new.lease_expires_at,
      new.last_heartbeat_at,
      new.revoke_reason,
      new.released_at
    ) is not distinct from row(
      old.status,
      old.lease_expires_at,
      old.last_heartbeat_at,
      old.revoke_reason,
      old.released_at
    ) then
      return old;
    end if;
    raise exception 'Lease worker provider già chiusa e immutabile.';
  end if;

  if new.status not in ('active', 'released', 'revoked', 'expired') then
    raise exception 'Stato della lease worker provider non valido.';
  end if;

  new.revision := old.revision + 1;
  new.updated_at := now();

  if new.status = 'active' then
    if new.lease_expires_at <= now() then
      raise exception 'Una lease worker attiva deve avere una scadenza futura.';
    end if;
    new.last_heartbeat_at := greatest(
      coalesce(new.last_heartbeat_at, old.last_heartbeat_at),
      old.last_heartbeat_at
    );
    new.released_at := null;
    new.revoke_reason := null;
  else
    new.released_at := coalesce(new.released_at, now());
    if new.status = 'released' then
      new.revoke_reason := null;
    else
      new.revoke_reason := left(
        coalesce(nullif(trim(new.revoke_reason), ''), 'Lease worker provider revocata.'),
        500
      );
    end if;
  end if;

  return new;
end;
$$;

revoke all on function public.prepare_provider_sync_worker_lease_v1()
from public, anon, authenticated;

drop trigger if exists provider_sync_worker_lease_revision_guard
on public.provider_sync_worker_leases;
create trigger provider_sync_worker_lease_revision_guard
before insert or update on public.provider_sync_worker_leases
for each row execute function public.prepare_provider_sync_worker_lease_v1();

create or replace function public.record_provider_sync_worker_lease_event_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_event_type text;
begin
  v_event_type := case
    when tg_op = 'INSERT' then 'acquired'
    when new.status = 'active' then 'heartbeat'
    else new.status
  end;

  insert into public.provider_sync_worker_lease_events (
    lease_id,
    run_id,
    recovery_request_id,
    league_id,
    event_type,
    lease_epoch,
    revision,
    lease_expires_at,
    event_fingerprint,
    created_at
  ) values (
    new.id,
    new.run_id,
    new.recovery_request_id,
    new.league_id,
    v_event_type,
    new.lease_epoch,
    new.revision,
    new.lease_expires_at,
    pg_catalog.md5(
      new.id::text || E'\n'
      || new.run_id::text || E'\n'
      || coalesce(new.recovery_request_id::text, '') || E'\n'
      || coalesce(new.league_id::text, '') || E'\n'
      || v_event_type || E'\n'
      || new.lease_epoch::text || E'\n'
      || new.revision::text || E'\n'
      || new.lease_expires_at::text
    ),
    now()
  )
  on conflict (lease_id, revision) do nothing;

  return new;
end;
$$;

revoke all on function public.record_provider_sync_worker_lease_event_v1()
from public, anon, authenticated;

drop trigger if exists provider_sync_worker_lease_event_writer
on public.provider_sync_worker_leases;
create trigger provider_sync_worker_lease_event_writer
after insert or update on public.provider_sync_worker_leases
for each row execute function public.record_provider_sync_worker_lease_event_v1();

create or replace function public.prevent_provider_sync_worker_lease_event_mutation_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  raise exception 'Lo storico delle lease worker provider è immutabile.';
end;
$$;

revoke all on function public.prevent_provider_sync_worker_lease_event_mutation_v1()
from public, anon, authenticated;

drop trigger if exists provider_sync_worker_lease_events_immutable
on public.provider_sync_worker_lease_events;
create trigger provider_sync_worker_lease_events_immutable
before update or delete on public.provider_sync_worker_lease_events
for each row execute function public.prevent_provider_sync_worker_lease_event_mutation_v1();

create or replace function public.acquire_provider_sync_worker_lease_v1(
  p_run_id uuid,
  p_lease_token uuid,
  p_recovery_request_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_run public.provider_sync_runs%rowtype;
  v_request public.provider_recovery_requests%rowtype;
  v_existing public.provider_sync_worker_leases%rowtype;
  v_inserted public.provider_sync_worker_leases%rowtype;
  v_seconds integer;
  v_league_id uuid;
begin
  if p_run_id is null then
    raise exception 'Run provider non valido per la lease worker.';
  end if;
  if p_lease_token is null then
    raise exception 'Token della lease worker provider non valido.';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext('provider-worker-lease:' || p_run_id::text)
  );

  select run_row.*
  into v_run
  from public.provider_sync_runs run_row
  where run_row.id = p_run_id
  for update;

  if not found then
    raise exception 'Run provider non trovato per la lease worker.';
  end if;

  if p_recovery_request_id is not null then
    select request_row.*
    into v_request
    from public.provider_recovery_requests request_row
    where request_row.id = p_recovery_request_id
    for update;

    if not found then
      raise exception 'Richiesta di recupero non trovata per la lease worker.';
    end if;
    if v_request.recovery_run_id is distinct from v_run.id then
      raise exception 'La richiesta di recupero non appartiene al run indicato.';
    end if;
    if v_request.status <> 'running' then
      raise exception 'La richiesta di recupero non è più in esecuzione.';
    end if;
    v_league_id := v_request.league_id;
  end if;

  select lease_row.*
  into v_existing
  from public.provider_sync_worker_leases lease_row
  where lease_row.run_id = v_run.id
  for update;

  if found then
    if v_existing.lease_token = p_lease_token
      and v_existing.status = 'active'
      and v_existing.lease_expires_at > now()
      and v_run.status = 'running' then
      return jsonb_build_object(
        'granted', true,
        'reused', true,
        'leaseId', v_existing.id,
        'leaseToken', v_existing.lease_token,
        'leaseEpoch', v_existing.lease_epoch,
        'leaseRevision', v_existing.revision,
        'leaseExpiresAt', v_existing.lease_expires_at,
        'lastHeartbeatAt', v_existing.last_heartbeat_at,
        'status', v_existing.status
      );
    end if;

    return jsonb_build_object(
      'granted', false,
      'reused', true,
      'leaseId', v_existing.id,
      'leaseEpoch', v_existing.lease_epoch,
      'leaseRevision', v_existing.revision,
      'leaseExpiresAt', v_existing.lease_expires_at,
      'lastHeartbeatAt', v_existing.last_heartbeat_at,
      'status', case
        when v_existing.status = 'active'
          and v_existing.lease_expires_at <= now() then 'expired'
        else v_existing.status
      end,
      'busy', v_existing.status = 'active'
        and v_existing.lease_expires_at > now()
        and v_existing.lease_token <> p_lease_token
    );
  end if;

  if v_run.status <> 'running' then
    return jsonb_build_object(
      'granted', false,
      'reused', true,
      'status', v_run.status,
      'busy', false
    );
  end if;

  v_seconds := public.provider_sync_worker_lease_seconds_v1(v_run.sync_type);

  insert into public.provider_sync_worker_leases (
    run_id,
    recovery_request_id,
    league_id,
    provider,
    sync_type,
    lease_token,
    lease_epoch,
    status,
    lease_expires_at,
    last_heartbeat_at,
    acquired_at
  ) values (
    v_run.id,
    p_recovery_request_id,
    v_league_id,
    v_run.provider,
    v_run.sync_type,
    p_lease_token,
    1,
    'active',
    now() + (v_seconds * interval '1 second'),
    now(),
    now()
  )
  returning * into v_inserted;

  return jsonb_build_object(
    'granted', true,
    'reused', false,
    'leaseId', v_inserted.id,
    'leaseToken', v_inserted.lease_token,
    'leaseEpoch', v_inserted.lease_epoch,
    'leaseRevision', v_inserted.revision,
    'leaseExpiresAt', v_inserted.lease_expires_at,
    'lastHeartbeatAt', v_inserted.last_heartbeat_at,
    'status', v_inserted.status
  );
end;
$$;

revoke all on function public.acquire_provider_sync_worker_lease_v1(uuid,uuid,uuid)
from public, anon, authenticated;
grant execute on function public.acquire_provider_sync_worker_lease_v1(uuid,uuid,uuid)
to service_role;

create or replace function public.assert_provider_sync_worker_lease_v1(
  p_run_id uuid,
  p_lease_token uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_run public.provider_sync_runs%rowtype;
  v_lease public.provider_sync_worker_leases%rowtype;
begin
  if p_run_id is null or p_lease_token is null then
    raise exception 'Identità della lease worker provider incompleta.';
  end if;

  select run_row.*
  into v_run
  from public.provider_sync_runs run_row
  where run_row.id = p_run_id
  for update;

  if not found then
    raise exception 'Run provider non trovato durante il controllo fencing.';
  end if;

  select lease_row.*
  into v_lease
  from public.provider_sync_worker_leases lease_row
  where lease_row.run_id = v_run.id
  for update;

  if not found then
    raise exception 'Lease worker provider non trovata per il run %.', v_run.id;
  end if;
  if v_lease.lease_token <> p_lease_token then
    raise exception 'Fencing provider rifiutato: il worker non possiede la lease corrente.';
  end if;
  if v_lease.status <> 'active' then
    raise exception 'Fencing provider rifiutato: lease worker nello stato %.', v_lease.status;
  end if;
  if v_lease.lease_expires_at <= now() then
    raise exception 'Fencing provider rifiutato: lease worker scaduta alle %.', v_lease.lease_expires_at;
  end if;
  if v_run.status <> 'running' then
    raise exception 'Fencing provider rifiutato: run già nello stato %.', v_run.status;
  end if;

  return jsonb_build_object(
    'valid', true,
    'runId', v_run.id,
    'runRevision', v_run.revision,
    'leaseId', v_lease.id,
    'leaseEpoch', v_lease.lease_epoch,
    'leaseRevision', v_lease.revision,
    'leaseExpiresAt', v_lease.lease_expires_at,
    'lastHeartbeatAt', v_lease.last_heartbeat_at
  );
end;
$$;

revoke all on function public.assert_provider_sync_worker_lease_v1(uuid,uuid)
from public, anon, authenticated;
grant execute on function public.assert_provider_sync_worker_lease_v1(uuid,uuid)
to service_role;

-- La verifica e la scrittura avvengono nella stessa transazione. In questo modo
-- il lock della lease resta attivo fino al completamento dell'upsert e non
-- esiste una finestra TOCTOU tra una RPC di controllo e una chiamata REST.
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
declare
  v_operation text := lower(trim(coalesce(p_operation, '')));
  v_result jsonb;
begin
  perform public.assert_provider_sync_worker_lease_v1(
    p_run_id,
    p_lease_token
  );

  if v_operation = 'upsert-athletes' then
    if jsonb_typeof(coalesce(p_payload, 'null'::jsonb)) <> 'array' then
      raise exception 'Payload atleti non valido per la scrittura fencing.';
    end if;

    with upserted as (
      insert into public.athletes as athlete_target (
        provider,
        provider_player_id,
        first_name,
        last_name,
        club_name,
        provider_team_id,
        photo_url,
        position_code,
        active,
        payload,
        updated_at
      )
      select
        item.provider,
        item.provider_player_id,
        item.first_name,
        item.last_name,
        item.club_name,
        item.provider_team_id,
        item.photo_url,
        item.position_code,
        coalesce(item.active, true),
        coalesce(item.payload, '{}'::jsonb),
        coalesce(item.updated_at, now())
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
        updated_at = excluded.updated_at
      returning id, provider_player_id, position_code
    )
    select jsonb_build_object(
      'count', count(*),
      'records', coalesce(jsonb_agg(to_jsonb(upserted)), '[]'::jsonb)
    )
    into v_result
    from upserted;

  elsif v_operation = 'upsert-athlete-roles' then
    if jsonb_typeof(coalesce(p_payload, 'null'::jsonb)) <> 'array' then
      raise exception 'Payload ruoli non valido per la scrittura fencing.';
    end if;

    with upserted as (
      insert into public.athlete_roles (athlete_id, mode, role_code)
      select
        item.athlete_id,
        item.mode::public.league_mode,
        item.role_code
      from jsonb_to_recordset(p_payload) as item(
        athlete_id uuid,
        mode text,
        role_code text
      )
      on conflict (athlete_id, mode, role_code) do nothing
      returning athlete_id
    )
    select jsonb_build_object('count', count(*))
    into v_result
    from upserted;

  elsif v_operation = 'upsert-matchday' then
    if jsonb_typeof(coalesce(p_payload, 'null'::jsonb)) <> 'object' then
      raise exception 'Payload giornata non valido per la scrittura fencing.';
    end if;

    with upserted as (
      insert into public.matchdays (
        competition_code,
        season,
        number,
        starts_at,
        locks_at,
        ends_at
      )
      select
        item.competition_code,
        item.season,
        item.number,
        item.starts_at,
        item.locks_at,
        item.ends_at
      from jsonb_to_record(p_payload) as item(
        competition_code text,
        season text,
        number smallint,
        starts_at timestamptz,
        locks_at timestamptz,
        ends_at timestamptz
      )
      on conflict (competition_code, season, number) do update
      set
        starts_at = excluded.starts_at,
        locks_at = excluded.locks_at,
        ends_at = excluded.ends_at
      returning id
    )
    select jsonb_build_object('record', to_jsonb(upserted))
    into v_result
    from upserted;

  elsif v_operation = 'upsert-provider-fixtures' then
    if jsonb_typeof(coalesce(p_payload, 'null'::jsonb)) <> 'array' then
      raise exception 'Payload partite non valido per la scrittura fencing.';
    end if;

    with upserted as (
      insert into public.provider_fixtures (
        provider,
        provider_fixture_id,
        competition_code,
        season,
        matchday_id,
        kickoff_at,
        status,
        home_team_provider_id,
        home_team_name,
        away_team_provider_id,
        away_team_name,
        home_goals,
        away_goals,
        payload,
        updated_at
      )
      select
        item.provider,
        item.provider_fixture_id,
        item.competition_code,
        item.season,
        item.matchday_id,
        item.kickoff_at,
        item.status,
        item.home_team_provider_id,
        item.home_team_name,
        item.away_team_provider_id,
        item.away_team_name,
        item.home_goals,
        item.away_goals,
        coalesce(item.payload, '{}'::jsonb),
        coalesce(item.updated_at, now())
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
        updated_at = excluded.updated_at
      returning id
    )
    select jsonb_build_object('count', count(*))
    into v_result
    from upserted;

  elsif v_operation = 'upsert-player-scores' then
    if jsonb_typeof(coalesce(p_payload, 'null'::jsonb)) <> 'array' then
      raise exception 'Payload voti non valido per la scrittura fencing.';
    end if;

    with upserted as (
      insert into public.player_match_scores (
        athlete_id,
        matchday_id,
        provider_fixture_id,
        provider_rating,
        fantasy_score,
        bonuses,
        maluses,
        raw_statistics,
        provider_payload,
        is_final,
        updated_at
      )
      select
        item.athlete_id,
        item.matchday_id,
        item.provider_fixture_id,
        item.provider_rating,
        item.fantasy_score,
        coalesce(item.bonuses, '{}'::jsonb),
        coalesce(item.maluses, '{}'::jsonb),
        coalesce(item.raw_statistics, '{}'::jsonb),
        coalesce(item.provider_payload, '{}'::jsonb),
        coalesce(item.is_final, false),
        coalesce(item.updated_at, now())
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
        updated_at = excluded.updated_at
      returning id
    )
    select jsonb_build_object('count', count(*))
    into v_result
    from upserted;

  else
    raise exception 'Operazione di scrittura provider non riconosciuta: %.', v_operation;
  end if;

  return coalesce(v_result, jsonb_build_object('count', 0));
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

create or replace function public.heartbeat_provider_sync_run_guarded_v2(
  p_run_id uuid,
  p_records_processed integer,
  p_progress_phase text,
  p_progress_current integer,
  p_progress_total integer default null,
  p_expected_revision bigint default null,
  p_lease_token uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_check jsonb;
  v_run jsonb;
  v_lease public.provider_sync_worker_leases%rowtype;
  v_seconds integer;
begin
  v_check := public.assert_provider_sync_worker_lease_v1(
    p_run_id,
    p_lease_token
  );

  v_run := public.heartbeat_provider_sync_run_guarded_v1(
    p_run_id,
    p_records_processed,
    p_progress_phase,
    p_progress_current,
    p_progress_total,
    p_expected_revision
  );

  select lease_row.*
  into v_lease
  from public.provider_sync_worker_leases lease_row
  where lease_row.run_id = p_run_id
  for update;

  v_seconds := public.provider_sync_worker_lease_seconds_v1(v_lease.sync_type);

  update public.provider_sync_worker_leases lease_row
  set
    last_heartbeat_at = now(),
    lease_expires_at = now() + (v_seconds * interval '1 second')
  where lease_row.id = v_lease.id
    and lease_row.status = 'active'
  returning * into v_lease;

  return v_run || jsonb_build_object(
    'workerFencing', true,
    'leaseId', v_lease.id,
    'leaseToken', v_lease.lease_token,
    'leaseEpoch', v_lease.lease_epoch,
    'leaseRevision', v_lease.revision,
    'leaseExpiresAt', v_lease.lease_expires_at,
    'lastHeartbeatAt', v_lease.last_heartbeat_at
  );
end;
$$;

revoke all on function public.heartbeat_provider_sync_run_guarded_v2(
  uuid,integer,text,integer,integer,bigint,uuid
)
from public, anon, authenticated;
grant execute on function public.heartbeat_provider_sync_run_guarded_v2(
  uuid,integer,text,integer,integer,bigint,uuid
)
to service_role;

create or replace function public.finish_provider_sync_run_guarded_v2(
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
  v_run public.provider_sync_runs%rowtype;
  v_lease public.provider_sync_worker_leases%rowtype;
  v_result jsonb;
begin
  select run_row.*
  into v_run
  from public.provider_sync_runs run_row
  where run_row.id = p_run_id
  for update;

  if not found then
    raise exception 'Run provider non trovato durante la chiusura fencing.';
  end if;

  select lease_row.*
  into v_lease
  from public.provider_sync_worker_leases lease_row
  where lease_row.run_id = v_run.id
  for update;

  if not found then
    raise exception 'Lease worker provider non trovata durante la chiusura.';
  end if;
  if v_lease.lease_token <> p_lease_token then
    raise exception 'Chiusura provider rifiutata: token worker non più proprietario.';
  end if;

  if v_run.status = 'running' then
    if v_lease.status <> 'active' then
      raise exception 'Chiusura provider rifiutata: lease nello stato %.', v_lease.status;
    end if;
    if v_lease.lease_expires_at <= now() then
      raise exception 'Chiusura provider rifiutata: lease worker scaduta.';
    end if;
  end if;

  v_result := public.finish_provider_sync_run_guarded_v1(
    p_run_id,
    p_status,
    p_records_processed,
    p_error_message,
    p_expected_revision
  );

  select lease_row.*
  into v_lease
  from public.provider_sync_worker_leases lease_row
  where lease_row.run_id = v_run.id;

  return v_result || jsonb_build_object(
    'workerFencing', true,
    'leaseId', v_lease.id,
    'leaseEpoch', v_lease.lease_epoch,
    'leaseRevision', v_lease.revision,
    'leaseExpiresAt', v_lease.lease_expires_at,
    'lastHeartbeatAt', v_lease.last_heartbeat_at,
    'leaseStatus', v_lease.status
  );
end;
$$;

revoke all on function public.finish_provider_sync_run_guarded_v2(
  uuid,text,integer,text,bigint,uuid
)
from public, anon, authenticated;
grant execute on function public.finish_provider_sync_run_guarded_v2(
  uuid,text,integer,text,bigint,uuid
)
to service_role;

create or replace function public.close_provider_sync_worker_lease_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.status not in ('completed', 'failed')
    or new.status is not distinct from old.status then
    return new;
  end if;

  update public.provider_sync_worker_leases lease_row
  set
    status = case when new.status = 'completed' then 'released' else 'revoked' end,
    revoke_reason = case
      when new.status = 'failed' then left(
        coalesce(nullif(trim(new.error_message), ''), 'Run provider concluso con errore.'),
        500
      )
      else null
    end,
    released_at = coalesce(new.finished_at, now())
  where lease_row.run_id = new.id
    and lease_row.status = 'active';

  return new;
end;
$$;

revoke all on function public.close_provider_sync_worker_lease_v1()
from public, anon, authenticated;

drop trigger if exists zz_provider_sync_worker_lease_closer
on public.provider_sync_runs;
create trigger zz_provider_sync_worker_lease_closer
after update of status on public.provider_sync_runs
for each row execute function public.close_provider_sync_worker_lease_v1();

create or replace function public.expire_stale_provider_sync_worker_leases_v1(
  p_run_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_candidate record;
  v_run public.provider_sync_runs%rowtype;
  v_lease public.provider_sync_worker_leases%rowtype;
  v_expired_count integer := 0;
  v_error text;
begin
  for v_candidate in
    select lease_row.run_id
    from public.provider_sync_worker_leases lease_row
    where lease_row.status = 'active'
      and lease_row.lease_expires_at <= now()
      and (p_run_id is null or lease_row.run_id = p_run_id)
    order by lease_row.lease_expires_at asc
  loop
    select run_row.*
    into v_run
    from public.provider_sync_runs run_row
    where run_row.id = v_candidate.run_id
    for update;

    select lease_row.*
    into v_lease
    from public.provider_sync_worker_leases lease_row
    where lease_row.run_id = v_candidate.run_id
    for update;

    if not found
      or v_lease.status <> 'active'
      or v_lease.lease_expires_at > now() then
      continue;
    end if;

    v_error := left(
      format(
        'Fencing provider: lease worker scaduta alle %s; esecuzione revocata.',
        v_lease.lease_expires_at
      ),
      500
    );

    update public.provider_sync_worker_leases lease_row
    set
      status = 'expired',
      revoke_reason = v_error,
      released_at = now()
    where lease_row.id = v_lease.id
      and lease_row.status = 'active';

    if v_run.id is not null and v_run.status = 'running' then
      perform public.finish_provider_sync_run_guarded_v1(
        v_run.id,
        'failed',
        greatest(coalesce(v_run.records_processed, 0), 0),
        v_error,
        v_run.revision
      );
    end if;

    v_expired_count := v_expired_count + 1;
  end loop;

  return jsonb_build_object(
    'expiredCount', v_expired_count,
    'checkedAt', now()
  );
end;
$$;

revoke all on function public.expire_stale_provider_sync_worker_leases_v1(uuid)
from public, anon, authenticated;
grant execute on function public.expire_stale_provider_sync_worker_leases_v1(uuid)
to service_role;

create or replace function public.start_provider_sync_run_guarded_v2(
  p_request jsonb,
  p_lease_token uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_run jsonb;
  v_lease jsonb;
  v_execute boolean;
begin
  perform public.expire_stale_provider_sync_worker_leases_v1(null);
  v_run := public.start_provider_sync_run_guarded_v1(p_request);

  if coalesce(v_run ->> 'status', '') <> 'running' then
    return v_run || jsonb_build_object(
      'execute', false,
      'workerFencing', true
    );
  end if;

  v_lease := public.acquire_provider_sync_worker_lease_v1(
    (v_run ->> 'runId')::uuid,
    p_lease_token,
    null
  );

  v_execute := coalesce((v_lease ->> 'granted')::boolean, false)
    and not coalesce((v_run ->> 'reused')::boolean, false);

  return v_run || jsonb_build_object(
    'execute', v_execute,
    'workerFencing', true,
    'leaseId', v_lease ->> 'leaseId',
    'leaseToken', case
      when coalesce((v_lease ->> 'granted')::boolean, false)
        then v_lease ->> 'leaseToken'
      else null
    end,
    'leaseEpoch', nullif(v_lease ->> 'leaseEpoch', '')::bigint,
    'leaseRevision', nullif(v_lease ->> 'leaseRevision', '')::bigint,
    'leaseExpiresAt', v_lease ->> 'leaseExpiresAt',
    'lastHeartbeatAt', v_lease ->> 'lastHeartbeatAt',
    'leaseStatus', v_lease ->> 'status'
  );
end;
$$;

revoke all on function public.start_provider_sync_run_guarded_v2(jsonb,uuid)
from public, anon, authenticated;
grant execute on function public.start_provider_sync_run_guarded_v2(jsonb,uuid)
to service_role;

create or replace function public.claim_provider_recovery_request_v3(
  p_request_id uuid,
  p_expected_revision bigint default null,
  p_lease_token uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_claim jsonb;
  v_run jsonb;
  v_lease jsonb;
  v_execute boolean;
begin
  if p_lease_token is null then
    raise exception 'Token worker obbligatorio per il recupero provider.';
  end if;

  perform public.expire_stale_provider_sync_worker_leases_v1(null);

  v_claim := public.claim_provider_recovery_request_v2(
    p_request_id,
    p_expected_revision
  );
  v_run := v_claim -> 'run';

  if v_run is null
    or jsonb_typeof(v_run) is distinct from 'object'
    or coalesce(v_run ->> 'status', '') <> 'running' then
    return v_claim || jsonb_build_object(
      'execute', false,
      'workerFencing', true
    );
  end if;

  v_lease := public.acquire_provider_sync_worker_lease_v1(
    (v_run ->> 'runId')::uuid,
    p_lease_token,
    p_request_id
  );

  v_execute := coalesce((v_claim ->> 'execute')::boolean, false)
    and coalesce((v_lease ->> 'granted')::boolean, false);

  return v_claim || jsonb_build_object(
    'execute', v_execute,
    'workerFencing', true,
    'run', v_run || jsonb_build_object(
      'leaseId', v_lease ->> 'leaseId',
      'leaseToken', case
        when coalesce((v_lease ->> 'granted')::boolean, false)
          then v_lease ->> 'leaseToken'
        else null
      end,
      'leaseEpoch', nullif(v_lease ->> 'leaseEpoch', '')::bigint,
      'leaseRevision', nullif(v_lease ->> 'leaseRevision', '')::bigint,
      'leaseExpiresAt', v_lease ->> 'leaseExpiresAt',
      'lastHeartbeatAt', v_lease ->> 'lastHeartbeatAt',
      'leaseStatus', v_lease ->> 'status'
    )
  );
end;
$$;

revoke all on function public.claim_provider_recovery_request_v3(
  uuid,bigint,uuid
)
from public, anon, authenticated;
grant execute on function public.claim_provider_recovery_request_v3(
  uuid,bigint,uuid
)
to service_role;

create or replace function public.claim_next_provider_recovery_request_v4(
  p_lease_token uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_claim jsonb;
  v_run jsonb;
  v_lease jsonb;
  v_execute boolean;
begin
  if p_lease_token is null then
    raise exception 'Token worker obbligatorio per la coda recuperi provider.';
  end if;

  perform public.expire_stale_provider_sync_worker_leases_v1(null);
  v_claim := public.claim_next_provider_recovery_request_v3();

  if coalesce((v_claim ->> 'empty')::boolean, false) then
    return v_claim || jsonb_build_object('workerFencing', true);
  end if;

  v_run := v_claim -> 'run';
  if v_run is null
    or jsonb_typeof(v_run) is distinct from 'object'
    or coalesce(v_run ->> 'status', '') <> 'running' then
    return v_claim || jsonb_build_object(
      'execute', false,
      'workerFencing', true
    );
  end if;

  v_lease := public.acquire_provider_sync_worker_lease_v1(
    (v_run ->> 'runId')::uuid,
    p_lease_token,
    (v_claim ->> 'requestId')::uuid
  );
  v_execute := coalesce((v_claim ->> 'execute')::boolean, false)
    and coalesce((v_lease ->> 'granted')::boolean, false);

  return v_claim || jsonb_build_object(
    'empty', false,
    'execute', v_execute,
    'workerFencing', true,
    'run', v_run || jsonb_build_object(
      'leaseId', v_lease ->> 'leaseId',
      'leaseToken', case
        when coalesce((v_lease ->> 'granted')::boolean, false)
          then v_lease ->> 'leaseToken'
        else null
      end,
      'leaseEpoch', nullif(v_lease ->> 'leaseEpoch', '')::bigint,
      'leaseRevision', nullif(v_lease ->> 'leaseRevision', '')::bigint,
      'leaseExpiresAt', v_lease ->> 'leaseExpiresAt',
      'lastHeartbeatAt', v_lease ->> 'lastHeartbeatAt',
      'leaseStatus', v_lease ->> 'status'
    )
  );
end;
$$;

revoke all on function public.claim_next_provider_recovery_request_v4(uuid)
from public, anon, authenticated;
grant execute on function public.claim_next_provider_recovery_request_v4(uuid)
to service_role;

create or replace function public.get_league_provider_worker_lease_center_v1(
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
  v_active_count integer := 0;
  v_expired_count integer := 0;
  v_released_last_24h integer := 0;
  v_revoked_last_24h integer := 0;
  v_latest_heartbeat_at timestamptz;
  v_latest jsonb;
begin
  select league_row.owner_id
  into v_owner_id
  from public.leagues league_row
  where league_row.id = p_league_id;

  if not found then
    raise exception 'Lega non trovata.';
  end if;
  if auth.uid() is null
    or (v_owner_id <> auth.uid() and not public.is_league_admin(p_league_id)) then
    raise exception 'Solo Presidente e Admin possono leggere il fencing provider.';
  end if;

  select
    count(*) filter (
      where lease_row.status = 'active'
        and lease_row.lease_expires_at > now()
    )::integer,
    count(*) filter (
      where lease_row.status = 'active'
        and lease_row.lease_expires_at <= now()
    )::integer,
    count(*) filter (
      where lease_row.status = 'released'
        and lease_row.released_at >= now() - interval '24 hours'
    )::integer,
    count(*) filter (
      where lease_row.status in ('revoked', 'expired')
        and lease_row.released_at >= now() - interval '24 hours'
    )::integer,
    max(lease_row.last_heartbeat_at)
  into
    v_active_count,
    v_expired_count,
    v_released_last_24h,
    v_revoked_last_24h,
    v_latest_heartbeat_at
  from public.provider_sync_worker_leases lease_row
  where lease_row.league_id = p_league_id;

  select jsonb_build_object(
    'runId', lease_row.run_id,
    'requestId', lease_row.recovery_request_id,
    'syncType', lease_row.sync_type,
    'status', case
      when lease_row.status = 'active' and lease_row.lease_expires_at <= now()
        then 'expired'
      else lease_row.status
    end,
    'leaseEpoch', lease_row.lease_epoch,
    'revision', lease_row.revision,
    'leaseExpiresAt', lease_row.lease_expires_at,
    'lastHeartbeatAt', lease_row.last_heartbeat_at
  )
  into v_latest
  from public.provider_sync_worker_leases lease_row
  where lease_row.league_id = p_league_id
  order by lease_row.updated_at desc
  limit 1;

  return jsonb_build_object(
    'protected', true,
    'healthy', coalesce(v_expired_count, 0) = 0,
    'workerFencingActive', true,
    'activeLeaseCount', coalesce(v_active_count, 0),
    'expiredLeaseCount', coalesce(v_expired_count, 0),
    'releasedLast24h', coalesce(v_released_last_24h, 0),
    'revokedLast24h', coalesce(v_revoked_last_24h, 0),
    'latestHeartbeatAt', v_latest_heartbeat_at,
    'latest', v_latest
  );
end;
$$;

revoke all on function public.get_league_provider_worker_lease_center_v1(uuid)
from public, anon, authenticated;
grant execute on function public.get_league_provider_worker_lease_center_v1(uuid)
to authenticated;

create or replace function public.get_league_provider_recovery_center_v7(
  p_league_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_center jsonb;
  v_fencing jsonb;
  v_healthy boolean;
begin
  v_center := public.get_league_provider_recovery_center_v6(p_league_id);
  v_fencing := public.get_league_provider_worker_lease_center_v1(p_league_id);
  v_healthy := coalesce((v_center ->> 'healthy')::boolean, false)
    and coalesce((v_fencing ->> 'healthy')::boolean, false);

  return v_center || jsonb_build_object(
    'healthy', v_healthy,
    'workerFencing', v_fencing
  );
end;
$$;

revoke all on function public.get_league_provider_recovery_center_v7(uuid)
from public, anon, authenticated;
grant execute on function public.get_league_provider_recovery_center_v7(uuid)
to authenticated;

create or replace function public.get_league_provider_sync_health_v10(
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
  v_recovery jsonb;
  v_healthy boolean;
  v_status text;
begin
  v_health := public.get_league_provider_sync_health_v9(p_league_id);
  v_recovery := public.get_league_provider_recovery_center_v7(p_league_id);
  v_healthy := coalesce((v_health ->> 'healthy')::boolean, false)
    and coalesce((v_recovery ->> 'healthy')::boolean, false);
  v_status := case
    when not v_healthy then 'attention'
    else coalesce(v_health ->> 'status', 'idle')
  end;

  return v_health || jsonb_build_object(
    'healthy', v_healthy,
    'status', v_status,
    'recoveryCenter', v_recovery
  );
end;
$$;

revoke all on function public.get_league_provider_sync_health_v10(uuid)
from public, anon, authenticated;
grant execute on function public.get_league_provider_sync_health_v10(uuid)
to authenticated;

-- Gli eventi non contengono token; la tabella lease non viene pubblicata.
do $realtime$
begin
  if exists (
    select 1
    from pg_catalog.pg_publication publication_row
    where publication_row.pubname = 'supabase_realtime'
  ) and not exists (
    select 1
    from pg_catalog.pg_publication_tables publication_table
    where publication_table.pubname = 'supabase_realtime'
      and publication_table.schemaname = 'public'
      and publication_table.tablename = 'provider_sync_worker_lease_events'
  ) then
    alter publication supabase_realtime
      add table public.provider_sync_worker_lease_events;
  end if;
end;
$realtime$;

create or replace function public.get_provider_worker_lease_fencing_integrity_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_previous jsonb;
  v_previous_ready boolean := false;
begin
  v_previous := public.get_provider_recovery_outcome_verification_integrity_v1();
  select not exists (
    select 1
    from jsonb_each(v_previous) check_row
    where check_row.value is distinct from 'true'::jsonb
  ) into v_previous_ready;

  return jsonb_build_object(
    'predecessor_ready', v_previous_ready,
    'lease_table_ready',
      to_regclass('public.provider_sync_worker_leases') is not null,
    'lease_columns_ready',
      (
        select count(*) = 16
        from information_schema.columns column_row
        where column_row.table_schema = 'public'
          and column_row.table_name = 'provider_sync_worker_leases'
          and column_row.column_name in (
            'id', 'run_id', 'recovery_request_id', 'league_id', 'provider',
            'sync_type', 'lease_token', 'lease_epoch', 'status',
            'lease_expires_at', 'last_heartbeat_at', 'revision',
            'revoke_reason', 'acquired_at', 'released_at', 'updated_at'
          )
      ),
    'lease_constraints_ready',
      exists (
        select 1
        from pg_catalog.pg_constraint constraint_row
        where constraint_row.conrelid =
          'public.provider_sync_worker_leases'::regclass
          and constraint_row.contype = 'u'
          and pg_get_constraintdef(constraint_row.oid) like '%run_id%'
      )
      and exists (
        select 1
        from pg_catalog.pg_constraint constraint_row
        where constraint_row.conrelid =
          'public.provider_sync_worker_leases'::regclass
          and constraint_row.contype = 'u'
          and pg_get_constraintdef(constraint_row.oid) like '%lease_token%'
      ),
    'lease_indexes_ready',
      to_regclass('public.provider_sync_worker_leases_league_idx') is not null
      and to_regclass('public.provider_sync_worker_leases_active_expiry_idx') is not null
      and to_regclass('public.provider_sync_worker_leases_request_idx') is not null,
    'lease_rls_privileges_ready',
      exists (
        select 1
        from pg_catalog.pg_class class_row
        where class_row.oid = 'public.provider_sync_worker_leases'::regclass
          and class_row.relrowsecurity
          and class_row.relreplident = 'f'
      )
      and not has_table_privilege(
        'authenticated', 'public.provider_sync_worker_leases', 'SELECT'
      )
      and has_table_privilege(
        'service_role', 'public.provider_sync_worker_leases', 'UPDATE'
      ),
    'lease_event_protection_ready',
      to_regclass('public.provider_sync_worker_lease_events') is not null
      and exists (
        select 1
        from pg_catalog.pg_trigger trigger_row
        where trigger_row.tgname = 'provider_sync_worker_lease_events_immutable'
          and trigger_row.tgrelid =
            'public.provider_sync_worker_lease_events'::regclass
          and not trigger_row.tgisinternal
      )
      and has_table_privilege(
        'authenticated', 'public.provider_sync_worker_lease_events', 'SELECT'
      )
      and not has_table_privilege(
        'authenticated', 'public.provider_sync_worker_lease_events', 'INSERT'
      )
      and exists (
        select 1
        from pg_catalog.pg_policies policy_row
        where policy_row.schemaname = 'public'
          and policy_row.tablename = 'provider_sync_worker_lease_events'
          and policy_row.policyname = 'provider_sync_worker_lease_events_read_directors'
          and policy_row.cmd = 'SELECT'
      ),
    'lease_policy_ready',
      to_regprocedure(
        'public.provider_sync_worker_lease_seconds_v1(text)'
      ) is not null
      and public.provider_sync_worker_lease_seconds_v1('sync-fixture-players') = 300
      and public.provider_sync_worker_lease_seconds_v1('sync-fixtures') = 300
      and public.provider_sync_worker_lease_seconds_v1('sync-season-players') = 600,
    'lease_revision_events_ready',
      to_regprocedure('public.prepare_provider_sync_worker_lease_v1()') is not null
      and to_regprocedure('public.record_provider_sync_worker_lease_event_v1()') is not null
      and exists (
        select 1
        from pg_catalog.pg_trigger trigger_row
        where trigger_row.tgname = 'provider_sync_worker_lease_revision_guard'
          and trigger_row.tgrelid = 'public.provider_sync_worker_leases'::regclass
          and not trigger_row.tgisinternal
      )
      and exists (
        select 1
        from pg_catalog.pg_trigger trigger_row
        where trigger_row.tgname = 'provider_sync_worker_lease_event_writer'
          and trigger_row.tgrelid = 'public.provider_sync_worker_leases'::regclass
          and not trigger_row.tgisinternal
      ),
    'lease_acquire_rpc_ready',
      to_regprocedure(
        'public.acquire_provider_sync_worker_lease_v1(uuid,uuid,uuid)'
      ) is not null
      and has_function_privilege(
        'service_role',
        'public.acquire_provider_sync_worker_lease_v1(uuid,uuid,uuid)',
        'EXECUTE'
      )
      and not has_function_privilege(
        'authenticated',
        'public.acquire_provider_sync_worker_lease_v1(uuid,uuid,uuid)',
        'EXECUTE'
      ),
    'lease_assert_rpc_ready',
      to_regprocedure(
        'public.assert_provider_sync_worker_lease_v1(uuid,uuid)'
      ) is not null
      and has_function_privilege(
        'service_role',
        'public.assert_provider_sync_worker_lease_v1(uuid,uuid)',
        'EXECUTE'
      )
      and to_regprocedure(
        'public.apply_provider_sync_write_guarded_v1(uuid,uuid,text,jsonb)'
      ) is not null
      and has_function_privilege(
        'service_role',
        'public.apply_provider_sync_write_guarded_v1(uuid,uuid,text,jsonb)',
        'EXECUTE'
      )
      and not has_function_privilege(
        'authenticated',
        'public.apply_provider_sync_write_guarded_v1(uuid,uuid,text,jsonb)',
        'EXECUTE'
      ),
    'heartbeat_v2_ready',
      to_regprocedure(
        'public.heartbeat_provider_sync_run_guarded_v2(uuid,integer,text,integer,integer,bigint,uuid)'
      ) is not null
      and has_function_privilege(
        'service_role',
        'public.heartbeat_provider_sync_run_guarded_v2(uuid,integer,text,integer,integer,bigint,uuid)',
        'EXECUTE'
      ),
    'finish_v2_ready',
      to_regprocedure(
        'public.finish_provider_sync_run_guarded_v2(uuid,text,integer,text,bigint,uuid)'
      ) is not null
      and has_function_privilege(
        'service_role',
        'public.finish_provider_sync_run_guarded_v2(uuid,text,integer,text,bigint,uuid)',
        'EXECUTE'
      ),
    'terminal_closer_ready',
      to_regprocedure('public.close_provider_sync_worker_lease_v1()') is not null
      and exists (
        select 1
        from pg_catalog.pg_trigger trigger_row
        where trigger_row.tgname = 'zz_provider_sync_worker_lease_closer'
          and trigger_row.tgrelid = 'public.provider_sync_runs'::regclass
          and not trigger_row.tgisinternal
      ),
    'lease_expiry_rpc_ready',
      to_regprocedure(
        'public.expire_stale_provider_sync_worker_leases_v1(uuid)'
      ) is not null
      and has_function_privilege(
        'service_role',
        'public.expire_stale_provider_sync_worker_leases_v1(uuid)',
        'EXECUTE'
      ),
    'guarded_start_claim_ready',
      to_regprocedure(
        'public.start_provider_sync_run_guarded_v2(jsonb,uuid)'
      ) is not null
      and to_regprocedure(
        'public.claim_provider_recovery_request_v3(uuid,bigint,uuid)'
      ) is not null
      and to_regprocedure(
        'public.claim_next_provider_recovery_request_v4(uuid)'
      ) is not null,
    'lease_center_ready',
      to_regprocedure(
        'public.get_league_provider_worker_lease_center_v1(uuid)'
      ) is not null
      and has_function_privilege(
        'authenticated',
        'public.get_league_provider_worker_lease_center_v1(uuid)',
        'EXECUTE'
      ),
    'recovery_center_v7_ready',
      to_regprocedure(
        'public.get_league_provider_recovery_center_v7(uuid)'
      ) is not null
      and has_function_privilege(
        'authenticated',
        'public.get_league_provider_recovery_center_v7(uuid)',
        'EXECUTE'
      ),
    'sync_health_v10_ready',
      to_regprocedure(
        'public.get_league_provider_sync_health_v10(uuid)'
      ) is not null
      and has_function_privilege(
        'authenticated',
        'public.get_league_provider_sync_health_v10(uuid)',
        'EXECUTE'
      ),
    'runtime_consistency_ready',
      exists (
        select 1
        from pg_catalog.pg_publication_tables publication_table
        where publication_table.pubname = 'supabase_realtime'
          and publication_table.schemaname = 'public'
          and publication_table.tablename = 'provider_sync_worker_lease_events'
      )
      and not exists (
        select 1
        from public.provider_sync_worker_leases lease_row
        left join public.provider_sync_runs run_row on run_row.id = lease_row.run_id
        left join public.provider_recovery_requests request_row
          on request_row.id = lease_row.recovery_request_id
        where run_row.id is null
          or lease_row.provider <> run_row.provider
          or lease_row.sync_type <> run_row.sync_type
          or (
            lease_row.recovery_request_id is not null
            and (
              request_row.id is null
              or request_row.recovery_run_id is distinct from lease_row.run_id
              or request_row.league_id is distinct from lease_row.league_id
            )
          )
          or (
            lease_row.status = 'active'
            and run_row.status <> 'running'
          )
      )
  );
end;
$$;

revoke all on function public.get_provider_worker_lease_fencing_integrity_v1()
from public, anon, authenticated;
grant execute on function public.get_provider_worker_lease_fencing_integrity_v1()
to authenticated, service_role;

-- Arresta la transazione indicando i nomi esatti degli eventuali controlli falsi.
do $validation$
declare
  v_checks jsonb;
  v_failed text[];
begin
  v_checks := public.get_provider_worker_lease_fencing_integrity_v1();

  select array_agg(check_row.key order by check_row.key)
  into v_failed
  from jsonb_each(v_checks) check_row
  where check_row.value is distinct from 'true'::jsonb;

  if coalesce(array_length(v_failed, 1), 0) > 0 then
    raise exception
      'Validazione v0.62.11 non superata. Controlli falsi: %',
      array_to_string(v_failed, '; ');
  end if;
end;
$validation$;

commit;

-- Diagnostica finale: devono comparire esattamente 20 valori true.
select
  (checks ->> 'predecessor_ready')::boolean as predecessor_ready,
  (checks ->> 'lease_table_ready')::boolean as lease_table_ready,
  (checks ->> 'lease_columns_ready')::boolean as lease_columns_ready,
  (checks ->> 'lease_constraints_ready')::boolean as lease_constraints_ready,
  (checks ->> 'lease_indexes_ready')::boolean as lease_indexes_ready,
  (checks ->> 'lease_rls_privileges_ready')::boolean as lease_rls_privileges_ready,
  (checks ->> 'lease_event_protection_ready')::boolean as lease_event_protection_ready,
  (checks ->> 'lease_policy_ready')::boolean as lease_policy_ready,
  (checks ->> 'lease_revision_events_ready')::boolean as lease_revision_events_ready,
  (checks ->> 'lease_acquire_rpc_ready')::boolean as lease_acquire_rpc_ready,
  (checks ->> 'lease_assert_rpc_ready')::boolean as lease_assert_rpc_ready,
  (checks ->> 'heartbeat_v2_ready')::boolean as heartbeat_v2_ready,
  (checks ->> 'finish_v2_ready')::boolean as finish_v2_ready,
  (checks ->> 'terminal_closer_ready')::boolean as terminal_closer_ready,
  (checks ->> 'lease_expiry_rpc_ready')::boolean as lease_expiry_rpc_ready,
  (checks ->> 'guarded_start_claim_ready')::boolean as guarded_start_claim_ready,
  (checks ->> 'lease_center_ready')::boolean as lease_center_ready,
  (checks ->> 'recovery_center_v7_ready')::boolean as recovery_center_v7_ready,
  (checks ->> 'sync_health_v10_ready')::boolean as sync_health_v10_ready,
  (checks ->> 'runtime_consistency_ready')::boolean as runtime_consistency_ready
from (
  select public.get_provider_worker_lease_fencing_integrity_v1() as checks
) diagnostic;
