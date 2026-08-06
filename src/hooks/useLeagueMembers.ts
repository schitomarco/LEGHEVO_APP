import { useCallback, useEffect, useState } from 'react';
import { AppState } from 'react-native';
import {
  fetchLeagueMembers,
  removeLeagueMember,
  setLeagueMemberRole,
  subscribeToLeagueMembers,
} from '../services/leagueService';
import type { LeagueMemberSummary } from '../types';

const demoMembers: LeagueMemberSummary[] = [
  {
    userId: 'demo-user',
    displayName: 'Marco Schito',
    role: 'admin',
    isOwner: true,
    joinedAt: '2026-07-01T18:00:00Z',
    team: {
      id: 'demo-team',
      name: 'Diavoli del Sud',
      creditsRemaining: 412,
    },
  },
  {
    userId: 'demo-user-2',
    displayName: 'Luca',
    role: 'manager',
    isOwner: false,
    joinedAt: '2026-07-01T18:01:00Z',
    team: {
      id: 'demo-team-2',
      name: 'Tiki Taka Boom',
      creditsRemaining: 388,
    },
  },
  {
    userId: 'demo-user-3',
    displayName: 'Antonio',
    role: 'manager',
    isOwner: false,
    joinedAt: '2026-07-01T18:02:00Z',
    team: {
      id: 'demo-team-3',
      name: 'Atletico Ma Non Troppo',
      creditsRemaining: 405,
    },
  },
];

export function useLeagueMembers(
  leagueId: string | null,
  isDemo: boolean,
) {
  const [members, setMembers] = useState<LeagueMemberSummary[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');

  const refresh = useCallback(async (silent = false) => {
    if (!leagueId) {
      setMembers([]);
      setError('');
      setLoading(false);
      return;
    }

    if (isDemo) {
      setMembers(demoMembers);
      setError('');
      setLoading(false);
      return;
    }

    if (!silent) {
      setLoading(true);
    }
    try {
      setMembers(await fetchLeagueMembers(leagueId));
      setError('');
    } catch {
      setError('Convocazioni momentaneamente non disponibili.');
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

    return subscribeToLeagueMembers(leagueId, () => void refresh(true));
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

  const changeRole = async (
    userId: string,
    role: LeagueMemberSummary['role'],
    expectedRevision: number,
  ) => {
    if (!leagueId) {
      return { error: 'Prima scegli una lega.' };
    }
    if (isDemo) {
      setMembers((current) =>
        current.map((member) =>
          member.userId === userId ? { ...member, role } : member,
        ),
      );
      return {};
    }

    const outcome = await setLeagueMemberRole(
      leagueId,
      userId,
      role,
      expectedRevision,
    );
    if (!outcome.error) {
      await refresh(true);
    }
    return outcome;
  };

  const remove = async (userId: string, expectedRevision: number) => {
    if (!leagueId) {
      return { error: 'Prima scegli una lega.' };
    }
    if (isDemo) {
      setMembers((current) =>
        current.filter((member) => member.userId !== userId),
      );
      return {};
    }

    const outcome = await removeLeagueMember(
      leagueId,
      userId,
      expectedRevision,
    );
    if (!outcome.error) {
      await refresh(true);
    }
    return outcome;
  };

  return {
    members,
    loading,
    error,
    refresh,
    changeRole,
    remove,
  };
}
