import { useEffect, useMemo, useState } from 'react';
import {
  ActivityIndicator,
  Alert,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  TextInput,
  View,
} from 'react-native';
import { useLeagueCalendar } from '../hooks/useLeagueCalendar';
import { fetchCalendarSchedulePreview } from '../services/calendarService';
import { colors, radius } from '../theme';
import type {
  CalendarFixture,
  CalendarSchedulePreview,
  CalendarTeamReadiness,
  LeagueCalendarState,
  LeagueScheduleHealth,
  LeagueSummary,
} from '../types';

type Props = {
  currentUserId: string | null;
  league: LeagueSummary | null;
  onBack: () => void;
};

export function CalendarScreen({
  currentUserId,
  league,
  onBack,
}: Props) {
  const calendar = useLeagueCalendar(
    league?.id ?? null,
    Boolean(league?.isDemo),
  );
  const [selectedMatchday, setSelectedMatchday] = useState<number | null>(null);
  const [season, setSeason] = useState(String(new Date().getFullYear()));
  const [startMatchday, setStartMatchday] = useState('1');
  const [returnLeg, setReturnLeg] = useState(true);
  const [feedback, setFeedback] = useState('');
  const [feedbackSuccess, setFeedbackSuccess] = useState(false);
  const [busyAction, setBusyAction] = useState('');
  const [schedulePreview, setSchedulePreview] =
    useState<CalendarSchedulePreview | null>(null);
  const [schedulePreviewLoading, setSchedulePreviewLoading] =
    useState(false);
  const [schedulePreviewError, setSchedulePreviewError] = useState('');

  const matchdays = useMemo(
    () => [...new Set(calendar.fixtures.map((item) => item.matchdayNumber))],
    [calendar.fixtures],
  );

  useEffect(() => {
    if (
      matchdays.length > 0 &&
      (selectedMatchday === null || !matchdays.includes(selectedMatchday))
    ) {
      setSelectedMatchday(
        findInitialMatchday(matchdays, calendar.fixtures),
      );
    }
  }, [calendar.fixtures, matchdays, selectedMatchday]);

  const parsedMatchday = Number.parseInt(startMatchday, 10);
  const projection = calculateProjection(
    calendar.state?.teamLimit ?? league?.teamLimit ?? 2,
    Number.isFinite(parsedMatchday) ? parsedMatchday : 1,
    returnLeg,
  );

  useEffect(() => {
    if (
      !league ||
      league.isDemo ||
      calendar.fixtures.length > 0 ||
      !/^\d{4}$/.test(season.trim()) ||
      !Number.isFinite(parsedMatchday) ||
      parsedMatchday < 1 ||
      projection.lastMatchday > 38
    ) {
      setSchedulePreview(null);
      setSchedulePreviewError('');
      setSchedulePreviewLoading(false);
      return;
    }

    let active = true;
    setSchedulePreviewLoading(true);
    setSchedulePreviewError('');

    void fetchCalendarSchedulePreview(
      season.trim(),
      parsedMatchday,
      projection.lastMatchday,
    )
      .then((nextPreview) => {
        if (active) {
          setSchedulePreview(nextPreview);
        }
      })
      .catch((caught) => {
        if (active) {
          setSchedulePreview(null);
          setSchedulePreviewError(
            caught instanceof Error
              ? caught.message
              : 'Le date della Serie A non sono disponibili.',
          );
        }
      })
      .finally(() => {
        if (active) {
          setSchedulePreviewLoading(false);
        }
      });

    return () => {
      active = false;
    };
  }, [
    calendar.fixtures.length,
    league?.id,
    league?.isDemo,
    parsedMatchday,
    projection.lastMatchday,
    season,
  ]);

  if (!league) {
    return (
      <View style={styles.missingRoot}>
        <Text style={styles.missingTitle}>Prima scegli una lega.</Text>
        <Pressable onPress={onBack} style={styles.primaryButton}>
          <Text style={styles.primaryButtonText}>TORNA ALLA LEGA</Text>
        </Pressable>
      </View>
    );
  }

  const state = calendar.state;
  const isOwner =
    Boolean(league.isDemo) ||
    state?.isOwner === true ||
    league.ownerId === currentUserId;
  const selectedFixtures = calendar.fixtures.filter(
    (item) => item.matchdayNumber === selectedMatchday,
  );
  const selectedSchedule = selectedFixtures[0] ?? null;

  const generate = async () => {
    if (
      !Number.isFinite(parsedMatchday) ||
      parsedMatchday < 1 ||
      parsedMatchday > 38
    ) {
      showFeedback(
        'La giornata iniziale deve essere compresa tra 1 e 38.',
        false,
      );
      return;
    }
    if (!/^\d{4}$/.test(season.trim())) {
      showFeedback(
        'Inserisci la stagione con quattro cifre, ad esempio 2026.',
        false,
      );
      return;
    }
    if (projection.lastMatchday > 38) {
      showFeedback(
        `Questa formula termina alla giornata ${projection.lastMatchday}. Scegli una partenza precedente.`,
        false,
      );
      return;
    }
    if (!state?.canGenerate) {
      showFeedback(
        'Il sorteggio si sblocca quando partecipanti, squadre e rose sono completi.',
        false,
      );
      return;
    }

    const estimatedFirstKickoff = new Date();
    estimatedFirstKickoff.setDate(estimatedFirstKickoff.getDate() + 7);
    estimatedFirstKickoff.setHours(18, 0, 0, 0);
    const firstKickoff =
      schedulePreview?.firstKickoff ??
      estimatedFirstKickoff.toISOString();

    setBusyAction('generate');
    setFeedback('');
    const outcome = await calendar.generate({
      season: season.trim(),
      startMatchday: parsedMatchday,
      firstKickoff,
      returnLeg,
    });
    setBusyAction('');

    if (outcome.error) {
      showFeedback(outcome.error, false);
      return;
    }

    showFeedback(
      `Calendario creato: ${outcome.affected ?? 0} partite pubblicate.`,
      true,
    );
  };

  const reset = async () => {
    setBusyAction('reset');
    setFeedback('');
    const outcome = await calendar.reset();
    setBusyAction('');

    if (outcome.error) {
      showFeedback(outcome.error, false);
      return;
    }

    setSelectedMatchday(null);
    showFeedback(
      `Calendario annullato: ${outcome.affected ?? 0} partite rimosse.`,
      true,
    );
  };

  const confirmReset = () => {
    Alert.alert(
      'Annullare il calendario?',
      'Giornate, accoppiamenti e formazioni già preparate verranno rimossi. Potrai effettuare un nuovo sorteggio prima dell’avvio.',
      [
        { text: 'TIENI IL CALENDARIO', style: 'cancel' },
        {
          text: 'ANNULLA CALENDARIO',
          style: 'destructive',
          onPress: () => void reset(),
        },
      ],
    );
  };

  function showFeedback(message: string, success: boolean) {
    setFeedback(message);
    setFeedbackSuccess(success);
  }

  return (
    <ScrollView
      style={styles.screen}
      contentContainerStyle={styles.content}
      showsVerticalScrollIndicator={false}
    >
      <View style={styles.header}>
        <Pressable onPress={onBack} style={styles.backButton}>
          <Text style={styles.backText}>‹</Text>
        </Pressable>
        <View style={styles.headerCopy}>
          <Text style={styles.eyebrow}>CALENDARIO LEGA</Text>
          <Text numberOfLines={1} style={styles.title}>
            {league.name}
          </Text>
        </View>
      </View>

      {calendar.loading ? (
        <LoadingCard />
      ) : calendar.error ? (
        <ErrorCard
          message={calendar.error}
          onRetry={() => void calendar.refresh()}
        />
      ) : !state ? (
        <ErrorCard
          message="Lo stato del calendario non è disponibile."
          onRetry={() => void calendar.refresh()}
        />
      ) : calendar.fixtures.length === 0 ? (
        <CalendarSetup
          busy={busyAction === 'generate'}
          feedback={feedback}
          feedbackSuccess={feedbackSuccess}
          isOwner={isOwner}
          onGenerate={() => void generate()}
          onReturnLegChange={setReturnLeg}
          onSeasonChange={setSeason}
          onStartMatchdayChange={setStartMatchday}
          projection={projection}
          returnLeg={returnLeg}
          schedulePreview={schedulePreview}
          schedulePreviewError={schedulePreviewError}
          schedulePreviewLoading={schedulePreviewLoading}
          season={season}
          startMatchday={startMatchday}
          state={state}
        />
      ) : (
        <>
          <CalendarSummary
            health={calendar.scheduleHealth}
            state={state}
          />

          <View style={styles.sectionHeader}>
            <View>
              <Text style={styles.sectionEyebrow}>TURNO SELEZIONATO</Text>
              <Text style={styles.sectionTitle}>Giornate</Text>
            </View>
            <Text style={styles.rangeLabel}>
              {state.firstMatchday ?? matchdays[0]}–
              {state.lastMatchday ?? matchdays[matchdays.length - 1]}
            </Text>
          </View>

          <ScrollView
            horizontal
            contentContainerStyle={styles.roundsRow}
            showsHorizontalScrollIndicator={false}
          >
            {matchdays.map((matchday) => (
              <Pressable
                accessibilityLabel={`Giornata ${matchday}`}
                key={matchday}
                onPress={() => setSelectedMatchday(matchday)}
                style={[
                  styles.roundButton,
                  selectedMatchday === matchday && styles.roundButtonActive,
                ]}
              >
                <Text
                  style={[
                    styles.roundNumber,
                    selectedMatchday === matchday && styles.roundNumberActive,
                  ]}
                >
                  {matchday}
                </Text>
                <Text
                  style={[
                    styles.roundLabel,
                    selectedMatchday === matchday && styles.roundLabelActive,
                  ]}
                >
                  GIORNATA
                </Text>
              </Pressable>
            ))}
          </ScrollView>

          <View style={styles.fixtureHeader}>
            <View>
              <Text style={styles.fixtureEyebrow}>ACCOPPIAMENTI</Text>
              <Text style={styles.fixtureTitle}>
                Giornata {selectedMatchday ?? '—'}
              </Text>
            </View>
            <View style={styles.fixtureDateColumn}>
              <Text style={styles.fixtureDate}>
                {formatDate(selectedSchedule?.startsAt)}
              </Text>
              <Text
                style={[
                  styles.scheduleSource,
                  selectedSchedule?.scheduleSource === 'provider' &&
                    styles.scheduleSourceProvider,
                ]}
              >
                {selectedSchedule?.scheduleSource === 'provider'
                  ? 'DATA SERIE A'
                  : 'DATA STIMATA'}
              </Text>
            </View>
          </View>

          {selectedSchedule ? (
            <MatchdayScheduleCard fixture={selectedSchedule} />
          ) : null}

          <View style={styles.fixturesCard}>
            {selectedFixtures.map((fixture) => (
              <FixtureRow
                currentUserId={
                  league.isDemo ? 'demo-user' : currentUserId
                }
                fixture={fixture}
                key={fixture.id}
              />
            ))}
          </View>

          {feedback ? (
            <Feedback message={feedback} success={feedbackSuccess} />
          ) : null}

          {!league.isDemo && state.canReset ? (
            <View style={styles.resetCard}>
              <View style={styles.resetCopy}>
                <Text style={styles.resetTitle}>Sorteggio da rifare?</Text>
                <Text style={styles.resetBody}>
                  Il Presidente può annullarlo solo prima dell’avvio ufficiale.
                </Text>
              </View>
              <Pressable
                disabled={busyAction === 'reset'}
                onPress={confirmReset}
                style={[
                  styles.resetButton,
                  busyAction === 'reset' && styles.buttonDisabled,
                ]}
              >
                <Text style={styles.resetButtonText}>
                  {busyAction === 'reset' ? 'ANNULLAMENTO…' : 'ANNULLA'}
                </Text>
              </Pressable>
            </View>
          ) : null}
        </>
      )}
    </ScrollView>
  );
}

function LoadingCard() {
  return (
    <View style={styles.loadingCard}>
      <ActivityIndicator color={colors.lime} size="large" />
      <Text style={styles.loadingTitle}>Prepariamo il tabellone</Text>
      <Text style={styles.loadingText}>
        Controllo squadre, rose e giornate disponibili.
      </Text>
    </View>
  );
}

function ErrorCard({
  message,
  onRetry,
}: {
  message: string;
  onRetry: () => void;
}) {
  return (
    <View style={styles.errorCard}>
      <Text style={styles.errorTitle}>Calendario indisponibile</Text>
      <Text style={styles.errorBody}>{message}</Text>
      <Pressable onPress={onRetry} style={styles.retryButton}>
        <Text style={styles.retryButtonText}>RIPROVA</Text>
      </Pressable>
    </View>
  );
}

function CalendarSetup({
  busy,
  feedback,
  feedbackSuccess,
  isOwner,
  onGenerate,
  onReturnLegChange,
  onSeasonChange,
  onStartMatchdayChange,
  projection,
  returnLeg,
  schedulePreview,
  schedulePreviewError,
  schedulePreviewLoading,
  season,
  startMatchday,
  state,
}: {
  busy: boolean;
  feedback: string;
  feedbackSuccess: boolean;
  isOwner: boolean;
  onGenerate: () => void;
  onReturnLegChange: (value: boolean) => void;
  onSeasonChange: (value: string) => void;
  onStartMatchdayChange: (value: string) => void;
  projection: CalendarProjection;
  returnLeg: boolean;
  schedulePreview: CalendarSchedulePreview | null;
  schedulePreviewError: string;
  schedulePreviewLoading: boolean;
  season: string;
  startMatchday: string;
  state: LeagueCalendarState;
}) {
  return (
    <>
      <View style={styles.setupHero}>
        <View style={styles.setupBadge}>
          <Text style={styles.setupBadgeText}>VS</Text>
        </View>
        <Text style={styles.setupEyebrow}>PRIMA DEL SORTEGGIO</Text>
        <Text style={styles.setupTitle}>Costruiamo il campionato</Text>
        <Text style={styles.setupBody}>
          LEGHEVO verifica rose, crediti, trattative e Asta Live prima di
          generare accoppiamenti senza duplicati.
        </Text>
      </View>

      <View style={styles.readinessCard}>
        <View style={styles.readinessHeader}>
          <View>
            <Text style={styles.cardEyebrow}>CONTROLLI AUTOMATICI</Text>
            <Text style={styles.cardTitle}>Pronti al sorteggio</Text>
          </View>
          <View
            style={[
              styles.readinessBadge,
              state.canGenerate && styles.readinessBadgeReady,
            ]}
          >
            <Text
              style={[
                styles.readinessBadgeText,
                state.canGenerate && styles.readinessBadgeTextReady,
              ]}
            >
              {state.canGenerate ? 'PRONTO' : 'IN ATTESA'}
            </Text>
          </View>
        </View>

        <CheckRow
          complete={state.checks.membersReady}
          detail={`${state.memberCount}/${state.teamLimit}`}
          label="Partecipanti"
        />
        <CheckRow
          complete={state.checks.teamsReady}
          detail={`${state.teamCount}/${state.teamLimit}`}
          label="Squadre create"
        />
        <CheckRow
          complete={state.checks.rostersReady}
          detail={`${state.fullRosterCount}/${state.teamLimit}`}
          label="Rose complete"
        />
        <CheckRow
          complete={state.checks.marketReady}
          detail={state.checks.marketReady ? 'INTEGRO' : 'DA VERIFICARE'}
          label="Mercato e crediti"
        />
        <CheckRow
          complete={state.checks.tradesSettled}
          detail={
            state.checks.tradesSettled
              ? 'NESSUNA APERTA'
              : `${state.preflight.pendingTradeCount} IN ATTESA`
          }
          label="Trattative"
        />
        <CheckRow
          complete={
            state.checks.auctionIntegrityReady &&
            state.checks.auctionClosed
          }
          detail={
            state.checks.auctionClosed
              ? 'CONCLUSA'
              : `${state.preflight.unfinishedAuctionCount} APERTA`
          }
          label="Asta pre-campionato"
        />
        <CheckRow
          complete={state.checks.competitionNotStarted}
          detail={
            state.checks.competitionNotStarted ? 'LIBERO' : 'BLOCCATO'
          }
          label="Pre-campionato"
        />
        {state.calendarExists ? (
          <CheckRow
            complete={
              state.checks.precompetitionSnapshotLocked &&
              state.checks.snapshotMutationGuardReady
            }
            detail={
              state.checks.precompetitionSnapshotLocked &&
              state.checks.snapshotMutationGuardReady
                ? 'CONGELATO'
                : 'DA PROTEGGERE'
            }
            label="Assetto iniziale"
          />
        ) : null}
      </View>

      <View style={styles.teamsCard}>
        <Text style={styles.cardEyebrow}>SPOGLIATOIO</Text>
        <Text style={styles.cardTitle}>Stato delle rose</Text>
        <View style={styles.teamsList}>
          {state.teams.map((team) => (
            <TeamReadinessRow key={team.teamId} team={team} />
          ))}
          {Array.from({
            length: Math.max(state.teamLimit - state.teams.length, 0),
          }).map((_, index) => (
            <View key={`open-slot-${index}`} style={styles.openTeamRow}>
              <View style={styles.openTeamIcon}>
                <Text style={styles.openTeamIconText}>+</Text>
              </View>
              <Text style={styles.openTeamText}>Posto ancora libero</Text>
            </View>
          ))}
        </View>
      </View>

      {isOwner ? (
        <View style={styles.configurationCard}>
          <Text style={styles.cardEyebrow}>IMPOSTAZIONI PRESIDENTE</Text>
          <Text style={styles.cardTitle}>Formula del campionato</Text>

          <View style={styles.doubleField}>
            <View style={styles.halfField}>
              <Text style={styles.fieldLabel}>STAGIONE</Text>
              <TextInput
                keyboardType="number-pad"
                maxLength={4}
                onChangeText={onSeasonChange}
                style={styles.input}
                value={season}
              />
            </View>
            <View style={styles.halfField}>
              <Text style={styles.fieldLabel}>DA GIORNATA</Text>
              <TextInput
                keyboardType="number-pad"
                maxLength={2}
                onChangeText={onStartMatchdayChange}
                style={styles.input}
                value={startMatchday}
              />
            </View>
          </View>

          <Text style={styles.fieldLabel}>FORMULA</Text>
          <View style={styles.choiceRow}>
            <Choice
              active={returnLeg}
              label="ANDATA + RITORNO"
              onPress={() => onReturnLegChange(true)}
            />
            <Choice
              active={!returnLeg}
              label="SOLO ANDATA"
              onPress={() => onReturnLegChange(false)}
            />
          </View>

          <View style={styles.projectionCard}>
            <ProjectionStat
              label="GIORNATE"
              value={String(projection.rounds)}
            />
            <View style={styles.projectionDivider} />
            <ProjectionStat
              label="PARTITE"
              value={String(projection.fixtures)}
            />
            <View style={styles.projectionDivider} />
            <ProjectionStat
              label="ULTIMA"
              value={String(projection.lastMatchday)}
            />
          </View>

          <SchedulePreviewCard
            error={schedulePreviewError}
            loading={schedulePreviewLoading}
            preview={schedulePreview}
          />

          {feedback ? (
            <Feedback message={feedback} success={feedbackSuccess} />
          ) : null}

          <Pressable
            disabled={busy || !state.canGenerate}
            onPress={onGenerate}
            style={[
              styles.primaryButton,
              (busy || !state.canGenerate) && styles.buttonDisabled,
            ]}
          >
            <Text style={styles.primaryButtonText}>
              {busy
                ? 'SORTEGGIO IN CORSO…'
                : state.canGenerate
                  ? 'GENERA CALENDARIO'
                  : 'PRE-CAMPIONATO NON COMPLETO'}
            </Text>
          </Pressable>
        </View>
      ) : (
        <View style={styles.managerNotice}>
          <View style={styles.managerBadge}>
            <Text style={styles.managerBadgeText}>P</Text>
          </View>
          <View style={styles.managerCopy}>
            <Text style={styles.managerNoticeTitle}>
              La decisione spetta al Presidente
            </Text>
            <Text style={styles.managerNoticeBody}>
              Potrai vedere il sorteggio in tempo reale appena verrà
              pubblicato.
            </Text>
          </View>
        </View>
      )}
    </>
  );
}

function CheckRow({
  complete,
  detail,
  label,
}: {
  complete: boolean;
  detail: string;
  label: string;
}) {
  return (
    <View style={styles.checkRow}>
      <View
        style={[
          styles.checkIcon,
          complete && styles.checkIconComplete,
        ]}
      >
        <Text
          style={[
            styles.checkIconText,
            complete && styles.checkIconTextComplete,
          ]}
        >
          {complete ? '✓' : '·'}
        </Text>
      </View>
      <Text style={styles.checkLabel}>{label}</Text>
      <Text
        style={[
          styles.checkDetail,
          complete && styles.checkDetailComplete,
        ]}
      >
        {detail}
      </Text>
    </View>
  );
}

function TeamReadinessRow({ team }: { team: CalendarTeamReadiness }) {
  return (
    <View style={styles.teamReadyRow}>
      <View
        style={[
          styles.teamReadyIcon,
          team.complete && styles.teamReadyIconComplete,
        ]}
      >
        <Text
          style={[
            styles.teamReadyIconText,
            team.complete && styles.teamReadyIconTextComplete,
          ]}
        >
          {team.complete ? '✓' : team.rosterCount}
        </Text>
      </View>
      <View style={styles.teamReadyCopy}>
        <Text numberOfLines={1} style={styles.teamReadyName}>
          {team.teamName}
        </Text>
        <Text style={styles.teamReadyRoster}>
          ROSA {team.rosterCount}/{team.rosterSize}
        </Text>
      </View>
      <Text
        style={[
          styles.teamReadyStatus,
          team.complete && styles.teamReadyStatusComplete,
        ]}
      >
        {team.complete ? 'COMPLETA' : 'DA COMPLETARE'}
      </Text>
    </View>
  );
}

function Choice({
  active,
  label,
  onPress,
}: {
  active: boolean;
  label: string;
  onPress: () => void;
}) {
  return (
    <Pressable
      onPress={onPress}
      style={[styles.choice, active && styles.choiceActive]}
    >
      <Text style={[styles.choiceText, active && styles.choiceTextActive]}>
        {label}
      </Text>
    </Pressable>
  );
}

function ProjectionStat({ label, value }: { label: string; value: string }) {
  return (
    <View style={styles.projectionStat}>
      <Text style={styles.projectionNumber}>{value}</Text>
      <Text style={styles.projectionLabel}>{label}</Text>
    </View>
  );
}

function CalendarSummary({
  health,
  state,
}: {
  health: LeagueScheduleHealth | null;
  state: LeagueCalendarState;
}) {
  const aligned = health?.providerAlignedMatchdays ?? 0;
  const total = health?.matchdayCount ?? state.matchdayCount;

  return (
    <View style={styles.summaryCard}>
      <View style={styles.summaryTop}>
        <View>
          <Text style={styles.summaryLabel}>
            STAGIONE {state.season ?? '—'}
          </Text>
          <Text style={styles.summaryTitle}>
            {state.returnLeg ? 'Andata + ritorno' : 'Solo andata'}
          </Text>
        </View>
        <View
          style={[
            styles.summaryStatus,
            state.competitionStartedAt && styles.summaryStatusActive,
          ]}
        >
          <Text
            style={[
              styles.summaryStatusText,
              state.competitionStartedAt && styles.summaryStatusTextActive,
            ]}
          >
            {state.competitionStartedAt ? 'IN CORSO' : 'PRE-CAMPIONATO'}
          </Text>
        </View>
      </View>
      <View style={styles.summaryStats}>
        <View style={styles.summaryStat}>
          <Text style={styles.summaryNumber}>{state.matchdayCount}</Text>
          <Text style={styles.summaryStatLabel}>GIORNATE</Text>
        </View>
        <View style={styles.summaryDivider} />
        <View style={styles.summaryStat}>
          <Text style={styles.summaryNumber}>{state.fixtureCount}</Text>
          <Text style={styles.summaryStatLabel}>PARTITE</Text>
        </View>
        <View style={styles.summaryDivider} />
        <View style={styles.summaryStat}>
          <Text style={styles.summaryNumber}>{state.teamCount}</Text>
          <Text style={styles.summaryStatLabel}>SQUADRE</Text>
        </View>
      </View>
      <View
        style={[
          styles.scheduleHealth,
          total > 0 &&
            aligned === total &&
            styles.scheduleHealthComplete,
        ]}
      >
        <View
          style={[
            styles.scheduleHealthDot,
            total > 0 &&
              aligned === total &&
              styles.scheduleHealthDotComplete,
          ]}
        />
        <View style={styles.scheduleHealthCopy}>
          <Text
            style={[
              styles.scheduleHealthTitle,
              total > 0 &&
                aligned === total &&
                styles.scheduleHealthTextComplete,
            ]}
          >
            {total > 0 && aligned === total
              ? 'Calendario allineato alla Serie A'
              : 'Allineamento date in corso'}
          </Text>
          <Text
            style={[
              styles.scheduleHealthBody,
              total > 0 &&
                aligned === total &&
                styles.scheduleHealthTextComplete,
            ]}
          >
            {aligned}/{total} giornate con calcio d’inizio e scadenza reali
          </Text>
        </View>
      </View>
      <View
        style={[
          styles.scheduleHealth,
          state.checks.calendarIntegrityReady &&
            state.checks.calendarSnapshotStable &&
            styles.scheduleHealthComplete,
        ]}
      >
        <View
          style={[
            styles.scheduleHealthDot,
            state.checks.calendarIntegrityReady &&
              state.checks.calendarSnapshotStable &&
              styles.scheduleHealthDotComplete,
          ]}
        />
        <View style={styles.scheduleHealthCopy}>
          <Text
            style={[
              styles.scheduleHealthTitle,
              state.checks.calendarIntegrityReady &&
                state.checks.calendarSnapshotStable &&
                styles.scheduleHealthTextComplete,
            ]}
          >
            {state.checks.calendarIntegrityReady &&
            state.checks.calendarSnapshotStable
              ? 'Sorteggio verificato e rose congelate'
              : 'Verifica pre-campionato richiesta'}
          </Text>
          <Text
            style={[
              styles.scheduleHealthBody,
              state.checks.calendarIntegrityReady &&
                state.checks.calendarSnapshotStable &&
                styles.scheduleHealthTextComplete,
            ]}
          >
            {state.preflight.expectedFixtureCount || state.fixtureCount} partite ·{' '}
            {state.preflight.expectedMatchdayCount || state.matchdayCount} giornate
          </Text>
        </View>
      </View>
    </View>
  );
}

function SchedulePreviewCard({
  error,
  loading,
  preview,
}: {
  error: string;
  loading: boolean;
  preview: CalendarSchedulePreview | null;
}) {
  if (loading) {
    return (
      <View style={styles.providerCard}>
        <ActivityIndicator color={colors.navy} size="small" />
        <View style={styles.providerCardCopy}>
          <Text style={styles.providerCardTitle}>Controllo date Serie A</Text>
          <Text style={styles.providerCardBody}>
            Verifico giornate e primi calci d’inizio disponibili.
          </Text>
        </View>
      </View>
    );
  }

  if (error) {
    return (
      <View style={styles.providerCard}>
        <View style={styles.providerFallbackBadge}>
          <Text style={styles.providerFallbackBadgeText}>!</Text>
        </View>
        <View style={styles.providerCardCopy}>
          <Text style={styles.providerCardTitle}>Date non disponibili</Text>
          <Text style={styles.providerCardBody}>{error}</Text>
        </View>
      </View>
    );
  }

  if (!preview) {
    return null;
  }

  const complete =
    preview.requestedMatchdays > 0 &&
    preview.providerAlignedMatchdays === preview.requestedMatchdays;

  return (
    <View
      style={[
        styles.providerCard,
        complete && styles.providerCardComplete,
      ]}
    >
      <View
        style={[
          styles.providerBadge,
          !complete && styles.providerFallbackBadge,
        ]}
      >
        <Text
          style={[
            styles.providerBadgeText,
            !complete && styles.providerFallbackBadgeText,
          ]}
        >
          {complete ? '✓' : '↻'}
        </Text>
      </View>
      <View style={styles.providerCardCopy}>
        <Text style={styles.providerCardTitle}>
          {complete ? 'Date Serie A complete' : 'Riallineamento automatico'}
        </Text>
        <Text style={styles.providerCardBody}>
          {preview.providerAlignedMatchdays}/{preview.requestedMatchdays}{' '}
          giornate già allineate
          {preview.missingMatchdays > 0
            ? ` · ${preview.missingMatchdays} ancora stimate`
            : ''}
        </Text>
      </View>
    </View>
  );
}

function MatchdayScheduleCard({ fixture }: { fixture: CalendarFixture }) {
  const provider = fixture.scheduleSource === 'provider';
  const now = Date.now();
  const locked = new Date(fixture.locksAt).getTime() <= now;

  return (
    <View
      style={[
        styles.matchdayScheduleCard,
        provider && styles.matchdayScheduleCardProvider,
      ]}
    >
      <View style={styles.matchdayScheduleItem}>
        <Text style={styles.matchdayScheduleLabel}>SCADENZA FORMAZIONE</Text>
        <Text style={styles.matchdayScheduleValue}>
          {formatDateTime(fixture.locksAt)}
        </Text>
        <Text style={styles.matchdayScheduleMeta}>
          {locked ? 'FORMAZIONI BLOCCATE' : 'PRIMO CALCIO D’INIZIO'}
        </Text>
      </View>
      <View style={styles.matchdayScheduleDivider} />
      <View style={styles.matchdayScheduleItem}>
        <Text style={styles.matchdayScheduleLabel}>PARTITE REALI</Text>
        <Text style={styles.matchdayScheduleValue}>
          {provider ? fixture.providerFixtureCount : '—'}
        </Text>
        <Text style={styles.matchdayScheduleMeta}>
          {provider
            ? `${fixture.providerFinalFixtureCount} CONCLUSE`
            : 'IN ATTESA DEL PROVIDER'}
        </Text>
      </View>
    </View>
  );
}

function FixtureRow({
  currentUserId,
  fixture,
}: {
  currentUserId: string | null;
  fixture: CalendarFixture;
}) {
  const current =
    fixture.homeTeam.managerId === currentUserId ||
    fixture.awayTeam.managerId === currentUserId;
  const hasResult =
    fixture.homeGoals !== null && fixture.awayGoals !== null;

  return (
    <View style={[styles.fixtureRow, current && styles.fixtureRowCurrent]}>
      <View style={styles.fixtureTeam}>
        <Text style={styles.homeAwayLabel}>CASA</Text>
        <Text
          numberOfLines={1}
          style={[
            styles.fixtureTeamName,
            fixture.homeTeam.managerId === currentUserId &&
              styles.fixtureTeamCurrent,
          ]}
        >
          {fixture.homeTeam.name}
        </Text>
        {fixture.homePoints !== null ? (
          <Text style={styles.fixturePoints}>{fixture.homePoints} FP</Text>
        ) : null}
      </View>
      <View style={styles.scoreBox}>
        <Text style={styles.scoreText}>
          {hasResult
            ? `${fixture.homeGoals} - ${fixture.awayGoals}`
            : 'VS'}
        </Text>
        <Text style={styles.scoreStatus}>
          {fixture.finalized ? 'FINALE' : 'DA GIOCARE'}
        </Text>
      </View>
      <View style={[styles.fixtureTeam, styles.fixtureTeamAway]}>
        <Text style={[styles.homeAwayLabel, styles.homeAwayLabelAway]}>
          TRASFERTA
        </Text>
        <Text
          numberOfLines={1}
          style={[
            styles.fixtureTeamName,
            styles.fixtureTeamNameAway,
            fixture.awayTeam.managerId === currentUserId &&
              styles.fixtureTeamCurrent,
          ]}
        >
          {fixture.awayTeam.name}
        </Text>
        {fixture.awayPoints !== null ? (
          <Text style={styles.fixturePoints}>{fixture.awayPoints} FP</Text>
        ) : null}
      </View>
    </View>
  );
}

function Feedback({
  message,
  success,
}: {
  message: string;
  success: boolean;
}) {
  return (
    <View
      style={[
        styles.feedbackCard,
        success && styles.feedbackCardSuccess,
      ]}
    >
      <Text
        style={[
          styles.feedbackText,
          success && styles.feedbackTextSuccess,
        ]}
      >
        {message}
      </Text>
    </View>
  );
}

type CalendarProjection = {
  rounds: number;
  fixtures: number;
  lastMatchday: number;
};

function calculateProjection(
  teamCount: number,
  firstMatchday: number,
  returnLeg: boolean,
): CalendarProjection {
  const safeTeams = Math.max(teamCount, 2);
  const slots = safeTeams % 2 === 0 ? safeTeams : safeTeams + 1;
  const singleRounds = slots - 1;
  const legs = returnLeg ? 2 : 1;
  const rounds = singleRounds * legs;
  const fixtures = Math.floor(safeTeams / 2) * rounds;

  return {
    rounds,
    fixtures,
    lastMatchday: firstMatchday + rounds - 1,
  };
}

function findInitialMatchday(
  matchdays: number[],
  fixtures: CalendarFixture[],
) {
  const now = Date.now();
  const upcoming = fixtures
    .filter((fixture) => new Date(fixture.startsAt).getTime() >= now)
    .sort(
      (left, right) =>
        new Date(left.startsAt).getTime() -
        new Date(right.startsAt).getTime(),
    )[0];

  return upcoming?.matchdayNumber ?? matchdays[matchdays.length - 1];
}

function formatDate(value?: string) {
  if (!value) {
    return '';
  }
  return new Intl.DateTimeFormat('it-IT', {
    day: '2-digit',
    month: 'short',
    year: 'numeric',
  })
    .format(new Date(value))
    .toUpperCase();
}

function formatDateTime(value: string) {
  return new Intl.DateTimeFormat('it-IT', {
    day: '2-digit',
    month: 'short',
    hour: '2-digit',
    minute: '2-digit',
  })
    .format(new Date(value))
    .toUpperCase();
}

const styles = StyleSheet.create({
  screen: {
    flex: 1,
    backgroundColor: colors.canvas,
  },
  content: {
    padding: 20,
    paddingBottom: 48,
  },
  missingRoot: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    padding: 25,
    backgroundColor: colors.canvas,
  },
  missingTitle: {
    color: colors.navy,
    fontSize: 20,
    fontWeight: '900',
    marginBottom: 20,
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
    fontWeight: '900',
    letterSpacing: 0.6,
  },
  title: {
    color: colors.navy,
    fontSize: 25,
    fontWeight: '900',
    marginTop: 4,
  },
  loadingCard: {
    minHeight: 270,
    borderRadius: radius.xl,
    alignItems: 'center',
    justifyContent: 'center',
    padding: 26,
    backgroundColor: colors.navy,
  },
  loadingTitle: {
    color: colors.warmWhite,
    fontSize: 18,
    fontWeight: '900',
    marginTop: 16,
  },
  loadingText: {
    color: colors.mutedLight,
    fontSize: 12,
    textAlign: 'center',
    lineHeight: 18,
    marginTop: 7,
  },
  errorCard: {
    borderRadius: radius.xl,
    padding: 24,
    backgroundColor: colors.navy,
  },
  errorTitle: {
    color: colors.warmWhite,
    fontSize: 19,
    fontWeight: '900',
  },
  errorBody: {
    color: colors.mutedLight,
    fontSize: 13,
    lineHeight: 19,
    marginTop: 8,
  },
  retryButton: {
    alignSelf: 'flex-start',
    borderRadius: radius.sm,
    paddingHorizontal: 18,
    paddingVertical: 12,
    backgroundColor: colors.lime,
    marginTop: 18,
  },
  retryButtonText: {
    color: colors.navy,
    fontSize: 10,
    fontWeight: '900',
  },
  setupHero: {
    borderRadius: radius.xl,
    padding: 24,
    backgroundColor: colors.navy,
  },
  setupBadge: {
    width: 56,
    height: 56,
    borderRadius: 19,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.lime,
  },
  setupBadgeText: {
    color: colors.navy,
    fontSize: 15,
    fontWeight: '900',
  },
  setupEyebrow: {
    color: colors.lime,
    fontSize: 9,
    fontWeight: '900',
    letterSpacing: 0.5,
    marginTop: 22,
  },
  setupTitle: {
    color: colors.warmWhite,
    fontSize: 25,
    fontWeight: '900',
    marginTop: 7,
  },
  setupBody: {
    color: colors.mutedLight,
    fontSize: 13,
    lineHeight: 20,
    marginTop: 9,
  },
  readinessCard: {
    borderRadius: radius.xl,
    padding: 22,
    backgroundColor: colors.white,
    marginTop: 14,
  },
  readinessHeader: {
    flexDirection: 'row',
    alignItems: 'flex-start',
    justifyContent: 'space-between',
    marginBottom: 13,
  },
  cardEyebrow: {
    color: colors.muted,
    fontSize: 9,
    fontWeight: '900',
    letterSpacing: 0.45,
  },
  cardTitle: {
    color: colors.navy,
    fontSize: 20,
    fontWeight: '900',
    marginTop: 5,
  },
  readinessBadge: {
    borderRadius: 999,
    paddingHorizontal: 11,
    paddingVertical: 7,
    backgroundColor: colors.canvasMuted,
  },
  readinessBadgeReady: {
    backgroundColor: colors.lime,
  },
  readinessBadgeText: {
    color: colors.muted,
    fontSize: 8,
    fontWeight: '900',
  },
  readinessBadgeTextReady: {
    color: colors.navy,
  },
  checkRow: {
    minHeight: 48,
    flexDirection: 'row',
    alignItems: 'center',
    borderTopWidth: 1,
    borderTopColor: colors.canvasMuted,
  },
  checkIcon: {
    width: 24,
    height: 24,
    borderRadius: 12,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.canvasMuted,
  },
  checkIconComplete: {
    backgroundColor: colors.lime,
  },
  checkIconText: {
    color: colors.muted,
    fontSize: 13,
    fontWeight: '900',
  },
  checkIconTextComplete: {
    color: colors.navy,
  },
  checkLabel: {
    flex: 1,
    color: colors.navy,
    fontSize: 12,
    fontWeight: '800',
    marginLeft: 11,
  },
  checkDetail: {
    color: colors.muted,
    fontSize: 9,
    fontWeight: '900',
  },
  checkDetailComplete: {
    color: colors.navy,
  },
  teamsCard: {
    borderRadius: radius.xl,
    padding: 22,
    backgroundColor: colors.white,
    marginTop: 14,
  },
  teamsList: {
    marginTop: 14,
  },
  teamReadyRow: {
    minHeight: 62,
    flexDirection: 'row',
    alignItems: 'center',
    borderTopWidth: 1,
    borderTopColor: colors.canvasMuted,
  },
  teamReadyIcon: {
    width: 38,
    height: 38,
    borderRadius: 14,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.canvasMuted,
  },
  teamReadyIconComplete: {
    backgroundColor: colors.navy,
  },
  teamReadyIconText: {
    color: colors.navy,
    fontSize: 11,
    fontWeight: '900',
  },
  teamReadyIconTextComplete: {
    color: colors.lime,
  },
  teamReadyCopy: {
    flex: 1,
    marginLeft: 11,
  },
  teamReadyName: {
    color: colors.navy,
    fontSize: 13,
    fontWeight: '900',
  },
  teamReadyRoster: {
    color: colors.muted,
    fontSize: 8,
    fontWeight: '900',
    marginTop: 3,
  },
  teamReadyStatus: {
    color: colors.muted,
    fontSize: 7,
    fontWeight: '900',
  },
  teamReadyStatusComplete: {
    color: colors.navy,
  },
  openTeamRow: {
    minHeight: 58,
    flexDirection: 'row',
    alignItems: 'center',
    borderTopWidth: 1,
    borderTopColor: colors.canvasMuted,
  },
  openTeamIcon: {
    width: 36,
    height: 36,
    borderRadius: 13,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.canvas,
  },
  openTeamIconText: {
    color: colors.muted,
    fontSize: 18,
    fontWeight: '700',
  },
  openTeamText: {
    color: colors.muted,
    fontSize: 12,
    fontWeight: '700',
    marginLeft: 11,
  },
  configurationCard: {
    borderRadius: radius.xl,
    padding: 22,
    backgroundColor: colors.white,
    marginTop: 14,
  },
  doubleField: {
    flexDirection: 'row',
    gap: 12,
  },
  halfField: {
    flex: 1,
  },
  fieldLabel: {
    color: colors.navy,
    fontSize: 9,
    fontWeight: '900',
    letterSpacing: 0.4,
    marginTop: 20,
    marginBottom: 8,
  },
  input: {
    height: 50,
    borderWidth: 1,
    borderColor: colors.canvasMuted,
    borderRadius: radius.sm,
    paddingHorizontal: 14,
    color: colors.navy,
    fontSize: 14,
    fontWeight: '800',
    backgroundColor: colors.canvas,
  },
  choiceRow: {
    flexDirection: 'row',
    gap: 10,
  },
  choice: {
    flex: 1,
    height: 46,
    borderWidth: 1,
    borderColor: colors.canvasMuted,
    borderRadius: 14,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.canvas,
  },
  choiceActive: {
    borderColor: colors.navy,
    backgroundColor: colors.navy,
  },
  choiceText: {
    color: colors.muted,
    fontSize: 9,
    fontWeight: '900',
  },
  choiceTextActive: {
    color: colors.lime,
  },
  projectionCard: {
    minHeight: 84,
    flexDirection: 'row',
    alignItems: 'center',
    borderRadius: radius.md,
    paddingHorizontal: 12,
    backgroundColor: colors.navy,
    marginTop: 18,
  },
  projectionStat: {
    flex: 1,
    alignItems: 'center',
  },
  projectionNumber: {
    color: colors.lime,
    fontSize: 19,
    fontWeight: '900',
  },
  projectionLabel: {
    color: colors.mutedLight,
    fontSize: 7,
    fontWeight: '900',
    marginTop: 3,
  },
  projectionDivider: {
    width: 1,
    height: 34,
    backgroundColor: colors.navyLine,
  },
  providerCard: {
    minHeight: 70,
    flexDirection: 'row',
    alignItems: 'center',
    borderRadius: radius.md,
    padding: 14,
    backgroundColor: colors.canvas,
    marginTop: 14,
  },
  providerCardComplete: {
    backgroundColor: colors.limeSoft,
  },
  providerBadge: {
    width: 38,
    height: 38,
    borderRadius: 13,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.lime,
  },
  providerBadgeText: {
    color: colors.navy,
    fontSize: 14,
    fontWeight: '900',
  },
  providerFallbackBadge: {
    width: 38,
    height: 38,
    borderRadius: 13,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.canvasMuted,
  },
  providerFallbackBadgeText: {
    color: colors.muted,
    fontSize: 14,
    fontWeight: '900',
  },
  providerCardCopy: {
    flex: 1,
    marginLeft: 12,
  },
  providerCardTitle: {
    color: colors.navy,
    fontSize: 12,
    fontWeight: '900',
  },
  providerCardBody: {
    color: colors.muted,
    fontSize: 9,
    lineHeight: 14,
    marginTop: 4,
  },
  primaryButton: {
    minHeight: 56,
    borderRadius: radius.md,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.lime,
    marginTop: 20,
    paddingHorizontal: 18,
  },
  buttonDisabled: {
    opacity: 0.42,
  },
  primaryButtonText: {
    color: colors.navy,
    fontSize: 10,
    fontWeight: '900',
    textAlign: 'center',
  },
  managerNotice: {
    flexDirection: 'row',
    alignItems: 'center',
    borderRadius: radius.xl,
    padding: 20,
    backgroundColor: colors.white,
    marginTop: 14,
  },
  managerBadge: {
    width: 46,
    height: 46,
    borderRadius: 16,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.navy,
  },
  managerBadgeText: {
    color: colors.lime,
    fontSize: 14,
    fontWeight: '900',
  },
  managerCopy: {
    flex: 1,
    marginLeft: 14,
  },
  managerNoticeTitle: {
    color: colors.navy,
    fontSize: 14,
    fontWeight: '900',
  },
  managerNoticeBody: {
    color: colors.muted,
    fontSize: 11,
    lineHeight: 16,
    marginTop: 5,
  },
  feedbackCard: {
    borderRadius: radius.sm,
    padding: 13,
    backgroundColor: '#FFF0EF',
    marginTop: 14,
  },
  feedbackCardSuccess: {
    backgroundColor: colors.limeSoft,
  },
  feedbackText: {
    color: colors.danger,
    fontSize: 11,
    fontWeight: '800',
    lineHeight: 17,
  },
  feedbackTextSuccess: {
    color: colors.navy,
  },
  summaryCard: {
    minHeight: 178,
    borderRadius: radius.xl,
    padding: 22,
    backgroundColor: colors.navy,
    justifyContent: 'space-between',
  },
  summaryTop: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'flex-start',
  },
  summaryLabel: {
    color: colors.mutedLight,
    fontSize: 9,
    fontWeight: '900',
  },
  summaryTitle: {
    color: colors.warmWhite,
    fontSize: 23,
    fontWeight: '900',
    marginTop: 5,
  },
  summaryStatus: {
    borderRadius: 999,
    paddingHorizontal: 10,
    paddingVertical: 7,
    backgroundColor: colors.navySoft,
  },
  summaryStatusActive: {
    backgroundColor: colors.lime,
  },
  summaryStatusText: {
    color: colors.mutedLight,
    fontSize: 7,
    fontWeight: '900',
  },
  summaryStatusTextActive: {
    color: colors.navy,
  },
  summaryStats: {
    flexDirection: 'row',
    alignItems: 'center',
    marginTop: 24,
  },
  summaryStat: {
    flex: 1,
  },
  summaryNumber: {
    color: colors.lime,
    fontSize: 23,
    fontWeight: '900',
  },
  summaryStatLabel: {
    color: colors.mutedLight,
    fontSize: 8,
    fontWeight: '900',
    marginTop: 3,
  },
  summaryDivider: {
    width: 1,
    height: 35,
    backgroundColor: colors.navyLine,
    marginHorizontal: 14,
  },
  scheduleHealth: {
    flexDirection: 'row',
    alignItems: 'center',
    borderRadius: 14,
    paddingHorizontal: 12,
    paddingVertical: 10,
    backgroundColor: colors.navySoft,
    marginTop: 18,
  },
  scheduleHealthComplete: {
    backgroundColor: colors.lime,
  },
  scheduleHealthDot: {
    width: 8,
    height: 8,
    borderRadius: 4,
    backgroundColor: colors.mutedLight,
  },
  scheduleHealthDotComplete: {
    backgroundColor: colors.navy,
  },
  scheduleHealthCopy: {
    flex: 1,
    marginLeft: 9,
  },
  scheduleHealthTitle: {
    color: colors.warmWhite,
    fontSize: 9,
    fontWeight: '900',
  },
  scheduleHealthBody: {
    color: colors.mutedLight,
    fontSize: 8,
    marginTop: 2,
  },
  scheduleHealthTextComplete: {
    color: colors.navy,
  },
  sectionHeader: {
    flexDirection: 'row',
    alignItems: 'flex-end',
    justifyContent: 'space-between',
    marginTop: 25,
    marginBottom: 12,
  },
  sectionEyebrow: {
    color: colors.muted,
    fontSize: 8,
    fontWeight: '900',
  },
  sectionTitle: {
    color: colors.navy,
    fontSize: 21,
    fontWeight: '900',
    marginTop: 3,
  },
  rangeLabel: {
    color: colors.muted,
    fontSize: 10,
    fontWeight: '900',
    marginBottom: 3,
  },
  roundsRow: {
    gap: 9,
    paddingRight: 20,
  },
  roundButton: {
    width: 66,
    height: 66,
    borderRadius: 18,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.white,
  },
  roundButtonActive: {
    backgroundColor: colors.navy,
  },
  roundNumber: {
    color: colors.navy,
    fontSize: 18,
    fontWeight: '900',
  },
  roundNumberActive: {
    color: colors.lime,
  },
  roundLabel: {
    color: colors.muted,
    fontSize: 7,
    fontWeight: '900',
    marginTop: 3,
  },
  roundLabelActive: {
    color: colors.mutedLight,
  },
  fixtureHeader: {
    flexDirection: 'row',
    alignItems: 'flex-end',
    justifyContent: 'space-between',
    marginTop: 25,
    marginBottom: 11,
  },
  fixtureEyebrow: {
    color: colors.muted,
    fontSize: 8,
    fontWeight: '900',
  },
  fixtureTitle: {
    color: colors.navy,
    fontSize: 20,
    fontWeight: '900',
    marginTop: 3,
  },
  fixtureDate: {
    color: colors.muted,
    fontSize: 9,
    fontWeight: '900',
    marginBottom: 3,
  },
  fixtureDateColumn: {
    alignItems: 'flex-end',
  },
  scheduleSource: {
    borderRadius: 999,
    paddingHorizontal: 8,
    paddingVertical: 4,
    color: colors.muted,
    fontSize: 6,
    fontWeight: '900',
    backgroundColor: colors.canvasMuted,
  },
  scheduleSourceProvider: {
    color: colors.navy,
    backgroundColor: colors.lime,
  },
  matchdayScheduleCard: {
    flexDirection: 'row',
    alignItems: 'stretch',
    borderRadius: radius.lg,
    padding: 15,
    backgroundColor: colors.white,
    marginBottom: 10,
  },
  matchdayScheduleCardProvider: {
    borderWidth: 1,
    borderColor: colors.lime,
  },
  matchdayScheduleItem: {
    flex: 1,
  },
  matchdayScheduleDivider: {
    width: 1,
    backgroundColor: colors.canvasMuted,
    marginHorizontal: 14,
  },
  matchdayScheduleLabel: {
    color: colors.muted,
    fontSize: 7,
    fontWeight: '900',
  },
  matchdayScheduleValue: {
    color: colors.navy,
    fontSize: 13,
    fontWeight: '900',
    marginTop: 5,
  },
  matchdayScheduleMeta: {
    color: colors.muted,
    fontSize: 6,
    fontWeight: '800',
    marginTop: 4,
  },
  fixturesCard: {
    borderRadius: radius.lg,
    padding: 8,
    backgroundColor: colors.white,
  },
  fixtureRow: {
    minHeight: 94,
    borderRadius: 17,
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 10,
    paddingVertical: 12,
  },
  fixtureRowCurrent: {
    backgroundColor: colors.canvas,
  },
  fixtureTeam: {
    flex: 1,
    minWidth: 0,
  },
  fixtureTeamAway: {
    alignItems: 'flex-end',
  },
  homeAwayLabel: {
    color: colors.muted,
    fontSize: 7,
    fontWeight: '900',
  },
  homeAwayLabelAway: {
    textAlign: 'right',
  },
  fixtureTeamName: {
    color: colors.navy,
    fontSize: 12,
    fontWeight: '900',
    marginTop: 4,
  },
  fixtureTeamNameAway: {
    textAlign: 'right',
  },
  fixtureTeamCurrent: {
    color: '#507900',
  },
  fixturePoints: {
    color: colors.muted,
    fontSize: 8,
    fontWeight: '800',
    marginTop: 4,
  },
  scoreBox: {
    width: 74,
    alignItems: 'center',
    justifyContent: 'center',
    marginHorizontal: 6,
  },
  scoreText: {
    color: colors.navy,
    fontSize: 17,
    fontWeight: '900',
  },
  scoreStatus: {
    color: colors.muted,
    fontSize: 7,
    fontWeight: '900',
    marginTop: 4,
  },
  resetCard: {
    flexDirection: 'row',
    alignItems: 'center',
    borderRadius: radius.lg,
    padding: 18,
    backgroundColor: colors.white,
    marginTop: 16,
  },
  resetCopy: {
    flex: 1,
  },
  resetTitle: {
    color: colors.navy,
    fontSize: 14,
    fontWeight: '900',
  },
  resetBody: {
    color: colors.muted,
    fontSize: 10,
    lineHeight: 15,
    marginTop: 4,
    paddingRight: 12,
  },
  resetButton: {
    borderRadius: radius.sm,
    paddingHorizontal: 14,
    paddingVertical: 12,
    backgroundColor: '#FFF0EF',
  },
  resetButtonText: {
    color: colors.danger,
    fontSize: 8,
    fontWeight: '900',
  },
});
