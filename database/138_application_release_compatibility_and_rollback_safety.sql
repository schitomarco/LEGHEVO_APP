-- LEGHEVO v0.62.34
-- Contratto di rilascio compatibile e rollback certificato.
-- Secondo blocco dello Sviluppo 9: lega ogni bundle mobile a un sigillo
-- applicativo certificato, impedisce attivazioni non atomiche e consente
-- rollback soltanto verso release già certificate e compatibili.
-- Migrazione idempotente, append-only e non distruttiva.

begin;

-- Preflight: il sigillo globale v0.62.33 deve essere installato e integro.
do $preflight$
declare
  v_missing text[] := array[]::text[];
  v_signature text;
  v_predecessor jsonb;
begin
  if to_regclass('public.leghevo_model_certifications') is null then
    v_missing := array_append(v_missing,
      'tabella public.leghevo_model_certifications');
  end if;

  foreach v_signature in array array[
    'public.get_leghevo_application_integrity_seal_v1()',
    'public.get_leghevo_application_integrity_model_v1()',
    'public.compute_leghevo_application_schema_fingerprint_v1()',
    'public.get_league_provider_sync_health_v32(uuid)',
    'public.get_league_season_state_v11(uuid)',
    'public.get_league_management_state_v21(uuid)'
  ] loop
    if to_regprocedure(v_signature) is null then
      v_missing := array_append(v_missing, 'funzione ' || v_signature);
    end if;
  end loop;

  if cardinality(v_missing) > 0 then
    raise exception
      'Preflight v0.62.34 non superato. Oggetti mancanti: %',
      array_to_string(v_missing, '; ');
  end if;

  v_predecessor := public.get_leghevo_application_integrity_seal_v1();
  if (select count(*) from pg_catalog.jsonb_each(v_predecessor)) <> 20
    or exists(
      select 1 from pg_catalog.jsonb_each(v_predecessor) item
      where pg_catalog.jsonb_typeof(item.value) is distinct from 'boolean'
         or item.value is distinct from 'true'::jsonb
    ) then
    raise exception
      'Preflight v0.62.34 non superato: la v0.62.33 non risulta integra [%].',
      v_predecessor;
  end if;
end;
$preflight$;

-- SemVer numerico limitato alle versioni stabili major.minor.patch.
create or replace function public.leghevo_semver_rank_v1(p_version text)
returns bigint
language plpgsql
immutable
security definer
set search_path = ''
as $function$
declare
  v_major bigint;
  v_minor bigint;
  v_patch bigint;
begin
  if p_version is null
    or trim(p_version) !~ '^[0-9]{1,6}\.[0-9]{1,6}\.[0-9]{1,6}$' then
    return null;
  end if;

  v_major := split_part(trim(p_version), '.', 1)::bigint;
  v_minor := split_part(trim(p_version), '.', 2)::bigint;
  v_patch := split_part(trim(p_version), '.', 3)::bigint;

  return v_major * 1000000000000::bigint
    + v_minor * 1000000::bigint
    + v_patch;
exception when others then
  return null;
end;
$function$;

revoke all on function public.leghevo_semver_rank_v1(text)
from public, anon, authenticated;
grant execute on function public.leghevo_semver_rank_v1(text)
to service_role;

create or replace function public.compute_leghevo_release_contract_fingerprint_v1(
  p_application_version text,
  p_bundle_fingerprint text,
  p_schema_fingerprint text,
  p_min_supported_client_version text,
  p_max_supported_client_version text,
  p_release_contract_version integer default 1
)
returns text
language sql
immutable
security definer
set search_path = ''
as $function$
  select pg_catalog.md5(
    coalesce(trim(p_application_version), '') || '|' ||
    coalesce(lower(trim(p_bundle_fingerprint)), '') || '|' ||
    coalesce(lower(trim(p_schema_fingerprint)), '') || '|' ||
    coalesce(trim(p_min_supported_client_version), '') || '|' ||
    coalesce(trim(p_max_supported_client_version), '') || '|' ||
    coalesce(p_release_contract_version, 0)::text
  );
$function$;

revoke all on function public.compute_leghevo_release_contract_fingerprint_v1(
  text, text, text, text, text, integer
) from public, anon, authenticated;
grant execute on function public.compute_leghevo_release_contract_fingerprint_v1(
  text, text, text, text, text, integer
) to service_role;

create table if not exists public.leghevo_application_release_certificates (
  id uuid primary key default gen_random_uuid(),
  application_version text not null unique,
  release_contract_version integer not null default 1,
  bundle_fingerprint text not null,
  schema_model_key text not null default 'application_integrity_v1',
  schema_model_version integer not null default 1,
  schema_fingerprint text not null,
  min_supported_client_version text not null,
  max_supported_client_version text not null,
  contract_fingerprint text not null unique,
  certified_at timestamptz not null default now(),
  certified_by uuid null,
  metadata jsonb not null default '{}'::jsonb,
  constraint leghevo_release_certificate_contract_version_check
    check (release_contract_version >= 1),
  constraint leghevo_release_certificate_bundle_check
    check (bundle_fingerprint ~ '^[0-9a-f]{64}$'),
  constraint leghevo_release_certificate_schema_key_check
    check (schema_model_key = 'application_integrity_v1'),
  constraint leghevo_release_certificate_schema_version_check
    check (schema_model_version = 1),
  constraint leghevo_release_certificate_schema_fingerprint_check
    check (schema_fingerprint ~ '^[0-9a-f]{32}$'),
  constraint leghevo_release_certificate_contract_fingerprint_check
    check (contract_fingerprint ~ '^[0-9a-f]{32}$'),
  constraint leghevo_release_certificate_versions_check
    check (
      public.leghevo_semver_rank_v1(application_version) is not null
      and public.leghevo_semver_rank_v1(min_supported_client_version) is not null
      and public.leghevo_semver_rank_v1(max_supported_client_version) is not null
      and public.leghevo_semver_rank_v1(min_supported_client_version)
        <= public.leghevo_semver_rank_v1(application_version)
      and public.leghevo_semver_rank_v1(application_version)
        <= public.leghevo_semver_rank_v1(max_supported_client_version)
    ),
  constraint leghevo_release_certificate_metadata_check
    check (jsonb_typeof(metadata) = 'object')
);

create table if not exists public.leghevo_application_release_heads (
  environment_key text primary key,
  active_release_id uuid not null references
    public.leghevo_application_release_certificates(id),
  previous_release_id uuid null references
    public.leghevo_application_release_certificates(id),
  generation bigint not null default 1,
  state text not null default 'active',
  safe_state text not null default 'active',
  activated_at timestamptz not null default now(),
  activated_by uuid null,
  last_request_id uuid not null unique,
  rollback_count integer not null default 0,
  affected_reason text null,
  updated_at timestamptz not null default now(),
  constraint leghevo_release_head_environment_check
    check (environment_key in ('production', 'staging')),
  constraint leghevo_release_head_generation_check
    check (generation >= 1),
  constraint leghevo_release_head_state_check
    check (state in ('active', 'rollback', 'affected')),
  constraint leghevo_release_head_safe_state_check
    check (safe_state in ('active', 'rollback')),
  constraint leghevo_release_head_state_consistency_check
    check (state = 'affected' or state = safe_state),
  constraint leghevo_release_head_rollback_count_check
    check (rollback_count >= 0),
  constraint leghevo_release_head_distinct_releases_check
    check (previous_release_id is null or previous_release_id <> active_release_id),
  constraint leghevo_release_head_affected_reason_check
    check (
      (state = 'affected' and char_length(trim(affected_reason)) >= 8)
      or (state <> 'affected' and affected_reason is null)
    )
);

create table if not exists public.leghevo_application_release_events (
  id bigint generated by default as identity primary key,
  environment_key text not null,
  request_id uuid not null unique,
  event_type text not null,
  from_release_id uuid null references
    public.leghevo_application_release_certificates(id),
  to_release_id uuid not null references
    public.leghevo_application_release_certificates(id),
  generation bigint not null,
  reason_code text not null,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  created_by uuid null,
  constraint leghevo_release_event_environment_check
    check (environment_key in ('production', 'staging')),
  constraint leghevo_release_event_type_check
    check (event_type in (
      'certified', 'activated', 'activation_revalidated',
      'rollback_activated', 'affected', 'revalidated'
    )),
  constraint leghevo_release_event_generation_check
    check (generation >= 0),
  constraint leghevo_release_event_reason_check
    check (char_length(trim(reason_code)) between 3 and 120),
  constraint leghevo_release_event_details_check
    check (jsonb_typeof(details) = 'object')
);

create index if not exists leghevo_release_certificates_schema_idx
on public.leghevo_application_release_certificates(
  schema_fingerprint, application_version
);
create index if not exists leghevo_release_events_environment_created_idx
on public.leghevo_application_release_events(
  environment_key, created_at desc
);
create index if not exists leghevo_release_events_target_idx
on public.leghevo_application_release_events(to_release_id, generation desc);

alter table public.leghevo_application_release_certificates enable row level security;
alter table public.leghevo_application_release_heads enable row level security;
alter table public.leghevo_application_release_events enable row level security;

drop policy if exists leghevo_release_certificates_read_authenticated
on public.leghevo_application_release_certificates;
create policy leghevo_release_certificates_read_authenticated
on public.leghevo_application_release_certificates
for select to authenticated using (true);

drop policy if exists leghevo_release_heads_read_authenticated
on public.leghevo_application_release_heads;
create policy leghevo_release_heads_read_authenticated
on public.leghevo_application_release_heads
for select to authenticated using (true);

drop policy if exists leghevo_release_events_read_authenticated
on public.leghevo_application_release_events;
create policy leghevo_release_events_read_authenticated
on public.leghevo_application_release_events
for select to authenticated using (true);

revoke all on table public.leghevo_application_release_certificates
from public, anon, authenticated, service_role;
revoke all on table public.leghevo_application_release_heads
from public, anon, authenticated, service_role;
revoke all on table public.leghevo_application_release_events
from public, anon, authenticated, service_role;
grant select on table public.leghevo_application_release_certificates
to authenticated, service_role;
grant select on table public.leghevo_application_release_heads
to authenticated, service_role;
grant select on table public.leghevo_application_release_events
to authenticated, service_role;

create or replace function public.guard_leghevo_release_certificate_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if tg_op = 'INSERT'
    and coalesce(current_setting('leghevo.release_context', true), '')
      = 'allowed' then
    return new;
  end if;
  raise exception
    'Certificato release protetto: modifica diretta non consentita.';
end;
$function$;

create or replace function public.guard_leghevo_release_head_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if coalesce(current_setting('leghevo.release_context', true), '')
      = 'allowed' then
    if tg_op = 'DELETE' then return old; end if;
    return new;
  end if;
  raise exception
    'Testa release protetta: modifica diretta non consentita.';
end;
$function$;

create or replace function public.guard_leghevo_release_event_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if tg_op = 'INSERT'
    and coalesce(current_setting('leghevo.release_context', true), '')
      = 'allowed' then
    return new;
  end if;
  raise exception
    'Evento release protetto e append-only: modifica non consentita.';
end;
$function$;

drop trigger if exists leghevo_release_certificates_guard
on public.leghevo_application_release_certificates;
create trigger leghevo_release_certificates_guard
before insert or update or delete
on public.leghevo_application_release_certificates
for each row execute function public.guard_leghevo_release_certificate_v1();
alter table public.leghevo_application_release_certificates
  enable always trigger leghevo_release_certificates_guard;

drop trigger if exists leghevo_release_heads_guard
on public.leghevo_application_release_heads;
create trigger leghevo_release_heads_guard
before insert or update or delete
on public.leghevo_application_release_heads
for each row execute function public.guard_leghevo_release_head_v1();
alter table public.leghevo_application_release_heads
  enable always trigger leghevo_release_heads_guard;

drop trigger if exists leghevo_release_events_guard
on public.leghevo_application_release_events;
create trigger leghevo_release_events_guard
before insert or update or delete
on public.leghevo_application_release_events
for each row execute function public.guard_leghevo_release_event_v1();
alter table public.leghevo_application_release_events
  enable always trigger leghevo_release_events_guard;

revoke all on function public.guard_leghevo_release_certificate_v1()
from public, anon, authenticated, service_role;
revoke all on function public.guard_leghevo_release_head_v1()
from public, anon, authenticated, service_role;
revoke all on function public.guard_leghevo_release_event_v1()
from public, anon, authenticated, service_role;

create or replace function public.certify_leghevo_application_release_v1(
  p_application_version text,
  p_bundle_fingerprint text,
  p_min_supported_client_version text,
  p_max_supported_client_version text,
  p_request_id uuid,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_integrity jsonb;
  v_schema_fingerprint text;
  v_contract_fingerprint text;
  v_existing public.leghevo_application_release_certificates%rowtype;
  v_request_event public.leghevo_application_release_events%rowtype;
  v_release_id uuid;
  v_generation bigint := 0;
begin
  if p_request_id is null then
    raise exception 'request_id obbligatorio per certificare la release.';
  end if;
  if public.leghevo_semver_rank_v1(p_application_version) is null
    or public.leghevo_semver_rank_v1(p_min_supported_client_version) is null
    or public.leghevo_semver_rank_v1(p_max_supported_client_version) is null
    or public.leghevo_semver_rank_v1(p_min_supported_client_version)
       > public.leghevo_semver_rank_v1(p_application_version)
    or public.leghevo_semver_rank_v1(p_application_version)
       > public.leghevo_semver_rank_v1(p_max_supported_client_version) then
    raise exception 'Intervallo SemVer della release non valido.';
  end if;
  if lower(trim(coalesce(p_bundle_fingerprint, '')))
      !~ '^[0-9a-f]{64}$' then
    raise exception 'Fingerprint bundle non valida.';
  end if;
  if jsonb_typeof(coalesce(p_metadata, '{}'::jsonb)) <> 'object' then
    raise exception 'Metadata release non validi.';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('leghevo:application-release', 0));

  select event.* into v_request_event
  from public.leghevo_application_release_events event
  where event.request_id = p_request_id;
  if found then
    select certificate.* into strict v_existing
    from public.leghevo_application_release_certificates certificate
    where certificate.id = v_request_event.to_release_id;
    if v_request_event.event_type <> 'certified'
      or v_existing.application_version <> trim(p_application_version)
      or v_existing.bundle_fingerprint <> lower(trim(p_bundle_fingerprint))
      or v_existing.min_supported_client_version
        <> trim(p_min_supported_client_version)
      or v_existing.max_supported_client_version
        <> trim(p_max_supported_client_version)
      or v_existing.metadata <> coalesce(p_metadata, '{}'::jsonb) then
      raise exception
        'request_id già utilizzato per un''operazione release diversa.';
    end if;
    return jsonb_build_object(
      'releaseId', v_existing.id,
      'applicationVersion', v_existing.application_version,
      'contractFingerprint', v_existing.contract_fingerprint,
      'reused', true
    );
  end if;

  v_integrity := public.get_leghevo_application_integrity_model_v1();
  if not coalesce((v_integrity ->> 'protected')::boolean, false)
    or not coalesce((v_integrity ->> 'schemaCertified')::boolean, false) then
    raise exception
      'Sigillo applicativo non integro: certificazione release bloccata.';
  end if;
  v_schema_fingerprint := lower(v_integrity ->> 'schemaFingerprint');

  v_contract_fingerprint :=
    public.compute_leghevo_release_contract_fingerprint_v1(
      trim(p_application_version), lower(trim(p_bundle_fingerprint)),
      v_schema_fingerprint, trim(p_min_supported_client_version),
      trim(p_max_supported_client_version), 1);

  select certificate.* into v_existing
  from public.leghevo_application_release_certificates certificate
  where certificate.application_version = trim(p_application_version);

  if found then
    if v_existing.bundle_fingerprint <> lower(trim(p_bundle_fingerprint))
      or v_existing.schema_fingerprint <> v_schema_fingerprint
      or v_existing.min_supported_client_version
        <> trim(p_min_supported_client_version)
      or v_existing.max_supported_client_version
        <> trim(p_max_supported_client_version)
      or v_existing.contract_fingerprint <> v_contract_fingerprint
      or v_existing.metadata <> coalesce(p_metadata, '{}'::jsonb) then
      raise exception
        'La versione % è già certificata con un contratto diverso.',
        p_application_version;
    end if;
    return jsonb_build_object(
      'releaseId', v_existing.id,
      'applicationVersion', v_existing.application_version,
      'contractFingerprint', v_existing.contract_fingerprint,
      'reused', true
    );
  end if;

  select coalesce(max(head.generation), 0)
  into v_generation
  from public.leghevo_application_release_heads head;

  perform set_config('leghevo.release_context', 'allowed', true);
  insert into public.leghevo_application_release_certificates(
    application_version, release_contract_version, bundle_fingerprint,
    schema_model_key, schema_model_version, schema_fingerprint,
    min_supported_client_version, max_supported_client_version,
    contract_fingerprint, certified_by, metadata
  ) values (
    trim(p_application_version), 1, lower(trim(p_bundle_fingerprint)),
    'application_integrity_v1', 1, v_schema_fingerprint,
    trim(p_min_supported_client_version),
    trim(p_max_supported_client_version),
    v_contract_fingerprint, auth.uid(), coalesce(p_metadata, '{}'::jsonb)
  ) returning id into v_release_id;

  insert into public.leghevo_application_release_events(
    environment_key, request_id, event_type, from_release_id,
    to_release_id, generation, reason_code, details, created_by
  ) values (
    'production', p_request_id, 'certified', null,
    v_release_id, v_generation, 'release.certified',
    jsonb_build_object(
      'applicationVersion', trim(p_application_version),
      'contractFingerprint', v_contract_fingerprint
    ), auth.uid()
  );
  perform set_config('leghevo.release_context', '', true);

  return jsonb_build_object(
    'releaseId', v_release_id,
    'applicationVersion', trim(p_application_version),
    'contractFingerprint', v_contract_fingerprint,
    'reused', false
  );
exception when others then
  perform set_config('leghevo.release_context', '', true);
  raise;
end;
$function$;

revoke all on function public.certify_leghevo_application_release_v1(
  text, text, text, text, uuid, jsonb
) from public, anon, authenticated;
grant execute on function public.certify_leghevo_application_release_v1(
  text, text, text, text, uuid, jsonb
) to service_role;

create or replace function public.activate_leghevo_application_release_v1(
  p_environment_key text,
  p_application_version text,
  p_request_id uuid,
  p_reason text default 'release.activation'
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_environment text := lower(trim(coalesce(p_environment_key, '')));
  v_target public.leghevo_application_release_certificates%rowtype;
  v_head public.leghevo_application_release_heads%rowtype;
  v_current public.leghevo_application_release_certificates%rowtype;
  v_integrity jsonb;
  v_event public.leghevo_application_release_events%rowtype;
  v_generation bigint;
begin
  if v_environment not in ('production', 'staging') then
    raise exception 'Ambiente release non valido.';
  end if;
  if p_request_id is null then
    raise exception 'request_id obbligatorio per attivare la release.';
  end if;
  if char_length(trim(coalesce(p_reason, ''))) < 3 then
    raise exception 'Motivazione di attivazione non valida.';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('leghevo:application-release', 0));

  select certificate.* into strict v_target
  from public.leghevo_application_release_certificates certificate
  where certificate.application_version = trim(p_application_version);

  select event.* into v_event
  from public.leghevo_application_release_events event
  where event.request_id = p_request_id;
  if found then
    if v_event.environment_key <> v_environment
      or v_event.event_type not in ('activated', 'activation_revalidated')
      or v_event.to_release_id <> v_target.id
      or v_event.reason_code <> trim(p_reason) then
      raise exception
        'request_id già utilizzato per un''operazione release diversa.';
    end if;
    return jsonb_build_object(
      'activeReleaseId', v_event.to_release_id,
      'generation', v_event.generation,
      'reused', true
    );
  end if;

  v_integrity := public.get_leghevo_application_integrity_model_v1();
  if not coalesce((v_integrity ->> 'protected')::boolean, false)
    or v_target.schema_fingerprint
      <> lower(coalesce(v_integrity ->> 'schemaFingerprint', ''))
    or v_target.contract_fingerprint <>
      public.compute_leghevo_release_contract_fingerprint_v1(
        v_target.application_version, v_target.bundle_fingerprint,
        v_target.schema_fingerprint,
        v_target.min_supported_client_version,
        v_target.max_supported_client_version,
        v_target.release_contract_version) then
    raise exception
      'Release % incompatibile con il sigillo applicativo corrente.',
      p_application_version;
  end if;

  select head.* into v_head
  from public.leghevo_application_release_heads head
  where head.environment_key = v_environment
  for update;

  if found then
    select certificate.* into strict v_current
    from public.leghevo_application_release_certificates certificate
    where certificate.id = v_head.active_release_id;

    if v_head.active_release_id = v_target.id and v_head.state = 'affected' then
      raise exception
        'Release attiva affected: usare la riconciliazione prima dell''attivazione.';
    end if;
    if v_head.active_release_id <> v_target.id
      and public.leghevo_semver_rank_v1(v_target.application_version)
        < public.leghevo_semver_rank_v1(v_current.application_version) then
      raise exception
        'Attivazione retrograda bloccata: usare il rollback certificato.';
    end if;
  end if;

  if found and v_head.active_release_id = v_target.id
    and v_head.state in ('active', 'rollback') then
    perform set_config('leghevo.release_context', 'allowed', true);
    insert into public.leghevo_application_release_events(
      environment_key, request_id, event_type, from_release_id,
      to_release_id, generation, reason_code, details, created_by
    ) values (
      v_environment, p_request_id, 'activation_revalidated',
      v_head.previous_release_id,
      v_target.id, v_head.generation, trim(p_reason),
      jsonb_build_object('applicationVersion', v_target.application_version),
      auth.uid()
    );
    perform set_config('leghevo.release_context', '', true);
    return jsonb_build_object(
      'activeReleaseId', v_target.id,
      'generation', v_head.generation,
      'reused', false,
      'alreadyActive', true
    );
  end if;

  v_generation := coalesce(v_head.generation, 0) + 1;
  perform set_config('leghevo.release_context', 'allowed', true);
  if v_head.environment_key is null then
    insert into public.leghevo_application_release_heads(
      environment_key, active_release_id, previous_release_id,
      generation, state, safe_state, activated_by, last_request_id,
      rollback_count, affected_reason
    ) values (
      v_environment, v_target.id, null, v_generation, 'active', 'active',
      auth.uid(), p_request_id, 0, null
    );
  else
    update public.leghevo_application_release_heads
    set previous_release_id = active_release_id,
        active_release_id = v_target.id,
        generation = v_generation,
        state = 'active',
        safe_state = 'active',
        activated_at = now(),
        activated_by = auth.uid(),
        last_request_id = p_request_id,
        affected_reason = null,
        updated_at = now()
    where environment_key = v_environment;
  end if;

  insert into public.leghevo_application_release_events(
    environment_key, request_id, event_type, from_release_id,
    to_release_id, generation, reason_code, details, created_by
  ) values (
    v_environment, p_request_id, 'activated', v_head.active_release_id,
    v_target.id, v_generation, trim(p_reason),
    jsonb_build_object('applicationVersion', v_target.application_version),
    auth.uid()
  );
  perform set_config('leghevo.release_context', '', true);

  return jsonb_build_object(
    'activeReleaseId', v_target.id,
    'generation', v_generation,
    'reused', false,
    'alreadyActive', false
  );
exception
  when no_data_found then
    perform set_config('leghevo.release_context', '', true);
    raise exception 'Release % non certificata.', p_application_version;
  when others then
    perform set_config('leghevo.release_context', '', true);
    raise;
end;
$function$;

revoke all on function public.activate_leghevo_application_release_v1(
  text, text, uuid, text
) from public, anon, authenticated;
grant execute on function public.activate_leghevo_application_release_v1(
  text, text, uuid, text
) to service_role;

create or replace function public.rollback_leghevo_application_release_v1(
  p_environment_key text,
  p_target_application_version text,
  p_request_id uuid,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_environment text := lower(trim(coalesce(p_environment_key, '')));
  v_target public.leghevo_application_release_certificates%rowtype;
  v_head public.leghevo_application_release_heads%rowtype;
  v_active public.leghevo_application_release_certificates%rowtype;
  v_integrity jsonb;
  v_event public.leghevo_application_release_events%rowtype;
  v_generation bigint;
begin
  if v_environment not in ('production', 'staging') then
    raise exception 'Ambiente release non valido.';
  end if;
  if p_request_id is null then
    raise exception 'request_id obbligatorio per il rollback.';
  end if;
  if char_length(trim(coalesce(p_reason, ''))) < 12 then
    raise exception 'Motivazione del rollback troppo breve.';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('leghevo:application-release', 0));

  select certificate.* into strict v_target
  from public.leghevo_application_release_certificates certificate
  where certificate.application_version = trim(p_target_application_version);

  select event.* into v_event
  from public.leghevo_application_release_events event
  where event.request_id = p_request_id;
  if found then
    if v_event.environment_key <> v_environment
      or v_event.event_type <> 'rollback_activated'
      or v_event.to_release_id <> v_target.id
      or v_event.details ->> 'reason' is distinct from trim(p_reason) then
      raise exception
        'request_id già utilizzato per un''operazione release diversa.';
    end if;
    return jsonb_build_object(
      'activeReleaseId', v_event.to_release_id,
      'generation', v_event.generation,
      'reused', true
    );
  end if;

  select head.* into strict v_head
  from public.leghevo_application_release_heads head
  where head.environment_key = v_environment
  for update;
  select certificate.* into strict v_active
  from public.leghevo_application_release_certificates certificate
  where certificate.id = v_head.active_release_id;

  if v_head.state = 'affected' then
    raise exception
      'Rollback bloccato: la testa release è affected e richiede riconciliazione.';
  end if;
  if v_target.id = v_active.id then
    raise exception 'La release richiesta è già attiva.';
  end if;
  if public.leghevo_semver_rank_v1(v_target.application_version)
      >= public.leghevo_semver_rank_v1(v_active.application_version) then
    raise exception 'Il target non è una versione precedente certificata.';
  end if;

  v_integrity := public.get_leghevo_application_integrity_model_v1();
  if not coalesce((v_integrity ->> 'protected')::boolean, false)
    or v_target.schema_fingerprint
      <> lower(coalesce(v_integrity ->> 'schemaFingerprint', ''))
    or v_target.contract_fingerprint <>
      public.compute_leghevo_release_contract_fingerprint_v1(
        v_target.application_version, v_target.bundle_fingerprint,
        v_target.schema_fingerprint,
        v_target.min_supported_client_version,
        v_target.max_supported_client_version,
        v_target.release_contract_version) then
    raise exception
      'Rollback bloccato: target incompatibile con lo schema corrente.';
  end if;

  v_generation := v_head.generation + 1;
  perform set_config('leghevo.release_context', 'allowed', true);
  update public.leghevo_application_release_heads
  set previous_release_id = active_release_id,
      active_release_id = v_target.id,
      generation = v_generation,
      state = 'rollback',
      safe_state = 'rollback',
      activated_at = now(),
      activated_by = auth.uid(),
      last_request_id = p_request_id,
      rollback_count = rollback_count + 1,
      affected_reason = null,
      updated_at = now()
  where environment_key = v_environment;

  insert into public.leghevo_application_release_events(
    environment_key, request_id, event_type, from_release_id,
    to_release_id, generation, reason_code, details, created_by
  ) values (
    v_environment, p_request_id, 'rollback_activated', v_active.id,
    v_target.id, v_generation, 'release.rollback_activated',
    jsonb_build_object(
      'reason', trim(p_reason),
      'fromVersion', v_active.application_version,
      'toVersion', v_target.application_version
    ), auth.uid()
  );
  perform set_config('leghevo.release_context', '', true);

  return jsonb_build_object(
    'activeReleaseId', v_target.id,
    'generation', v_generation,
    'reused', false,
    'rollbackActive', true
  );
exception
  when no_data_found then
    perform set_config('leghevo.release_context', '', true);
    raise exception 'Testa o release target non disponibile.';
  when others then
    perform set_config('leghevo.release_context', '', true);
    raise;
end;
$function$;

revoke all on function public.rollback_leghevo_application_release_v1(
  text, text, uuid, text
) from public, anon, authenticated;
grant execute on function public.rollback_leghevo_application_release_v1(
  text, text, uuid, text
) to service_role;

create or replace function public.reconcile_leghevo_application_release_v1(
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
  v_head public.leghevo_application_release_heads%rowtype;
  v_active public.leghevo_application_release_certificates%rowtype;
  v_event public.leghevo_application_release_events%rowtype;
  v_integrity jsonb;
  v_contract_valid boolean := false;
  v_schema_valid boolean := false;
  v_consistent boolean := false;
  v_generation bigint;
  v_event_type text;
  v_reason text;
  v_next_state text;
  v_next_safe_state text;
begin
  if v_environment not in ('production', 'staging') then
    raise exception 'Ambiente release non valido.';
  end if;
  if p_request_id is null then
    raise exception 'request_id obbligatorio per la riconciliazione.';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('leghevo:application-release', 0));

  select head.* into strict v_head
  from public.leghevo_application_release_heads head
  where head.environment_key = v_environment
  for update;
  select certificate.* into strict v_active
  from public.leghevo_application_release_certificates certificate
  where certificate.id = v_head.active_release_id;

  select event.* into v_event
  from public.leghevo_application_release_events event
  where event.request_id = p_request_id;
  if found then
    if v_event.environment_key <> v_environment
      or v_event.event_type not in ('affected', 'revalidated')
      or v_event.to_release_id <> v_active.id then
      raise exception
        'request_id già utilizzato per un''operazione release diversa.';
    end if;
    return jsonb_build_object(
      'activeReleaseId', v_active.id,
      'generation', v_event.generation,
      'status', v_head.state,
      'reused', true
    );
  end if;

  v_integrity := public.get_leghevo_application_integrity_model_v1();
  v_schema_valid :=
    coalesce((v_integrity ->> 'protected')::boolean, false)
    and v_active.schema_fingerprint
      = lower(coalesce(v_integrity ->> 'schemaFingerprint', ''));
  v_contract_valid := v_active.contract_fingerprint =
    public.compute_leghevo_release_contract_fingerprint_v1(
      v_active.application_version, v_active.bundle_fingerprint,
      v_active.schema_fingerprint,
      v_active.min_supported_client_version,
      v_active.max_supported_client_version,
      v_active.release_contract_version);
  v_consistent := v_schema_valid and v_contract_valid;

  v_generation := v_head.generation;
  v_next_state := v_head.state;
  v_next_safe_state := v_head.safe_state;

  if v_consistent then
    v_event_type := 'revalidated';
    v_reason := 'release.revalidated';
    if v_head.state = 'affected' then
      v_generation := v_generation + 1;
      v_next_state := v_head.safe_state;
    end if;
  else
    v_event_type := 'affected';
    v_reason := case
      when not coalesce((v_integrity ->> 'protected')::boolean, false)
        then 'release.application_integrity_affected'
      when not v_schema_valid then 'release.schema_fingerprint_changed'
      else 'release.contract_fingerprint_changed'
    end;
    if v_head.state <> 'affected' then
      v_generation := v_generation + 1;
      v_next_safe_state := v_head.state;
      v_next_state := 'affected';
    end if;
  end if;

  perform set_config('leghevo.release_context', 'allowed', true);
  update public.leghevo_application_release_heads
  set generation = v_generation,
      state = v_next_state,
      safe_state = v_next_safe_state,
      last_request_id = p_request_id,
      affected_reason = case
        when v_next_state = 'affected' then v_reason
        else null
      end,
      updated_at = now()
  where environment_key = v_environment;

  insert into public.leghevo_application_release_events(
    environment_key, request_id, event_type, from_release_id,
    to_release_id, generation, reason_code, details, created_by
  ) values (
    v_environment, p_request_id, v_event_type, v_active.id,
    v_active.id, v_generation, v_reason,
    jsonb_build_object(
      'applicationVersion', v_active.application_version,
      'schemaValid', v_schema_valid,
      'contractValid', v_contract_valid,
      'state', v_next_state
    ), auth.uid()
  );
  perform set_config('leghevo.release_context', '', true);

  return jsonb_build_object(
    'activeReleaseId', v_active.id,
    'generation', v_generation,
    'status', v_next_state,
    'reasonCode', v_reason,
    'reused', false
  );
exception
  when no_data_found then
    perform set_config('leghevo.release_context', '', true);
    raise exception 'Testa release o certificato attivo non disponibile.';
  when others then
    perform set_config('leghevo.release_context', '', true);
    raise;
end;
$function$;

revoke all on function public.reconcile_leghevo_application_release_v1(
  text, uuid
) from public, anon, authenticated;
grant execute on function public.reconcile_leghevo_application_release_v1(
  text, uuid
) to service_role;

create or replace function public.get_leghevo_application_release_model_v1(
  p_environment_key text default 'production'
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_environment text := lower(trim(coalesce(p_environment_key, 'production')));
  v_head public.leghevo_application_release_heads%rowtype;
  v_active public.leghevo_application_release_certificates%rowtype;
  v_previous public.leghevo_application_release_certificates%rowtype;
  v_integrity jsonb;
  v_expected_contract text;
  v_schema_certified boolean := false;
  v_contract_valid boolean := false;
  v_protected boolean := false;
  v_reason text;
begin
  select head.* into v_head
  from public.leghevo_application_release_heads head
  where head.environment_key = v_environment;

  if found then
    select certificate.* into v_active
    from public.leghevo_application_release_certificates certificate
    where certificate.id = v_head.active_release_id;
    if v_head.previous_release_id is not null then
      select certificate.* into v_previous
      from public.leghevo_application_release_certificates certificate
      where certificate.id = v_head.previous_release_id;
    end if;
  end if;

  v_integrity := public.get_leghevo_application_integrity_model_v1();
  v_schema_certified :=
    coalesce((v_integrity ->> 'protected')::boolean, false)
    and v_active.schema_fingerprint is not null
    and v_active.schema_fingerprint
      = lower(coalesce(v_integrity ->> 'schemaFingerprint', ''));

  v_expected_contract :=
    public.compute_leghevo_release_contract_fingerprint_v1(
      v_active.application_version, v_active.bundle_fingerprint,
      v_active.schema_fingerprint, v_active.min_supported_client_version,
      v_active.max_supported_client_version,
      v_active.release_contract_version);
  v_contract_valid := v_active.contract_fingerprint is not null
    and v_active.contract_fingerprint = v_expected_contract;
  v_protected := v_head.environment_key is not null
    and v_schema_certified and v_contract_valid
    and v_head.state in ('active', 'rollback');

  v_reason := case
    when v_head.environment_key is null then 'release.head_missing'
    when v_active.id is null then 'release.certificate_missing'
    when not v_schema_certified then 'release.schema_fingerprint_changed'
    when not v_contract_valid then 'release.contract_fingerprint_changed'
    when v_head.state = 'affected' then coalesce(
      v_head.affected_reason, 'release.affected')
    when v_head.state = 'rollback' then 'release.rollback_active'
    else 'release.active'
  end;

  return jsonb_build_object(
    'protected', v_protected,
    'healthy', v_protected,
    'active', v_head.environment_key is not null,
    'status', case
      when not v_protected then 'affected'
      when v_head.state = 'rollback' then 'rollback'
      else 'active'
    end,
    'reasonCode', v_reason,
    'environment', v_environment,
    'activeReleaseId', v_active.id,
    'activeVersion', v_active.application_version,
    'previousReleaseId', v_previous.id,
    'previousVersion', v_previous.application_version,
    'minSupportedVersion', v_active.min_supported_client_version,
    'maxSupportedVersion', v_active.max_supported_client_version,
    'releaseGeneration', v_head.generation,
    'rollbackActive', v_head.safe_state = 'rollback',
    'schemaCertified', v_schema_certified,
    'fingerprintStable', v_contract_valid,
    'schemaFingerprint', v_active.schema_fingerprint,
    'bundleFingerprint', v_active.bundle_fingerprint,
    'contractFingerprint', v_active.contract_fingerprint,
    'certifiedAt', v_active.certified_at,
    'activatedAt', v_head.activated_at,
    'rollbackCount', coalesce(v_head.rollback_count, 0)
  );
end;
$function$;

revoke all on function public.get_leghevo_application_release_model_v1(text)
from public, anon;
grant execute on function public.get_leghevo_application_release_model_v1(text)
to authenticated, service_role;

create or replace function public.get_leghevo_client_compatibility_v1(
  p_application_version text,
  p_bundle_fingerprint text
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_model jsonb;
  v_head public.leghevo_application_release_heads%rowtype;
  v_active public.leghevo_application_release_certificates%rowtype;
  v_client public.leghevo_application_release_certificates%rowtype;
  v_version_rank bigint;
  v_headers jsonb := '{}'::jsonb;
  v_header_version text;
  v_header_bundle text;
  v_header_contract text;
  v_header_consistent boolean := true;
  v_compatible boolean := false;
  v_reason text;
begin
  begin
    v_headers := coalesce(
      nullif(current_setting('request.headers', true), ''),
      '{}')::jsonb;
  exception when others then
    v_headers := '{}'::jsonb;
  end;
  v_header_version := nullif(v_headers ->> 'x-leghevo-version', '');
  v_header_bundle := nullif(
    v_headers ->> 'x-leghevo-bundle-fingerprint', '');
  v_header_contract := nullif(
    v_headers ->> 'x-leghevo-release-contract', '');
  v_header_consistent :=
    (v_header_version is null and v_header_bundle is null
      and v_header_contract is null)
    or (
      v_header_version = trim(coalesce(p_application_version, ''))
      and lower(v_header_bundle) = lower(trim(coalesce(
        p_bundle_fingerprint, '')))
      and v_header_contract = '1'
    );

  v_model := public.get_leghevo_application_release_model_v1('production');
  select head.* into v_head
  from public.leghevo_application_release_heads head
  where head.environment_key = 'production';
  if found then
    select certificate.* into v_active
    from public.leghevo_application_release_certificates certificate
    where certificate.id = v_head.active_release_id;
  end if;

  v_version_rank := public.leghevo_semver_rank_v1(p_application_version);
  select certificate.* into v_client
  from public.leghevo_application_release_certificates certificate
  where certificate.application_version = trim(coalesce(p_application_version, ''))
    and certificate.bundle_fingerprint = lower(trim(coalesce(
      p_bundle_fingerprint, '')));

  v_compatible :=
    coalesce((v_model ->> 'protected')::boolean, false)
    and v_header_consistent
    and v_version_rank is not null
    and v_client.id is not null
    and v_client.schema_fingerprint = v_active.schema_fingerprint
    and v_version_rank
      between public.leghevo_semver_rank_v1(v_active.min_supported_client_version)
          and public.leghevo_semver_rank_v1(v_active.max_supported_client_version);

  v_reason := case
    when not coalesce((v_model ->> 'protected')::boolean, false)
      then 'release.model_affected'
    when not v_header_consistent then 'release.request_attestation_mismatch'
    when v_version_rank is null then 'release.client_version_invalid'
    when v_client.id is null then 'release.bundle_not_certified'
    when v_client.schema_fingerprint <> v_active.schema_fingerprint
      then 'release.schema_incompatible'
    when v_version_rank
      < public.leghevo_semver_rank_v1(v_active.min_supported_client_version)
      then 'release.update_required'
    when v_version_rank
      > public.leghevo_semver_rank_v1(v_active.max_supported_client_version)
      then 'release.client_ahead_of_server'
    else 'release.compatible'
  end;

  return jsonb_build_object(
    'compatible', v_compatible,
    'protected', coalesce((v_model ->> 'protected')::boolean, false),
    'reasonCode', v_reason,
    'applicationVersion', trim(coalesce(p_application_version, '')),
    'activeVersion', v_active.application_version,
    'minSupportedVersion', v_active.min_supported_client_version,
    'maxSupportedVersion', v_active.max_supported_client_version,
    'releaseGeneration', v_head.generation,
    'rollbackActive', v_head.safe_state = 'rollback',
    'requestAttested', v_header_consistent,
    'checkedAt', now()
  );
end;
$function$;

revoke all on function public.get_leghevo_client_compatibility_v1(text, text)
from public;
grant execute on function public.get_leghevo_client_compatibility_v1(text, text)
to anon, authenticated, service_role;

-- Endpoint terminali v33/v12/v22: espongono il contratto senza rimuovere i
-- fallback precedenti.
create or replace function public.get_league_provider_sync_health_v33(
  p_league_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_base jsonb;
  v_release jsonb;
begin
  v_base := public.get_league_provider_sync_health_v32(p_league_id);
  v_release := public.get_leghevo_application_release_model_v1('production');
  return v_base || jsonb_build_object(
    'protected', coalesce((v_base ->> 'protected')::boolean, false)
      and coalesce((v_release ->> 'protected')::boolean, false),
    'healthy', coalesce((v_base ->> 'healthy')::boolean, false)
      and coalesce((v_release ->> 'healthy')::boolean, false),
    'applicationReleaseModel', v_release
  );
end;
$function$;
revoke all on function public.get_league_provider_sync_health_v33(uuid)
from public, anon, service_role;
grant execute on function public.get_league_provider_sync_health_v33(uuid)
to authenticated;

create or replace function public.get_league_season_state_v12(p_league_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_base jsonb;
  v_release jsonb;
begin
  v_base := public.get_league_season_state_v11(p_league_id);
  v_release := public.get_leghevo_application_release_model_v1('production');
  return v_base || jsonb_build_object(
    'applicationReleaseProtected',
      coalesce((v_release ->> 'protected')::boolean, false),
    'applicationReleaseStatus', v_release ->> 'status',
    'applicationReleaseVersion', v_release ->> 'activeVersion',
    'applicationReleaseGeneration', v_release -> 'releaseGeneration'
  );
end;
$function$;
revoke all on function public.get_league_season_state_v12(uuid)
from public, anon;
grant execute on function public.get_league_season_state_v12(uuid)
to authenticated;

create or replace function public.get_league_management_state_v22(
  p_league_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_base jsonb;
  v_release jsonb;
  v_checks jsonb;
begin
  v_base := public.get_league_management_state_v21(p_league_id);
  v_release := public.get_leghevo_application_release_model_v1('production');
  v_checks := coalesce(v_base -> 'checks', '{}'::jsonb)
    || jsonb_build_object(
      'applicationReleaseProtected',
        coalesce((v_release ->> 'protected')::boolean, false)
    );
  return v_base || jsonb_build_object(
    'applicationReleaseProtected',
      coalesce((v_release ->> 'protected')::boolean, false),
    'applicationReleaseStatus', v_release ->> 'status',
    'applicationReleaseVersion', v_release ->> 'activeVersion',
    'applicationReleaseGeneration', v_release -> 'releaseGeneration',
    'applicationReleaseRollbackActive',
      coalesce((v_release ->> 'rollbackActive')::boolean, false),
    'checks', v_checks
  );
end;
$function$;
revoke all on function public.get_league_management_state_v22(uuid)
from public, anon;
grant execute on function public.get_league_management_state_v22(uuid)
to authenticated;

-- Pubblicazione Realtime delle sole teste e degli eventi; i certificati sono
-- immutabili e consultabili tramite RPC.
do $realtime$
declare
  v_table_name text;
begin
  if exists (
    select 1 from pg_catalog.pg_publication publication
    where publication.pubname = 'supabase_realtime'
  ) then
    foreach v_table_name in array array[
      'leghevo_application_release_heads',
      'leghevo_application_release_events'
    ] loop
      if not exists (
        select 1 from pg_catalog.pg_publication_tables publication_table
        where publication_table.pubname = 'supabase_realtime'
          and publication_table.schemaname = 'public'
          and publication_table.tablename = v_table_name
      ) then
        execute format(
          'alter publication supabase_realtime add table public.%I',
          v_table_name);
      end if;
    end loop;
  end if;
end;
$realtime$;

-- Certifica la release precedente come target di rollback additivo e la nuova
-- release come testa di produzione. I request_id costanti rendono il backfill
-- completamente idempotente.
do $seed$
declare
  v_outcome jsonb;
begin
  v_outcome := public.certify_leghevo_application_release_v1(
    '0.62.33',
    'ff371500e9bb2d145c065d56866f88a9920c2f5e8855de725632fd08b41fb1f0',
    '0.62.33', '0.62.33',
    '62330000-0000-4000-8000-000000000001'::uuid,
    jsonb_build_object('baseline', true, 'sourceMigration', 137)
  );
  v_outcome := public.certify_leghevo_application_release_v1(
    '0.62.34',
    '30b6c5308745cd0261ef098a0363a0c29f1b4e33123e3d9619028796b300dfb3',
    '0.62.33', '0.62.34',
    '62340000-0000-4000-8000-000000000001'::uuid,
    jsonb_build_object('baseline', false, 'sourceMigration', 138)
  );
  v_outcome := public.activate_leghevo_application_release_v1(
    'production', '0.62.34',
    '62340000-0000-4000-8000-000000000002'::uuid,
    'release.production_activation'
  );
end;
$seed$;

-- Diagnostica finale della v0.62.34: esattamente venti booleani.
create or replace function public.get_leghevo_release_deployment_integrity_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_predecessor jsonb;
  v_model jsonb;
  v_compatibility jsonb;
  v_certificate public.leghevo_application_release_certificates%rowtype;
  v_head public.leghevo_application_release_heads%rowtype;
  v_certify_def text := coalesce(pg_catalog.pg_get_functiondef(
    to_regprocedure('public.certify_leghevo_application_release_v1(text,text,text,text,uuid,jsonb)')), '');
  v_activate_def text := coalesce(pg_catalog.pg_get_functiondef(
    to_regprocedure('public.activate_leghevo_application_release_v1(text,text,uuid,text)')), '');
  v_rollback_def text := coalesce(pg_catalog.pg_get_functiondef(
    to_regprocedure('public.rollback_leghevo_application_release_v1(text,text,uuid,text)')), '');
  v_reconcile_def text := coalesce(pg_catalog.pg_get_functiondef(
    to_regprocedure('public.reconcile_leghevo_application_release_v1(text,uuid)')), '');
  v_compatibility_def text := coalesce(pg_catalog.pg_get_functiondef(
    to_regprocedure('public.get_leghevo_client_compatibility_v1(text,text)')), '');
begin
  v_predecessor := public.get_leghevo_application_integrity_seal_v1();
  v_model := public.get_leghevo_application_release_model_v1('production');
  v_compatibility := public.get_leghevo_client_compatibility_v1(
    '0.62.34', '30b6c5308745cd0261ef098a0363a0c29f1b4e33123e3d9619028796b300dfb3');
  select head.* into v_head
  from public.leghevo_application_release_heads head
  where head.environment_key = 'production';
  if found then
    select certificate.* into v_certificate
    from public.leghevo_application_release_certificates certificate
    where certificate.id = v_head.active_release_id;
  end if;

  return jsonb_build_object(
    'predecessor_ready',
      public.provider_reliability_diagnostic_all_true_v1(v_predecessor),
    'certificate_table_ready',
      to_regclass('public.leghevo_application_release_certificates') is not null,
    'head_table_ready',
      to_regclass('public.leghevo_application_release_heads') is not null,
    'event_table_ready',
      to_regclass('public.leghevo_application_release_events') is not null,
    'columns_ready',
      (select count(*) from information_schema.columns column_row
       where column_row.table_schema = 'public'
         and column_row.table_name = 'leghevo_application_release_certificates'
         and column_row.column_name in (
           'application_version','bundle_fingerprint','schema_fingerprint',
           'min_supported_client_version','max_supported_client_version',
           'contract_fingerprint')) = 6
      and (select count(*) from information_schema.columns column_row
       where column_row.table_schema = 'public'
         and column_row.table_name = 'leghevo_application_release_heads'
         and column_row.column_name in (
           'active_release_id','previous_release_id','generation','state',
           'safe_state','last_request_id','rollback_count')) = 7,
    'constraints_ready',
      (select count(*) from pg_catalog.pg_constraint constraint_row
       where constraint_row.conrelid in (
         'public.leghevo_application_release_certificates'::regclass,
         'public.leghevo_application_release_heads'::regclass,
         'public.leghevo_application_release_events'::regclass)
         and constraint_row.contype in ('p','u','f','c')) >= 20,
    'indexes_ready',
      to_regclass('public.leghevo_release_certificates_schema_idx') is not null
      and to_regclass('public.leghevo_release_events_environment_created_idx') is not null
      and to_regclass('public.leghevo_release_events_target_idx') is not null,
    'rls_ready',
      coalesce((select relation_row.relrowsecurity from pg_catalog.pg_class relation_row
        where relation_row.oid = 'public.leghevo_application_release_certificates'::regclass), false)
      and coalesce((select relation_row.relrowsecurity from pg_catalog.pg_class relation_row
        where relation_row.oid = 'public.leghevo_application_release_heads'::regclass), false)
      and coalesce((select relation_row.relrowsecurity from pg_catalog.pg_class relation_row
        where relation_row.oid = 'public.leghevo_application_release_events'::regclass), false),
    'direct_write_blocked',
      not has_table_privilege('authenticated',
        'public.leghevo_application_release_certificates','INSERT')
      and not has_table_privilege('authenticated',
        'public.leghevo_application_release_heads','UPDATE')
      and not has_table_privilege('authenticated',
        'public.leghevo_application_release_events','DELETE')
      and not has_table_privilege('service_role',
        'public.leghevo_application_release_certificates','INSERT')
      and not has_table_privilege('service_role',
        'public.leghevo_application_release_heads','UPDATE'),
    'immutable_certificates_ready',
      exists(select 1 from pg_catalog.pg_trigger trigger_row
        where trigger_row.tgrelid = 'public.leghevo_application_release_certificates'::regclass
          and trigger_row.tgname = 'leghevo_release_certificates_guard'
          and trigger_row.tgenabled = 'A' and not trigger_row.tgisinternal),
    'immutable_events_ready',
      exists(select 1 from pg_catalog.pg_trigger trigger_row
        where trigger_row.tgrelid = 'public.leghevo_application_release_events'::regclass
          and trigger_row.tgname = 'leghevo_release_events_guard'
          and trigger_row.tgenabled = 'A' and not trigger_row.tgisinternal),
    'head_guard_ready',
      exists(select 1 from pg_catalog.pg_trigger trigger_row
        where trigger_row.tgrelid = 'public.leghevo_application_release_heads'::regclass
          and trigger_row.tgname = 'leghevo_release_heads_guard'
          and trigger_row.tgenabled = 'A' and not trigger_row.tgisinternal),
    'semver_helper_ready',
      public.leghevo_semver_rank_v1('0.62.33')
        < public.leghevo_semver_rank_v1('0.62.34')
      and public.leghevo_semver_rank_v1('invalid') is null,
    'contract_fingerprint_ready',
      length(public.compute_leghevo_release_contract_fingerprint_v1(
        '0.62.34','30b6c5308745cd0261ef098a0363a0c29f1b4e33123e3d9619028796b300dfb3',
        v_certificate.schema_fingerprint,'0.62.33','0.62.34',1)) = 32
      and v_certificate.contract_fingerprint =
        public.compute_leghevo_release_contract_fingerprint_v1(
          v_certificate.application_version, v_certificate.bundle_fingerprint,
          v_certificate.schema_fingerprint,
          v_certificate.min_supported_client_version,
          v_certificate.max_supported_client_version,
          v_certificate.release_contract_version),
    'certification_rpc_ready',
      to_regprocedure('public.certify_leghevo_application_release_v1(text,text,text,text,uuid,jsonb)') is not null
      and position('pg_advisory_xact_lock' in v_certify_def) > 0
      and not has_function_privilege('authenticated',
        'public.certify_leghevo_application_release_v1(text,text,text,text,uuid,jsonb)','EXECUTE'),
    'activation_rpc_ready',
      to_regprocedure('public.activate_leghevo_application_release_v1(text,text,uuid,text)') is not null
      and to_regprocedure('public.reconcile_leghevo_application_release_v1(text,uuid)') is not null
      and position('pg_advisory_xact_lock' in v_activate_def) > 0
      and position('Attivazione retrograda bloccata' in v_activate_def) > 0
      and position('Release attiva affected' in v_activate_def) > 0
      and position('pg_advisory_xact_lock' in v_reconcile_def) > 0
      and not has_function_privilege('authenticated',
        'public.activate_leghevo_application_release_v1(text,text,uuid,text)','EXECUTE')
      and not has_function_privilege('authenticated',
        'public.reconcile_leghevo_application_release_v1(text,uuid)','EXECUTE'),
    'rollback_rpc_ready',
      to_regprocedure('public.rollback_leghevo_application_release_v1(text,text,uuid,text)') is not null
      and position('target non è una versione precedente' in v_rollback_def) > 0
      and not has_function_privilege('authenticated',
        'public.rollback_leghevo_application_release_v1(text,text,uuid,text)','EXECUTE'),
    'compatibility_rpc_ready',
      to_regprocedure('public.get_leghevo_client_compatibility_v1(text,text)') is not null
      and position('request.headers' in v_compatibility_def) > 0
      and position('x-leghevo-release-contract' in v_compatibility_def) > 0
      and has_function_privilege('anon',
        'public.get_leghevo_client_compatibility_v1(text,text)','EXECUTE')
      and has_function_privilege('authenticated',
        'public.get_leghevo_client_compatibility_v1(text,text)','EXECUTE'),
    'endpoint_chain_ready',
      to_regprocedure('public.get_league_provider_sync_health_v33(uuid)') is not null
      and to_regprocedure('public.get_league_season_state_v12(uuid)') is not null
      and to_regprocedure('public.get_league_management_state_v22(uuid)') is not null
      and has_function_privilege('authenticated',
        'public.get_league_provider_sync_health_v33(uuid)','EXECUTE')
      and has_function_privilege('authenticated',
        'public.get_league_season_state_v12(uuid)','EXECUTE')
      and has_function_privilege('authenticated',
        'public.get_league_management_state_v22(uuid)','EXECUTE'),
    'active_release_ready',
      coalesce((v_model ->> 'protected')::boolean, false)
      and coalesce((v_model ->> 'activeVersion') = '0.62.34', false)
      and coalesce((v_model ->> 'releaseGeneration')::bigint, 0) >= 1
      and coalesce((v_compatibility ->> 'compatible')::boolean, false)
  );
end;
$function$;

revoke all on function public.get_leghevo_release_deployment_integrity_v1()
from public, anon, authenticated;
grant execute on function public.get_leghevo_release_deployment_integrity_v1()
to service_role;

-- L'esecuzione resta atomica: un singolo false annulla l'intera migrazione.
do $validation$
declare
  v_integrity jsonb;
  v_false text[];
begin
  v_integrity := public.get_leghevo_release_deployment_integrity_v1();
  select array_agg(item.key order by item.key)
  into v_false
  from pg_catalog.jsonb_each(v_integrity) item
  where pg_catalog.jsonb_typeof(item.value) is distinct from 'boolean'
     or item.value is distinct from 'true'::jsonb;

  if (select count(*) from pg_catalog.jsonb_each(v_integrity)) <> 20
    or cardinality(v_false) > 0 then
    raise exception
      'Validazione v0.62.34 non superata: %. Dettaglio: %',
      coalesce(array_to_string(v_false, ', '),
        'numero di controlli diverso da 20'),
      v_integrity;
  end if;
end;
$validation$;

commit;

with integrity as materialized (
  select public.get_leghevo_release_deployment_integrity_v1() as value
)
select
  (value ->> 'predecessor_ready')::boolean as predecessor_ready,
  (value ->> 'certificate_table_ready')::boolean as certificate_table_ready,
  (value ->> 'head_table_ready')::boolean as head_table_ready,
  (value ->> 'event_table_ready')::boolean as event_table_ready,
  (value ->> 'columns_ready')::boolean as columns_ready,
  (value ->> 'constraints_ready')::boolean as constraints_ready,
  (value ->> 'indexes_ready')::boolean as indexes_ready,
  (value ->> 'rls_ready')::boolean as rls_ready,
  (value ->> 'direct_write_blocked')::boolean as direct_write_blocked,
  (value ->> 'immutable_certificates_ready')::boolean as immutable_certificates_ready,
  (value ->> 'immutable_events_ready')::boolean as immutable_events_ready,
  (value ->> 'head_guard_ready')::boolean as head_guard_ready,
  (value ->> 'semver_helper_ready')::boolean as semver_helper_ready,
  (value ->> 'contract_fingerprint_ready')::boolean as contract_fingerprint_ready,
  (value ->> 'certification_rpc_ready')::boolean as certification_rpc_ready,
  (value ->> 'activation_rpc_ready')::boolean as activation_rpc_ready,
  (value ->> 'rollback_rpc_ready')::boolean as rollback_rpc_ready,
  (value ->> 'compatibility_rpc_ready')::boolean as compatibility_rpc_ready,
  (value ->> 'endpoint_chain_ready')::boolean as endpoint_chain_ready,
  (value ->> 'active_release_ready')::boolean as active_release_ready
from integrity;
