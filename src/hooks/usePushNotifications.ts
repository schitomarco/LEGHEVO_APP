import { useCallback, useEffect, useState } from 'react';
import {
  defaultPushPreferences,
  fetchPushPreferences,
  readNativePushPermission,
  registerCurrentPushDevice,
  releaseStoredPushDevice,
  savePushPreferences,
  subscribeToPushPreferenceChanges,
  subscribeToPushResponses,
  subscribeToPushTokenChanges,
  type PushPermissionState,
} from '../services/pushNotificationService';
import type {
  PushNotificationPreferences,
  PushNotificationTarget,
} from '../types';

export function usePushNotifications(
  userId: string | null,
  isDemo: boolean,
  onOpen: (target: PushNotificationTarget) => void,
) {
  const [preferences, setPreferences] =
    useState<PushNotificationPreferences>(defaultPushPreferences);
  const [permission, setPermission] =
    useState<PushPermissionState>('undetermined');
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');

  const refresh = useCallback(async () => {
    if (isDemo || !userId) {
      setPreferences(defaultPushPreferences);
      setPermission(isDemo ? 'unavailable' : 'undetermined');
      setError('');
      setLoading(false);
      return;
    }

    setLoading(true);
    try {
      const [nextPreferences, nextPermission] = await Promise.all([
        fetchPushPreferences(),
        readNativePushPermission(),
      ]);
      setPreferences(nextPreferences);
      setPermission(nextPermission);
      setError('');

      if (nextPreferences.pushEnabled && nextPermission === 'granted') {
        const registration = await registerCurrentPushDevice(false);
        setPermission(registration.permission);
        if (registration.preferences) {
          setPreferences(registration.preferences);
        }
        if (registration.error) {
          setError(registration.error);
        }
      } else if (!nextPreferences.pushEnabled) {
        await releaseStoredPushDevice();
      }
    } catch (cause) {
      setError(
        cause instanceof Error
          ? cause.message
          : 'Le preferenze push non sono disponibili.',
      );
    } finally {
      setLoading(false);
    }
  }, [isDemo, userId]);

  useEffect(() => {
    void refresh();
  }, [refresh]);

  useEffect(() => {
    if (isDemo || !userId) {
      return;
    }
    return subscribeToPushResponses(onOpen);
  }, [isDemo, onOpen, userId]);

  useEffect(() => {
    if (isDemo || !userId) {
      return;
    }

    return subscribeToPushPreferenceChanges(userId, () => {
      void fetchPushPreferences()
        .then((next) => {
          setPreferences(next);
          setError('');
        })
        .catch((cause) => {
          setError(
            cause instanceof Error
              ? cause.message
              : 'Le preferenze push non sono disponibili.',
          );
        });
    });
  }, [isDemo, userId]);

  useEffect(() => {
    if (isDemo || !userId || !preferences.pushEnabled) {
      return;
    }
    return subscribeToPushTokenChanges(() => {
      void registerCurrentPushDevice(false).then((outcome) => {
        setPermission(outcome.permission);
        if (outcome.preferences) {
          setPreferences(outcome.preferences);
        }
        if (outcome.error) {
          setError(outcome.error);
        }
      });
    });
  }, [isDemo, preferences.pushEnabled, userId]);

  const enable = async () => {
    if (isDemo) {
      setError('Le notifiche push non vengono registrate nella modalità demo.');
      return;
    }

    setBusy(true);
    const outcome = await registerCurrentPushDevice(true);
    setPermission(outcome.permission);
    if (outcome.preferences) {
      setPreferences(outcome.preferences);
      setError('');
    } else if (outcome.error) {
      setError(outcome.error);
    }
    setBusy(false);
  };

  const disable = async () => {
    if (isDemo) {
      setPreferences(defaultPushPreferences);
      return;
    }

    setBusy(true);
    try {
      const next = await savePushPreferences({
        ...preferences,
        pushEnabled: false,
      });
      setPreferences(next);
      setError('');
    } catch (cause) {
      setError(
        cause instanceof Error
          ? cause.message
          : 'Non riesco a disattivare gli avvisi push.',
      );
    } finally {
      setBusy(false);
    }
  };

  const update = async (
    key: keyof Pick<
      PushNotificationPreferences,
      | 'auctionTradeEnabled'
      | 'lineupEnabled'
      | 'resultsEnabled'
      | 'leagueEnabled'
      | 'systemEnabled'
    >,
    enabled: boolean,
  ) => {
    if (isDemo) {
      setPreferences((current) => ({ ...current, [key]: enabled }));
      return;
    }

    const previous = preferences;
    const optimistic = { ...preferences, [key]: enabled };
    setPreferences(optimistic);
    setBusy(true);
    try {
      const next = await savePushPreferences(optimistic);
      setPreferences(next);
      setError('');
    } catch (cause) {
      setPreferences(previous);
      setError(
        cause instanceof Error
          ? cause.message
          : 'Non riesco a salvare questa preferenza.',
      );
    } finally {
      setBusy(false);
    }
  };

  return {
    preferences,
    permission,
    loading,
    busy,
    error,
    refresh,
    enable,
    disable,
    update,
  };
}
