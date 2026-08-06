import { useEffect, useState } from 'react';
import {
  ActivityIndicator,
  Alert,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  View,
} from 'react-native';
import { useLeagueSuperCup } from '../hooks/useLeagueSuperCup';
import { colors, radius } from '../theme';
import type {
  LeagueSummary,
  LeagueSuperCupQualification,
  LeagueSuperCupTeam,
} from '../types';

type Props = {
  league: LeagueSummary | null;
  onBack: () => void;
};

export function LeagueSuperCupScreen({ league, onBack }: Props) {
  const state = useLeagueSuperCup(
    league?.id ?? null,
    Boolean(league?.isDemo),
  );
  const [selectedMatchday, setSelectedMatchday] =
    useState<number | null>(null);
  const [feedback, setFeedback] = useState('');

  useEffect(() => {
    if (
      selectedMatchday === null &&
      state.superCup?.startMatchdays.length
    ) {
      setSelectedMatchday(state.superCup.startMatchdays[0].number);
    }
  }, [selectedMatchday, state.superCup]);

  if (!league) {
    return (
      <View style={styles.centerRoot}>
        <Text style={styles.centerTitle}>Prima scegli una lega.</Text>
        <Pressable onPress={onBack} style={styles.primaryButton}>
          <Text style={styles.primaryButtonText}>TORNA ALLA LEGA</Text>
        </Pressable>
      </View>
    );
  }

  const schedule = async () => {
    if (selectedMatchday === null) {
      setFeedback('Scegli la giornata della finale.');
      return;
    }
    setFeedback('');
    const outcome = await state.create(selectedMatchday);
    setFeedback(
      outcome.error ??
        'Supercoppa programmata. La sfida è ora ufficiale.',
    );
  };

  const confirmFinalize = () => {
    Alert.alert(
      'Ufficializza la Supercoppa',
      'Il risultato diventerà definitivo e il vincitore entrerà nell’albo.',
      [
        { text: 'Annulla', style: 'cancel' },
        {
          text: 'Ufficializza',
          onPress: async () => {
            setFeedback('');
            const outcome = await state.finalize();
            setFeedback(
              outcome.error ?? 'Supercoppa assegnata e albo aggiornato.',
            );
          },
        },
      ],
    );
  };

  const superCup = state.superCup;

  return (
    <ScrollView
      contentContainerStyle={styles.content}
      showsVerticalScrollIndicator={false}
      style={styles.screen}
    >
      <View style={styles.header}>
        <Pressable onPress={onBack} style={styles.backButton}>
          <Text style={styles.backText}>‹</Text>
        </Pressable>
        <View style={styles.headerCopy}>
          <Text style={styles.eyebrow}>TROFEO TRA STAGIONI</Text>
          <Text style={styles.title}>Supercoppa</Text>
        </View>
        <Pressable
          accessibilityLabel="Aggiorna Supercoppa"
          accessibilityState={{
            busy: state.loading,
            disabled: state.loading,
          }}
          disabled={state.loading}
          onPress={() => void state.refresh()}
          style={[
            styles.reloadButton,
            state.loading && styles.reloadButtonDisabled,
          ]}
        >
          {state.loading ? (
            <ActivityIndicator color={colors.navy} size="small" />
          ) : (
            <Text style={styles.reloadText}>↻</Text>
          )}
        </Pressable>
      </View>

      {feedback ? <Text style={styles.feedback}>{feedback}</Text> : null}

      {state.loading && !superCup ? (
        <View style={styles.loadingCard}>
          <ActivityIndicator color={colors.lime} />
          <Text style={styles.loadingText}>Recupero i campioni…</Text>
        </View>
      ) : state.error && !superCup ? (
        <View style={styles.errorCard}>
          <Text style={styles.errorTitle}>Supercoppa indisponibile</Text>
          <Text style={styles.errorBody}>{state.error}</Text>
          <Pressable
            onPress={() => void state.refresh()}
            style={styles.primaryButton}
          >
            <Text style={styles.primaryButtonText}>RIPROVA</Text>
          </Pressable>
        </View>
      ) : superCup && !superCup.exists ? (
        <>
          <View style={styles.introCard}>
            <Text style={styles.introEyebrow}>UNA PARTITA, UN TROFEO</Text>
            <Text style={styles.introTitle}>
              La stagione ricomincia dai vincitori.
            </Text>
            <Text style={styles.introBody}>
              Campione del campionato e vincitore della Coppa precedente si
              affrontano con la stessa formazione della giornata scelta.
            </Text>
            {superCup.sourceSeason ? (
              <View style={styles.sourcePill}>
                <Text style={styles.sourcePillText}>
                  TITOLI {superCup.sourceSeason}
                </Text>
              </View>
            ) : null}
          </View>

          {superCup.leagueChampion && superCup.challenger ? (
            <MatchupCard
              challengerQualification={
                superCup.challengerQualification
              }
              home={superCup.leagueChampion}
              away={superCup.challenger}
            />
          ) : null}

          <View style={styles.ruleCard}>
            <Text style={styles.ruleTitle}>Regola della finale</Text>
            <Text style={styles.ruleBody}>
              Prima i gol, poi i fantapunti. In caso di parità perfetta il
              trofeo resta al campione del campionato precedente. Il bonus
              casa non viene applicato.
            </Text>
          </View>

          {superCup.canCreate ? (
            <>
              <View style={styles.sectionHeader}>
                <Text style={styles.sectionTitle}>Giornata della finale</Text>
                <Text style={styles.sectionMeta}>FORMAZIONE UNICA</Text>
              </View>
              <ScrollView
                horizontal
                showsHorizontalScrollIndicator={false}
                style={styles.matchdayScroller}
              >
                {superCup.startMatchdays.map((matchday) => {
                  const selected =
                    selectedMatchday === matchday.number;
                  return (
                    <Pressable
                      key={matchday.id}
                      onPress={() =>
                        setSelectedMatchday(matchday.number)
                      }
                      style={[
                        styles.matchdayChoice,
                        selected && styles.matchdayChoiceSelected,
                      ]}
                    >
                      <Text
                        style={[
                          styles.matchdayLabel,
                          selected && styles.matchdayTextSelected,
                        ]}
                      >
                        GIORNATA
                      </Text>
                      <Text
                        style={[
                          styles.matchdayNumber,
                          selected && styles.matchdayTextSelected,
                        ]}
                      >
                        {matchday.number}
                      </Text>
                      <Text
                        style={[
                          styles.matchdayDate,
                          selected && styles.matchdayTextSelected,
                        ]}
                      >
                        {formatShortDate(matchday.startsAt)}
                      </Text>
                    </Pressable>
                  );
                })}
              </ScrollView>
              <Pressable
                disabled={state.busy || selectedMatchday === null}
                onPress={() => void schedule()}
                style={[
                  styles.scheduleButton,
                  state.busy && styles.buttonDisabled,
                ]}
              >
                {state.busy ? (
                  <ActivityIndicator color={colors.navy} size="small" />
                ) : (
                  <Text style={styles.scheduleButtonText}>
                    PROGRAMMA LA SUPERCOPPA
                  </Text>
                )}
              </Pressable>
            </>
          ) : (
            <View style={styles.waitingCard}>
              <Text style={styles.waitingTitle}>
                Supercoppa non programmabile
              </Text>
              <Text style={styles.waitingBody}>
                {superCup.creationReason ??
                  'Il Presidente deve ancora preparare la sfida.'}
              </Text>
            </View>
          )}
        </>
      ) : superCup ? (
        <>
          {superCup.status === 'completed' && superCup.winner ? (
            <View style={styles.championCard}>
              <Text style={styles.championMark}>S</Text>
              <Text style={styles.championEyebrow}>
                VINCITORE DELLA SUPERCOPPA
              </Text>
              <Text style={styles.championName}>
                {superCup.winner.teamName}
              </Text>
              <Text style={styles.championManager}>
                {superCup.winner.managerName}
              </Text>
              {superCup.runnerUp ? (
                <Text style={styles.runnerUp}>
                  FINALISTA · {superCup.runnerUp.teamName}
                </Text>
              ) : null}
            </View>
          ) : (
            <View style={styles.heroCard}>
              <Text style={styles.heroEyebrow}>SUPERCOPPA IN CORSO</Text>
              <Text style={styles.heroTitle}>
                Titoli {superCup.sourceSeason ?? 'precedenti'}
              </Text>
              <Text style={styles.heroDate}>
                {superCup.matchday
                  ? `GIORNATA ${superCup.matchday.number} · ${formatDate(
                      superCup.matchday.startsAt,
                    )}`
                  : 'GIORNATA IN AGGIORNAMENTO'}
              </Text>
            </View>
          )}

          {superCup.scheduleCertified ? (
            <View style={styles.certificationPill}>
              <Text style={styles.certificationPillText}>
                PROGRAMMAZIONE CERTIFICATA · ANTI-DOPPIO TOCCO
              </Text>
            </View>
          ) : null}

          {superCup.finalizationCertified ? (
            <View style={styles.certificationPill}>
              <Text style={styles.certificationPillText}>
                VERDETTO UFFICIALE · ESITO CERTIFICATO
              </Text>
            </View>
          ) : null}

          {superCup.leagueChampion && superCup.challenger ? (
            <MatchupCard
              away={superCup.challenger}
              awayGoals={superCup.awayGoals}
              awayPoints={superCup.awayPoints}
              challengerQualification={
                superCup.challengerQualification
              }
              home={superCup.leagueChampion}
              homeGoals={superCup.homeGoals}
              homePoints={superCup.homePoints}
              official={superCup.status === 'completed'}
            />
          ) : null}

          {superCup.status === 'active' ? (
            <View style={styles.statusCard}>
              <View style={styles.statusTop}>
                <Text style={styles.statusTitle}>Stato del risultato</Text>
                <View
                  style={[
                    styles.statusBadge,
                    superCup.homeReady &&
                      superCup.awayReady &&
                      styles.statusBadgeReady,
                  ]}
                >
                  <Text style={styles.statusBadgeText}>
                    {superCup.homeReady && superCup.awayReady
                      ? 'VOTI COMPLETI'
                      : 'IN ATTESA'}
                  </Text>
                </View>
              </View>
              <Text style={styles.statusBody}>
                {superCup.homeReady && superCup.awayReady
                  ? 'Entrambe le formazioni hanno il punteggio definitivo.'
                  : `${superCup.homeCountedPlayers}/11 e ${superCup.awayCountedPlayers}/11 calciatori conteggiati.`}
              </Text>
            </View>
          ) : (
            <View style={styles.ruleCard}>
              <Text style={styles.ruleTitle}>Verdetto definitivo</Text>
              <Text style={styles.ruleBody}>
                {decisionLabel(superCup.decidedBy)}
              </Text>
            </View>
          )}

          {superCup.status === 'active' && superCup.isOwner ? (
            <View style={styles.directionCard}>
              <Text style={styles.directionEyebrow}>AREA PRESIDENTE</Text>
              <Text style={styles.directionTitle}>
                {superCup.canFinalize
                  ? 'La finale è pronta'
                  : 'In attesa dei voti definitivi'}
              </Text>
              <Text style={styles.directionBody}>
                {superCup.canFinalize
                  ? 'Ufficializzando assegnerai il trofeo e aggiornerai l’albo.'
                  : 'Il pulsante si attiva al termine della giornata reale.'}
              </Text>
              <Pressable
                disabled={!superCup.canFinalize || state.busy}
                onPress={confirmFinalize}
                style={[
                  styles.finalizeButton,
                  (!superCup.canFinalize || state.busy) &&
                    styles.buttonDisabled,
                ]}
              >
                {state.busy ? (
                  <ActivityIndicator color={colors.navy} size="small" />
                ) : (
                  <Text style={styles.finalizeButtonText}>
                    UFFICIALIZZA LA SUPERCOPPA
                  </Text>
                )}
              </Pressable>
            </View>
          ) : null}
        </>
      ) : null}
    </ScrollView>
  );
}

function MatchupCard({
  away,
  awayGoals,
  awayPoints,
  challengerQualification,
  home,
  homeGoals,
  homePoints,
  official = false,
}: {
  away: LeagueSuperCupTeam;
  awayGoals?: number | null;
  awayPoints?: number | null;
  challengerQualification: LeagueSuperCupQualification | null;
  home: LeagueSuperCupTeam;
  homeGoals?: number | null;
  homePoints?: number | null;
  official?: boolean;
}) {
  const hasScore = homeGoals !== null && homeGoals !== undefined;
  return (
    <View style={styles.matchupCard}>
      <Finalist
        label="CAMPIONE"
        manager={home.managerName}
        name={home.teamName}
      />
      <View style={styles.scoreColumn}>
        <Text style={styles.versus}>
          {hasScore ? `${homeGoals}–${awayGoals ?? 0}` : 'VS'}
        </Text>
        <Text style={styles.points}>
          {homePoints !== null &&
          homePoints !== undefined &&
          awayPoints !== null &&
          awayPoints !== undefined
            ? `${formatNumber(homePoints)} · ${formatNumber(awayPoints)}`
            : official
              ? 'RISULTATO UFFICIALE'
              : 'FINALE UNICA'}
        </Text>
      </View>
      <Finalist
        alignRight
        label={qualificationLabel(challengerQualification)}
        manager={away.managerName}
        name={away.teamName}
      />
    </View>
  );
}

function Finalist({
  alignRight = false,
  label,
  manager,
  name,
}: {
  alignRight?: boolean;
  label: string;
  manager: string;
  name: string;
}) {
  return (
    <View style={[styles.finalist, alignRight && styles.finalistRight]}>
      <View
        style={[
          styles.finalistMark,
          alignRight && styles.finalistMarkAway,
        ]}
      >
        <Text style={styles.finalistMarkText}>{label.slice(0, 1)}</Text>
      </View>
      <Text
        numberOfLines={2}
        style={[
          styles.finalistName,
          alignRight && styles.finalistTextRight,
        ]}
      >
        {name}
      </Text>
      <Text
        numberOfLines={1}
        style={[
          styles.finalistManager,
          alignRight && styles.finalistTextRight,
        ]}
      >
        {manager}
      </Text>
      <Text
        style={[
          styles.finalistLabel,
          alignRight && styles.finalistTextRight,
        ]}
      >
        {label}
      </Text>
    </View>
  );
}

function qualificationLabel(
  qualification: LeagueSuperCupQualification | null,
) {
  return qualification === 'cup_runner_up'
    ? 'FINALISTA COPPA'
    : 'VINCITORE COPPA';
}

function decisionLabel(
  decision:
    | 'goals'
    | 'fantasy_points'
    | 'league_champion'
    | null,
) {
  if (decision === 'goals') {
    return 'Trofeo assegnato in base al numero di gol.';
  }
  if (decision === 'fantasy_points') {
    return 'Parità nei gol: trofeo assegnato ai fantapunti.';
  }
  if (decision === 'league_champion') {
    return 'Parità perfetta: trofeo assegnato al campione del campionato precedente.';
  }
  return 'Risultato ufficializzato.';
}

function formatNumber(value: number) {
  return new Intl.NumberFormat('it-IT', {
    maximumFractionDigits: 2,
  }).format(value);
}

function formatShortDate(value: string) {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) {
    return '—';
  }
  return new Intl.DateTimeFormat('it-IT', {
    day: '2-digit',
    month: 'short',
  })
    .format(date)
    .toUpperCase();
}

function formatDate(value: string) {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) {
    return '—';
  }
  return new Intl.DateTimeFormat('it-IT', {
    day: '2-digit',
    month: 'short',
    year: 'numeric',
  })
    .format(date)
    .toUpperCase();
}

const styles = StyleSheet.create({
  screen: {
    flex: 1,
    backgroundColor: colors.canvas,
  },
  content: {
    paddingHorizontal: 20,
    paddingTop: 22,
    paddingBottom: 40,
  },
  centerRoot: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    padding: 28,
    backgroundColor: colors.canvas,
  },
  centerTitle: {
    color: colors.navy,
    fontSize: 22,
    fontWeight: '900',
    textAlign: 'center',
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
    fontSize: 10,
    fontWeight: '800',
    letterSpacing: 0.5,
  },
  title: {
    color: colors.navy,
    fontSize: 27,
    fontWeight: '900',
    marginTop: 4,
  },
  reloadButton: {
    width: 40,
    height: 40,
    borderRadius: 20,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.white,
  },
  reloadButtonDisabled: {
    opacity: 0.72,
  },
  reloadText: {
    color: colors.navy,
    fontSize: 21,
    fontWeight: '900',
  },
  feedback: {
    color: colors.navy,
    fontSize: 12,
    fontWeight: '800',
    lineHeight: 18,
    marginBottom: 12,
    padding: 13,
    borderRadius: radius.md,
    backgroundColor: colors.limeSoft,
  },
  loadingCard: {
    minHeight: 180,
    borderRadius: radius.xl,
    alignItems: 'center',
    justifyContent: 'center',
    gap: 12,
    backgroundColor: colors.navy,
  },
  loadingText: {
    color: colors.warmWhite,
    fontSize: 13,
  },
  errorCard: {
    borderRadius: radius.xl,
    padding: 24,
    backgroundColor: colors.white,
  },
  errorTitle: {
    color: colors.navy,
    fontSize: 20,
    fontWeight: '900',
  },
  errorBody: {
    color: colors.muted,
    fontSize: 13,
    lineHeight: 20,
    marginTop: 8,
  },
  primaryButton: {
    minHeight: 46,
    borderRadius: 23,
    alignItems: 'center',
    justifyContent: 'center',
    paddingHorizontal: 22,
    marginTop: 18,
    backgroundColor: colors.lime,
  },
  primaryButtonText: {
    color: colors.navy,
    fontSize: 10,
    fontWeight: '900',
  },
  introCard: {
    borderRadius: radius.xl,
    padding: 24,
    backgroundColor: colors.navy,
  },
  introEyebrow: {
    color: colors.lime,
    fontSize: 9,
    fontWeight: '900',
    letterSpacing: 0.7,
  },
  introTitle: {
    color: colors.warmWhite,
    fontSize: 25,
    lineHeight: 29,
    fontWeight: '900',
    marginTop: 8,
  },
  introBody: {
    color: colors.mutedLight,
    fontSize: 13,
    lineHeight: 20,
    marginTop: 10,
  },
  sourcePill: {
    alignSelf: 'flex-start',
    borderRadius: 14,
    paddingVertical: 7,
    paddingHorizontal: 12,
    marginTop: 18,
    backgroundColor: colors.navyLine,
  },
  sourcePillText: {
    color: colors.lime,
    fontSize: 9,
    fontWeight: '900',
  },
  heroCard: {
    borderRadius: radius.xl,
    padding: 24,
    backgroundColor: colors.navy,
  },
  certificationPill: {
    alignSelf: 'flex-start',
    borderRadius: 14,
    paddingVertical: 7,
    paddingHorizontal: 12,
    marginTop: 12,
    backgroundColor: colors.limeSoft,
  },
  certificationPillText: {
    color: colors.navy,
    fontSize: 8,
    fontWeight: '900',
    letterSpacing: 0.35,
  },
  heroEyebrow: {
    color: colors.lime,
    fontSize: 9,
    fontWeight: '900',
    letterSpacing: 0.7,
  },
  heroTitle: {
    color: colors.warmWhite,
    fontSize: 26,
    fontWeight: '900',
    marginTop: 7,
  },
  heroDate: {
    color: colors.mutedLight,
    fontSize: 10,
    fontWeight: '800',
    marginTop: 10,
  },
  matchupCard: {
    minHeight: 176,
    flexDirection: 'row',
    alignItems: 'center',
    borderRadius: radius.xl,
    padding: 20,
    marginTop: 14,
    backgroundColor: colors.white,
  },
  finalist: {
    flex: 1,
    alignItems: 'flex-start',
  },
  finalistRight: {
    alignItems: 'flex-end',
  },
  finalistMark: {
    width: 38,
    height: 38,
    borderRadius: 14,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.navy,
  },
  finalistMarkAway: {
    backgroundColor: colors.lime,
  },
  finalistMarkText: {
    color: colors.warmWhite,
    fontSize: 15,
    fontWeight: '900',
  },
  finalistName: {
    color: colors.navy,
    fontSize: 14,
    lineHeight: 17,
    fontWeight: '900',
    marginTop: 10,
  },
  finalistManager: {
    color: colors.muted,
    fontSize: 10,
    marginTop: 4,
  },
  finalistLabel: {
    color: colors.navy,
    fontSize: 7,
    fontWeight: '900',
    marginTop: 7,
  },
  finalistTextRight: {
    textAlign: 'right',
  },
  scoreColumn: {
    width: 74,
    alignItems: 'center',
  },
  versus: {
    color: colors.navy,
    fontSize: 24,
    fontWeight: '900',
  },
  points: {
    color: colors.muted,
    fontSize: 7,
    fontWeight: '800',
    textAlign: 'center',
    marginTop: 6,
  },
  ruleCard: {
    borderRadius: radius.lg,
    padding: 20,
    marginTop: 14,
    backgroundColor: colors.white,
  },
  ruleTitle: {
    color: colors.navy,
    fontSize: 15,
    fontWeight: '900',
  },
  ruleBody: {
    color: colors.muted,
    fontSize: 12,
    lineHeight: 19,
    marginTop: 7,
  },
  sectionHeader: {
    flexDirection: 'row',
    alignItems: 'flex-end',
    justifyContent: 'space-between',
    marginTop: 26,
    marginBottom: 11,
  },
  sectionTitle: {
    color: colors.navy,
    fontSize: 19,
    fontWeight: '900',
  },
  sectionMeta: {
    color: colors.muted,
    fontSize: 8,
    fontWeight: '900',
  },
  matchdayScroller: {
    marginHorizontal: -20,
    paddingLeft: 20,
  },
  matchdayChoice: {
    width: 104,
    minHeight: 116,
    borderRadius: radius.lg,
    justifyContent: 'center',
    padding: 15,
    marginRight: 10,
    backgroundColor: colors.white,
  },
  matchdayChoiceSelected: {
    backgroundColor: colors.navy,
  },
  matchdayLabel: {
    color: colors.muted,
    fontSize: 7,
    fontWeight: '900',
  },
  matchdayNumber: {
    color: colors.navy,
    fontSize: 27,
    fontWeight: '900',
    marginTop: 5,
  },
  matchdayDate: {
    color: colors.muted,
    fontSize: 9,
    fontWeight: '800',
    marginTop: 5,
  },
  matchdayTextSelected: {
    color: colors.lime,
  },
  scheduleButton: {
    minHeight: 52,
    borderRadius: 26,
    alignItems: 'center',
    justifyContent: 'center',
    marginTop: 16,
    backgroundColor: colors.lime,
  },
  scheduleButtonText: {
    color: colors.navy,
    fontSize: 10,
    fontWeight: '900',
  },
  waitingCard: {
    borderRadius: radius.lg,
    padding: 21,
    marginTop: 18,
    backgroundColor: colors.white,
  },
  waitingTitle: {
    color: colors.navy,
    fontSize: 16,
    fontWeight: '900',
  },
  waitingBody: {
    color: colors.muted,
    fontSize: 12,
    lineHeight: 19,
    marginTop: 7,
  },
  championCard: {
    alignItems: 'center',
    borderRadius: radius.xl,
    padding: 28,
    backgroundColor: colors.navy,
  },
  championMark: {
    width: 54,
    height: 54,
    borderRadius: 20,
    color: colors.navy,
    fontSize: 23,
    lineHeight: 54,
    fontWeight: '900',
    textAlign: 'center',
    backgroundColor: colors.lime,
  },
  championEyebrow: {
    color: colors.lime,
    fontSize: 9,
    fontWeight: '900',
    letterSpacing: 0.7,
    marginTop: 18,
  },
  championName: {
    color: colors.warmWhite,
    fontSize: 27,
    fontWeight: '900',
    textAlign: 'center',
    marginTop: 6,
  },
  championManager: {
    color: colors.mutedLight,
    fontSize: 12,
    marginTop: 5,
  },
  runnerUp: {
    color: colors.warmWhite,
    fontSize: 9,
    fontWeight: '800',
    marginTop: 16,
  },
  statusCard: {
    borderRadius: radius.lg,
    padding: 20,
    marginTop: 14,
    backgroundColor: colors.white,
  },
  statusTop: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
  },
  statusTitle: {
    color: colors.navy,
    fontSize: 15,
    fontWeight: '900',
  },
  statusBadge: {
    borderRadius: 11,
    paddingVertical: 6,
    paddingHorizontal: 9,
    backgroundColor: colors.canvasMuted,
  },
  statusBadgeReady: {
    backgroundColor: colors.limeSoft,
  },
  statusBadgeText: {
    color: colors.navy,
    fontSize: 7,
    fontWeight: '900',
  },
  statusBody: {
    color: colors.muted,
    fontSize: 12,
    lineHeight: 18,
    marginTop: 9,
  },
  directionCard: {
    borderRadius: radius.xl,
    padding: 22,
    marginTop: 18,
    backgroundColor: colors.navy,
  },
  directionEyebrow: {
    color: colors.lime,
    fontSize: 8,
    fontWeight: '900',
  },
  directionTitle: {
    color: colors.warmWhite,
    fontSize: 20,
    fontWeight: '900',
    marginTop: 6,
  },
  directionBody: {
    color: colors.mutedLight,
    fontSize: 12,
    lineHeight: 18,
    marginTop: 8,
  },
  finalizeButton: {
    minHeight: 50,
    borderRadius: 25,
    alignItems: 'center',
    justifyContent: 'center',
    marginTop: 18,
    backgroundColor: colors.lime,
  },
  finalizeButtonText: {
    color: colors.navy,
    fontSize: 10,
    fontWeight: '900',
  },
  buttonDisabled: {
    opacity: 0.42,
  },
});
