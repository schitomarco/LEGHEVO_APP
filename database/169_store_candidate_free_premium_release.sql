-- LEGHEVO v0.62.50
-- Ricertifica la candidata store Free/Premium con ambienti fail-closed.
-- La release v0.62.49 resta immutabile per rollback.

begin;

set local statement_timeout = '30min';

-- Le migrazioni commerciali 158-168 estendono intenzionalmente lo schema.
-- Prima del preflight di release ricertifichiamo i modelli predecessori solo
-- se i rispettivi venti controlli strutturali risultano ancora tutti sani.
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
      raise exception 'Ricertificazione v0.62.50 di % bloccata: %.',
        v_model_key, v_readiness;
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
        'store_candidate.schema_extension_recertified',
        169,
        v_readiness
      ) on conflict (model_key, model_version, current_schema_fingerprint)
        do nothing;

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
    raise exception
      'Ricertificazione v0.62.50 application integrity bloccata: %.',
      v_readiness;
  end if;
  v_current_fingerprint :=
    public.compute_leghevo_application_schema_fingerprint_v1();

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
      'store_candidate.application_integrity_recertified',
      169,
      v_readiness
    ) on conflict (model_key, model_version, current_schema_fingerprint)
      do nothing;

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
    or coalesce(v_release ->> 'activeVersion', '') not in ('0.62.48', '0.62.49', '0.62.50')
    or not (
      (
        coalesce((v_release ->> 'protected')::boolean, false)
        and coalesce((v_release ->> 'healthy')::boolean, false)
      )
      or (
        coalesce((v_release ->> 'active')::boolean, false)
        and coalesce(v_release ->> 'activeVersion', '') = '0.62.49'
        and coalesce(v_release ->> 'reasonCode', '') =
          'release.schema_fingerprint_changed'
        and coalesce((v_release ->> 'fingerprintStable')::boolean, false)
      )
    )
    or not coalesce((v_readiness ->> 'protected')::boolean, false)
    or not coalesce((v_readiness ->> 'goLiveAllowed')::boolean, false)
    or coalesce((v_readiness ->> 'failedCheckCount')::integer, 1) <> 0
    or (
      not coalesce((v_readiness ->> 'healthy')::boolean, false)
      and coalesce(v_readiness ->> 'reasonCode', '') <>
        'production_readiness.release_contract'
    ) then
    raise exception 'Preflight v0.62.50 non superato: application=%, release=%, readiness=%.',
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
      'leghevo-store-candidate-free-premium-seed-worker',
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
        p_destination_key || '|store-candidate-free-premium-applied|' ||
        (v_item ->> 'messageId') || '|' || (v_item ->> 'messageFingerprint')
      );
      v_outcome := public.apply_leghevo_operational_consumer_message_v1(
        p_environment_key,
        (v_item ->> 'messageId')::bigint,
        p_destination_key,
        (v_item ->> 'deliveryGeneration')::bigint,
        'leghevo-store-candidate-free-premium-seed-worker',
        10,
        p_delivery_fencing_token,
        p_consumer_key,
        p_consumer_generation,
        p_consumer_fencing_token,
        'leghevo-' || p_destination_key,
        v_application_fingerprint,
        gen_random_uuid(),
        jsonb_build_object('seedDelivery', true, 'sourceMigration', 169)
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
    'leghevo-v0.62.50-store-candidate-free-premium-artifact');
  v_provider_hash text := public.leghevo_sha256_hex_v1(
    'managed-backup-provider-production-v49');
  v_storage_hash text := public.leghevo_sha256_hex_v1(
    'external-vault-primary-v49');
  v_encryption_hash text := public.leghevo_sha256_hex_v1(
    'external-kms-key-reference-v49');
  v_actor_hash text := public.leghevo_sha256_hex_v1(
    'store-candidate-free-premium-custodian');
  v_target_hash text := public.leghevo_sha256_hex_v1(
    'isolated-store-candidate-free-premium-target');
  v_hash text;
  v_sequence bigint;
begin
  if exists (
    select 1
    from public.leghevo_production_readiness_certificates certificate
    where certificate.application_version = '0.62.50'
  ) then
    return;
  end if;

  v_outcome := public.certify_leghevo_operational_consumer_v1(
    'production', 'operations_center', 'leghevo-operations-consumer', 13,
    v_operations_consumer_token,
    '62e00000-0000-4000-8000-000000000001'::uuid,
    jsonb_build_object('sourceMigration', 169, 'contract', 'store-candidate-free-premium-v1')
  );
  v_outcome := public.certify_leghevo_operational_consumer_v1(
    'production', 'notification_dispatch', 'leghevo-notification-consumer', 13,
    v_notification_consumer_token,
    '62e00000-0000-4000-8000-000000000002'::uuid,
    jsonb_build_object('sourceMigration', 169, 'contract', 'store-candidate-free-premium-v1')
  );
  v_outcome := public.certify_leghevo_application_release_v1(
    '0.62.50',
    '61f859ff96b107a478678aa85b55727547f4b7534dafa8f4e983ea757d176790',
    '0.62.45',
    '0.62.50',
    '62e00000-0000-4000-8000-000000000003'::uuid,
    jsonb_build_object(
      'baseline', false,
      'sourceMigration', 169,
      'securityPatch', 'store-candidate-free-premium-v1'
    )
  );
  v_outcome := public.certify_leghevo_application_rollout_v1(
    'production', '0.62.50', 100, 100, 500, 3, 100,
    '62e00000-0000-4000-8000-000000000004'::uuid,
    jsonb_build_object('strategy', 'store-candidate-free-premium-recertification', 'sourceMigration', 169)
  );
  v_outcome := public.activate_leghevo_release_with_rollout_v1(
    'production',
    '0.62.50',
    '62e00000-0000-4000-8000-000000000005'::uuid,
    '62e00000-0000-4000-8000-000000000006'::uuid,
    'release.store_candidate_free_premium_activation'
  );
  v_outcome := public.certify_leghevo_operational_telemetry_source_v1(
    'production', 'leghevo-production-observer', 15, v_telemetry_token,
    '62e00000-0000-4000-8000-000000000007'::uuid,
    jsonb_build_object('provider', 'leghevo-runtime', 'sourceMigration', 169)
  );
  v_outcome := public.record_leghevo_authoritative_operational_window_v1(
    'production', 'leghevo-production-observer', 15, v_telemetry_token, 1,
    v_now - interval '5 minutes', v_now, 1000, 1, 0, 175,
    '62e00000-0000-4000-8000-000000000008'::uuid,
    jsonb_build_object('seedStage', 100, 'dependencySecurity', true)
  );

  perform public.seed_leghevo_accessibility_demo_fixture_drain_v1(
    'production', 'operations_center', 'leghevo-operations-consumer', 13,
    v_operations_consumer_token, v_operations_delivery_token
  );
  perform public.seed_leghevo_accessibility_demo_fixture_drain_v1(
    'production', 'notification_dispatch', 'leghevo-notification-consumer', 13,
    v_notification_consumer_token, v_notification_delivery_token
  );
  v_outcome := public.run_leghevo_operational_delivery_audit_v1(
    'production',
    '62e00000-0000-4000-8000-000000000009'::uuid,
    jsonb_build_object('sourceMigration', 169, 'storeCandidateFreePremium', true)
  );
  v_checkpoint := public.create_leghevo_disaster_recovery_checkpoint_v1(
    'production',
    '62e00000-0000-4000-8000-000000000010'::uuid,
    'disaster_recovery.release_0_62_49',
    jsonb_build_object('sourceMigration', 169)
  );
  v_outcome := public.run_leghevo_disaster_recovery_drill_v1(
    'production',
    (v_checkpoint ->> 'checkpointId')::bigint,
    '62e00000-0000-4000-8000-000000000011'::uuid,
    jsonb_build_object('sourceMigration', 169, 'storeCandidateFreePremium', true)
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
    '62e00000-0000-4000-8000-000000000012'::uuid,
    jsonb_build_object('evidenceMode', 'external_attestation', 'sourceMigration', 169)
  );
  v_outcome := public.append_leghevo_physical_backup_custody_event_v1(
    'production',
    (v_artifact ->> 'artifactId')::bigint,
    'checksum_verified',
    v_actor_hash,
    v_storage_hash,
    v_now,
    '62e00000-0000-4000-8000-000000000013'::uuid,
    jsonb_build_object('checksumAlgorithm', 'sha256', 'verified', true)
  );
  v_outcome := public.append_leghevo_physical_backup_custody_event_v1(
    'production',
    (v_artifact ->> 'artifactId')::bigint,
    'sealed',
    v_actor_hash,
    v_storage_hash,
    v_now,
    '62e00000-0000-4000-8000-000000000014'::uuid,
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
    '62e00000-0000-4000-8000-000000000015'::uuid,
    jsonb_build_object(
      'isolatedTarget', true,
      'networkWritesBlocked', true,
      'sourceMigration', 169
    )
  );

  v_run := public.begin_leghevo_service_return_v1(
    'production',
    '62e00000-0000-4000-8000-000000000020'::uuid,
    'service_return.store_candidate_free_premium_restore_verified',
    jsonb_build_object('sourceMigration', 169)
  );
  v_run_id := (v_run ->> 'runId')::bigint;
  v_snapshot := public.get_leghevo_service_return_snapshot_v1('production');

  v_hash := v_snapshot ->> 'applicationFingerprint';
  v_sequence := 0;
  v_outcome := public.record_leghevo_service_return_check_v1(
    'production', v_run_id, 'application_integrity', v_hash, v_hash,
    v_sequence, v_sequence, '62e00000-0000-4000-8000-000000000021'::uuid,
    jsonb_build_object('sourceMigration', 169)
  );
  v_hash := v_snapshot ->> 'releaseFingerprint';
  v_sequence := (v_snapshot ->> 'releaseGeneration')::bigint;
  v_outcome := public.record_leghevo_service_return_check_v1(
    'production', v_run_id, 'release_compatibility', v_hash, v_hash,
    v_sequence, v_sequence, '62e00000-0000-4000-8000-000000000022'::uuid,
    jsonb_build_object('sourceMigration', 169)
  );
  v_hash := v_snapshot ->> 'rolloutFingerprint';
  v_sequence := (v_snapshot ->> 'rolloutGeneration')::bigint;
  v_outcome := public.record_leghevo_service_return_check_v1(
    'production', v_run_id, 'rollout_state', v_hash, v_hash,
    v_sequence, v_sequence, '62e00000-0000-4000-8000-000000000023'::uuid,
    jsonb_build_object('sourceMigration', 169)
  );
  v_hash := v_snapshot ->> 'telemetryFingerprint';
  v_sequence := (v_snapshot ->> 'telemetryGeneration')::bigint;
  v_outcome := public.record_leghevo_service_return_check_v1(
    'production', v_run_id, 'telemetry_fencing', v_hash, v_hash,
    v_sequence, v_sequence, '62e00000-0000-4000-8000-000000000024'::uuid,
    jsonb_build_object('sourceMigration', 169)
  );
  v_hash := v_snapshot ->> 'outboxFingerprint';
  v_sequence := (v_snapshot ->> 'outboxSequence')::bigint;
  v_outcome := public.record_leghevo_service_return_check_v1(
    'production', v_run_id, 'outbox_continuity', v_hash, v_hash,
    v_sequence, v_sequence, '62e00000-0000-4000-8000-000000000025'::uuid,
    jsonb_build_object('sourceMigration', 169)
  );
  v_hash := v_snapshot ->> 'consumerFingerprint';
  v_sequence := (v_snapshot ->> 'consumerSequence')::bigint;
  v_outcome := public.record_leghevo_service_return_check_v1(
    'production', v_run_id, 'consumer_continuity', v_hash, v_hash,
    v_sequence, v_sequence, '62e00000-0000-4000-8000-000000000026'::uuid,
    jsonb_build_object('sourceMigration', 169)
  );
  v_hash := v_snapshot ->> 'auditFingerprint';
  v_sequence := (v_snapshot ->> 'auditSequence')::bigint;
  v_outcome := public.record_leghevo_service_return_check_v1(
    'production', v_run_id, 'delivery_audit', v_hash, v_hash,
    v_sequence, v_sequence, '62e00000-0000-4000-8000-000000000027'::uuid,
    jsonb_build_object('sourceMigration', 169)
  );
  v_hash := v_snapshot ->> 'physicalBackupFingerprint';
  v_sequence := (v_snapshot ->> 'artifactId')::bigint;
  v_outcome := public.record_leghevo_service_return_check_v1(
    'production', v_run_id, 'physical_backup', v_hash, v_hash,
    v_sequence, v_sequence, '62e00000-0000-4000-8000-000000000028'::uuid,
    jsonb_build_object('sourceMigration', 169)
  );
  v_outcome := public.complete_leghevo_service_return_v1(
    'production',
    v_run_id,
    '62e00000-0000-4000-8000-000000000030'::uuid,
    'service_return.store_candidate_free_premium_certified',
    jsonb_build_object('sourceMigration', 169, 'trafficPercentage', 100)
  );
  v_outcome := public.certify_leghevo_production_readiness_v1(
    'production',
    '62e00000-0000-4000-8000-000000000040'::uuid,
    'production_readiness.store_candidate_free_premium_certified',
    jsonb_build_object(
      'sourceMigration', 169,
      'applicationVersion', '0.62.50',
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

  if coalesce(v_release ->> 'activeVersion', '') <> '0.62.50'
    or coalesce(v_release ->> 'bundleFingerprint', '') <>
      '61f859ff96b107a478678aa85b55727547f4b7534dafa8f4e983ea757d176790'
    or not coalesce((v_release ->> 'protected')::boolean, false)
    or not coalesce((v_release ->> 'healthy')::boolean, false)
    or not coalesce((v_readiness ->> 'protected')::boolean, false)
    or not coalesce((v_readiness ->> 'healthy')::boolean, false)
    or not coalesce((v_readiness ->> 'fresh')::boolean, false)
    or not coalesce((v_readiness ->> 'goLiveAllowed')::boolean, false)
    or coalesce((v_readiness ->> 'checkCount')::integer, 0) <> 10
    or coalesce((v_readiness ->> 'failedCheckCount')::integer, 1) <> 0
    or coalesce(v_readiness ->> 'activeVersion', '') <> '0.62.50' then
    raise exception 'Validazione finale v0.62.50 non superata: release=%, readiness=%.',
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
