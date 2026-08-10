import { useCallback, useEffect, useState } from 'react';
import { AppState } from 'react-native';
import {
  fetchLeagueOperationsCenter,
  releaseLeagueProviderCircuitBreaker,
  requestLeagueProviderRecovery,
  sendLeagueLineupReminders,
  subscribeToLeagueOperations,
} from '../services/leagueOperationsService';
import type {
  LeagueLineupReminderOutcome,
  LeagueOperationsCenter,
  ProviderRecoveryCircuitBreakerReleaseOutcome,
  ProviderRecoveryRequestOutcome,
} from '../types';

function createDemoOperationsCenter(): LeagueOperationsCenter {
  const now = new Date();
  const locksAt = new Date(now.getTime() + 22 * 60 * 60 * 1000);
  const endsAt = new Date(now.getTime() + 4 * 24 * 60 * 60 * 1000);

  return {
    leagueId: 'demo-league',
    leagueName: 'Serie A da divano',
    leagueStatus: 'active',
    season: '2026',
    competitionStartedAt: '2026-09-01T18:00:00Z',
    isOwner: true,
    isDirector: true,
    generatedAt: now.toISOString(),
    focusMatchday: {
      id: 'demo-matchday-7',
      number: 7,
      startsAt: locksAt.toISOString(),
      locksAt: locksAt.toISOString(),
      endsAt: endsAt.toISOString(),
      scheduleSource: 'provider',
      scheduleSyncedAt: now.toISOString(),
      providerFixtureCount: 10,
      providerFinalFixtureCount: 0,
      fixtureCount: 2,
      readyCount: 0,
      officialCount: 0,
      status: 'upcoming',
      canFinalize: false,
    },
    nextLineupMatchday: {
      id: 'demo-matchday-7',
      number: 7,
      startsAt: locksAt.toISOString(),
      locksAt: locksAt.toISOString(),
      endsAt: endsAt.toISOString(),
      scheduleSource: 'provider',
      scheduleSyncedAt: now.toISOString(),
      providerFixtureCount: 10,
      providerFinalFixtureCount: 0,
      teamCount: 4,
      manualCount: 2,
      carriedCount: 0,
      draftCount: 1,
      missingCount: 1,
      reminderSentCount: 0,
      canRemind: true,
      teams: [
        {
          teamId: 'demo-team-4',
          teamName: 'Real Colizzati',
          managerId: 'demo-manager-4',
          managerName: 'Andrea Greco',
          status: 'missing',
          submittedAt: null,
          reminderSent: false,
        },
        {
          teamId: 'demo-team-3',
          teamName: 'Atletico Ma Non Troppo',
          managerId: 'demo-manager-3',
          managerName: 'Sara De Luca',
          status: 'draft',
          submittedAt: null,
          reminderSent: false,
        },
        {
          teamId: 'demo-team',
          teamName: 'Diavoli del Sud',
          managerId: 'demo-user',
          managerName: 'Marco Schito',
          status: 'manual',
          submittedAt: now.toISOString(),
          reminderSent: false,
        },
        {
          teamId: 'demo-team-2',
          teamName: 'Tiki Taka Boom',
          managerId: 'demo-manager-2',
          managerName: 'Luca Ferri',
          status: 'manual',
          submittedAt: now.toISOString(),
          reminderSent: false,
        },
      ],
    },
    providerBudget: {
      generatedAt: now.toISOString(),
      providers: [
        {
          provider: 'api-football',
          dailyLimit: 100,
          consumedUnits: 3,
          remainingUnits: 97,
          ordinaryRemainingUnits: 77,
          reservedHighPriorityUnits: 20,
          rejectedRequests: 0,
          cacheHits: 0,
          cacheEntries: 0,
          providerReportedRemaining: 97,
        },
        {
          provider: 'football-data',
          dailyLimit: 100_000,
          consumedUnits: 4,
          remainingUnits: 99_996,
          ordinaryRemainingUnits: 99_996,
          reservedHighPriorityUnits: 0,
          rejectedRequests: 0,
          cacheHits: 1,
          cacheEntries: 4,
          providerReportedRemaining: null,
        },
      ],
      externalRequests: 7,
      externalRequestsAvoided: 1,
      cacheHits: 1,
      cacheMisses: 7,
      retries: 0,
      fallbacks: 0,
      peakDaily: 4,
      forecast30Days: 105,
      openIdentityConflicts: 0,
      runningWorkers: 0,
      lastSyncAt: now.toISOString(),
      lastError: null,
    },
    providerSync: {
      provider: 'api-football',
      protected: true,
      healthy: true,
      status: 'healthy',
      failedLast24h: 0,
      stuckRunCount: 0,
      lastRunAt: now.toISOString(),
      lastSuccessfulAt: now.toISOString(),
      latestDataAt: now.toISOString(),
      dataQuality: {
        protected: true,
        healthy: true,
        status: 'healthy',
        stale: false,
        anomalyCount: 0,
        matchdayId: 'demo-matchday-7',
        matchdayNumber: 7,
        scheduleSource: 'provider',
        fixtureCount: 10,
        finalFixtureCount: 0,
        liveFixtureCount: 0,
        scoreCount: 0,
        finalScoreCount: 0,
        invalidScoreCount: 0,
        finalFixtureWithoutScoreCount: 0,
        scheduleMismatchCount: 0,
        snapshotMissingCount: 0,
        latestFixtureAt: now.toISOString(),
        latestScoreAt: null,
        latestSnapshot: null,
      },
      incidentCenter: {
        protected: true,
        healthy: true,
        activeCount: 0,
        criticalCount: 0,
        warningCount: 0,
        resolvedLast24h: 0,
        lastIncidentAt: null,
        lastResolvedAt: null,
        incidents: [],
      },
      recoveryCenter: {
        protected: true,
        healthy: true,
        pendingCount: 0,
        runningCount: 0,
        completedLast24h: 0,
        failedLast24h: 0,
        watchdogActive: true,
        staleRunningCount: 0,
        timedOutLast24h: 0,
        latestWatchdogAt: null,
        workerHeartbeatActive: true,
        runningHeartbeatFresh: true,
        heartbeatGraceSeconds: null,
        latestHeartbeatAt: null,
        latestProgress: null,
        retryCenter: {
          protected: true,
          healthy: true,
          automaticRetryActive: true,
          scheduledCount: 0,
          dueCount: 0,
          dispatchedCount: 0,
          succeededLast24h: 0,
          failedLast24h: 0,
          exhaustedOpenCount: 0,
          nextRetryAt: null,
          maxRetries: 3,
        },
        circuitBreaker: {
          protected: true,
          healthy: true,
          blocked: false,
          openCount: 0,
          releasedLast24h: 0,
          resolvedLast24h: 0,
          latestOpen: null,
        },
        outcomeVerification: {
          protected: true,
          healthy: true,
          outcomeVerificationActive: true,
          verifiedLast24h: 0,
          ineffectiveLast24h: 0,
          activeRetryCount: 0,
          exhaustedOpenCount: 0,
          latest: null,
        },
        workerFencing: {
          protected: true,
          healthy: true,
          workerFencingActive: true,
          activeLeaseCount: 0,
          expiredLeaseCount: 0,
          releasedLast24h: 0,
          revokedLast24h: 0,
          latestHeartbeatAt: null,
          latest: null,
        },
        latestRequestAt: null,
        canRequest: false,
        recoverableIncident: null,
        requests: [],
      },
      payloadContracts: {
        protected: true,
        healthy: true,
        runtimeValidationActive: true,
        databaseValidationActive: true,
        payloadStorageDisabled: true,
        contractVersion: 'api-football-v3/leghevo-contract-v1',
        violationsLast24h: 0,
        totalViolationCount: 0,
        latestViolationAt: null,
        latest: null,
      },
      deliveryIntegrity: {
        protected: true,
        healthy: true,
        deliveryValidationActive: true,
        completionGateActive: true,
        rawEntityStorageDisabled: true,
        deliveryVersion: 'api-football-v3/leghevo-delivery-v1',
        collectingCount: 0,
        certifiedLast24h: 1,
        rejectedLast24h: 0,
        totalCertificateCount: 1,
        latestCertificateAt: now.toISOString(),
        latest: null,
      },
      atomicPublication: {
        protected: true,
        healthy: true,
        atomicStagingActive: true,
        singleCommitPublicationActive: true,
        partialLiveWritesDisabled: true,
        stagingPayloadPurgedAfterFinish: true,
        collectingCount: 0,
        publishedLast24h: 1,
        discardedLast24h: 0,
        supersededLast24h: 0,
        totalPublicationCount: 1,
        latestPublicationAt: now.toISOString(),
        latest: null,
      },
      semanticScope: {
        protected: true,
        healthy: true,
        semanticScopeActive: true,
        operationBindingActive: true,
        crossEntityValidationActive: true,
        legacyBypassDisabled: true,
        collectingCount: 0,
        certifiedLast24h: 1,
        rejectedLast24h: 0,
        totalCertificateCount: 1,
        latestCertificateAt: now.toISOString(),
        latest: null,
      },
      publicationWatermark: {
        protected: true,
        healthy: true,
        monotonicOrderingActive: true,
        stalePublicationBlocked: true,
        completionBypassDisabled: true,
        globalScopeSerialized: true,
        activeWatermarkCount: 3,
        advancedLast24h: 1,
        staleRejectedLast24h: 0,
        latestWatermarkAt: now.toISOString(),
        latest: null,
      },
      playerCatalogReconciliation: {
        protected: true,
        healthy: true,
        authoritativeSnapshotActive: true,
        historicalSeasonRegressionBlocked: true,
        missingPlayersSoftDeactivated: true,
        exactRoleReplacementActive: true,
        physicalPlayerDeletionDisabled: true,
        collectingCount: 0,
        appliedLast24h: 1,
        supersededLast24h: 0,
        deactivatedPlayersLast24h: 2,
        removedRolesLast24h: 1,
        rosteredRetiredTotal: 0,
        totalReconciliationCount: 1,
        latestReconciliationAt: now.toISOString(),
        head: {
          id: 'demo-player-catalog-head',
          provider: 'api-football',
          competitionCode: 'IT-SA',
          season: now.getFullYear(),
          activePlayerCount: 150,
          generation: 1,
          lastTransition: 'backfilled',
          summary: 'Catalogo demo riconciliato con fotografia autorevole.',
          updatedAt: now.toISOString(),
        },
        latest: null,
      },
      fixtureLifecycleReconciliation: {
        protected: true,
        healthy: true,
        monotonicFixtureLifecycleActive: true,
        finalToNonFinalRegressionBlocked: true,
        finalGoalsPreserved: true,
        finalTeamIdentityLocked: true,
        physicalFixtureDeletionDisabled: true,
        collectingCount: 0,
        appliedLast24h: 1,
        createdFixturesLast24h: 0,
        advancedFixturesLast24h: 3,
        finalCorrectionsLast24h: 0,
        totalReconciliationCount: 1,
        latestReconciliationAt: now.toISOString(),
        head: {
          id: 'demo-fixture-lifecycle-head',
          fixtureIdFingerprint: 'demo-fixture-fingerprint',
          currentState: 'final',
          currentStatus: 'FT',
          generation: 2,
          lastTransition: 'advanced',
          summary: 'Partita demo avanzata a stato finale certificato.',
          updatedAt: now.toISOString(),
        },
        latest: null,
      },
      fixtureScoreReconciliation: {
        protected: true,
        healthy: true,
        authoritativeFixtureSnapshotActive: true,
        finalToProvisionalRegressionBlocked: true,
        missingFinalScoresSoftRetired: true,
        physicalScoreDeletionDisabled: true,
        twoTeamFinalCoverageRequired: true,
        collectingCount: 0,
        appliedLast24h: 1,
        finalAppliedLast24h: 1,
        retiredScoresLast24h: 1,
        restoredScoresLast24h: 0,
        totalReconciliationCount: 1,
        latestReconciliationAt: now.toISOString(),
        latest: null,
      },
      fixtureScoreCoherence: {
        protected: true,
        healthy: true,
        causalFixtureScoreBindingActive: true,
        fixtureGenerationAdvanceInvalidatesScores: true,
        concurrentLifecycleChangeDetected: true,
        scoreValuesPreservedWhileStale: true,
        alignedCount: 1,
        staleCount: 0,
        missingCount: 0,
        finalMissingCount: 0,
        eventsLast24h: 1,
        latestHead: {
          id: 'demo-fixture-score-coherence-head',
          fixtureIdFingerprint: 'demo-fixture-fingerprint',
          scoreGeneration: 2,
          fixtureLifecycleGeneration: 2,
          fixtureLifecycleRevision: 2,
          coherenceStatus: 'aligned',
          reasonCode: 'coherence.aligned',
          checkedAt: now.toISOString(),
        },
        latestEvent: null,
      },
      scoreConsumptionGate: {
        protected: true,
        healthy: true,
        officialResultConsumptionGateActive: true,
        staleScoresExcludedFromCalculations: true,
        blockedScoresCannotTriggerSubstitutions: true,
        scoreValuesPreservedWhileBlocked: true,
        trustedHeadCount: 1,
        blockedHeadCount: 0,
        staleHeadCount: 0,
        missingHeadCount: 0,
        blockedScoreCount: 0,
        blockedMatchdayCount: 0,
        officialFixtureRiskCount: 0,
        eventsLast24h: 1,
        latestEvent: {
          id: 'demo-score-consumption-event',
          fixtureIdFingerprint: 'demo-fixture-fingerprint',
          gateStatus: 'trusted',
          reasonCode: 'consumption.aligned',
          scoreGeneration: 2,
          fixtureLifecycleGeneration: 2,
          createdAt: now.toISOString(),
        },
      },
      officialResultImpact: {
        protected: true,
        healthy: true,
        preciseOfficialResultLineageActive: true,
        officialResultsNeverMutatedAutomatically: true,
        protectedCorrectionWorkflowAvailable: true,
        clearFixtureCount: 5,
        affectedFixtureCount: 0,
        inCorrectionFixtureCount: 0,
        affectedMatchdayCount: 0,
        eventsLast24h: 1,
        latestEvent: {
          id: 'demo-official-impact-event',
          fixtureId: 'demo-fantasy-fixture',
          matchdayId: 'demo-matchday',
          impactStatus: 'clear',
          reasonCode: 'impact.official_inputs_current',
          assessmentGeneration: 1,
          affectedSideCount: 0,
          createdAt: now.toISOString(),
        },
      },
      officialResultRemediation: {
        protected: true,
        healthy: true,
        raceSafeRemediationActive: true,
        staleAssessmentRejected: true,
        resultsNeverMutatedAutomatically: true,
        openCount: 0,
        inCorrectionCount: 0,
        resolvedCount: 1,
        uncertifiedCorrectionCount: 0,
        eventsLast24h: 1,
        items: [],
      },
      officialResultLineage: {
        protected: true,
        healthy: true,
        officializationCommitBarrierActive: true,
        transientMissingLineageSuppressed: true,
        correctionSourceLinkCertified: true,
        certifiedFixtureCount: 5,
        assemblingFixtureCount: 0,
        invalidFixtureCount: 0,
        reopenedFixtureCount: 0,
        eventsLast24h: 1,
        latestEvent: {
          id: 'demo-official-lineage-event',
          fixtureId: 'demo-fantasy-fixture',
          matchdayId: 'demo-matchday',
          lineageStatus: 'certified',
          reasonCode: 'lineage.commit_certified',
          lineageGeneration: 2,
          fixtureResultRevision: 1,
          createdAt: now.toISOString(),
        },
      },
      officialResultRemediationCompletion: {
        protected: true,
        healthy: true,
        causalCompletionCertificateActive: true,
        resolvedOnlyAfterCertifiedEvidence: true,
        automaticRecoveryDistinguished: true,
        pendingCount: 0,
        certifiedCount: 1,
        invalidCount: 0,
        supersededCount: 0,
        autoRecoveredCount: 0,
        correctionCertifiedCount: 1,
        uncertifiedResolvedCount: 0,
        eventsLast24h: 1,
        latestEvent: {
          id: 'demo-remediation-completion-event',
          fixtureId: 'demo-fantasy-fixture',
          matchdayId: 'demo-matchday',
          eventType: 'certified',
          completionStatus: 'certified',
          resolutionMode: 'correction_certified',
          reasonCode: 'completion.correction_lineage_certified',
          remediationGeneration: 1,
          completionGeneration: 1,
          createdAt: now.toISOString(),
        },
      },
      matchdayProgressionGate: {
        protected: true,
        healthy: true,
        causalProgressionBarrierActive: true,
        legacyProgressionBypassBlocked: true,
        priorMatchdayChainProtected: true,
        clearMatchdayCount: 4,
        blockedMatchdayCount: 0,
        affectedMatchdayCount: 0,
        unsafeProgressionCount: 0,
        eventsLast24h: 1,
        latestEvent: {
          id: 'demo-progression-gate-event',
          matchdayId: 'demo-matchday',
          matchdayNumber: 1,
          eventType: 'clear',
          gateStatus: 'clear',
          reasonCode: 'progression.causal_chain_certified',
          gateGeneration: 1,
          currentOfficializationRunId: 'demo-officialization-run',
          currentProgressionRunId: 'demo-progression-run',
          unsafeFixtureCount: 0,
          priorUnsafeProgressionCount: 0,
          createdAt: now.toISOString(),
        },
      },
      seasonCompletionGate: {
        protected: true,
        healthy: true,
        causalSeasonCompletionBarrierActive: true,
        legacySeasonCompletionBypassBlocked: true,
        progressionChainLocked: true,
        gateStatus: 'blocked',
        reasonCode: 'season_completion.progression_chain_incomplete',
        completionRunId: null,
        finalMatchdayId: 'demo-matchday',
        finalProgressionRunId: 'demo-progression-run',
        matchdayCount: 38,
        clearMatchdayCount: 4,
        unsafeMatchdayCount: 34,
        missingGateCount: 34,
        mismatchedProgressionCount: 0,
        completionAffected: false,
        eventsLast24h: 1,
        latestEvent: {
          id: 'demo-season-completion-event',
          eventType: 'blocked',
          gateStatus: 'blocked',
          reasonCode: 'season_completion.progression_chain_incomplete',
          gateGeneration: 1,
          currentCompletionRunId: null,
          finalMatchdayId: 'demo-matchday',
          finalProgressionRunId: 'demo-progression-run',
          unsafeMatchdayCount: 34,
          missingGateCount: 34,
          mismatchedProgressionCount: 0,
          createdAt: now.toISOString(),
        },
      },
      seasonOfficialSnapshot: {
        protected: true,
        published: false,
        healthy: true,
        status: 'pending',
        reasonCode: 'season_snapshot.not_published',
        affected: false,
        snapshotId: null,
        snapshotHash: null,
        standingsHash: null,
        completionRunId: null,
        completionGateGeneration: null,
        completionGateFingerprint: null,
        season: '2026',
        champion: null,
        podium: [],
        finalStandings: [],
        officializedAt: null,
        affectedAt: null,
      },
      providerSeasonBootstrap: {
        protected: true,
        applicable: false,
        healthy: true,
        affected: false,
        status: 'waiting',
        reasonCode: 'provider_bootstrap.not_required',
        season: 2026,
        catalogReady: true,
        fixturesReady: true,
        certified: false,
        certificateId: null,
        bootstrapHash: null,
        catalogGeneration: 1,
        catalogPlayerCount: 150,
        fixtureCount: 380,
        matchdayCount: 38,
        fixtureTeamCount: 20,
      },
      providerCompetitionStart: {
        protected: true,
        applicable: true,
        healthy: true,
        affected: false,
        status: 'official',
        reasonCode: 'provider_competition_start.official',
        started: true,
        ready: true,
        certified: true,
        certificateId: 1,
        startHash: '00000000000000000000000000000000',
        season: 2026,
        fantasyFixtureCount: 342,
        fantasyMatchdayCount: 38,
        fantasyTeamCount: 10,
      },
      providerReliabilityModel: {
        protected: true,
        modelClosed: true,
        healthy: true,
        schemaCertified: true,
        operationalHealthy: true,
        status: 'certified',
        reasonCode: 'provider_reliability.certified',
        modelKey: 'provider_reliability_v1',
        modelVersion: 1,
        applicationVersion: '0.62.32',
        certifiedAt: now.toISOString(),
        schemaFingerprint: '11111111111111111111111111111111',
        storedSchemaFingerprint: '11111111111111111111111111111111',
        fingerprintStable: true,
        checkCount: 20,
        passedCount: 20,
      },
      applicationIntegrityModel: {
        protected: true,
        modelClosed: true,
        healthy: true,
        schemaCertified: true,
        status: 'certified',
        reasonCode: 'application_integrity.certified',
        modelKey: 'application_integrity_v1',
        modelVersion: 1,
        applicationVersion: '0.62.33',
        certifiedAt: now.toISOString(),
        schemaFingerprint: '22222222222222222222222222222222',
        storedSchemaFingerprint: '22222222222222222222222222222222',
        fingerprintStable: true,
        checkCount: 20,
        passedCount: 20,
      },
      applicationRolloutModel: {
        protected: true,
        healthy: true,
        active: true,
        status: 'completed',
        reasonCode: 'rollout.completed',
        environment: 'production',
        releaseVersion: '0.62.41',
        stage: 'completed',
        exposurePercentage: 100,
        rolloutGeneration: 5,
        killSwitchActive: false,
        planFingerprintStable: true,
        latestHealthVerdict: 'healthy',
        latestErrorRateBps: 20,
        latestCrashCount: 0,
        latestHealthAt: now.toISOString(),
        startedAt: now.toISOString(),
        promotedAt: now.toISOString(),
      },
      applicationOperationalTelemetry: {
        protected: true,
        healthy: true,
        authoritative: true,
        status: 'active',
        reasonCode: 'telemetry.healthy',
        environment: 'production',
        sourceKey: 'leghevo-production-observer',
        sourceGeneration: 6,
        telemetryGeneration: 6,
        lastWindowSequence: 1,
        lastWindowStartedAt: now.toISOString(),
        lastWindowEndedAt: now.toISOString(),
        latestVerdict: 'healthy',
        latestErrorRateBps: 20,
        latestCrashCount: 0,
        latestP95LatencyMs: 220,
        latestExposurePercentage: 100,
        latestReleaseVersion: '0.62.41',
        autoRollbackEnabled: true,
        autoRollbackTriggered: false,
        fingerprintStable: true,
      },
      applicationOperationalOutbox: {
        protected: true,
        healthy: true,
        status: 'active',
        reasonCode: 'outbox.active',
        environment: 'production',
        captureReady: true,
        messageCount: 42,
        destinationCount: 84,
        pendingCount: 0,
        leasedCount: 0,
        retryCount: 0,
        deliveredCount: 84,
        deadLetterCount: 0,
        expiredLeaseCount: 0,
        lastSequence: 42,
        sequenceGapCount: 0,
        fingerprintMismatchCount: 0,
        oldestPendingAt: null,
        lastDeliveredAt: now.toISOString(),
        lastDeadLetterAt: null,
      },
      applicationOperationalConsumerDelivery: {
        protected: true,
        healthy: true,
        authoritative: true,
        status: 'active',
        reasonCode: 'consumer_delivery.active',
        environment: 'production',
        consumerCount: 2,
        receiptCount: 96,
        liveReceiptCount: 12,
        adoptedReceiptCount: 84,
        expectedReceiptCount: 96,
        replayRequestCount: 0,
        sequenceGapCount: 0,
        fingerprintMismatchCount: 0,
        receiptConsistencyMismatchCount: 0,
        lastAcknowledgedSequence: 48,
        lastAcknowledgedAt: now.toISOString(),
      },
      applicationOperationalDeliveryAudit: {
        protected: true,
        healthy: true,
        fresh: true,
        status: 'certified',
        reasonCode: 'delivery_audit.certified',
        environment: 'production',
        auditGeneration: 5,
        auditedThroughSequence: 54,
        currentLastSequence: 54,
        messageCount: 54,
        expectedDeliveryCount: 108,
        deliveryCount: 108,
        receiptCount: 108,
        sequenceGapCount: 0,
        consistencyMismatchCount: 0,
        fingerprintMismatchCount: 0,
        headMismatchCount: 0,
        deadLetterCount: 0,
        affectedDestinationCount: 0,
        lastAuditAt: now.toISOString(),
      },
      applicationDisasterRecovery: {
        protected: true,
        healthy: true,
        fresh: true,
        status: 'certified',
        reasonCode: 'disaster_recovery.certified',
        environment: 'production',
        checkpointGeneration: 6,
        drillGeneration: 6,
        activeVersion: '0.62.43',
        releaseGeneration: 3,
        rolloutGeneration: 1,
        exposurePercentage: 100,
        telemetryGeneration: 6,
        outboxSequence: 60,
        consumerSequence: 60,
        auditedSequence: 60,
        componentCount: 7,
        lastCheckpointAt: now.toISOString(),
        lastDrillAt: now.toISOString(),
      },
      applicationPhysicalBackup: {
        protected: true,
        healthy: true,
        fresh: true,
        status: 'certified',
        reasonCode: 'physical_backup.certified',
        environment: 'production',
        backupGeneration: 1,
        custodySequence: 4,
        rehearsalGeneration: 1,
        activeVersion: '0.62.43',
        checkpointGeneration: 6,
        artifactSizeBytes: 734003200,
        checksumVerified: true,
        custodyComplete: true,
        restoreVerified: true,
        lastArtifactAt: now.toISOString(),
        lastRehearsalAt: now.toISOString(),
      },
      applicationServiceReturn: {
        protected: true,
        healthy: true,
        fresh: true,
        status: 'certified',
        reasonCode: 'service_return.certified',
        environment: 'production',
        mode: 'active',
        recoveryGeneration: 3,
        activeVersion: '0.62.43',
        checkCount: 8,
        requiredCheckCount: 8,
        writesAllowed: true,
        workersAllowed: true,
        trafficPercentage: 100,
        lastRecoveryStartedAt: now.toISOString(),
        lastCertifiedAt: now.toISOString(),
      },
      applicationProductionReadiness: {
        protected: true,
        healthy: true,
        fresh: true,
        status: 'certified',
        reasonCode: 'production_readiness.certified',
        environment: 'production',
        readinessGeneration: 1,
        activeVersion: '0.62.43',
        checkCount: 10,
        requiredCheckCount: 10,
        goLiveAllowed: true,
        fingerprintStable: true,
        certifiedAt: now.toISOString(),
        affectedAt: null,
      },
      applicationReleaseModel: {
        protected: true,
        healthy: true,
        active: true,
        status: 'active',
        reasonCode: 'release.active',
        environment: 'production',
        activeVersion: '0.62.43',
        previousVersion: '0.62.42',
        minSupportedVersion: '0.62.42',
        maxSupportedVersion: '0.62.43',
        releaseGeneration: 3,
        rollbackActive: false,
        schemaCertified: true,
        fingerprintStable: true,
        bundleFingerprint: '3333333333333333333333333333333333333333333333333333333333333333',
        certifiedAt: now.toISOString(),
        activatedAt: now.toISOString(),
      },
      actions: [
        {
          action: 'sync-fixtures',
          status: 'completed',
          startedAt: now.toISOString(),
          finishedAt: now.toISOString(),
          recordsProcessed: 10,
          revision: 2,
          attempt: 1,
        },
        {
          action: 'sync-fixture-players',
          status: 'completed',
          startedAt: now.toISOString(),
          finishedAt: now.toISOString(),
          recordsProcessed: 22,
          revision: 2,
          attempt: 1,
        },
      ],
    },
  };
}

export function useLeagueOperations(
  leagueId: string | null,
  isDemo: boolean,
) {
  const [center, setCenter] = useState<LeagueOperationsCenter | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [actionLoading, setActionLoading] = useState(false);
  const [actionError, setActionError] = useState('');
  const [reminderOutcome, setReminderOutcome] =
    useState<LeagueLineupReminderOutcome | null>(null);
  const [recoveryLoading, setRecoveryLoading] = useState(false);
  const [recoveryError, setRecoveryError] = useState('');
  const [recoveryOutcome, setRecoveryOutcome] =
    useState<ProviderRecoveryRequestOutcome | null>(null);
  const [circuitBreakerLoading, setCircuitBreakerLoading] = useState(false);
  const [circuitBreakerError, setCircuitBreakerError] = useState('');
  const [circuitBreakerOutcome, setCircuitBreakerOutcome] =
    useState<ProviderRecoveryCircuitBreakerReleaseOutcome | null>(null);

  const refresh = useCallback(
    async (quiet = false) => {
      if (!leagueId) {
        setCenter(null);
        setError('');
        setLoading(false);
        return;
      }
      if (isDemo) {
        setCenter(createDemoOperationsCenter());
        setError('');
        setLoading(false);
        return;
      }

      if (!quiet) {
        setLoading(true);
      }
      try {
        setCenter(await fetchLeagueOperationsCenter(leagueId));
        setError('');
      } catch (cause) {
        setError(
          cause instanceof Error
            ? cause.message
            : 'Il Centro Operativo non risponde.',
        );
      } finally {
        setLoading(false);
      }
    },
    [isDemo, leagueId],
  );

  useEffect(() => {
    setReminderOutcome(null);
    setActionError('');
    setRecoveryOutcome(null);
    setRecoveryError('');
    setCircuitBreakerOutcome(null);
    setCircuitBreakerError('');
    void refresh();
  }, [refresh]);

  useEffect(() => {
    if (!leagueId || isDemo) {
      return;
    }
    return subscribeToLeagueOperations(leagueId, () => void refresh(true));
  }, [isDemo, leagueId, refresh]);

  useEffect(() => {
    if (!leagueId || isDemo) {
      return;
    }
    const subscription = AppState.addEventListener('change', (nextState) => {
      if (nextState === 'active') {
        void refresh(true);
      }
    });
    return () => subscription.remove();
  }, [isDemo, leagueId, refresh]);

  const sendReminders = async (matchdayId: string) => {
    if (!leagueId) {
      return { error: 'Prima scegli una lega.' };
    }
    if (isDemo) {
      const outcome: LeagueLineupReminderOutcome = {
        matchdayId,
        matchdayNumber: center?.nextLineupMatchday?.number ?? 0,
        targetCount:
          (center?.nextLineupMatchday?.draftCount ?? 0) +
          (center?.nextLineupMatchday?.missingCount ?? 0),
        sentCount:
          (center?.nextLineupMatchday?.draftCount ?? 0) +
          (center?.nextLineupMatchday?.missingCount ?? 0),
        alreadySentCount: 0,
      };
      setReminderOutcome(outcome);
      setActionError('');
      return { data: outcome };
    }

    setActionLoading(true);
    setActionError('');
    try {
      const outcome = await sendLeagueLineupReminders(
        leagueId,
        matchdayId,
      );
      if ('error' in outcome) {
        setActionError(
          outcome.error ?? 'Non riesco a inviare i promemoria.',
        );
      } else {
        setReminderOutcome(outcome.data);
        await refresh(true);
      }
      return outcome;
    } finally {
      setActionLoading(false);
    }
  };

  const requestRecovery = async (
    incidentId: string,
    expectedIncidentRevision: number,
  ) => {
    if (!leagueId) {
      return { error: 'Prima scegli una lega.' };
    }
    if (isDemo) {
      const outcome: ProviderRecoveryRequestOutcome = {
        requestId: 'demo-provider-recovery',
        incidentId,
        status: 'pending',
        revision: 1,
        attempt: 0,
        recoveryRunId: null,
        reused: false,
      };
      setRecoveryOutcome(outcome);
      setRecoveryError('');
      return { data: outcome };
    }

    setRecoveryLoading(true);
    setRecoveryError('');
    try {
      const outcome = await requestLeagueProviderRecovery(
        leagueId,
        incidentId,
        expectedIncidentRevision,
      );
      if ('error' in outcome) {
        setRecoveryError(
          outcome.error ?? 'Non riesco ad accodare il recupero provider.',
        );
      } else {
        setRecoveryOutcome(outcome.data);
        await refresh(true);
      }
      return outcome;
    } finally {
      setRecoveryLoading(false);
    }
  };

  const releaseCircuitBreaker = async (
    breakerId: string,
    expectedRevision: number,
  ) => {
    if (!leagueId) {
      return { error: 'Prima scegli una lega.' };
    }
    if (isDemo) {
      const outcome: ProviderRecoveryCircuitBreakerReleaseOutcome = {
        breakerId,
        incidentId: 'demo-provider-incident',
        status: 'released',
        revision: expectedRevision + 1,
        releasedAt: new Date().toISOString(),
        reused: false,
      };
      setCircuitBreakerOutcome(outcome);
      setCircuitBreakerError('');
      return { data: outcome };
    }

    setCircuitBreakerLoading(true);
    setCircuitBreakerError('');
    try {
      const outcome = await releaseLeagueProviderCircuitBreaker(
        leagueId,
        breakerId,
        expectedRevision,
      );
      if ('error' in outcome) {
        setCircuitBreakerError(
          outcome.error ?? 'Non riesco a riaprire i recuperi provider.',
        );
      } else {
        setCircuitBreakerOutcome(outcome.data);
        await refresh(true);
      }
      return outcome;
    } finally {
      setCircuitBreakerLoading(false);
    }
  };

  return {
    center,
    loading,
    error,
    actionLoading,
    actionError,
    reminderOutcome,
    recoveryLoading,
    recoveryError,
    recoveryOutcome,
    circuitBreakerLoading,
    circuitBreakerError,
    circuitBreakerOutcome,
    refresh,
    sendReminders,
    requestRecovery,
    releaseCircuitBreaker,
  };
}
