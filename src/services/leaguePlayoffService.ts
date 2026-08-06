import { supabase } from '../lib/supabase';
import type {
  LeagueCupPodiumTeam,
  LeagueCupRound,
  LeagueCupRoundStatus,
  LeagueCupStartMatchday,
  LeagueCupTeam,
  LeagueCupTie,
  LeagueCupTieDecision,
  LeagueCupTieStatus,
  LeaguePlayoffState,
  LeaguePlayoffStatus,
} from '../types';

export async function fetchLeaguePlayoffs(
  leagueId: string,
): Promise<LeaguePlayoffState> {
  if (!supabase) {
    throw new Error('Supabase non è configurato.');
  }

  const refresh = await supabase.rpc('recalculate_league_playoffs', {
    p_league_id: leagueId,
  });

  if (refresh.error && !isMissingMigration(refresh.error.message)) {
    throw new Error(translatePlayoffError(refresh.error.message));
  }

  let { data, error } = await supabase.rpc('get_league_playoff_state_v5', {
    p_league_id: leagueId,
  });

  if (error && isMissingRpc(error.message, 'get_league_playoff_state_v5')) {
    const v4Fallback = await supabase.rpc('get_league_playoff_state_v4', {
      p_league_id: leagueId,
    });
    data = v4Fallback.data;
    error = v4Fallback.error;
  }

  if (error && isMissingRpc(error.message, 'get_league_playoff_state_v4')) {
    const v3Fallback = await supabase.rpc('get_league_playoff_state_v3', {
      p_league_id: leagueId,
    });
    data = v3Fallback.data;
    error = v3Fallback.error;
  }

  if (error && isMissingRpc(error.message, 'get_league_playoff_state_v3')) {
    const v2Fallback = await supabase.rpc('get_league_playoff_state_v2', {
      p_league_id: leagueId,
    });
    data = v2Fallback.data;
    error = v2Fallback.error;
  }

  if (error && isMissingRpc(error.message, 'get_league_playoff_state_v2')) {
    const fallback = await supabase.rpc('get_league_playoff_state', {
      p_league_id: leagueId,
    });
    data = fallback.data;
    error = fallback.error;
  }

  if (error) {
    throw new Error(translatePlayoffError(error.message));
  }

  return normalizeLeaguePlayoffState(data);
}

export async function configureLeaguePlayoffs(
  leagueId: string,
  participantCount: 4 | 8,
) {
  if (!supabase) {
    return { error: 'Supabase non è configurato.' };
  }

  const requestId = createRequestId();
  let { error } = await supabase.rpc(
    'configure_league_playoffs_guarded_v1',
    {
      p_league_id: leagueId,
      p_participant_count: participantCount,
      p_request_id: requestId,
    },
  );

  if (
    error &&
    isMissingRpc(error.message, 'configure_league_playoffs_guarded_v1')
  ) {
    const fallback = await supabase.rpc('configure_league_playoffs', {
      p_league_id: leagueId,
      p_participant_count: participantCount,
    });
    error = fallback.error;
  }

  return {
    error: error ? translatePlayoffError(error.message) : undefined,
  };
}

export async function startLeaguePlayoffs(
  leagueId: string,
  startMatchdayNumber: number,
) {
  if (!supabase) {
    return { error: 'Supabase non è configurato.' };
  }

  const requestId = createRequestId();
  let { error } = await supabase.rpc('start_league_playoffs_guarded_v1', {
    p_league_id: leagueId,
    p_start_matchday_number: startMatchdayNumber,
    p_request_id: requestId,
  });

  if (error && isMissingRpc(error.message, 'start_league_playoffs_guarded_v1')) {
    const fallback = await supabase.rpc('start_league_playoffs', {
      p_league_id: leagueId,
      p_start_matchday_number: startMatchdayNumber,
    });
    error = fallback.error;
  }

  return {
    error: error ? translatePlayoffError(error.message) : undefined,
  };
}

export async function finalizeLeaguePlayoffRound(
  leagueId: string,
  roundNumber: number,
) {
  if (!supabase) {
    return { error: 'Supabase non è configurato.' };
  }

  const requestId = createRequestId();
  let { error } = await supabase.rpc(
    'finalize_league_playoff_round_guarded_v1',
    {
      p_league_id: leagueId,
      p_round_number: roundNumber,
      p_request_id: requestId,
    },
  );

  if (
    error &&
    isMissingRpc(error.message, 'finalize_league_playoff_round_guarded_v1')
  ) {
    const fallback = await supabase.rpc('finalize_league_playoff_round', {
      p_league_id: leagueId,
    });
    error = fallback.error;
  }

  return {
    error: error ? translatePlayoffError(error.message) : undefined,
  };
}

export function subscribeToLeaguePlayoffs(
  leagueId: string,
  onChange: () => void,
) {
  if (!supabase) {
    return () => undefined;
  }

  const client = supabase;
  const channel = client
    .channel(`league-playoffs-${leagueId}`)
    .on(
      'postgres_changes',
      {
        event: '*',
        schema: 'public',
        table: 'league_playoffs',
        filter: `league_id=eq.${leagueId}`,
      },
      onChange,
    )
    .on(
      'postgres_changes',
      {
        event: '*',
        schema: 'public',
        table: 'league_playoff_rounds',
      },
      onChange,
    )
    .on(
      'postgres_changes',
      {
        event: '*',
        schema: 'public',
        table: 'league_playoff_ties',
      },
      onChange,
    )
    .on(
      'postgres_changes',
      {
        event: '*',
        schema: 'public',
        table: 'league_playoff_configuration_runs',
        filter: `league_id=eq.${leagueId}`,
      },
      onChange,
    )
    .on(
      'postgres_changes',
      {
        event: '*',
        schema: 'public',
        table: 'league_playoff_start_runs',
        filter: `league_id=eq.${leagueId}`,
      },
      onChange,
    )
    .on(
      'postgres_changes',
      {
        event: '*',
        schema: 'public',
        table: 'league_playoff_round_finalization_runs',
        filter: `league_id=eq.${leagueId}`,
      },
      onChange,
    )
    .on(
      'postgres_changes',
      {
        event: '*',
        schema: 'public',
        table: 'league_playoff_completion_certificates',
        filter: `league_id=eq.${leagueId}`,
      },
      onChange,
    )
    .subscribe();

  return () => {
    void client.removeChannel(channel);
  };
}

export function normalizeLeaguePlayoffState(
  value: unknown,
): LeaguePlayoffState {
  const raw = asRecord(value);
  const status = normalizeStatus(raw.status);
  const participantCount = toNumber(raw.participantCount) === 8 ? 8 : 4;

  return {
    exists: raw.exists === true,
    leagueId: toString(raw.leagueId),
    playoffId: toNullableString(raw.playoffId),
    status,
    isOwner: raw.isOwner === true,
    canConfigure: raw.canConfigure === true,
    canStart: raw.canStart === true,
    actionReason: toNullableString(raw.actionReason),
    participantCount,
    roundCount: toNumber(raw.roundCount),
    currentRound: toNumber(raw.currentRound),
    regularSeasonReady: raw.regularSeasonReady === true,
    configuredAt: toNullableString(raw.configuredAt),
    startedAt: toNullableString(raw.startedAt),
    completedAt: toNullableString(raw.completedAt),
    configurationPolicy:
      raw.configurationPolicy === 'guarded_v1' ? 'guarded_v1' : 'legacy',
    configurationCertified: raw.configurationCertified === true,
    configurationRunId: toNullableNumber(raw.configurationRunId),
    configurationRequestId: toNullableString(raw.configurationRequestId),
    configurationSourceMode:
      raw.configurationSourceMode === 'guarded_v1' ||
      raw.configurationSourceMode === 'legacy_backfill'
        ? raw.configurationSourceMode
        : null,
    configurationHash: toNullableString(raw.configurationHash),
    configurationResultHash: toNullableString(raw.configurationResultHash),
    configurationCertifiedAt: toNullableString(
      raw.configurationCertifiedAt,
    ),
    startPolicy: raw.startPolicy === 'guarded_v1' ? 'guarded_v1' : 'legacy',
    startCertified: raw.startCertified === true,
    startRunId: toNullableNumber(raw.startRunId),
    startRequestId: toNullableString(raw.startRequestId),
    startSourceMode:
      raw.startSourceMode === 'guarded_v1' ||
      raw.startSourceMode === 'legacy_backfill'
        ? raw.startSourceMode
        : null,
    startMatchdayNumber: toNullableNumber(raw.startMatchdayNumber),
    startQualificationSourceHash: toNullableString(
      raw.startQualificationSourceHash,
    ),
    startQualificationHash: toNullableString(raw.startQualificationHash),
    startScheduleHash: toNullableString(raw.startScheduleHash),
    startOpeningBracketHash: toNullableString(raw.startOpeningBracketHash),
    startResultHash: toNullableString(raw.startResultHash),
    startCertifiedAt: toNullableString(raw.startCertifiedAt),
    roundFinalizationPolicy:
      raw.roundFinalizationPolicy === 'guarded_v1'
        ? 'guarded_v1'
        : 'legacy',
    officialRoundCount: toNumber(raw.officialRoundCount),
    certifiedRoundCount: toNumber(raw.certifiedRoundCount),
    roundsCertified: raw.roundsCertified === true,
    currentRoundOfficializationReady:
      raw.currentRoundOfficializationReady === true,
    lastRoundRunId: toNullableNumber(raw.lastRoundRunId),
    lastCertifiedRound: toNumber(raw.lastCertifiedRound),
    lastRoundFinalizedAt: toNullableString(raw.lastRoundFinalizedAt),
    completionPolicy:
      raw.completionPolicy === 'certified_v1' ? 'certified_v1' : 'legacy',
    completionCertified: raw.completionCertified === true,
    completionCertificateId: toNullableNumber(raw.completionCertificateId),
    completionFingerprint: toNullableString(raw.completionFingerprint),
    completionCertifiedAt: toNullableString(raw.completionCertifiedAt),
    completionFinalizationRunId: toNullableNumber(
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

function normalizeStatus(value: unknown): LeaguePlayoffStatus {
  if (
    value === 'configured' ||
    value === 'active' ||
    value === 'completed'
  ) {
    return value;
  }
  return 'not_configured';
}

function normalizeRoundStatus(value: unknown): LeagueCupRoundStatus {
  if (value === 'live' || value === 'ready' || value === 'official') {
    return value;
  }
  return 'scheduled';
}

function normalizeTieStatus(value: unknown): LeagueCupTieStatus {
  if (value === 'live' || value === 'ready' || value === 'official') {
    return value;
  }
  return 'waiting';
}

function normalizeDecision(value: unknown): LeagueCupTieDecision | null {
  if (
    value === 'goals' ||
    value === 'fantasy_points' ||
    value === 'seed'
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

function isMissingMigration(message: string) {
  const normalized = message.toLowerCase();
  return (
    normalized.includes('league_playoff') &&
    (normalized.includes('does not exist') ||
      normalized.includes('schema cache'))
  );
}

function translatePlayoffError(message: string) {
  const normalized = message.toLowerCase();
  if (isMissingMigration(message)) {
    return 'Aggiorna prima il database LEGHEVO con le migrazioni 047, 090, 091, 092 e 093 dei Playoff protetti.';
  }
  if (normalized.includes('solo il presidente')) {
    return 'Questa operazione è riservata al Presidente.';
  }
  if (normalized.includes('stagione regolare')) {
    return 'Prima devono essere ufficiali tutte le partite della stagione regolare.';
  }
  if (normalized.includes('giornate future')) {
    return message;
  }
  if (normalized.includes('non fai parte')) {
    return 'Non fai parte di questa lega.';
  }
  return message;
}
