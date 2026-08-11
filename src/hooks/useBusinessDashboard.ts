import { useCallback, useEffect, useState } from 'react';
import {
  fetchBusinessDashboard,
  fetchBusinessDashboardAccess,
  type BusinessDashboard,
} from '../services/businessDashboardService';

export function useBusinessDashboardAccess(
  userId: string | null,
  isDemo: boolean,
) {
  const [allowed, setAllowed] = useState(false);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    let active = true;
    if (!userId || isDemo) {
      setAllowed(false);
      setLoading(false);
      return () => {
        active = false;
      };
    }
    setLoading(true);
    void fetchBusinessDashboardAccess().then((access) => {
      if (active) {
        setAllowed(access);
        setLoading(false);
      }
    });
    return () => {
      active = false;
    };
  }, [isDemo, userId]);

  return { allowed, loading };
}

export function useBusinessDashboard(enabled: boolean) {
  const [data, setData] = useState<BusinessDashboard | null>(null);
  const [loading, setLoading] = useState(enabled);
  const [error, setError] = useState('');

  const refresh = useCallback(async () => {
    if (!enabled) {
      setData(null);
      setError('');
      setLoading(false);
      return;
    }
    setLoading(true);
    setError('');
    try {
      setData(await fetchBusinessDashboard());
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : 'Dati non disponibili.');
    } finally {
      setLoading(false);
    }
  }, [enabled]);

  useEffect(() => {
    void refresh();
  }, [refresh]);

  return { data, loading, error, refresh };
}
