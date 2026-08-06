import { supabase } from '../lib/supabase';
import type {
  LeagueHistory,
  LeagueHistoryPodiumEntry,
  LeagueHistorySeason,
  LeagueHistoryTitleLeader,
  LeagueSeasonChampion,
  LeagueSummary,
} from '../types';

export async function fetchLeagueHistory(
  leagueId: string,
): Promise<LeagueHistory> {
  if (!supabase) {
    throw new Error('Il collegamento al backend non è configurato.');
  }

  const { data, error } = await supabase.rpc('get_league_history', {
    p_league_id: leagueId,
  });

  if (error) {
    throw new Error(translateHistoryError(error.message));
  }

  return normalizeLeagueHistory(data);
}

export function subscribeToLeagueHistory(
  leagueId: string,
  onChange: () => void,
) {
  if (!supabase) {
    return () => undefined;
  }

  const client = supabase;
  const channel = client
    .channel(`league-history-${leagueId}`)
    .on(
      'postgres_changes',
      {
        event: 'UPDATE',
        schema: 'public',
        table: 'leagues',
      },
      onChange,
    )
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

export function normalizeLeagueHistory(value: unknown): LeagueHistory {
  const raw = asRecord(value);
  const seasons = Array.isArray(raw.seasons)
    ? raw.seasons.map(normalizeSeason)
    : [];
  const titleLeaders = Array.isArray(raw.titleLeaders)
    ? raw.titleLeaders.map(normalizeTitleLeader)
    : [];

  return {
    leagueName: toStringValue(raw.leagueName),
    selectedLeagueId: toStringValue(raw.selectedLeagueId),
    latestLeagueId: toStringValue(raw.latestLeagueId),
    totalSeasons: toNumber(raw.totalSeasons),
    completedSeasons: toNumber(raw.completedSeasons),
    seasons,
    titleLeaders,
  };
}

function normalizeSeason(value: unknown): LeagueHistorySeason {
  const raw = asRecord(value);
  const podium = Array.isArray(raw.podium)
    ? raw.podium.map(normalizePodiumEntry)
    : [];

  return {
    leagueId: toStringValue(raw.leagueId),
    season: toNullableString(raw.season),
    status: normalizeLeagueStatus(raw.status),
    startedAt: toNullableString(raw.startedAt),
    completedAt: toNullableString(raw.completedAt),
    memberCount: toNumber(raw.memberCount),
    fixtureCount: toNumber(raw.fixtureCount),
    officialFixtureCount: toNumber(raw.officialFixtureCount),
    champion: normalizeChampion(raw.champion),
    podium,
    isSelected: Boolean(raw.isSelected),
    isLatest: Boolean(raw.isLatest),
  };
}

function normalizePodiumEntry(value: unknown): LeagueHistoryPodiumEntry {
  const raw = asRecord(value);
  return {
    position: toNumber(raw.position),
    teamId: toStringValue(raw.teamId),
    teamName: toStringValue(raw.teamName),
    managerName: toStringValue(raw.managerName),
    leaguePoints: toNumber(raw.leaguePoints),
    pointsFor: toNumber(raw.pointsFor),
  };
}

function normalizeTitleLeader(value: unknown): LeagueHistoryTitleLeader {
  const raw = asRecord(value);
  return {
    managerId: toStringValue(raw.managerId),
    managerName: toStringValue(raw.managerName),
    titles: toNumber(raw.titles),
    teamNames: Array.isArray(raw.teamNames)
      ? raw.teamNames.filter(
          (teamName): teamName is string => typeof teamName === 'string',
        )
      : [],
  };
}

function normalizeChampion(value: unknown): LeagueSeasonChampion | null {
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
    managerName: toStringValue(raw.managerName),
    leaguePoints: toNumber(raw.leaguePoints),
    pointsFor: toNumber(raw.pointsFor),
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

function translateHistoryError(message: string) {
  const normalized = message.toLowerCase();
  if (
    normalized.includes('get_league_history') ||
    (normalized.includes('function') && normalized.includes('does not exist'))
  ) {
    return 'Aggiorna prima il database LEGHEVO con il file 041.';
  }
  if (normalized.includes('non fai parte')) {
    return 'Non fai parte di questa lega.';
  }
  if (normalized.includes('accesso')) {
    return 'Accedi di nuovo per consultare la storia della lega.';
  }
  return message;
}
