import type { RealtimeChannel } from '@supabase/supabase-js';
import { supabase } from '../lib/supabase';
import type { LeagueMode } from '../types';

export type BidRecord = {
  id: string;
  auction_item_id: string;
  fantasy_team_id: string;
  amount: number;
  created_at: string;
};

export type AuctionAthlete = {
  id: string;
  name: string;
  clubName: string;
  shirtNumber: number | null;
  positionCode: string | null;
  role: string;
};

export type AuctionCandidate = AuctionAthlete;
export type AuctionControlAction =
  | 'pause'
  | 'resume'
  | 'cancel_item'
  | 'complete';

export type AuctionIntegrity = {
  version: number;
  safetyEnabled: boolean;
  leagueId: string;
  checkedAt: string;
  ok: boolean;
  issueCount: number;
  openAuctions: number;
  biddingItems: number;
  orphanCurrentItems: number;
  orphanBiddingItems: number;
  invalidWinners: number;
  invalidBidSequences: number;
};

export type AuctionState = {
  integrity: AuctionIntegrity | null;
  auction: {
    id: string;
    status: 'scheduled' | 'live' | 'paused' | 'completed';
    bidIncrement: number;
    bidSeconds: number;
  } | null;
  currentItem: {
    id: string;
    status: 'queued' | 'bidding' | 'sold' | 'unsold';
    openingPrice: number;
    expiresAt: string | null;
    athlete: AuctionAthlete;
    highestBid: number | null;
    highestBidTeamId: string | null;
    highestBidTeamName: string | null;
  } | null;
  myTeam: {
    id: string;
    name: string;
    creditsRemaining: number;
    rosterCount: number;
  } | null;
};

type AthleteRow = {
  id: string;
  first_name: string | null;
  last_name: string;
  club_name: string;
  shirt_number: number | null;
  position_code: string | null;
};

type RoleRow = {
  athlete_id: string;
  role_code: string;
};

export async function fetchAuctionState(
  leagueId: string,
  userId: string,
  mode: LeagueMode,
): Promise<AuctionState> {
  if (!supabase) {
    return { auction: null, currentItem: null, myTeam: null, integrity: null };
  }

  const { data: teamData, error: teamError } = await supabase
    .from('fantasy_teams')
    .select('id, name, credits_remaining')
    .eq('league_id', leagueId)
    .eq('manager_id', userId)
    .maybeSingle();

  if (teamError) {
    throw teamError;
  }

  let rosterCount = 0;
  if (teamData) {
    const { count, error: rosterError } = await supabase
      .from('roster_entries')
      .select('id', { count: 'exact', head: true })
      .eq('fantasy_team_id', teamData.id)
      .is('released_at', null);

    if (rosterError) {
      throw rosterError;
    }
    rosterCount = count ?? 0;
  }

  const integrity = await fetchAuctionIntegrity(leagueId);

  const myTeam = teamData
    ? {
        id: teamData.id,
        name: teamData.name,
        creditsRemaining: teamData.credits_remaining,
        rosterCount,
      }
    : null;

  const { data: auctionData, error: auctionError } = await supabase
    .from('auctions')
    .select(
      'id, status, current_item_id, bid_increment, bid_seconds, created_at',
    )
    .eq('league_id', leagueId)
    .neq('status', 'completed')
    .order('created_at', { ascending: false })
    .limit(1)
    .maybeSingle();

  if (auctionError) {
    throw auctionError;
  }

  if (!auctionData) {
    return { auction: null, currentItem: null, myTeam, integrity };
  }

  const auction = {
    id: auctionData.id,
    status: auctionData.status as NonNullable<
      AuctionState['auction']
    >['status'],
    bidIncrement: auctionData.bid_increment,
    bidSeconds: auctionData.bid_seconds,
  };

  if (!auctionData.current_item_id) {
    return { auction, currentItem: null, myTeam, integrity };
  }

  const { data: itemData, error: itemError } = await supabase
    .from('auction_items')
    .select('id, athlete_id, status, opening_price, expires_at')
    .eq('id', auctionData.current_item_id)
    .single();

  if (itemError) {
    throw itemError;
  }

  const [athleteResponse, rolesResponse, bidsResponse] = await Promise.all([
    supabase
      .from('athletes')
      .select(
        'id, first_name, last_name, club_name, shirt_number, position_code',
      )
      .eq('id', itemData.athlete_id)
      .single(),
    supabase
      .from('athlete_roles')
      .select('athlete_id, role_code')
      .eq('athlete_id', itemData.athlete_id)
      .eq('mode', mode),
    supabase
      .from('bids')
      .select('id, auction_item_id, fantasy_team_id, amount, created_at')
      .eq('auction_item_id', itemData.id)
      .order('amount', { ascending: false })
      .order('created_at', { ascending: true })
      .limit(1),
  ]);

  if (athleteResponse.error) {
    throw athleteResponse.error;
  }
  if (rolesResponse.error) {
    throw rolesResponse.error;
  }
  if (bidsResponse.error) {
    throw bidsResponse.error;
  }

  const athleteRow = athleteResponse.data as AthleteRow;
  const roles = (rolesResponse.data ?? []) as RoleRow[];
  const highestBid = (bidsResponse.data?.[0] ?? null) as BidRecord | null;
  let highestBidTeamName: string | null = null;

  if (highestBid) {
    const { data: highestTeam, error: highestTeamError } = await supabase
      .from('fantasy_teams')
      .select('name')
      .eq('id', highestBid.fantasy_team_id)
      .single();

    if (highestTeamError) {
      throw highestTeamError;
    }
    highestBidTeamName = highestTeam.name;
  }

  return {
    auction,
    integrity,
    currentItem: {
      id: itemData.id,
      status: itemData.status,
      openingPrice: itemData.opening_price,
      expiresAt: itemData.expires_at,
      athlete: mapAthlete(athleteRow, roles),
      highestBid: highestBid?.amount ?? null,
      highestBidTeamId: highestBid?.fantasy_team_id ?? null,
      highestBidTeamName,
    },
    myTeam,
  };
}

export async function fetchAuctionCandidates(
  leagueId: string,
  mode: LeagueMode,
): Promise<AuctionCandidate[]> {
  if (!supabase) {
    return [];
  }

  const [athletesResponse, rolesResponse, rosterResponse] = await Promise.all([
    supabase
      .from('athletes')
      .select(
        'id, first_name, last_name, club_name, shirt_number, position_code',
      )
      .eq('active', true)
      .order('last_name', { ascending: true })
      .limit(200),
    supabase
      .from('athlete_roles')
      .select('athlete_id, role_code')
      .eq('mode', mode),
    supabase
      .from('roster_entries')
      .select('athlete_id')
      .eq('league_id', leagueId)
      .is('released_at', null),
  ]);

  if (athletesResponse.error) {
    throw athletesResponse.error;
  }
  if (rolesResponse.error) {
    throw rolesResponse.error;
  }
  if (rosterResponse.error) {
    throw rosterResponse.error;
  }

  const athletes = (athletesResponse.data ?? []) as AthleteRow[];
  const roles = (rolesResponse.data ?? []) as RoleRow[];
  const unavailable = new Set(
    (rosterResponse.data ?? []).map((item) => item.athlete_id),
  );

  return athletes
    .filter(
      (athlete) =>
        !unavailable.has(athlete.id) &&
        roles.some((role) => role.athlete_id === athlete.id),
    )
    .map((athlete) =>
      mapAthlete(
        athlete,
        roles.filter((role) => role.athlete_id === athlete.id),
      ),
    );
}


async function fetchAuctionIntegrity(
  leagueId: string,
): Promise<AuctionIntegrity | null> {
  if (!supabase) {
    return null;
  }

  const { data, error } = await supabase.rpc(
    'get_league_auction_integrity_v1',
    { p_league_id: leagueId },
  );

  // La diagnostica non deve bloccare la stanza se la migrazione non è ancora
  // installata. Le operazioni restano protette direttamente dalle RPC.
  if (error || !data || typeof data !== 'object') {
    return null;
  }

  return data as AuctionIntegrity;
}

export async function createAuctionRoom(
  leagueId: string,
  bidIncrement: number,
  bidSeconds: number,
) {
  requireBackend();
  const { data, error } = await supabase!.rpc('create_or_get_auction', {
    p_league_id: leagueId,
    p_bid_increment: bidIncrement,
    p_bid_seconds: bidSeconds,
  });

  if (error) {
    throw new Error(translateAuctionError(error.message));
  }
  return data;
}

export async function configureAuction(
  auctionId: string,
  bidIncrement: number,
  bidSeconds: number,
) {
  requireBackend();
  const { data, error } = await supabase!.rpc('configure_auction', {
    p_auction_id: auctionId,
    p_bid_increment: bidIncrement,
    p_bid_seconds: bidSeconds,
  });

  if (error) {
    throw new Error(translateAuctionError(error.message));
  }
  return data;
}

export async function controlAuction(
  auctionId: string,
  action: AuctionControlAction,
) {
  requireBackend();
  const { data, error } = await supabase!.rpc('control_auction', {
    p_auction_id: auctionId,
    p_action: action,
  });

  if (error) {
    throw new Error(translateAuctionError(error.message));
  }
  return data;
}

export async function nominatePlayer(
  auctionId: string,
  athleteId: string,
  openingPrice = 1,
) {
  requireBackend();
  const { data, error } = await supabase!.rpc('nominate_auction_player', {
    p_auction_id: auctionId,
    p_athlete_id: athleteId,
    p_opening_price: openingPrice,
  });

  if (error) {
    throw new Error(translateAuctionError(error.message));
  }
  return data;
}

export async function submitBid(auctionItemId: string, amount: number) {
  requireBackend();
  const { data, error } = await supabase!.rpc('place_bid', {
    p_auction_item_id: auctionItemId,
    p_amount: amount,
  });

  if (error) {
    throw new Error(translateAuctionError(error.message));
  }

  return (Array.isArray(data) ? data[0] : data) as BidRecord;
}

export async function finalizeAuctionItem(auctionItemId: string) {
  requireBackend();
  const { data, error } = await supabase!.rpc('finalize_auction_item', {
    p_auction_item_id: auctionItemId,
  });

  if (error) {
    throw new Error(translateAuctionError(error.message));
  }
  return data;
}

export function subscribeToAuction(
  leagueId: string,
  auctionId: string,
  currentItemId: string | null,
  onChange: () => void,
) {
  if (!supabase) {
    return () => undefined;
  }

  const client = supabase;
  let channel: RealtimeChannel = client
    .channel(`league-auction-${leagueId}-${auctionId}-${currentItemId ?? 'idle'}`)
    .on(
      'postgres_changes',
      {
        event: '*',
        schema: 'public',
        table: 'auctions',
        filter: `league_id=eq.${leagueId}`,
      },
      onChange,
    )
    .on(
      'postgres_changes',
      {
        event: '*',
        schema: 'public',
        table: 'auction_items',
        filter: `auction_id=eq.${auctionId}`,
      },
      onChange,
    );

  if (currentItemId) {
    channel = channel.on(
      'postgres_changes',
      {
        event: 'INSERT',
        schema: 'public',
        table: 'bids',
        filter: `auction_item_id=eq.${currentItemId}`,
      },
      onChange,
    );
  }

  channel.subscribe();

  return () => {
    void client.removeChannel(channel);
  };
}

function mapAthlete(athlete: AthleteRow, roles: RoleRow[]): AuctionAthlete {
  const fullName = [athlete.first_name, athlete.last_name]
    .filter(Boolean)
    .join(' ');

  return {
    id: athlete.id,
    name: fullName || athlete.last_name,
    clubName: athlete.club_name,
    shirtNumber: athlete.shirt_number,
    positionCode: athlete.position_code,
    role: roles.map((item) => item.role_code).join('/') || '—',
  };
}

function requireBackend() {
  if (!supabase) {
    throw new Error('Backend non configurato.');
  }
}

function translateAuctionError(message: string) {
  const normalized = message.toLowerCase();

  if (normalized.includes('function') && normalized.includes('does not exist')) {
    return 'Aggiorna prima il database LEGHEVO con il file 068.';
  }
  if (normalized.includes('tempo scaduto')) {
    return 'Tempo scaduto. Il VAR conferma.';
  }
  if (normalized.includes('crediti insufficienti')) {
    return 'Crediti insufficienti. Il bilancio piange.';
  }
  if (normalized.includes('offerta massima')) {
    return message;
  }
  if (normalized.includes('solo il presidente')) {
    return 'Questa operazione spetta al presidente della lega.';
  }

  return message;
}
