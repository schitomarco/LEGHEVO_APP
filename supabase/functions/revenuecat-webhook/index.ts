import { createClient } from 'npm:@supabase/supabase-js@2';

const jsonHeaders = { 'Content-Type': 'application/json' };
const premiumEntitlementId = 'premium';

type RevenueCatEvent = {
  id?: unknown;
  type?: unknown;
  app_user_id?: unknown;
  original_app_user_id?: unknown;
  aliases?: unknown;
  entitlement_id?: unknown;
  entitlement_ids?: unknown;
  store?: unknown;
  environment?: unknown;
  product_id?: unknown;
  new_product_id?: unknown;
  original_transaction_id?: unknown;
  transaction_id?: unknown;
  event_timestamp_ms?: unknown;
  purchased_at_ms?: unknown;
  expiration_at_ms?: unknown;
  grace_period_expiration_at_ms?: unknown;
  period_type?: unknown;
};

type NormalizedSubscriptionEvent = {
  eventId: string;
  userId: string;
  store: 'apple' | 'google' | 'test';
  environment: 'sandbox' | 'production';
  eventType: string;
  productId: string | null;
  originalTransactionId: string | null;
  status:
    | 'inactive'
    | 'trialing'
    | 'active'
    | 'grace_period'
    | 'billing_retry'
    | 'expired'
    | 'revoked';
  occurredAt: string;
  currentPeriodStartedAt: string | null;
  currentPeriodEndsAt: string | null;
  gracePeriodEndsAt: string | null;
  willRenew: boolean;
};

Deno.serve(async (request) => {
  if (request.method !== 'POST') {
    return json({ error: 'Metodo non consentito.' }, 405);
  }

  const expectedAuthorization = Deno.env.get(
    'REVENUECAT_WEBHOOK_AUTHORIZATION',
  );
  if (
    !expectedAuthorization ||
    !safeEqual(request.headers.get('authorization') ?? '', expectedAuthorization)
  ) {
    return json({ error: 'Webhook non autorizzato.' }, 401);
  }

  const rawBody = await request.text();
  let payload: { api_version?: unknown; event?: RevenueCatEvent };
  try {
    payload = JSON.parse(rawBody) as typeof payload;
  } catch {
    return json({ error: 'Payload JSON non valido.' }, 400);
  }

  if (payload.api_version !== '1.0' || !payload.event) {
    return json({ error: 'Formato webhook RevenueCat non supportato.' }, 400);
  }

  const normalized = normalizeEvent(payload.event);
  if ('ignored' in normalized) {
    return json({ ok: true, ignored: normalized.ignored });
  }
  if ('error' in normalized) {
    return json({ error: normalized.error }, 400);
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL');
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!supabaseUrl || !serviceRoleKey) {
    return json({ error: 'Backend del webhook non configurato.' }, 500);
  }

  const fingerprint = await sha256(rawBody);
  const supabase = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const event = normalized.event;
  const { data, error } = await supabase.rpc(
    'record_commercial_subscription_event_v1',
    {
      p_event_id: event.eventId,
      p_user_id: event.userId,
      p_store: event.store,
      p_environment: event.environment,
      p_event_type: event.eventType,
      p_product_id: event.productId,
      p_original_transaction_id: event.originalTransactionId,
      p_status: event.status,
      p_occurred_at: event.occurredAt,
      p_current_period_started_at: event.currentPeriodStartedAt,
      p_current_period_ends_at: event.currentPeriodEndsAt,
      p_grace_period_ends_at: event.gracePeriodEndsAt,
      p_will_renew: event.willRenew,
      p_payload_fingerprint: fingerprint,
    },
  );

  if (error) {
    console.error('RevenueCat event rejected by database', {
      eventId: event.eventId,
      code: error.code,
      message: error.message,
    });
    return json({ error: 'Evento non registrato.' }, 500);
  }

  return json({ ok: true, result: data });
});

function normalizeEvent(
  raw: RevenueCatEvent,
):
  | { event: NormalizedSubscriptionEvent }
  | { ignored: string }
  | { error: string } {
  const eventType = text(raw.type);
  const eventId = text(raw.id);
  if (!eventType || !eventId) {
    return { error: 'Evento senza tipo o identificativo.' };
  }

  if (eventType === 'TEST') {
    return { ignored: 'dashboard_test' };
  }

  const entitlementIds = Array.isArray(raw.entitlement_ids)
    ? raw.entitlement_ids.filter((value): value is string => typeof value === 'string')
    : [];
  const belongsToPremium =
    raw.entitlement_id === premiumEntitlementId ||
    entitlementIds.includes(premiumEntitlementId);
  if (!belongsToPremium) {
    return { ignored: 'non_premium_entitlement' };
  }

  const lifecycle = lifecycleFor(eventType, raw);
  if (!lifecycle) {
    return { ignored: `unsupported_${eventType.toLowerCase()}` };
  }

  const userId = findSupabaseUserId(raw);
  const store = mapStore(text(raw.store));
  const environment = mapEnvironment(text(raw.environment));
  const occurredAt = dateFromMilliseconds(raw.event_timestamp_ms);
  if (!userId || !store || !environment || !occurredAt) {
    return { error: 'Identità, store, ambiente o data evento non validi.' };
  }

  return {
    event: {
      eventId,
      userId,
      store,
      environment,
      eventType,
      productId: text(raw.new_product_id) ?? text(raw.product_id),
      originalTransactionId:
        text(raw.original_transaction_id) ?? text(raw.transaction_id),
      status: lifecycle.status,
      occurredAt,
      currentPeriodStartedAt: dateFromMilliseconds(raw.purchased_at_ms),
      currentPeriodEndsAt: dateFromMilliseconds(raw.expiration_at_ms),
      gracePeriodEndsAt:
        dateFromMilliseconds(raw.grace_period_expiration_at_ms) ??
        lifecycle.fallbackGraceEnd,
      willRenew: lifecycle.willRenew,
    },
  };
}

function lifecycleFor(eventType: string, raw: RevenueCatEvent) {
  const periodStatus = text(raw.period_type) === 'TRIAL' ? 'trialing' : 'active';
  const expiration = dateFromMilliseconds(raw.expiration_at_ms);

  switch (eventType) {
    case 'INITIAL_PURCHASE':
    case 'RENEWAL':
    case 'UNCANCELLATION':
    case 'SUBSCRIPTION_EXTENDED':
    case 'PRODUCT_CHANGE':
      return { status: periodStatus, willRenew: true, fallbackGraceEnd: null } as const;
    case 'CANCELLATION':
    case 'SUBSCRIPTION_PAUSED':
      return { status: periodStatus, willRenew: false, fallbackGraceEnd: null } as const;
    case 'BILLING_ISSUE':
      return {
        status: 'billing_retry',
        willRenew: true,
        fallbackGraceEnd: expiration,
      } as const;
    case 'EXPIRATION':
      return { status: 'expired', willRenew: false, fallbackGraceEnd: null } as const;
    default:
      return null;
  }
}

function findSupabaseUserId(raw: RevenueCatEvent) {
  const candidates = [
    raw.app_user_id,
    raw.original_app_user_id,
    ...(Array.isArray(raw.aliases) ? raw.aliases : []),
  ];
  return candidates.find(
    (candidate): candidate is string =>
      typeof candidate === 'string' &&
      /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(
        candidate,
      ),
  ) ?? null;
}

function mapStore(value: string | null) {
  if (value === 'APP_STORE' || value === 'MAC_APP_STORE') return 'apple' as const;
  if (value === 'PLAY_STORE') return 'google' as const;
  if (value === 'TEST_STORE') return 'test' as const;
  return null;
}

function mapEnvironment(value: string | null) {
  if (value === 'PRODUCTION') return 'production' as const;
  if (value === 'SANDBOX') return 'sandbox' as const;
  return null;
}

function dateFromMilliseconds(value: unknown) {
  if (typeof value !== 'number' || !Number.isFinite(value) || value <= 0) {
    return null;
  }
  return new Date(value).toISOString();
}

function text(value: unknown) {
  return typeof value === 'string' && value.trim() ? value.trim() : null;
}

async function sha256(value: string) {
  const bytes = new TextEncoder().encode(value);
  const digest = await crypto.subtle.digest('SHA-256', bytes);
  return Array.from(new Uint8Array(digest), (byte) =>
    byte.toString(16).padStart(2, '0'),
  ).join('');
}

function safeEqual(left: string, right: string) {
  const leftBytes = new TextEncoder().encode(left);
  const rightBytes = new TextEncoder().encode(right);
  if (leftBytes.length !== rightBytes.length) return false;
  let difference = 0;
  for (let index = 0; index < leftBytes.length; index += 1) {
    difference |= leftBytes[index] ^ rightBytes[index];
  }
  return difference === 0;
}

function json(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: jsonHeaders });
}
