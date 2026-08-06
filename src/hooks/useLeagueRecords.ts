import { useCallback, useEffect, useState } from 'react';
import {
  fetchLeagueRecords,
  subscribeToLeagueRecords,
} from '../services/leagueRecordsService';
import type { LeagueRecords } from '../types';

const demoRecords: LeagueRecords = {
  completedSeasons: 2,
  seasonRecords: [
    {
      key: 'league_points',
      value: 73,
      season: '2025',
      teamId: 'demo-team-2',
      teamName: 'Tiki Taka Boom',
      managerId: 'demo-manager-2',
      managerName: 'Luca Ferri',
    },
    {
      key: 'fantasy_points',
      value: 2248.5,
      season: '2025',
      teamId: 'demo-team-2',
      teamName: 'Tiki Taka Boom',
      managerId: 'demo-manager-2',
      managerName: 'Luca Ferri',
    },
    {
      key: 'wins',
      value: 23,
      season: '2025',
      teamId: 'demo-team-2',
      teamName: 'Tiki Taka Boom',
      managerId: 'demo-manager-2',
      managerName: 'Luca Ferri',
    },
    {
      key: 'goals_for',
      value: 66,
      season: '2024',
      teamId: 'demo-team',
      teamName: 'Diavoli del Sud',
      managerId: 'demo-user',
      managerName: 'Marco Schito',
    },
    {
      key: 'goal_difference',
      value: 24,
      season: '2024',
      teamId: 'demo-team',
      teamName: 'Diavoli del Sud',
      managerId: 'demo-user',
      managerName: 'Marco Schito',
    },
  ],
  matchRecords: [
    {
      key: 'highest_score',
      value: 91.5,
      fixtureId: 'demo-record-match-1',
      season: '2025',
      matchdayNumber: 9,
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
    },
    {
      key: 'biggest_win',
      value: 5,
      fixtureId: 'demo-record-match-2',
      season: '2024',
      matchdayNumber: 12,
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
    },
    {
      key: 'highest_total_goals',
      value: 8,
      fixtureId: 'demo-record-match-3',
      season: '2025',
      matchdayNumber: 18,
      teamId: 'demo-team-3',
      teamName: 'Atletico Ma Non Troppo',
      managerId: 'demo-manager-3',
      managerName: 'Davide Russo',
      opponentName: 'Real Colizzati',
      homeTeamName: 'Atletico Ma Non Troppo',
      awayTeamName: 'Real Colizzati',
      homePoints: 86,
      awayPoints: 84.5,
      homeGoals: 4,
      awayGoals: 4,
    },
  ],
  careerLeaders: [
    {
      rank: 1,
      managerId: 'demo-manager-2',
      managerName: 'Luca Ferri',
      seasons: 2,
      titles: 1,
      podiums: 2,
      bestFinish: 1,
      played: 56,
      won: 43,
      drawn: 7,
      lost: 6,
      goalsFor: 126,
      goalsAgainst: 78,
      fantasyPoints: 4411.5,
      leaguePoints: 138,
      winRate: 76.8,
      teamNames: ['Tiki Taka Boom'],
    },
    {
      rank: 2,
      managerId: 'demo-user',
      managerName: 'Marco Schito',
      seasons: 2,
      titles: 1,
      podiums: 2,
      bestFinish: 1,
      played: 56,
      won: 42,
      drawn: 5,
      lost: 9,
      goalsFor: 124,
      goalsAgainst: 82,
      fantasyPoints: 4414,
      leaguePoints: 140,
      winRate: 75,
      teamNames: ['Diavoli del Sud'],
    },
    {
      rank: 3,
      managerId: 'demo-manager-4',
      managerName: 'Paolo Greco',
      seasons: 2,
      titles: 0,
      podiums: 1,
      bestFinish: 3,
      played: 56,
      won: 34,
      drawn: 8,
      lost: 14,
      goalsFor: 107,
      goalsAgainst: 91,
      fantasyPoints: 4288,
      leaguePoints: 110,
      winRate: 60.7,
      teamNames: ['Real Colizzati'],
    },
  ],
};

export function useLeagueRecords(
  leagueId: string | null,
  isDemo: boolean,
) {
  const [records, setRecords] = useState<LeagueRecords | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');

  const refresh = useCallback(async (silent = false) => {
    if (!leagueId) {
      setRecords(null);
      setError('');
      setLoading(false);
      return;
    }

    if (isDemo) {
      setRecords(demoRecords);
      setError('');
      setLoading(false);
      return;
    }

    if (!silent) {
      setLoading(true);
    }
    try {
      setRecords(await fetchLeagueRecords(leagueId));
      setError('');
    } catch (cause) {
      setError(
        cause instanceof Error
          ? cause.message
          : 'I record della lega non rispondono.',
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

    return subscribeToLeagueRecords(leagueId, () => void refresh(true));
  }, [isDemo, leagueId, refresh]);

  return { records, loading, error, refresh };
}
