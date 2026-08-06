import { useCallback, useEffect, useState } from 'react';
import {
  fetchLeagueCupHistory,
  subscribeToLeagueCupHistory,
} from '../services/leagueCupHistoryService';
import type { LeagueCupHistory } from '../types';

const demoCupHistory: LeagueCupHistory = {
  leagueName: 'Serie A da divano',
  selectedLeagueId: 'demo-league',
  latestLeagueId: 'demo-league',
  completedCups: 2,
  activeCups: 1,
  titleLeaders: [
    {
      managerId: 'demo-user',
      managerName: 'Marco Schito',
      titles: 1,
      finals: 2,
      teamNames: ['Diavoli del Sud'],
      seasons: ['2024', '2025'],
    },
    {
      managerId: 'demo-manager-2',
      managerName: 'Luca Ferri',
      titles: 1,
      finals: 1,
      teamNames: ['Tiki Taka Boom'],
      seasons: ['2025'],
    },
  ],
  careerLeaders: [
    {
      rank: 1,
      managerId: 'demo-user',
      managerName: 'Marco Schito',
      participations: 2,
      titles: 1,
      finals: 2,
      tiesPlayed: 6,
      tiesWon: 5,
      winRate: 83.3,
      teamNames: ['Diavoli del Sud'],
    },
    {
      rank: 2,
      managerId: 'demo-manager-2',
      managerName: 'Luca Ferri',
      participations: 2,
      titles: 1,
      finals: 1,
      tiesPlayed: 5,
      tiesWon: 4,
      winRate: 80,
      teamNames: ['Tiki Taka Boom'],
    },
    {
      rank: 3,
      managerId: 'demo-manager-4',
      managerName: 'Paolo Greco',
      participations: 2,
      titles: 0,
      finals: 1,
      tiesPlayed: 5,
      tiesWon: 3,
      winRate: 60,
      teamNames: ['Real Colizzati'],
    },
  ],
  matchRecords: [
    {
      key: 'highest_score',
      value: 91.5,
      tieId: 'demo-cup-record-1',
      season: '2025',
      matchdayNumber: 31,
      roundName: 'Semifinali',
      teamId: 'demo-team-2',
      teamName: 'Tiki Taka Boom',
      managerId: 'demo-manager-2',
      managerName: 'Luca Ferri',
      opponentName: 'Scarsenal',
      homeTeamName: 'Tiki Taka Boom',
      awayTeamName: 'Scarsenal',
      homePoints: 91.5,
      awayPoints: 66,
      homeGoals: 5,
      awayGoals: 1,
      decidedBy: 'goals',
    },
    {
      key: 'biggest_win',
      value: 5,
      tieId: 'demo-cup-record-2',
      season: '2024',
      matchdayNumber: 34,
      roundName: 'Finale',
      teamId: 'demo-team',
      teamName: 'Diavoli del Sud',
      managerId: 'demo-user',
      managerName: 'Marco Schito',
      opponentName: 'Mai Una Gioia',
      homeTeamName: 'Diavoli del Sud',
      awayTeamName: 'Mai Una Gioia',
      homePoints: 89,
      awayPoints: 61.5,
      homeGoals: 5,
      awayGoals: 0,
      decidedBy: 'goals',
    },
    {
      key: 'highest_total_goals',
      value: 8,
      tieId: 'demo-cup-record-3',
      season: '2025',
      matchdayNumber: 32,
      roundName: 'Finale',
      teamId: 'demo-team-2',
      teamName: 'Tiki Taka Boom',
      managerId: 'demo-manager-2',
      managerName: 'Luca Ferri',
      opponentName: 'Diavoli del Sud',
      homeTeamName: 'Tiki Taka Boom',
      awayTeamName: 'Diavoli del Sud',
      homePoints: 86,
      awayPoints: 84.5,
      homeGoals: 4,
      awayGoals: 4,
      decidedBy: 'fantasy_points',
    },
  ],
  seasons: [
    {
      leagueId: 'demo-league',
      season: '2026',
      leagueStatus: 'active',
      cupExists: true,
      cupId: 'demo-cup',
      cupName: 'Coppa di Lega',
      cupStatus: 'active',
      startedAt: '2026-09-01T18:00:00Z',
      completedAt: null,
      teamCount: 8,
      roundCount: 3,
      currentRound: 2,
      totalTieCount: 7,
      officialTieCount: 4,
      champion: null,
      runnerUp: null,
      isSelected: true,
      isLatest: true,
    },
    {
      leagueId: 'demo-league-2025',
      season: '2025',
      leagueStatus: 'archived',
      cupExists: true,
      cupId: 'demo-cup-2025',
      cupName: 'Coppa di Lega',
      cupStatus: 'completed',
      startedAt: '2026-02-01T18:00:00Z',
      completedAt: '2026-05-10T21:00:00Z',
      teamCount: 8,
      roundCount: 3,
      currentRound: 3,
      totalTieCount: 7,
      officialTieCount: 7,
      champion: {
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
      isSelected: false,
      isLatest: false,
    },
    {
      leagueId: 'demo-league-2024',
      season: '2024',
      leagueStatus: 'archived',
      cupExists: true,
      cupId: 'demo-cup-2024',
      cupName: 'Coppa di Lega',
      cupStatus: 'completed',
      startedAt: '2025-02-02T18:00:00Z',
      completedAt: '2025-05-11T21:00:00Z',
      teamCount: 8,
      roundCount: 3,
      currentRound: 3,
      totalTieCount: 7,
      officialTieCount: 7,
      champion: {
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

export function useLeagueCupHistory(
  leagueId: string | null,
  isDemo: boolean,
) {
  const [history, setHistory] = useState<LeagueCupHistory | null>(null);
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
      setHistory(demoCupHistory);
      setError('');
      setLoading(false);
      return;
    }

    if (!silent) {
      setLoading(true);
    }
    try {
      setHistory(await fetchLeagueCupHistory(leagueId));
      setError('');
    } catch (cause) {
      setError(
        cause instanceof Error
          ? cause.message
          : 'La storia della Coppa non risponde.',
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

    return subscribeToLeagueCupHistory(
      leagueId,
      () => void refresh(true),
    );
  }, [isDemo, leagueId, refresh]);

  return { history, loading, error, refresh };
}
