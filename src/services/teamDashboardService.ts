import { supabase } from '../lib/supabase';
import type {
  TeamDashboard,
  TeamDashboardMatch,
  TeamDashboardTransaction,
} from '../types';

type DashboardPayload = {
  teamId: string;
  teamName: string;
  creditsRemaining: number | string;
  startingCredits: number | string;
  creditsSpent: number | string;
  rosterCount: number;
  rosterSize: number;
  memberCount: number;
  teamLimit: number;
  fixtureCount: number;
  competitionStartedAt: string | null;
  position: number;
  played: number;
  won: number;
  drawn: number;
  lost: number;
  goalsFor: number;
  goalsAgainst: number;
  pointsFor: number | string;
  leaguePoints: number;
  nextMatch: TeamDashboardMatch | null;
  lastMatch: TeamDashboardMatch | null;
  recentTransactions: TeamDashboardTransaction[];
};

export async function fetchMyTeamDashboard(
  leagueId: string,
): Promise<TeamDashboard> {
  if (!supabase) {
    throw new Error('Backend non configurato.');
  }

  const { data, error } = await supabase.rpc('get_my_team_dashboard', {
    p_league_id: leagueId,
  });

  if (error) {
    throw new Error(translateDashboardError(error.message));
  }

  const payload = data as DashboardPayload | null;
  if (!payload?.teamId) {
    throw new Error('Il cruscotto della squadra non è disponibile.');
  }

  return {
    ...payload,
    creditsRemaining: Number(payload.creditsRemaining),
    startingCredits: Number(payload.startingCredits),
    creditsSpent: Number(payload.creditsSpent),
    pointsFor: Number(payload.pointsFor),
    recentTransactions: payload.recentTransactions ?? [],
  };
}

export function subscribeToMyTeamDashboard(
  leagueId: string,
  teamId: string,
  onChange: () => void,
) {
  if (!supabase) {
    return () => undefined;
  }

  const client = supabase;
  const channel = client
    .channel(`team-dashboard-${teamId}`)
    .on(
      'postgres_changes',
      {
        event: '*',
        schema: 'public',
        table: 'fantasy_teams',
        filter: `id=eq.${teamId}`,
      },
      onChange,
    )
    .on(
      'postgres_changes',
      {
        event: '*',
        schema: 'public',
        table: 'roster_entries',
        filter: `fantasy_team_id=eq.${teamId}`,
      },
      onChange,
    )
    .on(
      'postgres_changes',
      {
        event: '*',
        schema: 'public',
        table: 'team_transactions',
        filter: `fantasy_team_id=eq.${teamId}`,
      },
      onChange,
    )
    .on(
      'postgres_changes',
      {
        event: 'UPDATE',
        schema: 'public',
        table: 'fantasy_fixtures',
        filter: `league_id=eq.${leagueId}`,
      },
      onChange,
    )
    .subscribe();

  return () => {
    void client.removeChannel(channel);
  };
}

function translateDashboardError(message: string) {
  const normalized = message.toLowerCase();
  if (
    normalized.includes('get_my_team_dashboard') ||
    (normalized.includes('function') && normalized.includes('does not exist'))
  ) {
    return 'Aggiorna prima il database LEGHEVO con il file 027.';
  }
  if (normalized.includes('non fai parte')) {
    return 'Non fai più parte di questa lega.';
  }
  if (normalized.includes('squadra non trovata')) {
    return 'La tua squadra non è ancora disponibile.';
  }
  return message;
}
