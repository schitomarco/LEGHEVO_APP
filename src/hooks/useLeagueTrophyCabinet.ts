import { useCallback, useEffect, useState } from 'react';
import {
  fetchLeagueTrophyCabinet,
  subscribeToLeagueTrophyCabinet,
} from '../services/leagueTrophyCabinetService';
import type { LeagueTrophyCabinet } from '../types';

const demoCabinet: LeagueTrophyCabinet = {
  leagueName: 'Serie A da divano',
  selectedLeagueId: 'demo-league',
  latestLeagueId: 'demo-league',
  totalTrophies: 6,
  leagueTitles: 2,
  cupTitles: 2,
  superCupTitles: 2,
  uniqueWinners: 2,
  doubles: 1,
  leaders: [
    {
      rank: 1,
      managerId: 'demo-user',
      managerName: 'Marco Schito',
      totalTrophies: 4,
      leagueTitles: 1,
      cupTitles: 1,
      superCupTitles: 2,
      leaguePodiums: 2,
      cupFinals: 2,
      superCupFinals: 2,
      doubles: 1,
      teamNames: ['Diavoli del Sud'],
      seasons: ['2024', '2025'],
    },
    {
      rank: 2,
      managerId: 'demo-manager-2',
      managerName: 'Luca Ferri',
      totalTrophies: 2,
      leagueTitles: 1,
      cupTitles: 1,
      superCupTitles: 0,
      leaguePodiums: 2,
      cupFinals: 1,
      superCupFinals: 0,
      doubles: 0,
      teamNames: ['Tiki Taka Boom'],
      seasons: ['2025'],
    },
    {
      rank: 3,
      managerId: 'demo-manager-4',
      managerName: 'Paolo Greco',
      totalTrophies: 0,
      leagueTitles: 0,
      cupTitles: 0,
      superCupTitles: 0,
      leaguePodiums: 1,
      cupFinals: 1,
      superCupFinals: 1,
      doubles: 0,
      teamNames: ['Real Colizzati'],
      seasons: [],
    },
  ],
  timeline: [
    {
      id: 'super-cup-demo-2025',
      competition: 'super_cup',
      leagueId: 'demo-league-2025',
      season: '2025',
      sourceSeason: '2024',
      completedAt: '2025-09-16T08:00:00Z',
      winner: {
        teamId: 'demo-team',
        teamName: 'Diavoli del Sud',
        managerId: 'demo-user',
        managerName: 'Marco Schito',
      },
      runnerUp: {
        teamId: 'demo-team-4',
        teamName: 'Real Colizzati',
        managerId: 'demo-manager-4',
        managerName: 'Paolo Greco',
      },
    },
    {
      id: 'league-demo-2025',
      competition: 'league',
      leagueId: 'demo-league-2025',
      season: '2025',
      sourceSeason: null,
      completedAt: '2026-05-24T21:00:00Z',
      winner: {
        teamId: 'demo-team-2',
        teamName: 'Tiki Taka Boom',
        managerId: 'demo-manager-2',
        managerName: 'Luca Ferri',
      },
      runnerUp: {
        teamId: 'demo-team',
        teamName: 'Diavoli del Sud',
        managerId: 'demo-user',
        managerName: 'Marco Schito',
      },
    },
    {
      id: 'cup-demo-2025',
      competition: 'cup',
      leagueId: 'demo-league-2025',
      season: '2025',
      sourceSeason: null,
      completedAt: '2026-05-10T21:00:00Z',
      winner: {
        teamId: 'demo-team-2',
        teamName: 'Tiki Taka Boom',
        managerId: 'demo-manager-2',
        managerName: 'Luca Ferri',
      },
      runnerUp: {
        teamId: 'demo-team',
        teamName: 'Diavoli del Sud',
        managerId: 'demo-user',
        managerName: 'Marco Schito',
      },
    },
  ],
};

export function useLeagueTrophyCabinet(
  leagueId: string | null,
  isDemo: boolean,
) {
  const [cabinet, setCabinet] =
    useState<LeagueTrophyCabinet | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');

  const refresh = useCallback(
    async (silent = false) => {
      if (isDemo) {
        setCabinet(demoCabinet);
        setError('');
        setLoading(false);
        return;
      }
      if (!leagueId) {
        setCabinet(null);
        setError('');
        setLoading(false);
        return;
      }

      if (!silent) {
        setLoading(true);
      }
      try {
        setCabinet(await fetchLeagueTrophyCabinet(leagueId));
        setError('');
      } catch (cause) {
        setError(
          cause instanceof Error
            ? cause.message
            : 'La bacheca dei trofei non risponde.',
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
    return subscribeToLeagueTrophyCabinet(
      leagueId,
      () => void refresh(true),
    );
  }, [isDemo, leagueId, refresh]);

  return { cabinet, loading, error, refresh };
}
