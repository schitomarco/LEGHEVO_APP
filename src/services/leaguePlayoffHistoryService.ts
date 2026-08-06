import { supabase } from '../lib/supabase';
import type {
  LeagueCupMatchRecord,
  LeagueCupMatchRecordKey,
  LeagueCupTieDecision,
  LeaguePlayoffHistory,
  LeaguePlayoffHistorySeason,
  LeaguePlayoffHistoryTeam,
  LeaguePlayoffHistoryTitleLeader,
  LeaguePlayoffManagerCareer,
  LeagueSummary,
} from '../types';

const matchRecordKeys: LeagueCupMatchRecordKey[] = [
  'highest_score',
  'biggest_win',
  'highest_total_goals',
];

export async function fetchLeaguePlayoffHistory(
  leagueId: string,
): Promise<LeaguePlayoffHistory> {
  if (!supabase) {
    throw new Error('Il collegamento al backend non è configurato.');
  }

  const { data, error } = await supabase.rpc('get_league_playoff_history', {
    p_league_id: leagueId,
  });

  if (error) {
    throw new Error(translatePlayoffHistoryError(error.message));
  }

  return normalizeLeaguePlayoffHistory(data);
}

export function subscribeToLeaguePlayoffHistory(
  leagueId: string,
  onChange: () => void,
) {
  if (!supabase) {
    return () => undefined;
  }

  const client = supabase;
  const channel = client
    .channel(`league-playoff-history-${leagueId}`)
    .on(
      'postgres_changes',
      {
        event: '*',
        schema: 'public',
        table: 'league_playoffs',
      },
      onChange,
    )
    .on(
      'postgres_changes',
      {
        event: '*',
        schema: 'public',
        table: 'league_playoff_entries',
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
    .subscribe();

  return () => {
    void client.removeChannel(channel);
  };
}

export function normalizeLeaguePlayoffHistory(
  value: unknown,
): LeaguePlayoffHistory {
  const raw = asRecord(value);
  return {
    leagueName: toStringValue(raw.leagueName),
    selectedLeagueId: toStringValue(raw.selectedLeagueId),
    latestLeagueId: toStringValue(raw.latestLeagueId),
    completedPlayoffs: toNumber(raw.completedPlayoffs),
    activePlayoffs: toNumber(raw.activePlayoffs),
    configuredPlayoffs: toNumber(raw.configuredPlayoffs),
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

function normalizeSeason(value: unknown): LeaguePlayoffHistorySeason {
  const raw = asRecord(value);
  return {
    leagueId: toStringValue(raw.leagueId),
    season: toNullableString(raw.season),
    leagueStatus: normalizeLeagueStatus(raw.leagueStatus),
    playoffExists: Boolean(raw.playoffExists),
    playoffId: toNullableString(raw.playoffId),
    playoffStatus: normalizePlayoffStatus(raw.playoffStatus),
    configuredAt: toNullableString(raw.configuredAt),
    startedAt: toNullableString(raw.startedAt),
    completedAt: toNullableString(raw.completedAt),
    participantCount: toNumber(raw.participantCount),
    roundCount: toNumber(raw.roundCount),
    currentRound: toNumber(raw.currentRound),
    totalTieCount: toNumber(raw.totalTieCount),
    officialTieCount: toNumber(raw.officialTieCount),
    champion: normalizeTeam(raw.champion),
    runnerUp: normalizeTeam(raw.runnerUp),
    regularSeasonLeader: normalizeTeam(raw.regularSeasonLeader),
    isSelected: Boolean(raw.isSelected),
    isLatest: Boolean(raw.isLatest),
  };
}

function normalizeTitleLeader(
  value: unknown,
): LeaguePlayoffHistoryTitleLeader {
  const raw = asRecord(value);
  return {
    managerId: toStringValue(raw.managerId),
    managerName: toStringValue(raw.managerName),
    titles: toNumber(raw.titles),
    finals: toNumber(raw.finals),
    lowerSeedTitles: toNumber(raw.lowerSeedTitles),
    teamNames: stringArray(raw.teamNames),
    seasons: stringArray(raw.seasons),
  };
}

function normalizeCareer(value: unknown): LeaguePlayoffManagerCareer {
  const raw = asRecord(value);
  return {
    rank: toNumber(raw.rank),
    managerId: toStringValue(raw.managerId),
    managerName: toStringValue(raw.managerName),
    participations: toNumber(raw.participations),
    titles: toNumber(raw.titles),
    finals: toNumber(raw.finals),
    lowerSeedTitles: toNumber(raw.lowerSeedTitles),
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

function normalizeTeam(value: unknown): LeaguePlayoffHistoryTeam | null {
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
    seed: toNullableNumber(raw.seed),
    regularSeasonPosition: toNullableNumber(raw.regularSeasonPosition),
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

function normalizePlayoffStatus(
  value: unknown,
): LeaguePlayoffHistorySeason['playoffStatus'] {
  if (
    value === 'configured' ||
    value === 'active' ||
    value === 'completed'
  ) {
    return value;
  }
  return 'not_configured';
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

function toNullableNumber(value: unknown) {
  if (value === null || value === undefined || value === '') {
    return null;
  }
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : null;
}

function translatePlayoffHistoryError(message: string) {
  const normalized = message.toLowerCase();
  if (
    normalized.includes('get_league_playoff_history') ||
    (normalized.includes('function') && normalized.includes('does not exist'))
  ) {
    return 'Aggiorna prima il database LEGHEVO con il file 048.';
  }
  if (normalized.includes('non fai parte')) {
    return 'Non fai parte di questa lega.';
  }
  if (normalized.includes('accesso')) {
    return 'Accedi di nuovo per consultare la storia dei Playoff.';
  }
  return message;
}
