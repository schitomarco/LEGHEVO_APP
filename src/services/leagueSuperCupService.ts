import { supabase } from '../lib/supabase';
import type {
  LeagueSummary,
  LeagueSuperCupDecision,
  LeagueSuperCupHistory,
  LeagueSuperCupHistorySeason,
  LeagueSuperCupMatchday,
  LeagueSuperCupQualification,
  LeagueSuperCupState,
  LeagueSuperCupTeam,
  LeagueSuperCupTitleLeader,
} from '../types';

export async function fetchLeagueSuperCup(
  leagueId: string,
): Promise<LeagueSuperCupState> {
  if (!supabase) {
    throw new Error('Il collegamento al backend non è configurato.');
  }

  const refresh = await supabase.rpc('recalculate_league_super_cup', {
    p_league_id: leagueId,
  });

  if (
    refresh.error &&
    !isMissingSuperCupMigration(refresh.error.message)
  ) {
    throw new Error(translateSuperCupError(refresh.error.message));
  }

  let { data, error } = await supabase.rpc(
    'get_league_super_cup_state_v3',
    {
      p_league_id: leagueId,
    },
  );

  if (error && isMissingRpc(error.message, 'get_league_super_cup_state_v3')) {
    const fallbackV2 = await supabase.rpc(
      'get_league_super_cup_state_v2',
      { p_league_id: leagueId },
    );
    data = fallbackV2.data;
    error = fallbackV2.error;
  }

  if (error && isMissingRpc(error.message, 'get_league_super_cup_state_v2')) {
    const fallback = await supabase.rpc('get_league_super_cup_state', {
      p_league_id: leagueId,
    });
    data = fallback.data;
    error = fallback.error;
  }

  if (error) {
    throw new Error(translateSuperCupError(error.message));
  }

  return normalizeLeagueSuperCupState(data);
}

export async function createLeagueSuperCup(
  leagueId: string,
  matchdayNumber: number,
) {
  if (!supabase) {
    return { error: 'Il collegamento al backend non è configurato.' };
  }

  const requestId = createRequestId();
  let { error } = await supabase.rpc(
    'create_league_super_cup_guarded_v1',
    {
      p_league_id: leagueId,
      p_matchday_number: matchdayNumber,
      p_request_id: requestId,
    },
  );

  if (
    error &&
    isMissingRpc(error.message, 'create_league_super_cup_guarded_v1')
  ) {
    const fallback = await supabase.rpc('create_league_super_cup', {
      p_league_id: leagueId,
      p_matchday_number: matchdayNumber,
    });
    error = fallback.error;
  }

  return {
    error: error ? translateSuperCupError(error.message) : undefined,
  };
}

export async function finalizeLeagueSuperCup(leagueId: string) {
  if (!supabase) {
    return { error: 'Il collegamento al backend non è configurato.' };
  }

  const requestId = createRequestId();
  let { error } = await supabase.rpc(
    'finalize_league_super_cup_guarded_v1',
    {
      p_league_id: leagueId,
      p_request_id: requestId,
    },
  );

  if (
    error &&
    isMissingRpc(error.message, 'finalize_league_super_cup_guarded_v1')
  ) {
    const fallback = await supabase.rpc('finalize_league_super_cup', {
      p_league_id: leagueId,
    });
    error = fallback.error;
  }

  return {
    error: error ? translateSuperCupError(error.message) : undefined,
  };
}

export async function fetchLeagueSuperCupHistory(
  leagueId: string,
): Promise<LeagueSuperCupHistory> {
  if (!supabase) {
    throw new Error('Il collegamento al backend non è configurato.');
  }

  const { data, error } = await supabase.rpc(
    'get_league_super_cup_history',
    {
      p_league_id: leagueId,
    },
  );

  if (error) {
    throw new Error(translateSuperCupError(error.message));
  }

  return normalizeLeagueSuperCupHistory(data);
}

export function subscribeToLeagueSuperCup(
  leagueId: string,
  onChange: () => void,
) {
  if (!supabase) {
    return () => undefined;
  }

  const client = supabase;
  const channel = client
    .channel(`league-super-cup-${leagueId}`)
    .on(
      'postgres_changes',
      {
        event: '*',
        schema: 'public',
        table: 'league_super_cups',
        filter: `league_id=eq.${leagueId}`,
      },
      onChange,
    )
    .on(
      'postgres_changes',
      {
        event: '*',
        schema: 'public',
        table: 'league_super_cup_schedule_runs',
        filter: `league_id=eq.${leagueId}`,
      },
      onChange,
    )
    .on(
      'postgres_changes',
      {
        event: '*',
        schema: 'public',
        table: 'league_super_cup_finalization_runs',
        filter: `league_id=eq.${leagueId}`,
      },
      onChange,
    )
    .subscribe();

  return () => {
    void client.removeChannel(channel);
  };
}

export function subscribeToLeagueSuperCupHistory(
  leagueId: string,
  onChange: () => void,
) {
  if (!supabase) {
    return () => undefined;
  }

  const client = supabase;
  const channel = client
    .channel(`league-super-cup-history-${leagueId}`)
    .on(
      'postgres_changes',
      {
        event: '*',
        schema: 'public',
        table: 'league_super_cups',
      },
      onChange,
    )
    .subscribe();

  return () => {
    void client.removeChannel(channel);
  };
}

export function normalizeLeagueSuperCupState(
  value: unknown,
): LeagueSuperCupState {
  const raw = asRecord(value);
  const status = normalizeStatus(raw.status);
  return {
    exists: raw.exists === true,
    leagueId: toStringValue(raw.leagueId),
    superCupId: toNullableString(raw.superCupId),
    status,
    isOwner: raw.isOwner === true,
    eligible: raw.eligible === true,
    canCreate: raw.canCreate === true,
    creationReason: toNullableString(raw.creationReason),
    sourceLeagueId: toNullableString(raw.sourceLeagueId),
    sourceSeason: toNullableString(raw.sourceSeason),
    leagueChampion: normalizeTeam(raw.leagueChampion),
    challenger: normalizeTeam(raw.challenger),
    challengerQualification: normalizeQualification(
      raw.challengerQualification,
    ),
    matchday: normalizeMatchday(raw.matchday),
    startMatchdays: Array.isArray(raw.startMatchdays)
      ? raw.startMatchdays.map(normalizeRequiredMatchday)
      : [],
    homePoints: toNullableNumber(raw.homePoints),
    awayPoints: toNullableNumber(raw.awayPoints),
    homeGoals: toNullableNumber(raw.homeGoals),
    awayGoals: toNullableNumber(raw.awayGoals),
    homeReady: raw.homeReady === true,
    awayReady: raw.awayReady === true,
    homeCountedPlayers: toNumber(raw.homeCountedPlayers),
    awayCountedPlayers: toNumber(raw.awayCountedPlayers),
    decidedBy: normalizeDecision(raw.decidedBy),
    createdAt: toNullableString(raw.createdAt),
    completedAt: toNullableString(raw.completedAt),
    canFinalize: raw.canFinalize === true,
    winner: normalizeTeam(raw.winner),
    runnerUp: normalizeTeam(raw.runnerUp),
    schedulePolicy: raw.schedulePolicy === 'guarded_v1' ? 'guarded_v1' : null,
    scheduleCertified: raw.scheduleCertified === true,
    scheduleRunId: toNullableNumber(raw.scheduleRunId),
    scheduleRequestId: toNullableString(raw.scheduleRequestId),
    scheduleQualifiersHash: toNullableString(raw.scheduleQualifiersHash),
    scheduleHash: toNullableString(raw.scheduleHash),
    scheduleResultHash: toNullableString(raw.scheduleResultHash),
    finalizationPolicy:
      raw.finalizationPolicy === 'guarded_v1' ? 'guarded_v1' : null,
    finalizationCertified: raw.finalizationCertified === true,
    finalizationRunId: toNullableNumber(raw.finalizationRunId),
    finalizationRequestId: toNullableString(raw.finalizationRequestId),
    finalizationSourceMode:
      raw.finalizationSourceMode === 'guarded_v1' ||
      raw.finalizationSourceMode === 'legacy_backfill'
        ? raw.finalizationSourceMode
        : null,
    finalizationInputHash: toNullableString(raw.finalizationInputHash),
    finalizationResultHash: toNullableString(raw.finalizationResultHash),
    finalizationOfficializationRunId: toNullableNumber(
      raw.finalizationOfficializationRunId,
    ),
    finalizationHomeResolutionId: toNullableNumber(
      raw.finalizationHomeResolutionId,
    ),
    finalizationAwayResolutionId: toNullableNumber(
      raw.finalizationAwayResolutionId,
    ),
  };
}

export function normalizeLeagueSuperCupHistory(
  value: unknown,
): LeagueSuperCupHistory {
  const raw = asRecord(value);
  return {
    leagueName: toStringValue(raw.leagueName),
    selectedLeagueId: toStringValue(raw.selectedLeagueId),
    latestLeagueId: toStringValue(raw.latestLeagueId),
    completedSuperCups: toNumber(raw.completedSuperCups),
    activeSuperCups: toNumber(raw.activeSuperCups),
    seasons: Array.isArray(raw.seasons)
      ? raw.seasons.map(normalizeHistorySeason)
      : [],
    titleLeaders: Array.isArray(raw.titleLeaders)
      ? raw.titleLeaders.map(normalizeTitleLeader)
      : [],
  };
}

function normalizeHistorySeason(
  value: unknown,
): LeagueSuperCupHistorySeason {
  const raw = asRecord(value);
  return {
    leagueId: toStringValue(raw.leagueId),
    season: toNullableString(raw.season),
    leagueStatus: normalizeLeagueStatus(raw.leagueStatus),
    superCupExists: raw.superCupExists === true,
    superCupId: toNullableString(raw.superCupId),
    superCupStatus: normalizeStatus(raw.superCupStatus),
    sourceSeason: toNullableString(raw.sourceSeason),
    matchdayNumber: toNumber(raw.matchdayNumber),
    challengerQualification: normalizeQualification(
      raw.challengerQualification,
    ),
    leagueChampion: normalizeTeam(raw.leagueChampion),
    challenger: normalizeTeam(raw.challenger),
    homePoints: toNullableNumber(raw.homePoints),
    awayPoints: toNullableNumber(raw.awayPoints),
    homeGoals: toNullableNumber(raw.homeGoals),
    awayGoals: toNullableNumber(raw.awayGoals),
    decidedBy: normalizeDecision(raw.decidedBy),
    createdAt: toNullableString(raw.createdAt),
    completedAt: toNullableString(raw.completedAt),
    winner: normalizeTeam(raw.winner),
    runnerUp: normalizeTeam(raw.runnerUp),
    isSelected: raw.isSelected === true,
    isLatest: raw.isLatest === true,
  };
}

function normalizeTitleLeader(
  value: unknown,
): LeagueSuperCupTitleLeader {
  const raw = asRecord(value);
  return {
    rank: toNumber(raw.rank),
    managerId: toStringValue(raw.managerId),
    managerName: toStringValue(raw.managerName),
    titles: toNumber(raw.titles),
    teamNames: stringArray(raw.teamNames),
    seasons: stringArray(raw.seasons),
  };
}

function normalizeTeam(value: unknown): LeagueSuperCupTeam | null {
  if (!value || typeof value !== 'object') {
    return null;
  }
  const raw = value as Record<string, unknown>;
  const teamId = toStringValue(raw.teamId);
  if (!teamId) {
    return null;
  }
  return {
    teamId,
    teamName: toStringValue(raw.teamName),
    managerId: toStringValue(raw.managerId),
    managerName: toStringValue(raw.managerName),
    qualification:
      normalizeQualification(raw.qualification) ?? undefined,
  };
}

function normalizeMatchday(
  value: unknown,
): LeagueSuperCupMatchday | null {
  if (!value || typeof value !== 'object') {
    return null;
  }
  return normalizeRequiredMatchday(value);
}

function normalizeRequiredMatchday(value: unknown): LeagueSuperCupMatchday {
  const raw = asRecord(value);
  return {
    id: toStringValue(raw.id),
    number: toNumber(raw.number),
    startsAt: toStringValue(raw.startsAt),
    locksAt: toStringValue(raw.locksAt),
    endsAt: toNullableString(raw.endsAt),
  };
}

function normalizeStatus(
  value: unknown,
): LeagueSuperCupState['status'] {
  if (value === 'active' || value === 'completed') {
    return value;
  }
  return 'not_created';
}

function normalizeLeagueStatus(value: unknown): LeagueSummary['status'] {
  if (
    value === 'draft' ||
    value === 'active' ||
    value === 'completed' ||
    value === 'archived'
  ) {
    return value;
  }
  return 'draft';
}

function normalizeQualification(
  value: unknown,
): LeagueSuperCupQualification | null {
  if (
    value === 'league_champion' ||
    value === 'cup_champion' ||
    value === 'cup_runner_up'
  ) {
    return value;
  }
  return null;
}

function normalizeDecision(value: unknown): LeagueSuperCupDecision | null {
  if (
    value === 'goals' ||
    value === 'fantasy_points' ||
    value === 'league_champion'
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

function toStringValue(value: unknown) {
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

function stringArray(value: unknown) {
  return Array.isArray(value)
    ? value.filter((item): item is string => typeof item === 'string')
    : [];
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

function isMissingSuperCupMigration(message: string) {
  const normalized = message.toLowerCase();
  return (
    normalized.includes('recalculate_league_super_cup') &&
    (normalized.includes('does not exist') ||
      normalized.includes('schema cache'))
  );
}

function translateSuperCupError(message: string) {
  const normalized = message.toLowerCase();
  if (
    (normalized.includes('league_super_cup') ||
      normalized.includes('league_super_cups')) &&
    (normalized.includes('does not exist') ||
      normalized.includes('schema cache'))
  ) {
    return 'Aggiorna prima il database LEGHEVO con il file 045.';
  }
  if (normalized.includes('solo il presidente')) {
    return 'Questa operazione è riservata al Presidente.';
  }
  if (normalized.includes('non fai parte')) {
    return 'Non fai parte di questa lega.';
  }
  if (normalized.includes('giornata scelta')) {
    return 'La giornata scelta non è più disponibile.';
  }
  if (normalized.includes('non ancora terminata')) {
    return 'La giornata reale non è ancora terminata.';
  }
  if (
    normalized.includes('non è ancora ufficializzata integralmente')
  ) {
    return 'La giornata deve essere ufficializzata prima della Supercoppa.';
  }
  if (
    normalized.includes('sostituzioni certificate') ||
    normalized.includes('risoluzioni protette')
  ) {
    return 'Le due formazioni non sono ancora state risolte definitivamente.';
  }
  if (normalized.includes('voti definitivi')) {
    return 'Mancano ancora voti definitivi per la Supercoppa.';
  }
  return message;
}
