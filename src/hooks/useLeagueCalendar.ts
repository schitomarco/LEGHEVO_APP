import { useCallback, useEffect, useState } from 'react';
import { AppState } from 'react-native';
import {
  fetchLeagueCalendar,
  fetchLeagueCalendarState,
  fetchLeagueScheduleHealth,
  generateLeagueCalendar,
  resetLeagueCalendar,
  subscribeToLeagueCalendar,
  type GenerateCalendarInput,
} from '../services/calendarService';
import type {
  CalendarFixture,
  LeagueCalendarState,
  LeagueScheduleHealth,
} from '../types';

const demoCalendar: CalendarFixture[] = [
  {
    id: 'demo-calendar-1',
    matchdayId: 'demo-matchday-7',
    matchdayNumber: 7,
    startsAt: '2026-09-19T18:00:00Z',
    locksAt: '2026-09-19T18:00:00Z',
    endsAt: '2026-09-21T22:45:00Z',
    scheduleSource: 'provider',
    scheduleSyncedAt: '2026-09-18T18:00:00Z',
    providerFixtureCount: 10,
    providerFinalFixtureCount: 0,
    homeTeam: {
      id: 'demo-team',
      name: 'Diavoli del Sud',
      managerId: 'demo-user',
    },
    awayTeam: {
      id: 'demo-team-2',
      name: 'Tiki Taka Boom',
      managerId: 'demo-user-2',
    },
    homePoints: null,
    awayPoints: null,
    homeGoals: null,
    awayGoals: null,
    finalized: false,
  },
  {
    id: 'demo-calendar-2',
    matchdayId: 'demo-matchday-7',
    matchdayNumber: 7,
    startsAt: '2026-09-19T18:00:00Z',
    locksAt: '2026-09-19T18:00:00Z',
    endsAt: '2026-09-21T22:45:00Z',
    scheduleSource: 'provider',
    scheduleSyncedAt: '2026-09-18T18:00:00Z',
    providerFixtureCount: 10,
    providerFinalFixtureCount: 0,
    homeTeam: {
      id: 'demo-team-3',
      name: 'Atletico Ma Non Troppo',
      managerId: 'demo-user-3',
    },
    awayTeam: {
      id: 'demo-team-4',
      name: 'Real Colizzati',
      managerId: 'demo-user-4',
    },
    homePoints: 72.5,
    awayPoints: 68,
    homeGoals: 2,
    awayGoals: 1,
    finalized: true,
  },
  {
    id: 'demo-calendar-3',
    matchdayId: 'demo-matchday-8',
    matchdayNumber: 8,
    startsAt: '2026-09-26T18:00:00Z',
    locksAt: '2026-09-26T18:00:00Z',
    endsAt: '2026-09-28T22:45:00Z',
    scheduleSource: 'provider',
    scheduleSyncedAt: '2026-09-25T18:00:00Z',
    providerFixtureCount: 10,
    providerFinalFixtureCount: 0,
    homeTeam: {
      id: 'demo-team-4',
      name: 'Real Colizzati',
      managerId: 'demo-user-4',
    },
    awayTeam: {
      id: 'demo-team',
      name: 'Diavoli del Sud',
      managerId: 'demo-user',
    },
    homePoints: null,
    awayPoints: null,
    homeGoals: null,
    awayGoals: null,
    finalized: false,
  },
  {
    id: 'demo-calendar-4',
    matchdayId: 'demo-matchday-8',
    matchdayNumber: 8,
    startsAt: '2026-09-26T18:00:00Z',
    locksAt: '2026-09-26T18:00:00Z',
    endsAt: '2026-09-28T22:45:00Z',
    scheduleSource: 'provider',
    scheduleSyncedAt: '2026-09-25T18:00:00Z',
    providerFixtureCount: 10,
    providerFinalFixtureCount: 0,
    homeTeam: {
      id: 'demo-team-2',
      name: 'Tiki Taka Boom',
      managerId: 'demo-user-2',
    },
    awayTeam: {
      id: 'demo-team-3',
      name: 'Atletico Ma Non Troppo',
      managerId: 'demo-user-3',
    },
    homePoints: null,
    awayPoints: null,
    homeGoals: null,
    awayGoals: null,
    finalized: false,
  },
];

const demoState: LeagueCalendarState = {
  memberCount: 4,
  teamCount: 4,
  teamLimit: 4,
  fullRosterCount: 4,
  rosterSize: 25,
  fixtureCount: 4,
  matchdayCount: 2,
  firstMatchday: 7,
  lastMatchday: 8,
  season: '2026',
  returnLeg: true,
  generatedAt: '2026-09-01T18:00:00Z',
  competitionStartedAt: null,
  calendarExists: true,
  isOwner: true,
  isDirector: true,
  canGenerate: false,
  canReset: true,
  checks: {
    membersReady: true,
    teamsReady: true,
    rostersReady: true,
    calendarEmpty: false,
    competitionNotStarted: true,
    marketReady: true,
    tradesSettled: true,
    auctionIntegrityReady: true,
    auctionClosed: true,
    calendarIntegrityReady: true,
    calendarSnapshotStable: true,
    precompetitionSnapshotLocked: true,
    snapshotMutationGuardReady: true,
  },
  preflight: {
    version: 1,
    checkedAt: '2026-09-01T18:00:00Z',
    pendingTradeCount: 0,
    unfinishedAuctionCount: 0,
    biddingItemCount: 0,
    expectedFixtureCount: 12,
    expectedMatchdayCount: 6,
    pairIssueCount: 0,
    teamMatchdayIssueCount: 0,
    calendarSnapshotPresent: true,
    calendarSnapshotStable: true,
    calendarIntegrityVerifiedAt: '2026-09-01T18:00:00Z',
    precompetitionSnapshotLocked: true,
    snapshotMutationGuardReady: true,
    snapshotMutationGuardCount: 9,
    canGenerateCalendar: false,
    canStartCompetition: true,
    checks: {
      marketReady: true,
      tradesSettled: true,
      auctionIntegrityReady: true,
      auctionClosed: true,
      calendarIntegrityReady: true,
      calendarSnapshotStable: true,
      precompetitionSnapshotLocked: true,
      snapshotMutationGuardReady: true,
    },
  },
  teams: [
    {
      teamId: 'demo-team',
      teamName: 'Diavoli del Sud',
      managerId: 'demo-user',
      rosterCount: 25,
      rosterSize: 25,
      complete: true,
    },
    {
      teamId: 'demo-team-2',
      teamName: 'Tiki Taka Boom',
      managerId: 'demo-user-2',
      rosterCount: 25,
      rosterSize: 25,
      complete: true,
    },
    {
      teamId: 'demo-team-3',
      teamName: 'Atletico Ma Non Troppo',
      managerId: 'demo-user-3',
      rosterCount: 25,
      rosterSize: 25,
      complete: true,
    },
    {
      teamId: 'demo-team-4',
      teamName: 'Real Colizzati',
      managerId: 'demo-user-4',
      rosterCount: 25,
      rosterSize: 25,
      complete: true,
    },
  ],
};

const demoScheduleHealth: LeagueScheduleHealth = {
  matchdayCount: 2,
  providerAlignedMatchdays: 2,
  estimatedMatchdays: 0,
  lastScheduleSyncAt: '2026-09-25T18:00:00Z',
  nextMatchday: {
    id: 'demo-matchday-7',
    number: 7,
    startsAt: '2026-09-19T18:00:00Z',
    locksAt: '2026-09-19T18:00:00Z',
    endsAt: '2026-09-21T22:45:00Z',
    scheduleSource: 'provider',
    providerFixtureCount: 10,
    providerFinalFixtureCount: 0,
  },
};

export function useLeagueCalendar(
  leagueId: string | null,
  isDemo: boolean,
) {
  const [fixtures, setFixtures] = useState<CalendarFixture[]>([]);
  const [state, setState] = useState<LeagueCalendarState | null>(null);
  const [scheduleHealth, setScheduleHealth] =
    useState<LeagueScheduleHealth | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');

  const refresh = useCallback(
    async (silent = false) => {
      if (!leagueId) {
        setFixtures([]);
        setState(null);
        setScheduleHealth(null);
        setError('');
        setLoading(false);
        return;
      }

      if (isDemo) {
        setFixtures(demoCalendar);
        setState(demoState);
        setScheduleHealth(demoScheduleHealth);
        setError('');
        setLoading(false);
        return;
      }

      if (!silent) {
        setLoading(true);
      }
      try {
        const [nextFixtures, nextState, nextScheduleHealth] =
          await Promise.all([
            fetchLeagueCalendar(leagueId),
            fetchLeagueCalendarState(leagueId),
            fetchLeagueScheduleHealth(leagueId),
          ]);
        setFixtures(nextFixtures);
        setState(nextState);
        setScheduleHealth(nextScheduleHealth);
        setError('');
      } catch (caught) {
        setError(
          caught instanceof Error
            ? caught.message
            : 'Il calendario non arriva dagli spogliatoi.',
        );
      } finally {
        setLoading(false);
      }
    },
    [isDemo, leagueId],
  );

  useEffect(() => {
    void refresh();
  }, [refresh]);

  useEffect(() => {
    if (!leagueId || isDemo) {
      return;
    }
    return subscribeToLeagueCalendar(leagueId, () => void refresh(true));
  }, [isDemo, leagueId, refresh]);

  useEffect(() => {
    if (!leagueId || isDemo) {
      return;
    }

    const subscription = AppState.addEventListener('change', (nextState) => {
      if (nextState === 'active') {
        void refresh(true);
      }
    });

    return () => subscription.remove();
  }, [isDemo, leagueId, refresh]);

  const generate = async (
    input: Omit<GenerateCalendarInput, 'leagueId'>,
  ) => {
    if (!leagueId || isDemo) {
      return { error: 'La demo ha già un calendario di esempio.' };
    }

    const outcome = await generateLeagueCalendar({ ...input, leagueId });
    if (outcome.affected !== undefined) {
      await refresh(true);
    }
    return outcome;
  };

  const reset = async () => {
    if (!leagueId) {
      return { error: 'Prima scegli una lega.' };
    }
    if (isDemo) {
      return { error: 'Il calendario della demo resta disponibile.' };
    }

    const outcome = await resetLeagueCalendar(leagueId);
    if (outcome.affected !== undefined) {
      await refresh(true);
    }
    return outcome;
  };

  return {
    fixtures,
    state,
    scheduleHealth,
    loading,
    error,
    generate,
    reset,
    refresh,
  };
}
