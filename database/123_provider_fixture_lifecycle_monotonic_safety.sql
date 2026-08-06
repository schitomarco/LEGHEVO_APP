-- LEGHEVO v0.62.19
-- Ciclo di vita monotono e certificato delle partite provider.
-- Eseguire dopo database/122_provider_fixture_score_reconciliation_safety.sql.
-- Revisione script v4: compatibilità Supabase, continuità certificata v7 -> v8 -> v9 e controllo UPSERT monotono verificato senza spazi.

begin;

-- PRE-FLIGHT: ogni dipendenza viene verificata prima di creare oggetti.
do $preflight$
declare
  v_missing text[] := array[]::text[];
  v_checks jsonb;
begin
  if to_regprocedure('public.get_provider_fixture_score_reconciliation_integrity_v1()') is null then
    v_missing := array_append(v_missing,'function public.get_provider_fixture_score_reconciliation_integrity_v1()');
  else
    v_checks := public.get_provider_fixture_score_reconciliation_integrity_v1();
    if (select count(*) from jsonb_each(v_checks)) <> 20 or exists (
      select 1 from jsonb_each(v_checks) check_row
      where jsonb_typeof(check_row.value) is distinct from 'boolean'
         or check_row.value is distinct from 'true'::jsonb
    ) then
      v_missing := array_append(v_missing,'v0.62.18 integrity: exactly 20 checks must be true');
    end if;
  end if;

  if to_regclass('public.provider_fixtures') is null then
    v_missing := array_append(v_missing,'table public.provider_fixtures');
  end if;
  if to_regclass('public.provider_sync_runs') is null then
    v_missing := array_append(v_missing,'table public.provider_sync_runs');
  end if;
  if to_regclass('public.provider_sync_publications') is null then
    v_missing := array_append(v_missing,'table public.provider_sync_publications');
  end if;
  if to_regclass('public.provider_sync_scope_certificates') is null then
    v_missing := array_append(v_missing,'table public.provider_sync_scope_certificates');
  end if;
  if to_regclass('public.provider_sync_stage_fixtures') is null then
    v_missing := array_append(v_missing,'table public.provider_sync_stage_fixtures');
  end if;
  if to_regclass('public.provider_recovery_requests') is null then
    v_missing := array_append(v_missing,'table public.provider_recovery_requests');
  end if;
  if to_regclass('public.leagues') is null then
    v_missing := array_append(v_missing,'table public.leagues');
  end if;

  if exists (
    select 1
    from (values
      ('provider_fixtures','id'),('provider_fixtures','provider'),
      ('provider_fixtures','provider_fixture_id'),('provider_fixtures','competition_code'),
      ('provider_fixtures','season'),('provider_fixtures','matchday_id'),
      ('provider_fixtures','kickoff_at'),('provider_fixtures','status'),
      ('provider_fixtures','home_team_provider_id'),('provider_fixtures','away_team_provider_id'),
      ('provider_fixtures','home_goals'),('provider_fixtures','away_goals'),
      ('provider_fixtures','updated_at'),
      ('provider_sync_runs','id'),('provider_sync_runs','provider'),
      ('provider_sync_runs','sync_type'),('provider_sync_runs','status'),
      ('provider_sync_runs','requested_for'),('provider_sync_runs','started_at'),
      ('provider_sync_publications','id'),('provider_sync_publications','run_id'),
      ('provider_sync_publications','recovery_request_id'),('provider_sync_publications','league_id'),
      ('provider_sync_publications','status'),('provider_sync_publications','run_revision'),
      ('provider_sync_scope_certificates','publication_id'),('provider_sync_scope_certificates','status'),
      ('provider_sync_scope_certificates','requested_date'),('provider_sync_scope_certificates','observed_fixture_count'),
      ('provider_sync_stage_fixtures','publication_id'),('provider_sync_stage_fixtures','provider'),
      ('provider_sync_stage_fixtures','provider_fixture_id'),('provider_sync_stage_fixtures','competition_code'),
      ('provider_sync_stage_fixtures','season'),('provider_sync_stage_fixtures','matchday_id'),
      ('provider_sync_stage_fixtures','kickoff_at'),('provider_sync_stage_fixtures','status'),
      ('provider_sync_stage_fixtures','home_team_provider_id'),('provider_sync_stage_fixtures','away_team_provider_id'),
      ('provider_sync_stage_fixtures','home_goals'),('provider_sync_stage_fixtures','away_goals')
    ) required(table_name,column_name)
    where not exists (
      select 1 from information_schema.columns column_row
      where column_row.table_schema='public'
        and column_row.table_name=required.table_name
        and column_row.column_name=required.column_name
    )
  ) then
    v_missing := array_append(v_missing,'required columns for provider fixture lifecycle');
  end if;

  if to_regprocedure('gen_random_uuid()') is null then
    v_missing := array_append(v_missing,'function gen_random_uuid()');
  end if;
  if to_regprocedure('pg_catalog.md5(text)') is null then
    v_missing := array_append(v_missing,'function pg_catalog.md5(text)');
  end if;
  if to_regprocedure('pg_catalog.hashtext(text)') is null then
    v_missing := array_append(v_missing,'function pg_catalog.hashtext(text)');
  end if;
  if to_regprocedure('pg_catalog.pg_advisory_xact_lock(bigint)') is null then
    v_missing := array_append(v_missing,'function pg_catalog.pg_advisory_xact_lock(bigint)');
  end if;
  if to_regprocedure('pg_catalog.set_config(text,text,boolean)') is null then
    v_missing := array_append(v_missing,'function pg_catalog.set_config(text,text,boolean)');
  end if;

  if to_regprocedure('public.assert_provider_sync_worker_lease_v1(uuid,uuid)') is null then
    v_missing := array_append(v_missing,'RPC public.assert_provider_sync_worker_lease_v1(uuid,uuid)');
  end if;
  if to_regprocedure('public.provider_sync_scope_watermark_decision_v1(uuid,uuid)') is null then
    v_missing := array_append(v_missing,'RPC public.provider_sync_scope_watermark_decision_v1(uuid,uuid)');
  end if;
  if to_regprocedure('public.discard_stale_provider_sync_publication_v1(uuid,integer,bigint,uuid,jsonb)') is null then
    v_missing := array_append(v_missing,'RPC public.discard_stale_provider_sync_publication_v1(uuid,integer,bigint,uuid,jsonb)');
  end if;
  if to_regprocedure('public.certify_provider_sync_publication_scope_v1(uuid,uuid)') is null then
    v_missing := array_append(v_missing,'RPC public.certify_provider_sync_publication_scope_v1(uuid,uuid)');
  end if;
  if to_regprocedure('public.provider_player_catalog_decision_v1(uuid,uuid)') is null then
    v_missing := array_append(v_missing,'RPC public.provider_player_catalog_decision_v1(uuid,uuid)');
  end if;
  if to_regprocedure('public.discard_superseded_provider_player_catalog_v1(uuid,integer,bigint,uuid,jsonb)') is null then
    v_missing := array_append(v_missing,'RPC public.discard_superseded_provider_player_catalog_v1(uuid,integer,bigint,uuid,jsonb)');
  end if;
  if to_regprocedure('public.prepare_provider_player_catalog_reconciliation_v1(uuid,uuid)') is null then
    v_missing := array_append(v_missing,'RPC public.prepare_provider_player_catalog_reconciliation_v1(uuid,uuid)');
  end if;
  if to_regprocedure('public.prepare_provider_fixture_score_reconciliation_v1(uuid,uuid)') is null then
    v_missing := array_append(v_missing,'RPC public.prepare_provider_fixture_score_reconciliation_v1(uuid,uuid)');
  end if;
  if to_regprocedure('public.finish_provider_sync_run_atomic_core_v1(uuid,text,integer,text,bigint,uuid)') is null then
    v_missing := array_append(v_missing,'RPC public.finish_provider_sync_run_atomic_core_v1(uuid,text,integer,text,bigint,uuid)');
  end if;
  if to_regprocedure('public.advance_provider_sync_scope_watermark_v1(uuid,integer,uuid)') is null then
    v_missing := array_append(v_missing,'RPC public.advance_provider_sync_scope_watermark_v1(uuid,integer,uuid)');
  end if;
  if to_regprocedure('public.get_provider_player_catalog_result_v1(uuid)') is null then
    v_missing := array_append(v_missing,'RPC public.get_provider_player_catalog_result_v1(uuid)');
  end if;
  if to_regprocedure('public.get_provider_fixture_score_result_v1(uuid)') is null then
    v_missing := array_append(v_missing,'RPC public.get_provider_fixture_score_result_v1(uuid)');
  end if;
  if to_regprocedure('public.get_league_provider_sync_health_v17(uuid)') is null then
    v_missing := array_append(v_missing,'RPC public.get_league_provider_sync_health_v17(uuid)');
  end if;
  if to_regprocedure('public.is_league_admin(uuid)') is null then
    v_missing := array_append(v_missing,'function public.is_league_admin(uuid)');
  end if;

  if to_regclass('public.provider_fixtures_provider_provider_fixture_id_key') is null then
    v_missing := array_append(v_missing,'unique constraint public.provider_fixtures(provider,provider_fixture_id)');
  end if;

  if exists (select 1 from public.provider_sync_runs run_row where run_row.status='running') then
    v_missing := array_append(v_missing,'no provider sync run may be running during installation');
  end if;

  if coalesce(array_length(v_missing,1),0)>0 then
    raise exception 'Preflight v0.62.19 non superato. Dipendenze mancanti: %',array_to_string(v_missing,'; ');
  end if;
end;
$preflight$;

create or replace function public.provider_fixture_lifecycle_state_v1(p_status text)
returns text
language sql
immutable
security definer
set search_path=''
as $function$
  select case upper(trim(coalesce(p_status,'')))
    when 'FT' then 'final'
    when 'AET' then 'final'
    when 'PEN' then 'final'
    when '1H' then 'live'
    when 'HT' then 'live'
    when '2H' then 'live'
    when 'ET' then 'live'
    when 'BT' then 'live'
    when 'P' then 'live'
    when 'LIVE' then 'live'
    when 'PST' then 'interrupted'
    when 'SUSP' then 'interrupted'
    when 'INT' then 'interrupted'
    when 'TBD' then 'scheduled'
    when 'CANC' then 'cancelled'
    when 'ABD' then 'cancelled'
    when 'AWD' then 'cancelled'
    when 'WO' then 'cancelled'
    when 'NS' then 'scheduled'
    else 'unknown'
  end;
$function$;
revoke all on function public.provider_fixture_lifecycle_state_v1(text) from public,anon,authenticated;
grant execute on function public.provider_fixture_lifecycle_state_v1(text) to service_role;

create or replace function public.provider_fixture_lifecycle_rank_v1(p_state text)
returns integer
language sql
immutable
security definer
set search_path=''
as $function$
  select case lower(trim(coalesce(p_state,'')))
    when 'scheduled' then 10
    when 'interrupted' then 20
    when 'cancelled' then 30
    when 'live' then 40
    when 'final' then 50
    else 0
  end;
$function$;
revoke all on function public.provider_fixture_lifecycle_rank_v1(text) from public,anon,authenticated;
grant execute on function public.provider_fixture_lifecycle_rank_v1(text) to service_role;

alter table public.provider_fixtures
  add column if not exists provider_lifecycle_state text not null default 'unknown',
  add column if not exists provider_lifecycle_reconciliation_id uuid,
  add column if not exists provider_lifecycle_reconciled_at timestamptz;

update public.provider_fixtures fixture_row
set provider_lifecycle_state=public.provider_fixture_lifecycle_state_v1(fixture_row.status)
where fixture_row.provider_lifecycle_state='unknown';

alter table public.provider_fixtures
  drop constraint if exists provider_fixtures_lifecycle_state_check;
alter table public.provider_fixtures
  add constraint provider_fixtures_lifecycle_state_check
  check (provider_lifecycle_state in ('scheduled','live','interrupted','cancelled','final','unknown'));

create index if not exists provider_fixtures_lifecycle_idx
  on public.provider_fixtures(provider,provider_lifecycle_state,kickoff_at desc);

create table if not exists public.provider_fixture_lifecycle_heads (
  id uuid primary key default gen_random_uuid(),
  provider text not null,
  provider_fixture_id text not null,
  current_state text not null check (current_state in ('scheduled','live','interrupted','cancelled','final')),
  current_status text not null,
  kickoff_at timestamptz not null,
  matchday_id uuid,
  home_team_provider_id text not null,
  away_team_provider_id text not null,
  home_goals smallint,
  away_goals smallint,
  latest_run_id uuid not null references public.provider_sync_runs(id),
  latest_publication_id uuid not null references public.provider_sync_publications(id),
  latest_reconciliation_id uuid not null,
  generation bigint not null default 1 check (generation>0),
  last_transition text not null check (last_transition in ('backfilled','created','advanced','refreshed','final_corrected')),
  summary text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(provider,provider_fixture_id)
);

create table if not exists public.provider_fixture_lifecycle_reconciliations (
  id uuid primary key default gen_random_uuid(),
  publication_id uuid not null unique references public.provider_sync_publications(id) on delete cascade,
  run_id uuid not null unique references public.provider_sync_runs(id) on delete cascade,
  recovery_request_id uuid references public.provider_recovery_requests(id),
  league_id uuid references public.leagues(id),
  provider text not null,
  requested_date date not null,
  status text not null default 'collecting' check (status in ('collecting','applied')),
  observed_fixture_count integer not null default 0 check (observed_fixture_count>=0),
  final_fixture_count integer not null default 0 check (final_fixture_count>=0),
  created_fixture_count integer not null default 0 check (created_fixture_count>=0),
  advanced_fixture_count integer not null default 0 check (advanced_fixture_count>=0),
  final_correction_count integer not null default 0 check (final_correction_count>=0),
  max_generation bigint,
  reason_code text not null default 'fixture.lifecycle_snapshot',
  summary text not null,
  reconciliation_fingerprint text not null check (reconciliation_fingerprint ~ '^[0-9a-f]{32}$'),
  revision bigint not null default 1 check (revision>0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  applied_at timestamptz,
  constraint provider_fixture_lifecycle_reconciliations_terminal_check
    check ((status='collecting' and applied_at is null) or (status='applied' and applied_at is not null))
);

create table if not exists public.provider_fixture_lifecycle_members (
  reconciliation_id uuid not null references public.provider_fixture_lifecycle_reconciliations(id) on delete cascade,
  fixture_key_fingerprint text not null check (fixture_key_fingerprint ~ '^[0-9a-f]{32}$'),
  previous_state text not null,
  candidate_state text not null check (candidate_state in ('scheduled','live','interrupted','cancelled','final')),
  previous_status text,
  candidate_status text not null,
  transition text not null check (transition in ('created','advanced','refreshed','final_corrected')),
  previous_home_goals smallint,
  previous_away_goals smallint,
  candidate_home_goals smallint,
  candidate_away_goals smallint,
  member_fingerprint text not null check (member_fingerprint ~ '^[0-9a-f]{32}$'),
  created_at timestamptz not null default now(),
  primary key(reconciliation_id,fixture_key_fingerprint)
);

create table if not exists public.provider_fixture_lifecycle_events (
  id uuid primary key default gen_random_uuid(),
  reconciliation_id uuid not null references public.provider_fixture_lifecycle_reconciliations(id) on delete cascade,
  league_id uuid references public.leagues(id),
  event_type text not null check (event_type in ('collecting','applied')),
  fixture_count integer not null check (fixture_count>=0),
  final_fixture_count integer not null check (final_fixture_count>=0),
  reason_code text not null,
  event_fingerprint text not null check (event_fingerprint ~ '^[0-9a-f]{32}$'),
  created_at timestamptz not null default now()
);

alter table public.provider_fixtures
  drop constraint if exists provider_fixtures_lifecycle_reconciliation_fk;
alter table public.provider_fixtures
  add constraint provider_fixtures_lifecycle_reconciliation_fk
  foreign key(provider_lifecycle_reconciliation_id)
  references public.provider_fixture_lifecycle_reconciliations(id);

alter table public.provider_fixture_lifecycle_heads
  drop constraint if exists provider_fixture_lifecycle_heads_reconciliation_fk;
alter table public.provider_fixture_lifecycle_heads
  add constraint provider_fixture_lifecycle_heads_reconciliation_fk
  foreign key(latest_reconciliation_id)
  references public.provider_fixture_lifecycle_reconciliations(id);

create index if not exists provider_fixture_lifecycle_heads_latest_idx
  on public.provider_fixture_lifecycle_heads(updated_at desc);
create index if not exists provider_fixture_lifecycle_reconciliations_latest_idx
  on public.provider_fixture_lifecycle_reconciliations(updated_at desc);
create index if not exists provider_fixture_lifecycle_events_latest_idx
  on public.provider_fixture_lifecycle_events(created_at desc);

alter table public.provider_fixture_lifecycle_heads enable row level security;
alter table public.provider_fixture_lifecycle_heads replica identity full;
alter table public.provider_fixture_lifecycle_reconciliations enable row level security;
alter table public.provider_fixture_lifecycle_reconciliations replica identity full;
alter table public.provider_fixture_lifecycle_members enable row level security;
alter table public.provider_fixture_lifecycle_events enable row level security;
alter table public.provider_fixture_lifecycle_events replica identity full;

revoke all on table public.provider_fixture_lifecycle_heads from public,anon,authenticated,service_role;
revoke all on table public.provider_fixture_lifecycle_reconciliations from public,anon,authenticated,service_role;
revoke all on table public.provider_fixture_lifecycle_members from public,anon,authenticated,service_role;
revoke all on table public.provider_fixture_lifecycle_events from public,anon,authenticated,service_role;
grant select on table public.provider_fixture_lifecycle_heads to authenticated,service_role;
grant select on table public.provider_fixture_lifecycle_reconciliations to authenticated,service_role;
grant select on table public.provider_fixture_lifecycle_events to authenticated,service_role;
grant select,insert,update on table public.provider_fixture_lifecycle_heads to service_role;
grant select,insert,update on table public.provider_fixture_lifecycle_reconciliations to service_role;
grant select,insert on table public.provider_fixture_lifecycle_members to service_role;
grant select,insert on table public.provider_fixture_lifecycle_events to service_role;

drop policy if exists provider_fixture_lifecycle_heads_read_directors on public.provider_fixture_lifecycle_heads;
create policy provider_fixture_lifecycle_heads_read_directors
on public.provider_fixture_lifecycle_heads for select to authenticated
using (exists(select 1 from public.leagues league_row where league_row.owner_id=auth.uid() or public.is_league_admin(league_row.id)));

drop policy if exists provider_fixture_lifecycle_reconciliations_read_directors on public.provider_fixture_lifecycle_reconciliations;
create policy provider_fixture_lifecycle_reconciliations_read_directors
on public.provider_fixture_lifecycle_reconciliations for select to authenticated
using (
  (league_id is not null and exists(select 1 from public.leagues league_row where league_row.id=provider_fixture_lifecycle_reconciliations.league_id and (league_row.owner_id=auth.uid() or public.is_league_admin(league_row.id))))
  or (league_id is null and exists(select 1 from public.leagues league_row where league_row.owner_id=auth.uid() or public.is_league_admin(league_row.id)))
);

drop policy if exists provider_fixture_lifecycle_events_read_directors on public.provider_fixture_lifecycle_events;
create policy provider_fixture_lifecycle_events_read_directors
on public.provider_fixture_lifecycle_events for select to authenticated
using (
  (league_id is not null and exists(select 1 from public.leagues league_row where league_row.id=provider_fixture_lifecycle_events.league_id and (league_row.owner_id=auth.uid() or public.is_league_admin(league_row.id))))
  or (league_id is null and exists(select 1 from public.leagues league_row where league_row.owner_id=auth.uid() or public.is_league_admin(league_row.id)))
);

create or replace function public.touch_provider_fixture_lifecycle_reconciliation_v1()
returns trigger language plpgsql security definer set search_path='' as $function$
begin
  if new.status is distinct from old.status
    or new.observed_fixture_count is distinct from old.observed_fixture_count
    or new.final_fixture_count is distinct from old.final_fixture_count
    or new.summary is distinct from old.summary then
    new.revision:=old.revision+1;
    new.updated_at:=now();
  end if;
  if new.status='applied' and old.status<>'applied' then new.applied_at:=now(); end if;
  return new;
end;
$function$;
revoke all on function public.touch_provider_fixture_lifecycle_reconciliation_v1() from public,anon,authenticated;
drop trigger if exists provider_fixture_lifecycle_reconciliations_touch on public.provider_fixture_lifecycle_reconciliations;
create trigger provider_fixture_lifecycle_reconciliations_touch
before update on public.provider_fixture_lifecycle_reconciliations
for each row execute function public.touch_provider_fixture_lifecycle_reconciliation_v1();
alter table public.provider_fixture_lifecycle_reconciliations enable always trigger provider_fixture_lifecycle_reconciliations_touch;

create or replace function public.write_provider_fixture_lifecycle_event_v1()
returns trigger language plpgsql security definer set search_path='' as $function$
begin
  if tg_op='UPDATE' and new.revision=old.revision then return new; end if;
  insert into public.provider_fixture_lifecycle_events(
    reconciliation_id,league_id,event_type,fixture_count,final_fixture_count,
    reason_code,event_fingerprint,created_at
  ) values(
    new.id,new.league_id,new.status,new.observed_fixture_count,new.final_fixture_count,
    new.reason_code,pg_catalog.md5(new.id::text||E'\n'||new.status||E'\n'||new.revision::text||E'\n'||new.observed_fixture_count::text),now()
  );
  return new;
end;
$function$;
revoke all on function public.write_provider_fixture_lifecycle_event_v1() from public,anon,authenticated;
drop trigger if exists provider_fixture_lifecycle_event_writer on public.provider_fixture_lifecycle_reconciliations;
create trigger provider_fixture_lifecycle_event_writer
after insert or update of status on public.provider_fixture_lifecycle_reconciliations
for each row execute function public.write_provider_fixture_lifecycle_event_v1();
alter table public.provider_fixture_lifecycle_reconciliations enable always trigger provider_fixture_lifecycle_event_writer;

create or replace function public.prevent_provider_fixture_lifecycle_event_mutation_v1()
returns trigger language plpgsql security definer set search_path='' as $function$
begin
  raise exception 'Storico ciclo vita partite provider immutabile.';
end;
$function$;
revoke all on function public.prevent_provider_fixture_lifecycle_event_mutation_v1() from public,anon,authenticated;
drop trigger if exists provider_fixture_lifecycle_events_immutable on public.provider_fixture_lifecycle_events;
create trigger provider_fixture_lifecycle_events_immutable
before update or delete on public.provider_fixture_lifecycle_events
for each row execute function public.prevent_provider_fixture_lifecycle_event_mutation_v1();
alter table public.provider_fixture_lifecycle_events enable always trigger provider_fixture_lifecycle_events_immutable;

drop trigger if exists provider_fixture_lifecycle_members_immutable on public.provider_fixture_lifecycle_members;
create trigger provider_fixture_lifecycle_members_immutable
before update or delete on public.provider_fixture_lifecycle_members
for each row execute function public.prevent_provider_fixture_lifecycle_event_mutation_v1();
alter table public.provider_fixture_lifecycle_members enable always trigger provider_fixture_lifecycle_members_immutable;

-- Le teste vengono create al primo run certificato. Le righe storiche restano intatte.

create or replace function public.prepare_provider_fixture_lifecycle_reconciliation_v1(p_run_id uuid,p_lease_token uuid)
returns jsonb language plpgsql security definer set search_path='' as $function$
declare
  v_run public.provider_sync_runs%rowtype;
  v_publication public.provider_sync_publications%rowtype;
  v_scope public.provider_sync_scope_certificates%rowtype;
  v_reconciliation public.provider_fixture_lifecycle_reconciliations%rowtype;
  v_fixture_count integer:=0;
  v_final_count integer:=0;
  v_member_count integer:=0;
  v_invalid integer:=0;
begin
  perform public.assert_provider_sync_worker_lease_v1(p_run_id,p_lease_token);
  select run_row.* into v_run from public.provider_sync_runs run_row where run_row.id=p_run_id for update;
  if not found then raise exception 'Partite provider non valide [fixture.run_missing].'; end if;
  if v_run.sync_type<>'sync-fixtures' then return jsonb_build_object('fixtureLifecycleReconciliation',false); end if;
  if v_run.status<>'running' then raise exception 'Partite provider non valide [fixture.run_not_running].'; end if;

  select publication_row.* into v_publication from public.provider_sync_publications publication_row
  where publication_row.run_id=p_run_id for update;
  if not found or v_publication.status<>'collecting' then
    raise exception 'Partite provider non valide [fixture.publication_not_collecting].';
  end if;
  select scope_row.* into v_scope from public.provider_sync_scope_certificates scope_row
  where scope_row.publication_id=v_publication.id for update;
  if not found or v_scope.status<>'certified' or v_scope.requested_date is null then
    raise exception 'Partite provider non valide [fixture.scope_not_certified].';
  end if;

  select count(*)::integer,
    count(*) filter(where public.provider_fixture_lifecycle_state_v1(stage_row.status)='final')::integer
  into v_fixture_count,v_final_count
  from public.provider_sync_stage_fixtures stage_row
  where stage_row.publication_id=v_publication.id;
  if v_fixture_count<>v_scope.observed_fixture_count then
    raise exception 'Partite provider non valide [fixture.count_mismatch].';
  end if;

  select count(*)::integer into v_invalid
  from public.provider_sync_stage_fixtures stage_row
  left join public.provider_fixtures fixture_row
    on fixture_row.provider=stage_row.provider and fixture_row.provider_fixture_id=stage_row.provider_fixture_id
  left join public.provider_fixture_lifecycle_heads head_row
    on head_row.provider=stage_row.provider and head_row.provider_fixture_id=stage_row.provider_fixture_id
  where stage_row.publication_id=v_publication.id and (
    public.provider_fixture_lifecycle_state_v1(stage_row.status)='unknown'
    or (public.provider_fixture_lifecycle_state_v1(stage_row.status)='final' and (stage_row.home_goals is null or stage_row.away_goals is null))
    or (coalesce(head_row.current_state,fixture_row.provider_lifecycle_state,public.provider_fixture_lifecycle_state_v1(fixture_row.status))='final' and public.provider_fixture_lifecycle_state_v1(stage_row.status)<>'final')
    or (coalesce(head_row.current_state,fixture_row.provider_lifecycle_state,public.provider_fixture_lifecycle_state_v1(fixture_row.status))='live' and public.provider_fixture_lifecycle_state_v1(stage_row.status)='scheduled')
    or (coalesce(head_row.current_state,fixture_row.provider_lifecycle_state,public.provider_fixture_lifecycle_state_v1(fixture_row.status))='final' and fixture_row.id is not null and (fixture_row.home_team_provider_id is distinct from stage_row.home_team_provider_id or fixture_row.away_team_provider_id is distinct from stage_row.away_team_provider_id))
    or (coalesce(head_row.current_state,fixture_row.provider_lifecycle_state,public.provider_fixture_lifecycle_state_v1(fixture_row.status))='final' and fixture_row.id is not null and (fixture_row.matchday_id is distinct from stage_row.matchday_id or (fixture_row.kickoff_at at time zone 'UTC')::date is distinct from (stage_row.kickoff_at at time zone 'UTC')::date))
  );
  if v_invalid>0 then
    raise exception 'Partite provider non valide [fixture.lifecycle_regression]: % transizioni non consentite.',v_invalid;
  end if;

  insert into public.provider_fixture_lifecycle_reconciliations(
    publication_id,run_id,recovery_request_id,league_id,provider,requested_date,
    status,observed_fixture_count,final_fixture_count,summary,reconciliation_fingerprint
  ) values(
    v_publication.id,v_run.id,v_publication.recovery_request_id,v_publication.league_id,
    v_run.provider,v_scope.requested_date,'collecting',v_fixture_count,v_final_count,
    format('Fotografia ciclo vita partite pronta: %s partite, %s finali.',v_fixture_count,v_final_count),
    pg_catalog.md5(v_publication.id::text||E'\n'||v_run.id::text||E'\n'||v_run.provider||E'\n'||v_scope.requested_date::text||E'\n'||v_fixture_count::text)
  ) on conflict(publication_id) do nothing;

  select reconciliation_row.* into v_reconciliation
  from public.provider_fixture_lifecycle_reconciliations reconciliation_row
  where reconciliation_row.publication_id=v_publication.id for update;
  if v_reconciliation.status='applied' then
    return jsonb_build_object('fixtureLifecycleReconciliation',true,'fixtureLifecycleStatus','applied','fixtureLifecycleReconciliationId',v_reconciliation.id);
  end if;

  insert into public.provider_fixture_lifecycle_members(
    reconciliation_id,fixture_key_fingerprint,previous_state,candidate_state,
    previous_status,candidate_status,transition,previous_home_goals,previous_away_goals,
    candidate_home_goals,candidate_away_goals,member_fingerprint
  )
  select v_reconciliation.id,
    pg_catalog.md5(stage_row.provider||E'\n'||stage_row.provider_fixture_id),
    coalesce(head_row.current_state,fixture_row.provider_lifecycle_state,public.provider_fixture_lifecycle_state_v1(fixture_row.status),'none'),
    public.provider_fixture_lifecycle_state_v1(stage_row.status),
    coalesce(head_row.current_status,fixture_row.status),stage_row.status,
    case
      when fixture_row.id is null and head_row.id is null then 'created'
      when coalesce(head_row.current_state,fixture_row.provider_lifecycle_state,public.provider_fixture_lifecycle_state_v1(fixture_row.status))='final'
        and public.provider_fixture_lifecycle_state_v1(stage_row.status)='final'
        and (coalesce(head_row.current_status,fixture_row.status) is distinct from stage_row.status
          or coalesce(head_row.home_goals,fixture_row.home_goals) is distinct from stage_row.home_goals
          or coalesce(head_row.away_goals,fixture_row.away_goals) is distinct from stage_row.away_goals) then 'final_corrected'
      when public.provider_fixture_lifecycle_rank_v1(public.provider_fixture_lifecycle_state_v1(stage_row.status))>
        public.provider_fixture_lifecycle_rank_v1(coalesce(head_row.current_state,fixture_row.provider_lifecycle_state,public.provider_fixture_lifecycle_state_v1(fixture_row.status))) then 'advanced'
      else 'refreshed'
    end,
    coalesce(head_row.home_goals,fixture_row.home_goals),coalesce(head_row.away_goals,fixture_row.away_goals),
    stage_row.home_goals,stage_row.away_goals,
    pg_catalog.md5(v_reconciliation.id::text||E'\n'||stage_row.provider||E'\n'||stage_row.provider_fixture_id||E'\n'||stage_row.status||E'\n'||coalesce(stage_row.home_goals::text,'')||E'\n'||coalesce(stage_row.away_goals::text,''))
  from public.provider_sync_stage_fixtures stage_row
  left join public.provider_fixtures fixture_row
    on fixture_row.provider=stage_row.provider and fixture_row.provider_fixture_id=stage_row.provider_fixture_id
  left join public.provider_fixture_lifecycle_heads head_row
    on head_row.provider=stage_row.provider and head_row.provider_fixture_id=stage_row.provider_fixture_id
  where stage_row.publication_id=v_publication.id
  on conflict(reconciliation_id,fixture_key_fingerprint) do nothing;

  select count(*)::integer into v_member_count from public.provider_fixture_lifecycle_members member_row
  where member_row.reconciliation_id=v_reconciliation.id;
  if v_member_count<>v_fixture_count then
    raise exception 'Partite provider non valide [fixture.member_count_mismatch].';
  end if;

  return jsonb_build_object(
    'fixtureLifecycleReconciliation',true,'fixtureLifecycleStatus','collecting',
    'fixtureLifecycleReconciliationId',v_reconciliation.id,'fixtureLifecycleFixtureCount',v_fixture_count,
    'fixtureLifecycleFinalCount',v_final_count
  );
end;
$function$;
revoke all on function public.prepare_provider_fixture_lifecycle_reconciliation_v1(uuid,uuid) from public,anon,authenticated,service_role;

create or replace function public.enforce_provider_fixture_lifecycle_v1()
returns trigger language plpgsql security definer set search_path='' as $function$
declare
  v_provider text;
  v_reconciliation_id uuid;
  v_reconciliation public.provider_fixture_lifecycle_reconciliations%rowtype;
  v_candidate_state text;
  v_previous_state text;
  v_transition text;
  v_fixture_fingerprint text;
begin
  if tg_op='DELETE' then
    if old.provider='api-football' then raise exception 'Partite provider non valide [fixture.physical_delete_disabled].'; end if;
    return old;
  end if;
  v_provider:=new.provider;
  if v_provider<>'api-football' then return new; end if;

  v_reconciliation_id:=nullif(current_setting('leghevo.provider_fixture_lifecycle_reconciliation_id',true),'')::uuid;
  if v_reconciliation_id is null then raise exception 'Partite provider non valide [fixture.lifecycle_required].'; end if;
  select reconciliation_row.* into v_reconciliation
  from public.provider_fixture_lifecycle_reconciliations reconciliation_row
  join public.provider_sync_publications publication_row on publication_row.id=reconciliation_row.publication_id
  where reconciliation_row.id=v_reconciliation_id and reconciliation_row.status='collecting'
    and publication_row.status='collecting' and reconciliation_row.provider=new.provider;
  if not found then raise exception 'Partite provider non valide [fixture.reconciliation_not_collecting].'; end if;

  v_fixture_fingerprint:=pg_catalog.md5(new.provider||E'\n'||new.provider_fixture_id);
  select member_row.transition into v_transition
  from public.provider_fixture_lifecycle_members member_row
  where member_row.reconciliation_id=v_reconciliation.id and member_row.fixture_key_fingerprint=v_fixture_fingerprint;
  if not found then raise exception 'Partite provider non valide [fixture.member_missing].'; end if;

  v_candidate_state:=public.provider_fixture_lifecycle_state_v1(new.status);
  if v_candidate_state='unknown' then raise exception 'Partite provider non valide [fixture.status_unknown].'; end if;
  if v_candidate_state='final' and (new.home_goals is null or new.away_goals is null) then
    raise exception 'Partite provider non valide [fixture.final_goals_missing].';
  end if;

  if tg_op='UPDATE' then
    v_previous_state:=coalesce(old.provider_lifecycle_state,public.provider_fixture_lifecycle_state_v1(old.status));
    if v_previous_state='final' and v_candidate_state<>'final' then
      raise exception 'Partite provider non valide [fixture.final_regression].';
    end if;
    if v_previous_state='live' and v_candidate_state='scheduled' then
      raise exception 'Partite provider non valide [fixture.live_regression].';
    end if;
    if v_previous_state='final' and (old.home_team_provider_id is distinct from new.home_team_provider_id or old.away_team_provider_id is distinct from new.away_team_provider_id) then
      raise exception 'Partite provider non valide [fixture.final_team_identity_change].';
    end if;
    if v_previous_state='final' and (old.matchday_id is distinct from new.matchday_id or (old.kickoff_at at time zone 'UTC')::date is distinct from (new.kickoff_at at time zone 'UTC')::date) then
      raise exception 'Partite provider non valide [fixture.final_schedule_regression].';
    end if;
  end if;

  new.provider_lifecycle_state:=v_candidate_state;
  new.provider_lifecycle_reconciliation_id:=v_reconciliation.id;
  new.provider_lifecycle_reconciled_at:=now();

  -- In un UPSERT PostgreSQL esegue prima il trigger INSERT e poi quello UPDATE.
  -- La testa viene avanzata una sola volta dal ramo UPDATE in caso di conflitto.
  if tg_op='INSERT' and exists (
    select 1 from public.provider_fixtures fixture_row
    where fixture_row.provider=new.provider
      and fixture_row.provider_fixture_id=new.provider_fixture_id
  ) then
    return new;
  end if;

  insert into public.provider_fixture_lifecycle_heads(
    provider,provider_fixture_id,current_state,current_status,kickoff_at,matchday_id,
    home_team_provider_id,away_team_provider_id,home_goals,away_goals,
    latest_run_id,latest_publication_id,latest_reconciliation_id,generation,last_transition,summary
  ) values(
    new.provider,new.provider_fixture_id,v_candidate_state,new.status,new.kickoff_at,new.matchday_id,
    new.home_team_provider_id,new.away_team_provider_id,new.home_goals,new.away_goals,
    v_reconciliation.run_id,v_reconciliation.publication_id,v_reconciliation.id,1,v_transition,
    format('Ciclo vita partita provider certificato: %s (%s).',v_candidate_state,new.status)
  ) on conflict(provider,provider_fixture_id) do update set
    current_state=excluded.current_state,current_status=excluded.current_status,
    kickoff_at=excluded.kickoff_at,matchday_id=excluded.matchday_id,
    home_team_provider_id=excluded.home_team_provider_id,away_team_provider_id=excluded.away_team_provider_id,
    home_goals=excluded.home_goals,away_goals=excluded.away_goals,
    latest_run_id=excluded.latest_run_id,latest_publication_id=excluded.latest_publication_id,
    latest_reconciliation_id=excluded.latest_reconciliation_id,
    generation=public.provider_fixture_lifecycle_heads.generation+1,
    last_transition=excluded.last_transition,summary=excluded.summary,updated_at=now();
  return new;
end;
$function$;
revoke all on function public.enforce_provider_fixture_lifecycle_v1() from public,anon,authenticated;
drop trigger if exists provider_fixture_lifecycle_guard on public.provider_fixtures;
create trigger provider_fixture_lifecycle_guard
before insert or update or delete on public.provider_fixtures
for each row execute function public.enforce_provider_fixture_lifecycle_v1();
alter table public.provider_fixtures enable always trigger provider_fixture_lifecycle_guard;

create or replace function public.apply_provider_fixture_lifecycle_on_publication_v1()
returns trigger language plpgsql security definer set search_path='' as $function$
declare
  v_reconciliation public.provider_fixture_lifecycle_reconciliations%rowtype;
  v_created integer:=0;
  v_advanced integer:=0;
  v_corrected integer:=0;
  v_max_generation bigint:=null;
begin
  if new.status<>'published' or new.status is not distinct from old.status then return new; end if;
  select reconciliation_row.* into v_reconciliation
  from public.provider_fixture_lifecycle_reconciliations reconciliation_row
  where reconciliation_row.publication_id=new.id and reconciliation_row.status='collecting' for update;
  if not found then return new; end if;

  select count(*) filter(where transition='created')::integer,
    count(*) filter(where transition='advanced')::integer,
    count(*) filter(where transition='final_corrected')::integer
  into v_created,v_advanced,v_corrected
  from public.provider_fixture_lifecycle_members member_row
  where member_row.reconciliation_id=v_reconciliation.id;
  select max(head_row.generation) into v_max_generation
  from public.provider_fixture_lifecycle_heads head_row
  where head_row.latest_reconciliation_id=v_reconciliation.id;

  update public.provider_fixture_lifecycle_reconciliations reconciliation_row
  set status='applied',created_fixture_count=v_created,advanced_fixture_count=v_advanced,
      final_correction_count=v_corrected,max_generation=v_max_generation,
      summary=format('Ciclo vita partite applicato: %s osservate, %s create, %s avanzate, %s correzioni finali.',v_reconciliation.observed_fixture_count,v_created,v_advanced,v_corrected)
  where reconciliation_row.id=v_reconciliation.id;
  return new;
end;
$function$;
revoke all on function public.apply_provider_fixture_lifecycle_on_publication_v1() from public,anon,authenticated;
drop trigger if exists provider_fixture_lifecycle_publication_reconcile on public.provider_sync_publications;
create trigger provider_fixture_lifecycle_publication_reconcile
after update of status on public.provider_sync_publications
for each row execute function public.apply_provider_fixture_lifecycle_on_publication_v1();
alter table public.provider_sync_publications enable always trigger provider_fixture_lifecycle_publication_reconcile;

create or replace function public.get_provider_fixture_lifecycle_result_v1(p_run_id uuid)
returns jsonb language sql stable security definer set search_path='' as $function$
  select coalesce((select jsonb_build_object(
    'fixtureLifecycleReconciliation',true,'fixtureLifecycleStatus',reconciliation_row.status,
    'fixtureLifecycleReconciliationId',reconciliation_row.id,
    'fixtureLifecycleFixtureCount',reconciliation_row.observed_fixture_count,
    'fixtureLifecycleFinalCount',reconciliation_row.final_fixture_count,
    'fixtureLifecycleCreatedCount',reconciliation_row.created_fixture_count,
    'fixtureLifecycleAdvancedCount',reconciliation_row.advanced_fixture_count,
    'fixtureLifecycleFinalCorrectionCount',reconciliation_row.final_correction_count,
    'fixtureLifecycleMaxGeneration',reconciliation_row.max_generation
  ) from public.provider_fixture_lifecycle_reconciliations reconciliation_row where reconciliation_row.run_id=p_run_id),jsonb_build_object('fixtureLifecycleReconciliation',false));
$function$;
revoke all on function public.get_provider_fixture_lifecycle_result_v1(uuid) from public,anon,authenticated,service_role;

create or replace function public.provider_recovery_retry_policy_v1(p_error_summary text,p_retry_no integer,p_sync_type text)
returns jsonb language plpgsql immutable security definer set search_path='' as $function$
declare
  v_message text:=lower(trim(coalesce(p_error_summary,'')));
  v_retry_no integer:=greatest(coalesce(p_retry_no,1),1);
  v_sync_type text:=lower(trim(coalesce(p_sync_type,'')));
  v_max_retries integer:=3;
  v_failure_class text:='unknown';
  v_retryable boolean:=true;
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
    or v_message like '%voti provider non validi%'
    or v_message like '%riconciliazione voti provider rifiutat%'
    or v_message like '%score.%'
    or v_message like '%partite provider non valide%'
    or v_message like '%fixture.%'
    or v_message like '%prima sincronizza il calendario%'
    or v_message like '%unauthorized%' or v_message like '%forbidden%' or v_message like '% 401%' or v_message like '% 403%' then
    v_retryable:=false;
    v_failure_class:=case when v_message like '%chiave%' or v_message like '%unauthorized%' or v_message like '%forbidden%' or v_message like '% 401%' or v_message like '% 403%' then 'configuration' else 'request' end;
  elsif v_message like '%429%' or v_message like '%rate limit%' or v_message like '%too many requests%' then v_failure_class:='rate_limit';
  elsif v_message like '%watchdog%' or v_message like '%timeout%' or v_message like '%timed out%' or v_message like '%senza aggiornamenti%' then v_failure_class:='timeout';
  elsif v_message like '%network%' or v_message like '%fetch failed%' or v_message like '%connessione%' or v_message like '%dns%' or v_message like '%temporarily unavailable%' then v_failure_class:='network';
  elsif v_message like '%500%' or v_message like '%502%' or v_message like '%503%' or v_message like '%504%' or v_message like '%provider%' then v_failure_class:='provider';
  end if;
  if v_retry_no>v_max_retries then v_retryable:=false; end if;
  v_delay_seconds:=case v_failure_class
    when 'rate_limit' then case v_retry_no when 1 then 120 when 2 then 600 else 1800 end
    when 'timeout' then case v_retry_no when 1 then 60 when 2 then 300 else 900 end
    when 'network' then case v_retry_no when 1 then 60 when 2 then 300 else 900 end
    when 'provider' then case v_retry_no when 1 then 120 when 2 then 600 else 1800 end
    when 'configuration' then 0 when 'request' then 0
    else case v_retry_no when 1 then 180 when 2 then 900 else 3600 end end;
  if v_retryable and v_sync_type='sync-season-players' then v_delay_seconds:=greatest(v_delay_seconds,300); end if;
  return jsonb_build_object('retryable',v_retryable,'failureClass',v_failure_class,'retryNo',v_retry_no,'maxRetries',v_max_retries,'delaySeconds',v_delay_seconds);
end;
$function$;
revoke all on function public.provider_recovery_retry_policy_v1(text,integer,text) from public,anon,authenticated;
grant execute on function public.provider_recovery_retry_policy_v1(text,integer,text) to service_role;

create or replace function public.finish_provider_sync_run_guarded_v9(
  p_run_id uuid,p_status text,p_records_processed integer,p_error_message text default null,
  p_expected_revision bigint default null,p_lease_token uuid default null
)
returns jsonb language plpgsql security definer set search_path='' as $function$
declare
  v_status text:=lower(trim(coalesce(p_status,'')));
  v_decision jsonb:='{}'::jsonb;
  v_scope jsonb:='{}'::jsonb;
  v_catalog_decision jsonb:='{}'::jsonb;
  v_catalog_prepare jsonb:='{}'::jsonb;
  v_catalog_result jsonb:='{}'::jsonb;
  v_fixture_prepare jsonb:='{}'::jsonb;
  v_fixture_result jsonb:='{}'::jsonb;
  v_score_prepare jsonb:='{}'::jsonb;
  v_score_result jsonb:='{}'::jsonb;
  v_result jsonb;
  v_watermark jsonb:='{}'::jsonb;
  v_sync_type text;
begin
  if v_status not in ('completed','failed') then raise exception 'Stato finale del run provider non valido.'; end if;
  if v_status='failed' then
    v_result:=public.finish_provider_sync_run_atomic_core_v1(p_run_id,p_status,p_records_processed,p_error_message,p_expected_revision,p_lease_token);
    return v_result||jsonb_build_object('monotonicPublication',true,'publicationSuperseded',false,'catalogReconciliation',false,'catalogSuperseded',false,'fixtureLifecycleReconciliation',false,'fixtureScoreReconciliation',false);
  end if;

  select run_row.sync_type into v_sync_type from public.provider_sync_runs run_row where run_row.id=p_run_id;
  if not found then raise exception 'Run provider non trovato durante la chiusura v9.'; end if;
  v_decision:=public.provider_sync_scope_watermark_decision_v1(p_run_id,p_lease_token);
  if coalesce((v_decision->>'stale')::boolean,false) then
    return public.discard_stale_provider_sync_publication_v1(p_run_id,p_records_processed,p_expected_revision,p_lease_token,v_decision)
      ||jsonb_build_object('catalogReconciliation',false,'catalogSuperseded',false,'fixtureLifecycleReconciliation',false,'fixtureScoreReconciliation',false);
  end if;
  v_scope:=public.certify_provider_sync_publication_scope_v1(p_run_id,p_lease_token);

  if v_sync_type='sync-season-players' then
    v_catalog_decision:=public.provider_player_catalog_decision_v1(p_run_id,p_lease_token);
    if coalesce((v_catalog_decision->>'superseded')::boolean,false) then
      return public.discard_superseded_provider_player_catalog_v1(p_run_id,p_records_processed,p_expected_revision,p_lease_token,v_catalog_decision)
        ||jsonb_build_object('fixtureLifecycleReconciliation',false,'fixtureScoreReconciliation',false);
    end if;
    v_catalog_prepare:=public.prepare_provider_player_catalog_reconciliation_v1(p_run_id,p_lease_token);
    perform pg_catalog.set_config('leghevo.provider_catalog_reconciliation_id',v_catalog_prepare->>'catalogReconciliationId',true);
  elsif v_sync_type='sync-fixtures' then
    v_fixture_prepare:=public.prepare_provider_fixture_lifecycle_reconciliation_v1(p_run_id,p_lease_token);
    perform pg_catalog.set_config('leghevo.provider_fixture_lifecycle_reconciliation_id',v_fixture_prepare->>'fixtureLifecycleReconciliationId',true);
  elsif v_sync_type='sync-fixture-players' then
    v_score_prepare:=public.prepare_provider_fixture_score_reconciliation_v1(p_run_id,p_lease_token);
    perform pg_catalog.set_config('leghevo.provider_fixture_score_reconciliation_id',v_score_prepare->>'fixtureScoreReconciliationId',true);
  end if;

  v_result:=public.finish_provider_sync_run_atomic_core_v1(p_run_id,p_status,p_records_processed,p_error_message,p_expected_revision,p_lease_token);
  perform pg_catalog.set_config('leghevo.provider_catalog_reconciliation_id','',true);
  perform pg_catalog.set_config('leghevo.provider_fixture_lifecycle_reconciliation_id','',true);
  perform pg_catalog.set_config('leghevo.provider_fixture_score_reconciliation_id','',true);
  v_watermark:=public.advance_provider_sync_scope_watermark_v1(p_run_id,p_records_processed,p_lease_token);
  v_catalog_result:=public.get_provider_player_catalog_result_v1(p_run_id);
  v_fixture_result:=public.get_provider_fixture_lifecycle_result_v1(p_run_id);
  v_score_result:=public.get_provider_fixture_score_result_v1(p_run_id);
  return v_result||v_scope||v_watermark||v_catalog_prepare||v_catalog_result||v_fixture_prepare||v_fixture_result||v_score_prepare||v_score_result
    ||jsonb_build_object('semanticScopeBinding',true,'monotonicPublication',true,'publicationSuperseded',false);
end;
$function$;
revoke all on function public.finish_provider_sync_run_guarded_v9(uuid,text,integer,text,bigint,uuid) from public,anon,authenticated;
grant execute on function public.finish_provider_sync_run_guarded_v9(uuid,text,integer,text,bigint,uuid) to service_role;

create or replace function public.finish_provider_sync_run_guarded_v8(
  p_run_id uuid,p_status text,p_records_processed integer,p_error_message text default null,
  p_expected_revision bigint default null,p_lease_token uuid default null
)
returns jsonb language plpgsql security definer set search_path='' as $function$
begin
  -- Continuità della firma v8: tutte le protezioni pregresse e il nuovo ciclo
  -- partita sono certificate nel corpo completo della v9.
  return public.finish_provider_sync_run_guarded_v9(p_run_id,p_status,p_records_processed,p_error_message,p_expected_revision,p_lease_token);
end;
$function$;
revoke all on function public.finish_provider_sync_run_guarded_v8(uuid,text,integer,text,bigint,uuid) from public,anon,authenticated;
grant execute on function public.finish_provider_sync_run_guarded_v8(uuid,text,integer,text,bigint,uuid) to service_role;

create or replace function public.get_league_provider_fixture_lifecycle_center_v1(p_league_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $function$
declare
  v_owner_id uuid;
  v_collecting integer:=0;
  v_applied integer:=0;
  v_created integer:=0;
  v_advanced integer:=0;
  v_corrected integer:=0;
  v_total integer:=0;
  v_latest_at timestamptz;
  v_latest jsonb;
  v_head jsonb;
begin
  if auth.uid() is null then raise exception 'Devi effettuare l''accesso.'; end if;
  select league_row.owner_id into v_owner_id from public.leagues league_row where league_row.id=p_league_id;
  if not found then raise exception 'Lega non trovata per il controllo del ciclo vita partite provider.'; end if;
  if v_owner_id<>auth.uid() and not public.is_league_admin(p_league_id) then
    raise exception 'Solo Presidente e Admin possono leggere il ciclo vita partite provider.';
  end if;

  select count(*) filter(where status='collecting')::integer,
    count(*) filter(where status='applied' and applied_at>=now()-interval '24 hours')::integer,
    coalesce(sum(created_fixture_count) filter(where status='applied' and applied_at>=now()-interval '24 hours'),0)::integer,
    coalesce(sum(advanced_fixture_count) filter(where status='applied' and applied_at>=now()-interval '24 hours'),0)::integer,
    coalesce(sum(final_correction_count) filter(where status='applied' and applied_at>=now()-interval '24 hours'),0)::integer,
    count(*)::integer,max(applied_at)
  into v_collecting,v_applied,v_created,v_advanced,v_corrected,v_total,v_latest_at
  from public.provider_fixture_lifecycle_reconciliations reconciliation_row
  where reconciliation_row.league_id=p_league_id or reconciliation_row.league_id is null;

  select jsonb_build_object(
    'id',reconciliation_row.id,'runId',reconciliation_row.run_id,
    'publicationId',reconciliation_row.publication_id,'requestId',reconciliation_row.recovery_request_id,
    'requestedDate',reconciliation_row.requested_date,'status',reconciliation_row.status,
    'observedFixtureCount',reconciliation_row.observed_fixture_count,
    'finalFixtureCount',reconciliation_row.final_fixture_count,
    'createdFixtureCount',reconciliation_row.created_fixture_count,
    'advancedFixtureCount',reconciliation_row.advanced_fixture_count,
    'finalCorrectionCount',reconciliation_row.final_correction_count,
    'maxGeneration',reconciliation_row.max_generation,
    'reasonCode',reconciliation_row.reason_code,'summary',reconciliation_row.summary,
    'updatedAt',reconciliation_row.updated_at
  ) into v_latest
  from public.provider_fixture_lifecycle_reconciliations reconciliation_row
  where reconciliation_row.league_id=p_league_id or reconciliation_row.league_id is null
  order by reconciliation_row.updated_at desc limit 1;

  select jsonb_build_object(
    'id',head_row.id,'fixtureIdFingerprint',pg_catalog.md5(head_row.provider||E'\n'||head_row.provider_fixture_id),
    'currentState',head_row.current_state,'currentStatus',head_row.current_status,
    'generation',head_row.generation,'lastTransition',head_row.last_transition,
    'summary',head_row.summary,'updatedAt',head_row.updated_at
  ) into v_head
  from public.provider_fixture_lifecycle_heads head_row
  order by head_row.updated_at desc limit 1;

  return jsonb_build_object(
    'protected',true,'healthy',v_collecting=0,
    'monotonicFixtureLifecycleActive',true,'finalToNonFinalRegressionBlocked',true,
    'finalGoalsPreserved',true,'finalTeamIdentityLocked',true,'physicalFixtureDeletionDisabled',true,
    'collectingCount',v_collecting,'appliedLast24h',v_applied,
    'createdFixturesLast24h',v_created,'advancedFixturesLast24h',v_advanced,
    'finalCorrectionsLast24h',v_corrected,'totalReconciliationCount',v_total,
    'latestReconciliationAt',v_latest_at,'head',v_head,'latest',v_latest
  );
end;
$function$;
revoke all on function public.get_league_provider_fixture_lifecycle_center_v1(uuid) from public,anon,service_role;
grant execute on function public.get_league_provider_fixture_lifecycle_center_v1(uuid) to authenticated;

create or replace function public.get_league_provider_sync_health_v18(p_league_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $function$
declare
  v_base jsonb;
  v_lifecycle jsonb;
  v_healthy boolean;
  v_status text;
begin
  v_base:=public.get_league_provider_sync_health_v17(p_league_id);
  v_lifecycle:=public.get_league_provider_fixture_lifecycle_center_v1(p_league_id);
  v_healthy:=coalesce((v_base->>'healthy')::boolean,false) and coalesce((v_lifecycle->>'healthy')::boolean,false);
  v_status:=case when not v_healthy then 'attention' else coalesce(v_base->>'status','idle') end;
  return v_base||jsonb_build_object(
    'protected',coalesce((v_base->>'protected')::boolean,false) and coalesce((v_lifecycle->>'protected')::boolean,false),
    'healthy',v_healthy,'status',v_status,'fixtureLifecycleReconciliation',v_lifecycle
  );
end;
$function$;
revoke all on function public.get_league_provider_sync_health_v18(uuid) from public,anon,service_role;
grant execute on function public.get_league_provider_sync_health_v18(uuid) to authenticated;

do $realtime$
begin
  if exists(select 1 from pg_catalog.pg_publication where pubname='supabase_realtime') then
    if not exists(select 1 from pg_catalog.pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='provider_fixture_lifecycle_heads') then
      alter publication supabase_realtime add table public.provider_fixture_lifecycle_heads;
    end if;
    if not exists(select 1 from pg_catalog.pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='provider_fixture_lifecycle_reconciliations') then
      alter publication supabase_realtime add table public.provider_fixture_lifecycle_reconciliations;
    end if;
    if not exists(select 1 from pg_catalog.pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='provider_fixture_lifecycle_events') then
      alter publication supabase_realtime add table public.provider_fixture_lifecycle_events;
    end if;
  end if;
end;
$realtime$;

create or replace function public.get_provider_fixture_lifecycle_integrity_v1()
returns jsonb language plpgsql stable security definer set search_path='' as $function$
declare
  v_predecessor jsonb;
  v_mapper text;
  v_prepare text;
  v_guard text;
  v_apply text;
  v_finish_v9 text;
  v_finish_v8 text;
  v_finish_v7 text;
  v_retry text;
begin
  v_predecessor:=public.get_provider_fixture_score_reconciliation_integrity_v1();
  select pg_catalog.pg_get_functiondef('public.provider_fixture_lifecycle_state_v1(text)'::regprocedure) into v_mapper;
  select pg_catalog.pg_get_functiondef('public.prepare_provider_fixture_lifecycle_reconciliation_v1(uuid,uuid)'::regprocedure) into v_prepare;
  select pg_catalog.pg_get_functiondef('public.enforce_provider_fixture_lifecycle_v1()'::regprocedure) into v_guard;
  select pg_catalog.pg_get_functiondef('public.apply_provider_fixture_lifecycle_on_publication_v1()'::regprocedure) into v_apply;
  select pg_catalog.pg_get_functiondef('public.finish_provider_sync_run_guarded_v9(uuid,text,integer,text,bigint,uuid)'::regprocedure) into v_finish_v9;
  select pg_catalog.pg_get_functiondef('public.finish_provider_sync_run_guarded_v8(uuid,text,integer,text,bigint,uuid)'::regprocedure) into v_finish_v8;
  select pg_catalog.pg_get_functiondef('public.finish_provider_sync_run_guarded_v7(uuid,text,integer,text,bigint,uuid)'::regprocedure) into v_finish_v7;
  select pg_catalog.pg_get_functiondef('public.provider_recovery_retry_policy_v1(text,integer,text)'::regprocedure) into v_retry;
  return jsonb_build_object(
    'predecessor_ready',
      (select count(*) from jsonb_each(v_predecessor)) = 20
      and not exists (
        select 1
        from jsonb_each(v_predecessor) predecessor_check
        where predecessor_check.key not in ('predecessor_ready','finish_v8_ready')
          and (
            jsonb_typeof(predecessor_check.value) is distinct from 'boolean'
            or predecessor_check.value is distinct from 'true'::jsonb
          )
      )
      and jsonb_typeof(v_predecessor -> 'predecessor_ready') = 'boolean'
      and (v_predecessor -> 'predecessor_ready') = 'false'::jsonb
      and jsonb_typeof(v_predecessor -> 'finish_v8_ready') = 'boolean'
      and (v_predecessor -> 'finish_v8_ready') = 'false'::jsonb
      and position('finish_provider_sync_run_guarded_v8' in lower(v_finish_v7)) > 0
      and position('finish_provider_sync_run_guarded_v9' in lower(v_finish_v8)) > 0
      and position('provider_sync_scope_watermark_decision_v1' in lower(v_finish_v9)) > 0
      and position('certify_provider_sync_publication_scope_v1' in lower(v_finish_v9)) > 0
      and position('provider_player_catalog_decision_v1' in lower(v_finish_v9)) > 0
      and position('prepare_provider_player_catalog_reconciliation_v1' in lower(v_finish_v9)) > 0
      and position('prepare_provider_fixture_score_reconciliation_v1' in lower(v_finish_v9)) > 0
      and position('prepare_provider_fixture_lifecycle_reconciliation_v1' in lower(v_finish_v9)) > 0
      and position('finish_provider_sync_run_atomic_core_v1' in lower(v_finish_v9)) > 0
      and position('advance_provider_sync_scope_watermark_v1' in lower(v_finish_v9)) > 0
      and position('leghevo.provider_catalog_reconciliation_id' in lower(v_finish_v9)) > 0
      and position('leghevo.provider_fixture_score_reconciliation_id' in lower(v_finish_v9)) > 0
      and position('leghevo.provider_fixture_lifecycle_reconciliation_id' in lower(v_finish_v9)) > 0,
    'fixture_columns_ready',not exists(select 1 from (values('provider_lifecycle_state'),('provider_lifecycle_reconciliation_id'),('provider_lifecycle_reconciled_at')) c(column_name) where not exists(select 1 from information_schema.columns x where x.table_schema='public' and x.table_name='provider_fixtures' and x.column_name=c.column_name)),
    'head_table_ready',to_regclass('public.provider_fixture_lifecycle_heads') is not null,
    'reconciliation_table_ready',to_regclass('public.provider_fixture_lifecycle_reconciliations') is not null,
    'member_table_ready',to_regclass('public.provider_fixture_lifecycle_members') is not null,
    'event_table_ready',to_regclass('public.provider_fixture_lifecycle_events') is not null,
    'constraints_ready',exists(select 1 from pg_catalog.pg_constraint where conrelid='public.provider_fixtures'::regclass and conname='provider_fixtures_lifecycle_state_check') and exists(select 1 from pg_catalog.pg_constraint where conrelid='public.provider_fixture_lifecycle_reconciliations'::regclass and conname='provider_fixture_lifecycle_reconciliations_terminal_check'),
    'indexes_ready',to_regclass('public.provider_fixtures_lifecycle_idx') is not null and to_regclass('public.provider_fixture_lifecycle_heads_latest_idx') is not null and to_regclass('public.provider_fixture_lifecycle_reconciliations_latest_idx') is not null,
    'rls_ready',(select relrowsecurity from pg_catalog.pg_class where oid='public.provider_fixture_lifecycle_heads'::regclass) and (select relrowsecurity from pg_catalog.pg_class where oid='public.provider_fixture_lifecycle_reconciliations'::regclass) and (select relrowsecurity from pg_catalog.pg_class where oid='public.provider_fixture_lifecycle_members'::regclass) and (select relrowsecurity from pg_catalog.pg_class where oid='public.provider_fixture_lifecycle_events'::regclass),
    'authenticated_write_blocked',not has_table_privilege('authenticated','public.provider_fixture_lifecycle_heads','INSERT') and not has_table_privilege('authenticated','public.provider_fixture_lifecycle_reconciliations','UPDATE') and not has_table_privilege('authenticated','public.provider_fixture_lifecycle_members','SELECT') and not has_table_privilege('authenticated','public.provider_fixture_lifecycle_events','DELETE'),
    'immutable_history_ready',exists(select 1 from pg_catalog.pg_trigger where tgrelid='public.provider_fixture_lifecycle_events'::regclass and tgname='provider_fixture_lifecycle_events_immutable' and tgenabled='A' and not tgisinternal) and exists(select 1 from pg_catalog.pg_trigger where tgrelid='public.provider_fixture_lifecycle_members'::regclass and tgname='provider_fixture_lifecycle_members_immutable' and tgenabled='A' and not tgisinternal),
    'lifecycle_mapper_ready',position('when ''ft''' in lower(v_mapper))>0 and position('then ''final''' in lower(v_mapper))>0 and position('when ''pst''' in lower(v_mapper))>0 and position('then ''interrupted''' in lower(v_mapper))>0,
    'reconciliation_prepare_ready',position('fixture.lifecycle_regression' in lower(v_prepare))>0 and position('fixture.member_count_mismatch' in lower(v_prepare))>0,
    'write_guard_ready',exists(select 1 from pg_catalog.pg_trigger where tgrelid='public.provider_fixtures'::regclass and tgname='provider_fixture_lifecycle_guard' and tgenabled='A' and not tgisinternal) and position('fixture.final_regression' in lower(v_guard))>0 and position('fixture.physical_delete_disabled' in lower(v_guard))>0,
    'head_monotonic_ready',
      position('onconflict(provider,provider_fixture_id)doupdate' in pg_catalog.regexp_replace(lower(v_guard),'[[:space:]]+','','g'))>0
      and position('generation=public.provider_fixture_lifecycle_heads.generation+1' in pg_catalog.regexp_replace(lower(v_guard),'[[:space:]]+','','g'))>0
      and position('final_corrected' in lower(v_prepare))>0,
    'publication_trigger_ready',exists(select 1 from pg_catalog.pg_trigger where tgrelid='public.provider_sync_publications'::regclass and tgname='provider_fixture_lifecycle_publication_reconcile' and tgenabled='A' and not tgisinternal) and position('status=''applied''' in replace(lower(v_apply),' ',''))>0,
    'finish_v9_ready',has_function_privilege('service_role','public.finish_provider_sync_run_guarded_v9(uuid,text,integer,text,bigint,uuid)','EXECUTE') and position('prepare_provider_fixture_lifecycle_reconciliation_v1' in lower(v_finish_v9))>0 and position('finish_provider_sync_run_guarded_v9' in lower(v_finish_v8))>0,
    'retry_policy_ready',position('partite provider non valide' in lower(v_retry))>0 and position('fixture.%' in lower(v_retry))>0,
    'center_health_ready',to_regprocedure('public.get_league_provider_fixture_lifecycle_center_v1(uuid)') is not null and to_regprocedure('public.get_league_provider_sync_health_v18(uuid)') is not null and has_function_privilege('authenticated','public.get_league_provider_sync_health_v18(uuid)','EXECUTE'),
    'realtime_ready',exists(select 1 from pg_catalog.pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='provider_fixture_lifecycle_heads') and exists(select 1 from pg_catalog.pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='provider_fixture_lifecycle_reconciliations') and exists(select 1 from pg_catalog.pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='provider_fixture_lifecycle_events') and not exists(select 1 from pg_catalog.pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='provider_fixture_lifecycle_members')
  );
end;
$function$;
revoke all on function public.get_provider_fixture_lifecycle_integrity_v1() from public,anon,authenticated;
grant execute on function public.get_provider_fixture_lifecycle_integrity_v1() to service_role;

do $validation$
declare
  v_checks jsonb;
  v_failed text;
begin
  v_checks:=public.get_provider_fixture_lifecycle_integrity_v1();
  select string_agg(check_row.key,', ' order by check_row.key) into v_failed
  from jsonb_each(v_checks) check_row
  where jsonb_typeof(check_row.value) is distinct from 'boolean' or check_row.value is distinct from 'true'::jsonb;
  if (select count(*) from jsonb_each(v_checks))<>20 then
    raise exception 'Validazione v0.62.19 non superata: attesi 20 controlli, trovati %.',
      (select count(*) from jsonb_each(v_checks));
  end if;
  if v_failed is not null then raise exception 'Validazione v0.62.19 non superata. Controlli falsi: %',v_failed; end if;
end;
$validation$;

commit;

-- DIAGNOSTICA FINALE: devono comparire esattamente 20 valori true.
select
  (checks->>'predecessor_ready')::boolean as predecessor_ready,
  (checks->>'fixture_columns_ready')::boolean as fixture_columns_ready,
  (checks->>'head_table_ready')::boolean as head_table_ready,
  (checks->>'reconciliation_table_ready')::boolean as reconciliation_table_ready,
  (checks->>'member_table_ready')::boolean as member_table_ready,
  (checks->>'event_table_ready')::boolean as event_table_ready,
  (checks->>'constraints_ready')::boolean as constraints_ready,
  (checks->>'indexes_ready')::boolean as indexes_ready,
  (checks->>'rls_ready')::boolean as rls_ready,
  (checks->>'authenticated_write_blocked')::boolean as authenticated_write_blocked,
  (checks->>'immutable_history_ready')::boolean as immutable_history_ready,
  (checks->>'lifecycle_mapper_ready')::boolean as lifecycle_mapper_ready,
  (checks->>'reconciliation_prepare_ready')::boolean as reconciliation_prepare_ready,
  (checks->>'write_guard_ready')::boolean as write_guard_ready,
  (checks->>'head_monotonic_ready')::boolean as head_monotonic_ready,
  (checks->>'publication_trigger_ready')::boolean as publication_trigger_ready,
  (checks->>'finish_v9_ready')::boolean as finish_v9_ready,
  (checks->>'retry_policy_ready')::boolean as retry_policy_ready,
  (checks->>'center_health_ready')::boolean as center_health_ready,
  (checks->>'realtime_ready')::boolean as realtime_ready
from (select public.get_provider_fixture_lifecycle_integrity_v1() as checks) diagnostic;
