import {
  ActivityIndicator,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  View,
} from 'react-native';
import { useLeagueMatchup } from '../hooks/useLeagueMatchup';
import { colors, radius, shadow } from '../theme';
import type {
  AppScreen,
  LeagueSummary,
  MatchupFixture,
  MatchupFormResult,
  MatchupLineupStatus,
  MatchupMeeting,
  MatchupRecord,
  MatchupTeam,
} from '../types';

type Props = {
  league: LeagueSummary | null;
  onNavigate: (screen: AppScreen) => void;
};

export function MatchupScreen({ league, onNavigate }: Props) {
  const matchup = useLeagueMatchup(league);

  if (!league) {
    return (
      <View style={styles.centerRoot}>
        <Text style={styles.centerTitle}>Prima scegli una lega.</Text>
        <Pressable
          onPress={() => onNavigate('home')}
          style={styles.primaryButton}
        >
          <Text style={styles.primaryButtonText}>TORNA ALLA HOME</Text>
        </Pressable>
      </View>
    );
  }

  if (matchup.loading && !matchup.center) {
    return (
      <View style={styles.centerRoot}>
        <ActivityIndicator color={colors.navy} size="large" />
        <Text style={styles.centerTitle}>Studio l’avversario…</Text>
        <Text style={styles.centerBody}>
          Precedenti, forma e numeri stanno entrando nello spogliatoio.
        </Text>
      </View>
    );
  }

  if (matchup.error && !matchup.center) {
    return (
      <View style={styles.centerRoot}>
        <Text style={styles.errorEyebrow}>CENTRO SFIDA IN PANCHINA</Text>
        <Text style={styles.centerTitle}>Prepartita non disponibile</Text>
        <Text style={styles.centerBody}>{matchup.error}</Text>
        <Pressable
          onPress={() => void matchup.refresh()}
          style={styles.primaryButton}
        >
          <Text style={styles.primaryButtonText}>RIPROVA</Text>
        </Pressable>
        <Pressable
          onPress={() => onNavigate('league')}
          style={styles.secondaryButton}
        >
          <Text style={styles.secondaryButtonText}>TORNA ALLA LEGA</Text>
        </Pressable>
      </View>
    );
  }

  const center = matchup.center;
  if (!center) {
    return null;
  }

  return (
    <ScrollView
      style={styles.screen}
      contentContainerStyle={styles.content}
      showsVerticalScrollIndicator={false}
    >
      <View style={styles.header}>
        <Pressable
          accessibilityLabel="Torna alla lega"
          onPress={() => onNavigate('league')}
          style={styles.backButton}
        >
          <Text style={styles.backText}>‹</Text>
        </Pressable>
        <View style={styles.headerCopy}>
          <Text style={styles.eyebrow}>
            {center.season ? `STAGIONE ${center.season}` : 'PREPARTITA'}
          </Text>
          <Text style={styles.title}>Centro Sfida</Text>
        </View>
        <Pressable
          accessibilityLabel="Aggiorna Centro Sfida"
          accessibilityState={{
            busy: matchup.loading,
            disabled: matchup.loading,
          }}
          disabled={matchup.loading}
          onPress={() => void matchup.refresh()}
          style={[
            styles.refreshButton,
            matchup.loading && styles.refreshButtonDisabled,
          ]}
        >
          {matchup.loading ? (
            <ActivityIndicator color={colors.navy} size="small" />
          ) : (
            <Text style={styles.refreshText}>↻</Text>
          )}
        </Pressable>
      </View>

      {!center.fixture || !center.opponent ? (
        <View style={styles.emptyCard}>
          <View style={styles.emptyIcon}>
            <Text style={styles.emptyIconText}>VS</Text>
          </View>
          <Text style={styles.emptyTitle}>Avversario da sorteggiare</Text>
          <Text style={styles.emptyBody}>
            Il Centro Sfida si accende appena il calendario assegna la prima
            partita.
          </Text>
          <Pressable
            onPress={() => onNavigate('calendar')}
            style={styles.darkButton}
          >
            <Text style={styles.darkButtonText}>APRI IL CALENDARIO →</Text>
          </Pressable>
        </View>
      ) : (
        <>
          <MatchHero
            fixture={center.fixture}
            myTeam={center.myTeam}
            opponent={center.opponent}
          />

          <LineupPrivacyCard
            locked={center.fixture.lineupsLocked}
            myStatus={center.fixture.myLineupStatus}
            opponentStatus={center.fixture.opponentLineupStatus}
            onOpenLineup={() => onNavigate('lineup')}
            onOpenLive={() => onNavigate('live')}
            status={center.fixture.status}
          />

          <Text style={styles.sectionTitle}>Confronto</Text>
          <View style={styles.comparisonCard}>
            <TeamComparison
              active
              team={center.myTeam}
              title="LA TUA SQUADRA"
            />
            <View style={styles.comparisonDivider} />
            <TeamComparison team={center.opponent} title="AVVERSARIO" />
          </View>

          <Text style={styles.sectionTitle}>Precedenti diretti</Text>
          <RivalryCard
            currentSeason={center.currentSeason}
            history={center.allTime}
            myName={center.myTeam.name}
            opponentName={center.opponent.name}
          />

          <View style={styles.historyHeader}>
            <Text style={styles.sectionTitle}>Ultime sfide</Text>
            <Text style={styles.historyCount}>
              {center.lastMeetings.length} RISULTATI
            </Text>
          </View>
          <View style={styles.meetingsCard}>
            {center.lastMeetings.length > 0 ? (
              center.lastMeetings.map((meeting) => (
                <MeetingRow key={meeting.fixtureId} meeting={meeting} />
              ))
            ) : (
              <View style={styles.noMeeting}>
                <Text style={styles.noMeetingTitle}>Prima volta faccia a faccia</Text>
                <Text style={styles.noMeetingBody}>
                  Nessun risultato ufficiale tra questi due manager.
                </Text>
              </View>
            )}
          </View>
        </>
      )}
    </ScrollView>
  );
}

function MatchHero({
  fixture,
  myTeam,
  opponent,
}: {
  fixture: MatchupFixture;
  myTeam: MatchupTeam;
  opponent: MatchupTeam;
}) {
  if (!fixture) {
    return null;
  }

  const home = fixture.myHome ? myTeam : opponent;
  const away = fixture.myHome ? opponent : myTeam;
  const showScore = fixture.status !== 'upcoming';
  const homeGoals = fixture.myHome ? fixture.myGoals : fixture.opponentGoals;
  const awayGoals = fixture.myHome ? fixture.opponentGoals : fixture.myGoals;
  const homePoints = fixture.myHome ? fixture.myPoints : fixture.opponentPoints;
  const awayPoints = fixture.myHome ? fixture.opponentPoints : fixture.myPoints;

  return (
    <View style={styles.heroCard}>
      <View style={styles.heroTop}>
        <Text style={styles.heroMeta}>
          GIORNATA {fixture.matchdayNumber} · {formatMatchDate(fixture.startsAt)}
        </Text>
        <View
          style={[
            styles.statusPill,
            fixture.status === 'live' && styles.statusPillLive,
            fixture.status === 'final' && styles.statusPillFinal,
          ]}
        >
          <Text style={styles.statusPillText}>
            {fixtureStatusLabel(fixture.status)}
          </Text>
        </View>
      </View>
      <View style={styles.versusRow}>
        <HeroTeam team={home} />
        <View style={styles.scoreBlock}>
          <Text style={styles.heroScore}>
            {showScore
              ? `${formatGoals(homeGoals)}–${formatGoals(awayGoals)}`
              : 'VS'}
          </Text>
          {showScore ? (
            <Text style={styles.heroPoints}>
              {formatPoints(homePoints)} · {formatPoints(awayPoints)} PT
            </Text>
          ) : (
            <Text style={styles.heroVenue}>CASA · TRASFERTA</Text>
          )}
        </View>
        <HeroTeam team={away} />
      </View>
      <View style={styles.lockBar}>
        <Text style={styles.lockLabel}>BLOCCO FORMAZIONI</Text>
        <Text style={styles.lockValue}>{formatLockDate(fixture.locksAt)}</Text>
      </View>
    </View>
  );
}

function HeroTeam({ team }: { team: MatchupTeam }) {
  return (
    <View style={styles.heroTeam}>
      <View style={styles.heroBadge}>
        <Text style={styles.heroBadgeText}>{teamInitials(team.name)}</Text>
      </View>
      <Text numberOfLines={2} style={styles.heroTeamName}>
        {team.name}
      </Text>
      <Text numberOfLines={1} style={styles.heroManager}>
        {team.managerName}
      </Text>
    </View>
  );
}

function LineupPrivacyCard({
  locked,
  myStatus,
  opponentStatus,
  status,
  onOpenLineup,
  onOpenLive,
}: {
  locked: boolean;
  myStatus: MatchupLineupStatus;
  opponentStatus: MatchupLineupStatus;
  status: 'upcoming' | 'live' | 'pending' | 'final';
  onOpenLineup: () => void;
  onOpenLive: () => void;
}) {
  return (
    <View style={styles.lineupCard}>
      <View style={styles.lineupHeader}>
        <View>
          <Text style={styles.lineupEyebrow}>DISTINTE PROTETTE</Text>
          <Text style={styles.lineupTitle}>
            {locked ? 'Formazioni bloccate' : 'Stato consegne'}
          </Text>
        </View>
        <View style={styles.shieldBadge}>
          <Text style={styles.shieldText}>{locked ? 'OK' : '••'}</Text>
        </View>
      </View>
      <View style={styles.lineupStatusRow}>
        <LineupStatus label="TU" status={myStatus} />
        <LineupStatus label="AVVERSARIO" status={opponentStatus} />
      </View>
      <Text style={styles.lineupPrivacy}>
        {locked
          ? 'Il blocco è scattato. Moduli e calciatori si consultano nel Live.'
          : 'Prima della scadenza LEGHEVO mostra soltanto lo stato: nessun modulo e nessun calciatore avversario.'}
      </Text>
      <Pressable
        onPress={status === 'upcoming' ? onOpenLineup : onOpenLive}
        style={styles.lineupButton}
      >
        <Text style={styles.lineupButtonText}>
          {status === 'upcoming' ? 'CONTROLLA LA TUA FORMAZIONE' : 'APRI IL LIVE'}
        </Text>
        <Text style={styles.lineupButtonArrow}>→</Text>
      </Pressable>
    </View>
  );
}

function LineupStatus({
  label,
  status,
}: {
  label: string;
  status: MatchupLineupStatus;
}) {
  const ready = status === 'submitted' || status === 'carried';
  return (
    <View style={styles.lineupStatus}>
      <Text style={styles.lineupStatusLabel}>{label}</Text>
      <View style={styles.lineupStatusValueRow}>
        <View
          style={[
            styles.lineupStatusDot,
            ready && styles.lineupStatusDotReady,
          ]}
        />
        <Text
          style={[
            styles.lineupStatusValue,
            ready && styles.lineupStatusValueReady,
          ]}
        >
          {lineupStatusLabel(status)}
        </Text>
      </View>
    </View>
  );
}

function TeamComparison({
  team,
  title,
  active = false,
}: {
  team: MatchupTeam;
  title: string;
  active?: boolean;
}) {
  return (
    <View style={styles.comparisonTeam}>
      <Text style={[styles.comparisonEyebrow, active && styles.activeText]}>
        {title}
      </Text>
      <Text numberOfLines={1} style={styles.comparisonName}>
        {team.name}
      </Text>
      <View style={styles.positionRow}>
        <Text style={styles.positionValue}>
          {team.position > 0 ? `${team.position}°` : '—'}
        </Text>
        <Text style={styles.positionLabel}>POSTO</Text>
      </View>
      <CompareStat label="PUNTI" value={team.leaguePoints} />
      <CompareStat label="FANTAPUNTI" value={formatNumber(team.pointsFor)} />
      <CompareStat label="GOL" value={`${team.goalsFor}:${team.goalsAgainst}`} />
      <View style={styles.formBlock}>
        <Text style={styles.formLabel}>ULTIME 5</Text>
        <FormDots form={team.recentForm} />
      </View>
      <Text style={styles.streakText}>
        {team.unbeatenStreak > 0
          ? `${team.unbeatenStreak} senza sconfitte`
          : 'Serie da riaprire'}
      </Text>
    </View>
  );
}

function CompareStat({
  label,
  value,
}: {
  label: string;
  value: string | number;
}) {
  return (
    <View style={styles.compareStat}>
      <Text style={styles.compareStatLabel}>{label}</Text>
      <Text style={styles.compareStatValue}>{value}</Text>
    </View>
  );
}

function FormDots({ form }: { form: MatchupFormResult[] }) {
  if (form.length === 0) {
    return <Text style={styles.noForm}>—</Text>;
  }
  return (
    <View style={styles.formRow}>
      {form.map((result, index) => (
        <View
          key={`${result}-${index}`}
          style={[
            styles.formDot,
            result === 'W' && styles.formWin,
            result === 'D' && styles.formDraw,
            result === 'L' && styles.formLoss,
          ]}
        >
          <Text style={styles.formDotText}>
            {result === 'W' ? 'V' : result === 'D' ? 'P' : 'S'}
          </Text>
        </View>
      ))}
    </View>
  );
}

function RivalryCard({
  currentSeason,
  history,
  myName,
  opponentName,
}: {
  currentSeason: MatchupRecord;
  history: MatchupRecord & {
    seasons: number;
    leader: 'me' | 'opponent' | 'level';
  };
  myName: string;
  opponentName: string;
}) {
  const leader =
    history.leader === 'me'
      ? myName
      : history.leader === 'opponent'
        ? opponentName
        : 'Perfetta parità';

  return (
    <View style={styles.rivalryCard}>
      <View style={styles.rivalryTop}>
        <View>
          <Text style={styles.rivalryEyebrow}>BILANCIO STORICO</Text>
          <Text style={styles.rivalryLeader}>{leader}</Text>
        </View>
        <View style={styles.seasonBadge}>
          <Text style={styles.seasonBadgeValue}>{history.seasons}</Text>
          <Text style={styles.seasonBadgeLabel}>STAGIONI</Text>
        </View>
      </View>
      <RecordBar
        draws={history.draws}
        label="TUTTE LE STAGIONI"
        myWins={history.myWins}
        opponentWins={history.opponentWins}
        played={history.played}
      />
      <View style={styles.rivalryDivider} />
      <RecordBar
        draws={currentSeason.draws}
        label="STAGIONE CORRENTE"
        myWins={currentSeason.myWins}
        opponentWins={currentSeason.opponentWins}
        played={currentSeason.played}
      />
      <View style={styles.rivalryNumbers}>
        <View>
          <Text style={styles.rivalryNumber}>
            {history.myGoals}–{history.opponentGoals}
          </Text>
          <Text style={styles.rivalryNumberLabel}>GOL STORICI</Text>
        </View>
        <View style={styles.rivalryNumberRight}>
          <Text style={styles.rivalryNumber}>
            {formatNumber(history.myPoints)}–{formatNumber(history.opponentPoints)}
          </Text>
          <Text style={styles.rivalryNumberLabel}>FANTAPUNTI</Text>
        </View>
      </View>
    </View>
  );
}

function RecordBar({
  label,
  played,
  myWins,
  draws,
  opponentWins,
}: {
  label: string;
  played: number;
  myWins: number;
  draws: number;
  opponentWins: number;
}) {
  return (
    <View style={styles.recordBlock}>
      <View style={styles.recordHeader}>
        <Text style={styles.recordLabel}>{label}</Text>
        <Text style={styles.recordPlayed}>{played} PARTITE</Text>
      </View>
      <View style={styles.recordValues}>
        <Text style={styles.recordValue}>{myWins} V</Text>
        <Text style={styles.recordValueMuted}>{draws} P</Text>
        <Text style={styles.recordValueOpponent}>{opponentWins} V</Text>
      </View>
      <View style={styles.recordTrack}>
        <View
          style={[
            styles.recordTrackMine,
            { flex: played > 0 ? Math.max(myWins, 0.2) : 1 },
          ]}
        />
        <View
          style={[
            styles.recordTrackDraw,
            { flex: played > 0 ? Math.max(draws, 0.2) : 1 },
          ]}
        />
        <View
          style={[
            styles.recordTrackOpponent,
            { flex: played > 0 ? Math.max(opponentWins, 0.2) : 1 },
          ]}
        />
      </View>
    </View>
  );
}

function MeetingRow({ meeting }: { meeting: MatchupMeeting }) {
  const homeGoals = meeting.myHome ? meeting.myGoals : meeting.opponentGoals;
  const awayGoals = meeting.myHome ? meeting.opponentGoals : meeting.myGoals;
  return (
    <View style={styles.meetingRow}>
      <View
        style={[
          styles.outcomeBadge,
          meeting.outcome === 'W' && styles.outcomeWin,
          meeting.outcome === 'L' && styles.outcomeLoss,
        ]}
      >
        <Text style={styles.outcomeText}>
          {meeting.outcome === 'W' ? 'V' : meeting.outcome === 'D' ? 'P' : 'S'}
        </Text>
      </View>
      <View style={styles.meetingCopy}>
        <Text numberOfLines={1} style={styles.meetingTeams}>
          {meeting.homeTeamName} · {meeting.awayTeamName}
        </Text>
        <Text style={styles.meetingMeta}>
          {meeting.season ?? 'STAGIONE'} · G{meeting.matchdayNumber} ·{' '}
          {formatShortDate(meeting.startsAt)}
        </Text>
      </View>
      <View style={styles.meetingScore}>
        <Text style={styles.meetingGoals}>
          {homeGoals}–{awayGoals}
        </Text>
        <Text style={styles.meetingPoints}>
          {formatNumber(meeting.myPoints)} PT
        </Text>
      </View>
    </View>
  );
}

function fixtureStatusLabel(status: 'upcoming' | 'live' | 'pending' | 'final') {
  if (status === 'live') return 'LIVE';
  if (status === 'pending') return 'IN CALCOLO';
  if (status === 'final') return 'FINALE';
  return 'PROSSIMA';
}

function lineupStatusLabel(status: MatchupLineupStatus) {
  if (status === 'submitted') return 'CONSEGNATA';
  if (status === 'carried') return 'RECUPERATA';
  if (status === 'draft') return 'BOZZA';
  return 'MANCANTE';
}

function teamInitials(name: string) {
  return name
    .split(/\s+/)
    .filter(Boolean)
    .slice(0, 2)
    .map((part) => part[0])
    .join('')
    .toUpperCase();
}

function formatMatchDate(value: string) {
  return new Intl.DateTimeFormat('it-IT', {
    weekday: 'short',
    day: '2-digit',
    month: 'short',
    hour: '2-digit',
    minute: '2-digit',
  })
    .format(new Date(value))
    .toUpperCase();
}

function formatLockDate(value: string) {
  return new Intl.DateTimeFormat('it-IT', {
    day: '2-digit',
    month: 'short',
    hour: '2-digit',
    minute: '2-digit',
  })
    .format(new Date(value))
    .toUpperCase();
}

function formatShortDate(value: string) {
  return new Intl.DateTimeFormat('it-IT', {
    day: '2-digit',
    month: 'short',
  })
    .format(new Date(value))
    .toUpperCase();
}

function formatGoals(value: number | null) {
  return value === null ? '—' : String(value);
}

function formatPoints(value: number | null) {
  return value === null ? '—' : formatNumber(value);
}

function formatNumber(value: number) {
  return new Intl.NumberFormat('it-IT', {
    maximumFractionDigits: 2,
  }).format(value);
}

const styles = StyleSheet.create({
  screen: {
    flex: 1,
    backgroundColor: colors.canvas,
  },
  content: {
    paddingHorizontal: 20,
    paddingTop: 20,
    paddingBottom: 44,
  },
  centerRoot: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    paddingHorizontal: 28,
    backgroundColor: colors.canvas,
  },
  centerTitle: {
    marginTop: 14,
    color: colors.navy,
    fontSize: 24,
    fontWeight: '900',
    textAlign: 'center',
  },
  centerBody: {
    marginTop: 8,
    color: colors.muted,
    fontSize: 14,
    lineHeight: 21,
    textAlign: 'center',
  },
  errorEyebrow: {
    color: colors.danger,
    fontSize: 10,
    fontWeight: '900',
    letterSpacing: 1,
  },
  primaryButton: {
    marginTop: 22,
    minWidth: 190,
    paddingVertical: 15,
    paddingHorizontal: 22,
    borderRadius: radius.md,
    backgroundColor: colors.lime,
    alignItems: 'center',
  },
  primaryButtonText: {
    color: colors.navy,
    fontSize: 11,
    fontWeight: '900',
    letterSpacing: 0.7,
  },
  secondaryButton: {
    marginTop: 10,
    paddingVertical: 12,
  },
  secondaryButtonText: {
    color: colors.navy,
    fontSize: 11,
    fontWeight: '800',
  },
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    marginBottom: 20,
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
    marginTop: -3,
    color: colors.navy,
    fontSize: 32,
    lineHeight: 34,
  },
  headerCopy: {
    flex: 1,
    marginLeft: 13,
  },
  eyebrow: {
    color: colors.muted,
    fontSize: 9,
    fontWeight: '900',
    letterSpacing: 1.1,
  },
  title: {
    marginTop: 2,
    color: colors.navy,
    fontSize: 27,
    fontWeight: '900',
  },
  refreshButton: {
    width: 42,
    height: 42,
    borderRadius: 21,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.white,
  },
  refreshButtonDisabled: {
    opacity: 0.65,
  },
  refreshText: {
    color: colors.navy,
    fontSize: 22,
    fontWeight: '800',
  },
  heroCard: {
    overflow: 'hidden',
    padding: 20,
    borderRadius: radius.xl,
    backgroundColor: colors.navy,
    ...shadow,
  },
  heroTop: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
  },
  heroMeta: {
    flex: 1,
    color: colors.mutedLight,
    fontSize: 9,
    fontWeight: '900',
    letterSpacing: 0.7,
  },
  statusPill: {
    paddingVertical: 6,
    paddingHorizontal: 10,
    borderRadius: 999,
    backgroundColor: colors.lime,
  },
  statusPillLive: {
    backgroundColor: colors.danger,
  },
  statusPillFinal: {
    backgroundColor: colors.white,
  },
  statusPillText: {
    color: colors.navy,
    fontSize: 9,
    fontWeight: '900',
    letterSpacing: 0.5,
  },
  versusRow: {
    flexDirection: 'row',
    alignItems: 'center',
    marginTop: 24,
  },
  heroTeam: {
    flex: 1,
    alignItems: 'center',
  },
  heroBadge: {
    width: 58,
    height: 58,
    borderRadius: 29,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.navySoft,
    borderWidth: 2,
    borderColor: colors.lime,
  },
  heroBadgeText: {
    color: colors.white,
    fontSize: 17,
    fontWeight: '900',
  },
  heroTeamName: {
    minHeight: 35,
    marginTop: 10,
    color: colors.white,
    fontSize: 13,
    lineHeight: 16,
    fontWeight: '900',
    textAlign: 'center',
  },
  heroManager: {
    marginTop: 3,
    color: colors.mutedLight,
    fontSize: 10,
    textAlign: 'center',
  },
  scoreBlock: {
    width: 80,
    alignItems: 'center',
  },
  heroScore: {
    color: colors.lime,
    fontSize: 30,
    fontWeight: '900',
    letterSpacing: -1,
  },
  heroPoints: {
    marginTop: 3,
    color: colors.mutedLight,
    fontSize: 9,
    fontWeight: '800',
  },
  heroVenue: {
    marginTop: 4,
    color: colors.mutedLight,
    fontSize: 8,
    fontWeight: '800',
  },
  lockBar: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    marginTop: 20,
    paddingTop: 15,
    borderTopWidth: StyleSheet.hairlineWidth,
    borderTopColor: colors.navyLine,
  },
  lockLabel: {
    color: colors.mutedLight,
    fontSize: 9,
    fontWeight: '900',
    letterSpacing: 0.6,
  },
  lockValue: {
    color: colors.white,
    fontSize: 10,
    fontWeight: '900',
  },
  lineupCard: {
    marginTop: 14,
    padding: 18,
    borderRadius: radius.lg,
    backgroundColor: colors.white,
  },
  lineupHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
  },
  lineupEyebrow: {
    color: colors.muted,
    fontSize: 9,
    fontWeight: '900',
    letterSpacing: 0.8,
  },
  lineupTitle: {
    marginTop: 3,
    color: colors.navy,
    fontSize: 19,
    fontWeight: '900',
  },
  shieldBadge: {
    width: 38,
    height: 38,
    borderRadius: 19,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.canvasMuted,
  },
  shieldText: {
    color: colors.navy,
    fontSize: 10,
    fontWeight: '900',
  },
  lineupStatusRow: {
    flexDirection: 'row',
    gap: 10,
    marginTop: 16,
  },
  lineupStatus: {
    flex: 1,
    padding: 12,
    borderRadius: radius.sm,
    backgroundColor: colors.canvas,
  },
  lineupStatusLabel: {
    color: colors.muted,
    fontSize: 8,
    fontWeight: '900',
    letterSpacing: 0.6,
  },
  lineupStatusValueRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 7,
    marginTop: 6,
  },
  lineupStatusDot: {
    width: 7,
    height: 7,
    borderRadius: 4,
    backgroundColor: colors.danger,
  },
  lineupStatusDotReady: {
    backgroundColor: colors.success,
  },
  lineupStatusValue: {
    color: colors.danger,
    fontSize: 10,
    fontWeight: '900',
  },
  lineupStatusValueReady: {
    color: colors.navy,
  },
  lineupPrivacy: {
    marginTop: 13,
    color: colors.muted,
    fontSize: 12,
    lineHeight: 18,
  },
  lineupButton: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    marginTop: 15,
    paddingVertical: 13,
    paddingHorizontal: 15,
    borderRadius: radius.md,
    backgroundColor: colors.lime,
  },
  lineupButtonText: {
    color: colors.navy,
    fontSize: 10,
    fontWeight: '900',
    letterSpacing: 0.4,
  },
  lineupButtonArrow: {
    color: colors.navy,
    fontSize: 18,
    fontWeight: '900',
  },
  sectionTitle: {
    marginTop: 24,
    marginBottom: 10,
    color: colors.navy,
    fontSize: 18,
    fontWeight: '900',
  },
  comparisonCard: {
    flexDirection: 'row',
    padding: 16,
    borderRadius: radius.lg,
    backgroundColor: colors.white,
  },
  comparisonTeam: {
    flex: 1,
    paddingHorizontal: 6,
  },
  comparisonDivider: {
    width: StyleSheet.hairlineWidth,
    marginHorizontal: 9,
    backgroundColor: colors.canvasMuted,
  },
  comparisonEyebrow: {
    color: colors.muted,
    fontSize: 8,
    fontWeight: '900',
    letterSpacing: 0.7,
  },
  activeText: {
    color: '#6C8F18',
  },
  comparisonName: {
    minHeight: 36,
    marginTop: 5,
    color: colors.navy,
    fontSize: 14,
    lineHeight: 18,
    fontWeight: '900',
  },
  positionRow: {
    flexDirection: 'row',
    alignItems: 'baseline',
    gap: 5,
    marginTop: 10,
    marginBottom: 8,
  },
  positionValue: {
    color: colors.navy,
    fontSize: 27,
    fontWeight: '900',
  },
  positionLabel: {
    color: colors.muted,
    fontSize: 8,
    fontWeight: '900',
  },
  compareStat: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingVertical: 7,
    borderTopWidth: StyleSheet.hairlineWidth,
    borderTopColor: colors.canvasMuted,
  },
  compareStatLabel: {
    color: colors.muted,
    fontSize: 8,
    fontWeight: '800',
  },
  compareStatValue: {
    color: colors.navy,
    fontSize: 11,
    fontWeight: '900',
  },
  formBlock: {
    marginTop: 10,
  },
  formLabel: {
    color: colors.muted,
    fontSize: 8,
    fontWeight: '900',
  },
  formRow: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 4,
    marginTop: 6,
  },
  formDot: {
    width: 22,
    height: 22,
    borderRadius: 11,
    alignItems: 'center',
    justifyContent: 'center',
  },
  formWin: {
    backgroundColor: colors.success,
  },
  formDraw: {
    backgroundColor: colors.canvasMuted,
  },
  formLoss: {
    backgroundColor: colors.danger,
  },
  formDotText: {
    color: colors.navy,
    fontSize: 8,
    fontWeight: '900',
  },
  noForm: {
    marginTop: 6,
    color: colors.muted,
  },
  streakText: {
    marginTop: 8,
    color: colors.muted,
    fontSize: 9,
    fontWeight: '700',
  },
  rivalryCard: {
    padding: 18,
    borderRadius: radius.lg,
    backgroundColor: colors.navy,
  },
  rivalryTop: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    marginBottom: 18,
  },
  rivalryEyebrow: {
    color: colors.mutedLight,
    fontSize: 8,
    fontWeight: '900',
    letterSpacing: 0.8,
  },
  rivalryLeader: {
    maxWidth: 220,
    marginTop: 4,
    color: colors.white,
    fontSize: 18,
    fontWeight: '900',
  },
  seasonBadge: {
    width: 58,
    height: 58,
    borderRadius: 29,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.lime,
  },
  seasonBadgeValue: {
    color: colors.navy,
    fontSize: 18,
    fontWeight: '900',
  },
  seasonBadgeLabel: {
    color: colors.navy,
    fontSize: 6,
    fontWeight: '900',
  },
  recordBlock: {
    gap: 8,
  },
  recordHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
  },
  recordLabel: {
    color: colors.white,
    fontSize: 9,
    fontWeight: '900',
  },
  recordPlayed: {
    color: colors.mutedLight,
    fontSize: 8,
    fontWeight: '800',
  },
  recordValues: {
    flexDirection: 'row',
    justifyContent: 'space-between',
  },
  recordValue: {
    color: colors.lime,
    fontSize: 11,
    fontWeight: '900',
  },
  recordValueMuted: {
    color: colors.mutedLight,
    fontSize: 11,
    fontWeight: '900',
  },
  recordValueOpponent: {
    color: colors.white,
    fontSize: 11,
    fontWeight: '900',
  },
  recordTrack: {
    height: 6,
    flexDirection: 'row',
    gap: 3,
  },
  recordTrackMine: {
    borderRadius: 3,
    backgroundColor: colors.lime,
  },
  recordTrackDraw: {
    borderRadius: 3,
    backgroundColor: colors.muted,
  },
  recordTrackOpponent: {
    borderRadius: 3,
    backgroundColor: colors.white,
  },
  rivalryDivider: {
    height: StyleSheet.hairlineWidth,
    marginVertical: 16,
    backgroundColor: colors.navyLine,
  },
  rivalryNumbers: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    marginTop: 18,
    paddingTop: 16,
    borderTopWidth: StyleSheet.hairlineWidth,
    borderTopColor: colors.navyLine,
  },
  rivalryNumber: {
    color: colors.white,
    fontSize: 16,
    fontWeight: '900',
  },
  rivalryNumberLabel: {
    marginTop: 3,
    color: colors.mutedLight,
    fontSize: 7,
    fontWeight: '900',
    letterSpacing: 0.5,
  },
  rivalryNumberRight: {
    alignItems: 'flex-end',
  },
  historyHeader: {
    flexDirection: 'row',
    alignItems: 'baseline',
    justifyContent: 'space-between',
  },
  historyCount: {
    color: colors.muted,
    fontSize: 8,
    fontWeight: '900',
    letterSpacing: 0.6,
  },
  meetingsCard: {
    overflow: 'hidden',
    borderRadius: radius.lg,
    backgroundColor: colors.white,
  },
  meetingRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 11,
    padding: 14,
    borderBottomWidth: StyleSheet.hairlineWidth,
    borderBottomColor: colors.canvasMuted,
  },
  outcomeBadge: {
    width: 32,
    height: 32,
    borderRadius: 16,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.canvasMuted,
  },
  outcomeWin: {
    backgroundColor: colors.success,
  },
  outcomeLoss: {
    backgroundColor: colors.danger,
  },
  outcomeText: {
    color: colors.navy,
    fontSize: 10,
    fontWeight: '900',
  },
  meetingCopy: {
    flex: 1,
  },
  meetingTeams: {
    color: colors.navy,
    fontSize: 12,
    fontWeight: '900',
  },
  meetingMeta: {
    marginTop: 3,
    color: colors.muted,
    fontSize: 8,
    fontWeight: '800',
  },
  meetingScore: {
    alignItems: 'flex-end',
  },
  meetingGoals: {
    color: colors.navy,
    fontSize: 17,
    fontWeight: '900',
  },
  meetingPoints: {
    marginTop: 2,
    color: colors.muted,
    fontSize: 8,
    fontWeight: '800',
  },
  noMeeting: {
    padding: 22,
    alignItems: 'center',
  },
  noMeetingTitle: {
    color: colors.navy,
    fontSize: 15,
    fontWeight: '900',
  },
  noMeetingBody: {
    marginTop: 5,
    color: colors.muted,
    fontSize: 12,
    textAlign: 'center',
  },
  emptyCard: {
    alignItems: 'center',
    padding: 26,
    borderRadius: radius.xl,
    backgroundColor: colors.white,
  },
  emptyIcon: {
    width: 64,
    height: 64,
    borderRadius: 32,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.lime,
  },
  emptyIconText: {
    color: colors.navy,
    fontSize: 16,
    fontWeight: '900',
  },
  emptyTitle: {
    marginTop: 16,
    color: colors.navy,
    fontSize: 22,
    fontWeight: '900',
  },
  emptyBody: {
    marginTop: 7,
    color: colors.muted,
    fontSize: 13,
    lineHeight: 19,
    textAlign: 'center',
  },
  darkButton: {
    marginTop: 18,
    paddingVertical: 14,
    paddingHorizontal: 18,
    borderRadius: radius.md,
    backgroundColor: colors.navy,
  },
  darkButtonText: {
    color: colors.white,
    fontSize: 10,
    fontWeight: '900',
  },
});
