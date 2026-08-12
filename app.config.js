const STAGING_SUPABASE_PROJECT_REF = 'livmqnctrufdyubdbkws';
const STORE_PROFILES = new Set(['testflight', 'play-testing', 'production']);

function required(name) {
  const value = process.env[name]?.trim();
  if (!value) {
    throw new Error(`[LEGHEVO EAS] Variabile obbligatoria assente: ${name}.`);
  }
  return value;
}

function validateStoreBuild(profile) {
  const appEnvironment = required('EXPO_PUBLIC_APP_ENV');
  const supabaseUrl = required('EXPO_PUBLIC_SUPABASE_URL');
  required('EXPO_PUBLIC_SUPABASE_PUBLISHABLE_KEY');

  let parsedUrl;
  try {
    parsedUrl = new URL(supabaseUrl);
  } catch {
    throw new Error(
      '[LEGHEVO EAS] EXPO_PUBLIC_SUPABASE_URL non e un URL valido.',
    );
  }
  if (
    parsedUrl.protocol !== 'https:' ||
    !parsedUrl.hostname.endsWith('.supabase.co')
  ) {
    throw new Error(
      '[LEGHEVO EAS] Il backend store deve usare un URL HTTPS Supabase valido.',
    );
  }

  const isStagingBackend = parsedUrl.hostname.startsWith(
    `${STAGING_SUPABASE_PROJECT_REF}.`,
  );
  if (profile === 'production') {
    if (appEnvironment !== 'production') {
      throw new Error(
        '[LEGHEVO EAS] La build production richiede EXPO_PUBLIC_APP_ENV=production.',
      );
    }
    if (isStagingBackend) {
      throw new Error(
        '[LEGHEVO EAS] Build production bloccata: il backend configurato e LEGHEVO Staging.',
      );
    }
  } else {
    if (appEnvironment !== 'staging') {
      throw new Error(
        `[LEGHEVO EAS] La build ${profile} richiede EXPO_PUBLIC_APP_ENV=staging.`,
      );
    }
    if (!isStagingBackend) {
      throw new Error(
        `[LEGHEVO EAS] La build ${profile} deve puntare esclusivamente a LEGHEVO Staging.`,
      );
    }
  }

  if (process.env.EXPO_PUBLIC_REVENUECAT_STORE_MODE !== 'store') {
    throw new Error(
      '[LEGHEVO EAS] EXPO_PUBLIC_REVENUECAT_STORE_MODE deve essere store.',
    );
  }
  if (process.env.EXPO_PUBLIC_REVENUECAT_PURCHASES_ENABLED !== 'true') {
    throw new Error(
      '[LEGHEVO EAS] Gli acquisti RevenueCat devono essere abilitati.',
    );
  }
  if (process.env.EXPO_PUBLIC_REVENUECAT_API_KEY?.trim()) {
    throw new Error(
      '[LEGHEVO EAS] La chiave generica Test Store non puo entrare in una build store.',
    );
  }

  const platform = process.env.EAS_BUILD_PLATFORM;
  if (!platform || platform === 'ios') {
    const key = required('EXPO_PUBLIC_REVENUECAT_IOS_API_KEY');
    if (!key.startsWith('appl_')) {
      throw new Error('[LEGHEVO EAS] Chiave RevenueCat iOS non valida.');
    }
  }
  if (!platform || platform === 'android') {
    const key = required('EXPO_PUBLIC_REVENUECAT_ANDROID_API_KEY');
    if (!key.startsWith('goog_')) {
      throw new Error('[LEGHEVO EAS] Chiave RevenueCat Android non valida.');
    }
  }
}

module.exports = ({ config }) => {
  const profile = process.env.EAS_BUILD_PROFILE;
  if (profile && STORE_PROFILES.has(profile)) {
    validateStoreBuild(profile);
  }
  return config;
};
