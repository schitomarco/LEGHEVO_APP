import { supabase } from '../lib/supabase';
import type {
  LeagueMatchupCenter,
  MatchupAllTimeRecord,
  MatchupFixture,
  MatchupFixtureStatus,
  MatchupFormResult,
  MatchupLineupStatus,
  MatchupMeeting,
  MatchupRecord,
  MatchupTeam,
} from '../types';

export async function fetchLeagueMatchupCenter(
  leagueId: string,
): Promise<LeagueMatchupCenter> {
  if (!supabase) {
    throw new Error('Il collegamento al backend non è configurato.');
  }

  const { data, error } = await supabase.rpc('get_league_matchup_center', {
    p_league_id: leagueId,
  });

  if (error) {
    throw new Error(translateMatchupError(error.message));
  }

  return normalizeMatchupCenter(data);
}

export function subscribeToLeagueMatchup(
  leagueId: string,
  teamIds: string[],
  onChange: () => void,
) {
  if (!supabase) {
    return () => undefined;
  }

  const client = supabase;
  const channel = client
    .channel(`league-matchup-${leagueId}-${teamIds.join('-')}`)
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
        event: 'UPDATE',
        schema: 'public',
        table: 'leagues',
        filter: `id=eq.${leagueId}`,
      },
      onChange,
    );

  teamIds.forEach((teamId) => {
    channel.on(
      'postgres_changes',
      {
        event: '*',
        schema: 'public',
        table: 'lineups',
        filter: `fantasy_team_id=eq.${teamId}`,
      },
      onChange,
    );
  });

  channel.subscribe();

  return () => {
    void client.removeChannel(channel);
  };
}

export function normalizeMatchupCenter(value: unknown): LeagueMatchupCenter {
  const raw = asRecord(value);
  return {
    leagueId: toStringValue(raw.leagueId),
    leagueName: toStringValue(raw.leagueName),
    season: toNullableString(raw.season),
    generatedAt: toStringValue(raw.generatedAt),
    myTeam: normalizeTeam(raw.myTeam),
    opponent: raw.opponent ? normalizeTeam(raw.opponent) : null,
    fixture: raw.fixture ? normalizeFixture(raw.fixture) : null,
    currentSeason: normalizeRecord(raw.currentSeason),
    allTime: normalizeAllTimeRecord(raw.allTime),
    lastMeetings: Array.isArray(raw.lastMeetings)
      ? raw.lastMeetings.map(normalizeMeeting)
      : [],
  };
}

function normalizeTeam(value: unknown): MatchupTeam {
  const raw = asRecord(value);
  return {
    id: toStringValue(raw.id),
    name: toStringValue(raw.name),
    managerName: toStringValue(raw.managerName) || 'Manager',
    position: toNumber(raw.position),
    played: toNumber(raw.played),
    won: toNumber(raw.won),
    drawn: toNumber(raw.drawn),
    lost: toNumber(raw.lost),
    goalsFor: toNumber(raw.goalsFor),
    goalsAgainst: toNumber(raw.goalsAgainst),
    pointsFor: toNumber(raw.pointsFor),
    leaguePoints: toNumber(raw.leaguePoints),
    recentForm: Array.isArray(raw.recentForm)
      ? raw.recentForm.filter(isFormResult)
      : [],
    unbeatenStreak: toNumber(raw.unbeatenStreak),
  };
}

function normalizeFixture(value: unknown): MatchupFixture {
  const raw = asRecord(value);
  return {
    id: toStringValue(raw.id),
    matchdayId: toStringValue(raw.matchdayId),
    matchdayNumber: toNumber(raw.matchdayNumber),
    startsAt: toStringValue(raw.startsAt),
    locksAt: toStringValue(raw.locksAt),
    endsAt: toNullableString(raw.endsAt),
    status: normalizeFixtureStatus(raw.status),
    homeTeamId: toStringValue(raw.homeTeamId),
    awayTeamId: toStringValue(raw.awayTeamId),
    myHome: Boolean(raw.myHome),
    myPoints: toNullableNumber(raw.myPoints),
    opponentPoints: toNullableNumber(raw.opponentPoints),
    myGoals: toNullableNumber(raw.myGoals),
    opponentGoals: toNullableNumber(raw.opponentGoals),
    myLineupStatus: normalizeLineupStatus(raw.myLineupStatus),
    opponentLineupStatus: normalizeLineupStatus(raw.opponentLineupStatus),
    lineupsLocked: Boolean(raw.lineupsLocked),
  };
}

function normalizeRecord(value: unknown): MatchupRecord {
  const raw = asRecord(value);
  return {
    played: toNumber(raw.played),
    myWins: toNumber(raw.myWins),
    draws: toNumber(raw.draws),
    opponentWins: toNumber(raw.opponentWins),
    myGoals: toNumber(raw.myGoals),
    opponentGoals: toNumber(raw.opponentGoals),
    myPoints: toNumber(raw.myPoints),
    opponentPoints: toNumber(raw.opponentPoints),
  };
}

function normalizeAllTimeRecord(value: unknown): MatchupAllTimeRecord {
  const raw = asRecord(value);
  return {
    ...normalizeRecord(raw),
    seasons: toNumber(raw.seasons),
    leader:
      raw.leader === 'me' || raw.leader === 'opponent'
        ? raw.leader
        : 'level',
  };
}

function normalizeMeeting(value: unknown): MatchupMeeting {
  const raw = asRecord(value);
  return {
    fixtureId: toStringValue(raw.fixtureId),
    leagueId: toStringValue(raw.leagueId),
    season: toNullableString(raw.season),
    matchdayNumber: toNumber(raw.matchdayNumber),
    startsAt: toStringValue(raw.startsAt),
    homeTeamName: toStringValue(raw.homeTeamName),
    awayTeamName: toStringValue(raw.awayTeamName),
    myHome: Boolean(raw.myHome),
    myPoints: toNumber(raw.myPoints),
    opponentPoints: toNumber(raw.opponentPoints),
    myGoals: toNumber(raw.myGoals),
    opponentGoals: toNumber(raw.opponentGoals),
    outcome: isFormResult(raw.outcome) ? raw.outcome : 'D',
  };
}

function normalizeFixtureStatus(value: unknown): MatchupFixtureStatus {
  return value === 'live' || value === 'pending' || value === 'final'
    ? value
    : 'upcoming';
}

function normalizeLineupStatus(value: unknown): MatchupLineupStatus {
  return value === 'submitted' ||
    value === 'carried' ||
    value === 'draft'
    ? value
    : 'missing';
}

function isFormResult(value: unknown): value is MatchupFormResult {
  return value === 'W' || value === 'D' || value === 'L';
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
  return toNumber(value);
}

function translateMatchupError(message: string) {
  const normalized = message.toLowerCase();
  if (
    normalized.includes('get_league_matchup_center') ||
    (normalized.includes('function') && normalized.includes('does not exist'))
  ) {
    return 'Aggiorna prima il database LEGHEVO con il file 054.';
  }
  if (normalized.includes('non fai parte')) {
    return 'Non fai più parte di questa lega.';
  }
  if (normalized.includes('squadra non è ancora disponibile')) {
    return 'La tua squadra non è ancora disponibile.';
  }
  if (normalized.includes('accesso')) {
    return 'Accedi di nuovo per aprire il Centro Sfida.';
  }
  return message;
}
