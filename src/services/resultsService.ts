import { supabase } from '../lib/supabase';
import type {
  FixtureResultStatus,
  GoalBands,
  LeagueFixtureResult,
  LeagueMatchdayResult,
  LeagueResultsCenter,
  MatchdayResultStatus,
} from '../types';

type ResultActionOutcome = {
  affected?: number;
  error?: string;
};

export async function fetchLeagueResultsCenter(
  leagueId: string,
): Promise<LeagueResultsCenter> {
  if (!supabase) {
    throw new Error('Il collegamento al backend non è configurato.');
  }

  const { data, error } = await supabase.rpc(
    'get_league_results_center_v6',
    {
      p_league_id: leagueId,
    },
  );

  if (error) {
    throw new Error(translateResultsError(error.message));
  }

  const center = normalizeResultsCenter(data);
  if (!center.isOwner) {
    return center;
  }

  const remediation = await supabase.rpc(
    'get_league_provider_official_result_remediation_v1',
    { p_league_id: leagueId },
  );

  if (remediation.error) {
    throw new Error(translateResultsError(remediation.error.message));
  }

  return mergeProviderRemediation(center, remediation.data);
}

export async function finalizeLeagueMatchday(
  leagueId: string,
  matchdayId: string,
): Promise<ResultActionOutcome> {
  if (!supabase) {
    return { error: 'Il collegamento al backend non è configurato.' };
  }

  const requestId = createRequestId();
  let { data, error } = await supabase.rpc(
    'finalize_league_matchday_guarded_v3',
    {
      p_league_id: leagueId,
      p_matchday_id: matchdayId,
      p_request_id: requestId,
    },
  );

  if (
    error &&
    isMissingRpc(error.message, 'finalize_league_matchday_guarded_v3')
  ) {
    const guardedFallback = await supabase.rpc(
      'finalize_league_matchday_guarded_v2',
      {
        p_league_id: leagueId,
        p_matchday_id: matchdayId,
        p_request_id: requestId,
      },
    );
    const fallback = guardedFallback.error
      ? await supabase.rpc('finalize_league_matchday', {
          p_league_id: leagueId,
          p_matchday_id: matchdayId,
        })
      : guardedFallback;
    data = fallback.data;
    error = fallback.error;
  }

  if (error) {
    return { error: translateResultsError(error.message) };
  }

  const raw = asRecord(data);
  return {
    affected: Number(
      raw.finalizedFixtureCount ??
        raw.fixtureCount ??
        data ??
        0,
    ),
  };
}

export async function reopenLeagueMatchday(
  leagueId: string,
  matchdayId: string,
): Promise<ResultActionOutcome> {
  if (!supabase) {
    return { error: 'Il collegamento al backend non è configurato.' };
  }

  const requestId = createRequestId();
  let { data, error } = await supabase.rpc(
    'reopen_league_matchday_guarded_v1',
    {
      p_league_id: leagueId,
      p_matchday_id: matchdayId,
      p_reason:
        'Riapertura completa della giornata richiesta dal Presidente.',
      p_request_id: requestId,
    },
  );

  if (
    error &&
    isMissingRpc(error.message, 'reopen_league_matchday_guarded_v1')
  ) {
    const fallback = await supabase.rpc('reopen_league_matchday', {
      p_league_id: leagueId,
      p_matchday_id: matchdayId,
    });
    data = fallback.data;
    error = fallback.error;
  }

  if (error) {
    return { error: translateResultsError(error.message) };
  }

  const raw = asRecord(data);
  return {
    affected: Number(raw.affectedFixtureCount ?? data ?? 0),
  };
}

export async function reopenLeagueFixture(
  leagueId: string,
  fixtureId: string,
  reason: string,
  expectedProviderImpactGeneration?: number | null,
): Promise<ResultActionOutcome> {
  if (!supabase) {
    return { error: 'Il collegamento al backend non è configurato.' };
  }

  const requestId = createRequestId();
  const useProviderRemediation =
    typeof expectedProviderImpactGeneration === 'number' &&
    expectedProviderImpactGeneration > 0;
  let { data, error } = useProviderRemediation
    ? await supabase.rpc(
        'start_provider_official_result_remediation_v1',
        {
          p_league_id: leagueId,
          p_fixture_id: fixtureId,
          p_expected_assessment_generation:
            expectedProviderImpactGeneration,
          p_reason: reason,
          p_request_id: requestId,
        },
      )
    : await supabase.rpc(
        'reopen_league_fixture_guarded_v1',
        {
          p_league_id: leagueId,
          p_fixture_id: fixtureId,
          p_reason: reason,
          p_request_id: requestId,
        },
      );

  if (
    error &&
    isMissingRpc(error.message, 'reopen_league_fixture_guarded_v1')
  ) {
    const fallback = await supabase.rpc('reopen_league_fixture', {
      p_league_id: leagueId,
      p_fixture_id: fixtureId,
      p_reason: reason,
    });
    data = fallback.data;
    error = fallback.error;
  }

  if (error) {
    return { error: translateResultsError(error.message) };
  }

  const raw = asRecord(data);
  return {
    affected: Number(raw.affectedFixtureCount ?? data ?? 0),
  };
}

export function subscribeToLeagueResultsCenter(
  leagueId: string,
  onChange: () => void,
) {
  if (!supabase) {
    return () => undefined;
  }

  const client = supabase;
  const channel = client
    .channel(`results-center-${leagueId}`)
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
        table: 'matchday_officialization_runs',
        filter: `league_id=eq.${leagueId}`,
      },
      onChange,
    )
    .on(
      'postgres_changes',
      {
        event: '*',
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
        table: 'provider_official_result_remediation_events',
        filter: `league_id=eq.${leagueId}`,
      },
      onChange,
    )
    .subscribe();

  return () => {
    void client.removeChannel(channel);
  };
}

function normalizeResultsCenter(value: unknown): LeagueResultsCenter {
  const raw = asRecord(value);
  const rawMatchdays = Array.isArray(raw.matchdays) ? raw.matchdays : [];

  return {
    leagueId: toStringValue(raw.leagueId),
    leagueName: toStringValue(raw.leagueName),
    isOwner: Boolean(raw.isOwner),
    competitionStartedAt: toNullableString(raw.competitionStartedAt),
    goalThreshold: toNumber(raw.goalThreshold, 66),
    goalStep: toNumber(raw.goalStep, 6),
    goalBandsEnabled: Boolean(raw.goalBandsEnabled),
    goalBands: normalizeGoalBands(raw.goalBands),
    goalMarginEnabled: Boolean(raw.goalMarginEnabled),
    goalMargin: toNumber(raw.goalMargin, 4),
    matchdays: rawMatchdays
      .map(normalizeMatchday)
      .sort((left, right) => left.number - right.number),
  };
}

function normalizeGoalBands(value: unknown): GoalBands {
  if (!Array.isArray(value) || value.length !== 6) {
    return [66, 72, 78, 84, 90, 96];
  }
  const parsed = value.map(Number);
  return parsed.every(
    (item, index) =>
      Number.isFinite(item) &&
      item >= 50 &&
      item <= 150 &&
      (index === 0 || item > parsed[index - 1]),
  )
    ? (parsed as GoalBands)
    : [66, 72, 78, 84, 90, 96];
}

function normalizeMatchday(value: unknown): LeagueMatchdayResult {
  const raw = asRecord(value);
  const rawFixtures = Array.isArray(raw.fixtures) ? raw.fixtures : [];

  return {
    id: toStringValue(raw.id),
    number: toNumber(raw.number),
    startsAt: toStringValue(raw.startsAt),
    endsAt: toNullableString(raw.endsAt),
    fixtureCount: toNumber(raw.fixtureCount),
    readyCount: toNumber(raw.readyCount),
    officialCount: toNumber(raw.officialCount),
    status: normalizeMatchdayStatus(raw.status),
    canFinalize: Boolean(raw.canFinalize),
    canReopen: Boolean(raw.canReopen),
    fixtures: rawFixtures.map(normalizeFixture),
  };
}

function normalizeFixture(value: unknown): LeagueFixtureResult {
  const raw = asRecord(value);

  return {
    id: toStringValue(raw.id),
    homeTeamId: toStringValue(raw.homeTeamId),
    homeTeamName: toStringValue(raw.homeTeamName),
    awayTeamId: toStringValue(raw.awayTeamId),
    awayTeamName: toStringValue(raw.awayTeamName),
    homePoints: toNullableNumber(raw.homePoints),
    awayPoints: toNullableNumber(raw.awayPoints),
    homeBasePoints: toNullableNumber(raw.homeBasePoints),
    awayBasePoints: toNullableNumber(raw.awayBasePoints),
    homeDefenseModifier: toNumber(raw.homeDefenseModifier),
    awayDefenseModifier: toNumber(raw.awayDefenseModifier),
    homeBonusApplied: toNumber(raw.homeBonusApplied),
    homeGoalMarginBonus: toNumber(raw.homeGoalMarginBonus),
    awayGoalMarginBonus: toNumber(raw.awayGoalMarginBonus),
    homeGoals: toNullableNumber(raw.homeGoals),
    awayGoals: toNullableNumber(raw.awayGoals),
    homeCountedPlayers: toNumber(raw.homeCountedPlayers),
    awayCountedPlayers: toNumber(raw.awayCountedPlayers),
    homeReady: Boolean(raw.homeReady),
    awayReady: Boolean(raw.awayReady),
    finalizedAt: toNullableString(raw.finalizedAt),
    canCorrect: Boolean(raw.canCorrect),
    revision: toNumber(raw.revision),
    correctionReason: toNullableString(raw.correctionReason),
    correctedAt: toNullableString(raw.correctedAt),
    status: normalizeFixtureStatus(raw.status),
    providerImpactStatus: normalizeProviderImpactStatus(
      raw.providerImpactStatus,
    ),
    providerImpactGeneration: toNullableNumber(
      raw.providerImpactGeneration,
    ),
    providerImpactReasonCode: toNullableString(
      raw.providerImpactReasonCode,
    ),
    providerRemediationStatus: normalizeProviderRemediationStatus(
      raw.providerRemediationStatus,
    ),
    providerRemediationRequired: Boolean(
      raw.providerRemediationRequired,
    ),
    providerCausalStartCertified: Boolean(
      raw.providerCausalStartCertified,
    ),
  };
}

function mergeProviderRemediation(
  center: LeagueResultsCenter,
  value: unknown,
): LeagueResultsCenter {
  const raw = asRecord(value);
  const items = Array.isArray(raw.items) ? raw.items : [];
  const byFixture = new Map<string, Record<string, unknown>>();

  for (const item of items) {
    const itemRaw = asRecord(item);
    const fixtureId = toStringValue(itemRaw.fixtureId);
    if (fixtureId) {
      byFixture.set(fixtureId, itemRaw);
    }
  }

  return {
    ...center,
    matchdays: center.matchdays.map((matchday) => ({
      ...matchday,
      fixtures: matchday.fixtures.map((fixture) => {
        const remediation = byFixture.get(fixture.id);
        if (!remediation) {
          return fixture;
        }
        const remediationStatus = normalizeProviderRemediationStatus(
          remediation.remediationStatus,
        );
        return {
          ...fixture,
          providerImpactStatus:
            remediationStatus === 'open' ? 'affected' : 'in_correction',
          providerImpactGeneration: toNullableNumber(
            remediation.impactAssessmentGeneration,
          ),
          providerImpactReasonCode: toNullableString(
            remediation.impactReasonCode,
          ),
          providerRemediationStatus: remediationStatus,
          providerRemediationRequired: remediationStatus === 'open',
          providerCausalStartCertified: Boolean(
            remediation.causalStartCertified,
          ),
        };
      }),
    })),
  };
}

function normalizeProviderImpactStatus(
  value: unknown,
): LeagueFixtureResult['providerImpactStatus'] {
  if (value === 'clear' || value === 'affected' || value === 'in_correction') {
    return value;
  }
  return null;
}

function normalizeProviderRemediationStatus(
  value: unknown,
): LeagueFixtureResult['providerRemediationStatus'] {
  if (value === 'open' || value === 'in_correction') {
    return value;
  }
  return null;
}

function normalizeMatchdayStatus(value: unknown): MatchdayResultStatus {
  if (
    value === 'upcoming' ||
    value === 'live' ||
    value === 'pending' ||
    value === 'ready' ||
    value === 'official'
  ) {
    return value;
  }
  return 'upcoming';
}

function normalizeFixtureStatus(value: unknown): FixtureResultStatus {
  if (
    value === 'waiting' ||
    value === 'provisional' ||
    value === 'ready' ||
    value === 'official'
  ) {
    return value;
  }
  return 'waiting';
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

function toNumber(value: unknown, fallback = 0) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : fallback;
}

function toNullableNumber(value: unknown) {
  if (value === null || value === undefined || value === '') {
    return null;
  }
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : null;
}


function isMissingRpc(message: string, functionName: string) {
  const normalized = message.toLowerCase();
  return (
    normalized.includes(functionName.toLowerCase()) &&
    (normalized.includes('does not exist') || normalized.includes('not found'))
  );
}

function createRequestId() {
  const template = 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx';
  return template.replace(/[xy]/g, (character) => {
    const random = Math.floor(Math.random() * 16);
    const value = character === 'x' ? random : (random & 0x3) | 0x8;
    return value.toString(16);
  });
}

function translateResultsError(message: string) {
  const normalized = message.toLowerCase();
  if (
    normalized.includes('start_provider_official_result_remediation_v1') ||
    normalized.includes('get_league_provider_official_result_remediation_v1')
  ) {
    return 'Esegui prima lo script Supabase della versione v0.62.23.';
  }
  if (
    normalized.includes('get_league_results_center_v6') ||
    normalized.includes('finalize_league_matchday_guarded_v3') ||
    normalized.includes('finalize_league_matchday_guarded_v2') ||
    normalized.includes('finalize_league_matchday_guarded_v1') ||
    normalized.includes('finalize_league_matchday') ||
    normalized.includes('reopen_league_matchday_guarded_v1') ||
    normalized.includes('reopen_league_matchday') ||
    normalized.includes('reopen_league_fixture_guarded_v1') ||
    normalized.includes('reopen_league_fixture') ||
    (normalized.includes('function') && normalized.includes('does not exist'))
  ) {
    return 'Aggiorna prima il database LEGHEVO fino al file 081.';
  }
  if (
    normalized.includes('valutazione provider è cambiata') ||
    normalized.includes('non richiede più una correzione provider')
  ) {
    return 'Lo stato provider è cambiato: aggiorna i risultati prima di procedere.';
  }
  if (normalized.includes('esposto a un impatto provider')) {
    return 'Correggi prima le partite provider segnalate usando il percorso protetto.';
  }
  if (normalized.includes('solo il presidente')) {
    return 'Questa operazione è riservata al Presidente della lega.';
  }
  if (normalized.includes('motivazione')) {
    return 'Inserisci una motivazione da 10 a 240 caratteri.';
  }
  if (normalized.includes('non fai parte')) {
    return 'Non fai parte della lega selezionata.';
  }
  return message;
}
