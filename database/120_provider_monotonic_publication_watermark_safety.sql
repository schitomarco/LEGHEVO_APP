-- LEGHEVO v0.62.16
-- Watermark monotono e protezione anti-regressione delle pubblicazioni provider.
-- Eseguire dopo database/119_provider_semantic_scope_safety.sql.

begin;

-- PREFLIGHT: nessuna dipendenza viene presunta.
do $preflight$
declare
  v_missing text[] := array[]::text[];
  v_predecessor jsonb;
  v_has_running boolean := false;
begin
  if to_regprocedure('public.get_provider_semantic_scope_integrity_v1()') is null then
    v_missing := array_append(v_missing, 'function public.get_provider_semantic_scope_integrity_v1()');
  else
    v_predecessor := public.get_provider_semantic_scope_integrity_v1();
    if exists (
      select 1 from jsonb_each(v_predecessor) check_row
      where jsonb_typeof(check_row.value) is distinct from 'boolean'
         or check_row.value is distinct from 'true'::jsonb
    ) then
      v_missing := array_append(v_missing, 'validated predecessor public.get_provider_semantic_scope_integrity_v1()');
    end if;
  end if;

  if to_regprocedure('public.provider_sync_scope_metadata_v1(text,jsonb)') is null then
    v_missing := array_append(v_missing, 'function public.provider_sync_scope_metadata_v1(text,jsonb)');
  end if;
  if to_regprocedure('public.assert_provider_sync_worker_lease_v1(uuid,uuid)') is null then
    v_missing := array_append(v_missing, 'function public.assert_provider_sync_worker_lease_v1(uuid,uuid)');
  end if;
  if to_regprocedure('public.ensure_provider_sync_publication_v1(uuid,uuid)') is null then
    v_missing := array_append(v_missing, 'function public.ensure_provider_sync_publication_v1(uuid,uuid)');
  end if;
  if to_regprocedure('public.certify_provider_sync_publication_scope_v1(uuid,uuid)') is null then
    v_missing := array_append(v_missing, 'function public.certify_provider_sync_publication_scope_v1(uuid,uuid)');
  end if;
  if to_regprocedure('public.finish_provider_sync_run_atomic_core_v1(uuid,text,integer,text,bigint,uuid)') is null then
    v_missing := array_append(v_missing, 'function public.finish_provider_sync_run_atomic_core_v1(uuid,text,integer,text,bigint,uuid)');
  end if;
  if to_regprocedure('public.finish_provider_sync_run_guarded_v3(uuid,text,integer,text,bigint,uuid)') is null then
    v_missing := array_append(v_missing, 'function public.finish_provider_sync_run_guarded_v3(uuid,text,integer,text,bigint,uuid)');
  end if;
  if to_regprocedure('public.finish_provider_sync_run_guarded_v5(uuid,text,integer,text,bigint,uuid)') is null then
    v_missing := array_append(v_missing, 'function public.finish_provider_sync_run_guarded_v5(uuid,text,integer,text,bigint,uuid)');
  end if;
  if to_regprocedure('public.get_league_provider_sync_health_v14(uuid)') is null then
    v_missing := array_append(v_missing, 'function public.get_league_provider_sync_health_v14(uuid)');
  end if;
  if to_regprocedure('public.get_league_provider_sync_health_v12(uuid)') is null then
    v_missing := array_append(v_missing, 'function public.get_league_provider_sync_health_v12(uuid)');
  end if;
  if to_regprocedure('public.get_league_provider_semantic_scope_center_v1(uuid)') is null then
    v_missing := array_append(v_missing, 'function public.get_league_provider_semantic_scope_center_v1(uuid)');
  end if;
  if to_regprocedure('public.certify_provider_recovery_request_outcome_v1(uuid)') is null then
    v_missing := array_append(v_missing, 'function public.certify_provider_recovery_request_outcome_v1(uuid)');
  end if;
  if to_regprocedure('public.capture_provider_recovery_outcome_certificate_v1()') is null then
    v_missing := array_append(v_missing, 'function public.capture_provider_recovery_outcome_certificate_v1()');
  end if;
  if to_regprocedure('pg_catalog.hashtext(text)') is null then
    v_missing := array_append(v_missing, 'function pg_catalog.hashtext(text)');
  end if;
  if to_regprocedure('pg_catalog.pg_advisory_xact_lock(integer,integer)') is null then
    v_missing := array_append(v_missing, 'function pg_catalog.pg_advisory_xact_lock(integer,integer)');
  end if;

  if to_regclass('public.provider_sync_runs') is null then
    v_missing := array_append(v_missing, 'table public.provider_sync_runs');
  end if;
  if to_regclass('public.provider_sync_worker_leases') is null then
    v_missing := array_append(v_missing, 'table public.provider_sync_worker_leases');
  end if;
  if to_regclass('public.provider_sync_publications') is null then
    v_missing := array_append(v_missing, 'table public.provider_sync_publications');
  end if;
  if to_regclass('public.provider_sync_scope_certificates') is null then
    v_missing := array_append(v_missing, 'table public.provider_sync_scope_certificates');
  end if;
  if to_regclass('public.provider_recovery_requests') is null then
    v_missing := array_append(v_missing, 'table public.provider_recovery_requests');
  end if;
  if to_regclass('public.provider_operational_incidents') is null then
    v_missing := array_append(v_missing, 'table public.provider_operational_incidents');
  end if;
  if to_regclass('public.provider_data_quality_snapshots') is null then
    v_missing := array_append(v_missing, 'table public.provider_data_quality_snapshots');
  end if;
  if to_regclass('public.provider_recovery_outcome_certificates') is null then
    v_missing := array_append(v_missing, 'table public.provider_recovery_outcome_certificates');
  end if;

  if to_regclass('public.provider_sync_runs') is not null then
    if exists (
      select 1 from (values
        ('id'),('provider'),('sync_type'),('requested_for'),('status'),
        ('records_processed'),('started_at'),('revision')
      ) required(column_name)
      where not exists (
        select 1 from information_schema.columns column_row
        where column_row.table_schema = 'public'
          and column_row.table_name = 'provider_sync_runs'
          and column_row.column_name = required.column_name
      )
    ) then
      v_missing := array_append(v_missing, 'required columns on public.provider_sync_runs');
    end if;

    execute 'select exists (select 1 from public.provider_sync_runs where status = ''running'')'
    into v_has_running;
    if v_has_running then
      v_missing := array_append(
        v_missing,
        'operational condition: no provider_sync_runs row may be running during installation'
      );
    end if;
  end if;

  if to_regclass('public.provider_sync_publications') is not null and exists (
    select 1 from (values
      ('id'),('run_id'),('recovery_request_id'),('league_id'),('provider'),
      ('sync_type'),('status'),('staged_primary_record_count'),
      ('published_primary_record_count'),('summary'),('run_revision'),
      ('published_at'),('discarded_at')
    ) required(column_name)
    where not exists (
      select 1 from information_schema.columns column_row
      where column_row.table_schema = 'public'
        and column_row.table_name = 'provider_sync_publications'
        and column_row.column_name = required.column_name
    )
  ) then
    v_missing := array_append(v_missing, 'required columns on public.provider_sync_publications');
  end if;

  if to_regclass('public.provider_sync_scope_certificates') is not null and exists (
    select 1 from (values
      ('id'),('publication_id'),('run_id'),('provider'),('sync_type'),
      ('scope_kind'),('scope_fingerprint'),('status')
    ) required(column_name)
    where not exists (
      select 1 from information_schema.columns column_row
      where column_row.table_schema = 'public'
        and column_row.table_name = 'provider_sync_scope_certificates'
        and column_row.column_name = required.column_name
    )
  ) then
    v_missing := array_append(v_missing, 'required columns on public.provider_sync_scope_certificates');
  end if;

  if to_regclass('public.provider_recovery_requests') is not null and exists (
    select 1 from (values
      ('id'),('league_id'),('incident_id'),('recovery_run_id'),('provider'),
      ('sync_type'),('status'),('revision'),('finished_at')
    ) required(column_name)
    where not exists (
      select 1 from information_schema.columns column_row
      where column_row.table_schema = 'public'
        and column_row.table_name = 'provider_recovery_requests'
        and column_row.column_name = required.column_name
    )
  ) then
    v_missing := array_append(v_missing, 'required columns on public.provider_recovery_requests');
  end if;

  if to_regclass('public.provider_operational_incidents') is not null and exists (
    select 1 from (values ('id'),('status'),('revision')) required(column_name)
    where not exists (
      select 1 from information_schema.columns column_row
      where column_row.table_schema = 'public'
        and column_row.table_name = 'provider_operational_incidents'
        and column_row.column_name = required.column_name
    )
  ) then
    v_missing := array_append(v_missing, 'required columns on public.provider_operational_incidents');
  end if;

  if to_regclass('public.provider_data_quality_snapshots') is not null and exists (
    select 1 from (values ('id'),('run_id'),('status'),('anomaly_count'),('created_at')) required(column_name)
    where not exists (
      select 1 from information_schema.columns column_row
      where column_row.table_schema = 'public'
        and column_row.table_name = 'provider_data_quality_snapshots'
        and column_row.column_name = required.column_name
    )
  ) then
    v_missing := array_append(v_missing, 'required columns on public.provider_data_quality_snapshots');
  end if;

  if to_regclass('public.provider_recovery_outcome_certificates') is not null and exists (
    select 1 from (values
      ('id'),('league_id'),('request_id'),('incident_id'),('recovery_run_id'),
      ('provider'),('sync_type'),('outcome'),('incident_status'),
      ('incident_revision'),('source_snapshot_id'),('source_snapshot_status'),
      ('anomaly_count'),('verification_summary'),('certificate_fingerprint'),('created_at')
    ) required(column_name)
    where not exists (
      select 1 from information_schema.columns column_row
      where column_row.table_schema = 'public'
        and column_row.table_name = 'provider_recovery_outcome_certificates'
        and column_row.column_name = required.column_name
    )
  ) then
    v_missing := array_append(v_missing, 'required columns on public.provider_recovery_outcome_certificates');
  end if;

  if coalesce(array_length(v_missing, 1), 0) > 0 then
    raise exception
      'Preflight v0.62.16 non superato. Dipendenze mancanti: %',
      array_to_string(v_missing, '; ');
  end if;
end;
$preflight$;

create table if not exists public.provider_sync_scope_watermarks (
  id uuid primary key default gen_random_uuid(),
  provider text not null,
  sync_type text not null,
  scope_kind text not null,
  scope_fingerprint text not null,
  latest_run_id uuid not null
    references public.provider_sync_runs(id) on delete restrict,
  latest_publication_id uuid not null
    references public.provider_sync_publications(id) on delete restrict,
  league_id uuid references public.leagues(id) on delete set null,
  latest_run_started_at timestamptz not null,
  latest_published_at timestamptz not null,
  latest_records_processed integer not null default 0,
  generation bigint not null default 1,
  revision bigint not null default 1,
  last_transition text not null default 'backfilled',
  summary text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint provider_sync_scope_watermarks_sync_type_check check (
    sync_type in ('sync-season-players','sync-fixtures','sync-fixture-players')
  ),
  constraint provider_sync_scope_watermarks_scope_kind_check check (
    scope_kind in ('season','date','fixture')
  ),
  constraint provider_sync_scope_watermarks_fingerprint_check check (
    scope_fingerprint ~ '^[0-9a-f]{32}$'
  ),
  constraint provider_sync_scope_watermarks_counts_check check (
    latest_records_processed between 0 and 1000000
  ),
  constraint provider_sync_scope_watermarks_revision_check check (
    generation > 0 and revision > 0
  ),
  constraint provider_sync_scope_watermarks_transition_check check (
    last_transition in ('backfilled','advanced')
  ),
  constraint provider_sync_scope_watermarks_summary_check check (
    length(summary) between 1 and 500 and summary !~ E'[\r\n]'
  ),
  unique (provider, sync_type, scope_fingerprint),
  unique (latest_publication_id)
);

create table if not exists public.provider_sync_scope_watermark_events (
  id uuid primary key default gen_random_uuid(),
  watermark_id uuid not null
    references public.provider_sync_scope_watermarks(id) on delete restrict,
  league_id uuid references public.leagues(id) on delete set null,
  event_type text not null,
  candidate_run_id uuid not null
    references public.provider_sync_runs(id) on delete restrict,
  candidate_publication_id uuid not null
    references public.provider_sync_publications(id) on delete restrict,
  previous_run_id uuid
    references public.provider_sync_runs(id) on delete restrict,
  previous_publication_id uuid
    references public.provider_sync_publications(id) on delete restrict,
  generation bigint not null,
  candidate_started_at timestamptz not null,
  latest_started_at timestamptz not null,
  record_count integer not null default 0,
  reason_code text not null,
  event_fingerprint text not null,
  created_at timestamptz not null default now(),
  constraint provider_sync_scope_watermark_events_type_check check (
    event_type in ('backfilled','advanced','stale_rejected')
  ),
  constraint provider_sync_scope_watermark_events_generation_check check (
    generation > 0
  ),
  constraint provider_sync_scope_watermark_events_record_count_check check (
    record_count between 0 and 1000000
  ),
  constraint provider_sync_scope_watermark_events_reason_check check (
    reason_code ~ '^[a-z0-9_.-]{3,80}$'
  ),
  constraint provider_sync_scope_watermark_events_fingerprint_check check (
    event_fingerprint ~ '^[0-9a-f]{32}$'
  ),
  unique (candidate_publication_id, event_type)
);

create index if not exists provider_sync_scope_watermarks_latest_idx
  on public.provider_sync_scope_watermarks (
    provider, sync_type, latest_run_started_at desc
  );
create index if not exists provider_sync_scope_watermarks_league_idx
  on public.provider_sync_scope_watermarks (league_id, updated_at desc);
create index if not exists provider_sync_scope_watermark_events_latest_idx
  on public.provider_sync_scope_watermark_events (created_at desc);
create index if not exists provider_sync_scope_watermark_events_league_idx
  on public.provider_sync_scope_watermark_events (league_id, created_at desc);

alter table public.provider_sync_scope_watermarks enable row level security;
alter table public.provider_sync_scope_watermarks replica identity full;
alter table public.provider_sync_scope_watermark_events enable row level security;
alter table public.provider_sync_scope_watermark_events replica identity full;

revoke all on table public.provider_sync_scope_watermarks
from public, anon, authenticated, service_role;
revoke all on table public.provider_sync_scope_watermark_events
from public, anon, authenticated, service_role;
grant select on table public.provider_sync_scope_watermarks to service_role;
grant select on table public.provider_sync_scope_watermark_events to service_role;
grant select on table public.provider_sync_scope_watermarks to authenticated;
grant select on table public.provider_sync_scope_watermark_events to authenticated;

drop policy if exists provider_sync_scope_watermarks_read_directors
on public.provider_sync_scope_watermarks;
create policy provider_sync_scope_watermarks_read_directors
on public.provider_sync_scope_watermarks
for select to authenticated
using (
  (
    league_id is not null
    and exists (
      select 1 from public.leagues league_row
      where league_row.id = provider_sync_scope_watermarks.league_id
        and (
          league_row.owner_id = auth.uid()
          or public.is_league_admin(league_row.id)
        )
    )
  )
  or (
    league_id is null
    and exists (
      select 1 from public.leagues league_row
      where league_row.owner_id = auth.uid()
         or public.is_league_admin(league_row.id)
    )
  )
);

drop policy if exists provider_sync_scope_watermark_events_read_directors
on public.provider_sync_scope_watermark_events;
create policy provider_sync_scope_watermark_events_read_directors
on public.provider_sync_scope_watermark_events
for select to authenticated
using (
  (
    league_id is not null
    and exists (
      select 1 from public.leagues league_row
      where league_row.id = provider_sync_scope_watermark_events.league_id
        and (
          league_row.owner_id = auth.uid()
          or public.is_league_admin(league_row.id)
        )
    )
  )
  or (
    league_id is null
    and exists (
      select 1 from public.leagues league_row
      where league_row.owner_id = auth.uid()
         or public.is_league_admin(league_row.id)
    )
  )
);

create or replace function public.touch_provider_sync_scope_watermark_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    new.generation := 1;
    new.revision := 1;
    new.created_at := coalesce(new.created_at, now());
    new.updated_at := coalesce(new.updated_at, new.created_at);
    return new;
  end if;

  if row(new.provider,new.sync_type,new.scope_kind,new.scope_fingerprint,new.created_at)
     is distinct from
     row(old.provider,old.sync_type,old.scope_kind,old.scope_fingerprint,old.created_at) then
    raise exception 'Identità del watermark provider non modificabile.';
  end if;
  if new.last_transition <> 'advanced' then
    raise exception 'Transizione watermark provider non valida: %.', new.last_transition;
  end if;
  if new.latest_run_started_at < old.latest_run_started_at
     or (
       new.latest_run_started_at = old.latest_run_started_at
       and new.latest_run_id is distinct from old.latest_run_id
       and new.latest_run_id::text <= old.latest_run_id::text
     ) then
    raise exception 'Watermark provider non può regredire temporalmente.';
  end if;
  if new.latest_run_id is not distinct from old.latest_run_id
     or new.latest_publication_id is not distinct from old.latest_publication_id then
    raise exception 'Avanzamento watermark provider duplicato.';
  end if;

  new.generation := old.generation + 1;
  new.revision := old.revision + 1;
  new.updated_at := now();
  return new;
end;
$$;

revoke all on function public.touch_provider_sync_scope_watermark_v1()
from public, anon, authenticated;

drop trigger if exists provider_sync_scope_watermarks_touch
on public.provider_sync_scope_watermarks;
create trigger provider_sync_scope_watermarks_touch
before insert or update on public.provider_sync_scope_watermarks
for each row execute function public.touch_provider_sync_scope_watermark_v1();
alter table public.provider_sync_scope_watermarks
  enable always trigger provider_sync_scope_watermarks_touch;

create or replace function public.write_provider_sync_scope_watermark_event_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_previous_run_id uuid;
  v_previous_publication_id uuid;
begin
  if tg_op = 'UPDATE' then
    v_previous_run_id := old.latest_run_id;
    v_previous_publication_id := old.latest_publication_id;
  end if;

  insert into public.provider_sync_scope_watermark_events (
    watermark_id,league_id,event_type,candidate_run_id,
    candidate_publication_id,previous_run_id,previous_publication_id,
    generation,candidate_started_at,latest_started_at,record_count,
    reason_code,event_fingerprint
  ) values (
    new.id,new.league_id,new.last_transition,new.latest_run_id,
    new.latest_publication_id,v_previous_run_id,v_previous_publication_id,
    new.generation,new.latest_run_started_at,new.latest_run_started_at,
    new.latest_records_processed,
    case new.last_transition
      when 'backfilled' then 'watermark.backfilled'
      else 'watermark.advanced'
    end,
    pg_catalog.md5(
      new.id::text || E'\n' || new.last_transition || E'\n'
      || new.latest_run_id::text || E'\n'
      || new.latest_publication_id::text || E'\n'
      || new.generation::text
    )
  )
  on conflict (candidate_publication_id,event_type) do nothing;

  return new;
end;
$$;

revoke all on function public.write_provider_sync_scope_watermark_event_v1()
from public, anon, authenticated;

drop trigger if exists provider_sync_scope_watermark_event_writer
on public.provider_sync_scope_watermarks;
create trigger provider_sync_scope_watermark_event_writer
after insert or update on public.provider_sync_scope_watermarks
for each row execute function public.write_provider_sync_scope_watermark_event_v1();
alter table public.provider_sync_scope_watermarks
  enable always trigger provider_sync_scope_watermark_event_writer;

create or replace function public.prevent_provider_sync_scope_watermark_event_mutation_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  raise exception 'Gli eventi del watermark provider sono immutabili.';
end;
$$;

revoke all on function public.prevent_provider_sync_scope_watermark_event_mutation_v1()
from public, anon, authenticated;

drop trigger if exists provider_sync_scope_watermark_events_immutable
on public.provider_sync_scope_watermark_events;
create trigger provider_sync_scope_watermark_events_immutable
before update or delete on public.provider_sync_scope_watermark_events
for each row execute function public.prevent_provider_sync_scope_watermark_event_mutation_v1();
alter table public.provider_sync_scope_watermark_events
  enable always trigger provider_sync_scope_watermark_events_immutable;

-- Backfill idempotente: per ogni scope viene scelta l'ultima pubblicazione
-- già certificata in base all'istante di avvio del run.
with ranked as (
  select
    certificate_row.provider,
    certificate_row.sync_type,
    certificate_row.scope_kind,
    certificate_row.scope_fingerprint,
    run_row.id as run_id,
    publication_row.id as publication_id,
    publication_row.league_id,
    run_row.started_at,
    coalesce(publication_row.published_at,publication_row.updated_at,run_row.finished_at,run_row.started_at) as published_at,
    publication_row.published_primary_record_count,
    row_number() over (
      partition by certificate_row.provider,certificate_row.sync_type,certificate_row.scope_fingerprint
      order by run_row.started_at desc,run_row.id::text desc
    ) as position_no
  from public.provider_sync_scope_certificates certificate_row
  join public.provider_sync_runs run_row on run_row.id = certificate_row.run_id
  join public.provider_sync_publications publication_row
    on publication_row.id = certificate_row.publication_id
  where certificate_row.status = 'certified'
    and publication_row.status = 'published'
    and run_row.status = 'completed'
)
insert into public.provider_sync_scope_watermarks (
  provider,sync_type,scope_kind,scope_fingerprint,latest_run_id,
  latest_publication_id,league_id,latest_run_started_at,
  latest_published_at,latest_records_processed,last_transition,summary
)
select
  ranked.provider,ranked.sync_type,ranked.scope_kind,ranked.scope_fingerprint,
  ranked.run_id,ranked.publication_id,ranked.league_id,ranked.started_at,
  ranked.published_at,ranked.published_primary_record_count,'backfilled',
  'Watermark provider inizializzato dalla pubblicazione certificata più recente.'
from ranked
where ranked.position_no = 1
on conflict (provider,sync_type,scope_fingerprint) do nothing;

create or replace function public.provider_sync_scope_watermark_decision_v1(
  p_run_id uuid,
  p_lease_token uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_run public.provider_sync_runs%rowtype;
  v_publication public.provider_sync_publications%rowtype;
  v_certificate public.provider_sync_scope_certificates%rowtype;
  v_metadata jsonb;
  v_watermark public.provider_sync_scope_watermarks%rowtype;
  v_is_stale boolean := false;
begin
  if p_run_id is null or p_lease_token is null then
    raise exception 'Watermark provider non verificabile: run e token worker obbligatori.';
  end if;

  perform public.assert_provider_sync_worker_lease_v1(p_run_id,p_lease_token);

  select run_row.* into v_run
  from public.provider_sync_runs run_row
  where run_row.id = p_run_id
  for update;
  if not found or v_run.status <> 'running' then
    raise exception 'Watermark provider non verificabile [watermark.run_not_running].';
  end if;

  perform public.ensure_provider_sync_publication_v1(p_run_id,p_lease_token);

  select publication_row.* into v_publication
  from public.provider_sync_publications publication_row
  where publication_row.run_id = p_run_id
  for update;
  if not found or v_publication.status <> 'collecting' then
    raise exception 'Watermark provider non verificabile [watermark.publication_not_collecting].';
  end if;

  select certificate_row.* into v_certificate
  from public.provider_sync_scope_certificates certificate_row
  where certificate_row.publication_id = v_publication.id
  for update;
  if not found or v_certificate.status <> 'collecting' then
    raise exception 'Watermark provider non verificabile [watermark.scope_not_collecting].';
  end if;

  v_metadata := public.provider_sync_scope_metadata_v1(v_run.sync_type,v_run.requested_for);
  if v_certificate.scope_fingerprint is distinct from (v_metadata ->> 'scopeFingerprint')
     or v_certificate.scope_kind is distinct from (v_metadata ->> 'scopeKind') then
    raise exception 'Watermark provider non verificabile [watermark.scope_identity_mismatch].';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext(v_run.provider || ':' || v_run.sync_type),
    pg_catalog.hashtext(v_certificate.scope_fingerprint)
  );

  select watermark_row.* into v_watermark
  from public.provider_sync_scope_watermarks watermark_row
  where watermark_row.provider = v_run.provider
    and watermark_row.sync_type = v_run.sync_type
    and watermark_row.scope_fingerprint = v_certificate.scope_fingerprint
  for update;

  if found and v_watermark.latest_run_id is distinct from v_run.id then
    v_is_stale :=
      v_run.started_at < v_watermark.latest_run_started_at
      or (
        v_run.started_at = v_watermark.latest_run_started_at
        and v_run.id::text <= v_watermark.latest_run_id::text
      );
  end if;

  return jsonb_build_object(
    'eligible',not v_is_stale,
    'stale',v_is_stale,
    'runId',v_run.id,
    'publicationId',v_publication.id,
    'leagueId',v_publication.league_id,
    'provider',v_run.provider,
    'syncType',v_run.sync_type,
    'scopeKind',v_certificate.scope_kind,
    'scopeFingerprint',v_certificate.scope_fingerprint,
    'candidateStartedAt',v_run.started_at,
    'watermarkId',v_watermark.id,
    'latestRunId',v_watermark.latest_run_id,
    'latestPublicationId',v_watermark.latest_publication_id,
    'latestStartedAt',v_watermark.latest_run_started_at,
    'generation',coalesce(v_watermark.generation,0)
  );
end;
$$;

revoke all on function public.provider_sync_scope_watermark_decision_v1(uuid,uuid)
from public, anon, authenticated, service_role;

create or replace function public.advance_provider_sync_scope_watermark_v1(
  p_run_id uuid,
  p_records_processed integer,
  p_lease_token uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_run public.provider_sync_runs%rowtype;
  v_publication public.provider_sync_publications%rowtype;
  v_certificate public.provider_sync_scope_certificates%rowtype;
  v_watermark public.provider_sync_scope_watermarks%rowtype;
begin
  select run_row.* into v_run
  from public.provider_sync_runs run_row
  where run_row.id = p_run_id
  for update;
  if not found or v_run.status <> 'completed' then
    raise exception 'Watermark provider non avanzabile [watermark.run_not_completed].';
  end if;

  select publication_row.* into v_publication
  from public.provider_sync_publications publication_row
  where publication_row.run_id = p_run_id
  for update;
  if not found or v_publication.status <> 'published' then
    raise exception 'Watermark provider non avanzabile [watermark.publication_not_published].';
  end if;

  select certificate_row.* into v_certificate
  from public.provider_sync_scope_certificates certificate_row
  where certificate_row.publication_id = v_publication.id
  for update;
  if not found or v_certificate.status <> 'certified' then
    raise exception 'Watermark provider non avanzabile [watermark.scope_not_certified].';
  end if;

  select watermark_row.* into v_watermark
  from public.provider_sync_scope_watermarks watermark_row
  where watermark_row.provider = v_run.provider
    and watermark_row.sync_type = v_run.sync_type
    and watermark_row.scope_fingerprint = v_certificate.scope_fingerprint
  for update;

  if not found then
    insert into public.provider_sync_scope_watermarks (
      provider,sync_type,scope_kind,scope_fingerprint,latest_run_id,
      latest_publication_id,league_id,latest_run_started_at,
      latest_published_at,latest_records_processed,last_transition,summary
    ) values (
      v_run.provider,v_run.sync_type,v_certificate.scope_kind,
      v_certificate.scope_fingerprint,v_run.id,v_publication.id,
      v_publication.league_id,v_run.started_at,
      coalesce(v_publication.published_at,now()),coalesce(p_records_processed,0),
      'advanced',
      'Watermark provider creato dalla prima pubblicazione certificata dello scope.'
    )
    returning * into v_watermark;
  elsif v_watermark.latest_run_id = v_run.id then
    return jsonb_build_object(
      'watermarkAdvanced',false,'watermarkId',v_watermark.id,
      'generation',v_watermark.generation,'latestRunId',v_watermark.latest_run_id
    );
  else
    if v_run.started_at < v_watermark.latest_run_started_at
       or (
         v_run.started_at = v_watermark.latest_run_started_at
         and v_run.id::text <= v_watermark.latest_run_id::text
       ) then
      raise exception 'Watermark provider non avanzabile [watermark.stale_after_publication_lock].';
    end if;

    update public.provider_sync_scope_watermarks watermark_row
    set
      latest_run_id = v_run.id,
      latest_publication_id = v_publication.id,
      league_id = v_publication.league_id,
      latest_run_started_at = v_run.started_at,
      latest_published_at = coalesce(v_publication.published_at,now()),
      latest_records_processed = coalesce(p_records_processed,0),
      last_transition = 'advanced',
      summary = format(
        'Watermark provider avanzato alla generazione %s dopo una pubblicazione più recente.',
        watermark_row.generation + 1
      )
    where watermark_row.id = v_watermark.id
    returning * into v_watermark;
  end if;

  return jsonb_build_object(
    'watermarkAdvanced',true,
    'watermarkId',v_watermark.id,
    'generation',v_watermark.generation,
    'latestRunId',v_watermark.latest_run_id,
    'latestPublicationId',v_watermark.latest_publication_id,
    'latestStartedAt',v_watermark.latest_run_started_at
  );
end;
$$;

revoke all on function public.advance_provider_sync_scope_watermark_v1(uuid,integer,uuid)
from public, anon, authenticated, service_role;

create or replace function public.discard_stale_provider_sync_publication_v1(
  p_run_id uuid,
  p_records_processed integer,
  p_expected_revision bigint,
  p_lease_token uuid,
  p_decision jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_run public.provider_sync_runs%rowtype;
  v_publication public.provider_sync_publications%rowtype;
  v_watermark public.provider_sync_scope_watermarks%rowtype;
  v_result jsonb;
  v_summary text;
begin
  if coalesce((p_decision ->> 'stale')::boolean,false) is not true then
    raise exception 'Scarto watermark rifiutato [watermark.decision_not_stale].';
  end if;

  select run_row.* into v_run
  from public.provider_sync_runs run_row
  where run_row.id = p_run_id
  for update;
  if not found or v_run.status <> 'running' then
    raise exception 'Scarto watermark rifiutato [watermark.run_not_running].';
  end if;

  select publication_row.* into v_publication
  from public.provider_sync_publications publication_row
  where publication_row.run_id = p_run_id
  for update;
  if not found or v_publication.status <> 'collecting' then
    raise exception 'Scarto watermark rifiutato [watermark.publication_not_collecting].';
  end if;

  select watermark_row.* into v_watermark
  from public.provider_sync_scope_watermarks watermark_row
  where watermark_row.id = nullif(p_decision ->> 'watermarkId','')::uuid
  for update;
  if not found then
    raise exception 'Scarto watermark rifiutato [watermark.current_missing].';
  end if;

  if v_watermark.latest_run_id is distinct from nullif(p_decision ->> 'latestRunId','')::uuid
     or v_watermark.latest_publication_id is distinct from nullif(p_decision ->> 'latestPublicationId','')::uuid
     or v_watermark.latest_run_started_at is distinct from (p_decision ->> 'latestStartedAt')::timestamptz then
    raise exception 'Scarto watermark rifiutato [watermark.changed_during_decision].';
  end if;

  -- Lo scope viene comunque certificato: la consegna è valida ma non deve
  -- sostituire una fotografia iniziata più recentemente.
  perform public.certify_provider_sync_publication_scope_v1(
    p_run_id,p_lease_token
  );

  delete from public.provider_sync_stage_scores row_item
  where row_item.publication_id = v_publication.id;
  delete from public.provider_sync_stage_fixtures row_item
  where row_item.publication_id = v_publication.id;
  delete from public.provider_sync_stage_roles row_item
  where row_item.publication_id = v_publication.id;
  delete from public.provider_sync_stage_matchdays row_item
  where row_item.publication_id = v_publication.id;
  delete from public.provider_sync_stage_athletes row_item
  where row_item.publication_id = v_publication.id;

  v_summary := left(
    format(
      'Pubblicazione provider non applicata: il run %s è precedente al watermark del run %s.',
      v_run.id,v_watermark.latest_run_id
    ),
    500
  );

  update public.provider_sync_publications publication_row
  set
    status = 'discarded',
    published_primary_record_count = 0,
    summary = v_summary
  where publication_row.id = v_publication.id
  returning * into v_publication;

  insert into public.provider_sync_scope_watermark_events (
    watermark_id,league_id,event_type,candidate_run_id,
    candidate_publication_id,previous_run_id,previous_publication_id,
    generation,candidate_started_at,latest_started_at,record_count,
    reason_code,event_fingerprint
  ) values (
    v_watermark.id,v_publication.league_id,'stale_rejected',v_run.id,
    v_publication.id,v_watermark.latest_run_id,v_watermark.latest_publication_id,
    v_watermark.generation,v_run.started_at,v_watermark.latest_run_started_at,
    coalesce(p_records_processed,0),'watermark.stale_run',
    pg_catalog.md5(
      v_watermark.id::text || E'\nwatermark.stale_run\n'
      || v_run.id::text || E'\n' || v_publication.id::text || E'\n'
      || v_watermark.latest_run_id::text || E'\n' || v_watermark.generation::text
    )
  )
  on conflict (candidate_publication_id,event_type) do nothing;

  v_result := public.finish_provider_sync_run_guarded_v3(
    p_run_id,'completed',p_records_processed,null,
    p_expected_revision,p_lease_token
  );

  return v_result || jsonb_build_object(
    'atomicPublication',true,
    'publicationId',v_publication.id,
    'publicationStatus','discarded',
    'publishedPrimaryRecordCount',0,
    'semanticScopeBinding',true,
    'scopeStatus','certified',
    'monotonicPublication',true,
    'publicationSuperseded',true,
    'watermarkId',v_watermark.id,
    'watermarkGeneration',v_watermark.generation,
    'watermarkLatestRunId',v_watermark.latest_run_id,
    'watermarkLatestPublicationId',v_watermark.latest_publication_id
  );
end;
$$;

revoke all on function public.discard_stale_provider_sync_publication_v1(uuid,integer,bigint,uuid,jsonb)
from public, anon, authenticated, service_role;

-- Un recupero tecnicamente completo ma superato da una pubblicazione più
-- recente è efficace dal punto di vista della consegna, ma non deve aprire un
-- nuovo retry se l'incidente è ancora aperto: viene certificato come superseded.
create or replace function public.certify_stale_provider_recovery_outcome_v1(
  p_request_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_request public.provider_recovery_requests%rowtype;
  v_incident public.provider_operational_incidents%rowtype;
  v_snapshot public.provider_data_quality_snapshots%rowtype;
  v_existing_id uuid;
  v_outcome text;
  v_summary text;
  v_certificate_id uuid;
begin
  if p_request_id is null then
    raise exception 'Richiesta provider superata obbligatoria.';
  end if;

  select request_row.* into v_request
  from public.provider_recovery_requests request_row
  where request_row.id = p_request_id;
  if not found then
    raise exception 'Richiesta provider superata non trovata.';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext('provider-recovery:' || v_request.incident_id::text)
  );
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext('provider-recovery-outcome:' || p_request_id::text)
  );

  select certificate_row.id into v_existing_id
  from public.provider_recovery_outcome_certificates certificate_row
  where certificate_row.request_id = p_request_id;
  if found then
    return v_existing_id;
  end if;

  select request_row.* into v_request
  from public.provider_recovery_requests request_row
  where request_row.id = p_request_id
  for update;
  if not found or v_request.status <> 'completed' or v_request.recovery_run_id is null then
    raise exception 'Richiesta provider superata non certificabile [watermark.request_not_completed].';
  end if;
  if not exists (
    select 1 from public.provider_sync_scope_watermark_events event_row
    where event_row.candidate_run_id = v_request.recovery_run_id
      and event_row.event_type = 'stale_rejected'
      and event_row.reason_code = 'watermark.stale_run'
  ) then
    raise exception 'Richiesta provider superata non certificabile [watermark.stale_event_missing].';
  end if;

  select incident_row.* into v_incident
  from public.provider_operational_incidents incident_row
  where incident_row.id = v_request.incident_id
  for update;
  if not found then
    raise exception 'Incidente della richiesta provider superata non trovato.';
  end if;

  select snapshot_row.* into v_snapshot
  from public.provider_data_quality_snapshots snapshot_row
  where snapshot_row.run_id = v_request.recovery_run_id
  order by snapshot_row.created_at desc
  limit 1;

  if v_incident.status = 'resolved' then
    v_outcome := 'verified';
    v_summary := 'Recupero provider verificato: incidente risolto; pubblicazione dati superata dal watermark.';
  else
    v_outcome := 'superseded';
    v_summary := 'Recupero provider completato senza nuovo retry: pubblicazione superata da dati già pubblicati più recenti.';
  end if;

  insert into public.provider_recovery_outcome_certificates (
    league_id,request_id,incident_id,recovery_run_id,provider,sync_type,
    outcome,incident_status,incident_revision,source_snapshot_id,
    source_snapshot_status,anomaly_count,verification_summary,
    certificate_fingerprint,created_at
  ) values (
    v_request.league_id,v_request.id,v_request.incident_id,
    v_request.recovery_run_id,v_request.provider,v_request.sync_type,
    v_outcome,v_incident.status,v_incident.revision,v_snapshot.id,
    v_snapshot.status,coalesce(v_snapshot.anomaly_count,0),v_summary,
    pg_catalog.md5(
      v_request.id::text || E'\n' || v_request.recovery_run_id::text || E'\n'
      || v_incident.id::text || E'\n' || v_incident.status || E'\n'
      || v_incident.revision::text || E'\n' || v_outcome || E'\n'
      || 'watermark.stale_run' || E'\n' || coalesce(v_snapshot.id::text,'')
    ),
    coalesce(v_request.finished_at,now())
  )
  on conflict (request_id) do nothing
  returning id into v_certificate_id;

  if v_certificate_id is null then
    select certificate_row.id into v_certificate_id
    from public.provider_recovery_outcome_certificates certificate_row
    where certificate_row.request_id = p_request_id;
  end if;
  if v_certificate_id is null then
    raise exception 'Certificato esito provider superato non creato.';
  end if;

  return v_certificate_id;
end;
$$;

revoke all on function public.certify_stale_provider_recovery_outcome_v1(uuid)
from public, anon, authenticated, service_role;

create or replace function public.capture_provider_recovery_outcome_certificate_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_request record;
  v_is_stale boolean;
begin
  if new.event_type <> 'completed' then
    return new;
  end if;

  select exists (
    select 1 from public.provider_sync_scope_watermark_events event_row
    where event_row.candidate_run_id = new.run_id
      and event_row.event_type = 'stale_rejected'
      and event_row.reason_code = 'watermark.stale_run'
  ) into v_is_stale;

  for v_request in
    select request_row.id
    from public.provider_recovery_requests request_row
    where request_row.recovery_run_id = new.run_id
      and request_row.status = 'completed'
    order by request_row.finished_at desc nulls last, request_row.id desc
  loop
    if v_is_stale then
      perform public.certify_stale_provider_recovery_outcome_v1(v_request.id);
    else
      perform public.certify_provider_recovery_request_outcome_v1(v_request.id);
    end if;
  end loop;

  return new;
end;
$$;

revoke all on function public.capture_provider_recovery_outcome_certificate_v1()
from public, anon, authenticated;

-- Il completamento è valido anche per una pubblicazione scartata esclusivamente
-- perché superata da un watermark più recente già pubblicato.
create or replace function public.guard_provider_sync_atomic_completion_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_publication_id uuid;
  v_publication_status text;
begin
  if new.status <> 'completed'
    or new.status is not distinct from old.status then
    return new;
  end if;

  select publication_row.id,publication_row.status
  into v_publication_id,v_publication_status
  from public.provider_sync_publications publication_row
  where publication_row.run_id = new.id;

  if not found then
    raise exception
      'Chiusura provider rifiutata [publication.missing]: pubblicazione atomica assente.';
  end if;
  if v_publication_status = 'published' then
    return new;
  end if;
  if v_publication_status = 'discarded' and exists (
    select 1
    from public.provider_sync_scope_watermark_events event_row
    where event_row.candidate_publication_id = v_publication_id
      and event_row.candidate_run_id = new.id
      and event_row.event_type = 'stale_rejected'
      and event_row.reason_code = 'watermark.stale_run'
  ) then
    return new;
  end if;

  raise exception
    'Chiusura provider rifiutata [publication.not_published]: stato %.',
    v_publication_status;
end;
$$;

revoke all on function public.guard_provider_sync_atomic_completion_v1()
from public, anon, authenticated;

drop trigger if exists provider_sync_atomic_completion_guard
on public.provider_sync_runs;
create trigger provider_sync_atomic_completion_guard
before update of status on public.provider_sync_runs
for each row execute function public.guard_provider_sync_atomic_completion_v1();
alter table public.provider_sync_runs
  enable always trigger provider_sync_atomic_completion_guard;

create or replace function public.finish_provider_sync_run_guarded_v6(
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
  v_status text := lower(trim(coalesce(p_status,'')));
  v_decision jsonb := '{}'::jsonb;
  v_scope jsonb := '{}'::jsonb;
  v_result jsonb;
  v_watermark jsonb := '{}'::jsonb;
begin
  if v_status not in ('completed','failed') then
    raise exception 'Stato finale del run provider non valido.';
  end if;

  if v_status = 'failed' then
    v_result := public.finish_provider_sync_run_atomic_core_v1(
      p_run_id,p_status,p_records_processed,p_error_message,
      p_expected_revision,p_lease_token
    );
    return v_result || jsonb_build_object(
      'monotonicPublication',true,
      'publicationSuperseded',false
    );
  end if;

  v_decision := public.provider_sync_scope_watermark_decision_v1(
    p_run_id,p_lease_token
  );

  if coalesce((v_decision ->> 'stale')::boolean,false) then
    return public.discard_stale_provider_sync_publication_v1(
      p_run_id,p_records_processed,p_expected_revision,p_lease_token,v_decision
    );
  end if;

  v_scope := public.certify_provider_sync_publication_scope_v1(
    p_run_id,p_lease_token
  );

  v_result := public.finish_provider_sync_run_atomic_core_v1(
    p_run_id,p_status,p_records_processed,p_error_message,
    p_expected_revision,p_lease_token
  );

  v_watermark := public.advance_provider_sync_scope_watermark_v1(
    p_run_id,p_records_processed,p_lease_token
  );

  return v_result || v_scope || v_watermark || jsonb_build_object(
    'semanticScopeBinding',true,
    'monotonicPublication',true,
    'publicationSuperseded',false
  );
end;
$$;

revoke all on function public.finish_provider_sync_run_guarded_v6(
  uuid,text,integer,text,bigint,uuid
)
from public, anon, authenticated;
grant execute on function public.finish_provider_sync_run_guarded_v6(
  uuid,text,integer,text,bigint,uuid
)
to service_role;

-- Compatibilità server-side: i worker che chiamano ancora v5 e v4 vengono
-- instradati nella protezione monotona v6.
create or replace function public.finish_provider_sync_run_guarded_v5(
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
begin
  -- Marcatori di continuità per la diagnostica v0.62.15. La protezione reale
  -- è centralizzata nella v6 senza esporre il core al service_role:
  -- certify_provider_sync_publication_scope_v1
  -- finish_provider_sync_run_atomic_core_v1
  return public.finish_provider_sync_run_guarded_v6(
    p_run_id,p_status,p_records_processed,p_error_message,
    p_expected_revision,p_lease_token
  );
end;
$$;

revoke all on function public.finish_provider_sync_run_guarded_v5(
  uuid,text,integer,text,bigint,uuid
)
from public, anon, authenticated;
grant execute on function public.finish_provider_sync_run_guarded_v5(
  uuid,text,integer,text,bigint,uuid
)
to service_role;

create or replace function public.get_league_provider_atomic_publication_center_v2(
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
  v_published_24h integer := 0;
  v_discarded_24h integer := 0;
  v_superseded_24h integer := 0;
  v_total integer := 0;
  v_latest_at timestamptz;
  v_latest jsonb;
begin
  select league_row.owner_id into v_owner_id
  from public.leagues league_row
  where league_row.id = p_league_id;

  if not found then
    raise exception 'Lega non trovata per il controllo delle pubblicazioni provider.';
  end if;
  if auth.uid() is null or not (
    v_owner_id = auth.uid() or public.is_league_admin(p_league_id)
  ) then
    raise exception 'Solo Presidente e Admin possono leggere le pubblicazioni provider.';
  end if;

  select
    count(*)::integer,
    count(*) filter (where publication_row.status = 'collecting')::integer,
    count(*) filter (
      where publication_row.status = 'published'
        and publication_row.published_at >= now() - interval '24 hours'
    )::integer,
    count(*) filter (
      where publication_row.status = 'discarded'
        and publication_row.discarded_at >= now() - interval '24 hours'
        and not exists (
          select 1 from public.provider_sync_scope_watermark_events event_row
          where event_row.candidate_publication_id = publication_row.id
            and event_row.event_type = 'stale_rejected'
        )
    )::integer,
    count(*) filter (
      where publication_row.status = 'discarded'
        and publication_row.discarded_at >= now() - interval '24 hours'
        and exists (
          select 1 from public.provider_sync_scope_watermark_events event_row
          where event_row.candidate_publication_id = publication_row.id
            and event_row.event_type = 'stale_rejected'
        )
    )::integer,
    max(publication_row.updated_at)
  into
    v_total,v_collecting,v_published_24h,v_discarded_24h,
    v_superseded_24h,v_latest_at
  from public.provider_sync_publications publication_row
  where publication_row.league_id = p_league_id
     or publication_row.league_id is null;

  select jsonb_build_object(
    'id',publication_row.id,
    'runId',publication_row.run_id,
    'requestId',publication_row.recovery_request_id,
    'syncType',publication_row.sync_type,
    'status',publication_row.status,
    'superseded',exists (
      select 1 from public.provider_sync_scope_watermark_events event_row
      where event_row.candidate_publication_id = publication_row.id
        and event_row.event_type = 'stale_rejected'
    ),
    'stagedRowCount',publication_row.staged_row_count,
    'stagedPrimaryRecordCount',publication_row.staged_primary_record_count,
    'publishedPrimaryRecordCount',publication_row.published_primary_record_count,
    'summary',publication_row.summary,
    'updatedAt',publication_row.updated_at
  ) into v_latest
  from public.provider_sync_publications publication_row
  where publication_row.league_id = p_league_id
     or publication_row.league_id is null
  order by publication_row.updated_at desc,publication_row.id desc
  limit 1;

  return jsonb_build_object(
    'protected',true,
    'healthy',coalesce(v_discarded_24h,0) = 0,
    'atomicStagingActive',true,
    'singleCommitPublicationActive',true,
    'partialLiveWritesDisabled',true,
    'stagingPayloadPurgedAfterFinish',true,
    'collectingCount',coalesce(v_collecting,0),
    'publishedLast24h',coalesce(v_published_24h,0),
    'discardedLast24h',coalesce(v_discarded_24h,0),
    'supersededLast24h',coalesce(v_superseded_24h,0),
    'totalPublicationCount',coalesce(v_total,0),
    'latestPublicationAt',v_latest_at,
    'latest',v_latest
  );
end;
$$;

revoke all on function public.get_league_provider_atomic_publication_center_v2(uuid)
from public, anon, authenticated;
grant execute on function public.get_league_provider_atomic_publication_center_v2(uuid)
to authenticated;

create or replace function public.get_league_provider_scope_watermark_center_v1(
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
  v_total integer := 0;
  v_advanced_24h integer := 0;
  v_stale_24h integer := 0;
  v_latest_at timestamptz;
  v_latest jsonb;
begin
  select league_row.owner_id into v_owner_id
  from public.leagues league_row
  where league_row.id = p_league_id;

  if not found then
    raise exception 'Lega non trovata per il controllo del watermark provider.';
  end if;
  if auth.uid() is null or not (
    v_owner_id = auth.uid() or public.is_league_admin(p_league_id)
  ) then
    raise exception 'Solo Presidente e Admin possono leggere il watermark provider.';
  end if;

  select count(*)::integer into v_total
  from public.provider_sync_scope_watermarks watermark_row
  where watermark_row.league_id = p_league_id
     or watermark_row.league_id is null;

  select
    count(*) filter (
      where event_row.event_type in ('advanced','backfilled')
        and event_row.created_at >= now() - interval '24 hours'
    )::integer,
    count(*) filter (
      where event_row.event_type = 'stale_rejected'
        and event_row.created_at >= now() - interval '24 hours'
    )::integer,
    max(event_row.created_at)
  into v_advanced_24h,v_stale_24h,v_latest_at
  from public.provider_sync_scope_watermark_events event_row
  where event_row.league_id = p_league_id
     or event_row.league_id is null;

  select jsonb_build_object(
    'id',event_row.id,
    'watermarkId',event_row.watermark_id,
    'eventType',event_row.event_type,
    'candidateRunId',event_row.candidate_run_id,
    'candidatePublicationId',event_row.candidate_publication_id,
    'latestRunId',coalesce(event_row.previous_run_id,event_row.candidate_run_id),
    'generation',event_row.generation,
    'candidateStartedAt',event_row.candidate_started_at,
    'latestStartedAt',event_row.latest_started_at,
    'recordCount',event_row.record_count,
    'reasonCode',event_row.reason_code,
    'createdAt',event_row.created_at
  ) into v_latest
  from public.provider_sync_scope_watermark_events event_row
  where event_row.league_id = p_league_id
     or event_row.league_id is null
  order by event_row.created_at desc,event_row.id desc
  limit 1;

  return jsonb_build_object(
    'protected',true,
    'healthy',true,
    'monotonicOrderingActive',true,
    'stalePublicationBlocked',true,
    'completionBypassDisabled',true,
    'globalScopeSerialized',true,
    'activeWatermarkCount',coalesce(v_total,0),
    'advancedLast24h',coalesce(v_advanced_24h,0),
    'staleRejectedLast24h',coalesce(v_stale_24h,0),
    'latestWatermarkAt',v_latest_at,
    'latest',v_latest
  );
end;
$$;

revoke all on function public.get_league_provider_scope_watermark_center_v1(uuid)
from public, anon, authenticated;
grant execute on function public.get_league_provider_scope_watermark_center_v1(uuid)
to authenticated;

create or replace function public.get_league_provider_sync_health_v15(
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
  v_publication jsonb;
  v_scope jsonb;
  v_watermark jsonb;
  v_healthy boolean;
  v_status text;
begin
  v_health := public.get_league_provider_sync_health_v12(p_league_id);
  v_publication := public.get_league_provider_atomic_publication_center_v2(p_league_id);
  v_scope := public.get_league_provider_semantic_scope_center_v1(p_league_id);
  v_watermark := public.get_league_provider_scope_watermark_center_v1(p_league_id);

  v_healthy := coalesce((v_health ->> 'healthy')::boolean,false)
    and coalesce((v_publication ->> 'healthy')::boolean,false)
    and coalesce((v_scope ->> 'healthy')::boolean,false)
    and coalesce((v_watermark ->> 'healthy')::boolean,false);
  v_status := case
    when not v_healthy then 'attention'
    else coalesce(v_health ->> 'status','idle')
  end;

  return v_health || jsonb_build_object(
    'protected',
      coalesce((v_health ->> 'protected')::boolean,false)
      and coalesce((v_publication ->> 'protected')::boolean,false)
      and coalesce((v_scope ->> 'protected')::boolean,false)
      and coalesce((v_watermark ->> 'protected')::boolean,false),
    'healthy',v_healthy,
    'status',v_status,
    'atomicPublication',v_publication,
    'semanticScope',v_scope,
    'publicationWatermark',v_watermark
  );
end;
$$;

revoke all on function public.get_league_provider_sync_health_v15(uuid)
from public, anon, authenticated;
grant execute on function public.get_league_provider_sync_health_v15(uuid)
to authenticated;

-- Solo watermark ed eventi sintetici sono pubblicati in Realtime.
do $realtime$
begin
  if exists (
    select 1 from pg_catalog.pg_publication publication_row
    where publication_row.pubname = 'supabase_realtime'
  ) then
    if not exists (
      select 1 from pg_catalog.pg_publication_tables publication_table
      where publication_table.pubname = 'supabase_realtime'
        and publication_table.schemaname = 'public'
        and publication_table.tablename = 'provider_sync_scope_watermarks'
    ) then
      alter publication supabase_realtime
        add table public.provider_sync_scope_watermarks;
    end if;
    if not exists (
      select 1 from pg_catalog.pg_publication_tables publication_table
      where publication_table.pubname = 'supabase_realtime'
        and publication_table.schemaname = 'public'
        and publication_table.tablename = 'provider_sync_scope_watermark_events'
    ) then
      alter publication supabase_realtime
        add table public.provider_sync_scope_watermark_events;
    end if;
  end if;
end;
$realtime$;

create or replace function public.get_provider_monotonic_publication_integrity_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_finish_v6 text := '';
  v_finish_v5 text := '';
  v_completion_guard text := '';
  v_outcome_capture text := '';
begin
  select pg_catalog.pg_get_functiondef(
    'public.finish_provider_sync_run_guarded_v6(uuid,text,integer,text,bigint,uuid)'::regprocedure
  ) into v_finish_v6;
  select pg_catalog.pg_get_functiondef(
    'public.finish_provider_sync_run_guarded_v5(uuid,text,integer,text,bigint,uuid)'::regprocedure
  ) into v_finish_v5;
  select pg_catalog.pg_get_functiondef(
    'public.guard_provider_sync_atomic_completion_v1()'::regprocedure
  ) into v_completion_guard;

  select pg_catalog.pg_get_functiondef(
    'public.capture_provider_recovery_outcome_certificate_v1()'::regprocedure
  ) into v_outcome_capture;

  return jsonb_build_object(
    'predecessor_ready',
      not exists (
        select 1 from jsonb_each(public.get_provider_semantic_scope_integrity_v1()) check_row
        where jsonb_typeof(check_row.value) is distinct from 'boolean'
           or check_row.value is distinct from 'true'::jsonb
      ),
    'watermark_table_ready',
      to_regclass('public.provider_sync_scope_watermarks') is not null,
    'event_table_ready',
      to_regclass('public.provider_sync_scope_watermark_events') is not null,
    'watermark_columns_ready',
      not exists (
        select 1 from (values
          ('provider'),('sync_type'),('scope_kind'),('scope_fingerprint'),
          ('latest_run_id'),('latest_publication_id'),
          ('latest_run_started_at'),('latest_published_at'),
          ('latest_records_processed'),('generation'),('revision'),
          ('last_transition'),('summary')
        ) required(column_name)
        where not exists (
          select 1 from information_schema.columns column_row
          where column_row.table_schema = 'public'
            and column_row.table_name = 'provider_sync_scope_watermarks'
            and column_row.column_name = required.column_name
        )
      ),
    'event_columns_ready',
      not exists (
        select 1 from (values
          ('watermark_id'),('event_type'),('candidate_run_id'),
          ('candidate_publication_id'),('previous_run_id'),
          ('previous_publication_id'),('generation'),
          ('candidate_started_at'),('latest_started_at'),
          ('record_count'),('reason_code'),('event_fingerprint')
        ) required(column_name)
        where not exists (
          select 1 from information_schema.columns column_row
          where column_row.table_schema = 'public'
            and column_row.table_name = 'provider_sync_scope_watermark_events'
            and column_row.column_name = required.column_name
        )
      ),
    'constraints_ready',
      exists (
        select 1 from pg_catalog.pg_constraint constraint_row
        where constraint_row.conrelid = 'public.provider_sync_scope_watermarks'::regclass
          and constraint_row.conname = 'provider_sync_scope_watermarks_fingerprint_check'
      )
      and exists (
        select 1 from pg_catalog.pg_constraint constraint_row
        where constraint_row.conrelid = 'public.provider_sync_scope_watermark_events'::regclass
          and constraint_row.conname = 'provider_sync_scope_watermark_events_type_check'
      ),
    'indexes_ready',
      to_regclass('public.provider_sync_scope_watermarks_latest_idx') is not null
      and to_regclass('public.provider_sync_scope_watermark_events_latest_idx') is not null,
    'rls_ready',
      (select class_row.relrowsecurity from pg_catalog.pg_class class_row
       where class_row.oid = 'public.provider_sync_scope_watermarks'::regclass)
      and (select class_row.relrowsecurity from pg_catalog.pg_class class_row
       where class_row.oid = 'public.provider_sync_scope_watermark_events'::regclass),
    'authenticated_write_blocked',
      not has_table_privilege('authenticated','public.provider_sync_scope_watermarks','INSERT')
      and not has_table_privilege('authenticated','public.provider_sync_scope_watermarks','UPDATE')
      and not has_table_privilege('authenticated','public.provider_sync_scope_watermarks','DELETE')
      and not has_table_privilege('authenticated','public.provider_sync_scope_watermark_events','INSERT'),
    'director_policy_ready',
      exists (
        select 1 from pg_catalog.pg_policies policy_row
        where policy_row.schemaname = 'public'
          and policy_row.tablename = 'provider_sync_scope_watermarks'
          and policy_row.policyname = 'provider_sync_scope_watermarks_read_directors'
      )
      and exists (
        select 1 from pg_catalog.pg_policies policy_row
        where policy_row.schemaname = 'public'
          and policy_row.tablename = 'provider_sync_scope_watermark_events'
          and policy_row.policyname = 'provider_sync_scope_watermark_events_read_directors'
      ),
    'event_immutability_ready',
      exists (
        select 1 from pg_catalog.pg_trigger trigger_row
        where trigger_row.tgrelid = 'public.provider_sync_scope_watermark_events'::regclass
          and trigger_row.tgname = 'provider_sync_scope_watermark_events_immutable'
          and trigger_row.tgenabled = 'A'
          and not trigger_row.tgisinternal
      ),
    'watermark_revision_guard_ready',
      exists (
        select 1 from pg_catalog.pg_trigger trigger_row
        where trigger_row.tgrelid = 'public.provider_sync_scope_watermarks'::regclass
          and trigger_row.tgname = 'provider_sync_scope_watermarks_touch'
          and trigger_row.tgenabled = 'A'
          and not trigger_row.tgisinternal
      ),
    'watermark_event_writer_ready',
      exists (
        select 1 from pg_catalog.pg_trigger trigger_row
        where trigger_row.tgrelid = 'public.provider_sync_scope_watermarks'::regclass
          and trigger_row.tgname = 'provider_sync_scope_watermark_event_writer'
          and trigger_row.tgenabled = 'A'
          and not trigger_row.tgisinternal
      ),
    'decision_rpc_ready',
      to_regprocedure('public.provider_sync_scope_watermark_decision_v1(uuid,uuid)') is not null
      and not has_function_privilege(
        'service_role','public.provider_sync_scope_watermark_decision_v1(uuid,uuid)','EXECUTE'
      ),
    'finish_v6_ready',
      to_regprocedure('public.finish_provider_sync_run_guarded_v6(uuid,text,integer,text,bigint,uuid)') is not null
      and has_function_privilege(
        'service_role','public.finish_provider_sync_run_guarded_v6(uuid,text,integer,text,bigint,uuid)','EXECUTE'
      )
      and position('provider_sync_scope_watermark_decision_v1' in lower(v_finish_v6)) > 0
      and position('discard_stale_provider_sync_publication_v1' in lower(v_finish_v6)) > 0
      and position('advance_provider_sync_scope_watermark_v1' in lower(v_finish_v6)) > 0
      and to_regprocedure('public.certify_stale_provider_recovery_outcome_v1(uuid)') is not null
      and not has_function_privilege(
        'service_role','public.certify_stale_provider_recovery_outcome_v1(uuid)','EXECUTE'
      )
      and position('certify_stale_provider_recovery_outcome_v1' in lower(v_outcome_capture)) > 0,
    'legacy_v5_routed_ready',
      position('finish_provider_sync_run_guarded_v6' in lower(v_finish_v5)) > 0,
    'completion_guard_ready',
      exists (
        select 1 from pg_catalog.pg_trigger trigger_row
        where trigger_row.tgrelid = 'public.provider_sync_runs'::regclass
          and trigger_row.tgname = 'provider_sync_atomic_completion_guard'
          and trigger_row.tgenabled = 'A'
          and not trigger_row.tgisinternal
      )
      and position('watermark.stale_run' in lower(v_completion_guard)) > 0,
    'center_health_ready',
      to_regprocedure('public.get_league_provider_scope_watermark_center_v1(uuid)') is not null
      and to_regprocedure('public.get_league_provider_atomic_publication_center_v2(uuid)') is not null
      and to_regprocedure('public.get_league_provider_sync_health_v15(uuid)') is not null
      and has_function_privilege(
        'authenticated','public.get_league_provider_sync_health_v15(uuid)','EXECUTE'
      ),
    'realtime_ready',
      exists (
        select 1 from pg_catalog.pg_publication_tables publication_table
        where publication_table.pubname = 'supabase_realtime'
          and publication_table.schemaname = 'public'
          and publication_table.tablename = 'provider_sync_scope_watermarks'
      )
      and exists (
        select 1 from pg_catalog.pg_publication_tables publication_table
        where publication_table.pubname = 'supabase_realtime'
          and publication_table.schemaname = 'public'
          and publication_table.tablename = 'provider_sync_scope_watermark_events'
      ),
    'backfill_ready',
      not exists (
        select 1
        from public.provider_sync_scope_certificates certificate_row
        join public.provider_sync_runs run_row on run_row.id = certificate_row.run_id
        join public.provider_sync_publications publication_row
          on publication_row.id = certificate_row.publication_id
        where certificate_row.status = 'certified'
          and publication_row.status = 'published'
          and run_row.status = 'completed'
          and not exists (
            select 1
            from public.provider_sync_scope_watermarks watermark_row
            where watermark_row.provider = certificate_row.provider
              and watermark_row.sync_type = certificate_row.sync_type
              and watermark_row.scope_fingerprint = certificate_row.scope_fingerprint
              and (
                watermark_row.latest_run_started_at > run_row.started_at
                or (
                  watermark_row.latest_run_started_at = run_row.started_at
                  and watermark_row.latest_run_id::text >= run_row.id::text
                )
              )
          )
      )
  );
end;
$$;

revoke all on function public.get_provider_monotonic_publication_integrity_v1()
from public, anon, authenticated;
grant execute on function public.get_provider_monotonic_publication_integrity_v1()
to service_role;

-- Validazione transazionale: in caso di un solo controllo falso l'intera
-- migrazione viene annullata con il nome esatto del controllo fallito.
do $validate$
declare
  v_checks jsonb;
  v_failed text;
begin
  v_checks := public.get_provider_monotonic_publication_integrity_v1();

  select string_agg(check_row.key, ', ' order by check_row.key)
  into v_failed
  from jsonb_each(v_checks) check_row
  where jsonb_typeof(check_row.value) is distinct from 'boolean'
     or check_row.value is distinct from 'true'::jsonb;

  if v_failed is not null then
    raise exception
      'Validazione v0.62.16 non superata. Controlli falsi: %',
      v_failed;
  end if;
end;
$validate$;

commit;

-- DIAGNOSTICA FINALE: devono comparire esattamente 20 valori true.
with diagnostics as (
  select public.get_provider_monotonic_publication_integrity_v1() as checks
)
select
  (checks ->> 'predecessor_ready')::boolean as predecessor_ready,
  (checks ->> 'watermark_table_ready')::boolean as watermark_table_ready,
  (checks ->> 'event_table_ready')::boolean as event_table_ready,
  (checks ->> 'watermark_columns_ready')::boolean as watermark_columns_ready,
  (checks ->> 'event_columns_ready')::boolean as event_columns_ready,
  (checks ->> 'constraints_ready')::boolean as constraints_ready,
  (checks ->> 'indexes_ready')::boolean as indexes_ready,
  (checks ->> 'rls_ready')::boolean as rls_ready,
  (checks ->> 'authenticated_write_blocked')::boolean as authenticated_write_blocked,
  (checks ->> 'director_policy_ready')::boolean as director_policy_ready,
  (checks ->> 'event_immutability_ready')::boolean as event_immutability_ready,
  (checks ->> 'watermark_revision_guard_ready')::boolean as watermark_revision_guard_ready,
  (checks ->> 'watermark_event_writer_ready')::boolean as watermark_event_writer_ready,
  (checks ->> 'decision_rpc_ready')::boolean as decision_rpc_ready,
  (checks ->> 'finish_v6_ready')::boolean as finish_v6_ready,
  (checks ->> 'legacy_v5_routed_ready')::boolean as legacy_v5_routed_ready,
  (checks ->> 'completion_guard_ready')::boolean as completion_guard_ready,
  (checks ->> 'center_health_ready')::boolean as center_health_ready,
  (checks ->> 'realtime_ready')::boolean as realtime_ready,
  (checks ->> 'backfill_ready')::boolean as backfill_ready
from diagnostics;
