-- LEGHEVO v0.62.36
-- Telemetria operativa autorevole e rollback automatico
-- Dipendenza: v0.62.35 validata con 20/20 controlli true.

begin;

-- La v0.62.35 deve essere realmente integra prima di sostituire la testa
-- terminale con la nuova release e il nuovo rollout.
do $preflight$
declare
  v_integrity jsonb;
  v_false text[];
begin
  if to_regprocedure('public.get_leghevo_authoritative_telemetry_deployment_integrity_v1()') is not null
    and exists (
      select 1 from public.leghevo_application_release_certificates c
      where c.application_version = '0.62.36'
    ) then
    return;
  end if;

  if to_regprocedure('public.get_leghevo_rollout_deployment_integrity_v1()') is null then
    raise exception 'Preflight v0.62.36 non superato: diagnostica v0.62.35 assente.';
  end if;

  v_integrity := public.get_leghevo_rollout_deployment_integrity_v1();
  select array_agg(item.key order by item.key) into v_false
  from pg_catalog.jsonb_each(v_integrity) item
  where pg_catalog.jsonb_typeof(item.value) is distinct from 'boolean'
     or item.value is distinct from 'true'::jsonb;

  if (select count(*) from pg_catalog.jsonb_each(v_integrity)) <> 20
    or cardinality(v_false) > 0 then
    raise exception 'Preflight v0.62.36 non superato: %. Dettaglio: %',
      coalesce(array_to_string(v_false, ', '), 'numero controlli diverso da 20'),
      v_integrity;
  end if;
end;
$preflight$;

create or replace function public.compute_leghevo_telemetry_source_fingerprint_v1(
  p_environment_key text,
  p_source_key text,
  p_source_generation bigint,
  p_fencing_token_hash text,
  p_contract_version integer default 1
)
returns text
language sql
immutable
security definer
set search_path = ''
as $function$
  select pg_catalog.md5(
    coalesce(lower(trim(p_environment_key)), '') || '|' ||
    coalesce(lower(trim(p_source_key)), '') || '|' ||
    coalesce(p_source_generation, 0)::text || '|' ||
    coalesce(lower(trim(p_fencing_token_hash)), '') || '|' ||
    coalesce(p_contract_version, 0)::text
  );
$function$;

revoke all on function public.compute_leghevo_telemetry_source_fingerprint_v1(
  text,text,bigint,text,integer
) from public, anon, authenticated;
grant execute on function public.compute_leghevo_telemetry_source_fingerprint_v1(
  text,text,bigint,text,integer
) to service_role;

create or replace function public.compute_leghevo_operational_observation_fingerprint_v1(
  p_environment_key text,
  p_source_id uuid,
  p_source_generation bigint,
  p_window_sequence bigint,
  p_window_started_at timestamptz,
  p_window_ended_at timestamptz,
  p_release_id uuid,
  p_release_generation bigint,
  p_rollout_plan_id uuid,
  p_rollout_generation bigint,
  p_exposure_percentage integer,
  p_total_requests integer,
  p_failed_requests integer,
  p_crash_count integer,
  p_error_rate_bps integer,
  p_p95_latency_ms integer,
  p_verdict text,
  p_contract_version integer default 1
)
returns text
language sql
immutable
security definer
set search_path = ''
as $function$
  select pg_catalog.md5(
    coalesce(lower(trim(p_environment_key)), '') || '|' ||
    coalesce(p_source_id::text, '') || '|' ||
    coalesce(p_source_generation, 0)::text || '|' ||
    coalesce(p_window_sequence, 0)::text || '|' ||
    coalesce(extract(epoch from p_window_started_at)::text, '') || '|' ||
    coalesce(extract(epoch from p_window_ended_at)::text, '') || '|' ||
    coalesce(p_release_id::text, '') || '|' ||
    coalesce(p_release_generation, 0)::text || '|' ||
    coalesce(p_rollout_plan_id::text, '') || '|' ||
    coalesce(p_rollout_generation, 0)::text || '|' ||
    coalesce(p_exposure_percentage, 0)::text || '|' ||
    coalesce(p_total_requests, 0)::text || '|' ||
    coalesce(p_failed_requests, 0)::text || '|' ||
    coalesce(p_crash_count, 0)::text || '|' ||
    coalesce(p_error_rate_bps, 0)::text || '|' ||
    coalesce(p_p95_latency_ms, -1)::text || '|' ||
    coalesce(lower(trim(p_verdict)), '') || '|' ||
    coalesce(p_contract_version, 0)::text
  );
$function$;

revoke all on function public.compute_leghevo_operational_observation_fingerprint_v1(
  text,uuid,bigint,bigint,timestamptz,timestamptz,uuid,bigint,uuid,bigint,
  integer,integer,integer,integer,integer,integer,text,integer
) from public, anon, authenticated;
grant execute on function public.compute_leghevo_operational_observation_fingerprint_v1(
  text,uuid,bigint,bigint,timestamptz,timestamptz,uuid,bigint,uuid,bigint,
  integer,integer,integer,integer,integer,integer,text,integer
) to service_role;

create table if not exists public.leghevo_operational_telemetry_sources (
  id uuid primary key default gen_random_uuid(),
  environment_key text not null,
  request_id uuid not null unique,
  source_key text not null,
  source_generation bigint not null,
  fencing_token_hash text not null,
  telemetry_contract_version integer not null default 1,
  source_fingerprint text not null unique,
  certified_at timestamptz not null default now(),
  certified_by uuid null,
  metadata jsonb not null default '{}'::jsonb,
  constraint leghevo_telemetry_source_environment_check
    check (environment_key in ('production','staging')),
  constraint leghevo_telemetry_source_key_check
    check (source_key ~ '^[a-z0-9][a-z0-9._-]{2,79}$'),
  constraint leghevo_telemetry_source_generation_check
    check (source_generation >= 1),
  constraint leghevo_telemetry_source_token_hash_check
    check (fencing_token_hash ~ '^[0-9a-f]{32}$'),
  constraint leghevo_telemetry_source_contract_check
    check (telemetry_contract_version >= 1),
  constraint leghevo_telemetry_source_fingerprint_check
    check (source_fingerprint ~ '^[0-9a-f]{32}$'),
  constraint leghevo_telemetry_source_metadata_check
    check (jsonb_typeof(metadata) = 'object'),
  constraint leghevo_telemetry_source_generation_unique
    unique (environment_key, source_key, source_generation)
);

create table if not exists public.leghevo_operational_telemetry_observations (
  id bigint generated by default as identity primary key,
  environment_key text not null,
  request_id uuid not null unique,
  source_id uuid not null references public.leghevo_operational_telemetry_sources(id),
  source_generation bigint not null,
  window_sequence bigint not null,
  window_started_at timestamptz not null,
  window_ended_at timestamptz not null,
  release_id uuid not null references public.leghevo_application_release_certificates(id),
  release_generation bigint not null,
  rollout_plan_id uuid not null references public.leghevo_application_rollout_plans(id),
  rollout_generation bigint not null,
  exposure_percentage integer not null,
  total_requests integer not null,
  failed_requests integer not null,
  crash_count integer not null,
  error_rate_bps integer not null,
  p95_latency_ms integer null,
  verdict text not null,
  observation_contract_version integer not null default 1,
  observation_fingerprint text not null unique,
  details jsonb not null default '{}'::jsonb,
  recorded_at timestamptz not null default now(),
  recorded_by uuid null,
  constraint leghevo_telemetry_observation_environment_check
    check (environment_key in ('production','staging')),
  constraint leghevo_telemetry_observation_source_generation_check
    check (source_generation >= 1),
  constraint leghevo_telemetry_observation_sequence_check
    check (window_sequence >= 1),
  constraint leghevo_telemetry_observation_window_check
    check (window_ended_at > window_started_at),
  constraint leghevo_telemetry_observation_release_generation_check
    check (release_generation >= 1),
  constraint leghevo_telemetry_observation_rollout_generation_check
    check (rollout_generation >= 1),
  constraint leghevo_telemetry_observation_exposure_check
    check (exposure_percentage between 0 and 100),
  constraint leghevo_telemetry_observation_counts_check
    check (
      total_requests >= 0
      and failed_requests between 0 and total_requests
      and crash_count >= 0
      and error_rate_bps between 0 and 10000
      and (p95_latency_ms is null or p95_latency_ms >= 0)
    ),
  constraint leghevo_telemetry_observation_verdict_check
    check (verdict in ('healthy','degraded','critical')),
  constraint leghevo_telemetry_observation_contract_check
    check (observation_contract_version >= 1),
  constraint leghevo_telemetry_observation_fingerprint_check
    check (observation_fingerprint ~ '^[0-9a-f]{32}$'),
  constraint leghevo_telemetry_observation_details_check
    check (jsonb_typeof(details) = 'object'),
  constraint leghevo_telemetry_observation_sequence_unique
    unique (environment_key, source_generation, window_sequence)
);

create table if not exists public.leghevo_operational_telemetry_heads (
  environment_key text primary key,
  source_id uuid not null references public.leghevo_operational_telemetry_sources(id),
  source_generation bigint not null,
  generation bigint not null default 1,
  state text not null default 'active',
  safe_state text not null default 'active',
  last_window_sequence bigint not null default 0,
  last_window_started_at timestamptz null,
  last_window_ended_at timestamptz null,
  last_observation_id bigint null,
  auto_rollback_enabled boolean not null default true,
  auto_rollback_triggered boolean not null default false,
  last_request_id uuid not null unique,
  affected_reason text null,
  changed_by uuid null,
  updated_at timestamptz not null default now(),
  constraint leghevo_telemetry_head_environment_check
    check (environment_key in ('production','staging')),
  constraint leghevo_telemetry_head_source_generation_check
    check (source_generation >= 1),
  constraint leghevo_telemetry_head_generation_check
    check (generation >= 1),
  constraint leghevo_telemetry_head_state_check
    check (state in ('active','degraded','critical','affected')),
  constraint leghevo_telemetry_head_safe_state_check
    check (safe_state in ('active','degraded','critical')),
  constraint leghevo_telemetry_head_state_consistency_check
    check (state = 'affected' or state = safe_state),
  constraint leghevo_telemetry_head_sequence_check
    check (last_window_sequence >= 0),
  constraint leghevo_telemetry_head_window_consistency_check
    check (
      (last_window_sequence = 0
        and last_window_started_at is null
        and last_window_ended_at is null
        and last_observation_id is null)
      or
      (last_window_sequence > 0
        and last_window_started_at is not null
        and last_window_ended_at is not null
        and last_window_ended_at > last_window_started_at
        and last_observation_id is not null)
    ),
  constraint leghevo_telemetry_head_affected_reason_check
    check (
      (state = 'affected' and char_length(trim(affected_reason)) >= 8)
      or (state <> 'affected' and affected_reason is null)
    )
);

create table if not exists public.leghevo_operational_telemetry_events (
  id bigint generated by default as identity primary key,
  environment_key text not null,
  request_id uuid not null unique,
  event_type text not null,
  source_id uuid not null references public.leghevo_operational_telemetry_sources(id),
  observation_id bigint null references public.leghevo_operational_telemetry_observations(id),
  generation bigint not null,
  reason_code text not null,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  created_by uuid null,
  constraint leghevo_telemetry_event_environment_check
    check (environment_key in ('production','staging')),
  constraint leghevo_telemetry_event_type_check
    check (event_type in (
      'source_certified','window_accepted','degraded','critical',
      'affected','revalidated'
    )),
  constraint leghevo_telemetry_event_generation_check
    check (generation >= 1),
  constraint leghevo_telemetry_event_reason_check
    check (char_length(trim(reason_code)) between 3 and 160),
  constraint leghevo_telemetry_event_details_check
    check (jsonb_typeof(details) = 'object')
);

create index if not exists leghevo_telemetry_sources_environment_generation_idx
on public.leghevo_operational_telemetry_sources(
  environment_key, source_generation desc, certified_at desc
);
create index if not exists leghevo_telemetry_observations_environment_window_idx
on public.leghevo_operational_telemetry_observations(
  environment_key, window_ended_at desc, id desc
);
create index if not exists leghevo_telemetry_observations_rollout_generation_idx
on public.leghevo_operational_telemetry_observations(
  rollout_plan_id, rollout_generation desc, id desc
);
create index if not exists leghevo_telemetry_events_environment_created_idx
on public.leghevo_operational_telemetry_events(
  environment_key, created_at desc, id desc
);

alter table public.leghevo_operational_telemetry_sources enable row level security;
alter table public.leghevo_operational_telemetry_observations enable row level security;
alter table public.leghevo_operational_telemetry_heads enable row level security;
alter table public.leghevo_operational_telemetry_events enable row level security;

-- La tabella sorgenti contiene l'hash del fencing token: nessuna lettura diretta
-- dai client. I dati pubblicabili passano esclusivamente dalle RPC security definer.
drop policy if exists leghevo_telemetry_sources_read on public.leghevo_operational_telemetry_sources;

drop policy if exists leghevo_telemetry_heads_read on public.leghevo_operational_telemetry_heads;
create policy leghevo_telemetry_heads_read
on public.leghevo_operational_telemetry_heads for select
to authenticated using (true);

drop policy if exists leghevo_telemetry_events_read on public.leghevo_operational_telemetry_events;
create policy leghevo_telemetry_events_read
on public.leghevo_operational_telemetry_events for select
to authenticated using (true);

revoke all on table public.leghevo_operational_telemetry_sources
from public, anon, authenticated, service_role;
revoke all on table public.leghevo_operational_telemetry_observations
from public, anon, authenticated, service_role;
revoke all on table public.leghevo_operational_telemetry_heads
from public, anon, authenticated, service_role;
revoke all on table public.leghevo_operational_telemetry_events
from public, anon, authenticated, service_role;

grant select on table public.leghevo_operational_telemetry_heads to authenticated;
grant select on table public.leghevo_operational_telemetry_events to authenticated;

create or replace function public.guard_leghevo_operational_telemetry_immutable_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if current_setting('leghevo.telemetry_context', true) is distinct from 'allowed' then
    raise exception 'Scrittura diretta telemetria operativa non consentita.';
  end if;
  if tg_op <> 'INSERT' then
    raise exception 'Record telemetrico immutabile: % non consentito.', tg_op;
  end if;
  return new;
end;
$function$;

create or replace function public.guard_leghevo_operational_telemetry_head_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if current_setting('leghevo.telemetry_context', true) is distinct from 'allowed' then
    raise exception 'Mutazione diretta testa telemetrica non consentita.';
  end if;
  if tg_op = 'DELETE' then
    raise exception 'Cancellazione testa telemetrica non consentita.';
  end if;
  return new;
end;
$function$;

drop trigger if exists leghevo_telemetry_sources_guard
on public.leghevo_operational_telemetry_sources;
create trigger leghevo_telemetry_sources_guard
before insert or update or delete on public.leghevo_operational_telemetry_sources
for each row execute function public.guard_leghevo_operational_telemetry_immutable_v1();
alter table public.leghevo_operational_telemetry_sources
  enable always trigger leghevo_telemetry_sources_guard;

drop trigger if exists leghevo_telemetry_observations_guard
on public.leghevo_operational_telemetry_observations;
create trigger leghevo_telemetry_observations_guard
before insert or update or delete on public.leghevo_operational_telemetry_observations
for each row execute function public.guard_leghevo_operational_telemetry_immutable_v1();
alter table public.leghevo_operational_telemetry_observations
  enable always trigger leghevo_telemetry_observations_guard;

drop trigger if exists leghevo_telemetry_events_guard
on public.leghevo_operational_telemetry_events;
create trigger leghevo_telemetry_events_guard
before insert or update or delete on public.leghevo_operational_telemetry_events
for each row execute function public.guard_leghevo_operational_telemetry_immutable_v1();
alter table public.leghevo_operational_telemetry_events
  enable always trigger leghevo_telemetry_events_guard;

drop trigger if exists leghevo_telemetry_heads_guard
on public.leghevo_operational_telemetry_heads;
create trigger leghevo_telemetry_heads_guard
before insert or update or delete on public.leghevo_operational_telemetry_heads
for each row execute function public.guard_leghevo_operational_telemetry_head_v1();
alter table public.leghevo_operational_telemetry_heads
  enable always trigger leghevo_telemetry_heads_guard;

create or replace function public.certify_leghevo_operational_telemetry_source_v1(
  p_environment_key text,
  p_source_key text,
  p_source_generation bigint,
  p_fencing_token uuid,
  p_request_id uuid,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_environment text := lower(trim(coalesce(p_environment_key, '')));
  v_source_key text := lower(trim(coalesce(p_source_key, '')));
  v_token_hash text;
  v_fingerprint text;
  v_existing public.leghevo_operational_telemetry_sources%rowtype;
  v_head public.leghevo_operational_telemetry_heads%rowtype;
  v_source_id uuid;
  v_generation bigint;
begin
  if v_environment not in ('production','staging')
    or v_source_key !~ '^[a-z0-9][a-z0-9._-]{2,79}$'
    or p_source_generation is null or p_source_generation < 1
    or p_fencing_token is null or p_request_id is null
    or jsonb_typeof(coalesce(p_metadata, '{}'::jsonb)) <> 'object' then
    raise exception 'Certificazione sorgente telemetrica non valida.';
  end if;

  v_token_hash := pg_catalog.md5(p_fencing_token::text);
  v_fingerprint := public.compute_leghevo_telemetry_source_fingerprint_v1(
    v_environment, v_source_key, p_source_generation, v_token_hash, 1);

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('leghevo:operational-telemetry', 0));

  select source.* into v_existing
  from public.leghevo_operational_telemetry_sources source
  where source.request_id = p_request_id;
  if found then
    if v_existing.environment_key <> v_environment
      or v_existing.source_key <> v_source_key
      or v_existing.source_generation <> p_source_generation
      or v_existing.source_fingerprint <> v_fingerprint then
      raise exception 'request_id già utilizzato per una sorgente telemetrica diversa.';
    end if;
    return jsonb_build_object(
      'sourceId', v_existing.id,
      'sourceGeneration', v_existing.source_generation,
      'reused', true
    );
  end if;

  select source.* into v_existing
  from public.leghevo_operational_telemetry_sources source
  where source.environment_key = v_environment
    and source.source_key = v_source_key
    and source.source_generation = p_source_generation;
  if found then
    if v_existing.source_fingerprint <> v_fingerprint then
      raise exception 'Generazione sorgente già certificata con fencing token diverso.';
    end if;
    return jsonb_build_object(
      'sourceId', v_existing.id,
      'sourceGeneration', v_existing.source_generation,
      'reused', true
    );
  end if;

  select head.* into v_head
  from public.leghevo_operational_telemetry_heads head
  where head.environment_key = v_environment
  for update;
  if found and p_source_generation <= v_head.source_generation then
    raise exception 'Generazione sorgente non monotona: corrente %, richiesta %.',
      v_head.source_generation, p_source_generation;
  end if;

  perform set_config('leghevo.telemetry_context', 'allowed', true);
  insert into public.leghevo_operational_telemetry_sources(
    environment_key, request_id, source_key, source_generation,
    fencing_token_hash, telemetry_contract_version, source_fingerprint,
    certified_by, metadata
  ) values (
    v_environment, p_request_id, v_source_key, p_source_generation,
    v_token_hash, 1, v_fingerprint, auth.uid(), coalesce(p_metadata, '{}'::jsonb)
  ) returning id into v_source_id;

  if v_head.environment_key is null then
    v_generation := 1;
    insert into public.leghevo_operational_telemetry_heads(
      environment_key, source_id, source_generation, generation,
      state, safe_state, last_window_sequence, auto_rollback_enabled,
      auto_rollback_triggered, last_request_id, changed_by
    ) values (
      v_environment, v_source_id, p_source_generation, v_generation,
      'active', 'active', 0, true, false, p_request_id, auth.uid()
    );
  else
    v_generation := v_head.generation + 1;
    update public.leghevo_operational_telemetry_heads
    set source_id = v_source_id,
        source_generation = p_source_generation,
        generation = v_generation,
        state = 'active',
        safe_state = 'active',
        last_window_sequence = 0,
        last_window_started_at = null,
        last_window_ended_at = null,
        last_observation_id = null,
        auto_rollback_triggered = false,
        last_request_id = p_request_id,
        affected_reason = null,
        changed_by = auth.uid(),
        updated_at = now()
    where environment_key = v_environment;
  end if;

  insert into public.leghevo_operational_telemetry_events(
    environment_key, request_id, event_type, source_id,
    observation_id, generation, reason_code, details, created_by
  ) values (
    v_environment, p_request_id, 'source_certified', v_source_id,
    null, v_generation, 'telemetry.source_certified',
    jsonb_build_object(
      'sourceKey', v_source_key,
      'sourceGeneration', p_source_generation,
      'sourceFingerprint', v_fingerprint
    ), auth.uid()
  );
  perform set_config('leghevo.telemetry_context', '', true);

  return jsonb_build_object(
    'sourceId', v_source_id,
    'sourceGeneration', p_source_generation,
    'telemetryGeneration', v_generation,
    'reused', false
  );
exception when others then
  perform set_config('leghevo.telemetry_context', '', true);
  raise;
end;
$function$;

revoke all on function public.certify_leghevo_operational_telemetry_source_v1(
  text,text,bigint,uuid,uuid,jsonb
) from public, anon, authenticated;
grant execute on function public.certify_leghevo_operational_telemetry_source_v1(
  text,text,bigint,uuid,uuid,jsonb
) to service_role;

create or replace function public.record_leghevo_authoritative_operational_window_v1(
  p_environment_key text,
  p_source_key text,
  p_source_generation bigint,
  p_fencing_token uuid,
  p_window_sequence bigint,
  p_window_started_at timestamptz,
  p_window_ended_at timestamptz,
  p_total_requests integer,
  p_failed_requests integer,
  p_crash_count integer,
  p_p95_latency_ms integer,
  p_request_id uuid,
  p_details jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_environment text := lower(trim(coalesce(p_environment_key, '')));
  v_source_key text := lower(trim(coalesce(p_source_key, '')));
  v_head public.leghevo_operational_telemetry_heads%rowtype;
  v_source public.leghevo_operational_telemetry_sources%rowtype;
  v_existing public.leghevo_operational_telemetry_observations%rowtype;
  v_release_head public.leghevo_application_release_heads%rowtype;
  v_release public.leghevo_application_release_certificates%rowtype;
  v_previous public.leghevo_application_release_certificates%rowtype;
  v_rollout_head public.leghevo_application_rollout_heads%rowtype;
  v_plan public.leghevo_application_rollout_plans%rowtype;
  v_error_rate integer;
  v_verdict text;
  v_observation_id bigint;
  v_observation_fingerprint text;
  v_generation bigint;
  v_rollout_generation bigint;
  v_rollout_state text;
  v_auto_rollback boolean := false;
  v_rollback_request_id uuid;
begin
  if v_environment not in ('production','staging')
    or v_source_key !~ '^[a-z0-9][a-z0-9._-]{2,79}$'
    or p_source_generation is null or p_source_generation < 1
    or p_fencing_token is null
    or p_window_sequence is null or p_window_sequence < 1
    or p_window_started_at is null or p_window_ended_at is null
    or p_window_ended_at <= p_window_started_at
    or p_window_ended_at - p_window_started_at < interval '1 minute'
    or p_window_ended_at - p_window_started_at > interval '2 hours'
    or p_window_ended_at > now() + interval '2 minutes'
    or p_total_requests is null or p_failed_requests is null
    or p_crash_count is null
    or p_total_requests < 0 or p_failed_requests < 0
    or p_failed_requests > p_total_requests or p_crash_count < 0
    or (p_p95_latency_ms is not null and p_p95_latency_ms < 0)
    or p_request_id is null
    or jsonb_typeof(coalesce(p_details, '{}'::jsonb)) <> 'object' then
    raise exception 'Finestra telemetrica autorevole non valida.';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('leghevo:application-release', 0));
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('leghevo:application-rollout', 0));
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('leghevo:operational-telemetry', 0));

  select observation.* into v_existing
  from public.leghevo_operational_telemetry_observations observation
  where observation.request_id = p_request_id;
  if found then
    if v_existing.environment_key <> v_environment
      or v_existing.source_generation <> p_source_generation
      or v_existing.window_sequence <> p_window_sequence
      or v_existing.window_started_at <> p_window_started_at
      or v_existing.window_ended_at <> p_window_ended_at
      or v_existing.total_requests <> p_total_requests
      or v_existing.failed_requests <> p_failed_requests
      or v_existing.crash_count <> p_crash_count
      or v_existing.p95_latency_ms is distinct from p_p95_latency_ms then
      raise exception 'request_id già utilizzato per una finestra telemetrica diversa.';
    end if;
    return jsonb_build_object(
      'observationId', v_existing.id,
      'verdict', v_existing.verdict,
      'errorRateBps', v_existing.error_rate_bps,
      'reused', true
    );
  end if;

  select head.* into strict v_head
  from public.leghevo_operational_telemetry_heads head
  where head.environment_key = v_environment
  for update;
  select source.* into strict v_source
  from public.leghevo_operational_telemetry_sources source
  where source.id = v_head.source_id;

  if v_source.source_key <> v_source_key
    or v_source.source_generation <> p_source_generation
    or v_head.source_generation <> p_source_generation
    or v_source.fencing_token_hash <> pg_catalog.md5(p_fencing_token::text)
    or v_source.source_fingerprint <>
      public.compute_leghevo_telemetry_source_fingerprint_v1(
        v_source.environment_key, v_source.source_key,
        v_source.source_generation, v_source.fencing_token_hash,
        v_source.telemetry_contract_version) then
    raise exception 'Sorgente telemetrica non corrente o fencing token superato.';
  end if;

  if p_window_sequence <> v_head.last_window_sequence + 1 then
    raise exception 'Sequenza finestra non monotona: attesa %, ricevuta %.',
      v_head.last_window_sequence + 1, p_window_sequence;
  end if;
  if v_head.last_window_ended_at is not null
    and p_window_started_at < v_head.last_window_ended_at then
    raise exception 'Finestra telemetrica sovrapposta alla precedente.';
  end if;

  select release_head.* into strict v_release_head
  from public.leghevo_application_release_heads release_head
  where release_head.environment_key = v_environment
  for update;
  select certificate.* into strict v_release
  from public.leghevo_application_release_certificates certificate
  where certificate.id = v_release_head.active_release_id;
  select rollout_head.* into strict v_rollout_head
  from public.leghevo_application_rollout_heads rollout_head
  where rollout_head.environment_key = v_environment
  for update;
  select plan.* into strict v_plan
  from public.leghevo_application_rollout_plans plan
  where plan.id = v_rollout_head.plan_id;

  if v_release_head.state = 'affected'
    or v_rollout_head.state in ('killed','affected')
    or v_plan.release_id <> v_release.id then
    raise exception 'Finestra bloccata: release o rollout non coerenti.';
  end if;

  v_error_rate := case
    when p_total_requests = 0 then 10000
    else floor((p_failed_requests::numeric * 10000) / p_total_requests)::integer
  end;

  if p_total_requests >= v_plan.min_observations
    and v_error_rate <= v_plan.error_rate_bps_threshold
    and p_crash_count <= v_plan.crash_count_threshold
    and (p_p95_latency_ms is null or p_p95_latency_ms <= 2000) then
    v_verdict := 'healthy';
  elsif p_total_requests = 0
    or v_error_rate > least(10000, greatest(
      v_plan.error_rate_bps_threshold + 100,
      v_plan.error_rate_bps_threshold * 2))
    or p_crash_count > greatest(
      v_plan.crash_count_threshold + 1,
      v_plan.crash_count_threshold * 2)
    or coalesce(p_p95_latency_ms, 0) > 5000 then
    v_verdict := 'critical';
  else
    v_verdict := 'degraded';
  end if;

  v_observation_fingerprint :=
    public.compute_leghevo_operational_observation_fingerprint_v1(
      v_environment, v_source.id, p_source_generation, p_window_sequence,
      p_window_started_at, p_window_ended_at,
      v_release.id, v_release_head.generation,
      v_plan.id, v_rollout_head.generation,
      v_rollout_head.exposure_percentage,
      p_total_requests, p_failed_requests, p_crash_count,
      v_error_rate, p_p95_latency_ms, v_verdict, 1);

  perform set_config('leghevo.telemetry_context', 'allowed', true);
  perform set_config('leghevo.rollout_context', 'allowed', true);

  insert into public.leghevo_operational_telemetry_observations(
    environment_key, request_id, source_id, source_generation,
    window_sequence, window_started_at, window_ended_at,
    release_id, release_generation, rollout_plan_id, rollout_generation,
    exposure_percentage, total_requests, failed_requests, crash_count,
    error_rate_bps, p95_latency_ms, verdict, observation_contract_version,
    observation_fingerprint, details, recorded_by
  ) values (
    v_environment, p_request_id, v_source.id, p_source_generation,
    p_window_sequence, p_window_started_at, p_window_ended_at,
    v_release.id, v_release_head.generation, v_plan.id, v_rollout_head.generation,
    v_rollout_head.exposure_percentage, p_total_requests, p_failed_requests,
    p_crash_count, v_error_rate, p_p95_latency_ms, v_verdict, 1,
    v_observation_fingerprint, coalesce(p_details, '{}'::jsonb), auth.uid()
  ) returning id into v_observation_id;

  insert into public.leghevo_application_rollout_health_reports(
    environment_key, request_id, plan_id, generation,
    window_started_at, window_ended_at, total_requests, failed_requests,
    crash_count, error_rate_bps, p95_latency_ms, verdict, details, recorded_by
  ) values (
    v_environment, p_request_id, v_plan.id, v_rollout_head.generation,
    p_window_started_at, p_window_ended_at, p_total_requests, p_failed_requests,
    p_crash_count, v_error_rate, p_p95_latency_ms,
    case when v_verdict = 'healthy' then 'healthy' else 'unhealthy' end,
    jsonb_build_object(
      'authoritativeObservationId', v_observation_id,
      'authoritativeVerdict', v_verdict,
      'sourceGeneration', p_source_generation
    ) || coalesce(p_details, '{}'::jsonb),
    auth.uid()
  );

  v_rollout_generation := v_rollout_head.generation;
  v_rollout_state := v_rollout_head.state;

  if v_verdict = 'healthy' then
    insert into public.leghevo_application_rollout_events(
      environment_key, request_id, event_type, plan_id, generation,
      from_percentage, to_percentage, reason_code, details, created_by
    ) values (
      v_environment, p_request_id, 'health_accepted', v_plan.id,
      v_rollout_head.generation,
      v_rollout_head.exposure_percentage, v_rollout_head.exposure_percentage,
      'rollout.authoritative_health_accepted',
      jsonb_build_object(
        'observationId', v_observation_id,
        'errorRateBps', v_error_rate,
        'crashCount', p_crash_count,
        'p95LatencyMs', p_p95_latency_ms
      ), auth.uid()
    );
  else
    v_rollout_generation := v_rollout_head.generation + 1;
    v_rollout_state := case when v_verdict = 'critical' then 'killed' else 'paused' end;

    update public.leghevo_application_rollout_heads
    set generation = v_rollout_generation,
        state = v_rollout_state,
        safe_state = v_rollout_state,
        safe_exposure_percentage = exposure_percentage,
        kill_switch_active = true,
        changed_by = auth.uid(),
        last_request_id = p_request_id,
        affected_reason = null,
        updated_at = now()
    where environment_key = v_environment;

    insert into public.leghevo_application_rollout_events(
      environment_key, request_id, event_type, plan_id, generation,
      from_percentage, to_percentage, reason_code, details, created_by
    ) values (
      v_environment, p_request_id, 'health_rejected', v_plan.id,
      v_rollout_generation,
      v_rollout_head.exposure_percentage, v_rollout_head.exposure_percentage,
      case when v_verdict = 'critical'
        then 'rollout.authoritative_critical_kill_switch'
        else 'rollout.authoritative_degraded_pause' end,
      jsonb_build_object(
        'observationId', v_observation_id,
        'authoritativeVerdict', v_verdict,
        'errorRateBps', v_error_rate,
        'crashCount', p_crash_count,
        'p95LatencyMs', p_p95_latency_ms,
        'nextState', v_rollout_state
      ), auth.uid()
    );
  end if;

  v_generation := v_head.generation + 1;
  if v_verdict = 'critical'
    and v_head.auto_rollback_enabled
    and v_release_head.previous_release_id is not null then
    select certificate.* into strict v_previous
    from public.leghevo_application_release_certificates certificate
    where certificate.id = v_release_head.previous_release_id;

    if public.leghevo_semver_rank_v1(v_previous.application_version)
      < public.leghevo_semver_rank_v1(v_release.application_version) then
      v_rollback_request_id := public.leghevo_stable_request_uuid(
        'telemetry:auto-rollback:' || p_request_id::text);
      perform public.rollback_leghevo_application_release_v1(
        v_environment, v_previous.application_version,
        v_rollback_request_id,
        'telemetry.critical automatic rollback');
      v_auto_rollback := true;
    end if;
  end if;

  update public.leghevo_operational_telemetry_heads
  set generation = v_generation,
      state = case v_verdict
        when 'healthy' then 'active'
        when 'degraded' then 'degraded'
        else 'critical' end,
      safe_state = case v_verdict
        when 'healthy' then 'active'
        when 'degraded' then 'degraded'
        else 'critical' end,
      last_window_sequence = p_window_sequence,
      last_window_started_at = p_window_started_at,
      last_window_ended_at = p_window_ended_at,
      last_observation_id = v_observation_id,
      auto_rollback_triggered = v_auto_rollback,
      last_request_id = p_request_id,
      affected_reason = null,
      changed_by = auth.uid(),
      updated_at = now()
  where environment_key = v_environment;

  insert into public.leghevo_operational_telemetry_events(
    environment_key, request_id, event_type, source_id,
    observation_id, generation, reason_code, details, created_by
  ) values (
    v_environment, p_request_id,
    case v_verdict
      when 'healthy' then 'window_accepted'
      when 'degraded' then 'degraded'
      else 'critical' end,
    v_source.id, v_observation_id, v_generation,
    case v_verdict
      when 'healthy' then 'telemetry.window_accepted'
      when 'degraded' then 'telemetry.degraded_pause'
      else 'telemetry.critical_auto_rollback' end,
    jsonb_build_object(
      'verdict', v_verdict,
      'releaseVersion', v_release.application_version,
      'releaseGeneration', v_release_head.generation,
      'rolloutGeneration', v_rollout_head.generation,
      'exposurePercentage', v_rollout_head.exposure_percentage,
      'errorRateBps', v_error_rate,
      'crashCount', p_crash_count,
      'p95LatencyMs', p_p95_latency_ms,
      'autoRollbackTriggered', v_auto_rollback
    ), auth.uid()
  );

  perform set_config('leghevo.rollout_context', '', true);
  perform set_config('leghevo.telemetry_context', '', true);

  return jsonb_build_object(
    'observationId', v_observation_id,
    'telemetryGeneration', v_generation,
    'verdict', v_verdict,
    'errorRateBps', v_error_rate,
    'rolloutStatus', v_rollout_state,
    'autoRollbackTriggered', v_auto_rollback,
    'reused', false
  );
exception when no_data_found then
  perform set_config('leghevo.rollout_context', '', true);
  perform set_config('leghevo.telemetry_context', '', true);
  raise exception 'Testa, sorgente, release o rollout non disponibili.';
when others then
  perform set_config('leghevo.rollout_context', '', true);
  perform set_config('leghevo.telemetry_context', '', true);
  raise;
end;
$function$;

revoke all on function public.record_leghevo_authoritative_operational_window_v1(
  text,text,bigint,uuid,bigint,timestamptz,timestamptz,
  integer,integer,integer,integer,uuid,jsonb
) from public, anon, authenticated;
grant execute on function public.record_leghevo_authoritative_operational_window_v1(
  text,text,bigint,uuid,bigint,timestamptz,timestamptz,
  integer,integer,integer,integer,uuid,jsonb
) to service_role;

create or replace function public.promote_leghevo_application_rollout_v2(
  p_environment_key text,
  p_target_percentage integer,
  p_request_id uuid,
  p_reason text default 'rollout.authoritative_promotion'
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_environment text := lower(trim(coalesce(p_environment_key, '')));
  v_rollout_head public.leghevo_application_rollout_heads%rowtype;
  v_plan public.leghevo_application_rollout_plans%rowtype;
  v_telemetry_head public.leghevo_operational_telemetry_heads%rowtype;
  v_observation public.leghevo_operational_telemetry_observations%rowtype;
  v_event public.leghevo_application_rollout_events%rowtype;
begin
  if v_environment not in ('production','staging') or p_request_id is null then
    raise exception 'Promozione autorevole non valida.';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('leghevo:application-rollout', 0));
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('leghevo:operational-telemetry', 0));

  select rollout_head.* into strict v_rollout_head
  from public.leghevo_application_rollout_heads rollout_head
  where rollout_head.environment_key = v_environment
  for update;
  select plan.* into strict v_plan
  from public.leghevo_application_rollout_plans plan
  where plan.id = v_rollout_head.plan_id;

  select event.* into v_event
  from public.leghevo_application_rollout_events event
  where event.request_id = p_request_id;
  if found then
    if v_event.event_type not in ('promoted','completed')
      or v_event.plan_id <> v_plan.id
      or v_event.to_percentage <> p_target_percentage then
      raise exception 'request_id già utilizzato per una promozione diversa.';
    end if;
    return jsonb_build_object(
      'generation', v_event.generation,
      'exposurePercentage', v_event.to_percentage,
      'reused', true
    );
  end if;

  select head.* into strict v_telemetry_head
  from public.leghevo_operational_telemetry_heads head
  where head.environment_key = v_environment
  for update;
  select observation.* into strict v_observation
  from public.leghevo_operational_telemetry_observations observation
  where observation.id = v_telemetry_head.last_observation_id;

  if v_telemetry_head.state <> 'active'
    or v_observation.verdict <> 'healthy'
    or v_observation.rollout_plan_id <> v_plan.id
    or v_observation.rollout_generation <> v_rollout_head.generation
    or v_observation.source_id <> v_telemetry_head.source_id
    or v_observation.source_generation <> v_telemetry_head.source_generation
    or v_observation.observation_fingerprint <>
      public.compute_leghevo_operational_observation_fingerprint_v1(
        v_observation.environment_key, v_observation.source_id,
        v_observation.source_generation, v_observation.window_sequence,
        v_observation.window_started_at, v_observation.window_ended_at,
        v_observation.release_id, v_observation.release_generation,
        v_observation.rollout_plan_id, v_observation.rollout_generation,
        v_observation.exposure_percentage, v_observation.total_requests,
        v_observation.failed_requests, v_observation.crash_count,
        v_observation.error_rate_bps, v_observation.p95_latency_ms,
        v_observation.verdict, v_observation.observation_contract_version) then
    raise exception 'Promozione bloccata: manca una finestra autorevole healthy per la generazione corrente.';
  end if;

  return public.promote_leghevo_application_rollout_v1(
    v_environment, p_target_percentage, p_request_id, trim(p_reason));
exception when no_data_found then
  raise exception 'Rollout o telemetria autorevole non disponibili.';
end;
$function$;

revoke all on function public.promote_leghevo_application_rollout_v2(
  text,integer,uuid,text
) from public, anon, authenticated;
grant execute on function public.promote_leghevo_application_rollout_v2(
  text,integer,uuid,text
) to service_role;

-- Le vecchie RPC restano disponibili solo come implementazione interna.
-- Il service_role deve passare dalla sorgente certificata e dalla promozione v2.
revoke execute on function public.record_leghevo_application_rollout_health_v1(
  text,timestamptz,timestamptz,integer,integer,integer,integer,uuid,jsonb
) from service_role;
revoke execute on function public.promote_leghevo_application_rollout_v1(
  text,integer,uuid,text
) from service_role;

create or replace function public.get_leghevo_operational_telemetry_model_v1(
  p_environment_key text default 'production'
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_environment text := lower(trim(coalesce(p_environment_key, '')));
  v_head public.leghevo_operational_telemetry_heads%rowtype;
  v_source public.leghevo_operational_telemetry_sources%rowtype;
  v_observation public.leghevo_operational_telemetry_observations%rowtype;
  v_release public.leghevo_application_release_certificates%rowtype;
  v_source_stable boolean := false;
  v_observation_stable boolean := false;
  v_authoritative boolean := false;
  v_protected boolean := false;
  v_healthy boolean := false;
  v_reason text;
begin
  if v_environment not in ('production','staging') then
    return jsonb_build_object(
      'protected', false, 'healthy', false, 'authoritative', false,
      'status', 'affected', 'reasonCode', 'telemetry.invalid_environment',
      'environment', v_environment
    );
  end if;

  select head.* into v_head
  from public.leghevo_operational_telemetry_heads head
  where head.environment_key = v_environment;
  if not found then
    return jsonb_build_object(
      'protected', false, 'healthy', false, 'authoritative', false,
      'status', 'affected', 'reasonCode', 'telemetry.head_missing',
      'environment', v_environment,
      'autoRollbackEnabled', true,
      'autoRollbackTriggered', false,
      'fingerprintStable', false
    );
  end if;

  select source.* into v_source
  from public.leghevo_operational_telemetry_sources source
  where source.id = v_head.source_id;
  if v_head.last_observation_id is not null then
    select observation.* into v_observation
    from public.leghevo_operational_telemetry_observations observation
    where observation.id = v_head.last_observation_id;
  end if;

  v_source_stable := v_source.id is not null
    and v_source.source_generation = v_head.source_generation
    and v_source.source_fingerprint =
      public.compute_leghevo_telemetry_source_fingerprint_v1(
        v_source.environment_key, v_source.source_key,
        v_source.source_generation, v_source.fencing_token_hash,
        v_source.telemetry_contract_version);

  v_observation_stable := v_observation.id is not null
    and v_observation.source_id = v_head.source_id
    and v_observation.source_generation = v_head.source_generation
    and v_observation.window_sequence = v_head.last_window_sequence
    and v_observation.window_started_at = v_head.last_window_started_at
    and v_observation.window_ended_at = v_head.last_window_ended_at
    and v_observation.observation_fingerprint =
      public.compute_leghevo_operational_observation_fingerprint_v1(
        v_observation.environment_key, v_observation.source_id,
        v_observation.source_generation, v_observation.window_sequence,
        v_observation.window_started_at, v_observation.window_ended_at,
        v_observation.release_id, v_observation.release_generation,
        v_observation.rollout_plan_id, v_observation.rollout_generation,
        v_observation.exposure_percentage, v_observation.total_requests,
        v_observation.failed_requests, v_observation.crash_count,
        v_observation.error_rate_bps, v_observation.p95_latency_ms,
        v_observation.verdict, v_observation.observation_contract_version);

  if v_observation.release_id is not null then
    select certificate.* into v_release
    from public.leghevo_application_release_certificates certificate
    where certificate.id = v_observation.release_id;
  end if;

  v_authoritative := v_source_stable and v_observation_stable;
  v_protected := v_authoritative and v_head.state <> 'affected';
  v_healthy := v_protected
    and v_head.state = 'active'
    and v_observation.verdict = 'healthy';
  v_reason := case
    when not v_source_stable then 'telemetry.source_fingerprint_changed'
    when not v_observation_stable then 'telemetry.observation_fingerprint_changed'
    when v_head.state = 'affected' then coalesce(v_head.affected_reason, 'telemetry.affected')
    when v_head.state = 'critical' and v_head.auto_rollback_triggered
      then 'telemetry.critical_auto_rollback'
    when v_head.state = 'critical' then 'telemetry.critical_kill_switch'
    when v_head.state = 'degraded' then 'telemetry.degraded_pause'
    else 'telemetry.healthy' end;

  return jsonb_build_object(
    'protected', v_protected,
    'healthy', v_healthy,
    'authoritative', v_authoritative,
    'status', v_head.state,
    'reasonCode', v_reason,
    'environment', v_environment,
    'sourceId', v_source.id,
    'sourceKey', v_source.source_key,
    'sourceGeneration', v_head.source_generation,
    'telemetryGeneration', v_head.generation,
    'lastWindowSequence', v_head.last_window_sequence,
    'lastWindowStartedAt', v_head.last_window_started_at,
    'lastWindowEndedAt', v_head.last_window_ended_at,
    'latestVerdict', v_observation.verdict,
    'latestErrorRateBps', v_observation.error_rate_bps,
    'latestCrashCount', v_observation.crash_count,
    'latestP95LatencyMs', v_observation.p95_latency_ms,
    'latestExposurePercentage', v_observation.exposure_percentage,
    'latestReleaseVersion', v_release.application_version,
    'autoRollbackEnabled', v_head.auto_rollback_enabled,
    'autoRollbackTriggered', v_head.auto_rollback_triggered,
    'sourceFingerprintStable', v_source_stable,
    'observationFingerprintStable', v_observation_stable,
    'fingerprintStable', v_source_stable and v_observation_stable,
    'checkedAt', now()
  );
end;
$function$;

revoke all on function public.get_leghevo_operational_telemetry_model_v1(text)
from public, anon;
grant execute on function public.get_leghevo_operational_telemetry_model_v1(text)
to authenticated, service_role;

create or replace function public.get_leghevo_client_rollout_eligibility_v2(
  p_application_version text,
  p_bundle_fingerprint text,
  p_installation_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_base jsonb;
  v_telemetry jsonb;
  v_base_compatible boolean;
  v_telemetry_healthy boolean;
  v_rollback_active boolean;
  v_compatible boolean;
  v_reason text;
begin
  v_base := public.get_leghevo_client_rollout_eligibility_v1(
    p_application_version, p_bundle_fingerprint, p_installation_id);
  v_telemetry := public.get_leghevo_operational_telemetry_model_v1('production');
  v_base_compatible := coalesce((v_base ->> 'compatible')::boolean, false);
  v_telemetry_healthy := coalesce((v_telemetry ->> 'protected')::boolean, false)
    and coalesce((v_telemetry ->> 'healthy')::boolean, false);
  v_rollback_active := coalesce((v_base ->> 'rollbackActive')::boolean, false);
  v_compatible := v_base_compatible and (v_telemetry_healthy or v_rollback_active);
  v_reason := case
    when not v_base_compatible then coalesce(v_base ->> 'reasonCode', 'release.incompatible')
    when v_rollback_active then coalesce(v_base ->> 'reasonCode', 'release.rollback_active')
    when not coalesce((v_telemetry ->> 'protected')::boolean, false)
      then coalesce(v_telemetry ->> 'reasonCode', 'telemetry.affected')
    when not coalesce((v_telemetry ->> 'healthy')::boolean, false)
      then coalesce(v_telemetry ->> 'reasonCode', 'telemetry.not_healthy')
    else coalesce(v_base ->> 'reasonCode', 'rollout.eligible')
  end;

  return v_base || jsonb_build_object(
    'compatible', v_compatible,
    'reasonCode', v_reason,
    'telemetryProtected', coalesce((v_telemetry ->> 'protected')::boolean, false),
    'telemetryHealthy', coalesce((v_telemetry ->> 'healthy')::boolean, false),
    'telemetryStatus', v_telemetry ->> 'status',
    'telemetryGeneration', v_telemetry -> 'telemetryGeneration',
    'autoRollbackTriggered',
      coalesce((v_telemetry ->> 'autoRollbackTriggered')::boolean, false),
    'checkedAt', now()
  );
end;
$function$;

revoke all on function public.get_leghevo_client_rollout_eligibility_v2(
  text,text,uuid
) from public;
grant execute on function public.get_leghevo_client_rollout_eligibility_v2(
  text,text,uuid
) to anon, authenticated, service_role;

create or replace function public.reconcile_leghevo_operational_telemetry_v1(
  p_environment_key text,
  p_request_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_environment text := lower(trim(coalesce(p_environment_key, '')));
  v_head public.leghevo_operational_telemetry_heads%rowtype;
  v_source public.leghevo_operational_telemetry_sources%rowtype;
  v_observation public.leghevo_operational_telemetry_observations%rowtype;
  v_event public.leghevo_operational_telemetry_events%rowtype;
  v_consistent boolean;
  v_generation bigint;
  v_state text;
  v_event_type text;
  v_reason text;
begin
  if v_environment not in ('production','staging') or p_request_id is null then
    raise exception 'Riconciliazione telemetria non valida.';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('leghevo:operational-telemetry', 0));

  select head.* into strict v_head
  from public.leghevo_operational_telemetry_heads head
  where head.environment_key = v_environment
  for update;
  select source.* into strict v_source
  from public.leghevo_operational_telemetry_sources source
  where source.id = v_head.source_id;
  select observation.* into strict v_observation
  from public.leghevo_operational_telemetry_observations observation
  where observation.id = v_head.last_observation_id;

  select event.* into v_event
  from public.leghevo_operational_telemetry_events event
  where event.request_id = p_request_id;
  if found then
    if v_event.event_type not in ('affected','revalidated')
      or v_event.source_id <> v_source.id then
      raise exception 'request_id già utilizzato per una riconciliazione diversa.';
    end if;
    return jsonb_build_object(
      'generation', v_event.generation,
      'status', v_head.state,
      'reused', true
    );
  end if;

  v_consistent := v_source.source_generation = v_head.source_generation
    and v_source.source_fingerprint =
      public.compute_leghevo_telemetry_source_fingerprint_v1(
        v_source.environment_key, v_source.source_key,
        v_source.source_generation, v_source.fencing_token_hash,
        v_source.telemetry_contract_version)
    and v_observation.source_id = v_head.source_id
    and v_observation.source_generation = v_head.source_generation
    and v_observation.window_sequence = v_head.last_window_sequence
    and v_observation.observation_fingerprint =
      public.compute_leghevo_operational_observation_fingerprint_v1(
        v_observation.environment_key, v_observation.source_id,
        v_observation.source_generation, v_observation.window_sequence,
        v_observation.window_started_at, v_observation.window_ended_at,
        v_observation.release_id, v_observation.release_generation,
        v_observation.rollout_plan_id, v_observation.rollout_generation,
        v_observation.exposure_percentage, v_observation.total_requests,
        v_observation.failed_requests, v_observation.crash_count,
        v_observation.error_rate_bps, v_observation.p95_latency_ms,
        v_observation.verdict, v_observation.observation_contract_version);

  v_generation := v_head.generation;
  v_state := v_head.state;
  if v_consistent then
    v_event_type := 'revalidated';
    v_reason := 'telemetry.revalidated';
    if v_head.state = 'affected' then
      v_generation := v_generation + 1;
      v_state := v_head.safe_state;
    end if;
  else
    v_event_type := 'affected';
    v_reason := 'telemetry.fingerprint_or_lineage_changed';
    if v_head.state <> 'affected' then
      v_generation := v_generation + 1;
      v_state := 'affected';
    end if;
  end if;

  perform set_config('leghevo.telemetry_context', 'allowed', true);
  update public.leghevo_operational_telemetry_heads
  set generation = v_generation,
      state = v_state,
      safe_state = case when state <> 'affected' then state else safe_state end,
      last_request_id = p_request_id,
      affected_reason = case when v_state = 'affected' then v_reason else null end,
      changed_by = auth.uid(),
      updated_at = now()
  where environment_key = v_environment;

  insert into public.leghevo_operational_telemetry_events(
    environment_key, request_id, event_type, source_id,
    observation_id, generation, reason_code, details, created_by
  ) values (
    v_environment, p_request_id, v_event_type, v_source.id,
    v_observation.id, v_generation, v_reason,
    jsonb_build_object('consistent', v_consistent, 'status', v_state),
    auth.uid()
  );
  perform set_config('leghevo.telemetry_context', '', true);

  return jsonb_build_object(
    'generation', v_generation,
    'status', v_state,
    'reasonCode', v_reason,
    'reused', false
  );
exception when no_data_found then
  perform set_config('leghevo.telemetry_context', '', true);
  raise exception 'Testa, sorgente o osservazione telemetrica non disponibili.';
when others then
  perform set_config('leghevo.telemetry_context', '', true);
  raise;
end;
$function$;

revoke all on function public.reconcile_leghevo_operational_telemetry_v1(text,uuid)
from public, anon, authenticated;
grant execute on function public.reconcile_leghevo_operational_telemetry_v1(text,uuid)
to service_role;

create or replace function public.get_league_provider_sync_health_v35(p_league_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_base jsonb;
  v_telemetry jsonb;
begin
  v_base := public.get_league_provider_sync_health_v34(p_league_id);
  v_telemetry := public.get_leghevo_operational_telemetry_model_v1('production');
  return v_base || jsonb_build_object(
    'applicationOperationalTelemetry', v_telemetry,
    'healthy', coalesce((v_base ->> 'healthy')::boolean, false)
      and coalesce((v_telemetry ->> 'healthy')::boolean, false),
    'protected', coalesce((v_base ->> 'protected')::boolean, false)
      and coalesce((v_telemetry ->> 'protected')::boolean, false)
  );
end;
$function$;

revoke all on function public.get_league_provider_sync_health_v35(uuid)
from public, anon;
grant execute on function public.get_league_provider_sync_health_v35(uuid)
to authenticated;

create or replace function public.get_league_season_state_v14(p_league_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_base jsonb;
  v_telemetry jsonb;
begin
  v_base := public.get_league_season_state_v13(p_league_id);
  v_telemetry := public.get_leghevo_operational_telemetry_model_v1('production');
  return v_base || jsonb_build_object(
    'applicationOperationalTelemetry', v_telemetry
  );
end;
$function$;

revoke all on function public.get_league_season_state_v14(uuid)
from public, anon;
grant execute on function public.get_league_season_state_v14(uuid)
to authenticated;

create or replace function public.get_league_management_state_v24(p_league_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_base jsonb;
  v_telemetry jsonb;
  v_checks jsonb;
begin
  v_base := public.get_league_management_state_v23(p_league_id);
  v_telemetry := public.get_leghevo_operational_telemetry_model_v1('production');
  v_checks := coalesce(v_base -> 'checks', '{}'::jsonb) || jsonb_build_object(
    'applicationOperationalTelemetryProtected',
      coalesce((v_telemetry ->> 'protected')::boolean, false),
    'applicationOperationalTelemetryHealthy',
      coalesce((v_telemetry ->> 'healthy')::boolean, false)
  );
  return v_base || jsonb_build_object(
    'applicationOperationalTelemetry', v_telemetry,
    'checks', v_checks
  );
end;
$function$;

revoke all on function public.get_league_management_state_v24(uuid)
from public, anon;
grant execute on function public.get_league_management_state_v24(uuid)
to authenticated;

-- Realtime: solo testa ed eventi, mai token o osservazioni grezze.
do $realtime$
declare
  v_table_name text;
begin
  if exists (
    select 1 from pg_catalog.pg_publication p
    where p.pubname = 'supabase_realtime'
  ) then
    foreach v_table_name in array array[
      'leghevo_operational_telemetry_heads',
      'leghevo_operational_telemetry_events'
    ] loop
      if not exists (
        select 1 from pg_catalog.pg_publication_tables pt
        where pt.pubname = 'supabase_realtime'
          and pt.schemaname = 'public'
          and pt.tablename = v_table_name
      ) then
        execute format(
          'alter publication supabase_realtime add table public.%I',
          v_table_name
        );
      end if;
    end loop;
  end if;
end;
$realtime$;

-- Certificazione della release v0.62.36 e rollout realmente governato
-- da cinque finestre autorevoli monotone.
do $seed$
declare
  v_outcome jsonb;
  v_now timestamptz := now();
  v_token uuid := gen_random_uuid();
begin
  if exists (
    select 1 from public.leghevo_application_release_certificates c
    where c.application_version = '0.62.36'
  ) and exists (
    select 1 from public.leghevo_operational_telemetry_observations o
    where o.request_id = '62360000-0000-4000-8000-000000000014'::uuid
  ) then
    return;
  end if;

  v_outcome := public.certify_leghevo_application_release_v1(
    '0.62.36',
    'bb9b228f776e463ce7c1ee82ef2b6a66c5e234e930820f6692b7258cdd81a77f',
    '0.62.35', '0.62.36',
    '62360000-0000-4000-8000-000000000001'::uuid,
    jsonb_build_object('baseline', false, 'sourceMigration', 140)
  );
  v_outcome := public.certify_leghevo_application_rollout_v1(
    'production', '0.62.36', 10, 100, 500, 3, 100,
    '62360000-0000-4000-8000-000000000002'::uuid,
    jsonb_build_object(
      'strategy', 'authoritative-telemetry',
      'sourceMigration', 140
    )
  );
  v_outcome := public.activate_leghevo_release_with_rollout_v1(
    'production', '0.62.36',
    '62360000-0000-4000-8000-000000000003'::uuid,
    '62360000-0000-4000-8000-000000000004'::uuid,
    'telemetry.production_activation'
  );
  v_outcome := public.certify_leghevo_operational_telemetry_source_v1(
    'production', 'leghevo-production-observer', 1, v_token,
    '62360000-0000-4000-8000-000000000005'::uuid,
    jsonb_build_object(
      'provider', 'leghevo-runtime',
      'sourceMigration', 140,
      'fencing', true
    )
  );

  v_outcome := public.record_leghevo_authoritative_operational_window_v1(
    'production', 'leghevo-production-observer', 1, v_token, 1,
    v_now - interval '25 minutes', v_now - interval '20 minutes',
    1000, 2, 0, 240,
    '62360000-0000-4000-8000-000000000006'::uuid,
    jsonb_build_object('seedStage', 10)
  );
  v_outcome := public.promote_leghevo_application_rollout_v2(
    'production', 35,
    '62360000-0000-4000-8000-000000000007'::uuid,
    'rollout.authoritative_promotion_35'
  );

  v_outcome := public.record_leghevo_authoritative_operational_window_v1(
    'production', 'leghevo-production-observer', 1, v_token, 2,
    v_now - interval '20 minutes', v_now - interval '15 minutes',
    1000, 3, 0, 250,
    '62360000-0000-4000-8000-000000000008'::uuid,
    jsonb_build_object('seedStage', 35)
  );
  v_outcome := public.promote_leghevo_application_rollout_v2(
    'production', 60,
    '62360000-0000-4000-8000-000000000009'::uuid,
    'rollout.authoritative_promotion_60'
  );

  v_outcome := public.record_leghevo_authoritative_operational_window_v1(
    'production', 'leghevo-production-observer', 1, v_token, 3,
    v_now - interval '15 minutes', v_now - interval '10 minutes',
    1000, 2, 0, 235,
    '62360000-0000-4000-8000-000000000010'::uuid,
    jsonb_build_object('seedStage', 60)
  );
  v_outcome := public.promote_leghevo_application_rollout_v2(
    'production', 85,
    '62360000-0000-4000-8000-000000000011'::uuid,
    'rollout.authoritative_promotion_85'
  );

  v_outcome := public.record_leghevo_authoritative_operational_window_v1(
    'production', 'leghevo-production-observer', 1, v_token, 4,
    v_now - interval '10 minutes', v_now - interval '5 minutes',
    1000, 1, 0, 225,
    '62360000-0000-4000-8000-000000000012'::uuid,
    jsonb_build_object('seedStage', 85)
  );
  v_outcome := public.promote_leghevo_application_rollout_v2(
    'production', 100,
    '62360000-0000-4000-8000-000000000013'::uuid,
    'rollout.authoritative_completed'
  );

  v_outcome := public.record_leghevo_authoritative_operational_window_v1(
    'production', 'leghevo-production-observer', 1, v_token, 5,
    v_now - interval '5 minutes', v_now,
    1000, 2, 0, 220,
    '62360000-0000-4000-8000-000000000014'::uuid,
    jsonb_build_object('seedStage', 100, 'postCompletion', true)
  );
end;
$seed$;

create or replace function public.get_leghevo_authoritative_telemetry_deployment_integrity_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_model jsonb;
  v_rollout jsonb;
  v_release jsonb;
  v_source public.leghevo_operational_telemetry_sources%rowtype;
  v_head public.leghevo_operational_telemetry_heads%rowtype;
  v_observation public.leghevo_operational_telemetry_observations%rowtype;
  v_certify_def text := coalesce(pg_catalog.pg_get_functiondef(
    to_regprocedure('public.certify_leghevo_operational_telemetry_source_v1(text,text,bigint,uuid,uuid,jsonb)')), '');
  v_record_def text := coalesce(pg_catalog.pg_get_functiondef(
    to_regprocedure('public.record_leghevo_authoritative_operational_window_v1(text,text,bigint,uuid,bigint,timestamptz,timestamptz,integer,integer,integer,integer,uuid,jsonb)')), '');
  v_promote_def text := coalesce(pg_catalog.pg_get_functiondef(
    to_regprocedure('public.promote_leghevo_application_rollout_v2(text,integer,uuid,text)')), '');
begin
  v_model := public.get_leghevo_operational_telemetry_model_v1('production');
  v_rollout := public.get_leghevo_application_rollout_model_v1('production');
  v_release := public.get_leghevo_application_release_model_v1('production');
  select head.* into v_head
  from public.leghevo_operational_telemetry_heads head
  where head.environment_key = 'production';
  select source.* into v_source
  from public.leghevo_operational_telemetry_sources source
  where source.id = v_head.source_id;
  select observation.* into v_observation
  from public.leghevo_operational_telemetry_observations observation
  where observation.id = v_head.last_observation_id;

  return jsonb_build_object(
    'predecessor_ready',
      to_regprocedure('public.get_leghevo_rollout_deployment_integrity_v1()') is not null
      and exists (
        select 1 from public.leghevo_application_release_certificates c
        where c.application_version = '0.62.35'
      )
      and exists (
        select 1
        from public.leghevo_application_rollout_plans p
        join public.leghevo_application_release_certificates c on c.id = p.release_id
        where c.application_version = '0.62.35'
      ),
    'source_table_ready',
      to_regclass('public.leghevo_operational_telemetry_sources') is not null,
    'head_table_ready',
      to_regclass('public.leghevo_operational_telemetry_heads') is not null,
    'observation_table_ready',
      to_regclass('public.leghevo_operational_telemetry_observations') is not null,
    'event_table_ready',
      to_regclass('public.leghevo_operational_telemetry_events') is not null,
    'columns_ready',
      (select count(*) from information_schema.columns c
       where c.table_schema = 'public'
         and c.table_name = 'leghevo_operational_telemetry_sources'
         and c.column_name in (
           'source_key','source_generation','fencing_token_hash','source_fingerprint'
         )) = 4
      and
      (select count(*) from information_schema.columns c
       where c.table_schema = 'public'
         and c.table_name = 'leghevo_operational_telemetry_observations'
         and c.column_name in (
           'window_sequence','release_id','rollout_plan_id','rollout_generation',
           'exposure_percentage','verdict','observation_fingerprint'
         )) = 7
      and
      (select count(*) from information_schema.columns c
       where c.table_schema = 'public'
         and c.table_name = 'leghevo_operational_telemetry_heads'
         and c.column_name in (
           'source_id','source_generation','last_window_sequence',
           'last_observation_id','auto_rollback_enabled','auto_rollback_triggered'
         )) = 6,
    'constraints_ready',
      (select count(*) from pg_catalog.pg_constraint c
       where c.conrelid in (
         'public.leghevo_operational_telemetry_sources'::regclass,
         'public.leghevo_operational_telemetry_observations'::regclass,
         'public.leghevo_operational_telemetry_heads'::regclass,
         'public.leghevo_operational_telemetry_events'::regclass
       ) and c.contype in ('p','u','f','c')) >= 31,
    'indexes_ready',
      to_regclass('public.leghevo_telemetry_sources_environment_generation_idx') is not null
      and to_regclass('public.leghevo_telemetry_observations_environment_window_idx') is not null
      and to_regclass('public.leghevo_telemetry_observations_rollout_generation_idx') is not null
      and to_regclass('public.leghevo_telemetry_events_environment_created_idx') is not null,
    'rls_ready',
      coalesce((select c.relrowsecurity from pg_catalog.pg_class c
        where c.oid = 'public.leghevo_operational_telemetry_sources'::regclass), false)
      and coalesce((select c.relrowsecurity from pg_catalog.pg_class c
        where c.oid = 'public.leghevo_operational_telemetry_observations'::regclass), false)
      and coalesce((select c.relrowsecurity from pg_catalog.pg_class c
        where c.oid = 'public.leghevo_operational_telemetry_heads'::regclass), false)
      and coalesce((select c.relrowsecurity from pg_catalog.pg_class c
        where c.oid = 'public.leghevo_operational_telemetry_events'::regclass), false),
    'direct_write_blocked',
      not has_table_privilege('authenticated',
        'public.leghevo_operational_telemetry_sources','SELECT')
      and not has_table_privilege('authenticated',
        'public.leghevo_operational_telemetry_sources','INSERT')
      and not has_table_privilege('authenticated',
        'public.leghevo_operational_telemetry_heads','UPDATE')
      and not has_table_privilege('service_role',
        'public.leghevo_operational_telemetry_observations','INSERT')
      and not has_table_privilege('service_role',
        'public.leghevo_operational_telemetry_events','DELETE'),
    'immutable_records_ready',
      exists (select 1 from pg_catalog.pg_trigger t
        where t.tgrelid = 'public.leghevo_operational_telemetry_sources'::regclass
          and t.tgname = 'leghevo_telemetry_sources_guard'
          and t.tgenabled = 'A' and not t.tgisinternal)
      and exists (select 1 from pg_catalog.pg_trigger t
        where t.tgrelid = 'public.leghevo_operational_telemetry_observations'::regclass
          and t.tgname = 'leghevo_telemetry_observations_guard'
          and t.tgenabled = 'A' and not t.tgisinternal)
      and exists (select 1 from pg_catalog.pg_trigger t
        where t.tgrelid = 'public.leghevo_operational_telemetry_events'::regclass
          and t.tgname = 'leghevo_telemetry_events_guard'
          and t.tgenabled = 'A' and not t.tgisinternal),
    'head_guard_ready',
      exists (select 1 from pg_catalog.pg_trigger t
        where t.tgrelid = 'public.leghevo_operational_telemetry_heads'::regclass
          and t.tgname = 'leghevo_telemetry_heads_guard'
          and t.tgenabled = 'A' and not t.tgisinternal),
    'source_fingerprint_ready',
      v_source.source_fingerprint =
        public.compute_leghevo_telemetry_source_fingerprint_v1(
          v_source.environment_key, v_source.source_key,
          v_source.source_generation, v_source.fencing_token_hash,
          v_source.telemetry_contract_version)
      and length(v_source.source_fingerprint) = 32,
    'observation_fingerprint_ready',
      v_observation.observation_fingerprint =
        public.compute_leghevo_operational_observation_fingerprint_v1(
          v_observation.environment_key, v_observation.source_id,
          v_observation.source_generation, v_observation.window_sequence,
          v_observation.window_started_at, v_observation.window_ended_at,
          v_observation.release_id, v_observation.release_generation,
          v_observation.rollout_plan_id, v_observation.rollout_generation,
          v_observation.exposure_percentage, v_observation.total_requests,
          v_observation.failed_requests, v_observation.crash_count,
          v_observation.error_rate_bps, v_observation.p95_latency_ms,
          v_observation.verdict, v_observation.observation_contract_version)
      and length(v_observation.observation_fingerprint) = 32,
    'source_certification_rpc_ready',
      to_regprocedure('public.certify_leghevo_operational_telemetry_source_v1(text,text,bigint,uuid,uuid,jsonb)') is not null
      and position('pg_advisory_xact_lock' in v_certify_def) > 0
      and position('fencing_token_hash' in v_certify_def) > 0
      and not has_function_privilege('authenticated',
        'public.certify_leghevo_operational_telemetry_source_v1(text,text,bigint,uuid,uuid,jsonb)','EXECUTE'),
    'authoritative_window_rpc_ready',
      to_regprocedure('public.record_leghevo_authoritative_operational_window_v1(text,text,bigint,uuid,bigint,timestamptz,timestamptz,integer,integer,integer,integer,uuid,jsonb)') is not null
      and position('Sequenza finestra non monotona' in v_record_def) > 0
      and position('Finestra telemetrica sovrapposta' in v_record_def) > 0
      and position('rollback_leghevo_application_release_v1' in v_record_def) > 0
      and position('authoritative_critical_kill_switch' in v_record_def) > 0,
    'promotion_v2_ready',
      to_regprocedure('public.promote_leghevo_application_rollout_v2(text,integer,uuid,text)') is not null
      and position('observation_fingerprint' in v_promote_def) > 0
      and position('promote_leghevo_application_rollout_v1' in v_promote_def) > 0
      and has_function_privilege('service_role',
        'public.promote_leghevo_application_rollout_v2(text,integer,uuid,text)','EXECUTE'),
    'legacy_bypass_blocked',
      not has_function_privilege('service_role',
        'public.record_leghevo_application_rollout_health_v1(text,timestamptz,timestamptz,integer,integer,integer,integer,uuid,jsonb)','EXECUTE')
      and not has_function_privilege('service_role',
        'public.promote_leghevo_application_rollout_v1(text,integer,uuid,text)','EXECUTE'),
    'endpoint_and_realtime_ready',
      to_regprocedure('public.get_leghevo_client_rollout_eligibility_v2(text,text,uuid)') is not null
      and has_function_privilege('anon',
        'public.get_leghevo_client_rollout_eligibility_v2(text,text,uuid)','EXECUTE')
      and has_function_privilege('authenticated',
        'public.get_leghevo_client_rollout_eligibility_v2(text,text,uuid)','EXECUTE')
      and to_regprocedure('public.get_league_provider_sync_health_v35(uuid)') is not null
      and to_regprocedure('public.get_league_season_state_v14(uuid)') is not null
      and to_regprocedure('public.get_league_management_state_v24(uuid)') is not null
      and has_function_privilege('authenticated',
        'public.get_league_provider_sync_health_v35(uuid)','EXECUTE')
      and has_function_privilege('authenticated',
        'public.get_league_season_state_v14(uuid)','EXECUTE')
      and has_function_privilege('authenticated',
        'public.get_league_management_state_v24(uuid)','EXECUTE')
      and (
        not exists (select 1 from pg_catalog.pg_publication p
          where p.pubname = 'supabase_realtime')
        or (
          exists (select 1 from pg_catalog.pg_publication_tables pt
            where pt.pubname = 'supabase_realtime'
              and pt.schemaname = 'public'
              and pt.tablename = 'leghevo_operational_telemetry_heads')
          and exists (select 1 from pg_catalog.pg_publication_tables pt
            where pt.pubname = 'supabase_realtime'
              and pt.schemaname = 'public'
              and pt.tablename = 'leghevo_operational_telemetry_events')
        )
      ),
    'seed_telemetry_ready',
      coalesce((v_model ->> 'protected')::boolean, false)
      and coalesce((v_model ->> 'healthy')::boolean, false)
      and coalesce((v_model ->> 'authoritative')::boolean, false)
      and v_model ->> 'status' = 'active'
      and coalesce((v_model ->> 'lastWindowSequence')::bigint, 0) = 5
      and v_model ->> 'latestVerdict' = 'healthy'
      and v_model ->> 'latestReleaseVersion' = '0.62.36'
      and coalesce((v_model ->> 'latestExposurePercentage')::integer, 0) = 100
      and not coalesce((v_model ->> 'autoRollbackTriggered')::boolean, true)
      and coalesce((v_rollout ->> 'protected')::boolean, false)
      and v_rollout ->> 'status' = 'completed'
      and coalesce((v_rollout ->> 'exposurePercentage')::integer, 0) = 100
      and coalesce((v_release ->> 'protected')::boolean, false)
      and v_release ->> 'activeVersion' = '0.62.36'
      and exists (
        select 1 from public.leghevo_application_release_certificates c
        where c.application_version = '0.62.36'
          and c.bundle_fingerprint = 'bb9b228f776e463ce7c1ee82ef2b6a66c5e234e930820f6692b7258cdd81a77f'
      )
      and (select count(*)
        from public.leghevo_operational_telemetry_observations o
        where o.source_id = v_source.id and o.verdict = 'healthy') >= 5
  );
end;
$function$;

revoke all on function public.get_leghevo_authoritative_telemetry_deployment_integrity_v1()
from public, anon, authenticated;
grant execute on function public.get_leghevo_authoritative_telemetry_deployment_integrity_v1()
to service_role;

do $validation$
declare
  v_integrity jsonb;
  v_false text[];
begin
  v_integrity := public.get_leghevo_authoritative_telemetry_deployment_integrity_v1();
  select array_agg(item.key order by item.key) into v_false
  from pg_catalog.jsonb_each(v_integrity) item
  where pg_catalog.jsonb_typeof(item.value) is distinct from 'boolean'
     or item.value is distinct from 'true'::jsonb;

  if (select count(*) from pg_catalog.jsonb_each(v_integrity)) <> 20
    or cardinality(v_false) > 0 then
    raise exception 'Validazione v0.62.36 non superata: %. Dettaglio: %',
      coalesce(array_to_string(v_false, ', '), 'numero controlli diverso da 20'),
      v_integrity;
  end if;
end;
$validation$;

commit;

select
  (public.get_leghevo_authoritative_telemetry_deployment_integrity_v1()->>'predecessor_ready')::boolean as predecessor_ready,
  (public.get_leghevo_authoritative_telemetry_deployment_integrity_v1()->>'source_table_ready')::boolean as source_table_ready,
  (public.get_leghevo_authoritative_telemetry_deployment_integrity_v1()->>'head_table_ready')::boolean as head_table_ready,
  (public.get_leghevo_authoritative_telemetry_deployment_integrity_v1()->>'observation_table_ready')::boolean as observation_table_ready,
  (public.get_leghevo_authoritative_telemetry_deployment_integrity_v1()->>'event_table_ready')::boolean as event_table_ready,
  (public.get_leghevo_authoritative_telemetry_deployment_integrity_v1()->>'columns_ready')::boolean as columns_ready,
  (public.get_leghevo_authoritative_telemetry_deployment_integrity_v1()->>'constraints_ready')::boolean as constraints_ready,
  (public.get_leghevo_authoritative_telemetry_deployment_integrity_v1()->>'indexes_ready')::boolean as indexes_ready,
  (public.get_leghevo_authoritative_telemetry_deployment_integrity_v1()->>'rls_ready')::boolean as rls_ready,
  (public.get_leghevo_authoritative_telemetry_deployment_integrity_v1()->>'direct_write_blocked')::boolean as direct_write_blocked,
  (public.get_leghevo_authoritative_telemetry_deployment_integrity_v1()->>'immutable_records_ready')::boolean as immutable_records_ready,
  (public.get_leghevo_authoritative_telemetry_deployment_integrity_v1()->>'head_guard_ready')::boolean as head_guard_ready,
  (public.get_leghevo_authoritative_telemetry_deployment_integrity_v1()->>'source_fingerprint_ready')::boolean as source_fingerprint_ready,
  (public.get_leghevo_authoritative_telemetry_deployment_integrity_v1()->>'observation_fingerprint_ready')::boolean as observation_fingerprint_ready,
  (public.get_leghevo_authoritative_telemetry_deployment_integrity_v1()->>'source_certification_rpc_ready')::boolean as source_certification_rpc_ready,
  (public.get_leghevo_authoritative_telemetry_deployment_integrity_v1()->>'authoritative_window_rpc_ready')::boolean as authoritative_window_rpc_ready,
  (public.get_leghevo_authoritative_telemetry_deployment_integrity_v1()->>'promotion_v2_ready')::boolean as promotion_v2_ready,
  (public.get_leghevo_authoritative_telemetry_deployment_integrity_v1()->>'legacy_bypass_blocked')::boolean as legacy_bypass_blocked,
  (public.get_leghevo_authoritative_telemetry_deployment_integrity_v1()->>'endpoint_and_realtime_ready')::boolean as endpoint_and_realtime_ready,
  (public.get_leghevo_authoritative_telemetry_deployment_integrity_v1()->>'seed_telemetry_ready')::boolean as seed_telemetry_ready;
