import { useCallback, useEffect, useState } from 'react';
import {
  fetchLeaguePlayoffHistory,
  subscribeToLeaguePlayoffHistory,
} from '../services/leaguePlayoffHistoryService';
import type { LeaguePlayoffHistory } from '../types';

const demoPlayoffHistory: LeaguePlayoffHistory = {
  leagueName: 'Serie A da divano',
  selectedLeagueId: 'demo-league',
  latestLeagueId: 'demo-league',
  completedPlayoffs: 2,
  activePlayoffs: 1,
  configuredPlayoffs: 0,
  titleLeaders: [
    {
      managerId: 'demo-user',
      managerName: 'Marco Schito',
      titles: 1,
      finals: 2,
      lowerSeedTitles: 1,
      teamNames: ['Diavoli del Sud'],
      seasons: ['2024', '2025'],
    },
    {
      managerId: 'demo-manager-2',
      managerName: 'Luca Ferri',
      titles: 1,
      finals: 1,
      lowerSeedTitles: 0,
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
      lowerSeedTitles: 1,
      tiesPlayed: 5,
      tiesWon: 4,
      winRate: 80,
      teamNames: ['Diavoli del Sud'],
    },
    {
      rank: 2,
      managerId: 'demo-manager-2',
      managerName: 'Luca Ferri',
      participations: 2,
      titles: 1,
      finals: 1,
      lowerSeedTitles: 0,
      tiesPlayed: 4,
      tiesWon: 3,
      winRate: 75,
      teamNames: ['Tiki Taka Boom'],
    },
  ],
  matchRecords: [
    {
      key: 'highest_score',
      value: 94.5,
      tieId: 'demo-playoff-record-1',
      season: '2025',
      matchdayNumber: 37,
      roundName: 'Semifinali',
      teamId: 'demo-team',
      teamName: 'Diavoli del Sud',
      managerId: 'demo-user',
      managerName: 'Marco Schito',
      opponentName: 'Mai Una Gioia',
      homeTeamName: 'Diavoli del Sud',
      awayTeamName: 'Mai Una Gioia',
      homePoints: 94.5,
      awayPoints: 68,
      homeGoals: 5,
      awayGoals: 1,
      decidedBy: 'goals',
    },
    {
      key: 'biggest_win',
      value: 4,
      tieId: 'demo-playoff-record-2',
      season: '2025',
      matchdayNumber: 37,
      roundName: 'Semifinali',
      teamId: 'demo-team',
      teamName: 'Diavoli del Sud',
      managerId: 'demo-user',
      managerName: 'Marco Schito',
      opponentName: 'Mai Una Gioia',
      homeTeamName: 'Diavoli del Sud',
      awayTeamName: 'Mai Una Gioia',
      homePoints: 94.5,
      awayPoints: 68,
      homeGoals: 5,
      awayGoals: 1,
      decidedBy: 'goals',
    },
    {
      key: 'highest_total_goals',
      value: 8,
      tieId: 'demo-playoff-record-3',
      season: '2024',
      matchdayNumber: 38,
      roundName: 'Finale Scudetto',
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
      playoffExists: true,
      playoffId: 'demo-playoff',
      playoffStatus: 'active',
      configuredAt: '2026-08-01T18:00:00Z',
      startedAt: '2027-05-15T18:00:00Z',
      completedAt: null,
      participantCount: 4,
      roundCount: 2,
      currentRound: 1,
      totalTieCount: 3,
      officialTieCount: 0,
      champion: null,
      runnerUp: null,
      regularSeasonLeader: {
        teamId: 'demo-team-2',
        teamName: 'Tiki Taka Boom',
        managerId: 'demo-manager-2',
        managerName: 'Luca Ferri',
        seed: 1,
        regularSeasonPosition: 1,
      },
      isSelected: true,
      isLatest: true,
    },
    {
      leagueId: 'demo-league-2025',
      season: '2025',
      leagueStatus: 'archived',
      playoffExists: true,
      playoffId: 'demo-playoff-2025',
      playoffStatus: 'completed',
      configuredAt: '2025-08-01T18:00:00Z',
      startedAt: '2026-05-16T18:00:00Z',
      completedAt: '2026-05-25T21:00:00Z',
      participantCount: 4,
      roundCount: 2,
      currentRound: 2,
      totalTieCount: 3,
      officialTieCount: 3,
      champion: {
        teamId: 'demo-team',
        teamName: 'Diavoli del Sud',
        managerId: 'demo-user',
        managerName: 'Marco Schito',
        seed: 3,
        regularSeasonPosition: 3,
      },
      runnerUp: {
        teamId: 'demo-team-2',
        teamName: 'Tiki Taka Boom',
        managerId: 'demo-manager-2',
        managerName: 'Luca Ferri',
        seed: 1,
        regularSeasonPosition: 1,
      },
      regularSeasonLeader: {
        teamId: 'demo-team-2',
        teamName: 'Tiki Taka Boom',
        managerId: 'demo-manager-2',
        managerName: 'Luca Ferri',
        seed: 1,
        regularSeasonPosition: 1,
      },
      isSelected: false,
      isLatest: false,
    },
    {
      leagueId: 'demo-league-2024',
      season: '2024',
      leagueStatus: 'archived',
      playoffExists: true,
      playoffId: 'demo-playoff-2024',
      playoffStatus: 'completed',
      configuredAt: '2024-08-01T18:00:00Z',
      startedAt: '2025-05-17T18:00:00Z',
      completedAt: '2025-05-26T21:00:00Z',
      participantCount: 4,
      roundCount: 2,
      currentRound: 2,
      totalTieCount: 3,
      officialTieCount: 3,
      champion: {
        teamId: 'demo-team-2',
        teamName: 'Tiki Taka Boom',
        managerId: 'demo-manager-2',
        managerName: 'Luca Ferri',
        seed: 1,
        regularSeasonPosition: 1,
      },
      runnerUp: {
        teamId: 'demo-team',
        teamName: 'Diavoli del Sud',
        managerId: 'demo-user',
        managerName: 'Marco Schito',
        seed: 2,
        regularSeasonPosition: 2,
      },
      regularSeasonLeader: {
        teamId: 'demo-team-2',
        teamName: 'Tiki Taka Boom',
        managerId: 'demo-manager-2',
        managerName: 'Luca Ferri',
        seed: 1,
        regularSeasonPosition: 1,
      },
      isSelected: false,
      isLatest: false,
    },
  ],
};

export function useLeaguePlayoffHistory(
  leagueId: string | null,
  isDemo: boolean,
) {
  const [history, setHistory] = useState<LeaguePlayoffHistory | null>(null);
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
      setHistory(demoPlayoffHistory);
      setError('');
      setLoading(false);
      return;
    }

    if (!silent) {
      setLoading(true);
    }
    try {
      setHistory(await fetchLeaguePlayoffHistory(leagueId));
      setError('');
    } catch (cause) {
      setError(
        cause instanceof Error
          ? cause.message
          : 'La storia dei Playoff non risponde.',
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

    return subscribeToLeaguePlayoffHistory(
      leagueId,
      () => void refresh(true),
    );
  }, [isDemo, leagueId, refresh]);

  return { history, loading, error, refresh };
}
