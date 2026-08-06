import { supabase } from '../lib/supabase';
import type {
  LeaguePostponementCenter,
  PostponedFixtureIssue,
  PostponedFixtureResolution,
} from '../types';

type RawResolution = {
  id: string;
  decision: string;
  politicalScore: number | string;
  reason: string;
  decidedAt: string;
  decidedBy: string;
  revision?: number | string;
  stateFingerprint?: string | null;
  protected?: boolean;
};

type RawIssue = {
  providerFixtureId: string;
  externalFixtureId: string;
  matchdayId: string;
  matchdayNumber: number | string;
  kickoffAt: string;
  status: string;
  homeTeam: string;
  awayTeam: string;
  locked: boolean;
  resolution: RawResolution | null;
};

type RawIntegrity = {
  healthy?: boolean;
  activeResolutionCount?: number | string;
  certifiedActionCount?: number | string;
  invalidResolutionCount?: number | string;
  invalidActionCount?: number | string;
  duplicateActiveCount?: number | string;
  idempotencyReady?: boolean;
  revisionReady?: boolean;
  providerFinalContinuityReady?: boolean;
};

type RawCenter = {
  leagueId: string;
  leagueName: string;
  isOwner: boolean;
  issueCount: number | string;
  resolvedCount: number | string;
  unresolvedCount: number | string;
  issues: RawIssue[] | null;
  protected?: boolean;
  idempotencyReady?: boolean;
  revisionReady?: boolean;
  certifiedActionCount?: number | string;
  lastCertifiedAt?: string | null;
  integrity?: RawIntegrity | null;
};

type GuardedActionResult = {
  actionRunId?: string;
  resolutionId?: string;
  revision?: number | string;
  stateFingerprint?: string | null;
  revokedAt?: string | null;
  protected?: boolean;
  idempotent?: boolean;
};

type PostponementActionOutcome = {
  actionRunId?: string | null;
  resolutionId?: string | null;
  revision?: number;
  stateFingerprint?: string | null;
  revokedAt?: string | null;
  protected?: boolean;
  idempotent?: boolean;
  error?: string;
};

export async function fetchLeaguePostponementCenter(
  leagueId: string,
): Promise<LeaguePostponementCenter> {
  if (!supabase) {
    throw new Error('Il collegamento al backend non è configurato.');
  }

  const guarded = await supabase.rpc('get_league_postponement_center_v2', {
    p_league_id: leagueId,
  });

  if (!guarded.error) {
    return mapCenter(normalizeRawCenter(guarded.data), true);
  }

  if (!isMissingGuardedPostponementFunction(guarded.error.message)) {
    throw new Error(translatePostponementError(guarded.error.message));
  }

  const legacy = await supabase.rpc('get_league_postponement_center', {
    p_league_id: leagueId,
  });

  if (legacy.error) {
    throw new Error(translatePostponementError(legacy.error.message));
  }

  return mapCenter(normalizeRawCenter(legacy.data), false);
}

export async function applyFixturePoliticalScore(
  leagueId: string,
  providerFixtureId: string,
  score: number,
  reason: string,
): Promise<PostponementActionOutcome> {
  if (!supabase) {
    return { error: 'Il collegamento al backend non è configurato.' };
  }

  const guarded = await supabase.rpc(
    'apply_league_fixture_political_score_guarded_v1',
    {
      p_league_id: leagueId,
      p_provider_fixture_id: providerFixtureId,
      p_political_score: score,
      p_reason: reason.trim(),
      p_idempotency_key: createOperationId(),
    },
  );

  if (!guarded.error) {
    return normalizeActionResult(guarded.data);
  }

  if (!isMissingGuardedPostponementFunction(guarded.error.message)) {
    return { error: translatePostponementError(guarded.error.message) };
  }

  const legacy = await supabase.rpc(
    'apply_league_fixture_political_score',
    {
      p_league_id: leagueId,
      p_provider_fixture_id: providerFixtureId,
      p_political_score: score,
      p_reason: reason.trim(),
    },
  );

  return legacy.error
    ? { error: translatePostponementError(legacy.error.message) }
    : {
        resolutionId: String(legacy.data),
        revision: 0,
        stateFingerprint: null,
        protected: false,
        idempotent: false,
      };
}

export async function revokeFixturePoliticalScore(
  leagueId: string,
  resolutionId: string,
  reason: string,
  expectedRevision: number,
): Promise<PostponementActionOutcome> {
  if (!supabase) {
    return { error: 'Il collegamento al backend non è configurato.' };
  }

  const guarded = await supabase.rpc(
    'revoke_league_fixture_political_score_guarded_v1',
    {
      p_league_id: leagueId,
      p_resolution_id: resolutionId,
      p_reason: reason.trim(),
      p_expected_revision: expectedRevision > 0 ? expectedRevision : null,
      p_idempotency_key: createOperationId(),
    },
  );

  if (!guarded.error) {
    return normalizeActionResult(guarded.data);
  }

  if (!isMissingGuardedPostponementFunction(guarded.error.message)) {
    return { error: translatePostponementError(guarded.error.message) };
  }

  const legacy = await supabase.rpc(
    'revoke_league_fixture_political_score',
    {
      p_league_id: leagueId,
      p_resolution_id: resolutionId,
      p_reason: reason.trim(),
    },
  );

  return legacy.error
    ? { error: translatePostponementError(legacy.error.message) }
    : {
        resolutionId,
        revision: expectedRevision,
        stateFingerprint: null,
        protected: false,
        idempotent: false,
      };
}

export function subscribeToFixtureResolutions(
  leagueId: string,
  onChange: () => void,
) {
  if (!supabase) {
    return () => undefined;
  }

  const client = supabase;
  const channel = client
    .channel(`fixture-resolutions-${leagueId}`)
    .on(
      'postgres_changes',
      {
        event: '*',
        schema: 'public',
        table: 'league_fixture_resolutions',
        filter: `league_id=eq.${leagueId}`,
      },
      onChange,
    )
    .on(
      'postgres_changes',
      {
        event: 'INSERT',
        schema: 'public',
        table: 'fixture_resolution_action_runs',
        filter: `league_id=eq.${leagueId}`,
      },
      onChange,
    )
    .subscribe();

  return () => {
    void client.removeChannel(channel);
  };
}

function mapCenter(raw: RawCenter, guarded: boolean): LeaguePostponementCenter {
  const integrity = raw.integrity ?? null;
  return {
    leagueId: raw.leagueId,
    leagueName: raw.leagueName,
    isOwner: Boolean(raw.isOwner),
    issueCount: toNumber(raw.issueCount),
    resolvedCount: toNumber(raw.resolvedCount),
    unresolvedCount: toNumber(raw.unresolvedCount),
    issues: (raw.issues ?? []).map((issue) => mapIssue(issue, guarded)),
    protected: guarded && Boolean(raw.protected),
    idempotencyReady: guarded && Boolean(raw.idempotencyReady),
    revisionReady: guarded && Boolean(raw.revisionReady),
    certifiedActionCount: toNumber(raw.certifiedActionCount),
    lastCertifiedAt: toNullableString(raw.lastCertifiedAt),
    integrity: {
      healthy: guarded && Boolean(integrity?.healthy),
      activeResolutionCount: toNumber(integrity?.activeResolutionCount),
      certifiedActionCount: toNumber(integrity?.certifiedActionCount),
      invalidResolutionCount: toNumber(integrity?.invalidResolutionCount),
      invalidActionCount: toNumber(integrity?.invalidActionCount),
      duplicateActiveCount: toNumber(integrity?.duplicateActiveCount),
      providerFinalContinuityReady:
        guarded && Boolean(integrity?.providerFinalContinuityReady),
    },
  };
}

function normalizeRawCenter(value: unknown): RawCenter {
  const raw = Array.isArray(value) ? value[0] : value;
  if (!raw || typeof raw !== 'object') {
    throw new Error('Il centro rinvii non ha restituito dati.');
  }
  return raw as RawCenter;
}

function mapIssue(raw: RawIssue, guarded: boolean): PostponedFixtureIssue {
  return {
    providerFixtureId: raw.providerFixtureId,
    externalFixtureId: raw.externalFixtureId,
    matchdayId: raw.matchdayId,
    matchdayNumber: toNumber(raw.matchdayNumber),
    kickoffAt: raw.kickoffAt,
    status: raw.status,
    homeTeam: raw.homeTeam,
    awayTeam: raw.awayTeam,
    locked: Boolean(raw.locked),
    resolution: raw.resolution
      ? mapResolution(raw.resolution, guarded)
      : null,
  };
}

function mapResolution(
  raw: RawResolution,
  guarded: boolean,
): PostponedFixtureResolution {
  return {
    id: raw.id,
    decision: 'political_score',
    politicalScore: toNumber(raw.politicalScore, 6),
    reason: raw.reason,
    decidedAt: raw.decidedAt,
    decidedBy: raw.decidedBy,
    revision: toNumber(raw.revision),
    stateFingerprint: toNullableString(raw.stateFingerprint),
    protected: guarded && Boolean(raw.protected),
  };
}

function normalizeActionResult(
  value: unknown,
): PostponementActionOutcome {
  const raw = (Array.isArray(value) ? value[0] : value) as
    | GuardedActionResult
    | null;
  return {
    actionRunId: toNullableString(raw?.actionRunId),
    resolutionId: toNullableString(raw?.resolutionId),
    revision: toNumber(raw?.revision),
    stateFingerprint: toNullableString(raw?.stateFingerprint),
    revokedAt: toNullableString(raw?.revokedAt),
    protected: Boolean(raw?.protected),
    idempotent: Boolean(raw?.idempotent),
  };
}

function createOperationId() {
  return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (token) => {
    const value = Math.floor(Math.random() * 16);
    const normalized = token === 'x' ? value : (value & 0x3) | 0x8;
    return normalized.toString(16);
  });
}

function toNumber(value: unknown, fallback = 0) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : fallback;
}

function toNullableString(value: unknown) {
  return typeof value === 'string' && value.length > 0 ? value : null;
}

function isMissingGuardedPostponementFunction(message: string) {
  const normalized = message.toLowerCase();
  return (
    normalized.includes('does not exist') ||
    normalized.includes('schema cache') ||
    normalized.includes('could not find the function')
  );
}

function translatePostponementError(message: string) {
  const normalized = message.toLowerCase();
  if (
    normalized.includes('get_league_postponement_center_v2') ||
    normalized.includes('political_score_guarded_v1') ||
    normalized.includes('fixture_resolution_action_runs')
  ) {
    return 'Aggiorna il database LEGHEVO con la migrazione 105.';
  }
  if (
    normalized.includes('get_league_postponement_center') ||
    normalized.includes('apply_league_fixture_political_score') ||
    normalized.includes('revoke_league_fixture_political_score') ||
    normalized.includes('league_fixture_resolutions')
  ) {
    return 'Aggiorna prima il database LEGHEVO con il file 052.';
  }
  if (normalized.includes('solo il presidente')) {
    return 'Solo il Presidente può modificare il voto d’ufficio.';
  }
  if (normalized.includes('riapri prima')) {
    return 'I risultati sono già ufficiali: riapri prima la giornata.';
  }
  if (normalized.includes('altro dispositivo')) {
    return 'La decisione è cambiata su un altro dispositivo. Aggiorna e riprova.';
  }
  if (normalized.includes('già attivo')) {
    return 'Per questa partita è già presente un voto d’ufficio differente.';
  }
  if (normalized.includes('non risulta rinviata')) {
    return 'Il provider non segnala più questa partita come rinviata.';
  }
  if (normalized.includes('motivazione')) {
    return 'Inserisci una motivazione valida per registrare la decisione.';
  }
  if (normalized.includes('non fai parte')) {
    return 'Non fai parte della lega selezionata.';
  }
  return message;
}
