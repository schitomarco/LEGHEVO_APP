-- LEGHEVO v0.61.1 · Richieste privacy protette e revisionate
-- Migrazione interna: database/095_data_rights_request_safety.sql
--
-- Obiettivi:
-- - submission/cancellazione idempotenti;
-- - revisione ottimistica contro azioni concorrenti;
-- - registro immutabile delle operazioni;
-- - compatibilità con le RPC storiche;
-- - nessuna modifica ai contenuti delle richieste già presenti.

begin;

-- Preflight dettagliato: in caso di dipendenza mancante il messaggio indica
-- esattamente l'oggetto da ripristinare prima di riprovare.
do $preflight$
declare
  v_missing text[] := array[]::text[];
  v_expected record;
begin
  if to_regclass('public.profiles') is null then
    v_missing := array_append(v_missing, 'table public.profiles');
  end if;
  if to_regclass('public.data_rights_requests') is null then
    v_missing := array_append(v_missing, 'table public.data_rights_requests');
  end if;
  if to_regclass('public.data_rights_request_events') is null then
    v_missing := array_append(v_missing, 'table public.data_rights_request_events');
  end if;
  if to_regprocedure('public.set_updated_at()') is null then
    v_missing := array_append(v_missing, 'function public.set_updated_at()');
  end if;

  for v_expected in
    select *
    from (values
      ('profiles', 'id'),
      ('profiles', 'deleted_at'),
      ('data_rights_requests', 'id'),
      ('data_rights_requests', 'user_id'),
      ('data_rights_requests', 'request_type'),
      ('data_rights_requests', 'details'),
      ('data_rights_requests', 'status'),
      ('data_rights_requests', 'response_note'),
      ('data_rights_requests', 'submitted_at'),
      ('data_rights_requests', 'due_at'),
      ('data_rights_requests', 'updated_at'),
      ('data_rights_requests', 'closed_at'),
      ('data_rights_request_events', 'id'),
      ('data_rights_request_events', 'request_id'),
      ('data_rights_request_events', 'actor_user_id'),
      ('data_rights_request_events', 'event_type'),
      ('data_rights_request_events', 'status'),
      ('data_rights_request_events', 'note'),
      ('data_rights_request_events', 'occurred_at')
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
      'Preflight v0.61.1 non superato. Oggetti mancanti: %',
      array_to_string(v_missing, '; ');
  end if;
end;
$preflight$;

alter table public.data_rights_requests
  add column if not exists revision bigint not null default 1,
  add column if not exists request_fingerprint text,
  add column if not exists submission_request_id uuid,
  add column if not exists cancellation_request_id uuid;

update public.data_rights_requests request
set request_fingerprint = md5(
  request.request_type || E'\n' || coalesce(request.details, '')
)
where request.request_fingerprint is null;

alter table public.data_rights_requests
  alter column request_fingerprint set not null;

alter table public.data_rights_requests
  drop constraint if exists data_rights_requests_revision_check;
alter table public.data_rights_requests
  add constraint data_rights_requests_revision_check
  check (revision > 0);

alter table public.data_rights_requests
  drop constraint if exists data_rights_requests_fingerprint_check;
alter table public.data_rights_requests
  add constraint data_rights_requests_fingerprint_check
  check (char_length(request_fingerprint) = 32);

create unique index if not exists data_rights_submission_request_unique_idx
  on public.data_rights_requests (user_id, submission_request_id)
  where submission_request_id is not null;

create unique index if not exists data_rights_cancellation_request_unique_idx
  on public.data_rights_requests (user_id, cancellation_request_id)
  where cancellation_request_id is not null;

create table if not exists public.data_rights_request_action_runs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete restrict,
  request_id uuid,
  action_type text not null check (
    action_type in ('submit', 'cancel', 'status_change')
  ),
  idempotency_key uuid not null,
  request_type text not null check (
    request_type in (
      'access',
      'rectification',
      'portability',
      'restriction',
      'objection',
      'erasure'
    )
  ),
  previous_revision bigint,
  result_revision bigint not null check (result_revision > 0),
  result_status text not null check (
    result_status in (
      'submitted',
      'in_review',
      'fulfilled',
      'rejected',
      'cancelled'
    )
  ),
  payload_fingerprint text not null check (
    char_length(payload_fingerprint) = 32
  ),
  result_snapshot jsonb not null check (
    jsonb_typeof(result_snapshot) = 'object'
  ),
  created_at timestamptz not null default now(),
  unique (user_id, idempotency_key)
);

-- Il registro conserva l'identificativo come fotografia, senza FK: in questo
-- modo la cancellazione dell'account può rimuovere la pratica operativa senza
-- alterare o cancellare il certificato immutabile dell'azione.
alter table public.data_rights_request_action_runs
  drop constraint if exists data_rights_request_action_runs_request_id_fkey;

create index if not exists data_rights_action_runs_request_idx
  on public.data_rights_request_action_runs (request_id, created_at desc);
create index if not exists data_rights_action_runs_user_idx
  on public.data_rights_request_action_runs (user_id, created_at desc);

alter table public.data_rights_request_action_runs enable row level security;
alter table public.data_rights_request_action_runs replica identity full;

drop policy if exists data_rights_action_runs_read_own
on public.data_rights_request_action_runs;
create policy data_rights_action_runs_read_own
on public.data_rights_request_action_runs
for select to authenticated
using (user_id = auth.uid());

revoke all on table public.data_rights_request_action_runs
from public, anon, authenticated;
grant select on table public.data_rights_request_action_runs
to authenticated;

create or replace function public.prevent_data_rights_action_run_mutation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  raise exception
    'Operazione privacy certificata: modifica o cancellazione diretta non consentita.';
end;
$$;

revoke all on function public.prevent_data_rights_action_run_mutation()
from public, anon, authenticated;

drop trigger if exists data_rights_action_runs_immutable
on public.data_rights_request_action_runs;
create trigger data_rights_action_runs_immutable
before update or delete on public.data_rights_request_action_runs
for each row execute function public.prevent_data_rights_action_run_mutation();

create or replace function public.data_rights_request_payload_v1(
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
    'requestType', request.request_type,
    'details', request.details,
    'status', request.status,
    'responseNote', request.response_note,
    'submittedAt', request.submitted_at,
    'dueAt', request.due_at,
    'updatedAt', request.updated_at,
    'closedAt', request.closed_at,
    'revision', request.revision,
    'protected', true,
    'canCancel', request.status in ('submitted', 'in_review'),
    'events', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', event.id,
          'eventType', event.event_type,
          'status', event.status,
          'note', event.note,
          'occurredAt', event.occurred_at
        )
        order by event.occurred_at, event.id
      )
      from public.data_rights_request_events event
      where event.request_id = request.id
    ), '[]'::jsonb)
  )
  into v_payload
  from public.data_rights_requests request
  where request.id = p_request_id;

  return v_payload;
end;
$$;

revoke all on function public.data_rights_request_payload_v1(uuid)
from public, anon, authenticated;


create or replace function public.data_rights_request_certificate_v1(
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
    'requestType', request.request_type,
    'status', request.status,
    'submittedAt', request.submitted_at,
    'dueAt', request.due_at,
    'updatedAt', request.updated_at,
    'closedAt', request.closed_at,
    'revision', request.revision,
    'protected', true,
    'canCancel', false,
    'details', null,
    'responseNote', null,
    'events', '[]'::jsonb
  )
  into v_certificate
  from public.data_rights_requests request
  where request.id = p_request_id;

  return v_certificate;
end;
$$;

revoke all on function public.data_rights_request_certificate_v1(uuid)
from public, anon, authenticated;

create or replace function public.get_my_data_rights_center_v2()
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
  v_total_count integer := 0;
begin
  if v_user_id is null then
    raise exception 'Devi effettuare l''accesso.';
  end if;

  select
    count(*) filter (
      where request.status in ('submitted', 'in_review')
    )::integer,
    count(*)::integer,
    coalesce(
      jsonb_agg(
        public.data_rights_request_payload_v1(request.id)
        order by request.submitted_at desc, request.id desc
      ),
      '[]'::jsonb
    )
  into v_open_count, v_total_count, v_requests
  from public.data_rights_requests request
  where request.user_id = v_user_id;

  return jsonb_build_object(
    'generatedAt', now(),
    'openCount', v_open_count,
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

create or replace function public.submit_my_data_rights_request_guarded_v1(
  p_request_type text,
  p_details text,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_request_type text := lower(trim(coalesce(p_request_type, '')));
  v_details text := nullif(trim(coalesce(p_details, '')), '');
  v_fingerprint text;
  v_request public.data_rights_requests%rowtype;
  v_run public.data_rights_request_action_runs%rowtype;
  v_payload jsonb;
begin
  if v_user_id is null then
    raise exception 'Devi effettuare l''accesso.';
  end if;
  if p_idempotency_key is null then
    raise exception 'Identificativo della richiesta mancante.';
  end if;
  if v_request_type not in (
    'access', 'rectification', 'portability',
    'restriction', 'objection', 'erasure'
  ) then
    raise exception 'Tipo di richiesta privacy non valido.';
  end if;
  if v_details is not null and char_length(v_details) > 2000 then
    raise exception 'La descrizione può contenere al massimo 2000 caratteri.';
  end if;
  if v_request_type in (
    'rectification', 'restriction', 'objection', 'erasure'
  ) and char_length(coalesce(v_details, '')) < 10 then
    raise exception 'Descrivi la richiesta con almeno 10 caratteri.';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'leghevo:data-rights:submit:' || v_user_id::text || ':' || v_request_type,
      0
    )
  );

  select run.*
  into v_run
  from public.data_rights_request_action_runs run
  where run.user_id = v_user_id
    and run.idempotency_key = p_idempotency_key;

  if found then
    if v_run.action_type <> 'submit' then
      raise exception 'Identificativo già usato per un''altra operazione.';
    end if;
    v_payload := coalesce(
      public.data_rights_request_payload_v1(v_run.request_id),
      v_run.result_snapshot
    );
    return v_payload || jsonb_build_object('idempotentReplay', true);
  end if;

  v_fingerprint := md5(v_request_type || E'\n' || coalesce(v_details, ''));

  select request.*
  into v_request
  from public.data_rights_requests request
  where request.user_id = v_user_id
    and request.request_type = v_request_type
    and request.status in ('submitted', 'in_review')
  for update;

  if found then
    if v_request.request_fingerprint <> v_fingerprint then
      raise exception 'Hai già una richiesta dello stesso tipo ancora aperta.';
    end if;

    v_payload := public.data_rights_request_payload_v1(v_request.id);
    insert into public.data_rights_request_action_runs (
      user_id,
      request_id,
      action_type,
      idempotency_key,
      request_type,
      previous_revision,
      result_revision,
      result_status,
      payload_fingerprint,
      result_snapshot
    ) values (
      v_user_id,
      v_request.id,
      'submit',
      p_idempotency_key,
      v_request.request_type,
      v_request.revision,
      v_request.revision,
      v_request.status,
      v_request.request_fingerprint,
      public.data_rights_request_certificate_v1(v_request.id)
    );
    return v_payload || jsonb_build_object('idempotentReplay', true);
  end if;

  insert into public.data_rights_requests (
    user_id,
    request_type,
    details,
    status,
    submitted_at,
    due_at,
    updated_at,
    revision,
    request_fingerprint,
    submission_request_id
  ) values (
    v_user_id,
    v_request_type,
    v_details,
    'submitted',
    now(),
    now() + interval '30 days',
    now(),
    1,
    v_fingerprint,
    p_idempotency_key
  )
  returning * into v_request;

  insert into public.data_rights_request_events (
    request_id,
    actor_user_id,
    event_type,
    status,
    note,
    occurred_at
  ) values (
    v_request.id,
    v_user_id,
    'submitted',
    'submitted',
    v_details,
    v_request.submitted_at
  );

  v_payload := public.data_rights_request_payload_v1(v_request.id);

  insert into public.data_rights_request_action_runs (
    user_id,
    request_id,
    action_type,
    idempotency_key,
    request_type,
    previous_revision,
    result_revision,
    result_status,
    payload_fingerprint,
    result_snapshot
  ) values (
    v_user_id,
    v_request.id,
    'submit',
    p_idempotency_key,
    v_request.request_type,
    null,
    v_request.revision,
    v_request.status,
    v_request.request_fingerprint,
    public.data_rights_request_certificate_v1(v_request.id)
  );

  return v_payload || jsonb_build_object('idempotentReplay', false);
end;
$$;

create or replace function public.cancel_my_data_rights_request_guarded_v1(
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
  v_request public.data_rights_requests%rowtype;
  v_run public.data_rights_request_action_runs%rowtype;
  v_now timestamptz := now();
  v_payload jsonb;
begin
  if v_user_id is null then
    raise exception 'Devi effettuare l''accesso.';
  end if;
  if p_request_id is null or p_idempotency_key is null then
    raise exception 'Dati dell''operazione privacy incompleti.';
  end if;
  if coalesce(p_expected_revision, 0) < 1 then
    raise exception 'Revisione della richiesta non valida.';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'leghevo:data-rights:request:' || p_request_id::text,
      0
    )
  );

  select run.*
  into v_run
  from public.data_rights_request_action_runs run
  where run.user_id = v_user_id
    and run.idempotency_key = p_idempotency_key;

  if found then
    if v_run.action_type <> 'cancel'
      or v_run.request_id is distinct from p_request_id then
      raise exception 'Identificativo già usato per un''altra operazione.';
    end if;
    v_payload := coalesce(
      public.data_rights_request_payload_v1(v_run.request_id),
      v_run.result_snapshot
    );
    return v_payload || jsonb_build_object('idempotentReplay', true);
  end if;

  select request.*
  into v_request
  from public.data_rights_requests request
  where request.id = p_request_id
    and request.user_id = v_user_id
  for update;

  if not found then
    raise exception 'Richiesta privacy non trovata.';
  end if;

  if v_request.status = 'cancelled' then
    v_payload := public.data_rights_request_payload_v1(v_request.id);
    insert into public.data_rights_request_action_runs (
      user_id, request_id, action_type, idempotency_key, request_type,
      previous_revision, result_revision, result_status,
      payload_fingerprint, result_snapshot
    ) values (
      v_user_id, v_request.id, 'cancel', p_idempotency_key,
      v_request.request_type, v_request.revision, v_request.revision,
      v_request.status, v_request.request_fingerprint,
      public.data_rights_request_certificate_v1(v_request.id)
    );
    return v_payload || jsonb_build_object('idempotentReplay', true);
  end if;

  if v_request.revision <> p_expected_revision then
    raise exception
      'La richiesta è stata aggiornata su un altro dispositivo. Ricarica e riprova.';
  end if;
  if v_request.status not in ('submitted', 'in_review') then
    raise exception 'La richiesta non può più essere annullata.';
  end if;

  update public.data_rights_requests request
  set
    status = 'cancelled',
    closed_at = v_now,
    updated_at = v_now,
    revision = request.revision + 1,
    cancellation_request_id = p_idempotency_key
  where request.id = v_request.id
  returning * into v_request;

  insert into public.data_rights_request_events (
    request_id, actor_user_id, event_type, status, note, occurred_at
  ) values (
    v_request.id,
    v_user_id,
    'cancelled',
    'cancelled',
    'Richiesta annullata dall''utente.',
    v_now
  );

  v_payload := public.data_rights_request_payload_v1(v_request.id);
  insert into public.data_rights_request_action_runs (
    user_id, request_id, action_type, idempotency_key, request_type,
    previous_revision, result_revision, result_status,
    payload_fingerprint, result_snapshot
  ) values (
    v_user_id, v_request.id, 'cancel', p_idempotency_key,
    v_request.request_type, p_expected_revision, v_request.revision,
    v_request.status, v_request.request_fingerprint,
    public.data_rights_request_certificate_v1(v_request.id)
  );

  return v_payload || jsonb_build_object('idempotentReplay', false);
end;
$$;

create or replace function public.set_data_rights_request_status_guarded_v1(
  p_request_id uuid,
  p_status text,
  p_response_note text,
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
  v_note text := nullif(trim(coalesce(p_response_note, '')), '');
  v_request public.data_rights_requests%rowtype;
  v_run public.data_rights_request_action_runs%rowtype;
  v_now timestamptz := now();
  v_payload jsonb;
begin
  if p_request_id is null or p_idempotency_key is null then
    raise exception 'Dati dell''operazione privacy incompleti.';
  end if;
  if v_status not in ('in_review', 'fulfilled', 'rejected') then
    raise exception 'Stato della richiesta privacy non valido.';
  end if;
  if v_note is not null and char_length(v_note) > 2000 then
    raise exception 'La risposta può contenere al massimo 2000 caratteri.';
  end if;
  if v_status in ('fulfilled', 'rejected')
    and char_length(coalesce(v_note, '')) < 10 then
    raise exception 'Inserisci una risposta di almeno 10 caratteri.';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'leghevo:data-rights:request:' || p_request_id::text,
      0
    )
  );

  select request.*
  into v_request
  from public.data_rights_requests request
  where request.id = p_request_id
  for update;

  if not found then
    raise exception 'Richiesta privacy non trovata.';
  end if;

  select run.*
  into v_run
  from public.data_rights_request_action_runs run
  where run.user_id = v_request.user_id
    and run.idempotency_key = p_idempotency_key;

  if found then
    if v_run.action_type <> 'status_change'
      or v_run.request_id is distinct from p_request_id then
      raise exception 'Identificativo già usato per un''altra operazione.';
    end if;
    v_payload := coalesce(
      public.data_rights_request_payload_v1(v_run.request_id),
      v_run.result_snapshot
    );
    return v_payload || jsonb_build_object('idempotentReplay', true);
  end if;

  if v_request.revision <> p_expected_revision then
    raise exception
      'La richiesta è stata aggiornata da un altro processo. Ricarica e riprova.';
  end if;
  if v_request.status not in ('submitted', 'in_review') then
    raise exception 'La richiesta privacy è già chiusa.';
  end if;

  if v_request.status = v_status then
    v_payload := public.data_rights_request_payload_v1(v_request.id);
  else
    update public.data_rights_requests request
    set
      status = v_status,
      response_note = coalesce(v_note, request.response_note),
      closed_at = case
        when v_status in ('fulfilled', 'rejected') then v_now
        else null
      end,
      updated_at = v_now,
      revision = request.revision + 1
    where request.id = v_request.id
    returning * into v_request;

    insert into public.data_rights_request_events (
      request_id, actor_user_id, event_type, status, note, occurred_at
    ) values (
      v_request.id,
      auth.uid(),
      'status_changed',
      v_request.status,
      v_note,
      v_now
    );
    v_payload := public.data_rights_request_payload_v1(v_request.id);
  end if;

  insert into public.data_rights_request_action_runs (
    user_id, request_id, action_type, idempotency_key, request_type,
    previous_revision, result_revision, result_status,
    payload_fingerprint, result_snapshot
  ) values (
    v_request.user_id, v_request.id, 'status_change', p_idempotency_key,
    v_request.request_type, p_expected_revision, v_request.revision,
    v_request.status, v_request.request_fingerprint,
    public.data_rights_request_certificate_v1(v_request.id)
  );

  return v_payload || jsonb_build_object('idempotentReplay', false);
end;
$$;

-- Compatibilità: le RPC storiche restano disponibili, ma passano tutte dal
-- percorso revisionato e idempotente.
create or replace function public.get_my_data_rights_center()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select public.get_my_data_rights_center_v2();
$$;

create or replace function public.submit_my_data_rights_request(
  p_request_type text,
  p_details text default null
)
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select public.submit_my_data_rights_request_guarded_v1(
    p_request_type,
    p_details,
    gen_random_uuid()
  );
$$;

create or replace function public.cancel_my_data_rights_request(
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
  from public.data_rights_requests request
  where request.id = p_request_id
    and request.user_id = auth.uid();

  return public.cancel_my_data_rights_request_guarded_v1(
    p_request_id,
    coalesce(v_revision, 0),
    gen_random_uuid()
  );
end;
$$;

create or replace function public.set_data_rights_request_status(
  p_request_id uuid,
  p_status text,
  p_response_note text default null
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
  from public.data_rights_requests request
  where request.id = p_request_id;

  return public.set_data_rights_request_status_guarded_v1(
    p_request_id,
    p_status,
    p_response_note,
    coalesce(v_revision, 0),
    gen_random_uuid()
  );
end;
$$;

revoke all on function public.get_my_data_rights_center_v2()
from public, anon;
revoke all on function public.submit_my_data_rights_request_guarded_v1(
  text, text, uuid
) from public, anon;
revoke all on function public.cancel_my_data_rights_request_guarded_v1(
  uuid, bigint, uuid
) from public, anon;
revoke all on function public.set_data_rights_request_status_guarded_v1(
  uuid, text, text, bigint, uuid
) from public, anon, authenticated;

revoke all on function public.get_my_data_rights_center()
from public, anon;
revoke all on function public.submit_my_data_rights_request(text, text)
from public, anon;
revoke all on function public.cancel_my_data_rights_request(uuid)
from public, anon;
revoke all on function public.set_data_rights_request_status(uuid, text, text)
from public, anon, authenticated;

grant execute on function public.get_my_data_rights_center_v2()
to authenticated;
grant execute on function public.submit_my_data_rights_request_guarded_v1(
  text, text, uuid
) to authenticated;
grant execute on function public.cancel_my_data_rights_request_guarded_v1(
  uuid, bigint, uuid
) to authenticated;
grant execute on function public.set_data_rights_request_status_guarded_v1(
  uuid, text, text, bigint, uuid
) to service_role;

grant execute on function public.get_my_data_rights_center()
to authenticated;
grant execute on function public.submit_my_data_rights_request(text, text)
to authenticated;
grant execute on function public.cancel_my_data_rights_request(uuid)
to authenticated;
grant execute on function public.set_data_rights_request_status(
  uuid, text, text
) to service_role;

-- Pubblicazione Realtime idempotente del Centro Diritti Privacy.
do $realtime$
declare
  v_table_name text;
begin
  if exists (
    select 1
    from pg_catalog.pg_publication publication
    where publication.pubname = 'supabase_realtime'
  ) then
    foreach v_table_name in array array[
      'data_rights_requests',
      'data_rights_request_events',
      'data_rights_request_action_runs'
    ] loop
      execute format(
        'alter table public.%I replica identity full',
        v_table_name
      );

      if not exists (
        select 1
        from pg_catalog.pg_publication_tables publication_table
        where publication_table.pubname = 'supabase_realtime'
          and publication_table.schemaname = 'public'
          and publication_table.tablename = v_table_name
      ) then
        execute format(
          'alter publication supabase_realtime add table public.%I',
          v_table_name
        );
      end if;
    end loop;
  end if;
end;
$realtime$;

create or replace function public.get_data_rights_request_safety_integrity_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_realtime_ready boolean;
begin
  select
    not exists (
      select 1
      from pg_catalog.pg_publication publication
      where publication.pubname = 'supabase_realtime'
    )
    or (
      select count(*) = 3
      from (values
        ('data_rights_requests'),
        ('data_rights_request_events'),
        ('data_rights_request_action_runs')
      ) expected(table_name)
      where exists (
        select 1
        from pg_catalog.pg_publication_tables publication_table
        where publication_table.pubname = 'supabase_realtime'
          and publication_table.schemaname = 'public'
          and publication_table.tablename = expected.table_name
      )
    )
  into v_realtime_ready;

  return jsonb_build_object(
    'requestRevisionColumnReady', exists (
      select 1 from information_schema.columns
      where table_schema = 'public'
        and table_name = 'data_rights_requests'
        and column_name = 'revision'
        and is_nullable = 'NO'
    ),
    'requestFingerprintColumnReady', exists (
      select 1 from information_schema.columns
      where table_schema = 'public'
        and table_name = 'data_rights_requests'
        and column_name = 'request_fingerprint'
        and is_nullable = 'NO'
    ),
    'submissionKeyColumnReady', exists (
      select 1 from information_schema.columns
      where table_schema = 'public'
        and table_name = 'data_rights_requests'
        and column_name = 'submission_request_id'
    ),
    'cancellationKeyColumnReady', exists (
      select 1 from information_schema.columns
      where table_schema = 'public'
        and table_name = 'data_rights_requests'
        and column_name = 'cancellation_request_id'
    ),
    'actionRunsTableReady', to_regclass(
      'public.data_rights_request_action_runs'
    ) is not null,
    'actionRunsColumnsReady', (
      select count(*) = 12
      from information_schema.columns column_row
      where column_row.table_schema = 'public'
        and column_row.table_name = 'data_rights_request_action_runs'
        and column_row.column_name in (
          'id', 'user_id', 'request_id', 'action_type', 'idempotency_key',
          'request_type', 'previous_revision', 'result_revision',
          'result_status', 'payload_fingerprint', 'result_snapshot', 'created_at'
        )
    ),
    'actionRunsRlsReady', coalesce((
      select relation.relrowsecurity
      from pg_catalog.pg_class relation
      join pg_catalog.pg_namespace namespace
        on namespace.oid = relation.relnamespace
      where namespace.nspname = 'public'
        and relation.relname = 'data_rights_request_action_runs'
    ), false),
    'actionRunsReadPolicyReady', exists (
      select 1 from pg_catalog.pg_policies policy
      where policy.schemaname = 'public'
        and policy.tablename = 'data_rights_request_action_runs'
        and policy.policyname = 'data_rights_action_runs_read_own'
    ),
    'actionRunsDirectWritesBlocked',
      not has_table_privilege(
        'authenticated',
        'public.data_rights_request_action_runs',
        'INSERT,UPDATE,DELETE'
      ),
    'immutableTriggerReady', exists (
      select 1
      from pg_catalog.pg_trigger trigger_row
      where trigger_row.tgrelid =
        'public.data_rights_request_action_runs'::regclass
        and trigger_row.tgname = 'data_rights_action_runs_immutable'
        and not trigger_row.tgisinternal
    ),
    'payloadBuilderReady',
      to_regprocedure(
        'public.data_rights_request_payload_v1(uuid)'
      ) is not null
      and to_regprocedure(
        'public.data_rights_request_certificate_v1(uuid)'
      ) is not null,
    'centerV2Ready', to_regprocedure(
      'public.get_my_data_rights_center_v2()'
    ) is not null,
    'guardedSubmitReady', to_regprocedure(
      'public.submit_my_data_rights_request_guarded_v1(text,text,uuid)'
    ) is not null,
    'guardedCancelReady', to_regprocedure(
      'public.cancel_my_data_rights_request_guarded_v1(uuid,bigint,uuid)'
    ) is not null,
    'guardedStatusReady', to_regprocedure(
      'public.set_data_rights_request_status_guarded_v1(uuid,text,text,bigint,uuid)'
    ) is not null,
    'legacySubmitRoutesGuarded', coalesce(
      pg_get_functiondef(
        to_regprocedure('public.submit_my_data_rights_request(text,text)')
      ) ilike '%submit_my_data_rights_request_guarded_v1%',
      false
    ),
    'legacyCancelRoutesGuarded', coalesce(
      pg_get_functiondef(
        to_regprocedure('public.cancel_my_data_rights_request(uuid)')
      ) ilike '%cancel_my_data_rights_request_guarded_v1%',
      false
    ),
    'authenticatedGuardedActionsReady',
      has_function_privilege(
        'authenticated',
        'public.submit_my_data_rights_request_guarded_v1(text,text,uuid)',
        'EXECUTE'
      ) and has_function_privilege(
        'authenticated',
        'public.cancel_my_data_rights_request_guarded_v1(uuid,bigint,uuid)',
        'EXECUTE'
      ),
    'anonymousGuardedActionsBlocked',
      not has_function_privilege(
        'anon',
        'public.submit_my_data_rights_request_guarded_v1(text,text,uuid)',
        'EXECUTE'
      ) and not has_function_privilege(
        'anon',
        'public.cancel_my_data_rights_request_guarded_v1(uuid,bigint,uuid)',
        'EXECUTE'
      ),
    'realtimeRegistryReady', v_realtime_ready
  );
end;
$$;

revoke all on function public.get_data_rights_request_safety_integrity_v1()
from public, anon;
grant execute on function public.get_data_rights_request_safety_integrity_v1()
to authenticated, service_role;

-- Validazione transazionale con dettaglio completo in caso di anomalia.
do $validation$
declare
  v_integrity jsonb;
  v_failures jsonb;
begin
  v_integrity := public.get_data_rights_request_safety_integrity_v1();

  select coalesce(jsonb_object_agg(entry.key, entry.value), '{}'::jsonb)
  into v_failures
  from jsonb_each(v_integrity) entry
  where entry.value <> 'true'::jsonb;

  if v_failures <> '{}'::jsonb then
    raise exception
      'Validazione v0.61.1 non superata. Controlli falsi: %',
      v_failures;
  end if;
end;
$validation$;

commit;

-- Diagnostica finale: devono comparire esattamente 20 valori true.
select
  (integrity ->> 'requestRevisionColumnReady')::boolean
    as request_revision_column_ready,
  (integrity ->> 'requestFingerprintColumnReady')::boolean
    as request_fingerprint_column_ready,
  (integrity ->> 'submissionKeyColumnReady')::boolean
    as submission_key_column_ready,
  (integrity ->> 'cancellationKeyColumnReady')::boolean
    as cancellation_key_column_ready,
  (integrity ->> 'actionRunsTableReady')::boolean
    as action_runs_table_ready,
  (integrity ->> 'actionRunsColumnsReady')::boolean
    as action_runs_columns_ready,
  (integrity ->> 'actionRunsRlsReady')::boolean
    as action_runs_rls_ready,
  (integrity ->> 'actionRunsReadPolicyReady')::boolean
    as action_runs_read_policy_ready,
  (integrity ->> 'actionRunsDirectWritesBlocked')::boolean
    as action_runs_direct_writes_blocked,
  (integrity ->> 'immutableTriggerReady')::boolean
    as immutable_trigger_ready,
  (integrity ->> 'payloadBuilderReady')::boolean
    as payload_builder_ready,
  (integrity ->> 'centerV2Ready')::boolean
    as center_v2_ready,
  (integrity ->> 'guardedSubmitReady')::boolean
    as guarded_submit_ready,
  (integrity ->> 'guardedCancelReady')::boolean
    as guarded_cancel_ready,
  (integrity ->> 'guardedStatusReady')::boolean
    as guarded_status_ready,
  (integrity ->> 'legacySubmitRoutesGuarded')::boolean
    as legacy_submit_routes_guarded,
  (integrity ->> 'legacyCancelRoutesGuarded')::boolean
    as legacy_cancel_routes_guarded,
  (integrity ->> 'authenticatedGuardedActionsReady')::boolean
    as authenticated_guarded_actions_ready,
  (integrity ->> 'anonymousGuardedActionsBlocked')::boolean
    as anonymous_guarded_actions_blocked,
  (integrity ->> 'realtimeRegistryReady')::boolean
    as realtime_registry_ready
from (
  select public.get_data_rights_request_safety_integrity_v1() as integrity
) diagnostics;
