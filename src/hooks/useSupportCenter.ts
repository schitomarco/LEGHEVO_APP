import { useCallback, useEffect, useState } from 'react';
import {
  closeSupportRequest,
  createSupportRequest,
  fetchSupportCenter,
  replyToSupportRequest,
  subscribeToSupportCenter,
  type CreateSupportRequestInput,
  type SupportCenter,
} from '../services/supportService';

const demoSupportCenter: SupportCenter = {
  generatedAt: '2026-07-29T12:00:00Z',
  openCount: 1,
  waitingUserCount: 1,
  totalCount: 1,
  protection: {
    guardedActionsReady: true,
    revisionControlReady: true,
    idempotencyReady: true,
  },
  requests: [
    {
      id: 'demo-support-request',
      leagueId: 'demo-league',
      leagueName: 'Gli Irriducibili',
      category: 'lineup_results',
      subject: 'Chiarimento su una sostituzione',
      status: 'waiting_user',
      createdAt: '2026-07-28T18:10:00Z',
      updatedAt: '2026-07-29T09:30:00Z',
      resolvedAt: null,
      closedAt: null,
      revision: 2,
      protected: true,
      canReply: true,
      canClose: true,
      messages: [
        {
          id: 'demo-support-message-user',
          authorType: 'user',
          body: 'Perché il primo panchinaro non è entrato nella giornata 6?',
          createdAt: '2026-07-28T18:10:00Z',
        },
        {
          id: 'demo-support-message-staff',
          authorType: 'support',
          body:
            'Il limite di tre sostituzioni era già stato raggiunto. Se vuoi, indicaci il nome della lega per un controllo puntuale.',
          createdAt: '2026-07-29T09:30:00Z',
        },
      ],
      events: [
        {
          id: 'demo-support-event-submitted',
          actorType: 'user',
          eventType: 'submitted',
          status: 'submitted',
          occurredAt: '2026-07-28T18:10:00Z',
        },
        {
          id: 'demo-support-event-replied',
          actorType: 'support',
          eventType: 'support_replied',
          status: 'waiting_user',
          occurredAt: '2026-07-29T09:30:00Z',
        },
      ],
    },
  ],
};

export function useSupportCenter(
  userId: string | null,
  isDemo: boolean,
) {
  const [center, setCenter] = useState<SupportCenter | null>(
    isDemo ? demoSupportCenter : null,
  );
  const [loading, setLoading] = useState(true);
  const [actionLoading, setActionLoading] = useState(false);
  const [error, setError] = useState('');
  const [notice, setNotice] = useState('');

  const refresh = useCallback(
    async (quiet = false) => {
      if (isDemo) {
        setCenter(demoSupportCenter);
        setError('');
        setLoading(false);
        return;
      }

      if (!userId) {
        setCenter(null);
        setError('');
        setLoading(false);
        return;
      }

      if (!quiet) {
        setLoading(true);
      }
      try {
        setCenter(await fetchSupportCenter());
        setError('');
      } catch (cause) {
        setError(
          cause instanceof Error
            ? cause.message
            : 'Il Centro Assistenza non è disponibile.',
        );
      } finally {
        setLoading(false);
      }
    },
    [isDemo, userId],
  );

  useEffect(() => {
    void refresh();
  }, [refresh]);

  useEffect(() => {
    if (isDemo || !userId) {
      return;
    }
    return subscribeToSupportCenter(userId, () => void refresh(true));
  }, [isDemo, refresh, userId]);

  const create = async (input: CreateSupportRequestInput) => {
    if (isDemo) {
      setError(
        'Le richieste vengono inviate soltanto dagli account registrati.',
      );
      setNotice('');
      return { error: 'La modalità demo non crea richieste di assistenza.' };
    }

    setActionLoading(true);
    setError('');
    setNotice('');
    try {
      const outcome = await createSupportRequest(input);
      if (outcome.error) {
        setError(outcome.error);
        return outcome;
      }
      await refresh(true);
      setNotice('Richiesta inviata. Puoi seguirla da questa schermata.');
      return outcome;
    } finally {
      setActionLoading(false);
    }
  };

  const reply = async (
    requestId: string,
    message: string,
    expectedRevision: number,
  ) => {
    if (isDemo) {
      setError(
        'Le risposte vengono inviate soltanto dagli account registrati.',
      );
      setNotice('');
      return { error: 'La modalità demo non invia risposte.' };
    }

    setActionLoading(true);
    setError('');
    setNotice('');
    try {
      const outcome = await replyToSupportRequest(
        requestId,
        message,
        expectedRevision,
      );
      if (outcome.error) {
        setError(outcome.error);
        return outcome;
      }
      await refresh(true);
      setNotice('Risposta inviata all’assistenza.');
      return outcome;
    } finally {
      setActionLoading(false);
    }
  };

  const close = async (requestId: string, expectedRevision: number) => {
    if (isDemo) {
      setError(
        'Le pratiche demo restano disponibili come anteprima.',
      );
      setNotice('');
      return { error: 'La modalità demo non chiude pratiche.' };
    }

    setActionLoading(true);
    setError('');
    setNotice('');
    try {
      const outcome = await closeSupportRequest(
        requestId,
        expectedRevision,
      );
      if (outcome.error) {
        setError(outcome.error);
        return outcome;
      }
      await refresh(true);
      setNotice('Richiesta chiusa.');
      return outcome;
    } finally {
      setActionLoading(false);
    }
  };

  return {
    center,
    loading,
    actionLoading,
    error,
    notice,
    refresh,
    create,
    reply,
    close,
  };
}
