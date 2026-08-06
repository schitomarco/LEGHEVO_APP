-- LEGHEVO · Centro Assistenza e pratiche tracciate
-- Eseguire nel SQL Editor di Supabase dopo 054.
--
-- Lo script aggiunge FAQ lato app, richieste, conversazioni e cronologia
-- protette. Non crea pratiche, non invia comunicazioni e non modifica account,
-- leghe, formazioni o risultati.

alter table public.user_notifications
  drop constraint if exists user_notifications_action_screen_check;

alter table public.user_notifications
  add constraint user_notifications_action_screen_check
  check (
    action_screen is null
    or action_screen in (
      'home',
      'league',
      'live',
      'auction',
      'calendar',
      'leagueCup',
      'leaguePlayoffs',
      'leagueSuperCup',
      'leagueOperations',
      'postponements',
      'lineup',
      'roster',
      'standings',
      'market',
      'support'
    )
  );

create table if not exists public.support_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  league_id uuid references public.leagues(id) on delete set null,
  category text not null check (
    category in (
      'account',
      'league',
      'auction_market',
      'lineup_results',
      'technical',
      'billing',
      'safety',
      'other'
    )
  ),
  subject text not null
    check (char_length(trim(subject)) between 5 and 100),
  status text not null default 'submitted' check (
    status in (
      'submitted',
      'in_progress',
      'waiting_user',
      'resolved',
      'closed'
    )
  ),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  resolved_at timestamptz,
  closed_at timestamptz,
  check (
    (status = 'resolved' and resolved_at is not null and closed_at is null)
    or
    (status = 'closed' and closed_at is not null)
    or
    (
      status in ('submitted', 'in_progress', 'waiting_user')
      and resolved_at is null
      and closed_at is null
    )
  )
);

create table if not exists public.support_request_messages (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null
    references public.support_requests(id) on delete cascade,
  author_type text not null check (author_type in ('user', 'support')),
  actor_user_id uuid references auth.users(id) on delete set null,
  body text not null check (char_length(trim(body)) between 2 and 3000),
  created_at timestamptz not null default now()
);

create table if not exists public.support_request_events (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null
    references public.support_requests(id) on delete cascade,
  actor_type text not null check (actor_type in ('user', 'support')),
  actor_user_id uuid references auth.users(id) on delete set null,
  event_type text not null check (
    event_type in (
      'submitted',
      'user_replied',
      'support_replied',
      'status_changed',
      'closed'
    )
  ),
  status text not null check (
    status in (
      'submitted',
      'in_progress',
      'waiting_user',
      'resolved',
      'closed'
    )
  ),
  occurred_at timestamptz not null default now()
);

create index if not exists support_requests_user_date_idx
  on public.support_requests (user_id, updated_at desc, id desc);

create index if not exists support_requests_open_queue_idx
  on public.support_requests (status, updated_at)
  where status in ('submitted', 'in_progress', 'waiting_user');

create index if not exists support_messages_request_date_idx
  on public.support_request_messages (request_id, created_at, id);

create index if not exists support_events_request_date_idx
  on public.support_request_events (request_id, occurred_at, id);

drop trigger if exists support_requests_set_updated_at
on public.support_requests;

create trigger support_requests_set_updated_at
before update on public.support_requests
for each row execute function public.set_updated_at();

alter table public.support_requests enable row level security;
alter table public.support_request_messages enable row level security;
alter table public.support_request_events enable row level security;

drop policy if exists support_requests_read_own
on public.support_requests;

create policy support_requests_read_own
on public.support_requests for select to authenticated
using (user_id = auth.uid());

drop policy if exists support_messages_read_own
on public.support_request_messages;

create policy support_messages_read_own
on public.support_request_messages for select to authenticated
using (
  exists (
    select 1
    from public.support_requests request
    where request.id = support_request_messages.request_id
      and request.user_id = auth.uid()
  )
);

drop policy if exists support_events_read_own
on public.support_request_events;

create policy support_events_read_own
on public.support_request_events for select to authenticated
using (
  exists (
    select 1
    from public.support_requests request
    where request.id = support_request_events.request_id
      and request.user_id = auth.uid()
  )
);

revoke all on public.support_requests from anon, authenticated;
revoke all on public.support_request_messages from anon, authenticated;
revoke all on public.support_request_events from anon, authenticated;
grant select on public.support_requests to authenticated;
grant select on public.support_request_messages to authenticated;
grant select on public.support_request_events to authenticated;

create or replace function public.get_my_support_center()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_requests jsonb := '[]'::jsonb;
  v_open_count integer := 0;
  v_waiting_count integer := 0;
  v_total_count integer := 0;
begin
  if v_user_id is null then
    raise exception 'Devi effettuare l''accesso.';
  end if;

  select
    count(*) filter (
      where request.status in ('submitted', 'in_progress', 'waiting_user')
    )::integer,
    count(*) filter (
      where request.status = 'waiting_user'
    )::integer,
    count(*)::integer,
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'id', request.id,
          'leagueId', request.league_id,
          'leagueName', league.name,
          'category', request.category,
          'subject', request.subject,
          'status', request.status,
          'createdAt', request.created_at,
          'updatedAt', request.updated_at,
          'resolvedAt', request.resolved_at,
          'closedAt', request.closed_at,
          'canReply',
            request.status in (
              'submitted',
              'in_progress',
              'waiting_user'
            ),
          'canClose',
            request.status in (
              'submitted',
              'in_progress',
              'waiting_user'
            ),
          'messages', coalesce((
            select jsonb_agg(
              jsonb_build_object(
                'id', message.id,
                'authorType', message.author_type,
                'body', message.body,
                'createdAt', message.created_at
              )
              order by message.created_at, message.id
            )
            from public.support_request_messages message
            where message.request_id = request.id
          ), '[]'::jsonb),
          'events', coalesce((
            select jsonb_agg(
              jsonb_build_object(
                'id', event.id,
                'actorType', event.actor_type,
                'eventType', event.event_type,
                'status', event.status,
                'occurredAt', event.occurred_at
              )
              order by event.occurred_at, event.id
            )
            from public.support_request_events event
            where event.request_id = request.id
          ), '[]'::jsonb)
        )
        order by request.updated_at desc, request.id desc
      ),
      '[]'::jsonb
    )
  into v_open_count, v_waiting_count, v_total_count, v_requests
  from public.support_requests request
  left join public.leagues league on league.id = request.league_id
  where request.user_id = v_user_id;

  return jsonb_build_object(
    'generatedAt', now(),
    'openCount', v_open_count,
    'waitingUserCount', v_waiting_count,
    'totalCount', v_total_count,
    'requests', v_requests
  );
end;
$$;

create or replace function public.create_my_support_request(
  p_category text,
  p_subject text,
  p_message text,
  p_league_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_category text := lower(trim(coalesce(p_category, '')));
  v_subject text := trim(coalesce(p_subject, ''));
  v_message text := trim(coalesce(p_message, ''));
  v_request public.support_requests%rowtype;
  v_message_id uuid;
  v_event_id uuid;
begin
  if v_user_id is null then
    raise exception 'Devi effettuare l''accesso.';
  end if;

  if v_category not in (
    'account',
    'league',
    'auction_market',
    'lineup_results',
    'technical',
    'billing',
    'safety',
    'other'
  ) then
    raise exception 'Categoria di assistenza non valida.';
  end if;

  if char_length(v_subject) not between 5 and 100 then
    raise exception 'L''oggetto deve contenere da 5 a 100 caratteri.';
  end if;

  if char_length(v_message) not between 10 and 3000 then
    raise exception 'Il messaggio deve contenere da 10 a 3000 caratteri.';
  end if;

  if p_league_id is not null and not exists (
    select 1
    from public.league_members member
    where member.league_id = p_league_id
      and member.user_id = v_user_id
  ) then
    raise exception 'Puoi collegare soltanto una lega a cui partecipi.';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(v_user_id::text, 55)
  );

  if (
    select count(*)
    from public.support_requests request
    where request.user_id = v_user_id
      and request.status in ('submitted', 'in_progress', 'waiting_user')
  ) >= 3 then
    raise exception 'Puoi avere al massimo tre richieste di assistenza aperte.';
  end if;

  insert into public.support_requests (
    user_id,
    league_id,
    category,
    subject,
    status
  )
  values (
    v_user_id,
    p_league_id,
    v_category,
    v_subject,
    'submitted'
  )
  returning * into v_request;

  insert into public.support_request_messages (
    request_id,
    author_type,
    actor_user_id,
    body
  )
  values (
    v_request.id,
    'user',
    v_user_id,
    v_message
  )
  returning id into v_message_id;

  insert into public.support_request_events (
    request_id,
    actor_type,
    actor_user_id,
    event_type,
    status
  )
  values (
    v_request.id,
    'user',
    v_user_id,
    'submitted',
    'submitted'
  )
  returning id into v_event_id;

  return jsonb_build_object(
    'id', v_request.id,
    'leagueId', v_request.league_id,
    'category', v_request.category,
    'subject', v_request.subject,
    'status', v_request.status,
    'createdAt', v_request.created_at,
    'updatedAt', v_request.updated_at,
    'resolvedAt', null,
    'closedAt', null,
    'canReply', true,
    'canClose', true,
    'messages', jsonb_build_array(
      jsonb_build_object(
        'id', v_message_id,
        'authorType', 'user',
        'body', v_message,
        'createdAt', v_request.created_at
      )
    ),
    'events', jsonb_build_array(
      jsonb_build_object(
        'id', v_event_id,
        'actorType', 'user',
        'eventType', 'submitted',
        'status', 'submitted',
        'occurredAt', v_request.created_at
      )
    )
  );
end;
$$;

create or replace function public.reply_to_my_support_request(
  p_request_id uuid,
  p_message text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_message text := trim(coalesce(p_message, ''));
  v_request public.support_requests%rowtype;
  v_message_id uuid;
  v_now timestamptz := now();
begin
  if v_user_id is null then
    raise exception 'Devi effettuare l''accesso.';
  end if;

  if char_length(v_message) not between 2 and 3000 then
    raise exception 'La risposta deve contenere da 2 a 3000 caratteri.';
  end if;

  select request.*
  into v_request
  from public.support_requests request
  where request.id = p_request_id
    and request.user_id = v_user_id
  for update;

  if not found then
    raise exception 'Richiesta di assistenza non trovata.';
  end if;

  if v_request.status not in (
    'submitted',
    'in_progress',
    'waiting_user'
  ) then
    raise exception 'La richiesta è chiusa e non accetta altre risposte.';
  end if;

  update public.support_requests request
  set
    status = 'submitted',
    updated_at = v_now
  where request.id = v_request.id
  returning * into v_request;

  insert into public.support_request_messages (
    request_id,
    author_type,
    actor_user_id,
    body,
    created_at
  )
  values (
    v_request.id,
    'user',
    v_user_id,
    v_message,
    v_now
  )
  returning id into v_message_id;

  insert into public.support_request_events (
    request_id,
    actor_type,
    actor_user_id,
    event_type,
    status,
    occurred_at
  )
  values (
    v_request.id,
    'user',
    v_user_id,
    'user_replied',
    v_request.status,
    v_now
  );

  return jsonb_build_object(
    'id', v_request.id,
    'status', v_request.status,
    'updatedAt', v_request.updated_at,
    'messageId', v_message_id
  );
end;
$$;

create or replace function public.close_my_support_request(
  p_request_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_request public.support_requests%rowtype;
  v_now timestamptz := now();
begin
  if v_user_id is null then
    raise exception 'Devi effettuare l''accesso.';
  end if;

  select request.*
  into v_request
  from public.support_requests request
  where request.id = p_request_id
    and request.user_id = v_user_id
  for update;

  if not found then
    raise exception 'Richiesta di assistenza non trovata.';
  end if;

  if v_request.status in ('resolved', 'closed') then
    raise exception 'La richiesta è già conclusa.';
  end if;

  update public.support_requests request
  set
    status = 'closed',
    closed_at = v_now,
    updated_at = v_now
  where request.id = v_request.id
  returning * into v_request;

  insert into public.support_request_events (
    request_id,
    actor_type,
    actor_user_id,
    event_type,
    status,
    occurred_at
  )
  values (
    v_request.id,
    'user',
    v_user_id,
    'closed',
    'closed',
    v_now
  );

  return jsonb_build_object(
    'id', v_request.id,
    'status', v_request.status,
    'updatedAt', v_request.updated_at,
    'closedAt', v_request.closed_at
  );
end;
$$;

create or replace function public.process_support_request(
  p_request_id uuid,
  p_status text,
  p_public_reply text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_status text := lower(trim(coalesce(p_status, '')));
  v_reply text := nullif(trim(coalesce(p_public_reply, '')), '');
  v_request public.support_requests%rowtype;
  v_message_id uuid;
  v_event_id uuid;
  v_now timestamptz := now();
begin
  if v_status not in ('in_progress', 'waiting_user', 'resolved') then
    raise exception 'Stato di assistenza non valido.';
  end if;

  if v_reply is not null and char_length(v_reply) > 3000 then
    raise exception 'La risposta può contenere al massimo 3000 caratteri.';
  end if;

  if v_status in ('waiting_user', 'resolved')
    and char_length(coalesce(v_reply, '')) < 2 then
    raise exception 'Inserisci una risposta pubblica per questo stato.';
  end if;

  select request.*
  into v_request
  from public.support_requests request
  where request.id = p_request_id
  for update;

  if not found then
    raise exception 'Richiesta di assistenza non trovata.';
  end if;

  if v_request.status in ('resolved', 'closed') then
    raise exception 'La richiesta di assistenza è già conclusa.';
  end if;

  update public.support_requests request
  set
    status = v_status,
    resolved_at = case when v_status = 'resolved' then v_now else null end,
    updated_at = v_now
  where request.id = v_request.id
  returning * into v_request;

  if v_reply is not null then
    insert into public.support_request_messages (
      request_id,
      author_type,
      actor_user_id,
      body,
      created_at
    )
    values (
      v_request.id,
      'support',
      auth.uid(),
      v_reply,
      v_now
    )
    returning id into v_message_id;
  end if;

  insert into public.support_request_events (
    request_id,
    actor_type,
    actor_user_id,
    event_type,
    status,
    occurred_at
  )
  values (
    v_request.id,
    'support',
    auth.uid(),
    case
      when v_message_id is not null then 'support_replied'
      else 'status_changed'
    end,
    v_request.status,
    v_now
  )
  returning id into v_event_id;

  perform public.create_user_notification(
    v_request.user_id,
    v_request.league_id,
    'system',
    case
      when v_request.status = 'resolved' then 'Assistenza: pratica risolta'
      when v_request.status = 'waiting_user' then 'Assistenza: serve una risposta'
      else 'Assistenza: pratica aggiornata'
    end,
    case
      when v_reply is not null then left(v_reply, 280)
      else 'La tua richiesta di assistenza ha un nuovo aggiornamento.'
    end,
    'support',
    jsonb_build_object(
      'supportRequestId', v_request.id,
      'supportStatus', v_request.status
    ),
    'support:' || v_request.id::text || ':' || v_event_id::text
  );

  return jsonb_build_object(
    'id', v_request.id,
    'status', v_request.status,
    'updatedAt', v_request.updated_at,
    'resolvedAt', v_request.resolved_at,
    'messageId', v_message_id,
    'eventId', v_event_id
  );
end;
$$;

create or replace function public.export_my_personal_data_v4()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_export jsonb;
begin
  if auth.uid() is null then
    raise exception 'Devi effettuare l''accesso.';
  end if;

  v_export := public.export_my_personal_data_v3();

  return v_export || jsonb_build_object(
    'exportVersion', 4,
    'supportCenter', public.get_my_support_center()
  );
end;
$$;

revoke all on function public.get_my_support_center()
from public, anon;
revoke all on function public.create_my_support_request(text, text, text, uuid)
from public, anon;
revoke all on function public.reply_to_my_support_request(uuid, text)
from public, anon;
revoke all on function public.close_my_support_request(uuid)
from public, anon;
revoke all on function public.process_support_request(uuid, text, text)
from public, anon, authenticated;
revoke all on function public.export_my_personal_data_v4()
from public, anon;

grant execute on function public.get_my_support_center()
to authenticated;
grant execute on function public.create_my_support_request(
  text,
  text,
  text,
  uuid
) to authenticated;
grant execute on function public.reply_to_my_support_request(uuid, text)
to authenticated;
grant execute on function public.close_my_support_request(uuid)
to authenticated;
grant execute on function public.process_support_request(uuid, text, text)
to service_role;
grant execute on function public.export_my_personal_data_v4()
to authenticated;

select
  to_regclass('public.support_requests') is not null
    as support_requests_ready,
  to_regclass('public.support_request_messages') is not null
    as support_messages_ready,
  to_regclass('public.support_request_events') is not null
    as support_events_ready,
  to_regprocedure(
    'public.get_my_support_center()'
  ) is not null as support_center_read_ready,
  to_regprocedure(
    'public.create_my_support_request(text,text,text,uuid)'
  ) is not null as support_create_ready,
  to_regprocedure(
    'public.reply_to_my_support_request(uuid,text)'
  ) is not null as support_reply_ready,
  to_regprocedure(
    'public.close_my_support_request(uuid)'
  ) is not null as support_close_ready,
  to_regprocedure(
    'public.process_support_request(uuid,text,text)'
  ) is not null as support_processing_ready,
  to_regprocedure(
    'public.export_my_personal_data_v4()'
  ) is not null as personal_export_v4_ready,
  has_function_privilege(
    'authenticated',
    'public.get_my_support_center()',
    'EXECUTE'
  ) as support_read_access_ready,
  not has_function_privilege(
    'authenticated',
    'public.process_support_request(uuid,text,text)',
    'EXECUTE'
  ) as support_processing_protected,
  exists (
    select 1
    from pg_constraint constraint_info
    where constraint_info.conrelid = 'public.user_notifications'::regclass
      and constraint_info.conname =
        'user_notifications_action_screen_check'
      and pg_get_constraintdef(constraint_info.oid) ilike '%support%'
  ) as support_notification_route_ready;
