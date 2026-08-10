export type MainTab = 'home' | 'league' | 'live' | 'profile';
export type AppScreen =
  | MainTab
  | 'about'
  | 'account'
  | 'auction'
  | 'calendar'
  | 'leagueCup'
  | 'leagueOperations'
  | 'leaguePlayoffs'
  | 'leagueSuperCup'
  | 'leagueHistory'
  | 'leagueManagement'
  | 'leagueRulebook'
  | 'leagueSettings'
  | 'leagueSetup'
  | 'lineup'
  | 'matchup'
  | 'roster'
  | 'standings'
  | 'teamMembership'
  | 'market'
  | 'notifications'
  | 'notificationPreferences'
  | 'players'
  | 'postponements'
  | 'premium'
  | 'privacy'
  | 'publicRoster'
  | 'support';



export type PublicTeamSelection = {
  id: string;
  name: string;
  managerName?: string | null;
};

export type LeagueMode = 'classic' | 'mantra';

export type LeagueSummary = {
  id: string;
  name: string;
  inviteCode: string;
  mode: LeagueMode;
  status: 'draft' | 'active' | 'completed' | 'archived';
  teamLimit: number;
  startingCredits: number;
  rosterSize: number;
  memberCount: number;
  ownerId?: string;
  invitesOpen?: boolean;
  competitionStartedAt?: string | null;
  currentRole?: 'admin' | 'manager';
  season?: string | null;
  team?: {
    id: string;
    name: string;
    creditsRemaining: number;
  };
  isDemo?: boolean;
};

export type LeagueMemberSummary = {
  userId: string;
  displayName: string;
  role: 'admin' | 'manager';
  isOwner?: boolean;
  joinedAt: string;
  team?: {
    id: string;
    name: string;
    creditsRemaining: number;
  };
};

export type LeaguePermissionState = {
  role: 'president' | 'admin' | 'manager' | 'none';
  isMember: boolean;
  isOwner: boolean;
  isAdmin: boolean;
  hasTeam: boolean;
  canAccessDirection: boolean;
  canRunOperations: boolean;
  canEditRules: boolean;
  canManageInvites: boolean;
  canManageMembers: boolean;
  canManageAdmins: boolean;
  canTransferPresidency: boolean;
  canStartCompetition: boolean;
  canCloseSeason: boolean;
  canSubmitLineup: boolean;
  canUseMarket: boolean;
};



export type LeagueAccessSession = {
  accessValid: boolean;
  reason: 'membership_revoked' | 'league_missing' | null;
  revision: number;
  roleUpdatedAt: string | null;
  permissions: LeaguePermissionState;
};

export type LeagueRoleAuditEvent = {
  id: string;
  type: 'admin_granted' | 'admin_revoked' | 'presidency_transferred';
  actorId: string | null;
  actorName: string;
  targetUserId: string | null;
  targetName: string;
  previousRole: 'admin' | 'manager' | null;
  newRole: 'admin' | 'manager' | null;
  createdAt: string;
};

export type LeagueRoleIntegrity = {
  healthy: boolean;
  ownerMemberExists: boolean;
  ownerProfileActive: boolean;
  teamManagersAreMembers: boolean;
  oneTeamPerManager: boolean;
  memberCount: number;
  adminCount: number;
  teamCount: number;
  orphanTeamCount: number;
  duplicateTeamManagerCount: number;
};

export type LeagueRoleMatrixMember = {
  userId: string;
  displayName: string;
  teamName: string | null;
  role: 'president' | 'admin' | 'manager';
  canAccessDirection: boolean;
  canManageHierarchy: boolean;
  canRunOperations: boolean;
  canManageTeam: boolean;
};

export type LeagueRoleSecurity = {
  hardened: boolean;
  presidentCount: number;
  adminCount: number;
  managerCount: number;
  directRoleMutationBlocked: boolean;
  directPresidencyMutationBlocked: boolean;
  directRemovalBlocked: boolean;
  guardedActionsReady: boolean;
  members: LeagueRoleMatrixMember[];
};

export type LeagueRoleControlState = {
  integrity: LeagueRoleIntegrity;
  security: LeagueRoleSecurity;
  events: LeagueRoleAuditEvent[];
};


export type LeagueCompetitionLifecycle = {
  started: boolean;
  startedAt: string | null;
  startedBy: string | null;
  revision: number;
  startVersion: number;
  openingVersion: number;
  openingVerifiedAt: string | null;
  currentMatchdayId: string | null;
  currentMatchdayNumber: number;
  openingMatchdayId: string | null;
  openingMatchdayNumber: number;
  openingStartsAt: string | null;
  openingLocksAt: string | null;
  openingFixtureCount: number;
  expectedOpeningFixtureCount: number;
  openingReady: boolean;
  activationProtected: boolean;
  modelClosed: boolean;
  modelClosedAt: string | null;
  modelVersion: number;
  structureVerifiedAt: string | null;
  fixtureStructureProtected: boolean;
  leagueStructureProtected: boolean;
  calendarFingerprintStable: boolean;
  calendarCountsReady: boolean;
  integrityHealthy: boolean;
  eventCount: number;
};

export type LeagueManagementState = {
  memberCount: number;
  teamLimit: number;
  teamCount: number;
  fullRosterCount: number;
  rosterSize: number;
  fixtureCount: number;
  officialFixtureCount: number;
  remainingFixtureCount: number;
  invitesOpen: boolean;
  competitionStartedAt: string | null;
  completedAt: string | null;
  status: LeagueSummary['status'];
  season: string | null;
  champion: LeagueSeasonChampion | null;
  isOwner: boolean;
  canStart: boolean;
  canComplete: boolean;
  seasonCompletionCausalStatus: 'clear' | 'blocked' | 'affected';
  seasonCompletionCausalReason: string | null;
  seasonCompletionCausallyCertified: boolean;
  seasonCompletionAffected: boolean;
  officialSnapshotProtected: boolean;
  officialSnapshotPublished: boolean;
  officialSnapshotHealthy: boolean;
  officialSnapshotStatus: 'pending' | 'official' | 'affected';
  officialSnapshotReason: string | null;
  officialSnapshotAffected: boolean;
  officialSnapshotId: number | null;
  officialSnapshotHash: string | null;
  officialPodium: LeagueStanding[];
  seasonRolloverProtected: boolean;
  seasonRolloverCertified: boolean;
  seasonRolloverHealthy: boolean;
  seasonRolloverStatus: 'pending' | 'certified' | 'affected';
  seasonRolloverReason: string | null;
  seasonRolloverAffected: boolean;
  seasonRolloverCertificateId: number | null;
  seasonRolloverLineageHash: string | null;
  seasonRolloverSourceSnapshotHash: string | null;
  providerSeasonBootstrapProtected: boolean;
  providerSeasonBootstrapApplicable: boolean;
  providerSeasonBootstrapHealthy: boolean;
  providerSeasonBootstrapAffected: boolean;
  providerSeasonBootstrapStatus: 'waiting' | 'catalog_ready' | 'ready' | 'affected';
  providerSeasonBootstrapReason: string | null;
  providerSeasonCatalogReady: boolean;
  providerSeasonFixturesReady: boolean;
  providerSeasonBootstrapCertified: boolean;
  providerSeasonBootstrapCertificateId: number | null;
  providerSeasonBootstrapHash: string | null;
  providerCompetitionStartProtected: boolean;
  providerCompetitionStartApplicable: boolean;
  providerCompetitionStartHealthy: boolean;
  providerCompetitionStartAffected: boolean;
  providerCompetitionStartStatus: 'waiting' | 'ready' | 'official' | 'affected';
  providerCompetitionStartReason: string | null;
  providerCompetitionStartReady: boolean;
  providerCompetitionStartCertified: boolean;
  providerCompetitionStartCertificateId: number | null;
  providerCompetitionStartHash: string | null;
  canRenew: boolean;
  previousLeagueId: string | null;
  previousSeason: string | null;
  nextLeagueId: string | null;
  nextSeason: string | null;
  renewedAt: string | null;
  renewalCopiedMemberCount: number;
  permissions: LeaguePermissionState;
  accessSession: LeagueAccessSession;
  roleControl: LeagueRoleControlState;
  competitionLifecycle: LeagueCompetitionLifecycle;
  checks: {
    membersReady: boolean;
    teamsReady: boolean;
    rostersReady: boolean;
    calendarReady: boolean;
    marketReady: boolean;
    tradesSettled: boolean;
    auctionIntegrityReady: boolean;
    auctionClosed: boolean;
    calendarIntegrityReady: boolean;
    calendarSnapshotStable: boolean;
    precompetitionSnapshotLocked: boolean;
    snapshotMutationGuardReady: boolean;
    competitionActivationReady: boolean;
    competitionModelClosed: boolean;
    matchdayProgressionReady: boolean;
    seasonCompletionCertified: boolean;
    seasonCompletionCausalReady: boolean;
    seasonOfficialSnapshotProtected: boolean;
    seasonOfficialSnapshotPublished: boolean;
    seasonOfficialSnapshotHealthy: boolean;
    seasonRolloverProtected: boolean;
    seasonRolloverCertified: boolean;
    seasonRolloverHealthy: boolean;
    providerSeasonBootstrapProtected: boolean;
    providerSeasonCatalogReady: boolean;
    providerSeasonFixturesReady: boolean;
    providerSeasonBootstrapCertified: boolean;
    providerSeasonBootstrapHealthy: boolean;
    providerCompetitionStartProtected: boolean;
    providerCompetitionStartReady: boolean;
    providerCompetitionStartCertified: boolean;
    providerCompetitionStartHealthy: boolean;
    lineupLifecycleReady: boolean;
    liveLifecycleReady: boolean;
    matchdayLifecycleReady: boolean;
    matchdayModelClosed: boolean;
    specialCompetitionsModelClosed: boolean;
  };
};

export type CalendarFixture = {
  id: string;
  matchdayId: string;
  matchdayNumber: number;
  startsAt: string;
  locksAt: string;
  endsAt: string | null;
  scheduleSource: 'estimated' | 'provider';
  scheduleSyncedAt: string | null;
  providerFixtureCount: number;
  providerFinalFixtureCount: number;
  homeTeam: {
    id: string;
    name: string;
    managerId: string;
  };
  awayTeam: {
    id: string;
    name: string;
    managerId: string;
  };
  homePoints: number | null;
  awayPoints: number | null;
  homeGoals: number | null;
  awayGoals: number | null;
  finalized: boolean;
};

export type CalendarScheduleMatchday = {
  id: string;
  number: number;
  startsAt: string;
  locksAt: string;
  endsAt: string | null;
  scheduleSource: 'estimated' | 'provider';
  providerFixtureCount: number;
  providerFinalFixtureCount: number;
};

export type LeagueScheduleHealth = {
  matchdayCount: number;
  providerAlignedMatchdays: number;
  estimatedMatchdays: number;
  lastScheduleSyncAt: string | null;
  nextMatchday: CalendarScheduleMatchday | null;
};

export type CalendarSchedulePreview = {
  requestedMatchdays: number;
  availableMatchdays: number;
  providerAlignedMatchdays: number;
  estimatedMatchdays: number;
  missingMatchdays: number;
  firstKickoff: string | null;
};

export type CalendarTeamReadiness = {
  teamId: string;
  teamName: string;
  managerId: string;
  rosterCount: number;
  rosterSize: number;
  complete: boolean;
};

export type LeagueCompetitionPreflight = {
  version: number;
  checkedAt: string | null;
  pendingTradeCount: number;
  unfinishedAuctionCount: number;
  biddingItemCount: number;
  expectedFixtureCount: number;
  expectedMatchdayCount: number;
  pairIssueCount: number;
  teamMatchdayIssueCount: number;
  calendarSnapshotPresent: boolean;
  calendarSnapshotStable: boolean;
  calendarIntegrityVerifiedAt: string | null;
  precompetitionSnapshotLocked: boolean;
  snapshotMutationGuardReady: boolean;
  snapshotMutationGuardCount: number;
  canGenerateCalendar: boolean;
  canStartCompetition: boolean;
  checks: {
    marketReady: boolean;
    tradesSettled: boolean;
    auctionIntegrityReady: boolean;
    auctionClosed: boolean;
    calendarIntegrityReady: boolean;
    calendarSnapshotStable: boolean;
    precompetitionSnapshotLocked: boolean;
    snapshotMutationGuardReady: boolean;
  };
};

export type LeagueCalendarState = {
  memberCount: number;
  teamCount: number;
  teamLimit: number;
  fullRosterCount: number;
  rosterSize: number;
  fixtureCount: number;
  matchdayCount: number;
  firstMatchday: number | null;
  lastMatchday: number | null;
  season: string | null;
  returnLeg: boolean;
  generatedAt: string | null;
  competitionStartedAt: string | null;
  calendarExists: boolean;
  isOwner: boolean;
  isDirector: boolean;
  canGenerate: boolean;
  canReset: boolean;
  checks: {
    membersReady: boolean;
    teamsReady: boolean;
    rostersReady: boolean;
    calendarEmpty: boolean;
    competitionNotStarted: boolean;
    marketReady: boolean;
    tradesSettled: boolean;
    auctionIntegrityReady: boolean;
    auctionClosed: boolean;
    calendarIntegrityReady: boolean;
    calendarSnapshotStable: boolean;
    precompetitionSnapshotLocked: boolean;
    snapshotMutationGuardReady: boolean;
  };
  preflight: LeagueCompetitionPreflight;
  teams: CalendarTeamReadiness[];
};

export type RosterPlayer = {
  id: string;
  name: string;
  clubName: string;
  shirtNumber: number | null;
  role: string;
  purchasePrice: number;
};

export type LineupContext = {
  matchday: {
    id: string;
    number: number;
    startsAt: string;
    locksAt: string;
  };
  opponentName: string;
  home: boolean;
  formation: string | null;
  starterIds: string[];
  benchIds: string[];
  benchLimit: number;
  rosterCount: number;
  submittedAt: string | null;
  firstSubmittedAt: string | null;
  updatedAt: string | null;
  lockedAt: string | null;
  lineupOrigin: 'manager' | 'carried' | 'previous_preview' | 'empty';
  sourceMatchdayNumber: number | null;
  willAutoCarry: boolean;
  firstSubmissionRequired: boolean;
  revision: number;
  contentHash: string | null;
  serverNow: string | null;
  secondsUntilLock: number;
  canSubmit: boolean;
  lockState: 'open' | 'locked';
  submissionPolicy: 'guarded_v1' | 'legacy';
  integrityReady: boolean;
  directWritesBlocked: boolean;
  deadlinePolicy: 'guarded_v1' | 'legacy';
  deadlineOutcome:
    | 'open'
    | 'processing'
    | 'manager'
    | 'carried'
    | 'missing';
  deadlineCertified: boolean;
  deadlineProcessedAt: string | null;
  deadlineEventReady: boolean;
  immutableAfterLock: boolean;
  matchdayLineupsFinalizedAt: string | null;
  matchdayLineupLockRevision: number;
  matchdayLineupLockHash: string | null;
};

export type LeagueStanding = {
  position: number;
  teamId: string;
  teamName: string;
  played: number;
  won: number;
  drawn: number;
  lost: number;
  goalsFor: number;
  goalsAgainst: number;
  goalDifference: number;
  pointsFor: number;
  leaguePoints: number;
  headToHeadPlayed: number;
  headToHeadPoints: number;
  headToHeadGoalDifference: number;
  headToHeadEligible: boolean;
};

export type StandingsTiebreaker =
  | 'goal_difference'
  | 'fantasy_points'
  | 'head_to_head';

export type LeagueSeasonChampion = {
  teamId: string;
  teamName: string;
  managerName: string;
  leaguePoints: number;
  pointsFor: number;
};

export type LeagueSeasonState = {
  status: LeagueSummary['status'];
  season: string | null;
  competitionStartedAt: string | null;
  completedAt: string | null;
  isOwner: boolean;
  fixtureCount: number;
  officialFixtureCount: number;
  remainingFixtureCount: number;
  canComplete: boolean;
  champion: LeagueSeasonChampion | null;
  tiebreaker: StandingsTiebreaker;
  finalStandings: LeagueStanding[];
  completionCertified: boolean;
  completionRunId: number | null;
  completionStandingsHash: string | null;
  finalProgressionRunId: number | null;
  finalMatchdayId: string | null;
  seasonReadyToComplete: boolean;
  seasonCompletionCausalStatus: 'clear' | 'blocked' | 'affected';
  seasonCompletionCausalReason: string | null;
  seasonCompletionCausallyCertified: boolean;
  seasonCompletionAffected: boolean;
  officialSnapshotProtected: boolean;
  officialSnapshotPublished: boolean;
  officialSnapshotHealthy: boolean;
  officialSnapshotStatus: 'pending' | 'official' | 'affected';
  officialSnapshotReason: string | null;
  officialSnapshotAffected: boolean;
  officialSnapshotId: number | null;
  officialSnapshotHash: string | null;
  officialPodium: LeagueStanding[];
  seasonRolloverProtected: boolean;
  seasonRolloverCertified: boolean;
  seasonRolloverHealthy: boolean;
  seasonRolloverStatus: 'pending' | 'certified' | 'affected';
  seasonRolloverReason: string | null;
  seasonRolloverAffected: boolean;
  seasonRolloverCertificateId: number | null;
  seasonRolloverLineageHash: string | null;
  seasonRolloverSourceSnapshotHash: string | null;
  providerSeasonBootstrapProtected: boolean;
  providerSeasonBootstrapApplicable: boolean;
  providerSeasonBootstrapHealthy: boolean;
  providerSeasonBootstrapAffected: boolean;
  providerSeasonBootstrapStatus: 'waiting' | 'catalog_ready' | 'ready' | 'affected';
  providerSeasonBootstrapReason: string | null;
  providerSeasonCatalogReady: boolean;
  providerSeasonFixturesReady: boolean;
  providerSeasonBootstrapCertified: boolean;
  providerSeasonBootstrapCertificateId: number | null;
  providerSeasonBootstrapHash: string | null;
  providerCompetitionStartProtected: boolean;
  providerCompetitionStartApplicable: boolean;
  providerCompetitionStartHealthy: boolean;
  providerCompetitionStartAffected: boolean;
  providerCompetitionStartStatus: 'waiting' | 'ready' | 'official' | 'affected';
  providerCompetitionStartReason: string | null;
  providerCompetitionStartReady: boolean;
  providerCompetitionStartCertified: boolean;
  providerCompetitionStartCertificateId: number | null;
  providerCompetitionStartHash: string | null;
};

export type LeagueHistoryPodiumEntry = {
  position: number;
  teamId: string;
  teamName: string;
  managerName: string;
  leaguePoints: number;
  pointsFor: number;
};

export type LeagueHistorySeason = {
  leagueId: string;
  season: string | null;
  status: LeagueSummary['status'];
  startedAt: string | null;
  completedAt: string | null;
  memberCount: number;
  fixtureCount: number;
  officialFixtureCount: number;
  champion: LeagueSeasonChampion | null;
  podium: LeagueHistoryPodiumEntry[];
  isSelected: boolean;
  isLatest: boolean;
};

export type LeagueHistoryTitleLeader = {
  managerId: string;
  managerName: string;
  titles: number;
  teamNames: string[];
};

export type LeagueHistory = {
  leagueName: string;
  selectedLeagueId: string;
  latestLeagueId: string;
  totalSeasons: number;
  completedSeasons: number;
  seasons: LeagueHistorySeason[];
  titleLeaders: LeagueHistoryTitleLeader[];
};

export type LeagueSeasonRecordKey =
  | 'league_points'
  | 'fantasy_points'
  | 'wins'
  | 'goals_for'
  | 'goal_difference';

export type LeagueSeasonRecord = {
  key: LeagueSeasonRecordKey;
  value: number;
  season: string | null;
  teamId: string;
  teamName: string;
  managerId: string;
  managerName: string;
};

export type LeagueMatchRecordKey =
  | 'highest_score'
  | 'biggest_win'
  | 'highest_total_goals';

export type LeagueMatchRecord = {
  key: LeagueMatchRecordKey;
  value: number;
  fixtureId: string;
  season: string | null;
  matchdayNumber: number;
  teamId: string;
  teamName: string;
  managerId: string;
  managerName: string;
  opponentName: string;
  homeTeamName: string;
  awayTeamName: string;
  homePoints: number;
  awayPoints: number;
  homeGoals: number;
  awayGoals: number;
};

export type LeagueManagerCareer = {
  rank: number;
  managerId: string;
  managerName: string;
  seasons: number;
  titles: number;
  podiums: number;
  bestFinish: number;
  played: number;
  won: number;
  drawn: number;
  lost: number;
  goalsFor: number;
  goalsAgainst: number;
  fantasyPoints: number;
  leaguePoints: number;
  winRate: number;
  teamNames: string[];
};

export type LeagueRecords = {
  completedSeasons: number;
  seasonRecords: LeagueSeasonRecord[];
  matchRecords: LeagueMatchRecord[];
  careerLeaders: LeagueManagerCareer[];
};

export type LeagueCupTeam = {
  id: string;
  name: string;
  managerName: string;
  seed: number;
};

export type LeagueCupTieStatus =
  | 'waiting'
  | 'live'
  | 'ready'
  | 'official'
  | 'bye';

export type LeagueCupTieDecision =
  | 'goals'
  | 'fantasy_points'
  | 'seed'
  | 'bye';

export type LeagueCupTie = {
  id: string;
  position: number;
  homeTeam: LeagueCupTeam | null;
  awayTeam: LeagueCupTeam | null;
  homePoints: number | null;
  awayPoints: number | null;
  homeGoals: number | null;
  awayGoals: number | null;
  homeReady: boolean;
  awayReady: boolean;
  homeCountedPlayers: number;
  awayCountedPlayers: number;
  winnerTeamId: string | null;
  decidedBy: LeagueCupTieDecision | null;
  finalizedAt: string | null;
  status: LeagueCupTieStatus;
};

export type LeagueCupRoundStatus =
  | 'scheduled'
  | 'live'
  | 'ready'
  | 'official';

export type LeagueCupRound = {
  id: string;
  number: number;
  name: string;
  matchdayId: string;
  matchdayNumber: number;
  startsAt: string;
  locksAt: string;
  endsAt: string | null;
  status: LeagueCupRoundStatus;
  finalizedAt: string | null;
  ties: LeagueCupTie[];
};

export type LeagueCupStartMatchday = {
  id: string;
  number: number;
  startsAt: string;
  locksAt: string;
};

export type LeagueCupPodiumTeam = {
  teamId: string;
  teamName: string;
  managerName: string;
};

export type LeagueCupState = {
  exists: boolean;
  leagueId: string;
  cupId: string | null;
  name: string;
  status: 'not_created' | 'active' | 'completed';
  isOwner: boolean;
  canCreate: boolean;
  creationReason: string | null;
  teamCount: number;
  bracketSize: number;
  roundCount: number;
  currentRound: number;
  startedAt: string | null;
  completedAt: string | null;
  drawSeed: string | null;
  drawPolicy: 'guarded_v1' | 'legacy';
  drawCertified: boolean;
  drawRunId: string | null;
  drawRevision: number;
  roundFinalizationPolicy: 'guarded_v1' | 'legacy';
  officialRoundCount: number;
  certifiedRoundCount: number;
  roundsCertified: boolean;
  currentRoundOfficializationReady: boolean;
  lastRoundRunId: string | null;
  lastCertifiedRound: number;
  lastRoundFinalizedAt: string | null;
  completionPolicy: 'certified_v1' | 'legacy';
  completionCertified: boolean;
  completionCertificateId: string | null;
  completionFingerprint: string | null;
  completionCertifiedAt: string | null;
  completionFinalizationRunId: string | null;
  startMatchdays: LeagueCupStartMatchday[];
  rounds: LeagueCupRound[];
  champion: LeagueCupPodiumTeam | null;
  runnerUp: LeagueCupPodiumTeam | null;
  canFinalizeCurrent: boolean;
};

export type LeaguePlayoffStatus =
  | 'not_configured'
  | 'configured'
  | 'active'
  | 'completed';

export type LeaguePlayoffState = {
  exists: boolean;
  leagueId: string;
  playoffId: string | null;
  status: LeaguePlayoffStatus;
  isOwner: boolean;
  canConfigure: boolean;
  canStart: boolean;
  actionReason: string | null;
  participantCount: 4 | 8;
  roundCount: number;
  currentRound: number;
  regularSeasonReady: boolean;
  configuredAt: string | null;
  startedAt: string | null;
  completedAt: string | null;
  configurationPolicy: 'guarded_v1' | 'legacy';
  configurationCertified: boolean;
  configurationRunId: number | null;
  configurationRequestId: string | null;
  configurationSourceMode: 'guarded_v1' | 'legacy_backfill' | null;
  configurationHash: string | null;
  configurationResultHash: string | null;
  configurationCertifiedAt: string | null;
  startPolicy: 'guarded_v1' | 'legacy';
  startCertified: boolean;
  startRunId: number | null;
  startRequestId: string | null;
  startSourceMode: 'guarded_v1' | 'legacy_backfill' | null;
  startMatchdayNumber: number | null;
  startQualificationSourceHash: string | null;
  startQualificationHash: string | null;
  startScheduleHash: string | null;
  startOpeningBracketHash: string | null;
  startResultHash: string | null;
  startCertifiedAt: string | null;
  roundFinalizationPolicy: 'guarded_v1' | 'legacy';
  officialRoundCount: number;
  certifiedRoundCount: number;
  roundsCertified: boolean;
  currentRoundOfficializationReady: boolean;
  lastRoundRunId: number | null;
  lastCertifiedRound: number;
  lastRoundFinalizedAt: string | null;
  completionPolicy: 'certified_v1' | 'legacy';
  completionCertified: boolean;
  completionCertificateId: number | null;
  completionFingerprint: string | null;
  completionCertifiedAt: string | null;
  completionFinalizationRunId: number | null;
  startMatchdays: LeagueCupStartMatchday[];
  rounds: LeagueCupRound[];
  champion: LeagueCupPodiumTeam | null;
  runnerUp: LeagueCupPodiumTeam | null;
  canFinalizeCurrent: boolean;
};

export type LeaguePlayoffHistoryTeam = {
  teamId: string;
  teamName: string;
  managerId: string;
  managerName: string;
  seed: number | null;
  regularSeasonPosition: number | null;
};

export type LeaguePlayoffHistorySeason = {
  leagueId: string;
  season: string | null;
  leagueStatus: LeagueSummary['status'];
  playoffExists: boolean;
  playoffId: string | null;
  playoffStatus: LeaguePlayoffStatus;
  configuredAt: string | null;
  startedAt: string | null;
  completedAt: string | null;
  participantCount: number;
  roundCount: number;
  currentRound: number;
  totalTieCount: number;
  officialTieCount: number;
  champion: LeaguePlayoffHistoryTeam | null;
  runnerUp: LeaguePlayoffHistoryTeam | null;
  regularSeasonLeader: LeaguePlayoffHistoryTeam | null;
  isSelected: boolean;
  isLatest: boolean;
};

export type LeaguePlayoffHistoryTitleLeader = {
  managerId: string;
  managerName: string;
  titles: number;
  finals: number;
  lowerSeedTitles: number;
  teamNames: string[];
  seasons: string[];
};

export type LeaguePlayoffManagerCareer = {
  rank: number;
  managerId: string;
  managerName: string;
  participations: number;
  titles: number;
  finals: number;
  lowerSeedTitles: number;
  tiesPlayed: number;
  tiesWon: number;
  winRate: number;
  teamNames: string[];
};

export type LeaguePlayoffHistory = {
  leagueName: string;
  selectedLeagueId: string;
  latestLeagueId: string;
  completedPlayoffs: number;
  activePlayoffs: number;
  configuredPlayoffs: number;
  seasons: LeaguePlayoffHistorySeason[];
  titleLeaders: LeaguePlayoffHistoryTitleLeader[];
  careerLeaders: LeaguePlayoffManagerCareer[];
  matchRecords: LeagueCupMatchRecord[];
};

export type LeagueCupHistoryTeam = {
  teamId: string;
  teamName: string;
  managerId: string;
  managerName: string;
};

export type LeagueCupHistorySeason = {
  leagueId: string;
  season: string | null;
  leagueStatus: LeagueSummary['status'];
  cupExists: boolean;
  cupId: string | null;
  cupName: string | null;
  cupStatus: 'not_created' | 'active' | 'completed';
  startedAt: string | null;
  completedAt: string | null;
  teamCount: number;
  roundCount: number;
  currentRound: number;
  totalTieCount: number;
  officialTieCount: number;
  champion: LeagueCupHistoryTeam | null;
  runnerUp: LeagueCupHistoryTeam | null;
  isSelected: boolean;
  isLatest: boolean;
};

export type LeagueCupHistoryTitleLeader = {
  managerId: string;
  managerName: string;
  titles: number;
  finals: number;
  teamNames: string[];
  seasons: string[];
};

export type LeagueCupManagerCareer = {
  rank: number;
  managerId: string;
  managerName: string;
  participations: number;
  titles: number;
  finals: number;
  tiesPlayed: number;
  tiesWon: number;
  winRate: number;
  teamNames: string[];
};

export type LeagueCupMatchRecordKey =
  | 'highest_score'
  | 'biggest_win'
  | 'highest_total_goals';

export type LeagueCupMatchRecord = {
  key: LeagueCupMatchRecordKey;
  value: number;
  tieId: string;
  season: string | null;
  matchdayNumber: number;
  roundName: string;
  teamId: string;
  teamName: string;
  managerId: string;
  managerName: string;
  opponentName: string;
  homeTeamName: string;
  awayTeamName: string;
  homePoints: number;
  awayPoints: number;
  homeGoals: number;
  awayGoals: number;
  decidedBy: LeagueCupTieDecision | null;
};

export type LeagueCupHistory = {
  leagueName: string;
  selectedLeagueId: string;
  latestLeagueId: string;
  completedCups: number;
  activeCups: number;
  seasons: LeagueCupHistorySeason[];
  titleLeaders: LeagueCupHistoryTitleLeader[];
  careerLeaders: LeagueCupManagerCareer[];
  matchRecords: LeagueCupMatchRecord[];
};

export type LeagueSuperCupQualification =
  | 'league_champion'
  | 'cup_champion'
  | 'cup_runner_up';

export type LeagueSuperCupDecision =
  | 'goals'
  | 'fantasy_points'
  | 'league_champion';

export type LeagueSuperCupTeam = {
  teamId: string;
  teamName: string;
  managerId: string;
  managerName: string;
  qualification?: LeagueSuperCupQualification;
};

export type LeagueSuperCupMatchday = {
  id: string;
  number: number;
  startsAt: string;
  locksAt: string;
  endsAt: string | null;
};

export type LeagueSuperCupState = {
  exists: boolean;
  leagueId: string;
  superCupId: string | null;
  status: 'not_created' | 'active' | 'completed';
  isOwner: boolean;
  eligible: boolean;
  canCreate: boolean;
  creationReason: string | null;
  sourceLeagueId: string | null;
  sourceSeason: string | null;
  leagueChampion: LeagueSuperCupTeam | null;
  challenger: LeagueSuperCupTeam | null;
  challengerQualification: LeagueSuperCupQualification | null;
  matchday: LeagueSuperCupMatchday | null;
  startMatchdays: LeagueSuperCupMatchday[];
  homePoints: number | null;
  awayPoints: number | null;
  homeGoals: number | null;
  awayGoals: number | null;
  homeReady: boolean;
  awayReady: boolean;
  homeCountedPlayers: number;
  awayCountedPlayers: number;
  decidedBy: LeagueSuperCupDecision | null;
  createdAt: string | null;
  completedAt: string | null;
  canFinalize: boolean;
  winner: LeagueSuperCupTeam | null;
  runnerUp: LeagueSuperCupTeam | null;
  schedulePolicy: 'guarded_v1' | null;
  scheduleCertified: boolean;
  scheduleRunId: number | null;
  scheduleRequestId: string | null;
  scheduleQualifiersHash: string | null;
  scheduleHash: string | null;
  scheduleResultHash: string | null;
  finalizationPolicy: 'guarded_v1' | null;
  finalizationCertified: boolean;
  finalizationRunId: number | null;
  finalizationRequestId: string | null;
  finalizationSourceMode: 'guarded_v1' | 'legacy_backfill' | null;
  finalizationInputHash: string | null;
  finalizationResultHash: string | null;
  finalizationOfficializationRunId: number | null;
  finalizationHomeResolutionId: number | null;
  finalizationAwayResolutionId: number | null;
};

export type LeagueSuperCupHistorySeason = {
  leagueId: string;
  season: string | null;
  leagueStatus: LeagueSummary['status'];
  superCupExists: boolean;
  superCupId: string | null;
  superCupStatus: 'not_created' | 'active' | 'completed';
  sourceSeason: string | null;
  matchdayNumber: number;
  challengerQualification: LeagueSuperCupQualification | null;
  leagueChampion: LeagueSuperCupTeam | null;
  challenger: LeagueSuperCupTeam | null;
  homePoints: number | null;
  awayPoints: number | null;
  homeGoals: number | null;
  awayGoals: number | null;
  decidedBy: LeagueSuperCupDecision | null;
  createdAt: string | null;
  completedAt: string | null;
  winner: LeagueSuperCupTeam | null;
  runnerUp: LeagueSuperCupTeam | null;
  isSelected: boolean;
  isLatest: boolean;
};

export type LeagueSuperCupTitleLeader = {
  rank: number;
  managerId: string;
  managerName: string;
  titles: number;
  teamNames: string[];
  seasons: string[];
};

export type LeagueSuperCupHistory = {
  leagueName: string;
  selectedLeagueId: string;
  latestLeagueId: string;
  completedSuperCups: number;
  activeSuperCups: number;
  seasons: LeagueSuperCupHistorySeason[];
  titleLeaders: LeagueSuperCupTitleLeader[];
};

export type LeagueTrophyCompetition =
  | 'league'
  | 'cup'
  | 'super_cup';

export type LeagueTrophyCabinetTeam = {
  teamId: string;
  teamName: string;
  managerId: string;
  managerName: string;
};

export type LeagueTrophyTimelineEntry = {
  id: string;
  competition: LeagueTrophyCompetition;
  leagueId: string;
  season: string | null;
  sourceSeason: string | null;
  completedAt: string | null;
  winner: LeagueTrophyCabinetTeam;
  runnerUp: LeagueTrophyCabinetTeam | null;
};

export type LeagueTrophyLeader = {
  rank: number;
  managerId: string;
  managerName: string;
  totalTrophies: number;
  leagueTitles: number;
  cupTitles: number;
  superCupTitles: number;
  leaguePodiums: number;
  cupFinals: number;
  superCupFinals: number;
  doubles: number;
  teamNames: string[];
  seasons: string[];
};

export type LeagueTrophyCabinet = {
  leagueName: string;
  selectedLeagueId: string;
  latestLeagueId: string;
  totalTrophies: number;
  leagueTitles: number;
  cupTitles: number;
  superCupTitles: number;
  uniqueWinners: number;
  doubles: number;
  leaders: LeagueTrophyLeader[];
  timeline: LeagueTrophyTimelineEntry[];
};

export type LeagueOperationMatchdayStatus =
  | 'upcoming'
  | 'live'
  | 'pending'
  | 'ready'
  | 'official';

export type LeagueOperationLineupStatus =
  | 'manual'
  | 'carried'
  | 'draft'
  | 'missing';

export type LeagueOperationTeamLineup = {
  teamId: string;
  teamName: string;
  managerId: string;
  managerName: string;
  status: LeagueOperationLineupStatus;
  submittedAt: string | null;
  reminderSent: boolean;
};

export type LeagueOperationFocusMatchday = {
  id: string;
  number: number;
  startsAt: string;
  locksAt: string;
  endsAt: string | null;
  scheduleSource: 'estimated' | 'provider';
  scheduleSyncedAt: string | null;
  providerFixtureCount: number;
  providerFinalFixtureCount: number;
  fixtureCount: number;
  readyCount: number;
  officialCount: number;
  status: LeagueOperationMatchdayStatus;
  canFinalize: boolean;
};

export type LeagueOperationLineupMatchday = {
  id: string;
  number: number;
  startsAt: string;
  locksAt: string;
  endsAt: string | null;
  scheduleSource: 'estimated' | 'provider';
  scheduleSyncedAt: string | null;
  providerFixtureCount: number;
  providerFinalFixtureCount: number;
  teamCount: number;
  manualCount: number;
  carriedCount: number;
  draftCount: number;
  missingCount: number;
  reminderSentCount: number;
  canRemind: boolean;
  teams: LeagueOperationTeamLineup[];
};

export type ProviderSyncRunStatus = 'running' | 'completed' | 'failed';

export type ProviderSyncAction =
  | 'sync-fixtures'
  | 'sync-fixture-players'
  | 'sync-season-players';

export type ProviderSyncActionState = {
  action: ProviderSyncAction;
  status: ProviderSyncRunStatus;
  startedAt: string;
  finishedAt: string | null;
  recordsProcessed: number;
  revision: number;
  attempt: number;
};

export type ProviderDataQualityStatus = 'healthy' | 'attention' | 'idle';

export type ProviderDataQualitySnapshot = {
  runId: string;
  action: ProviderSyncAction;
  status: ProviderDataQualityStatus;
  anomalyCount: number;
  latestSourceAt: string | null;
  createdAt: string;
};

export type LeagueProviderDataQuality = {
  protected: boolean;
  healthy: boolean;
  status: ProviderDataQualityStatus;
  stale: boolean;
  anomalyCount: number;
  matchdayId: string | null;
  matchdayNumber: number | null;
  scheduleSource: 'estimated' | 'provider' | null;
  fixtureCount: number;
  finalFixtureCount: number;
  liveFixtureCount: number;
  scoreCount: number;
  finalScoreCount: number;
  invalidScoreCount: number;
  finalFixtureWithoutScoreCount: number;
  scheduleMismatchCount: number;
  snapshotMissingCount: number;
  latestFixtureAt: string | null;
  latestScoreAt: string | null;
  latestSnapshot: ProviderDataQualitySnapshot | null;
};

export type ProviderOperationalIncident = {
  id: string;
  type: 'sync_failure' | 'data_quality';
  syncType: ProviderSyncAction;
  severity: 'warning' | 'critical';
  status: 'open' | 'resolved';
  occurrenceCount: number;
  revision: number;
  summary: string;
  firstDetectedAt: string;
  lastDetectedAt: string;
};

export type LeagueProviderIncidentCenter = {
  protected: boolean;
  healthy: boolean;
  activeCount: number;
  criticalCount: number;
  warningCount: number;
  resolvedLast24h: number;
  lastIncidentAt: string | null;
  lastResolvedAt: string | null;
  incidents: ProviderOperationalIncident[];
};

export type ProviderRecoveryRequestStatus =
  | 'pending'
  | 'running'
  | 'completed'
  | 'failed'
  | 'cancelled';

export type ProviderRecoveryRequest = {
  id: string;
  incidentId: string;
  syncType: ProviderSyncAction;
  status: ProviderRecoveryRequestStatus;
  revision: number;
  attempt: number;
  requestedAt: string;
  startedAt: string | null;
  finishedAt: string | null;
  errorSummary: string | null;
};

export type ProviderRecoverableIncident = {
  id: string;
  revision: number;
  syncType: ProviderSyncAction;
  severity: 'warning' | 'critical';
  summary: string;
};

export type ProviderRecoveryProgress = {
  requestId: string;
  runId: string;
  syncType: ProviderSyncAction;
  phase: string;
  current: number;
  total: number | null;
  recordsProcessed: number;
  heartbeatAt: string;
  revision: number;
  percent: number | null;
};

export type ProviderAutomaticRetryCenter = {
  protected: boolean;
  healthy: boolean;
  automaticRetryActive: boolean;
  scheduledCount: number;
  dueCount: number;
  dispatchedCount: number;
  succeededLast24h: number;
  failedLast24h: number;
  exhaustedOpenCount: number;
  nextRetryAt: string | null;
  maxRetries: number;
};

export type ProviderRecoveryCircuitBreakerOpen = {
  id: string;
  incidentId: string;
  revision: number;
  syncType: ProviderSyncAction;
  failureClass:
    | 'rate_limit'
    | 'timeout'
    | 'network'
    | 'provider'
    | 'configuration'
    | 'request'
    | 'unknown';
  retryNo: number;
  maxRetries: number;
  summary: string;
  openedAt: string;
};

export type ProviderRecoveryCircuitBreakerCenter = {
  protected: boolean;
  healthy: boolean;
  blocked: boolean;
  openCount: number;
  releasedLast24h: number;
  resolvedLast24h: number;
  latestOpen: ProviderRecoveryCircuitBreakerOpen | null;
};

export type ProviderRecoveryCircuitBreakerReleaseOutcome = {
  breakerId: string;
  incidentId: string;
  status: 'released';
  revision: number;
  releasedAt: string;
  reused: boolean;
};

export type ProviderRecoveryOutcomeVerificationStatus =
  | 'verified'
  | 'retry_scheduled'
  | 'exhausted'
  | 'superseded';

export type ProviderRecoveryOutcomeVerificationLatest = {
  id: string;
  requestId: string;
  incidentId: string;
  syncType: ProviderSyncAction;
  outcome: ProviderRecoveryOutcomeVerificationStatus;
  snapshotStatus: ProviderDataQualityStatus | null;
  anomalyCount: number;
  retryNo: number | null;
  maxRetries: number | null;
  summary: string;
  createdAt: string;
};

export type ProviderRecoveryOutcomeVerificationCenter = {
  protected: boolean;
  healthy: boolean;
  outcomeVerificationActive: boolean;
  verifiedLast24h: number;
  ineffectiveLast24h: number;
  activeRetryCount: number;
  exhaustedOpenCount: number;
  latest: ProviderRecoveryOutcomeVerificationLatest | null;
};


export type ProviderWorkerLeaseStatus =
  | 'active'
  | 'released'
  | 'revoked'
  | 'expired';

export type ProviderWorkerLeaseLatest = {
  runId: string;
  requestId: string | null;
  syncType: ProviderSyncAction;
  status: ProviderWorkerLeaseStatus;
  leaseEpoch: number;
  revision: number;
  leaseExpiresAt: string;
  lastHeartbeatAt: string;
};

export type ProviderWorkerFencingCenter = {
  protected: boolean;
  healthy: boolean;
  workerFencingActive: boolean;
  activeLeaseCount: number;
  expiredLeaseCount: number;
  releasedLast24h: number;
  revokedLast24h: number;
  latestHeartbeatAt: string | null;
  latest: ProviderWorkerLeaseLatest | null;
};

export type ProviderPayloadContractViolationLatest = {
  id: string;
  runId: string;
  requestId: string | null;
  syncType: ProviderSyncAction;
  scope: string;
  code: string;
  itemIndex: number | null;
  summary: string;
  payloadSize: number;
  detectedAt: string;
};

export type ProviderPayloadContractCenter = {
  protected: boolean;
  healthy: boolean;
  runtimeValidationActive: boolean;
  databaseValidationActive: boolean;
  payloadStorageDisabled: boolean;
  contractVersion: string;
  violationsLast24h: number;
  totalViolationCount: number;
  latestViolationAt: string | null;
  latest: ProviderPayloadContractViolationLatest | null;
};

export type ProviderDeliveryCertificateLatest = {
  id: string;
  runId: string;
  requestId: string | null;
  syncType: ProviderSyncAction;
  status: 'collecting' | 'certified' | 'rejected';
  expectedUnitCount: number | null;
  observedUnitCount: number;
  observedRecordCount: number;
  uniqueEntityCount: number;
  summary: string;
  updatedAt: string;
};

export type ProviderDeliveryIntegrityCenter = {
  protected: boolean;
  healthy: boolean;
  deliveryValidationActive: boolean;
  completionGateActive: boolean;
  rawEntityStorageDisabled: boolean;
  deliveryVersion: string;
  collectingCount: number;
  certifiedLast24h: number;
  rejectedLast24h: number;
  totalCertificateCount: number;
  latestCertificateAt: string | null;
  latest: ProviderDeliveryCertificateLatest | null;
};

export type ProviderAtomicPublicationLatest = {
  id: string;
  runId: string;
  requestId: string | null;
  syncType: ProviderSyncAction;
  status: 'collecting' | 'published' | 'discarded';
  superseded: boolean;
  stagedRowCount: number;
  stagedPrimaryRecordCount: number;
  publishedPrimaryRecordCount: number;
  summary: string;
  updatedAt: string;
};

export type ProviderAtomicPublicationCenter = {
  protected: boolean;
  healthy: boolean;
  atomicStagingActive: boolean;
  singleCommitPublicationActive: boolean;
  partialLiveWritesDisabled: boolean;
  stagingPayloadPurgedAfterFinish: boolean;
  collectingCount: number;
  publishedLast24h: number;
  discardedLast24h: number;
  supersededLast24h: number;
  totalPublicationCount: number;
  latestPublicationAt: string | null;
  latest: ProviderAtomicPublicationLatest | null;
};

export type ProviderSemanticScopeLatest = {
  id: string;
  runId: string;
  publicationId: string;
  requestId: string | null;
  syncType: ProviderSyncAction;
  scopeKind: 'season' | 'date' | 'fixture';
  status: 'collecting' | 'certified' | 'rejected';
  observedAthleteCount: number;
  observedRoleCount: number;
  observedMatchdayCount: number;
  observedFixtureCount: number;
  observedScoreCount: number;
  summary: string;
  updatedAt: string;
};

export type ProviderSemanticScopeCenter = {
  protected: boolean;
  healthy: boolean;
  semanticScopeActive: boolean;
  operationBindingActive: boolean;
  crossEntityValidationActive: boolean;
  legacyBypassDisabled: boolean;
  collectingCount: number;
  certifiedLast24h: number;
  rejectedLast24h: number;
  totalCertificateCount: number;
  latestCertificateAt: string | null;
  latest: ProviderSemanticScopeLatest | null;
};

export type ProviderScopeWatermarkLatest = {
  id: string;
  watermarkId: string;
  eventType: 'backfilled' | 'advanced' | 'stale_rejected';
  candidateRunId: string;
  candidatePublicationId: string;
  latestRunId: string;
  generation: number;
  candidateStartedAt: string;
  latestStartedAt: string;
  recordCount: number;
  reasonCode: string;
  createdAt: string;
};

export type ProviderScopeWatermarkCenter = {
  protected: boolean;
  healthy: boolean;
  monotonicOrderingActive: boolean;
  stalePublicationBlocked: boolean;
  completionBypassDisabled: boolean;
  globalScopeSerialized: boolean;
  activeWatermarkCount: number;
  advancedLast24h: number;
  staleRejectedLast24h: number;
  latestWatermarkAt: string | null;
  latest: ProviderScopeWatermarkLatest | null;
};

export type ProviderPlayerCatalogHead = {
  id: string;
  provider: string;
  competitionCode: string;
  season: number;
  activePlayerCount: number;
  generation: number;
  lastTransition: 'backfilled' | 'advanced' | 'refreshed';
  summary: string;
  updatedAt: string;
};

export type ProviderPlayerCatalogLatest = {
  id: string;
  runId: string;
  publicationId: string;
  requestId: string | null;
  season: number;
  status: 'collecting' | 'applied' | 'superseded';
  observedPlayerCount: number;
  deactivatedPlayerCount: number;
  authoritativeRoleCount: number;
  removedRoleCount: number;
  rosteredRetiredCount: number;
  generation: number | null;
  reasonCode: string;
  summary: string;
  updatedAt: string;
};

export type ProviderPlayerCatalogCenter = {
  protected: boolean;
  healthy: boolean;
  authoritativeSnapshotActive: boolean;
  historicalSeasonRegressionBlocked: boolean;
  missingPlayersSoftDeactivated: boolean;
  exactRoleReplacementActive: boolean;
  physicalPlayerDeletionDisabled: boolean;
  collectingCount: number;
  appliedLast24h: number;
  supersededLast24h: number;
  deactivatedPlayersLast24h: number;
  removedRolesLast24h: number;
  rosteredRetiredTotal: number;
  totalReconciliationCount: number;
  latestReconciliationAt: string | null;
  head: ProviderPlayerCatalogHead | null;
  latest: ProviderPlayerCatalogLatest | null;
};

export type ProviderFixtureLifecycleHead = {
  id: string;
  fixtureIdFingerprint: string;
  currentState: 'scheduled' | 'live' | 'interrupted' | 'cancelled' | 'final';
  currentStatus: string;
  generation: number;
  lastTransition: 'backfilled' | 'created' | 'advanced' | 'refreshed' | 'final_corrected';
  summary: string;
  updatedAt: string;
};

export type ProviderFixtureLifecycleLatest = {
  id: string;
  runId: string;
  publicationId: string;
  requestId: string | null;
  requestedDate: string;
  status: 'collecting' | 'applied';
  observedFixtureCount: number;
  finalFixtureCount: number;
  createdFixtureCount: number;
  advancedFixtureCount: number;
  finalCorrectionCount: number;
  maxGeneration: number | null;
  reasonCode: string;
  summary: string;
  updatedAt: string;
};

export type ProviderFixtureLifecycleCenter = {
  protected: boolean;
  healthy: boolean;
  monotonicFixtureLifecycleActive: boolean;
  finalToNonFinalRegressionBlocked: boolean;
  finalGoalsPreserved: boolean;
  finalTeamIdentityLocked: boolean;
  physicalFixtureDeletionDisabled: boolean;
  collectingCount: number;
  appliedLast24h: number;
  createdFixturesLast24h: number;
  advancedFixturesLast24h: number;
  finalCorrectionsLast24h: number;
  totalReconciliationCount: number;
  latestReconciliationAt: string | null;
  head: ProviderFixtureLifecycleHead | null;
  latest: ProviderFixtureLifecycleLatest | null;
};

export type ProviderFixtureScoreLatest = {
  id: string;
  runId: string;
  publicationId: string;
  requestId: string | null;
  fixtureIdFingerprint: string;
  fixtureStatus: string;
  isFinal: boolean;
  status: 'collecting' | 'applied';
  observedScoreCount: number;
  homeScoreCount: number;
  awayScoreCount: number;
  retiredScoreCount: number;
  restoredScoreCount: number;
  generation: number | null;
  reasonCode: string;
  summary: string;
  updatedAt: string;
};

export type ProviderFixtureScoreCenter = {
  protected: boolean;
  healthy: boolean;
  authoritativeFixtureSnapshotActive: boolean;
  finalToProvisionalRegressionBlocked: boolean;
  missingFinalScoresSoftRetired: boolean;
  physicalScoreDeletionDisabled: boolean;
  twoTeamFinalCoverageRequired: boolean;
  collectingCount: number;
  appliedLast24h: number;
  finalAppliedLast24h: number;
  retiredScoresLast24h: number;
  restoredScoresLast24h: number;
  totalReconciliationCount: number;
  latestReconciliationAt: string | null;
  latest: ProviderFixtureScoreLatest | null;
};

export type ProviderFixtureScoreCoherenceHead = {
  id: string;
  fixtureIdFingerprint: string;
  scoreGeneration: number;
  fixtureLifecycleGeneration: number | null;
  fixtureLifecycleRevision: number | null;
  coherenceStatus: 'aligned' | 'stale' | 'missing';
  reasonCode: string;
  checkedAt: string | null;
};

export type ProviderFixtureScoreCoherenceEvent = {
  id: string;
  eventType: 'aligned' | 'stale' | 'missing';
  fixtureIdFingerprint: string;
  scoreGeneration: number;
  fixtureLifecycleGeneration: number | null;
  fixtureLifecycleRevision: number | null;
  coherenceStatus: 'aligned' | 'stale' | 'missing';
  reasonCode: string;
  createdAt: string;
};

export type ProviderFixtureScoreCoherenceCenter = {
  protected: boolean;
  healthy: boolean;
  causalFixtureScoreBindingActive: boolean;
  fixtureGenerationAdvanceInvalidatesScores: boolean;
  concurrentLifecycleChangeDetected: boolean;
  scoreValuesPreservedWhileStale: boolean;
  alignedCount: number;
  staleCount: number;
  missingCount: number;
  finalMissingCount: number;
  eventsLast24h: number;
  latestHead: ProviderFixtureScoreCoherenceHead | null;
  latestEvent: ProviderFixtureScoreCoherenceEvent | null;
};

export type ProviderScoreConsumptionGateEvent = {
  id: string;
  fixtureIdFingerprint: string;
  gateStatus: 'trusted' | 'blocked';
  reasonCode: string;
  scoreGeneration: number;
  fixtureLifecycleGeneration: number | null;
  createdAt: string;
};

export type ProviderScoreConsumptionGateCenter = {
  protected: boolean;
  healthy: boolean;
  officialResultConsumptionGateActive: boolean;
  staleScoresExcludedFromCalculations: boolean;
  blockedScoresCannotTriggerSubstitutions: boolean;
  scoreValuesPreservedWhileBlocked: boolean;
  trustedHeadCount: number;
  blockedHeadCount: number;
  staleHeadCount: number;
  missingHeadCount: number;
  blockedScoreCount: number;
  blockedMatchdayCount: number;
  officialFixtureRiskCount: number;
  eventsLast24h: number;
  latestEvent: ProviderScoreConsumptionGateEvent | null;
};

export type ProviderOfficialResultImpactEvent = {
  id: string;
  fixtureId: string;
  matchdayId: string;
  impactStatus: 'clear' | 'affected' | 'in_correction';
  reasonCode: string;
  assessmentGeneration: number;
  affectedSideCount: number;
  createdAt: string;
};

export type ProviderOfficialResultImpactCenter = {
  protected: boolean;
  healthy: boolean;
  preciseOfficialResultLineageActive: boolean;
  officialResultsNeverMutatedAutomatically: boolean;
  protectedCorrectionWorkflowAvailable: boolean;
  clearFixtureCount: number;
  affectedFixtureCount: number;
  inCorrectionFixtureCount: number;
  affectedMatchdayCount: number;
  eventsLast24h: number;
  latestEvent: ProviderOfficialResultImpactEvent | null;
};

export type ProviderOfficialResultRemediationItem = {
  headId: string;
  fixtureId: string;
  matchdayId: string;
  matchdayNumber: number;
  homeTeamName: string;
  awayTeamName: string;
  impactAssessmentGeneration: number;
  remediationGeneration: number;
  remediationStatus: 'open' | 'in_correction';
  causalStartCertified: boolean;
  correctionRunId: number | null;
  openedAt: string;
  startedAt: string | null;
  impactReasonCode: string;
};

export type ProviderOfficialResultRemediationCenter = {
  protected: boolean;
  healthy: boolean;
  raceSafeRemediationActive: boolean;
  staleAssessmentRejected: boolean;
  resultsNeverMutatedAutomatically: boolean;
  openCount: number;
  inCorrectionCount: number;
  resolvedCount: number;
  uncertifiedCorrectionCount: number;
  eventsLast24h: number;
  items: ProviderOfficialResultRemediationItem[];
};

export type ProviderOfficialResultLineageEvent = {
  id: string;
  fixtureId: string;
  matchdayId: string;
  lineageStatus: 'reopened' | 'assembling' | 'certified' | 'invalid';
  reasonCode: string;
  lineageGeneration: number;
  fixtureResultRevision: number;
  createdAt: string;
};

export type ProviderOfficialResultLineageCenter = {
  protected: boolean;
  healthy: boolean;
  officializationCommitBarrierActive: boolean;
  transientMissingLineageSuppressed: boolean;
  correctionSourceLinkCertified: boolean;
  certifiedFixtureCount: number;
  assemblingFixtureCount: number;
  invalidFixtureCount: number;
  reopenedFixtureCount: number;
  eventsLast24h: number;
  latestEvent: ProviderOfficialResultLineageEvent | null;
};

export type ProviderOfficialResultRemediationCompletionEvent = {
  id: string;
  fixtureId: string;
  matchdayId: string;
  eventType: 'pending' | 'certified' | 'invalid' | 'superseded' | 'revalidated';
  completionStatus: 'pending' | 'certified' | 'invalid' | 'superseded';
  resolutionMode: 'none' | 'auto_recovered' | 'correction_certified';
  reasonCode: string;
  remediationGeneration: number;
  completionGeneration: number;
  createdAt: string;
};

export type ProviderOfficialResultRemediationCompletionCenter = {
  protected: boolean;
  healthy: boolean;
  causalCompletionCertificateActive: boolean;
  resolvedOnlyAfterCertifiedEvidence: boolean;
  automaticRecoveryDistinguished: boolean;
  pendingCount: number;
  certifiedCount: number;
  invalidCount: number;
  supersededCount: number;
  autoRecoveredCount: number;
  correctionCertifiedCount: number;
  uncertifiedResolvedCount: number;
  eventsLast24h: number;
  latestEvent: ProviderOfficialResultRemediationCompletionEvent | null;
};


export type ProviderMatchdayProgressionGateEvent = {
  id: string;
  matchdayId: string;
  matchdayNumber: number;
  eventType: 'clear' | 'blocked' | 'affected' | 'revalidated';
  gateStatus: 'clear' | 'blocked' | 'affected';
  reasonCode: string;
  gateGeneration: number;
  currentOfficializationRunId: string | null;
  currentProgressionRunId: string | null;
  unsafeFixtureCount: number;
  priorUnsafeProgressionCount: number;
  createdAt: string;
};

export type ProviderMatchdayProgressionGateCenter = {
  protected: boolean;
  healthy: boolean;
  causalProgressionBarrierActive: boolean;
  legacyProgressionBypassBlocked: boolean;
  priorMatchdayChainProtected: boolean;
  clearMatchdayCount: number;
  blockedMatchdayCount: number;
  affectedMatchdayCount: number;
  unsafeProgressionCount: number;
  eventsLast24h: number;
  latestEvent: ProviderMatchdayProgressionGateEvent | null;
};

export type ProviderSeasonCompletionGateEvent = {
  id: string;
  eventType: 'clear' | 'blocked' | 'affected' | 'revalidated';
  gateStatus: 'clear' | 'blocked' | 'affected';
  reasonCode: string;
  gateGeneration: number;
  currentCompletionRunId: string | null;
  finalMatchdayId: string | null;
  finalProgressionRunId: string | null;
  unsafeMatchdayCount: number;
  missingGateCount: number;
  mismatchedProgressionCount: number;
  createdAt: string;
};

export type ProviderSeasonCompletionGateCenter = {
  protected: boolean;
  healthy: boolean;
  causalSeasonCompletionBarrierActive: boolean;
  legacySeasonCompletionBypassBlocked: boolean;
  progressionChainLocked: boolean;
  gateStatus: 'clear' | 'blocked' | 'affected';
  reasonCode: string;
  completionRunId: string | null;
  finalMatchdayId: string | null;
  finalProgressionRunId: string | null;
  matchdayCount: number;
  clearMatchdayCount: number;
  unsafeMatchdayCount: number;
  missingGateCount: number;
  mismatchedProgressionCount: number;
  completionAffected: boolean;
  eventsLast24h: number;
  latestEvent: ProviderSeasonCompletionGateEvent | null;
};


export type ProviderSeasonBootstrapCenter = {
  protected: boolean;
  applicable: boolean;
  healthy: boolean;
  affected: boolean;
  status: 'waiting' | 'catalog_ready' | 'ready' | 'affected';
  reasonCode: string;
  season: number | null;
  catalogReady: boolean;
  fixturesReady: boolean;
  certified: boolean;
  certificateId: number | null;
  bootstrapHash: string | null;
  catalogGeneration: number | null;
  catalogPlayerCount: number;
  fixtureCount: number;
  matchdayCount: number;
  fixtureTeamCount: number;
};


export type ProviderCompetitionStartCenter = {
  protected: boolean;
  applicable: boolean;
  healthy: boolean;
  affected: boolean;
  status: 'waiting' | 'ready' | 'official' | 'affected';
  reasonCode: string;
  started: boolean;
  ready: boolean;
  certified: boolean;
  certificateId: number | null;
  startHash: string | null;
  season: number | null;
  fantasyFixtureCount: number;
  fantasyMatchdayCount: number;
  fantasyTeamCount: number;
};

export type ProviderReliabilityModelCenter = {
  protected: boolean;
  modelClosed: boolean;
  healthy: boolean;
  schemaCertified: boolean;
  operationalHealthy: boolean;
  status: 'certified' | 'attention' | 'affected';
  reasonCode: string;
  modelKey: string;
  modelVersion: number;
  applicationVersion: string;
  certifiedAt: string | null;
  schemaFingerprint: string | null;
  storedSchemaFingerprint: string | null;
  fingerprintStable: boolean;
  checkCount: number;
  passedCount: number;
};

export type ApplicationIntegrityModelCenter = {
  protected: boolean;
  modelClosed: boolean;
  healthy: boolean;
  schemaCertified: boolean;
  status: 'certified' | 'affected';
  reasonCode: string;
  modelKey: string;
  modelVersion: number;
  applicationVersion: string;
  certifiedAt: string | null;
  schemaFingerprint: string | null;
  storedSchemaFingerprint: string | null;
  fingerprintStable: boolean;
  checkCount: number;
  passedCount: number;
};

export type ApplicationRolloutModelCenter = {
  protected: boolean;
  healthy: boolean;
  active: boolean;
  status: 'active' | 'paused' | 'killed' | 'completed' | 'affected';
  reasonCode: string;
  environment: string;
  releaseVersion: string | null;
  stage: 'pilot' | 'canary' | 'general' | 'completed' | null;
  exposurePercentage: number | null;
  rolloutGeneration: number | null;
  killSwitchActive: boolean;
  planFingerprintStable: boolean;
  latestHealthVerdict: 'healthy' | 'unhealthy' | null;
  latestErrorRateBps: number | null;
  latestCrashCount: number | null;
  latestHealthAt: string | null;
  startedAt: string | null;
  promotedAt: string | null;
};

export type ApplicationOperationalTelemetryCenter = {
  protected: boolean;
  healthy: boolean;
  authoritative: boolean;
  status: 'active' | 'degraded' | 'critical' | 'affected';
  reasonCode: string;
  environment: string;
  sourceKey: string | null;
  sourceGeneration: number | null;
  telemetryGeneration: number | null;
  lastWindowSequence: number | null;
  lastWindowStartedAt: string | null;
  lastWindowEndedAt: string | null;
  latestVerdict: 'healthy' | 'degraded' | 'critical' | null;
  latestErrorRateBps: number | null;
  latestCrashCount: number | null;
  latestP95LatencyMs: number | null;
  latestExposurePercentage: number | null;
  latestReleaseVersion: string | null;
  autoRollbackEnabled: boolean;
  autoRollbackTriggered: boolean;
  fingerprintStable: boolean;
};

export type ApplicationOperationalOutboxCenter = {
  protected: boolean;
  healthy: boolean;
  status: 'active' | 'attention' | 'dead_letter' | 'affected';
  reasonCode: string;
  environment: string;
  captureReady: boolean;
  messageCount: number;
  destinationCount: number;
  pendingCount: number;
  leasedCount: number;
  retryCount: number;
  deliveredCount: number;
  deadLetterCount: number;
  expiredLeaseCount: number;
  lastSequence: number;
  sequenceGapCount: number;
  fingerprintMismatchCount: number;
  oldestPendingAt: string | null;
  lastDeliveredAt: string | null;
  lastDeadLetterAt: string | null;
};

export type ApplicationOperationalConsumerDeliveryCenter = {
  protected: boolean;
  healthy: boolean;
  authoritative: boolean;
  status: 'active' | 'attention' | 'affected';
  reasonCode: string;
  environment: string;
  consumerCount: number;
  receiptCount: number;
  liveReceiptCount: number;
  adoptedReceiptCount: number;
  expectedReceiptCount: number;
  replayRequestCount: number;
  sequenceGapCount: number;
  fingerprintMismatchCount: number;
  receiptConsistencyMismatchCount: number;
  lastAcknowledgedSequence: number;
  lastAcknowledgedAt: string | null;
};

export type ApplicationOperationalDeliveryAuditCenter = {
  protected: boolean;
  healthy: boolean;
  fresh: boolean;
  status: 'certified' | 'stale' | 'attention' | 'affected';
  reasonCode: string;
  environment: string;
  auditGeneration: number;
  auditedThroughSequence: number;
  currentLastSequence: number;
  messageCount: number;
  expectedDeliveryCount: number;
  deliveryCount: number;
  receiptCount: number;
  sequenceGapCount: number;
  consistencyMismatchCount: number;
  fingerprintMismatchCount: number;
  headMismatchCount: number;
  deadLetterCount: number;
  affectedDestinationCount: number;
  lastAuditAt: string | null;
};


export type ApplicationDisasterRecoveryCenter = {
  protected: boolean;
  healthy: boolean;
  fresh: boolean;
  status: 'certified' | 'stale' | 'affected';
  reasonCode: string;
  environment: string;
  checkpointGeneration: number;
  drillGeneration: number;
  activeVersion: string | null;
  releaseGeneration: number;
  rolloutGeneration: number;
  exposurePercentage: number;
  telemetryGeneration: number;
  outboxSequence: number;
  consumerSequence: number;
  auditedSequence: number;
  componentCount: number;
  lastCheckpointAt: string | null;
  lastDrillAt: string | null;
};

export type ApplicationPhysicalBackupCenter = {
  protected: boolean;
  healthy: boolean;
  fresh: boolean;
  status: 'certified' | 'stale' | 'affected';
  reasonCode: string;
  environment: string;
  backupGeneration: number;
  custodySequence: number;
  rehearsalGeneration: number;
  activeVersion: string | null;
  checkpointGeneration: number;
  artifactSizeBytes: number;
  checksumVerified: boolean;
  custodyComplete: boolean;
  restoreVerified: boolean;
  lastArtifactAt: string | null;
  lastRehearsalAt: string | null;
};

export type ApplicationServiceReturnCenter = {
  protected: boolean;
  healthy: boolean;
  fresh: boolean;
  status: 'certified' | 'recovery' | 'affected';
  reasonCode: string;
  environment: string;
  mode: 'active' | 'recovery' | 'affected';
  recoveryGeneration: number;
  activeVersion: string | null;
  checkCount: number;
  requiredCheckCount: number;
  writesAllowed: boolean;
  workersAllowed: boolean;
  trafficPercentage: number;
  lastRecoveryStartedAt: string | null;
  lastCertifiedAt: string | null;
};

export type ApplicationProductionReadinessCenter = {
  protected: boolean;
  healthy: boolean;
  fresh: boolean;
  status: 'certified' | 'pending' | 'affected';
  reasonCode: string;
  environment: string;
  readinessGeneration: number;
  activeVersion: string | null;
  checkCount: number;
  requiredCheckCount: number;
  goLiveAllowed: boolean;
  fingerprintStable: boolean;
  certifiedAt: string | null;
  affectedAt: string | null;
};

export type ApplicationReleaseModelCenter = {
  protected: boolean;
  healthy: boolean;
  active: boolean;
  status: 'active' | 'rollback' | 'affected';
  reasonCode: string;
  environment: string;
  activeVersion: string | null;
  previousVersion: string | null;
  minSupportedVersion: string | null;
  maxSupportedVersion: string | null;
  releaseGeneration: number | null;
  rollbackActive: boolean;
  schemaCertified: boolean;
  fingerprintStable: boolean;
  bundleFingerprint: string | null;
  certifiedAt: string | null;
  activatedAt: string | null;
};

export type LeagueSeasonOfficialSnapshotCenter = {
  protected: boolean;
  published: boolean;
  healthy: boolean;
  status: 'pending' | 'official' | 'affected';
  reasonCode: string;
  affected: boolean;
  snapshotId: string | null;
  snapshotHash: string | null;
  standingsHash: string | null;
  completionRunId: string | null;
  completionGateGeneration: number | null;
  completionGateFingerprint: string | null;
  season: string | null;
  champion: LeagueSeasonChampion | null;
  podium: LeagueStanding[];
  finalStandings: LeagueStanding[];
  officializedAt: string | null;
  affectedAt: string | null;
};

export type LeagueProviderRecoveryCenter = {
  protected: boolean;
  healthy: boolean;
  pendingCount: number;
  runningCount: number;
  completedLast24h: number;
  failedLast24h: number;
  watchdogActive: boolean;
  staleRunningCount: number;
  timedOutLast24h: number;
  latestWatchdogAt: string | null;
  workerHeartbeatActive: boolean;
  runningHeartbeatFresh: boolean;
  heartbeatGraceSeconds: number | null;
  latestHeartbeatAt: string | null;
  latestProgress: ProviderRecoveryProgress | null;
  retryCenter: ProviderAutomaticRetryCenter | null;
  circuitBreaker: ProviderRecoveryCircuitBreakerCenter | null;
  outcomeVerification: ProviderRecoveryOutcomeVerificationCenter | null;
  workerFencing: ProviderWorkerFencingCenter | null;
  latestRequestAt: string | null;
  canRequest: boolean;
  recoverableIncident: ProviderRecoverableIncident | null;
  requests: ProviderRecoveryRequest[];
};

export type ProviderRecoveryRequestOutcome = {
  requestId: string;
  incidentId: string;
  status: ProviderRecoveryRequestStatus;
  revision: number;
  attempt: number;
  recoveryRunId: string | null;
  reused: boolean;
};

export type LeagueProviderSyncHealth = {
  provider: string;
  protected: boolean;
  healthy: boolean;
  status: 'healthy' | 'attention' | 'idle';
  failedLast24h: number;
  stuckRunCount: number;
  lastRunAt: string | null;
  lastSuccessfulAt: string | null;
  latestDataAt: string | null;
  actions: ProviderSyncActionState[];
  dataQuality: LeagueProviderDataQuality | null;
  incidentCenter: LeagueProviderIncidentCenter | null;
  recoveryCenter: LeagueProviderRecoveryCenter | null;
  payloadContracts: ProviderPayloadContractCenter | null;
  deliveryIntegrity: ProviderDeliveryIntegrityCenter | null;
  atomicPublication: ProviderAtomicPublicationCenter | null;
  semanticScope: ProviderSemanticScopeCenter | null;
  publicationWatermark: ProviderScopeWatermarkCenter | null;
  playerCatalogReconciliation: ProviderPlayerCatalogCenter | null;
  fixtureLifecycleReconciliation: ProviderFixtureLifecycleCenter | null;
  fixtureScoreReconciliation: ProviderFixtureScoreCenter | null;
  fixtureScoreCoherence: ProviderFixtureScoreCoherenceCenter | null;
  scoreConsumptionGate: ProviderScoreConsumptionGateCenter | null;
  officialResultImpact: ProviderOfficialResultImpactCenter | null;
  officialResultRemediation: ProviderOfficialResultRemediationCenter | null;
  officialResultLineage: ProviderOfficialResultLineageCenter | null;
  officialResultRemediationCompletion:
    ProviderOfficialResultRemediationCompletionCenter | null;
  matchdayProgressionGate: ProviderMatchdayProgressionGateCenter | null;
  seasonCompletionGate: ProviderSeasonCompletionGateCenter | null;
  seasonOfficialSnapshot: LeagueSeasonOfficialSnapshotCenter | null;
  providerSeasonBootstrap: ProviderSeasonBootstrapCenter | null;
  providerCompetitionStart: ProviderCompetitionStartCenter | null;
  providerReliabilityModel: ProviderReliabilityModelCenter | null;
  applicationIntegrityModel: ApplicationIntegrityModelCenter | null;
  applicationReleaseModel: ApplicationReleaseModelCenter | null;
  applicationRolloutModel: ApplicationRolloutModelCenter | null;
  applicationOperationalTelemetry: ApplicationOperationalTelemetryCenter | null;
  applicationOperationalOutbox: ApplicationOperationalOutboxCenter | null;
  applicationOperationalConsumerDelivery:
    ApplicationOperationalConsumerDeliveryCenter | null;
  applicationOperationalDeliveryAudit:
    ApplicationOperationalDeliveryAuditCenter | null;
  applicationDisasterRecovery: ApplicationDisasterRecoveryCenter | null;
  applicationPhysicalBackup: ApplicationPhysicalBackupCenter | null;
  applicationServiceReturn: ApplicationServiceReturnCenter | null;
  applicationProductionReadiness: ApplicationProductionReadinessCenter | null;
};

export type LeagueOperationsCenter = {
  leagueId: string;
  leagueName: string;
  leagueStatus: LeagueSummary['status'];
  season: string | null;
  competitionStartedAt: string | null;
  isOwner: boolean;
  isDirector: boolean;
  generatedAt: string;
  focusMatchday: LeagueOperationFocusMatchday | null;
  nextLineupMatchday: LeagueOperationLineupMatchday | null;
  providerSync: LeagueProviderSyncHealth | null;
};

export type LeagueLineupReminderOutcome = {
  matchdayId: string;
  matchdayNumber: number;
  targetCount: number;
  sentCount: number;
  alreadySentCount: number;
};

export type PostponedFixtureResolution = {
  id: string;
  decision: 'political_score';
  politicalScore: number;
  reason: string;
  decidedAt: string;
  decidedBy: string;
  revision: number;
  stateFingerprint: string | null;
  protected: boolean;
};

export type PostponementIntegrity = {
  healthy: boolean;
  activeResolutionCount: number;
  certifiedActionCount: number;
  invalidResolutionCount: number;
  invalidActionCount: number;
  duplicateActiveCount: number;
  providerFinalContinuityReady: boolean;
};

export type PostponedFixtureIssue = {
  providerFixtureId: string;
  externalFixtureId: string;
  matchdayId: string;
  matchdayNumber: number;
  kickoffAt: string;
  status: string;
  homeTeam: string;
  awayTeam: string;
  locked: boolean;
  resolution: PostponedFixtureResolution | null;
};

export type LeaguePostponementCenter = {
  leagueId: string;
  leagueName: string;
  isOwner: boolean;
  issueCount: number;
  resolvedCount: number;
  unresolvedCount: number;
  issues: PostponedFixtureIssue[];
  protected: boolean;
  idempotencyReady: boolean;
  revisionReady: boolean;
  certifiedActionCount: number;
  lastCertifiedAt: string | null;
  integrity: PostponementIntegrity;
};

export type MatchdayResultStatus =
  | 'upcoming'
  | 'live'
  | 'pending'
  | 'ready'
  | 'official';

export type FixtureResultStatus =
  | 'waiting'
  | 'provisional'
  | 'ready'
  | 'official';

export type LeagueFixtureResult = {
  id: string;
  homeTeamId: string;
  homeTeamName: string;
  awayTeamId: string;
  awayTeamName: string;
  homePoints: number | null;
  awayPoints: number | null;
  homeBasePoints: number | null;
  awayBasePoints: number | null;
  homeDefenseModifier: number;
  awayDefenseModifier: number;
  homeBonusApplied: number;
  homeGoalMarginBonus: number;
  awayGoalMarginBonus: number;
  homeGoals: number | null;
  awayGoals: number | null;
  homeCountedPlayers: number;
  awayCountedPlayers: number;
  homeReady: boolean;
  awayReady: boolean;
  finalizedAt: string | null;
  canCorrect: boolean;
  revision: number;
  correctionReason: string | null;
  correctedAt: string | null;
  status: FixtureResultStatus;
  providerImpactStatus: 'clear' | 'affected' | 'in_correction' | null;
  providerImpactGeneration: number | null;
  providerImpactReasonCode: string | null;
  providerRemediationStatus: 'open' | 'in_correction' | null;
  providerRemediationRequired: boolean;
  providerCausalStartCertified: boolean;
};

export type LeagueMatchdayResult = {
  id: string;
  number: number;
  startsAt: string;
  endsAt: string | null;
  fixtureCount: number;
  readyCount: number;
  officialCount: number;
  status: MatchdayResultStatus;
  canFinalize: boolean;
  canReopen: boolean;
  fixtures: LeagueFixtureResult[];
};

export type LeagueResultsCenter = {
  leagueId: string;
  leagueName: string;
  isOwner: boolean;
  competitionStartedAt: string | null;
  goalThreshold: number;
  goalStep: number;
  goalBandsEnabled: boolean;
  goalBands: GoalBands;
  goalMarginEnabled: boolean;
  goalMargin: number;
  matchdays: LeagueMatchdayResult[];
};

export type TeamDashboardTransaction = {
  id: string;
  type: 'auction_purchase' | 'market_purchase' | 'release' | 'trade';
  athleteId: string;
  athleteName: string;
  creditDelta: number;
  createdAt: string;
};

export type TeamDashboardMatch = {
  fixtureId: string;
  matchdayId: string;
  matchdayNumber: number;
  startsAt: string;
  home: boolean;
  opponentId: string;
  opponentName: string;
  myPoints?: number | null;
  opponentPoints?: number | null;
  myGoals?: number | null;
  opponentGoals?: number | null;
};

export type TeamDashboard = {
  teamId: string;
  teamName: string;
  creditsRemaining: number;
  startingCredits: number;
  creditsSpent: number;
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
  pointsFor: number;
  leaguePoints: number;
  nextMatch: TeamDashboardMatch | null;
  lastMatch: TeamDashboardMatch | null;
  recentTransactions: TeamDashboardTransaction[];
};

export type MatchupFormResult = 'W' | 'D' | 'L';

export type MatchupTeam = {
  id: string;
  name: string;
  managerName: string;
  position: number;
  played: number;
  won: number;
  drawn: number;
  lost: number;
  goalsFor: number;
  goalsAgainst: number;
  pointsFor: number;
  leaguePoints: number;
  recentForm: MatchupFormResult[];
  unbeatenStreak: number;
};

export type MatchupLineupStatus =
  | 'submitted'
  | 'carried'
  | 'draft'
  | 'missing';

export type MatchupFixtureStatus =
  | 'upcoming'
  | 'live'
  | 'pending'
  | 'final';

export type MatchupFixture = {
  id: string;
  matchdayId: string;
  matchdayNumber: number;
  startsAt: string;
  locksAt: string;
  endsAt: string | null;
  status: MatchupFixtureStatus;
  homeTeamId: string;
  awayTeamId: string;
  myHome: boolean;
  myPoints: number | null;
  opponentPoints: number | null;
  myGoals: number | null;
  opponentGoals: number | null;
  myLineupStatus: MatchupLineupStatus;
  opponentLineupStatus: MatchupLineupStatus;
  lineupsLocked: boolean;
};

export type MatchupRecord = {
  played: number;
  myWins: number;
  draws: number;
  opponentWins: number;
  myGoals: number;
  opponentGoals: number;
  myPoints: number;
  opponentPoints: number;
};

export type MatchupAllTimeRecord = MatchupRecord & {
  seasons: number;
  leader: 'me' | 'opponent' | 'level';
};

export type MatchupMeeting = {
  fixtureId: string;
  leagueId: string;
  season: string | null;
  matchdayNumber: number;
  startsAt: string;
  homeTeamName: string;
  awayTeamName: string;
  myHome: boolean;
  myPoints: number;
  opponentPoints: number;
  myGoals: number;
  opponentGoals: number;
  outcome: MatchupFormResult;
};

export type LeagueMatchupCenter = {
  leagueId: string;
  leagueName: string;
  season: string | null;
  generatedAt: string;
  myTeam: MatchupTeam;
  opponent: MatchupTeam | null;
  fixture: MatchupFixture | null;
  currentSeason: MatchupRecord;
  allTime: MatchupAllTimeRecord;
  lastMeetings: MatchupMeeting[];
};

export type MarketPlayer = RosterPlayer & {
  teamId: string | null;
};

export type MarketTeam = {
  id: string;
  name: string;
  creditsRemaining: number;
  players: MarketPlayer[];
};

export type TradeOfferStatus =
  | 'pending'
  | 'accepted'
  | 'declined'
  | 'canceled'
  | 'expired';

export type TradeOfferSummary = {
  id: string;
  proposerTeamId: string;
  proposerTeamName: string;
  recipientTeamId: string;
  recipientTeamName: string;
  status: TradeOfferStatus;
  proposerCredits: number;
  recipientCredits: number;
  offeredPlayers: MarketPlayer[];
  requestedPlayers: MarketPlayer[];
  message: string | null;
  expiresAt: string;
  createdAt: string;
};

export type MarketIntegrityTeam = {
  teamId: string;
  teamName: string;
  creditsRemaining: number;
  expectedCredits: number;
  creditDifference: number;
  creditOk: boolean;
  rosterCount: number;
  rosterSize: number;
  rosterOk: boolean;
  minimumReserve: number;
  reserveOk: boolean;
  transactionCount: number;
};

export type MarketIntegrity = {
  version: number;
  leagueId: string;
  checkedAt: string;
  ok: boolean;
  issueCount: number;
  expiredOffersClosed: number;
  duplicateActivePlayers: number;
  rosterLeagueMismatches: number;
  transactionLeagueMismatches: number;
  invalidPendingTrades: number;
  tradeSafetyEnabled?: boolean;
  pendingReservedOffers?: number;
  reservedTradeCredits?: number;
  orphanPlayerReservations?: number;
  orphanCreditReservations?: number;
  overcommittedTradeTeams?: number;
  invalidProjectedTrades?: number;
  marketAuctionSafetyEnabled?: boolean;
  auctionLockedAthletes?: number;
  marketAuctionConflicts?: number;
  soldAuctionLedgerMismatches?: number;
  marketModelClosed?: boolean;
  protectedMutationTables?: number;
  unsafeDirectPolicies?: number;
  unsafeAuthenticatedDmlGrants?: number;
  rpcOnlyMutations?: boolean;
  teams: MarketIntegrityTeam[];
};

export type MarketDashboard = {
  marketOpen: boolean;
  minimumPrice: number;
  releaseRefundPercent: number;
  myTeam: MarketTeam | null;
  teams: MarketTeam[];
  freeAgents: MarketPlayer[];
  offers: TradeOfferSummary[];
  integrity: MarketIntegrity | null;
};

export type LeagueSettings = {
  marketOpen: boolean;
  marketMinimumPrice: number;
  releaseRefundPercent: number;
  maxSubstitutions: number;
  defenseModifierEnabled: boolean;
  defenseModifierMinDefenders: number;
  goalThreshold: number;
  goalStep: number;
  goalBandsEnabled: boolean;
  goalBands: GoalBands;
  goalMarginEnabled: boolean;
  goalMargin: number;
  standingsTiebreaker: StandingsTiebreaker;
  homeBonus: number;
  bonusGoal: number;
  bonusAssist: number;
  bonusPenaltySaved: number;
  malusYellowCard: number;
  malusRedCard: number;
  malusPenaltyMissed: number;
  malusGoalConceded: number;
  rosterGoalkeepers: number;
  rosterDefenders: number;
  rosterMidfielders: number;
  rosterAttackers: number;
};

export type LeagueRuleRevision = {
  id: string;
  revision: number;
  reason: string;
  changedKeys: string[];
  changedAt: string;
  changedBy: string;
};

export type LeagueRulebook = {
  leagueId: string;
  leagueName: string;
  mode: LeagueMode;
  status: LeagueSummary['status'];
  season: string | null;
  teamLimit: number;
  startingCredits: number;
  rosterSize: number;
  isDirector: boolean;
  currentRevision: number;
  updatedAt: string;
  settings: LeagueSettings;
  revisions: LeagueRuleRevision[];
};

export type GoalBands = [
  number,
  number,
  number,
  number,
  number,
  number,
];

export type DefenseModifierBreakdown = {
  enabled: boolean;
  eligible: boolean;
  minimumDefenders: number;
  defenderCount: number;
  averageRating: number | null;
  bonus: number;
};

export type PlayerLiveScore = {
  id: string;
  role: string;
  name: string;
  status: string;
  score: string;
  highlighted?: boolean;
  isFinal?: boolean;
  scoreOrigin?: 'provider' | 'political' | null;
  isSubstitute?: boolean;
  replacedPlayerName?: string | null;
  blockedReason?:
    | 'awaiting_score'
    | 'limit_reached'
    | 'no_compatible_bench'
    | null;
};

export type LiveMatchStatus = 'upcoming' | 'live' | 'pending' | 'final';

export type LiveTeamScore = {
  teamId: string;
  name: string;
  points: number | null;
  basePoints: number | null;
  defenseModifier: DefenseModifierBreakdown;
  homeBonus: number;
  goals: number | null;
  countedPlayers: number;
  ready: boolean;
};

export type LiveMatchCenter = {
  leagueId: string;
  leagueName: string;
  mode: LeagueMode;
  status: LiveMatchStatus;
  fixtureId: string;
  myTeamId: string;
  lineupOrigin: 'manager' | 'carried' | 'missing';
  lineupSourceMatchdayNumber: number | null;
  substitutions: {
    used: number;
    limit: number;
    unavailableStarters: number;
    applied: boolean;
  };
  goalMargin: {
    enabled: boolean;
    minimum: number;
    applied: boolean;
    homeBonus: number;
    awayBonus: number;
  };
  goalBands: {
    enabled: boolean;
    thresholds: GoalBands;
  };
  matchday: {
    id: string;
    number: number;
    startsAt: string;
    locksAt: string;
    endsAt: string | null;
  };
  home: LiveTeamScore;
  away: LiveTeamScore;
  players: PlayerLiveScore[];
};

export type NotificationKind =
  | 'auction'
  | 'trade'
  | 'lineup'
  | 'result'
  | 'market'
  | 'league'
  | 'system';

export type AppNotification = {
  id: string;
  leagueId: string | null;
  kind: NotificationKind;
  title: string;
  body: string;
  actionScreen: AppScreen | null;
  metadata: Record<string, unknown>;
  readAt: string | null;
  createdAt: string;
  revision: number;
  stateFingerprint: string | null;
  protected: boolean;
};

export type NotificationCenterState = {
  notifications: AppNotification[];
  unreadCount: number;
  totalCount: number;
  protected: boolean;
  certifiedActionCount: number;
  lastCertifiedAt: string | null;
};

export type PushNotificationDevice = {
  id: string;
  platform: 'ios' | 'android';
  deviceName: string | null;
  appVersion: string | null;
  enabled: boolean;
  registeredAt: string;
  lastSeenAt: string;
  revision: number;
  tokenFingerprint: string | null;
};

export type PushNotificationPreferences = {
  pushEnabled: boolean;
  auctionTradeEnabled: boolean;
  lineupEnabled: boolean;
  resultsEnabled: boolean;
  leagueEnabled: boolean;
  systemEnabled: boolean;
  activeDeviceCount: number;
  devices: PushNotificationDevice[];
  revision: number;
  protected: boolean;
  preferenceFingerprint: string | null;
  certifiedActionCount: number;
  lastCertifiedAt: string | null;
};

export type PushNotificationTarget = {
  notificationId: string | null;
  leagueId: string | null;
  actionScreen: AppScreen | null;
};

export type PlayerDirectoryItem = {
  id: string;
  name: string;
  clubName: string;
  shirtNumber: number | null;
  role: string;
  teamId: string | null;
  teamName: string | null;
  purchasePrice: number | null;
  appearances: number;
  averageRating: number | null;
  averageFantasyScore: number | null;
  goals: number;
  assists: number;
  yellowCards: number;
  redCards: number;
  lastScores: number[];
};
