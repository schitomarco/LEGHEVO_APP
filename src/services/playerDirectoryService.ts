import { supabase } from '../lib/supabase';
import type { PlayerDirectoryItem } from '../types';

type RawPlayer = {
  id: string;
  name: string;
  clubName: string;
  shirtNumber: number | null;
  role: string;
  teamId: string | null;
  teamName: string | null;
  purchasePrice: number | null;
  appearances: number | string;
  averageRating: number | string | null;
  averageFantasyScore: number | string | null;
  goals: number | string;
  assists: number | string;
  yellowCards: number | string;
  redCards: number | string;
  lastScores: Array<number | string>;
};

export async function fetchPlayerDirectory(
  leagueId: string,
): Promise<PlayerDirectoryItem[]> {
  if (!supabase) {
    return [];
  }

  const { data, error } = await supabase.rpc('get_league_player_directory', {
    p_league_id: leagueId,
  });

  if (error) {
    throw new Error(translateDirectoryError(error.message));
  }

  const rows = (Array.isArray(data) ? data : []) as unknown as RawPlayer[];
  return rows.map(mapPlayer);
}

function mapPlayer(player: RawPlayer): PlayerDirectoryItem {
  return {
    id: player.id,
    name: player.name,
    clubName: player.clubName,
    shirtNumber: nullableNumber(player.shirtNumber),
    role: player.role || '—',
    teamId: player.teamId,
    teamName: player.teamName,
    purchasePrice: nullableNumber(player.purchasePrice),
    appearances: numberValue(player.appearances),
    averageRating: nullableNumber(player.averageRating),
    averageFantasyScore: nullableNumber(player.averageFantasyScore),
    goals: numberValue(player.goals),
    assists: numberValue(player.assists),
    yellowCards: numberValue(player.yellowCards),
    redCards: numberValue(player.redCards),
    lastScores: (player.lastScores ?? [])
      .map(numberValue)
      .filter((value) => Number.isFinite(value)),
  };
}

function numberValue(value: number | string | null | undefined) {
  const parsed = Number(value ?? 0);
  return Number.isFinite(parsed) ? parsed : 0;
}

function nullableNumber(value: number | string | null | undefined) {
  if (value === null || value === undefined) {
    return null;
  }
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : null;
}

function translateDirectoryError(message: string) {
  const normalized = message.toLowerCase();
  if (
    normalized.includes('get_league_player_directory') ||
    normalized.includes('does not exist')
  ) {
    return 'Aggiorna prima il database LEGHEVO con il file 019.';
  }
  if (normalized.includes('non fai parte')) {
    return 'Non fai parte della lega selezionata.';
  }
  return message;
}
