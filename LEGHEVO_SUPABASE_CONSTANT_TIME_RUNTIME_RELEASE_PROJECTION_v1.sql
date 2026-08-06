-- LEGHEVO v0.62.43 runtime hardening
-- Proiezione di compatibilita client a costo costante.
-- Dipendenza: v0.62.43 validata con production readiness certificata.

begin;

do $preflight$
begin
  if to_regprocedure(
    'public.get_leghevo_client_rollout_eligibility_v9(text,text,uuid)'
  ) is null then
    raise exception 'Preflight runtime projection non superato: endpoint v9 assente.';
  end if;
  if to_regclass('public.leghevo_production_readiness_checks') is null
    or to_regclass('public.leghevo_production_readiness_heads') is null
    or to_regclass('public.leghevo_application_release_heads') is null
    or to_regclass('public.leghevo_application_rollout_heads') is null then
    raise exception 'Preflight runtime projection non superato: catena certificata incompleta.';
  end if;
end;
$preflight$;

-- L'endpoint pubblico non ricostruisce piu il modello di integrita dello schema.
-- Verifica invece le fingerprint immutabili del run/certificato finale e le
-- confronta con le teste operative correnti. La complessita dipende soltanto
-- dai dieci check certificati e dalle teste terminali, non dalla dimensione
-- dello schema o dallo storico applicativo.
create or replace function public.get_leghevo_client_rollout_eligibility_v9(
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
  v_release_head public.leghevo_application_release_heads%rowtype;
  v_active_release public.leghevo_application_release_certificates%rowtype;
  v_client_release public.leghevo_application_release_certificates%rowtype;
  v_rollout_head public.leghevo_application_rollout_heads%rowtype;
  v_rollout_plan public.leghevo_application_rollout_plans%rowtype;
  v_readiness_head public.leghevo_production_readiness_heads%rowtype;
  v_readiness_run public.leghevo_production_readiness_runs%rowtype;
  v_readiness_certificate public.leghevo_production_readiness_certificates%rowtype;
  v_headers jsonb := '{}'::jsonb;
  v_models jsonb := '{}'::jsonb;
  v_outbox jsonb := '{}'::jsonb;
  v_consumer jsonb := '{}'::jsonb;
  v_audit jsonb := '{}'::jsonb;
  v_recovery jsonb := '{}'::jsonb;
  v_backup jsonb := '{}'::jsonb;
  v_service_return jsonb := '{}'::jsonb;
  v_check_count integer := 0;
  v_failed_check_count integer := 0;
  v_invalid_check_count integer := 0;
  v_checks_fingerprint text;
  v_release_contract_stable boolean := false;
  v_rollout_plan_stable boolean := false;
  v_readiness_run_stable boolean := false;
  v_readiness_certificate_stable boolean := false;
  v_readiness_head_stable boolean := false;
  v_certified_chain_stable boolean := false;
  v_live_components_stable boolean := false;
  v_header_consistent boolean := true;
  v_base_compatible boolean := false;
  v_rollout_protected boolean := false;
  v_rollout_eligible boolean := false;
  v_readiness_protected boolean := false;
  v_compatible boolean := false;
  v_reason text := 'production_readiness.not_protected';
  v_client_rank bigint;
  v_active_rank bigint;
  v_rollout_rank bigint;
  v_bucket integer;
  v_current_outbox_sequence bigint := 0;
  v_dead_letter_count bigint := 0;
  v_consumer_count integer := 0;
  v_consumer_affected_count integer := 0;
  v_consumer_min_sequence bigint := 0;
  v_consumer_max_sequence bigint := 0;
  v_audit_count integer := 0;
  v_audit_affected_count integer := 0;
  v_audit_min_sequence bigint := 0;
  v_audit_max_sequence bigint := 0;
  v_telemetry_generation bigint;
  v_telemetry_state text;
  v_telemetry_rollback boolean;
  v_checkpoint_generation bigint;
  v_recovery_status text;
  v_backup_generation bigint;
  v_backup_status text;
  v_service_return_generation bigint;
  v_service_return_mode text;
  v_service_return_status text;
  v_service_return_writes boolean;
  v_service_return_workers boolean;
  v_service_return_traffic integer;
begin
  begin
    v_headers := coalesce(
      nullif(current_setting('request.headers', true), ''),
      '{}'
    )::jsonb;
  exception when others then
    v_headers := '{}'::jsonb;
  end;

  v_header_consistent :=
    (
      nullif(v_headers ->> 'x-leghevo-version', '') is null
      and nullif(v_headers ->> 'x-leghevo-bundle-fingerprint', '') is null
      and nullif(v_headers ->> 'x-leghevo-release-contract', '') is null
    )
    or (
      v_headers ->> 'x-leghevo-version'
        = trim(coalesce(p_application_version, ''))
      and lower(v_headers ->> 'x-leghevo-bundle-fingerprint')
        = lower(trim(coalesce(p_bundle_fingerprint, '')))
      and v_headers ->> 'x-leghevo-release-contract' = '1'
    );

  select head.* into v_release_head
  from public.leghevo_application_release_heads head
  where head.environment_key = 'production';
  if found then
    select certificate.* into v_active_release
    from public.leghevo_application_release_certificates certificate
    where certificate.id = v_release_head.active_release_id;
  end if;

  select certificate.* into v_client_release
  from public.leghevo_application_release_certificates certificate
  where certificate.application_version = trim(coalesce(p_application_version, ''))
    and certificate.bundle_fingerprint = lower(trim(coalesce(p_bundle_fingerprint, '')));

  select head.* into v_rollout_head
  from public.leghevo_application_rollout_heads head
  where head.environment_key = 'production';
  if found then
    select plan.* into v_rollout_plan
    from public.leghevo_application_rollout_plans plan
    where plan.id = v_rollout_head.plan_id;
  end if;

  select head.* into v_readiness_head
  from public.leghevo_production_readiness_heads head
  where head.environment_key = 'production';
  if found then
    select run.* into v_readiness_run
    from public.leghevo_production_readiness_runs run
    where run.id = v_readiness_head.run_id;
    if v_readiness_head.certificate_id is not null then
      select certificate.* into v_readiness_certificate
      from public.leghevo_production_readiness_certificates certificate
      where certificate.id = v_readiness_head.certificate_id;
    end if;
  end if;

  select
    count(*)::integer,
    count(*) filter (where check_row.status <> 'passed')::integer,
    count(*) filter (
      where check_row.check_fingerprint <>
        public.compute_leghevo_production_readiness_check_fingerprint_v1(
          check_row.run_id,
          check_row.check_key,
          check_row.check_ordinal,
          check_row.component_fingerprint,
          check_row.component_sequence,
          check_row.status,
          check_row.details
        )
    )::integer,
    public.leghevo_sha256_hex_v1(
      string_agg(
        check_row.check_key || '|' || check_row.check_fingerprint,
        ';' order by check_row.check_ordinal
      )
    ),
    coalesce(
      jsonb_object_agg(check_row.check_key, check_row.details -> 'model'),
      '{}'::jsonb
    )
  into
    v_check_count,
    v_failed_check_count,
    v_invalid_check_count,
    v_checks_fingerprint,
    v_models
  from public.leghevo_production_readiness_checks check_row
  where check_row.run_id = v_readiness_run.id;

  v_release_contract_stable :=
    v_active_release.id is not null
    and v_active_release.contract_fingerprint =
      public.compute_leghevo_release_contract_fingerprint_v1(
        v_active_release.application_version,
        v_active_release.bundle_fingerprint,
        v_active_release.schema_fingerprint,
        v_active_release.min_supported_client_version,
        v_active_release.max_supported_client_version,
        v_active_release.release_contract_version
      );

  v_rollout_plan_stable :=
    v_rollout_plan.id is not null
    and v_rollout_plan.plan_fingerprint =
      public.compute_leghevo_rollout_plan_fingerprint_v1(
        v_rollout_plan.release_id,
        v_rollout_plan.environment_key,
        v_rollout_plan.initial_percentage,
        v_rollout_plan.max_percentage,
        v_rollout_plan.error_rate_bps_threshold,
        v_rollout_plan.crash_count_threshold,
        v_rollout_plan.min_observations,
        v_rollout_plan.rollout_contract_version
      );

  v_readiness_run_stable :=
    v_readiness_run.id is not null
    and v_readiness_run.run_fingerprint =
      public.compute_leghevo_production_readiness_run_fingerprint_v1(
        v_readiness_run.environment_key,
        v_readiness_run.readiness_generation,
        v_readiness_run.active_release_version,
        v_readiness_run.release_generation,
        v_readiness_run.rollout_generation,
        v_readiness_run.telemetry_generation,
        v_readiness_run.outbox_sequence,
        v_readiness_run.consumer_sequence,
        v_readiness_run.audit_sequence,
        v_readiness_run.checkpoint_generation,
        v_readiness_run.backup_generation,
        v_readiness_run.service_return_generation,
        v_readiness_run.snapshot_fingerprint,
        v_readiness_run.contract_version
      );

  v_readiness_certificate_stable :=
    v_readiness_certificate.id is not null
    and v_readiness_certificate.run_id = v_readiness_run.id
    and v_readiness_certificate.check_count = 10
    and v_readiness_certificate.run_fingerprint = v_readiness_run.run_fingerprint
    and v_readiness_certificate.checks_fingerprint = v_checks_fingerprint
    and v_readiness_certificate.certificate_fingerprint =
      public.compute_leghevo_production_readiness_certificate_fingerprint_v1(
        v_readiness_certificate.run_id,
        v_readiness_certificate.environment_key,
        v_readiness_certificate.readiness_generation,
        v_readiness_certificate.application_version,
        v_readiness_certificate.check_count,
        v_readiness_certificate.run_fingerprint,
        v_readiness_certificate.checks_fingerprint,
        v_readiness_certificate.contract_version
      );

  v_readiness_head_stable :=
    v_readiness_head.environment_key is not null
    and v_readiness_head.state_fingerprint = public.leghevo_sha256_hex_v1(
      v_readiness_head.environment_key || '|' ||
      v_readiness_head.readiness_generation::text || '|' ||
      v_readiness_head.run_id::text || '|' ||
      v_readiness_head.certificate_id::text || '|' ||
      v_readiness_head.mode || '|' ||
      v_readiness_head.revision::text
    );

  v_certified_chain_stable :=
    v_check_count = 10
    and v_failed_check_count = 0
    and v_invalid_check_count = 0
    and v_release_contract_stable
    and v_rollout_plan_stable
    and v_readiness_run_stable
    and v_readiness_certificate_stable
    and v_readiness_head_stable
    and v_release_head.state in ('active', 'rollback')
    and v_rollout_head.state in ('active', 'completed')
    and not coalesce(v_rollout_head.kill_switch_active, true)
    and v_rollout_plan.release_id = v_release_head.active_release_id
    and v_readiness_run.release_generation = v_release_head.generation
    and v_readiness_run.rollout_generation = v_rollout_head.generation
    and v_readiness_run.active_release_version = v_active_release.application_version
    and v_readiness_head.active_release_version = v_active_release.application_version;

  select head.generation, head.state, head.auto_rollback_triggered
  into v_telemetry_generation, v_telemetry_state, v_telemetry_rollback
  from public.leghevo_operational_telemetry_heads head
  where head.environment_key = 'production';

  select coalesce(max(message.stream_sequence), 0)
  into v_current_outbox_sequence
  from public.leghevo_operational_outbox_messages message
  where message.environment_key = 'production';

  select count(*) into v_dead_letter_count
  from public.leghevo_operational_outbox_dead_letters dead_letter
  join public.leghevo_operational_outbox_messages message
    on message.id = dead_letter.message_id
  where message.environment_key = 'production';

  select
    count(*)::integer,
    count(*) filter (where head.state <> 'active')::integer,
    coalesce(min(head.last_stream_sequence), 0),
    coalesce(max(head.last_stream_sequence), 0)
  into
    v_consumer_count,
    v_consumer_affected_count,
    v_consumer_min_sequence,
    v_consumer_max_sequence
  from public.leghevo_operational_consumer_heads head
  where head.environment_key = 'production';

  select
    count(*)::integer,
    count(*) filter (where head.state <> 'certified')::integer,
    coalesce(min(head.audited_through_sequence), 0),
    coalesce(max(head.audited_through_sequence), 0)
  into
    v_audit_count,
    v_audit_affected_count,
    v_audit_min_sequence,
    v_audit_max_sequence
  from public.leghevo_operational_delivery_audit_heads head
  where head.environment_key = 'production';

  select head.checkpoint_generation, head.status
  into v_checkpoint_generation, v_recovery_status
  from public.leghevo_disaster_recovery_heads head
  where head.environment_key = 'production';

  select head.backup_generation, head.status
  into v_backup_generation, v_backup_status
  from public.leghevo_physical_backup_heads head
  where head.environment_key = 'production';

  select
    head.recovery_generation,
    head.mode,
    head.status,
    head.writes_allowed,
    head.workers_allowed,
    head.traffic_percentage
  into
    v_service_return_generation,
    v_service_return_mode,
    v_service_return_status,
    v_service_return_writes,
    v_service_return_workers,
    v_service_return_traffic
  from public.leghevo_service_return_heads head
  where head.environment_key = 'production';

  v_live_components_stable :=
    v_telemetry_generation = v_readiness_run.telemetry_generation
    and v_telemetry_state = 'active'
    and not coalesce(v_telemetry_rollback, true)
    and v_current_outbox_sequence = v_readiness_run.outbox_sequence
    and v_dead_letter_count = 0
    and v_consumer_count > 0
    and v_consumer_affected_count = 0
    and v_consumer_min_sequence = v_readiness_run.consumer_sequence
    and v_consumer_max_sequence = v_readiness_run.consumer_sequence
    and v_audit_count = v_consumer_count
    and v_audit_affected_count = 0
    and v_audit_min_sequence = v_readiness_run.audit_sequence
    and v_audit_max_sequence = v_readiness_run.audit_sequence
    and v_checkpoint_generation = v_readiness_run.checkpoint_generation
    and v_recovery_status in ('certified', 'revalidated')
    and v_backup_generation = v_readiness_run.backup_generation
    and v_backup_status in ('certified', 'revalidated')
    and v_service_return_generation = v_readiness_run.service_return_generation
    and v_service_return_mode = 'active'
    and v_service_return_status in ('certified', 'revalidated')
    and coalesce(v_service_return_writes, false)
    and coalesce(v_service_return_workers, false)
    and coalesce(v_service_return_traffic, 0) = 100;

  v_readiness_protected :=
    v_certified_chain_stable
    and v_live_components_stable
    and v_readiness_head.mode = 'active'
    and v_readiness_head.status in ('certified', 'revalidated')
    and v_readiness_head.go_live_allowed
    and v_readiness_run.status = 'certified'
    and v_readiness_certificate.status = 'certified';

  v_client_rank := public.leghevo_semver_rank_v1(p_application_version);
  v_active_rank := public.leghevo_semver_rank_v1(v_active_release.application_version);
  select public.leghevo_semver_rank_v1(certificate.application_version)
  into v_rollout_rank
  from public.leghevo_application_release_certificates certificate
  where certificate.id = v_rollout_plan.release_id;

  v_base_compatible :=
    v_release_contract_stable
    and v_header_consistent
    and v_client_rank is not null
    and v_active_rank is not null
    and v_client_release.id is not null
    and v_client_release.schema_fingerprint = v_active_release.schema_fingerprint
    and v_client_rank between
      public.leghevo_semver_rank_v1(v_active_release.min_supported_client_version)
      and public.leghevo_semver_rank_v1(v_active_release.max_supported_client_version);

  v_rollout_protected :=
    v_rollout_plan_stable
    and v_rollout_head.state in ('active', 'completed')
    and not coalesce(v_rollout_head.kill_switch_active, true)
    and v_rollout_head.exposure_percentage between 1 and 100;

  if p_installation_id is not null and v_rollout_plan.id is not null then
    v_bucket := (((pg_catalog.hashtextextended(
      p_installation_id::text || ':' || v_rollout_plan.id::text,
      0
    ) % 100) + 100) % 100)::integer;
  end if;

  if not v_base_compatible then
    v_rollout_eligible := false;
  elsif v_rollout_rank is null then
    v_rollout_eligible := false;
  elsif v_client_rank < v_rollout_rank then
    v_rollout_eligible := true;
  elsif v_client_rank > v_rollout_rank then
    v_rollout_eligible := false;
  elsif not v_rollout_protected or v_bucket is null then
    v_rollout_eligible := false;
  else
    v_rollout_eligible := v_bucket < v_rollout_head.exposure_percentage;
  end if;

  v_compatible := v_base_compatible
    and v_rollout_eligible
    and v_readiness_protected;

  v_reason := case
    when not v_release_contract_stable then 'release.model_affected'
    when not v_header_consistent then 'release.request_attestation_mismatch'
    when v_client_rank is null then 'release.client_version_invalid'
    when v_client_release.id is null then 'release.bundle_not_certified'
    when v_client_release.schema_fingerprint <> v_active_release.schema_fingerprint
      then 'release.schema_incompatible'
    when v_client_rank < public.leghevo_semver_rank_v1(
      v_active_release.min_supported_client_version
    ) then 'release.update_required'
    when v_client_rank > public.leghevo_semver_rank_v1(
      v_active_release.max_supported_client_version
    ) then 'release.client_ahead_of_server'
    when not v_certified_chain_stable then 'production_readiness.not_protected'
    when not v_live_components_stable then 'production_readiness.stale'
    when v_readiness_head.mode <> 'active'
      or v_readiness_head.status not in ('certified', 'revalidated')
      or not v_readiness_head.go_live_allowed
      then coalesce(v_readiness_head.reason_code, 'production_readiness.affected')
    when v_rollout_rank is null then 'rollout.contract_missing'
    when v_client_rank > v_rollout_rank then 'rollout.release_ahead_of_plan'
    when not v_rollout_protected then case
      when coalesce(v_rollout_head.kill_switch_active, true)
        then 'rollout.kill_switch_active'
      else coalesce(v_rollout_head.affected_reason, 'rollout.affected')
    end
    when v_bucket is null then 'rollout.installation_identity_missing'
    when not v_rollout_eligible then 'rollout.not_exposed'
    when v_client_rank < v_rollout_rank then 'rollout.previous_release_allowed'
    when v_rollout_head.state = 'completed' then 'rollout.completed'
    else 'rollout.eligible'
  end;

  v_outbox := coalesce(v_models -> 'transactional_outbox', '{}'::jsonb);
  v_consumer := coalesce(v_models -> 'consumer_delivery', '{}'::jsonb);
  v_audit := coalesce(v_models -> 'delivery_audit', '{}'::jsonb);
  v_recovery := coalesce(v_models -> 'disaster_recovery', '{}'::jsonb);
  v_backup := coalesce(v_models -> 'physical_backup', '{}'::jsonb);
  v_service_return := coalesce(v_models -> 'service_return', '{}'::jsonb);

  return jsonb_build_object(
    'compatible', v_compatible,
    'protected', v_readiness_protected,
    'reasonCode', v_reason,
    'applicationVersion', trim(coalesce(p_application_version, '')),
    'activeVersion', v_active_release.application_version,
    'minSupportedVersion', v_active_release.min_supported_client_version,
    'maxSupportedVersion', v_active_release.max_supported_client_version,
    'releaseGeneration', v_release_head.generation,
    'rollbackActive', v_release_head.safe_state = 'rollback',
    'requestAttested', v_header_consistent,
    'rolloutProtected', v_rollout_protected,
    'rolloutEligible', v_rollout_eligible,
    'rolloutStatus', v_rollout_head.state,
    'rolloutStage', v_rollout_head.stage,
    'rolloutExposurePercentage', v_rollout_head.exposure_percentage,
    'rolloutGeneration', v_rollout_head.generation,
    'rolloutBucket', v_bucket,
    'killSwitchActive', coalesce(v_rollout_head.kill_switch_active, true),
    'outboxProtected', coalesce((v_outbox ->> 'protected')::boolean, false),
    'outboxHealthy', coalesce((v_outbox ->> 'healthy')::boolean, false),
    'outboxStatus', v_outbox ->> 'status',
    'outboxPendingCount', coalesce((v_outbox ->> 'pendingCount')::bigint, 0),
    'outboxDeadLetterCount', v_dead_letter_count,
    'consumerDeliveryProtected', coalesce((v_consumer ->> 'protected')::boolean, false),
    'consumerDeliveryHealthy', coalesce((v_consumer ->> 'healthy')::boolean, false),
    'consumerDeliveryStatus', v_consumer ->> 'status',
    'consumerReceiptCount', v_consumer -> 'receiptCount',
    'consumerExpectedReceiptCount', v_consumer -> 'expectedReceiptCount'
  ) || jsonb_build_object(
    'deliveryAuditProtected', coalesce((v_audit ->> 'protected')::boolean, false),
    'deliveryAuditHealthy', coalesce((v_audit ->> 'healthy')::boolean, false),
    'deliveryAuditFresh', v_audit_count > 0 and v_audit_affected_count = 0,
    'deliveryAuditStatus', v_audit ->> 'status',
    'deliveryAuditGeneration', v_audit -> 'auditGeneration',
    'deliveryAuditSequence', v_audit_min_sequence,
    'disasterRecoveryProtected', coalesce((v_recovery ->> 'protected')::boolean, false),
    'disasterRecoveryHealthy', coalesce((v_recovery ->> 'healthy')::boolean, false),
    'disasterRecoveryFresh', v_checkpoint_generation = v_readiness_run.checkpoint_generation,
    'disasterRecoveryStatus', v_recovery_status,
    'disasterRecoveryCheckpointGeneration', v_checkpoint_generation,
    'disasterRecoveryDrillGeneration', v_recovery -> 'drillGeneration',
    'physicalBackupProtected', coalesce((v_backup ->> 'protected')::boolean, false),
    'physicalBackupHealthy', coalesce((v_backup ->> 'healthy')::boolean, false),
    'physicalBackupFresh', v_backup_generation = v_readiness_run.backup_generation,
    'physicalBackupStatus', v_backup_status,
    'physicalBackupGeneration', v_backup_generation,
    'physicalBackupRehearsalGeneration', v_backup -> 'rehearsalGeneration',
    'serviceReturnProtected', coalesce((v_service_return ->> 'protected')::boolean, false),
    'serviceReturnHealthy', coalesce((v_service_return ->> 'healthy')::boolean, false),
    'serviceReturnFresh', v_service_return_generation = v_readiness_run.service_return_generation,
    'serviceReturnStatus', v_service_return_status,
    'serviceReturnMode', v_service_return_mode,
    'serviceReturnGeneration', v_service_return_generation,
    'serviceReturnCheckCount', v_service_return -> 'checkCount',
    'productionReadinessProtected', v_readiness_protected,
    'productionReadinessHealthy', v_readiness_protected,
    'productionReadinessFresh', v_live_components_stable,
    'productionReadinessStatus', case
      when v_readiness_protected then 'certified'
      when v_readiness_head.mode = 'pending' then 'pending'
      else 'affected'
    end,
    'productionReadinessGeneration', v_readiness_head.readiness_generation,
    'productionReadinessCheckCount', v_check_count,
    'productionGoLiveAllowed', v_readiness_protected,
    'checkedAt', now()
  );
end;
$function$;

revoke all on function public.get_leghevo_client_rollout_eligibility_v9(
  text, text, uuid
) from public, anon, authenticated, service_role;
grant execute on function public.get_leghevo_client_rollout_eligibility_v9(
  text, text, uuid
) to anon, authenticated, service_role;
revoke execute on function public.get_leghevo_client_rollout_eligibility_v8(
  text, text, uuid
) from anon, authenticated, service_role;

create or replace function public.get_leghevo_runtime_release_projection_integrity_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_definition text := coalesce(pg_catalog.pg_get_functiondef(
    to_regprocedure('public.get_leghevo_client_rollout_eligibility_v9(text,text,uuid)')
  ), '');
  v_runtime jsonb;
  v_rejected jsonb;
  v_started_at timestamptz;
  v_elapsed_ms numeric;
begin
  v_started_at := clock_timestamp();
  v_runtime := public.get_leghevo_client_rollout_eligibility_v9(
    '0.62.43',
    '9cd8380cc324b6292f0e74fd0b5a727171cacc137462942d6c69149304ca3e5e',
    '00000000-0000-4000-8000-000000000148'::uuid
  );
  v_rejected := public.get_leghevo_client_rollout_eligibility_v9(
    '0.62.43', repeat('0', 64),
    '00000000-0000-4000-8000-000000000148'::uuid
  );
  v_elapsed_ms := extract(epoch from (clock_timestamp() - v_started_at)) * 1000;

  return jsonb_build_object(
    'predecessor_ready',
      to_regclass('public.leghevo_production_readiness_heads') is not null
      and to_regclass('public.leghevo_production_readiness_checks') is not null,
    'endpoint_signature_ready',
      to_regprocedure('public.get_leghevo_client_rollout_eligibility_v9(text,text,uuid)') is not null,
    'security_definer_ready', exists(
      select 1 from pg_catalog.pg_proc procedure_row
      where procedure_row.oid = to_regprocedure(
        'public.get_leghevo_client_rollout_eligibility_v9(text,text,uuid)'
      ) and procedure_row.prosecdef
    ),
    'stable_ready', exists(
      select 1 from pg_catalog.pg_proc procedure_row
      where procedure_row.oid = to_regprocedure(
        'public.get_leghevo_client_rollout_eligibility_v9(text,text,uuid)'
      ) and procedure_row.provolatile = 's'
    ),
    'search_path_ready', exists(
      select 1 from pg_catalog.pg_proc procedure_row
      where procedure_row.oid = to_regprocedure(
        'public.get_leghevo_client_rollout_eligibility_v9(text,text,uuid)'
      ) and procedure_row.proconfig @> array['search_path=""']
    ),
    'anonymous_access_ready', has_function_privilege(
      'anon',
      'public.get_leghevo_client_rollout_eligibility_v9(text,text,uuid)',
      'EXECUTE'
    ),
    'authenticated_access_ready', has_function_privilege(
      'authenticated',
      'public.get_leghevo_client_rollout_eligibility_v9(text,text,uuid)',
      'EXECUTE'
    ),
    'public_access_blocked', not has_function_privilege(
      'public',
      'public.get_leghevo_client_rollout_eligibility_v9(text,text,uuid)',
      'EXECUTE'
    ),
    'legacy_access_blocked',
      not has_function_privilege(
        'anon',
        'public.get_leghevo_client_rollout_eligibility_v8(text,text,uuid)',
        'EXECUTE'
      )
      and not has_function_privilege(
        'authenticated',
        'public.get_leghevo_client_rollout_eligibility_v8(text,text,uuid)',
        'EXECUTE'
      ),
    'constant_time_source_ready',
      position('get_leghevo_client_rollout_eligibility_v8' in v_definition) = 0
      and position('get_leghevo_application_integrity_model_v1' in v_definition) = 0
      and position('get_leghevo_production_readiness_snapshot_v1' in v_definition) = 0,
    'certified_checks_ready',
      position('leghevo_production_readiness_checks' in v_definition) > 0,
    'check_fingerprint_ready',
      position('compute_leghevo_production_readiness_check_fingerprint_v1' in v_definition) > 0,
    'run_fingerprint_ready',
      position('compute_leghevo_production_readiness_run_fingerprint_v1' in v_definition) > 0,
    'certificate_fingerprint_ready',
      position('compute_leghevo_production_readiness_certificate_fingerprint_v1' in v_definition) > 0,
    'head_fingerprint_ready', position('state_fingerprint' in v_definition) > 0,
    'release_fingerprint_ready',
      position('compute_leghevo_release_contract_fingerprint_v1' in v_definition) > 0,
    'rollout_fingerprint_ready',
      position('compute_leghevo_rollout_plan_fingerprint_v1' in v_definition) > 0,
    'request_attestation_ready',
      position('x-leghevo-bundle-fingerprint' in v_definition) > 0,
    'fail_closed_ready',
      coalesce((v_runtime ->> 'compatible')::boolean, false)
      and coalesce((v_runtime ->> 'productionReadinessProtected')::boolean, false)
      and not coalesce((v_rejected ->> 'compatible')::boolean, true)
      and v_rejected ->> 'reasonCode' = 'release.bundle_not_certified',
    'runtime_latency_ready', v_elapsed_ms < 1000
  );
end;
$function$;

revoke all on function public.get_leghevo_runtime_release_projection_integrity_v1()
  from public, anon, authenticated;
grant execute on function public.get_leghevo_runtime_release_projection_integrity_v1()
  to service_role;

do $validate$
declare
  v_integrity jsonb;
  v_false text[];
begin
  v_integrity := public.get_leghevo_runtime_release_projection_integrity_v1();
  select array_agg(item.key order by item.key) into v_false
  from pg_catalog.jsonb_each(v_integrity) item
  where pg_catalog.jsonb_typeof(item.value) is distinct from 'boolean'
     or item.value is distinct from 'true'::jsonb;

  if (select count(*) from pg_catalog.jsonb_each(v_integrity)) <> 20
    or cardinality(v_false) > 0 then
    raise exception 'Validazione runtime projection non superata: %. Dettaglio: %',
      coalesce(array_to_string(v_false, ', '), 'numero controlli diverso da 20'),
      v_integrity;
  end if;
end;
$validate$;

commit;

select public.get_leghevo_runtime_release_projection_integrity_v1();
