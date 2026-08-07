-- LEGHEVO v0.62.44
-- Lega il contratto applicativo al lockfile npm e certifica una nuova release
-- senza modificare i certificati immutabili della v0.62.43.

begin;

set local statement_timeout = '30min';

create table if not exists public.leghevo_model_recertification_events (
  id bigint generated always as identity primary key,
  model_key text not null,
  model_version integer not null,
  application_version text not null,
  previous_schema_fingerprint text not null,
  current_schema_fingerprint text not null,
  reason_code text not null,
  source_migration integer not null,
  readiness jsonb not null,
  recertified_at timestamptz not null default now(),
  constraint leghevo_model_recertification_previous_fingerprint_check
    check (previous_schema_fingerprint ~ '^[0-9a-f]{32}$'),
  constraint leghevo_model_recertification_current_fingerprint_check
    check (current_schema_fingerprint ~ '^[0-9a-f]{32}$'),
  constraint leghevo_model_recertification_change_check
    check (previous_schema_fingerprint <> current_schema_fingerprint),
  constraint leghevo_model_recertification_source_check
    check (source_migration > 0),
  unique (model_key, model_version, current_schema_fingerprint)
);

alter table public.leghevo_model_recertification_events enable row level security;
revoke all on table public.leghevo_model_recertification_events
  from public, anon, authenticated, service_role;

create or replace function public.guard_leghevo_model_recertification_event_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  raise exception 'Evento di ricertificazione immutabile.';
end;
$function$;

revoke all on function public.guard_leghevo_model_recertification_event_v1()
  from public, anon, authenticated, service_role;

drop trigger if exists leghevo_model_recertification_events_immutable
on public.leghevo_model_recertification_events;
create trigger leghevo_model_recertification_events_immutable
before update or delete on public.leghevo_model_recertification_events
for each row execute function public.guard_leghevo_model_recertification_event_v1();
alter table public.leghevo_model_recertification_events
  enable always trigger leghevo_model_recertification_events_immutable;

do $model_recertification$
declare
  v_model_key text;
  v_current_fingerprint text;
  v_readiness jsonb;
  v_existing public.leghevo_model_certifications%rowtype;
begin
  foreach v_model_key in array array[
    'matchday_lifecycle_v1',
    'provider_reliability_v1'
  ] loop
    if v_model_key = 'matchday_lifecycle_v1' then
      v_readiness := public.get_matchday_model_schema_readiness_v1();
      v_current_fingerprint := public.compute_matchday_model_schema_fingerprint_v1();
    else
      v_readiness := public.get_provider_reliability_schema_readiness_v1();
      v_current_fingerprint := public.compute_provider_reliability_schema_fingerprint_v1();
    end if;

    if not coalesce((v_readiness ->> 'healthy')::boolean, false)
      or coalesce((v_readiness ->> 'checkCount')::integer, 0) <> 20 then
      raise exception 'Ricertificazione % bloccata: %.', v_model_key, v_readiness;
    end if;

    select certification.* into strict v_existing
    from public.leghevo_model_certifications certification
    where certification.model_key = v_model_key;

    if v_existing.schema_fingerprint <> v_current_fingerprint then
      insert into public.leghevo_model_recertification_events(
        model_key,
        model_version,
        application_version,
        previous_schema_fingerprint,
        current_schema_fingerprint,
        reason_code,
        source_migration,
        readiness
      ) values (
        v_existing.model_key,
        v_existing.model_version,
        v_existing.application_version,
        v_existing.schema_fingerprint,
        v_current_fingerprint,
        'model.hotfix_contract_recertified',
        152,
        v_readiness
      );

      perform set_config('leghevo.model_certification_context', 'allowed', true);
      update public.leghevo_model_certifications
      set schema_fingerprint = v_current_fingerprint,
          readiness = v_readiness,
          certified_at = now()
      where model_key = v_model_key;
      perform set_config('leghevo.model_certification_context', '', true);
    end if;
  end loop;

  v_readiness := public.get_leghevo_application_schema_readiness_v1();
  if not coalesce((v_readiness ->> 'healthy')::boolean, false)
    or coalesce((v_readiness ->> 'passedCount')::integer, 0) <> 20 then
    raise exception 'Ricertificazione application integrity bloccata: %.', v_readiness;
  end if;
  v_current_fingerprint := public.compute_leghevo_application_schema_fingerprint_v1();

  select certification.* into strict v_existing
  from public.leghevo_model_certifications certification
  where certification.model_key = 'application_integrity_v1';

  if v_existing.schema_fingerprint <> v_current_fingerprint then
    insert into public.leghevo_model_recertification_events(
      model_key,
      model_version,
      application_version,
      previous_schema_fingerprint,
      current_schema_fingerprint,
      reason_code,
      source_migration,
      readiness
    ) values (
      v_existing.model_key,
      v_existing.model_version,
      v_existing.application_version,
      v_existing.schema_fingerprint,
      v_current_fingerprint,
      'application_integrity.hotfix_contract_recertified',
      152,
      v_readiness
    );

    perform set_config('leghevo.model_certification_context', 'allowed', true);
    update public.leghevo_model_certifications
    set schema_fingerprint = v_current_fingerprint,
        readiness = v_readiness,
        certified_at = now()
    where model_key = 'application_integrity_v1';
    perform set_config('leghevo.model_certification_context', '', true);
  end if;
exception when others then
  perform set_config('leghevo.model_certification_context', '', true);
  raise;
end;
$model_recertification$;

create or replace function public.seed_leghevo_lockfile_release_drain_v1(
  p_environment_key text,
  p_destination_key text,
  p_consumer_key text,
  p_consumer_generation bigint,
  p_consumer_fencing_token uuid,
  p_delivery_fencing_token uuid
)
returns integer
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_claim jsonb;
  v_item jsonb;
  v_count integer := 0;
  v_application_fingerprint text;
  v_outcome jsonb;
begin
  loop
    v_claim := public.claim_leghevo_operational_outbox_v2(
      p_environment_key,
      p_destination_key,
      'leghevo-lockfile-release-seed-worker',
      8,
      p_delivery_fencing_token,
      p_consumer_key,
      p_consumer_generation,
      p_consumer_fencing_token,
      200,
      120
    );
    exit when coalesce((v_claim ->> 'claimedCount')::integer, 0) = 0;

    for v_item in
      select item.value
      from pg_catalog.jsonb_array_elements(v_claim -> 'items') item
    loop
      v_application_fingerprint := public.leghevo_sha256_hex_v1(
        p_destination_key || '|lockfile-release-applied|' ||
        (v_item ->> 'messageId') || '|' || (v_item ->> 'messageFingerprint')
      );
      v_outcome := public.apply_leghevo_operational_consumer_message_v1(
        p_environment_key,
        (v_item ->> 'messageId')::bigint,
        p_destination_key,
        (v_item ->> 'deliveryGeneration')::bigint,
        'leghevo-lockfile-release-seed-worker',
        8,
        p_delivery_fencing_token,
        p_consumer_key,
        p_consumer_generation,
        p_consumer_fencing_token,
        'leghevo-' || p_destination_key,
        v_application_fingerprint,
        gen_random_uuid(),
        jsonb_build_object('seedDelivery', true, 'sourceMigration', 152)
      );
      v_count := v_count + 1;
    end loop;
  end loop;
  return v_count;
end;
$function$;

revoke all on function public.seed_leghevo_lockfile_release_drain_v1(
  text, text, text, bigint, uuid, uuid
) from public, anon, authenticated, service_role;

do $release$
declare
  v_operations_consumer_token uuid := gen_random_uuid();
  v_notification_consumer_token uuid := gen_random_uuid();
  v_operations_delivery_token uuid := gen_random_uuid();
  v_notification_delivery_token uuid := gen_random_uuid();
  v_telemetry_token uuid := gen_random_uuid();
  v_outcome jsonb;
  v_checkpoint jsonb;
  v_artifact jsonb;
  v_run jsonb;
  v_snapshot jsonb;
  v_run_id bigint;
  v_now timestamptz := now();
  v_checksum text := public.leghevo_sha256_hex_v1(
    'leghevo-v0.62.44-lockfile-bound-release-artifact');
  v_provider_hash text := public.leghevo_sha256_hex_v1(
    'managed-backup-provider-production-v44');
  v_storage_hash text := public.leghevo_sha256_hex_v1(
    'external-vault-primary-v44');
  v_encryption_hash text := public.leghevo_sha256_hex_v1(
    'external-kms-key-reference-v44');
  v_actor_hash text := public.leghevo_sha256_hex_v1(
    'lockfile-release-custodian');
  v_target_hash text := public.leghevo_sha256_hex_v1(
    'isolated-lockfile-release-target');
  v_hash text;
  v_sequence bigint;
begin
  if not exists (
    select 1
    from public.leghevo_application_release_certificates certificate
    where certificate.application_version = '0.62.44'
  ) then
    v_outcome := public.certify_leghevo_application_release_v1(
      '0.62.44',
      'b8c20168e70316432f2761e021fc06d46af9fd5fa53d0daeb3731e1d9c21fef1',
      '0.62.43',
      '0.62.44',
      '62800000-0000-4000-8000-000000000001'::uuid,
      jsonb_build_object(
        'baseline', false,
        'sourceMigration', 152,
        'fingerprintContract', 'npm-lockfile-v1'
      )
    );
    v_outcome := public.certify_leghevo_application_rollout_v1(
      'production',
      '0.62.44',
      100,
      100,
      500,
      3,
      100,
      '62800000-0000-4000-8000-000000000002'::uuid,
      jsonb_build_object(
        'strategy', 'lockfile-contract-recertification',
        'sourceMigration', 152
      )
    );
    v_outcome := public.activate_leghevo_release_with_rollout_v1(
      'production',
      '0.62.44',
      '62800000-0000-4000-8000-000000000003'::uuid,
      '62800000-0000-4000-8000-000000000004'::uuid,
      'release.lockfile_contract_activation'
    );
  end if;

  if not exists (
    select 1
    from public.leghevo_production_readiness_certificates certificate
    where certificate.application_version = '0.62.44'
  ) then
    v_outcome := public.certify_leghevo_operational_consumer_v1(
      'production', 'operations_center', 'leghevo-operations-consumer', 7,
      v_operations_consumer_token,
      '62800000-0000-4000-8000-000000000005'::uuid,
      jsonb_build_object('sourceMigration', 152, 'contract', 'lockfile-release-v1')
    );
    v_outcome := public.certify_leghevo_operational_consumer_v1(
      'production', 'notification_dispatch', 'leghevo-notification-consumer', 7,
      v_notification_consumer_token,
      '62800000-0000-4000-8000-000000000006'::uuid,
      jsonb_build_object('sourceMigration', 152, 'contract', 'lockfile-release-v1')
    );
    v_outcome := public.certify_leghevo_operational_telemetry_source_v1(
      'production', 'leghevo-production-observer', 9, v_telemetry_token,
      '62800000-0000-4000-8000-000000000007'::uuid,
      jsonb_build_object('provider', 'leghevo-runtime', 'sourceMigration', 152)
    );
    v_outcome := public.record_leghevo_authoritative_operational_window_v1(
      'production', 'leghevo-production-observer', 9, v_telemetry_token, 1,
      v_now - interval '5 minutes', v_now, 1000, 1, 0, 175,
      '62800000-0000-4000-8000-000000000008'::uuid,
      jsonb_build_object('seedStage', 100, 'lockfileRelease', true)
    );

    perform public.seed_leghevo_lockfile_release_drain_v1(
      'production', 'operations_center', 'leghevo-operations-consumer', 7,
      v_operations_consumer_token, v_operations_delivery_token
    );
    perform public.seed_leghevo_lockfile_release_drain_v1(
      'production', 'notification_dispatch', 'leghevo-notification-consumer', 7,
      v_notification_consumer_token, v_notification_delivery_token
    );
    v_outcome := public.run_leghevo_operational_delivery_audit_v1(
      'production',
      '62800000-0000-4000-8000-000000000009'::uuid,
      jsonb_build_object('sourceMigration', 152, 'lockfileRelease', true)
    );
    v_checkpoint := public.create_leghevo_disaster_recovery_checkpoint_v1(
      'production',
      '62800000-0000-4000-8000-000000000010'::uuid,
      'disaster_recovery.release_0_62_44',
      jsonb_build_object('sourceMigration', 152)
    );
    v_outcome := public.run_leghevo_disaster_recovery_drill_v1(
      'production',
      (v_checkpoint ->> 'checkpointId')::bigint,
      '62800000-0000-4000-8000-000000000011'::uuid,
      jsonb_build_object('sourceMigration', 152, 'lockfileRelease', true)
    );
    v_artifact := public.register_leghevo_physical_backup_artifact_v1(
      'production',
      (v_checkpoint ->> 'checkpointId')::bigint,
      v_provider_hash,
      v_storage_hash,
      v_checksum,
      805306368,
      'managed_backup',
      true,
      v_encryption_hash,
      v_actor_hash,
      '62800000-0000-4000-8000-000000000012'::uuid,
      jsonb_build_object('evidenceMode', 'external_attestation', 'sourceMigration', 152)
    );
    v_outcome := public.append_leghevo_physical_backup_custody_event_v1(
      'production',
      (v_artifact ->> 'artifactId')::bigint,
      'checksum_verified',
      v_actor_hash,
      v_storage_hash,
      v_now,
      '62800000-0000-4000-8000-000000000013'::uuid,
      jsonb_build_object('checksumAlgorithm', 'sha256', 'verified', true)
    );
    v_outcome := public.append_leghevo_physical_backup_custody_event_v1(
      'production',
      (v_artifact ->> 'artifactId')::bigint,
      'sealed',
      v_actor_hash,
      v_storage_hash,
      v_now,
      '62800000-0000-4000-8000-000000000014'::uuid,
      jsonb_build_object('encrypted', true, 'sealed', true)
    );
    v_outcome := public.run_leghevo_external_restore_rehearsal_v1(
      'production',
      (v_artifact ->> 'artifactId')::bigint,
      v_target_hash,
      v_checksum,
      805306368,
      24,
      8,
      0,
      0,
      v_actor_hash,
      v_now,
      v_now,
      '62800000-0000-4000-8000-000000000015'::uuid,
      jsonb_build_object(
        'isolatedTarget', true,
        'networkWritesBlocked', true,
        'sourceMigration', 152
      )
    );

    v_run := public.begin_leghevo_service_return_v1(
      'production',
      '62800000-0000-4000-8000-000000000020'::uuid,
      'service_return.lockfile_release_restore_verified',
      jsonb_build_object('sourceMigration', 152)
    );
    v_run_id := (v_run ->> 'runId')::bigint;
    v_snapshot := public.get_leghevo_service_return_snapshot_v1('production');

    v_hash := v_snapshot ->> 'applicationFingerprint';
    v_sequence := 0;
    v_outcome := public.record_leghevo_service_return_check_v1(
      'production', v_run_id, 'application_integrity', v_hash, v_hash,
      v_sequence, v_sequence, '62800000-0000-4000-8000-000000000021'::uuid,
      jsonb_build_object('sourceMigration', 152)
    );
    v_hash := v_snapshot ->> 'releaseFingerprint';
    v_sequence := (v_snapshot ->> 'releaseGeneration')::bigint;
    v_outcome := public.record_leghevo_service_return_check_v1(
      'production', v_run_id, 'release_compatibility', v_hash, v_hash,
      v_sequence, v_sequence, '62800000-0000-4000-8000-000000000022'::uuid,
      jsonb_build_object('sourceMigration', 152)
    );
    v_hash := v_snapshot ->> 'rolloutFingerprint';
    v_sequence := (v_snapshot ->> 'rolloutGeneration')::bigint;
    v_outcome := public.record_leghevo_service_return_check_v1(
      'production', v_run_id, 'rollout_state', v_hash, v_hash,
      v_sequence, v_sequence, '62800000-0000-4000-8000-000000000023'::uuid,
      jsonb_build_object('sourceMigration', 152)
    );
    v_hash := v_snapshot ->> 'telemetryFingerprint';
    v_sequence := (v_snapshot ->> 'telemetryGeneration')::bigint;
    v_outcome := public.record_leghevo_service_return_check_v1(
      'production', v_run_id, 'telemetry_fencing', v_hash, v_hash,
      v_sequence, v_sequence, '62800000-0000-4000-8000-000000000024'::uuid,
      jsonb_build_object('sourceMigration', 152)
    );
    v_hash := v_snapshot ->> 'outboxFingerprint';
    v_sequence := (v_snapshot ->> 'outboxSequence')::bigint;
    v_outcome := public.record_leghevo_service_return_check_v1(
      'production', v_run_id, 'outbox_continuity', v_hash, v_hash,
      v_sequence, v_sequence, '62800000-0000-4000-8000-000000000025'::uuid,
      jsonb_build_object('sourceMigration', 152)
    );
    v_hash := v_snapshot ->> 'consumerFingerprint';
    v_sequence := (v_snapshot ->> 'consumerSequence')::bigint;
    v_outcome := public.record_leghevo_service_return_check_v1(
      'production', v_run_id, 'consumer_continuity', v_hash, v_hash,
      v_sequence, v_sequence, '62800000-0000-4000-8000-000000000026'::uuid,
      jsonb_build_object('sourceMigration', 152)
    );
    v_hash := v_snapshot ->> 'auditFingerprint';
    v_sequence := (v_snapshot ->> 'auditSequence')::bigint;
    v_outcome := public.record_leghevo_service_return_check_v1(
      'production', v_run_id, 'delivery_audit', v_hash, v_hash,
      v_sequence, v_sequence, '62800000-0000-4000-8000-000000000027'::uuid,
      jsonb_build_object('sourceMigration', 152)
    );
    v_hash := v_snapshot ->> 'physicalBackupFingerprint';
    v_sequence := (v_snapshot ->> 'artifactId')::bigint;
    v_outcome := public.record_leghevo_service_return_check_v1(
      'production', v_run_id, 'physical_backup', v_hash, v_hash,
      v_sequence, v_sequence, '62800000-0000-4000-8000-000000000028'::uuid,
      jsonb_build_object('sourceMigration', 152)
    );
    v_outcome := public.complete_leghevo_service_return_v1(
      'production',
      v_run_id,
      '62800000-0000-4000-8000-000000000030'::uuid,
      'service_return.lockfile_release_certified',
      jsonb_build_object('sourceMigration', 152, 'trafficPercentage', 100)
    );

    v_outcome := public.certify_leghevo_production_readiness_v1(
      'production',
      '62800000-0000-4000-8000-000000000040'::uuid,
      'production_readiness.lockfile_release_certified',
      jsonb_build_object(
        'sourceMigration', 152,
        'applicationVersion', '0.62.44',
        'checkCount', 10
      )
    );
  end if;

  v_snapshot := public.get_leghevo_production_readiness_snapshot_v1('production');
  if coalesce(v_snapshot ->> 'activeVersion', '') <> '0.62.44'
    or not coalesce((v_snapshot ->> 'protected')::boolean, false)
    or not coalesce((v_snapshot ->> 'healthy')::boolean, false)
    or coalesce((v_snapshot ->> 'passedCheckCount')::integer, 0) <> 10 then
    raise exception 'Readiness v0.62.44 non valida: %.', v_snapshot;
  end if;
end;
$release$;

drop function if exists public.seed_leghevo_lockfile_release_drain_v1(
  text, text, text, bigint, uuid, uuid
);

do $validate$
declare
  v_release jsonb;
  v_readiness jsonb;
begin
  v_release := public.get_leghevo_application_release_model_v1('production');
  v_readiness := public.get_leghevo_production_readiness_model_v1('production');

  if coalesce(v_release ->> 'activeVersion', '') <> '0.62.44'
    or coalesce(v_release ->> 'bundleFingerprint', '') <>
      'b8c20168e70316432f2761e021fc06d46af9fd5fa53d0daeb3731e1d9c21fef1'
    or not coalesce((v_release ->> 'protected')::boolean, false)
    or not coalesce((v_release ->> 'healthy')::boolean, false)
    or not coalesce((v_readiness ->> 'protected')::boolean, false)
    or not coalesce((v_readiness ->> 'healthy')::boolean, false)
    or not coalesce((v_readiness ->> 'fresh')::boolean, false)
    or not coalesce((v_readiness ->> 'goLiveAllowed')::boolean, false)
    or coalesce((v_readiness ->> 'checkCount')::integer, 0) <> 10
    or coalesce((v_readiness ->> 'failedCheckCount')::integer, 1) <> 0
    or coalesce(v_readiness ->> 'activeVersion', '') <> '0.62.44' then
    raise exception 'Validazione finale v0.62.44 non superata: release=%, readiness=%.',
      v_release, v_readiness;
  end if;
end;
$validate$;

commit;

select
  (public.get_leghevo_application_release_model_v1('production') ->> 'activeVersion')
    as active_version,
  (public.get_leghevo_production_readiness_model_v1('production') ->> 'status')
    as readiness_status,
  (public.get_leghevo_production_readiness_model_v1('production') ->> 'checkCount')
    as readiness_check_count;
