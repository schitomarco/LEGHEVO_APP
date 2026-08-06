-- LEGHEVO v0.62.10 · Verifica protetta dell'efficacia dei recuperi provider
-- Migrazione interna: database/114_provider_recovery_outcome_verification_safety.sql
--
-- Obiettivi:
-- - distinguere un run tecnicamente completato da un recupero realmente efficace;
-- - certificare l'esito rispetto all'incidente provider collegato e alla fotografia qualità;
-- - proseguire automaticamente il backoff quando l'incidente resta aperto;
-- - aprire il circuit breaker esistente quando anche la verifica esaurisce i tentativi;
-- - impedire nuovi cicli manuali privi di una verifica chiusa;
-- - preservare dati sportivi, coda, watchdog, heartbeat, retry e blocchi già validati;
-- - terminare con una diagnostica strutturale di esattamente 20 controlli.

begin;

-- Preflight strutturale e di continuità. Nessuna modifica viene applicata se
-- manca una dipendenza validata nelle versioni v0.62.3-v0.62.9.
do $preflight$
declare
  v_missing text[] := array[]::text[];
  v_expected record;
  v_invalid_requests text;
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
      ('provider_sync_run_events', 'id'),
      ('provider_sync_run_events', 'run_id'),
      ('provider_sync_run_events', 'event_type'),
      ('provider_data_quality_snapshots', 'id'),
      ('provider_data_quality_snapshots', 'run_id'),
      ('provider_data_quality_snapshots', 'status'),
      ('provider_data_quality_snapshots', 'anomaly_count'),
      ('provider_data_quality_snapshots', 'created_at'),
      ('provider_operational_incidents', 'id'),
      ('provider_operational_incidents', 'provider'),
      ('provider_operational_incidents', 'sync_type'),
      ('provider_operational_incidents', 'status'),
      ('provider_operational_incidents', 'revision'),
      ('provider_operational_incidents', 'source_snapshot_id'),
      ('provider_operational_incidents', 'resolved_at'),
      ('provider_recovery_requests', 'id'),
      ('provider_recovery_requests', 'league_id'),
      ('provider_recovery_requests', 'incident_id'),
      ('provider_recovery_requests', 'provider'),
      ('provider_recovery_requests', 'sync_type'),
      ('provider_recovery_requests', 'status'),
      ('provider_recovery_requests', 'revision'),
      ('provider_recovery_requests', 'idempotency_key'),
      ('provider_recovery_requests', 'recovery_run_id'),
      ('provider_recovery_requests', 'requested_at'),
      ('provider_recovery_requests', 'finished_at'),
      ('provider_recovery_retry_schedules', 'id'),
      ('provider_recovery_retry_schedules', 'league_id'),
      ('provider_recovery_retry_schedules', 'incident_id'),
      ('provider_recovery_retry_schedules', 'source_request_id'),
      ('provider_recovery_retry_schedules', 'retry_request_id'),
      ('provider_recovery_retry_schedules', 'provider'),
      ('provider_recovery_retry_schedules', 'sync_type'),
      ('provider_recovery_retry_schedules', 'retry_no'),
      ('provider_recovery_retry_schedules', 'max_retries'),
      ('provider_recovery_retry_schedules', 'failure_class'),
      ('provider_recovery_retry_schedules', 'retryable'),
      ('provider_recovery_retry_schedules', 'status'),
      ('provider_recovery_retry_schedules', 'available_at'),
      ('provider_recovery_retry_schedules', 'source_request_revision'),
      ('provider_recovery_retry_schedules', 'failure_summary'),
      ('provider_recovery_retry_schedules', 'created_at'),
      ('provider_recovery_retry_schedules', 'finished_at'),
      ('provider_recovery_circuit_breakers', 'id'),
      ('provider_recovery_circuit_breakers', 'league_id'),
      ('provider_recovery_circuit_breakers', 'incident_id'),
      ('provider_recovery_circuit_breakers', 'source_schedule_id'),
      ('provider_recovery_circuit_breakers', 'status'),
      ('provider_recovery_circuit_breakers', 'opened_at')
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
  if to_regprocedure('pg_catalog.pg_advisory_xact_lock(bigint)') is null then
    v_missing := array_append(
      v_missing,
      'function pg_catalog.pg_advisory_xact_lock(bigint)'
    );
  end if;
  if to_regprocedure('public.is_league_admin(uuid)') is null then
    v_missing := array_append(v_missing, 'function public.is_league_admin(uuid)');
  end if;
  if to_regprocedure(
    'public.provider_recovery_retry_policy_v1(text,integer,text)'
  ) is null then
    v_missing := array_append(
      v_missing,
      'function public.provider_recovery_retry_policy_v1(text,integer,text)'
    );
  end if;
  if to_regprocedure('public.get_league_provider_retry_center_v2(uuid)') is null then
    v_missing := array_append(
      v_missing,
      'function public.get_league_provider_retry_center_v2(uuid)'
    );
  end if;
  if to_regprocedure('public.get_league_provider_recovery_center_v5(uuid)') is null then
    v_missing := array_append(
      v_missing,
      'function public.get_league_provider_recovery_center_v5(uuid)'
    );
  end if;
  if to_regprocedure('public.get_league_provider_sync_health_v8(uuid)') is null then
    v_missing := array_append(
      v_missing,
      'function public.get_league_provider_sync_health_v8(uuid)'
    );
  end if;
  if to_regprocedure(
    'public.get_provider_recovery_circuit_breaker_integrity_v1()'
  ) is null then
    v_missing := array_append(
      v_missing,
      'function public.get_provider_recovery_circuit_breaker_integrity_v1()'
    );
  end if;
  if to_regprocedure('public.capture_provider_recovery_run_outcome_v1()') is null then
    v_missing := array_append(
      v_missing,
      'function public.capture_provider_recovery_run_outcome_v1()'
    );
  end if;
  if to_regprocedure('public.capture_provider_sync_incident_v1()') is null then
    v_missing := array_append(
      v_missing,
      'function public.capture_provider_sync_incident_v1()'
    );
  end if;
  if to_regprocedure('public.capture_provider_data_quality_snapshot_v1()') is null then
    v_missing := array_append(
      v_missing,
      'function public.capture_provider_data_quality_snapshot_v1()'
    );
  end if;
  if to_regprocedure('public.capture_provider_quality_incident_v1()') is null then
    v_missing := array_append(
      v_missing,
      'function public.capture_provider_quality_incident_v1()'
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

  if not exists (
    select 1
    from pg_catalog.pg_trigger trigger_row
    where trigger_row.tgname = 'provider_sync_run_event_writer'
      and trigger_row.tgrelid = 'public.provider_sync_runs'::regclass
      and not trigger_row.tgisinternal
  ) then
    v_missing := array_append(
      v_missing,
      'trigger provider_sync_run_event_writer on public.provider_sync_runs'
    );
  end if;
  if not exists (
    select 1
    from pg_catalog.pg_trigger trigger_row
    where trigger_row.tgname = 'provider_recovery_run_outcome_capture'
      and trigger_row.tgrelid = 'public.provider_sync_runs'::regclass
      and not trigger_row.tgisinternal
  ) then
    v_missing := array_append(
      v_missing,
      'trigger provider_recovery_run_outcome_capture on public.provider_sync_runs'
    );
  end if;
  if not exists (
    select 1
    from pg_catalog.pg_trigger trigger_row
    where trigger_row.tgname = 'provider_sync_incident_capture'
      and trigger_row.tgrelid = 'public.provider_sync_run_events'::regclass
      and not trigger_row.tgisinternal
  ) then
    v_missing := array_append(
      v_missing,
      'trigger provider_sync_incident_capture on public.provider_sync_run_events'
    );
  end if;
  if not exists (
    select 1
    from pg_catalog.pg_trigger trigger_row
    where trigger_row.tgname = 'provider_sync_quality_snapshot_writer'
      and trigger_row.tgrelid = 'public.provider_sync_run_events'::regclass
      and not trigger_row.tgisinternal
  ) then
    v_missing := array_append(
      v_missing,
      'trigger provider_sync_quality_snapshot_writer on public.provider_sync_run_events'
    );
  end if;
  if not exists (
    select 1
    from pg_catalog.pg_trigger trigger_row
    where trigger_row.tgname = 'provider_quality_incident_capture'
      and trigger_row.tgrelid = 'public.provider_data_quality_snapshots'::regclass
      and not trigger_row.tgisinternal
  ) then
    v_missing := array_append(
      v_missing,
      'trigger provider_quality_incident_capture on public.provider_data_quality_snapshots'
    );
  end if;
  if not exists (
    select 1
    from pg_catalog.pg_trigger trigger_row
    where trigger_row.tgname = 'provider_recovery_circuit_breaker_opener'
      and trigger_row.tgrelid = 'public.provider_recovery_retry_schedules'::regclass
      and not trigger_row.tgisinternal
  ) then
    v_missing := array_append(
      v_missing,
      'trigger provider_recovery_circuit_breaker_opener on public.provider_recovery_retry_schedules'
    );
  end if;

  if coalesce(array_length(v_missing, 1), 0) > 0 then
    raise exception
      'Preflight v0.62.10 non superato. Oggetti mancanti: %',
      array_to_string(v_missing, '; ');
  end if;

  select string_agg(request_row.id::text, ', ' order by request_row.finished_at)
  into v_invalid_requests
  from public.provider_recovery_requests request_row
  where request_row.status = 'completed'
    and request_row.recovery_run_id is null;

  if v_invalid_requests is not null then
    raise exception
      'Preflight v0.62.10 non superato. Richieste completed prive di recovery_run_id: %',
      v_invalid_requests;
  end if;
end;
$preflight$;

-- Ogni certificato è una fotografia immutabile dell'efficacia del singolo
-- recupero. Gli UUID collegati sono conservati come riferimenti storici; la
-- cancellazione transita soltanto dalla richiesta padre.
create table if not exists public.provider_recovery_outcome_certificates (
  id uuid primary key default gen_random_uuid(),
  league_id uuid not null,
  request_id uuid not null unique
    references public.provider_recovery_requests(id) on delete cascade,
  incident_id uuid not null,
  recovery_run_id uuid not null,
  provider text not null,
  sync_type text not null,
  outcome text not null check (
    outcome in ('verified', 'retry_scheduled', 'exhausted', 'superseded')
  ),
  incident_status text not null check (incident_status in ('open', 'resolved')),
  incident_revision bigint not null check (incident_revision > 0),
  source_snapshot_id uuid,
  source_snapshot_status text check (
    source_snapshot_status is null
    or source_snapshot_status in ('healthy', 'attention', 'idle')
  ),
  anomaly_count integer not null default 0 check (anomaly_count >= 0),
  retry_schedule_id uuid unique,
  retry_no integer check (retry_no is null or retry_no > 0),
  max_retries integer check (max_retries is null or max_retries between 1 and 5),
  verification_summary text not null,
  certificate_fingerprint text not null check (char_length(certificate_fingerprint) = 32),
  created_at timestamptz not null default now(),
  check (
    (outcome = 'verified'
      and incident_status = 'resolved'
      and retry_schedule_id is null
      and retry_no is null
      and max_retries is null)
    or (outcome in ('retry_scheduled', 'exhausted')
      and incident_status = 'open'
      and retry_schedule_id is not null
      and retry_no is not null
      and max_retries is not null)
    or (outcome = 'superseded'
      and incident_status = 'open'
      and retry_schedule_id is null
      and retry_no is null
      and max_retries is null)
  )
);

create index if not exists provider_recovery_outcome_certificates_league_idx
  on public.provider_recovery_outcome_certificates (league_id, created_at desc);
create index if not exists provider_recovery_outcome_certificates_incident_idx
  on public.provider_recovery_outcome_certificates (incident_id, created_at desc);
create index if not exists provider_recovery_outcome_certificates_outcome_idx
  on public.provider_recovery_outcome_certificates (outcome, created_at desc);

alter table public.provider_recovery_outcome_certificates enable row level security;
alter table public.provider_recovery_outcome_certificates replica identity full;

revoke all on table public.provider_recovery_outcome_certificates
from public, anon, authenticated;
grant select on table public.provider_recovery_outcome_certificates to authenticated;
grant select, insert on table public.provider_recovery_outcome_certificates
to service_role;

drop policy if exists provider_recovery_outcome_certificates_read_directors
on public.provider_recovery_outcome_certificates;
create policy provider_recovery_outcome_certificates_read_directors
on public.provider_recovery_outcome_certificates
for select to authenticated
using (
  exists (
    select 1
    from public.leagues league_row
    where league_row.id = provider_recovery_outcome_certificates.league_id
      and (
        league_row.owner_id = auth.uid()
        or public.is_league_admin(league_row.id)
      )
  )
);

create or replace function public.prevent_provider_recovery_outcome_certificate_mutation_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'DELETE'
    and not exists (
      select 1
      from public.provider_recovery_requests request_row
      where request_row.id = old.request_id
    ) then
    return old;
  end if;

  raise exception
    'Certificato esito recupero provider immutabile: modifica o cancellazione non consentita.';
end;
$$;

revoke all on function public.prevent_provider_recovery_outcome_certificate_mutation_v1()
from public, anon, authenticated;

drop trigger if exists provider_recovery_outcome_certificates_immutable
on public.provider_recovery_outcome_certificates;
create trigger provider_recovery_outcome_certificates_immutable
before update or delete on public.provider_recovery_outcome_certificates
for each row execute function public.prevent_provider_recovery_outcome_certificate_mutation_v1();

-- Certifica una singola richiesta completata. Se l'incidente è ancora aperto,
-- la richiesta viene trattata come recupero tecnicamente riuscito ma non
-- efficace: il backoff già validato prosegue dalla posizione corretta.
create or replace function public.certify_provider_recovery_request_outcome_v1(
  p_request_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_request public.provider_recovery_requests%rowtype;
  v_incident public.provider_operational_incidents%rowtype;
  v_snapshot public.provider_data_quality_snapshots%rowtype;
  v_existing_certificate_id uuid;
  v_current_retry_no integer := 0;
  v_next_retry_no integer;
  v_policy jsonb;
  v_retryable boolean;
  v_delay_seconds integer;
  v_failure_class text;
  v_max_retries integer;
  v_schedule_status text;
  v_schedule public.provider_recovery_retry_schedules%rowtype;
  v_outcome text;
  v_summary text;
  v_certificate_id uuid;
  v_superseding_request_id uuid;
  v_active_schedule_id uuid;
  v_open_breaker_id uuid;
begin
  if p_request_id is null then
    raise exception 'Richiesta da certificare obbligatoria.';
  end if;

  -- Legge prima il riferimento senza bloccare righe, poi segue lo stesso
  -- ordine di lock della coda: incidente -> richiesta. Evita inversioni con
  -- richieste manuali o dispatcher concorrenti.
  select request_row.*
  into v_request
  from public.provider_recovery_requests request_row
  where request_row.id = p_request_id;

  if not found then
    raise exception 'Richiesta di recupero provider da certificare non trovata.';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext('provider-recovery:' || v_request.incident_id::text)
  );
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext('provider-recovery-outcome:' || p_request_id::text)
  );

  select certificate_row.id
  into v_existing_certificate_id
  from public.provider_recovery_outcome_certificates certificate_row
  where certificate_row.request_id = p_request_id;

  if found then
    return v_existing_certificate_id;
  end if;

  select request_row.*
  into v_request
  from public.provider_recovery_requests request_row
  where request_row.id = p_request_id
  for update;

  if not found then
    raise exception
      'Richiesta di recupero provider % rimossa durante la certificazione.',
      p_request_id;
  end if;
  if v_request.status <> 'completed' then
    raise exception
      'La richiesta di recupero % non è completed: stato corrente %.',
      v_request.id,
      v_request.status;
  end if;
  if v_request.recovery_run_id is null then
    raise exception
      'La richiesta di recupero % è completed ma priva del run collegato.',
      v_request.id;
  end if;

  select incident_row.*
  into v_incident
  from public.provider_operational_incidents incident_row
  where incident_row.id = v_request.incident_id
  for update;

  if not found then
    raise exception
      'Incidente provider % collegato alla richiesta % non trovato.',
      v_request.incident_id,
      v_request.id;
  end if;

  select snapshot_row.*
  into v_snapshot
  from public.provider_data_quality_snapshots snapshot_row
  where snapshot_row.run_id = v_request.recovery_run_id
  order by snapshot_row.created_at desc
  limit 1;

  if v_incident.status = 'resolved' then
    v_outcome := 'verified';
    v_summary := 'Recupero provider verificato: incidente risolto.';

    insert into public.provider_recovery_outcome_certificates (
      league_id,
      request_id,
      incident_id,
      recovery_run_id,
      provider,
      sync_type,
      outcome,
      incident_status,
      incident_revision,
      source_snapshot_id,
      source_snapshot_status,
      anomaly_count,
      verification_summary,
      certificate_fingerprint,
      created_at
    ) values (
      v_request.league_id,
      v_request.id,
      v_request.incident_id,
      v_request.recovery_run_id,
      v_request.provider,
      v_request.sync_type,
      v_outcome,
      v_incident.status,
      v_incident.revision,
      v_snapshot.id,
      v_snapshot.status,
      coalesce(v_snapshot.anomaly_count, 0),
      v_summary,
      pg_catalog.md5(
        v_request.id::text || E'\n'
        || v_request.recovery_run_id::text || E'\n'
        || v_incident.id::text || E'\n'
        || v_incident.status || E'\n'
        || v_incident.revision::text || E'\n'
        || v_outcome || E'\n'
        || coalesce(v_snapshot.id::text, '') || E'\n'
        || coalesce(v_snapshot.status, '') || E'\n'
        || coalesce(v_snapshot.anomaly_count, 0)::text
      ),
      coalesce(v_request.finished_at, now())
    )
    on conflict (request_id) do nothing
    returning id into v_certificate_id;
  else
    -- Un recupero storico non deve riaprire una seconda catena se esiste già
    -- un tentativo successivo, un retry attivo o un circuit breaker aperto.
    select request_row.id
    into v_superseding_request_id
    from public.provider_recovery_requests request_row
    where request_row.incident_id = v_request.incident_id
      and request_row.id <> v_request.id
      and (
        request_row.requested_at > v_request.requested_at
        or (
          request_row.requested_at = v_request.requested_at
          and request_row.id > v_request.id
        )
      )
    order by request_row.requested_at asc, request_row.id asc
    limit 1;

    select schedule_row.id
    into v_active_schedule_id
    from public.provider_recovery_retry_schedules schedule_row
    where schedule_row.incident_id = v_request.incident_id
      and schedule_row.source_request_id <> v_request.id
      and schedule_row.status in ('scheduled', 'dispatched')
    order by schedule_row.created_at desc, schedule_row.id desc
    limit 1;

    select breaker_row.id
    into v_open_breaker_id
    from public.provider_recovery_circuit_breakers breaker_row
    where breaker_row.incident_id = v_request.incident_id
      and breaker_row.status = 'open'
    order by breaker_row.opened_at desc, breaker_row.id desc
    limit 1;

    if v_superseding_request_id is not null
      or v_active_schedule_id is not null
      or v_open_breaker_id is not null then
      v_outcome := 'superseded';
      v_summary := case
        when v_superseding_request_id is not null then
          format(
            'Verifica storica chiusa senza nuovo retry: esiste la richiesta successiva %s.',
            v_superseding_request_id
          )
        when v_active_schedule_id is not null then
          format(
            'Verifica storica chiusa senza nuovo retry: pianificazione attiva %s già presente.',
            v_active_schedule_id
          )
        else
          format(
            'Verifica storica chiusa senza nuovo retry: circuit breaker %s già aperto.',
            v_open_breaker_id
          )
      end;

      insert into public.provider_recovery_outcome_certificates (
        league_id,
        request_id,
        incident_id,
        recovery_run_id,
        provider,
        sync_type,
        outcome,
        incident_status,
        incident_revision,
        source_snapshot_id,
        source_snapshot_status,
        anomaly_count,
        verification_summary,
        certificate_fingerprint,
        created_at
      ) values (
        v_request.league_id,
        v_request.id,
        v_request.incident_id,
        v_request.recovery_run_id,
        v_request.provider,
        v_request.sync_type,
        v_outcome,
        v_incident.status,
        v_incident.revision,
        v_snapshot.id,
        v_snapshot.status,
        coalesce(v_snapshot.anomaly_count, 0),
        v_summary,
        pg_catalog.md5(
          v_request.id::text || E'\n'
          || v_request.recovery_run_id::text || E'\n'
          || v_incident.id::text || E'\n'
          || v_incident.status || E'\n'
          || v_incident.revision::text || E'\n'
          || v_outcome || E'\n'
          || coalesce(v_snapshot.id::text, '') || E'\n'
          || coalesce(v_snapshot.status, '') || E'\n'
          || coalesce(v_snapshot.anomaly_count, 0)::text || E'\n'
          || coalesce(v_superseding_request_id::text, '') || E'\n'
          || coalesce(v_active_schedule_id::text, '') || E'\n'
          || coalesce(v_open_breaker_id::text, '')
        ),
        coalesce(v_request.finished_at, now())
      )
      on conflict (request_id) do nothing
      returning id into v_certificate_id;
    else
      select coalesce(max(schedule_row.retry_no), 0)
      into v_current_retry_no
    from public.provider_recovery_retry_schedules schedule_row
    where schedule_row.retry_request_id = v_request.id;

    v_next_retry_no := v_current_retry_no + 1;
    v_summary := case
      when v_snapshot.id is null then
        'Recupero provider completato ma non certificabile: fotografia qualità assente e incidente ancora aperto.'
      when v_snapshot.status = 'attention' then
        format(
          'Recupero provider completato ma inefficace: incidente ancora aperto e %s anomalie rilevate.',
          coalesce(v_snapshot.anomaly_count, 0)
        )
      else
        'Recupero provider completato ma inefficace: incidente ancora aperto dopo la verifica.'
    end;

    v_policy := public.provider_recovery_retry_policy_v1(
      v_summary,
      v_next_retry_no,
      v_request.sync_type
    );
    v_retryable := coalesce((v_policy ->> 'retryable')::boolean, false);
    v_delay_seconds := greatest(
      coalesce((v_policy ->> 'delaySeconds')::integer, 0),
      0
    );
    v_failure_class := coalesce(v_policy ->> 'failureClass', 'provider');
    v_max_retries := greatest(
      coalesce((v_policy ->> 'maxRetries')::integer, 3),
      1
    );
    v_schedule_status := case when v_retryable then 'scheduled' else 'exhausted' end;

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
      v_request.league_id,
      v_request.incident_id,
      v_request.id,
      v_request.provider,
      v_request.sync_type,
      v_next_retry_no,
      v_max_retries,
      v_failure_class,
      v_retryable,
      v_schedule_status,
      now() + (v_delay_seconds * interval '1 second'),
      v_request.revision,
      v_summary,
      case when v_retryable then null else now() end
    )
    on conflict (source_request_id) do nothing
    returning * into v_schedule;

    if v_schedule.id is null then
      select schedule_row.*
      into v_schedule
      from public.provider_recovery_retry_schedules schedule_row
      where schedule_row.source_request_id = v_request.id;
    end if;

    if v_schedule.id is null then
      raise exception
        'Pianificazione della verifica esito non creata per la richiesta %.',
        v_request.id;
    end if;

    v_outcome := case
      when v_schedule.status = 'exhausted' then 'exhausted'
      else 'retry_scheduled'
    end;

    insert into public.provider_recovery_outcome_certificates (
      league_id,
      request_id,
      incident_id,
      recovery_run_id,
      provider,
      sync_type,
      outcome,
      incident_status,
      incident_revision,
      source_snapshot_id,
      source_snapshot_status,
      anomaly_count,
      retry_schedule_id,
      retry_no,
      max_retries,
      verification_summary,
      certificate_fingerprint,
      created_at
    ) values (
      v_request.league_id,
      v_request.id,
      v_request.incident_id,
      v_request.recovery_run_id,
      v_request.provider,
      v_request.sync_type,
      v_outcome,
      v_incident.status,
      v_incident.revision,
      v_snapshot.id,
      v_snapshot.status,
      coalesce(v_snapshot.anomaly_count, 0),
      v_schedule.id,
      v_schedule.retry_no,
      v_schedule.max_retries,
      v_summary,
      pg_catalog.md5(
        v_request.id::text || E'\n'
        || v_request.recovery_run_id::text || E'\n'
        || v_incident.id::text || E'\n'
        || v_incident.status || E'\n'
        || v_incident.revision::text || E'\n'
        || v_outcome || E'\n'
        || coalesce(v_snapshot.id::text, '') || E'\n'
        || coalesce(v_snapshot.status, '') || E'\n'
        || coalesce(v_snapshot.anomaly_count, 0)::text || E'\n'
        || v_schedule.id::text || E'\n'
        || v_schedule.retry_no::text || E'\n'
        || v_schedule.max_retries::text
      ),
      coalesce(v_request.finished_at, now())
    )
    on conflict (request_id) do nothing
    returning id into v_certificate_id;
    end if;
  end if;

  if v_certificate_id is null then
    select certificate_row.id
    into v_certificate_id
    from public.provider_recovery_outcome_certificates certificate_row
    where certificate_row.request_id = v_request.id;
  end if;

  if v_certificate_id is null then
    raise exception
      'Certificato esito non creato per la richiesta provider %.',
      v_request.id;
  end if;

  return v_certificate_id;
end;
$$;

revoke all on function public.certify_provider_recovery_request_outcome_v1(uuid)
from public, anon, authenticated;
grant execute on function public.certify_provider_recovery_request_outcome_v1(uuid)
to service_role;

-- Il nome alfabeticamente successivo garantisce che l'incidente e la fotografia
-- qualità siano già stati aggiornati dagli handler validati prima del controllo.
create or replace function public.capture_provider_recovery_outcome_certificate_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_request record;
begin
  if new.event_type <> 'completed' then
    return new;
  end if;

  for v_request in
    select request_row.id
    from public.provider_recovery_requests request_row
    where request_row.recovery_run_id = new.run_id
      and request_row.status = 'completed'
    order by request_row.finished_at desc nulls last, request_row.id desc
  loop
    perform public.certify_provider_recovery_request_outcome_v1(v_request.id);
  end loop;

  return new;
end;
$$;

revoke all on function public.capture_provider_recovery_outcome_certificate_v1()
from public, anon, authenticated;

drop trigger if exists zz_provider_recovery_outcome_certifier
on public.provider_sync_run_events;
create trigger zz_provider_recovery_outcome_certifier
after insert on public.provider_sync_run_events
for each row execute function public.capture_provider_recovery_outcome_certificate_v1();

-- Finché la verifica ha già pianificato un retry, una nuova richiesta manuale
-- non può aprire una catena parallela. Il dispatcher automatico è ammesso solo
-- con la chiave idempotente uguale all'id della pianificazione e senza sessione
-- utente, come avviene nel worker service_role già validato.
create or replace function public.guard_provider_recovery_pending_verification_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_schedule public.provider_recovery_retry_schedules%rowtype;
begin
  select schedule_row.*
  into v_schedule
  from public.provider_recovery_retry_schedules schedule_row
  where schedule_row.incident_id = new.incident_id
    and schedule_row.status in ('scheduled', 'dispatched')
  order by schedule_row.available_at asc, schedule_row.created_at asc
  limit 1;

  if found and (
    auth.uid() is not null
    or new.idempotency_key is distinct from v_schedule.id
  ) then
    raise exception
      'Verifica efficacia provider in corso. Retry % nello stato %: attendere la conclusione prima di accodare un nuovo recupero.',
      v_schedule.id,
      v_schedule.status;
  end if;

  return new;
end;
$$;

revoke all on function public.guard_provider_recovery_pending_verification_v1()
from public, anon, authenticated;

drop trigger if exists provider_recovery_pending_verification_guard
on public.provider_recovery_requests;
create trigger provider_recovery_pending_verification_guard
before insert on public.provider_recovery_requests
for each row execute function public.guard_provider_recovery_pending_verification_v1();

-- Backfill idempotente dei recuperi completed precedenti alla v0.62.10. Non
-- modifica partite, voti o risultati; crea soltanto certificati e, se serve,
-- continua la catena retry già prevista dal modello.
do $backfill$
declare
  v_request record;
begin
  for v_request in
    select request_row.id
    from public.provider_recovery_requests request_row
    where request_row.status = 'completed'
      and request_row.recovery_run_id is not null
      and not exists (
        select 1
        from public.provider_recovery_outcome_certificates certificate_row
        where certificate_row.request_id = request_row.id
      )
    order by request_row.finished_at desc nulls last, request_row.id desc
  loop
    perform public.certify_provider_recovery_request_outcome_v1(v_request.id);
  end loop;
end;
$backfill$;

create or replace function public.get_league_provider_outcome_verification_center_v1(
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
  v_verified_last_24h integer := 0;
  v_ineffective_last_24h integer := 0;
  v_active_retry_count integer := 0;
  v_exhausted_open_count integer := 0;
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
    raise exception 'La verifica esito provider è riservata alla Direzione.';
  end if;

  select
    count(*) filter (
      where certificate_row.outcome = 'verified'
        and certificate_row.created_at >= now() - interval '24 hours'
    )::integer,
    count(*) filter (
      where certificate_row.outcome in ('retry_scheduled', 'exhausted')
        and certificate_row.created_at >= now() - interval '24 hours'
    )::integer,
    count(*) filter (
      where certificate_row.outcome = 'retry_scheduled'
        and exists (
          select 1
          from public.provider_recovery_retry_schedules schedule_row
          where schedule_row.id = certificate_row.retry_schedule_id
            and schedule_row.status in ('scheduled', 'dispatched')
        )
    )::integer,
    count(*) filter (
      where certificate_row.outcome = 'exhausted'
        and exists (
          select 1
          from public.provider_recovery_circuit_breakers breaker_row
          where breaker_row.source_schedule_id = certificate_row.retry_schedule_id
            and breaker_row.status = 'open'
        )
    )::integer
  into
    v_verified_last_24h,
    v_ineffective_last_24h,
    v_active_retry_count,
    v_exhausted_open_count
  from public.provider_recovery_outcome_certificates certificate_row
  where certificate_row.league_id = p_league_id;

  select jsonb_build_object(
    'id', certificate_row.id,
    'requestId', certificate_row.request_id,
    'incidentId', certificate_row.incident_id,
    'syncType', certificate_row.sync_type,
    'outcome', certificate_row.outcome,
    'snapshotStatus', certificate_row.source_snapshot_status,
    'anomalyCount', certificate_row.anomaly_count,
    'retryNo', certificate_row.retry_no,
    'maxRetries', certificate_row.max_retries,
    'summary', certificate_row.verification_summary,
    'createdAt', certificate_row.created_at
  )
  into v_latest
  from public.provider_recovery_outcome_certificates certificate_row
  where certificate_row.league_id = p_league_id
  order by certificate_row.created_at desc, certificate_row.id desc
  limit 1;

  return jsonb_build_object(
    'protected', true,
    'healthy', coalesce(v_exhausted_open_count, 0) = 0,
    'outcomeVerificationActive', true,
    'verifiedLast24h', coalesce(v_verified_last_24h, 0),
    'ineffectiveLast24h', coalesce(v_ineffective_last_24h, 0),
    'activeRetryCount', coalesce(v_active_retry_count, 0),
    'exhaustedOpenCount', coalesce(v_exhausted_open_count, 0),
    'latest', v_latest
  );
end;
$$;

revoke all on function public.get_league_provider_outcome_verification_center_v1(uuid)
from public, anon, authenticated;
grant execute on function public.get_league_provider_outcome_verification_center_v1(uuid)
to authenticated;

create or replace function public.get_league_provider_retry_center_v3(
  p_league_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_retry jsonb;
  v_verification jsonb;
begin
  v_retry := public.get_league_provider_retry_center_v2(p_league_id);
  v_verification := public.get_league_provider_outcome_verification_center_v1(
    p_league_id
  );

  return v_retry || jsonb_build_object(
    'outcomeVerification', v_verification
  );
end;
$$;

revoke all on function public.get_league_provider_retry_center_v3(uuid)
from public, anon, authenticated;
grant execute on function public.get_league_provider_retry_center_v3(uuid)
to authenticated;

create or replace function public.get_league_provider_recovery_center_v6(
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
  v_verification jsonb;
  v_healthy boolean;
  v_can_request boolean;
begin
  v_center := public.get_league_provider_recovery_center_v5(p_league_id);
  v_retry := public.get_league_provider_retry_center_v3(p_league_id);
  v_verification := public.get_league_provider_outcome_verification_center_v1(
    p_league_id
  );
  v_healthy := coalesce((v_center ->> 'healthy')::boolean, false)
    and coalesce((v_verification ->> 'healthy')::boolean, false);
  v_can_request := coalesce((v_center ->> 'canRequest')::boolean, false)
    and coalesce((v_verification ->> 'activeRetryCount')::integer, 0) = 0
    and coalesce((v_verification ->> 'exhaustedOpenCount')::integer, 0) = 0;

  return v_center || jsonb_build_object(
    'healthy', v_healthy,
    'canRequest', v_can_request,
    'retryCenter', v_retry,
    'outcomeVerification', v_verification
  );
end;
$$;

revoke all on function public.get_league_provider_recovery_center_v6(uuid)
from public, anon, authenticated;
grant execute on function public.get_league_provider_recovery_center_v6(uuid)
to authenticated;

create or replace function public.get_league_provider_sync_health_v9(
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
  v_health := public.get_league_provider_sync_health_v8(p_league_id);
  v_recovery := public.get_league_provider_recovery_center_v6(p_league_id);
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

revoke all on function public.get_league_provider_sync_health_v9(uuid)
from public, anon, authenticated;
grant execute on function public.get_league_provider_sync_health_v9(uuid)
to authenticated;

-- Realtime espone certificati tecnici senza payload requested_for, chiavi o
-- motivazioni private della Direzione.
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
      and publication_table.tablename = 'provider_recovery_outcome_certificates'
  ) then
    alter publication supabase_realtime
      add table public.provider_recovery_outcome_certificates;
  end if;
end;
$realtime$;

create or replace function public.get_provider_recovery_outcome_verification_integrity_v1()
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
  v_previous := public.get_provider_recovery_circuit_breaker_integrity_v1();
  select not exists (
    select 1
    from jsonb_each(v_previous) check_row
    where check_row.value is distinct from 'true'::jsonb
  ) into v_previous_ready;

  return jsonb_build_object(
    'predecessor_ready', v_previous_ready,
    'certificate_table_ready',
      to_regclass('public.provider_recovery_outcome_certificates') is not null,
    'certificate_columns_ready',
      (
        select count(*) = 19
        from information_schema.columns column_row
        where column_row.table_schema = 'public'
          and column_row.table_name = 'provider_recovery_outcome_certificates'
          and column_row.column_name in (
            'id', 'league_id', 'request_id', 'incident_id', 'recovery_run_id',
            'provider', 'sync_type', 'outcome', 'incident_status',
            'incident_revision', 'source_snapshot_id', 'source_snapshot_status',
            'anomaly_count', 'retry_schedule_id', 'retry_no', 'max_retries',
            'verification_summary', 'certificate_fingerprint', 'created_at'
          )
      ),
    'certificate_constraints_ready',
      exists (
        select 1
        from pg_catalog.pg_constraint constraint_row
        where constraint_row.conrelid =
          'public.provider_recovery_outcome_certificates'::regclass
          and constraint_row.contype = 'u'
          and pg_get_constraintdef(constraint_row.oid) like '%request_id%'
      )
      and exists (
        select 1
        from pg_catalog.pg_constraint constraint_row
        where constraint_row.conrelid =
          'public.provider_recovery_outcome_certificates'::regclass
          and constraint_row.contype = 'c'
          and pg_get_constraintdef(constraint_row.oid) like '%retry_scheduled%'
          and pg_get_constraintdef(constraint_row.oid) like '%superseded%'
      ),
    'certificate_indexes_ready',
      to_regclass('public.provider_recovery_outcome_certificates_league_idx') is not null
      and to_regclass('public.provider_recovery_outcome_certificates_incident_idx') is not null
      and to_regclass('public.provider_recovery_outcome_certificates_outcome_idx') is not null,
    'certificate_rls_ready',
      exists (
        select 1
        from pg_catalog.pg_class class_row
        where class_row.oid =
          'public.provider_recovery_outcome_certificates'::regclass
          and class_row.relrowsecurity
          and class_row.relreplident = 'f'
      ),
    'certificate_policy_ready',
      exists (
        select 1
        from pg_catalog.pg_policies policy_row
        where policy_row.schemaname = 'public'
          and policy_row.tablename = 'provider_recovery_outcome_certificates'
          and policy_row.policyname =
            'provider_recovery_outcome_certificates_read_directors'
          and policy_row.cmd = 'SELECT'
      ),
    'certificate_privileges_ready',
      has_table_privilege(
        'authenticated',
        'public.provider_recovery_outcome_certificates',
        'SELECT'
      )
      and not has_table_privilege(
        'authenticated',
        'public.provider_recovery_outcome_certificates',
        'INSERT'
      )
      and has_table_privilege(
        'service_role',
        'public.provider_recovery_outcome_certificates',
        'INSERT'
      ),
    'certificate_immutability_ready',
      to_regprocedure(
        'public.prevent_provider_recovery_outcome_certificate_mutation_v1()'
      ) is not null
      and exists (
        select 1
        from pg_catalog.pg_trigger trigger_row
        where trigger_row.tgname =
          'provider_recovery_outcome_certificates_immutable'
          and trigger_row.tgrelid =
            'public.provider_recovery_outcome_certificates'::regclass
          and not trigger_row.tgisinternal
      ),
    'certifier_rpc_ready',
      to_regprocedure(
        'public.certify_provider_recovery_request_outcome_v1(uuid)'
      ) is not null
      and has_function_privilege(
        'service_role',
        'public.certify_provider_recovery_request_outcome_v1(uuid)',
        'EXECUTE'
      )
      and not has_function_privilege(
        'authenticated',
        'public.certify_provider_recovery_request_outcome_v1(uuid)',
        'EXECUTE'
      ),
    'completion_trigger_ready',
      to_regprocedure(
        'public.capture_provider_recovery_outcome_certificate_v1()'
      ) is not null
      and exists (
        select 1
        from pg_catalog.pg_trigger trigger_row
        where trigger_row.tgname = 'zz_provider_recovery_outcome_certifier'
          and trigger_row.tgrelid =
            'public.provider_sync_run_events'::regclass
          and not trigger_row.tgisinternal
      )
      and to_regprocedure(
        'public.guard_provider_recovery_pending_verification_v1()'
      ) is not null
      and exists (
        select 1
        from pg_catalog.pg_trigger trigger_row
        where trigger_row.tgname =
          'provider_recovery_pending_verification_guard'
          and trigger_row.tgrelid =
            'public.provider_recovery_requests'::regclass
          and not trigger_row.tgisinternal
      ),
    'trigger_order_dependencies_ready',
      exists (
        select 1
        from pg_catalog.pg_trigger trigger_row
        where trigger_row.tgname = 'provider_sync_run_event_writer'
          and trigger_row.tgrelid =
            'public.provider_sync_runs'::regclass
          and not trigger_row.tgisinternal
      )
      and exists (
        select 1
        from pg_catalog.pg_trigger trigger_row
        where trigger_row.tgname = 'provider_sync_incident_capture'
          and trigger_row.tgrelid =
            'public.provider_sync_run_events'::regclass
          and not trigger_row.tgisinternal
      )
      and exists (
        select 1
        from pg_catalog.pg_trigger trigger_row
        where trigger_row.tgname = 'provider_sync_quality_snapshot_writer'
          and trigger_row.tgrelid =
            'public.provider_sync_run_events'::regclass
          and not trigger_row.tgisinternal
      )
      and exists (
        select 1
        from pg_catalog.pg_trigger trigger_row
        where trigger_row.tgname = 'provider_quality_incident_capture'
          and trigger_row.tgrelid =
            'public.provider_data_quality_snapshots'::regclass
          and not trigger_row.tgisinternal
      )
      and 'provider_recovery_run_outcome_capture' <
        'provider_sync_run_event_writer'
      and 'provider_sync_incident_capture' <
        'zz_provider_recovery_outcome_certifier'
      and 'provider_sync_quality_snapshot_writer' <
        'zz_provider_recovery_outcome_certifier',
    'retry_policy_continuity_ready',
      to_regprocedure(
        'public.provider_recovery_retry_policy_v1(text,integer,text)'
      ) is not null
      and to_regclass('public.provider_recovery_retry_schedules') is not null,
    'circuit_continuity_ready',
      exists (
        select 1
        from pg_catalog.pg_trigger trigger_row
        where trigger_row.tgname = 'provider_recovery_circuit_breaker_opener'
          and trigger_row.tgrelid =
            'public.provider_recovery_retry_schedules'::regclass
          and not trigger_row.tgisinternal
      )
      and to_regclass('public.provider_recovery_circuit_breakers') is not null,
    'verification_center_ready',
      to_regprocedure(
        'public.get_league_provider_outcome_verification_center_v1(uuid)'
      ) is not null
      and has_function_privilege(
        'authenticated',
        'public.get_league_provider_outcome_verification_center_v1(uuid)',
        'EXECUTE'
      ),
    'retry_center_v3_ready',
      to_regprocedure('public.get_league_provider_retry_center_v3(uuid)') is not null
      and has_function_privilege(
        'authenticated',
        'public.get_league_provider_retry_center_v3(uuid)',
        'EXECUTE'
      ),
    'recovery_center_v6_ready',
      to_regprocedure('public.get_league_provider_recovery_center_v6(uuid)') is not null
      and has_function_privilege(
        'authenticated',
        'public.get_league_provider_recovery_center_v6(uuid)',
        'EXECUTE'
      ),
    'sync_health_v9_ready',
      to_regprocedure('public.get_league_provider_sync_health_v9(uuid)') is not null
      and has_function_privilege(
        'authenticated',
        'public.get_league_provider_sync_health_v9(uuid)',
        'EXECUTE'
      ),
    'realtime_ready',
      exists (
        select 1
        from pg_catalog.pg_publication_tables publication_table
        where publication_table.pubname = 'supabase_realtime'
          and publication_table.schemaname = 'public'
          and publication_table.tablename =
            'provider_recovery_outcome_certificates'
      ),
    'runtime_consistency_ready',
      not exists (
        select 1
        from public.provider_recovery_outcome_certificates certificate_row
        left join public.provider_recovery_requests request_row
          on request_row.id = certificate_row.request_id
        where request_row.id is null
          or request_row.status <> 'completed'
          or request_row.recovery_run_id is distinct from
            certificate_row.recovery_run_id
          or (
            certificate_row.outcome = 'verified'
            and certificate_row.incident_status <> 'resolved'
          )
          or (
            certificate_row.outcome = 'superseded'
            and (
              certificate_row.incident_status <> 'open'
              or certificate_row.retry_schedule_id is not null
            )
          )
          or (
            certificate_row.outcome in ('retry_scheduled', 'exhausted')
            and not exists (
              select 1
              from public.provider_recovery_retry_schedules schedule_row
              where schedule_row.id = certificate_row.retry_schedule_id
                and schedule_row.source_request_id = certificate_row.request_id
            )
          )
      )
      and not exists (
        select 1
        from public.provider_recovery_requests request_row
        where request_row.status = 'completed'
          and request_row.recovery_run_id is not null
          and not exists (
            select 1
            from public.provider_recovery_outcome_certificates certificate_row
            where certificate_row.request_id = request_row.id
          )
      )
  );
end;
$$;

revoke all on function public.get_provider_recovery_outcome_verification_integrity_v1()
from public, anon, authenticated;
grant execute on function public.get_provider_recovery_outcome_verification_integrity_v1()
to authenticated, service_role;

-- Arresta la transazione indicando i nomi esatti degli eventuali controlli falsi.
do $validation$
declare
  v_checks jsonb;
  v_failed text[];
begin
  v_checks := public.get_provider_recovery_outcome_verification_integrity_v1();

  select array_agg(check_row.key order by check_row.key)
  into v_failed
  from jsonb_each(v_checks) check_row
  where check_row.value is distinct from 'true'::jsonb;

  if coalesce(array_length(v_failed, 1), 0) > 0 then
    raise exception
      'Validazione v0.62.10 non superata. Controlli falsi: %',
      array_to_string(v_failed, '; ');
  end if;
end;
$validation$;

commit;

-- Diagnostica finale: devono comparire esattamente 20 valori true.
select
  (checks ->> 'predecessor_ready')::boolean as predecessor_ready,
  (checks ->> 'certificate_table_ready')::boolean as certificate_table_ready,
  (checks ->> 'certificate_columns_ready')::boolean as certificate_columns_ready,
  (checks ->> 'certificate_constraints_ready')::boolean as certificate_constraints_ready,
  (checks ->> 'certificate_indexes_ready')::boolean as certificate_indexes_ready,
  (checks ->> 'certificate_rls_ready')::boolean as certificate_rls_ready,
  (checks ->> 'certificate_policy_ready')::boolean as certificate_policy_ready,
  (checks ->> 'certificate_privileges_ready')::boolean as certificate_privileges_ready,
  (checks ->> 'certificate_immutability_ready')::boolean as certificate_immutability_ready,
  (checks ->> 'certifier_rpc_ready')::boolean as certifier_rpc_ready,
  (checks ->> 'completion_trigger_ready')::boolean as completion_trigger_ready,
  (checks ->> 'trigger_order_dependencies_ready')::boolean as trigger_order_dependencies_ready,
  (checks ->> 'retry_policy_continuity_ready')::boolean as retry_policy_continuity_ready,
  (checks ->> 'circuit_continuity_ready')::boolean as circuit_continuity_ready,
  (checks ->> 'verification_center_ready')::boolean as verification_center_ready,
  (checks ->> 'retry_center_v3_ready')::boolean as retry_center_v3_ready,
  (checks ->> 'recovery_center_v6_ready')::boolean as recovery_center_v6_ready,
  (checks ->> 'sync_health_v9_ready')::boolean as sync_health_v9_ready,
  (checks ->> 'realtime_ready')::boolean as realtime_ready,
  (checks ->> 'runtime_consistency_ready')::boolean as runtime_consistency_ready
from (
  select public.get_provider_recovery_outcome_verification_integrity_v1() as checks
) diagnostic;
