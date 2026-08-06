import { useCallback, useEffect, useState } from 'react';
import { fetchTeamRoster } from '../services/rosterService';
import type { LeagueMode, RosterPlayer } from '../types';

export const demoRoster: RosterPlayer[] = [
  {
    id: 'demo-p-1',
    name: 'Andrea Romano',
    clubName: 'Torino Granata',
    shirtNumber: 1,
    role: 'P',
    purchasePrice: 18,
  },
  {
    id: 'demo-p-2',
    name: 'Michele Rizzi',
    clubName: 'Roma Giallorossa',
    shirtNumber: 22,
    role: 'P',
    purchasePrice: 3,
  },
  {
    id: 'demo-d-1',
    name: 'Luca Conti',
    clubName: 'Milano Rossonera',
    shirtNumber: 2,
    role: 'D',
    purchasePrice: 21,
  },
  {
    id: 'demo-d-2',
    name: 'Davide Serra',
    clubName: 'Roma Giallorossa',
    shirtNumber: 4,
    role: 'D',
    purchasePrice: 16,
  },
  {
    id: 'demo-d-3',
    name: 'Nicolò Greco',
    clubName: 'Bergamo Nerazzurra',
    shirtNumber: 5,
    role: 'D',
    purchasePrice: 27,
  },
  {
    id: 'demo-d-4',
    name: 'Matteo Villa',
    clubName: 'Bologna Rossoblù',
    shirtNumber: 3,
    role: 'D',
    purchasePrice: 12,
  },
  {
    id: 'demo-d-5',
    name: 'Simone Gallo',
    clubName: 'Lecce Giallorossa',
    shirtNumber: 13,
    role: 'D',
    purchasePrice: 8,
  },
  {
    id: 'demo-c-1',
    name: 'Marco Riva',
    clubName: 'Bologna Rossoblù',
    shirtNumber: 8,
    role: 'C',
    purchasePrice: 34,
  },
  {
    id: 'demo-c-2',
    name: 'Tommaso Leone',
    clubName: 'Napoli Azzurra',
    shirtNumber: 10,
    role: 'C',
    purchasePrice: 47,
  },
  {
    id: 'demo-c-3',
    name: 'Samuele Fiore',
    clubName: 'Firenze Viola',
    shirtNumber: 7,
    role: 'C',
    purchasePrice: 29,
  },
  {
    id: 'demo-c-4',
    name: 'Gabriele Costa',
    clubName: 'Lecce Giallorossa',
    shirtNumber: 6,
    role: 'C',
    purchasePrice: 11,
  },
  {
    id: 'demo-a-1',
    name: 'Riccardo Silva',
    clubName: 'Milano Nerazzurra',
    shirtNumber: 9,
    role: 'A',
    purchasePrice: 68,
  },
  {
    id: 'demo-a-2',
    name: 'Edoardo Marini',
    clubName: 'Torino Bianconera',
    shirtNumber: 11,
    role: 'A',
    purchasePrice: 55,
  },
  {
    id: 'demo-a-3',
    name: 'Pietro Moretti',
    clubName: 'Lazio Biancoceleste',
    shirtNumber: 18,
    role: 'A',
    purchasePrice: 41,
  },
  {
    id: 'demo-a-4',
    name: 'Alessio De Luca',
    clubName: 'Genova Blucerchiata',
    shirtNumber: 19,
    role: 'A',
    purchasePrice: 22,
  },
];

export function useTeamRoster(
  fantasyTeamId: string | null,
  mode: LeagueMode,
  isDemo: boolean,
) {
  const [players, setPlayers] = useState<RosterPlayer[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');

  const refresh = useCallback(async () => {
    if (isDemo) {
      setPlayers(demoRoster);
      setError('');
      setLoading(false);
      return;
    }

    if (!fantasyTeamId) {
      setPlayers([]);
      setError('');
      setLoading(false);
      return;
    }

    setLoading(true);
    try {
      setPlayers(await fetchTeamRoster(fantasyTeamId, mode));
      setError('');
    } catch {
      setError('La distinta della rosa non è disponibile.');
    } finally {
      setLoading(false);
    }
  }, [fantasyTeamId, isDemo, mode]);

  useEffect(() => {
    void refresh();
  }, [refresh]);

  return { players, loading, error, refresh };
}
