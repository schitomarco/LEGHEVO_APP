import { supabase } from '../lib/supabase';
import type { LineupContext } from '../types';

export type SaveLineupInput = {
  fantasyTeamId: string;
  matchdayId: string;
  formation: string;
  starterIds: string[];
  benchIds: string[];
  expectedRevision: number;
};

export async function fetchLineupContext(
  leagueId: string,
): Promise<LineupContext | null> {
  if (!supabase) {
    return null;
  }

  let { data, error } = await supabase.rpc(
    'get_my_lineup_workspace_v3',
    { p_league_id: leagueId },
  );

  if (error && isMissingRpc(error.message, 'get_my_lineup_workspace_v3')) {
    const protectedFallback = await supabase.rpc(
      'get_my_lineup_workspace_v2',
      { p_league_id: leagueId },
    );
    data = protectedFallback.data;
    error = protectedFallback.error;
  }

  if (error && isMissingRpc(error.message, 'get_my_lineup_workspace_v2')) {
    const fallback = await supabase.rpc('get_my_lineup_workspace', {
      p_league_id: leagueId,
    });
    data = fallback.data;
    error = fallback.error;
  }

  if (error) {
    throw new Error(translateLineupError(error.message));
  }

  return normalizeLineupContext(data);
}

export async function saveLineup(input: SaveLineupInput) {
  if (!supabase) {
    return { error: 'Il collegamento al backend non è configurato.' };
  }

  const requestId = createRequestId();
  let { data, error } = await supabase.rpc('save_team_lineup_guarded_v1', {
    p_fantasy_team_id: input.fantasyTeamId,
    p_matchday_id: input.matchdayId,
    p_formation: input.formation,
    p_starter_ids: input.starterIds,
    p_bench_ids: input.benchIds,
    p_expected_revision: input.expectedRevision,
    p_request_id: requestId,
  });

  if (error && isMissingRpc(error.message, 'save_team_lineup_guarded_v1')) {
    const fallback = await supabase.rpc('save_team_lineup', {
      p_fantasy_team_id: input.fantasyTeamId,
      p_matchday_id: input.matchdayId,
      p_formation: input.formation,
      p_starter_ids: input.starterIds,
      p_bench_ids: input.benchIds,
    });
    data = fallback.data;
    error = fallback.error;
  }

  if (error) {
    return { error: translateLineupError(error.message) };
  }

  const raw = data && typeof data === 'object'
    ? (data as Record<string, unknown>)
    : null;

  return {
    data,
    revision: raw ? toNumber(raw.revision) : input.expectedRevision + 1,
  };
}

export function subscribeToLineup(
  leagueId: string,
  fantasyTeamId: string,
  onChange: () => void,
) {
  if (!supabase) {
    return () => undefined;
  }

  const client = supabase;
  const channel = client
    .channel(`lineup-${leagueId}-${fantasyTeamId}`)
    .on(
      'postgres_changes',
      {
        event: '*',
        schema: 'public',
        table: 'lineups',
        filter: `fantasy_team_id=eq.${fantasyTeamId}`,
      },
      onChange,
    )
    .on(
      'postgres_changes',
      {
        event: '*',
        schema: 'public',
        table: 'lineup_deadline_events',
        filter: `league_id=eq.${leagueId}`,
      },
      onChange,
    )
    .on(
      'postgres_changes',
      {
        event: '*',
        schema: 'public',
        table: 'fantasy_fixtures',
        filter: `league_id=eq.${leagueId}`,
      },
      onChange,
    )
    .on(
      'postgres_changes',
      {
        event: '*',
        schema: 'public',
        table: 'roster_entries',
        filter: `league_id=eq.${leagueId}`,
      },
      onChange,
    )
    .subscribe();

  return () => {
    void client.removeChannel(channel);
  };
}

function normalizeLineupContext(value: unknown): LineupContext | null {
  if (!value || typeof value !== 'object') {
    return null;
  }

  const raw = value as Record<string, unknown>;
  if (!raw.available) {
    return null;
  }

  const rawMatchday =
    raw.matchday && typeof raw.matchday === 'object'
      ? (raw.matchday as Record<string, unknown>)
      : {};
  const matchdayId = toString(rawMatchday.id);
  const opponentName = toString(raw.opponentName);
  const startsAt = toString(rawMatchday.startsAt);
  const locksAt = toString(rawMatchday.locksAt);

  if (!matchdayId || !opponentName || !startsAt || !locksAt) {
    return null;
  }

  return {
    matchday: {
      id: matchdayId,
      number: toNumber(rawMatchday.number),
      startsAt,
      locksAt,
    },
    opponentName,
    home: Boolean(raw.home),
    formation: toString(raw.formation),
    starterIds: toStringArray(raw.starterIds),
    benchIds: toStringArray(raw.benchIds),
    benchLimit: toNumber(raw.benchLimit),
    rosterCount: toNumber(raw.rosterCount),
    submittedAt: toString(raw.submittedAt),
    firstSubmittedAt: toString(raw.firstSubmittedAt),
    updatedAt: toString(raw.updatedAt),
    lockedAt: toString(raw.lockedAt),
    lineupOrigin: normalizeLineupOrigin(raw.lineupOrigin),
    sourceMatchdayNumber: toNullableNumber(raw.sourceMatchdayNumber),
    willAutoCarry: Boolean(raw.willAutoCarry),
    firstSubmissionRequired: Boolean(raw.firstSubmissionRequired),
    revision: toNumber(raw.lineupRevision),
    contentHash: toString(raw.lineupContentHash),
    serverNow: toString(raw.serverNow),
    secondsUntilLock: toNumber(raw.secondsUntilLock),
    canSubmit: raw.canSubmit !== false,
    lockState: raw.lockState === 'locked' ? 'locked' : 'open',
    submissionPolicy:
      raw.submissionPolicy === 'guarded_v1' ? 'guarded_v1' : 'legacy',
    integrityReady: raw.integrityReady !== false,
    directWritesBlocked: Boolean(raw.directWritesBlocked),
    deadlinePolicy:
      raw.deadlinePolicy === 'guarded_v1' ? 'guarded_v1' : 'legacy',
    deadlineOutcome: normalizeDeadlineOutcome(raw.deadlineOutcome),
    deadlineCertified: Boolean(raw.deadlineCertified),
    deadlineProcessedAt: toString(raw.deadlineProcessedAt),
    deadlineEventReady: Boolean(raw.deadlineEventReady),
    immutableAfterLock: Boolean(raw.immutableAfterLock),
    matchdayLineupsFinalizedAt: toString(raw.matchdayLineupsFinalizedAt),
    matchdayLineupLockRevision: toNumber(raw.matchdayLineupLockRevision),
    matchdayLineupLockHash: toString(raw.matchdayLineupLockHash),
  };
}

function normalizeDeadlineOutcome(
  value: unknown,
): LineupContext['deadlineOutcome'] {
  if (
    value === 'processing' ||
    value === 'manager' ||
    value === 'carried' ||
    value === 'missing'
  ) {
    return value;
  }
  return 'open';
}

function normalizeLineupOrigin(
  value: unknown,
): LineupContext['lineupOrigin'] {
  if (
    value === 'manager' ||
    value === 'carried' ||
    value === 'previous_preview' ||
    value === 'empty'
  ) {
    return value;
  }
  return 'empty';
}

function toString(value: unknown) {
  return typeof value === 'string' && value.length > 0 ? value : null;
}

function toStringArray(value: unknown) {
  return Array.isArray(value)
    ? value.filter((item): item is string => typeof item === 'string')
    : [];
}

function toNumber(value: unknown) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : 0;
}

function toNullableNumber(value: unknown) {
  if (value === null || value === undefined || value === '') {
    return null;
  }
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : null;
}

function isMissingRpc(message: string, functionName: string) {
  const normalized = message.toLowerCase();
  return (
    normalized.includes(functionName.toLowerCase()) &&
    (normalized.includes('does not exist') || normalized.includes('not found'))
  );
}

function createRequestId() {
  const template = 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx';
  return template.replace(/[xy]/g, (character) => {
    const random = Math.floor(Math.random() * 16);
    const value = character === 'x' ? random : (random & 0x3) | 0x8;
    return value.toString(16);
  });
}

function translateLineupError(message: string) {
  const normalized = message.toLowerCase();

  if (
    normalized.includes('get_my_lineup_workspace') ||
    normalized.includes('save_team_lineup_guarded_v1') ||
    (normalized.includes('function') && normalized.includes('does not exist'))
  ) {
    return 'Aggiorna prima il database LEGHEVO con i file 075 e 076.';
  }
  if (normalized.includes('revision_conflict')) {
    return 'La formazione è cambiata su un altro dispositivo. Ho aggiornato la distinta: controllala e riprova.';
  }
  if (normalized.includes('formazioni bloccate')) {
    return 'Tempo scaduto: le formazioni sono già bloccate.';
  }
  if (normalized.includes('richiede 1p')) {
    return message;
  }
  if (normalized.includes('11 calciatori')) {
    return 'Devi scegliere esattamente 11 titolari.';
  }
  if (normalized.includes('panchina deve contenere tutti')) {
    return 'Inserisci in panchina tutti i calciatori rimasti, senza duplicati.';
  }
  if (normalized.includes('slot del modulo mantra')) {
    return 'Gli undici scelti non sono compatibili con tutti i ruoli del modulo Mantra.';
  }
  if (normalized.includes('soltanto la tua formazione')) {
    return 'Puoi consegnare soltanto la formazione della tua squadra.';
  }

  return message;
}
