import { supabase } from '../lib/supabase';
import type {
  AppNotification,
  AppScreen,
  NotificationCenterState,
  NotificationKind,
} from '../types';

type NotificationRow = {
  id: string;
  league_id: string | null;
  kind: NotificationKind;
  title: string;
  body: string;
  action_screen: string | null;
  metadata: Record<string, unknown> | null;
  read_at: string | null;
  created_at: string;
};

export type NotificationReadResult = {
  notificationId: string;
  readAt: string | null;
  revision: number;
  stateFingerprint: string | null;
  affectedCount: number;
  protected: boolean;
};

export type NotificationReadAllResult = {
  affectedCount: number;
  readAt: string | null;
  unreadCount: number;
  resultRevision: number;
  resultFingerprint: string | null;
  protected: boolean;
};

const allowedScreens = new Set<AppScreen>([
  'home',
  'league',
  'live',
  'auction',
  'calendar',
  'leagueCup',
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

export async function fetchUserNotifications(
  userId: string,
): Promise<NotificationCenterState> {
  if (!supabase) {
    return emptyNotificationCenter;
  }

  const guarded = await supabase.rpc('get_my_notification_center_v2', {
    p_limit: 60,
  });
  if (!guarded.error) {
    return normalizeNotificationCenter(guarded.data);
  }

  if (!isMissingGuardedNotificationFunction(guarded.error.message)) {
    throw new Error(translateNotificationError(guarded.error.message));
  }

  const { data, error } = await supabase
    .from('user_notifications')
    .select(
      [
        'id',
        'league_id',
        'kind',
        'title',
        'body',
        'action_screen',
        'metadata',
        'read_at',
        'created_at',
      ].join(','),
    )
    .eq('user_id', userId)
    .order('created_at', { ascending: false })
    .limit(60);

  if (error) {
    throw new Error(translateNotificationError(error.message));
  }

  const notifications = ((data ?? []) as unknown as NotificationRow[]).map(
    mapLegacyNotification,
  );

  return {
    notifications,
    unreadCount: notifications.filter((notification) => !notification.readAt)
      .length,
    totalCount: notifications.length,
    protected: false,
    certifiedActionCount: 0,
    lastCertifiedAt: null,
  };
}

export async function markNotificationRead(
  notificationId: string,
): Promise<NotificationReadResult> {
  if (!supabase) {
    return {
      notificationId,
      readAt: null,
      revision: 0,
      stateFingerprint: null,
      affectedCount: 0,
      protected: false,
    };
  }

  const guarded = await supabase.rpc('mark_notification_read_guarded_v1', {
    p_notification_id: notificationId,
    p_idempotency_key: createOperationId(),
  });

  if (!guarded.error) {
    return normalizeReadResult(guarded.data, notificationId);
  }

  if (!isMissingGuardedNotificationFunction(guarded.error.message)) {
    throw new Error(translateNotificationError(guarded.error.message));
  }

  const legacy = await supabase.rpc('mark_notification_read', {
    p_notification_id: notificationId,
  });
  if (legacy.error) {
    throw new Error(translateNotificationError(legacy.error.message));
  }

  return {
    notificationId,
    readAt: toNullableString(legacy.data),
    revision: 0,
    stateFingerprint: null,
    affectedCount: 1,
    protected: false,
  };
}

export async function markAllNotificationsRead(): Promise<NotificationReadAllResult> {
  if (!supabase) {
    return {
      affectedCount: 0,
      readAt: null,
      unreadCount: 0,
      resultRevision: 0,
      resultFingerprint: null,
      protected: false,
    };
  }

  const guarded = await supabase.rpc(
    'mark_all_notifications_read_guarded_v1',
    { p_idempotency_key: createOperationId() },
  );

  if (!guarded.error) {
    return normalizeReadAllResult(guarded.data);
  }

  if (!isMissingGuardedNotificationFunction(guarded.error.message)) {
    throw new Error(translateNotificationError(guarded.error.message));
  }

  const legacy = await supabase.rpc('mark_all_notifications_read');
  if (legacy.error) {
    throw new Error(translateNotificationError(legacy.error.message));
  }

  return {
    affectedCount: toNumber(legacy.data),
    readAt: new Date().toISOString(),
    unreadCount: 0,
    resultRevision: 0,
    resultFingerprint: null,
    protected: false,
  };
}

export function subscribeToNotifications(
  userId: string,
  onChange: () => void,
) {
  if (!supabase) {
    return () => undefined;
  }

  const client = supabase;
  const channel = client
    .channel(`notifications-${userId}`)
    .on(
      'postgres_changes',
      {
        event: '*',
        schema: 'public',
        table: 'user_notifications',
        filter: `user_id=eq.${userId}`,
      },
      onChange,
    )
    .on(
      'postgres_changes',
      {
        event: '*',
        schema: 'public',
        table: 'notification_action_runs',
        filter: `user_id=eq.${userId}`,
      },
      onChange,
    )
    .subscribe();

  return () => {
    void client.removeChannel(channel);
  };
}

function normalizeNotificationCenter(value: unknown): NotificationCenterState {
  const raw = asRecord(value);
  const notifications = Array.isArray(raw.notifications)
    ? raw.notifications.map(normalizeNotification)
    : [];

  return {
    notifications,
    unreadCount: Math.max(0, toNumber(raw.unreadCount)),
    totalCount: Math.max(0, toNumber(raw.totalCount)),
    protected: Boolean(raw.protected),
    certifiedActionCount: Math.max(0, toNumber(raw.certifiedActionCount)),
    lastCertifiedAt: toNullableString(raw.lastCertifiedAt),
  };
}

function normalizeNotification(value: unknown): AppNotification {
  const raw = asRecord(value);
  const actionScreen =
    typeof raw.actionScreen === 'string' &&
    allowedScreens.has(raw.actionScreen as AppScreen)
      ? (raw.actionScreen as AppScreen)
      : null;

  return {
    id: toStringValue(raw.id),
    leagueId: toNullableString(raw.leagueId),
    kind: normalizeKind(raw.kind),
    title: toStringValue(raw.title),
    body: toStringValue(raw.body),
    actionScreen,
    metadata: asRecord(raw.metadata),
    readAt: toNullableString(raw.readAt),
    createdAt: toStringValue(raw.createdAt),
    revision: Math.max(1, toNumber(raw.revision)),
    stateFingerprint: toNullableString(raw.stateFingerprint),
    protected: Boolean(raw.protected),
  };
}

function mapLegacyNotification(row: NotificationRow): AppNotification {
  const actionScreen =
    row.action_screen && allowedScreens.has(row.action_screen as AppScreen)
      ? (row.action_screen as AppScreen)
      : null;

  return {
    id: row.id,
    leagueId: row.league_id,
    kind: row.kind,
    title: row.title,
    body: row.body,
    actionScreen,
    metadata: row.metadata ?? {},
    readAt: row.read_at,
    createdAt: row.created_at,
    revision: 1,
    stateFingerprint: null,
    protected: false,
  };
}

function normalizeReadResult(
  value: unknown,
  notificationId: string,
): NotificationReadResult {
  const raw = asRecord(value);
  return {
    notificationId: toStringValue(raw.notificationId) || notificationId,
    readAt: toNullableString(raw.readAt),
    revision: Math.max(1, toNumber(raw.revision)),
    stateFingerprint: toNullableString(raw.stateFingerprint),
    affectedCount: Math.max(0, toNumber(raw.affectedCount)),
    protected: Boolean(raw.protected),
  };
}

function normalizeReadAllResult(value: unknown): NotificationReadAllResult {
  const raw = asRecord(value);
  return {
    affectedCount: Math.max(0, toNumber(raw.affectedCount)),
    readAt: toNullableString(raw.readAt),
    unreadCount: Math.max(0, toNumber(raw.unreadCount)),
    resultRevision: Math.max(0, toNumber(raw.resultRevision)),
    resultFingerprint: toNullableString(raw.resultFingerprint),
    protected: Boolean(raw.protected),
  };
}

function translateNotificationError(message: string) {
  const normalized = message.toLowerCase();
  if (
    normalized.includes('identificativo operazione') ||
    normalized.includes('notification_action_runs')
  ) {
    return 'La richiesta non è stata accettata. Aggiorna la bacheca e riprova una sola volta.';
  }
  if (
    normalized.includes('get_my_notification_center_v2') ||
    normalized.includes('mark_notification_read_guarded_v1') ||
    normalized.includes('mark_all_notifications_read_guarded_v1')
  ) {
    return 'Aggiorna prima il database LEGHEVO con la migrazione 100.';
  }
  if (
    normalized.includes('user_notifications') ||
    normalized.includes('mark_notification_read') ||
    normalized.includes('mark_all_notifications_read')
  ) {
    return 'Il Centro Notifiche non è ancora disponibile nel database.';
  }
  return message;
}

function isMissingGuardedNotificationFunction(message: string) {
  const normalized = message.toLowerCase();
  return (
    normalized.includes('does not exist') ||
    normalized.includes('schema cache') ||
    normalized.includes('could not find the function')
  );
}

function normalizeKind(value: unknown): NotificationKind {
  return value === 'auction' ||
    value === 'trade' ||
    value === 'lineup' ||
    value === 'result' ||
    value === 'market' ||
    value === 'league' ||
    value === 'system'
    ? value
    : 'system';
}

function createOperationId() {
  return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (token) => {
    const value = Math.floor(Math.random() * 16);
    const normalized = token === 'x' ? value : (value & 0x3) | 0x8;
    return normalized.toString(16);
  });
}

function asRecord(value: unknown): Record<string, unknown> {
  return value && typeof value === 'object'
    ? (value as Record<string, unknown>)
    : {};
}

function toStringValue(value: unknown) {
  return typeof value === 'string' ? value : '';
}

function toNullableString(value: unknown) {
  return typeof value === 'string' && value.length > 0 ? value : null;
}

function toNumber(value: unknown) {
  if (typeof value === 'number' && Number.isFinite(value)) {
    return value;
  }
  if (typeof value === 'string') {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : 0;
  }
  return 0;
}

const emptyNotificationCenter: NotificationCenterState = {
  notifications: [],
  unreadCount: 0,
  totalCount: 0,
  protected: false,
  certifiedActionCount: 0,
  lastCertifiedAt: null,
};
