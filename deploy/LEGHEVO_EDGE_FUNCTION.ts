import { withSupabase } from 'npm:@supabase/server@1';
import type { SupabaseClient } from 'npm:@supabase/supabase-js@2';

// LEGHEVO v0.62.20 · Edge Function API-Football con coerenza causale partita/voti,
// ciclo vita monotono, pubblicazione atomica, watermark, quarantena, lease e fencing.
// File standalone per il deploy della funzione sync-football-data.

const API_BASE_URL = 'https://v3.football.api-sports.io';

const PROVIDER_PAYLOAD_CONTRACT_VERSION =
  'api-football-v3/leghevo-contract-v1';

type ProviderDeliveryMetadata = {
  path: string;
  current: number;
  total: number;
  results: number;
  entityKeys: string[];
};

type ApiFootballEnvelope<T> = {
  errors: Record<string, string> | string[];
  paging: {
    current: number;
    total: number;
  };
  response: T[];
  results: number;
  delivery: ProviderDeliveryMetadata;
};

type ProviderContractIssue = {
  code: string;
  summary: string;
  itemIndex: number | null;
};

class ProviderContractError extends Error {
  readonly contractVersion = PROVIDER_PAYLOAD_CONTRACT_VERSION;

  constructor(
    readonly scope: string,
    readonly code: string,
    readonly itemIndex: number | null,
    readonly payloadFingerprint: string,
    readonly payloadSize: number,
    summary: string,
  ) {
    super(summary);
    this.name = 'ProviderContractError';
    Object.setPrototypeOf(this, ProviderContractError.prototype);
  }
}

async function createProviderContractError(
  scope: string,
  code: string,
  summary: string,
  payload: unknown,
  itemIndex: number | null = null,
): Promise<ProviderContractError> {
  const serialized = serializePayload(payload);
  const encoded = new TextEncoder().encode(serialized);
  const digest = await crypto.subtle.digest('SHA-256', encoded);
  const fingerprint = Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, '0'))
    .join('');

  return new ProviderContractError(
    normalizeContractToken(scope, 'scope'),
    normalizeContractToken(code, 'contract.invalid'),
    itemIndex,
    fingerprint,
    encoded.byteLength,
    sanitizeSummary(summary),
  );
}


class ProviderDeliveryError extends Error {
  constructor(
    readonly code: string,
    summary: string,
  ) {
    super(`Consegna provider incompleta [${code}]: ${summary}`);
    this.name = 'ProviderDeliveryError';
    Object.setPrototypeOf(this, ProviderDeliveryError.prototype);
  }
}

class ApiFootballClient {
  constructor(private readonly apiKey: string) {}

  async get<T>(
    path: string,
    parameters: Record<string, string | number>,
  ): Promise<ApiFootballEnvelope<T>> {
    const url = new URL(`${API_BASE_URL}${path}`);
    Object.entries(parameters).forEach(([key, value]) => {
      url.searchParams.set(key, String(value));
    });

    const response = await fetch(url, {
      headers: {
        'x-apisports-key': this.apiKey,
      },
    });

    if (!response.ok) {
      throw new Error(
        `API-Football ha risposto con HTTP ${response.status}.`,
      );
    }

    const rawBody = await response.text();
    let parsedBody: unknown;
    try {
      parsedBody = JSON.parse(rawBody);
    } catch {
      throw await createProviderContractError(
        `envelope:${path}`,
        'invalid_json',
        'Payload provider non valido [envelope.invalid_json]: la risposta non è JSON valido.',
        rawBody,
      );
    }

    const envelopeIssue = validateEnvelope(parsedBody);
    if (envelopeIssue) {
      throw await createProviderContractError(
        `envelope:${path}`,
        envelopeIssue.code,
        envelopeIssue.summary,
        rawBody,
        envelopeIssue.itemIndex,
      );
    }

    const body = parsedBody as ApiFootballEnvelope<unknown>;
    const errors = Array.isArray(body.errors)
      ? body.errors
      : Object.values(body.errors ?? {});

    if (errors.length > 0) {
      throw new Error(`API-Football: ${errors.join(', ')}`);
    }

    const responseIssue = validateEndpointResponse(path, body.response);
    if (responseIssue) {
      throw await createProviderContractError(
        `response:${path}`,
        responseIssue.code,
        responseIssue.summary,
        rawBody,
        responseIssue.itemIndex,
      );
    }

    const delivery = validateProviderDelivery(path, parameters, body);
    return { ...body, delivery } as ApiFootballEnvelope<T>;
  }
}

function validateEnvelope(value: unknown): ProviderContractIssue | null {
  const raw = asRecord(value);
  if (!raw) {
    return issue(
      'envelope.object',
      'Payload provider non valido [envelope.object]: è richiesto un oggetto.',
    );
  }

  const errors = raw.errors;
  if (!Array.isArray(errors) && !asRecord(errors)) {
    return issue(
      'envelope.errors',
      'Payload provider non valido [envelope.errors]: campo errors non conforme.',
    );
  }
  if (Array.isArray(errors) && errors.some((item) => typeof item !== 'string')) {
    return issue(
      'envelope.errors_items',
      'Payload provider non valido [envelope.errors_items]: errors contiene valori non testuali.',
    );
  }
  if (
    !Array.isArray(errors) &&
    Object.values(errors as Record<string, unknown>).some(
      (item) => typeof item !== 'string',
    )
  ) {
    return issue(
      'envelope.errors_values',
      'Payload provider non valido [envelope.errors_values]: errors contiene valori non testuali.',
    );
  }

  const paging = asRecord(raw.paging);
  if (
    !paging ||
    !isNonNegativeInteger(paging.current) ||
    !isNonNegativeInteger(paging.total)
  ) {
    return issue(
      'envelope.paging',
      'Payload provider non valido [envelope.paging]: paginazione non conforme.',
    );
  }

  if (!Array.isArray(raw.response)) {
    return issue(
      'envelope.response',
      'Payload provider non valido [envelope.response]: response deve essere un array.',
    );
  }
  if (!isNonNegativeInteger(raw.results)) {
    return issue(
      'envelope.results',
      'Payload provider non valido [envelope.results]: results non è un intero valido.',
    );
  }

  return null;
}

function validateEndpointResponse(
  path: string,
  response: unknown[],
): ProviderContractIssue | null {
  switch (path) {
    case '/players':
      return validateSeasonPlayers(response);
    case '/fixtures':
      return validateFixtures(response);
    case '/fixtures/players':
      return validateFixturePlayers(response);
    default:
      return issue(
        'endpoint.unsupported',
        `Payload provider non valido [endpoint.unsupported]: endpoint ${path} non certificato.`,
      );
  }
}

function validateSeasonPlayers(
  response: unknown[],
): ProviderContractIssue | null {
  for (let index = 0; index < response.length; index += 1) {
    const item = asRecord(response[index]);
    const player = item ? asRecord(item.player) : null;
    if (!item || !player) {
      return issue(
        'players.item',
        `Payload provider non valido [players.item] all'indice ${index}.`,
        index,
      );
    }
    if (!isPositiveInteger(player.id) || !isNonEmptyString(player.name)) {
      return issue(
        'players.identity',
        `Payload provider non valido [players.identity] all'indice ${index}.`,
        index,
      );
    }
    if (
      !isNullableString(player.firstname) ||
      !isNullableString(player.lastname) ||
      !isNullableString(player.photo)
    ) {
      return issue(
        'players.profile',
        `Payload provider non valido [players.profile] all'indice ${index}.`,
        index,
      );
    }
    if (!Array.isArray(item.statistics)) {
      return issue(
        'players.statistics',
        `Payload provider non valido [players.statistics] all'indice ${index}.`,
        index,
      );
    }
    if (item.statistics.length > 0) {
      const statistics = asRecord(item.statistics[0]);
      const team = statistics ? asRecord(statistics.team) : null;
      const games = statistics ? asRecord(statistics.games) : null;
      if (
        !statistics ||
        !team ||
        !games ||
        !isPositiveInteger(team.id) ||
        !isNonEmptyString(team.name) ||
        !isNullableString(games.position)
      ) {
        return issue(
          'players.statistics_shape',
          `Payload provider non valido [players.statistics_shape] all'indice ${index}.`,
          index,
        );
      }
    }
  }
  return null;
}

function validateFixtures(response: unknown[]): ProviderContractIssue | null {
  for (let index = 0; index < response.length; index += 1) {
    const item = asRecord(response[index]);
    const fixture = item ? asRecord(item.fixture) : null;
    const status = fixture ? asRecord(fixture.status) : null;
    const league = item ? asRecord(item.league) : null;
    const teams = item ? asRecord(item.teams) : null;
    const home = teams ? asRecord(teams.home) : null;
    const away = teams ? asRecord(teams.away) : null;
    const goals = item ? asRecord(item.goals) : null;

    if (!item || !fixture || !status || !league || !home || !away || !goals) {
      return issue(
        'fixtures.item',
        `Payload provider non valido [fixtures.item] all'indice ${index}.`,
        index,
      );
    }
    if (
      !isPositiveInteger(fixture.id) ||
      !isValidDateString(fixture.date) ||
      !isNonEmptyString(status.short) ||
      !isNonEmptyString(league.round)
    ) {
      return issue(
        'fixtures.identity',
        `Payload provider non valido [fixtures.identity] all'indice ${index}.`,
        index,
      );
    }
    if (
      !isPositiveInteger(home.id) ||
      !isNonEmptyString(home.name) ||
      !isPositiveInteger(away.id) ||
      !isNonEmptyString(away.name)
    ) {
      return issue(
        'fixtures.teams',
        `Payload provider non valido [fixtures.teams] all'indice ${index}.`,
        index,
      );
    }
    if (!isNullableFiniteNumber(goals.home) || !isNullableFiniteNumber(goals.away)) {
      return issue(
        'fixtures.goals',
        `Payload provider non valido [fixtures.goals] all'indice ${index}.`,
        index,
      );
    }
  }
  return null;
}

function validateFixturePlayers(
  response: unknown[],
): ProviderContractIssue | null {
  for (let teamIndex = 0; teamIndex < response.length; teamIndex += 1) {
    const item = asRecord(response[teamIndex]);
    const team = item ? asRecord(item.team) : null;
    if (
      !item ||
      !team ||
      !isPositiveInteger(team.id) ||
      !isNonEmptyString(team.name) ||
      !Array.isArray(item.players)
    ) {
      return issue(
        'fixture_players.team',
        `Payload provider non valido [fixture_players.team] all'indice ${teamIndex}.`,
        teamIndex,
      );
    }

    for (let playerIndex = 0; playerIndex < item.players.length; playerIndex += 1) {
      const itemIndex = teamIndex * 10000 + playerIndex;
      const playerItem = asRecord(item.players[playerIndex]);
      const player = playerItem ? asRecord(playerItem.player) : null;
      if (
        !playerItem ||
        !player ||
        !isPositiveInteger(player.id) ||
        !isNonEmptyString(player.name) ||
        !isNullableString(player.photo) ||
        !Array.isArray(playerItem.statistics)
      ) {
        return issue(
          'fixture_players.player',
          `Payload provider non valido [fixture_players.player] alla squadra ${teamIndex}, calciatore ${playerIndex}.`,
          itemIndex,
        );
      }

      if (playerItem.statistics.length === 0) {
        continue;
      }

      const stats = asRecord(playerItem.statistics[0]);
      const games = stats ? asRecord(stats.games) : null;
      const goals = stats ? asRecord(stats.goals) : null;
      const cards = stats ? asRecord(stats.cards) : null;
      const penalty = stats ? asRecord(stats.penalty) : null;
      if (!stats || !games || !goals || !cards || !penalty) {
        return issue(
          'fixture_players.statistics',
          `Payload provider non valido [fixture_players.statistics] alla squadra ${teamIndex}, calciatore ${playerIndex}.`,
          itemIndex,
        );
      }
      if (
        !isNullableFiniteNumber(games.minutes) ||
        !isNullableString(games.position) ||
        !isNullableNumericString(games.rating) ||
        typeof games.substitute !== 'boolean' ||
        !isNullableFiniteNumber(goals.total) ||
        !isNullableFiniteNumber(goals.conceded) ||
        !isNullableFiniteNumber(goals.assists) ||
        !isNullableFiniteNumber(goals.saves) ||
        !isNullableFiniteNumber(cards.yellow) ||
        !isNullableFiniteNumber(cards.red) ||
        !isNullableFiniteNumber(penalty.scored) ||
        !isNullableFiniteNumber(penalty.missed) ||
        !isNullableFiniteNumber(penalty.saved)
      ) {
        return issue(
          'fixture_players.statistics_values',
          `Payload provider non valido [fixture_players.statistics_values] alla squadra ${teamIndex}, calciatore ${playerIndex}.`,
          itemIndex,
        );
      }
    }
  }
  return null;
}

function validateProviderDelivery(
  path: string,
  parameters: Record<string, string | number>,
  envelope: ApiFootballEnvelope<unknown>,
): ProviderDeliveryMetadata {
  if (envelope.results !== envelope.response.length) {
    throw new ProviderDeliveryError(
      'delivery.results_mismatch',
      `il provider dichiara ${envelope.results} risultati ma ne ha consegnati ${envelope.response.length}.`,
    );
  }

  const requestedPage = parameters.page === undefined
    ? null
    : Number(parameters.page);
  if (
    requestedPage !== null &&
    (!Number.isInteger(requestedPage) || requestedPage < 1)
  ) {
    throw new ProviderDeliveryError(
      'delivery.requested_page',
      'la pagina richiesta non è un intero positivo.',
    );
  }
  if (requestedPage !== null && envelope.paging.current !== requestedPage) {
    throw new ProviderDeliveryError(
      'delivery.page_mismatch',
      `richiesta pagina ${requestedPage}, ricevuta pagina ${envelope.paging.current}.`,
    );
  }
  if (
    envelope.paging.total > 0 &&
    envelope.paging.current > envelope.paging.total
  ) {
    throw new ProviderDeliveryError(
      'delivery.page_range',
      `pagina corrente ${envelope.paging.current} oltre il totale ${envelope.paging.total}.`,
    );
  }
  if (requestedPage === null && envelope.paging.total > 1) {
    throw new ProviderDeliveryError(
      'delivery.unexpected_pagination',
      `l'endpoint richiede ${envelope.paging.total} pagine ma il flusso è certificato come unitario.`,
    );
  }

  const entityKeys = extractProviderEntityKeys(path, envelope.response);
  if (new Set(entityKeys).size !== entityKeys.length) {
    throw new ProviderDeliveryError(
      'delivery.duplicate_entity',
      'la stessa entità è presente più volte nella risposta.',
    );
  }

  return {
    path,
    current: envelope.paging.current,
    total: envelope.paging.total,
    results: envelope.results,
    entityKeys,
  };
}

function extractProviderEntityKeys(
  path: string,
  response: unknown[],
): string[] {
  if (path === '/players') {
    return response.map((item) => {
      const player = asRecord(asRecord(item)?.player);
      return `player:${String(player?.id ?? '')}`;
    });
  }
  if (path === '/fixtures') {
    return response.map((item) => {
      const fixture = asRecord(asRecord(item)?.fixture);
      return `fixture:${String(fixture?.id ?? '')}`;
    });
  }
  if (path === '/fixtures/players') {
    return response.flatMap((teamItem) => {
      const team = asRecord(teamItem);
      if (!team || !Array.isArray(team.players)) {
        return [];
      }
      return team.players.flatMap((playerItem) => {
        const rawPlayerItem = asRecord(playerItem);
        const player = asRecord(rawPlayerItem?.player);
        const statistics = rawPlayerItem?.statistics;
        if (!Array.isArray(statistics) || statistics.length === 0) {
          return [];
        }
        return [`fixture-player:${String(player?.id ?? '')}`];
      });
    });
  }
  throw new ProviderDeliveryError(
    'delivery.endpoint_unsupported',
    `endpoint ${path} non riconosciuto dal certificato di consegna.`,
  );
}

function issue(
  code: string,
  summary: string,
  itemIndex: number | null = null,
): ProviderContractIssue {
  return { code, summary, itemIndex };
}

function asRecord(value: unknown): Record<string, unknown> | null {
  return value !== null && typeof value === 'object' && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : null;
}

function isNonEmptyString(value: unknown): value is string {
  return typeof value === 'string' && value.trim().length > 0;
}

function isNullableString(value: unknown): value is string | null | undefined {
  return value === null || value === undefined || typeof value === 'string';
}

function isPositiveInteger(value: unknown): value is number {
  return Number.isInteger(value) && Number(value) > 0;
}

function isNonNegativeInteger(value: unknown): value is number {
  return Number.isInteger(value) && Number(value) >= 0;
}

function isNullableFiniteNumber(
  value: unknown,
): value is number | null | undefined {
  return (
    value === null ||
    value === undefined ||
    (typeof value === 'number' && Number.isFinite(value))
  );
}

function isNullableNumericString(
  value: unknown,
): value is string | null | undefined {
  if (value === null || value === undefined) {
    return true;
  }
  if (typeof value !== 'string' || value.trim().length === 0) {
    return false;
  }
  return Number.isFinite(Number(value));
}

function isValidDateString(value: unknown): value is string {
  return typeof value === 'string' && Number.isFinite(Date.parse(value));
}

function serializePayload(value: unknown) {
  if (typeof value === 'string') {
    return value;
  }
  try {
    return JSON.stringify(value) ?? 'null';
  } catch {
    return String(value);
  }
}

function normalizeContractToken(value: string, fallback: string) {
  const normalized = value
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9:/._-]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 120);
  return normalized || fallback;
}

function sanitizeSummary(value: string) {
  return value.replace(/[\r\n]+/g, ' ').trim().slice(0, 500);
}


const PROVIDER = 'api-football';
const COMPETITION_CODE = 'IT-SA';

type SyncRequest =
  | {
      action: 'sync-season-players';
      season: number;
    }
  | {
      action: 'sync-fixtures';
      season: number;
      date: string;
    }
  | {
      action: 'sync-fixture-players';
      fixtureId: number;
    };

type ProviderSyncRun = {
  id: string;
  status: 'running' | 'completed' | 'failed';
  revision: number;
  attempt: number;
  recordsProcessed: number;
  requestKey: string;
  progressPhase: string;
  progressCurrent: number;
  progressTotal: number | null;
  heartbeatAt: string | null;
  leaseToken: string | null;
  leaseEpoch: number | null;
  leaseExpiresAt: string | null;
  leaseStatus: 'active' | 'released' | 'revoked' | 'expired' | null;
  reused: boolean;
  publicationSuperseded: boolean;
  watermarkGeneration: number | null;
  watermarkLatestRunId: string | null;
  catalogReconciliation: boolean;
  catalogSuperseded: boolean;
  catalogStatus: 'collecting' | 'applied' | 'superseded' | null;
  catalogSeason: number | null;
  catalogCurrentSeason: number | null;
  catalogGeneration: number | null;
  catalogPlayerCount: number;
  catalogDeactivatedPlayerCount: number;
  catalogRemovedRoleCount: number;
  catalogRosteredRetiredCount: number;
  fixtureLifecycleReconciliation: boolean;
  fixtureLifecycleStatus: 'collecting' | 'applied' | null;
  fixtureLifecycleFixtureCount: number;
  fixtureLifecycleFinalCount: number;
  fixtureLifecycleCreatedCount: number;
  fixtureLifecycleAdvancedCount: number;
  fixtureLifecycleFinalCorrectionCount: number;
  fixtureLifecycleMaxGeneration: number | null;
  fixtureScoreCoherence: boolean;
  fixtureScoreCoherenceStatus: 'aligned' | 'stale' | 'missing' | null;
  fixtureScoreCoherenceEventCount: number;
  fixtureScoreCoherenceStaleCount: number;
  fixtureScoreCoherenceScoreGeneration: number | null;
  fixtureScoreCoherenceLifecycleGeneration: number | null;
  fixtureScoreCoherenceLifecycleRevision: number | null;
  fixtureScoreCoherenceReasonCode: string | null;
};

type ProviderSyncProgress = {
  phase: 'starting' | 'season-players' | 'fixtures' | 'fixture-players' | 'finalizing';
  current: number;
  total: number | null;
  recordsProcessed: number;
};

type ProviderProgressCallback = (
  progress: ProviderSyncProgress,
) => Promise<void>;

type ProviderLeaseAssertion = () => Promise<void>;

type ProviderFencedWriteOperation =
  | 'upsert-athletes'
  | 'upsert-athlete-roles'
  | 'upsert-matchday'
  | 'upsert-provider-fixtures'
  | 'upsert-player-scores';

type ProviderFencedWriter = (
  operation: ProviderFencedWriteOperation,
  payload: unknown,
) => Promise<Record<string, unknown> | null>;

type ProviderDeliveryUnit = {
  unitNo: number;
  expectedUnitCount: number;
  declaredCurrent: number;
  declaredTotal: number;
  declaredResults: number;
  observedResults: number;
  recordsProcessed: number;
  entityKeys: string[];
};

type ProviderDeliveryRecorder = (
  unit: ProviderDeliveryUnit,
) => Promise<void>;

type ProviderRecoveryRequest = {
  recoveryRequestId: string;
};

type ProviderRecoveryQueueRequest = {
  processRecoveryQueue: true;
};

type ProviderRecoveryClaim = {
  requestId: string;
  status: 'pending' | 'running' | 'completed' | 'failed' | 'cancelled';
  revision: number;
  requestedFor: SyncRequest;
  execute: boolean;
  reused: boolean;
  run: ProviderSyncRun | null;
};

type ApiSeasonPlayer = {
  player: {
    id: number;
    firstname: string | null;
    lastname: string | null;
    name: string;
    photo: string | null;
  };
  statistics: Array<{
    team: { id: number; name: string };
    games: { position: string | null };
  }>;
};

type ApiFixture = {
  fixture: {
    id: number;
    date: string;
    status: { short: string };
  };
  league: {
    round: string;
  };
  teams: {
    home: { id: number; name: string };
    away: { id: number; name: string };
  };
  goals: {
    home: number | null;
    away: number | null;
  };
};

type ApiFixtureTeam = {
  team: { id: number; name: string };
  players: ApiFixturePlayer[];
};

type ApiFixturePlayer = {
  player: {
    id: number;
    name: string;
    photo: string | null;
  };
  statistics: Array<{
    games: {
      minutes: number | null;
      position: string | null;
      rating: string | null;
      substitute: boolean;
    };
    goals: {
      total: number | null;
      conceded: number | null;
      assists: number | null;
      saves: number | null;
    };
    cards: {
      yellow: number | null;
      red: number | null;
    };
    penalty: {
      scored: number | null;
      missed: number | null;
      saved: number | null;
    };
    [key: string]: unknown;
  }>;
};

const jsonHeaders = {
  'Content-Type': 'application/json',
};

export default {
  fetch: withSupabase(
    { auth: 'secret:automations' },
    async (request, context) => {
      if (request.method !== 'POST') {
        return json({ error: 'Metodo non consentito.' }, 405);
      }

      const apiKey = Deno.env.get('API_FOOTBALL_KEY');
      if (!apiKey) {
        return json({ error: 'Chiave API-Football non configurata.' }, 500);
      }

      let body: unknown;
      try {
        body = await request.json();
      } catch {
        return json({ error: 'Corpo JSON non valido.' }, 400);
      }

      const supabase = context.supabaseAdmin;
      const api = new ApiFootballClient(apiKey);
      let payload: SyncRequest;
      let run: ProviderSyncRun;
      let recoveryRequestId: string | null = null;
      const workerToken = crypto.randomUUID();

      if (
        isProviderRecoveryRequest(body) ||
        isProviderRecoveryQueueRequest(body)
      ) {
        const claim = isProviderRecoveryRequest(body)
          ? await claimRecoveryRequest(
              supabase,
              body.recoveryRequestId,
              workerToken,
            )
          : await claimNextRecoveryRequest(supabase, workerToken);

        if (!claim) {
          return json({ ok: true, queueEmpty: true, reused: true });
        }

        payload = claim.requestedFor;
        recoveryRequestId = claim.requestId;

        if (claim.status === 'completed') {
          return json({
            ok: true,
            action: payload.action,
            recordsProcessed: claim.run?.recordsProcessed ?? 0,
            runId: claim.run?.id ?? null,
            recoveryRequestId,
            reused: true,
          });
        }

        if (claim.status === 'failed' || claim.status === 'cancelled') {
          return json(
            {
              error: 'La richiesta di recupero non è più eseguibile.',
              recoveryRequestId,
            },
            409,
          );
        }

        if (!claim.run) {
          return json(
            {
              error: 'Il recupero non ha prodotto un run provider valido.',
              recoveryRequestId,
            },
            500,
          );
        }

        run = claim.run;
        if (!claim.execute) {
          return json(
            {
              ok: true,
              action: payload.action,
              recordsProcessed: run.recordsProcessed,
              runId: run.id,
              recoveryRequestId,
              reused: true,
              status: run.status,
            },
            run.status === 'completed' ? 200 : 202,
          );
        }
      } else {
        payload = body as SyncRequest;
        run = await startRun(supabase, payload, workerToken);

        if (run.reused && run.status === 'completed') {
          return json({
            ok: true,
            action: payload.action,
            recordsProcessed: run.recordsProcessed,
            runId: run.id,
            reused: true,
          });
        }

        if (run.reused && run.status === 'running') {
          return json(
            {
              ok: true,
              action: payload.action,
              recordsProcessed: run.recordsProcessed,
              runId: run.id,
              reused: true,
              status: 'running',
            },
            202,
          );
        }
      }

      try {
        run = await heartbeatRun(supabase, run, {
          phase: 'starting',
          current: 0,
          total: null,
          recordsProcessed: run.recordsProcessed,
        });

        const recordsProcessed = await executeSync(
          supabase,
          api,
          payload,
          Number(Deno.env.get('API_FOOTBALL_LEAGUE_ID') ?? 135),
          async (progress) => {
            run = await heartbeatRun(supabase, run, progress);
          },
          async () => {
            await assertWorkerLease(supabase, run);
          },
          async (operation, writePayload) =>
            applyProviderSyncWrite(
              supabase,
              run,
              operation,
              writePayload,
            ),
          async (unit) =>
            recordProviderDeliveryUnit(supabase, run, unit),
        );

        run = await heartbeatRun(supabase, run, {
          phase: 'finalizing',
          current: recordsProcessed,
          total: null,
          recordsProcessed,
        });

        const completed = await finishRun(
          supabase,
          run,
          'completed',
          recordsProcessed,
        );

        return json({
          ok: true,
          action: payload.action,
          recordsProcessed: completed.recordsProcessed,
          runId: completed.id,
          reused: completed.reused,
          superseded: completed.publicationSuperseded,
          watermarkGeneration: completed.watermarkGeneration,
          watermarkLatestRunId: completed.watermarkLatestRunId,
          catalogReconciliation: completed.catalogReconciliation,
          catalogSuperseded: completed.catalogSuperseded,
          catalogStatus: completed.catalogStatus,
          catalogSeason: completed.catalogSeason,
          catalogCurrentSeason: completed.catalogCurrentSeason,
          catalogGeneration: completed.catalogGeneration,
          catalogPlayerCount: completed.catalogPlayerCount,
          catalogDeactivatedPlayerCount: completed.catalogDeactivatedPlayerCount,
          catalogRemovedRoleCount: completed.catalogRemovedRoleCount,
          catalogRosteredRetiredCount: completed.catalogRosteredRetiredCount,
          fixtureLifecycleReconciliation:
            completed.fixtureLifecycleReconciliation,
          fixtureLifecycleStatus: completed.fixtureLifecycleStatus,
          fixtureLifecycleFixtureCount:
            completed.fixtureLifecycleFixtureCount,
          fixtureLifecycleFinalCount: completed.fixtureLifecycleFinalCount,
          fixtureLifecycleCreatedCount:
            completed.fixtureLifecycleCreatedCount,
          fixtureLifecycleAdvancedCount:
            completed.fixtureLifecycleAdvancedCount,
          fixtureLifecycleFinalCorrectionCount:
            completed.fixtureLifecycleFinalCorrectionCount,
          fixtureLifecycleMaxGeneration:
            completed.fixtureLifecycleMaxGeneration,
          fixtureScoreCoherence: completed.fixtureScoreCoherence,
          fixtureScoreCoherenceStatus:
            completed.fixtureScoreCoherenceStatus,
          fixtureScoreCoherenceEventCount:
            completed.fixtureScoreCoherenceEventCount,
          fixtureScoreCoherenceStaleCount:
            completed.fixtureScoreCoherenceStaleCount,
          fixtureScoreCoherenceScoreGeneration:
            completed.fixtureScoreCoherenceScoreGeneration,
          fixtureScoreCoherenceLifecycleGeneration:
            completed.fixtureScoreCoherenceLifecycleGeneration,
          fixtureScoreCoherenceLifecycleRevision:
            completed.fixtureScoreCoherenceLifecycleRevision,
          fixtureScoreCoherenceReasonCode:
            completed.fixtureScoreCoherenceReasonCode,
          recoveryRequestId,
        });
      } catch (error) {
        const message =
          error instanceof Error ? error.message : 'Errore di sincronizzazione.';

        if (error instanceof ProviderContractError) {
          try {
            await recordProviderContractViolation(supabase, run, error);
          } catch (recordError) {
            console.error(
              'Impossibile certificare la violazione del contratto provider.',
              recordError,
            );
          }
        }

        try {
          await finishRun(
            supabase,
            run,
            'failed',
            run.recordsProcessed,
            message,
          );
        } catch (finishError) {
          console.error('Impossibile certificare il fallimento provider.', finishError);
        }
        return json(
          { error: message, runId: run.id, recoveryRequestId },
          error instanceof ProviderContractError ? 422 : 500,
        );
      }
    },
  ),
};

async function executeSync(
  supabase: SupabaseClient,
  api: ApiFootballClient,
  payload: SyncRequest,
  leagueId: number,
  onProgress: ProviderProgressCallback,
  assertLease: ProviderLeaseAssertion,
  fencedWrite: ProviderFencedWriter,
  recordDelivery: ProviderDeliveryRecorder,
) {
  switch (payload.action) {
    case 'sync-season-players':
      return syncSeasonPlayers(
        supabase,
        api,
        leagueId,
        payload.season,
        onProgress,
        assertLease,
        fencedWrite,
        recordDelivery,
      );
    case 'sync-fixtures':
      return syncFixtures(
        supabase,
        api,
        leagueId,
        payload.season,
        payload.date,
        onProgress,
        assertLease,
        fencedWrite,
        recordDelivery,
      );
    case 'sync-fixture-players':
      return syncFixturePlayers(
        supabase,
        api,
        payload.fixtureId,
        onProgress,
        assertLease,
        fencedWrite,
        recordDelivery,
      );
    default:
      throw new Error('Azione di sincronizzazione non riconosciuta.');
  }
}

async function syncSeasonPlayers(
  supabase: SupabaseClient,
  api: ApiFootballClient,
  leagueId: number,
  season: number,
  onProgress: ProviderProgressCallback,
  assertLease: ProviderLeaseAssertion,
  fencedWrite: ProviderFencedWriter,
  recordDelivery: ProviderDeliveryRecorder,
) {
  let page = 1;
  let totalPages = 1;
  let certifiedTotalPages: number | null = null;
  let processed = 0;
  const seenEntities = new Set<string>();

  do {
    const envelope = await api.get<ApiSeasonPlayer>('/players', {
      league: leagueId,
      season,
      page,
    });
    totalPages = Math.max(envelope.delivery.total, 1);
    if (certifiedTotalPages === null) {
      certifiedTotalPages = totalPages;
    } else if (certifiedTotalPages !== totalPages) {
      throw new ProviderDeliveryError(
        'delivery.total_changed',
        `il totale pagine è cambiato da ${certifiedTotalPages} a ${totalPages}.`,
      );
    }
    for (const entityKey of envelope.delivery.entityKeys) {
      if (seenEntities.has(entityKey)) {
        throw new ProviderDeliveryError(
          'delivery.duplicate_entity',
          `l'entità ${entityKey} è stata ricevuta in più pagine.`,
        );
      }
      seenEntities.add(entityKey);
    }
    const unitProcessed = await upsertSeasonPlayers(
      supabase,
      envelope.response,
      assertLease,
      fencedWrite,
    );
    if (unitProcessed !== envelope.delivery.entityKeys.length) {
      throw new ProviderDeliveryError(
        'delivery.records_mismatch',
        `la pagina ${page} contiene ${envelope.delivery.entityKeys.length} entità ma ne sono state elaborate ${unitProcessed}.`,
      );
    }
    await recordDelivery({
      unitNo: page,
      expectedUnitCount: totalPages,
      declaredCurrent: envelope.delivery.current,
      declaredTotal: envelope.delivery.total,
      declaredResults: envelope.delivery.results,
      observedResults: envelope.response.length,
      recordsProcessed: unitProcessed,
      entityKeys: envelope.delivery.entityKeys,
    });
    processed += unitProcessed;
    await onProgress({
      phase: 'season-players',
      current: page,
      total: totalPages,
      recordsProcessed: processed,
    });
    page += 1;
  } while (page <= totalPages);

  return processed;
}

async function upsertSeasonPlayers(
  supabase: SupabaseClient,
  players: ApiSeasonPlayer[],
  assertLease: ProviderLeaseAssertion,
  fencedWrite: ProviderFencedWriter,
) {
  if (players.length === 0) {
    return 0;
  }

  const athleteRows = players.map(({ player, statistics }) => {
    const current = statistics[0];
    return {
      provider: PROVIDER,
      provider_player_id: String(player.id),
      first_name: player.firstname,
      last_name: player.lastname || player.name,
      club_name: current?.team.name ?? 'Svincolato',
      provider_team_id: current?.team.id
        ? String(current.team.id)
        : null,
      photo_url: player.photo,
      position_code: current?.games.position ?? null,
      active: true,
      payload: { player, statistics },
      updated_at: new Date().toISOString(),
    };
  });

  const fencedResult = await fencedWrite('upsert-athletes', athleteRows);
  let athletes: Array<{
    id: string;
    provider_player_id: string;
    position_code: string | null;
  }>;

  if (fencedResult) {
    athletes = normalizeFencedAthletes(fencedResult);
  } else {
    await assertLease();
    const { data, error } = await supabase
      .from('athletes')
      .upsert(athleteRows, { onConflict: 'provider,provider_player_id' })
      .select('id, provider_player_id, position_code');

    if (error) {
      throw error;
    }
    athletes = data ?? [];
  }

  await upsertRoles(supabase, athletes, assertLease, fencedWrite);
  return athletes.length;
}

async function syncFixtures(
  supabase: SupabaseClient,
  api: ApiFootballClient,
  leagueId: number,
  season: number,
  date: string,
  onProgress: ProviderProgressCallback,
  assertLease: ProviderLeaseAssertion,
  fencedWrite: ProviderFencedWriter,
  recordDelivery: ProviderDeliveryRecorder,
) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) {
    throw new Error('La data deve essere nel formato YYYY-MM-DD.');
  }

  const envelope = await api.get<ApiFixture>('/fixtures', {
    league: leagueId,
    season,
    date,
  });
  const fixtures = envelope.response;

  const grouped = new Map<number, ApiFixture[]>();
  for (const fixture of fixtures) {
    const matchdayNumber = parseMatchday(fixture.league.round);
    const group = grouped.get(matchdayNumber) ?? [];
    group.push(fixture);
    grouped.set(matchdayNumber, group);
  }

  let completedGroups = 0;
  let processed = 0;

  for (const [number, matchdayFixtures] of grouped.entries()) {
    const kickoffDates = matchdayFixtures
      .map((item) => new Date(item.fixture.date))
      .sort((left, right) => left.getTime() - right.getTime());
    const startsAt = kickoffDates[0];
    const endsAt = new Date(
      kickoffDates[kickoffDates.length - 1].getTime() + 3 * 60 * 60 * 1000,
    );

    const matchdayPayload = {
      competition_code: COMPETITION_CODE,
      season: String(season),
      number,
      starts_at: startsAt.toISOString(),
      locks_at: startsAt.toISOString(),
      ends_at: endsAt.toISOString(),
    };
    const fencedMatchday = await fencedWrite(
      'upsert-matchday',
      matchdayPayload,
    );
    let matchday: { id: string };

    if (fencedMatchday) {
      matchday = normalizeFencedMatchday(fencedMatchday);
    } else {
      await assertLease();
      const { data, error: matchdayError } = await supabase
        .from('matchdays')
        .upsert(
          matchdayPayload,
          { onConflict: 'competition_code,season,number' },
        )
        .select('id')
        .single();

      if (matchdayError) {
        throw matchdayError;
      }
      matchday = data;
    }

    const rows = matchdayFixtures.map((item) => ({
      provider: PROVIDER,
      provider_fixture_id: String(item.fixture.id),
      competition_code: COMPETITION_CODE,
      season: String(season),
      matchday_id: matchday.id,
      kickoff_at: item.fixture.date,
      status: item.fixture.status.short,
      home_team_provider_id: String(item.teams.home.id),
      home_team_name: item.teams.home.name,
      away_team_provider_id: String(item.teams.away.id),
      away_team_name: item.teams.away.name,
      home_goals: item.goals.home,
      away_goals: item.goals.away,
      payload: item,
      updated_at: new Date().toISOString(),
    }));

    const fencedFixtures = await fencedWrite(
      'upsert-provider-fixtures',
      rows,
    );
    if (!fencedFixtures) {
      await assertLease();
      const { error: fixturesError } = await supabase
        .from('provider_fixtures')
        .upsert(rows, { onConflict: 'provider,provider_fixture_id' });

      if (fixturesError) {
        throw fixturesError;
      }
    }

    completedGroups += 1;
    processed += matchdayFixtures.length;
    await onProgress({
      phase: 'fixtures',
      current: completedGroups,
      total: grouped.size,
      recordsProcessed: processed,
    });
  }

  if (grouped.size === 0) {
    await onProgress({
      phase: 'fixtures',
      current: 0,
      total: 0,
      recordsProcessed: 0,
    });
  }

  await recordDelivery({
    unitNo: 1,
    expectedUnitCount: Math.max(envelope.delivery.total, 1),
    declaredCurrent: envelope.delivery.current,
    declaredTotal: envelope.delivery.total,
    declaredResults: envelope.delivery.results,
    observedResults: fixtures.length,
    recordsProcessed: processed,
    entityKeys: envelope.delivery.entityKeys,
  });

  return fixtures.length;
}

async function syncFixturePlayers(
  supabase: SupabaseClient,
  api: ApiFootballClient,
  fixtureId: number,
  onProgress: ProviderProgressCallback,
  assertLease: ProviderLeaseAssertion,
  fencedWrite: ProviderFencedWriter,
  recordDelivery: ProviderDeliveryRecorder,
) {
  const { data: providerFixture, error: fixtureError } = await supabase
    .from('provider_fixtures')
    .select('matchday_id, status')
    .eq('provider', PROVIDER)
    .eq('provider_fixture_id', String(fixtureId))
    .single();

  if (fixtureError || !providerFixture?.matchday_id) {
    throw new Error(
      'Prima sincronizza il calendario: manca la giornata della partita.',
    );
  }

  const envelope = await api.get<ApiFixtureTeam>('/fixtures/players', {
    fixture: fixtureId,
  });

  let processed = 0;
  let completedTeams = 0;
  for (const team of envelope.response) {
    processed += await upsertFixtureTeamScores(
      supabase,
      providerFixture.matchday_id,
      fixtureId,
      providerFixture.status,
      team,
      assertLease,
      fencedWrite,
    );
    completedTeams += 1;
    await onProgress({
      phase: 'fixture-players',
      current: completedTeams,
      total: envelope.response.length,
      recordsProcessed: processed,
    });
  }

  if (envelope.response.length === 0) {
    await onProgress({
      phase: 'fixture-players',
      current: 0,
      total: 0,
      recordsProcessed: 0,
    });
  }

  if (processed !== envelope.delivery.entityKeys.length) {
    throw new ProviderDeliveryError(
      'delivery.records_mismatch',
      `la partita contiene ${envelope.delivery.entityKeys.length} voti utilizzabili ma ne sono stati elaborati ${processed}.`,
    );
  }
  await recordDelivery({
    unitNo: 1,
    expectedUnitCount: Math.max(envelope.delivery.total, 1),
    declaredCurrent: envelope.delivery.current,
    declaredTotal: envelope.delivery.total,
    declaredResults: envelope.delivery.results,
    observedResults: envelope.response.length,
    recordsProcessed: processed,
    entityKeys: envelope.delivery.entityKeys,
  });

  return processed;
}

async function upsertFixtureTeamScores(
  supabase: SupabaseClient,
  matchdayId: string,
  fixtureId: number,
  fixtureStatus: string,
  team: ApiFixtureTeam,
  assertLease: ProviderLeaseAssertion,
  fencedWrite: ProviderFencedWriter,
) {
  if (team.players.length === 0) {
    return 0;
  }

  const athleteRows = team.players.map(({ player, statistics }) => ({
    provider: PROVIDER,
    provider_player_id: String(player.id),
    last_name: player.name,
    club_name: team.team.name,
    provider_team_id: String(team.team.id),
    photo_url: player.photo,
    position_code: statistics[0]?.games.position ?? null,
    active: true,
    payload: { player, statistics },
    updated_at: new Date().toISOString(),
  }));

  const fencedAthletes = await fencedWrite('upsert-athletes', athleteRows);
  let athletes: Array<{
    id: string;
    provider_player_id: string;
    position_code: string | null;
  }>;

  if (fencedAthletes) {
    athletes = normalizeFencedAthletes(fencedAthletes);
  } else {
    await assertLease();
    const { data, error: athleteError } = await supabase
      .from('athletes')
      .upsert(athleteRows, { onConflict: 'provider,provider_player_id' })
      .select('id, provider_player_id, position_code');

    if (athleteError) {
      throw athleteError;
    }
    athletes = data ?? [];
  }

  await upsertRoles(supabase, athletes, assertLease, fencedWrite);

  const athleteIds = new Map(
    athletes.map((athlete) => [
      athlete.provider_player_id,
      athlete.id,
    ]),
  );

  const scoreRows = team.players.flatMap(({ player, statistics }) => {
    const stats = statistics[0];
    const athleteId = athleteIds.get(String(player.id));
    if (!stats || !athleteId) {
      return [];
    }

    const calculated = calculateStandardFantasyScore(stats);
    return [
      {
        athlete_id: athleteId,
        matchday_id: matchdayId,
        provider_fixture_id: String(fixtureId),
        provider_rating: calculated.rating,
        fantasy_score: calculated.fantasyScore,
        bonuses: calculated.bonuses,
        maluses: calculated.maluses,
        raw_statistics: stats,
        provider_payload: { player, statistics },
        is_final: ['FT', 'AET', 'PEN'].includes(fixtureStatus),
        updated_at: new Date().toISOString(),
      },
    ];
  });

  const fencedScores = await fencedWrite('upsert-player-scores', scoreRows);
  if (!fencedScores) {
    await assertLease();
    const { error: scoresError } = await supabase
      .from('player_match_scores')
      .upsert(scoreRows, { onConflict: 'athlete_id,matchday_id' });

    if (scoresError) {
      throw scoresError;
    }
  }

  return scoreRows.length;
}

function calculateStandardFantasyScore(
  stats: ApiFixturePlayer['statistics'][number],
) {
  const rating = toNumber(stats.games.rating);
  const goals = stats.goals.total ?? 0;
  const assists = stats.goals.assists ?? 0;
  const penaltiesSaved = stats.penalty.saved ?? 0;
  const yellowCards = stats.cards.yellow ?? 0;
  const redCards = stats.cards.red ?? 0;
  const penaltiesMissed = stats.penalty.missed ?? 0;
  const goalsConceded =
    stats.games.position === 'G' ? (stats.goals.conceded ?? 0) : 0;

  const bonuses = {
    goals: goals * 3,
    assists,
    penalties_saved: penaltiesSaved * 3,
  };
  const maluses = {
    yellow_cards: yellowCards * 0.5,
    red_cards: redCards,
    penalties_missed: penaltiesMissed * 3,
    goals_conceded: goalsConceded,
  };

  const bonusTotal = Object.values(bonuses).reduce(
    (total, value) => total + value,
    0,
  );
  const malusTotal = Object.values(maluses).reduce(
    (total, value) => total + value,
    0,
  );

  return {
    rating,
    fantasyScore:
      rating === null ? null : roundTwo(rating + bonusTotal - malusTotal),
    bonuses,
    maluses,
  };
}

async function upsertRoles(
  supabase: SupabaseClient,
  athletes: Array<{
    id: string;
    position_code: string | null;
  }>,
  assertLease: ProviderLeaseAssertion,
  fencedWrite: ProviderFencedWriter,
) {
  const roles = athletes.flatMap((athlete) => {
    const mapped = mapRoles(athlete.position_code);
    return [
      {
        athlete_id: athlete.id,
        mode: 'classic',
        role_code: mapped.classic,
      },
      {
        athlete_id: athlete.id,
        mode: 'mantra',
        role_code: mapped.mantra,
      },
    ];
  });

  if (roles.length === 0) {
    return;
  }

  const fencedRoles = await fencedWrite('upsert-athlete-roles', roles);
  if (!fencedRoles) {
    await assertLease();
    const { error } = await supabase
      .from('athlete_roles')
      .upsert(roles, { onConflict: 'athlete_id,mode,role_code' });

    if (error) {
      throw error;
    }
  }
}

function mapRoles(position: string | null) {
  switch (position) {
    case 'G':
      return { classic: 'P', mantra: 'Por' };
    case 'D':
      return { classic: 'D', mantra: 'Dc' };
    case 'M':
      return { classic: 'C', mantra: 'M' };
    case 'F':
      return { classic: 'A', mantra: 'A' };
    default:
      return { classic: 'C', mantra: 'M' };
  }
}

function parseMatchday(round: string) {
  const match = round.match(/(\d+)(?!.*\d)/);
  if (!match) {
    throw new Error(`Impossibile leggere la giornata da "${round}".`);
  }
  return Number(match[1]);
}

function toNumber(value: string | null) {
  if (value === null) {
    return null;
  }
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : null;
}

function roundTwo(value: number) {
  return Math.round(value * 100) / 100;
}

function isProviderRecoveryQueueRequest(
  value: unknown,
): value is ProviderRecoveryQueueRequest {
  if (!value || typeof value !== 'object') {
    return false;
  }
  const raw = value as Record<string, unknown>;
  return raw.processRecoveryQueue === true;
}

function isProviderRecoveryRequest(
  value: unknown,
): value is ProviderRecoveryRequest {
  if (!value || typeof value !== 'object') {
    return false;
  }
  const raw = value as Record<string, unknown>;
  return (
    typeof raw.recoveryRequestId === 'string' &&
    raw.recoveryRequestId.length > 0
  );
}

async function claimNextRecoveryRequest(
  supabase: SupabaseClient,
  workerToken: string,
): Promise<ProviderRecoveryClaim | null> {
  let result = await supabase.rpc(
    'claim_next_provider_recovery_request_v4',
    { p_lease_token: workerToken },
  );

  if (result.error && isMissingRpcError(result.error.message)) {
    result = await supabase.rpc(
      'claim_next_provider_recovery_request_v3',
    );
  }

  if (result.error && isMissingRpcError(result.error.message)) {
    result = await supabase.rpc('claim_next_provider_recovery_request_v2');
  }
  if (result.error && isMissingRpcError(result.error.message)) {
    result = await supabase.rpc('claim_next_provider_recovery_request_v1');
  }
  if (result.error) {
    throw result.error;
  }

  const raw =
    result.data && typeof result.data === 'object'
      ? (result.data as Record<string, unknown>)
      : {};
  if (raw.empty === true) {
    return null;
  }

  return normalizeProviderRecoveryClaim(raw);
}

async function claimRecoveryRequest(
  supabase: SupabaseClient,
  requestId: string,
  workerToken: string,
): Promise<ProviderRecoveryClaim> {
  const fencedParameters = {
    p_request_id: requestId,
    p_expected_revision: null,
    p_lease_token: workerToken,
  };
  const legacyParameters = {
    p_request_id: requestId,
    p_expected_revision: null,
  };
  let result = await supabase.rpc(
    'claim_provider_recovery_request_v3',
    fencedParameters,
  );

  if (result.error && isMissingRpcError(result.error.message)) {
    result = await supabase.rpc(
      'claim_provider_recovery_request_v2',
      legacyParameters,
    );
  }

  if (result.error && isMissingRpcError(result.error.message)) {
    result = await supabase.rpc(
      'claim_provider_recovery_request_v1',
      legacyParameters,
    );
  }
  if (result.error) {
    throw result.error;
  }

  const raw =
    result.data && typeof result.data === 'object'
      ? (result.data as Record<string, unknown>)
      : {};
  return normalizeProviderRecoveryClaim(raw);
}

function isMissingRpcError(message: string) {
  const normalized = message.toLowerCase();
  return (
    normalized.includes('does not exist') ||
    normalized.includes('could not find the function')
  );
}

function normalizeProviderRecoveryClaim(
  raw: Record<string, unknown>,
): ProviderRecoveryClaim {
  const status =
    raw.status === 'running' ||
    raw.status === 'completed' ||
    raw.status === 'failed' ||
    raw.status === 'cancelled'
      ? raw.status
      : 'pending';
  const requestedFor = raw.requestedFor as SyncRequest;
  const run = raw.run ? normalizeProviderSyncRun(raw.run) : null;

  if (!raw.requestId || !requestedFor || typeof requestedFor !== 'object') {
    throw new Error('Risposta della coda recuperi provider non valida.');
  }

  return {
    requestId: String(raw.requestId),
    status,
    revision: Number(raw.revision) || 1,
    requestedFor,
    execute: Boolean(raw.execute),
    reused: Boolean(raw.reused),
    run,
  };
}

async function startRun(
  supabase: SupabaseClient,
  payload: SyncRequest,
  workerToken: string,
): Promise<ProviderSyncRun> {
  let result = await supabase.rpc(
    'start_provider_sync_run_guarded_v2',
    { p_request: payload, p_lease_token: workerToken },
  );

  if (result.error && isMissingRpcError(result.error.message)) {
    result = await supabase.rpc(
      'start_provider_sync_run_guarded_v1',
      { p_request: payload },
    );
  }
  if (result.error) {
    throw result.error;
  }

  return normalizeProviderSyncRun(result.data);
}

async function heartbeatRun(
  supabase: SupabaseClient,
  run: ProviderSyncRun,
  progress: ProviderSyncProgress,
): Promise<ProviderSyncRun> {
  const parameters = {
    p_run_id: run.id,
    p_records_processed: progress.recordsProcessed,
    p_progress_phase: progress.phase,
    p_progress_current: progress.current,
    p_progress_total: progress.total,
    p_expected_revision: run.revision,
  };
  const callHeartbeat = () =>
    run.leaseToken
      ? supabase.rpc(
          'heartbeat_provider_sync_run_guarded_v2',
          { ...parameters, p_lease_token: run.leaseToken },
        )
      : supabase.rpc(
          'heartbeat_provider_sync_run_guarded_v1',
          parameters,
        );

  let result = await callHeartbeat();

  if (result.error && isMissingRpcError(result.error.message) && run.leaseToken) {
    result = await supabase.rpc(
      'heartbeat_provider_sync_run_guarded_v1',
      parameters,
    );
  } else if (result.error) {
    // Ripete la stessa operazione una sola volta: un errore fencing non viene
    // mai aggirato usando la RPC legacy priva del token.
    result = await callHeartbeat();
  }

  if (result.error && isMissingRpcError(result.error.message)) {
    return run;
  }
  if (result.error) {
    throw result.error;
  }

  return normalizeProviderSyncRun(result.data);
}

async function finishRun(
  supabase: SupabaseClient,
  run: ProviderSyncRun,
  status: 'completed' | 'failed',
  recordsProcessed: number,
  errorMessage?: string,
): Promise<ProviderSyncRun> {
  const parameters = {
    p_run_id: run.id,
    p_status: status,
    p_records_processed: recordsProcessed,
    p_error_message: errorMessage ?? null,
    p_expected_revision: run.revision,
  };
  let result = run.leaseToken
    ? await supabase.rpc(
        'finish_provider_sync_run_guarded_v10',
        { ...parameters, p_lease_token: run.leaseToken },
      )
    : await supabase.rpc(
        'finish_provider_sync_run_guarded_v1',
        parameters,
      );

  if (result.error && isMissingRpcError(result.error.message) && run.leaseToken) {
    const guardedVersions = [9, 8, 7, 6, 5, 4, 3, 2] as const;
    for (const version of guardedVersions) {
      result = await supabase.rpc(
        `finish_provider_sync_run_guarded_v${version}`,
        { ...parameters, p_lease_token: run.leaseToken },
      );
      if (!result.error || !isMissingRpcError(result.error.message)) {
        break;
      }
    }
    if (result.error && isMissingRpcError(result.error.message)) {
      result = await supabase.rpc(
        'finish_provider_sync_run_guarded_v1',
        parameters,
      );
    }
  }
  if (result.error) {
    throw result.error;
  }

  return normalizeProviderSyncRun(result.data);
}

async function assertWorkerLease(
  supabase: SupabaseClient,
  run: ProviderSyncRun,
) {
  if (!run.leaseToken) {
    return;
  }

  const { error } = await supabase.rpc(
    'assert_provider_sync_worker_lease_v1',
    {
      p_run_id: run.id,
      p_lease_token: run.leaseToken,
    },
  );

  if (error && !isMissingRpcError(error.message)) {
    throw error;
  }
}

async function applyProviderSyncWrite(
  supabase: SupabaseClient,
  run: ProviderSyncRun,
  operation: ProviderFencedWriteOperation,
  payload: unknown,
): Promise<Record<string, unknown> | null> {
  if (!run.leaseToken) {
    return null;
  }

  const parameters = {
    p_run_id: run.id,
    p_lease_token: run.leaseToken,
    p_operation: operation,
    p_payload: payload,
  };
  let result = await supabase.rpc(
    'stage_provider_sync_write_guarded_v1',
    parameters,
  );

  if (result.error && isMissingRpcError(result.error.message)) {
    result = await supabase.rpc(
      'apply_provider_sync_write_guarded_v2',
      parameters,
    );
  }

  if (result.error && isMissingRpcError(result.error.message)) {
    result = await supabase.rpc(
      'apply_provider_sync_write_guarded_v1',
      parameters,
    );
  }

  if (result.error) {
    if (isProviderPayloadContractMessage(result.error.message)) {
      throw await createProviderContractError(
        `write:${operation}`,
        extractProviderPayloadContractCode(result.error.message),
        result.error.message,
        payload,
      );
    }
    throw result.error;
  }

  const { data } = result;
  if (!data || typeof data !== 'object' || Array.isArray(data)) {
    throw new Error('Risposta della scrittura provider fencing non valida.');
  }
  return data as Record<string, unknown>;
}

async function recordProviderDeliveryUnit(
  supabase: SupabaseClient,
  run: ProviderSyncRun,
  unit: ProviderDeliveryUnit,
) {
  if (!run.leaseToken) {
    throw new ProviderDeliveryError(
      'delivery.lease_missing',
      'la lease worker non è disponibile per certificare la consegna.',
    );
  }

  const fingerprints = await hashProviderEntityKeys(unit.entityKeys);
  const { error } = await supabase.rpc(
    'record_provider_sync_delivery_unit_v1',
    {
      p_run_id: run.id,
      p_lease_token: run.leaseToken,
      p_unit_no: unit.unitNo,
      p_expected_unit_count: unit.expectedUnitCount,
      p_declared_current: unit.declaredCurrent,
      p_declared_total: unit.declaredTotal,
      p_declared_results: unit.declaredResults,
      p_observed_results: unit.observedResults,
      p_records_processed: unit.recordsProcessed,
      p_entity_fingerprints: fingerprints,
    },
  );

  if (error) {
    throw error;
  }
}

async function hashProviderEntityKeys(entityKeys: string[]) {
  const fingerprints: string[] = [];
  for (const entityKey of entityKeys) {
    const encoded = new TextEncoder().encode(entityKey);
    const digest = await crypto.subtle.digest('SHA-256', encoded);
    fingerprints.push(
      Array.from(new Uint8Array(digest))
        .map((byte) => byte.toString(16).padStart(2, '0'))
        .join(''),
    );
  }
  return fingerprints;
}

async function recordProviderContractViolation(
  supabase: SupabaseClient,
  run: ProviderSyncRun,
  violation: ProviderContractError,
) {
  if (!run.leaseToken) {
    return;
  }

  const { error } = await supabase.rpc(
    'record_provider_payload_contract_violation_v1',
    {
      p_run_id: run.id,
      p_lease_token: run.leaseToken,
      p_contract_scope: violation.scope,
      p_contract_version: violation.contractVersion,
      p_violation_code: violation.code,
      p_item_index: violation.itemIndex,
      p_summary: violation.message,
      p_payload_fingerprint: violation.payloadFingerprint,
      p_payload_size: violation.payloadSize,
    },
  );

  if (error && !isMissingRpcError(error.message)) {
    throw error;
  }
}

function isProviderPayloadContractMessage(message: string) {
  return message.toLowerCase().includes('payload provider non valid');
}

function extractProviderPayloadContractCode(message: string) {
  const match = message.toLowerCase().match(/\[([a-z0-9._-]+)\]/);
  return match?.[1] ?? 'write_contract_rejected';
}

function normalizeFencedAthletes(
  value: Record<string, unknown>,
): Array<{
  id: string;
  provider_player_id: string;
  position_code: string | null;
}> {
  if (!Array.isArray(value.records)) {
    throw new Error('Risposta atleti della scrittura fencing non valida.');
  }

  return value.records.map((record) => {
    const raw = record as Record<string, unknown>;
    if (
      typeof raw.id !== 'string' ||
      typeof raw.provider_player_id !== 'string'
    ) {
      throw new Error('Atleta restituito dalla scrittura fencing non valido.');
    }
    return {
      id: raw.id,
      provider_player_id: raw.provider_player_id,
      position_code:
        typeof raw.position_code === 'string' ? raw.position_code : null,
    };
  });
}

function normalizeFencedMatchday(
  value: Record<string, unknown>,
): { id: string } {
  const raw =
    value.record && typeof value.record === 'object' && !Array.isArray(value.record)
      ? (value.record as Record<string, unknown>)
      : null;
  if (!raw || typeof raw.id !== 'string') {
    throw new Error('Giornata restituita dalla scrittura fencing non valida.');
  }
  return { id: raw.id };
}

function normalizeProviderSyncRun(value: unknown): ProviderSyncRun {
  const raw =
    value && typeof value === 'object'
      ? (value as Record<string, unknown>)
      : {};
  const id = typeof raw.runId === 'string' ? raw.runId : '';
  const status =
    raw.status === 'completed' || raw.status === 'failed'
      ? raw.status
      : 'running';
  const revision = Number(raw.revision);
  const attempt = Number(raw.attempt);
  const recordsProcessed = Number(raw.recordsProcessed);

  if (!id || !Number.isFinite(revision) || revision < 1) {
    throw new Error('Risposta del registro provider non valida.');
  }

  return {
    id,
    status,
    revision,
    attempt: Number.isFinite(attempt) && attempt > 0 ? attempt : 1,
    recordsProcessed:
      Number.isFinite(recordsProcessed) && recordsProcessed >= 0
        ? recordsProcessed
        : 0,
    requestKey:
      typeof raw.requestKey === 'string' ? raw.requestKey : '',
    progressPhase:
      typeof raw.progressPhase === 'string' ? raw.progressPhase : 'starting',
    progressCurrent:
      Number.isFinite(Number(raw.progressCurrent)) && Number(raw.progressCurrent) >= 0
        ? Number(raw.progressCurrent)
        : 0,
    progressTotal:
      raw.progressTotal === null || raw.progressTotal === undefined
        ? null
        : Number.isFinite(Number(raw.progressTotal)) && Number(raw.progressTotal) >= 0
          ? Number(raw.progressTotal)
          : null,
    heartbeatAt:
      typeof raw.heartbeatAt === 'string' ? raw.heartbeatAt : null,
    leaseToken:
      typeof raw.leaseToken === 'string' ? raw.leaseToken : null,
    leaseEpoch:
      Number.isFinite(Number(raw.leaseEpoch)) && Number(raw.leaseEpoch) > 0
        ? Number(raw.leaseEpoch)
        : null,
    leaseExpiresAt:
      typeof raw.leaseExpiresAt === 'string' ? raw.leaseExpiresAt : null,
    leaseStatus:
      raw.leaseStatus === 'active' ||
      raw.leaseStatus === 'released' ||
      raw.leaseStatus === 'revoked' ||
      raw.leaseStatus === 'expired'
        ? raw.leaseStatus
        : null,
    reused: Boolean(raw.reused),
    publicationSuperseded: Boolean(raw.publicationSuperseded),
    watermarkGeneration:
      Number.isFinite(Number(raw.watermarkGeneration)) &&
      Number(raw.watermarkGeneration) > 0
        ? Number(raw.watermarkGeneration)
        : null,
    watermarkLatestRunId:
      typeof raw.watermarkLatestRunId === 'string'
        ? raw.watermarkLatestRunId
        : null,
    catalogReconciliation: Boolean(raw.catalogReconciliation),
    catalogSuperseded: Boolean(raw.catalogSuperseded),
    catalogStatus:
      raw.catalogStatus === 'collecting' ||
      raw.catalogStatus === 'applied' ||
      raw.catalogStatus === 'superseded'
        ? raw.catalogStatus
        : null,
    catalogSeason:
      Number.isFinite(Number(raw.catalogSeason)) && Number(raw.catalogSeason) >= 2000
        ? Number(raw.catalogSeason)
        : null,
    catalogCurrentSeason:
      Number.isFinite(Number(raw.catalogCurrentSeason)) &&
      Number(raw.catalogCurrentSeason) >= 2000
        ? Number(raw.catalogCurrentSeason)
        : null,
    catalogGeneration:
      Number.isFinite(Number(raw.catalogGeneration)) && Number(raw.catalogGeneration) > 0
        ? Number(raw.catalogGeneration)
        : null,
    catalogPlayerCount:
      Number.isFinite(Number(raw.catalogPlayerCount)) && Number(raw.catalogPlayerCount) >= 0
        ? Number(raw.catalogPlayerCount)
        : 0,
    catalogDeactivatedPlayerCount:
      Number.isFinite(Number(raw.catalogDeactivatedPlayerCount)) &&
      Number(raw.catalogDeactivatedPlayerCount) >= 0
        ? Number(raw.catalogDeactivatedPlayerCount)
        : 0,
    catalogRemovedRoleCount:
      Number.isFinite(Number(raw.catalogRemovedRoleCount)) &&
      Number(raw.catalogRemovedRoleCount) >= 0
        ? Number(raw.catalogRemovedRoleCount)
        : 0,
    catalogRosteredRetiredCount:
      Number.isFinite(Number(raw.catalogRosteredRetiredCount)) &&
      Number(raw.catalogRosteredRetiredCount) >= 0
        ? Number(raw.catalogRosteredRetiredCount)
        : 0,
    fixtureLifecycleReconciliation: Boolean(
      raw.fixtureLifecycleReconciliation,
    ),
    fixtureLifecycleStatus:
      raw.fixtureLifecycleStatus === 'collecting' ||
      raw.fixtureLifecycleStatus === 'applied'
        ? raw.fixtureLifecycleStatus
        : null,
    fixtureLifecycleFixtureCount:
      Number.isFinite(Number(raw.fixtureLifecycleFixtureCount)) &&
      Number(raw.fixtureLifecycleFixtureCount) >= 0
        ? Number(raw.fixtureLifecycleFixtureCount)
        : 0,
    fixtureLifecycleFinalCount:
      Number.isFinite(Number(raw.fixtureLifecycleFinalCount)) &&
      Number(raw.fixtureLifecycleFinalCount) >= 0
        ? Number(raw.fixtureLifecycleFinalCount)
        : 0,
    fixtureLifecycleCreatedCount:
      Number.isFinite(Number(raw.fixtureLifecycleCreatedCount)) &&
      Number(raw.fixtureLifecycleCreatedCount) >= 0
        ? Number(raw.fixtureLifecycleCreatedCount)
        : 0,
    fixtureLifecycleAdvancedCount:
      Number.isFinite(Number(raw.fixtureLifecycleAdvancedCount)) &&
      Number(raw.fixtureLifecycleAdvancedCount) >= 0
        ? Number(raw.fixtureLifecycleAdvancedCount)
        : 0,
    fixtureLifecycleFinalCorrectionCount:
      Number.isFinite(Number(raw.fixtureLifecycleFinalCorrectionCount)) &&
      Number(raw.fixtureLifecycleFinalCorrectionCount) >= 0
        ? Number(raw.fixtureLifecycleFinalCorrectionCount)
        : 0,
    fixtureLifecycleMaxGeneration:
      Number.isFinite(Number(raw.fixtureLifecycleMaxGeneration)) &&
      Number(raw.fixtureLifecycleMaxGeneration) > 0
        ? Number(raw.fixtureLifecycleMaxGeneration)
        : null,
    fixtureScoreCoherence: Boolean(raw.fixtureScoreCoherence),
    fixtureScoreCoherenceStatus:
      raw.fixtureScoreCoherenceStatus === 'aligned' ||
      raw.fixtureScoreCoherenceStatus === 'stale' ||
      raw.fixtureScoreCoherenceStatus === 'missing'
        ? raw.fixtureScoreCoherenceStatus
        : null,
    fixtureScoreCoherenceEventCount:
      Number.isFinite(Number(raw.fixtureScoreCoherenceEventCount)) &&
      Number(raw.fixtureScoreCoherenceEventCount) >= 0
        ? Number(raw.fixtureScoreCoherenceEventCount)
        : 0,
    fixtureScoreCoherenceStaleCount:
      Number.isFinite(Number(raw.fixtureScoreCoherenceStaleCount)) &&
      Number(raw.fixtureScoreCoherenceStaleCount) >= 0
        ? Number(raw.fixtureScoreCoherenceStaleCount)
        : 0,
    fixtureScoreCoherenceScoreGeneration:
      Number.isFinite(Number(raw.fixtureScoreCoherenceScoreGeneration)) &&
      Number(raw.fixtureScoreCoherenceScoreGeneration) > 0
        ? Number(raw.fixtureScoreCoherenceScoreGeneration)
        : null,
    fixtureScoreCoherenceLifecycleGeneration:
      Number.isFinite(Number(raw.fixtureScoreCoherenceLifecycleGeneration)) &&
      Number(raw.fixtureScoreCoherenceLifecycleGeneration) > 0
        ? Number(raw.fixtureScoreCoherenceLifecycleGeneration)
        : null,
    fixtureScoreCoherenceLifecycleRevision:
      Number.isFinite(Number(raw.fixtureScoreCoherenceLifecycleRevision)) &&
      Number(raw.fixtureScoreCoherenceLifecycleRevision) > 0
        ? Number(raw.fixtureScoreCoherenceLifecycleRevision)
        : null,
    fixtureScoreCoherenceReasonCode:
      typeof raw.fixtureScoreCoherenceReasonCode === 'string'
        ? raw.fixtureScoreCoherenceReasonCode
        : null,
  };
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: jsonHeaders,
  });
}
