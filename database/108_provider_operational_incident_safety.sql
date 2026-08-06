-- LEGHEVO v0.62.4 · Incidenti operativi provider protetti
-- Migrazione interna: database/108_provider_operational_incident_safety.sql
--
-- Obiettivi:
-- - aprire automaticamente un incidente dopo un sync fallito o una fotografia qualità critica;
-- - aggiornare lo stesso incidente senza duplicazioni;
-- - risolverlo automaticamente dopo un nuovo esito regolare;
-- - conservare un registro immutabile delle revisioni;
-- - mostrare il ciclo degli incidenti nel Centro Operativo;
-- - diagnostica strutturale finale di 20 controlli.

begin;

-- Preflight: nessuna scrittura viene applicata se manca una dipendenza validata
-- nelle versioni v0.62.2 e v0.62.3.
do $preflight$
declare
  v_missing text[] := array[]::text[];
  v_expected record;
begin
  for v_expected in
    select *
    from (values
      ('provider_sync_runs', 'id'),
      ('provider_sync_runs', 'provider'),
      ('provider_sync_runs', 'sync_type'),
      ('provider_sync_runs', 'status'),
      ('provider_sync_runs', 'attempt_no'),
      ('provider_sync_runs', 'error_message'),
      ('provider_sync_run_events', 'id'),
      ('provider_sync_run_events', 'run_id'),
      ('provider_sync_run_events', 'provider'),
      ('provider_sync_run_events', 'sync_type'),
      ('provider_sync_run_events', 'event_type'),
      ('provider_sync_run_events', 'created_at'),
      ('provider_data_quality_snapshots', 'id'),
      ('provider_data_quality_snapshots', 'run_id'),
      ('provider_data_quality_snapshots', 'provider'),
      ('provider_data_quality_snapshots', 'sync_type'),
      ('provider_data_quality_snapshots', 'status'),
      ('provider_data_quality_snapshots', 'anomaly_count'),
      ('provider_data_quality_snapshots', 'metrics'),
      ('provider_data_quality_snapshots', 'created_at'),
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
  if to_regprocedure('public.get_league_provider_sync_health_v2(uuid)') is null then
    v_missing := array_append(
      v_missing,
      'function public.get_league_provider_sync_health_v2(uuid)'
    );
  end if;

  if coalesce(array_length(v_missing, 1), 0) > 0 then
    raise exception
      'Preflight v0.62.4 non superato. Oggetti mancanti: %',
      array_to_string(v_missing, '; ');
  end if;
end;
$preflight$;

create table if not exists public.provider_operational_incidents (
  id uuid primary key default gen_random_uuid(),
  provider text not null,
  incident_key text not null,
  incident_type text not null check (
    incident_type in ('sync_failure', 'data_quality')
  ),
  sync_type text not null,
  severity text not null check (severity in ('warning', 'critical')),
  status text not null check (status in ('open', 'resolved')),
  occurrence_count integer not null default 1 check (occurrence_count > 0),
  revision bigint not null default 1 check (revision > 0),
  source_run_id uuid references public.provider_sync_runs(id) on delete set null,
  source_snapshot_id uuid references public.provider_data_quality_snapshots(id)
    on delete set null,
  summary text not null,
  state_fingerprint text not null check (char_length(state_fingerprint) = 32),
  first_detected_at timestamptz not null default now(),
  last_detected_at timestamptz not null default now(),
  resolved_at timestamptz,
  updated_at timestamptz not null default now(),
  check (
    (status = 'open' and resolved_at is null)
    or (status = 'resolved' and resolved_at is not null)
  )
);

create unique index if not exists provider_operational_incidents_open_uidx
  on public.provider_operational_incidents (provider, incident_key)
  where status = 'open';
create index if not exists provider_operational_incidents_latest_idx
  on public.provider_operational_incidents (last_detected_at desc);
create index if not exists provider_operational_incidents_status_idx
  on public.provider_operational_incidents (provider, status, severity);

create table if not exists public.provider_operational_incident_events (
  id uuid primary key default gen_random_uuid(),
  incident_id uuid not null
    references public.provider_operational_incidents(id) on delete cascade,
  provider text not null,
  incident_key text not null,
  event_type text not null check (event_type in ('opened', 'updated', 'resolved')),
  severity text not null check (severity in ('warning', 'critical')),
  revision bigint not null check (revision > 0),
  occurrence_count integer not null check (occurrence_count > 0),
  event_fingerprint text not null check (char_length(event_fingerprint) = 32),
  created_at timestamptz not null default now(),
  unique (incident_id, revision)
);

create index if not exists provider_operational_incident_events_latest_idx
  on public.provider_operational_incident_events (created_at desc);
create index if not exists provider_operational_incident_events_key_idx
  on public.provider_operational_incident_events
  (provider, incident_key, created_at desc);

alter table public.provider_operational_incidents enable row level security;
alter table public.provider_operational_incidents replica identity full;
alter table public.provider_operational_incident_events enable row level security;
alter table public.provider_operational_incident_events replica identity full;

revoke all on table public.provider_operational_incidents
from public, anon, authenticated;
revoke all on table public.provider_operational_incident_events
from public, anon, authenticated;

grant select on table public.provider_operational_incidents to authenticated;
grant select on table public.provider_operational_incident_events to authenticated;
grant select, insert, update on table public.provider_operational_incidents
  to service_role;
grant select, insert on table public.provider_operational_incident_events
  to service_role;

drop policy if exists provider_operational_incidents_read_authenticated
on public.provider_operational_incidents;
create policy provider_operational_incidents_read_authenticated
on public.provider_operational_incidents
for select to authenticated
using (true);

drop policy if exists provider_operational_incident_events_read_authenticated
on public.provider_operational_incident_events;
create policy provider_operational_incident_events_read_authenticated
on public.provider_operational_incident_events
for select to authenticated
using (true);

create or replace function public.record_provider_operational_incident_event_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_event_type text;
begin
  if tg_op = 'INSERT' then
    v_event_type := 'opened';
  elsif new.status = 'resolved' and old.status = 'open' then
    v_event_type := 'resolved';
  else
    v_event_type := 'updated';
  end if;

  insert into public.provider_operational_incident_events (
    incident_id,
    provider,
    incident_key,
    event_type,
    severity,
    revision,
    occurrence_count,
    event_fingerprint,
    created_at
  ) values (
    new.id,
    new.provider,
    new.incident_key,
    v_event_type,
    new.severity,
    new.revision,
    new.occurrence_count,
    pg_catalog.md5(
      new.id::text || E'\n'
      || v_event_type || E'\n'
      || new.revision::text || E'\n'
      || new.occurrence_count::text || E'\n'
      || new.state_fingerprint
    ),
    new.updated_at
  )
  on conflict (incident_id, revision) do nothing;

  return new;
end;
$$;

revoke all on function public.record_provider_operational_incident_event_v1()
from public, anon, authenticated;

create or replace function public.prevent_provider_operational_incident_event_mutation_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  raise exception
    'Evento incidente provider certificato: modifica o cancellazione non consentita.';
end;
$$;

revoke all on function public.prevent_provider_operational_incident_event_mutation_v1()
from public, anon, authenticated;

drop trigger if exists provider_operational_incident_event_writer
on public.provider_operational_incidents;
create trigger provider_operational_incident_event_writer
after insert or update on public.provider_operational_incidents
for each row execute function public.record_provider_operational_incident_event_v1();

drop trigger if exists provider_operational_incident_events_immutable
on public.provider_operational_incident_events;
create trigger provider_operational_incident_events_immutable
before update or delete on public.provider_operational_incident_events
for each row execute function public.prevent_provider_operational_incident_event_mutation_v1();

create or replace function public.upsert_provider_operational_incident_v1(
  p_provider text,
  p_incident_key text,
  p_incident_type text,
  p_sync_type text,
  p_severity text,
  p_summary text,
  p_source_run_id uuid default null,
  p_source_snapshot_id uuid default null,
  p_detected_at timestamptz default now()
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_provider text := lower(trim(coalesce(p_provider, '')));
  v_key text := lower(trim(coalesce(p_incident_key, '')));
  v_type text := lower(trim(coalesce(p_incident_type, '')));
  v_sync_type text := lower(trim(coalesce(p_sync_type, '')));
  v_severity text := lower(trim(coalesce(p_severity, '')));
  v_summary text := left(trim(coalesce(p_summary, '')), 500);
  v_detected_at timestamptz := coalesce(p_detected_at, now());
  v_existing public.provider_operational_incidents%rowtype;
  v_revision bigint;
  v_occurrences integer;
  v_id uuid;
begin
  if v_provider = '' or v_key = '' or v_sync_type = '' then
    raise exception 'Identità incidente provider non valida.';
  end if;
  if v_type not in ('sync_failure', 'data_quality') then
    raise exception 'Tipo incidente provider non valido.';
  end if;
  if v_severity not in ('warning', 'critical') then
    raise exception 'Gravità incidente provider non valida.';
  end if;
  if v_summary = '' then
    raise exception 'Descrizione incidente provider obbligatoria.';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext(v_provider || ':' || v_key)
  );

  select incident.*
  into v_existing
  from public.provider_operational_incidents incident
  where incident.provider = v_provider
    and incident.incident_key = v_key
    and incident.status = 'open'
  order by incident.last_detected_at desc
  limit 1
  for update;

  if found then
    if p_source_snapshot_id is not null
      and v_existing.source_snapshot_id = p_source_snapshot_id then
      return v_existing.id;
    end if;
    if p_source_snapshot_id is null
      and p_source_run_id is not null
      and v_existing.source_run_id = p_source_run_id
      and v_existing.incident_type = v_type then
      return v_existing.id;
    end if;

    v_revision := v_existing.revision + 1;
    v_occurrences := v_existing.occurrence_count + 1;

    update public.provider_operational_incidents incident
    set
      severity = case
        when incident.severity = 'critical' or v_severity = 'critical'
          then 'critical'
        else 'warning'
      end,
      occurrence_count = v_occurrences,
      revision = v_revision,
      source_run_id = coalesce(p_source_run_id, incident.source_run_id),
      source_snapshot_id = coalesce(
        p_source_snapshot_id,
        incident.source_snapshot_id
      ),
      summary = v_summary,
      last_detected_at = greatest(incident.last_detected_at, v_detected_at),
      updated_at = now(),
      state_fingerprint = pg_catalog.md5(
        incident.id::text || E'\nopen\n'
        || v_revision::text || E'\n'
        || v_occurrences::text || E'\n'
        || case
          when incident.severity = 'critical' or v_severity = 'critical'
            then 'critical'
          else 'warning'
        end || E'\n'
        || coalesce(
          coalesce(p_source_run_id, incident.source_run_id)::text,
          ''
        ) || E'\n'
        || coalesce(
          coalesce(
            p_source_snapshot_id,
            incident.source_snapshot_id
          )::text,
          ''
        )
      )
    where incident.id = v_existing.id
    returning incident.id into v_id;

    return v_id;
  end if;

  v_id := gen_random_uuid();
  insert into public.provider_operational_incidents (
    id,
    provider,
    incident_key,
    incident_type,
    sync_type,
    severity,
    status,
    occurrence_count,
    revision,
    source_run_id,
    source_snapshot_id,
    summary,
    state_fingerprint,
    first_detected_at,
    last_detected_at,
    updated_at
  ) values (
    v_id,
    v_provider,
    v_key,
    v_type,
    v_sync_type,
    v_severity,
    'open',
    1,
    1,
    p_source_run_id,
    p_source_snapshot_id,
    v_summary,
    pg_catalog.md5(
      v_id::text || E'\nopen\n1\n1\n'
      || v_severity || E'\n'
      || coalesce(p_source_run_id::text, '') || E'\n'
      || coalesce(p_source_snapshot_id::text, '')
    ),
    v_detected_at,
    v_detected_at,
    now()
  );

  return v_id;
end;
$$;

revoke all on function public.upsert_provider_operational_incident_v1(
  text, text, text, text, text, text, uuid, uuid, timestamptz
) from public, anon, authenticated;
grant execute on function public.upsert_provider_operational_incident_v1(
  text, text, text, text, text, text, uuid, uuid, timestamptz
) to service_role;

create or replace function public.resolve_provider_operational_incident_v1(
  p_provider text,
  p_incident_key text,
  p_summary text,
  p_resolved_at timestamptz default now()
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_provider text := lower(trim(coalesce(p_provider, '')));
  v_key text := lower(trim(coalesce(p_incident_key, '')));
  v_summary text := left(trim(coalesce(p_summary, '')), 500);
  v_resolved_at timestamptz := coalesce(p_resolved_at, now());
  v_existing public.provider_operational_incidents%rowtype;
  v_revision bigint;
begin
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext(v_provider || ':' || v_key)
  );

  select incident.*
  into v_existing
  from public.provider_operational_incidents incident
  where incident.provider = v_provider
    and incident.incident_key = v_key
    and incident.status = 'open'
  order by incident.last_detected_at desc
  limit 1
  for update;

  if not found then
    return false;
  end if;

  v_revision := v_existing.revision + 1;
  update public.provider_operational_incidents incident
  set
    status = 'resolved',
    revision = v_revision,
    summary = case when v_summary = '' then incident.summary else v_summary end,
    resolved_at = v_resolved_at,
    updated_at = now(),
    state_fingerprint = pg_catalog.md5(
      incident.id::text || E'\nresolved\n'
      || v_revision::text || E'\n'
      || incident.occurrence_count::text || E'\n'
      || incident.severity || E'\n'
      || v_resolved_at::text
    )
  where incident.id = v_existing.id;

  return true;
end;
$$;

revoke all on function public.resolve_provider_operational_incident_v1(
  text, text, text, timestamptz
) from public, anon, authenticated;
grant execute on function public.resolve_provider_operational_incident_v1(
  text, text, text, timestamptz
) to service_role;

create or replace function public.capture_provider_sync_incident_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_attempt integer := 1;
begin
  if new.event_type = 'failed' then
    select greatest(coalesce(run_row.attempt_no, 1), 1)
    into v_attempt
    from public.provider_sync_runs run_row
    where run_row.id = new.run_id;

    perform public.upsert_provider_operational_incident_v1(
      new.provider,
      'sync_failure:' || new.sync_type,
      'sync_failure',
      new.sync_type,
      case when v_attempt >= 3 then 'critical' else 'warning' end,
      case
        when v_attempt >= 3
          then 'Sincronizzazione provider fallita ripetutamente.'
        else 'Sincronizzazione provider fallita.'
      end,
      new.run_id,
      null,
      new.created_at
    );
  elsif new.event_type = 'completed' then
    perform public.resolve_provider_operational_incident_v1(
      new.provider,
      'sync_failure:' || new.sync_type,
      'Sincronizzazione provider ripristinata.',
      new.created_at
    );
  end if;

  return new;
end;
$$;

revoke all on function public.capture_provider_sync_incident_v1()
from public, anon, authenticated;

create or replace function public.capture_provider_quality_incident_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_stale boolean := coalesce((new.metrics ->> 'stale')::boolean, false);
  v_severity text;
begin
  if new.status = 'attention' then
    v_severity := case
      when v_stale or new.anomaly_count >= 3 then 'critical'
      else 'warning'
    end;

    perform public.upsert_provider_operational_incident_v1(
      new.provider,
      'data_quality:' || new.sync_type,
      'data_quality',
      new.sync_type,
      v_severity,
      case
        when v_stale then 'Dati provider non aggiornati entro la finestra prevista.'
        when new.anomaly_count = 1 then 'Rilevata 1 anomalia nei dati provider.'
        else format('Rilevate %s anomalie nei dati provider.', new.anomaly_count)
      end,
      new.run_id,
      new.id,
      new.created_at
    );
  else
    perform public.resolve_provider_operational_incident_v1(
      new.provider,
      'data_quality:' || new.sync_type,
      'Qualità dei dati provider ripristinata.',
      new.created_at
    );
  end if;

  return new;
end;
$$;

revoke all on function public.capture_provider_quality_incident_v1()
from public, anon, authenticated;

drop trigger if exists provider_sync_incident_capture
on public.provider_sync_run_events;
create trigger provider_sync_incident_capture
after insert on public.provider_sync_run_events
for each row execute function public.capture_provider_sync_incident_v1();

drop trigger if exists provider_quality_incident_capture
on public.provider_data_quality_snapshots;
create trigger provider_quality_incident_capture
after insert on public.provider_data_quality_snapshots
for each row execute function public.capture_provider_quality_incident_v1();

-- Backfill non distruttivo: viene considerato soltanto l'ultimo esito di ogni
-- flusso. Nessun run o dato sportivo viene alterato.
do $backfill$
declare
  v_run record;
  v_snapshot record;
begin
  for v_run in
    select distinct on (run_row.provider, run_row.sync_type)
      run_row.id,
      run_row.provider,
      run_row.sync_type,
      run_row.status,
      run_row.attempt_no,
      coalesce(run_row.finished_at, run_row.started_at) as detected_at
    from public.provider_sync_runs run_row
    order by
      run_row.provider,
      run_row.sync_type,
      run_row.started_at desc,
      run_row.attempt_no desc
  loop
    if v_run.status = 'failed' then
      perform public.upsert_provider_operational_incident_v1(
        v_run.provider,
        'sync_failure:' || v_run.sync_type,
        'sync_failure',
        v_run.sync_type,
        case when v_run.attempt_no >= 3 then 'critical' else 'warning' end,
        'Ultima sincronizzazione provider non riuscita.',
        v_run.id,
        null,
        v_run.detected_at
      );
    elsif v_run.status = 'completed' then
      perform public.resolve_provider_operational_incident_v1(
        v_run.provider,
        'sync_failure:' || v_run.sync_type,
        'Sincronizzazione provider ripristinata.',
        v_run.detected_at
      );
    end if;
  end loop;

  for v_snapshot in
    select distinct on (snapshot.provider, snapshot.sync_type)
      snapshot.id,
      snapshot.run_id,
      snapshot.provider,
      snapshot.sync_type,
      snapshot.status,
      snapshot.anomaly_count,
      snapshot.metrics,
      snapshot.created_at
    from public.provider_data_quality_snapshots snapshot
    order by snapshot.provider, snapshot.sync_type, snapshot.created_at desc
  loop
    if v_snapshot.status = 'attention' then
      perform public.upsert_provider_operational_incident_v1(
        v_snapshot.provider,
        'data_quality:' || v_snapshot.sync_type,
        'data_quality',
        v_snapshot.sync_type,
        case
          when coalesce((v_snapshot.metrics ->> 'stale')::boolean, false)
            or v_snapshot.anomaly_count >= 3 then 'critical'
          else 'warning'
        end,
        'Ultima fotografia della qualità provider richiede controllo.',
        v_snapshot.run_id,
        v_snapshot.id,
        v_snapshot.created_at
      );
    else
      perform public.resolve_provider_operational_incident_v1(
        v_snapshot.provider,
        'data_quality:' || v_snapshot.sync_type,
        'Qualità dei dati provider ripristinata.',
        v_snapshot.created_at
      );
    end if;
  end loop;
end;
$backfill$;

create or replace function public.get_league_provider_incident_center_v1(
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
  v_critical_count integer := 0;
  v_warning_count integer := 0;
  v_resolved_last_24h integer := 0;
  v_last_incident_at timestamptz;
  v_last_resolved_at timestamptz;
  v_incidents jsonb := '[]'::jsonb;
begin
  if auth.uid() is null then
    raise exception 'Devi effettuare l''accesso.';
  end if;

  select league.owner_id
  into v_owner_id
  from public.leagues league
  where league.id = p_league_id;

  if not found then
    raise exception 'Lega non trovata.';
  end if;

  if v_owner_id <> auth.uid()
    and not public.is_league_admin(p_league_id) then
    raise exception 'Il Centro Incidenti provider è riservato alla Direzione.';
  end if;

  select
    count(*)::integer,
    count(*) filter (where incident.severity = 'critical')::integer,
    count(*) filter (where incident.severity = 'warning')::integer,
    max(incident.last_detected_at)
  into
    v_active_count,
    v_critical_count,
    v_warning_count,
    v_last_incident_at
  from public.provider_operational_incidents incident
  where incident.provider = 'api-football'
    and incident.status = 'open';

  select
    count(*) filter (
      where incident.resolved_at >= now() - interval '24 hours'
    )::integer,
    max(incident.resolved_at)
  into v_resolved_last_24h, v_last_resolved_at
  from public.provider_operational_incidents incident
  where incident.provider = 'api-football'
    and incident.status = 'resolved';

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', incident.id,
        'type', incident.incident_type,
        'syncType', incident.sync_type,
        'severity', incident.severity,
        'status', incident.status,
        'occurrenceCount', incident.occurrence_count,
        'revision', incident.revision,
        'summary', incident.summary,
        'firstDetectedAt', incident.first_detected_at,
        'lastDetectedAt', incident.last_detected_at
      )
      order by
        case when incident.severity = 'critical' then 0 else 1 end,
        incident.last_detected_at desc
    ),
    '[]'::jsonb
  )
  into v_incidents
  from public.provider_operational_incidents incident
  where incident.provider = 'api-football'
    and incident.status = 'open';

  return jsonb_build_object(
    'protected', true,
    'healthy', coalesce(v_active_count, 0) = 0,
    'activeCount', coalesce(v_active_count, 0),
    'criticalCount', coalesce(v_critical_count, 0),
    'warningCount', coalesce(v_warning_count, 0),
    'resolvedLast24h', coalesce(v_resolved_last_24h, 0),
    'lastIncidentAt', v_last_incident_at,
    'lastResolvedAt', v_last_resolved_at,
    'incidents', v_incidents
  );
end;
$$;

revoke all on function public.get_league_provider_incident_center_v1(uuid)
from public, anon, authenticated;
grant execute on function public.get_league_provider_incident_center_v1(uuid)
to authenticated;

create or replace function public.get_league_provider_sync_health_v3(
  p_league_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_sync jsonb;
  v_incidents jsonb;
  v_attention boolean;
begin
  v_sync := public.get_league_provider_sync_health_v2(p_league_id);
  v_incidents := public.get_league_provider_incident_center_v1(p_league_id);
  v_attention := coalesce(v_sync ->> 'status', 'idle') = 'attention'
    or coalesce((v_incidents ->> 'activeCount')::integer, 0) > 0;

  return v_sync || jsonb_build_object(
    'healthy', not v_attention,
    'status', case
      when v_attention then 'attention'
      when coalesce(v_sync ->> 'status', 'idle') = 'idle' then 'idle'
      else 'healthy'
    end,
    'incidentCenter', v_incidents
  );
end;
$$;

revoke all on function public.get_league_provider_sync_health_v3(uuid)
from public, anon, authenticated;
grant execute on function public.get_league_provider_sync_health_v3(uuid)
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
        and publication_table.tablename = 'provider_operational_incidents'
    ) then
      alter publication supabase_realtime
        add table public.provider_operational_incidents;
    end if;

    if not exists (
      select 1
      from pg_catalog.pg_publication_tables publication_table
      where publication_table.pubname = 'supabase_realtime'
        and publication_table.schemaname = 'public'
        and publication_table.tablename = 'provider_operational_incident_events'
    ) then
      alter publication supabase_realtime
        add table public.provider_operational_incident_events;
    end if;
  end if;
end;
$realtime$;

create or replace function public.get_provider_operational_incident_integrity_v1()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'incidents_table_ready',
      to_regclass('public.provider_operational_incidents') is not null,
    'events_table_ready',
      to_regclass('public.provider_operational_incident_events') is not null,
    'incident_columns_ready',
      (
        select count(*) = 17
        from information_schema.columns column_row
        where column_row.table_schema = 'public'
          and column_row.table_name = 'provider_operational_incidents'
          and column_row.column_name in (
            'id', 'provider', 'incident_key', 'incident_type', 'sync_type',
            'severity', 'status', 'occurrence_count', 'revision',
            'source_run_id', 'source_snapshot_id', 'summary',
            'state_fingerprint', 'first_detected_at', 'last_detected_at',
            'resolved_at', 'updated_at'
          )
      ),
    'incident_indexes_ready',
      to_regclass('public.provider_operational_incidents_open_uidx') is not null
      and to_regclass('public.provider_operational_incidents_latest_idx') is not null
      and to_regclass('public.provider_operational_incidents_status_idx') is not null,
    'event_writer_ready',
      to_regprocedure(
        'public.record_provider_operational_incident_event_v1()'
      ) is not null,
    'event_writer_trigger_ready',
      exists (
        select 1 from pg_trigger trigger_row
        where trigger_row.tgname = 'provider_operational_incident_event_writer'
          and trigger_row.tgrelid =
            'public.provider_operational_incidents'::regclass
          and not trigger_row.tgisinternal
      ),
    'events_immutable_ready',
      to_regprocedure(
        'public.prevent_provider_operational_incident_event_mutation_v1()'
      ) is not null
      and exists (
        select 1 from pg_trigger trigger_row
        where trigger_row.tgname =
          'provider_operational_incident_events_immutable'
          and trigger_row.tgrelid =
            'public.provider_operational_incident_events'::regclass
          and not trigger_row.tgisinternal
      ),
    'incident_upsert_ready',
      to_regprocedure(
        'public.upsert_provider_operational_incident_v1(text,text,text,text,text,text,uuid,uuid,timestamptz)'
      ) is not null
      and has_function_privilege(
        'service_role',
        'public.upsert_provider_operational_incident_v1(text,text,text,text,text,text,uuid,uuid,timestamptz)',
        'EXECUTE'
      ),
    'incident_resolve_ready',
      to_regprocedure(
        'public.resolve_provider_operational_incident_v1(text,text,text,timestamptz)'
      ) is not null
      and has_function_privilege(
        'service_role',
        'public.resolve_provider_operational_incident_v1(text,text,text,timestamptz)',
        'EXECUTE'
      ),
    'sync_capture_ready',
      to_regprocedure('public.capture_provider_sync_incident_v1()') is not null
      and exists (
        select 1 from pg_trigger trigger_row
        where trigger_row.tgname = 'provider_sync_incident_capture'
          and trigger_row.tgrelid = 'public.provider_sync_run_events'::regclass
          and not trigger_row.tgisinternal
      ),
    'quality_capture_ready',
      to_regprocedure('public.capture_provider_quality_incident_v1()') is not null
      and exists (
        select 1 from pg_trigger trigger_row
        where trigger_row.tgname = 'provider_quality_incident_capture'
          and trigger_row.tgrelid =
            'public.provider_data_quality_snapshots'::regclass
          and not trigger_row.tgisinternal
      ),
    'incident_center_rpc_ready',
      to_regprocedure(
        'public.get_league_provider_incident_center_v1(uuid)'
      ) is not null,
    'health_v3_rpc_ready',
      to_regprocedure('public.get_league_provider_sync_health_v3(uuid)')
        is not null,
    'rls_policies_ready',
      coalesce((
        select class_row.relrowsecurity
        from pg_class class_row
        join pg_namespace namespace_row
          on namespace_row.oid = class_row.relnamespace
        where namespace_row.nspname = 'public'
          and class_row.relname = 'provider_operational_incidents'
      ), false)
      and coalesce((
        select class_row.relrowsecurity
        from pg_class class_row
        join pg_namespace namespace_row
          on namespace_row.oid = class_row.relnamespace
        where namespace_row.nspname = 'public'
          and class_row.relname = 'provider_operational_incident_events'
      ), false)
      and exists (
        select 1 from pg_policies policy_row
        where policy_row.schemaname = 'public'
          and policy_row.tablename = 'provider_operational_incidents'
          and policy_row.policyname =
            'provider_operational_incidents_read_authenticated'
      )
      and exists (
        select 1 from pg_policies policy_row
        where policy_row.schemaname = 'public'
          and policy_row.tablename = 'provider_operational_incident_events'
          and policy_row.policyname =
            'provider_operational_incident_events_read_authenticated'
      ),
    'authenticated_read_ready',
      has_table_privilege(
        'authenticated', 'public.provider_operational_incidents', 'SELECT'
      )
      and has_table_privilege(
        'authenticated',
        'public.provider_operational_incident_events',
        'SELECT'
      ),
    'authenticated_writes_blocked',
      not has_table_privilege(
        'authenticated', 'public.provider_operational_incidents', 'INSERT'
      )
      and not has_table_privilege(
        'authenticated', 'public.provider_operational_incidents', 'UPDATE'
      )
      and not has_table_privilege(
        'authenticated', 'public.provider_operational_incidents', 'DELETE'
      )
      and not has_table_privilege(
        'authenticated',
        'public.provider_operational_incident_events',
        'INSERT'
      ),
    'anonymous_tables_blocked',
      not has_table_privilege(
        'anon', 'public.provider_operational_incidents', 'SELECT'
      )
      and not has_table_privilege(
        'anon', 'public.provider_operational_incident_events', 'SELECT'
      ),
    'authenticated_rpc_ready',
      has_function_privilege(
        'authenticated',
        'public.get_league_provider_incident_center_v1(uuid)',
        'EXECUTE'
      )
      and has_function_privilege(
        'authenticated',
        'public.get_league_provider_sync_health_v3(uuid)',
        'EXECUTE'
      ),
    'anonymous_rpc_blocked',
      not has_function_privilege(
        'anon',
        'public.get_league_provider_incident_center_v1(uuid)',
        'EXECUTE'
      )
      and not has_function_privilege(
        'anon',
        'public.get_league_provider_sync_health_v3(uuid)',
        'EXECUTE'
      ),
    'realtime_ready',
      exists (
        select 1
        from pg_catalog.pg_publication_tables publication_table
        where publication_table.pubname = 'supabase_realtime'
          and publication_table.schemaname = 'public'
          and publication_table.tablename = 'provider_operational_incidents'
      )
      and exists (
        select 1
        from pg_catalog.pg_publication_tables publication_table
        where publication_table.pubname = 'supabase_realtime'
          and publication_table.schemaname = 'public'
          and publication_table.tablename =
            'provider_operational_incident_events'
      )
  )
$$;

revoke all on function public.get_provider_operational_incident_integrity_v1()
from public, anon, authenticated;

do $validate$
declare
  v_checks jsonb;
  v_failed text[];
begin
  v_checks := public.get_provider_operational_incident_integrity_v1();

  select array_agg(check_row.key order by check_row.key)
  into v_failed
  from jsonb_each(v_checks) check_row
  where check_row.value is distinct from 'true'::jsonb;

  if coalesce(array_length(v_failed, 1), 0) > 0 then
    raise exception
      'Validazione v0.62.4 non superata. Controlli falsi: %',
      array_to_string(v_failed, ', ');
  end if;
end;
$validate$;

commit;

-- Diagnostica finale: devono comparire esattamente 20 valori true.
select
  coalesce((public.get_provider_operational_incident_integrity_v1() ->> 'incidents_table_ready')::boolean, false)
    as incidents_table_ready,
  coalesce((public.get_provider_operational_incident_integrity_v1() ->> 'events_table_ready')::boolean, false)
    as events_table_ready,
  coalesce((public.get_provider_operational_incident_integrity_v1() ->> 'incident_columns_ready')::boolean, false)
    as incident_columns_ready,
  coalesce((public.get_provider_operational_incident_integrity_v1() ->> 'incident_indexes_ready')::boolean, false)
    as incident_indexes_ready,
  coalesce((public.get_provider_operational_incident_integrity_v1() ->> 'event_writer_ready')::boolean, false)
    as event_writer_ready,
  coalesce((public.get_provider_operational_incident_integrity_v1() ->> 'event_writer_trigger_ready')::boolean, false)
    as event_writer_trigger_ready,
  coalesce((public.get_provider_operational_incident_integrity_v1() ->> 'events_immutable_ready')::boolean, false)
    as events_immutable_ready,
  coalesce((public.get_provider_operational_incident_integrity_v1() ->> 'incident_upsert_ready')::boolean, false)
    as incident_upsert_ready,
  coalesce((public.get_provider_operational_incident_integrity_v1() ->> 'incident_resolve_ready')::boolean, false)
    as incident_resolve_ready,
  coalesce((public.get_provider_operational_incident_integrity_v1() ->> 'sync_capture_ready')::boolean, false)
    as sync_capture_ready,
  coalesce((public.get_provider_operational_incident_integrity_v1() ->> 'quality_capture_ready')::boolean, false)
    as quality_capture_ready,
  coalesce((public.get_provider_operational_incident_integrity_v1() ->> 'incident_center_rpc_ready')::boolean, false)
    as incident_center_rpc_ready,
  coalesce((public.get_provider_operational_incident_integrity_v1() ->> 'health_v3_rpc_ready')::boolean, false)
    as health_v3_rpc_ready,
  coalesce((public.get_provider_operational_incident_integrity_v1() ->> 'rls_policies_ready')::boolean, false)
    as rls_policies_ready,
  coalesce((public.get_provider_operational_incident_integrity_v1() ->> 'authenticated_read_ready')::boolean, false)
    as authenticated_read_ready,
  coalesce((public.get_provider_operational_incident_integrity_v1() ->> 'authenticated_writes_blocked')::boolean, false)
    as authenticated_writes_blocked,
  coalesce((public.get_provider_operational_incident_integrity_v1() ->> 'anonymous_tables_blocked')::boolean, false)
    as anonymous_tables_blocked,
  coalesce((public.get_provider_operational_incident_integrity_v1() ->> 'authenticated_rpc_ready')::boolean, false)
    as authenticated_rpc_ready,
  coalesce((public.get_provider_operational_incident_integrity_v1() ->> 'anonymous_rpc_blocked')::boolean, false)
    as anonymous_rpc_blocked,
  coalesce((public.get_provider_operational_incident_integrity_v1() ->> 'realtime_ready')::boolean, false)
    as realtime_ready;
