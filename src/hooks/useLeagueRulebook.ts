import { useCallback, useEffect, useState } from 'react';
import {
  fetchLeagueRulebook,
  subscribeToLeagueRulebook,
} from '../services/rulebookService';
import { defaultLeagueSettings } from '../services/settingsService';
import type { LeagueRulebook, LeagueSummary } from '../types';

function createDemoRulebook(): LeagueRulebook {
  return {
    leagueId: 'demo-league',
    leagueName: 'Gli Irriducibili',
    mode: 'classic',
    status: 'active',
    season: '2026',
    teamLimit: 8,
    startingCredits: 500,
    rosterSize: 25,
    isDirector: true,
    currentRevision: 2,
    updatedAt: new Date(
      Date.now() - 2 * 24 * 60 * 60 * 1000,
    ).toISOString(),
    settings: {
      ...defaultLeagueSettings,
      marketMinimumPrice: 3,
      releaseRefundPercent: 60,
      defenseModifierEnabled: true,
      homeBonus: 1,
    },
    revisions: [
      {
        id: 'demo-rule-revision-2',
        revision: 2,
        reason: 'Adeguato il rimborso svincoli dopo il voto della lega.',
        changedKeys: ['release_refund_percent'],
        changedAt: new Date(
          Date.now() - 2 * 24 * 60 * 60 * 1000,
        ).toISOString(),
        changedBy: 'Marco Schito',
      },
      {
        id: 'demo-rule-revision-1',
        revision: 1,
        reason: 'Attivato il modificatore difesa per la nuova stagione.',
        changedKeys: [
          'defense_modifier_enabled',
          'defense_modifier_min_defenders',
        ],
        changedAt: new Date(
          Date.now() - 30 * 24 * 60 * 60 * 1000,
        ).toISOString(),
        changedBy: 'Marco Schito',
      },
    ],
  };
}

export function useLeagueRulebook(league: LeagueSummary | null) {
  const isDemo = Boolean(league?.isDemo);
  const [rulebook, setRulebook] = useState<LeagueRulebook | null>(
    isDemo ? createDemoRulebook() : null,
  );
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');

  const refresh = useCallback(
    async (silent = false) => {
      if (!league) {
        setRulebook(null);
        setError('');
        setLoading(false);
        return;
      }

      if (isDemo) {
        setRulebook(createDemoRulebook());
        setError('');
        setLoading(false);
        return;
      }

      if (!silent) {
        setLoading(true);
      }
      try {
        setRulebook(await fetchLeagueRulebook(league.id));
        setError('');
      } catch (cause) {
        setError(
          cause instanceof Error
            ? cause.message
            : 'Il regolamento non è disponibile.',
        );
      } finally {
        setLoading(false);
      }
    },
    [isDemo, league],
  );

  useEffect(() => {
    void refresh();
  }, [refresh]);

  useEffect(() => {
    if (!league || isDemo) {
      return;
    }
    return subscribeToLeagueRulebook(
      league.id,
      () => void refresh(true),
    );
  }, [isDemo, league, refresh]);

  return { rulebook, loading, error, refresh };
}
