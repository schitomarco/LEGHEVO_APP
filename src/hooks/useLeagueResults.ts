import { useCallback, useEffect, useState } from 'react';
import { AppState } from 'react-native';
import {
  fetchLeagueResultsCenter,
  finalizeLeagueMatchday,
  reopenLeagueFixture,
  reopenLeagueMatchday,
  subscribeToLeagueResultsCenter,
} from '../services/resultsService';
import type { LeagueResultsCenter } from '../types';

const demoResultsCenter: LeagueResultsCenter = {
  leagueId: 'demo-league',
  leagueName: 'Serie A da Divano',
  isOwner: true,
  competitionStartedAt: '2026-09-01T18:00:00Z',
  goalThreshold: 66,
  goalStep: 6,
  goalBandsEnabled: true,
  goalBands: [65, 71, 77, 83, 90, 96],
  goalMarginEnabled: true,
  goalMargin: 4,
  matchdays: [
    {
      id: 'demo-matchday-6',
      number: 6,
      startsAt: '2026-09-12T18:00:00Z',
      endsAt: '2026-09-16T18:00:00Z',
      fixtureCount: 2,
      readyCount: 2,
      officialCount: 2,
      status: 'official',
      canFinalize: false,
      canReopen: true,
      fixtures: [
        {
          id: 'demo-result-1',
          homeTeamId: 'demo-team',
          homeTeamName: 'Diavoli del Sud',
          awayTeamId: 'demo-team-2',
          awayTeamName: 'Tiki Taka Boom',
          homePoints: 72.5,
          awayPoints: 68,
          homeBasePoints: 68.5,
          awayBasePoints: 67,
          homeDefenseModifier: 4,
          awayDefenseModifier: 1,
          homeBonusApplied: 0,
          homeGoalMarginBonus: 0,
          awayGoalMarginBonus: 0,
          homeGoals: 2,
          awayGoals: 1,
          homeCountedPlayers: 11,
          awayCountedPlayers: 11,
          homeReady: true,
          awayReady: true,
          finalizedAt: '2026-09-16T20:00:00Z',
          canCorrect: true,
          revision: 1,
          correctionReason: null,
          correctedAt: null,
          status: 'official',
          providerImpactStatus: null,
          providerImpactGeneration: null,
          providerImpactReasonCode: null,
          providerRemediationStatus: null,
          providerRemediationRequired: false,
          providerCausalStartCertified: false,
        },
        {
          id: 'demo-result-2',
          homeTeamId: 'demo-team-3',
          homeTeamName: 'Atletico Ma Non Troppo',
          awayTeamId: 'demo-team-4',
          awayTeamName: 'Real Colizzati',
          homePoints: 65,
          awayPoints: 66,
          homeBasePoints: 65,
          awayBasePoints: 66,
          homeDefenseModifier: 0,
          awayDefenseModifier: 0,
          homeBonusApplied: 0,
          homeGoalMarginBonus: 0,
          awayGoalMarginBonus: 0,
          homeGoals: 0,
          awayGoals: 1,
          homeCountedPlayers: 11,
          awayCountedPlayers: 11,
          homeReady: true,
          awayReady: true,
          finalizedAt: '2026-09-16T20:00:00Z',
          canCorrect: true,
          revision: 2,
          correctionReason: 'Assist corretto dal provider ufficiale.',
          correctedAt: '2026-09-16T20:15:00Z',
          status: 'official',
          providerImpactStatus: null,
          providerImpactGeneration: null,
          providerImpactReasonCode: null,
          providerRemediationStatus: null,
          providerRemediationRequired: false,
          providerCausalStartCertified: false,
        },
      ],
    },
    {
      id: 'demo-matchday-7',
      number: 7,
      startsAt: '2026-09-19T18:00:00Z',
      endsAt: '2026-09-23T18:00:00Z',
      fixtureCount: 2,
      readyCount: 1,
      officialCount: 0,
      status: 'live',
      canFinalize: false,
      canReopen: false,
      fixtures: [
        {
          id: 'demo-result-3',
          homeTeamId: 'demo-team-4',
          homeTeamName: 'Real Colizzati',
          awayTeamId: 'demo-team',
          awayTeamName: 'Diavoli del Sud',
          homePoints: 67.5,
          awayPoints: 70,
          homeBasePoints: 66.5,
          awayBasePoints: 68,
          homeDefenseModifier: 1,
          awayDefenseModifier: 2,
          homeBonusApplied: 0,
          homeGoalMarginBonus: 0,
          awayGoalMarginBonus: 0,
          homeGoals: 1,
          awayGoals: 1,
          homeCountedPlayers: 10,
          awayCountedPlayers: 11,
          homeReady: false,
          awayReady: true,
          finalizedAt: null,
          canCorrect: false,
          revision: 0,
          correctionReason: null,
          correctedAt: null,
          status: 'provisional',
          providerImpactStatus: null,
          providerImpactGeneration: null,
          providerImpactReasonCode: null,
          providerRemediationStatus: null,
          providerRemediationRequired: false,
          providerCausalStartCertified: false,
        },
        {
          id: 'demo-result-4',
          homeTeamId: 'demo-team-2',
          homeTeamName: 'Tiki Taka Boom',
          awayTeamId: 'demo-team-3',
          awayTeamName: 'Atletico Ma Non Troppo',
          homePoints: 66,
          awayPoints: 64,
          homeBasePoints: 66,
          awayBasePoints: 64,
          homeDefenseModifier: 0,
          awayDefenseModifier: 0,
          homeBonusApplied: 0,
          homeGoalMarginBonus: 0,
          awayGoalMarginBonus: 0,
          homeGoals: 1,
          awayGoals: 0,
          homeCountedPlayers: 11,
          awayCountedPlayers: 11,
          homeReady: true,
          awayReady: true,
          finalizedAt: null,
          canCorrect: false,
          revision: 0,
          correctionReason: null,
          correctedAt: null,
          status: 'ready',
          providerImpactStatus: null,
          providerImpactGeneration: null,
          providerImpactReasonCode: null,
          providerRemediationStatus: null,
          providerRemediationRequired: false,
          providerCausalStartCertified: false,
        },
      ],
    },
  ],
};

export function useLeagueResults(
  leagueId: string | null,
  isDemo: boolean,
) {
  const [center, setCenter] = useState<LeagueResultsCenter | null>(null);
  const [loading, setLoading] = useState(true);
  const [actionLoading, setActionLoading] = useState(false);
  const [error, setError] = useState('');
  const [actionError, setActionError] = useState('');

  const refresh = useCallback(
    async (silent = false) => {
      if (!leagueId) {
        setCenter(null);
        setError('');
        setLoading(false);
        return;
      }

      if (isDemo) {
        setCenter(demoResultsCenter);
        setError('');
        setLoading(false);
        return;
      }

      if (!silent) {
        setLoading(true);
      }
      try {
        setCenter(await fetchLeagueResultsCenter(leagueId));
        setError('');
      } catch (caught) {
        setError(
          caught instanceof Error
            ? caught.message
            : 'I risultati non arrivano dal campo.',
        );
      } finally {
        setLoading(false);
      }
    },
    [isDemo, leagueId],
  );

  useEffect(() => {
    void refresh();
  }, [refresh]);

  useEffect(() => {
    if (!leagueId || isDemo) {
      return;
    }
    return subscribeToLeagueResultsCenter(leagueId, () =>
      void refresh(true),
    );
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

  const finalize = async (matchdayId: string) => {
    if (!leagueId || isDemo) {
      return { error: 'La demo non modifica i risultati.' };
    }

    setActionLoading(true);
    setActionError('');
    try {
      const outcome = await finalizeLeagueMatchday(leagueId, matchdayId);
      if (outcome.error) {
        setActionError(outcome.error);
      } else {
        await refresh(true);
      }
      return outcome;
    } finally {
      setActionLoading(false);
    }
  };

  const reopen = async (matchdayId: string) => {
    if (!leagueId || isDemo) {
      return { error: 'La demo non modifica i risultati.' };
    }

    setActionLoading(true);
    setActionError('');
    try {
      const outcome = await reopenLeagueMatchday(leagueId, matchdayId);
      if (outcome.error) {
        setActionError(outcome.error);
      } else {
        await refresh(true);
      }
      return outcome;
    } finally {
      setActionLoading(false);
    }
  };

  const reopenFixture = async (
    fixtureId: string,
    reason: string,
    expectedProviderImpactGeneration?: number | null,
  ) => {
    if (!leagueId || isDemo) {
      return { error: 'La demo non modifica i risultati.' };
    }

    setActionLoading(true);
    setActionError('');
    try {
      const outcome = await reopenLeagueFixture(
        leagueId,
        fixtureId,
        reason,
        expectedProviderImpactGeneration,
      );
      if (outcome.error) {
        setActionError(outcome.error);
      } else {
        await refresh(true);
      }
      return outcome;
    } finally {
      setActionLoading(false);
    }
  };

  return {
    center,
    loading,
    actionLoading,
    error,
    actionError,
    finalize,
    reopen,
    reopenFixture,
    refresh,
  };
}
