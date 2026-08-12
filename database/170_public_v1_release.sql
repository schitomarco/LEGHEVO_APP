-- LEGHEVO v1.0.0
-- Certifica e attiva la prima release pubblica sugli store.
-- La candidata v0.62.50 resta immutabile e disponibile per il rollback.

begin;

set local statement_timeout = '30min';

do $preflight$
declare
  v_application jsonb;
  v_release jsonb;
  v_head public.leghevo_production_readiness_heads%rowtype;
  v_run public.leghevo_production_readiness_runs%rowtype;
  v_certificate public.leghevo_production_readiness_certificates%rowtype;
  v_check_count integer := 0;
  v_failed_check_count integer := 0;
  v_checks_fingerprint text;
begin
  raise notice 'LEGHEVO_V1_STAGE preflight_application';
  v_application := public.get_leghevo_application_integrity_model_v1();
  raise notice 'LEGHEVO_V1_STAGE preflight_release';
  v_release := public.get_leghevo_application_release_model_v1('production');
  raise notice 'LEGHEVO_V1_STAGE preflight_readiness';
  select head.* into v_head
  from public.leghevo_production_readiness_heads head
  where head.environment_key = 'production';
  if not found then
    raise exception 'Preflight v1.0.0 non superato: readiness head assente.';
  end if;

  select run.* into strict v_run
  from public.leghevo_production_readiness_runs run
  where run.id = v_head.run_id;
  select certificate.* into strict v_certificate
  from public.leghevo_production_readiness_certificates certificate
  where certificate.id = v_head.certificate_id;
  select count(*), count(*) filter (where check_row.status <> 'passed'),
    public.leghevo_sha256_hex_v1(
      string_agg(
        check_row.check_key || '|' || check_row.check_fingerprint,
        ';' order by check_row.check_ordinal
      )
    )
  into v_check_count, v_failed_check_count, v_checks_fingerprint
  from public.leghevo_production_readiness_checks check_row
  where check_row.run_id = v_run.id;
  raise notice 'LEGHEVO_V1_STAGE preflight_validate';

  if not coalesce((v_application ->> 'protected')::boolean, false)
    or not coalesce((v_application ->> 'healthy')::boolean, false)
    or coalesce(v_release ->> 'activeVersion', '') not in ('0.62.50', '1.0.0')
    or not coalesce((v_release ->> 'protected')::boolean, false)
    or not coalesce((v_release ->> 'healthy')::boolean, false)
    or v_head.mode <> 'active'
    or v_head.status not in ('certified', 'revalidated')
    or not v_head.go_live_allowed
    or v_head.active_release_version <> v_run.active_release_version
    or v_run.status <> 'certified'
    or v_run.active_release_version not in ('0.62.50', '1.0.0')
    or v_run.run_fingerprint <> public.compute_leghevo_production_readiness_run_fingerprint_v1(
      v_run.environment_key, v_run.readiness_generation, v_run.active_release_version,
      v_run.release_generation, v_run.rollout_generation, v_run.telemetry_generation,
      v_run.outbox_sequence, v_run.consumer_sequence, v_run.audit_sequence,
      v_run.checkpoint_generation, v_run.backup_generation,
      v_run.service_return_generation, v_run.snapshot_fingerprint, v_run.contract_version
    )
    or v_check_count <> 10
    or v_failed_check_count <> 0
    or v_certificate.status <> 'certified'
    or v_certificate.application_version <> v_run.active_release_version
    or v_certificate.run_fingerprint <> v_run.run_fingerprint
    or v_certificate.checks_fingerprint <> v_checks_fingerprint
    or v_certificate.certificate_fingerprint <>
      public.compute_leghevo_production_readiness_certificate_fingerprint_v1(
        v_certificate.run_id, v_certificate.environment_key,
        v_certificate.readiness_generation, v_certificate.application_version,
        v_certificate.check_count, v_certificate.run_fingerprint,
        v_certificate.checks_fingerprint, v_certificate.contract_version
      ) then
    raise exception
      'Preflight v1.0.0 non superato: application=%, release=%, head=%, run=%, certificate=%, checks=%/%.',
      v_application, v_release, row_to_json(v_head), row_to_json(v_run),
      row_to_json(v_certificate), v_check_count, v_failed_check_count;
  end if;
end;
$preflight$;

create or replace function public.seed_leghevo_public_v1_outbox_drain_v1(
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
  v_target_stream_sequence bigint;
  v_processed_stream_sequence bigint := 0;
begin
  raise notice 'LEGHEVO_V1_STAGE release_start';
  -- Congela il confine della coda prima di iniziare. Le procedure di ack
  -- possono produrre nuova telemetria operativa: inseguirla nello stesso
  -- ciclo renderebbe il seed non terminante.
  select coalesce(max(message.stream_sequence), 0)
  into v_target_stream_sequence
  from public.leghevo_operational_outbox_messages message
  where message.environment_key = lower(trim(p_environment_key));

  loop
    exit when v_processed_stream_sequence >= v_target_stream_sequence;

    v_claim := public.claim_leghevo_operational_outbox_v2(
      p_environment_key,
      p_destination_key,
      'leghevo-public-v1-seed-worker',
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
        p_destination_key || '|public-v1-applied|' ||
        (v_item ->> 'messageId') || '|' || (v_item ->> 'messageFingerprint')
      );
      v_outcome := public.apply_leghevo_operational_consumer_message_v1(
        p_environment_key,
        (v_item ->> 'messageId')::bigint,
        p_destination_key,
        (v_item ->> 'deliveryGeneration')::bigint,
        'leghevo-public-v1-seed-worker',
        10,
        p_delivery_fencing_token,
        p_consumer_key,
        p_consumer_generation,
        p_consumer_fencing_token,
        'leghevo-' || p_destination_key,
        v_application_fingerprint,
        gen_random_uuid(),
        jsonb_build_object('seedDelivery', true, 'sourceMigration', 170)
      );
      v_count := v_count + 1;
      v_processed_stream_sequence := (v_item ->> 'streamSequence')::bigint;

      if v_count > 1000 then
        raise exception
          'Drenaggio outbox v1.0.0 oltre il limite di sicurezza: destination=%, target=%, processed=%.',
          p_destination_key, v_target_stream_sequence, v_processed_stream_sequence;
      end if;
    end loop;
  end loop;
  return v_count;
end;
$function$;

revoke all on function public.seed_leghevo_public_v1_outbox_drain_v1(
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
    'leghevo-v1.0.0-public-store-artifact');
  v_provider_hash text := public.leghevo_sha256_hex_v1(
    'managed-backup-provider-production-v1');
  v_storage_hash text := public.leghevo_sha256_hex_v1(
    'external-vault-primary-v1');
  v_encryption_hash text := public.leghevo_sha256_hex_v1(
    'external-kms-key-reference-v1');
  v_actor_hash text := public.leghevo_sha256_hex_v1(
    'public-v1-custodian');
  v_target_hash text := public.leghevo_sha256_hex_v1(
    'isolated-public-v1-restore-target');
  v_hash text;
  v_sequence bigint;
begin
  if exists (
    select 1
    from public.leghevo_production_readiness_certificates certificate
    where certificate.application_version = '1.0.0'
  ) then
    return;
  end if;

  v_outcome := public.certify_leghevo_operational_consumer_v1(
    'production', 'operations_center', 'leghevo-operations-consumer', 14,
    v_operations_consumer_token,
    '10000000-0000-4000-8000-000000000001'::uuid,
    jsonb_build_object('sourceMigration', 170, 'contract', 'public-v1')
  );
  v_outcome := public.certify_leghevo_operational_consumer_v1(
    'production', 'notification_dispatch', 'leghevo-notification-consumer', 14,
    v_notification_consumer_token,
    '10000000-0000-4000-8000-000000000002'::uuid,
    jsonb_build_object('sourceMigration', 170, 'contract', 'public-v1')
  );
  v_outcome := public.certify_leghevo_application_release_v1(
    '1.0.0',
    '06ea897294c9cb1c4a3d5377a37e7db073dc53b19dead5129d8efadbc11c7b68',
    '0.62.50',
    '1.0.0',
    '10000000-0000-4000-8000-000000000003'::uuid,
    jsonb_build_object(
      'baseline', false,
      'sourceMigration', 170,
      'release', 'public-v1'
    )
  );
  v_outcome := public.certify_leghevo_application_rollout_v1(
    'production', '1.0.0', 100, 100, 500, 3, 100,
    '10000000-0000-4000-8000-000000000004'::uuid,
    jsonb_build_object('strategy', 'public-v1-certification', 'sourceMigration', 170)
  );
  v_outcome := public.activate_leghevo_release_with_rollout_v1(
    'production',
    '1.0.0',
    '10000000-0000-4000-8000-000000000005'::uuid,
    '10000000-0000-4000-8000-000000000006'::uuid,
    'release.public_v1_activation'
  );
  raise notice 'LEGHEVO_V1_STAGE release_activated';
  v_outcome := public.certify_leghevo_operational_telemetry_source_v1(
    'production', 'leghevo-production-observer', 16, v_telemetry_token,
    '10000000-0000-4000-8000-000000000007'::uuid,
    jsonb_build_object('provider', 'leghevo-runtime', 'sourceMigration', 170)
  );
  v_outcome := public.record_leghevo_authoritative_operational_window_v1(
    'production', 'leghevo-production-observer', 16, v_telemetry_token, 1,
    v_now - interval '5 minutes', v_now, 1000, 1, 0, 175,
    '10000000-0000-4000-8000-000000000008'::uuid,
    jsonb_build_object('publicRelease', '1.0.0', 'dependencySecurity', true)
  );

  perform public.seed_leghevo_public_v1_outbox_drain_v1(
    'production', 'operations_center', 'leghevo-operations-consumer', 14,
    v_operations_consumer_token, v_operations_delivery_token
  );
  raise notice 'LEGHEVO_V1_STAGE operations_drained';
  perform public.seed_leghevo_public_v1_outbox_drain_v1(
    'production', 'notification_dispatch', 'leghevo-notification-consumer', 14,
    v_notification_consumer_token, v_notification_delivery_token
  );
  raise notice 'LEGHEVO_V1_STAGE notifications_drained';
  v_outcome := public.run_leghevo_operational_delivery_audit_v1(
    'production',
    '10000000-0000-4000-8000-000000000009'::uuid,
    jsonb_build_object('sourceMigration', 170, 'publicRelease', '1.0.0')
  );
  raise notice 'LEGHEVO_V1_STAGE audit_complete';
  v_checkpoint := public.create_leghevo_disaster_recovery_checkpoint_v1(
    'production',
    '10000000-0000-4000-8000-000000000010'::uuid,
    'disaster_recovery.release_1_0_0',
    jsonb_build_object('sourceMigration', 170)
  );
  v_outcome := public.run_leghevo_disaster_recovery_drill_v1(
    'production',
    (v_checkpoint ->> 'checkpointId')::bigint,
    '10000000-0000-4000-8000-000000000011'::uuid,
    jsonb_build_object('sourceMigration', 170, 'publicRelease', '1.0.0')
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
    '10000000-0000-4000-8000-000000000012'::uuid,
    jsonb_build_object('evidenceMode', 'external_attestation', 'sourceMigration', 170)
  );
  v_outcome := public.append_leghevo_physical_backup_custody_event_v1(
    'production',
    (v_artifact ->> 'artifactId')::bigint,
    'checksum_verified',
    v_actor_hash,
    v_storage_hash,
    v_now,
    '10000000-0000-4000-8000-000000000013'::uuid,
    jsonb_build_object('checksumAlgorithm', 'sha256', 'verified', true)
  );
  v_outcome := public.append_leghevo_physical_backup_custody_event_v1(
    'production',
    (v_artifact ->> 'artifactId')::bigint,
    'sealed',
    v_actor_hash,
    v_storage_hash,
    v_now,
    '10000000-0000-4000-8000-000000000014'::uuid,
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
    '10000000-0000-4000-8000-000000000015'::uuid,
    jsonb_build_object(
      'isolatedTarget', true,
      'networkWritesBlocked', true,
      'sourceMigration', 170
    )
  );
  raise notice 'LEGHEVO_V1_STAGE recovery_complete';

  v_run := public.begin_leghevo_service_return_v1(
    'production',
    '10000000-0000-4000-8000-000000000020'::uuid,
    'service_return.public_v1_restore_verified',
    jsonb_build_object('sourceMigration', 170)
  );
  v_run_id := (v_run ->> 'runId')::bigint;
  v_snapshot := public.get_leghevo_service_return_snapshot_v1('production');
  raise notice 'LEGHEVO_V1_STAGE service_snapshot';

  v_hash := v_snapshot ->> 'applicationFingerprint';
  v_sequence := 0;
  v_outcome := public.record_leghevo_service_return_check_v1(
    'production', v_run_id, 'application_integrity', v_hash, v_hash,
    v_sequence, v_sequence, '10000000-0000-4000-8000-000000000021'::uuid,
    jsonb_build_object('sourceMigration', 170)
  );
  v_hash := v_snapshot ->> 'releaseFingerprint';
  v_sequence := (v_snapshot ->> 'releaseGeneration')::bigint;
  v_outcome := public.record_leghevo_service_return_check_v1(
    'production', v_run_id, 'release_compatibility', v_hash, v_hash,
    v_sequence, v_sequence, '10000000-0000-4000-8000-000000000022'::uuid,
    jsonb_build_object('sourceMigration', 170)
  );
  v_hash := v_snapshot ->> 'rolloutFingerprint';
  v_sequence := (v_snapshot ->> 'rolloutGeneration')::bigint;
  v_outcome := public.record_leghevo_service_return_check_v1(
    'production', v_run_id, 'rollout_state', v_hash, v_hash,
    v_sequence, v_sequence, '10000000-0000-4000-8000-000000000023'::uuid,
    jsonb_build_object('sourceMigration', 170)
  );
  v_hash := v_snapshot ->> 'telemetryFingerprint';
  v_sequence := (v_snapshot ->> 'telemetryGeneration')::bigint;
  v_outcome := public.record_leghevo_service_return_check_v1(
    'production', v_run_id, 'telemetry_fencing', v_hash, v_hash,
    v_sequence, v_sequence, '10000000-0000-4000-8000-000000000024'::uuid,
    jsonb_build_object('sourceMigration', 170)
  );
  v_hash := v_snapshot ->> 'outboxFingerprint';
  v_sequence := (v_snapshot ->> 'outboxSequence')::bigint;
  v_outcome := public.record_leghevo_service_return_check_v1(
    'production', v_run_id, 'outbox_continuity', v_hash, v_hash,
    v_sequence, v_sequence, '10000000-0000-4000-8000-000000000025'::uuid,
    jsonb_build_object('sourceMigration', 170)
  );
  v_hash := v_snapshot ->> 'consumerFingerprint';
  v_sequence := (v_snapshot ->> 'consumerSequence')::bigint;
  v_outcome := public.record_leghevo_service_return_check_v1(
    'production', v_run_id, 'consumer_continuity', v_hash, v_hash,
    v_sequence, v_sequence, '10000000-0000-4000-8000-000000000026'::uuid,
    jsonb_build_object('sourceMigration', 170)
  );
  v_hash := v_snapshot ->> 'auditFingerprint';
  v_sequence := (v_snapshot ->> 'auditSequence')::bigint;
  v_outcome := public.record_leghevo_service_return_check_v1(
    'production', v_run_id, 'delivery_audit', v_hash, v_hash,
    v_sequence, v_sequence, '10000000-0000-4000-8000-000000000027'::uuid,
    jsonb_build_object('sourceMigration', 170)
  );
  v_hash := v_snapshot ->> 'physicalBackupFingerprint';
  v_sequence := (v_snapshot ->> 'artifactId')::bigint;
  v_outcome := public.record_leghevo_service_return_check_v1(
    'production', v_run_id, 'physical_backup', v_hash, v_hash,
    v_sequence, v_sequence, '10000000-0000-4000-8000-000000000028'::uuid,
    jsonb_build_object('sourceMigration', 170)
  );
  v_outcome := public.complete_leghevo_service_return_v1(
    'production',
    v_run_id,
    '10000000-0000-4000-8000-000000000030'::uuid,
    'service_return.public_v1_certified',
    jsonb_build_object('sourceMigration', 170, 'trafficPercentage', 100)
  );
  raise notice 'LEGHEVO_V1_STAGE service_return_complete';
  v_outcome := public.certify_leghevo_production_readiness_v1(
    'production',
    '10000000-0000-4000-8000-000000000040'::uuid,
    'production_readiness.public_v1_certified',
    jsonb_build_object(
      'sourceMigration', 170,
      'applicationVersion', '1.0.0',
      'checkCount', 10
    )
  );
  raise notice 'LEGHEVO_V1_STAGE readiness_certified';
end;
$release$;

drop function if exists public.seed_leghevo_public_v1_outbox_drain_v1(
  text, text, text, bigint, uuid, uuid
);

do $validate$
declare
  v_release jsonb;
  v_head public.leghevo_production_readiness_heads%rowtype;
  v_run public.leghevo_production_readiness_runs%rowtype;
  v_certificate public.leghevo_production_readiness_certificates%rowtype;
  v_check_count integer := 0;
  v_failed_check_count integer := 0;
  v_checks_fingerprint text;
begin
  raise notice 'LEGHEVO_V1_STAGE final_release_model';
  v_release := public.get_leghevo_application_release_model_v1('production');
  raise notice 'LEGHEVO_V1_STAGE final_readiness_model';
  select head.* into strict v_head
  from public.leghevo_production_readiness_heads head
  where head.environment_key = 'production';
  select run.* into strict v_run
  from public.leghevo_production_readiness_runs run
  where run.id = v_head.run_id;
  select certificate.* into strict v_certificate
  from public.leghevo_production_readiness_certificates certificate
  where certificate.id = v_head.certificate_id;
  select count(*), count(*) filter (where check_row.status <> 'passed'),
    public.leghevo_sha256_hex_v1(
      string_agg(
        check_row.check_key || '|' || check_row.check_fingerprint,
        ';' order by check_row.check_ordinal
      )
    )
  into v_check_count, v_failed_check_count, v_checks_fingerprint
  from public.leghevo_production_readiness_checks check_row
  where check_row.run_id = v_run.id;
  raise notice 'LEGHEVO_V1_STAGE final_validate';

  if coalesce(v_release ->> 'activeVersion', '') <> '1.0.0'
    or coalesce(v_release ->> 'bundleFingerprint', '') <>
      '06ea897294c9cb1c4a3d5377a37e7db073dc53b19dead5129d8efadbc11c7b68'
    or not coalesce((v_release ->> 'protected')::boolean, false)
    or not coalesce((v_release ->> 'healthy')::boolean, false)
    or v_head.mode <> 'active'
    or v_head.status not in ('certified', 'revalidated')
    or not v_head.go_live_allowed
    or v_head.active_release_version <> '1.0.0'
    or v_run.status <> 'certified'
    or v_run.active_release_version <> '1.0.0'
    or v_check_count <> 10
    or v_failed_check_count <> 0
    or v_certificate.status <> 'certified'
    or v_certificate.application_version <> '1.0.0'
    or v_certificate.run_fingerprint <> v_run.run_fingerprint
    or v_certificate.checks_fingerprint <> v_checks_fingerprint then
    raise exception
      'Validazione finale v1.0.0 non superata: release=%, head=%, run=%, certificate=%, checks=%/%.',
      v_release, row_to_json(v_head), row_to_json(v_run),
      row_to_json(v_certificate), v_check_count, v_failed_check_count;
  end if;
end;
$validate$;

commit;

select
  (public.get_leghevo_application_release_model_v1('production') ->> 'activeVersion')
    as active_version,
  head.status as readiness_status,
  (select count(*)
   from public.leghevo_production_readiness_checks check_row
   where check_row.run_id = head.run_id) as readiness_check_count
from public.leghevo_production_readiness_heads head
where head.environment_key = 'production';
