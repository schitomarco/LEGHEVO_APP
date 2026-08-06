import { supabase } from '../lib/supabase';
import type {
  LeagueSeasonChampion,
  LeagueSeasonState,
  LeagueStanding,
  StandingsTiebreaker,
} from '../types';

export async function fetchLeagueSeasonState(
  leagueId: string,
): Promise<LeagueSeasonState> {
  if (!supabase) {
    throw new Error('Il collegamento al backend non è configurato.');
  }

  const latest = await supabase.rpc('get_league_season_state_v13', {
    p_league_id: leagueId,
  });

  if (!latest.error) {
    return normalizeLeagueSeasonState(latest.data);
  }

  if (!isMissingRpc(latest.error.message, 'get_league_season_state_v13')) {
    throw new Error(translateSeasonError(latest.error.message));
  }

  const fallbackV12 = await supabase.rpc('get_league_season_state_v12', {
    p_league_id: leagueId,
  });

  if (!fallbackV12.error) {
    return normalizeLeagueSeasonState(fallbackV12.data);
  }

  if (!isMissingRpc(fallbackV12.error.message, 'get_league_season_state_v12')) {
    throw new Error(translateSeasonError(fallbackV12.error.message));
  }

  const fallbackV11 = await supabase.rpc('get_league_season_state_v11', {
    p_league_id: leagueId,
  });

  if (!fallbackV11.error) {
    return normalizeLeagueSeasonState(fallbackV11.data);
  }

  if (!isMissingRpc(fallbackV11.error.message, 'get_league_season_state_v11')) {
    throw new Error(translateSeasonError(fallbackV11.error.message));
  }

  const fallbackV10 = await supabase.rpc('get_league_season_state_v10', {
    p_league_id: leagueId,
  });

  if (!fallbackV10.error) {
    return normalizeLeagueSeasonState(fallbackV10.data);
  }

  if (!isMissingRpc(fallbackV10.error.message, 'get_league_season_state_v10')) {
    throw new Error(translateSeasonError(fallbackV10.error.message));
  }

  const fallbackV9 = await supabase.rpc('get_league_season_state_v9', {
    p_league_id: leagueId,
  });

  if (!fallbackV9.error) {
    return normalizeLeagueSeasonState(fallbackV9.data);
  }

  if (!isMissingRpc(fallbackV9.error.message, 'get_league_season_state_v9')) {
    throw new Error(translateSeasonError(fallbackV9.error.message));
  }

  const fallbackV8 = await supabase.rpc('get_league_season_state_v8', {
    p_league_id: leagueId,
  });

  if (!fallbackV8.error) {
    return normalizeLeagueSeasonState(fallbackV8.data);
  }

  if (!isMissingRpc(fallbackV8.error.message, 'get_league_season_state_v8')) {
    throw new Error(translateSeasonError(fallbackV8.error.message));
  }

  const fallbackV7 = await supabase.rpc('get_league_season_state_v7', {
    p_league_id: leagueId,
  });

  if (!fallbackV7.error) {
    return normalizeLeagueSeasonState(fallbackV7.data);
  }

  if (!isMissingRpc(fallbackV7.error.message, 'get_league_season_state_v7')) {
    throw new Error(translateSeasonError(fallbackV7.error.message));
  }

  const fallbackV6 = await supabase.rpc('get_league_season_state_v6', {
    p_league_id: leagueId,
  });

  if (!fallbackV6.error) {
    return normalizeLeagueSeasonState(fallbackV6.data);
  }

  if (!isMissingRpc(fallbackV6.error.message, 'get_league_season_state_v6')) {
    throw new Error(translateSeasonError(fallbackV6.error.message));
  }

  const fallbackV5 = await supabase.rpc('get_league_season_state_v5', {
    p_league_id: leagueId,
  });

  if (!fallbackV5.error) {
    return normalizeLeagueSeasonState(fallbackV5.data);
  }

  if (!isMissingRpc(fallbackV5.error.message, 'get_league_season_state_v5')) {
    throw new Error(translateSeasonError(fallbackV5.error.message));
  }

  const fallbackV4 = await supabase.rpc('get_league_season_state_v4', {
    p_league_id: leagueId,
  });

  if (!fallbackV4.error) {
    return normalizeLeagueSeasonState(fallbackV4.data);
  }

  if (!isMissingRpc(fallbackV4.error.message, 'get_league_season_state_v4')) {
    throw new Error(translateSeasonError(fallbackV4.error.message));
  }

  const fallback = await supabase.rpc('get_league_season_state_v3', {
    p_league_id: leagueId,
  });

  if (fallback.error) {
    throw new Error(translateSeasonError(fallback.error.message));
  }

  return normalizeLeagueSeasonState(fallback.data);
}

export async function completeLeagueSeason(
  leagueId: string,
): Promise<{ championTeamId?: string; error?: string }> {
  if (!supabase) {
    return { error: 'Il collegamento al backend non è configurato.' };
  }

  const requestId = createRequestId();
  const latest = await supabase.rpc(
    'complete_league_season_guarded_v3',
    {
      p_league_id: leagueId,
      p_request_id: requestId,
    },
  );

  if (!latest.error) {
    const payload = asRecord(latest.data);
    return {
      championTeamId: toNullableString(payload.championTeamId) ?? undefined,
    };
  }

  if (!isMissingRpc(
    latest.error.message,
    'complete_league_season_guarded_v3',
  )) {
    return { error: translateSeasonError(latest.error.message) };
  }

  const fallbackV2 = await supabase.rpc(
    'complete_league_season_guarded_v2',
    {
      p_league_id: leagueId,
      p_request_id: requestId,
    },
  );

  if (!fallbackV2.error) {
    const payload = asRecord(fallbackV2.data);
    return {
      championTeamId: toNullableString(payload.championTeamId) ?? undefined,
    };
  }

  if (!isMissingRpc(
    fallbackV2.error.message,
    'complete_league_season_guarded_v2',
  )) {
    return { error: translateSeasonError(fallbackV2.error.message) };
  }

  const fallbackGuarded = await supabase.rpc(
    'complete_league_season_guarded_v1',
    {
      p_league_id: leagueId,
      p_request_id: requestId,
    },
  );

  if (!fallbackGuarded.error) {
    const payload = asRecord(fallbackGuarded.data);
    return {
      championTeamId: toNullableString(payload.championTeamId) ?? undefined,
    };
  }

  if (!isMissingRpc(
    fallbackGuarded.error.message,
    'complete_league_season_guarded_v1',
  )) {
    return { error: translateSeasonError(fallbackGuarded.error.message) };
  }

  const fallback = await supabase.rpc('complete_league_season', {
    p_league_id: leagueId,
  });

  if (fallback.error) {
    return { error: translateSeasonError(fallback.error.message) };
  }

  return {
    championTeamId:
      typeof fallback.data === 'string' ? fallback.data : undefined,
  };
}

export async function renewLeagueSeason(
  leagueId: string,
  nextSeason: string,
): Promise<{ renewedLeagueId?: string; error?: string }> {
  if (!supabase) {
    return { error: 'Il collegamento al backend non è configurato.' };
  }

  const requestId = createRequestId();
  const guardedV3 = await supabase.rpc('renew_league_season_guarded_v3', {
    p_league_id: leagueId,
    p_next_season: nextSeason.trim(),
    p_request_id: requestId,
  });

  if (!guardedV3.error) {
    const payload = asRecord(guardedV3.data);
    return {
      renewedLeagueId:
        toNullableString(payload.renewedLeagueId) ?? undefined,
    };
  }

  if (!isMissingRpc(
    guardedV3.error.message,
    'renew_league_season_guarded_v3',
  )) {
    return { error: translateSeasonError(guardedV3.error.message) };
  }

  const guardedV2 = await supabase.rpc('renew_league_season_guarded_v2', {
    p_league_id: leagueId,
    p_next_season: nextSeason.trim(),
    p_request_id: requestId,
  });

  if (!guardedV2.error) {
    const payload = asRecord(guardedV2.data);
    return {
      renewedLeagueId:
        toNullableString(payload.renewedLeagueId) ?? undefined,
    };
  }

  if (!isMissingRpc(
    guardedV2.error.message,
    'renew_league_season_guarded_v2',
  )) {
    return { error: translateSeasonError(guardedV2.error.message) };
  }

  const fallback = await supabase.rpc('renew_league_season', {
    p_league_id: leagueId,
    p_next_season: nextSeason.trim(),
  });

  if (fallback.error) {
    return { error: translateSeasonError(fallback.error.message) };
  }

  return {
    renewedLeagueId:
      typeof fallback.data === 'string' ? fallback.data : undefined,
  };
}

export function normalizeLeagueSeasonState(
  value: unknown,
): LeagueSeasonState {
  const raw = asRecord(value);
  const finalStandings = Array.isArray(raw.finalStandings)
    ? raw.finalStandings.map(normalizeFinalStanding)
    : [];

  return {
    status: normalizeLeagueStatus(raw.leagueStatus),
    season: toNullableString(raw.season),
    competitionStartedAt: toNullableString(raw.competitionStartedAt),
    completedAt: toNullableString(raw.completedAt),
    isOwner: Boolean(raw.isOwner),
    fixtureCount: toNumber(raw.fixtureCount),
    officialFixtureCount: toNumber(raw.officialFixtureCount),
    remainingFixtureCount: toNumber(raw.remainingFixtureCount),
    canComplete: Boolean(raw.canComplete),
    champion: normalizeChampion(raw.champion),
    tiebreaker: normalizeTiebreaker(raw.standingsTiebreaker),
    finalStandings,
    completionCertified: Boolean(raw.completionCertified),
    completionRunId: toNullableNumber(raw.completionRunId),
    completionStandingsHash: toNullableString(raw.completionStandingsHash),
    finalProgressionRunId: toNullableNumber(raw.finalProgressionRunId),
    finalMatchdayId: toNullableString(raw.finalMatchdayId),
    seasonReadyToComplete: Boolean(raw.seasonReadyToComplete),
    seasonCompletionCausalStatus:
      raw.seasonCompletionCausalStatus === 'clear' ||
      raw.seasonCompletionCausalStatus === 'affected'
        ? raw.seasonCompletionCausalStatus
        : 'blocked',
    seasonCompletionCausalReason: toNullableString(
      raw.seasonCompletionCausalReason,
    ),
    seasonCompletionCausallyCertified: Boolean(
      raw.seasonCompletionCausallyCertified,
    ),
    seasonCompletionAffected: Boolean(raw.seasonCompletionAffected),
    officialSnapshotProtected: Boolean(raw.officialSnapshotProtected),
    officialSnapshotPublished: Boolean(raw.officialSnapshotPublished),
    officialSnapshotHealthy:
      raw.officialSnapshotHealthy === undefined
        ? true
        : Boolean(raw.officialSnapshotHealthy),
    officialSnapshotStatus:
      raw.officialSnapshotStatus === 'official' ||
      raw.officialSnapshotStatus === 'affected'
        ? raw.officialSnapshotStatus
        : 'pending',
    officialSnapshotReason: toNullableString(raw.officialSnapshotReason),
    officialSnapshotAffected: Boolean(raw.officialSnapshotAffected),
    officialSnapshotId: toNullableNumber(raw.officialSnapshotId),
    officialSnapshotHash: toNullableString(raw.officialSnapshotHash),
    officialPodium: Array.isArray(raw.officialPodium)
      ? raw.officialPodium.map(normalizeFinalStanding)
      : [],
    seasonRolloverProtected: Boolean(raw.seasonRolloverProtected),
    seasonRolloverCertified: Boolean(raw.seasonRolloverCertified),
    seasonRolloverHealthy:
      raw.seasonRolloverHealthy === undefined
        ? true
        : Boolean(raw.seasonRolloverHealthy),
    seasonRolloverStatus:
      raw.seasonRolloverStatus === 'certified' ||
      raw.seasonRolloverStatus === 'affected'
        ? raw.seasonRolloverStatus
        : 'pending',
    seasonRolloverReason: toNullableString(raw.seasonRolloverReason),
    seasonRolloverAffected: Boolean(raw.seasonRolloverAffected),
    seasonRolloverCertificateId: toNullableNumber(
      raw.seasonRolloverCertificateId,
    ),
    seasonRolloverLineageHash: toNullableString(
      raw.seasonRolloverLineageHash,
    ),
    seasonRolloverSourceSnapshotHash: toNullableString(
      raw.seasonRolloverSourceSnapshotHash,
    ),
    providerSeasonBootstrapProtected: Boolean(raw.providerSeasonBootstrapProtected),
    providerSeasonBootstrapApplicable: Boolean(raw.providerSeasonBootstrapApplicable),
    providerSeasonBootstrapHealthy:
      raw.providerSeasonBootstrapHealthy === undefined
        ? true
        : Boolean(raw.providerSeasonBootstrapHealthy),
    providerSeasonBootstrapAffected: Boolean(raw.providerSeasonBootstrapAffected),
    providerSeasonBootstrapStatus:
      raw.providerSeasonBootstrapStatus === 'catalog_ready' ||
      raw.providerSeasonBootstrapStatus === 'ready' ||
      raw.providerSeasonBootstrapStatus === 'affected'
        ? raw.providerSeasonBootstrapStatus
        : 'waiting',
    providerSeasonBootstrapReason: toNullableString(raw.providerSeasonBootstrapReason),
    providerSeasonCatalogReady: Boolean(raw.providerSeasonCatalogReady),
    providerSeasonFixturesReady: Boolean(raw.providerSeasonFixturesReady),
    providerSeasonBootstrapCertified: Boolean(raw.providerSeasonBootstrapCertified),
    providerSeasonBootstrapCertificateId: toNullableNumber(
      raw.providerSeasonBootstrapCertificateId,
    ),
    providerSeasonBootstrapHash: toNullableString(raw.providerSeasonBootstrapHash),
    providerCompetitionStartProtected: Boolean(raw.providerCompetitionStartProtected),
    providerCompetitionStartApplicable: Boolean(raw.providerCompetitionStartApplicable),
    providerCompetitionStartHealthy:
      raw.providerCompetitionStartHealthy === undefined
        ? true
        : Boolean(raw.providerCompetitionStartHealthy),
    providerCompetitionStartAffected: Boolean(raw.providerCompetitionStartAffected),
    providerCompetitionStartStatus:
      raw.providerCompetitionStartStatus === 'ready' ||
      raw.providerCompetitionStartStatus === 'official' ||
      raw.providerCompetitionStartStatus === 'affected'
        ? raw.providerCompetitionStartStatus
        : 'waiting',
    providerCompetitionStartReason: toNullableString(raw.providerCompetitionStartReason),
    providerCompetitionStartReady: Boolean(raw.providerCompetitionStartReady),
    providerCompetitionStartCertified: Boolean(raw.providerCompetitionStartCertified),
    providerCompetitionStartCertificateId: toNullableNumber(
      raw.providerCompetitionStartCertificateId,
    ),
    providerCompetitionStartHash: toNullableString(raw.providerCompetitionStartHash),
  };
}

function normalizeFinalStanding(value: unknown): LeagueStanding {
  const raw = asRecord(value);
  return {
    position: toNumber(raw.position),
    teamId: toStringValue(raw.teamId),
    teamName: toStringValue(raw.teamName),
    played: toNumber(raw.played),
    won: toNumber(raw.won),
    drawn: toNumber(raw.drawn),
    lost: toNumber(raw.lost),
    goalsFor: toNumber(raw.goalsFor),
    goalsAgainst: toNumber(raw.goalsAgainst),
    goalDifference: toNumber(raw.goalDifference),
    pointsFor: toNumber(raw.pointsFor),
    leaguePoints: toNumber(raw.leaguePoints),
    headToHeadPlayed: 0,
    headToHeadPoints: 0,
    headToHeadGoalDifference: 0,
    headToHeadEligible: false,
  };
}

function normalizeChampion(value: unknown): LeagueSeasonChampion | null {
  if (!value || typeof value !== 'object') {
    return null;
  }
  const raw = value as Record<string, unknown>;
  const teamId = toStringValue(raw.teamId);
  if (!teamId) {
    return null;
  }
  return {
    teamId,
    teamName: toStringValue(raw.teamName),
    managerName: toStringValue(raw.managerName),
    leaguePoints: toNumber(raw.leaguePoints),
    pointsFor: toNumber(raw.pointsFor),
  };
}

function normalizeLeagueStatus(
  value: unknown,
): LeagueSeasonState['status'] {
  if (
    value === 'draft' ||
    value === 'active' ||
    value === 'completed' ||
    value === 'archived'
  ) {
    return value;
  }
  return 'draft';
}

function normalizeTiebreaker(value: unknown): StandingsTiebreaker {
  if (
    value === 'goal_difference' ||
    value === 'fantasy_points' ||
    value === 'head_to_head'
  ) {
    return value;
  }
  return 'goal_difference';
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

function toNumber(value: unknown) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : 0;
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
  return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(
    /[xy]/g,
    (character) => {
      const random = Math.floor(Math.random() * 16);
      const value = character === 'x' ? random : (random & 0x3) | 0x8;
      return value.toString(16);
    },
  );
}

function translateSeasonError(message: string) {
  const normalized = message.toLowerCase();
  if (normalized.includes('get_league_season_state_v13')) {
    return 'Aggiorna il database LEGHEVO fino alla migrazione 139.';
  }
  if (normalized.includes('get_league_season_state_v12')) {
    return 'Aggiorna il database LEGHEVO fino alla migrazione 138.';
  }
  if (normalized.includes('get_league_season_state_v11')) {
    return 'Aggiorna il database LEGHEVO fino alla migrazione 137.';
  }
  if (normalized.includes('get_league_season_state_v10')) {
    return 'Aggiorna il database LEGHEVO fino alla migrazione 136.';
  }
  if (normalized.includes('get_league_season_state_v9')) {
    return 'Aggiorna il database LEGHEVO fino alla migrazione 135.';
  }

  if (
    normalized.includes('get_league_season_state_v8') ||
    normalized.includes('renew_league_season_guarded_v3')
  ) {
    return 'Aggiorna prima il database LEGHEVO con la migrazione 134.';
  }
  if (
    normalized.includes('get_league_season_state_v7') ||
    normalized.includes('renew_league_season_guarded_v2')
  ) {
    return 'Aggiorna prima il database LEGHEVO con la migrazione 133.';
  }
  if (
    normalized.includes('get_league_season_state_v6') ||
    normalized.includes('complete_league_season_guarded_v3')
  ) {
    return 'Aggiorna prima il database LEGHEVO con la migrazione 132.';
  }
  if (
    normalized.includes('get_league_season_state_v5') ||
    normalized.includes('complete_league_season_guarded_v2')
  ) {
    return 'Aggiorna prima il database LEGHEVO con la migrazione 131.';
  }
  if (
    normalized.includes('get_league_season_state_v5') ||
    normalized.includes('get_league_season_state_v4') ||
    normalized.includes('get_league_season_state_v3') ||
    normalized.includes('complete_league_season_guarded_v2') ||
    normalized.includes('complete_league_season_guarded_v1') ||
    normalized.includes('complete_league_season') ||
    normalized.includes('renew_league_season') ||
    (normalized.includes('function') && normalized.includes('does not exist'))
  ) {
    return 'Aggiorna prima il database LEGHEVO con il file 082.';
  }
  if (normalized.includes('provider.season_completion_gate')) {
    if (normalized.includes('progression_gate_missing')) {
      return 'La chiusura è bloccata: manca la certificazione provider di una giornata.';
    }
    if (normalized.includes('progression_generation_mismatch')) {
      return 'La chiusura è bloccata: una progressione non coincide più con la generazione certificata.';
    }
    if (normalized.includes('progression_chain_unsafe')) {
      return 'La chiusura è bloccata: una giornata dipende da risultati provider da verificare.';
    }
    return 'La chiusura resta bloccata finché tutte le progressioni giornata non tornano certificate.';
  }
  if (normalized.includes('season_rollover.source_snapshot_affected')) {
    return 'Il rinnovo è bloccato: lo snapshot ufficiale richiede una verifica della Direzione.';
  }
  if (normalized.includes('snapshot ufficiale della stagione assente')) {
    return 'Prima completa la stagione e pubblica lo snapshot ufficiale.';
  }
  if (normalized.includes('copia atomica')) {
    return 'Il rinnovo è stato annullato perché partecipanti e squadre non sono stati copiati in modo coerente.';
  }
  if (normalized.includes('solo il presidente')) {
    return 'Solo il Presidente può chiudere la stagione.';
  }
  if (normalized.includes('progressione di tutte le giornate')) {
    return 'Prima ufficializza e certifica in ordine tutte le giornate.';
  }
  if (normalized.includes('ultima giornata non è ancora pronta')) {
    return 'L’ultima giornata deve essere ufficializzata e avanzata prima della chiusura.';
  }
  if (normalized.includes('fotografia finale')) {
    return 'La classifica finale non supera il controllo di integrità.';
  }
  if (normalized.includes('tutti i risultati')) {
    return 'Prima devono essere ufficiali tutte le partite del calendario.';
  }
  if (normalized.includes('playoff scudetto')) {
    return 'Prima devi completare i Playoff Scudetto.';
  }
  if (normalized.includes('classifica finale')) {
    return 'La classifica finale non contiene ancora tutte le squadre.';
  }
  if (normalized.includes('stagione è conclusa')) {
    return 'La stagione è conclusa: risultati e revisioni sono congelati.';
  }
  if (normalized.includes('quattro cifre')) {
    return 'Inserisci la nuova stagione con quattro cifre, ad esempio 2027.';
  }
  if (normalized.includes('deve essere successiva')) {
    return 'La nuova stagione deve essere successiva a quella appena conclusa.';
  }
  if (normalized.includes('già stata preparata')) {
    return message;
  }
  if (normalized.includes('partecipanti e squadre')) {
    return 'Partecipanti e squadre non sono allineati: controlla lo spogliatoio prima del rinnovo.';
  }
  if (normalized.includes('prima devi chiudere')) {
    return 'Prima devi concludere ufficialmente la stagione corrente.';
  }
  return message;
}
