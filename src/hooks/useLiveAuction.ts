import { useCallback, useEffect, useState } from 'react';
import {
  configureAuction,
  controlAuction,
  createAuctionRoom,
  fetchAuctionCandidates,
  fetchAuctionState,
  finalizeAuctionItem,
  nominatePlayer,
  submitBid,
  subscribeToAuction,
  type AuctionControlAction,
  type AuctionCandidate,
  type AuctionState,
} from '../services/auctionService';
import type { LeagueSummary } from '../types';

function createDemoState(): AuctionState {
  return {
    integrity: {
      version: 1,
      safetyEnabled: true,
      leagueId: 'demo-league',
      checkedAt: new Date().toISOString(),
      ok: true,
      issueCount: 0,
      openAuctions: 1,
      biddingItems: 1,
      orphanCurrentItems: 0,
      orphanBiddingItems: 0,
      invalidWinners: 0,
      invalidBidSequences: 0,
    },
    auction: {
      id: 'demo-auction',
      status: 'live',
      bidIncrement: 1,
      bidSeconds: 15,
    },
    currentItem: {
      id: 'demo-auction-item',
      status: 'bidding',
      openingPrice: 32,
      expiresAt: new Date(Date.now() + 60_000).toISOString(),
      athlete: {
        id: 'demo-athlete',
        name: 'Riccardo Silva',
        clubName: 'Milano Nerazzurra',
        shirtNumber: 9,
        positionCode: 'Attacker',
        role: 'A',
      },
      highestBid: 68,
      highestBidTeamId: 'demo-team-2',
      highestBidTeamName: 'Tiki Taka Boom',
    },
    myTeam: {
      id: 'demo-team',
      name: 'Diavoli del Sud',
      creditsRemaining: 412,
      rosterCount: 14,
    },
  };
}

export function useLiveAuction(
  league: LeagueSummary | null,
  userId: string | null,
) {
  const isDemo = Boolean(league?.isDemo);
  const [state, setState] = useState<AuctionState>(() => createDemoState());
  const [candidates, setCandidates] = useState<AuctionCandidate[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');

  const refresh = useCallback(async () => {
    if (!league || !userId) {
      if (isDemo) {
        setLoading(false);
      } else {
        setState({
          auction: null,
          currentItem: null,
          myTeam: null,
          integrity: null,
        });
        setCandidates([]);
        setLoading(false);
      }
      return;
    }

    if (isDemo) {
      setLoading(false);
      return;
    }

    setLoading(true);
    try {
      const nextState = await fetchAuctionState(
        league.id,
        userId,
        league.mode,
      );
      setState(nextState);
      setError('');

      if (nextState.auction && !nextState.currentItem) {
        setCandidates(
          await fetchAuctionCandidates(league.id, league.mode),
        );
      } else {
        setCandidates([]);
      }
    } catch {
      setError('La stanza asta non risponde. Qualcuno ha staccato il Wi-Fi.');
    } finally {
      setLoading(false);
    }
  }, [isDemo, league, userId]);

  useEffect(() => {
    void refresh();
  }, [refresh]);

  useEffect(() => {
    if (
      isDemo ||
      !league ||
      !state.auction
    ) {
      return;
    }

    return subscribeToAuction(
      league.id,
      state.auction.id,
      state.currentItem?.id ?? null,
      () => void refresh(),
    );
  }, [
    isDemo,
    league,
    refresh,
    state.auction?.id,
    state.currentItem?.id,
  ]);

  const openRoom = async (bidIncrement: number, bidSeconds: number) => {
    if (!league || isDemo) {
      return { error: 'La stanza demo è già aperta.' };
    }
    try {
      await createAuctionRoom(league.id, bidIncrement, bidSeconds);
      await refresh();
      return {};
    } catch (caught) {
      return { error: messageFrom(caught) };
    }
  };

  const configure = async (bidIncrement: number, bidSeconds: number) => {
    if (!state.auction) {
      return { error: 'Nessuna stanza asta disponibile.' };
    }

    if (isDemo) {
      setState((current) => ({
        ...current,
        auction: current.auction
          ? { ...current.auction, bidIncrement, bidSeconds }
          : null,
      }));
      return {};
    }

    try {
      await configureAuction(state.auction.id, bidIncrement, bidSeconds);
      await refresh();
      return {};
    } catch (caught) {
      return { error: messageFrom(caught) };
    }
  };

  const control = async (action: AuctionControlAction) => {
    if (!state.auction) {
      return { error: 'Nessuna stanza asta disponibile.' };
    }

    if (isDemo) {
      setState((current) => {
        if (action === 'complete') {
          return { ...current, auction: null, currentItem: null };
        }
        if (action === 'cancel_item') {
          return { ...current, currentItem: null };
        }
        return {
          ...current,
          auction: current.auction
            ? {
                ...current.auction,
                status: action === 'pause' ? 'paused' : 'live',
              }
            : null,
          currentItem: current.currentItem
            ? {
                ...current.currentItem,
                expiresAt:
                  action === 'pause'
                    ? null
                    : new Date(
                        Date.now() +
                          (current.auction?.bidSeconds ?? 15) * 1000,
                      ).toISOString(),
              }
            : null,
        };
      });
      return {};
    }

    try {
      await controlAuction(state.auction.id, action);
      await refresh();
      return {};
    } catch (caught) {
      return { error: messageFrom(caught) };
    }
  };

  const nominate = async (athleteId: string) => {
    if (!state.auction || isDemo) {
      return { error: 'Nessuna stanza asta disponibile.' };
    }
    try {
      await nominatePlayer(state.auction.id, athleteId);
      await refresh();
      return {};
    } catch (caught) {
      return { error: messageFrom(caught) };
    }
  };

  const bid = async (amount: number) => {
    if (!state.currentItem) {
      return { error: 'Nessun calciatore è attualmente all’asta.' };
    }

    if (isDemo) {
      setState((current) => ({
        ...current,
        currentItem: current.currentItem
          ? {
              ...current.currentItem,
              highestBid: amount,
              highestBidTeamId: current.myTeam?.id ?? null,
              highestBidTeamName: current.myTeam?.name ?? null,
              expiresAt: new Date(
                Date.now() + (current.auction?.bidSeconds ?? 15) * 1000,
              ).toISOString(),
            }
          : null,
      }));
      return {};
    }

    try {
      await submitBid(state.currentItem.id, amount);
      await refresh();
      return {};
    } catch (caught) {
      return { error: messageFrom(caught) };
    }
  };

  const finalize = async () => {
    if (!state.currentItem || isDemo) {
      return { error: 'Questa assegnazione è disponibile nella lega reale.' };
    }
    try {
      await finalizeAuctionItem(state.currentItem.id);
      await refresh();
      return {};
    } catch (caught) {
      return { error: messageFrom(caught) };
    }
  };

  return {
    state,
    candidates,
    loading,
    error,
    refresh,
    openRoom,
    configure,
    control,
    nominate,
    bid,
    finalize,
  };
}

function messageFrom(caught: unknown) {
  return caught instanceof Error
    ? caught.message
    : 'Operazione non riuscita. Il presidente sta indagando.';
}
