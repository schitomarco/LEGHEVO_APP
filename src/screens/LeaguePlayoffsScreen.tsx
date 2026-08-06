import { useEffect, useMemo, useState } from 'react';
import {
  ActivityIndicator,
  Alert,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  View,
} from 'react-native';
import { useLeaguePlayoffs } from '../hooks/useLeaguePlayoffs';
import { colors, radius } from '../theme';
import type {
  LeagueCupRound,
  LeagueCupTie,
  LeagueCupTieDecision,
  LeagueSummary,
} from '../types';

type Props = {
  league: LeagueSummary | null;
  onBack: () => void;
  onOpenLineup: () => void;
};

export function LeaguePlayoffsScreen({
  league,
  onBack,
  onOpenLineup,
}: Props) {
  const state = useLeaguePlayoffs(
    league?.id ?? null,
    Boolean(league?.isDemo),
  );
  const [participantCount, setParticipantCount] = useState<4 | 8>(4);
  const [selectedMatchday, setSelectedMatchday] = useState<number | null>(
    null,
  );
  const [feedback, setFeedback] = useState('');

  useEffect(() => {
    if (state.playoffs?.participantCount) {
      setParticipantCount(state.playoffs.participantCount);
    }
  }, [state.playoffs?.participantCount]);

  useEffect(() => {
    if (
      selectedMatchday === null &&
      state.playoffs?.startMatchdays[0]?.number
    ) {
      setSelectedMatchday(state.playoffs.startMatchdays[0].number);
    }
  }, [selectedMatchday, state.playoffs?.startMatchdays]);

  const currentRound = useMemo(
    () =>
      state.playoffs?.rounds.find(
        (round) => round.number === state.playoffs?.currentRound,
      ) ?? null,
    [state.playoffs],
  );

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

  const configure = async () => {
    setFeedback('');
    const outcome = await state.configure(participantCount);
    setFeedback(
      outcome.error ??
        `Playoff configurati per le prime ${participantCount} squadre.`,
    );
  };

  const start = async () => {
    if (selectedMatchday === null) {
      setFeedback('Scegli la giornata da cui iniziare.');
      return;
    }
    setFeedback('');
    const outcome = await state.start(selectedMatchday);
    setFeedback(
      outcome.error ??
        'Classifica congelata: teste di serie e tabellone sono ufficiali.',
    );
  };

  const confirmFinalize = () => {
    if (!currentRound) {
      return;
    }
    Alert.alert(
      `Ufficializza ${currentRound.name}`,
      'I vincitori avanzeranno. Il risultato del turno non potrà più essere modificato.',
      [
        { text: 'Annulla', style: 'cancel' },
        {
          text: 'Ufficializza',
          onPress: async () => {
            setFeedback('');
            const outcome = await state.finalizeCurrentRound();
            setFeedback(
              outcome.error ??
                (currentRound.number === state.playoffs?.roundCount
                  ? 'Playoff conclusi: il Campione LEGHEVO è ufficiale.'
                  : 'Turno ufficiale. Il tabellone è aggiornato.'),
            );
          },
        },
      ],
    );
  };

  const playoffs = state.playoffs;

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
          <Text style={styles.eyebrow}>FASE FINALE</Text>
          <Text numberOfLines={1} style={styles.title}>
            Playoff Scudetto
          </Text>
        </View>
        <Pressable
          accessibilityLabel="Aggiorna Playoff Scudetto"
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
            <ActivityIndicator color={colors.lime} size="small" />
          ) : (
            <Text style={styles.reloadText}>↻</Text>
          )}
        </Pressable>
      </View>

      {state.loading && !playoffs ? (
        <View style={styles.loadingCard}>
          <ActivityIndicator color={colors.lime} />
          <Text style={styles.loadingText}>Controllo la griglia…</Text>
        </View>
      ) : state.error && !playoffs ? (
        <View style={styles.lightCard}>
          <Text style={styles.cardTitle}>Playoff indisponibili</Text>
          <Text style={styles.cardBody}>{state.error}</Text>
          <Pressable
            onPress={() => void state.refresh()}
            style={styles.primaryButton}
          >
            <Text style={styles.primaryButtonText}>RIPROVA</Text>
          </Pressable>
        </View>
      ) : playoffs?.status === 'not_configured' ? (
        <>
          <View style={styles.heroCard}>
            <Text style={styles.heroEyebrow}>SCELTA DEL PRESIDENTE</Text>
            <Text style={styles.heroTitle}>La classifica apre le finali.</Text>
            <Text style={styles.heroBody}>
              Al termine della stagione regolare, le migliori squadre entrano
              nel tabellone. Chi vince la finale diventa Campione della lega.
            </Text>
          </View>

          <View style={styles.lightCard}>
            <Text style={styles.cardTitle}>Formato</Text>
            <Text style={styles.cardBody}>
              La configurazione si decide prima dell’avvio del campionato e
              resta congelata per tutta la stagione.
            </Text>
            <View style={styles.choiceRow}>
              {([4, 8] as const).map((count) => {
                const selected = participantCount === count;
                return (
                  <Pressable
                    key={count}
                    onPress={() => setParticipantCount(count)}
                    style={[
                      styles.choice,
                      selected && styles.choiceSelected,
                    ]}
                  >
                    <Text
                      style={[
                        styles.choiceValue,
                        selected && styles.choiceValueSelected,
                      ]}
                    >
                      TOP {count}
                    </Text>
                    <Text
                      style={[
                        styles.choiceLabel,
                        selected && styles.choiceLabelSelected,
                      ]}
                    >
                      {count === 4 ? '2 TURNI' : '3 TURNI'}
                    </Text>
                  </Pressable>
                );
              })}
            </View>
            {playoffs.canConfigure ? (
              <Pressable
                disabled={state.busy}
                onPress={() => void configure()}
                style={[
                  styles.actionButton,
                  state.busy && styles.buttonDisabled,
                ]}
              >
                {state.busy ? (
                  <ActivityIndicator color={colors.navy} size="small" />
                ) : (
                  <Text style={styles.actionButtonText}>
                    ATTIVA PLAYOFF TOP {participantCount}
                  </Text>
                )}
              </Pressable>
            ) : (
              <Text style={styles.reason}>
                {playoffs.actionReason ??
                  'Solo il Presidente può configurare i playoff.'}
              </Text>
            )}
          </View>
        </>
      ) : playoffs?.status === 'configured' ? (
        <>
          <View style={styles.heroCard}>
            <View style={styles.heroTop}>
              <View>
                <Text style={styles.heroEyebrow}>FORMATO CONGELATO</Text>
                <Text style={styles.heroTitle}>
                  Top {playoffs.participantCount}
                </Text>
              </View>
              <View style={styles.bigBadge}>
                <Text style={styles.bigBadgeValue}>
                  {playoffs.roundCount}
                </Text>
                <Text style={styles.bigBadgeLabel}>TURNI</Text>
              </View>
            </View>
            <Text style={styles.heroBody}>
              Le teste di serie saranno assegnate dalla classifica definitiva
              della stagione regolare.
            </Text>
            {playoffs.configurationCertified ? (
              <Text style={styles.configurationCertified}>
                FORMATO CERTIFICATO · ANTI-DOPPIO TOCCO
              </Text>
            ) : null}
          </View>

          {playoffs.regularSeasonReady && playoffs.canStart ? (
            <>
              <View style={styles.sectionHeader}>
                <Text style={styles.sectionTitle}>Giornata di partenza</Text>
                <Text style={styles.sectionMeta}>SERIE A</Text>
              </View>
              <ScrollView
                horizontal
                showsHorizontalScrollIndicator={false}
                style={styles.matchdayScroller}
              >
                {playoffs.startMatchdays.map((matchday) => {
                  const selected = selectedMatchday === matchday.number;
                  return (
                    <Pressable
                      key={matchday.id}
                      onPress={() => setSelectedMatchday(matchday.number)}
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
                onPress={() => void start()}
                style={[
                  styles.actionButton,
                  state.busy && styles.buttonDisabled,
                ]}
              >
                <Text style={styles.actionButtonText}>
                  CREA IL TABELLONE
                </Text>
              </Pressable>
            </>
          ) : (
            <View style={styles.lightCard}>
              <Text style={styles.cardTitle}>
                Prima si chiude la stagione regolare
              </Text>
              <Text style={styles.cardBody}>
                {playoffs.actionReason ??
                  'Il tabellone si sblocca quando tutte le partite del campionato sono ufficiali.'}
              </Text>
            </View>
          )}
        </>
      ) : playoffs ? (
        <>
          {playoffs.status === 'completed' && playoffs.champion ? (
            <View style={styles.championCard}>
              <Text style={styles.championMark}>P</Text>
              <Text style={styles.championEyebrow}>CAMPIONE LEGHEVO</Text>
              <Text style={styles.championName}>
                {playoffs.champion.teamName}
              </Text>
              <Text style={styles.championManager}>
                {playoffs.champion.managerName}
              </Text>
              {playoffs.runnerUp ? (
                <Text style={styles.runnerUp}>
                  FINALISTA · {playoffs.runnerUp.teamName}
                </Text>
              ) : null}
              {playoffs.completionCertified ? (
                <Text style={styles.configurationCertified}>
                  ESITO FINALE CERTIFICATO
                </Text>
              ) : playoffs.certifiedRoundCount > 0 ? (
                <Text style={styles.configurationCertified}>
                  TURNI CERTIFICATI · VERDETTO PROTETTO
                </Text>
              ) : playoffs.startCertified ? (
                <Text style={styles.configurationCertified}>
                  TABELLONE CERTIFICATO · AVVIO PROTETTO
                </Text>
              ) : playoffs.configurationCertified ? (
                <Text style={styles.configurationCertified}>
                  FORMATO CERTIFICATO · ANTI-DOPPIO TOCCO
                </Text>
              ) : null}
            </View>
          ) : (
            <View style={styles.heroCard}>
              <View style={styles.heroTop}>
                <View style={styles.heroMain}>
                  <Text style={styles.heroEyebrow}>PLAYOFF IN CORSO</Text>
                  <Text style={styles.heroTitle}>
                    {currentRound?.name ?? 'Fase finale'}
                  </Text>
                </View>
                <View style={styles.bigBadge}>
                  <Text style={styles.bigBadgeValue}>
                    {playoffs.currentRound}/{playoffs.roundCount}
                  </Text>
                  <Text style={styles.bigBadgeLabel}>TURNO</Text>
                </View>
              </View>
              <Text style={styles.heroBody}>
                {currentRound
                  ? `GIORNATA ${currentRound.matchdayNumber} · ${formatDate(
                      currentRound.startsAt,
                    )}`
                  : 'TABELLONE IN AGGIORNAMENTO'}
              </Text>
              {playoffs.certifiedRoundCount > 0 ? (
                <Text style={styles.configurationCertified}>
                  TURNI CERTIFICATI · VERDETTO PROTETTO
                </Text>
              ) : playoffs.startCertified ? (
                <Text style={styles.configurationCertified}>
                  TABELLONE CERTIFICATO · AVVIO PROTETTO
                </Text>
              ) : playoffs.configurationCertified ? (
                <Text style={styles.configurationCertified}>
                  FORMATO CERTIFICATO · ANTI-DOPPIO TOCCO
                </Text>
              ) : null}
              {currentRound &&
              new Date(currentRound.locksAt).getTime() > Date.now() ? (
                <Pressable
                  onPress={onOpenLineup}
                  style={styles.lineupButton}
                >
                  <Text style={styles.lineupButtonText}>
                    SCHIERA LA FORMAZIONE →
                  </Text>
                </Pressable>
              ) : null}
            </View>
          )}

          <View style={styles.sectionHeader}>
            <Text style={styles.sectionTitle}>Tabellone</Text>
            <Text style={styles.sectionMeta}>
              TOP {playoffs.participantCount}
            </Text>
          </View>
          {playoffs.rounds.map((round) => (
            <RoundCard
              current={
                playoffs.status === 'active' &&
                round.number === playoffs.currentRound
              }
              key={round.id}
              round={round}
            />
          ))}

          {playoffs.status === 'active' && playoffs.isOwner ? (
            <View style={styles.directionCard}>
              <Text style={styles.directionEyebrow}>AREA PRESIDENTE</Text>
              <Text style={styles.directionTitle}>
                {playoffs.canFinalizeCurrent
                  ? 'Il turno è pronto'
                  : 'In attesa dei voti definitivi'}
              </Text>
              <Text style={styles.directionBody}>
                {playoffs.canFinalizeCurrent
                  ? 'Ufficializzando, i vincitori avanzeranno automaticamente e il turno verrà certificato.'
                  : 'Il comando si sblocca quando la giornata reale termina e tutti i punteggi sono definitivi.'}
              </Text>
              <Pressable
                disabled={!playoffs.canFinalizeCurrent || state.busy}
                onPress={confirmFinalize}
                style={[
                  styles.finalizeButton,
                  (!playoffs.canFinalizeCurrent || state.busy) &&
                    styles.buttonDisabled,
                ]}
              >
                <Text style={styles.finalizeButtonText}>
                  UFFICIALIZZA {currentRound?.name.toUpperCase() ?? 'TURNO'}
                </Text>
              </Pressable>
            </View>
          ) : null}
        </>
      ) : null}

      {feedback ? (
        <View style={styles.feedbackCard}>
          <Text style={styles.feedbackText}>{feedback}</Text>
        </View>
      ) : null}
    </ScrollView>
  );
}

function RoundCard({
  current,
  round,
}: {
  current: boolean;
  round: LeagueCupRound;
}) {
  return (
    <View style={[styles.roundCard, current && styles.roundCardCurrent]}>
      <View style={styles.roundHeader}>
        <View>
          <Text
            style={[
              styles.roundEyebrow,
              current && styles.roundTextCurrent,
            ]}
          >
            {current ? 'TURNO ATTUALE' : statusLabel(round.status)}
          </Text>
          <Text
            style={[
              styles.roundTitle,
              current && styles.roundTextCurrent,
            ]}
          >
            {round.name}
          </Text>
        </View>
        <View style={[styles.dayBadge, current && styles.dayBadgeCurrent]}>
          <Text
            style={[
              styles.dayBadgeText,
              current && styles.dayBadgeTextCurrent,
            ]}
          >
            G {round.matchdayNumber}
          </Text>
        </View>
      </View>
      <Text
        style={[styles.roundDate, current && styles.roundDateCurrent]}
      >
        {formatDate(round.startsAt)}
      </Text>
      {round.ties.map((tie) => (
        <TieCard key={tie.id} tie={tie} />
      ))}
    </View>
  );
}

function TieCard({ tie }: { tie: LeagueCupTie }) {
  const homeWinner = tie.winnerTeamId === tie.homeTeam?.id;
  const awayWinner = tie.winnerTeamId === tie.awayTeam?.id;
  return (
    <View style={styles.tieCard}>
      <TeamRow
        goals={tie.homeGoals}
        points={tie.homePoints}
        team={tie.homeTeam}
        winner={homeWinner}
      />
      <View style={styles.divider} />
      <TeamRow
        goals={tie.awayGoals}
        points={tie.awayPoints}
        team={tie.awayTeam}
        winner={awayWinner}
      />
      <View style={styles.tieFooter}>
        <Text style={styles.tieStatus}>{tieStatusLabel(tie)}</Text>
        {tie.decidedBy && tie.decidedBy !== 'goals' ? (
          <Text style={styles.tieDecision}>
            {decisionLabel(tie.decidedBy)}
          </Text>
        ) : null}
      </View>
    </View>
  );
}

function TeamRow({
  goals,
  points,
  team,
  winner,
}: {
  goals: number | null;
  points: number | null;
  team: LeagueCupTie['homeTeam'];
  winner: boolean;
}) {
  return (
    <View style={styles.teamRow}>
      <View style={[styles.seed, winner && styles.seedWinner]}>
        <Text style={[styles.seedText, winner && styles.seedTextWinner]}>
          {team?.seed ?? '—'}
        </Text>
      </View>
      <View style={styles.teamCopy}>
        <Text
          numberOfLines={1}
          style={[styles.teamName, winner && styles.teamNameWinner]}
        >
          {team?.name ?? 'Vincente turno precedente'}
        </Text>
        <Text numberOfLines={1} style={styles.managerName}>
          {team?.managerName ?? 'ACCOPPIAMENTO IN ATTESA'}
        </Text>
      </View>
      <View style={styles.scoreCopy}>
        <Text style={[styles.goals, winner && styles.goalsWinner]}>
          {goals ?? '–'}
        </Text>
        <Text style={styles.points}>
          {points === null ? '— FP' : `${formatNumber(points)} FP`}
        </Text>
      </View>
    </View>
  );
}

function statusLabel(status: LeagueCupRound['status']) {
  if (status === 'official') return 'UFFICIALE';
  if (status === 'ready') return 'DA UFFICIALIZZARE';
  if (status === 'live') return 'IN CORSO';
  return 'PROGRAMMATO';
}

function tieStatusLabel(tie: LeagueCupTie) {
  if (tie.status === 'official') return 'RISULTATO UFFICIALE';
  if (tie.status === 'ready') return 'PUNTEGGIO DEFINITIVO';
  if (tie.status === 'live') return 'LIVE';
  return !tie.homeTeam || !tie.awayTeam ? 'DA DEFINIRE' : 'IN ATTESA';
}

function decisionLabel(decision: LeagueCupTieDecision) {
  if (decision === 'fantasy_points') return 'PASSA AI FANTAPUNTI';
  if (decision === 'seed') return 'PASSA LA MIGLIORE TESTA DI SERIE';
  return 'DECISA AI GOL';
}

function formatNumber(value: number) {
  return new Intl.NumberFormat('it-IT', {
    maximumFractionDigits: 2,
  }).format(value);
}

function formatDate(value: string) {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return 'DATA DA DEFINIRE';
  return new Intl.DateTimeFormat('it-IT', {
    weekday: 'short',
    day: '2-digit',
    month: 'short',
    year: 'numeric',
  })
    .format(date)
    .toUpperCase();
}

function formatShortDate(value: string) {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return '—';
  return new Intl.DateTimeFormat('it-IT', {
    day: '2-digit',
    month: 'short',
  })
    .format(date)
    .toUpperCase();
}

const styles = StyleSheet.create({
  screen: { flex: 1, backgroundColor: colors.canvas },
  content: {
    paddingHorizontal: 20,
    paddingTop: 22,
    paddingBottom: 38,
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
  header: { flexDirection: 'row', alignItems: 'center', marginBottom: 22 },
  backButton: {
    width: 42,
    height: 42,
    borderRadius: 21,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.white,
  },
  backText: { color: colors.navy, fontSize: 30, lineHeight: 32 },
  headerCopy: { flex: 1, marginLeft: 13 },
  eyebrow: {
    color: colors.muted,
    fontSize: 8,
    fontWeight: '900',
    letterSpacing: 0.7,
  },
  title: {
    color: colors.navy,
    fontSize: 23,
    fontWeight: '900',
    marginTop: 4,
  },
  reloadButton: {
    width: 42,
    height: 42,
    borderRadius: 21,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.navy,
  },
  reloadButtonDisabled: {
    opacity: 0.72,
  },
  reloadText: { color: colors.lime, fontSize: 19, fontWeight: '900' },
  loadingCard: {
    minHeight: 154,
    borderRadius: radius.xl,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.navy,
  },
  loadingText: { color: colors.warmWhite, fontSize: 12, marginTop: 13 },
  heroCard: {
    borderRadius: radius.xl,
    padding: 24,
    backgroundColor: colors.navy,
  },
  heroTop: {
    flexDirection: 'row',
    alignItems: 'flex-start',
    justifyContent: 'space-between',
  },
  heroMain: { flex: 1, paddingRight: 12 },
  heroEyebrow: {
    color: colors.lime,
    fontSize: 9,
    fontWeight: '900',
    letterSpacing: 0.7,
  },
  heroTitle: {
    color: colors.white,
    fontSize: 28,
    lineHeight: 31,
    fontWeight: '900',
    marginTop: 9,
  },
  heroBody: {
    color: colors.mutedLight,
    fontSize: 13,
    lineHeight: 20,
    marginTop: 11,
  },
  configurationCertified: {
    color: colors.lime,
    fontSize: 7,
    fontWeight: '900',
    marginTop: 9,
  },
  bigBadge: {
    minWidth: 58,
    borderRadius: 16,
    alignItems: 'center',
    paddingVertical: 9,
    paddingHorizontal: 10,
    backgroundColor: colors.navyLine,
  },
  bigBadgeValue: { color: colors.lime, fontSize: 19, fontWeight: '900' },
  bigBadgeLabel: {
    color: colors.mutedLight,
    fontSize: 7,
    fontWeight: '900',
    marginTop: 2,
  },
  lightCard: {
    borderRadius: radius.xl,
    padding: 22,
    backgroundColor: colors.white,
    marginTop: 14,
  },
  cardTitle: { color: colors.navy, fontSize: 18, fontWeight: '900' },
  cardBody: {
    color: colors.muted,
    fontSize: 12,
    lineHeight: 19,
    marginTop: 7,
  },
  choiceRow: { flexDirection: 'row', gap: 10, marginTop: 18 },
  choice: {
    flex: 1,
    borderWidth: 1,
    borderColor: colors.canvasMuted,
    borderRadius: radius.lg,
    padding: 16,
    backgroundColor: colors.canvas,
  },
  choiceSelected: { borderColor: colors.lime, backgroundColor: colors.navy },
  choiceValue: { color: colors.navy, fontSize: 17, fontWeight: '900' },
  choiceValueSelected: { color: colors.lime },
  choiceLabel: {
    color: colors.muted,
    fontSize: 8,
    fontWeight: '900',
    marginTop: 4,
  },
  choiceLabelSelected: { color: colors.mutedLight },
  actionButton: {
    minHeight: 52,
    borderRadius: 26,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.lime,
    marginTop: 18,
  },
  actionButtonText: { color: colors.navy, fontSize: 10, fontWeight: '900' },
  primaryButton: {
    minHeight: 44,
    borderRadius: 22,
    paddingHorizontal: 20,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.lime,
    marginTop: 18,
  },
  primaryButtonText: { color: colors.navy, fontSize: 10, fontWeight: '900' },
  reason: {
    color: colors.muted,
    fontSize: 11,
    lineHeight: 17,
    marginTop: 16,
  },
  sectionHeader: {
    flexDirection: 'row',
    alignItems: 'flex-end',
    justifyContent: 'space-between',
    marginTop: 25,
    marginBottom: 12,
  },
  sectionTitle: { color: colors.navy, fontSize: 21, fontWeight: '900' },
  sectionMeta: { color: colors.muted, fontSize: 8, fontWeight: '900' },
  matchdayScroller: { marginHorizontal: -20, paddingHorizontal: 20 },
  matchdayChoice: {
    width: 100,
    minHeight: 112,
    borderRadius: radius.lg,
    padding: 15,
    backgroundColor: colors.white,
    marginRight: 10,
  },
  matchdayChoiceSelected: { backgroundColor: colors.navy },
  matchdayLabel: { color: colors.muted, fontSize: 7, fontWeight: '900' },
  matchdayNumber: {
    color: colors.navy,
    fontSize: 26,
    fontWeight: '900',
    marginTop: 7,
  },
  matchdayDate: {
    color: colors.muted,
    fontSize: 8,
    fontWeight: '900',
    marginTop: 6,
  },
  matchdayTextSelected: { color: colors.lime },
  lineupButton: {
    minHeight: 42,
    borderRadius: 21,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.lime,
    marginTop: 18,
  },
  lineupButtonText: { color: colors.navy, fontSize: 9, fontWeight: '900' },
  championCard: {
    borderRadius: radius.xl,
    padding: 25,
    alignItems: 'center',
    backgroundColor: colors.navy,
  },
  championMark: {
    width: 52,
    height: 52,
    borderRadius: 26,
    color: colors.navy,
    fontSize: 24,
    lineHeight: 52,
    fontWeight: '900',
    textAlign: 'center',
    backgroundColor: colors.lime,
  },
  championEyebrow: {
    color: colors.lime,
    fontSize: 9,
    fontWeight: '900',
    marginTop: 15,
  },
  championName: {
    color: colors.white,
    fontSize: 25,
    fontWeight: '900',
    marginTop: 8,
  },
  championManager: { color: colors.mutedLight, fontSize: 12, marginTop: 4 },
  runnerUp: {
    color: colors.mutedLight,
    fontSize: 8,
    fontWeight: '900',
    marginTop: 16,
  },
  roundCard: {
    borderRadius: radius.xl,
    padding: 18,
    backgroundColor: colors.white,
    marginBottom: 13,
  },
  roundCardCurrent: { backgroundColor: colors.navy },
  roundHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
  },
  roundEyebrow: {
    color: colors.muted,
    fontSize: 7,
    fontWeight: '900',
  },
  roundTitle: {
    color: colors.navy,
    fontSize: 18,
    fontWeight: '900',
    marginTop: 4,
  },
  roundTextCurrent: { color: colors.lime },
  dayBadge: {
    borderRadius: 12,
    paddingHorizontal: 10,
    paddingVertical: 7,
    backgroundColor: colors.canvas,
  },
  dayBadgeCurrent: { backgroundColor: colors.navyLine },
  dayBadgeText: { color: colors.navy, fontSize: 9, fontWeight: '900' },
  dayBadgeTextCurrent: { color: colors.lime },
  roundDate: {
    color: colors.muted,
    fontSize: 8,
    fontWeight: '900',
    marginTop: 8,
    marginBottom: 12,
  },
  roundDateCurrent: { color: colors.mutedLight },
  tieCard: {
    borderRadius: radius.lg,
    padding: 13,
    backgroundColor: colors.canvas,
    marginTop: 9,
  },
  teamRow: { flexDirection: 'row', alignItems: 'center' },
  seed: {
    width: 28,
    height: 28,
    borderRadius: 14,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.white,
  },
  seedWinner: { backgroundColor: colors.lime },
  seedText: { color: colors.muted, fontSize: 10, fontWeight: '900' },
  seedTextWinner: { color: colors.navy },
  teamCopy: { flex: 1, marginLeft: 10, marginRight: 8 },
  teamName: { color: colors.navy, fontSize: 12, fontWeight: '900' },
  teamNameWinner: { color: colors.navy },
  managerName: {
    color: colors.muted,
    fontSize: 7,
    fontWeight: '800',
    marginTop: 2,
  },
  scoreCopy: { alignItems: 'flex-end' },
  goals: { color: colors.navy, fontSize: 20, fontWeight: '900' },
  goalsWinner: { color: colors.success },
  points: { color: colors.muted, fontSize: 7, marginTop: 1 },
  divider: {
    height: 1,
    backgroundColor: colors.canvasMuted,
    marginVertical: 9,
  },
  tieFooter: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    marginTop: 10,
  },
  tieStatus: { color: colors.muted, fontSize: 7, fontWeight: '900' },
  tieDecision: { color: colors.success, fontSize: 7, fontWeight: '900' },
  directionCard: {
    borderRadius: radius.xl,
    padding: 21,
    backgroundColor: colors.white,
    marginTop: 5,
  },
  directionEyebrow: {
    color: colors.muted,
    fontSize: 8,
    fontWeight: '900',
  },
  directionTitle: {
    color: colors.navy,
    fontSize: 19,
    fontWeight: '900',
    marginTop: 6,
  },
  directionBody: {
    color: colors.muted,
    fontSize: 12,
    lineHeight: 18,
    marginTop: 7,
  },
  finalizeButton: {
    minHeight: 48,
    borderRadius: 24,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.lime,
    marginTop: 17,
  },
  finalizeButtonText: { color: colors.navy, fontSize: 9, fontWeight: '900' },
  buttonDisabled: { opacity: 0.42 },
  feedbackCard: {
    borderRadius: radius.lg,
    padding: 16,
    backgroundColor: colors.navy,
    marginTop: 15,
  },
  feedbackText: {
    color: colors.warmWhite,
    fontSize: 11,
    lineHeight: 17,
    textAlign: 'center',
  },
});
