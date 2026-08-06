-- LEGHEVO v0.62.13 · Completezza e coerenza delle consegne provider
-- Migrazione interna: database/117_provider_delivery_completeness_safety.sql
--
-- Obiettivi:
-- - certificare che ogni risposta dichiari esattamente i record realmente ricevuti;
-- - impedire pagine mancanti, fuori ordine, duplicate o con totale variabile;
-- - impedire la duplicazione della stessa entità tra unità dello stesso run;
-- - subordinare la chiusura completed a un certificato di consegna completo;
-- - conservare solo impronte SHA-256 e metadati, mai payload o identificativi grezzi;
-- - terminare con una diagnostica strutturale di esattamente 20 controlli.

begin;

-- Preflight esplicito delle sole dipendenze realmente utilizzate.
do $preflight$
declare
  v_missing text[] := array[]::text[];
  v_expected record;
begin
  for v_expected in
    select *
    from (values
      ('leagues', 'id'),
      ('leagues', 'owner_id'),
      ('provider_sync_runs', 'id'),
      ('provider_sync_runs', 'provider'),
      ('provider_sync_runs', 'sync_type'),
      ('provider_sync_runs', 'status'),
      ('provider_sync_runs', 'revision'),
      ('provider_sync_runs', 'records_processed'),
      ('provider_recovery_requests', 'id'),
      ('provider_recovery_requests', 'league_id'),
      ('provider_recovery_requests', 'recovery_run_id'),
      ('provider_sync_worker_leases', 'run_id'),
      ('provider_sync_worker_leases', 'recovery_request_id'),
      ('provider_sync_worker_leases', 'league_id'),
      ('provider_sync_worker_leases', 'lease_token'),
      ('provider_sync_worker_leases', 'lease_epoch'),
      ('provider_sync_worker_leases', 'status'),
      ('provider_sync_worker_leases', 'lease_expires_at')
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

  if to_regprocedure('auth.uid()') is null then
    v_missing := array_append(v_missing, 'function auth.uid()');
  end if;
  if to_regprocedure('gen_random_uuid()') is null then
    v_missing := array_append(v_missing, 'function gen_random_uuid()');
  end if;
  if to_regprocedure('public.is_league_admin(uuid)') is null then
    v_missing := array_append(v_missing, 'function public.is_league_admin(uuid)');
  end if;
  if to_regprocedure(
    'public.assert_provider_sync_worker_lease_v1(uuid,uuid)'
  ) is null then
    v_missing := array_append(
      v_missing,
      'function public.assert_provider_sync_worker_lease_v1(uuid,uuid)'
    );
  end if;
  if to_regprocedure(
    'public.finish_provider_sync_run_guarded_v2(uuid,text,integer,text,bigint,uuid)'
  ) is null then
    v_missing := array_append(
      v_missing,
      'function public.finish_provider_sync_run_guarded_v2(uuid,text,integer,text,bigint,uuid)'
    );
  end if;
  if to_regprocedure(
    'public.get_league_provider_sync_health_v11(uuid)'
  ) is null then
    v_missing := array_append(
      v_missing,
      'function public.get_league_provider_sync_health_v11(uuid)'
    );
  end if;
  if to_regprocedure(
    'public.get_provider_payload_contract_quarantine_integrity_v1()'
  ) is null then
    v_missing := array_append(
      v_missing,
      'function public.get_provider_payload_contract_quarantine_integrity_v1()'
    );
  end if;
  if to_regprocedure(
    'public.provider_recovery_retry_policy_v1(text,integer,text)'
  ) is null then
    v_missing := array_append(
      v_missing,
      'function public.provider_recovery_retry_policy_v1(text,integer,text)'
    );
  end if;

  if not exists (
    select 1 from pg_catalog.pg_roles role_row where role_row.rolname = 'anon'
  ) then
    v_missing := array_append(v_missing, 'role anon');
  end if;
  if not exists (
    select 1 from pg_catalog.pg_roles role_row where role_row.rolname = 'authenticated'
  ) then
    v_missing := array_append(v_missing, 'role authenticated');
  end if;
  if not exists (
    select 1 from pg_catalog.pg_roles role_row where role_row.rolname = 'service_role'
  ) then
    v_missing := array_append(v_missing, 'role service_role');
  end if;

  if coalesce(array_length(v_missing, 1), 0) > 0 then
    raise exception
      'Preflight v0.62.13 non superato. Oggetti mancanti: %',
      array_to_string(v_missing, '; ');
  end if;
end;
$preflight$;

create table if not exists public.provider_sync_delivery_certificates (
  id uuid primary key default gen_random_uuid(),
  run_id uuid not null,
  recovery_request_id uuid,
  league_id uuid,
  provider text not null,
  sync_type text not null,
  status text not null default 'collecting',
  expected_unit_count integer,
  observed_unit_count integer not null default 0,
  observed_record_count integer not null default 0,
  unique_entity_count integer not null default 0,
  last_unit_no integer,
  manifest_fingerprint text not null default md5(''),
  summary text not null default 'Consegna provider in acquisizione.',
  run_revision bigint not null,
  lease_epoch bigint not null,
  revision bigint not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  certified_at timestamptz,
  rejected_at timestamptz,
  constraint provider_sync_delivery_certificates_run_fk
    foreign key (run_id) references public.provider_sync_runs(id) on delete restrict,
  constraint provider_sync_delivery_certificates_request_fk
    foreign key (recovery_request_id)
    references public.provider_recovery_requests(id) on delete set null,
  constraint provider_sync_delivery_certificates_league_fk
    foreign key (league_id) references public.leagues(id) on delete set null,
  constraint provider_sync_delivery_certificates_run_uidx unique (run_id),
  constraint provider_sync_delivery_certificates_id_run_uidx unique (id, run_id),
  constraint provider_sync_delivery_certificates_provider_check
    check (provider = lower(trim(provider)) and length(provider) between 1 and 60),
  constraint provider_sync_delivery_certificates_sync_type_check
    check (sync_type in ('sync-season-players','sync-fixtures','sync-fixture-players')),
  constraint provider_sync_delivery_certificates_status_check
    check (status in ('collecting','certified','rejected')),
  constraint provider_sync_delivery_certificates_counts_check
    check (
      (expected_unit_count is null or expected_unit_count between 1 and 10000)
      and observed_unit_count between 0 and 10000
      and observed_record_count between 0 and 1000000
      and unique_entity_count between 0 and 1000000
      and (last_unit_no is null or last_unit_no between 1 and 10000)
    ),
  constraint provider_sync_delivery_certificates_fingerprint_check
    check (manifest_fingerprint ~ '^[0-9a-f]{32}$'),
  constraint provider_sync_delivery_certificates_summary_check
    check (length(summary) between 1 and 500 and summary !~ E'[\\r\\n]'),
  constraint provider_sync_delivery_certificates_revision_check
    check (run_revision > 0 and lease_epoch > 0 and revision > 0),
  constraint provider_sync_delivery_certificates_terminal_check
    check (
      (status = 'collecting' and certified_at is null and rejected_at is null)
      or (status = 'certified' and certified_at is not null and rejected_at is null)
      or (status = 'rejected' and certified_at is null and rejected_at is not null)
    )
);

create table if not exists public.provider_sync_delivery_units (
  id uuid primary key default gen_random_uuid(),
  certificate_id uuid not null,
  run_id uuid not null,
  unit_no integer not null,
  expected_unit_count integer not null,
  declared_current integer not null,
  declared_total integer not null,
  declared_results integer not null,
  observed_results integer not null,
  records_processed integer not null,
  unique_entity_count integer not null,
  entity_manifest_fingerprint text not null,
  recorded_at timestamptz not null default now(),
  constraint provider_sync_delivery_units_certificate_run_fk
    foreign key (certificate_id, run_id)
    references public.provider_sync_delivery_certificates(id, run_id) on delete restrict,
  constraint provider_sync_delivery_units_run_fk
    foreign key (run_id) references public.provider_sync_runs(id) on delete restrict,
  constraint provider_sync_delivery_units_run_unit_uidx unique (run_id, unit_no),
  constraint provider_sync_delivery_units_counts_check
    check (
      unit_no between 1 and 10000
      and expected_unit_count between 1 and 10000
      and unit_no <= expected_unit_count
      and declared_current between 0 and 10000
      and declared_total between 0 and 10000
      and declared_results between 0 and 1000000
      and observed_results between 0 and 1000000
      and declared_results = observed_results
      and records_processed between 0 and 1000000
      and unique_entity_count between 0 and 1000000
      and unique_entity_count = records_processed
    ),
  constraint provider_sync_delivery_units_fingerprint_check
    check (entity_manifest_fingerprint ~ '^[0-9a-f]{64}$')
);

create table if not exists public.provider_sync_delivery_entities (
  id uuid primary key default gen_random_uuid(),
  certificate_id uuid not null,
  run_id uuid not null,
  unit_no integer not null,
  entity_fingerprint text not null,
  recorded_at timestamptz not null default now(),
  constraint provider_sync_delivery_entities_certificate_run_fk
    foreign key (certificate_id, run_id)
    references public.provider_sync_delivery_certificates(id, run_id) on delete restrict,
  constraint provider_sync_delivery_entities_run_fk
    foreign key (run_id) references public.provider_sync_runs(id) on delete restrict,
  constraint provider_sync_delivery_entities_unit_fk
    foreign key (run_id, unit_no)
    references public.provider_sync_delivery_units(run_id, unit_no) on delete restrict,
  constraint provider_sync_delivery_entities_run_entity_uidx
    unique (run_id, entity_fingerprint),
  constraint provider_sync_delivery_entities_unit_check
    check (unit_no between 1 and 10000),
  constraint provider_sync_delivery_entities_fingerprint_check
    check (entity_fingerprint ~ '^[0-9a-f]{64}$')
);

create index if not exists provider_sync_delivery_certificates_league_idx
  on public.provider_sync_delivery_certificates (league_id, updated_at desc);
create index if not exists provider_sync_delivery_certificates_status_idx
  on public.provider_sync_delivery_certificates (status, updated_at desc);
create index if not exists provider_sync_delivery_units_certificate_idx
  on public.provider_sync_delivery_units (certificate_id, unit_no);
create index if not exists provider_sync_delivery_entities_certificate_idx
  on public.provider_sync_delivery_entities (certificate_id, unit_no);

alter table public.provider_sync_delivery_certificates enable row level security;
alter table public.provider_sync_delivery_certificates replica identity full;
alter table public.provider_sync_delivery_units enable row level security;
alter table public.provider_sync_delivery_entities enable row level security;

revoke all on table public.provider_sync_delivery_certificates
from public, anon, authenticated;
revoke all on table public.provider_sync_delivery_units
from public, anon, authenticated;
revoke all on table public.provider_sync_delivery_entities
from public, anon, authenticated;
grant select on table public.provider_sync_delivery_certificates to authenticated;
grant all on table public.provider_sync_delivery_certificates to service_role;
grant all on table public.provider_sync_delivery_units to service_role;
grant all on table public.provider_sync_delivery_entities to service_role;

drop policy if exists provider_sync_delivery_certificates_read_directors
on public.provider_sync_delivery_certificates;
create policy provider_sync_delivery_certificates_read_directors
on public.provider_sync_delivery_certificates
for select to authenticated
using (
  (
    league_id is not null
    and exists (
      select 1
      from public.leagues league_row
      where league_row.id = provider_sync_delivery_certificates.league_id
        and (
          league_row.owner_id = auth.uid()
          or public.is_league_admin(league_row.id)
        )
    )
  )
  or (
    league_id is null
    and exists (
      select 1
      from public.leagues league_row
      where league_row.owner_id = auth.uid()
        or public.is_league_admin(league_row.id)
    )
  )
);

create or replace function public.prevent_provider_sync_delivery_detail_mutation_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  raise exception 'Dettaglio della consegna provider immutabile.';
end;
$$;

revoke all on function public.prevent_provider_sync_delivery_detail_mutation_v1()
from public, anon, authenticated;

drop trigger if exists provider_sync_delivery_units_immutable
on public.provider_sync_delivery_units;
create trigger provider_sync_delivery_units_immutable
before update or delete on public.provider_sync_delivery_units
for each row execute function public.prevent_provider_sync_delivery_detail_mutation_v1();

drop trigger if exists provider_sync_delivery_entities_immutable
on public.provider_sync_delivery_entities;
create trigger provider_sync_delivery_entities_immutable
before update or delete on public.provider_sync_delivery_entities
for each row execute function public.prevent_provider_sync_delivery_detail_mutation_v1();

create or replace function public.prepare_provider_sync_delivery_certificate_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    new.provider := lower(trim(coalesce(new.provider, '')));
    new.sync_type := lower(trim(coalesce(new.sync_type, '')));
    new.status := 'collecting';
    new.observed_unit_count := 0;
    new.observed_record_count := 0;
    new.unique_entity_count := 0;
    new.last_unit_no := null;
    new.manifest_fingerprint := md5('');
    new.summary := 'Consegna provider in acquisizione.';
    new.revision := 1;
    new.created_at := coalesce(new.created_at, now());
    new.updated_at := new.created_at;
    new.certified_at := null;
    new.rejected_at := null;
    return new;
  end if;

  if row(
    new.run_id, new.recovery_request_id, new.league_id, new.provider,
    new.sync_type, new.run_revision, new.lease_epoch, new.created_at
  ) is distinct from row(
    old.run_id, old.recovery_request_id, old.league_id, old.provider,
    old.sync_type, old.run_revision, old.lease_epoch, old.created_at
  ) then
    raise exception 'Identità del certificato di consegna provider non modificabile.';
  end if;

  if old.status in ('certified','rejected') then
    if new is not distinct from old then
      return old;
    end if;
    raise exception 'Certificato di consegna provider già concluso e immutabile.';
  end if;
  if new.status not in ('collecting','certified','rejected') then
    raise exception 'Transizione del certificato di consegna provider non valida.';
  end if;
  if new.observed_unit_count < old.observed_unit_count
    or new.observed_record_count < old.observed_record_count
    or new.unique_entity_count < old.unique_entity_count then
    raise exception 'Contatori della consegna provider non possono diminuire.';
  end if;

  new.revision := old.revision + 1;
  new.updated_at := now();
  if new.status = 'certified' then
    new.certified_at := coalesce(new.certified_at, now());
    new.rejected_at := null;
  elsif new.status = 'rejected' then
    new.rejected_at := coalesce(new.rejected_at, now());
    new.certified_at := null;
  else
    new.certified_at := null;
    new.rejected_at := null;
  end if;
  return new;
end;
$$;

revoke all on function public.prepare_provider_sync_delivery_certificate_v1()
from public, anon, authenticated;

drop trigger if exists provider_sync_delivery_certificate_revision_guard
on public.provider_sync_delivery_certificates;
create trigger provider_sync_delivery_certificate_revision_guard
before insert or update on public.provider_sync_delivery_certificates
for each row execute function public.prepare_provider_sync_delivery_certificate_v1();

create or replace function public.provider_sync_delivery_version_v1()
returns text
language sql
immutable
security definer
set search_path = ''
as $$
  select 'api-football-v3/leghevo-delivery-v1'::text;
$$;

revoke all on function public.provider_sync_delivery_version_v1()
from public, anon, authenticated;
grant execute on function public.provider_sync_delivery_version_v1()
to authenticated, service_role;

create or replace function public.record_provider_sync_delivery_unit_v1(
  p_run_id uuid,
  p_lease_token uuid,
  p_unit_no integer,
  p_expected_unit_count integer,
  p_declared_current integer,
  p_declared_total integer,
  p_declared_results integer,
  p_observed_results integer,
  p_records_processed integer,
  p_entity_fingerprints jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_assertion jsonb;
  v_run public.provider_sync_runs%rowtype;
  v_lease public.provider_sync_worker_leases%rowtype;
  v_certificate public.provider_sync_delivery_certificates%rowtype;
  v_existing public.provider_sync_delivery_units%rowtype;
  v_entity_count integer;
  v_distinct_count integer;
  v_manifest text;
begin
  if p_run_id is null or p_lease_token is null then
    raise exception 'Consegna provider incompleta [delivery.identity_missing].';
  end if;
  if coalesce(p_unit_no, 0) < 1
    or coalesce(p_expected_unit_count, 0) < 1
    or p_unit_no > p_expected_unit_count then
    raise exception 'Consegna provider incompleta [delivery.unit_range].';
  end if;
  if coalesce(p_declared_current, -1) < 0
    or coalesce(p_declared_total, -1) < 0
    or coalesce(p_declared_results, -1) < 0
    or coalesce(p_observed_results, -1) < 0
    or coalesce(p_records_processed, -1) < 0 then
    raise exception 'Consegna provider incompleta [delivery.negative_count].';
  end if;
  if p_declared_results <> p_observed_results then
    raise exception
      'Consegna provider incompleta [delivery.results_mismatch]: dichiarati %, ricevuti %.',
      p_declared_results,
      p_observed_results;
  end if;
  if p_entity_fingerprints is null
    or jsonb_typeof(p_entity_fingerprints) <> 'array' then
    raise exception 'Consegna provider incompleta [delivery.entities_array].';
  end if;

  select count(*)::integer, count(distinct value)::integer
  into v_entity_count, v_distinct_count
  from jsonb_array_elements_text(p_entity_fingerprints);

  if v_entity_count <> p_records_processed
    or v_distinct_count <> v_entity_count then
    raise exception
      'Consegna provider incompleta [delivery.entity_count]: record %, impronte %, distinte %.',
      p_records_processed,
      v_entity_count,
      v_distinct_count;
  end if;
  if exists (
    select 1
    from jsonb_array_elements_text(p_entity_fingerprints) entity_row(value)
    where entity_row.value !~ '^[0-9a-f]{64}$'
  ) then
    raise exception 'Consegna provider incompleta [delivery.entity_fingerprint].';
  end if;

  select
    md5('delivery-unit-a' || coalesce(string_agg(entity_row.value, E'\n' order by entity_row.value), ''))
    || md5('delivery-unit-b' || coalesce(string_agg(entity_row.value, E'\n' order by entity_row.value), ''))
  into v_manifest
  from jsonb_array_elements_text(p_entity_fingerprints) entity_row(value);

  v_assertion := public.assert_provider_sync_worker_lease_v1(
    p_run_id,
    p_lease_token
  );

  select run_row.*
  into v_run
  from public.provider_sync_runs run_row
  where run_row.id = p_run_id
  for update;

  if not found then
    raise exception 'Run provider non trovato durante la certificazione della consegna.';
  end if;

  select lease_row.*
  into v_lease
  from public.provider_sync_worker_leases lease_row
  where lease_row.run_id = p_run_id
  for update;

  if not found then
    raise exception 'Lease worker provider non trovata durante la certificazione.';
  end if;
  if v_lease.lease_token <> p_lease_token then
    raise exception 'Certificazione consegna rifiutata: token worker non più proprietario.';
  end if;
  if v_run.status = 'running' then
    if v_lease.status <> 'active' then
      raise exception 'Certificazione consegna rifiutata: lease nello stato %.', v_lease.status;
    end if;
    if v_lease.lease_expires_at <= now() then
      raise exception 'Certificazione consegna rifiutata: lease worker scaduta.';
    end if;
  end if;

  if p_expected_unit_count <> greatest(p_declared_total, 1) then
    raise exception
      'Consegna provider incompleta [delivery.expected_total]: atteso %, dichiarato %.',
      p_expected_unit_count,
      p_declared_total;
  end if;
  if v_run.sync_type = 'sync-season-players' then
    if p_declared_current <> p_unit_no then
      raise exception
        'Consegna provider incompleta [delivery.page_mismatch]: unità %, pagina %.',
        p_unit_no,
        p_declared_current;
    end if;
  elsif p_unit_no <> 1
    or p_expected_unit_count <> 1
    or p_declared_total > 1 then
    raise exception 'Consegna provider incompleta [delivery.unexpected_pagination].';
  end if;

  select certificate_row.*
  into v_certificate
  from public.provider_sync_delivery_certificates certificate_row
  where certificate_row.run_id = p_run_id
  for update;

  if not found then
    insert into public.provider_sync_delivery_certificates (
      run_id,
      recovery_request_id,
      league_id,
      provider,
      sync_type,
      expected_unit_count,
      run_revision,
      lease_epoch
    ) values (
      v_run.id,
      v_lease.recovery_request_id,
      v_lease.league_id,
      v_run.provider,
      v_run.sync_type,
      p_expected_unit_count,
      coalesce((v_assertion ->> 'runRevision')::bigint, v_run.revision),
      coalesce((v_assertion ->> 'leaseEpoch')::bigint, v_lease.lease_epoch)
    )
    returning * into v_certificate;
  end if;

  if v_certificate.status <> 'collecting' then
    raise exception 'Consegna provider già conclusa nello stato %.', v_certificate.status;
  end if;
  if v_certificate.expected_unit_count is distinct from p_expected_unit_count then
    raise exception
      'Consegna provider incompleta [delivery.total_changed]: atteso %, ricevuto %.',
      v_certificate.expected_unit_count,
      p_expected_unit_count;
  end if;
  select unit_row.*
  into v_existing
  from public.provider_sync_delivery_units unit_row
  where unit_row.run_id = p_run_id
    and unit_row.unit_no = p_unit_no;

  if found then
    if row(
      v_existing.expected_unit_count,
      v_existing.declared_current,
      v_existing.declared_total,
      v_existing.declared_results,
      v_existing.observed_results,
      v_existing.records_processed,
      v_existing.unique_entity_count,
      v_existing.entity_manifest_fingerprint
    ) is not distinct from row(
      p_expected_unit_count,
      p_declared_current,
      p_declared_total,
      p_declared_results,
      p_observed_results,
      p_records_processed,
      v_entity_count,
      v_manifest
    ) then
      return jsonb_build_object(
        'certificateId', v_certificate.id,
        'unitNo', p_unit_no,
        'status', v_certificate.status,
        'revision', v_certificate.revision,
        'reused', true
      );
    end if;
    raise exception 'Consegna provider incompleta [delivery.unit_conflict].';
  end if;

  if p_unit_no <> v_certificate.observed_unit_count + 1 then
    raise exception
      'Consegna provider incompleta [delivery.unit_order]: attesa unità %, ricevuta %.',
      v_certificate.observed_unit_count + 1,
      p_unit_no;
  end if;

  -- Una stessa impronta non può essere presente in due pagine/unità del run.
  if exists (
    select 1
    from jsonb_array_elements_text(p_entity_fingerprints) entity_row(value)
    join public.provider_sync_delivery_entities existing_row
      on existing_row.run_id = p_run_id
     and existing_row.entity_fingerprint = entity_row.value
  ) then
    raise exception 'Consegna provider incompleta [delivery.duplicate_entity].';
  end if;

  insert into public.provider_sync_delivery_units (
    certificate_id,
    run_id,
    unit_no,
    expected_unit_count,
    declared_current,
    declared_total,
    declared_results,
    observed_results,
    records_processed,
    unique_entity_count,
    entity_manifest_fingerprint
  ) values (
    v_certificate.id,
    p_run_id,
    p_unit_no,
    p_expected_unit_count,
    p_declared_current,
    p_declared_total,
    p_declared_results,
    p_observed_results,
    p_records_processed,
    v_entity_count,
    v_manifest
  );

  insert into public.provider_sync_delivery_entities (
    certificate_id,
    run_id,
    unit_no,
    entity_fingerprint
  )
  select
    v_certificate.id,
    p_run_id,
    p_unit_no,
    entity_row.value
  from jsonb_array_elements_text(p_entity_fingerprints) entity_row(value);

  update public.provider_sync_delivery_certificates certificate_row
  set
    observed_unit_count = certificate_row.observed_unit_count + 1,
    observed_record_count = certificate_row.observed_record_count + p_records_processed,
    unique_entity_count = certificate_row.unique_entity_count + v_entity_count,
    last_unit_no = p_unit_no,
    manifest_fingerprint = md5(
      certificate_row.manifest_fingerprint || E'\n'
      || p_unit_no::text || E'\n'
      || p_expected_unit_count::text || E'\n'
      || p_declared_current::text || E'\n'
      || p_declared_total::text || E'\n'
      || p_declared_results::text || E'\n'
      || p_records_processed::text || E'\n'
      || v_manifest
    ),
    summary = format(
      'Consegna provider acquisita: unità %s/%s, record %s.',
      certificate_row.observed_unit_count + 1,
      p_expected_unit_count,
      certificate_row.observed_record_count + p_records_processed
    )
  where certificate_row.id = v_certificate.id
  returning * into v_certificate;

  return jsonb_build_object(
    'certificateId', v_certificate.id,
    'runId', v_certificate.run_id,
    'status', v_certificate.status,
    'expectedUnitCount', v_certificate.expected_unit_count,
    'observedUnitCount', v_certificate.observed_unit_count,
    'observedRecordCount', v_certificate.observed_record_count,
    'uniqueEntityCount', v_certificate.unique_entity_count,
    'revision', v_certificate.revision,
    'reused', false
  );
exception
  when unique_violation then
    raise exception 'Consegna provider incompleta [delivery.duplicate_entity].';
end;
$$;

revoke all on function public.record_provider_sync_delivery_unit_v1(
  uuid,uuid,integer,integer,integer,integer,integer,integer,integer,jsonb
)
from public, anon, authenticated;
grant execute on function public.record_provider_sync_delivery_unit_v1(
  uuid,uuid,integer,integer,integer,integer,integer,integer,integer,jsonb
)
to service_role;

create or replace function public.finish_provider_sync_run_guarded_v3(
  p_run_id uuid,
  p_status text,
  p_records_processed integer,
  p_error_message text default null,
  p_expected_revision bigint default null,
  p_lease_token uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_status text := lower(trim(coalesce(p_status, '')));
  v_run public.provider_sync_runs%rowtype;
  v_lease public.provider_sync_worker_leases%rowtype;
  v_certificate public.provider_sync_delivery_certificates%rowtype;
  v_result jsonb;
  v_unit_count integer;
  v_min_unit integer;
  v_max_unit integer;
begin
  if v_status not in ('completed','failed') then
    raise exception 'Stato finale del run provider non valido.';
  end if;

  select run_row.*
  into v_run
  from public.provider_sync_runs run_row
  where run_row.id = p_run_id
  for update;

  if not found then
    raise exception 'Run provider non trovato durante la certificazione della consegna.';
  end if;

  select lease_row.*
  into v_lease
  from public.provider_sync_worker_leases lease_row
  where lease_row.run_id = p_run_id
  for update;

  if not found then
    raise exception 'Lease worker provider non trovata durante la certificazione.';
  end if;
  if v_lease.lease_token <> p_lease_token then
    raise exception 'Certificazione consegna rifiutata: token worker non più proprietario.';
  end if;
  if v_run.status = 'running' then
    if v_lease.status <> 'active' then
      raise exception 'Certificazione consegna rifiutata: lease nello stato %.', v_lease.status;
    end if;
    if v_lease.lease_expires_at <= now() then
      raise exception 'Certificazione consegna rifiutata: lease worker scaduta.';
    end if;
  end if;

  select certificate_row.*
  into v_certificate
  from public.provider_sync_delivery_certificates certificate_row
  where certificate_row.run_id = p_run_id
  for update;

  if v_status = 'completed' then
    if not found then
      raise exception 'Consegna provider incompleta [delivery.certificate_missing].';
    end if;
    if v_certificate.status = 'certified' then
      if v_certificate.observed_record_count = coalesce(p_records_processed, 0) then
        v_result := public.finish_provider_sync_run_guarded_v2(
          p_run_id,
          p_status,
          p_records_processed,
          p_error_message,
          p_expected_revision,
          p_lease_token
        );
        return v_result || jsonb_build_object(
          'deliveryCertified', true,
          'deliveryCertificateId', v_certificate.id,
          'deliveryRevision', v_certificate.revision
        );
      end if;
      raise exception 'Consegna provider già certificata con un conteggio differente.';
    end if;
    if v_certificate.status <> 'collecting' then
      raise exception 'Consegna provider non certificabile nello stato %.', v_certificate.status;
    end if;

    select count(*)::integer, min(unit_row.unit_no), max(unit_row.unit_no)
    into v_unit_count, v_min_unit, v_max_unit
    from public.provider_sync_delivery_units unit_row
    where unit_row.certificate_id = v_certificate.id;

    if v_certificate.expected_unit_count is null
      or v_certificate.observed_unit_count <> v_certificate.expected_unit_count
      or v_unit_count <> v_certificate.expected_unit_count
      or v_min_unit <> 1
      or v_max_unit <> v_certificate.expected_unit_count then
      raise exception
        'Consegna provider incompleta [delivery.units_missing]: attese %, osservate %.',
        v_certificate.expected_unit_count,
        v_certificate.observed_unit_count;
    end if;
    if v_certificate.observed_record_count <> coalesce(p_records_processed, 0) then
      raise exception
        'Consegna provider incompleta [delivery.records_mismatch]: certificati %, run %.',
        v_certificate.observed_record_count,
        coalesce(p_records_processed, 0);
    end if;
    if v_certificate.unique_entity_count <> v_certificate.observed_record_count then
      raise exception 'Consegna provider incompleta [delivery.unique_mismatch].';
    end if;

    update public.provider_sync_delivery_certificates certificate_row
    set
      status = 'certified',
      summary = format(
        'Consegna provider certificata: %s unità, %s record univoci.',
        v_certificate.observed_unit_count,
        v_certificate.observed_record_count
      )
    where certificate_row.id = v_certificate.id
    returning * into v_certificate;
  else
    if found and v_certificate.status = 'collecting' then
      update public.provider_sync_delivery_certificates certificate_row
      set
        status = 'rejected',
        summary = left(
          case
            when lower(coalesce(p_error_message, '')) like '%consegna provider incompleta%'
              then regexp_replace(
                coalesce(nullif(trim(p_error_message), ''), 'Consegna provider respinta.'),
                E'[\r\n]+',
                ' ',
                'g'
              )
            else 'Consegna provider interrotta prima della certificazione.'
          end,
          500
        )
      where certificate_row.id = v_certificate.id
      returning * into v_certificate;
    elsif not found
      and lower(coalesce(p_error_message, '')) like '%consegna provider incompleta%' then
      insert into public.provider_sync_delivery_certificates (
        run_id,
        recovery_request_id,
        league_id,
        provider,
        sync_type,
        expected_unit_count,
        run_revision,
        lease_epoch
      ) values (
        v_run.id,
        v_lease.recovery_request_id,
        v_lease.league_id,
        v_run.provider,
        v_run.sync_type,
        null,
        v_run.revision,
        v_lease.lease_epoch
      )
      returning * into v_certificate;

      update public.provider_sync_delivery_certificates certificate_row
      set
        status = 'rejected',
        summary = left(
          regexp_replace(
            coalesce(nullif(trim(p_error_message), ''), 'Consegna provider respinta.'),
            E'[\r\n]+',
            ' ',
            'g'
          ),
          500
        )
      where certificate_row.id = v_certificate.id
      returning * into v_certificate;
    end if;
  end if;

  v_result := public.finish_provider_sync_run_guarded_v2(
    p_run_id,
    p_status,
    p_records_processed,
    p_error_message,
    p_expected_revision,
    p_lease_token
  );

  return v_result || jsonb_build_object(
    'deliveryCertified', coalesce(v_certificate.status = 'certified', false),
    'deliveryCertificateId', v_certificate.id,
    'deliveryRevision', v_certificate.revision,
    'deliveryStatus', v_certificate.status
  );
end;
$$;

revoke all on function public.finish_provider_sync_run_guarded_v3(
  uuid,text,integer,text,bigint,uuid
)
from public, anon, authenticated;
grant execute on function public.finish_provider_sync_run_guarded_v3(
  uuid,text,integer,text,bigint,uuid
)
to service_role;

create or replace function public.get_league_provider_delivery_center_v1(
  p_league_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_owner_id uuid;
  v_collecting integer := 0;
  v_certified_24h integer := 0;
  v_rejected_24h integer := 0;
  v_total integer := 0;
  v_latest_at timestamptz;
  v_latest jsonb;
begin
  select league_row.owner_id
  into v_owner_id
  from public.leagues league_row
  where league_row.id = p_league_id;

  if not found then
    raise exception 'Lega non trovata per il controllo delle consegne provider.';
  end if;
  if auth.uid() is null
    or not (
      v_owner_id = auth.uid()
      or public.is_league_admin(p_league_id)
    ) then
    raise exception 'Solo Presidente e Admin possono leggere le consegne provider.';
  end if;

  select
    count(*)::integer,
    count(*) filter (where certificate_row.status = 'collecting')::integer,
    count(*) filter (
      where certificate_row.status = 'certified'
        and certificate_row.certified_at >= now() - interval '24 hours'
    )::integer,
    count(*) filter (
      where certificate_row.status = 'rejected'
        and certificate_row.rejected_at >= now() - interval '24 hours'
    )::integer,
    max(certificate_row.updated_at)
  into v_total, v_collecting, v_certified_24h, v_rejected_24h, v_latest_at
  from public.provider_sync_delivery_certificates certificate_row
  where certificate_row.league_id = p_league_id
    or certificate_row.league_id is null;

  select jsonb_build_object(
    'id', certificate_row.id,
    'runId', certificate_row.run_id,
    'requestId', certificate_row.recovery_request_id,
    'syncType', certificate_row.sync_type,
    'status', certificate_row.status,
    'expectedUnitCount', certificate_row.expected_unit_count,
    'observedUnitCount', certificate_row.observed_unit_count,
    'observedRecordCount', certificate_row.observed_record_count,
    'uniqueEntityCount', certificate_row.unique_entity_count,
    'summary', certificate_row.summary,
    'updatedAt', certificate_row.updated_at
  )
  into v_latest
  from public.provider_sync_delivery_certificates certificate_row
  where certificate_row.league_id = p_league_id
    or certificate_row.league_id is null
  order by certificate_row.updated_at desc, certificate_row.id desc
  limit 1;

  return jsonb_build_object(
    'protected', true,
    'healthy', coalesce(v_rejected_24h, 0) = 0,
    'deliveryValidationActive', true,
    'completionGateActive', true,
    'rawEntityStorageDisabled', true,
    'deliveryVersion', public.provider_sync_delivery_version_v1(),
    'collectingCount', coalesce(v_collecting, 0),
    'certifiedLast24h', coalesce(v_certified_24h, 0),
    'rejectedLast24h', coalesce(v_rejected_24h, 0),
    'totalCertificateCount', coalesce(v_total, 0),
    'latestCertificateAt', v_latest_at,
    'latest', v_latest
  );
end;
$$;

revoke all on function public.get_league_provider_delivery_center_v1(uuid)
from public, anon, authenticated;
grant execute on function public.get_league_provider_delivery_center_v1(uuid)
to authenticated;

create or replace function public.get_league_provider_sync_health_v12(
  p_league_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_health jsonb;
  v_delivery jsonb;
  v_healthy boolean;
  v_status text;
begin
  v_health := public.get_league_provider_sync_health_v11(p_league_id);
  v_delivery := public.get_league_provider_delivery_center_v1(p_league_id);
  v_healthy := coalesce((v_health ->> 'healthy')::boolean, false)
    and coalesce((v_delivery ->> 'healthy')::boolean, false);
  v_status := case
    when not v_healthy then 'attention'
    else coalesce(v_health ->> 'status', 'idle')
  end;

  return v_health || jsonb_build_object(
    'protected',
      coalesce((v_health ->> 'protected')::boolean, false)
      and coalesce((v_delivery ->> 'protected')::boolean, false),
    'healthy', v_healthy,
    'status', v_status,
    'deliveryIntegrity', v_delivery
  );
end;
$$;

revoke all on function public.get_league_provider_sync_health_v12(uuid)
from public, anon, authenticated;
grant execute on function public.get_league_provider_sync_health_v12(uuid)
to authenticated;

-- Solo il certificato sintetico è pubblicato. Unità e impronte restano server-side.
do $realtime$
begin
  if exists (
    select 1
    from pg_catalog.pg_publication publication_row
    where publication_row.pubname = 'supabase_realtime'
  ) and not exists (
    select 1
    from pg_catalog.pg_publication_tables publication_table
    where publication_table.pubname = 'supabase_realtime'
      and publication_table.schemaname = 'public'
      and publication_table.tablename = 'provider_sync_delivery_certificates'
  ) then
    alter publication supabase_realtime
      add table public.provider_sync_delivery_certificates;
  end if;
end;
$realtime$;

create or replace function public.get_provider_delivery_completeness_integrity_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_predecessor jsonb;
  v_retry_policy jsonb;
begin
  v_predecessor := public.get_provider_payload_contract_quarantine_integrity_v1();
  v_retry_policy := public.provider_recovery_retry_policy_v1(
    'Consegna provider incompleta [delivery.units_missing].',
    1,
    'sync-season-players'
  );

  return jsonb_build_object(
    'predecessor_ready',
      not exists (
        select 1 from jsonb_each(v_predecessor) check_row
        where check_row.value is distinct from 'true'::jsonb
      ),
    'certificate_table_ready',
      to_regclass('public.provider_sync_delivery_certificates') is not null,
    'detail_tables_ready',
      to_regclass('public.provider_sync_delivery_units') is not null
      and to_regclass('public.provider_sync_delivery_entities') is not null,
    'certificate_columns_ready',
      (
        select count(*) = 21
        from information_schema.columns column_row
        where column_row.table_schema = 'public'
          and column_row.table_name = 'provider_sync_delivery_certificates'
          and column_row.column_name in (
            'id','run_id','recovery_request_id','league_id','provider','sync_type',
            'status','expected_unit_count','observed_unit_count',
            'observed_record_count','unique_entity_count','last_unit_no',
            'manifest_fingerprint','summary','run_revision','lease_epoch',
            'revision','created_at','updated_at','certified_at','rejected_at'
          )
      ),
    'detail_constraints_ready',
      to_regclass('public.provider_sync_delivery_units_run_unit_uidx') is not null
      and to_regclass('public.provider_sync_delivery_entities_run_entity_uidx') is not null,
    'indexes_ready',
      to_regclass('public.provider_sync_delivery_certificates_league_idx') is not null
      and to_regclass('public.provider_sync_delivery_certificates_status_idx') is not null
      and to_regclass('public.provider_sync_delivery_units_certificate_idx') is not null
      and to_regclass('public.provider_sync_delivery_entities_certificate_idx') is not null,
    'rls_ready',
      coalesce((
        select class_row.relrowsecurity
        from pg_catalog.pg_class class_row
        where class_row.oid = 'public.provider_sync_delivery_certificates'::regclass
      ), false)
      and coalesce((
        select class_row.relrowsecurity
        from pg_catalog.pg_class class_row
        where class_row.oid = 'public.provider_sync_delivery_units'::regclass
      ), false)
      and coalesce((
        select class_row.relrowsecurity
        from pg_catalog.pg_class class_row
        where class_row.oid = 'public.provider_sync_delivery_entities'::regclass
      ), false),
    'privileges_ready',
      has_table_privilege('authenticated','public.provider_sync_delivery_certificates','SELECT')
      and not has_table_privilege('authenticated','public.provider_sync_delivery_certificates','INSERT')
      and not has_table_privilege('authenticated','public.provider_sync_delivery_units','SELECT')
      and not has_table_privilege('authenticated','public.provider_sync_delivery_entities','SELECT')
      and has_table_privilege('service_role','public.provider_sync_delivery_units','INSERT')
      and has_table_privilege('service_role','public.provider_sync_delivery_entities','INSERT'),
    'director_policy_ready',
      exists (
        select 1 from pg_catalog.pg_policies policy_row
        where policy_row.schemaname = 'public'
          and policy_row.tablename = 'provider_sync_delivery_certificates'
          and policy_row.policyname = 'provider_sync_delivery_certificates_read_directors'
      ),
    'detail_immutable_ready',
      exists (
        select 1 from pg_catalog.pg_trigger trigger_row
        where trigger_row.tgname = 'provider_sync_delivery_units_immutable'
          and trigger_row.tgrelid = 'public.provider_sync_delivery_units'::regclass
          and not trigger_row.tgisinternal
      )
      and exists (
        select 1 from pg_catalog.pg_trigger trigger_row
        where trigger_row.tgname = 'provider_sync_delivery_entities_immutable'
          and trigger_row.tgrelid = 'public.provider_sync_delivery_entities'::regclass
          and not trigger_row.tgisinternal
      ),
    'certificate_guard_ready',
      exists (
        select 1 from pg_catalog.pg_trigger trigger_row
        where trigger_row.tgname = 'provider_sync_delivery_certificate_revision_guard'
          and trigger_row.tgrelid = 'public.provider_sync_delivery_certificates'::regclass
          and not trigger_row.tgisinternal
      ),
    'delivery_version_ready',
      to_regprocedure('public.provider_sync_delivery_version_v1()') is not null
      and public.provider_sync_delivery_version_v1() =
        'api-football-v3/leghevo-delivery-v1',
    'unit_recorder_ready',
      to_regprocedure(
        'public.record_provider_sync_delivery_unit_v1(uuid,uuid,integer,integer,integer,integer,integer,integer,integer,jsonb)'
      ) is not null
      and has_function_privilege(
        'service_role',
        'public.record_provider_sync_delivery_unit_v1(uuid,uuid,integer,integer,integer,integer,integer,integer,integer,jsonb)',
        'EXECUTE'
      )
      and not has_function_privilege(
        'authenticated',
        'public.record_provider_sync_delivery_unit_v1(uuid,uuid,integer,integer,integer,integer,integer,integer,integer,jsonb)',
        'EXECUTE'
      ),
    'finish_gate_v3_ready',
      to_regprocedure(
        'public.finish_provider_sync_run_guarded_v3(uuid,text,integer,text,bigint,uuid)'
      ) is not null
      and has_function_privilege(
        'service_role',
        'public.finish_provider_sync_run_guarded_v3(uuid,text,integer,text,bigint,uuid)',
        'EXECUTE'
      ),
    'delivery_center_ready',
      to_regprocedure('public.get_league_provider_delivery_center_v1(uuid)') is not null
      and has_function_privilege(
        'authenticated',
        'public.get_league_provider_delivery_center_v1(uuid)',
        'EXECUTE'
      ),
    'sync_health_v12_ready',
      to_regprocedure('public.get_league_provider_sync_health_v12(uuid)') is not null
      and has_function_privilege(
        'authenticated',
        'public.get_league_provider_sync_health_v12(uuid)',
        'EXECUTE'
      ),
    'retry_policy_compatibility_ready',
      coalesce((v_retry_policy ->> 'retryable')::boolean, false)
      and coalesce(v_retry_policy ->> 'failureClass', '') = 'provider',
    'realtime_ready',
      exists (
        select 1
        from pg_catalog.pg_publication_tables publication_table
        where publication_table.pubname = 'supabase_realtime'
          and publication_table.schemaname = 'public'
          and publication_table.tablename = 'provider_sync_delivery_certificates'
      ),
    'no_raw_identity_ready',
      not exists (
        select 1
        from information_schema.columns column_row
        where column_row.table_schema = 'public'
          and column_row.table_name in (
            'provider_sync_delivery_certificates',
            'provider_sync_delivery_units',
            'provider_sync_delivery_entities'
          )
          and column_row.column_name in (
            'payload','raw_payload','provider_payload','entity_id','provider_entity_id',
            'lease_token','api_key','access_token'
          )
      ),
    'runtime_consistency_ready',
      not exists (
        select 1
        from public.provider_sync_delivery_certificates certificate_row
        left join public.provider_sync_runs run_row
          on run_row.id = certificate_row.run_id
        left join public.provider_recovery_requests request_row
          on request_row.id = certificate_row.recovery_request_id
        where run_row.id is null
          or certificate_row.provider is distinct from run_row.provider
          or certificate_row.sync_type is distinct from run_row.sync_type
          or certificate_row.observed_unit_count < 0
          or certificate_row.observed_record_count < 0
          or certificate_row.unique_entity_count <> certificate_row.observed_record_count
          or (
            certificate_row.observed_unit_count = 0
            and certificate_row.last_unit_no is not null
          )
          or (
            certificate_row.observed_unit_count > 0
            and certificate_row.last_unit_no is distinct from certificate_row.observed_unit_count
          )
          or certificate_row.observed_unit_count <> (
            select count(*)::integer
            from public.provider_sync_delivery_units unit_row
            where unit_row.certificate_id = certificate_row.id
          )
          or certificate_row.observed_record_count::bigint <> (
            select coalesce(sum(unit_row.records_processed), 0::bigint)
            from public.provider_sync_delivery_units unit_row
            where unit_row.certificate_id = certificate_row.id
          )
          or certificate_row.unique_entity_count <> (
            select count(*)::integer
            from public.provider_sync_delivery_entities entity_row
            where entity_row.certificate_id = certificate_row.id
          )
          or exists (
            select 1
            from public.provider_sync_delivery_units unit_row
            where unit_row.certificate_id = certificate_row.id
              and unit_row.expected_unit_count is distinct from certificate_row.expected_unit_count
          )
          or (
            certificate_row.status = 'certified'
            and (
              run_row.status <> 'completed'
              or certificate_row.expected_unit_count is null
              or certificate_row.observed_unit_count <> certificate_row.expected_unit_count
              or certificate_row.last_unit_no <> certificate_row.expected_unit_count
              or certificate_row.observed_record_count <> run_row.records_processed
              or coalesce((
                select min(unit_row.unit_no)
                from public.provider_sync_delivery_units unit_row
                where unit_row.certificate_id = certificate_row.id
              ), 0) <> 1
              or coalesce((
                select max(unit_row.unit_no)
                from public.provider_sync_delivery_units unit_row
                where unit_row.certificate_id = certificate_row.id
              ), 0) <> certificate_row.expected_unit_count
            )
          )
          or (
            certificate_row.recovery_request_id is not null
            and (
              request_row.id is null
              or request_row.recovery_run_id is distinct from certificate_row.run_id
              or request_row.league_id is distinct from certificate_row.league_id
            )
          )
      )
  );
end;
$$;

revoke all on function public.get_provider_delivery_completeness_integrity_v1()
from public, anon, authenticated;
grant execute on function public.get_provider_delivery_completeness_integrity_v1()
to authenticated, service_role;

-- Arresta la transazione indicando i nomi esatti degli eventuali controlli falsi.
do $validation$
declare
  v_checks jsonb;
  v_failed text[];
begin
  v_checks := public.get_provider_delivery_completeness_integrity_v1();

  select array_agg(check_row.key order by check_row.key)
  into v_failed
  from jsonb_each(v_checks) check_row
  where check_row.value is distinct from 'true'::jsonb;

  if coalesce(array_length(v_failed, 1), 0) > 0 then
    raise exception
      'Validazione v0.62.13 non superata. Controlli falsi: %',
      array_to_string(v_failed, '; ');
  end if;
end;
$validation$;

commit;

-- Diagnostica finale: devono comparire esattamente 20 valori true.
select
  (checks ->> 'predecessor_ready')::boolean as predecessor_ready,
  (checks ->> 'certificate_table_ready')::boolean as certificate_table_ready,
  (checks ->> 'detail_tables_ready')::boolean as detail_tables_ready,
  (checks ->> 'certificate_columns_ready')::boolean as certificate_columns_ready,
  (checks ->> 'detail_constraints_ready')::boolean as detail_constraints_ready,
  (checks ->> 'indexes_ready')::boolean as indexes_ready,
  (checks ->> 'rls_ready')::boolean as rls_ready,
  (checks ->> 'privileges_ready')::boolean as privileges_ready,
  (checks ->> 'director_policy_ready')::boolean as director_policy_ready,
  (checks ->> 'detail_immutable_ready')::boolean as detail_immutable_ready,
  (checks ->> 'certificate_guard_ready')::boolean as certificate_guard_ready,
  (checks ->> 'delivery_version_ready')::boolean as delivery_version_ready,
  (checks ->> 'unit_recorder_ready')::boolean as unit_recorder_ready,
  (checks ->> 'finish_gate_v3_ready')::boolean as finish_gate_v3_ready,
  (checks ->> 'delivery_center_ready')::boolean as delivery_center_ready,
  (checks ->> 'sync_health_v12_ready')::boolean as sync_health_v12_ready,
  (checks ->> 'retry_policy_compatibility_ready')::boolean as retry_policy_compatibility_ready,
  (checks ->> 'realtime_ready')::boolean as realtime_ready,
  (checks ->> 'no_raw_identity_ready')::boolean as no_raw_identity_ready,
  (checks ->> 'runtime_consistency_ready')::boolean as runtime_consistency_ready
from (
  select public.get_provider_delivery_completeness_integrity_v1() as checks
) diagnostic;
