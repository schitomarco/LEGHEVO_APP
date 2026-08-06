-- LEGHEVO v0.62.8 · Retry automatico e backoff protetto del provider
-- Migrazione interna: database/112_provider_recovery_retry_backoff_safety.sql
--
-- Obiettivi:
-- - classificare in modo deterministico i fallimenti dei recuperi provider;
-- - pianificare retry automatici con backoff crescente e limite massimo;
-- - impedire retry duplicati o concorrenti per lo stesso fallimento;
-- - conservare uno storico immutabile delle decisioni e degli esiti;
-- - integrare la coda automatica nel worker senza modificare dati sportivi;
-- - terminare con una diagnostica strutturale di 20 controlli.

begin;

-- Preflight esclusivamente strutturale. Nessuna modifica viene applicata se
-- manca una dipendenza validata nelle versioni v0.62.5-v0.62.7.
do $preflight$
declare
  v_missing text[] := array[]::text[];
  v_expected record;
begin
  for v_expected in
    select *
    from (values
      ('provider_recovery_requests', 'id'),
      ('provider_recovery_requests', 'league_id'),
      ('provider_recovery_requests', 'incident_id'),
      ('provider_recovery_requests', 'provider'),
      ('provider_recovery_requests', 'sync_type'),
      ('provider_recovery_requests', 'requested_for'),
      ('provider_recovery_requests', 'requested_by'),
      ('provider_recovery_requests', 'idempotency_key'),
      ('provider_recovery_requests', 'status'),
      ('provider_recovery_requests', 'revision'),
      ('provider_recovery_requests', 'error_summary'),
      ('provider_recovery_requests', 'source_run_id'),
      ('provider_recovery_requests', 'recovery_run_id'),
      ('provider_recovery_requests', 'expected_incident_revision'),
      ('provider_recovery_requests', 'requested_at'),
      ('provider_recovery_requests', 'finished_at'),
      ('provider_recovery_requests', 'updated_at'),
      ('provider_operational_incidents', 'id'),
      ('provider_operational_incidents', 'status'),
      ('provider_operational_incidents', 'revision'),
      ('provider_operational_incidents', 'source_run_id'),
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
  if to_regprocedure('public.prepare_provider_recovery_request_v1()') is null then
    v_missing := array_append(
      v_missing,
      'function public.prepare_provider_recovery_request_v1()'
    );
  end if;
  if not exists (
    select 1
    from pg_trigger trigger_row
    where trigger_row.tgname = 'provider_recovery_request_revision_guard'
      and trigger_row.tgrelid = to_regclass('public.provider_recovery_requests')
      and not trigger_row.tgisinternal
  ) then
    v_missing := array_append(
      v_missing,
      'trigger public.provider_recovery_request_revision_guard'
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
    'public.claim_next_provider_recovery_request_v2()'
  ) is null then
    v_missing := array_append(
      v_missing,
      'function public.claim_next_provider_recovery_request_v2()'
    );
  end if;
  if to_regprocedure(
    'public.get_league_provider_recovery_center_v3(uuid)'
  ) is null then
    v_missing := array_append(
      v_missing,
      'function public.get_league_provider_recovery_center_v3(uuid)'
    );
  end if;
  if to_regprocedure('public.get_league_provider_sync_health_v6(uuid)') is null then
    v_missing := array_append(
      v_missing,
      'function public.get_league_provider_sync_health_v6(uuid)'
    );
  end if;

  if coalesce(array_length(v_missing, 1), 0) > 0 then
    raise exception
      'Preflight v0.62.8 non superato. Oggetti mancanti: %',
      array_to_string(v_missing, '; ');
  end if;
end;
$preflight$;

create table if not exists public.provider_recovery_retry_schedules (
  id uuid primary key default gen_random_uuid(),
  league_id uuid not null references public.leagues(id) on delete cascade,
  incident_id uuid not null
    references public.provider_operational_incidents(id) on delete cascade,
  source_request_id uuid not null
    references public.provider_recovery_requests(id) on delete cascade,
  retry_request_id uuid
    references public.provider_recovery_requests(id) on delete cascade,
  provider text not null,
  sync_type text not null,
  retry_no integer not null check (retry_no > 0),
  max_retries integer not null default 3 check (max_retries between 1 and 5),
  failure_class text not null check (
    failure_class in (
      'rate_limit', 'timeout', 'network', 'provider',
      'configuration', 'request', 'unknown'
    )
  ),
  retryable boolean not null,
  status text not null check (
    status in (
      'scheduled', 'dispatched', 'succeeded',
      'failed', 'exhausted', 'cancelled'
    )
  ),
  available_at timestamptz not null,
  source_request_revision bigint not null check (source_request_revision > 0),
  revision bigint not null default 1 check (revision > 0),
  failure_summary text,
  schedule_fingerprint text not null check (char_length(schedule_fingerprint) = 32),
  result_fingerprint text check (
    result_fingerprint is null or char_length(result_fingerprint) = 32
  ),
  created_at timestamptz not null default now(),
  dispatched_at timestamptz,
  finished_at timestamptz,
  updated_at timestamptz not null default now(),
  unique (source_request_id),
  check (
    (status = 'scheduled' and retryable and dispatched_at is null and finished_at is null)
    or (status = 'dispatched' and retryable and dispatched_at is not null and finished_at is null)
    or (status in ('succeeded', 'failed') and dispatched_at is not null and finished_at is not null)
    or (status in ('exhausted', 'cancelled') and finished_at is not null)
  )
);

create unique index if not exists provider_recovery_retry_request_uidx
  on public.provider_recovery_retry_schedules (retry_request_id)
  where retry_request_id is not null;
create index if not exists provider_recovery_retry_due_idx
  on public.provider_recovery_retry_schedules (status, available_at asc)
  where status = 'scheduled';
create index if not exists provider_recovery_retry_league_latest_idx
  on public.provider_recovery_retry_schedules (league_id, created_at desc);
create index if not exists provider_recovery_retry_incident_idx
  on public.provider_recovery_retry_schedules (incident_id, retry_no desc);

create table if not exists public.provider_recovery_retry_events (
  id uuid primary key default gen_random_uuid(),
  schedule_id uuid not null
    references public.provider_recovery_retry_schedules(id) on delete cascade,
  league_id uuid not null references public.leagues(id) on delete cascade,
  incident_id uuid not null
    references public.provider_operational_incidents(id) on delete cascade,
  -- Gli identificativi delle richieste sono fotografie storiche. La pulizia
  -- avviene tramite schedule_id, evitando due percorsi cascade concorrenti
  -- contro il trigger di immutabilità degli eventi.
  source_request_id uuid not null,
  retry_request_id uuid,
  event_type text not null check (
    event_type in (
      'scheduled', 'dispatched', 'succeeded',
      'failed', 'exhausted', 'cancelled'
    )
  ),
  retry_no integer not null check (retry_no > 0),
  revision bigint not null check (revision > 0),
  event_fingerprint text not null check (char_length(event_fingerprint) = 32),
  created_at timestamptz not null default now(),
  unique (schedule_id, revision)
);

create index if not exists provider_recovery_retry_events_latest_idx
  on public.provider_recovery_retry_events (league_id, created_at desc);
create index if not exists provider_recovery_retry_events_incident_idx
  on public.provider_recovery_retry_events (incident_id, created_at desc);

alter table public.provider_recovery_retry_schedules enable row level security;
alter table public.provider_recovery_retry_schedules replica identity full;
alter table public.provider_recovery_retry_events enable row level security;
alter table public.provider_recovery_retry_events replica identity full;

revoke all on table public.provider_recovery_retry_schedules
from public, anon, authenticated;
revoke all on table public.provider_recovery_retry_events
from public, anon, authenticated;

grant select on table public.provider_recovery_retry_schedules to authenticated;
grant select on table public.provider_recovery_retry_events to authenticated;
grant select, insert, update on table public.provider_recovery_retry_schedules
  to service_role;
grant select, insert on table public.provider_recovery_retry_events
  to service_role;

drop policy if exists provider_recovery_retry_schedules_read_directors
on public.provider_recovery_retry_schedules;
create policy provider_recovery_retry_schedules_read_directors
on public.provider_recovery_retry_schedules
for select to authenticated
using (
  exists (
    select 1
    from public.leagues league_row
    where league_row.id = provider_recovery_retry_schedules.league_id
      and (
        league_row.owner_id = auth.uid()
        or public.is_league_admin(league_row.id)
      )
  )
);

drop policy if exists provider_recovery_retry_events_read_directors
on public.provider_recovery_retry_events;
create policy provider_recovery_retry_events_read_directors
on public.provider_recovery_retry_events
for select to authenticated
using (
  exists (
    select 1
    from public.leagues league_row
    where league_row.id = provider_recovery_retry_events.league_id
      and (
        league_row.owner_id = auth.uid()
        or public.is_league_admin(league_row.id)
      )
  )
);

-- La policy è deterministica: tre retry massimi, con attese crescenti e
-- classificazione prudente degli errori non recuperabili.
create or replace function public.provider_recovery_retry_policy_v1(
  p_error_summary text,
  p_retry_no integer,
  p_sync_type text
)
returns jsonb
language plpgsql
immutable
security definer
set search_path = ''
as $$
declare
  v_message text := lower(trim(coalesce(p_error_summary, '')));
  v_retry_no integer := greatest(coalesce(p_retry_no, 1), 1);
  v_sync_type text := lower(trim(coalesce(p_sync_type, '')));
  v_max_retries integer := 3;
  v_failure_class text := 'unknown';
  v_retryable boolean := true;
  v_delay_seconds integer;
begin
  if v_message like '%chiave api-football non configurata%'
    or v_message like '%azione di sincronizzazione non riconosciuta%'
    or v_message like '%corpo json non valido%'
    or v_message like '%payload%non valid%'
    or v_message like '%prima sincronizza il calendario%'
    or v_message like '%unauthorized%'
    or v_message like '%forbidden%'
    or v_message like '% 401%'
    or v_message like '% 403%' then
    v_retryable := false;
    v_failure_class := case
      when v_message like '%chiave%'
        or v_message like '%unauthorized%'
        or v_message like '%forbidden%'
        or v_message like '% 401%'
        or v_message like '% 403%'
      then 'configuration'
      else 'request'
    end;
  elsif v_message like '%429%'
    or v_message like '%rate limit%'
    or v_message like '%too many requests%' then
    v_failure_class := 'rate_limit';
  elsif v_message like '%watchdog%'
    or v_message like '%timeout%'
    or v_message like '%timed out%'
    or v_message like '%senza aggiornamenti%' then
    v_failure_class := 'timeout';
  elsif v_message like '%network%'
    or v_message like '%fetch failed%'
    or v_message like '%connessione%'
    or v_message like '%dns%'
    or v_message like '%temporarily unavailable%' then
    v_failure_class := 'network';
  elsif v_message like '%500%'
    or v_message like '%502%'
    or v_message like '%503%'
    or v_message like '%504%'
    or v_message like '%provider%' then
    v_failure_class := 'provider';
  end if;

  if v_retry_no > v_max_retries then
    v_retryable := false;
  end if;

  v_delay_seconds := case v_failure_class
    when 'rate_limit' then
      case v_retry_no when 1 then 120 when 2 then 600 else 1800 end
    when 'timeout' then
      case v_retry_no when 1 then 60 when 2 then 300 else 900 end
    when 'network' then
      case v_retry_no when 1 then 60 when 2 then 300 else 900 end
    when 'provider' then
      case v_retry_no when 1 then 120 when 2 then 600 else 1800 end
    when 'configuration' then 0
    when 'request' then 0
    else case v_retry_no when 1 then 180 when 2 then 900 else 3600 end
  end;

  -- Le rose stagionali sono più onerose: evita retry troppo ravvicinati.
  if v_retryable and v_sync_type = 'sync-season-players' then
    v_delay_seconds := greatest(v_delay_seconds, 300);
  end if;

  return jsonb_build_object(
    'retryable', v_retryable,
    'failureClass', v_failure_class,
    'retryNo', v_retry_no,
    'maxRetries', v_max_retries,
    'delaySeconds', v_delay_seconds
  );
end;
$$;

revoke all on function public.provider_recovery_retry_policy_v1(text, integer, text)
from public, anon, authenticated;
grant execute on function public.provider_recovery_retry_policy_v1(text, integer, text)
to service_role;

create or replace function public.prepare_provider_recovery_retry_schedule_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    new.provider := lower(trim(coalesce(new.provider, '')));
    new.sync_type := lower(trim(coalesce(new.sync_type, '')));
    new.failure_summary := left(
      coalesce(nullif(trim(new.failure_summary), ''), 'Errore provider non specificato.'),
      500
    );
    new.revision := 1;
    new.created_at := coalesce(new.created_at, now());
    new.updated_at := new.created_at;
    new.dispatched_at := null;
    new.result_fingerprint := null;
    if new.status = 'scheduled' then
      new.finished_at := null;
    else
      new.finished_at := coalesce(new.finished_at, new.created_at);
    end if;
    new.schedule_fingerprint := pg_catalog.md5(
      new.league_id::text || E'\n'
      || new.incident_id::text || E'\n'
      || new.source_request_id::text || E'\n'
      || new.provider || E'\n'
      || new.sync_type || E'\n'
      || new.retry_no::text || E'\n'
      || new.max_retries::text || E'\n'
      || new.failure_class || E'\n'
      || new.retryable::text || E'\n'
      || new.available_at::text || E'\n'
      || new.source_request_revision::text
    );
    if new.status in ('exhausted', 'cancelled') then
      new.result_fingerprint := pg_catalog.md5(
        new.id::text || E'\n'
        || new.status || E'\n'
        || new.revision::text || E'\n'
        || new.finished_at::text
      );
    end if;
    return new;
  end if;

  if row(
    new.league_id,
    new.incident_id,
    new.source_request_id,
    new.provider,
    new.sync_type,
    new.retry_no,
    new.max_retries,
    new.failure_class,
    new.retryable,
    new.available_at,
    new.source_request_revision,
    new.failure_summary,
    new.schedule_fingerprint,
    new.created_at
  ) is distinct from row(
    old.league_id,
    old.incident_id,
    old.source_request_id,
    old.provider,
    old.sync_type,
    old.retry_no,
    old.max_retries,
    old.failure_class,
    old.retryable,
    old.available_at,
    old.source_request_revision,
    old.failure_summary,
    old.schedule_fingerprint,
    old.created_at
  ) then
    raise exception 'Identità della pianificazione retry non modificabile.';
  end if;

  if old.retry_request_id is not null
    and new.retry_request_id is distinct from old.retry_request_id then
    raise exception 'Richiesta retry già associata e non modificabile.';
  end if;

  if old.status in ('succeeded', 'failed', 'exhausted', 'cancelled') then
    if row(new.status, new.retry_request_id, new.dispatched_at, new.finished_at)
      is not distinct from
      row(old.status, old.retry_request_id, old.dispatched_at, old.finished_at) then
      return old;
    end if;
    raise exception 'Pianificazione retry già conclusa e immutabile.';
  end if;

  if old.status = 'scheduled'
    and new.status not in ('scheduled', 'dispatched', 'cancelled') then
    raise exception 'Transizione della pianificazione retry non valida.';
  end if;
  if old.status = 'dispatched'
    and new.status not in ('dispatched', 'succeeded', 'failed', 'cancelled') then
    raise exception 'Transizione del retry in esecuzione non valida.';
  end if;

  if row(new.status, new.retry_request_id, new.dispatched_at, new.finished_at)
    is not distinct from
    row(old.status, old.retry_request_id, old.dispatched_at, old.finished_at) then
    return old;
  end if;

  new.revision := old.revision + 1;
  new.updated_at := now();

  if new.status = 'dispatched' then
    if new.retry_request_id is null then
      raise exception 'Retry inviato senza richiesta associata.';
    end if;
    new.dispatched_at := coalesce(new.dispatched_at, now());
    new.finished_at := null;
  elsif new.status in ('succeeded', 'failed', 'cancelled') then
    new.dispatched_at := coalesce(new.dispatched_at, old.dispatched_at);
    new.finished_at := coalesce(new.finished_at, now());
  end if;

  new.result_fingerprint := case
    when new.status = 'scheduled' then null
    else pg_catalog.md5(
      new.id::text || E'\n'
      || new.status || E'\n'
      || new.revision::text || E'\n'
      || coalesce(new.retry_request_id::text, '') || E'\n'
      || coalesce(new.dispatched_at::text, '') || E'\n'
      || coalesce(new.finished_at::text, '')
    )
  end;

  return new;
end;
$$;

revoke all on function public.prepare_provider_recovery_retry_schedule_v1()
from public, anon, authenticated;

drop trigger if exists provider_recovery_retry_schedule_revision_guard
on public.provider_recovery_retry_schedules;
create trigger provider_recovery_retry_schedule_revision_guard
before insert or update on public.provider_recovery_retry_schedules
for each row execute function public.prepare_provider_recovery_retry_schedule_v1();

create or replace function public.record_provider_recovery_retry_event_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.provider_recovery_retry_events (
    schedule_id,
    league_id,
    incident_id,
    source_request_id,
    retry_request_id,
    event_type,
    retry_no,
    revision,
    event_fingerprint,
    created_at
  ) values (
    new.id,
    new.league_id,
    new.incident_id,
    new.source_request_id,
    new.retry_request_id,
    new.status,
    new.retry_no,
    new.revision,
    pg_catalog.md5(
      new.id::text || E'\n'
      || new.status || E'\n'
      || new.retry_no::text || E'\n'
      || new.revision::text || E'\n'
      || coalesce(new.retry_request_id::text, '') || E'\n'
      || coalesce(new.result_fingerprint, new.schedule_fingerprint)
    ),
    new.updated_at
  )
  on conflict (schedule_id, revision) do nothing;

  return new;
end;
$$;

revoke all on function public.record_provider_recovery_retry_event_v1()
from public, anon, authenticated;

drop trigger if exists provider_recovery_retry_event_writer
on public.provider_recovery_retry_schedules;
create trigger provider_recovery_retry_event_writer
after insert or update on public.provider_recovery_retry_schedules
for each row execute function public.record_provider_recovery_retry_event_v1();

create or replace function public.prevent_provider_recovery_retry_event_mutation_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'DELETE'
    and not exists (
      select 1
      from public.provider_recovery_retry_schedules schedule_row
      where schedule_row.id = old.schedule_id
    ) then
    return old;
  end if;

  raise exception 'Evento retry provider certificato: modifica o cancellazione non consentita.';
end;
$$;

revoke all on function public.prevent_provider_recovery_retry_event_mutation_v1()
from public, anon, authenticated;

drop trigger if exists provider_recovery_retry_events_immutable
on public.provider_recovery_retry_events;
create trigger provider_recovery_retry_events_immutable
before update or delete on public.provider_recovery_retry_events
for each row execute function public.prevent_provider_recovery_retry_event_mutation_v1();

-- Ogni fallimento terminale genera al massimo una decisione retry. La chiave
-- unica source_request_id rende il trigger idempotente anche dopo retry tecnici.
create or replace function public.schedule_provider_recovery_retry_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_previous_retry_no integer := 0;
  v_next_retry_no integer;
  v_policy jsonb;
  v_retryable boolean;
  v_delay_seconds integer;
  v_failure_class text;
  v_max_retries integer;
  v_status text;
begin
  if new.status <> 'failed'
    or old.status is not distinct from new.status then
    return new;
  end if;

  if exists (
    select 1
    from public.provider_recovery_retry_schedules schedule_row
    where schedule_row.source_request_id = new.id
  ) then
    return new;
  end if;

  select coalesce(max(schedule_row.retry_no), 0)
  into v_previous_retry_no
  from public.provider_recovery_retry_schedules schedule_row
  where schedule_row.retry_request_id = new.id;

  v_next_retry_no := v_previous_retry_no + 1;
  v_policy := public.provider_recovery_retry_policy_v1(
    new.error_summary,
    v_next_retry_no,
    new.sync_type
  );
  v_retryable := coalesce((v_policy ->> 'retryable')::boolean, false);
  v_delay_seconds := greatest(coalesce((v_policy ->> 'delaySeconds')::integer, 0), 0);
  v_failure_class := coalesce(v_policy ->> 'failureClass', 'unknown');
  v_max_retries := greatest(coalesce((v_policy ->> 'maxRetries')::integer, 3), 1);
  v_status := case when v_retryable then 'scheduled' else 'exhausted' end;

  insert into public.provider_recovery_retry_schedules (
    league_id,
    incident_id,
    source_request_id,
    provider,
    sync_type,
    retry_no,
    max_retries,
    failure_class,
    retryable,
    status,
    available_at,
    source_request_revision,
    failure_summary,
    finished_at
  ) values (
    new.league_id,
    new.incident_id,
    new.id,
    new.provider,
    new.sync_type,
    v_next_retry_no,
    v_max_retries,
    v_failure_class,
    v_retryable,
    v_status,
    now() + (v_delay_seconds * interval '1 second'),
    new.revision,
    new.error_summary,
    case when v_retryable then null else now() end
  )
  on conflict (source_request_id) do nothing;

  return new;
end;
$$;

revoke all on function public.schedule_provider_recovery_retry_v1()
from public, anon, authenticated;

drop trigger if exists provider_recovery_retry_scheduler
on public.provider_recovery_requests;
create trigger provider_recovery_retry_scheduler
after update of status on public.provider_recovery_requests
for each row execute function public.schedule_provider_recovery_retry_v1();

-- Allinea la pianificazione con l'esito della richiesta generata dal retry.
create or replace function public.capture_provider_recovery_retry_outcome_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.status not in ('completed', 'failed', 'cancelled')
    or old.status is not distinct from new.status then
    return new;
  end if;

  update public.provider_recovery_retry_schedules schedule_row
  set
    status = case
      when new.status = 'completed' then 'succeeded'
      when new.status = 'failed' then 'failed'
      else 'cancelled'
    end,
    finished_at = coalesce(new.finished_at, now())
  where schedule_row.retry_request_id = new.id
    and schedule_row.status = 'dispatched';

  return new;
end;
$$;

revoke all on function public.capture_provider_recovery_retry_outcome_v1()
from public, anon, authenticated;

drop trigger if exists provider_recovery_retry_outcome_capture
on public.provider_recovery_requests;
create trigger provider_recovery_retry_outcome_capture
after update of status on public.provider_recovery_requests
for each row execute function public.capture_provider_recovery_retry_outcome_v1();

-- Converte una pianificazione scaduta in una nuova richiesta ordinaria. La
-- richiesta usa l'id della pianificazione come chiave idempotente.
create or replace function public.dispatch_due_provider_recovery_retry_v1(
  p_schedule_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_schedule public.provider_recovery_retry_schedules%rowtype;
  v_source public.provider_recovery_requests%rowtype;
  v_incident public.provider_operational_incidents%rowtype;
  v_active_id uuid;
  v_inserted public.provider_recovery_requests%rowtype;
  v_claim jsonb;
begin
  select schedule_row.*
  into v_schedule
  from public.provider_recovery_retry_schedules schedule_row
  where schedule_row.status = 'scheduled'
    and schedule_row.available_at <= now()
    and (p_schedule_id is null or schedule_row.id = p_schedule_id)
  order by schedule_row.available_at asc, schedule_row.created_at asc
  limit 1
  for update skip locked;

  if not found then
    return jsonb_build_object('empty', true);
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext('provider-recovery:' || v_schedule.incident_id::text)
  );

  select incident_row.*
  into v_incident
  from public.provider_operational_incidents incident_row
  where incident_row.id = v_schedule.incident_id
  for update;

  if not found or v_incident.status <> 'open' then
    update public.provider_recovery_retry_schedules schedule_row
    set status = 'cancelled', finished_at = now()
    where schedule_row.id = v_schedule.id;

    return jsonb_build_object(
      'empty', true,
      'retryScheduleId', v_schedule.id,
      'status', 'cancelled',
      'execute', false,
      'reused', true,
      'automaticRetry', true
    );
  end if;

  select request_row.*
  into v_source
  from public.provider_recovery_requests request_row
  where request_row.id = v_schedule.source_request_id;

  if not found or v_source.requested_by is null then
    update public.provider_recovery_retry_schedules schedule_row
    set status = 'cancelled', finished_at = now()
    where schedule_row.id = v_schedule.id;

    return jsonb_build_object(
      'empty', true,
      'retryScheduleId', v_schedule.id,
      'status', 'cancelled',
      'execute', false,
      'reused', true,
      'automaticRetry', true
    );
  end if;

  select request_row.id
  into v_active_id
  from public.provider_recovery_requests request_row
  where request_row.incident_id = v_schedule.incident_id
    and request_row.status in ('pending', 'running')
  order by request_row.requested_at asc
  limit 1;

  if v_active_id is not null then
    return jsonb_build_object(
      'empty', true,
      'busy', true,
      'activeRequestId', v_active_id,
      'retryScheduleId', v_schedule.id
    );
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
    v_schedule.league_id,
    v_schedule.incident_id,
    v_schedule.provider,
    v_schedule.sync_type,
    v_source.requested_for,
    v_source.requested_by,
    v_schedule.id,
    'pending',
    v_incident.source_run_id,
    v_incident.revision
  )
  returning * into v_inserted;

  update public.provider_recovery_retry_schedules schedule_row
  set
    status = 'dispatched',
    retry_request_id = v_inserted.id,
    dispatched_at = now()
  where schedule_row.id = v_schedule.id;

  v_claim := public.claim_provider_recovery_request_v2(
    v_inserted.id,
    v_inserted.revision
  );

  return v_claim || jsonb_build_object(
    'empty', false,
    'automaticRetry', true,
    'retryScheduleId', v_schedule.id,
    'retryNo', v_schedule.retry_no,
    'maxRetries', v_schedule.max_retries
  );
end;
$$;

revoke all on function public.dispatch_due_provider_recovery_retry_v1(uuid)
from public, anon, authenticated;
grant execute on function public.dispatch_due_provider_recovery_retry_v1(uuid)
to service_role;

-- Il worker prova prima i retry automatici maturati e poi la coda manuale.
create or replace function public.claim_next_provider_recovery_request_v3()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_retry jsonb;
begin
  v_retry := public.dispatch_due_provider_recovery_retry_v1(null);

  if coalesce((v_retry ->> 'empty')::boolean, true) = false then
    return v_retry;
  end if;

  return public.claim_next_provider_recovery_request_v2();
end;
$$;

revoke all on function public.claim_next_provider_recovery_request_v3()
from public, anon, authenticated;
grant execute on function public.claim_next_provider_recovery_request_v3()
to service_role;

create or replace function public.get_league_provider_retry_center_v1(
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
  v_scheduled_count integer := 0;
  v_due_count integer := 0;
  v_dispatched_count integer := 0;
  v_succeeded_last_24h integer := 0;
  v_failed_last_24h integer := 0;
  v_exhausted_open_count integer := 0;
  v_next_retry_at timestamptz;
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
    raise exception 'Solo Presidente e Admin possono leggere i retry provider.';
  end if;

  select
    count(*) filter (where schedule_row.status = 'scheduled'),
    count(*) filter (
      where schedule_row.status = 'scheduled'
        and schedule_row.available_at <= now()
    ),
    count(*) filter (where schedule_row.status = 'dispatched'),
    count(*) filter (
      where schedule_row.status = 'succeeded'
        and schedule_row.finished_at >= now() - interval '24 hours'
    ),
    count(*) filter (
      where schedule_row.status = 'failed'
        and schedule_row.finished_at >= now() - interval '24 hours'
    ),
    count(*) filter (
      where schedule_row.status = 'exhausted'
        and incident_row.status = 'open'
    ),
    min(schedule_row.available_at) filter (
      where schedule_row.status = 'scheduled'
    )
  into
    v_scheduled_count,
    v_due_count,
    v_dispatched_count,
    v_succeeded_last_24h,
    v_failed_last_24h,
    v_exhausted_open_count,
    v_next_retry_at
  from public.provider_recovery_retry_schedules schedule_row
  join public.provider_operational_incidents incident_row
    on incident_row.id = schedule_row.incident_id
  where schedule_row.league_id = p_league_id;

  return jsonb_build_object(
    'protected', true,
    'healthy', v_exhausted_open_count = 0,
    'automaticRetryActive', true,
    'scheduledCount', v_scheduled_count,
    'dueCount', v_due_count,
    'dispatchedCount', v_dispatched_count,
    'succeededLast24h', v_succeeded_last_24h,
    'failedLast24h', v_failed_last_24h,
    'exhaustedOpenCount', v_exhausted_open_count,
    'nextRetryAt', v_next_retry_at,
    'maxRetries', 3
  );
end;
$$;

revoke all on function public.get_league_provider_retry_center_v1(uuid)
from public, anon, authenticated;
grant execute on function public.get_league_provider_retry_center_v1(uuid)
to authenticated;

create or replace function public.get_league_provider_recovery_center_v4(
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
  v_retry jsonb;
  v_healthy boolean;
  v_can_request boolean;
begin
  v_center := public.get_league_provider_recovery_center_v3(p_league_id);
  v_retry := public.get_league_provider_retry_center_v1(p_league_id);
  v_healthy := coalesce((v_center ->> 'healthy')::boolean, false)
    and coalesce((v_retry ->> 'healthy')::boolean, false);
  v_can_request := coalesce((v_center ->> 'canRequest')::boolean, false)
    and coalesce((v_retry ->> 'scheduledCount')::integer, 0) = 0
    and coalesce((v_retry ->> 'dispatchedCount')::integer, 0) = 0;

  return v_center || jsonb_build_object(
    'healthy', v_healthy,
    'canRequest', v_can_request,
    'retryCenter', v_retry
  );
end;
$$;

revoke all on function public.get_league_provider_recovery_center_v4(uuid)
from public, anon, authenticated;
grant execute on function public.get_league_provider_recovery_center_v4(uuid)
to authenticated;

create or replace function public.get_league_provider_sync_health_v7(
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
  v_health := public.get_league_provider_sync_health_v6(p_league_id);
  v_recovery := public.get_league_provider_recovery_center_v4(p_league_id);
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

revoke all on function public.get_league_provider_sync_health_v7(uuid)
from public, anon, authenticated;
grant execute on function public.get_league_provider_sync_health_v7(uuid)
to authenticated;

-- Pubblica soltanto il registro eventi, privo del payload requested_for.
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
      and publication_table.tablename = 'provider_recovery_retry_events'
  ) then
    alter publication supabase_realtime
      add table public.provider_recovery_retry_events;
  end if;
end;
$realtime$;

create or replace function public.get_provider_recovery_retry_backoff_integrity_v1()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'retry_schedule_table_ready',
      to_regclass('public.provider_recovery_retry_schedules') is not null,
    'retry_event_table_ready',
      to_regclass('public.provider_recovery_retry_events') is not null,
    'retry_schedule_columns_ready',
      (
        select count(*) = 22
        from information_schema.columns column_row
        where column_row.table_schema = 'public'
          and column_row.table_name = 'provider_recovery_retry_schedules'
          and column_row.column_name in (
            'id', 'league_id', 'incident_id', 'source_request_id',
            'retry_request_id', 'provider', 'sync_type', 'retry_no',
            'max_retries', 'failure_class', 'retryable', 'status',
            'available_at', 'source_request_revision', 'revision',
            'failure_summary', 'schedule_fingerprint', 'result_fingerprint',
            'created_at', 'dispatched_at', 'finished_at', 'updated_at'
          )
      ),
    'retry_event_columns_ready',
      (
        select count(*) = 11
        from information_schema.columns column_row
        where column_row.table_schema = 'public'
          and column_row.table_name = 'provider_recovery_retry_events'
          and column_row.column_name in (
            'id', 'schedule_id', 'league_id', 'incident_id',
            'source_request_id', 'retry_request_id', 'event_type',
            'retry_no', 'revision', 'event_fingerprint', 'created_at'
          )
      ),
    'retry_indexes_ready',
      to_regclass('public.provider_recovery_retry_request_uidx') is not null
      and to_regclass('public.provider_recovery_retry_due_idx') is not null
      and to_regclass('public.provider_recovery_retry_league_latest_idx') is not null,
    'retry_rls_and_read_ready',
      coalesce((
        select class_row.relrowsecurity
        from pg_class class_row
        where class_row.oid = 'public.provider_recovery_retry_schedules'::regclass
      ), false)
      and coalesce((
        select class_row.relrowsecurity
        from pg_class class_row
        where class_row.oid = 'public.provider_recovery_retry_events'::regclass
      ), false)
      and has_table_privilege(
        'authenticated', 'public.provider_recovery_retry_schedules', 'SELECT'
      )
      and has_table_privilege(
        'authenticated', 'public.provider_recovery_retry_events', 'SELECT'
      ),
    'authenticated_retry_writes_blocked',
      not has_table_privilege(
        'authenticated', 'public.provider_recovery_retry_schedules', 'INSERT'
      )
      and not has_table_privilege(
        'authenticated', 'public.provider_recovery_retry_schedules', 'UPDATE'
      )
      and not has_table_privilege(
        'authenticated', 'public.provider_recovery_retry_events', 'INSERT'
      ),
    'service_role_retry_write_ready',
      has_table_privilege(
        'service_role', 'public.provider_recovery_retry_schedules', 'INSERT'
      )
      and has_table_privilege(
        'service_role', 'public.provider_recovery_retry_schedules', 'UPDATE'
      )
      and has_table_privilege(
        'service_role', 'public.provider_recovery_retry_events', 'INSERT'
      ),
    'retry_policy_ready',
      to_regprocedure(
        'public.provider_recovery_retry_policy_v1(text,integer,text)'
      ) is not null,
    'retry_revision_guard_ready',
      to_regprocedure(
        'public.prepare_provider_recovery_retry_schedule_v1()'
      ) is not null
      and exists (
        select 1 from pg_trigger trigger_row
        where trigger_row.tgname = 'provider_recovery_retry_schedule_revision_guard'
          and trigger_row.tgrelid = 'public.provider_recovery_retry_schedules'::regclass
          and not trigger_row.tgisinternal
      ),
    'retry_event_writer_ready',
      to_regprocedure('public.record_provider_recovery_retry_event_v1()') is not null
      and exists (
        select 1 from pg_trigger trigger_row
        where trigger_row.tgname = 'provider_recovery_retry_event_writer'
          and trigger_row.tgrelid = 'public.provider_recovery_retry_schedules'::regclass
          and not trigger_row.tgisinternal
      ),
    'retry_event_immutability_ready',
      to_regprocedure(
        'public.prevent_provider_recovery_retry_event_mutation_v1()'
      ) is not null
      and exists (
        select 1 from pg_trigger trigger_row
        where trigger_row.tgname = 'provider_recovery_retry_events_immutable'
          and trigger_row.tgrelid = 'public.provider_recovery_retry_events'::regclass
          and not trigger_row.tgisinternal
      ),
    'retry_scheduler_ready',
      to_regprocedure('public.schedule_provider_recovery_retry_v1()') is not null
      and exists (
        select 1 from pg_trigger trigger_row
        where trigger_row.tgname = 'provider_recovery_retry_scheduler'
          and trigger_row.tgrelid = 'public.provider_recovery_requests'::regclass
          and not trigger_row.tgisinternal
      ),
    'retry_outcome_capture_ready',
      to_regprocedure('public.capture_provider_recovery_retry_outcome_v1()') is not null
      and exists (
        select 1 from pg_trigger trigger_row
        where trigger_row.tgname = 'provider_recovery_retry_outcome_capture'
          and trigger_row.tgrelid = 'public.provider_recovery_requests'::regclass
          and not trigger_row.tgisinternal
      ),
    'retry_dispatch_rpc_ready',
      to_regprocedure(
        'public.dispatch_due_provider_recovery_retry_v1(uuid)'
      ) is not null
      and has_function_privilege(
        'service_role',
        'public.dispatch_due_provider_recovery_retry_v1(uuid)',
        'EXECUTE'
      )
      and not has_function_privilege(
        'authenticated',
        'public.dispatch_due_provider_recovery_retry_v1(uuid)',
        'EXECUTE'
      ),
    'retry_claim_v3_ready',
      to_regprocedure('public.claim_next_provider_recovery_request_v3()') is not null
      and has_function_privilege(
        'service_role',
        'public.claim_next_provider_recovery_request_v3()',
        'EXECUTE'
      )
      and not has_function_privilege(
        'authenticated',
        'public.claim_next_provider_recovery_request_v3()',
        'EXECUTE'
      ),
    'retry_center_ready',
      to_regprocedure('public.get_league_provider_retry_center_v1(uuid)') is not null
      and to_regprocedure('public.get_league_provider_recovery_center_v4(uuid)') is not null
      and has_function_privilege(
        'authenticated',
        'public.get_league_provider_retry_center_v1(uuid)',
        'EXECUTE'
      ),
    'provider_health_v7_ready',
      to_regprocedure('public.get_league_provider_sync_health_v7(uuid)') is not null
      and has_function_privilege(
        'authenticated',
        'public.get_league_provider_sync_health_v7(uuid)',
        'EXECUTE'
      ),
    'retry_realtime_ready',
      exists (
        select 1
        from pg_catalog.pg_publication_tables publication_table
        where publication_table.pubname = 'supabase_realtime'
          and publication_table.schemaname = 'public'
          and publication_table.tablename = 'provider_recovery_retry_events'
      ),
    'provider_continuity_ready',
      to_regprocedure(
        'public.claim_provider_recovery_request_v2(uuid,bigint)'
      ) is not null
      and to_regprocedure(
        'public.get_league_provider_recovery_center_v3(uuid)'
      ) is not null
      and to_regprocedure(
        'public.get_league_provider_sync_health_v6(uuid)'
      ) is not null
  );
$$;

revoke all on function public.get_provider_recovery_retry_backoff_integrity_v1()
from public, anon, authenticated;
grant execute on function public.get_provider_recovery_retry_backoff_integrity_v1()
to authenticated, service_role;

-- Arresta la transazione indicando il nome esatto degli eventuali controlli falsi.
do $validation$
declare
  v_checks jsonb := public.get_provider_recovery_retry_backoff_integrity_v1();
  v_failed text[];
begin
  select array_agg(check_row.key order by check_row.key)
  into v_failed
  from jsonb_each(v_checks) check_row
  where jsonb_typeof(check_row.value) is distinct from 'boolean'
    or check_row.value is distinct from 'true'::jsonb;

  if coalesce(array_length(v_failed, 1), 0) > 0 then
    raise exception
      'Validazione v0.62.8 non superata. Controlli falsi: %',
      array_to_string(v_failed, '; ');
  end if;
end;
$validation$;

commit;

-- Diagnostica finale: devono comparire esattamente 20 valori true.
select
  (checks ->> 'retry_schedule_table_ready')::boolean
    as retry_schedule_table_ready,
  (checks ->> 'retry_event_table_ready')::boolean
    as retry_event_table_ready,
  (checks ->> 'retry_schedule_columns_ready')::boolean
    as retry_schedule_columns_ready,
  (checks ->> 'retry_event_columns_ready')::boolean
    as retry_event_columns_ready,
  (checks ->> 'retry_indexes_ready')::boolean
    as retry_indexes_ready,
  (checks ->> 'retry_rls_and_read_ready')::boolean
    as retry_rls_and_read_ready,
  (checks ->> 'authenticated_retry_writes_blocked')::boolean
    as authenticated_retry_writes_blocked,
  (checks ->> 'service_role_retry_write_ready')::boolean
    as service_role_retry_write_ready,
  (checks ->> 'retry_policy_ready')::boolean
    as retry_policy_ready,
  (checks ->> 'retry_revision_guard_ready')::boolean
    as retry_revision_guard_ready,
  (checks ->> 'retry_event_writer_ready')::boolean
    as retry_event_writer_ready,
  (checks ->> 'retry_event_immutability_ready')::boolean
    as retry_event_immutability_ready,
  (checks ->> 'retry_scheduler_ready')::boolean
    as retry_scheduler_ready,
  (checks ->> 'retry_outcome_capture_ready')::boolean
    as retry_outcome_capture_ready,
  (checks ->> 'retry_dispatch_rpc_ready')::boolean
    as retry_dispatch_rpc_ready,
  (checks ->> 'retry_claim_v3_ready')::boolean
    as retry_claim_v3_ready,
  (checks ->> 'retry_center_ready')::boolean
    as retry_center_ready,
  (checks ->> 'provider_health_v7_ready')::boolean
    as provider_health_v7_ready,
  (checks ->> 'retry_realtime_ready')::boolean
    as retry_realtime_ready,
  (checks ->> 'provider_continuity_ready')::boolean
    as provider_continuity_ready
from (
  select public.get_provider_recovery_retry_backoff_integrity_v1() as checks
) diagnostic;
