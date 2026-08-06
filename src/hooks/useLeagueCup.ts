import { useCallback, useEffect, useState } from 'react';
import { AppState } from 'react-native';
import {
  createLeagueCup,
  fetchLeagueCup,
  finalizeLeagueCupRound,
  subscribeToLeagueCup,
} from '../services/leagueCupService';
import type { LeagueCupState } from '../types';

const demoCup: LeagueCupState = {
  exists: true,
  leagueId: 'demo-league',
  cupId: 'demo-cup',
  name: 'Coppa di Lega',
  status: 'active',
  isOwner: true,
  canCreate: false,
  creationReason: null,
  teamCount: 8,
  bracketSize: 8,
  roundCount: 3,
  currentRound: 2,
  startedAt: '2026-09-01T18:00:00Z',
  completedAt: null,
  drawSeed: 'demo-draw',
  drawPolicy: 'guarded_v1',
  drawCertified: true,
  drawRunId: 'demo-draw-run',
  drawRevision: 1,
  roundFinalizationPolicy: 'guarded_v1',
  officialRoundCount: 1,
  certifiedRoundCount: 1,
  roundsCertified: true,
  currentRoundOfficializationReady: false,
  lastRoundRunId: 'demo-round-run',
  lastCertifiedRound: 1,
  lastRoundFinalizedAt: '2026-10-06T08:00:00Z',
  completionPolicy: 'certified_v1',
  completionCertified: false,
  completionCertificateId: null,
  completionFingerprint: null,
  completionCertifiedAt: null,
  completionFinalizationRunId: null,
  startMatchdays: [],
  champion: null,
  runnerUp: null,
  canFinalizeCurrent: false,
  rounds: [
    {
      id: 'demo-cup-round-1',
      number: 1,
      name: 'Quarti di finale',
      matchdayId: 'demo-md-1',
      matchdayNumber: 5,
      startsAt: '2026-10-03T13:00:00Z',
      locksAt: '2026-10-03T12:55:00Z',
      endsAt: '2026-10-05T22:45:00Z',
      status: 'official',
      finalizedAt: '2026-10-06T08:00:00Z',
      ties: [
        demoTie(
          'demo-tie-1',
          1,
          ['Diavoli del Sud', 'Marco', 1],
          ['Tiki Taka Boom', 'Andrea', 2],
          2,
          1,
          74.5,
          67,
          'goals',
        ),
        demoTie(
          'demo-tie-2',
          2,
          ['Atletico Pensione', 'Luca', 3],
          ['Real Madrink', 'Gianni', 4],
          1,
          2,
          69,
          72,
          'goals',
        ),
        demoTie(
          'demo-tie-3',
          3,
          ['Gli Svincolati', 'Paolo', 5],
          ['FC Ansia', 'Matteo', 6],
          1,
          1,
          70,
          68.5,
          'fantasy_points',
        ),
        demoTie(
          'demo-tie-4',
          4,
          ['Var United', 'Davide', 7],
          ['Mai Una Gioia', 'Stefano', 8],
          0,
          1,
          63.5,
          66,
          'goals',
        ),
      ],
    },
    {
      id: 'demo-cup-round-2',
      number: 2,
      name: 'Semifinali',
      matchdayId: 'demo-md-2',
      matchdayNumber: 8,
      startsAt: '2026-10-24T13:00:00Z',
      locksAt: '2026-10-24T12:55:00Z',
      endsAt: '2026-10-26T22:45:00Z',
      status: 'scheduled',
      finalizedAt: null,
      ties: [
        demoWaitingTie(
          'demo-tie-5',
          1,
          ['Diavoli del Sud', 'Marco', 1],
          ['Real Madrink', 'Gianni', 4],
        ),
        demoWaitingTie(
          'demo-tie-6',
          2,
          ['Gli Svincolati', 'Paolo', 5],
          ['Mai Una Gioia', 'Stefano', 8],
        ),
      ],
    },
    {
      id: 'demo-cup-round-3',
      number: 3,
      name: 'Finale',
      matchdayId: 'demo-md-3',
      matchdayNumber: 11,
      startsAt: '2026-11-21T13:00:00Z',
      locksAt: '2026-11-21T12:55:00Z',
      endsAt: '2026-11-23T22:45:00Z',
      status: 'scheduled',
      finalizedAt: null,
      ties: [
        {
          id: 'demo-tie-7',
          position: 1,
          homeTeam: null,
          awayTeam: null,
          homePoints: null,
          awayPoints: null,
          homeGoals: null,
          awayGoals: null,
          homeReady: false,
          awayReady: false,
          homeCountedPlayers: 0,
          awayCountedPlayers: 0,
          winnerTeamId: null,
          decidedBy: null,
          finalizedAt: null,
          status: 'waiting',
        },
      ],
    },
  ],
};

export function useLeagueCup(
  leagueId: string | null,
  isDemo: boolean,
) {
  const [cup, setCup] = useState<LeagueCupState | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);

  const refresh = useCallback(async (silent = false) => {
    if (isDemo) {
      setCup(demoCup);
      setError('');
      setLoading(false);
      return;
    }

    if (!leagueId) {
      setCup(null);
      setError('');
      setLoading(false);
      return;
    }

    if (!silent) {
      setLoading(true);
    }
    try {
      setCup(await fetchLeagueCup(leagueId));
      setError('');
    } catch (cause) {
      setError(
        cause instanceof Error
          ? cause.message
          : 'Il tabellone non risponde.',
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
    return subscribeToLeagueCup(leagueId, () => void refresh(true));
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

  const create = async (startMatchdayNumber: number) => {
    if (!leagueId || isDemo) {
      return { error: 'La coppa demo è già pronta.' };
    }
    setBusy(true);
    const outcome = await createLeagueCup(leagueId, startMatchdayNumber);
    if (!outcome.error) {
      await refresh(true);
    }
    setBusy(false);
    return outcome;
  };

  const finalizeCurrentRound = async () => {
    if (!leagueId || isDemo) {
      return { error: 'Il turno demo non è ancora terminato.' };
    }
    setBusy(true);
    const outcome = await finalizeLeagueCupRound(
      leagueId,
      cup?.currentRound ?? 0,
    );
    if (!outcome.error) {
      await refresh(true);
    }
    setBusy(false);
    return outcome;
  };

  return {
    cup,
    loading,
    error,
    busy,
    refresh,
    create,
    finalizeCurrentRound,
  };
}

function demoTie(
  id: string,
  position: number,
  home: [string, string, number],
  away: [string, string, number],
  homeGoals: number,
  awayGoals: number,
  homePoints: number,
  awayPoints: number,
  decidedBy: 'goals' | 'fantasy_points',
) {
  const homeTeam = {
    id: `${id}-home`,
    name: home[0],
    managerName: home[1],
    seed: home[2],
  };
  const awayTeam = {
    id: `${id}-away`,
    name: away[0],
    managerName: away[1],
    seed: away[2],
  };
  const winnerTeamId =
    homeGoals > awayGoals ||
    (homeGoals === awayGoals && homePoints > awayPoints)
      ? homeTeam.id
      : awayTeam.id;
  return {
    id,
    position,
    homeTeam,
    awayTeam,
    homePoints,
    awayPoints,
    homeGoals,
    awayGoals,
    homeReady: true,
    awayReady: true,
    homeCountedPlayers: 11,
    awayCountedPlayers: 11,
    winnerTeamId,
    decidedBy,
    finalizedAt: '2026-10-06T08:00:00Z',
    status: 'official' as const,
  };
}

function demoWaitingTie(
  id: string,
  position: number,
  home: [string, string, number],
  away: [string, string, number],
) {
  return {
    id,
    position,
    homeTeam: {
      id: `${id}-home`,
      name: home[0],
      managerName: home[1],
      seed: home[2],
    },
    awayTeam: {
      id: `${id}-away`,
      name: away[0],
      managerName: away[1],
      seed: away[2],
    },
    homePoints: null,
    awayPoints: null,
    homeGoals: null,
    awayGoals: null,
    homeReady: false,
    awayReady: false,
    homeCountedPlayers: 0,
    awayCountedPlayers: 0,
    winnerTeamId: null,
    decidedBy: null,
    finalizedAt: null,
    status: 'waiting' as const,
  };
}
