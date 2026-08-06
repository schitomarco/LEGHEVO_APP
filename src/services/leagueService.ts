import { supabase } from '../lib/supabase';
import type {
  LeagueMemberSummary,
  LeagueMode,
  LeagueSummary,
} from '../types';

export type CreateLeagueInput = {
  name: string;
  teamName: string;
  mode: LeagueMode;
  teamLimit: number;
  startingCredits: number;
  rosterSize: number;
};

export type JoinLeagueInput = {
  inviteCode: string;
  teamName: string;
};

export type LeagueActionOutcome = {
  league?: LeagueSummary;
  error?: string;
};

export type LeagueInvitePreview = {
  leagueId: string;
  leagueName: string;
  mode: LeagueMode;
  status: LeagueSummary['status'];
  teamLimit: number;
  teamCount: number;
  availableSpots: number;
  startingCredits: number;
  rosterSize: number;
  invitesOpen: boolean;
  alreadyMember: boolean;
  alreadyHasTeam: boolean;
  canJoin: boolean;
  blockReason?: string;
};

export type LeagueInvitePreviewOutcome = {
  preview?: LeagueInvitePreview;
  error?: string;
};

type LeagueRow = {
  id: string;
  owner_id: string;
  name: string;
  invite_code: string;
  invites_open?: boolean;
  competition_started_at?: string | null;
  calendar_season?: string | null;
  mode: LeagueMode;
  status: LeagueSummary['status'];
  team_limit: number;
  starting_credits: number;
  roster_size: number;
};

type TeamRow = {
  id: string;
  league_id: string;
  name: string;
  credits_remaining: number;
};

type MemberRow = {
  league_id?: string;
  user_id: string;
  role: LeagueMemberSummary['role'];
  joined_at: string;
};

type ProfileRow = {
  id: string;
  display_name: string;
};

type LeagueOwnerRow = {
  owner_id: string;
};

type LeagueInvitePreviewRow = {
  league_id: string;
  league_name: string;
  league_mode: LeagueMode;
  league_status: LeagueSummary['status'];
  team_limit: number;
  team_count: number;
  available_spots: number;
  starting_credits: number;
  roster_size: number;
  invites_open: boolean;
  already_member: boolean;
  already_has_team: boolean;
  can_join: boolean;
  block_reason: string | null;
};

export async function fetchUserLeagues(
  userId: string,
): Promise<LeagueSummary[]> {
  if (!supabase) {
    return [];
  }

  const { data: leagueRows, error: leagueError } = await supabase
    .from('leagues')
    .select(
      'id, owner_id, name, invite_code, invites_open, competition_started_at, calendar_season, mode, status, team_limit, starting_credits, roster_size',
    )
    .order('created_at', { ascending: false });

  if (leagueError) {
    throw leagueError;
  }

  const leagues = (leagueRows ?? []) as LeagueRow[];
  if (leagues.length === 0) {
    return [];
  }

  const leagueIds = leagues.map((league) => league.id);
  const [teamsResponse, membersResponse] = await Promise.all([
    supabase
      .from('fantasy_teams')
      .select('id, league_id, name, credits_remaining')
      .eq('manager_id', userId)
      .in('league_id', leagueIds),
    supabase
      .from('league_members')
      .select('league_id, user_id, role')
      .in('league_id', leagueIds),
  ]);

  if (teamsResponse.error) {
    throw teamsResponse.error;
  }
  if (membersResponse.error) {
    throw membersResponse.error;
  }

  const teams = (teamsResponse.data ?? []) as TeamRow[];
  const memberCounts = (membersResponse.data ?? []).reduce<Record<string, number>>(
    (counts, member) => {
      counts[member.league_id] = (counts[member.league_id] ?? 0) + 1;
      return counts;
    },
    {},
  );

  return leagues.map((league) =>
    mapLeague(
      league,
      teams.find((team) => team.league_id === league.id),
      memberCounts[league.id] ?? 1,
      (
        membersResponse.data ?? []
      ).find(
        (member) =>
          member.league_id === league.id && member.user_id === userId,
      )?.role as LeagueMemberSummary['role'] | undefined,
    ),
  );
}

export async function fetchLeagueMembers(
  leagueId: string,
): Promise<LeagueMemberSummary[]> {
  if (!supabase) {
    return [];
  }

  const [membersResponse, teamsResponse, leagueResponse] = await Promise.all([
    supabase
      .from('league_members')
      .select('user_id, role, joined_at')
      .eq('league_id', leagueId)
      .order('joined_at', { ascending: true }),
    supabase
      .from('fantasy_teams')
      .select('id, league_id, manager_id, name, credits_remaining')
      .eq('league_id', leagueId),
    supabase
      .from('leagues')
      .select('owner_id')
      .eq('id', leagueId)
      .single(),
  ]);

  if (membersResponse.error) {
    throw membersResponse.error;
  }
  if (teamsResponse.error) {
    throw teamsResponse.error;
  }
  if (leagueResponse.error) {
    throw leagueResponse.error;
  }

  const members = (membersResponse.data ?? []) as MemberRow[];
  if (members.length === 0) {
    return [];
  }

  const { data: profileData, error: profilesError } = await supabase
    .from('profiles')
    .select('id, display_name')
    .in(
      'id',
      members.map((member) => member.user_id),
    );

  if (profilesError) {
    throw profilesError;
  }

  const profiles = (profileData ?? []) as ProfileRow[];
  const teams = (teamsResponse.data ?? []) as Array<
    TeamRow & { manager_id: string }
  >;
  const ownerId = (leagueResponse.data as LeagueOwnerRow).owner_id;

  return members.map((member) => {
    const profile = profiles.find((item) => item.id === member.user_id);
    const team = teams.find((item) => item.manager_id === member.user_id);

    return {
      userId: member.user_id,
      displayName: profile?.display_name ?? 'Mister senza nome',
      role: member.role,
      isOwner: member.user_id === ownerId,
      joinedAt: member.joined_at,
      team: team
        ? {
            id: team.id,
            name: team.name,
            creditsRemaining: team.credits_remaining,
          }
        : undefined,
    };
  });
}

export function subscribeToLeagueOverview(
  userId: string,
  onChange: () => void,
) {
  if (!supabase) {
    return () => undefined;
  }

  const client = supabase;
  const channel = client
    .channel(`league-overview-${userId}`)
    .on(
      'postgres_changes',
      {
        event: '*',
        schema: 'public',
        table: 'league_members',
      },
      onChange,
    )
    .on(
      'postgres_changes',
      {
        event: '*',
        schema: 'public',
        table: 'fantasy_teams',
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

export function subscribeToLeagueMembers(
  leagueId: string,
  onChange: () => void,
) {
  if (!supabase) {
    return () => undefined;
  }

  const client = supabase;
  const channel = client
    .channel(`league-members-${leagueId}`)
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
        event: '*',
        schema: 'public',
        table: 'fantasy_teams',
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
    .subscribe();

  return () => {
    void client.removeChannel(channel);
  };
}


export async function previewLeagueInvite(
  inviteCode: string,
): Promise<LeagueInvitePreviewOutcome> {
  if (!supabase) {
    return { error: 'Il collegamento al backend non è configurato.' };
  }

  const normalizedCode = inviteCode
    .replace(/[^a-z0-9]/gi, '')
    .toUpperCase();

  const { data, error } = await supabase.rpc('preview_league_invite', {
    p_invite_code: normalizedCode,
  });

  if (error) {
    const translated = translateLeagueError(error.message);
    return {
      error:
        translated.includes('file 006')
          ? 'Aggiorna prima il database LEGHEVO con lo script 060.'
          : translated,
    };
  }

  const row = (Array.isArray(data) ? data[0] : data) as
    | LeagueInvitePreviewRow
    | null;

  if (!row) {
    return { error: 'Codice invito non valido. Chiedilo di nuovo al presidente.' };
  }

  return {
    preview: {
      leagueId: row.league_id,
      leagueName: row.league_name,
      mode: row.league_mode,
      status: row.league_status,
      teamLimit: row.team_limit,
      teamCount: row.team_count,
      availableSpots: row.available_spots,
      startingCredits: row.starting_credits,
      rosterSize: row.roster_size,
      invitesOpen: row.invites_open,
      alreadyMember: row.already_member,
      alreadyHasTeam: row.already_has_team,
      canJoin: row.can_join,
      blockReason: row.block_reason ?? undefined,
    },
  };
}

export async function createLeague(
  input: CreateLeagueInput,
): Promise<LeagueActionOutcome> {
  if (!supabase) {
    return { error: 'Il collegamento al backend non è configurato.' };
  }

  const { data, error } = await supabase.rpc('create_league_with_team', {
    p_name: input.name.trim(),
    p_team_name: input.teamName.trim(),
    p_mode: input.mode,
    p_team_limit: input.teamLimit,
    p_starting_credits: input.startingCredits,
    p_roster_size: input.rosterSize,
  });

  if (error) {
    return { error: translateLeagueError(error.message) };
  }

  return {
    league: mapLeague(normalizeLeagueRow(data), undefined, 1, 'admin'),
  };
}

export async function joinLeague(
  input: JoinLeagueInput,
): Promise<LeagueActionOutcome> {
  if (!supabase) {
    return { error: 'Il collegamento al backend non è configurato.' };
  }

  const { data, error } = await supabase.rpc('join_league_by_code', {
    p_invite_code: input.inviteCode.trim().toUpperCase(),
    p_team_name: input.teamName.trim(),
  });

  if (error) {
    return { error: translateLeagueError(error.message) };
  }

  return {
    league: mapLeague(normalizeLeagueRow(data), undefined, 1, 'manager'),
  };
}

export async function setLeagueMemberRole(
  leagueId: string,
  userId: string,
  role: LeagueMemberSummary['role'],
  expectedRevision: number,
): Promise<{ error?: string }> {
  return callMemberManagementRpc('set_league_member_role_guarded', {
    p_league_id: leagueId,
    p_user_id: userId,
    p_role: role,
    p_expected_revision: expectedRevision,
  });
}

export async function removeLeagueMember(
  leagueId: string,
  userId: string,
  expectedRevision: number,
): Promise<{ error?: string }> {
  return callMemberManagementRpc('remove_league_member_guarded', {
    p_league_id: leagueId,
    p_user_id: userId,
    p_expected_revision: expectedRevision,
  });
}

export async function regenerateLeagueInviteCode(
  leagueId: string,
): Promise<{ inviteCode?: string; error?: string }> {
  if (!supabase) {
    return { error: 'Il collegamento al backend non è configurato.' };
  }

  const { data, error } = await supabase.rpc(
    'regenerate_league_invite_code',
    { p_league_id: leagueId },
  );

  if (error) {
    return { error: translateMemberManagementError(error.message) };
  }

  return { inviteCode: String(data) };
}

async function callMemberManagementRpc(
  functionName:
    | 'set_league_member_role_guarded'
    | 'remove_league_member_guarded',
  params: Record<string, unknown>,
): Promise<{ error?: string }> {
  if (!supabase) {
    return { error: 'Il collegamento al backend non è configurato.' };
  }

  const { error } = await supabase.rpc(functionName, params);
  return error
    ? { error: translateMemberManagementError(error.message) }
    : {};
}

function translateMemberManagementError(message: string) {
  const normalized = message.toLowerCase();
  if (
    normalized.includes('set_league_member_role_guarded') ||
    normalized.includes('remove_league_member_guarded') ||
    normalized.includes('regenerate_league_invite_code') ||
    (normalized.includes('function') && normalized.includes('does not exist'))
  ) {
    return 'Aggiorna prima il database LEGHEVO con il file 064.';
  }
  if (normalized.includes('altro dispositivo') || normalized.includes('revisione dei permessi')) {
    return 'Ruoli aggiornati su un altro dispositivo. Ricarica la Direzione Lega e riprova.';
  }
  if (normalized.includes('ha già attività nella lega')) {
    return 'Non puoi rimuoverlo: ha già partecipato ad asta, mercato, formazione o calendario.';
  }
  if (normalized.includes('competizione è iniziata')) {
    return 'La competizione è già iniziata: i partecipanti sono bloccati.';
  }
  if (normalized.includes('solo il presidente')) {
    return 'Solo il Presidente può completare questa operazione.';
  }
  return message;
}

function normalizeLeagueRow(value: unknown): LeagueRow {
  const row = Array.isArray(value) ? value[0] : value;
  return row as LeagueRow;
}

function mapLeague(
  league: LeagueRow,
  team?: TeamRow,
  memberCount = 1,
  currentRole?: LeagueMemberSummary['role'],
): LeagueSummary {
  return {
    id: league.id,
    ownerId: league.owner_id,
    name: league.name,
    inviteCode: league.invite_code,
    invitesOpen: league.invites_open ?? true,
    competitionStartedAt: league.competition_started_at ?? null,
    season: league.calendar_season ?? null,
    mode: league.mode,
    status: league.status,
    teamLimit: league.team_limit,
    startingCredits: league.starting_credits,
    rosterSize: league.roster_size,
    memberCount,
    currentRole,
    team: team
      ? {
          id: team.id,
          name: team.name,
          creditsRemaining: team.credits_remaining,
        }
      : undefined,
  };
}

function translateLeagueError(message: string) {
  const normalized = message.toLowerCase();

  if (normalized.includes('function') && normalized.includes('does not exist')) {
    return 'Aggiorna prima il database LEGHEVO con il file 006.';
  }
  if (normalized.includes('codice invito non valido')) {
    return 'Codice invito non valido. Chiedilo di nuovo al presidente.';
  }
  if (normalized.includes('inviti di questa lega sono chiusi')) {
    return 'Gli inviti sono chiusi dal Presidente.';
  }
  if (normalized.includes('non accetta più partecipanti')) {
    return 'La competizione è già iniziata: non è più possibile entrare.';
  }
  if (normalized.includes('lega è al completo')) {
    return 'La lega è al completo. Panchina compresa.';
  }
  if (
    normalized.includes('fantasy_teams_league_id_name_key') ||
    normalized.includes('questo nome squadra è già stato preso')
  ) {
    return 'Questo nome squadra è già stato preso. Servirà più fantasia.';
  }
  if (normalized.includes('fai già parte di questa lega')) {
    return 'Fai già parte di questa lega.';
  }
  if (normalized.includes('codice invito deve contenere 10 caratteri')) {
    return 'Il codice invito deve contenere 10 caratteri.';
  }
  if (normalized.includes('nome della lega deve contenere')) {
    return 'Il nome della lega deve contenere da 3 a 50 caratteri.';
  }
  if (normalized.includes('nome squadra deve contenere')) {
    return 'Il nome squadra deve contenere da 2 a 40 caratteri.';
  }

  return message;
}
