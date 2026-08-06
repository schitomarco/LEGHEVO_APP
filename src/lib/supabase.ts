import 'react-native-url-polyfill/auto';

import AsyncStorage from '@react-native-async-storage/async-storage';
import { AppState, Platform } from 'react-native';
import { createClient, processLock } from '@supabase/supabase-js';
import {
  APP_BUNDLE_FINGERPRINT,
  APP_RELEASE_CONTRACT_VERSION,
  APP_RELEASE_VERSION,
} from '../release';

const supabaseUrl = process.env.EXPO_PUBLIC_SUPABASE_URL;
const supabasePublishableKey =
  process.env.EXPO_PUBLIC_SUPABASE_PUBLISHABLE_KEY ??
  process.env.EXPO_PUBLIC_SUPABASE_KEY;

export const isBackendConfigured = Boolean(
  supabaseUrl && supabasePublishableKey,
);

export const supabase = isBackendConfigured
  ? createClient(supabaseUrl!, supabasePublishableKey!, {
      global: {
        headers: {
          'x-leghevo-version': APP_RELEASE_VERSION,
          'x-leghevo-bundle-fingerprint': APP_BUNDLE_FINGERPRINT,
          'x-leghevo-release-contract': String(APP_RELEASE_CONTRACT_VERSION),
        },
      },
      auth: {
        storage: AsyncStorage,
        autoRefreshToken: true,
        persistSession: true,
        detectSessionInUrl: false,
        lock: processLock,
      },
    })
  : null;

if (supabase && Platform.OS !== 'web') {
  AppState.addEventListener('change', (state) => {
    if (state === 'active') {
      supabase.auth.startAutoRefresh();
    } else {
      supabase.auth.stopAutoRefresh();
    }
  });
}
