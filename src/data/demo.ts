import type { PlayerLiveScore } from '../types';

export const livePlayers: PlayerLiveScore[] = [
  { id: '1', role: 'P', name: 'A. Romano', status: 'Terminata', score: '6,0' },
  {
    id: '2',
    role: 'D',
    name: 'L. Conti',
    status: 'Gol +3',
    score: '9,5',
    highlighted: true,
  },
  {
    id: '3',
    role: 'C',
    name: 'M. Riva',
    status: "In campo · 71'",
    score: '6,5',
  },
  {
    id: '4',
    role: 'A',
    name: 'R. Silva',
    status: 'Assist +1',
    score: '7,5',
    highlighted: true,
  },
];

export const standings = [
  { position: 1, name: 'Tiki Taka FC', points: 15 },
  { position: 2, name: 'Diavoli del Sud', points: 13, current: true },
  { position: 3, name: 'Real Madrink', points: 12 },
  { position: 4, name: 'Atletico Ma Non Troppo', points: 10 },
];
