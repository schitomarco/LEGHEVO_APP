import { useCallback, useEffect, useState } from 'react';
import { AppState } from 'react-native';
import {
  createLeague,
  fetchUserLeagues,
  joinLeague,
  previewLeagueInvite,
  subscribeToLeagueOverview,
  type CreateLeagueInput,
  type JoinLeagueInput,
  type LeagueActionOutcome,
  type LeagueInvitePreviewOutcome,
} from '../services/leagueService';
import type { LeagueSummary } from '../types';

const demoLeague: LeagueSummary = {
  id: 'demo-league',
  name: 'Serie A da divano',
  inviteCode: 'DIVANO26',
  mode: 'classic',
  status: 'active',
  teamLimit: 8,
  startingCredits: 500,
  rosterSize: 25,
  memberCount: 8,
  ownerId: 'demo-user',
  invitesOpen: false,
  competitionStartedAt: '2026-09-01T18:00:00Z',
  season: '2026',
  currentRole: 'admin',
  team: {
    id: 'demo-team',
    name: 'Diavoli del Sud',
    creditsRemaining: 412,
  },
  isDemo: true,
};

export function useLeagues(userId: string | null, isDemo: boolean) {
  const [leagues, setLeagues] = useState<LeagueSummary[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');

  const refresh = useCallback(async (silent = false) => {
    if (isDemo) {
      setLeagues([demoLeague]);
      setError('');
      setLoading(false);
      return;
    }

    if (!userId) {
      setLeagues([]);
      setError('');
      setLoading(false);
      return;
    }

    if (!silent) {
      setLoading(true);
    }
    try {
      setLeagues(await fetchUserLeagues(userId));
      setError('');
    } catch {
      setError('Non riesco a caricare le leghe. Riprova tra poco.');
    } finally {
      setLoading(false);
    }
  }, [isDemo, userId]);

  useEffect(() => {
    void refresh();
  }, [refresh]);

  useEffect(() => {
    if (!userId || isDemo) {
      return;
    }

    return subscribeToLeagueOverview(userId, () => void refresh(true));
  }, [isDemo, refresh, userId]);

  useEffect(() => {
    if (!userId || isDemo) {
      return;
    }

    const subscription = AppState.addEventListener('change', (state) => {
      if (state === 'active') {
        void refresh(true);
      }
    });

    return () => subscription.remove();
  }, [isDemo, refresh, userId]);


  const previewInvite = async (
    inviteCode: string,
  ): Promise<LeagueInvitePreviewOutcome> => {
    if (isDemo || !userId) {
      return { error: 'Per verificare un invito serve un account LEGHEVO.' };
    }

    return previewLeagueInvite(inviteCode);
  };

  const create = async (
    input: CreateLeagueInput,
  ): Promise<LeagueActionOutcome> => {
    if (isDemo || !userId) {
      return { error: 'Per creare una lega serve un account LEGHEVO.' };
    }

    const outcome = await createLeague(input);
    if (outcome.league) {
      await refresh(true);
    }
    return outcome;
  };

  const join = async (
    input: JoinLeagueInput,
  ): Promise<LeagueActionOutcome> => {
    if (isDemo || !userId) {
      return { error: 'Per entrare in una lega serve un account LEGHEVO.' };
    }

    const outcome = await joinLeague(input);
    if (outcome.league) {
      await refresh(true);
    }
    return outcome;
  };

  return {
    leagues,
    loading,
    error,
    refresh,
    create,
    join,
    previewInvite,
  };
}
