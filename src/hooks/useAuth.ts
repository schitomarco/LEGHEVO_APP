import { useEffect, useMemo, useState } from 'react';
import type { Session } from '@supabase/supabase-js';
import * as Linking from 'expo-linking';
import { isBackendConfigured, supabase } from '../lib/supabase';
import {
  removeCurrentAccount,
  saveDisplayName,
  saveNewPassword,
  sendPasswordReset,
} from '../services/accountService';
import {
  exportPersonalData,
  loadPrivacyPreferences,
  savePrivacyPreferences,
  subscribeToPrivacyCenter,
  type PrivacyPreferences,
} from '../services/privacyService';
import {
  MINIMUM_AGE_VERSION,
  PRIVACY_POLICY_VERSION,
  TERMS_VERSION,
} from '../legalDocuments';
import { unregisterCurrentPushDevice } from '../services/pushNotificationService';

export type AuthOutcome = {
  error?: string;
  notice?: string;
};

export type RegistrationChoices = {
  minimumAgeConfirmed: boolean;
  privacyAcknowledged: boolean;
  termsAccepted: boolean;
};

export function useAuth() {
  const [session, setSession] = useState<Session | null>(null);
  const [demoAuthenticated, setDemoAuthenticated] = useState(false);
  const [passwordRecovery, setPasswordRecovery] = useState(false);
  const [recoveryError, setRecoveryError] = useState('');
  const [loading, setLoading] = useState(true);
  const [privacy, setPrivacy] = useState<PrivacyPreferences | null>(null);
  const [privacyError, setPrivacyError] = useState('');
  const [privacyLoading, setPrivacyLoading] = useState(false);
  const [privacyUserId, setPrivacyUserId] = useState<string | null>(null);

  useEffect(() => {
    if (!supabase) {
      setLoading(false);
      return;
    }

    const client = supabase;
    let mounted = true;

    void client.auth.getSession().then(({ data }) => {
      if (mounted) {
        setSession(data.session);
        setLoading(false);
      }
    });

    const handleRecoveryUrl = async (url: string) => {
      const params = authParameters(url);
      const isRecovery =
        url.includes('reset-password') || params.get('type') === 'recovery';
      if (!isRecovery) {
        return;
      }

      const linkError =
        params.get('error_description') ?? params.get('error');
      if (linkError) {
        setRecoveryError(linkError.replace(/\+/g, ' '));
        setPasswordRecovery(true);
        return;
      }

      const accessToken = params.get('access_token');
      const refreshToken = params.get('refresh_token');
      const code = params.get('code');

      if (accessToken && refreshToken) {
        const { data, error } = await client.auth.setSession({
          access_token: accessToken,
          refresh_token: refreshToken,
        });
        if (error) {
          setRecoveryError(translateAuthError(error.message));
          setPasswordRecovery(true);
          return;
        }
        setSession(data.session);
      } else if (code) {
        const { data, error } =
          await client.auth.exchangeCodeForSession(code);
        if (error) {
          setRecoveryError(translateAuthError(error.message));
          setPasswordRecovery(true);
          return;
        }
        setSession(data.session);
      } else {
        setRecoveryError('Il link di recupero non è valido o è scaduto.');
        setPasswordRecovery(true);
        return;
      }

      setRecoveryError('');
      setPasswordRecovery(true);
    };

    void Linking.getInitialURL().then((url) => {
      if (url) {
        void handleRecoveryUrl(url);
      }
    });

    const linkingSubscription = Linking.addEventListener('url', ({ url }) => {
      void handleRecoveryUrl(url);
    });

    const {
      data: { subscription },
    } = client.auth.onAuthStateChange((event, nextSession) => {
      setSession(nextSession);
      setLoading(false);
      if (event === 'PASSWORD_RECOVERY') {
        setRecoveryError('');
        setPasswordRecovery(true);
      }
    });

    return () => {
      mounted = false;
      linkingSubscription.remove();
      subscription.unsubscribe();
    };
  }, []);

  useEffect(() => {
    const userId = session?.user.id ?? null;
    if (!userId || demoAuthenticated) {
      setPrivacy(null);
      setPrivacyError('');
      setPrivacyLoading(false);
      setPrivacyUserId(null);
      return;
    }

    let active = true;
    setPrivacyLoading(true);
    setPrivacyError('');

    const refreshPrivacy = async (initial = false) => {
      const outcome = await loadPrivacyPreferences();
      if (!active) {
        return;
      }
      setPrivacy(outcome.data ?? null);
      setPrivacyError(outcome.error ?? '');
      if (initial) {
        setPrivacyLoading(false);
        setPrivacyUserId(userId);
      }
    };

    void refreshPrivacy(true);
    const unsubscribe = subscribeToPrivacyCenter(userId, () => {
      void refreshPrivacy();
    });

    return () => {
      active = false;
      unsubscribe();
    };
  }, [demoAuthenticated, session?.user.id]);

  const profile = useMemo(() => {
    if (demoAuthenticated) {
      return {
        displayName: 'Marco Schito',
        email: 'marco@example.com',
        emailVerified: false,
        isDemo: true,
        userId: null,
      };
    }

    const displayName =
      session?.user.user_metadata?.display_name ??
      session?.user.email?.split('@')[0] ??
      'Mister';

    return {
      displayName,
      email: session?.user.email ?? '',
      emailVerified: Boolean(session?.user.email_confirmed_at),
      isDemo: false,
      userId: session?.user.id ?? null,
    };
  }, [demoAuthenticated, session]);

  const signIn = async (
    email: string,
    password: string,
  ): Promise<AuthOutcome> => {
    if (!supabase) {
      return { error: 'Il backend non è ancora configurato su questo dispositivo.' };
    }

    const { error } = await supabase.auth.signInWithPassword({
      email: email.trim(),
      password,
    });

    return error ? { error: translateAuthError(error.message) } : {};
  };

  const signUp = async (
    email: string,
    password: string,
    displayName: string,
    choices: RegistrationChoices,
  ): Promise<AuthOutcome> => {
    if (!supabase) {
      return { error: 'Il backend non è ancora configurato su questo dispositivo.' };
    }

    const { data, error } = await supabase.auth.signUp({
      email: email.trim(),
      password,
      options: {
        data: {
          display_name: displayName.trim(),
          marketing_consent: false,
          minimum_age_confirmed: choices.minimumAgeConfirmed,
          minimum_age_confirmed_at: new Date().toISOString(),
          minimum_age_version: MINIMUM_AGE_VERSION,
          privacy_acknowledged: choices.privacyAcknowledged,
          privacy_acknowledged_at: new Date().toISOString(),
          privacy_policy_version: PRIVACY_POLICY_VERSION,
          terms_accepted: choices.termsAccepted,
          terms_accepted_at: new Date().toISOString(),
          terms_version: TERMS_VERSION,
        },
      },
    });

    if (error) {
      return { error: translateAuthError(error.message) };
    }

    if (data.user && !data.session) {
      return {
        notice:
          'Account creato. Controlla l’email per confermare: poi si entra in campo.',
      };
    }

    return {};
  };

  const logout = async () => {
    setDemoAuthenticated(false);
    setPasswordRecovery(false);
    setRecoveryError('');
    setPrivacy(null);
    setPrivacyError('');
    setPrivacyUserId(null);
    if (session && supabase) {
      try {
        await unregisterCurrentPushDevice();
      } catch {
        // Il logout locale deve riuscire anche se il dispositivo è offline.
      }
      await supabase.auth.signOut();
    }
    setSession(null);
  };

  const resetPassword = async (email: string) => sendPasswordReset(email);

  const updateDisplayName = async (displayName: string) => {
    if (demoAuthenticated) {
      return { error: 'Il profilo demo non può essere modificato.' };
    }
    return saveDisplayName(displayName);
  };

  const updatePassword = async (password: string) => {
    if (demoAuthenticated) {
      return { error: 'Il profilo demo non ha una password.' };
    }
    return saveNewPassword(password);
  };

  const completePasswordRecovery = async (password: string) => {
    const outcome = await saveNewPassword(password);
    if (!outcome.error) {
      setPasswordRecovery(false);
      setRecoveryError('');
    }
    return outcome;
  };

  const cancelPasswordRecovery = async () => {
    setPasswordRecovery(false);
    setRecoveryError('');
    if (supabase) {
      await supabase.auth.signOut({ scope: 'local' });
    }
    setSession(null);
  };

  const deleteAccount = async () => {
    if (demoAuthenticated) {
      return { error: 'Il profilo demo non può essere eliminato.' };
    }
    const outcome = await removeCurrentAccount();
    if (!outcome.error) {
      setSession(null);
      setDemoAuthenticated(false);
      setPasswordRecovery(false);
    }
    return outcome;
  };

  const updatePrivacyChoices = async () => {
    if (demoAuthenticated) {
      return { error: 'Le preferenze del profilo demo non vengono salvate.' };
    }

    const outcome = await savePrivacyPreferences();
    if (outcome.data) {
      setPrivacy(outcome.data);
      setPrivacyError('');
      setPrivacyUserId(session?.user.id ?? null);
    }
    return {
      error: outcome.error,
      notice: outcome.notice,
    };
  };

  const isPrivacyReady =
    demoAuthenticated ||
    !session ||
    (!privacyLoading && privacyUserId === session.user.id);

  return {
    authenticated: demoAuthenticated || Boolean(session),
    backendConfigured: isBackendConfigured,
    loading: loading || !isPrivacyReady,
    passwordRecovery,
    privacy,
    privacyError,
    privacyRequired:
      Boolean(session) &&
      !demoAuthenticated &&
      !privacy?.currentDocumentsAccepted,
    profile,
    recoveryError,
    cancelPasswordRecovery,
    completePasswordRecovery,
    deleteAccount,
    demoLogin: () => setDemoAuthenticated(true),
    exportPersonalData,
    resetPassword,
    signIn,
    signUp,
    updateDisplayName,
    updatePassword,
    updatePrivacyChoices,
    logout,
  };
}

function authParameters(url: string) {
  const hashStart = url.indexOf('#');
  const queryStart = url.indexOf('?');
  const query =
    queryStart >= 0
      ? url.slice(queryStart + 1, hashStart >= 0 ? hashStart : undefined)
      : '';
  const hash = hashStart >= 0 ? url.slice(hashStart + 1) : '';
  return new URLSearchParams([query, hash].filter(Boolean).join('&'));
}

function translateAuthError(message: string) {
  const normalized = message.toLowerCase();

  if (normalized.includes('invalid login credentials')) {
    return 'Email o password non corretti. Il VAR non può aiutarti.';
  }
  if (normalized.includes('password should be')) {
    return 'La password deve avere almeno 6 caratteri.';
  }
  if (normalized.includes('user already registered')) {
    return 'Questa email è già registrata. Prova ad accedere.';
  }

  return message;
}
