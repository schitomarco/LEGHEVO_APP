import { supabase } from '../lib/supabase';
import type {
  LeagueAccessSession,
  LeagueCompetitionLifecycle,
  LeagueManagementState,
  LeaguePermissionState,
  LeagueRoleAuditEvent,
  LeagueRoleControlState,
  LeagueRoleIntegrity,
  LeagueRoleMatrixMember,
  LeagueRoleSecurity,
} from '../types';

type ActionOutcome = {
  error?: string;
};

export async function fetchLeagueAccessSession(
  leagueId: string,
): Promise<LeagueAccessSession> {
  if (!supabase) {
    throw new Error('Il collegamento al backend non è configurato.');
  }

  const { data, error } = await supabase.rpc('get_league_access_session', {
    p_league_id: leagueId,
  });

  if (error) {
    throw new Error(translateManagementError(error.message));
  }

  return normalizeAccessSession(data);
}

export async function fetchLeagueManagementState(
  leagueId: string,
): Promise<LeagueManagementState> {
  if (!supabase) {
    throw new Error('Il collegamento al backend non è configurato.');
  }

  // The later management-state revisions also aggregate release-readiness and
  // disaster-recovery diagnostics. Those checks are useful for deployment
  // certification, but they can exceed the interactive request timeout on a
  // cold project. Revision 14 contains the complete league-management domain
  // state needed by this screen and keeps navigation responsive.
  const interactiveState = await supabase.rpc(
    'get_league_management_state_v14',
    { p_league_id: leagueId },
  );
  if (!interactiveState.error) {
    return normalizeManagementState(interactiveState.data);
  }
  if (!isMissingManagementFunction(
    interactiveState.error.message,
    'get_league_management_state_v14',
  )) {
    throw new Error(translateManagementError(interactiveState.error.message));
  }

  const latestV28 = await supabase.rpc('get_league_management_state_v28', {
    p_league_id: leagueId,
  });
  if (!latestV28.error) {
    return normalizeManagementState(latestV28.data);
  }
  if (!isMissingManagementFunction(
    latestV28.error.message,
    'get_league_management_state_v28',
  )) {
    throw new Error(translateManagementError(latestV28.error.message));
  }

  const latestV27 = await supabase.rpc('get_league_management_state_v27', {
    p_league_id: leagueId,
  });

  if (!latestV27.error) {
    return normalizeManagementState(latestV27.data);
  }
  if (!isMissingManagementFunction(
    latestV27.error.message,
    'get_league_management_state_v27',
  )) {
    throw new Error(translateManagementError(latestV27.error.message));
  }

  const latestV26 = await supabase.rpc('get_league_management_state_v26', {
    p_league_id: leagueId,
  });
  if (!latestV26.error) {
    return normalizeManagementState(latestV26.data);
  }
  if (!isMissingManagementFunction(
    latestV26.error.message,
    'get_league_management_state_v26',
  )) {
    throw new Error(translateManagementError(latestV26.error.message));
  }

  const latestV25 = await supabase.rpc('get_league_management_state_v25', {
    p_league_id: leagueId,
  });
  if (!latestV25.error) {
    return normalizeManagementState(latestV25.data);
  }
  if (!isMissingManagementFunction(
    latestV25.error.message,
    'get_league_management_state_v25',
  )) {
    throw new Error(translateManagementError(latestV25.error.message));
  }

  const latest = await supabase.rpc('get_league_management_state_v24', {
    p_league_id: leagueId,
  });

  if (!latest.error) {
    return normalizeManagementState(latest.data);
  }

  const missingLatest = isMissingManagementFunction(
    latest.error.message,
    'get_league_management_state_v24',
  );
  if (!missingLatest) {
    throw new Error(translateManagementError(latest.error.message));
  }

  const fallbackV23 = await supabase.rpc('get_league_management_state_v23', {
    p_league_id: leagueId,
  });
  if (!fallbackV23.error) {
    return normalizeManagementState(fallbackV23.data);
  }
  if (!isMissingManagementFunction(
    fallbackV23.error.message,
    'get_league_management_state_v23',
  )) {
    throw new Error(translateManagementError(fallbackV23.error.message));
  }

  const fallbackV22 = await supabase.rpc('get_league_management_state_v22', {
    p_league_id: leagueId,
  });
  if (!fallbackV22.error) {
    return normalizeManagementState(fallbackV22.data);
  }
  if (!isMissingManagementFunction(
    fallbackV22.error.message,
    'get_league_management_state_v22',
  )) {
    throw new Error(translateManagementError(fallbackV22.error.message));
  }

  const fallbackV21 = await supabase.rpc('get_league_management_state_v21', {
    p_league_id: leagueId,
  });
  if (!fallbackV21.error) {
    return normalizeManagementState(fallbackV21.data);
  }

  if (!isMissingManagementFunction(
    fallbackV21.error.message,
    'get_league_management_state_v21',
  )) {
    throw new Error(translateManagementError(fallbackV21.error.message));
  }

  const fallbackV20 = await supabase.rpc('get_league_management_state_v20', {
    p_league_id: leagueId,
  });
  if (!fallbackV20.error) {
    return normalizeManagementState(fallbackV20.data);
  }

  if (!isMissingManagementFunction(
    fallbackV20.error.message,
    'get_league_management_state_v20',
  )) {
    throw new Error(translateManagementError(fallbackV20.error.message));
  }

  const fallbackV19 = await supabase.rpc('get_league_management_state_v19', {
    p_league_id: leagueId,
  });
  if (!fallbackV19.error) {
    return normalizeManagementState(fallbackV19.data);
  }

  if (!isMissingManagementFunction(
    fallbackV19.error.message,
    'get_league_management_state_v19',
  )) {
    throw new Error(translateManagementError(fallbackV19.error.message));
  }

  const fallbackV18 = await supabase.rpc('get_league_management_state_v18', {
    p_league_id: leagueId,
  });
  if (!fallbackV18.error) {
    return normalizeManagementState(fallbackV18.data);
  }

  if (!isMissingManagementFunction(
    fallbackV18.error.message,
    'get_league_management_state_v18',
  )) {
    throw new Error(translateManagementError(fallbackV18.error.message));
  }

  const fallbackV17 = await supabase.rpc('get_league_management_state_v17', {
    p_league_id: leagueId,
  });
  if (!fallbackV17.error) {
    return normalizeManagementState(fallbackV17.data);
  }

  if (!isMissingManagementFunction(
    fallbackV17.error.message,
    'get_league_management_state_v17',
  )) {
    throw new Error(translateManagementError(fallbackV17.error.message));
  }

  const fallbackV16 = await supabase.rpc('get_league_management_state_v16', {
    p_league_id: leagueId,
  });
  if (!fallbackV16.error) {
    return normalizeManagementState(fallbackV16.data);
  }

  if (!isMissingManagementFunction(
    fallbackV16.error.message,
    'get_league_management_state_v16',
  )) {
    throw new Error(translateManagementError(fallbackV16.error.message));
  }

  const fallbackV15 = await supabase.rpc('get_league_management_state_v15', {
    p_league_id: leagueId,
  });
  if (!fallbackV15.error) {
    return normalizeManagementState(fallbackV15.data);
  }

  if (!isMissingManagementFunction(
    fallbackV15.error.message,
    'get_league_management_state_v15',
  )) {
    throw new Error(translateManagementError(fallbackV15.error.message));
  }

  const fallbackV14 = await supabase.rpc('get_league_management_state_v14', {
    p_league_id: leagueId,
  });
  if (!fallbackV14.error) {
    return normalizeManagementState(fallbackV14.data);
  }

  if (!isMissingManagementFunction(
    fallbackV14.error.message,
    'get_league_management_state_v14',
  )) {
    throw new Error(translateManagementError(fallbackV14.error.message));
  }

  const fallbackV13 = await supabase.rpc('get_league_management_state_v13', {
    p_league_id: leagueId,
  });
  if (!fallbackV13.error) {
    return normalizeManagementState(fallbackV13.data);
  }

  if (!isMissingManagementFunction(
    fallbackV13.error.message,
    'get_league_management_state_v13',
  )) {
    throw new Error(translateManagementError(fallbackV13.error.message));
  }

  const fallbackV12 = await supabase.rpc('get_league_management_state_v12', {
    p_league_id: leagueId,
  });
  if (!fallbackV12.error) {
    return normalizeManagementState(fallbackV12.data);
  }

  if (!isMissingManagementFunction(
    fallbackV12.error.message,
    'get_league_management_state_v12',
  )) {
    throw new Error(translateManagementError(fallbackV12.error.message));
  }

  const fallbackV11 = await supabase.rpc('get_league_management_state_v11', {
    p_league_id: leagueId,
  });
  if (!fallbackV11.error) {
    return normalizeManagementState(fallbackV11.data);
  }

  if (!isMissingManagementFunction(
    fallbackV11.error.message,
    'get_league_management_state_v11',
  )) {
    throw new Error(translateManagementError(fallbackV11.error.message));
  }

  const fallbackV10 = await supabase.rpc('get_league_management_state_v10', {
    p_league_id: leagueId,
  });
  if (!fallbackV10.error) {
    return normalizeManagementState(fallbackV10.data);
  }

  const fallbackV9 = await supabase.rpc('get_league_management_state_v9', {
    p_league_id: leagueId,
  });
  if (!fallbackV9.error) {
    return normalizeManagementState(fallbackV9.data);
  }

  const fallbackV8 = await supabase.rpc('get_league_management_state_v8', {
    p_league_id: leagueId,
  });
  if (!fallbackV8.error) {
    return normalizeManagementState(fallbackV8.data);
  }

  const fallbackV7 = await supabase.rpc('get_league_management_state_v7', {
    p_league_id: leagueId,
  });
  if (!fallbackV7.error) {
    return normalizeManagementState(fallbackV7.data);
  }

  const fallback = await supabase.rpc('get_league_management_state_v6', {
    p_league_id: leagueId,
  });
  if (fallback.error) {
    throw new Error(translateManagementError(fallback.error.message));
  }

  return normalizeManagementState(fallback.data);
}

export async function setLeagueInvitesOpen(
  leagueId: string,
  open: boolean,
): Promise<ActionOutcome> {
  return callManagementRpc('set_league_invites_open', {
    p_league_id: leagueId,
    p_open: open,
  });
}

export async function transferLeaguePresidency(
  leagueId: string,
  newOwnerId: string,
  expectedRevision: number,
): Promise<ActionOutcome> {
  return callManagementRpc('transfer_league_presidency_guarded', {
    p_league_id: leagueId,
    p_new_owner_id: newOwnerId,
    p_expected_revision: expectedRevision,
  });
}

export async function startLeagueCompetition(
  leagueId: string,
): Promise<ActionOutcome> {
  if (!supabase) {
    return { error: 'Il collegamento al backend non è configurato.' };
  }

  const latest = await supabase.rpc('start_league_competition_guarded_v4', {
    p_league_id: leagueId,
  });
  if (!latest.error) {
    return {};
  }

  if (!isMissingManagementFunction(
    latest.error.message,
    'start_league_competition_guarded_v4',
  )) {
    return { error: translateManagementError(latest.error.message) };
  }

  const fallbackV3 = await supabase.rpc('start_league_competition_guarded_v3', {
    p_league_id: leagueId,
  });
  if (!fallbackV3.error) {
    return {};
  }

  if (!isMissingManagementFunction(
    fallbackV3.error.message,
    'start_league_competition_guarded_v3',
  )) {
    return { error: translateManagementError(fallbackV3.error.message) };
  }

  const fallbackV2 = await supabase.rpc('start_league_competition_guarded_v2', {
    p_league_id: leagueId,
  });
  if (!fallbackV2.error) {
    return {};
  }

  if (!isMissingManagementFunction(
    fallbackV2.error.message,
    'start_league_competition_guarded_v2',
  )) {
    return { error: translateManagementError(fallbackV2.error.message) };
  }

  const fallback = await supabase.rpc('start_league_competition_guarded', {
    p_league_id: leagueId,
  });
  return fallback.error
    ? { error: translateManagementError(fallback.error.message) }
    : {};
}

export function subscribeToLeagueDirection(
  leagueId: string,
  onChange: () => void,
) {
  if (!supabase) {
    return () => undefined;
  }

  const client = supabase;
  const channel = client
    .channel(`league-direction-${leagueId}`)
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
        table: 'roster_entries',
        filter: `league_id=eq.${leagueId}`,
      },
      onChange,
    )
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
        table: 'league_members',
        filter: `league_id=eq.${leagueId}`,
      },
      onChange,
    )
    .on(
      'postgres_changes',
      {
        event: 'INSERT',
        schema: 'public',
        table: 'league_role_events',
        filter: `league_id=eq.${leagueId}`,
      },
      onChange,
    )
    .on(
      'postgres_changes',
      {
        event: '*',
        schema: 'public',
        table: 'league_competition_events',
        filter: `league_id=eq.${leagueId}`,
      },
      onChange,
    )
    .on(
      'postgres_changes',
      {
        event: 'INSERT',
        schema: 'public',
        table: 'lineup_submission_events',
        filter: `league_id=eq.${leagueId}`,
      },
      onChange,
    )
    .on(
      'postgres_changes',
      {
        event: 'INSERT',
        schema: 'public',
        table: 'lineup_deadline_events',
        filter: `league_id=eq.${leagueId}`,
      },
      onChange,
    )
    .on(
      'postgres_changes',
      {
        event: '*',
        schema: 'public',
        table: 'lineup_resolution_runs',
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
    .on(
      'postgres_changes',
      {
        event: '*',
        schema: 'public',
        table: 'matchday_officialization_runs',
        filter: `league_id=eq.${leagueId}`,
      },
      onChange,
    )
    .on(
      'postgres_changes',
      {
        event: 'INSERT',
        schema: 'public',
        table: 'result_correction_runs',
        filter: `league_id=eq.${leagueId}`,
      },
      onChange,
    )
    .on(
      'postgres_changes',
      {
        event: '*',
        schema: 'public',
        table: 'matchday_progression_runs',
        filter: `league_id=eq.${leagueId}`,
      },
      onChange,
    )
    .on(
      'postgres_changes',
      {
        event: 'INSERT',
        schema: 'public',
        table: 'season_completion_runs',
        filter: `league_id=eq.${leagueId}`,
      },
      onChange,
    )
    .on(
      'postgres_changes',
      {
        event: 'INSERT',
        schema: 'public',
        table: 'league_season_rollover_events',
        filter: `source_league_id=eq.${leagueId}`,
      },
      onChange,
    )
    .on(
      'postgres_changes',
      {
        event: 'INSERT',
        schema: 'public',
        table: 'league_cup_draw_runs',
        filter: `league_id=eq.${leagueId}`,
      },
      onChange,
    )
    .on(
      'postgres_changes',
      {
        event: 'INSERT',
        schema: 'public',
        table: 'league_cup_round_finalization_runs',
        filter: `league_id=eq.${leagueId}`,
      },
      onChange,
    )
    .on(
      'postgres_changes',
      {
        event: 'INSERT',
        schema: 'public',
        table: 'league_cup_completion_certificates',
        filter: `league_id=eq.${leagueId}`,
      },
      onChange,
    )
    .on(
      'postgres_changes',
      {
        event: 'INSERT',
        schema: 'public',
        table: 'league_super_cup_schedule_runs',
        filter: `league_id=eq.${leagueId}`,
      },
      onChange,
    )
    .on(
      'postgres_changes',
      {
        event: 'INSERT',
        schema: 'public',
        table: 'league_super_cup_finalization_runs',
        filter: `league_id=eq.${leagueId}`,
      },
      onChange,
    )
    .on(
      'postgres_changes',
      {
        event: 'INSERT',
        schema: 'public',
        table: 'league_playoff_configuration_runs',
        filter: `league_id=eq.${leagueId}`,
      },
      onChange,
    )
    .on(
      'postgres_changes',
      {
        event: 'INSERT',
        schema: 'public',
        table: 'league_playoff_start_runs',
        filter: `league_id=eq.${leagueId}`,
      },
      onChange,
    )
    .on(
      'postgres_changes',
      {
        event: 'INSERT',
        schema: 'public',
        table: 'league_playoff_round_finalization_runs',
        filter: `league_id=eq.${leagueId}`,
      },
      onChange,
    )
    .on(
      'postgres_changes',
      {
        event: 'INSERT',
        schema: 'public',
        table: 'league_playoff_completion_certificates',
        filter: `league_id=eq.${leagueId}`,
      },
      onChange,
    )
    .on(
      'postgres_changes',
      {
        event: 'INSERT',
        schema: 'public',
        table: 'provider_competition_start_events',
        filter: `league_id=eq.${leagueId}`,
      },
      onChange,
    )
    .subscribe();

  return () => {
    void client.removeChannel(channel);
  };
}

async function callManagementRpc(
  functionName:
    | 'set_league_invites_open'
    | 'transfer_league_presidency_guarded'
    | 'start_league_competition_guarded',
  params: Record<string, unknown>,
): Promise<ActionOutcome> {
  if (!supabase) {
    return { error: 'Il collegamento al backend non è configurato.' };
  }

  const { error } = await supabase.rpc(functionName, params);
  return error ? { error: translateManagementError(error.message) } : {};
}

function normalizeManagementState(value: unknown): LeagueManagementState {
  const raw =
    value && typeof value === 'object'
      ? (value as Record<string, unknown>)
      : {};
  const checksValue =
    raw.checks && typeof raw.checks === 'object'
      ? (raw.checks as Record<string, unknown>)
      : {};

  return {
    memberCount: toNumber(raw.memberCount),
    teamLimit: toNumber(raw.teamLimit),
    teamCount: toNumber(raw.teamCount),
    fullRosterCount: toNumber(raw.fullRosterCount),
    rosterSize: toNumber(raw.rosterSize),
    fixtureCount: toNumber(raw.fixtureCount),
    officialFixtureCount: toNumber(raw.officialFixtureCount),
    remainingFixtureCount: toNumber(raw.remainingFixtureCount),
    invitesOpen: Boolean(raw.invitesOpen),
    competitionStartedAt:
      typeof raw.competitionStartedAt === 'string'
        ? raw.competitionStartedAt
        : null,
    completedAt:
      typeof raw.completedAt === 'string' ? raw.completedAt : null,
    status: normalizeLeagueStatus(raw.leagueStatus),
    season: typeof raw.season === 'string' ? raw.season : null,
    champion: normalizeChampion(raw.champion),
    isOwner: Boolean(raw.isOwner),
    canStart: Boolean(raw.canStart),
    canComplete: Boolean(raw.canComplete),
    seasonCompletionCausalStatus:
      raw.seasonCompletionCausalStatus === 'clear' ||
      raw.seasonCompletionCausalStatus === 'affected'
        ? raw.seasonCompletionCausalStatus
        : 'blocked',
    seasonCompletionCausalReason: toNullableString(
      raw.seasonCompletionCausalReason,
    ),
    seasonCompletionCausallyCertified: Boolean(
      raw.seasonCompletionCausallyCertified,
    ),
    seasonCompletionAffected: Boolean(raw.seasonCompletionAffected),
    officialSnapshotProtected: Boolean(raw.officialSnapshotProtected),
    officialSnapshotPublished: Boolean(raw.officialSnapshotPublished),
    officialSnapshotHealthy:
      raw.officialSnapshotHealthy === undefined
        ? true
        : Boolean(raw.officialSnapshotHealthy),
    officialSnapshotStatus:
      raw.officialSnapshotStatus === 'official' ||
      raw.officialSnapshotStatus === 'affected'
        ? raw.officialSnapshotStatus
        : 'pending',
    officialSnapshotReason: toNullableString(raw.officialSnapshotReason),
    officialSnapshotAffected: Boolean(raw.officialSnapshotAffected),
    officialSnapshotId: toNullableNumber(raw.officialSnapshotId),
    officialSnapshotHash: toNullableString(raw.officialSnapshotHash),
    officialPodium: Array.isArray(raw.officialPodium)
      ? raw.officialPodium.map(normalizeStanding)
      : [],
    seasonRolloverProtected: Boolean(raw.seasonRolloverProtected),
    seasonRolloverCertified: Boolean(raw.seasonRolloverCertified),
    seasonRolloverHealthy:
      raw.seasonRolloverHealthy === undefined
        ? true
        : Boolean(raw.seasonRolloverHealthy),
    seasonRolloverStatus:
      raw.seasonRolloverStatus === 'certified' ||
      raw.seasonRolloverStatus === 'affected'
        ? raw.seasonRolloverStatus
        : 'pending',
    seasonRolloverReason: toNullableString(raw.seasonRolloverReason),
    seasonRolloverAffected: Boolean(raw.seasonRolloverAffected),
    seasonRolloverCertificateId: toNullableNumber(
      raw.seasonRolloverCertificateId,
    ),
    seasonRolloverLineageHash: toNullableString(
      raw.seasonRolloverLineageHash,
    ),
    seasonRolloverSourceSnapshotHash: toNullableString(
      raw.seasonRolloverSourceSnapshotHash,
    ),
    providerSeasonBootstrapProtected: Boolean(raw.providerSeasonBootstrapProtected),
    providerSeasonBootstrapApplicable: Boolean(raw.providerSeasonBootstrapApplicable),
    providerSeasonBootstrapHealthy:
      raw.providerSeasonBootstrapHealthy === undefined
        ? true
        : Boolean(raw.providerSeasonBootstrapHealthy),
    providerSeasonBootstrapAffected: Boolean(raw.providerSeasonBootstrapAffected),
    providerSeasonBootstrapStatus:
      raw.providerSeasonBootstrapStatus === 'catalog_ready' ||
      raw.providerSeasonBootstrapStatus === 'ready' ||
      raw.providerSeasonBootstrapStatus === 'affected'
        ? raw.providerSeasonBootstrapStatus
        : 'waiting',
    providerSeasonBootstrapReason: toNullableString(raw.providerSeasonBootstrapReason),
    providerSeasonCatalogReady: Boolean(raw.providerSeasonCatalogReady),
    providerSeasonFixturesReady: Boolean(raw.providerSeasonFixturesReady),
    providerSeasonBootstrapCertified: Boolean(raw.providerSeasonBootstrapCertified),
    providerSeasonBootstrapCertificateId: toNullableNumber(
      raw.providerSeasonBootstrapCertificateId,
    ),
    providerSeasonBootstrapHash: toNullableString(raw.providerSeasonBootstrapHash),
    providerCompetitionStartProtected: Boolean(raw.providerCompetitionStartProtected),
    providerCompetitionStartApplicable: Boolean(raw.providerCompetitionStartApplicable),
    providerCompetitionStartHealthy:
      raw.providerCompetitionStartHealthy === undefined
        ? true
        : Boolean(raw.providerCompetitionStartHealthy),
    providerCompetitionStartAffected: Boolean(raw.providerCompetitionStartAffected),
    providerCompetitionStartStatus:
      raw.providerCompetitionStartStatus === 'ready' ||
      raw.providerCompetitionStartStatus === 'official' ||
      raw.providerCompetitionStartStatus === 'affected'
        ? raw.providerCompetitionStartStatus
        : 'waiting',
    providerCompetitionStartReason: toNullableString(raw.providerCompetitionStartReason),
    providerCompetitionStartReady: Boolean(raw.providerCompetitionStartReady),
    providerCompetitionStartCertified: Boolean(raw.providerCompetitionStartCertified),
    providerCompetitionStartCertificateId: toNullableNumber(
      raw.providerCompetitionStartCertificateId,
    ),
    providerCompetitionStartHash: toNullableString(raw.providerCompetitionStartHash),
    canRenew: Boolean(raw.canRenew),
    previousLeagueId: toNullableString(raw.previousLeagueId),
    previousSeason: toNullableString(raw.previousSeason),
    nextLeagueId: toNullableString(raw.nextLeagueId),
    nextSeason: toNullableString(raw.nextSeason),
    renewedAt: toNullableString(raw.renewedAt),
    renewalCopiedMemberCount: toNumber(raw.renewalCopiedMemberCount),
    permissions: normalizePermissions(raw.permissions),
    accessSession: normalizeAccessSession(raw.accessSession),
    roleControl: normalizeRoleControl(raw.roleControl),
    competitionLifecycle: normalizeCompetitionLifecycle(
      raw.competitionLifecycle,
      raw.competitionStartedAt,
    ),
    checks: {
      membersReady: Boolean(checksValue.membersReady),
      teamsReady: Boolean(checksValue.teamsReady),
      rostersReady: Boolean(checksValue.rostersReady),
      calendarReady: Boolean(checksValue.calendarReady),
      marketReady: Boolean(checksValue.marketReady ?? true),
      tradesSettled: Boolean(checksValue.tradesSettled ?? true),
      auctionIntegrityReady: Boolean(
        checksValue.auctionIntegrityReady ?? true,
      ),
      auctionClosed: Boolean(checksValue.auctionClosed ?? true),
      calendarIntegrityReady: Boolean(
        checksValue.calendarIntegrityReady ?? checksValue.calendarReady,
      ),
      calendarSnapshotStable: Boolean(
        checksValue.calendarSnapshotStable ?? checksValue.calendarReady,
      ),
      precompetitionSnapshotLocked: Boolean(
        checksValue.precompetitionSnapshotLocked,
      ),
      snapshotMutationGuardReady: Boolean(
        checksValue.snapshotMutationGuardReady,
      ),
      competitionActivationReady: Boolean(
        checksValue.competitionActivationReady ??
          checksValue.precompetitionSnapshotLocked,
      ),
      competitionModelClosed: Boolean(
        checksValue.competitionModelClosed ??
          checksValue.competitionActivationReady,
      ),
      matchdayProgressionReady: Boolean(
        checksValue.matchdayProgressionReady,
      ),
      seasonCompletionCertified: Boolean(
        checksValue.seasonCompletionCertified,
      ),
      seasonCompletionCausalReady: Boolean(
        checksValue.seasonCompletionCausalReady,
      ),
      seasonOfficialSnapshotProtected: Boolean(
        checksValue.seasonOfficialSnapshotProtected,
      ),
      seasonOfficialSnapshotPublished: Boolean(
        checksValue.seasonOfficialSnapshotPublished,
      ),
      seasonOfficialSnapshotHealthy:
        checksValue.seasonOfficialSnapshotHealthy === undefined
          ? true
          : Boolean(checksValue.seasonOfficialSnapshotHealthy),
      seasonRolloverProtected: Boolean(
        checksValue.seasonRolloverProtected,
      ),
      seasonRolloverCertified: Boolean(
        checksValue.seasonRolloverCertified,
      ),
      seasonRolloverHealthy:
        checksValue.seasonRolloverHealthy === undefined
          ? true
          : Boolean(checksValue.seasonRolloverHealthy),
      providerSeasonBootstrapProtected: Boolean(
        checksValue.providerSeasonBootstrapProtected,
      ),
      providerSeasonCatalogReady: Boolean(
        checksValue.providerSeasonCatalogReady,
      ),
      providerSeasonFixturesReady: Boolean(
        checksValue.providerSeasonFixturesReady,
      ),
      providerSeasonBootstrapCertified: Boolean(
        checksValue.providerSeasonBootstrapCertified,
      ),
      providerSeasonBootstrapHealthy:
        checksValue.providerSeasonBootstrapHealthy === undefined
          ? true
          : Boolean(checksValue.providerSeasonBootstrapHealthy),
      providerCompetitionStartProtected: Boolean(
        checksValue.providerCompetitionStartProtected,
      ),
      providerCompetitionStartReady: Boolean(
        checksValue.providerCompetitionStartReady,
      ),
      providerCompetitionStartCertified: Boolean(
        checksValue.providerCompetitionStartCertified,
      ),
      providerCompetitionStartHealthy:
        checksValue.providerCompetitionStartHealthy === undefined
          ? true
          : Boolean(checksValue.providerCompetitionStartHealthy),
      lineupLifecycleReady: Boolean(
        checksValue.lineupLifecycleReady,
      ),
      liveLifecycleReady: Boolean(
        checksValue.liveLifecycleReady,
      ),
      matchdayLifecycleReady: Boolean(
        checksValue.matchdayLifecycleReady,
      ),
      matchdayModelClosed: Boolean(
        checksValue.matchdayModelClosed,
      ),
      specialCompetitionsModelClosed: Boolean(
        checksValue.specialCompetitionsModelClosed,
      ),
    },
  };
}



function normalizeCompetitionLifecycle(
  value: unknown,
  fallbackStartedAt: unknown,
): LeagueCompetitionLifecycle {
  const raw =
    value && typeof value === 'object'
      ? (value as Record<string, unknown>)
      : {};

  return {
    started: Boolean(raw.started ?? fallbackStartedAt),
    startedAt: toNullableString(raw.startedAt ?? fallbackStartedAt),
    startedBy: toNullableString(raw.startedBy),
    revision: toNumber(raw.revision),
    startVersion: toNumber(raw.startVersion),
    openingVersion: toNumber(raw.openingVersion),
    openingVerifiedAt: toNullableString(raw.openingVerifiedAt),
    currentMatchdayId: toNullableString(raw.currentMatchdayId),
    currentMatchdayNumber: toNumber(raw.currentMatchdayNumber),
    openingMatchdayId: toNullableString(raw.openingMatchdayId),
    openingMatchdayNumber: toNumber(raw.openingMatchdayNumber),
    openingStartsAt: toNullableString(raw.openingStartsAt),
    openingLocksAt: toNullableString(raw.openingLocksAt),
    openingFixtureCount: toNumber(raw.openingFixtureCount),
    expectedOpeningFixtureCount: toNumber(
      raw.expectedOpeningFixtureCount,
    ),
    openingReady: Boolean(raw.openingReady),
    activationProtected: Boolean(raw.activationProtected),
    modelClosed: Boolean(raw.modelClosed),
    modelClosedAt: toNullableString(raw.modelClosedAt),
    modelVersion: toNumber(raw.modelVersion),
    structureVerifiedAt: toNullableString(raw.structureVerifiedAt),
    fixtureStructureProtected: Boolean(raw.fixtureStructureProtected),
    leagueStructureProtected: Boolean(raw.leagueStructureProtected),
    calendarFingerprintStable: Boolean(raw.calendarFingerprintStable),
    calendarCountsReady: Boolean(raw.calendarCountsReady),
    integrityHealthy: Boolean(raw.integrityHealthy),
    eventCount: toNumber(raw.eventCount),
  };
}

function normalizeAccessSession(value: unknown): LeagueAccessSession {
  const raw =
    value && typeof value === 'object'
      ? (value as Record<string, unknown>)
      : {};
  const reason =
    raw.reason === 'membership_revoked' || raw.reason === 'league_missing'
      ? raw.reason
      : null;

  return {
    accessValid: Boolean(raw.accessValid),
    reason,
    revision: toNumber(raw.revision),
    roleUpdatedAt: toNullableString(raw.roleUpdatedAt),
    permissions: normalizePermissions(raw.permissions),
  };
}

function normalizeRoleControl(value: unknown): LeagueRoleControlState {
  const raw =
    value && typeof value === 'object'
      ? (value as Record<string, unknown>)
      : {};
  const events = Array.isArray(raw.events)
    ? raw.events.map(normalizeRoleEvent).filter(Boolean) as LeagueRoleAuditEvent[]
    : [];

  return {
    integrity: normalizeRoleIntegrity(raw.integrity),
    security: normalizeRoleSecurity(raw.security),
    events,
  };
}

function normalizeRoleSecurity(value: unknown): LeagueRoleSecurity {
  const raw =
    value && typeof value === 'object'
      ? (value as Record<string, unknown>)
      : {};
  const members = Array.isArray(raw.members)
    ? raw.members
        .map(normalizeRoleMatrixMember)
        .filter(Boolean) as LeagueRoleMatrixMember[]
    : [];

  return {
    hardened: Boolean(raw.hardened),
    presidentCount: toNumber(raw.presidentCount),
    adminCount: toNumber(raw.adminCount),
    managerCount: toNumber(raw.managerCount),
    directRoleMutationBlocked: Boolean(raw.directRoleMutationBlocked),
    directPresidencyMutationBlocked: Boolean(
      raw.directPresidencyMutationBlocked,
    ),
    directRemovalBlocked: Boolean(raw.directRemovalBlocked),
    guardedActionsReady: Boolean(raw.guardedActionsReady),
    members,
  };
}

function normalizeRoleMatrixMember(
  value: unknown,
): LeagueRoleMatrixMember | null {
  if (!value || typeof value !== 'object') {
    return null;
  }
  const raw = value as Record<string, unknown>;
  const role =
    raw.role === 'president' || raw.role === 'admin' || raw.role === 'manager'
      ? raw.role
      : null;
  if (!role || typeof raw.userId !== 'string') {
    return null;
  }
  return {
    userId: raw.userId,
    displayName:
      typeof raw.displayName === 'string' ? raw.displayName : 'Account',
    teamName: typeof raw.teamName === 'string' ? raw.teamName : null,
    role,
    canAccessDirection: Boolean(raw.canAccessDirection),
    canManageHierarchy: Boolean(raw.canManageHierarchy),
    canRunOperations: Boolean(raw.canRunOperations),
    canManageTeam: Boolean(raw.canManageTeam),
  };
}

function normalizeRoleIntegrity(value: unknown): LeagueRoleIntegrity {
  const raw =
    value && typeof value === 'object'
      ? (value as Record<string, unknown>)
      : {};
  return {
    healthy: Boolean(raw.healthy),
    ownerMemberExists: Boolean(raw.ownerMemberExists),
    ownerProfileActive: Boolean(raw.ownerProfileActive),
    teamManagersAreMembers: Boolean(raw.teamManagersAreMembers),
    oneTeamPerManager: Boolean(raw.oneTeamPerManager),
    memberCount: toNumber(raw.memberCount),
    adminCount: toNumber(raw.adminCount),
    teamCount: toNumber(raw.teamCount),
    orphanTeamCount: toNumber(raw.orphanTeamCount),
    duplicateTeamManagerCount: toNumber(raw.duplicateTeamManagerCount),
  };
}

function normalizeRoleEvent(value: unknown): LeagueRoleAuditEvent | null {
  if (!value || typeof value !== 'object') {
    return null;
  }
  const raw = value as Record<string, unknown>;
  if (typeof raw.id !== 'string' || typeof raw.createdAt !== 'string') {
    return null;
  }
  const type =
    raw.type === 'admin_granted' ||
    raw.type === 'admin_revoked' ||
    raw.type === 'presidency_transferred'
      ? raw.type
      : null;
  if (!type) {
    return null;
  }
  const role = (input: unknown) =>
    input === 'admin' || input === 'manager' ? input : null;
  return {
    id: raw.id,
    type,
    actorId: typeof raw.actorId === 'string' ? raw.actorId : null,
    actorName: typeof raw.actorName === 'string' ? raw.actorName : 'Account',
    targetUserId:
      typeof raw.targetUserId === 'string' ? raw.targetUserId : null,
    targetName: typeof raw.targetName === 'string' ? raw.targetName : 'Account',
    previousRole: role(raw.previousRole),
    newRole: role(raw.newRole),
    createdAt: raw.createdAt,
  };
}

function normalizePermissions(value: unknown): LeaguePermissionState {
  const raw =
    value && typeof value === 'object'
      ? (value as Record<string, unknown>)
      : {};
  const role =
    raw.role === 'president' ||
    raw.role === 'admin' ||
    raw.role === 'manager' ||
    raw.role === 'none'
      ? raw.role
      : 'none';

  return {
    role,
    isMember: Boolean(raw.isMember),
    isOwner: Boolean(raw.isOwner),
    isAdmin: Boolean(raw.isAdmin),
    hasTeam: Boolean(raw.hasTeam),
    canAccessDirection: Boolean(raw.canAccessDirection),
    canRunOperations: Boolean(raw.canRunOperations),
    canEditRules: Boolean(raw.canEditRules),
    canManageInvites: Boolean(raw.canManageInvites),
    canManageMembers: Boolean(raw.canManageMembers),
    canManageAdmins: Boolean(raw.canManageAdmins),
    canTransferPresidency: Boolean(raw.canTransferPresidency),
    canStartCompetition: Boolean(raw.canStartCompetition),
    canCloseSeason: Boolean(raw.canCloseSeason),
    canSubmitLineup: Boolean(raw.canSubmitLineup),
    canUseMarket: Boolean(raw.canUseMarket),
  };
}

function normalizeLeagueStatus(
  value: unknown,
): LeagueManagementState['status'] {
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

function normalizeStanding(value: unknown) {
  const raw = value && typeof value === 'object'
    ? (value as Record<string, unknown>)
    : {};
  return {
    position: toNumber(raw.position),
    teamId: typeof raw.teamId === 'string' ? raw.teamId : '',
    teamName: typeof raw.teamName === 'string' ? raw.teamName : '',
    played: toNumber(raw.played),
    won: toNumber(raw.won),
    drawn: toNumber(raw.drawn),
    lost: toNumber(raw.lost),
    goalsFor: toNumber(raw.goalsFor),
    goalsAgainst: toNumber(raw.goalsAgainst),
    goalDifference: toNumber(raw.goalDifference),
    pointsFor: toNumber(raw.pointsFor),
    leaguePoints: toNumber(raw.leaguePoints),
    headToHeadPlayed: toNumber(raw.headToHeadPlayed),
    headToHeadPoints: toNumber(raw.headToHeadPoints),
    headToHeadGoalDifference: toNumber(raw.headToHeadGoalDifference),
    headToHeadEligible: Boolean(raw.headToHeadEligible),
  };
}

function normalizeChampion(value: unknown): LeagueManagementState['champion'] {
  if (!value || typeof value !== 'object') {
    return null;
  }
  const raw = value as Record<string, unknown>;
  if (typeof raw.teamId !== 'string') {
    return null;
  }
  return {
    teamId: raw.teamId,
    teamName: typeof raw.teamName === 'string' ? raw.teamName : '',
    managerName:
      typeof raw.managerName === 'string' ? raw.managerName : '',
    leaguePoints: toNumber(raw.leaguePoints),
    pointsFor: toNumber(raw.pointsFor),
  };
}

function toNumber(value: unknown) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : 0;
}

function toNullableNumber(value: unknown) {
  if (value === null || value === undefined || value === '') {
    return null;
  }
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : null;
}

function toNullableString(value: unknown) {
  return typeof value === 'string' && value ? value : null;
}

function isMissingManagementFunction(
  message: string,
  functionName: string,
) {
  const normalized = message.toLowerCase();
  const mentionsFunction = normalized.includes(functionName.toLowerCase());
  const reportsMissing =
    normalized.includes('does not exist') ||
    normalized.includes('could not find the function') ||
    normalized.includes('schema cache');

  return mentionsFunction && reportsMissing;
}

function translateManagementError(message: string) {
  const normalized = message.toLowerCase();

  if (normalized.includes('get_league_management_state_v24')) {
    return 'La telemetria operativa autorevole non è ancora installata nel database.';
  }
  if (normalized.includes('get_league_management_state_v23')) {
    return 'Aggiorna il database LEGHEVO fino alla migrazione 139.';
  }
  if (normalized.includes('get_league_management_state_v22')) {
    return 'Aggiorna il database LEGHEVO fino alla migrazione 138.';
  }
  if (normalized.includes('get_league_management_state_v21')) {
    return 'Aggiorna il database LEGHEVO fino alla migrazione 137.';
  }
  if (normalized.includes('get_league_management_state_v20')) {
    return 'Aggiorna il database LEGHEVO fino alla migrazione 136.';
  }
  if (normalized.includes('get_league_management_state_v19')) {
    return 'Aggiorna il database LEGHEVO fino alla migrazione 135.';
  }
  if (normalized.includes('get_league_management_state_v18')) {
    return 'Aggiorna il database LEGHEVO fino alla migrazione 134.';
  }
  if (normalized.includes('get_league_management_state_v17')) {
    return 'Aggiorna il database LEGHEVO fino alla migrazione 133.';
  }
  if (normalized.includes('get_league_management_state_v16')) {
    return 'Aggiorna il database LEGHEVO fino alla migrazione 132.';
  }
  if (normalized.includes('get_league_management_state_v15')) {
    return 'Aggiorna il database LEGHEVO fino alla migrazione 131.';
  }

  if (normalized.includes('avvio bloccato dal bootstrap provider')) {
    return 'La nuova stagione non può partire: il bootstrap provider non è ancora certificato.';
  }
  if (normalized.includes('avvio competizione non pronto')) {
    return 'La competizione non può partire finché calendario e giornata inaugurale non sono certificati.';
  }
  if (normalized.includes('start_league_competition_guarded_v4')) {
    return 'Aggiorna il database LEGHEVO fino alla migrazione 135.';
  }

  if (
    normalized.includes('get_league_management_state_v14') ||
    normalized.includes('get_league_management_state_v13') ||
    normalized.includes('get_league_management_state_v12') ||
    normalized.includes('get_league_management_state_v11') ||
    normalized.includes('get_league_management_state_v10') ||
    normalized.includes('get_league_management_state_v9') ||
    normalized.includes('get_league_management_state_v8') ||
    normalized.includes('get_league_management_state_v7') ||
    normalized.includes('get_league_management_state_v6') ||
    normalized.includes('get_league_access_session') ||
    normalized.includes('get_league_management_state_v5') ||
    normalized.includes('get_league_management_state_v4') ||
    normalized.includes('set_league_invites_open') ||
    normalized.includes('transfer_league_presidency_guarded') ||
    normalized.includes('start_league_competition_guarded_v3') ||
    normalized.includes('start_league_competition_guarded_v2') ||
    normalized.includes('start_league_competition_guarded') ||
    normalized.includes('start_league_competition') ||
    (normalized.includes('function') && normalized.includes('does not exist'))
  ) {
    return 'Aggiorna il database LEGHEVO fino alla migrazione 094.';
  }
  if (normalized.includes('altro dispositivo') || normalized.includes('revisione dei permessi')) {
    return 'La direzione è cambiata su un altro dispositivo. Aggiorna e riprova.';
  }
  if (normalized.includes('accesso alla lega revocato')) {
    return 'Non fai più parte di questa lega.';
  }
  if (normalized.includes('non hai più accesso alla direzione')) {
    return 'Il tuo ruolo è cambiato: la Direzione Lega non è più disponibile.';
  }
  if (normalized.includes('solo il presidente')) {
    return 'Questa decisione spetta al Presidente della lega.';
  }
  if (normalized.includes('spogliatoio non è ancora completo')) {
    return 'Prima devono entrare tutte le squadre previste.';
  }
  if (normalized.includes('ogni partecipante deve avere una squadra')) {
    return 'Ogni partecipante deve avere una squadra valida.';
  }
  if (normalized.includes('rose devono essere complete')) {
    return 'Completa tutte le rose prima del fischio d’inizio.';
  }
  if (normalized.includes('fotografia pre-campionato')) {
    return 'Il sorteggio non è ancora protetto: aggiorna il calendario e riprova.';
  }
  if (normalized.includes('assetto della lega è cambiato')) {
    return 'L’assetto della lega non coincide più con il calendario pubblicato.';
  }
  if (normalized.includes('genera il calendario')) {
    return 'Genera il calendario prima di avviare la competizione.';
  }
  if (normalized.includes('inviti restano chiusi')) {
    return 'La competizione è già iniziata: gli inviti restano chiusi.';
  }

  return message;
}
