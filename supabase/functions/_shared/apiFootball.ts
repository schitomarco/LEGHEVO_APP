const API_BASE_URL = 'https://v3.football.api-sports.io';

export const PROVIDER_PAYLOAD_CONTRACT_VERSION =
  'api-football-v3/leghevo-contract-v1';

export type ProviderDeliveryMetadata = {
  path: string;
  current: number;
  total: number;
  results: number;
  entityKeys: string[];
};

export type ApiFootballEnvelope<T> = {
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

export class ProviderContractError extends Error {
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

export async function createProviderContractError(
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


export class ProviderDeliveryError extends Error {
  constructor(
    readonly code: string,
    summary: string,
  ) {
    super(`Consegna provider incompleta [${code}]: ${summary}`);
    this.name = 'ProviderDeliveryError';
    Object.setPrototypeOf(this, ProviderDeliveryError.prototype);
  }
}

export class ApiFootballClient {
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
