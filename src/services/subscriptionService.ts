import { supabase } from '../lib/supabase';
import {
  isRevenueCatTestStoreEnabled,
  loadRevenueCatSnapshot,
  purchaseRevenueCatPackage,
  restoreRevenueCatPurchases,
} from './revenueCatService';

export type CommercialTier = 'free' | 'premium';
export type CommercialBillingPeriod = 'monthly' | 'annual';

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
  annualPriceLabel: string;
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
  monthlyPriceLabel: '2,99 €/mese',
  annualPriceLabel: '9,99 €/anno',
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

export async function loadCommercialEntitlement(userId: string): Promise<{
  data?: CommercialEntitlement;
  error?: string;
}> {
  if (!supabase) {
    return { error: 'Il collegamento al backend non è configurato.' };
  }

  const { data, error } = await supabase.rpc(
    'get_my_commercial_entitlement_v1',
  );

  let backendEntitlement = FREE_COMMERCIAL_ENTITLEMENT;
  let backendWarning = '';
  if (error) {
    if (
      error.message.includes('get_my_commercial_entitlement_v1') ||
      error.message.toLowerCase().includes('schema cache')
    ) {
      backendWarning =
        'Il profilo Premium sarà completo dopo l’aggiornamento del database di staging.';
    } else {
      return { error: 'Non riesco a verificare il piano del tuo account.' };
    }
  } else {
    backendEntitlement = normalizeCommercialEntitlement(data);
  }

  if (!isRevenueCatTestStoreEnabled()) {
    return { data: backendEntitlement, error: backendWarning || undefined };
  }

  try {
    const revenueCat = await loadRevenueCatSnapshot(userId);
    return {
      data: mergeRevenueCatSnapshot(backendEntitlement, revenueCat),
      error: backendWarning || undefined,
    };
  } catch {
    return {
      data: { ...backendEntitlement, purchasesEnabled: false },
      error: 'Non riesco a collegarmi al Test Store RevenueCat.',
    };
  }
}

export async function startPremiumPurchase(
  userId: string,
  period: CommercialBillingPeriod,
): Promise<{ error?: string }> {
  const result = await purchaseRevenueCatPackage(userId, period);
  return { error: result.error };
}

export async function restorePremiumPurchases(
  userId: string,
): Promise<{ restored: boolean; error?: string }> {
  const result = await restoreRevenueCatPurchases(userId);
  return {
    restored: result.snapshot?.isPremium === true,
    error: result.error,
  };
}

function mergeRevenueCatSnapshot(
  backend: CommercialEntitlement,
  revenueCat: Awaited<ReturnType<typeof loadRevenueCatSnapshot>>,
): CommercialEntitlement {
  const isPremium = backend.isPremium || revenueCat.isPremium;
  return {
    ...backend,
    tier: isPremium ? 'premium' : 'free',
    status: isPremium ? 'active' : backend.status,
    isPremium,
    store: revenueCat.isPremium ? revenueCat.store : backend.store,
    productId: revenueCat.isPremium ? revenueCat.productId : backend.productId,
    environment: revenueCat.isPremium
      ? revenueCat.environment
      : backend.environment,
    currentPeriodEndsAt: revenueCat.isPremium
      ? revenueCat.currentPeriodEndsAt
      : backend.currentPeriodEndsAt,
    willRenew: revenueCat.isPremium ? revenueCat.willRenew : backend.willRenew,
    maxOwnedLeagues: isPremium ? null : backend.maxOwnedLeagues,
    maxParticipantsPerLeague: isPremium
      ? 20
      : backend.maxParticipantsPerLeague,
    adsEnabled: !isPremium,
    purchasesEnabled: revenueCat.configured && revenueCat.offeringAvailable,
    monthlyPriceLabel:
      revenueCat.monthlyPriceLabel ?? backend.monthlyPriceLabel,
    annualPriceLabel: revenueCat.annualPriceLabel ?? backend.annualPriceLabel,
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
        : '2,99 €/mese',
    annualPriceLabel:
      typeof raw.annualPriceLabel === 'string'
        ? raw.annualPriceLabel.replace(' euro/', ' €/')
        : '9,99 €/anno',
  };
}

function toNonNegativeInteger(value: unknown) {
  const parsed = typeof value === 'number' ? value : Number(value);
  return Number.isFinite(parsed) ? Math.max(Math.trunc(parsed), 0) : 0;
}
