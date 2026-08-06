import { useCallback, useEffect, useState } from 'react';
import { AppState } from 'react-native';
import {
  configureLeaguePlayoffs,
  fetchLeaguePlayoffs,
  finalizeLeaguePlayoffRound,
  startLeaguePlayoffs,
  subscribeToLeaguePlayoffs,
} from '../services/leaguePlayoffService';
import type { LeaguePlayoffState } from '../types';

const demoPlayoffs: LeaguePlayoffState = {
  exists: true,
  leagueId: 'demo-league',
  playoffId: 'demo-playoffs',
  status: 'active',
  isOwner: true,
  canConfigure: false,
  canStart: false,
  actionReason: null,
  participantCount: 4,
  roundCount: 2,
  currentRound: 1,
  regularSeasonReady: true,
  configuredAt: '2026-08-20T10:00:00Z',
  startedAt: '2027-05-20T10:00:00Z',
  completedAt: null,
  configurationPolicy: 'guarded_v1',
  configurationCertified: true,
  configurationRunId: 1,
  configurationRequestId: 'demo-playoff-configuration-request',
  configurationSourceMode: 'guarded_v1',
  configurationHash: 'demo-playoff-configuration-hash',
  configurationResultHash: 'demo-playoff-result-hash',
  configurationCertifiedAt: '2026-08-20T10:00:00Z',
  startPolicy: 'guarded_v1',
  startCertified: true,
  startRunId: 1,
  startRequestId: 'demo-playoff-start-request',
  startSourceMode: 'guarded_v1',
  startMatchdayNumber: 37,
  startQualificationSourceHash: 'demo-playoff-qualification-source-hash',
  startQualificationHash: 'demo-playoff-qualification-hash',
  startScheduleHash: 'demo-playoff-schedule-hash',
  startOpeningBracketHash: 'demo-playoff-opening-bracket-hash',
  startResultHash: 'demo-playoff-start-result-hash',
  startCertifiedAt: '2027-05-20T10:00:00Z',
  roundFinalizationPolicy: 'guarded_v1',
  officialRoundCount: 0,
  certifiedRoundCount: 0,
  roundsCertified: true,
  currentRoundOfficializationReady: false,
  lastRoundRunId: null,
  lastCertifiedRound: 0,
  lastRoundFinalizedAt: null,
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
      id: 'demo-playoff-round-1',
      number: 1,
      name: 'Semifinali',
      matchdayId: 'demo-playoff-md-1',
      matchdayNumber: 37,
      startsAt: '2027-05-23T13:00:00Z',
      locksAt: '2027-05-23T12:55:00Z',
      endsAt: '2027-05-25T22:45:00Z',
      status: 'scheduled',
      finalizedAt: null,
      ties: [
        waitingTie('demo-playoff-tie-1', 1, [
          'Diavoli del Sud',
          'Marco',
          1,
        ], ['Mai Una Gioia', 'Stefano', 4]),
        waitingTie('demo-playoff-tie-2', 2, [
          'Real Madrink',
          'Gianni',
          2,
        ], ['Gli Svincolati', 'Paolo', 3]),
      ],
    },
    {
      id: 'demo-playoff-round-2',
      number: 2,
      name: 'Finale Scudetto',
      matchdayId: 'demo-playoff-md-2',
      matchdayNumber: 38,
      startsAt: '2027-05-30T13:00:00Z',
      locksAt: '2027-05-30T12:55:00Z',
      endsAt: '2027-06-01T22:45:00Z',
      status: 'scheduled',
      finalizedAt: null,
      ties: [
        {
          id: 'demo-playoff-tie-3',
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

export function useLeaguePlayoffs(
  leagueId: string | null,
  isDemo: boolean,
) {
  const [playoffs, setPlayoffs] = useState<LeaguePlayoffState | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);

  const refresh = useCallback(async (silent = false) => {
    if (isDemo) {
      setPlayoffs(demoPlayoffs);
      setError('');
      setLoading(false);
      return;
    }
    if (!leagueId) {
      setPlayoffs(null);
      setError('');
      setLoading(false);
      return;
    }
    if (!silent) {
      setLoading(true);
    }
    try {
      setPlayoffs(await fetchLeaguePlayoffs(leagueId));
      setError('');
    } catch (cause) {
      setError(
        cause instanceof Error
          ? cause.message
          : 'I playoff non rispondono.',
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
    return subscribeToLeaguePlayoffs(leagueId, () => void refresh(true));
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

  const configure = async (participantCount: 4 | 8) => {
    if (!leagueId || isDemo) {
      return { error: 'I playoff demo sono già configurati.' };
    }
    setBusy(true);
    const outcome = await configureLeaguePlayoffs(
      leagueId,
      participantCount,
    );
    if (!outcome.error) {
      await refresh(true);
    }
    setBusy(false);
    return outcome;
  };

  const start = async (startMatchdayNumber: number) => {
    if (!leagueId || isDemo) {
      return { error: 'I playoff demo sono già iniziati.' };
    }
    setBusy(true);
    const outcome = await startLeaguePlayoffs(
      leagueId,
      startMatchdayNumber,
    );
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
    const outcome = await finalizeLeaguePlayoffRound(
      leagueId,
      playoffs?.currentRound ?? 0,
    );
    if (!outcome.error) {
      await refresh(true);
    }
    setBusy(false);
    return outcome;
  };

  return {
    playoffs,
    loading,
    error,
    busy,
    refresh,
    configure,
    start,
    finalizeCurrentRound,
  };
}

function waitingTie(
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
