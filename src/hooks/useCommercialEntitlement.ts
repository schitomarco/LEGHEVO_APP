import { useCallback, useEffect, useState } from 'react';
import { AppState } from 'react-native';
import {
  DEMO_COMMERCIAL_ENTITLEMENT,
  FREE_COMMERCIAL_ENTITLEMENT,
  loadCommercialEntitlement,
  restorePremiumPurchases,
  startPremiumPurchase,
  type CommercialBillingPeriod,
  type CommercialEntitlement,
} from '../services/subscriptionService';

export function useCommercialEntitlement(
  userId: string | null,
  isDemo: boolean,
) {
  const [entitlement, setEntitlement] = useState<CommercialEntitlement>(
    isDemo ? DEMO_COMMERCIAL_ENTITLEMENT : FREE_COMMERCIAL_ENTITLEMENT,
  );
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');

  const refresh = useCallback(async (silent = false) => {
    if (isDemo) {
      setEntitlement(DEMO_COMMERCIAL_ENTITLEMENT);
      setError('');
      setLoading(false);
      return;
    }

    if (!userId) {
      setEntitlement(FREE_COMMERCIAL_ENTITLEMENT);
      setError('');
      setLoading(false);
      return;
    }

    if (!silent) {
      setLoading(true);
    }
    const outcome = await loadCommercialEntitlement();
    if (outcome.data) {
      setEntitlement(outcome.data);
    }
    setError(outcome.error ?? '');
    setLoading(false);
  }, [isDemo, userId]);

  useEffect(() => {
    void refresh();
  }, [refresh]);

  useEffect(() => {
    if (!userId || isDemo) {
      return;
    }
    const subscription = AppState.addEventListener('change', (state) => {
      if (state === 'active') {
        void refresh(true);
      }
    });
    return () => subscription.remove();
  }, [isDemo, refresh, userId]);

  const purchase = async (period: CommercialBillingPeriod) => {
    const outcome = await startPremiumPurchase(period);
    if (outcome.error) {
      setError(outcome.error);
    }
    return outcome;
  };

  const restore = async () => {
    const outcome = await restorePremiumPurchases();
    if (outcome.error) {
      setError(outcome.error);
    } else {
      await refresh(true);
    }
    return outcome;
  };

  return {
    entitlement,
    loading,
    error,
    refresh,
    purchase,
    restore,
  };
}
