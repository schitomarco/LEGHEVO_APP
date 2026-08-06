import { supabase } from '../lib/supabase';
import type {
  LeagueCupHistory,
  LeagueCupHistorySeason,
  LeagueCupHistoryTeam,
  LeagueCupHistoryTitleLeader,
  LeagueCupManagerCareer,
  LeagueCupMatchRecord,
  LeagueCupMatchRecordKey,
  LeagueCupTieDecision,
  LeagueSummary,
} from '../types';

const matchRecordKeys: LeagueCupMatchRecordKey[] = [
  'highest_score',
  'biggest_win',
  'highest_total_goals',
];

export async function fetchLeagueCupHistory(
  leagueId: string,
): Promise<LeagueCupHistory> {
  if (!supabase) {
    throw new Error('Il collegamento al backend non è configurato.');
  }

  const { data, error } = await supabase.rpc('get_league_cup_history', {
    p_league_id: leagueId,
  });

  if (error) {
    throw new Error(translateCupHistoryError(error.message));
  }

  return normalizeLeagueCupHistory(data);
}

export function subscribeToLeagueCupHistory(
  leagueId: string,
  onChange: () => void,
) {
  if (!supabase) {
    return () => undefined;
  }

  const client = supabase;
  const channel = client
    .channel(`league-cup-history-${leagueId}`)
    .on(
      'postgres_changes',
      {
        event: '*',
        schema: 'public',
        table: 'league_cups',
      },
      onChange,
    )
    .on(
      'postgres_changes',
      {
        event: '*',
        schema: 'public',
        table: 'league_cup_entries',
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
    .subscribe();

  return () => {
    void client.removeChannel(channel);
  };
}

export function normalizeLeagueCupHistory(value: unknown): LeagueCupHistory {
  const raw = asRecord(value);
  return {
    leagueName: toStringValue(raw.leagueName),
    selectedLeagueId: toStringValue(raw.selectedLeagueId),
    latestLeagueId: toStringValue(raw.latestLeagueId),
    completedCups: toNumber(raw.completedCups),
    activeCups: toNumber(raw.activeCups),
    seasons: Array.isArray(raw.seasons)
      ? raw.seasons.map(normalizeSeason)
      : [],
    titleLeaders: Array.isArray(raw.titleLeaders)
      ? raw.titleLeaders.map(normalizeTitleLeader)
      : [],
    careerLeaders: Array.isArray(raw.careerLeaders)
      ? raw.careerLeaders.map(normalizeCareer)
      : [],
    matchRecords: Array.isArray(raw.matchRecords)
      ? raw.matchRecords
          .map(normalizeMatchRecord)
          .filter((record): record is LeagueCupMatchRecord => Boolean(record))
      : [],
  };
}

function normalizeSeason(value: unknown): LeagueCupHistorySeason {
  const raw = asRecord(value);
  return {
    leagueId: toStringValue(raw.leagueId),
    season: toNullableString(raw.season),
    leagueStatus: normalizeLeagueStatus(raw.leagueStatus),
    cupExists: Boolean(raw.cupExists),
    cupId: toNullableString(raw.cupId),
    cupName: toNullableString(raw.cupName),
    cupStatus: normalizeCupStatus(raw.cupStatus),
    startedAt: toNullableString(raw.startedAt),
    completedAt: toNullableString(raw.completedAt),
    teamCount: toNumber(raw.teamCount),
    roundCount: toNumber(raw.roundCount),
    currentRound: toNumber(raw.currentRound),
    totalTieCount: toNumber(raw.totalTieCount),
    officialTieCount: toNumber(raw.officialTieCount),
    champion: normalizeTeam(raw.champion),
    runnerUp: normalizeTeam(raw.runnerUp),
    isSelected: Boolean(raw.isSelected),
    isLatest: Boolean(raw.isLatest),
  };
}

function normalizeTitleLeader(
  value: unknown,
): LeagueCupHistoryTitleLeader {
  const raw = asRecord(value);
  return {
    managerId: toStringValue(raw.managerId),
    managerName: toStringValue(raw.managerName),
    titles: toNumber(raw.titles),
    finals: toNumber(raw.finals),
    teamNames: stringArray(raw.teamNames),
    seasons: stringArray(raw.seasons),
  };
}

function normalizeCareer(value: unknown): LeagueCupManagerCareer {
  const raw = asRecord(value);
  return {
    rank: toNumber(raw.rank),
    managerId: toStringValue(raw.managerId),
    managerName: toStringValue(raw.managerName),
    participations: toNumber(raw.participations),
    titles: toNumber(raw.titles),
    finals: toNumber(raw.finals),
    tiesPlayed: toNumber(raw.tiesPlayed),
    tiesWon: toNumber(raw.tiesWon),
    winRate: toNumber(raw.winRate),
    teamNames: stringArray(raw.teamNames),
  };
}

function normalizeMatchRecord(value: unknown): LeagueCupMatchRecord | null {
  const raw = asRecord(value);
  if (!isMatchRecordKey(raw.key)) {
    return null;
  }
  return {
    key: raw.key,
    value: toNumber(raw.value),
    tieId: toStringValue(raw.tieId),
    season: toNullableString(raw.season),
    matchdayNumber: toNumber(raw.matchdayNumber),
    roundName: toStringValue(raw.roundName),
    teamId: toStringValue(raw.teamId),
    teamName: toStringValue(raw.teamName),
    managerId: toStringValue(raw.managerId),
    managerName: toStringValue(raw.managerName),
    opponentName: toStringValue(raw.opponentName),
    homeTeamName: toStringValue(raw.homeTeamName),
    awayTeamName: toStringValue(raw.awayTeamName),
    homePoints: toNumber(raw.homePoints),
    awayPoints: toNumber(raw.awayPoints),
    homeGoals: toNumber(raw.homeGoals),
    awayGoals: toNumber(raw.awayGoals),
    decidedBy: normalizeDecision(raw.decidedBy),
  };
}

function normalizeTeam(value: unknown): LeagueCupHistoryTeam | null {
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
  };
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

function normalizeCupStatus(
  value: unknown,
): LeagueCupHistorySeason['cupStatus'] {
  if (value === 'active' || value === 'completed') {
    return value;
  }
  return 'not_created';
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

function isMatchRecordKey(
  value: unknown,
): value is LeagueCupMatchRecordKey {
  return matchRecordKeys.some((key) => key === value);
}

function stringArray(value: unknown) {
  return Array.isArray(value)
    ? value.filter((item): item is string => typeof item === 'string')
    : [];
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
  return typeof value === 'string' && value ? value : null;
}

function toNumber(value: unknown) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : 0;
}

function translateCupHistoryError(message: string) {
  const normalized = message.toLowerCase();
  if (
    normalized.includes('get_league_cup_history') ||
    (normalized.includes('function') && normalized.includes('does not exist'))
  ) {
    return 'Aggiorna prima il database LEGHEVO con il file 044.';
  }
  if (normalized.includes('non fai parte')) {
    return 'Non fai parte di questa lega.';
  }
  if (normalized.includes('accesso')) {
    return 'Accedi di nuovo per consultare la storia della Coppa.';
  }
  return message;
}
