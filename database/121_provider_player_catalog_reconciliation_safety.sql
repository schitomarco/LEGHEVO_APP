-- LEGHEVO v0.62.17
-- Riconciliazione autorevole e non distruttiva del catalogo calciatori provider.
-- Eseguire dopo database/120_provider_monotonic_publication_watermark_safety.sql.

begin;

-- PREFLIGHT: tutte le dipendenze e le firme RPC vengono verificate prima di
-- creare oggetti o modificare il percorso di chiusura del worker.
do $preflight$
declare
  v_missing text[] := array[]::text[];
  v_predecessor jsonb;
  v_has_running boolean := false;
begin
  if to_regprocedure('public.get_provider_monotonic_publication_integrity_v1()') is null then
    v_missing := array_append(v_missing, 'function public.get_provider_monotonic_publication_integrity_v1()');
  else
    v_predecessor := public.get_provider_monotonic_publication_integrity_v1();
    if exists (
      select 1 from jsonb_each(v_predecessor) check_row
      where jsonb_typeof(check_row.value) is distinct from 'boolean'
         or check_row.value is distinct from 'true'::jsonb
    ) then
      v_missing := array_append(v_missing, 'validated predecessor public.get_provider_monotonic_publication_integrity_v1()');
    end if;
  end if;


  if to_regprocedure('public.assert_provider_sync_worker_lease_v1(uuid,uuid)') is null then
    v_missing := array_append(v_missing, 'function public.assert_provider_sync_worker_lease_v1(uuid,uuid)');
  end if;
  if to_regprocedure('public.provider_sync_scope_watermark_decision_v1(uuid,uuid)') is null then
    v_missing := array_append(v_missing, 'function public.provider_sync_scope_watermark_decision_v1(uuid,uuid)');
  end if;
  if to_regprocedure('public.discard_stale_provider_sync_publication_v1(uuid,integer,bigint,uuid,jsonb)') is null then
    v_missing := array_append(v_missing, 'function public.discard_stale_provider_sync_publication_v1(uuid,integer,bigint,uuid,jsonb)');
  end if;
  if to_regprocedure('public.certify_provider_sync_publication_scope_v1(uuid,uuid)') is null then
    v_missing := array_append(v_missing, 'function public.certify_provider_sync_publication_scope_v1(uuid,uuid)');
  end if;
  if to_regprocedure('public.finish_provider_sync_run_atomic_core_v1(uuid,text,integer,text,bigint,uuid)') is null then
    v_missing := array_append(v_missing, 'function public.finish_provider_sync_run_atomic_core_v1(uuid,text,integer,text,bigint,uuid)');
  end if;
  if to_regprocedure('public.finish_provider_sync_run_guarded_v6(uuid,text,integer,text,bigint,uuid)') is null then
    v_missing := array_append(v_missing, 'function public.finish_provider_sync_run_guarded_v6(uuid,text,integer,text,bigint,uuid)');
  end if;
  if to_regprocedure('public.finish_provider_sync_run_guarded_v3(uuid,text,integer,text,bigint,uuid)') is null then
    v_missing := array_append(v_missing, 'function public.finish_provider_sync_run_guarded_v3(uuid,text,integer,text,bigint,uuid)');
  end if;
  if to_regprocedure('public.advance_provider_sync_scope_watermark_v1(uuid,integer,uuid)') is null then
    v_missing := array_append(v_missing, 'function public.advance_provider_sync_scope_watermark_v1(uuid,integer,uuid)');
  end if;
  if to_regprocedure('public.get_league_provider_sync_health_v15(uuid)') is null then
    v_missing := array_append(v_missing, 'function public.get_league_provider_sync_health_v15(uuid)');
  end if;
  if to_regprocedure('public.is_league_admin(uuid)') is null then
    v_missing := array_append(v_missing, 'function public.is_league_admin(uuid)');
  end if;
  if to_regprocedure('public.provider_recovery_retry_policy_v1(text,integer,text)') is null then
    v_missing := array_append(v_missing, 'function public.provider_recovery_retry_policy_v1(text,integer,text)');
  end if;
  if to_regprocedure('public.certify_provider_recovery_request_outcome_v1(uuid)') is null then
    v_missing := array_append(v_missing, 'function public.certify_provider_recovery_request_outcome_v1(uuid)');
  end if;
  if to_regprocedure('pg_catalog.hashtext(text)') is null then
    v_missing := array_append(v_missing, 'function pg_catalog.hashtext(text)');
  end if;
  if to_regprocedure('pg_catalog.pg_advisory_xact_lock(bigint)') is null then
    v_missing := array_append(v_missing, 'function pg_catalog.pg_advisory_xact_lock(bigint)');
  end if;
  if to_regprocedure('pg_catalog.md5(text)') is null then
    v_missing := array_append(v_missing, 'function pg_catalog.md5(text)');
  end if;
  if to_regprocedure('pg_catalog.current_setting(text,boolean)') is null then
    v_missing := array_append(v_missing, 'function pg_catalog.current_setting(text,boolean)');
  end if;
  if to_regprocedure('pg_catalog.set_config(text,text,boolean)') is null then
    v_missing := array_append(v_missing, 'function pg_catalog.set_config(text,text,boolean)');
  end if;

  if to_regprocedure('pg_catalog.gen_random_uuid()') is null
     and to_regprocedure('public.gen_random_uuid()') is null then
    v_missing := array_append(v_missing, 'function gen_random_uuid()');
  end if;
  if to_regprocedure('auth.uid()') is null then
    v_missing := array_append(v_missing, 'function auth.uid()');
  end if;
  if to_regtype('public.league_mode') is null then
    v_missing := array_append(v_missing, 'type public.league_mode');
  end if;

  if to_regclass('public.provider_sync_runs') is null then
    v_missing := array_append(v_missing, 'table public.provider_sync_runs');
  end if;
  if to_regclass('public.provider_sync_publications') is null then
    v_missing := array_append(v_missing, 'table public.provider_sync_publications');
  end if;
  if to_regclass('public.provider_sync_scope_certificates') is null then
    v_missing := array_append(v_missing, 'table public.provider_sync_scope_certificates');
  end if;
  if to_regclass('public.provider_sync_stage_athletes') is null then
    v_missing := array_append(v_missing, 'table public.provider_sync_stage_athletes');
  end if;
  if to_regclass('public.provider_sync_stage_roles') is null then
    v_missing := array_append(v_missing, 'table public.provider_sync_stage_roles');
  end if;
  if to_regclass('public.provider_sync_stage_matchdays') is null then
    v_missing := array_append(v_missing, 'table public.provider_sync_stage_matchdays');
  end if;
  if to_regclass('public.provider_sync_stage_fixtures') is null then
    v_missing := array_append(v_missing, 'table public.provider_sync_stage_fixtures');
  end if;
  if to_regclass('public.provider_sync_stage_scores') is null then
    v_missing := array_append(v_missing, 'table public.provider_sync_stage_scores');
  end if;
  if to_regclass('public.athletes') is null then
    v_missing := array_append(v_missing, 'table public.athletes');
  end if;
  if to_regclass('public.athlete_roles') is null then
    v_missing := array_append(v_missing, 'table public.athlete_roles');
  end if;
  if to_regclass('public.roster_entries') is null then
    v_missing := array_append(v_missing, 'table public.roster_entries');
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
      ('sync_type'),('status'),('published_primary_record_count'),('summary')
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
      ('publication_id'),('run_id'),('provider'),('sync_type'),('scope_kind'),
      ('requested_season'),('status'),('scope_fingerprint'),
      ('observed_athlete_count'),('observed_role_count')
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

  if to_regclass('public.leagues') is null then
    v_missing := array_append(v_missing, 'table public.leagues');
  elsif exists (
    select 1 from (values ('id'),('owner_id')) required(column_name)
    where not exists (
      select 1 from information_schema.columns column_row
      where column_row.table_schema = 'public'
        and column_row.table_name = 'leagues'
        and column_row.column_name = required.column_name
    )
  ) then
    v_missing := array_append(v_missing, 'required columns on public.leagues');
  end if;

  if to_regclass('public.athletes') is not null and exists (
    select 1 from (values
      ('id'),('provider'),('provider_player_id'),('active'),('updated_at')
    ) required(column_name)
    where not exists (
      select 1 from information_schema.columns column_row
      where column_row.table_schema = 'public'
        and column_row.table_name = 'athletes'
        and column_row.column_name = required.column_name
    )
  ) then
    v_missing := array_append(v_missing, 'required columns on public.athletes');
  end if;

  if to_regclass('public.athlete_roles') is not null and exists (
    select 1 from (values ('athlete_id'),('mode'),('role_code')) required(column_name)
    where not exists (
      select 1 from information_schema.columns column_row
      where column_row.table_schema = 'public'
        and column_row.table_name = 'athlete_roles'
        and column_row.column_name = required.column_name
    )
  ) then
    v_missing := array_append(v_missing, 'required columns on public.athlete_roles');
  end if;

  if to_regclass('public.roster_entries') is not null and exists (
    select 1 from (values ('league_id'),('athlete_id'),('released_at')) required(column_name)
    where not exists (
      select 1 from information_schema.columns column_row
      where column_row.table_schema = 'public'
        and column_row.table_name = 'roster_entries'
        and column_row.column_name = required.column_name
    )
  ) then
    v_missing := array_append(v_missing, 'required columns on public.roster_entries');
  end if;

  if to_regclass('public.provider_sync_stage_athletes') is not null and exists (
    select 1 from (values
      ('publication_id'),('athlete_id'),('provider'),('provider_player_id'),('active')
    ) required(column_name)
    where not exists (
      select 1 from information_schema.columns column_row
      where column_row.table_schema = 'public'
        and column_row.table_name = 'provider_sync_stage_athletes'
        and column_row.column_name = required.column_name
    )
  ) then
    v_missing := array_append(v_missing, 'required columns on public.provider_sync_stage_athletes');
  end if;

  if to_regclass('public.provider_sync_stage_roles') is not null and exists (
    select 1 from (values
      ('publication_id'),('athlete_id'),('mode'),('role_code')
    ) required(column_name)
    where not exists (
      select 1 from information_schema.columns column_row
      where column_row.table_schema = 'public'
        and column_row.table_name = 'provider_sync_stage_roles'
        and column_row.column_name = required.column_name
    )
  ) then
    v_missing := array_append(v_missing, 'required columns on public.provider_sync_stage_roles');
  end if;

  if to_regclass('public.provider_sync_stage_matchdays') is not null and exists (
    select 1 from (values ('publication_id')) required(column_name)
    where not exists (
      select 1 from information_schema.columns column_row
      where column_row.table_schema = 'public'
        and column_row.table_name = 'provider_sync_stage_matchdays'
        and column_row.column_name = required.column_name
    )
  ) then
    v_missing := array_append(v_missing, 'required columns on public.provider_sync_stage_matchdays');
  end if;

  if to_regclass('public.provider_sync_stage_fixtures') is not null and exists (
    select 1 from (values ('publication_id')) required(column_name)
    where not exists (
      select 1 from information_schema.columns column_row
      where column_row.table_schema = 'public'
        and column_row.table_name = 'provider_sync_stage_fixtures'
        and column_row.column_name = required.column_name
    )
  ) then
    v_missing := array_append(v_missing, 'required columns on public.provider_sync_stage_fixtures');
  end if;

  if to_regclass('public.provider_sync_stage_scores') is not null and exists (
    select 1 from (values ('publication_id')) required(column_name)
    where not exists (
      select 1 from information_schema.columns column_row
      where column_row.table_schema = 'public'
        and column_row.table_name = 'provider_sync_stage_scores'
        and column_row.column_name = required.column_name
    )
  ) then
    v_missing := array_append(v_missing, 'required columns on public.provider_sync_stage_scores');
  end if;

  if to_regclass('public.provider_recovery_requests') is not null and exists (
    select 1 from (values
      ('id'),('league_id'),('incident_id'),('provider'),('sync_type'),('status'),
      ('recovery_run_id'),('finished_at')
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
    select 1 from (values
      ('id'),('run_id'),('status'),('anomaly_count'),('created_at')
    ) required(column_name)
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

  if to_regclass('public.provider_sync_scope_watermark_events') is null then
    v_missing := array_append(v_missing, 'table public.provider_sync_scope_watermark_events');
  elsif exists (
    select 1 from (values
      ('candidate_run_id'),('candidate_publication_id'),('event_type'),('reason_code')
    ) required(column_name)
    where not exists (
      select 1 from information_schema.columns column_row
      where column_row.table_schema = 'public'
        and column_row.table_name = 'provider_sync_scope_watermark_events'
        and column_row.column_name = required.column_name
    )
  ) then
    v_missing := array_append(v_missing, 'required columns on public.provider_sync_scope_watermark_events');
  end if;

  if to_regclass('public.provider_sync_run_events') is null then
    v_missing := array_append(v_missing, 'table public.provider_sync_run_events');
  elsif exists (
    select 1 from (values ('run_id'),('event_type')) required(column_name)
    where not exists (
      select 1 from information_schema.columns column_row
      where column_row.table_schema = 'public'
        and column_row.table_name = 'provider_sync_run_events'
        and column_row.column_name = required.column_name
    )
  ) then
    v_missing := array_append(v_missing, 'required columns on public.provider_sync_run_events');
  end if;

  if to_regclass('public.athlete_roles_pkey') is null then
    v_missing := array_append(v_missing, 'constraint/index public.athlete_roles_pkey');
  end if;

  if coalesce(array_length(v_missing,1),0) > 0 then
    raise exception 'Preflight v0.62.17 non superato. Dipendenze mancanti: %',
      array_to_string(v_missing,'; ');
  end if;
end;
$preflight$;

create table if not exists public.provider_player_catalog_heads (
  id uuid primary key default gen_random_uuid(),
  provider text not null,
  competition_code text not null,
  latest_season integer not null,
  latest_run_id uuid not null references public.provider_sync_runs(id) on delete restrict,
  latest_publication_id uuid not null references public.provider_sync_publications(id) on delete restrict,
  latest_run_started_at timestamptz not null,
  active_player_count integer not null default 0,
  generation bigint not null default 1,
  revision bigint not null default 1,
  last_transition text not null default 'backfilled',
  summary text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (provider,competition_code),
  constraint provider_player_catalog_heads_provider_check check (
    length(trim(provider)) between 1 and 100 and provider !~ E'[\r\n]'
  ),
  constraint provider_player_catalog_heads_competition_check check (
    competition_code = 'IT-SA'
  ),
  constraint provider_player_catalog_heads_season_check check (
    latest_season between 2000 and 2200
  ),
  constraint provider_player_catalog_heads_count_check check (
    active_player_count between 0 and 1000000
  ),
  constraint provider_player_catalog_heads_generation_check check (
    generation > 0 and revision > 0
  ),
  constraint provider_player_catalog_heads_transition_check check (
    last_transition in ('backfilled','advanced','refreshed')
  ),
  constraint provider_player_catalog_heads_summary_check check (
    length(summary) between 1 and 500 and summary !~ E'[\r\n]'
  )
);

create table if not exists public.provider_player_catalog_reconciliations (
  id uuid primary key default gen_random_uuid(),
  head_id uuid references public.provider_player_catalog_heads(id) on delete restrict,
  publication_id uuid not null unique references public.provider_sync_publications(id) on delete restrict,
  run_id uuid not null unique references public.provider_sync_runs(id) on delete restrict,
  recovery_request_id uuid references public.provider_recovery_requests(id) on delete set null,
  league_id uuid references public.leagues(id) on delete set null,
  provider text not null,
  competition_code text not null,
  season integer not null,
  status text not null default 'collecting',
  previous_season integer,
  observed_player_count integer not null default 0,
  deactivated_player_count integer not null default 0,
  authoritative_role_count integer not null default 0,
  removed_role_count integer not null default 0,
  rostered_retired_count integer not null default 0,
  generation bigint,
  reason_code text not null default 'catalog.collecting',
  summary text not null default 'Catalogo calciatori provider in riconciliazione.',
  reconciliation_fingerprint text not null,
  revision bigint not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  applied_at timestamptz,
  superseded_at timestamptz,
  constraint provider_player_catalog_reconciliations_competition_check check (
    competition_code = 'IT-SA'
  ),
  constraint provider_player_catalog_reconciliations_season_check check (
    season between 2000 and 2200
    and (previous_season is null or previous_season between 2000 and 2200)
  ),
  constraint provider_player_catalog_reconciliations_status_check check (
    status in ('collecting','applied','superseded')
  ),
  constraint provider_player_catalog_reconciliations_count_check check (
    observed_player_count between 0 and 1000000
    and deactivated_player_count between 0 and 1000000
    and authoritative_role_count between 0 and 2000000
    and removed_role_count between 0 and 2000000
    and rostered_retired_count between 0 and 1000000
  ),
  constraint provider_player_catalog_reconciliations_reason_check check (
    reason_code in ('catalog.collecting','catalog.applied','catalog.older_season')
  ),
  constraint provider_player_catalog_reconciliations_fingerprint_check check (
    reconciliation_fingerprint ~ '^[0-9a-f]{32}$'
  ),
  constraint provider_player_catalog_reconciliations_revision_check check (
    revision > 0 and (generation is null or generation > 0)
  ),
  constraint provider_player_catalog_reconciliations_summary_check check (
    length(summary) between 1 and 500 and summary !~ E'[\r\n]'
  ),
  constraint provider_player_catalog_reconciliations_terminal_check check (
    (status = 'collecting' and applied_at is null and superseded_at is null)
    or (status = 'applied' and applied_at is not null and superseded_at is null)
    or (status = 'superseded' and applied_at is null and superseded_at is not null)
  )
);

create table if not exists public.provider_player_catalog_members (
  reconciliation_id uuid not null references public.provider_player_catalog_reconciliations(id) on delete restrict,
  player_key_fingerprint text not null,
  classic_role text not null,
  mantra_role text not null,
  member_fingerprint text not null,
  created_at timestamptz not null default now(),
  primary key (reconciliation_id,player_key_fingerprint),
  constraint provider_player_catalog_members_player_key_check check (
    player_key_fingerprint ~ '^[0-9a-f]{32}$'
  ),
  constraint provider_player_catalog_members_role_check check (
    length(trim(classic_role)) between 1 and 20
    and length(trim(mantra_role)) between 1 and 20
    and classic_role !~ E'[\r\n]'
    and mantra_role !~ E'[\r\n]'
  ),
  constraint provider_player_catalog_members_fingerprint_check check (
    member_fingerprint ~ '^[0-9a-f]{32}$'
  )
);

create table if not exists public.provider_player_catalog_events (
  id uuid primary key default gen_random_uuid(),
  reconciliation_id uuid not null references public.provider_player_catalog_reconciliations(id) on delete restrict,
  head_id uuid references public.provider_player_catalog_heads(id) on delete restrict,
  run_id uuid not null references public.provider_sync_runs(id) on delete restrict,
  publication_id uuid not null references public.provider_sync_publications(id) on delete restrict,
  league_id uuid references public.leagues(id) on delete set null,
  event_type text not null,
  season integer not null,
  previous_season integer,
  observed_player_count integer not null,
  deactivated_player_count integer not null,
  authoritative_role_count integer not null,
  removed_role_count integer not null,
  rostered_retired_count integer not null,
  generation bigint,
  reason_code text not null,
  event_fingerprint text not null,
  created_at timestamptz not null default now(),
  unique (reconciliation_id,event_type),
  constraint provider_player_catalog_events_type_check check (
    event_type in ('collecting','applied','superseded')
  ),
  constraint provider_player_catalog_events_season_check check (
    season between 2000 and 2200
    and (previous_season is null or previous_season between 2000 and 2200)
  ),
  constraint provider_player_catalog_events_count_check check (
    observed_player_count between 0 and 1000000
    and deactivated_player_count between 0 and 1000000
    and authoritative_role_count between 0 and 2000000
    and removed_role_count between 0 and 2000000
    and rostered_retired_count between 0 and 1000000
  ),
  constraint provider_player_catalog_events_reason_check check (
    reason_code in ('catalog.collecting','catalog.applied','catalog.older_season')
  ),
  constraint provider_player_catalog_events_generation_check check (
    generation is null or generation > 0
  ),
  constraint provider_player_catalog_events_fingerprint_check check (
    event_fingerprint ~ '^[0-9a-f]{32}$'
  )
);

create index if not exists provider_player_catalog_heads_latest_idx
  on public.provider_player_catalog_heads (provider,competition_code,latest_season desc);
create index if not exists provider_player_catalog_reconciliations_latest_idx
  on public.provider_player_catalog_reconciliations (created_at desc);
create index if not exists provider_player_catalog_reconciliations_league_idx
  on public.provider_player_catalog_reconciliations (league_id,created_at desc);
create index if not exists provider_player_catalog_members_key_idx
  on public.provider_player_catalog_members (player_key_fingerprint,reconciliation_id);
create index if not exists provider_player_catalog_events_latest_idx
  on public.provider_player_catalog_events (created_at desc);
create index if not exists provider_player_catalog_events_league_idx
  on public.provider_player_catalog_events (league_id,created_at desc);

alter table public.provider_player_catalog_heads enable row level security;
alter table public.provider_player_catalog_heads replica identity full;
alter table public.provider_player_catalog_reconciliations enable row level security;
alter table public.provider_player_catalog_reconciliations replica identity full;
alter table public.provider_player_catalog_members enable row level security;
alter table public.provider_player_catalog_events enable row level security;
alter table public.provider_player_catalog_events replica identity full;

revoke all on table public.provider_player_catalog_heads from public,anon,authenticated,service_role;
revoke all on table public.provider_player_catalog_reconciliations from public,anon,authenticated,service_role;
revoke all on table public.provider_player_catalog_members from public,anon,authenticated,service_role;
revoke all on table public.provider_player_catalog_events from public,anon,authenticated,service_role;
grant select on table public.provider_player_catalog_heads to authenticated,service_role;
grant select on table public.provider_player_catalog_reconciliations to authenticated,service_role;
grant select on table public.provider_player_catalog_events to authenticated,service_role;
grant select on table public.provider_player_catalog_members to service_role;

drop policy if exists provider_player_catalog_heads_read_directors on public.provider_player_catalog_heads;
create policy provider_player_catalog_heads_read_directors
on public.provider_player_catalog_heads
for select to authenticated
using (
  exists (
    select 1 from public.leagues league_row
    where league_row.owner_id = auth.uid()
       or public.is_league_admin(league_row.id)
  )
);

drop policy if exists provider_player_catalog_reconciliations_read_directors on public.provider_player_catalog_reconciliations;
create policy provider_player_catalog_reconciliations_read_directors
on public.provider_player_catalog_reconciliations
for select to authenticated
using (
  (league_id is not null and exists (
    select 1 from public.leagues league_row
    where league_row.id = provider_player_catalog_reconciliations.league_id
      and (league_row.owner_id = auth.uid() or public.is_league_admin(league_row.id))
  ))
  or (league_id is null and exists (
    select 1 from public.leagues league_row
    where league_row.owner_id = auth.uid() or public.is_league_admin(league_row.id)
  ))
);

drop policy if exists provider_player_catalog_events_read_directors on public.provider_player_catalog_events;
create policy provider_player_catalog_events_read_directors
on public.provider_player_catalog_events
for select to authenticated
using (
  (league_id is not null and exists (
    select 1 from public.leagues league_row
    where league_row.id = provider_player_catalog_events.league_id
      and (league_row.owner_id = auth.uid() or public.is_league_admin(league_row.id))
  ))
  or (league_id is null and exists (
    select 1 from public.leagues league_row
    where league_row.owner_id = auth.uid() or public.is_league_admin(league_row.id)
  ))
);

create or replace function public.touch_provider_player_catalog_head_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if tg_op = 'UPDATE' then
    if new.id is distinct from old.id
      or new.provider is distinct from old.provider
      or new.competition_code is distinct from old.competition_code
      or new.created_at is distinct from old.created_at then
      raise exception 'Identità del catalogo calciatori provider non modificabile.';
    end if;
    if new.latest_season < old.latest_season then
      raise exception 'Regressione della stagione catalogo provider non consentita.';
    end if;
    if new.generation <= old.generation then
      raise exception 'Generazione del catalogo provider non avanzata.';
    end if;
    new.revision := old.revision + 1;
    new.updated_at := now();
  end if;
  return new;
end;
$function$;

revoke all on function public.touch_provider_player_catalog_head_v1() from public,anon,authenticated,service_role;
drop trigger if exists provider_player_catalog_heads_touch on public.provider_player_catalog_heads;
create trigger provider_player_catalog_heads_touch
before update on public.provider_player_catalog_heads
for each row execute function public.touch_provider_player_catalog_head_v1();
alter table public.provider_player_catalog_heads enable always trigger provider_player_catalog_heads_touch;

create or replace function public.touch_provider_player_catalog_reconciliation_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if tg_op = 'UPDATE' then
    if row(new.publication_id,new.run_id,new.recovery_request_id,new.league_id,new.provider,new.competition_code,new.season,new.created_at)
       is distinct from
       row(old.publication_id,old.run_id,old.recovery_request_id,old.league_id,old.provider,old.competition_code,old.season,old.created_at) then
      raise exception 'Identità della riconciliazione catalogo provider non modificabile.';
    end if;
    if old.status <> 'collecting' or new.status not in ('applied','superseded') then
      raise exception 'Transizione della riconciliazione catalogo provider non valida: % -> %.',old.status,new.status;
    end if;
    new.revision := old.revision + 1;
    new.updated_at := now();
    if new.status = 'applied' then
      new.applied_at := coalesce(new.applied_at,now());
      new.superseded_at := null;
    else
      new.superseded_at := coalesce(new.superseded_at,now());
      new.applied_at := null;
    end if;
  end if;
  return new;
end;
$function$;

revoke all on function public.touch_provider_player_catalog_reconciliation_v1() from public,anon,authenticated,service_role;
drop trigger if exists provider_player_catalog_reconciliations_touch on public.provider_player_catalog_reconciliations;
create trigger provider_player_catalog_reconciliations_touch
before update on public.provider_player_catalog_reconciliations
for each row execute function public.touch_provider_player_catalog_reconciliation_v1();
alter table public.provider_player_catalog_reconciliations enable always trigger provider_player_catalog_reconciliations_touch;

create or replace function public.write_provider_player_catalog_event_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if tg_op = 'UPDATE' and new.status is not distinct from old.status then
    return new;
  end if;

  insert into public.provider_player_catalog_events (
    reconciliation_id,head_id,run_id,publication_id,league_id,event_type,
    season,previous_season,observed_player_count,deactivated_player_count,
    authoritative_role_count,removed_role_count,rostered_retired_count,
    generation,reason_code,event_fingerprint,created_at
  ) values (
    new.id,new.head_id,new.run_id,new.publication_id,new.league_id,new.status,
    new.season,new.previous_season,new.observed_player_count,new.deactivated_player_count,
    new.authoritative_role_count,new.removed_role_count,new.rostered_retired_count,
    new.generation,new.reason_code,
    pg_catalog.md5(
      new.id::text || E'\n' || new.status || E'\n' || new.run_id::text || E'\n'
      || new.publication_id::text || E'\n' || new.season::text || E'\n'
      || new.observed_player_count::text || E'\n' || new.deactivated_player_count::text
      || E'\n' || new.authoritative_role_count::text || E'\n'
      || new.removed_role_count::text || E'\n' || new.rostered_retired_count::text
      || E'\n' || new.reason_code || E'\n' || new.revision::text
    ),
    case when new.status = 'applied' then new.applied_at
         when new.status = 'superseded' then new.superseded_at
         else new.created_at end
  )
  on conflict (reconciliation_id,event_type) do nothing;
  return new;
end;
$function$;

revoke all on function public.write_provider_player_catalog_event_v1() from public,anon,authenticated,service_role;
drop trigger if exists provider_player_catalog_event_writer on public.provider_player_catalog_reconciliations;
create trigger provider_player_catalog_event_writer
 after insert or update on public.provider_player_catalog_reconciliations
for each row execute function public.write_provider_player_catalog_event_v1();
alter table public.provider_player_catalog_reconciliations enable always trigger provider_player_catalog_event_writer;

create or replace function public.prevent_provider_player_catalog_event_mutation_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  raise exception 'Storico della riconciliazione catalogo provider immutabile.';
end;
$function$;

revoke all on function public.prevent_provider_player_catalog_event_mutation_v1() from public,anon,authenticated,service_role;
drop trigger if exists provider_player_catalog_events_immutable on public.provider_player_catalog_events;
create trigger provider_player_catalog_events_immutable
before update or delete on public.provider_player_catalog_events
for each row execute function public.prevent_provider_player_catalog_event_mutation_v1();
alter table public.provider_player_catalog_events enable always trigger provider_player_catalog_events_immutable;

create or replace function public.prevent_provider_player_catalog_member_mutation_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  raise exception 'Fotografia dei membri del catalogo provider immutabile.';
end;
$function$;

revoke all on function public.prevent_provider_player_catalog_member_mutation_v1() from public,anon,authenticated,service_role;
drop trigger if exists provider_player_catalog_members_immutable on public.provider_player_catalog_members;
create trigger provider_player_catalog_members_immutable
before update or delete on public.provider_player_catalog_members
for each row execute function public.prevent_provider_player_catalog_member_mutation_v1();
alter table public.provider_player_catalog_members enable always trigger provider_player_catalog_members_immutable;

-- Restituisce la fotografia catalogo che deve governare le scritture correnti.
-- Durante il commit stagionale usa esclusivamente il contesto interno della
-- riconciliazione collecting; negli altri flussi usa l'ultimo head applicato.
create or replace function public.resolve_provider_player_catalog_reconciliation_v1(
  p_provider text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_context text := pg_catalog.current_setting(
    'leghevo.provider_catalog_reconciliation_id',true
  );
  v_context_id uuid;
  v_reconciliation_id uuid;
begin
  begin
    v_context_id := nullif(trim(coalesce(v_context,'')),'')::uuid;
  exception when invalid_text_representation then
    v_context_id := null;
  end;

  if v_context_id is not null then
    select reconciliation_row.id into v_reconciliation_id
    from public.provider_player_catalog_reconciliations reconciliation_row
    where reconciliation_row.id = v_context_id
      and reconciliation_row.provider = p_provider
      and reconciliation_row.status = 'collecting';
    if found then return v_reconciliation_id; end if;
  end if;

  select reconciliation_row.id into v_reconciliation_id
  from public.provider_player_catalog_heads head_row
  join public.provider_player_catalog_reconciliations reconciliation_row
    on reconciliation_row.publication_id = head_row.latest_publication_id
   and reconciliation_row.status = 'applied'
  where head_row.provider = p_provider
    and head_row.competition_code = 'IT-SA';

  return v_reconciliation_id;
end;
$function$;

revoke all on function public.resolve_provider_player_catalog_reconciliation_v1(text)
from public,anon,authenticated,service_role;

-- Qualunque upsert successivo, compresi quelli dei voti partita, conserva lo
-- stato attivo deciso dall'ultima fotografia stagionale autorevole.
create or replace function public.enforce_provider_player_catalog_active_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_reconciliation_id uuid;
  v_is_member boolean;
begin
  if new.provider is null or new.provider_player_id is null then return new; end if;

  v_reconciliation_id := public.resolve_provider_player_catalog_reconciliation_v1(
    new.provider
  );
  if v_reconciliation_id is null then return new; end if;

  select exists (
    select 1
    from public.provider_player_catalog_members member_row
    where member_row.reconciliation_id = v_reconciliation_id
      and member_row.player_key_fingerprint = pg_catalog.md5(
        new.provider || E'\n' || new.provider_player_id
      )
  ) into v_is_member;

  new.active := coalesce(v_is_member,false);
  return new;
end;
$function$;

revoke all on function public.enforce_provider_player_catalog_active_v1()
from public,anon,authenticated,service_role;
drop trigger if exists provider_player_catalog_active_guard on public.athletes;
create trigger provider_player_catalog_active_guard
before insert or update on public.athletes
for each row execute function public.enforce_provider_player_catalog_active_v1();
alter table public.athletes enable always trigger provider_player_catalog_active_guard;

-- I flussi non stagionali non possono reinserire ruoli differenti da quelli
-- della fotografia corrente né creare ruoli per un atleta già ritirato.
create or replace function public.enforce_provider_player_catalog_role_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_provider text;
  v_provider_player_id text;
  v_reconciliation_id uuid;
  v_expected_role text;
begin
  if new.mode not in ('classic','mantra') then return new; end if;

  select athlete_row.provider,athlete_row.provider_player_id
  into v_provider,v_provider_player_id
  from public.athletes athlete_row
  where athlete_row.id = new.athlete_id;
  if not found or v_provider is null or v_provider_player_id is null then return new; end if;

  v_reconciliation_id := public.resolve_provider_player_catalog_reconciliation_v1(
    v_provider
  );
  if v_reconciliation_id is null then return new; end if;

  select case new.mode
    when 'classic' then member_row.classic_role
    when 'mantra' then member_row.mantra_role
  end
  into v_expected_role
  from public.provider_player_catalog_members member_row
  where member_row.reconciliation_id = v_reconciliation_id
    and member_row.player_key_fingerprint = pg_catalog.md5(
      v_provider || E'\n' || v_provider_player_id
    );

  if not found or new.role_code is distinct from v_expected_role then
    -- La riga fuori catalogo viene ignorata senza far fallire voti o statistiche:
    -- il ruolo autorevole esistente resta invariato e il calciatore assente
    -- continua a essere conservato come inattivo.
    if tg_op = 'INSERT' then return null; end if;
    return old;
  end if;

  return new;
end;
$function$;

revoke all on function public.enforce_provider_player_catalog_role_v1()
from public,anon,authenticated,service_role;
drop trigger if exists provider_player_catalog_role_guard on public.athlete_roles;
create trigger provider_player_catalog_role_guard
before insert or update on public.athlete_roles
for each row execute function public.enforce_provider_player_catalog_role_v1();
alter table public.athlete_roles enable always trigger provider_player_catalog_role_guard;

-- Il catalogo globale degli atleti può rappresentare una sola stagione corrente.
-- Viene quindi creato un head dalla stagione più alta già pubblicata, senza
-- alterare atleti o ruoli esistenti durante l'installazione.
insert into public.provider_player_catalog_heads (
  provider,competition_code,latest_season,latest_run_id,latest_publication_id,
  latest_run_started_at,active_player_count,generation,last_transition,summary
)
select distinct on (publication_row.provider)
  publication_row.provider,
  'IT-SA',
  certificate_row.requested_season,
  run_row.id,
  publication_row.id,
  run_row.started_at,
  (select count(*)::integer from public.athletes athlete_row
    where athlete_row.provider = publication_row.provider and athlete_row.active),
  1,
  'backfilled',
  format('Head catalogo provider inizializzato dalla stagione %s già pubblicata.',certificate_row.requested_season)
from public.provider_sync_scope_certificates certificate_row
join public.provider_sync_publications publication_row
  on publication_row.id = certificate_row.publication_id
join public.provider_sync_runs run_row on run_row.id = certificate_row.run_id
where certificate_row.sync_type = 'sync-season-players'
  and certificate_row.scope_kind = 'season'
  and certificate_row.status = 'certified'
  and certificate_row.requested_season is not null
  and publication_row.status = 'published'
order by publication_row.provider,certificate_row.requested_season desc,run_row.started_at desc,run_row.id desc
on conflict (provider,competition_code) do nothing;

create or replace function public.provider_player_catalog_decision_v1(
  p_run_id uuid,
  p_lease_token uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_run public.provider_sync_runs%rowtype;
  v_publication public.provider_sync_publications%rowtype;
  v_certificate public.provider_sync_scope_certificates%rowtype;
  v_head public.provider_player_catalog_heads%rowtype;
  v_superseded boolean := false;
begin
  perform public.assert_provider_sync_worker_lease_v1(p_run_id,p_lease_token);

  select run_row.* into v_run
  from public.provider_sync_runs run_row
  where run_row.id = p_run_id
  for update;
  if not found or v_run.status <> 'running' then
    raise exception 'Decisione catalogo provider rifiutata [catalog.run_not_running].';
  end if;

  if v_run.sync_type <> 'sync-season-players' then
    return jsonb_build_object('applicable',false,'superseded',false);
  end if;

  select publication_row.* into v_publication
  from public.provider_sync_publications publication_row
  where publication_row.run_id = p_run_id
  for update;
  if not found or v_publication.status <> 'collecting' then
    raise exception 'Decisione catalogo provider rifiutata [catalog.publication_not_collecting].';
  end if;

  select certificate_row.* into v_certificate
  from public.provider_sync_scope_certificates certificate_row
  where certificate_row.publication_id = v_publication.id
  for update;
  if not found or v_certificate.status <> 'certified'
     or v_certificate.scope_kind <> 'season'
     or v_certificate.requested_season is null then
    raise exception 'Decisione catalogo provider rifiutata [catalog.scope_not_certified].';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext('provider-player-catalog:' || v_run.provider || ':IT-SA')::bigint
  );

  select head_row.* into v_head
  from public.provider_player_catalog_heads head_row
  where head_row.provider = v_run.provider
    and head_row.competition_code = 'IT-SA'
  for update;

  if found then
    v_superseded := v_certificate.requested_season < v_head.latest_season;
  end if;

  return jsonb_build_object(
    'applicable',true,
    'superseded',v_superseded,
    'candidateSeason',v_certificate.requested_season,
    'headId',v_head.id,
    'headSeason',v_head.latest_season,
    'headRunId',v_head.latest_run_id,
    'headPublicationId',v_head.latest_publication_id,
    'headGeneration',v_head.generation
  );
end;
$function$;

revoke all on function public.provider_player_catalog_decision_v1(uuid,uuid) from public,anon,authenticated,service_role;

create or replace function public.prepare_provider_player_catalog_reconciliation_v1(
  p_run_id uuid,
  p_lease_token uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_run public.provider_sync_runs%rowtype;
  v_publication public.provider_sync_publications%rowtype;
  v_certificate public.provider_sync_scope_certificates%rowtype;
  v_head public.provider_player_catalog_heads%rowtype;
  v_reconciliation public.provider_player_catalog_reconciliations%rowtype;
  v_member_count integer := 0;
  v_staged_count integer := 0;
begin
  perform public.assert_provider_sync_worker_lease_v1(p_run_id,p_lease_token);

  select run_row.* into v_run
  from public.provider_sync_runs run_row
  where run_row.id = p_run_id
  for update;
  if not found or v_run.status <> 'running' or v_run.sync_type <> 'sync-season-players' then
    raise exception 'Preparazione catalogo provider rifiutata [catalog.run_invalid].';
  end if;

  select publication_row.* into v_publication
  from public.provider_sync_publications publication_row
  where publication_row.run_id = p_run_id
  for update;
  if not found or v_publication.status <> 'collecting' then
    raise exception 'Preparazione catalogo provider rifiutata [catalog.publication_invalid].';
  end if;

  select certificate_row.* into v_certificate
  from public.provider_sync_scope_certificates certificate_row
  where certificate_row.publication_id = v_publication.id
  for update;
  if not found or v_certificate.status <> 'certified'
     or v_certificate.requested_season is null then
    raise exception 'Preparazione catalogo provider rifiutata [catalog.scope_invalid].';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext('provider-player-catalog:' || v_run.provider || ':IT-SA')::bigint
  );

  select head_row.* into v_head
  from public.provider_player_catalog_heads head_row
  where head_row.provider = v_run.provider and head_row.competition_code = 'IT-SA'
  for update;
  if found and v_certificate.requested_season < v_head.latest_season then
    raise exception 'Preparazione catalogo provider rifiutata [catalog.older_season].';
  end if;
  if v_certificate.observed_athlete_count <= 0 then
    raise exception 'Consegna catalogo provider incompleta [catalog.empty_snapshot]: nessun calciatore certificato.';
  end if;
  if v_certificate.observed_role_count <> v_certificate.observed_athlete_count * 2 then
    raise exception
      'Consegna catalogo provider incompleta [catalog.role_coverage]: ruoli %, calciatori %.',
      v_certificate.observed_role_count,v_certificate.observed_athlete_count;
  end if;
  if v_head.id is not null
     and v_head.active_player_count > 0
     and v_certificate.observed_athlete_count * 2 < v_head.active_player_count then
    raise exception
      'Consegna catalogo provider incompleta [catalog.coverage_drop]: ricevuti %, attivi correnti %.',
      v_certificate.observed_athlete_count,v_head.active_player_count;
  end if;

  insert into public.provider_player_catalog_reconciliations (
    head_id,publication_id,run_id,recovery_request_id,league_id,provider,
    competition_code,season,status,previous_season,observed_player_count,
    authoritative_role_count,reason_code,summary,reconciliation_fingerprint
  ) values (
    v_head.id,v_publication.id,v_run.id,v_publication.recovery_request_id,
    v_publication.league_id,v_run.provider,'IT-SA',v_certificate.requested_season,
    'collecting',v_head.latest_season,v_certificate.observed_athlete_count,
    v_certificate.observed_role_count,'catalog.collecting',
    format('Catalogo provider stagione %s pronto per la riconciliazione atomica.',v_certificate.requested_season),
    pg_catalog.md5(v_publication.id::text || E'\n' || v_run.id::text || E'\n'
      || v_run.provider || E'\nIT-SA\n' || v_certificate.requested_season::text)
  )
  on conflict (publication_id) do nothing;

  select reconciliation_row.* into v_reconciliation
  from public.provider_player_catalog_reconciliations reconciliation_row
  where reconciliation_row.publication_id = v_publication.id
  for update;
  if not found then
    raise exception 'Preparazione catalogo provider fallita [catalog.reconciliation_missing].';
  end if;
  if v_reconciliation.status = 'applied' then
    return jsonb_build_object(
      'catalogReconciliation',true,'catalogStatus','applied',
      'catalogReconciliationId',v_reconciliation.id,'catalogSeason',v_reconciliation.season
    );
  end if;
  if v_reconciliation.status <> 'collecting' then
    raise exception 'Preparazione catalogo provider rifiutata [catalog.reconciliation_terminal].';
  end if;

  insert into public.provider_player_catalog_members (
    reconciliation_id,player_key_fingerprint,classic_role,mantra_role,member_fingerprint
  )
  select
    v_reconciliation.id,
    pg_catalog.md5(stage_athlete.provider || E'\n' || stage_athlete.provider_player_id),
    max(stage_role.role_code) filter (where stage_role.mode = 'classic'),
    max(stage_role.role_code) filter (where stage_role.mode = 'mantra'),
    pg_catalog.md5(
      stage_athlete.provider || E'\n' || stage_athlete.provider_player_id || E'\n'
      || max(stage_role.role_code) filter (where stage_role.mode = 'classic')
      || E'\n'
      || max(stage_role.role_code) filter (where stage_role.mode = 'mantra')
    )
  from public.provider_sync_stage_athletes stage_athlete
  join public.provider_sync_stage_roles stage_role
    on stage_role.publication_id = stage_athlete.publication_id
   and stage_role.athlete_id = stage_athlete.athlete_id
  where stage_athlete.publication_id = v_publication.id
  group by stage_athlete.provider,stage_athlete.provider_player_id
  on conflict (reconciliation_id,player_key_fingerprint) do nothing;

  select count(*)::integer into v_member_count
  from public.provider_player_catalog_members member_row
  where member_row.reconciliation_id = v_reconciliation.id;
  select count(*)::integer into v_staged_count
  from public.provider_sync_stage_athletes stage_row
  where stage_row.publication_id = v_publication.id;

  if v_member_count <> v_staged_count
     or v_member_count <> v_certificate.observed_athlete_count then
    raise exception
      'Preparazione catalogo provider rifiutata [catalog.member_count_mismatch]: membri %, staging %, certificato %.',
      v_member_count,v_staged_count,v_certificate.observed_athlete_count;
  end if;

  return jsonb_build_object(
    'catalogReconciliation',true,
    'catalogStatus','collecting',
    'catalogReconciliationId',v_reconciliation.id,
    'catalogSeason',v_reconciliation.season,
    'catalogPlayerCount',v_member_count
  );
end;
$function$;

revoke all on function public.prepare_provider_player_catalog_reconciliation_v1(uuid,uuid) from public,anon,authenticated,service_role;

-- La riconciliazione viene applicata nello stesso commit della pubblicazione:
-- il trigger scatta dopo che gli upsert live sono riusciti, ma prima della
-- chiusura del run. Nessun atleta o rosa viene cancellato fisicamente.
create or replace function public.apply_provider_player_catalog_on_publication_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_reconciliation public.provider_player_catalog_reconciliations%rowtype;
  v_head public.provider_player_catalog_heads%rowtype;
  v_removed_roles integer := 0;
  v_deactivated integer := 0;
  v_rostered_retired integer := 0;
  v_active_count integer := 0;
  v_resolved_count integer := 0;
  v_live_role_count integer := 0;
  v_transition text;
begin
  if new.status <> 'published' or new.status is not distinct from old.status then
    return new;
  end if;

  select reconciliation_row.* into v_reconciliation
  from public.provider_player_catalog_reconciliations reconciliation_row
  where reconciliation_row.publication_id = new.id
    and reconciliation_row.status = 'collecting'
  for update;
  if not found then
    return new;
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext('provider-player-catalog:' || v_reconciliation.provider || ':IT-SA')::bigint
  );

  select head_row.* into v_head
  from public.provider_player_catalog_heads head_row
  where head_row.provider = v_reconciliation.provider
    and head_row.competition_code = v_reconciliation.competition_code
  for update;
  if found and v_reconciliation.season < v_head.latest_season then
    raise exception 'Riconciliazione catalogo provider rifiutata [catalog.regression_after_publication_lock].';
  end if;

  perform pg_catalog.set_config(
    'leghevo.provider_catalog_reconciliation_id',v_reconciliation.id::text,true
  );

  select count(*)::integer into v_resolved_count
  from public.provider_player_catalog_members member_row
  join public.athletes athlete_row
    on athlete_row.provider = v_reconciliation.provider
   and pg_catalog.md5(athlete_row.provider || E'\n' || athlete_row.provider_player_id)
       = member_row.player_key_fingerprint
  where member_row.reconciliation_id = v_reconciliation.id;

  if v_resolved_count <> v_reconciliation.observed_player_count then
    raise exception
      'Riconciliazione catalogo provider rifiutata [catalog.live_resolution_mismatch]: risolti %, attesi %.',
      v_resolved_count,v_reconciliation.observed_player_count;
  end if;

  with removed as (
    delete from public.athlete_roles role_row
    using public.provider_player_catalog_members member_row,public.athletes athlete_row
    where member_row.reconciliation_id = v_reconciliation.id
      and athlete_row.id = role_row.athlete_id
      and athlete_row.provider = v_reconciliation.provider
      and pg_catalog.md5(athlete_row.provider || E'\n' || athlete_row.provider_player_id)
          = member_row.player_key_fingerprint
      and role_row.mode in ('classic','mantra')
      and (
        (role_row.mode = 'classic' and role_row.role_code <> member_row.classic_role)
        or (role_row.mode = 'mantra' and role_row.role_code <> member_row.mantra_role)
      )
    returning role_row.athlete_id
  )
  select count(*)::integer into v_removed_roles from removed;

  insert into public.athlete_roles (athlete_id,mode,role_code)
  select authoritative_role.athlete_id,authoritative_role.mode,authoritative_role.role_code
  from (
    select athlete_row.id as athlete_id,'classic'::public.league_mode as mode,member_row.classic_role as role_code
    from public.provider_player_catalog_members member_row
    join public.athletes athlete_row
      on athlete_row.provider = v_reconciliation.provider
     and pg_catalog.md5(athlete_row.provider || E'\n' || athlete_row.provider_player_id)
         = member_row.player_key_fingerprint
    where member_row.reconciliation_id = v_reconciliation.id
    union all
    select athlete_row.id as athlete_id,'mantra'::public.league_mode as mode,member_row.mantra_role as role_code
    from public.provider_player_catalog_members member_row
    join public.athletes athlete_row
      on athlete_row.provider = v_reconciliation.provider
     and pg_catalog.md5(athlete_row.provider || E'\n' || athlete_row.provider_player_id)
         = member_row.player_key_fingerprint
    where member_row.reconciliation_id = v_reconciliation.id
  ) authoritative_role
  on conflict (athlete_id,mode,role_code) do nothing;

  select count(*)::integer into v_live_role_count
  from public.athlete_roles role_row
  join public.athletes athlete_row on athlete_row.id = role_row.athlete_id
  join public.provider_player_catalog_members member_row
    on member_row.reconciliation_id = v_reconciliation.id
   and member_row.player_key_fingerprint = pg_catalog.md5(
     athlete_row.provider || E'\n' || athlete_row.provider_player_id
   )
  where athlete_row.provider = v_reconciliation.provider
    and role_row.mode in ('classic','mantra')
    and (
      (role_row.mode = 'classic' and role_row.role_code = member_row.classic_role)
      or (role_row.mode = 'mantra' and role_row.role_code = member_row.mantra_role)
    );

  if v_live_role_count <> v_reconciliation.observed_player_count * 2 then
    raise exception
      'Riconciliazione catalogo provider rifiutata [catalog.live_role_mismatch]: ruoli %, attesi %.',
      v_live_role_count,v_reconciliation.observed_player_count * 2;
  end if;

  update public.athletes athlete_row
  set active = true,updated_at = now()
  where athlete_row.provider = v_reconciliation.provider
    and not athlete_row.active
    and exists (
      select 1 from public.provider_player_catalog_members member_row
      where member_row.reconciliation_id = v_reconciliation.id
        and member_row.player_key_fingerprint = pg_catalog.md5(
          athlete_row.provider || E'\n' || athlete_row.provider_player_id
        )
    );

  with retired as (
    update public.athletes athlete_row
    set active = false,updated_at = now()
    where athlete_row.provider = v_reconciliation.provider
      and athlete_row.active
      and not exists (
        select 1 from public.provider_player_catalog_members member_row
        where member_row.reconciliation_id = v_reconciliation.id
          and member_row.player_key_fingerprint = pg_catalog.md5(
            athlete_row.provider || E'\n' || athlete_row.provider_player_id
          )
      )
    returning athlete_row.id
  )
  select
    count(*)::integer,
    count(*) filter (
      where exists (
        select 1 from public.roster_entries roster_row
        where roster_row.athlete_id = retired.id
          and roster_row.released_at is null
      )
    )::integer
  into v_deactivated,v_rostered_retired
  from retired;

  select count(*)::integer into v_active_count
  from public.athletes athlete_row
  where athlete_row.provider = v_reconciliation.provider and athlete_row.active;

  if v_active_count <> v_reconciliation.observed_player_count then
    raise exception
      'Riconciliazione catalogo provider rifiutata [catalog.active_count_mismatch]: attivi %, attesi %.',
      v_active_count,v_reconciliation.observed_player_count;
  end if;

  if v_head.id is null then
    insert into public.provider_player_catalog_heads (
      provider,competition_code,latest_season,latest_run_id,latest_publication_id,
      latest_run_started_at,active_player_count,generation,last_transition,summary
    )
    select
      v_reconciliation.provider,v_reconciliation.competition_code,v_reconciliation.season,
      v_reconciliation.run_id,v_reconciliation.publication_id,run_row.started_at,
      v_active_count,1,'backfilled',
      format('Catalogo provider stagione %s applicato con %s calciatori attivi.',v_reconciliation.season,v_active_count)
    from public.provider_sync_runs run_row
    where run_row.id = v_reconciliation.run_id
    returning * into v_head;
  else
    v_transition := case when v_reconciliation.season > v_head.latest_season
      then 'advanced' else 'refreshed' end;
    update public.provider_player_catalog_heads head_row
    set
      latest_season = v_reconciliation.season,
      latest_run_id = v_reconciliation.run_id,
      latest_publication_id = v_reconciliation.publication_id,
      latest_run_started_at = (select run_row.started_at from public.provider_sync_runs run_row where run_row.id = v_reconciliation.run_id),
      active_player_count = v_active_count,
      generation = head_row.generation + 1,
      last_transition = v_transition,
      summary = format(
        'Catalogo provider stagione %s riconciliato: %s attivi, %s ritirati, %s ruoli superati rimossi.',
        v_reconciliation.season,v_active_count,v_deactivated,v_removed_roles
      )
    where head_row.id = v_head.id
    returning * into v_head;
  end if;

  update public.provider_player_catalog_reconciliations reconciliation_row
  set
    head_id = v_head.id,
    status = 'applied',
    deactivated_player_count = v_deactivated,
    authoritative_role_count = v_reconciliation.observed_player_count * 2,
    removed_role_count = v_removed_roles,
    rostered_retired_count = v_rostered_retired,
    generation = v_head.generation,
    reason_code = 'catalog.applied',
    summary = format(
      'Catalogo calciatori provider riconciliato senza cancellazioni: %s presenti, %s resi inattivi, %s ruoli superati rimossi.',
      v_reconciliation.observed_player_count,v_deactivated,v_removed_roles
    )
  where reconciliation_row.id = v_reconciliation.id;

  perform pg_catalog.set_config('leghevo.provider_catalog_reconciliation_id','',true);
  return new;
end;
$function$;

revoke all on function public.apply_provider_player_catalog_on_publication_v1() from public,anon,authenticated,service_role;
drop trigger if exists provider_player_catalog_publication_reconcile on public.provider_sync_publications;
create trigger provider_player_catalog_publication_reconcile
 after update of status on public.provider_sync_publications
for each row execute function public.apply_provider_player_catalog_on_publication_v1();
alter table public.provider_sync_publications enable always trigger provider_player_catalog_publication_reconcile;

create or replace function public.discard_superseded_provider_player_catalog_v1(
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
as $function$
declare
  v_run public.provider_sync_runs%rowtype;
  v_publication public.provider_sync_publications%rowtype;
  v_certificate public.provider_sync_scope_certificates%rowtype;
  v_head public.provider_player_catalog_heads%rowtype;
  v_reconciliation public.provider_player_catalog_reconciliations%rowtype;
  v_result jsonb;
begin
  if coalesce((p_decision ->> 'applicable')::boolean,false) is not true
     or coalesce((p_decision ->> 'superseded')::boolean,false) is not true then
    raise exception 'Scarto catalogo provider rifiutato [catalog.decision_not_superseded].';
  end if;

  select run_row.* into v_run
  from public.provider_sync_runs run_row
  where run_row.id = p_run_id
  for update;
  if not found or v_run.status <> 'running' or v_run.sync_type <> 'sync-season-players' then
    raise exception 'Scarto catalogo provider rifiutato [catalog.run_invalid].';
  end if;

  select publication_row.* into v_publication
  from public.provider_sync_publications publication_row
  where publication_row.run_id = p_run_id
  for update;
  if not found or v_publication.status <> 'collecting' then
    raise exception 'Scarto catalogo provider rifiutato [catalog.publication_invalid].';
  end if;

  select certificate_row.* into v_certificate
  from public.provider_sync_scope_certificates certificate_row
  where certificate_row.publication_id = v_publication.id
  for update;
  if not found or v_certificate.status <> 'certified' or v_certificate.requested_season is null then
    raise exception 'Scarto catalogo provider rifiutato [catalog.scope_invalid].';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext('provider-player-catalog:' || v_run.provider || ':IT-SA')::bigint
  );
  select head_row.* into v_head
  from public.provider_player_catalog_heads head_row
  where head_row.provider = v_run.provider and head_row.competition_code = 'IT-SA'
  for update;
  if not found
     or v_head.id is distinct from nullif(p_decision ->> 'headId','')::uuid
     or v_head.latest_season is distinct from (p_decision ->> 'headSeason')::integer
     or v_head.latest_run_id is distinct from nullif(p_decision ->> 'headRunId','')::uuid
     or v_certificate.requested_season >= v_head.latest_season then
    raise exception 'Scarto catalogo provider rifiutato [catalog.head_changed].';
  end if;

  insert into public.provider_player_catalog_reconciliations (
    head_id,publication_id,run_id,recovery_request_id,league_id,provider,
    competition_code,season,status,previous_season,observed_player_count,
    authoritative_role_count,generation,reason_code,summary,
    reconciliation_fingerprint,superseded_at
  ) values (
    v_head.id,v_publication.id,v_run.id,v_publication.recovery_request_id,
    v_publication.league_id,v_run.provider,'IT-SA',v_certificate.requested_season,
    'superseded',v_head.latest_season,v_certificate.observed_athlete_count,
    v_certificate.observed_role_count,v_head.generation,'catalog.older_season',
    format('Catalogo stagione %s non applicato: la stagione corrente è %s.',v_certificate.requested_season,v_head.latest_season),
    pg_catalog.md5(v_publication.id::text || E'\n' || v_run.id::text || E'\n'
      || 'catalog.older_season' || E'\n' || v_certificate.requested_season::text
      || E'\n' || v_head.latest_season::text),
    now()
  )
  on conflict (publication_id) do nothing;

  select reconciliation_row.* into v_reconciliation
  from public.provider_player_catalog_reconciliations reconciliation_row
  where reconciliation_row.publication_id = v_publication.id;
  if not found or v_reconciliation.status <> 'superseded' then
    raise exception 'Scarto catalogo provider rifiutato [catalog.reconciliation_missing].';
  end if;

  delete from public.provider_sync_stage_scores row_item where row_item.publication_id = v_publication.id;
  delete from public.provider_sync_stage_fixtures row_item where row_item.publication_id = v_publication.id;
  delete from public.provider_sync_stage_roles row_item where row_item.publication_id = v_publication.id;
  delete from public.provider_sync_stage_matchdays row_item where row_item.publication_id = v_publication.id;
  delete from public.provider_sync_stage_athletes row_item where row_item.publication_id = v_publication.id;

  update public.provider_sync_publications publication_row
  set status = 'discarded',published_primary_record_count = 0,
      summary = left(format(
        'Pubblicazione catalogo provider non applicata: stagione %s precedente alla stagione corrente %s.',
        v_certificate.requested_season,v_head.latest_season
      ),500)
  where publication_row.id = v_publication.id
  returning * into v_publication;

  v_result := public.finish_provider_sync_run_guarded_v3(
    p_run_id,'completed',p_records_processed,null,p_expected_revision,p_lease_token
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
    'catalogReconciliation',true,
    'catalogSuperseded',true,
    'catalogStatus','superseded',
    'catalogReconciliationId',v_reconciliation.id,
    'catalogSeason',v_reconciliation.season,
    'catalogCurrentSeason',v_head.latest_season,
    'catalogGeneration',v_head.generation,
    'catalogPlayerCount',v_reconciliation.observed_player_count,
    'catalogDeactivatedPlayerCount',0,
    'catalogRemovedRoleCount',0,
    'catalogRosteredRetiredCount',0
  );
end;
$function$;

revoke all on function public.discard_superseded_provider_player_catalog_v1(uuid,integer,bigint,uuid,jsonb) from public,anon,authenticated,service_role;

create or replace function public.get_provider_player_catalog_result_v1(p_run_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_row public.provider_player_catalog_reconciliations%rowtype;
begin
  select reconciliation_row.* into v_row
  from public.provider_player_catalog_reconciliations reconciliation_row
  where reconciliation_row.run_id = p_run_id;
  if not found then
    return jsonb_build_object('catalogReconciliation',false,'catalogSuperseded',false);
  end if;
  return jsonb_build_object(
    'catalogReconciliation',true,
    'catalogSuperseded',v_row.status = 'superseded',
    'catalogStatus',v_row.status,
    'catalogReconciliationId',v_row.id,
    'catalogSeason',v_row.season,
    'catalogCurrentSeason',case when v_row.status = 'superseded' then coalesce(v_row.previous_season,v_row.season) else v_row.season end,
    'catalogGeneration',v_row.generation,
    'catalogPlayerCount',v_row.observed_player_count,
    'catalogDeactivatedPlayerCount',v_row.deactivated_player_count,
    'catalogAuthoritativeRoleCount',v_row.authoritative_role_count,
    'catalogRemovedRoleCount',v_row.removed_role_count,
    'catalogRosteredRetiredCount',v_row.rostered_retired_count
  );
end;
$function$;

revoke all on function public.get_provider_player_catalog_result_v1(uuid) from public,anon,authenticated,service_role;

-- La funzione storica conserva il nome richiesto dalla v0.62.16 ma certifica
-- ora qualunque pubblicazione benignamente superata: watermark o catalogo.
create or replace function public.certify_stale_provider_recovery_outcome_v1(
  p_request_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_request public.provider_recovery_requests%rowtype;
  v_incident public.provider_operational_incidents%rowtype;
  v_snapshot public.provider_data_quality_snapshots%rowtype;
  v_existing_id uuid;
  v_outcome text;
  v_summary text;
  v_reason text;
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

  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('provider-recovery:' || v_request.incident_id::text)::bigint);
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('provider-recovery-outcome:' || p_request_id::text)::bigint);

  select certificate_row.id into v_existing_id
  from public.provider_recovery_outcome_certificates certificate_row
  where certificate_row.request_id = p_request_id;
  if found then return v_existing_id; end if;

  select request_row.* into v_request
  from public.provider_recovery_requests request_row
  where request_row.id = p_request_id
  for update;
  if not found or v_request.status <> 'completed' or v_request.recovery_run_id is null then
    raise exception 'Richiesta provider superata non certificabile [superseded.request_not_completed].';
  end if;

  if exists (
    select 1 from public.provider_sync_scope_watermark_events event_row
    where event_row.candidate_run_id = v_request.recovery_run_id
      and event_row.event_type = 'stale_rejected'
      and event_row.reason_code = 'watermark.stale_run'
  ) then
    v_reason := 'watermark.stale_run';
  elsif exists (
    select 1 from public.provider_player_catalog_reconciliations reconciliation_row
    where reconciliation_row.run_id = v_request.recovery_run_id
      and reconciliation_row.status = 'superseded'
      and reconciliation_row.reason_code = 'catalog.older_season'
  ) then
    v_reason := 'catalog.older_season';
  else
    raise exception 'Richiesta provider superata non certificabile [superseded.event_missing].';
  end if;

  select incident_row.* into v_incident
  from public.provider_operational_incidents incident_row
  where incident_row.id = v_request.incident_id
  for update;
  if not found then raise exception 'Incidente della richiesta provider superata non trovato.'; end if;

  select snapshot_row.* into v_snapshot
  from public.provider_data_quality_snapshots snapshot_row
  where snapshot_row.run_id = v_request.recovery_run_id
  order by snapshot_row.created_at desc limit 1;

  if v_incident.status = 'resolved' then
    v_outcome := 'verified';
    v_summary := 'Recupero provider verificato: incidente risolto; pubblicazione superata senza regressione.';
  else
    v_outcome := 'superseded';
    v_summary := case when v_reason = 'catalog.older_season'
      then 'Recupero completato senza retry: catalogo storico superato dalla stagione corrente.'
      else 'Recupero completato senza retry: pubblicazione superata da dati più recenti.' end;
  end if;

  insert into public.provider_recovery_outcome_certificates (
    league_id,request_id,incident_id,recovery_run_id,provider,sync_type,
    outcome,incident_status,incident_revision,source_snapshot_id,
    source_snapshot_status,anomaly_count,verification_summary,
    certificate_fingerprint,created_at
  ) values (
    v_request.league_id,v_request.id,v_request.incident_id,v_request.recovery_run_id,
    v_request.provider,v_request.sync_type,v_outcome,v_incident.status,
    v_incident.revision,v_snapshot.id,v_snapshot.status,
    coalesce(v_snapshot.anomaly_count,0),v_summary,
    pg_catalog.md5(v_request.id::text || E'\n' || v_request.recovery_run_id::text
      || E'\n' || v_incident.id::text || E'\n' || v_incident.status || E'\n'
      || v_incident.revision::text || E'\n' || v_outcome || E'\n' || v_reason
      || E'\n' || coalesce(v_snapshot.id::text,'')),
    coalesce(v_request.finished_at,now())
  )
  on conflict (request_id) do nothing returning id into v_certificate_id;

  if v_certificate_id is null then
    select certificate_row.id into v_certificate_id
    from public.provider_recovery_outcome_certificates certificate_row
    where certificate_row.request_id = p_request_id;
  end if;
  if v_certificate_id is null then raise exception 'Certificato esito provider superato non creato.'; end if;
  return v_certificate_id;
end;
$function$;

revoke all on function public.certify_stale_provider_recovery_outcome_v1(uuid) from public,anon,authenticated,service_role;

create or replace function public.capture_provider_recovery_outcome_certificate_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_request record;
  v_is_superseded boolean;
begin
  if new.event_type <> 'completed' then return new; end if;

  select
    exists (
      select 1 from public.provider_sync_scope_watermark_events event_row
      where event_row.candidate_run_id = new.run_id
        and event_row.event_type = 'stale_rejected'
        and event_row.reason_code = 'watermark.stale_run'
    )
    or exists (
      select 1 from public.provider_player_catalog_reconciliations reconciliation_row
      where reconciliation_row.run_id = new.run_id
        and reconciliation_row.status = 'superseded'
        and reconciliation_row.reason_code = 'catalog.older_season'
    )
  into v_is_superseded;

  for v_request in
    select request_row.id
    from public.provider_recovery_requests request_row
    where request_row.recovery_run_id = new.run_id
      and request_row.status = 'completed'
    order by request_row.finished_at desc nulls last,request_row.id desc
  loop
    if v_is_superseded then
      perform public.certify_stale_provider_recovery_outcome_v1(v_request.id);
    else
      perform public.certify_provider_recovery_request_outcome_v1(v_request.id);
    end if;
  end loop;
  return new;
end;
$function$;

revoke all on function public.capture_provider_recovery_outcome_certificate_v1() from public,anon,authenticated;

-- Gli errori di riconciliazione catalogo sono deterministici e non vengono
-- trasformati in catene di retry identiche.
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
as $function$
declare
  v_message text := lower(trim(coalesce(p_error_summary,'')));
  v_retry_no integer := greatest(coalesce(p_retry_no,1),1);
  v_sync_type text := lower(trim(coalesce(p_sync_type,'')));
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
    or v_message like '%catalogo provider rifiutat%'
    or v_message like '%riconciliazione catalogo provider rifiutat%'
    or v_message like '%catalog.member_count_mismatch%'
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

  if v_retry_no > v_max_retries then v_retryable := false; end if;

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
    v_delay_seconds := greatest(v_delay_seconds,300);
  end if;

  return jsonb_build_object(
    'retryable',v_retryable,'failureClass',v_failure_class,
    'retryNo',v_retry_no,'maxRetries',v_max_retries,
    'delaySeconds',v_delay_seconds
  );
end;
$function$;

revoke all on function public.provider_recovery_retry_policy_v1(text,integer,text)
from public,anon,authenticated;
grant execute on function public.provider_recovery_retry_policy_v1(text,integer,text)
to service_role;

create or replace function public.guard_provider_sync_atomic_completion_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_publication_id uuid;
  v_publication_status text;
begin
  if new.status <> 'completed' or new.status is not distinct from old.status then return new; end if;

  select publication_row.id,publication_row.status
  into v_publication_id,v_publication_status
  from public.provider_sync_publications publication_row
  where publication_row.run_id = new.id;
  if not found then
    raise exception 'Chiusura provider rifiutata [publication.missing]: pubblicazione atomica assente.';
  end if;
  if v_publication_status = 'published' then return new; end if;
  if v_publication_status = 'discarded' and (
    exists (
      select 1 from public.provider_sync_scope_watermark_events event_row
      where event_row.candidate_publication_id = v_publication_id
        and event_row.candidate_run_id = new.id
        and event_row.event_type = 'stale_rejected'
        and event_row.reason_code = 'watermark.stale_run'
    )
    or exists (
      select 1 from public.provider_player_catalog_reconciliations reconciliation_row
      where reconciliation_row.publication_id = v_publication_id
        and reconciliation_row.run_id = new.id
        and reconciliation_row.status = 'superseded'
        and reconciliation_row.reason_code = 'catalog.older_season'
    )
  ) then return new; end if;

  raise exception 'Chiusura provider rifiutata [publication.not_published]: stato %.',v_publication_status;
end;
$function$;

revoke all on function public.guard_provider_sync_atomic_completion_v1() from public,anon,authenticated;

create or replace function public.finish_provider_sync_run_guarded_v7(
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
as $function$
declare
  v_status text := lower(trim(coalesce(p_status,'')));
  v_decision jsonb := '{}'::jsonb;
  v_scope jsonb := '{}'::jsonb;
  v_catalog_decision jsonb := '{}'::jsonb;
  v_catalog_prepare jsonb := '{}'::jsonb;
  v_catalog_result jsonb := '{}'::jsonb;
  v_result jsonb;
  v_watermark jsonb := '{}'::jsonb;
  v_sync_type text;
begin
  if v_status not in ('completed','failed') then
    raise exception 'Stato finale del run provider non valido.';
  end if;

  if v_status = 'failed' then
    v_result := public.finish_provider_sync_run_atomic_core_v1(
      p_run_id,p_status,p_records_processed,p_error_message,p_expected_revision,p_lease_token
    );
    return v_result || jsonb_build_object(
      'monotonicPublication',true,'publicationSuperseded',false,
      'catalogReconciliation',false,'catalogSuperseded',false
    );
  end if;

  select run_row.sync_type into v_sync_type
  from public.provider_sync_runs run_row where run_row.id = p_run_id;
  if not found then raise exception 'Run provider non trovato durante la chiusura v7.'; end if;

  v_decision := public.provider_sync_scope_watermark_decision_v1(p_run_id,p_lease_token);
  if coalesce((v_decision ->> 'stale')::boolean,false) then
    return public.discard_stale_provider_sync_publication_v1(
      p_run_id,p_records_processed,p_expected_revision,p_lease_token,v_decision
    ) || jsonb_build_object('catalogReconciliation',false,'catalogSuperseded',false);
  end if;

  v_scope := public.certify_provider_sync_publication_scope_v1(p_run_id,p_lease_token);

  if v_sync_type = 'sync-season-players' then
    v_catalog_decision := public.provider_player_catalog_decision_v1(p_run_id,p_lease_token);
    if coalesce((v_catalog_decision ->> 'superseded')::boolean,false) then
      return public.discard_superseded_provider_player_catalog_v1(
        p_run_id,p_records_processed,p_expected_revision,p_lease_token,v_catalog_decision
      );
    end if;
    v_catalog_prepare := public.prepare_provider_player_catalog_reconciliation_v1(p_run_id,p_lease_token);
    perform pg_catalog.set_config(
      'leghevo.provider_catalog_reconciliation_id',
      v_catalog_prepare ->> 'catalogReconciliationId',true
    );
  end if;

  v_result := public.finish_provider_sync_run_atomic_core_v1(
    p_run_id,p_status,p_records_processed,p_error_message,p_expected_revision,p_lease_token
  );

  perform pg_catalog.set_config('leghevo.provider_catalog_reconciliation_id','',true);

  v_watermark := public.advance_provider_sync_scope_watermark_v1(
    p_run_id,p_records_processed,p_lease_token
  );
  v_catalog_result := public.get_provider_player_catalog_result_v1(p_run_id);

  return v_result || v_scope || v_watermark || v_catalog_prepare || v_catalog_result
    || jsonb_build_object(
      'semanticScopeBinding',true,
      'monotonicPublication',true,
      'publicationSuperseded',false
    );
end;
$function$;

revoke all on function public.finish_provider_sync_run_guarded_v7(uuid,text,integer,text,bigint,uuid) from public,anon,authenticated;
grant execute on function public.finish_provider_sync_run_guarded_v7(uuid,text,integer,text,bigint,uuid) to service_role;

-- Compatibilità server-side: v6 mantiene i marcatori richiesti dalla propria
-- diagnostica e instrada realmente tutto nel nuovo completion gate v7.
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
as $function$
begin
  -- provider_sync_scope_watermark_decision_v1
  -- discard_stale_provider_sync_publication_v1
  -- advance_provider_sync_scope_watermark_v1
  return public.finish_provider_sync_run_guarded_v7(
    p_run_id,p_status,p_records_processed,p_error_message,p_expected_revision,p_lease_token
  );
end;
$function$;

revoke all on function public.finish_provider_sync_run_guarded_v6(uuid,text,integer,text,bigint,uuid) from public,anon,authenticated;
grant execute on function public.finish_provider_sync_run_guarded_v6(uuid,text,integer,text,bigint,uuid) to service_role;

create or replace function public.get_league_provider_player_catalog_center_v1(p_league_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_owner_id uuid;
  v_collecting integer := 0;
  v_applied_24h integer := 0;
  v_superseded_24h integer := 0;
  v_deactivated_24h integer := 0;
  v_removed_roles_24h integer := 0;
  v_rostered_retired integer := 0;
  v_total integer := 0;
  v_head jsonb;
  v_latest jsonb;
  v_latest_at timestamptz;
begin
  select league_row.owner_id into v_owner_id
  from public.leagues league_row where league_row.id = p_league_id;
  if not found then raise exception 'Lega non trovata per il controllo del catalogo provider.'; end if;
  if auth.uid() is null or not (v_owner_id = auth.uid() or public.is_league_admin(p_league_id)) then
    raise exception 'Solo Presidente e Admin possono leggere il catalogo provider.';
  end if;

  select
    count(*)::integer,
    count(*) filter (where status = 'collecting')::integer,
    count(*) filter (where status = 'applied' and applied_at >= now() - interval '24 hours')::integer,
    count(*) filter (where status = 'superseded' and superseded_at >= now() - interval '24 hours')::integer,
    coalesce(sum(deactivated_player_count) filter (where applied_at >= now() - interval '24 hours'),0)::integer,
    coalesce(sum(removed_role_count) filter (where applied_at >= now() - interval '24 hours'),0)::integer,
    0::integer,
    max(updated_at)
  into v_total,v_collecting,v_applied_24h,v_superseded_24h,v_deactivated_24h,
       v_removed_roles_24h,v_rostered_retired,v_latest_at
  from public.provider_player_catalog_reconciliations reconciliation_row
  where reconciliation_row.league_id = p_league_id or reconciliation_row.league_id is null;

  select count(distinct roster_row.athlete_id)::integer
  into v_rostered_retired
  from public.roster_entries roster_row
  join public.athletes athlete_row on athlete_row.id = roster_row.athlete_id
  where roster_row.league_id = p_league_id
    and roster_row.released_at is null
    and not athlete_row.active;

  select jsonb_build_object(
    'id',head_row.id,'provider',head_row.provider,'competitionCode',head_row.competition_code,
    'season',head_row.latest_season,'activePlayerCount',head_row.active_player_count,
    'generation',head_row.generation,'lastTransition',head_row.last_transition,
    'summary',head_row.summary,'updatedAt',head_row.updated_at
  ) into v_head
  from public.provider_player_catalog_heads head_row
  order by head_row.updated_at desc limit 1;

  select jsonb_build_object(
    'id',reconciliation_row.id,'runId',reconciliation_row.run_id,
    'publicationId',reconciliation_row.publication_id,
    'requestId',reconciliation_row.recovery_request_id,
    'season',reconciliation_row.season,'status',reconciliation_row.status,
    'observedPlayerCount',reconciliation_row.observed_player_count,
    'deactivatedPlayerCount',reconciliation_row.deactivated_player_count,
    'authoritativeRoleCount',reconciliation_row.authoritative_role_count,
    'removedRoleCount',reconciliation_row.removed_role_count,
    'rosteredRetiredCount',reconciliation_row.rostered_retired_count,
    'generation',reconciliation_row.generation,'reasonCode',reconciliation_row.reason_code,
    'summary',reconciliation_row.summary,'updatedAt',reconciliation_row.updated_at
  ) into v_latest
  from public.provider_player_catalog_reconciliations reconciliation_row
  where reconciliation_row.league_id = p_league_id or reconciliation_row.league_id is null
  order by reconciliation_row.updated_at desc,reconciliation_row.id desc limit 1;

  return jsonb_build_object(
    'protected',true,
    'healthy',v_collecting = 0,
    'authoritativeSnapshotActive',true,
    'historicalSeasonRegressionBlocked',true,
    'missingPlayersSoftDeactivated',true,
    'exactRoleReplacementActive',true,
    'physicalPlayerDeletionDisabled',true,
    'collectingCount',v_collecting,
    'appliedLast24h',v_applied_24h,
    'supersededLast24h',v_superseded_24h,
    'deactivatedPlayersLast24h',v_deactivated_24h,
    'removedRolesLast24h',v_removed_roles_24h,
    'rosteredRetiredTotal',v_rostered_retired,
    'totalReconciliationCount',v_total,
    'latestReconciliationAt',v_latest_at,
    'head',v_head,
    'latest',v_latest
  );
end;
$function$;

revoke all on function public.get_league_provider_player_catalog_center_v1(uuid) from public,anon,service_role;
grant execute on function public.get_league_provider_player_catalog_center_v1(uuid) to authenticated;

create or replace function public.get_league_provider_sync_health_v16(p_league_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_base jsonb;
  v_catalog jsonb;
  v_healthy boolean;
  v_status text;
begin
  v_base := public.get_league_provider_sync_health_v15(p_league_id);
  v_catalog := public.get_league_provider_player_catalog_center_v1(p_league_id);
  v_healthy := coalesce((v_base ->> 'healthy')::boolean,false)
    and coalesce((v_catalog ->> 'healthy')::boolean,false);
  v_status := case
    when not v_healthy then 'attention'
    when coalesce(v_base ->> 'status','idle') = 'idle' then 'idle'
    else 'healthy' end;

  return v_base || jsonb_build_object(
    'protected',coalesce((v_base ->> 'protected')::boolean,false)
      and coalesce((v_catalog ->> 'protected')::boolean,false),
    'healthy',v_healthy,
    'status',v_status,
    'playerCatalogReconciliation',v_catalog
  );
end;
$function$;

revoke all on function public.get_league_provider_sync_health_v16(uuid) from public,anon,service_role;
grant execute on function public.get_league_provider_sync_health_v16(uuid) to authenticated;

-- Solo head, riconciliazioni ed eventi sintetici sono pubblicati in Realtime.
do $realtime$
begin
  if exists (select 1 from pg_catalog.pg_publication where pubname = 'supabase_realtime') then
    if not exists (
      select 1 from pg_catalog.pg_publication_tables
      where pubname = 'supabase_realtime' and schemaname = 'public'
        and tablename = 'provider_player_catalog_heads'
    ) then alter publication supabase_realtime add table public.provider_player_catalog_heads; end if;
    if not exists (
      select 1 from pg_catalog.pg_publication_tables
      where pubname = 'supabase_realtime' and schemaname = 'public'
        and tablename = 'provider_player_catalog_reconciliations'
    ) then alter publication supabase_realtime add table public.provider_player_catalog_reconciliations; end if;
    if not exists (
      select 1 from pg_catalog.pg_publication_tables
      where pubname = 'supabase_realtime' and schemaname = 'public'
        and tablename = 'provider_player_catalog_events'
    ) then alter publication supabase_realtime add table public.provider_player_catalog_events; end if;
  end if;
end;
$realtime$;

create or replace function public.get_provider_player_catalog_reconciliation_integrity_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_finish_v7 text := '';
  v_finish_v6 text := '';
  v_guard text := '';
  v_capture text := '';
  v_retry text := '';
  v_prepare text := '';
  v_apply text := '';
  v_event_guard text := '';
  v_member_guard text := '';
  v_active_guard text := '';
  v_role_guard text := '';
begin
  select pg_catalog.pg_get_functiondef('public.finish_provider_sync_run_guarded_v7(uuid,text,integer,text,bigint,uuid)'::regprocedure) into v_finish_v7;
  select pg_catalog.pg_get_functiondef('public.finish_provider_sync_run_guarded_v6(uuid,text,integer,text,bigint,uuid)'::regprocedure) into v_finish_v6;
  select pg_catalog.pg_get_functiondef('public.guard_provider_sync_atomic_completion_v1()'::regprocedure) into v_guard;
  select pg_catalog.pg_get_functiondef('public.capture_provider_recovery_outcome_certificate_v1()'::regprocedure) into v_capture;
  select pg_catalog.pg_get_functiondef('public.provider_recovery_retry_policy_v1(text,integer,text)'::regprocedure) into v_retry;
  select pg_catalog.pg_get_functiondef('public.prepare_provider_player_catalog_reconciliation_v1(uuid,uuid)'::regprocedure) into v_prepare;
  select pg_catalog.pg_get_functiondef('public.apply_provider_player_catalog_on_publication_v1()'::regprocedure) into v_apply;
  select pg_catalog.pg_get_functiondef('public.prevent_provider_player_catalog_event_mutation_v1()'::regprocedure) into v_event_guard;
  select pg_catalog.pg_get_functiondef('public.prevent_provider_player_catalog_member_mutation_v1()'::regprocedure) into v_member_guard;
  select pg_catalog.pg_get_functiondef('public.enforce_provider_player_catalog_active_v1()'::regprocedure) into v_active_guard;
  select pg_catalog.pg_get_functiondef('public.enforce_provider_player_catalog_role_v1()'::regprocedure) into v_role_guard;

  return jsonb_build_object(
    'predecessor_ready',not exists (
      select 1 from jsonb_each(public.get_provider_monotonic_publication_integrity_v1()) check_row
      where jsonb_typeof(check_row.value) is distinct from 'boolean'
         or check_row.value is distinct from 'true'::jsonb
    ),
    'catalog_head_table_ready',to_regclass('public.provider_player_catalog_heads') is not null,
    'reconciliation_table_ready',to_regclass('public.provider_player_catalog_reconciliations') is not null,
    'member_table_ready',to_regclass('public.provider_player_catalog_members') is not null,
    'event_table_ready',to_regclass('public.provider_player_catalog_events') is not null,
    'catalog_columns_ready',not exists (
      select 1 from (values
        ('provider_player_catalog_heads','latest_season'),
        ('provider_player_catalog_heads','generation'),
        ('provider_player_catalog_reconciliations','publication_id'),
        ('provider_player_catalog_reconciliations','season'),
        ('provider_player_catalog_reconciliations','deactivated_player_count'),
        ('provider_player_catalog_reconciliations','removed_role_count'),
        ('provider_player_catalog_members','player_key_fingerprint'),
        ('provider_player_catalog_members','classic_role'),
        ('provider_player_catalog_members','mantra_role'),
        ('provider_player_catalog_events','event_type')
      ) required(table_name,column_name)
      where not exists (
        select 1 from information_schema.columns column_row
        where column_row.table_schema = 'public'
          and column_row.table_name = required.table_name
          and column_row.column_name = required.column_name
      )
    ),
    'catalog_constraints_ready',
      exists (select 1 from pg_catalog.pg_constraint where conrelid = 'public.provider_player_catalog_heads'::regclass and conname = 'provider_player_catalog_heads_season_check')
      and exists (select 1 from pg_catalog.pg_constraint where conrelid = 'public.provider_player_catalog_reconciliations'::regclass and conname = 'provider_player_catalog_reconciliations_terminal_check')
      and exists (select 1 from pg_catalog.pg_constraint where conrelid = 'public.provider_player_catalog_events'::regclass and conname = 'provider_player_catalog_events_type_check')
      and exists (select 1 from pg_catalog.pg_constraint where conrelid = 'public.provider_player_catalog_members'::regclass and conname = 'provider_player_catalog_members_player_key_check'),
    'catalog_indexes_ready',
      to_regclass('public.provider_player_catalog_heads_latest_idx') is not null
      and to_regclass('public.provider_player_catalog_reconciliations_latest_idx') is not null
      and to_regclass('public.provider_player_catalog_members_key_idx') is not null,
    'rls_ready',
      (select relrowsecurity from pg_catalog.pg_class where oid = 'public.provider_player_catalog_heads'::regclass)
      and (select relrowsecurity from pg_catalog.pg_class where oid = 'public.provider_player_catalog_reconciliations'::regclass)
      and (select relrowsecurity from pg_catalog.pg_class where oid = 'public.provider_player_catalog_members'::regclass)
      and (select relrowsecurity from pg_catalog.pg_class where oid = 'public.provider_player_catalog_events'::regclass),
    'authenticated_write_blocked',
      not has_table_privilege('authenticated','public.provider_player_catalog_heads','INSERT')
      and not has_table_privilege('authenticated','public.provider_player_catalog_heads','UPDATE')
      and not has_table_privilege('authenticated','public.provider_player_catalog_heads','DELETE')
      and not has_table_privilege('authenticated','public.provider_player_catalog_reconciliations','INSERT')
      and not has_table_privilege('authenticated','public.provider_player_catalog_reconciliations','UPDATE')
      and not has_table_privilege('authenticated','public.provider_player_catalog_reconciliations','DELETE')
      and not has_table_privilege('authenticated','public.provider_player_catalog_events','INSERT')
      and not has_table_privilege('authenticated','public.provider_player_catalog_events','UPDATE')
      and not has_table_privilege('authenticated','public.provider_player_catalog_events','DELETE')
      and not has_table_privilege('authenticated','public.provider_player_catalog_members','SELECT')
      and not has_table_privilege('authenticated','public.provider_player_catalog_members','INSERT')
      and not has_table_privilege('authenticated','public.provider_player_catalog_members','UPDATE')
      and not has_table_privilege('authenticated','public.provider_player_catalog_members','DELETE'),
    'director_policy_ready',
      exists (select 1 from pg_catalog.pg_policies where schemaname='public' and tablename='provider_player_catalog_heads' and policyname='provider_player_catalog_heads_read_directors')
      and exists (select 1 from pg_catalog.pg_policies where schemaname='public' and tablename='provider_player_catalog_reconciliations' and policyname='provider_player_catalog_reconciliations_read_directors')
      and exists (select 1 from pg_catalog.pg_policies where schemaname='public' and tablename='provider_player_catalog_events' and policyname='provider_player_catalog_events_read_directors'),
    'event_immutability_ready',exists (
      select 1 from pg_catalog.pg_trigger
      where tgrelid = 'public.provider_player_catalog_events'::regclass
        and tgname = 'provider_player_catalog_events_immutable' and tgenabled = 'A' and not tgisinternal
    ) and position('raise exception' in lower(v_event_guard)) > 0,
    'member_immutability_ready',exists (
      select 1 from pg_catalog.pg_trigger
      where tgrelid = 'public.provider_player_catalog_members'::regclass
        and tgname = 'provider_player_catalog_members_immutable' and tgenabled = 'A' and not tgisinternal
    ) and position('raise exception' in lower(v_member_guard)) > 0,
    'head_revision_guard_ready',exists (
      select 1 from pg_catalog.pg_trigger
      where tgrelid = 'public.provider_player_catalog_heads'::regclass
        and tgname = 'provider_player_catalog_heads_touch' and tgenabled = 'A' and not tgisinternal
    ),
    'publication_reconciliation_ready',exists (
      select 1 from pg_catalog.pg_trigger
      where tgrelid = 'public.provider_sync_publications'::regclass
        and tgname = 'provider_player_catalog_publication_reconcile' and tgenabled = 'A' and not tgisinternal
    )
      and to_regprocedure('public.prepare_provider_player_catalog_reconciliation_v1(uuid,uuid)') is not null
      and position('catalog.coverage_drop' in lower(v_prepare)) > 0
      and position('provider_player_catalog_members' in lower(v_prepare)) > 0
      and position('delete from public.athlete_roles' in lower(v_apply)) > 0
      and position('set active = false' in lower(v_apply)) > 0
      and position('delete from public.athletes' in lower(v_apply)) = 0
      and exists (
        select 1 from pg_catalog.pg_trigger
        where tgrelid = 'public.athletes'::regclass
          and tgname = 'provider_player_catalog_active_guard'
          and tgenabled = 'A' and not tgisinternal
      )
      and exists (
        select 1 from pg_catalog.pg_trigger
        where tgrelid = 'public.athlete_roles'::regclass
          and tgname = 'provider_player_catalog_role_guard'
          and tgenabled = 'A' and not tgisinternal
      )
      and position('provider_player_catalog_members' in lower(v_active_guard)) > 0
      and position('return null' in lower(v_role_guard)) > 0
      and position('return old' in lower(v_role_guard)) > 0,
    'decision_discard_ready',
      to_regprocedure('public.provider_player_catalog_decision_v1(uuid,uuid)') is not null
      and to_regprocedure('public.discard_superseded_provider_player_catalog_v1(uuid,integer,bigint,uuid,jsonb)') is not null
      and not has_function_privilege('service_role','public.provider_player_catalog_decision_v1(uuid,uuid)','EXECUTE')
      and not has_function_privilege('service_role','public.discard_superseded_provider_player_catalog_v1(uuid,integer,bigint,uuid,jsonb)','EXECUTE'),
    'finish_v7_ready',
      has_function_privilege('service_role','public.finish_provider_sync_run_guarded_v7(uuid,text,integer,text,bigint,uuid)','EXECUTE')
      and position('provider_player_catalog_decision_v1' in lower(v_finish_v7)) > 0
      and position('prepare_provider_player_catalog_reconciliation_v1' in lower(v_finish_v7)) > 0
      and position('advance_provider_sync_scope_watermark_v1' in lower(v_finish_v7)) > 0
      and position('leghevo.provider_catalog_reconciliation_id' in lower(v_finish_v7)) > 0
      and position('finish_provider_sync_run_guarded_v7' in lower(v_finish_v6)) > 0,
    'completion_recovery_continuity_ready',
      position('watermark.stale_run' in lower(v_guard)) > 0
      and position('catalog.older_season' in lower(v_guard)) > 0
      and position('certify_stale_provider_recovery_outcome_v1' in lower(v_capture)) > 0
      and position('catalog.older_season' in lower(v_capture)) > 0
      and position('catalogo provider rifiutat' in lower(v_retry)) > 0,
    'center_health_ready',
      to_regprocedure('public.get_league_provider_player_catalog_center_v1(uuid)') is not null
      and to_regprocedure('public.get_league_provider_sync_health_v16(uuid)') is not null
      and has_function_privilege('authenticated','public.get_league_provider_sync_health_v16(uuid)','EXECUTE'),
    'realtime_ready',
      exists (select 1 from pg_catalog.pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='provider_player_catalog_heads')
      and exists (select 1 from pg_catalog.pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='provider_player_catalog_reconciliations')
      and exists (select 1 from pg_catalog.pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='provider_player_catalog_events')
      and not exists (select 1 from pg_catalog.pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='provider_player_catalog_members')
  );
end;
$function$;

revoke all on function public.get_provider_player_catalog_reconciliation_integrity_v1() from public,anon,authenticated;
grant execute on function public.get_provider_player_catalog_reconciliation_integrity_v1() to service_role;

-- La migrazione si annulla integralmente se uno dei 20 controlli non è true.
do $validation$
declare
  v_checks jsonb;
  v_failed text;
begin
  v_checks := public.get_provider_player_catalog_reconciliation_integrity_v1();
  select string_agg(check_row.key,', ' order by check_row.key) into v_failed
  from jsonb_each(v_checks) check_row
  where jsonb_typeof(check_row.value) is distinct from 'boolean'
     or check_row.value is distinct from 'true'::jsonb;
  if v_failed is not null then
    raise exception 'Validazione v0.62.17 non superata. Controlli falsi: %',v_failed;
  end if;
end;
$validation$;

commit;

-- DIAGNOSTICA FINALE: devono comparire esattamente 20 valori true.
select
  (checks ->> 'predecessor_ready')::boolean as predecessor_ready,
  (checks ->> 'catalog_head_table_ready')::boolean as catalog_head_table_ready,
  (checks ->> 'reconciliation_table_ready')::boolean as reconciliation_table_ready,
  (checks ->> 'member_table_ready')::boolean as member_table_ready,
  (checks ->> 'event_table_ready')::boolean as event_table_ready,
  (checks ->> 'catalog_columns_ready')::boolean as catalog_columns_ready,
  (checks ->> 'catalog_constraints_ready')::boolean as catalog_constraints_ready,
  (checks ->> 'catalog_indexes_ready')::boolean as catalog_indexes_ready,
  (checks ->> 'rls_ready')::boolean as rls_ready,
  (checks ->> 'authenticated_write_blocked')::boolean as authenticated_write_blocked,
  (checks ->> 'director_policy_ready')::boolean as director_policy_ready,
  (checks ->> 'event_immutability_ready')::boolean as event_immutability_ready,
  (checks ->> 'member_immutability_ready')::boolean as member_immutability_ready,
  (checks ->> 'head_revision_guard_ready')::boolean as head_revision_guard_ready,
  (checks ->> 'publication_reconciliation_ready')::boolean as publication_reconciliation_ready,
  (checks ->> 'decision_discard_ready')::boolean as decision_discard_ready,
  (checks ->> 'finish_v7_ready')::boolean as finish_v7_ready,
  (checks ->> 'completion_recovery_continuity_ready')::boolean as completion_recovery_continuity_ready,
  (checks ->> 'center_health_ready')::boolean as center_health_ready,
  (checks ->> 'realtime_ready')::boolean as realtime_ready
from (select public.get_provider_player_catalog_reconciliation_integrity_v1() as checks) diagnostic;
