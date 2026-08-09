import { supabase } from '../lib/supabase';
import type { AuthOutcome } from '../hooks/useAuth';

const PASSWORD_RESET_REDIRECT_URL = 'leghevo://reset-password';

export type AccountCenterState = {
  userId: string;
  displayName: string;
  email: string;
  emailVerified: boolean;
  revision: number;
  profileFingerprint: string | null;
  deletedAt: string | null;
  protected: boolean;
  certifiedActionCount: number;
  lastCertifiedAt: string | null;
  securityRevision: number;
  securityFingerprint: string | null;
  securityMonitoredSince: string | null;
  lastPasswordChangedAt: string | null;
  lastEmailChangedAt: string | null;
  lastEmailVerifiedAt: string | null;
  securityProtected: boolean;
  certifiedSecurityEventCount: number;
  lastSecurityEventAt: string | null;
  serviceHubRevision: number;
  serviceHubFingerprint: string | null;
  serviceHubLastActivityAt: string | null;
  protectedServiceCount: number;
  totalServiceCount: number;
  serviceHubProtected: boolean;
  accountServicesModelClosed: boolean;
  accountServicesModelVersion: number;
  accountServicesCertifiedAt: string | null;
  accountServicesSchemaFingerprint: string | null;
};

export function passwordResetRedirectUrl() {
  return PASSWORD_RESET_REDIRECT_URL;
}

export async function sendPasswordReset(
  email: string,
): Promise<AuthOutcome> {
  if (!supabase) {
    return { error: 'Il backend non è configurato su questo dispositivo.' };
  }

  const { error } = await supabase.auth.resetPasswordForEmail(email.trim(), {
    redirectTo: passwordResetRedirectUrl(),
  });

  return error
    ? { error: translateAccountError(error.message) }
    : {
        notice:
          'Email inviata. Apri il link sul telefono per scegliere la nuova password.',
      };
}

export async function fetchAccountCenter(): Promise<AccountCenterState> {
  if (!supabase) {
    throw new Error('Il backend non è configurato su questo dispositivo.');
  }

  const guardedV5 = await supabase.rpc('get_my_account_center_v5');
  if (!guardedV5.error) {
    return normalizeAccountCenter(guardedV5.data);
  }

  if (!isMissingGuardedAccountFunction(guardedV5.error.message)) {
    throw new Error(translateAccountError(guardedV5.error.message));
  }

  const guardedV4 = await supabase.rpc('get_my_account_center_v4');
  if (!guardedV4.error) {
    return normalizeAccountCenter(guardedV4.data);
  }

  if (!isMissingGuardedAccountFunction(guardedV4.error.message)) {
    throw new Error(translateAccountError(guardedV4.error.message));
  }

  const guardedV3 = await supabase.rpc('get_my_account_center_v3');
  if (!guardedV3.error) {
    return normalizeAccountCenter(guardedV3.data);
  }

  if (!isMissingGuardedAccountFunction(guardedV3.error.message)) {
    throw new Error(translateAccountError(guardedV3.error.message));
  }

  const guardedV2 = await supabase.rpc('get_my_account_center_v2');
  if (!guardedV2.error) {
    return normalizeAccountCenter(guardedV2.data);
  }

  if (!isMissingGuardedAccountFunction(guardedV2.error.message)) {
    throw new Error(translateAccountError(guardedV2.error.message));
  }

  const { data, error } = await supabase.auth.getUser();
  if (error || !data.user) {
    throw new Error(
      translateAccountError(error?.message ?? 'Profilo non trovato.'),
    );
  }

  return {
    userId: data.user.id,
    displayName:
      String(data.user.user_metadata?.display_name ?? '').trim() ||
      data.user.email?.split('@')[0] ||
      'Mister',
    email: data.user.email ?? '',
    emailVerified: Boolean(data.user.email_confirmed_at),
    revision: 1,
    profileFingerprint: null,
    deletedAt: null,
    protected: false,
    certifiedActionCount: 0,
    lastCertifiedAt: null,
    securityRevision: 0,
    securityFingerprint: null,
    securityMonitoredSince: null,
    lastPasswordChangedAt: null,
    lastEmailChangedAt: null,
    lastEmailVerifiedAt: null,
    securityProtected: false,
    certifiedSecurityEventCount: 0,
    lastSecurityEventAt: null,
    serviceHubRevision: 0,
    serviceHubFingerprint: null,
    serviceHubLastActivityAt: null,
    protectedServiceCount: 0,
    totalServiceCount: 8,
    serviceHubProtected: false,
    accountServicesModelClosed: false,
    accountServicesModelVersion: 0,
    accountServicesCertifiedAt: null,
    accountServicesSchemaFingerprint: null,
  };
}

export function subscribeToAccountCenter(
  userId: string,
  onChange: () => void,
) {
  if (!supabase) {
    return () => undefined;
  }

  const client = supabase;
  const channel = client
    .channel(`account-center-${userId}`)
    .on(
      'postgres_changes',
      {
        event: '*',
        schema: 'public',
        table: 'account_action_runs',
        filter: `user_id=eq.${userId}`,
      },
      onChange,
    )
    .on(
      'postgres_changes',
      {
        event: '*',
        schema: 'public',
        table: 'account_security_states',
        filter: `user_id=eq.${userId}`,
      },
      onChange,
    )
    .on(
      'postgres_changes',
      {
        event: '*',
        schema: 'public',
        table: 'account_security_events',
        filter: `user_id=eq.${userId}`,
      },
      onChange,
    )
    .on(
      'postgres_changes',
      {
        event: '*',
        schema: 'public',
        table: 'account_service_states',
        filter: `user_id=eq.${userId}`,
      },
      onChange,
    )
    .on(
      'postgres_changes',
      {
        event: '*',
        schema: 'public',
        table: 'account_service_events',
        filter: `user_id=eq.${userId}`,
      },
      onChange,
    )
    .subscribe();

  return () => {
    void client.removeChannel(channel);
  };
}

export async function saveDisplayName(
  displayName: string,
): Promise<AuthOutcome> {
  if (!supabase) {
    return { error: 'Il backend non è configurato su questo dispositivo.' };
  }

  const normalized = displayName.trim();

  try {
    const center = await fetchAccountCenter();
    const guarded = await supabase.rpc('update_my_profile_guarded_v1', {
      p_display_name: normalized,
      p_expected_revision: center.revision,
      p_idempotency_key: createOperationId(),
    });

    if (guarded.error) {
      if (!isMissingGuardedAccountFunction(guarded.error.message)) {
        return { error: translateAccountError(guarded.error.message) };
      }

      const legacy = await supabase.rpc('update_my_profile', {
        p_display_name: normalized,
      });
      if (legacy.error) {
        return { error: translateAccountError(legacy.error.message) };
      }
    }

    // La RPC protetta aggiorna anche auth.users in modo atomico. Il refresh
    // riallinea subito la sessione locale e il nome mostrato nell'app.
    await supabase.auth.refreshSession();
    return { notice: 'Nome aggiornato. Lo spogliatoio prende nota.' };
  } catch (error) {
    return {
      error: translateAccountError(
        error instanceof Error ? error.message : 'Aggiornamento non riuscito.',
      ),
    };
  }
}

export async function saveNewPassword(
  password: string,
): Promise<AuthOutcome> {
  if (!supabase) {
    return { error: 'Il backend non è configurato su questo dispositivo.' };
  }

  const { error } = await supabase.auth.updateUser({ password });
  if (error) {
    return { error: translateAccountError(error.message) };
  }

  await supabase.auth.refreshSession();
  return {
    notice: 'Password aggiornata e registrata nel Centro Sicurezza.',
  };
}

export async function removeCurrentAccount(): Promise<AuthOutcome> {
  if (!supabase) {
    return { error: 'Il backend non è configurato su questo dispositivo.' };
  }

  try {
    const center = await fetchAccountCenter();
    const guarded = await supabase.rpc('delete_my_account_guarded_v1', {
      p_expected_revision: center.revision,
      p_idempotency_key: createOperationId(),
    });

    if (guarded.error) {
      if (!isMissingGuardedAccountFunction(guarded.error.message)) {
        return { error: translateAccountError(guarded.error.message) };
      }

      const legacy = await supabase.rpc('delete_my_account');
      if (legacy.error || legacy.data !== true) {
        return {
          error: translateAccountError(
            legacy.error?.message ??
              'Non è stato possibile eliminare l’account.',
          ),
        };
      }
    }

    // L'utente Auth è già stato rimosso dalla RPC. Il logout locale serve
    // soltanto a eliminare eventuali token rimasti sul dispositivo.
    await supabase.auth.signOut({ scope: 'local' });
    return { notice: 'Account eliminato definitivamente.' };
  } catch (error) {
    return {
      error: translateAccountError(
        error instanceof Error ? error.message : 'Eliminazione non riuscita.',
      ),
    };
  }
}

export function translateAccountError(message: string) {
  const normalized = message.toLowerCase();

  if (normalized.includes('rate limit')) {
    return 'Hai fatto troppi tentativi. Aspetta qualche minuto e riprova.';
  }
  if (
    normalized.includes('password should be') ||
    normalized.includes('weak password')
  ) {
    return 'Scegli una password di almeno 8 caratteri.';
  }
  if (normalized.includes('same password')) {
    return 'La nuova password deve essere diversa dalla precedente.';
  }
  if (normalized.includes('auth session missing')) {
    return 'La sessione di recupero non è pronta. Richiedi una nuova email e riapri il link sul telefono.';
  }
  if (
    normalized.includes('aggiornato su un altro dispositivo') ||
    normalized.includes('revisione profilo')
  ) {
    return 'Il profilo è cambiato su un altro dispositivo. Riapri la schermata e riprova.';
  }
  if (normalized.includes('identificativo operazione')) {
    return 'La richiesta non è stata accettata. Riprova una sola volta.';
  }
  if (
    normalized.includes('update_my_profile') ||
    normalized.includes('delete_my_account') ||
    normalized.includes('get_my_account_center') ||
    normalized.includes('account_security_') ||
    normalized.includes('does not exist') ||
    normalized.includes('schema cache')
  ) {
    return 'Aggiorna prima il database LEGHEVO con le migrazioni account fino alla 104.';
  }
  return message;
}

function normalizeAccountCenter(value: unknown): AccountCenterState {
  const raw = asRecord(value);
  const serviceHub = asRecord(raw.serviceHub);
  const modelClosure = asRecord(raw.accountServicesModelClosure);
  return {
    userId: toStringValue(raw.userId),
    displayName: toStringValue(raw.displayName),
    email: toStringValue(raw.email),
    emailVerified: Boolean(raw.emailVerified),
    revision: Math.max(1, toNumber(raw.revision)),
    profileFingerprint: toNullableString(raw.profileFingerprint),
    deletedAt: toNullableString(raw.deletedAt),
    protected: Boolean(raw.protected),
    certifiedActionCount: Math.max(0, toNumber(raw.certifiedActionCount)),
    lastCertifiedAt: toNullableString(raw.lastCertifiedAt),
    securityRevision: Math.max(0, toNumber(raw.securityRevision)),
    securityFingerprint: toNullableString(raw.securityFingerprint),
    securityMonitoredSince: toNullableString(raw.securityMonitoredSince),
    lastPasswordChangedAt: toNullableString(raw.lastPasswordChangedAt),
    lastEmailChangedAt: toNullableString(raw.lastEmailChangedAt),
    lastEmailVerifiedAt: toNullableString(raw.lastEmailVerifiedAt),
    securityProtected: Boolean(raw.securityProtected),
    certifiedSecurityEventCount: Math.max(
      0,
      toNumber(raw.certifiedSecurityEventCount),
    ),
    lastSecurityEventAt: toNullableString(raw.lastSecurityEventAt),
    serviceHubRevision: Math.max(0, toNumber(serviceHub.revision)),
    serviceHubFingerprint: toNullableString(serviceHub.stateFingerprint),
    serviceHubLastActivityAt: toNullableString(serviceHub.lastActivityAt),
    protectedServiceCount: Math.max(
      0,
      toNumber(serviceHub.protectedServiceCount),
    ),
    totalServiceCount: Math.max(8, toNumber(serviceHub.totalServiceCount)),
    serviceHubProtected: Boolean(serviceHub.allProtected),
    accountServicesModelClosed: Boolean(modelClosure.healthy),
    accountServicesModelVersion: Math.max(
      0,
      toNumber(modelClosure.modelVersion),
    ),
    accountServicesCertifiedAt: toNullableString(modelClosure.certifiedAt),
    accountServicesSchemaFingerprint: toNullableString(
      modelClosure.schemaFingerprint,
    ),
  };
}

function isMissingGuardedAccountFunction(message: string) {
  const normalized = message.toLowerCase();
  return (
    normalized.includes('does not exist') ||
    normalized.includes('schema cache') ||
    normalized.includes('could not find the function')
  );
}

function createOperationId() {
  return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (token) => {
    const value = Math.floor(Math.random() * 16);
    const normalized = token === 'x' ? value : (value & 0x3) | 0x8;
    return normalized.toString(16);
  });
}

function asRecord(value: unknown): Record<string, unknown> {
  return value && typeof value === 'object'
    ? (value as Record<string, unknown>)
    : {};
}

function toStringValue(value: unknown) {
  return typeof value === 'string' ? value : '';
}

function toNullableString(value: unknown) {
  return typeof value === 'string' && value ? value : null;
}

function toNumber(value: unknown) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : 0;
}
