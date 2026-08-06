import { supabase } from '../lib/supabase';
import { fetchLeagueSeasonState } from './seasonService';
import type {
  LeagueSeasonState,
  LeagueStanding,
  StandingsTiebreaker,
} from '../types';

type StandingRow = {
  position: number;
  fantasy_team_id: string;
  team_name: string;
  played: number;
  won: number;
  drawn: number;
  lost: number;
  goals_for: number;
  goals_against: number;
  goal_difference: number;
  points_for: number | string;
  league_points: number;
  standings_tiebreaker: StandingsTiebreaker;
  head_to_head_played: number;
  head_to_head_points: number;
  head_to_head_goal_difference: number;
  head_to_head_eligible: boolean;
};

export async function fetchLeagueStandings(
  leagueId: string,
): Promise<{
  standings: LeagueStanding[];
  tiebreaker: StandingsTiebreaker;
  season: LeagueSeasonState;
}> {
  if (!supabase) {
    return {
      standings: [],
      tiebreaker: 'goal_difference',
      season: {
        status: 'draft',
        season: null,
        competitionStartedAt: null,
        completedAt: null,
        isOwner: false,
        fixtureCount: 0,
        officialFixtureCount: 0,
        remainingFixtureCount: 0,
        canComplete: false,
        champion: null,
        tiebreaker: 'goal_difference',
        finalStandings: [],
        completionCertified: false,
        completionRunId: null,
        completionStandingsHash: null,
        finalProgressionRunId: null,
        finalMatchdayId: null,
        seasonReadyToComplete: false,
        seasonCompletionCausalStatus: 'blocked',
        seasonCompletionCausalReason:
          'season_completion.progression_chain_incomplete',
        seasonCompletionCausallyCertified: false,
        seasonCompletionAffected: false,
        officialSnapshotProtected: true,
        officialSnapshotPublished: false,
        officialSnapshotHealthy: true,
        officialSnapshotStatus: 'pending',
        officialSnapshotReason: 'season_snapshot.not_published',
        officialSnapshotAffected: false,
        officialSnapshotId: null,
        officialSnapshotHash: null,
        officialPodium: [],
        seasonRolloverProtected: true,
        seasonRolloverCertified: false,
        seasonRolloverHealthy: true,
        seasonRolloverStatus: 'pending',
        seasonRolloverReason: 'season_rollover.not_created',
        seasonRolloverAffected: false,
        seasonRolloverCertificateId: null,
        seasonRolloverLineageHash: null,
        seasonRolloverSourceSnapshotHash: null,
        providerSeasonBootstrapProtected: true,
        providerSeasonBootstrapApplicable: false,
        providerSeasonBootstrapHealthy: true,
        providerSeasonBootstrapAffected: false,
        providerSeasonBootstrapStatus: 'waiting',
        providerSeasonBootstrapReason: 'provider_bootstrap.not_required',
        providerSeasonCatalogReady: true,
        providerSeasonFixturesReady: true,
        providerSeasonBootstrapCertified: false,
        providerSeasonBootstrapCertificateId: null,
        providerSeasonBootstrapHash: null,
        providerCompetitionStartProtected: true,
        providerCompetitionStartApplicable: false,
        providerCompetitionStartHealthy: true,
        providerCompetitionStartAffected: false,
        providerCompetitionStartStatus: 'official',
        providerCompetitionStartReason: 'provider_competition_start.not_required',
        providerCompetitionStartReady: true,
        providerCompetitionStartCertified: false,
        providerCompetitionStartCertificateId: null,
        providerCompetitionStartHash: null,
      },
    };
  }

  const [standingsResponse, season] = await Promise.all([
    supabase.rpc('get_league_standings_v2', {
      p_league_id: leagueId,
    }),
    fetchLeagueSeasonState(leagueId),
  ]);

  if (standingsResponse.error) {
    throw standingsResponse.error;
  }

  const rows = (standingsResponse.data ?? []) as StandingRow[];
  const liveStandings = rows.map((row) => ({
    position: row.position,
    teamId: row.fantasy_team_id,
    teamName: row.team_name,
    played: row.played,
    won: row.won,
    drawn: row.drawn,
    lost: row.lost,
    goalsFor: row.goals_for,
    goalsAgainst: row.goals_against,
    goalDifference: row.goal_difference,
    pointsFor: Number(row.points_for),
    leaguePoints: row.league_points,
    headToHeadPlayed: row.head_to_head_played,
    headToHeadPoints: row.head_to_head_points,
    headToHeadGoalDifference: row.head_to_head_goal_difference,
    headToHeadEligible: row.head_to_head_eligible,
  }));

  return {
    tiebreaker:
      season.status === 'completed' || season.status === 'archived'
        ? season.tiebreaker
        : rows[0]?.standings_tiebreaker ?? 'goal_difference',
    standings:
      (season.status === 'completed' || season.status === 'archived') &&
      season.finalStandings.length > 0
        ? season.finalStandings
        : liveStandings,
    season,
  };
}

export async function recalculateLeagueMatchday(
  leagueId: string,
  matchdayId: string,
) {
  if (!supabase) {
    return { error: 'Il collegamento al backend non è configurato.' };
  }

  const { data, error } = await supabase.rpc(
    'recalculate_league_matchday',
    {
      p_league_id: leagueId,
      p_matchday_id: matchdayId,
    },
  );

  if (error) {
    return { error: translateStandingsError(error.message) };
  }

  return { updated: Number(data ?? 0) };
}

export function subscribeToLeagueResults(
  leagueId: string,
  onChange: () => void,
) {
  if (!supabase) {
    return () => undefined;
  }

  const client = supabase;
  const channel = client
    .channel(`league-results-${leagueId}`)
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
    .on(
      'postgres_changes',
      {
        event: 'UPDATE',
        schema: 'public',
        table: 'leagues',
        filter: `id=eq.${leagueId}`,
      },
      onChange,
    )
    .on(
      'postgres_changes',
      {
        event: '*',
        schema: 'public',
        table: 'league_season_summaries',
        filter: `league_id=eq.${leagueId}`,
      },
      onChange,
    )
    .subscribe();

  return () => {
    void client.removeChannel(channel);
  };
}

function translateStandingsError(message: string) {
  const normalized = message.toLowerCase();
  if (
    normalized.includes('get_league_standings_v2') ||
    normalized.includes('recalculate_league_matchday')
  ) {
    return 'Aggiorna prima il database LEGHEVO con il file 039.';
  }
  return message;
}
