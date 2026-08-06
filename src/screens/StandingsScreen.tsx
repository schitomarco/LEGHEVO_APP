import { useEffect, useState } from 'react';
import {
  ActivityIndicator,
  Alert,
  Modal,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  TextInput,
  View,
} from 'react-native';
import { useLeagueResults } from '../hooks/useLeagueResults';
import { useLeagueStandings } from '../hooks/useLeagueStandings';
import { colors, radius } from '../theme';
import type {
  AppScreen,
  LeagueFixtureResult,
  LeagueMatchdayResult,
  LeagueStanding,
  LeagueSummary,
  MatchdayResultStatus,
  PublicTeamSelection,
  StandingsTiebreaker,
} from '../types';

type Props = {
  league: LeagueSummary | null;
  onNavigate: (screen: AppScreen) => void;
  onOpenTeam: (team: PublicTeamSelection, isCurrent: boolean) => void;
};

export function StandingsScreen({ league, onNavigate, onOpenTeam }: Props) {
  const state = useLeagueStandings(
    league?.id ?? null,
    Boolean(league?.isDemo),
  );
  const results = useLeagueResults(
    league?.id ?? null,
    Boolean(league?.isDemo),
  );
  const [selectedMatchdayId, setSelectedMatchdayId] = useState<string | null>(
    null,
  );
  const [correctionFixture, setCorrectionFixture] =
    useState<LeagueFixtureResult | null>(null);
  const [correctionReason, setCorrectionReason] = useState('');
  const [correctionError, setCorrectionError] = useState('');
  const matchdays = results.center?.matchdays ?? [];
  const isRefreshing = state.loading || results.loading;

  useEffect(() => {
    if (matchdays.length === 0) {
      setSelectedMatchdayId(null);
      return;
    }
    if (
      selectedMatchdayId &&
      matchdays.some((matchday) => matchday.id === selectedMatchdayId)
    ) {
      return;
    }

    const preferred =
      matchdays.find((matchday) => matchday.status === 'live') ??
      matchdays.find((matchday) => matchday.status === 'ready') ??
      matchdays.find((matchday) => matchday.status === 'pending') ??
      matchdays.find((matchday) => matchday.status === 'upcoming') ??
      matchdays[matchdays.length - 1];
    setSelectedMatchdayId(preferred.id);
  }, [matchdays, selectedMatchdayId]);

  if (!league) {
    return (
      <View style={styles.centerRoot}>
        <Text style={styles.centerTitle}>Prima scegli una lega.</Text>
        <Pressable
          onPress={() => onNavigate('home')}
          style={styles.refreshButton}
        >
          <Text style={styles.refreshButtonText}>TORNA ALLA HOME</Text>
        </Pressable>
      </View>
    );
  }

  const myStanding = state.standings.find(
    (standing) => standing.teamId === league.team?.id,
  );
  const completedMatches = Math.floor(
    state.standings.reduce(
      (total, standing) => total + standing.played,
      0,
    ) / 2,
  );
  const selectedIndex = Math.max(
    0,
    matchdays.findIndex((matchday) => matchday.id === selectedMatchdayId),
  );
  const selectedMatchday = matchdays[selectedIndex] ?? null;
  const changeMatchday = (offset: number) => {
    const next = matchdays[selectedIndex + offset];
    if (next) {
      setSelectedMatchdayId(next.id);
    }
  };
  const confirmFinalize = () => {
    if (!selectedMatchday) {
      return;
    }
    Alert.alert(
      `Ufficializzare la giornata ${selectedMatchday.number}?`,
      'I risultati entreranno in classifica e saranno notificati a tutti i partecipanti.',
      [
        { text: 'Annulla', style: 'cancel' },
        {
          text: 'Ufficializza',
          onPress: () => void results.finalize(selectedMatchday.id),
        },
      ],
    );
  };
  const openCorrection = (fixture: LeagueFixtureResult) => {
    setCorrectionFixture(fixture);
    setCorrectionReason('');
    setCorrectionError('');
  };
  const closeCorrection = () => {
    setCorrectionFixture(null);
    setCorrectionReason('');
    setCorrectionError('');
  };
  const submitCorrection = async () => {
    if (!correctionFixture) {
      return;
    }

    if (
      correctionFixture.providerRemediationRequired &&
      !correctionFixture.providerImpactGeneration
    ) {
      setCorrectionError(
        'La generazione provider non è più disponibile: aggiorna i risultati e riprova.',
      );
      return;
    }

    const reason = correctionReason.trim();
    if (reason.length < 10 || reason.length > 240) {
      setCorrectionError(
        'Inserisci una motivazione da 10 a 240 caratteri.',
      );
      return;
    }

    const outcome = await results.reopenFixture(
      correctionFixture.id,
      reason,
      correctionFixture.providerRemediationRequired
        ? correctionFixture.providerImpactGeneration
        : null,
    );
    if (outcome.error) {
      setCorrectionError(outcome.error);
      return;
    }

    closeCorrection();
  };

  return (
    <ScrollView
      style={styles.screen}
      contentContainerStyle={styles.content}
      showsVerticalScrollIndicator={false}
    >
      <View style={styles.header}>
        <Pressable
          onPress={() => onNavigate('league')}
          style={styles.backButton}
        >
          <Text style={styles.backText}>‹</Text>
        </Pressable>
        <View style={styles.headerCopy}>
          <Text style={styles.eyebrow}>CAMPIONATO</Text>
          <Text numberOfLines={1} style={styles.title}>
            Risultati e classifica
          </Text>
        </View>
        <Pressable
          accessibilityLabel="Aggiorna risultati e classifica"
          accessibilityState={{
            busy: isRefreshing,
            disabled: isRefreshing,
          }}
          disabled={isRefreshing}
          onPress={() =>
            void Promise.all([state.refresh(), results.refresh()])
          }
          style={[
            styles.reloadButton,
            isRefreshing && styles.reloadButtonDisabled,
          ]}
        >
          {isRefreshing ? (
            <ActivityIndicator color={colors.lime} size="small" />
          ) : (
            <Text style={styles.reloadText}>↻</Text>
          )}
        </Pressable>
      </View>

      {(state.season?.status === 'completed' ||
        state.season?.status === 'archived') &&
      state.season.champion &&
      state.season.completedAt ? (
        <View style={styles.championCard}>
          <Text style={styles.championEyebrow}>
            CAMPIONE · STAGIONE {state.season.season ?? '—'}
          </Text>
          <Text style={styles.championTeam}>
            {state.season.champion.teamName}
          </Text>
          <Text style={styles.championManager}>
            {state.season.champion.managerName}
          </Text>
          <View style={styles.championStats}>
            <ChampionStat
              label="PUNTI"
              value={String(state.season.champion.leaguePoints)}
            />
            <ChampionStat
              label="FANTAPUNTI"
              value={formatPoints(state.season.champion.pointsFor)}
            />
            <ChampionStat
              label="CHIUSA"
              value={formatShortDate(state.season.completedAt)}
            />
          </View>
          <Text style={styles.championNote}>
            {state.season.officialSnapshotAffected
              ? 'Snapshot storico conservato senza modifiche. La Direzione deve verificare una regressione provider successiva.'
              : 'Classifica finale certificata nello snapshot ufficiale immutabile della stagione.'}
          </Text>
        </View>
      ) : null}

      <View style={styles.heroCard}>
        <View>
          <Text style={styles.heroEyebrow}>LA TUA POSIZIONE</Text>
          <Text style={styles.heroPosition}>
            {myStanding ? `${myStanding.position}ª` : '—'}
          </Text>
          <Text style={styles.heroTeam}>
            {league.team?.name ?? 'Squadra da completare'}
          </Text>
        </View>
        <View style={styles.heroStats}>
          <HeroStat
            label="PUNTI"
            value={String(myStanding?.leaguePoints ?? 0)}
          />
          <HeroStat
            label="PARTITE"
            value={String(myStanding?.played ?? 0)}
          />
          <HeroStat label="GIOCATE" value={String(completedMatches)} />
        </View>
      </View>

      <View style={styles.sectionHeader}>
        <Text style={styles.sectionTitle}>Risultati di giornata</Text>
        <Text style={styles.liveLabel}>
          {results.center?.isOwner ? 'GESTIONE PRESIDENTE' : 'DATI LIVE'}
        </Text>
      </View>

      {results.loading ? (
        <View style={styles.loadingCard}>
          <ActivityIndicator color={colors.navy} />
          <Text style={styles.loadingText}>Controllo tutti i tabellini…</Text>
        </View>
      ) : results.error ? (
        <View style={styles.errorCard}>
          <Text style={styles.errorTitle}>Risultati indisponibili</Text>
          <Text style={styles.errorBody}>{results.error}</Text>
        </View>
      ) : selectedMatchday ? (
        <MatchdayCard
          actionError={results.actionError}
          actionLoading={results.actionLoading}
          canGoNext={selectedIndex < matchdays.length - 1}
          canGoPrevious={selectedIndex > 0}
          matchday={selectedMatchday}
          myTeamId={league.team?.id ?? null}
          onFinalize={confirmFinalize}
          onNext={() => changeMatchday(1)}
          onPrevious={() => changeMatchday(-1)}
          onCorrect={openCorrection}
        />
      ) : (
        <View style={styles.emptyCard}>
          <Text style={styles.emptyTitle}>Calendario ancora da generare</Text>
          <Text style={styles.emptyBody}>
            Appena il Presidente pubblica gli accoppiamenti, qui compariranno
            punteggi provvisori e risultati ufficiali.
          </Text>
          <Pressable
            onPress={() => onNavigate('calendar')}
            style={styles.inlineButton}
          >
            <Text style={styles.inlineButtonText}>APRI IL CALENDARIO</Text>
          </Pressable>
        </View>
      )}

      <View style={styles.sectionHeader}>
        <Text style={styles.sectionTitle}>Campionato</Text>
        <Text style={styles.liveLabel}>
          {state.season?.status === 'completed' ||
          state.season?.status === 'archived'
            ? 'CLASSIFICA FINALE'
            : 'SOLO RISULTATI UFFICIALI'}
        </Text>
      </View>

      {state.loading ? (
        <View style={styles.loadingCard}>
          <ActivityIndicator color={colors.navy} />
          <Text style={styles.loadingText}>Conto gol, punti e alibi…</Text>
        </View>
      ) : state.error ? (
        <View style={styles.errorCard}>
          <Text style={styles.errorTitle}>Classifica indisponibile</Text>
          <Text style={styles.errorBody}>{state.error}</Text>
        </View>
      ) : state.standings.length === 0 ? (
        <View style={styles.emptyCard}>
          <Text style={styles.emptyTitle}>Spogliatoio ancora vuoto</Text>
          <Text style={styles.emptyBody}>
            Le squadre compariranno appena entrano nella lega.
          </Text>
        </View>
      ) : (
        <View style={styles.table}>
          <View style={styles.tableHeader}>
            <Text style={[styles.headerCell, styles.positionCell]}>#</Text>
            <Text style={[styles.headerCell, styles.nameCell]}>SQUADRA</Text>
            <Text style={styles.headerCell}>PG</Text>
            <Text style={styles.headerCell}>V</Text>
            <Text style={styles.headerCell}>N</Text>
            <Text style={styles.headerCell}>P</Text>
            <Text style={[styles.headerCell, styles.goalsCell]}>GF:GS</Text>
            <Text style={[styles.headerCell, styles.pointsCell]}>PT</Text>
          </View>
          {state.standings.map((standing) => (
            <StandingRow
              current={standing.teamId === league.team?.id}
              key={standing.teamId}
              onPress={(isCurrent) =>
                onOpenTeam(
                  { id: standing.teamId, name: standing.teamName },
                  isCurrent,
                )
              }
              standing={standing}
              tiebreaker={state.tiebreaker}
            />
          ))}
        </View>
      )}

      <View style={styles.rulesCard}>
        <Text style={styles.rulesEyebrow}>CRITERIO CLASSIFICA</Text>
        <Text style={styles.rulesTitle}>
          {tiebreakerTitle(state.tiebreaker)}
        </Text>
        <Text style={styles.rulesBody}>
          {tiebreakerDescription(state.tiebreaker)}
        </Text>
      </View>

      <View style={styles.rulesCard}>
        <Text style={styles.rulesEyebrow}>REGOLA GOL</Text>
        <Text style={styles.rulesTitle}>
          {results.center?.goalBandsEnabled
            ? 'Ogni gol ha la sua fascia'
            : `Da ${formatPoints(
                results.center?.goalThreshold ?? 66,
              )} si gonfia la rete`}
        </Text>
        <Text style={styles.rulesBody}>
          {results.center?.goalBandsEnabled
            ? results.center.goalBands
                .map(
                  (threshold, index) =>
                    `${index + 1} gol a ${formatPoints(threshold)}`,
                )
                .join(', ')
            : `Primo gol a ${formatPoints(
                results.center?.goalThreshold ?? 66,
              )} fantapunti, poi uno ogni ${formatPoints(
                results.center?.goalStep ?? 6,
              )}`}
          . Vittoria 3 punti, pareggio 1, sconfitta 0.
          {results.center?.goalMarginEnabled
            ? ` A parità di gol, uno scarto di almeno ${formatPoints(
                results.center.goalMargin,
              )} assegna un gol aggiuntivo.`
            : ''}{' '}
          La classifica usa esclusivamente giornate ufficializzate.
        </Text>
      </View>

      <Modal
        animationType="fade"
        onRequestClose={closeCorrection}
        transparent
        visible={Boolean(correctionFixture)}
      >
        <View style={styles.modalBackdrop}>
          <View style={styles.correctionModal}>
            <Text style={styles.correctionEyebrow}>
              CORREZIONE PUNTUALE
            </Text>
            <Text style={styles.correctionTitle}>
              {correctionFixture
                ? `${correctionFixture.homeTeamName}–${correctionFixture.awayTeamName}`
                : 'Risultato ufficiale'}
            </Text>
            <Text style={styles.correctionBody}>
              {correctionFixture?.providerRemediationRequired
                ? 'La riapertura verrà collegata alla generazione provider ancora corrente. Se nel frattempo lo stato cambia, l’operazione verrà bloccata.'
                : 'Solo questa partita uscirà temporaneamente dalla classifica. Le altre resteranno ufficiali.'}
            </Text>
            <TextInput
              editable={!results.actionLoading}
              maxLength={240}
              multiline
              onChangeText={(value) => {
                setCorrectionReason(value);
                setCorrectionError('');
              }}
              placeholder="Es. Assist corretto dal provider ufficiale"
              placeholderTextColor={colors.mutedLight}
              style={styles.correctionInput}
              value={correctionReason}
            />
            <View style={styles.correctionCounterRow}>
              <Text style={styles.correctionHint}>
                Motivazione obbligatoria
              </Text>
              <Text style={styles.correctionCounter}>
                {correctionReason.trim().length}/240
              </Text>
            </View>
            {correctionError ? (
              <Text style={styles.correctionError}>
                {correctionError}
              </Text>
            ) : null}
            <View style={styles.correctionActions}>
              <Pressable
                disabled={results.actionLoading}
                onPress={closeCorrection}
                style={styles.correctionCancel}
              >
                <Text style={styles.correctionCancelText}>ANNULLA</Text>
              </Pressable>
              <Pressable
                disabled={results.actionLoading}
                onPress={() => void submitCorrection()}
                style={[
                  styles.correctionConfirm,
                  results.actionLoading && styles.actionButtonDisabled,
                ]}
              >
                {results.actionLoading ? (
                  <ActivityIndicator color={colors.lime} size="small" />
                ) : (
                  <Text style={styles.correctionConfirmText}>
                    RIAPRI RISULTATO
                  </Text>
                )}
              </Pressable>
            </View>
          </View>
        </View>
      </Modal>
    </ScrollView>
  );
}

function MatchdayCard({
  actionError,
  actionLoading,
  canGoNext,
  canGoPrevious,
  matchday,
  myTeamId,
  onFinalize,
  onNext,
  onPrevious,
  onCorrect,
}: {
  actionError: string;
  actionLoading: boolean;
  canGoNext: boolean;
  canGoPrevious: boolean;
  matchday: LeagueMatchdayResult;
  myTeamId: string | null;
  onFinalize: () => void;
  onNext: () => void;
  onPrevious: () => void;
  onCorrect: (fixture: LeagueFixtureResult) => void;
}) {
  return (
    <View style={styles.matchdayCard}>
      <View style={styles.matchdayToolbar}>
        <Pressable
          accessibilityLabel="Giornata precedente"
          disabled={!canGoPrevious}
          onPress={onPrevious}
          style={[
            styles.matchdayArrow,
            !canGoPrevious && styles.matchdayArrowDisabled,
          ]}
        >
          <Text style={styles.matchdayArrowText}>‹</Text>
        </Pressable>
        <View style={styles.matchdayHeading}>
          <Text style={styles.matchdayEyebrow}>GIORNATA</Text>
          <Text style={styles.matchdayNumber}>{matchday.number}</Text>
        </View>
        <Pressable
          accessibilityLabel="Giornata successiva"
          disabled={!canGoNext}
          onPress={onNext}
          style={[
            styles.matchdayArrow,
            !canGoNext && styles.matchdayArrowDisabled,
          ]}
        >
          <Text style={styles.matchdayArrowText}>›</Text>
        </Pressable>
      </View>

      <View style={styles.matchdayStatusRow}>
        <View
          style={[
            styles.matchdayStatus,
            statusStyle(matchday.status),
          ]}
        >
          <Text style={styles.matchdayStatusText}>
            {statusLabel(matchday.status)}
          </Text>
        </View>
        <Text style={styles.matchdayDate}>
          {formatMatchdayDate(matchday.startsAt)}
        </Text>
      </View>

      <Text style={styles.matchdayMessage}>{statusMessage(matchday)}</Text>

      <View style={styles.fixturesList}>
        {matchday.fixtures.map((fixture) => (
          <FixtureResultRow
            fixture={fixture}
            key={fixture.id}
            myTeamId={myTeamId}
            onCorrect={onCorrect}
          />
        ))}
      </View>

      <View style={styles.matchdayProgressRow}>
        <Text style={styles.matchdayProgressLabel}>TABELLINI COMPLETI</Text>
        <Text style={styles.matchdayProgressValue}>
          {matchday.readyCount}/{matchday.fixtureCount}
        </Text>
      </View>

      {actionError ? (
        <Text style={styles.matchdayActionError}>{actionError}</Text>
      ) : null}

      {matchday.canFinalize ? (
        <Pressable
          disabled={actionLoading}
          onPress={onFinalize}
          style={[
            styles.officialButton,
            actionLoading && styles.actionButtonDisabled,
          ]}
        >
          {actionLoading ? (
            <ActivityIndicator color={colors.lime} size="small" />
          ) : (
            <Text style={styles.officialButtonText}>
              UFFICIALIZZA GIORNATA
            </Text>
          )}
        </Pressable>
      ) : null}
    </View>
  );
}

function FixtureResultRow({
  fixture,
  myTeamId,
  onCorrect,
}: {
  fixture: LeagueFixtureResult;
  myTeamId: string | null;
  onCorrect: (fixture: LeagueFixtureResult) => void;
}) {
  return (
    <View style={styles.fixtureItem}>
      <View style={styles.fixtureRow}>
        <View style={styles.fixtureTeams}>
          <Text
            numberOfLines={1}
            style={[
              styles.fixtureTeam,
              fixture.homeTeamId === myTeamId && styles.fixtureMyTeam,
            ]}
          >
            {fixture.homeTeamName}
          </Text>
          <Text
            numberOfLines={1}
            style={[
              styles.fixtureTeam,
              fixture.awayTeamId === myTeamId && styles.fixtureMyTeam,
            ]}
          >
            {fixture.awayTeamName}
          </Text>
        </View>
        <View style={styles.fixtureScore}>
          <Text style={styles.fixtureGoals}>
            {formatNullable(fixture.homeGoals)}
          </Text>
          <Text style={styles.fixtureGoals}>
            {formatNullable(fixture.awayGoals)}
          </Text>
        </View>
        <View style={styles.fixturePoints}>
          <Text style={styles.fixturePointsText}>
            {formatScoreDetail(
              fixture.homePoints,
              fixture.homeDefenseModifier,
              fixture.homeBonusApplied,
              fixture.homeGoalMarginBonus,
            )}
          </Text>
          <Text style={styles.fixturePointsText}>
            {formatScoreDetail(
              fixture.awayPoints,
              fixture.awayDefenseModifier,
              0,
              fixture.awayGoalMarginBonus,
            )}
          </Text>
        </View>
        <View
          style={[
            styles.fixtureState,
            fixture.status === 'official' && styles.fixtureStateOfficial,
            fixture.status === 'ready' && styles.fixtureStateReady,
          ]}
        >
          <Text
            style={[
              styles.fixtureStateText,
              fixture.status === 'official' &&
                styles.fixtureStateTextOfficial,
            ]}
          >
            {fixture.status === 'official'
              ? 'OK'
              : `${fixture.homeCountedPlayers}/${fixture.awayCountedPlayers}`}
          </Text>
        </View>
      </View>
      {fixture.providerRemediationRequired ? (
        <View style={styles.fixtureProviderAlert}>
          <Text style={styles.fixtureProviderAlertTitle}>
            CORREZIONE PROVIDER RICHIESTA
          </Text>
          <Text style={styles.fixtureProviderAlertBody}>
            La proiezione ufficiale non coincide più con gli input correnti.
            La riapertura userà la generazione certificata{' '}
            {fixture.providerImpactGeneration ?? '—'}.
          </Text>
        </View>
      ) : fixture.providerRemediationStatus === 'in_correction' ? (
        <View style={styles.fixtureProviderCorrection}>
          <Text style={styles.fixtureProviderCorrectionText}>
            CORREZIONE PROVIDER IN CORSO
            {fixture.providerCausalStartCertified ? ' · PRESA IN CARICO CERTIFICATA' : ''}
          </Text>
        </View>
      ) : null}
      {fixture.correctionReason ? (
        <Text style={styles.fixtureCorrectionReason}>
          REVISIONE {fixture.revision} · {fixture.correctionReason}
        </Text>
      ) : null}
      {fixture.canCorrect ? (
        <Pressable
          onPress={() => onCorrect(fixture)}
          style={styles.fixtureCorrectionButton}
        >
          <Text style={styles.fixtureCorrectionButtonText}>
            {fixture.providerRemediationRequired
              ? 'AVVIA CORREZIONE PROVIDER'
              : 'CORREGGI SOLO QUESTA PARTITA'}
          </Text>
        </Pressable>
      ) : null}
    </View>
  );
}

function statusLabel(status: MatchdayResultStatus) {
  switch (status) {
    case 'live':
      return 'LIVE';
    case 'pending':
      return 'IN VERIFICA';
    case 'ready':
      return 'PRONTA';
    case 'official':
      return 'UFFICIALE';
    default:
      return 'DA GIOCARE';
  }
}

function statusStyle(status: MatchdayResultStatus) {
  if (status === 'official') {
    return styles.matchdayStatusOfficial;
  }
  if (status === 'ready') {
    return styles.matchdayStatusReady;
  }
  if (status === 'live') {
    return styles.matchdayStatusLive;
  }
  return null;
}

function statusMessage(matchday: LeagueMatchdayResult) {
  switch (matchday.status) {
    case 'official':
      return 'Risultati acquisiti e classifica aggiornata.';
    case 'ready':
      return 'Tutti i voti sono definitivi. Il Presidente può chiudere la giornata.';
    case 'pending':
      return 'Le partite sono terminate, ma mancano ancora alcuni voti definitivi.';
    case 'live':
      return 'Fantapunti e gol sono provvisori finché la giornata non viene ufficializzata.';
    default:
      return 'I punteggi compariranno automaticamente dopo il calcio d’inizio.';
  }
}

function formatMatchdayDate(value: string) {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) {
    return 'DATA DA DEFINIRE';
  }
  return date
    .toLocaleDateString('it-IT', {
      day: '2-digit',
      month: 'short',
      year: 'numeric',
    })
    .toUpperCase();
}

function formatShortDate(value: string) {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) {
    return '—';
  }
  return date.toLocaleDateString('it-IT', {
    day: '2-digit',
    month: '2-digit',
    year: '2-digit',
  });
}

function formatNullable(value: number | null) {
  if (value === null) {
    return '—';
  }
  return formatPoints(value);
}

function formatScoreDetail(
  total: number | null,
  defenseModifier: number,
  homeBonus: number,
  goalMarginBonus: number,
) {
  if (total === null) {
    return '— FP';
  }

  const additions = [
    defenseModifier > 0
      ? `+${formatPoints(defenseModifier)} MD`
      : null,
    homeBonus > 0 ? `+${formatPoints(homeBonus)} C` : null,
    goalMarginBonus > 0 ? '+1 G SCARTO' : null,
  ].filter(Boolean);

  return `${formatPoints(total)} FP${
    additions.length > 0 ? ` · ${additions.join(' ')}` : ''
  }`;
}

function HeroStat({ label, value }: { label: string; value: string }) {
  return (
    <View style={styles.heroStat}>
      <Text style={styles.heroStatValue}>{value}</Text>
      <Text style={styles.heroStatLabel}>{label}</Text>
    </View>
  );
}

function ChampionStat({ label, value }: { label: string; value: string }) {
  return (
    <View style={styles.championStat}>
      <Text style={styles.championStatValue}>{value}</Text>
      <Text style={styles.championStatLabel}>{label}</Text>
    </View>
  );
}

function StandingRow({
  current,
  standing,
  tiebreaker,
  onPress,
}: {
  current: boolean;
  standing: LeagueStanding;
  tiebreaker: StandingsTiebreaker;
  onPress: (isCurrent: boolean) => void;
}) {
  return (
    <Pressable
      accessibilityLabel={`Apri la rosa di ${standing.teamName}`}
      accessibilityRole="button"
      onPress={() => onPress(current)}
      style={({ pressed }) => [
        styles.tableRow,
        current && styles.currentRow,
        pressed && styles.tableRowPressed,
      ]}
    >
      <View style={styles.positionCell}>
        <View style={[styles.positionBadge, current && styles.currentBadge]}>
          <Text
            style={[
              styles.positionText,
              current && styles.currentPositionText,
            ]}
          >
            {standing.position}
          </Text>
        </View>
      </View>
      <View style={styles.nameCell}>
        <Text
          numberOfLines={1}
          style={[styles.teamName, current && styles.currentTeamName]}
        >
          {standing.teamName}
        </Text>
        <Text style={styles.fantasyPoints}>
          {standingDetail(standing, tiebreaker)}
        </Text>
      </View>
      <Text style={styles.statCell}>{standing.played}</Text>
      <Text style={styles.statCell}>{standing.won}</Text>
      <Text style={styles.statCell}>{standing.drawn}</Text>
      <Text style={styles.statCell}>{standing.lost}</Text>
      <Text style={[styles.statCell, styles.goalsCell]}>
        {standing.goalsFor}:{standing.goalsAgainst}
      </Text>
      <Text style={[styles.leaguePoints, styles.pointsCell]}>
        {standing.leaguePoints}
      </Text>
    </Pressable>
  );
}

function standingDetail(
  standing: LeagueStanding,
  tiebreaker: StandingsTiebreaker,
) {
  if (tiebreaker === 'fantasy_points') {
    return `${formatPoints(standing.pointsFor)} FP · DR ${formatSigned(
      standing.goalDifference,
    )}`;
  }

  if (tiebreaker === 'head_to_head') {
    if (standing.headToHeadEligible) {
      return `SD ${standing.headToHeadPoints} PT · DR ${formatSigned(
        standing.headToHeadGoalDifference,
      )}`;
    }
    return `SD in attesa · DR ${formatSigned(standing.goalDifference)}`;
  }

  return `DR ${formatSigned(standing.goalDifference)} · ${formatPoints(
    standing.pointsFor,
  )} FP`;
}

function tiebreakerTitle(tiebreaker: StandingsTiebreaker) {
  switch (tiebreaker) {
    case 'fantasy_points':
      return 'Prima contano i fantapunti';
    case 'head_to_head':
      return 'Prima gli scontri diretti';
    default:
      return 'Prima la differenza reti';
  }
}

function tiebreakerDescription(tiebreaker: StandingsTiebreaker) {
  switch (tiebreaker) {
    case 'fantasy_points':
      return 'A pari punti di campionato: fantapunti totali, differenza reti, gol fatti e nome squadra.';
    case 'head_to_head':
      return 'La mini-classifica usa punti, differenza reti e gol fatti negli scontri diretti. Se i confronti reciproci non sono ancora omogenei, il criterio passa automaticamente a differenza reti, gol fatti e fantapunti.';
    default:
      return 'A pari punti di campionato: differenza reti, gol fatti, fantapunti totali e nome squadra.';
  }
}

function formatSigned(value: number) {
  return value > 0 ? `+${value}` : String(value);
}

function formatPoints(value: number) {
  return Number.isInteger(value) ? String(value) : value.toFixed(1);
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
  centerRoot: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    padding: 25,
    backgroundColor: colors.canvas,
  },
  centerTitle: {
    color: colors.navy,
    fontSize: 20,
    fontWeight: '900',
    marginBottom: 18,
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
    letterSpacing: 0.5,
  },
  title: {
    color: colors.navy,
    fontSize: 25,
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
    fontSize: 22,
    fontWeight: '900',
  },
  heroCard: {
    minHeight: 205,
    borderRadius: radius.xl,
    justifyContent: 'space-between',
    padding: 24,
    backgroundColor: colors.navy,
  },
  championCard: {
    borderRadius: radius.xl,
    padding: 24,
    marginBottom: 16,
    backgroundColor: colors.lime,
  },
  championEyebrow: {
    color: colors.navy,
    fontSize: 9,
    fontWeight: '900',
    letterSpacing: 0.7,
  },
  championTeam: {
    color: colors.navy,
    fontSize: 29,
    fontWeight: '900',
    marginTop: 8,
  },
  championManager: {
    color: colors.navy,
    fontSize: 11,
    fontWeight: '800',
    marginTop: 3,
  },
  championStats: {
    flexDirection: 'row',
    gap: 10,
    marginTop: 22,
  },
  championStat: {
    flex: 1,
    borderTopWidth: 1,
    borderTopColor: 'rgba(7, 20, 38, 0.22)',
    paddingTop: 10,
  },
  championStatValue: {
    color: colors.navy,
    fontSize: 16,
    fontWeight: '900',
  },
  championStatLabel: {
    color: colors.navy,
    fontSize: 7,
    fontWeight: '900',
    marginTop: 3,
  },
  championNote: {
    color: colors.navy,
    fontSize: 9,
    fontWeight: '700',
    lineHeight: 14,
    marginTop: 16,
  },
  heroEyebrow: {
    color: colors.mutedLight,
    fontSize: 9,
    fontWeight: '900',
    letterSpacing: 0.7,
  },
  heroPosition: {
    color: colors.lime,
    fontSize: 48,
    fontWeight: '900',
    marginTop: 4,
  },
  heroTeam: {
    color: colors.warmWhite,
    fontSize: 17,
    fontWeight: '900',
  },
  heroStats: {
    flexDirection: 'row',
    gap: 10,
    marginTop: 22,
  },
  heroStat: {
    flex: 1,
    borderTopWidth: 1,
    borderTopColor: colors.navyLine,
    paddingTop: 11,
  },
  heroStatValue: {
    color: colors.warmWhite,
    fontSize: 18,
    fontWeight: '900',
  },
  heroStatLabel: {
    color: colors.mutedLight,
    fontSize: 8,
    fontWeight: '900',
    marginTop: 3,
  },
  sectionHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    marginBottom: 12,
    marginTop: 26,
  },
  sectionTitle: {
    color: colors.navy,
    fontSize: 18,
    fontWeight: '900',
  },
  liveLabel: {
    color: colors.muted,
    fontSize: 8,
    fontWeight: '900',
    letterSpacing: 0.4,
  },
  matchdayCard: {
    overflow: 'hidden',
    borderRadius: radius.xl,
    padding: 18,
    backgroundColor: colors.white,
  },
  matchdayToolbar: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
  },
  matchdayArrow: {
    width: 38,
    height: 38,
    borderRadius: 19,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.canvasMuted,
  },
  matchdayArrowDisabled: {
    opacity: 0.28,
  },
  matchdayArrowText: {
    color: colors.navy,
    fontSize: 27,
    fontWeight: '800',
    lineHeight: 29,
  },
  matchdayHeading: {
    alignItems: 'center',
  },
  matchdayEyebrow: {
    color: colors.muted,
    fontSize: 8,
    fontWeight: '900',
    letterSpacing: 0.7,
  },
  matchdayNumber: {
    color: colors.navy,
    fontSize: 27,
    fontWeight: '900',
    marginTop: 1,
  },
  matchdayStatusRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    marginTop: 16,
  },
  matchdayStatus: {
    borderRadius: 999,
    paddingHorizontal: 10,
    paddingVertical: 6,
    backgroundColor: colors.canvasMuted,
  },
  matchdayStatusLive: {
    backgroundColor: '#FFE9DA',
  },
  matchdayStatusReady: {
    backgroundColor: '#E7F4FF',
  },
  matchdayStatusOfficial: {
    backgroundColor: '#E8F8B9',
  },
  matchdayStatusText: {
    color: colors.navy,
    fontSize: 8,
    fontWeight: '900',
    letterSpacing: 0.5,
  },
  matchdayDate: {
    color: colors.muted,
    fontSize: 9,
    fontWeight: '900',
  },
  matchdayMessage: {
    color: colors.muted,
    fontSize: 11,
    lineHeight: 17,
    marginTop: 10,
  },
  fixturesList: {
    borderTopWidth: StyleSheet.hairlineWidth,
    borderTopColor: colors.canvasMuted,
    marginTop: 16,
  },
  fixtureItem: {
    borderBottomWidth: StyleSheet.hairlineWidth,
    borderBottomColor: colors.canvasMuted,
    paddingBottom: 10,
  },
  fixtureRow: {
    minHeight: 66,
    flexDirection: 'row',
    alignItems: 'center',
    paddingVertical: 10,
  },
  fixtureTeams: {
    flex: 1,
    minWidth: 100,
    gap: 7,
  },
  fixtureTeam: {
    color: colors.navy,
    fontSize: 10,
    fontWeight: '800',
  },
  fixtureMyTeam: {
    fontWeight: '900',
  },
  fixtureScore: {
    width: 28,
    alignItems: 'center',
    gap: 4,
  },
  fixtureGoals: {
    color: colors.navy,
    fontSize: 13,
    fontWeight: '900',
  },
  fixturePoints: {
    width: 82,
    alignItems: 'flex-end',
    gap: 7,
  },
  fixturePointsText: {
    color: colors.muted,
    fontSize: 7,
    fontWeight: '800',
  },
  fixtureState: {
    width: 33,
    minHeight: 22,
    borderRadius: 8,
    alignItems: 'center',
    justifyContent: 'center',
    marginLeft: 8,
    backgroundColor: colors.canvasMuted,
  },
  fixtureStateReady: {
    backgroundColor: '#E7F4FF',
  },
  fixtureStateOfficial: {
    backgroundColor: colors.navy,
  },
  fixtureStateText: {
    color: colors.muted,
    fontSize: 7,
    fontWeight: '900',
  },
  fixtureStateTextOfficial: {
    color: colors.lime,
  },
  fixtureProviderAlert: {
    marginTop: 10,
    padding: 11,
    borderRadius: 12,
    backgroundColor: '#FFF3D9',
  },
  fixtureProviderAlertTitle: {
    color: '#8A4B00',
    fontSize: 10,
    fontWeight: '900',
    letterSpacing: 0.4,
  },
  fixtureProviderAlertBody: {
    marginTop: 5,
    color: '#6A4216',
    fontSize: 12,
    fontWeight: '700',
    lineHeight: 17,
  },
  fixtureProviderCorrection: {
    marginTop: 10,
    paddingVertical: 8,
    paddingHorizontal: 10,
    borderRadius: 10,
    backgroundColor: '#E7F0FF',
  },
  fixtureProviderCorrectionText: {
    color: '#214E87',
    fontSize: 10,
    fontWeight: '900',
    letterSpacing: 0.35,
  },
  fixtureCorrectionReason: {
    color: colors.muted,
    fontSize: 8,
    fontWeight: '700',
    lineHeight: 13,
    marginTop: -3,
  },
  fixtureCorrectionButton: {
    alignSelf: 'flex-start',
    borderRadius: 10,
    paddingHorizontal: 10,
    paddingVertical: 8,
    marginTop: 8,
    backgroundColor: colors.canvasMuted,
  },
  fixtureCorrectionButtonText: {
    color: colors.navy,
    fontSize: 8,
    fontWeight: '900',
    letterSpacing: 0.3,
  },
  matchdayProgressRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    marginTop: 14,
  },
  matchdayProgressLabel: {
    color: colors.muted,
    fontSize: 8,
    fontWeight: '900',
    letterSpacing: 0.4,
  },
  matchdayProgressValue: {
    color: colors.navy,
    fontSize: 12,
    fontWeight: '900',
  },
  matchdayActionError: {
    color: '#A43B2C',
    fontSize: 10,
    fontWeight: '800',
    lineHeight: 15,
    marginTop: 12,
  },
  officialButton: {
    minHeight: 48,
    borderRadius: radius.md,
    alignItems: 'center',
    justifyContent: 'center',
    marginTop: 16,
    backgroundColor: colors.navy,
  },
  officialButtonText: {
    color: colors.lime,
    fontSize: 10,
    fontWeight: '900',
    letterSpacing: 0.5,
  },
  reopenButton: {
    minHeight: 44,
    borderWidth: 1,
    borderColor: colors.canvasMuted,
    borderRadius: radius.md,
    alignItems: 'center',
    justifyContent: 'center',
    marginTop: 14,
    backgroundColor: colors.white,
  },
  reopenButtonText: {
    color: colors.navy,
    fontSize: 9,
    fontWeight: '900',
    letterSpacing: 0.4,
  },
  actionButtonDisabled: {
    opacity: 0.6,
  },
  modalBackdrop: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    padding: 24,
    backgroundColor: 'rgba(7, 20, 38, 0.72)',
  },
  correctionModal: {
    width: '100%',
    maxWidth: 520,
    borderRadius: radius.xl,
    padding: 24,
    backgroundColor: colors.white,
  },
  correctionEyebrow: {
    color: colors.muted,
    fontSize: 9,
    fontWeight: '900',
    letterSpacing: 0.5,
  },
  correctionTitle: {
    color: colors.navy,
    fontSize: 20,
    fontWeight: '900',
    marginTop: 7,
  },
  correctionBody: {
    color: colors.muted,
    fontSize: 12,
    lineHeight: 18,
    marginTop: 8,
  },
  correctionInput: {
    minHeight: 112,
    borderWidth: 1,
    borderColor: colors.canvasMuted,
    borderRadius: radius.md,
    color: colors.navy,
    fontSize: 13,
    lineHeight: 19,
    padding: 14,
    marginTop: 18,
    textAlignVertical: 'top',
    backgroundColor: colors.canvas,
  },
  correctionCounterRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    marginTop: 7,
  },
  correctionHint: {
    color: colors.muted,
    fontSize: 8,
    fontWeight: '800',
  },
  correctionCounter: {
    color: colors.muted,
    fontSize: 8,
    fontWeight: '900',
  },
  correctionError: {
    color: '#A43B2C',
    fontSize: 10,
    fontWeight: '800',
    lineHeight: 15,
    marginTop: 12,
  },
  correctionActions: {
    flexDirection: 'row',
    gap: 10,
    marginTop: 20,
  },
  correctionCancel: {
    flex: 1,
    minHeight: 46,
    alignItems: 'center',
    justifyContent: 'center',
    borderRadius: radius.md,
    backgroundColor: colors.canvasMuted,
  },
  correctionCancelText: {
    color: colors.navy,
    fontSize: 9,
    fontWeight: '900',
  },
  correctionConfirm: {
    flex: 1.4,
    minHeight: 46,
    alignItems: 'center',
    justifyContent: 'center',
    borderRadius: radius.md,
    backgroundColor: colors.navy,
  },
  correctionConfirmText: {
    color: colors.lime,
    fontSize: 9,
    fontWeight: '900',
  },
  loadingCard: {
    minHeight: 180,
    borderRadius: radius.lg,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.white,
  },
  loadingText: {
    color: colors.muted,
    fontSize: 12,
    marginTop: 10,
  },
  errorCard: {
    borderRadius: radius.lg,
    padding: 22,
    backgroundColor: colors.navy,
  },
  errorTitle: {
    color: colors.warmWhite,
    fontSize: 17,
    fontWeight: '900',
  },
  errorBody: {
    color: colors.mutedLight,
    fontSize: 12,
    lineHeight: 18,
    marginTop: 8,
  },
  emptyCard: {
    borderRadius: radius.lg,
    padding: 22,
    backgroundColor: colors.white,
  },
  emptyTitle: {
    color: colors.navy,
    fontSize: 17,
    fontWeight: '900',
  },
  emptyBody: {
    color: colors.muted,
    fontSize: 12,
    lineHeight: 18,
    marginTop: 8,
  },
  inlineButton: {
    alignSelf: 'flex-start',
    borderRadius: radius.md,
    paddingHorizontal: 14,
    paddingVertical: 11,
    marginTop: 16,
    backgroundColor: colors.navy,
  },
  inlineButtonText: {
    color: colors.lime,
    fontSize: 9,
    fontWeight: '900',
  },
  table: {
    overflow: 'hidden',
    borderRadius: radius.lg,
    backgroundColor: colors.white,
  },
  tableHeader: {
    height: 37,
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 8,
    backgroundColor: colors.canvasMuted,
  },
  tableRow: {
    minHeight: 61,
    flexDirection: 'row',
    alignItems: 'center',
    borderBottomWidth: StyleSheet.hairlineWidth,
    borderBottomColor: colors.canvasMuted,
    paddingHorizontal: 8,
  },
  tableRowPressed: {
    opacity: 0.72,
  },
  currentRow: {
    backgroundColor: '#F4FFD9',
  },
  headerCell: {
    width: 25,
    color: colors.muted,
    fontSize: 8,
    fontWeight: '900',
    textAlign: 'center',
  },
  positionCell: {
    width: 30,
    alignItems: 'center',
  },
  nameCell: {
    flex: 1,
    minWidth: 95,
  },
  goalsCell: {
    width: 37,
  },
  pointsCell: {
    width: 31,
  },
  positionBadge: {
    width: 23,
    height: 23,
    borderRadius: 8,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.canvasMuted,
  },
  currentBadge: {
    backgroundColor: colors.navy,
  },
  positionText: {
    color: colors.navy,
    fontSize: 10,
    fontWeight: '900',
  },
  currentPositionText: {
    color: colors.lime,
  },
  teamName: {
    color: colors.navy,
    fontSize: 11,
    fontWeight: '900',
  },
  currentTeamName: {
    color: colors.navy,
  },
  fantasyPoints: {
    color: colors.muted,
    fontSize: 8,
    fontWeight: '700',
    marginTop: 2,
  },
  statCell: {
    width: 25,
    color: colors.navy,
    fontSize: 10,
    fontWeight: '800',
    textAlign: 'center',
  },
  leaguePoints: {
    color: colors.navy,
    fontSize: 14,
    fontWeight: '900',
    textAlign: 'center',
  },
  rulesCard: {
    borderWidth: 1,
    borderColor: colors.canvasMuted,
    borderRadius: radius.lg,
    padding: 20,
    marginTop: 18,
    backgroundColor: colors.white,
  },
  rulesEyebrow: {
    color: colors.muted,
    fontSize: 9,
    fontWeight: '900',
  },
  rulesTitle: {
    color: colors.navy,
    fontSize: 17,
    fontWeight: '900',
    marginTop: 5,
  },
  rulesBody: {
    color: colors.muted,
    fontSize: 12,
    lineHeight: 18,
    marginTop: 8,
  },
  refreshButton: {
    borderRadius: radius.md,
    paddingHorizontal: 20,
    paddingVertical: 14,
    backgroundColor: colors.navy,
  },
  refreshButtonText: {
    color: colors.lime,
    fontSize: 10,
    fontWeight: '900',
  },
});
