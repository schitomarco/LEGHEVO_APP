import {
  ActivityIndicator,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  View,
} from 'react-native';
import { SectionTitle } from '../components/SectionTitle';
import { colors, radius, shadow } from '../theme';
import type {
  AppScreen,
  LeagueSummary,
  LiveMatchCenter,
} from '../types';

type Props = {
  displayName: string;
  leagues: LeagueSummary[];
  loading: boolean;
  error: string;
  match: LiveMatchCenter | null;
  matchLoading: boolean;
  matchError: string;
  unreadCount: number;
  onNavigate: (screen: AppScreen) => void;
  onOpenLeague: (leagueId: string) => void;
  onOpenLineup: (leagueId: string) => void;
  onOpenLive: (leagueId: string) => void;
};

export function HomeScreen({
  displayName,
  leagues,
  loading,
  error,
  match,
  matchLoading,
  matchError,
  unreadCount,
  onNavigate,
  onOpenLeague,
  onOpenLineup,
  onOpenLive,
}: Props) {
  const firstName = displayName.trim().split(/\s+/)[0] || 'Mister';
  const initials = displayName
    .trim()
    .split(/\s+/)
    .map((part) => part[0])
    .join('')
    .slice(0, 2)
    .toUpperCase();
  const firstLeague = leagues[0];
  const matchAction = match ? actionForMatch(match) : null;

  return (
    <ScrollView
      style={styles.screen}
      contentContainerStyle={styles.content}
      showsVerticalScrollIndicator={false}
    >
      <View style={styles.headerRow}>
        <SectionTitle eyebrow={`Buongiorno, ${firstName}`} title="Le tue leghe" />
        <View style={styles.headerActions}>
          <Pressable
            accessibilityLabel={
              unreadCount > 0
                ? `${unreadCount} notifiche da leggere`
                : 'Apri notifiche'
            }
            onPress={() => onNavigate('notifications')}
            style={styles.notificationButton}
          >
            <Text style={styles.notificationSymbol}>◎</Text>
            {unreadCount > 0 ? (
              <View style={styles.notificationBadge}>
                <Text style={styles.notificationBadgeText}>
                  {unreadCount > 9 ? '9+' : unreadCount}
                </Text>
              </View>
            ) : null}
          </Pressable>
          <View style={styles.avatar}>
            <Text style={styles.avatarText}>{initials || 'LV'}</Text>
          </View>
        </View>
      </View>

      <View style={styles.leagueHeader}>
        <Text style={styles.leagueHeaderText}>
          {leagues.length === 1
            ? '1 SPOGLIATOIO'
            : `${leagues.length} SPOGLIATOI`}
        </Text>
        <Pressable
          onPress={() => onNavigate('leagueSetup')}
          style={styles.newLeagueButton}
        >
          <Text style={styles.newLeagueText}>＋ NUOVA</Text>
        </Pressable>
      </View>

      {loading ? (
        <View style={styles.loadingCard}>
          <ActivityIndicator color={colors.lime} />
          <Text style={styles.loadingText}>Controllo gli spogliatoi…</Text>
        </View>
      ) : error ? (
        <View style={styles.emptyCard}>
          <Text style={styles.emptyTitle}>Connessione in panchina</Text>
          <Text style={styles.emptyBody}>{error}</Text>
        </View>
      ) : leagues.length === 0 ? (
        <Pressable
          onPress={() => onNavigate('leagueSetup')}
          style={styles.emptyCard}
        >
          <View style={styles.emptyIcon}>
            <Text style={styles.emptyIconText}>L</Text>
          </View>
          <Text style={styles.emptyTitle}>Qui non vola ancora una diffida</Text>
          <Text style={styles.emptyBody}>
            Crea una lega oppure entra con il codice ricevuto dal presidente.
          </Text>
          <View style={styles.emptyCta}>
            <Text style={styles.emptyCtaText}>INIZIA ORA →</Text>
          </View>
        </Pressable>
      ) : (
        <View style={styles.leagueList}>
          {leagues.map((league) => (
            <LeagueCard
              key={league.id}
              league={league}
              onPress={() => onOpenLeague(league.id)}
            />
          ))}
        </View>
      )}

      {firstLeague ? (
        <>
          <View style={styles.matchSectionHeader}>
            <Text style={styles.sectionTitle}>
              {match?.status === 'final' ? 'Ultimo risultato' : 'Prossima sfida'}
            </Text>
            {match ? (
              <View
                style={[
                  styles.statusPill,
                  match.status === 'live' && styles.statusPillLive,
                ]}
              >
                <Text style={styles.statusPillText}>
                  {matchStatusLabel(match)}
                </Text>
              </View>
            ) : null}
          </View>
          <View style={styles.matchCard}>
            {matchLoading ? (
              <View style={styles.matchLoading}>
                <ActivityIndicator color={colors.navy} />
                <Text style={styles.matchLoadingText}>
                  Cerco la prossima figuraccia…
                </Text>
              </View>
            ) : match ? (
              <>
                <Text style={styles.matchMeta}>
                  GIORNATA {match.matchday.number} ·{' '}
                  {formatMatchDate(match.matchday.startsAt)}
                </Text>
                <View style={styles.matchRow}>
                  <TeamBadge
                    active={match.home.teamId === match.myTeamId}
                    initials={teamInitials(match.home.name)}
                    label={match.home.name}
                  />
                  <View style={styles.matchScore}>
                    <Text style={styles.vs}>
                      {match.status === 'upcoming'
                        ? 'VS'
                        : `${formatGoals(match.home.goals)}–${formatGoals(
                            match.away.goals,
                          )}`}
                    </Text>
                    {match.status !== 'upcoming' ? (
                      <Text style={styles.matchPoints}>
                        {formatPoints(match.home.points)} ·{' '}
                        {formatPoints(match.away.points)} PT
                      </Text>
                    ) : null}
                  </View>
                  <TeamBadge
                    active={match.away.teamId === match.myTeamId}
                    initials={teamInitials(match.away.name)}
                    label={match.away.name}
                  />
                </View>
              </>
            ) : (
              <View style={styles.waitingMatch}>
                <Text style={styles.waitingMatchTitle}>
                  {matchError
                    ? 'La giornata non risponde'
                    : 'Calendario in riscaldamento'}
                </Text>
                <Text style={styles.waitingMatchBody}>
                  {matchError
                    ? matchError
                    : 'Appena lo spogliatoio è completo generiamo gli scontri diretti.'}
                </Text>
              </View>
            )}
          </View>

          <Pressable
            onPress={() => {
              if (matchAction === 'lineup') {
                onOpenLineup(firstLeague.id);
              } else if (matchAction === 'live') {
                onOpenLive(firstLeague.id);
              } else {
                onOpenLeague(firstLeague.id);
              }
            }}
            style={styles.lineupButton}
          >
            <Text style={styles.lineupText}>
              {matchAction === 'lineup'
                ? 'Schiera la formazione'
                : matchAction === 'live'
                  ? match?.status === 'final'
                    ? 'Rivedi il risultato'
                    : 'Segui il Live'
                  : 'Apri la tua lega'}
            </Text>
            <Text style={styles.lineupArrow}>→</Text>
          </Pressable>
        </>
      ) : null}

      <Pressable
        onPress={() => onNavigate('leagueSetup')}
        style={styles.noticeCard}
      >
        <View style={styles.noticeIcon}>
          <Text style={styles.noticeIconText}>+</Text>
        </View>
        <View style={styles.noticeCopy}>
          <Text style={styles.noticeTitle}>Invita il gruppo del lunedì</Text>
          <Text style={styles.noticeBody}>
            Crea la lega. Per gli sfottò siete già autonomi.
          </Text>
        </View>
      </Pressable>
    </ScrollView>
  );
}

function LeagueCard({
  league,
  onPress,
}: {
  league: LeagueSummary;
  onPress: () => void;
}) {
  return (
    <Pressable onPress={onPress} style={styles.leagueCard}>
      <View style={styles.leagueTopRow}>
        <View style={styles.activePill}>
          <Text style={styles.activePillText}>
            {leagueStatusLabel(league.status)}
          </Text>
        </View>
        <Text style={styles.modeLabel}>
          {league.mode === 'classic' ? 'CLASSICO' : 'MANTRA'}
          {league.season ? ` · ${league.season}` : ''}
        </Text>
      </View>
      <Text style={styles.leagueName}>{league.name}</Text>
      <Text style={styles.leagueMeta}>
        {league.memberCount}/{league.teamLimit} partecipanti
      </Text>
      <View style={styles.divider} />
      <View style={styles.teamRow}>
        <View>
          <Text style={styles.teamLabel}>LA TUA SQUADRA</Text>
          <Text style={styles.teamName}>
            {league.team?.name ?? 'Squadra da completare'}
          </Text>
        </View>
        <Text style={styles.position}>→</Text>
      </View>
    </Pressable>
  );
}

function leagueStatusLabel(status: LeagueSummary['status']) {
  if (status === 'active') {
    return 'LEGA ATTIVA';
  }
  if (status === 'completed') {
    return 'STAGIONE CONCLUSA';
  }
  if (status === 'archived') {
    return 'STAGIONE ARCHIVIATA';
  }
  return 'IN PREPARAZIONE';
}

function TeamBadge({
  initials,
  label,
  active,
}: {
  initials: string;
  label: string;
  active?: boolean;
}) {
  return (
    <View style={styles.badgeWrapper}>
      <View style={[styles.teamBadge, active && styles.teamBadgeActive]}>
        <Text style={[styles.teamBadgeText, active && styles.teamBadgeTextActive]}>
          {initials}
        </Text>
      </View>
      <Text numberOfLines={1} style={styles.teamBadgeLabel}>
        {label}
      </Text>
    </View>
  );
}

function actionForMatch(match: LiveMatchCenter): 'lineup' | 'live' {
  if (
    match.status === 'upcoming' &&
    new Date(match.matchday.locksAt).getTime() > Date.now()
  ) {
    return 'lineup';
  }
  return 'live';
}

function matchStatusLabel(match: LiveMatchCenter) {
  if (match.status === 'live') {
    return 'LIVE';
  }
  if (match.status === 'pending') {
    return 'IN CALCOLO';
  }
  if (match.status === 'final') {
    return 'FINALE';
  }
  return new Date(match.matchday.locksAt).getTime() > Date.now()
    ? 'DA SCHIERARE'
    : 'BLOCCATA';
}

function formatMatchDate(value: string) {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) {
    return 'ORARIO DA DEFINIRE';
  }
  return new Intl.DateTimeFormat('it-IT', {
    weekday: 'short',
    day: '2-digit',
    month: 'short',
    hour: '2-digit',
    minute: '2-digit',
  })
    .format(date)
    .replace(',', ' ·')
    .toUpperCase();
}

function teamInitials(name: string) {
  return name
    .trim()
    .split(/\s+/)
    .map((part) => part[0])
    .join('')
    .slice(0, 2)
    .toUpperCase();
}

function formatGoals(value: number | null) {
  return value === null ? '–' : String(value);
}

function formatPoints(value: number | null) {
  return value === null
    ? '—'
    : value.toFixed(1).replace('.', ',');
}

const styles = StyleSheet.create({
  screen: {
    flex: 1,
    backgroundColor: colors.canvas,
  },
  content: {
    paddingHorizontal: 20,
    paddingTop: 22,
    paddingBottom: 30,
  },
  headerRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    marginBottom: 18,
  },
  headerActions: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 9,
  },
  notificationButton: {
    width: 42,
    height: 42,
    borderRadius: 21,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.white,
  },
  notificationSymbol: {
    color: colors.navy,
    fontSize: 20,
    fontWeight: '900',
  },
  notificationBadge: {
    position: 'absolute',
    top: -2,
    right: -2,
    minWidth: 18,
    height: 18,
    borderRadius: 9,
    paddingHorizontal: 4,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.lime,
    borderWidth: 2,
    borderColor: colors.canvas,
  },
  notificationBadgeText: {
    color: colors.navy,
    fontSize: 8,
    fontWeight: '900',
  },
  avatar: {
    width: 46,
    height: 46,
    borderRadius: 23,
    backgroundColor: colors.navy,
    alignItems: 'center',
    justifyContent: 'center',
  },
  avatarText: {
    color: colors.lime,
    fontSize: 13,
    fontWeight: '900',
  },
  leagueHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    marginBottom: 11,
  },
  leagueHeaderText: {
    color: colors.muted,
    fontSize: 10,
    fontWeight: '900',
    letterSpacing: 0.45,
  },
  newLeagueButton: {
    height: 32,
    paddingHorizontal: 13,
    borderRadius: 16,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.lime,
  },
  newLeagueText: {
    color: colors.navy,
    fontSize: 10,
    fontWeight: '900',
  },
  leagueList: {
    gap: 12,
  },
  leagueCard: {
    borderRadius: radius.xl,
    padding: 22,
    backgroundColor: colors.navy,
  },
  leagueTopRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
  },
  activePill: {
    alignSelf: 'flex-start',
    paddingHorizontal: 13,
    height: 27,
    borderRadius: 14,
    backgroundColor: colors.lime,
    justifyContent: 'center',
  },
  activePillText: {
    color: colors.navy,
    fontSize: 9,
    fontWeight: '900',
  },
  modeLabel: {
    color: colors.mutedLight,
    fontSize: 9,
    fontWeight: '900',
  },
  leagueName: {
    color: colors.warmWhite,
    fontSize: 22,
    fontWeight: '900',
    marginTop: 18,
  },
  leagueMeta: {
    color: colors.mutedLight,
    fontSize: 14,
    marginTop: 6,
  },
  divider: {
    height: 1,
    backgroundColor: colors.navyLine,
    marginVertical: 18,
  },
  teamRow: {
    flexDirection: 'row',
    alignItems: 'flex-end',
    justifyContent: 'space-between',
  },
  teamLabel: {
    color: colors.mutedLight,
    fontSize: 10,
    fontWeight: '800',
    letterSpacing: 0.4,
  },
  teamName: {
    color: colors.warmWhite,
    fontSize: 16,
    fontWeight: '800',
    marginTop: 5,
  },
  position: {
    color: colors.lime,
    fontSize: 27,
    fontWeight: '700',
  },
  loadingCard: {
    minHeight: 180,
    borderRadius: radius.xl,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.navy,
    gap: 12,
  },
  loadingText: {
    color: colors.mutedLight,
    fontSize: 12,
    fontWeight: '700',
  },
  emptyCard: {
    minHeight: 230,
    borderRadius: radius.xl,
    alignItems: 'center',
    justifyContent: 'center',
    padding: 25,
    backgroundColor: colors.navy,
  },
  emptyIcon: {
    width: 52,
    height: 52,
    borderRadius: 18,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.lime,
  },
  emptyIconText: {
    color: colors.navy,
    fontSize: 23,
    fontWeight: '900',
  },
  emptyTitle: {
    color: colors.warmWhite,
    fontSize: 18,
    fontWeight: '900',
    textAlign: 'center',
    marginTop: 17,
  },
  emptyBody: {
    color: colors.mutedLight,
    fontSize: 13,
    lineHeight: 19,
    textAlign: 'center',
    marginTop: 8,
  },
  emptyCta: {
    marginTop: 18,
    paddingHorizontal: 16,
    height: 34,
    borderRadius: 17,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.lime,
  },
  emptyCtaText: {
    color: colors.navy,
    fontSize: 10,
    fontWeight: '900',
  },
  sectionTitle: {
    color: colors.navy,
    fontSize: 21,
    fontWeight: '900',
  },
  matchSectionHeader: {
    marginTop: 24,
    marginBottom: 12,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
  },
  statusPill: {
    height: 25,
    borderRadius: 13,
    paddingHorizontal: 11,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.canvasMuted,
  },
  statusPillLive: {
    backgroundColor: colors.lime,
  },
  statusPillText: {
    color: colors.navy,
    fontSize: 8,
    fontWeight: '900',
  },
  matchCard: {
    backgroundColor: colors.white,
    borderRadius: radius.lg,
    padding: 20,
    ...shadow,
  },
  matchMeta: {
    color: colors.muted,
    fontSize: 10,
    fontWeight: '800',
  },
  matchRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-around',
    marginTop: 18,
  },
  matchLoading: {
    minHeight: 120,
    alignItems: 'center',
    justifyContent: 'center',
    gap: 10,
  },
  matchLoadingText: {
    color: colors.muted,
    fontSize: 11,
    fontWeight: '700',
  },
  matchScore: {
    alignItems: 'center',
    minWidth: 70,
  },
  matchPoints: {
    color: colors.muted,
    fontSize: 9,
    fontWeight: '800',
    marginTop: 5,
  },
  badgeWrapper: {
    alignItems: 'center',
    minWidth: 88,
  },
  teamBadge: {
    width: 58,
    height: 58,
    borderRadius: 29,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.canvasMuted,
  },
  teamBadgeActive: {
    backgroundColor: colors.navy,
  },
  teamBadgeText: {
    color: colors.navy,
    fontSize: 13,
    fontWeight: '900',
  },
  teamBadgeTextActive: {
    color: colors.lime,
  },
  teamBadgeLabel: {
    color: colors.navy,
    fontSize: 10,
    fontWeight: '800',
    marginTop: 9,
    maxWidth: 100,
  },
  vs: {
    color: colors.navy,
    fontSize: 18,
    fontWeight: '900',
  },
  waitingMatch: {
    minHeight: 86,
    justifyContent: 'center',
  },
  waitingMatchTitle: {
    color: colors.navy,
    fontSize: 16,
    fontWeight: '900',
  },
  waitingMatchBody: {
    color: colors.muted,
    fontSize: 12,
    lineHeight: 18,
    marginTop: 7,
  },
  lineupButton: {
    height: 64,
    borderRadius: radius.lg,
    marginTop: 18,
    paddingHorizontal: 20,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    backgroundColor: colors.lime,
  },
  lineupText: {
    color: colors.navy,
    fontSize: 15,
    fontWeight: '900',
  },
  lineupArrow: {
    color: colors.navy,
    fontSize: 25,
    fontWeight: '700',
  },
  noticeCard: {
    borderRadius: radius.lg,
    marginTop: 18,
    padding: 18,
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: colors.white,
  },
  noticeIcon: {
    width: 42,
    height: 42,
    borderRadius: 15,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.navy,
  },
  noticeIconText: {
    color: colors.lime,
    fontSize: 21,
    fontWeight: '900',
  },
  noticeCopy: {
    flex: 1,
    marginLeft: 14,
  },
  noticeTitle: {
    color: colors.navy,
    fontSize: 14,
    fontWeight: '900',
  },
  noticeBody: {
    color: colors.muted,
    fontSize: 12,
    marginTop: 5,
  },
});
