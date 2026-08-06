-- LEGHEVO · Centro Diritti Privacy e richieste GDPR tracciate
-- Eseguire nel SQL Editor di Supabase dopo 049.
--
-- Lo script aggiunge struttura, letture e azioni protette. Non crea richieste,
-- non invia comunicazioni e non modifica account, leghe o dati sportivi.

create table if not exists public.data_rights_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
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
  details text,
  status text not null default 'submitted' check (
    status in (
      'submitted',
      'in_review',
      'fulfilled',
      'rejected',
      'cancelled'
    )
  ),
  response_note text,
  submitted_at timestamptz not null default now(),
  due_at timestamptz not null default (now() + interval '30 days'),
  updated_at timestamptz not null default now(),
  closed_at timestamptz,
  check (details is null or char_length(details) <= 2000),
  check (response_note is null or char_length(response_note) <= 2000),
  check (
    (status in ('fulfilled', 'rejected', 'cancelled') and closed_at is not null)
    or
    (status in ('submitted', 'in_review') and closed_at is null)
  )
);

create table if not exists public.data_rights_request_events (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null
    references public.data_rights_requests(id) on delete cascade,
  actor_user_id uuid references auth.users(id) on delete set null,
  event_type text not null check (
    event_type in ('submitted', 'status_changed', 'cancelled')
  ),
  status text not null check (
    status in (
      'submitted',
      'in_review',
      'fulfilled',
      'rejected',
      'cancelled'
    )
  ),
  note text,
  occurred_at timestamptz not null default now(),
  check (note is null or char_length(note) <= 2000)
);

create unique index if not exists data_rights_one_open_type_idx
  on public.data_rights_requests (user_id, request_type)
  where status in ('submitted', 'in_review');

create index if not exists data_rights_requests_user_date_idx
  on public.data_rights_requests (user_id, submitted_at desc);

create index if not exists data_rights_events_request_date_idx
  on public.data_rights_request_events (request_id, occurred_at, id);

drop trigger if exists data_rights_requests_set_updated_at
on public.data_rights_requests;

create trigger data_rights_requests_set_updated_at
before update on public.data_rights_requests
for each row execute function public.set_updated_at();

alter table public.data_rights_requests enable row level security;
alter table public.data_rights_request_events enable row level security;

drop policy if exists data_rights_requests_read_own
on public.data_rights_requests;

create policy data_rights_requests_read_own
on public.data_rights_requests for select to authenticated
using (user_id = auth.uid());

drop policy if exists data_rights_events_read_own
on public.data_rights_request_events;

create policy data_rights_events_read_own
on public.data_rights_request_events for select to authenticated
using (
  exists (
    select 1
    from public.data_rights_requests request
    where request.id = data_rights_request_events.request_id
      and request.user_id = auth.uid()
  )
);

revoke all on public.data_rights_requests from anon, authenticated;
revoke all on public.data_rights_request_events from anon, authenticated;
grant select on public.data_rights_requests to authenticated;
grant select on public.data_rights_request_events to authenticated;

create or replace function public.get_my_data_rights_center()
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
        jsonb_build_object(
          'id', request.id,
          'requestType', request.request_type,
          'details', request.details,
          'status', request.status,
          'responseNote', request.response_note,
          'submittedAt', request.submitted_at,
          'dueAt', request.due_at,
          'updatedAt', request.updated_at,
          'closedAt', request.closed_at,
          'canCancel',
            request.status in ('submitted', 'in_review'),
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
    'requests', v_requests
  );
end;
$$;

create or replace function public.submit_my_data_rights_request(
  p_request_type text,
  p_details text default null
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
  v_request public.data_rights_requests%rowtype;
begin
  if v_user_id is null then
    raise exception 'Devi effettuare l''accesso.';
  end if;

  if v_request_type not in (
    'access',
    'rectification',
    'portability',
    'restriction',
    'objection',
    'erasure'
  ) then
    raise exception 'Tipo di richiesta privacy non valido.';
  end if;

  if v_details is not null and char_length(v_details) > 2000 then
    raise exception 'La descrizione può contenere al massimo 2000 caratteri.';
  end if;

  if v_request_type in (
    'rectification',
    'restriction',
    'objection',
    'erasure'
  ) and char_length(coalesce(v_details, '')) < 10 then
    raise exception 'Descrivi la richiesta con almeno 10 caratteri.';
  end if;

  if exists (
    select 1
    from public.data_rights_requests request
    where request.user_id = v_user_id
      and request.request_type = v_request_type
      and request.status in ('submitted', 'in_review')
  ) then
    raise exception 'Hai già una richiesta dello stesso tipo ancora aperta.';
  end if;

  insert into public.data_rights_requests (
    user_id,
    request_type,
    details,
    status,
    submitted_at,
    due_at,
    updated_at
  )
  values (
    v_user_id,
    v_request_type,
    v_details,
    'submitted',
    now(),
    now() + interval '30 days',
    now()
  )
  returning * into v_request;

  insert into public.data_rights_request_events (
    request_id,
    actor_user_id,
    event_type,
    status,
    note,
    occurred_at
  )
  values (
    v_request.id,
    v_user_id,
    'submitted',
    'submitted',
    v_details,
    v_request.submitted_at
  );

  return jsonb_build_object(
    'id', v_request.id,
    'requestType', v_request.request_type,
    'details', v_request.details,
    'status', v_request.status,
    'responseNote', v_request.response_note,
    'submittedAt', v_request.submitted_at,
    'dueAt', v_request.due_at,
    'updatedAt', v_request.updated_at,
    'closedAt', v_request.closed_at,
    'canCancel', true,
    'events', jsonb_build_array(
      jsonb_build_object(
        'eventType', 'submitted',
        'status', 'submitted',
        'note', v_request.details,
        'occurredAt', v_request.submitted_at
      )
    )
  );
exception
  when unique_violation then
    raise exception 'Hai già una richiesta dello stesso tipo ancora aperta.';
end;
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
  v_user_id uuid := auth.uid();
  v_request public.data_rights_requests%rowtype;
  v_now timestamptz := now();
begin
  if v_user_id is null then
    raise exception 'Devi effettuare l''accesso.';
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

  if v_request.status not in ('submitted', 'in_review') then
    raise exception 'La richiesta non può più essere annullata.';
  end if;

  update public.data_rights_requests request
  set
    status = 'cancelled',
    closed_at = v_now,
    updated_at = v_now
  where request.id = v_request.id
  returning * into v_request;

  insert into public.data_rights_request_events (
    request_id,
    actor_user_id,
    event_type,
    status,
    note,
    occurred_at
  )
  values (
    v_request.id,
    v_user_id,
    'cancelled',
    'cancelled',
    'Richiesta annullata dall''utente.',
    v_now
  );

  return jsonb_build_object(
    'id', v_request.id,
    'status', v_request.status,
    'closedAt', v_request.closed_at,
    'canCancel', false
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
  v_status text := lower(trim(coalesce(p_status, '')));
  v_note text := nullif(trim(coalesce(p_response_note, '')), '');
  v_request public.data_rights_requests%rowtype;
  v_now timestamptz := now();
begin
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

  select request.*
  into v_request
  from public.data_rights_requests request
  where request.id = p_request_id
  for update;

  if not found then
    raise exception 'Richiesta privacy non trovata.';
  end if;

  if v_request.status not in ('submitted', 'in_review') then
    raise exception 'La richiesta privacy è già chiusa.';
  end if;

  if v_request.status = v_status then
    return jsonb_build_object(
      'id', v_request.id,
      'status', v_request.status,
      'responseNote', v_request.response_note,
      'updatedAt', v_request.updated_at,
      'closedAt', v_request.closed_at
    );
  end if;

  update public.data_rights_requests request
  set
    status = v_status,
    response_note = coalesce(v_note, request.response_note),
    closed_at = case
      when v_status in ('fulfilled', 'rejected') then v_now
      else null
    end,
    updated_at = v_now
  where request.id = v_request.id
  returning * into v_request;

  insert into public.data_rights_request_events (
    request_id,
    actor_user_id,
    event_type,
    status,
    note,
    occurred_at
  )
  values (
    v_request.id,
    auth.uid(),
    'status_changed',
    v_request.status,
    v_note,
    v_now
  );

  return jsonb_build_object(
    'id', v_request.id,
    'status', v_request.status,
    'responseNote', v_request.response_note,
    'updatedAt', v_request.updated_at,
    'closedAt', v_request.closed_at
  );
end;
$$;

create or replace function public.export_my_personal_data_v2()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_base jsonb;
  v_rights jsonb;
begin
  if v_user_id is null then
    raise exception 'Devi effettuare l''accesso.';
  end if;

  v_base := public.export_my_personal_data();
  v_rights := public.get_my_data_rights_center();

  return v_base || jsonb_build_object(
    'export_format', 'LEGHEVO-personal-data-v2',
    'data_rights_center', v_rights
  );
end;
$$;

revoke all on function public.get_my_data_rights_center()
from public, anon;
revoke all on function public.submit_my_data_rights_request(text, text)
from public, anon;
revoke all on function public.cancel_my_data_rights_request(uuid)
from public, anon;
revoke all on function public.set_data_rights_request_status(uuid, text, text)
from public, anon, authenticated;
revoke all on function public.export_my_personal_data_v2()
from public, anon;

grant execute on function public.get_my_data_rights_center()
to authenticated;
grant execute on function public.submit_my_data_rights_request(text, text)
to authenticated;
grant execute on function public.cancel_my_data_rights_request(uuid)
to authenticated;
grant execute on function public.set_data_rights_request_status(
  uuid,
  text,
  text
) to service_role;
grant execute on function public.export_my_personal_data_v2()
to authenticated;

select
  to_regclass('public.data_rights_requests') is not null
    as data_rights_requests_ready,
  to_regclass('public.data_rights_request_events') is not null
    as data_rights_events_ready,
  to_regprocedure(
    'public.get_my_data_rights_center()'
  ) is not null as data_rights_center_ready,
  to_regprocedure(
    'public.submit_my_data_rights_request(text,text)'
  ) is not null as data_rights_submit_ready,
  to_regprocedure(
    'public.cancel_my_data_rights_request(uuid)'
  ) is not null as data_rights_cancel_ready,
  to_regprocedure(
    'public.set_data_rights_request_status(uuid,text,text)'
  ) is not null as data_rights_processing_ready,
  to_regprocedure(
    'public.export_my_personal_data_v2()'
  ) is not null as personal_export_v2_ready,
  has_function_privilege(
    'authenticated',
    'public.get_my_data_rights_center()',
    'EXECUTE'
  ) as data_rights_read_access_ready,
  has_function_privilege(
    'authenticated',
    'public.submit_my_data_rights_request(text,text)',
    'EXECUTE'
  ) as data_rights_submit_access_ready,
  not has_function_privilege(
    'authenticated',
    'public.set_data_rights_request_status(uuid,text,text)',
    'EXECUTE'
  ) as data_rights_processing_protected,
  exists (
    select 1
    from pg_indexes index_info
    where index_info.schemaname = 'public'
      and index_info.indexname = 'data_rights_one_open_type_idx'
  ) as data_rights_duplicates_blocked,
  exists (
    select 1
    from pg_trigger trigger_info
    where trigger_info.tgname = 'data_rights_requests_set_updated_at'
      and not trigger_info.tgisinternal
  ) as data_rights_timestamp_ready;
