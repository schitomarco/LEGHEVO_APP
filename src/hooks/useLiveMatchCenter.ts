import { useCallback, useEffect, useState } from 'react';
import { livePlayers } from '../data/demo';
import {
  fetchLiveMatchCenter,
  subscribeToLiveMatch,
} from '../services/liveScoreService';
import type { LeagueSummary, LiveMatchCenter } from '../types';

function createDemoLiveMatch(): LiveMatchCenter {
  const startsAt = new Date();
  startsAt.setHours(startsAt.getHours() - 2);
  const endsAt = new Date(startsAt);
  endsAt.setDate(endsAt.getDate() + 3);

  return {
    leagueId: 'demo-league',
    leagueName: 'Serie A da divano',
    mode: 'classic',
    status: 'live',
    fixtureId: 'demo-fantasy-fixture-7',
    myTeamId: 'demo-team',
    lineupOrigin: 'manager',
    lineupSourceMatchdayNumber: null,
    substitutions: {
      used: 1,
      limit: 5,
      unavailableStarters: 0,
      applied: true,
    },
    goalMargin: {
      enabled: true,
      minimum: 4,
      applied: false,
      homeBonus: 0,
      awayBonus: 0,
    },
    goalBands: {
      enabled: true,
      thresholds: [65, 71, 77, 83, 90, 96],
    },
    matchday: {
      id: 'demo-matchday-7',
      number: 7,
      startsAt: startsAt.toISOString(),
      locksAt: startsAt.toISOString(),
      endsAt: endsAt.toISOString(),
    },
    home: {
      teamId: 'demo-team',
      name: 'Diavoli del Sud',
      points: 72.5,
      basePoints: 68.5,
      defenseModifier: {
        enabled: true,
        eligible: true,
        minimumDefenders: 4,
        defenderCount: 4,
        averageRating: 6.76,
        bonus: 4,
      },
      homeBonus: 0,
      goals: 2,
      countedPlayers: 6,
      ready: false,
    },
    away: {
      teamId: 'demo-opponent',
      name: 'Tiki Taka Boom',
      points: 68,
      basePoints: 67,
      defenseModifier: {
        enabled: true,
        eligible: true,
        minimumDefenders: 4,
        defenderCount: 4,
        averageRating: 6.1,
        bonus: 1,
      },
      homeBonus: 0,
      goals: 1,
      countedPlayers: 7,
      ready: false,
    },
    players: livePlayers,
  };
}

export function useLiveMatchCenter(league: LeagueSummary | null) {
  const isDemo = Boolean(league?.isDemo);
  const [match, setMatch] = useState<LiveMatchCenter | null>(() =>
    isDemo ? createDemoLiveMatch() : null,
  );
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');

  const refresh = useCallback(async () => {
    if (!league) {
      setMatch(null);
      setError('');
      setLoading(false);
      return;
    }
    if (isDemo) {
      setMatch(createDemoLiveMatch());
      setError('');
      setLoading(false);
      return;
    }

    setLoading(true);
    try {
      setMatch(await fetchLiveMatchCenter(league.id));
      setError('');
    } catch (cause) {
      setError(
        cause instanceof Error
          ? cause.message
          : 'Il Live non risponde. Il VAR sta controllando.',
      );
    } finally {
      setLoading(false);
    }
  }, [isDemo, league]);

  useEffect(() => {
    void refresh();
  }, [refresh]);

  useEffect(() => {
    if (!league || isDemo) {
      return;
    }
    return subscribeToLiveMatch(league.id, () => {
      void refresh();
    });
  }, [isDemo, league, refresh]);

  return { match, loading, error, refresh };
}
