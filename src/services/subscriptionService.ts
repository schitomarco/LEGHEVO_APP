import { supabase } from '../lib/supabase';

export type CommercialTier = 'free' | 'premium';

export type CommercialEntitlement = {
  tier: CommercialTier;
  status:
    | 'inactive'
    | 'trialing'
    | 'active'
    | 'grace_period'
    | 'billing_retry'
    | 'expired'
    | 'revoked';
  isPremium: boolean;
  store: 'apple' | 'google' | 'manual' | 'test' | null;
  productId: string | null;
  environment: 'sandbox' | 'production';
  currentPeriodEndsAt: string | null;
  gracePeriodEndsAt: string | null;
  willRenew: boolean;
  ownedLeagueCount: number;
  maxOwnedLeagues: number | null;
  maxParticipantsPerLeague: number;
  adsEnabled: boolean;
  purchasesEnabled: boolean;
  monthlyPriceLabel: string;
};

export const FREE_COMMERCIAL_ENTITLEMENT: CommercialEntitlement = {
  tier: 'free',
  status: 'inactive',
  isPremium: false,
  store: null,
  productId: null,
  environment: 'sandbox',
  currentPeriodEndsAt: null,
  gracePeriodEndsAt: null,
  willRenew: false,
  ownedLeagueCount: 0,
  maxOwnedLeagues: 1,
  maxParticipantsPerLeague: 6,
  adsEnabled: true,
  purchasesEnabled: false,
  monthlyPriceLabel: '9,99 €/mese',
};

export const DEMO_COMMERCIAL_ENTITLEMENT: CommercialEntitlement = {
  ...FREE_COMMERCIAL_ENTITLEMENT,
  tier: 'premium',
  status: 'active',
  isPremium: true,
  store: 'test',
  productId: 'leghevo_premium_monthly',
  ownedLeagueCount: 1,
  maxOwnedLeagues: null,
  maxParticipantsPerLeague: 20,
  adsEnabled: false,
};

export async function loadCommercialEntitlement(): Promise<{
  data?: CommercialEntitlement;
  error?: string;
}> {
  if (!supabase) {
    return { error: 'Il collegamento al backend non è configurato.' };
  }

  const { data, error } = await supabase.rpc(
    'get_my_commercial_entitlement_v1',
  );

  if (error) {
    if (
      error.message.includes('get_my_commercial_entitlement_v1') ||
      error.message.toLowerCase().includes('schema cache')
    ) {
      return {
        data: FREE_COMMERCIAL_ENTITLEMENT,
        error: 'Il profilo Premium sarà disponibile dopo l’aggiornamento del database.',
      };
    }
    return { error: 'Non riesco a verificare il piano del tuo account.' };
  }

  return { data: normalizeCommercialEntitlement(data) };
}

export async function startPremiumPurchase(): Promise<{ error?: string }> {
  return {
    error:
      'Gli acquisti sono ancora in modalità preparazione. Nessun addebito è stato effettuato.',
  };
}

export async function restorePremiumPurchases(): Promise<{ error?: string }> {
  return {
    error:
      'Il ripristino sarà disponibile quando collegheremo Apple e Google a RevenueCat.',
  };
}

function normalizeCommercialEntitlement(
  value: unknown,
): CommercialEntitlement {
  const raw = value && typeof value === 'object'
    ? (value as Record<string, unknown>)
    : {};
  const isPremium = raw.isPremium === true;
  const store =
    raw.store === 'apple' ||
    raw.store === 'google' ||
    raw.store === 'manual' ||
    raw.store === 'test'
      ? raw.store
      : null;
  const status =
    raw.status === 'trialing' ||
    raw.status === 'active' ||
    raw.status === 'grace_period' ||
    raw.status === 'billing_retry' ||
    raw.status === 'expired' ||
    raw.status === 'revoked'
      ? raw.status
      : 'inactive';

  return {
    tier: isPremium ? 'premium' : 'free',
    status,
    isPremium,
    store,
    productId: typeof raw.productId === 'string' ? raw.productId : null,
    environment: raw.environment === 'production' ? 'production' : 'sandbox',
    currentPeriodEndsAt:
      typeof raw.currentPeriodEndsAt === 'string'
        ? raw.currentPeriodEndsAt
        : null,
    gracePeriodEndsAt:
      typeof raw.gracePeriodEndsAt === 'string'
        ? raw.gracePeriodEndsAt
        : null,
    willRenew: raw.willRenew === true,
    ownedLeagueCount: toNonNegativeInteger(raw.ownedLeagueCount),
    maxOwnedLeagues:
      raw.maxOwnedLeagues === null
        ? null
        : Math.max(toNonNegativeInteger(raw.maxOwnedLeagues), 1),
    maxParticipantsPerLeague: Math.max(
      toNonNegativeInteger(raw.maxParticipantsPerLeague),
      isPremium ? 20 : 6,
    ),
    adsEnabled: !isPremium && raw.adsEnabled !== false,
    purchasesEnabled: raw.purchasesEnabled === true,
    monthlyPriceLabel:
      typeof raw.monthlyPriceLabel === 'string'
        ? raw.monthlyPriceLabel.replace(' euro/', ' €/')
        : '9,99 €/mese',
  };
}

function toNonNegativeInteger(value: unknown) {
  const parsed = typeof value === 'number' ? value : Number(value);
  return Number.isFinite(parsed) ? Math.max(Math.trunc(parsed), 0) : 0;
}
