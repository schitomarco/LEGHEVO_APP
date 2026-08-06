import { supabase } from '../lib/supabase';
import {
  MINIMUM_AGE_VERSION,
  PRIVACY_POLICY_VERSION,
  TERMS_VERSION,
} from '../legalDocuments';
import type { AuthOutcome } from '../hooks/useAuth';

export type PrivacyPreferences = {
  privacyPolicyVersion: string | null;
  privacyAcknowledgedAt: string | null;
  termsVersion: string | null;
  termsAcceptedAt: string | null;
  marketingConsent: boolean;
  marketingUpdatedAt: string | null;
  minimumAgeVersion: string | null;
  minimumAgeConfirmedAt: string | null;
  releaseKey: string | null;
  revision: number;
  acceptanceFingerprint: string | null;
  currentDocumentsAccepted: boolean;
  protected: boolean;
  certifiedActionCount: number;
  lastCertifiedAt: string | null;
  exportProtected: boolean;
  certifiedExportCount: number;
  exportRevision: number;
  lastExportedAt: string | null;
  lastExportFingerprint: string | null;
};

export type PrivacyPreferencesOutcome = {
  data?: PrivacyPreferences;
  error?: string;
};

export type PersonalDataExportOutcome = {
  data?: Record<string, unknown>;
  error?: string;
};

type PrivacyRow = {
  privacy_policy_version: string;
  privacy_acknowledged_at: string;
  terms_version: string;
  terms_accepted_at: string;
  marketing_consent: boolean;
  marketing_updated_at: string;
  minimum_age_version: string | null;
  minimum_age_confirmed_at: string | null;
};

export async function loadPrivacyPreferences(): Promise<PrivacyPreferencesOutcome> {
  if (!supabase) {
    return { error: 'Il backend non è configurato su questo dispositivo.' };
  }

  const protectedExport = await supabase.rpc('get_my_privacy_center_v4');
  if (!protectedExport.error) {
    return { data: normalizePrivacyPreferences(protectedExport.data) };
  }

  if (!isMissingGuardedPrivacyFunction(protectedExport.error.message)) {
    return { error: translatePrivacyError(protectedExport.error.message) };
  }

  const guarded = await supabase.rpc('get_my_privacy_center_v3');
  if (!guarded.error) {
    return { data: normalizePrivacyPreferences(guarded.data) };
  }

  if (!isMissingGuardedPrivacyFunction(guarded.error.message)) {
    return { error: translatePrivacyError(guarded.error.message) };
  }

  const { data, error } = await supabase
    .from('user_privacy_preferences')
    .select(
      'privacy_policy_version, privacy_acknowledged_at, terms_version, terms_accepted_at, marketing_consent, marketing_updated_at, minimum_age_version, minimum_age_confirmed_at',
    )
    .maybeSingle();

  if (error) {
    return { error: translatePrivacyError(error.message) };
  }

  return {
    data: data ? mapPrivacyRow(data as PrivacyRow) : emptyPreferences(),
  };
}

export function subscribeToPrivacyCenter(
  userId: string,
  onChange: () => void,
) {
  if (!supabase) {
    return () => undefined;
  }

  const client = supabase;
  const channel = client
    .channel(`privacy-center-${userId}`)
    .on(
      'postgres_changes',
      {
        event: '*',
        schema: 'public',
        table: 'user_privacy_preferences',
        filter: `user_id=eq.${userId}`,
      },
      onChange,
    )
    .on(
      'postgres_changes',
      {
        event: '*',
        schema: 'public',
        table: 'legal_acceptance_action_runs',
        filter: `user_id=eq.${userId}`,
      },
      onChange,
    )
    .on(
      'postgres_changes',
      {
        event: '*',
        schema: 'public',
        table: 'personal_data_export_runs',
        filter: `user_id=eq.${userId}`,
      },
      onChange,
    )
    .subscribe();

  return () => {
    void client.removeChannel(channel);
  };
}

export async function savePrivacyPreferences(): Promise<
  PrivacyPreferencesOutcome & AuthOutcome
> {
  if (!supabase) {
    return { error: 'Il backend non è configurato su questo dispositivo.' };
  }

  const current = await loadPrivacyPreferences();
  if (current.error) {
    return { error: current.error };
  }

  const guarded = await supabase.rpc(
    'save_my_privacy_preferences_guarded_v1',
    {
      p_expected_revision: current.data?.revision ?? 0,
      p_idempotency_key: createOperationId(),
      p_minimum_age_version: MINIMUM_AGE_VERSION,
      p_privacy_policy_version: PRIVACY_POLICY_VERSION,
      p_terms_version: TERMS_VERSION,
    },
  );

  if (!guarded.error) {
    return {
      data: normalizePrivacyPreferences(guarded.data),
      notice:
        'Documenti registrati con revisione certificata. Riceverai soltanto comunicazioni di servizio.',
    };
  }

  if (!isMissingGuardedPrivacyFunction(guarded.error.message)) {
    return { error: translatePrivacyError(guarded.error.message) };
  }

  const legacy = await supabase.rpc('save_my_privacy_preferences', {
    p_marketing_consent: false,
    p_privacy_policy_version: PRIVACY_POLICY_VERSION,
    p_terms_version: TERMS_VERSION,
  });

  if (legacy.error) {
    return { error: translatePrivacyError(legacy.error.message) };
  }

  return {
    data: normalizePrivacyPreferences(legacy.data),
    notice: 'Documenti registrati. Riceverai soltanto comunicazioni di servizio.',
  };
}

export async function exportPersonalData(): Promise<PersonalDataExportOutcome> {
  if (!supabase) {
    return { error: 'Il backend non è configurato su questo dispositivo.' };
  }

  const guarded = await supabase.rpc(
    'export_my_personal_data_guarded_v1',
    { p_idempotency_key: createOperationId() },
  );

  if (!guarded.error && guarded.data && typeof guarded.data === 'object') {
    return { data: guarded.data as Record<string, unknown> };
  }

  if (guarded.error && !isMissingGuardedPrivacyFunction(guarded.error.message)) {
    return { error: translatePrivacyError(guarded.error.message) };
  }

  const legacy = await supabase.rpc('export_my_personal_data_v5');
  if (legacy.error || !legacy.data || typeof legacy.data !== 'object') {
    return {
      error: translatePrivacyError(
        legacy.error?.message ??
          'Non è stato possibile preparare la copia dei dati.',
      ),
    };
  }

  return { data: legacy.data as Record<string, unknown> };
}

function normalizePrivacyPreferences(value: unknown): PrivacyPreferences {
  const raw = asRecord(value);
  const privacyPolicyVersion = nullableString(
    raw.privacyPolicyVersion ?? raw.privacy_policy_version,
  );
  const termsVersion = nullableString(raw.termsVersion ?? raw.terms_version);
  const minimumAgeVersion = nullableString(
    raw.minimumAgeVersion ?? raw.minimum_age_version,
  );
  const minimumAgeConfirmedAt = nullableString(
    raw.minimumAgeConfirmedAt ?? raw.minimum_age_confirmed_at,
  );

  return {
    privacyPolicyVersion,
    privacyAcknowledgedAt: nullableString(
      raw.privacyAcknowledgedAt ?? raw.privacy_acknowledged_at,
    ),
    termsVersion,
    termsAcceptedAt: nullableString(
      raw.termsAcceptedAt ?? raw.terms_accepted_at,
    ),
    marketingConsent: Boolean(
      raw.marketingConsent ?? raw.marketing_consent ?? false,
    ),
    marketingUpdatedAt: nullableString(
      raw.marketingUpdatedAt ?? raw.marketing_updated_at,
    ),
    minimumAgeVersion,
    minimumAgeConfirmedAt,
    releaseKey: nullableString(raw.releaseKey ?? raw.release_key),
    revision: Math.max(0, numberValue(raw.revision)),
    acceptanceFingerprint: nullableString(
      raw.acceptanceFingerprint ?? raw.acceptance_fingerprint,
    ),
    currentDocumentsAccepted:
      typeof raw.currentDocumentsAccepted === 'boolean'
        ? raw.currentDocumentsAccepted
        : privacyPolicyVersion === PRIVACY_POLICY_VERSION &&
          termsVersion === TERMS_VERSION &&
          minimumAgeVersion === MINIMUM_AGE_VERSION &&
          Boolean(minimumAgeConfirmedAt),
    protected: Boolean(raw.protected),
    certifiedActionCount: Math.max(
      0,
      numberValue(raw.certifiedActionCount),
    ),
    lastCertifiedAt: nullableString(raw.lastCertifiedAt),
    exportProtected: Boolean(raw.exportProtected),
    certifiedExportCount: Math.max(
      0,
      numberValue(raw.certifiedExportCount),
    ),
    exportRevision: Math.max(0, numberValue(raw.exportRevision)),
    lastExportedAt: nullableString(raw.lastExportedAt),
    lastExportFingerprint: nullableString(raw.lastExportFingerprint),
  };
}

function mapPrivacyRow(row: PrivacyRow): PrivacyPreferences {
  return {
    privacyPolicyVersion: row.privacy_policy_version,
    privacyAcknowledgedAt: row.privacy_acknowledged_at,
    termsVersion: row.terms_version,
    termsAcceptedAt: row.terms_accepted_at,
    marketingConsent: row.marketing_consent,
    marketingUpdatedAt: row.marketing_updated_at,
    minimumAgeVersion: row.minimum_age_version,
    minimumAgeConfirmedAt: row.minimum_age_confirmed_at,
    releaseKey: null,
    revision: row.minimum_age_confirmed_at ? 1 : 0,
    acceptanceFingerprint: null,
    currentDocumentsAccepted:
      row.privacy_policy_version === PRIVACY_POLICY_VERSION &&
      row.terms_version === TERMS_VERSION &&
      row.minimum_age_version === MINIMUM_AGE_VERSION &&
      Boolean(row.minimum_age_confirmed_at),
    protected: false,
    certifiedActionCount: 0,
    lastCertifiedAt: null,
    exportProtected: false,
    certifiedExportCount: 0,
    exportRevision: 0,
    lastExportedAt: null,
    lastExportFingerprint: null,
  };
}

function emptyPreferences(): PrivacyPreferences {
  return {
    privacyPolicyVersion: null,
    privacyAcknowledgedAt: null,
    termsVersion: null,
    termsAcceptedAt: null,
    marketingConsent: false,
    marketingUpdatedAt: null,
    minimumAgeVersion: null,
    minimumAgeConfirmedAt: null,
    releaseKey: null,
    revision: 0,
    acceptanceFingerprint: null,
    currentDocumentsAccepted: false,
    protected: false,
    certifiedActionCount: 0,
    lastCertifiedAt: null,
    exportProtected: false,
    certifiedExportCount: 0,
    exportRevision: 0,
    lastExportedAt: null,
    lastExportFingerprint: null,
  };
}

function translatePrivacyError(message: string) {
  const normalized = message.toLowerCase();

  if (
    normalized.includes('aggiornati su un altro dispositivo') ||
    normalized.includes('revisione dei documenti')
  ) {
    return 'I documenti sono stati aggiornati su un altro dispositivo. Riapri la schermata e riprova.';
  }
  if (normalized.includes('identificativo operazione')) {
    return 'La richiesta non è stata accettata. Riprova una sola volta.';
  }
  if (
    normalized.includes('dati sono cambiati durante il tentativo') ||
    normalized.includes('copia dati prodotta non è valida')
  ) {
    return 'I dati sono cambiati durante la preparazione. Avvia nuovamente l’esportazione.';
  }
  if (normalized.includes('export_my_personal_data_guarded_v1')) {
    return 'Aggiorna il database LEGHEVO con la migrazione 102 prima di esportare i dati.';
  }
  if (
    normalized.includes('minimum_age') ||
    normalized.includes('legal_document_releases') ||
    normalized.includes('legal_acceptance') ||
    normalized.includes('get_my_privacy_center_v3') ||
    normalized.includes('get_my_privacy_center_v4') ||
    normalized.includes('save_my_privacy_preferences_guarded_v1')
  ) {
    return 'Aggiorna il database LEGHEVO con la migrazione 099 prima di continuare.';
  }
  if (
    normalized.includes('user_privacy_preferences') ||
    normalized.includes('save_my_privacy_preferences') ||
    normalized.includes('export_my_personal_data') ||
    normalized.includes('does not exist') ||
    normalized.includes('schema cache')
  ) {
    return normalized.includes('export_my_personal_data_v5')
      ? 'Aggiorna il database LEGHEVO con il file 056 prima di esportare i dati.'
      : 'Aggiorna il database LEGHEVO con la migrazione 099 prima di continuare.';
  }
  if (normalized.includes('versione dei documenti')) {
    return 'La versione dei documenti non è aggiornata. Riavvia LEGHEVO.';
  }

  return message;
}

function isMissingGuardedPrivacyFunction(message: string) {
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

function nullableString(value: unknown) {
  return typeof value === 'string' && value ? value : null;
}

function numberValue(value: unknown) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : 0;
}
