import { supabase } from '../lib/supabase';
import type {
  LeagueMode,
  MarketDashboard,
  MarketIntegrity,
  MarketPlayer,
  MarketTeam,
  TradeOfferStatus,
  TradeOfferSummary,
} from '../types';

type TeamRow = {
  id: string;
  name: string;
  credits_remaining: number;
};

type RosterRow = {
  fantasy_team_id: string;
  athlete_id: string;
  purchase_price: number;
};

type AthleteRow = {
  id: string;
  first_name: string | null;
  last_name: string;
  club_name: string;
  shirt_number: number | null;
};

type RoleRow = {
  athlete_id: string;
  role_code: string;
};

type OfferRow = {
  id: string;
  proposer_team_id: string;
  recipient_team_id: string;
  status: TradeOfferStatus;
  proposer_credits: number;
  recipient_credits: number;
  message: string | null;
  expires_at: string;
  created_at: string;
};

type OfferPlayerRow = {
  trade_offer_id: string;
  fantasy_team_id: string;
  athlete_id: string;
};

export type CreateTradeInput = {
  proposerTeamId: string;
  recipientTeamId: string;
  offeredPlayerIds: string[];
  requestedPlayerIds: string[];
  proposerCredits: number;
  recipientCredits: number;
  message?: string;
};

export async function fetchMarketDashboard(
  leagueId: string,
  myTeamId: string,
  mode: LeagueMode,
): Promise<MarketDashboard> {
  if (!supabase) {
    return emptyDashboard();
  }

  const [
    leagueResponse,
    teamsResponse,
    rosterResponse,
    athletesResponse,
    rolesResponse,
    offersResponse,
    auctionResponse,
  ] = await Promise.all([
    supabase
      .from('leagues')
      .select('scoring_rules')
      .eq('id', leagueId)
      .single(),
    supabase
      .from('fantasy_teams')
      .select('id, name, credits_remaining')
      .eq('league_id', leagueId)
      .order('name', { ascending: true }),
    supabase
      .from('roster_entries')
      .select('fantasy_team_id, athlete_id, purchase_price')
      .eq('league_id', leagueId)
      .is('released_at', null),
    supabase
      .from('athletes')
      .select('id, first_name, last_name, club_name, shirt_number')
      .eq('active', true)
      .order('last_name', { ascending: true })
      .limit(500),
    supabase
      .from('athlete_roles')
      .select('athlete_id, role_code')
      .eq('mode', mode),
    supabase
      .from('trade_offers')
      .select(
        'id, proposer_team_id, recipient_team_id, status, proposer_credits, recipient_credits, message, expires_at, created_at',
      )
      .eq('league_id', leagueId)
      .order('created_at', { ascending: false })
      .limit(100),
    supabase
      .from('auctions')
      .select('current_item_id')
      .eq('league_id', leagueId)
      .neq('status', 'completed')
      .order('created_at', { ascending: false })
      .limit(1)
      .maybeSingle(),
  ]);

  const firstError =
    leagueResponse.error ??
    teamsResponse.error ??
    rosterResponse.error ??
    athletesResponse.error ??
    rolesResponse.error ??
    offersResponse.error ??
    auctionResponse.error;
  if (firstError) {
    throw firstError;
  }

  const teamsData = (teamsResponse.data ?? []) as TeamRow[];
  const rosterData = (rosterResponse.data ?? []) as RosterRow[];
  const athletesData = (athletesResponse.data ?? []) as AthleteRow[];
  const rolesData = (rolesResponse.data ?? []) as RoleRow[];
  const offersData = (offersResponse.data ?? []) as OfferRow[];
  const athleteMap = new Map(
    athletesData.map((athlete) => [athlete.id, athlete]),
  );
  const roleMap = rolesData.reduce<Map<string, string[]>>((map, role) => {
    map.set(role.athlete_id, [
      ...(map.get(role.athlete_id) ?? []),
      role.role_code,
    ]);
    return map;
  }, new Map());

  const mapPlayer = (
    athleteId: string,
    teamId: string | null,
    purchasePrice: number,
  ): MarketPlayer | null => {
    const athlete = athleteMap.get(athleteId);
    if (!athlete) {
      return null;
    }
    return {
      id: athlete.id,
      name:
        [athlete.first_name, athlete.last_name].filter(Boolean).join(' ') ||
        athlete.last_name,
      clubName: athlete.club_name,
      shirtNumber: athlete.shirt_number,
      role: roleMap.get(athlete.id)?.join('/') || '—',
      purchasePrice,
      teamId,
    };
  };

  const teams: MarketTeam[] = teamsData.map((team) => ({
    id: team.id,
    name: team.name,
    creditsRemaining: team.credits_remaining,
    players: rosterData
      .filter((roster) => roster.fantasy_team_id === team.id)
      .map((roster) =>
        mapPlayer(
          roster.athlete_id,
          team.id,
          roster.purchase_price,
        ),
      )
      .filter((player): player is MarketPlayer => Boolean(player))
      .sort(comparePlayers),
  }));

  const ownedAthleteIds = new Set(
    rosterData.map((roster) => roster.athlete_id),
  );
  const auctionLockedAthleteIds = new Set<string>();
  const currentAuctionItemId = auctionResponse.data?.current_item_id;
  if (currentAuctionItemId) {
    const { data: lockedItem, error: lockedItemError } = await supabase
      .from('auction_items')
      .select('athlete_id, status')
      .eq('id', currentAuctionItemId)
      .maybeSingle();
    if (lockedItemError) {
      throw lockedItemError;
    }
    if (lockedItem?.status === 'bidding') {
      auctionLockedAthleteIds.add(lockedItem.athlete_id);
    }
  }

  const freeAgents = athletesData
    .filter(
      (athlete) =>
        !ownedAthleteIds.has(athlete.id) &&
        !auctionLockedAthleteIds.has(athlete.id),
    )
    .map((athlete) => mapPlayer(athlete.id, null, 0))
    .filter((player): player is MarketPlayer => Boolean(player))
    .sort(comparePlayers);

  let offerPlayersData: OfferPlayerRow[] = [];
  if (offersData.length > 0) {
    const { data, error } = await supabase
      .from('trade_offer_players')
      .select('trade_offer_id, fantasy_team_id, athlete_id')
      .in(
        'trade_offer_id',
        offersData.map((offer) => offer.id),
      );
    if (error) {
      throw error;
    }
    offerPlayersData = (data ?? []) as OfferPlayerRow[];
  }

  const teamMap = new Map(teams.map((team) => [team.id, team]));
  const offers: TradeOfferSummary[] = offersData.map((offer) => {
    const status =
      offer.status === 'pending' &&
      new Date(offer.expires_at).getTime() <= Date.now()
        ? 'expired'
        : offer.status;
    const players = offerPlayersData.filter(
      (player) => player.trade_offer_id === offer.id,
    );

    return {
      id: offer.id,
      proposerTeamId: offer.proposer_team_id,
      proposerTeamName:
        teamMap.get(offer.proposer_team_id)?.name ?? 'Squadra',
      recipientTeamId: offer.recipient_team_id,
      recipientTeamName:
        teamMap.get(offer.recipient_team_id)?.name ?? 'Squadra',
      status,
      proposerCredits: offer.proposer_credits,
      recipientCredits: offer.recipient_credits,
      offeredPlayers: players
        .filter(
          (player) =>
            player.fantasy_team_id === offer.proposer_team_id,
        )
        .map((player) => {
          const roster = rosterData.find(
            (item) => item.athlete_id === player.athlete_id,
          );
          return mapPlayer(
            player.athlete_id,
            offer.proposer_team_id,
            roster?.purchase_price ?? 0,
          );
        })
        .filter((player): player is MarketPlayer => Boolean(player)),
      requestedPlayers: players
        .filter(
          (player) =>
            player.fantasy_team_id === offer.recipient_team_id,
        )
        .map((player) => {
          const roster = rosterData.find(
            (item) => item.athlete_id === player.athlete_id,
          );
          return mapPlayer(
            player.athlete_id,
            offer.recipient_team_id,
            roster?.purchase_price ?? 0,
          );
        })
        .filter((player): player is MarketPlayer => Boolean(player)),
      message: offer.message,
      expiresAt: offer.expires_at,
      createdAt: offer.created_at,
    };
  });

  const scoringRules =
    (leagueResponse.data?.scoring_rules as Record<string, unknown>) ?? {};
  const integrity = await fetchMarketIntegrity(leagueId);

  return {
    marketOpen: scoringRules.market_open !== false,
    minimumPrice: positiveInteger(scoringRules.market_min_price, 1),
    releaseRefundPercent: boundedInteger(
      scoringRules.release_refund_percent,
      50,
      0,
      100,
    ),
    myTeam: teams.find((team) => team.id === myTeamId) ?? null,
    teams,
    freeAgents,
    offers,
    integrity,
  };
}

async function fetchMarketIntegrity(
  leagueId: string,
): Promise<MarketIntegrity | null> {
  if (!supabase) {
    return null;
  }

  const v4Response = await supabase.rpc(
    'get_league_market_integrity_v4',
    { p_league_id: leagueId },
  );

  if (
    !v4Response.error &&
    v4Response.data &&
    typeof v4Response.data === 'object'
  ) {
    return v4Response.data as MarketIntegrity;
  }

  const v3Response = await supabase.rpc(
    'get_league_market_integrity_v3',
    { p_league_id: leagueId },
  );

  if (
    !v3Response.error &&
    v3Response.data &&
    typeof v3Response.data === 'object'
  ) {
    return v3Response.data as MarketIntegrity;
  }

  const v2Response = await supabase.rpc(
    'get_league_market_integrity_v2',
    { p_league_id: leagueId },
  );

  if (
    !v2Response.error &&
    v2Response.data &&
    typeof v2Response.data === 'object'
  ) {
    return v2Response.data as MarketIntegrity;
  }

  const v1Response = await supabase.rpc(
    'get_league_market_integrity_v1',
    { p_league_id: leagueId },
  );

  // La diagnostica non deve rendere inutilizzabile il Mercato se lo script
  // Supabase non è stato ancora installato o se il controllo è temporaneamente
  // indisponibile. Le operazioni sensibili restano comunque protette dalle RPC.
  if (
    v1Response.error ||
    !v1Response.data ||
    typeof v1Response.data !== 'object'
  ) {
    return null;
  }

  return v1Response.data as MarketIntegrity;
}

export async function signFreeAgent(teamId: string, athleteId: string) {
  return callMarketRpc('sign_free_agent', {
    p_fantasy_team_id: teamId,
    p_athlete_id: athleteId,
  });
}

export async function releaseRosterPlayer(
  teamId: string,
  athleteId: string,
) {
  return callMarketRpc('release_roster_player', {
    p_fantasy_team_id: teamId,
    p_athlete_id: athleteId,
  });
}

export async function createTradeOffer(input: CreateTradeInput) {
  return callMarketRpc('create_trade_offer', {
    p_proposer_team_id: input.proposerTeamId,
    p_recipient_team_id: input.recipientTeamId,
    p_offered_player_ids: input.offeredPlayerIds,
    p_requested_player_ids: input.requestedPlayerIds,
    p_proposer_credits: input.proposerCredits,
    p_recipient_credits: input.recipientCredits,
    p_message: input.message?.trim() || null,
  });
}

export async function respondTradeOffer(
  tradeOfferId: string,
  accept: boolean,
) {
  return callMarketRpc('respond_trade_offer', {
    p_trade_offer_id: tradeOfferId,
    p_accept: accept,
  });
}

export async function cancelTradeOffer(tradeOfferId: string) {
  return callMarketRpc('cancel_trade_offer', {
    p_trade_offer_id: tradeOfferId,
  });
}

export function subscribeToMarket(
  leagueId: string,
  onChange: () => void,
) {
  if (!supabase) {
    return () => undefined;
  }
  const client = supabase;
  const channel = client
    .channel(`transfer-market-${leagueId}`)
    .on(
      'postgres_changes',
      {
        event: '*',
        schema: 'public',
        table: 'trade_offers',
        filter: `league_id=eq.${leagueId}`,
      },
      onChange,
    )
    .on(
      'postgres_changes',
      {
        event: '*',
        schema: 'public',
        table: 'trade_offer_players',
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
        event: 'UPDATE',
        schema: 'public',
        table: 'fantasy_teams',
        filter: `league_id=eq.${leagueId}`,
      },
      onChange,
    )
    .subscribe();

  return () => {
    void client.removeChannel(channel);
  };
}

async function callMarketRpc(
  functionName:
    | 'sign_free_agent'
    | 'release_roster_player'
    | 'create_trade_offer'
    | 'respond_trade_offer'
    | 'cancel_trade_offer',
  params: Record<string, unknown>,
): Promise<{ error?: string }> {
  if (!supabase) {
    return { error: 'Il collegamento al backend non è configurato.' };
  }

  const { error } = await supabase.rpc(functionName, params);
  return error ? { error: translateMarketError(error.message) } : {};
}

function translateMarketError(message: string) {
  const normalized = message.toLowerCase();
  if (
    normalized.includes('sign_free_agent') ||
    normalized.includes('release_roster_player') ||
    normalized.includes('trade_offer')
  ) {
    return 'Aggiorna prima il database LEGHEVO con il file 011.';
  }
  return message;
}

function comparePlayers(left: MarketPlayer, right: MarketPlayer) {
  return (
    roleOrder(left.role) - roleOrder(right.role) ||
    left.name.localeCompare(right.name)
  );
}

function roleOrder(role: string) {
  if (role === 'P' || role.includes('Por')) return 0;
  if (role === 'D' || role.startsWith('D')) return 1;
  if (role === 'C' || role === 'M') return 2;
  return 3;
}

function positiveInteger(value: unknown, fallback: number) {
  const number = Number(value);
  return Number.isInteger(number) && number > 0 ? number : fallback;
}

function boundedInteger(
  value: unknown,
  fallback: number,
  minimum: number,
  maximum: number,
) {
  const number = Number(value);
  return Number.isInteger(number)
    ? Math.min(Math.max(number, minimum), maximum)
    : fallback;
}

export function emptyDashboard(): MarketDashboard {
  return {
    marketOpen: true,
    minimumPrice: 1,
    releaseRefundPercent: 50,
    myTeam: null,
    teams: [],
    freeAgents: [],
    offers: [],
    integrity: null,
  };
}
