-- LEGHEVO v0.62.6 · Watchdog protetto dei recuperi provider
-- Migrazione interna: database/110_provider_recovery_watchdog_safety.sql
--
-- Obiettivi:
-- - rilevare richieste di recupero rimaste bloccate nello stato running;
-- - usare timeout distinti per ogni tipo di sincronizzazione;
-- - chiudere in modo atomico i run provider realmente scaduti;
-- - rendere nuovamente recuperabile l'incidente senza creare duplicati;
-- - conservare uno storico immutabile degli interventi del watchdog;
-- - esporre lo stato nel Centro Operativo e alla Edge Function;
-- - terminare con una diagnostica strutturale di 20 controlli.

begin;

-- Preflight esclusivamente strutturale. Nessuna modifica viene applicata se
-- manca una dipendenza validata nelle versioni v0.62.2-v0.62.5.
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
      ('provider_recovery_requests', 'sync_type'),
      ('provider_recovery_requests', 'status'),
      ('provider_recovery_requests', 'revision'),
      ('provider_recovery_requests', 'recovery_run_id'),
      ('provider_recovery_requests', 'started_at'),
      ('provider_recovery_requests', 'updated_at'),
      ('provider_recovery_requests', 'finished_at'),
      ('provider_recovery_requests', 'error_summary'),
      ('provider_recovery_requests', 'attempt_no'),
      ('provider_sync_runs', 'id'),
      ('provider_sync_runs', 'status'),
      ('provider_sync_runs', 'revision'),
      ('provider_sync_runs', 'attempt_no'),
      ('provider_sync_runs', 'sync_type'),
      ('provider_sync_runs', 'records_processed'),
      ('provider_sync_runs', 'error_message'),
      ('provider_sync_runs', 'started_at'),
      ('provider_sync_runs', 'last_updated_at'),
      ('provider_sync_runs', 'finished_at'),
      ('provider_operational_incidents', 'id'),
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
    'public.claim_provider_recovery_request_v1(uuid,bigint)'
  ) is null then
    v_missing := array_append(
      v_missing,
      'function public.claim_provider_recovery_request_v1(uuid,bigint)'
    );
  end if;
  if to_regprocedure('public.claim_next_provider_recovery_request_v1()') is null then
    v_missing := array_append(
      v_missing,
      'function public.claim_next_provider_recovery_request_v1()'
    );
  end if;
  if to_regprocedure('public.get_league_provider_recovery_center_v1(uuid)') is null then
    v_missing := array_append(
      v_missing,
      'function public.get_league_provider_recovery_center_v1(uuid)'
    );
  end if;
  if to_regprocedure('public.get_league_provider_sync_health_v4(uuid)') is null then
    v_missing := array_append(
      v_missing,
      'function public.get_league_provider_sync_health_v4(uuid)'
    );
  end if;

  if coalesce(array_length(v_missing, 1), 0) > 0 then
    raise exception
      'Preflight v0.62.6 non superato. Oggetti mancanti: %',
      array_to_string(v_missing, '; ');
  end if;
end;
$preflight$;

create table if not exists public.provider_recovery_watchdog_events (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  request_id uuid not null
    references public.provider_recovery_requests(id) on delete cascade,
  league_id uuid not null references public.leagues(id) on delete cascade,
  incident_id uuid not null
    references public.provider_operational_incidents(id) on delete cascade,
  run_id uuid references public.provider_sync_runs(id) on delete set null,
  sync_type text not null,
  event_type text not null default 'timed_out'
    check (event_type = 'timed_out'),
  request_revision bigint not null check (request_revision > 0),
  run_revision bigint check (run_revision is null or run_revision > 0),
  timeout_seconds integer not null check (timeout_seconds between 60 and 86400),
  elapsed_seconds integer not null check (elapsed_seconds >= timeout_seconds),
  event_fingerprint text not null check (char_length(event_fingerprint) = 32),
  created_at timestamptz not null default now(),
  unique (request_id, request_revision, event_type)
);

create index if not exists provider_recovery_watchdog_events_league_latest_idx
  on public.provider_recovery_watchdog_events (league_id, created_at desc);
create index if not exists provider_recovery_watchdog_events_request_idx
  on public.provider_recovery_watchdog_events (request_id, created_at desc);

alter table public.provider_recovery_watchdog_events enable row level security;
alter table public.provider_recovery_watchdog_events replica identity full;

revoke all on table public.provider_recovery_watchdog_events
from public, anon, authenticated;
grant select on table public.provider_recovery_watchdog_events to authenticated;
grant select, insert on table public.provider_recovery_watchdog_events to service_role;

drop policy if exists provider_recovery_watchdog_events_read_directors
on public.provider_recovery_watchdog_events;
create policy provider_recovery_watchdog_events_read_directors
on public.provider_recovery_watchdog_events
for select to authenticated
using (
  exists (
    select 1
    from public.leagues league_row
    where league_row.id = provider_recovery_watchdog_events.league_id
      and (
        league_row.owner_id = auth.uid()
        or public.is_league_admin(league_row.id)
      )
  )
);

create or replace function public.prevent_provider_recovery_watchdog_event_mutation_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'UPDATE'
    and pg_trigger_depth() > 1
    and old.run_id is not null
    and new.run_id is null
    and row(
      new.id,
      new.request_id,
      new.league_id,
      new.incident_id,
      new.sync_type,
      new.event_type,
      new.request_revision,
      new.run_revision,
      new.timeout_seconds,
      new.elapsed_seconds,
      new.event_fingerprint,
      new.created_at
    ) is not distinct from row(
      old.id,
      old.request_id,
      old.league_id,
      old.incident_id,
      old.sync_type,
      old.event_type,
      old.request_revision,
      old.run_revision,
      old.timeout_seconds,
      old.elapsed_seconds,
      old.event_fingerprint,
      old.created_at
    ) then
    return new;
  end if;

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
    return old;
  end if;

  raise exception
    'Evento watchdog provider certificato: modifica o cancellazione non consentita.';
end;
$$;

revoke all on function public.prevent_provider_recovery_watchdog_event_mutation_v1()
from public, anon, authenticated;

drop trigger if exists provider_recovery_watchdog_events_immutable
on public.provider_recovery_watchdog_events;
create trigger provider_recovery_watchdog_events_immutable
before update or delete on public.provider_recovery_watchdog_events
for each row execute function public.prevent_provider_recovery_watchdog_event_mutation_v1();

create or replace function public.provider_recovery_timeout_seconds_v1(
  p_sync_type text
)
returns integer
language sql
immutable
set search_path = ''
as $$
  select case lower(trim(coalesce(p_sync_type, '')))
    when 'sync-fixture-players' then 900
    when 'sync-fixtures' then 1200
    when 'sync-season-players' then 3600
    else 1800
  end
$$;

revoke all on function public.provider_recovery_timeout_seconds_v1(text)
from public, anon, authenticated;
grant execute on function public.provider_recovery_timeout_seconds_v1(text)
to service_role;

create or replace function public.expire_stale_provider_recovery_requests_v1(
  p_request_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_candidate record;
  v_request public.provider_recovery_requests%rowtype;
  v_run public.provider_sync_runs%rowtype;
  v_reference_at timestamptz;
  v_timeout_seconds integer;
  v_elapsed_seconds integer;
  v_expired_count integer := 0;
  v_checked_count integer := 0;
  v_error_message text;
begin
  for v_candidate in
    select
      request_row.id,
      request_row.recovery_run_id
    from public.provider_recovery_requests request_row
    where request_row.status = 'running'
      and (p_request_id is null or request_row.id = p_request_id)
    order by request_row.updated_at asc
  loop
    v_checked_count := v_checked_count + 1;

    -- Mantiene lo stesso ordine di lock della chiusura del run provider:
    -- prima il run, poi la richiesta collegata. In questo modo il watchdog
    -- non può entrare in deadlock con il worker che sta certificando l'esito.
    select run_row.*
    into v_run
    from public.provider_sync_runs run_row
    where run_row.id = v_candidate.recovery_run_id
    for update;

    select request_row.*
    into v_request
    from public.provider_recovery_requests request_row
    where request_row.id = v_candidate.id
    for update;

    if not found
      or v_request.status <> 'running'
      or v_request.recovery_run_id is distinct from v_candidate.recovery_run_id then
      continue;
    end if;

    v_timeout_seconds := public.provider_recovery_timeout_seconds_v1(
      v_request.sync_type
    );

    if v_run.id is not null and v_run.status in ('completed', 'failed') then
      update public.provider_recovery_requests request_row
      set
        status = v_run.status,
        attempt_no = greatest(request_row.attempt_no, v_run.attempt_no),
        error_summary = case
          when v_run.status = 'failed' then v_run.error_message
          else null
        end,
        finished_at = coalesce(v_run.finished_at, now())
      where request_row.id = v_request.id
        and request_row.status = 'running';
      continue;
    end if;

    v_reference_at := greatest(
      coalesce(v_request.updated_at, '-infinity'::timestamptz),
      coalesce(v_request.started_at, '-infinity'::timestamptz),
      coalesce(v_run.last_updated_at, '-infinity'::timestamptz),
      coalesce(v_run.started_at, '-infinity'::timestamptz)
    );

    if v_reference_at = '-infinity'::timestamptz then
      v_reference_at := now();
    end if;

    v_elapsed_seconds := greatest(
      floor(extract(epoch from (now() - v_reference_at)))::integer,
      0
    );

    if v_elapsed_seconds < v_timeout_seconds then
      continue;
    end if;

    v_error_message := left(
      format(
        'Watchdog provider: recupero %s interrotto dopo %s secondi senza aggiornamenti.',
        v_request.sync_type,
        v_elapsed_seconds
      ),
      500
    );

    if v_run.id is not null and v_run.status = 'running' then
      perform public.finish_provider_sync_run_guarded_v1(
        v_run.id,
        'failed',
        greatest(coalesce(v_run.records_processed, 0), 0),
        v_error_message,
        v_run.revision
      );
    else
      update public.provider_recovery_requests request_row
      set
        status = 'failed',
        error_summary = v_error_message,
        finished_at = now()
      where request_row.id = v_request.id
        and request_row.status = 'running';
    end if;

    insert into public.provider_recovery_watchdog_events (
      request_id,
      league_id,
      incident_id,
      run_id,
      sync_type,
      event_type,
      request_revision,
      run_revision,
      timeout_seconds,
      elapsed_seconds,
      event_fingerprint,
      created_at
    ) values (
      v_request.id,
      v_request.league_id,
      v_request.incident_id,
      v_run.id,
      v_request.sync_type,
      'timed_out',
      v_request.revision,
      v_run.revision,
      v_timeout_seconds,
      v_elapsed_seconds,
      pg_catalog.md5(
        v_request.id::text || E'\n'
        || v_request.revision::text || E'\n'
        || coalesce(v_run.id::text, '') || E'\n'
        || coalesce(v_run.revision::text, '') || E'\n'
        || v_timeout_seconds::text || E'\n'
        || v_elapsed_seconds::text
      ),
      now()
    )
    on conflict (request_id, request_revision, event_type) do nothing;

    v_expired_count := v_expired_count + 1;
  end loop;

  return jsonb_build_object(
    'checkedCount', v_checked_count,
    'expiredCount', v_expired_count,
    'checkedAt', now()
  );
end;
$$;

revoke all on function public.expire_stale_provider_recovery_requests_v1(uuid)
from public, anon, authenticated;
grant execute on function public.expire_stale_provider_recovery_requests_v1(uuid)
to service_role;

create or replace function public.claim_provider_recovery_request_v2(
  p_request_id uuid,
  p_expected_revision bigint default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public.expire_stale_provider_recovery_requests_v1(p_request_id);
  return public.claim_provider_recovery_request_v1(
    p_request_id,
    p_expected_revision
  );
end;
$$;

revoke all on function public.claim_provider_recovery_request_v2(uuid, bigint)
from public, anon, authenticated;
grant execute on function public.claim_provider_recovery_request_v2(uuid, bigint)
to service_role;

create or replace function public.claim_next_provider_recovery_request_v2()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public.expire_stale_provider_recovery_requests_v1(null);
  return public.claim_next_provider_recovery_request_v1();
end;
$$;

revoke all on function public.claim_next_provider_recovery_request_v2()
from public, anon, authenticated;
grant execute on function public.claim_next_provider_recovery_request_v2()
to service_role;

create or replace function public.get_league_provider_recovery_center_v2(
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
  v_owner_id uuid;
  v_stale_running_count integer := 0;
  v_timed_out_last_24h integer := 0;
  v_latest_watchdog_at timestamptz;
  v_healthy boolean;
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

  v_center := public.get_league_provider_recovery_center_v1(p_league_id);

  select count(*)::integer
  into v_stale_running_count
  from public.provider_recovery_requests request_row
  left join public.provider_sync_runs run_row
    on run_row.id = request_row.recovery_run_id
  where request_row.league_id = p_league_id
    and request_row.status = 'running'
    and greatest(
      coalesce(request_row.updated_at, '-infinity'::timestamptz),
      coalesce(request_row.started_at, '-infinity'::timestamptz),
      coalesce(run_row.last_updated_at, '-infinity'::timestamptz),
      coalesce(run_row.started_at, '-infinity'::timestamptz)
    ) < now() - (
      public.provider_recovery_timeout_seconds_v1(request_row.sync_type)
      * interval '1 second'
    );

  select
    count(*) filter (
      where watchdog_row.created_at >= now() - interval '24 hours'
    )::integer,
    max(watchdog_row.created_at)
  into v_timed_out_last_24h, v_latest_watchdog_at
  from public.provider_recovery_watchdog_events watchdog_row
  where watchdog_row.league_id = p_league_id;

  v_healthy := coalesce((v_center ->> 'healthy')::boolean, false)
    and coalesce(v_stale_running_count, 0) = 0;

  return v_center || jsonb_build_object(
    'healthy', v_healthy,
    'watchdogActive', true,
    'staleRunningCount', coalesce(v_stale_running_count, 0),
    'timedOutLast24h', coalesce(v_timed_out_last_24h, 0),
    'latestWatchdogAt', v_latest_watchdog_at,
    'timeoutPolicy', jsonb_build_object(
      'fixturePlayersSeconds',
        public.provider_recovery_timeout_seconds_v1('sync-fixture-players'),
      'fixturesSeconds',
        public.provider_recovery_timeout_seconds_v1('sync-fixtures'),
      'seasonPlayersSeconds',
        public.provider_recovery_timeout_seconds_v1('sync-season-players')
    )
  );
end;
$$;

revoke all on function public.get_league_provider_recovery_center_v2(uuid)
from public, anon, authenticated;
grant execute on function public.get_league_provider_recovery_center_v2(uuid)
to authenticated;

create or replace function public.get_league_provider_sync_health_v5(
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
  v_health := public.get_league_provider_sync_health_v4(p_league_id);
  v_recovery := public.get_league_provider_recovery_center_v2(p_league_id);
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

revoke all on function public.get_league_provider_sync_health_v5(uuid)
from public, anon, authenticated;
grant execute on function public.get_league_provider_sync_health_v5(uuid)
to authenticated;

do $realtime$
begin
  if exists (
    select 1
    from pg_catalog.pg_publication publication
    where publication.pubname = 'supabase_realtime'
  ) and not exists (
    select 1
    from pg_catalog.pg_publication_tables publication_table
    where publication_table.pubname = 'supabase_realtime'
      and publication_table.schemaname = 'public'
      and publication_table.tablename = 'provider_recovery_watchdog_events'
  ) then
    alter publication supabase_realtime
      add table public.provider_recovery_watchdog_events;
  end if;
end;
$realtime$;

create or replace function public.get_provider_recovery_watchdog_integrity_v1()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'watchdog_table_ready',
      to_regclass('public.provider_recovery_watchdog_events') is not null,
    'watchdog_columns_ready',
      (
        select count(*) = 13
        from information_schema.columns column_row
        where column_row.table_schema = 'public'
          and column_row.table_name = 'provider_recovery_watchdog_events'
          and column_row.column_name in (
            'id', 'request_id', 'league_id', 'incident_id', 'run_id',
            'sync_type', 'event_type', 'request_revision', 'run_revision',
            'timeout_seconds', 'elapsed_seconds', 'event_fingerprint',
            'created_at'
          )
      ),
    'watchdog_indexes_ready',
      to_regclass(
        'public.provider_recovery_watchdog_events_league_latest_idx'
      ) is not null
      and to_regclass(
        'public.provider_recovery_watchdog_events_request_idx'
      ) is not null,
    'watchdog_immutable_ready',
      to_regprocedure(
        'public.prevent_provider_recovery_watchdog_event_mutation_v1()'
      ) is not null
      and exists (
        select 1
        from pg_trigger trigger_row
        where trigger_row.tgname = 'provider_recovery_watchdog_events_immutable'
          and trigger_row.tgrelid =
            'public.provider_recovery_watchdog_events'::regclass
          and not trigger_row.tgisinternal
      ),
    'timeout_policy_rpc_ready',
      to_regprocedure(
        'public.provider_recovery_timeout_seconds_v1(text)'
      ) is not null,
    'timeout_policy_values_ready',
      public.provider_recovery_timeout_seconds_v1('sync-fixture-players') = 900
      and public.provider_recovery_timeout_seconds_v1('sync-fixtures') = 1200
      and public.provider_recovery_timeout_seconds_v1('sync-season-players') = 3600,
    'watchdog_expire_rpc_ready',
      to_regprocedure(
        'public.expire_stale_provider_recovery_requests_v1(uuid)'
      ) is not null
      and has_function_privilege(
        'service_role',
        'public.expire_stale_provider_recovery_requests_v1(uuid)',
        'EXECUTE'
      ),
    'watchdog_claim_rpc_ready',
      to_regprocedure(
        'public.claim_provider_recovery_request_v2(uuid,bigint)'
      ) is not null
      and has_function_privilege(
        'service_role',
        'public.claim_provider_recovery_request_v2(uuid,bigint)',
        'EXECUTE'
      ),
    'watchdog_next_claim_rpc_ready',
      to_regprocedure(
        'public.claim_next_provider_recovery_request_v2()'
      ) is not null
      and has_function_privilege(
        'service_role',
        'public.claim_next_provider_recovery_request_v2()',
        'EXECUTE'
      ),
    'watchdog_center_rpc_ready',
      to_regprocedure(
        'public.get_league_provider_recovery_center_v2(uuid)'
      ) is not null
      and has_function_privilege(
        'authenticated',
        'public.get_league_provider_recovery_center_v2(uuid)',
        'EXECUTE'
      ),
    'provider_health_v5_ready',
      to_regprocedure(
        'public.get_league_provider_sync_health_v5(uuid)'
      ) is not null
      and has_function_privilege(
        'authenticated',
        'public.get_league_provider_sync_health_v5(uuid)',
        'EXECUTE'
      ),
    'watchdog_rls_ready',
      coalesce((
        select class_row.relrowsecurity
        from pg_class class_row
        join pg_namespace namespace_row
          on namespace_row.oid = class_row.relnamespace
        where namespace_row.nspname = 'public'
          and class_row.relname = 'provider_recovery_watchdog_events'
      ), false),
    'watchdog_policy_ready',
      exists (
        select 1
        from pg_policies policy_row
        where policy_row.schemaname = 'public'
          and policy_row.tablename = 'provider_recovery_watchdog_events'
          and policy_row.policyname =
            'provider_recovery_watchdog_events_read_directors'
      ),
    'authenticated_watchdog_read_ready',
      has_table_privilege(
        'authenticated',
        'public.provider_recovery_watchdog_events',
        'SELECT'
      ),
    'authenticated_watchdog_writes_blocked',
      not has_table_privilege(
        'authenticated',
        'public.provider_recovery_watchdog_events',
        'INSERT'
      )
      and not has_table_privilege(
        'authenticated',
        'public.provider_recovery_watchdog_events',
        'UPDATE'
      )
      and not has_table_privilege(
        'authenticated',
        'public.provider_recovery_watchdog_events',
        'DELETE'
      ),
    'service_role_watchdog_insert_ready',
      has_table_privilege(
        'service_role',
        'public.provider_recovery_watchdog_events',
        'INSERT'
      ),
    'watchdog_realtime_ready',
      exists (
        select 1
        from pg_catalog.pg_publication_tables publication_table
        where publication_table.pubname = 'supabase_realtime'
          and publication_table.schemaname = 'public'
          and publication_table.tablename =
            'provider_recovery_watchdog_events'
      ),
    'recovery_queue_continuity_ready',
      to_regprocedure(
        'public.get_provider_recovery_queue_integrity_v1()'
      ) is not null
      and to_regclass('public.provider_recovery_requests') is not null,
    'provider_finish_continuity_ready',
      to_regprocedure(
        'public.finish_provider_sync_run_guarded_v1(uuid,text,integer,text,bigint)'
      ) is not null,
    'provider_incident_continuity_ready',
      to_regclass('public.provider_operational_incidents') is not null
      and to_regprocedure(
        'public.get_league_provider_sync_health_v4(uuid)'
      ) is not null
  );
$$;

revoke all on function public.get_provider_recovery_watchdog_integrity_v1()
from public, anon, authenticated;
grant execute on function public.get_provider_recovery_watchdog_integrity_v1()
to authenticated, service_role;

-- Arresta la transazione indicando il nome esatto degli eventuali controlli falsi.
do $validation$
declare
  v_checks jsonb := public.get_provider_recovery_watchdog_integrity_v1();
  v_failed text[];
begin
  select array_agg(check_row.key order by check_row.key)
  into v_failed
  from jsonb_each(v_checks) check_row
  where jsonb_typeof(check_row.value) is distinct from 'boolean'
    or check_row.value is distinct from 'true'::jsonb;

  if coalesce(array_length(v_failed, 1), 0) > 0 then
    raise exception
      'Validazione v0.62.6 non superata. Controlli falsi: %',
      array_to_string(v_failed, '; ');
  end if;
end;
$validation$;

commit;

-- Diagnostica finale: devono comparire esattamente 20 valori true.
select
  (checks ->> 'watchdog_table_ready')::boolean
    as watchdog_table_ready,
  (checks ->> 'watchdog_columns_ready')::boolean
    as watchdog_columns_ready,
  (checks ->> 'watchdog_indexes_ready')::boolean
    as watchdog_indexes_ready,
  (checks ->> 'watchdog_immutable_ready')::boolean
    as watchdog_immutable_ready,
  (checks ->> 'timeout_policy_rpc_ready')::boolean
    as timeout_policy_rpc_ready,
  (checks ->> 'timeout_policy_values_ready')::boolean
    as timeout_policy_values_ready,
  (checks ->> 'watchdog_expire_rpc_ready')::boolean
    as watchdog_expire_rpc_ready,
  (checks ->> 'watchdog_claim_rpc_ready')::boolean
    as watchdog_claim_rpc_ready,
  (checks ->> 'watchdog_next_claim_rpc_ready')::boolean
    as watchdog_next_claim_rpc_ready,
  (checks ->> 'watchdog_center_rpc_ready')::boolean
    as watchdog_center_rpc_ready,
  (checks ->> 'provider_health_v5_ready')::boolean
    as provider_health_v5_ready,
  (checks ->> 'watchdog_rls_ready')::boolean
    as watchdog_rls_ready,
  (checks ->> 'watchdog_policy_ready')::boolean
    as watchdog_policy_ready,
  (checks ->> 'authenticated_watchdog_read_ready')::boolean
    as authenticated_watchdog_read_ready,
  (checks ->> 'authenticated_watchdog_writes_blocked')::boolean
    as authenticated_watchdog_writes_blocked,
  (checks ->> 'service_role_watchdog_insert_ready')::boolean
    as service_role_watchdog_insert_ready,
  (checks ->> 'watchdog_realtime_ready')::boolean
    as watchdog_realtime_ready,
  (checks ->> 'recovery_queue_continuity_ready')::boolean
    as recovery_queue_continuity_ready,
  (checks ->> 'provider_finish_continuity_ready')::boolean
    as provider_finish_continuity_ready,
  (checks ->> 'provider_incident_continuity_ready')::boolean
    as provider_incident_continuity_ready
from (
  select public.get_provider_recovery_watchdog_integrity_v1() as checks
) diagnostic;
