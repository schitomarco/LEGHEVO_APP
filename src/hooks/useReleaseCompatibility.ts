import { useCallback, useEffect, useState } from 'react';
import { AppState } from 'react-native';
import {
  fetchReleaseCompatibility,
  type ReleaseCompatibility,
} from '../services/releaseCompatibilityService';
import { APP_RELEASE_VERSION } from '../release';

type State = ReleaseCompatibility & {
  loading: boolean;
};

const initialState: State = {
  compatible: true,
  enforced: false,
  status: 'legacy',
  reasonCode: 'release.not_checked',
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
  checkedAt: new Date(0).toISOString(),
  loading: true,
};

export function useReleaseCompatibility() {
  const [state, setState] = useState<State>(initialState);

  const refresh = useCallback(async (showLoader = true) => {
    if (showLoader) {
      setState((current) => ({ ...current, loading: true }));
    }
    const outcome = await fetchReleaseCompatibility();
    setState({ ...outcome, loading: false });
  }, []);

  useEffect(() => {
    void refresh();
    const interval = setInterval(() => void refresh(false), 60_000);
    const appStateSubscription = AppState.addEventListener(
      'change',
      (nextState: string) => {
        if (nextState === 'active') {
          void refresh(false);
        }
      },
    );

    return () => {
      clearInterval(interval);
      appStateSubscription.remove();
    };
  }, [refresh]);

  return { ...state, refresh };
}
