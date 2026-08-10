import { withSupabase } from 'npm:@supabase/server@1';
import type { SupabaseClient } from 'npm:@supabase/supabase-js@2';
import {
  ApiFootballClient,
  type ApiFootballReader,
  ProviderContractError,
  ProviderDeliveryError,
  createProviderContractError,
} from '../_shared/apiFootball.ts';
import {
  FootballDataClient,
  type FootballDataReader,
} from '../_shared/footballData.ts';
import {
  QuotaCachedApiFootballClient,
  QuotaCachedFootballDataClient,
} from '../_shared/providerGateway.ts';
import { ProviderQuotaError } from '../_shared/footballProvider.ts';

const PROVIDER = 'api-football';
const FOOTBALL_DATA_PROVIDER = 'football-data';
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
      provider?: 'api-football' | 'football-data';
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

type FootballDataFixture = {
  id: number;
  utcDate: string;
  status: string;
  matchday: number;
  homeTeam: { id: number; name: string; shortName?: string | null };
  awayTeam: { id: number; name: string; shortName?: string | null };
  score: { fullTime: { home: number | null; away: number | null } };
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

      let body: unknown;
      try {
        body = await request.json();
      } catch {
        return json({ error: 'Corpo JSON non valido.' }, 400);
      }

      const supabase = context.supabaseAdmin;
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
        const provider = requestedProvider(payload);
        const apiKey = Deno.env.get('API_FOOTBALL_KEY');
        const footballDataKey = Deno.env.get('FOOTBALL_DATA_API_KEY');
        const api = apiKey
          ? new QuotaCachedApiFootballClient(
              supabase,
              new ApiFootballClient(apiKey),
              () => run.id,
            )
          : null;
        const footballData = footballDataKey
          ? new QuotaCachedFootballDataClient(
              supabase,
              new FootballDataClient(footballDataKey),
              () => run.id,
            )
          : null;
        if (provider === PROVIDER && !api) {
          throw new Error('Chiave API-Football non configurata.');
        }
        if (provider === FOOTBALL_DATA_PROVIDER && !footballData) {
          throw new Error('Chiave football-data.org non configurata.');
        }
        run = await heartbeatRun(supabase, run, {
          phase: 'starting',
          current: 0,
          total: null,
          recordsProcessed: run.recordsProcessed,
        });

        const recordsProcessed = await executeSync(
          supabase,
          api,
          footballData,
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
          error instanceof ProviderContractError
            ? 422
            : error instanceof ProviderQuotaError
              ? 429
              : 500,
        );
      }
    },
  ),
};

async function executeSync(
  supabase: SupabaseClient,
  api: ApiFootballReader | null,
  footballData: FootballDataReader | null,
  payload: SyncRequest,
  leagueId: number,
  onProgress: ProviderProgressCallback,
  assertLease: ProviderLeaseAssertion,
  fencedWrite: ProviderFencedWriter,
  recordDelivery: ProviderDeliveryRecorder,
) {
  const provider = requestedProvider(payload);
  if (provider === FOOTBALL_DATA_PROVIDER) {
    if (payload.action !== 'sync-fixtures' || !footballData) {
      throw new Error('football-data.org è autorizzato soltanto per il calendario.');
    }
    return syncFootballDataFixtures(
      supabase,
      footballData,
      payload.season,
      payload.date,
      onProgress,
      assertLease,
      fencedWrite,
      recordDelivery,
    );
  }
  if (!api) throw new Error('Client API-Football non configurato.');
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

function requestedProvider(payload: SyncRequest) {
  return payload.action === 'sync-fixtures'
    ? payload.provider ?? PROVIDER
    : PROVIDER;
}

async function syncSeasonPlayers(
  supabase: SupabaseClient,
  api: ApiFootballReader,
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
  api: ApiFootballReader,
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

async function syncFootballDataFixtures(
  supabase: SupabaseClient,
  api: FootballDataReader,
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
  const envelope = await api.get<FootballDataFixture>(
    '/competitions/2019/matches',
    { season, dateFrom: date, dateTo: date },
  );
  const fixtures = envelope.response;
  for (let index = 0; index < fixtures.length; index += 1) {
    const issue = validateFootballDataFixture(fixtures[index]);
    if (issue) {
      throw await createProviderContractError(
        'response:/competitions/2019/matches',
        issue.code,
        issue.summary,
        envelope.raw,
        index,
        'football-data-v4/leghevo-contract-v1',
      );
    }
  }

  const grouped = new Map<number, FootballDataFixture[]>();
  for (const fixture of fixtures) {
    const group = grouped.get(fixture.matchday) ?? [];
    group.push(fixture);
    grouped.set(fixture.matchday, group);
  }
  let completedGroups = 0;
  let processed = 0;
  for (const [number, group] of grouped.entries()) {
    const kickoffDates = group
      .map((item) => new Date(item.utcDate))
      .sort((left, right) => left.getTime() - right.getTime());
    const startsAt = kickoffDates[0];
    const endsAt = new Date(
      kickoffDates[kickoffDates.length - 1].getTime() + 3 * 60 * 60 * 1000,
    );
    const fencedMatchday = await fencedWrite('upsert-matchday', {
      competition_code: COMPETITION_CODE,
      season: String(season),
      number,
      starts_at: startsAt.toISOString(),
      locks_at: startsAt.toISOString(),
      ends_at: endsAt.toISOString(),
    });
    let matchday: { id: string };
    if (fencedMatchday) {
      matchday = normalizeFencedMatchday(fencedMatchday);
    } else {
      await assertLease();
      const { data, error } = await supabase.from('matchdays').upsert(
        {
          competition_code: COMPETITION_CODE,
          season: String(season),
          number,
          starts_at: startsAt.toISOString(),
          locks_at: startsAt.toISOString(),
          ends_at: endsAt.toISOString(),
        },
        { onConflict: 'competition_code,season,number' },
      ).select('id').single();
      if (error) throw error;
      matchday = data;
    }

    const rows = group.map((item) => ({
      provider: FOOTBALL_DATA_PROVIDER,
      provider_fixture_id: String(item.id),
      competition_code: COMPETITION_CODE,
      season: String(season),
      matchday_id: matchday.id,
      kickoff_at: item.utcDate,
      status: normalizeFootballDataStatus(item.status),
      home_team_provider_id: String(item.homeTeam.id),
      home_team_name: item.homeTeam.name,
      away_team_provider_id: String(item.awayTeam.id),
      away_team_name: item.awayTeam.name,
      home_goals: item.score.fullTime.home,
      away_goals: item.score.fullTime.away,
      payload: item,
      updated_at: new Date().toISOString(),
    }));
    const fencedFixtures = await fencedWrite('upsert-provider-fixtures', rows);
    if (!fencedFixtures) {
      await assertLease();
      const { error } = await supabase.from('provider_fixtures').upsert(
        rows,
        { onConflict: 'provider,provider_fixture_id' },
      );
      if (error) throw error;
    }
    completedGroups += 1;
    processed += group.length;
    await onProgress({
      phase: 'fixtures',
      current: completedGroups,
      total: grouped.size,
      recordsProcessed: processed,
    });
  }
  if (grouped.size === 0) {
    await onProgress({
      phase: 'fixtures', current: 0, total: 0, recordsProcessed: 0,
    });
  }
  await recordDelivery({
    unitNo: 1,
    expectedUnitCount: 1,
    declaredCurrent: 1,
    declaredTotal: 1,
    declaredResults: fixtures.length,
    observedResults: fixtures.length,
    recordsProcessed: processed,
    entityKeys: fixtures.map((item) => String(item.id)),
  });
  return fixtures.length;
}

function validateFootballDataFixture(item: FootballDataFixture) {
  if (!item || typeof item !== 'object') {
    return { code: 'fixture.object', summary: 'Partita football-data.org non valida.' };
  }
  if (!Number.isInteger(item.id) || item.id <= 0) {
    return { code: 'fixture.id', summary: 'Identificativo partita non valido.' };
  }
  if (!Number.isInteger(item.matchday) || item.matchday <= 0) {
    return { code: 'fixture.matchday', summary: 'Giornata partita non valida.' };
  }
  if (!item.utcDate || Number.isNaN(Date.parse(item.utcDate))) {
    return { code: 'fixture.utc_date', summary: 'Data UTC partita non valida.' };
  }
  for (const team of [item.homeTeam, item.awayTeam]) {
    if (!team || !Number.isInteger(team.id) || team.id <= 0 || !team.name?.trim()) {
      return { code: 'fixture.team', summary: 'Squadra partita non valida.' };
    }
  }
  if (!item.score || !item.score.fullTime) {
    return { code: 'fixture.score', summary: 'Punteggio partita non valido.' };
  }
  for (const score of [item.score.fullTime.home, item.score.fullTime.away]) {
    if (score !== null && (!Number.isInteger(score) || score < 0)) {
      return { code: 'fixture.score_value', summary: 'Valore punteggio non valido.' };
    }
  }
  try {
    normalizeFootballDataStatus(item.status);
  } catch {
    return { code: 'fixture.status', summary: 'Stato partita non riconosciuto.' };
  }
  return null;
}

function normalizeFootballDataStatus(status: string) {
  const statuses: Record<string, string> = {
    SCHEDULED: 'NS', TIMED: 'NS', IN_PLAY: 'LIVE', PAUSED: 'HT',
    FINISHED: 'FT', POSTPONED: 'PST', SUSPENDED: 'SUSP',
    CANCELLED: 'CANC', AWARDED: 'AWD',
  };
  const normalized = statuses[String(status).toUpperCase()];
  if (!normalized) throw new Error(`Stato football-data.org non supportato: ${status}.`);
  return normalized;
}

async function syncFixturePlayers(
  supabase: SupabaseClient,
  api: ApiFootballReader,
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
        provider: PROVIDER,
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
    'start_provider_sync_run_guarded_v3',
    { p_request: payload, p_lease_token: workerToken },
  );

  if (result.error && isMissingRpcError(result.error.message)) {
    result = await supabase.rpc(
      'start_provider_sync_run_guarded_v2',
      { p_request: payload, p_lease_token: workerToken },
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
  const footballDataFixtures = operation === 'upsert-provider-fixtures'
    && Array.isArray(payload)
    && payload.length > 0
    && payload.every((item) =>
      Boolean(item)
      && typeof item === 'object'
      && (item as Record<string, unknown>).provider === FOOTBALL_DATA_PROVIDER
    );
  if (footballDataFixtures) {
    const dedicated = await supabase.rpc(
      'stage_football_data_fixture_write_guarded_v1',
      {
        p_run_id: run.id,
        p_lease_token: run.leaseToken,
        p_payload: payload,
      },
    );
    if (dedicated.error) {
      if (isProviderPayloadContractMessage(dedicated.error.message)) {
        throw await createProviderContractError(
          `write:${operation}`,
          extractProviderPayloadContractCode(dedicated.error.message),
          dedicated.error.message,
          payload,
          null,
          'football-data-v4/leghevo-contract-v1',
        );
      }
      throw dedicated.error;
    }
    if (!dedicated.data || typeof dedicated.data !== 'object') {
      throw new Error('Risposta staging football-data non valida.');
    }
    return dedicated.data as Record<string, unknown>;
  }
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
