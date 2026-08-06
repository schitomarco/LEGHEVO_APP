import { useCallback, useEffect, useState } from 'react';
import {
  defaultLeagueSettings,
  fetchLeagueSettings,
  updateLeagueSettings,
} from '../services/settingsService';
import type { LeagueSettings, LeagueSummary } from '../types';

export function useLeagueSettings(league: LeagueSummary | null) {
  const isDemo = Boolean(league?.isDemo);
  const [settings, setSettings] = useState<LeagueSettings>(
    defaultLeagueSettings,
  );
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');

  const refresh = useCallback(async () => {
    if (!league) {
      setSettings(defaultLeagueSettings);
      setLoading(false);
      return;
    }
    if (isDemo) {
      setLoading(false);
      setError('');
      return;
    }

    setLoading(true);
    try {
      setSettings(await fetchLeagueSettings(league.id));
      setError('');
    } catch {
      setError('Le regole non arrivano. Qualcuno ha nascosto il regolamento.');
    } finally {
      setLoading(false);
    }
  }, [isDemo, league]);

  useEffect(() => {
    void refresh();
  }, [refresh]);

  const save = async (next: LeagueSettings, changeReason: string) => {
    if (!league) {
      return { error: 'Prima scegli una lega.' };
    }
    if (isDemo) {
      setSettings(next);
      return {};
    }

    setSaving(true);
    const outcome = await updateLeagueSettings(
      league.id,
      next,
      changeReason,
    );
    setSaving(false);

    if (outcome.error) {
      return { error: outcome.error };
    }
    if (outcome.settings) {
      setSettings(outcome.settings);
    }
    return {};
  };

  return {
    settings,
    loading,
    saving,
    error,
    refresh,
    save,
  };
}
