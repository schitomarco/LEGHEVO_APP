import { useCallback, useEffect, useState } from 'react';
import { demoRoster } from './useTeamRoster';
import {
  cancelTradeOffer,
  createTradeOffer,
  emptyDashboard,
  fetchMarketDashboard,
  releaseRosterPlayer,
  respondTradeOffer,
  signFreeAgent,
  subscribeToMarket,
  type CreateTradeInput,
} from '../services/marketService';
import type {
  LeagueSummary,
  MarketDashboard,
  MarketPlayer,
  TradeOfferSummary,
} from '../types';

const demoFreeAgents: MarketPlayer[] = [
  {
    id: 'demo-free-1',
    name: 'Fabio Bernardi',
    clubName: 'Verona Gialloblù',
    shirtNumber: 21,
    role: 'D',
    purchasePrice: 0,
    teamId: null,
  },
  {
    id: 'demo-free-2',
    name: 'Daniele Esposito',
    clubName: 'Napoli Azzurra',
    shirtNumber: 17,
    role: 'C',
    purchasePrice: 0,
    teamId: null,
  },
  {
    id: 'demo-free-3',
    name: 'Manuel Ferri',
    clubName: 'Parma Crociata',
    shirtNumber: 30,
    role: 'A',
    purchasePrice: 0,
    teamId: null,
  },
];

function createDemoDashboard(): MarketDashboard {
  const myPlayers = demoRoster.map((player) => ({
    ...player,
    teamId: 'demo-team',
  }));
  const rivalPlayers: MarketPlayer[] = [
    {
      id: 'demo-rival-1',
      name: 'Cristian Sala',
      clubName: 'Milano Rossonera',
      shirtNumber: 7,
      role: 'A',
      purchasePrice: 61,
      teamId: 'demo-team-2',
    },
    {
      id: 'demo-rival-2',
      name: 'Alberto Parisi',
      clubName: 'Roma Giallorossa',
      shirtNumber: 8,
      role: 'C',
      purchasePrice: 32,
      teamId: 'demo-team-2',
    },
  ];
  const teams = [
    {
      id: 'demo-team',
      name: 'Diavoli del Sud',
      creditsRemaining: 412,
      players: myPlayers,
    },
    {
      id: 'demo-team-2',
      name: 'Tiki Taka Boom',
      creditsRemaining: 365,
      players: rivalPlayers,
    },
    {
      id: 'demo-team-3',
      name: 'Atletico Ma Non Troppo',
      creditsRemaining: 389,
      players: [
        {
          id: 'demo-rival-3',
          name: 'Lorenzo Ricci',
          clubName: 'Torino Granata',
          shirtNumber: 10,
          role: 'A',
          purchasePrice: 48,
          teamId: 'demo-team-3',
        },
      ],
    },
  ];

  return {
    marketOpen: true,
    minimumPrice: 1,
    releaseRefundPercent: 50,
    myTeam: teams[0],
    teams,
    freeAgents: demoFreeAgents,
    offers: [],
    integrity: null,
  };
}

export function useTransferMarket(league: LeagueSummary | null) {
  const isDemo = Boolean(league?.isDemo);
  const [dashboard, setDashboard] = useState<MarketDashboard>(() =>
    isDemo ? createDemoDashboard() : emptyDashboard(),
  );
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');

  const refresh = useCallback(async () => {
    if (!league?.team?.id) {
      setDashboard(isDemo ? createDemoDashboard() : emptyDashboard());
      setLoading(false);
      return;
    }
    if (isDemo) {
      setLoading(false);
      return;
    }

    setLoading(true);
    try {
      setDashboard(
        await fetchMarketDashboard(
          league.id,
          league.team.id,
          league.mode,
        ),
      );
      setError('');
    } catch {
      setError('Il mercato non risponde. Il procuratore ha spento il telefono.');
    } finally {
      setLoading(false);
    }
  }, [isDemo, league]);

  useEffect(() => {
    void refresh();
  }, [refresh]);

  useEffect(() => {
    if (!league || isDemo) {
      return;
    }
    return subscribeToMarket(league.id, () => void refresh());
  }, [isDemo, league, refresh]);

  const sign = async (athleteId: string) => {
    if (!dashboard.myTeam) {
      return { error: 'Squadra non disponibile.' };
    }
    if (isDemo) {
      const candidate = dashboard.freeAgents.find(
        (player) => player.id === athleteId,
      );
      if (!candidate) {
        return { error: 'Calciatore non più disponibile.' };
      }
      if (dashboard.myTeam.creditsRemaining < dashboard.minimumPrice) {
        return { error: 'Crediti insufficienti.' };
      }
      setDashboard((current) => {
        const teams = current.teams.map((team) =>
          team.id === current.myTeam?.id
            ? {
                ...team,
                creditsRemaining:
                  team.creditsRemaining - current.minimumPrice,
                players: [
                  ...team.players,
                  {
                    ...candidate,
                    teamId: team.id,
                    purchasePrice: current.minimumPrice,
                  },
                ],
              }
            : team,
        );
        return {
          ...current,
          teams,
          myTeam:
            teams.find((team) => team.id === current.myTeam?.id) ?? null,
          freeAgents: current.freeAgents.filter(
            (player) => player.id !== athleteId,
          ),
        };
      });
      return {};
    }

    const outcome = await signFreeAgent(dashboard.myTeam.id, athleteId);
    if (!outcome.error) {
      await refresh();
    }
    return outcome;
  };

  const release = async (athleteId: string) => {
    if (!dashboard.myTeam) {
      return { error: 'Squadra non disponibile.' };
    }
    if (isDemo) {
      const player = dashboard.myTeam.players.find(
        (item) => item.id === athleteId,
      );
      if (!player) {
        return { error: 'Calciatore non presente in rosa.' };
      }
      const refund = Math.floor(
        (player.purchasePrice * dashboard.releaseRefundPercent) / 100,
      );
      setDashboard((current) => {
        const teams = current.teams.map((team) =>
          team.id === current.myTeam?.id
            ? {
                ...team,
                creditsRemaining: team.creditsRemaining + refund,
                players: team.players.filter(
                  (item) => item.id !== athleteId,
                ),
              }
            : team,
        );
        return {
          ...current,
          teams,
          myTeam:
            teams.find((team) => team.id === current.myTeam?.id) ?? null,
          freeAgents: [
            ...current.freeAgents,
            { ...player, teamId: null, purchasePrice: 0 },
          ],
          offers: current.offers.map((offer) =>
            offer.offeredPlayers.some((item) => item.id === athleteId) ||
            offer.requestedPlayers.some((item) => item.id === athleteId)
              ? { ...offer, status: 'canceled' }
              : offer,
          ),
        };
      });
      return {};
    }

    const outcome = await releaseRosterPlayer(
      dashboard.myTeam.id,
      athleteId,
    );
    if (!outcome.error) {
      await refresh();
    }
    return outcome;
  };

  const propose = async (
    input: Omit<CreateTradeInput, 'proposerTeamId'>,
  ) => {
    if (!dashboard.myTeam) {
      return { error: 'Squadra non disponibile.' };
    }
    const completeInput = {
      ...input,
      proposerTeamId: dashboard.myTeam.id,
    };

    if (isDemo) {
      const recipient = dashboard.teams.find(
        (team) => team.id === input.recipientTeamId,
      );
      if (!recipient) {
        return { error: 'Squadra destinataria non trovata.' };
      }
      const offer: TradeOfferSummary = {
        id: `demo-offer-${Date.now()}`,
        proposerTeamId: dashboard.myTeam.id,
        proposerTeamName: dashboard.myTeam.name,
        recipientTeamId: recipient.id,
        recipientTeamName: recipient.name,
        status: 'pending',
        proposerCredits: input.proposerCredits,
        recipientCredits: input.recipientCredits,
        offeredPlayers: dashboard.myTeam.players.filter((player) =>
          input.offeredPlayerIds.includes(player.id),
        ),
        requestedPlayers: recipient.players.filter((player) =>
          input.requestedPlayerIds.includes(player.id),
        ),
        message: input.message?.trim() || null,
        createdAt: new Date().toISOString(),
        expiresAt: new Date(
          Date.now() + 7 * 24 * 60 * 60 * 1000,
        ).toISOString(),
      };
      setDashboard((current) => ({
        ...current,
        offers: [offer, ...current.offers],
      }));
      return {};
    }

    const outcome = await createTradeOffer(completeInput);
    if (!outcome.error) {
      await refresh();
    }
    return outcome;
  };

  const respond = async (offerId: string, accept: boolean) => {
    if (isDemo) {
      setDashboard((current) => ({
        ...current,
        offers: current.offers.map((offer) =>
          offer.id === offerId
            ? { ...offer, status: accept ? 'accepted' : 'declined' }
            : offer,
        ),
      }));
      return {};
    }
    const outcome = await respondTradeOffer(offerId, accept);
    if (!outcome.error) {
      await refresh();
    }
    return outcome;
  };

  const cancel = async (offerId: string) => {
    if (isDemo) {
      setDashboard((current) => ({
        ...current,
        offers: current.offers.map((offer) =>
          offer.id === offerId
            ? { ...offer, status: 'canceled' }
            : offer,
        ),
      }));
      return {};
    }
    const outcome = await cancelTradeOffer(offerId);
    if (!outcome.error) {
      await refresh();
    }
    return outcome;
  };

  return {
    dashboard,
    loading,
    error,
    refresh,
    sign,
    release,
    propose,
    respond,
    cancel,
  };
}
