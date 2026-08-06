import { supabase } from '../lib/supabase';
import type {
  LeagueLineupReminderOutcome,
  LeagueOperationFocusMatchday,
  LeagueOperationLineupMatchday,
  LeagueOperationLineupStatus,
  LeagueOperationMatchdayStatus,
  LeagueOperationsCenter,
  LeagueProviderDataQuality,
  LeagueProviderIncidentCenter,
  LeagueProviderRecoveryCenter,
  LeagueProviderSyncHealth,
  LeagueSummary,
  ProviderAutomaticRetryCenter,
  ProviderRecoveryCircuitBreakerCenter,
  ProviderRecoveryCircuitBreakerOpen,
  ProviderRecoveryCircuitBreakerReleaseOutcome,
  ProviderRecoveryOutcomeVerificationCenter,
  ProviderRecoveryRequestOutcome,
  ProviderRecoveryRequestStatus,
  ProviderWorkerFencingCenter,
  ProviderPayloadContractCenter,
  ProviderDeliveryIntegrityCenter,
  ProviderAtomicPublicationCenter,
  ProviderSemanticScopeCenter,
  ProviderScopeWatermarkCenter,
  ProviderPlayerCatalogCenter,
  ProviderFixtureLifecycleCenter,
  ProviderFixtureScoreCenter,
  ProviderFixtureScoreCoherenceCenter,
  ProviderScoreConsumptionGateCenter,
  ProviderOfficialResultImpactCenter,
  ProviderOfficialResultRemediationCenter,
  ProviderOfficialResultLineageCenter,
  ProviderOfficialResultRemediationCompletionCenter,
  ProviderMatchdayProgressionGateCenter,
  ProviderSeasonCompletionGateCenter,
  LeagueSeasonOfficialSnapshotCenter,
  ProviderSeasonBootstrapCenter,
  ProviderCompetitionStartCenter,
  ProviderReliabilityModelCenter,
  ApplicationIntegrityModelCenter,
  ApplicationReleaseModelCenter,
  ApplicationRolloutModelCenter,
  ApplicationOperationalTelemetryCenter,
  ApplicationOperationalOutboxCenter,
  ApplicationOperationalConsumerDeliveryCenter,
  ApplicationOperationalDeliveryAuditCenter,
  ApplicationDisasterRecoveryCenter,
  ApplicationPhysicalBackupCenter,
  ApplicationServiceReturnCenter,
  ApplicationProductionReadinessCenter,
  ProviderSyncAction,
  ProviderSyncRunStatus,
} from '../types';

export async function fetchLeagueOperationsCenter(
  leagueId: string,
): Promise<LeagueOperationsCenter> {
  if (!supabase) {
    throw new Error('Il collegamento al backend non è configurato.');
  }

  const [{ data, error }, providerSync] = await Promise.all([
    supabase.rpc('get_league_operations_center', {
      p_league_id: leagueId,
    }),
    fetchLeagueProviderSyncHealth(leagueId),
  ]);

  if (error) {
    throw new Error(translateLeagueOperationsError(error.message));
  }

  return {
    ...normalizeLeagueOperationsCenter(data),
    providerSync,
  };
}

async function fetchLeagueProviderSyncHealth(
  leagueId: string,
): Promise<LeagueProviderSyncHealth | null> {
  if (!supabase) {
    return null;
  }

  const productionReadiness = await supabase.rpc(
    'get_league_provider_sync_health_v42',
    { p_league_id: leagueId },
  );

  if (!productionReadiness.error) {
    return normalizeProviderSyncHealth(productionReadiness.data);
  }

  const productionReadinessError = productionReadiness.error.message.toLowerCase();
  if (
    !productionReadinessError.includes('get_league_provider_sync_health_v42') &&
    !(productionReadinessError.includes('function') && productionReadinessError.includes('does not exist'))
  ) {
    throw new Error(translateLeagueOperationsError(productionReadiness.error.message));
  }

  const serviceReturn = await supabase.rpc(
    'get_league_provider_sync_health_v41',
    { p_league_id: leagueId },
  );

  if (!serviceReturn.error) {
    return normalizeProviderSyncHealth(serviceReturn.data);
  }

  const serviceReturnError = serviceReturn.error.message.toLowerCase();
  if (
    !serviceReturnError.includes('get_league_provider_sync_health_v41') &&
    !(serviceReturnError.includes('function') && serviceReturnError.includes('does not exist'))
  ) {
    throw new Error(translateLeagueOperationsError(serviceReturn.error.message));
  }

  const physicalBackup = await supabase.rpc(
    'get_league_provider_sync_health_v40',
    { p_league_id: leagueId },
  );

  if (!physicalBackup.error) {
    return normalizeProviderSyncHealth(physicalBackup.data);
  }

  const physicalBackupError = physicalBackup.error.message.toLowerCase();
  if (
    !physicalBackupError.includes('get_league_provider_sync_health_v40') &&
    !(physicalBackupError.includes('function') && physicalBackupError.includes('does not exist'))
  ) {
    throw new Error(translateLeagueOperationsError(physicalBackup.error.message));
  }

  const disasterRecovery = await supabase.rpc(
    'get_league_provider_sync_health_v39',
    { p_league_id: leagueId },
  );

  if (!disasterRecovery.error) {
    return normalizeProviderSyncHealth(disasterRecovery.data);
  }

  const disasterRecoveryError = disasterRecovery.error.message.toLowerCase();
  if (
    !disasterRecoveryError.includes('get_league_provider_sync_health_v39') &&
    !(disasterRecoveryError.includes('function') && disasterRecoveryError.includes('does not exist'))
  ) {
    throw new Error(translateLeagueOperationsError(disasterRecovery.error.message));
  }

  const operationalDeliveryAudit = await supabase.rpc(
    'get_league_provider_sync_health_v38',
    { p_league_id: leagueId },
  );

  if (!operationalDeliveryAudit.error) {
    return normalizeProviderSyncHealth(operationalDeliveryAudit.data);
  }

  const operationalDeliveryAuditError =
    operationalDeliveryAudit.error.message.toLowerCase();
  if (
    !operationalDeliveryAuditError.includes(
      'get_league_provider_sync_health_v38',
    ) &&
    !(
      operationalDeliveryAuditError.includes('function') &&
      operationalDeliveryAuditError.includes('does not exist')
    )
  ) {
    throw new Error(
      translateLeagueOperationsError(operationalDeliveryAudit.error.message),
    );
  }

  const operationalConsumerDelivery = await supabase.rpc(
    'get_league_provider_sync_health_v37',
    { p_league_id: leagueId },
  );

  if (!operationalConsumerDelivery.error) {
    return normalizeProviderSyncHealth(operationalConsumerDelivery.data);
  }

  const operationalConsumerDeliveryError =
    operationalConsumerDelivery.error.message.toLowerCase();
  if (
    !operationalConsumerDeliveryError.includes(
      'get_league_provider_sync_health_v37',
    ) &&
    !(
      operationalConsumerDeliveryError.includes('function') &&
      operationalConsumerDeliveryError.includes('does not exist')
    )
  ) {
    throw new Error(
      translateLeagueOperationsError(
        operationalConsumerDelivery.error.message,
      ),
    );
  }

  const operationalOutbox = await supabase.rpc(
    'get_league_provider_sync_health_v36',
    { p_league_id: leagueId },
  );

  if (!operationalOutbox.error) {
    return normalizeProviderSyncHealth(operationalOutbox.data);
  }

  const operationalOutboxError = operationalOutbox.error.message.toLowerCase();
  if (
    !operationalOutboxError.includes('get_league_provider_sync_health_v36') &&
    !(
      operationalOutboxError.includes('function') &&
      operationalOutboxError.includes('does not exist')
    )
  ) {
    throw new Error(
      translateLeagueOperationsError(operationalOutbox.error.message),
    );
  }

  const operationalTelemetry = await supabase.rpc(
    'get_league_provider_sync_health_v35',
    { p_league_id: leagueId },
  );

  if (!operationalTelemetry.error) {
    return normalizeProviderSyncHealth(operationalTelemetry.data);
  }

  const operationalTelemetryError =
    operationalTelemetry.error.message.toLowerCase();
  if (
    !operationalTelemetryError.includes(
      'get_league_provider_sync_health_v35',
    ) &&
    !(
      operationalTelemetryError.includes('function') &&
      operationalTelemetryError.includes('does not exist')
    )
  ) {
    throw new Error(
      translateLeagueOperationsError(operationalTelemetry.error.message),
    );
  }

  const applicationRolloutModel = await supabase.rpc(
    'get_league_provider_sync_health_v34',
    { p_league_id: leagueId },
  );

  if (!applicationRolloutModel.error) {
    return normalizeProviderSyncHealth(applicationRolloutModel.data);
  }

  const applicationRolloutModelError =
    applicationRolloutModel.error.message.toLowerCase();
  if (
    !applicationRolloutModelError.includes(
      'get_league_provider_sync_health_v34',
    ) &&
    !(
      applicationRolloutModelError.includes('function') &&
      applicationRolloutModelError.includes('does not exist')
    )
  ) {
    throw new Error(
      translateLeagueOperationsError(applicationRolloutModel.error.message),
    );
  }

  const applicationReleaseModel = await supabase.rpc(
    'get_league_provider_sync_health_v33',
    { p_league_id: leagueId },
  );

  if (!applicationReleaseModel.error) {
    return normalizeProviderSyncHealth(applicationReleaseModel.data);
  }

  const applicationReleaseModelError =
    applicationReleaseModel.error.message.toLowerCase();
  if (
    !applicationReleaseModelError.includes(
      'get_league_provider_sync_health_v33',
    ) &&
    !(
      applicationReleaseModelError.includes('function') &&
      applicationReleaseModelError.includes('does not exist')
    )
  ) {
    throw new Error(
      translateLeagueOperationsError(applicationReleaseModel.error.message),
    );
  }

  const applicationIntegrityModel = await supabase.rpc(
    'get_league_provider_sync_health_v32',
    { p_league_id: leagueId },
  );

  if (!applicationIntegrityModel.error) {
    return normalizeProviderSyncHealth(applicationIntegrityModel.data);
  }

  const applicationIntegrityModelError =
    applicationIntegrityModel.error.message.toLowerCase();
  if (
    !applicationIntegrityModelError.includes(
      'get_league_provider_sync_health_v32',
    ) &&
    !(
      applicationIntegrityModelError.includes('function') &&
      applicationIntegrityModelError.includes('does not exist')
    )
  ) {
    throw new Error(
      translateLeagueOperationsError(applicationIntegrityModel.error.message),
    );
  }

  const providerReliabilityModel = await supabase.rpc(
    'get_league_provider_sync_health_v31',
    { p_league_id: leagueId },
  );

  if (!providerReliabilityModel.error) {
    return normalizeProviderSyncHealth(providerReliabilityModel.data);
  }

  const providerReliabilityModelError =
    providerReliabilityModel.error.message.toLowerCase();
  if (
    !providerReliabilityModelError.includes(
      'get_league_provider_sync_health_v31',
    ) &&
    !(
      providerReliabilityModelError.includes('function') &&
      providerReliabilityModelError.includes('does not exist')
    )
  ) {
    throw new Error(
      translateLeagueOperationsError(providerReliabilityModel.error.message),
    );
  }

  const providerCompetitionStart = await supabase.rpc(
    'get_league_provider_sync_health_v30',
    { p_league_id: leagueId },
  );

  if (!providerCompetitionStart.error) {
    return normalizeProviderSyncHealth(providerCompetitionStart.data);
  }

  const providerCompetitionStartError =
    providerCompetitionStart.error.message.toLowerCase();
  if (
    !providerCompetitionStartError.includes(
      'get_league_provider_sync_health_v30',
    ) &&
    !(
      providerCompetitionStartError.includes('function') &&
      providerCompetitionStartError.includes('does not exist')
    )
  ) {
    throw new Error(
      translateLeagueOperationsError(providerCompetitionStart.error.message),
    );
  }

  const providerSeasonBootstrap = await supabase.rpc(
    'get_league_provider_sync_health_v29',
    { p_league_id: leagueId },
  );

  if (!providerSeasonBootstrap.error) {
    return normalizeProviderSyncHealth(providerSeasonBootstrap.data);
  }

  const providerSeasonBootstrapError =
    providerSeasonBootstrap.error.message.toLowerCase();
  if (
    !providerSeasonBootstrapError.includes(
      'get_league_provider_sync_health_v29',
    ) &&
    !(
      providerSeasonBootstrapError.includes('function') &&
      providerSeasonBootstrapError.includes('does not exist')
    )
  ) {
    throw new Error(
      translateLeagueOperationsError(providerSeasonBootstrap.error.message),
    );
  }

  const seasonRolloverLineage = await supabase.rpc(
    'get_league_provider_sync_health_v28',
    { p_league_id: leagueId },
  );

  if (!seasonRolloverLineage.error) {
    return normalizeProviderSyncHealth(seasonRolloverLineage.data);
  }

  const seasonRolloverLineageError =
    seasonRolloverLineage.error.message.toLowerCase();
  if (
    !seasonRolloverLineageError.includes(
      'get_league_provider_sync_health_v28',
    ) &&
    !(
      seasonRolloverLineageError.includes('function') &&
      seasonRolloverLineageError.includes('does not exist')
    )
  ) {
    throw new Error(
      translateLeagueOperationsError(seasonRolloverLineage.error.message),
    );
  }

  const seasonOfficialSnapshot = await supabase.rpc(
    'get_league_provider_sync_health_v27',
    { p_league_id: leagueId },
  );

  if (!seasonOfficialSnapshot.error) {
    return normalizeProviderSyncHealth(seasonOfficialSnapshot.data);
  }

  const seasonOfficialSnapshotError =
    seasonOfficialSnapshot.error.message.toLowerCase();
  if (
    !seasonOfficialSnapshotError.includes(
      'get_league_provider_sync_health_v27',
    ) &&
    !(
      seasonOfficialSnapshotError.includes('function') &&
      seasonOfficialSnapshotError.includes('does not exist')
    )
  ) {
    throw new Error(
      translateLeagueOperationsError(seasonOfficialSnapshot.error.message),
    );
  }

  const seasonCompletionGate = await supabase.rpc(
    'get_league_provider_sync_health_v26',
    { p_league_id: leagueId },
  );

  if (!seasonCompletionGate.error) {
    return normalizeProviderSyncHealth(seasonCompletionGate.data);
  }

  const seasonCompletionGateError =
    seasonCompletionGate.error.message.toLowerCase();
  if (
    !seasonCompletionGateError.includes(
      'get_league_provider_sync_health_v26',
    ) &&
    !(
      seasonCompletionGateError.includes('function') &&
      seasonCompletionGateError.includes('does not exist')
    )
  ) {
    throw new Error(
      translateLeagueOperationsError(seasonCompletionGate.error.message),
    );
  }

  const matchdayProgressionGate = await supabase.rpc(
    'get_league_provider_sync_health_v25',
    { p_league_id: leagueId },
  );

  if (!matchdayProgressionGate.error) {
    return normalizeProviderSyncHealth(matchdayProgressionGate.data);
  }

  const matchdayProgressionGateError =
    matchdayProgressionGate.error.message.toLowerCase();
  if (
    !matchdayProgressionGateError.includes(
      'get_league_provider_sync_health_v25',
    ) &&
    !(
      matchdayProgressionGateError.includes('function') &&
      matchdayProgressionGateError.includes('does not exist')
    )
  ) {
    throw new Error(
      translateLeagueOperationsError(matchdayProgressionGate.error.message),
    );
  }

  const officialResultRemediationCompletion = await supabase.rpc(
    'get_league_provider_sync_health_v24',
    { p_league_id: leagueId },
  );

  if (!officialResultRemediationCompletion.error) {
    return normalizeProviderSyncHealth(
      officialResultRemediationCompletion.data,
    );
  }

  const officialResultRemediationCompletionError =
    officialResultRemediationCompletion.error.message.toLowerCase();
  if (
    !officialResultRemediationCompletionError.includes(
      'get_league_provider_sync_health_v24',
    ) &&
    !(
      officialResultRemediationCompletionError.includes('function') &&
      officialResultRemediationCompletionError.includes('does not exist')
    )
  ) {
    throw new Error(
      translateLeagueOperationsError(
        officialResultRemediationCompletion.error.message,
      ),
    );
  }

  const officialResultLineage = await supabase.rpc(
    'get_league_provider_sync_health_v23',
    { p_league_id: leagueId },
  );

  if (!officialResultLineage.error) {
    return normalizeProviderSyncHealth(officialResultLineage.data);
  }

  const officialResultLineageError =
    officialResultLineage.error.message.toLowerCase();
  if (
    !officialResultLineageError.includes('get_league_provider_sync_health_v23') &&
    !(
      officialResultLineageError.includes('function') &&
      officialResultLineageError.includes('does not exist')
    )
  ) {
    throw new Error(
      translateLeagueOperationsError(officialResultLineage.error.message),
    );
  }

  const officialResultRemediation = await supabase.rpc(
    'get_league_provider_sync_health_v22',
    { p_league_id: leagueId },
  );

  if (!officialResultRemediation.error) {
    return normalizeProviderSyncHealth(officialResultRemediation.data);
  }

  const officialResultRemediationError =
    officialResultRemediation.error.message.toLowerCase();
  if (
    !officialResultRemediationError.includes(
      'get_league_provider_sync_health_v22',
    ) &&
    !(
      officialResultRemediationError.includes('function') &&
      officialResultRemediationError.includes('does not exist')
    )
  ) {
    throw new Error(
      translateLeagueOperationsError(
        officialResultRemediation.error.message,
      ),
    );
  }

  const officialResultImpact = await supabase.rpc(
    'get_league_provider_sync_health_v21',
    { p_league_id: leagueId },
  );

  if (!officialResultImpact.error) {
    return normalizeProviderSyncHealth(officialResultImpact.data);
  }

  const officialResultImpactError =
    officialResultImpact.error.message.toLowerCase();
  if (
    !officialResultImpactError.includes('get_league_provider_sync_health_v21') &&
    !(
      officialResultImpactError.includes('function') &&
      officialResultImpactError.includes('does not exist')
    )
  ) {
    throw new Error(
      translateLeagueOperationsError(officialResultImpact.error.message),
    );
  }

  const scoreConsumptionGate = await supabase.rpc(
    'get_league_provider_sync_health_v20',
    { p_league_id: leagueId },
  );

  if (!scoreConsumptionGate.error) {
    return normalizeProviderSyncHealth(scoreConsumptionGate.data);
  }

  const scoreConsumptionGateError =
    scoreConsumptionGate.error.message.toLowerCase();
  if (
    !scoreConsumptionGateError.includes('get_league_provider_sync_health_v20') &&
    !(
      scoreConsumptionGateError.includes('function') &&
      scoreConsumptionGateError.includes('does not exist')
    )
  ) {
    throw new Error(
      translateLeagueOperationsError(scoreConsumptionGate.error.message),
    );
  }

  const fixtureScoreCoherence = await supabase.rpc(
    'get_league_provider_sync_health_v19',
    { p_league_id: leagueId },
  );

  if (!fixtureScoreCoherence.error) {
    return normalizeProviderSyncHealth(fixtureScoreCoherence.data);
  }

  const fixtureScoreCoherenceError =
    fixtureScoreCoherence.error.message.toLowerCase();
  if (
    !fixtureScoreCoherenceError.includes('get_league_provider_sync_health_v19') &&
    !(
      fixtureScoreCoherenceError.includes('function') &&
      fixtureScoreCoherenceError.includes('does not exist')
    )
  ) {
    throw new Error(
      translateLeagueOperationsError(fixtureScoreCoherence.error.message),
    );
  }

  const fixtureLifecycle = await supabase.rpc(
    'get_league_provider_sync_health_v18',
    { p_league_id: leagueId },
  );

  if (!fixtureLifecycle.error) {
    return normalizeProviderSyncHealth(fixtureLifecycle.data);
  }

  const fixtureLifecycleError = fixtureLifecycle.error.message.toLowerCase();
  if (
    !fixtureLifecycleError.includes('get_league_provider_sync_health_v18') &&
    !(
      fixtureLifecycleError.includes('function') &&
      fixtureLifecycleError.includes('does not exist')
    )
  ) {
    throw new Error(
      translateLeagueOperationsError(fixtureLifecycle.error.message),
    );
  }

  const fixtureScores = await supabase.rpc(
    'get_league_provider_sync_health_v17',
    { p_league_id: leagueId },
  );

  if (!fixtureScores.error) {
    return normalizeProviderSyncHealth(fixtureScores.data);
  }

  const fixtureScoresError = fixtureScores.error.message.toLowerCase();
  if (
    !fixtureScoresError.includes('get_league_provider_sync_health_v17') &&
    !(
      fixtureScoresError.includes('function') &&
      fixtureScoresError.includes('does not exist')
    )
  ) {
    throw new Error(
      translateLeagueOperationsError(fixtureScores.error.message),
    );
  }

  const playerCatalog = await supabase.rpc(
    'get_league_provider_sync_health_v16',
    { p_league_id: leagueId },
  );

  if (!playerCatalog.error) {
    return normalizeProviderSyncHealth(playerCatalog.data);
  }

  const playerCatalogError = playerCatalog.error.message.toLowerCase();
  if (
    !playerCatalogError.includes('get_league_provider_sync_health_v16') &&
    !(
      playerCatalogError.includes('function') &&
      playerCatalogError.includes('does not exist')
    )
  ) {
    throw new Error(
      translateLeagueOperationsError(playerCatalog.error.message),
    );
  }

  const monotonicPublication = await supabase.rpc(
    'get_league_provider_sync_health_v15',
    { p_league_id: leagueId },
  );

  if (!monotonicPublication.error) {
    return normalizeProviderSyncHealth(monotonicPublication.data);
  }

  const monotonicError = monotonicPublication.error.message.toLowerCase();
  if (
    !monotonicError.includes('get_league_provider_sync_health_v15') &&
    !(
      monotonicError.includes('function') &&
      monotonicError.includes('does not exist')
    )
  ) {
    throw new Error(
      translateLeagueOperationsError(monotonicPublication.error.message),
    );
  }

  const semanticScope = await supabase.rpc(
    'get_league_provider_sync_health_v14',
    { p_league_id: leagueId },
  );

  if (!semanticScope.error) {
    return normalizeProviderSyncHealth(semanticScope.data);
  }

  const semanticScopeError = semanticScope.error.message.toLowerCase();
  if (
    !semanticScopeError.includes('get_league_provider_sync_health_v14') &&
    !(
      semanticScopeError.includes('function') &&
      semanticScopeError.includes('does not exist')
    )
  ) {
    throw new Error(
      translateLeagueOperationsError(semanticScope.error.message),
    );
  }

  const atomicPublication = await supabase.rpc(
    'get_league_provider_sync_health_v13',
    { p_league_id: leagueId },
  );

  if (!atomicPublication.error) {
    return normalizeProviderSyncHealth(atomicPublication.data);
  }

  const atomicPublicationError = atomicPublication.error.message.toLowerCase();
  if (
    !atomicPublicationError.includes('get_league_provider_sync_health_v13') &&
    !(
      atomicPublicationError.includes('function') &&
      atomicPublicationError.includes('does not exist')
    )
  ) {
    throw new Error(
      translateLeagueOperationsError(atomicPublication.error.message),
    );
  }

  const deliveryIntegrity = await supabase.rpc(
    'get_league_provider_sync_health_v12',
    { p_league_id: leagueId },
  );

  if (!deliveryIntegrity.error) {
    return normalizeProviderSyncHealth(deliveryIntegrity.data);
  }

  const deliveryIntegrityError = deliveryIntegrity.error.message.toLowerCase();
  if (
    !deliveryIntegrityError.includes('get_league_provider_sync_health_v12') &&
    !(
      deliveryIntegrityError.includes('function') &&
      deliveryIntegrityError.includes('does not exist')
    )
  ) {
    throw new Error(
      translateLeagueOperationsError(deliveryIntegrity.error.message),
    );
  }

  const payloadContracts = await supabase.rpc(
    'get_league_provider_sync_health_v11',
    { p_league_id: leagueId },
  );

  if (!payloadContracts.error) {
    return normalizeProviderSyncHealth(payloadContracts.data);
  }

  const payloadContractsError = payloadContracts.error.message.toLowerCase();
  if (
    !payloadContractsError.includes('get_league_provider_sync_health_v11') &&
    !(
      payloadContractsError.includes('function') &&
      payloadContractsError.includes('does not exist')
    )
  ) {
    throw new Error(
      translateLeagueOperationsError(payloadContracts.error.message),
    );
  }

  const workerFencing = await supabase.rpc(
    'get_league_provider_sync_health_v10',
    { p_league_id: leagueId },
  );

  if (!workerFencing.error) {
    return normalizeProviderSyncHealth(workerFencing.data);
  }

  const workerFencingError = workerFencing.error.message.toLowerCase();
  if (
    !workerFencingError.includes('get_league_provider_sync_health_v10') &&
    !(
      workerFencingError.includes('function') &&
      workerFencingError.includes('does not exist')
    )
  ) {
    throw new Error(
      translateLeagueOperationsError(workerFencing.error.message),
    );
  }

  const outcomeVerification = await supabase.rpc(
    'get_league_provider_sync_health_v9',
    { p_league_id: leagueId },
  );

  if (!outcomeVerification.error) {
    return normalizeProviderSyncHealth(outcomeVerification.data);
  }

  const outcomeVerificationError =
    outcomeVerification.error.message.toLowerCase();
  if (
    !outcomeVerificationError.includes('get_league_provider_sync_health_v9') &&
    !(
      outcomeVerificationError.includes('function') &&
      outcomeVerificationError.includes('does not exist')
    )
  ) {
    throw new Error(
      translateLeagueOperationsError(outcomeVerification.error.message),
    );
  }

  const circuitBreaker = await supabase.rpc(
    'get_league_provider_sync_health_v8',
    { p_league_id: leagueId },
  );

  if (!circuitBreaker.error) {
    return normalizeProviderSyncHealth(circuitBreaker.data);
  }

  const circuitBreakerError = circuitBreaker.error.message.toLowerCase();
  if (
    !circuitBreakerError.includes('get_league_provider_sync_health_v8') &&
    !(
      circuitBreakerError.includes('function') &&
      circuitBreakerError.includes('does not exist')
    )
  ) {
    throw new Error(
      translateLeagueOperationsError(circuitBreaker.error.message),
    );
  }

  const automaticRetry = await supabase.rpc(
    'get_league_provider_sync_health_v7',
    { p_league_id: leagueId },
  );

  if (!automaticRetry.error) {
    return normalizeProviderSyncHealth(automaticRetry.data);
  }

  const automaticRetryError = automaticRetry.error.message.toLowerCase();
  if (
    !automaticRetryError.includes('get_league_provider_sync_health_v7') &&
    !(
      automaticRetryError.includes('function') &&
      automaticRetryError.includes('does not exist')
    )
  ) {
    throw new Error(
      translateLeagueOperationsError(automaticRetry.error.message),
    );
  }

  const heartbeat = await supabase.rpc(
    'get_league_provider_sync_health_v6',
    { p_league_id: leagueId },
  );

  if (!heartbeat.error) {
    return normalizeProviderSyncHealth(heartbeat.data);
  }

  const heartbeatError = heartbeat.error.message.toLowerCase();
  if (
    !heartbeatError.includes('get_league_provider_sync_health_v6') &&
    !(
      heartbeatError.includes('function') &&
      heartbeatError.includes('does not exist')
    )
  ) {
    throw new Error(translateLeagueOperationsError(heartbeat.error.message));
  }

  const watchdog = await supabase.rpc(
    'get_league_provider_sync_health_v5',
    { p_league_id: leagueId },
  );

  if (!watchdog.error) {
    return normalizeProviderSyncHealth(watchdog.data);
  }

  const watchdogError = watchdog.error.message.toLowerCase();
  if (
    !watchdogError.includes('get_league_provider_sync_health_v5') &&
    !(
      watchdogError.includes('function') &&
      watchdogError.includes('does not exist')
    )
  ) {
    throw new Error(translateLeagueOperationsError(watchdog.error.message));
  }

  const latest = await supabase.rpc(
    'get_league_provider_sync_health_v4',
    { p_league_id: leagueId },
  );

  if (!latest.error) {
    return normalizeProviderSyncHealth(latest.data);
  }

  const latestError = latest.error.message.toLowerCase();
  if (
    !latestError.includes('get_league_provider_sync_health_v4') &&
    !(
      latestError.includes('function') &&
      latestError.includes('does not exist')
    )
  ) {
    throw new Error(translateLeagueOperationsError(latest.error.message));
  }

  const current = await supabase.rpc(
    'get_league_provider_sync_health_v3',
    { p_league_id: leagueId },
  );

  if (!current.error) {
    return normalizeProviderSyncHealth(current.data);
  }

  const currentError = current.error.message.toLowerCase();
  if (
    !currentError.includes('get_league_provider_sync_health_v3') &&
    !(
      currentError.includes('function') &&
      currentError.includes('does not exist')
    )
  ) {
    throw new Error(translateLeagueOperationsError(current.error.message));
  }

  const previous = await supabase.rpc(
    'get_league_provider_sync_health_v2',
    { p_league_id: leagueId },
  );

  if (!previous.error) {
    return normalizeProviderSyncHealth(previous.data);
  }

  const previousError = previous.error.message.toLowerCase();
  if (
    !previousError.includes('get_league_provider_sync_health_v2') &&
    !(
      previousError.includes('function') &&
      previousError.includes('does not exist')
    )
  ) {
    throw new Error(translateLeagueOperationsError(previous.error.message));
  }

  const legacy = await supabase.rpc(
    'get_league_provider_sync_health_v1',
    { p_league_id: leagueId },
  );

  if (legacy.error) {
    const normalized = legacy.error.message.toLowerCase();
    if (
      normalized.includes('get_league_provider_sync_health_v1') ||
      (normalized.includes('function') && normalized.includes('does not exist'))
    ) {
      return null;
    }
    throw new Error(translateLeagueOperationsError(legacy.error.message));
  }

  return normalizeProviderSyncHealth(legacy.data);
}

export async function requestLeagueProviderRecovery(
  leagueId: string,
  incidentId: string,
  expectedIncidentRevision: number,
): Promise<
  | { data: ProviderRecoveryRequestOutcome; error?: never }
  | { error: string }
> {
  if (!supabase) {
    return { error: 'Il collegamento al backend non è configurato.' };
  }

  const { data, error } = await supabase.rpc(
    'request_provider_recovery_guarded_v1',
    {
      p_league_id: leagueId,
      p_incident_id: incidentId,
      p_expected_incident_revision: expectedIncidentRevision,
      p_idempotency_key: createOperationId(),
    },
  );

  if (error) {
    return { error: translateLeagueOperationsError(error.message) };
  }

  return { data: normalizeProviderRecoveryOutcome(data) };
}

export async function releaseLeagueProviderCircuitBreaker(
  leagueId: string,
  breakerId: string,
  expectedRevision: number,
): Promise<
  | { data: ProviderRecoveryCircuitBreakerReleaseOutcome; error?: never }
  | { error: string }
> {
  if (!supabase) {
    return { error: 'Il collegamento al backend non è configurato.' };
  }

  const { data, error } = await supabase.rpc(
    'release_provider_recovery_circuit_breaker_guarded_v1',
    {
      p_league_id: leagueId,
      p_breaker_id: breakerId,
      p_expected_revision: expectedRevision,
      p_release_reason:
        'Riapertura manuale autorizzata dal Centro Operativo LEGHEVO.',
      p_idempotency_key: createOperationId(),
    },
  );

  if (error) {
    return { error: translateLeagueOperationsError(error.message) };
  }

  return { data: normalizeProviderCircuitBreakerReleaseOutcome(data) };
}

export async function sendLeagueLineupReminders(
  leagueId: string,
  matchdayId: string,
): Promise<
  { data: LeagueLineupReminderOutcome; error?: never } | { error: string }
> {
  if (!supabase) {
    return { error: 'Il collegamento al backend non è configurato.' };
  }

  const { data, error } = await supabase.rpc(
    'send_league_lineup_reminders',
    {
      p_league_id: leagueId,
      p_matchday_id: matchdayId,
    },
  );

  if (error) {
    return { error: translateLeagueOperationsError(error.message) };
  }

  return { data: normalizeReminderOutcome(data) };
}

export function subscribeToLeagueOperations(
  leagueId: string,
  onChange: () => void,
) {
  if (!supabase) {
    return () => undefined;
  }

  const client = supabase;
  const channel = client
    .channel(`league-operations-${leagueId}`)
    .on(
      'postgres_changes',
      {
        event: '*',
        schema: 'public',
        table: 'fantasy_fixtures',
        filter: `league_id=eq.${leagueId}`,
      },
      onChange,
    )
    .on(
      'postgres_changes',
      {
        event: '*',
        schema: 'public',
        table: 'lineups',
      },
      onChange,
    )
    .on(
      'postgres_changes',
      {
        event: '*',
        schema: 'public',
        table: 'matchdays',
      },
      onChange,
    )
    .on(
      'postgres_changes',
      {
        event: 'INSERT',
        schema: 'public',
        table: 'provider_sync_run_events',
      },
      onChange,
    )
    .on(
      'postgres_changes',
      {
        event: 'INSERT',
        schema: 'public',
        table: 'provider_data_quality_snapshots',
      },
      onChange,
    )
    .on(
      'postgres_changes',
      {
        event: '*',
        schema: 'public',
        table: 'provider_operational_incidents',
      },
      onChange,
    )
    .on(
      'postgres_changes',
      {
        event: 'INSERT',
        schema: 'public',
        table: 'provider_operational_incident_events',
      },
      onChange,
    )
    .on(
      'postgres_changes',
      {
        event: '*',
        schema: 'public',
        table: 'provider_recovery_requests',
        filter: `league_id=eq.${leagueId}`,
      },
      onChange,
    )
    .on(
      'postgres_changes',
      {
        event: 'INSERT',
        schema: 'public',
        table: 'provider_recovery_request_events',
        filter: `league_id=eq.${leagueId}`,
      },
      onChange,
    )
    .on(
      'postgres_changes',
      {
        event: 'INSERT',
        schema: 'public',
        table: 'provider_recovery_watchdog_events',
        filter: `league_id=eq.${leagueId}`,
      },
      onChange,
    )
    .on(
      'postgres_changes',
      {
        event: 'INSERT',
        schema: 'public',
        table: 'provider_recovery_retry_events',
        filter: `league_id=eq.${leagueId}`,
      },
      onChange,
    )
    .on(
      'postgres_changes',
      {
        event: 'INSERT',
        schema: 'public',
        table: 'provider_recovery_circuit_breaker_events',
        filter: `league_id=eq.${leagueId}`,
      },
      onChange,
    )
    .on(
      'postgres_changes',
      {
        event: 'INSERT',
        schema: 'public',
        table: 'provider_sync_publication_events',
      },
      onChange,
    )
    .on(
      'postgres_changes',
      {
        event: 'INSERT',
        schema: 'public',
        table: 'provider_sync_scope_events',
      },
      onChange,
    )
    .on(
      'postgres_changes',
      {
        event: 'INSERT',
        schema: 'public',
        table: 'provider_score_consumption_gate_events',
      },
      onChange,
    )
    .on(
      'postgres_changes',
      {
        event: 'INSERT',
        schema: 'public',
        table: 'provider_official_result_impact_events',
        filter: `league_id=eq.${leagueId}`,
      },
      onChange,
    )
    .on(
      'postgres_changes',
      {
        event: 'INSERT',
        schema: 'public',
        table: 'provider_official_result_remediation_events',
        filter: `league_id=eq.${leagueId}`,
      },
      onChange,
    )
    .on(
      'postgres_changes',
      {
        event: 'INSERT',
        schema: 'public',
        table: 'provider_official_result_lineage_events',
        filter: `league_id=eq.${leagueId}`,
      },
      onChange,
    )
    .on(
      'postgres_changes',
      {
        event: 'INSERT',
        schema: 'public',
        table: 'provider_official_result_remediation_completion_events',
        filter: `league_id=eq.${leagueId}`,
      },
      onChange,
    )
    .subscribe();

  return () => {
    void client.removeChannel(channel);
  };
}

export function normalizeLeagueOperationsCenter(
  value: unknown,
): LeagueOperationsCenter {
  const raw = asRecord(value);
  return {
    leagueId: toStringValue(raw.leagueId),
    leagueName: toStringValue(raw.leagueName),
    leagueStatus: normalizeLeagueStatus(raw.leagueStatus),
    season: toNullableString(raw.season),
    competitionStartedAt: toNullableString(raw.competitionStartedAt),
    isOwner: Boolean(raw.isOwner),
    isDirector: Boolean(raw.isDirector),
    generatedAt: toStringValue(raw.generatedAt),
    focusMatchday: normalizeFocusMatchday(raw.focusMatchday),
    nextLineupMatchday: normalizeLineupMatchday(raw.nextLineupMatchday),
    providerSync: null,
  };
}

function normalizeProviderSyncHealth(
  value: unknown,
): LeagueProviderSyncHealth {
  const raw = asRecord(value);
  return {
    provider: toStringValue(raw.provider) || 'api-football',
    protected: Boolean(raw.protected),
    healthy: Boolean(raw.healthy),
    status: normalizeProviderSyncHealthStatus(raw.status),
    failedLast24h: toNumber(raw.failedLast24h),
    stuckRunCount: toNumber(raw.stuckRunCount),
    lastRunAt: toNullableString(raw.lastRunAt),
    lastSuccessfulAt: toNullableString(raw.lastSuccessfulAt),
    latestDataAt: toNullableString(raw.latestDataAt),
    dataQuality: normalizeProviderDataQuality(raw.dataQuality),
    incidentCenter: normalizeProviderIncidentCenter(raw.incidentCenter),
    recoveryCenter: normalizeProviderRecoveryCenter(raw.recoveryCenter),
    payloadContracts: normalizeProviderPayloadContractCenter(
      raw.payloadContracts,
    ),
    deliveryIntegrity: normalizeProviderDeliveryIntegrityCenter(
      raw.deliveryIntegrity,
    ),
    atomicPublication: normalizeProviderAtomicPublicationCenter(
      raw.atomicPublication,
    ),
    semanticScope: normalizeProviderSemanticScopeCenter(raw.semanticScope),
    publicationWatermark: normalizeProviderScopeWatermarkCenter(
      raw.publicationWatermark,
    ),
    playerCatalogReconciliation: normalizeProviderPlayerCatalogCenter(
      raw.playerCatalogReconciliation,
    ),
    fixtureLifecycleReconciliation:
      normalizeProviderFixtureLifecycleCenter(
        raw.fixtureLifecycleReconciliation,
      ),
    fixtureScoreReconciliation: normalizeProviderFixtureScoreCenter(
      raw.fixtureScoreReconciliation,
    ),
    fixtureScoreCoherence: normalizeProviderFixtureScoreCoherenceCenter(
      raw.fixtureScoreCoherence,
    ),
    scoreConsumptionGate: normalizeProviderScoreConsumptionGateCenter(
      raw.scoreConsumptionGate,
    ),
    officialResultImpact: normalizeProviderOfficialResultImpactCenter(
      raw.officialResultImpact,
    ),
    officialResultRemediation:
      normalizeProviderOfficialResultRemediationCenter(
        raw.officialResultRemediation,
      ),
    officialResultLineage: normalizeProviderOfficialResultLineageCenter(
      raw.officialResultLineage,
    ),
    officialResultRemediationCompletion:
      normalizeProviderOfficialResultRemediationCompletionCenter(
        raw.officialResultRemediationCompletion,
      ),
    matchdayProgressionGate: normalizeProviderMatchdayProgressionGateCenter(
      raw.matchdayProgressionGate,
    ),
    seasonCompletionGate: normalizeProviderSeasonCompletionGateCenter(
      raw.seasonCompletionGate,
    ),
    seasonOfficialSnapshot: normalizeLeagueSeasonOfficialSnapshotCenter(
      raw.seasonOfficialSnapshot,
    ),
    providerSeasonBootstrap: normalizeProviderSeasonBootstrapCenter(
      raw.providerSeasonBootstrap,
    ),
    providerCompetitionStart: normalizeProviderCompetitionStartCenter(
      raw.providerCompetitionStart,
    ),
    providerReliabilityModel: normalizeProviderReliabilityModelCenter(
      raw.providerReliabilityModel,
    ),
    applicationIntegrityModel: normalizeApplicationIntegrityModelCenter(
      raw.applicationIntegrityModel,
    ),
    applicationReleaseModel: normalizeApplicationReleaseModelCenter(
      raw.applicationReleaseModel,
    ),
    applicationRolloutModel: normalizeApplicationRolloutModelCenter(
      raw.applicationRolloutModel,
    ),
    applicationOperationalTelemetry:
      normalizeApplicationOperationalTelemetryCenter(
        raw.applicationOperationalTelemetry,
      ),
    applicationOperationalOutbox:
      normalizeApplicationOperationalOutboxCenter(
        raw.applicationOperationalOutbox,
      ),
    applicationOperationalConsumerDelivery:
      normalizeApplicationOperationalConsumerDeliveryCenter(
        raw.applicationOperationalConsumerDelivery,
      ),
    applicationOperationalDeliveryAudit:
      normalizeApplicationOperationalDeliveryAuditCenter(
        raw.applicationOperationalDeliveryAudit,
      ),
    applicationDisasterRecovery:
      normalizeApplicationDisasterRecoveryCenter(
        raw.applicationDisasterRecovery,
      ),
    applicationPhysicalBackup:
      normalizeApplicationPhysicalBackupCenter(
        raw.applicationPhysicalBackup,
      ),
    applicationServiceReturn:
      normalizeApplicationServiceReturnCenter(
        raw.applicationServiceReturn,
      ),
    applicationProductionReadiness:
      normalizeApplicationProductionReadinessCenter(
        raw.applicationProductionReadiness,
      ),
    actions: Array.isArray(raw.actions)
      ? raw.actions.flatMap((item) => {
          const actionRaw = asRecord(item);
          const action = normalizeProviderSyncAction(actionRaw.action);
          if (!action) {
            return [];
          }
          return [
            {
              action,
              status: normalizeProviderSyncRunStatus(actionRaw.status),
              startedAt: toStringValue(actionRaw.startedAt),
              finishedAt: toNullableString(actionRaw.finishedAt),
              recordsProcessed: toNumber(actionRaw.recordsProcessed),
              revision: toNumber(actionRaw.revision, 1),
              attempt: toNumber(actionRaw.attempt, 1),
            },
          ];
        })
      : [],
  };
}

function normalizeProviderIncidentCenter(
  value: unknown,
): LeagueProviderIncidentCenter | null {
  const raw = nullableRecord(value);
  if (!raw) {
    return null;
  }

  return {
    protected: Boolean(raw.protected),
    healthy: Boolean(raw.healthy),
    activeCount: toNumber(raw.activeCount),
    criticalCount: toNumber(raw.criticalCount),
    warningCount: toNumber(raw.warningCount),
    resolvedLast24h: toNumber(raw.resolvedLast24h),
    lastIncidentAt: toNullableString(raw.lastIncidentAt),
    lastResolvedAt: toNullableString(raw.lastResolvedAt),
    incidents: Array.isArray(raw.incidents)
      ? raw.incidents.flatMap((item) => {
          const incidentRaw = asRecord(item);
          const action = normalizeProviderSyncAction(incidentRaw.syncType);
          const type =
            incidentRaw.type === 'data_quality'
              ? 'data_quality'
              : incidentRaw.type === 'sync_failure'
                ? 'sync_failure'
                : null;
          if (!action || !type) {
            return [];
          }
          return [
            {
              id: toStringValue(incidentRaw.id),
              type,
              syncType: action,
              severity:
                incidentRaw.severity === 'critical' ? 'critical' : 'warning',
              status:
                incidentRaw.status === 'resolved' ? 'resolved' : 'open',
              occurrenceCount: toNumber(incidentRaw.occurrenceCount, 1),
              revision: toNumber(incidentRaw.revision, 1),
              summary: toStringValue(incidentRaw.summary),
              firstDetectedAt: toStringValue(incidentRaw.firstDetectedAt),
              lastDetectedAt: toStringValue(incidentRaw.lastDetectedAt),
            },
          ];
        })
      : [],
  };
}

function normalizeProviderAutomaticRetryCenter(
  value: unknown,
): ProviderAutomaticRetryCenter | null {
  const raw = nullableRecord(value);
  if (!raw) {
    return null;
  }

  return {
    protected: Boolean(raw.protected),
    healthy: Boolean(raw.healthy),
    automaticRetryActive: Boolean(raw.automaticRetryActive),
    scheduledCount: toNumber(raw.scheduledCount),
    dueCount: toNumber(raw.dueCount),
    dispatchedCount: toNumber(raw.dispatchedCount),
    succeededLast24h: toNumber(raw.succeededLast24h),
    failedLast24h: toNumber(raw.failedLast24h),
    exhaustedOpenCount: toNumber(raw.exhaustedOpenCount),
    nextRetryAt: toNullableString(raw.nextRetryAt),
    maxRetries: toNumber(raw.maxRetries, 3),
  };
}

function normalizeProviderCircuitBreakerCenter(
  value: unknown,
): ProviderRecoveryCircuitBreakerCenter | null {
  const raw = nullableRecord(value);
  if (!raw) {
    return null;
  }

  const latestRaw = nullableRecord(raw.latestOpen);
  const latestAction = latestRaw
    ? normalizeProviderSyncAction(latestRaw.syncType)
    : null;
  const failureClass = latestRaw
    ? normalizeProviderCircuitFailureClass(latestRaw.failureClass)
    : 'unknown';

  return {
    protected: Boolean(raw.protected),
    healthy: Boolean(raw.healthy),
    blocked: Boolean(raw.blocked),
    openCount: toNumber(raw.openCount),
    releasedLast24h: toNumber(raw.releasedLast24h),
    resolvedLast24h: toNumber(raw.resolvedLast24h),
    latestOpen:
      latestRaw && latestAction
        ? {
            id: toStringValue(latestRaw.id),
            incidentId: toStringValue(latestRaw.incidentId),
            revision: toNumber(latestRaw.revision, 1),
            syncType: latestAction,
            failureClass,
            retryNo: toNumber(latestRaw.retryNo),
            maxRetries: toNumber(latestRaw.maxRetries, 3),
            summary: toStringValue(latestRaw.summary),
            openedAt: toStringValue(latestRaw.openedAt),
          }
        : null,
  };
}

function normalizeProviderOutcomeVerificationCenter(
  value: unknown,
): ProviderRecoveryOutcomeVerificationCenter | null {
  const raw = nullableRecord(value);
  if (!raw) {
    return null;
  }

  const latestRaw = nullableRecord(raw.latest);
  const latestAction = latestRaw
    ? normalizeProviderSyncAction(latestRaw.syncType)
    : null;
  const latestOutcome = latestRaw
    ? normalizeProviderOutcomeVerificationStatus(latestRaw.outcome)
    : null;

  return {
    protected: Boolean(raw.protected),
    healthy: Boolean(raw.healthy),
    outcomeVerificationActive: Boolean(raw.outcomeVerificationActive),
    verifiedLast24h: toNumber(raw.verifiedLast24h),
    ineffectiveLast24h: toNumber(raw.ineffectiveLast24h),
    activeRetryCount: toNumber(raw.activeRetryCount),
    exhaustedOpenCount: toNumber(raw.exhaustedOpenCount),
    latest:
      latestRaw && latestAction && latestOutcome
        ? {
            id: toStringValue(latestRaw.id),
            requestId: toStringValue(latestRaw.requestId),
            incidentId: toStringValue(latestRaw.incidentId),
            syncType: latestAction,
            outcome: latestOutcome,
            snapshotStatus:
              latestRaw.snapshotStatus === null ||
              latestRaw.snapshotStatus === undefined
                ? null
                : normalizeProviderDataQualityStatus(latestRaw.snapshotStatus),
            anomalyCount: toNumber(latestRaw.anomalyCount),
            retryNo:
              latestRaw.retryNo === null || latestRaw.retryNo === undefined
                ? null
                : toNumber(latestRaw.retryNo),
            maxRetries:
              latestRaw.maxRetries === null ||
              latestRaw.maxRetries === undefined
                ? null
                : toNumber(latestRaw.maxRetries),
            summary: toStringValue(latestRaw.summary),
            createdAt: toStringValue(latestRaw.createdAt),
          }
        : null,
  };
}

function normalizeProviderWorkerFencingCenter(
  value: unknown,
): ProviderWorkerFencingCenter | null {
  const raw = nullableRecord(value);
  if (!raw) {
    return null;
  }

  const latestRaw = nullableRecord(raw.latest);
  const latestAction = latestRaw
    ? normalizeProviderSyncAction(latestRaw.syncType)
    : null;
  const latestStatus =
    latestRaw?.status === 'released' ||
    latestRaw?.status === 'revoked' ||
    latestRaw?.status === 'expired'
      ? latestRaw.status
      : 'active';

  return {
    protected: Boolean(raw.protected),
    healthy: Boolean(raw.healthy),
    workerFencingActive: Boolean(raw.workerFencingActive),
    activeLeaseCount: toNumber(raw.activeLeaseCount),
    expiredLeaseCount: toNumber(raw.expiredLeaseCount),
    releasedLast24h: toNumber(raw.releasedLast24h),
    revokedLast24h: toNumber(raw.revokedLast24h),
    latestHeartbeatAt: toNullableString(raw.latestHeartbeatAt),
    latest:
      latestRaw && latestAction
        ? {
            runId: toStringValue(latestRaw.runId),
            requestId: toNullableString(latestRaw.requestId),
            syncType: latestAction,
            status: latestStatus,
            leaseEpoch: toNumber(latestRaw.leaseEpoch, 1),
            revision: toNumber(latestRaw.revision, 1),
            leaseExpiresAt: toStringValue(latestRaw.leaseExpiresAt),
            lastHeartbeatAt: toStringValue(latestRaw.lastHeartbeatAt),
          }
        : null,
  };
}

function normalizeProviderPayloadContractCenter(
  value: unknown,
): ProviderPayloadContractCenter | null {
  const raw = nullableRecord(value);
  if (!raw) {
    return null;
  }

  const latestRaw = nullableRecord(raw.latest);
  const latestAction = latestRaw
    ? normalizeProviderSyncAction(latestRaw.syncType)
    : null;

  return {
    protected: Boolean(raw.protected),
    healthy: Boolean(raw.healthy),
    runtimeValidationActive: Boolean(raw.runtimeValidationActive),
    databaseValidationActive: Boolean(raw.databaseValidationActive),
    payloadStorageDisabled: Boolean(raw.payloadStorageDisabled),
    contractVersion: toStringValue(raw.contractVersion),
    violationsLast24h: toNumber(raw.violationsLast24h),
    totalViolationCount: toNumber(raw.totalViolationCount),
    latestViolationAt: toNullableString(raw.latestViolationAt),
    latest:
      latestRaw && latestAction
        ? {
            id: toStringValue(latestRaw.id),
            runId: toStringValue(latestRaw.runId),
            requestId: toNullableString(latestRaw.requestId),
            syncType: latestAction,
            scope: toStringValue(latestRaw.scope),
            code: toStringValue(latestRaw.code),
            itemIndex:
              latestRaw.itemIndex === null || latestRaw.itemIndex === undefined
                ? null
                : toNumber(latestRaw.itemIndex),
            summary: toStringValue(latestRaw.summary),
            payloadSize: toNumber(latestRaw.payloadSize),
            detectedAt: toStringValue(latestRaw.detectedAt),
          }
        : null,
  };
}

function normalizeProviderDeliveryIntegrityCenter(
  value: unknown,
): ProviderDeliveryIntegrityCenter | null {
  const raw = nullableRecord(value);
  if (!raw) {
    return null;
  }

  const latestRaw = nullableRecord(raw.latest);
  const latestAction = latestRaw
    ? normalizeProviderSyncAction(latestRaw.syncType)
    : null;
  const latestStatus = latestRaw?.status === 'certified'
    ? 'certified'
    : latestRaw?.status === 'rejected'
      ? 'rejected'
      : 'collecting';

  return {
    protected: Boolean(raw.protected),
    healthy: Boolean(raw.healthy),
    deliveryValidationActive: Boolean(raw.deliveryValidationActive),
    completionGateActive: Boolean(raw.completionGateActive),
    rawEntityStorageDisabled: Boolean(raw.rawEntityStorageDisabled),
    deliveryVersion: toStringValue(raw.deliveryVersion),
    collectingCount: toNumber(raw.collectingCount),
    certifiedLast24h: toNumber(raw.certifiedLast24h),
    rejectedLast24h: toNumber(raw.rejectedLast24h),
    totalCertificateCount: toNumber(raw.totalCertificateCount),
    latestCertificateAt: toNullableString(raw.latestCertificateAt),
    latest:
      latestRaw && latestAction
        ? {
            id: toStringValue(latestRaw.id),
            runId: toStringValue(latestRaw.runId),
            requestId: toNullableString(latestRaw.requestId),
            syncType: latestAction,
            status: latestStatus,
            expectedUnitCount:
              latestRaw.expectedUnitCount === null ||
              latestRaw.expectedUnitCount === undefined
                ? null
                : toNumber(latestRaw.expectedUnitCount),
            observedUnitCount: toNumber(latestRaw.observedUnitCount),
            observedRecordCount: toNumber(latestRaw.observedRecordCount),
            uniqueEntityCount: toNumber(latestRaw.uniqueEntityCount),
            summary: toStringValue(latestRaw.summary),
            updatedAt: toStringValue(latestRaw.updatedAt),
          }
        : null,
  };
}

function normalizeProviderAtomicPublicationCenter(
  value: unknown,
): ProviderAtomicPublicationCenter | null {
  const raw = nullableRecord(value);
  if (!raw) {
    return null;
  }

  const latestRaw = nullableRecord(raw.latest);
  const latestAction = latestRaw
    ? normalizeProviderSyncAction(latestRaw.syncType)
    : null;
  const latestStatus = latestRaw?.status === 'published'
    ? 'published'
    : latestRaw?.status === 'discarded'
      ? 'discarded'
      : 'collecting';

  return {
    protected: Boolean(raw.protected),
    healthy: Boolean(raw.healthy),
    atomicStagingActive: Boolean(raw.atomicStagingActive),
    singleCommitPublicationActive: Boolean(
      raw.singleCommitPublicationActive,
    ),
    partialLiveWritesDisabled: Boolean(raw.partialLiveWritesDisabled),
    stagingPayloadPurgedAfterFinish: Boolean(
      raw.stagingPayloadPurgedAfterFinish,
    ),
    collectingCount: toNumber(raw.collectingCount),
    publishedLast24h: toNumber(raw.publishedLast24h),
    discardedLast24h: toNumber(raw.discardedLast24h),
    supersededLast24h: toNumber(raw.supersededLast24h),
    totalPublicationCount: toNumber(raw.totalPublicationCount),
    latestPublicationAt: toNullableString(raw.latestPublicationAt),
    latest:
      latestRaw && latestAction
        ? {
            id: toStringValue(latestRaw.id),
            runId: toStringValue(latestRaw.runId),
            requestId: toNullableString(latestRaw.requestId),
            syncType: latestAction,
            status: latestStatus,
            superseded: Boolean(latestRaw.superseded),
            stagedRowCount: toNumber(latestRaw.stagedRowCount),
            stagedPrimaryRecordCount: toNumber(
              latestRaw.stagedPrimaryRecordCount,
            ),
            publishedPrimaryRecordCount: toNumber(
              latestRaw.publishedPrimaryRecordCount,
            ),
            summary: toStringValue(latestRaw.summary),
            updatedAt: toStringValue(latestRaw.updatedAt),
          }
        : null,
  };
}

function normalizeProviderSemanticScopeCenter(
  value: unknown,
): ProviderSemanticScopeCenter | null {
  const raw = nullableRecord(value);
  if (!raw) {
    return null;
  }

  const latestRaw = nullableRecord(raw.latest);
  const latestAction = latestRaw
    ? normalizeProviderSyncAction(latestRaw.syncType)
    : null;
  const latestScopeKind = latestRaw?.scopeKind === 'season'
    ? 'season'
    : latestRaw?.scopeKind === 'date'
      ? 'date'
      : 'fixture';
  const latestStatus = latestRaw?.status === 'certified'
    ? 'certified'
    : latestRaw?.status === 'rejected'
      ? 'rejected'
      : 'collecting';

  return {
    protected: Boolean(raw.protected),
    healthy: Boolean(raw.healthy),
    semanticScopeActive: Boolean(raw.semanticScopeActive),
    operationBindingActive: Boolean(raw.operationBindingActive),
    crossEntityValidationActive: Boolean(raw.crossEntityValidationActive),
    legacyBypassDisabled: Boolean(raw.legacyBypassDisabled),
    collectingCount: toNumber(raw.collectingCount),
    certifiedLast24h: toNumber(raw.certifiedLast24h),
    rejectedLast24h: toNumber(raw.rejectedLast24h),
    totalCertificateCount: toNumber(raw.totalCertificateCount),
    latestCertificateAt: toNullableString(raw.latestCertificateAt),
    latest:
      latestRaw && latestAction
        ? {
            id: toStringValue(latestRaw.id),
            runId: toStringValue(latestRaw.runId),
            publicationId: toStringValue(latestRaw.publicationId),
            requestId: toNullableString(latestRaw.requestId),
            syncType: latestAction,
            scopeKind: latestScopeKind,
            status: latestStatus,
            observedAthleteCount: toNumber(latestRaw.observedAthleteCount),
            observedRoleCount: toNumber(latestRaw.observedRoleCount),
            observedMatchdayCount: toNumber(latestRaw.observedMatchdayCount),
            observedFixtureCount: toNumber(latestRaw.observedFixtureCount),
            observedScoreCount: toNumber(latestRaw.observedScoreCount),
            summary: toStringValue(latestRaw.summary),
            updatedAt: toStringValue(latestRaw.updatedAt),
          }
        : null,
  };
}

function normalizeProviderScopeWatermarkCenter(
  value: unknown,
): ProviderScopeWatermarkCenter | null {
  const raw = nullableRecord(value);
  if (!raw) {
    return null;
  }

  const latestRaw = nullableRecord(raw.latest);
  const eventType = latestRaw?.eventType === 'stale_rejected'
    ? 'stale_rejected'
    : latestRaw?.eventType === 'advanced'
      ? 'advanced'
      : 'backfilled';

  return {
    protected: Boolean(raw.protected),
    healthy: Boolean(raw.healthy),
    monotonicOrderingActive: Boolean(raw.monotonicOrderingActive),
    stalePublicationBlocked: Boolean(raw.stalePublicationBlocked),
    completionBypassDisabled: Boolean(raw.completionBypassDisabled),
    globalScopeSerialized: Boolean(raw.globalScopeSerialized),
    activeWatermarkCount: toNumber(raw.activeWatermarkCount),
    advancedLast24h: toNumber(raw.advancedLast24h),
    staleRejectedLast24h: toNumber(raw.staleRejectedLast24h),
    latestWatermarkAt: toNullableString(raw.latestWatermarkAt),
    latest: latestRaw
      ? {
          id: toStringValue(latestRaw.id),
          watermarkId: toStringValue(latestRaw.watermarkId),
          eventType,
          candidateRunId: toStringValue(latestRaw.candidateRunId),
          candidatePublicationId: toStringValue(
            latestRaw.candidatePublicationId,
          ),
          latestRunId: toStringValue(latestRaw.latestRunId),
          generation: toNumber(latestRaw.generation, 1),
          candidateStartedAt: toStringValue(latestRaw.candidateStartedAt),
          latestStartedAt: toStringValue(latestRaw.latestStartedAt),
          recordCount: toNumber(latestRaw.recordCount),
          reasonCode: toStringValue(latestRaw.reasonCode),
          createdAt: toStringValue(latestRaw.createdAt),
        }
      : null,
  };
}

function normalizeProviderPlayerCatalogCenter(
  value: unknown,
): ProviderPlayerCatalogCenter | null {
  const raw = nullableRecord(value);
  if (!raw) {
    return null;
  }

  const headRaw = nullableRecord(raw.head);
  const latestRaw = nullableRecord(raw.latest);
  const headTransition = headRaw?.lastTransition === 'advanced'
    ? 'advanced'
    : headRaw?.lastTransition === 'refreshed'
      ? 'refreshed'
      : 'backfilled';
  const latestStatus = latestRaw?.status === 'applied'
    ? 'applied'
    : latestRaw?.status === 'superseded'
      ? 'superseded'
      : 'collecting';

  return {
    protected: Boolean(raw.protected),
    healthy: Boolean(raw.healthy),
    authoritativeSnapshotActive: Boolean(raw.authoritativeSnapshotActive),
    historicalSeasonRegressionBlocked: Boolean(
      raw.historicalSeasonRegressionBlocked,
    ),
    missingPlayersSoftDeactivated: Boolean(raw.missingPlayersSoftDeactivated),
    exactRoleReplacementActive: Boolean(raw.exactRoleReplacementActive),
    physicalPlayerDeletionDisabled: Boolean(raw.physicalPlayerDeletionDisabled),
    collectingCount: toNumber(raw.collectingCount),
    appliedLast24h: toNumber(raw.appliedLast24h),
    supersededLast24h: toNumber(raw.supersededLast24h),
    deactivatedPlayersLast24h: toNumber(raw.deactivatedPlayersLast24h),
    removedRolesLast24h: toNumber(raw.removedRolesLast24h),
    rosteredRetiredTotal: toNumber(raw.rosteredRetiredTotal),
    totalReconciliationCount: toNumber(raw.totalReconciliationCount),
    latestReconciliationAt: toNullableString(raw.latestReconciliationAt),
    head: headRaw
      ? {
          id: toStringValue(headRaw.id),
          provider: toStringValue(headRaw.provider),
          competitionCode: toStringValue(headRaw.competitionCode),
          season: toNumber(headRaw.season),
          activePlayerCount: toNumber(headRaw.activePlayerCount),
          generation: toNumber(headRaw.generation, 1),
          lastTransition: headTransition,
          summary: toStringValue(headRaw.summary),
          updatedAt: toStringValue(headRaw.updatedAt),
        }
      : null,
    latest: latestRaw
      ? {
          id: toStringValue(latestRaw.id),
          runId: toStringValue(latestRaw.runId),
          publicationId: toStringValue(latestRaw.publicationId),
          requestId: toNullableString(latestRaw.requestId),
          season: toNumber(latestRaw.season),
          status: latestStatus,
          observedPlayerCount: toNumber(latestRaw.observedPlayerCount),
          deactivatedPlayerCount: toNumber(latestRaw.deactivatedPlayerCount),
          authoritativeRoleCount: toNumber(latestRaw.authoritativeRoleCount),
          removedRoleCount: toNumber(latestRaw.removedRoleCount),
          rosteredRetiredCount: toNumber(latestRaw.rosteredRetiredCount),
          generation:
            latestRaw.generation === null || latestRaw.generation === undefined
              ? null
              : toNumber(latestRaw.generation, 1),
          reasonCode: toStringValue(latestRaw.reasonCode),
          summary: toStringValue(latestRaw.summary),
          updatedAt: toStringValue(latestRaw.updatedAt),
        }
      : null,
  };
}

function normalizeProviderFixtureLifecycleCenter(
  value: unknown,
): ProviderFixtureLifecycleCenter | null {
  const raw = nullableRecord(value);
  if (!raw) {
    return null;
  }

  const headRaw = nullableRecord(raw.head);
  const latestRaw = nullableRecord(raw.latest);
  const currentState =
    headRaw?.currentState === 'live' ||
    headRaw?.currentState === 'interrupted' ||
    headRaw?.currentState === 'cancelled' ||
    headRaw?.currentState === 'final'
      ? headRaw.currentState
      : 'scheduled';
  const lastTransition =
    headRaw?.lastTransition === 'created' ||
    headRaw?.lastTransition === 'advanced' ||
    headRaw?.lastTransition === 'refreshed' ||
    headRaw?.lastTransition === 'final_corrected'
      ? headRaw.lastTransition
      : 'backfilled';
  const latestStatus = latestRaw?.status === 'applied'
    ? 'applied'
    : 'collecting';

  return {
    protected: Boolean(raw.protected),
    healthy: Boolean(raw.healthy),
    monotonicFixtureLifecycleActive: Boolean(
      raw.monotonicFixtureLifecycleActive,
    ),
    finalToNonFinalRegressionBlocked: Boolean(
      raw.finalToNonFinalRegressionBlocked,
    ),
    finalGoalsPreserved: Boolean(raw.finalGoalsPreserved),
    finalTeamIdentityLocked: Boolean(raw.finalTeamIdentityLocked),
    physicalFixtureDeletionDisabled: Boolean(
      raw.physicalFixtureDeletionDisabled,
    ),
    collectingCount: toNumber(raw.collectingCount),
    appliedLast24h: toNumber(raw.appliedLast24h),
    createdFixturesLast24h: toNumber(raw.createdFixturesLast24h),
    advancedFixturesLast24h: toNumber(raw.advancedFixturesLast24h),
    finalCorrectionsLast24h: toNumber(raw.finalCorrectionsLast24h),
    totalReconciliationCount: toNumber(raw.totalReconciliationCount),
    latestReconciliationAt: toNullableString(raw.latestReconciliationAt),
    head: headRaw
      ? {
          id: toStringValue(headRaw.id),
          fixtureIdFingerprint: toStringValue(
            headRaw.fixtureIdFingerprint,
          ),
          currentState,
          currentStatus: toStringValue(headRaw.currentStatus),
          generation: toNumber(headRaw.generation, 1),
          lastTransition,
          summary: toStringValue(headRaw.summary),
          updatedAt: toStringValue(headRaw.updatedAt),
        }
      : null,
    latest: latestRaw
      ? {
          id: toStringValue(latestRaw.id),
          runId: toStringValue(latestRaw.runId),
          publicationId: toStringValue(latestRaw.publicationId),
          requestId: toNullableString(latestRaw.requestId),
          requestedDate: toStringValue(latestRaw.requestedDate),
          status: latestStatus,
          observedFixtureCount: toNumber(latestRaw.observedFixtureCount),
          finalFixtureCount: toNumber(latestRaw.finalFixtureCount),
          createdFixtureCount: toNumber(latestRaw.createdFixtureCount),
          advancedFixtureCount: toNumber(latestRaw.advancedFixtureCount),
          finalCorrectionCount: toNumber(latestRaw.finalCorrectionCount),
          maxGeneration:
            latestRaw.maxGeneration === null ||
            latestRaw.maxGeneration === undefined
              ? null
              : toNumber(latestRaw.maxGeneration, 1),
          reasonCode: toStringValue(latestRaw.reasonCode),
          summary: toStringValue(latestRaw.summary),
          updatedAt: toStringValue(latestRaw.updatedAt),
        }
      : null,
  };
}

function normalizeProviderFixtureScoreCenter(
  value: unknown,
): ProviderFixtureScoreCenter | null {
  const raw = nullableRecord(value);
  if (!raw) {
    return null;
  }

  const latestRaw = nullableRecord(raw.latest);
  const latestStatus = latestRaw?.status === 'applied'
    ? 'applied'
    : 'collecting';

  return {
    protected: Boolean(raw.protected),
    healthy: Boolean(raw.healthy),
    authoritativeFixtureSnapshotActive: Boolean(
      raw.authoritativeFixtureSnapshotActive,
    ),
    finalToProvisionalRegressionBlocked: Boolean(
      raw.finalToProvisionalRegressionBlocked,
    ),
    missingFinalScoresSoftRetired: Boolean(
      raw.missingFinalScoresSoftRetired,
    ),
    physicalScoreDeletionDisabled: Boolean(raw.physicalScoreDeletionDisabled),
    twoTeamFinalCoverageRequired: Boolean(raw.twoTeamFinalCoverageRequired),
    collectingCount: toNumber(raw.collectingCount),
    appliedLast24h: toNumber(raw.appliedLast24h),
    finalAppliedLast24h: toNumber(raw.finalAppliedLast24h),
    retiredScoresLast24h: toNumber(raw.retiredScoresLast24h),
    restoredScoresLast24h: toNumber(raw.restoredScoresLast24h),
    totalReconciliationCount: toNumber(raw.totalReconciliationCount),
    latestReconciliationAt: toNullableString(raw.latestReconciliationAt),
    latest: latestRaw
      ? {
          id: toStringValue(latestRaw.id),
          runId: toStringValue(latestRaw.runId),
          publicationId: toStringValue(latestRaw.publicationId),
          requestId: toNullableString(latestRaw.requestId),
          fixtureIdFingerprint: toStringValue(
            latestRaw.fixtureIdFingerprint,
          ),
          fixtureStatus: toStringValue(latestRaw.fixtureStatus),
          isFinal: Boolean(latestRaw.isFinal),
          status: latestStatus,
          observedScoreCount: toNumber(latestRaw.observedScoreCount),
          homeScoreCount: toNumber(latestRaw.homeScoreCount),
          awayScoreCount: toNumber(latestRaw.awayScoreCount),
          retiredScoreCount: toNumber(latestRaw.retiredScoreCount),
          restoredScoreCount: toNumber(latestRaw.restoredScoreCount),
          generation:
            latestRaw.generation === null || latestRaw.generation === undefined
              ? null
              : toNumber(latestRaw.generation, 1),
          reasonCode: toStringValue(latestRaw.reasonCode),
          summary: toStringValue(latestRaw.summary),
          updatedAt: toStringValue(latestRaw.updatedAt),
        }
      : null,
  };
}


function normalizeProviderFixtureScoreCoherenceCenter(
  value: unknown,
): ProviderFixtureScoreCoherenceCenter | null {
  const raw = nullableRecord(value);
  if (!raw) {
    return null;
  }

  const latestHeadRaw = nullableRecord(raw.latestHead);
  const latestEventRaw = nullableRecord(raw.latestEvent);
  const normalizeStatus = (status: unknown): 'aligned' | 'stale' | 'missing' =>
    status === 'aligned' || status === 'stale' ? status : 'missing';

  return {
    protected: Boolean(raw.protected),
    healthy: Boolean(raw.healthy),
    causalFixtureScoreBindingActive: Boolean(
      raw.causalFixtureScoreBindingActive,
    ),
    fixtureGenerationAdvanceInvalidatesScores: Boolean(
      raw.fixtureGenerationAdvanceInvalidatesScores,
    ),
    concurrentLifecycleChangeDetected: Boolean(
      raw.concurrentLifecycleChangeDetected,
    ),
    scoreValuesPreservedWhileStale: Boolean(
      raw.scoreValuesPreservedWhileStale,
    ),
    alignedCount: toNumber(raw.alignedCount),
    staleCount: toNumber(raw.staleCount),
    missingCount: toNumber(raw.missingCount),
    finalMissingCount: toNumber(raw.finalMissingCount),
    eventsLast24h: toNumber(raw.eventsLast24h),
    latestHead: latestHeadRaw
      ? {
          id: toStringValue(latestHeadRaw.id),
          fixtureIdFingerprint: toStringValue(
            latestHeadRaw.fixtureIdFingerprint,
          ),
          scoreGeneration: toNumber(latestHeadRaw.scoreGeneration, 1),
          fixtureLifecycleGeneration:
            latestHeadRaw.fixtureLifecycleGeneration === null ||
            latestHeadRaw.fixtureLifecycleGeneration === undefined
              ? null
              : toNumber(latestHeadRaw.fixtureLifecycleGeneration, 1),
          fixtureLifecycleRevision:
            latestHeadRaw.fixtureLifecycleRevision === null ||
            latestHeadRaw.fixtureLifecycleRevision === undefined
              ? null
              : toNumber(latestHeadRaw.fixtureLifecycleRevision, 1),
          coherenceStatus: normalizeStatus(
            latestHeadRaw.coherenceStatus,
          ),
          reasonCode: toStringValue(latestHeadRaw.reasonCode),
          checkedAt: toNullableString(latestHeadRaw.checkedAt),
        }
      : null,
    latestEvent: latestEventRaw
      ? {
          id: toStringValue(latestEventRaw.id),
          eventType: normalizeStatus(latestEventRaw.eventType),
          fixtureIdFingerprint: toStringValue(
            latestEventRaw.fixtureIdFingerprint,
          ),
          scoreGeneration: toNumber(latestEventRaw.scoreGeneration, 1),
          fixtureLifecycleGeneration:
            latestEventRaw.fixtureLifecycleGeneration === null ||
            latestEventRaw.fixtureLifecycleGeneration === undefined
              ? null
              : toNumber(latestEventRaw.fixtureLifecycleGeneration, 1),
          fixtureLifecycleRevision:
            latestEventRaw.fixtureLifecycleRevision === null ||
            latestEventRaw.fixtureLifecycleRevision === undefined
              ? null
              : toNumber(latestEventRaw.fixtureLifecycleRevision, 1),
          coherenceStatus: normalizeStatus(
            latestEventRaw.coherenceStatus,
          ),
          reasonCode: toStringValue(latestEventRaw.reasonCode),
          createdAt: toStringValue(latestEventRaw.createdAt),
        }
      : null,
  };
}


function normalizeProviderScoreConsumptionGateCenter(
  value: unknown,
): ProviderScoreConsumptionGateCenter | null {
  const raw = nullableRecord(value);
  if (!raw) {
    return null;
  }

  const latestEventRaw = nullableRecord(raw.latestEvent);
  return {
    protected: Boolean(raw.protected),
    healthy: Boolean(raw.healthy),
    officialResultConsumptionGateActive: Boolean(
      raw.officialResultConsumptionGateActive,
    ),
    staleScoresExcludedFromCalculations: Boolean(
      raw.staleScoresExcludedFromCalculations,
    ),
    blockedScoresCannotTriggerSubstitutions: Boolean(
      raw.blockedScoresCannotTriggerSubstitutions,
    ),
    scoreValuesPreservedWhileBlocked: Boolean(
      raw.scoreValuesPreservedWhileBlocked,
    ),
    trustedHeadCount: toNumber(raw.trustedHeadCount),
    blockedHeadCount: toNumber(raw.blockedHeadCount),
    staleHeadCount: toNumber(raw.staleHeadCount),
    missingHeadCount: toNumber(raw.missingHeadCount),
    blockedScoreCount: toNumber(raw.blockedScoreCount),
    blockedMatchdayCount: toNumber(raw.blockedMatchdayCount),
    officialFixtureRiskCount: toNumber(raw.officialFixtureRiskCount),
    eventsLast24h: toNumber(raw.eventsLast24h),
    latestEvent: latestEventRaw
      ? {
          id: toStringValue(latestEventRaw.id),
          fixtureIdFingerprint: toStringValue(
            latestEventRaw.fixtureIdFingerprint,
          ),
          gateStatus:
            latestEventRaw.gateStatus === 'trusted' ? 'trusted' : 'blocked',
          reasonCode: toStringValue(latestEventRaw.reasonCode),
          scoreGeneration: toNumber(latestEventRaw.scoreGeneration, 1),
          fixtureLifecycleGeneration:
            latestEventRaw.fixtureLifecycleGeneration === null ||
            latestEventRaw.fixtureLifecycleGeneration === undefined
              ? null
              : toNumber(latestEventRaw.fixtureLifecycleGeneration, 1),
          createdAt: toStringValue(latestEventRaw.createdAt),
        }
      : null,
  };
}


function normalizeProviderOfficialResultImpactCenter(
  value: unknown,
): ProviderOfficialResultImpactCenter | null {
  const raw = nullableRecord(value);
  if (!raw) {
    return null;
  }

  const latestEventRaw = nullableRecord(raw.latestEvent);
  const impactStatus = latestEventRaw?.impactStatus;
  return {
    protected: Boolean(raw.protected),
    healthy: Boolean(raw.healthy),
    preciseOfficialResultLineageActive: Boolean(
      raw.preciseOfficialResultLineageActive,
    ),
    officialResultsNeverMutatedAutomatically: Boolean(
      raw.officialResultsNeverMutatedAutomatically,
    ),
    protectedCorrectionWorkflowAvailable: Boolean(
      raw.protectedCorrectionWorkflowAvailable,
    ),
    clearFixtureCount: toNumber(raw.clearFixtureCount),
    affectedFixtureCount: toNumber(raw.affectedFixtureCount),
    inCorrectionFixtureCount: toNumber(raw.inCorrectionFixtureCount),
    affectedMatchdayCount: toNumber(raw.affectedMatchdayCount),
    eventsLast24h: toNumber(raw.eventsLast24h),
    latestEvent: latestEventRaw
      ? {
          id: toStringValue(latestEventRaw.id),
          fixtureId: toStringValue(latestEventRaw.fixtureId),
          matchdayId: toStringValue(latestEventRaw.matchdayId),
          impactStatus:
            impactStatus === 'affected' || impactStatus === 'in_correction'
              ? impactStatus
              : 'clear',
          reasonCode: toStringValue(latestEventRaw.reasonCode),
          assessmentGeneration: toNumber(
            latestEventRaw.assessmentGeneration,
            1,
          ),
          affectedSideCount: toNumber(latestEventRaw.affectedSideCount),
          createdAt: toStringValue(latestEventRaw.createdAt),
        }
      : null,
  };
}


function normalizeProviderOfficialResultRemediationCenter(
  value: unknown,
): ProviderOfficialResultRemediationCenter | null {
  const raw = nullableRecord(value);
  if (!raw) {
    return null;
  }

  return {
    protected: Boolean(raw.protected),
    healthy: Boolean(raw.healthy),
    raceSafeRemediationActive: Boolean(raw.raceSafeRemediationActive),
    staleAssessmentRejected: Boolean(raw.staleAssessmentRejected),
    resultsNeverMutatedAutomatically: Boolean(
      raw.resultsNeverMutatedAutomatically,
    ),
    openCount: toNumber(raw.openCount),
    inCorrectionCount: toNumber(raw.inCorrectionCount),
    resolvedCount: toNumber(raw.resolvedCount),
    uncertifiedCorrectionCount: toNumber(raw.uncertifiedCorrectionCount),
    eventsLast24h: toNumber(raw.eventsLast24h),
    items: Array.isArray(raw.items)
      ? raw.items.flatMap((item) => {
          const itemRaw = nullableRecord(item);
          if (!itemRaw) {
            return [];
          }
          const status = itemRaw.remediationStatus;
          if (status !== 'open' && status !== 'in_correction') {
            return [];
          }
          return [{
            headId: toStringValue(itemRaw.headId),
            fixtureId: toStringValue(itemRaw.fixtureId),
            matchdayId: toStringValue(itemRaw.matchdayId),
            matchdayNumber: toNumber(itemRaw.matchdayNumber),
            homeTeamName: toStringValue(itemRaw.homeTeamName),
            awayTeamName: toStringValue(itemRaw.awayTeamName),
            impactAssessmentGeneration: toNumber(
              itemRaw.impactAssessmentGeneration,
              1,
            ),
            remediationGeneration: toNumber(
              itemRaw.remediationGeneration,
              1,
            ),
            remediationStatus: status,
            causalStartCertified: Boolean(itemRaw.causalStartCertified),
            correctionRunId: toNullableNumber(itemRaw.correctionRunId),
            openedAt: toStringValue(itemRaw.openedAt),
            startedAt: toNullableString(itemRaw.startedAt),
            impactReasonCode: toStringValue(itemRaw.impactReasonCode),
          }];
        })
      : [],
  };
}

function normalizeProviderOfficialResultLineageCenter(
  value: unknown,
): ProviderOfficialResultLineageCenter | null {
  const raw = nullableRecord(value);
  if (!raw) {
    return null;
  }

  const latestEventRaw = nullableRecord(raw.latestEvent);
  const latestStatus = latestEventRaw?.lineageStatus;

  return {
    protected: Boolean(raw.protected),
    healthy: Boolean(raw.healthy),
    officializationCommitBarrierActive: Boolean(
      raw.officializationCommitBarrierActive,
    ),
    transientMissingLineageSuppressed: Boolean(
      raw.transientMissingLineageSuppressed,
    ),
    correctionSourceLinkCertified: Boolean(
      raw.correctionSourceLinkCertified,
    ),
    certifiedFixtureCount: toNumber(raw.certifiedFixtureCount),
    assemblingFixtureCount: toNumber(raw.assemblingFixtureCount),
    invalidFixtureCount: toNumber(raw.invalidFixtureCount),
    reopenedFixtureCount: toNumber(raw.reopenedFixtureCount),
    eventsLast24h: toNumber(raw.eventsLast24h),
    latestEvent: latestEventRaw
      ? {
          id: toStringValue(latestEventRaw.id),
          fixtureId: toStringValue(latestEventRaw.fixtureId),
          matchdayId: toStringValue(latestEventRaw.matchdayId),
          lineageStatus:
            latestStatus === 'reopened' ||
            latestStatus === 'assembling' ||
            latestStatus === 'invalid'
              ? latestStatus
              : 'certified',
          reasonCode: toStringValue(latestEventRaw.reasonCode),
          lineageGeneration: toNumber(
            latestEventRaw.lineageGeneration,
            1,
          ),
          fixtureResultRevision: toNumber(
            latestEventRaw.fixtureResultRevision,
          ),
          createdAt: toStringValue(latestEventRaw.createdAt),
        }
      : null,
  };
}

function normalizeProviderOfficialResultRemediationCompletionCenter(
  value: unknown,
): ProviderOfficialResultRemediationCompletionCenter | null {
  const raw = nullableRecord(value);
  if (!raw) {
    return null;
  }

  const latestEventRaw = nullableRecord(raw.latestEvent);
  const latestEventType = latestEventRaw?.eventType;
  const latestStatus = latestEventRaw?.completionStatus;
  const latestMode = latestEventRaw?.resolutionMode;

  return {
    protected: Boolean(raw.protected),
    healthy: Boolean(raw.healthy),
    causalCompletionCertificateActive: Boolean(
      raw.causalCompletionCertificateActive,
    ),
    resolvedOnlyAfterCertifiedEvidence: Boolean(
      raw.resolvedOnlyAfterCertifiedEvidence,
    ),
    automaticRecoveryDistinguished: Boolean(
      raw.automaticRecoveryDistinguished,
    ),
    pendingCount: toNumber(raw.pendingCount),
    certifiedCount: toNumber(raw.certifiedCount),
    invalidCount: toNumber(raw.invalidCount),
    supersededCount: toNumber(raw.supersededCount),
    autoRecoveredCount: toNumber(raw.autoRecoveredCount),
    correctionCertifiedCount: toNumber(raw.correctionCertifiedCount),
    uncertifiedResolvedCount: toNumber(raw.uncertifiedResolvedCount),
    eventsLast24h: toNumber(raw.eventsLast24h),
    latestEvent: latestEventRaw
      ? {
          id: toStringValue(latestEventRaw.id),
          fixtureId: toStringValue(latestEventRaw.fixtureId),
          matchdayId: toStringValue(latestEventRaw.matchdayId),
          eventType:
            latestEventType === 'certified' ||
            latestEventType === 'invalid' ||
            latestEventType === 'superseded' ||
            latestEventType === 'revalidated'
              ? latestEventType
              : 'pending',
          completionStatus:
            latestStatus === 'certified' ||
            latestStatus === 'invalid' ||
            latestStatus === 'superseded'
              ? latestStatus
              : 'pending',
          resolutionMode:
            latestMode === 'auto_recovered' ||
            latestMode === 'correction_certified'
              ? latestMode
              : 'none',
          reasonCode: toStringValue(latestEventRaw.reasonCode),
          remediationGeneration: toNumber(
            latestEventRaw.remediationGeneration,
            1,
          ),
          completionGeneration: toNumber(
            latestEventRaw.completionGeneration,
            1,
          ),
          createdAt: toStringValue(latestEventRaw.createdAt),
        }
      : null,
  };
}

function normalizeProviderMatchdayProgressionGateCenter(
  value: unknown,
): ProviderMatchdayProgressionGateCenter | null {
  const raw = nullableRecord(value);
  if (!raw) {
    return null;
  }
  const latestEventRaw = nullableRecord(raw.latestEvent);
  const eventType = latestEventRaw?.eventType;
  const gateStatus = latestEventRaw?.gateStatus;
  return {
    protected: Boolean(raw.protected),
    healthy: Boolean(raw.healthy),
    causalProgressionBarrierActive: Boolean(raw.causalProgressionBarrierActive),
    legacyProgressionBypassBlocked: Boolean(raw.legacyProgressionBypassBlocked),
    priorMatchdayChainProtected: Boolean(raw.priorMatchdayChainProtected),
    clearMatchdayCount: toNumber(raw.clearMatchdayCount),
    blockedMatchdayCount: toNumber(raw.blockedMatchdayCount),
    affectedMatchdayCount: toNumber(raw.affectedMatchdayCount),
    unsafeProgressionCount: toNumber(raw.unsafeProgressionCount),
    eventsLast24h: toNumber(raw.eventsLast24h),
    latestEvent: latestEventRaw
      ? {
          id: toStringValue(latestEventRaw.id),
          matchdayId: toStringValue(latestEventRaw.matchdayId),
          matchdayNumber: toNumber(latestEventRaw.matchdayNumber),
          eventType:
            eventType === 'blocked' ||
            eventType === 'affected' ||
            eventType === 'revalidated'
              ? eventType
              : 'clear',
          gateStatus:
            gateStatus === 'blocked' || gateStatus === 'affected'
              ? gateStatus
              : 'clear',
          reasonCode: toStringValue(latestEventRaw.reasonCode),
          gateGeneration: toNumber(latestEventRaw.gateGeneration, 1),
          currentOfficializationRunId:
            toNullableString(latestEventRaw.currentOfficializationRunId),
          currentProgressionRunId:
            toNullableString(latestEventRaw.currentProgressionRunId),
          unsafeFixtureCount: toNumber(latestEventRaw.unsafeFixtureCount),
          priorUnsafeProgressionCount: toNumber(
            latestEventRaw.priorUnsafeProgressionCount,
          ),
          createdAt: toStringValue(latestEventRaw.createdAt),
        }
      : null,
  };
}

function normalizeProviderSeasonCompletionGateCenter(
  value: unknown,
): ProviderSeasonCompletionGateCenter | null {
  const raw = nullableRecord(value);
  if (!raw) {
    return null;
  }
  const latestEventRaw = nullableRecord(raw.latestEvent);
  const eventType = latestEventRaw?.eventType;
  const gateStatus = raw.gateStatus;
  const latestGateStatus = latestEventRaw?.gateStatus;
  return {
    protected: Boolean(raw.protected),
    healthy: Boolean(raw.healthy),
    causalSeasonCompletionBarrierActive: Boolean(
      raw.causalSeasonCompletionBarrierActive,
    ),
    legacySeasonCompletionBypassBlocked: Boolean(
      raw.legacySeasonCompletionBypassBlocked,
    ),
    progressionChainLocked: Boolean(raw.progressionChainLocked),
    gateStatus:
      gateStatus === 'clear' || gateStatus === 'affected'
        ? gateStatus
        : 'blocked',
    reasonCode: toStringValue(raw.reasonCode),
    completionRunId: toNullableIdentifier(raw.completionRunId),
    finalMatchdayId: toNullableString(raw.finalMatchdayId),
    finalProgressionRunId: toNullableString(raw.finalProgressionRunId),
    matchdayCount: toNumber(raw.matchdayCount),
    clearMatchdayCount: toNumber(raw.clearMatchdayCount),
    unsafeMatchdayCount: toNumber(raw.unsafeMatchdayCount),
    missingGateCount: toNumber(raw.missingGateCount),
    mismatchedProgressionCount: toNumber(raw.mismatchedProgressionCount),
    completionAffected: Boolean(raw.completionAffected),
    eventsLast24h: toNumber(raw.eventsLast24h),
    latestEvent: latestEventRaw
      ? {
          id: toStringValue(latestEventRaw.id),
          eventType:
            eventType === 'blocked' ||
            eventType === 'affected' ||
            eventType === 'revalidated'
              ? eventType
              : 'clear',
          gateStatus:
            latestGateStatus === 'clear' || latestGateStatus === 'affected'
              ? latestGateStatus
              : 'blocked',
          reasonCode: toStringValue(latestEventRaw.reasonCode),
          gateGeneration: toNumber(latestEventRaw.gateGeneration, 1),
          currentCompletionRunId: toNullableString(
            latestEventRaw.currentCompletionRunId,
          ),
          finalMatchdayId: toNullableString(latestEventRaw.finalMatchdayId),
          finalProgressionRunId: toNullableString(
            latestEventRaw.finalProgressionRunId,
          ),
          unsafeMatchdayCount: toNumber(latestEventRaw.unsafeMatchdayCount),
          missingGateCount: toNumber(latestEventRaw.missingGateCount),
          mismatchedProgressionCount: toNumber(
            latestEventRaw.mismatchedProgressionCount,
          ),
          createdAt: toStringValue(latestEventRaw.createdAt),
        }
      : null,
  };
}

function normalizeProviderSeasonBootstrapCenter(
  value: unknown,
): ProviderSeasonBootstrapCenter | null {
  const raw = nullableRecord(value);
  if (!raw) {
    return null;
  }

  const status = raw.status === 'catalog_ready'
    ? 'catalog_ready'
    : raw.status === 'ready'
      ? 'ready'
      : raw.status === 'affected'
        ? 'affected'
        : 'waiting';

  return {
    protected: Boolean(raw.protected),
    applicable: Boolean(raw.applicable),
    healthy: raw.healthy === undefined ? true : Boolean(raw.healthy),
    affected: Boolean(raw.affected),
    status,
    reasonCode: toStringValue(raw.reasonCode),
    season: toNullableNumber(raw.season),
    catalogReady: Boolean(raw.catalogReady),
    fixturesReady: Boolean(raw.fixturesReady),
    certified: Boolean(raw.certified),
    certificateId: toNullableNumber(raw.certificateId),
    bootstrapHash: toNullableString(raw.bootstrapHash),
    catalogGeneration: toNullableNumber(raw.catalogGeneration),
    catalogPlayerCount: toNumber(raw.catalogPlayerCount),
    fixtureCount: toNumber(raw.fixtureCount),
    matchdayCount: toNumber(raw.matchdayCount),
    fixtureTeamCount: toNumber(raw.fixtureTeamCount),
  };
}

function normalizeProviderCompetitionStartCenter(
  value: unknown,
): ProviderCompetitionStartCenter | null {
  const raw = nullableRecord(value);
  if (!raw) {
    return null;
  }
  const status =
    raw.status === 'ready' ||
    raw.status === 'official' ||
    raw.status === 'affected'
      ? raw.status
      : 'waiting';
  return {
    protected: Boolean(raw.protected),
    applicable: Boolean(raw.applicable),
    healthy: raw.healthy === undefined ? true : Boolean(raw.healthy),
    affected: Boolean(raw.affected),
    status,
    reasonCode: toStringValue(raw.reasonCode),
    started: Boolean(raw.started),
    ready: Boolean(raw.ready),
    certified: Boolean(raw.certified),
    certificateId: toNullableNumber(raw.certificateId),
    startHash: toNullableString(raw.startHash),
    season: toNullableNumber(raw.season),
    fantasyFixtureCount: toNumber(raw.fantasyFixtureCount),
    fantasyMatchdayCount: toNumber(raw.fantasyMatchdayCount),
    fantasyTeamCount: toNumber(raw.fantasyTeamCount),
  };
}

function normalizeProviderReliabilityModelCenter(
  value: unknown,
): ProviderReliabilityModelCenter | null {
  const raw = nullableRecord(value);
  if (!raw) {
    return null;
  }
  const status = raw.status === 'certified'
    ? 'certified'
    : raw.status === 'attention'
      ? 'attention'
      : 'affected';
  return {
    protected: Boolean(raw.protected),
    modelClosed: Boolean(raw.modelClosed),
    healthy: Boolean(raw.healthy),
    schemaCertified: Boolean(raw.schemaCertified),
    operationalHealthy: Boolean(raw.operationalHealthy),
    status,
    reasonCode: toStringValue(raw.reasonCode),
    modelKey: toStringValue(raw.modelKey),
    modelVersion: toNumber(raw.modelVersion, 1),
    applicationVersion: toStringValue(raw.applicationVersion),
    certifiedAt: toNullableString(raw.certifiedAt),
    schemaFingerprint: toNullableString(raw.schemaFingerprint),
    storedSchemaFingerprint: toNullableString(raw.storedSchemaFingerprint),
    fingerprintStable: Boolean(raw.fingerprintStable),
    checkCount: toNumber(raw.checkCount),
    passedCount: toNumber(raw.passedCount),
  };
}

function normalizeApplicationIntegrityModelCenter(
  value: unknown,
): ApplicationIntegrityModelCenter | null {
  const raw = nullableRecord(value);
  if (!raw) {
    return null;
  }
  return {
    protected: Boolean(raw.protected),
    modelClosed: Boolean(raw.modelClosed),
    healthy: Boolean(raw.healthy),
    schemaCertified: Boolean(raw.schemaCertified),
    status: raw.status === 'certified' ? 'certified' : 'affected',
    reasonCode: toStringValue(raw.reasonCode),
    modelKey: toStringValue(raw.modelKey),
    modelVersion: toNumber(raw.modelVersion, 1),
    applicationVersion: toStringValue(raw.applicationVersion),
    certifiedAt: toNullableString(raw.certifiedAt),
    schemaFingerprint: toNullableString(raw.schemaFingerprint),
    storedSchemaFingerprint: toNullableString(raw.storedSchemaFingerprint),
    fingerprintStable: Boolean(raw.fingerprintStable),
    checkCount: toNumber(raw.checkCount),
    passedCount: toNumber(raw.passedCount),
  };
}

function normalizeApplicationRolloutModelCenter(
  value: unknown,
): ApplicationRolloutModelCenter | null {
  const raw = nullableRecord(value);
  if (!raw) {
    return null;
  }
  const status = raw.status === 'active' ||
    raw.status === 'paused' ||
    raw.status === 'killed' ||
    raw.status === 'completed'
      ? raw.status
      : 'affected';
  const stage = raw.stage === 'pilot' ||
    raw.stage === 'canary' ||
    raw.stage === 'general' ||
    raw.stage === 'completed'
      ? raw.stage
      : null;
  const latestHealthVerdict = raw.latestHealthVerdict === 'healthy' ||
    raw.latestHealthVerdict === 'unhealthy'
      ? raw.latestHealthVerdict
      : null;
  return {
    protected: Boolean(raw.protected),
    healthy: Boolean(raw.healthy),
    active: Boolean(raw.active),
    status,
    reasonCode: toStringValue(raw.reasonCode),
    environment: toStringValue(raw.environment) || 'production',
    releaseVersion: toNullableString(raw.releaseVersion),
    stage,
    exposurePercentage: raw.exposurePercentage === null || raw.exposurePercentage === undefined
      ? null
      : toNumber(raw.exposurePercentage),
    rolloutGeneration: raw.rolloutGeneration === null || raw.rolloutGeneration === undefined
      ? null
      : toNumber(raw.rolloutGeneration),
    killSwitchActive: Boolean(raw.killSwitchActive),
    planFingerprintStable: Boolean(raw.planFingerprintStable),
    latestHealthVerdict,
    latestErrorRateBps: raw.latestErrorRateBps === null || raw.latestErrorRateBps === undefined
      ? null
      : toNumber(raw.latestErrorRateBps),
    latestCrashCount: raw.latestCrashCount === null || raw.latestCrashCount === undefined
      ? null
      : toNumber(raw.latestCrashCount),
    latestHealthAt: toNullableString(raw.latestHealthAt),
    startedAt: toNullableString(raw.startedAt),
    promotedAt: toNullableString(raw.promotedAt),
  };
}

function normalizeApplicationOperationalTelemetryCenter(
  value: unknown,
): ApplicationOperationalTelemetryCenter | null {
  const raw = nullableRecord(value);
  if (!raw) {
    return null;
  }
  const status = raw.status === 'active' ||
    raw.status === 'degraded' ||
    raw.status === 'critical'
      ? raw.status
      : 'affected';
  const latestVerdict = raw.latestVerdict === 'healthy' ||
    raw.latestVerdict === 'degraded' ||
    raw.latestVerdict === 'critical'
      ? raw.latestVerdict
      : null;
  return {
    protected: Boolean(raw.protected),
    healthy: Boolean(raw.healthy),
    authoritative: Boolean(raw.authoritative),
    status,
    reasonCode: toStringValue(raw.reasonCode),
    environment: toStringValue(raw.environment) || 'production',
    sourceKey: toNullableString(raw.sourceKey),
    sourceGeneration: raw.sourceGeneration === null || raw.sourceGeneration === undefined
      ? null
      : toNumber(raw.sourceGeneration),
    telemetryGeneration: raw.telemetryGeneration === null || raw.telemetryGeneration === undefined
      ? null
      : toNumber(raw.telemetryGeneration),
    lastWindowSequence: raw.lastWindowSequence === null || raw.lastWindowSequence === undefined
      ? null
      : toNumber(raw.lastWindowSequence),
    lastWindowStartedAt: toNullableString(raw.lastWindowStartedAt),
    lastWindowEndedAt: toNullableString(raw.lastWindowEndedAt),
    latestVerdict,
    latestErrorRateBps: raw.latestErrorRateBps === null || raw.latestErrorRateBps === undefined
      ? null
      : toNumber(raw.latestErrorRateBps),
    latestCrashCount: raw.latestCrashCount === null || raw.latestCrashCount === undefined
      ? null
      : toNumber(raw.latestCrashCount),
    latestP95LatencyMs: raw.latestP95LatencyMs === null || raw.latestP95LatencyMs === undefined
      ? null
      : toNumber(raw.latestP95LatencyMs),
    latestExposurePercentage: raw.latestExposurePercentage === null || raw.latestExposurePercentage === undefined
      ? null
      : toNumber(raw.latestExposurePercentage),
    latestReleaseVersion: toNullableString(raw.latestReleaseVersion),
    autoRollbackEnabled: Boolean(raw.autoRollbackEnabled),
    autoRollbackTriggered: Boolean(raw.autoRollbackTriggered),
    fingerprintStable: Boolean(raw.fingerprintStable),
  };
}

function normalizeApplicationOperationalOutboxCenter(
  value: unknown,
): ApplicationOperationalOutboxCenter | null {
  const raw = nullableRecord(value);
  if (!raw) {
    return null;
  }
  const status = raw.status === 'active' ||
    raw.status === 'attention' ||
    raw.status === 'dead_letter'
      ? raw.status
      : 'affected';
  return {
    protected: Boolean(raw.protected),
    healthy: Boolean(raw.healthy),
    status,
    reasonCode: toStringValue(raw.reasonCode),
    environment: toStringValue(raw.environment) || 'production',
    captureReady: Boolean(raw.captureReady),
    messageCount: toNumber(raw.messageCount),
    destinationCount: toNumber(raw.destinationCount),
    pendingCount: toNumber(raw.pendingCount),
    leasedCount: toNumber(raw.leasedCount),
    retryCount: toNumber(raw.retryCount),
    deliveredCount: toNumber(raw.deliveredCount),
    deadLetterCount: toNumber(raw.deadLetterCount),
    expiredLeaseCount: toNumber(raw.expiredLeaseCount),
    lastSequence: toNumber(raw.lastSequence),
    sequenceGapCount: toNumber(raw.sequenceGapCount),
    fingerprintMismatchCount: toNumber(raw.fingerprintMismatchCount),
    oldestPendingAt: toNullableString(raw.oldestPendingAt),
    lastDeliveredAt: toNullableString(raw.lastDeliveredAt),
    lastDeadLetterAt: toNullableString(raw.lastDeadLetterAt),
  };
}

function normalizeApplicationOperationalConsumerDeliveryCenter(
  value: unknown,
): ApplicationOperationalConsumerDeliveryCenter | null {
  const raw = nullableRecord(value);
  if (!raw) {
    return null;
  }
  const status = raw.status === 'active' || raw.status === 'attention'
    ? raw.status
    : 'affected';
  return {
    protected: Boolean(raw.protected),
    healthy: Boolean(raw.healthy),
    authoritative: Boolean(raw.authoritative),
    status,
    reasonCode: toStringValue(raw.reasonCode),
    environment: toStringValue(raw.environment) || 'production',
    consumerCount: toNumber(raw.consumerCount),
    receiptCount: toNumber(raw.receiptCount),
    liveReceiptCount: toNumber(raw.liveReceiptCount),
    adoptedReceiptCount: toNumber(raw.adoptedReceiptCount),
    expectedReceiptCount: toNumber(raw.expectedReceiptCount),
    replayRequestCount: toNumber(raw.replayRequestCount),
    sequenceGapCount: toNumber(raw.sequenceGapCount),
    fingerprintMismatchCount: toNumber(raw.fingerprintMismatchCount),
    receiptConsistencyMismatchCount: toNumber(
      raw.receiptConsistencyMismatchCount,
    ),
    lastAcknowledgedSequence: toNumber(raw.lastAcknowledgedSequence),
    lastAcknowledgedAt: toNullableString(raw.lastAcknowledgedAt),
  };
}

function normalizeApplicationOperationalDeliveryAuditCenter(
  value: unknown,
): ApplicationOperationalDeliveryAuditCenter | null {
  const raw = nullableRecord(value);
  if (!raw) {
    return null;
  }
  const status = raw.status === 'certified' ||
    raw.status === 'stale' ||
    raw.status === 'attention'
      ? raw.status
      : 'affected';
  return {
    protected: Boolean(raw.protected),
    healthy: Boolean(raw.healthy),
    fresh: Boolean(raw.fresh),
    status,
    reasonCode: toStringValue(raw.reasonCode),
    environment: toStringValue(raw.environment) || 'production',
    auditGeneration: toNumber(raw.auditGeneration),
    auditedThroughSequence: toNumber(raw.auditedThroughSequence),
    currentLastSequence: toNumber(raw.currentLastSequence),
    messageCount: toNumber(raw.messageCount),
    expectedDeliveryCount: toNumber(raw.expectedDeliveryCount),
    deliveryCount: toNumber(raw.deliveryCount),
    receiptCount: toNumber(raw.receiptCount),
    sequenceGapCount: toNumber(raw.sequenceGapCount),
    consistencyMismatchCount: toNumber(raw.consistencyMismatchCount),
    fingerprintMismatchCount: toNumber(raw.fingerprintMismatchCount),
    headMismatchCount: toNumber(raw.headMismatchCount),
    deadLetterCount: toNumber(raw.deadLetterCount),
    affectedDestinationCount: toNumber(raw.affectedDestinationCount),
    lastAuditAt: toNullableString(raw.lastAuditAt),
  };
}

function normalizeApplicationDisasterRecoveryCenter(
  value: unknown,
): ApplicationDisasterRecoveryCenter | null {
  const raw = nullableRecord(value);
  if (!raw) {
    return null;
  }
  const status = raw.status === 'certified' || raw.status === 'stale'
    ? raw.status
    : 'affected';
  return {
    protected: Boolean(raw.protected),
    healthy: Boolean(raw.healthy),
    fresh: Boolean(raw.fresh),
    status,
    reasonCode: toStringValue(raw.reasonCode),
    environment: toStringValue(raw.environment) || 'production',
    checkpointGeneration: toNumber(raw.checkpointGeneration),
    drillGeneration: toNumber(raw.drillGeneration),
    activeVersion: toNullableString(raw.activeVersion),
    releaseGeneration: toNumber(raw.releaseGeneration),
    rolloutGeneration: toNumber(raw.rolloutGeneration),
    exposurePercentage: toNumber(raw.exposurePercentage),
    telemetryGeneration: toNumber(raw.telemetryGeneration),
    outboxSequence: toNumber(raw.outboxSequence),
    consumerSequence: toNumber(raw.consumerSequence),
    auditedSequence: toNumber(raw.auditedSequence),
    componentCount: toNumber(raw.componentCount),
    lastCheckpointAt: toNullableString(raw.lastCheckpointAt),
    lastDrillAt: toNullableString(raw.lastDrillAt),
  };
}

function normalizeApplicationPhysicalBackupCenter(
  value: unknown,
): ApplicationPhysicalBackupCenter | null {
  const raw = nullableRecord(value);
  if (!raw) {
    return null;
  }
  const status = raw.status === 'certified' || raw.status === 'stale'
    ? raw.status
    : 'affected';
  return {
    protected: Boolean(raw.protected),
    healthy: Boolean(raw.healthy),
    fresh: Boolean(raw.fresh),
    status,
    reasonCode: toStringValue(raw.reasonCode),
    environment: toStringValue(raw.environment) || 'production',
    backupGeneration: toNumber(raw.backupGeneration),
    custodySequence: toNumber(raw.custodySequence),
    rehearsalGeneration: toNumber(raw.rehearsalGeneration),
    activeVersion: toNullableString(raw.activeVersion),
    checkpointGeneration: toNumber(raw.checkpointGeneration),
    artifactSizeBytes: toNumber(raw.artifactSizeBytes),
    checksumVerified: Boolean(raw.checksumVerified),
    custodyComplete: Boolean(raw.custodyComplete),
    restoreVerified: Boolean(raw.restoreVerified),
    lastArtifactAt: toNullableString(raw.lastArtifactAt),
    lastRehearsalAt: toNullableString(raw.lastRehearsalAt),
  };
}

function normalizeApplicationServiceReturnCenter(
  value: unknown,
): ApplicationServiceReturnCenter | null {
  const raw = nullableRecord(value);
  if (!raw) {
    return null;
  }
  const status = raw.status === 'certified' || raw.status === 'recovery'
    ? raw.status
    : 'affected';
  const mode = raw.mode === 'active' || raw.mode === 'recovery'
    ? raw.mode
    : 'affected';
  return {
    protected: Boolean(raw.protected),
    healthy: Boolean(raw.healthy),
    fresh: Boolean(raw.fresh),
    status,
    reasonCode: toStringValue(raw.reasonCode),
    environment: toStringValue(raw.environment) || 'production',
    mode,
    recoveryGeneration: toNumber(raw.recoveryGeneration),
    activeVersion: toNullableString(raw.activeVersion),
    checkCount: toNumber(raw.checkCount),
    requiredCheckCount: toNumber(raw.requiredCheckCount, 8),
    writesAllowed: Boolean(raw.writesAllowed),
    workersAllowed: Boolean(raw.workersAllowed),
    trafficPercentage: toNumber(raw.trafficPercentage),
    lastRecoveryStartedAt: toNullableString(raw.lastRecoveryStartedAt),
    lastCertifiedAt: toNullableString(raw.lastCertifiedAt),
  };
}

function normalizeApplicationProductionReadinessCenter(
  value: unknown,
): ApplicationProductionReadinessCenter | null {
  const raw = nullableRecord(value);
  if (!raw) {
    return null;
  }
  const status = raw.status === 'certified' || raw.status === 'pending'
    ? raw.status
    : 'affected';
  return {
    protected: Boolean(raw.protected),
    healthy: Boolean(raw.healthy),
    fresh: Boolean(raw.fresh),
    status,
    reasonCode: toStringValue(raw.reasonCode),
    environment: toStringValue(raw.environment) || 'production',
    readinessGeneration: toNumber(raw.readinessGeneration),
    activeVersion: toNullableString(raw.activeVersion),
    checkCount: toNumber(raw.checkCount),
    requiredCheckCount: toNumber(raw.requiredCheckCount, 10),
    goLiveAllowed: Boolean(raw.goLiveAllowed),
    fingerprintStable: Boolean(raw.fingerprintStable),
    certifiedAt: toNullableString(raw.certifiedAt),
    affectedAt: toNullableString(raw.affectedAt),
  };
}

function normalizeApplicationReleaseModelCenter(
  value: unknown,
): ApplicationReleaseModelCenter | null {
  const raw = nullableRecord(value);
  if (!raw) {
    return null;
  }
  const status = raw.status === 'rollback'
    ? 'rollback'
    : raw.status === 'active'
      ? 'active'
      : 'affected';
  return {
    protected: Boolean(raw.protected),
    healthy: Boolean(raw.healthy),
    active: Boolean(raw.active),
    status,
    reasonCode: toStringValue(raw.reasonCode),
    environment: toStringValue(raw.environment) || 'production',
    activeVersion: toNullableString(raw.activeVersion),
    previousVersion: toNullableString(raw.previousVersion),
    minSupportedVersion: toNullableString(raw.minSupportedVersion),
    maxSupportedVersion: toNullableString(raw.maxSupportedVersion),
    releaseGeneration: raw.releaseGeneration === null || raw.releaseGeneration === undefined
      ? null
      : toNumber(raw.releaseGeneration),
    rollbackActive: Boolean(raw.rollbackActive),
    schemaCertified: Boolean(raw.schemaCertified),
    fingerprintStable: Boolean(raw.fingerprintStable),
    bundleFingerprint: toNullableString(raw.bundleFingerprint),
    certifiedAt: toNullableString(raw.certifiedAt),
    activatedAt: toNullableString(raw.activatedAt),
  };
}

function normalizeLeagueSeasonOfficialSnapshotCenter(
  value: unknown,
): LeagueSeasonOfficialSnapshotCenter | null {
  const raw = nullableRecord(value);
  if (!raw) {
    return null;
  }
  const status = raw.status;
  const championRaw = nullableRecord(raw.champion);
  return {
    protected: Boolean(raw.protected),
    published: Boolean(raw.published),
    healthy: raw.healthy === undefined ? true : Boolean(raw.healthy),
    status:
      status === 'official' || status === 'affected'
        ? status
        : 'pending',
    reasonCode: toStringValue(raw.reasonCode),
    affected: Boolean(raw.affected),
    snapshotId: toNullableIdentifier(raw.snapshotId),
    snapshotHash: toNullableString(raw.snapshotHash),
    standingsHash: toNullableString(raw.standingsHash),
    completionRunId: toNullableIdentifier(raw.completionRunId),
    completionGateGeneration:
      raw.completionGateGeneration === null ||
      raw.completionGateGeneration === undefined
        ? null
        : toNumber(raw.completionGateGeneration),
    completionGateFingerprint: toNullableString(
      raw.completionGateFingerprint,
    ),
    season: toNullableString(raw.season),
    champion: championRaw
      ? {
          teamId: toStringValue(championRaw.teamId),
          teamName: toStringValue(championRaw.teamName),
          managerName: toStringValue(championRaw.managerName),
          leaguePoints: toNumber(championRaw.leaguePoints),
          pointsFor: toNumber(championRaw.pointsFor),
        }
      : null,
    podium: Array.isArray(raw.podium)
      ? raw.podium.map(normalizeOfficialSnapshotStanding)
      : [],
    finalStandings: Array.isArray(raw.finalStandings)
      ? raw.finalStandings.map(normalizeOfficialSnapshotStanding)
      : [],
    officializedAt: toNullableString(raw.officializedAt),
    affectedAt: toNullableString(raw.affectedAt),
  };
}

function normalizeOfficialSnapshotStanding(value: unknown) {
  const raw = asRecord(value);
  return {
    position: toNumber(raw.position),
    teamId: toStringValue(raw.teamId),
    teamName: toStringValue(raw.teamName),
    played: toNumber(raw.played),
    won: toNumber(raw.won),
    drawn: toNumber(raw.drawn),
    lost: toNumber(raw.lost),
    goalsFor: toNumber(raw.goalsFor),
    goalsAgainst: toNumber(raw.goalsAgainst),
    goalDifference: toNumber(raw.goalDifference),
    pointsFor: toNumber(raw.pointsFor),
    leaguePoints: toNumber(raw.leaguePoints),
    headToHeadPlayed: toNumber(raw.headToHeadPlayed),
    headToHeadPoints: toNumber(raw.headToHeadPoints),
    headToHeadGoalDifference: toNumber(raw.headToHeadGoalDifference),
    headToHeadEligible: Boolean(raw.headToHeadEligible),
  };
}

function normalizeProviderRecoveryCenter(
  value: unknown,
): LeagueProviderRecoveryCenter | null {
  const raw = nullableRecord(value);
  if (!raw) {
    return null;
  }

  const recoverableRaw = nullableRecord(raw.recoverableIncident);
  const recoverableAction = recoverableRaw
    ? normalizeProviderSyncAction(recoverableRaw.syncType)
    : null;

  const progressRaw = nullableRecord(raw.latestProgress);
  const progressAction = progressRaw
    ? normalizeProviderSyncAction(progressRaw.syncType)
    : null;
  const retryCenter = normalizeProviderAutomaticRetryCenter(raw.retryCenter);
  const circuitBreaker = normalizeProviderCircuitBreakerCenter(
    raw.circuitBreaker,
  );
  const outcomeVerification = normalizeProviderOutcomeVerificationCenter(
    raw.outcomeVerification,
  );
  const workerFencing = normalizeProviderWorkerFencingCenter(
    raw.workerFencing,
  );

  return {
    protected: Boolean(raw.protected),
    healthy: Boolean(raw.healthy),
    pendingCount: toNumber(raw.pendingCount),
    runningCount: toNumber(raw.runningCount),
    completedLast24h: toNumber(raw.completedLast24h),
    failedLast24h: toNumber(raw.failedLast24h),
    watchdogActive: Boolean(raw.watchdogActive),
    staleRunningCount: toNumber(raw.staleRunningCount),
    timedOutLast24h: toNumber(raw.timedOutLast24h),
    latestWatchdogAt: toNullableString(raw.latestWatchdogAt),
    workerHeartbeatActive: Boolean(raw.workerHeartbeatActive),
    runningHeartbeatFresh:
      raw.runningHeartbeatFresh === undefined
        ? true
        : Boolean(raw.runningHeartbeatFresh),
    heartbeatGraceSeconds:
      raw.heartbeatGraceSeconds === null ||
      raw.heartbeatGraceSeconds === undefined
        ? null
        : toNumber(raw.heartbeatGraceSeconds),
    latestHeartbeatAt: toNullableString(raw.latestHeartbeatAt),
    latestProgress:
      progressRaw && progressAction
        ? {
            requestId: toStringValue(progressRaw.requestId),
            runId: toStringValue(progressRaw.runId),
            syncType: progressAction,
            phase: toStringValue(progressRaw.phase),
            current: toNumber(progressRaw.current),
            total:
              progressRaw.total === null || progressRaw.total === undefined
                ? null
                : toNumber(progressRaw.total),
            recordsProcessed: toNumber(progressRaw.recordsProcessed),
            heartbeatAt: toStringValue(progressRaw.heartbeatAt),
            revision: toNumber(progressRaw.revision, 1),
            percent:
              progressRaw.percent === null || progressRaw.percent === undefined
                ? null
                : toNumber(progressRaw.percent),
          }
        : null,
    retryCenter,
    circuitBreaker,
    outcomeVerification,
    workerFencing,
    latestRequestAt: toNullableString(raw.latestRequestAt),
    canRequest: Boolean(raw.canRequest),
    recoverableIncident:
      recoverableRaw && recoverableAction
        ? {
            id: toStringValue(recoverableRaw.id),
            revision: toNumber(recoverableRaw.revision, 1),
            syncType: recoverableAction,
            severity:
              recoverableRaw.severity === 'critical'
                ? 'critical'
                : 'warning',
            summary: toStringValue(recoverableRaw.summary),
          }
        : null,
    requests: Array.isArray(raw.requests)
      ? raw.requests.flatMap((item) => {
          const requestRaw = asRecord(item);
          const action = normalizeProviderSyncAction(requestRaw.syncType);
          if (!action) {
            return [];
          }
          return [
            {
              id: toStringValue(requestRaw.id),
              incidentId: toStringValue(requestRaw.incidentId),
              syncType: action,
              status: normalizeProviderRecoveryStatus(requestRaw.status),
              revision: toNumber(requestRaw.revision, 1),
              attempt: toNumber(requestRaw.attempt),
              requestedAt: toStringValue(requestRaw.requestedAt),
              startedAt: toNullableString(requestRaw.startedAt),
              finishedAt: toNullableString(requestRaw.finishedAt),
              errorSummary: toNullableString(requestRaw.errorSummary),
            },
          ];
        })
      : [],
  };
}

function normalizeProviderRecoveryOutcome(
  value: unknown,
): ProviderRecoveryRequestOutcome {
  const raw = asRecord(value);
  return {
    requestId: toStringValue(raw.requestId),
    incidentId: toStringValue(raw.incidentId),
    status: normalizeProviderRecoveryStatus(raw.status),
    revision: toNumber(raw.revision, 1),
    attempt: toNumber(raw.attempt),
    recoveryRunId: toNullableString(raw.recoveryRunId),
    reused: Boolean(raw.reused),
  };
}

function normalizeProviderCircuitBreakerReleaseOutcome(
  value: unknown,
): ProviderRecoveryCircuitBreakerReleaseOutcome {
  const raw = asRecord(value);
  return {
    breakerId: toStringValue(raw.breakerId),
    incidentId: toStringValue(raw.incidentId),
    status: 'released',
    revision: toNumber(raw.revision, 1),
    releasedAt: toStringValue(raw.releasedAt),
    reused: Boolean(raw.reused),
  };
}

function normalizeProviderDataQuality(
  value: unknown,
): LeagueProviderDataQuality | null {
  const raw = nullableRecord(value);
  if (!raw) {
    return null;
  }

  const latestRaw = nullableRecord(raw.latestSnapshot);
  const latestAction = latestRaw
    ? normalizeProviderSyncAction(latestRaw.action)
    : null;

  return {
    protected: Boolean(raw.protected),
    healthy: Boolean(raw.healthy),
    status: normalizeProviderDataQualityStatus(raw.status),
    stale: Boolean(raw.stale),
    anomalyCount: toNumber(raw.anomalyCount),
    matchdayId: toNullableString(raw.matchdayId),
    matchdayNumber:
      raw.matchdayNumber === null || raw.matchdayNumber === undefined
        ? null
        : toNumber(raw.matchdayNumber),
    scheduleSource:
      raw.scheduleSource === 'provider' || raw.scheduleSource === 'estimated'
        ? raw.scheduleSource
        : null,
    fixtureCount: toNumber(raw.fixtureCount),
    finalFixtureCount: toNumber(raw.finalFixtureCount),
    liveFixtureCount: toNumber(raw.liveFixtureCount),
    scoreCount: toNumber(raw.scoreCount),
    finalScoreCount: toNumber(raw.finalScoreCount),
    invalidScoreCount: toNumber(raw.invalidScoreCount),
    finalFixtureWithoutScoreCount: toNumber(
      raw.finalFixtureWithoutScoreCount,
    ),
    scheduleMismatchCount: toNumber(raw.scheduleMismatchCount),
    snapshotMissingCount: toNumber(raw.snapshotMissingCount),
    latestFixtureAt: toNullableString(raw.latestFixtureAt),
    latestScoreAt: toNullableString(raw.latestScoreAt),
    latestSnapshot:
      latestRaw && latestAction
        ? {
            runId: toStringValue(latestRaw.runId),
            action: latestAction,
            status: normalizeProviderDataQualityStatus(latestRaw.status),
            anomalyCount: toNumber(latestRaw.anomalyCount),
            latestSourceAt: toNullableString(latestRaw.latestSourceAt),
            createdAt: toStringValue(latestRaw.createdAt),
          }
        : null,
  };
}

function normalizeFocusMatchday(
  value: unknown,
): LeagueOperationFocusMatchday | null {
  const raw = nullableRecord(value);
  if (!raw) {
    return null;
  }
  const id = toStringValue(raw.id);
  if (!id) {
    return null;
  }
  return {
    id,
    number: toNumber(raw.number),
    startsAt: toStringValue(raw.startsAt),
    locksAt: toStringValue(raw.locksAt),
    endsAt: toNullableString(raw.endsAt),
    scheduleSource: normalizeScheduleSource(raw.scheduleSource),
    scheduleSyncedAt: toNullableString(raw.scheduleSyncedAt),
    providerFixtureCount: toNumber(raw.providerFixtureCount),
    providerFinalFixtureCount: toNumber(raw.providerFinalFixtureCount),
    fixtureCount: toNumber(raw.fixtureCount),
    readyCount: toNumber(raw.readyCount),
    officialCount: toNumber(raw.officialCount),
    status: normalizeMatchdayStatus(raw.status),
    canFinalize: Boolean(raw.canFinalize),
  };
}

function normalizeLineupMatchday(
  value: unknown,
): LeagueOperationLineupMatchday | null {
  const raw = nullableRecord(value);
  if (!raw) {
    return null;
  }
  const id = toStringValue(raw.id);
  if (!id) {
    return null;
  }
  return {
    id,
    number: toNumber(raw.number),
    startsAt: toStringValue(raw.startsAt),
    locksAt: toStringValue(raw.locksAt),
    endsAt: toNullableString(raw.endsAt),
    scheduleSource: normalizeScheduleSource(raw.scheduleSource),
    scheduleSyncedAt: toNullableString(raw.scheduleSyncedAt),
    providerFixtureCount: toNumber(raw.providerFixtureCount),
    providerFinalFixtureCount: toNumber(raw.providerFinalFixtureCount),
    teamCount: toNumber(raw.teamCount),
    manualCount: toNumber(raw.manualCount),
    carriedCount: toNumber(raw.carriedCount),
    draftCount: toNumber(raw.draftCount),
    missingCount: toNumber(raw.missingCount),
    reminderSentCount: toNumber(raw.reminderSentCount),
    canRemind: Boolean(raw.canRemind),
    teams: Array.isArray(raw.teams)
      ? raw.teams.map((team) => {
          const teamRaw = asRecord(team);
          return {
            teamId: toStringValue(teamRaw.teamId),
            teamName: toStringValue(teamRaw.teamName),
            managerId: toStringValue(teamRaw.managerId),
            managerName: toStringValue(teamRaw.managerName),
            status: normalizeLineupStatus(teamRaw.status),
            submittedAt: toNullableString(teamRaw.submittedAt),
            reminderSent: Boolean(teamRaw.reminderSent),
          };
        })
      : [],
  };
}

function normalizeReminderOutcome(
  value: unknown,
): LeagueLineupReminderOutcome {
  const raw = asRecord(value);
  return {
    matchdayId: toStringValue(raw.matchdayId),
    matchdayNumber: toNumber(raw.matchdayNumber),
    targetCount: toNumber(raw.targetCount),
    sentCount: toNumber(raw.sentCount),
    alreadySentCount: toNumber(raw.alreadySentCount),
  };
}

function normalizeLeagueStatus(value: unknown): LeagueSummary['status'] {
  if (
    value === 'draft' ||
    value === 'active' ||
    value === 'completed' ||
    value === 'archived'
  ) {
    return value;
  }
  return 'draft';
}

function normalizeScheduleSource(
  value: unknown,
): 'estimated' | 'provider' {
  return value === 'provider' ? 'provider' : 'estimated';
}

function normalizeMatchdayStatus(
  value: unknown,
): LeagueOperationMatchdayStatus {
  if (
    value === 'upcoming' ||
    value === 'live' ||
    value === 'pending' ||
    value === 'ready' ||
    value === 'official'
  ) {
    return value;
  }
  return 'pending';
}

function normalizeLineupStatus(
  value: unknown,
): LeagueOperationLineupStatus {
  if (
    value === 'manual' ||
    value === 'carried' ||
    value === 'draft' ||
    value === 'missing'
  ) {
    return value;
  }
  return 'missing';
}

function normalizeProviderDataQualityStatus(
  value: unknown,
): LeagueProviderDataQuality['status'] {
  if (value === 'healthy' || value === 'attention' || value === 'idle') {
    return value;
  }
  return 'idle';
}

function normalizeProviderSyncHealthStatus(
  value: unknown,
): LeagueProviderSyncHealth['status'] {
  if (value === 'healthy' || value === 'attention' || value === 'idle') {
    return value;
  }
  return 'idle';
}

function normalizeProviderOutcomeVerificationStatus(
  value: unknown,
): 'verified' | 'retry_scheduled' | 'exhausted' | 'superseded' | null {
  if (
    value === 'verified' ||
    value === 'retry_scheduled' ||
    value === 'exhausted' ||
    value === 'superseded'
  ) {
    return value;
  }
  return null;
}

function normalizeProviderCircuitFailureClass(
  value: unknown,
): ProviderRecoveryCircuitBreakerOpen['failureClass'] {
  if (
    value === 'rate_limit' ||
    value === 'timeout' ||
    value === 'network' ||
    value === 'provider' ||
    value === 'configuration' ||
    value === 'request'
  ) {
    return value;
  }
  return 'unknown';
}

function normalizeProviderRecoveryStatus(
  value: unknown,
): ProviderRecoveryRequestStatus {
  if (
    value === 'pending' ||
    value === 'running' ||
    value === 'completed' ||
    value === 'failed' ||
    value === 'cancelled'
  ) {
    return value;
  }
  return 'pending';
}

function normalizeProviderSyncAction(
  value: unknown,
): ProviderSyncAction | null {
  if (
    value === 'sync-fixtures' ||
    value === 'sync-fixture-players' ||
    value === 'sync-season-players'
  ) {
    return value;
  }
  return null;
}

function normalizeProviderSyncRunStatus(
  value: unknown,
): ProviderSyncRunStatus {
  if (value === 'completed' || value === 'failed') {
    return value;
  }
  return 'running';
}

function translateLeagueOperationsError(message: string) {
  const normalized = message.toLowerCase();
  if (normalized.includes('get_league_provider_sync_health_v35')) {
    return 'La telemetria operativa autorevole non è ancora disponibile nel database.';
  }
  if (normalized.includes('get_league_provider_sync_health_v34')) {
    return 'Aggiorna il database LEGHEVO fino alla migrazione 139.';
  }
  if (normalized.includes('get_league_provider_sync_health_v33')) {
    return 'Esegui prima lo script Supabase della versione v0.62.34.';
  }
  if (normalized.includes('get_league_provider_sync_health_v32')) {
    return 'Esegui prima lo script Supabase della versione v0.62.33.';
  }
  if (normalized.includes('get_league_provider_sync_health_v31')) {
    return 'Esegui prima lo script Supabase della versione v0.62.32.';
  }
  if (normalized.includes('get_league_provider_sync_health_v30')) {
    return 'Esegui prima lo script Supabase della versione v0.62.31.';
  }
  if (normalized.includes('get_league_provider_sync_health_v29')) {
    return 'Esegui prima lo script Supabase della versione v0.62.30.';
  }
  if (normalized.includes('get_league_provider_sync_health_v28')) {
    return 'Esegui prima lo script Supabase della versione v0.62.29.';
  }
  if (normalized.includes('get_league_provider_sync_health_v27')) {
    return 'Esegui prima lo script Supabase della versione v0.62.28.';
  }
  if (normalized.includes('get_league_provider_sync_health_v26')) {
    return 'Esegui prima lo script Supabase della versione v0.62.27.';
  }
  if (
    normalized.includes('get_league_provider_sync_health_v21') ||
    normalized.includes('get_league_provider_official_result_impact_v1') ||
    normalized.includes('get_league_provider_official_result_remediation_v1') ||
    normalized.includes('get_league_provider_sync_health_v22')
  ) {
    return 'Esegui prima lo script Supabase della versione v0.62.23.';
  }
  if (
    normalized.includes('get_league_provider_sync_health_v20') ||
    normalized.includes('get_league_provider_score_consumption_gate_v1')
  ) {
    return 'Esegui prima lo script Supabase della versione v0.62.21.';
  }
  if (
    normalized.includes('get_league_provider_sync_health_v9') ||
    normalized.includes('get_league_provider_recovery_center_v6') ||
    normalized.includes('get_league_provider_retry_center_v3') ||
    normalized.includes(
      'get_league_provider_outcome_verification_center_v1',
    )
  ) {
    return 'Esegui prima lo script Supabase della versione v0.62.10.';
  }
  if (
    normalized.includes('get_league_provider_sync_health_v8') ||
    normalized.includes('get_league_provider_recovery_center_v5') ||
    normalized.includes(
      'release_provider_recovery_circuit_breaker_guarded_v1',
    )
  ) {
    return 'Esegui prima lo script Supabase della versione v0.62.9.';
  }
  if (
    normalized.includes('get_league_provider_sync_health_v7') ||
    normalized.includes('get_league_provider_recovery_center_v4') ||
    normalized.includes('claim_next_provider_recovery_request_v3')
  ) {
    return 'Esegui prima lo script Supabase della versione v0.62.8.';
  }
  if (
    normalized.includes('get_league_provider_sync_health_v6') ||
    normalized.includes('get_league_provider_sync_health_v5') ||
    normalized.includes('claim_next_provider_recovery_request_v2') ||
    normalized.includes('claim_provider_recovery_request_v2')
  ) {
    return 'Esegui prima lo script Supabase della versione v0.62.7.';
  }
  if (normalized.includes('request_provider_recovery_guarded_v1')) {
    return 'Esegui prima lo script Supabase della versione v0.62.5.';
  }
  if (
    normalized.includes('get_league_operations_center') ||
    normalized.includes('send_league_lineup_reminders') ||
    (normalized.includes('function') && normalized.includes('does not exist'))
  ) {
    return 'Il database LEGHEVO non contiene ancora tutte le funzioni richieste.';
  }
  if (
    normalized.includes('riservato alla direzione') ||
    normalized.includes('solo il presidente')
  ) {
    return 'Il Centro Operativo è riservato alla Direzione della lega.';
  }
  if (normalized.includes('altro dispositivo') || normalized.includes('altra esecuzione')) {
    return 'Lo stato del provider è cambiato su un altro dispositivo. Aggiorna e riprova.';
  }
  if (normalized.includes('circuit breaker provider aperto')) {
    return 'I retry sono esauriti. La Direzione deve riaprire i recuperi provider.';
  }
  if (normalized.includes('circuit breaker aggiornato')) {
    return 'Il blocco provider è cambiato su un altro dispositivo. Aggiorna e riprova.';
  }
  if (normalized.includes('già risolto')) {
    return 'L’incidente provider risulta già risolto.';
  }
  if (normalized.includes('nessuna richiesta provider valida')) {
    return 'Non è disponibile una sincronizzazione sorgente da recuperare.';
  }
  if (normalized.includes('scadenza')) {
    return 'La scadenza delle formazioni è già trascorsa.';
  }
  if (normalized.includes('non è ancora iniziata')) {
    return 'Avvia prima ufficialmente la competizione.';
  }
  if (normalized.includes('non fai parte')) {
    return 'Non fai parte della lega selezionata.';
  }
  return message;
}

function createOperationId() {
  return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (token) => {
    const value = Math.floor(Math.random() * 16);
    const normalized = token === 'x' ? value : (value & 0x3) | 0x8;
    return normalized.toString(16);
  });
}

function asRecord(value: unknown): Record<string, unknown> {
  return value && typeof value === 'object'
    ? (value as Record<string, unknown>)
    : {};
}

function nullableRecord(value: unknown): Record<string, unknown> | null {
  return value && typeof value === 'object'
    ? (value as Record<string, unknown>)
    : null;
}

function toStringValue(value: unknown) {
  return typeof value === 'string' ? value : '';
}

function toNullableIdentifier(value: unknown) {
  if (typeof value === 'string' && value) {
    return value;
  }
  if (typeof value === 'number' && Number.isFinite(value)) {
    return String(value);
  }
  return null;
}

function toNullableString(value: unknown) {
  return typeof value === 'string' && value ? value : null;
}

function toNumber(value: unknown, fallback = 0) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : fallback;
}

function toNullableNumber(value: unknown) {
  if (value === null || value === undefined || value === '') {
    return null;
  }
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : null;
}
