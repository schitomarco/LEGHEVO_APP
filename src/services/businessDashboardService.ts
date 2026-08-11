import { supabase } from '../lib/supabase';

export type BusinessDailyPoint = {
  period: string;
  revenueCents: number;
  newPremium: number;
  renewals: number;
  cancellations: number;
};

export type BusinessMonthlyPoint = {
  period: string;
  revenueCents: number;
  leaguesCreated: number;
};

export type BusinessDashboard = {
  generatedAt: string;
  currency: 'EUR';
  dataMode: 'management_estimate';
  officialSourceNotice: string;
  todayRevenueCents: number;
  monthRevenueCents: number;
  seasonRevenueCents: number;
  activeUsers: number;
  premiumUsers: number;
  conversionRate: number;
  appleRevenueCents: number;
  googleRevenueCents: number;
  advertisingRevenueCents: number;
  leagueProRevenueCents: number;
  totalRevenueCents: number;
  estimatedCostsCents: number;
  operatingMarginCents: number;
  newPremium: number;
  renewals: number;
  cancellations: number;
  arpuCents: number;
  activeLeagues: number;
  daily: BusinessDailyPoint[];
  monthly: BusinessMonthlyPoint[];
};

export async function fetchBusinessDashboardAccess(): Promise<boolean> {
  if (!supabase) {
    return false;
  }
  const claim = await supabase.rpc('claim_my_leghevo_business_owner_v1');
  if (!claim.error && claim.data === true) {
    return true;
  }
  const { data, error } = await supabase.rpc('get_my_business_dashboard_access_v1');
  if (error) {
    return false;
  }
  return data === true;
}

export async function fetchBusinessDashboard(): Promise<BusinessDashboard> {
  if (!supabase) {
    throw new Error('Il collegamento al backend non è configurato.');
  }
  const { data, error } = await supabase.rpc(
    'get_leghevo_business_dashboard_v1',
  );
  if (error) {
    throw new Error(translateBusinessDashboardError(error.message));
  }
  return normalizeBusinessDashboard(data);
}

function normalizeBusinessDashboard(value: unknown): BusinessDashboard {
  const raw = record(value);
  return {
    generatedAt: text(raw.generatedAt) ?? new Date().toISOString(),
    currency: 'EUR',
    dataMode: 'management_estimate',
    officialSourceNotice:
      text(raw.officialSourceNotice) ??
      'Importi gestionali stimati. Per maturato e liquidato fanno fede i provider.',
    todayRevenueCents: integer(raw.todayRevenueCents),
    monthRevenueCents: integer(raw.monthRevenueCents),
    seasonRevenueCents: integer(raw.seasonRevenueCents),
    activeUsers: integer(raw.activeUsers),
    premiumUsers: integer(raw.premiumUsers),
    conversionRate: decimal(raw.conversionRate),
    appleRevenueCents: integer(raw.appleRevenueCents),
    googleRevenueCents: integer(raw.googleRevenueCents),
    advertisingRevenueCents: integer(raw.advertisingRevenueCents),
    leagueProRevenueCents: integer(raw.leagueProRevenueCents),
    totalRevenueCents: integer(raw.totalRevenueCents),
    estimatedCostsCents: integer(raw.estimatedCostsCents),
    operatingMarginCents: integer(raw.operatingMarginCents),
    newPremium: integer(raw.newPremium),
    renewals: integer(raw.renewals),
    cancellations: integer(raw.cancellations),
    arpuCents: integer(raw.arpuCents),
    activeLeagues: integer(raw.activeLeagues),
    daily: array(raw.daily).map(normalizeDailyPoint),
    monthly: array(raw.monthly).map(normalizeMonthlyPoint),
  };
}

function normalizeDailyPoint(value: unknown): BusinessDailyPoint {
  const raw = record(value);
  return {
    period: text(raw.period) ?? '',
    revenueCents: integer(raw.revenueCents),
    newPremium: integer(raw.newPremium),
    renewals: integer(raw.renewals),
    cancellations: integer(raw.cancellations),
  };
}

function normalizeMonthlyPoint(value: unknown): BusinessMonthlyPoint {
  const raw = record(value);
  return {
    period: text(raw.period) ?? '',
    revenueCents: integer(raw.revenueCents),
    leaguesCreated: integer(raw.leaguesCreated),
  };
}

function translateBusinessDashboardError(message: string) {
  const normalized = message.toLowerCase();
  if (normalized.includes('riservata') || normalized.includes('permission')) {
    return 'Questa dashboard è riservata al proprietario LEGHEVO.';
  }
  if (
    normalized.includes('get_leghevo_business_dashboard_v1') ||
    normalized.includes('schema cache')
  ) {
    return 'La Business Dashboard deve ancora essere attivata sul database.';
  }
  return 'Non riesco a caricare i dati gestionali.';
}

function record(value: unknown): Record<string, unknown> {
  return value && typeof value === 'object'
    ? (value as Record<string, unknown>)
    : {};
}

function array(value: unknown): unknown[] {
  return Array.isArray(value) ? value : [];
}

function text(value: unknown): string | null {
  return typeof value === 'string' && value ? value : null;
}

function decimal(value: unknown): number {
  const parsed = typeof value === 'number' ? value : Number(value);
  return Number.isFinite(parsed) ? parsed : 0;
}

function integer(value: unknown): number {
  return Math.round(decimal(value));
}
