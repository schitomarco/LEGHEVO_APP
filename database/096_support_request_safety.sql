-- LEGHEVO v0.61.2 · Centro Assistenza protetto e revisionato
-- Migrazione interna: database/096_support_request_safety.sql
--
-- Obiettivi:
-- - creazione, risposta e chiusura idempotenti;
-- - revisione ottimistica contro operazioni concorrenti;
-- - lavorazione service-role revisionata;
-- - registro immutabile delle azioni;
-- - compatibilità con le RPC storiche;
-- - nessuna modifica ai contenuti delle pratiche già presenti.

begin;

-- Preflight dettagliato: non modifica nulla se manca una dipendenza.
do $preflight$
declare
  v_missing text[] := array[]::text[];
  v_expected record;
begin
  if to_regclass('public.support_requests') is null then
    v_missing := array_append(v_missing, 'table public.support_requests');
  end if;
  if to_regclass('public.support_request_messages') is null then
    v_missing := array_append(v_missing, 'table public.support_request_messages');
  end if;
  if to_regclass('public.support_request_events') is null then
    v_missing := array_append(v_missing, 'table public.support_request_events');
  end if;
  if to_regclass('public.league_members') is null then
    v_missing := array_append(v_missing, 'table public.league_members');
  end if;
  if to_regclass('public.leagues') is null then
    v_missing := array_append(v_missing, 'table public.leagues');
  end if;
  if to_regprocedure('public.set_updated_at()') is null then
    v_missing := array_append(v_missing, 'function public.set_updated_at()');
  end if;
  if to_regprocedure(
    'public.create_user_notification(uuid,uuid,text,text,text,text,jsonb,text)'
  ) is null then
    v_missing := array_append(
      v_missing,
      'function public.create_user_notification(uuid,uuid,text,text,text,text,jsonb,text)'
    );
  end if;

  for v_expected in
    select *
    from (values
      ('support_requests', 'id'),
      ('support_requests', 'user_id'),
      ('support_requests', 'league_id'),
      ('support_requests', 'category'),
      ('support_requests', 'subject'),
      ('support_requests', 'status'),
      ('support_requests', 'created_at'),
      ('support_requests', 'updated_at'),
      ('support_requests', 'resolved_at'),
      ('support_requests', 'closed_at'),
      ('support_request_messages', 'id'),
      ('support_request_messages', 'request_id'),
      ('support_request_messages', 'author_type'),
      ('support_request_messages', 'actor_user_id'),
      ('support_request_messages', 'body'),
      ('support_request_messages', 'created_at'),
      ('support_request_events', 'id'),
      ('support_request_events', 'request_id'),
      ('support_request_events', 'actor_type'),
      ('support_request_events', 'actor_user_id'),
      ('support_request_events', 'event_type'),
      ('support_request_events', 'status'),
      ('support_request_events', 'occurred_at'),
      ('league_members', 'league_id'),
      ('league_members', 'user_id'),
      ('leagues', 'id'),
      ('leagues', 'name')
    ) as expected(table_name, column_name)
  loop
    if not exists (
      select 1
      from information_schema.columns column_row
      where column_row.table_schema = 'public'
        and column_row.table_name = v_expected.table_name
        and column_row.column_name = v_expected.column_name
    ) then
      v_missing := array_append(
        v_missing,
        format('column public.%I.%I', v_expected.table_name, v_expected.column_name)
      );
    end if;
  end loop;

  if coalesce(array_length(v_missing, 1), 0) > 0 then
    raise exception
      'Preflight v0.61.2 non superato. Oggetti mancanti: %',
      array_to_string(v_missing, '; ');
  end if;
end;
$preflight$;

alter table public.support_requests
  add column if not exists revision bigint not null default 1,
  add column if not exists request_fingerprint text,
  add column if not exists submission_request_id uuid;

update public.support_requests request
set request_fingerprint = pg_catalog.md5(
  request.category || E'\n' ||
  request.subject || E'\n' ||
  coalesce(request.league_id::text, '') || E'\n' ||
  coalesce((
    select message.body
    from public.support_request_messages message
    where message.request_id = request.id
      and message.author_type = 'user'
    order by message.created_at, message.id
    limit 1
  ), '')
)
where request.request_fingerprint is null;

alter table public.support_requests
  alter column request_fingerprint set not null;

alter table public.support_requests
  drop constraint if exists support_requests_revision_check;
alter table public.support_requests
  add constraint support_requests_revision_check
  check (revision > 0);

alter table public.support_requests
  drop constraint if exists support_requests_fingerprint_check;
alter table public.support_requests
  add constraint support_requests_fingerprint_check
  check (char_length(request_fingerprint) = 32);

create unique index if not exists support_submission_request_unique_idx
  on public.support_requests (user_id, submission_request_id)
  where submission_request_id is not null;

create table if not exists public.support_request_action_runs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null,
  request_id uuid not null,
  actor_type text not null check (actor_type in ('user', 'support')),
  actor_user_id uuid,
  action_type text not null check (
    action_type in ('create', 'user_reply', 'user_close', 'staff_process')
  ),
  idempotency_key uuid not null unique,
  previous_revision bigint,
  result_revision bigint not null check (result_revision > 0),
  result_status text not null check (
    result_status in (
      'submitted', 'in_progress', 'waiting_user', 'resolved', 'closed'
    )
  ),
  payload_fingerprint text not null check (
    char_length(payload_fingerprint) = 32
  ),
  result_snapshot jsonb not null check (
    jsonb_typeof(result_snapshot) = 'object'
  ),
  created_at timestamptz not null default now()
);

create index if not exists support_action_runs_request_idx
  on public.support_request_action_runs (request_id, created_at desc);
create index if not exists support_action_runs_user_idx
  on public.support_request_action_runs (user_id, created_at desc);

alter table public.support_request_action_runs enable row level security;
alter table public.support_request_action_runs replica identity full;
alter table public.support_requests replica identity full;
alter table public.support_request_messages replica identity full;
alter table public.support_request_events replica identity full;

drop policy if exists support_action_runs_read_own
on public.support_request_action_runs;
create policy support_action_runs_read_own
on public.support_request_action_runs
for select to authenticated
using (user_id = auth.uid());

revoke all on table public.support_request_action_runs
from public, anon, authenticated;
grant select on table public.support_request_action_runs
to authenticated;

create or replace function public.prevent_support_action_run_mutation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  raise exception
    'Operazione di assistenza certificata: modifica o cancellazione diretta non consentita.';
end;
$$;

revoke all on function public.prevent_support_action_run_mutation()
from public, anon, authenticated;

drop trigger if exists support_action_runs_immutable
on public.support_request_action_runs;
create trigger support_action_runs_immutable
before update or delete on public.support_request_action_runs
for each row execute function public.prevent_support_action_run_mutation();

create or replace function public.support_request_payload_v1(
  p_request_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_payload jsonb;
begin
  select jsonb_build_object(
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
    'revision', request.revision,
    'protected', true,
    'canReply', request.status in ('submitted', 'in_progress', 'waiting_user'),
    'canClose', request.status in ('submitted', 'in_progress', 'waiting_user'),
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
  into v_payload
  from public.support_requests request
  left join public.leagues league on league.id = request.league_id
  where request.id = p_request_id;

  return v_payload;
end;
$$;

revoke all on function public.support_request_payload_v1(uuid)
from public, anon, authenticated;

create or replace function public.support_request_certificate_v1(
  p_request_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_certificate jsonb;
begin
  select jsonb_build_object(
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
    'revision', request.revision,
    'protected', true,
    'canReply', false,
    'canClose', false,
    'messages', '[]'::jsonb,
    'events', '[]'::jsonb
  )
  into v_certificate
  from public.support_requests request
  left join public.leagues league on league.id = request.league_id
  where request.id = p_request_id;

  return v_certificate;
end;
$$;

revoke all on function public.support_request_certificate_v1(uuid)
from public, anon, authenticated;

create or replace function public.get_my_support_center_v2()
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
    count(*) filter (where request.status = 'waiting_user')::integer,
    count(*)::integer,
    coalesce(
      jsonb_agg(
        public.support_request_payload_v1(request.id)
        order by request.updated_at desc, request.id desc
      ),
      '[]'::jsonb
    )
  into v_open_count, v_waiting_count, v_total_count, v_requests
  from public.support_requests request
  where request.user_id = v_user_id;

  return jsonb_build_object(
    'generatedAt', now(),
    'openCount', v_open_count,
    'waitingUserCount', v_waiting_count,
    'totalCount', v_total_count,
    'requests', v_requests,
    'protection', jsonb_build_object(
      'guardedActionsReady', true,
      'revisionControlReady', true,
      'idempotencyReady', true
    )
  );
end;
$$;

create or replace function public.create_my_support_request_guarded_v1(
  p_category text,
  p_subject text,
  p_message text,
  p_league_id uuid,
  p_idempotency_key uuid
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
  v_fingerprint text;
  v_request public.support_requests%rowtype;
  v_run public.support_request_action_runs%rowtype;
  v_message_id uuid;
  v_event_id uuid;
  v_payload jsonb;
begin
  if v_user_id is null then
    raise exception 'Devi effettuare l''accesso.';
  end if;
  if p_idempotency_key is null then
    raise exception 'Identificativo della richiesta mancante.';
  end if;
  if v_category not in (
    'account', 'league', 'auction_market', 'lineup_results',
    'technical', 'billing', 'safety', 'other'
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

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'leghevo:support:create:' || v_user_id::text,
      0
    )
  );

  select run.*
  into v_run
  from public.support_request_action_runs run
  where run.idempotency_key = p_idempotency_key;

  if found then
    if v_run.user_id <> v_user_id or v_run.action_type <> 'create' then
      raise exception 'Identificativo già usato per un''altra operazione.';
    end if;
    return coalesce(
      public.support_request_payload_v1(v_run.request_id),
      v_run.result_snapshot
    ) || jsonb_build_object('idempotentReplay', true);
  end if;

  v_fingerprint := pg_catalog.md5(
    v_category || E'\n' || v_subject || E'\n' ||
    coalesce(p_league_id::text, '') || E'\n' || v_message
  );

  select request.*
  into v_request
  from public.support_requests request
  where request.user_id = v_user_id
    and request.status in ('submitted', 'in_progress', 'waiting_user')
    and request.request_fingerprint = v_fingerprint
  order by request.created_at desc
  limit 1
  for update;

  if found then
    v_payload := public.support_request_payload_v1(v_request.id);
    insert into public.support_request_action_runs (
      user_id, request_id, actor_type, actor_user_id, action_type,
      idempotency_key, previous_revision, result_revision, result_status,
      payload_fingerprint, result_snapshot
    ) values (
      v_user_id, v_request.id, 'user', v_user_id, 'create',
      p_idempotency_key, v_request.revision, v_request.revision,
      v_request.status, v_fingerprint,
      public.support_request_certificate_v1(v_request.id)
    );
    return v_payload || jsonb_build_object('idempotentReplay', true);
  end if;

  if (
    select count(*)
    from public.support_requests request
    where request.user_id = v_user_id
      and request.status in ('submitted', 'in_progress', 'waiting_user')
  ) >= 3 then
    raise exception 'Puoi avere al massimo tre richieste di assistenza aperte.';
  end if;

  insert into public.support_requests (
    user_id, league_id, category, subject, status, revision,
    request_fingerprint, submission_request_id
  ) values (
    v_user_id, p_league_id, v_category, v_subject, 'submitted', 1,
    v_fingerprint, p_idempotency_key
  )
  returning * into v_request;

  insert into public.support_request_messages (
    request_id, author_type, actor_user_id, body, created_at
  ) values (
    v_request.id, 'user', v_user_id, v_message, v_request.created_at
  )
  returning id into v_message_id;

  insert into public.support_request_events (
    request_id, actor_type, actor_user_id, event_type, status, occurred_at
  ) values (
    v_request.id, 'user', v_user_id, 'submitted', 'submitted',
    v_request.created_at
  )
  returning id into v_event_id;

  v_payload := public.support_request_payload_v1(v_request.id);

  insert into public.support_request_action_runs (
    user_id, request_id, actor_type, actor_user_id, action_type,
    idempotency_key, previous_revision, result_revision, result_status,
    payload_fingerprint, result_snapshot
  ) values (
    v_user_id, v_request.id, 'user', v_user_id, 'create',
    p_idempotency_key, null, v_request.revision, v_request.status,
    v_fingerprint, public.support_request_certificate_v1(v_request.id)
  );

  return v_payload || jsonb_build_object(
    'messageId', v_message_id,
    'eventId', v_event_id,
    'idempotentReplay', false
  );
end;
$$;

create or replace function public.reply_to_my_support_request_guarded_v1(
  p_request_id uuid,
  p_message text,
  p_expected_revision bigint,
  p_idempotency_key uuid
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
  v_run public.support_request_action_runs%rowtype;
  v_now timestamptz := now();
  v_message_id uuid;
  v_event_id uuid;
  v_payload jsonb;
  v_fingerprint text;
begin
  if v_user_id is null then
    raise exception 'Devi effettuare l''accesso.';
  end if;
  if p_request_id is null or p_idempotency_key is null then
    raise exception 'Dati della risposta incompleti.';
  end if;
  if coalesce(p_expected_revision, 0) < 1 then
    raise exception 'Revisione della richiesta non valida.';
  end if;
  if char_length(v_message) not between 2 and 3000 then
    raise exception 'La risposta deve contenere da 2 a 3000 caratteri.';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'leghevo:support:request:' || p_request_id::text,
      0
    )
  );

  select run.*
  into v_run
  from public.support_request_action_runs run
  where run.idempotency_key = p_idempotency_key;

  if found then
    if v_run.user_id <> v_user_id
      or v_run.action_type <> 'user_reply'
      or v_run.request_id <> p_request_id then
      raise exception 'Identificativo già usato per un''altra operazione.';
    end if;
    return coalesce(
      public.support_request_payload_v1(v_run.request_id),
      v_run.result_snapshot
    ) || jsonb_build_object('idempotentReplay', true);
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
  if v_request.revision <> p_expected_revision then
    raise exception
      'La richiesta è stata aggiornata su un altro dispositivo. Ricarica e riprova.';
  end if;
  if v_request.status not in ('submitted', 'in_progress', 'waiting_user') then
    raise exception 'La richiesta è chiusa e non accetta altre risposte.';
  end if;

  update public.support_requests request
  set
    status = 'submitted',
    resolved_at = null,
    closed_at = null,
    updated_at = v_now,
    revision = request.revision + 1
  where request.id = v_request.id
  returning * into v_request;

  insert into public.support_request_messages (
    request_id, author_type, actor_user_id, body, created_at
  ) values (
    v_request.id, 'user', v_user_id, v_message, v_now
  )
  returning id into v_message_id;

  insert into public.support_request_events (
    request_id, actor_type, actor_user_id, event_type, status, occurred_at
  ) values (
    v_request.id, 'user', v_user_id, 'user_replied', v_request.status, v_now
  )
  returning id into v_event_id;

  v_payload := public.support_request_payload_v1(v_request.id);
  v_fingerprint := pg_catalog.md5('user_reply' || E'\n' || v_message);

  insert into public.support_request_action_runs (
    user_id, request_id, actor_type, actor_user_id, action_type,
    idempotency_key, previous_revision, result_revision, result_status,
    payload_fingerprint, result_snapshot
  ) values (
    v_user_id, v_request.id, 'user', v_user_id, 'user_reply',
    p_idempotency_key, p_expected_revision, v_request.revision,
    v_request.status, v_fingerprint,
    public.support_request_certificate_v1(v_request.id)
  );

  return v_payload || jsonb_build_object(
    'messageId', v_message_id,
    'eventId', v_event_id,
    'idempotentReplay', false
  );
end;
$$;

create or replace function public.close_my_support_request_guarded_v1(
  p_request_id uuid,
  p_expected_revision bigint,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_request public.support_requests%rowtype;
  v_run public.support_request_action_runs%rowtype;
  v_now timestamptz := now();
  v_event_id uuid;
  v_payload jsonb;
begin
  if v_user_id is null then
    raise exception 'Devi effettuare l''accesso.';
  end if;
  if p_request_id is null or p_idempotency_key is null then
    raise exception 'Dati della chiusura incompleti.';
  end if;
  if coalesce(p_expected_revision, 0) < 1 then
    raise exception 'Revisione della richiesta non valida.';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'leghevo:support:request:' || p_request_id::text,
      0
    )
  );

  select run.*
  into v_run
  from public.support_request_action_runs run
  where run.idempotency_key = p_idempotency_key;

  if found then
    if v_run.user_id <> v_user_id
      or v_run.action_type <> 'user_close'
      or v_run.request_id <> p_request_id then
      raise exception 'Identificativo già usato per un''altra operazione.';
    end if;
    return coalesce(
      public.support_request_payload_v1(v_run.request_id),
      v_run.result_snapshot
    ) || jsonb_build_object('idempotentReplay', true);
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
  if v_request.revision <> p_expected_revision then
    raise exception
      'La richiesta è stata aggiornata su un altro dispositivo. Ricarica e riprova.';
  end if;
  if v_request.status not in ('submitted', 'in_progress', 'waiting_user') then
    raise exception 'La richiesta è già conclusa.';
  end if;

  update public.support_requests request
  set
    status = 'closed',
    resolved_at = null,
    closed_at = v_now,
    updated_at = v_now,
    revision = request.revision + 1
  where request.id = v_request.id
  returning * into v_request;

  insert into public.support_request_events (
    request_id, actor_type, actor_user_id, event_type, status, occurred_at
  ) values (
    v_request.id, 'user', v_user_id, 'closed', 'closed', v_now
  )
  returning id into v_event_id;

  v_payload := public.support_request_payload_v1(v_request.id);

  insert into public.support_request_action_runs (
    user_id, request_id, actor_type, actor_user_id, action_type,
    idempotency_key, previous_revision, result_revision, result_status,
    payload_fingerprint, result_snapshot
  ) values (
    v_user_id, v_request.id, 'user', v_user_id, 'user_close',
    p_idempotency_key, p_expected_revision, v_request.revision,
    v_request.status,
    pg_catalog.md5('user_close' || E'\n' || v_request.id::text),
    public.support_request_certificate_v1(v_request.id)
  );

  return v_payload || jsonb_build_object(
    'eventId', v_event_id,
    'idempotentReplay', false
  );
end;
$$;

create or replace function public.process_support_request_guarded_v1(
  p_request_id uuid,
  p_status text,
  p_public_reply text,
  p_expected_revision bigint,
  p_idempotency_key uuid
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
  v_run public.support_request_action_runs%rowtype;
  v_now timestamptz := now();
  v_message_id uuid;
  v_event_id uuid;
  v_payload jsonb;
  v_changed boolean;
begin
  if p_request_id is null or p_idempotency_key is null then
    raise exception 'Dati della lavorazione incompleti.';
  end if;
  if coalesce(p_expected_revision, 0) < 1 then
    raise exception 'Revisione della richiesta non valida.';
  end if;
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

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'leghevo:support:request:' || p_request_id::text,
      0
    )
  );

  select request.*
  into v_request
  from public.support_requests request
  where request.id = p_request_id
  for update;

  if not found then
    raise exception 'Richiesta di assistenza non trovata.';
  end if;

  select run.*
  into v_run
  from public.support_request_action_runs run
  where run.idempotency_key = p_idempotency_key;

  if found then
    if v_run.action_type <> 'staff_process'
      or v_run.request_id <> p_request_id then
      raise exception 'Identificativo già usato per un''altra operazione.';
    end if;
    return coalesce(
      public.support_request_payload_v1(v_run.request_id),
      v_run.result_snapshot
    ) || jsonb_build_object('idempotentReplay', true);
  end if;

  if v_request.revision <> p_expected_revision then
    raise exception
      'La richiesta è stata aggiornata da un altro processo. Ricarica e riprova.';
  end if;
  if v_request.status in ('resolved', 'closed') then
    raise exception 'La richiesta di assistenza è già conclusa.';
  end if;

  v_changed := v_request.status <> v_status or v_reply is not null;

  if v_changed then
    update public.support_requests request
    set
      status = v_status,
      resolved_at = case when v_status = 'resolved' then v_now else null end,
      closed_at = null,
      updated_at = v_now,
      revision = request.revision + 1
    where request.id = v_request.id
    returning * into v_request;

    if v_reply is not null then
      insert into public.support_request_messages (
        request_id, author_type, actor_user_id, body, created_at
      ) values (
        v_request.id, 'support', auth.uid(), v_reply, v_now
      )
      returning id into v_message_id;
    end if;

    insert into public.support_request_events (
      request_id, actor_type, actor_user_id, event_type, status, occurred_at
    ) values (
      v_request.id,
      'support',
      auth.uid(),
      case when v_message_id is not null then 'support_replied'
           else 'status_changed' end,
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
        'supportStatus', v_request.status,
        'supportRevision', v_request.revision
      ),
      'support:' || v_request.id::text || ':revision:' || v_request.revision::text
    );
  end if;

  v_payload := public.support_request_payload_v1(v_request.id);

  insert into public.support_request_action_runs (
    user_id, request_id, actor_type, actor_user_id, action_type,
    idempotency_key, previous_revision, result_revision, result_status,
    payload_fingerprint, result_snapshot
  ) values (
    v_request.user_id, v_request.id, 'support', auth.uid(), 'staff_process',
    p_idempotency_key, p_expected_revision, v_request.revision,
    v_request.status,
    pg_catalog.md5(
      'staff_process' || E'\n' || v_status || E'\n' || coalesce(v_reply, '')
    ),
    public.support_request_certificate_v1(v_request.id)
  );

  return v_payload || jsonb_build_object(
    'messageId', v_message_id,
    'eventId', v_event_id,
    'idempotentReplay', not v_changed
  );
end;
$$;

-- Compatibilità: le RPC storiche restano disponibili, ma usano il percorso
-- protetto. Le nuove app inviano esplicitamente revisione e chiave operazione.
create or replace function public.get_my_support_center()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select public.get_my_support_center_v2();
$$;

create or replace function public.create_my_support_request(
  p_category text,
  p_subject text,
  p_message text,
  p_league_id uuid default null
)
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select public.create_my_support_request_guarded_v1(
    p_category,
    p_subject,
    p_message,
    p_league_id,
    gen_random_uuid()
  );
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
  v_revision bigint;
begin
  select request.revision
  into v_revision
  from public.support_requests request
  where request.id = p_request_id
    and request.user_id = auth.uid();

  return public.reply_to_my_support_request_guarded_v1(
    p_request_id,
    p_message,
    coalesce(v_revision, 0),
    gen_random_uuid()
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
  v_revision bigint;
begin
  select request.revision
  into v_revision
  from public.support_requests request
  where request.id = p_request_id
    and request.user_id = auth.uid();

  return public.close_my_support_request_guarded_v1(
    p_request_id,
    coalesce(v_revision, 0),
    gen_random_uuid()
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
  v_revision bigint;
begin
  select request.revision
  into v_revision
  from public.support_requests request
  where request.id = p_request_id;

  return public.process_support_request_guarded_v1(
    p_request_id,
    p_status,
    p_public_reply,
    coalesce(v_revision, 0),
    gen_random_uuid()
  );
end;
$$;

-- Permessi: utenti autenticati possono usare solo lettura e azioni proprie.
revoke all on function public.get_my_support_center_v2()
from public, anon;
revoke all on function public.create_my_support_request_guarded_v1(
  text, text, text, uuid, uuid
) from public, anon;
revoke all on function public.reply_to_my_support_request_guarded_v1(
  uuid, text, bigint, uuid
) from public, anon;
revoke all on function public.close_my_support_request_guarded_v1(
  uuid, bigint, uuid
) from public, anon;
revoke all on function public.process_support_request_guarded_v1(
  uuid, text, text, bigint, uuid
) from public, anon, authenticated;

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

grant execute on function public.get_my_support_center_v2()
to authenticated;
grant execute on function public.create_my_support_request_guarded_v1(
  text, text, text, uuid, uuid
) to authenticated;
grant execute on function public.reply_to_my_support_request_guarded_v1(
  uuid, text, bigint, uuid
) to authenticated;
grant execute on function public.close_my_support_request_guarded_v1(
  uuid, bigint, uuid
) to authenticated;
grant execute on function public.process_support_request_guarded_v1(
  uuid, text, text, bigint, uuid
) to service_role;

grant execute on function public.get_my_support_center()
to authenticated;
grant execute on function public.create_my_support_request(
  text, text, text, uuid
) to authenticated;
grant execute on function public.reply_to_my_support_request(uuid, text)
to authenticated;
grant execute on function public.close_my_support_request(uuid)
to authenticated;
grant execute on function public.process_support_request(uuid, text, text)
to service_role;

-- Le tabelle operative restano in sola lettura per l'app.
revoke insert, update, delete on public.support_requests
from authenticated, anon;
revoke insert, update, delete on public.support_request_messages
from authenticated, anon;
revoke insert, update, delete on public.support_request_events
from authenticated, anon;

-- Pubblicazione Realtime idempotente dei quattro registri del Centro Assistenza.
do $realtime$
declare
  v_table text;
begin
  if exists (
    select 1 from pg_publication publication
    where publication.pubname = 'supabase_realtime'
  ) then
    foreach v_table in array array[
      'support_requests',
      'support_request_messages',
      'support_request_events',
      'support_request_action_runs'
    ]
    loop
      if not exists (
        select 1
        from pg_publication_tables publication_table
        where publication_table.pubname = 'supabase_realtime'
          and publication_table.schemaname = 'public'
          and publication_table.tablename = v_table
      ) then
        execute format(
          'alter publication supabase_realtime add table public.%I',
          v_table
        );
      end if;
    end loop;
  end if;
end;
$realtime$;

create or replace function public.get_support_request_safety_integrity_v1()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'supportRequestsReady', to_regclass('public.support_requests') is not null,
    'supportMessagesReady', to_regclass('public.support_request_messages') is not null,
    'supportEventsReady', to_regclass('public.support_request_events') is not null,
    'actionRunsReady', to_regclass('public.support_request_action_runs') is not null,
    'revisionReady', exists (
      select 1 from information_schema.columns column_row
      where column_row.table_schema = 'public'
        and column_row.table_name = 'support_requests'
        and column_row.column_name = 'revision'
    ),
    'fingerprintReady', exists (
      select 1 from information_schema.columns column_row
      where column_row.table_schema = 'public'
        and column_row.table_name = 'support_requests'
        and column_row.column_name = 'request_fingerprint'
    ),
    'submissionKeyReady', exists (
      select 1 from information_schema.columns column_row
      where column_row.table_schema = 'public'
        and column_row.table_name = 'support_requests'
        and column_row.column_name = 'submission_request_id'
    ),
    'actionRunsRlsReady', coalesce((
      select class.relrowsecurity
      from pg_class class
      where class.oid = to_regclass('public.support_request_action_runs')
    ), false),
    'actionRunsImmutable', exists (
      select 1 from pg_trigger trigger_row
      where trigger_row.tgrelid = to_regclass('public.support_request_action_runs')
        and trigger_row.tgname = 'support_action_runs_immutable'
        and not trigger_row.tgisinternal
    ),
    'guardedCreateReady', to_regprocedure(
      'public.create_my_support_request_guarded_v1(text,text,text,uuid,uuid)'
    ) is not null,
    'guardedReplyReady', to_regprocedure(
      'public.reply_to_my_support_request_guarded_v1(uuid,text,bigint,uuid)'
    ) is not null,
    'guardedCloseReady', to_regprocedure(
      'public.close_my_support_request_guarded_v1(uuid,bigint,uuid)'
    ) is not null,
    'guardedProcessReady', to_regprocedure(
      'public.process_support_request_guarded_v1(uuid,text,text,bigint,uuid)'
    ) is not null,
    'centerV2Ready', to_regprocedure(
      'public.get_my_support_center_v2()'
    ) is not null,
    'authenticatedCreateReady', has_function_privilege(
      'authenticated',
      'public.create_my_support_request_guarded_v1(text,text,text,uuid,uuid)',
      'EXECUTE'
    ),
    'authenticatedReplyReady', has_function_privilege(
      'authenticated',
      'public.reply_to_my_support_request_guarded_v1(uuid,text,bigint,uuid)',
      'EXECUTE'
    ),
    'authenticatedCloseReady', has_function_privilege(
      'authenticated',
      'public.close_my_support_request_guarded_v1(uuid,bigint,uuid)',
      'EXECUTE'
    ),
    'staffProcessingProtected', not has_function_privilege(
      'authenticated',
      'public.process_support_request_guarded_v1(uuid,text,text,bigint,uuid)',
      'EXECUTE'
    ),
    'directWritesBlocked',
      not has_table_privilege('authenticated', 'public.support_requests', 'INSERT')
      and not has_table_privilege('authenticated', 'public.support_requests', 'UPDATE')
      and not has_table_privilege('authenticated', 'public.support_requests', 'DELETE')
      and not has_table_privilege('authenticated', 'public.support_request_messages', 'INSERT')
      and not has_table_privilege('authenticated', 'public.support_request_messages', 'UPDATE')
      and not has_table_privilege('authenticated', 'public.support_request_messages', 'DELETE')
      and not has_table_privilege('authenticated', 'public.support_request_events', 'INSERT')
      and not has_table_privilege('authenticated', 'public.support_request_events', 'UPDATE')
      and not has_table_privilege('authenticated', 'public.support_request_events', 'DELETE')
      and not has_table_privilege('authenticated', 'public.support_request_action_runs', 'INSERT')
      and not has_table_privilege('authenticated', 'public.support_request_action_runs', 'UPDATE')
      and not has_table_privilege('authenticated', 'public.support_request_action_runs', 'DELETE'),
    'realtimeReady', not exists (
      select required.table_name
      from (values
        ('support_requests'),
        ('support_request_messages'),
        ('support_request_events'),
        ('support_request_action_runs')
      ) as required(table_name)
      where not exists (
        select 1
        from pg_publication_tables publication_table
        where publication_table.pubname = 'supabase_realtime'
          and publication_table.schemaname = 'public'
          and publication_table.tablename = required.table_name
      )
    )
  );
$$;

revoke all on function public.get_support_request_safety_integrity_v1()
from public, anon;
grant execute on function public.get_support_request_safety_integrity_v1()
to authenticated, service_role;

commit;

-- Diagnostica conclusiva: devono comparire esattamente 20 valori true.
select
  to_regclass('public.support_requests') is not null
    as support_requests_ready,
  to_regclass('public.support_request_messages') is not null
    as support_messages_ready,
  to_regclass('public.support_request_events') is not null
    as support_events_ready,
  to_regclass('public.support_request_action_runs') is not null
    as support_action_runs_ready,
  exists (
    select 1 from information_schema.columns column_row
    where column_row.table_schema = 'public'
      and column_row.table_name = 'support_requests'
      and column_row.column_name = 'revision'
  ) as support_revision_ready,
  exists (
    select 1 from information_schema.columns column_row
    where column_row.table_schema = 'public'
      and column_row.table_name = 'support_requests'
      and column_row.column_name = 'request_fingerprint'
  ) as support_fingerprint_ready,
  exists (
    select 1 from information_schema.columns column_row
    where column_row.table_schema = 'public'
      and column_row.table_name = 'support_requests'
      and column_row.column_name = 'submission_request_id'
  ) as support_submission_key_ready,
  coalesce((
    select class.relrowsecurity
    from pg_class class
    where class.oid = to_regclass('public.support_request_action_runs')
  ), false) as support_action_runs_rls_ready,
  exists (
    select 1 from pg_trigger trigger_row
    where trigger_row.tgrelid = to_regclass('public.support_request_action_runs')
      and trigger_row.tgname = 'support_action_runs_immutable'
      and not trigger_row.tgisinternal
  ) as support_action_runs_immutable,
  to_regprocedure(
    'public.create_my_support_request_guarded_v1(text,text,text,uuid,uuid)'
  ) is not null as support_guarded_create_ready,
  to_regprocedure(
    'public.reply_to_my_support_request_guarded_v1(uuid,text,bigint,uuid)'
  ) is not null as support_guarded_reply_ready,
  to_regprocedure(
    'public.close_my_support_request_guarded_v1(uuid,bigint,uuid)'
  ) is not null as support_guarded_close_ready,
  to_regprocedure(
    'public.process_support_request_guarded_v1(uuid,text,text,bigint,uuid)'
  ) is not null as support_guarded_process_ready,
  to_regprocedure('public.get_my_support_center_v2()') is not null
    as support_center_v2_ready,
  has_function_privilege(
    'authenticated',
    'public.create_my_support_request_guarded_v1(text,text,text,uuid,uuid)',
    'EXECUTE'
  ) as support_authenticated_create_ready,
  has_function_privilege(
    'authenticated',
    'public.reply_to_my_support_request_guarded_v1(uuid,text,bigint,uuid)',
    'EXECUTE'
  ) as support_authenticated_reply_ready,
  has_function_privilege(
    'authenticated',
    'public.close_my_support_request_guarded_v1(uuid,bigint,uuid)',
    'EXECUTE'
  ) as support_authenticated_close_ready,
  not has_function_privilege(
    'authenticated',
    'public.process_support_request_guarded_v1(uuid,text,text,bigint,uuid)',
    'EXECUTE'
  ) as support_staff_processing_protected,
  (
    not has_table_privilege('authenticated', 'public.support_requests', 'INSERT')
    and not has_table_privilege('authenticated', 'public.support_requests', 'UPDATE')
    and not has_table_privilege('authenticated', 'public.support_requests', 'DELETE')
    and not has_table_privilege('authenticated', 'public.support_request_messages', 'INSERT')
    and not has_table_privilege('authenticated', 'public.support_request_messages', 'UPDATE')
    and not has_table_privilege('authenticated', 'public.support_request_messages', 'DELETE')
    and not has_table_privilege('authenticated', 'public.support_request_events', 'INSERT')
    and not has_table_privilege('authenticated', 'public.support_request_events', 'UPDATE')
    and not has_table_privilege('authenticated', 'public.support_request_events', 'DELETE')
    and not has_table_privilege('authenticated', 'public.support_request_action_runs', 'INSERT')
    and not has_table_privilege('authenticated', 'public.support_request_action_runs', 'UPDATE')
    and not has_table_privilege('authenticated', 'public.support_request_action_runs', 'DELETE')
  ) as support_direct_writes_blocked,
  not exists (
    select required.table_name
    from (values
      ('support_requests'),
      ('support_request_messages'),
      ('support_request_events'),
      ('support_request_action_runs')
    ) as required(table_name)
    where not exists (
      select 1
      from pg_publication_tables publication_table
      where publication_table.pubname = 'supabase_realtime'
        and publication_table.schemaname = 'public'
        and publication_table.tablename = required.table_name
    )
  ) as support_realtime_ready;
