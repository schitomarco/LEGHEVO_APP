import {
  parseOptionalHeaderInteger,
  type ProviderQuotaMetadata,
  type ProviderRequestOptions,
} from './footballProvider.ts';

const FOOTBALL_DATA_BASE_URL = 'https://api.football-data.org/v4';

export type FootballDataEnvelope<T> = {
  response: T[];
  raw: unknown;
  quota: ProviderQuotaMetadata;
};

export interface FootballDataReader {
  readonly provider: string;
  get<T>(
    path: string,
    parameters: Record<string, string | number>,
    options?: ProviderRequestOptions,
  ): Promise<FootballDataEnvelope<T>>;
}

export class FootballDataClient implements FootballDataReader {
  readonly provider = 'football-data';

  constructor(private readonly apiToken: string) {}

  async get<T>(
    path: string,
    parameters: Record<string, string | number>,
    _options?: ProviderRequestOptions,
  ): Promise<FootballDataEnvelope<T>> {
    if (!path.startsWith('/')) {
      throw new Error('Endpoint football-data.org non valido.');
    }
    const url = new URL(`${FOOTBALL_DATA_BASE_URL}${path}`);
    Object.entries(parameters).forEach(([key, value]) => {
      url.searchParams.set(key, String(value));
    });

    const response = await fetch(url, {
      headers: { 'X-Auth-Token': this.apiToken },
    });
    if (!response.ok) {
      throw new Error(
        `football-data.org ha risposto con HTTP ${response.status}.`,
      );
    }

    const raw = await response.json() as unknown;
    return {
      response: normalizeFootballDataCollection<T>(raw),
      raw,
      quota: {
        httpStatus: response.status,
        dailyLimit: null,
        dailyRemaining: null,
        minuteLimit: parseOptionalHeaderInteger(
          response.headers.get('x-requests-available-minute'),
        ),
        minuteRemaining: null,
        etag: response.headers.get('etag'),
        lastModified: response.headers.get('last-modified'),
      },
    };
  }
}

function normalizeFootballDataCollection<T>(raw: unknown): T[] {
  if (Array.isArray(raw)) {
    return raw as T[];
  }
  if (!raw || typeof raw !== 'object') {
    throw new Error('Payload football-data.org non valido.');
  }
  const record = raw as Record<string, unknown>;
  for (const key of ['matches', 'teams', 'standings', 'competitions']) {
    if (Array.isArray(record[key])) {
      return record[key] as T[];
    }
  }
  throw new Error('Collezione football-data.org non riconosciuta.');
}
