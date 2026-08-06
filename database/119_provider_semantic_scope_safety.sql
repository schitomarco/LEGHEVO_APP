-- LEGHEVO v0.62.15
-- Vincolo semantico dello scope e isolamento del write-set provider.
-- Eseguire dopo database/118_provider_atomic_publication_safety.sql.

begin;

-- Preflight esplicito: nessuna dipendenza viene presunta.
do $preflight$
declare
  v_missing text[] := array[]::text[];
  v_required text;
  v_active_run boolean := false;
begin
  if to_regprocedure('public.get_provider_atomic_publication_integrity_v1()') is null then
    v_missing := array_append(v_missing, 'function public.get_provider_atomic_publication_integrity_v1()');
  end if;
  if to_regprocedure('public.normalize_provider_sync_request_v1(jsonb)') is null then
    v_missing := array_append(v_missing, 'function public.normalize_provider_sync_request_v1(jsonb)');
  end if;
  if to_regprocedure('public.assert_provider_sync_worker_lease_v1(uuid,uuid)') is null then
    v_missing := array_append(v_missing, 'function public.assert_provider_sync_worker_lease_v1(uuid,uuid)');
  end if;
  if to_regprocedure('public.refresh_provider_sync_publication_counts_v1(uuid)') is null then
    v_missing := array_append(v_missing, 'function public.refresh_provider_sync_publication_counts_v1(uuid)');
  end if;
  if to_regprocedure('public.finish_provider_sync_run_guarded_v4(uuid,text,integer,text,bigint,uuid)') is null then
    v_missing := array_append(v_missing, 'function public.finish_provider_sync_run_guarded_v4(uuid,text,integer,text,bigint,uuid)');
  end if;
  if to_regprocedure('public.provider_recovery_retry_policy_v1(text,integer,text)') is null then
    v_missing := array_append(v_missing, 'function public.provider_recovery_retry_policy_v1(text,integer,text)');
  end if;
  if to_regprocedure('public.get_league_provider_sync_health_v13(uuid)') is null then
    v_missing := array_append(v_missing, 'function public.get_league_provider_sync_health_v13(uuid)');
  end if;
  if to_regprocedure('public.is_league_admin(uuid)') is null then
    v_missing := array_append(v_missing, 'function public.is_league_admin(uuid)');
  end if;
  if to_regprocedure('auth.uid()') is null then
    v_missing := array_append(v_missing, 'function auth.uid()');
  end if;
  if to_regprocedure('gen_random_uuid()') is null then
    v_missing := array_append(v_missing, 'function gen_random_uuid()');
  end if;
  if to_regprocedure('pg_catalog.md5(text)') is null then
    v_missing := array_append(v_missing, 'function pg_catalog.md5(text)');
  end if;

  foreach v_required in array array[
    'public.provider_sync_runs',
    'public.provider_sync_worker_leases',
    'public.provider_sync_publications',
    'public.provider_recovery_requests',
    'public.provider_sync_stage_athletes',
    'public.provider_sync_stage_roles',
    'public.provider_sync_stage_matchdays',
    'public.provider_sync_stage_fixtures',
    'public.provider_sync_stage_scores',
    'public.provider_fixtures',
    'public.leagues'
  ]
  loop
    if to_regclass(v_required) is null then
      v_missing := array_append(v_missing, 'table ' || v_required);
    end if;
  end loop;

  for v_required in
    select required.table_name || '.' || required.column_name
    from (values
      ('provider_sync_runs','id'),('provider_sync_runs','provider'),
      ('provider_sync_runs','sync_type'),('provider_sync_runs','requested_for'),
      ('provider_sync_runs','status'),('provider_sync_runs','revision'),
      ('provider_sync_worker_leases','run_id'),
      ('provider_sync_worker_leases','lease_token'),
      ('provider_sync_worker_leases','status'),
      ('provider_sync_worker_leases','lease_expires_at'),
      ('provider_sync_worker_leases','recovery_request_id'),
      ('provider_sync_worker_leases','league_id'),
      ('provider_sync_worker_leases','lease_epoch'),
      ('provider_sync_publications','id'),('provider_sync_publications','run_id'),
      ('provider_sync_publications','recovery_request_id'),
      ('provider_sync_publications','league_id'),('provider_sync_publications','provider'),
      ('provider_sync_publications','sync_type'),('provider_sync_publications','status'),
      ('provider_sync_publications','staged_primary_record_count'),
      ('provider_sync_publications','published_primary_record_count'),
      ('provider_sync_publications','summary'),
      ('provider_sync_publications','run_revision'),
      ('provider_sync_publications','revision'),
      ('provider_sync_publications','updated_at'),
      ('provider_sync_publications','published_at'),
      ('provider_sync_publications','discarded_at'),
      ('provider_sync_stage_athletes','publication_id'),
      ('provider_sync_stage_athletes','athlete_id'),
      ('provider_sync_stage_athletes','provider'),
      ('provider_sync_stage_roles','publication_id'),
      ('provider_sync_stage_roles','athlete_id'),
      ('provider_sync_stage_roles','mode'),
      ('provider_sync_stage_matchdays','publication_id'),
      ('provider_sync_stage_matchdays','matchday_id'),
      ('provider_sync_stage_matchdays','competition_code'),
      ('provider_sync_stage_matchdays','season'),
      ('provider_sync_stage_fixtures','publication_id'),
      ('provider_sync_stage_fixtures','provider'),
      ('provider_sync_stage_fixtures','provider_fixture_id'),
      ('provider_sync_stage_fixtures','competition_code'),
      ('provider_sync_stage_fixtures','season'),
      ('provider_sync_stage_fixtures','matchday_id'),
      ('provider_sync_stage_fixtures','kickoff_at'),
      ('provider_sync_stage_scores','publication_id'),
      ('provider_sync_stage_scores','athlete_id'),
      ('provider_sync_stage_scores','matchday_id'),
      ('provider_sync_stage_scores','provider_fixture_id'),
      ('provider_fixtures','provider'),('provider_fixtures','provider_fixture_id'),
      ('provider_fixtures','matchday_id'),('provider_recovery_requests','id'),
      ('leagues','id'),('leagues','owner_id')
    ) as required(table_name,column_name)
    where not exists (
      select 1
      from information_schema.columns column_row
      where column_row.table_schema = 'public'
        and column_row.table_name = required.table_name
        and column_row.column_name = required.column_name
    )
  loop
    v_missing := array_append(v_missing, 'column public.' || v_required);
  end loop;

  if to_regclass('public.provider_sync_runs') is not null then
    execute 'select exists (select 1 from public.provider_sync_runs where status = ''running'')'
    into v_active_run;
    if v_active_run then
      v_missing := array_append(
        v_missing,
        'operational condition: no provider_sync_runs row may be running during installation'
      );
    end if;
  end if;

  if coalesce(array_length(v_missing, 1), 0) > 0 then
    raise exception
      'Preflight v0.62.15 non superato. Dipendenze mancanti: %',
      array_to_string(v_missing, '; ');
  end if;
end;
$preflight$;

create table if not exists public.provider_sync_scope_certificates (
  id uuid primary key default gen_random_uuid(),
  publication_id uuid not null unique
    references public.provider_sync_publications(id) on delete restrict,
  run_id uuid not null unique
    references public.provider_sync_runs(id) on delete restrict,
  recovery_request_id uuid
    references public.provider_recovery_requests(id) on delete set null,
  league_id uuid references public.leagues(id) on delete set null,
  provider text not null,
  sync_type text not null,
  scope_kind text not null,
  scope_fingerprint text not null,
  requested_season integer,
  requested_date date,
  requested_fixture_id text,
  status text not null default 'collecting',
  observed_athlete_count integer not null default 0,
  observed_role_count integer not null default 0,
  observed_matchday_count integer not null default 0,
  observed_fixture_count integer not null default 0,
  observed_score_count integer not null default 0,
  summary text not null default 'Write-set provider in acquisizione.',
  run_revision bigint not null,
  revision bigint not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  certified_at timestamptz,
  rejected_at timestamptz,
  constraint provider_sync_scope_certificates_sync_type_check check (
    sync_type in ('sync-season-players','sync-fixtures','sync-fixture-players')
  ),
  constraint provider_sync_scope_certificates_scope_kind_check check (
    scope_kind in ('season','date','fixture')
  ),
  constraint provider_sync_scope_certificates_fingerprint_check check (
    scope_fingerprint ~ '^[0-9a-f]{32}$'
  ),
  constraint provider_sync_scope_certificates_status_check check (
    status in ('collecting','certified','rejected')
  ),
  constraint provider_sync_scope_certificates_counts_check check (
    observed_athlete_count between 0 and 1000000
    and observed_role_count between 0 and 2000000
    and observed_matchday_count between 0 and 100000
    and observed_fixture_count between 0 and 1000000
    and observed_score_count between 0 and 1000000
  ),
  constraint provider_sync_scope_certificates_summary_check check (
    length(summary) between 1 and 500 and summary !~ E'[\r\n]'
  ),
  constraint provider_sync_scope_certificates_revision_check check (
    run_revision > 0 and revision > 0
  ),
  constraint provider_sync_scope_certificates_requested_scope_check check (
    (scope_kind = 'season' and requested_season is not null
      and requested_date is null and requested_fixture_id is null)
    or (scope_kind = 'date' and requested_season is not null
      and requested_date is not null and requested_fixture_id is null)
    or (scope_kind = 'fixture' and requested_season is null
      and requested_date is null and requested_fixture_id is not null)
  ),
  constraint provider_sync_scope_certificates_terminal_check check (
    (status = 'collecting' and certified_at is null and rejected_at is null)
    or (status = 'certified' and certified_at is not null and rejected_at is null)
    or (status = 'rejected' and certified_at is null and rejected_at is not null)
  )
);

create table if not exists public.provider_sync_scope_events (
  id uuid primary key default gen_random_uuid(),
  certificate_id uuid not null
    references public.provider_sync_scope_certificates(id) on delete restrict,
  publication_id uuid not null
    references public.provider_sync_publications(id) on delete restrict,
  run_id uuid not null references public.provider_sync_runs(id) on delete restrict,
  league_id uuid references public.leagues(id) on delete set null,
  event_type text not null check (
    event_type in ('collecting','certified','rejected')
  ),
  revision bigint not null check (revision > 0),
  primary_record_count integer not null check (
    primary_record_count between 0 and 1000000
  ),
  event_fingerprint text not null check (
    event_fingerprint ~ '^[0-9a-f]{32}$'
  ),
  created_at timestamptz not null default now(),
  unique (certificate_id, revision)
);

create index if not exists provider_sync_scope_certificates_league_idx
  on public.provider_sync_scope_certificates (league_id, updated_at desc);
create index if not exists provider_sync_scope_certificates_status_idx
  on public.provider_sync_scope_certificates (status, updated_at desc);
create index if not exists provider_sync_scope_certificates_scope_idx
  on public.provider_sync_scope_certificates (
    provider, sync_type, scope_fingerprint, updated_at desc
  );
create index if not exists provider_sync_scope_events_league_idx
  on public.provider_sync_scope_events (league_id, created_at desc);

alter table public.provider_sync_scope_certificates enable row level security;
alter table public.provider_sync_scope_certificates replica identity full;
alter table public.provider_sync_scope_events enable row level security;
alter table public.provider_sync_scope_events replica identity full;

revoke all on table public.provider_sync_scope_certificates
from public, anon, authenticated, service_role;
revoke all on table public.provider_sync_scope_events
from public, anon, authenticated, service_role;
grant select on table public.provider_sync_scope_certificates to service_role;
grant select on table public.provider_sync_scope_events to service_role;

drop policy if exists provider_sync_scope_certificates_read_directors
on public.provider_sync_scope_certificates;
create policy provider_sync_scope_certificates_read_directors
on public.provider_sync_scope_certificates
for select to authenticated
using (
  (
    league_id is not null
    and exists (
      select 1
      from public.leagues league_row
      where league_row.id = provider_sync_scope_certificates.league_id
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

drop policy if exists provider_sync_scope_events_read_directors
on public.provider_sync_scope_events;
create policy provider_sync_scope_events_read_directors
on public.provider_sync_scope_events
for select to authenticated
using (
  (
    league_id is not null
    and exists (
      select 1
      from public.leagues league_row
      where league_row.id = provider_sync_scope_events.league_id
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

grant select on table public.provider_sync_scope_certificates to authenticated;
grant select on table public.provider_sync_scope_events to authenticated;

create or replace function public.provider_sync_scope_metadata_v1(
  p_sync_type text,
  p_requested_for jsonb
)
returns jsonb
language plpgsql
immutable
security definer
set search_path = ''
as $$
declare
  v_sync_type text := lower(trim(coalesce(p_sync_type, '')));
  v_request jsonb;
  v_action text;
begin
  v_request := public.normalize_provider_sync_request_v1(p_requested_for);
  v_action := v_request ->> 'action';

  if v_action is distinct from v_sync_type then
    raise exception
      'Ambito provider non valido [scope.action_mismatch]: run %, richiesta %.',
      v_sync_type,
      coalesce(v_action, 'null');
  end if;

  if v_sync_type = 'sync-season-players' then
    return jsonb_build_object(
      'scopeKind', 'season',
      'scopeFingerprint', pg_catalog.md5(v_sync_type || E'\n' || v_request::text),
      'requestedSeason', (v_request ->> 'season')::integer,
      'requestedDate', null,
      'requestedFixtureId', null,
      'allowedOperations', jsonb_build_array('upsert-athletes','upsert-athlete-roles')
    );
  elsif v_sync_type = 'sync-fixtures' then
    return jsonb_build_object(
      'scopeKind', 'date',
      'scopeFingerprint', pg_catalog.md5(v_sync_type || E'\n' || v_request::text),
      'requestedSeason', (v_request ->> 'season')::integer,
      'requestedDate', v_request ->> 'date',
      'requestedFixtureId', null,
      'allowedOperations', jsonb_build_array('upsert-matchday','upsert-provider-fixtures')
    );
  elsif v_sync_type = 'sync-fixture-players' then
    return jsonb_build_object(
      'scopeKind', 'fixture',
      'scopeFingerprint', pg_catalog.md5(v_sync_type || E'\n' || v_request::text),
      'requestedSeason', null,
      'requestedDate', null,
      'requestedFixtureId', v_request ->> 'fixtureId',
      'allowedOperations', jsonb_build_array(
        'upsert-athletes','upsert-athlete-roles','upsert-player-scores'
      )
    );
  end if;

  raise exception
    'Ambito provider non valido [scope.sync_type_unknown]: %.',
    v_sync_type;
end;
$$;

revoke all on function public.provider_sync_scope_metadata_v1(text,jsonb)
from public, anon, authenticated;
grant execute on function public.provider_sync_scope_metadata_v1(text,jsonb)
to service_role;

create or replace function public.touch_provider_sync_scope_certificate_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'UPDATE' then
    if row(
      new.publication_id,new.run_id,new.recovery_request_id,new.league_id,
      new.provider,new.sync_type,new.scope_kind,new.scope_fingerprint,
      new.requested_season,new.requested_date,new.requested_fixture_id,
      new.run_revision,new.created_at
    ) is distinct from row(
      old.publication_id,old.run_id,old.recovery_request_id,old.league_id,
      old.provider,old.sync_type,old.scope_kind,old.scope_fingerprint,
      old.requested_season,old.requested_date,old.requested_fixture_id,
      old.run_revision,old.created_at
    ) then
      raise exception 'Identità del certificato scope provider non modificabile.';
    end if;
    if old.status in ('certified','rejected') then
      raise exception 'Certificato scope provider terminale non modificabile.';
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
  end if;
  return new;
end;
$$;

revoke all on function public.touch_provider_sync_scope_certificate_v1()
from public, anon, authenticated;

drop trigger if exists provider_sync_scope_certificates_touch on public.provider_sync_scope_certificates;
create trigger provider_sync_scope_certificates_touch
before update on public.provider_sync_scope_certificates
for each row execute function public.touch_provider_sync_scope_certificate_v1();

create or replace function public.write_provider_sync_scope_event_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_primary integer;
begin
  if tg_op = 'UPDATE' and new.status is not distinct from old.status then
    return new;
  end if;

  v_primary := case new.sync_type
    when 'sync-season-players' then new.observed_athlete_count
    when 'sync-fixtures' then new.observed_fixture_count
    when 'sync-fixture-players' then new.observed_score_count
    else 0
  end;

  insert into public.provider_sync_scope_events (
    certificate_id,publication_id,run_id,league_id,event_type,
    revision,primary_record_count,event_fingerprint
  ) values (
    new.id,new.publication_id,new.run_id,new.league_id,new.status,
    new.revision,v_primary,
    pg_catalog.md5(
      new.id::text || E'\n' || new.status || E'\n'
      || new.revision::text || E'\n' || v_primary::text
    )
  )
  on conflict (certificate_id,revision) do nothing;

  return new;
end;
$$;

revoke all on function public.write_provider_sync_scope_event_v1()
from public, anon, authenticated;

drop trigger if exists provider_sync_scope_event_writer on public.provider_sync_scope_certificates;
create trigger provider_sync_scope_event_writer
after insert or update of status on public.provider_sync_scope_certificates
for each row execute function public.write_provider_sync_scope_event_v1();

create or replace function public.prevent_provider_sync_scope_event_mutation_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  raise exception 'Gli eventi dello scope provider sono immutabili.';
end;
$$;

revoke all on function public.prevent_provider_sync_scope_event_mutation_v1()
from public, anon, authenticated;

drop trigger if exists provider_sync_scope_events_immutable on public.provider_sync_scope_events;
create trigger provider_sync_scope_events_immutable
before update or delete on public.provider_sync_scope_events
for each row execute function public.prevent_provider_sync_scope_event_mutation_v1();
alter table public.provider_sync_scope_events
  enable always trigger provider_sync_scope_events_immutable;

create or replace function public.ensure_provider_sync_scope_certificate_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_run public.provider_sync_runs%rowtype;
  v_metadata jsonb;
begin
  select run_row.* into v_run
  from public.provider_sync_runs run_row
  where run_row.id = new.run_id;

  if not found then
    raise exception 'Run provider non trovato durante la creazione del certificato scope.';
  end if;

  v_metadata := public.provider_sync_scope_metadata_v1(
    v_run.sync_type,
    v_run.requested_for
  );

  insert into public.provider_sync_scope_certificates (
    publication_id,run_id,recovery_request_id,league_id,provider,sync_type,
    scope_kind,scope_fingerprint,requested_season,requested_date,
    requested_fixture_id,status,summary,run_revision
  ) values (
    new.id,new.run_id,new.recovery_request_id,new.league_id,new.provider,new.sync_type,
    v_metadata ->> 'scopeKind',v_metadata ->> 'scopeFingerprint',
    nullif(v_metadata ->> 'requestedSeason','')::integer,
    nullif(v_metadata ->> 'requestedDate','')::date,
    nullif(v_metadata ->> 'requestedFixtureId',''),
    case new.status when 'published' then 'certified'
      when 'discarded' then 'rejected' else 'collecting' end,
    case new.status
      when 'published' then 'Pubblicazione storica acquisita come scope già certificato.'
      when 'discarded' then 'Pubblicazione storica acquisita come scope respinto.'
      else 'Write-set provider in acquisizione.'
    end,
    new.run_revision
  )
  on conflict (publication_id) do nothing;

  return new;
end;
$$;

revoke all on function public.ensure_provider_sync_scope_certificate_v1()
from public, anon, authenticated;

drop trigger if exists provider_sync_scope_certificate_creator on public.provider_sync_publications;
create trigger provider_sync_scope_certificate_creator
after insert on public.provider_sync_publications
for each row execute function public.ensure_provider_sync_scope_certificate_v1();

-- Backfill idempotente delle pubblicazioni create prima della v0.62.15.
insert into public.provider_sync_scope_certificates (
  publication_id,run_id,recovery_request_id,league_id,provider,sync_type,
  scope_kind,scope_fingerprint,requested_season,requested_date,
  requested_fixture_id,status,observed_athlete_count,observed_role_count,
  observed_matchday_count,observed_fixture_count,observed_score_count,
  summary,run_revision,certified_at,rejected_at
)
select
  publication_row.id,publication_row.run_id,publication_row.recovery_request_id,
  publication_row.league_id,publication_row.provider,publication_row.sync_type,
  metadata.value ->> 'scopeKind',metadata.value ->> 'scopeFingerprint',
  nullif(metadata.value ->> 'requestedSeason','')::integer,
  nullif(metadata.value ->> 'requestedDate','')::date,
  nullif(metadata.value ->> 'requestedFixtureId',''),
  case publication_row.status when 'published' then 'certified'
    when 'discarded' then 'rejected' else 'collecting' end,
  (select count(*)::integer from public.provider_sync_stage_athletes row_item
    where row_item.publication_id = publication_row.id),
  (select count(*)::integer from public.provider_sync_stage_roles row_item
    where row_item.publication_id = publication_row.id),
  (select count(*)::integer from public.provider_sync_stage_matchdays row_item
    where row_item.publication_id = publication_row.id),
  (select count(*)::integer from public.provider_sync_stage_fixtures row_item
    where row_item.publication_id = publication_row.id),
  (select count(*)::integer from public.provider_sync_stage_scores row_item
    where row_item.publication_id = publication_row.id),
  case publication_row.status
    when 'published' then 'Pubblicazione storica acquisita come scope già certificato.'
    when 'discarded' then 'Pubblicazione storica acquisita come scope respinto.'
    else 'Write-set provider storico ancora in acquisizione.'
  end,
  publication_row.run_revision,
  case when publication_row.status = 'published'
    then coalesce(publication_row.published_at,publication_row.updated_at) end,
  case when publication_row.status = 'discarded'
    then coalesce(publication_row.discarded_at,publication_row.updated_at) end
from public.provider_sync_publications publication_row
join public.provider_sync_runs run_row on run_row.id = publication_row.run_id
cross join lateral (
  select public.provider_sync_scope_metadata_v1(
    run_row.sync_type,run_row.requested_for
  ) as value
) metadata
on conflict (publication_id) do nothing;

create or replace function public.validate_provider_sync_stage_scope_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_publication public.provider_sync_publications%rowtype;
  v_run public.provider_sync_runs%rowtype;
  v_certificate public.provider_sync_scope_certificates%rowtype;
  v_operation text;
  v_allowed jsonb;
  v_requested_for jsonb;
  v_expected_matchday uuid;
begin
  select publication_row.* into v_publication
  from public.provider_sync_publications publication_row
  where publication_row.id = new.publication_id;
  if not found then
    raise exception 'Ambito provider non valido [scope.publication_missing].';
  end if;

  select run_row.* into v_run
  from public.provider_sync_runs run_row
  where run_row.id = v_publication.run_id;
  if not found or v_run.status <> 'running' then
    raise exception 'Ambito provider non valido [scope.run_not_running].';
  end if;

  select certificate_row.* into v_certificate
  from public.provider_sync_scope_certificates certificate_row
  where certificate_row.publication_id = new.publication_id;
  if not found or v_certificate.status <> 'collecting' then
    raise exception 'Ambito provider non valido [scope.certificate_not_collecting].';
  end if;

  v_requested_for := public.normalize_provider_sync_request_v1(v_run.requested_for);
  v_allowed := public.provider_sync_scope_metadata_v1(
    v_run.sync_type,v_run.requested_for
  ) -> 'allowedOperations';

  v_operation := case tg_table_name
    when 'provider_sync_stage_athletes' then 'upsert-athletes'
    when 'provider_sync_stage_roles' then 'upsert-athlete-roles'
    when 'provider_sync_stage_matchdays' then 'upsert-matchday'
    when 'provider_sync_stage_fixtures' then 'upsert-provider-fixtures'
    when 'provider_sync_stage_scores' then 'upsert-player-scores'
    else null
  end;

  if v_operation is null or not (v_allowed ? v_operation) then
    raise exception
      'Ambito provider non valido [scope.operation_not_allowed]: % non consentita per %.',
      coalesce(v_operation,tg_table_name),v_run.sync_type;
  end if;

  if tg_table_name = 'provider_sync_stage_athletes' then
    if new.provider is distinct from v_publication.provider then
      raise exception 'Ambito provider non valido [scope.athlete_provider_mismatch].';
    end if;

  elsif tg_table_name = 'provider_sync_stage_roles' then
    if not exists (
      select 1 from public.provider_sync_stage_athletes athlete_row
      where athlete_row.publication_id = new.publication_id
        and athlete_row.athlete_id = new.athlete_id
    ) then
      raise exception 'Ambito provider non valido [scope.role_without_staged_athlete].';
    end if;

  elsif tg_table_name = 'provider_sync_stage_matchdays' then
    if new.competition_code <> 'IT-SA'
      or new.season <> (v_requested_for ->> 'season') then
      raise exception 'Ambito provider non valido [scope.matchday_request_mismatch].';
    end if;

  elsif tg_table_name = 'provider_sync_stage_fixtures' then
    if new.provider is distinct from v_publication.provider
      or new.competition_code <> 'IT-SA'
      or new.season <> (v_requested_for ->> 'season')
      or (new.kickoff_at at time zone 'UTC')::date
        <> (v_requested_for ->> 'date')::date then
      raise exception 'Ambito provider non valido [scope.fixture_request_mismatch].';
    end if;
    if not exists (
      select 1 from public.provider_sync_stage_matchdays matchday_row
      where matchday_row.publication_id = new.publication_id
        and matchday_row.matchday_id = new.matchday_id
        and matchday_row.competition_code = new.competition_code
        and matchday_row.season = new.season
    ) then
      raise exception 'Ambito provider non valido [scope.fixture_without_staged_matchday].';
    end if;

  elsif tg_table_name = 'provider_sync_stage_scores' then
    if new.provider_fixture_id is distinct from (v_requested_for ->> 'fixtureId') then
      raise exception 'Ambito provider non valido [scope.score_fixture_mismatch].';
    end if;
    select fixture_row.matchday_id into v_expected_matchday
    from public.provider_fixtures fixture_row
    where fixture_row.provider = v_publication.provider
      and fixture_row.provider_fixture_id = (v_requested_for ->> 'fixtureId')
    limit 1;
    if v_expected_matchday is null
      or new.matchday_id is distinct from v_expected_matchday then
      raise exception 'Ambito provider non valido [scope.score_matchday_mismatch].';
    end if;
    if not exists (
      select 1 from public.provider_sync_stage_athletes athlete_row
      where athlete_row.publication_id = new.publication_id
        and athlete_row.athlete_id = new.athlete_id
    ) then
      raise exception 'Ambito provider non valido [scope.score_without_staged_athlete].';
    end if;
  end if;

  return new;
end;
$$;

revoke all on function public.validate_provider_sync_stage_scope_v1()
from public, anon, authenticated;

drop trigger if exists provider_sync_stage_athletes_scope_guard on public.provider_sync_stage_athletes;
create trigger provider_sync_stage_athletes_scope_guard
before insert or update on public.provider_sync_stage_athletes
for each row execute function public.validate_provider_sync_stage_scope_v1();
alter table public.provider_sync_stage_athletes
  enable always trigger provider_sync_stage_athletes_scope_guard;
drop trigger if exists provider_sync_stage_roles_scope_guard on public.provider_sync_stage_roles;
create trigger provider_sync_stage_roles_scope_guard
before insert or update on public.provider_sync_stage_roles
for each row execute function public.validate_provider_sync_stage_scope_v1();
alter table public.provider_sync_stage_roles
  enable always trigger provider_sync_stage_roles_scope_guard;
drop trigger if exists provider_sync_stage_matchdays_scope_guard on public.provider_sync_stage_matchdays;
create trigger provider_sync_stage_matchdays_scope_guard
before insert or update on public.provider_sync_stage_matchdays
for each row execute function public.validate_provider_sync_stage_scope_v1();
alter table public.provider_sync_stage_matchdays
  enable always trigger provider_sync_stage_matchdays_scope_guard;
drop trigger if exists provider_sync_stage_fixtures_scope_guard on public.provider_sync_stage_fixtures;
create trigger provider_sync_stage_fixtures_scope_guard
before insert or update on public.provider_sync_stage_fixtures
for each row execute function public.validate_provider_sync_stage_scope_v1();
alter table public.provider_sync_stage_fixtures
  enable always trigger provider_sync_stage_fixtures_scope_guard;
drop trigger if exists provider_sync_stage_scores_scope_guard on public.provider_sync_stage_scores;
create trigger provider_sync_stage_scores_scope_guard
before insert or update on public.provider_sync_stage_scores
for each row execute function public.validate_provider_sync_stage_scope_v1();
alter table public.provider_sync_stage_scores
  enable always trigger provider_sync_stage_scores_scope_guard;

create or replace function public.certify_provider_sync_publication_scope_v1(
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
  v_request jsonb;
  v_athletes integer;
  v_roles integer;
  v_matchdays integer;
  v_fixtures integer;
  v_scores integer;
  v_invalid integer := 0;
begin
  perform public.assert_provider_sync_worker_lease_v1(p_run_id,p_lease_token);

  select run_row.* into v_run
  from public.provider_sync_runs run_row
  where run_row.id = p_run_id
  for update;
  if not found or v_run.status <> 'running' then
    raise exception 'Ambito provider non valido [scope.run_not_running_at_certification].';
  end if;

  perform public.ensure_provider_sync_publication_v1(p_run_id,p_lease_token);

  select publication_row.* into v_publication
  from public.provider_sync_publications publication_row
  where publication_row.run_id = p_run_id
  for update;
  if not found or v_publication.status <> 'collecting' then
    raise exception 'Ambito provider non valido [scope.publication_not_collecting].';
  end if;

  select certificate_row.* into v_certificate
  from public.provider_sync_scope_certificates certificate_row
  where certificate_row.publication_id = v_publication.id
  for update;
  if not found then
    raise exception 'Ambito provider non valido [scope.certificate_missing].';
  end if;
  if v_certificate.status = 'certified' then
    return jsonb_build_object(
      'semanticScope',true,'scopeStatus','certified',
      'certificateId',v_certificate.id,'scopeFingerprint',v_certificate.scope_fingerprint
    );
  end if;
  if v_certificate.status <> 'collecting' then
    raise exception 'Ambito provider non valido [scope.certificate_terminal].';
  end if;

  perform public.refresh_provider_sync_publication_counts_v1(v_publication.id);
  select publication_row.* into v_publication
  from public.provider_sync_publications publication_row
  where publication_row.id = v_publication.id
  for update;
  v_request := public.normalize_provider_sync_request_v1(v_run.requested_for);

  select count(*)::integer into v_athletes
  from public.provider_sync_stage_athletes row_item
  where row_item.publication_id = v_publication.id;
  select count(*)::integer into v_roles
  from public.provider_sync_stage_roles row_item
  where row_item.publication_id = v_publication.id;
  select count(*)::integer into v_matchdays
  from public.provider_sync_stage_matchdays row_item
  where row_item.publication_id = v_publication.id;
  select count(*)::integer into v_fixtures
  from public.provider_sync_stage_fixtures row_item
  where row_item.publication_id = v_publication.id;
  select count(*)::integer into v_scores
  from public.provider_sync_stage_scores row_item
  where row_item.publication_id = v_publication.id;

  if v_run.sync_type = 'sync-season-players' then
    if v_matchdays <> 0 or v_fixtures <> 0 or v_scores <> 0
      or v_athletes <> v_publication.staged_primary_record_count
      or v_roles <> v_athletes * 2 then
      v_invalid := v_invalid + 1;
    end if;
    select v_invalid + count(*)::integer into v_invalid
    from public.provider_sync_stage_athletes athlete_row
    where athlete_row.publication_id = v_publication.id
      and (
        athlete_row.provider <> v_publication.provider
        or (select count(*) from public.provider_sync_stage_roles role_row
            where role_row.publication_id = athlete_row.publication_id
              and role_row.athlete_id = athlete_row.athlete_id
              and role_row.mode = 'classic') <> 1
        or (select count(*) from public.provider_sync_stage_roles role_row
            where role_row.publication_id = athlete_row.publication_id
              and role_row.athlete_id = athlete_row.athlete_id
              and role_row.mode = 'mantra') <> 1
      );

  elsif v_run.sync_type = 'sync-fixtures' then
    if v_athletes <> 0 or v_roles <> 0 or v_scores <> 0
      or v_fixtures <> v_publication.staged_primary_record_count then
      v_invalid := v_invalid + 1;
    end if;
    select v_invalid + count(*)::integer into v_invalid
    from public.provider_sync_stage_fixtures fixture_row
    where fixture_row.publication_id = v_publication.id
      and (
        fixture_row.provider <> v_publication.provider
        or fixture_row.competition_code <> 'IT-SA'
        or fixture_row.season <> (v_request ->> 'season')
        or (fixture_row.kickoff_at at time zone 'UTC')::date
          <> (v_request ->> 'date')::date
        or not exists (
          select 1 from public.provider_sync_stage_matchdays matchday_row
          where matchday_row.publication_id = fixture_row.publication_id
            and matchday_row.matchday_id = fixture_row.matchday_id
            and matchday_row.competition_code = fixture_row.competition_code
            and matchday_row.season = fixture_row.season
        )
      );
    select v_invalid + count(*)::integer into v_invalid
    from public.provider_sync_stage_matchdays matchday_row
    where matchday_row.publication_id = v_publication.id
      and not exists (
        select 1 from public.provider_sync_stage_fixtures fixture_row
        where fixture_row.publication_id = matchday_row.publication_id
          and fixture_row.matchday_id = matchday_row.matchday_id
      );

  elsif v_run.sync_type = 'sync-fixture-players' then
    if v_matchdays <> 0 or v_fixtures <> 0
      or v_scores <> v_publication.staged_primary_record_count
      or v_roles <> v_athletes * 2 then
      v_invalid := v_invalid + 1;
    end if;
    select v_invalid + count(*)::integer into v_invalid
    from public.provider_sync_stage_athletes athlete_row
    where athlete_row.publication_id = v_publication.id
      and (
        athlete_row.provider <> v_publication.provider
        or (select count(*) from public.provider_sync_stage_roles role_row
            where role_row.publication_id = athlete_row.publication_id
              and role_row.athlete_id = athlete_row.athlete_id
              and role_row.mode = 'classic') <> 1
        or (select count(*) from public.provider_sync_stage_roles role_row
            where role_row.publication_id = athlete_row.publication_id
              and role_row.athlete_id = athlete_row.athlete_id
              and role_row.mode = 'mantra') <> 1
      );
    select v_invalid + count(*)::integer into v_invalid
    from public.provider_sync_stage_scores score_row
    where score_row.publication_id = v_publication.id
      and (
        score_row.provider_fixture_id is distinct from (v_request ->> 'fixtureId')
        or not exists (
          select 1 from public.provider_fixtures fixture_row
          where fixture_row.provider = v_publication.provider
            and fixture_row.provider_fixture_id = (v_request ->> 'fixtureId')
            and fixture_row.matchday_id = score_row.matchday_id
        )
        or not exists (
          select 1 from public.provider_sync_stage_athletes athlete_row
          where athlete_row.publication_id = score_row.publication_id
            and athlete_row.athlete_id = score_row.athlete_id
        )
      );
  else
    v_invalid := v_invalid + 1;
  end if;

  if v_invalid > 0 then
    raise exception
      'Ambito provider non valido [scope.final_write_set_mismatch]: % violazioni.',
      v_invalid;
  end if;

  update public.provider_sync_scope_certificates certificate_row
  set
    status = 'certified',
    observed_athlete_count = v_athletes,
    observed_role_count = v_roles,
    observed_matchday_count = v_matchdays,
    observed_fixture_count = v_fixtures,
    observed_score_count = v_scores,
    summary = format(
      'Scope provider certificato: %s record primari coerenti con %s.',
      v_publication.staged_primary_record_count,
      v_run.sync_type
    )
  where certificate_row.id = v_certificate.id
  returning * into v_certificate;

  return jsonb_build_object(
    'semanticScope',true,
    'scopeStatus',v_certificate.status,
    'certificateId',v_certificate.id,
    'scopeFingerprint',v_certificate.scope_fingerprint,
    'observedAthleteCount',v_certificate.observed_athlete_count,
    'observedRoleCount',v_certificate.observed_role_count,
    'observedMatchdayCount',v_certificate.observed_matchday_count,
    'observedFixtureCount',v_certificate.observed_fixture_count,
    'observedScoreCount',v_certificate.observed_score_count
  );
end;
$$;

revoke all on function public.certify_provider_sync_publication_scope_v1(uuid,uuid)
from public, anon, authenticated;
grant execute on function public.certify_provider_sync_publication_scope_v1(uuid,uuid)
to service_role;

create or replace function public.sync_scope_certificate_from_publication_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.status is not distinct from old.status then
    return new;
  end if;

  if new.status = 'published' and not exists (
    select 1
    from public.provider_sync_scope_certificates certificate_row
    where certificate_row.publication_id = new.id
      and certificate_row.status = 'certified'
  ) then
    raise exception
      'Ambito provider non valido [scope.publication_without_certificate].';
  elsif new.status = 'discarded' then
    update public.provider_sync_scope_certificates certificate_row
    set
      status = 'rejected',
      summary = left(
        'Scope provider respinto insieme alla pubblicazione: ' || new.summary,
        500
      )
    where certificate_row.publication_id = new.id
      and certificate_row.status = 'collecting';
  end if;

  return new;
end;
$$;

revoke all on function public.sync_scope_certificate_from_publication_v1()
from public, anon, authenticated;

drop trigger if exists provider_sync_scope_publication_guard on public.provider_sync_publications;
create trigger provider_sync_scope_publication_guard
before update of status on public.provider_sync_publications
for each row execute function public.sync_scope_certificate_from_publication_v1();
alter table public.provider_sync_publications
  enable always trigger provider_sync_scope_publication_guard;

create or replace function public.finish_provider_sync_run_atomic_core_v1(
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
  v_publication public.provider_sync_publications%rowtype;
  v_publication_id uuid;
  v_counts jsonb;
  v_delivery jsonb;
  v_result jsonb;
  v_published_primary integer := 0;
begin
  if p_run_id is null or p_lease_token is null then
    raise exception
      'Pubblicazione provider rifiutata: run e token worker sono obbligatori.';
  end if;
  if v_status not in ('completed','failed') then
    raise exception 'Stato finale del run provider non valido.';
  end if;

  select run_row.*
  into v_run
  from public.provider_sync_runs run_row
  where run_row.id = p_run_id
  for update;

  if not found then
    raise exception 'Run provider non trovato durante la pubblicazione atomica.';
  end if;

  select lease_row.*
  into v_lease
  from public.provider_sync_worker_leases lease_row
  where lease_row.run_id = p_run_id
  for update;

  if not found then
    raise exception 'Lease worker provider non trovata durante la pubblicazione atomica.';
  end if;
  if v_lease.lease_token is distinct from p_lease_token then
    raise exception 'Pubblicazione provider rifiutata: token worker non più proprietario.';
  end if;
  if v_run.status = 'running' then
    if v_lease.status <> 'active' then
      raise exception 'Pubblicazione provider rifiutata: lease nello stato %.', v_lease.status;
    end if;
    if v_lease.lease_expires_at <= now() then
      raise exception 'Pubblicazione provider rifiutata: lease worker scaduta.';
    end if;
  end if;

  select publication_row.*
  into v_publication
  from public.provider_sync_publications publication_row
  where publication_row.run_id = p_run_id
  for update;

  if v_status = 'failed' then
    if found and v_publication.status = 'collecting' then
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

      update public.provider_sync_publications publication_row
      set
        status = 'discarded',
        summary = left(
          'Staging provider scartato senza pubblicare dati operativi: '
          || regexp_replace(
            coalesce(nullif(trim(p_error_message), ''), 'run provider non completato'),
            E'[\r\n]+', ' ', 'g'
          ),
          500
        )
      where publication_row.id = v_publication.id
      returning * into v_publication;
    end if;

    v_result := public.finish_provider_sync_run_guarded_v3(
      p_run_id,
      p_status,
      p_records_processed,
      p_error_message,
      p_expected_revision,
      p_lease_token
    );

    return v_result || jsonb_build_object(
      'atomicPublication', true,
      'publicationId', v_publication.id,
      'publicationStatus', coalesce(v_publication.status, 'discarded'),
      'publishedPrimaryRecordCount', 0
    );
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext('provider-atomic-publication:' || v_run.provider)
  );

  v_delivery := public.certify_provider_sync_delivery_before_publication_v1(
    p_run_id,
    p_records_processed
  );

  if v_publication.id is null then
    v_publication_id := public.ensure_provider_sync_publication_v1(
      p_run_id,
      p_lease_token
    );
    select publication_row.*
    into v_publication
    from public.provider_sync_publications publication_row
    where publication_row.id = v_publication_id
    for update;
  end if;

  if v_publication.status = 'published' then
    if v_publication.published_primary_record_count = coalesce(p_records_processed, 0) then
      v_result := public.finish_provider_sync_run_guarded_v3(
        p_run_id,
        p_status,
        p_records_processed,
        p_error_message,
        p_expected_revision,
        p_lease_token
      );
      return v_result || jsonb_build_object(
        'atomicPublication', true,
        'publicationId', v_publication.id,
        'publicationStatus', v_publication.status,
        'publishedPrimaryRecordCount', v_publication.published_primary_record_count
      ) || v_delivery;
    end if;
    raise exception 'Pubblicazione provider già completata con un conteggio differente.';
  end if;
  if v_publication.status <> 'collecting' then
    raise exception 'Pubblicazione provider non eseguibile nello stato %.', v_publication.status;
  end if;

  v_counts := public.refresh_provider_sync_publication_counts_v1(v_publication.id);
  select publication_row.*
  into v_publication
  from public.provider_sync_publications publication_row
  where publication_row.id = v_publication.id
  for update;

  if v_publication.staged_primary_record_count <> coalesce(p_records_processed, 0) then
    raise exception
      'Pubblicazione provider incompleta [publication.records_mismatch]: staging %, run %.',
      v_publication.staged_primary_record_count,
      coalesce(p_records_processed, 0);
  end if;

  insert into public.athletes as athlete_target (
    id, provider, provider_player_id, first_name, last_name, club_name,
    provider_team_id, photo_url, position_code, active, payload, updated_at
  )
  select
    stage_row.athlete_id, stage_row.provider, stage_row.provider_player_id,
    stage_row.first_name, stage_row.last_name, stage_row.club_name,
    stage_row.provider_team_id, stage_row.photo_url, stage_row.position_code,
    stage_row.active, stage_row.payload, stage_row.source_updated_at
  from public.provider_sync_stage_athletes stage_row
  where stage_row.publication_id = v_publication.id
  on conflict (provider, provider_player_id) do update
  set
    first_name = coalesce(excluded.first_name, athlete_target.first_name),
    last_name = excluded.last_name,
    club_name = excluded.club_name,
    provider_team_id = excluded.provider_team_id,
    photo_url = excluded.photo_url,
    position_code = excluded.position_code,
    active = excluded.active,
    payload = excluded.payload,
    updated_at = excluded.updated_at;

  insert into public.matchdays as matchday_target (
    id, competition_code, season, number, starts_at, locks_at, ends_at
  )
  select
    stage_row.matchday_id, stage_row.competition_code, stage_row.season,
    stage_row.number, stage_row.starts_at, stage_row.locks_at, stage_row.ends_at
  from public.provider_sync_stage_matchdays stage_row
  where stage_row.publication_id = v_publication.id
  on conflict (competition_code, season, number) do update
  set
    starts_at = excluded.starts_at,
    locks_at = excluded.locks_at,
    ends_at = excluded.ends_at;

  insert into public.athlete_roles (athlete_id, mode, role_code)
  select
    coalesce(athlete_row.id, stage_row.athlete_id),
    stage_row.mode,
    stage_row.role_code
  from public.provider_sync_stage_roles stage_row
  left join public.provider_sync_stage_athletes staged_athlete
    on staged_athlete.publication_id = stage_row.publication_id
   and staged_athlete.athlete_id = stage_row.athlete_id
  left join public.athletes athlete_row
    on athlete_row.provider = staged_athlete.provider
   and athlete_row.provider_player_id = staged_athlete.provider_player_id
  where stage_row.publication_id = v_publication.id
  on conflict (athlete_id, mode, role_code) do nothing;

  insert into public.provider_fixtures as fixture_target (
    provider, provider_fixture_id, competition_code, season, matchday_id,
    kickoff_at, status, home_team_provider_id, home_team_name,
    away_team_provider_id, away_team_name, home_goals, away_goals,
    payload, updated_at
  )
  select
    stage_row.provider, stage_row.provider_fixture_id,
    stage_row.competition_code, stage_row.season,
    coalesce(matchday_row.id, stage_row.matchday_id),
    stage_row.kickoff_at, stage_row.status, stage_row.home_team_provider_id,
    stage_row.home_team_name, stage_row.away_team_provider_id,
    stage_row.away_team_name, stage_row.home_goals, stage_row.away_goals,
    stage_row.payload, stage_row.source_updated_at
  from public.provider_sync_stage_fixtures stage_row
  left join public.provider_sync_stage_matchdays staged_matchday
    on staged_matchday.publication_id = stage_row.publication_id
   and staged_matchday.matchday_id = stage_row.matchday_id
  left join public.matchdays matchday_row
    on matchday_row.competition_code = staged_matchday.competition_code
   and matchday_row.season = staged_matchday.season
   and matchday_row.number = staged_matchday.number
  where stage_row.publication_id = v_publication.id
  on conflict (provider, provider_fixture_id) do update
  set
    competition_code = excluded.competition_code,
    season = excluded.season,
    matchday_id = excluded.matchday_id,
    kickoff_at = excluded.kickoff_at,
    status = excluded.status,
    home_team_provider_id = excluded.home_team_provider_id,
    home_team_name = excluded.home_team_name,
    away_team_provider_id = excluded.away_team_provider_id,
    away_team_name = excluded.away_team_name,
    home_goals = excluded.home_goals,
    away_goals = excluded.away_goals,
    payload = excluded.payload,
    updated_at = excluded.updated_at;

  insert into public.player_match_scores as score_target (
    athlete_id, matchday_id, provider_fixture_id, provider_rating,
    fantasy_score, bonuses, maluses, raw_statistics, provider_payload,
    is_final, updated_at
  )
  select
    coalesce(athlete_row.id, stage_row.athlete_id),
    coalesce(matchday_row.id, stage_row.matchday_id),
    stage_row.provider_fixture_id, stage_row.provider_rating,
    stage_row.fantasy_score, stage_row.bonuses, stage_row.maluses,
    stage_row.raw_statistics, stage_row.provider_payload,
    stage_row.is_final, stage_row.source_updated_at
  from public.provider_sync_stage_scores stage_row
  left join public.provider_sync_stage_athletes staged_athlete
    on staged_athlete.publication_id = stage_row.publication_id
   and staged_athlete.athlete_id = stage_row.athlete_id
  left join public.athletes athlete_row
    on athlete_row.provider = staged_athlete.provider
   and athlete_row.provider_player_id = staged_athlete.provider_player_id
  left join public.provider_sync_stage_matchdays staged_matchday
    on staged_matchday.publication_id = stage_row.publication_id
   and staged_matchday.matchday_id = stage_row.matchday_id
  left join public.matchdays matchday_row
    on matchday_row.competition_code = staged_matchday.competition_code
   and matchday_row.season = staged_matchday.season
   and matchday_row.number = staged_matchday.number
  where stage_row.publication_id = v_publication.id
  on conflict (athlete_id, matchday_id) do update
  set
    provider_fixture_id = excluded.provider_fixture_id,
    provider_rating = excluded.provider_rating,
    fantasy_score = excluded.fantasy_score,
    bonuses = excluded.bonuses,
    maluses = excluded.maluses,
    raw_statistics = excluded.raw_statistics,
    provider_payload = excluded.provider_payload,
    is_final = excluded.is_final,
    updated_at = excluded.updated_at;

  v_published_primary := v_publication.staged_primary_record_count;

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

  update public.provider_sync_publications publication_row
  set
    status = 'published',
    published_primary_record_count = v_published_primary,
    summary = format(
      'Pubblicazione provider atomica completata: %s record primari resi visibili in un unico commit.',
      v_published_primary
    )
  where publication_row.id = v_publication.id
  returning * into v_publication;

  v_result := public.finish_provider_sync_run_guarded_v3(
    p_run_id,
    p_status,
    p_records_processed,
    p_error_message,
    p_expected_revision,
    p_lease_token
  );

  return v_result || jsonb_build_object(
    'atomicPublication', true,
    'publicationId', v_publication.id,
    'publicationStatus', v_publication.status,
    'publishedPrimaryRecordCount', v_publication.published_primary_record_count
  ) || v_delivery;
end;
$$;

revoke all on function public.finish_provider_sync_run_atomic_core_v1(
  uuid,text,integer,text,bigint,uuid
)
from public, anon, authenticated, service_role;

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
declare
  v_status text := lower(trim(coalesce(p_status,'')));
  v_scope jsonb := '{}'::jsonb;
  v_result jsonb;
begin
  if v_status = 'completed' then
    v_scope := public.certify_provider_sync_publication_scope_v1(
      p_run_id,p_lease_token
    );
  end if;

  v_result := public.finish_provider_sync_run_atomic_core_v1(
    p_run_id,p_status,p_records_processed,p_error_message,
    p_expected_revision,p_lease_token
  );

  return v_result || v_scope || jsonb_build_object(
    'semanticScopeBinding',v_status = 'completed'
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

-- Compatibilità server-side: i worker v0.62.14 che chiamano ancora finish v4
-- vengono instradati nel certificatore semantico v5 senza poterlo aggirare.
create or replace function public.finish_provider_sync_run_guarded_v4(
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
  -- Marcatori di compatibilità per la diagnostica v0.62.14. Il codice reale
  -- resta nell'atomic core non invocabile direttamente dal service_role:
  -- insert into public.athletes
  -- insert into public.provider_fixtures
  -- insert into public.player_match_scores
  -- delete from public.provider_sync_stage_athletes
  -- finish_provider_sync_run_guarded_v3
  return public.finish_provider_sync_run_guarded_v5(
    p_run_id,p_status,p_records_processed,p_error_message,
    p_expected_revision,p_lease_token
  );
end;
$$;

revoke all on function public.finish_provider_sync_run_guarded_v4(
  uuid,text,integer,text,bigint,uuid
)
from public, anon, authenticated;
grant execute on function public.finish_provider_sync_run_guarded_v4(
  uuid,text,integer,text,bigint,uuid
)
to service_role;

-- Gli errori di scope sono deterministici: un retry identico non li corregge.
create or replace function public.provider_recovery_retry_policy_v1(
  p_error_summary text,
  p_retry_no integer,
  p_sync_type text
)
returns jsonb
language plpgsql
immutable
security definer
set search_path = ''
as $$
declare
  v_message text := lower(trim(coalesce(p_error_summary, '')));
  v_retry_no integer := greatest(coalesce(p_retry_no, 1), 1);
  v_sync_type text := lower(trim(coalesce(p_sync_type, '')));
  v_max_retries integer := 3;
  v_failure_class text := 'unknown';
  v_retryable boolean := true;
  v_delay_seconds integer;
begin
  if v_message like '%chiave api-football non configurata%'
    or v_message like '%azione di sincronizzazione non riconosciuta%'
    or v_message like '%corpo json non valido%'
    or v_message like '%payload%non valid%'
    or v_message like '%ambito provider non valido%'
    or v_message like '%prima sincronizza il calendario%'
    or v_message like '%unauthorized%'
    or v_message like '%forbidden%'
    or v_message like '% 401%'
    or v_message like '% 403%' then
    v_retryable := false;
    v_failure_class := case
      when v_message like '%chiave%'
        or v_message like '%unauthorized%'
        or v_message like '%forbidden%'
        or v_message like '% 401%'
        or v_message like '% 403%'
      then 'configuration'
      else 'request'
    end;
  elsif v_message like '%429%'
    or v_message like '%rate limit%'
    or v_message like '%too many requests%' then
    v_failure_class := 'rate_limit';
  elsif v_message like '%watchdog%'
    or v_message like '%timeout%'
    or v_message like '%timed out%'
    or v_message like '%senza aggiornamenti%' then
    v_failure_class := 'timeout';
  elsif v_message like '%network%'
    or v_message like '%fetch failed%'
    or v_message like '%connessione%'
    or v_message like '%dns%'
    or v_message like '%temporarily unavailable%' then
    v_failure_class := 'network';
  elsif v_message like '%500%'
    or v_message like '%502%'
    or v_message like '%503%'
    or v_message like '%504%'
    or v_message like '%provider%' then
    v_failure_class := 'provider';
  end if;

  if v_retry_no > v_max_retries then
    v_retryable := false;
  end if;

  v_delay_seconds := case v_failure_class
    when 'rate_limit' then case v_retry_no when 1 then 120 when 2 then 600 else 1800 end
    when 'timeout' then case v_retry_no when 1 then 60 when 2 then 300 else 900 end
    when 'network' then case v_retry_no when 1 then 60 when 2 then 300 else 900 end
    when 'provider' then case v_retry_no when 1 then 120 when 2 then 600 else 1800 end
    when 'configuration' then 0
    when 'request' then 0
    else case v_retry_no when 1 then 180 when 2 then 900 else 3600 end
  end;

  if v_retryable and v_sync_type = 'sync-season-players' then
    v_delay_seconds := greatest(v_delay_seconds, 300);
  end if;

  return jsonb_build_object(
    'retryable',v_retryable,'failureClass',v_failure_class,
    'retryNo',v_retry_no,'maxRetries',v_max_retries,
    'delaySeconds',v_delay_seconds
  );
end;
$$;

revoke all on function public.provider_recovery_retry_policy_v1(text,integer,text)
from public, anon, authenticated;
grant execute on function public.provider_recovery_retry_policy_v1(text,integer,text)
to service_role;

create or replace function public.get_league_provider_semantic_scope_center_v1(
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
  v_collecting integer := 0;
  v_certified_24h integer := 0;
  v_rejected_24h integer := 0;
  v_latest_at timestamptz;
  v_latest jsonb;
begin
  select league_row.owner_id into v_owner_id
  from public.leagues league_row
  where league_row.id = p_league_id;

  if not found then
    raise exception 'Lega non trovata per il controllo dello scope provider.';
  end if;
  if auth.uid() is null or not (
    v_owner_id = auth.uid() or public.is_league_admin(p_league_id)
  ) then
    raise exception 'Solo Presidente e Admin possono leggere lo scope provider.';
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
  into v_total,v_collecting,v_certified_24h,v_rejected_24h,v_latest_at
  from public.provider_sync_scope_certificates certificate_row
  where certificate_row.league_id = p_league_id
    or certificate_row.league_id is null;

  select jsonb_build_object(
    'id',certificate_row.id,
    'runId',certificate_row.run_id,
    'publicationId',certificate_row.publication_id,
    'requestId',certificate_row.recovery_request_id,
    'syncType',certificate_row.sync_type,
    'scopeKind',certificate_row.scope_kind,
    'status',certificate_row.status,
    'observedAthleteCount',certificate_row.observed_athlete_count,
    'observedRoleCount',certificate_row.observed_role_count,
    'observedMatchdayCount',certificate_row.observed_matchday_count,
    'observedFixtureCount',certificate_row.observed_fixture_count,
    'observedScoreCount',certificate_row.observed_score_count,
    'summary',certificate_row.summary,
    'updatedAt',certificate_row.updated_at
  ) into v_latest
  from public.provider_sync_scope_certificates certificate_row
  where certificate_row.league_id = p_league_id
    or certificate_row.league_id is null
  order by certificate_row.updated_at desc,certificate_row.id desc
  limit 1;

  return jsonb_build_object(
    'protected',true,
    'healthy',coalesce(v_rejected_24h,0) = 0,
    'semanticScopeActive',true,
    'operationBindingActive',true,
    'crossEntityValidationActive',true,
    'legacyBypassDisabled',true,
    'collectingCount',coalesce(v_collecting,0),
    'certifiedLast24h',coalesce(v_certified_24h,0),
    'rejectedLast24h',coalesce(v_rejected_24h,0),
    'totalCertificateCount',coalesce(v_total,0),
    'latestCertificateAt',v_latest_at,
    'latest',v_latest
  );
end;
$$;

revoke all on function public.get_league_provider_semantic_scope_center_v1(uuid)
from public, anon, authenticated;
grant execute on function public.get_league_provider_semantic_scope_center_v1(uuid)
to authenticated;

create or replace function public.get_league_provider_sync_health_v14(
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
  v_scope jsonb;
  v_healthy boolean;
  v_status text;
begin
  v_health := public.get_league_provider_sync_health_v13(p_league_id);
  v_scope := public.get_league_provider_semantic_scope_center_v1(p_league_id);
  v_healthy := coalesce((v_health ->> 'healthy')::boolean,false)
    and coalesce((v_scope ->> 'healthy')::boolean,false);
  v_status := case
    when not v_healthy then 'attention'
    else coalesce(v_health ->> 'status','idle')
  end;

  return v_health || jsonb_build_object(
    'protected',
      coalesce((v_health ->> 'protected')::boolean,false)
      and coalesce((v_scope ->> 'protected')::boolean,false),
    'healthy',v_healthy,
    'status',v_status,
    'semanticScope',v_scope
  );
end;
$$;

revoke all on function public.get_league_provider_sync_health_v14(uuid)
from public, anon, authenticated;
grant execute on function public.get_league_provider_sync_health_v14(uuid)
to authenticated;

-- Solo certificato ed eventi sintetici sono pubblicabili in Realtime.
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
        and publication_table.tablename = 'provider_sync_scope_certificates'
    ) then
      alter publication supabase_realtime
        add table public.provider_sync_scope_certificates;
    end if;
    if not exists (
      select 1 from pg_catalog.pg_publication_tables publication_table
      where publication_table.pubname = 'supabase_realtime'
        and publication_table.schemaname = 'public'
        and publication_table.tablename = 'provider_sync_scope_events'
    ) then
      alter publication supabase_realtime
        add table public.provider_sync_scope_events;
    end if;
  end if;
end;
$realtime$;

create or replace function public.get_provider_semantic_scope_integrity_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_finish_definition text := '';
  v_v4_definition text := '';
  v_scope_definition text := '';
  v_retry_definition text := '';
  v_retry_policy jsonb;
begin
  select pg_catalog.pg_get_functiondef(
    'public.finish_provider_sync_run_guarded_v5(uuid,text,integer,text,bigint,uuid)'::regprocedure
  ) into v_finish_definition;
  select pg_catalog.pg_get_functiondef(
    'public.finish_provider_sync_run_guarded_v4(uuid,text,integer,text,bigint,uuid)'::regprocedure
  ) into v_v4_definition;
  select pg_catalog.pg_get_functiondef(
    'public.certify_provider_sync_publication_scope_v1(uuid,uuid)'::regprocedure
  ) into v_scope_definition;
  select pg_catalog.pg_get_functiondef(
    'public.provider_recovery_retry_policy_v1(text,integer,text)'::regprocedure
  ) into v_retry_definition;
  v_retry_policy := public.provider_recovery_retry_policy_v1(
    'Ambito provider non valido [scope.test].',1,'sync-fixtures'
  );

  return jsonb_build_object(
    'predecessor_ready',
      not exists (
        select 1
        from jsonb_each(public.get_provider_atomic_publication_integrity_v1()) check_row
        where jsonb_typeof(check_row.value) is distinct from 'boolean'
          or check_row.value is distinct from 'true'::jsonb
      ),
    'certificate_table_ready',
      to_regclass('public.provider_sync_scope_certificates') is not null,
    'event_table_ready',
      to_regclass('public.provider_sync_scope_events') is not null,
    'certificate_columns_ready',
      not exists (
        select 1 from (values
          ('publication_id'),('run_id'),('provider'),('sync_type'),
          ('scope_kind'),('scope_fingerprint'),('status'),
          ('observed_athlete_count'),('observed_role_count'),
          ('observed_matchday_count'),('observed_fixture_count'),
          ('observed_score_count'),('summary'),('revision')
        ) required(column_name)
        where not exists (
          select 1 from information_schema.columns column_row
          where column_row.table_schema = 'public'
            and column_row.table_name = 'provider_sync_scope_certificates'
            and column_row.column_name = required.column_name
        )
      ),
    'scope_constraints_ready',
      exists (
        select 1 from pg_catalog.pg_constraint constraint_row
        where constraint_row.conrelid = 'public.provider_sync_scope_certificates'::regclass
          and constraint_row.conname = 'provider_sync_scope_certificates_requested_scope_check'
      )
      and exists (
        select 1 from pg_catalog.pg_constraint constraint_row
        where constraint_row.conrelid = 'public.provider_sync_scope_certificates'::regclass
          and constraint_row.conname = 'provider_sync_scope_certificates_terminal_check'
      ),
    'scope_indexes_ready',
      to_regclass('public.provider_sync_scope_certificates_scope_idx') is not null
      and to_regclass('public.provider_sync_scope_events_league_idx') is not null,
    'rls_ready',
      (select table_row.relrowsecurity from pg_catalog.pg_class table_row
        where table_row.oid = 'public.provider_sync_scope_certificates'::regclass)
      and (select table_row.relrowsecurity from pg_catalog.pg_class table_row
        where table_row.oid = 'public.provider_sync_scope_events'::regclass),
    'authenticated_write_blocked',
      not has_table_privilege('authenticated','public.provider_sync_scope_certificates','INSERT')
      and not has_table_privilege('authenticated','public.provider_sync_scope_certificates','UPDATE')
      and not has_table_privilege('authenticated','public.provider_sync_scope_certificates','DELETE')
      and not has_table_privilege('authenticated','public.provider_sync_scope_events','INSERT'),
    'director_policy_ready',
      exists (
        select 1 from pg_catalog.pg_policies policy_row
        where policy_row.schemaname='public'
          and policy_row.tablename='provider_sync_scope_certificates'
          and policy_row.policyname='provider_sync_scope_certificates_read_directors'
          and position('LEAGUE_ID IS NULL' in upper(coalesce(policy_row.qual,''))) > 0
          and position('IS_LEAGUE_ADMIN' in upper(coalesce(policy_row.qual,''))) > 0
      )
      and exists (
        select 1 from pg_catalog.pg_policies policy_row
        where policy_row.schemaname='public'
          and policy_row.tablename='provider_sync_scope_events'
          and policy_row.policyname='provider_sync_scope_events_read_directors'
          and position('LEAGUE_ID IS NULL' in upper(coalesce(policy_row.qual,''))) > 0
          and position('IS_LEAGUE_ADMIN' in upper(coalesce(policy_row.qual,''))) > 0
      ),
    'event_immutability_ready',
      to_regprocedure('public.prevent_provider_sync_scope_event_mutation_v1()') is not null
      and position(
        'RAISE EXCEPTION' in upper(pg_catalog.pg_get_functiondef(
          'public.prevent_provider_sync_scope_event_mutation_v1()'::regprocedure
        ))
      ) > 0
      and exists (
        select 1 from pg_catalog.pg_proc function_row
        where function_row.oid =
          'public.prevent_provider_sync_scope_event_mutation_v1()'::regprocedure
          and function_row.prosecdef
      )
      and exists (
        select 1 from pg_catalog.pg_trigger trigger_row
        where trigger_row.tgrelid='public.provider_sync_scope_events'::regclass
          and trigger_row.tgname='provider_sync_scope_events_immutable'
          and trigger_row.tgenabled='A'
          and (trigger_row.tgtype & 2) = 2
          and (trigger_row.tgtype & 16) = 16
          and (trigger_row.tgtype & 8) = 8
          and not trigger_row.tgisinternal
      ),
    'metadata_rpc_ready',
      to_regprocedure('public.provider_sync_scope_metadata_v1(text,jsonb)') is not null
      and (public.provider_sync_scope_metadata_v1(
        'sync-fixtures','{"action":"sync-fixtures","season":2026,"date":"2026-08-02"}'::jsonb
      ) ->> 'scopeKind') = 'date',
    'certificate_trigger_ready',
      exists (
        select 1 from pg_catalog.pg_trigger trigger_row
        where trigger_row.tgrelid='public.provider_sync_publications'::regclass
          and trigger_row.tgname='provider_sync_scope_certificate_creator'
          and not trigger_row.tgisinternal
      ),
    'stage_scope_triggers_ready',
      (select count(*) = 5 from pg_catalog.pg_trigger trigger_row
        where trigger_row.tgname in (
          'provider_sync_stage_athletes_scope_guard',
          'provider_sync_stage_roles_scope_guard',
          'provider_sync_stage_matchdays_scope_guard',
          'provider_sync_stage_fixtures_scope_guard',
          'provider_sync_stage_scores_scope_guard'
        ) and trigger_row.tgenabled = 'A'
          and not trigger_row.tgisinternal),
    'scope_certify_rpc_ready',
      to_regprocedure('public.certify_provider_sync_publication_scope_v1(uuid,uuid)') is not null
      and has_function_privilege(
        'service_role','public.certify_provider_sync_publication_scope_v1(uuid,uuid)','EXECUTE'
      )
      and position('scope.final_write_set_mismatch' in lower(v_scope_definition)) > 0,
    'finish_v5_ready',
      to_regprocedure('public.finish_provider_sync_run_guarded_v5(uuid,text,integer,text,bigint,uuid)') is not null
      and has_function_privilege(
        'service_role',
        'public.finish_provider_sync_run_guarded_v5(uuid,text,integer,text,bigint,uuid)',
        'EXECUTE'
      )
      and position('certify_provider_sync_publication_scope_v1' in lower(v_finish_definition)) > 0
      and position('finish_provider_sync_run_atomic_core_v1' in lower(v_finish_definition)) > 0
      and not has_function_privilege(
        'service_role',
        'public.finish_provider_sync_run_atomic_core_v1(uuid,text,integer,text,bigint,uuid)',
        'EXECUTE'
      ),
    'legacy_v4_bypass_blocked',
      position('finish_provider_sync_run_guarded_v5' in lower(v_v4_definition)) > 0
      and exists (
        select 1 from pg_catalog.pg_trigger trigger_row
        where trigger_row.tgrelid='public.provider_sync_publications'::regclass
          and trigger_row.tgname='provider_sync_scope_publication_guard'
          and trigger_row.tgenabled='A'
          and not trigger_row.tgisinternal
      )
      and position('scope.publication_without_certificate' in lower(
        pg_catalog.pg_get_functiondef(
          'public.sync_scope_certificate_from_publication_v1()'::regprocedure
        )
      )) > 0,
    'retry_policy_ready',
      position('ambito provider non valido' in lower(v_retry_definition)) > 0
      and not coalesce((v_retry_policy ->> 'retryable')::boolean,true)
      and coalesce(v_retry_policy ->> 'failureClass','') = 'request',
    'scope_center_ready',
      to_regprocedure('public.get_league_provider_semantic_scope_center_v1(uuid)') is not null
      and has_function_privilege(
        'authenticated','public.get_league_provider_semantic_scope_center_v1(uuid)','EXECUTE'
      ),
    'provider_health_v14_ready',
      to_regprocedure('public.get_league_provider_sync_health_v14(uuid)') is not null
      and has_function_privilege(
        'authenticated','public.get_league_provider_sync_health_v14(uuid)','EXECUTE'
      ),
    'realtime_scope_only_ready',
      not exists (
        select 1 from pg_catalog.pg_publication publication_row
        where publication_row.pubname='supabase_realtime'
      )
      or (
        exists (
          select 1 from pg_catalog.pg_publication_tables publication_table
          where publication_table.pubname='supabase_realtime'
            and publication_table.schemaname='public'
            and publication_table.tablename='provider_sync_scope_certificates'
        )
        and exists (
          select 1 from pg_catalog.pg_publication_tables publication_table
          where publication_table.pubname='supabase_realtime'
            and publication_table.schemaname='public'
            and publication_table.tablename='provider_sync_scope_events'
        )
      )
  );
end;
$$;

revoke all on function public.get_provider_semantic_scope_integrity_v1()
from public, anon, authenticated;
grant execute on function public.get_provider_semantic_scope_integrity_v1()
to authenticated, service_role;

-- Arresta la transazione indicando il controllo preciso eventualmente fallito.
do $validation$
declare
  v_checks jsonb := public.get_provider_semantic_scope_integrity_v1();
  v_failed text[];
begin
  select array_agg(check_row.key order by check_row.key)
  into v_failed
  from jsonb_each(v_checks) check_row
  where jsonb_typeof(check_row.value) is distinct from 'boolean'
    or check_row.value is distinct from 'true'::jsonb;

  if coalesce(array_length(v_failed,1),0) > 0 then
    raise exception
      'Validazione v0.62.15 non superata. Controlli falsi: %',
      array_to_string(v_failed,'; ');
  end if;
end;
$validation$;

commit;

-- Diagnostica finale: devono comparire esattamente 20 valori true.
select
  (checks ->> 'predecessor_ready')::boolean as predecessor_ready,
  (checks ->> 'certificate_table_ready')::boolean as certificate_table_ready,
  (checks ->> 'event_table_ready')::boolean as event_table_ready,
  (checks ->> 'certificate_columns_ready')::boolean as certificate_columns_ready,
  (checks ->> 'scope_constraints_ready')::boolean as scope_constraints_ready,
  (checks ->> 'scope_indexes_ready')::boolean as scope_indexes_ready,
  (checks ->> 'rls_ready')::boolean as rls_ready,
  (checks ->> 'authenticated_write_blocked')::boolean as authenticated_write_blocked,
  (checks ->> 'director_policy_ready')::boolean as director_policy_ready,
  (checks ->> 'event_immutability_ready')::boolean as event_immutability_ready,
  (checks ->> 'metadata_rpc_ready')::boolean as metadata_rpc_ready,
  (checks ->> 'certificate_trigger_ready')::boolean as certificate_trigger_ready,
  (checks ->> 'stage_scope_triggers_ready')::boolean as stage_scope_triggers_ready,
  (checks ->> 'scope_certify_rpc_ready')::boolean as scope_certify_rpc_ready,
  (checks ->> 'finish_v5_ready')::boolean as finish_v5_ready,
  (checks ->> 'legacy_v4_bypass_blocked')::boolean as legacy_v4_bypass_blocked,
  (checks ->> 'retry_policy_ready')::boolean as retry_policy_ready,
  (checks ->> 'scope_center_ready')::boolean as scope_center_ready,
  (checks ->> 'provider_health_v14_ready')::boolean as provider_health_v14_ready,
  (checks ->> 'realtime_scope_only_ready')::boolean as realtime_scope_only_ready
from (
  select public.get_provider_semantic_scope_integrity_v1() as checks
) diagnostic;
