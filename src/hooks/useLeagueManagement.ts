import { useCallback, useEffect, useState } from 'react';
import { AppState } from 'react-native';
import {
  fetchLeagueAccessSession,
  fetchLeagueManagementState,
  setLeagueInvitesOpen,
  startLeagueCompetition,
  subscribeToLeagueDirection,
  transferLeaguePresidency,
} from '../services/leagueManagementService';
import {
  completeLeagueSeason,
  renewLeagueSeason,
} from '../services/seasonService';
import type { LeagueAccessSession, LeagueManagementState } from '../types';

const demoState: LeagueManagementState = {
  memberCount: 8,
  teamLimit: 8,
  teamCount: 8,
  fullRosterCount: 8,
  rosterSize: 25,
  fixtureCount: 56,
  officialFixtureCount: 4,
  remainingFixtureCount: 52,
  invitesOpen: false,
  competitionStartedAt: '2026-09-01T18:00:00Z',
  completedAt: null,
  status: 'active',
  season: '2026',
  champion: null,
  isOwner: true,
  canStart: false,
  canComplete: false,
  seasonCompletionCausalStatus: 'blocked',
  seasonCompletionCausalReason: 'season_completion.progression_chain_incomplete',
  seasonCompletionCausallyCertified: false,
  seasonCompletionAffected: false,
  officialSnapshotProtected: true,
  officialSnapshotPublished: false,
  officialSnapshotHealthy: true,
  officialSnapshotStatus: 'pending',
  officialSnapshotReason: 'season_snapshot.not_published',
  officialSnapshotAffected: false,
  officialSnapshotId: null,
  officialSnapshotHash: null,
  officialPodium: [],
  seasonRolloverProtected: true,
  seasonRolloverCertified: false,
  seasonRolloverHealthy: true,
  seasonRolloverStatus: 'pending',
  seasonRolloverReason: 'season_rollover.not_created',
  seasonRolloverAffected: false,
  seasonRolloverCertificateId: null,
  seasonRolloverLineageHash: null,
  seasonRolloverSourceSnapshotHash: null,
  providerSeasonBootstrapProtected: true,
  providerSeasonBootstrapApplicable: false,
  providerSeasonBootstrapHealthy: true,
  providerSeasonBootstrapAffected: false,
  providerSeasonBootstrapStatus: 'waiting',
  providerSeasonBootstrapReason: 'provider_bootstrap.not_required',
  providerSeasonCatalogReady: true,
  providerSeasonFixturesReady: true,
  providerSeasonBootstrapCertified: false,
  providerSeasonBootstrapCertificateId: null,
  providerSeasonBootstrapHash: null,
  providerCompetitionStartProtected: true,
  providerCompetitionStartApplicable: false,
  providerCompetitionStartHealthy: true,
  providerCompetitionStartAffected: false,
  providerCompetitionStartStatus: 'official',
  providerCompetitionStartReason: 'provider_competition_start.not_required',
  providerCompetitionStartReady: true,
  providerCompetitionStartCertified: false,
  providerCompetitionStartCertificateId: null,
  providerCompetitionStartHash: null,
  canRenew: false,
  previousLeagueId: null,
  previousSeason: null,
  nextLeagueId: null,
  nextSeason: '2027',
  renewedAt: null,
  renewalCopiedMemberCount: 0,
  competitionLifecycle: {
    started: true,
    startedAt: '2026-09-01T18:00:00Z',
    startedBy: null,
    revision: 1,
    startVersion: 2,
    openingVersion: 1,
    openingVerifiedAt: '2026-09-01T18:00:00Z',
    currentMatchdayId: null,
    currentMatchdayNumber: 1,
    openingMatchdayId: null,
    openingMatchdayNumber: 1,
    openingStartsAt: '2026-09-06T13:00:00Z',
    openingLocksAt: '2026-09-06T12:55:00Z',
    openingFixtureCount: 4,
    expectedOpeningFixtureCount: 4,
    openingReady: true,
    activationProtected: true,
    modelClosed: true,
    modelClosedAt: '2026-09-01T18:00:00Z',
    modelVersion: 1,
    structureVerifiedAt: '2026-09-01T18:00:00Z',
    fixtureStructureProtected: true,
    leagueStructureProtected: true,
    calendarFingerprintStable: true,
    calendarCountsReady: true,
    integrityHealthy: true,
    eventCount: 2,
  },
  roleControl: {
    integrity: {
      healthy: true,
      ownerMemberExists: true,
      ownerProfileActive: true,
      teamManagersAreMembers: true,
      oneTeamPerManager: true,
      memberCount: 8,
      adminCount: 2,
      teamCount: 8,
      orphanTeamCount: 0,
      duplicateTeamManagerCount: 0,
    },
    security: {
      hardened: true,
      presidentCount: 1,
      adminCount: 1,
      managerCount: 6,
      directRoleMutationBlocked: true,
      directPresidencyMutationBlocked: true,
      directRemovalBlocked: true,
      guardedActionsReady: true,
      members: [],
    },
    events: [],
  },
  permissions: {
    role: 'president',
    isMember: true,
    isOwner: true,
    isAdmin: true,
    hasTeam: true,
    canAccessDirection: true,
    canRunOperations: true,
    canEditRules: true,
    canManageInvites: true,
    canManageMembers: true,
    canManageAdmins: true,
    canTransferPresidency: false,
    canStartCompetition: true,
    canCloseSeason: true,
    canSubmitLineup: true,
    canUseMarket: true,
  },
  accessSession: {
    accessValid: true,
    reason: null,
    revision: 1,
    roleUpdatedAt: '2026-07-01T18:00:00Z',
    permissions: {
      role: 'president',
      isMember: true,
      isOwner: true,
      isAdmin: true,
      hasTeam: true,
      canAccessDirection: true,
      canRunOperations: true,
      canEditRules: true,
      canManageInvites: true,
      canManageMembers: true,
      canManageAdmins: true,
      canTransferPresidency: false,
      canStartCompetition: true,
      canCloseSeason: true,
      canSubmitLineup: true,
      canUseMarket: true,
    },
  },
  checks: {
    membersReady: true,
    teamsReady: true,
    rostersReady: true,
    calendarReady: true,
    marketReady: true,
    tradesSettled: true,
    auctionIntegrityReady: true,
    auctionClosed: true,
    calendarIntegrityReady: true,
    calendarSnapshotStable: true,
    precompetitionSnapshotLocked: true,
    snapshotMutationGuardReady: true,
    competitionActivationReady: true,
    competitionModelClosed: true,
    matchdayProgressionReady: true,
    seasonCompletionCertified: false,
    seasonCompletionCausalReady: false,
    seasonOfficialSnapshotProtected: true,
    seasonOfficialSnapshotPublished: false,
    seasonOfficialSnapshotHealthy: true,
    seasonRolloverProtected: true,
    seasonRolloverCertified: false,
    seasonRolloverHealthy: true,
    providerSeasonBootstrapProtected: true,
    providerSeasonCatalogReady: true,
    providerSeasonFixturesReady: true,
    providerSeasonBootstrapCertified: false,
    providerSeasonBootstrapHealthy: true,
    providerCompetitionStartProtected: true,
    providerCompetitionStartReady: true,
    providerCompetitionStartCertified: false,
    providerCompetitionStartHealthy: true,
    lineupLifecycleReady: true,
    liveLifecycleReady: true,
    matchdayLifecycleReady: true,
    matchdayModelClosed: true,
    specialCompetitionsModelClosed: true,
  },
};

export function useLeagueManagement(
  leagueId: string | null,
  isDemo: boolean,
) {
  const [state, setState] = useState<LeagueManagementState | null>(null);
  const [access, setAccess] = useState<LeagueAccessSession | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');

  const refresh = useCallback(async (silent = false) => {
    if (!leagueId) {
      setState(null);
      setAccess(null);
      setError('');
      setLoading(false);
      return;
    }

    if (isDemo) {
      setState(demoState);
      setAccess(demoState.accessSession);
      setError('');
      setLoading(false);
      return;
    }

    if (!silent) {
      setLoading(true);
    }
    try {
      const nextAccess = await fetchLeagueAccessSession(leagueId);
      setAccess(nextAccess);

      if (!nextAccess.accessValid || !nextAccess.permissions.canAccessDirection) {
        setState(null);
        setError('');
        return;
      }

      const nextState = await fetchLeagueManagementState(leagueId);
      setState(nextState);
      setAccess(nextState.accessSession);
      setError('');
    } catch (cause) {
      setError(
        cause instanceof Error
          ? cause.message
          : 'La direzione della lega non risponde.',
      );
    } finally {
      setLoading(false);
    }
  }, [isDemo, leagueId]);

  useEffect(() => {
    void refresh();
  }, [refresh]);

  useEffect(() => {
    if (!leagueId || isDemo) {
      return;
    }

    return subscribeToLeagueDirection(leagueId, () => void refresh(true));
  }, [isDemo, leagueId, refresh]);

  useEffect(() => {
    if (!leagueId || isDemo) {
      return;
    }

    const subscription = AppState.addEventListener('change', (next) => {
      if (next === 'active') {
        void refresh(true);
      }
    });

    return () => subscription.remove();
  }, [isDemo, leagueId, refresh]);

  const setInvitesOpen = async (open: boolean) => {
    if (!leagueId) {
      return { error: 'Prima scegli una lega.' };
    }
    if (isDemo) {
      setState((current) =>
        current ? { ...current, invitesOpen: open } : current,
      );
      return {};
    }

    const outcome = await setLeagueInvitesOpen(leagueId, open);
    if (!outcome.error) {
      await refresh(true);
    }
    return outcome;
  };

  const transferPresidency = async (
    newOwnerId: string,
    expectedRevision: number,
  ) => {
    if (!leagueId) {
      return { error: 'Prima scegli una lega.' };
    }
    if (isDemo) {
      return { error: 'La presidenza demo resta negli spogliatoi demo.' };
    }

    const outcome = await transferLeaguePresidency(
      leagueId,
      newOwnerId,
      expectedRevision,
    );
    if (!outcome.error) {
      await refresh(true);
    }
    return outcome;
  };

  const startCompetition = async () => {
    if (!leagueId) {
      return { error: 'Prima scegli una lega.' };
    }
    if (isDemo) {
      return { error: 'La competizione demo è già iniziata.' };
    }

    const outcome = await startLeagueCompetition(leagueId);
    if (!outcome.error) {
      await refresh(true);
    }
    return outcome;
  };

  const completeCompetition = async () => {
    if (!leagueId) {
      return { error: 'Prima scegli una lega.' };
    }
    if (isDemo) {
      return {
        error: 'La stagione demo resta aperta per mostrare risultati e Live.',
      };
    }

    const outcome = await completeLeagueSeason(leagueId);
    if (!outcome.error) {
      await refresh(true);
    }
    return outcome;
  };

  const renewCompetition = async (nextSeason: string) => {
    if (!leagueId) {
      return { error: 'Prima scegli una lega.' };
    }
    if (isDemo) {
      return {
        error: 'La stagione demo resta quella attuale.',
      };
    }

    const outcome = await renewLeagueSeason(leagueId, nextSeason);
    if (!outcome.error) {
      await refresh(true);
    }
    return outcome;
  };

  return {
    state,
    access,
    loading,
    error,
    refresh,
    setInvitesOpen,
    transferPresidency,
    startCompetition,
    completeCompetition,
    renewCompetition,
  };
}
