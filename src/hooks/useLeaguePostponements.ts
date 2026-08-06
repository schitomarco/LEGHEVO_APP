import { useCallback, useEffect, useState } from 'react';
import {
  applyFixturePoliticalScore,
  fetchLeaguePostponementCenter,
  revokeFixturePoliticalScore,
  subscribeToFixtureResolutions,
} from '../services/postponementService';
import type {
  LeaguePostponementCenter,
  LeagueSummary,
} from '../types';

function createDemoCenter(): LeaguePostponementCenter {
  return {
    leagueId: 'demo-league',
    leagueName: 'Serie A da divano',
    isOwner: true,
    issueCount: 2,
    resolvedCount: 1,
    unresolvedCount: 1,
    protected: true,
    idempotencyReady: true,
    revisionReady: true,
    certifiedActionCount: 1,
    lastCertifiedAt: new Date().toISOString(),
    integrity: {
      healthy: true,
      activeResolutionCount: 1,
      certifiedActionCount: 1,
      invalidResolutionCount: 0,
      invalidActionCount: 0,
      duplicateActiveCount: 0,
      providerFinalContinuityReady: true,
    },
    issues: [
      {
        providerFixtureId: 'demo-provider-fixture-1',
        externalFixtureId: 'demo-9001',
        matchdayId: 'demo-matchday-7',
        matchdayNumber: 7,
        kickoffAt: new Date(Date.now() - 36 * 60 * 60 * 1000).toISOString(),
        status: 'PST',
        homeTeam: 'Torino',
        awayTeam: 'Lazio',
        locked: false,
        resolution: null,
      },
      {
        providerFixtureId: 'demo-provider-fixture-2',
        externalFixtureId: 'demo-9002',
        matchdayId: 'demo-matchday-6',
        matchdayNumber: 6,
        kickoffAt: new Date(Date.now() - 8 * 24 * 60 * 60 * 1000).toISOString(),
        status: 'SUSP',
        homeTeam: 'Udinese',
        awayTeam: 'Fiorentina',
        locked: false,
        resolution: {
          id: 'demo-resolution-1',
          decision: 'political_score',
          politicalScore: 6,
          reason: 'Recupero oltre la finestra prevista dal regolamento.',
          decidedAt: new Date(
            Date.now() - 6 * 24 * 60 * 60 * 1000,
          ).toISOString(),
          decidedBy: 'Marco',
          revision: 1,
          stateFingerprint: 'demo-certified-resolution',
          protected: true,
        },
      },
    ],
  };
}

export function useLeaguePostponements(league: LeagueSummary | null) {
  const isDemo = Boolean(league?.isDemo);
  const [center, setCenter] = useState<LeaguePostponementCenter | null>(
    isDemo ? createDemoCenter() : null,
  );
  const [loading, setLoading] = useState(true);
  const [savingId, setSavingId] = useState<string | null>(null);
  const [error, setError] = useState('');
  const [notice, setNotice] = useState('');

  const refresh = useCallback(async () => {
    if (!league) {
      setCenter(null);
      setError('');
      setLoading(false);
      return;
    }
    if (isDemo) {
      setCenter((current) => current ?? createDemoCenter());
      setError('');
      setLoading(false);
      return;
    }

    setLoading(true);
    try {
      setCenter(await fetchLeaguePostponementCenter(league.id));
      setError('');
    } catch (cause) {
      setError(
        cause instanceof Error
          ? cause.message
          : 'Il centro rinvii non risponde.',
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
    return subscribeToFixtureResolutions(league.id, () => void refresh());
  }, [isDemo, league, refresh]);

  const applyPoliticalScore = async (
    providerFixtureId: string,
    score: number,
    reason: string,
  ): Promise<{ error?: string }> => {
    if (!league) {
      return { error: 'Prima scegli una lega.' };
    }

    setSavingId(providerFixtureId);
    setNotice('');
    if (isDemo) {
      setCenter((current) => {
        if (!current) return current;
        const issues = current.issues.map((issue) =>
          issue.providerFixtureId === providerFixtureId
            ? {
                ...issue,
                resolution: {
                  id: `demo-resolution-${providerFixtureId}`,
                  decision: 'political_score' as const,
                  politicalScore: score,
                  reason,
                  decidedAt: new Date().toISOString(),
                  decidedBy: 'Marco',
                  revision: 1,
                  stateFingerprint: `demo-${providerFixtureId}`,
                  protected: true,
                },
              }
            : issue,
        );
        const resolvedCount = issues.filter(
          (issue) => issue.resolution,
        ).length;
        return {
          ...current,
          issues,
          resolvedCount,
          unresolvedCount: issues.length - resolvedCount,
        };
      });
      setNotice('Voto d’ufficio applicato nella simulazione.');
      setSavingId(null);
      return {};
    }

    const outcome = await applyFixturePoliticalScore(
      league.id,
      providerFixtureId,
      score,
      reason,
    );
    setSavingId(null);
    if (outcome.error) {
      return { error: outcome.error };
    }

    setNotice('Voto d’ufficio registrato e calcoli aggiornati.');
    await refresh();
    return {};
  };

  const revokePoliticalScore = async (
    providerFixtureId: string,
    resolutionId: string,
    reason: string,
    expectedRevision: number,
  ): Promise<{ error?: string }> => {
    if (!league) {
      return { error: 'Prima scegli una lega.' };
    }

    setSavingId(providerFixtureId);
    setNotice('');
    if (isDemo) {
      setCenter((current) => {
        if (!current) return current;
        const issues = current.issues.map((issue) =>
          issue.providerFixtureId === providerFixtureId
            ? { ...issue, resolution: null }
            : issue,
        );
        const resolvedCount = issues.filter(
          (issue) => issue.resolution,
        ).length;
        return {
          ...current,
          issues,
          resolvedCount,
          unresolvedCount: issues.length - resolvedCount,
        };
      });
      setNotice('Voto revocato: la simulazione attende il recupero.');
      setSavingId(null);
      return {};
    }

    const outcome = await revokeFixturePoliticalScore(
      league.id,
      resolutionId,
      reason,
      expectedRevision,
    );
    setSavingId(null);
    if (outcome.error) {
      return { error: outcome.error };
    }

    setNotice('Voto revocato: LEGHEVO attende nuovamente il recupero.');
    await refresh();
    return {};
  };

  return {
    center,
    loading,
    savingId,
    error,
    notice,
    refresh,
    applyPoliticalScore,
    revokePoliticalScore,
  };
}
