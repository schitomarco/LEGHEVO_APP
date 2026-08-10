import Purchases, {
  LOG_LEVEL,
  type CustomerInfo,
  type PurchasesError,
  type PurchasesOffering,
  type PurchasesPackage,
} from 'react-native-purchases';
import { Platform } from 'react-native';

const REVENUECAT_ENTITLEMENT_ID = 'premium';
const revenueCatTestApiKey = process.env.EXPO_PUBLIC_REVENUECAT_API_KEY?.trim();
const revenueCatIosApiKey =
  process.env.EXPO_PUBLIC_REVENUECAT_IOS_API_KEY?.trim();
const revenueCatAndroidApiKey =
  process.env.EXPO_PUBLIC_REVENUECAT_ANDROID_API_KEY?.trim();
const configuredStoreMode =
  process.env.EXPO_PUBLIC_REVENUECAT_STORE_MODE?.trim().toLowerCase();
const purchasesEnabled =
  process.env.EXPO_PUBLIC_REVENUECAT_PURCHASES_ENABLED === 'true';

let configured = false;
let configuredUserId: string | null = null;
let configurationTask: Promise<void> | null = null;

export type RevenueCatSnapshot = {
  configured: boolean;
  offeringAvailable: boolean;
  isPremium: boolean;
  productId: string | null;
  store: 'apple' | 'google' | 'test' | null;
  environment: 'sandbox' | 'production';
  currentPeriodEndsAt: string | null;
  willRenew: boolean;
  monthlyPriceLabel: string | null;
  annualPriceLabel: string | null;
  purchaseMode: 'test' | 'store';
};

export function isRevenueCatTestStoreEnabled() {
  return getRevenueCatConfiguration()?.mode === 'test';
}

export function isRevenueCatEnabled() {
  return getRevenueCatConfiguration() !== null;
}

export async function loadRevenueCatSnapshot(
  userId: string,
): Promise<RevenueCatSnapshot> {
  await ensureRevenueCatUser(userId);
  const [customerInfo, offerings] = await Promise.all([
    Purchases.getCustomerInfo(),
    Purchases.getOfferings(),
  ]);
  return createSnapshot(customerInfo, selectOffering(offerings));
}

export async function purchaseRevenueCatPackage(
  userId: string,
  period: 'monthly' | 'annual',
): Promise<{ cancelled?: boolean; snapshot?: RevenueCatSnapshot; error?: string }> {
  try {
    await ensureRevenueCatUser(userId);
    const offerings = await Purchases.getOfferings();
    const offering = selectOffering(offerings);
    const selectedPackage = selectPackage(offering, period);
    if (!offering || !selectedPackage) {
      return {
        error:
          'Il piano selezionato non è disponibile nello store. Controlla l’offerta Premium su RevenueCat.',
      };
    }

    const { customerInfo } = await Purchases.purchasePackage(selectedPackage);
    const snapshot = createSnapshot(customerInfo, offering);
    if (!snapshot.isPremium) {
      return {
        error:
          'L’acquisto è stato registrato, ma l’abilitazione Premium non è ancora disponibile.',
      };
    }
    return { snapshot };
  } catch (error) {
    if (isCancelledPurchase(error)) {
      return { cancelled: true };
    }
    return { error: revenueCatErrorMessage(error) };
  }
}

export async function restoreRevenueCatPurchases(
  userId: string,
): Promise<{ snapshot?: RevenueCatSnapshot; error?: string }> {
  try {
    await ensureRevenueCatUser(userId);
    const [customerInfo, offerings] = await Promise.all([
      Purchases.restorePurchases(),
      Purchases.getOfferings(),
    ]);
    return { snapshot: createSnapshot(customerInfo, selectOffering(offerings)) };
  } catch (error) {
    return { error: revenueCatErrorMessage(error) };
  }
}

async function ensureRevenueCatUser(userId: string) {
  const configuration = getRevenueCatConfiguration();
  if (!configuration) {
    throw new Error('RevenueCat non è configurato in modo sicuro per questa build.');
  }
  if (!userId) {
    throw new Error('Accedi al tuo account prima di gestire Premium.');
  }

  if (!configured) {
    if (!configurationTask) {
      configurationTask = Promise.resolve().then(async () => {
        Purchases.configure({ apiKey: configuration.apiKey, appUserID: userId });
        if (__DEV__) {
          await Purchases.setLogLevel(LOG_LEVEL.DEBUG);
        }
        configured = true;
        configuredUserId = userId;
      });
    }
    try {
      await configurationTask;
    } catch (error) {
      configurationTask = null;
      throw error;
    }
    return;
  }

  if (configuredUserId !== userId) {
    await Purchases.logOut();
    await Purchases.logIn(userId);
    configuredUserId = userId;
  }
}

function selectOffering(offerings: Awaited<ReturnType<typeof Purchases.getOfferings>>) {
  return (
    offerings.current ??
    offerings.all.Premium ??
    offerings.all.premium ??
    null
  );
}

function selectPackage(
  offering: PurchasesOffering | null,
  period: 'monthly' | 'annual',
): PurchasesPackage | null {
  if (!offering) {
    return null;
  }
  return period === 'annual' ? offering.annual : offering.monthly;
}

function createSnapshot(
  customerInfo: CustomerInfo,
  offering: PurchasesOffering | null,
): RevenueCatSnapshot {
  const configuration = getRevenueCatConfiguration();
  if (!configuration) {
    throw new Error('RevenueCat non è configurato in modo sicuro per questa build.');
  }
  const entitlement = customerInfo.entitlements.active[REVENUECAT_ENTITLEMENT_ID];
  return {
    configured: true,
    offeringAvailable: offering !== null,
    isPremium: entitlement?.isActive === true,
    productId: entitlement?.productIdentifier ?? null,
    store: mapStore(entitlement?.store),
    environment: entitlement?.isSandbox === false ? 'production' : 'sandbox',
    currentPeriodEndsAt: entitlement?.expirationDate ?? null,
    willRenew: entitlement?.willRenew === true,
    monthlyPriceLabel: offering?.monthly?.product.priceString ?? null,
    annualPriceLabel: offering?.annual?.product.priceString ?? null,
    purchaseMode: configuration.mode,
  };
}

function getRevenueCatConfiguration(): {
  apiKey: string;
  mode: 'test' | 'store';
} | null {
  if (!purchasesEnabled) {
    return null;
  }

  const wantsTestStore =
    configuredStoreMode === 'test' ||
    (!configuredStoreMode && revenueCatTestApiKey?.startsWith('test_'));
  if (wantsTestStore) {
    return __DEV__ && revenueCatTestApiKey?.startsWith('test_')
      ? { apiKey: revenueCatTestApiKey, mode: 'test' }
      : null;
  }

  if (configuredStoreMode !== 'store') {
    return null;
  }

  if (Platform.OS === 'ios' && revenueCatIosApiKey?.startsWith('appl_')) {
    return { apiKey: revenueCatIosApiKey, mode: 'store' };
  }
  if (
    Platform.OS === 'android' &&
    revenueCatAndroidApiKey?.startsWith('goog_')
  ) {
    return { apiKey: revenueCatAndroidApiKey, mode: 'store' };
  }
  return null;
}

function mapStore(store: string | undefined): 'apple' | 'google' | 'test' | null {
  if (store === 'APP_STORE' || store === 'MAC_APP_STORE') {
    return 'apple';
  }
  if (store === 'PLAY_STORE') {
    return 'google';
  }
  if (store === 'TEST_STORE') {
    return 'test';
  }
  return null;
}

function isCancelledPurchase(error: unknown) {
  return (
    typeof error === 'object' &&
    error !== null &&
    ((error as Partial<PurchasesError>).userCancelled === true ||
      (error as Partial<PurchasesError>).code ===
        Purchases.PURCHASES_ERROR_CODE.PURCHASE_CANCELLED_ERROR)
  );
}

function revenueCatErrorMessage(error: unknown) {
  if (error instanceof Error && error.message.includes('non è configurato')) {
    return error.message;
  }
  return 'RevenueCat non è raggiungibile. Controlla la connessione e riprova.';
}
