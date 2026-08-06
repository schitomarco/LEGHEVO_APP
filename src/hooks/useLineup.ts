import { useCallback, useEffect, useState } from 'react';
import { AppState } from 'react-native';
import {
  fetchLineupContext,
  saveLineup,
  subscribeToLineup,
  type SaveLineupInput,
} from '../services/lineupService';
import type { LineupContext } from '../types';

function createDemoContext(): LineupContext {
  const startsAt = new Date();
  startsAt.setDate(startsAt.getDate() + 2);
  startsAt.setHours(18, 0, 0, 0);

  return {
    matchday: {
      id: 'demo-matchday-7',
      number: 7,
      startsAt: startsAt.toISOString(),
      locksAt: startsAt.toISOString(),
    },
    opponentName: 'Tiki Taka Boom',
    home: true,
    formation: null,
    starterIds: [],
    benchIds: [],
    benchLimit: 4,
    rosterCount: 15,
    submittedAt: null,
    firstSubmittedAt: null,
    updatedAt: null,
    lockedAt: null,
    lineupOrigin: 'empty',
    sourceMatchdayNumber: null,
    willAutoCarry: false,
    firstSubmissionRequired: true,
    revision: 0,
    contentHash: null,
    serverNow: new Date().toISOString(),
    secondsUntilLock: Math.max(
      Math.floor((startsAt.getTime() - Date.now()) / 1000),
      0,
    ),
    canSubmit: true,
    lockState: 'open',
    submissionPolicy: 'guarded_v1',
    integrityReady: true,
    directWritesBlocked: true,
    deadlinePolicy: 'guarded_v1',
    deadlineOutcome: 'open',
    deadlineCertified: false,
    deadlineProcessedAt: null,
    deadlineEventReady: true,
    immutableAfterLock: false,
    matchdayLineupsFinalizedAt: null,
    matchdayLineupLockRevision: 0,
    matchdayLineupLockHash: null,
  };
}

export function useLineup(
  leagueId: string | null,
  fantasyTeamId: string | null,
  isDemo: boolean,
) {
  const [context, setContext] = useState<LineupContext | null>(() =>
    isDemo ? createDemoContext() : null,
  );
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');

  const refresh = useCallback(async (silent = false) => {
    if (isDemo) {
      setContext((current) => current ?? createDemoContext());
      setError('');
      setLoading(false);
      return;
    }

    if (!leagueId || !fantasyTeamId) {
      setContext(null);
      setError('');
      setLoading(false);
      return;
    }

    if (!silent) {
      setLoading(true);
    }
    try {
      setContext(await fetchLineupContext(leagueId));
      setError('');
    } catch (caught) {
      setError(
        caught instanceof Error
          ? caught.message
          : 'Non riesco a trovare la prossima distinta.',
      );
    } finally {
      setLoading(false);
    }
  }, [fantasyTeamId, isDemo, leagueId]);

  useEffect(() => {
    void refresh();
  }, [refresh]);

  useEffect(() => {
    if (isDemo || !leagueId || !fantasyTeamId) {
      return;
    }

    return subscribeToLineup(leagueId, fantasyTeamId, () => {
      void refresh(true);
    });
  }, [fantasyTeamId, isDemo, leagueId, refresh]);

  useEffect(() => {
    if (isDemo) {
      return;
    }

    const subscription = AppState.addEventListener('change', (state) => {
      if (state === 'active') {
        void refresh(true);
      }
    });

    return () => subscription.remove();
  }, [isDemo, refresh]);

  const submit = async (
    input: Omit<SaveLineupInput, 'fantasyTeamId' | 'matchdayId' | 'expectedRevision'>,
  ): Promise<{ error?: string }> => {
    if (!context || !fantasyTeamId) {
      if (!isDemo) {
        return { error: 'Nessuna giornata disponibile.' };
      }
    }

    if (isDemo) {
      setContext((current) =>
        current
          ? {
              ...current,
              formation: input.formation,
              starterIds: input.starterIds,
              benchIds: input.benchIds,
              submittedAt: new Date().toISOString(),
              firstSubmittedAt:
                current.firstSubmittedAt ?? new Date().toISOString(),
              updatedAt: new Date().toISOString(),
              lockedAt: null,
              lineupOrigin: 'manager',
              sourceMatchdayNumber: null,
              willAutoCarry: false,
              firstSubmissionRequired: false,
              revision: current.revision + 1,
              contentHash: null,
              serverNow: new Date().toISOString(),
              canSubmit: true,
              lockState: 'open',
              submissionPolicy: 'guarded_v1',
              integrityReady: true,
              directWritesBlocked: true,
              deadlinePolicy: 'guarded_v1',
              deadlineOutcome: 'open',
              deadlineCertified: false,
              deadlineProcessedAt: null,
              deadlineEventReady: true,
              immutableAfterLock: false,
              matchdayLineupsFinalizedAt: null,
              matchdayLineupLockRevision: 0,
              matchdayLineupLockHash: null,
            }
          : current,
      );
      return {};
    }

    const outcome = await saveLineup({
      ...input,
      fantasyTeamId: fantasyTeamId!,
      matchdayId: context!.matchday.id,
      expectedRevision: context!.revision,
    });
    if (!outcome.error) {
      await refresh();
    } else if (outcome.error.includes('altro dispositivo')) {
      await refresh(true);
    }
    return outcome;
  };

  return { context, loading, error, refresh, submit };
}
