import { useCallback, useEffect, useState } from 'react';
import {
  fetchMyTeamDashboard,
  subscribeToMyTeamDashboard,
} from '../services/teamDashboardService';
import type { LeagueSummary, TeamDashboard } from '../types';

const demoDashboard: TeamDashboard = {
  teamId: 'demo-team',
  teamName: 'Diavoli del Sud',
  creditsRemaining: 188,
  startingCredits: 500,
  creditsSpent: 312,
  rosterCount: 25,
  rosterSize: 25,
  memberCount: 8,
  teamLimit: 8,
  fixtureCount: 56,
  competitionStartedAt: '2026-09-01T18:00:00Z',
  position: 2,
  played: 6,
  won: 4,
  drawn: 1,
  lost: 1,
  goalsFor: 12,
  goalsAgainst: 7,
  pointsFor: 438,
  leaguePoints: 13,
  nextMatch: {
    fixtureId: 'demo-fixture-next',
    matchdayId: 'demo-matchday-7',
    matchdayNumber: 7,
    startsAt: '2026-09-19T18:00:00Z',
    home: true,
    opponentId: 'demo-team-2',
    opponentName: 'Tiki Taka Boom',
  },
  lastMatch: {
    fixtureId: 'demo-fixture-last',
    matchdayId: 'demo-matchday-6',
    matchdayNumber: 6,
    startsAt: '2026-09-12T18:00:00Z',
    home: false,
    opponentId: 'demo-team-4',
    opponentName: 'Real Colizzati',
    myPoints: 72.5,
    opponentPoints: 68,
    myGoals: 2,
    opponentGoals: 1,
  },
  recentTransactions: [],
};

export function useTeamDashboard(league: LeagueSummary | null) {
  const [dashboard, setDashboard] = useState<TeamDashboard | null>(
    league?.isDemo ? demoDashboard : null,
  );
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');

  const refresh = useCallback(async () => {
    if (!league) {
      setDashboard(null);
      setError('');
      setLoading(false);
      return;
    }

    if (league.isDemo) {
      setDashboard(demoDashboard);
      setError('');
      setLoading(false);
      return;
    }

    setLoading(true);
    try {
      setDashboard(await fetchMyTeamDashboard(league.id));
      setError('');
    } catch (reason) {
      setError(
        reason instanceof Error
          ? reason.message
          : 'Il cruscotto della squadra non è disponibile.',
      );
    } finally {
      setLoading(false);
    }
  }, [league]);

  useEffect(() => {
    void refresh();
  }, [refresh]);

  useEffect(() => {
    if (!league || league.isDemo || !league.team?.id) {
      return;
    }

    return subscribeToMyTeamDashboard(
      league.id,
      league.team.id,
      () => void refresh(),
    );
  }, [league, refresh]);

  return { dashboard, loading, error, refresh };
}
