import { useCallback, useEffect, useState } from 'react';
import { fetchPlayerDirectory } from '../services/playerDirectoryService';
import type { LeagueSummary, PlayerDirectoryItem } from '../types';

const demoPlayers: PlayerDirectoryItem[] = [
  {
    id: 'demo-player-1',
    name: 'Lorenzo Ricci',
    clubName: 'Milano Rossonera',
    shirtNumber: 10,
    role: 'A',
    teamId: 'demo-team',
    teamName: 'Diavoli del Sud',
    purchasePrice: 48,
    appearances: 7,
    averageRating: 6.71,
    averageFantasyScore: 8.21,
    goals: 4,
    assists: 2,
    yellowCards: 1,
    redCards: 0,
    lastScores: [10, 6.5, 9.5, 6, 9],
  },
  {
    id: 'demo-player-2',
    name: 'Cristian Sala',
    clubName: 'Torino Granata',
    shirtNumber: 7,
    role: 'A',
    teamId: 'demo-team-2',
    teamName: 'Tiki Taka Boom',
    purchasePrice: 61,
    appearances: 7,
    averageRating: 6.43,
    averageFantasyScore: 7.36,
    goals: 3,
    assists: 1,
    yellowCards: 0,
    redCards: 0,
    lastScores: [6, 9.5, 5.5, 10, 6],
  },
  {
    id: 'demo-player-3',
    name: 'Alberto Parisi',
    clubName: 'Roma Giallorossa',
    shirtNumber: 8,
    role: 'C',
    teamId: 'demo-team-2',
    teamName: 'Tiki Taka Boom',
    purchasePrice: 32,
    appearances: 6,
    averageRating: 6.33,
    averageFantasyScore: 6.83,
    goals: 1,
    assists: 3,
    yellowCards: 2,
    redCards: 0,
    lastScores: [7, 6.5, 8, 5.5, 7],
  },
  {
    id: 'demo-player-4',
    name: 'Matteo Leone',
    clubName: 'Napoli Azzurra',
    shirtNumber: 1,
    role: 'P',
    teamId: 'demo-team',
    teamName: 'Diavoli del Sud',
    purchasePrice: 14,
    appearances: 7,
    averageRating: 6.14,
    averageFantasyScore: 5.71,
    goals: 0,
    assists: 0,
    yellowCards: 0,
    redCards: 0,
    lastScores: [6, 5, 7, 5.5, 5.5],
  },
  {
    id: 'demo-player-5',
    name: 'Davide Greco',
    clubName: 'Bologna Rossoblù',
    shirtNumber: 4,
    role: 'D',
    teamId: 'demo-team',
    teamName: 'Diavoli del Sud',
    purchasePrice: 22,
    appearances: 7,
    averageRating: 6.29,
    averageFantasyScore: 6.36,
    goals: 1,
    assists: 0,
    yellowCards: 2,
    redCards: 0,
    lastScores: [6.5, 6, 9, 5.5, 5.5],
  },
  {
    id: 'demo-player-6',
    name: 'Fabio Bernardi',
    clubName: 'Verona Gialloblù',
    shirtNumber: 21,
    role: 'D',
    teamId: null,
    teamName: null,
    purchasePrice: null,
    appearances: 5,
    averageRating: 6.1,
    averageFantasyScore: 6,
    goals: 0,
    assists: 1,
    yellowCards: 1,
    redCards: 0,
    lastScores: [6, 6.5, 5.5, 6, 6],
  },
  {
    id: 'demo-player-7',
    name: 'Daniele Esposito',
    clubName: 'Napoli Azzurra',
    shirtNumber: 17,
    role: 'C',
    teamId: null,
    teamName: null,
    purchasePrice: null,
    appearances: 6,
    averageRating: 6.42,
    averageFantasyScore: 6.75,
    goals: 1,
    assists: 2,
    yellowCards: 1,
    redCards: 0,
    lastScores: [6.5, 7.5, 6, 8, 5.5],
  },
  {
    id: 'demo-player-8',
    name: 'Manuel Ferri',
    clubName: 'Parma Crociata',
    shirtNumber: 30,
    role: 'A',
    teamId: null,
    teamName: null,
    purchasePrice: null,
    appearances: 4,
    averageRating: 6.25,
    averageFantasyScore: 7.13,
    goals: 2,
    assists: 0,
    yellowCards: 0,
    redCards: 0,
    lastScores: [9.5, 6, 7, 6],
  },
  {
    id: 'demo-player-9',
    name: 'Simone De Luca',
    clubName: 'Firenze Viola',
    shirtNumber: 6,
    role: 'D',
    teamId: 'demo-team-3',
    teamName: 'Atletico Ma Non Troppo',
    purchasePrice: 18,
    appearances: 7,
    averageRating: 6.07,
    averageFantasyScore: 5.93,
    goals: 0,
    assists: 0,
    yellowCards: 2,
    redCards: 1,
    lastScores: [6, 5.5, 4, 6.5, 6],
  },
  {
    id: 'demo-player-10',
    name: 'Nicolò Conti',
    clubName: 'Lazio Celeste',
    shirtNumber: 11,
    role: 'C',
    teamId: 'demo-team',
    teamName: 'Diavoli del Sud',
    purchasePrice: 37,
    appearances: 7,
    averageRating: 6.5,
    averageFantasyScore: 7.21,
    goals: 2,
    assists: 3,
    yellowCards: 1,
    redCards: 0,
    lastScores: [7.5, 9, 6.5, 7, 6],
  },
];

export function usePlayerDirectory(league: LeagueSummary | null) {
  const isDemo = Boolean(league?.isDemo);
  const [players, setPlayers] = useState<PlayerDirectoryItem[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');

  const refresh = useCallback(async () => {
    if (!league) {
      setPlayers([]);
      setError('');
      setLoading(false);
      return;
    }
    if (isDemo) {
      setPlayers(demoPlayers);
      setError('');
      setLoading(false);
      return;
    }

    setLoading(true);
    try {
      setPlayers(await fetchPlayerDirectory(league.id));
      setError('');
    } catch (cause) {
      setError(
        cause instanceof Error
          ? cause.message
          : 'L’archivio calciatori non risponde.',
      );
    } finally {
      setLoading(false);
    }
  }, [isDemo, league]);

  useEffect(() => {
    void refresh();
  }, [refresh]);

  return { players, loading, error, refresh };
}
