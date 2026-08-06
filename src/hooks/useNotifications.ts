import { useCallback, useEffect, useState } from 'react';
import {
  fetchUserNotifications,
  markAllNotificationsRead,
  markNotificationRead,
  subscribeToNotifications,
} from '../services/notificationService';
import type { AppNotification } from '../types';

function demoNotifications(): AppNotification[] {
  const now = Date.now();
  return [
    {
      id: 'demo-notification-trade',
      leagueId: 'demo-league',
      kind: 'trade',
      title: 'Nuova proposta di scambio',
      body: 'Tiki Taka Boom ha bussato alla porta del tuo procuratore.',
      actionScreen: 'market',
      metadata: {},
      readAt: null,
      createdAt: new Date(now - 8 * 60 * 1000).toISOString(),
      revision: 1,
      stateFingerprint: null,
      protected: false,
    },
    {
      id: 'demo-notification-lineup',
      leagueId: 'demo-league',
      kind: 'lineup',
      title: 'Formazione da consegnare',
      body: 'Mancano 90 minuti. Il mister avversario finge di essere tranquillo.',
      actionScreen: 'lineup',
      metadata: {},
      readAt: null,
      createdAt: new Date(now - 38 * 60 * 1000).toISOString(),
      revision: 1,
      stateFingerprint: null,
      protected: false,
    },
    {
      id: 'demo-notification-auction',
      leagueId: 'demo-league',
      kind: 'auction',
      title: 'Aggiudicato',
      body: 'Lorenzo Ricci entra nella tua rosa per 48 crediti.',
      actionScreen: 'roster',
      metadata: {},
      readAt: new Date(now - 2 * 60 * 60 * 1000).toISOString(),
      createdAt: new Date(now - 2 * 60 * 60 * 1000).toISOString(),
      revision: 2,
      stateFingerprint: null,
      protected: false,
    },
    {
      id: 'demo-notification-result',
      leagueId: 'demo-league',
      kind: 'result',
      title: 'Risultato definitivo',
      body: 'Diavoli del Sud 2–1 Tiki Taka Boom. Il VAR ha chiuso tutto.',
      actionScreen: 'live',
      metadata: {},
      readAt: new Date(now - 24 * 60 * 60 * 1000).toISOString(),
      createdAt: new Date(now - 24 * 60 * 60 * 1000).toISOString(),
      revision: 2,
      stateFingerprint: null,
      protected: false,
    },
  ];
}

export function useNotifications(
  userId: string | null,
  isDemo: boolean,
) {
  const [notifications, setNotifications] = useState<AppNotification[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [unreadCount, setUnreadCount] = useState(0);
  const [protectedCenter, setProtectedCenter] = useState(false);
  const [certifiedActionCount, setCertifiedActionCount] = useState(0);
  const [lastCertifiedAt, setLastCertifiedAt] = useState<string | null>(null);

  const refresh = useCallback(async () => {
    if (isDemo) {
      setNotifications((current) => {
        const next = current.length > 0 ? current : demoNotifications();
        setUnreadCount(
          next.filter((notification) => !notification.readAt).length,
        );
        return next;
      });
      setProtectedCenter(false);
      setCertifiedActionCount(0);
      setLastCertifiedAt(null);
      setError('');
      setLoading(false);
      return;
    }

    if (!userId) {
      setNotifications([]);
      setUnreadCount(0);
      setProtectedCenter(false);
      setCertifiedActionCount(0);
      setLastCertifiedAt(null);
      setError('');
      setLoading(false);
      return;
    }

    setLoading(true);
    try {
      const center = await fetchUserNotifications(userId);
      setNotifications(center.notifications);
      setUnreadCount(center.unreadCount);
      setProtectedCenter(center.protected);
      setCertifiedActionCount(center.certifiedActionCount);
      setLastCertifiedAt(center.lastCertifiedAt);
      setError('');
    } catch (cause) {
      setError(
        cause instanceof Error
          ? cause.message
          : 'Le notifiche sono rimaste negli spogliatoi.',
      );
    } finally {
      setLoading(false);
    }
  }, [isDemo, userId]);

  useEffect(() => {
    void refresh();
  }, [refresh]);

  useEffect(() => {
    if (!userId || isDemo) {
      return;
    }
    return subscribeToNotifications(userId, () => void refresh());
  }, [isDemo, refresh, userId]);

  const markRead = useCallback(
    async (notificationId: string) => {
      const optimisticReadAt = new Date().toISOString();
      setNotifications((current) => {
        const wasUnread = current.some(
          (notification) =>
            notification.id === notificationId && !notification.readAt,
        );
        if (wasUnread) {
          setUnreadCount((count) => Math.max(0, count - 1));
        }
        return current.map((notification) =>
          notification.id === notificationId
            ? {
                ...notification,
                readAt: notification.readAt ?? optimisticReadAt,
              }
            : notification,
        );
      });

      if (!isDemo) {
        try {
          const result = await markNotificationRead(notificationId);
          setNotifications((current) =>
            current.map((notification) =>
              notification.id === notificationId
                ? {
                    ...notification,
                    readAt: result.readAt ?? notification.readAt,
                    revision:
                      result.revision > 0
                        ? result.revision
                        : notification.revision,
                    stateFingerprint:
                      result.stateFingerprint ?? notification.stateFingerprint,
                    protected: result.protected || notification.protected,
                  }
                : notification,
            ),
          );
          if (result.protected) {
            setProtectedCenter(true);
            setLastCertifiedAt(new Date().toISOString());
            void refresh();
          }
          setError('');
        } catch (cause) {
          setError(
            cause instanceof Error
              ? cause.message
              : 'Non riesco a segnare la notifica come letta.',
          );
          await refresh();
        }
      }
    },
    [isDemo, refresh],
  );

  const markAllRead = useCallback(async () => {
    const optimisticReadAt = new Date().toISOString();
    setUnreadCount(0);
    setNotifications((current) =>
      current.map((notification) => ({
        ...notification,
        readAt: notification.readAt ?? optimisticReadAt,
      })),
    );

    if (!isDemo) {
      try {
        const result = await markAllNotificationsRead();
        if (result.protected) {
          setProtectedCenter(true);
          setLastCertifiedAt(new Date().toISOString());
          await refresh();
        } else if (result.unreadCount > 0) {
          await refresh();
        }
        setError('');
      } catch (cause) {
        setError(
          cause instanceof Error
            ? cause.message
            : 'Non riesco a chiudere il giro delle notifiche.',
        );
        await refresh();
      }
    }
  }, [isDemo, refresh]);

  return {
    notifications,
    unreadCount,
    loading,
    error,
    protected: protectedCenter,
    certifiedActionCount,
    lastCertifiedAt,
    refresh,
    markRead,
    markAllRead,
  };
}
