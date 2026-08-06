import { supabase } from '../lib/supabase';
import type { LeagueMode, RosterPlayer } from '../types';

type RosterEntryRow = {
  athlete_id: string;
  purchase_price: number;
};

type AthleteRow = {
  id: string;
  first_name: string | null;
  last_name: string;
  club_name: string;
  shirt_number: number | null;
};

type RoleRow = {
  athlete_id: string;
  role_code: string;
};

export async function fetchTeamRoster(
  fantasyTeamId: string,
  mode: LeagueMode,
): Promise<RosterPlayer[]> {
  if (!supabase) {
    return [];
  }

  const { data: rosterData, error: rosterError } = await supabase
    .from('roster_entries')
    .select('athlete_id, purchase_price')
    .eq('fantasy_team_id', fantasyTeamId)
    .is('released_at', null)
    .order('acquired_at', { ascending: true });

  if (rosterError) {
    throw rosterError;
  }

  const entries = (rosterData ?? []) as RosterEntryRow[];
  if (entries.length === 0) {
    return [];
  }

  const athleteIds = entries.map((entry) => entry.athlete_id);
  const [athletesResponse, rolesResponse] = await Promise.all([
    supabase
      .from('athletes')
      .select('id, first_name, last_name, club_name, shirt_number')
      .in('id', athleteIds),
    supabase
      .from('athlete_roles')
      .select('athlete_id, role_code')
      .eq('mode', mode)
      .in('athlete_id', athleteIds),
  ]);

  if (athletesResponse.error) {
    throw athletesResponse.error;
  }
  if (rolesResponse.error) {
    throw rolesResponse.error;
  }

  const athletes = (athletesResponse.data ?? []) as AthleteRow[];
  const roles = (rolesResponse.data ?? []) as RoleRow[];

  return entries
    .map((entry) => {
      const athlete = athletes.find((item) => item.id === entry.athlete_id);
      if (!athlete) {
        return null;
      }

      const fullName = [athlete.first_name, athlete.last_name]
        .filter(Boolean)
        .join(' ');

      return {
        id: athlete.id,
        name: fullName || athlete.last_name,
        clubName: athlete.club_name,
        shirtNumber: athlete.shirt_number,
        role:
          roles
            .filter((role) => role.athlete_id === athlete.id)
            .map((role) => role.role_code)
            .join('/') || '—',
        purchasePrice: entry.purchase_price,
      } satisfies RosterPlayer;
    })
    .filter((player): player is RosterPlayer => Boolean(player))
    .sort(
      (left, right) =>
        roleOrder(left.role) - roleOrder(right.role) ||
        left.name.localeCompare(right.name),
    );
}

function roleOrder(role: string) {
  if (role === 'P' || role.includes('Por')) return 0;
  if (role === 'D' || role.startsWith('D')) return 1;
  if (role === 'C' || role === 'M') return 2;
  return 3;
}
