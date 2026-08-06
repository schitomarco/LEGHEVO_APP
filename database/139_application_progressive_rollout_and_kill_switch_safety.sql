-- LEGHEVO v0.62.35
-- Rollout progressivo certificato, promozione controllata e kill switch.
-- Correzione pre-validazione v2: CASE del comando rollout reso non ambiguo.
-- Eseguire una sola volta nel SQL Editor di Supabase.

begin;

-- Preflight: la v0.62.34 deve essere completa e ancora coerente prima di
-- estendere il contratto di rilascio al rollout operativo.
do $preflight$
declare
  v_previous jsonb;
  v_false text[];
begin
  if to_regprocedure('public.get_leghevo_release_deployment_integrity_v1()') is null
    or to_regprocedure('public.certify_leghevo_application_release_v1(text,text,text,text,uuid,jsonb)') is null
    or to_regprocedure('public.activate_leghevo_application_release_v1(text,text,uuid,text)') is null
    or to_regprocedure('public.get_leghevo_client_compatibility_v1(text,text)') is null then
    raise exception 'Preflight v0.62.35 non superato: installare e validare prima la v0.62.34.';
  end if;

  v_previous := public.get_leghevo_release_deployment_integrity_v1();
  select array_agg(item.key order by item.key)
  into v_false
  from pg_catalog.jsonb_each(v_previous) item
  where pg_catalog.jsonb_typeof(item.value) is distinct from 'boolean'
     or item.value is distinct from 'true'::jsonb;

  if (select count(*) from pg_catalog.jsonb_each(v_previous)) <> 20
    or cardinality(v_false) > 0 then
    raise exception
      'Preflight v0.62.35 non superato: v0.62.34 non integra (%). Dettaglio: %',
      coalesce(array_to_string(v_false, ', '), 'numero controlli diverso da 20'),
      v_previous;
  end if;
end;
$preflight$;

create or replace function public.compute_leghevo_rollout_plan_fingerprint_v1(
  p_release_id uuid,
  p_environment_key text,
  p_initial_percentage integer,
  p_max_percentage integer,
  p_error_rate_bps_threshold integer,
  p_crash_count_threshold integer,
  p_min_observations integer,
  p_rollout_contract_version integer
)
returns text
language sql
immutable
strict
set search_path = ''
as $function$
  select pg_catalog.md5(pg_catalog.concat_ws('|',
    p_release_id::text,
    lower(trim(p_environment_key)),
    p_initial_percentage::text,
    p_max_percentage::text,
    p_error_rate_bps_threshold::text,
    p_crash_count_threshold::text,
    p_min_observations::text,
    p_rollout_contract_version::text
  ));
$function$;

revoke all on function public.compute_leghevo_rollout_plan_fingerprint_v1(
  uuid,text,integer,integer,integer,integer,integer,integer
) from public, anon, authenticated;
grant execute on function public.compute_leghevo_rollout_plan_fingerprint_v1(
  uuid,text,integer,integer,integer,integer,integer,integer
) to service_role;

create table if not exists public.leghevo_application_rollout_plans (
  id uuid primary key default gen_random_uuid(),
  environment_key text not null,
  release_id uuid not null references
    public.leghevo_application_release_certificates(id),
  rollout_contract_version integer not null default 1,
  initial_percentage integer not null,
  max_percentage integer not null default 100,
  error_rate_bps_threshold integer not null default 500,
  crash_count_threshold integer not null default 3,
  min_observations integer not null default 100,
  plan_fingerprint text not null unique,
  certified_at timestamptz not null default now(),
  certified_by uuid null,
  metadata jsonb not null default '{}'::jsonb,
  constraint leghevo_rollout_plan_environment_check
    check (environment_key in ('production','staging')),
  constraint leghevo_rollout_plan_contract_check
    check (rollout_contract_version >= 1),
  constraint leghevo_rollout_plan_percentage_check
    check (
      initial_percentage between 1 and 100
      and max_percentage between initial_percentage and 100
    ),
  constraint leghevo_rollout_plan_error_threshold_check
    check (error_rate_bps_threshold between 0 and 10000),
  constraint leghevo_rollout_plan_crash_threshold_check
    check (crash_count_threshold between 0 and 100000),
  constraint leghevo_rollout_plan_observations_check
    check (min_observations >= 1),
  constraint leghevo_rollout_plan_fingerprint_check
    check (plan_fingerprint ~ '^[0-9a-f]{32}$'),
  constraint leghevo_rollout_plan_metadata_check
    check (jsonb_typeof(metadata) = 'object'),
  constraint leghevo_rollout_plan_release_unique
    unique (environment_key, release_id)
);

create table if not exists public.leghevo_application_rollout_heads (
  environment_key text primary key,
  plan_id uuid not null references public.leghevo_application_rollout_plans(id),
  generation bigint not null default 1,
  state text not null default 'active',
  safe_state text not null default 'active',
  stage text not null default 'pilot',
  exposure_percentage integer not null,
  safe_exposure_percentage integer not null,
  kill_switch_active boolean not null default false,
  started_at timestamptz not null default now(),
  promoted_at timestamptz not null default now(),
  changed_by uuid null,
  last_request_id uuid not null unique,
  affected_reason text null,
  updated_at timestamptz not null default now(),
  constraint leghevo_rollout_head_environment_check
    check (environment_key in ('production','staging')),
  constraint leghevo_rollout_head_generation_check check (generation >= 1),
  constraint leghevo_rollout_head_state_check
    check (state in ('active','paused','killed','completed','affected')),
  constraint leghevo_rollout_head_safe_state_check
    check (safe_state in ('active','paused','killed','completed')),
  constraint leghevo_rollout_head_stage_check
    check (stage in ('pilot','canary','general','completed')),
  constraint leghevo_rollout_head_exposure_check
    check (
      exposure_percentage between 0 and 100
      and safe_exposure_percentage between 0 and 100
    ),
  constraint leghevo_rollout_head_state_consistency_check
    check (state = 'affected' or state = safe_state),
  constraint leghevo_rollout_head_kill_consistency_check
    check (
      (state in ('paused','killed','affected') and kill_switch_active)
      or (state in ('active','completed') and not kill_switch_active)
    ),
  constraint leghevo_rollout_head_completed_check
    check (state <> 'completed' or exposure_percentage = 100),
  constraint leghevo_rollout_head_affected_reason_check
    check (
      (state = 'affected' and char_length(trim(affected_reason)) >= 8)
      or (state <> 'affected' and affected_reason is null)
    )
);

create table if not exists public.leghevo_application_rollout_events (
  id bigint generated by default as identity primary key,
  environment_key text not null,
  request_id uuid not null unique,
  event_type text not null,
  plan_id uuid not null references public.leghevo_application_rollout_plans(id),
  generation bigint not null,
  from_percentage integer null,
  to_percentage integer not null,
  reason_code text not null,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  created_by uuid null,
  constraint leghevo_rollout_event_environment_check
    check (environment_key in ('production','staging')),
  constraint leghevo_rollout_event_type_check
    check (event_type in (
      'certified','started','promoted','paused','resumed','killed',
      'completed','health_accepted','health_rejected','affected','revalidated'
    )),
  constraint leghevo_rollout_event_generation_check check (generation >= 0),
  constraint leghevo_rollout_event_percentage_check
    check (
      (from_percentage is null or from_percentage between 0 and 100)
      and to_percentage between 0 and 100
    ),
  constraint leghevo_rollout_event_reason_check
    check (char_length(trim(reason_code)) between 3 and 140),
  constraint leghevo_rollout_event_details_check
    check (jsonb_typeof(details) = 'object')
);

create table if not exists public.leghevo_application_rollout_health_reports (
  id bigint generated by default as identity primary key,
  environment_key text not null,
  request_id uuid not null unique,
  plan_id uuid not null references public.leghevo_application_rollout_plans(id),
  generation bigint not null,
  window_started_at timestamptz not null,
  window_ended_at timestamptz not null,
  total_requests integer not null,
  failed_requests integer not null,
  crash_count integer not null,
  error_rate_bps integer not null,
  p95_latency_ms integer null,
  verdict text not null,
  details jsonb not null default '{}'::jsonb,
  recorded_at timestamptz not null default now(),
  recorded_by uuid null,
  constraint leghevo_rollout_health_environment_check
    check (environment_key in ('production','staging')),
  constraint leghevo_rollout_health_generation_check check (generation >= 1),
  constraint leghevo_rollout_health_window_check
    check (window_ended_at > window_started_at),
  constraint leghevo_rollout_health_counts_check
    check (
      total_requests >= 0
      and failed_requests between 0 and total_requests
      and crash_count >= 0
      and error_rate_bps between 0 and 10000
      and (p95_latency_ms is null or p95_latency_ms >= 0)
    ),
  constraint leghevo_rollout_health_verdict_check
    check (verdict in ('healthy','unhealthy')),
  constraint leghevo_rollout_health_details_check
    check (jsonb_typeof(details) = 'object')
);

create index if not exists leghevo_rollout_plans_release_idx
on public.leghevo_application_rollout_plans(environment_key, release_id);
create index if not exists leghevo_rollout_events_environment_created_idx
on public.leghevo_application_rollout_events(environment_key, created_at desc);
create index if not exists leghevo_rollout_events_plan_generation_idx
on public.leghevo_application_rollout_events(plan_id, generation desc);
create index if not exists leghevo_rollout_health_plan_generation_idx
on public.leghevo_application_rollout_health_reports(plan_id, generation desc, recorded_at desc);

alter table public.leghevo_application_rollout_plans enable row level security;
alter table public.leghevo_application_rollout_heads enable row level security;
alter table public.leghevo_application_rollout_events enable row level security;
alter table public.leghevo_application_rollout_health_reports enable row level security;

drop policy if exists leghevo_rollout_plans_read on public.leghevo_application_rollout_plans;
create policy leghevo_rollout_plans_read
on public.leghevo_application_rollout_plans for select
to authenticated using (true);
drop policy if exists leghevo_rollout_heads_read on public.leghevo_application_rollout_heads;
create policy leghevo_rollout_heads_read
on public.leghevo_application_rollout_heads for select
to authenticated using (true);
drop policy if exists leghevo_rollout_events_read on public.leghevo_application_rollout_events;
create policy leghevo_rollout_events_read
on public.leghevo_application_rollout_events for select
to authenticated using (true);

revoke all on table public.leghevo_application_rollout_plans
from public, anon, authenticated, service_role;
revoke all on table public.leghevo_application_rollout_heads
from public, anon, authenticated, service_role;
revoke all on table public.leghevo_application_rollout_events
from public, anon, authenticated, service_role;
revoke all on table public.leghevo_application_rollout_health_reports
from public, anon, authenticated, service_role;
grant select on table public.leghevo_application_rollout_plans,
  public.leghevo_application_rollout_heads,
  public.leghevo_application_rollout_events
to authenticated, service_role;
grant select on table public.leghevo_application_rollout_health_reports
to service_role;

create or replace function public.guard_leghevo_rollout_plan_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if tg_op = 'INSERT'
    and coalesce(current_setting('leghevo.rollout_context', true), '') = 'allowed' then
    return new;
  end if;
  raise exception 'Piano rollout protetto e immutabile: modifica diretta non consentita.';
end;
$function$;

create or replace function public.guard_leghevo_rollout_head_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if tg_op in ('INSERT','UPDATE')
    and coalesce(current_setting('leghevo.rollout_context', true), '') = 'allowed' then
    return new;
  end if;
  raise exception 'Testa rollout protetta: modifica diretta non consentita.';
end;
$function$;

create or replace function public.guard_leghevo_rollout_event_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if tg_op = 'INSERT'
    and coalesce(current_setting('leghevo.rollout_context', true), '') = 'allowed' then
    return new;
  end if;
  raise exception 'Evento rollout append-only: modifica diretta non consentita.';
end;
$function$;

create or replace function public.guard_leghevo_rollout_health_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if tg_op = 'INSERT'
    and coalesce(current_setting('leghevo.rollout_context', true), '') = 'allowed' then
    return new;
  end if;
  raise exception 'Report salute rollout append-only: modifica diretta non consentita.';
end;
$function$;

drop trigger if exists leghevo_rollout_plans_guard
on public.leghevo_application_rollout_plans;
create trigger leghevo_rollout_plans_guard
before insert or update or delete on public.leghevo_application_rollout_plans
for each row execute function public.guard_leghevo_rollout_plan_v1();
alter table public.leghevo_application_rollout_plans
  enable always trigger leghevo_rollout_plans_guard;

drop trigger if exists leghevo_rollout_heads_guard
on public.leghevo_application_rollout_heads;
create trigger leghevo_rollout_heads_guard
before insert or update or delete on public.leghevo_application_rollout_heads
for each row execute function public.guard_leghevo_rollout_head_v1();
alter table public.leghevo_application_rollout_heads
  enable always trigger leghevo_rollout_heads_guard;

drop trigger if exists leghevo_rollout_events_guard
on public.leghevo_application_rollout_events;
create trigger leghevo_rollout_events_guard
before insert or update or delete on public.leghevo_application_rollout_events
for each row execute function public.guard_leghevo_rollout_event_v1();
alter table public.leghevo_application_rollout_events
  enable always trigger leghevo_rollout_events_guard;

drop trigger if exists leghevo_rollout_health_guard
on public.leghevo_application_rollout_health_reports;
create trigger leghevo_rollout_health_guard
before insert or update or delete on public.leghevo_application_rollout_health_reports
for each row execute function public.guard_leghevo_rollout_health_v1();
alter table public.leghevo_application_rollout_health_reports
  enable always trigger leghevo_rollout_health_guard;

revoke all on function public.guard_leghevo_rollout_plan_v1()
from public, anon, authenticated, service_role;
revoke all on function public.guard_leghevo_rollout_head_v1()
from public, anon, authenticated, service_role;
revoke all on function public.guard_leghevo_rollout_event_v1()
from public, anon, authenticated, service_role;
revoke all on function public.guard_leghevo_rollout_health_v1()
from public, anon, authenticated, service_role;

create or replace function public.certify_leghevo_application_rollout_v1(
  p_environment_key text,
  p_application_version text,
  p_initial_percentage integer,
  p_max_percentage integer,
  p_error_rate_bps_threshold integer,
  p_crash_count_threshold integer,
  p_min_observations integer,
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
  v_release public.leghevo_application_release_certificates%rowtype;
  v_integrity jsonb;
  v_fingerprint text;
  v_existing public.leghevo_application_rollout_plans%rowtype;
  v_event public.leghevo_application_rollout_events%rowtype;
  v_plan_id uuid;
begin
  if v_environment not in ('production','staging') then
    raise exception 'Ambiente rollout non valido.';
  end if;
  if p_request_id is null then
    raise exception 'request_id obbligatorio per certificare il rollout.';
  end if;
  if p_initial_percentage not between 1 and 100
    or p_max_percentage not between p_initial_percentage and 100
    or p_error_rate_bps_threshold not between 0 and 10000
    or p_crash_count_threshold < 0
    or p_min_observations < 1 then
    raise exception 'Parametri del piano rollout non validi.';
  end if;
  if jsonb_typeof(coalesce(p_metadata, '{}'::jsonb)) <> 'object' then
    raise exception 'Metadata rollout non validi.';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('leghevo:application-release', 0));
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('leghevo:application-rollout', 0));

  select certificate.* into strict v_release
  from public.leghevo_application_release_certificates certificate
  where certificate.application_version = trim(p_application_version);

  v_integrity := public.get_leghevo_application_integrity_model_v1();
  if not coalesce((v_integrity ->> 'protected')::boolean, false)
    or v_release.schema_fingerprint <> lower(coalesce(v_integrity ->> 'schemaFingerprint', ''))
    or v_release.contract_fingerprint <>
      public.compute_leghevo_release_contract_fingerprint_v1(
        v_release.application_version, v_release.bundle_fingerprint,
        v_release.schema_fingerprint, v_release.min_supported_client_version,
        v_release.max_supported_client_version, v_release.release_contract_version) then
    raise exception 'Release % non compatibile con il sigillo applicativo.', p_application_version;
  end if;

  select event.* into v_event
  from public.leghevo_application_rollout_events event
  where event.request_id = p_request_id;
  if found then
    select plan.* into strict v_existing
    from public.leghevo_application_rollout_plans plan
    where plan.id = v_event.plan_id;
    if v_event.event_type <> 'certified'
      or v_existing.environment_key <> v_environment
      or v_existing.release_id <> v_release.id
      or v_existing.initial_percentage <> p_initial_percentage
      or v_existing.max_percentage <> p_max_percentage
      or v_existing.error_rate_bps_threshold <> p_error_rate_bps_threshold
      or v_existing.crash_count_threshold <> p_crash_count_threshold
      or v_existing.min_observations <> p_min_observations
      or v_existing.metadata <> coalesce(p_metadata, '{}'::jsonb) then
      raise exception 'request_id già utilizzato per un piano rollout diverso.';
    end if;
    return jsonb_build_object('planId', v_existing.id, 'reused', true);
  end if;

  v_fingerprint := public.compute_leghevo_rollout_plan_fingerprint_v1(
    v_release.id, v_environment, p_initial_percentage, p_max_percentage,
    p_error_rate_bps_threshold, p_crash_count_threshold,
    p_min_observations, 1);

  select plan.* into v_existing
  from public.leghevo_application_rollout_plans plan
  where plan.environment_key = v_environment
    and plan.release_id = v_release.id;
  if found then
    if v_existing.plan_fingerprint <> v_fingerprint
      or v_existing.metadata <> coalesce(p_metadata, '{}'::jsonb) then
      raise exception 'La release possiede già un piano rollout differente e immutabile.';
    end if;
    v_plan_id := v_existing.id;
  else
    perform set_config('leghevo.rollout_context', 'allowed', true);
    insert into public.leghevo_application_rollout_plans(
      environment_key, release_id, rollout_contract_version,
      initial_percentage, max_percentage, error_rate_bps_threshold,
      crash_count_threshold, min_observations, plan_fingerprint,
      certified_by, metadata
    ) values (
      v_environment, v_release.id, 1,
      p_initial_percentage, p_max_percentage, p_error_rate_bps_threshold,
      p_crash_count_threshold, p_min_observations, v_fingerprint,
      auth.uid(), coalesce(p_metadata, '{}'::jsonb)
    ) returning id into v_plan_id;
    perform set_config('leghevo.rollout_context', '', true);
  end if;

  perform set_config('leghevo.rollout_context', 'allowed', true);
  insert into public.leghevo_application_rollout_events(
    environment_key, request_id, event_type, plan_id, generation,
    from_percentage, to_percentage, reason_code, details, created_by
  ) values (
    v_environment, p_request_id, 'certified', v_plan_id, 0,
    null, p_initial_percentage, 'rollout.certified',
    jsonb_build_object('applicationVersion', v_release.application_version,
      'planFingerprint', v_fingerprint), auth.uid()
  );
  perform set_config('leghevo.rollout_context', '', true);

  return jsonb_build_object('planId', v_plan_id,
    'planFingerprint', v_fingerprint, 'reused', false);
exception when no_data_found then
  perform set_config('leghevo.rollout_context', '', true);
  raise exception 'Release % non certificata.', p_application_version;
when others then
  perform set_config('leghevo.rollout_context', '', true);
  raise;
end;
$function$;

revoke all on function public.certify_leghevo_application_rollout_v1(
  text,text,integer,integer,integer,integer,integer,uuid,jsonb
) from public, anon, authenticated;
grant execute on function public.certify_leghevo_application_rollout_v1(
  text,text,integer,integer,integer,integer,integer,uuid,jsonb
) to service_role;

create or replace function public.start_leghevo_application_rollout_v1(
  p_environment_key text,
  p_application_version text,
  p_request_id uuid,
  p_reason text default 'rollout.started'
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_environment text := lower(trim(coalesce(p_environment_key, '')));
  v_release public.leghevo_application_release_certificates%rowtype;
  v_release_head public.leghevo_application_release_heads%rowtype;
  v_plan public.leghevo_application_rollout_plans%rowtype;
  v_head public.leghevo_application_rollout_heads%rowtype;
  v_event public.leghevo_application_rollout_events%rowtype;
  v_state text;
  v_stage text;
begin
  if v_environment not in ('production','staging') or p_request_id is null
    or char_length(trim(coalesce(p_reason,''))) < 3 then
    raise exception 'Parametri di avvio rollout non validi.';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('leghevo:application-release', 0));
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('leghevo:application-rollout', 0));

  select certificate.* into strict v_release
  from public.leghevo_application_release_certificates certificate
  where certificate.application_version = trim(p_application_version);
  select release_head.* into strict v_release_head
  from public.leghevo_application_release_heads release_head
  where release_head.environment_key = v_environment
  for update;
  if v_release_head.active_release_id <> v_release.id
    or v_release_head.state = 'affected' then
    raise exception 'Rollout bloccato: la release richiesta non è la testa attiva integra.';
  end if;
  select plan.* into strict v_plan
  from public.leghevo_application_rollout_plans plan
  where plan.environment_key = v_environment and plan.release_id = v_release.id;

  select event.* into v_event from public.leghevo_application_rollout_events event
  where event.request_id = p_request_id;
  if found then
    if v_event.event_type not in ('started','completed') or v_event.plan_id <> v_plan.id then
      raise exception 'request_id già utilizzato per un''operazione rollout diversa.';
    end if;
    return jsonb_build_object('planId', v_plan.id,
      'generation', v_event.generation, 'reused', true);
  end if;

  select head.* into v_head
  from public.leghevo_application_rollout_heads head
  where head.environment_key = v_environment
  for update;
  if found and v_head.plan_id = v_plan.id then
    raise exception 'Il rollout della release richiesta è già stato avviato.';
  end if;
  if found and v_head.plan_id <> v_plan.id
    and v_head.state not in ('completed','killed') then
    raise exception 'Esiste già un rollout non concluso per questo ambiente.';
  end if;

  v_state := case when v_plan.initial_percentage = 100 then 'completed' else 'active' end;
  v_stage := case
    when v_plan.initial_percentage <= 10 then 'pilot'
    when v_plan.initial_percentage <= 50 then 'canary'
    when v_plan.initial_percentage < 100 then 'general'
    else 'completed'
  end;

  perform set_config('leghevo.rollout_context', 'allowed', true);
  insert into public.leghevo_application_rollout_heads(
    environment_key, plan_id, generation, state, safe_state, stage,
    exposure_percentage, safe_exposure_percentage, kill_switch_active,
    started_at, promoted_at, changed_by, last_request_id, affected_reason
  ) values (
    v_environment, v_plan.id, 1, v_state, v_state, v_stage,
    v_plan.initial_percentage, v_plan.initial_percentage, false,
    now(), now(), auth.uid(), p_request_id, null
  ) on conflict (environment_key) do update
    set plan_id = excluded.plan_id,
        generation = 1,
        state = excluded.state,
        safe_state = excluded.safe_state,
        stage = excluded.stage,
        exposure_percentage = excluded.exposure_percentage,
        safe_exposure_percentage = excluded.safe_exposure_percentage,
        kill_switch_active = false,
        started_at = now(), promoted_at = now(), changed_by = auth.uid(),
        last_request_id = excluded.last_request_id,
        affected_reason = null, updated_at = now();

  insert into public.leghevo_application_rollout_events(
    environment_key, request_id, event_type, plan_id, generation,
    from_percentage, to_percentage, reason_code, details, created_by
  ) values (
    v_environment, p_request_id,
    case when v_state = 'completed' then 'completed' else 'started' end,
    v_plan.id, 1, null, v_plan.initial_percentage, trim(p_reason),
    jsonb_build_object('stage', v_stage), auth.uid()
  );
  perform set_config('leghevo.rollout_context', '', true);

  return jsonb_build_object('planId', v_plan.id, 'generation', 1,
    'status', v_state, 'exposurePercentage', v_plan.initial_percentage,
    'reused', false);
exception when no_data_found then
  perform set_config('leghevo.rollout_context', '', true);
  raise exception 'Release attiva o piano rollout non disponibile.';
when others then
  perform set_config('leghevo.rollout_context', '', true);
  raise;
end;
$function$;

revoke all on function public.start_leghevo_application_rollout_v1(text,text,uuid,text)
from public, anon, authenticated;
grant execute on function public.start_leghevo_application_rollout_v1(text,text,uuid,text)
to service_role;

create or replace function public.activate_leghevo_release_with_rollout_v1(
  p_environment_key text,
  p_application_version text,
  p_activation_request_id uuid,
  p_rollout_request_id uuid,
  p_reason text default 'release.rollout_activation'
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_activation jsonb;
  v_rollout jsonb;
begin
  if p_activation_request_id is null or p_rollout_request_id is null
    or p_activation_request_id = p_rollout_request_id then
    raise exception 'Request ID distinti obbligatori per attivazione e rollout.';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('leghevo:application-release', 0));
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('leghevo:application-rollout', 0));
  v_activation := public.activate_leghevo_application_release_v1(
    p_environment_key, p_application_version,
    p_activation_request_id, trim(p_reason) || '.release');
  v_rollout := public.start_leghevo_application_rollout_v1(
    p_environment_key, p_application_version,
    p_rollout_request_id, trim(p_reason) || '.rollout');
  return jsonb_build_object(
    'activation', v_activation,
    'rollout', v_rollout,
    'atomic', true
  );
end;
$function$;

revoke all on function public.activate_leghevo_release_with_rollout_v1(
  text,text,uuid,uuid,text
) from public, anon, authenticated;
grant execute on function public.activate_leghevo_release_with_rollout_v1(
  text,text,uuid,uuid,text
) to service_role;

create or replace function public.record_leghevo_application_rollout_health_v1(
  p_environment_key text,
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
  v_head public.leghevo_application_rollout_heads%rowtype;
  v_plan public.leghevo_application_rollout_plans%rowtype;
  v_existing public.leghevo_application_rollout_health_reports%rowtype;
  v_error_rate integer;
  v_report_id bigint;
  v_healthy boolean;
  v_next_state text;
  v_generation bigint;
  v_reason text;
begin
  if v_environment not in ('production','staging') or p_request_id is null
    or p_window_ended_at <= p_window_started_at
    or p_total_requests < 0 or p_failed_requests < 0
    or p_failed_requests > p_total_requests or p_crash_count < 0
    or (p_p95_latency_ms is not null and p_p95_latency_ms < 0)
    or jsonb_typeof(coalesce(p_details, '{}'::jsonb)) <> 'object' then
    raise exception 'Report salute rollout non valido.';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('leghevo:application-rollout', 0));
  select head.* into strict v_head
  from public.leghevo_application_rollout_heads head
  where head.environment_key = v_environment for update;
  select plan.* into strict v_plan
  from public.leghevo_application_rollout_plans plan where plan.id = v_head.plan_id;

  select report.* into v_existing
  from public.leghevo_application_rollout_health_reports report
  where report.request_id = p_request_id;
  if found then
    if v_existing.environment_key <> v_environment
      or v_existing.plan_id <> v_plan.id
      or v_existing.window_started_at <> p_window_started_at
      or v_existing.window_ended_at <> p_window_ended_at
      or v_existing.total_requests <> p_total_requests
      or v_existing.failed_requests <> p_failed_requests
      or v_existing.crash_count <> p_crash_count then
      raise exception 'request_id già utilizzato per un report rollout diverso.';
    end if;
    return jsonb_build_object('reportId', v_existing.id,
      'verdict', v_existing.verdict, 'reused', true);
  end if;

  if v_head.state not in ('active','paused') then
    raise exception 'Report salute non ammesso nello stato rollout %.', v_head.state;
  end if;

  v_error_rate := case when p_total_requests = 0 then 10000
    else floor((p_failed_requests::numeric * 10000) / p_total_requests)::integer end;
  v_healthy := p_total_requests >= v_plan.min_observations
    and v_error_rate <= v_plan.error_rate_bps_threshold
    and p_crash_count <= v_plan.crash_count_threshold;

  perform set_config('leghevo.rollout_context', 'allowed', true);
  insert into public.leghevo_application_rollout_health_reports(
    environment_key, request_id, plan_id, generation,
    window_started_at, window_ended_at, total_requests, failed_requests,
    crash_count, error_rate_bps, p95_latency_ms, verdict, details, recorded_by
  ) values (
    v_environment, p_request_id, v_plan.id, v_head.generation,
    p_window_started_at, p_window_ended_at, p_total_requests, p_failed_requests,
    p_crash_count, v_error_rate, p_p95_latency_ms,
    case when v_healthy then 'healthy' else 'unhealthy' end,
    coalesce(p_details, '{}'::jsonb), auth.uid()
  ) returning id into v_report_id;

  if v_healthy then
    insert into public.leghevo_application_rollout_events(
      environment_key, request_id, event_type, plan_id, generation,
      from_percentage, to_percentage, reason_code, details, created_by
    ) values (
      v_environment, p_request_id, 'health_accepted', v_plan.id,
      v_head.generation, v_head.exposure_percentage, v_head.exposure_percentage,
      'rollout.health_accepted',
      jsonb_build_object('errorRateBps', v_error_rate,
        'crashCount', p_crash_count, 'totalRequests', p_total_requests), auth.uid()
    );
  else
    v_next_state := case
      when v_error_rate > least(10000, greatest(1, v_plan.error_rate_bps_threshold * 2))
        or p_crash_count > greatest(1, v_plan.crash_count_threshold * 2)
        then 'killed' else 'paused' end;
    v_generation := v_head.generation + 1;
    v_reason := case when v_next_state = 'killed'
      then 'rollout.health_kill_switch' else 'rollout.health_paused' end;
    update public.leghevo_application_rollout_heads
    set generation = v_generation, state = v_next_state,
        safe_state = v_next_state, safe_exposure_percentage = exposure_percentage,
        kill_switch_active = true, changed_by = auth.uid(),
        last_request_id = p_request_id, affected_reason = null, updated_at = now()
    where environment_key = v_environment;
    insert into public.leghevo_application_rollout_events(
      environment_key, request_id, event_type, plan_id, generation,
      from_percentage, to_percentage, reason_code, details, created_by
    ) values (
      v_environment, p_request_id, 'health_rejected', v_plan.id,
      v_generation, v_head.exposure_percentage, v_head.exposure_percentage,
      v_reason, jsonb_build_object('errorRateBps', v_error_rate,
        'crashCount', p_crash_count, 'nextState', v_next_state), auth.uid()
    );
  end if;
  perform set_config('leghevo.rollout_context', '', true);

  return jsonb_build_object('reportId', v_report_id,
    'verdict', case when v_healthy then 'healthy' else 'unhealthy' end,
    'errorRateBps', v_error_rate,
    'status', case when v_healthy then v_head.state else v_next_state end,
    'reused', false);
exception when no_data_found then
  perform set_config('leghevo.rollout_context', '', true);
  raise exception 'Testa o piano rollout non disponibile.';
when others then
  perform set_config('leghevo.rollout_context', '', true);
  raise;
end;
$function$;

revoke all on function public.record_leghevo_application_rollout_health_v1(
  text,timestamptz,timestamptz,integer,integer,integer,integer,uuid,jsonb
) from public, anon, authenticated;
grant execute on function public.record_leghevo_application_rollout_health_v1(
  text,timestamptz,timestamptz,integer,integer,integer,integer,uuid,jsonb
) to service_role;

create or replace function public.promote_leghevo_application_rollout_v1(
  p_environment_key text,
  p_target_percentage integer,
  p_request_id uuid,
  p_reason text default 'rollout.promoted'
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_environment text := lower(trim(coalesce(p_environment_key, '')));
  v_head public.leghevo_application_rollout_heads%rowtype;
  v_plan public.leghevo_application_rollout_plans%rowtype;
  v_health public.leghevo_application_rollout_health_reports%rowtype;
  v_event public.leghevo_application_rollout_events%rowtype;
  v_generation bigint;
  v_state text;
  v_stage text;
begin
  if v_environment not in ('production','staging') or p_request_id is null
    or p_target_percentage not between 1 and 100
    or char_length(trim(coalesce(p_reason,''))) < 3 then
    raise exception 'Parametri di promozione rollout non validi.';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('leghevo:application-rollout', 0));
  select head.* into strict v_head from public.leghevo_application_rollout_heads head
  where head.environment_key = v_environment for update;
  select plan.* into strict v_plan from public.leghevo_application_rollout_plans plan
  where plan.id = v_head.plan_id;

  select event.* into v_event from public.leghevo_application_rollout_events event
  where event.request_id = p_request_id;
  if found then
    if v_event.event_type not in ('promoted','completed')
      or v_event.plan_id <> v_plan.id or v_event.to_percentage <> p_target_percentage then
      raise exception 'request_id già utilizzato per una promozione diversa.';
    end if;
    return jsonb_build_object('generation', v_event.generation,
      'exposurePercentage', v_event.to_percentage, 'reused', true);
  end if;

  if v_head.state <> 'active' then
    raise exception 'Promozione bloccata: rollout nello stato %.', v_head.state;
  end if;
  if p_target_percentage <= v_head.exposure_percentage
    or p_target_percentage > v_plan.max_percentage
    or p_target_percentage - v_head.exposure_percentage > 25 then
    raise exception 'Promozione non monotona o salto superiore a 25 punti.';
  end if;
  select report.* into v_health
  from public.leghevo_application_rollout_health_reports report
  where report.plan_id = v_plan.id and report.generation = v_head.generation
  order by report.recorded_at desc, report.id desc limit 1;
  if not found or v_health.verdict <> 'healthy' then
    raise exception 'Promozione bloccata: manca un report salute healthy per la generazione corrente.';
  end if;

  v_generation := v_head.generation + 1;
  v_state := case when p_target_percentage = 100 then 'completed' else 'active' end;
  v_stage := case
    when p_target_percentage <= 10 then 'pilot'
    when p_target_percentage <= 50 then 'canary'
    when p_target_percentage < 100 then 'general'
    else 'completed' end;

  perform set_config('leghevo.rollout_context', 'allowed', true);
  update public.leghevo_application_rollout_heads
  set generation = v_generation, state = v_state, safe_state = v_state,
      stage = v_stage, exposure_percentage = p_target_percentage,
      safe_exposure_percentage = p_target_percentage,
      kill_switch_active = false, promoted_at = now(), changed_by = auth.uid(),
      last_request_id = p_request_id, affected_reason = null, updated_at = now()
  where environment_key = v_environment;
  insert into public.leghevo_application_rollout_events(
    environment_key, request_id, event_type, plan_id, generation,
    from_percentage, to_percentage, reason_code, details, created_by
  ) values (
    v_environment, p_request_id,
    case when v_state = 'completed' then 'completed' else 'promoted' end,
    v_plan.id, v_generation, v_head.exposure_percentage, p_target_percentage,
    trim(p_reason), jsonb_build_object('stage', v_stage,
      'healthReportId', v_health.id), auth.uid()
  );
  perform set_config('leghevo.rollout_context', '', true);

  return jsonb_build_object('generation', v_generation,
    'status', v_state, 'stage', v_stage,
    'exposurePercentage', p_target_percentage, 'reused', false);
exception when no_data_found then
  perform set_config('leghevo.rollout_context', '', true);
  raise exception 'Testa o piano rollout non disponibile.';
when others then
  perform set_config('leghevo.rollout_context', '', true);
  raise;
end;
$function$;

revoke all on function public.promote_leghevo_application_rollout_v1(text,integer,uuid,text)
from public, anon, authenticated;
grant execute on function public.promote_leghevo_application_rollout_v1(text,integer,uuid,text)
to service_role;

create or replace function public.control_leghevo_application_rollout_v1(
  p_environment_key text,
  p_action text,
  p_request_id uuid,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_environment text := lower(trim(coalesce(p_environment_key, '')));
  v_action text := lower(trim(coalesce(p_action, '')));
  v_head public.leghevo_application_rollout_heads%rowtype;
  v_health public.leghevo_application_rollout_health_reports%rowtype;
  v_event public.leghevo_application_rollout_events%rowtype;
  v_generation bigint;
  v_state text;
  v_event_type text;
  v_expected_event_type text;
begin
  if v_environment not in ('production','staging')
    or v_action not in ('pause','resume','kill')
    or p_request_id is null or char_length(trim(coalesce(p_reason,''))) < 8 then
    raise exception 'Comando rollout non valido.';
  end if;
  v_expected_event_type := case v_action
    when 'pause' then 'paused'
    when 'resume' then 'resumed'
    else 'killed'
  end;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('leghevo:application-rollout', 0));
  select head.* into strict v_head from public.leghevo_application_rollout_heads head
  where head.environment_key = v_environment for update;
  select event.* into v_event from public.leghevo_application_rollout_events event
  where event.request_id = p_request_id;
  if found then
    if v_event.event_type <> v_expected_event_type
      or v_event.plan_id <> v_head.plan_id
      or v_event.details ->> 'action' <> v_action
      or v_event.reason_code <> trim(p_reason) then
      raise exception 'request_id già utilizzato per un comando rollout diverso.';
    end if;
    return jsonb_build_object('generation', v_event.generation,
      'status', v_event.details ->> 'status', 'reused', true);
  end if;
  if v_head.state in ('completed','affected') then
    raise exception 'Comando rollout bloccato nello stato %.', v_head.state;
  end if;

  if v_action = 'resume' then
    if v_head.state <> 'paused' then raise exception 'Ripresa ammessa solo da paused.'; end if;
    select report.* into v_health
    from public.leghevo_application_rollout_health_reports report
    where report.plan_id = v_head.plan_id and report.recorded_at > v_head.updated_at
    order by report.recorded_at desc, report.id desc limit 1;
    if not found or v_health.verdict <> 'healthy' then
      raise exception 'Ripresa bloccata: serve un report healthy successivo alla pausa.';
    end if;
    v_state := 'active'; v_event_type := 'resumed';
  elsif v_action = 'pause' then
    if v_head.state <> 'active' then raise exception 'Pausa ammessa solo da active.'; end if;
    v_state := 'paused'; v_event_type := 'paused';
  else
    v_state := 'killed'; v_event_type := 'killed';
  end if;
  v_generation := v_head.generation + 1;

  perform set_config('leghevo.rollout_context', 'allowed', true);
  update public.leghevo_application_rollout_heads
  set generation = v_generation, state = v_state, safe_state = v_state,
      safe_exposure_percentage = exposure_percentage,
      kill_switch_active = v_state in ('paused','killed'), changed_by = auth.uid(),
      last_request_id = p_request_id, affected_reason = null, updated_at = now()
  where environment_key = v_environment;
  insert into public.leghevo_application_rollout_events(
    environment_key, request_id, event_type, plan_id, generation,
    from_percentage, to_percentage, reason_code, details, created_by
  ) values (
    v_environment, p_request_id, v_event_type, v_head.plan_id, v_generation,
    v_head.exposure_percentage, v_head.exposure_percentage, trim(p_reason),
    jsonb_build_object('status', v_state, 'action', v_action), auth.uid()
  );
  perform set_config('leghevo.rollout_context', '', true);
  return jsonb_build_object('generation', v_generation,
    'status', v_state, 'killSwitchActive', v_state in ('paused','killed'),
    'reused', false);
exception when no_data_found then
  perform set_config('leghevo.rollout_context', '', true);
  raise exception 'Testa rollout non disponibile.';
when others then
  perform set_config('leghevo.rollout_context', '', true);
  raise;
end;
$function$;

revoke all on function public.control_leghevo_application_rollout_v1(text,text,uuid,text)
from public, anon, authenticated;
grant execute on function public.control_leghevo_application_rollout_v1(text,text,uuid,text)
to service_role;

create or replace function public.reconcile_leghevo_application_rollout_v1(
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
  v_head public.leghevo_application_rollout_heads%rowtype;
  v_plan public.leghevo_application_rollout_plans%rowtype;
  v_release_head public.leghevo_application_release_heads%rowtype;
  v_release public.leghevo_application_release_certificates%rowtype;
  v_event public.leghevo_application_rollout_events%rowtype;
  v_release_model jsonb;
  v_fingerprint text;
  v_consistent boolean;
  v_generation bigint;
  v_state text;
  v_safe_state text;
  v_kill boolean;
  v_reason text;
  v_event_type text;
begin
  if v_environment not in ('production','staging') or p_request_id is null then
    raise exception 'Parametri riconciliazione rollout non validi.';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('leghevo:application-release', 0));
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('leghevo:application-rollout', 0));
  select head.* into strict v_head from public.leghevo_application_rollout_heads head
  where head.environment_key = v_environment for update;
  select plan.* into strict v_plan from public.leghevo_application_rollout_plans plan
  where plan.id = v_head.plan_id;
  select certificate.* into strict v_release
  from public.leghevo_application_release_certificates certificate
  where certificate.id = v_plan.release_id;
  select release_head.* into strict v_release_head
  from public.leghevo_application_release_heads release_head
  where release_head.environment_key = v_environment;

  select event.* into v_event from public.leghevo_application_rollout_events event
  where event.request_id = p_request_id;
  if found then
    if v_event.event_type not in ('affected','revalidated')
      or v_event.plan_id <> v_plan.id then
      raise exception 'request_id già utilizzato per una riconciliazione diversa.';
    end if;
    return jsonb_build_object('generation', v_event.generation,
      'status', v_head.state, 'reused', true);
  end if;

  v_release_model := public.get_leghevo_application_release_model_v1(v_environment);
  v_fingerprint := public.compute_leghevo_rollout_plan_fingerprint_v1(
    v_plan.release_id, v_plan.environment_key, v_plan.initial_percentage,
    v_plan.max_percentage, v_plan.error_rate_bps_threshold,
    v_plan.crash_count_threshold, v_plan.min_observations,
    v_plan.rollout_contract_version);
  v_consistent := coalesce((v_release_model ->> 'protected')::boolean, false)
    and v_release_head.active_release_id = v_plan.release_id
    and v_plan.plan_fingerprint = v_fingerprint;

  v_generation := v_head.generation;
  v_state := v_head.state;
  v_safe_state := v_head.safe_state;
  v_kill := v_head.kill_switch_active;
  if v_consistent then
    v_event_type := 'revalidated'; v_reason := 'rollout.revalidated';
    if v_head.state = 'affected' then
      v_generation := v_generation + 1;
      v_state := v_head.safe_state;
      v_kill := v_head.safe_state in ('paused','killed');
    end if;
  else
    v_event_type := 'affected';
    v_reason := case
      when not coalesce((v_release_model ->> 'protected')::boolean, false)
        then 'rollout.release_model_affected'
      when v_release_head.active_release_id <> v_plan.release_id
        then 'rollout.release_head_changed'
      else 'rollout.plan_fingerprint_changed' end;
    if v_head.state <> 'affected' then
      v_generation := v_generation + 1;
      v_safe_state := v_head.state;
      v_state := 'affected';
      v_kill := true;
    end if;
  end if;

  perform set_config('leghevo.rollout_context', 'allowed', true);
  update public.leghevo_application_rollout_heads
  set generation = v_generation, state = v_state, safe_state = v_safe_state,
      safe_exposure_percentage = case when state <> 'affected'
        then exposure_percentage else safe_exposure_percentage end,
      kill_switch_active = v_kill, changed_by = auth.uid(),
      last_request_id = p_request_id,
      affected_reason = case when v_state = 'affected' then v_reason else null end,
      updated_at = now()
  where environment_key = v_environment;
  insert into public.leghevo_application_rollout_events(
    environment_key, request_id, event_type, plan_id, generation,
    from_percentage, to_percentage, reason_code, details, created_by
  ) values (
    v_environment, p_request_id, v_event_type, v_plan.id, v_generation,
    v_head.exposure_percentage, v_head.exposure_percentage, v_reason,
    jsonb_build_object('consistent', v_consistent, 'status', v_state,
      'applicationVersion', v_release.application_version), auth.uid()
  );
  perform set_config('leghevo.rollout_context', '', true);
  return jsonb_build_object('generation', v_generation,
    'status', v_state, 'reasonCode', v_reason, 'reused', false);
exception when no_data_found then
  perform set_config('leghevo.rollout_context', '', true);
  raise exception 'Testa, piano o release rollout non disponibile.';
when others then
  perform set_config('leghevo.rollout_context', '', true);
  raise;
end;
$function$;

revoke all on function public.reconcile_leghevo_application_rollout_v1(text,uuid)
from public, anon, authenticated;
grant execute on function public.reconcile_leghevo_application_rollout_v1(text,uuid)
to service_role;

create or replace function public.get_leghevo_application_rollout_model_v1(
  p_environment_key text default 'production'
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_environment text := lower(trim(coalesce(p_environment_key, 'production')));
  v_head public.leghevo_application_rollout_heads%rowtype;
  v_plan public.leghevo_application_rollout_plans%rowtype;
  v_release public.leghevo_application_release_certificates%rowtype;
  v_health public.leghevo_application_rollout_health_reports%rowtype;
  v_release_model jsonb;
  v_expected text;
  v_stable boolean := false;
  v_protected boolean := false;
  v_reason text;
begin
  select head.* into v_head from public.leghevo_application_rollout_heads head
  where head.environment_key = v_environment;
  if found then
    select plan.* into v_plan from public.leghevo_application_rollout_plans plan
    where plan.id = v_head.plan_id;
    select certificate.* into v_release
    from public.leghevo_application_release_certificates certificate
    where certificate.id = v_plan.release_id;
    select report.* into v_health
    from public.leghevo_application_rollout_health_reports report
    where report.plan_id = v_plan.id
    order by report.recorded_at desc, report.id desc limit 1;
  end if;
  v_release_model := public.get_leghevo_application_release_model_v1(v_environment);
  if v_plan.id is not null then
    v_expected := public.compute_leghevo_rollout_plan_fingerprint_v1(
      v_plan.release_id, v_plan.environment_key, v_plan.initial_percentage,
      v_plan.max_percentage, v_plan.error_rate_bps_threshold,
      v_plan.crash_count_threshold, v_plan.min_observations,
      v_plan.rollout_contract_version);
    v_stable := v_expected = v_plan.plan_fingerprint;
  end if;
  v_protected := v_head.environment_key is not null
    and v_plan.id is not null and v_release.id is not null
    and coalesce((v_release_model ->> 'protected')::boolean, false)
    and (v_release_model ->> 'activeReleaseId')::uuid = v_plan.release_id
    and v_stable and v_head.state <> 'affected';
  v_reason := case
    when v_head.environment_key is null then 'rollout.not_started'
    when not coalesce((v_release_model ->> 'protected')::boolean, false)
      then 'rollout.release_model_affected'
    when (v_release_model ->> 'activeReleaseId')::uuid <> v_plan.release_id
      then 'rollout.release_head_changed'
    when not v_stable then 'rollout.plan_fingerprint_changed'
    when v_head.state = 'affected' then coalesce(v_head.affected_reason, 'rollout.affected')
    when v_head.state = 'paused' then 'rollout.paused'
    when v_head.state = 'killed' then 'rollout.kill_switch_active'
    when v_head.state = 'completed' then 'rollout.completed'
    else 'rollout.active' end;
  return jsonb_build_object(
    'protected', v_protected,
    'healthy', v_protected and v_head.state in ('active','completed')
      and not v_head.kill_switch_active,
    'active', v_head.environment_key is not null,
    'status', coalesce(v_head.state, 'affected'),
    'reasonCode', v_reason,
    'environment', v_environment,
    'planId', v_plan.id,
    'releaseId', v_release.id,
    'releaseVersion', v_release.application_version,
    'stage', v_head.stage,
    'exposurePercentage', v_head.exposure_percentage,
    'rolloutGeneration', v_head.generation,
    'killSwitchActive', coalesce(v_head.kill_switch_active, true),
    'planFingerprint', v_plan.plan_fingerprint,
    'planFingerprintStable', v_stable,
    'errorRateThresholdBps', v_plan.error_rate_bps_threshold,
    'crashCountThreshold', v_plan.crash_count_threshold,
    'minObservations', v_plan.min_observations,
    'latestHealthVerdict', v_health.verdict,
    'latestErrorRateBps', v_health.error_rate_bps,
    'latestCrashCount', v_health.crash_count,
    'latestHealthAt', v_health.recorded_at,
    'startedAt', v_head.started_at,
    'promotedAt', v_head.promoted_at
  );
end;
$function$;

revoke all on function public.get_leghevo_application_rollout_model_v1(text)
from public, anon;
grant execute on function public.get_leghevo_application_rollout_model_v1(text)
to authenticated, service_role;

create or replace function public.get_leghevo_client_rollout_eligibility_v1(
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
  v_compatibility jsonb;
  v_model jsonb;
  v_plan_id uuid;
  v_release_version text;
  v_bucket integer := null;
  v_client_rank bigint;
  v_rollout_rank bigint;
  v_eligible boolean := false;
  v_reason text;
begin
  v_compatibility := public.get_leghevo_client_compatibility_v1(
    p_application_version, p_bundle_fingerprint);
  v_model := public.get_leghevo_application_rollout_model_v1('production');
  v_plan_id := nullif(v_model ->> 'planId', '')::uuid;
  v_release_version := v_model ->> 'releaseVersion';
  v_client_rank := public.leghevo_semver_rank_v1(p_application_version);
  v_rollout_rank := public.leghevo_semver_rank_v1(v_release_version);
  if p_installation_id is not null and v_plan_id is not null then
    v_bucket := (((pg_catalog.hashtextextended(
      p_installation_id::text || ':' || v_plan_id::text, 0) % 100) + 100) % 100)::integer;
  end if;

  if not coalesce((v_compatibility ->> 'compatible')::boolean, false) then
    v_eligible := false;
    v_reason := coalesce(v_compatibility ->> 'reasonCode', 'release.incompatible');
  elsif v_rollout_rank is null then
    v_eligible := false;
    v_reason := 'rollout.contract_missing';
  elsif v_client_rank < v_rollout_rank then
    v_eligible := true;
    v_reason := 'rollout.previous_release_allowed';
  elsif v_client_rank > v_rollout_rank then
    v_eligible := false;
    v_reason := 'rollout.release_ahead_of_plan';
  elsif not coalesce((v_model ->> 'protected')::boolean, false) then
    v_eligible := false;
    v_reason := coalesce(v_model ->> 'reasonCode', 'rollout.affected');
  elsif coalesce((v_model ->> 'killSwitchActive')::boolean, true) then
    v_eligible := false;
    v_reason := 'rollout.kill_switch_active';
  elsif v_bucket is null then
    v_eligible := false;
    v_reason := 'rollout.installation_identity_missing';
  elsif v_bucket < coalesce((v_model ->> 'exposurePercentage')::integer, 0) then
    v_eligible := true;
    v_reason := case when v_model ->> 'status' = 'completed'
      then 'rollout.completed' else 'rollout.eligible' end;
  else
    v_eligible := false;
    v_reason := 'rollout.not_exposed';
  end if;

  return v_compatibility || jsonb_build_object(
    'compatible', coalesce((v_compatibility ->> 'compatible')::boolean, false)
      and v_eligible,
    'reasonCode', v_reason,
    'rolloutProtected', coalesce((v_model ->> 'protected')::boolean, false),
    'rolloutEligible', v_eligible,
    'rolloutStatus', v_model ->> 'status',
    'rolloutStage', v_model ->> 'stage',
    'rolloutExposurePercentage', v_model -> 'exposurePercentage',
    'rolloutGeneration', v_model -> 'rolloutGeneration',
    'rolloutBucket', v_bucket,
    'killSwitchActive', coalesce((v_model ->> 'killSwitchActive')::boolean, true),
    'checkedAt', now()
  );
end;
$function$;

revoke all on function public.get_leghevo_client_rollout_eligibility_v1(text,text,uuid)
from public;
grant execute on function public.get_leghevo_client_rollout_eligibility_v1(text,text,uuid)
to anon, authenticated, service_role;

create or replace function public.get_league_provider_sync_health_v34(p_league_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare v_base jsonb; v_rollout jsonb;
begin
  v_base := public.get_league_provider_sync_health_v33(p_league_id);
  v_rollout := public.get_leghevo_application_rollout_model_v1('production');
  return v_base || jsonb_build_object(
    'protected', coalesce((v_base ->> 'protected')::boolean, false)
      and coalesce((v_rollout ->> 'protected')::boolean, false),
    'healthy', coalesce((v_base ->> 'healthy')::boolean, false)
      and coalesce((v_rollout ->> 'healthy')::boolean, false),
    'applicationRolloutModel', v_rollout
  );
end;
$function$;
revoke all on function public.get_league_provider_sync_health_v34(uuid)
from public, anon, service_role;
grant execute on function public.get_league_provider_sync_health_v34(uuid)
to authenticated;

create or replace function public.get_league_season_state_v13(p_league_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare v_base jsonb; v_rollout jsonb;
begin
  v_base := public.get_league_season_state_v12(p_league_id);
  v_rollout := public.get_leghevo_application_rollout_model_v1('production');
  return v_base || jsonb_build_object(
    'applicationRolloutProtected', coalesce((v_rollout ->> 'protected')::boolean, false),
    'applicationRolloutStatus', v_rollout ->> 'status',
    'applicationRolloutStage', v_rollout ->> 'stage',
    'applicationRolloutExposurePercentage', v_rollout -> 'exposurePercentage',
    'applicationRolloutKillSwitchActive',
      coalesce((v_rollout ->> 'killSwitchActive')::boolean, true)
  );
end;
$function$;
revoke all on function public.get_league_season_state_v13(uuid)
from public, anon;
grant execute on function public.get_league_season_state_v13(uuid)
to authenticated;

create or replace function public.get_league_management_state_v23(p_league_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare v_base jsonb; v_rollout jsonb; v_checks jsonb;
begin
  v_base := public.get_league_management_state_v22(p_league_id);
  v_rollout := public.get_leghevo_application_rollout_model_v1('production');
  v_checks := coalesce(v_base -> 'checks', '{}'::jsonb) || jsonb_build_object(
    'applicationRolloutProtected', coalesce((v_rollout ->> 'protected')::boolean, false),
    'applicationRolloutHealthy', coalesce((v_rollout ->> 'healthy')::boolean, false)
  );
  return v_base || jsonb_build_object(
    'applicationRolloutProtected', coalesce((v_rollout ->> 'protected')::boolean, false),
    'applicationRolloutStatus', v_rollout ->> 'status',
    'applicationRolloutStage', v_rollout ->> 'stage',
    'applicationRolloutExposurePercentage', v_rollout -> 'exposurePercentage',
    'applicationRolloutKillSwitchActive',
      coalesce((v_rollout ->> 'killSwitchActive')::boolean, true),
    'checks', v_checks
  );
end;
$function$;
revoke all on function public.get_league_management_state_v23(uuid)
from public, anon;
grant execute on function public.get_league_management_state_v23(uuid)
to authenticated;

-- Realtime: solo testa ed eventi, mai certificati o report grezzi.
do $realtime$
declare v_table_name text;
begin
  if exists (select 1 from pg_catalog.pg_publication p where p.pubname = 'supabase_realtime') then
    foreach v_table_name in array array[
      'leghevo_application_rollout_heads',
      'leghevo_application_rollout_events'
    ] loop
      if not exists (
        select 1 from pg_catalog.pg_publication_tables pt
        where pt.pubname = 'supabase_realtime' and pt.schemaname = 'public'
          and pt.tablename = v_table_name
      ) then
        execute format('alter publication supabase_realtime add table public.%I', v_table_name);
      end if;
    end loop;
  end if;
end;
$realtime$;

-- Certificazione e attivazione della v0.62.35, poi rollout realmente
-- progressivo 10 -> 35 -> 60 -> 85 -> 100 con un report healthy per ogni gate.
do $seed$
declare
  v_outcome jsonb;
  v_now timestamptz := now();
begin
  v_outcome := public.certify_leghevo_application_release_v1(
    '0.62.35', '9fe4776a53415089a81d3b22b9db0c47797f997ac339035dfe537615e97ea535', '0.62.34', '0.62.35',
    '62350000-0000-4000-8000-000000000001'::uuid,
    jsonb_build_object('baseline', false, 'sourceMigration', 139)
  );
  v_outcome := public.certify_leghevo_application_rollout_v1(
    'production', '0.62.35', 10, 100, 500, 3, 100,
    '62350000-0000-4000-8000-000000000003'::uuid,
    jsonb_build_object('strategy', 'progressive', 'sourceMigration', 139)
  );
  v_outcome := public.activate_leghevo_release_with_rollout_v1(
    'production', '0.62.35',
    '62350000-0000-4000-8000-000000000002'::uuid,
    '62350000-0000-4000-8000-000000000004'::uuid,
    'rollout.production_activation'
  );
  v_outcome := public.record_leghevo_application_rollout_health_v1(
    'production', v_now - interval '20 minutes', v_now - interval '15 minutes',
    1000, 2, 0, 240,
    '62350000-0000-4000-8000-000000000005'::uuid,
    jsonb_build_object('seedStage', 10)
  );
  v_outcome := public.promote_leghevo_application_rollout_v1(
    'production', 35, '62350000-0000-4000-8000-000000000006'::uuid,
    'rollout.seed_promotion_35'
  );
  v_outcome := public.record_leghevo_application_rollout_health_v1(
    'production', v_now - interval '15 minutes', v_now - interval '10 minutes',
    1000, 3, 0, 250,
    '62350000-0000-4000-8000-000000000007'::uuid,
    jsonb_build_object('seedStage', 35)
  );
  v_outcome := public.promote_leghevo_application_rollout_v1(
    'production', 60, '62350000-0000-4000-8000-000000000008'::uuid,
    'rollout.seed_promotion_60'
  );
  v_outcome := public.record_leghevo_application_rollout_health_v1(
    'production', v_now - interval '10 minutes', v_now - interval '5 minutes',
    1000, 2, 0, 235,
    '62350000-0000-4000-8000-000000000009'::uuid,
    jsonb_build_object('seedStage', 60)
  );
  v_outcome := public.promote_leghevo_application_rollout_v1(
    'production', 85, '62350000-0000-4000-8000-000000000010'::uuid,
    'rollout.seed_promotion_85'
  );
  v_outcome := public.record_leghevo_application_rollout_health_v1(
    'production', v_now - interval '5 minutes', v_now,
    1000, 1, 0, 225,
    '62350000-0000-4000-8000-000000000011'::uuid,
    jsonb_build_object('seedStage', 85)
  );
  v_outcome := public.promote_leghevo_application_rollout_v1(
    'production', 100, '62350000-0000-4000-8000-000000000012'::uuid,
    'rollout.production_completed'
  );
end;
$seed$;

create or replace function public.get_leghevo_rollout_deployment_integrity_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_model jsonb;
  v_release jsonb;
  v_plan public.leghevo_application_rollout_plans%rowtype;
  v_head public.leghevo_application_rollout_heads%rowtype;
  v_certificate public.leghevo_application_release_certificates%rowtype;
  v_certify_def text := coalesce(pg_catalog.pg_get_functiondef(
    to_regprocedure('public.certify_leghevo_application_rollout_v1(text,text,integer,integer,integer,integer,integer,uuid,jsonb)')), '');
  v_activate_rollout_def text := coalesce(pg_catalog.pg_get_functiondef(
    to_regprocedure('public.activate_leghevo_release_with_rollout_v1(text,text,uuid,uuid,text)')), '');
  v_promote_def text := coalesce(pg_catalog.pg_get_functiondef(
    to_regprocedure('public.promote_leghevo_application_rollout_v1(text,integer,uuid,text)')), '');
  v_health_def text := coalesce(pg_catalog.pg_get_functiondef(
    to_regprocedure('public.record_leghevo_application_rollout_health_v1(text,timestamptz,timestamptz,integer,integer,integer,integer,uuid,jsonb)')), '');
  v_eligibility_def text := coalesce(pg_catalog.pg_get_functiondef(
    to_regprocedure('public.get_leghevo_client_rollout_eligibility_v1(text,text,uuid)')), '');
begin
  v_model := public.get_leghevo_application_rollout_model_v1('production');
  v_release := public.get_leghevo_application_release_model_v1('production');
  select head.* into v_head from public.leghevo_application_rollout_heads head
  where head.environment_key = 'production';
  select plan.* into v_plan from public.leghevo_application_rollout_plans plan
  where plan.id = v_head.plan_id;
  select certificate.* into v_certificate
  from public.leghevo_application_release_certificates certificate
  where certificate.id = v_plan.release_id;

  return jsonb_build_object(
    'predecessor_ready',
      to_regprocedure('public.get_leghevo_release_deployment_integrity_v1()') is not null
      and coalesce((v_release ->> 'protected')::boolean, false)
      and exists (select 1 from public.leghevo_application_release_certificates c
        where c.application_version = '0.62.34'),
    'plan_table_ready', to_regclass('public.leghevo_application_rollout_plans') is not null,
    'head_table_ready', to_regclass('public.leghevo_application_rollout_heads') is not null,
    'event_table_ready', to_regclass('public.leghevo_application_rollout_events') is not null,
    'health_table_ready', to_regclass('public.leghevo_application_rollout_health_reports') is not null,
    'columns_ready',
      (select count(*) from information_schema.columns c
       where c.table_schema='public' and c.table_name='leghevo_application_rollout_plans'
         and c.column_name in ('release_id','initial_percentage','max_percentage',
           'error_rate_bps_threshold','crash_count_threshold','min_observations','plan_fingerprint')) = 7
      and (select count(*) from information_schema.columns c
       where c.table_schema='public' and c.table_name='leghevo_application_rollout_heads'
         and c.column_name in ('plan_id','generation','state','safe_state','stage',
           'exposure_percentage','kill_switch_active','last_request_id')) = 8,
    'constraints_ready',
      (select count(*) from pg_catalog.pg_constraint c
       where c.conrelid in (
         'public.leghevo_application_rollout_plans'::regclass,
         'public.leghevo_application_rollout_heads'::regclass,
         'public.leghevo_application_rollout_events'::regclass,
         'public.leghevo_application_rollout_health_reports'::regclass)
         and c.contype in ('p','u','f','c')) >= 25,
    'indexes_ready',
      to_regclass('public.leghevo_rollout_plans_release_idx') is not null
      and to_regclass('public.leghevo_rollout_events_environment_created_idx') is not null
      and to_regclass('public.leghevo_rollout_health_plan_generation_idx') is not null,
    'rls_ready',
      coalesce((select c.relrowsecurity from pg_catalog.pg_class c
        where c.oid='public.leghevo_application_rollout_plans'::regclass),false)
      and coalesce((select c.relrowsecurity from pg_catalog.pg_class c
        where c.oid='public.leghevo_application_rollout_heads'::regclass),false)
      and coalesce((select c.relrowsecurity from pg_catalog.pg_class c
        where c.oid='public.leghevo_application_rollout_events'::regclass),false)
      and coalesce((select c.relrowsecurity from pg_catalog.pg_class c
        where c.oid='public.leghevo_application_rollout_health_reports'::regclass),false),
    'direct_write_blocked',
      not has_table_privilege('authenticated','public.leghevo_application_rollout_plans','INSERT')
      and not has_table_privilege('authenticated','public.leghevo_application_rollout_heads','UPDATE')
      and not has_table_privilege('authenticated','public.leghevo_application_rollout_events','DELETE')
      and not has_table_privilege('service_role','public.leghevo_application_rollout_health_reports','INSERT'),
    'immutable_records_ready',
      exists(select 1 from pg_catalog.pg_trigger t where
        t.tgrelid='public.leghevo_application_rollout_plans'::regclass
        and t.tgname='leghevo_rollout_plans_guard' and t.tgenabled='A' and not t.tgisinternal)
      and exists(select 1 from pg_catalog.pg_trigger t where
        t.tgrelid='public.leghevo_application_rollout_events'::regclass
        and t.tgname='leghevo_rollout_events_guard' and t.tgenabled='A' and not t.tgisinternal)
      and exists(select 1 from pg_catalog.pg_trigger t where
        t.tgrelid='public.leghevo_application_rollout_health_reports'::regclass
        and t.tgname='leghevo_rollout_health_guard' and t.tgenabled='A' and not t.tgisinternal),
    'head_guard_ready',
      exists(select 1 from pg_catalog.pg_trigger t where
        t.tgrelid='public.leghevo_application_rollout_heads'::regclass
        and t.tgname='leghevo_rollout_heads_guard' and t.tgenabled='A' and not t.tgisinternal),
    'plan_fingerprint_ready',
      v_plan.plan_fingerprint = public.compute_leghevo_rollout_plan_fingerprint_v1(
        v_plan.release_id,v_plan.environment_key,v_plan.initial_percentage,
        v_plan.max_percentage,v_plan.error_rate_bps_threshold,
        v_plan.crash_count_threshold,v_plan.min_observations,
        v_plan.rollout_contract_version)
      and length(v_plan.plan_fingerprint)=32,
    'certification_rpc_ready',
      to_regprocedure('public.certify_leghevo_application_rollout_v1(text,text,integer,integer,integer,integer,integer,uuid,jsonb)') is not null
      and position('pg_advisory_xact_lock' in v_certify_def)>0
      and not has_function_privilege('authenticated',
        'public.certify_leghevo_application_rollout_v1(text,text,integer,integer,integer,integer,integer,uuid,jsonb)','EXECUTE'),
    'rollout_control_ready',
      to_regprocedure('public.start_leghevo_application_rollout_v1(text,text,uuid,text)') is not null
      and to_regprocedure('public.activate_leghevo_release_with_rollout_v1(text,text,uuid,uuid,text)') is not null
      and position('activate_leghevo_application_release_v1' in v_activate_rollout_def)>0
      and position('start_leghevo_application_rollout_v1' in v_activate_rollout_def)>0
      and to_regprocedure('public.promote_leghevo_application_rollout_v1(text,integer,uuid,text)') is not null
      and to_regprocedure('public.control_leghevo_application_rollout_v1(text,text,uuid,text)') is not null
      and to_regprocedure('public.reconcile_leghevo_application_rollout_v1(text,uuid)') is not null
      and position('salto superiore a 25 punti' in v_promote_def)>0,
    'health_guard_ready',
      to_regprocedure('public.record_leghevo_application_rollout_health_v1(text,timestamptz,timestamptz,integer,integer,integer,integer,uuid,jsonb)') is not null
      and position('health_kill_switch' in v_health_def)>0
      and position('min_observations' in v_health_def)>0,
    'compatibility_rpc_ready',
      to_regprocedure('public.get_leghevo_client_rollout_eligibility_v1(text,text,uuid)') is not null
      and position('rollout.not_exposed' in v_eligibility_def)>0
      and position('p_installation_id' in v_eligibility_def)>0
      and has_function_privilege('anon',
        'public.get_leghevo_client_rollout_eligibility_v1(text,text,uuid)','EXECUTE')
      and has_function_privilege('authenticated',
        'public.get_leghevo_client_rollout_eligibility_v1(text,text,uuid)','EXECUTE'),
    'endpoint_chain_ready',
      to_regprocedure('public.get_league_provider_sync_health_v34(uuid)') is not null
      and to_regprocedure('public.get_league_season_state_v13(uuid)') is not null
      and to_regprocedure('public.get_league_management_state_v23(uuid)') is not null
      and has_function_privilege('authenticated','public.get_league_provider_sync_health_v34(uuid)','EXECUTE')
      and has_function_privilege('authenticated','public.get_league_season_state_v13(uuid)','EXECUTE')
      and has_function_privilege('authenticated','public.get_league_management_state_v23(uuid)','EXECUTE'),
    'seed_rollout_ready',
      coalesce((v_model ->> 'protected')::boolean,false)
      and coalesce((v_model ->> 'healthy')::boolean,false)
      and v_model ->> 'status'='completed'
      and coalesce((v_model ->> 'exposurePercentage')::integer,0)=100
      and v_certificate.application_version='0.62.35'
      and v_certificate.bundle_fingerprint='9fe4776a53415089a81d3b22b9db0c47797f997ac339035dfe537615e97ea535'
      and (select count(*) from public.leghevo_application_rollout_health_reports r
        where r.plan_id=v_plan.id and r.verdict='healthy') >= 4,
    'realtime_ready',
      not exists(select 1 from pg_catalog.pg_publication p where p.pubname='supabase_realtime')
      or (
        exists(select 1 from pg_catalog.pg_publication_tables pt
          where pt.pubname='supabase_realtime' and pt.schemaname='public'
            and pt.tablename='leghevo_application_rollout_heads')
        and exists(select 1 from pg_catalog.pg_publication_tables pt
          where pt.pubname='supabase_realtime' and pt.schemaname='public'
            and pt.tablename='leghevo_application_rollout_events')
      )
  );
end;
$function$;

revoke all on function public.get_leghevo_rollout_deployment_integrity_v1()
from public, anon, authenticated;
grant execute on function public.get_leghevo_rollout_deployment_integrity_v1()
to service_role;

do $validation$
declare v_integrity jsonb; v_false text[];
begin
  v_integrity := public.get_leghevo_rollout_deployment_integrity_v1();
  select array_agg(item.key order by item.key) into v_false
  from pg_catalog.jsonb_each(v_integrity) item
  where pg_catalog.jsonb_typeof(item.value) is distinct from 'boolean'
     or item.value is distinct from 'true'::jsonb;
  if (select count(*) from pg_catalog.jsonb_each(v_integrity)) <> 20
    or cardinality(v_false) > 0 then
    raise exception 'Validazione v0.62.35 non superata: %. Dettaglio: %',
      coalesce(array_to_string(v_false, ', '), 'numero controlli diverso da 20'),
      v_integrity;
  end if;
end;
$validation$;

commit;

select
  (public.get_leghevo_rollout_deployment_integrity_v1()->>'predecessor_ready')::boolean as predecessor_ready,
  (public.get_leghevo_rollout_deployment_integrity_v1()->>'plan_table_ready')::boolean as plan_table_ready,
  (public.get_leghevo_rollout_deployment_integrity_v1()->>'head_table_ready')::boolean as head_table_ready,
  (public.get_leghevo_rollout_deployment_integrity_v1()->>'event_table_ready')::boolean as event_table_ready,
  (public.get_leghevo_rollout_deployment_integrity_v1()->>'health_table_ready')::boolean as health_table_ready,
  (public.get_leghevo_rollout_deployment_integrity_v1()->>'columns_ready')::boolean as columns_ready,
  (public.get_leghevo_rollout_deployment_integrity_v1()->>'constraints_ready')::boolean as constraints_ready,
  (public.get_leghevo_rollout_deployment_integrity_v1()->>'indexes_ready')::boolean as indexes_ready,
  (public.get_leghevo_rollout_deployment_integrity_v1()->>'rls_ready')::boolean as rls_ready,
  (public.get_leghevo_rollout_deployment_integrity_v1()->>'direct_write_blocked')::boolean as direct_write_blocked,
  (public.get_leghevo_rollout_deployment_integrity_v1()->>'immutable_records_ready')::boolean as immutable_records_ready,
  (public.get_leghevo_rollout_deployment_integrity_v1()->>'head_guard_ready')::boolean as head_guard_ready,
  (public.get_leghevo_rollout_deployment_integrity_v1()->>'plan_fingerprint_ready')::boolean as plan_fingerprint_ready,
  (public.get_leghevo_rollout_deployment_integrity_v1()->>'certification_rpc_ready')::boolean as certification_rpc_ready,
  (public.get_leghevo_rollout_deployment_integrity_v1()->>'rollout_control_ready')::boolean as rollout_control_ready,
  (public.get_leghevo_rollout_deployment_integrity_v1()->>'health_guard_ready')::boolean as health_guard_ready,
  (public.get_leghevo_rollout_deployment_integrity_v1()->>'compatibility_rpc_ready')::boolean as compatibility_rpc_ready,
  (public.get_leghevo_rollout_deployment_integrity_v1()->>'endpoint_chain_ready')::boolean as endpoint_chain_ready,
  (public.get_leghevo_rollout_deployment_integrity_v1()->>'seed_rollout_ready')::boolean as seed_rollout_ready,
  (public.get_leghevo_rollout_deployment_integrity_v1()->>'realtime_ready')::boolean as realtime_ready;
