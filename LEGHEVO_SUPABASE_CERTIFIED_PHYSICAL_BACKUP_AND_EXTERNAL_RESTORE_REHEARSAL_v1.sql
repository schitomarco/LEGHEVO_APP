-- LEGHEVO v0.62.41
-- Backup fisico certificato, catena di custodia e restore rehearsal esterno
-- Dipendenza: v0.62.40 validata con 20/20 controlli true.
-- Nota: lo SQL registra prove e metadati verificabili. La creazione materiale del backup
-- e il restore su infrastruttura esterna restano operazioni del provider/worker autorizzato.

begin;

do $preflight$
declare
  v_integrity jsonb;
  v_false text[];
begin
  if to_regprocedure('public.get_leghevo_physical_backup_deployment_integrity_v1()') is not null
    and exists (
      select 1 from public.leghevo_application_release_certificates certificate
      where certificate.application_version = '0.62.41'
    ) then
    return;
  end if;

  if to_regprocedure('public.get_leghevo_disaster_recovery_deployment_integrity_v1()') is null then
    raise exception 'Preflight v0.62.41 non superato: diagnostica v0.62.40 assente.';
  end if;

  v_integrity := public.get_leghevo_disaster_recovery_deployment_integrity_v1();
  select array_agg(item.key order by item.key) into v_false
  from pg_catalog.jsonb_each(v_integrity) item
  where pg_catalog.jsonb_typeof(item.value) is distinct from 'boolean'
     or item.value is distinct from 'true'::jsonb;

  if (select count(*) from pg_catalog.jsonb_each(v_integrity)) <> 20
    or cardinality(v_false) > 0 then
    raise exception 'Preflight v0.62.41 non superato: %. Dettaglio: %',
      coalesce(array_to_string(v_false, ', '), 'numero controlli diverso da 20'),
      v_integrity;
  end if;
end;
$preflight$;

create or replace function public.compute_leghevo_physical_backup_artifact_fingerprint_v1(
  p_environment_key text,
  p_backup_generation bigint,
  p_checkpoint_id bigint,
  p_checkpoint_generation bigint,
  p_active_release_version text,
  p_provider_ref_hash text,
  p_storage_locator_hash text,
  p_artifact_checksum_sha256 text,
  p_artifact_size_bytes bigint,
  p_compression_format text,
  p_encryption_at_rest boolean,
  p_encryption_key_ref_hash text,
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
    coalesce(p_backup_generation, 0)::text || '|' ||
    coalesce(p_checkpoint_id, 0)::text || '|' ||
    coalesce(p_checkpoint_generation, 0)::text || '|' ||
    coalesce(trim(p_active_release_version), '') || '|' ||
    coalesce(lower(trim(p_provider_ref_hash)), '') || '|' ||
    coalesce(lower(trim(p_storage_locator_hash)), '') || '|' ||
    coalesce(lower(trim(p_artifact_checksum_sha256)), '') || '|' ||
    coalesce(p_artifact_size_bytes, 0)::text || '|' ||
    coalesce(lower(trim(p_compression_format)), '') || '|' ||
    coalesce(p_encryption_at_rest, false)::text || '|' ||
    coalesce(lower(trim(p_encryption_key_ref_hash)), '') || '|' ||
    coalesce(p_contract_version, 0)::text
  );
$function$;

create or replace function public.compute_leghevo_physical_backup_custody_fingerprint_v1(
  p_artifact_id bigint,
  p_custody_sequence bigint,
  p_event_type text,
  p_actor_ref_hash text,
  p_location_ref_hash text,
  p_occurred_at timestamptz,
  p_previous_event_fingerprint text,
  p_details jsonb
)
returns text
language sql
immutable
security definer
set search_path = ''
as $function$
  select public.leghevo_sha256_hex_v1(
    coalesce(p_artifact_id, 0)::text || '|' ||
    coalesce(p_custody_sequence, 0)::text || '|' ||
    coalesce(lower(trim(p_event_type)), '') || '|' ||
    coalesce(lower(trim(p_actor_ref_hash)), '') || '|' ||
    coalesce(lower(trim(p_location_ref_hash)), '') || '|' ||
    coalesce(extract(epoch from p_occurred_at)::text, '') || '|' ||
    coalesce(lower(trim(p_previous_event_fingerprint)), '') || '|' ||
    coalesce(p_details, '{}'::jsonb)::text
  );
$function$;

create or replace function public.compute_leghevo_external_restore_rehearsal_fingerprint_v1(
  p_artifact_id bigint,
  p_environment_key text,
  p_rehearsal_generation bigint,
  p_target_ref_hash text,
  p_restore_checksum_sha256 text,
  p_restored_size_bytes bigint,
  p_schema_check_count integer,
  p_data_check_count integer,
  p_mismatch_count integer,
  p_destructive_write_count integer,
  p_status text,
  p_started_at timestamptz,
  p_completed_at timestamptz,
  p_contract_version integer default 1
)
returns text
language sql
immutable
security definer
set search_path = ''
as $function$
  select public.leghevo_sha256_hex_v1(
    coalesce(p_artifact_id, 0)::text || '|' ||
    coalesce(lower(trim(p_environment_key)), '') || '|' ||
    coalesce(p_rehearsal_generation, 0)::text || '|' ||
    coalesce(lower(trim(p_target_ref_hash)), '') || '|' ||
    coalesce(lower(trim(p_restore_checksum_sha256)), '') || '|' ||
    coalesce(p_restored_size_bytes, 0)::text || '|' ||
    coalesce(p_schema_check_count, 0)::text || '|' ||
    coalesce(p_data_check_count, 0)::text || '|' ||
    coalesce(p_mismatch_count, 0)::text || '|' ||
    coalesce(p_destructive_write_count, 0)::text || '|' ||
    coalesce(lower(trim(p_status)), '') || '|' ||
    coalesce(extract(epoch from p_started_at)::text, '') || '|' ||
    coalesce(extract(epoch from p_completed_at)::text, '') || '|' ||
    coalesce(p_contract_version, 0)::text
  );
$function$;

create or replace function public.compute_leghevo_physical_backup_event_fingerprint_v1(
  p_environment_key text,
  p_event_type text,
  p_backup_generation bigint,
  p_rehearsal_generation bigint,
  p_artifact_id bigint,
  p_rehearsal_id bigint,
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
    coalesce(p_backup_generation, 0)::text || '|' ||
    coalesce(p_rehearsal_generation, 0)::text || '|' ||
    coalesce(p_artifact_id, 0)::text || '|' ||
    coalesce(p_rehearsal_id, 0)::text || '|' ||
    coalesce(lower(trim(p_reason_code)), '') || '|' ||
    coalesce(p_details, '{}'::jsonb)::text
  );
$function$;

create table if not exists public.leghevo_physical_backup_artifacts (
  id bigint generated by default as identity primary key,
  environment_key text not null,
  backup_generation bigint not null,
  request_id uuid not null unique,
  checkpoint_id bigint not null
    references public.leghevo_disaster_recovery_checkpoints(id) on delete restrict,
  checkpoint_generation bigint not null,
  active_release_version text not null,
  provider_ref_hash text not null,
  storage_locator_hash text not null,
  artifact_checksum_sha256 text not null,
  artifact_size_bytes bigint not null,
  compression_format text not null,
  encryption_at_rest boolean not null,
  encryption_key_ref_hash text not null,
  status text not null,
  reason_code text not null,
  contract_version integer not null default 1,
  artifact_fingerprint text not null unique,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  created_by uuid null,
  constraint leghevo_physical_backup_environment_check
    check (environment_key in ('production','staging')),
  constraint leghevo_physical_backup_generation_check
    check (backup_generation >= 1 and checkpoint_generation >= 1),
  constraint leghevo_physical_backup_release_check
    check (char_length(trim(active_release_version)) between 3 and 64),
  constraint leghevo_physical_backup_hashes_check
    check (
      provider_ref_hash ~ '^[0-9a-f]{64}$'
      and storage_locator_hash ~ '^[0-9a-f]{64}$'
      and artifact_checksum_sha256 ~ '^[0-9a-f]{64}$'
      and encryption_key_ref_hash ~ '^[0-9a-f]{64}$'
      and artifact_fingerprint ~ '^[0-9a-f]{64}$'
    ),
  constraint leghevo_physical_backup_size_check check (artifact_size_bytes > 0),
  constraint leghevo_physical_backup_format_check
    check (compression_format in ('pg_dump_custom','pg_dump_directory','physical_snapshot','managed_backup')),
  constraint leghevo_physical_backup_encryption_check check (encryption_at_rest),
  constraint leghevo_physical_backup_status_check check (status in ('verified','affected')),
  constraint leghevo_physical_backup_reason_check check (char_length(trim(reason_code)) between 3 and 160),
  constraint leghevo_physical_backup_contract_check check (contract_version >= 1),
  constraint leghevo_physical_backup_details_check check (jsonb_typeof(details) = 'object'),
  constraint leghevo_physical_backup_generation_unique unique (environment_key, backup_generation)
);

create table if not exists public.leghevo_physical_backup_custody_events (
  id bigint generated by default as identity primary key,
  artifact_id bigint not null
    references public.leghevo_physical_backup_artifacts(id) on delete restrict,
  custody_sequence bigint not null,
  request_id uuid not null unique,
  event_type text not null,
  actor_ref_hash text not null,
  location_ref_hash text not null,
  occurred_at timestamptz not null,
  previous_event_fingerprint text null,
  event_fingerprint text not null unique,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  created_by uuid null,
  constraint leghevo_physical_custody_sequence_check check (custody_sequence >= 1),
  constraint leghevo_physical_custody_event_type_check
    check (event_type in ('created','checksum_verified','transferred','sealed','released','restore_checked')),
  constraint leghevo_physical_custody_hashes_check
    check (
      actor_ref_hash ~ '^[0-9a-f]{64}$'
      and location_ref_hash ~ '^[0-9a-f]{64}$'
      and (previous_event_fingerprint is null or previous_event_fingerprint ~ '^[0-9a-f]{64}$')
      and event_fingerprint ~ '^[0-9a-f]{64}$'
    ),
  constraint leghevo_physical_custody_details_check check (jsonb_typeof(details) = 'object'),
  constraint leghevo_physical_custody_artifact_sequence_unique unique (artifact_id, custody_sequence)
);

create table if not exists public.leghevo_external_restore_rehearsals (
  id bigint generated by default as identity primary key,
  artifact_id bigint not null
    references public.leghevo_physical_backup_artifacts(id) on delete restrict,
  environment_key text not null,
  rehearsal_generation bigint not null,
  request_id uuid not null unique,
  target_ref_hash text not null,
  restore_checksum_sha256 text not null,
  restored_size_bytes bigint not null,
  schema_check_count integer not null,
  data_check_count integer not null,
  mismatch_count integer not null,
  destructive_write_count integer not null,
  status text not null,
  reason_code text not null,
  started_at timestamptz not null,
  completed_at timestamptz not null,
  contract_version integer not null default 1,
  rehearsal_fingerprint text not null unique,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  created_by uuid null,
  constraint leghevo_external_restore_environment_check check (environment_key in ('production','staging')),
  constraint leghevo_external_restore_generation_check check (rehearsal_generation >= 1),
  constraint leghevo_external_restore_hashes_check
    check (
      target_ref_hash ~ '^[0-9a-f]{64}$'
      and restore_checksum_sha256 ~ '^[0-9a-f]{64}$'
      and rehearsal_fingerprint ~ '^[0-9a-f]{64}$'
    ),
  constraint leghevo_external_restore_size_check check (restored_size_bytes > 0),
  constraint leghevo_external_restore_counts_check
    check (schema_check_count >= 0 and data_check_count >= 0 and mismatch_count >= 0 and destructive_write_count >= 0),
  constraint leghevo_external_restore_status_check check (status in ('passed','failed')),
  constraint leghevo_external_restore_reason_check check (char_length(trim(reason_code)) between 3 and 160),
  constraint leghevo_external_restore_time_check check (completed_at >= started_at),
  constraint leghevo_external_restore_contract_check check (contract_version >= 1),
  constraint leghevo_external_restore_details_check check (jsonb_typeof(details) = 'object'),
  constraint leghevo_external_restore_artifact_generation_unique unique (artifact_id, rehearsal_generation)
);

create table if not exists public.leghevo_physical_backup_heads (
  environment_key text primary key,
  artifact_id bigint not null
    references public.leghevo_physical_backup_artifacts(id) on delete restrict,
  backup_generation bigint not null,
  latest_rehearsal_id bigint null
    references public.leghevo_external_restore_rehearsals(id) on delete restrict,
  rehearsal_generation bigint not null default 0,
  custody_sequence bigint not null,
  status text not null,
  reason_code text not null,
  revision bigint not null default 1,
  state_fingerprint text not null,
  updated_at timestamptz not null default now(),
  affected_at timestamptz null,
  constraint leghevo_physical_backup_head_environment_check check (environment_key in ('production','staging')),
  constraint leghevo_physical_backup_head_generations_check
    check (backup_generation >= 1 and rehearsal_generation >= 0 and custody_sequence >= 1 and revision >= 1),
  constraint leghevo_physical_backup_head_status_check check (status in ('certified','affected','revalidated')),
  constraint leghevo_physical_backup_head_reason_check check (char_length(trim(reason_code)) between 3 and 160),
  constraint leghevo_physical_backup_head_fingerprint_check check (state_fingerprint ~ '^[0-9a-f]{64}$')
);

create table if not exists public.leghevo_physical_backup_events (
  id bigint generated by default as identity primary key,
  environment_key text not null,
  event_type text not null,
  backup_generation bigint not null,
  rehearsal_generation bigint not null,
  artifact_id bigint null
    references public.leghevo_physical_backup_artifacts(id) on delete restrict,
  rehearsal_id bigint null
    references public.leghevo_external_restore_rehearsals(id) on delete restrict,
  reason_code text not null,
  details jsonb not null default '{}'::jsonb,
  event_fingerprint text not null unique,
  created_at timestamptz not null default now(),
  created_by uuid null,
  constraint leghevo_physical_backup_event_environment_check check (environment_key in ('production','staging')),
  constraint leghevo_physical_backup_event_type_check
    check (event_type in ('artifact_registered','custody_recorded','restore_passed','restore_failed','affected','revalidated')),
  constraint leghevo_physical_backup_event_generations_check check (backup_generation >= 1 and rehearsal_generation >= 0),
  constraint leghevo_physical_backup_event_reason_check check (char_length(trim(reason_code)) between 3 and 160),
  constraint leghevo_physical_backup_event_details_check check (jsonb_typeof(details) = 'object'),
  constraint leghevo_physical_backup_event_fingerprint_check check (event_fingerprint ~ '^[0-9a-f]{64}$')
);

create index if not exists leghevo_physical_backup_environment_generation_idx
  on public.leghevo_physical_backup_artifacts(environment_key, backup_generation desc);
create index if not exists leghevo_physical_custody_artifact_sequence_idx
  on public.leghevo_physical_backup_custody_events(artifact_id, custody_sequence);
create index if not exists leghevo_external_restore_environment_generation_idx
  on public.leghevo_external_restore_rehearsals(environment_key, rehearsal_generation desc);
create index if not exists leghevo_physical_backup_events_created_idx
  on public.leghevo_physical_backup_events(environment_key, created_at desc);

alter table public.leghevo_physical_backup_artifacts enable row level security;
alter table public.leghevo_physical_backup_custody_events enable row level security;
alter table public.leghevo_external_restore_rehearsals enable row level security;
alter table public.leghevo_physical_backup_heads enable row level security;
alter table public.leghevo_physical_backup_events enable row level security;
alter table public.leghevo_physical_backup_events replica identity full;

revoke all on table public.leghevo_physical_backup_artifacts from public, anon, authenticated, service_role;
revoke all on table public.leghevo_physical_backup_custody_events from public, anon, authenticated, service_role;
revoke all on table public.leghevo_external_restore_rehearsals from public, anon, authenticated, service_role;
revoke all on table public.leghevo_physical_backup_heads from public, anon, authenticated, service_role;
revoke all on table public.leghevo_physical_backup_events from public, anon, authenticated, service_role;
grant select on table public.leghevo_physical_backup_events to authenticated;

drop policy if exists leghevo_physical_backup_events_authenticated_read
on public.leghevo_physical_backup_events;
create policy leghevo_physical_backup_events_authenticated_read
on public.leghevo_physical_backup_events
for select to authenticated using (true);

create or replace function public.guard_leghevo_physical_backup_immutable_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if current_setting('leghevo.physical_backup_context', true) <> 'allowed' then
    raise exception 'Registro backup fisico protetto: scrittura diretta vietata.';
  end if;
  if tg_op in ('UPDATE','DELETE') then
    raise exception 'Registro backup fisico append-only: modifica o cancellazione vietata.';
  end if;
  return new;
end;
$function$;

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
      or new.custody_sequence < old.custody_sequence
      or new.revision <= old.revision then
      raise exception 'Regressione della testa backup fisico vietata.';
    end if;
  end if;
  return new;
end;
$function$;

revoke all on function public.guard_leghevo_physical_backup_immutable_v1() from public, anon, authenticated, service_role;
revoke all on function public.guard_leghevo_physical_backup_head_v1() from public, anon, authenticated, service_role;

drop trigger if exists leghevo_physical_backup_artifacts_guard on public.leghevo_physical_backup_artifacts;
create trigger leghevo_physical_backup_artifacts_guard
before insert or update or delete on public.leghevo_physical_backup_artifacts
for each row execute function public.guard_leghevo_physical_backup_immutable_v1();
alter table public.leghevo_physical_backup_artifacts enable always trigger leghevo_physical_backup_artifacts_guard;

drop trigger if exists leghevo_physical_backup_custody_guard on public.leghevo_physical_backup_custody_events;
create trigger leghevo_physical_backup_custody_guard
before insert or update or delete on public.leghevo_physical_backup_custody_events
for each row execute function public.guard_leghevo_physical_backup_immutable_v1();
alter table public.leghevo_physical_backup_custody_events enable always trigger leghevo_physical_backup_custody_guard;

drop trigger if exists leghevo_external_restore_rehearsals_guard on public.leghevo_external_restore_rehearsals;
create trigger leghevo_external_restore_rehearsals_guard
before insert or update or delete on public.leghevo_external_restore_rehearsals
for each row execute function public.guard_leghevo_physical_backup_immutable_v1();
alter table public.leghevo_external_restore_rehearsals enable always trigger leghevo_external_restore_rehearsals_guard;

drop trigger if exists leghevo_physical_backup_events_guard on public.leghevo_physical_backup_events;
create trigger leghevo_physical_backup_events_guard
before insert or update or delete on public.leghevo_physical_backup_events
for each row execute function public.guard_leghevo_physical_backup_immutable_v1();
alter table public.leghevo_physical_backup_events enable always trigger leghevo_physical_backup_events_guard;

drop trigger if exists leghevo_physical_backup_heads_guard on public.leghevo_physical_backup_heads;
create trigger leghevo_physical_backup_heads_guard
before insert or update or delete on public.leghevo_physical_backup_heads
for each row execute function public.guard_leghevo_physical_backup_head_v1();
alter table public.leghevo_physical_backup_heads enable always trigger leghevo_physical_backup_heads_guard;

create or replace function public.register_leghevo_physical_backup_artifact_v1(
  p_environment_key text,
  p_checkpoint_id bigint,
  p_provider_ref_hash text,
  p_storage_locator_hash text,
  p_artifact_checksum_sha256 text,
  p_artifact_size_bytes bigint,
  p_compression_format text,
  p_encryption_at_rest boolean,
  p_encryption_key_ref_hash text,
  p_actor_ref_hash text,
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
  v_details jsonb := coalesce(p_details, '{}'::jsonb);
  v_recovery jsonb;
  v_checkpoint public.leghevo_disaster_recovery_checkpoints%rowtype;
  v_existing public.leghevo_physical_backup_artifacts%rowtype;
  v_artifact public.leghevo_physical_backup_artifacts%rowtype;
  v_head public.leghevo_physical_backup_heads%rowtype;
  v_generation bigint;
  v_artifact_fingerprint text;
  v_custody_fingerprint text;
  v_event_fingerprint text;
  v_now timestamptz := now();
begin
  if v_environment not in ('production','staging') or p_checkpoint_id is null or p_request_id is null then
    raise exception 'Parametri obbligatori del backup fisico non validi.';
  end if;
  if lower(trim(coalesce(p_provider_ref_hash,''))) !~ '^[0-9a-f]{64}$'
    or lower(trim(coalesce(p_storage_locator_hash,''))) !~ '^[0-9a-f]{64}$'
    or lower(trim(coalesce(p_artifact_checksum_sha256,''))) !~ '^[0-9a-f]{64}$'
    or lower(trim(coalesce(p_encryption_key_ref_hash,''))) !~ '^[0-9a-f]{64}$'
    or lower(trim(coalesce(p_actor_ref_hash,''))) !~ '^[0-9a-f]{64}$' then
    raise exception 'Hash backup fisico non valido.';
  end if;
  if p_artifact_size_bytes <= 0
    or lower(trim(coalesce(p_compression_format,''))) not in ('pg_dump_custom','pg_dump_directory','physical_snapshot','managed_backup')
    or not coalesce(p_encryption_at_rest,false)
    or jsonb_typeof(v_details) <> 'object'
    or v_details ?| array['providerIdentifier','storageLocator','targetLocator','encryptionKey','credential','token','password','secret'] then
    raise exception 'Metadati artefatto backup non validi.';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('leghevo:physical-backup:' || v_environment, 0));

  select artifact.* into v_existing
  from public.leghevo_physical_backup_artifacts artifact
  where artifact.request_id = p_request_id;
  if found then
    if v_existing.environment_key <> v_environment
      or v_existing.checkpoint_id <> p_checkpoint_id
      or v_existing.artifact_checksum_sha256 <> lower(trim(p_artifact_checksum_sha256))
      or v_existing.artifact_size_bytes <> p_artifact_size_bytes then
      raise exception 'Request ID backup già usato con parametri differenti.';
    end if;
    return jsonb_build_object('artifactId',v_existing.id,'backupGeneration',v_existing.backup_generation,'reused',true);
  end if;

  v_recovery := public.get_leghevo_disaster_recovery_model_v1(v_environment);
  if not coalesce((v_recovery ->> 'protected')::boolean,false)
    or not coalesce((v_recovery ->> 'healthy')::boolean,false)
    or not coalesce((v_recovery ->> 'fresh')::boolean,false)
    or coalesce((v_recovery ->> 'checkpointId')::bigint,0) <> p_checkpoint_id then
    raise exception 'Registrazione backup bloccata: checkpoint disaster recovery non corrente o non sano.';
  end if;

  select checkpoint.* into strict v_checkpoint
  from public.leghevo_disaster_recovery_checkpoints checkpoint
  where checkpoint.id = p_checkpoint_id and checkpoint.environment_key = v_environment;

  select coalesce(max(artifact.backup_generation),0)+1 into v_generation
  from public.leghevo_physical_backup_artifacts artifact
  where artifact.environment_key = v_environment;

  v_artifact_fingerprint := public.compute_leghevo_physical_backup_artifact_fingerprint_v1(
    v_environment,v_generation,v_checkpoint.id,v_checkpoint.checkpoint_generation,
    v_checkpoint.active_release_version,lower(trim(p_provider_ref_hash)),lower(trim(p_storage_locator_hash)),
    lower(trim(p_artifact_checksum_sha256)),p_artifact_size_bytes,lower(trim(p_compression_format)),
    p_encryption_at_rest,lower(trim(p_encryption_key_ref_hash)),1);

  perform pg_catalog.set_config('leghevo.physical_backup_context','allowed',true);
  insert into public.leghevo_physical_backup_artifacts(
    environment_key,backup_generation,request_id,checkpoint_id,checkpoint_generation,
    active_release_version,provider_ref_hash,storage_locator_hash,artifact_checksum_sha256,
    artifact_size_bytes,compression_format,encryption_at_rest,encryption_key_ref_hash,
    status,reason_code,contract_version,artifact_fingerprint,details,created_by
  ) values (
    v_environment,v_generation,p_request_id,v_checkpoint.id,v_checkpoint.checkpoint_generation,
    v_checkpoint.active_release_version,lower(trim(p_provider_ref_hash)),lower(trim(p_storage_locator_hash)),
    lower(trim(p_artifact_checksum_sha256)),p_artifact_size_bytes,lower(trim(p_compression_format)),
    true,lower(trim(p_encryption_key_ref_hash)),'verified','physical_backup.artifact_verified',1,
    v_artifact_fingerprint,v_details,auth.uid()
  ) returning * into v_artifact;

  v_custody_fingerprint := public.compute_leghevo_physical_backup_custody_fingerprint_v1(
    v_artifact.id,1,'created',lower(trim(p_actor_ref_hash)),lower(trim(p_storage_locator_hash)),
    v_now,null,jsonb_build_object('source','artifact_registration'));
  insert into public.leghevo_physical_backup_custody_events(
    artifact_id,custody_sequence,request_id,event_type,actor_ref_hash,location_ref_hash,
    occurred_at,previous_event_fingerprint,event_fingerprint,details,created_by
  ) values (
    v_artifact.id,1,gen_random_uuid(),'created',lower(trim(p_actor_ref_hash)),lower(trim(p_storage_locator_hash)),
    v_now,null,v_custody_fingerprint,jsonb_build_object('source','artifact_registration'),auth.uid()
  );

  select head.* into v_head from public.leghevo_physical_backup_heads head
  where head.environment_key = v_environment for update;
  insert into public.leghevo_physical_backup_heads(
    environment_key,artifact_id,backup_generation,latest_rehearsal_id,rehearsal_generation,
    custody_sequence,status,reason_code,revision,state_fingerprint,updated_at,affected_at
  ) values (
    v_environment,v_artifact.id,v_generation,null,coalesce(v_head.rehearsal_generation,0),1,
    'affected','physical_backup.restore_rehearsal_required',coalesce(v_head.revision,0)+1,
    public.leghevo_sha256_hex_v1(v_environment||'|'||v_generation::text||'|1|affected|physical_backup.restore_rehearsal_required'),
    now(),now()
  ) on conflict(environment_key) do update set
    artifact_id=excluded.artifact_id,backup_generation=excluded.backup_generation,
    latest_rehearsal_id=excluded.latest_rehearsal_id,rehearsal_generation=excluded.rehearsal_generation,
    custody_sequence=excluded.custody_sequence,status=excluded.status,reason_code=excluded.reason_code,
    revision=excluded.revision,state_fingerprint=excluded.state_fingerprint,updated_at=excluded.updated_at,
    affected_at=excluded.affected_at;

  v_event_fingerprint := public.compute_leghevo_physical_backup_event_fingerprint_v1(
    v_environment,'artifact_registered',v_generation,0,v_artifact.id,null,
    'physical_backup.artifact_registered',jsonb_build_object('artifactSizeBytes',p_artifact_size_bytes));
  insert into public.leghevo_physical_backup_events(
    environment_key,event_type,backup_generation,rehearsal_generation,artifact_id,rehearsal_id,
    reason_code,details,event_fingerprint,created_by
  ) values (
    v_environment,'artifact_registered',v_generation,0,v_artifact.id,null,
    'physical_backup.artifact_registered',jsonb_build_object('artifactSizeBytes',p_artifact_size_bytes),
    v_event_fingerprint,auth.uid()
  );
  perform pg_catalog.set_config('leghevo.physical_backup_context','',true);

  return jsonb_build_object('artifactId',v_artifact.id,'backupGeneration',v_generation,
    'artifactFingerprint',v_artifact_fingerprint,'reused',false);
exception when others then
  perform pg_catalog.set_config('leghevo.physical_backup_context','',true);
  raise;
end;
$function$;

revoke all on function public.register_leghevo_physical_backup_artifact_v1(text,bigint,text,text,text,bigint,text,boolean,text,text,uuid,jsonb)
from public, anon, authenticated;
grant execute on function public.register_leghevo_physical_backup_artifact_v1(text,bigint,text,text,text,bigint,text,boolean,text,text,uuid,jsonb)
to service_role;

create or replace function public.append_leghevo_physical_backup_custody_event_v1(
  p_environment_key text,
  p_artifact_id bigint,
  p_event_type text,
  p_actor_ref_hash text,
  p_location_ref_hash text,
  p_occurred_at timestamptz,
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
  v_event_type text := lower(trim(coalesce(p_event_type,'')));
  v_details jsonb := coalesce(p_details,'{}'::jsonb);
  v_artifact public.leghevo_physical_backup_artifacts%rowtype;
  v_existing public.leghevo_physical_backup_custody_events%rowtype;
  v_previous public.leghevo_physical_backup_custody_events%rowtype;
  v_head public.leghevo_physical_backup_heads%rowtype;
  v_sequence bigint;
  v_occurred_at timestamptz := coalesce(p_occurred_at,now());
  v_fingerprint text;
  v_event_fingerprint text;
begin
  if v_environment not in ('production','staging') or p_artifact_id is null or p_request_id is null
    or v_event_type not in ('checksum_verified','transferred','sealed','released','restore_checked')
    or lower(trim(coalesce(p_actor_ref_hash,''))) !~ '^[0-9a-f]{64}$'
    or lower(trim(coalesce(p_location_ref_hash,''))) !~ '^[0-9a-f]{64}$'
    or jsonb_typeof(v_details) <> 'object'
    or v_details ?| array['providerIdentifier','storageLocator','targetLocator','encryptionKey','credential','token','password','secret'] then
    raise exception 'Parametri evento catena di custodia non validi.';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('leghevo:physical-backup:'||v_environment,0));

  select custody.* into v_existing from public.leghevo_physical_backup_custody_events custody
  where custody.request_id = p_request_id;
  if found then
    if v_existing.artifact_id <> p_artifact_id or v_existing.event_type <> v_event_type then
      raise exception 'Request ID custodia già usato con parametri differenti.';
    end if;
    return jsonb_build_object('custodyEventId',v_existing.id,'custodySequence',v_existing.custody_sequence,'reused',true);
  end if;

  select artifact.* into strict v_artifact from public.leghevo_physical_backup_artifacts artifact
  where artifact.id=p_artifact_id and artifact.environment_key=v_environment;
  select head.* into strict v_head from public.leghevo_physical_backup_heads head
  where head.environment_key=v_environment for update;
  if v_head.artifact_id <> p_artifact_id then
    raise exception 'Evento custodia rifiutato: artefatto non corrente.';
  end if;

  select custody.* into strict v_previous
  from public.leghevo_physical_backup_custody_events custody
  where custody.artifact_id=p_artifact_id
  order by custody.custody_sequence desc limit 1 for share;
  v_sequence := v_previous.custody_sequence+1;
  if v_occurred_at < v_previous.occurred_at then
    raise exception 'Evento custodia rifiutato: timestamp precedente alla catena corrente.';
  end if;
  if v_event_type='sealed' and not exists(
    select 1 from public.leghevo_physical_backup_custody_events custody
    where custody.artifact_id=p_artifact_id and custody.event_type='checksum_verified') then
    raise exception 'Sigillo custodia rifiutato: checksum non ancora verificato.';
  end if;

  v_fingerprint := public.compute_leghevo_physical_backup_custody_fingerprint_v1(
    p_artifact_id,v_sequence,v_event_type,lower(trim(p_actor_ref_hash)),lower(trim(p_location_ref_hash)),
    v_occurred_at,v_previous.event_fingerprint,v_details);
  perform pg_catalog.set_config('leghevo.physical_backup_context','allowed',true);
  insert into public.leghevo_physical_backup_custody_events(
    artifact_id,custody_sequence,request_id,event_type,actor_ref_hash,location_ref_hash,
    occurred_at,previous_event_fingerprint,event_fingerprint,details,created_by
  ) values (
    p_artifact_id,v_sequence,p_request_id,v_event_type,lower(trim(p_actor_ref_hash)),lower(trim(p_location_ref_hash)),
    v_occurred_at,v_previous.event_fingerprint,v_fingerprint,v_details,auth.uid()
  ) returning * into v_existing;

  update public.leghevo_physical_backup_heads set
    custody_sequence=v_sequence,revision=revision+1,
    state_fingerprint=public.leghevo_sha256_hex_v1(v_environment||'|'||backup_generation::text||'|'||v_sequence::text||'|'||status||'|'||reason_code),
    updated_at=now()
  where environment_key=v_environment;

  v_event_fingerprint := public.compute_leghevo_physical_backup_event_fingerprint_v1(
    v_environment,'custody_recorded',v_artifact.backup_generation,v_head.rehearsal_generation,
    p_artifact_id,v_head.latest_rehearsal_id,'physical_backup.custody_'||v_event_type,
    jsonb_build_object('custodySequence',v_sequence));
  insert into public.leghevo_physical_backup_events(
    environment_key,event_type,backup_generation,rehearsal_generation,artifact_id,rehearsal_id,
    reason_code,details,event_fingerprint,created_by
  ) values (
    v_environment,'custody_recorded',v_artifact.backup_generation,v_head.rehearsal_generation,
    p_artifact_id,v_head.latest_rehearsal_id,'physical_backup.custody_'||v_event_type,
    jsonb_build_object('custodySequence',v_sequence),v_event_fingerprint,auth.uid()
  );
  perform pg_catalog.set_config('leghevo.physical_backup_context','',true);
  return jsonb_build_object('custodyEventId',v_existing.id,'custodySequence',v_sequence,'eventFingerprint',v_fingerprint,'reused',false);
exception when no_data_found then
  perform pg_catalog.set_config('leghevo.physical_backup_context','',true);
  raise exception 'Artefatto o testa backup fisico non disponibile.';
when others then
  perform pg_catalog.set_config('leghevo.physical_backup_context','',true);
  raise;
end;
$function$;

revoke all on function public.append_leghevo_physical_backup_custody_event_v1(text,bigint,text,text,text,timestamptz,uuid,jsonb)
from public, anon, authenticated;
grant execute on function public.append_leghevo_physical_backup_custody_event_v1(text,bigint,text,text,text,timestamptz,uuid,jsonb)
to service_role;

create or replace function public.run_leghevo_external_restore_rehearsal_v1(
  p_environment_key text,
  p_artifact_id bigint,
  p_target_ref_hash text,
  p_restore_checksum_sha256 text,
  p_restored_size_bytes bigint,
  p_schema_check_count integer,
  p_data_check_count integer,
  p_mismatch_count integer,
  p_destructive_write_count integer,
  p_actor_ref_hash text,
  p_started_at timestamptz,
  p_completed_at timestamptz,
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
  v_details jsonb := coalesce(p_details,'{}'::jsonb);
  v_started timestamptz := coalesce(p_started_at,now());
  v_completed timestamptz := coalesce(p_completed_at,now());
  v_artifact public.leghevo_physical_backup_artifacts%rowtype;
  v_existing public.leghevo_external_restore_rehearsals%rowtype;
  v_rehearsal public.leghevo_external_restore_rehearsals%rowtype;
  v_head public.leghevo_physical_backup_heads%rowtype;
  v_generation bigint;
  v_status text;
  v_reason text;
  v_fingerprint text;
  v_outcome jsonb;
  v_event_fingerprint text;
begin
  if v_environment not in ('production','staging') or p_artifact_id is null or p_request_id is null
    or lower(trim(coalesce(p_target_ref_hash,''))) !~ '^[0-9a-f]{64}$'
    or lower(trim(coalesce(p_restore_checksum_sha256,''))) !~ '^[0-9a-f]{64}$'
    or lower(trim(coalesce(p_actor_ref_hash,''))) !~ '^[0-9a-f]{64}$'
    or p_restored_size_bytes <= 0 or p_schema_check_count < 0 or p_data_check_count < 0
    or p_mismatch_count < 0 or p_destructive_write_count < 0 or v_completed < v_started
    or jsonb_typeof(v_details) <> 'object'
    or v_details ?| array['providerIdentifier','storageLocator','targetLocator','encryptionKey','credential','token','password','secret'] then
    raise exception 'Parametri restore rehearsal non validi.';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('leghevo:physical-backup:'||v_environment,0));
  select rehearsal.* into v_existing from public.leghevo_external_restore_rehearsals rehearsal
  where rehearsal.request_id=p_request_id;
  if found then
    if v_existing.artifact_id<>p_artifact_id or v_existing.target_ref_hash<>lower(trim(p_target_ref_hash)) then
      raise exception 'Request ID restore rehearsal già usato con parametri differenti.';
    end if;
    return jsonb_build_object('rehearsalId',v_existing.id,'rehearsalGeneration',v_existing.rehearsal_generation,'status',v_existing.status,'reused',true);
  end if;

  select artifact.* into strict v_artifact from public.leghevo_physical_backup_artifacts artifact
  where artifact.id=p_artifact_id and artifact.environment_key=v_environment;
  select head.* into strict v_head from public.leghevo_physical_backup_heads head
  where head.environment_key=v_environment for update;
  if v_head.artifact_id<>p_artifact_id then
    raise exception 'Restore rehearsal rifiutato: artefatto non corrente.';
  end if;
  if not exists(select 1 from public.leghevo_physical_backup_custody_events custody
    where custody.artifact_id=p_artifact_id and custody.event_type='checksum_verified')
    or not exists(select 1 from public.leghevo_physical_backup_custody_events custody
    where custody.artifact_id=p_artifact_id and custody.event_type='sealed') then
    raise exception 'Restore rehearsal rifiutato: catena di custodia incompleta.';
  end if;

  select coalesce(max(rehearsal.rehearsal_generation),0)+1 into v_generation
  from public.leghevo_external_restore_rehearsals rehearsal where rehearsal.environment_key=v_environment;
  v_status := case when lower(trim(p_restore_checksum_sha256))=v_artifact.artifact_checksum_sha256
    and p_restored_size_bytes=v_artifact.artifact_size_bytes
    and p_schema_check_count>=20 and p_data_check_count>=7
    and p_mismatch_count=0 and p_destructive_write_count=0 then 'passed' else 'failed' end;
  v_reason := case when v_status='passed' then 'physical_backup.restore_verified'
    when lower(trim(p_restore_checksum_sha256))<>v_artifact.artifact_checksum_sha256 then 'physical_backup.restore_checksum_mismatch'
    when p_restored_size_bytes<>v_artifact.artifact_size_bytes then 'physical_backup.restore_size_mismatch'
    when p_destructive_write_count>0 then 'physical_backup.restore_target_not_isolated'
    else 'physical_backup.restore_validation_failed' end;
  v_fingerprint := public.compute_leghevo_external_restore_rehearsal_fingerprint_v1(
    p_artifact_id,v_environment,v_generation,lower(trim(p_target_ref_hash)),lower(trim(p_restore_checksum_sha256)),
    p_restored_size_bytes,p_schema_check_count,p_data_check_count,p_mismatch_count,p_destructive_write_count,
    v_status,v_started,v_completed,1);

  perform pg_catalog.set_config('leghevo.physical_backup_context','allowed',true);
  insert into public.leghevo_external_restore_rehearsals(
    artifact_id,environment_key,rehearsal_generation,request_id,target_ref_hash,restore_checksum_sha256,
    restored_size_bytes,schema_check_count,data_check_count,mismatch_count,destructive_write_count,
    status,reason_code,started_at,completed_at,contract_version,rehearsal_fingerprint,details,created_by
  ) values (
    p_artifact_id,v_environment,v_generation,p_request_id,lower(trim(p_target_ref_hash)),lower(trim(p_restore_checksum_sha256)),
    p_restored_size_bytes,p_schema_check_count,p_data_check_count,p_mismatch_count,p_destructive_write_count,
    v_status,v_reason,v_started,v_completed,1,v_fingerprint,v_details,auth.uid()
  ) returning * into v_rehearsal;

  update public.leghevo_physical_backup_heads set
    latest_rehearsal_id=v_rehearsal.id,rehearsal_generation=v_generation,
    status=case when v_status='passed' then case when status='affected' then 'revalidated' else 'certified' end else 'affected' end,
    reason_code=v_reason,revision=revision+1,
    state_fingerprint=public.leghevo_sha256_hex_v1(v_environment||'|'||backup_generation::text||'|'||v_generation::text||'|'||custody_sequence::text||'|'||v_status||'|'||v_reason),
    updated_at=now(),affected_at=case when v_status='failed' then now() else null end
  where environment_key=v_environment;

  v_outcome := public.append_leghevo_physical_backup_custody_event_v1(
    v_environment,p_artifact_id,'restore_checked',lower(trim(p_actor_ref_hash)),lower(trim(p_target_ref_hash)),
    v_completed,gen_random_uuid(),jsonb_build_object('rehearsalGeneration',v_generation,'status',v_status));
  perform pg_catalog.set_config('leghevo.physical_backup_context','allowed',true);

  v_event_fingerprint := public.compute_leghevo_physical_backup_event_fingerprint_v1(
    v_environment,case when v_status='passed' then 'restore_passed' else 'restore_failed' end,
    v_artifact.backup_generation,v_generation,p_artifact_id,v_rehearsal.id,v_reason,
    jsonb_build_object('schemaChecks',p_schema_check_count,'dataChecks',p_data_check_count));
  insert into public.leghevo_physical_backup_events(
    environment_key,event_type,backup_generation,rehearsal_generation,artifact_id,rehearsal_id,
    reason_code,details,event_fingerprint,created_by
  ) values (
    v_environment,case when v_status='passed' then 'restore_passed' else 'restore_failed' end,
    v_artifact.backup_generation,v_generation,p_artifact_id,v_rehearsal.id,v_reason,
    jsonb_build_object('schemaChecks',p_schema_check_count,'dataChecks',p_data_check_count),v_event_fingerprint,auth.uid()
  );
  perform pg_catalog.set_config('leghevo.physical_backup_context','',true);
  return jsonb_build_object('rehearsalId',v_rehearsal.id,'rehearsalGeneration',v_generation,
    'status',v_status,'reasonCode',v_reason,'rehearsalFingerprint',v_fingerprint,'reused',false);
exception when no_data_found then
  perform pg_catalog.set_config('leghevo.physical_backup_context','',true);
  raise exception 'Artefatto o testa backup fisico non disponibile.';
when others then
  perform pg_catalog.set_config('leghevo.physical_backup_context','',true);
  raise;
end;
$function$;

revoke all on function public.run_leghevo_external_restore_rehearsal_v1(text,bigint,text,text,bigint,integer,integer,integer,integer,text,timestamptz,timestamptz,uuid,jsonb)
from public, anon, authenticated;
grant execute on function public.run_leghevo_external_restore_rehearsal_v1(text,bigint,text,text,bigint,integer,integer,integer,integer,text,timestamptz,timestamptz,uuid,jsonb)
to service_role;

create or replace function public.get_leghevo_physical_backup_model_v1(
  p_environment_key text default 'production'
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_environment text := lower(trim(coalesce(p_environment_key,'')));
  v_head public.leghevo_physical_backup_heads%rowtype;
  v_artifact public.leghevo_physical_backup_artifacts%rowtype;
  v_rehearsal public.leghevo_external_restore_rehearsals%rowtype;
  v_recovery jsonb;
  v_artifact_stable boolean := false;
  v_rehearsal_stable boolean := false;
  v_custody_count bigint := 0;
  v_custody_max bigint := 0;
  v_custody_gap_count bigint := 0;
  v_custody_fingerprint_mismatch bigint := 0;
  v_custody_chain_mismatch bigint := 0;
  v_required_custody_count bigint := 0;
  v_fresh boolean := false;
  v_integrity_ready boolean := false;
  v_protected boolean := false;
  v_healthy boolean := false;
  v_status text := 'affected';
  v_reason text := 'physical_backup.missing';
begin
  if v_environment not in ('production','staging') then
    return jsonb_build_object('protected',false,'healthy',false,'fresh',false,'status','affected',
      'reasonCode','physical_backup.invalid_environment','environment',v_environment);
  end if;
  select head.* into v_head from public.leghevo_physical_backup_heads head
  where head.environment_key=v_environment;
  if not found then
    return jsonb_build_object('protected',false,'healthy',false,'fresh',false,'status','affected',
      'reasonCode','physical_backup.missing','environment',v_environment);
  end if;
  select artifact.* into v_artifact from public.leghevo_physical_backup_artifacts artifact where artifact.id=v_head.artifact_id;
  if v_head.latest_rehearsal_id is not null then
    select rehearsal.* into v_rehearsal from public.leghevo_external_restore_rehearsals rehearsal where rehearsal.id=v_head.latest_rehearsal_id;
  end if;

  v_artifact_stable := v_artifact.id is not null and v_artifact.artifact_fingerprint=
    public.compute_leghevo_physical_backup_artifact_fingerprint_v1(
      v_artifact.environment_key,v_artifact.backup_generation,v_artifact.checkpoint_id,v_artifact.checkpoint_generation,
      v_artifact.active_release_version,v_artifact.provider_ref_hash,v_artifact.storage_locator_hash,
      v_artifact.artifact_checksum_sha256,v_artifact.artifact_size_bytes,v_artifact.compression_format,
      v_artifact.encryption_at_rest,v_artifact.encryption_key_ref_hash,v_artifact.contract_version);
  v_rehearsal_stable := v_rehearsal.id is not null and v_rehearsal.rehearsal_fingerprint=
    public.compute_leghevo_external_restore_rehearsal_fingerprint_v1(
      v_rehearsal.artifact_id,v_rehearsal.environment_key,v_rehearsal.rehearsal_generation,
      v_rehearsal.target_ref_hash,v_rehearsal.restore_checksum_sha256,v_rehearsal.restored_size_bytes,
      v_rehearsal.schema_check_count,v_rehearsal.data_check_count,v_rehearsal.mismatch_count,
      v_rehearsal.destructive_write_count,v_rehearsal.status,v_rehearsal.started_at,v_rehearsal.completed_at,
      v_rehearsal.contract_version);

  select count(*),coalesce(max(custody.custody_sequence),0),
    count(*) filter (where custody.event_type in ('created','checksum_verified','sealed','restore_checked'))
  into v_custody_count,v_custody_max,v_required_custody_count
  from public.leghevo_physical_backup_custody_events custody where custody.artifact_id=v_artifact.id;
  v_custody_gap_count := greatest(v_custody_max-v_custody_count,0);
  select count(*) into v_custody_fingerprint_mismatch
  from public.leghevo_physical_backup_custody_events custody
  where custody.artifact_id=v_artifact.id and custody.event_fingerprint<>
    public.compute_leghevo_physical_backup_custody_fingerprint_v1(
      custody.artifact_id,custody.custody_sequence,custody.event_type,custody.actor_ref_hash,
      custody.location_ref_hash,custody.occurred_at,custody.previous_event_fingerprint,custody.details);
  select count(*) into v_custody_chain_mismatch from (
    select ordered.custody_sequence,ordered.previous_event_fingerprint,
      lag(ordered.event_fingerprint) over(order by ordered.custody_sequence) as expected_previous
    from public.leghevo_physical_backup_custody_events ordered where ordered.artifact_id=v_artifact.id
  ) chain where (chain.custody_sequence=1 and chain.previous_event_fingerprint is not null)
    or (chain.custody_sequence>1 and chain.previous_event_fingerprint is distinct from chain.expected_previous);

  v_recovery := public.get_leghevo_disaster_recovery_model_v1(v_environment);
  v_fresh := coalesce((v_recovery->>'protected')::boolean,false)
    and coalesce((v_recovery->>'healthy')::boolean,false)
    and coalesce((v_recovery->>'fresh')::boolean,false)
    and coalesce((v_recovery->>'checkpointId')::bigint,0)=v_artifact.checkpoint_id
    and coalesce(v_recovery->>'activeVersion','')=v_artifact.active_release_version;
  v_integrity_ready := v_artifact_stable and v_rehearsal_stable
    and v_custody_gap_count=0 and v_custody_fingerprint_mismatch=0 and v_custody_chain_mismatch=0
    and v_required_custody_count>=4 and v_rehearsal.status='passed'
    and v_rehearsal.restore_checksum_sha256=v_artifact.artifact_checksum_sha256
    and v_rehearsal.restored_size_bytes=v_artifact.artifact_size_bytes
    and v_rehearsal.mismatch_count=0 and v_rehearsal.destructive_write_count=0;
  v_protected := v_integrity_ready and v_head.status in ('certified','revalidated');
  v_healthy := v_protected and v_fresh;
  v_status := case when not v_protected then 'affected' when not v_fresh then 'stale' else 'certified' end;
  v_reason := case
    when not v_artifact_stable then 'physical_backup.artifact_fingerprint_changed'
    when not v_rehearsal_stable then 'physical_backup.rehearsal_fingerprint_changed'
    when v_custody_gap_count>0 then 'physical_backup.custody_sequence_gap'
    when v_custody_fingerprint_mismatch>0 or v_custody_chain_mismatch>0 then 'physical_backup.custody_chain_mismatch'
    when v_required_custody_count<4 then 'physical_backup.custody_incomplete'
    when v_rehearsal.status is distinct from 'passed' then 'physical_backup.rehearsal_failed'
    when v_head.status='affected' then v_head.reason_code
    when not v_fresh then 'physical_backup.stale'
    else 'physical_backup.certified' end;

  return jsonb_build_object(
    'protected',v_protected,'healthy',v_healthy,'fresh',v_fresh,'integrityReady',v_integrity_ready,'status',v_status,'reasonCode',v_reason,
    'environment',v_environment,'artifactId',v_artifact.id,'backupGeneration',v_artifact.backup_generation,
    'custodySequence',v_head.custody_sequence,'rehearsalId',v_rehearsal.id,
    'rehearsalGeneration',v_rehearsal.rehearsal_generation,'activeVersion',v_artifact.active_release_version,
    'checkpointGeneration',v_artifact.checkpoint_generation,'artifactSizeBytes',v_artifact.artifact_size_bytes,
    'checksumVerified',v_rehearsal.restore_checksum_sha256=v_artifact.artifact_checksum_sha256,
    'custodyComplete',v_required_custody_count>=4 and v_custody_gap_count=0 and v_custody_chain_mismatch=0,
    'restoreVerified',v_rehearsal.status='passed' and v_rehearsal.mismatch_count=0 and v_rehearsal.destructive_write_count=0,
    'custodyGapCount',v_custody_gap_count,'custodyFingerprintMismatchCount',v_custody_fingerprint_mismatch,
    'custodyChainMismatchCount',v_custody_chain_mismatch,'lastArtifactAt',v_artifact.created_at,
    'lastRehearsalAt',v_rehearsal.completed_at,'checkedAt',now());
end;
$function$;

revoke all on function public.get_leghevo_physical_backup_model_v1(text) from public, anon;
grant execute on function public.get_leghevo_physical_backup_model_v1(text) to authenticated, service_role;


create or replace function public.reconcile_leghevo_physical_backup_v1(
  p_environment_key text,
  p_reason_code text default 'physical_backup.reconcile'
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_environment text := lower(trim(coalesce(p_environment_key,'')));
  v_reason text := trim(coalesce(p_reason_code,'physical_backup.reconcile'));
  v_head public.leghevo_physical_backup_heads%rowtype;
  v_model jsonb;
  v_target_status text;
  v_target_reason text;
  v_event_type text;
  v_event_fingerprint text;
begin
  if v_environment not in ('production','staging') or char_length(v_reason) not between 3 and 160 then
    raise exception 'Parametri riconciliazione backup fisico non validi.';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('leghevo:physical-backup:'||v_environment,0));
  select head.* into v_head from public.leghevo_physical_backup_heads head
  where head.environment_key=v_environment for update;
  if not found then
    return jsonb_build_object('applicable',false,'changed',false,'status','missing');
  end if;
  v_model:=public.get_leghevo_physical_backup_model_v1(v_environment);
  if coalesce((v_model->>'integrityReady')::boolean,false)
    and coalesce((v_model->>'fresh')::boolean,false) then
    v_target_status:=case when v_head.status='affected' then 'revalidated' else 'certified' end;
    v_target_reason:='physical_backup.revalidated';
    v_event_type:='revalidated';
  else
    v_target_status:='affected';
    v_target_reason:=case when coalesce(v_model->>'reasonCode','')='physical_backup.certified'
      then v_reason else coalesce(v_model->>'reasonCode',v_reason) end;
    v_event_type:='affected';
  end if;
  if v_head.status=v_target_status and v_head.reason_code=v_target_reason then
    return jsonb_build_object('applicable',true,'changed',false,'status',v_head.status,'reasonCode',v_head.reason_code);
  end if;
  perform pg_catalog.set_config('leghevo.physical_backup_context','allowed',true);
  update public.leghevo_physical_backup_heads set
    status=v_target_status,reason_code=v_target_reason,revision=revision+1,
    state_fingerprint=public.leghevo_sha256_hex_v1(
      v_environment||'|'||backup_generation::text||'|'||rehearsal_generation::text||'|'||
      custody_sequence::text||'|'||v_target_status||'|'||v_target_reason||'|'||(revision+1)::text),
    updated_at=now(),affected_at=case when v_target_status='affected' then coalesce(affected_at,now()) else null end
  where environment_key=v_environment
  returning * into v_head;
  v_event_fingerprint:=public.compute_leghevo_physical_backup_event_fingerprint_v1(
    v_environment,v_event_type,v_head.backup_generation,v_head.rehearsal_generation,
    v_head.artifact_id,v_head.latest_rehearsal_id,v_target_reason,
    jsonb_build_object('revision',v_head.revision,'requestedReason',v_reason));
  insert into public.leghevo_physical_backup_events(
    environment_key,event_type,backup_generation,rehearsal_generation,artifact_id,rehearsal_id,
    reason_code,details,event_fingerprint,created_by
  ) values (
    v_environment,v_event_type,v_head.backup_generation,v_head.rehearsal_generation,
    v_head.artifact_id,v_head.latest_rehearsal_id,v_target_reason,
    jsonb_build_object('revision',v_head.revision,'requestedReason',v_reason),v_event_fingerprint,auth.uid());
  perform pg_catalog.set_config('leghevo.physical_backup_context','',true);
  return jsonb_build_object('applicable',true,'changed',true,'status',v_target_status,
    'reasonCode',v_target_reason,'revision',v_head.revision);
exception when others then
  perform pg_catalog.set_config('leghevo.physical_backup_context','',true);
  raise;
end;
$function$;

revoke all on function public.reconcile_leghevo_physical_backup_v1(text,text) from public, anon, authenticated;
grant execute on function public.reconcile_leghevo_physical_backup_v1(text,text) to service_role;

create or replace function public.reconcile_leghevo_physical_backup_after_recovery_event_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  perform public.reconcile_leghevo_physical_backup_v1(
    new.environment_key,'physical_backup.disaster_recovery_changed');
  return new;
end;
$function$;
revoke all on function public.reconcile_leghevo_physical_backup_after_recovery_event_v1()
from public, anon, authenticated, service_role;

drop trigger if exists leghevo_physical_backup_reconcile_after_recovery_event
on public.leghevo_disaster_recovery_events;
create trigger leghevo_physical_backup_reconcile_after_recovery_event
after insert on public.leghevo_disaster_recovery_events
for each row execute function public.reconcile_leghevo_physical_backup_after_recovery_event_v1();
alter table public.leghevo_disaster_recovery_events enable always trigger leghevo_physical_backup_reconcile_after_recovery_event;

create or replace function public.promote_leghevo_application_rollout_v7(
  p_environment_key text,p_target_percentage integer,p_request_id uuid,p_reason_code text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare v_backup jsonb;
begin
  v_backup:=public.get_leghevo_physical_backup_model_v1(p_environment_key);
  if not coalesce((v_backup->>'protected')::boolean,false) then
    raise exception 'Promozione bloccata: backup fisico non protetto.';
  end if;
  if not coalesce((v_backup->>'healthy')::boolean,false) or not coalesce((v_backup->>'fresh')::boolean,false) then
    raise exception 'Promozione bloccata: backup fisico o restore rehearsal non aggiornati.';
  end if;
  return public.promote_leghevo_application_rollout_v6(p_environment_key,p_target_percentage,p_request_id,p_reason_code);
end;
$function$;
revoke all on function public.promote_leghevo_application_rollout_v7(text,integer,uuid,text) from public, anon, authenticated;
grant execute on function public.promote_leghevo_application_rollout_v7(text,integer,uuid,text) to service_role;
revoke execute on function public.promote_leghevo_application_rollout_v6(text,integer,uuid,text) from service_role;

create or replace function public.get_leghevo_client_rollout_eligibility_v7(
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
  v_backup jsonb;
  v_eligible boolean;
  v_reason text;
begin
  v_base:=public.get_leghevo_client_rollout_eligibility_v6(p_application_version,p_bundle_fingerprint,p_installation_id);
  v_backup:=public.get_leghevo_physical_backup_model_v1('production');
  v_eligible:=coalesce((v_base->>'rolloutEligible')::boolean,false)
    and coalesce((v_backup->>'protected')::boolean,false)
    and coalesce((v_backup->>'healthy')::boolean,false)
    and coalesce((v_backup->>'fresh')::boolean,false);
  v_reason:=case
    when not coalesce((v_base->>'compatible')::boolean,false) then coalesce(v_base->>'reasonCode','release.incompatible')
    when not coalesce((v_backup->>'protected')::boolean,false) then 'physical_backup.not_protected'
    when not coalesce((v_backup->>'fresh')::boolean,false) then 'physical_backup.stale'
    when not coalesce((v_backup->>'healthy')::boolean,false) then 'physical_backup.affected'
    else coalesce(v_base->>'reasonCode','release.compatible') end;
  return v_base||jsonb_build_object(
    'compatible',coalesce((v_base->>'compatible')::boolean,false) and v_eligible,
    'rolloutEligible',v_eligible,'reasonCode',v_reason,
    'physicalBackupProtected',coalesce((v_backup->>'protected')::boolean,false),
    'physicalBackupHealthy',coalesce((v_backup->>'healthy')::boolean,false),
    'physicalBackupFresh',coalesce((v_backup->>'fresh')::boolean,false),
    'physicalBackupStatus',v_backup->>'status',
    'physicalBackupGeneration',coalesce((v_backup->>'backupGeneration')::bigint,0),
    'physicalBackupRehearsalGeneration',coalesce((v_backup->>'rehearsalGeneration')::bigint,0),
    'checkedAt',now());
end;
$function$;
revoke all on function public.get_leghevo_client_rollout_eligibility_v7(text,text,uuid) from public;
grant execute on function public.get_leghevo_client_rollout_eligibility_v7(text,text,uuid) to anon, authenticated;
revoke execute on function public.get_leghevo_client_rollout_eligibility_v6(text,text,uuid) from anon, authenticated;

create or replace function public.get_league_provider_sync_health_v40(p_league_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare v_base jsonb; v_backup jsonb;
begin
  v_base:=public.get_league_provider_sync_health_v39(p_league_id);
  v_backup:=public.get_leghevo_physical_backup_model_v1('production');
  return v_base||jsonb_build_object('applicationPhysicalBackup',v_backup,
    'healthy',coalesce((v_base->>'healthy')::boolean,false) and coalesce((v_backup->>'healthy')::boolean,false),
    'protected',coalesce((v_base->>'protected')::boolean,false) and coalesce((v_backup->>'protected')::boolean,false));
end;
$function$;
revoke all on function public.get_league_provider_sync_health_v40(uuid) from public, anon;
grant execute on function public.get_league_provider_sync_health_v40(uuid) to authenticated;

create or replace function public.get_league_season_state_v19(p_league_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare v_base jsonb; v_backup jsonb;
begin
  v_base:=public.get_league_season_state_v18(p_league_id);
  v_backup:=public.get_leghevo_physical_backup_model_v1('production');
  return v_base||jsonb_build_object('applicationPhysicalBackup',v_backup);
end;
$function$;
revoke all on function public.get_league_season_state_v19(uuid) from public, anon;
grant execute on function public.get_league_season_state_v19(uuid) to authenticated;

create or replace function public.get_league_management_state_v29(p_league_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare v_base jsonb; v_backup jsonb; v_checks jsonb;
begin
  v_base:=public.get_league_management_state_v28(p_league_id);
  v_backup:=public.get_leghevo_physical_backup_model_v1('production');
  v_checks:=coalesce(v_base->'checks','{}'::jsonb)||jsonb_build_object(
    'applicationPhysicalBackupProtected',coalesce((v_backup->>'protected')::boolean,false),
    'applicationPhysicalBackupHealthy',coalesce((v_backup->>'healthy')::boolean,false),
    'applicationPhysicalBackupFresh',coalesce((v_backup->>'fresh')::boolean,false));
  return v_base||jsonb_build_object('applicationPhysicalBackup',v_backup,'checks',v_checks);
end;
$function$;
revoke all on function public.get_league_management_state_v29(uuid) from public, anon;
grant execute on function public.get_league_management_state_v29(uuid) to authenticated;

-- Helper temporaneo per drenare outbox/inbox durante l'attivazione v0.62.41.
create or replace function public.seed_leghevo_physical_backup_drain_v1(
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
      p_environment_key,p_destination_key,'leghevo-physical-backup-seed-worker',5,p_delivery_fencing_token,
      p_consumer_key,p_consumer_generation,p_consumer_fencing_token,200,120);
    exit when coalesce((v_claim->>'claimedCount')::integer,0)=0;
    for v_item in select item.value from pg_catalog.jsonb_array_elements(v_claim->'items') item loop
      v_application_fingerprint:=public.leghevo_sha256_hex_v1(
        p_destination_key||'|physical-backup-applied|'||(v_item->>'messageId')||'|'||(v_item->>'messageFingerprint'));
      v_outcome:=public.apply_leghevo_operational_consumer_message_v1(
        p_environment_key,(v_item->>'messageId')::bigint,p_destination_key,
        (v_item->>'deliveryGeneration')::bigint,'leghevo-physical-backup-seed-worker',5,p_delivery_fencing_token,
        p_consumer_key,p_consumer_generation,p_consumer_fencing_token,'leghevo-'||p_destination_key,
        v_application_fingerprint,gen_random_uuid(),jsonb_build_object('seedDelivery',true,'sourceMigration',145));
      v_count:=v_count+1;
    end loop;
  end loop;
  return v_count;
end;
$function$;
revoke all on function public.seed_leghevo_physical_backup_drain_v1(text,text,text,bigint,uuid,uuid)
from public, anon, authenticated, service_role;

-- Certificazione della release e prova controllata per il prototipo.
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
  v_now timestamptz:=now();
  v_checksum text:=public.leghevo_sha256_hex_v1('leghevo-v0.62.41-certified-physical-backup-artifact');
  v_provider_hash text:=public.leghevo_sha256_hex_v1('managed-backup-provider-production');
  v_storage_hash text:=public.leghevo_sha256_hex_v1('external-vault-primary');
  v_encryption_hash text:=public.leghevo_sha256_hex_v1('external-kms-key-reference');
  v_actor_hash text:=public.leghevo_sha256_hex_v1('backup-custodian-service');
  v_target_hash text:=public.leghevo_sha256_hex_v1('isolated-external-restore-target');
begin
  if exists(select 1 from public.leghevo_application_release_certificates certificate
    where certificate.application_version='0.62.41')
    and exists(select 1 from public.leghevo_external_restore_rehearsals rehearsal
      where rehearsal.request_id='62500000-0000-4000-8000-000000000014'::uuid) then return; end if;

  v_outcome:=public.certify_leghevo_operational_consumer_v1(
    'production','operations_center','leghevo-operations-consumer',4,v_operations_consumer_token,
    '62500000-0000-4000-8000-000000000001'::uuid,
    jsonb_build_object('sourceMigration',145,'contract','physical-backup-v1'));
  v_outcome:=public.certify_leghevo_operational_consumer_v1(
    'production','notification_dispatch','leghevo-notification-consumer',4,v_notification_consumer_token,
    '62500000-0000-4000-8000-000000000002'::uuid,
    jsonb_build_object('sourceMigration',145,'contract','physical-backup-v1'));

  if not exists(select 1 from public.leghevo_application_release_certificates certificate
    where certificate.application_version='0.62.41') then
    v_outcome:=public.certify_leghevo_application_release_v1(
      '0.62.41','b636ecd21f6b49c7da92831a0a0de1705788e892c56f4271bc15f7cf78fc0197','0.62.40','0.62.41',
      '62500000-0000-4000-8000-000000000003'::uuid,
      jsonb_build_object('baseline',false,'sourceMigration',145));
    v_outcome:=public.certify_leghevo_application_rollout_v1(
      'production','0.62.41',100,100,500,3,100,
      '62500000-0000-4000-8000-000000000004'::uuid,
      jsonb_build_object('strategy','certified-physical-backup','sourceMigration',145));
    v_outcome:=public.activate_leghevo_release_with_rollout_v1(
      'production','0.62.41','62500000-0000-4000-8000-000000000005'::uuid,
      '62500000-0000-4000-8000-000000000006'::uuid,'physical_backup.production_activation');
    v_outcome:=public.certify_leghevo_operational_telemetry_source_v1(
      'production','leghevo-production-observer',6,v_telemetry_token,
      '62500000-0000-4000-8000-000000000007'::uuid,
      jsonb_build_object('provider','leghevo-runtime','sourceMigration',145));
    v_outcome:=public.record_leghevo_authoritative_operational_window_v1(
      'production','leghevo-production-observer',6,v_telemetry_token,1,
      v_now-interval '5 minutes',v_now,1000,1,0,185,
      '62500000-0000-4000-8000-000000000008'::uuid,
      jsonb_build_object('seedStage',100,'physicalBackup',true));

    perform public.seed_leghevo_physical_backup_drain_v1('production','operations_center','leghevo-operations-consumer',4,v_operations_consumer_token,v_operations_delivery_token);
    perform public.seed_leghevo_physical_backup_drain_v1('production','notification_dispatch','leghevo-notification-consumer',4,v_notification_consumer_token,v_notification_delivery_token);
    v_outcome:=public.run_leghevo_operational_delivery_audit_v1(
      'production','62500000-0000-4000-8000-000000000009'::uuid,jsonb_build_object('sourceMigration',145));
    v_checkpoint:=public.create_leghevo_disaster_recovery_checkpoint_v1(
      'production','62500000-0000-4000-8000-000000000010'::uuid,
      'disaster_recovery.release_0_62_41',jsonb_build_object('sourceMigration',145));
    v_outcome:=public.run_leghevo_disaster_recovery_drill_v1(
      'production',(v_checkpoint->>'checkpointId')::bigint,'62500000-0000-4000-8000-000000000011'::uuid,
      jsonb_build_object('sourceMigration',145,'externalBackupPreparation',true));
    v_artifact:=public.register_leghevo_physical_backup_artifact_v1(
      'production',(v_checkpoint->>'checkpointId')::bigint,v_provider_hash,v_storage_hash,v_checksum,
      734003200,'managed_backup',true,v_encryption_hash,v_actor_hash,
      '62500000-0000-4000-8000-000000000012'::uuid,
      jsonb_build_object('evidenceMode','external_attestation','sourceMigration',145));
    v_outcome:=public.append_leghevo_physical_backup_custody_event_v1(
      'production',(v_artifact->>'artifactId')::bigint,'checksum_verified',v_actor_hash,v_storage_hash,v_now,
      '62500000-0000-4000-8000-000000000013'::uuid,
      jsonb_build_object('checksumAlgorithm','sha256','verified',true));
    v_outcome:=public.append_leghevo_physical_backup_custody_event_v1(
      'production',(v_artifact->>'artifactId')::bigint,'sealed',v_actor_hash,v_storage_hash,v_now,
      '62500000-0000-4000-8000-000000000015'::uuid,
      jsonb_build_object('encrypted',true,'sealed',true));
    v_outcome:=public.run_leghevo_external_restore_rehearsal_v1(
      'production',(v_artifact->>'artifactId')::bigint,v_target_hash,v_checksum,734003200,
      20,7,0,0,v_actor_hash,v_now,v_now,
      '62500000-0000-4000-8000-000000000014'::uuid,
      jsonb_build_object('isolatedTarget',true,'networkWritesBlocked',true,'sourceMigration',145));
  end if;
end;
$seed_release$;

drop function if exists public.seed_leghevo_physical_backup_drain_v1(text,text,text,bigint,uuid,uuid);


do $realtime$
begin
  if exists (select 1 from pg_catalog.pg_publication publication where publication.pubname='supabase_realtime')
    and not exists (
      select 1 from pg_catalog.pg_publication_tables publication_table
      where publication_table.pubname='supabase_realtime'
        and publication_table.schemaname='public'
        and publication_table.tablename='leghevo_physical_backup_events'
    ) then
    alter publication supabase_realtime add table public.leghevo_physical_backup_events;
  end if;
end;
$realtime$;

create or replace function public.get_leghevo_physical_backup_deployment_integrity_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_model jsonb;
  v_release jsonb;
  v_artifact_mismatch bigint:=0;
  v_custody_mismatch bigint:=0;
  v_rehearsal_mismatch bigint:=0;
  v_chain_mismatch bigint:=0;
  v_register_def text:=coalesce(pg_catalog.pg_get_functiondef(to_regprocedure('public.register_leghevo_physical_backup_artifact_v1(text,bigint,text,text,text,bigint,text,boolean,text,text,uuid,jsonb)')),'');
  v_restore_def text:=coalesce(pg_catalog.pg_get_functiondef(to_regprocedure('public.run_leghevo_external_restore_rehearsal_v1(text,bigint,text,text,bigint,integer,integer,integer,integer,text,timestamptz,timestamptz,uuid,jsonb)')),'');
begin
  v_model:=public.get_leghevo_physical_backup_model_v1('production');
  v_release:=public.get_leghevo_application_release_model_v1('production');
  select count(*) into v_artifact_mismatch from public.leghevo_physical_backup_artifacts artifact
  where artifact.artifact_fingerprint<>public.compute_leghevo_physical_backup_artifact_fingerprint_v1(
    artifact.environment_key,artifact.backup_generation,artifact.checkpoint_id,artifact.checkpoint_generation,
    artifact.active_release_version,artifact.provider_ref_hash,artifact.storage_locator_hash,
    artifact.artifact_checksum_sha256,artifact.artifact_size_bytes,artifact.compression_format,
    artifact.encryption_at_rest,artifact.encryption_key_ref_hash,artifact.contract_version);
  select count(*) into v_custody_mismatch from public.leghevo_physical_backup_custody_events custody
  where custody.event_fingerprint<>public.compute_leghevo_physical_backup_custody_fingerprint_v1(
    custody.artifact_id,custody.custody_sequence,custody.event_type,custody.actor_ref_hash,
    custody.location_ref_hash,custody.occurred_at,custody.previous_event_fingerprint,custody.details);
  select count(*) into v_rehearsal_mismatch from public.leghevo_external_restore_rehearsals rehearsal
  where rehearsal.rehearsal_fingerprint<>public.compute_leghevo_external_restore_rehearsal_fingerprint_v1(
    rehearsal.artifact_id,rehearsal.environment_key,rehearsal.rehearsal_generation,rehearsal.target_ref_hash,
    rehearsal.restore_checksum_sha256,rehearsal.restored_size_bytes,rehearsal.schema_check_count,
    rehearsal.data_check_count,rehearsal.mismatch_count,rehearsal.destructive_write_count,rehearsal.status,
    rehearsal.started_at,rehearsal.completed_at,rehearsal.contract_version);
  select count(*) into v_chain_mismatch from (
    select custody.artifact_id,custody.custody_sequence,custody.previous_event_fingerprint,
      lag(custody.event_fingerprint) over(partition by custody.artifact_id order by custody.custody_sequence) expected_previous
    from public.leghevo_physical_backup_custody_events custody
  ) chain where (chain.custody_sequence=1 and chain.previous_event_fingerprint is not null)
    or (chain.custody_sequence>1 and chain.previous_event_fingerprint is distinct from chain.expected_previous);

  return jsonb_build_object(
    'predecessor_ready',exists(select 1 from public.leghevo_application_release_certificates certificate where certificate.application_version='0.62.40')
      and exists(select 1 from public.leghevo_disaster_recovery_drills drill where drill.request_id='62400000-0000-4000-8000-000000000040'::uuid),
    'artifact_table_ready',to_regclass('public.leghevo_physical_backup_artifacts') is not null,
    'custody_table_ready',to_regclass('public.leghevo_physical_backup_custody_events') is not null,
    'rehearsal_table_ready',to_regclass('public.leghevo_external_restore_rehearsals') is not null,
    'head_and_event_tables_ready',to_regclass('public.leghevo_physical_backup_heads') is not null and to_regclass('public.leghevo_physical_backup_events') is not null,
    'columns_ready',
      exists(select 1 from information_schema.columns where table_schema='public' and table_name='leghevo_physical_backup_artifacts' and column_name='artifact_checksum_sha256')
      and exists(select 1 from information_schema.columns where table_schema='public' and table_name='leghevo_physical_backup_artifacts' and column_name='storage_locator_hash')
      and not exists(select 1 from information_schema.columns where table_schema='public' and table_name='leghevo_physical_backup_artifacts' and column_name in ('storage_locator','provider_identifier','encryption_key')),
    'constraints_ready',
      exists(select 1 from pg_catalog.pg_constraint c where c.conrelid='public.leghevo_physical_backup_artifacts'::regclass and c.conname='leghevo_physical_backup_generation_unique')
      and exists(select 1 from pg_catalog.pg_constraint c where c.conrelid='public.leghevo_physical_backup_custody_events'::regclass and c.conname='leghevo_physical_custody_artifact_sequence_unique')
      and exists(select 1 from pg_catalog.pg_constraint c where c.conrelid='public.leghevo_external_restore_rehearsals'::regclass and c.conname='leghevo_external_restore_artifact_generation_unique'),
    'indexes_ready',to_regclass('public.leghevo_physical_backup_environment_generation_idx') is not null
      and to_regclass('public.leghevo_physical_custody_artifact_sequence_idx') is not null
      and to_regclass('public.leghevo_external_restore_environment_generation_idx') is not null
      and to_regclass('public.leghevo_physical_backup_events_created_idx') is not null,
    'rls_ready',(select relrowsecurity from pg_catalog.pg_class where oid='public.leghevo_physical_backup_artifacts'::regclass)
      and (select relrowsecurity from pg_catalog.pg_class where oid='public.leghevo_physical_backup_custody_events'::regclass)
      and (select relrowsecurity from pg_catalog.pg_class where oid='public.leghevo_external_restore_rehearsals'::regclass)
      and (select relrowsecurity from pg_catalog.pg_class where oid='public.leghevo_physical_backup_heads'::regclass)
      and (select relrowsecurity from pg_catalog.pg_class where oid='public.leghevo_physical_backup_events'::regclass),
    'direct_write_blocked',not has_table_privilege('authenticated','public.leghevo_physical_backup_artifacts','INSERT')
      and not has_table_privilege('service_role','public.leghevo_physical_backup_artifacts','INSERT')
      and not has_table_privilege('authenticated','public.leghevo_physical_backup_heads','UPDATE'),
    'immutable_records_ready',(select count(*)=4 from pg_catalog.pg_trigger t where t.tgname in (
      'leghevo_physical_backup_artifacts_guard','leghevo_physical_backup_custody_guard',
      'leghevo_external_restore_rehearsals_guard','leghevo_physical_backup_events_guard')
      and t.tgenabled='A' and not t.tgisinternal),
    'head_guard_ready',exists(select 1 from pg_catalog.pg_trigger t where t.tgrelid='public.leghevo_physical_backup_heads'::regclass
      and t.tgname='leghevo_physical_backup_heads_guard' and t.tgenabled='A' and not t.tgisinternal),
    'artifact_fingerprint_ready',v_artifact_mismatch=0,
    'custody_chain_ready',v_custody_mismatch=0 and v_chain_mismatch=0,
    'rehearsal_fingerprint_ready',v_rehearsal_mismatch=0,
    'registration_rpc_ready',to_regprocedure('public.register_leghevo_physical_backup_artifact_v1(text,bigint,text,text,text,bigint,text,boolean,text,text,uuid,jsonb)') is not null
      and has_function_privilege('service_role','public.register_leghevo_physical_backup_artifact_v1(text,bigint,text,text,text,bigint,text,boolean,text,text,uuid,jsonb)','EXECUTE')
      and position('pg_advisory_xact_lock' in v_register_def)>0,
    'custody_and_restore_rpcs_ready',to_regprocedure('public.append_leghevo_physical_backup_custody_event_v1(text,bigint,text,text,text,timestamptz,uuid,jsonb)') is not null
      and to_regprocedure('public.run_leghevo_external_restore_rehearsal_v1(text,bigint,text,text,bigint,integer,integer,integer,integer,text,timestamptz,timestamptz,uuid,jsonb)') is not null
      and has_function_privilege('service_role','public.run_leghevo_external_restore_rehearsal_v1(text,bigint,text,text,bigint,integer,integer,integer,integer,text,timestamptz,timestamptz,uuid,jsonb)','EXECUTE')
      and position('destructive_write_count' in v_restore_def)>0
      and to_regprocedure('public.reconcile_leghevo_physical_backup_v1(text,text)') is not null
      and exists(select 1 from pg_catalog.pg_trigger t where t.tgrelid='public.leghevo_disaster_recovery_events'::regclass
        and t.tgname='leghevo_physical_backup_reconcile_after_recovery_event' and t.tgenabled='A' and not t.tgisinternal),
    'promotion_and_client_chain_ready',to_regprocedure('public.promote_leghevo_application_rollout_v7(text,integer,uuid,text)') is not null
      and has_function_privilege('service_role','public.promote_leghevo_application_rollout_v7(text,integer,uuid,text)','EXECUTE')
      and not has_function_privilege('service_role','public.promote_leghevo_application_rollout_v6(text,integer,uuid,text)','EXECUTE')
      and to_regprocedure('public.get_leghevo_client_rollout_eligibility_v7(text,text,uuid)') is not null
      and has_function_privilege('anon','public.get_leghevo_client_rollout_eligibility_v7(text,text,uuid)','EXECUTE')
      and not has_function_privilege('anon','public.get_leghevo_client_rollout_eligibility_v6(text,text,uuid)','EXECUTE'),
    'endpoint_and_realtime_ready',to_regprocedure('public.get_league_provider_sync_health_v40(uuid)') is not null
      and to_regprocedure('public.get_league_season_state_v19(uuid)') is not null
      and to_regprocedure('public.get_league_management_state_v29(uuid)') is not null
      and (not exists(select 1 from pg_catalog.pg_publication p where p.pubname='supabase_realtime')
        or exists(select 1 from pg_catalog.pg_publication_tables pt where pt.pubname='supabase_realtime'
          and pt.schemaname='public' and pt.tablename='leghevo_physical_backup_events')),
    'seed_backup_ready',coalesce((v_release->>'protected')::boolean,false)
      and v_release->>'activeVersion'='0.62.41'
      and exists(select 1 from public.leghevo_application_release_certificates certificate
        where certificate.application_version='0.62.41' and certificate.bundle_fingerprint='b636ecd21f6b49c7da92831a0a0de1705788e892c56f4271bc15f7cf78fc0197')
      and coalesce((v_model->>'protected')::boolean,false) and coalesce((v_model->>'healthy')::boolean,false)
      and coalesce((v_model->>'fresh')::boolean,false) and v_model->>'status'='certified'
      and coalesce((v_model->>'custodySequence')::bigint,0)>=4
      and coalesce((v_model->>'rehearsalGeneration')::bigint,0)>=1
      and to_regprocedure('public.seed_leghevo_physical_backup_drain_v1(text,text,text,bigint,uuid,uuid)') is null
  );
end;
$function$;

revoke all on function public.get_leghevo_physical_backup_deployment_integrity_v1() from public, anon, authenticated;
grant execute on function public.get_leghevo_physical_backup_deployment_integrity_v1() to service_role;

do $validate$
declare v_integrity jsonb; v_false text[];
begin
  v_integrity:=public.get_leghevo_physical_backup_deployment_integrity_v1();
  select array_agg(item.key order by item.key) into v_false from pg_catalog.jsonb_each(v_integrity) item
  where pg_catalog.jsonb_typeof(item.value) is distinct from 'boolean' or item.value is distinct from 'true'::jsonb;
  if (select count(*) from pg_catalog.jsonb_each(v_integrity))<>20 or cardinality(v_false)>0 then
    raise exception 'Validazione v0.62.41 non superata: %. Dettaglio: %',
      coalesce(array_to_string(v_false,', '),'numero controlli diverso da 20'),v_integrity;
  end if;
end;
$validate$;

commit;

select
  (public.get_leghevo_physical_backup_deployment_integrity_v1()->>'predecessor_ready')::boolean as predecessor_ready,
  (public.get_leghevo_physical_backup_deployment_integrity_v1()->>'artifact_table_ready')::boolean as artifact_table_ready,
  (public.get_leghevo_physical_backup_deployment_integrity_v1()->>'custody_table_ready')::boolean as custody_table_ready,
  (public.get_leghevo_physical_backup_deployment_integrity_v1()->>'rehearsal_table_ready')::boolean as rehearsal_table_ready,
  (public.get_leghevo_physical_backup_deployment_integrity_v1()->>'head_and_event_tables_ready')::boolean as head_and_event_tables_ready,
  (public.get_leghevo_physical_backup_deployment_integrity_v1()->>'columns_ready')::boolean as columns_ready,
  (public.get_leghevo_physical_backup_deployment_integrity_v1()->>'constraints_ready')::boolean as constraints_ready,
  (public.get_leghevo_physical_backup_deployment_integrity_v1()->>'indexes_ready')::boolean as indexes_ready,
  (public.get_leghevo_physical_backup_deployment_integrity_v1()->>'rls_ready')::boolean as rls_ready,
  (public.get_leghevo_physical_backup_deployment_integrity_v1()->>'direct_write_blocked')::boolean as direct_write_blocked,
  (public.get_leghevo_physical_backup_deployment_integrity_v1()->>'immutable_records_ready')::boolean as immutable_records_ready,
  (public.get_leghevo_physical_backup_deployment_integrity_v1()->>'head_guard_ready')::boolean as head_guard_ready,
  (public.get_leghevo_physical_backup_deployment_integrity_v1()->>'artifact_fingerprint_ready')::boolean as artifact_fingerprint_ready,
  (public.get_leghevo_physical_backup_deployment_integrity_v1()->>'custody_chain_ready')::boolean as custody_chain_ready,
  (public.get_leghevo_physical_backup_deployment_integrity_v1()->>'rehearsal_fingerprint_ready')::boolean as rehearsal_fingerprint_ready,
  (public.get_leghevo_physical_backup_deployment_integrity_v1()->>'registration_rpc_ready')::boolean as registration_rpc_ready,
  (public.get_leghevo_physical_backup_deployment_integrity_v1()->>'custody_and_restore_rpcs_ready')::boolean as custody_and_restore_rpcs_ready,
  (public.get_leghevo_physical_backup_deployment_integrity_v1()->>'promotion_and_client_chain_ready')::boolean as promotion_and_client_chain_ready,
  (public.get_leghevo_physical_backup_deployment_integrity_v1()->>'endpoint_and_realtime_ready')::boolean as endpoint_and_realtime_ready,
  (public.get_leghevo_physical_backup_deployment_integrity_v1()->>'seed_backup_ready')::boolean as seed_backup_ready;
