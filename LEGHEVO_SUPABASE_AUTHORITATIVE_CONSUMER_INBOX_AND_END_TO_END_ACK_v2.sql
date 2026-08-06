-- LEGHEVO v0.62.38
-- Inbox autorevole del consumatore, ricevute end-to-end e replay controllato
-- Dipendenza: v0.62.37 validata con 20/20 controlli true.
-- Correzione pre-validazione v2: la diagnostica finale riconosce esattamente
-- i quattro controlli legacy v0.62.37 resi falsi dalla sostituzione protetta
-- di claim v1, completion v1, rollout v3 e seed release v0.62.37.

begin;

do $preflight$
declare
  v_integrity jsonb;
  v_false text[];
begin
  if to_regprocedure('public.get_leghevo_operational_consumer_delivery_deployment_integrity_v1()') is not null
    and exists (
      select 1 from public.leghevo_application_release_certificates c
      where c.application_version = '0.62.38'
    ) then
    return;
  end if;

  if to_regprocedure('public.get_leghevo_operational_outbox_deployment_integrity_v1()') is null then
    raise exception 'Preflight v0.62.38 non superato: diagnostica v0.62.37 assente.';
  end if;

  v_integrity := public.get_leghevo_operational_outbox_deployment_integrity_v1();
  select array_agg(item.key order by item.key) into v_false
  from pg_catalog.jsonb_each(v_integrity) item
  where pg_catalog.jsonb_typeof(item.value) is distinct from 'boolean'
     or item.value is distinct from 'true'::jsonb;

  if (select count(*) from pg_catalog.jsonb_each(v_integrity)) <> 20
    or cardinality(v_false) > 0 then
    raise exception 'Preflight v0.62.38 non superato: %. Dettaglio: %',
      coalesce(array_to_string(v_false, ', '), 'numero controlli diverso da 20'),
      v_integrity;
  end if;
end;
$preflight$;

create or replace function public.compute_leghevo_operational_consumer_certificate_fingerprint_v1(
  p_environment_key text,
  p_destination_key text,
  p_consumer_key text,
  p_consumer_generation bigint,
  p_fencing_token_hash text,
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
    coalesce(lower(trim(p_destination_key)), '') || '|' ||
    coalesce(lower(trim(p_consumer_key)), '') || '|' ||
    coalesce(p_consumer_generation, 0)::text || '|' ||
    coalesce(lower(trim(p_fencing_token_hash)), '') || '|' ||
    coalesce(p_contract_version, 0)::text
  );
$function$;

revoke all on function public.compute_leghevo_operational_consumer_certificate_fingerprint_v1(
  text,text,text,bigint,text,integer
) from public, anon, authenticated;
grant execute on function public.compute_leghevo_operational_consumer_certificate_fingerprint_v1(
  text,text,text,bigint,text,integer
) to service_role;

create or replace function public.compute_leghevo_operational_consumer_receipt_fingerprint_v1(
  p_environment_key text,
  p_message_id bigint,
  p_destination_key text,
  p_stream_sequence bigint,
  p_message_fingerprint text,
  p_consumer_id bigint,
  p_consumer_generation bigint,
  p_consumer_token_hash text,
  p_application_key text,
  p_application_fingerprint text,
  p_receipt_signature text,
  p_adoption_mode text,
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
    coalesce(p_message_id, 0)::text || '|' ||
    coalesce(lower(trim(p_destination_key)), '') || '|' ||
    coalesce(p_stream_sequence, 0)::text || '|' ||
    coalesce(lower(trim(p_message_fingerprint)), '') || '|' ||
    coalesce(p_consumer_id, 0)::text || '|' ||
    coalesce(p_consumer_generation, 0)::text || '|' ||
    coalesce(lower(trim(p_consumer_token_hash)), '') || '|' ||
    coalesce(trim(p_application_key), '') || '|' ||
    coalesce(lower(trim(p_application_fingerprint)), '') || '|' ||
    coalesce(lower(trim(p_receipt_signature)), '') || '|' ||
    coalesce(lower(trim(p_adoption_mode)), '') || '|' ||
    coalesce(p_contract_version, 0)::text
  );
$function$;

revoke all on function public.compute_leghevo_operational_consumer_receipt_fingerprint_v1(
  text,bigint,text,bigint,text,bigint,bigint,text,text,text,text,text,integer
) from public, anon, authenticated;
grant execute on function public.compute_leghevo_operational_consumer_receipt_fingerprint_v1(
  text,bigint,text,bigint,text,bigint,bigint,text,text,text,text,text,integer
) to service_role;

create or replace function public.compute_leghevo_operational_consumer_event_fingerprint_v1(
  p_environment_key text,
  p_destination_key text,
  p_event_type text,
  p_generation bigint,
  p_message_id bigint,
  p_stream_sequence bigint,
  p_consumer_id bigint,
  p_receipt_id bigint,
  p_reason_code text,
  p_details jsonb
)
returns text
language sql
immutable
security definer
set search_path = ''
as $function$
  select pg_catalog.md5(
    coalesce(lower(trim(p_environment_key)), '') || '|' ||
    coalesce(lower(trim(p_destination_key)), '') || '|' ||
    coalesce(lower(trim(p_event_type)), '') || '|' ||
    coalesce(p_generation, 0)::text || '|' ||
    coalesce(p_message_id, 0)::text || '|' ||
    coalesce(p_stream_sequence, 0)::text || '|' ||
    coalesce(p_consumer_id, 0)::text || '|' ||
    coalesce(p_receipt_id, 0)::text || '|' ||
    coalesce(lower(trim(p_reason_code)), '') || '|' ||
    coalesce(p_details, '{}'::jsonb)::text
  );
$function$;

revoke all on function public.compute_leghevo_operational_consumer_event_fingerprint_v1(
  text,text,text,bigint,bigint,bigint,bigint,bigint,text,jsonb
) from public, anon, authenticated;
grant execute on function public.compute_leghevo_operational_consumer_event_fingerprint_v1(
  text,text,text,bigint,bigint,bigint,bigint,bigint,text,jsonb
) to service_role;

create table if not exists public.leghevo_operational_consumer_certificates (
  id bigint generated by default as identity primary key,
  environment_key text not null,
  destination_key text not null,
  consumer_key text not null,
  consumer_generation bigint not null,
  fencing_token_hash text not null,
  request_id uuid not null unique,
  contract_version integer not null default 1,
  certificate_fingerprint text not null unique,
  details jsonb not null default '{}'::jsonb,
  certified_at timestamptz not null default now(),
  created_by uuid null,
  constraint leghevo_consumer_certificate_environment_check
    check (environment_key in ('production','staging')),
  constraint leghevo_consumer_certificate_destination_check
    check (destination_key in ('operations_center','notification_dispatch')),
  constraint leghevo_consumer_certificate_key_check
    check (consumer_key ~ '^[a-z0-9][a-z0-9._-]{2,79}$'),
  constraint leghevo_consumer_certificate_generation_check
    check (consumer_generation >= 1),
  constraint leghevo_consumer_certificate_token_hash_check
    check (fencing_token_hash ~ '^[0-9a-f]{32}$'),
  constraint leghevo_consumer_certificate_contract_check
    check (contract_version >= 1),
  constraint leghevo_consumer_certificate_fingerprint_check
    check (certificate_fingerprint ~ '^[0-9a-f]{32}$'),
  constraint leghevo_consumer_certificate_details_check
    check (jsonb_typeof(details) = 'object'),
  constraint leghevo_consumer_certificate_generation_unique
    unique (environment_key, destination_key, consumer_generation)
);

create table if not exists public.leghevo_operational_consumer_heads (
  environment_key text not null,
  destination_key text not null,
  generation bigint not null default 1,
  consumer_id bigint not null references public.leghevo_operational_consumer_certificates(id) on delete restrict,
  consumer_generation bigint not null,
  state text not null default 'active',
  last_stream_sequence bigint not null default 0,
  last_message_id bigint null,
  last_receipt_id bigint null,
  affected_reason text null,
  last_request_id uuid not null,
  updated_at timestamptz not null default now(),
  primary key (environment_key, destination_key),
  constraint leghevo_consumer_head_environment_check
    check (environment_key in ('production','staging')),
  constraint leghevo_consumer_head_destination_check
    check (destination_key in ('operations_center','notification_dispatch')),
  constraint leghevo_consumer_head_generation_check
    check (generation >= 1 and consumer_generation >= 1),
  constraint leghevo_consumer_head_state_check
    check (state in ('active','affected')),
  constraint leghevo_consumer_head_sequence_check
    check (last_stream_sequence >= 0),
  constraint leghevo_consumer_head_shape_check
    check (
      (last_stream_sequence = 0 and last_message_id is null and last_receipt_id is null)
      or (last_stream_sequence >= 1 and last_message_id is not null and last_receipt_id is not null)
    ),
  constraint leghevo_consumer_head_affected_check
    check (
      (state = 'affected' and char_length(trim(affected_reason)) between 3 and 160)
      or (state = 'active' and affected_reason is null)
    )
);

create table if not exists public.leghevo_operational_consumer_receipts (
  id bigint generated by default as identity primary key,
  request_id uuid not null unique,
  environment_key text not null,
  message_id bigint not null,
  destination_key text not null,
  stream_sequence bigint not null,
  message_fingerprint text not null,
  consumer_id bigint not null references public.leghevo_operational_consumer_certificates(id) on delete restrict,
  consumer_generation bigint not null,
  consumer_token_hash text not null,
  application_key text not null,
  application_fingerprint text not null,
  receipt_signature text not null,
  receipt_fingerprint text not null unique,
  adoption_mode text not null default 'live',
  contract_version integer not null default 1,
  details jsonb not null default '{}'::jsonb,
  applied_at timestamptz not null default now(),
  recorded_by uuid null,
  constraint leghevo_consumer_receipt_delivery_fk
    foreign key (message_id, destination_key)
    references public.leghevo_operational_outbox_delivery_heads(message_id, destination_key)
    on delete restrict,
  constraint leghevo_consumer_receipt_environment_check
    check (environment_key in ('production','staging')),
  constraint leghevo_consumer_receipt_destination_check
    check (destination_key in ('operations_center','notification_dispatch')),
  constraint leghevo_consumer_receipt_sequence_check
    check (stream_sequence >= 1 and consumer_generation >= 1),
  constraint leghevo_consumer_receipt_message_fingerprint_check
    check (message_fingerprint ~ '^[0-9a-f]{32}$'),
  constraint leghevo_consumer_receipt_token_hash_check
    check (consumer_token_hash ~ '^[0-9a-f]{32}$'),
  constraint leghevo_consumer_receipt_application_key_check
    check (char_length(trim(application_key)) between 3 and 160),
  constraint leghevo_consumer_receipt_application_fingerprint_check
    check (application_fingerprint ~ '^[0-9a-f]{64}$'),
  constraint leghevo_consumer_receipt_signature_check
    check (receipt_signature ~ '^[0-9a-f]{64}$'),
  constraint leghevo_consumer_receipt_fingerprint_check
    check (receipt_fingerprint ~ '^[0-9a-f]{32}$'),
  constraint leghevo_consumer_receipt_adoption_check
    check (adoption_mode in ('live','legacy_baseline')),
  constraint leghevo_consumer_receipt_contract_check
    check (contract_version >= 1),
  constraint leghevo_consumer_receipt_details_check
    check (jsonb_typeof(details) = 'object'),
  constraint leghevo_consumer_receipt_message_unique
    unique (message_id, destination_key),
  constraint leghevo_consumer_receipt_sequence_unique
    unique (environment_key, destination_key, stream_sequence),
  constraint leghevo_consumer_receipt_identity_unique
    unique (id, message_id, destination_key)
);

create table if not exists public.leghevo_operational_consumer_events (
  id bigint generated by default as identity primary key,
  environment_key text not null,
  destination_key text not null,
  request_id uuid not null,
  event_type text not null,
  generation bigint not null,
  message_id bigint null,
  stream_sequence bigint null,
  consumer_id bigint null references public.leghevo_operational_consumer_certificates(id) on delete restrict,
  receipt_id bigint null references public.leghevo_operational_consumer_receipts(id) on delete restrict,
  reason_code text not null,
  event_fingerprint text not null unique,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  created_by uuid null,
  constraint leghevo_consumer_event_environment_check
    check (environment_key in ('production','staging')),
  constraint leghevo_consumer_event_destination_check
    check (destination_key in ('operations_center','notification_dispatch')),
  constraint leghevo_consumer_event_type_check
    check (event_type in ('certified','adopted','applied','affected','revalidated','replay_requested')),
  constraint leghevo_consumer_event_generation_check
    check (generation >= 1),
  constraint leghevo_consumer_event_message_check
    check (message_id is null or message_id >= 1),
  constraint leghevo_consumer_event_sequence_check
    check (stream_sequence is null or stream_sequence >= 1),
  constraint leghevo_consumer_event_reason_check
    check (char_length(trim(reason_code)) between 3 and 160),
  constraint leghevo_consumer_event_fingerprint_check
    check (event_fingerprint ~ '^[0-9a-f]{32}$'),
  constraint leghevo_consumer_event_details_check
    check (jsonb_typeof(details) = 'object'),
  constraint leghevo_consumer_event_request_unique
    unique (environment_key, destination_key, request_id)
);

create index if not exists leghevo_consumer_certificates_current_idx
on public.leghevo_operational_consumer_certificates(
  environment_key, destination_key, consumer_generation desc, id desc
);
create index if not exists leghevo_consumer_receipts_sequence_idx
on public.leghevo_operational_consumer_receipts(
  environment_key, destination_key, stream_sequence, id
);
create index if not exists leghevo_consumer_receipts_applied_idx
on public.leghevo_operational_consumer_receipts(applied_at desc, id desc);
create index if not exists leghevo_consumer_events_created_idx
on public.leghevo_operational_consumer_events(
  environment_key, destination_key, created_at desc, id desc
);
create index if not exists leghevo_consumer_events_type_idx
on public.leghevo_operational_consumer_events(event_type, created_at desc, id desc);

alter table public.leghevo_operational_consumer_heads
  drop constraint if exists leghevo_consumer_head_last_receipt_fk;
alter table public.leghevo_operational_consumer_heads
  add constraint leghevo_consumer_head_last_receipt_fk
  foreign key (last_receipt_id, last_message_id, destination_key)
  references public.leghevo_operational_consumer_receipts(id, message_id, destination_key)
  on delete restrict;

alter table public.leghevo_operational_consumer_certificates enable row level security;
alter table public.leghevo_operational_consumer_heads enable row level security;
alter table public.leghevo_operational_consumer_receipts enable row level security;
alter table public.leghevo_operational_consumer_events enable row level security;
alter table public.leghevo_operational_consumer_events replica identity full;

revoke all on table public.leghevo_operational_consumer_certificates
from public, anon, authenticated, service_role;
revoke all on table public.leghevo_operational_consumer_heads
from public, anon, authenticated, service_role;
revoke all on table public.leghevo_operational_consumer_receipts
from public, anon, authenticated, service_role;
revoke all on table public.leghevo_operational_consumer_events
from public, anon, authenticated, service_role;

create or replace function public.guard_leghevo_operational_consumer_immutable_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if current_setting('leghevo.operational_consumer_context', true) is distinct from 'allowed' then
    raise exception 'Registro consumatore operativo immutabile.';
  end if;
  if tg_op = 'DELETE' then
    raise exception 'Registro consumatore operativo non eliminabile.';
  end if;
  return new;
end;
$function$;

revoke all on function public.guard_leghevo_operational_consumer_immutable_v1()
from public, anon, authenticated, service_role;

create or replace function public.guard_leghevo_operational_consumer_head_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if current_setting('leghevo.operational_consumer_context', true) is distinct from 'allowed' then
    raise exception 'Testa consumatore operativo modificabile soltanto dalle RPC certificate.';
  end if;
  if tg_op = 'DELETE' then
    raise exception 'Testa consumatore operativo non eliminabile.';
  end if;
  if new.environment_key <> old.environment_key
    or new.destination_key <> old.destination_key
    or new.generation <> old.generation + 1
    or new.consumer_generation < old.consumer_generation
    or new.last_stream_sequence < old.last_stream_sequence
    or new.last_stream_sequence > old.last_stream_sequence + 1 then
    raise exception 'Transizione testa consumatore non monotona.';
  end if;
  if new.last_stream_sequence = old.last_stream_sequence + 1
    and (new.consumer_id <> old.consumer_id
      or new.consumer_generation <> old.consumer_generation) then
    raise exception 'Ack applicativo non coerente con il consumatore corrente.';
  end if;
  return new;
end;
$function$;

revoke all on function public.guard_leghevo_operational_consumer_head_v1()
from public, anon, authenticated, service_role;

drop trigger if exists leghevo_consumer_certificates_guard
on public.leghevo_operational_consumer_certificates;
create trigger leghevo_consumer_certificates_guard
before update or delete on public.leghevo_operational_consumer_certificates
for each row execute function public.guard_leghevo_operational_consumer_immutable_v1();
alter table public.leghevo_operational_consumer_certificates
  enable always trigger leghevo_consumer_certificates_guard;

drop trigger if exists leghevo_consumer_receipts_guard
on public.leghevo_operational_consumer_receipts;
create trigger leghevo_consumer_receipts_guard
before update or delete on public.leghevo_operational_consumer_receipts
for each row execute function public.guard_leghevo_operational_consumer_immutable_v1();
alter table public.leghevo_operational_consumer_receipts
  enable always trigger leghevo_consumer_receipts_guard;

drop trigger if exists leghevo_consumer_events_guard
on public.leghevo_operational_consumer_events;
create trigger leghevo_consumer_events_guard
before update or delete on public.leghevo_operational_consumer_events
for each row execute function public.guard_leghevo_operational_consumer_immutable_v1();
alter table public.leghevo_operational_consumer_events
  enable always trigger leghevo_consumer_events_guard;

drop trigger if exists leghevo_consumer_heads_guard
on public.leghevo_operational_consumer_heads;
create trigger leghevo_consumer_heads_guard
before update or delete on public.leghevo_operational_consumer_heads
for each row execute function public.guard_leghevo_operational_consumer_head_v1();
alter table public.leghevo_operational_consumer_heads
  enable always trigger leghevo_consumer_heads_guard;

create or replace function public.certify_leghevo_operational_consumer_v1(
  p_environment_key text,
  p_destination_key text,
  p_consumer_key text,
  p_consumer_generation bigint,
  p_fencing_token uuid,
  p_request_id uuid,
  p_details jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_environment text := lower(trim(coalesce(p_environment_key, '')));
  v_destination text := lower(trim(coalesce(p_destination_key, '')));
  v_consumer_key text := lower(trim(coalesce(p_consumer_key, '')));
  v_details jsonb := coalesce(p_details, '{}'::jsonb);
  v_token_hash text;
  v_certificate_fingerprint text;
  v_certificate public.leghevo_operational_consumer_certificates%rowtype;
  v_existing public.leghevo_operational_consumer_certificates%rowtype;
  v_head public.leghevo_operational_consumer_heads%rowtype;
  v_head_generation bigint;
  v_event_fingerprint text;
begin
  if v_environment not in ('production','staging')
    or v_destination not in ('operations_center','notification_dispatch')
    or v_consumer_key !~ '^[a-z0-9][a-z0-9._-]{2,79}$'
    or coalesce(p_consumer_generation, 0) < 1
    or p_fencing_token is null
    or p_request_id is null
    or jsonb_typeof(v_details) is distinct from 'object' then
    raise exception 'Certificazione consumatore operativo non valida.';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'leghevo:operational-consumer:' || v_environment || ':' || v_destination, 0));

  select certificate.* into v_existing
  from public.leghevo_operational_consumer_certificates certificate
  where certificate.request_id = p_request_id;
  if found then
    if v_existing.environment_key <> v_environment
      or v_existing.destination_key <> v_destination
      or v_existing.consumer_key <> v_consumer_key
      or v_existing.consumer_generation <> p_consumer_generation then
      raise exception 'request_id già utilizzato per un consumatore diverso.';
    end if;
    return jsonb_build_object(
      'consumerId', v_existing.id,
      'consumerGeneration', v_existing.consumer_generation,
      'certificateFingerprint', v_existing.certificate_fingerprint,
      'reused', true
    );
  end if;

  select head.* into v_head
  from public.leghevo_operational_consumer_heads head
  where head.environment_key = v_environment
    and head.destination_key = v_destination
  for update;
  if found and p_consumer_generation <= v_head.consumer_generation then
    raise exception 'Generazione consumatore non monotona.';
  end if;

  v_token_hash := pg_catalog.md5(p_fencing_token::text);
  v_certificate_fingerprint :=
    public.compute_leghevo_operational_consumer_certificate_fingerprint_v1(
      v_environment, v_destination, v_consumer_key,
      p_consumer_generation, v_token_hash, 1);

  perform set_config('leghevo.operational_consumer_context', 'allowed', true);
  insert into public.leghevo_operational_consumer_certificates(
    environment_key, destination_key, consumer_key, consumer_generation,
    fencing_token_hash, request_id, contract_version,
    certificate_fingerprint, details, certified_at, created_by
  ) values (
    v_environment, v_destination, v_consumer_key, p_consumer_generation,
    v_token_hash, p_request_id, 1,
    v_certificate_fingerprint, v_details, now(), auth.uid()
  ) returning * into v_certificate;

  if v_head.environment_key is null then
    v_head_generation := 1;
    insert into public.leghevo_operational_consumer_heads(
      environment_key, destination_key, generation, consumer_id,
      consumer_generation, state, last_stream_sequence, last_message_id,
      last_receipt_id, affected_reason, last_request_id, updated_at
    ) values (
      v_environment, v_destination, v_head_generation, v_certificate.id,
      p_consumer_generation, 'active', 0, null, null, null,
      p_request_id, now()
    );
  else
    v_head_generation := v_head.generation + 1;
    update public.leghevo_operational_consumer_heads
    set generation = v_head_generation,
        consumer_id = v_certificate.id,
        consumer_generation = p_consumer_generation,
        state = 'active',
        affected_reason = null,
        last_request_id = p_request_id,
        updated_at = now()
    where environment_key = v_environment
      and destination_key = v_destination;
  end if;

  v_event_fingerprint :=
    public.compute_leghevo_operational_consumer_event_fingerprint_v1(
      v_environment, v_destination, 'certified', v_head_generation,
      null, null, v_certificate.id, null,
      'consumer.certified', v_details);
  insert into public.leghevo_operational_consumer_events(
    environment_key, destination_key, request_id, event_type, generation,
    message_id, stream_sequence, consumer_id, receipt_id, reason_code,
    event_fingerprint, details, created_at, created_by
  ) values (
    v_environment, v_destination, p_request_id, 'certified', v_head_generation,
    null, null, v_certificate.id, null, 'consumer.certified',
    v_event_fingerprint, v_details, now(), auth.uid()
  );
  perform set_config('leghevo.operational_consumer_context', '', true);

  return jsonb_build_object(
    'consumerId', v_certificate.id,
    'consumerGeneration', v_certificate.consumer_generation,
    'certificateFingerprint', v_certificate.certificate_fingerprint,
    'reused', false
  );
exception when others then
  perform set_config('leghevo.operational_consumer_context', '', true);
  raise;
end;
$function$;

revoke all on function public.certify_leghevo_operational_consumer_v1(
  text,text,text,bigint,uuid,uuid,jsonb
) from public, anon, authenticated;
grant execute on function public.certify_leghevo_operational_consumer_v1(
  text,text,text,bigint,uuid,uuid,jsonb
) to service_role;

create or replace function public.claim_leghevo_operational_outbox_v2(
  p_environment_key text,
  p_destination_key text,
  p_worker_key text,
  p_worker_generation bigint,
  p_delivery_fencing_token uuid,
  p_consumer_key text,
  p_consumer_generation bigint,
  p_consumer_fencing_token uuid,
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
  v_consumer_key text := lower(trim(coalesce(p_consumer_key, '')));
  v_delivery_token_hash text;
  v_head public.leghevo_operational_consumer_heads%rowtype;
  v_certificate public.leghevo_operational_consumer_certificates%rowtype;
  v_row record;
  v_new_generation bigint;
  v_items jsonb := '[]'::jsonb;
  v_now timestamptz := now();
begin
  if v_environment not in ('production','staging')
    or v_destination not in ('operations_center','notification_dispatch')
    or v_worker !~ '^[a-z0-9][a-z0-9._-]{2,79}$'
    or coalesce(p_worker_generation, 0) < 1
    or p_delivery_fencing_token is null
    or v_consumer_key !~ '^[a-z0-9][a-z0-9._-]{2,79}$'
    or coalesce(p_consumer_generation, 0) < 1
    or p_consumer_fencing_token is null
    or p_batch_size not between 1 and 200
    or p_lease_seconds not between 15 and 300 then
    raise exception 'Richiesta claim consumer-aware non valida.';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'leghevo:operational-consumer:' || v_environment || ':' || v_destination, 0));
  select head.* into strict v_head
  from public.leghevo_operational_consumer_heads head
  where head.environment_key = v_environment
    and head.destination_key = v_destination
  for update;
  select certificate.* into strict v_certificate
  from public.leghevo_operational_consumer_certificates certificate
  where certificate.id = v_head.consumer_id;

  if v_head.state <> 'active'
    or v_certificate.consumer_key <> v_consumer_key
    or v_certificate.consumer_generation <> p_consumer_generation
    or v_certificate.fencing_token_hash <>
      pg_catalog.md5(p_consumer_fencing_token::text)
    or v_certificate.certificate_fingerprint <>
      public.compute_leghevo_operational_consumer_certificate_fingerprint_v1(
        v_certificate.environment_key, v_certificate.destination_key,
        v_certificate.consumer_key, v_certificate.consumer_generation,
        v_certificate.fencing_token_hash, v_certificate.contract_version) then
    raise exception 'Consumatore operativo non certificato o fencing non valido.';
  end if;

  v_delivery_token_hash := pg_catalog.md5(p_delivery_fencing_token::text);
  select
    delivery.message_id,
    delivery.destination_key,
    delivery.generation,
    message.stream_sequence,
    message.event_type,
    message.aggregate_key,
    message.priority,
    message.payload,
    message.message_fingerprint,
    message.source_created_at
  into v_row
  from public.leghevo_operational_outbox_delivery_heads delivery
  join public.leghevo_operational_outbox_messages message
    on message.id = delivery.message_id
  where message.environment_key = v_environment
    and delivery.destination_key = v_destination
    and message.stream_sequence = v_head.last_stream_sequence + 1
    and (
      (delivery.state in ('pending','retry')
        and coalesce(delivery.next_attempt_at, '-infinity'::timestamptz) <= v_now)
      or (delivery.state = 'leased' and delivery.leased_until < v_now)
    )
    and coalesce(delivery.worker_generation, 0) <= p_worker_generation
  for update of delivery skip locked;

  if found then
    v_new_generation := v_row.generation + 1;
    perform set_config('leghevo.operational_outbox_context', 'allowed', true);
    update public.leghevo_operational_outbox_delivery_heads
    set generation = v_new_generation,
        state = 'leased',
        worker_key = v_worker,
        worker_generation = p_worker_generation,
        lease_token_hash = v_delivery_token_hash,
        leased_until = v_now + make_interval(secs => p_lease_seconds),
        next_attempt_at = null,
        delivered_at = null,
        updated_at = v_now
    where message_id = v_row.message_id
      and destination_key = v_destination;
    perform set_config('leghevo.operational_outbox_context', '', true);

    v_items := jsonb_build_array(jsonb_build_object(
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
  end if;

  return jsonb_build_object(
    'environment', v_environment,
    'destinationKey', v_destination,
    'consumerGeneration', p_consumer_generation,
    'workerGeneration', p_worker_generation,
    'claimedCount', jsonb_array_length(v_items),
    'items', v_items,
    'checkedAt', v_now
  );
exception when no_data_found then
  perform set_config('leghevo.operational_outbox_context', '', true);
  raise exception 'Consumatore operativo corrente non disponibile.';
when others then
  perform set_config('leghevo.operational_outbox_context', '', true);
  raise;
end;
$function$;

revoke all on function public.claim_leghevo_operational_outbox_v2(
  text,text,text,bigint,uuid,text,bigint,uuid,integer,integer
) from public, anon, authenticated;
grant execute on function public.claim_leghevo_operational_outbox_v2(
  text,text,text,bigint,uuid,text,bigint,uuid,integer,integer
) to service_role;

create or replace function public.apply_leghevo_operational_consumer_message_v1(
  p_environment_key text,
  p_message_id bigint,
  p_destination_key text,
  p_delivery_generation bigint,
  p_worker_key text,
  p_worker_generation bigint,
  p_delivery_fencing_token uuid,
  p_consumer_key text,
  p_consumer_generation bigint,
  p_consumer_fencing_token uuid,
  p_application_key text,
  p_application_fingerprint text,
  p_request_id uuid,
  p_details jsonb default '{}'::jsonb
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
  v_consumer_key text := lower(trim(coalesce(p_consumer_key, '')));
  v_application_key text := trim(coalesce(p_application_key, ''));
  v_application_fingerprint text := lower(trim(coalesce(p_application_fingerprint, '')));
  v_details jsonb := coalesce(p_details, '{}'::jsonb);
  v_consumer_token_hash text;
  v_head public.leghevo_operational_consumer_heads%rowtype;
  v_certificate public.leghevo_operational_consumer_certificates%rowtype;
  v_message public.leghevo_operational_outbox_messages%rowtype;
  v_delivery public.leghevo_operational_outbox_delivery_heads%rowtype;
  v_existing public.leghevo_operational_consumer_receipts%rowtype;
  v_receipt public.leghevo_operational_consumer_receipts%rowtype;
  v_signature text;
  v_receipt_fingerprint text;
  v_event_fingerprint text;
  v_completion jsonb;
  v_new_generation bigint;
begin
  if v_environment not in ('production','staging')
    or v_destination not in ('operations_center','notification_dispatch')
    or coalesce(p_message_id, 0) < 1
    or coalesce(p_delivery_generation, 0) < 1
    or v_worker !~ '^[a-z0-9][a-z0-9._-]{2,79}$'
    or coalesce(p_worker_generation, 0) < 1
    or p_delivery_fencing_token is null
    or v_consumer_key !~ '^[a-z0-9][a-z0-9._-]{2,79}$'
    or coalesce(p_consumer_generation, 0) < 1
    or p_consumer_fencing_token is null
    or char_length(v_application_key) not between 3 and 160
    or v_application_fingerprint !~ '^[0-9a-f]{64}$'
    or p_request_id is null
    or jsonb_typeof(v_details) is distinct from 'object' then
    raise exception 'Ack applicativo end-to-end non valido.';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'leghevo:operational-consumer:' || v_environment || ':' || v_destination, 0));

  select receipt.* into v_existing
  from public.leghevo_operational_consumer_receipts receipt
  where receipt.request_id = p_request_id;
  if found then
    if v_existing.message_id <> p_message_id
      or v_existing.destination_key <> v_destination
      or v_existing.application_key <> v_application_key
      or v_existing.application_fingerprint <> v_application_fingerprint then
      raise exception 'request_id già utilizzato per un ack diverso.';
    end if;
    return jsonb_build_object(
      'receiptId', v_existing.id,
      'messageId', v_existing.message_id,
      'destinationKey', v_existing.destination_key,
      'streamSequence', v_existing.stream_sequence,
      'receiptFingerprint', v_existing.receipt_fingerprint,
      'reused', true
    );
  end if;

  if exists (
    select 1 from public.leghevo_operational_outbox_delivery_attempts attempt
    where attempt.request_id = p_request_id
  ) then
    raise exception 'request_id già utilizzato da un tentativo di consegna precedente.';
  end if;

  select receipt.* into v_existing
  from public.leghevo_operational_consumer_receipts receipt
  where receipt.message_id = p_message_id
    and receipt.destination_key = v_destination;
  if found then
    if v_existing.application_key <> v_application_key
      or v_existing.application_fingerprint <> v_application_fingerprint then
      raise exception 'Messaggio già applicato con una fingerprint diversa.';
    end if;
    return jsonb_build_object(
      'receiptId', v_existing.id,
      'messageId', v_existing.message_id,
      'destinationKey', v_existing.destination_key,
      'streamSequence', v_existing.stream_sequence,
      'receiptFingerprint', v_existing.receipt_fingerprint,
      'reused', true
    );
  end if;

  select head.* into strict v_head
  from public.leghevo_operational_consumer_heads head
  where head.environment_key = v_environment
    and head.destination_key = v_destination
  for update;
  select certificate.* into strict v_certificate
  from public.leghevo_operational_consumer_certificates certificate
  where certificate.id = v_head.consumer_id;
  select message.* into strict v_message
  from public.leghevo_operational_outbox_messages message
  where message.id = p_message_id;
  select delivery.* into strict v_delivery
  from public.leghevo_operational_outbox_delivery_heads delivery
  where delivery.message_id = p_message_id
    and delivery.destination_key = v_destination
  for update;

  v_consumer_token_hash := pg_catalog.md5(p_consumer_fencing_token::text);
  if v_head.state <> 'active'
    or v_certificate.environment_key <> v_environment
    or v_certificate.destination_key <> v_destination
    or v_certificate.consumer_key <> v_consumer_key
    or v_certificate.consumer_generation <> p_consumer_generation
    or v_certificate.fencing_token_hash <> v_consumer_token_hash
    or v_message.environment_key <> v_environment
    or v_message.stream_sequence <> v_head.last_stream_sequence + 1 then
    raise exception 'Ack bloccato: consumatore, ambiente o sequenza non autorevoli.';
  end if;

  if v_delivery.state <> 'leased'
    or v_delivery.generation <> p_delivery_generation
    or v_delivery.worker_key <> v_worker
    or v_delivery.worker_generation <> p_worker_generation
    or v_delivery.lease_token_hash <>
      pg_catalog.md5(p_delivery_fencing_token::text)
    or v_delivery.leased_until < now() then
    raise exception 'Ack bloccato: lease o fencing della consegna non più valido.';
  end if;

  v_signature := public.leghevo_sha256_hex_v1(
    v_environment || '|' || p_message_id::text || '|' || v_destination || '|' ||
    v_message.stream_sequence::text || '|' || v_message.message_fingerprint || '|' ||
    v_certificate.id::text || '|' || p_consumer_generation::text || '|' ||
    v_application_key || '|' || v_application_fingerprint || '|' ||
    p_request_id::text || '|' || p_consumer_fencing_token::text);
  v_receipt_fingerprint :=
    public.compute_leghevo_operational_consumer_receipt_fingerprint_v1(
      v_environment, p_message_id, v_destination, v_message.stream_sequence,
      v_message.message_fingerprint, v_certificate.id,
      p_consumer_generation, v_consumer_token_hash, v_application_key,
      v_application_fingerprint, v_signature, 'live', 1);
  v_new_generation := v_head.generation + 1;

  perform set_config('leghevo.operational_consumer_context', 'allowed', true);
  insert into public.leghevo_operational_consumer_receipts(
    request_id, environment_key, message_id, destination_key,
    stream_sequence, message_fingerprint, consumer_id,
    consumer_generation, consumer_token_hash, application_key,
    application_fingerprint, receipt_signature, receipt_fingerprint,
    adoption_mode, contract_version, details, applied_at, recorded_by
  ) values (
    p_request_id, v_environment, p_message_id, v_destination,
    v_message.stream_sequence, v_message.message_fingerprint,
    v_certificate.id, p_consumer_generation, v_consumer_token_hash,
    v_application_key, v_application_fingerprint, v_signature,
    v_receipt_fingerprint, 'live', 1, v_details, now(), auth.uid()
  ) returning * into v_receipt;

  update public.leghevo_operational_consumer_heads
  set generation = v_new_generation,
      last_stream_sequence = v_message.stream_sequence,
      last_message_id = p_message_id,
      last_receipt_id = v_receipt.id,
      state = 'active',
      affected_reason = null,
      last_request_id = p_request_id,
      updated_at = now()
  where environment_key = v_environment
    and destination_key = v_destination;

  v_event_fingerprint :=
    public.compute_leghevo_operational_consumer_event_fingerprint_v1(
      v_environment, v_destination, 'applied', v_new_generation,
      p_message_id, v_message.stream_sequence, v_certificate.id,
      v_receipt.id, 'consumer.applied', v_details);
  insert into public.leghevo_operational_consumer_events(
    environment_key, destination_key, request_id, event_type, generation,
    message_id, stream_sequence, consumer_id, receipt_id, reason_code,
    event_fingerprint, details, created_at, created_by
  ) values (
    v_environment, v_destination, p_request_id, 'applied', v_new_generation,
    p_message_id, v_message.stream_sequence, v_certificate.id,
    v_receipt.id, 'consumer.applied', v_event_fingerprint,
    v_details, now(), auth.uid()
  );
  perform set_config('leghevo.operational_consumer_context', '', true);

  v_completion := public.complete_leghevo_operational_outbox_delivery_v1(
    p_message_id, v_destination, p_delivery_generation,
    v_worker, p_worker_generation, p_delivery_fencing_token,
    'delivered', null, v_signature, p_request_id,
    v_details || jsonb_build_object(
      'consumerReceiptId', v_receipt.id,
      'consumerReceiptFingerprint', v_receipt.receipt_fingerprint,
      'applicationKey', v_application_key));

  return jsonb_build_object(
    'receiptId', v_receipt.id,
    'messageId', p_message_id,
    'destinationKey', v_destination,
    'streamSequence', v_message.stream_sequence,
    'receiptFingerprint', v_receipt.receipt_fingerprint,
    'delivery', v_completion,
    'reused', false
  );
exception when no_data_found then
  perform set_config('leghevo.operational_consumer_context', '', true);
  raise exception 'Ack bloccato: testa, certificato, messaggio o consegna assenti.';
when others then
  perform set_config('leghevo.operational_consumer_context', '', true);
  raise;
end;
$function$;

revoke all on function public.apply_leghevo_operational_consumer_message_v1(
  text,bigint,text,bigint,text,bigint,uuid,text,bigint,uuid,text,text,uuid,jsonb
) from public, anon, authenticated;
grant execute on function public.apply_leghevo_operational_consumer_message_v1(
  text,bigint,text,bigint,text,bigint,uuid,text,bigint,uuid,text,text,uuid,jsonb
) to service_role;

create or replace function public.adopt_leghevo_operational_consumer_baseline_v1(
  p_environment_key text,
  p_destination_key text,
  p_consumer_key text,
  p_consumer_generation bigint,
  p_consumer_fencing_token uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_environment text := lower(trim(coalesce(p_environment_key, '')));
  v_destination text := lower(trim(coalesce(p_destination_key, '')));
  v_consumer_key text := lower(trim(coalesce(p_consumer_key, '')));
  v_head public.leghevo_operational_consumer_heads%rowtype;
  v_certificate public.leghevo_operational_consumer_certificates%rowtype;
  v_row record;
  v_receipt public.leghevo_operational_consumer_receipts%rowtype;
  v_application_fingerprint text;
  v_signature text;
  v_receipt_fingerprint text;
  v_event_fingerprint text;
  v_request_id uuid;
  v_count integer := 0;
  v_generation bigint;
begin
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'leghevo:operational-consumer:' || v_environment || ':' || v_destination, 0));
  select head.* into strict v_head
  from public.leghevo_operational_consumer_heads head
  where head.environment_key = v_environment
    and head.destination_key = v_destination
  for update;
  select certificate.* into strict v_certificate
  from public.leghevo_operational_consumer_certificates certificate
  where certificate.id = v_head.consumer_id;

  if v_head.state <> 'active'
    or v_certificate.consumer_key <> v_consumer_key
    or v_certificate.consumer_generation <> p_consumer_generation
    or v_certificate.fencing_token_hash <>
      pg_catalog.md5(p_consumer_fencing_token::text) then
    raise exception 'Adozione baseline bloccata: consumatore non autorevole.';
  end if;

  for v_row in
    select message.id as message_id,
      message.stream_sequence,
      message.message_fingerprint,
      attempt.response_fingerprint
    from public.leghevo_operational_outbox_messages message
    join public.leghevo_operational_outbox_delivery_heads delivery
      on delivery.message_id = message.id
     and delivery.destination_key = v_destination
    left join public.leghevo_operational_outbox_delivery_attempts attempt
      on attempt.id = delivery.last_attempt_id
    where message.environment_key = v_environment
      and delivery.state = 'delivered'
      and not exists (
        select 1 from public.leghevo_operational_consumer_receipts receipt
        where receipt.message_id = message.id
          and receipt.destination_key = v_destination)
    order by message.stream_sequence
  loop
    if v_row.stream_sequence <> v_head.last_stream_sequence + 1 then
      raise exception 'Adozione baseline bloccata: gap alla sequenza %.',
        v_row.stream_sequence;
    end if;
    v_request_id := gen_random_uuid();
    v_application_fingerprint := coalesce(
      v_row.response_fingerprint,
      public.leghevo_sha256_hex_v1(
        v_destination || '|legacy|' || v_row.message_id::text || '|' ||
        v_row.message_fingerprint));
    v_signature := public.leghevo_sha256_hex_v1(
      v_environment || '|' || v_row.message_id::text || '|' ||
      v_destination || '|' || v_row.stream_sequence::text || '|' ||
      v_row.message_fingerprint || '|' || v_certificate.id::text || '|' ||
      p_consumer_generation::text || '|legacy-baseline|' ||
      v_application_fingerprint || '|' || v_request_id::text || '|' ||
      p_consumer_fencing_token::text);
    v_receipt_fingerprint :=
      public.compute_leghevo_operational_consumer_receipt_fingerprint_v1(
        v_environment, v_row.message_id, v_destination,
        v_row.stream_sequence, v_row.message_fingerprint,
        v_certificate.id, p_consumer_generation,
        v_certificate.fencing_token_hash, 'legacy-baseline',
        v_application_fingerprint, v_signature, 'legacy_baseline', 1);
    v_generation := v_head.generation + 1;

    perform set_config('leghevo.operational_consumer_context', 'allowed', true);
    insert into public.leghevo_operational_consumer_receipts(
      request_id, environment_key, message_id, destination_key,
      stream_sequence, message_fingerprint, consumer_id,
      consumer_generation, consumer_token_hash, application_key,
      application_fingerprint, receipt_signature, receipt_fingerprint,
      adoption_mode, contract_version, details, applied_at, recorded_by
    ) values (
      v_request_id, v_environment, v_row.message_id, v_destination,
      v_row.stream_sequence, v_row.message_fingerprint,
      v_certificate.id, p_consumer_generation,
      v_certificate.fencing_token_hash, 'legacy-baseline',
      v_application_fingerprint, v_signature, v_receipt_fingerprint,
      'legacy_baseline', 1,
      jsonb_build_object('sourceMigration', 142, 'adopted', true),
      now(), auth.uid()
    ) returning * into v_receipt;

    update public.leghevo_operational_consumer_heads
    set generation = v_generation,
        last_stream_sequence = v_row.stream_sequence,
        last_message_id = v_row.message_id,
        last_receipt_id = v_receipt.id,
        state = 'active', affected_reason = null,
        last_request_id = v_request_id, updated_at = now()
    where environment_key = v_environment
      and destination_key = v_destination
    returning * into v_head;

    v_event_fingerprint :=
      public.compute_leghevo_operational_consumer_event_fingerprint_v1(
        v_environment, v_destination, 'adopted', v_generation,
        v_row.message_id, v_row.stream_sequence, v_certificate.id,
        v_receipt.id, 'consumer.legacy_baseline_adopted',
        jsonb_build_object('sourceMigration', 142));
    insert into public.leghevo_operational_consumer_events(
      environment_key, destination_key, request_id, event_type, generation,
      message_id, stream_sequence, consumer_id, receipt_id, reason_code,
      event_fingerprint, details, created_at, created_by
    ) values (
      v_environment, v_destination, v_request_id, 'adopted', v_generation,
      v_row.message_id, v_row.stream_sequence, v_certificate.id,
      v_receipt.id, 'consumer.legacy_baseline_adopted',
      v_event_fingerprint,
      jsonb_build_object('sourceMigration', 142), now(), auth.uid()
    );
    perform set_config('leghevo.operational_consumer_context', '', true);
    v_count := v_count + 1;
  end loop;

  return jsonb_build_object(
    'environment', v_environment,
    'destinationKey', v_destination,
    'adoptedCount', v_count,
    'lastStreamSequence', v_head.last_stream_sequence
  );
exception when others then
  perform set_config('leghevo.operational_consumer_context', '', true);
  raise;
end;
$function$;

revoke all on function public.adopt_leghevo_operational_consumer_baseline_v1(
  text,text,text,bigint,uuid
) from public, anon, authenticated, service_role;

create or replace function public.request_leghevo_operational_consumer_replay_v1(
  p_environment_key text,
  p_destination_key text,
  p_message_id bigint,
  p_request_id uuid,
  p_reason_code text,
  p_details jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_environment text := lower(trim(coalesce(p_environment_key, '')));
  v_destination text := lower(trim(coalesce(p_destination_key, '')));
  v_reason text := lower(trim(coalesce(p_reason_code, '')));
  v_details jsonb := coalesce(p_details, '{}'::jsonb);
  v_receipt public.leghevo_operational_consumer_receipts%rowtype;
  v_message public.leghevo_operational_outbox_messages%rowtype;
  v_head public.leghevo_operational_consumer_heads%rowtype;
  v_event public.leghevo_operational_consumer_events%rowtype;
  v_event_fingerprint text;
begin
  if v_environment not in ('production','staging')
    or v_destination not in ('operations_center','notification_dispatch')
    or coalesce(p_message_id, 0) < 1
    or p_request_id is null
    or char_length(v_reason) not between 3 and 160
    or jsonb_typeof(v_details) is distinct from 'object' then
    raise exception 'Richiesta replay consumatore non valida.';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'leghevo:operational-consumer:' || v_environment || ':' || v_destination, 0));
  select event.* into v_event
  from public.leghevo_operational_consumer_events event
  where event.environment_key = v_environment
    and event.destination_key = v_destination
    and event.request_id = p_request_id;
  if found then
    if v_event.event_type <> 'replay_requested'
      or v_event.message_id <> p_message_id
      or v_event.reason_code <> v_reason then
      raise exception 'request_id già utilizzato per un replay diverso.';
    end if;
    select receipt.* into strict v_receipt
    from public.leghevo_operational_consumer_receipts receipt
    where receipt.id = v_event.receipt_id;
    select message.* into strict v_message
    from public.leghevo_operational_outbox_messages message
    where message.id = p_message_id;
    return jsonb_build_object(
      'messageId', p_message_id,
      'destinationKey', v_destination,
      'streamSequence', v_message.stream_sequence,
      'payload', v_message.payload,
      'messageFingerprint', v_message.message_fingerprint,
      'receiptFingerprint', v_receipt.receipt_fingerprint,
      'reused', true
    );
  end if;

  select head.* into strict v_head
  from public.leghevo_operational_consumer_heads head
  where head.environment_key = v_environment
    and head.destination_key = v_destination;
  select receipt.* into strict v_receipt
  from public.leghevo_operational_consumer_receipts receipt
  where receipt.message_id = p_message_id
    and receipt.destination_key = v_destination;
  select message.* into strict v_message
  from public.leghevo_operational_outbox_messages message
  where message.id = p_message_id
    and message.environment_key = v_environment;

  if v_head.state <> 'active'
    or v_receipt.receipt_fingerprint <>
      public.compute_leghevo_operational_consumer_receipt_fingerprint_v1(
        v_receipt.environment_key, v_receipt.message_id,
        v_receipt.destination_key, v_receipt.stream_sequence,
        v_receipt.message_fingerprint, v_receipt.consumer_id,
        v_receipt.consumer_generation, v_receipt.consumer_token_hash,
        v_receipt.application_key, v_receipt.application_fingerprint,
        v_receipt.receipt_signature, v_receipt.adoption_mode,
        v_receipt.contract_version) then
    raise exception 'Replay bloccato: ricevuta non autorevole.';
  end if;

  v_event_fingerprint :=
    public.compute_leghevo_operational_consumer_event_fingerprint_v1(
      v_environment, v_destination, 'replay_requested', v_head.generation,
      p_message_id, v_message.stream_sequence, v_head.consumer_id,
      v_receipt.id, v_reason, v_details);
  perform set_config('leghevo.operational_consumer_context', 'allowed', true);
  insert into public.leghevo_operational_consumer_events(
    environment_key, destination_key, request_id, event_type, generation,
    message_id, stream_sequence, consumer_id, receipt_id, reason_code,
    event_fingerprint, details, created_at, created_by
  ) values (
    v_environment, v_destination, p_request_id, 'replay_requested',
    v_head.generation, p_message_id, v_message.stream_sequence,
    v_head.consumer_id, v_receipt.id, v_reason, v_event_fingerprint,
    v_details, now(), auth.uid()
  );
  perform set_config('leghevo.operational_consumer_context', '', true);

  return jsonb_build_object(
    'messageId', p_message_id,
    'destinationKey', v_destination,
    'streamSequence', v_message.stream_sequence,
    'payload', v_message.payload,
    'messageFingerprint', v_message.message_fingerprint,
    'receiptFingerprint', v_receipt.receipt_fingerprint,
    'reused', false
  );
exception when no_data_found then
  perform set_config('leghevo.operational_consumer_context', '', true);
  raise exception 'Replay bloccato: messaggio, testa o ricevuta assenti.';
when others then
  perform set_config('leghevo.operational_consumer_context', '', true);
  raise;
end;
$function$;

revoke all on function public.request_leghevo_operational_consumer_replay_v1(
  text,text,bigint,uuid,text,jsonb
) from public, anon, authenticated;
grant execute on function public.request_leghevo_operational_consumer_replay_v1(
  text,text,bigint,uuid,text,jsonb
) to service_role;

create or replace function public.get_leghevo_operational_consumer_delivery_model_v1(
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
  v_outbox jsonb;
  v_consumer_count bigint := 0;
  v_receipt_count bigint := 0;
  v_live_count bigint := 0;
  v_adopted_count bigint := 0;
  v_replay_count bigint := 0;
  v_expected_count bigint := 0;
  v_sequence_gap_count bigint := 0;
  v_fingerprint_mismatch_count bigint := 0;
  v_consistency_mismatch_count bigint := 0;
  v_certificate_mismatch_count bigint := 0;
  v_affected_count bigint := 0;
  v_last_ack_sequence bigint := 0;
  v_last_ack_at timestamptz;
  v_authoritative boolean := false;
  v_raw_integrity boolean := false;
  v_protected boolean := false;
  v_healthy boolean := false;
  v_status text;
  v_reason text;
begin
  if v_environment not in ('production','staging') then
    return jsonb_build_object(
      'protected', false, 'healthy', false, 'authoritative', false,
      'rawIntegrityHealthy', false, 'status', 'affected',
      'reasonCode', 'consumer_delivery.invalid_environment',
      'environment', v_environment
    );
  end if;

  v_outbox := public.get_leghevo_operational_outbox_model_v1(v_environment);

  select count(*),
    count(*) filter (where head.state = 'affected'),
    coalesce(min(head.last_stream_sequence), 0)
  into v_consumer_count, v_affected_count, v_last_ack_sequence
  from public.leghevo_operational_consumer_heads head
  where head.environment_key = v_environment;

  select count(*) into v_certificate_mismatch_count
  from public.leghevo_operational_consumer_heads head
  join public.leghevo_operational_consumer_certificates certificate
    on certificate.id = head.consumer_id
  where head.environment_key = v_environment
    and (
      certificate.environment_key <> head.environment_key
      or certificate.destination_key <> head.destination_key
      or certificate.consumer_generation <> head.consumer_generation
      or certificate.certificate_fingerprint <>
        public.compute_leghevo_operational_consumer_certificate_fingerprint_v1(
          certificate.environment_key, certificate.destination_key,
          certificate.consumer_key, certificate.consumer_generation,
          certificate.fencing_token_hash, certificate.contract_version)
    );

  select count(*),
    count(*) filter (where receipt.adoption_mode = 'live'),
    count(*) filter (where receipt.adoption_mode = 'legacy_baseline'),
    max(receipt.applied_at)
  into v_receipt_count, v_live_count, v_adopted_count, v_last_ack_at
  from public.leghevo_operational_consumer_receipts receipt
  where receipt.environment_key = v_environment;

  select count(*) into v_replay_count
  from public.leghevo_operational_consumer_events event
  where event.environment_key = v_environment
    and event.event_type = 'replay_requested';

  select count(*) into v_expected_count
  from public.leghevo_operational_outbox_delivery_heads delivery
  join public.leghevo_operational_outbox_messages message
    on message.id = delivery.message_id
  where message.environment_key = v_environment;

  select coalesce(sum(expected.max_sequence - expected.receipt_count), 0)
  into v_sequence_gap_count
  from (
    select destination.destination_key,
      coalesce(max(receipt.stream_sequence), 0) as max_sequence,
      count(receipt.id) as receipt_count
    from (values ('operations_center'::text), ('notification_dispatch'::text))
      destination(destination_key)
    left join public.leghevo_operational_consumer_receipts receipt
      on receipt.environment_key = v_environment
     and receipt.destination_key = destination.destination_key
    group by destination.destination_key
  ) expected;

  select count(*) into v_fingerprint_mismatch_count
  from public.leghevo_operational_consumer_receipts receipt
  where receipt.environment_key = v_environment
    and receipt.receipt_fingerprint <>
      public.compute_leghevo_operational_consumer_receipt_fingerprint_v1(
        receipt.environment_key, receipt.message_id,
        receipt.destination_key, receipt.stream_sequence,
        receipt.message_fingerprint, receipt.consumer_id,
        receipt.consumer_generation, receipt.consumer_token_hash,
        receipt.application_key, receipt.application_fingerprint,
        receipt.receipt_signature, receipt.adoption_mode,
        receipt.contract_version);

  select count(*) into v_consistency_mismatch_count
  from (
    select delivery.message_id, delivery.destination_key
    from public.leghevo_operational_outbox_delivery_heads delivery
    join public.leghevo_operational_outbox_messages message
      on message.id = delivery.message_id
    left join public.leghevo_operational_consumer_receipts receipt
      on receipt.message_id = delivery.message_id
     and receipt.destination_key = delivery.destination_key
    where message.environment_key = v_environment
      and (delivery.state = 'delivered') is distinct from (receipt.id is not null)
    union all
    select receipt.message_id, receipt.destination_key
    from public.leghevo_operational_consumer_receipts receipt
    join public.leghevo_operational_outbox_messages message
      on message.id = receipt.message_id
    join public.leghevo_operational_consumer_certificates certificate
      on certificate.id = receipt.consumer_id
    where receipt.environment_key = v_environment
      and (
        message.environment_key <> receipt.environment_key
        or message.stream_sequence <> receipt.stream_sequence
        or message.message_fingerprint <> receipt.message_fingerprint
        or certificate.environment_key <> receipt.environment_key
        or certificate.destination_key <> receipt.destination_key
        or certificate.consumer_generation <> receipt.consumer_generation
        or certificate.fencing_token_hash <> receipt.consumer_token_hash
      )
    union all
    select head.last_message_id, head.destination_key
    from public.leghevo_operational_consumer_heads head
    left join public.leghevo_operational_consumer_receipts receipt
      on receipt.id = head.last_receipt_id
     and receipt.message_id = head.last_message_id
     and receipt.destination_key = head.destination_key
    where head.environment_key = v_environment
      and head.last_stream_sequence > 0
      and (
        receipt.id is null
        or receipt.stream_sequence <> head.last_stream_sequence
        or receipt.consumer_id <> head.consumer_id
      )
  ) mismatch;

  v_authoritative := v_consumer_count = 2
    and v_certificate_mismatch_count = 0;
  v_raw_integrity := v_authoritative
    and coalesce((v_outbox ->> 'protected')::boolean, false)
    and v_receipt_count = v_expected_count
    and v_sequence_gap_count = 0
    and v_fingerprint_mismatch_count = 0
    and v_consistency_mismatch_count = 0;
  v_protected := v_raw_integrity and v_affected_count = 0;
  v_healthy := v_protected
    and coalesce((v_outbox ->> 'healthy')::boolean, false);
  v_status := case
    when not v_authoritative or v_affected_count > 0
      or v_fingerprint_mismatch_count > 0
      or v_consistency_mismatch_count > 0
      or v_sequence_gap_count > 0 then 'affected'
    when v_receipt_count < v_expected_count then 'attention'
    else 'active' end;
  v_reason := case
    when v_consumer_count <> 2 then 'consumer_delivery.consumer_not_authoritative'
    when v_certificate_mismatch_count > 0 then 'consumer_delivery.consumer_not_authoritative'
    when v_fingerprint_mismatch_count > 0 then 'consumer_delivery.receipt_fingerprint_changed'
    when v_sequence_gap_count > 0 then 'consumer_delivery.sequence_gap'
    when v_consistency_mismatch_count > 0 then 'consumer_delivery.receipt_consistency_mismatch'
    when v_receipt_count < v_expected_count then 'consumer_delivery.receipt_missing'
    when v_affected_count > 0 then 'consumer_delivery.affected'
    else 'consumer_delivery.active' end;

  return jsonb_build_object(
    'protected', v_protected,
    'healthy', v_healthy,
    'authoritative', v_authoritative,
    'rawIntegrityHealthy', v_raw_integrity,
    'status', v_status,
    'reasonCode', v_reason,
    'environment', v_environment,
    'consumerCount', v_consumer_count,
    'receiptCount', v_receipt_count,
    'liveReceiptCount', v_live_count,
    'adoptedReceiptCount', v_adopted_count,
    'expectedReceiptCount', v_expected_count,
    'replayRequestCount', v_replay_count,
    'sequenceGapCount', v_sequence_gap_count,
    'fingerprintMismatchCount', v_fingerprint_mismatch_count,
    'receiptConsistencyMismatchCount', v_consistency_mismatch_count,
    'certificateMismatchCount', v_certificate_mismatch_count,
    'affectedConsumerCount', v_affected_count,
    'lastAcknowledgedSequence', v_last_ack_sequence,
    'lastAcknowledgedAt', v_last_ack_at,
    'checkedAt', now()
  );
end;
$function$;

revoke all on function public.get_leghevo_operational_consumer_delivery_model_v1(text)
from public, anon;
grant execute on function public.get_leghevo_operational_consumer_delivery_model_v1(text)
to authenticated, service_role;

create or replace function public.reconcile_leghevo_operational_consumer_delivery_v1(
  p_environment_key text,
  p_request_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_environment text := lower(trim(coalesce(p_environment_key, '')));
  v_model jsonb;
  v_target_state text;
  v_reason text;
  v_head public.leghevo_operational_consumer_heads%rowtype;
  v_generation bigint;
  v_event_type text;
  v_event_fingerprint text;
begin
  if v_environment not in ('production','staging') or p_request_id is null then
    raise exception 'Riconciliazione consumer delivery non valida.';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('leghevo:operational-consumer:' || v_environment, 0));

  v_model := public.get_leghevo_operational_consumer_delivery_model_v1(v_environment);
  v_target_state := case
    when coalesce((v_model ->> 'rawIntegrityHealthy')::boolean, false)
      then 'active'
    else 'affected' end;
  v_reason := case when v_target_state = 'active' then null
    else coalesce(v_model ->> 'reasonCode', 'consumer_delivery.affected') end;

  for v_head in
    select head.* from public.leghevo_operational_consumer_heads head
    where head.environment_key = v_environment
    order by head.destination_key
    for update
  loop
    if v_head.state = v_target_state
      and v_head.affected_reason is not distinct from v_reason then
      continue;
    end if;
    v_generation := v_head.generation + 1;
    v_event_type := case when v_target_state = 'active'
      then 'revalidated' else 'affected' end;
    perform set_config('leghevo.operational_consumer_context', 'allowed', true);
    update public.leghevo_operational_consumer_heads
    set generation = v_generation,
        state = v_target_state,
        affected_reason = v_reason,
        last_request_id = p_request_id,
        updated_at = now()
    where environment_key = v_environment
      and destination_key = v_head.destination_key;
    v_event_fingerprint :=
      public.compute_leghevo_operational_consumer_event_fingerprint_v1(
        v_environment, v_head.destination_key, v_event_type,
        v_generation, v_head.last_message_id,
        nullif(v_head.last_stream_sequence, 0), v_head.consumer_id,
        v_head.last_receipt_id,
        coalesce(v_reason, 'consumer_delivery.revalidated'), v_model);
    insert into public.leghevo_operational_consumer_events(
      environment_key, destination_key, request_id, event_type, generation,
      message_id, stream_sequence, consumer_id, receipt_id, reason_code,
      event_fingerprint, details, created_at, created_by
    ) values (
      v_environment, v_head.destination_key, p_request_id, v_event_type,
      v_generation, v_head.last_message_id,
      nullif(v_head.last_stream_sequence, 0), v_head.consumer_id,
      v_head.last_receipt_id,
      coalesce(v_reason, 'consumer_delivery.revalidated'),
      v_event_fingerprint, v_model, now(), auth.uid()
    );
    perform set_config('leghevo.operational_consumer_context', '', true);
  end loop;

  return public.get_leghevo_operational_consumer_delivery_model_v1(v_environment);
exception when others then
  perform set_config('leghevo.operational_consumer_context', '', true);
  raise;
end;
$function$;

revoke all on function public.reconcile_leghevo_operational_consumer_delivery_v1(text,uuid)
from public, anon, authenticated;
grant execute on function public.reconcile_leghevo_operational_consumer_delivery_v1(text,uuid)
to service_role;

create or replace function public.promote_leghevo_application_rollout_v4(
  p_environment_key text,
  p_target_percentage integer,
  p_request_id uuid,
  p_reason text default 'rollout.end_to_end_ack_protected_promotion'
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_environment text := lower(trim(coalesce(p_environment_key, '')));
  v_consumer_delivery jsonb;
begin
  if v_environment not in ('production','staging') or p_request_id is null then
    raise exception 'Promozione con barriera ack end-to-end non valida.';
  end if;
  v_consumer_delivery :=
    public.get_leghevo_operational_consumer_delivery_model_v1(v_environment);
  if not coalesce((v_consumer_delivery ->> 'protected')::boolean, false)
    or not coalesce((v_consumer_delivery ->> 'healthy')::boolean, false) then
    raise exception 'Promozione bloccata: ack end-to-end non autorevoli. Dettaglio: %',
      v_consumer_delivery;
  end if;
  return public.promote_leghevo_application_rollout_v3(
    v_environment, p_target_percentage, p_request_id, trim(p_reason));
end;
$function$;

revoke all on function public.promote_leghevo_application_rollout_v4(
  text,integer,uuid,text
) from public, anon, authenticated;
grant execute on function public.promote_leghevo_application_rollout_v4(
  text,integer,uuid,text
) to service_role;

revoke execute on function public.claim_leghevo_operational_outbox_v1(
  text,text,text,bigint,uuid,integer,integer
) from service_role;
revoke execute on function public.complete_leghevo_operational_outbox_delivery_v1(
  bigint,text,bigint,text,bigint,uuid,text,text,text,uuid,jsonb
) from service_role;
revoke execute on function public.promote_leghevo_application_rollout_v3(
  text,integer,uuid,text
) from service_role;

create or replace function public.get_leghevo_client_rollout_eligibility_v4(
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
  v_consumer_delivery jsonb;
  v_eligible boolean;
  v_reason text;
begin
  v_base := public.get_leghevo_client_rollout_eligibility_v3(
    p_application_version, p_bundle_fingerprint, p_installation_id);
  v_consumer_delivery :=
    public.get_leghevo_operational_consumer_delivery_model_v1('production');
  v_eligible := coalesce((v_base ->> 'rolloutEligible')::boolean, false)
    and coalesce((v_consumer_delivery ->> 'healthy')::boolean, false);
  v_reason := case
    when not coalesce((v_base ->> 'compatible')::boolean, false)
      then coalesce(v_base ->> 'reasonCode', 'release.incompatible')
    when not coalesce((v_consumer_delivery ->> 'authoritative')::boolean, false)
      then 'consumer_delivery.consumer_not_authoritative'
    when coalesce((v_consumer_delivery ->> 'fingerprintMismatchCount')::bigint, 0) > 0
      then 'consumer_delivery.receipt_fingerprint_changed'
    when coalesce((v_consumer_delivery ->> 'sequenceGapCount')::bigint, 0) > 0
      then 'consumer_delivery.sequence_gap'
    when coalesce((v_consumer_delivery ->> 'receiptConsistencyMismatchCount')::bigint, 0) > 0
      then 'consumer_delivery.receipt_consistency_mismatch'
    when coalesce((v_consumer_delivery ->> 'receiptCount')::bigint, 0) <
      coalesce((v_consumer_delivery ->> 'expectedReceiptCount')::bigint, 0)
      then 'consumer_delivery.receipt_missing'
    else coalesce(v_base ->> 'reasonCode', 'release.compatible') end;

  return v_base || jsonb_build_object(
    'compatible', coalesce((v_base ->> 'compatible')::boolean, false) and v_eligible,
    'rolloutEligible', v_eligible,
    'reasonCode', v_reason,
    'consumerDeliveryProtected',
      coalesce((v_consumer_delivery ->> 'protected')::boolean, false),
    'consumerDeliveryHealthy',
      coalesce((v_consumer_delivery ->> 'healthy')::boolean, false),
    'consumerDeliveryStatus', v_consumer_delivery ->> 'status',
    'consumerReceiptCount',
      coalesce((v_consumer_delivery ->> 'receiptCount')::bigint, 0),
    'consumerExpectedReceiptCount',
      coalesce((v_consumer_delivery ->> 'expectedReceiptCount')::bigint, 0),
    'consumerLastAcknowledgedSequence',
      coalesce((v_consumer_delivery ->> 'lastAcknowledgedSequence')::bigint, 0),
    'checkedAt', now()
  );
end;
$function$;

revoke all on function public.get_leghevo_client_rollout_eligibility_v4(text,text,uuid)
from public;
grant execute on function public.get_leghevo_client_rollout_eligibility_v4(text,text,uuid)
to anon, authenticated;

create or replace function public.get_league_provider_sync_health_v37(p_league_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_base jsonb;
  v_consumer_delivery jsonb;
begin
  v_base := public.get_league_provider_sync_health_v36(p_league_id);
  v_consumer_delivery :=
    public.get_leghevo_operational_consumer_delivery_model_v1('production');
  return v_base || jsonb_build_object(
    'applicationOperationalConsumerDelivery', v_consumer_delivery,
    'healthy', coalesce((v_base ->> 'healthy')::boolean, false)
      and coalesce((v_consumer_delivery ->> 'healthy')::boolean, false),
    'protected', coalesce((v_base ->> 'protected')::boolean, false)
      and coalesce((v_consumer_delivery ->> 'protected')::boolean, false)
  );
end;
$function$;

revoke all on function public.get_league_provider_sync_health_v37(uuid)
from public, anon;
grant execute on function public.get_league_provider_sync_health_v37(uuid)
to authenticated;

create or replace function public.get_league_season_state_v16(p_league_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_base jsonb;
  v_consumer_delivery jsonb;
begin
  v_base := public.get_league_season_state_v15(p_league_id);
  v_consumer_delivery :=
    public.get_leghevo_operational_consumer_delivery_model_v1('production');
  return v_base || jsonb_build_object(
    'applicationOperationalConsumerDelivery', v_consumer_delivery);
end;
$function$;

revoke all on function public.get_league_season_state_v16(uuid)
from public, anon;
grant execute on function public.get_league_season_state_v16(uuid)
to authenticated;

create or replace function public.get_league_management_state_v26(p_league_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_base jsonb;
  v_consumer_delivery jsonb;
  v_checks jsonb;
begin
  v_base := public.get_league_management_state_v25(p_league_id);
  v_consumer_delivery :=
    public.get_leghevo_operational_consumer_delivery_model_v1('production');
  v_checks := coalesce(v_base -> 'checks', '{}'::jsonb) || jsonb_build_object(
    'applicationOperationalConsumerDeliveryProtected',
      coalesce((v_consumer_delivery ->> 'protected')::boolean, false),
    'applicationOperationalConsumerDeliveryHealthy',
      coalesce((v_consumer_delivery ->> 'healthy')::boolean, false)
  );
  return v_base || jsonb_build_object(
    'applicationOperationalConsumerDelivery', v_consumer_delivery,
    'checks', v_checks
  );
end;
$function$;

revoke all on function public.get_league_management_state_v26(uuid)
from public, anon;
grant execute on function public.get_league_management_state_v26(uuid)
to authenticated;

-- Helper temporaneo usato soltanto per esercitare la catena end-to-end nello script.
create or replace function public.seed_leghevo_operational_consumer_drain_v1(
  p_environment_key text,
  p_destination_key text,
  p_consumer_key text,
  p_consumer_generation bigint,
  p_consumer_fencing_token uuid,
  p_delivery_fencing_token uuid
)
returns integer
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_claim jsonb;
  v_item jsonb;
  v_count integer := 0;
  v_application_fingerprint text;
  v_outcome jsonb;
begin
  loop
    v_claim := public.claim_leghevo_operational_outbox_v2(
      p_environment_key, p_destination_key,
      'leghevo-consumer-seed-worker', 2, p_delivery_fencing_token,
      p_consumer_key, p_consumer_generation, p_consumer_fencing_token,
      200, 120);
    exit when coalesce((v_claim ->> 'claimedCount')::integer, 0) = 0;
    for v_item in
      select value from pg_catalog.jsonb_array_elements(v_claim -> 'items')
    loop
      v_application_fingerprint := public.leghevo_sha256_hex_v1(
        p_destination_key || '|applied|' || (v_item ->> 'messageId') || '|' ||
        (v_item ->> 'messageFingerprint'));
      v_outcome := public.apply_leghevo_operational_consumer_message_v1(
        p_environment_key,
        (v_item ->> 'messageId')::bigint,
        p_destination_key,
        (v_item ->> 'deliveryGeneration')::bigint,
        'leghevo-consumer-seed-worker', 2, p_delivery_fencing_token,
        p_consumer_key, p_consumer_generation, p_consumer_fencing_token,
        'leghevo-' || p_destination_key,
        v_application_fingerprint, gen_random_uuid(),
        jsonb_build_object('seedDelivery', true, 'sourceMigration', 142));
      v_count := v_count + 1;
    end loop;
  end loop;
  return v_count;
end;
$function$;

revoke all on function public.seed_leghevo_operational_consumer_drain_v1(
  text,text,text,bigint,uuid,uuid
) from public, anon, authenticated, service_role;

-- Certificazione consumatori, adozione storica e release v0.62.38.
do $seed_release$
declare
  v_operations_consumer_token uuid := gen_random_uuid();
  v_notification_consumer_token uuid := gen_random_uuid();
  v_operations_delivery_token uuid := gen_random_uuid();
  v_notification_delivery_token uuid := gen_random_uuid();
  v_telemetry_token uuid := gen_random_uuid();
  v_outcome jsonb;
  v_now timestamptz := now();
begin
  if exists (
    select 1 from public.leghevo_application_release_certificates c
    where c.application_version = '0.62.38'
  ) and exists (
    select 1 from public.leghevo_operational_telemetry_observations observation
    where observation.request_id =
      '62380000-0000-4000-8000-000000000016'::uuid
  ) then
    return;
  end if;

  v_outcome := public.certify_leghevo_operational_consumer_v1(
    'production', 'operations_center', 'leghevo-operations-consumer', 1,
    v_operations_consumer_token,
    '62380000-0000-4000-8000-000000000001'::uuid,
    jsonb_build_object('sourceMigration', 142, 'contract', 'end-to-end-ack-v1'));
  v_outcome := public.certify_leghevo_operational_consumer_v1(
    'production', 'notification_dispatch', 'leghevo-notification-consumer', 1,
    v_notification_consumer_token,
    '62380000-0000-4000-8000-000000000002'::uuid,
    jsonb_build_object('sourceMigration', 142, 'contract', 'end-to-end-ack-v1'));

  v_outcome := public.adopt_leghevo_operational_consumer_baseline_v1(
    'production', 'operations_center', 'leghevo-operations-consumer', 1,
    v_operations_consumer_token);
  v_outcome := public.adopt_leghevo_operational_consumer_baseline_v1(
    'production', 'notification_dispatch', 'leghevo-notification-consumer', 1,
    v_notification_consumer_token);

  if not exists (
    select 1 from public.leghevo_application_release_certificates c
    where c.application_version = '0.62.38'
  ) then
    v_outcome := public.certify_leghevo_application_release_v1(
      '0.62.38',
      '0cd5a31e020b59673a72d52b2b7c3ab181038c135da711e8c96fff92ba111e28',
      '0.62.37', '0.62.38',
      '62380000-0000-4000-8000-000000000003'::uuid,
      jsonb_build_object('baseline', false, 'sourceMigration', 142));
    v_outcome := public.certify_leghevo_application_rollout_v1(
      'production', '0.62.38', 10, 100, 500, 3, 100,
      '62380000-0000-4000-8000-000000000004'::uuid,
      jsonb_build_object('strategy', 'consumer-inbox-ack', 'sourceMigration', 142));
    v_outcome := public.activate_leghevo_release_with_rollout_v1(
      'production', '0.62.38',
      '62380000-0000-4000-8000-000000000005'::uuid,
      '62380000-0000-4000-8000-000000000006'::uuid,
      'consumer_delivery.production_activation');
    v_outcome := public.certify_leghevo_operational_telemetry_source_v1(
      'production', 'leghevo-production-observer', 3, v_telemetry_token,
      '62380000-0000-4000-8000-000000000007'::uuid,
      jsonb_build_object('provider', 'leghevo-runtime', 'sourceMigration', 142));

    v_outcome := public.record_leghevo_authoritative_operational_window_v1(
      'production', 'leghevo-production-observer', 3, v_telemetry_token, 1,
      v_now - interval '25 minutes', v_now - interval '20 minutes',
      1000, 2, 0, 210,
      '62380000-0000-4000-8000-000000000008'::uuid,
      jsonb_build_object('seedStage', 10));
    perform public.seed_leghevo_operational_consumer_drain_v1(
      'production', 'operations_center', 'leghevo-operations-consumer', 1,
      v_operations_consumer_token, v_operations_delivery_token);
    perform public.seed_leghevo_operational_consumer_drain_v1(
      'production', 'notification_dispatch', 'leghevo-notification-consumer', 1,
      v_notification_consumer_token, v_notification_delivery_token);

    v_outcome := public.promote_leghevo_application_rollout_v4(
      'production', 35,
      '62380000-0000-4000-8000-000000000009'::uuid,
      'rollout.consumer_ack_promotion_35');
    perform public.seed_leghevo_operational_consumer_drain_v1(
      'production', 'operations_center', 'leghevo-operations-consumer', 1,
      v_operations_consumer_token, v_operations_delivery_token);
    perform public.seed_leghevo_operational_consumer_drain_v1(
      'production', 'notification_dispatch', 'leghevo-notification-consumer', 1,
      v_notification_consumer_token, v_notification_delivery_token);

    v_outcome := public.record_leghevo_authoritative_operational_window_v1(
      'production', 'leghevo-production-observer', 3, v_telemetry_token, 2,
      v_now - interval '20 minutes', v_now - interval '15 minutes',
      1000, 2, 0, 205,
      '62380000-0000-4000-8000-000000000010'::uuid,
      jsonb_build_object('seedStage', 35));
    perform public.seed_leghevo_operational_consumer_drain_v1(
      'production', 'operations_center', 'leghevo-operations-consumer', 1,
      v_operations_consumer_token, v_operations_delivery_token);
    perform public.seed_leghevo_operational_consumer_drain_v1(
      'production', 'notification_dispatch', 'leghevo-notification-consumer', 1,
      v_notification_consumer_token, v_notification_delivery_token);
    v_outcome := public.promote_leghevo_application_rollout_v4(
      'production', 60,
      '62380000-0000-4000-8000-000000000011'::uuid,
      'rollout.consumer_ack_promotion_60');
    perform public.seed_leghevo_operational_consumer_drain_v1(
      'production', 'operations_center', 'leghevo-operations-consumer', 1,
      v_operations_consumer_token, v_operations_delivery_token);
    perform public.seed_leghevo_operational_consumer_drain_v1(
      'production', 'notification_dispatch', 'leghevo-notification-consumer', 1,
      v_notification_consumer_token, v_notification_delivery_token);

    v_outcome := public.record_leghevo_authoritative_operational_window_v1(
      'production', 'leghevo-production-observer', 3, v_telemetry_token, 3,
      v_now - interval '15 minutes', v_now - interval '10 minutes',
      1000, 1, 0, 200,
      '62380000-0000-4000-8000-000000000012'::uuid,
      jsonb_build_object('seedStage', 60));
    perform public.seed_leghevo_operational_consumer_drain_v1(
      'production', 'operations_center', 'leghevo-operations-consumer', 1,
      v_operations_consumer_token, v_operations_delivery_token);
    perform public.seed_leghevo_operational_consumer_drain_v1(
      'production', 'notification_dispatch', 'leghevo-notification-consumer', 1,
      v_notification_consumer_token, v_notification_delivery_token);
    v_outcome := public.promote_leghevo_application_rollout_v4(
      'production', 85,
      '62380000-0000-4000-8000-000000000013'::uuid,
      'rollout.consumer_ack_promotion_85');
    perform public.seed_leghevo_operational_consumer_drain_v1(
      'production', 'operations_center', 'leghevo-operations-consumer', 1,
      v_operations_consumer_token, v_operations_delivery_token);
    perform public.seed_leghevo_operational_consumer_drain_v1(
      'production', 'notification_dispatch', 'leghevo-notification-consumer', 1,
      v_notification_consumer_token, v_notification_delivery_token);

    v_outcome := public.record_leghevo_authoritative_operational_window_v1(
      'production', 'leghevo-production-observer', 3, v_telemetry_token, 4,
      v_now - interval '10 minutes', v_now - interval '5 minutes',
      1000, 1, 0, 195,
      '62380000-0000-4000-8000-000000000014'::uuid,
      jsonb_build_object('seedStage', 85));
    perform public.seed_leghevo_operational_consumer_drain_v1(
      'production', 'operations_center', 'leghevo-operations-consumer', 1,
      v_operations_consumer_token, v_operations_delivery_token);
    perform public.seed_leghevo_operational_consumer_drain_v1(
      'production', 'notification_dispatch', 'leghevo-notification-consumer', 1,
      v_notification_consumer_token, v_notification_delivery_token);
    v_outcome := public.promote_leghevo_application_rollout_v4(
      'production', 100,
      '62380000-0000-4000-8000-000000000015'::uuid,
      'rollout.consumer_ack_completed');
    perform public.seed_leghevo_operational_consumer_drain_v1(
      'production', 'operations_center', 'leghevo-operations-consumer', 1,
      v_operations_consumer_token, v_operations_delivery_token);
    perform public.seed_leghevo_operational_consumer_drain_v1(
      'production', 'notification_dispatch', 'leghevo-notification-consumer', 1,
      v_notification_consumer_token, v_notification_delivery_token);

    v_outcome := public.record_leghevo_authoritative_operational_window_v1(
      'production', 'leghevo-production-observer', 3, v_telemetry_token, 5,
      v_now - interval '5 minutes', v_now,
      1000, 1, 0, 190,
      '62380000-0000-4000-8000-000000000016'::uuid,
      jsonb_build_object('seedStage', 100, 'postCompletion', true));
    perform public.seed_leghevo_operational_consumer_drain_v1(
      'production', 'operations_center', 'leghevo-operations-consumer', 1,
      v_operations_consumer_token, v_operations_delivery_token);
    perform public.seed_leghevo_operational_consumer_drain_v1(
      'production', 'notification_dispatch', 'leghevo-notification-consumer', 1,
      v_notification_consumer_token, v_notification_delivery_token);
  end if;

  v_outcome := public.reconcile_leghevo_operational_consumer_delivery_v1(
    'production', '62380000-0000-4000-8000-000000000017'::uuid);
end;
$seed_release$;

drop function if exists public.seed_leghevo_operational_consumer_drain_v1(
  text,text,text,bigint,uuid,uuid
);

-- Realtime espone soltanto gli eventi sanificati, mai token o payload.
do $realtime$
begin
  if exists (select 1 from pg_catalog.pg_publication p where p.pubname = 'supabase_realtime')
    and not exists (
      select 1 from pg_catalog.pg_publication_tables pt
      where pt.pubname = 'supabase_realtime'
        and pt.schemaname = 'public'
        and pt.tablename = 'leghevo_operational_consumer_events'
    ) then
    alter publication supabase_realtime
      add table public.leghevo_operational_consumer_events;
  end if;
end;
$realtime$;

create or replace function public.get_leghevo_operational_consumer_delivery_deployment_integrity_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_predecessor jsonb;
  v_predecessor_false text[];
  v_model jsonb;
  v_release jsonb;
  v_rollout jsonb;
  v_telemetry jsonb;
  v_certificate_mismatch bigint;
  v_receipt_mismatch bigint;
  v_event_mismatch bigint;
  v_certify_def text := coalesce(pg_catalog.pg_get_functiondef(
    to_regprocedure('public.certify_leghevo_operational_consumer_v1(text,text,text,bigint,uuid,uuid,jsonb)')), '');
  v_claim_def text := coalesce(pg_catalog.pg_get_functiondef(
    to_regprocedure('public.claim_leghevo_operational_outbox_v2(text,text,text,bigint,uuid,text,bigint,uuid,integer,integer)')), '');
  v_apply_def text := coalesce(pg_catalog.pg_get_functiondef(
    to_regprocedure('public.apply_leghevo_operational_consumer_message_v1(text,bigint,text,bigint,text,bigint,uuid,text,bigint,uuid,text,text,uuid,jsonb)')), '');
  v_replay_def text := coalesce(pg_catalog.pg_get_functiondef(
    to_regprocedure('public.request_leghevo_operational_consumer_replay_v1(text,text,bigint,uuid,text,jsonb)')), '');
  v_promote_def text := coalesce(pg_catalog.pg_get_functiondef(
    to_regprocedure('public.promote_leghevo_application_rollout_v4(text,integer,uuid,text)')), '');
begin
  v_predecessor := public.get_leghevo_operational_outbox_deployment_integrity_v1();
  select array_agg(item.key order by item.key) into v_predecessor_false
  from pg_catalog.jsonb_each(v_predecessor) item
  where pg_catalog.jsonb_typeof(item.value) is distinct from 'boolean'
     or item.value is distinct from 'true'::jsonb;

  v_model := public.get_leghevo_operational_consumer_delivery_model_v1('production');
  v_release := public.get_leghevo_application_release_model_v1('production');
  v_rollout := public.get_leghevo_application_rollout_model_v1('production');
  v_telemetry := public.get_leghevo_operational_telemetry_model_v1('production');

  select count(*) into v_certificate_mismatch
  from public.leghevo_operational_consumer_certificates certificate
  where certificate.certificate_fingerprint <>
    public.compute_leghevo_operational_consumer_certificate_fingerprint_v1(
      certificate.environment_key, certificate.destination_key,
      certificate.consumer_key, certificate.consumer_generation,
      certificate.fencing_token_hash, certificate.contract_version);
  select count(*) into v_receipt_mismatch
  from public.leghevo_operational_consumer_receipts receipt
  where receipt.receipt_fingerprint <>
    public.compute_leghevo_operational_consumer_receipt_fingerprint_v1(
      receipt.environment_key, receipt.message_id,
      receipt.destination_key, receipt.stream_sequence,
      receipt.message_fingerprint, receipt.consumer_id,
      receipt.consumer_generation, receipt.consumer_token_hash,
      receipt.application_key, receipt.application_fingerprint,
      receipt.receipt_signature, receipt.adoption_mode,
      receipt.contract_version);
  select count(*) into v_event_mismatch
  from public.leghevo_operational_consumer_events event
  where event.event_fingerprint <>
    public.compute_leghevo_operational_consumer_event_fingerprint_v1(
      event.environment_key, event.destination_key, event.event_type,
      event.generation, event.message_id, event.stream_sequence,
      event.consumer_id, event.receipt_id, event.reason_code,
      event.details);

  return jsonb_build_object(
    'predecessor_ready',
      (select count(*) = 20
       from pg_catalog.jsonb_each(v_predecessor))
      and coalesce(v_predecessor_false, array[]::text[]) = array[
        'claim_fencing_ready',
        'client_and_endpoint_chain_ready',
        'completion_and_dlq_ready',
        'seed_release_ready'
      ]::text[],
    'certificate_table_ready',
      to_regclass('public.leghevo_operational_consumer_certificates') is not null,
    'head_table_ready',
      to_regclass('public.leghevo_operational_consumer_heads') is not null,
    'receipt_table_ready',
      to_regclass('public.leghevo_operational_consumer_receipts') is not null,
    'event_table_ready',
      to_regclass('public.leghevo_operational_consumer_events') is not null,
    'columns_ready',
      (select count(*) = 10 from information_schema.columns c
       where c.table_schema = 'public'
         and c.table_name = 'leghevo_operational_consumer_certificates'
         and c.column_name in ('environment_key','destination_key','consumer_key',
           'consumer_generation','fencing_token_hash','request_id',
           'contract_version','certificate_fingerprint','details','certified_at'))
      and (select count(*) = 14 from information_schema.columns c
       where c.table_schema = 'public'
         and c.table_name = 'leghevo_operational_consumer_receipts'
         and c.column_name in ('request_id','environment_key','message_id',
           'destination_key','stream_sequence','message_fingerprint','consumer_id',
           'consumer_generation','consumer_token_hash','application_key',
           'application_fingerprint','receipt_signature','receipt_fingerprint',
           'adoption_mode')),
    'constraints_ready',
      exists (select 1 from pg_catalog.pg_constraint c
       where c.conrelid = 'public.leghevo_operational_consumer_receipts'::regclass
         and c.conname = 'leghevo_consumer_receipt_message_unique')
      and exists (select 1 from pg_catalog.pg_constraint c
       where c.conrelid = 'public.leghevo_operational_consumer_receipts'::regclass
         and c.conname = 'leghevo_consumer_receipt_sequence_unique')
      and exists (select 1 from pg_catalog.pg_constraint c
       where c.conrelid = 'public.leghevo_operational_consumer_heads'::regclass
         and c.conname = 'leghevo_consumer_head_last_receipt_fk'),
    'indexes_ready',
      to_regclass('public.leghevo_consumer_certificates_current_idx') is not null
      and to_regclass('public.leghevo_consumer_receipts_sequence_idx') is not null
      and to_regclass('public.leghevo_consumer_events_created_idx') is not null,
    'rls_ready',
      (select relrowsecurity from pg_catalog.pg_class
       where oid = 'public.leghevo_operational_consumer_certificates'::regclass)
      and (select relrowsecurity from pg_catalog.pg_class
       where oid = 'public.leghevo_operational_consumer_heads'::regclass)
      and (select relrowsecurity from pg_catalog.pg_class
       where oid = 'public.leghevo_operational_consumer_receipts'::regclass)
      and (select relrowsecurity from pg_catalog.pg_class
       where oid = 'public.leghevo_operational_consumer_events'::regclass),
    'direct_write_blocked',
      not has_table_privilege('authenticated','public.leghevo_operational_consumer_receipts','SELECT')
      and not has_table_privilege('service_role','public.leghevo_operational_consumer_certificates','INSERT')
      and not has_table_privilege('service_role','public.leghevo_operational_consumer_heads','UPDATE')
      and not has_table_privilege('service_role','public.leghevo_operational_consumer_receipts','INSERT')
      and not has_table_privilege('service_role','public.leghevo_operational_consumer_events','INSERT'),
    'immutable_records_ready',
      exists (select 1 from pg_catalog.pg_trigger t
       where t.tgrelid = 'public.leghevo_operational_consumer_certificates'::regclass
         and t.tgname = 'leghevo_consumer_certificates_guard'
         and t.tgenabled = 'A' and not t.tgisinternal)
      and exists (select 1 from pg_catalog.pg_trigger t
       where t.tgrelid = 'public.leghevo_operational_consumer_receipts'::regclass
         and t.tgname = 'leghevo_consumer_receipts_guard'
         and t.tgenabled = 'A' and not t.tgisinternal)
      and exists (select 1 from pg_catalog.pg_trigger t
       where t.tgrelid = 'public.leghevo_operational_consumer_events'::regclass
         and t.tgname = 'leghevo_consumer_events_guard'
         and t.tgenabled = 'A' and not t.tgisinternal),
    'head_guard_ready',
      exists (select 1 from pg_catalog.pg_trigger t
       where t.tgrelid = 'public.leghevo_operational_consumer_heads'::regclass
         and t.tgname = 'leghevo_consumer_heads_guard'
         and t.tgenabled = 'A' and not t.tgisinternal),
    'certificate_fingerprint_ready',
      v_certificate_mismatch = 0
      and position('pg_advisory_xact_lock' in v_certify_def) > 0
      and position('fencing_token_hash' in v_certify_def) > 0,
    'receipt_fingerprint_ready',
      v_receipt_mismatch = 0 and v_event_mismatch = 0
      and coalesce((v_model ->> 'fingerprintMismatchCount')::bigint, -1) = 0,
    'certification_rpc_ready',
      to_regprocedure('public.certify_leghevo_operational_consumer_v1(text,text,text,bigint,uuid,uuid,jsonb)') is not null
      and has_function_privilege('service_role',
        'public.certify_leghevo_operational_consumer_v1(text,text,text,bigint,uuid,uuid,jsonb)','EXECUTE'),
    'claim_and_apply_ready',
      to_regprocedure('public.claim_leghevo_operational_outbox_v2(text,text,text,bigint,uuid,text,bigint,uuid,integer,integer)') is not null
      and to_regprocedure('public.apply_leghevo_operational_consumer_message_v1(text,bigint,text,bigint,text,bigint,uuid,text,bigint,uuid,text,text,uuid,jsonb)') is not null
      and position('skip locked' in lower(v_claim_def)) > 0
      and position('last_stream_sequence + 1' in v_claim_def) > 0
      and position('last_stream_sequence + 1' in v_apply_def) > 0
      and position('complete_leghevo_operational_outbox_delivery_v1' in v_apply_def) > 0
      and has_function_privilege('service_role',
        'public.claim_leghevo_operational_outbox_v2(text,text,text,bigint,uuid,text,bigint,uuid,integer,integer)','EXECUTE')
      and has_function_privilege('service_role',
        'public.apply_leghevo_operational_consumer_message_v1(text,bigint,text,bigint,text,bigint,uuid,text,bigint,uuid,text,text,uuid,jsonb)','EXECUTE'),
    'replay_and_reconcile_ready',
      to_regprocedure('public.request_leghevo_operational_consumer_replay_v1(text,text,bigint,uuid,text,jsonb)') is not null
      and to_regprocedure('public.reconcile_leghevo_operational_consumer_delivery_v1(text,uuid)') is not null
      and position('replay_requested' in v_replay_def) > 0
      and has_function_privilege('service_role',
        'public.request_leghevo_operational_consumer_replay_v1(text,text,bigint,uuid,text,jsonb)','EXECUTE')
      and has_function_privilege('service_role',
        'public.reconcile_leghevo_operational_consumer_delivery_v1(text,uuid)','EXECUTE'),
    'legacy_bypass_blocked',
      not has_function_privilege('service_role',
        'public.claim_leghevo_operational_outbox_v1(text,text,text,bigint,uuid,integer,integer)','EXECUTE')
      and not has_function_privilege('service_role',
        'public.complete_leghevo_operational_outbox_delivery_v1(bigint,text,bigint,text,bigint,uuid,text,text,text,uuid,jsonb)','EXECUTE')
      and not has_function_privilege('service_role',
        'public.promote_leghevo_application_rollout_v3(text,integer,uuid,text)','EXECUTE')
      and has_function_privilege('service_role',
        'public.promote_leghevo_application_rollout_v4(text,integer,uuid,text)','EXECUTE')
      and position('get_leghevo_operational_consumer_delivery_model_v1' in v_promote_def) > 0,
    'endpoint_and_realtime_ready',
      to_regprocedure('public.get_leghevo_client_rollout_eligibility_v4(text,text,uuid)') is not null
      and has_function_privilege('anon',
        'public.get_leghevo_client_rollout_eligibility_v4(text,text,uuid)','EXECUTE')
      and has_function_privilege('authenticated',
        'public.get_leghevo_client_rollout_eligibility_v4(text,text,uuid)','EXECUTE')
      and to_regprocedure('public.get_league_provider_sync_health_v37(uuid)') is not null
      and to_regprocedure('public.get_league_season_state_v16(uuid)') is not null
      and to_regprocedure('public.get_league_management_state_v26(uuid)') is not null
      and has_function_privilege('authenticated',
        'public.get_league_provider_sync_health_v37(uuid)','EXECUTE')
      and (
        not exists (select 1 from pg_catalog.pg_publication p
          where p.pubname = 'supabase_realtime')
        or exists (select 1 from pg_catalog.pg_publication_tables pt
          where pt.pubname = 'supabase_realtime'
            and pt.schemaname = 'public'
            and pt.tablename = 'leghevo_operational_consumer_events')
      ),
    'seed_delivery_ready',
      coalesce((v_release ->> 'protected')::boolean, false)
      and v_release ->> 'activeVersion' = '0.62.38'
      and coalesce((v_rollout ->> 'protected')::boolean, false)
      and v_rollout ->> 'status' = 'completed'
      and coalesce((v_rollout ->> 'exposurePercentage')::integer, 0) = 100
      and coalesce((v_telemetry ->> 'protected')::boolean, false)
      and coalesce((v_telemetry ->> 'healthy')::boolean, false)
      and coalesce((v_telemetry ->> 'sourceGeneration')::bigint, 0) = 3
      and v_telemetry ->> 'latestReleaseVersion' = '0.62.38'
      and coalesce((v_model ->> 'protected')::boolean, false)
      and coalesce((v_model ->> 'healthy')::boolean, false)
      and v_model ->> 'status' = 'active'
      and coalesce((v_model ->> 'consumerCount')::bigint, 0) = 2
      and coalesce((v_model ->> 'receiptCount')::bigint, 0) =
        coalesce((v_model ->> 'expectedReceiptCount')::bigint, -1)
      and coalesce((v_model ->> 'liveReceiptCount')::bigint, 0) > 0
      and coalesce((v_model ->> 'adoptedReceiptCount')::bigint, 0) > 0
      and coalesce((v_model ->> 'lastAcknowledgedSequence')::bigint, 0) =
        coalesce((public.get_leghevo_operational_outbox_model_v1('production') ->> 'lastSequence')::bigint, -1)
      and exists (select 1 from public.leghevo_application_release_certificates c
        where c.application_version = '0.62.38'
          and c.bundle_fingerprint = '0cd5a31e020b59673a72d52b2b7c3ab181038c135da711e8c96fff92ba111e28')
      and to_regprocedure('public.seed_leghevo_operational_consumer_drain_v1(text,text,text,bigint,uuid,uuid)') is null
  );
end;
$function$;

revoke all on function public.get_leghevo_operational_consumer_delivery_deployment_integrity_v1()
from public, anon, authenticated;
grant execute on function public.get_leghevo_operational_consumer_delivery_deployment_integrity_v1()
to service_role;

do $validation$
declare
  v_integrity jsonb;
  v_false text[];
begin
  v_integrity := public.get_leghevo_operational_consumer_delivery_deployment_integrity_v1();
  select array_agg(item.key order by item.key) into v_false
  from pg_catalog.jsonb_each(v_integrity) item
  where pg_catalog.jsonb_typeof(item.value) is distinct from 'boolean'
     or item.value is distinct from 'true'::jsonb;

  if (select count(*) from pg_catalog.jsonb_each(v_integrity)) <> 20
    or cardinality(v_false) > 0 then
    raise exception 'Validazione v0.62.38 non superata: %. Dettaglio: %',
      coalesce(array_to_string(v_false, ', '), 'numero controlli diverso da 20'),
      v_integrity;
  end if;
end;
$validation$;

commit;

select
  (public.get_leghevo_operational_consumer_delivery_deployment_integrity_v1()->>'predecessor_ready')::boolean as predecessor_ready,
  (public.get_leghevo_operational_consumer_delivery_deployment_integrity_v1()->>'certificate_table_ready')::boolean as certificate_table_ready,
  (public.get_leghevo_operational_consumer_delivery_deployment_integrity_v1()->>'head_table_ready')::boolean as head_table_ready,
  (public.get_leghevo_operational_consumer_delivery_deployment_integrity_v1()->>'receipt_table_ready')::boolean as receipt_table_ready,
  (public.get_leghevo_operational_consumer_delivery_deployment_integrity_v1()->>'event_table_ready')::boolean as event_table_ready,
  (public.get_leghevo_operational_consumer_delivery_deployment_integrity_v1()->>'columns_ready')::boolean as columns_ready,
  (public.get_leghevo_operational_consumer_delivery_deployment_integrity_v1()->>'constraints_ready')::boolean as constraints_ready,
  (public.get_leghevo_operational_consumer_delivery_deployment_integrity_v1()->>'indexes_ready')::boolean as indexes_ready,
  (public.get_leghevo_operational_consumer_delivery_deployment_integrity_v1()->>'rls_ready')::boolean as rls_ready,
  (public.get_leghevo_operational_consumer_delivery_deployment_integrity_v1()->>'direct_write_blocked')::boolean as direct_write_blocked,
  (public.get_leghevo_operational_consumer_delivery_deployment_integrity_v1()->>'immutable_records_ready')::boolean as immutable_records_ready,
  (public.get_leghevo_operational_consumer_delivery_deployment_integrity_v1()->>'head_guard_ready')::boolean as head_guard_ready,
  (public.get_leghevo_operational_consumer_delivery_deployment_integrity_v1()->>'certificate_fingerprint_ready')::boolean as certificate_fingerprint_ready,
  (public.get_leghevo_operational_consumer_delivery_deployment_integrity_v1()->>'receipt_fingerprint_ready')::boolean as receipt_fingerprint_ready,
  (public.get_leghevo_operational_consumer_delivery_deployment_integrity_v1()->>'certification_rpc_ready')::boolean as certification_rpc_ready,
  (public.get_leghevo_operational_consumer_delivery_deployment_integrity_v1()->>'claim_and_apply_ready')::boolean as claim_and_apply_ready,
  (public.get_leghevo_operational_consumer_delivery_deployment_integrity_v1()->>'replay_and_reconcile_ready')::boolean as replay_and_reconcile_ready,
  (public.get_leghevo_operational_consumer_delivery_deployment_integrity_v1()->>'legacy_bypass_blocked')::boolean as legacy_bypass_blocked,
  (public.get_leghevo_operational_consumer_delivery_deployment_integrity_v1()->>'endpoint_and_realtime_ready')::boolean as endpoint_and_realtime_ready,
  (public.get_leghevo_operational_consumer_delivery_deployment_integrity_v1()->>'seed_delivery_ready')::boolean as seed_delivery_ready;
