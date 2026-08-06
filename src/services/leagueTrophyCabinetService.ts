import { supabase } from '../lib/supabase';
import type {
  LeagueTrophyCabinet,
  LeagueTrophyCabinetTeam,
  LeagueTrophyCompetition,
  LeagueTrophyLeader,
  LeagueTrophyTimelineEntry,
} from '../types';

export async function fetchLeagueTrophyCabinet(
  leagueId: string,
): Promise<LeagueTrophyCabinet> {
  if (!supabase) {
    throw new Error('Il collegamento al backend non è configurato.');
  }

  const { data, error } = await supabase.rpc(
    'get_league_trophy_cabinet',
    {
      p_league_id: leagueId,
    },
  );

  if (error) {
    throw new Error(translateTrophyCabinetError(error.message));
  }

  return normalizeLeagueTrophyCabinet(data);
}

export function subscribeToLeagueTrophyCabinet(
  leagueId: string,
  onChange: () => void,
) {
  if (!supabase) {
    return () => undefined;
  }

  const client = supabase;
  const channel = client
    .channel(`league-trophy-cabinet-${leagueId}`)
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
        table: 'league_cups',
      },
      onChange,
    )
    .on(
      'postgres_changes',
      {
        event: '*',
        schema: 'public',
        table: 'league_super_cups',
      },
      onChange,
    )
    .on(
      'postgres_changes',
      {
        event: 'UPDATE',
        schema: 'public',
        table: 'leagues',
      },
      onChange,
    )
    .subscribe();

  return () => {
    void client.removeChannel(channel);
  };
}

export function normalizeLeagueTrophyCabinet(
  value: unknown,
): LeagueTrophyCabinet {
  const raw = asRecord(value);
  return {
    leagueName: toStringValue(raw.leagueName),
    selectedLeagueId: toStringValue(raw.selectedLeagueId),
    latestLeagueId: toStringValue(raw.latestLeagueId),
    totalTrophies: toNumber(raw.totalTrophies),
    leagueTitles: toNumber(raw.leagueTitles),
    cupTitles: toNumber(raw.cupTitles),
    superCupTitles: toNumber(raw.superCupTitles),
    uniqueWinners: toNumber(raw.uniqueWinners),
    doubles: toNumber(raw.doubles),
    leaders: Array.isArray(raw.leaders)
      ? raw.leaders.map(normalizeLeader)
      : [],
    timeline: Array.isArray(raw.timeline)
      ? raw.timeline.map(normalizeTimelineEntry)
      : [],
  };
}

function normalizeLeader(value: unknown): LeagueTrophyLeader {
  const raw = asRecord(value);
  return {
    rank: toNumber(raw.rank),
    managerId: toStringValue(raw.managerId),
    managerName: toStringValue(raw.managerName),
    totalTrophies: toNumber(raw.totalTrophies),
    leagueTitles: toNumber(raw.leagueTitles),
    cupTitles: toNumber(raw.cupTitles),
    superCupTitles: toNumber(raw.superCupTitles),
    leaguePodiums: toNumber(raw.leaguePodiums),
    cupFinals: toNumber(raw.cupFinals),
    superCupFinals: toNumber(raw.superCupFinals),
    doubles: toNumber(raw.doubles),
    teamNames: toStringArray(raw.teamNames),
    seasons: toStringArray(raw.seasons),
  };
}

function normalizeTimelineEntry(
  value: unknown,
): LeagueTrophyTimelineEntry {
  const raw = asRecord(value);
  return {
    id: toStringValue(raw.id),
    competition: normalizeCompetition(raw.competition),
    leagueId: toStringValue(raw.leagueId),
    season: toNullableString(raw.season),
    sourceSeason: toNullableString(raw.sourceSeason),
    completedAt: toNullableString(raw.completedAt),
    winner: normalizeRequiredTeam(raw.winner),
    runnerUp: normalizeTeam(raw.runnerUp),
  };
}

function normalizeRequiredTeam(value: unknown): LeagueTrophyCabinetTeam {
  return (
    normalizeTeam(value) ?? {
      teamId: '',
      teamName: 'Squadra',
      managerId: '',
      managerName: 'Manager',
    }
  );
}

function normalizeTeam(value: unknown): LeagueTrophyCabinetTeam | null {
  const raw = asRecord(value);
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

function normalizeCompetition(value: unknown): LeagueTrophyCompetition {
  if (value === 'cup' || value === 'super_cup') {
    return value;
  }
  return 'league';
}

function translateTrophyCabinetError(message: string) {
  const normalized = message.toLowerCase();
  if (
    normalized.includes('get_league_trophy_cabinet') ||
    (normalized.includes('function') &&
      normalized.includes('does not exist'))
  ) {
    return 'Aggiorna prima il database LEGHEVO con il file 046.';
  }
  if (normalized.includes('non fai parte')) {
    return 'Non fai parte di questa lega.';
  }
  if (normalized.includes('accesso')) {
    return 'Accedi di nuovo per consultare la bacheca.';
  }
  return message;
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

function toStringArray(value: unknown) {
  return Array.isArray(value)
    ? value.filter((item): item is string => typeof item === 'string')
    : [];
}

function toNumber(value: unknown) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : 0;
}
