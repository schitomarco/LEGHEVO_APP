import { useCallback, useEffect, useState } from 'react';
import {
  fetchLeagueHistory,
  subscribeToLeagueHistory,
} from '../services/leagueHistoryService';
import type { LeagueHistory } from '../types';

const demoHistory: LeagueHistory = {
  leagueName: 'Serie A da divano',
  selectedLeagueId: 'demo-league',
  latestLeagueId: 'demo-league',
  totalSeasons: 3,
  completedSeasons: 2,
  titleLeaders: [
    {
      managerId: 'demo-manager-2',
      managerName: 'Luca Ferri',
      titles: 1,
      teamNames: ['Tiki Taka Boom'],
    },
    {
      managerId: 'demo-user',
      managerName: 'Marco Schito',
      titles: 1,
      teamNames: ['Diavoli del Sud'],
    },
  ],
  seasons: [
    {
      leagueId: 'demo-league',
      season: '2026',
      status: 'active',
      startedAt: '2026-09-01T18:00:00Z',
      completedAt: null,
      memberCount: 8,
      fixtureCount: 56,
      officialFixtureCount: 4,
      champion: null,
      podium: [],
      isSelected: true,
      isLatest: true,
    },
    {
      leagueId: 'demo-league-2025',
      season: '2025',
      status: 'archived',
      startedAt: '2025-08-24T18:00:00Z',
      completedAt: '2026-05-24T21:00:00Z',
      memberCount: 8,
      fixtureCount: 56,
      officialFixtureCount: 56,
      champion: {
        teamId: 'demo-team-2',
        teamName: 'Tiki Taka Boom',
        managerName: 'Luca Ferri',
        leaguePoints: 73,
        pointsFor: 2248.5,
      },
      podium: [
        {
          position: 1,
          teamId: 'demo-team-2',
          teamName: 'Tiki Taka Boom',
          managerName: 'Luca Ferri',
          leaguePoints: 73,
          pointsFor: 2248.5,
        },
        {
          position: 2,
          teamId: 'demo-team',
          teamName: 'Diavoli del Sud',
          managerName: 'Marco Schito',
          leaguePoints: 69,
          pointsFor: 2204,
        },
        {
          position: 3,
          teamId: 'demo-team-4',
          teamName: 'Real Colizzati',
          managerName: 'Paolo Greco',
          leaguePoints: 64,
          pointsFor: 2171.5,
        },
      ],
      isSelected: false,
      isLatest: false,
    },
    {
      leagueId: 'demo-league-2024',
      season: '2024',
      status: 'archived',
      startedAt: '2024-08-25T18:00:00Z',
      completedAt: '2025-05-25T21:00:00Z',
      memberCount: 8,
      fixtureCount: 56,
      officialFixtureCount: 56,
      champion: {
        teamId: 'demo-team',
        teamName: 'Diavoli del Sud',
        managerName: 'Marco Schito',
        leaguePoints: 71,
        pointsFor: 2210,
      },
      podium: [
        {
          position: 1,
          teamId: 'demo-team',
          teamName: 'Diavoli del Sud',
          managerName: 'Marco Schito',
          leaguePoints: 71,
          pointsFor: 2210,
        },
        {
          position: 2,
          teamId: 'demo-team-3',
          teamName: 'Atletico Ma Non Troppo',
          managerName: 'Davide Russo',
          leaguePoints: 68,
          pointsFor: 2186.5,
        },
        {
          position: 3,
          teamId: 'demo-team-2',
          teamName: 'Tiki Taka Boom',
          managerName: 'Luca Ferri',
          leaguePoints: 65,
          pointsFor: 2163,
        },
      ],
      isSelected: false,
      isLatest: false,
    },
  ],
};

export function useLeagueHistory(
  leagueId: string | null,
  isDemo: boolean,
) {
  const [history, setHistory] = useState<LeagueHistory | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');

  const refresh = useCallback(async (silent = false) => {
    if (!leagueId) {
      setHistory(null);
      setError('');
      setLoading(false);
      return;
    }

    if (isDemo) {
      setHistory(demoHistory);
      setError('');
      setLoading(false);
      return;
    }

    if (!silent) {
      setLoading(true);
    }
    try {
      setHistory(await fetchLeagueHistory(leagueId));
      setError('');
    } catch (cause) {
      setError(
        cause instanceof Error
          ? cause.message
          : 'La storia della lega non risponde.',
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

    return subscribeToLeagueHistory(leagueId, () => void refresh(true));
  }, [isDemo, leagueId, refresh]);

  return { history, loading, error, refresh };
}
