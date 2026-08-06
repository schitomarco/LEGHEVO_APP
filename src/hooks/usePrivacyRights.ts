import { useCallback, useEffect, useState } from 'react';
import {
  cancelPrivacyRightsRequest,
  fetchPrivacyRightsCenter,
  submitPrivacyRightsRequest,
  subscribeToPrivacyRightsCenter,
  type PrivacyRightType,
  type PrivacyRightsCenter,
} from '../services/privacyRightsService';

function createDemoPrivacyRightsCenter(): PrivacyRightsCenter {
  return {
    generatedAt: new Date().toISOString(),
    openCount: 0,
    totalCount: 0,
    protection: {
      guardedActionsReady: true,
      revisionControlReady: true,
      idempotencyReady: true,
    },
    requests: [],
  };
}

export function usePrivacyRights(isDemo: boolean, userId: string) {
  const [center, setCenter] = useState<PrivacyRightsCenter | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [actionLoading, setActionLoading] = useState(false);
  const [actionError, setActionError] = useState('');
  const [notice, setNotice] = useState('');

  const refresh = useCallback(
    async (quiet = false) => {
      if (isDemo) {
        setCenter(createDemoPrivacyRightsCenter());
        setError('');
        setLoading(false);
        return;
      }

      if (!quiet) {
        setLoading(true);
      }
      try {
        setCenter(await fetchPrivacyRightsCenter());
        setError('');
      } catch (cause) {
        setError(
          cause instanceof Error
            ? cause.message
            : 'Il Centro Diritti Privacy non risponde.',
        );
      } finally {
        setLoading(false);
      }
    },
    [isDemo],
  );

  useEffect(() => {
    void refresh();
  }, [refresh]);

  useEffect(() => {
    if (isDemo || !userId) {
      return;
    }
    return subscribeToPrivacyRightsCenter(userId, () => void refresh(true));
  }, [isDemo, refresh, userId]);

  const submit = async (requestType: PrivacyRightType, details: string) => {
    if (isDemo) {
      setActionError(
        'Le richieste privacy sono disponibili per gli account registrati.',
      );
      setNotice('');
      return { error: 'Le richieste non vengono inviate dalla modalità demo.' };
    }

    setActionLoading(true);
    setActionError('');
    setNotice('');
    try {
      const outcome = await submitPrivacyRightsRequest(requestType, details);
      if ('error' in outcome) {
        setActionError(
          outcome.error ?? 'Non riesco a registrare la richiesta privacy.',
        );
        return outcome;
      }
      await refresh(true);
      setNotice(
        'Richiesta registrata. Puoi seguirne lo stato in questa schermata.',
      );
      return outcome;
    } finally {
      setActionLoading(false);
    }
  };

  const cancel = async (requestId: string, expectedRevision: number) => {
    if (isDemo) {
      setActionError(
        'Le richieste privacy sono disponibili per gli account registrati.',
      );
      setNotice('');
      return { error: 'Le richieste non vengono modificate dalla modalità demo.' };
    }

    setActionLoading(true);
    setActionError('');
    setNotice('');
    try {
      const outcome = await cancelPrivacyRightsRequest(
        requestId,
        expectedRevision,
      );
      if (outcome.error) {
        setActionError(outcome.error);
        return outcome;
      }
      await refresh(true);
      setNotice('Richiesta annullata.');
      return outcome;
    } finally {
      setActionLoading(false);
    }
  };

  return {
    center,
    loading,
    error,
    actionLoading,
    actionError,
    notice,
    refresh,
    submit,
    cancel,
  };
}
