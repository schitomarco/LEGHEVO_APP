import { supabase } from '../lib/supabase';

export type SupportCategory =
  | 'account'
  | 'league'
  | 'auction_market'
  | 'lineup_results'
  | 'technical'
  | 'billing'
  | 'safety'
  | 'other';

export type SupportRequestStatus =
  | 'submitted'
  | 'in_progress'
  | 'waiting_user'
  | 'resolved'
  | 'closed';

export type SupportMessage = {
  id: string;
  authorType: 'user' | 'support';
  body: string;
  createdAt: string;
};

export type SupportEvent = {
  id: string;
  actorType: 'user' | 'support';
  eventType:
    | 'submitted'
    | 'user_replied'
    | 'support_replied'
    | 'status_changed'
    | 'closed';
  status: SupportRequestStatus;
  occurredAt: string;
};

export type SupportRequest = {
  id: string;
  leagueId: string | null;
  leagueName: string | null;
  category: SupportCategory;
  subject: string;
  status: SupportRequestStatus;
  createdAt: string;
  updatedAt: string;
  resolvedAt: string | null;
  closedAt: string | null;
  revision: number;
  protected: boolean;
  canReply: boolean;
  canClose: boolean;
  messages: SupportMessage[];
  events: SupportEvent[];
};

export type SupportCenter = {
  generatedAt: string;
  openCount: number;
  waitingUserCount: number;
  totalCount: number;
  protection: {
    guardedActionsReady: boolean;
    revisionControlReady: boolean;
    idempotencyReady: boolean;
  };
  requests: SupportRequest[];
};

export type CreateSupportRequestInput = {
  category: SupportCategory;
  subject: string;
  message: string;
  leagueId: string | null;
};

export async function fetchSupportCenter(): Promise<SupportCenter> {
  if (!supabase) {
    throw new Error('Il collegamento al backend non è configurato.');
  }

  const { data, error } = await supabase.rpc('get_my_support_center_v2');
  if (error) {
    throw new Error(translateSupportError(error.message));
  }

  return normalizeSupportCenter(data);
}

export async function createSupportRequest(
  input: CreateSupportRequestInput,
): Promise<{ data?: SupportRequest; error?: string }> {
  if (!supabase) {
    return { error: 'Il collegamento al backend non è configurato.' };
  }

  const { data, error } = await supabase.rpc(
    'create_my_support_request_guarded_v1',
    {
      p_category: input.category,
      p_idempotency_key: createOperationId(),
      p_league_id: input.leagueId,
      p_message: input.message.trim(),
      p_subject: input.subject.trim(),
    },
  );

  if (error) {
    return { error: translateSupportError(error.message) };
  }

  return { data: normalizeSupportRequest(data) };
}

export async function replyToSupportRequest(
  requestId: string,
  message: string,
  expectedRevision: number,
): Promise<{ error?: string }> {
  if (!supabase) {
    return { error: 'Il collegamento al backend non è configurato.' };
  }

  const { error } = await supabase.rpc(
    'reply_to_my_support_request_guarded_v1',
    {
      p_expected_revision: expectedRevision,
      p_idempotency_key: createOperationId(),
      p_message: message.trim(),
      p_request_id: requestId,
    },
  );

  if (error) {
    return { error: translateSupportError(error.message) };
  }

  return {};
}

export async function closeSupportRequest(
  requestId: string,
  expectedRevision: number,
): Promise<{ error?: string }> {
  if (!supabase) {
    return { error: 'Il collegamento al backend non è configurato.' };
  }

  const { error } = await supabase.rpc(
    'close_my_support_request_guarded_v1',
    {
      p_expected_revision: expectedRevision,
      p_idempotency_key: createOperationId(),
      p_request_id: requestId,
    },
  );

  if (error) {
    return { error: translateSupportError(error.message) };
  }

  return {};
}

export function subscribeToSupportCenter(
  userId: string,
  onChange: () => void,
) {
  if (!supabase) {
    return () => undefined;
  }

  const client = supabase;
  const channel = client
    .channel(`support-center-${userId}`)
    .on(
      'postgres_changes',
      {
        event: '*',
        schema: 'public',
        table: 'support_requests',
        filter: `user_id=eq.${userId}`,
      },
      onChange,
    )
    .on(
      'postgres_changes',
      {
        event: '*',
        schema: 'public',
        table: 'support_request_messages',
      },
      onChange,
    )
    .on(
      'postgres_changes',
      {
        event: '*',
        schema: 'public',
        table: 'support_request_events',
      },
      onChange,
    )
    .on(
      'postgres_changes',
      {
        event: '*',
        schema: 'public',
        table: 'support_request_action_runs',
        filter: `user_id=eq.${userId}`,
      },
      onChange,
    )
    .subscribe();

  return () => {
    void client.removeChannel(channel);
  };
}

export function normalizeSupportCenter(value: unknown): SupportCenter {
  const raw = asRecord(value);
  return {
    generatedAt: toStringValue(raw.generatedAt),
    openCount: toNumber(raw.openCount),
    waitingUserCount: toNumber(raw.waitingUserCount),
    totalCount: toNumber(raw.totalCount),
    protection: normalizeProtection(raw.protection),
    requests: Array.isArray(raw.requests)
      ? raw.requests.map(normalizeSupportRequest)
      : [],
  };
}

function normalizeSupportRequest(value: unknown): SupportRequest {
  const raw = asRecord(value);
  return {
    id: toStringValue(raw.id),
    leagueId: toNullableString(raw.leagueId),
    leagueName: toNullableString(raw.leagueName),
    category: normalizeCategory(raw.category),
    subject: toStringValue(raw.subject),
    status: normalizeStatus(raw.status),
    createdAt: toStringValue(raw.createdAt),
    updatedAt: toStringValue(raw.updatedAt),
    resolvedAt: toNullableString(raw.resolvedAt),
    closedAt: toNullableString(raw.closedAt),
    revision: Math.max(1, toNumber(raw.revision)),
    protected: Boolean(raw.protected),
    canReply: Boolean(raw.canReply),
    canClose: Boolean(raw.canClose),
    messages: Array.isArray(raw.messages)
      ? raw.messages.map((message) => {
          const messageRaw = asRecord(message);
          return {
            id: toStringValue(messageRaw.id),
            authorType:
              messageRaw.authorType === 'support' ? 'support' : 'user',
            body: toStringValue(messageRaw.body),
            createdAt: toStringValue(messageRaw.createdAt),
          };
        })
      : [],
    events: Array.isArray(raw.events)
      ? raw.events.map((event) => {
          const eventRaw = asRecord(event);
          return {
            id: toStringValue(eventRaw.id),
            actorType:
              eventRaw.actorType === 'support' ? 'support' : 'user',
            eventType: normalizeEventType(eventRaw.eventType),
            status: normalizeStatus(eventRaw.status),
            occurredAt: toStringValue(eventRaw.occurredAt),
          };
        })
      : [],
  };
}

function normalizeProtection(value: unknown): SupportCenter['protection'] {
  const raw = asRecord(value);
  return {
    guardedActionsReady: Boolean(raw.guardedActionsReady),
    revisionControlReady: Boolean(raw.revisionControlReady),
    idempotencyReady: Boolean(raw.idempotencyReady),
  };
}

function normalizeCategory(value: unknown): SupportCategory {
  if (
    value === 'account' ||
    value === 'league' ||
    value === 'auction_market' ||
    value === 'lineup_results' ||
    value === 'technical' ||
    value === 'billing' ||
    value === 'safety' ||
    value === 'other'
  ) {
    return value;
  }
  return 'other';
}

function normalizeStatus(value: unknown): SupportRequestStatus {
  if (
    value === 'submitted' ||
    value === 'in_progress' ||
    value === 'waiting_user' ||
    value === 'resolved' ||
    value === 'closed'
  ) {
    return value;
  }
  return 'submitted';
}

function normalizeEventType(value: unknown): SupportEvent['eventType'] {
  if (
    value === 'submitted' ||
    value === 'user_replied' ||
    value === 'support_replied' ||
    value === 'status_changed' ||
    value === 'closed'
  ) {
    return value;
  }
  return 'status_changed';
}

function translateSupportError(message: string) {
  const normalized = message.toLowerCase();
  if (
    normalized.includes('get_my_support_center_v2') ||
    normalized.includes('support_request_action_runs') ||
    normalized.includes('guarded_v1') ||
    (normalized.includes('function') && normalized.includes('does not exist'))
  ) {
    return 'Aggiorna prima il database LEGHEVO con il file 096.';
  }
  if (normalized.includes('massimo tre richieste')) {
    return 'Puoi avere al massimo tre richieste di assistenza aperte.';
  }
  if (normalized.includes('oggetto deve contenere')) {
    return 'L’oggetto deve contenere da 5 a 100 caratteri.';
  }
  if (normalized.includes('messaggio deve contenere')) {
    return 'Il messaggio deve contenere da 10 a 3000 caratteri.';
  }
  if (normalized.includes('risposta deve contenere')) {
    return 'La risposta deve contenere da 2 a 3000 caratteri.';
  }
  if (normalized.includes('soltanto una lega')) {
    return 'Puoi collegare soltanto una lega a cui partecipi.';
  }
  if (
    normalized.includes('altro dispositivo') ||
    normalized.includes('altro processo')
  ) {
    return 'La richiesta è cambiata su un altro dispositivo. Ricarica e riprova.';
  }
  if (normalized.includes('già conclusa') || normalized.includes('chiusa')) {
    return 'La richiesta è già conclusa.';
  }
  if (normalized.includes('non trovata')) {
    return 'La richiesta di assistenza non è disponibile.';
  }
  return message;
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
