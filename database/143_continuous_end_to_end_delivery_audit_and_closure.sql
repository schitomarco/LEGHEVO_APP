-- LEGHEVO v0.62.39
-- Audit continuo end-to-end, attestazioni immutabili e chiusura certificata della catena operativa
-- Dipendenza: v0.62.38 validata con 20/20 controlli true.

begin;

do $preflight$
declare
  v_integrity jsonb;
  v_false text[];
begin
  if to_regprocedure('public.get_leghevo_operational_delivery_audit_deployment_integrity_v1()') is not null
    and exists (
      select 1 from public.leghevo_application_release_certificates c
      where c.application_version = '0.62.39'
    ) then
    return;
  end if;

  if to_regprocedure('public.get_leghevo_operational_consumer_delivery_deployment_integrity_v1()') is null then
    raise exception 'Preflight v0.62.39 non superato: diagnostica v0.62.38 assente.';
  end if;

  v_integrity := public.get_leghevo_operational_consumer_delivery_deployment_integrity_v1();
  select array_agg(item.key order by item.key) into v_false
  from pg_catalog.jsonb_each(v_integrity) item
  where pg_catalog.jsonb_typeof(item.value) is distinct from 'boolean'
     or item.value is distinct from 'true'::jsonb;

  if (select count(*) from pg_catalog.jsonb_each(v_integrity)) <> 20
    or cardinality(v_false) > 0 then
    raise exception 'Preflight v0.62.39 non superato: %. Dettaglio: %',
      coalesce(array_to_string(v_false, ', '), 'numero controlli diverso da 20'),
      v_integrity;
  end if;
end;
$preflight$;

create or replace function public.compute_leghevo_operational_delivery_audit_run_fingerprint_v1(
  p_environment_key text,
  p_audit_generation bigint,
  p_audited_through_sequence bigint,
  p_message_count bigint,
  p_expected_delivery_count bigint,
  p_delivery_count bigint,
  p_receipt_count bigint,
  p_sequence_gap_count bigint,
  p_consistency_mismatch_count bigint,
  p_fingerprint_mismatch_count bigint,
  p_head_mismatch_count bigint,
  p_dead_letter_count bigint,
  p_status text,
  p_contract_version integer default 1
)
returns text
language sql
immutable
security definer
set search_path = ''
as $function$
  select public.leghevo_sha256_hex_v1(
    coalesce(lower(trim(p_environment_key)), '') || '|' ||
    coalesce(p_audit_generation, 0)::text || '|' ||
    coalesce(p_audited_through_sequence, 0)::text || '|' ||
    coalesce(p_message_count, 0)::text || '|' ||
    coalesce(p_expected_delivery_count, 0)::text || '|' ||
    coalesce(p_delivery_count, 0)::text || '|' ||
    coalesce(p_receipt_count, 0)::text || '|' ||
    coalesce(p_sequence_gap_count, 0)::text || '|' ||
    coalesce(p_consistency_mismatch_count, 0)::text || '|' ||
    coalesce(p_fingerprint_mismatch_count, 0)::text || '|' ||
    coalesce(p_head_mismatch_count, 0)::text || '|' ||
    coalesce(p_dead_letter_count, 0)::text || '|' ||
    coalesce(lower(trim(p_status)), '') || '|' ||
    coalesce(p_contract_version, 0)::text
  );
$function$;

create or replace function public.compute_leghevo_operational_delivery_attestation_fingerprint_v1(
  p_run_id bigint,
  p_environment_key text,
  p_destination_key text,
  p_expected_sequence bigint,
  p_acknowledged_sequence bigint,
  p_message_count bigint,
  p_delivery_count bigint,
  p_receipt_count bigint,
  p_mismatch_count bigint,
  p_receipt_chain_fingerprint text,
  p_status text,
  p_reason_code text,
  p_contract_version integer default 1
)
returns text
language sql
immutable
security definer
set search_path = ''
as $function$
  select public.leghevo_sha256_hex_v1(
    coalesce(p_run_id, 0)::text || '|' ||
    coalesce(lower(trim(p_environment_key)), '') || '|' ||
    coalesce(lower(trim(p_destination_key)), '') || '|' ||
    coalesce(p_expected_sequence, 0)::text || '|' ||
    coalesce(p_acknowledged_sequence, 0)::text || '|' ||
    coalesce(p_message_count, 0)::text || '|' ||
    coalesce(p_delivery_count, 0)::text || '|' ||
    coalesce(p_receipt_count, 0)::text || '|' ||
    coalesce(p_mismatch_count, 0)::text || '|' ||
    coalesce(lower(trim(p_receipt_chain_fingerprint)), '') || '|' ||
    coalesce(lower(trim(p_status)), '') || '|' ||
    coalesce(lower(trim(p_reason_code)), '') || '|' ||
    coalesce(p_contract_version, 0)::text
  );
$function$;

create or replace function public.compute_leghevo_operational_delivery_audit_event_fingerprint_v1(
  p_environment_key text,
  p_destination_key text,
  p_event_type text,
  p_generation bigint,
  p_run_id bigint,
  p_attestation_id bigint,
  p_remediation_id bigint,
  p_reason_code text,
  p_details jsonb
)
returns text
language sql
immutable
security definer
set search_path = ''
as $function$
  select public.leghevo_sha256_hex_v1(
    coalesce(lower(trim(p_environment_key)), '') || '|' ||
    coalesce(lower(trim(p_destination_key)), '') || '|' ||
    coalesce(lower(trim(p_event_type)), '') || '|' ||
    coalesce(p_generation, 0)::text || '|' ||
    coalesce(p_run_id, 0)::text || '|' ||
    coalesce(p_attestation_id, 0)::text || '|' ||
    coalesce(p_remediation_id, 0)::text || '|' ||
    coalesce(lower(trim(p_reason_code)), '') || '|' ||
    coalesce(p_details, '{}'::jsonb)::text
  );
$function$;

create table if not exists public.leghevo_operational_delivery_audit_runs (
  id bigint generated by default as identity primary key,
  environment_key text not null,
  audit_generation bigint not null,
  request_id uuid not null unique,
  audited_through_sequence bigint not null,
  message_count bigint not null,
  expected_delivery_count bigint not null,
  delivery_count bigint not null,
  receipt_count bigint not null,
  sequence_gap_count bigint not null,
  consistency_mismatch_count bigint not null,
  fingerprint_mismatch_count bigint not null,
  head_mismatch_count bigint not null,
  dead_letter_count bigint not null,
  status text not null,
  reason_code text not null,
  contract_version integer not null default 1,
  run_fingerprint text not null unique,
  details jsonb not null default '{}'::jsonb,
  started_at timestamptz not null,
  completed_at timestamptz not null default now(),
  created_by uuid null,
  constraint leghevo_delivery_audit_run_environment_check
    check (environment_key in ('production','staging')),
  constraint leghevo_delivery_audit_run_generation_check
    check (audit_generation >= 1),
  constraint leghevo_delivery_audit_run_sequence_check
    check (audited_through_sequence >= 0),
  constraint leghevo_delivery_audit_run_counts_check
    check (
      message_count >= 0 and expected_delivery_count >= 0
      and delivery_count >= 0 and receipt_count >= 0
      and sequence_gap_count >= 0 and consistency_mismatch_count >= 0
      and fingerprint_mismatch_count >= 0 and head_mismatch_count >= 0
      and dead_letter_count >= 0
    ),
  constraint leghevo_delivery_audit_run_status_check
    check (status in ('certified','affected')),
  constraint leghevo_delivery_audit_run_reason_check
    check (char_length(trim(reason_code)) between 3 and 160),
  constraint leghevo_delivery_audit_run_contract_check
    check (contract_version >= 1),
  constraint leghevo_delivery_audit_run_fingerprint_check
    check (run_fingerprint ~ '^[0-9a-f]{64}$'),
  constraint leghevo_delivery_audit_run_details_check
    check (jsonb_typeof(details) = 'object'),
  constraint leghevo_delivery_audit_run_time_check
    check (completed_at >= started_at),
  constraint leghevo_delivery_audit_run_generation_unique
    unique (environment_key, audit_generation)
);

create table if not exists public.leghevo_operational_delivery_audit_attestations (
  id bigint generated by default as identity primary key,
  run_id bigint not null references public.leghevo_operational_delivery_audit_runs(id) on delete restrict,
  environment_key text not null,
  destination_key text not null,
  expected_sequence bigint not null,
  acknowledged_sequence bigint not null,
  message_count bigint not null,
  delivery_count bigint not null,
  receipt_count bigint not null,
  mismatch_count bigint not null,
  receipt_chain_fingerprint text not null,
  status text not null,
  reason_code text not null,
  contract_version integer not null default 1,
  attestation_fingerprint text not null unique,
  details jsonb not null default '{}'::jsonb,
  attested_at timestamptz not null default now(),
  created_by uuid null,
  constraint leghevo_delivery_attestation_environment_check
    check (environment_key in ('production','staging')),
  constraint leghevo_delivery_attestation_destination_check
    check (destination_key in ('operations_center','notification_dispatch')),
  constraint leghevo_delivery_attestation_sequence_check
    check (expected_sequence >= 0 and acknowledged_sequence >= 0),
  constraint leghevo_delivery_attestation_counts_check
    check (message_count >= 0 and delivery_count >= 0 and receipt_count >= 0 and mismatch_count >= 0),
  constraint leghevo_delivery_attestation_chain_check
    check (receipt_chain_fingerprint ~ '^[0-9a-f]{64}$'),
  constraint leghevo_delivery_attestation_status_check
    check (status in ('certified','affected')),
  constraint leghevo_delivery_attestation_reason_check
    check (char_length(trim(reason_code)) between 3 and 160),
  constraint leghevo_delivery_attestation_contract_check
    check (contract_version >= 1),
  constraint leghevo_delivery_attestation_fingerprint_check
    check (attestation_fingerprint ~ '^[0-9a-f]{64}$'),
  constraint leghevo_delivery_attestation_details_check
    check (jsonb_typeof(details) = 'object'),
  constraint leghevo_delivery_attestation_run_destination_unique
    unique (run_id, destination_key),
  constraint leghevo_delivery_attestation_identity_unique
    unique (id, run_id, destination_key)
);

create table if not exists public.leghevo_operational_delivery_audit_heads (
  environment_key text not null,
  destination_key text not null,
  generation bigint not null default 1,
  latest_run_id bigint not null references public.leghevo_operational_delivery_audit_runs(id) on delete restrict,
  latest_attestation_id bigint not null,
  state text not null,
  audited_through_sequence bigint not null,
  affected_reason text null,
  last_request_id uuid not null,
  updated_at timestamptz not null default now(),
  primary key (environment_key, destination_key),
  constraint leghevo_delivery_audit_head_destination_check
    check (destination_key in ('operations_center','notification_dispatch')),
  constraint leghevo_delivery_audit_head_environment_check
    check (environment_key in ('production','staging')),
  constraint leghevo_delivery_audit_head_generation_check
    check (generation >= 1 and audited_through_sequence >= 0),
  constraint leghevo_delivery_audit_head_state_check
    check (state in ('certified','affected')),
  constraint leghevo_delivery_audit_head_reason_check
    check (
      (state = 'affected' and char_length(trim(affected_reason)) between 3 and 160)
      or (state = 'certified' and affected_reason is null)
    )
);

create table if not exists public.leghevo_operational_delivery_audit_remediations (
  id bigint generated by default as identity primary key,
  request_id uuid not null unique,
  environment_key text not null,
  destination_key text not null,
  audit_run_id bigint not null references public.leghevo_operational_delivery_audit_runs(id) on delete restrict,
  remediation_type text not null,
  reason_code text not null,
  status text not null default 'requested',
  remediation_fingerprint text not null unique,
  details jsonb not null default '{}'::jsonb,
  requested_at timestamptz not null default now(),
  requested_by uuid null,
  constraint leghevo_delivery_remediation_environment_check
    check (environment_key in ('production','staging')),
  constraint leghevo_delivery_remediation_destination_check
    check (destination_key in ('operations_center','notification_dispatch')),
  constraint leghevo_delivery_remediation_type_check
    check (remediation_type in ('replay_review','quarantine','manual_investigation')),
  constraint leghevo_delivery_remediation_reason_check
    check (char_length(trim(reason_code)) between 3 and 160),
  constraint leghevo_delivery_remediation_status_check
    check (status = 'requested'),
  constraint leghevo_delivery_remediation_fingerprint_check
    check (remediation_fingerprint ~ '^[0-9a-f]{64}$'),
  constraint leghevo_delivery_remediation_details_check
    check (jsonb_typeof(details) = 'object')
);

create table if not exists public.leghevo_operational_delivery_audit_events (
  id bigint generated by default as identity primary key,
  environment_key text not null,
  destination_key text not null,
  request_id uuid not null,
  event_type text not null,
  generation bigint not null,
  run_id bigint not null references public.leghevo_operational_delivery_audit_runs(id) on delete restrict,
  attestation_id bigint null references public.leghevo_operational_delivery_audit_attestations(id) on delete restrict,
  remediation_id bigint null references public.leghevo_operational_delivery_audit_remediations(id) on delete restrict,
  reason_code text not null,
  event_fingerprint text not null unique,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  created_by uuid null,
  constraint leghevo_delivery_audit_event_environment_check
    check (environment_key in ('production','staging')),
  constraint leghevo_delivery_audit_event_destination_check
    check (destination_key in ('operations_center','notification_dispatch')),
  constraint leghevo_delivery_audit_event_type_check
    check (event_type in ('attested','affected','revalidated','remediation_requested')),
  constraint leghevo_delivery_audit_event_generation_check
    check (generation >= 1),
  constraint leghevo_delivery_audit_event_reason_check
    check (char_length(trim(reason_code)) between 3 and 160),
  constraint leghevo_delivery_audit_event_fingerprint_check
    check (event_fingerprint ~ '^[0-9a-f]{64}$'),
  constraint leghevo_delivery_audit_event_details_check
    check (jsonb_typeof(details) = 'object'),
  constraint leghevo_delivery_audit_event_request_unique
    unique (environment_key, destination_key, request_id, event_type)
);

alter table public.leghevo_operational_delivery_audit_heads
  drop constraint if exists leghevo_delivery_audit_head_attestation_fk;
alter table public.leghevo_operational_delivery_audit_heads
  add constraint leghevo_delivery_audit_head_attestation_fk
  foreign key (latest_attestation_id, latest_run_id, destination_key)
  references public.leghevo_operational_delivery_audit_attestations(id, run_id, destination_key)
  on delete restrict;

create index if not exists leghevo_delivery_audit_runs_environment_generation_idx
on public.leghevo_operational_delivery_audit_runs(environment_key, audit_generation desc, id desc);
create index if not exists leghevo_delivery_audit_attestations_destination_idx
on public.leghevo_operational_delivery_audit_attestations(environment_key, destination_key, attested_at desc, id desc);
create index if not exists leghevo_delivery_audit_remediations_created_idx
on public.leghevo_operational_delivery_audit_remediations(environment_key, requested_at desc, id desc);
create index if not exists leghevo_delivery_audit_events_created_idx
on public.leghevo_operational_delivery_audit_events(environment_key, destination_key, created_at desc, id desc);

alter table public.leghevo_operational_delivery_audit_runs enable row level security;
alter table public.leghevo_operational_delivery_audit_attestations enable row level security;
alter table public.leghevo_operational_delivery_audit_heads enable row level security;
alter table public.leghevo_operational_delivery_audit_remediations enable row level security;
alter table public.leghevo_operational_delivery_audit_events enable row level security;
alter table public.leghevo_operational_delivery_audit_events replica identity full;

revoke all on table public.leghevo_operational_delivery_audit_runs from public, anon, authenticated, service_role;
revoke all on table public.leghevo_operational_delivery_audit_attestations from public, anon, authenticated, service_role;
revoke all on table public.leghevo_operational_delivery_audit_heads from public, anon, authenticated, service_role;
revoke all on table public.leghevo_operational_delivery_audit_remediations from public, anon, authenticated, service_role;
revoke all on table public.leghevo_operational_delivery_audit_events from public, anon, authenticated, service_role;
grant select on table public.leghevo_operational_delivery_audit_events to authenticated;

drop policy if exists leghevo_delivery_audit_events_authenticated_read
on public.leghevo_operational_delivery_audit_events;
create policy leghevo_delivery_audit_events_authenticated_read
on public.leghevo_operational_delivery_audit_events
for select to authenticated using (true);

create or replace function public.guard_leghevo_operational_delivery_audit_immutable_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if current_setting('leghevo.delivery_audit_context', true) <> 'allowed' then
    raise exception 'Record audit operativo immutabile: scrittura diretta vietata.';
  end if;
  if tg_op in ('UPDATE','DELETE') then
    raise exception 'Record audit operativo append-only: modifica o cancellazione vietata.';
  end if;
  return new;
end;
$function$;

create or replace function public.guard_leghevo_operational_delivery_audit_head_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if current_setting('leghevo.delivery_audit_context', true) <> 'allowed' then
    raise exception 'Testa audit operativo protetta: scrittura diretta vietata.';
  end if;
  if tg_op = 'DELETE' then
    raise exception 'Testa audit operativo non cancellabile.';
  end if;
  if tg_op = 'UPDATE' then
    if new.generation <= old.generation
      or new.audited_through_sequence < old.audited_through_sequence then
      raise exception 'Regressione della testa audit operativo vietata.';
    end if;
  end if;
  return new;
end;
$function$;

revoke all on function public.guard_leghevo_operational_delivery_audit_immutable_v1() from public, anon, authenticated, service_role;
revoke all on function public.guard_leghevo_operational_delivery_audit_head_v1() from public, anon, authenticated, service_role;

drop trigger if exists leghevo_delivery_audit_runs_guard on public.leghevo_operational_delivery_audit_runs;
create trigger leghevo_delivery_audit_runs_guard
before insert or update or delete on public.leghevo_operational_delivery_audit_runs
for each row execute function public.guard_leghevo_operational_delivery_audit_immutable_v1();
alter table public.leghevo_operational_delivery_audit_runs enable always trigger leghevo_delivery_audit_runs_guard;

drop trigger if exists leghevo_delivery_audit_attestations_guard on public.leghevo_operational_delivery_audit_attestations;
create trigger leghevo_delivery_audit_attestations_guard
before insert or update or delete on public.leghevo_operational_delivery_audit_attestations
for each row execute function public.guard_leghevo_operational_delivery_audit_immutable_v1();
alter table public.leghevo_operational_delivery_audit_attestations enable always trigger leghevo_delivery_audit_attestations_guard;

drop trigger if exists leghevo_delivery_audit_remediations_guard on public.leghevo_operational_delivery_audit_remediations;
create trigger leghevo_delivery_audit_remediations_guard
before insert or update or delete on public.leghevo_operational_delivery_audit_remediations
for each row execute function public.guard_leghevo_operational_delivery_audit_immutable_v1();
alter table public.leghevo_operational_delivery_audit_remediations enable always trigger leghevo_delivery_audit_remediations_guard;

drop trigger if exists leghevo_delivery_audit_events_guard on public.leghevo_operational_delivery_audit_events;
create trigger leghevo_delivery_audit_events_guard
before insert or update or delete on public.leghevo_operational_delivery_audit_events
for each row execute function public.guard_leghevo_operational_delivery_audit_immutable_v1();
alter table public.leghevo_operational_delivery_audit_events enable always trigger leghevo_delivery_audit_events_guard;

drop trigger if exists leghevo_delivery_audit_heads_guard on public.leghevo_operational_delivery_audit_heads;
create trigger leghevo_delivery_audit_heads_guard
before insert or update or delete on public.leghevo_operational_delivery_audit_heads
for each row execute function public.guard_leghevo_operational_delivery_audit_head_v1();
alter table public.leghevo_operational_delivery_audit_heads enable always trigger leghevo_delivery_audit_heads_guard;

create or replace function public.run_leghevo_operational_delivery_audit_v1(
  p_environment_key text,
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
  v_details jsonb := coalesce(p_details, '{}'::jsonb);
  v_existing public.leghevo_operational_delivery_audit_runs%rowtype;
  v_previous_run public.leghevo_operational_delivery_audit_runs%rowtype;
  v_run public.leghevo_operational_delivery_audit_runs%rowtype;
  v_outbox jsonb;
  v_consumer jsonb;
  v_generation bigint;
  v_last_sequence bigint := 0;
  v_message_count bigint := 0;
  v_expected_delivery_count bigint := 0;
  v_delivery_count bigint := 0;
  v_receipt_count bigint := 0;
  v_sequence_gap_count bigint := 0;
  v_consistency_mismatch_count bigint := 0;
  v_fingerprint_mismatch_count bigint := 0;
  v_head_mismatch_count bigint := 0;
  v_dead_letter_count bigint := 0;
  v_status text;
  v_reason text;
  v_run_fingerprint text;
  v_started_at timestamptz := clock_timestamp();
  v_destination text;
  v_destination_delivery_count bigint;
  v_destination_receipt_count bigint;
  v_destination_ack_sequence bigint;
  v_destination_mismatch_count bigint;
  v_receipt_chain_fingerprint text;
  v_attestation_status text;
  v_attestation_reason text;
  v_attestation_fingerprint text;
  v_attestation public.leghevo_operational_delivery_audit_attestations%rowtype;
  v_head public.leghevo_operational_delivery_audit_heads%rowtype;
  v_head_generation bigint;
  v_event_type text;
  v_event_fingerprint text;
begin
  if v_environment not in ('production','staging')
    or p_request_id is null
    or jsonb_typeof(v_details) is distinct from 'object' then
    raise exception 'Audit operativo end-to-end non valido.';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('leghevo:operational-delivery-audit:' || v_environment, 0));

  select run.* into v_existing
  from public.leghevo_operational_delivery_audit_runs run
  where run.request_id = p_request_id;
  if found then
    if v_existing.environment_key <> v_environment then
      raise exception 'request_id già utilizzato per un ambiente audit diverso.';
    end if;
    return public.get_leghevo_operational_delivery_audit_model_v1(v_environment);
  end if;

  select run.* into v_previous_run
  from public.leghevo_operational_delivery_audit_runs run
  where run.environment_key = v_environment
  order by run.audit_generation desc, run.id desc
  limit 1
  for update;
  v_generation := coalesce(v_previous_run.audit_generation, 0) + 1;

  v_outbox := public.get_leghevo_operational_outbox_model_v1(v_environment);
  v_consumer := public.get_leghevo_operational_consumer_delivery_model_v1(v_environment);
  v_last_sequence := coalesce((v_outbox ->> 'lastSequence')::bigint, 0);

  select count(*) into v_message_count
  from public.leghevo_operational_outbox_messages message
  where message.environment_key = v_environment;
  v_expected_delivery_count := v_message_count * 2;

  select count(*) into v_delivery_count
  from public.leghevo_operational_outbox_delivery_heads delivery
  join public.leghevo_operational_outbox_messages message on message.id = delivery.message_id
  where message.environment_key = v_environment;

  select count(*) into v_receipt_count
  from public.leghevo_operational_consumer_receipts receipt
  where receipt.environment_key = v_environment;

  select count(*) into v_dead_letter_count
  from public.leghevo_operational_outbox_dead_letters dead_letter
  join public.leghevo_operational_outbox_messages message on message.id = dead_letter.message_id
  where message.environment_key = v_environment;

  select coalesce(sum(greatest(v_last_sequence - destination_counts.receipt_count, 0)), 0)
  into v_sequence_gap_count
  from (
    select destination_values.destination_key as destination_key,
           count(receipt.id) as receipt_count
    from (values ('operations_center'::text), ('notification_dispatch'::text))
      destination_values(destination_key)
    left join public.leghevo_operational_consumer_receipts receipt
      on receipt.environment_key = v_environment
     and receipt.destination_key = destination_values.destination_key
    group by destination_values.destination_key
  ) destination_counts;

  select count(*) into v_fingerprint_mismatch_count
  from public.leghevo_operational_consumer_receipts receipt
  where receipt.environment_key = v_environment
    and receipt.receipt_fingerprint <>
      public.compute_leghevo_operational_consumer_receipt_fingerprint_v1(
        receipt.environment_key, receipt.message_id, receipt.destination_key,
        receipt.stream_sequence, receipt.message_fingerprint, receipt.consumer_id,
        receipt.consumer_generation, receipt.consumer_token_hash,
        receipt.application_key, receipt.application_fingerprint,
        receipt.receipt_signature, receipt.adoption_mode, receipt.contract_version);

  select count(*) into v_consistency_mismatch_count
  from (
    select message.id, destination.destination_key
    from public.leghevo_operational_outbox_messages message
    cross join (values ('operations_center'::text), ('notification_dispatch'::text)) destination(destination_key)
    left join public.leghevo_operational_outbox_delivery_heads delivery
      on delivery.message_id = message.id and delivery.destination_key = destination.destination_key
    left join public.leghevo_operational_consumer_receipts receipt
      on receipt.message_id = message.id and receipt.destination_key = destination.destination_key
    where message.environment_key = v_environment
      and (
        delivery.message_id is null
        or delivery.state <> 'delivered'
        or receipt.id is null
        or receipt.environment_key <> message.environment_key
        or receipt.stream_sequence <> message.stream_sequence
        or receipt.message_fingerprint <> message.message_fingerprint
      )
  ) mismatch;

  select count(*) into v_head_mismatch_count
  from (values ('operations_center'::text), ('notification_dispatch'::text)) destination(destination_key)
  left join public.leghevo_operational_consumer_heads head
    on head.environment_key = v_environment
   and head.destination_key = destination.destination_key
  where head.environment_key is null
     or head.state <> 'active'
     or head.last_stream_sequence <> v_last_sequence;

  v_status := case
    when coalesce((v_outbox ->> 'protected')::boolean, false)
      and coalesce((v_outbox ->> 'healthy')::boolean, false)
      and coalesce((v_consumer ->> 'protected')::boolean, false)
      and coalesce((v_consumer ->> 'healthy')::boolean, false)
      and v_delivery_count = v_expected_delivery_count
      and v_receipt_count = v_expected_delivery_count
      and v_sequence_gap_count = 0
      and v_consistency_mismatch_count = 0
      and v_fingerprint_mismatch_count = 0
      and v_head_mismatch_count = 0
      and v_dead_letter_count = 0
      then 'certified'
    else 'affected'
  end;
  v_reason := case
    when not coalesce((v_outbox ->> 'protected')::boolean, false) then 'delivery_audit.outbox_not_protected'
    when not coalesce((v_consumer ->> 'protected')::boolean, false) then 'delivery_audit.consumer_not_protected'
    when v_dead_letter_count > 0 then 'delivery_audit.dead_letter_present'
    when v_fingerprint_mismatch_count > 0 then 'delivery_audit.fingerprint_mismatch'
    when v_consistency_mismatch_count > 0 then 'delivery_audit.delivery_consistency_mismatch'
    when v_sequence_gap_count > 0 then 'delivery_audit.sequence_gap'
    when v_head_mismatch_count > 0 then 'delivery_audit.head_mismatch'
    when v_delivery_count <> v_expected_delivery_count then 'delivery_audit.delivery_count_mismatch'
    when v_receipt_count <> v_expected_delivery_count then 'delivery_audit.receipt_count_mismatch'
    else 'delivery_audit.certified'
  end;

  v_run_fingerprint := public.compute_leghevo_operational_delivery_audit_run_fingerprint_v1(
    v_environment, v_generation, v_last_sequence, v_message_count,
    v_expected_delivery_count, v_delivery_count, v_receipt_count,
    v_sequence_gap_count, v_consistency_mismatch_count,
    v_fingerprint_mismatch_count, v_head_mismatch_count,
    v_dead_letter_count, v_status, 1);

  perform set_config('leghevo.delivery_audit_context', 'allowed', true);
  insert into public.leghevo_operational_delivery_audit_runs(
    environment_key, audit_generation, request_id, audited_through_sequence,
    message_count, expected_delivery_count, delivery_count, receipt_count,
    sequence_gap_count, consistency_mismatch_count, fingerprint_mismatch_count,
    head_mismatch_count, dead_letter_count, status, reason_code,
    contract_version, run_fingerprint, details, started_at, completed_at, created_by
  ) values (
    v_environment, v_generation, p_request_id, v_last_sequence,
    v_message_count, v_expected_delivery_count, v_delivery_count, v_receipt_count,
    v_sequence_gap_count, v_consistency_mismatch_count, v_fingerprint_mismatch_count,
    v_head_mismatch_count, v_dead_letter_count, v_status, v_reason,
    1, v_run_fingerprint, v_details, v_started_at, clock_timestamp(), auth.uid()
  ) returning * into v_run;

  foreach v_destination in array array['operations_center','notification_dispatch']::text[]
  loop
    select count(delivery.message_id), count(receipt.id), coalesce(max(receipt.stream_sequence), 0)
    into v_destination_delivery_count, v_destination_receipt_count, v_destination_ack_sequence
    from public.leghevo_operational_outbox_messages message
    left join public.leghevo_operational_outbox_delivery_heads delivery
      on delivery.message_id = message.id and delivery.destination_key = v_destination
    left join public.leghevo_operational_consumer_receipts receipt
      on receipt.message_id = message.id and receipt.destination_key = v_destination
    where message.environment_key = v_environment;

    select count(*) into v_destination_mismatch_count
    from public.leghevo_operational_outbox_messages message
    left join public.leghevo_operational_outbox_delivery_heads delivery
      on delivery.message_id = message.id and delivery.destination_key = v_destination
    left join public.leghevo_operational_consumer_receipts receipt
      on receipt.message_id = message.id and receipt.destination_key = v_destination
    where message.environment_key = v_environment
      and (
        delivery.message_id is null
        or delivery.state <> 'delivered'
        or receipt.id is null
        or receipt.environment_key <> message.environment_key
        or receipt.stream_sequence <> message.stream_sequence
        or receipt.message_fingerprint <> message.message_fingerprint
        or receipt.receipt_fingerprint <>
          public.compute_leghevo_operational_consumer_receipt_fingerprint_v1(
            receipt.environment_key, receipt.message_id, receipt.destination_key,
            receipt.stream_sequence, receipt.message_fingerprint, receipt.consumer_id,
            receipt.consumer_generation, receipt.consumer_token_hash,
            receipt.application_key, receipt.application_fingerprint,
            receipt.receipt_signature, receipt.adoption_mode, receipt.contract_version)
      );

    select public.leghevo_sha256_hex_v1(
      coalesce(string_agg(receipt.receipt_fingerprint, '|' order by receipt.stream_sequence), '')
    ) into v_receipt_chain_fingerprint
    from public.leghevo_operational_consumer_receipts receipt
    where receipt.environment_key = v_environment
      and receipt.destination_key = v_destination;

    v_attestation_status := case
      when v_destination_delivery_count = v_message_count
       and v_destination_receipt_count = v_message_count
       and v_destination_ack_sequence = v_last_sequence
       and v_destination_mismatch_count = 0
       and v_dead_letter_count = 0 then 'certified'
      else 'affected'
    end;
    v_attestation_reason := case
      when v_dead_letter_count > 0 then 'delivery_audit.dead_letter_present'
      when v_destination_mismatch_count > 0 then 'delivery_audit.destination_mismatch'
      when v_destination_delivery_count <> v_message_count then 'delivery_audit.destination_delivery_missing'
      when v_destination_receipt_count <> v_message_count then 'delivery_audit.destination_receipt_missing'
      when v_destination_ack_sequence <> v_last_sequence then 'delivery_audit.destination_sequence_gap'
      else 'delivery_audit.destination_certified'
    end;
    v_attestation_fingerprint := public.compute_leghevo_operational_delivery_attestation_fingerprint_v1(
      v_run.id, v_environment, v_destination, v_last_sequence,
      v_destination_ack_sequence, v_message_count, v_destination_delivery_count,
      v_destination_receipt_count, v_destination_mismatch_count,
      v_receipt_chain_fingerprint, v_attestation_status, v_attestation_reason, 1);

    insert into public.leghevo_operational_delivery_audit_attestations(
      run_id, environment_key, destination_key, expected_sequence,
      acknowledged_sequence, message_count, delivery_count, receipt_count,
      mismatch_count, receipt_chain_fingerprint, status, reason_code,
      contract_version, attestation_fingerprint, details, attested_at, created_by
    ) values (
      v_run.id, v_environment, v_destination, v_last_sequence,
      v_destination_ack_sequence, v_message_count, v_destination_delivery_count,
      v_destination_receipt_count, v_destination_mismatch_count,
      v_receipt_chain_fingerprint, v_attestation_status, v_attestation_reason,
      1, v_attestation_fingerprint,
      jsonb_build_object('runFingerprint', v_run_fingerprint), now(), auth.uid()
    ) returning * into v_attestation;

    select head.* into v_head
    from public.leghevo_operational_delivery_audit_heads head
    where head.environment_key = v_environment
      and head.destination_key = v_destination
    for update;
    v_head_generation := coalesce(v_head.generation, 0) + 1;
    v_event_type := case
      when v_attestation_status = 'affected' then 'affected'
      when v_head.state = 'affected' then 'revalidated'
      else 'attested'
    end;

    if v_head.environment_key is null then
      insert into public.leghevo_operational_delivery_audit_heads(
        environment_key, destination_key, generation, latest_run_id,
        latest_attestation_id, state, audited_through_sequence,
        affected_reason, last_request_id, updated_at
      ) values (
        v_environment, v_destination, v_head_generation, v_run.id,
        v_attestation.id, v_attestation_status, v_last_sequence,
        case when v_attestation_status = 'affected' then v_attestation_reason else null end,
        p_request_id, now()
      );
    else
      update public.leghevo_operational_delivery_audit_heads
      set generation = v_head_generation,
          latest_run_id = v_run.id,
          latest_attestation_id = v_attestation.id,
          state = v_attestation_status,
          audited_through_sequence = v_last_sequence,
          affected_reason = case when v_attestation_status = 'affected' then v_attestation_reason else null end,
          last_request_id = p_request_id,
          updated_at = now()
      where environment_key = v_environment
        and destination_key = v_destination;
    end if;

    v_event_fingerprint := public.compute_leghevo_operational_delivery_audit_event_fingerprint_v1(
      v_environment, v_destination, v_event_type, v_head_generation,
      v_run.id, v_attestation.id, null, v_attestation_reason,
      jsonb_build_object('auditGeneration', v_generation,
        'auditedThroughSequence', v_last_sequence,
        'attestationFingerprint', v_attestation_fingerprint));
    insert into public.leghevo_operational_delivery_audit_events(
      environment_key, destination_key, request_id, event_type, generation,
      run_id, attestation_id, remediation_id, reason_code,
      event_fingerprint, details, created_at, created_by
    ) values (
      v_environment, v_destination, p_request_id, v_event_type, v_head_generation,
      v_run.id, v_attestation.id, null, v_attestation_reason,
      v_event_fingerprint,
      jsonb_build_object('auditGeneration', v_generation,
        'auditedThroughSequence', v_last_sequence,
        'attestationFingerprint', v_attestation_fingerprint),
      now(), auth.uid()
    );
  end loop;
  perform set_config('leghevo.delivery_audit_context', '', true);

  return public.get_leghevo_operational_delivery_audit_model_v1(v_environment);
exception when others then
  perform set_config('leghevo.delivery_audit_context', '', true);
  raise;
end;
$function$;

create or replace function public.get_leghevo_operational_delivery_audit_model_v1(
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
  v_consumer jsonb;
  v_run public.leghevo_operational_delivery_audit_runs%rowtype;
  v_head_count bigint := 0;
  v_affected_head_count bigint := 0;
  v_run_mismatch_count bigint := 0;
  v_attestation_mismatch_count bigint := 0;
  v_current_last_sequence bigint := 0;
  v_fresh boolean := false;
  v_protected boolean := false;
  v_healthy boolean := false;
  v_status text;
  v_reason text;
begin
  if v_environment not in ('production','staging') then
    return jsonb_build_object(
      'protected', false, 'healthy', false, 'fresh', false,
      'status', 'affected', 'reasonCode', 'delivery_audit.invalid_environment',
      'environment', v_environment
    );
  end if;

  v_outbox := public.get_leghevo_operational_outbox_model_v1(v_environment);
  v_consumer := public.get_leghevo_operational_consumer_delivery_model_v1(v_environment);
  v_current_last_sequence := coalesce((v_outbox ->> 'lastSequence')::bigint, 0);

  select run.* into v_run
  from public.leghevo_operational_delivery_audit_runs run
  where run.environment_key = v_environment
  order by run.audit_generation desc, run.id desc
  limit 1;

  if v_run.id is null then
    return jsonb_build_object(
      'protected', false, 'healthy', false, 'fresh', false,
      'status', 'attention', 'reasonCode', 'delivery_audit.missing',
      'environment', v_environment,
      'currentLastSequence', v_current_last_sequence,
      'checkedAt', now()
    );
  end if;

  select count(*), count(*) filter (where head.state = 'affected')
  into v_head_count, v_affected_head_count
  from public.leghevo_operational_delivery_audit_heads head
  where head.environment_key = v_environment;

  select count(*) into v_run_mismatch_count
  from public.leghevo_operational_delivery_audit_runs run
  where run.environment_key = v_environment
    and run.run_fingerprint <>
      public.compute_leghevo_operational_delivery_audit_run_fingerprint_v1(
        run.environment_key, run.audit_generation, run.audited_through_sequence,
        run.message_count, run.expected_delivery_count, run.delivery_count,
        run.receipt_count, run.sequence_gap_count, run.consistency_mismatch_count,
        run.fingerprint_mismatch_count, run.head_mismatch_count,
        run.dead_letter_count, run.status, run.contract_version);

  select count(*) into v_attestation_mismatch_count
  from public.leghevo_operational_delivery_audit_attestations attestation
  join public.leghevo_operational_delivery_audit_runs run on run.id = attestation.run_id
  where run.environment_key = v_environment
    and attestation.attestation_fingerprint <>
      public.compute_leghevo_operational_delivery_attestation_fingerprint_v1(
        attestation.run_id, attestation.environment_key, attestation.destination_key,
        attestation.expected_sequence, attestation.acknowledged_sequence,
        attestation.message_count, attestation.delivery_count,
        attestation.receipt_count, attestation.mismatch_count,
        attestation.receipt_chain_fingerprint, attestation.status,
        attestation.reason_code, attestation.contract_version);

  v_fresh := v_run.audited_through_sequence = v_current_last_sequence;
  v_protected := v_run.status = 'certified'
    and v_head_count = 2
    and v_affected_head_count = 0
    and v_run_mismatch_count = 0
    and v_attestation_mismatch_count = 0
    and v_fresh;
  v_healthy := v_protected
    and coalesce((v_outbox ->> 'healthy')::boolean, false)
    and coalesce((v_consumer ->> 'healthy')::boolean, false);
  v_status := case
    when v_run_mismatch_count > 0 or v_attestation_mismatch_count > 0 then 'affected'
    when v_run.status = 'affected' or v_affected_head_count > 0 then 'affected'
    when not v_fresh then 'stale'
    when v_healthy then 'certified'
    else 'attention'
  end;
  v_reason := case
    when v_run_mismatch_count > 0 then 'delivery_audit.run_fingerprint_changed'
    when v_attestation_mismatch_count > 0 then 'delivery_audit.attestation_fingerprint_changed'
    when v_run.status = 'affected' or v_affected_head_count > 0 then v_run.reason_code
    when not v_fresh then 'delivery_audit.new_events_not_attested'
    when not coalesce((v_outbox ->> 'healthy')::boolean, false) then 'delivery_audit.outbox_unhealthy'
    when not coalesce((v_consumer ->> 'healthy')::boolean, false) then 'delivery_audit.consumer_unhealthy'
    else 'delivery_audit.certified'
  end;

  return jsonb_build_object(
    'protected', v_protected,
    'healthy', v_healthy,
    'fresh', v_fresh,
    'status', v_status,
    'reasonCode', v_reason,
    'environment', v_environment,
    'auditGeneration', v_run.audit_generation,
    'auditedThroughSequence', v_run.audited_through_sequence,
    'currentLastSequence', v_current_last_sequence,
    'messageCount', v_run.message_count,
    'expectedDeliveryCount', v_run.expected_delivery_count,
    'deliveryCount', v_run.delivery_count,
    'receiptCount', v_run.receipt_count,
    'sequenceGapCount', v_run.sequence_gap_count,
    'consistencyMismatchCount', v_run.consistency_mismatch_count,
    'fingerprintMismatchCount', v_run.fingerprint_mismatch_count,
    'headMismatchCount', v_run.head_mismatch_count,
    'deadLetterCount', v_run.dead_letter_count,
    'affectedDestinationCount', v_affected_head_count,
    'runFingerprintMismatchCount', v_run_mismatch_count,
    'attestationFingerprintMismatchCount', v_attestation_mismatch_count,
    'lastAuditAt', v_run.completed_at,
    'checkedAt', now()
  );
end;
$function$;

create or replace function public.request_leghevo_operational_delivery_remediation_v1(
  p_environment_key text,
  p_destination_key text,
  p_remediation_type text,
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
  v_type text := lower(trim(coalesce(p_remediation_type, '')));
  v_reason text := trim(coalesce(p_reason_code, ''));
  v_details jsonb := coalesce(p_details, '{}'::jsonb);
  v_head public.leghevo_operational_delivery_audit_heads%rowtype;
  v_existing public.leghevo_operational_delivery_audit_remediations%rowtype;
  v_remediation public.leghevo_operational_delivery_audit_remediations%rowtype;
  v_fingerprint text;
  v_event_fingerprint text;
begin
  if v_environment not in ('production','staging')
    or v_destination not in ('operations_center','notification_dispatch')
    or v_type not in ('replay_review','quarantine','manual_investigation')
    or p_request_id is null
    or char_length(v_reason) not between 3 and 160
    or jsonb_typeof(v_details) is distinct from 'object' then
    raise exception 'Richiesta remediation audit operativo non valida.';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('leghevo:operational-delivery-audit:' || v_environment, 0));

  select remediation.* into v_existing
  from public.leghevo_operational_delivery_audit_remediations remediation
  where remediation.request_id = p_request_id;
  if found then
    if v_existing.environment_key <> v_environment
      or v_existing.destination_key <> v_destination
      or v_existing.remediation_type <> v_type then
      raise exception 'request_id già utilizzato per una remediation diversa.';
    end if;
    return jsonb_build_object('remediationId', v_existing.id, 'reused', true);
  end if;

  select head.* into strict v_head
  from public.leghevo_operational_delivery_audit_heads head
  where head.environment_key = v_environment
    and head.destination_key = v_destination
  for update;
  if v_head.state <> 'affected' then
    raise exception 'Remediation ammessa soltanto su una testa audit affected.';
  end if;

  v_fingerprint := public.leghevo_sha256_hex_v1(
    v_environment || '|' || v_destination || '|' || v_head.latest_run_id::text || '|' ||
    v_type || '|' || v_reason || '|' || p_request_id::text);

  perform set_config('leghevo.delivery_audit_context', 'allowed', true);
  insert into public.leghevo_operational_delivery_audit_remediations(
    request_id, environment_key, destination_key, audit_run_id,
    remediation_type, reason_code, status, remediation_fingerprint,
    details, requested_at, requested_by
  ) values (
    p_request_id, v_environment, v_destination, v_head.latest_run_id,
    v_type, v_reason, 'requested', v_fingerprint,
    v_details, now(), auth.uid()
  ) returning * into v_remediation;

  v_event_fingerprint := public.compute_leghevo_operational_delivery_audit_event_fingerprint_v1(
    v_environment, v_destination, 'remediation_requested', v_head.generation,
    v_head.latest_run_id, v_head.latest_attestation_id, v_remediation.id,
    v_reason, jsonb_build_object('remediationType', v_type));
  insert into public.leghevo_operational_delivery_audit_events(
    environment_key, destination_key, request_id, event_type, generation,
    run_id, attestation_id, remediation_id, reason_code,
    event_fingerprint, details, created_at, created_by
  ) values (
    v_environment, v_destination, p_request_id, 'remediation_requested', v_head.generation,
    v_head.latest_run_id, v_head.latest_attestation_id, v_remediation.id, v_reason,
    v_event_fingerprint, jsonb_build_object('remediationType', v_type), now(), auth.uid()
  );
  perform set_config('leghevo.delivery_audit_context', '', true);

  return jsonb_build_object(
    'remediationId', v_remediation.id,
    'auditRunId', v_remediation.audit_run_id,
    'status', v_remediation.status,
    'reused', false
  );
exception when no_data_found then
  perform set_config('leghevo.delivery_audit_context', '', true);
  raise exception 'Testa audit operativo non disponibile.';
when others then
  perform set_config('leghevo.delivery_audit_context', '', true);
  raise;
end;
$function$;

revoke all on function public.compute_leghevo_operational_delivery_audit_run_fingerprint_v1(text,bigint,bigint,bigint,bigint,bigint,bigint,bigint,bigint,bigint,bigint,bigint,text,integer) from public, anon, authenticated;
grant execute on function public.compute_leghevo_operational_delivery_audit_run_fingerprint_v1(text,bigint,bigint,bigint,bigint,bigint,bigint,bigint,bigint,bigint,bigint,bigint,text,integer) to service_role;
revoke all on function public.compute_leghevo_operational_delivery_attestation_fingerprint_v1(bigint,text,text,bigint,bigint,bigint,bigint,bigint,bigint,text,text,text,integer) from public, anon, authenticated;
grant execute on function public.compute_leghevo_operational_delivery_attestation_fingerprint_v1(bigint,text,text,bigint,bigint,bigint,bigint,bigint,bigint,text,text,text,integer) to service_role;
revoke all on function public.compute_leghevo_operational_delivery_audit_event_fingerprint_v1(text,text,text,bigint,bigint,bigint,bigint,text,jsonb) from public, anon, authenticated;
grant execute on function public.compute_leghevo_operational_delivery_audit_event_fingerprint_v1(text,text,text,bigint,bigint,bigint,bigint,text,jsonb) to service_role;
revoke all on function public.run_leghevo_operational_delivery_audit_v1(text,uuid,jsonb) from public, anon, authenticated;
grant execute on function public.run_leghevo_operational_delivery_audit_v1(text,uuid,jsonb) to service_role;
revoke all on function public.get_leghevo_operational_delivery_audit_model_v1(text) from public, anon;
grant execute on function public.get_leghevo_operational_delivery_audit_model_v1(text) to authenticated, service_role;
revoke all on function public.request_leghevo_operational_delivery_remediation_v1(text,text,text,uuid,text,jsonb) from public, anon, authenticated;
grant execute on function public.request_leghevo_operational_delivery_remediation_v1(text,text,text,uuid,text,jsonb) to service_role;

create or replace function public.promote_leghevo_application_rollout_v5(
  p_environment_key text,
  p_target_percentage integer,
  p_request_id uuid,
  p_reason text default 'rollout.delivery_audit_protected_promotion'
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_environment text := lower(trim(coalesce(p_environment_key, '')));
  v_audit jsonb;
begin
  if v_environment not in ('production','staging') or p_request_id is null then
    raise exception 'Promozione con barriera audit end-to-end non valida.';
  end if;
  v_audit := public.get_leghevo_operational_delivery_audit_model_v1(v_environment);
  if not coalesce((v_audit ->> 'protected')::boolean, false)
    or not coalesce((v_audit ->> 'healthy')::boolean, false)
    or not coalesce((v_audit ->> 'fresh')::boolean, false) then
    raise exception 'Promozione bloccata: audit end-to-end non certificato. Dettaglio: %', v_audit;
  end if;
  return public.promote_leghevo_application_rollout_v4(
    v_environment, p_target_percentage, p_request_id, trim(p_reason));
end;
$function$;

revoke all on function public.promote_leghevo_application_rollout_v5(text,integer,uuid,text) from public, anon, authenticated;
grant execute on function public.promote_leghevo_application_rollout_v5(text,integer,uuid,text) to service_role;
revoke execute on function public.promote_leghevo_application_rollout_v4(text,integer,uuid,text) from service_role;

create or replace function public.get_leghevo_client_rollout_eligibility_v5(
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
  v_audit jsonb;
  v_eligible boolean;
  v_reason text;
begin
  v_base := public.get_leghevo_client_rollout_eligibility_v4(
    p_application_version, p_bundle_fingerprint, p_installation_id);
  v_audit := public.get_leghevo_operational_delivery_audit_model_v1('production');
  v_eligible := coalesce((v_base ->> 'rolloutEligible')::boolean, false)
    and coalesce((v_audit ->> 'healthy')::boolean, false)
    and coalesce((v_audit ->> 'fresh')::boolean, false);
  v_reason := case
    when not coalesce((v_base ->> 'compatible')::boolean, false)
      then coalesce(v_base ->> 'reasonCode', 'release.incompatible')
    when not coalesce((v_audit ->> 'protected')::boolean, false)
      then 'delivery_audit.not_protected'
    when not coalesce((v_audit ->> 'fresh')::boolean, false)
      then 'delivery_audit.new_events_not_attested'
    when coalesce((v_audit ->> 'fingerprintMismatchCount')::bigint, 0) > 0
      or coalesce((v_audit ->> 'runFingerprintMismatchCount')::bigint, 0) > 0
      or coalesce((v_audit ->> 'attestationFingerprintMismatchCount')::bigint, 0) > 0
      then 'delivery_audit.fingerprint_mismatch'
    when coalesce((v_audit ->> 'sequenceGapCount')::bigint, 0) > 0
      then 'delivery_audit.sequence_gap'
    when coalesce((v_audit ->> 'consistencyMismatchCount')::bigint, 0) > 0
      then 'delivery_audit.delivery_consistency_mismatch'
    else coalesce(v_base ->> 'reasonCode', 'release.compatible')
  end;

  return v_base || jsonb_build_object(
    'compatible', coalesce((v_base ->> 'compatible')::boolean, false) and v_eligible,
    'rolloutEligible', v_eligible,
    'reasonCode', v_reason,
    'deliveryAuditProtected', coalesce((v_audit ->> 'protected')::boolean, false),
    'deliveryAuditHealthy', coalesce((v_audit ->> 'healthy')::boolean, false),
    'deliveryAuditFresh', coalesce((v_audit ->> 'fresh')::boolean, false),
    'deliveryAuditStatus', v_audit ->> 'status',
    'deliveryAuditGeneration', coalesce((v_audit ->> 'auditGeneration')::bigint, 0),
    'deliveryAuditSequence', coalesce((v_audit ->> 'auditedThroughSequence')::bigint, 0),
    'checkedAt', now()
  );
end;
$function$;

revoke all on function public.get_leghevo_client_rollout_eligibility_v5(text,text,uuid) from public;
grant execute on function public.get_leghevo_client_rollout_eligibility_v5(text,text,uuid) to anon, authenticated;

create or replace function public.get_league_provider_sync_health_v38(p_league_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_base jsonb;
  v_audit jsonb;
begin
  v_base := public.get_league_provider_sync_health_v37(p_league_id);
  v_audit := public.get_leghevo_operational_delivery_audit_model_v1('production');
  return v_base || jsonb_build_object(
    'applicationOperationalDeliveryAudit', v_audit,
    'healthy', coalesce((v_base ->> 'healthy')::boolean, false)
      and coalesce((v_audit ->> 'healthy')::boolean, false),
    'protected', coalesce((v_base ->> 'protected')::boolean, false)
      and coalesce((v_audit ->> 'protected')::boolean, false)
  );
end;
$function$;
revoke all on function public.get_league_provider_sync_health_v38(uuid) from public, anon;
grant execute on function public.get_league_provider_sync_health_v38(uuid) to authenticated;

create or replace function public.get_league_season_state_v17(p_league_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_base jsonb;
  v_audit jsonb;
begin
  v_base := public.get_league_season_state_v16(p_league_id);
  v_audit := public.get_leghevo_operational_delivery_audit_model_v1('production');
  return v_base || jsonb_build_object('applicationOperationalDeliveryAudit', v_audit);
end;
$function$;
revoke all on function public.get_league_season_state_v17(uuid) from public, anon;
grant execute on function public.get_league_season_state_v17(uuid) to authenticated;

create or replace function public.get_league_management_state_v27(p_league_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_base jsonb;
  v_audit jsonb;
  v_checks jsonb;
begin
  v_base := public.get_league_management_state_v26(p_league_id);
  v_audit := public.get_leghevo_operational_delivery_audit_model_v1('production');
  v_checks := coalesce(v_base -> 'checks', '{}'::jsonb) || jsonb_build_object(
    'applicationOperationalDeliveryAuditProtected', coalesce((v_audit ->> 'protected')::boolean, false),
    'applicationOperationalDeliveryAuditHealthy', coalesce((v_audit ->> 'healthy')::boolean, false),
    'applicationOperationalDeliveryAuditFresh', coalesce((v_audit ->> 'fresh')::boolean, false)
  );
  return v_base || jsonb_build_object(
    'applicationOperationalDeliveryAudit', v_audit,
    'checks', v_checks
  );
end;
$function$;
revoke all on function public.get_league_management_state_v27(uuid) from public, anon;
grant execute on function public.get_league_management_state_v27(uuid) to authenticated;

-- Helper temporaneo per esercitare outbox, inbox e audit nella release v0.62.39.
create or replace function public.seed_leghevo_operational_delivery_audit_drain_v1(
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
      'leghevo-delivery-audit-seed-worker', 3, p_delivery_fencing_token,
      p_consumer_key, p_consumer_generation, p_consumer_fencing_token,
      200, 120);
    exit when coalesce((v_claim ->> 'claimedCount')::integer, 0) = 0;
    for v_item in select value from pg_catalog.jsonb_array_elements(v_claim -> 'items')
    loop
      v_application_fingerprint := public.leghevo_sha256_hex_v1(
        p_destination_key || '|audited-applied|' || (v_item ->> 'messageId') || '|' ||
        (v_item ->> 'messageFingerprint'));
      v_outcome := public.apply_leghevo_operational_consumer_message_v1(
        p_environment_key, (v_item ->> 'messageId')::bigint, p_destination_key,
        (v_item ->> 'deliveryGeneration')::bigint,
        'leghevo-delivery-audit-seed-worker', 3, p_delivery_fencing_token,
        p_consumer_key, p_consumer_generation, p_consumer_fencing_token,
        'leghevo-' || p_destination_key, v_application_fingerprint,
        gen_random_uuid(), jsonb_build_object('seedDelivery', true, 'sourceMigration', 143));
      v_count := v_count + 1;
    end loop;
  end loop;
  return v_count;
end;
$function$;
revoke all on function public.seed_leghevo_operational_delivery_audit_drain_v1(text,text,text,bigint,uuid,uuid) from public, anon, authenticated, service_role;

-- Certificazione, rollout ed audit continuo della release v0.62.39.
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
    where c.application_version = '0.62.39'
  ) and exists (
    select 1 from public.leghevo_operational_delivery_audit_runs run
    where run.request_id = '62390000-0000-4000-8000-000000000030'::uuid
  ) then
    return;
  end if;

  v_outcome := public.certify_leghevo_operational_consumer_v1(
    'production', 'operations_center', 'leghevo-operations-consumer', 2,
    v_operations_consumer_token, '62390000-0000-4000-8000-000000000001'::uuid,
    jsonb_build_object('sourceMigration', 143, 'contract', 'continuous-delivery-audit-v1'));
  v_outcome := public.certify_leghevo_operational_consumer_v1(
    'production', 'notification_dispatch', 'leghevo-notification-consumer', 2,
    v_notification_consumer_token, '62390000-0000-4000-8000-000000000002'::uuid,
    jsonb_build_object('sourceMigration', 143, 'contract', 'continuous-delivery-audit-v1'));

  if not exists (
    select 1 from public.leghevo_application_release_certificates c
    where c.application_version = '0.62.39'
  ) then
    v_outcome := public.certify_leghevo_application_release_v1(
      '0.62.39', '054e6d828c700efeefa713f0260911b76545214a2fa5b7cbeeeca9021c62d55b', '0.62.38', '0.62.39',
      '62390000-0000-4000-8000-000000000003'::uuid,
      jsonb_build_object('baseline', false, 'sourceMigration', 143));
    v_outcome := public.certify_leghevo_application_rollout_v1(
      'production', '0.62.39', 10, 100, 500, 3, 100,
      '62390000-0000-4000-8000-000000000004'::uuid,
      jsonb_build_object('strategy', 'continuous-end-to-end-audit', 'sourceMigration', 143));
    v_outcome := public.activate_leghevo_release_with_rollout_v1(
      'production', '0.62.39',
      '62390000-0000-4000-8000-000000000005'::uuid,
      '62390000-0000-4000-8000-000000000006'::uuid,
      'delivery_audit.production_activation');
    v_outcome := public.certify_leghevo_operational_telemetry_source_v1(
      'production', 'leghevo-production-observer', 4, v_telemetry_token,
      '62390000-0000-4000-8000-000000000007'::uuid,
      jsonb_build_object('provider', 'leghevo-runtime', 'sourceMigration', 143));

    v_outcome := public.record_leghevo_authoritative_operational_window_v1(
      'production', 'leghevo-production-observer', 4, v_telemetry_token, 1,
      v_now - interval '25 minutes', v_now - interval '20 minutes',
      1000, 2, 0, 210,
      '62390000-0000-4000-8000-000000000008'::uuid,
      jsonb_build_object('seedStage', 10));
    perform public.seed_leghevo_operational_delivery_audit_drain_v1('production','operations_center','leghevo-operations-consumer',2,v_operations_consumer_token,v_operations_delivery_token);
    perform public.seed_leghevo_operational_delivery_audit_drain_v1('production','notification_dispatch','leghevo-notification-consumer',2,v_notification_consumer_token,v_notification_delivery_token);
    v_outcome := public.run_leghevo_operational_delivery_audit_v1('production','62390000-0000-4000-8000-000000000009'::uuid,jsonb_build_object('seedStage',10));
    v_outcome := public.promote_leghevo_application_rollout_v5('production',35,'62390000-0000-4000-8000-000000000010'::uuid,'rollout.delivery_audit_promotion_35');

    perform public.seed_leghevo_operational_delivery_audit_drain_v1('production','operations_center','leghevo-operations-consumer',2,v_operations_consumer_token,v_operations_delivery_token);
    perform public.seed_leghevo_operational_delivery_audit_drain_v1('production','notification_dispatch','leghevo-notification-consumer',2,v_notification_consumer_token,v_notification_delivery_token);
    v_outcome := public.record_leghevo_authoritative_operational_window_v1(
      'production', 'leghevo-production-observer', 4, v_telemetry_token, 2,
      v_now - interval '20 minutes', v_now - interval '15 minutes',
      1000, 2, 0, 205,
      '62390000-0000-4000-8000-000000000011'::uuid,
      jsonb_build_object('seedStage', 35));
    perform public.seed_leghevo_operational_delivery_audit_drain_v1('production','operations_center','leghevo-operations-consumer',2,v_operations_consumer_token,v_operations_delivery_token);
    perform public.seed_leghevo_operational_delivery_audit_drain_v1('production','notification_dispatch','leghevo-notification-consumer',2,v_notification_consumer_token,v_notification_delivery_token);
    v_outcome := public.run_leghevo_operational_delivery_audit_v1('production','62390000-0000-4000-8000-000000000012'::uuid,jsonb_build_object('seedStage',35));
    v_outcome := public.promote_leghevo_application_rollout_v5('production',60,'62390000-0000-4000-8000-000000000013'::uuid,'rollout.delivery_audit_promotion_60');

    perform public.seed_leghevo_operational_delivery_audit_drain_v1('production','operations_center','leghevo-operations-consumer',2,v_operations_consumer_token,v_operations_delivery_token);
    perform public.seed_leghevo_operational_delivery_audit_drain_v1('production','notification_dispatch','leghevo-notification-consumer',2,v_notification_consumer_token,v_notification_delivery_token);
    v_outcome := public.record_leghevo_authoritative_operational_window_v1(
      'production', 'leghevo-production-observer', 4, v_telemetry_token, 3,
      v_now - interval '15 minutes', v_now - interval '10 minutes',
      1000, 1, 0, 200,
      '62390000-0000-4000-8000-000000000014'::uuid,
      jsonb_build_object('seedStage', 60));
    perform public.seed_leghevo_operational_delivery_audit_drain_v1('production','operations_center','leghevo-operations-consumer',2,v_operations_consumer_token,v_operations_delivery_token);
    perform public.seed_leghevo_operational_delivery_audit_drain_v1('production','notification_dispatch','leghevo-notification-consumer',2,v_notification_consumer_token,v_notification_delivery_token);
    v_outcome := public.run_leghevo_operational_delivery_audit_v1('production','62390000-0000-4000-8000-000000000015'::uuid,jsonb_build_object('seedStage',60));
    v_outcome := public.promote_leghevo_application_rollout_v5('production',85,'62390000-0000-4000-8000-000000000016'::uuid,'rollout.delivery_audit_promotion_85');

    perform public.seed_leghevo_operational_delivery_audit_drain_v1('production','operations_center','leghevo-operations-consumer',2,v_operations_consumer_token,v_operations_delivery_token);
    perform public.seed_leghevo_operational_delivery_audit_drain_v1('production','notification_dispatch','leghevo-notification-consumer',2,v_notification_consumer_token,v_notification_delivery_token);
    v_outcome := public.record_leghevo_authoritative_operational_window_v1(
      'production', 'leghevo-production-observer', 4, v_telemetry_token, 4,
      v_now - interval '10 minutes', v_now - interval '5 minutes',
      1000, 1, 0, 195,
      '62390000-0000-4000-8000-000000000017'::uuid,
      jsonb_build_object('seedStage', 85));
    perform public.seed_leghevo_operational_delivery_audit_drain_v1('production','operations_center','leghevo-operations-consumer',2,v_operations_consumer_token,v_operations_delivery_token);
    perform public.seed_leghevo_operational_delivery_audit_drain_v1('production','notification_dispatch','leghevo-notification-consumer',2,v_notification_consumer_token,v_notification_delivery_token);
    v_outcome := public.run_leghevo_operational_delivery_audit_v1('production','62390000-0000-4000-8000-000000000018'::uuid,jsonb_build_object('seedStage',85));
    v_outcome := public.promote_leghevo_application_rollout_v5('production',100,'62390000-0000-4000-8000-000000000019'::uuid,'rollout.delivery_audit_completed');

    perform public.seed_leghevo_operational_delivery_audit_drain_v1('production','operations_center','leghevo-operations-consumer',2,v_operations_consumer_token,v_operations_delivery_token);
    perform public.seed_leghevo_operational_delivery_audit_drain_v1('production','notification_dispatch','leghevo-notification-consumer',2,v_notification_consumer_token,v_notification_delivery_token);
    v_outcome := public.record_leghevo_authoritative_operational_window_v1(
      'production', 'leghevo-production-observer', 4, v_telemetry_token, 5,
      v_now - interval '5 minutes', v_now,
      1000, 1, 0, 190,
      '62390000-0000-4000-8000-000000000020'::uuid,
      jsonb_build_object('seedStage', 100, 'postCompletion', true));
    perform public.seed_leghevo_operational_delivery_audit_drain_v1('production','operations_center','leghevo-operations-consumer',2,v_operations_consumer_token,v_operations_delivery_token);
    perform public.seed_leghevo_operational_delivery_audit_drain_v1('production','notification_dispatch','leghevo-notification-consumer',2,v_notification_consumer_token,v_notification_delivery_token);
  end if;

  v_outcome := public.run_leghevo_operational_delivery_audit_v1(
    'production', '62390000-0000-4000-8000-000000000030'::uuid,
    jsonb_build_object('seedStage',100,'closure',true));
end;
$seed_release$;

drop function if exists public.seed_leghevo_operational_delivery_audit_drain_v1(text,text,text,bigint,uuid,uuid);

do $realtime$
begin
  if exists (select 1 from pg_catalog.pg_publication p where p.pubname = 'supabase_realtime')
    and not exists (
      select 1 from pg_catalog.pg_publication_tables pt
      where pt.pubname = 'supabase_realtime'
        and pt.schemaname = 'public'
        and pt.tablename = 'leghevo_operational_delivery_audit_events'
    ) then
    alter publication supabase_realtime add table public.leghevo_operational_delivery_audit_events;
  end if;
end;
$realtime$;

create or replace function public.get_leghevo_operational_delivery_audit_deployment_integrity_v1()
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
  v_run_mismatch bigint;
  v_attestation_mismatch bigint;
  v_run_def text := coalesce(pg_catalog.pg_get_functiondef(
    to_regprocedure('public.run_leghevo_operational_delivery_audit_v1(text,uuid,jsonb)')), '');
  v_promote_def text := coalesce(pg_catalog.pg_get_functiondef(
    to_regprocedure('public.promote_leghevo_application_rollout_v5(text,integer,uuid,text)')), '');
begin
  v_predecessor := public.get_leghevo_operational_consumer_delivery_deployment_integrity_v1();
  select array_agg(item.key order by item.key) into v_predecessor_false
  from pg_catalog.jsonb_each(v_predecessor) item
  where pg_catalog.jsonb_typeof(item.value) is distinct from 'boolean'
     or item.value is distinct from 'true'::jsonb;

  v_model := public.get_leghevo_operational_delivery_audit_model_v1('production');
  v_release := public.get_leghevo_application_release_model_v1('production');
  v_rollout := public.get_leghevo_application_rollout_model_v1('production');
  v_telemetry := public.get_leghevo_operational_telemetry_model_v1('production');

  select count(*) into v_run_mismatch
  from public.leghevo_operational_delivery_audit_runs run
  where run.run_fingerprint <>
    public.compute_leghevo_operational_delivery_audit_run_fingerprint_v1(
      run.environment_key, run.audit_generation, run.audited_through_sequence,
      run.message_count, run.expected_delivery_count, run.delivery_count,
      run.receipt_count, run.sequence_gap_count, run.consistency_mismatch_count,
      run.fingerprint_mismatch_count, run.head_mismatch_count,
      run.dead_letter_count, run.status, run.contract_version);

  select count(*) into v_attestation_mismatch
  from public.leghevo_operational_delivery_audit_attestations attestation
  where attestation.attestation_fingerprint <>
    public.compute_leghevo_operational_delivery_attestation_fingerprint_v1(
      attestation.run_id, attestation.environment_key, attestation.destination_key,
      attestation.expected_sequence, attestation.acknowledged_sequence,
      attestation.message_count, attestation.delivery_count,
      attestation.receipt_count, attestation.mismatch_count,
      attestation.receipt_chain_fingerprint, attestation.status,
      attestation.reason_code, attestation.contract_version);

  return jsonb_build_object(
    'predecessor_ready',
      (select count(*) = 20 from pg_catalog.jsonb_each(v_predecessor))
      and coalesce(v_predecessor_false, array[]::text[]) = array[
        'legacy_bypass_blocked',
        'seed_delivery_ready'
      ]::text[],
    'run_table_ready', to_regclass('public.leghevo_operational_delivery_audit_runs') is not null,
    'attestation_table_ready', to_regclass('public.leghevo_operational_delivery_audit_attestations') is not null,
    'head_table_ready', to_regclass('public.leghevo_operational_delivery_audit_heads') is not null,
    'remediation_and_event_tables_ready',
      to_regclass('public.leghevo_operational_delivery_audit_remediations') is not null
      and to_regclass('public.leghevo_operational_delivery_audit_events') is not null,
    'constraints_ready',
      exists (select 1 from pg_catalog.pg_constraint c
        where c.conrelid = 'public.leghevo_operational_delivery_audit_runs'::regclass
          and c.conname = 'leghevo_delivery_audit_run_generation_unique')
      and exists (select 1 from pg_catalog.pg_constraint c
        where c.conrelid = 'public.leghevo_operational_delivery_audit_attestations'::regclass
          and c.conname = 'leghevo_delivery_attestation_run_destination_unique')
      and exists (select 1 from pg_catalog.pg_constraint c
        where c.conrelid = 'public.leghevo_operational_delivery_audit_heads'::regclass
          and c.conname = 'leghevo_delivery_audit_head_attestation_fk'),
    'indexes_ready',
      to_regclass('public.leghevo_delivery_audit_runs_environment_generation_idx') is not null
      and to_regclass('public.leghevo_delivery_audit_attestations_destination_idx') is not null
      and to_regclass('public.leghevo_delivery_audit_events_created_idx') is not null,
    'rls_ready',
      (select relrowsecurity from pg_catalog.pg_class where oid = 'public.leghevo_operational_delivery_audit_runs'::regclass)
      and (select relrowsecurity from pg_catalog.pg_class where oid = 'public.leghevo_operational_delivery_audit_attestations'::regclass)
      and (select relrowsecurity from pg_catalog.pg_class where oid = 'public.leghevo_operational_delivery_audit_heads'::regclass)
      and (select relrowsecurity from pg_catalog.pg_class where oid = 'public.leghevo_operational_delivery_audit_remediations'::regclass)
      and (select relrowsecurity from pg_catalog.pg_class where oid = 'public.leghevo_operational_delivery_audit_events'::regclass),
    'direct_write_blocked',
      not has_table_privilege('authenticated','public.leghevo_operational_delivery_audit_runs','INSERT')
      and not has_table_privilege('service_role','public.leghevo_operational_delivery_audit_runs','INSERT')
      and not has_table_privilege('authenticated','public.leghevo_operational_delivery_audit_remediations','INSERT'),
    'immutable_records_ready',
      (select count(*) = 4 from pg_catalog.pg_trigger t
       where t.tgname in ('leghevo_delivery_audit_runs_guard','leghevo_delivery_audit_attestations_guard',
         'leghevo_delivery_audit_remediations_guard','leghevo_delivery_audit_events_guard')
         and t.tgenabled = 'A' and not t.tgisinternal),
    'head_guard_ready',
      exists (select 1 from pg_catalog.pg_trigger t
       where t.tgrelid = 'public.leghevo_operational_delivery_audit_heads'::regclass
         and t.tgname = 'leghevo_delivery_audit_heads_guard'
         and t.tgenabled = 'A' and not t.tgisinternal),
    'fingerprints_ready', v_run_mismatch = 0 and v_attestation_mismatch = 0,
    'audit_rpc_ready',
      to_regprocedure('public.run_leghevo_operational_delivery_audit_v1(text,uuid,jsonb)') is not null
      and has_function_privilege('service_role','public.run_leghevo_operational_delivery_audit_v1(text,uuid,jsonb)','EXECUTE')
      and position('pg_advisory_xact_lock' in v_run_def) > 0
      and position('receipt_chain_fingerprint' in v_run_def) > 0,
    'remediation_rpc_ready',
      to_regprocedure('public.request_leghevo_operational_delivery_remediation_v1(text,text,text,uuid,text,jsonb)') is not null
      and has_function_privilege('service_role','public.request_leghevo_operational_delivery_remediation_v1(text,text,text,uuid,text,jsonb)','EXECUTE'),
    'promotion_v5_ready',
      to_regprocedure('public.promote_leghevo_application_rollout_v5(text,integer,uuid,text)') is not null
      and has_function_privilege('service_role','public.promote_leghevo_application_rollout_v5(text,integer,uuid,text)','EXECUTE')
      and not has_function_privilege('service_role','public.promote_leghevo_application_rollout_v4(text,integer,uuid,text)','EXECUTE')
      and position('get_leghevo_operational_delivery_audit_model_v1' in v_promote_def) > 0,
    'client_barrier_ready',
      to_regprocedure('public.get_leghevo_client_rollout_eligibility_v5(text,text,uuid)') is not null
      and has_function_privilege('anon','public.get_leghevo_client_rollout_eligibility_v5(text,text,uuid)','EXECUTE')
      and has_function_privilege('authenticated','public.get_leghevo_client_rollout_eligibility_v5(text,text,uuid)','EXECUTE'),
    'endpoint_chain_ready',
      to_regprocedure('public.get_league_provider_sync_health_v38(uuid)') is not null
      and to_regprocedure('public.get_league_season_state_v17(uuid)') is not null
      and to_regprocedure('public.get_league_management_state_v27(uuid)') is not null
      and has_function_privilege('authenticated','public.get_league_provider_sync_health_v38(uuid)','EXECUTE'),
    'realtime_ready',
      not exists (select 1 from pg_catalog.pg_publication p where p.pubname = 'supabase_realtime')
      or exists (select 1 from pg_catalog.pg_publication_tables pt
        where pt.pubname = 'supabase_realtime' and pt.schemaname = 'public'
          and pt.tablename = 'leghevo_operational_delivery_audit_events'),
    'seed_release_ready',
      coalesce((v_release ->> 'protected')::boolean, false)
      and v_release ->> 'activeVersion' = '0.62.39'
      and coalesce((v_rollout ->> 'protected')::boolean, false)
      and v_rollout ->> 'status' = 'completed'
      and coalesce((v_rollout ->> 'exposurePercentage')::integer, 0) = 100
      and coalesce((v_telemetry ->> 'protected')::boolean, false)
      and coalesce((v_telemetry ->> 'sourceGeneration')::bigint, 0) = 4
      and v_telemetry ->> 'latestReleaseVersion' = '0.62.39'
      and exists (select 1 from public.leghevo_application_release_certificates c
        where c.application_version = '0.62.39'
          and c.bundle_fingerprint = '054e6d828c700efeefa713f0260911b76545214a2fa5b7cbeeeca9021c62d55b'),
    'closure_audit_ready',
      coalesce((v_model ->> 'protected')::boolean, false)
      and coalesce((v_model ->> 'healthy')::boolean, false)
      and coalesce((v_model ->> 'fresh')::boolean, false)
      and v_model ->> 'status' = 'certified'
      and coalesce((v_model ->> 'sequenceGapCount')::bigint, -1) = 0
      and coalesce((v_model ->> 'consistencyMismatchCount')::bigint, -1) = 0
      and coalesce((v_model ->> 'fingerprintMismatchCount')::bigint, -1) = 0
      and coalesce((v_model ->> 'deadLetterCount')::bigint, -1) = 0
      and (select count(*) from public.leghevo_operational_delivery_audit_attestations a
        join public.leghevo_operational_delivery_audit_runs r on r.id = a.run_id
        where r.environment_key = 'production' and r.id = (
          select max(id) from public.leghevo_operational_delivery_audit_runs
          where environment_key = 'production'
        ) and a.status = 'certified') = 2
      and to_regprocedure('public.seed_leghevo_operational_delivery_audit_drain_v1(text,text,text,bigint,uuid,uuid)') is null
  );
end;
$function$;

revoke all on function public.get_leghevo_operational_delivery_audit_deployment_integrity_v1() from public, anon, authenticated;
grant execute on function public.get_leghevo_operational_delivery_audit_deployment_integrity_v1() to service_role;

do $validation$
declare
  v_integrity jsonb;
  v_false text[];
begin
  v_integrity := public.get_leghevo_operational_delivery_audit_deployment_integrity_v1();
  select array_agg(item.key order by item.key) into v_false
  from pg_catalog.jsonb_each(v_integrity) item
  where pg_catalog.jsonb_typeof(item.value) is distinct from 'boolean'
     or item.value is distinct from 'true'::jsonb;

  if (select count(*) from pg_catalog.jsonb_each(v_integrity)) <> 20
    or cardinality(v_false) > 0 then
    raise exception 'Validazione v0.62.39 non superata: %. Dettaglio: %',
      coalesce(array_to_string(v_false, ', '), 'numero controlli diverso da 20'),
      v_integrity;
  end if;
end;
$validation$;

commit;

select
  (public.get_leghevo_operational_delivery_audit_deployment_integrity_v1()->>'predecessor_ready')::boolean as predecessor_ready,
  (public.get_leghevo_operational_delivery_audit_deployment_integrity_v1()->>'run_table_ready')::boolean as run_table_ready,
  (public.get_leghevo_operational_delivery_audit_deployment_integrity_v1()->>'attestation_table_ready')::boolean as attestation_table_ready,
  (public.get_leghevo_operational_delivery_audit_deployment_integrity_v1()->>'head_table_ready')::boolean as head_table_ready,
  (public.get_leghevo_operational_delivery_audit_deployment_integrity_v1()->>'remediation_and_event_tables_ready')::boolean as remediation_and_event_tables_ready,
  (public.get_leghevo_operational_delivery_audit_deployment_integrity_v1()->>'constraints_ready')::boolean as constraints_ready,
  (public.get_leghevo_operational_delivery_audit_deployment_integrity_v1()->>'indexes_ready')::boolean as indexes_ready,
  (public.get_leghevo_operational_delivery_audit_deployment_integrity_v1()->>'rls_ready')::boolean as rls_ready,
  (public.get_leghevo_operational_delivery_audit_deployment_integrity_v1()->>'direct_write_blocked')::boolean as direct_write_blocked,
  (public.get_leghevo_operational_delivery_audit_deployment_integrity_v1()->>'immutable_records_ready')::boolean as immutable_records_ready,
  (public.get_leghevo_operational_delivery_audit_deployment_integrity_v1()->>'head_guard_ready')::boolean as head_guard_ready,
  (public.get_leghevo_operational_delivery_audit_deployment_integrity_v1()->>'fingerprints_ready')::boolean as fingerprints_ready,
  (public.get_leghevo_operational_delivery_audit_deployment_integrity_v1()->>'audit_rpc_ready')::boolean as audit_rpc_ready,
  (public.get_leghevo_operational_delivery_audit_deployment_integrity_v1()->>'remediation_rpc_ready')::boolean as remediation_rpc_ready,
  (public.get_leghevo_operational_delivery_audit_deployment_integrity_v1()->>'promotion_v5_ready')::boolean as promotion_v5_ready,
  (public.get_leghevo_operational_delivery_audit_deployment_integrity_v1()->>'client_barrier_ready')::boolean as client_barrier_ready,
  (public.get_leghevo_operational_delivery_audit_deployment_integrity_v1()->>'endpoint_chain_ready')::boolean as endpoint_chain_ready,
  (public.get_leghevo_operational_delivery_audit_deployment_integrity_v1()->>'realtime_ready')::boolean as realtime_ready,
  (public.get_leghevo_operational_delivery_audit_deployment_integrity_v1()->>'seed_release_ready')::boolean as seed_release_ready,
  (public.get_leghevo_operational_delivery_audit_deployment_integrity_v1()->>'closure_audit_ready')::boolean as closure_audit_ready;
