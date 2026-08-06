import { supabase } from '../lib/supabase';

export type TeamMembershipOutcome = {
  error?: string;
  notice?: string;
};

export async function updateMyTeamName(
  leagueId: string,
  teamName: string,
): Promise<TeamMembershipOutcome> {
  if (!supabase) {
    return { error: 'Il collegamento al backend non è configurato.' };
  }

  const { error } = await supabase.rpc('update_my_team_name', {
    p_league_id: leagueId,
    p_team_name: teamName.trim(),
  });

  return error
    ? { error: translateMembershipError(error.message) }
    : { notice: 'Nome squadra aggiornato in tutto lo spogliatoio.' };
}

export async function leaveLeague(
  leagueId: string,
): Promise<TeamMembershipOutcome> {
  if (!supabase) {
    return { error: 'Il collegamento al backend non è configurato.' };
  }

  const { data, error } = await supabase.rpc('leave_league', {
    p_league_id: leagueId,
  });

  if (error || data !== true) {
    return {
      error: translateMembershipError(
        error?.message ?? 'Non è stato possibile lasciare la lega.',
      ),
    };
  }

  return { notice: 'Hai lasciato la lega.' };
}

function translateMembershipError(message: string) {
  const normalized = message.toLowerCase();

  if (
    normalized.includes('update_my_team_name') ||
    normalized.includes('leave_league') ||
    (normalized.includes('function') && normalized.includes('does not exist'))
  ) {
    return 'Aggiorna prima il database LEGHEVO con il file 025.';
  }
  if (normalized.includes('da 2 a 40 caratteri')) {
    return 'Il nome squadra deve contenere da 2 a 40 caratteri.';
  }
  if (normalized.includes('nome squadra è già stato preso')) {
    return 'Questo nome squadra è già stato preso. Servirà più fantasia.';
  }
  if (normalized.includes('trasferire la presidenza')) {
    return 'Trasferisci prima la presidenza a un altro partecipante.';
  }
  if (normalized.includes('competizione è iniziata')) {
    return 'La competizione è iniziata: squadra e partecipazione sono bloccate.';
  }
  if (
    normalized.includes('chiamata d’asta in corso') ||
    normalized.includes("chiamata d'asta in corso")
  ) {
    return 'Chiudi o annulla la chiamata d’asta in corso e riprova.';
  }
  if (normalized.includes('non fai parte')) {
    return 'Non fai più parte di questa lega.';
  }

  return message;
}
