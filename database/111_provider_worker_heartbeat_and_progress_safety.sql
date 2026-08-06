-- LEGHEVO v0.62.7 · Heartbeat e avanzamento protetto del worker provider
-- Migrazione interna: database/111_provider_worker_heartbeat_and_progress_safety.sql
--
-- Obiettivi:
-- - impedire al watchdog di interrompere un worker ancora realmente attivo;
-- - registrare heartbeat revisionati durante le sincronizzazioni API-Football;
-- - certificare fase, avanzamento e numero di record elaborati;
-- - mantenere idempotenza e controllo ottimistico della revisione del run;
-- - mostrare il progresso del recupero nel Centro Operativo;
-- - terminare con una diagnostica strutturale di 20 controlli.

begin;

-- Preflight esclusivamente strutturale. Nessuna modifica viene applicata se
-- manca una dipendenza validata nelle versioni v0.62.2-v0.62.6.
do $preflight$
declare
  v_missing text[] := array[]::text[];
  v_expected record;
begin
  for v_expected in
    select *
    from (values
      ('provider_sync_runs', 'id'),
      ('provider_sync_runs', 'status'),
      ('provider_sync_runs', 'sync_type'),
      ('provider_sync_runs', 'revision'),
      ('provider_sync_runs', 'records_processed'),
      ('provider_sync_runs', 'last_updated_at'),
      ('provider_sync_run_events', 'id'),
      ('provider_sync_run_events', 'run_id'),
      ('provider_sync_run_events', 'event_type'),
      ('provider_sync_run_events', 'revision'),
      ('provider_sync_run_events', 'records_processed'),
      ('provider_sync_run_events', 'created_at'),
      ('provider_recovery_requests', 'id'),
      ('provider_recovery_requests', 'league_id'),
      ('provider_recovery_requests', 'status'),
      ('provider_recovery_requests', 'recovery_run_id'),
      ('provider_recovery_requests', 'sync_type'),
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
  if to_regprocedure(
    'public.finish_provider_sync_run_guarded_v1(uuid,text,integer,text,bigint)'
  ) is null then
    v_missing := array_append(
      v_missing,
      'function public.finish_provider_sync_run_guarded_v1(uuid,text,integer,text,bigint)'
    );
  end if;
  if to_regprocedure(
    'public.get_league_provider_recovery_center_v2(uuid)'
  ) is null then
    v_missing := array_append(
      v_missing,
      'function public.get_league_provider_recovery_center_v2(uuid)'
    );
  end if;
  if to_regprocedure('public.get_league_provider_sync_health_v5(uuid)') is null then
    v_missing := array_append(
      v_missing,
      'function public.get_league_provider_sync_health_v5(uuid)'
    );
  end if;
  if to_regprocedure('public.provider_recovery_timeout_seconds_v1(text)') is null then
    v_missing := array_append(
      v_missing,
      'function public.provider_recovery_timeout_seconds_v1(text)'
    );
  end if;
  if to_regprocedure(
    'public.expire_stale_provider_recovery_requests_v1(uuid)'
  ) is null then
    v_missing := array_append(
      v_missing,
      'function public.expire_stale_provider_recovery_requests_v1(uuid)'
    );
  end if;

  if coalesce(array_length(v_missing, 1), 0) > 0 then
    raise exception
      'Preflight v0.62.7 non superato. Oggetti mancanti: %',
      array_to_string(v_missing, '; ');
  end if;
end;
$preflight$;

-- Le colonne vengono aggiunte con valori predefiniti non nulli. Non viene
-- eseguito alcun UPDATE di backfill, perché i run conclusi sono già protetti
-- dal trigger di immutabilità revisionale della v0.62.2.
alter table public.provider_sync_runs
  add column if not exists heartbeat_at timestamptz not null default now(),
  add column if not exists progress_phase text not null default 'starting',
  add column if not exists progress_current integer not null default 0,
  add column if not exists progress_total integer;

alter table public.provider_sync_runs
  alter column heartbeat_at set default now(),
  alter column heartbeat_at set not null,
  alter column progress_phase set default 'starting',
  alter column progress_phase set not null,
  alter column progress_current set default 0,
  alter column progress_current set not null;

alter table public.provider_sync_runs
  drop constraint if exists provider_sync_runs_progress_phase_check;
alter table public.provider_sync_runs
  add constraint provider_sync_runs_progress_phase_check
  check (
    char_length(trim(progress_phase)) between 1 and 80
  );

alter table public.provider_sync_runs
  drop constraint if exists provider_sync_runs_progress_current_check;
alter table public.provider_sync_runs
  add constraint provider_sync_runs_progress_current_check
  check (progress_current >= 0);

alter table public.provider_sync_runs
  drop constraint if exists provider_sync_runs_progress_total_check;
alter table public.provider_sync_runs
  add constraint provider_sync_runs_progress_total_check
  check (
    progress_total is null
    or (progress_total >= 0 and progress_current <= progress_total)
  );

create index if not exists provider_sync_runs_heartbeat_idx
  on public.provider_sync_runs (status, heartbeat_at desc);

-- Anche il registro eventi è già immutabile: i campi storici ricevono
-- valori tecnici predefiniti senza effettuare UPDATE sulle righe certificate.
alter table public.provider_sync_run_events
  add column if not exists progress_phase text not null default 'legacy',
  add column if not exists progress_current integer not null default 0,
  add column if not exists progress_total integer,
  add column if not exists heartbeat_at timestamptz not null default now();

alter table public.provider_sync_run_events
  alter column progress_phase set default 'legacy',
  alter column progress_phase set not null,
  alter column progress_current set default 0,
  alter column progress_current set not null,
  alter column heartbeat_at set default now(),
  alter column heartbeat_at set not null;

alter table public.provider_sync_run_events
  drop constraint if exists provider_sync_run_events_progress_phase_check;
alter table public.provider_sync_run_events
  add constraint provider_sync_run_events_progress_phase_check
  check (char_length(trim(progress_phase)) between 1 and 80);

alter table public.provider_sync_run_events
  drop constraint if exists provider_sync_run_events_progress_current_check;
alter table public.provider_sync_run_events
  add constraint provider_sync_run_events_progress_current_check
  check (progress_current >= 0);

alter table public.provider_sync_run_events
  drop constraint if exists provider_sync_run_events_progress_total_check;
alter table public.provider_sync_run_events
  add constraint provider_sync_run_events_progress_total_check
  check (
    progress_total is null
    or (progress_total >= 0 and progress_current <= progress_total)
  );

create index if not exists provider_sync_run_events_heartbeat_idx
  on public.provider_sync_run_events (heartbeat_at desc);

-- La funzione storica mantiene la stessa firma, ma registra anche il progresso
-- associato a ogni revisione del run.
create or replace function public.record_provider_sync_run_event_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_event_type text;
begin
  if tg_op = 'INSERT' then
    v_event_type := 'started';
  elsif new.status = 'completed' then
    v_event_type := 'completed';
  elsif new.status = 'failed' then
    v_event_type := 'failed';
  else
    v_event_type := 'heartbeat';
  end if;

  insert into public.provider_sync_run_events (
    run_id,
    provider,
    sync_type,
    event_type,
    revision,
    records_processed,
    progress_phase,
    progress_current,
    progress_total,
    heartbeat_at,
    event_fingerprint,
    created_at
  ) values (
    new.id,
    new.provider,
    new.sync_type,
    v_event_type,
    new.revision,
    new.records_processed,
    new.progress_phase,
    new.progress_current,
    new.progress_total,
    new.heartbeat_at,
    pg_catalog.md5(
      new.id::text || E'\n'
      || v_event_type || E'\n'
      || new.revision::text || E'\n'
      || new.records_processed::text || E'\n'
      || new.progress_phase || E'\n'
      || new.progress_current::text || E'\n'
      || coalesce(new.progress_total::text, '') || E'\n'
      || new.heartbeat_at::text || E'\n'
      || coalesce(new.result_fingerprint, '')
    ),
    new.last_updated_at
  )
  on conflict (run_id, revision) do nothing;

  return new;
end;
$$;

revoke all on function public.record_provider_sync_run_event_v1()
from public, anon, authenticated;

-- Aggiornamento revisionato del worker. Il retry della stessa chiamata è
-- riconosciuto come idempotente se lo stato richiesto è già stato salvato.
create or replace function public.heartbeat_provider_sync_run_guarded_v1(
  p_run_id uuid,
  p_records_processed integer,
  p_progress_phase text,
  p_progress_current integer,
  p_progress_total integer default null,
  p_expected_revision bigint default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_phase text := lower(trim(coalesce(p_progress_phase, '')));
  v_records integer := greatest(coalesce(p_records_processed, 0), 0);
  v_current integer := greatest(coalesce(p_progress_current, 0), 0);
  v_total integer := case
    when p_progress_total is null then null
    else greatest(p_progress_total, 0)
  end;
  v_run public.provider_sync_runs%rowtype;
  v_updated public.provider_sync_runs%rowtype;
begin
  if p_run_id is null then
    raise exception 'Run provider non valido.';
  end if;
  if v_phase = '' or char_length(v_phase) > 80 then
    raise exception 'Fase di avanzamento provider non valida.';
  end if;
  if coalesce(p_records_processed, 0) < 0
    or coalesce(p_progress_current, 0) < 0
    or (p_progress_total is not null and p_progress_total < 0) then
    raise exception 'Avanzamento provider negativo non consentito.';
  end if;
  if v_total is not null and v_current > v_total then
    raise exception 'Avanzamento provider superiore al totale previsto.';
  end if;

  select run_row.*
  into v_run
  from public.provider_sync_runs run_row
  where run_row.id = p_run_id
  for update;

  if not found then
    raise exception 'Run provider non trovato.';
  end if;

  if v_run.status in ('completed', 'failed') then
    return jsonb_build_object(
      'runId', v_run.id,
      'status', v_run.status,
      'revision', v_run.revision,
      'attempt', v_run.attempt_no,
      'recordsProcessed', v_run.records_processed,
      'requestKey', v_run.request_key,
      'progressPhase', v_run.progress_phase,
      'progressCurrent', v_run.progress_current,
      'progressTotal', v_run.progress_total,
      'heartbeatAt', v_run.heartbeat_at,
      'reused', true
    );
  end if;

  if p_expected_revision is not null
    and v_run.revision <> p_expected_revision then
    if v_run.records_processed = greatest(v_run.records_processed, v_records)
      and v_run.progress_phase = v_phase
      and v_run.progress_current = v_current
      and v_run.progress_total is not distinct from v_total then
      return jsonb_build_object(
        'runId', v_run.id,
        'status', v_run.status,
        'revision', v_run.revision,
        'attempt', v_run.attempt_no,
        'recordsProcessed', v_run.records_processed,
        'requestKey', v_run.request_key,
        'progressPhase', v_run.progress_phase,
        'progressCurrent', v_run.progress_current,
        'progressTotal', v_run.progress_total,
        'heartbeatAt', v_run.heartbeat_at,
        'reused', true
      );
    end if;

    raise exception
      'Run provider aggiornato da un''altra esecuzione. Revisione attesa %, revisione corrente %.',
      p_expected_revision,
      v_run.revision;
  end if;

  update public.provider_sync_runs run_row
  set
    records_processed = greatest(run_row.records_processed, v_records),
    progress_phase = v_phase,
    progress_current = v_current,
    progress_total = v_total,
    heartbeat_at = now()
  where run_row.id = v_run.id
    and run_row.status = 'running'
  returning * into v_updated;

  return jsonb_build_object(
    'runId', v_updated.id,
    'status', v_updated.status,
    'revision', v_updated.revision,
    'attempt', v_updated.attempt_no,
    'recordsProcessed', v_updated.records_processed,
    'requestKey', v_updated.request_key,
    'progressPhase', v_updated.progress_phase,
    'progressCurrent', v_updated.progress_current,
    'progressTotal', v_updated.progress_total,
    'heartbeatAt', v_updated.heartbeat_at,
    'reused', false
  );
end;
$$;

revoke all on function public.heartbeat_provider_sync_run_guarded_v1(
  uuid, integer, text, integer, integer, bigint
) from public, anon, authenticated;
grant execute on function public.heartbeat_provider_sync_run_guarded_v1(
  uuid, integer, text, integer, integer, bigint
) to service_role;

create or replace function public.get_league_provider_recovery_center_v3(
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
  v_progress record;
  v_progress_json jsonb := null;
  v_has_running boolean := false;
  v_heartbeat_fresh boolean := true;
  v_timeout_seconds integer := 0;
  v_grace_seconds integer := 0;
  v_healthy boolean;
begin
  v_center := public.get_league_provider_recovery_center_v2(p_league_id);

  select
    request_row.id as request_id,
    run_row.id as run_id,
    request_row.sync_type,
    run_row.progress_phase,
    run_row.progress_current,
    run_row.progress_total,
    run_row.records_processed,
    run_row.heartbeat_at,
    run_row.revision as run_revision
  into v_progress
  from public.provider_recovery_requests request_row
  join public.provider_sync_runs run_row
    on run_row.id = request_row.recovery_run_id
  where request_row.league_id = p_league_id
    and request_row.status = 'running'
    and run_row.status = 'running'
  order by run_row.heartbeat_at desc, request_row.started_at desc
  limit 1;

  v_has_running := found;

  if v_has_running then
    v_timeout_seconds := public.provider_recovery_timeout_seconds_v1(
      v_progress.sync_type
    );
    v_grace_seconds := greatest(
      60,
      least(greatest(v_timeout_seconds / 3, 1), 300)
    );
    v_heartbeat_fresh := v_progress.heartbeat_at >= now() - (
      v_grace_seconds * interval '1 second'
    );

    v_progress_json := jsonb_build_object(
      'requestId', v_progress.request_id,
      'runId', v_progress.run_id,
      'syncType', v_progress.sync_type,
      'phase', v_progress.progress_phase,
      'current', v_progress.progress_current,
      'total', v_progress.progress_total,
      'recordsProcessed', v_progress.records_processed,
      'heartbeatAt', v_progress.heartbeat_at,
      'revision', v_progress.run_revision,
      'percent', case
        when coalesce(v_progress.progress_total, 0) > 0 then
          round(
            least(
              100::numeric,
              (v_progress.progress_current::numeric * 100)
              / v_progress.progress_total::numeric
            ),
            1
          )
        else null
      end
    );
  end if;

  v_healthy := coalesce((v_center ->> 'healthy')::boolean, false)
    and v_heartbeat_fresh;

  return v_center || jsonb_build_object(
    'healthy', v_healthy,
    'workerHeartbeatActive', true,
    'runningHeartbeatFresh', v_heartbeat_fresh,
    'heartbeatGraceSeconds', case
      when v_has_running then v_grace_seconds
      else null
    end,
    'latestHeartbeatAt', case
      when v_has_running then v_progress.heartbeat_at
      else null
    end,
    'latestProgress', v_progress_json
  );
end;
$$;

revoke all on function public.get_league_provider_recovery_center_v3(uuid)
from public, anon, authenticated;
grant execute on function public.get_league_provider_recovery_center_v3(uuid)
to authenticated;

create or replace function public.get_league_provider_sync_health_v6(
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
  v_health := public.get_league_provider_sync_health_v5(p_league_id);
  v_recovery := public.get_league_provider_recovery_center_v3(p_league_id);
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

revoke all on function public.get_league_provider_sync_health_v6(uuid)
from public, anon, authenticated;
grant execute on function public.get_league_provider_sync_health_v6(uuid)
to authenticated;

create or replace function public.get_provider_worker_heartbeat_integrity_v1()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'run_progress_columns_ready',
      (
        select count(*) = 4
        from information_schema.columns column_row
        where column_row.table_schema = 'public'
          and column_row.table_name = 'provider_sync_runs'
          and column_row.column_name in (
            'heartbeat_at', 'progress_phase', 'progress_current', 'progress_total'
          )
      ),
    'event_progress_columns_ready',
      (
        select count(*) = 4
        from information_schema.columns column_row
        where column_row.table_schema = 'public'
          and column_row.table_name = 'provider_sync_run_events'
          and column_row.column_name in (
            'heartbeat_at', 'progress_phase', 'progress_current', 'progress_total'
          )
      ),
    'run_progress_constraints_ready',
      exists (
        select 1 from pg_constraint constraint_row
        where constraint_row.conname = 'provider_sync_runs_progress_phase_check'
          and constraint_row.conrelid = 'public.provider_sync_runs'::regclass
      )
      and exists (
        select 1 from pg_constraint constraint_row
        where constraint_row.conname = 'provider_sync_runs_progress_current_check'
          and constraint_row.conrelid = 'public.provider_sync_runs'::regclass
      )
      and exists (
        select 1 from pg_constraint constraint_row
        where constraint_row.conname = 'provider_sync_runs_progress_total_check'
          and constraint_row.conrelid = 'public.provider_sync_runs'::regclass
      ),
    'event_progress_constraints_ready',
      exists (
        select 1 from pg_constraint constraint_row
        where constraint_row.conname = 'provider_sync_run_events_progress_phase_check'
          and constraint_row.conrelid = 'public.provider_sync_run_events'::regclass
      )
      and exists (
        select 1 from pg_constraint constraint_row
        where constraint_row.conname = 'provider_sync_run_events_progress_current_check'
          and constraint_row.conrelid = 'public.provider_sync_run_events'::regclass
      )
      and exists (
        select 1 from pg_constraint constraint_row
        where constraint_row.conname = 'provider_sync_run_events_progress_total_check'
          and constraint_row.conrelid = 'public.provider_sync_run_events'::regclass
      ),
    'run_heartbeat_index_ready',
      to_regclass('public.provider_sync_runs_heartbeat_idx') is not null,
    'event_heartbeat_index_ready',
      to_regclass('public.provider_sync_run_events_heartbeat_idx') is not null,
    'event_writer_ready',
      to_regprocedure('public.record_provider_sync_run_event_v1()') is not null
      and exists (
        select 1
        from pg_trigger trigger_row
        where trigger_row.tgname = 'provider_sync_run_event_writer'
          and trigger_row.tgrelid = 'public.provider_sync_runs'::regclass
          and not trigger_row.tgisinternal
      ),
    'heartbeat_rpc_ready',
      to_regprocedure(
        'public.heartbeat_provider_sync_run_guarded_v1(uuid,integer,text,integer,integer,bigint)'
      ) is not null
      and has_function_privilege(
        'service_role',
        'public.heartbeat_provider_sync_run_guarded_v1(uuid,integer,text,integer,integer,bigint)',
        'EXECUTE'
      ),
    'authenticated_heartbeat_blocked',
      not has_function_privilege(
        'authenticated',
        'public.heartbeat_provider_sync_run_guarded_v1(uuid,integer,text,integer,integer,bigint)',
        'EXECUTE'
      ),
    'recovery_center_v3_ready',
      to_regprocedure('public.get_league_provider_recovery_center_v3(uuid)') is not null
      and has_function_privilege(
        'authenticated',
        'public.get_league_provider_recovery_center_v3(uuid)',
        'EXECUTE'
      ),
    'provider_health_v6_ready',
      to_regprocedure('public.get_league_provider_sync_health_v6(uuid)') is not null
      and has_function_privilege(
        'authenticated',
        'public.get_league_provider_sync_health_v6(uuid)',
        'EXECUTE'
      ),
    'run_rls_ready',
      coalesce((
        select class_row.relrowsecurity
        from pg_class class_row
        join pg_namespace namespace_row
          on namespace_row.oid = class_row.relnamespace
        where namespace_row.nspname = 'public'
          and class_row.relname = 'provider_sync_runs'
      ), false),
    'event_rls_ready',
      coalesce((
        select class_row.relrowsecurity
        from pg_class class_row
        join pg_namespace namespace_row
          on namespace_row.oid = class_row.relnamespace
        where namespace_row.nspname = 'public'
          and class_row.relname = 'provider_sync_run_events'
      ), false),
    'authenticated_event_read_ready',
      has_table_privilege(
        'authenticated',
        'public.provider_sync_run_events',
        'SELECT'
      ),
    'authenticated_event_writes_blocked',
      not has_table_privilege(
        'authenticated',
        'public.provider_sync_run_events',
        'INSERT'
      )
      and not has_table_privilege(
        'authenticated',
        'public.provider_sync_run_events',
        'UPDATE'
      )
      and not has_table_privilege(
        'authenticated',
        'public.provider_sync_run_events',
        'DELETE'
      ),
    'service_role_run_update_ready',
      has_table_privilege(
        'service_role',
        'public.provider_sync_runs',
        'UPDATE'
      ),
    'event_realtime_ready',
      exists (
        select 1
        from pg_catalog.pg_publication_tables publication_table
        where publication_table.pubname = 'supabase_realtime'
          and publication_table.schemaname = 'public'
          and publication_table.tablename = 'provider_sync_run_events'
      ),
    'watchdog_continuity_ready',
      to_regprocedure(
        'public.expire_stale_provider_recovery_requests_v1(uuid)'
      ) is not null
      and to_regprocedure(
        'public.provider_recovery_timeout_seconds_v1(text)'
      ) is not null,
    'recovery_queue_continuity_ready',
      to_regclass('public.provider_recovery_requests') is not null
      and to_regprocedure(
        'public.get_league_provider_recovery_center_v2(uuid)'
      ) is not null,
    'provider_finish_continuity_ready',
      to_regprocedure(
        'public.finish_provider_sync_run_guarded_v1(uuid,text,integer,text,bigint)'
      ) is not null
  );
$$;

revoke all on function public.get_provider_worker_heartbeat_integrity_v1()
from public, anon, authenticated;
grant execute on function public.get_provider_worker_heartbeat_integrity_v1()
to authenticated, service_role;

-- Arresta la transazione indicando il nome esatto degli eventuali controlli falsi.
do $validation$
declare
  v_checks jsonb := public.get_provider_worker_heartbeat_integrity_v1();
  v_failed text[];
begin
  select array_agg(check_row.key order by check_row.key)
  into v_failed
  from jsonb_each(v_checks) check_row
  where jsonb_typeof(check_row.value) is distinct from 'boolean'
    or check_row.value is distinct from 'true'::jsonb;

  if coalesce(array_length(v_failed, 1), 0) > 0 then
    raise exception
      'Validazione v0.62.7 non superata. Controlli falsi: %',
      array_to_string(v_failed, '; ');
  end if;
end;
$validation$;

commit;

-- Diagnostica finale: devono comparire esattamente 20 valori true.
select
  (checks ->> 'run_progress_columns_ready')::boolean
    as run_progress_columns_ready,
  (checks ->> 'event_progress_columns_ready')::boolean
    as event_progress_columns_ready,
  (checks ->> 'run_progress_constraints_ready')::boolean
    as run_progress_constraints_ready,
  (checks ->> 'event_progress_constraints_ready')::boolean
    as event_progress_constraints_ready,
  (checks ->> 'run_heartbeat_index_ready')::boolean
    as run_heartbeat_index_ready,
  (checks ->> 'event_heartbeat_index_ready')::boolean
    as event_heartbeat_index_ready,
  (checks ->> 'event_writer_ready')::boolean
    as event_writer_ready,
  (checks ->> 'heartbeat_rpc_ready')::boolean
    as heartbeat_rpc_ready,
  (checks ->> 'authenticated_heartbeat_blocked')::boolean
    as authenticated_heartbeat_blocked,
  (checks ->> 'recovery_center_v3_ready')::boolean
    as recovery_center_v3_ready,
  (checks ->> 'provider_health_v6_ready')::boolean
    as provider_health_v6_ready,
  (checks ->> 'run_rls_ready')::boolean
    as run_rls_ready,
  (checks ->> 'event_rls_ready')::boolean
    as event_rls_ready,
  (checks ->> 'authenticated_event_read_ready')::boolean
    as authenticated_event_read_ready,
  (checks ->> 'authenticated_event_writes_blocked')::boolean
    as authenticated_event_writes_blocked,
  (checks ->> 'service_role_run_update_ready')::boolean
    as service_role_run_update_ready,
  (checks ->> 'event_realtime_ready')::boolean
    as event_realtime_ready,
  (checks ->> 'watchdog_continuity_ready')::boolean
    as watchdog_continuity_ready,
  (checks ->> 'recovery_queue_continuity_ready')::boolean
    as recovery_queue_continuity_ready,
  (checks ->> 'provider_finish_continuity_ready')::boolean
    as provider_finish_continuity_ready
from (
  select public.get_provider_worker_heartbeat_integrity_v1() as checks
) diagnostic;
