import { useCallback, useEffect, useState } from 'react';
import {
  fetchLeagueStandings,
  subscribeToLeagueResults,
} from '../services/standingsService';
import type {
  LeagueSeasonState,
  LeagueStanding,
  StandingsTiebreaker,
} from '../types';

const demoStandings: LeagueStanding[] = [
  {
    position: 1,
    teamId: 'demo-team-2',
    teamName: 'Tiki Taka Boom',
    played: 6,
    won: 5,
    drawn: 0,
    lost: 1,
    goalsFor: 13,
    goalsAgainst: 6,
    goalDifference: 7,
    pointsFor: 443.5,
    leaguePoints: 15,
    headToHeadPlayed: 0,
    headToHeadPoints: 0,
    headToHeadGoalDifference: 0,
    headToHeadEligible: false,
  },
  {
    position: 2,
    teamId: 'demo-team',
    teamName: 'Diavoli del Sud',
    played: 6,
    won: 4,
    drawn: 1,
    lost: 1,
    goalsFor: 12,
    goalsAgainst: 7,
    goalDifference: 5,
    pointsFor: 438,
    leaguePoints: 13,
    headToHeadPlayed: 0,
    headToHeadPoints: 0,
    headToHeadGoalDifference: 0,
    headToHeadEligible: false,
  },
  {
    position: 3,
    teamId: 'demo-team-4',
    teamName: 'Real Colizzati',
    played: 6,
    won: 4,
    drawn: 0,
    lost: 2,
    goalsFor: 11,
    goalsAgainst: 8,
    goalDifference: 3,
    pointsFor: 431.5,
    leaguePoints: 12,
    headToHeadPlayed: 0,
    headToHeadPoints: 0,
    headToHeadGoalDifference: 0,
    headToHeadEligible: false,
  },
  {
    position: 4,
    teamId: 'demo-team-3',
    teamName: 'Atletico Ma Non Troppo',
    played: 6,
    won: 3,
    drawn: 1,
    lost: 2,
    goalsFor: 10,
    goalsAgainst: 9,
    goalDifference: 1,
    pointsFor: 425,
    leaguePoints: 10,
    headToHeadPlayed: 0,
    headToHeadPoints: 0,
    headToHeadGoalDifference: 0,
    headToHeadEligible: false,
  },
  {
    position: 5,
    teamId: 'demo-team-5',
    teamName: 'FC Birre Medie',
    played: 6,
    won: 2,
    drawn: 1,
    lost: 3,
    goalsFor: 8,
    goalsAgainst: 10,
    goalDifference: -2,
    pointsFor: 412,
    leaguePoints: 7,
    headToHeadPlayed: 0,
    headToHeadPoints: 0,
    headToHeadGoalDifference: 0,
    headToHeadEligible: false,
  },
  {
    position: 6,
    teamId: 'demo-team-6',
    teamName: 'Scarsenal',
    played: 6,
    won: 2,
    drawn: 0,
    lost: 4,
    goalsFor: 7,
    goalsAgainst: 11,
    goalDifference: -4,
    pointsFor: 404.5,
    leaguePoints: 6,
    headToHeadPlayed: 0,
    headToHeadPoints: 0,
    headToHeadGoalDifference: 0,
    headToHeadEligible: false,
  },
  {
    position: 7,
    teamId: 'demo-team-7',
    teamName: 'Borussia Porcmund',
    played: 6,
    won: 1,
    drawn: 1,
    lost: 4,
    goalsFor: 6,
    goalsAgainst: 12,
    goalDifference: -6,
    pointsFor: 396,
    leaguePoints: 4,
    headToHeadPlayed: 0,
    headToHeadPoints: 0,
    headToHeadGoalDifference: 0,
    headToHeadEligible: false,
  },
  {
    position: 8,
    teamId: 'demo-team-8',
    teamName: 'Mai Una Gioia',
    played: 6,
    won: 0,
    drawn: 0,
    lost: 6,
    goalsFor: 4,
    goalsAgainst: 18,
    goalDifference: -14,
    pointsFor: 374.5,
    leaguePoints: 0,
    headToHeadPlayed: 0,
    headToHeadPoints: 0,
    headToHeadGoalDifference: 0,
    headToHeadEligible: false,
  },
];

const demoSeason: LeagueSeasonState = {
  status: 'active',
  season: '2026',
  competitionStartedAt: '2026-09-01T18:00:00Z',
  completedAt: null,
  isOwner: true,
  fixtureCount: 56,
  officialFixtureCount: 4,
  remainingFixtureCount: 52,
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
  seasonCompletionCausalReason: 'season_completion.progression_chain_incomplete',
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
};

export function useLeagueStandings(
  leagueId: string | null,
  isDemo: boolean,
) {
  const [standings, setStandings] = useState<LeagueStanding[]>([]);
  const [tiebreaker, setTiebreaker] = useState<StandingsTiebreaker>(
    'goal_difference',
  );
  const [season, setSeason] = useState<LeagueSeasonState | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');

  const refresh = useCallback(async () => {
    if (!leagueId) {
      setStandings([]);
      setTiebreaker('goal_difference');
      setSeason(null);
      setError('');
      setLoading(false);
      return;
    }

    if (isDemo) {
      setStandings(demoStandings);
      setTiebreaker('goal_difference');
      setSeason(demoSeason);
      setError('');
      setLoading(false);
      return;
    }

    setLoading(true);
    try {
      const snapshot = await fetchLeagueStandings(leagueId);
      setStandings(snapshot.standings);
      setTiebreaker(snapshot.tiebreaker);
      setSeason(snapshot.season);
      setError('');
    } catch {
      setError('La classifica non risponde. Forse sta facendo i conti a mano.');
    } finally {
      setLoading(false);
    }
  }, [isDemo, leagueId]);

  useEffect(() => {
    void refresh();
  }, [refresh]);

  useEffect(() => {
    if (!leagueId || isDemo) {
      return;
    }
    return subscribeToLeagueResults(leagueId, () => void refresh());
  }, [isDemo, leagueId, refresh]);

  return { standings, tiebreaker, season, loading, error, refresh };
}
