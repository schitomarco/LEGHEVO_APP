import { isBackendConfigured, supabase } from '../lib/supabase';
import {
  APP_BUNDLE_FINGERPRINT,
  APP_RELEASE_VERSION,
} from '../release';
import { getOrCreateInstallationId } from './installationIdentityService';

export type ReleaseCompatibilityStatus =
  | 'compatible'
  | 'incompatible'
  | 'held'
  | 'paused'
  | 'legacy'
  | 'unavailable';

export type ReleaseCompatibility = {
  compatible: boolean;
  enforced: boolean;
  status: ReleaseCompatibilityStatus;
  reasonCode: string;
  applicationVersion: string;
  activeVersion: string | null;
  minSupportedVersion: string | null;
  maxSupportedVersion: string | null;
  releaseGeneration: number | null;
  rollbackActive: boolean;
  rolloutProtected: boolean;
  rolloutEligible: boolean;
  rolloutStatus: string | null;
  rolloutStage: string | null;
  rolloutExposurePercentage: number | null;
  rolloutBucket: number | null;
  killSwitchActive: boolean;
  outboxProtected: boolean;
  outboxHealthy: boolean;
  outboxStatus: string | null;
  outboxPendingCount: number | null;
  outboxDeadLetterCount: number | null;
  consumerDeliveryProtected: boolean;
  consumerDeliveryHealthy: boolean;
  consumerDeliveryStatus: string | null;
  consumerReceiptCount: number | null;
  consumerExpectedReceiptCount: number | null;
  deliveryAuditProtected: boolean;
  deliveryAuditHealthy: boolean;
  deliveryAuditFresh: boolean;
  deliveryAuditStatus: string | null;
  deliveryAuditGeneration: number | null;
  deliveryAuditSequence: number | null;
  disasterRecoveryProtected: boolean;
  disasterRecoveryHealthy: boolean;
  disasterRecoveryFresh: boolean;
  disasterRecoveryStatus: string | null;
  disasterRecoveryCheckpointGeneration: number | null;
  disasterRecoveryDrillGeneration: number | null;
  physicalBackupProtected: boolean;
  physicalBackupHealthy: boolean;
  physicalBackupFresh: boolean;
  physicalBackupStatus: string | null;
  physicalBackupGeneration: number | null;
  physicalBackupRehearsalGeneration: number | null;
  serviceReturnProtected: boolean;
  serviceReturnHealthy: boolean;
  serviceReturnFresh: boolean;
  serviceReturnStatus: string | null;
  serviceReturnMode: string | null;
  serviceReturnGeneration: number | null;
  serviceReturnCheckCount: number | null;
  productionReadinessProtected: boolean;
  productionReadinessHealthy: boolean;
  productionReadinessFresh: boolean;
  productionReadinessStatus: string | null;
  productionReadinessGeneration: number | null;
  productionReadinessCheckCount: number | null;
  productionGoLiveAllowed: boolean;
  checkedAt: string;
};

function asRecord(value: unknown): Record<string, unknown> {
  return value && typeof value === 'object' && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : {};
}

function toNullableString(value: unknown): string | null {
  return typeof value === 'string' && value.length > 0 ? value : null;
}

function toNullableNumber(value: unknown): number | null {
  if (typeof value === 'number' && Number.isFinite(value)) {
    return value;
  }
  if (typeof value === 'string' && value.trim().length > 0) {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : null;
  }
  return null;
}

function isMissingRpc(message: string, functionName: string): boolean {
  const normalized = message.toLowerCase();
  return (
    normalized.includes(functionName.toLowerCase()) &&
    (normalized.includes('does not exist') ||
      normalized.includes('function') ||
      normalized.includes('schema cache') ||
      normalized.includes('could not find'))
  );
}

function localOutcome(
  status: ReleaseCompatibilityStatus,
  reasonCode: string,
  compatible: boolean,
  enforced: boolean,
): ReleaseCompatibility {
  return {
    compatible,
    enforced,
    status,
    reasonCode,
    applicationVersion: APP_RELEASE_VERSION,
    activeVersion: null,
    minSupportedVersion: null,
    maxSupportedVersion: null,
    releaseGeneration: null,
    rollbackActive: false,
    rolloutProtected: false,
    rolloutEligible: true,
    rolloutStatus: null,
    rolloutStage: null,
    rolloutExposurePercentage: null,
    rolloutBucket: null,
    killSwitchActive: false,
    outboxProtected: false,
    outboxHealthy: false,
    outboxStatus: null,
    outboxPendingCount: null,
    outboxDeadLetterCount: null,
    consumerDeliveryProtected: false,
    consumerDeliveryHealthy: false,
    consumerDeliveryStatus: null,
    consumerReceiptCount: null,
    consumerExpectedReceiptCount: null,
    deliveryAuditProtected: false,
    deliveryAuditHealthy: false,
    deliveryAuditFresh: false,
    deliveryAuditStatus: null,
    deliveryAuditGeneration: null,
    deliveryAuditSequence: null,
    disasterRecoveryProtected: false,
    disasterRecoveryHealthy: false,
    disasterRecoveryFresh: false,
    disasterRecoveryStatus: null,
    disasterRecoveryCheckpointGeneration: null,
    disasterRecoveryDrillGeneration: null,
    physicalBackupProtected: false,
    physicalBackupHealthy: false,
    physicalBackupFresh: false,
    physicalBackupStatus: null,
    physicalBackupGeneration: null,
    physicalBackupRehearsalGeneration: null,
    serviceReturnProtected: false,
    serviceReturnHealthy: false,
    serviceReturnFresh: false,
    serviceReturnStatus: null,
    serviceReturnMode: null,
    serviceReturnGeneration: null,
    serviceReturnCheckCount: null,
    productionReadinessProtected: false,
    productionReadinessHealthy: false,
    productionReadinessFresh: false,
    productionReadinessStatus: null,
    productionReadinessGeneration: null,
    productionReadinessCheckCount: null,
    productionGoLiveAllowed: false,
    checkedAt: new Date().toISOString(),
  };
}

function normalizeOutcome(data: unknown, rolloutContract: boolean) {
  const raw = asRecord(data);
  const compatibilityReady = Boolean(raw.compatible);
  const rolloutEligible = rolloutContract
    ? Boolean(raw.rolloutEligible)
    : true;
  const compatible = compatibilityReady && rolloutEligible;
  const reasonCode =
    typeof raw.reasonCode === 'string'
      ? raw.reasonCode
      : compatible
        ? 'release.compatible'
        : 'release.incompatible';
  const status: ReleaseCompatibilityStatus = compatible
    ? 'compatible'
    : reasonCode === 'rollout.kill_switch_active' ||
        reasonCode === 'rollout.paused' ||
        reasonCode === 'rollout.affected' ||
        reasonCode === 'telemetry.degraded_pause' ||
        reasonCode === 'telemetry.critical_auto_rollback' ||
        reasonCode === 'telemetry.critical_kill_switch' ||
        reasonCode === 'telemetry.affected' ||
        reasonCode === 'outbox.dead_letter_present' ||
        reasonCode === 'outbox.capture_not_protected' ||
        reasonCode === 'outbox.message_fingerprint_changed' ||
        reasonCode === 'outbox.sequence_gap' ||
        reasonCode === 'outbox.delivery_consistency_mismatch' ||
        reasonCode === 'consumer_delivery.receipt_missing' ||
        reasonCode === 'consumer_delivery.sequence_gap' ||
        reasonCode === 'consumer_delivery.receipt_fingerprint_changed' ||
        reasonCode === 'consumer_delivery.receipt_consistency_mismatch' ||
        reasonCode === 'consumer_delivery.consumer_not_authoritative' ||
        reasonCode === 'delivery_audit.not_protected' ||
        reasonCode === 'delivery_audit.new_events_not_attested' ||
        reasonCode === 'delivery_audit.fingerprint_mismatch' ||
        reasonCode === 'delivery_audit.sequence_gap' ||
        reasonCode === 'delivery_audit.delivery_consistency_mismatch' ||
        reasonCode === 'disaster_recovery.not_protected' ||
        reasonCode === 'disaster_recovery.stale' ||
        reasonCode === 'disaster_recovery.affected' ||
        reasonCode === 'disaster_recovery.drill_failed' ||
        reasonCode === 'physical_backup.not_protected' ||
        reasonCode === 'physical_backup.stale' ||
        reasonCode === 'physical_backup.affected' ||
        reasonCode === 'physical_backup.rehearsal_failed' ||
        reasonCode === 'service_return.not_protected' ||
        reasonCode === 'service_return.recovery_mode' ||
        reasonCode === 'service_return.affected' ||
        reasonCode === 'service_return.stale' ||
        reasonCode === 'production_readiness.not_protected' ||
        reasonCode === 'production_readiness.pending' ||
        reasonCode === 'production_readiness.affected' ||
        reasonCode === 'production_readiness.stale'
      ? 'paused'
      : reasonCode === 'rollout.not_exposed'
        ? 'held'
        : 'incompatible';

  return {
    compatible,
    enforced: true,
    status,
    reasonCode,
    applicationVersion: APP_RELEASE_VERSION,
    activeVersion: toNullableString(raw.activeVersion),
    minSupportedVersion: toNullableString(raw.minSupportedVersion),
    maxSupportedVersion: toNullableString(raw.maxSupportedVersion),
    releaseGeneration: toNullableNumber(raw.releaseGeneration),
    rollbackActive: Boolean(raw.rollbackActive),
    rolloutProtected: Boolean(raw.rolloutProtected),
    rolloutEligible,
    rolloutStatus: toNullableString(raw.rolloutStatus),
    rolloutStage: toNullableString(raw.rolloutStage),
    rolloutExposurePercentage: toNullableNumber(raw.rolloutExposurePercentage),
    rolloutBucket: toNullableNumber(raw.rolloutBucket),
    killSwitchActive: Boolean(raw.killSwitchActive),
    outboxProtected: Boolean(raw.outboxProtected),
    outboxHealthy: Boolean(raw.outboxHealthy),
    outboxStatus: toNullableString(raw.outboxStatus),
    outboxPendingCount: toNullableNumber(raw.outboxPendingCount),
    outboxDeadLetterCount: toNullableNumber(raw.outboxDeadLetterCount),
    consumerDeliveryProtected: Boolean(raw.consumerDeliveryProtected),
    consumerDeliveryHealthy: Boolean(raw.consumerDeliveryHealthy),
    consumerDeliveryStatus: toNullableString(raw.consumerDeliveryStatus),
    consumerReceiptCount: toNullableNumber(raw.consumerReceiptCount),
    consumerExpectedReceiptCount: toNullableNumber(
      raw.consumerExpectedReceiptCount,
    ),
    deliveryAuditProtected: Boolean(raw.deliveryAuditProtected),
    deliveryAuditHealthy: Boolean(raw.deliveryAuditHealthy),
    deliveryAuditFresh: Boolean(raw.deliveryAuditFresh),
    deliveryAuditStatus: toNullableString(raw.deliveryAuditStatus),
    deliveryAuditGeneration: toNullableNumber(raw.deliveryAuditGeneration),
    deliveryAuditSequence: toNullableNumber(raw.deliveryAuditSequence),
    disasterRecoveryProtected: Boolean(raw.disasterRecoveryProtected),
    disasterRecoveryHealthy: Boolean(raw.disasterRecoveryHealthy),
    disasterRecoveryFresh: Boolean(raw.disasterRecoveryFresh),
    disasterRecoveryStatus: toNullableString(raw.disasterRecoveryStatus),
    disasterRecoveryCheckpointGeneration: toNullableNumber(
      raw.disasterRecoveryCheckpointGeneration,
    ),
    disasterRecoveryDrillGeneration: toNullableNumber(
      raw.disasterRecoveryDrillGeneration,
    ),
    physicalBackupProtected: Boolean(raw.physicalBackupProtected),
    physicalBackupHealthy: Boolean(raw.physicalBackupHealthy),
    physicalBackupFresh: Boolean(raw.physicalBackupFresh),
    physicalBackupStatus: toNullableString(raw.physicalBackupStatus),
    physicalBackupGeneration: toNullableNumber(raw.physicalBackupGeneration),
    physicalBackupRehearsalGeneration: toNullableNumber(
      raw.physicalBackupRehearsalGeneration,
    ),
    serviceReturnProtected: Boolean(raw.serviceReturnProtected),
    serviceReturnHealthy: Boolean(raw.serviceReturnHealthy),
    serviceReturnFresh: Boolean(raw.serviceReturnFresh),
    serviceReturnStatus: toNullableString(raw.serviceReturnStatus),
    serviceReturnMode: toNullableString(raw.serviceReturnMode),
    serviceReturnGeneration: toNullableNumber(raw.serviceReturnGeneration),
    serviceReturnCheckCount: toNullableNumber(raw.serviceReturnCheckCount),
    productionReadinessProtected: Boolean(raw.productionReadinessProtected),
    productionReadinessHealthy: Boolean(raw.productionReadinessHealthy),
    productionReadinessFresh: Boolean(raw.productionReadinessFresh),
    productionReadinessStatus: toNullableString(raw.productionReadinessStatus),
    productionReadinessGeneration: toNullableNumber(raw.productionReadinessGeneration),
    productionReadinessCheckCount: toNullableNumber(raw.productionReadinessCheckCount),
    productionGoLiveAllowed: Boolean(raw.productionGoLiveAllowed),
    checkedAt: toNullableString(raw.checkedAt) ?? new Date().toISOString(),
  } satisfies ReleaseCompatibility;
}

export async function fetchReleaseCompatibility(): Promise<ReleaseCompatibility> {
  if (!isBackendConfigured || !supabase) {
    return localOutcome(
      'legacy',
      'release.backend_not_configured',
      true,
      false,
    );
  }

  try {
    const installationId = await getOrCreateInstallationId();
    const productionReadinessResponse = await supabase.rpc(
      'get_leghevo_client_rollout_eligibility_v9',
      {
        p_application_version: APP_RELEASE_VERSION,
        p_bundle_fingerprint: APP_BUNDLE_FINGERPRINT,
        p_installation_id: installationId,
      },
    );

    if (!productionReadinessResponse.error) {
      return normalizeOutcome(productionReadinessResponse.data, true);
    }
    if (!isMissingRpc(
      productionReadinessResponse.error.message,
      'get_leghevo_client_rollout_eligibility_v9',
    )) {
      return localOutcome(
        'unavailable',
        'production_readiness.eligibility_unavailable',
        false,
        true,
      );
    }

    const serviceReturnResponse = await supabase.rpc(
      'get_leghevo_client_rollout_eligibility_v8',
      {
        p_application_version: APP_RELEASE_VERSION,
        p_bundle_fingerprint: APP_BUNDLE_FINGERPRINT,
        p_installation_id: installationId,
      },
    );

    if (!serviceReturnResponse.error) {
      return normalizeOutcome(serviceReturnResponse.data, true);
    }
    if (!isMissingRpc(
      serviceReturnResponse.error.message,
      'get_leghevo_client_rollout_eligibility_v8',
    )) {
      return localOutcome(
        'unavailable',
        'service_return.eligibility_unavailable',
        false,
        true,
      );
    }

    const physicalBackupResponse = await supabase.rpc(
      'get_leghevo_client_rollout_eligibility_v7',
      {
        p_application_version: APP_RELEASE_VERSION,
        p_bundle_fingerprint: APP_BUNDLE_FINGERPRINT,
        p_installation_id: installationId,
      },
    );

    if (!physicalBackupResponse.error) {
      return normalizeOutcome(physicalBackupResponse.data, true);
    }
    if (!isMissingRpc(
      physicalBackupResponse.error.message,
      'get_leghevo_client_rollout_eligibility_v7',
    )) {
      return localOutcome(
        'unavailable',
        'physical_backup.eligibility_unavailable',
        false,
        true,
      );
    }

    const disasterRecoveryResponse = await supabase.rpc(
      'get_leghevo_client_rollout_eligibility_v6',
      {
        p_application_version: APP_RELEASE_VERSION,
        p_bundle_fingerprint: APP_BUNDLE_FINGERPRINT,
        p_installation_id: installationId,
      },
    );

    if (!disasterRecoveryResponse.error) {
      return normalizeOutcome(disasterRecoveryResponse.data, true);
    }
    if (!isMissingRpc(
      disasterRecoveryResponse.error.message,
      'get_leghevo_client_rollout_eligibility_v6',
    )) {
      return localOutcome(
        'unavailable',
        'disaster_recovery.eligibility_unavailable',
        false,
        true,
      );
    }

    const deliveryAuditResponse = await supabase.rpc(
      'get_leghevo_client_rollout_eligibility_v5',
      {
        p_application_version: APP_RELEASE_VERSION,
        p_bundle_fingerprint: APP_BUNDLE_FINGERPRINT,
        p_installation_id: installationId,
      },
    );

    if (!deliveryAuditResponse.error) {
      return normalizeOutcome(deliveryAuditResponse.data, true);
    }
    if (!isMissingRpc(
      deliveryAuditResponse.error.message,
      'get_leghevo_client_rollout_eligibility_v5',
    )) {
      return localOutcome(
        'unavailable',
        'delivery_audit.eligibility_unavailable',
        false,
        true,
      );
    }

    const consumerDeliveryResponse = await supabase.rpc(
      'get_leghevo_client_rollout_eligibility_v4',
      {
        p_application_version: APP_RELEASE_VERSION,
        p_bundle_fingerprint: APP_BUNDLE_FINGERPRINT,
        p_installation_id: installationId,
      },
    );

    if (!consumerDeliveryResponse.error) {
      return normalizeOutcome(consumerDeliveryResponse.data, true);
    }
    if (!isMissingRpc(
      consumerDeliveryResponse.error.message,
      'get_leghevo_client_rollout_eligibility_v4',
    )) {
      return localOutcome(
        'unavailable',
        'consumer_delivery.eligibility_unavailable',
        false,
        true,
      );
    }

    const outboxResponse = await supabase.rpc(
      'get_leghevo_client_rollout_eligibility_v3',
      {
        p_application_version: APP_RELEASE_VERSION,
        p_bundle_fingerprint: APP_BUNDLE_FINGERPRINT,
        p_installation_id: installationId,
      },
    );

    if (!outboxResponse.error) {
      return normalizeOutcome(outboxResponse.data, true);
    }
    if (!isMissingRpc(
      outboxResponse.error.message,
      'get_leghevo_client_rollout_eligibility_v3',
    )) {
      return localOutcome(
        'unavailable',
        'outbox.eligibility_unavailable',
        false,
        true,
      );
    }

    const telemetryResponse = await supabase.rpc(
      'get_leghevo_client_rollout_eligibility_v2',
      {
        p_application_version: APP_RELEASE_VERSION,
        p_bundle_fingerprint: APP_BUNDLE_FINGERPRINT,
        p_installation_id: installationId,
      },
    );

    if (!telemetryResponse.error) {
      return normalizeOutcome(telemetryResponse.data, true);
    }
    if (!isMissingRpc(
      telemetryResponse.error.message,
      'get_leghevo_client_rollout_eligibility_v2',
    )) {
      return localOutcome(
        'unavailable',
        'telemetry.eligibility_unavailable',
        false,
        true,
      );
    }

    const rolloutResponse = await supabase.rpc(
      'get_leghevo_client_rollout_eligibility_v1',
      {
        p_application_version: APP_RELEASE_VERSION,
        p_bundle_fingerprint: APP_BUNDLE_FINGERPRINT,
        p_installation_id: installationId,
      },
    );

    if (!rolloutResponse.error) {
      return normalizeOutcome(rolloutResponse.data, true);
    }
    if (!isMissingRpc(
      rolloutResponse.error.message,
      'get_leghevo_client_rollout_eligibility_v1',
    )) {
      return localOutcome(
        'unavailable',
        'rollout.eligibility_unavailable',
        false,
        true,
      );
    }

    const response = await supabase.rpc(
      'get_leghevo_client_compatibility_v1',
      {
        p_application_version: APP_RELEASE_VERSION,
        p_bundle_fingerprint: APP_BUNDLE_FINGERPRINT,
      },
    );
    if (response.error) {
      if (isMissingRpc(
        response.error.message,
        'get_leghevo_client_compatibility_v1',
      )) {
        return localOutcome(
          'legacy',
          'release.contract_not_installed',
          true,
          false,
        );
      }
      return localOutcome(
        'unavailable',
        'release.compatibility_unavailable',
        false,
        true,
      );
    }
    return normalizeOutcome(response.data, false);
  } catch {
    return localOutcome(
      'unavailable',
      'release.compatibility_unavailable',
      false,
      true,
    );
  }
}
