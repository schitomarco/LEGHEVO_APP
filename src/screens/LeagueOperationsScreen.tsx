import {
  ActivityIndicator,
  Alert,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  View,
} from 'react-native';
import { useLeagueOperations } from '../hooks/useLeagueOperations';
import { colors, radius, shadow } from '../theme';
import type {
  AppScreen,
  LeagueOperationLineupStatus,
  LeagueOperationMatchdayStatus,
  LeagueOperationsCenter,
  LeagueSummary,
} from '../types';

type Props = {
  league: LeagueSummary | null;
  onBack: () => void;
  onNavigate: (screen: AppScreen) => void;
};

type Priority = {
  key: string;
  tone: 'urgent' | 'action' | 'waiting' | 'done';
  label: string;
  title: string;
  detail: string;
  screen?: AppScreen;
};

export function LeagueOperationsScreen({
  league,
  onBack,
  onNavigate,
}: Props) {
  const operations = useLeagueOperations(
    league?.id ?? null,
    Boolean(league?.isDemo),
  );

  if (!league) {
    return (
      <View style={styles.centerRoot}>
        <Text style={styles.centerTitle}>Prima scegli una lega.</Text>
        <Pressable onPress={onBack} style={styles.darkButton}>
          <Text style={styles.darkButtonText}>TORNA ALLA LEGA</Text>
        </Pressable>
      </View>
    );
  }

  const center = operations.center;
  const lineup = center?.nextLineupMatchday ?? null;
  const focus = center?.focusMatchday ?? null;
  const providerSync = center?.providerSync ?? null;
  const providerBudget = center?.providerBudget ?? null;
  const apiFootballBudget = providerBudget?.providers.find(
    (provider) => provider.provider === 'api-football',
  ) ?? null;
  const footballDataBudget = providerBudget?.providers.find(
    (provider) => provider.provider === 'football-data',
  ) ?? null;
  const providerCacheTotal = providerBudget
    ? providerBudget.cacheHits + providerBudget.cacheMisses
    : 0;
  const providerCacheHitRate = providerCacheTotal > 0 && providerBudget
    ? Math.round((providerBudget.cacheHits / providerCacheTotal) * 100)
    : 0;
  const providerQuality = providerSync?.dataQuality ?? null;
  const providerIncidents = providerSync?.incidentCenter ?? null;
  const providerRecovery = providerSync?.recoveryCenter ?? null;
  const providerRetry = providerRecovery?.retryCenter ?? null;
  const providerCircuit = providerRecovery?.circuitBreaker ?? null;
  const providerVerification = providerRecovery?.outcomeVerification ?? null;
  const providerFencing = providerRecovery?.workerFencing ?? null;
  const providerContracts = providerSync?.payloadContracts ?? null;
  const providerDelivery = providerSync?.deliveryIntegrity ?? null;
  const providerPublication = providerSync?.atomicPublication ?? null;
  const providerScope = providerSync?.semanticScope ?? null;
  const providerWatermark = providerSync?.publicationWatermark ?? null;
  const providerCatalog = providerSync?.playerCatalogReconciliation ?? null;
  const providerFixtureLifecycle =
    providerSync?.fixtureLifecycleReconciliation ?? null;
  const providerFixtureScores = providerSync?.fixtureScoreReconciliation ?? null;
  const providerFixtureScoreCoherence =
    providerSync?.fixtureScoreCoherence ?? null;
  const providerScoreConsumptionGate =
    providerSync?.scoreConsumptionGate ?? null;
  const providerOfficialResultImpact =
    providerSync?.officialResultImpact ?? null;
  const providerOfficialResultRemediation =
    providerSync?.officialResultRemediation ?? null;
  const providerOfficialResultLineage =
    providerSync?.officialResultLineage ?? null;
  const providerOfficialResultRemediationCompletion =
    providerSync?.officialResultRemediationCompletion ?? null;
  const providerMatchdayProgressionGate =
    providerSync?.matchdayProgressionGate ?? null;
  const providerSeasonCompletionGate =
    providerSync?.seasonCompletionGate ?? null;
  const providerCompetitionStart =
    providerSync?.providerCompetitionStart ?? null;
  const providerReliabilityModel =
    providerSync?.providerReliabilityModel ?? null;
  const applicationIntegrityModel =
    providerSync?.applicationIntegrityModel ?? null;
  const applicationReleaseModel =
    providerSync?.applicationReleaseModel ?? null;
  const applicationRolloutModel =
    providerSync?.applicationRolloutModel ?? null;
  const applicationOperationalTelemetry =
    providerSync?.applicationOperationalTelemetry ?? null;
  const applicationOperationalOutbox =
    providerSync?.applicationOperationalOutbox ?? null;
  const applicationOperationalConsumerDelivery =
    providerSync?.applicationOperationalConsumerDelivery ?? null;
  const applicationOperationalDeliveryAudit =
    providerSync?.applicationOperationalDeliveryAudit ?? null;
  const applicationDisasterRecovery =
    providerSync?.applicationDisasterRecovery ?? null;
  const applicationPhysicalBackup =
    providerSync?.applicationPhysicalBackup ?? null;
  const applicationServiceReturn =
    providerSync?.applicationServiceReturn ?? null;
  const applicationProductionReadiness =
    providerSync?.applicationProductionReadiness ?? null;
  const submittedCount = lineup
    ? lineup.manualCount + lineup.carriedCount
    : 0;
  const priorities = buildPriorities(center);

  const confirmReminders = () => {
    if (!lineup) {
      return;
    }
    const targetCount = lineup.draftCount + lineup.missingCount;
    Alert.alert(
      `Inviare ${targetCount} promemoria?`,
      'Ogni manager senza formazione consegnata riceverà una sola notifica per questa giornata.',
      [
        { text: 'Annulla', style: 'cancel' },
        {
          text: 'Invia',
          onPress: () => void operations.sendReminders(lineup.id),
        },
      ],
    );
  };

  const confirmCircuitBreakerRelease = () => {
    const breaker = providerCircuit?.latestOpen;
    if (!breaker) {
      return;
    }
    Alert.alert(
      'Riaprire i recuperi provider?',
      `${breaker.summary}

Il blocco sarà rilasciato dalla Direzione. Dopo l’aggiornamento potrai accodare un nuovo recupero manuale.`,
      [
        { text: 'Annulla', style: 'cancel' },
        {
          text: 'Riapri',
          onPress: () =>
            void operations.releaseCircuitBreaker(
              breaker.id,
              breaker.revision,
            ),
        },
      ],
    );
  };

  const confirmProviderRecovery = () => {
    const incident = providerRecovery?.recoverableIncident;
    if (!incident) {
      return;
    }
    Alert.alert(
      'Accodare il recupero provider?',
      `${incident.summary}

La richiesta sarà certificata e affidata al worker server senza duplicare i run già attivi.`,
      [
        { text: 'Annulla', style: 'cancel' },
        {
          text: 'Accoda',
          onPress: () =>
            void operations.requestRecovery(incident.id, incident.revision),
        },
      ],
    );
  };

  return (
    <ScrollView
      style={styles.screen}
      contentContainerStyle={styles.content}
      showsVerticalScrollIndicator={false}
    >
      <View style={styles.header}>
        <Pressable
          accessibilityLabel="Torna alla lega"
          onPress={onBack}
          style={styles.backButton}
        >
          <Text style={styles.backText}>‹</Text>
        </Pressable>
        <View style={styles.headerCopy}>
          <Text style={styles.eyebrow}>AREA PRESIDENTE</Text>
          <Text numberOfLines={1} style={styles.title}>
            Centro Operativo
          </Text>
        </View>
        <Pressable
          accessibilityLabel="Aggiorna Centro Operativo"
          disabled={operations.loading}
          onPress={() => void operations.refresh()}
          style={[
            styles.reloadButton,
            operations.loading && styles.reloadButtonDisabled,
          ]}
        >
          {operations.loading ? (
            <ActivityIndicator color={colors.lime} size="small" />
          ) : (
            <Text style={styles.reloadText}>↻</Text>
          )}
        </Pressable>
      </View>

      {operations.loading ? (
        <View style={styles.loadingCard}>
          <ActivityIndicator color={colors.navy} />
          <Text style={styles.loadingText}>
            Controllo consegne, voti e scadenze…
          </Text>
        </View>
      ) : operations.error ? (
        <View style={styles.errorCard}>
          <Text style={styles.errorTitle}>Centro non disponibile</Text>
          <Text style={styles.errorBody}>{operations.error}</Text>
          <Pressable
            onPress={() => void operations.refresh()}
            style={styles.retryButton}
          >
            <Text style={styles.retryButtonText}>RIPROVA</Text>
          </Pressable>
        </View>
      ) : center ? (
        <>
          <View style={styles.heroCard}>
            <View style={styles.heroTop}>
              <View>
                <Text style={styles.heroEyebrow}>
                  {center.season
                    ? `STAGIONE ${center.season}`
                    : 'GIORNATA DI LEGA'}
                </Text>
                <Text style={styles.heroTitle}>
                  {focus ? `Giornata ${focus.number}` : 'In attesa del calendario'}
                </Text>
              </View>
              <View
                style={[
                  styles.statusPill,
                  focus?.status === 'live' && styles.statusPillLive,
                  focus?.status === 'ready' && styles.statusPillReady,
                ]}
              >
                <Text style={styles.statusPillText}>
                  {focus ? matchdayStatusLabel(focus.status) : 'PRE-CAMPIONATO'}
                </Text>
              </View>
            </View>
            <Text style={styles.heroBody}>
              {focus
                ? focusStatusDescription(focus.status)
                : 'Genera il calendario e avvia la competizione per attivare il controllo settimanale.'}
            </Text>
            {lineup ? (
              <View style={styles.deadlineRow}>
                <Text style={styles.deadlineLabel}>SCADENZA FORMAZIONI</Text>
                <Text style={styles.deadlineValue}>
                  {formatDateTime(lineup.locksAt)}
                </Text>
                <Text style={styles.deadlineCountdown}>
                  {formatCountdown(lineup.locksAt)}
                </Text>
              </View>
            ) : null}
          </View>

          <View style={styles.sectionHeader}>
            <Text style={styles.sectionTitle}>Priorità</Text>
            <Text style={styles.sectionMeta}>{priorities.length} CONTROLLI</Text>
          </View>
          <View style={styles.priorityList}>
            {priorities.map((priority) => (
              <Pressable
                disabled={!priority.screen}
                key={priority.key}
                onPress={() =>
                  priority.screen && onNavigate(priority.screen)
                }
                style={[
                  styles.priorityCard,
                  priority.tone === 'urgent' && styles.priorityCardUrgent,
                  priority.tone === 'done' && styles.priorityCardDone,
                ]}
              >
                <View
                  style={[
                    styles.priorityMarker,
                    priority.tone === 'urgent' &&
                      styles.priorityMarkerUrgent,
                    priority.tone === 'done' && styles.priorityMarkerDone,
                  ]}
                />
                <View style={styles.priorityCopy}>
                  <Text style={styles.priorityLabel}>{priority.label}</Text>
                  <Text style={styles.priorityTitle}>{priority.title}</Text>
                  <Text style={styles.priorityDetail}>{priority.detail}</Text>
                </View>
                {priority.screen ? (
                  <Text style={styles.priorityArrow}>→</Text>
                ) : null}
              </Pressable>
            ))}
          </View>

          <View style={styles.sectionHeader}>
            <Text style={styles.sectionTitle}>Consegne formazione</Text>
            <Text style={styles.sectionMeta}>
              {lineup ? `GIORNATA ${lineup.number}` : 'NESSUNA APERTA'}
            </Text>
          </View>

          {lineup ? (
            <View style={styles.lineupCard}>
              <View style={styles.statsGrid}>
                <Metric
                  label="CONSEGNATE"
                  value={`${submittedCount}/${lineup.teamCount}`}
                />
                <Metric label="BOZZE" value={String(lineup.draftCount)} />
                <Metric label="MANCANTI" value={String(lineup.missingCount)} />
                <Metric
                  label="PROMEMORIA"
                  value={String(lineup.reminderSentCount)}
                />
              </View>

              <View style={styles.teamList}>
                {lineup.teams.map((team) => (
                  <View key={team.teamId} style={styles.teamRow}>
                    <View
                      style={[
                        styles.teamStatus,
                        team.status === 'manual' && styles.teamStatusDone,
                        team.status === 'carried' && styles.teamStatusCarried,
                        team.status === 'missing' && styles.teamStatusMissing,
                      ]}
                    >
                      <Text
                        style={[
                          styles.teamStatusText,
                          team.status === 'manual' &&
                            styles.teamStatusTextDone,
                          team.status === 'missing' &&
                            styles.teamStatusTextMissing,
                        ]}
                      >
                        {lineupStatusSymbol(team.status)}
                      </Text>
                    </View>
                    <View style={styles.teamCopy}>
                      <Text style={styles.teamName}>{team.teamName}</Text>
                      <Text style={styles.teamManager}>
                        {team.managerName} · {lineupStatusLabel(team.status)}
                      </Text>
                    </View>
                    <Text style={styles.teamTime}>
                      {team.submittedAt
                        ? formatTime(team.submittedAt)
                        : team.reminderSent
                          ? 'AVVISATO'
                          : '—'}
                    </Text>
                  </View>
                ))}
              </View>

              {operations.actionError ? (
                <Text style={styles.actionError}>{operations.actionError}</Text>
              ) : null}
              {operations.reminderOutcome ? (
                <View style={styles.successCard}>
                  <Text style={styles.successTitle}>
                    Promemoria controllati
                  </Text>
                  <Text style={styles.successBody}>
                    {operations.reminderOutcome.sentCount} inviati ·{' '}
                    {operations.reminderOutcome.alreadySentCount} già presenti
                  </Text>
                </View>
              ) : null}

              {lineup.canRemind ? (
                <Pressable
                  disabled={operations.actionLoading}
                  onPress={confirmReminders}
                  style={[
                    styles.reminderButton,
                    operations.actionLoading && styles.disabledButton,
                  ]}
                >
                  {operations.actionLoading ? (
                    <ActivityIndicator color={colors.lime} />
                  ) : (
                    <Text style={styles.reminderButtonText}>
                      INVIA PROMEMORIA AI RITARDATARI
                    </Text>
                  )}
                </Pressable>
              ) : (
                <Text style={styles.privacyNote}>
                  Sono visibili solo stato e orario della consegna. I calciatori
                  schierati restano protetti fino alla scadenza.
                </Text>
              )}
            </View>
          ) : (
            <EmptyCard
              body="Non ci sono giornate future con una formazione ancora aperta."
              title="Nessuna consegna da inseguire"
            />
          )}

          <View style={styles.sectionHeader}>
            <Text style={styles.sectionTitle}>Voti e risultati</Text>
            <Text style={styles.sectionMeta}>STATO UFFICIALE</Text>
          </View>

          {focus ? (
            <View style={styles.resultsCard}>
              <View style={styles.resultHeader}>
                <View>
                  <Text style={styles.resultEyebrow}>
                    GIORNATA {focus.number}
                  </Text>
                  <Text style={styles.resultTitle}>
                    {matchdayStatusLabel(focus.status)}
                  </Text>
                </View>
                <Text style={styles.resultRatio}>
                  {focus.officialCount}/{focus.fixtureCount}
                </Text>
              </View>

              <ProgressBar
                total={focus.fixtureCount}
                value={
                  focus.officialCount > 0
                    ? focus.officialCount
                    : focus.readyCount
                }
              />

              <View style={styles.providerRow}>
                <View style={styles.providerCopy}>
                  <Text style={styles.providerLabel}>COPERTURA PROVIDER</Text>
                  <Text style={styles.providerValue}>
                    {focus.scheduleSource === 'provider'
                      ? `${focus.providerFinalFixtureCount}/${focus.providerFixtureCount} partite reali concluse`
                      : 'Date stimate · sincronizzazione in attesa'}
                  </Text>
                </View>
                <View
                  style={[
                    styles.providerDot,
                    focus.scheduleSource === 'provider' &&
                      styles.providerDotActive,
                  ]}
                />
              </View>

              {providerBudget ? (
                <View style={styles.providerHealthCard}>
                  <View style={styles.providerHealthHeader}>
                    <View style={styles.providerHealthCopy}>
                      <Text style={styles.providerHealthEyebrow}>
                        BUDGET PROVIDER
                      </Text>
                      <Text style={styles.providerHealthTitle}>
                        API esterne sotto controllo
                      </Text>
                    </View>
                    <Text style={styles.providerHealthBadge}>
                      CACHE CENTRALE
                    </Text>
                  </View>
                  <View style={styles.providerHealthMetrics}>
                    <View style={styles.providerHealthMetric}>
                      <Text style={styles.providerHealthMetricValue}>
                        {apiFootballBudget
                          ? `${apiFootballBudget.consumedUnits}/${apiFootballBudget.dailyLimit}`
                          : '—'}
                      </Text>
                      <Text style={styles.providerHealthMetricLabel}>
                        API-FOOTBALL OGGI
                      </Text>
                    </View>
                    <View style={styles.providerHealthMetric}>
                      <Text style={styles.providerHealthMetricValue}>
                        {apiFootballBudget?.reservedHighPriorityUnits ?? 0}
                      </Text>
                      <Text style={styles.providerHealthMetricLabel}>
                        RISERVA P0/P1
                      </Text>
                    </View>
                    <View style={styles.providerHealthMetric}>
                      <Text style={styles.providerHealthMetricValue}>
                        {providerCacheHitRate}%
                      </Text>
                      <Text style={styles.providerHealthMetricLabel}>
                        CACHE HIT
                      </Text>
                    </View>
                    <View style={styles.providerHealthMetric}>
                      <Text style={styles.providerHealthMetricValue}>
                        {providerBudget.externalRequestsAvoided}
                      </Text>
                      <Text style={styles.providerHealthMetricLabel}>
                        CHIAMATE EVITATE
                      </Text>
                    </View>
                  </View>
                  <Text style={styles.providerHealthFooter}>
                    football-data.org: {footballDataBudget
                      ? `${footballDataBudget.consumedUnits} richieste tracciate`
                      : 'in attesa di configurazione'}
                    {' · '}previsione 30 giorni{' '}
                    {providerBudget.forecast30Days}
                    {' · '}ultimo sync{' '}
                    {formatOptionalDateTime(providerBudget.lastSyncAt)}
                  </Text>
                </View>
              ) : null}

              {providerSync ? (
                <View
                  style={[
                    styles.providerHealthCard,
                    providerSync.status === 'attention' &&
                      styles.providerHealthCardAttention,
                  ]}
                >
                  <View style={styles.providerHealthHeader}>
                    <View style={styles.providerHealthCopy}>
                      <Text style={styles.providerHealthEyebrow}>
                        PIPELINE DATI PROTETTO
                      </Text>
                      <Text style={styles.providerHealthTitle}>
                        {providerSyncStatusLabel(providerSync.status)}
                      </Text>
                    </View>
                    <Text style={styles.providerHealthBadge}>
                      {providerSync.protected ? 'CERTIFICATO' : 'DA VERIFICARE'}
                    </Text>
                  </View>
                  <View style={styles.providerHealthMetrics}>
                    <View style={styles.providerHealthMetric}>
                      <Text style={styles.providerHealthMetricValue}>
                        {providerSync.stuckRunCount}
                      </Text>
                      <Text style={styles.providerHealthMetricLabel}>
                        RUN BLOCCATI
                      </Text>
                    </View>
                    <View style={styles.providerHealthMetric}>
                      <Text style={styles.providerHealthMetricValue}>
                        {providerSync.failedLast24h}
                      </Text>
                      <Text style={styles.providerHealthMetricLabel}>
                        ERRORI 24H
                      </Text>
                    </View>
                    <View style={styles.providerHealthMetric}>
                      <Text style={styles.providerHealthMetricValue}>
                        {providerQuality?.anomalyCount ?? 0}
                      </Text>
                      <Text style={styles.providerHealthMetricLabel}>
                        ANOMALIE DATI
                      </Text>
                    </View>
                    <View style={styles.providerHealthMetric}>
                      <Text style={styles.providerHealthMetricValue}>
                        {providerIncidents?.activeCount ?? 0}
                      </Text>
                      <Text style={styles.providerHealthMetricLabel}>
                        INCIDENTI
                      </Text>
                    </View>
                  </View>
                  <Text style={styles.providerHealthFooter}>
                    Ultimo dato{' '}
                    {formatOptionalDateTime(providerSync.latestDataAt)}
                    {' · '}
                    {providerSync.actions.length} flussi tracciati
                  </Text>
                  {applicationRolloutModel ? (
                    <>
                      <Text style={styles.providerRecoveryWatchdog}>
                        ROLLOUT {applicationRolloutModel.releaseVersion ?? '—'}{' '}
                        {applicationRolloutModel.status === 'completed'
                          ? 'COMPLETATO'
                          : applicationRolloutModel.status === 'active'
                            ? 'IN CORSO'
                            : applicationRolloutModel.status === 'paused'
                              ? 'IN PAUSA'
                              : applicationRolloutModel.status === 'killed'
                                ? 'FERMATO'
                                : 'DA VERIFICARE'}
                      </Text>
                      <Text style={styles.providerCircuitBreakerSummary}>
                        {applicationRolloutModel.status === 'completed'
                          ? 'Distribuzione certificata al 100% con controlli di salute superati.'
                          : applicationRolloutModel.status === 'active'
                            ? `${applicationRolloutModel.stage ?? 'scaglione'} · ${applicationRolloutModel.exposurePercentage ?? 0}% abilitato · generazione ${applicationRolloutModel.rolloutGeneration ?? '—'}.`
                            : applicationRolloutModel.killSwitchActive
                              ? 'Kill switch attivo: nuove installazioni bloccate finché la Direzione non certifica la ripresa.'
                              : 'Il piano di rollout non coincide più con release, fingerprint o testa certificata.'}
                      </Text>
                    </>
                  ) : null}
                  {applicationOperationalTelemetry ? (
                    <>
                      <Text style={styles.providerRecoveryWatchdog}>
                        TELEMETRIA {applicationOperationalTelemetry.status === 'active'
                          ? 'AUTOREVOLE'
                          : applicationOperationalTelemetry.status === 'degraded'
                            ? 'DEGRADATA'
                            : applicationOperationalTelemetry.status === 'critical'
                              ? 'CRITICA'
                              : 'DA VERIFICARE'}
                      </Text>
                      <Text style={styles.providerCircuitBreakerSummary}>
                        {applicationOperationalTelemetry.status === 'active'
                          ? `Sorgente ${applicationOperationalTelemetry.sourceKey ?? 'certificata'} · finestra ${applicationOperationalTelemetry.lastWindowSequence ?? '—'} · errori ${applicationOperationalTelemetry.latestErrorRateBps ?? 0} bps · p95 ${applicationOperationalTelemetry.latestP95LatencyMs ?? '—'} ms.`
                          : applicationOperationalTelemetry.autoRollbackTriggered
                            ? 'Anomalia critica: kill switch e rollback automatico verso la release precedente certificata.'
                            : 'Finestre fuori sequenza, sorgente non certificata o fingerprint incoerente: promozioni bloccate in sicurezza.'}
                      </Text>
                    </>
                  ) : null}
                  {applicationOperationalOutbox ? (
                    <>
                      <Text style={styles.providerRecoveryWatchdog}>
                        OUTBOX {applicationOperationalOutbox.status === 'active'
                          ? 'CONSEGNATA'
                          : applicationOperationalOutbox.status === 'attention'
                            ? 'IN ATTESA'
                            : applicationOperationalOutbox.status === 'dead_letter'
                              ? 'BLOCCATA'
                              : 'DA VERIFICARE'}
                      </Text>
                      <Text style={styles.providerCircuitBreakerSummary}>
                        {applicationOperationalOutbox.status === 'active'
                          ? `${applicationOperationalOutbox.deliveredCount}/${applicationOperationalOutbox.destinationCount} consegne certificate · sequenza ${applicationOperationalOutbox.lastSequence} · nessuna dead-letter.`
                          : applicationOperationalOutbox.deadLetterCount > 0
                            ? `${applicationOperationalOutbox.deadLetterCount} consegne in dead-letter: promozione e accesso client bloccati in sicurezza.`
                            : `${applicationOperationalOutbox.pendingCount} in attesa · ${applicationOperationalOutbox.retryCount} in retry · ${applicationOperationalOutbox.expiredLeaseCount} lease scadute.`}
                      </Text>
                    </>
                  ) : null}
                  {applicationDisasterRecovery ? (
                    <View style={styles.providerHealthCard}>
                      <Text style={styles.providerHealthTitle}>
                        DISASTER RECOVERY {applicationDisasterRecovery.status === 'certified'
                          ? 'CERTIFICATO'
                          : applicationDisasterRecovery.status === 'stale'
                            ? 'DA RINNOVARE'
                            : 'IN ATTENZIONE'}
                      </Text>
                      <Text style={styles.providerCircuitBreakerSummary}>
                        {applicationDisasterRecovery.status === 'certified'
                          ? `Checkpoint ${applicationDisasterRecovery.checkpointGeneration} · drill ${applicationDisasterRecovery.drillGeneration} · release ${applicationDisasterRecovery.activeVersion ?? '—'} · ${applicationDisasterRecovery.componentCount} componenti verificati.`
                          : applicationDisasterRecovery.status === 'stale'
                            ? 'Il checkpoint non rappresenta più la generazione operativa corrente: serve una nuova prova di ripristino.'
                            : 'La prova di ripristino ha rilevato una divergenza. Le promozioni restano bloccate fino alla remediation.'}
                      </Text>
                    </View>
                  ) : null}

                  {applicationPhysicalBackup ? (
                    <View style={styles.providerHealthCard}>
                      <Text style={styles.providerHealthTitle}>
                        BACKUP FISICO {applicationPhysicalBackup.status === 'certified'
                          ? 'CERTIFICATO'
                          : applicationPhysicalBackup.status === 'stale'
                            ? 'DA RINNOVARE'
                            : 'IN ATTENZIONE'}
                      </Text>
                      <Text style={styles.providerCircuitBreakerSummary}>
                        {applicationPhysicalBackup.status === 'certified'
                          ? `Backup ${applicationPhysicalBackup.backupGeneration} · custodia ${applicationPhysicalBackup.custodySequence} eventi · restore esterno ${applicationPhysicalBackup.rehearsalGeneration} superato · ${Math.round(applicationPhysicalBackup.artifactSizeBytes / 1048576)} MB verificati.`
                          : applicationPhysicalBackup.status === 'stale'
                            ? 'Il backup non rappresenta più il checkpoint corrente: serve un nuovo artefatto e una nuova prova di restore esterno.'
                            : 'Checksum, catena di custodia o prova di ripristino non sono coerenti. Release e promozioni restano bloccate.'}
                      </Text>
                    </View>
                  ) : null}

                  {applicationServiceReturn ? (
                    <View style={styles.providerHealthCard}>
                      <Text style={styles.providerHealthTitle}>
                        RITORNO IN SERVIZIO {applicationServiceReturn.status === 'certified'
                          ? 'CERTIFICATO'
                          : applicationServiceReturn.status === 'recovery'
                            ? 'IN RECOVERY'
                            : 'BLOCCATO'}
                      </Text>
                      <Text style={styles.providerCircuitBreakerSummary}>
                        {applicationServiceReturn.status === 'certified'
                          ? `Generazione ${applicationServiceReturn.recoveryGeneration} · ${applicationServiceReturn.checkCount}/${applicationServiceReturn.requiredCheckCount} controlli · traffico ${applicationServiceReturn.trafficPercentage}% · worker riaperti.`
                          : applicationServiceReturn.status === 'recovery'
                            ? 'Scritture, worker e traffico restano sospesi finché tutti gli otto controlli post-restore non sono certificati.'
                            : 'Una dipendenza è cambiata dopo la riapertura: il sistema è tornato in modalità fail-closed.'}
                      </Text>
                    </View>
                  ) : null}

                  {applicationProductionReadiness ? (
                    <View style={styles.providerHealthCard}>
                      <Text style={styles.providerHealthTitle}>
                        GO-LIVE {applicationProductionReadiness.status === 'certified'
                          ? 'CERTIFICATO'
                          : applicationProductionReadiness.status === 'pending'
                            ? 'IN VERIFICA'
                            : 'BLOCCATO'}
                      </Text>
                      <Text style={styles.providerCircuitBreakerSummary}>
                        {applicationProductionReadiness.status === 'certified'
                          ? `Generazione ${applicationProductionReadiness.readinessGeneration} · ${applicationProductionReadiness.checkCount}/${applicationProductionReadiness.requiredCheckCount} controlli · release ${applicationProductionReadiness.activeVersion ?? '—'} pronta alla produzione.`
                          : applicationProductionReadiness.status === 'pending'
                            ? 'La certificazione finale sta verificando contemporaneamente rilascio, telemetria, consegne, backup e ritorno in servizio.'
                            : 'Una dipendenza della produzione non è più coerente: il go-live resta bloccato in modalità fail-closed.'}
                      </Text>
                    </View>
                  ) : null}

                  {applicationOperationalDeliveryAudit ? (
                    <>
                      <Text style={styles.providerRecoveryWatchdog}>
                        AUDIT CONSEGNE {applicationOperationalDeliveryAudit.status === 'certified'
                          ? 'CERTIFICATO'
                          : applicationOperationalDeliveryAudit.status === 'stale'
                            ? 'DA AGGIORNARE'
                            : applicationOperationalDeliveryAudit.status === 'attention'
                              ? 'IN ATTESA'
                              : 'BLOCCATO'}
                      </Text>
                      <Text style={styles.providerCircuitBreakerSummary}>
                        {applicationOperationalDeliveryAudit.status === 'certified'
                          ? `Generazione ${applicationOperationalDeliveryAudit.auditGeneration} · sequenza ${applicationOperationalDeliveryAudit.auditedThroughSequence} · ${applicationOperationalDeliveryAudit.receiptCount}/${applicationOperationalDeliveryAudit.expectedDeliveryCount} ricevute verificate.`
                          : applicationOperationalDeliveryAudit.status === 'stale'
                            ? `Nuovi eventi dopo la sequenza ${applicationOperationalDeliveryAudit.auditedThroughSequence}: serve una nuova attestazione prima della promozione.`
                            : `${applicationOperationalDeliveryAudit.sequenceGapCount} gap · ${applicationOperationalDeliveryAudit.consistencyMismatchCount} incoerenze · ${applicationOperationalDeliveryAudit.deadLetterCount} dead-letter.`}
                      </Text>
                    </>
                  ) : null}
                  {applicationOperationalConsumerDelivery ? (
                    <>
                      <Text style={styles.providerRecoveryWatchdog}>
                        ACK END-TO-END {applicationOperationalConsumerDelivery.status === 'active'
                          ? 'CERTIFICATI'
                          : applicationOperationalConsumerDelivery.status === 'attention'
                            ? 'IN ATTESA'
                            : 'DA VERIFICARE'}
                      </Text>
                      <Text style={styles.providerCircuitBreakerSummary}>
                        {applicationOperationalConsumerDelivery.status === 'active'
                          ? `${applicationOperationalConsumerDelivery.receiptCount}/${applicationOperationalConsumerDelivery.expectedReceiptCount} ricevute applicative · ${applicationOperationalConsumerDelivery.consumerCount} consumatori certificati · nessun gap.`
                          : applicationOperationalConsumerDelivery.sequenceGapCount > 0
                            ? `${applicationOperationalConsumerDelivery.sequenceGapCount} gap nella sequenza degli ack: replay e promozioni bloccati.`
                            : `${applicationOperationalConsumerDelivery.receiptConsistencyMismatchCount} incoerenze tra consegne outbox e ricevute applicative.`}
                      </Text>
                    </>
                  ) : null}
                  {applicationReleaseModel ? (
                    <>
                      <Text style={styles.providerRecoveryWatchdog}>
                        RELEASE {applicationReleaseModel.activeVersion ?? '—'}{' '}
                        {applicationReleaseModel.status === 'active'
                          ? 'CERTIFICATA'
                          : applicationReleaseModel.status === 'rollback'
                            ? 'IN ROLLBACK'
                            : 'DA VERIFICARE'}
                      </Text>
                      <Text style={styles.providerCircuitBreakerSummary}>
                        {applicationReleaseModel.status === 'active'
                          ? `Client ammessi ${applicationReleaseModel.minSupportedVersion ?? '—'} – ${applicationReleaseModel.maxSupportedVersion ?? '—'} · generazione ${applicationReleaseModel.releaseGeneration ?? '—'}.`
                          : applicationReleaseModel.status === 'rollback'
                            ? `Rollback controllato verso ${applicationReleaseModel.activeVersion ?? 'una release certificata'}: le versioni fuori contratto vengono bloccate all’avvio.`
                            : 'Il contratto di rilascio non coincide con il sigillo applicativo: sospendi la pubblicazione e verifica certificato, fingerprint e testa attiva.'}
                      </Text>
                    </>
                  ) : null}
                  {applicationIntegrityModel ? (
                    <>
                      <Text style={styles.providerRecoveryWatchdog}>
                        MODELLO APP {applicationIntegrityModel.modelClosed ? 'CERTIFICATO' : 'DA VERIFICARE'} ·{' '}
                        {applicationIntegrityModel.passedCount}/{applicationIntegrityModel.checkCount} CAPACITÀ
                      </Text>
                      <Text style={styles.providerCircuitBreakerSummary}>
                        {applicationIntegrityModel.status === 'certified'
                          ? 'Ruoli, mercato, competizioni, giornate, account e provider condividono lo stesso sigillo strutturale.'
                          : 'Il sigillo globale non coincide più con lo schema installato: verifica migrazioni, policy, trigger e RPC prima del rilascio.'}
                      </Text>
                    </>
                  ) : null}
                  {providerReliabilityModel ? (
                    <>
                      <Text style={styles.providerRecoveryWatchdog}>
                        MODELLO PROVIDER {providerReliabilityModel.modelClosed ? 'CHIUSO' : 'DA VERIFICARE'} ·{' '}
                        {providerReliabilityModel.passedCount}/{providerReliabilityModel.checkCount} CAPACITÀ CERTIFICATE
                      </Text>
                      <Text style={styles.providerCircuitBreakerSummary}>
                        {providerReliabilityModel.status === 'certified'
                          ? 'L’intera catena dello Sviluppo 8 è sigillata e la sua impronta strutturale coincide con quella certificata.'
                          : providerReliabilityModel.status === 'attention'
                            ? 'Il sigillo strutturale è valido, ma la pipeline operativa corrente richiede attenzione.'
                            : 'La struttura installata non coincide più con il sigillo certificato: controlla funzioni, trigger e policy provider.'}
                      </Text>
                    </>
                  ) : null}
                  {providerCompetitionStart?.applicable ? (
                    <Text style={styles.providerHealthFooter}>
                      Avvio competizione {providerCompetitionStart.certified ? 'certificato' : 'in attesa'}
                      {' · '}
                      {providerCompetitionStart.fantasyMatchdayCount} giornate
                      {' · '}
                      {providerCompetitionStart.fantasyFixtureCount} partite fantasy
                    </Text>
                  ) : null}
                  {providerQuality ? (
                    <Text style={styles.providerHealthFooter}>
                      Qualità{' '}
                      {providerDataQualityLabel(providerQuality.status)}
                      {' · '}
                      {providerQuality.finalFixtureCount}/
                      {providerQuality.fixtureCount} partite definitive
                      {' · '}
                      {providerQuality.finalScoreCount}/
                      {providerQuality.scoreCount} voti definitivi
                    </Text>
                  ) : null}
                  {providerIncidents ? (
                    <Text style={styles.providerHealthFooter}>
                      Incidenti attivi {providerIncidents.activeCount}
                      {' · '}
                      {providerIncidents.criticalCount} critici
                      {' · '}
                      {providerIncidents.resolvedLast24h} risolti nelle ultime 24h
                    </Text>
                  ) : null}
                  {providerIncidents?.incidents[0] ? (
                    <Text style={styles.providerIncidentSummary}>
                      {providerIncidents.incidents[0].summary}
                    </Text>
                  ) : null}
                  {providerRecovery ? (
                    <>
                      <Text style={styles.providerHealthFooter}>
                        Recuperi in coda {providerRecovery.pendingCount}
                        {' · '}
                        in esecuzione {providerRecovery.runningCount}
                        {' · '}
                        {providerRecovery.completedLast24h} completati nelle ultime 24h
                      </Text>
                      {providerRecovery.watchdogActive ? (
                        <Text style={styles.providerRecoveryWatchdog}>
                          WATCHDOG CODA ATTIVO · {providerRecovery.staleRunningCount}{' '}
                          BLOCCATI · {providerRecovery.timedOutLast24h} TIMEOUT 24H
                        </Text>
                      ) : null}
                      {providerRecovery.workerHeartbeatActive ? (
                        <Text style={styles.providerRecoveryWatchdog}>
                          HEARTBEAT WORKER ATTIVO
                          {providerRecovery.latestProgress
                            ? ` · ${providerProgressLabel(providerRecovery.latestProgress.phase)} · ${formatProviderProgress(providerRecovery.latestProgress.current, providerRecovery.latestProgress.total, providerRecovery.latestProgress.recordsProcessed)}`
                            : ' · IN ATTESA DI UN RECUPERO'}
                        </Text>
                      ) : null}
                      {providerRetry?.automaticRetryActive ? (
                        <Text style={styles.providerRecoveryWatchdog}>
                          RETRY AUTOMATICO ATTIVO · {providerRetry.scheduledCount}{' '}
                          PROGRAMMATI · {providerRetry.exhaustedOpenCount} ESAURITI
                          {providerRetry.nextRetryAt
                            ? ` · PROSSIMO ${formatOptionalDateTime(providerRetry.nextRetryAt)}`
                            : ''}
                        </Text>
                      ) : null}
                      {providerFencing?.workerFencingActive ? (
                        <Text style={styles.providerRecoveryWatchdog}>
                          FENCING WORKER ATTIVO · {providerFencing.activeLeaseCount}{' '}
                          LEASE ATTIVE · {providerFencing.expiredLeaseCount} SCADUTE
                        </Text>
                      ) : null}
                      {providerContracts?.runtimeValidationActive &&
                      providerContracts.databaseValidationActive ? (
                        <>
                          <Text style={styles.providerRecoveryWatchdog}>
                            CONTRATTI PAYLOAD ATTIVI ·{' '}
                            {providerContracts.violationsLast24h} QUARANTENE 24H ·{' '}
                            PAYLOAD GREZZO NON SALVATO
                          </Text>
                          {providerContracts.latest &&
                          providerContracts.violationsLast24h > 0 ? (
                            <Text style={styles.providerCircuitBreakerSummary}>
                              {providerContracts.latest.summary}
                            </Text>
                          ) : null}
                        </>
                      ) : null}
                      {providerDelivery?.deliveryValidationActive &&
                      providerDelivery.completionGateActive ? (
                        <>
                          <Text style={styles.providerRecoveryWatchdog}>
                            CONSEGNA PROVIDER CERTIFICATA ·{' '}
                            {providerDelivery.certifiedLast24h} COMPLETE 24H ·{' '}
                            {providerDelivery.rejectedLast24h} RESPINTE ·{' '}
                            {providerDelivery.collectingCount} IN CORSO
                          </Text>
                          {providerDelivery.latest?.status === 'rejected' ? (
                            <Text style={styles.providerCircuitBreakerSummary}>
                              {providerDelivery.latest.summary}
                            </Text>
                          ) : null}
                        </>
                      ) : null}
                      {providerPublication?.atomicStagingActive &&
                      providerPublication.singleCommitPublicationActive ? (
                        <>
                          <Text style={styles.providerRecoveryWatchdog}>
                            PUBBLICAZIONE ATOMICA ATTIVA ·{' '}
                            {providerPublication.publishedLast24h} PUBBLICATE 24H ·{' '}
                            {providerPublication.discardedLast24h} SCARTATE ·{' '}
                            {providerPublication.collectingCount} IN STAGING
                          </Text>
                          {providerPublication.latest?.status === 'discarded' ? (
                            <Text style={styles.providerCircuitBreakerSummary}>
                              {providerPublication.latest.summary}
                            </Text>
                          ) : null}
                        </>
                      ) : null}
                      {providerScope?.semanticScopeActive &&
                      providerScope.operationBindingActive ? (
                        <>
                          <Text style={styles.providerRecoveryWatchdog}>
                            SCOPE PROVIDER VINCOLATO ·{' '}
                            {providerScope.certifiedLast24h} CERTIFICATI 24H ·{' '}
                            {providerScope.rejectedLast24h} RESPINTI ·{' '}
                            {providerScope.collectingCount} IN VERIFICA
                          </Text>
                          {providerScope.latest?.status === 'rejected' ? (
                            <Text style={styles.providerCircuitBreakerSummary}>
                              {providerScope.latest.summary}
                            </Text>
                          ) : null}
                        </>
                      ) : null}
                      {providerWatermark?.monotonicOrderingActive &&
                      providerWatermark.stalePublicationBlocked ? (
                        <>
                          <Text style={styles.providerRecoveryWatchdog}>
                            ORDINE TEMPORALE PROTETTO ·{' '}
                            {providerWatermark.advancedLast24h} AVANZAMENTI 24H ·{' '}
                            {providerWatermark.staleRejectedLast24h} REGRESSIONI BLOCCATE ·{' '}
                            {providerWatermark.activeWatermarkCount} SCOPE TRACCIATI
                          </Text>
                          {providerWatermark.latest?.eventType === 'stale_rejected' ? (
                            <Text style={styles.providerCircuitBreakerSummary}>
                              Una pubblicazione iniziata prima è stata scartata perché
                              superata da dati già pubblicati più recenti.
                            </Text>
                          ) : null}
                        </>
                      ) : null}
                      {providerCatalog?.authoritativeSnapshotActive &&
                      providerCatalog.exactRoleReplacementActive ? (
                        <>
                          <Text style={styles.providerRecoveryWatchdog}>
                            CATALOGO CALCIATORI RICONCILIATO ·{' '}
                            {providerCatalog.appliedLast24h} APPLICATI 24H ·{' '}
                            {providerCatalog.deactivatedPlayersLast24h} RITIRATI ·{' '}
                            {providerCatalog.removedRolesLast24h} RUOLI CORRETTI
                          </Text>
                          {providerCatalog.latest?.status === 'superseded' ? (
                            <Text style={styles.providerCircuitBreakerSummary}>
                              Una fotografia di una stagione storica è stata certificata
                              ma non ha sostituito il catalogo corrente.
                            </Text>
                          ) : providerCatalog.rosteredRetiredTotal > 0 ? (
                            <Text style={styles.providerCircuitBreakerSummary}>
                              {providerCatalog.rosteredRetiredTotal} calciatori non più
                              presenti nel catalogo restano conservati nelle rose attive.
                            </Text>
                          ) : null}
                        </>
                      ) : null}
                      {providerFixtureLifecycle?.monotonicFixtureLifecycleActive &&
                      providerFixtureLifecycle.finalToNonFinalRegressionBlocked ? (
                        <>
                          <Text style={styles.providerRecoveryWatchdog}>
                            CICLO PARTITE PROTETTO ·{' '}
                            {providerFixtureLifecycle.appliedLast24h} APPLICATI 24H ·{' '}
                            {providerFixtureLifecycle.advancedFixturesLast24h} AVANZAMENTI ·{' '}
                            {providerFixtureLifecycle.finalCorrectionsLast24h} CORREZIONI FINALI
                          </Text>
                          {providerFixtureLifecycle.head?.currentState === 'final' ? (
                            <Text style={styles.providerCircuitBreakerSummary}>
                              Una partita finale non può tornare provvisoria né perdere gol,
                              squadre o giornata già certificate.
                            </Text>
                          ) : null}
                        </>
                      ) : null}
                      {providerFixtureScores?.authoritativeFixtureSnapshotActive &&
                      providerFixtureScores.missingFinalScoresSoftRetired ? (
                        <>
                          <Text style={styles.providerRecoveryWatchdog}>
                            VOTI PARTITA RICONCILIATI ·{' '}
                            {providerFixtureScores.appliedLast24h} APPLICATI 24H ·{' '}
                            {providerFixtureScores.retiredScoresLast24h} RITIRATI ·{' '}
                            {providerFixtureScores.finalAppliedLast24h} FINALI
                          </Text>
                          {providerFixtureScores.latest?.retiredScoreCount ? (
                            <Text style={styles.providerCircuitBreakerSummary}>
                              {providerFixtureScores.latest.retiredScoreCount} voti non più
                              presenti nella fotografia finale sono stati neutralizzati senza
                              cancellare lo storico provider.
                            </Text>
                          ) : providerFixtureScores.latest &&
                            !providerFixtureScores.latest.isFinal ? (
                            <Text style={styles.providerCircuitBreakerSummary}>
                              La fotografia più recente è ancora provvisoria: nessun voto
                              precedente è stato ritirato.
                            </Text>
                          ) : null}
                        </>
                      ) : null}
                      {providerFixtureScoreCoherence?.causalFixtureScoreBindingActive ? (
                        <>
                          <Text style={styles.providerRecoveryWatchdog}>
                            COERENZA PARTITA/VOTI PROTETTA ·{' '}
                            {providerFixtureScoreCoherence.alignedCount} ALLINEATE ·{' '}
                            {providerFixtureScoreCoherence.staleCount} SUPERATE ·{' '}
                            {providerFixtureScoreCoherence.finalMissingCount} FINALI DA VERIFICARE
                          </Text>
                          {providerFixtureScoreCoherence.staleCount > 0 ? (
                            <Text style={styles.providerCircuitBreakerSummary}>
                              Una partita è avanzata o è stata corretta dopo l’ultima fotografia
                              voti. I valori restano conservati, ma il Centro Operativo li segnala
                              come non più appartenenti alla generazione corrente.
                            </Text>
                          ) : providerFixtureScoreCoherence.finalMissingCount > 0 ? (
                            <Text style={styles.providerCircuitBreakerSummary}>
                              Alcune partite finali non hanno ancora una fotografia voti allineata
                              alla loro generazione certificata.
                            </Text>
                          ) : (
                            <Text style={styles.providerCircuitBreakerSummary}>
                              Ogni fotografia voti appartiene alla generazione corrente della
                              relativa partita provider.
                            </Text>
                          )}
                        </>
                      ) : null}
                      {providerScoreConsumptionGate?.officialResultConsumptionGateActive ? (
                        <>
                          <Text style={styles.providerRecoveryWatchdog}>
                            CONSUMO VOTI CERTIFICATO ·{' '}
                            {providerScoreConsumptionGate.trustedHeadCount} UTILIZZABILI ·{' '}
                            {providerScoreConsumptionGate.blockedHeadCount} BLOCCATI ·{' '}
                            {providerScoreConsumptionGate.officialFixtureRiskCount} UFFICIALI DA VERIFICARE
                          </Text>
                          {providerScoreConsumptionGate.blockedHeadCount > 0 ? (
                            <Text style={styles.providerCircuitBreakerSummary}>
                              {providerScoreConsumptionGate.blockedScoreCount} voti restano nello
                              storico ma non possono entrare in sostituzioni, proiezioni o nuovi
                              risultati ufficiali finché non tornano allineati.
                            </Text>
                          ) : (
                            <Text style={styles.providerCircuitBreakerSummary}>
                              Il motore sportivo utilizza esclusivamente fotografie voti correnti
                              e causalmente allineate alla partita provider.
                            </Text>
                          )}
                        </>
                      ) : null}
                      {providerOfficialResultLineage?.officializationCommitBarrierActive ? (
                        <>
                          <Text style={styles.providerRecoveryWatchdog}>
                            LINEAGE UFFICIALE CERTIFICATA ·{' '}
                            {providerOfficialResultLineage.certifiedFixtureCount} COMPLETE ·{' '}
                            {providerOfficialResultLineage.assemblingFixtureCount} IN COMMIT ·{' '}
                            {providerOfficialResultLineage.invalidFixtureCount} NON COERENTI
                          </Text>
                          {providerOfficialResultLineage.invalidFixtureCount > 0 ? (
                            <Text style={styles.providerCircuitBreakerSummary}>
                              Una o più partite ufficiali non risultano collegate in modo coerente
                              alla proiezione, alla officialization run o alla correzione che le ha
                              generate. L’impatto viene segnalato senza modificare i risultati.
                            </Text>
                          ) : providerOfficialResultLineage.assemblingFixtureCount > 0 ? (
                            <Text style={styles.providerCircuitBreakerSummary}>
                              Il collegamento ufficiale è ancora nella fase atomica di commit. Il
                              sistema sospende la valutazione d’impatto per evitare falsi allarmi.
                            </Text>
                          ) : (
                            <Text style={styles.providerCircuitBreakerSummary}>
                              Ogni risultato ufficiale è collegato alla propria proiezione e alla
                              revisione di ufficializzazione completa; le correzioni conservano
                              anche la sorgente causale certificata.
                            </Text>
                          )}
                        </>
                      ) : null}
                      {providerOfficialResultRemediationCompletion?.causalCompletionCertificateActive ? (
                        <>
                          <Text style={styles.providerRecoveryWatchdog}>
                            CHIUSURA REMEDIATION CERTIFICATA ·{' '}
                            {providerOfficialResultRemediationCompletion.certifiedCount} CHIUSE ·{' '}
                            {providerOfficialResultRemediationCompletion.pendingCount} IN CORSO ·{' '}
                            {providerOfficialResultRemediationCompletion.invalidCount} NON CERTIFICATE
                          </Text>
                          {providerOfficialResultRemediationCompletion.invalidCount > 0 ||
                          providerOfficialResultRemediationCompletion.uncertifiedResolvedCount > 0 ? (
                            <Text style={styles.providerCircuitBreakerSummary}>
                              Una chiusura non possiede ancora la prova causale completa tra
                              correction run, officialization run e lineage certificata. Il
                              risultato non viene modificato automaticamente e il caso resta
                              segnalato alla Direzione.
                            </Text>
                          ) : providerOfficialResultRemediationCompletion.pendingCount > 0 ? (
                            <Text style={styles.providerCircuitBreakerSummary}>
                              Le remediation aperte o in correzione restano in attesa della nuova
                              ufficializzazione certificata.
                            </Text>
                          ) : (
                            <Text style={styles.providerCircuitBreakerSummary}>
                              Ogni remediation risolta distingue il recupero automatico dalla
                              correzione manuale e conserva la prova della lineage che ha chiuso
                              l’impatto provider.
                            </Text>
                          )}
                        </>
                      ) : null}
                      {providerMatchdayProgressionGate?.causalProgressionBarrierActive ? (
                        <>
                          <Text style={styles.providerRecoveryWatchdog}>
                            PROGRESSIONE GIORNATA PROTETTA ·{' '}
                            {providerMatchdayProgressionGate.clearMatchdayCount} CERTIFICATE ·{' '}
                            {providerMatchdayProgressionGate.blockedMatchdayCount} BLOCCATE ·{' '}
                            {providerMatchdayProgressionGate.affectedMatchdayCount} DA RIVEDERE
                          </Text>
                          {providerMatchdayProgressionGate.unsafeProgressionCount > 0 ? (
                            <Text style={styles.providerCircuitBreakerSummary}>
                              Una progressione già registrata dipende da risultati provider non
                              più causalmente affidabili. Calendario e classifica non vengono
                              arretrati automaticamente; le giornate successive restano bloccate
                              finché la catena non torna certificata.
                            </Text>
                          ) : providerMatchdayProgressionGate.blockedMatchdayCount > 0 ? (
                            <Text style={styles.providerCircuitBreakerSummary}>
                              Una giornata non può avanzare finché impatto, lineage e chiusura di
                              ogni eventuale remediation non risultano certificati.
                            </Text>
                          ) : (
                            <Text style={styles.providerCircuitBreakerSummary}>
                              Ogni avanzamento utilizza la stessa officialization run corrente e
                              una catena provider certificata anche per le giornate precedenti.
                            </Text>
                          )}
                        </>
                      ) : null}
                      {providerSeasonCompletionGate?.causalSeasonCompletionBarrierActive ? (
                        <>
                          <Text style={styles.providerRecoveryWatchdog}>
                            CHIUSURA STAGIONE PROTETTA ·{' '}
                            {providerSeasonCompletionGate.clearMatchdayCount}/
                            {providerSeasonCompletionGate.matchdayCount} GIORNATE CERTIFICATE
                          </Text>
                          {providerSeasonCompletionGate.completionAffected ? (
                            <Text style={styles.providerCircuitBreakerSummary}>
                              La stagione risulta già conclusa, ma una progressione precedente non
                              è più causalmente affidabile. Classifica, campione e storico non
                              vengono modificati automaticamente; il caso resta segnalato alla
                              Direzione.
                            </Text>
                          ) : providerSeasonCompletionGate.gateStatus === 'blocked' ? (
                            <Text style={styles.providerCircuitBreakerSummary}>
                              La proclamazione del campione resta bloccata finché tutte le giornate
                              non possiedono la progressione corrente certificata dal provider.
                            </Text>
                          ) : (
                            <Text style={styles.providerCircuitBreakerSummary}>
                              L’intera catena delle progressioni giornata è certificata e il commit
                              della stagione usa un lock comune contro cambi concorrenti.
                            </Text>
                          )}
                        </>
                      ) : null}
                      {providerOfficialResultImpact?.preciseOfficialResultLineageActive ? (
                        <>
                          <Text style={styles.providerRecoveryWatchdog}>
                            IMPATTO RISULTATI CERTIFICATO ·{' '}
                            {providerOfficialResultImpact.clearFixtureCount} COERENTI ·{' '}
                            {providerOfficialResultImpact.affectedFixtureCount} DA RIVEDERE ·{' '}
                            {providerOfficialResultImpact.inCorrectionFixtureCount} IN CORREZIONE
                          </Text>
                          {providerOfficialResultImpact.affectedFixtureCount > 0 ? (
                            <Text style={styles.providerCircuitBreakerSummary}>
                              La proiezione usata per uno o più risultati ufficiali non coincide
                              più con gli input correnti protetti dal provider. I risultati non
                              vengono modificati automaticamente e restano disponibili per il
                              percorso di correzione certificato.
                            </Text>
                          ) : (
                            <Text style={styles.providerCircuitBreakerSummary}>
                              Ogni risultato ufficiale utilizza ancora le stesse risoluzioni
                              certificate della relativa proiezione.
                            </Text>
                          )}
                        </>
                      ) : null}
                      {providerOfficialResultRemediation?.raceSafeRemediationActive ? (
                        <>
                          <Text style={styles.providerRecoveryWatchdog}>
                            REMEDIATION RISULTATI PROTETTA ·{' '}
                            {providerOfficialResultRemediation.openCount} DA PRENDERE IN CARICO ·{' '}
                            {providerOfficialResultRemediation.inCorrectionCount} IN CORREZIONE ·{' '}
                            {providerOfficialResultRemediation.resolvedCount} RISOLTI
                          </Text>
                          {providerOfficialResultRemediation.openCount > 0 ? (
                            <Text style={styles.providerCircuitBreakerSummary}>
                              La riapertura viene collegata alla generazione d’impatto ancora
                              corrente. Una valutazione superata viene respinta prima di modificare
                              il risultato ufficiale.
                            </Text>
                          ) : providerOfficialResultRemediation.uncertifiedCorrectionCount > 0 ? (
                            <Text style={styles.providerCircuitBreakerSummary}>
                              {providerOfficialResultRemediation.uncertifiedCorrectionCount}{' '}
                              correzioni precedenti non risultano avviate dalla presa in carico
                              causale e restano evidenziate per audit.
                            </Text>
                          ) : (
                            <Text style={styles.providerCircuitBreakerSummary}>
                              Ogni correzione provider aperta è collegata alla valutazione causale
                              mostrata nel Centro Risultati.
                            </Text>
                          )}
                        </>
                      ) : null}
                      {providerVerification?.outcomeVerificationActive ? (
                        <>
                          <Text style={styles.providerRecoveryWatchdog}>
                            VERIFICA EFFICACIA ATTIVA ·{' '}
                            {providerVerification.verifiedLast24h} VERIFICATI 24H ·{' '}
                            {providerVerification.activeRetryCount} DA RIPROVARE ·{' '}
                            {providerVerification.exhaustedOpenCount} ESAURITI
                          </Text>
                          {providerVerification.latest &&
                          providerVerification.latest.outcome !== 'verified' ? (
                            <Text style={styles.providerCircuitBreakerSummary}>
                              {providerVerification.latest.summary}
                            </Text>
                          ) : null}
                        </>
                      ) : null}
                      {providerCircuit?.blocked &&
                      providerCircuit.latestOpen ? (
                        <>
                          <Text style={styles.providerCircuitBreakerAlert}>
                            CIRCUIT BREAKER APERTO · RETRY ESAURITI
                          </Text>
                          <Text style={styles.providerCircuitBreakerSummary}>
                            {providerCircuit.latestOpen.summary}
                          </Text>
                        </>
                      ) : null}
                    </>
                  ) : null}
                  {operations.circuitBreakerError ? (
                    <Text style={styles.providerRecoveryError}>
                      {operations.circuitBreakerError}
                    </Text>
                  ) : null}
                  {operations.circuitBreakerOutcome ? (
                    <Text style={styles.providerRecoverySuccess}>
                      Circuit breaker rilasciato · revisione{' '}
                      {operations.circuitBreakerOutcome.revision}
                    </Text>
                  ) : null}
                  {providerCircuit?.blocked && providerCircuit.latestOpen ? (
                    <Pressable
                      disabled={operations.circuitBreakerLoading}
                      onPress={confirmCircuitBreakerRelease}
                      style={[
                        styles.providerCircuitBreakerButton,
                        operations.circuitBreakerLoading && styles.disabledButton,
                      ]}
                    >
                      {operations.circuitBreakerLoading ? (
                        <ActivityIndicator color={colors.navy} size="small" />
                      ) : (
                        <Text style={styles.providerCircuitBreakerButtonText}>
                          RIAPRI RECUPERI PROVIDER
                        </Text>
                      )}
                    </Pressable>
                  ) : null}
                  {operations.recoveryError ? (
                    <Text style={styles.providerRecoveryError}>
                      {operations.recoveryError}
                    </Text>
                  ) : null}
                  {operations.recoveryOutcome ? (
                    <Text style={styles.providerRecoverySuccess}>
                      Recupero certificato in coda · revisione{' '}
                      {operations.recoveryOutcome.revision}
                    </Text>
                  ) : null}
                  {providerRecovery?.canRequest &&
                  providerRecovery.recoverableIncident ? (
                    <Pressable
                      disabled={operations.recoveryLoading}
                      onPress={confirmProviderRecovery}
                      style={[
                        styles.providerRecoveryButton,
                        operations.recoveryLoading && styles.disabledButton,
                      ]}
                    >
                      {operations.recoveryLoading ? (
                        <ActivityIndicator color={colors.lime} size="small" />
                      ) : (
                        <Text style={styles.providerRecoveryButtonText}>
                          ACCODA RECUPERO PROVIDER
                        </Text>
                      )}
                    </Pressable>
                  ) : providerRecovery &&
                    (providerRecovery.pendingCount > 0 ||
                      providerRecovery.runningCount > 0) ? (
                    <Text style={styles.providerRecoveryPending}>
                      RECUPERO CERTIFICATO · IN ATTESA DEL WORKER SERVER
                    </Text>
                  ) : null}
                </View>
              ) : null}

              <Pressable
                onPress={() => onNavigate('standings')}
                style={[
                  styles.resultButton,
                  focus.canFinalize && styles.resultButtonReady,
                ]}
              >
                <Text
                  style={[
                    styles.resultButtonText,
                    focus.canFinalize && styles.resultButtonTextReady,
                  ]}
                >
                  {focus.canFinalize
                    ? 'VAI A UFFICIALIZZARE'
                    : 'APRI RISULTATI E CLASSIFICA'}
                </Text>
              </Pressable>
            </View>
          ) : (
            <EmptyCard
              body="Il monitor dei risultati si attiverà appena esisterà il calendario."
              title="Nessuna giornata da controllare"
            />
          )}

          <Text style={styles.sectionTitle}>Azioni rapide</Text>
          <View style={styles.quickGrid}>
            <QuickAction
              label="Formazioni"
              onPress={() => onNavigate('lineup')}
              symbol="11"
            />
            <QuickAction
              label="Live"
              onPress={() => onNavigate('live')}
              symbol="●"
            />
            <QuickAction
              label="Calendario"
              onPress={() => onNavigate('calendar')}
              symbol="↻"
            />
            <QuickAction
              label="Risultati"
              onPress={() => onNavigate('standings')}
              symbol="≡"
            />
          </View>

          <Text style={styles.footerNote}>
            Aggiornato {formatDateTime(center.generatedAt)} · accesso riservato
            alla Direzione
          </Text>
        </>
      ) : null}
    </ScrollView>
  );
}

function Metric({ label, value }: { label: string; value: string }) {
  return (
    <View style={styles.metric}>
      <Text style={styles.metricValue}>{value}</Text>
      <Text style={styles.metricLabel}>{label}</Text>
    </View>
  );
}

function ProgressBar({ total, value }: { total: number; value: number }) {
  const percentage =
    total > 0 ? Math.min(100, Math.max(0, (value / total) * 100)) : 0;
  const width = `${percentage}%` as `${number}%`;
  return (
    <View style={styles.progressTrack}>
      <View style={[styles.progressValue, { width }]} />
    </View>
  );
}

function EmptyCard({ body, title }: { body: string; title: string }) {
  return (
    <View style={styles.emptyCard}>
      <Text style={styles.emptyTitle}>{title}</Text>
      <Text style={styles.emptyBody}>{body}</Text>
    </View>
  );
}

function QuickAction({
  label,
  onPress,
  symbol,
}: {
  label: string;
  onPress: () => void;
  symbol: string;
}) {
  return (
    <Pressable onPress={onPress} style={styles.quickAction}>
      <Text style={styles.quickSymbol}>{symbol}</Text>
      <Text style={styles.quickLabel}>{label}</Text>
    </Pressable>
  );
}

function buildPriorities(center: LeagueOperationsCenter | null): Priority[] {
  if (!center) {
    return [];
  }

  const priorities: Priority[] = [];
  const lineup = center.nextLineupMatchday;
  const focus = center.focusMatchday;
  const providerSync = center.providerSync;

  if (providerSync?.status === 'attention') {
    const quality = providerSync.dataQuality;
    priorities.push({
      key: 'provider-sync-attention',
      tone: 'urgent',
      label: 'DATI DA CONTROLLARE',
      title:
        quality?.status === 'attention'
          ? 'Qualità dei dati provider da verificare'
          : 'Sincronizzazione provider da verificare',
      detail:
        providerSync.incidentCenter?.incidents[0]?.summary ??
        (quality?.status === 'attention'
          ? `${quality.anomalyCount} anomalie · ${
              quality.stale ? 'dati non aggiornati' : 'copertura incompleta'
            }.`
          : `${providerSync.stuckRunCount} run bloccati · ${providerSync.failedLast24h} errori nelle ultime 24 ore.`),
    });
  }

  if (!center.competitionStartedAt) {
    priorities.push({
      key: 'start',
      tone: 'action',
      label: 'DA FARE',
      title: 'Avvia la competizione',
      detail: 'Completa la checklist della Direzione e dai il via ufficiale.',
      screen: 'leagueManagement',
    });
  }

  if (lineup && lineup.draftCount + lineup.missingCount > 0) {
    const lateCount = lineup.draftCount + lineup.missingCount;
    const urgent = hoursUntil(lineup.locksAt) <= 24;
    priorities.push({
      key: 'lineups',
      tone: urgent ? 'urgent' : 'action',
      label: urgent ? 'URGENTE' : 'DA SEGUIRE',
      title: `${lateCount} formazion${lateCount === 1 ? 'e' : 'i'} non consegnat${lateCount === 1 ? 'a' : 'e'}`,
      detail: `La giornata ${lineup.number} chiude ${formatCountdown(lineup.locksAt).toLowerCase()}.`,
      screen: 'lineup',
    });
  } else if (lineup) {
    priorities.push({
      key: 'lineups-ready',
      tone: 'done',
      label: 'COMPLETO',
      title: 'Tutte le formazioni sono consegnate',
      detail: `La giornata ${lineup.number} è pronta per il calcio d’inizio.`,
    });
  }

  if (focus?.canFinalize) {
    priorities.push({
      key: 'finalize',
      tone: 'urgent',
      label: 'VERDETTO PRONTO',
      title: `Ufficializza la giornata ${focus.number}`,
      detail: 'Tutti i tabellini sono definitivi e la classifica può essere aggiornata.',
      screen: 'standings',
    });
  } else if (focus?.status === 'live' || focus?.status === 'pending') {
    priorities.push({
      key: 'provider',
      tone: 'waiting',
      label: 'IN ATTESA',
      title: 'Controlla la copertura dei voti',
      detail:
        focus.scheduleSource === 'provider'
          ? `${focus.providerFinalFixtureCount}/${focus.providerFixtureCount} partite reali concluse.`
          : 'Le date della giornata sono ancora stimate.',
      screen: 'live',
    });
  } else if (focus?.status === 'official') {
    priorities.push({
      key: 'official',
      tone: 'done',
      label: 'CHIUSA',
      title: `Giornata ${focus.number} ufficiale`,
      detail: 'Risultati acquisiti e classifica aggiornata.',
      screen: 'standings',
    });
  }

  if (priorities.length === 0) {
    priorities.push({
      key: 'waiting-calendar',
      tone: 'waiting',
      label: 'IN ATTESA',
      title: 'Prepara il calendario',
      detail: 'Il Centro Operativo si riempirà con la prima giornata.',
      screen: 'calendar',
    });
  }

  return priorities;
}

function matchdayStatusLabel(status: LeagueOperationMatchdayStatus) {
  const labels: Record<LeagueOperationMatchdayStatus, string> = {
    upcoming: 'IN PREPARAZIONE',
    live: 'LIVE',
    pending: 'IN CALCOLO',
    ready: 'DA UFFICIALIZZARE',
    official: 'UFFICIALE',
  };
  return labels[status];
}

function focusStatusDescription(status: LeagueOperationMatchdayStatus) {
  const labels: Record<LeagueOperationMatchdayStatus, string> = {
    upcoming: 'Le formazioni sono aperte. Controlla chi deve ancora consegnare.',
    live: 'La giornata è in corso e i voti stanno arrivando dal provider.',
    pending: 'Il turno è terminato, ma non tutti i tabellini sono definitivi.',
    ready: 'I risultati sono completi: manca soltanto il verdetto del Presidente.',
    official: 'Risultati acquisiti e classifica aggiornata senza operazioni pendenti.',
  };
  return labels[status];
}

function lineupStatusLabel(status: LeagueOperationLineupStatus) {
  const labels: Record<LeagueOperationLineupStatus, string> = {
    manual: 'Consegnata',
    carried: 'Recuperata',
    draft: 'Solo bozza',
    missing: 'Mancante',
  };
  return labels[status];
}

function lineupStatusSymbol(status: LeagueOperationLineupStatus) {
  const labels: Record<LeagueOperationLineupStatus, string> = {
    manual: '✓',
    carried: '↻',
    draft: '…',
    missing: '!',
  };
  return labels[status];
}

function providerDataQualityLabel(
  status: 'healthy' | 'attention' | 'idle',
) {
  if (status === 'attention') {
    return 'DA VERIFICARE';
  }
  if (status === 'healthy') {
    return 'CERTIFICATA';
  }
  return 'IN ATTESA';
}

function providerSyncStatusLabel(
  status: 'healthy' | 'attention' | 'idle',
) {
  if (status === 'attention') {
    return 'RICHIEDE CONTROLLO';
  }
  if (status === 'healthy') {
    return 'SINCRONIZZAZIONE REGOLARE';
  }
  return 'IN ATTESA DEL PRIMO SYNC';
}


function providerProgressLabel(phase: string) {
  const labels: Record<string, string> = {
    starting: 'AVVIO',
    'season-players': 'ROSE STAGIONALI',
    fixtures: 'CALENDARIO',
    'fixture-players': 'VOTI PARTITA',
    finalizing: 'CERTIFICAZIONE',
    completed: 'COMPLETATO',
    failed: 'ERRORE',
  };
  return labels[phase] ?? phase.replace(/[-_]+/g, ' ').toUpperCase();
}

function formatProviderProgress(
  current: number,
  total: number | null,
  recordsProcessed: number,
) {
  if (total !== null && total > 0) {
    return `${Math.min(current, total)}/${total} · ${recordsProcessed} RECORD`;
  }
  return `${recordsProcessed} RECORD`;
}

function formatOptionalDateTime(value: string | null) {
  return value ? formatDateTime(value) : 'non ancora disponibile';
}

function formatDateTime(value: string) {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) {
    return '—';
  }
  return new Intl.DateTimeFormat('it-IT', {
    weekday: 'short',
    day: '2-digit',
    month: 'short',
    hour: '2-digit',
    minute: '2-digit',
  }).format(date);
}

function formatTime(value: string) {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) {
    return '—';
  }
  return new Intl.DateTimeFormat('it-IT', {
    hour: '2-digit',
    minute: '2-digit',
  }).format(date);
}

function hoursUntil(value: string) {
  const timestamp = new Date(value).getTime();
  if (!Number.isFinite(timestamp)) {
    return Number.POSITIVE_INFINITY;
  }
  return Math.max(0, (timestamp - Date.now()) / (60 * 60 * 1000));
}

function formatCountdown(value: string) {
  const timestamp = new Date(value).getTime();
  if (!Number.isFinite(timestamp)) {
    return 'SCADENZA DA VERIFICARE';
  }
  const milliseconds = timestamp - Date.now();
  if (milliseconds <= 0) {
    return 'SCADUTA';
  }
  const totalMinutes = Math.ceil(milliseconds / (60 * 1000));
  const days = Math.floor(totalMinutes / (24 * 60));
  const hours = Math.floor((totalMinutes % (24 * 60)) / 60);
  const minutes = totalMinutes % 60;
  if (days > 0) {
    return `TRA ${days}G ${hours}H`;
  }
  if (hours > 0) {
    return `TRA ${hours}H ${minutes}M`;
  }
  return `TRA ${minutes} MIN`;
}

const styles = StyleSheet.create({
  screen: {
    flex: 1,
    backgroundColor: colors.canvas,
  },
  content: {
    paddingHorizontal: 20,
    paddingTop: 14,
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
    fontSize: 20,
    fontWeight: '900',
    marginBottom: 20,
  },
  header: {
    minHeight: 56,
    flexDirection: 'row',
    alignItems: 'center',
    marginBottom: 18,
  },
  backButton: {
    width: 42,
    height: 42,
    borderRadius: 16,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.white,
  },
  backText: {
    color: colors.navy,
    fontSize: 32,
    lineHeight: 34,
    marginTop: -2,
  },
  headerCopy: {
    flex: 1,
    marginHorizontal: 12,
  },
  eyebrow: {
    color: colors.muted,
    fontSize: 9,
    fontWeight: '900',
    letterSpacing: 1.1,
  },
  title: {
    color: colors.navy,
    fontSize: 22,
    fontWeight: '900',
    marginTop: 3,
  },
  reloadButton: {
    width: 42,
    height: 42,
    borderRadius: 16,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.navy,
  },
  reloadButtonDisabled: {
    opacity: 0.72,
  },
  reloadText: {
    color: colors.lime,
    fontSize: 20,
    fontWeight: '900',
  },
  heroCard: {
    borderRadius: radius.xl,
    padding: 22,
    backgroundColor: colors.navy,
    ...shadow,
  },
  heroTop: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'flex-start',
  },
  heroEyebrow: {
    color: colors.lime,
    fontSize: 9,
    fontWeight: '900',
    letterSpacing: 1.2,
  },
  heroTitle: {
    color: colors.white,
    fontSize: 28,
    fontWeight: '900',
    marginTop: 6,
  },
  heroBody: {
    color: colors.mutedLight,
    fontSize: 12,
    lineHeight: 18,
    marginTop: 12,
    maxWidth: 310,
  },
  statusPill: {
    borderRadius: 999,
    paddingHorizontal: 10,
    paddingVertical: 7,
    backgroundColor: colors.navyLine,
  },
  statusPillLive: {
    backgroundColor: colors.danger,
  },
  statusPillReady: {
    backgroundColor: colors.lime,
  },
  statusPillText: {
    color: colors.white,
    fontSize: 8,
    fontWeight: '900',
  },
  deadlineRow: {
    marginTop: 20,
    paddingTop: 16,
    borderTopWidth: 1,
    borderTopColor: colors.navyLine,
  },
  deadlineLabel: {
    color: colors.mutedLight,
    fontSize: 8,
    fontWeight: '900',
    letterSpacing: 1,
  },
  deadlineValue: {
    color: colors.white,
    fontSize: 14,
    fontWeight: '800',
    marginTop: 5,
  },
  deadlineCountdown: {
    color: colors.lime,
    fontSize: 11,
    fontWeight: '900',
    marginTop: 5,
  },
  sectionHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    marginTop: 26,
    marginBottom: 12,
  },
  sectionTitle: {
    color: colors.navy,
    fontSize: 17,
    fontWeight: '900',
    marginTop: 26,
    marginBottom: 12,
  },
  sectionMeta: {
    color: colors.muted,
    fontSize: 8,
    fontWeight: '900',
    letterSpacing: 0.8,
  },
  priorityList: {
    gap: 8,
  },
  priorityCard: {
    minHeight: 86,
    borderRadius: radius.lg,
    padding: 15,
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: colors.white,
  },
  priorityCardUrgent: {
    backgroundColor: '#FFF1EF',
  },
  priorityCardDone: {
    backgroundColor: colors.limeSoft,
  },
  priorityMarker: {
    width: 5,
    height: 48,
    borderRadius: 4,
    backgroundColor: colors.mutedLight,
  },
  priorityMarkerUrgent: {
    backgroundColor: colors.danger,
  },
  priorityMarkerDone: {
    backgroundColor: colors.navy,
  },
  priorityCopy: {
    flex: 1,
    marginLeft: 14,
  },
  priorityLabel: {
    color: colors.muted,
    fontSize: 8,
    fontWeight: '900',
    letterSpacing: 0.8,
  },
  priorityTitle: {
    color: colors.navy,
    fontSize: 14,
    fontWeight: '900',
    marginTop: 4,
  },
  priorityDetail: {
    color: colors.muted,
    fontSize: 10,
    lineHeight: 15,
    marginTop: 4,
  },
  priorityArrow: {
    color: colors.navy,
    fontSize: 20,
    marginLeft: 8,
  },
  lineupCard: {
    borderRadius: radius.lg,
    padding: 14,
    backgroundColor: colors.white,
    ...shadow,
  },
  statsGrid: {
    flexDirection: 'row',
    gap: 6,
  },
  metric: {
    flex: 1,
    minHeight: 65,
    borderRadius: 15,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.canvas,
  },
  metricValue: {
    color: colors.navy,
    fontSize: 19,
    fontWeight: '900',
  },
  metricLabel: {
    color: colors.muted,
    fontSize: 7,
    fontWeight: '900',
    marginTop: 4,
  },
  teamList: {
    marginTop: 12,
  },
  teamRow: {
    minHeight: 62,
    flexDirection: 'row',
    alignItems: 'center',
    borderTopWidth: 1,
    borderTopColor: colors.canvasMuted,
  },
  teamStatus: {
    width: 34,
    height: 34,
    borderRadius: 13,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.canvasMuted,
  },
  teamStatusDone: {
    backgroundColor: colors.navy,
  },
  teamStatusCarried: {
    backgroundColor: colors.limeSoft,
  },
  teamStatusMissing: {
    backgroundColor: '#FFE2DF',
  },
  teamStatusText: {
    color: colors.navy,
    fontSize: 13,
    fontWeight: '900',
  },
  teamStatusTextDone: {
    color: colors.lime,
  },
  teamStatusTextMissing: {
    color: colors.danger,
  },
  teamCopy: {
    flex: 1,
    marginLeft: 11,
  },
  teamName: {
    color: colors.navy,
    fontSize: 12,
    fontWeight: '900',
  },
  teamManager: {
    color: colors.muted,
    fontSize: 9,
    fontWeight: '700',
    marginTop: 3,
  },
  teamTime: {
    color: colors.muted,
    fontSize: 8,
    fontWeight: '900',
  },
  reminderButton: {
    minHeight: 50,
    borderRadius: 17,
    alignItems: 'center',
    justifyContent: 'center',
    marginTop: 12,
    backgroundColor: colors.navy,
  },
  reminderButtonText: {
    color: colors.lime,
    fontSize: 10,
    fontWeight: '900',
    letterSpacing: 0.5,
  },
  disabledButton: {
    opacity: 0.55,
  },
  privacyNote: {
    color: colors.muted,
    fontSize: 9,
    lineHeight: 14,
    textAlign: 'center',
    marginTop: 12,
  },
  actionError: {
    color: colors.danger,
    fontSize: 10,
    fontWeight: '800',
    marginTop: 10,
  },
  successCard: {
    borderRadius: 15,
    padding: 12,
    marginTop: 10,
    backgroundColor: colors.limeSoft,
  },
  successTitle: {
    color: colors.navy,
    fontSize: 11,
    fontWeight: '900',
  },
  successBody: {
    color: colors.navySoft,
    fontSize: 9,
    marginTop: 3,
  },
  resultsCard: {
    borderRadius: radius.lg,
    padding: 18,
    backgroundColor: colors.white,
    ...shadow,
  },
  resultHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
  },
  resultEyebrow: {
    color: colors.muted,
    fontSize: 8,
    fontWeight: '900',
    letterSpacing: 0.8,
  },
  resultTitle: {
    color: colors.navy,
    fontSize: 17,
    fontWeight: '900',
    marginTop: 4,
  },
  resultRatio: {
    color: colors.navy,
    fontSize: 24,
    fontWeight: '900',
  },
  progressTrack: {
    height: 7,
    borderRadius: 999,
    overflow: 'hidden',
    marginTop: 16,
    backgroundColor: colors.canvasMuted,
  },
  progressValue: {
    height: '100%',
    borderRadius: 999,
    backgroundColor: colors.lime,
  },
  providerRow: {
    minHeight: 62,
    flexDirection: 'row',
    alignItems: 'center',
    marginTop: 10,
  },
  providerCopy: {
    flex: 1,
  },
  providerLabel: {
    color: colors.muted,
    fontSize: 8,
    fontWeight: '900',
  },
  providerValue: {
    color: colors.navy,
    fontSize: 11,
    fontWeight: '700',
    marginTop: 4,
  },
  providerDot: {
    width: 10,
    height: 10,
    borderRadius: 5,
    backgroundColor: colors.mutedLight,
  },
  providerDotActive: {
    backgroundColor: colors.success,
  },
  providerHealthCard: {
    marginTop: 12,
    borderRadius: 16,
    padding: 14,
    backgroundColor: colors.limeSoft,
  },
  providerHealthCardAttention: {
    backgroundColor: '#FFF1EF',
  },
  providerHealthHeader: {
    flexDirection: 'row',
    alignItems: 'flex-start',
    justifyContent: 'space-between',
  },
  providerHealthCopy: {
    flex: 1,
    paddingRight: 10,
  },
  providerHealthEyebrow: {
    color: colors.muted,
    fontSize: 8,
    fontWeight: '900',
    letterSpacing: 0.8,
  },
  providerHealthTitle: {
    color: colors.navy,
    fontSize: 13,
    fontWeight: '900',
    marginTop: 4,
  },
  providerHealthBadge: {
    borderRadius: 999,
    paddingHorizontal: 8,
    paddingVertical: 5,
    overflow: 'hidden',
    backgroundColor: colors.navy,
    color: colors.lime,
    fontSize: 7,
    fontWeight: '900',
  },
  providerHealthMetrics: {
    flexDirection: 'row',
    gap: 6,
    marginTop: 12,
  },
  providerHealthMetric: {
    flex: 1,
    minHeight: 48,
    borderRadius: 12,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.white,
  },
  providerHealthMetricValue: {
    color: colors.navy,
    fontSize: 16,
    fontWeight: '900',
  },
  providerHealthMetricLabel: {
    color: colors.muted,
    fontSize: 6,
    fontWeight: '900',
    marginTop: 3,
  },
  providerHealthFooter: {
    color: colors.muted,
    fontSize: 9,
    fontWeight: '700',
    marginTop: 10,
  },
  providerIncidentSummary: {
    color: colors.navy,
    fontSize: 9,
    fontWeight: '800',
    lineHeight: 14,
    marginTop: 8,
  },
  providerCircuitBreakerAlert: {
    color: colors.danger,
    fontSize: 10,
    fontWeight: '900',
    letterSpacing: 0.5,
    marginTop: 9,
  },
  providerCircuitBreakerSummary: {
    color: colors.navy,
    fontSize: 9,
    fontWeight: '800',
    lineHeight: 14,
    marginTop: 5,
  },
  providerCircuitBreakerButton: {
    minHeight: 42,
    borderRadius: 13,
    alignItems: 'center',
    justifyContent: 'center',
    marginTop: 12,
    backgroundColor: colors.lime,
  },
  providerCircuitBreakerButtonText: {
    color: colors.navy,
    fontSize: 8,
    fontWeight: '900',
  },
  providerRecoveryButton: {
    minHeight: 42,
    borderRadius: 13,
    alignItems: 'center',
    justifyContent: 'center',
    marginTop: 12,
    backgroundColor: colors.navy,
  },
  providerRecoveryButtonText: {
    color: colors.lime,
    fontSize: 8,
    fontWeight: '900',
  },
  providerRecoveryPending: {
    color: colors.navy,
    fontSize: 8,
    fontWeight: '900',
    letterSpacing: 0.4,
    marginTop: 10,
  },
  providerRecoveryWatchdog: {
    color: colors.lime,
    fontSize: 10,
    fontWeight: '900',
    letterSpacing: 0.5,
    marginTop: 7,
  },
  providerRecoveryError: {
    color: colors.danger,
    fontSize: 9,
    fontWeight: '800',
    lineHeight: 14,
    marginTop: 10,
  },
  providerRecoverySuccess: {
    color: colors.navy,
    fontSize: 9,
    fontWeight: '900',
    lineHeight: 14,
    marginTop: 10,
  },
  resultButton: {
    minHeight: 46,
    borderRadius: 16,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.canvasMuted,
  },
  resultButtonReady: {
    backgroundColor: colors.navy,
  },
  resultButtonText: {
    color: colors.navy,
    fontSize: 9,
    fontWeight: '900',
  },
  resultButtonTextReady: {
    color: colors.lime,
  },
  quickGrid: {
    flexDirection: 'row',
    gap: 8,
  },
  quickAction: {
    flex: 1,
    minHeight: 76,
    borderRadius: 18,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.white,
  },
  quickSymbol: {
    color: colors.navy,
    fontSize: 18,
    fontWeight: '900',
  },
  quickLabel: {
    color: colors.muted,
    fontSize: 8,
    fontWeight: '900',
    marginTop: 7,
  },
  footerNote: {
    color: colors.muted,
    fontSize: 8,
    lineHeight: 13,
    textAlign: 'center',
    marginTop: 24,
  },
  emptyCard: {
    borderRadius: radius.lg,
    padding: 20,
    backgroundColor: colors.white,
  },
  emptyTitle: {
    color: colors.navy,
    fontSize: 14,
    fontWeight: '900',
  },
  emptyBody: {
    color: colors.muted,
    fontSize: 11,
    lineHeight: 17,
    marginTop: 6,
  },
  loadingCard: {
    minHeight: 170,
    borderRadius: radius.xl,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.white,
  },
  loadingText: {
    color: colors.muted,
    fontSize: 11,
    fontWeight: '700',
    marginTop: 12,
  },
  errorCard: {
    borderRadius: radius.xl,
    padding: 22,
    backgroundColor: colors.white,
  },
  errorTitle: {
    color: colors.navy,
    fontSize: 17,
    fontWeight: '900',
  },
  errorBody: {
    color: colors.muted,
    fontSize: 11,
    lineHeight: 17,
    marginTop: 7,
  },
  retryButton: {
    minHeight: 44,
    borderRadius: 15,
    alignItems: 'center',
    justifyContent: 'center',
    marginTop: 16,
    backgroundColor: colors.navy,
  },
  retryButtonText: {
    color: colors.lime,
    fontSize: 9,
    fontWeight: '900',
  },
  darkButton: {
    minHeight: 48,
    borderRadius: 16,
    alignItems: 'center',
    justifyContent: 'center',
    paddingHorizontal: 20,
    backgroundColor: colors.navy,
  },
  darkButtonText: {
    color: colors.lime,
    fontSize: 10,
    fontWeight: '900',
  },
});
