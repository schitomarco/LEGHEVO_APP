import { supabase } from '../lib/supabase';
import type { GoalBands, LeagueSettings } from '../types';

export const defaultLeagueSettings: LeagueSettings = {
  marketOpen: true,
  marketMinimumPrice: 1,
  releaseRefundPercent: 50,
  maxSubstitutions: 5,
  defenseModifierEnabled: false,
  defenseModifierMinDefenders: 4,
  goalThreshold: 66,
  goalStep: 6,
  goalBandsEnabled: false,
  goalBands: [66, 72, 78, 84, 90, 96],
  goalMarginEnabled: false,
  goalMargin: 4,
  standingsTiebreaker: 'goal_difference',
  homeBonus: 0,
  bonusGoal: 3,
  bonusAssist: 1,
  bonusPenaltySaved: 3,
  malusYellowCard: 0.5,
  malusRedCard: 1,
  malusPenaltyMissed: 3,
  malusGoalConceded: 1,
  rosterGoalkeepers: 3,
  rosterDefenders: 8,
  rosterMidfielders: 8,
  rosterAttackers: 6,
};

type LeagueRulesRow = {
  scoring_rules: Record<string, unknown> | null;
  roster_size: number;
};

export async function fetchLeagueSettings(
  leagueId: string,
): Promise<LeagueSettings> {
  if (!supabase) {
    return defaultLeagueSettings;
  }

  const { data, error } = await supabase
    .from('leagues')
    .select('scoring_rules, roster_size')
    .eq('id', leagueId)
    .single();

  if (error) {
    throw error;
  }

  const row = data as LeagueRulesRow | null;
  return mapSettings(row?.scoring_rules, row?.roster_size);
}

export async function updateLeagueSettings(
  leagueId: string,
  settings: LeagueSettings,
  changeReason: string,
): Promise<{ settings?: LeagueSettings; error?: string }> {
  if (!supabase) {
    return { error: 'Il collegamento al backend non è configurato.' };
  }

  const { data, error } = await supabase.rpc('update_league_settings_v9', {
    p_league_id: leagueId,
    p_market_open: settings.marketOpen,
    p_market_min_price: settings.marketMinimumPrice,
    p_release_refund_percent: settings.releaseRefundPercent,
    p_goal_threshold: settings.goalThreshold,
    p_goal_step: settings.goalStep,
    p_goal_bands_enabled: settings.goalBandsEnabled,
    p_goal_bands: settings.goalBands,
    p_goal_margin_enabled: settings.goalMarginEnabled,
    p_goal_margin: settings.goalMargin,
    p_standings_tiebreaker: settings.standingsTiebreaker,
    p_home_bonus: settings.homeBonus,
    p_bonus_goal: settings.bonusGoal,
    p_bonus_assist: settings.bonusAssist,
    p_bonus_penalty_saved: settings.bonusPenaltySaved,
    p_malus_yellow_card: settings.malusYellowCard,
    p_malus_red_card: settings.malusRedCard,
    p_malus_penalty_missed: settings.malusPenaltyMissed,
    p_malus_goal_conceded: settings.malusGoalConceded,
    p_roster_goalkeepers: settings.rosterGoalkeepers,
    p_roster_defenders: settings.rosterDefenders,
    p_roster_midfielders: settings.rosterMidfielders,
    p_roster_attackers: settings.rosterAttackers,
    p_max_substitutions: settings.maxSubstitutions,
    p_defense_modifier_enabled: settings.defenseModifierEnabled,
    p_defense_modifier_min_defenders:
      settings.defenseModifierMinDefenders,
    p_change_reason: changeReason.trim(),
  });

  if (error) {
    return { error: translateSettingsError(error.message) };
  }

  const row = (Array.isArray(data) ? data[0] : data) as LeagueRulesRow | null;
  return { settings: mapSettings(row?.scoring_rules, row?.roster_size) };
}

export function mapSettings(
  rules: Record<string, unknown> | null | undefined,
  rosterSize = 25,
): LeagueSettings {
  const source = rules ?? {};
  const quotaDefaults = defaultRosterQuotas(rosterSize);
  const goalThreshold = boundedNumber(
    source.goal_threshold,
    defaultLeagueSettings.goalThreshold,
    50,
    100,
  );
  const goalStep = boundedNumber(
    source.goal_step,
    defaultLeagueSettings.goalStep,
    1,
    20,
  );
  return {
    marketOpen: source.market_open !== false,
    marketMinimumPrice: boundedInteger(
      source.market_min_price,
      defaultLeagueSettings.marketMinimumPrice,
      1,
      1000,
    ),
    releaseRefundPercent: boundedInteger(
      source.release_refund_percent,
      defaultLeagueSettings.releaseRefundPercent,
      0,
      100,
    ),
    maxSubstitutions: boundedInteger(
      source.max_substitutions,
      defaultLeagueSettings.maxSubstitutions,
      0,
      11,
    ),
    defenseModifierEnabled:
      source.defense_modifier_enabled === true,
    defenseModifierMinDefenders: boundedInteger(
      source.defense_modifier_min_defenders,
      defaultLeagueSettings.defenseModifierMinDefenders,
      4,
      5,
    ),
    goalThreshold,
    goalStep,
    goalBandsEnabled: source.goal_bands_enabled === true,
    goalBands: normalizeGoalBands(
      source.goal_bands,
      goalThreshold,
      goalStep,
    ),
    goalMarginEnabled: source.goal_margin_enabled === true,
    goalMargin: boundedNumber(
      source.goal_margin,
      defaultLeagueSettings.goalMargin,
      1,
      20,
    ),
    standingsTiebreaker: normalizeStandingsTiebreaker(
      source.standings_tiebreaker,
    ),
    homeBonus: boundedNumber(
      source.home_bonus,
      defaultLeagueSettings.homeBonus,
      0,
      10,
    ),
    bonusGoal: boundedNumber(
      source.bonus_goal,
      defaultLeagueSettings.bonusGoal,
      0,
      10,
    ),
    bonusAssist: boundedNumber(
      source.bonus_assist,
      defaultLeagueSettings.bonusAssist,
      0,
      5,
    ),
    bonusPenaltySaved: boundedNumber(
      source.bonus_penalty_saved,
      defaultLeagueSettings.bonusPenaltySaved,
      0,
      10,
    ),
    malusYellowCard: boundedNumber(
      source.malus_yellow_card,
      defaultLeagueSettings.malusYellowCard,
      0,
      5,
    ),
    malusRedCard: boundedNumber(
      source.malus_red_card,
      defaultLeagueSettings.malusRedCard,
      0,
      10,
    ),
    malusPenaltyMissed: boundedNumber(
      source.malus_penalty_missed,
      defaultLeagueSettings.malusPenaltyMissed,
      0,
      10,
    ),
    malusGoalConceded: boundedNumber(
      source.malus_goal_conceded,
      defaultLeagueSettings.malusGoalConceded,
      0,
      5,
    ),
    rosterGoalkeepers: boundedInteger(
      source.roster_quota_goalkeepers,
      quotaDefaults.goalkeepers,
      1,
      rosterSize,
    ),
    rosterDefenders: boundedInteger(
      source.roster_quota_defenders,
      quotaDefaults.defenders,
      3,
      rosterSize,
    ),
    rosterMidfielders: boundedInteger(
      source.roster_quota_midfielders,
      quotaDefaults.midfielders,
      3,
      rosterSize,
    ),
    rosterAttackers: boundedInteger(
      source.roster_quota_attackers,
      quotaDefaults.attackers,
      1,
      rosterSize,
    ),
  };
}

function normalizeGoalBands(
  value: unknown,
  threshold: number,
  step: number,
): GoalBands {
  const fallback = Array.from(
    { length: 6 },
    (_, index) => threshold + step * index,
  ) as GoalBands;

  if (!Array.isArray(value) || value.length !== 6) {
    return fallback;
  }

  const parsed = value.map(Number);
  const valid = parsed.every(
    (item, index) =>
      Number.isFinite(item) &&
      item >= 50 &&
      item <= 150 &&
      (index === 0 || item > parsed[index - 1]),
  );

  return valid ? (parsed as GoalBands) : fallback;
}

function normalizeStandingsTiebreaker(
  value: unknown,
): LeagueSettings['standingsTiebreaker'] {
  return value === 'fantasy_points' || value === 'head_to_head'
    ? value
    : 'goal_difference';
}

export function defaultRosterQuotas(rosterSize: number) {
  const safeSize = Math.max(11, Math.round(rosterSize));
  const goalkeepers = Math.max(1, Math.round(safeSize * 0.12));
  const remaining = safeSize - goalkeepers;
  const defenders = Math.max(3, Math.round(remaining * 0.36));
  const midfielders = Math.max(3, Math.round(remaining * 0.36));
  const attackers = safeSize - goalkeepers - defenders - midfielders;
  return { goalkeepers, defenders, midfielders, attackers };
}

function boundedInteger(
  value: unknown,
  fallback: number,
  minimum: number,
  maximum: number,
) {
  const parsed = Number(value);
  return Number.isInteger(parsed) && parsed >= minimum && parsed <= maximum
    ? parsed
    : fallback;
}

function boundedNumber(
  value: unknown,
  fallback: number,
  minimum: number,
  maximum: number,
) {
  const parsed = Number(value);
  return Number.isFinite(parsed) && parsed >= minimum && parsed <= maximum
    ? parsed
    : fallback;
}

function translateSettingsError(message: string) {
  const normalized = message.toLowerCase();
  if (
    normalized.includes('update_league_settings_v9') ||
    (normalized.includes('function') && normalized.includes('does not exist'))
  ) {
    return 'Aggiorna prima il database LEGHEVO con il file 056.';
  }
  if (normalized.includes('motivazione')) {
    return 'Inserisci una motivazione tra 8 e 240 caratteri.';
  }
  if (normalized.includes('nessuna regola')) {
    return 'Non hai modificato nessuna regola.';
  }
  if (normalized.includes('solo il presidente')) {
    return 'Solo il Presidente può cambiare queste regole.';
  }
  return message;
}
