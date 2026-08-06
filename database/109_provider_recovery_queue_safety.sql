-- LEGHEVO v0.62.5 · Recupero operativo provider protetto
-- Migrazione interna: database/109_provider_recovery_queue_safety.sql
--
-- Obiettivi:
-- - accodare in modo atomico e idempotente il recupero di un incidente provider;
-- - impedire richieste concorrenti per lo stesso incidente;
-- - collegare ogni recupero a un nuovo run provider certificato;
-- - aggiornare automaticamente l'esito della richiesta quando termina il run;
-- - conservare uno storico immutabile delle revisioni;
-- - esporre stato e azione protetta nel Centro Operativo;
-- - diagnostica strutturale finale di 20 controlli.

begin;

-- Preflight esclusivamente strutturale. Nessuna scrittura viene applicata se
-- manca una dipendenza validata nelle versioni v0.62.2-v0.62.4.
do $preflight$
declare
  v_missing text[] := array[]::text[];
  v_expected record;
begin
  for v_expected in
    select *
    from (values
      ('provider_operational_incidents', 'id'),
      ('provider_operational_incidents', 'provider'),
      ('provider_operational_incidents', 'sync_type'),
      ('provider_operational_incidents', 'severity'),
      ('provider_operational_incidents', 'status'),
      ('provider_operational_incidents', 'revision'),
      ('provider_operational_incidents', 'source_run_id'),
      ('provider_operational_incidents', 'source_snapshot_id'),
      ('provider_operational_incidents', 'summary'),
      ('provider_operational_incidents', 'last_detected_at'),
      ('provider_sync_runs', 'id'),
      ('provider_sync_runs', 'provider'),
      ('provider_sync_runs', 'sync_type'),
      ('provider_sync_runs', 'requested_for'),
      ('provider_sync_runs', 'status'),
      ('provider_sync_runs', 'revision'),
      ('provider_sync_runs', 'attempt_no'),
      ('provider_sync_runs', 'records_processed'),
      ('provider_sync_runs', 'request_key'),
      ('provider_sync_runs', 'error_message'),
      ('provider_sync_runs', 'started_at'),
      ('provider_sync_runs', 'finished_at'),
      ('provider_data_quality_snapshots', 'id'),
      ('provider_data_quality_snapshots', 'run_id'),
      ('leagues', 'id'),
      ('leagues', 'owner_id')
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

  if to_regprocedure('public.is_league_admin(uuid)') is null then
    v_missing := array_append(v_missing, 'function public.is_league_admin(uuid)');
  end if;
  if to_regprocedure('public.normalize_provider_sync_request_v1(jsonb)') is null then
    v_missing := array_append(
      v_missing,
      'function public.normalize_provider_sync_request_v1(jsonb)'
    );
  end if;
  if to_regprocedure('public.provider_sync_request_bucket_v1(text,timestamptz)') is null then
    v_missing := array_append(
      v_missing,
      'function public.provider_sync_request_bucket_v1(text,timestamptz)'
    );
  end if;
  if to_regprocedure('public.get_league_provider_sync_health_v3(uuid)') is null then
    v_missing := array_append(
      v_missing,
      'function public.get_league_provider_sync_health_v3(uuid)'
    );
  end if;

  if coalesce(array_length(v_missing, 1), 0) > 0 then
    raise exception
      'Preflight v0.62.5 non superato. Oggetti mancanti: %',
      array_to_string(v_missing, '; ');
  end if;
end;
$preflight$;

create table if not exists public.provider_recovery_requests (
  id uuid primary key default gen_random_uuid(),
  league_id uuid not null references public.leagues(id) on delete cascade,
  incident_id uuid not null
    references public.provider_operational_incidents(id) on delete cascade,
  provider text not null,
  sync_type text not null,
  requested_for jsonb not null check (jsonb_typeof(requested_for) = 'object'),
  requested_by uuid references auth.users(id) on delete set null,
  idempotency_key uuid not null,
  status text not null default 'pending' check (
    status in ('pending', 'running', 'completed', 'failed', 'cancelled')
  ),
  source_run_id uuid references public.provider_sync_runs(id) on delete set null,
  recovery_run_id uuid references public.provider_sync_runs(id) on delete set null,
  expected_incident_revision bigint not null check (expected_incident_revision > 0),
  revision bigint not null default 1 check (revision > 0),
  attempt_no integer not null default 0 check (attempt_no >= 0),
  error_summary text,
  request_fingerprint text not null check (char_length(request_fingerprint) = 32),
  result_fingerprint text check (
    result_fingerprint is null or char_length(result_fingerprint) = 32
  ),
  requested_at timestamptz not null default now(),
  started_at timestamptz,
  finished_at timestamptz,
  updated_at timestamptz not null default now(),
  unique (requested_by, idempotency_key),
  check (
    (status = 'pending' and started_at is null and finished_at is null)
    or (status = 'running' and started_at is not null and finished_at is null)
    or (status in ('completed', 'failed') and started_at is not null and finished_at is not null)
    or (status = 'cancelled' and finished_at is not null)
  )
);

create unique index if not exists provider_recovery_requests_active_incident_uidx
  on public.provider_recovery_requests (incident_id)
  where status in ('pending', 'running');
create index if not exists provider_recovery_requests_league_latest_idx
  on public.provider_recovery_requests (league_id, requested_at desc);
create index if not exists provider_recovery_requests_status_idx
  on public.provider_recovery_requests (provider, status, updated_at desc);

create table if not exists public.provider_recovery_request_events (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null
    references public.provider_recovery_requests(id) on delete cascade,
  league_id uuid not null references public.leagues(id) on delete cascade,
  incident_id uuid not null
    references public.provider_operational_incidents(id) on delete cascade,
  event_type text not null check (
    event_type in ('requested', 'started', 'updated', 'completed', 'failed', 'cancelled')
  ),
  status text not null check (
    status in ('pending', 'running', 'completed', 'failed', 'cancelled')
  ),
  revision bigint not null check (revision > 0),
  attempt_no integer not null check (attempt_no >= 0),
  recovery_run_id uuid references public.provider_sync_runs(id) on delete set null,
  event_fingerprint text not null check (char_length(event_fingerprint) = 32),
  created_at timestamptz not null default now(),
  unique (request_id, revision)
);

create index if not exists provider_recovery_request_events_latest_idx
  on public.provider_recovery_request_events (league_id, created_at desc);
create index if not exists provider_recovery_request_events_incident_idx
  on public.provider_recovery_request_events (incident_id, created_at desc);

alter table public.provider_recovery_requests enable row level security;
alter table public.provider_recovery_requests replica identity full;
alter table public.provider_recovery_request_events enable row level security;
alter table public.provider_recovery_request_events replica identity full;

revoke all on table public.provider_recovery_requests
from public, anon, authenticated;
revoke all on table public.provider_recovery_request_events
from public, anon, authenticated;

grant select on table public.provider_recovery_requests to authenticated;
grant select on table public.provider_recovery_request_events to authenticated;
grant select, insert, update on table public.provider_recovery_requests
  to service_role;
grant select, insert on table public.provider_recovery_request_events
  to service_role;

drop policy if exists provider_recovery_requests_read_directors
on public.provider_recovery_requests;
create policy provider_recovery_requests_read_directors
on public.provider_recovery_requests
for select to authenticated
using (
  exists (
    select 1
    from public.leagues league_row
    where league_row.id = provider_recovery_requests.league_id
      and (
        league_row.owner_id = auth.uid()
        or public.is_league_admin(league_row.id)
      )
  )
);

drop policy if exists provider_recovery_request_events_read_directors
on public.provider_recovery_request_events;
create policy provider_recovery_request_events_read_directors
on public.provider_recovery_request_events
for select to authenticated
using (
  exists (
    select 1
    from public.leagues league_row
    where league_row.id = provider_recovery_request_events.league_id
      and (
        league_row.owner_id = auth.uid()
        or public.is_league_admin(league_row.id)
      )
  )
);

create or replace function public.prepare_provider_recovery_request_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_requester_anonymization boolean := false;
begin
  if tg_op = 'INSERT' then
    new.provider := lower(trim(coalesce(new.provider, '')));
    new.sync_type := lower(trim(coalesce(new.sync_type, '')));
    if new.provider = '' or new.sync_type = '' then
      raise exception 'Identità della richiesta di recupero provider non valida.';
    end if;
    if jsonb_typeof(new.requested_for) is distinct from 'object' then
      raise exception 'Payload di recupero provider non valido.';
    end if;
    if new.requested_by is null or new.idempotency_key is null then
      raise exception 'Richiesta di recupero priva di identità idempotente.';
    end if;
    if new.status <> 'pending' then
      raise exception 'Una richiesta di recupero deve iniziare nello stato pending.';
    end if;

    new.revision := 1;
    new.attempt_no := 0;
    new.error_summary := null;
    new.result_fingerprint := null;
    new.requested_at := coalesce(new.requested_at, now());
    new.started_at := null;
    new.finished_at := null;
    new.updated_at := new.requested_at;
    new.request_fingerprint := pg_catalog.md5(
      new.league_id::text || E'\n'
      || new.incident_id::text || E'\n'
      || new.requested_by::text || E'\n'
      || new.idempotency_key::text || E'\n'
      || new.provider || E'\n'
      || new.sync_type || E'\n'
      || new.requested_for::text || E'\n'
      || new.expected_incident_revision::text
    );
    return new;
  end if;

  if row(
    new.league_id,
    new.incident_id,
    new.provider,
    new.sync_type,
    new.requested_for,
    new.idempotency_key,
    new.source_run_id,
    new.expected_incident_revision,
    new.request_fingerprint,
    new.requested_at
  ) is distinct from row(
    old.league_id,
    old.incident_id,
    old.provider,
    old.sync_type,
    old.requested_for,
    old.idempotency_key,
    old.source_run_id,
    old.expected_incident_revision,
    old.request_fingerprint,
    old.requested_at
  ) then
    raise exception 'Identità della richiesta di recupero non modificabile.';
  end if;

  v_requester_anonymization :=
    old.requested_by is not null
    and new.requested_by is null
    and (
      pg_trigger_depth() > 1
      or not exists (
        select 1
        from auth.users user_row
        where user_row.id = old.requested_by
      )
    );

  if new.requested_by is distinct from old.requested_by
    and not v_requester_anonymization then
    raise exception 'Autore della richiesta di recupero non modificabile.';
  end if;

  if v_requester_anonymization then
    new.revision := old.revision + 1;
    new.updated_at := now();
    return new;
  end if;

  if old.recovery_run_id is not null
    and new.recovery_run_id is distinct from old.recovery_run_id then
    raise exception 'Run di recupero già associato e non modificabile.';
  end if;

  if old.status in ('completed', 'failed', 'cancelled') then
    if row(
      new.status,
      new.recovery_run_id,
      new.attempt_no,
      new.error_summary,
      new.started_at,
      new.finished_at
    ) is not distinct from row(
      old.status,
      old.recovery_run_id,
      old.attempt_no,
      old.error_summary,
      old.started_at,
      old.finished_at
    ) then
      return old;
    end if;
    raise exception 'Richiesta di recupero già conclusa e immutabile.';
  end if;

  if old.status = 'pending'
    and new.status not in ('pending', 'running', 'completed', 'cancelled') then
    raise exception 'Transizione della richiesta di recupero non valida.';
  end if;
  if old.status = 'running'
    and new.status not in ('running', 'completed', 'failed') then
    raise exception 'Transizione del recupero in esecuzione non valida.';
  end if;

  if row(
    new.status,
    new.recovery_run_id,
    new.attempt_no,
    new.error_summary,
    new.started_at,
    new.finished_at
  ) is not distinct from row(
    old.status,
    old.recovery_run_id,
    old.attempt_no,
    old.error_summary,
    old.started_at,
    old.finished_at
  ) then
    return old;
  end if;

  new.revision := old.revision + 1;
  new.updated_at := now();
  new.attempt_no := greatest(coalesce(new.attempt_no, old.attempt_no), old.attempt_no);

  if new.status = 'pending' then
    new.started_at := null;
    new.finished_at := null;
    new.error_summary := null;
    new.result_fingerprint := null;
  elsif new.status = 'running' then
    new.started_at := coalesce(new.started_at, old.started_at, now());
    new.finished_at := null;
    new.error_summary := null;
    new.result_fingerprint := null;
  else
    if new.status in ('completed', 'failed') then
      new.started_at := coalesce(new.started_at, old.started_at, now());
    end if;
    new.finished_at := coalesce(new.finished_at, now());
    new.error_summary := case
      when new.status = 'failed' then left(
        coalesce(nullif(trim(new.error_summary), ''), 'Recupero provider non riuscito.'),
        500
      )
      when new.status = 'cancelled' then left(
        coalesce(nullif(trim(new.error_summary), ''), 'Recupero annullato prima dell’avvio.'),
        500
      )
      else null
    end;
    new.result_fingerprint := pg_catalog.md5(
      new.id::text || E'\n'
      || new.status || E'\n'
      || new.revision::text || E'\n'
      || coalesce(new.recovery_run_id::text, '') || E'\n'
      || new.attempt_no::text || E'\n'
      || coalesce(new.error_summary, '') || E'\n'
      || new.finished_at::text
    );
  end if;

  return new;
end;
$$;

revoke all on function public.prepare_provider_recovery_request_v1()
from public, anon, authenticated;

drop trigger if exists provider_recovery_request_revision_guard
on public.provider_recovery_requests;
create trigger provider_recovery_request_revision_guard
before insert or update on public.provider_recovery_requests
for each row execute function public.prepare_provider_recovery_request_v1();

create or replace function public.record_provider_recovery_request_event_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_event_type text;
begin
  if tg_op = 'INSERT' then
    v_event_type := 'requested';
  elsif new.status = 'running' and old.status = 'pending' then
    v_event_type := 'started';
  elsif new.status = 'completed' then
    v_event_type := 'completed';
  elsif new.status = 'failed' then
    v_event_type := 'failed';
  elsif new.status = 'cancelled' then
    v_event_type := 'cancelled';
  else
    v_event_type := 'updated';
  end if;

  insert into public.provider_recovery_request_events (
    request_id,
    league_id,
    incident_id,
    event_type,
    status,
    revision,
    attempt_no,
    recovery_run_id,
    event_fingerprint,
    created_at
  ) values (
    new.id,
    new.league_id,
    new.incident_id,
    v_event_type,
    new.status,
    new.revision,
    new.attempt_no,
    new.recovery_run_id,
    pg_catalog.md5(
      new.id::text || E'\n'
      || v_event_type || E'\n'
      || new.status || E'\n'
      || new.revision::text || E'\n'
      || new.attempt_no::text || E'\n'
      || coalesce(new.recovery_run_id::text, '') || E'\n'
      || coalesce(new.result_fingerprint, new.request_fingerprint)
    ),
    new.updated_at
  )
  on conflict (request_id, revision) do nothing;

  return new;
end;
$$;

revoke all on function public.record_provider_recovery_request_event_v1()
from public, anon, authenticated;

drop trigger if exists provider_recovery_request_event_writer
on public.provider_recovery_requests;
create trigger provider_recovery_request_event_writer
after insert or update on public.provider_recovery_requests
for each row execute function public.record_provider_recovery_request_event_v1();

create or replace function public.prevent_provider_recovery_event_mutation_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'DELETE'
    and (
      not exists (
        select 1
        from public.provider_recovery_requests request_row
        where request_row.id = old.request_id
      )
      or not exists (
        select 1
        from public.provider_operational_incidents incident_row
        where incident_row.id = old.incident_id
      )
      or not exists (
        select 1
        from public.leagues league_row
        where league_row.id = old.league_id
      )
    ) then
    -- Consente esclusivamente le cascate tecniche dopo la rimozione del padre.
    return old;
  end if;

  raise exception 'Evento di recupero provider certificato: modifica o cancellazione non consentita.';
end;
$$;

revoke all on function public.prevent_provider_recovery_event_mutation_v1()
from public, anon, authenticated;

drop trigger if exists provider_recovery_request_events_immutable
on public.provider_recovery_request_events;
create trigger provider_recovery_request_events_immutable
before update or delete on public.provider_recovery_request_events
for each row execute function public.prevent_provider_recovery_event_mutation_v1();

create or replace function public.request_provider_recovery_guarded_v1(
  p_league_id uuid,
  p_incident_id uuid,
  p_expected_incident_revision bigint,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_owner_id uuid;
  v_incident public.provider_operational_incidents%rowtype;
  v_source_run public.provider_sync_runs%rowtype;
  v_existing public.provider_recovery_requests%rowtype;
  v_inserted public.provider_recovery_requests%rowtype;
begin
  if v_user_id is null then
    raise exception 'Sessione non valida.';
  end if;
  if p_idempotency_key is null then
    raise exception 'Chiave idempotente del recupero obbligatoria.';
  end if;

  select league_row.owner_id
  into v_owner_id
  from public.leagues league_row
  where league_row.id = p_league_id;

  if not found then
    raise exception 'Lega non trovata.';
  end if;
  if v_owner_id <> v_user_id and not public.is_league_admin(p_league_id) then
    raise exception 'Il recupero provider è riservato alla Direzione.';
  end if;

  select request_row.*
  into v_existing
  from public.provider_recovery_requests request_row
  where request_row.league_id = p_league_id
    and request_row.requested_by = v_user_id
    and request_row.idempotency_key = p_idempotency_key
  limit 1;

  if found then
    if v_existing.incident_id <> p_incident_id then
      raise exception 'Chiave idempotente già usata per un altro incidente provider.';
    end if;
    return jsonb_build_object(
      'requestId', v_existing.id,
      'incidentId', v_existing.incident_id,
      'status', v_existing.status,
      'revision', v_existing.revision,
      'attempt', v_existing.attempt_no,
      'recoveryRunId', v_existing.recovery_run_id,
      'reused', true
    );
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext('provider-recovery:' || p_incident_id::text)
  );

  select incident_row.*
  into v_incident
  from public.provider_operational_incidents incident_row
  where incident_row.id = p_incident_id
  for update;

  if not found then
    raise exception 'Incidente provider non trovato.';
  end if;
  if v_incident.status <> 'open' then
    raise exception 'L’incidente provider risulta già risolto.';
  end if;
  if p_expected_incident_revision is not null
    and v_incident.revision <> p_expected_incident_revision then
    raise exception
      'Incidente aggiornato da un altro dispositivo. Revisione attesa %, revisione corrente %.',
      p_expected_incident_revision,
      v_incident.revision;
  end if;

  select request_row.*
  into v_existing
  from public.provider_recovery_requests request_row
  where request_row.incident_id = p_incident_id
    and request_row.status in ('pending', 'running')
  order by request_row.requested_at desc
  limit 1;

  if found then
    return jsonb_build_object(
      'requestId', v_existing.id,
      'incidentId', v_existing.incident_id,
      'status', v_existing.status,
      'revision', v_existing.revision,
      'attempt', v_existing.attempt_no,
      'recoveryRunId', v_existing.recovery_run_id,
      'reused', true
    );
  end if;

  if v_incident.source_run_id is not null then
    select run_row.*
    into v_source_run
    from public.provider_sync_runs run_row
    where run_row.id = v_incident.source_run_id;
  end if;

  if v_source_run.id is null and v_incident.source_snapshot_id is not null then
    select run_row.*
    into v_source_run
    from public.provider_data_quality_snapshots snapshot_row
    join public.provider_sync_runs run_row on run_row.id = snapshot_row.run_id
    where snapshot_row.id = v_incident.source_snapshot_id;
  end if;

  if v_source_run.id is null then
    select run_row.*
    into v_source_run
    from public.provider_sync_runs run_row
    where run_row.provider = v_incident.provider
      and run_row.sync_type = v_incident.sync_type
    order by run_row.started_at desc
    limit 1;
  end if;

  if v_source_run.id is null
    or jsonb_typeof(v_source_run.requested_for) is distinct from 'object' then
    raise exception 'Nessuna richiesta provider valida disponibile per il recupero.';
  end if;

  insert into public.provider_recovery_requests (
    league_id,
    incident_id,
    provider,
    sync_type,
    requested_for,
    requested_by,
    idempotency_key,
    status,
    source_run_id,
    expected_incident_revision
  ) values (
    p_league_id,
    v_incident.id,
    v_incident.provider,
    v_source_run.sync_type,
    v_source_run.requested_for,
    v_user_id,
    p_idempotency_key,
    'pending',
    v_source_run.id,
    v_incident.revision
  )
  returning * into v_inserted;

  return jsonb_build_object(
    'requestId', v_inserted.id,
    'incidentId', v_inserted.incident_id,
    'status', v_inserted.status,
    'revision', v_inserted.revision,
    'attempt', v_inserted.attempt_no,
    'recoveryRunId', v_inserted.recovery_run_id,
    'reused', false
  );
end;
$$;

revoke all on function public.request_provider_recovery_guarded_v1(
  uuid, uuid, bigint, uuid
) from public, anon, authenticated;
grant execute on function public.request_provider_recovery_guarded_v1(
  uuid, uuid, bigint, uuid
) to authenticated;

create or replace function public.start_provider_recovery_sync_run_v1(
  p_request_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_request public.provider_recovery_requests%rowtype;
  v_normalized jsonb;
  v_provider constant text := 'api-football';
  v_sync_type text;
  v_started_at timestamptz := now();
  v_bucket text;
  v_request_fingerprint text;
  v_request_key text;
  v_existing public.provider_sync_runs%rowtype;
  v_inserted public.provider_sync_runs%rowtype;
  v_attempt integer := 1;
begin
  select request_row.*
  into v_request
  from public.provider_recovery_requests request_row
  where request_row.id = p_request_id
  for update;

  if not found then
    raise exception 'Richiesta di recupero provider non trovata.';
  end if;
  if v_request.status <> 'pending' then
    raise exception 'La richiesta di recupero non è più in attesa.';
  end if;

  v_normalized := public.normalize_provider_sync_request_v1(v_request.requested_for);
  v_sync_type := v_normalized ->> 'action';
  v_bucket := public.provider_sync_request_bucket_v1(v_sync_type, v_started_at);
  v_request_fingerprint := pg_catalog.md5(
    v_provider || E'\n' || v_sync_type || E'\n' || v_normalized::text
  );
  v_request_key := pg_catalog.md5(v_request_fingerprint || E'\n' || v_bucket);

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext(v_request_key)
  );

  -- Un recupero riusa soltanto un run realmente in corso. Un run già
  -- completato non soddisfa una richiesta di recupero: viene creato un nuovo
  -- tentativo anche all'interno della stessa finestra temporale.
  select run_row.*
  into v_existing
  from public.provider_sync_runs run_row
  where run_row.provider = v_provider
    and run_row.request_key = v_request_key
    and run_row.status = 'running'
  order by run_row.attempt_no desc, run_row.started_at desc
  limit 1
  for update;

  if found then
    return jsonb_build_object(
      'runId', v_existing.id,
      'status', v_existing.status,
      'revision', v_existing.revision,
      'attempt', v_existing.attempt_no,
      'recordsProcessed', v_existing.records_processed,
      'requestKey', v_existing.request_key,
      'reused', true
    );
  end if;

  select coalesce(max(run_row.attempt_no), 0) + 1
  into v_attempt
  from public.provider_sync_runs run_row
  where run_row.provider = v_provider
    and run_row.request_key = v_request_key;

  insert into public.provider_sync_runs (
    provider,
    sync_type,
    requested_for,
    status,
    records_processed,
    started_at,
    request_bucket,
    request_key,
    request_fingerprint,
    attempt_no
  ) values (
    v_provider,
    v_sync_type,
    v_normalized,
    'running',
    0,
    v_started_at,
    v_bucket,
    v_request_key,
    v_request_fingerprint,
    greatest(v_attempt, 1)
  )
  returning * into v_inserted;

  return jsonb_build_object(
    'runId', v_inserted.id,
    'status', v_inserted.status,
    'revision', v_inserted.revision,
    'attempt', v_inserted.attempt_no,
    'recordsProcessed', v_inserted.records_processed,
    'requestKey', v_inserted.request_key,
    'reused', false
  );
end;
$$;

revoke all on function public.start_provider_recovery_sync_run_v1(uuid)
from public, anon, authenticated;
grant execute on function public.start_provider_recovery_sync_run_v1(uuid)
to service_role;

create or replace function public.claim_provider_recovery_request_v1(
  p_request_id uuid,
  p_expected_revision bigint default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_request public.provider_recovery_requests%rowtype;
  v_run public.provider_sync_runs%rowtype;
  v_started jsonb;
  v_run_id uuid;
  v_run_status text;
  v_run_revision bigint;
  v_run_attempt integer;
  v_run_records integer;
  v_run_key text;
  v_run_reused boolean;
  v_updated public.provider_recovery_requests%rowtype;
begin
  select request_row.*
  into v_request
  from public.provider_recovery_requests request_row
  where request_row.id = p_request_id
  for update;

  if not found then
    raise exception 'Richiesta di recupero provider non trovata.';
  end if;

  if p_expected_revision is not null
    and v_request.revision <> p_expected_revision then
    raise exception
      'Richiesta di recupero aggiornata da un’altra esecuzione. Revisione attesa %, revisione corrente %.',
      p_expected_revision,
      v_request.revision;
  end if;

  if v_request.status in ('completed', 'failed', 'cancelled') then
    return jsonb_build_object(
      'requestId', v_request.id,
      'status', v_request.status,
      'revision', v_request.revision,
      'requestedFor', v_request.requested_for,
      'execute', false,
      'reused', true
    );
  end if;

  if v_request.recovery_run_id is not null then
    select run_row.*
    into v_run
    from public.provider_sync_runs run_row
    where run_row.id = v_request.recovery_run_id;

    return jsonb_build_object(
      'requestId', v_request.id,
      'status', v_request.status,
      'revision', v_request.revision,
      'requestedFor', v_request.requested_for,
      'execute', false,
      'reused', true,
      'run', jsonb_build_object(
        'runId', v_run.id,
        'status', v_run.status,
        'revision', v_run.revision,
        'attempt', v_run.attempt_no,
        'recordsProcessed', v_run.records_processed,
        'requestKey', v_run.request_key,
        'reused', true
      )
    );
  end if;

  v_started := public.start_provider_recovery_sync_run_v1(v_request.id);
  v_run_id := (v_started ->> 'runId')::uuid;
  v_run_status := coalesce(v_started ->> 'status', 'running');
  v_run_revision := greatest(coalesce((v_started ->> 'revision')::bigint, 1), 1);
  v_run_attempt := greatest(coalesce((v_started ->> 'attempt')::integer, 1), 1);
  v_run_records := greatest(coalesce((v_started ->> 'recordsProcessed')::integer, 0), 0);
  v_run_key := coalesce(v_started ->> 'requestKey', '');
  v_run_reused := coalesce((v_started ->> 'reused')::boolean, false);

  update public.provider_recovery_requests request_row
  set
    status = case when v_run_status = 'completed' then 'completed' else 'running' end,
    recovery_run_id = v_run_id,
    attempt_no = v_run_attempt,
    started_at = now(),
    finished_at = case when v_run_status = 'completed' then now() else null end
  where request_row.id = v_request.id
  returning * into v_updated;

  return jsonb_build_object(
    'requestId', v_updated.id,
    'status', v_updated.status,
    'revision', v_updated.revision,
    'requestedFor', v_updated.requested_for,
    'execute', v_run_status = 'running' and not v_run_reused,
    'reused', v_run_reused,
    'run', jsonb_build_object(
      'runId', v_run_id,
      'status', v_run_status,
      'revision', v_run_revision,
      'attempt', v_run_attempt,
      'recordsProcessed', v_run_records,
      'requestKey', v_run_key,
      'reused', v_run_reused
    )
  );
end;
$$;

revoke all on function public.claim_provider_recovery_request_v1(uuid, bigint)
from public, anon, authenticated;
grant execute on function public.claim_provider_recovery_request_v1(uuid, bigint)
to service_role;

create or replace function public.claim_next_provider_recovery_request_v1()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_request_id uuid;
  v_revision bigint;
begin
  select request_row.id, request_row.revision
  into v_request_id, v_revision
  from public.provider_recovery_requests request_row
  where request_row.status = 'pending'
  order by request_row.requested_at asc
  limit 1
  for update skip locked;

  if not found then
    return jsonb_build_object('empty', true);
  end if;

  return public.claim_provider_recovery_request_v1(
    v_request_id,
    v_revision
  ) || jsonb_build_object('empty', false);
end;
$$;

revoke all on function public.claim_next_provider_recovery_request_v1()
from public, anon, authenticated;
grant execute on function public.claim_next_provider_recovery_request_v1()
to service_role;

create or replace function public.capture_provider_recovery_run_outcome_v1()
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

  update public.provider_recovery_requests request_row
  set
    status = new.status,
    attempt_no = greatest(request_row.attempt_no, new.attempt_no),
    error_summary = case when new.status = 'failed' then new.error_message else null end,
    finished_at = coalesce(new.finished_at, now())
  where request_row.recovery_run_id = new.id
    and request_row.status = 'running';

  return new;
end;
$$;

revoke all on function public.capture_provider_recovery_run_outcome_v1()
from public, anon, authenticated;

drop trigger if exists provider_recovery_run_outcome_capture
on public.provider_sync_runs;
create trigger provider_recovery_run_outcome_capture
after update of status on public.provider_sync_runs
for each row execute function public.capture_provider_recovery_run_outcome_v1();

create or replace function public.get_league_provider_recovery_center_v1(
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
  v_pending_count integer := 0;
  v_running_count integer := 0;
  v_completed_last_24h integer := 0;
  v_failed_last_24h integer := 0;
  v_latest_request_at timestamptz;
  v_requests jsonb := '[]'::jsonb;
  v_recoverable_incident jsonb;
begin
  select league_row.owner_id
  into v_owner_id
  from public.leagues league_row
  where league_row.id = p_league_id;

  if not found then
    raise exception 'Lega non trovata.';
  end if;
  if v_owner_id <> auth.uid() and not public.is_league_admin(p_league_id) then
    raise exception 'Il Centro Recuperi provider è riservato alla Direzione.';
  end if;

  select
    count(*) filter (where request_row.status = 'pending')::integer,
    count(*) filter (where request_row.status = 'running')::integer,
    count(*) filter (
      where request_row.status = 'completed'
        and request_row.finished_at >= now() - interval '24 hours'
    )::integer,
    count(*) filter (
      where request_row.status = 'failed'
        and request_row.finished_at >= now() - interval '24 hours'
    )::integer,
    max(request_row.updated_at)
  into
    v_pending_count,
    v_running_count,
    v_completed_last_24h,
    v_failed_last_24h,
    v_latest_request_at
  from public.provider_recovery_requests request_row
  where request_row.provider = 'api-football'
    and request_row.league_id = p_league_id;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', request_row.id,
        'incidentId', request_row.incident_id,
        'syncType', request_row.sync_type,
        'status', request_row.status,
        'revision', request_row.revision,
        'attempt', request_row.attempt_no,
        'requestedAt', request_row.requested_at,
        'startedAt', request_row.started_at,
        'finishedAt', request_row.finished_at,
        'errorSummary', request_row.error_summary
      )
      order by request_row.requested_at desc
    ),
    '[]'::jsonb
  )
  into v_requests
  from (
    select request_row.*
    from public.provider_recovery_requests request_row
    where request_row.provider = 'api-football'
      and request_row.league_id = p_league_id
    order by request_row.requested_at desc
    limit 10
  ) request_row;

  select jsonb_build_object(
    'id', incident_row.id,
    'revision', incident_row.revision,
    'syncType', incident_row.sync_type,
    'severity', incident_row.severity,
    'summary', incident_row.summary
  )
  into v_recoverable_incident
  from public.provider_operational_incidents incident_row
  where incident_row.provider = 'api-football'
    and incident_row.status = 'open'
    and not exists (
      select 1
      from public.provider_recovery_requests active_request
      where active_request.incident_id = incident_row.id
        and active_request.status in ('pending', 'running')
    )
    and (
      incident_row.source_run_id is not null
      or incident_row.source_snapshot_id is not null
      or exists (
        select 1
        from public.provider_sync_runs run_row
        where run_row.provider = incident_row.provider
          and run_row.sync_type = incident_row.sync_type
      )
    )
  order by
    case when incident_row.severity = 'critical' then 0 else 1 end,
    incident_row.last_detected_at desc
  limit 1;

  return jsonb_build_object(
    'protected', true,
    'healthy', coalesce(v_pending_count, 0) = 0
      and coalesce(v_running_count, 0) = 0
      and coalesce(v_failed_last_24h, 0) = 0,
    'pendingCount', coalesce(v_pending_count, 0),
    'runningCount', coalesce(v_running_count, 0),
    'completedLast24h', coalesce(v_completed_last_24h, 0),
    'failedLast24h', coalesce(v_failed_last_24h, 0),
    'latestRequestAt', v_latest_request_at,
    'canRequest', v_recoverable_incident is not null,
    'recoverableIncident', v_recoverable_incident,
    'requests', v_requests
  );
end;
$$;

revoke all on function public.get_league_provider_recovery_center_v1(uuid)
from public, anon, authenticated;
grant execute on function public.get_league_provider_recovery_center_v1(uuid)
to authenticated;

create or replace function public.get_league_provider_sync_health_v4(
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
begin
  v_health := public.get_league_provider_sync_health_v3(p_league_id);
  v_recovery := public.get_league_provider_recovery_center_v1(p_league_id);

  return v_health || jsonb_build_object(
    'recoveryCenter', v_recovery
  );
end;
$$;

revoke all on function public.get_league_provider_sync_health_v4(uuid)
from public, anon, authenticated;
grant execute on function public.get_league_provider_sync_health_v4(uuid)
to authenticated;

do $realtime$
begin
  if exists (
    select 1
    from pg_catalog.pg_publication publication
    where publication.pubname = 'supabase_realtime'
  ) then
    if not exists (
      select 1
      from pg_catalog.pg_publication_tables publication_table
      where publication_table.pubname = 'supabase_realtime'
        and publication_table.schemaname = 'public'
        and publication_table.tablename = 'provider_recovery_requests'
    ) then
      alter publication supabase_realtime
        add table public.provider_recovery_requests;
    end if;

    if not exists (
      select 1
      from pg_catalog.pg_publication_tables publication_table
      where publication_table.pubname = 'supabase_realtime'
        and publication_table.schemaname = 'public'
        and publication_table.tablename = 'provider_recovery_request_events'
    ) then
      alter publication supabase_realtime
        add table public.provider_recovery_request_events;
    end if;
  end if;
end;
$realtime$;

create or replace function public.get_provider_recovery_queue_integrity_v1()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'recovery_requests_table_ready',
      to_regclass('public.provider_recovery_requests') is not null,
    'recovery_events_table_ready',
      to_regclass('public.provider_recovery_request_events') is not null,
    'recovery_request_columns_ready',
      (
        select count(*) = 21
        from information_schema.columns column_row
        where column_row.table_schema = 'public'
          and column_row.table_name = 'provider_recovery_requests'
          and column_row.column_name in (
            'id', 'league_id', 'incident_id', 'provider', 'sync_type',
            'requested_for', 'requested_by', 'idempotency_key', 'status',
            'source_run_id', 'recovery_run_id', 'expected_incident_revision',
            'revision', 'attempt_no', 'error_summary', 'request_fingerprint',
            'result_fingerprint', 'requested_at', 'started_at', 'finished_at',
            'updated_at'
          )
      ),
    'recovery_event_columns_ready',
      (
        select count(*) = 11
        from information_schema.columns column_row
        where column_row.table_schema = 'public'
          and column_row.table_name = 'provider_recovery_request_events'
          and column_row.column_name in (
            'id', 'request_id', 'league_id', 'incident_id', 'event_type',
            'status', 'revision', 'attempt_no', 'recovery_run_id',
            'event_fingerprint', 'created_at'
          )
      ),
    'recovery_indexes_ready',
      to_regclass('public.provider_recovery_requests_active_incident_uidx') is not null
      and to_regclass('public.provider_recovery_requests_league_latest_idx') is not null
      and to_regclass('public.provider_recovery_requests_status_idx') is not null,
    'recovery_revision_guard_ready',
      to_regprocedure('public.prepare_provider_recovery_request_v1()') is not null
      and exists (
        select 1 from pg_trigger trigger_row
        where trigger_row.tgname = 'provider_recovery_request_revision_guard'
          and trigger_row.tgrelid = 'public.provider_recovery_requests'::regclass
          and not trigger_row.tgisinternal
      ),
    'recovery_event_writer_ready',
      to_regprocedure('public.record_provider_recovery_request_event_v1()') is not null
      and exists (
        select 1 from pg_trigger trigger_row
        where trigger_row.tgname = 'provider_recovery_request_event_writer'
          and trigger_row.tgrelid = 'public.provider_recovery_requests'::regclass
          and not trigger_row.tgisinternal
      ),
    'recovery_events_immutable_ready',
      to_regprocedure('public.prevent_provider_recovery_event_mutation_v1()') is not null
      and exists (
        select 1 from pg_trigger trigger_row
        where trigger_row.tgname = 'provider_recovery_request_events_immutable'
          and trigger_row.tgrelid = 'public.provider_recovery_request_events'::regclass
          and not trigger_row.tgisinternal
      ),
    'recovery_request_rpc_ready',
      to_regprocedure(
        'public.request_provider_recovery_guarded_v1(uuid,uuid,bigint,uuid)'
      ) is not null
      and has_function_privilege(
        'authenticated',
        'public.request_provider_recovery_guarded_v1(uuid,uuid,bigint,uuid)',
        'EXECUTE'
      ),
    'recovery_claim_rpc_ready',
      to_regprocedure('public.start_provider_recovery_sync_run_v1(uuid)') is not null
      and to_regprocedure('public.claim_provider_recovery_request_v1(uuid,bigint)') is not null
      and to_regprocedure('public.claim_next_provider_recovery_request_v1()') is not null
      and has_function_privilege(
        'service_role',
        'public.start_provider_recovery_sync_run_v1(uuid)',
        'EXECUTE'
      )
      and has_function_privilege(
        'service_role',
        'public.claim_provider_recovery_request_v1(uuid,bigint)',
        'EXECUTE'
      )
      and has_function_privilege(
        'service_role',
        'public.claim_next_provider_recovery_request_v1()',
        'EXECUTE'
      ),
    'recovery_outcome_capture_ready',
      to_regprocedure('public.capture_provider_recovery_run_outcome_v1()') is not null
      and exists (
        select 1 from pg_trigger trigger_row
        where trigger_row.tgname = 'provider_recovery_run_outcome_capture'
          and trigger_row.tgrelid = 'public.provider_sync_runs'::regclass
          and not trigger_row.tgisinternal
      ),
    'recovery_center_rpc_ready',
      to_regprocedure('public.get_league_provider_recovery_center_v1(uuid)') is not null
      and has_function_privilege(
        'authenticated',
        'public.get_league_provider_recovery_center_v1(uuid)',
        'EXECUTE'
      ),
    'provider_health_v4_ready',
      to_regprocedure('public.get_league_provider_sync_health_v4(uuid)') is not null
      and has_function_privilege(
        'authenticated',
        'public.get_league_provider_sync_health_v4(uuid)',
        'EXECUTE'
      ),
    'recovery_rls_ready',
      coalesce((
        select class_row.relrowsecurity
        from pg_class class_row
        join pg_namespace namespace_row on namespace_row.oid = class_row.relnamespace
        where namespace_row.nspname = 'public'
          and class_row.relname = 'provider_recovery_requests'
      ), false)
      and coalesce((
        select class_row.relrowsecurity
        from pg_class class_row
        join pg_namespace namespace_row on namespace_row.oid = class_row.relnamespace
        where namespace_row.nspname = 'public'
          and class_row.relname = 'provider_recovery_request_events'
      ), false),
    'recovery_policies_ready',
      exists (
        select 1 from pg_policies policy_row
        where policy_row.schemaname = 'public'
          and policy_row.tablename = 'provider_recovery_requests'
          and policy_row.policyname = 'provider_recovery_requests_read_directors'
      )
      and exists (
        select 1 from pg_policies policy_row
        where policy_row.schemaname = 'public'
          and policy_row.tablename = 'provider_recovery_request_events'
          and policy_row.policyname = 'provider_recovery_request_events_read_directors'
      ),
    'authenticated_recovery_read_ready',
      has_table_privilege(
        'authenticated', 'public.provider_recovery_requests', 'SELECT'
      )
      and has_table_privilege(
        'authenticated', 'public.provider_recovery_request_events', 'SELECT'
      ),
    'authenticated_recovery_writes_blocked',
      not has_table_privilege(
        'authenticated', 'public.provider_recovery_requests', 'INSERT'
      )
      and not has_table_privilege(
        'authenticated', 'public.provider_recovery_requests', 'UPDATE'
      )
      and not has_table_privilege(
        'authenticated', 'public.provider_recovery_requests', 'DELETE'
      )
      and not has_table_privilege(
        'authenticated', 'public.provider_recovery_request_events', 'INSERT'
      ),
    'service_role_recovery_ready',
      has_table_privilege(
        'service_role', 'public.provider_recovery_requests', 'INSERT'
      )
      and has_table_privilege(
        'service_role', 'public.provider_recovery_requests', 'UPDATE'
      )
      and has_table_privilege(
        'service_role', 'public.provider_recovery_request_events', 'INSERT'
      ),
    'recovery_realtime_ready',
      exists (
        select 1 from pg_catalog.pg_publication_tables publication_table
        where publication_table.pubname = 'supabase_realtime'
          and publication_table.schemaname = 'public'
          and publication_table.tablename = 'provider_recovery_requests'
      )
      and exists (
        select 1 from pg_catalog.pg_publication_tables publication_table
        where publication_table.pubname = 'supabase_realtime'
          and publication_table.schemaname = 'public'
          and publication_table.tablename = 'provider_recovery_request_events'
      ),
    'provider_incident_continuity_ready',
      to_regprocedure('public.get_league_provider_sync_health_v3(uuid)') is not null
      and to_regclass('public.provider_operational_incidents') is not null
  );
$$;

revoke all on function public.get_provider_recovery_queue_integrity_v1()
from public, anon, authenticated;
grant execute on function public.get_provider_recovery_queue_integrity_v1()
to authenticated, service_role;

-- Arresta la transazione con il nome esatto degli eventuali controlli falsi.
do $validation$
declare
  v_checks jsonb := public.get_provider_recovery_queue_integrity_v1();
  v_failed text[];
begin
  select array_agg(check_row.key order by check_row.key)
  into v_failed
  from jsonb_each(v_checks) check_row
  where jsonb_typeof(check_row.value) is distinct from 'boolean'
    or check_row.value is distinct from 'true'::jsonb;

  if coalesce(array_length(v_failed, 1), 0) > 0 then
    raise exception
      'Validazione v0.62.5 non superata. Controlli falsi: %',
      array_to_string(v_failed, '; ');
  end if;
end;
$validation$;

commit;

-- Diagnostica finale: devono comparire esattamente 20 valori true.
select
  (checks ->> 'recovery_requests_table_ready')::boolean
    as recovery_requests_table_ready,
  (checks ->> 'recovery_events_table_ready')::boolean
    as recovery_events_table_ready,
  (checks ->> 'recovery_request_columns_ready')::boolean
    as recovery_request_columns_ready,
  (checks ->> 'recovery_event_columns_ready')::boolean
    as recovery_event_columns_ready,
  (checks ->> 'recovery_indexes_ready')::boolean
    as recovery_indexes_ready,
  (checks ->> 'recovery_revision_guard_ready')::boolean
    as recovery_revision_guard_ready,
  (checks ->> 'recovery_event_writer_ready')::boolean
    as recovery_event_writer_ready,
  (checks ->> 'recovery_events_immutable_ready')::boolean
    as recovery_events_immutable_ready,
  (checks ->> 'recovery_request_rpc_ready')::boolean
    as recovery_request_rpc_ready,
  (checks ->> 'recovery_claim_rpc_ready')::boolean
    as recovery_claim_rpc_ready,
  (checks ->> 'recovery_outcome_capture_ready')::boolean
    as recovery_outcome_capture_ready,
  (checks ->> 'recovery_center_rpc_ready')::boolean
    as recovery_center_rpc_ready,
  (checks ->> 'provider_health_v4_ready')::boolean
    as provider_health_v4_ready,
  (checks ->> 'recovery_rls_ready')::boolean
    as recovery_rls_ready,
  (checks ->> 'recovery_policies_ready')::boolean
    as recovery_policies_ready,
  (checks ->> 'authenticated_recovery_read_ready')::boolean
    as authenticated_recovery_read_ready,
  (checks ->> 'authenticated_recovery_writes_blocked')::boolean
    as authenticated_recovery_writes_blocked,
  (checks ->> 'service_role_recovery_ready')::boolean
    as service_role_recovery_ready,
  (checks ->> 'recovery_realtime_ready')::boolean
    as recovery_realtime_ready,
  (checks ->> 'provider_incident_continuity_ready')::boolean
    as provider_incident_continuity_ready
from (
  select public.get_provider_recovery_queue_integrity_v1() as checks
) diagnostic;
