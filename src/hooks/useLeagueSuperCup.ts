import { useCallback, useEffect, useState } from 'react';
import { AppState } from 'react-native';
import {
  createLeagueSuperCup,
  fetchLeagueSuperCup,
  finalizeLeagueSuperCup,
  subscribeToLeagueSuperCup,
} from '../services/leagueSuperCupService';
import type { LeagueSuperCupState } from '../types';

const demoSuperCup: LeagueSuperCupState = {
  exists: true,
  leagueId: 'demo-league',
  superCupId: 'demo-super-cup',
  status: 'active',
  isOwner: true,
  eligible: true,
  canCreate: false,
  creationReason: null,
  sourceLeagueId: 'demo-league-2025',
  sourceSeason: '2025',
  leagueChampion: {
    teamId: 'demo-team',
    teamName: 'Diavoli del Sud',
    managerId: 'demo-user',
    managerName: 'Marco Schito',
    qualification: 'league_champion',
  },
  challenger: {
    teamId: 'demo-team-2',
    teamName: 'Tiki Taka Boom',
    managerId: 'demo-manager-2',
    managerName: 'Luca Ferri',
    qualification: 'cup_champion',
  },
  challengerQualification: 'cup_champion',
  matchday: {
    id: 'demo-super-cup-matchday',
    number: 4,
    startsAt: '2026-09-19T13:00:00Z',
    locksAt: '2026-09-19T12:55:00Z',
    endsAt: '2026-09-21T22:45:00Z',
  },
  startMatchdays: [],
  homePoints: null,
  awayPoints: null,
  homeGoals: null,
  awayGoals: null,
  homeReady: false,
  awayReady: false,
  homeCountedPlayers: 0,
  awayCountedPlayers: 0,
  decidedBy: null,
  createdAt: '2026-08-30T18:00:00Z',
  completedAt: null,
  canFinalize: false,
  winner: null,
  runnerUp: null,
  schedulePolicy: 'guarded_v1',
  scheduleCertified: true,
  scheduleRunId: 1,
  scheduleRequestId: 'demo-super-cup-schedule-request',
  scheduleQualifiersHash: 'demo-qualifiers-hash',
  scheduleHash: 'demo-schedule-hash',
  scheduleResultHash: 'demo-result-hash',
  finalizationPolicy: 'guarded_v1',
  finalizationCertified: false,
  finalizationRunId: null,
  finalizationRequestId: null,
  finalizationSourceMode: null,
  finalizationInputHash: null,
  finalizationResultHash: null,
  finalizationOfficializationRunId: null,
  finalizationHomeResolutionId: null,
  finalizationAwayResolutionId: null,
};

export function useLeagueSuperCup(
  leagueId: string | null,
  isDemo: boolean,
) {
  const [superCup, setSuperCup] = useState<LeagueSuperCupState | null>(
    null,
  );
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);

  const refresh = useCallback(
    async (silent = false) => {
      if (isDemo) {
        setSuperCup(demoSuperCup);
        setError('');
        setLoading(false);
        return;
      }

      if (!leagueId) {
        setSuperCup(null);
        setError('');
        setLoading(false);
        return;
      }

      if (!silent) {
        setLoading(true);
      }
      try {
        setSuperCup(await fetchLeagueSuperCup(leagueId));
        setError('');
      } catch (cause) {
        setError(
          cause instanceof Error
            ? cause.message
            : 'La Supercoppa non risponde.',
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
    return subscribeToLeagueSuperCup(leagueId, () => void refresh(true));
  }, [isDemo, leagueId, refresh]);

  useEffect(() => {
    if (!leagueId || isDemo) {
      return;
    }
    const subscription = AppState.addEventListener('change', (state) => {
      if (state === 'active') {
        void refresh(true);
      }
    });
    return () => subscription.remove();
  }, [isDemo, leagueId, refresh]);

  const create = async (matchdayNumber: number) => {
    if (!leagueId || isDemo) {
      return { error: 'La Supercoppa demo è già programmata.' };
    }
    setBusy(true);
    const outcome = await createLeagueSuperCup(
      leagueId,
      matchdayNumber,
    );
    if (!outcome.error) {
      await refresh(true);
    }
    setBusy(false);
    return outcome;
  };

  const finalize = async () => {
    if (!leagueId || isDemo) {
      return { error: 'La Supercoppa demo non è ancora terminata.' };
    }
    setBusy(true);
    const outcome = await finalizeLeagueSuperCup(leagueId);
    if (!outcome.error) {
      await refresh(true);
    }
    setBusy(false);
    return outcome;
  };

  return {
    superCup,
    loading,
    error,
    busy,
    refresh,
    create,
    finalize,
  };
}
