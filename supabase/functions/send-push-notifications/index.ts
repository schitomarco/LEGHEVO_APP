import { withSupabase } from 'npm:@supabase/server@1';
import type { SupabaseClient } from 'npm:@supabase/supabase-js@2';

const EXPO_PUSH_URL = 'https://exp.host/--/api/v2/push/send';
const jsonHeaders = {
  'Content-Type': 'application/json',
};

type PushQueueItem = {
  delivery_id: string;
  notification_id: string;
  expo_push_token: string;
  title: string;
  body: string;
  action_screen: string | null;
  league_id: string | null;
  notification_kind: string;
  metadata: Record<string, unknown> | null;
};

type ExpoPushTicket = {
  status: 'ok' | 'error';
  id?: string;
  message?: string;
  details?: {
    error?: string;
  };
};

export default {
  fetch: withSupabase(
    { auth: 'secret:automations' },
    async (request, context) => {
      if (request.method !== 'POST') {
        return json({ error: 'Metodo non consentito.' }, 405);
      }

      let requestedLimit = 50;
      try {
        const payload = (await request.json()) as { limit?: number };
        requestedLimit = Number(payload.limit ?? 50);
      } catch {
        // Un webhook senza corpo usa il lotto standard.
      }

      const limit = Math.max(
        1,
        Math.min(Number.isFinite(requestedLimit) ? requestedLimit : 50, 100),
      );
      const supabase = context.supabaseAdmin;
      const queue = await claimQueue(supabase, limit);

      if (queue.length === 0) {
        return json({ ok: true, claimed: 0, sent: 0, failed: 0, retried: 0 });
      }

      const accessToken = Deno.env.get('EXPO_ACCESS_TOKEN');
      let tickets: ExpoPushTicket[];

      try {
        const response = await fetch(EXPO_PUSH_URL, {
          method: 'POST',
          headers: {
            ...jsonHeaders,
            Accept: 'application/json',
            'Accept-Encoding': 'gzip, deflate',
            ...(accessToken
              ? { Authorization: `Bearer ${accessToken}` }
              : {}),
          },
          body: JSON.stringify(queue.map(toExpoMessage)),
        });

        if (!response.ok) {
          throw new Error(`Expo Push ha risposto con HTTP ${response.status}.`);
        }

        const envelope = (await response.json()) as {
          data?: ExpoPushTicket | ExpoPushTicket[];
          errors?: Array<{ message?: string }>;
        };

        if (envelope.errors?.length) {
          throw new Error(
            envelope.errors
              .map((error) => error.message ?? 'Errore Expo Push.')
              .join(' '),
          );
        }

        tickets = Array.isArray(envelope.data)
          ? envelope.data
          : envelope.data
            ? [envelope.data]
            : [];

        if (tickets.length !== queue.length) {
          throw new Error('Expo Push non ha restituito tutti i ticket attesi.');
        }
      } catch (error) {
        const message =
          error instanceof Error
            ? error.message
            : 'Servizio Expo Push non raggiungibile.';
        await Promise.all(
          queue.map((item) =>
            completeDelivery(supabase, item.delivery_id, {
              status: 'retry',
              errorCode: 'ExpoPushUnavailable',
              errorMessage: message,
            }),
          ),
        );
        return json(
          {
            ok: false,
            claimed: queue.length,
            sent: 0,
            failed: 0,
            retried: queue.length,
            error: message,
          },
          502,
        );
      }

      let sent = 0;
      let failed = 0;
      let retried = 0;

      for (let index = 0; index < queue.length; index += 1) {
        const item = queue[index];
        const ticket = tickets[index];

        if (ticket.status === 'ok') {
          await completeDelivery(supabase, item.delivery_id, {
            status: 'sent',
            ticketId: ticket.id,
          });
          sent += 1;
          continue;
        }

        const errorCode = ticket.details?.error ?? 'ExpoPushError';
        const shouldRetry = ![
          'DeviceNotRegistered',
          'MessageTooBig',
          'InvalidCredentials',
        ].includes(errorCode);

        await completeDelivery(supabase, item.delivery_id, {
          status: shouldRetry ? 'retry' : 'failed',
          errorCode,
          errorMessage: ticket.message ?? 'Notifica rifiutata da Expo Push.',
        });

        if (shouldRetry) {
          retried += 1;
        } else {
          failed += 1;
        }
      }

      return json({
        ok: true,
        claimed: queue.length,
        sent,
        failed,
        retried,
        enhancedSecurity: Boolean(accessToken),
      });
    },
  ),
};

async function claimQueue(supabase: SupabaseClient, limit: number) {
  const { data, error } = await supabase.rpc(
    'claim_notification_push_batch',
    { p_limit: limit },
  );

  if (error) {
    throw new Error(`Coda notifiche non disponibile: ${error.message}`);
  }

  return (data ?? []) as PushQueueItem[];
}

function toExpoMessage(item: PushQueueItem) {
  return {
    to: item.expo_push_token,
    sound: 'default',
    priority: 'high',
    channelId: 'leghevo',
    title: item.title,
    body: item.body,
    data: {
      notificationId: item.notification_id,
      leagueId: item.league_id,
      actionScreen: item.action_screen,
      kind: item.notification_kind,
      metadata: item.metadata ?? {},
    },
  };
}

async function completeDelivery(
  supabase: SupabaseClient,
  deliveryId: string,
  outcome: {
    status: 'sent' | 'failed' | 'retry' | 'skipped';
    ticketId?: string;
    errorCode?: string;
    errorMessage?: string;
  },
) {
  const { error } = await supabase.rpc(
    'complete_notification_push_delivery',
    {
      p_delivery_id: deliveryId,
      p_status: outcome.status,
      p_expo_ticket_id: outcome.ticketId ?? null,
      p_error_code: outcome.errorCode ?? null,
      p_error_message: outcome.errorMessage ?? null,
    },
  );

  if (error) {
    throw new Error(`Esito push non registrato: ${error.message}`);
  }
}

function json(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: jsonHeaders,
  });
}
