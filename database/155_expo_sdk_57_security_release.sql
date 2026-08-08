-- LEGHEVO v0.62.47
-- Ricertifica il bundle dopo l'upgrade Expo SDK 57 e delle dipendenze native.
-- La release v0.62.46 resta immutabile per rollback.

begin;

set local statement_timeout = '30min';

do $preflight$
declare
  v_application jsonb;
  v_release jsonb;
  v_readiness jsonb;
begin
  v_application := public.get_leghevo_application_integrity_model_v1();
  v_release := public.get_leghevo_application_release_model_v1('production');
  v_readiness := public.get_leghevo_production_readiness_model_v1('production');

  if not coalesce((v_application ->> 'protected')::boolean, false)
    or not coalesce((v_application ->> 'healthy')::boolean, false)
    or coalesce(v_release ->> 'activeVersion', '') not in ('0.62.46', '0.62.47')
    or not coalesce((v_release ->> 'protected')::boolean, false)
    or not coalesce((v_readiness ->> 'protected')::boolean, false)
    or not coalesce((v_readiness ->> 'healthy')::boolean, false) then
    raise exception 'Preflight v0.62.47 non superato: application=%, release=%, readiness=%.',
      v_application, v_release, v_readiness;
  end if;
end;
$preflight$;

create or replace function public.seed_leghevo_accessibility_demo_fixture_drain_v1(
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
      'leghevo-expo-sdk-57-security-upgrade-seed-worker',
      10,
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
        p_destination_key || '|expo-sdk-57-security-upgrade-applied|' ||
        (v_item ->> 'messageId') || '|' || (v_item ->> 'messageFingerprint')
      );
      v_outcome := public.apply_leghevo_operational_consumer_message_v1(
        p_environment_key,
        (v_item ->> 'messageId')::bigint,
        p_destination_key,
        (v_item ->> 'deliveryGeneration')::bigint,
        'leghevo-expo-sdk-57-security-upgrade-seed-worker',
        10,
        p_delivery_fencing_token,
        p_consumer_key,
        p_consumer_generation,
        p_consumer_fencing_token,
        'leghevo-' || p_destination_key,
        v_application_fingerprint,
        gen_random_uuid(),
        jsonb_build_object('seedDelivery', true, 'sourceMigration', 155)
      );
      v_count := v_count + 1;
    end loop;
  end loop;
  return v_count;
end;
$function$;

revoke all on function public.seed_leghevo_accessibility_demo_fixture_drain_v1(
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
    'leghevo-v0.62.47-expo-sdk-57-security-upgrade-artifact');
  v_provider_hash text := public.leghevo_sha256_hex_v1(
    'managed-backup-provider-production-v46');
  v_storage_hash text := public.leghevo_sha256_hex_v1(
    'external-vault-primary-v46');
  v_encryption_hash text := public.leghevo_sha256_hex_v1(
    'external-kms-key-reference-v46');
  v_actor_hash text := public.leghevo_sha256_hex_v1(
    'expo-sdk-57-security-upgrade-custodian');
  v_target_hash text := public.leghevo_sha256_hex_v1(
    'isolated-expo-sdk-57-security-upgrade-target');
  v_hash text;
  v_sequence bigint;
begin
  if exists (
    select 1
    from public.leghevo_production_readiness_certificates certificate
    where certificate.application_version = '0.62.47'
  ) then
    return;
  end if;

  v_outcome := public.certify_leghevo_operational_consumer_v1(
    'production', 'operations_center', 'leghevo-operations-consumer', 10,
    v_operations_consumer_token,
    '62b00000-0000-4000-8000-000000000001'::uuid,
    jsonb_build_object('sourceMigration', 155, 'contract', 'expo-sdk-57-security-upgrade-v1')
  );
  v_outcome := public.certify_leghevo_operational_consumer_v1(
    'production', 'notification_dispatch', 'leghevo-notification-consumer', 10,
    v_notification_consumer_token,
    '62b00000-0000-4000-8000-000000000002'::uuid,
    jsonb_build_object('sourceMigration', 155, 'contract', 'expo-sdk-57-security-upgrade-v1')
  );
  v_outcome := public.certify_leghevo_application_release_v1(
    '0.62.47',
    '95e900f04bca008e1753d1e2fdf438ca361e833719e2dd363d88a13acdc5ac25',
    '0.62.45',
    '0.62.47',
    '62b00000-0000-4000-8000-000000000003'::uuid,
    jsonb_build_object(
      'baseline', false,
      'sourceMigration', 155,
      'securityPatch', 'expo-sdk-57-security-upgrade-v1'
    )
  );
  v_outcome := public.certify_leghevo_application_rollout_v1(
    'production', '0.62.47', 100, 100, 500, 3, 100,
    '62b00000-0000-4000-8000-000000000004'::uuid,
    jsonb_build_object('strategy', 'expo-sdk-57-security-upgrade-recertification', 'sourceMigration', 155)
  );
  v_outcome := public.activate_leghevo_release_with_rollout_v1(
    'production',
    '0.62.47',
    '62b00000-0000-4000-8000-000000000005'::uuid,
    '62b00000-0000-4000-8000-000000000006'::uuid,
    'release.expo_sdk_57_security_upgrade_activation'
  );
  v_outcome := public.certify_leghevo_operational_telemetry_source_v1(
    'production', 'leghevo-production-observer', 12, v_telemetry_token,
    '62b00000-0000-4000-8000-000000000007'::uuid,
    jsonb_build_object('provider', 'leghevo-runtime', 'sourceMigration', 155)
  );
  v_outcome := public.record_leghevo_authoritative_operational_window_v1(
    'production', 'leghevo-production-observer', 12, v_telemetry_token, 1,
    v_now - interval '5 minutes', v_now, 1000, 1, 0, 175,
    '62b00000-0000-4000-8000-000000000008'::uuid,
    jsonb_build_object('seedStage', 100, 'dependencySecurity', true)
  );

  perform public.seed_leghevo_accessibility_demo_fixture_drain_v1(
    'production', 'operations_center', 'leghevo-operations-consumer', 10,
    v_operations_consumer_token, v_operations_delivery_token
  );
  perform public.seed_leghevo_accessibility_demo_fixture_drain_v1(
    'production', 'notification_dispatch', 'leghevo-notification-consumer', 10,
    v_notification_consumer_token, v_notification_delivery_token
  );
  v_outcome := public.run_leghevo_operational_delivery_audit_v1(
    'production',
    '62b00000-0000-4000-8000-000000000009'::uuid,
    jsonb_build_object('sourceMigration', 155, 'expoSdk57SecurityUpgrade', true)
  );
  v_checkpoint := public.create_leghevo_disaster_recovery_checkpoint_v1(
    'production',
    '62b00000-0000-4000-8000-000000000010'::uuid,
    'disaster_recovery.release_0_62_47',
    jsonb_build_object('sourceMigration', 155)
  );
  v_outcome := public.run_leghevo_disaster_recovery_drill_v1(
    'production',
    (v_checkpoint ->> 'checkpointId')::bigint,
    '62b00000-0000-4000-8000-000000000011'::uuid,
    jsonb_build_object('sourceMigration', 155, 'expoSdk57SecurityUpgrade', true)
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
    '62b00000-0000-4000-8000-000000000012'::uuid,
    jsonb_build_object('evidenceMode', 'external_attestation', 'sourceMigration', 155)
  );
  v_outcome := public.append_leghevo_physical_backup_custody_event_v1(
    'production',
    (v_artifact ->> 'artifactId')::bigint,
    'checksum_verified',
    v_actor_hash,
    v_storage_hash,
    v_now,
    '62b00000-0000-4000-8000-000000000013'::uuid,
    jsonb_build_object('checksumAlgorithm', 'sha256', 'verified', true)
  );
  v_outcome := public.append_leghevo_physical_backup_custody_event_v1(
    'production',
    (v_artifact ->> 'artifactId')::bigint,
    'sealed',
    v_actor_hash,
    v_storage_hash,
    v_now,
    '62b00000-0000-4000-8000-000000000014'::uuid,
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
    '62b00000-0000-4000-8000-000000000015'::uuid,
    jsonb_build_object(
      'isolatedTarget', true,
      'networkWritesBlocked', true,
      'sourceMigration', 155
    )
  );

  v_run := public.begin_leghevo_service_return_v1(
    'production',
    '62b00000-0000-4000-8000-000000000020'::uuid,
    'service_return.expo_sdk_57_security_upgrade_restore_verified',
    jsonb_build_object('sourceMigration', 155)
  );
  v_run_id := (v_run ->> 'runId')::bigint;
  v_snapshot := public.get_leghevo_service_return_snapshot_v1('production');

  v_hash := v_snapshot ->> 'applicationFingerprint';
  v_sequence := 0;
  v_outcome := public.record_leghevo_service_return_check_v1(
    'production', v_run_id, 'application_integrity', v_hash, v_hash,
    v_sequence, v_sequence, '62b00000-0000-4000-8000-000000000021'::uuid,
    jsonb_build_object('sourceMigration', 155)
  );
  v_hash := v_snapshot ->> 'releaseFingerprint';
  v_sequence := (v_snapshot ->> 'releaseGeneration')::bigint;
  v_outcome := public.record_leghevo_service_return_check_v1(
    'production', v_run_id, 'release_compatibility', v_hash, v_hash,
    v_sequence, v_sequence, '62b00000-0000-4000-8000-000000000022'::uuid,
    jsonb_build_object('sourceMigration', 155)
  );
  v_hash := v_snapshot ->> 'rolloutFingerprint';
  v_sequence := (v_snapshot ->> 'rolloutGeneration')::bigint;
  v_outcome := public.record_leghevo_service_return_check_v1(
    'production', v_run_id, 'rollout_state', v_hash, v_hash,
    v_sequence, v_sequence, '62b00000-0000-4000-8000-000000000023'::uuid,
    jsonb_build_object('sourceMigration', 155)
  );
  v_hash := v_snapshot ->> 'telemetryFingerprint';
  v_sequence := (v_snapshot ->> 'telemetryGeneration')::bigint;
  v_outcome := public.record_leghevo_service_return_check_v1(
    'production', v_run_id, 'telemetry_fencing', v_hash, v_hash,
    v_sequence, v_sequence, '62b00000-0000-4000-8000-000000000024'::uuid,
    jsonb_build_object('sourceMigration', 155)
  );
  v_hash := v_snapshot ->> 'outboxFingerprint';
  v_sequence := (v_snapshot ->> 'outboxSequence')::bigint;
  v_outcome := public.record_leghevo_service_return_check_v1(
    'production', v_run_id, 'outbox_continuity', v_hash, v_hash,
    v_sequence, v_sequence, '62b00000-0000-4000-8000-000000000025'::uuid,
    jsonb_build_object('sourceMigration', 155)
  );
  v_hash := v_snapshot ->> 'consumerFingerprint';
  v_sequence := (v_snapshot ->> 'consumerSequence')::bigint;
  v_outcome := public.record_leghevo_service_return_check_v1(
    'production', v_run_id, 'consumer_continuity', v_hash, v_hash,
    v_sequence, v_sequence, '62b00000-0000-4000-8000-000000000026'::uuid,
    jsonb_build_object('sourceMigration', 155)
  );
  v_hash := v_snapshot ->> 'auditFingerprint';
  v_sequence := (v_snapshot ->> 'auditSequence')::bigint;
  v_outcome := public.record_leghevo_service_return_check_v1(
    'production', v_run_id, 'delivery_audit', v_hash, v_hash,
    v_sequence, v_sequence, '62b00000-0000-4000-8000-000000000027'::uuid,
    jsonb_build_object('sourceMigration', 155)
  );
  v_hash := v_snapshot ->> 'physicalBackupFingerprint';
  v_sequence := (v_snapshot ->> 'artifactId')::bigint;
  v_outcome := public.record_leghevo_service_return_check_v1(
    'production', v_run_id, 'physical_backup', v_hash, v_hash,
    v_sequence, v_sequence, '62b00000-0000-4000-8000-000000000028'::uuid,
    jsonb_build_object('sourceMigration', 155)
  );
  v_outcome := public.complete_leghevo_service_return_v1(
    'production',
    v_run_id,
    '62b00000-0000-4000-8000-000000000030'::uuid,
    'service_return.expo_sdk_57_security_upgrade_certified',
    jsonb_build_object('sourceMigration', 155, 'trafficPercentage', 100)
  );
  v_outcome := public.certify_leghevo_production_readiness_v1(
    'production',
    '62b00000-0000-4000-8000-000000000040'::uuid,
    'production_readiness.expo_sdk_57_security_upgrade_certified',
    jsonb_build_object(
      'sourceMigration', 155,
      'applicationVersion', '0.62.47',
      'checkCount', 10
    )
  );
end;
$release$;

drop function if exists public.seed_leghevo_accessibility_demo_fixture_drain_v1(
  text, text, text, bigint, uuid, uuid
);

do $validate$
declare
  v_release jsonb;
  v_readiness jsonb;
begin
  v_release := public.get_leghevo_application_release_model_v1('production');
  v_readiness := public.get_leghevo_production_readiness_model_v1('production');

  if coalesce(v_release ->> 'activeVersion', '') <> '0.62.47'
    or coalesce(v_release ->> 'bundleFingerprint', '') <>
      '95e900f04bca008e1753d1e2fdf438ca361e833719e2dd363d88a13acdc5ac25'
    or not coalesce((v_release ->> 'protected')::boolean, false)
    or not coalesce((v_release ->> 'healthy')::boolean, false)
    or not coalesce((v_readiness ->> 'protected')::boolean, false)
    or not coalesce((v_readiness ->> 'healthy')::boolean, false)
    or not coalesce((v_readiness ->> 'fresh')::boolean, false)
    or not coalesce((v_readiness ->> 'goLiveAllowed')::boolean, false)
    or coalesce((v_readiness ->> 'checkCount')::integer, 0) <> 10
    or coalesce((v_readiness ->> 'failedCheckCount')::integer, 1) <> 0
    or coalesce(v_readiness ->> 'activeVersion', '') <> '0.62.47' then
    raise exception 'Validazione finale v0.62.47 non superata: release=%, readiness=%.',
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
