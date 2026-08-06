import { supabase } from '../lib/supabase';
import type {
  LeagueCupPodiumTeam,
  LeagueCupRound,
  LeagueCupRoundStatus,
  LeagueCupStartMatchday,
  LeagueCupState,
  LeagueCupTeam,
  LeagueCupTie,
  LeagueCupTieDecision,
  LeagueCupTieStatus,
} from '../types';

export async function fetchLeagueCup(
  leagueId: string,
): Promise<LeagueCupState> {
  if (!supabase) {
    throw new Error('Supabase non è configurato.');
  }

  const refresh = await supabase.rpc('recalculate_league_cup', {
    p_league_id: leagueId,
  });

  if (refresh.error && !isMissingCupMigration(refresh.error.message)) {
    throw new Error(translateCupError(refresh.error.message));
  }

  let { data, error } = await supabase.rpc('get_league_cup_state_v4', {
    p_league_id: leagueId,
  });

  if (error && isMissingRpc(error.message, 'get_league_cup_state_v4')) {
    const fallbackV3 = await supabase.rpc('get_league_cup_state_v3', {
      p_league_id: leagueId,
    });
    data = fallbackV3.data;
    error = fallbackV3.error;
  }

  if (error && isMissingRpc(error.message, 'get_league_cup_state_v3')) {
    const fallbackV2 = await supabase.rpc('get_league_cup_state_v2', {
      p_league_id: leagueId,
    });
    data = fallbackV2.data;
    error = fallbackV2.error;
  }

  if (error && isMissingRpc(error.message, 'get_league_cup_state_v2')) {
    const fallback = await supabase.rpc('get_league_cup_state', {
      p_league_id: leagueId,
    });
    data = fallback.data;
    error = fallback.error;
  }

  if (error) {
    throw new Error(translateCupError(error.message));
  }

  return normalizeLeagueCupState(data);
}

export async function createLeagueCup(
  leagueId: string,
  startMatchdayNumber: number,
) {
  if (!supabase) {
    return { error: 'Supabase non è configurato.' };
  }

  const requestId = createRequestId();
  let { error } = await supabase.rpc('create_league_cup_guarded_v1', {
    p_league_id: leagueId,
    p_start_matchday_number: startMatchdayNumber,
    p_request_id: requestId,
  });

  if (error && isMissingRpc(error.message, 'create_league_cup_guarded_v1')) {
    const fallback = await supabase.rpc('create_league_cup', {
      p_league_id: leagueId,
      p_start_matchday_number: startMatchdayNumber,
    });
    error = fallback.error;
  }

  return {
    error: error ? translateCupError(error.message) : undefined,
  };
}

export async function finalizeLeagueCupRound(
  leagueId: string,
  roundNumber: number,
) {
  if (!supabase) {
    return { error: 'Supabase non è configurato.' };
  }

  const requestId = createRequestId();
  let { error } = await supabase.rpc(
    'finalize_league_cup_round_guarded_v1',
    {
      p_league_id: leagueId,
      p_round_number: roundNumber,
      p_request_id: requestId,
    },
  );

  if (
    error &&
    isMissingRpc(error.message, 'finalize_league_cup_round_guarded_v1')
  ) {
    const fallback = await supabase.rpc('finalize_league_cup_round', {
      p_league_id: leagueId,
    });
    error = fallback.error;
  }

  return {
    error: error ? translateCupError(error.message) : undefined,
  };
}

export function subscribeToLeagueCup(
  leagueId: string,
  onChange: () => void,
) {
  if (!supabase) {
    return () => undefined;
  }

  const client = supabase;
  const channel = client
    .channel(`league-cup-${leagueId}`)
    .on(
      'postgres_changes',
      {
        event: '*',
        schema: 'public',
        table: 'league_cups',
        filter: `league_id=eq.${leagueId}`,
      },
      onChange,
    )
    .on(
      'postgres_changes',
      {
        event: '*',
        schema: 'public',
        table: 'league_cup_rounds',
      },
      onChange,
    )
    .on(
      'postgres_changes',
      {
        event: '*',
        schema: 'public',
        table: 'league_cup_ties',
      },
      onChange,
    )
    .on(
      'postgres_changes',
      {
        event: '*',
        schema: 'public',
        table: 'league_cup_draw_runs',
        filter: `league_id=eq.${leagueId}`,
      },
      onChange,
    )
    .on(
      'postgres_changes',
      {
        event: '*',
        schema: 'public',
        table: 'league_cup_round_finalization_runs',
        filter: `league_id=eq.${leagueId}`,
      },
      onChange,
    )
    .on(
      'postgres_changes',
      {
        event: '*',
        schema: 'public',
        table: 'league_cup_completion_certificates',
        filter: `league_id=eq.${leagueId}`,
      },
      onChange,
    )
    .subscribe();

  return () => {
    void client.removeChannel(channel);
  };
}

export function normalizeLeagueCupState(value: unknown): LeagueCupState {
  const raw = asRecord(value);
  const exists = raw.exists === true;
  const rawStatus = toNullableString(raw.status);

  return {
    exists,
    leagueId: toString(raw.leagueId),
    cupId: toNullableString(raw.cupId),
    name: toNullableString(raw.name) ?? 'Coppa di Lega',
    status:
      rawStatus === 'active' || rawStatus === 'completed'
        ? rawStatus
        : 'not_created',
    isOwner: raw.isOwner === true,
    canCreate: raw.canCreate === true,
    creationReason: toNullableString(raw.creationReason),
    teamCount: toNumber(raw.teamCount),
    bracketSize: toNumber(raw.bracketSize),
    roundCount: toNumber(raw.roundCount),
    currentRound: Math.max(toNumber(raw.currentRound), exists ? 1 : 0),
    startedAt: toNullableString(raw.startedAt),
    completedAt: toNullableString(raw.completedAt),
    drawSeed: toNullableString(raw.drawSeed),
    drawPolicy: raw.drawPolicy === 'guarded_v1' ? 'guarded_v1' : 'legacy',
    drawCertified: raw.drawCertified === true,
    drawRunId: toNullableId(raw.drawRunId),
    drawRevision: toNumber(raw.drawRevision),
    roundFinalizationPolicy:
      raw.roundFinalizationPolicy === 'guarded_v1'
        ? 'guarded_v1'
        : 'legacy',
    officialRoundCount: toNumber(raw.officialRoundCount),
    certifiedRoundCount: toNumber(raw.certifiedRoundCount),
    roundsCertified: raw.roundsCertified !== false,
    currentRoundOfficializationReady:
      raw.currentRoundOfficializationReady === true,
    lastRoundRunId: toNullableId(raw.lastRoundRunId),
    lastCertifiedRound: toNumber(raw.lastCertifiedRound),
    lastRoundFinalizedAt: toNullableString(raw.lastRoundFinalizedAt),
    completionPolicy:
      raw.completionPolicy === 'certified_v1'
        ? 'certified_v1'
        : 'legacy',
    completionCertified: raw.completionCertified === true,
    completionCertificateId: toNullableId(raw.completionCertificateId),
    completionFingerprint: toNullableString(raw.completionFingerprint),
    completionCertifiedAt: toNullableString(raw.completionCertifiedAt),
    completionFinalizationRunId: toNullableId(
      raw.completionFinalizationRunId,
    ),
    startMatchdays: Array.isArray(raw.startMatchdays)
      ? raw.startMatchdays.map(normalizeStartMatchday)
      : [],
    rounds: Array.isArray(raw.rounds)
      ? raw.rounds.map(normalizeRound)
      : [],
    champion: normalizePodiumTeam(raw.champion),
    runnerUp: normalizePodiumTeam(raw.runnerUp),
    canFinalizeCurrent: raw.canFinalizeCurrent === true,
  };
}

function normalizeStartMatchday(value: unknown): LeagueCupStartMatchday {
  const raw = asRecord(value);
  return {
    id: toString(raw.id),
    number: toNumber(raw.number),
    startsAt: toString(raw.startsAt),
    locksAt: toString(raw.locksAt),
  };
}

function normalizeRound(value: unknown): LeagueCupRound {
  const raw = asRecord(value);
  return {
    id: toString(raw.id),
    number: toNumber(raw.number),
    name: toString(raw.name),
    matchdayId: toString(raw.matchdayId),
    matchdayNumber: toNumber(raw.matchdayNumber),
    startsAt: toString(raw.startsAt),
    locksAt: toString(raw.locksAt),
    endsAt: toNullableString(raw.endsAt),
    status: normalizeRoundStatus(raw.status),
    finalizedAt: toNullableString(raw.finalizedAt),
    ties: Array.isArray(raw.ties) ? raw.ties.map(normalizeTie) : [],
  };
}

function normalizeTie(value: unknown): LeagueCupTie {
  const raw = asRecord(value);
  return {
    id: toString(raw.id),
    position: toNumber(raw.position),
    homeTeam: normalizeTeam(raw.homeTeam),
    awayTeam: normalizeTeam(raw.awayTeam),
    homePoints: toNullableNumber(raw.homePoints),
    awayPoints: toNullableNumber(raw.awayPoints),
    homeGoals: toNullableNumber(raw.homeGoals),
    awayGoals: toNullableNumber(raw.awayGoals),
    homeReady: raw.homeReady === true,
    awayReady: raw.awayReady === true,
    homeCountedPlayers: toNumber(raw.homeCountedPlayers),
    awayCountedPlayers: toNumber(raw.awayCountedPlayers),
    winnerTeamId: toNullableString(raw.winnerTeamId),
    decidedBy: normalizeDecision(raw.decidedBy),
    finalizedAt: toNullableString(raw.finalizedAt),
    status: normalizeTieStatus(raw.status),
  };
}

function normalizeTeam(value: unknown): LeagueCupTeam | null {
  if (!value || typeof value !== 'object') {
    return null;
  }
  const raw = value as Record<string, unknown>;
  return {
    id: toString(raw.id),
    name: toString(raw.name),
    managerName: toString(raw.managerName),
    seed: toNumber(raw.seed),
  };
}

function normalizePodiumTeam(value: unknown): LeagueCupPodiumTeam | null {
  if (!value || typeof value !== 'object') {
    return null;
  }
  const raw = value as Record<string, unknown>;
  return {
    teamId: toString(raw.teamId),
    teamName: toString(raw.teamName),
    managerName: toString(raw.managerName),
  };
}

function normalizeRoundStatus(value: unknown): LeagueCupRoundStatus {
  if (
    value === 'live' ||
    value === 'ready' ||
    value === 'official'
  ) {
    return value;
  }
  return 'scheduled';
}

function normalizeTieStatus(value: unknown): LeagueCupTieStatus {
  if (
    value === 'live' ||
    value === 'ready' ||
    value === 'official' ||
    value === 'bye'
  ) {
    return value;
  }
  return 'waiting';
}

function normalizeDecision(value: unknown): LeagueCupTieDecision | null {
  if (
    value === 'goals' ||
    value === 'fantasy_points' ||
    value === 'seed' ||
    value === 'bye'
  ) {
    return value;
  }
  return null;
}

function asRecord(value: unknown): Record<string, unknown> {
  return value && typeof value === 'object'
    ? (value as Record<string, unknown>)
    : {};
}

function toString(value: unknown) {
  return typeof value === 'string' ? value : '';
}

function toNullableString(value: unknown) {
  return typeof value === 'string' && value.length > 0 ? value : null;
}

function toNullableId(value: unknown) {
  if (typeof value === 'string' && value.length > 0) {
    return value;
  }
  if (typeof value === 'number' && Number.isFinite(value)) {
    return String(value);
  }
  return null;
}

function toNumber(value: unknown) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : 0;
}

function toNullableNumber(value: unknown) {
  if (value === null || value === undefined || value === '') {
    return null;
  }
  return toNumber(value);
}

function createRequestId() {
  const template = 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx';
  return template.replace(/[xy]/g, (character) => {
    const random = Math.floor(Math.random() * 16);
    const value = character === 'x' ? random : (random & 0x3) | 0x8;
    return value.toString(16);
  });
}

function isMissingRpc(message: string, functionName: string) {
  const normalized = message.toLowerCase();
  return (
    normalized.includes(functionName.toLowerCase()) &&
    (normalized.includes('does not exist') ||
      normalized.includes('schema cache'))
  );
}

function isMissingCupMigration(message: string) {
  const normalized = message.toLowerCase();
  return (
    normalized.includes('recalculate_league_cup') &&
    (normalized.includes('does not exist') ||
      normalized.includes('schema cache'))
  );
}

function translateCupError(message: string) {
  const normalized = message.toLowerCase();
  if (
    normalized.includes('league_cup') &&
    (normalized.includes('does not exist') ||
      normalized.includes('schema cache'))
  ) {
    return 'Aggiorna il database LEGHEVO con le migrazioni 085, 086 e 087 della Coppa protetta.';
  }
  if (normalized.includes('solo il presidente')) {
    return 'Questa operazione è riservata al Presidente.';
  }
  if (normalized.includes('non fai parte')) {
    return 'Non fai parte di questa lega.';
  }
  return message;
}
