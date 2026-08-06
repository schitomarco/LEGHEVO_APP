import { useCallback, useEffect, useMemo, useState } from 'react';
import {
  fetchLeagueMatchupCenter,
  subscribeToLeagueMatchup,
} from '../services/matchupService';
import type { LeagueMatchupCenter, LeagueSummary } from '../types';

const demoMatchup: LeagueMatchupCenter = {
  leagueId: 'demo-league',
  leagueName: 'Gli Irriducibili',
  season: '2026',
  generatedAt: '2026-09-18T18:00:00Z',
  myTeam: {
    id: 'demo-team',
    name: 'Diavoli del Sud',
    managerName: 'Marco Schito',
    position: 2,
    played: 6,
    won: 4,
    drawn: 1,
    lost: 1,
    goalsFor: 12,
    goalsAgainst: 7,
    pointsFor: 438,
    leaguePoints: 13,
    recentForm: ['W', 'W', 'D', 'W', 'L'],
    unbeatenStreak: 4,
  },
  opponent: {
    id: 'demo-team-2',
    name: 'Tiki Taka Boom',
    managerName: 'Luca Ferri',
    position: 1,
    played: 6,
    won: 5,
    drawn: 0,
    lost: 1,
    goalsFor: 15,
    goalsAgainst: 6,
    pointsFor: 446.5,
    leaguePoints: 15,
    recentForm: ['W', 'L', 'W', 'W', 'W'],
    unbeatenStreak: 1,
  },
  fixture: {
    id: 'demo-fixture-next',
    matchdayId: 'demo-matchday-7',
    matchdayNumber: 7,
    startsAt: '2026-09-19T18:00:00Z',
    locksAt: '2026-09-19T18:00:00Z',
    endsAt: '2026-09-21T21:00:00Z',
    status: 'upcoming',
    homeTeamId: 'demo-team',
    awayTeamId: 'demo-team-2',
    myHome: true,
    myPoints: null,
    opponentPoints: null,
    myGoals: null,
    opponentGoals: null,
    myLineupStatus: 'submitted',
    opponentLineupStatus: 'submitted',
    lineupsLocked: false,
  },
  currentSeason: {
    played: 1,
    myWins: 0,
    draws: 1,
    opponentWins: 0,
    myGoals: 2,
    opponentGoals: 2,
    myPoints: 72.5,
    opponentPoints: 72,
  },
  allTime: {
    played: 5,
    seasons: 3,
    myWins: 2,
    draws: 1,
    opponentWins: 2,
    myGoals: 9,
    opponentGoals: 9,
    myPoints: 361,
    opponentPoints: 359.5,
    leader: 'level',
  },
  lastMeetings: [
    {
      fixtureId: 'demo-rivalry-1',
      leagueId: 'demo-league',
      season: '2026',
      matchdayNumber: 2,
      startsAt: '2026-08-30T18:00:00Z',
      homeTeamName: 'Tiki Taka Boom',
      awayTeamName: 'Diavoli del Sud',
      myHome: false,
      myPoints: 72.5,
      opponentPoints: 72,
      myGoals: 2,
      opponentGoals: 2,
      outcome: 'D',
    },
    {
      fixtureId: 'demo-rivalry-2',
      leagueId: 'demo-league-2025',
      season: '2025',
      matchdayNumber: 22,
      startsAt: '2025-03-02T18:00:00Z',
      homeTeamName: 'Diavoli del Sud',
      awayTeamName: 'Tiki Taka Boom',
      myHome: true,
      myPoints: 78,
      opponentPoints: 69.5,
      myGoals: 3,
      opponentGoals: 1,
      outcome: 'W',
    },
    {
      fixtureId: 'demo-rivalry-3',
      leagueId: 'demo-league-2025',
      season: '2025',
      matchdayNumber: 8,
      startsAt: '2024-11-03T18:00:00Z',
      homeTeamName: 'Tiki Taka Boom',
      awayTeamName: 'Diavoli del Sud',
      myHome: false,
      myPoints: 65,
      opponentPoints: 73.5,
      myGoals: 1,
      opponentGoals: 2,
      outcome: 'L',
    },
  ],
};

export function useLeagueMatchup(league: LeagueSummary | null) {
  const [center, setCenter] = useState<LeagueMatchupCenter | null>(
    league?.isDemo ? demoMatchup : null,
  );
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');

  const refresh = useCallback(
    async (silent = false) => {
      if (!league) {
        setCenter(null);
        setError('');
        setLoading(false);
        return;
      }

      if (league.isDemo) {
        setCenter(demoMatchup);
        setError('');
        setLoading(false);
        return;
      }

      if (!silent) {
        setLoading(true);
      }
      try {
        setCenter(await fetchLeagueMatchupCenter(league.id));
        setError('');
      } catch (cause) {
        setError(
          cause instanceof Error
            ? cause.message
            : 'Il Centro Sfida non è disponibile.',
        );
      } finally {
        setLoading(false);
      }
    },
    [league],
  );

  const teamIds = useMemo(
    () =>
      [center?.myTeam.id, center?.opponent?.id].filter(
        (teamId): teamId is string => Boolean(teamId),
      ),
    [center?.myTeam.id, center?.opponent?.id],
  );

  useEffect(() => {
    void refresh();
  }, [refresh]);

  useEffect(() => {
    if (!league || league.isDemo || teamIds.length === 0) {
      return;
    }

    return subscribeToLeagueMatchup(
      league.id,
      teamIds,
      () => void refresh(true),
    );
  }, [league, refresh, teamIds]);

  return { center, loading, error, refresh };
}
