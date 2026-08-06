import { supabase } from '../lib/supabase';
import type {
  LeagueMode,
  LeagueRuleRevision,
  LeagueRulebook,
  LeagueSummary,
} from '../types';
import { mapSettings } from './settingsService';

type RawRulebook = {
  leagueId?: unknown;
  leagueName?: unknown;
  mode?: unknown;
  status?: unknown;
  season?: unknown;
  teamLimit?: unknown;
  startingCredits?: unknown;
  rosterSize?: unknown;
  isDirector?: unknown;
  currentRevision?: unknown;
  updatedAt?: unknown;
  rules?: unknown;
  revisions?: unknown;
};

export async function fetchLeagueRulebook(
  leagueId: string,
): Promise<LeagueRulebook> {
  if (!supabase) {
    throw new Error('Il collegamento al backend non è configurato.');
  }

  const { data, error } = await supabase.rpc('get_league_rulebook', {
    p_league_id: leagueId,
  });

  if (!error) {
    return normalizeRulebook(data);
  }

  if (isLegacySeasonFieldError(error.message)) {
    return fetchLeagueRulebookFallback(leagueId);
  }

  throw new Error(translateRulebookError(error.message));
}


type RulebookLeagueRow = {
  id: string;
  name: string;
  mode: unknown;
  status: unknown;
  calendar_season: string | null;
  team_limit: number;
  starting_credits: number;
  roster_size: number;
  updated_at: string;
  scoring_rules: Record<string, unknown> | null;
};

type RulebookMemberRow = {
  role: string;
};

type RulebookRevisionRow = {
  id: string;
  revision: number;
  reason: string;
  changed_keys: string[] | null;
  changed_at: string;
  changed_by: string | null;
};

type RulebookProfileRow = {
  id: string;
  display_name: string;
};

async function fetchLeagueRulebookFallback(
  leagueId: string,
): Promise<LeagueRulebook> {
  if (!supabase) {
    throw new Error('Il collegamento al backend non è configurato.');
  }

  const { data: authData, error: authError } = await supabase.auth.getUser();
  const userId = authData.user?.id;
  if (authError || !userId) {
    throw new Error('Devi effettuare l’accesso.');
  }

  const [leagueResponse, memberResponse, revisionsResponse] =
    await Promise.all([
      supabase
        .from('leagues')
        .select(
          'id, name, mode, status, calendar_season, team_limit, starting_credits, roster_size, updated_at, scoring_rules',
        )
        .eq('id', leagueId)
        .single(),
      supabase
        .from('league_members')
        .select('role')
        .eq('league_id', leagueId)
        .eq('user_id', userId)
        .single(),
      supabase
        .from('league_rule_revisions')
        .select(
          'id, revision, reason, changed_keys, changed_at, changed_by',
          { count: 'exact' },
        )
        .eq('league_id', leagueId)
        .order('revision', { ascending: false })
        .limit(20),
    ]);

  if (leagueResponse.error) {
    throw new Error(translateRulebookError(leagueResponse.error.message));
  }
  if (memberResponse.error) {
    throw new Error(translateRulebookError(memberResponse.error.message));
  }
  if (revisionsResponse.error) {
    throw new Error(translateRulebookError(revisionsResponse.error.message));
  }

  const league = leagueResponse.data as RulebookLeagueRow;
  const member = memberResponse.data as RulebookMemberRow;
  const revisions = (revisionsResponse.data ?? []) as RulebookRevisionRow[];
  const profileIds = Array.from(
    new Set(
      revisions
        .map((revision) => revision.changed_by)
        .filter((id): id is string => Boolean(id)),
    ),
  );

  const profileNames = new Map<string, string>();
  if (profileIds.length > 0) {
    const { data: profiles, error: profilesError } = await supabase
      .from('profiles')
      .select('id, display_name')
      .in('id', profileIds);

    if (!profilesError) {
      for (const profile of (profiles ?? []) as RulebookProfileRow[]) {
        profileNames.set(profile.id, profile.display_name);
      }
    }
  }

  return {
    leagueId: league.id,
    leagueName: league.name,
    mode: normalizeMode(league.mode),
    status: normalizeStatus(league.status),
    season: league.calendar_season,
    teamLimit: toInteger(league.team_limit, 8),
    startingCredits: toInteger(league.starting_credits, 500),
    rosterSize: toInteger(league.roster_size, 25),
    isDirector: member.role === 'admin',
    currentRevision: revisionsResponse.count ?? revisions.length,
    updatedAt: league.updated_at,
    settings: mapSettings(
      league.scoring_rules,
      toInteger(league.roster_size, 25),
    ),
    revisions: revisions.map((revision) => ({
      id: revision.id,
      revision: toInteger(revision.revision, 0),
      reason: revision.reason,
      changedKeys: Array.isArray(revision.changed_keys)
        ? revision.changed_keys
        : [],
      changedAt: revision.changed_at,
      changedBy:
        (revision.changed_by && profileNames.get(revision.changed_by)) ||
        'Account eliminato',
    })),
  };
}

function isLegacySeasonFieldError(message: string) {
  const normalized = message.toLowerCase();
  return (
    normalized.includes('v_league') &&
    normalized.includes('has no field') &&
    normalized.includes('season')
  );
}

export function subscribeToLeagueRulebook(
  leagueId: string,
  onChange: () => void,
) {
  if (!supabase) {
    return () => undefined;
  }

  const client = supabase;
  const channel = client
    .channel(`league-rulebook-${leagueId}`)
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
        event: 'INSERT',
        schema: 'public',
        table: 'league_rule_revisions',
        filter: `league_id=eq.${leagueId}`,
      },
      onChange,
    )
    .subscribe();

  return () => {
    void client.removeChannel(channel);
  };
}

export function normalizeRulebook(value: unknown): LeagueRulebook {
  const raw = asRecord(
    Array.isArray(value) ? value[0] : value,
  ) as RawRulebook;
  const rosterSize = toInteger(raw.rosterSize, 25);
  const rules = asRecord(raw.rules);

  return {
    leagueId: toStringValue(raw.leagueId),
    leagueName: toStringValue(raw.leagueName),
    mode: normalizeMode(raw.mode),
    status: normalizeStatus(raw.status),
    season: toNullableString(raw.season),
    teamLimit: toInteger(raw.teamLimit, 8),
    startingCredits: toInteger(raw.startingCredits, 500),
    rosterSize,
    isDirector: Boolean(raw.isDirector),
    currentRevision: toInteger(raw.currentRevision, 0),
    updatedAt: toStringValue(raw.updatedAt),
    settings: mapSettings(rules, rosterSize),
    revisions: Array.isArray(raw.revisions)
      ? raw.revisions.map(normalizeRevision)
      : [],
  };
}

function normalizeRevision(value: unknown): LeagueRuleRevision {
  const raw = asRecord(value);
  return {
    id: toStringValue(raw.id),
    revision: toInteger(raw.revision, 0),
    reason: toStringValue(raw.reason),
    changedKeys: Array.isArray(raw.changedKeys)
      ? raw.changedKeys.filter(
          (item): item is string => typeof item === 'string',
        )
      : [],
    changedAt: toStringValue(raw.changedAt),
    changedBy: toStringValue(raw.changedBy) || 'Account eliminato',
  };
}

function normalizeMode(value: unknown): LeagueMode {
  return value === 'mantra' ? 'mantra' : 'classic';
}

function normalizeStatus(value: unknown): LeagueSummary['status'] {
  return value === 'active' ||
    value === 'completed' ||
    value === 'archived'
    ? value
    : 'draft';
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

function toInteger(value: unknown, fallback: number) {
  const parsed = Number(value);
  return Number.isInteger(parsed) ? parsed : fallback;
}

function translateRulebookError(message: string) {
  const normalized = message.toLowerCase();
  if (
    normalized.includes('get_league_rulebook') ||
    (normalized.includes('function') && normalized.includes('does not exist'))
  ) {
    return 'Aggiorna prima il database LEGHEVO con il file 056.';
  }
  if (normalized.includes('non fai parte')) {
    return 'Il regolamento è riservato ai membri della lega.';
  }
  return message;
}
