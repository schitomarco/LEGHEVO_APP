-- LEGHEVO v0.62.37
-- Outbox operativa transazionale, consegna monotona e dead-letter queue
-- Dipendenza: v0.62.36 validata con 20/20 controlli true.

begin;

do $preflight$
declare
  v_integrity jsonb;
  v_false text[];
begin
  if to_regprocedure('public.get_leghevo_operational_outbox_deployment_integrity_v1()') is not null
    and exists (
      select 1 from public.leghevo_application_release_certificates c
      where c.application_version = '0.62.37'
    ) then
    return;
  end if;

  if to_regprocedure('public.get_leghevo_authoritative_telemetry_deployment_integrity_v1()') is null then
    raise exception 'Preflight v0.62.37 non superato: diagnostica v0.62.36 assente.';
  end if;

  v_integrity := public.get_leghevo_authoritative_telemetry_deployment_integrity_v1();
  select array_agg(item.key order by item.key) into v_false
  from pg_catalog.jsonb_each(v_integrity) item
  where pg_catalog.jsonb_typeof(item.value) is distinct from 'boolean'
     or item.value is distinct from 'true'::jsonb;

  if (select count(*) from pg_catalog.jsonb_each(v_integrity)) <> 20
    or cardinality(v_false) > 0 then
    raise exception 'Preflight v0.62.37 non superato: %. Dettaglio: %',
      coalesce(array_to_string(v_false, ', '), 'numero controlli diverso da 20'),
      v_integrity;
  end if;
end;
$preflight$;

create or replace function public.compute_leghevo_operational_outbox_message_fingerprint_v1(
  p_environment_key text,
  p_source_table text,
  p_source_event_id bigint,
  p_source_request_id uuid,
  p_event_type text,
  p_aggregate_key text,
  p_stream_sequence bigint,
  p_priority text,
  p_payload jsonb,
  p_contract_version integer default 1
)
returns text
language sql
immutable
security definer
set search_path = ''
as $function$
  select pg_catalog.md5(
    coalesce(lower(trim(p_environment_key)), '') || '|' ||
    coalesce(lower(trim(p_source_table)), '') || '|' ||
    coalesce(p_source_event_id, 0)::text || '|' ||
    coalesce(p_source_request_id::text, '') || '|' ||
    coalesce(lower(trim(p_event_type)), '') || '|' ||
    coalesce(trim(p_aggregate_key), '') || '|' ||
    coalesce(p_stream_sequence, 0)::text || '|' ||
    coalesce(lower(trim(p_priority)), '') || '|' ||
    coalesce(p_payload, '{}'::jsonb)::text || '|' ||
    coalesce(p_contract_version, 0)::text
  );
$function$;

revoke all on function public.compute_leghevo_operational_outbox_message_fingerprint_v1(
  text,text,bigint,uuid,text,text,bigint,text,jsonb,integer
) from public, anon, authenticated;
grant execute on function public.compute_leghevo_operational_outbox_message_fingerprint_v1(
  text,text,bigint,uuid,text,text,bigint,text,jsonb,integer
) to service_role;

create or replace function public.compute_leghevo_operational_outbox_attempt_fingerprint_v1(
  p_message_id bigint,
  p_destination_key text,
  p_attempt_no integer,
  p_delivery_generation bigint,
  p_worker_key text,
  p_worker_generation bigint,
  p_outcome text,
  p_error_code text,
  p_response_fingerprint text,
  p_details jsonb
)
returns text
language sql
immutable
security definer
set search_path = ''
as $function$
  select pg_catalog.md5(
    coalesce(p_message_id, 0)::text || '|' ||
    coalesce(lower(trim(p_destination_key)), '') || '|' ||
    coalesce(p_attempt_no, 0)::text || '|' ||
    coalesce(p_delivery_generation, 0)::text || '|' ||
    coalesce(lower(trim(p_worker_key)), '') || '|' ||
    coalesce(p_worker_generation, 0)::text || '|' ||
    coalesce(lower(trim(p_outcome)), '') || '|' ||
    coalesce(lower(trim(p_error_code)), '') || '|' ||
    coalesce(lower(trim(p_response_fingerprint)), '') || '|' ||
    coalesce(p_details, '{}'::jsonb)::text
  );
$function$;

revoke all on function public.compute_leghevo_operational_outbox_attempt_fingerprint_v1(
  bigint,text,integer,bigint,text,bigint,text,text,text,jsonb
) from public, anon, authenticated;
grant execute on function public.compute_leghevo_operational_outbox_attempt_fingerprint_v1(
  bigint,text,integer,bigint,text,bigint,text,text,text,jsonb
) to service_role;

create or replace function public.compute_leghevo_operational_dead_letter_fingerprint_v1(
  p_message_id bigint,
  p_destination_key text,
  p_attempt_id bigint,
  p_reason_code text,
  p_message_fingerprint text
)
returns text
language sql
immutable
security definer
set search_path = ''
as $function$
  select pg_catalog.md5(
    coalesce(p_message_id, 0)::text || '|' ||
    coalesce(lower(trim(p_destination_key)), '') || '|' ||
    coalesce(p_attempt_id, 0)::text || '|' ||
    coalesce(lower(trim(p_reason_code)), '') || '|' ||
    coalesce(lower(trim(p_message_fingerprint)), '')
  );
$function$;

revoke all on function public.compute_leghevo_operational_dead_letter_fingerprint_v1(
  bigint,text,bigint,text,text
) from public, anon, authenticated;
grant execute on function public.compute_leghevo_operational_dead_letter_fingerprint_v1(
  bigint,text,bigint,text,text
) to service_role;

create table if not exists public.leghevo_operational_outbox_messages (
  id bigint generated by default as identity primary key,
  environment_key text not null,
  source_table text not null,
  source_event_id bigint not null,
  source_request_id uuid not null,
  event_type text not null,
  aggregate_key text not null,
  stream_sequence bigint not null,
  priority text not null default 'normal',
  payload jsonb not null default '{}'::jsonb,
  payload_contract_version integer not null default 1,
  message_fingerprint text not null unique,
  source_created_at timestamptz not null,
  created_at timestamptz not null default now(),
  created_by uuid null,
  constraint leghevo_outbox_message_environment_check
    check (environment_key in ('production','staging')),
  constraint leghevo_outbox_message_source_table_check
    check (source_table in (
      'leghevo_application_release_events',
      'leghevo_application_rollout_events',
      'leghevo_operational_telemetry_events'
    )),
  constraint leghevo_outbox_message_source_event_check
    check (source_event_id >= 1),
  constraint leghevo_outbox_message_event_type_check
    check (char_length(trim(event_type)) between 3 and 120),
  constraint leghevo_outbox_message_aggregate_check
    check (char_length(trim(aggregate_key)) between 1 and 160),
  constraint leghevo_outbox_message_sequence_check
    check (stream_sequence >= 1),
  constraint leghevo_outbox_message_priority_check
    check (priority in ('normal','critical')),
  constraint leghevo_outbox_message_payload_check
    check (jsonb_typeof(payload) = 'object'),
  constraint leghevo_outbox_message_contract_check
    check (payload_contract_version >= 1),
  constraint leghevo_outbox_message_fingerprint_check
    check (message_fingerprint ~ '^[0-9a-f]{32}$'),
  constraint leghevo_outbox_message_source_unique
    unique (source_table, source_event_id),
  constraint leghevo_outbox_message_sequence_unique
    unique (environment_key, stream_sequence)
);

create table if not exists public.leghevo_operational_outbox_delivery_heads (
  message_id bigint not null references public.leghevo_operational_outbox_messages(id) on delete restrict,
  destination_key text not null,
  generation bigint not null default 1,
  state text not null default 'pending',
  attempt_count integer not null default 0,
  worker_key text null,
  worker_generation bigint null,
  lease_token_hash text null,
  leased_until timestamptz null,
  next_attempt_at timestamptz null,
  delivered_at timestamptz null,
  last_attempt_id bigint null,
  last_error_code text null,
  updated_at timestamptz not null default now(),
  primary key (message_id, destination_key),
  constraint leghevo_outbox_delivery_destination_check
    check (destination_key in ('operations_center','notification_dispatch')),
  constraint leghevo_outbox_delivery_generation_check
    check (generation >= 1),
  constraint leghevo_outbox_delivery_state_check
    check (state in ('pending','leased','retry','delivered','dead_letter')),
  constraint leghevo_outbox_delivery_attempt_count_check
    check (attempt_count between 0 and 5),
  constraint leghevo_outbox_delivery_worker_check
    check (
      (worker_key is null and worker_generation is null)
      or (
        worker_key ~ '^[a-z0-9][a-z0-9._-]{2,79}$'
        and worker_generation >= 1
      )
    ),
  constraint leghevo_outbox_delivery_lease_hash_check
    check (lease_token_hash is null or lease_token_hash ~ '^[0-9a-f]{32}$'),
  constraint leghevo_outbox_delivery_state_shape_check
    check (
      (state = 'leased' and worker_key is not null and worker_generation is not null
        and lease_token_hash is not null and leased_until is not null)
      or (state <> 'leased' and lease_token_hash is null and leased_until is null)
    ),
  constraint leghevo_outbox_delivery_terminal_shape_check
    check (
      (state = 'delivered' and delivered_at is not null)
      or (state <> 'delivered' and delivered_at is null)
    ),
  constraint leghevo_outbox_delivery_retry_shape_check
    check (
      (state = 'retry' and next_attempt_at is not null)
      or (state <> 'retry' and next_attempt_at is null)
    ),
  constraint leghevo_outbox_delivery_error_check
    check (last_error_code is null or char_length(trim(last_error_code)) between 3 and 160)
);

create table if not exists public.leghevo_operational_outbox_delivery_attempts (
  id bigint generated by default as identity primary key,
  request_id uuid not null unique,
  message_id bigint not null,
  destination_key text not null,
  attempt_no integer not null,
  delivery_generation bigint not null,
  worker_key text not null,
  worker_generation bigint not null,
  outcome text not null,
  error_code text null,
  response_fingerprint text null,
  attempt_fingerprint text not null unique,
  details jsonb not null default '{}'::jsonb,
  started_at timestamptz not null,
  finished_at timestamptz not null default now(),
  recorded_by uuid null,
  constraint leghevo_outbox_attempt_head_fk
    foreign key (message_id, destination_key)
    references public.leghevo_operational_outbox_delivery_heads(message_id, destination_key)
    on delete restrict,
  constraint leghevo_outbox_attempt_destination_check
    check (destination_key in ('operations_center','notification_dispatch')),
  constraint leghevo_outbox_attempt_no_check
    check (attempt_no between 1 and 5),
  constraint leghevo_outbox_attempt_generation_check
    check (delivery_generation >= 1 and worker_generation >= 1),
  constraint leghevo_outbox_attempt_worker_check
    check (worker_key ~ '^[a-z0-9][a-z0-9._-]{2,79}$'),
  constraint leghevo_outbox_attempt_outcome_check
    check (outcome in ('delivered','retry','dead_letter')),
  constraint leghevo_outbox_attempt_error_check
    check (
      (outcome = 'delivered' and error_code is null)
      or (outcome <> 'delivered' and char_length(trim(error_code)) between 3 and 160)
    ),
  constraint leghevo_outbox_attempt_response_check
    check (response_fingerprint is null or response_fingerprint ~ '^[0-9a-f]{64}$'),
  constraint leghevo_outbox_attempt_fingerprint_check
    check (attempt_fingerprint ~ '^[0-9a-f]{32}$'),
  constraint leghevo_outbox_attempt_details_check
    check (jsonb_typeof(details) = 'object'),
  constraint leghevo_outbox_attempt_time_check
    check (finished_at >= started_at),
  constraint leghevo_outbox_attempt_sequence_unique
    unique (message_id, destination_key, attempt_no),
  constraint leghevo_outbox_attempt_identity_unique
    unique (id, message_id, destination_key)
);

create table if not exists public.leghevo_operational_outbox_dead_letters (
  id bigint generated by default as identity primary key,
  message_id bigint not null,
  destination_key text not null,
  attempt_id bigint not null references public.leghevo_operational_outbox_delivery_attempts(id) on delete restrict,
  reason_code text not null,
  message_fingerprint text not null,
  dead_letter_fingerprint text not null unique,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  created_by uuid null,
  constraint leghevo_outbox_dead_letter_head_fk
    foreign key (message_id, destination_key)
    references public.leghevo_operational_outbox_delivery_heads(message_id, destination_key)
    on delete restrict,
  constraint leghevo_outbox_dead_letter_destination_check
    check (destination_key in ('operations_center','notification_dispatch')),
  constraint leghevo_outbox_dead_letter_reason_check
    check (char_length(trim(reason_code)) between 3 and 160),
  constraint leghevo_outbox_dead_letter_message_fingerprint_check
    check (message_fingerprint ~ '^[0-9a-f]{32}$'),
  constraint leghevo_outbox_dead_letter_fingerprint_check
    check (dead_letter_fingerprint ~ '^[0-9a-f]{32}$'),
  constraint leghevo_outbox_dead_letter_details_check
    check (jsonb_typeof(details) = 'object'),
  constraint leghevo_outbox_dead_letter_message_unique
    unique (message_id, destination_key)
);

create index if not exists leghevo_outbox_messages_environment_sequence_idx
on public.leghevo_operational_outbox_messages(environment_key, stream_sequence);
create index if not exists leghevo_outbox_messages_priority_created_idx
on public.leghevo_operational_outbox_messages(environment_key, priority, created_at, id);
create index if not exists leghevo_outbox_delivery_claim_idx
on public.leghevo_operational_outbox_delivery_heads(destination_key, state, next_attempt_at, leased_until, message_id);
create index if not exists leghevo_outbox_attempts_message_destination_idx
on public.leghevo_operational_outbox_delivery_attempts(message_id, destination_key, attempt_no desc);
create index if not exists leghevo_outbox_dead_letters_created_idx
on public.leghevo_operational_outbox_dead_letters(created_at desc, id desc);

do $constraints$
begin
  if not exists (
    select 1 from pg_catalog.pg_constraint c
    where c.conrelid = 'public.leghevo_operational_outbox_delivery_heads'::regclass
      and c.conname = 'leghevo_outbox_delivery_last_attempt_fk'
  ) then
    alter table public.leghevo_operational_outbox_delivery_heads
      add constraint leghevo_outbox_delivery_last_attempt_fk
      foreign key (last_attempt_id, message_id, destination_key)
      references public.leghevo_operational_outbox_delivery_attempts(
        id, message_id, destination_key
      )
      on delete restrict;
  end if;
end;
$constraints$;

alter table public.leghevo_operational_outbox_messages enable row level security;
alter table public.leghevo_operational_outbox_delivery_heads enable row level security;
alter table public.leghevo_operational_outbox_delivery_attempts enable row level security;
alter table public.leghevo_operational_outbox_dead_letters enable row level security;
alter table public.leghevo_operational_outbox_dead_letters replica identity full;

-- La coda completa e i dettagli di errore restano backend-only. L'app legge
-- esclusivamente il riepilogo sanificato esposto dalla RPC del Centro Operativo.
drop policy if exists leghevo_outbox_dead_letters_read on public.leghevo_operational_outbox_dead_letters;

revoke all on table public.leghevo_operational_outbox_messages
from public, anon, authenticated, service_role;
revoke all on table public.leghevo_operational_outbox_delivery_heads
from public, anon, authenticated, service_role;
revoke all on table public.leghevo_operational_outbox_delivery_attempts
from public, anon, authenticated, service_role;
revoke all on table public.leghevo_operational_outbox_dead_letters
from public, anon, authenticated, service_role;
grant select on table public.leghevo_operational_outbox_dead_letters
to service_role;

create or replace function public.guard_leghevo_operational_outbox_immutable_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if current_setting('leghevo.operational_outbox_context', true) is distinct from 'allowed' then
    raise exception 'Scrittura diretta outbox operativa non consentita.';
  end if;
  if tg_op <> 'INSERT' then
    raise exception 'Record outbox immutabile: % non consentito.', tg_op;
  end if;
  return new;
end;
$function$;

revoke all on function public.guard_leghevo_operational_outbox_immutable_v1()
from public, anon, authenticated, service_role;

create or replace function public.guard_leghevo_operational_outbox_delivery_head_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if current_setting('leghevo.operational_outbox_context', true) is distinct from 'allowed' then
    raise exception 'Testa consegna outbox protetta: modifica diretta non consentita.';
  end if;
  if tg_op = 'DELETE' then
    raise exception 'Testa consegna outbox non eliminabile.';
  end if;
  if tg_op = 'INSERT' then
    return new;
  end if;
  if old.state in ('delivered','dead_letter') then
    raise exception 'Consegna terminale non modificabile.';
  end if;
  if new.generation <= old.generation then
    raise exception 'Generazione consegna non monotona.';
  end if;
  if new.attempt_count < old.attempt_count then
    raise exception 'Tentativi consegna non monotoni.';
  end if;
  if old.worker_generation is not null
    and new.worker_generation is not null
    and new.worker_generation < old.worker_generation then
    raise exception 'Fencing worker consegna non monotono.';
  end if;
  return new;
end;
$function$;

revoke all on function public.guard_leghevo_operational_outbox_delivery_head_v1()
from public, anon, authenticated, service_role;


drop trigger if exists leghevo_outbox_messages_guard on public.leghevo_operational_outbox_messages;
create trigger leghevo_outbox_messages_guard
before insert or update or delete on public.leghevo_operational_outbox_messages
for each row execute function public.guard_leghevo_operational_outbox_immutable_v1();
alter table public.leghevo_operational_outbox_messages
  enable always trigger leghevo_outbox_messages_guard;

drop trigger if exists leghevo_outbox_attempts_guard on public.leghevo_operational_outbox_delivery_attempts;
create trigger leghevo_outbox_attempts_guard
before insert or update or delete on public.leghevo_operational_outbox_delivery_attempts
for each row execute function public.guard_leghevo_operational_outbox_immutable_v1();
alter table public.leghevo_operational_outbox_delivery_attempts
  enable always trigger leghevo_outbox_attempts_guard;

drop trigger if exists leghevo_outbox_dead_letters_guard on public.leghevo_operational_outbox_dead_letters;
create trigger leghevo_outbox_dead_letters_guard
before insert or update or delete on public.leghevo_operational_outbox_dead_letters
for each row execute function public.guard_leghevo_operational_outbox_immutable_v1();
alter table public.leghevo_operational_outbox_dead_letters
  enable always trigger leghevo_outbox_dead_letters_guard;

drop trigger if exists leghevo_outbox_delivery_heads_guard on public.leghevo_operational_outbox_delivery_heads;
create trigger leghevo_outbox_delivery_heads_guard
before insert or update or delete on public.leghevo_operational_outbox_delivery_heads
for each row execute function public.guard_leghevo_operational_outbox_delivery_head_v1();
alter table public.leghevo_operational_outbox_delivery_heads
  enable always trigger leghevo_outbox_delivery_heads_guard;


create or replace function public.enqueue_leghevo_operational_outbox_message_v1(
  p_environment_key text,
  p_source_table text,
  p_source_event_id bigint,
  p_source_request_id uuid,
  p_event_type text,
  p_aggregate_key text,
  p_payload jsonb,
  p_priority text,
  p_source_created_at timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_environment text := lower(trim(coalesce(p_environment_key, '')));
  v_source_table text := lower(trim(coalesce(p_source_table, '')));
  v_event_type text := lower(trim(coalesce(p_event_type, '')));
  v_aggregate_key text := trim(coalesce(p_aggregate_key, ''));
  v_priority text := lower(trim(coalesce(p_priority, 'normal')));
  v_payload jsonb := coalesce(p_payload, '{}'::jsonb);
  v_message public.leghevo_operational_outbox_messages%rowtype;
  v_sequence bigint;
  v_fingerprint text;
begin
  if v_environment not in ('production','staging')
    or v_source_table not in (
      'leghevo_application_release_events',
      'leghevo_application_rollout_events',
      'leghevo_operational_telemetry_events'
    )
    or coalesce(p_source_event_id, 0) < 1
    or p_source_request_id is null
    or char_length(v_event_type) < 3
    or char_length(v_aggregate_key) < 1
    or jsonb_typeof(v_payload) is distinct from 'object'
    or v_priority not in ('normal','critical')
    or p_source_created_at is null then
    raise exception 'Messaggio outbox non valido.';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('leghevo:operational-outbox:' || v_environment, 0));

  select message.* into v_message
  from public.leghevo_operational_outbox_messages message
  where message.source_table = v_source_table
    and message.source_event_id = p_source_event_id;
  if found then
    return jsonb_build_object(
      'messageId', v_message.id,
      'streamSequence', v_message.stream_sequence,
      'messageFingerprint', v_message.message_fingerprint,
      'reused', true
    );
  end if;

  select coalesce(max(message.stream_sequence), 0) + 1 into v_sequence
  from public.leghevo_operational_outbox_messages message
  where message.environment_key = v_environment;

  v_fingerprint := public.compute_leghevo_operational_outbox_message_fingerprint_v1(
    v_environment, v_source_table, p_source_event_id, p_source_request_id,
    v_event_type, v_aggregate_key, v_sequence, v_priority, v_payload, 1
  );

  perform set_config('leghevo.operational_outbox_context', 'allowed', true);
  insert into public.leghevo_operational_outbox_messages(
    environment_key, source_table, source_event_id, source_request_id,
    event_type, aggregate_key, stream_sequence, priority, payload,
    payload_contract_version, message_fingerprint, source_created_at, created_by
  ) values (
    v_environment, v_source_table, p_source_event_id, p_source_request_id,
    v_event_type, v_aggregate_key, v_sequence, v_priority, v_payload,
    1, v_fingerprint, p_source_created_at, auth.uid()
  ) returning * into v_message;

  insert into public.leghevo_operational_outbox_delivery_heads(
    message_id, destination_key, generation, state, attempt_count, updated_at
  ) values
    (v_message.id, 'operations_center', 1, 'pending', 0, now()),
    (v_message.id, 'notification_dispatch', 1, 'pending', 0, now());
  perform set_config('leghevo.operational_outbox_context', '', true);

  return jsonb_build_object(
    'messageId', v_message.id,
    'streamSequence', v_message.stream_sequence,
    'messageFingerprint', v_message.message_fingerprint,
    'reused', false
  );
exception when others then
  perform set_config('leghevo.operational_outbox_context', '', true);
  raise;
end;
$function$;

revoke all on function public.enqueue_leghevo_operational_outbox_message_v1(
  text,text,bigint,uuid,text,text,jsonb,text,timestamptz
) from public, anon, authenticated, service_role;

create or replace function public.capture_leghevo_operational_event_to_outbox_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_row jsonb := to_jsonb(new);
  v_priority text;
  v_aggregate_key text;
  v_outcome jsonb;
begin
  v_priority := case
    when lower(coalesce(v_row ->> 'event_type', '')) in (
      'affected','critical','killed','rollback_activated','health_rejected'
    ) then 'critical'
    else 'normal'
  end;
  v_aggregate_key := coalesce(
    nullif(v_row ->> 'to_release_id', ''),
    nullif(v_row ->> 'plan_id', ''),
    nullif(v_row ->> 'source_id', ''),
    v_row ->> 'environment_key'
  );

  v_outcome := public.enqueue_leghevo_operational_outbox_message_v1(
    v_row ->> 'environment_key',
    tg_table_name,
    (v_row ->> 'id')::bigint,
    (v_row ->> 'request_id')::uuid,
    v_row ->> 'event_type',
    v_aggregate_key,
    jsonb_build_object(
      'sourceTable', tg_table_name,
      'sourceEventId', (v_row ->> 'id')::bigint,
      'eventType', v_row ->> 'event_type',
      'generation', coalesce((v_row ->> 'generation')::bigint, 0),
      'reasonCode', v_row ->> 'reason_code',
      'details', coalesce(v_row -> 'details', '{}'::jsonb),
      'createdAt', v_row ->> 'created_at'
    ),
    v_priority,
    (v_row ->> 'created_at')::timestamptz
  );
  return new;
end;
$function$;

revoke all on function public.capture_leghevo_operational_event_to_outbox_v1()
from public, anon, authenticated, service_role;


drop trigger if exists leghevo_release_events_outbox_capture
on public.leghevo_application_release_events;
create trigger leghevo_release_events_outbox_capture
after insert on public.leghevo_application_release_events
for each row execute function public.capture_leghevo_operational_event_to_outbox_v1();
alter table public.leghevo_application_release_events
  enable always trigger leghevo_release_events_outbox_capture;

drop trigger if exists leghevo_rollout_events_outbox_capture
on public.leghevo_application_rollout_events;
create trigger leghevo_rollout_events_outbox_capture
after insert on public.leghevo_application_rollout_events
for each row execute function public.capture_leghevo_operational_event_to_outbox_v1();
alter table public.leghevo_application_rollout_events
  enable always trigger leghevo_rollout_events_outbox_capture;

drop trigger if exists leghevo_telemetry_events_outbox_capture
on public.leghevo_operational_telemetry_events;
create trigger leghevo_telemetry_events_outbox_capture
after insert on public.leghevo_operational_telemetry_events
for each row execute function public.capture_leghevo_operational_event_to_outbox_v1();
alter table public.leghevo_operational_telemetry_events
  enable always trigger leghevo_telemetry_events_outbox_capture;


create or replace function public.claim_leghevo_operational_outbox_v1(
  p_environment_key text,
  p_destination_key text,
  p_worker_key text,
  p_worker_generation bigint,
  p_fencing_token uuid,
  p_batch_size integer default 25,
  p_lease_seconds integer default 60
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_environment text := lower(trim(coalesce(p_environment_key, '')));
  v_destination text := lower(trim(coalesce(p_destination_key, '')));
  v_worker text := lower(trim(coalesce(p_worker_key, '')));
  v_token_hash text;
  v_items jsonb := '[]'::jsonb;
  v_now timestamptz := now();
  v_row record;
  v_new_generation bigint;
begin
  if v_environment not in ('production','staging')
    or v_destination not in ('operations_center','notification_dispatch')
    or v_worker !~ '^[a-z0-9][a-z0-9._-]{2,79}$'
    or coalesce(p_worker_generation, 0) < 1
    or p_fencing_token is null
    or p_batch_size not between 1 and 200
    or p_lease_seconds not between 15 and 300 then
    raise exception 'Richiesta claim outbox non valida.';
  end if;
  v_token_hash := pg_catalog.md5(p_fencing_token::text);

  perform set_config('leghevo.operational_outbox_context', 'allowed', true);
  for v_row in
    select
      head.message_id,
      head.destination_key,
      head.generation,
      message.stream_sequence,
      message.event_type,
      message.aggregate_key,
      message.priority,
      message.payload,
      message.message_fingerprint,
      message.source_created_at
    from public.leghevo_operational_outbox_delivery_heads head
    join public.leghevo_operational_outbox_messages message
      on message.id = head.message_id
    where message.environment_key = v_environment
      and head.destination_key = v_destination
      and (
        (head.state in ('pending','retry')
          and coalesce(head.next_attempt_at, '-infinity'::timestamptz) <= v_now)
        or (head.state = 'leased' and head.leased_until < v_now)
      )
      and coalesce(head.worker_generation, 0) <= p_worker_generation
    order by
      case when message.priority = 'critical' then 0 else 1 end,
      message.stream_sequence
    limit p_batch_size
    for update of head skip locked
  loop
    v_new_generation := v_row.generation + 1;
    update public.leghevo_operational_outbox_delivery_heads
    set generation = v_new_generation,
        state = 'leased',
        worker_key = v_worker,
        worker_generation = p_worker_generation,
        lease_token_hash = v_token_hash,
        leased_until = v_now + make_interval(secs => p_lease_seconds),
        next_attempt_at = null,
        delivered_at = null,
        updated_at = v_now
    where message_id = v_row.message_id
      and destination_key = v_destination;

    v_items := v_items || jsonb_build_array(jsonb_build_object(
      'messageId', v_row.message_id,
      'destinationKey', v_destination,
      'deliveryGeneration', v_new_generation,
      'streamSequence', v_row.stream_sequence,
      'eventType', v_row.event_type,
      'aggregateKey', v_row.aggregate_key,
      'priority', v_row.priority,
      'payload', v_row.payload,
      'messageFingerprint', v_row.message_fingerprint,
      'sourceCreatedAt', v_row.source_created_at,
      'leasedUntil', v_now + make_interval(secs => p_lease_seconds)
    ));
  end loop;
  perform set_config('leghevo.operational_outbox_context', '', true);

  return jsonb_build_object(
    'environment', v_environment,
    'destinationKey', v_destination,
    'workerGeneration', p_worker_generation,
    'claimedCount', jsonb_array_length(v_items),
    'items', v_items,
    'checkedAt', v_now
  );
exception when others then
  perform set_config('leghevo.operational_outbox_context', '', true);
  raise;
end;
$function$;

revoke all on function public.claim_leghevo_operational_outbox_v1(
  text,text,text,bigint,uuid,integer,integer
) from public, anon, authenticated;
grant execute on function public.claim_leghevo_operational_outbox_v1(
  text,text,text,bigint,uuid,integer,integer
) to service_role;

create or replace function public.complete_leghevo_operational_outbox_delivery_v1(
  p_message_id bigint,
  p_destination_key text,
  p_delivery_generation bigint,
  p_worker_key text,
  p_worker_generation bigint,
  p_fencing_token uuid,
  p_outcome text,
  p_error_code text,
  p_response_fingerprint text,
  p_request_id uuid,
  p_details jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_destination text := lower(trim(coalesce(p_destination_key, '')));
  v_worker text := lower(trim(coalesce(p_worker_key, '')));
  v_outcome text := lower(trim(coalesce(p_outcome, '')));
  v_error_code text := nullif(lower(trim(coalesce(p_error_code, ''))), '');
  v_details jsonb := coalesce(p_details, '{}'::jsonb);
  v_token_hash text;
  v_head public.leghevo_operational_outbox_delivery_heads%rowtype;
  v_message public.leghevo_operational_outbox_messages%rowtype;
  v_existing public.leghevo_operational_outbox_delivery_attempts%rowtype;
  v_attempt public.leghevo_operational_outbox_delivery_attempts%rowtype;
  v_attempt_no integer;
  v_effective_outcome text;
  v_attempt_fingerprint text;
  v_dead_letter_fingerprint text;
  v_retry_seconds integer;
begin
  if coalesce(p_message_id, 0) < 1
    or v_destination not in ('operations_center','notification_dispatch')
    or coalesce(p_delivery_generation, 0) < 1
    or v_worker !~ '^[a-z0-9][a-z0-9._-]{2,79}$'
    or coalesce(p_worker_generation, 0) < 1
    or p_fencing_token is null
    or v_outcome not in ('delivered','retry','dead_letter')
    or p_request_id is null
    or jsonb_typeof(v_details) is distinct from 'object'
    or (p_response_fingerprint is not null
      and p_response_fingerprint !~ '^[0-9a-f]{64}$') then
    raise exception 'Completamento consegna outbox non valido.';
  end if;

  select attempt.* into v_existing
  from public.leghevo_operational_outbox_delivery_attempts attempt
  where attempt.request_id = p_request_id;
  if found then
    if v_existing.message_id <> p_message_id
      or v_existing.destination_key <> v_destination then
      raise exception 'request_id già utilizzato per una consegna diversa.';
    end if;
    return jsonb_build_object(
      'messageId', v_existing.message_id,
      'destinationKey', v_existing.destination_key,
      'attemptNo', v_existing.attempt_no,
      'outcome', v_existing.outcome,
      'reused', true
    );
  end if;

  select head.* into strict v_head
  from public.leghevo_operational_outbox_delivery_heads head
  where head.message_id = p_message_id
    and head.destination_key = v_destination
  for update;
  select message.* into strict v_message
  from public.leghevo_operational_outbox_messages message
  where message.id = p_message_id;

  v_token_hash := pg_catalog.md5(p_fencing_token::text);
  if v_head.state <> 'leased'
    or v_head.generation <> p_delivery_generation
    or v_head.worker_key <> v_worker
    or v_head.worker_generation <> p_worker_generation
    or v_head.lease_token_hash <> v_token_hash
    or v_head.leased_until < now() then
    raise exception 'Lease o fencing consegna non più valido.';
  end if;

  v_attempt_no := v_head.attempt_count + 1;
  v_effective_outcome := case
    when v_outcome = 'retry' and v_attempt_no >= 5 then 'dead_letter'
    else v_outcome
  end;
  if v_effective_outcome <> 'delivered' and v_error_code is null then
    v_error_code := 'delivery.unknown_error';
  end if;
  if v_effective_outcome = 'delivered' then
    v_error_code := null;
  end if;

  v_attempt_fingerprint := public.compute_leghevo_operational_outbox_attempt_fingerprint_v1(
    p_message_id, v_destination, v_attempt_no, p_delivery_generation,
    v_worker, p_worker_generation, v_effective_outcome, v_error_code,
    p_response_fingerprint, v_details
  );

  perform set_config('leghevo.operational_outbox_context', 'allowed', true);
  insert into public.leghevo_operational_outbox_delivery_attempts(
    request_id, message_id, destination_key, attempt_no,
    delivery_generation, worker_key, worker_generation, outcome,
    error_code, response_fingerprint, attempt_fingerprint,
    details, started_at, finished_at, recorded_by
  ) values (
    p_request_id, p_message_id, v_destination, v_attempt_no,
    p_delivery_generation, v_worker, p_worker_generation, v_effective_outcome,
    v_error_code, p_response_fingerprint, v_attempt_fingerprint,
    v_details, now(), now(), auth.uid()
  ) returning * into v_attempt;

  if v_effective_outcome = 'delivered' then
    update public.leghevo_operational_outbox_delivery_heads
    set generation = generation + 1,
        state = 'delivered',
        attempt_count = v_attempt_no,
        worker_key = v_worker,
        worker_generation = p_worker_generation,
        lease_token_hash = null,
        leased_until = null,
        next_attempt_at = null,
        delivered_at = now(),
        last_attempt_id = v_attempt.id,
        last_error_code = null,
        updated_at = now()
    where message_id = p_message_id and destination_key = v_destination;
  elsif v_effective_outcome = 'retry' then
    v_retry_seconds := least(300, power(2, v_attempt_no)::integer * 5);
    update public.leghevo_operational_outbox_delivery_heads
    set generation = generation + 1,
        state = 'retry',
        attempt_count = v_attempt_no,
        worker_key = v_worker,
        worker_generation = p_worker_generation,
        lease_token_hash = null,
        leased_until = null,
        next_attempt_at = now() + make_interval(secs => v_retry_seconds),
        delivered_at = null,
        last_attempt_id = v_attempt.id,
        last_error_code = v_error_code,
        updated_at = now()
    where message_id = p_message_id and destination_key = v_destination;
  else
    v_dead_letter_fingerprint := public.compute_leghevo_operational_dead_letter_fingerprint_v1(
      p_message_id, v_destination, v_attempt.id, v_error_code,
      v_message.message_fingerprint
    );
    insert into public.leghevo_operational_outbox_dead_letters(
      message_id, destination_key, attempt_id, reason_code,
      message_fingerprint, dead_letter_fingerprint, details, created_by
    ) values (
      p_message_id, v_destination, v_attempt.id, v_error_code,
      v_message.message_fingerprint, v_dead_letter_fingerprint,
      v_details || jsonb_build_object('attemptNo', v_attempt_no), auth.uid()
    ) on conflict (message_id, destination_key) do nothing;

    update public.leghevo_operational_outbox_delivery_heads
    set generation = generation + 1,
        state = 'dead_letter',
        attempt_count = v_attempt_no,
        worker_key = v_worker,
        worker_generation = p_worker_generation,
        lease_token_hash = null,
        leased_until = null,
        next_attempt_at = null,
        delivered_at = null,
        last_attempt_id = v_attempt.id,
        last_error_code = v_error_code,
        updated_at = now()
    where message_id = p_message_id and destination_key = v_destination;
  end if;
  perform set_config('leghevo.operational_outbox_context', '', true);

  return jsonb_build_object(
    'messageId', p_message_id,
    'destinationKey', v_destination,
    'attemptNo', v_attempt_no,
    'outcome', v_effective_outcome,
    'deadLettered', v_effective_outcome = 'dead_letter',
    'reused', false
  );
exception when no_data_found then
  perform set_config('leghevo.operational_outbox_context', '', true);
  raise exception 'Messaggio o testa consegna outbox non disponibile.';
when others then
  perform set_config('leghevo.operational_outbox_context', '', true);
  raise;
end;
$function$;

revoke all on function public.complete_leghevo_operational_outbox_delivery_v1(
  bigint,text,bigint,text,bigint,uuid,text,text,text,uuid,jsonb
) from public, anon, authenticated;
grant execute on function public.complete_leghevo_operational_outbox_delivery_v1(
  bigint,text,bigint,text,bigint,uuid,text,text,text,uuid,jsonb
) to service_role;

create or replace function public.get_leghevo_operational_outbox_model_v1(
  p_environment_key text default 'production'
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_environment text := lower(trim(coalesce(p_environment_key, '')));
  v_message_count bigint := 0;
  v_pending_count bigint := 0;
  v_leased_count bigint := 0;
  v_retry_count bigint := 0;
  v_delivered_count bigint := 0;
  v_dead_letter_count bigint := 0;
  v_dead_letter_record_count bigint := 0;
  v_expired_lease_count bigint := 0;
  v_fingerprint_mismatch_count bigint := 0;
  v_sequence_gap_count bigint := 0;
  v_delivery_head_mismatch_count bigint := 0;
  v_delivery_consistency_mismatch_count bigint := 0;
  v_last_sequence bigint := 0;
  v_oldest_pending_at timestamptz;
  v_last_delivered_at timestamptz;
  v_last_dead_letter_at timestamptz;
  v_capture_ready boolean := false;
  v_protected boolean := false;
  v_healthy boolean := false;
  v_status text;
  v_reason text;
begin
  if v_environment not in ('production','staging') then
    return jsonb_build_object(
      'protected', false, 'healthy', false, 'status', 'affected',
      'reasonCode', 'outbox.invalid_environment', 'environment', v_environment
    );
  end if;

  select count(*), coalesce(max(message.stream_sequence), 0)
  into v_message_count, v_last_sequence
  from public.leghevo_operational_outbox_messages message
  where message.environment_key = v_environment;

  select
    count(*) filter (where head.state = 'pending'),
    count(*) filter (where head.state = 'leased'),
    count(*) filter (where head.state = 'retry'),
    count(*) filter (where head.state = 'delivered'),
    count(*) filter (where head.state = 'dead_letter'),
    count(*) filter (where head.state = 'leased' and head.leased_until < now()),
    min(message.created_at) filter (where head.state in ('pending','retry','leased')),
    max(head.delivered_at) filter (where head.state = 'delivered')
  into
    v_pending_count, v_leased_count, v_retry_count, v_delivered_count,
    v_dead_letter_count, v_expired_lease_count,
    v_oldest_pending_at, v_last_delivered_at
  from public.leghevo_operational_outbox_delivery_heads head
  join public.leghevo_operational_outbox_messages message
    on message.id = head.message_id
  where message.environment_key = v_environment;

  select count(*), max(dead.created_at)
  into v_dead_letter_record_count, v_last_dead_letter_at
  from public.leghevo_operational_outbox_dead_letters dead
  join public.leghevo_operational_outbox_messages message
    on message.id = dead.message_id
  where message.environment_key = v_environment;

  select count(*) into v_delivery_head_mismatch_count
  from (
    select message.id
    from public.leghevo_operational_outbox_messages message
    left join public.leghevo_operational_outbox_delivery_heads head
      on head.message_id = message.id
    where message.environment_key = v_environment
    group by message.id
    having count(head.destination_key) <> 2
  ) incomplete_message;
  v_delivery_consistency_mismatch_count :=
    v_delivery_head_mismatch_count
    + pg_catalog.abs(v_dead_letter_count - v_dead_letter_record_count);

  select count(*) into v_fingerprint_mismatch_count
  from public.leghevo_operational_outbox_messages message
  where message.environment_key = v_environment
    and message.message_fingerprint is distinct from
      public.compute_leghevo_operational_outbox_message_fingerprint_v1(
        message.environment_key, message.source_table, message.source_event_id,
        message.source_request_id, message.event_type, message.aggregate_key,
        message.stream_sequence, message.priority, message.payload,
        message.payload_contract_version
      );

  select count(*) into v_sequence_gap_count
  from (
    select sequence_row.stream_sequence,
      lag(sequence_row.stream_sequence) over (order by sequence_row.stream_sequence) as previous_sequence
    from public.leghevo_operational_outbox_messages sequence_row
    where sequence_row.environment_key = v_environment
  ) sequence_check
  where (previous_sequence is null and stream_sequence <> 1)
     or (previous_sequence is not null and stream_sequence <> previous_sequence + 1);

  v_capture_ready :=
    exists (select 1 from pg_catalog.pg_trigger t
      where t.tgrelid = 'public.leghevo_application_release_events'::regclass
        and t.tgname = 'leghevo_release_events_outbox_capture'
        and t.tgenabled = 'A' and not t.tgisinternal)
    and exists (select 1 from pg_catalog.pg_trigger t
      where t.tgrelid = 'public.leghevo_application_rollout_events'::regclass
        and t.tgname = 'leghevo_rollout_events_outbox_capture'
        and t.tgenabled = 'A' and not t.tgisinternal)
    and exists (select 1 from pg_catalog.pg_trigger t
      where t.tgrelid = 'public.leghevo_operational_telemetry_events'::regclass
        and t.tgname = 'leghevo_telemetry_events_outbox_capture'
        and t.tgenabled = 'A' and not t.tgisinternal);

  v_protected := v_capture_ready
    and v_fingerprint_mismatch_count = 0
    and v_sequence_gap_count = 0
    and v_delivery_consistency_mismatch_count = 0;
  v_healthy := v_protected
    and v_dead_letter_count = 0
    and v_expired_lease_count = 0
    and v_retry_count = 0;
  v_status := case
    when not v_protected then 'affected'
    when v_dead_letter_count > 0 then 'dead_letter'
    when v_expired_lease_count > 0 or v_retry_count > 0 then 'attention'
    else 'active'
  end;
  v_reason := case
    when not v_capture_ready then 'outbox.capture_not_protected'
    when v_fingerprint_mismatch_count > 0 then 'outbox.message_fingerprint_changed'
    when v_sequence_gap_count > 0 then 'outbox.sequence_gap'
    when v_delivery_consistency_mismatch_count > 0 then 'outbox.delivery_consistency_mismatch'
    when v_dead_letter_count > 0 then 'outbox.dead_letter_present'
    when v_expired_lease_count > 0 then 'outbox.lease_expired'
    when v_retry_count > 0 then 'outbox.retry_pending'
    else 'outbox.active'
  end;

  return jsonb_build_object(
    'protected', v_protected,
    'healthy', v_healthy,
    'status', v_status,
    'reasonCode', v_reason,
    'environment', v_environment,
    'captureReady', v_capture_ready,
    'messageCount', v_message_count,
    'destinationCount', v_message_count * 2,
    'pendingCount', v_pending_count,
    'leasedCount', v_leased_count,
    'retryCount', v_retry_count,
    'deliveredCount', v_delivered_count,
    'deadLetterCount', v_dead_letter_count,
    'expiredLeaseCount', v_expired_lease_count,
    'lastSequence', v_last_sequence,
    'sequenceGapCount', v_sequence_gap_count,
    'fingerprintMismatchCount', v_fingerprint_mismatch_count,
    'deliveryHeadMismatchCount', v_delivery_head_mismatch_count,
    'deliveryConsistencyMismatchCount', v_delivery_consistency_mismatch_count,
    'oldestPendingAt', v_oldest_pending_at,
    'lastDeliveredAt', v_last_delivered_at,
    'lastDeadLetterAt', v_last_dead_letter_at,
    'checkedAt', now()
  );
end;
$function$;

revoke all on function public.get_leghevo_operational_outbox_model_v1(text)
from public, anon;
grant execute on function public.get_leghevo_operational_outbox_model_v1(text)
to authenticated, service_role;

create or replace function public.promote_leghevo_application_rollout_v3(
  p_environment_key text,
  p_target_percentage integer,
  p_request_id uuid,
  p_reason text default 'rollout.outbox_protected_promotion'
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_environment text := lower(trim(coalesce(p_environment_key, '')));
  v_outbox jsonb;
begin
  if v_environment not in ('production','staging') or p_request_id is null then
    raise exception 'Promozione con barriera outbox non valida.';
  end if;

  v_outbox := public.get_leghevo_operational_outbox_model_v1(v_environment);
  if not coalesce((v_outbox ->> 'protected')::boolean, false)
    or coalesce((v_outbox ->> 'deadLetterCount')::bigint, 0) > 0 then
    raise exception 'Promozione bloccata: outbox operativa non protetta o con dead-letter. Dettaglio: %',
      v_outbox;
  end if;

  return public.promote_leghevo_application_rollout_v2(
    v_environment, p_target_percentage, p_request_id, trim(p_reason));
end;
$function$;

revoke all on function public.promote_leghevo_application_rollout_v3(
  text,integer,uuid,text
) from public, anon, authenticated;
grant execute on function public.promote_leghevo_application_rollout_v3(
  text,integer,uuid,text
) to service_role;

-- Dopo l'installazione della migrazione 141 il worker deve passare dalla v3,
-- che combina telemetria autorevole e integrità dell'outbox.
revoke execute on function public.promote_leghevo_application_rollout_v2(
  text,integer,uuid,text
) from service_role;

create or replace function public.get_leghevo_client_rollout_eligibility_v3(
  p_application_version text,
  p_bundle_fingerprint text,
  p_installation_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_base jsonb;
  v_outbox jsonb;
  v_base_compatible boolean;
  v_outbox_ready boolean;
  v_compatible boolean;
  v_reason text;
begin
  v_base := public.get_leghevo_client_rollout_eligibility_v2(
    p_application_version, p_bundle_fingerprint, p_installation_id);
  v_outbox := public.get_leghevo_operational_outbox_model_v1('production');
  v_base_compatible := coalesce((v_base ->> 'compatible')::boolean, false);
  v_outbox_ready := coalesce((v_outbox ->> 'protected')::boolean, false)
    and coalesce((v_outbox ->> 'deadLetterCount')::bigint, 0) = 0;
  v_compatible := v_base_compatible and v_outbox_ready;
  v_reason := case
    when not v_base_compatible then coalesce(v_base ->> 'reasonCode', 'release.incompatible')
    when not coalesce((v_outbox ->> 'protected')::boolean, false)
      then coalesce(v_outbox ->> 'reasonCode', 'outbox.affected')
    when coalesce((v_outbox ->> 'deadLetterCount')::bigint, 0) > 0
      then 'outbox.dead_letter_present'
    else coalesce(v_base ->> 'reasonCode', 'rollout.eligible')
  end;

  return v_base || jsonb_build_object(
    'compatible', v_compatible,
    'reasonCode', v_reason,
    'outboxProtected', coalesce((v_outbox ->> 'protected')::boolean, false),
    'outboxHealthy', coalesce((v_outbox ->> 'healthy')::boolean, false),
    'outboxStatus', v_outbox ->> 'status',
    'outboxPendingCount', coalesce((v_outbox ->> 'pendingCount')::bigint, 0),
    'outboxDeadLetterCount', coalesce((v_outbox ->> 'deadLetterCount')::bigint, 0),
    'checkedAt', now()
  );
end;
$function$;

revoke all on function public.get_leghevo_client_rollout_eligibility_v3(text,text,uuid)
from public;
grant execute on function public.get_leghevo_client_rollout_eligibility_v3(text,text,uuid)
to anon, authenticated, service_role;

create or replace function public.get_league_provider_sync_health_v36(p_league_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_base jsonb;
  v_outbox jsonb;
begin
  v_base := public.get_league_provider_sync_health_v35(p_league_id);
  v_outbox := public.get_leghevo_operational_outbox_model_v1('production');
  return v_base || jsonb_build_object(
    'applicationOperationalOutbox', v_outbox,
    'healthy', coalesce((v_base ->> 'healthy')::boolean, false)
      and coalesce((v_outbox ->> 'healthy')::boolean, false),
    'protected', coalesce((v_base ->> 'protected')::boolean, false)
      and coalesce((v_outbox ->> 'protected')::boolean, false)
  );
end;
$function$;

revoke all on function public.get_league_provider_sync_health_v36(uuid)
from public, anon;
grant execute on function public.get_league_provider_sync_health_v36(uuid)
to authenticated;

create or replace function public.get_league_season_state_v15(p_league_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_base jsonb;
  v_outbox jsonb;
begin
  v_base := public.get_league_season_state_v14(p_league_id);
  v_outbox := public.get_leghevo_operational_outbox_model_v1('production');
  return v_base || jsonb_build_object('applicationOperationalOutbox', v_outbox);
end;
$function$;

revoke all on function public.get_league_season_state_v15(uuid)
from public, anon;
grant execute on function public.get_league_season_state_v15(uuid)
to authenticated;

create or replace function public.get_league_management_state_v25(p_league_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_base jsonb;
  v_outbox jsonb;
  v_checks jsonb;
begin
  v_base := public.get_league_management_state_v24(p_league_id);
  v_outbox := public.get_leghevo_operational_outbox_model_v1('production');
  v_checks := coalesce(v_base -> 'checks', '{}'::jsonb) || jsonb_build_object(
    'applicationOperationalOutboxProtected',
      coalesce((v_outbox ->> 'protected')::boolean, false),
    'applicationOperationalOutboxHealthy',
      coalesce((v_outbox ->> 'healthy')::boolean, false)
  );
  return v_base || jsonb_build_object(
    'applicationOperationalOutbox', v_outbox,
    'checks', v_checks
  );
end;
$function$;

revoke all on function public.get_league_management_state_v25(uuid)
from public, anon;
grant execute on function public.get_league_management_state_v25(uuid)
to authenticated;

-- Backfill idempotente degli eventi operativi già certificati.
do $backfill$
declare
  v_event record;
  v_outcome jsonb;
begin
  for v_event in
    select * from (
      select
        'leghevo_application_release_events'::text as source_table,
        event.id as source_event_id,
        event.environment_key,
        event.request_id,
        event.event_type,
        event.generation,
        event.reason_code,
        event.details,
        event.created_at,
        coalesce(event.to_release_id::text, event.environment_key) as aggregate_key
      from public.leghevo_application_release_events event
      union all
      select
        'leghevo_application_rollout_events'::text,
        event.id, event.environment_key, event.request_id, event.event_type,
        event.generation, event.reason_code, event.details, event.created_at,
        event.plan_id::text
      from public.leghevo_application_rollout_events event
      union all
      select
        'leghevo_operational_telemetry_events'::text,
        event.id, event.environment_key, event.request_id, event.event_type,
        event.generation, event.reason_code, event.details, event.created_at,
        event.source_id::text
      from public.leghevo_operational_telemetry_events event
    ) source_events
    order by created_at, source_table, source_event_id
  loop
    v_outcome := public.enqueue_leghevo_operational_outbox_message_v1(
      v_event.environment_key,
      v_event.source_table,
      v_event.source_event_id,
      v_event.request_id,
      v_event.event_type,
      v_event.aggregate_key,
      jsonb_build_object(
        'sourceTable', v_event.source_table,
        'sourceEventId', v_event.source_event_id,
        'eventType', v_event.event_type,
        'generation', v_event.generation,
        'reasonCode', v_event.reason_code,
        'details', coalesce(v_event.details, '{}'::jsonb),
        'createdAt', v_event.created_at
      ),
      case when lower(v_event.event_type) in (
        'affected','critical','killed','rollback_activated','health_rejected'
      ) then 'critical' else 'normal' end,
      v_event.created_at
    );
  end loop;
end;
$backfill$;

-- Realtime espone soltanto la dead-letter queue priva di payload e token.
do $realtime$
begin
  if exists (select 1 from pg_catalog.pg_publication p where p.pubname = 'supabase_realtime')
    and not exists (
      select 1 from pg_catalog.pg_publication_tables pt
      where pt.pubname = 'supabase_realtime'
        and pt.schemaname = 'public'
        and pt.tablename = 'leghevo_operational_outbox_dead_letters'
    ) then
    alter publication supabase_realtime
      add table public.leghevo_operational_outbox_dead_letters;
  end if;
end;
$realtime$;

-- Certificazione della release v0.62.37, rollout autorevole e cattura outbox.
do $seed_release$
declare
  v_outcome jsonb;
  v_now timestamptz := now();
  v_token uuid := gen_random_uuid();
begin
  if exists (
    select 1 from public.leghevo_application_release_certificates c
    where c.application_version = '0.62.37'
  ) and exists (
    select 1 from public.leghevo_operational_telemetry_observations o
    where o.request_id = '62370000-0000-4000-8000-000000000014'::uuid
  ) then
    return;
  end if;

  v_outcome := public.certify_leghevo_application_release_v1(
    '0.62.37',
    'c72b1e6b37afe352df30bf33db2d900d580420df042a9f5052754dd75af13630',
    '0.62.36', '0.62.37',
    '62370000-0000-4000-8000-000000000001'::uuid,
    jsonb_build_object('baseline', false, 'sourceMigration', 141)
  );
  v_outcome := public.certify_leghevo_application_rollout_v1(
    'production', '0.62.37', 10, 100, 500, 3, 100,
    '62370000-0000-4000-8000-000000000002'::uuid,
    jsonb_build_object('strategy', 'transactional-outbox', 'sourceMigration', 141)
  );
  v_outcome := public.activate_leghevo_release_with_rollout_v1(
    'production', '0.62.37',
    '62370000-0000-4000-8000-000000000003'::uuid,
    '62370000-0000-4000-8000-000000000004'::uuid,
    'outbox.production_activation'
  );
  v_outcome := public.certify_leghevo_operational_telemetry_source_v1(
    'production', 'leghevo-production-observer', 2, v_token,
    '62370000-0000-4000-8000-000000000005'::uuid,
    jsonb_build_object('provider', 'leghevo-runtime', 'sourceMigration', 141, 'fencing', true)
  );

  v_outcome := public.record_leghevo_authoritative_operational_window_v1(
    'production', 'leghevo-production-observer', 2, v_token, 1,
    v_now - interval '25 minutes', v_now - interval '20 minutes',
    1000, 2, 0, 240,
    '62370000-0000-4000-8000-000000000006'::uuid,
    jsonb_build_object('seedStage', 10)
  );
  v_outcome := public.promote_leghevo_application_rollout_v3(
    'production', 35,
    '62370000-0000-4000-8000-000000000007'::uuid,
    'rollout.outbox_promotion_35'
  );
  v_outcome := public.record_leghevo_authoritative_operational_window_v1(
    'production', 'leghevo-production-observer', 2, v_token, 2,
    v_now - interval '20 minutes', v_now - interval '15 minutes',
    1000, 2, 0, 235,
    '62370000-0000-4000-8000-000000000008'::uuid,
    jsonb_build_object('seedStage', 35)
  );
  v_outcome := public.promote_leghevo_application_rollout_v3(
    'production', 60,
    '62370000-0000-4000-8000-000000000009'::uuid,
    'rollout.outbox_promotion_60'
  );
  v_outcome := public.record_leghevo_authoritative_operational_window_v1(
    'production', 'leghevo-production-observer', 2, v_token, 3,
    v_now - interval '15 minutes', v_now - interval '10 minutes',
    1000, 1, 0, 230,
    '62370000-0000-4000-8000-000000000010'::uuid,
    jsonb_build_object('seedStage', 60)
  );
  v_outcome := public.promote_leghevo_application_rollout_v3(
    'production', 85,
    '62370000-0000-4000-8000-000000000011'::uuid,
    'rollout.outbox_promotion_85'
  );
  v_outcome := public.record_leghevo_authoritative_operational_window_v1(
    'production', 'leghevo-production-observer', 2, v_token, 4,
    v_now - interval '10 minutes', v_now - interval '5 minutes',
    1000, 1, 0, 225,
    '62370000-0000-4000-8000-000000000012'::uuid,
    jsonb_build_object('seedStage', 85)
  );
  v_outcome := public.promote_leghevo_application_rollout_v3(
    'production', 100,
    '62370000-0000-4000-8000-000000000013'::uuid,
    'rollout.outbox_completed'
  );
  v_outcome := public.record_leghevo_authoritative_operational_window_v1(
    'production', 'leghevo-production-observer', 2, v_token, 5,
    v_now - interval '5 minutes', v_now,
    1000, 1, 0, 220,
    '62370000-0000-4000-8000-000000000014'::uuid,
    jsonb_build_object('seedStage', 100, 'postCompletion', true)
  );
end;
$seed_release$;

-- Esercizio completo di claim e consegna per entrambe le destinazioni.
do $seed_delivery$
declare
  v_destination text;
  v_token uuid;
  v_claim jsonb;
  v_item jsonb;
  v_outcome jsonb;
  v_response_fingerprint text;
begin
  foreach v_destination in array array['operations_center','notification_dispatch'] loop
    v_token := gen_random_uuid();
    loop
      v_claim := public.claim_leghevo_operational_outbox_v1(
        'production', v_destination, 'leghevo-outbox-seed-worker', 1,
        v_token, 200, 120
      );
      exit when coalesce((v_claim ->> 'claimedCount')::integer, 0) = 0;
      for v_item in select value from pg_catalog.jsonb_array_elements(v_claim -> 'items') loop
        v_response_fingerprint :=
          pg_catalog.md5(v_destination || ':' || (v_item ->> 'messageId')) ||
          pg_catalog.md5('response:' || v_destination || ':' || (v_item ->> 'messageId'));
        v_outcome := public.complete_leghevo_operational_outbox_delivery_v1(
          (v_item ->> 'messageId')::bigint,
          v_destination,
          (v_item ->> 'deliveryGeneration')::bigint,
          'leghevo-outbox-seed-worker',
          1,
          v_token,
          'delivered',
          null,
          v_response_fingerprint,
          gen_random_uuid(),
          jsonb_build_object('seedDelivery', true, 'sourceMigration', 141)
        );
      end loop;
    end loop;
  end loop;
end;
$seed_delivery$;

create or replace function public.get_leghevo_operational_outbox_deployment_integrity_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_model jsonb;
  v_release jsonb;
  v_rollout jsonb;
  v_telemetry jsonb;
  v_enqueue_def text := coalesce(pg_catalog.pg_get_functiondef(
    to_regprocedure('public.enqueue_leghevo_operational_outbox_message_v1(text,text,bigint,uuid,text,text,jsonb,text,timestamptz)')), '');
  v_claim_def text := coalesce(pg_catalog.pg_get_functiondef(
    to_regprocedure('public.claim_leghevo_operational_outbox_v1(text,text,text,bigint,uuid,integer,integer)')), '');
  v_complete_def text := coalesce(pg_catalog.pg_get_functiondef(
    to_regprocedure('public.complete_leghevo_operational_outbox_delivery_v1(bigint,text,bigint,text,bigint,uuid,text,text,text,uuid,jsonb)')), '');
  v_message_mismatch_count bigint;
  v_attempt_mismatch_count bigint;
  v_dead_letter_mismatch_count bigint;
  v_sequence_gap_count bigint;
  v_message_count bigint;
  v_head_count bigint;
  v_delivered_count bigint;
begin
  v_model := public.get_leghevo_operational_outbox_model_v1('production');
  v_release := public.get_leghevo_application_release_model_v1('production');
  v_rollout := public.get_leghevo_application_rollout_model_v1('production');
  v_telemetry := public.get_leghevo_operational_telemetry_model_v1('production');

  select count(*) into v_message_mismatch_count
  from public.leghevo_operational_outbox_messages message
  where message.message_fingerprint is distinct from
    public.compute_leghevo_operational_outbox_message_fingerprint_v1(
      message.environment_key, message.source_table, message.source_event_id,
      message.source_request_id, message.event_type, message.aggregate_key,
      message.stream_sequence, message.priority, message.payload,
      message.payload_contract_version
    );

  select count(*) into v_attempt_mismatch_count
  from public.leghevo_operational_outbox_delivery_attempts attempt
  where attempt.attempt_fingerprint is distinct from
    public.compute_leghevo_operational_outbox_attempt_fingerprint_v1(
      attempt.message_id, attempt.destination_key, attempt.attempt_no,
      attempt.delivery_generation, attempt.worker_key,
      attempt.worker_generation, attempt.outcome, attempt.error_code,
      attempt.response_fingerprint, attempt.details
    );

  select count(*) into v_dead_letter_mismatch_count
  from public.leghevo_operational_outbox_dead_letters dead
  where dead.dead_letter_fingerprint is distinct from
    public.compute_leghevo_operational_dead_letter_fingerprint_v1(
      dead.message_id, dead.destination_key, dead.attempt_id,
      dead.reason_code, dead.message_fingerprint
    );

  select count(*) into v_sequence_gap_count
  from (
    select message.stream_sequence,
      lag(message.stream_sequence) over (
        partition by message.environment_key order by message.stream_sequence
      ) as previous_sequence
    from public.leghevo_operational_outbox_messages message
  ) sequence_check
  where (previous_sequence is null and stream_sequence <> 1)
     or (previous_sequence is not null and stream_sequence <> previous_sequence + 1);

  select count(*) into v_message_count
  from public.leghevo_operational_outbox_messages message
  where message.environment_key = 'production';
  select count(*) into v_head_count
  from public.leghevo_operational_outbox_delivery_heads head
  join public.leghevo_operational_outbox_messages message on message.id = head.message_id
  where message.environment_key = 'production';
  select count(*) into v_delivered_count
  from public.leghevo_operational_outbox_delivery_heads head
  join public.leghevo_operational_outbox_messages message on message.id = head.message_id
  where message.environment_key = 'production' and head.state = 'delivered';

  return jsonb_build_object(
    'predecessor_ready',
      to_regprocedure('public.get_leghevo_authoritative_telemetry_deployment_integrity_v1()') is not null
      and exists (select 1 from public.leghevo_application_release_certificates c
        where c.application_version = '0.62.36'),
    'message_table_ready',
      to_regclass('public.leghevo_operational_outbox_messages') is not null,
    'delivery_head_table_ready',
      to_regclass('public.leghevo_operational_outbox_delivery_heads') is not null,
    'attempt_table_ready',
      to_regclass('public.leghevo_operational_outbox_delivery_attempts') is not null,
    'dead_letter_table_ready',
      to_regclass('public.leghevo_operational_outbox_dead_letters') is not null,
    'columns_ready',
      (select count(*) from information_schema.columns c
       where c.table_schema = 'public' and c.table_name = 'leghevo_operational_outbox_messages'
         and c.column_name in ('source_table','source_event_id','stream_sequence','message_fingerprint','payload')) = 5
      and (select count(*) from information_schema.columns c
       where c.table_schema = 'public' and c.table_name = 'leghevo_operational_outbox_delivery_heads'
         and c.column_name in ('state','generation','worker_generation','lease_token_hash','attempt_count')) = 5
      and (select count(*) from information_schema.columns c
       where c.table_schema = 'public' and c.table_name = 'leghevo_operational_outbox_delivery_attempts'
         and c.column_name in ('attempt_no','delivery_generation','outcome','attempt_fingerprint')) = 4,
    'constraints_ready',
      exists (select 1 from pg_catalog.pg_constraint c
        where c.conrelid = 'public.leghevo_operational_outbox_messages'::regclass
          and c.conname = 'leghevo_outbox_message_source_unique')
      and exists (select 1 from pg_catalog.pg_constraint c
        where c.conrelid = 'public.leghevo_operational_outbox_messages'::regclass
          and c.conname = 'leghevo_outbox_message_sequence_unique')
      and exists (select 1 from pg_catalog.pg_constraint c
        where c.conrelid = 'public.leghevo_operational_outbox_delivery_attempts'::regclass
          and c.conname = 'leghevo_outbox_attempt_sequence_unique')
      and exists (select 1 from pg_catalog.pg_constraint c
        where c.conrelid = 'public.leghevo_operational_outbox_delivery_attempts'::regclass
          and c.conname = 'leghevo_outbox_attempt_identity_unique')
      and exists (select 1 from pg_catalog.pg_constraint c
        where c.conrelid = 'public.leghevo_operational_outbox_dead_letters'::regclass
          and c.conname = 'leghevo_outbox_dead_letter_message_unique')
      and exists (select 1 from pg_catalog.pg_constraint c
        where c.conrelid = 'public.leghevo_operational_outbox_delivery_heads'::regclass
          and c.conname = 'leghevo_outbox_delivery_last_attempt_fk'),
    'indexes_ready',
      to_regclass('public.leghevo_outbox_messages_environment_sequence_idx') is not null
      and to_regclass('public.leghevo_outbox_delivery_claim_idx') is not null
      and to_regclass('public.leghevo_outbox_attempts_message_destination_idx') is not null
      and to_regclass('public.leghevo_outbox_dead_letters_created_idx') is not null,
    'rls_ready',
      coalesce((select c.relrowsecurity from pg_catalog.pg_class c
        where c.oid = 'public.leghevo_operational_outbox_messages'::regclass), false)
      and coalesce((select c.relrowsecurity from pg_catalog.pg_class c
        where c.oid = 'public.leghevo_operational_outbox_delivery_heads'::regclass), false)
      and coalesce((select c.relrowsecurity from pg_catalog.pg_class c
        where c.oid = 'public.leghevo_operational_outbox_delivery_attempts'::regclass), false)
      and coalesce((select c.relrowsecurity from pg_catalog.pg_class c
        where c.oid = 'public.leghevo_operational_outbox_dead_letters'::regclass), false),
    'direct_write_blocked',
      not has_table_privilege('authenticated','public.leghevo_operational_outbox_messages','SELECT')
      and not has_table_privilege('authenticated','public.leghevo_operational_outbox_delivery_heads','SELECT')
      and not has_table_privilege('authenticated','public.leghevo_operational_outbox_dead_letters','SELECT')
      and not has_table_privilege('service_role','public.leghevo_operational_outbox_messages','INSERT')
      and not has_table_privilege('service_role','public.leghevo_operational_outbox_delivery_heads','UPDATE')
      and not has_table_privilege('service_role','public.leghevo_operational_outbox_delivery_attempts','INSERT')
      and has_table_privilege('service_role','public.leghevo_operational_outbox_dead_letters','SELECT'),
    'immutable_records_ready',
      exists (select 1 from pg_catalog.pg_trigger t
        where t.tgrelid = 'public.leghevo_operational_outbox_messages'::regclass
          and t.tgname = 'leghevo_outbox_messages_guard' and t.tgenabled = 'A' and not t.tgisinternal)
      and exists (select 1 from pg_catalog.pg_trigger t
        where t.tgrelid = 'public.leghevo_operational_outbox_delivery_attempts'::regclass
          and t.tgname = 'leghevo_outbox_attempts_guard' and t.tgenabled = 'A' and not t.tgisinternal)
      and exists (select 1 from pg_catalog.pg_trigger t
        where t.tgrelid = 'public.leghevo_operational_outbox_dead_letters'::regclass
          and t.tgname = 'leghevo_outbox_dead_letters_guard' and t.tgenabled = 'A' and not t.tgisinternal),
    'delivery_head_guard_ready',
      exists (select 1 from pg_catalog.pg_trigger t
        where t.tgrelid = 'public.leghevo_operational_outbox_delivery_heads'::regclass
          and t.tgname = 'leghevo_outbox_delivery_heads_guard' and t.tgenabled = 'A' and not t.tgisinternal),
    'source_capture_triggers_ready',
      coalesce((v_model ->> 'captureReady')::boolean, false),
    'message_fingerprint_ready',
      v_message_mismatch_count = 0
      and v_attempt_mismatch_count = 0
      and v_dead_letter_mismatch_count = 0
      and v_sequence_gap_count = 0
      and coalesce((v_model ->> 'deliveryConsistencyMismatchCount')::bigint, -1) = 0,
    'enqueue_dedup_ready',
      to_regprocedure('public.enqueue_leghevo_operational_outbox_message_v1(text,text,bigint,uuid,text,text,jsonb,text,timestamptz)') is not null
      and position('pg_advisory_xact_lock' in v_enqueue_def) > 0
      and position('source_event_id = p_source_event_id' in v_enqueue_def) > 0
      and not has_function_privilege('service_role',
        'public.enqueue_leghevo_operational_outbox_message_v1(text,text,bigint,uuid,text,text,jsonb,text,timestamptz)','EXECUTE'),
    'claim_fencing_ready',
      to_regprocedure('public.claim_leghevo_operational_outbox_v1(text,text,text,bigint,uuid,integer,integer)') is not null
      and position('skip locked' in lower(v_claim_def)) > 0
      and position('worker_generation' in v_claim_def) > 0
      and position('lease_token_hash' in v_claim_def) > 0
      and has_function_privilege('service_role',
        'public.claim_leghevo_operational_outbox_v1(text,text,text,bigint,uuid,integer,integer)','EXECUTE'),
    'completion_and_dlq_ready',
      to_regprocedure('public.complete_leghevo_operational_outbox_delivery_v1(bigint,text,bigint,text,bigint,uuid,text,text,text,uuid,jsonb)') is not null
      and position('Lease o fencing consegna non più valido' in v_complete_def) > 0
      and position('dead_letter' in v_complete_def) > 0
      and position('v_attempt_no >= 5' in v_complete_def) > 0
      and has_function_privilege('service_role',
        'public.complete_leghevo_operational_outbox_delivery_v1(bigint,text,bigint,text,bigint,uuid,text,text,text,uuid,jsonb)','EXECUTE'),
    'client_and_endpoint_chain_ready',
      to_regprocedure('public.get_leghevo_client_rollout_eligibility_v3(text,text,uuid)') is not null
      and has_function_privilege('anon','public.get_leghevo_client_rollout_eligibility_v3(text,text,uuid)','EXECUTE')
      and has_function_privilege('authenticated','public.get_leghevo_client_rollout_eligibility_v3(text,text,uuid)','EXECUTE')
      and to_regprocedure('public.get_league_provider_sync_health_v36(uuid)') is not null
      and to_regprocedure('public.get_league_season_state_v15(uuid)') is not null
      and to_regprocedure('public.get_league_management_state_v25(uuid)') is not null
      and to_regprocedure('public.promote_leghevo_application_rollout_v3(text,integer,uuid,text)') is not null
      and has_function_privilege('service_role',
        'public.promote_leghevo_application_rollout_v3(text,integer,uuid,text)','EXECUTE')
      and not has_function_privilege('service_role',
        'public.promote_leghevo_application_rollout_v2(text,integer,uuid,text)','EXECUTE')
      and has_function_privilege('authenticated','public.get_league_provider_sync_health_v36(uuid)','EXECUTE'),
    'seed_release_ready',
      coalesce((v_release ->> 'protected')::boolean, false)
      and v_release ->> 'activeVersion' = '0.62.37'
      and coalesce((v_rollout ->> 'protected')::boolean, false)
      and v_rollout ->> 'status' = 'completed'
      and coalesce((v_rollout ->> 'exposurePercentage')::integer, 0) = 100
      and coalesce((v_telemetry ->> 'protected')::boolean, false)
      and coalesce((v_telemetry ->> 'healthy')::boolean, false)
      and coalesce((v_telemetry ->> 'sourceGeneration')::bigint, 0) = 2
      and v_telemetry ->> 'latestReleaseVersion' = '0.62.37'
      and exists (select 1 from public.leghevo_application_release_certificates c
        where c.application_version = '0.62.37'
          and c.bundle_fingerprint = 'c72b1e6b37afe352df30bf33db2d900d580420df042a9f5052754dd75af13630'),
    'seed_outbox_ready',
      coalesce((v_model ->> 'protected')::boolean, false)
      and coalesce((v_model ->> 'healthy')::boolean, false)
      and v_model ->> 'status' = 'active'
      and v_message_count > 0
      and v_head_count = v_message_count * 2
      and v_delivered_count = v_head_count
      and coalesce((v_model ->> 'pendingCount')::bigint, -1) = 0
      and coalesce((v_model ->> 'leasedCount')::bigint, -1) = 0
      and coalesce((v_model ->> 'retryCount')::bigint, -1) = 0
      and coalesce((v_model ->> 'deadLetterCount')::bigint, -1) = 0
      and coalesce((v_model ->> 'lastSequence')::bigint, 0) = v_message_count
      and (
        not exists (select 1 from pg_catalog.pg_publication p where p.pubname = 'supabase_realtime')
        or exists (select 1 from pg_catalog.pg_publication_tables pt
          where pt.pubname = 'supabase_realtime'
            and pt.schemaname = 'public'
            and pt.tablename = 'leghevo_operational_outbox_dead_letters')
      )
  );
end;
$function$;

revoke all on function public.get_leghevo_operational_outbox_deployment_integrity_v1()
from public, anon, authenticated;
grant execute on function public.get_leghevo_operational_outbox_deployment_integrity_v1()
to service_role;

do $validation$
declare
  v_integrity jsonb;
  v_false text[];
begin
  v_integrity := public.get_leghevo_operational_outbox_deployment_integrity_v1();
  select array_agg(item.key order by item.key) into v_false
  from pg_catalog.jsonb_each(v_integrity) item
  where pg_catalog.jsonb_typeof(item.value) is distinct from 'boolean'
     or item.value is distinct from 'true'::jsonb;

  if (select count(*) from pg_catalog.jsonb_each(v_integrity)) <> 20
    or cardinality(v_false) > 0 then
    raise exception 'Validazione v0.62.37 non superata: %. Dettaglio: %',
      coalesce(array_to_string(v_false, ', '), 'numero controlli diverso da 20'),
      v_integrity;
  end if;
end;
$validation$;

commit;

select
  (public.get_leghevo_operational_outbox_deployment_integrity_v1()->>'predecessor_ready')::boolean as predecessor_ready,
  (public.get_leghevo_operational_outbox_deployment_integrity_v1()->>'message_table_ready')::boolean as message_table_ready,
  (public.get_leghevo_operational_outbox_deployment_integrity_v1()->>'delivery_head_table_ready')::boolean as delivery_head_table_ready,
  (public.get_leghevo_operational_outbox_deployment_integrity_v1()->>'attempt_table_ready')::boolean as attempt_table_ready,
  (public.get_leghevo_operational_outbox_deployment_integrity_v1()->>'dead_letter_table_ready')::boolean as dead_letter_table_ready,
  (public.get_leghevo_operational_outbox_deployment_integrity_v1()->>'columns_ready')::boolean as columns_ready,
  (public.get_leghevo_operational_outbox_deployment_integrity_v1()->>'constraints_ready')::boolean as constraints_ready,
  (public.get_leghevo_operational_outbox_deployment_integrity_v1()->>'indexes_ready')::boolean as indexes_ready,
  (public.get_leghevo_operational_outbox_deployment_integrity_v1()->>'rls_ready')::boolean as rls_ready,
  (public.get_leghevo_operational_outbox_deployment_integrity_v1()->>'direct_write_blocked')::boolean as direct_write_blocked,
  (public.get_leghevo_operational_outbox_deployment_integrity_v1()->>'immutable_records_ready')::boolean as immutable_records_ready,
  (public.get_leghevo_operational_outbox_deployment_integrity_v1()->>'delivery_head_guard_ready')::boolean as delivery_head_guard_ready,
  (public.get_leghevo_operational_outbox_deployment_integrity_v1()->>'source_capture_triggers_ready')::boolean as source_capture_triggers_ready,
  (public.get_leghevo_operational_outbox_deployment_integrity_v1()->>'message_fingerprint_ready')::boolean as message_fingerprint_ready,
  (public.get_leghevo_operational_outbox_deployment_integrity_v1()->>'enqueue_dedup_ready')::boolean as enqueue_dedup_ready,
  (public.get_leghevo_operational_outbox_deployment_integrity_v1()->>'claim_fencing_ready')::boolean as claim_fencing_ready,
  (public.get_leghevo_operational_outbox_deployment_integrity_v1()->>'completion_and_dlq_ready')::boolean as completion_and_dlq_ready,
  (public.get_leghevo_operational_outbox_deployment_integrity_v1()->>'client_and_endpoint_chain_ready')::boolean as client_and_endpoint_chain_ready,
  (public.get_leghevo_operational_outbox_deployment_integrity_v1()->>'seed_release_ready')::boolean as seed_release_ready,
  (public.get_leghevo_operational_outbox_deployment_integrity_v1()->>'seed_outbox_ready')::boolean as seed_outbox_ready;
