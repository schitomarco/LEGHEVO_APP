import {
  ActivityIndicator,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  View,
} from 'react-native';
import { useLiveMatchCenter } from '../hooks/useLiveMatchCenter';
import { colors, radius } from '../theme';
import type {
  AppScreen,
  LeagueSummary,
  LiveMatchCenter,
  LiveTeamScore,
} from '../types';

type Props = {
  league: LeagueSummary | null;
  onNavigate: (screen: AppScreen) => void;
};

export function LiveScreen({ league, onNavigate }: Props) {
  const live = useLiveMatchCenter(league);

  if (!league) {
    return (
      <View style={styles.centerRoot}>
        <View style={styles.centerBadge}>
          <Text style={styles.centerBadgeText}>L</Text>
        </View>
        <Text style={styles.centerTitle}>Prima scegli una lega</Text>
        <Text style={styles.centerBody}>
          Il Live senza spogliatoio è soltanto calcio alla radio.
        </Text>
        <Pressable
          onPress={() => onNavigate('home')}
          style={styles.primaryButton}
        >
          <Text style={styles.primaryButtonText}>VAI ALLE LEGHE</Text>
        </Pressable>
      </View>
    );
  }

  if (live.loading) {
    return (
      <View style={styles.centerRoot}>
        <ActivityIndicator color={colors.navy} size="large" />
        <Text style={styles.loadingText}>Accendo tutti i campi…</Text>
      </View>
    );
  }

  if (live.error) {
    return (
      <View style={styles.centerRoot}>
        <Text style={styles.centerTitle}>Live momentaneamente in panchina</Text>
        <Text style={styles.centerBody}>{live.error}</Text>
        <Pressable
          onPress={() => void live.refresh()}
          style={styles.primaryButton}
        >
          <Text style={styles.primaryButtonText}>RIPROVA</Text>
        </Pressable>
      </View>
    );
  }

  if (!live.match) {
    return (
      <View style={styles.centerRoot}>
        <View style={styles.centerBadge}>
          <Text style={styles.centerBadgeText}>0'</Text>
        </View>
        <Text style={styles.centerTitle}>Nessuna partita convocata</Text>
        <Text style={styles.centerBody}>
          Genera il calendario della lega e qui comparirà la prossima sfida.
        </Text>
        <Pressable
          onPress={() => onNavigate('calendar')}
          style={styles.primaryButton}
        >
          <Text style={styles.primaryButtonText}>APRI IL CALENDARIO</Text>
        </Pressable>
      </View>
    );
  }

  const match = live.match;
  const totalCounted =
    match.home.countedPlayers + match.away.countedPlayers;
  const progress = Math.min(100, Math.round((totalCounted / 22) * 100));

  return (
    <ScrollView
      style={styles.screen}
      contentContainerStyle={styles.content}
      showsVerticalScrollIndicator={false}
    >
      <View style={styles.headerRow}>
        <View style={styles.headerCopy}>
          <Text numberOfLines={1} style={styles.eyebrow}>
            {match.leagueName}
          </Text>
          <Text style={styles.title}>Giornata {match.matchday.number}</Text>
        </View>
        <View
          style={[
            styles.livePill,
            match.status === 'final' && styles.finalPill,
          ]}
        >
          <View
            style={[
              styles.liveDot,
              match.status !== 'live' && styles.liveDotWaiting,
            ]}
          />
          <Text style={styles.liveText}>{statusLabel(match)}</Text>
        </View>
      </View>

      <View style={styles.scoreCard}>
        <Text style={styles.scoreMeta}>
          {scoreMeta(match, totalCounted)}
        </Text>
        <View style={styles.scoreRow}>
          <ScoreBadge
            active={match.home.teamId === match.myTeamId}
            team={match.home}
          />
          <View style={styles.scoreCenter}>
            <Text style={styles.scorePrimary}>
              {formatGoals(match.home.goals)}–{formatGoals(match.away.goals)}
            </Text>
            <Text style={styles.scoreSecondary}>
              {formatPoints(match.home.points)} ·{' '}
              {formatPoints(match.away.points)} PT
            </Text>
          </View>
          <ScoreBadge
            active={match.away.teamId === match.myTeamId}
            team={match.away}
          />
        </View>
        <View style={styles.progressTrack}>
          <View
            style={[
              styles.progressValue,
              { width: `${progress}%` as `${number}%` },
            ]}
          />
        </View>
      </View>

      <ScoreBreakdown home={match.home} away={match.away} />

      {match.goalBands.enabled ? (
        <View style={styles.goalBandsCard}>
          <Text style={styles.goalBandsLabel}>FASCE GOL PERSONALIZZATE</Text>
          <Text style={styles.goalBandsText}>
            {match.goalBands.thresholds
              .map(
                (threshold, index) =>
                  `${index + 1}G ${formatPoints(threshold)}`,
              )
              .join(' · ')}
          </Text>
        </View>
      ) : null}

      {match.goalMargin.applied ? (
        <View style={styles.goalMarginCard}>
          <Text style={styles.goalMarginLabel}>REGOLA SCARTO APPLICATA</Text>
          <Text style={styles.goalMarginText}>
            {match.goalMargin.homeBonus > 0
              ? match.home.name
              : match.away.name}{' '}
            riceve un gol aggiuntivo per uno scarto di almeno{' '}
            {formatPoints(match.goalMargin.minimum)} fantapunti.
          </Text>
        </View>
      ) : null}

      {match.lineupOrigin === 'carried' ? (
        <View style={styles.lineupOriginCard}>
          <Text style={styles.lineupOriginLabel}>DISTINTA RECUPERATA</Text>
          <Text style={styles.lineupOriginText}>
            LEGHEVO ha confermato automaticamente la formazione
            {match.lineupSourceMatchdayNumber
              ? ` della giornata ${match.lineupSourceMatchdayNumber}`
              : ' precedente'}
            .
          </Text>
        </View>
      ) : match.lineupOrigin === 'missing' &&
        match.status !== 'upcoming' ? (
        <View
          style={[
            styles.lineupOriginCard,
            styles.lineupOriginCardWarning,
          ]}
        >
          <Text
            style={[
              styles.lineupOriginLabel,
              styles.lineupOriginLabelWarning,
            ]}
          >
            DISTINTA ASSENTE
          </Text>
          <Text style={styles.lineupOriginText}>
            Non era disponibile una formazione valida: il punteggio della
            squadra sarà 0.
          </Text>
        </View>
      ) : null}

      <View style={styles.substitutionCard}>
        <View style={styles.substitutionHeader}>
          <Text style={styles.substitutionLabel}>CAMBI AUTOMATICI</Text>
          <Text style={styles.substitutionCounter}>
            {match.substitutions.used}/{match.substitutions.limit}
          </Text>
        </View>
        <Text style={styles.substitutionText}>
          {substitutionMessage(match)}
        </Text>
      </View>

      <View style={styles.analysisCard}>
        <Text style={styles.analysisLabel}>DAL CAMPO</Text>
        <Text style={styles.analysisText}>{analysisMessage(match)}</Text>
      </View>

      <View style={styles.sectionHeader}>
        <Text style={styles.sectionTitle}>I tuoi giocatori</Text>
        <Text style={styles.sectionCounter}>
          {match.players.filter((player) => player.score !== 'SV').length}/11
        </Text>
      </View>

      {match.players.length === 0 ? (
        <View style={styles.emptyLineupCard}>
          <Text style={styles.emptyLineupTitle}>Distinta non trovata</Text>
          <Text style={styles.emptyLineupBody}>
            {match.status === 'upcoming'
              ? 'Consegna la formazione per vedere voti, bonus e sostituzioni nel Live.'
              : 'La scadenza è passata senza una formazione valida. Il risultato sarà calcolato a 0 fantapunti.'}
          </Text>
          {match.status === 'upcoming' ? (
            <Pressable
              onPress={() => onNavigate('lineup')}
              style={styles.lineupButton}
            >
              <Text style={styles.lineupButtonText}>SCHIERA LA FORMAZIONE</Text>
            </Pressable>
          ) : null}
        </View>
      ) : (
        <View style={styles.playersList}>
          {match.players.map((player) => (
            <View key={`${player.id}-${player.name}`} style={styles.playerRow}>
              <View style={styles.roleBadge}>
                <Text numberOfLines={1} style={styles.roleText}>
                  {player.role}
                </Text>
              </View>
              <View style={styles.playerCopy}>
                <Text style={styles.playerName}>{player.name}</Text>
                <Text
                  numberOfLines={1}
                  style={[
                    styles.playerStatus,
                    player.isSubstitute && styles.substituteStatus,
                  ]}
                >
                  {player.status}
                </Text>
              </View>
              <View
                style={[
                  styles.playerScore,
                  player.highlighted && styles.playerScoreHighlighted,
                ]}
              >
                <Text style={styles.playerScoreText}>{player.score}</Text>
              </View>
            </View>
          ))}
        </View>
      )}
    </ScrollView>
  );
}

function ScoreBadge({
  team,
  active,
}: {
  team: LiveTeamScore;
  active?: boolean;
}) {
  return (
    <View style={styles.badgeWrapper}>
      <View style={[styles.badge, active && styles.badgeActive]}>
        <Text style={styles.badgeText}>{teamInitials(team.name)}</Text>
      </View>
      <Text numberOfLines={2} style={styles.badgeLabel}>
        {team.name}
        {active ? ' · TU' : ''}
      </Text>
      <Text style={styles.badgeCount}>{team.countedPlayers}/11 VOTI</Text>
    </View>
  );
}

function ScoreBreakdown({
  home,
  away,
}: {
  home: LiveTeamScore;
  away: LiveTeamScore;
}) {
  const visible =
    home.defenseModifier.enabled ||
    away.defenseModifier.enabled ||
    home.homeBonus !== 0;

  if (!visible) {
    return null;
  }

  return (
    <View style={styles.breakdownCard}>
      <Text style={styles.breakdownLabel}>CALCOLO FANTAPUNTI</Text>
      <BreakdownRow team={home} />
      <View style={styles.breakdownDivider} />
      <BreakdownRow team={away} />
    </View>
  );
}

function BreakdownRow({ team }: { team: LiveTeamScore }) {
  const modifier = team.defenseModifier;
  const parts = [
    team.basePoints === null
      ? 'base in attesa'
      : `${formatPoints(team.basePoints)} base`,
  ];

  if (modifier.enabled) {
    parts.push(
      modifier.eligible
        ? `+${formatPoints(modifier.bonus)} difesa · media ${formatPoints(
            modifier.averageRating ?? 0,
          )}`
        : `difesa non valida · ${modifier.defenderCount}/${modifier.minimumDefenders}`,
    );
  }
  if (team.homeBonus !== 0) {
    parts.push(`+${formatPoints(team.homeBonus)} casa`);
  }

  return (
    <View style={styles.breakdownRow}>
      <Text numberOfLines={1} style={styles.breakdownTeam}>
        {team.name}
      </Text>
      <Text style={styles.breakdownValue}>{parts.join(' · ')}</Text>
    </View>
  );
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

function statusLabel(match: LiveMatchCenter) {
  const labels = {
    upcoming: 'IN ATTESA',
    live: 'LIVE',
    pending: 'IN CALCOLO',
    final: 'FINALE',
  };
  return labels[match.status];
}

function scoreMeta(match: LiveMatchCenter, totalCounted: number) {
  if (match.status === 'upcoming') {
    return `FISCHIO D’INIZIO · ${formatKickoff(match.matchday.startsAt)}`;
  }
  if (match.status === 'final') {
    return 'RISULTATO UFFICIALE · 22/22 VOTI';
  }
  return `PARZIALE · ${totalCounted}/22 VOTI`;
}

function formatKickoff(value: string) {
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

function formatGoals(value: number | null) {
  return value === null ? '—' : String(value);
}

function formatPoints(value: number | null) {
  return value === null ? '—' : value.toFixed(1).replace('.', ',');
}

function analysisMessage(match: LiveMatchCenter) {
  if (match.status === 'upcoming') {
    return `Si parte ${formatKickoff(match.matchday.startsAt)}. Controlla la distinta prima che il mister inventi scuse.`;
  }
  if (match.status === 'pending') {
    return 'Le partite sono finite, ma mancano ancora alcuni voti definitivi. Il lunedì è lungo.';
  }

  const myTeam =
    match.home.teamId === match.myTeamId ? match.home : match.away;
  const opponent =
    match.home.teamId === match.myTeamId ? match.away : match.home;

  if (myTeam.goals === null || opponent.goals === null) {
    return 'I primi voti stanno arrivando. Per ora nessuno può vantarsi.';
  }
  if (myTeam.goals > opponent.goals) {
    return match.status === 'final'
      ? 'Tre punti nello spogliatoio. Le analisi tattiche possono aspettare.'
      : 'Sei avanti. Vietato fare calcoli fino al triplice fischio.';
  }
  if (myTeam.goals < opponent.goals) {
    return match.status === 'final'
      ? 'È andata male. Da domani si parlerà soltanto di sfortuna.'
      : 'Sei sotto. La rimonta ha ancora il GPS acceso.';
  }
  return match.status === 'final'
    ? 'Pareggio ufficiale. Ognuno potrà dire di meritare di più.'
    : 'Equilibrio totale. Basta un bonus per far saltare la panchina.';
}

function substitutionMessage(match: LiveMatchCenter) {
  if (!match.substitutions.applied) {
    return `L’ordine della panchina sarà applicato al termine della giornata, fino a ${match.substitutions.limit} cambi compatibili.`;
  }
  if (match.substitutions.used === 0) {
    return match.substitutions.unavailableStarters > 0
      ? `${match.substitutions.unavailableStarters} titolari senza voto e nessuna riserva compatibile disponibile.`
      : 'Nessun cambio necessario: tutti i titolari valutati sono rimasti in campo.';
  }

  const unavailable =
    match.substitutions.unavailableStarters > 0
      ? ` ${match.substitutions.unavailableStarters} titolari sono rimasti senza voto.`
      : '';
  return `${match.substitutions.used} sostituzioni applicate seguendo la priorità scelta in panchina.${unavailable}`;
}

const styles = StyleSheet.create({
  screen: {
    flex: 1,
    backgroundColor: colors.canvas,
  },
  content: {
    padding: 20,
    paddingBottom: 36,
  },
  centerRoot: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    padding: 28,
    backgroundColor: colors.canvas,
  },
  centerBadge: {
    width: 62,
    height: 62,
    borderRadius: 20,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.navy,
  },
  centerBadgeText: {
    color: colors.lime,
    fontSize: 18,
    fontWeight: '900',
  },
  centerTitle: {
    color: colors.navy,
    fontSize: 22,
    fontWeight: '900',
    textAlign: 'center',
    marginTop: 20,
  },
  centerBody: {
    color: colors.muted,
    fontSize: 13,
    lineHeight: 19,
    textAlign: 'center',
    marginTop: 8,
  },
  primaryButton: {
    minHeight: 50,
    borderRadius: 25,
    alignItems: 'center',
    justifyContent: 'center',
    paddingHorizontal: 24,
    backgroundColor: colors.lime,
    marginTop: 22,
  },
  primaryButtonText: {
    color: colors.navy,
    fontSize: 10,
    fontWeight: '900',
  },
  loadingText: {
    color: colors.muted,
    fontSize: 12,
    fontWeight: '800',
    marginTop: 12,
  },
  headerRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    marginBottom: 22,
  },
  headerCopy: {
    flex: 1,
    marginRight: 12,
  },
  eyebrow: {
    color: colors.muted,
    fontSize: 12,
  },
  title: {
    color: colors.navy,
    fontSize: 30,
    fontWeight: '900',
    marginTop: 4,
  },
  livePill: {
    height: 34,
    borderRadius: 17,
    paddingHorizontal: 14,
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: colors.navy,
  },
  finalPill: {
    backgroundColor: colors.muted,
  },
  liveDot: {
    width: 8,
    height: 8,
    borderRadius: 4,
    backgroundColor: colors.danger,
    marginRight: 7,
  },
  liveDotWaiting: {
    backgroundColor: colors.lime,
  },
  liveText: {
    color: colors.warmWhite,
    fontSize: 9,
    fontWeight: '900',
  },
  scoreCard: {
    borderRadius: radius.xl,
    backgroundColor: colors.navy,
    padding: 22,
  },
  breakdownCard: {
    borderRadius: radius.lg,
    padding: 16,
    backgroundColor: colors.white,
    marginTop: 12,
  },
  breakdownLabel: {
    color: colors.muted,
    fontSize: 8,
    fontWeight: '900',
    letterSpacing: 0.5,
    marginBottom: 11,
  },
  breakdownRow: {
    gap: 3,
  },
  breakdownTeam: {
    color: colors.navy,
    fontSize: 11,
    fontWeight: '900',
  },
  breakdownValue: {
    color: colors.muted,
    fontSize: 9,
    fontWeight: '700',
    lineHeight: 14,
  },
  breakdownDivider: {
    height: StyleSheet.hairlineWidth,
    backgroundColor: colors.canvasMuted,
    marginVertical: 11,
  },
  goalMarginCard: {
    borderWidth: 1,
    borderColor: colors.lime,
    borderRadius: radius.lg,
    backgroundColor: colors.limeSoft,
    padding: 16,
    marginTop: 12,
  },
  goalMarginLabel: {
    color: colors.navy,
    fontSize: 8,
    fontWeight: '900',
    letterSpacing: 0.6,
  },
  goalMarginText: {
    color: colors.navy,
    fontSize: 12,
    lineHeight: 18,
    marginTop: 6,
  },
  goalBandsCard: {
    borderRadius: radius.lg,
    backgroundColor: colors.navy,
    padding: 16,
    marginTop: 12,
  },
  goalBandsLabel: {
    color: colors.lime,
    fontSize: 8,
    fontWeight: '900',
    letterSpacing: 0.6,
  },
  goalBandsText: {
    color: colors.white,
    fontSize: 11,
    fontWeight: '800',
    lineHeight: 18,
    marginTop: 6,
  },
  scoreMeta: {
    color: colors.mutedLight,
    fontSize: 9,
    fontWeight: '900',
    textAlign: 'center',
  },
  scoreRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    marginTop: 20,
  },
  badgeWrapper: {
    alignItems: 'center',
    width: 92,
  },
  badge: {
    width: 58,
    height: 58,
    borderRadius: 29,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.canvasMuted,
  },
  badgeActive: {
    backgroundColor: colors.lime,
  },
  badgeText: {
    color: colors.navy,
    fontSize: 13,
    fontWeight: '900',
  },
  badgeLabel: {
    minHeight: 25,
    color: colors.warmWhite,
    fontSize: 8,
    lineHeight: 12,
    fontWeight: '900',
    textAlign: 'center',
    marginTop: 8,
  },
  badgeCount: {
    color: colors.mutedLight,
    fontSize: 7,
    fontWeight: '900',
    marginTop: 3,
  },
  scoreCenter: {
    alignItems: 'center',
  },
  scorePrimary: {
    color: colors.warmWhite,
    fontSize: 32,
    fontWeight: '900',
  },
  scoreSecondary: {
    color: colors.mutedLight,
    fontSize: 10,
    fontWeight: '800',
    marginTop: 5,
  },
  progressTrack: {
    height: 7,
    borderRadius: 4,
    backgroundColor: colors.navyLine,
    marginTop: 22,
    overflow: 'hidden',
  },
  progressValue: {
    height: '100%',
    borderRadius: 4,
    backgroundColor: colors.lime,
  },
  lineupOriginCard: {
    borderWidth: 1,
    borderColor: colors.lime,
    borderRadius: radius.lg,
    backgroundColor: colors.limeSoft,
    padding: 16,
    marginTop: 14,
  },
  lineupOriginCardWarning: {
    borderColor: '#F1B1AC',
    backgroundColor: '#FFE9E8',
  },
  lineupOriginLabel: {
    color: colors.navy,
    fontSize: 8,
    fontWeight: '900',
    letterSpacing: 0.6,
  },
  lineupOriginLabelWarning: {
    color: '#A3312D',
  },
  lineupOriginText: {
    color: colors.navy,
    fontSize: 12,
    lineHeight: 18,
    marginTop: 6,
  },
  substitutionCard: {
    borderRadius: radius.lg,
    backgroundColor: colors.white,
    padding: 18,
    marginTop: 20,
  },
  substitutionHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
  },
  substitutionLabel: {
    color: colors.muted,
    fontSize: 9,
    fontWeight: '900',
  },
  substitutionCounter: {
    color: colors.navy,
    fontSize: 15,
    fontWeight: '900',
  },
  substitutionText: {
    color: colors.navy,
    fontSize: 12,
    lineHeight: 18,
    marginTop: 8,
  },
  analysisCard: {
    borderRadius: radius.lg,
    backgroundColor: colors.lime,
    padding: 18,
    marginTop: 12,
  },
  analysisLabel: {
    color: colors.navy,
    fontSize: 9,
    fontWeight: '900',
  },
  analysisText: {
    color: colors.navy,
    fontSize: 14,
    lineHeight: 20,
    marginTop: 7,
  },
  sectionHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    marginTop: 24,
    marginBottom: 12,
  },
  sectionTitle: {
    color: colors.navy,
    fontSize: 21,
    fontWeight: '900',
  },
  sectionCounter: {
    color: colors.muted,
    fontSize: 10,
    fontWeight: '900',
  },
  emptyLineupCard: {
    borderRadius: radius.lg,
    padding: 20,
    backgroundColor: colors.white,
  },
  emptyLineupTitle: {
    color: colors.navy,
    fontSize: 17,
    fontWeight: '900',
  },
  emptyLineupBody: {
    color: colors.muted,
    fontSize: 12,
    lineHeight: 18,
    marginTop: 7,
  },
  lineupButton: {
    minHeight: 46,
    borderRadius: radius.md,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.lime,
    marginTop: 16,
  },
  lineupButtonText: {
    color: colors.navy,
    fontSize: 9,
    fontWeight: '900',
  },
  playersList: {
    gap: 8,
  },
  playerRow: {
    minHeight: 62,
    borderRadius: radius.md,
    backgroundColor: colors.white,
    paddingHorizontal: 12,
    flexDirection: 'row',
    alignItems: 'center',
  },
  roleBadge: {
    minWidth: 36,
    height: 36,
    borderRadius: 18,
    paddingHorizontal: 7,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.navy,
  },
  roleText: {
    color: colors.lime,
    fontSize: 9,
    fontWeight: '900',
  },
  playerCopy: {
    flex: 1,
    marginLeft: 12,
  },
  playerName: {
    color: colors.navy,
    fontSize: 14,
    fontWeight: '800',
  },
  playerStatus: {
    color: colors.muted,
    fontSize: 9,
    marginTop: 3,
  },
  substituteStatus: {
    color: colors.navy,
    fontWeight: '800',
  },
  playerScore: {
    minWidth: 48,
    height: 27,
    borderRadius: 14,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.canvasMuted,
  },
  playerScoreHighlighted: {
    backgroundColor: colors.lime,
  },
  playerScoreText: {
    color: colors.navy,
    fontSize: 11,
    fontWeight: '900',
  },
});
