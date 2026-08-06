-- LEGHEVO v0.62.43
-- Sigillo finale di production readiness e go-live controllato
-- Dipendenza: v0.62.42 validata con 20/20 controlli true.

begin;

do $preflight$
declare
  v_integrity jsonb;
  v_false text[];
begin
  if to_regprocedure('public.get_leghevo_production_readiness_deployment_integrity_v1()') is not null
    and exists(
      select 1 from public.leghevo_application_release_certificates certificate
      where certificate.application_version='0.62.43'
    ) then
    return;
  end if;

  if to_regprocedure('public.get_leghevo_service_return_deployment_integrity_v1()') is null then
    raise exception 'Preflight v0.62.43 non superato: diagnostica v0.62.42 assente.';
  end if;

  v_integrity := public.get_leghevo_service_return_deployment_integrity_v1();
  select array_agg(item.key order by item.key)
  into v_false
  from pg_catalog.jsonb_each(v_integrity) item
  where pg_catalog.jsonb_typeof(item.value) is distinct from 'boolean'
     or item.value is distinct from 'true'::jsonb;

  if (select count(*) from pg_catalog.jsonb_each(v_integrity)) <> 20
    or cardinality(v_false) > 0 then
    raise exception 'Preflight v0.62.43 non superato: %. Dettaglio: %',
      coalesce(array_to_string(v_false, ', '), 'numero controlli diverso da 20'),
      v_integrity;
  end if;
end;
$preflight$;

create or replace function public.compute_leghevo_production_readiness_run_fingerprint_v1(
  p_environment_key text,
  p_readiness_generation bigint,
  p_active_release_version text,
  p_release_generation bigint,
  p_rollout_generation bigint,
  p_telemetry_generation bigint,
  p_outbox_sequence bigint,
  p_consumer_sequence bigint,
  p_audit_sequence bigint,
  p_checkpoint_generation bigint,
  p_backup_generation bigint,
  p_service_return_generation bigint,
  p_snapshot_fingerprint text,
  p_contract_version integer default 1
)
returns text
language sql
immutable
security definer
set search_path = ''
as $function$
  select public.leghevo_sha256_hex_v1(
    coalesce(lower(trim(p_environment_key)), '') || '|' ||
    coalesce(p_readiness_generation, 0)::text || '|' ||
    coalesce(trim(p_active_release_version), '') || '|' ||
    coalesce(p_release_generation, 0)::text || '|' ||
    coalesce(p_rollout_generation, 0)::text || '|' ||
    coalesce(p_telemetry_generation, 0)::text || '|' ||
    coalesce(p_outbox_sequence, 0)::text || '|' ||
    coalesce(p_consumer_sequence, 0)::text || '|' ||
    coalesce(p_audit_sequence, 0)::text || '|' ||
    coalesce(p_checkpoint_generation, 0)::text || '|' ||
    coalesce(p_backup_generation, 0)::text || '|' ||
    coalesce(p_service_return_generation, 0)::text || '|' ||
    coalesce(lower(trim(p_snapshot_fingerprint)), '') || '|' ||
    coalesce(p_contract_version, 0)::text
  );
$function$;

create or replace function public.compute_leghevo_production_readiness_check_fingerprint_v1(
  p_run_id bigint,
  p_check_key text,
  p_check_ordinal integer,
  p_component_fingerprint text,
  p_component_sequence bigint,
  p_status text,
  p_details jsonb
)
returns text
language sql
immutable
security definer
set search_path = ''
as $function$
  select public.leghevo_sha256_hex_v1(
    coalesce(p_run_id, 0)::text || '|' ||
    coalesce(lower(trim(p_check_key)), '') || '|' ||
    coalesce(p_check_ordinal, 0)::text || '|' ||
    coalesce(lower(trim(p_component_fingerprint)), '') || '|' ||
    coalesce(p_component_sequence, 0)::text || '|' ||
    coalesce(lower(trim(p_status)), '') || '|' ||
    coalesce(p_details, '{}'::jsonb)::text
  );
$function$;

create or replace function public.compute_leghevo_production_readiness_certificate_fingerprint_v1(
  p_run_id bigint,
  p_environment_key text,
  p_readiness_generation bigint,
  p_application_version text,
  p_check_count integer,
  p_run_fingerprint text,
  p_checks_fingerprint text,
  p_contract_version integer default 1
)
returns text
language sql
immutable
security definer
set search_path = ''
as $function$
  select public.leghevo_sha256_hex_v1(
    coalesce(p_run_id, 0)::text || '|' ||
    coalesce(lower(trim(p_environment_key)), '') || '|' ||
    coalesce(p_readiness_generation, 0)::text || '|' ||
    coalesce(trim(p_application_version), '') || '|' ||
    coalesce(p_check_count, 0)::text || '|' ||
    coalesce(lower(trim(p_run_fingerprint)), '') || '|' ||
    coalesce(lower(trim(p_checks_fingerprint)), '') || '|' ||
    coalesce(p_contract_version, 0)::text
  );
$function$;

create or replace function public.compute_leghevo_production_readiness_event_fingerprint_v1(
  p_environment_key text,
  p_event_type text,
  p_readiness_generation bigint,
  p_run_id bigint,
  p_certificate_id bigint,
  p_reason_code text,
  p_details jsonb
)
returns text
language sql
immutable
security definer
set search_path = ''
as $function$
  select public.leghevo_sha256_hex_v1(
    coalesce(lower(trim(p_environment_key)), '') || '|' ||
    coalesce(lower(trim(p_event_type)), '') || '|' ||
    coalesce(p_readiness_generation, 0)::text || '|' ||
    coalesce(p_run_id, 0)::text || '|' ||
    coalesce(p_certificate_id, 0)::text || '|' ||
    coalesce(lower(trim(p_reason_code)), '') || '|' ||
    coalesce(p_details, '{}'::jsonb)::text
  );
$function$;

create table if not exists public.leghevo_production_readiness_runs (
  id bigint generated by default as identity primary key,
  environment_key text not null,
  readiness_generation bigint not null,
  request_id uuid not null unique,
  active_release_version text not null,
  release_generation bigint not null,
  rollout_generation bigint not null,
  telemetry_generation bigint not null,
  outbox_sequence bigint not null,
  consumer_sequence bigint not null,
  audit_sequence bigint not null,
  checkpoint_generation bigint not null,
  backup_generation bigint not null,
  service_return_generation bigint not null,
  required_check_count integer not null default 10,
  snapshot_fingerprint text not null,
  run_fingerprint text not null,
  status text not null default 'evaluating',
  reason_code text not null,
  contract_version integer not null default 1,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  created_by uuid,
  constraint leghevo_production_readiness_run_environment_check
    check (environment_key in ('production','staging')),
  constraint leghevo_production_readiness_run_generation_check
    check (readiness_generation > 0),
  constraint leghevo_production_readiness_run_check_count_check
    check (required_check_count = 10),
  constraint leghevo_production_readiness_run_status_check
    check (status in ('evaluating','certified','affected')),
  constraint leghevo_production_readiness_run_fingerprint_check
    check (run_fingerprint ~ '^[0-9a-f]{64}$' and snapshot_fingerprint ~ '^[0-9a-f]{64}$'),
  constraint leghevo_production_readiness_run_generation_unique
    unique (environment_key, readiness_generation)
);

create table if not exists public.leghevo_production_readiness_checks (
  id bigint generated by default as identity primary key,
  run_id bigint not null references public.leghevo_production_readiness_runs(id) on delete restrict,
  check_key text not null,
  check_ordinal integer not null,
  component_fingerprint text not null,
  component_sequence bigint not null default 0,
  status text not null,
  reason_code text not null,
  details jsonb not null default '{}'::jsonb,
  check_fingerprint text not null,
  checked_at timestamptz not null default now(),
  checked_by uuid,
  constraint leghevo_production_readiness_check_key_check
    check (check_key in (
      'application_integrity','release_contract','rollout_completion',
      'operational_telemetry','transactional_outbox','consumer_delivery',
      'delivery_audit','disaster_recovery','physical_backup','service_return'
    )),
  constraint leghevo_production_readiness_check_ordinal_check
    check (check_ordinal between 1 and 10),
  constraint leghevo_production_readiness_check_status_check
    check (status in ('passed','failed')),
  constraint leghevo_production_readiness_check_fingerprint_check
    check (component_fingerprint ~ '^[0-9a-f]{64}$' and check_fingerprint ~ '^[0-9a-f]{64}$'),
  constraint leghevo_production_readiness_run_check_unique unique (run_id, check_key),
  constraint leghevo_production_readiness_run_ordinal_unique unique (run_id, check_ordinal)
);

create table if not exists public.leghevo_production_readiness_certificates (
  id bigint generated by default as identity primary key,
  run_id bigint not null unique references public.leghevo_production_readiness_runs(id) on delete restrict,
  environment_key text not null,
  readiness_generation bigint not null,
  request_id uuid not null unique,
  application_version text not null,
  check_count integer not null,
  run_fingerprint text not null,
  checks_fingerprint text not null,
  certificate_fingerprint text not null unique,
  status text not null default 'certified',
  reason_code text not null,
  contract_version integer not null default 1,
  details jsonb not null default '{}'::jsonb,
  certified_at timestamptz not null default now(),
  certified_by uuid,
  constraint leghevo_production_readiness_certificate_environment_check
    check (environment_key in ('production','staging')),
  constraint leghevo_production_readiness_certificate_check_count_check
    check (check_count = 10),
  constraint leghevo_production_readiness_certificate_status_check
    check (status = 'certified'),
  constraint leghevo_production_readiness_certificate_fingerprint_check
    check (run_fingerprint ~ '^[0-9a-f]{64}$'
      and checks_fingerprint ~ '^[0-9a-f]{64}$'
      and certificate_fingerprint ~ '^[0-9a-f]{64}$'),
  constraint leghevo_production_readiness_certificate_generation_unique
    unique (environment_key, readiness_generation)
);

create table if not exists public.leghevo_production_readiness_heads (
  environment_key text primary key,
  readiness_generation bigint not null,
  run_id bigint not null references public.leghevo_production_readiness_runs(id) on delete restrict,
  certificate_id bigint references public.leghevo_production_readiness_certificates(id) on delete restrict,
  mode text not null,
  status text not null,
  go_live_allowed boolean not null default false,
  active_release_version text not null,
  reason_code text not null,
  revision bigint not null default 1,
  state_fingerprint text not null,
  certified_at timestamptz,
  affected_at timestamptz,
  updated_at timestamptz not null default now(),
  constraint leghevo_production_readiness_head_environment_check
    check (environment_key in ('production','staging')),
  constraint leghevo_production_readiness_head_mode_check
    check (mode in ('pending','active','affected')),
  constraint leghevo_production_readiness_head_status_check
    check (status in ('pending','certified','revalidated','affected')),
  constraint leghevo_production_readiness_head_fingerprint_check
    check (state_fingerprint ~ '^[0-9a-f]{64}$')
);

create table if not exists public.leghevo_production_readiness_events (
  id bigint generated by default as identity primary key,
  environment_key text not null,
  event_type text not null,
  readiness_generation bigint not null,
  run_id bigint references public.leghevo_production_readiness_runs(id) on delete restrict,
  certificate_id bigint references public.leghevo_production_readiness_certificates(id) on delete restrict,
  reason_code text not null,
  details jsonb not null default '{}'::jsonb,
  event_fingerprint text not null,
  created_at timestamptz not null default now(),
  created_by uuid,
  constraint leghevo_production_readiness_event_environment_check
    check (environment_key in ('production','staging')),
  constraint leghevo_production_readiness_event_type_check
    check (event_type in ('certified','affected','revalidated')),
  constraint leghevo_production_readiness_event_fingerprint_check
    check (event_fingerprint ~ '^[0-9a-f]{64}$')
);

create index if not exists leghevo_production_readiness_runs_environment_generation_idx
  on public.leghevo_production_readiness_runs(environment_key, readiness_generation desc);
create index if not exists leghevo_production_readiness_checks_run_ordinal_idx
  on public.leghevo_production_readiness_checks(run_id, check_ordinal);
create index if not exists leghevo_production_readiness_certificates_environment_generation_idx
  on public.leghevo_production_readiness_certificates(environment_key, readiness_generation desc);
create index if not exists leghevo_production_readiness_events_environment_created_idx
  on public.leghevo_production_readiness_events(environment_key, created_at desc);

alter table public.leghevo_production_readiness_runs enable row level security;
alter table public.leghevo_production_readiness_checks enable row level security;
alter table public.leghevo_production_readiness_certificates enable row level security;
alter table public.leghevo_production_readiness_heads enable row level security;
alter table public.leghevo_production_readiness_events enable row level security;

drop policy if exists leghevo_production_readiness_runs_authenticated_read
  on public.leghevo_production_readiness_runs;
create policy leghevo_production_readiness_runs_authenticated_read
  on public.leghevo_production_readiness_runs for select to authenticated using (true);
drop policy if exists leghevo_production_readiness_checks_authenticated_read
  on public.leghevo_production_readiness_checks;
create policy leghevo_production_readiness_checks_authenticated_read
  on public.leghevo_production_readiness_checks for select to authenticated using (true);
drop policy if exists leghevo_production_readiness_certificates_authenticated_read
  on public.leghevo_production_readiness_certificates;
create policy leghevo_production_readiness_certificates_authenticated_read
  on public.leghevo_production_readiness_certificates for select to authenticated using (true);
drop policy if exists leghevo_production_readiness_heads_authenticated_read
  on public.leghevo_production_readiness_heads;
create policy leghevo_production_readiness_heads_authenticated_read
  on public.leghevo_production_readiness_heads for select to authenticated using (true);
drop policy if exists leghevo_production_readiness_events_authenticated_read
  on public.leghevo_production_readiness_events;
create policy leghevo_production_readiness_events_authenticated_read
  on public.leghevo_production_readiness_events for select to authenticated using (true);

revoke all on table public.leghevo_production_readiness_runs from public, anon, authenticated, service_role;
revoke all on table public.leghevo_production_readiness_checks from public, anon, authenticated, service_role;
revoke all on table public.leghevo_production_readiness_certificates from public, anon, authenticated, service_role;
revoke all on table public.leghevo_production_readiness_heads from public, anon, authenticated, service_role;
revoke all on table public.leghevo_production_readiness_events from public, anon, authenticated, service_role;
grant select on table public.leghevo_production_readiness_runs to authenticated;
grant select on table public.leghevo_production_readiness_checks to authenticated;
grant select on table public.leghevo_production_readiness_certificates to authenticated;
grant select on table public.leghevo_production_readiness_heads to authenticated;
grant select on table public.leghevo_production_readiness_events to authenticated;

create or replace function public.guard_leghevo_production_readiness_immutable_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if current_setting('leghevo.production_readiness_context', true) <> 'allowed' then
    raise exception 'Registro production readiness protetto: scrittura diretta vietata.';
  end if;
  if tg_op in ('UPDATE','DELETE') then
    raise exception 'Registro production readiness immutabile.';
  end if;
  return new;
end;
$function$;

create or replace function public.guard_leghevo_production_readiness_head_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if current_setting('leghevo.production_readiness_context', true) <> 'allowed' then
    raise exception 'Testa production readiness protetta: scrittura diretta vietata.';
  end if;
  if tg_op = 'DELETE' then
    raise exception 'Testa production readiness non cancellabile.';
  end if;
  if tg_op = 'UPDATE' and (
    new.readiness_generation < old.readiness_generation
    or new.revision <= old.revision
  ) then
    raise exception 'Regressione della testa production readiness vietata.';
  end if;
  return new;
end;
$function$;

drop trigger if exists leghevo_production_readiness_runs_guard
  on public.leghevo_production_readiness_runs;
create trigger leghevo_production_readiness_runs_guard
before insert or update or delete on public.leghevo_production_readiness_runs
for each row execute function public.guard_leghevo_production_readiness_immutable_v1();
alter table public.leghevo_production_readiness_runs
  enable always trigger leghevo_production_readiness_runs_guard;

drop trigger if exists leghevo_production_readiness_checks_guard
  on public.leghevo_production_readiness_checks;
create trigger leghevo_production_readiness_checks_guard
before insert or update or delete on public.leghevo_production_readiness_checks
for each row execute function public.guard_leghevo_production_readiness_immutable_v1();
alter table public.leghevo_production_readiness_checks
  enable always trigger leghevo_production_readiness_checks_guard;

drop trigger if exists leghevo_production_readiness_certificates_guard
  on public.leghevo_production_readiness_certificates;
create trigger leghevo_production_readiness_certificates_guard
before insert or update or delete on public.leghevo_production_readiness_certificates
for each row execute function public.guard_leghevo_production_readiness_immutable_v1();
alter table public.leghevo_production_readiness_certificates
  enable always trigger leghevo_production_readiness_certificates_guard;

drop trigger if exists leghevo_production_readiness_events_guard
  on public.leghevo_production_readiness_events;
create trigger leghevo_production_readiness_events_guard
before insert or update or delete on public.leghevo_production_readiness_events
for each row execute function public.guard_leghevo_production_readiness_immutable_v1();
alter table public.leghevo_production_readiness_events
  enable always trigger leghevo_production_readiness_events_guard;

drop trigger if exists leghevo_production_readiness_heads_guard
  on public.leghevo_production_readiness_heads;
create trigger leghevo_production_readiness_heads_guard
before insert or update or delete on public.leghevo_production_readiness_heads
for each row execute function public.guard_leghevo_production_readiness_head_v1();
alter table public.leghevo_production_readiness_heads
  enable always trigger leghevo_production_readiness_heads_guard;

revoke all on function public.guard_leghevo_production_readiness_immutable_v1()
  from public, anon, authenticated, service_role;
revoke all on function public.guard_leghevo_production_readiness_head_v1()
  from public, anon, authenticated, service_role;

create or replace function public.get_leghevo_production_readiness_snapshot_v1(
  p_environment_key text default 'production'
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_environment text := lower(trim(coalesce(p_environment_key,'production')));
  v_application jsonb;
  v_release jsonb;
  v_rollout jsonb;
  v_telemetry jsonb;
  v_outbox jsonb;
  v_consumer jsonb;
  v_audit jsonb;
  v_recovery jsonb;
  v_backup jsonb;
  v_return jsonb;
  v_checks jsonb;
  v_components jsonb;
  v_active_version text;
  v_healthy boolean;
  v_reason text;
  v_snapshot_fingerprint text;
begin
  if v_environment not in ('production','staging') then
    return jsonb_build_object('protected',false,'healthy',false,
      'reasonCode','production_readiness.invalid_environment','environment',v_environment);
  end if;

  v_application := public.get_leghevo_application_integrity_model_v1();
  v_release := public.get_leghevo_application_release_model_v1(v_environment);
  v_rollout := public.get_leghevo_application_rollout_model_v1(v_environment);
  v_telemetry := public.get_leghevo_operational_telemetry_model_v1(v_environment);
  v_outbox := public.get_leghevo_operational_outbox_model_v1(v_environment);
  v_consumer := public.get_leghevo_operational_consumer_delivery_model_v1(v_environment);
  v_audit := public.get_leghevo_operational_delivery_audit_model_v1(v_environment);
  v_recovery := public.get_leghevo_disaster_recovery_model_v1(v_environment);
  v_backup := public.get_leghevo_physical_backup_model_v1(v_environment);
  v_return := public.get_leghevo_service_return_model_v1(v_environment);
  v_active_version := v_release->>'activeVersion';

  v_checks := jsonb_build_object(
    'application_integrity',coalesce((v_application->>'protected')::boolean,false)
      and coalesce((v_application->>'healthy')::boolean,false),
    'release_contract',coalesce((v_release->>'protected')::boolean,false)
      and coalesce((v_release->>'healthy')::boolean,false)
      and v_active_version is not null,
    'rollout_completion',coalesce((v_rollout->>'protected')::boolean,false)
      and coalesce((v_rollout->>'healthy')::boolean,false)
      and coalesce((v_rollout->>'exposurePercentage')::integer,0)=100
      and coalesce(v_rollout->>'releaseVersion','')=coalesce(v_active_version,''),
    'operational_telemetry',coalesce((v_telemetry->>'protected')::boolean,false)
      and coalesce((v_telemetry->>'healthy')::boolean,false)
      and coalesce(v_telemetry->>'latestReleaseVersion','')=coalesce(v_active_version,''),
    'transactional_outbox',coalesce((v_outbox->>'protected')::boolean,false)
      and coalesce((v_outbox->>'healthy')::boolean,false),
    'consumer_delivery',coalesce((v_consumer->>'protected')::boolean,false)
      and coalesce((v_consumer->>'healthy')::boolean,false),
    'delivery_audit',coalesce((v_audit->>'protected')::boolean,false)
      and coalesce((v_audit->>'healthy')::boolean,false)
      and coalesce((v_audit->>'fresh')::boolean,false),
    'disaster_recovery',coalesce((v_recovery->>'protected')::boolean,false)
      and coalesce((v_recovery->>'healthy')::boolean,false)
      and coalesce((v_recovery->>'fresh')::boolean,false)
      and coalesce(v_recovery->>'activeVersion','')=coalesce(v_active_version,''),
    'physical_backup',coalesce((v_backup->>'protected')::boolean,false)
      and coalesce((v_backup->>'healthy')::boolean,false)
      and coalesce((v_backup->>'fresh')::boolean,false)
      and coalesce(v_backup->>'activeVersion','')=coalesce(v_active_version,''),
    'service_return',coalesce((v_return->>'protected')::boolean,false)
      and coalesce((v_return->>'healthy')::boolean,false)
      and coalesce((v_return->>'fresh')::boolean,false)
      and coalesce(v_return->>'mode','affected')='active'
      and coalesce(v_return->>'activeVersion','')=coalesce(v_active_version,'')
  );

  v_components := jsonb_build_object(
    'application_integrity',jsonb_build_object('fingerprint',public.leghevo_sha256_hex_v1(v_application::text),'sequence',0,'model',v_application),
    'release_contract',jsonb_build_object('fingerprint',public.leghevo_sha256_hex_v1(v_release::text),'sequence',coalesce((v_release->>'releaseGeneration')::bigint,0),'model',v_release),
    'rollout_completion',jsonb_build_object('fingerprint',public.leghevo_sha256_hex_v1(v_rollout::text),'sequence',coalesce((v_rollout->>'rolloutGeneration')::bigint,0),'model',v_rollout),
    'operational_telemetry',jsonb_build_object('fingerprint',public.leghevo_sha256_hex_v1(v_telemetry::text),'sequence',coalesce((v_telemetry->>'telemetryGeneration')::bigint,0),'model',v_telemetry),
    'transactional_outbox',jsonb_build_object('fingerprint',public.leghevo_sha256_hex_v1(v_outbox::text),'sequence',coalesce((v_outbox->>'lastSequence')::bigint,0),'model',v_outbox),
    'consumer_delivery',jsonb_build_object('fingerprint',public.leghevo_sha256_hex_v1(v_consumer::text),'sequence',coalesce((v_consumer->>'lastAcknowledgedSequence')::bigint,0),'model',v_consumer),
    'delivery_audit',jsonb_build_object('fingerprint',public.leghevo_sha256_hex_v1(v_audit::text),'sequence',coalesce((v_audit->>'auditedThroughSequence')::bigint,0),'model',v_audit),
    'disaster_recovery',jsonb_build_object('fingerprint',public.leghevo_sha256_hex_v1(v_recovery::text),'sequence',coalesce((v_recovery->>'checkpointGeneration')::bigint,0),'model',v_recovery),
    'physical_backup',jsonb_build_object('fingerprint',public.leghevo_sha256_hex_v1(v_backup::text),'sequence',coalesce((v_backup->>'backupGeneration')::bigint,0),'model',v_backup),
    'service_return',jsonb_build_object('fingerprint',public.leghevo_sha256_hex_v1(v_return::text),'sequence',coalesce((v_return->>'recoveryGeneration')::bigint,0),'model',v_return)
  );

  select count(*)=10 and count(*) filter(where item.value='true'::jsonb)=10
  into v_healthy
  from pg_catalog.jsonb_each(v_checks) item;

  v_reason := case
    when not coalesce((v_checks->>'application_integrity')::boolean,false) then 'production_readiness.application_integrity'
    when not coalesce((v_checks->>'release_contract')::boolean,false) then 'production_readiness.release_contract'
    when not coalesce((v_checks->>'rollout_completion')::boolean,false) then 'production_readiness.rollout_completion'
    when not coalesce((v_checks->>'operational_telemetry')::boolean,false) then 'production_readiness.operational_telemetry'
    when not coalesce((v_checks->>'transactional_outbox')::boolean,false) then 'production_readiness.transactional_outbox'
    when not coalesce((v_checks->>'consumer_delivery')::boolean,false) then 'production_readiness.consumer_delivery'
    when not coalesce((v_checks->>'delivery_audit')::boolean,false) then 'production_readiness.delivery_audit'
    when not coalesce((v_checks->>'disaster_recovery')::boolean,false) then 'production_readiness.disaster_recovery'
    when not coalesce((v_checks->>'physical_backup')::boolean,false) then 'production_readiness.physical_backup'
    when not coalesce((v_checks->>'service_return')::boolean,false) then 'production_readiness.service_return'
    else 'production_readiness.ready' end;

  v_snapshot_fingerprint := public.leghevo_sha256_hex_v1(
    v_environment||'|'||coalesce(v_active_version,'')||'|'||v_checks::text||'|'||v_components::text);

  return jsonb_build_object(
    'protected',v_healthy,'healthy',v_healthy,'reasonCode',v_reason,
    'environment',v_environment,'activeVersion',v_active_version,
    'releaseGeneration',coalesce((v_release->>'releaseGeneration')::bigint,0),
    'rolloutGeneration',coalesce((v_rollout->>'rolloutGeneration')::bigint,0),
    'telemetryGeneration',coalesce((v_telemetry->>'telemetryGeneration')::bigint,0),
    'outboxSequence',coalesce((v_outbox->>'lastSequence')::bigint,0),
    'consumerSequence',coalesce((v_consumer->>'lastAcknowledgedSequence')::bigint,0),
    'auditSequence',coalesce((v_audit->>'auditedThroughSequence')::bigint,0),
    'checkpointGeneration',coalesce((v_recovery->>'checkpointGeneration')::bigint,0),
    'backupGeneration',coalesce((v_backup->>'backupGeneration')::bigint,0),
    'serviceReturnGeneration',coalesce((v_return->>'recoveryGeneration')::bigint,0),
    'requiredCheckCount',10,'passedCheckCount',(select count(*) from pg_catalog.jsonb_each(v_checks) item where item.value='true'::jsonb),
    'checks',v_checks,'components',v_components,'snapshotFingerprint',v_snapshot_fingerprint,
    'checkedAt',now());
end;
$function$;

revoke all on function public.get_leghevo_production_readiness_snapshot_v1(text)
  from public, anon, authenticated;
grant execute on function public.get_leghevo_production_readiness_snapshot_v1(text)
  to service_role;

create or replace function public.certify_leghevo_production_readiness_v1(
  p_environment_key text,
  p_request_id uuid,
  p_reason_code text,
  p_details jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_environment text:=lower(trim(coalesce(p_environment_key,'')));
  v_reason text:=lower(trim(coalesce(p_reason_code,'production_readiness.certified')));
  v_details jsonb:=coalesce(p_details,'{}'::jsonb);
  v_snapshot jsonb;
  v_generation bigint;
  v_run public.leghevo_production_readiness_runs%rowtype;
  v_certificate public.leghevo_production_readiness_certificates%rowtype;
  v_checks_fingerprint text;
  v_event_fingerprint text;
  v_existing public.leghevo_production_readiness_certificates%rowtype;
  v_item record;
  v_component jsonb;
  v_status text;
  v_ordinal integer;
begin
  if v_environment not in ('production','staging') or p_request_id is null or v_reason='' then
    raise exception 'Parametri certificazione production readiness non validi.';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('leghevo.production_readiness.'||v_environment,0));

  select certificate.* into v_existing
  from public.leghevo_production_readiness_certificates certificate
  where certificate.request_id=p_request_id;
  if found then
    return jsonb_build_object('certificateId',v_existing.id,'readinessGeneration',v_existing.readiness_generation,
      'status','certified','idempotent',true);
  end if;

  v_snapshot:=public.get_leghevo_production_readiness_snapshot_v1(v_environment);
  if not coalesce((v_snapshot->>'healthy')::boolean,false)
    or coalesce((v_snapshot->>'passedCheckCount')::integer,0)<>10 then
    raise exception 'Certificazione production readiness bloccata: %.',v_snapshot;
  end if;

  select coalesce(max(run.readiness_generation),0)+1 into v_generation
  from public.leghevo_production_readiness_runs run
  where run.environment_key=v_environment;

  perform pg_catalog.set_config('leghevo.production_readiness_context','allowed',true);
  insert into public.leghevo_production_readiness_runs(
    environment_key,readiness_generation,request_id,active_release_version,
    release_generation,rollout_generation,telemetry_generation,outbox_sequence,
    consumer_sequence,audit_sequence,checkpoint_generation,backup_generation,
    service_return_generation,required_check_count,snapshot_fingerprint,run_fingerprint,
    status,reason_code,contract_version,details,created_by
  ) values (
    v_environment,v_generation,p_request_id,v_snapshot->>'activeVersion',
    (v_snapshot->>'releaseGeneration')::bigint,(v_snapshot->>'rolloutGeneration')::bigint,
    (v_snapshot->>'telemetryGeneration')::bigint,(v_snapshot->>'outboxSequence')::bigint,
    (v_snapshot->>'consumerSequence')::bigint,(v_snapshot->>'auditSequence')::bigint,
    (v_snapshot->>'checkpointGeneration')::bigint,(v_snapshot->>'backupGeneration')::bigint,
    (v_snapshot->>'serviceReturnGeneration')::bigint,10,v_snapshot->>'snapshotFingerprint',
    public.compute_leghevo_production_readiness_run_fingerprint_v1(
      v_environment,v_generation,v_snapshot->>'activeVersion',
      (v_snapshot->>'releaseGeneration')::bigint,(v_snapshot->>'rolloutGeneration')::bigint,
      (v_snapshot->>'telemetryGeneration')::bigint,(v_snapshot->>'outboxSequence')::bigint,
      (v_snapshot->>'consumerSequence')::bigint,(v_snapshot->>'auditSequence')::bigint,
      (v_snapshot->>'checkpointGeneration')::bigint,(v_snapshot->>'backupGeneration')::bigint,
      (v_snapshot->>'serviceReturnGeneration')::bigint,v_snapshot->>'snapshotFingerprint',1),
    'certified',v_reason,1,v_details,auth.uid()
  ) returning * into v_run;

  for v_item in
    select * from (values
      ('application_integrity'::text,1),('release_contract',2),('rollout_completion',3),
      ('operational_telemetry',4),('transactional_outbox',5),('consumer_delivery',6),
      ('delivery_audit',7),('disaster_recovery',8),('physical_backup',9),('service_return',10)
    ) check_list(check_key,check_ordinal)
    order by check_ordinal
  loop
    v_component:=v_snapshot->'components'->v_item.check_key;
    v_status:=case when coalesce((v_snapshot->'checks'->>v_item.check_key)::boolean,false)
      then 'passed' else 'failed' end;
    insert into public.leghevo_production_readiness_checks(
      run_id,check_key,check_ordinal,component_fingerprint,component_sequence,
      status,reason_code,details,check_fingerprint,checked_by
    ) values (
      v_run.id,v_item.check_key,v_item.check_ordinal,v_component->>'fingerprint',
      coalesce((v_component->>'sequence')::bigint,0),v_status,
      case when v_status='passed' then 'production_readiness.check_passed' else 'production_readiness.check_failed' end,
      jsonb_build_object('model',v_component->'model'),
      public.compute_leghevo_production_readiness_check_fingerprint_v1(
        v_run.id,v_item.check_key,v_item.check_ordinal,v_component->>'fingerprint',
        coalesce((v_component->>'sequence')::bigint,0),v_status,jsonb_build_object('model',v_component->'model')),
      auth.uid());
  end loop;

  select public.leghevo_sha256_hex_v1(
    string_agg(check_row.check_key||'|'||check_row.check_fingerprint,';' order by check_row.check_ordinal))
  into v_checks_fingerprint
  from public.leghevo_production_readiness_checks check_row
  where check_row.run_id=v_run.id;

  insert into public.leghevo_production_readiness_certificates(
    run_id,environment_key,readiness_generation,request_id,application_version,check_count,
    run_fingerprint,checks_fingerprint,certificate_fingerprint,status,reason_code,
    contract_version,details,certified_by
  ) values (
    v_run.id,v_environment,v_generation,p_request_id,v_run.active_release_version,10,
    v_run.run_fingerprint,v_checks_fingerprint,
    public.compute_leghevo_production_readiness_certificate_fingerprint_v1(
      v_run.id,v_environment,v_generation,v_run.active_release_version,10,
      v_run.run_fingerprint,v_checks_fingerprint,1),
    'certified',v_reason,1,v_details,auth.uid()
  ) returning * into v_certificate;


  insert into public.leghevo_production_readiness_heads(
    environment_key,readiness_generation,run_id,certificate_id,mode,status,
    go_live_allowed,active_release_version,reason_code,revision,state_fingerprint,
    certified_at,affected_at,updated_at
  ) values (
    v_environment,v_generation,v_run.id,v_certificate.id,'active','certified',true,
    v_run.active_release_version,v_reason,1,
    public.leghevo_sha256_hex_v1(v_environment||'|'||v_generation::text||'|'||v_run.id::text||'|'||v_certificate.id::text||'|active|1'),
    now(),null,now()
  ) on conflict(environment_key) do update set
    readiness_generation=excluded.readiness_generation,run_id=excluded.run_id,
    certificate_id=excluded.certificate_id,mode='active',status='certified',
    go_live_allowed=true,active_release_version=excluded.active_release_version,
    reason_code=excluded.reason_code,revision=public.leghevo_production_readiness_heads.revision+1,
    state_fingerprint=public.leghevo_sha256_hex_v1(
      excluded.environment_key||'|'||excluded.readiness_generation::text||'|'||excluded.run_id::text||'|'||excluded.certificate_id::text||'|active|'||(public.leghevo_production_readiness_heads.revision+1)::text),
    certified_at=now(),affected_at=null,updated_at=now();

  v_event_fingerprint:=public.compute_leghevo_production_readiness_event_fingerprint_v1(
    v_environment,'certified',v_generation,v_run.id,v_certificate.id,v_reason,
    jsonb_build_object('checkCount',10,'activeVersion',v_run.active_release_version));
  insert into public.leghevo_production_readiness_events(
    environment_key,event_type,readiness_generation,run_id,certificate_id,
    reason_code,details,event_fingerprint,created_by
  ) values (
    v_environment,'certified',v_generation,v_run.id,v_certificate.id,v_reason,
    jsonb_build_object('checkCount',10,'activeVersion',v_run.active_release_version),
    v_event_fingerprint,auth.uid());

  perform pg_catalog.set_config('leghevo.production_readiness_context','',true);
  return jsonb_build_object('certificateId',v_certificate.id,'readinessGeneration',v_generation,
    'status','certified','goLiveAllowed',true,'idempotent',false);
exception when others then
  perform pg_catalog.set_config('leghevo.production_readiness_context','',true);
  raise;
end;
$function$;

revoke all on function public.certify_leghevo_production_readiness_v1(text,uuid,text,jsonb)
  from public, anon, authenticated;
grant execute on function public.certify_leghevo_production_readiness_v1(text,uuid,text,jsonb)
  to service_role;

create or replace function public.get_leghevo_production_readiness_model_v1(
  p_environment_key text default 'production'
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_environment text:=lower(trim(coalesce(p_environment_key,'production')));
  v_head public.leghevo_production_readiness_heads%rowtype;
  v_run public.leghevo_production_readiness_runs%rowtype;
  v_certificate public.leghevo_production_readiness_certificates%rowtype;
  v_snapshot jsonb;
  v_check_count integer:=0;
  v_failed_count integer:=0;
  v_checks_fingerprint text;
  v_run_stable boolean:=false;
  v_certificate_stable boolean:=false;
  v_fresh boolean:=false;
  v_protected boolean:=false;
  v_healthy boolean:=false;
  v_status text:='affected';
  v_reason text:='production_readiness.missing';
begin
  select head.* into v_head from public.leghevo_production_readiness_heads head
  where head.environment_key=v_environment;
  if not found then
    return jsonb_build_object('protected',false,'healthy',false,'fresh',false,
      'status','pending','reasonCode','production_readiness.missing','environment',v_environment,
      'readinessGeneration',0,'checkCount',0,'requiredCheckCount',10,
      'goLiveAllowed',false,'fingerprintStable',false,'checkedAt',now());
  end if;
  select run.* into v_run from public.leghevo_production_readiness_runs run where run.id=v_head.run_id;
  if v_head.certificate_id is not null then
    select certificate.* into v_certificate
    from public.leghevo_production_readiness_certificates certificate
    where certificate.id=v_head.certificate_id;
  end if;
  select count(*),count(*) filter(where check_row.status<>'passed'),
    public.leghevo_sha256_hex_v1(string_agg(check_row.check_key||'|'||check_row.check_fingerprint,';' order by check_row.check_ordinal))
  into v_check_count,v_failed_count,v_checks_fingerprint
  from public.leghevo_production_readiness_checks check_row where check_row.run_id=v_run.id;

  v_run_stable:=v_run.run_fingerprint=public.compute_leghevo_production_readiness_run_fingerprint_v1(
    v_run.environment_key,v_run.readiness_generation,v_run.active_release_version,
    v_run.release_generation,v_run.rollout_generation,v_run.telemetry_generation,
    v_run.outbox_sequence,v_run.consumer_sequence,v_run.audit_sequence,
    v_run.checkpoint_generation,v_run.backup_generation,v_run.service_return_generation,
    v_run.snapshot_fingerprint,v_run.contract_version);
  v_certificate_stable:=v_certificate.id is not null
    and v_certificate.checks_fingerprint=v_checks_fingerprint
    and v_certificate.certificate_fingerprint=
      public.compute_leghevo_production_readiness_certificate_fingerprint_v1(
        v_certificate.run_id,v_certificate.environment_key,v_certificate.readiness_generation,
        v_certificate.application_version,v_certificate.check_count,v_certificate.run_fingerprint,
        v_certificate.checks_fingerprint,v_certificate.contract_version);
  v_snapshot:=public.get_leghevo_production_readiness_snapshot_v1(v_environment);
  v_fresh:=coalesce((v_snapshot->>'healthy')::boolean,false)
    and coalesce(v_snapshot->>'activeVersion','')=v_run.active_release_version;
  v_protected:=v_run_stable and v_certificate_stable and v_check_count=10 and v_failed_count=0
    and v_head.mode='active' and v_head.status in ('certified','revalidated')
    and v_head.go_live_allowed;
  v_healthy:=v_protected and v_fresh;
  v_status:=case when v_healthy then 'certified'
    when v_head.mode='pending' then 'pending' else 'affected' end;
  v_reason:=case
    when not v_run_stable then 'production_readiness.run_fingerprint_changed'
    when not v_certificate_stable then 'production_readiness.certificate_fingerprint_changed'
    when v_check_count<>10 or v_failed_count>0 then 'production_readiness.checks_incomplete'
    when v_head.mode='affected' or v_head.status='affected' then v_head.reason_code
    when not v_fresh then coalesce(v_snapshot->>'reasonCode','production_readiness.stale')
    else 'production_readiness.certified' end;
  return jsonb_build_object(
    'protected',v_protected,'healthy',v_healthy,'fresh',v_fresh,'status',v_status,
    'reasonCode',v_reason,'environment',v_environment,'readinessGeneration',v_head.readiness_generation,
    'runId',v_run.id,'certificateId',v_certificate.id,'activeVersion',v_run.active_release_version,
    'checkCount',v_check_count,'requiredCheckCount',10,'failedCheckCount',v_failed_count,
    'goLiveAllowed',v_head.go_live_allowed,'fingerprintStable',v_run_stable and v_certificate_stable,
    'certifiedAt',v_head.certified_at,'affectedAt',v_head.affected_at,
    'currentSnapshot',v_snapshot,'checkedAt',now());
end;
$function$;

revoke all on function public.get_leghevo_production_readiness_model_v1(text) from public, anon;
grant execute on function public.get_leghevo_production_readiness_model_v1(text)
  to authenticated, service_role;

create or replace function public.reconcile_leghevo_production_readiness_v1(
  p_environment_key text,
  p_reason_code text default 'production_readiness.dependency_changed'
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_environment text:=lower(trim(coalesce(p_environment_key,'production')));
  v_reason text:=lower(trim(coalesce(p_reason_code,'production_readiness.dependency_changed')));
  v_head public.leghevo_production_readiness_heads%rowtype;
  v_run public.leghevo_production_readiness_runs%rowtype;
  v_snapshot jsonb;
  v_event_type text;
  v_event_fingerprint text;
begin
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('leghevo.production_readiness.'||v_environment,0));
  select head.* into v_head from public.leghevo_production_readiness_heads head
  where head.environment_key=v_environment for update;
  if not found then return jsonb_build_object('applicable',false,'changed',false); end if;
  select run.* into v_run from public.leghevo_production_readiness_runs run where run.id=v_head.run_id;
  v_snapshot:=public.get_leghevo_production_readiness_snapshot_v1(v_environment);
  if coalesce((v_snapshot->>'healthy')::boolean,false)
    and coalesce(v_snapshot->>'activeVersion','')=v_run.active_release_version then
    if v_head.mode<>'affected' and v_head.status<>'affected' then
      return jsonb_build_object('applicable',true,'changed',false,'status',v_head.status);
    end if;
    v_event_type:='revalidated';
    perform pg_catalog.set_config('leghevo.production_readiness_context','allowed',true);
    update public.leghevo_production_readiness_heads set
      mode='active',status='revalidated',go_live_allowed=true,reason_code='production_readiness.revalidated',
      revision=revision+1,state_fingerprint=public.leghevo_sha256_hex_v1(
        environment_key||'|'||readiness_generation::text||'|'||run_id::text||'|'||certificate_id::text||'|active|'||(revision+1)::text),
      affected_at=null,updated_at=now()
    where environment_key=v_environment returning * into v_head;
  else
    if v_head.mode='affected' and v_head.status='affected' then
      return jsonb_build_object('applicable',true,'changed',false,'status','affected');
    end if;
    v_event_type:='affected';
    perform pg_catalog.set_config('leghevo.production_readiness_context','allowed',true);
    update public.leghevo_production_readiness_heads set
      mode='affected',status='affected',go_live_allowed=false,reason_code=v_reason,
      revision=revision+1,state_fingerprint=public.leghevo_sha256_hex_v1(
        environment_key||'|'||readiness_generation::text||'|'||run_id::text||'|'||certificate_id::text||'|affected|'||(revision+1)::text),
      affected_at=coalesce(affected_at,now()),updated_at=now()
    where environment_key=v_environment returning * into v_head;
  end if;
  v_event_fingerprint:=public.compute_leghevo_production_readiness_event_fingerprint_v1(
    v_environment,v_event_type,v_head.readiness_generation,v_head.run_id,v_head.certificate_id,
    v_head.reason_code,jsonb_build_object('currentSnapshot',v_snapshot));
  insert into public.leghevo_production_readiness_events(
    environment_key,event_type,readiness_generation,run_id,certificate_id,reason_code,
    details,event_fingerprint,created_by
  ) values (
    v_environment,v_event_type,v_head.readiness_generation,v_head.run_id,v_head.certificate_id,
    v_head.reason_code,jsonb_build_object('currentSnapshot',v_snapshot),v_event_fingerprint,auth.uid());
  perform pg_catalog.set_config('leghevo.production_readiness_context','',true);
  return jsonb_build_object('applicable',true,'changed',true,'status',v_head.status,
    'reasonCode',v_head.reason_code,'revision',v_head.revision);
exception when others then
  perform pg_catalog.set_config('leghevo.production_readiness_context','',true);
  raise;
end;
$function$;

revoke all on function public.reconcile_leghevo_production_readiness_v1(text,text)
  from public, anon, authenticated;
grant execute on function public.reconcile_leghevo_production_readiness_v1(text,text)
  to service_role;

create or replace function public.reconcile_leghevo_production_readiness_after_event_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  perform public.reconcile_leghevo_production_readiness_v1(new.environment_key,'production_readiness.dependency_changed');
  return new;
end;
$function$;
revoke all on function public.reconcile_leghevo_production_readiness_after_event_v1()
  from public, anon, authenticated, service_role;

-- Trigger sulle dipendenze terminali. La riconciliazione non modifica mai i certificati.
do $dependency_triggers$
begin
  execute 'drop trigger if exists leghevo_production_readiness_after_release_event on public.leghevo_application_release_events';
  execute 'create trigger leghevo_production_readiness_after_release_event after insert on public.leghevo_application_release_events for each row execute function public.reconcile_leghevo_production_readiness_after_event_v1()';
  execute 'alter table public.leghevo_application_release_events enable always trigger leghevo_production_readiness_after_release_event';
  execute 'drop trigger if exists leghevo_production_readiness_after_rollout_event on public.leghevo_application_rollout_events';
  execute 'create trigger leghevo_production_readiness_after_rollout_event after insert on public.leghevo_application_rollout_events for each row execute function public.reconcile_leghevo_production_readiness_after_event_v1()';
  execute 'alter table public.leghevo_application_rollout_events enable always trigger leghevo_production_readiness_after_rollout_event';
  execute 'drop trigger if exists leghevo_production_readiness_after_telemetry_event on public.leghevo_operational_telemetry_events';
  execute 'create trigger leghevo_production_readiness_after_telemetry_event after insert on public.leghevo_operational_telemetry_events for each row execute function public.reconcile_leghevo_production_readiness_after_event_v1()';
  execute 'alter table public.leghevo_operational_telemetry_events enable always trigger leghevo_production_readiness_after_telemetry_event';
  execute 'drop trigger if exists leghevo_production_readiness_after_audit_event on public.leghevo_operational_delivery_audit_events';
  execute 'create trigger leghevo_production_readiness_after_audit_event after insert on public.leghevo_operational_delivery_audit_events for each row execute function public.reconcile_leghevo_production_readiness_after_event_v1()';
  execute 'alter table public.leghevo_operational_delivery_audit_events enable always trigger leghevo_production_readiness_after_audit_event';
  execute 'drop trigger if exists leghevo_production_readiness_after_recovery_event on public.leghevo_disaster_recovery_events';
  execute 'create trigger leghevo_production_readiness_after_recovery_event after insert on public.leghevo_disaster_recovery_events for each row execute function public.reconcile_leghevo_production_readiness_after_event_v1()';
  execute 'alter table public.leghevo_disaster_recovery_events enable always trigger leghevo_production_readiness_after_recovery_event';
  execute 'drop trigger if exists leghevo_production_readiness_after_backup_event on public.leghevo_physical_backup_events';
  execute 'create trigger leghevo_production_readiness_after_backup_event after insert on public.leghevo_physical_backup_events for each row execute function public.reconcile_leghevo_production_readiness_after_event_v1()';
  execute 'alter table public.leghevo_physical_backup_events enable always trigger leghevo_production_readiness_after_backup_event';
  execute 'drop trigger if exists leghevo_production_readiness_after_service_return_event on public.leghevo_service_return_events';
  execute 'create trigger leghevo_production_readiness_after_service_return_event after insert on public.leghevo_service_return_events for each row execute function public.reconcile_leghevo_production_readiness_after_event_v1()';
  execute 'alter table public.leghevo_service_return_events enable always trigger leghevo_production_readiness_after_service_return_event';
end;
$dependency_triggers$;

create or replace function public.assert_leghevo_production_readiness_v1(
  p_environment_key text,
  p_operation_key text
)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare v_model jsonb;
begin
  v_model:=public.get_leghevo_production_readiness_model_v1(p_environment_key);
  if not coalesce((v_model->>'protected')::boolean,false)
    or not coalesce((v_model->>'healthy')::boolean,false)
    or not coalesce((v_model->>'goLiveAllowed')::boolean,false) then
    raise exception 'Operazione % bloccata: production readiness non certificata. Dettaglio: %',
      coalesce(nullif(trim(p_operation_key),''),'unknown'),v_model;
  end if;
end;
$function$;
revoke all on function public.assert_leghevo_production_readiness_v1(text,text)
  from public, anon, authenticated;
grant execute on function public.assert_leghevo_production_readiness_v1(text,text)
  to service_role;

create or replace function public.promote_leghevo_application_rollout_v9(
  p_environment_key text,p_target_percentage integer,p_request_id uuid,p_reason_code text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
begin
  perform public.assert_leghevo_production_readiness_v1(p_environment_key,'rollout.promote');
  return public.promote_leghevo_application_rollout_v8(
    p_environment_key,p_target_percentage,p_request_id,p_reason_code);
end;
$function$;
revoke all on function public.promote_leghevo_application_rollout_v9(text,integer,uuid,text)
  from public, anon, authenticated;
grant execute on function public.promote_leghevo_application_rollout_v9(text,integer,uuid,text)
  to service_role;
revoke execute on function public.promote_leghevo_application_rollout_v8(text,integer,uuid,text)
  from service_role;

create or replace function public.get_leghevo_client_rollout_eligibility_v9(
  p_application_version text,p_bundle_fingerprint text,p_installation_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_base jsonb;
  v_readiness jsonb;
  v_eligible boolean;
  v_reason text;
begin
  v_base:=public.get_leghevo_client_rollout_eligibility_v8(
    p_application_version,p_bundle_fingerprint,p_installation_id);
  v_readiness:=public.get_leghevo_production_readiness_model_v1('production');
  v_eligible:=coalesce((v_base->>'rolloutEligible')::boolean,false)
    and coalesce((v_readiness->>'protected')::boolean,false)
    and coalesce((v_readiness->>'healthy')::boolean,false)
    and coalesce((v_readiness->>'goLiveAllowed')::boolean,false);
  v_reason:=case
    when not coalesce((v_base->>'compatible')::boolean,false) then coalesce(v_base->>'reasonCode','release.incompatible')
    when not coalesce((v_readiness->>'protected')::boolean,false) then 'production_readiness.not_protected'
    when not coalesce((v_readiness->>'fresh')::boolean,false) then 'production_readiness.stale'
    when v_readiness->>'status'='pending' then 'production_readiness.pending'
    when not coalesce((v_readiness->>'healthy')::boolean,false) then 'production_readiness.affected'
    else coalesce(v_base->>'reasonCode','release.compatible') end;
  return v_base||jsonb_build_object(
    'compatible',coalesce((v_base->>'compatible')::boolean,false) and v_eligible,
    'rolloutEligible',v_eligible,'reasonCode',v_reason,
    'productionReadinessProtected',coalesce((v_readiness->>'protected')::boolean,false),
    'productionReadinessHealthy',coalesce((v_readiness->>'healthy')::boolean,false),
    'productionReadinessFresh',coalesce((v_readiness->>'fresh')::boolean,false),
    'productionReadinessStatus',v_readiness->>'status',
    'productionReadinessGeneration',coalesce((v_readiness->>'readinessGeneration')::bigint,0),
    'productionReadinessCheckCount',coalesce((v_readiness->>'checkCount')::integer,0),
    'productionGoLiveAllowed',coalesce((v_readiness->>'goLiveAllowed')::boolean,false),
    'checkedAt',now());
end;
$function$;
revoke all on function public.get_leghevo_client_rollout_eligibility_v9(text,text,uuid) from public;
grant execute on function public.get_leghevo_client_rollout_eligibility_v9(text,text,uuid)
  to anon, authenticated;
revoke execute on function public.get_leghevo_client_rollout_eligibility_v8(text,text,uuid)
  from anon, authenticated;

create or replace function public.get_league_provider_sync_health_v42(p_league_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare v_base jsonb; v_readiness jsonb;
begin
  v_base:=public.get_league_provider_sync_health_v41(p_league_id);
  v_readiness:=public.get_leghevo_production_readiness_model_v1('production');
  return v_base||jsonb_build_object('applicationProductionReadiness',v_readiness,
    'healthy',coalesce((v_base->>'healthy')::boolean,false) and coalesce((v_readiness->>'healthy')::boolean,false),
    'protected',coalesce((v_base->>'protected')::boolean,false) and coalesce((v_readiness->>'protected')::boolean,false));
end;
$function$;
revoke all on function public.get_league_provider_sync_health_v42(uuid) from public, anon;
grant execute on function public.get_league_provider_sync_health_v42(uuid) to authenticated;

create or replace function public.get_league_season_state_v21(p_league_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare v_base jsonb; v_readiness jsonb;
begin
  v_base:=public.get_league_season_state_v20(p_league_id);
  v_readiness:=public.get_leghevo_production_readiness_model_v1('production');
  return v_base||jsonb_build_object('applicationProductionReadiness',v_readiness);
end;
$function$;
revoke all on function public.get_league_season_state_v21(uuid) from public, anon;
grant execute on function public.get_league_season_state_v21(uuid) to authenticated;

create or replace function public.get_league_management_state_v31(p_league_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare v_base jsonb; v_readiness jsonb; v_checks jsonb;
begin
  v_base:=public.get_league_management_state_v30(p_league_id);
  v_readiness:=public.get_leghevo_production_readiness_model_v1('production');
  v_checks:=coalesce(v_base->'checks','{}'::jsonb)||jsonb_build_object(
    'applicationProductionReadinessProtected',coalesce((v_readiness->>'protected')::boolean,false),
    'applicationProductionReadinessHealthy',coalesce((v_readiness->>'healthy')::boolean,false),
    'applicationProductionGoLiveAllowed',coalesce((v_readiness->>'goLiveAllowed')::boolean,false));
  return v_base||jsonb_build_object('applicationProductionReadiness',v_readiness,'checks',v_checks);
end;
$function$;
revoke all on function public.get_league_management_state_v31(uuid) from public, anon;
grant execute on function public.get_league_management_state_v31(uuid) to authenticated;

-- Helper temporaneo per drenare outbox/inbox durante il go-live v0.62.43.
create or replace function public.seed_leghevo_production_readiness_drain_v1(
  p_environment_key text,p_destination_key text,p_consumer_key text,p_consumer_generation bigint,
  p_consumer_fencing_token uuid,p_delivery_fencing_token uuid
)
returns integer
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_claim jsonb; v_item jsonb; v_count integer:=0; v_application_fingerprint text; v_outcome jsonb;
begin
  loop
    v_claim:=public.claim_leghevo_operational_outbox_v2(
      p_environment_key,p_destination_key,'leghevo-production-readiness-seed-worker',7,p_delivery_fencing_token,
      p_consumer_key,p_consumer_generation,p_consumer_fencing_token,200,120);
    exit when coalesce((v_claim->>'claimedCount')::integer,0)=0;
    for v_item in select item.value from pg_catalog.jsonb_array_elements(v_claim->'items') item loop
      v_application_fingerprint:=public.leghevo_sha256_hex_v1(
        p_destination_key||'|production-readiness-applied|'||(v_item->>'messageId')||'|'||(v_item->>'messageFingerprint'));
      v_outcome:=public.apply_leghevo_operational_consumer_message_v1(
        p_environment_key,(v_item->>'messageId')::bigint,p_destination_key,
        (v_item->>'deliveryGeneration')::bigint,'leghevo-production-readiness-seed-worker',7,p_delivery_fencing_token,
        p_consumer_key,p_consumer_generation,p_consumer_fencing_token,'leghevo-'||p_destination_key,
        v_application_fingerprint,gen_random_uuid(),jsonb_build_object('seedDelivery',true,'sourceMigration',147));
      v_count:=v_count+1;
    end loop;
  end loop;
  return v_count;
end;
$function$;
revoke all on function public.seed_leghevo_production_readiness_drain_v1(text,text,text,bigint,uuid,uuid)
  from public, anon, authenticated, service_role;

-- Certificazione della release finale e della readiness di produzione per il prototipo.
do $seed_release$
declare
  v_operations_consumer_token uuid:=gen_random_uuid();
  v_notification_consumer_token uuid:=gen_random_uuid();
  v_operations_delivery_token uuid:=gen_random_uuid();
  v_notification_delivery_token uuid:=gen_random_uuid();
  v_telemetry_token uuid:=gen_random_uuid();
  v_outcome jsonb;
  v_checkpoint jsonb;
  v_artifact jsonb;
  v_run jsonb;
  v_snapshot jsonb;
  v_run_id bigint;
  v_now timestamptz:=now();
  v_checksum text:=public.leghevo_sha256_hex_v1('leghevo-v0.62.43-production-readiness-artifact');
  v_provider_hash text:=public.leghevo_sha256_hex_v1('managed-backup-provider-production-v43');
  v_storage_hash text:=public.leghevo_sha256_hex_v1('external-vault-primary-v43');
  v_encryption_hash text:=public.leghevo_sha256_hex_v1('external-kms-key-reference-v43');
  v_actor_hash text:=public.leghevo_sha256_hex_v1('production-readiness-custodian');
  v_target_hash text:=public.leghevo_sha256_hex_v1('isolated-production-readiness-target');
  v_hash text;
  v_sequence bigint;
begin
  if exists(select 1 from public.leghevo_production_readiness_certificates certificate
    where certificate.application_version='0.62.43') then return; end if;

  v_outcome:=public.certify_leghevo_operational_consumer_v1(
    'production','operations_center','leghevo-operations-consumer',6,v_operations_consumer_token,
    '62700000-0000-4000-8000-000000000001'::uuid,
    jsonb_build_object('sourceMigration',147,'contract','production-readiness-v1'));
  v_outcome:=public.certify_leghevo_operational_consumer_v1(
    'production','notification_dispatch','leghevo-notification-consumer',6,v_notification_consumer_token,
    '62700000-0000-4000-8000-000000000002'::uuid,
    jsonb_build_object('sourceMigration',147,'contract','production-readiness-v1'));

  v_outcome:=public.certify_leghevo_application_release_v1(
    '0.62.43','9cd8380cc324b6292f0e74fd0b5a727171cacc137462942d6c69149304ca3e5e','0.62.42','0.62.43',
    '62700000-0000-4000-8000-000000000003'::uuid,
    jsonb_build_object('baseline',false,'sourceMigration',147,'productionReadiness',true));
  v_outcome:=public.certify_leghevo_application_rollout_v1(
    'production','0.62.43',100,100,500,3,100,
    '62700000-0000-4000-8000-000000000004'::uuid,
    jsonb_build_object('strategy','final-production-readiness','sourceMigration',147));
  v_outcome:=public.activate_leghevo_release_with_rollout_v1(
    'production','0.62.43','62700000-0000-4000-8000-000000000005'::uuid,
    '62700000-0000-4000-8000-000000000006'::uuid,'production_readiness.production_activation');
  v_outcome:=public.certify_leghevo_operational_telemetry_source_v1(
    'production','leghevo-production-observer',8,v_telemetry_token,
    '62700000-0000-4000-8000-000000000007'::uuid,
    jsonb_build_object('provider','leghevo-runtime','sourceMigration',147));
  v_outcome:=public.record_leghevo_authoritative_operational_window_v1(
    'production','leghevo-production-observer',8,v_telemetry_token,1,
    v_now-interval '5 minutes',v_now,1000,1,0,175,
    '62700000-0000-4000-8000-000000000008'::uuid,
    jsonb_build_object('seedStage',100,'productionReadiness',true));

  perform public.seed_leghevo_production_readiness_drain_v1(
    'production','operations_center','leghevo-operations-consumer',6,
    v_operations_consumer_token,v_operations_delivery_token);
  perform public.seed_leghevo_production_readiness_drain_v1(
    'production','notification_dispatch','leghevo-notification-consumer',6,
    v_notification_consumer_token,v_notification_delivery_token);
  v_outcome:=public.run_leghevo_operational_delivery_audit_v1(
    'production','62700000-0000-4000-8000-000000000009'::uuid,
    jsonb_build_object('sourceMigration',147,'productionReadiness',true));
  v_checkpoint:=public.create_leghevo_disaster_recovery_checkpoint_v1(
    'production','62700000-0000-4000-8000-000000000010'::uuid,
    'disaster_recovery.release_0_62_43',jsonb_build_object('sourceMigration',147));
  v_outcome:=public.run_leghevo_disaster_recovery_drill_v1(
    'production',(v_checkpoint->>'checkpointId')::bigint,
    '62700000-0000-4000-8000-000000000011'::uuid,
    jsonb_build_object('sourceMigration',147,'productionReadiness',true));
  v_artifact:=public.register_leghevo_physical_backup_artifact_v1(
    'production',(v_checkpoint->>'checkpointId')::bigint,v_provider_hash,v_storage_hash,v_checksum,
    805306368,'managed_backup',true,v_encryption_hash,v_actor_hash,
    '62700000-0000-4000-8000-000000000012'::uuid,
    jsonb_build_object('evidenceMode','external_attestation','sourceMigration',147));
  v_outcome:=public.append_leghevo_physical_backup_custody_event_v1(
    'production',(v_artifact->>'artifactId')::bigint,'checksum_verified',v_actor_hash,v_storage_hash,v_now,
    '62700000-0000-4000-8000-000000000013'::uuid,
    jsonb_build_object('checksumAlgorithm','sha256','verified',true));
  v_outcome:=public.append_leghevo_physical_backup_custody_event_v1(
    'production',(v_artifact->>'artifactId')::bigint,'sealed',v_actor_hash,v_storage_hash,v_now,
    '62700000-0000-4000-8000-000000000014'::uuid,
    jsonb_build_object('encrypted',true,'sealed',true));
  v_outcome:=public.run_leghevo_external_restore_rehearsal_v1(
    'production',(v_artifact->>'artifactId')::bigint,v_target_hash,v_checksum,805306368,
    24,8,0,0,v_actor_hash,v_now,v_now,
    '62700000-0000-4000-8000-000000000015'::uuid,
    jsonb_build_object('isolatedTarget',true,'networkWritesBlocked',true,'sourceMigration',147));

  v_run:=public.begin_leghevo_service_return_v1(
    'production','62700000-0000-4000-8000-000000000020'::uuid,
    'service_return.production_readiness_restore_verified',jsonb_build_object('sourceMigration',147));
  v_run_id:=(v_run->>'runId')::bigint;
  v_snapshot:=public.get_leghevo_service_return_snapshot_v1('production');

  v_hash:=v_snapshot->>'applicationFingerprint'; v_sequence:=0;
  v_outcome:=public.record_leghevo_service_return_check_v1(
    'production',v_run_id,'application_integrity',v_hash,v_hash,v_sequence,v_sequence,
    '62700000-0000-4000-8000-000000000021'::uuid,jsonb_build_object('sourceMigration',147));
  v_hash:=v_snapshot->>'releaseFingerprint'; v_sequence:=(v_snapshot->>'releaseGeneration')::bigint;
  v_outcome:=public.record_leghevo_service_return_check_v1(
    'production',v_run_id,'release_compatibility',v_hash,v_hash,v_sequence,v_sequence,
    '62700000-0000-4000-8000-000000000022'::uuid,jsonb_build_object('sourceMigration',147));
  v_hash:=v_snapshot->>'rolloutFingerprint'; v_sequence:=(v_snapshot->>'rolloutGeneration')::bigint;
  v_outcome:=public.record_leghevo_service_return_check_v1(
    'production',v_run_id,'rollout_state',v_hash,v_hash,v_sequence,v_sequence,
    '62700000-0000-4000-8000-000000000023'::uuid,jsonb_build_object('sourceMigration',147));
  v_hash:=v_snapshot->>'telemetryFingerprint'; v_sequence:=(v_snapshot->>'telemetryGeneration')::bigint;
  v_outcome:=public.record_leghevo_service_return_check_v1(
    'production',v_run_id,'telemetry_fencing',v_hash,v_hash,v_sequence,v_sequence,
    '62700000-0000-4000-8000-000000000024'::uuid,jsonb_build_object('sourceMigration',147));
  v_hash:=v_snapshot->>'outboxFingerprint'; v_sequence:=(v_snapshot->>'outboxSequence')::bigint;
  v_outcome:=public.record_leghevo_service_return_check_v1(
    'production',v_run_id,'outbox_continuity',v_hash,v_hash,v_sequence,v_sequence,
    '62700000-0000-4000-8000-000000000025'::uuid,jsonb_build_object('sourceMigration',147));
  v_hash:=v_snapshot->>'consumerFingerprint'; v_sequence:=(v_snapshot->>'consumerSequence')::bigint;
  v_outcome:=public.record_leghevo_service_return_check_v1(
    'production',v_run_id,'consumer_continuity',v_hash,v_hash,v_sequence,v_sequence,
    '62700000-0000-4000-8000-000000000026'::uuid,jsonb_build_object('sourceMigration',147));
  v_hash:=v_snapshot->>'auditFingerprint'; v_sequence:=(v_snapshot->>'auditSequence')::bigint;
  v_outcome:=public.record_leghevo_service_return_check_v1(
    'production',v_run_id,'delivery_audit',v_hash,v_hash,v_sequence,v_sequence,
    '62700000-0000-4000-8000-000000000027'::uuid,jsonb_build_object('sourceMigration',147));
  v_hash:=v_snapshot->>'physicalBackupFingerprint'; v_sequence:=(v_snapshot->>'artifactId')::bigint;
  v_outcome:=public.record_leghevo_service_return_check_v1(
    'production',v_run_id,'physical_backup',v_hash,v_hash,v_sequence,v_sequence,
    '62700000-0000-4000-8000-000000000028'::uuid,jsonb_build_object('sourceMigration',147));
  v_outcome:=public.complete_leghevo_service_return_v1(
    'production',v_run_id,'62700000-0000-4000-8000-000000000030'::uuid,
    'service_return.production_readiness_certified',jsonb_build_object('sourceMigration',147,'trafficPercentage',100));

  v_outcome:=public.certify_leghevo_production_readiness_v1(
    'production','62700000-0000-4000-8000-000000000040'::uuid,
    'production_readiness.go_live_certified',
    jsonb_build_object('sourceMigration',147,'applicationVersion','0.62.43','checkCount',10));
end;
$seed_release$;

drop function if exists public.seed_leghevo_production_readiness_drain_v1(text,text,text,bigint,uuid,uuid);

do $realtime$
begin
  if exists(select 1 from pg_catalog.pg_publication publication where publication.pubname='supabase_realtime')
    and not exists(
      select 1 from pg_catalog.pg_publication_tables publication_table
      where publication_table.pubname='supabase_realtime'
        and publication_table.schemaname='public'
        and publication_table.tablename='leghevo_production_readiness_events'
    ) then
    execute 'alter publication supabase_realtime add table public.leghevo_production_readiness_events';
  end if;
end;
$realtime$;

create or replace function public.get_leghevo_production_readiness_deployment_integrity_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_model jsonb;
  v_release jsonb;
  v_run_mismatch bigint:=0;
  v_check_mismatch bigint:=0;
  v_certificate_mismatch bigint:=0;
  v_certify_def text:=coalesce(pg_catalog.pg_get_functiondef(
    to_regprocedure('public.certify_leghevo_production_readiness_v1(text,uuid,text,jsonb)')),'');
begin
  v_model:=public.get_leghevo_production_readiness_model_v1('production');
  v_release:=public.get_leghevo_application_release_model_v1('production');

  select count(*) into v_run_mismatch
  from public.leghevo_production_readiness_runs run
  where run.run_fingerprint<>public.compute_leghevo_production_readiness_run_fingerprint_v1(
    run.environment_key,run.readiness_generation,run.active_release_version,
    run.release_generation,run.rollout_generation,run.telemetry_generation,
    run.outbox_sequence,run.consumer_sequence,run.audit_sequence,
    run.checkpoint_generation,run.backup_generation,run.service_return_generation,
    run.snapshot_fingerprint,run.contract_version);
  select count(*) into v_check_mismatch
  from public.leghevo_production_readiness_checks check_row
  where check_row.check_fingerprint<>public.compute_leghevo_production_readiness_check_fingerprint_v1(
    check_row.run_id,check_row.check_key,check_row.check_ordinal,check_row.component_fingerprint,
    check_row.component_sequence,check_row.status,check_row.details);
  select count(*) into v_certificate_mismatch
  from public.leghevo_production_readiness_certificates certificate
  where certificate.certificate_fingerprint<>
    public.compute_leghevo_production_readiness_certificate_fingerprint_v1(
      certificate.run_id,certificate.environment_key,certificate.readiness_generation,
      certificate.application_version,certificate.check_count,certificate.run_fingerprint,
      certificate.checks_fingerprint,certificate.contract_version);

  return jsonb_build_object(
    'predecessor_ready',to_regprocedure('public.get_leghevo_service_return_deployment_integrity_v1()') is not null
      and to_regprocedure('public.get_leghevo_service_return_model_v1(text)') is not null,
    'run_table_ready',to_regclass('public.leghevo_production_readiness_runs') is not null,
    'check_table_ready',to_regclass('public.leghevo_production_readiness_checks') is not null,
    'certificate_table_ready',to_regclass('public.leghevo_production_readiness_certificates') is not null,
    'head_and_event_tables_ready',to_regclass('public.leghevo_production_readiness_heads') is not null
      and to_regclass('public.leghevo_production_readiness_events') is not null,
    'columns_ready',exists(select 1 from information_schema.columns where table_schema='public'
      and table_name='leghevo_production_readiness_runs' and column_name='snapshot_fingerprint')
      and exists(select 1 from information_schema.columns where table_schema='public'
        and table_name='leghevo_production_readiness_heads' and column_name='go_live_allowed'),
    'constraints_ready',exists(select 1 from pg_catalog.pg_constraint constraint_row
      where constraint_row.conrelid='public.leghevo_production_readiness_runs'::regclass
        and constraint_row.conname='leghevo_production_readiness_run_generation_unique')
      and exists(select 1 from pg_catalog.pg_constraint constraint_row
        where constraint_row.conrelid='public.leghevo_production_readiness_checks'::regclass
          and constraint_row.conname='leghevo_production_readiness_run_check_unique'),
    'indexes_ready',to_regclass('public.leghevo_production_readiness_runs_environment_generation_idx') is not null
      and to_regclass('public.leghevo_production_readiness_checks_run_ordinal_idx') is not null
      and to_regclass('public.leghevo_production_readiness_events_environment_created_idx') is not null,
    'rls_ready',(select relrowsecurity from pg_catalog.pg_class where oid='public.leghevo_production_readiness_runs'::regclass)
      and (select relrowsecurity from pg_catalog.pg_class where oid='public.leghevo_production_readiness_checks'::regclass)
      and (select relrowsecurity from pg_catalog.pg_class where oid='public.leghevo_production_readiness_certificates'::regclass)
      and (select relrowsecurity from pg_catalog.pg_class where oid='public.leghevo_production_readiness_heads'::regclass)
      and (select relrowsecurity from pg_catalog.pg_class where oid='public.leghevo_production_readiness_events'::regclass),
    'direct_write_blocked',not has_table_privilege('authenticated','public.leghevo_production_readiness_runs','INSERT')
      and not has_table_privilege('service_role','public.leghevo_production_readiness_runs','INSERT')
      and not has_table_privilege('authenticated','public.leghevo_production_readiness_heads','UPDATE'),
    'immutable_records_ready',(select count(*)=4 from pg_catalog.pg_trigger trigger_row
      where trigger_row.tgname in ('leghevo_production_readiness_runs_guard',
        'leghevo_production_readiness_checks_guard','leghevo_production_readiness_certificates_guard',
        'leghevo_production_readiness_events_guard') and trigger_row.tgenabled='A' and not trigger_row.tgisinternal),
    'head_guard_ready',exists(select 1 from pg_catalog.pg_trigger trigger_row
      where trigger_row.tgrelid='public.leghevo_production_readiness_heads'::regclass
        and trigger_row.tgname='leghevo_production_readiness_heads_guard'
        and trigger_row.tgenabled='A' and not trigger_row.tgisinternal),
    'fingerprints_ready',v_run_mismatch=0 and v_check_mismatch=0 and v_certificate_mismatch=0,
    'snapshot_rpc_ready',to_regprocedure('public.get_leghevo_production_readiness_snapshot_v1(text)') is not null
      and has_function_privilege('service_role','public.get_leghevo_production_readiness_snapshot_v1(text)','EXECUTE'),
    'certification_rpc_ready',to_regprocedure('public.certify_leghevo_production_readiness_v1(text,uuid,text,jsonb)') is not null
      and has_function_privilege('service_role','public.certify_leghevo_production_readiness_v1(text,uuid,text,jsonb)','EXECUTE')
      and position('pg_advisory_xact_lock' in v_certify_def)>0,
    'reconcile_and_assert_ready',to_regprocedure('public.reconcile_leghevo_production_readiness_v1(text,text)') is not null
      and to_regprocedure('public.assert_leghevo_production_readiness_v1(text,text)') is not null
      and (select count(*)=7 from pg_catalog.pg_trigger trigger_row
        where trigger_row.tgname like 'leghevo_production_readiness_after_%_event'
          and trigger_row.tgenabled='A' and not trigger_row.tgisinternal),
    'promotion_v9_ready',to_regprocedure('public.promote_leghevo_application_rollout_v9(text,integer,uuid,text)') is not null
      and has_function_privilege('service_role','public.promote_leghevo_application_rollout_v9(text,integer,uuid,text)','EXECUTE')
      and not has_function_privilege('service_role','public.promote_leghevo_application_rollout_v8(text,integer,uuid,text)','EXECUTE'),
    'client_and_endpoint_chain_ready',to_regprocedure('public.get_leghevo_client_rollout_eligibility_v9(text,text,uuid)') is not null
      and has_function_privilege('anon','public.get_leghevo_client_rollout_eligibility_v9(text,text,uuid)','EXECUTE')
      and not has_function_privilege('anon','public.get_leghevo_client_rollout_eligibility_v8(text,text,uuid)','EXECUTE')
      and to_regprocedure('public.get_league_provider_sync_health_v42(uuid)') is not null
      and to_regprocedure('public.get_league_season_state_v21(uuid)') is not null
      and to_regprocedure('public.get_league_management_state_v31(uuid)') is not null,
    'realtime_ready',not exists(select 1 from pg_catalog.pg_publication publication where publication.pubname='supabase_realtime')
      or exists(select 1 from pg_catalog.pg_publication_tables publication_table
        where publication_table.pubname='supabase_realtime' and publication_table.schemaname='public'
          and publication_table.tablename='leghevo_production_readiness_events'),
    'seed_production_readiness_ready',coalesce((v_release->>'protected')::boolean,false)
      and v_release->>'activeVersion'='0.62.43'
      and exists(select 1 from public.leghevo_application_release_certificates certificate
        where certificate.application_version='0.62.43'
          and certificate.bundle_fingerprint='9cd8380cc324b6292f0e74fd0b5a727171cacc137462942d6c69149304ca3e5e')
      and coalesce((v_model->>'protected')::boolean,false)
      and coalesce((v_model->>'healthy')::boolean,false)
      and coalesce((v_model->>'fresh')::boolean,false)
      and v_model->>'status'='certified'
      and coalesce((v_model->>'checkCount')::integer,0)=10
      and coalesce((v_model->>'goLiveAllowed')::boolean,false)
      and v_model->>'activeVersion'='0.62.43'
      and to_regprocedure('public.seed_leghevo_production_readiness_drain_v1(text,text,text,bigint,uuid,uuid)') is null
  );
end;
$function$;

revoke all on function public.get_leghevo_production_readiness_deployment_integrity_v1()
  from public, anon, authenticated;
grant execute on function public.get_leghevo_production_readiness_deployment_integrity_v1()
  to service_role;

do $validate$
declare v_integrity jsonb; v_false text[];
begin
  v_integrity:=public.get_leghevo_production_readiness_deployment_integrity_v1();
  select array_agg(item.key order by item.key) into v_false
  from pg_catalog.jsonb_each(v_integrity) item
  where pg_catalog.jsonb_typeof(item.value) is distinct from 'boolean'
     or item.value is distinct from 'true'::jsonb;
  if (select count(*) from pg_catalog.jsonb_each(v_integrity))<>20 or cardinality(v_false)>0 then
    raise exception 'Validazione v0.62.43 non superata: %. Dettaglio: %',
      coalesce(array_to_string(v_false,', '),'numero controlli diverso da 20'),v_integrity;
  end if;
end;
$validate$;

commit;

select
  (public.get_leghevo_production_readiness_deployment_integrity_v1()->>'predecessor_ready')::boolean as predecessor_ready,
  (public.get_leghevo_production_readiness_deployment_integrity_v1()->>'run_table_ready')::boolean as run_table_ready,
  (public.get_leghevo_production_readiness_deployment_integrity_v1()->>'check_table_ready')::boolean as check_table_ready,
  (public.get_leghevo_production_readiness_deployment_integrity_v1()->>'certificate_table_ready')::boolean as certificate_table_ready,
  (public.get_leghevo_production_readiness_deployment_integrity_v1()->>'head_and_event_tables_ready')::boolean as head_and_event_tables_ready,
  (public.get_leghevo_production_readiness_deployment_integrity_v1()->>'columns_ready')::boolean as columns_ready,
  (public.get_leghevo_production_readiness_deployment_integrity_v1()->>'constraints_ready')::boolean as constraints_ready,
  (public.get_leghevo_production_readiness_deployment_integrity_v1()->>'indexes_ready')::boolean as indexes_ready,
  (public.get_leghevo_production_readiness_deployment_integrity_v1()->>'rls_ready')::boolean as rls_ready,
  (public.get_leghevo_production_readiness_deployment_integrity_v1()->>'direct_write_blocked')::boolean as direct_write_blocked,
  (public.get_leghevo_production_readiness_deployment_integrity_v1()->>'immutable_records_ready')::boolean as immutable_records_ready,
  (public.get_leghevo_production_readiness_deployment_integrity_v1()->>'head_guard_ready')::boolean as head_guard_ready,
  (public.get_leghevo_production_readiness_deployment_integrity_v1()->>'fingerprints_ready')::boolean as fingerprints_ready,
  (public.get_leghevo_production_readiness_deployment_integrity_v1()->>'snapshot_rpc_ready')::boolean as snapshot_rpc_ready,
  (public.get_leghevo_production_readiness_deployment_integrity_v1()->>'certification_rpc_ready')::boolean as certification_rpc_ready,
  (public.get_leghevo_production_readiness_deployment_integrity_v1()->>'reconcile_and_assert_ready')::boolean as reconcile_and_assert_ready,
  (public.get_leghevo_production_readiness_deployment_integrity_v1()->>'promotion_v9_ready')::boolean as promotion_v9_ready,
  (public.get_leghevo_production_readiness_deployment_integrity_v1()->>'client_and_endpoint_chain_ready')::boolean as client_and_endpoint_chain_ready,
  (public.get_leghevo_production_readiness_deployment_integrity_v1()->>'realtime_ready')::boolean as realtime_ready,
  (public.get_leghevo_production_readiness_deployment_integrity_v1()->>'seed_production_readiness_ready')::boolean as seed_production_readiness_ready;
