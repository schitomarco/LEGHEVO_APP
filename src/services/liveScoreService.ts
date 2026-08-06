import { supabase } from '../lib/supabase';
import type {
  DefenseModifierBreakdown,
  GoalBands,
  LiveMatchCenter,
  LiveMatchStatus,
  LiveTeamScore,
  PlayerLiveScore,
} from '../types';

type RawLivePlayer = {
  athleteId: string;
  name: string;
  role: string;
  slot: number;
  providerRating: number | string | null;
  fantasyScore: number | string | null;
  bonuses: Record<string, number> | null;
  maluses: Record<string, number> | null;
  rawStatistics: Record<string, unknown> | null;
  isFinal: boolean;
  scoreOrigin: 'provider' | 'political' | null;
  isSubstitute: boolean;
  replacedPlayerName: string | null;
  blockedReason:
    | 'awaiting_score'
    | 'limit_reached'
    | 'no_compatible_bench'
    | null;
};

type RawLiveTeam = {
  teamId: string;
  name: string;
  points: number | string | null;
  basePoints: number | string | null;
  defenseModifier: Partial<DefenseModifierBreakdown> | null;
  homeBonus: number | string | null;
  goals: number | null;
  countedPlayers: number;
  ready: boolean;
};

type RawLiveMatch = {
  leagueId: string;
  leagueName: string;
  mode: 'classic' | 'mantra';
  status: LiveMatchStatus;
  fixtureId: string;
  myTeamId: string;
  lineupOrigin: 'manager' | 'carried' | 'missing';
  lineupSourceMatchdayNumber: number | string | null;
  substitutions: {
    used: number | string;
    limit: number | string;
    unavailableStarters: number | string;
    applied: boolean;
  };
  goalMargin: {
    enabled: boolean;
    minimum: number | string;
    applied: boolean;
    homeBonus: number | string;
    awayBonus: number | string;
  };
  goalBands: {
    enabled: boolean;
    thresholds: Array<number | string>;
  };
  matchday: {
    id: string;
    number: number;
    startsAt: string;
    locksAt: string;
    endsAt: string | null;
  };
  home: RawLiveTeam;
  away: RawLiveTeam;
  players: RawLivePlayer[];
};

let liveChannelSequence = 0;

export async function fetchLiveMatchCenter(
  leagueId: string,
): Promise<LiveMatchCenter | null> {
  if (!supabase) {
    return null;
  }

  const { data, error } = await supabase.rpc('get_my_live_match_v6', {
    p_league_id: leagueId,
  });

  if (error) {
    throw new Error(translateLiveError(error.message));
  }

  const row = (Array.isArray(data) ? data[0] : data) as RawLiveMatch | null;
  if (!row) {
    return null;
  }

  return {
    leagueId: row.leagueId,
    leagueName: row.leagueName,
    mode: row.mode,
    status: row.status,
    fixtureId: row.fixtureId,
    myTeamId: row.myTeamId,
    lineupOrigin: normalizeLineupOrigin(row.lineupOrigin),
    lineupSourceMatchdayNumber: toNullableNumber(
      row.lineupSourceMatchdayNumber,
    ),
    substitutions: {
      used: toNumber(row.substitutions?.used),
      limit: toNumber(row.substitutions?.limit, 5),
      unavailableStarters: toNumber(
        row.substitutions?.unavailableStarters,
      ),
      applied: Boolean(row.substitutions?.applied),
    },
    goalMargin: {
      enabled: Boolean(row.goalMargin?.enabled),
      minimum: toNumber(row.goalMargin?.minimum, 4),
      applied: Boolean(row.goalMargin?.applied),
      homeBonus: toNumber(row.goalMargin?.homeBonus),
      awayBonus: toNumber(row.goalMargin?.awayBonus),
    },
    goalBands: {
      enabled: Boolean(row.goalBands?.enabled),
      thresholds: normalizeGoalBands(row.goalBands?.thresholds),
    },
    matchday: row.matchday,
    home: mapTeam(row.home),
    away: mapTeam(row.away),
    players: (row.players ?? []).map(mapPlayer),
  };
}

function normalizeGoalBands(
  value: Array<number | string> | null | undefined,
): GoalBands {
  if (!Array.isArray(value) || value.length !== 6) {
    return [66, 72, 78, 84, 90, 96];
  }
  const parsed = value.map(Number);
  return parsed.every(
    (item, index) =>
      Number.isFinite(item) &&
      item >= 50 &&
      item <= 150 &&
      (index === 0 || item > parsed[index - 1]),
  )
    ? (parsed as GoalBands)
    : [66, 72, 78, 84, 90, 96];
}

function normalizeLineupOrigin(
  value: unknown,
): LiveMatchCenter['lineupOrigin'] {
  return value === 'manager' || value === 'carried'
    ? value
    : 'missing';
}

export function subscribeToLiveMatch(
  leagueId: string,
  onChange: () => void,
) {
  if (!supabase) {
    return () => undefined;
  }

  const client = supabase;
  liveChannelSequence += 1;
  const channelName = [
    'live-match',
    leagueId,
    Date.now().toString(36),
    liveChannelSequence.toString(36),
  ].join('-');
  const channel = client
    .channel(channelName)
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
        table: 'live_fixture_projection_runs',
        filter: `league_id=eq.${leagueId}`,
      },
      onChange,
    )
    .subscribe();

  return () => {
    void client.removeChannel(channel);
  };
}

function mapTeam(team: RawLiveTeam): LiveTeamScore {
  const modifier = team.defenseModifier ?? {};
  return {
    teamId: team.teamId,
    name: team.name,
    points: toNullableNumber(team.points),
    basePoints: toNullableNumber(team.basePoints),
    defenseModifier: {
      enabled: Boolean(modifier.enabled),
      eligible: Boolean(modifier.eligible),
      minimumDefenders: toNumber(modifier.minimumDefenders, 4),
      defenderCount: toNumber(modifier.defenderCount),
      averageRating: toNullableNumber(modifier.averageRating ?? null),
      bonus: toNumber(modifier.bonus),
    },
    homeBonus: toNumber(team.homeBonus),
    goals: team.goals,
    countedPlayers: Number(team.countedPlayers ?? 0),
    ready: Boolean(team.ready),
  };
}

function mapPlayer(player: RawLivePlayer): PlayerLiveScore {
  return {
    id: player.athleteId,
    role: player.role,
    name: player.name,
    status: buildStatus(player),
    score: formatScore(player.fantasyScore),
    highlighted:
      hasPositiveValue(player.bonuses) ||
      Boolean(player.isSubstitute) ||
      player.scoreOrigin === 'political',
    isFinal: player.isFinal,
    scoreOrigin: player.scoreOrigin,
    isSubstitute: player.isSubstitute,
    replacedPlayerName: player.replacedPlayerName,
    blockedReason: player.blockedReason,
  };
}

function formatScore(value: number | string | null) {
  if (value === null || value === undefined) {
    return 'SV';
  }
  return Number(value).toFixed(1).replace('.', ',');
}

function buildStatus(player: RawLivePlayer) {
  const bonuses = player.bonuses ?? {};
  const maluses = player.maluses ?? {};
  const raw = player.rawStatistics ?? {};

  if (
    player.scoreOrigin === 'political' ||
    raw.leghevoPoliticalScore === true
  ) {
    return 'Voto d’ufficio';
  }

  if (player.isSubstitute && player.replacedPlayerName) {
    return `Subentrato per ${player.replacedPlayerName}`;
  }

  if (player.blockedReason === 'limit_reached') {
    return 'SV · limite cambi raggiunto';
  }
  if (player.blockedReason === 'no_compatible_bench') {
    return 'SV · nessuna riserva compatibile';
  }

  if (Number(bonuses.goals ?? 0) > 0) {
    return 'Gol · bonus';
  }
  if (Number(bonuses.assists ?? 0) > 0) {
    return 'Assist · bonus';
  }
  if (Number(bonuses.penalties_saved ?? 0) > 0) {
    return 'Rigore parato';
  }
  if (Number(maluses.missed_penalties ?? 0) > 0) {
    return 'Rigore sbagliato';
  }
  if (Number(maluses.red_cards ?? 0) > 0) {
    return 'Espulsione';
  }
  if (Number(maluses.yellow_cards ?? 0) > 0) {
    return 'Ammonizione';
  }
  if (player.isFinal) {
    return 'Terminata';
  }

  const games =
    typeof raw.games === 'object' && raw.games
      ? (raw.games as Record<string, unknown>)
      : null;
  const minutes = Number(games?.minutes ?? raw.minutes ?? 0);
  return minutes > 0 ? `In campo · ${minutes}'` : 'In attesa';
}

function hasPositiveValue(values: Record<string, number> | null) {
  return Object.values(values ?? {}).some((value) => Number(value) > 0);
}

function toNullableNumber(value: number | string | null) {
  if (value === null || value === undefined) {
    return null;
  }
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : null;
}

function toNumber(
  value: number | string | null | undefined,
  fallback = 0,
) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : fallback;
}

function translateLiveError(message: string) {
  const normalized = message.toLowerCase();
  if (
    normalized.includes('get_my_live_match') ||
    (normalized.includes('function') && normalized.includes('does not exist'))
  ) {
    return 'Aggiorna prima il database LEGHEVO con il file 036.';
  }
  if (normalized.includes('non fai parte')) {
    return 'Non fai parte della lega selezionata.';
  }
  return message;
}
