import AsyncStorage from '@react-native-async-storage/async-storage';
import Constants from 'expo-constants';
import * as Notifications from 'expo-notifications';
import { Platform } from 'react-native';
import { supabase } from '../lib/supabase';
import type {
  AppScreen,
  PushNotificationPreferences,
  PushNotificationTarget,
} from '../types';

const PUSH_TOKEN_STORAGE_KEY = 'leghevo:expo-push-token';
const PUSH_CHANNEL_ID = 'leghevo';

const allowedScreens = new Set<AppScreen>([
  'home',
  'league',
  'live',
  'auction',
  'calendar',
  'leagueCup',
  'leagueOperations',
  'leaguePlayoffs',
  'leagueSuperCup',
  'leagueRulebook',
  'lineup',
  'postponements',
  'roster',
  'standings',
  'market',
  'support',
]);

Notifications.setNotificationHandler({
  handleNotification: async () => ({
    shouldPlaySound: true,
    shouldSetBadge: false,
    shouldShowBanner: true,
    shouldShowList: true,
  }),
});

export type PushPermissionState =
  | 'granted'
  | 'denied'
  | 'undetermined'
  | 'unavailable';

export type PushRegistrationOutcome = {
  preferences?: PushNotificationPreferences;
  permission: PushPermissionState;
  error?: string;
};

export const defaultPushPreferences: PushNotificationPreferences = {
  pushEnabled: false,
  auctionTradeEnabled: true,
  lineupEnabled: true,
  resultsEnabled: true,
  leagueEnabled: true,
  systemEnabled: true,
  activeDeviceCount: 0,
  devices: [],
  revision: 0,
  protected: false,
  preferenceFingerprint: null,
  certifiedActionCount: 0,
  lastCertifiedAt: null,
};

export async function fetchPushPreferences() {
  if (!supabase) {
    throw new Error('Il backend non è configurato su questo dispositivo.');
  }

  const guarded = await supabase.rpc(
    'get_my_push_notification_preferences_v2',
  );
  if (!guarded.error) {
    return mapPushPreferences(guarded.data);
  }

  if (!isMissingGuardedPushFunction(guarded.error.message)) {
    throw new Error(translatePushError(guarded.error.message));
  }

  const legacy = await supabase.rpc('get_my_push_notification_preferences');
  if (legacy.error) {
    throw new Error(translatePushError(legacy.error.message));
  }

  return mapPushPreferences(legacy.data);
}

export async function savePushPreferences(
  preferences: PushNotificationPreferences,
) {
  if (!supabase) {
    throw new Error('Il backend non è configurato su questo dispositivo.');
  }

  const guarded = await supabase.rpc(
    'save_my_push_notification_preferences_guarded_v1',
    {
      p_push_enabled: preferences.pushEnabled,
      p_auction_trade_enabled: preferences.auctionTradeEnabled,
      p_lineup_enabled: preferences.lineupEnabled,
      p_results_enabled: preferences.resultsEnabled,
      p_league_enabled: preferences.leagueEnabled,
      p_system_enabled: preferences.systemEnabled,
      p_expected_revision: preferences.revision,
      p_idempotency_key: createOperationId(),
    },
  );

  let data = guarded.data;
  if (guarded.error) {
    if (!isMissingGuardedPushFunction(guarded.error.message)) {
      throw new Error(translatePushError(guarded.error.message));
    }

    const legacy = await supabase.rpc(
      'save_my_push_notification_preferences',
      {
        p_push_enabled: preferences.pushEnabled,
        p_auction_trade_enabled: preferences.auctionTradeEnabled,
        p_lineup_enabled: preferences.lineupEnabled,
        p_results_enabled: preferences.resultsEnabled,
        p_league_enabled: preferences.leagueEnabled,
        p_system_enabled: preferences.systemEnabled,
      },
    );
    if (legacy.error) {
      throw new Error(translatePushError(legacy.error.message));
    }
    data = legacy.data;
  }

  if (!preferences.pushEnabled) {
    await AsyncStorage.removeItem(PUSH_TOKEN_STORAGE_KEY);
  }

  return mapPushPreferences(data);
}

export async function registerCurrentPushDevice(
  requestPermission: boolean,
): Promise<PushRegistrationOutcome> {
  if (Platform.OS === 'web') {
    return {
      permission: 'unavailable',
      error: 'Le notifiche push sono disponibili nell’app iOS e Android.',
    };
  }

  if (!supabase) {
    return {
      permission: 'unavailable',
      error: 'Il backend non è configurato su questo dispositivo.',
    };
  }

  if (Platform.OS === 'android') {
    await Notifications.setNotificationChannelAsync(PUSH_CHANNEL_ID, {
      name: 'LEGHEVO',
      description: 'Formazioni, mercato, risultati e attività della lega.',
      importance: Notifications.AndroidImportance.HIGH,
      vibrationPattern: [0, 250, 180, 250],
      lightColor: '#C7FF39',
      sound: 'default',
    });
  }

  const currentPermission = await Notifications.getPermissionsAsync();
  let permission = permissionFromStatus(currentPermission.status);

  if (permission !== 'granted' && requestPermission) {
    const requested = await Notifications.requestPermissionsAsync();
    permission = permissionFromStatus(requested.status);
  }

  if (permission !== 'granted') {
    return {
      permission,
      error: requestPermission
        ? 'Permesso non concesso. Puoi abilitarlo dalle impostazioni del telefono.'
        : undefined,
    };
  }

  const projectId = resolveProjectId();
  if (!projectId) {
    return {
      permission,
      error:
        'Il progetto EAS non è ancora collegato. Le push saranno attivabili dalla build di sviluppo.',
    };
  }

  try {
    const expoPushToken = (
      await Notifications.getExpoPushTokenAsync({ projectId })
    ).data;
    const input = {
      p_expo_push_token: expoPushToken,
      p_platform: Platform.OS,
      p_device_name:
        Platform.OS === 'ios' ? 'Dispositivo Apple' : 'Dispositivo Android',
      p_app_version: Constants.expoConfig?.version ?? null,
    };

    const guarded = await supabase.rpc(
      'register_my_push_device_guarded_v1',
      {
        ...input,
        p_idempotency_key: createOperationId(),
      },
    );

    if (guarded.error) {
      if (!isMissingGuardedPushFunction(guarded.error.message)) {
        throw new Error(translatePushError(guarded.error.message));
      }
      const legacy = await supabase.rpc('register_my_push_device', input);
      if (legacy.error) {
        throw new Error(translatePushError(legacy.error.message));
      }
    }

    await AsyncStorage.setItem(PUSH_TOKEN_STORAGE_KEY, expoPushToken);
    return {
      permission,
      preferences: guarded.error
        ? await fetchPushPreferences()
        : mapPushPreferences(guarded.data),
    };
  } catch (cause) {
    return {
      permission,
      error: translateRegistrationError(cause),
    };
  }
}

export async function unregisterCurrentPushDevice() {
  if (!supabase) {
    return;
  }

  const token = await AsyncStorage.getItem(PUSH_TOKEN_STORAGE_KEY);
  if (!token) {
    return;
  }

  const guarded = await supabase.rpc('disable_my_push_device_guarded_v1', {
    p_expo_push_token: token,
    p_idempotency_key: createOperationId(),
  });

  if (!guarded.error) {
    await AsyncStorage.removeItem(PUSH_TOKEN_STORAGE_KEY);
    return;
  }

  if (!isMissingGuardedPushFunction(guarded.error.message)) {
    return;
  }

  const legacy = await supabase.rpc('disable_my_push_device', {
    p_expo_push_token: token,
  });
  if (!legacy.error) {
    await AsyncStorage.removeItem(PUSH_TOKEN_STORAGE_KEY);
  }
}

export async function releaseStoredPushDevice() {
  if (!supabase) {
    return;
  }

  const token = await AsyncStorage.getItem(PUSH_TOKEN_STORAGE_KEY);
  if (!token) {
    return;
  }

  const guarded = await supabase.rpc(
    'release_stored_push_device_guarded_v1',
    {
      p_expo_push_token: token,
      p_idempotency_key: createOperationId(),
    },
  );

  if (guarded.error) {
    if (!isMissingGuardedPushFunction(guarded.error.message)) {
      throw new Error(translatePushError(guarded.error.message));
    }
    const legacy = await supabase.rpc('release_stored_push_device', {
      p_expo_push_token: token,
    });
    if (legacy.error) {
      throw new Error(translatePushError(legacy.error.message));
    }
  }

  await AsyncStorage.removeItem(PUSH_TOKEN_STORAGE_KEY);
}

export async function readNativePushPermission(): Promise<PushPermissionState> {
  if (Platform.OS === 'web') {
    return 'unavailable';
  }
  try {
    const permission = await Notifications.getPermissionsAsync();
    return permissionFromStatus(permission.status);
  } catch {
    return 'unavailable';
  }
}

export function subscribeToPushResponses(
  onOpen: (target: PushNotificationTarget) => void,
) {
  const openResponse = (response: Notifications.NotificationResponse | null) => {
    if (!response) {
      return;
    }
    onOpen(mapNotificationTarget(response.notification.request.content.data));
  };

  openResponse(Notifications.getLastNotificationResponse());
  const subscription =
    Notifications.addNotificationResponseReceivedListener(openResponse);

  return () => subscription.remove();
}

export function subscribeToPushTokenChanges(onChange: () => void) {
  if (Platform.OS === 'web') {
    return () => undefined;
  }
  const subscription = Notifications.addPushTokenListener(onChange);
  return () => subscription.remove();
}

export function subscribeToPushPreferenceChanges(
  userId: string,
  onChange: () => void,
) {
  if (!supabase) {
    return () => undefined;
  }

  const channel = supabase
    .channel(`push-preference-actions:${userId}`)
    .on(
      'postgres_changes',
      {
        event: 'INSERT',
        schema: 'public',
        table: 'push_preference_action_runs',
        filter: `user_id=eq.${userId}`,
      },
      onChange,
    )
    .subscribe();

  return () => {
    void supabase?.removeChannel(channel);
  };
}

function resolveProjectId() {
  const configuredId =
    Constants.expoConfig?.extra?.eas?.projectId ??
    Constants.easConfig?.projectId ??
    process.env.EXPO_PUBLIC_EAS_PROJECT_ID;

  return typeof configuredId === 'string' && configuredId.trim()
    ? configuredId.trim()
    : null;
}

function mapNotificationTarget(
  data: Record<string, unknown>,
): PushNotificationTarget {
  const actionScreen =
    typeof data.actionScreen === 'string' &&
    allowedScreens.has(data.actionScreen as AppScreen)
      ? (data.actionScreen as AppScreen)
      : null;

  return {
    notificationId:
      typeof data.notificationId === 'string' ? data.notificationId : null,
    leagueId: typeof data.leagueId === 'string' ? data.leagueId : null,
    actionScreen,
  };
}

function mapPushPreferences(value: unknown): PushNotificationPreferences {
  const row =
    value && typeof value === 'object'
      ? (value as Record<string, unknown>)
      : {};
  const devices = Array.isArray(row.devices)
    ? row.devices
        .filter(
          (device): device is Record<string, unknown> =>
            Boolean(device) && typeof device === 'object',
        )
        .map((device) => ({
          id: String(device.id ?? ''),
          platform:
            device.platform === 'ios'
              ? ('ios' as const)
              : ('android' as const),
          deviceName:
            typeof device.deviceName === 'string' ? device.deviceName : null,
          appVersion:
            typeof device.appVersion === 'string' ? device.appVersion : null,
          enabled: Boolean(device.enabled),
          registeredAt:
            typeof device.registeredAt === 'string'
              ? device.registeredAt
              : new Date(0).toISOString(),
          lastSeenAt:
            typeof device.lastSeenAt === 'string'
              ? device.lastSeenAt
              : new Date(0).toISOString(),
          revision: toNonNegativeNumber(device.revision),
          tokenFingerprint:
            typeof device.tokenFingerprint === 'string'
              ? device.tokenFingerprint
              : null,
        }))
    : [];

  return {
    pushEnabled: Boolean(row.pushEnabled),
    auctionTradeEnabled: row.auctionTradeEnabled !== false,
    lineupEnabled: row.lineupEnabled !== false,
    resultsEnabled: row.resultsEnabled !== false,
    leagueEnabled: row.leagueEnabled !== false,
    systemEnabled: row.systemEnabled !== false,
    activeDeviceCount:
      typeof row.activeDeviceCount === 'number'
        ? row.activeDeviceCount
        : devices.filter((device) => device.enabled).length,
    devices,
    revision: toNonNegativeNumber(row.revision),
    protected: Boolean(row.protected),
    preferenceFingerprint:
      typeof row.preferenceFingerprint === 'string'
        ? row.preferenceFingerprint
        : null,
    certifiedActionCount: toNonNegativeNumber(row.certifiedActionCount),
    lastCertifiedAt:
      typeof row.lastCertifiedAt === 'string' ? row.lastCertifiedAt : null,
  };
}

function permissionFromStatus(status: Notifications.PermissionStatus) {
  if (status === Notifications.PermissionStatus.GRANTED) {
    return 'granted' as const;
  }
  if (status === Notifications.PermissionStatus.DENIED) {
    return 'denied' as const;
  }
  return 'undetermined' as const;
}

function translateRegistrationError(cause: unknown) {
  const message = cause instanceof Error ? cause.message : String(cause);
  const normalized = message.toLowerCase();
  if (
    normalized.includes('expo go') ||
    normalized.includes('development build')
  ) {
    return 'Le push remote richiedono una build di sviluppo EAS, non Expo Go.';
  }
  return translatePushError(message);
}

function translatePushError(message: string) {
  const normalized = message.toLowerCase();
  if (
    normalized.includes('altro dispositivo') ||
    normalized.includes('altro processo')
  ) {
    return 'Le preferenze sono cambiate su un altro dispositivo. Ricarica e riprova.';
  }
  if (normalized.includes('ancora attivo su un altro account')) {
    return 'Questo dispositivo è ancora collegato a un altro account. Disconnetti prima l’account precedente.';
  }
  if (
    normalized.includes('push_preference_action_runs') ||
    normalized.includes('get_my_push_notification_preferences_v2') ||
    normalized.includes('guarded_v1') ||
    normalized.includes('user_notification_preferences') ||
    normalized.includes('user_push_devices') ||
    normalized.includes('get_my_push_notification_preferences') ||
    normalized.includes('register_my_push_device') ||
    normalized.includes('release_stored_push_device') ||
    normalized.includes('does not exist') ||
    normalized.includes('schema cache')
  ) {
    return 'Aggiorna prima il database LEGHEVO con il file 097.';
  }
  return message;
}

function isMissingGuardedPushFunction(message: string) {
  const normalized = message.toLowerCase();
  return (
    normalized.includes('does not exist') ||
    normalized.includes('schema cache') ||
    normalized.includes('could not find the function')
  );
}

function createOperationId() {
  return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (token) => {
    const value = Math.floor(Math.random() * 16);
    const normalized = token === 'x' ? value : (value & 0x3) | 0x8;
    return normalized.toString(16);
  });
}

function toNonNegativeNumber(value: unknown) {
  const parsed = Number(value);
  return Number.isFinite(parsed) && parsed >= 0 ? parsed : 0;
}
