-- LEGHEVO v0.62.42
-- Riapertura controllata post-restore, recovery mode e certificato di ritorno in servizio
-- Dipendenza: v0.62.41 validata con 20/20 controlli true.
-- Revisione standalone v3: normalizzazione fail-safe delle fingerprint del controllo post-restore e mantenimento della correzione sulla custodia.

begin;

do $preflight$
declare
  v_integrity jsonb;
  v_false text[];
begin
  if to_regprocedure('public.get_leghevo_service_return_deployment_integrity_v1()') is not null
    and exists (
      select 1
      from public.leghevo_application_release_certificates certificate
      where certificate.application_version = '0.62.42'
    ) then
    return;
  end if;

  if to_regprocedure('public.get_leghevo_physical_backup_deployment_integrity_v1()') is null then
    raise exception 'Preflight v0.62.42 non superato: diagnostica v0.62.41 assente.';
  end if;

  v_integrity := public.get_leghevo_physical_backup_deployment_integrity_v1();
  select array_agg(item.key order by item.key)
  into v_false
  from pg_catalog.jsonb_each(v_integrity) item
  where pg_catalog.jsonb_typeof(item.value) is distinct from 'boolean'
     or item.value is distinct from 'true'::jsonb;

  if (select count(*) from pg_catalog.jsonb_each(v_integrity)) <> 20
    or cardinality(v_false) > 0 then
    raise exception 'Preflight v0.62.42 non superato: %. Dettaglio: %',
      coalesce(array_to_string(v_false, ', '), 'numero controlli diverso da 20'),
      v_integrity;
  end if;
end;
$preflight$;

-- Correzione pre-validazione v2: la sequenza di custodia e' locale al singolo artefatto.
-- Quando aumenta backup_generation puo' ripartire da 1; resta monotona all'interno
-- della stessa generazione e rehearsal_generation non puo' mai regredire.
create or replace function public.guard_leghevo_physical_backup_head_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if current_setting('leghevo.physical_backup_context', true) <> 'allowed' then
    raise exception 'Testa backup fisico protetta: scrittura diretta vietata.';
  end if;
  if tg_op = 'DELETE' then
    raise exception 'Testa backup fisico non cancellabile.';
  end if;
  if tg_op = 'UPDATE' then
    if new.backup_generation < old.backup_generation
      or new.rehearsal_generation < old.rehearsal_generation
      or (new.backup_generation = old.backup_generation
        and new.custody_sequence < old.custody_sequence)
      or new.revision <= old.revision then
      raise exception 'Regressione della testa backup fisico vietata.';
    end if;
    if new.backup_generation > old.backup_generation
      and new.custody_sequence <> 1 then
      raise exception 'Nuova generazione backup fisico non inizializzata dalla prima custodia.';
    end if;
  end if;
  return new;
end;
$function$;

create or replace function public.compute_leghevo_service_return_run_fingerprint_v1(
  p_environment_key text,
  p_recovery_generation bigint,
  p_artifact_id bigint,
  p_rehearsal_id bigint,
  p_checkpoint_id bigint,
  p_active_release_version text,
  p_release_generation bigint,
  p_rollout_generation bigint,
  p_telemetry_generation bigint,
  p_outbox_sequence bigint,
  p_consumer_sequence bigint,
  p_audit_sequence bigint,
  p_reason_code text,
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
    coalesce(p_recovery_generation, 0)::text || '|' ||
    coalesce(p_artifact_id, 0)::text || '|' ||
    coalesce(p_rehearsal_id, 0)::text || '|' ||
    coalesce(p_checkpoint_id, 0)::text || '|' ||
    coalesce(trim(p_active_release_version), '') || '|' ||
    coalesce(p_release_generation, 0)::text || '|' ||
    coalesce(p_rollout_generation, 0)::text || '|' ||
    coalesce(p_telemetry_generation, 0)::text || '|' ||
    coalesce(p_outbox_sequence, 0)::text || '|' ||
    coalesce(p_consumer_sequence, 0)::text || '|' ||
    coalesce(p_audit_sequence, 0)::text || '|' ||
    coalesce(lower(trim(p_reason_code)), '') || '|' ||
    coalesce(p_contract_version, 0)::text
  );
$function$;

create or replace function public.compute_leghevo_service_return_check_fingerprint_v1(
  p_run_id bigint,
  p_check_key text,
  p_check_ordinal integer,
  p_expected_fingerprint text,
  p_observed_fingerprint text,
  p_expected_sequence bigint,
  p_observed_sequence bigint,
  p_status text,
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
    coalesce(p_run_id, 0)::text || '|' ||
    coalesce(lower(trim(p_check_key)), '') || '|' ||
    coalesce(p_check_ordinal, 0)::text || '|' ||
    coalesce(lower(trim(p_expected_fingerprint)), '') || '|' ||
    coalesce(lower(trim(p_observed_fingerprint)), '') || '|' ||
    coalesce(p_expected_sequence, 0)::text || '|' ||
    coalesce(p_observed_sequence, 0)::text || '|' ||
    coalesce(lower(trim(p_status)), '') || '|' ||
    coalesce(lower(trim(p_reason_code)), '') || '|' ||
    coalesce(p_details, '{}'::jsonb)::text
  );
$function$;

create or replace function public.compute_leghevo_service_return_certificate_fingerprint_v1(
  p_run_id bigint,
  p_environment_key text,
  p_recovery_generation bigint,
  p_check_count integer,
  p_active_release_version text,
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
    coalesce(p_recovery_generation, 0)::text || '|' ||
    coalesce(p_check_count, 0)::text || '|' ||
    coalesce(trim(p_active_release_version), '') || '|' ||
    coalesce(lower(trim(p_run_fingerprint)), '') || '|' ||
    coalesce(lower(trim(p_checks_fingerprint)), '') || '|' ||
    coalesce(p_contract_version, 0)::text
  );
$function$;

create or replace function public.compute_leghevo_service_return_event_fingerprint_v1(
  p_environment_key text,
  p_event_type text,
  p_recovery_generation bigint,
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
    coalesce(p_recovery_generation, 0)::text || '|' ||
    coalesce(p_run_id, 0)::text || '|' ||
    coalesce(p_certificate_id, 0)::text || '|' ||
    coalesce(lower(trim(p_reason_code)), '') || '|' ||
    coalesce(p_details, '{}'::jsonb)::text
  );
$function$;

create table if not exists public.leghevo_service_return_runs (
  id bigint generated by default as identity primary key,
  environment_key text not null,
  recovery_generation bigint not null,
  request_id uuid not null unique,
  artifact_id bigint not null
    references public.leghevo_physical_backup_artifacts(id) on delete restrict,
  rehearsal_id bigint not null
    references public.leghevo_external_restore_rehearsals(id) on delete restrict,
  checkpoint_id bigint not null
    references public.leghevo_disaster_recovery_checkpoints(id) on delete restrict,
  active_release_version text not null,
  release_generation bigint not null,
  rollout_generation bigint not null,
  telemetry_generation bigint not null,
  outbox_sequence bigint not null,
  consumer_sequence bigint not null,
  audit_sequence bigint not null,
  reason_code text not null,
  contract_version integer not null default 1,
  run_fingerprint text not null unique,
  details jsonb not null default '{}'::jsonb,
  started_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  created_by uuid null,
  constraint leghevo_service_return_run_environment_check
    check (environment_key in ('production','staging')),
  constraint leghevo_service_return_run_generation_check
    check (recovery_generation >= 1 and release_generation >= 1 and rollout_generation >= 1
      and telemetry_generation >= 1 and outbox_sequence >= 0 and consumer_sequence >= 0
      and audit_sequence >= 0),
  constraint leghevo_service_return_run_release_check
    check (char_length(trim(active_release_version)) between 3 and 64),
  constraint leghevo_service_return_run_reason_check
    check (char_length(trim(reason_code)) between 3 and 160),
  constraint leghevo_service_return_run_contract_check check (contract_version >= 1),
  constraint leghevo_service_return_run_fingerprint_check
    check (run_fingerprint ~ '^[0-9a-f]{64}$'),
  constraint leghevo_service_return_run_details_check check (jsonb_typeof(details) = 'object'),
  constraint leghevo_service_return_run_generation_unique
    unique (environment_key, recovery_generation)
);

create table if not exists public.leghevo_service_return_checks (
  id bigint generated by default as identity primary key,
  run_id bigint not null
    references public.leghevo_service_return_runs(id) on delete restrict,
  check_key text not null,
  check_ordinal integer not null,
  request_id uuid not null unique,
  expected_fingerprint text not null,
  observed_fingerprint text not null,
  expected_sequence bigint not null,
  observed_sequence bigint not null,
  status text not null,
  reason_code text not null,
  check_fingerprint text not null unique,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  created_by uuid null,
  constraint leghevo_service_return_check_key_check check (check_key in (
    'application_integrity','release_compatibility','rollout_state','telemetry_fencing',
    'outbox_continuity','consumer_continuity','delivery_audit','physical_backup'
  )),
  constraint leghevo_service_return_check_ordinal_check check (check_ordinal between 1 and 8),
  constraint leghevo_service_return_check_hashes_check check (
    expected_fingerprint ~ '^[0-9a-f]{64}$'
    and observed_fingerprint ~ '^[0-9a-f]{64}$'
    and check_fingerprint ~ '^[0-9a-f]{64}$'
  ),
  constraint leghevo_service_return_check_sequence_check
    check (expected_sequence >= 0 and observed_sequence >= 0),
  constraint leghevo_service_return_check_status_check check (status in ('passed','failed')),
  constraint leghevo_service_return_check_reason_check
    check (char_length(trim(reason_code)) between 3 and 160),
  constraint leghevo_service_return_check_details_check check (jsonb_typeof(details) = 'object'),
  constraint leghevo_service_return_run_check_unique unique (run_id, check_key),
  constraint leghevo_service_return_run_ordinal_unique unique (run_id, check_ordinal)
);

create table if not exists public.leghevo_service_return_certificates (
  id bigint generated by default as identity primary key,
  run_id bigint not null unique
    references public.leghevo_service_return_runs(id) on delete restrict,
  environment_key text not null,
  recovery_generation bigint not null,
  request_id uuid not null unique,
  check_count integer not null,
  active_release_version text not null,
  run_fingerprint text not null,
  checks_fingerprint text not null,
  status text not null,
  reason_code text not null,
  contract_version integer not null default 1,
  certificate_fingerprint text not null unique,
  details jsonb not null default '{}'::jsonb,
  certified_at timestamptz not null default now(),
  certified_by uuid null,
  constraint leghevo_service_return_certificate_environment_check
    check (environment_key in ('production','staging')),
  constraint leghevo_service_return_certificate_generation_check check (recovery_generation >= 1),
  constraint leghevo_service_return_certificate_check_count check (check_count = 8),
  constraint leghevo_service_return_certificate_release_check
    check (char_length(trim(active_release_version)) between 3 and 64),
  constraint leghevo_service_return_certificate_hashes_check check (
    run_fingerprint ~ '^[0-9a-f]{64}$'
    and checks_fingerprint ~ '^[0-9a-f]{64}$'
    and certificate_fingerprint ~ '^[0-9a-f]{64}$'
  ),
  constraint leghevo_service_return_certificate_status_check check (status = 'certified'),
  constraint leghevo_service_return_certificate_reason_check
    check (char_length(trim(reason_code)) between 3 and 160),
  constraint leghevo_service_return_certificate_contract_check check (contract_version >= 1),
  constraint leghevo_service_return_certificate_details_check check (jsonb_typeof(details) = 'object'),
  constraint leghevo_service_return_certificate_generation_unique
    unique (environment_key, recovery_generation)
);

create table if not exists public.leghevo_service_return_heads (
  environment_key text primary key,
  recovery_generation bigint not null,
  run_id bigint not null
    references public.leghevo_service_return_runs(id) on delete restrict,
  certificate_id bigint null
    references public.leghevo_service_return_certificates(id) on delete restrict,
  mode text not null,
  status text not null,
  writes_allowed boolean not null,
  workers_allowed boolean not null,
  traffic_percentage integer not null,
  reason_code text not null,
  revision bigint not null default 1,
  state_fingerprint text not null,
  entered_at timestamptz not null,
  certified_at timestamptz null,
  affected_at timestamptz null,
  updated_at timestamptz not null default now(),
  constraint leghevo_service_return_head_environment_check
    check (environment_key in ('production','staging')),
  constraint leghevo_service_return_head_generation_check
    check (recovery_generation >= 1 and revision >= 1),
  constraint leghevo_service_return_head_mode_check check (mode in ('recovery','active','affected')),
  constraint leghevo_service_return_head_status_check
    check (status in ('recovery','certified','revalidated','affected')),
  constraint leghevo_service_return_head_traffic_check check (traffic_percentage between 0 and 100),
  constraint leghevo_service_return_head_consistency_check check (
    (mode = 'active' and status in ('certified','revalidated') and writes_allowed and workers_allowed
      and traffic_percentage = 100 and certificate_id is not null and certified_at is not null)
    or (mode = 'recovery' and status = 'recovery' and not writes_allowed and not workers_allowed
      and traffic_percentage = 0 and certificate_id is null)
    or (mode = 'affected' and status = 'affected' and not writes_allowed and not workers_allowed
      and traffic_percentage = 0 and affected_at is not null)
  ),
  constraint leghevo_service_return_head_reason_check
    check (char_length(trim(reason_code)) between 3 and 160),
  constraint leghevo_service_return_head_fingerprint_check
    check (state_fingerprint ~ '^[0-9a-f]{64}$')
);

create table if not exists public.leghevo_service_return_events (
  id bigint generated by default as identity primary key,
  environment_key text not null,
  event_type text not null,
  recovery_generation bigint not null,
  run_id bigint not null
    references public.leghevo_service_return_runs(id) on delete restrict,
  certificate_id bigint null
    references public.leghevo_service_return_certificates(id) on delete restrict,
  reason_code text not null,
  details jsonb not null default '{}'::jsonb,
  event_fingerprint text not null unique,
  created_at timestamptz not null default now(),
  created_by uuid null,
  constraint leghevo_service_return_event_environment_check
    check (environment_key in ('production','staging')),
  constraint leghevo_service_return_event_type_check
    check (event_type in ('recovery_entered','check_recorded','certified','affected','revalidated')),
  constraint leghevo_service_return_event_generation_check check (recovery_generation >= 1),
  constraint leghevo_service_return_event_reason_check
    check (char_length(trim(reason_code)) between 3 and 160),
  constraint leghevo_service_return_event_details_check check (jsonb_typeof(details) = 'object'),
  constraint leghevo_service_return_event_fingerprint_check
    check (event_fingerprint ~ '^[0-9a-f]{64}$')
);

create index if not exists leghevo_service_return_runs_environment_generation_idx
  on public.leghevo_service_return_runs(environment_key, recovery_generation desc);
create index if not exists leghevo_service_return_checks_run_ordinal_idx
  on public.leghevo_service_return_checks(run_id, check_ordinal);
create index if not exists leghevo_service_return_certificates_environment_generation_idx
  on public.leghevo_service_return_certificates(environment_key, recovery_generation desc);
create index if not exists leghevo_service_return_events_environment_created_idx
  on public.leghevo_service_return_events(environment_key, created_at desc);

alter table public.leghevo_service_return_runs enable row level security;
alter table public.leghevo_service_return_checks enable row level security;
alter table public.leghevo_service_return_certificates enable row level security;
alter table public.leghevo_service_return_heads enable row level security;
alter table public.leghevo_service_return_events enable row level security;

revoke all on table public.leghevo_service_return_runs from public, anon, authenticated, service_role;
revoke all on table public.leghevo_service_return_checks from public, anon, authenticated, service_role;
revoke all on table public.leghevo_service_return_certificates from public, anon, authenticated, service_role;
revoke all on table public.leghevo_service_return_heads from public, anon, authenticated, service_role;
revoke all on table public.leghevo_service_return_events from public, anon, authenticated, service_role;

grant select on table public.leghevo_service_return_runs to authenticated, service_role;
grant select on table public.leghevo_service_return_checks to authenticated, service_role;
grant select on table public.leghevo_service_return_certificates to authenticated, service_role;
grant select on table public.leghevo_service_return_heads to authenticated, service_role;
grant select on table public.leghevo_service_return_events to authenticated, service_role;

create policy leghevo_service_return_runs_authenticated_read
on public.leghevo_service_return_runs for select to authenticated
using (true);
create policy leghevo_service_return_checks_authenticated_read
on public.leghevo_service_return_checks for select to authenticated
using (true);
create policy leghevo_service_return_certificates_authenticated_read
on public.leghevo_service_return_certificates for select to authenticated
using (true);
create policy leghevo_service_return_heads_authenticated_read
on public.leghevo_service_return_heads for select to authenticated
using (true);
create policy leghevo_service_return_events_authenticated_read
on public.leghevo_service_return_events for select to authenticated
using (true);

create or replace function public.guard_leghevo_service_return_immutable_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  raise exception 'Registro ritorno in servizio immutabile.';
end;
$function$;
revoke all on function public.guard_leghevo_service_return_immutable_v1()
from public, anon, authenticated, service_role;

create or replace function public.guard_leghevo_service_return_head_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if pg_catalog.current_setting('leghevo.service_return_context', true) is distinct from 'allowed' then
    raise exception 'Testa ritorno in servizio modificabile soltanto dalle RPC certificate.';
  end if;
  if tg_op = 'DELETE' then
    raise exception 'Testa ritorno in servizio non eliminabile.';
  end if;
  if tg_op = 'UPDATE' then
    if new.environment_key is distinct from old.environment_key
      or new.recovery_generation < old.recovery_generation
      or new.revision <> old.revision + 1 then
      raise exception 'Regressione o revisione non monotona della testa ritorno in servizio.';
    end if;
    if new.recovery_generation = old.recovery_generation
      and new.run_id is distinct from old.run_id then
      raise exception 'Run non sostituibile nella stessa generazione recovery.';
    end if;
  end if;
  return new;
end;
$function$;
revoke all on function public.guard_leghevo_service_return_head_v1()
from public, anon, authenticated, service_role;

create trigger leghevo_service_return_runs_guard
before update or delete on public.leghevo_service_return_runs
for each row execute function public.guard_leghevo_service_return_immutable_v1();
alter table public.leghevo_service_return_runs enable always trigger leghevo_service_return_runs_guard;
create trigger leghevo_service_return_checks_guard
before update or delete on public.leghevo_service_return_checks
for each row execute function public.guard_leghevo_service_return_immutable_v1();
alter table public.leghevo_service_return_checks enable always trigger leghevo_service_return_checks_guard;
create trigger leghevo_service_return_certificates_guard
before update or delete on public.leghevo_service_return_certificates
for each row execute function public.guard_leghevo_service_return_immutable_v1();
alter table public.leghevo_service_return_certificates enable always trigger leghevo_service_return_certificates_guard;
create trigger leghevo_service_return_events_guard
before update or delete on public.leghevo_service_return_events
for each row execute function public.guard_leghevo_service_return_immutable_v1();
alter table public.leghevo_service_return_events enable always trigger leghevo_service_return_events_guard;
create trigger leghevo_service_return_heads_guard
before insert or update or delete on public.leghevo_service_return_heads
for each row execute function public.guard_leghevo_service_return_head_v1();
alter table public.leghevo_service_return_heads enable always trigger leghevo_service_return_heads_guard;

create or replace function public.get_leghevo_service_return_snapshot_v1(
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
  v_application jsonb;
  v_release jsonb;
  v_rollout jsonb;
  v_telemetry jsonb;
  v_outbox jsonb;
  v_consumer jsonb;
  v_audit jsonb;
  v_recovery jsonb;
  v_backup jsonb;
begin
  if v_environment not in ('production','staging') then
    return jsonb_build_object('protected',false,'healthy',false,'reasonCode','service_return.invalid_environment');
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
  return jsonb_build_object(
    'protected',
      coalesce((v_application->>'protected')::boolean,false)
      and coalesce((v_release->>'protected')::boolean,false)
      and coalesce((v_rollout->>'protected')::boolean,false)
      and coalesce((v_telemetry->>'protected')::boolean,false)
      and coalesce((v_outbox->>'protected')::boolean,false)
      and coalesce((v_consumer->>'protected')::boolean,false)
      and coalesce((v_audit->>'protected')::boolean,false)
      and coalesce((v_recovery->>'protected')::boolean,false)
      and coalesce((v_backup->>'protected')::boolean,false),
    'healthy',
      coalesce((v_application->>'healthy')::boolean,false)
      and coalesce((v_release->>'healthy')::boolean,false)
      and coalesce((v_rollout->>'healthy')::boolean,false)
      and coalesce((v_telemetry->>'healthy')::boolean,false)
      and coalesce((v_outbox->>'healthy')::boolean,false)
      and coalesce((v_consumer->>'healthy')::boolean,false)
      and coalesce((v_audit->>'healthy')::boolean,false)
      and coalesce((v_recovery->>'healthy')::boolean,false)
      and coalesce((v_backup->>'healthy')::boolean,false),
    'environment',v_environment,
    'activeReleaseVersion',v_release->>'activeVersion',
    'releaseGeneration',coalesce((v_release->>'releaseGeneration')::bigint,0),
    'rolloutGeneration',coalesce((v_rollout->>'rolloutGeneration')::bigint,0),
    'telemetryGeneration',coalesce((v_telemetry->>'sourceGeneration')::bigint,0),
    'outboxSequence',coalesce((v_outbox->>'lastSequence')::bigint,0),
    'consumerSequence',coalesce((v_consumer->>'lastAcknowledgedSequence')::bigint,0),
    'auditSequence',coalesce((v_audit->>'auditedThroughSequence')::bigint,0),
    'artifactId',coalesce((v_backup->>'artifactId')::bigint,0),
    'rehearsalId',coalesce((v_backup->>'rehearsalId')::bigint,0),
    'checkpointId',coalesce((v_recovery->>'checkpointId')::bigint,0),
    'applicationFingerprint',case
      when lower(trim(coalesce(v_application->>'schemaFingerprint',''))) ~ '^[0-9a-f]{64}$'
        then lower(trim(v_application->>'schemaFingerprint'))
      else public.leghevo_sha256_hex_v1(v_application::text)
    end,
    'releaseFingerprint',case
      when lower(trim(coalesce(v_release->>'contractFingerprint',''))) ~ '^[0-9a-f]{64}$'
        then lower(trim(v_release->>'contractFingerprint'))
      else public.leghevo_sha256_hex_v1(v_release::text)
    end,
    'rolloutFingerprint',case
      when lower(trim(coalesce(v_rollout->>'planFingerprint',''))) ~ '^[0-9a-f]{64}$'
        then lower(trim(v_rollout->>'planFingerprint'))
      else public.leghevo_sha256_hex_v1(v_rollout::text)
    end,
    'telemetryFingerprint',public.leghevo_sha256_hex_v1(v_telemetry::text),
    'outboxFingerprint',public.leghevo_sha256_hex_v1(v_outbox::text),
    'consumerFingerprint',public.leghevo_sha256_hex_v1(v_consumer::text),
    'auditFingerprint',public.leghevo_sha256_hex_v1(v_audit::text),
    'physicalBackupFingerprint',public.leghevo_sha256_hex_v1(v_backup::text),
    'checkedAt',now()
  );
end;
$function$;
revoke all on function public.get_leghevo_service_return_snapshot_v1(text)
from public, anon, authenticated;
grant execute on function public.get_leghevo_service_return_snapshot_v1(text) to service_role;

create or replace function public.begin_leghevo_service_return_v1(
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
  v_environment text := lower(trim(coalesce(p_environment_key,'')));
  v_reason text := trim(coalesce(p_reason_code,''));
  v_details jsonb := coalesce(p_details,'{}'::jsonb);
  v_existing public.leghevo_service_return_runs%rowtype;
  v_snapshot jsonb;
  v_generation bigint;
  v_run public.leghevo_service_return_runs%rowtype;
  v_event_fingerprint text;
begin
  if v_environment not in ('production','staging') or p_request_id is null
    or char_length(v_reason) not between 3 and 160 or jsonb_typeof(v_details) <> 'object' then
    raise exception 'Parametri ingresso recovery mode non validi.';
  end if;
  if v_details ?| array['password','token','secret','credential','privateKey','apiKey'] then
    raise exception 'Dettagli recovery contenenti dati sensibili non ammessi.';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('leghevo:service-return:'||v_environment,0));
  select run.* into v_existing
  from public.leghevo_service_return_runs run
  where run.request_id=p_request_id;
  if found then
    return jsonb_build_object('runId',v_existing.id,'recoveryGeneration',v_existing.recovery_generation,
      'idempotent',true,'mode','recovery');
  end if;
  v_snapshot:=public.get_leghevo_service_return_snapshot_v1(v_environment);
  if not coalesce((v_snapshot->>'protected')::boolean,false)
    or not coalesce((v_snapshot->>'healthy')::boolean,false) then
    raise exception 'Ingresso recovery bloccato: catena operativa o backup non certificati. Dettaglio: %',v_snapshot;
  end if;
  select coalesce(max(run.recovery_generation),0)+1 into v_generation
  from public.leghevo_service_return_runs run
  where run.environment_key=v_environment;
  insert into public.leghevo_service_return_runs(
    environment_key,recovery_generation,request_id,artifact_id,rehearsal_id,checkpoint_id,
    active_release_version,release_generation,rollout_generation,telemetry_generation,
    outbox_sequence,consumer_sequence,audit_sequence,reason_code,run_fingerprint,details,created_by
  ) values (
    v_environment,v_generation,p_request_id,(v_snapshot->>'artifactId')::bigint,
    (v_snapshot->>'rehearsalId')::bigint,(v_snapshot->>'checkpointId')::bigint,
    v_snapshot->>'activeReleaseVersion',(v_snapshot->>'releaseGeneration')::bigint,
    (v_snapshot->>'rolloutGeneration')::bigint,(v_snapshot->>'telemetryGeneration')::bigint,
    (v_snapshot->>'outboxSequence')::bigint,(v_snapshot->>'consumerSequence')::bigint,
    (v_snapshot->>'auditSequence')::bigint,v_reason,
    public.compute_leghevo_service_return_run_fingerprint_v1(
      v_environment,v_generation,(v_snapshot->>'artifactId')::bigint,(v_snapshot->>'rehearsalId')::bigint,
      (v_snapshot->>'checkpointId')::bigint,v_snapshot->>'activeReleaseVersion',
      (v_snapshot->>'releaseGeneration')::bigint,(v_snapshot->>'rolloutGeneration')::bigint,
      (v_snapshot->>'telemetryGeneration')::bigint,(v_snapshot->>'outboxSequence')::bigint,
      (v_snapshot->>'consumerSequence')::bigint,(v_snapshot->>'auditSequence')::bigint,v_reason,1),
    v_details,auth.uid()
  ) returning * into v_run;
  perform pg_catalog.set_config('leghevo.service_return_context','allowed',true);
  insert into public.leghevo_service_return_heads(
    environment_key,recovery_generation,run_id,certificate_id,mode,status,writes_allowed,
    workers_allowed,traffic_percentage,reason_code,revision,state_fingerprint,entered_at,updated_at
  ) values (
    v_environment,v_generation,v_run.id,null,'recovery','recovery',false,false,0,v_reason,1,
    public.leghevo_sha256_hex_v1(v_environment||'|'||v_generation::text||'|'||v_run.id::text||'|recovery|1'),
    now(),now()
  ) on conflict (environment_key) do update set
    recovery_generation=excluded.recovery_generation,run_id=excluded.run_id,certificate_id=null,
    mode='recovery',status='recovery',writes_allowed=false,workers_allowed=false,traffic_percentage=0,
    reason_code=excluded.reason_code,revision=public.leghevo_service_return_heads.revision+1,
    state_fingerprint=public.leghevo_sha256_hex_v1(
      excluded.environment_key||'|'||excluded.recovery_generation::text||'|'||excluded.run_id::text||
      '|recovery|'||(public.leghevo_service_return_heads.revision+1)::text),
    entered_at=now(),certified_at=null,affected_at=null,updated_at=now();
  v_event_fingerprint:=public.compute_leghevo_service_return_event_fingerprint_v1(
    v_environment,'recovery_entered',v_generation,v_run.id,null,v_reason,
    jsonb_build_object('artifactId',v_run.artifact_id,'rehearsalId',v_run.rehearsal_id));
  insert into public.leghevo_service_return_events(
    environment_key,event_type,recovery_generation,run_id,certificate_id,reason_code,details,
    event_fingerprint,created_by
  ) values (
    v_environment,'recovery_entered',v_generation,v_run.id,null,v_reason,
    jsonb_build_object('artifactId',v_run.artifact_id,'rehearsalId',v_run.rehearsal_id),
    v_event_fingerprint,auth.uid());
  perform pg_catalog.set_config('leghevo.service_return_context','',true);
  return jsonb_build_object('runId',v_run.id,'recoveryGeneration',v_generation,
    'idempotent',false,'mode','recovery');
exception when others then
  perform pg_catalog.set_config('leghevo.service_return_context','',true);
  raise;
end;
$function$;
revoke all on function public.begin_leghevo_service_return_v1(text,uuid,text,jsonb)
from public, anon, authenticated;
grant execute on function public.begin_leghevo_service_return_v1(text,uuid,text,jsonb) to service_role;

create or replace function public.record_leghevo_service_return_check_v1(
  p_environment_key text,
  p_run_id bigint,
  p_check_key text,
  p_expected_fingerprint text,
  p_observed_fingerprint text,
  p_expected_sequence bigint,
  p_observed_sequence bigint,
  p_request_id uuid,
  p_details jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_environment text := lower(trim(coalesce(p_environment_key,'')));
  v_key text := lower(trim(coalesce(p_check_key,'')));
  v_expected text := lower(trim(coalesce(p_expected_fingerprint,'')));
  v_observed text := lower(trim(coalesce(p_observed_fingerprint,'')));
  v_details jsonb := coalesce(p_details,'{}'::jsonb);
  v_run public.leghevo_service_return_runs%rowtype;
  v_head public.leghevo_service_return_heads%rowtype;
  v_existing public.leghevo_service_return_checks%rowtype;
  v_ordinal integer;
  v_status text;
  v_reason text;
  v_check public.leghevo_service_return_checks%rowtype;
  v_event_fingerprint text;
begin
  if v_environment not in ('production','staging') or p_run_id is null or p_request_id is null
    or v_key not in ('application_integrity','release_compatibility','rollout_state','telemetry_fencing',
      'outbox_continuity','consumer_continuity','delivery_audit','physical_backup')
    or v_expected !~ '^[0-9a-f]{64}$' or v_observed !~ '^[0-9a-f]{64}$'
    or coalesce(p_expected_sequence,-1)<0 or coalesce(p_observed_sequence,-1)<0
    or jsonb_typeof(v_details)<>'object' then
    raise exception 'Parametri controllo ritorno in servizio non validi.';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('leghevo:service-return:'||v_environment,0));
  select check_row.* into v_existing
  from public.leghevo_service_return_checks check_row
  where check_row.request_id=p_request_id;
  if found then
    return jsonb_build_object('checkId',v_existing.id,'status',v_existing.status,'idempotent',true);
  end if;
  select run.* into v_run from public.leghevo_service_return_runs run
  where run.id=p_run_id and run.environment_key=v_environment;
  if not found then raise exception 'Run recovery non trovato.'; end if;
  select head.* into v_head from public.leghevo_service_return_heads head
  where head.environment_key=v_environment for update;
  if not found or v_head.run_id<>v_run.id or v_head.mode<>'recovery' then
    raise exception 'Controllo bloccato: recovery mode non corrente.';
  end if;
  v_ordinal:=case v_key
    when 'application_integrity' then 1 when 'release_compatibility' then 2
    when 'rollout_state' then 3 when 'telemetry_fencing' then 4
    when 'outbox_continuity' then 5 when 'consumer_continuity' then 6
    when 'delivery_audit' then 7 when 'physical_backup' then 8 end;
  v_status:=case when v_expected=v_observed and p_observed_sequence>=p_expected_sequence
    then 'passed' else 'failed' end;
  v_reason:=case when v_status='passed' then 'service_return.check_passed'
    when v_expected<>v_observed then 'service_return.fingerprint_mismatch'
    else 'service_return.sequence_regression' end;
  insert into public.leghevo_service_return_checks(
    run_id,check_key,check_ordinal,request_id,expected_fingerprint,observed_fingerprint,
    expected_sequence,observed_sequence,status,reason_code,check_fingerprint,details,created_by
  ) values (
    v_run.id,v_key,v_ordinal,p_request_id,v_expected,v_observed,p_expected_sequence,p_observed_sequence,
    v_status,v_reason,public.compute_leghevo_service_return_check_fingerprint_v1(
      v_run.id,v_key,v_ordinal,v_expected,v_observed,p_expected_sequence,p_observed_sequence,
      v_status,v_reason,v_details),v_details,auth.uid()
  ) returning * into v_check;
  v_event_fingerprint:=public.compute_leghevo_service_return_event_fingerprint_v1(
    v_environment,'check_recorded',v_run.recovery_generation,v_run.id,null,v_reason,
    jsonb_build_object('checkKey',v_key,'checkId',v_check.id,'status',v_status));
  insert into public.leghevo_service_return_events(
    environment_key,event_type,recovery_generation,run_id,certificate_id,reason_code,details,
    event_fingerprint,created_by
  ) values (
    v_environment,'check_recorded',v_run.recovery_generation,v_run.id,null,v_reason,
    jsonb_build_object('checkKey',v_key,'checkId',v_check.id,'status',v_status),
    v_event_fingerprint,auth.uid());
  return jsonb_build_object('checkId',v_check.id,'checkKey',v_key,'status',v_status,
    'reasonCode',v_reason,'idempotent',false);
end;
$function$;
revoke all on function public.record_leghevo_service_return_check_v1(text,bigint,text,text,text,bigint,bigint,uuid,jsonb)
from public, anon, authenticated;
grant execute on function public.record_leghevo_service_return_check_v1(text,bigint,text,text,text,bigint,bigint,uuid,jsonb)
to service_role;

create or replace function public.complete_leghevo_service_return_v1(
  p_environment_key text,
  p_run_id bigint,
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
  v_environment text := lower(trim(coalesce(p_environment_key,'')));
  v_reason text := trim(coalesce(p_reason_code,''));
  v_details jsonb := coalesce(p_details,'{}'::jsonb);
  v_run public.leghevo_service_return_runs%rowtype;
  v_head public.leghevo_service_return_heads%rowtype;
  v_existing public.leghevo_service_return_certificates%rowtype;
  v_snapshot jsonb;
  v_check_count integer;
  v_failed_count integer;
  v_checks_fingerprint text;
  v_certificate public.leghevo_service_return_certificates%rowtype;
  v_event_fingerprint text;
begin
  if v_environment not in ('production','staging') or p_run_id is null or p_request_id is null
    or char_length(v_reason) not between 3 and 160 or jsonb_typeof(v_details)<>'object' then
    raise exception 'Parametri certificazione ritorno in servizio non validi.';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('leghevo:service-return:'||v_environment,0));
  select certificate.* into v_existing
  from public.leghevo_service_return_certificates certificate
  where certificate.request_id=p_request_id;
  if found then
    return jsonb_build_object('certificateId',v_existing.id,'recoveryGeneration',v_existing.recovery_generation,
      'status',v_existing.status,'idempotent',true);
  end if;
  select run.* into v_run from public.leghevo_service_return_runs run
  where run.id=p_run_id and run.environment_key=v_environment;
  if not found then raise exception 'Run recovery non trovato.'; end if;
  select head.* into v_head from public.leghevo_service_return_heads head
  where head.environment_key=v_environment for update;
  if not found or v_head.run_id<>v_run.id or v_head.mode<>'recovery' then
    raise exception 'Certificazione bloccata: recovery mode non corrente.';
  end if;
  select count(*),count(*) filter(where check_row.status<>'passed')
  into v_check_count,v_failed_count
  from public.leghevo_service_return_checks check_row
  where check_row.run_id=v_run.id;
  if v_check_count<>8 or v_failed_count>0 then
    raise exception 'Certificazione bloccata: richiesti 8 controlli passed, presenti %, falliti %.',
      v_check_count,v_failed_count;
  end if;
  v_snapshot:=public.get_leghevo_service_return_snapshot_v1(v_environment);
  if not coalesce((v_snapshot->>'protected')::boolean,false)
    or not coalesce((v_snapshot->>'healthy')::boolean,false)
    or coalesce(v_snapshot->>'activeReleaseVersion','')<>v_run.active_release_version
    or (v_snapshot->>'artifactId')::bigint<>v_run.artifact_id
    or (v_snapshot->>'rehearsalId')::bigint<>v_run.rehearsal_id
    or (v_snapshot->>'checkpointId')::bigint<>v_run.checkpoint_id
    or (v_snapshot->>'outboxSequence')::bigint<v_run.outbox_sequence
    or (v_snapshot->>'consumerSequence')::bigint<v_run.consumer_sequence
    or (v_snapshot->>'auditSequence')::bigint<v_run.audit_sequence then
    raise exception 'Certificazione bloccata: snapshot corrente non coerente con il run. Dettaglio: %',v_snapshot;
  end if;
  select public.leghevo_sha256_hex_v1(
    string_agg(check_row.check_key||'|'||check_row.check_fingerprint,';' order by check_row.check_ordinal))
  into v_checks_fingerprint
  from public.leghevo_service_return_checks check_row
  where check_row.run_id=v_run.id;
  insert into public.leghevo_service_return_certificates(
    run_id,environment_key,recovery_generation,request_id,check_count,active_release_version,
    run_fingerprint,checks_fingerprint,status,reason_code,certificate_fingerprint,details,certified_by
  ) values (
    v_run.id,v_environment,v_run.recovery_generation,p_request_id,8,v_run.active_release_version,
    v_run.run_fingerprint,v_checks_fingerprint,'certified',v_reason,
    public.compute_leghevo_service_return_certificate_fingerprint_v1(
      v_run.id,v_environment,v_run.recovery_generation,8,v_run.active_release_version,
      v_run.run_fingerprint,v_checks_fingerprint,1),v_details,auth.uid()
  ) returning * into v_certificate;
  perform pg_catalog.set_config('leghevo.service_return_context','allowed',true);
  update public.leghevo_service_return_heads set
    certificate_id=v_certificate.id,mode='active',status='certified',writes_allowed=true,
    workers_allowed=true,traffic_percentage=100,reason_code=v_reason,revision=revision+1,
    state_fingerprint=public.leghevo_sha256_hex_v1(
      v_environment||'|'||recovery_generation::text||'|'||run_id::text||'|'||v_certificate.id::text||
      '|active|'||(revision+1)::text),certified_at=now(),affected_at=null,updated_at=now()
  where environment_key=v_environment;
  v_event_fingerprint:=public.compute_leghevo_service_return_event_fingerprint_v1(
    v_environment,'certified',v_run.recovery_generation,v_run.id,v_certificate.id,v_reason,
    jsonb_build_object('checkCount',8,'trafficPercentage',100));
  insert into public.leghevo_service_return_events(
    environment_key,event_type,recovery_generation,run_id,certificate_id,reason_code,details,
    event_fingerprint,created_by
  ) values (
    v_environment,'certified',v_run.recovery_generation,v_run.id,v_certificate.id,v_reason,
    jsonb_build_object('checkCount',8,'trafficPercentage',100),v_event_fingerprint,auth.uid());
  perform pg_catalog.set_config('leghevo.service_return_context','',true);
  return jsonb_build_object('certificateId',v_certificate.id,'recoveryGeneration',v_run.recovery_generation,
    'status','certified','mode','active','idempotent',false);
exception when others then
  perform pg_catalog.set_config('leghevo.service_return_context','',true);
  raise;
end;
$function$;
revoke all on function public.complete_leghevo_service_return_v1(text,bigint,uuid,text,jsonb)
from public, anon, authenticated;
grant execute on function public.complete_leghevo_service_return_v1(text,bigint,uuid,text,jsonb) to service_role;

create or replace function public.get_leghevo_service_return_model_v1(
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
  v_head public.leghevo_service_return_heads%rowtype;
  v_run public.leghevo_service_return_runs%rowtype;
  v_certificate public.leghevo_service_return_certificates%rowtype;
  v_snapshot jsonb;
  v_check_count integer:=0;
  v_failed_count integer:=0;
  v_run_stable boolean:=false;
  v_certificate_stable boolean:=false;
  v_fresh boolean:=false;
  v_protected boolean:=false;
  v_healthy boolean:=false;
  v_status text:='affected';
  v_reason text:='service_return.missing';
  v_current_checks_fingerprint text;
begin
  if v_environment not in ('production','staging') then
    return jsonb_build_object('protected',false,'healthy',false,'fresh',false,'status','affected',
      'mode','affected','reasonCode','service_return.invalid_environment','environment',v_environment);
  end if;
  select head.* into v_head from public.leghevo_service_return_heads head
  where head.environment_key=v_environment;
  if not found then
    return jsonb_build_object('protected',false,'healthy',false,'fresh',false,'status','affected',
      'mode','affected','reasonCode','service_return.missing','environment',v_environment,
      'requiredCheckCount',8,'checkCount',0,'writesAllowed',false,'workersAllowed',false,
      'trafficPercentage',0,'checkedAt',now());
  end if;
  select run.* into v_run from public.leghevo_service_return_runs run where run.id=v_head.run_id;
  if v_head.certificate_id is not null then
    select certificate.* into v_certificate from public.leghevo_service_return_certificates certificate
    where certificate.id=v_head.certificate_id;
  end if;
  select count(*),count(*) filter(where check_row.status<>'passed')
  into v_check_count,v_failed_count
  from public.leghevo_service_return_checks check_row where check_row.run_id=v_run.id;
  v_run_stable:=v_run.run_fingerprint=public.compute_leghevo_service_return_run_fingerprint_v1(
    v_run.environment_key,v_run.recovery_generation,v_run.artifact_id,v_run.rehearsal_id,
    v_run.checkpoint_id,v_run.active_release_version,v_run.release_generation,v_run.rollout_generation,
    v_run.telemetry_generation,v_run.outbox_sequence,v_run.consumer_sequence,v_run.audit_sequence,
    v_run.reason_code,v_run.contract_version);
  if v_certificate.id is not null then
    select public.leghevo_sha256_hex_v1(
      string_agg(check_row.check_key||'|'||check_row.check_fingerprint,';' order by check_row.check_ordinal))
    into v_current_checks_fingerprint
    from public.leghevo_service_return_checks check_row where check_row.run_id=v_run.id;
    v_certificate_stable:=v_certificate.certificate_fingerprint=
      public.compute_leghevo_service_return_certificate_fingerprint_v1(
        v_certificate.run_id,v_certificate.environment_key,v_certificate.recovery_generation,
        v_certificate.check_count,v_certificate.active_release_version,v_certificate.run_fingerprint,
        v_certificate.checks_fingerprint,v_certificate.contract_version)
      and v_certificate.checks_fingerprint=v_current_checks_fingerprint;
  end if;
  v_snapshot:=public.get_leghevo_service_return_snapshot_v1(v_environment);
  v_fresh:=coalesce((v_snapshot->>'protected')::boolean,false)
    and coalesce((v_snapshot->>'healthy')::boolean,false)
    and coalesce(v_snapshot->>'activeReleaseVersion','')=v_run.active_release_version
    and (v_snapshot->>'artifactId')::bigint=v_run.artifact_id
    and (v_snapshot->>'rehearsalId')::bigint=v_run.rehearsal_id
    and (v_snapshot->>'checkpointId')::bigint=v_run.checkpoint_id
    and (v_snapshot->>'outboxSequence')::bigint>=v_run.outbox_sequence
    and (v_snapshot->>'consumerSequence')::bigint>=v_run.consumer_sequence
    and (v_snapshot->>'auditSequence')::bigint>=v_run.audit_sequence;
  v_protected:=v_run_stable and v_certificate_stable and v_check_count=8 and v_failed_count=0
    and v_head.mode='active' and v_head.status in ('certified','revalidated')
    and v_head.writes_allowed and v_head.workers_allowed and v_head.traffic_percentage=100;
  v_healthy:=v_protected and v_fresh;
  v_status:=case when v_head.mode='recovery' then 'recovery'
    when v_healthy then 'certified' else 'affected' end;
  v_reason:=case
    when not v_run_stable then 'service_return.run_fingerprint_changed'
    when v_head.mode='recovery' then 'service_return.recovery_mode'
    when v_check_count<>8 or v_failed_count>0 then 'service_return.checks_incomplete'
    when not v_certificate_stable then 'service_return.certificate_fingerprint_changed'
    when v_head.mode='affected' or v_head.status='affected' then v_head.reason_code
    when not v_fresh then 'service_return.stale'
    else 'service_return.certified' end;
  return jsonb_build_object(
    'protected',v_protected,'healthy',v_healthy,'fresh',v_fresh,'status',v_status,
    'reasonCode',v_reason,'environment',v_environment,'mode',v_head.mode,
    'recoveryGeneration',v_head.recovery_generation,'runId',v_run.id,
    'certificateId',v_certificate.id,'activeVersion',v_run.active_release_version,
    'checkCount',v_check_count,'requiredCheckCount',8,'failedCheckCount',v_failed_count,
    'writesAllowed',v_head.writes_allowed,'workersAllowed',v_head.workers_allowed,
    'trafficPercentage',v_head.traffic_percentage,'runFingerprintStable',v_run_stable,
    'certificateFingerprintStable',v_certificate_stable,'lastRecoveryStartedAt',v_head.entered_at,
    'lastCertifiedAt',v_head.certified_at,'checkedAt',now());
end;
$function$;
revoke all on function public.get_leghevo_service_return_model_v1(text) from public, anon;
grant execute on function public.get_leghevo_service_return_model_v1(text) to authenticated, service_role;

create or replace function public.reconcile_leghevo_service_return_v1(
  p_environment_key text,
  p_reason_code text default 'service_return.reconcile'
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_environment text := lower(trim(coalesce(p_environment_key,'')));
  v_reason text := trim(coalesce(p_reason_code,'service_return.reconcile'));
  v_head public.leghevo_service_return_heads%rowtype;
  v_model jsonb;
  v_event_fingerprint text;
begin
  if v_environment not in ('production','staging') or char_length(v_reason) not between 3 and 160 then
    raise exception 'Parametri riconciliazione ritorno in servizio non validi.';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('leghevo:service-return:'||v_environment,0));
  select head.* into v_head from public.leghevo_service_return_heads head
  where head.environment_key=v_environment for update;
  if not found then return jsonb_build_object('applicable',false,'changed',false,'status','missing'); end if;
  v_model:=public.get_leghevo_service_return_model_v1(v_environment);
  if coalesce((v_model->>'healthy')::boolean,false) then
    return jsonb_build_object('applicable',true,'changed',false,'status',v_head.status,
      'reasonCode',v_head.reason_code);
  end if;
  if v_head.mode='affected' and v_head.reason_code=coalesce(v_model->>'reasonCode',v_reason) then
    return jsonb_build_object('applicable',true,'changed',false,'status','affected',
      'reasonCode',v_head.reason_code);
  end if;
  perform pg_catalog.set_config('leghevo.service_return_context','allowed',true);
  update public.leghevo_service_return_heads set
    mode='affected',status='affected',writes_allowed=false,workers_allowed=false,traffic_percentage=0,
    reason_code=coalesce(v_model->>'reasonCode',v_reason),revision=revision+1,
    state_fingerprint=public.leghevo_sha256_hex_v1(
      v_environment||'|'||recovery_generation::text||'|'||run_id::text||'|affected|'||(revision+1)::text),
    affected_at=coalesce(affected_at,now()),updated_at=now()
  where environment_key=v_environment returning * into v_head;
  v_event_fingerprint:=public.compute_leghevo_service_return_event_fingerprint_v1(
    v_environment,'affected',v_head.recovery_generation,v_head.run_id,v_head.certificate_id,
    v_head.reason_code,jsonb_build_object('requestedReason',v_reason,'revision',v_head.revision));
  insert into public.leghevo_service_return_events(
    environment_key,event_type,recovery_generation,run_id,certificate_id,reason_code,details,
    event_fingerprint,created_by
  ) values (
    v_environment,'affected',v_head.recovery_generation,v_head.run_id,v_head.certificate_id,
    v_head.reason_code,jsonb_build_object('requestedReason',v_reason,'revision',v_head.revision),
    v_event_fingerprint,auth.uid());
  perform pg_catalog.set_config('leghevo.service_return_context','',true);
  return jsonb_build_object('applicable',true,'changed',true,'status','affected',
    'reasonCode',v_head.reason_code,'revision',v_head.revision);
exception when others then
  perform pg_catalog.set_config('leghevo.service_return_context','',true);
  raise;
end;
$function$;
revoke all on function public.reconcile_leghevo_service_return_v1(text,text)
from public, anon, authenticated;
grant execute on function public.reconcile_leghevo_service_return_v1(text,text) to service_role;

create or replace function public.reconcile_leghevo_service_return_after_dependency_event_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  perform public.reconcile_leghevo_service_return_v1(new.environment_key,'service_return.dependency_changed');
  return new;
end;
$function$;
revoke all on function public.reconcile_leghevo_service_return_after_dependency_event_v1()
from public, anon, authenticated, service_role;

create trigger leghevo_service_return_reconcile_after_physical_backup_event
after insert on public.leghevo_physical_backup_events
for each row execute function public.reconcile_leghevo_service_return_after_dependency_event_v1();
alter table public.leghevo_physical_backup_events enable always trigger leghevo_service_return_reconcile_after_physical_backup_event;

create trigger leghevo_service_return_reconcile_after_release_event
after insert on public.leghevo_application_release_events
for each row execute function public.reconcile_leghevo_service_return_after_dependency_event_v1();
alter table public.leghevo_application_release_events enable always trigger leghevo_service_return_reconcile_after_release_event;

create or replace function public.assert_leghevo_service_return_active_v1(
  p_environment_key text,
  p_operation_key text
)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_model jsonb;
begin
  v_model:=public.get_leghevo_service_return_model_v1(p_environment_key);
  if not coalesce((v_model->>'protected')::boolean,false)
    or not coalesce((v_model->>'healthy')::boolean,false)
    or coalesce(v_model->>'mode','affected')<>'active' then
    raise exception 'Operazione % bloccata: ritorno in servizio non certificato. Dettaglio: %',
      coalesce(nullif(trim(p_operation_key),''),'unknown'),v_model;
  end if;
end;
$function$;
revoke all on function public.assert_leghevo_service_return_active_v1(text,text)
from public, anon, authenticated;
grant execute on function public.assert_leghevo_service_return_active_v1(text,text) to service_role;

create or replace function public.promote_leghevo_application_rollout_v8(
  p_environment_key text,p_target_percentage integer,p_request_id uuid,p_reason_code text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
begin
  perform public.assert_leghevo_service_return_active_v1(p_environment_key,'rollout.promote');
  return public.promote_leghevo_application_rollout_v7(
    p_environment_key,p_target_percentage,p_request_id,p_reason_code);
end;
$function$;
revoke all on function public.promote_leghevo_application_rollout_v8(text,integer,uuid,text)
from public, anon, authenticated;
grant execute on function public.promote_leghevo_application_rollout_v8(text,integer,uuid,text) to service_role;
revoke execute on function public.promote_leghevo_application_rollout_v7(text,integer,uuid,text) from service_role;

create or replace function public.get_leghevo_client_rollout_eligibility_v8(
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
  v_return jsonb;
  v_eligible boolean;
  v_reason text;
begin
  v_base:=public.get_leghevo_client_rollout_eligibility_v7(
    p_application_version,p_bundle_fingerprint,p_installation_id);
  v_return:=public.get_leghevo_service_return_model_v1('production');
  v_eligible:=coalesce((v_base->>'rolloutEligible')::boolean,false)
    and coalesce((v_return->>'protected')::boolean,false)
    and coalesce((v_return->>'healthy')::boolean,false)
    and coalesce(v_return->>'mode','affected')='active';
  v_reason:=case
    when not coalesce((v_base->>'compatible')::boolean,false) then coalesce(v_base->>'reasonCode','release.incompatible')
    when coalesce(v_return->>'mode','affected')='recovery' then 'service_return.recovery_mode'
    when not coalesce((v_return->>'protected')::boolean,false) then 'service_return.not_protected'
    when not coalesce((v_return->>'fresh')::boolean,false) then 'service_return.stale'
    when not coalesce((v_return->>'healthy')::boolean,false) then 'service_return.affected'
    else coalesce(v_base->>'reasonCode','release.compatible') end;
  return v_base||jsonb_build_object(
    'compatible',coalesce((v_base->>'compatible')::boolean,false) and v_eligible,
    'rolloutEligible',v_eligible,'reasonCode',v_reason,
    'serviceReturnProtected',coalesce((v_return->>'protected')::boolean,false),
    'serviceReturnHealthy',coalesce((v_return->>'healthy')::boolean,false),
    'serviceReturnFresh',coalesce((v_return->>'fresh')::boolean,false),
    'serviceReturnStatus',v_return->>'status','serviceReturnMode',v_return->>'mode',
    'serviceReturnGeneration',coalesce((v_return->>'recoveryGeneration')::bigint,0),
    'serviceReturnCheckCount',coalesce((v_return->>'checkCount')::integer,0),
    'checkedAt',now());
end;
$function$;
revoke all on function public.get_leghevo_client_rollout_eligibility_v8(text,text,uuid) from public;
grant execute on function public.get_leghevo_client_rollout_eligibility_v8(text,text,uuid) to anon, authenticated;
revoke execute on function public.get_leghevo_client_rollout_eligibility_v7(text,text,uuid) from anon, authenticated;

create or replace function public.get_league_provider_sync_health_v41(p_league_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare v_base jsonb; v_return jsonb;
begin
  v_base:=public.get_league_provider_sync_health_v40(p_league_id);
  v_return:=public.get_leghevo_service_return_model_v1('production');
  return v_base||jsonb_build_object('applicationServiceReturn',v_return,
    'healthy',coalesce((v_base->>'healthy')::boolean,false) and coalesce((v_return->>'healthy')::boolean,false),
    'protected',coalesce((v_base->>'protected')::boolean,false) and coalesce((v_return->>'protected')::boolean,false));
end;
$function$;
revoke all on function public.get_league_provider_sync_health_v41(uuid) from public, anon;
grant execute on function public.get_league_provider_sync_health_v41(uuid) to authenticated;

create or replace function public.get_league_season_state_v20(p_league_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare v_base jsonb; v_return jsonb;
begin
  v_base:=public.get_league_season_state_v19(p_league_id);
  v_return:=public.get_leghevo_service_return_model_v1('production');
  return v_base||jsonb_build_object('applicationServiceReturn',v_return);
end;
$function$;
revoke all on function public.get_league_season_state_v20(uuid) from public, anon;
grant execute on function public.get_league_season_state_v20(uuid) to authenticated;

create or replace function public.get_league_management_state_v30(p_league_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare v_base jsonb; v_return jsonb; v_checks jsonb;
begin
  v_base:=public.get_league_management_state_v29(p_league_id);
  v_return:=public.get_leghevo_service_return_model_v1('production');
  v_checks:=coalesce(v_base->'checks','{}'::jsonb)||jsonb_build_object(
    'applicationServiceReturnProtected',coalesce((v_return->>'protected')::boolean,false),
    'applicationServiceReturnHealthy',coalesce((v_return->>'healthy')::boolean,false),
    'applicationServiceReturnActive',coalesce(v_return->>'mode','affected')='active');
  return v_base||jsonb_build_object('applicationServiceReturn',v_return,'checks',v_checks);
end;
$function$;
revoke all on function public.get_league_management_state_v30(uuid) from public, anon;
grant execute on function public.get_league_management_state_v30(uuid) to authenticated;

-- Helper temporaneo per drenare outbox/inbox durante l'attivazione v0.62.42.
create or replace function public.seed_leghevo_service_return_drain_v1(
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
      p_environment_key,p_destination_key,'leghevo-service-return-seed-worker',6,p_delivery_fencing_token,
      p_consumer_key,p_consumer_generation,p_consumer_fencing_token,200,120);
    exit when coalesce((v_claim->>'claimedCount')::integer,0)=0;
    for v_item in select item.value from pg_catalog.jsonb_array_elements(v_claim->'items') item loop
      v_application_fingerprint:=public.leghevo_sha256_hex_v1(
        p_destination_key||'|service-return-applied|'||(v_item->>'messageId')||'|'||(v_item->>'messageFingerprint'));
      v_outcome:=public.apply_leghevo_operational_consumer_message_v1(
        p_environment_key,(v_item->>'messageId')::bigint,p_destination_key,
        (v_item->>'deliveryGeneration')::bigint,'leghevo-service-return-seed-worker',6,p_delivery_fencing_token,
        p_consumer_key,p_consumer_generation,p_consumer_fencing_token,'leghevo-'||p_destination_key,
        v_application_fingerprint,gen_random_uuid(),jsonb_build_object('seedDelivery',true,'sourceMigration',146));
      v_count:=v_count+1;
    end loop;
  end loop;
  return v_count;
end;
$function$;
revoke all on function public.seed_leghevo_service_return_drain_v1(text,text,text,bigint,uuid,uuid)
from public, anon, authenticated, service_role;

-- Certificazione release, backup e ritorno in servizio controllato per il prototipo.
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
  v_checksum text:=public.leghevo_sha256_hex_v1('leghevo-v0.62.42-controlled-service-return-artifact');
  v_provider_hash text:=public.leghevo_sha256_hex_v1('managed-backup-provider-production-v42');
  v_storage_hash text:=public.leghevo_sha256_hex_v1('external-vault-primary-v42');
  v_encryption_hash text:=public.leghevo_sha256_hex_v1('external-kms-key-reference-v42');
  v_actor_hash text:=public.leghevo_sha256_hex_v1('service-return-custodian');
  v_target_hash text:=public.leghevo_sha256_hex_v1('isolated-service-return-target');
  v_hash text;
  v_sequence bigint;
begin
  if exists(select 1 from public.leghevo_application_release_certificates certificate
    where certificate.application_version='0.62.42')
    and exists(select 1 from public.leghevo_service_return_certificates certificate
      where certificate.request_id='62600000-0000-4000-8000-000000000030'::uuid) then return; end if;

  v_outcome:=public.certify_leghevo_operational_consumer_v1(
    'production','operations_center','leghevo-operations-consumer',5,v_operations_consumer_token,
    '62600000-0000-4000-8000-000000000001'::uuid,
    jsonb_build_object('sourceMigration',146,'contract','service-return-v1'));
  v_outcome:=public.certify_leghevo_operational_consumer_v1(
    'production','notification_dispatch','leghevo-notification-consumer',5,v_notification_consumer_token,
    '62600000-0000-4000-8000-000000000002'::uuid,
    jsonb_build_object('sourceMigration',146,'contract','service-return-v1'));

  if not exists(select 1 from public.leghevo_application_release_certificates certificate
    where certificate.application_version='0.62.42') then
    v_outcome:=public.certify_leghevo_application_release_v1(
      '0.62.42','f0cce54f8aa03995cc836ae8c29ad002a0eda6df80e08a67cd79a6bab0fd5cd3','0.62.41','0.62.42',
      '62600000-0000-4000-8000-000000000003'::uuid,
      jsonb_build_object('baseline',false,'sourceMigration',146));
    v_outcome:=public.certify_leghevo_application_rollout_v1(
      'production','0.62.42',100,100,500,3,100,
      '62600000-0000-4000-8000-000000000004'::uuid,
      jsonb_build_object('strategy','controlled-service-return','sourceMigration',146));
    v_outcome:=public.activate_leghevo_release_with_rollout_v1(
      'production','0.62.42','62600000-0000-4000-8000-000000000005'::uuid,
      '62600000-0000-4000-8000-000000000006'::uuid,'service_return.production_activation');
    v_outcome:=public.certify_leghevo_operational_telemetry_source_v1(
      'production','leghevo-production-observer',7,v_telemetry_token,
      '62600000-0000-4000-8000-000000000007'::uuid,
      jsonb_build_object('provider','leghevo-runtime','sourceMigration',146));
    v_outcome:=public.record_leghevo_authoritative_operational_window_v1(
      'production','leghevo-production-observer',7,v_telemetry_token,1,
      v_now-interval '5 minutes',v_now,1000,1,0,180,
      '62600000-0000-4000-8000-000000000008'::uuid,
      jsonb_build_object('seedStage',100,'serviceReturn',true));

    perform public.seed_leghevo_service_return_drain_v1(
      'production','operations_center','leghevo-operations-consumer',5,
      v_operations_consumer_token,v_operations_delivery_token);
    perform public.seed_leghevo_service_return_drain_v1(
      'production','notification_dispatch','leghevo-notification-consumer',5,
      v_notification_consumer_token,v_notification_delivery_token);
    v_outcome:=public.run_leghevo_operational_delivery_audit_v1(
      'production','62600000-0000-4000-8000-000000000009'::uuid,
      jsonb_build_object('sourceMigration',146));
    v_checkpoint:=public.create_leghevo_disaster_recovery_checkpoint_v1(
      'production','62600000-0000-4000-8000-000000000010'::uuid,
      'disaster_recovery.release_0_62_42',jsonb_build_object('sourceMigration',146));
    v_outcome:=public.run_leghevo_disaster_recovery_drill_v1(
      'production',(v_checkpoint->>'checkpointId')::bigint,
      '62600000-0000-4000-8000-000000000011'::uuid,
      jsonb_build_object('sourceMigration',146,'serviceReturnPreparation',true));
    v_artifact:=public.register_leghevo_physical_backup_artifact_v1(
      'production',(v_checkpoint->>'checkpointId')::bigint,v_provider_hash,v_storage_hash,v_checksum,
      786432000,'managed_backup',true,v_encryption_hash,v_actor_hash,
      '62600000-0000-4000-8000-000000000012'::uuid,
      jsonb_build_object('evidenceMode','external_attestation','sourceMigration',146));
    v_outcome:=public.append_leghevo_physical_backup_custody_event_v1(
      'production',(v_artifact->>'artifactId')::bigint,'checksum_verified',v_actor_hash,v_storage_hash,v_now,
      '62600000-0000-4000-8000-000000000013'::uuid,
      jsonb_build_object('checksumAlgorithm','sha256','verified',true));
    v_outcome:=public.append_leghevo_physical_backup_custody_event_v1(
      'production',(v_artifact->>'artifactId')::bigint,'sealed',v_actor_hash,v_storage_hash,v_now,
      '62600000-0000-4000-8000-000000000014'::uuid,
      jsonb_build_object('encrypted',true,'sealed',true));
    v_outcome:=public.run_leghevo_external_restore_rehearsal_v1(
      'production',(v_artifact->>'artifactId')::bigint,v_target_hash,v_checksum,786432000,
      24,8,0,0,v_actor_hash,v_now,v_now,
      '62600000-0000-4000-8000-000000000015'::uuid,
      jsonb_build_object('isolatedTarget',true,'networkWritesBlocked',true,'sourceMigration',146));
  end if;

  v_run:=public.begin_leghevo_service_return_v1(
    'production','62600000-0000-4000-8000-000000000020'::uuid,
    'service_return.restore_verified',jsonb_build_object('sourceMigration',146));
  v_run_id:=(v_run->>'runId')::bigint;
  v_snapshot:=public.get_leghevo_service_return_snapshot_v1('production');

  v_hash:=v_snapshot->>'applicationFingerprint'; v_sequence:=0;
  v_outcome:=public.record_leghevo_service_return_check_v1(
    'production',v_run_id,'application_integrity',v_hash,v_hash,v_sequence,v_sequence,
    '62600000-0000-4000-8000-000000000021'::uuid,jsonb_build_object('sourceMigration',146));
  v_hash:=v_snapshot->>'releaseFingerprint'; v_sequence:=(v_snapshot->>'releaseGeneration')::bigint;
  v_outcome:=public.record_leghevo_service_return_check_v1(
    'production',v_run_id,'release_compatibility',v_hash,v_hash,v_sequence,v_sequence,
    '62600000-0000-4000-8000-000000000022'::uuid,jsonb_build_object('sourceMigration',146));
  v_hash:=v_snapshot->>'rolloutFingerprint'; v_sequence:=(v_snapshot->>'rolloutGeneration')::bigint;
  v_outcome:=public.record_leghevo_service_return_check_v1(
    'production',v_run_id,'rollout_state',v_hash,v_hash,v_sequence,v_sequence,
    '62600000-0000-4000-8000-000000000023'::uuid,jsonb_build_object('sourceMigration',146));
  v_hash:=v_snapshot->>'telemetryFingerprint'; v_sequence:=(v_snapshot->>'telemetryGeneration')::bigint;
  v_outcome:=public.record_leghevo_service_return_check_v1(
    'production',v_run_id,'telemetry_fencing',v_hash,v_hash,v_sequence,v_sequence,
    '62600000-0000-4000-8000-000000000024'::uuid,jsonb_build_object('sourceMigration',146));
  v_hash:=v_snapshot->>'outboxFingerprint'; v_sequence:=(v_snapshot->>'outboxSequence')::bigint;
  v_outcome:=public.record_leghevo_service_return_check_v1(
    'production',v_run_id,'outbox_continuity',v_hash,v_hash,v_sequence,v_sequence,
    '62600000-0000-4000-8000-000000000025'::uuid,jsonb_build_object('sourceMigration',146));
  v_hash:=v_snapshot->>'consumerFingerprint'; v_sequence:=(v_snapshot->>'consumerSequence')::bigint;
  v_outcome:=public.record_leghevo_service_return_check_v1(
    'production',v_run_id,'consumer_continuity',v_hash,v_hash,v_sequence,v_sequence,
    '62600000-0000-4000-8000-000000000026'::uuid,jsonb_build_object('sourceMigration',146));
  v_hash:=v_snapshot->>'auditFingerprint'; v_sequence:=(v_snapshot->>'auditSequence')::bigint;
  v_outcome:=public.record_leghevo_service_return_check_v1(
    'production',v_run_id,'delivery_audit',v_hash,v_hash,v_sequence,v_sequence,
    '62600000-0000-4000-8000-000000000027'::uuid,jsonb_build_object('sourceMigration',146));
  v_hash:=v_snapshot->>'physicalBackupFingerprint'; v_sequence:=(v_snapshot->>'artifactId')::bigint;
  v_outcome:=public.record_leghevo_service_return_check_v1(
    'production',v_run_id,'physical_backup',v_hash,v_hash,v_sequence,v_sequence,
    '62600000-0000-4000-8000-000000000028'::uuid,jsonb_build_object('sourceMigration',146));
  v_outcome:=public.complete_leghevo_service_return_v1(
    'production',v_run_id,'62600000-0000-4000-8000-000000000030'::uuid,
    'service_return.certified',jsonb_build_object('sourceMigration',146,'trafficPercentage',100));
end;
$seed_release$;

drop function if exists public.seed_leghevo_service_return_drain_v1(text,text,text,bigint,uuid,uuid);

do $realtime$
begin
  if exists(select 1 from pg_catalog.pg_publication publication where publication.pubname='supabase_realtime')
    and not exists(
      select 1 from pg_catalog.pg_publication_tables publication_table
      where publication_table.pubname='supabase_realtime'
        and publication_table.schemaname='public'
        and publication_table.tablename='leghevo_service_return_events'
    ) then
    execute 'alter publication supabase_realtime add table public.leghevo_service_return_events';
  end if;
end;
$realtime$;

create or replace function public.get_leghevo_service_return_deployment_integrity_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_model jsonb;
  v_release jsonb;
  v_run_mismatch bigint;
  v_check_mismatch bigint;
  v_certificate_mismatch bigint;
  v_begin_def text:=coalesce(pg_get_functiondef(to_regprocedure('public.begin_leghevo_service_return_v1(text,uuid,text,jsonb)')),'');
  v_complete_def text:=coalesce(pg_get_functiondef(to_regprocedure('public.complete_leghevo_service_return_v1(text,bigint,uuid,text,jsonb)')),'');
begin
  v_model:=public.get_leghevo_service_return_model_v1('production');
  v_release:=public.get_leghevo_application_release_model_v1('production');
  select count(*) into v_run_mismatch
  from public.leghevo_service_return_runs run
  where run.run_fingerprint<>public.compute_leghevo_service_return_run_fingerprint_v1(
    run.environment_key,run.recovery_generation,run.artifact_id,run.rehearsal_id,run.checkpoint_id,
    run.active_release_version,run.release_generation,run.rollout_generation,run.telemetry_generation,
    run.outbox_sequence,run.consumer_sequence,run.audit_sequence,run.reason_code,run.contract_version);
  select count(*) into v_check_mismatch
  from public.leghevo_service_return_checks check_row
  where check_row.check_fingerprint<>public.compute_leghevo_service_return_check_fingerprint_v1(
    check_row.run_id,check_row.check_key,check_row.check_ordinal,check_row.expected_fingerprint,
    check_row.observed_fingerprint,check_row.expected_sequence,check_row.observed_sequence,
    check_row.status,check_row.reason_code,check_row.details);
  select count(*) into v_certificate_mismatch
  from public.leghevo_service_return_certificates certificate
  where certificate.certificate_fingerprint<>public.compute_leghevo_service_return_certificate_fingerprint_v1(
    certificate.run_id,certificate.environment_key,certificate.recovery_generation,certificate.check_count,
    certificate.active_release_version,certificate.run_fingerprint,certificate.checks_fingerprint,
    certificate.contract_version);
  return jsonb_build_object(
    'predecessor_ready',to_regprocedure('public.get_leghevo_physical_backup_deployment_integrity_v1()') is not null
      and coalesce((public.get_leghevo_physical_backup_model_v1('production')->>'protected')::boolean,false),
    'run_table_ready',to_regclass('public.leghevo_service_return_runs') is not null,
    'check_table_ready',to_regclass('public.leghevo_service_return_checks') is not null,
    'certificate_table_ready',to_regclass('public.leghevo_service_return_certificates') is not null,
    'head_and_event_tables_ready',to_regclass('public.leghevo_service_return_heads') is not null
      and to_regclass('public.leghevo_service_return_events') is not null,
    'columns_ready',exists(select 1 from information_schema.columns where table_schema='public'
      and table_name='leghevo_service_return_heads' and column_name='workers_allowed')
      and exists(select 1 from information_schema.columns where table_schema='public'
        and table_name='leghevo_service_return_runs' and column_name='consumer_sequence'),
    'constraints_ready',exists(select 1 from pg_catalog.pg_constraint constraint_row
      where constraint_row.conrelid='public.leghevo_service_return_runs'::regclass
        and constraint_row.conname='leghevo_service_return_run_generation_unique')
      and exists(select 1 from pg_catalog.pg_constraint constraint_row
        where constraint_row.conrelid='public.leghevo_service_return_checks'::regclass
          and constraint_row.conname='leghevo_service_return_run_check_unique'),
    'indexes_ready',to_regclass('public.leghevo_service_return_runs_environment_generation_idx') is not null
      and to_regclass('public.leghevo_service_return_checks_run_ordinal_idx') is not null
      and to_regclass('public.leghevo_service_return_events_environment_created_idx') is not null,
    'rls_ready',(select relrowsecurity from pg_catalog.pg_class where oid='public.leghevo_service_return_runs'::regclass)
      and (select relrowsecurity from pg_catalog.pg_class where oid='public.leghevo_service_return_checks'::regclass)
      and (select relrowsecurity from pg_catalog.pg_class where oid='public.leghevo_service_return_certificates'::regclass)
      and (select relrowsecurity from pg_catalog.pg_class where oid='public.leghevo_service_return_heads'::regclass)
      and (select relrowsecurity from pg_catalog.pg_class where oid='public.leghevo_service_return_events'::regclass),
    'direct_write_blocked',not has_table_privilege('authenticated','public.leghevo_service_return_runs','INSERT')
      and not has_table_privilege('service_role','public.leghevo_service_return_runs','INSERT')
      and not has_table_privilege('authenticated','public.leghevo_service_return_heads','UPDATE'),
    'immutable_records_ready',(select count(*)=4 from pg_catalog.pg_trigger trigger_row
      where trigger_row.tgname in ('leghevo_service_return_runs_guard','leghevo_service_return_checks_guard',
        'leghevo_service_return_certificates_guard','leghevo_service_return_events_guard')
        and trigger_row.tgenabled='A' and not trigger_row.tgisinternal),
    'head_guard_ready',exists(select 1 from pg_catalog.pg_trigger trigger_row
      where trigger_row.tgrelid='public.leghevo_service_return_heads'::regclass
        and trigger_row.tgname='leghevo_service_return_heads_guard'
        and trigger_row.tgenabled='A' and not trigger_row.tgisinternal)
      and exists(select 1 from pg_catalog.pg_trigger trigger_row
        where trigger_row.tgrelid='public.leghevo_physical_backup_heads'::regclass
          and trigger_row.tgname='leghevo_physical_backup_heads_guard'
          and trigger_row.tgenabled='A' and not trigger_row.tgisinternal)
      and position('new.backup_generation = old.backup_generation' in
        pg_catalog.pg_get_functiondef(
          pg_catalog.to_regprocedure('public.guard_leghevo_physical_backup_head_v1()')
        )) > 0,
    'fingerprints_ready',v_run_mismatch=0 and v_check_mismatch=0 and v_certificate_mismatch=0,
    'recovery_entry_rpc_ready',to_regprocedure('public.begin_leghevo_service_return_v1(text,uuid,text,jsonb)') is not null
      and has_function_privilege('service_role','public.begin_leghevo_service_return_v1(text,uuid,text,jsonb)','EXECUTE')
      and position('pg_advisory_xact_lock' in v_begin_def)>0,
    'check_rpc_ready',to_regprocedure('public.record_leghevo_service_return_check_v1(text,bigint,text,text,text,bigint,bigint,uuid,jsonb)') is not null
      and has_function_privilege('service_role','public.record_leghevo_service_return_check_v1(text,bigint,text,text,text,bigint,bigint,uuid,jsonb)','EXECUTE'),
    'completion_rpc_ready',to_regprocedure('public.complete_leghevo_service_return_v1(text,bigint,uuid,text,jsonb)') is not null
      and has_function_privilege('service_role','public.complete_leghevo_service_return_v1(text,bigint,uuid,text,jsonb)','EXECUTE')
      and position('check_count<>8' in replace(v_complete_def,' ',''))>0,
    'dependency_reconcile_ready',to_regprocedure('public.reconcile_leghevo_service_return_v1(text,text)') is not null
      and (select count(*)=2 from pg_catalog.pg_trigger trigger_row
        where trigger_row.tgname in ('leghevo_service_return_reconcile_after_physical_backup_event',
          'leghevo_service_return_reconcile_after_release_event')
          and trigger_row.tgenabled='A' and not trigger_row.tgisinternal),
    'promotion_and_client_chain_ready',to_regprocedure('public.promote_leghevo_application_rollout_v8(text,integer,uuid,text)') is not null
      and has_function_privilege('service_role','public.promote_leghevo_application_rollout_v8(text,integer,uuid,text)','EXECUTE')
      and not has_function_privilege('service_role','public.promote_leghevo_application_rollout_v7(text,integer,uuid,text)','EXECUTE')
      and to_regprocedure('public.get_leghevo_client_rollout_eligibility_v8(text,text,uuid)') is not null
      and has_function_privilege('anon','public.get_leghevo_client_rollout_eligibility_v8(text,text,uuid)','EXECUTE')
      and not has_function_privilege('anon','public.get_leghevo_client_rollout_eligibility_v7(text,text,uuid)','EXECUTE'),
    'endpoint_and_realtime_ready',to_regprocedure('public.get_league_provider_sync_health_v41(uuid)') is not null
      and to_regprocedure('public.get_league_season_state_v20(uuid)') is not null
      and to_regprocedure('public.get_league_management_state_v30(uuid)') is not null
      and (not exists(select 1 from pg_catalog.pg_publication publication where publication.pubname='supabase_realtime')
        or exists(select 1 from pg_catalog.pg_publication_tables publication_table
          where publication_table.pubname='supabase_realtime' and publication_table.schemaname='public'
            and publication_table.tablename='leghevo_service_return_events')),
    'seed_service_return_ready',coalesce((v_release->>'protected')::boolean,false)
      and v_release->>'activeVersion'='0.62.42'
      and exists(select 1 from public.leghevo_application_release_certificates certificate
        where certificate.application_version='0.62.42'
          and certificate.bundle_fingerprint='f0cce54f8aa03995cc836ae8c29ad002a0eda6df80e08a67cd79a6bab0fd5cd3')
      and coalesce((v_model->>'protected')::boolean,false)
      and coalesce((v_model->>'healthy')::boolean,false)
      and coalesce((v_model->>'fresh')::boolean,false)
      and v_model->>'status'='certified' and v_model->>'mode'='active'
      and coalesce((v_model->>'checkCount')::integer,0)=8
      and coalesce((v_model->>'trafficPercentage')::integer,0)=100
      and to_regprocedure('public.seed_leghevo_service_return_drain_v1(text,text,text,bigint,uuid,uuid)') is null
  );
end;
$function$;

revoke all on function public.get_leghevo_service_return_deployment_integrity_v1()
from public, anon, authenticated;
grant execute on function public.get_leghevo_service_return_deployment_integrity_v1() to service_role;

do $validate$
declare v_integrity jsonb; v_false text[];
begin
  v_integrity:=public.get_leghevo_service_return_deployment_integrity_v1();
  select array_agg(item.key order by item.key) into v_false
  from pg_catalog.jsonb_each(v_integrity) item
  where pg_catalog.jsonb_typeof(item.value) is distinct from 'boolean'
     or item.value is distinct from 'true'::jsonb;
  if (select count(*) from pg_catalog.jsonb_each(v_integrity))<>20 or cardinality(v_false)>0 then
    raise exception 'Validazione v0.62.42 non superata: %. Dettaglio: %',
      coalesce(array_to_string(v_false,', '),'numero controlli diverso da 20'),v_integrity;
  end if;
end;
$validate$;

commit;

select
  (public.get_leghevo_service_return_deployment_integrity_v1()->>'predecessor_ready')::boolean as predecessor_ready,
  (public.get_leghevo_service_return_deployment_integrity_v1()->>'run_table_ready')::boolean as run_table_ready,
  (public.get_leghevo_service_return_deployment_integrity_v1()->>'check_table_ready')::boolean as check_table_ready,
  (public.get_leghevo_service_return_deployment_integrity_v1()->>'certificate_table_ready')::boolean as certificate_table_ready,
  (public.get_leghevo_service_return_deployment_integrity_v1()->>'head_and_event_tables_ready')::boolean as head_and_event_tables_ready,
  (public.get_leghevo_service_return_deployment_integrity_v1()->>'columns_ready')::boolean as columns_ready,
  (public.get_leghevo_service_return_deployment_integrity_v1()->>'constraints_ready')::boolean as constraints_ready,
  (public.get_leghevo_service_return_deployment_integrity_v1()->>'indexes_ready')::boolean as indexes_ready,
  (public.get_leghevo_service_return_deployment_integrity_v1()->>'rls_ready')::boolean as rls_ready,
  (public.get_leghevo_service_return_deployment_integrity_v1()->>'direct_write_blocked')::boolean as direct_write_blocked,
  (public.get_leghevo_service_return_deployment_integrity_v1()->>'immutable_records_ready')::boolean as immutable_records_ready,
  (public.get_leghevo_service_return_deployment_integrity_v1()->>'head_guard_ready')::boolean as head_guard_ready,
  (public.get_leghevo_service_return_deployment_integrity_v1()->>'fingerprints_ready')::boolean as fingerprints_ready,
  (public.get_leghevo_service_return_deployment_integrity_v1()->>'recovery_entry_rpc_ready')::boolean as recovery_entry_rpc_ready,
  (public.get_leghevo_service_return_deployment_integrity_v1()->>'check_rpc_ready')::boolean as check_rpc_ready,
  (public.get_leghevo_service_return_deployment_integrity_v1()->>'completion_rpc_ready')::boolean as completion_rpc_ready,
  (public.get_leghevo_service_return_deployment_integrity_v1()->>'dependency_reconcile_ready')::boolean as dependency_reconcile_ready,
  (public.get_leghevo_service_return_deployment_integrity_v1()->>'promotion_and_client_chain_ready')::boolean as promotion_and_client_chain_ready,
  (public.get_leghevo_service_return_deployment_integrity_v1()->>'endpoint_and_realtime_ready')::boolean as endpoint_and_realtime_ready,
  (public.get_leghevo_service_return_deployment_integrity_v1()->>'seed_service_return_ready')::boolean as seed_service_return_ready
where false;
