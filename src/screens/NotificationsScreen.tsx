import {
  ActivityIndicator,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  View,
} from 'react-native';
import { colors, radius } from '../theme';
import type { AppNotification } from '../types';

type Props = {
  notifications: AppNotification[];
  unreadCount: number;
  loading: boolean;
  error: string;
  protected: boolean;
  certifiedActionCount: number;
  lastCertifiedAt: string | null;
  onBack: () => void;
  onMarkAllRead: () => void | Promise<void>;
  onOpen: (notification: AppNotification) => void | Promise<void>;
  onRefresh: () => void | Promise<void>;
};

const kindStyles = {
  auction: { symbol: 'A', label: 'ASTA' },
  trade: { symbol: 'S', label: 'SCAMBIO' },
  lineup: { symbol: '11', label: 'FORMAZIONE' },
  result: { symbol: 'V', label: 'RISULTATO' },
  market: { symbol: 'M', label: 'MERCATO' },
  league: { symbol: 'L', label: 'LEGA' },
  system: { symbol: '!', label: 'LEGHEVO' },
} as const;

export function NotificationsScreen({
  notifications,
  unreadCount,
  loading,
  error,
  protected: protectedCenter,
  certifiedActionCount,
  lastCertifiedAt,
  onBack,
  onMarkAllRead,
  onOpen,
  onRefresh,
}: Props) {
  return (
    <ScrollView
      style={styles.screen}
      contentContainerStyle={styles.content}
      showsVerticalScrollIndicator={false}
    >
      <View style={styles.header}>
        <Pressable
          accessibilityLabel="Torna alla home"
          onPress={onBack}
          style={styles.backButton}
        >
          <Text style={styles.backText}>‹</Text>
        </Pressable>
        <View style={styles.headerCopy}>
          <Text style={styles.eyebrow}>SPOGLIATOIO SEMPRE ACCESO</Text>
          <Text style={styles.title}>Notifiche</Text>
        </View>
        <Pressable
          accessibilityLabel="Aggiorna notifiche"
          disabled={loading}
          onPress={() => void onRefresh()}
          style={styles.reloadButton}
        >
          <Text style={styles.reloadText}>↻</Text>
        </Pressable>
      </View>

      <View style={styles.summaryCard}>
        <View>
          <Text style={styles.summaryEyebrow}>DA LEGGERE</Text>
          <Text style={styles.summaryValue}>{unreadCount}</Text>
        </View>
        <View style={styles.summaryCopy}>
          <Text style={styles.summaryTitle}>
            {unreadCount === 0
              ? 'Tutto sotto controllo'
              : unreadCount === 1
                ? 'Una questione aperta'
                : 'Il gruppo si è mosso'}
          </Text>
          <Text style={styles.summaryBody}>
            {unreadCount === 0
              ? 'Per ora nessuno ha combinato niente.'
              : 'Offerte, risultati e colpi d’asta arrivano qui.'}
          </Text>
        </View>
      </View>

      {protectedCenter ? (
        <View style={styles.protectionCard}>
          <View style={styles.protectionTop}>
            <Text style={styles.protectionLabel}>INBOX PROTETTA</Text>
            <Text style={styles.protectionCount}>
              {certifiedActionCount} AZIONI CERTIFICATE
            </Text>
          </View>
          <Text style={styles.protectionBody}>
            Letture sincronizzate tra dispositivi con controllo anti-doppio
            tocco e registro immutabile.
            {lastCertifiedAt
              ? ` Ultima azione: ${formatCertifiedTime(lastCertifiedAt)}.`
              : ''}
          </Text>
        </View>
      ) : null}

      <View style={styles.sectionHeader}>
        <Text style={styles.sectionTitle}>Ultimi aggiornamenti</Text>
        {unreadCount > 0 ? (
          <Pressable onPress={() => void onMarkAllRead()}>
            <Text style={styles.markAllText}>SEGNA TUTTE LETTE</Text>
          </Pressable>
        ) : null}
      </View>

      {loading ? (
        <View style={styles.stateCard}>
          <ActivityIndicator color={colors.navy} />
          <Text style={styles.stateBody}>Controllo cosa è successo…</Text>
        </View>
      ) : error ? (
        <View style={styles.errorCard}>
          <Text style={styles.errorTitle}>Bacheca indisponibile</Text>
          <Text style={styles.errorBody}>{error}</Text>
        </View>
      ) : notifications.length === 0 ? (
        <View style={styles.stateCard}>
          <View style={styles.emptySymbol}>
            <Text style={styles.emptySymbolText}>✓</Text>
          </View>
          <Text style={styles.stateTitle}>Silenzio nello spogliatoio</Text>
          <Text style={styles.stateBody}>
            Le novità di asta, mercato e partite compariranno qui.
          </Text>
        </View>
      ) : (
        <View style={styles.list}>
          {notifications.map((notification) => (
            <NotificationCard
              key={notification.id}
              notification={notification}
              onPress={() => void onOpen(notification)}
            />
          ))}
        </View>
      )}
    </ScrollView>
  );
}

function NotificationCard({
  notification,
  onPress,
}: {
  notification: AppNotification;
  onPress: () => void;
}) {
  const meta = kindStyles[notification.kind];
  const unread = !notification.readAt;

  return (
    <Pressable
      onPress={onPress}
      style={[styles.card, unread && styles.cardUnread]}
    >
      <View style={[styles.kindBadge, unread && styles.kindBadgeUnread]}>
        <Text style={[styles.kindSymbol, unread && styles.kindSymbolUnread]}>
          {meta.symbol}
        </Text>
      </View>
      <View style={styles.cardCopy}>
        <View style={styles.cardMeta}>
          <Text style={styles.kindLabel}>{meta.label}</Text>
          <Text style={styles.timeLabel}>
            {formatRelativeTime(notification.createdAt)}
          </Text>
        </View>
        <Text style={styles.cardTitle}>{notification.title}</Text>
        <Text style={styles.cardBody}>{notification.body}</Text>
      </View>
      <View style={styles.cardAction}>
        {unread ? <View style={styles.unreadDot} /> : null}
        {notification.actionScreen ? (
          <Text style={styles.cardArrow}>›</Text>
        ) : null}
      </View>
    </Pressable>
  );
}

function formatRelativeTime(value: string) {
  const elapsed = Math.max(0, Date.now() - new Date(value).getTime());
  const minutes = Math.floor(elapsed / 60000);
  if (minutes < 1) {
    return 'ADESSO';
  }
  if (minutes < 60) {
    return `${minutes} MIN`;
  }
  const hours = Math.floor(minutes / 60);
  if (hours < 24) {
    return `${hours} ${hours === 1 ? 'ORA' : 'ORE'}`;
  }
  const days = Math.floor(hours / 24);
  return `${days} ${days === 1 ? 'GIORNO' : 'GIORNI'}`;
}

function formatCertifiedTime(value: string) {
  const parsed = new Date(value);
  if (Number.isNaN(parsed.getTime())) {
    return 'adesso';
  }
  return parsed.toLocaleString('it-IT', {
    day: '2-digit',
    month: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
  });
}

const styles = StyleSheet.create({
  screen: {
    flex: 1,
    backgroundColor: colors.canvas,
  },
  content: {
    padding: 20,
    paddingBottom: 42,
  },
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    marginBottom: 22,
  },
  backButton: {
    width: 42,
    height: 42,
    borderRadius: 21,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.white,
  },
  backText: {
    color: colors.navy,
    fontSize: 32,
    lineHeight: 34,
  },
  headerCopy: {
    flex: 1,
    marginLeft: 14,
  },
  eyebrow: {
    color: colors.muted,
    fontSize: 9,
    fontWeight: '900',
    letterSpacing: 0.55,
  },
  title: {
    color: colors.navy,
    fontSize: 28,
    fontWeight: '900',
    marginTop: 3,
  },
  reloadButton: {
    width: 42,
    height: 42,
    borderRadius: 21,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.white,
  },
  reloadText: {
    color: colors.navy,
    fontSize: 22,
    fontWeight: '800',
  },
  summaryCard: {
    minHeight: 142,
    borderRadius: radius.xl,
    padding: 22,
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: colors.navy,
  },
  summaryEyebrow: {
    color: colors.mutedLight,
    fontSize: 9,
    fontWeight: '900',
    letterSpacing: 0.55,
  },
  summaryValue: {
    color: colors.lime,
    fontSize: 48,
    fontWeight: '900',
    lineHeight: 54,
    minWidth: 68,
  },
  summaryCopy: {
    flex: 1,
    marginLeft: 16,
    paddingLeft: 18,
    borderLeftWidth: 1,
    borderLeftColor: colors.navyLine,
  },
  summaryTitle: {
    color: colors.warmWhite,
    fontSize: 17,
    fontWeight: '900',
  },
  summaryBody: {
    color: colors.mutedLight,
    fontSize: 12,
    lineHeight: 18,
    marginTop: 6,
  },
  protectionCard: {
    marginTop: 12,
    borderRadius: radius.lg,
    padding: 16,
    backgroundColor: '#F5FCE5',
    borderWidth: 1,
    borderColor: '#DCEAB8',
  },
  protectionTop: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
  },
  protectionLabel: {
    color: colors.navy,
    fontSize: 9,
    fontWeight: '900',
    letterSpacing: 0.45,
  },
  protectionCount: {
    color: colors.navy,
    fontSize: 8,
    fontWeight: '900',
  },
  protectionBody: {
    color: colors.muted,
    fontSize: 11,
    lineHeight: 17,
    marginTop: 8,
  },
  sectionHeader: {
    minHeight: 56,
    flexDirection: 'row',
    alignItems: 'flex-end',
    justifyContent: 'space-between',
    paddingBottom: 12,
  },
  sectionTitle: {
    color: colors.navy,
    fontSize: 17,
    fontWeight: '900',
  },
  markAllText: {
    color: colors.navy,
    fontSize: 9,
    fontWeight: '900',
    letterSpacing: 0.35,
  },
  list: {
    gap: 10,
  },
  card: {
    minHeight: 112,
    borderRadius: radius.lg,
    padding: 16,
    flexDirection: 'row',
    alignItems: 'flex-start',
    backgroundColor: colors.white,
    borderWidth: 1,
    borderColor: '#E4E8E1',
  },
  cardUnread: {
    borderColor: colors.lime,
    backgroundColor: '#FCFFF4',
  },
  kindBadge: {
    width: 42,
    height: 42,
    borderRadius: 14,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.canvasMuted,
  },
  kindBadgeUnread: {
    backgroundColor: colors.navy,
  },
  kindSymbol: {
    color: colors.navy,
    fontSize: 12,
    fontWeight: '900',
  },
  kindSymbolUnread: {
    color: colors.lime,
  },
  cardCopy: {
    flex: 1,
    marginLeft: 13,
  },
  cardMeta: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
  },
  kindLabel: {
    color: colors.muted,
    fontSize: 8,
    fontWeight: '900',
    letterSpacing: 0.45,
  },
  timeLabel: {
    color: colors.muted,
    fontSize: 8,
    fontWeight: '800',
  },
  cardTitle: {
    color: colors.navy,
    fontSize: 15,
    fontWeight: '900',
    marginTop: 6,
  },
  cardBody: {
    color: colors.muted,
    fontSize: 12,
    lineHeight: 17,
    marginTop: 4,
  },
  cardAction: {
    width: 18,
    alignItems: 'flex-end',
    marginLeft: 5,
  },
  unreadDot: {
    width: 8,
    height: 8,
    borderRadius: 4,
    backgroundColor: colors.lime,
  },
  cardArrow: {
    color: colors.navy,
    fontSize: 25,
    marginTop: 24,
  },
  stateCard: {
    minHeight: 220,
    borderRadius: radius.xl,
    padding: 24,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.white,
  },
  emptySymbol: {
    width: 54,
    height: 54,
    borderRadius: 27,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.lime,
    marginBottom: 16,
  },
  emptySymbolText: {
    color: colors.navy,
    fontSize: 22,
    fontWeight: '900',
  },
  stateTitle: {
    color: colors.navy,
    fontSize: 18,
    fontWeight: '900',
  },
  stateBody: {
    color: colors.muted,
    fontSize: 13,
    lineHeight: 19,
    textAlign: 'center',
    marginTop: 8,
  },
  errorCard: {
    minHeight: 170,
    borderRadius: radius.xl,
    padding: 24,
    justifyContent: 'center',
    backgroundColor: '#FFF0EF',
  },
  errorTitle: {
    color: colors.danger,
    fontSize: 17,
    fontWeight: '900',
  },
  errorBody: {
    color: colors.navy,
    fontSize: 13,
    lineHeight: 19,
    marginTop: 8,
  },
});
