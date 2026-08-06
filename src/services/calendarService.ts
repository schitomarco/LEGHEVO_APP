import { supabase } from '../lib/supabase';
import type {
  CalendarFixture,
  CalendarSchedulePreview,
  CalendarTeamReadiness,
  LeagueCalendarState,
  LeagueScheduleHealth,
} from '../types';

type FixtureRow = {
  id: string;
  matchday_id: string;
  home_team_id: string;
  away_team_id: string;
  home_points: number | string | null;
  away_points: number | string | null;
  home_goals: number | null;
  away_goals: number | null;
  finalized_at: string | null;
};

type MatchdayRow = {
  id: string;
  number: number;
  starts_at: string;
  locks_at: string;
  ends_at: string | null;
  schedule_source: string;
  schedule_synced_at: string | null;
  provider_fixture_count: number;
  provider_final_fixture_count: number;
};

type CalendarTeamRow = {
  id: string;
  name: string;
  manager_id: string;
};

export type GenerateCalendarInput = {
  leagueId: string;
  season: string;
  startMatchday: number;
  firstKickoff: string;
  returnLeg: boolean;
};

export type CalendarActionOutcome = {
  affected?: number;
  error?: string;
};

export async function fetchLeagueCalendar(
  leagueId: string,
): Promise<CalendarFixture[]> {
  if (!supabase) {
    return [];
  }

  const { data: fixtureData, error: fixtureError } = await supabase
    .from('fantasy_fixtures')
    .select(
      'id, matchday_id, home_team_id, away_team_id, home_points, away_points, home_goals, away_goals, finalized_at',
    )
    .eq('league_id', leagueId);

  if (fixtureError) {
    throw new Error(translateCalendarError(fixtureError.message));
  }

  const fixtures = (fixtureData ?? []) as FixtureRow[];
  if (fixtures.length === 0) {
    return [];
  }

  const matchdayIds = [...new Set(fixtures.map((item) => item.matchday_id))];
  const teamIds = [
    ...new Set(
      fixtures.flatMap((item) => [item.home_team_id, item.away_team_id]),
    ),
  ];

  const [matchdaysResponse, teamsResponse] = await Promise.all([
    supabase
      .from('matchdays')
      .select(
        'id, number, starts_at, locks_at, ends_at, schedule_source, schedule_synced_at, provider_fixture_count, provider_final_fixture_count',
      )
      .in('id', matchdayIds),
    supabase
      .from('fantasy_teams')
      .select('id, name, manager_id')
      .in('id', teamIds),
  ]);

  if (matchdaysResponse.error) {
    throw new Error(translateCalendarError(matchdaysResponse.error.message));
  }
  if (teamsResponse.error) {
    throw new Error(translateCalendarError(teamsResponse.error.message));
  }

  const matchdays = (matchdaysResponse.data ?? []) as MatchdayRow[];
  const teams = (teamsResponse.data ?? []) as CalendarTeamRow[];
  const matchdaysById = new Map(
    matchdays.map((matchday) => [matchday.id, matchday]),
  );
  const teamsById = new Map(teams.map((team) => [team.id, team]));

  return fixtures
    .map((fixture) => {
      const matchday = matchdaysById.get(fixture.matchday_id);
      const homeTeam = teamsById.get(fixture.home_team_id);
      const awayTeam = teamsById.get(fixture.away_team_id);

      if (!matchday || !homeTeam || !awayTeam) {
        return null;
      }

      return {
        id: fixture.id,
        matchdayId: fixture.matchday_id,
        matchdayNumber: matchday.number,
        startsAt: matchday.starts_at,
        locksAt: matchday.locks_at,
        endsAt: matchday.ends_at,
        scheduleSource:
          matchday.schedule_source === 'provider'
            ? 'provider'
            : 'estimated',
        scheduleSyncedAt: matchday.schedule_synced_at,
        providerFixtureCount: toNumber(matchday.provider_fixture_count),
        providerFinalFixtureCount: toNumber(
          matchday.provider_final_fixture_count,
        ),
        homeTeam: {
          id: homeTeam.id,
          name: homeTeam.name,
          managerId: homeTeam.manager_id,
        },
        awayTeam: {
          id: awayTeam.id,
          name: awayTeam.name,
          managerId: awayTeam.manager_id,
        },
        homePoints: toNullableNumber(fixture.home_points),
        awayPoints: toNullableNumber(fixture.away_points),
        homeGoals: fixture.home_goals,
        awayGoals: fixture.away_goals,
        finalized: Boolean(fixture.finalized_at),
      } satisfies CalendarFixture;
    })
    .filter((fixture): fixture is CalendarFixture => Boolean(fixture))
    .sort(
      (left, right) =>
        left.matchdayNumber - right.matchdayNumber ||
        left.homeTeam.name.localeCompare(right.homeTeam.name),
    );
}

export async function fetchLeagueCalendarState(
  leagueId: string,
): Promise<LeagueCalendarState> {
  if (!supabase) {
    throw new Error('Il collegamento al backend non è configurato.');
  }

  const latest = await supabase.rpc('get_league_calendar_state_v3', {
    p_league_id: leagueId,
  });

  if (!latest.error) {
    return normalizeCalendarState(latest.data);
  }

  const latestMessage = latest.error.message.toLowerCase();
  const missingLatest =
    latestMessage.includes('does not exist') ||
    latestMessage.includes('get_league_calendar_state_v3');
  if (!missingLatest) {
    throw new Error(translateCalendarError(latest.error.message));
  }

  const fallbackV2 = await supabase.rpc('get_league_calendar_state_v2', {
    p_league_id: leagueId,
  });
  if (!fallbackV2.error) {
    return normalizeCalendarState(fallbackV2.data);
  }

  const fallback = await supabase.rpc('get_league_calendar_state', {
    p_league_id: leagueId,
  });
  if (fallback.error) {
    throw new Error(translateCalendarError(fallback.error.message));
  }

  return normalizeCalendarState(fallback.data);
}

export async function fetchLeagueScheduleHealth(
  leagueId: string,
): Promise<LeagueScheduleHealth> {
  if (!supabase) {
    throw new Error('Il collegamento al backend non è configurato.');
  }

  const { data, error } = await supabase.rpc(
    'get_league_schedule_health',
    { p_league_id: leagueId },
  );

  if (error) {
    throw new Error(translateCalendarError(error.message));
  }

  return normalizeScheduleHealth(data);
}

export async function fetchCalendarSchedulePreview(
  season: string,
  firstMatchday: number,
  lastMatchday: number,
): Promise<CalendarSchedulePreview> {
  const requestedMatchdays = Math.max(lastMatchday - firstMatchday + 1, 0);
  if (!supabase || requestedMatchdays === 0) {
    return {
      requestedMatchdays,
      availableMatchdays: 0,
      providerAlignedMatchdays: 0,
      estimatedMatchdays: 0,
      missingMatchdays: requestedMatchdays,
      firstKickoff: null,
    };
  }

  const { data, error } = await supabase
    .from('matchdays')
    .select('number, starts_at, schedule_source')
    .eq('competition_code', 'IT-SA')
    .eq('season', season)
    .gte('number', firstMatchday)
    .lte('number', lastMatchday)
    .order('number');

  if (error) {
    throw new Error(translateCalendarError(error.message));
  }

  const rows = (data ?? []) as Array<{
    number: number;
    starts_at: string;
    schedule_source: string;
  }>;
  const providerAlignedMatchdays = rows.filter(
    (row) => row.schedule_source === 'provider',
  ).length;
  const first = rows.find((row) => row.number === firstMatchday);

  return {
    requestedMatchdays,
    availableMatchdays: rows.length,
    providerAlignedMatchdays,
    estimatedMatchdays: rows.length - providerAlignedMatchdays,
    missingMatchdays: Math.max(requestedMatchdays - rows.length, 0),
    firstKickoff: first?.starts_at ?? null,
  };
}

export async function generateLeagueCalendar(
  input: GenerateCalendarInput,
): Promise<CalendarActionOutcome> {
  if (!supabase) {
    return { error: 'Il collegamento al backend non è configurato.' };
  }

  const { data, error } = await supabase.rpc(
    'generate_head_to_head_calendar_guarded_v2',
    {
      p_league_id: input.leagueId,
      p_season: input.season,
      p_start_matchday: input.startMatchday,
      p_first_kickoff: input.firstKickoff,
      p_return_leg: input.returnLeg,
    },
  );

  if (error) {
    return { error: translateCalendarError(error.message) };
  }

  const raw =
    data && typeof data === 'object'
      ? (data as Record<string, unknown>)
      : {};
  return { affected: toNumber(raw.affected) };
}

export async function resetLeagueCalendar(
  leagueId: string,
): Promise<CalendarActionOutcome> {
  if (!supabase) {
    return { error: 'Il collegamento al backend non è configurato.' };
  }

  const { data, error } = await supabase.rpc('reset_league_calendar', {
    p_league_id: leagueId,
  });

  if (error) {
    return { error: translateCalendarError(error.message) };
  }

  return { affected: Number(data ?? 0) };
}

export function subscribeToLeagueCalendar(
  leagueId: string,
  onChange: () => void,
) {
  if (!supabase) {
    return () => undefined;
  }

  const client = supabase;
  const channel = client
    .channel(`league-calendar-${leagueId}`)
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
        table: 'fantasy_teams',
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
        event: 'UPDATE',
        schema: 'public',
        table: 'matchdays',
      },
      onChange,
    )
    .subscribe();

  return () => {
    void client.removeChannel(channel);
  };
}

function normalizeScheduleHealth(value: unknown): LeagueScheduleHealth {
  const raw =
    value && typeof value === 'object'
      ? (value as Record<string, unknown>)
      : {};
  const nextRaw =
    raw.nextMatchday && typeof raw.nextMatchday === 'object'
      ? (raw.nextMatchday as Record<string, unknown>)
      : null;
  const nextId = nextRaw ? toNullableString(nextRaw.id) : null;
  const nextStartsAt = nextRaw
    ? toNullableString(nextRaw.startsAt)
    : null;
  const nextLocksAt = nextRaw ? toNullableString(nextRaw.locksAt) : null;

  return {
    matchdayCount: toNumber(raw.matchdayCount),
    providerAlignedMatchdays: toNumber(raw.providerAlignedMatchdays),
    estimatedMatchdays: toNumber(raw.estimatedMatchdays),
    lastScheduleSyncAt: toNullableString(raw.lastScheduleSyncAt),
    nextMatchday:
      nextRaw && nextId && nextStartsAt && nextLocksAt
        ? {
            id: nextId,
            number: toNumber(nextRaw.number),
            startsAt: nextStartsAt,
            locksAt: nextLocksAt,
            endsAt: toNullableString(nextRaw.endsAt),
            scheduleSource:
              nextRaw.scheduleSource === 'provider'
                ? 'provider'
                : 'estimated',
            providerFixtureCount: toNumber(
              nextRaw.providerFixtureCount,
            ),
            providerFinalFixtureCount: toNumber(
              nextRaw.providerFinalFixtureCount,
            ),
          }
        : null,
  };
}

function normalizeCalendarState(value: unknown): LeagueCalendarState {
  const raw =
    value && typeof value === 'object'
      ? (value as Record<string, unknown>)
      : {};
  const rawChecks =
    raw.checks && typeof raw.checks === 'object'
      ? (raw.checks as Record<string, unknown>)
      : {};
  const rawTeams = Array.isArray(raw.teams) ? raw.teams : [];
  const preflightRaw =
    raw.preflight && typeof raw.preflight === 'object'
      ? (raw.preflight as Record<string, unknown>)
      : {};
  const preflightChecksRaw =
    preflightRaw.checks && typeof preflightRaw.checks === 'object'
      ? (preflightRaw.checks as Record<string, unknown>)
      : {};

  const marketReady = Boolean(
    rawChecks.marketReady ?? preflightChecksRaw.marketReady ?? true,
  );
  const tradesSettled = Boolean(
    rawChecks.tradesSettled ?? preflightChecksRaw.tradesSettled ?? true,
  );
  const auctionIntegrityReady = Boolean(
    rawChecks.auctionIntegrityReady ??
      preflightChecksRaw.auctionIntegrityReady ??
      true,
  );
  const auctionClosed = Boolean(
    rawChecks.auctionClosed ?? preflightChecksRaw.auctionClosed ?? true,
  );
  const calendarIntegrityReady = Boolean(
    rawChecks.calendarIntegrityReady ??
      preflightChecksRaw.calendarIntegrityReady ??
      false,
  );
  const calendarSnapshotStable = Boolean(
    rawChecks.calendarSnapshotStable ??
      preflightChecksRaw.calendarSnapshotStable ??
      false,
  );
  const precompetitionSnapshotLocked = Boolean(
    rawChecks.precompetitionSnapshotLocked ??
      preflightChecksRaw.precompetitionSnapshotLocked ??
      false,
  );
  const snapshotMutationGuardReady = Boolean(
    rawChecks.snapshotMutationGuardReady ??
      preflightChecksRaw.snapshotMutationGuardReady ??
      false,
  );

  return {
    memberCount: toNumber(raw.memberCount),
    teamCount: toNumber(raw.teamCount),
    teamLimit: toNumber(raw.teamLimit),
    fullRosterCount: toNumber(raw.fullRosterCount),
    rosterSize: toNumber(raw.rosterSize),
    fixtureCount: toNumber(raw.fixtureCount),
    matchdayCount: toNumber(raw.matchdayCount),
    firstMatchday: toNullableInteger(raw.firstMatchday),
    lastMatchday: toNullableInteger(raw.lastMatchday),
    season: toNullableString(raw.season),
    returnLeg: Boolean(raw.returnLeg),
    generatedAt: toNullableString(raw.generatedAt),
    competitionStartedAt: toNullableString(raw.competitionStartedAt),
    calendarExists: Boolean(raw.calendarExists),
    isOwner: Boolean(raw.isOwner),
    isDirector: Boolean(raw.isDirector),
    canGenerate: Boolean(raw.canGenerate),
    canReset: Boolean(raw.canReset),
    checks: {
      membersReady: Boolean(rawChecks.membersReady),
      teamsReady: Boolean(rawChecks.teamsReady),
      rostersReady: Boolean(rawChecks.rostersReady),
      calendarEmpty: Boolean(rawChecks.calendarEmpty),
      competitionNotStarted: Boolean(
        rawChecks.competitionNotStarted,
      ),
      marketReady,
      tradesSettled,
      auctionIntegrityReady,
      auctionClosed,
      calendarIntegrityReady,
      calendarSnapshotStable,
      precompetitionSnapshotLocked,
      snapshotMutationGuardReady,
    },
    preflight: {
      version: toNumber(preflightRaw.version),
      checkedAt: toNullableString(preflightRaw.checkedAt),
      pendingTradeCount: toNumber(preflightRaw.pendingTradeCount),
      unfinishedAuctionCount: toNumber(
        preflightRaw.unfinishedAuctionCount,
      ),
      biddingItemCount: toNumber(preflightRaw.biddingItemCount),
      expectedFixtureCount: toNumber(
        preflightRaw.expectedFixtureCount,
      ),
      expectedMatchdayCount: toNumber(
        preflightRaw.expectedMatchdayCount,
      ),
      pairIssueCount: toNumber(preflightRaw.pairIssueCount),
      teamMatchdayIssueCount: toNumber(
        preflightRaw.teamMatchdayIssueCount,
      ),
      calendarSnapshotPresent: Boolean(
        preflightRaw.calendarSnapshotPresent,
      ),
      calendarSnapshotStable: Boolean(
        preflightRaw.calendarSnapshotStable,
      ),
      calendarIntegrityVerifiedAt: toNullableString(
        preflightRaw.calendarIntegrityVerifiedAt,
      ),
      precompetitionSnapshotLocked,
      snapshotMutationGuardReady,
      snapshotMutationGuardCount: toNumber(
        preflightRaw.snapshotMutationGuardCount,
      ),
      canGenerateCalendar: Boolean(
        preflightRaw.canGenerateCalendar ?? raw.canGenerate,
      ),
      canStartCompetition: Boolean(
        preflightRaw.canStartCompetition,
      ),
      checks: {
        marketReady,
        tradesSettled,
        auctionIntegrityReady,
        auctionClosed,
        calendarIntegrityReady,
        calendarSnapshotStable,
        precompetitionSnapshotLocked,
        snapshotMutationGuardReady,
      },
    },
    teams: rawTeams
      .map(normalizeTeamReadiness)
      .filter((team): team is CalendarTeamReadiness => Boolean(team)),
  };
}

function normalizeTeamReadiness(
  value: unknown,
): CalendarTeamReadiness | null {
  if (!value || typeof value !== 'object') {
    return null;
  }
  const raw = value as Record<string, unknown>;
  const teamId = toNullableString(raw.teamId);
  const teamName = toNullableString(raw.teamName);
  const managerId = toNullableString(raw.managerId);

  if (!teamId || !teamName || !managerId) {
    return null;
  }

  return {
    teamId,
    teamName,
    managerId,
    rosterCount: toNumber(raw.rosterCount),
    rosterSize: toNumber(raw.rosterSize),
    complete: Boolean(raw.complete),
  };
}

function toNumber(value: unknown) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : 0;
}

function toNullableInteger(value: unknown) {
  if (value === null || value === undefined) {
    return null;
  }
  const parsed = Number(value);
  return Number.isInteger(parsed) ? parsed : null;
}

function toNullableNumber(value: number | string | null) {
  if (value === null) {
    return null;
  }
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : null;
}

function toNullableString(value: unknown) {
  return typeof value === 'string' && value.length > 0 ? value : null;
}

function translateCalendarError(message: string) {
  const normalized = message.toLowerCase();

  if (
    normalized.includes('get_league_calendar_state') ||
    normalized.includes('get_league_competition_readiness_v2') ||
    normalized.includes('get_league_competition_readiness_v1') ||
    normalized.includes('generate_head_to_head_calendar_guarded_v2') ||
    normalized.includes('generate_head_to_head_calendar_guarded') ||
    normalized.includes('get_league_schedule_health') ||
    normalized.includes('reset_league_calendar') ||
    (normalized.includes('function') && normalized.includes('does not exist'))
  ) {
    if (normalized.includes('get_league_schedule_health')) {
      return 'Aggiorna prima il database LEGHEVO con il file 031.';
    }
    if (
      normalized.includes('get_league_competition_readiness_v2') ||
    normalized.includes('get_league_competition_readiness_v1') ||
      normalized.includes('generate_head_to_head_calendar_guarded_v2') ||
    normalized.includes('generate_head_to_head_calendar_guarded') ||
      normalized.includes('get_league_calendar_state_v2')
    ) {
      return 'Aggiorna prima Supabase con il file 072.';
    }
    return 'Aggiorna prima il database LEGHEVO con il file 028.';
  }
  if (
    normalized.includes('schedule_source') ||
    normalized.includes('provider_fixture_count')
  ) {
    return 'Aggiorna prima il database LEGHEVO con il file 031.';
  }
  if (normalized.includes('non fai parte')) {
    return 'Questa lega non è più associata al tuo account.';
  }
  if (normalized.includes('spogliatoio non è completo')) {
    return 'Prima devono entrare tutte le squadre previste nella lega.';
  }
  if (normalized.includes('rose devono essere complete')) {
    return 'Prima tutte le squadre devono completare la propria rosa.';
  }
  if (normalized.includes('già stato generato')) {
    return 'Il calendario di questa lega esiste già.';
  }
  if (normalized.includes('solo il presidente')) {
    return 'Questa operazione è riservata al Presidente della lega.';
  }
  if (normalized.includes('competizione è già iniziata')) {
    return 'La competizione è già iniziata: il calendario è definitivo.';
  }
  if (normalized.includes('competizione è iniziata')) {
    return 'La competizione è iniziata: il calendario non può più cambiare.';
  }
  if (normalized.includes('trattative ancora in attesa')) {
    return 'Chiudi o annulla tutte le trattative prima del sorteggio.';
  }
  if (normalized.includes("termina l'asta live")) {
    return 'Termina l’Asta Live prima di generare il calendario.';
  }
  if (normalized.includes('mercato segnala anomalie')) {
    return 'Il Mercato segnala anomalie da risolvere prima del sorteggio.';
  }
  if (normalized.includes('asta live segnala anomalie')) {
    return 'L’Asta Live segnala anomalie da risolvere prima del sorteggio.';
  }
  if (normalized.includes('verifica calendario non superata')) {
    return 'Il sorteggio non ha superato i controlli automatici ed è stato annullato.';
  }
  if (normalized.includes('calendario è già stato sorteggiato')) {
    return 'Il calendario è già sorteggiato: annullalo prima di cambiare l’assetto della lega.';
  }
  if (normalized.includes('stagione deve avere quattro cifre')) {
    return 'Inserisci la stagione con quattro cifre, ad esempio 2026.';
  }
  if (normalized.includes('giornata iniziale')) {
    return 'Scegli una giornata iniziale compatibile con la formula.';
  }

  return message;
}
