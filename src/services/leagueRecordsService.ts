import { supabase } from '../lib/supabase';
import type {
  LeagueManagerCareer,
  LeagueMatchRecord,
  LeagueMatchRecordKey,
  LeagueRecords,
  LeagueSeasonRecord,
  LeagueSeasonRecordKey,
} from '../types';

const seasonRecordKeys: LeagueSeasonRecordKey[] = [
  'league_points',
  'fantasy_points',
  'wins',
  'goals_for',
  'goal_difference',
];

const matchRecordKeys: LeagueMatchRecordKey[] = [
  'highest_score',
  'biggest_win',
  'highest_total_goals',
];

export async function fetchLeagueRecords(
  leagueId: string,
): Promise<LeagueRecords> {
  if (!supabase) {
    throw new Error('Il collegamento al backend non è configurato.');
  }

  const { data, error } = await supabase.rpc('get_league_records', {
    p_league_id: leagueId,
  });

  if (error) {
    throw new Error(translateRecordsError(error.message));
  }

  return normalizeLeagueRecords(data);
}

export function subscribeToLeagueRecords(
  leagueId: string,
  onChange: () => void,
) {
  if (!supabase) {
    return () => undefined;
  }

  const client = supabase;
  const channel = client
    .channel(`league-records-${leagueId}`)
    .on(
      'postgres_changes',
      {
        event: '*',
        schema: 'public',
        table: 'league_season_summaries',
      },
      onChange,
    )
    .on(
      'postgres_changes',
      {
        event: '*',
        schema: 'public',
        table: 'league_season_rollovers',
      },
      onChange,
    )
    .subscribe();

  return () => {
    void client.removeChannel(channel);
  };
}

export function normalizeLeagueRecords(value: unknown): LeagueRecords {
  const raw = asRecord(value);
  return {
    completedSeasons: toNumber(raw.completedSeasons),
    seasonRecords: Array.isArray(raw.seasonRecords)
      ? raw.seasonRecords
          .map(normalizeSeasonRecord)
          .filter((record): record is LeagueSeasonRecord => Boolean(record))
      : [],
    matchRecords: Array.isArray(raw.matchRecords)
      ? raw.matchRecords
          .map(normalizeMatchRecord)
          .filter((record): record is LeagueMatchRecord => Boolean(record))
      : [],
    careerLeaders: Array.isArray(raw.careerLeaders)
      ? raw.careerLeaders.map(normalizeCareer)
      : [],
  };
}

function normalizeSeasonRecord(value: unknown): LeagueSeasonRecord | null {
  const raw = asRecord(value);
  if (!isSeasonRecordKey(raw.key)) {
    return null;
  }
  return {
    key: raw.key,
    value: toNumber(raw.value),
    season: toNullableString(raw.season),
    teamId: toStringValue(raw.teamId),
    teamName: toStringValue(raw.teamName),
    managerId: toStringValue(raw.managerId),
    managerName: toStringValue(raw.managerName),
  };
}

function normalizeMatchRecord(value: unknown): LeagueMatchRecord | null {
  const raw = asRecord(value);
  if (!isMatchRecordKey(raw.key)) {
    return null;
  }
  return {
    key: raw.key,
    value: toNumber(raw.value),
    fixtureId: toStringValue(raw.fixtureId),
    season: toNullableString(raw.season),
    matchdayNumber: toNumber(raw.matchdayNumber),
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
  };
}

function normalizeCareer(value: unknown): LeagueManagerCareer {
  const raw = asRecord(value);
  return {
    rank: toNumber(raw.rank),
    managerId: toStringValue(raw.managerId),
    managerName: toStringValue(raw.managerName),
    seasons: toNumber(raw.seasons),
    titles: toNumber(raw.titles),
    podiums: toNumber(raw.podiums),
    bestFinish: toNumber(raw.bestFinish),
    played: toNumber(raw.played),
    won: toNumber(raw.won),
    drawn: toNumber(raw.drawn),
    lost: toNumber(raw.lost),
    goalsFor: toNumber(raw.goalsFor),
    goalsAgainst: toNumber(raw.goalsAgainst),
    fantasyPoints: toNumber(raw.fantasyPoints),
    leaguePoints: toNumber(raw.leaguePoints),
    winRate: toNumber(raw.winRate),
    teamNames: Array.isArray(raw.teamNames)
      ? raw.teamNames.filter(
          (teamName): teamName is string => typeof teamName === 'string',
        )
      : [],
  };
}

function isSeasonRecordKey(value: unknown): value is LeagueSeasonRecordKey {
  return seasonRecordKeys.some((key) => key === value);
}

function isMatchRecordKey(value: unknown): value is LeagueMatchRecordKey {
  return matchRecordKeys.some((key) => key === value);
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

function translateRecordsError(message: string) {
  const normalized = message.toLowerCase();
  if (
    normalized.includes('get_league_records') ||
    (normalized.includes('function') && normalized.includes('does not exist'))
  ) {
    return 'Aggiorna prima il database LEGHEVO con il file 042.';
  }
  if (normalized.includes('non fai parte')) {
    return 'Non fai parte di questa lega.';
  }
  if (normalized.includes('accesso')) {
    return 'Accedi di nuovo per consultare i record della lega.';
  }
  return message;
}
