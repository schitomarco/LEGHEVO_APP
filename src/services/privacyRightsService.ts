import { supabase } from '../lib/supabase';

export type PrivacyRightType =
  | 'access'
  | 'rectification'
  | 'portability'
  | 'restriction'
  | 'objection'
  | 'erasure';

export type PrivacyRequestStatus =
  | 'submitted'
  | 'in_review'
  | 'fulfilled'
  | 'rejected'
  | 'cancelled';

export type PrivacyRequestEvent = {
  id: string;
  eventType: 'submitted' | 'status_changed' | 'cancelled';
  status: PrivacyRequestStatus;
  note: string | null;
  occurredAt: string;
};

export type PrivacyRightsRequest = {
  id: string;
  requestType: PrivacyRightType;
  details: string | null;
  status: PrivacyRequestStatus;
  responseNote: string | null;
  submittedAt: string;
  dueAt: string;
  updatedAt: string;
  closedAt: string | null;
  canCancel: boolean;
  revision: number;
  protected: boolean;
  events: PrivacyRequestEvent[];
};

export type PrivacyRightsCenter = {
  generatedAt: string;
  openCount: number;
  totalCount: number;
  protection: {
    guardedActionsReady: boolean;
    revisionControlReady: boolean;
    idempotencyReady: boolean;
  };
  requests: PrivacyRightsRequest[];
};

type PrivacyRightsOutcome =
  | { data: PrivacyRightsRequest; error?: never }
  | { data?: never; error: string };

export async function fetchPrivacyRightsCenter(): Promise<PrivacyRightsCenter> {
  if (!supabase) {
    throw new Error('Il collegamento al backend non è configurato.');
  }

  const { data, error } = await supabase.rpc('get_my_data_rights_center_v2');
  if (error) {
    throw new Error(translatePrivacyRightsError(error.message));
  }

  return normalizePrivacyRightsCenter(data);
}

export async function submitPrivacyRightsRequest(
  requestType: PrivacyRightType,
  details: string,
): Promise<PrivacyRightsOutcome> {
  if (!supabase) {
    return { error: 'Il collegamento al backend non è configurato.' };
  }

  const { data, error } = await supabase.rpc(
    'submit_my_data_rights_request_guarded_v1',
    {
      p_details: details.trim() || null,
      p_idempotency_key: createOperationId(),
      p_request_type: requestType,
    },
  );

  if (error) {
    return { error: translatePrivacyRightsError(error.message) };
  }

  return { data: normalizePrivacyRightsRequest(data) };
}

export async function cancelPrivacyRightsRequest(
  requestId: string,
  expectedRevision: number,
): Promise<{ error?: string }> {
  if (!supabase) {
    return { error: 'Il collegamento al backend non è configurato.' };
  }

  const { error } = await supabase.rpc(
    'cancel_my_data_rights_request_guarded_v1',
    {
      p_expected_revision: expectedRevision,
      p_idempotency_key: createOperationId(),
      p_request_id: requestId,
    },
  );

  if (error) {
    return { error: translatePrivacyRightsError(error.message) };
  }

  return {};
}


export function subscribeToPrivacyRightsCenter(
  userId: string,
  onChange: () => void,
) {
  if (!supabase) {
    return () => undefined;
  }

  const client = supabase;
  const channel = client
    .channel(`privacy-rights-${userId}`)
    .on(
      'postgres_changes',
      {
        event: '*',
        schema: 'public',
        table: 'data_rights_requests',
        filter: `user_id=eq.${userId}`,
      },
      onChange,
    )
    .on(
      'postgres_changes',
      {
        event: '*',
        schema: 'public',
        table: 'data_rights_request_events',
      },
      onChange,
    )
    .on(
      'postgres_changes',
      {
        event: '*',
        schema: 'public',
        table: 'data_rights_request_action_runs',
        filter: `user_id=eq.${userId}`,
      },
      onChange,
    )
    .subscribe();

  return () => {
    void client.removeChannel(channel);
  };
}

export function normalizePrivacyRightsCenter(
  value: unknown,
): PrivacyRightsCenter {
  const raw = asRecord(value);
  return {
    generatedAt: toStringValue(raw.generatedAt),
    openCount: toNumber(raw.openCount),
    totalCount: toNumber(raw.totalCount),
    protection: normalizeProtection(raw.protection),
    requests: Array.isArray(raw.requests)
      ? raw.requests.map(normalizePrivacyRightsRequest)
      : [],
  };
}

function normalizePrivacyRightsRequest(value: unknown): PrivacyRightsRequest {
  const raw = asRecord(value);
  return {
    id: toStringValue(raw.id),
    requestType: normalizeRequestType(raw.requestType),
    details: toNullableString(raw.details),
    status: normalizeRequestStatus(raw.status),
    responseNote: toNullableString(raw.responseNote),
    submittedAt: toStringValue(raw.submittedAt),
    dueAt: toStringValue(raw.dueAt),
    updatedAt: toStringValue(raw.updatedAt),
    closedAt: toNullableString(raw.closedAt),
    canCancel: Boolean(raw.canCancel),
    revision: Math.max(1, toNumber(raw.revision)),
    protected: Boolean(raw.protected),
    events: Array.isArray(raw.events)
      ? raw.events.map((event) => {
          const eventRaw = asRecord(event);
          return {
            id: toStringValue(eventRaw.id),
            eventType: normalizeEventType(eventRaw.eventType),
            status: normalizeRequestStatus(eventRaw.status),
            note: toNullableString(eventRaw.note),
            occurredAt: toStringValue(eventRaw.occurredAt),
          };
        })
      : [],
  };
}

function normalizeRequestType(value: unknown): PrivacyRightType {
  if (
    value === 'access' ||
    value === 'rectification' ||
    value === 'portability' ||
    value === 'restriction' ||
    value === 'objection' ||
    value === 'erasure'
  ) {
    return value;
  }
  return 'access';
}

function normalizeRequestStatus(value: unknown): PrivacyRequestStatus {
  if (
    value === 'submitted' ||
    value === 'in_review' ||
    value === 'fulfilled' ||
    value === 'rejected' ||
    value === 'cancelled'
  ) {
    return value;
  }
  return 'submitted';
}

function normalizeEventType(
  value: unknown,
): PrivacyRequestEvent['eventType'] {
  if (
    value === 'submitted' ||
    value === 'status_changed' ||
    value === 'cancelled'
  ) {
    return value;
  }
  return 'status_changed';
}

function translatePrivacyRightsError(message: string) {
  const normalized = message.toLowerCase();
  if (
    normalized.includes('get_my_data_rights_center') ||
    normalized.includes('submit_my_data_rights_request') ||
    normalized.includes('cancel_my_data_rights_request') ||
    normalized.includes('data_rights_request_action_runs') ||
    normalized.includes('export_my_personal_data_v2') ||
    normalized.includes('data_rights_requests') ||
    (normalized.includes('function') && normalized.includes('does not exist'))
  ) {
    return 'Aggiorna prima il database LEGHEVO con il file 095.';
  }
  if (normalized.includes('stesso tipo ancora aperta')) {
    return 'Hai già una richiesta dello stesso tipo ancora aperta.';
  }
  if (normalized.includes('almeno 10 caratteri')) {
    return 'Descrivi la richiesta con almeno 10 caratteri.';
  }
  if (normalized.includes('massimo 2000')) {
    return 'La descrizione può contenere al massimo 2000 caratteri.';
  }
  if (normalized.includes('altro dispositivo') || normalized.includes('altro processo')) {
    return 'La richiesta è cambiata su un altro dispositivo. Ricarica e riprova.';
  }
  if (normalized.includes('non può più essere annullata')) {
    return 'La richiesta è già stata lavorata e non può più essere annullata.';
  }
  if (normalized.includes('non trovata')) {
    return 'La richiesta privacy non è disponibile.';
  }
  return message;
}


function normalizeProtection(value: unknown): PrivacyRightsCenter['protection'] {
  const raw = asRecord(value);
  return {
    guardedActionsReady: Boolean(raw.guardedActionsReady),
    revisionControlReady: Boolean(raw.revisionControlReady),
    idempotencyReady: Boolean(raw.idempotencyReady),
  };
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
