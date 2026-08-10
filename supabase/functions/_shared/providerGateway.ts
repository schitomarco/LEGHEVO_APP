import type { SupabaseClient } from 'npm:@supabase/supabase-js@2';
import type {
  ApiFootballEnvelope,
  ApiFootballReader,
} from './apiFootball.ts';
import {
  ProviderQuotaError,
  type ProviderPriority,
  type ProviderRequestOptions,
  sha256Hex,
  stableProviderRequestHashInput,
} from './footballProvider.ts';

type BudgetClaim = {
  allowed: boolean;
  requestId: string;
  remainingUnits: number;
};

type CacheRead<T> = {
  cacheHit: boolean;
  payload?: ApiFootballEnvelope<T>;
};

const DEFAULT_OPTIONS: Record<string, ProviderRequestOptions> = {
  '/players': {
    priority: 'P2',
    ttlSeconds: 24 * 60 * 60,
    reasonCode: 'season-player-catalog',
  },
  '/fixtures': {
    priority: 'P1',
    ttlSeconds: 60 * 60,
    reasonCode: 'fixture-lifecycle',
  },
  '/fixtures/players': {
    priority: 'P0',
    ttlSeconds: 5 * 60,
    reasonCode: 'final-player-statistics',
  },
};

export class QuotaCachedApiFootballClient implements ApiFootballReader {
  readonly provider = 'api-football';

  constructor(
    private readonly supabase: SupabaseClient,
    private readonly upstream: ApiFootballReader,
    private readonly currentRunId: () => string | null,
  ) {}

  async get<T>(
    path: string,
    parameters: Record<string, string | number>,
    options = DEFAULT_OPTIONS[path],
  ): Promise<ApiFootballEnvelope<T>> {
    if (!options) {
      throw new Error(`Policy cache/quota assente per ${path}.`);
    }
    assertRequestOptions(options);

    const requestHash = await sha256Hex(
      stableProviderRequestHashInput(this.provider, path, parameters),
    );
    const cached = await this.readCache<T>(path, requestHash);
    if (cached.cacheHit && cached.payload) {
      await this.recordCacheHit(
        path,
        requestHash,
        parameters,
        options,
      );
      return cached.payload;
    }

    const claim = await this.claimBudget(
      path,
      requestHash,
      options.priority,
      parameters,
      options,
    );
    if (!claim.allowed) {
      throw new ProviderQuotaError(
        this.provider,
        options.priority,
        claim.remainingUnits,
      );
    }

    try {
      const envelope = await this.upstream.get<T>(path, parameters, options);
      await this.writeCache(path, requestHash, envelope, options.ttlSeconds);
      await this.finishRequest(claim.requestId, true, envelope);
      return envelope;
    } catch (error) {
      try {
        await this.finishRequest(
          claim.requestId,
          false,
          null,
          error instanceof Error ? error.name : 'provider.request_failed',
        );
      } catch (finishError) {
        console.error(
          'Impossibile chiudere il ledger della richiesta provider.',
          finishError,
        );
      }
      throw error;
    }
  }

  private async readCache<T>(path: string, requestHash: string) {
    const { data, error } = await this.supabase.rpc(
      'read_provider_response_cache_v1',
      {
        p_provider: this.provider,
        p_endpoint: path,
        p_request_hash: requestHash,
      },
    );
    if (error) {
      throw error;
    }
    return (data ?? { cacheHit: false }) as CacheRead<T>;
  }

  private async claimBudget(
    path: string,
    requestHash: string,
    priority: ProviderPriority,
    parameters: Record<string, string | number>,
    options: ProviderRequestOptions,
  ) {
    const { data, error } = await this.supabase.rpc(
      'claim_provider_request_budget_v2',
      {
        p_provider: this.provider,
        p_endpoint: path,
        p_request_hash: requestHash,
        p_priority: priority,
        p_run_id: this.currentRunId(),
        p_reason_code: options.reasonCode ?? 'scheduled-sync',
        p_retry_no: options.retryNo ?? 0,
        p_fallback_provider: options.fallbackProvider ?? null,
        p_request_context: parameters,
      },
    );
    if (error) {
      throw error;
    }
    const claim = (data ?? {}) as Partial<BudgetClaim>;
    if (typeof claim.allowed !== 'boolean' || !claim.requestId) {
      throw new Error('Risposta del quota manager provider non valida.');
    }
    return {
      allowed: claim.allowed,
      requestId: String(claim.requestId),
      remainingUnits: Number(claim.remainingUnits) || 0,
    };
  }

  private async recordCacheHit(
    path: string,
    requestHash: string,
    parameters: Record<string, string | number>,
    options: ProviderRequestOptions,
  ) {
    const { error } = await this.supabase.rpc(
      'record_provider_cache_hit_v1',
      {
        p_provider: this.provider,
        p_endpoint: path,
        p_request_hash: requestHash,
        p_priority: options.priority,
        p_run_id: this.currentRunId(),
        p_reason_code: options.reasonCode ?? 'scheduled-sync',
        p_retry_no: options.retryNo ?? 0,
        p_fallback_provider: options.fallbackProvider ?? null,
        p_request_context: parameters,
      },
    );
    if (error) {
      throw error;
    }
  }

  private async writeCache<T>(
    path: string,
    requestHash: string,
    envelope: ApiFootballEnvelope<T>,
    ttlSeconds: number,
  ) {
    const { error } = await this.supabase.rpc(
      'write_provider_response_cache_v1',
      {
        p_provider: this.provider,
        p_endpoint: path,
        p_request_hash: requestHash,
        p_payload: envelope,
        p_ttl_seconds: ttlSeconds,
        p_etag: envelope.quota?.etag ?? null,
        p_last_modified: envelope.quota?.lastModified ?? null,
      },
    );
    if (error) {
      throw error;
    }
  }

  private async finishRequest<T>(
    requestId: string,
    succeeded: boolean,
    envelope: ApiFootballEnvelope<T> | null,
    errorCode: string | null = null,
  ) {
    const { error } = await this.supabase.rpc(
      'finish_provider_request_v1',
      {
        p_request_id: requestId,
        p_succeeded: succeeded,
        p_http_status: envelope?.quota?.httpStatus ?? null,
        p_provider_reported_limit: envelope?.quota?.dailyLimit ?? null,
        p_provider_reported_remaining:
          envelope?.quota?.dailyRemaining ?? null,
        p_error_code: errorCode,
      },
    );
    if (error) {
      throw error;
    }
  }
}

function assertRequestOptions(options: ProviderRequestOptions) {
  if (!['P0', 'P1', 'P2', 'P3'].includes(options.priority)) {
    throw new Error('Priorità provider non valida.');
  }
  if (
    !Number.isInteger(options.ttlSeconds)
    || options.ttlSeconds < 1
    || options.ttlSeconds > 604800
  ) {
    throw new Error('TTL provider non valido.');
  }
  if (
    options.retryNo !== undefined
    && (!Number.isInteger(options.retryNo) || options.retryNo < 0)
  ) {
    throw new Error('Numero retry provider non valido.');
  }
}
