import { useCallback, useEffect, useState } from 'react';
import {
  fetchLeagueSuperCupHistory,
  subscribeToLeagueSuperCupHistory,
} from '../services/leagueSuperCupService';
import type { LeagueSuperCupHistory } from '../types';

const demoHistory: LeagueSuperCupHistory = {
  leagueName: 'Serie A da divano',
  selectedLeagueId: 'demo-league',
  latestLeagueId: 'demo-league',
  completedSuperCups: 2,
  activeSuperCups: 1,
  titleLeaders: [
    {
      rank: 1,
      managerId: 'demo-user',
      managerName: 'Marco Schito',
      titles: 2,
      teamNames: ['Diavoli del Sud'],
      seasons: ['2025', '2026'],
    },
  ],
  seasons: [
    {
      leagueId: 'demo-league',
      season: '2026',
      leagueStatus: 'active',
      superCupExists: true,
      superCupId: 'demo-super-cup',
      superCupStatus: 'active',
      sourceSeason: '2025',
      matchdayNumber: 4,
      challengerQualification: 'cup_champion',
      leagueChampion: {
        teamId: 'demo-team',
        teamName: 'Diavoli del Sud',
        managerId: 'demo-user',
        managerName: 'Marco Schito',
      },
      challenger: {
        teamId: 'demo-team-2',
        teamName: 'Tiki Taka Boom',
        managerId: 'demo-manager-2',
        managerName: 'Luca Ferri',
      },
      homePoints: null,
      awayPoints: null,
      homeGoals: null,
      awayGoals: null,
      decidedBy: null,
      createdAt: '2026-08-30T18:00:00Z',
      completedAt: null,
      winner: null,
      runnerUp: null,
      isSelected: true,
      isLatest: true,
    },
    {
      leagueId: 'demo-league-2025',
      season: '2025',
      leagueStatus: 'archived',
      superCupExists: true,
      superCupId: 'demo-super-cup-2025',
      superCupStatus: 'completed',
      sourceSeason: '2024',
      matchdayNumber: 3,
      challengerQualification: 'cup_runner_up',
      leagueChampion: {
        teamId: 'demo-team',
        teamName: 'Diavoli del Sud',
        managerId: 'demo-user',
        managerName: 'Marco Schito',
      },
      challenger: {
        teamId: 'demo-team-4',
        teamName: 'Real Colizzati',
        managerId: 'demo-manager-4',
        managerName: 'Paolo Greco',
      },
      homePoints: 76.5,
      awayPoints: 70,
      homeGoals: 2,
      awayGoals: 1,
      decidedBy: 'goals',
      createdAt: '2025-08-28T18:00:00Z',
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
      isSelected: false,
      isLatest: false,
    },
  ],
};

export function useLeagueSuperCupHistory(
  leagueId: string | null,
  isDemo: boolean,
) {
  const [history, setHistory] =
    useState<LeagueSuperCupHistory | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');

  const refresh = useCallback(async () => {
    if (isDemo) {
      setHistory(demoHistory);
      setError('');
      setLoading(false);
      return;
    }
    if (!leagueId) {
      setHistory(null);
      setError('');
      setLoading(false);
      return;
    }

    setLoading(true);
    try {
      setHistory(await fetchLeagueSuperCupHistory(leagueId));
      setError('');
    } catch (cause) {
      setError(
        cause instanceof Error
          ? cause.message
          : 'Lo storico della Supercoppa non risponde.',
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
    return subscribeToLeagueSuperCupHistory(
      leagueId,
      () => void refresh(),
    );
  }, [isDemo, leagueId, refresh]);

  return { history, loading, error, refresh };
}
