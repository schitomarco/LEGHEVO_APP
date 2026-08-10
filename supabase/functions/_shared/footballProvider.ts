export type ProviderPriority = 'P0' | 'P1' | 'P2' | 'P3';

export type ProviderRequestOptions = {
  priority: ProviderPriority;
  ttlSeconds: number;
  reasonCode?: string;
  retryNo?: number;
  fallbackProvider?: string | null;
};

export type ProviderQuotaMetadata = {
  httpStatus: number;
  dailyLimit: number | null;
  dailyRemaining: number | null;
  minuteLimit: number | null;
  minuteRemaining: number | null;
  etag: string | null;
  lastModified: string | null;
};

export interface FootballProviderReader<TEnvelope = unknown> {
  readonly provider: string;

  get<T>(
    path: string,
    parameters: Record<string, string | number>,
    options?: ProviderRequestOptions,
  ): Promise<TEnvelope & { response: T[] }>;
}

export class ProviderQuotaError extends Error {
  constructor(
    readonly provider: string,
    readonly priority: ProviderPriority,
    readonly remainingUnits: number,
  ) {
    super(
      `Rate limit giornaliero ${provider} esaurito per priorità ${priority}; `
      + `unità residue protette: ${remainingUnits}.`,
    );
    this.name = 'ProviderQuotaError';
    Object.setPrototypeOf(this, ProviderQuotaError.prototype);
  }
}

export function stableProviderRequestHashInput(
  provider: string,
  path: string,
  parameters: Record<string, string | number>,
) {
  const normalizedParameters = Object.entries(parameters)
    .sort(([left], [right]) => left.localeCompare(right))
    .map(([key, value]) => [key, String(value)]);
  return JSON.stringify([
    provider.trim().toLowerCase(),
    path.trim(),
    normalizedParameters,
  ]);
}

export async function sha256Hex(value: string) {
  const encoded = new TextEncoder().encode(value);
  const digest = await crypto.subtle.digest('SHA-256', encoded);
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, '0'))
    .join('');
}

export function parseOptionalHeaderInteger(value: string | null) {
  if (value === null || value.trim() === '') {
    return null;
  }
  const parsed = Number(value);
  return Number.isInteger(parsed) && parsed >= 0 ? parsed : null;
}
