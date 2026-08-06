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
import { useLeagueCup } from '../hooks/useLeagueCup';
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
};

export function LeagueCupScreen({ league, onBack }: Props) {
  const state = useLeagueCup(
    league?.id ?? null,
    Boolean(league?.isDemo),
  );
  const [selectedMatchday, setSelectedMatchday] = useState<number | null>(
    null,
  );
  const [feedback, setFeedback] = useState('');

  useEffect(() => {
    if (
      selectedMatchday === null &&
      state.cup?.startMatchdays[0]?.number
    ) {
      setSelectedMatchday(state.cup.startMatchdays[0].number);
    }
  }, [selectedMatchday, state.cup?.startMatchdays]);

  const currentRound = useMemo(
    () =>
      state.cup?.rounds.find(
        (round) => round.number === state.cup?.currentRound,
      ) ?? null,
    [state.cup],
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

  const createCup = async () => {
    if (selectedMatchday === null) {
      setFeedback('Scegli la giornata da cui partire.');
      return;
    }
    setFeedback('');
    const outcome = await state.create(selectedMatchday);
    setFeedback(
      outcome.error ??
        'Sorteggio completato. Il tabellone è ora ufficiale.',
    );
  };

  const confirmFinalize = () => {
    if (!currentRound) {
      return;
    }
    Alert.alert(
      `Ufficializza ${currentRound.name}`,
      'I vincitori avanzeranno nel tabellone. Il turno non potrà più essere modificato.',
      [
        { text: 'Annulla', style: 'cancel' },
        {
          text: 'Ufficializza',
          onPress: async () => {
            setFeedback('');
            const outcome = await state.finalizeCurrentRound();
            setFeedback(
              outcome.error ??
                (currentRound.number === state.cup?.roundCount
                  ? 'Coppa conclusa e campione proclamato.'
                  : 'Turno ufficiale. Il tabellone è aggiornato.'),
            );
          },
        },
      ],
    );
  };

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
          <Text style={styles.eyebrow}>COMPETIZIONE PARALLELA</Text>
          <Text numberOfLines={1} style={styles.title}>
            Coppa di Lega
          </Text>
        </View>
        <Pressable
          accessibilityLabel="Aggiorna Coppa di Lega"
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

      {state.loading && !state.cup ? (
        <View style={styles.loadingCard}>
          <ActivityIndicator color={colors.lime} />
          <Text style={styles.loadingText}>Preparo il tabellone…</Text>
        </View>
      ) : state.error && !state.cup ? (
        <View style={styles.errorCard}>
          <Text style={styles.errorTitle}>Coppa indisponibile</Text>
          <Text style={styles.errorBody}>{state.error}</Text>
          <Pressable
            onPress={() => void state.refresh()}
            style={styles.primaryButton}
          >
            <Text style={styles.primaryButtonText}>RIPROVA</Text>
          </Pressable>
        </View>
      ) : state.cup && !state.cup.exists ? (
        <>
          <View style={styles.introCard}>
            <Text style={styles.introEyebrow}>NUOVA COMPETIZIONE</Text>
            <Text style={styles.introTitle}>
              Un errore e sei fuori.
            </Text>
            <Text style={styles.introBody}>
              Sorteggio casuale, eliminazione diretta e una sola formazione
              valida sia per il campionato sia per la coppa.
            </Text>
            <View style={styles.formatRow}>
              <FormatStat label="SQUADRE" value={state.cup.teamCount} />
              <FormatStat label="TABELLONE" value={state.cup.bracketSize} />
              <FormatStat label="TURNI" value={state.cup.roundCount} />
            </View>
          </View>

          <View style={styles.ruleCard}>
            <Text style={styles.ruleTitle}>Come si decide una sfida</Text>
            <Text style={styles.ruleBody}>
              Prima i gol, poi i fantapunti. Se la parità è perfetta avanza la
              testa di serie estratta al sorteggio. Gli eventuali bye vengono
              assegnati automaticamente.
            </Text>
          </View>

          {state.cup.canCreate ? (
            <>
              <View style={styles.sectionHeader}>
                <Text style={styles.sectionTitle}>Giornata di partenza</Text>
                <Text style={styles.sectionMeta}>
                  {state.cup.roundCount} TURNI
                </Text>
              </View>
              <ScrollView
                horizontal
                showsHorizontalScrollIndicator={false}
                style={styles.matchdayScroller}
              >
                {state.cup.startMatchdays.map((matchday) => {
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
                          styles.matchdayChoiceLabel,
                          selected && styles.matchdayChoiceLabelSelected,
                        ]}
                      >
                        GIORNATA
                      </Text>
                      <Text
                        style={[
                          styles.matchdayChoiceNumber,
                          selected && styles.matchdayChoiceNumberSelected,
                        ]}
                      >
                        {matchday.number}
                      </Text>
                      <Text
                        style={[
                          styles.matchdayChoiceDate,
                          selected && styles.matchdayChoiceDateSelected,
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
                onPress={() => void createCup()}
                style={[
                  styles.createButton,
                  state.busy && styles.buttonDisabled,
                ]}
              >
                {state.busy ? (
                  <ActivityIndicator color={colors.navy} size="small" />
                ) : (
                  <Text style={styles.createButtonText}>
                    SORTEGGIA LA COPPA
                  </Text>
                )}
              </Pressable>
            </>
          ) : (
            <View style={styles.waitingCard}>
              <Text style={styles.waitingTitle}>Tabellone non ancora pronto</Text>
              <Text style={styles.waitingBody}>
                {state.cup.creationReason ??
                  'Il Presidente deve ancora aprire la competizione.'}
              </Text>
            </View>
          )}
        </>
      ) : state.cup ? (
        <>
          {state.cup.status === 'completed' && state.cup.champion ? (
            <View style={styles.championCard}>
              <Text style={styles.championMark}>C</Text>
              <Text style={styles.championEyebrow}>CAMPIONE DELLA COPPA</Text>
              <Text style={styles.championName}>
                {state.cup.champion.teamName}
              </Text>
              <Text style={styles.championManager}>
                {state.cup.champion.managerName}
              </Text>
              {state.cup.runnerUp ? (
                <Text style={styles.runnerUp}>
                  FINALISTA · {state.cup.runnerUp.teamName}
                </Text>
              ) : null}
              {state.cup.completionCertified ? (
                <Text style={styles.completionCertified}>
                  ESITO FINALE CERTIFICATO
                </Text>
              ) : null}
            </View>
          ) : (
            <View style={styles.heroCard}>
              <View style={styles.heroTop}>
                <View>
                  <Text style={styles.heroEyebrow}>COPPA IN CORSO</Text>
                  <Text style={styles.heroTitle}>
                    {currentRound?.name ?? state.cup.name}
                  </Text>
                </View>
                <View style={styles.roundBadge}>
                  <Text style={styles.roundBadgeValue}>
                    {state.cup.currentRound}/{state.cup.roundCount}
                  </Text>
                  <Text style={styles.roundBadgeLabel}>TURNO</Text>
                </View>
              </View>
              <View style={styles.progressTrack}>
                <View
                  style={[
                    styles.progressValue,
                    {
                      width: `${
                        (state.cup.currentRound / state.cup.roundCount) * 100
                      }%`,
                    },
                  ]}
                />
              </View>
              <Text style={styles.heroNote}>
                {currentRound
                  ? `GIORNATA ${currentRound.matchdayNumber} · ${formatDate(
                      currentRound.startsAt,
                    )}`
                  : 'TABELLONE IN AGGIORNAMENTO'}
              </Text>
              {state.cup.drawCertified ? (
                <Text style={styles.drawCertified}>
                  SORTEGGIO CERTIFICATO · ANTI-DOPPIO TOCCO
                </Text>
              ) : null}
              {state.cup.certifiedRoundCount > 0 ? (
                <Text style={styles.roundCertified}>
                  TURNI UFFICIALI CERTIFICATI · {state.cup.certifiedRoundCount}
                </Text>
              ) : null}
            </View>
          )}

          <View style={styles.sectionHeader}>
            <Text style={styles.sectionTitle}>Tabellone</Text>
            <Text style={styles.sectionMeta}>
              {state.cup.teamCount} SQUADRE
            </Text>
          </View>

          {state.cup.rounds.map((round) => (
            <CupRoundCard
              current={
                state.cup?.status === 'active' &&
                round.number === state.cup.currentRound
              }
              key={round.id}
              round={round}
            />
          ))}

          {state.cup.status === 'active' && state.cup.isOwner ? (
            <View style={styles.directionCard}>
              <Text style={styles.directionEyebrow}>AREA PRESIDENTE</Text>
              <Text style={styles.directionTitle}>
                {state.cup.canFinalizeCurrent
                  ? 'Il turno è pronto'
                  : 'In attesa dei voti definitivi'}
              </Text>
              <Text style={styles.directionBody}>
                {state.cup.canFinalizeCurrent
                  ? 'Ufficializzando, i vincitori avanzeranno automaticamente.'
                  : 'La coppa si sblocca quando la giornata reale termina e tutte le formazioni hanno il punteggio definitivo.'}
              </Text>
              <Pressable
                disabled={!state.cup.canFinalizeCurrent || state.busy}
                onPress={confirmFinalize}
                style={[
                  styles.finalizeButton,
                  (!state.cup.canFinalizeCurrent || state.busy) &&
                    styles.finalizeButtonDisabled,
                ]}
              >
                {state.busy ? (
                  <ActivityIndicator color={colors.navy} size="small" />
                ) : (
                  <Text style={styles.finalizeButtonText}>
                    UFFICIALIZZA {currentRound?.name.toUpperCase() ?? 'TURNO'}
                  </Text>
                )}
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

function CupRoundCard({
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
              current && styles.roundEyebrowCurrent,
            ]}
          >
            {current ? 'TURNO ATTUALE' : statusLabel(round.status)}
          </Text>
          <Text
            style={[
              styles.roundTitle,
              current && styles.roundTitleCurrent,
            ]}
          >
            {round.name}
          </Text>
        </View>
        <View style={[styles.dayBadge, current && styles.dayBadgeCurrent]}>
          <Text
            style={[
              styles.dayBadgeLabel,
              current && styles.dayBadgeLabelCurrent,
            ]}
          >
            G
          </Text>
          <Text
            style={[
              styles.dayBadgeNumber,
              current && styles.dayBadgeNumberCurrent,
            ]}
          >
            {round.matchdayNumber}
          </Text>
        </View>
      </View>
      <Text
        style={[
          styles.roundDate,
          current && styles.roundDateCurrent,
        ]}
      >
        {formatDate(round.startsAt)}
      </Text>
      <View style={styles.tieList}>
        {round.ties.map((tie) => (
          <CupTieRow key={tie.id} tie={tie} />
        ))}
      </View>
    </View>
  );
}

function CupTieRow({ tie }: { tie: LeagueCupTie }) {
  const homeWinner = tie.winnerTeamId === tie.homeTeam?.id;
  const awayWinner = tie.winnerTeamId === tie.awayTeam?.id;
  const awaitingTeams = !tie.homeTeam || (!tie.awayTeam && tie.status !== 'bye');

  return (
    <View style={styles.tieCard}>
      <TeamScoreRow
        goals={tie.homeGoals}
        points={tie.homePoints}
        team={tie.homeTeam}
        winner={homeWinner}
      />
      <View style={styles.tieDivider} />
      {tie.status === 'bye' ? (
        <View style={styles.byeRow}>
          <Text style={styles.byeText}>BYE · PASSAGGIO AUTOMATICO</Text>
        </View>
      ) : (
        <TeamScoreRow
          goals={tie.awayGoals}
          points={tie.awayPoints}
          team={tie.awayTeam}
          winner={awayWinner}
        />
      )}
      <View style={styles.tieFooter}>
        <Text style={styles.tieStatus}>
          {awaitingTeams ? 'DA DEFINIRE' : tieStatusLabel(tie)}
        </Text>
        {tie.decidedBy && tie.decidedBy !== 'goals' ? (
          <Text style={styles.tieDecision}>
            {decisionLabel(tie.decidedBy)}
          </Text>
        ) : null}
      </View>
    </View>
  );
}

function TeamScoreRow({
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
      <View style={[styles.seedBadge, winner && styles.seedBadgeWinner]}>
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

function FormatStat({ label, value }: { label: string; value: number }) {
  return (
    <View style={styles.formatStat}>
      <Text style={styles.formatValue}>{value}</Text>
      <Text style={styles.formatLabel}>{label}</Text>
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
  if (tie.status === 'bye') return 'QUALIFICATA';
  return 'IN ATTESA';
}

function decisionLabel(decision: LeagueCupTieDecision) {
  if (decision === 'fantasy_points') return 'PASSA AI FANTAPUNTI';
  if (decision === 'seed') return 'PASSA PER TESTA DI SERIE';
  if (decision === 'bye') return 'BYE';
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
  screen: {
    flex: 1,
    backgroundColor: colors.canvas,
  },
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
    fontSize: 30,
    lineHeight: 32,
  },
  headerCopy: {
    flex: 1,
    marginLeft: 13,
  },
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
  reloadText: {
    color: colors.lime,
    fontSize: 19,
    fontWeight: '900',
  },
  loadingCard: {
    minHeight: 154,
    borderRadius: radius.xl,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.navy,
  },
  loadingText: {
    color: colors.warmWhite,
    fontSize: 12,
    marginTop: 13,
  },
  errorCard: {
    borderRadius: radius.xl,
    padding: 22,
    backgroundColor: colors.white,
  },
  errorTitle: {
    color: colors.navy,
    fontSize: 18,
    fontWeight: '900',
  },
  errorBody: {
    color: colors.muted,
    fontSize: 12,
    lineHeight: 19,
    marginTop: 7,
  },
  primaryButton: {
    minHeight: 44,
    borderRadius: 22,
    paddingHorizontal: 20,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.lime,
    marginTop: 18,
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
    color: colors.white,
    fontSize: 28,
    lineHeight: 31,
    fontWeight: '900',
    marginTop: 9,
  },
  introBody: {
    color: colors.mutedLight,
    fontSize: 13,
    lineHeight: 20,
    marginTop: 10,
  },
  formatRow: {
    flexDirection: 'row',
    borderTopWidth: 1,
    borderTopColor: colors.navyLine,
    marginTop: 22,
    paddingTop: 18,
  },
  formatStat: {
    flex: 1,
  },
  formatValue: {
    color: colors.lime,
    fontSize: 22,
    fontWeight: '900',
  },
  formatLabel: {
    color: colors.mutedLight,
    fontSize: 7,
    fontWeight: '900',
    marginTop: 3,
  },
  ruleCard: {
    borderRadius: radius.lg,
    padding: 19,
    backgroundColor: colors.white,
    marginTop: 14,
  },
  ruleTitle: {
    color: colors.navy,
    fontSize: 15,
    fontWeight: '900',
  },
  ruleBody: {
    color: colors.muted,
    fontSize: 12,
    lineHeight: 18,
    marginTop: 7,
  },
  sectionHeader: {
    flexDirection: 'row',
    alignItems: 'flex-end',
    justifyContent: 'space-between',
    marginTop: 25,
    marginBottom: 12,
  },
  sectionTitle: {
    color: colors.navy,
    fontSize: 21,
    fontWeight: '900',
  },
  sectionMeta: {
    color: colors.muted,
    fontSize: 8,
    fontWeight: '900',
  },
  matchdayScroller: {
    marginHorizontal: -20,
    paddingHorizontal: 20,
  },
  matchdayChoice: {
    width: 104,
    minHeight: 116,
    borderRadius: radius.lg,
    padding: 15,
    backgroundColor: colors.white,
    marginRight: 10,
  },
  matchdayChoiceSelected: {
    backgroundColor: colors.navy,
  },
  matchdayChoiceLabel: {
    color: colors.muted,
    fontSize: 7,
    fontWeight: '900',
  },
  matchdayChoiceLabelSelected: {
    color: colors.mutedLight,
  },
  matchdayChoiceNumber: {
    color: colors.navy,
    fontSize: 29,
    fontWeight: '900',
    marginTop: 6,
  },
  matchdayChoiceNumberSelected: {
    color: colors.lime,
  },
  matchdayChoiceDate: {
    color: colors.muted,
    fontSize: 8,
    fontWeight: '900',
    marginTop: 8,
  },
  matchdayChoiceDateSelected: {
    color: colors.white,
  },
  createButton: {
    minHeight: 54,
    borderRadius: 27,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.lime,
    marginTop: 18,
  },
  createButtonText: {
    color: colors.navy,
    fontSize: 11,
    fontWeight: '900',
    letterSpacing: 0.4,
  },
  buttonDisabled: {
    opacity: 0.55,
  },
  waitingCard: {
    borderRadius: radius.lg,
    padding: 20,
    backgroundColor: colors.white,
    marginTop: 16,
  },
  waitingTitle: {
    color: colors.navy,
    fontSize: 16,
    fontWeight: '900',
  },
  waitingBody: {
    color: colors.muted,
    fontSize: 12,
    lineHeight: 18,
    marginTop: 6,
  },
  heroCard: {
    borderRadius: radius.xl,
    padding: 22,
    backgroundColor: colors.navy,
  },
  heroTop: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'flex-start',
  },
  heroEyebrow: {
    color: colors.lime,
    fontSize: 8,
    fontWeight: '900',
    letterSpacing: 0.7,
  },
  heroTitle: {
    color: colors.white,
    fontSize: 25,
    fontWeight: '900',
    marginTop: 6,
  },
  roundBadge: {
    minWidth: 56,
    borderRadius: 18,
    alignItems: 'center',
    paddingVertical: 9,
    backgroundColor: colors.lime,
  },
  roundBadgeValue: {
    color: colors.navy,
    fontSize: 15,
    fontWeight: '900',
  },
  roundBadgeLabel: {
    color: colors.navy,
    fontSize: 6,
    fontWeight: '900',
    marginTop: 2,
  },
  progressTrack: {
    height: 7,
    borderRadius: 999,
    overflow: 'hidden',
    backgroundColor: colors.navyLine,
    marginTop: 24,
  },
  progressValue: {
    height: '100%',
    borderRadius: 999,
    backgroundColor: colors.lime,
  },
  heroNote: {
    color: colors.mutedLight,
    fontSize: 8,
    fontWeight: '900',
    marginTop: 9,
  },
  drawCertified: {
    color: colors.lime,
    fontSize: 7,
    fontWeight: '900',
    marginTop: 7,
  },
  roundCertified: {
    color: colors.mutedLight,
    fontSize: 7,
    fontWeight: '900',
    marginTop: 5,
  },
  championCard: {
    borderRadius: radius.xl,
    padding: 26,
    alignItems: 'center',
    backgroundColor: colors.navy,
  },
  championMark: {
    width: 58,
    height: 58,
    borderRadius: 20,
    color: colors.navy,
    backgroundColor: colors.lime,
    textAlign: 'center',
    textAlignVertical: 'center',
    fontSize: 26,
    lineHeight: 58,
    fontWeight: '900',
    overflow: 'hidden',
  },
  championEyebrow: {
    color: colors.lime,
    fontSize: 8,
    fontWeight: '900',
    letterSpacing: 0.8,
    marginTop: 18,
  },
  championName: {
    color: colors.white,
    fontSize: 27,
    fontWeight: '900',
    textAlign: 'center',
    marginTop: 7,
  },
  championManager: {
    color: colors.mutedLight,
    fontSize: 12,
    marginTop: 5,
  },
  runnerUp: {
    color: colors.mutedLight,
    fontSize: 8,
    fontWeight: '900',
    marginTop: 18,
  },
  completionCertified: {
    color: colors.lime,
    fontSize: 8,
    fontWeight: '900',
    letterSpacing: 0.8,
    marginTop: 12,
  },
  roundCard: {
    borderRadius: radius.xl,
    padding: 18,
    backgroundColor: colors.white,
    marginBottom: 13,
  },
  roundCardCurrent: {
    backgroundColor: colors.navy,
  },
  roundHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'flex-start',
  },
  roundEyebrow: {
    color: colors.muted,
    fontSize: 7,
    fontWeight: '900',
    letterSpacing: 0.5,
  },
  roundEyebrowCurrent: {
    color: colors.lime,
  },
  roundTitle: {
    color: colors.navy,
    fontSize: 18,
    fontWeight: '900',
    marginTop: 5,
  },
  roundTitleCurrent: {
    color: colors.white,
  },
  dayBadge: {
    minWidth: 43,
    height: 43,
    borderRadius: 15,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.canvasMuted,
  },
  dayBadgeCurrent: {
    backgroundColor: colors.lime,
  },
  dayBadgeLabel: {
    color: colors.muted,
    fontSize: 8,
    fontWeight: '900',
    marginRight: 2,
  },
  dayBadgeLabelCurrent: {
    color: colors.navy,
  },
  dayBadgeNumber: {
    color: colors.navy,
    fontSize: 14,
    fontWeight: '900',
  },
  dayBadgeNumberCurrent: {
    color: colors.navy,
  },
  roundDate: {
    color: colors.muted,
    fontSize: 8,
    fontWeight: '900',
    marginTop: 8,
  },
  roundDateCurrent: {
    color: colors.mutedLight,
  },
  tieList: {
    marginTop: 15,
  },
  tieCard: {
    borderRadius: radius.md,
    overflow: 'hidden',
    backgroundColor: colors.canvas,
    marginTop: 9,
  },
  teamRow: {
    minHeight: 62,
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 12,
  },
  seedBadge: {
    width: 28,
    height: 28,
    borderRadius: 10,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.canvasMuted,
  },
  seedBadgeWinner: {
    backgroundColor: colors.lime,
  },
  seedText: {
    color: colors.muted,
    fontSize: 10,
    fontWeight: '900',
  },
  seedTextWinner: {
    color: colors.navy,
  },
  teamCopy: {
    flex: 1,
    marginLeft: 10,
  },
  teamName: {
    color: colors.navy,
    fontSize: 12,
    fontWeight: '800',
  },
  teamNameWinner: {
    fontWeight: '900',
  },
  managerName: {
    color: colors.muted,
    fontSize: 8,
    marginTop: 3,
  },
  scoreCopy: {
    alignItems: 'flex-end',
    marginLeft: 8,
  },
  goals: {
    color: colors.navy,
    fontSize: 19,
    fontWeight: '900',
  },
  goalsWinner: {
    color: '#5C8A00',
  },
  points: {
    color: colors.muted,
    fontSize: 7,
    fontWeight: '900',
    marginTop: 2,
  },
  tieDivider: {
    height: 1,
    backgroundColor: colors.canvasMuted,
    marginHorizontal: 12,
  },
  byeRow: {
    minHeight: 44,
    alignItems: 'center',
    justifyContent: 'center',
  },
  byeText: {
    color: colors.muted,
    fontSize: 7,
    fontWeight: '900',
  },
  tieFooter: {
    minHeight: 28,
    paddingHorizontal: 12,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    backgroundColor: colors.canvasMuted,
  },
  tieStatus: {
    color: colors.muted,
    fontSize: 7,
    fontWeight: '900',
  },
  tieDecision: {
    color: colors.navy,
    fontSize: 7,
    fontWeight: '900',
  },
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
    fontSize: 18,
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
    minHeight: 50,
    borderRadius: 25,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.lime,
    marginTop: 17,
  },
  finalizeButtonDisabled: {
    backgroundColor: colors.canvasMuted,
  },
  finalizeButtonText: {
    color: colors.navy,
    fontSize: 9,
    fontWeight: '900',
  },
  feedbackCard: {
    borderRadius: radius.md,
    padding: 16,
    backgroundColor: colors.navy,
    marginTop: 14,
  },
  feedbackText: {
    color: colors.white,
    fontSize: 11,
    lineHeight: 17,
    textAlign: 'center',
  },
});
