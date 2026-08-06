-- LEGHEVO v0.62.22
-- Impatto causale certificato sui risultati ufficiali provider.
-- Eseguire dopo database/125_provider_score_consumption_gate_safety.sql.
-- I risultati ufficiali non vengono modificati automaticamente: la migrazione
-- certifica esattamente se la proiezione ufficiale usa ancora gli stessi input
-- delle risoluzioni correnti protette dal gate provider.

begin;

-- PRE-FLIGHT: dipendenze reali e firme complete.
do $preflight$
declare
  v_missing text[] := array[]::text[];
  v_checks jsonb;
begin
  if to_regprocedure('public.get_provider_score_consumption_gate_integrity_v1()') is null then
    v_missing := array_append(v_missing,'function public.get_provider_score_consumption_gate_integrity_v1()');
  else
    v_checks := public.get_provider_score_consumption_gate_integrity_v1();
    if (select count(*) from jsonb_each(v_checks)) <> 20
      or exists(
        select 1 from jsonb_each(v_checks) check_row
        where jsonb_typeof(check_row.value) is distinct from 'boolean'
           or check_row.value is distinct from 'true'::jsonb
      ) then
      v_missing := array_append(v_missing,'v0.62.21 integrity: all 20 checks must be true');
    end if;
  end if;

  if to_regclass('public.leagues') is null then v_missing:=array_append(v_missing,'table public.leagues'); end if;
  if to_regclass('public.matchdays') is null then v_missing:=array_append(v_missing,'table public.matchdays'); end if;
  if to_regclass('public.fantasy_fixtures') is null then v_missing:=array_append(v_missing,'table public.fantasy_fixtures'); end if;
  if to_regclass('public.live_fixture_projection_runs') is null then v_missing:=array_append(v_missing,'table public.live_fixture_projection_runs'); end if;
  if to_regclass('public.lineup_resolution_runs') is null then v_missing:=array_append(v_missing,'table public.lineup_resolution_runs'); end if;
  if to_regclass('public.matchday_officialization_runs') is null then v_missing:=array_append(v_missing,'table public.matchday_officialization_runs'); end if;
  if to_regclass('public.provider_score_consumption_gate_events') is null then v_missing:=array_append(v_missing,'table public.provider_score_consumption_gate_events'); end if;
  if to_regclass('public.provider_sync_runs') is null then v_missing:=array_append(v_missing,'table public.provider_sync_runs'); end if;

  if exists(
    select 1
    from (values
      ('leagues','id'),('leagues','owner_id'),
      ('matchdays','id'),
      ('fantasy_fixtures','id'),('fantasy_fixtures','league_id'),('fantasy_fixtures','matchday_id'),
      ('fantasy_fixtures','home_team_id'),('fantasy_fixtures','away_team_id'),
      ('fantasy_fixtures','official_projection_id'),('fantasy_fixtures','officialization_run_id'),
      ('fantasy_fixtures','result_revision'),('fantasy_fixtures','finalized_at'),
      ('live_fixture_projection_runs','id'),('live_fixture_projection_runs','fixture_id'),
      ('live_fixture_projection_runs','home_resolution_id'),('live_fixture_projection_runs','away_resolution_id'),
      ('lineup_resolution_runs','id'),('lineup_resolution_runs','input_hash'),
      ('provider_score_consumption_gate_events','id'),('provider_score_consumption_gate_events','matchday_id'),
      ('provider_sync_runs','status')
    ) required(table_name,column_name)
    where not exists(
      select 1 from information_schema.columns column_row
      where column_row.table_schema='public'
        and column_row.table_name=required.table_name
        and column_row.column_name=required.column_name
    )
  ) then
    v_missing:=array_append(v_missing,'required columns for official result impact certification');
  end if;

  if to_regprocedure('public.lineup_resolution_input_hash_v1(uuid,uuid)') is null then
    v_missing:=array_append(v_missing,'function public.lineup_resolution_input_hash_v1(uuid,uuid)');
  end if;
  if to_regprocedure('public.get_league_provider_sync_health_v20(uuid)') is null then
    v_missing:=array_append(v_missing,'RPC public.get_league_provider_sync_health_v20(uuid)');
  end if;
  if to_regprocedure('public.is_league_admin(uuid)') is null then
    v_missing:=array_append(v_missing,'function public.is_league_admin(uuid)');
  end if;
  if to_regprocedure('public.reopen_league_fixture_guarded_v1(uuid,uuid,text,uuid)') is null then
    v_missing:=array_append(v_missing,'RPC public.reopen_league_fixture_guarded_v1(uuid,uuid,text,uuid)');
  end if;

  if exists(select 1 from public.provider_sync_runs run_row where run_row.status='running') then
    v_missing:=array_append(v_missing,'no provider sync run may be running during installation');
  end if;

  if coalesce(array_length(v_missing,1),0)>0 then
    raise exception 'Preflight v0.62.22 non superato. Dipendenze mancanti: %',array_to_string(v_missing,'; ');
  end if;
end;
$preflight$;

create table if not exists public.provider_official_result_impact_heads (
  id uuid primary key default gen_random_uuid(),
  league_id uuid not null references public.leagues(id) on delete cascade,
  matchday_id uuid not null references public.matchdays(id) on delete cascade,
  fixture_id uuid not null unique references public.fantasy_fixtures(id) on delete cascade,
  official_projection_id bigint references public.live_fixture_projection_runs(id) on delete restrict,
  officialization_run_id bigint references public.matchday_officialization_runs(id) on delete set null,
  fixture_result_revision integer not null default 0,
  impact_status text not null,
  reason_code text not null,
  assessment_generation bigint not null default 1,
  affected_side_count smallint not null default 0,
  official_home_input_hash text,
  official_away_input_hash text,
  current_home_input_hash text,
  current_away_input_hash text,
  risk_fingerprint text not null,
  first_affected_at timestamptz,
  last_assessed_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint provider_official_result_impact_heads_status_check
    check(impact_status in ('clear','affected','in_correction')),
  constraint provider_official_result_impact_heads_reason_check
    check(length(trim(reason_code)) between 1 and 120 and reason_code !~ E'[\r\n]'),
  constraint provider_official_result_impact_heads_generation_check
    check(assessment_generation>=1),
  constraint provider_official_result_impact_heads_sides_check
    check(affected_side_count between 0 and 2),
  constraint provider_official_result_impact_heads_revision_check
    check(fixture_result_revision>=0),
  constraint provider_official_result_impact_heads_hashes_check
    check(
      (official_home_input_hash is null or length(official_home_input_hash)=32)
      and (official_away_input_hash is null or length(official_away_input_hash)=32)
      and (current_home_input_hash is null or length(current_home_input_hash)=32)
      and (current_away_input_hash is null or length(current_away_input_hash)=32)
      and length(risk_fingerprint)=32
    )
);

create index if not exists provider_official_result_impact_heads_league_idx
  on public.provider_official_result_impact_heads(league_id,impact_status,updated_at desc);
create index if not exists provider_official_result_impact_heads_matchday_idx
  on public.provider_official_result_impact_heads(matchday_id,impact_status);

create table if not exists public.provider_official_result_impact_events (
  id uuid primary key default gen_random_uuid(),
  head_id uuid not null references public.provider_official_result_impact_heads(id) on delete restrict,
  league_id uuid not null references public.leagues(id) on delete cascade,
  matchday_id uuid not null references public.matchdays(id) on delete cascade,
  fixture_id uuid not null references public.fantasy_fixtures(id) on delete cascade,
  official_projection_id bigint references public.live_fixture_projection_runs(id) on delete restrict,
  impact_status text not null,
  reason_code text not null,
  assessment_generation bigint not null,
  affected_side_count smallint not null,
  risk_fingerprint text not null,
  event_fingerprint text not null unique,
  created_at timestamptz not null default now(),
  constraint provider_official_result_impact_events_status_check
    check(impact_status in ('clear','affected','in_correction')),
  constraint provider_official_result_impact_events_reason_check
    check(length(trim(reason_code)) between 1 and 120 and reason_code !~ E'[\r\n]'),
  constraint provider_official_result_impact_events_generation_check
    check(assessment_generation>=1),
  constraint provider_official_result_impact_events_sides_check
    check(affected_side_count between 0 and 2),
  constraint provider_official_result_impact_events_hashes_check
    check(length(risk_fingerprint)=32 and length(event_fingerprint)=32),
  unique(head_id,assessment_generation)
);

create index if not exists provider_official_result_impact_events_league_idx
  on public.provider_official_result_impact_events(league_id,created_at desc);
create index if not exists provider_official_result_impact_events_matchday_idx
  on public.provider_official_result_impact_events(matchday_id,created_at desc);

alter table public.provider_official_result_impact_heads enable row level security;
alter table public.provider_official_result_impact_events enable row level security;
alter table public.provider_official_result_impact_events replica identity full;

revoke all on table public.provider_official_result_impact_heads from public,anon,authenticated,service_role;
revoke all on table public.provider_official_result_impact_events from public,anon,authenticated,service_role;
grant select on table public.provider_official_result_impact_heads to authenticated;
grant select on table public.provider_official_result_impact_events to authenticated;
grant select,insert,update on table public.provider_official_result_impact_heads to service_role;
grant select,insert on table public.provider_official_result_impact_events to service_role;

drop policy if exists provider_official_result_impact_heads_director_select
on public.provider_official_result_impact_heads;
create policy provider_official_result_impact_heads_director_select
on public.provider_official_result_impact_heads
for select to authenticated
using(
  exists(select 1 from public.leagues league_row
    where league_row.id=league_id
      and (league_row.owner_id=auth.uid() or public.is_league_admin(league_id)))
);

drop policy if exists provider_official_result_impact_events_director_select
on public.provider_official_result_impact_events;
create policy provider_official_result_impact_events_director_select
on public.provider_official_result_impact_events
for select to authenticated
using(
  exists(select 1 from public.leagues league_row
    where league_row.id=league_id
      and (league_row.owner_id=auth.uid() or public.is_league_admin(league_id)))
);

create or replace function public.prevent_provider_official_result_impact_head_mutation_v1()
returns trigger
language plpgsql
security definer
set search_path=''
as $function$
begin
  if coalesce(current_setting('leghevo.provider_official_result_impact_context',true),'')='on' then
    if tg_op='DELETE' then return old; end if;
    return new;
  end if;
  raise exception 'Testa impatto risultato provider certificata: modifica diretta non consentita.';
end;
$function$;
revoke all on function public.prevent_provider_official_result_impact_head_mutation_v1() from public,anon,authenticated;

drop trigger if exists provider_official_result_impact_heads_guard
on public.provider_official_result_impact_heads;
create trigger provider_official_result_impact_heads_guard
before insert or update or delete on public.provider_official_result_impact_heads
for each row execute function public.prevent_provider_official_result_impact_head_mutation_v1();
alter table public.provider_official_result_impact_heads enable always trigger provider_official_result_impact_heads_guard;

create or replace function public.prevent_provider_official_result_impact_event_mutation_v1()
returns trigger
language plpgsql
security definer
set search_path=''
as $function$
begin
  raise exception 'Storico impatto risultato provider immutabile.';
end;
$function$;
revoke all on function public.prevent_provider_official_result_impact_event_mutation_v1() from public,anon,authenticated;

drop trigger if exists provider_official_result_impact_events_immutable
on public.provider_official_result_impact_events;
create trigger provider_official_result_impact_events_immutable
before update or delete on public.provider_official_result_impact_events
for each row execute function public.prevent_provider_official_result_impact_event_mutation_v1();
alter table public.provider_official_result_impact_events enable always trigger provider_official_result_impact_events_immutable;

create or replace function public.compute_provider_official_result_impact_v1(p_fixture_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $function$
declare
  v_fixture record;
  v_current_home_hash text;
  v_current_away_hash text;
  v_home_changed boolean:=false;
  v_away_changed boolean:=false;
  v_status text;
  v_reason text;
  v_sides smallint:=0;
  v_risk text;
begin
  select
    fixture.id,fixture.league_id,fixture.matchday_id,fixture.home_team_id,fixture.away_team_id,
    fixture.official_projection_id,fixture.officialization_run_id,fixture.result_revision,fixture.finalized_at,
    projection.home_resolution_id,projection.away_resolution_id,
    home_resolution.input_hash as official_home_input_hash,
    away_resolution.input_hash as official_away_input_hash
  into v_fixture
  from public.fantasy_fixtures fixture
  left join public.live_fixture_projection_runs projection on projection.id=fixture.official_projection_id
  left join public.lineup_resolution_runs home_resolution on home_resolution.id=projection.home_resolution_id
  left join public.lineup_resolution_runs away_resolution on away_resolution.id=projection.away_resolution_id
  where fixture.id=p_fixture_id;

  if not found then
    return jsonb_build_object('available',false,'reasonCode','impact.fixture_not_found');
  end if;

  if v_fixture.finalized_at is null then
    v_status:='in_correction';
    v_reason:='impact.fixture_reopened';
  elsif v_fixture.official_projection_id is null
     or v_fixture.home_resolution_id is null
     or v_fixture.away_resolution_id is null
     or v_fixture.official_home_input_hash is null
     or v_fixture.official_away_input_hash is null then
    v_status:='affected';
    v_reason:='impact.official_lineage_missing';
    v_sides:=2;
  else
    v_current_home_hash:=public.lineup_resolution_input_hash_v1(v_fixture.home_team_id,v_fixture.matchday_id);
    v_current_away_hash:=public.lineup_resolution_input_hash_v1(v_fixture.away_team_id,v_fixture.matchday_id);
    v_home_changed:=v_current_home_hash is distinct from v_fixture.official_home_input_hash;
    v_away_changed:=v_current_away_hash is distinct from v_fixture.official_away_input_hash;
    v_sides:=(case when v_home_changed then 1 else 0 end + case when v_away_changed then 1 else 0 end)::smallint;
    if v_sides=0 then
      v_status:='clear';
      v_reason:='impact.official_inputs_current';
    elsif v_home_changed and v_away_changed then
      v_status:='affected';
      v_reason:='impact.both_resolution_inputs_changed';
    elsif v_home_changed then
      v_status:='affected';
      v_reason:='impact.home_resolution_input_changed';
    else
      v_status:='affected';
      v_reason:='impact.away_resolution_input_changed';
    end if;
  end if;

  v_risk:=md5(jsonb_build_object(
    'fixtureId',v_fixture.id,'officialProjectionId',v_fixture.official_projection_id,
    'officializationRunId',v_fixture.officialization_run_id,'resultRevision',v_fixture.result_revision,
    'status',v_status,'reason',v_reason,
    'officialHomeInputHash',v_fixture.official_home_input_hash,
    'officialAwayInputHash',v_fixture.official_away_input_hash,
    'currentHomeInputHash',v_current_home_hash,'currentAwayInputHash',v_current_away_hash
  )::text);

  return jsonb_build_object(
    'available',true,'fixtureId',v_fixture.id,'leagueId',v_fixture.league_id,
    'matchdayId',v_fixture.matchday_id,'officialProjectionId',v_fixture.official_projection_id,
    'officializationRunId',v_fixture.officialization_run_id,
    'fixtureResultRevision',v_fixture.result_revision,'impactStatus',v_status,
    'reasonCode',v_reason,'affectedSideCount',v_sides,
    'officialHomeInputHash',v_fixture.official_home_input_hash,
    'officialAwayInputHash',v_fixture.official_away_input_hash,
    'currentHomeInputHash',v_current_home_hash,'currentAwayInputHash',v_current_away_hash,
    'riskFingerprint',v_risk
  );
end;
$function$;
revoke all on function public.compute_provider_official_result_impact_v1(uuid) from public,anon,authenticated;
grant execute on function public.compute_provider_official_result_impact_v1(uuid) to service_role;

create or replace function public.reconcile_provider_official_result_impact_v1(p_matchday_id uuid)
returns integer
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_fixture_id uuid;
  v_assessment jsonb;
  v_existing public.provider_official_result_impact_heads%rowtype;
  v_head public.provider_official_result_impact_heads%rowtype;
  v_generation bigint;
  v_changed boolean;
  v_count integer:=0;
begin
  if p_matchday_id is null then return 0; end if;
  perform set_config('leghevo.provider_official_result_impact_context','on',true);

  for v_fixture_id in
    select fixture.id
    from public.fantasy_fixtures fixture
    where fixture.matchday_id=p_matchday_id
      and (fixture.finalized_at is not null or exists(
        select 1 from public.provider_official_result_impact_heads head where head.fixture_id=fixture.id
      ))
    order by fixture.id
  loop
    v_assessment:=public.compute_provider_official_result_impact_v1(v_fixture_id);
    if coalesce((v_assessment->>'available')::boolean,false)=false then continue; end if;

    select * into v_existing
    from public.provider_official_result_impact_heads head
    where head.fixture_id=v_fixture_id
    for update;

    v_changed:=not found or v_existing.risk_fingerprint is distinct from v_assessment->>'riskFingerprint';
    v_generation:=case when v_existing.id is null then 1 when v_changed then v_existing.assessment_generation+1 else v_existing.assessment_generation end;

    insert into public.provider_official_result_impact_heads(
      league_id,matchday_id,fixture_id,official_projection_id,officialization_run_id,
      fixture_result_revision,impact_status,reason_code,assessment_generation,affected_side_count,
      official_home_input_hash,official_away_input_hash,current_home_input_hash,current_away_input_hash,
      risk_fingerprint,first_affected_at,last_assessed_at,updated_at
    ) values(
      (v_assessment->>'leagueId')::uuid,(v_assessment->>'matchdayId')::uuid,v_fixture_id,
      nullif(v_assessment->>'officialProjectionId','')::bigint,
      nullif(v_assessment->>'officializationRunId','')::bigint,
      coalesce((v_assessment->>'fixtureResultRevision')::integer,0),v_assessment->>'impactStatus',
      v_assessment->>'reasonCode',v_generation,coalesce((v_assessment->>'affectedSideCount')::smallint,0),
      nullif(v_assessment->>'officialHomeInputHash',''),nullif(v_assessment->>'officialAwayInputHash',''),
      nullif(v_assessment->>'currentHomeInputHash',''),nullif(v_assessment->>'currentAwayInputHash',''),
      v_assessment->>'riskFingerprint',
      case when v_assessment->>'impactStatus'='affected' then now() else null end,
      now(),now()
    )
    on conflict(fixture_id) do update set
      league_id=excluded.league_id,matchday_id=excluded.matchday_id,
      official_projection_id=excluded.official_projection_id,
      officialization_run_id=excluded.officialization_run_id,
      fixture_result_revision=excluded.fixture_result_revision,
      impact_status=excluded.impact_status,reason_code=excluded.reason_code,
      assessment_generation=excluded.assessment_generation,
      affected_side_count=excluded.affected_side_count,
      official_home_input_hash=excluded.official_home_input_hash,
      official_away_input_hash=excluded.official_away_input_hash,
      current_home_input_hash=excluded.current_home_input_hash,
      current_away_input_hash=excluded.current_away_input_hash,
      risk_fingerprint=excluded.risk_fingerprint,
      first_affected_at=case
        when public.provider_official_result_impact_heads.first_affected_at is not null
          then public.provider_official_result_impact_heads.first_affected_at
        when excluded.impact_status='affected' then now() else null end,
      last_assessed_at=now(),updated_at=case when v_changed then now() else public.provider_official_result_impact_heads.updated_at end
    returning * into v_head;

    if v_changed then
      insert into public.provider_official_result_impact_events(
        head_id,league_id,matchday_id,fixture_id,official_projection_id,
        impact_status,reason_code,assessment_generation,affected_side_count,
        risk_fingerprint,event_fingerprint,created_at
      ) values(
        v_head.id,v_head.league_id,v_head.matchday_id,v_head.fixture_id,v_head.official_projection_id,
        v_head.impact_status,v_head.reason_code,v_head.assessment_generation,v_head.affected_side_count,
        v_head.risk_fingerprint,
        md5(v_head.id::text||E'\n'||v_head.assessment_generation::text||E'\n'||v_head.risk_fingerprint),now()
      ) on conflict(event_fingerprint) do nothing;
    end if;
    v_count:=v_count+1;
  end loop;
  perform set_config('leghevo.provider_official_result_impact_context','',true);
  return v_count;
end;
$function$;
revoke all on function public.reconcile_provider_official_result_impact_v1(uuid) from public,anon,authenticated;
grant execute on function public.reconcile_provider_official_result_impact_v1(uuid) to service_role;

create or replace function public.reconcile_provider_official_result_impact_from_gate_v1()
returns trigger
language plpgsql
security definer
set search_path=''
as $function$
begin
  perform public.reconcile_provider_official_result_impact_v1(new.matchday_id);
  return new;
end;
$function$;
revoke all on function public.reconcile_provider_official_result_impact_from_gate_v1() from public,anon,authenticated;

drop trigger if exists provider_official_result_impact_gate_writer
on public.provider_score_consumption_gate_events;
create trigger provider_official_result_impact_gate_writer
after insert on public.provider_score_consumption_gate_events
for each row execute function public.reconcile_provider_official_result_impact_from_gate_v1();
alter table public.provider_score_consumption_gate_events enable always trigger provider_official_result_impact_gate_writer;

create or replace function public.reconcile_provider_official_result_impact_from_fixture_v1()
returns trigger
language plpgsql
security definer
set search_path=''
as $function$
begin
  perform public.reconcile_provider_official_result_impact_v1(new.matchday_id);
  return new;
end;
$function$;
revoke all on function public.reconcile_provider_official_result_impact_from_fixture_v1() from public,anon,authenticated;

drop trigger if exists provider_official_result_impact_fixture_writer
on public.fantasy_fixtures;
create trigger provider_official_result_impact_fixture_writer
after insert or update of finalized_at,official_projection_id,result_revision on public.fantasy_fixtures
for each row execute function public.reconcile_provider_official_result_impact_from_fixture_v1();
alter table public.fantasy_fixtures enable always trigger provider_official_result_impact_fixture_writer;

-- Backfill non distruttivo delle sole partite ufficiali già presenti.
do $backfill$
declare
  v_matchday_id uuid;
begin
  for v_matchday_id in
    select distinct fixture.matchday_id
    from public.fantasy_fixtures fixture
    where fixture.finalized_at is not null
  loop
    perform public.reconcile_provider_official_result_impact_v1(v_matchday_id);
  end loop;
end;
$backfill$;

create or replace function public.get_league_provider_official_result_impact_v1(p_league_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $function$
declare
  v_owner_id uuid;
  v_clear integer:=0;
  v_affected integer:=0;
  v_correction integer:=0;
  v_affected_matchdays integer:=0;
  v_events_24h integer:=0;
  v_latest jsonb;
begin
  if auth.uid() is null then raise exception 'Devi effettuare l''accesso.'; end if;
  select league_row.owner_id into v_owner_id from public.leagues league_row where league_row.id=p_league_id;
  if not found then raise exception 'Lega non trovata per la certificazione impatto risultati.'; end if;
  if v_owner_id<>auth.uid() and not public.is_league_admin(p_league_id) then
    raise exception 'Solo Presidente e Admin possono leggere l''impatto sui risultati ufficiali.';
  end if;

  select
    count(*) filter(where head.impact_status='clear')::integer,
    count(*) filter(where head.impact_status='affected')::integer,
    count(*) filter(where head.impact_status='in_correction')::integer,
    count(distinct head.matchday_id) filter(where head.impact_status='affected')::integer
  into v_clear,v_affected,v_correction,v_affected_matchdays
  from public.provider_official_result_impact_heads head
  where head.league_id=p_league_id;

  select count(*)::integer into v_events_24h
  from public.provider_official_result_impact_events event_row
  where event_row.league_id=p_league_id and event_row.created_at>=now()-interval '24 hours';

  select jsonb_build_object(
    'id',event_row.id,'fixtureId',event_row.fixture_id,'matchdayId',event_row.matchday_id,
    'impactStatus',event_row.impact_status,'reasonCode',event_row.reason_code,
    'assessmentGeneration',event_row.assessment_generation,
    'affectedSideCount',event_row.affected_side_count,'createdAt',event_row.created_at
  ) into v_latest
  from public.provider_official_result_impact_events event_row
  where event_row.league_id=p_league_id
  order by event_row.created_at desc limit 1;

  return jsonb_build_object(
    'protected',true,'healthy',v_affected=0,
    'preciseOfficialResultLineageActive',true,
    'officialResultsNeverMutatedAutomatically',true,
    'protectedCorrectionWorkflowAvailable',to_regprocedure('public.reopen_league_fixture_guarded_v1(uuid,uuid,text,uuid)') is not null,
    'clearFixtureCount',v_clear,'affectedFixtureCount',v_affected,
    'inCorrectionFixtureCount',v_correction,'affectedMatchdayCount',v_affected_matchdays,
    'eventsLast24h',v_events_24h,'latestEvent',v_latest
  );
end;
$function$;
revoke all on function public.get_league_provider_official_result_impact_v1(uuid) from public,anon,service_role;
grant execute on function public.get_league_provider_official_result_impact_v1(uuid) to authenticated;

create or replace function public.get_league_provider_sync_health_v21(p_league_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $function$
declare
  v_base jsonb;
  v_impact jsonb;
  v_healthy boolean;
  v_status text;
begin
  v_base:=public.get_league_provider_sync_health_v20(p_league_id);
  v_impact:=public.get_league_provider_official_result_impact_v1(p_league_id);
  v_healthy:=coalesce((v_base->>'healthy')::boolean,false) and coalesce((v_impact->>'healthy')::boolean,false);
  v_status:=case when not v_healthy then 'attention' else coalesce(v_base->>'status','idle') end;
  return v_base||jsonb_build_object(
    'protected',coalesce((v_base->>'protected')::boolean,false) and coalesce((v_impact->>'protected')::boolean,false),
    'healthy',v_healthy,'status',v_status,'officialResultImpact',v_impact
  );
end;
$function$;
revoke all on function public.get_league_provider_sync_health_v21(uuid) from public,anon,service_role;
grant execute on function public.get_league_provider_sync_health_v21(uuid) to authenticated;

create or replace function public.get_provider_official_result_impact_integrity_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $function$
declare
  v_predecessor jsonb;
  v_compute text;
  v_center text;
  v_health text;
begin
  v_predecessor:=public.get_provider_score_consumption_gate_integrity_v1();
  v_compute:=lower(pg_catalog.pg_get_functiondef('public.compute_provider_official_result_impact_v1(uuid)'::regprocedure));
  v_center:=lower(pg_catalog.pg_get_functiondef('public.get_league_provider_official_result_impact_v1(uuid)'::regprocedure));
  v_health:=lower(pg_catalog.pg_get_functiondef('public.get_league_provider_sync_health_v21(uuid)'::regprocedure));
  return jsonb_build_object(
    'predecessor_ready',(select count(*) from jsonb_each(v_predecessor))=20
      and not exists(select 1 from jsonb_each(v_predecessor) check_row where check_row.value is distinct from 'true'::jsonb),
    'head_table_ready',to_regclass('public.provider_official_result_impact_heads') is not null,
    'event_table_ready',to_regclass('public.provider_official_result_impact_events') is not null,
    'constraints_ready',(select count(*)>=7 from pg_catalog.pg_constraint where conrelid='public.provider_official_result_impact_heads'::regclass)
      and (select count(*)>=7 from pg_catalog.pg_constraint where conrelid='public.provider_official_result_impact_events'::regclass),
    'indexes_ready',to_regclass('public.provider_official_result_impact_heads_league_idx') is not null
      and to_regclass('public.provider_official_result_impact_events_league_idx') is not null,
    'rls_ready',(select relrowsecurity from pg_catalog.pg_class where oid='public.provider_official_result_impact_heads'::regclass)
      and (select relrowsecurity from pg_catalog.pg_class where oid='public.provider_official_result_impact_events'::regclass),
    'authenticated_write_blocked',not has_table_privilege('authenticated','public.provider_official_result_impact_heads','INSERT')
      and not has_table_privilege('authenticated','public.provider_official_result_impact_heads','UPDATE')
      and not has_table_privilege('authenticated','public.provider_official_result_impact_events','INSERT'),
    'service_role_ready',has_table_privilege('service_role','public.provider_official_result_impact_heads','SELECT')
      and has_table_privilege('service_role','public.provider_official_result_impact_heads','INSERT')
      and has_table_privilege('service_role','public.provider_official_result_impact_events','INSERT'),
    'immutable_events_ready',exists(select 1 from pg_catalog.pg_trigger trigger_row
      where trigger_row.tgrelid='public.provider_official_result_impact_events'::regclass
        and trigger_row.tgname='provider_official_result_impact_events_immutable'
        and trigger_row.tgenabled='A' and not trigger_row.tgisinternal),
    'head_guard_ready',exists(select 1 from pg_catalog.pg_trigger trigger_row
      where trigger_row.tgrelid='public.provider_official_result_impact_heads'::regclass
        and trigger_row.tgname='provider_official_result_impact_heads_guard'
        and trigger_row.tgenabled='A' and not trigger_row.tgisinternal),
    'compute_rpc_ready',to_regprocedure('public.compute_provider_official_result_impact_v1(uuid)') is not null,
    'reconcile_rpc_ready',to_regprocedure('public.reconcile_provider_official_result_impact_v1(uuid)') is not null,
    'score_event_trigger_ready',exists(select 1 from pg_catalog.pg_trigger trigger_row
      where trigger_row.tgrelid='public.provider_score_consumption_gate_events'::regclass
        and trigger_row.tgname='provider_official_result_impact_gate_writer'
        and trigger_row.tgenabled='A' and not trigger_row.tgisinternal),
    'fixture_trigger_ready',exists(select 1 from pg_catalog.pg_trigger trigger_row
      where trigger_row.tgrelid='public.fantasy_fixtures'::regclass
        and trigger_row.tgname='provider_official_result_impact_fixture_writer'
        and trigger_row.tgenabled='A' and not trigger_row.tgisinternal),
    'backfill_ready',not exists(select 1 from public.fantasy_fixtures fixture
      where fixture.finalized_at is not null and not exists(
        select 1 from public.provider_official_result_impact_heads head where head.fixture_id=fixture.id)),
    'lineage_hash_ready',position('lineup_resolution_input_hash_v1' in v_compute)>0
      and position('official_projection_id' in v_compute)>0
      and position('official_home_input_hash' in v_compute)>0,
    'center_rpc_ready',to_regprocedure('public.get_league_provider_official_result_impact_v1(uuid)') is not null
      and position('affectedfixturecount' in replace(v_center,'_',''))>0,
    'health_v21_ready',to_regprocedure('public.get_league_provider_sync_health_v21(uuid)') is not null
      and position('officialresultimpact' in replace(v_health,'_',''))>0,
    'realtime_events_only_ready',exists(select 1 from pg_catalog.pg_publication_tables publication_row
      where publication_row.pubname='supabase_realtime' and publication_row.schemaname='public'
        and publication_row.tablename='provider_official_result_impact_events')
      or not exists(select 1 from pg_catalog.pg_publication_tables publication_row
        where publication_row.pubname='supabase_realtime' and publication_row.schemaname='public'
          and publication_row.tablename='provider_official_result_impact_heads'),
    'rpc_grants_ready',has_function_privilege('authenticated','public.get_league_provider_official_result_impact_v1(uuid)','EXECUTE')
      and has_function_privilege('authenticated','public.get_league_provider_sync_health_v21(uuid)','EXECUTE')
      and not has_function_privilege('authenticated','public.compute_provider_official_result_impact_v1(uuid)','EXECUTE')
  );
end;
$function$;
revoke all on function public.get_provider_official_result_impact_integrity_v1() from public,anon,authenticated;
grant execute on function public.get_provider_official_result_impact_integrity_v1() to service_role;

do $realtime$
begin
  if exists(select 1 from pg_catalog.pg_publication where pubname='supabase_realtime') then
    if not exists(select 1 from pg_catalog.pg_publication_tables
      where pubname='supabase_realtime' and schemaname='public'
        and tablename='provider_official_result_impact_events') then
      execute 'alter publication supabase_realtime add table public.provider_official_result_impact_events';
    end if;
  end if;
end;
$realtime$;

do $validation$
declare
  v_checks jsonb;
  v_failed text;
begin
  v_checks:=public.get_provider_official_result_impact_integrity_v1();
  select string_agg(check_row.key,', ' order by check_row.key) into v_failed
  from jsonb_each(v_checks) check_row
  where jsonb_typeof(check_row.value) is distinct from 'boolean'
     or check_row.value is distinct from 'true'::jsonb;
  if (select count(*) from jsonb_each(v_checks))<>20 or v_failed is not null then
    raise exception 'Validazione v0.62.22 non superata. Controlli falsi: %',coalesce(v_failed,'numero_controlli_non_valido');
  end if;
end;
$validation$;

commit;

-- DIAGNOSTICA FINALE: devono comparire esattamente 20 valori true.
select
  (checks->>'predecessor_ready')::boolean as predecessor_ready,
  (checks->>'head_table_ready')::boolean as head_table_ready,
  (checks->>'event_table_ready')::boolean as event_table_ready,
  (checks->>'constraints_ready')::boolean as constraints_ready,
  (checks->>'indexes_ready')::boolean as indexes_ready,
  (checks->>'rls_ready')::boolean as rls_ready,
  (checks->>'authenticated_write_blocked')::boolean as authenticated_write_blocked,
  (checks->>'service_role_ready')::boolean as service_role_ready,
  (checks->>'immutable_events_ready')::boolean as immutable_events_ready,
  (checks->>'head_guard_ready')::boolean as head_guard_ready,
  (checks->>'compute_rpc_ready')::boolean as compute_rpc_ready,
  (checks->>'reconcile_rpc_ready')::boolean as reconcile_rpc_ready,
  (checks->>'score_event_trigger_ready')::boolean as score_event_trigger_ready,
  (checks->>'fixture_trigger_ready')::boolean as fixture_trigger_ready,
  (checks->>'backfill_ready')::boolean as backfill_ready,
  (checks->>'lineage_hash_ready')::boolean as lineage_hash_ready,
  (checks->>'center_rpc_ready')::boolean as center_rpc_ready,
  (checks->>'health_v21_ready')::boolean as health_v21_ready,
  (checks->>'realtime_events_only_ready')::boolean as realtime_events_only_ready,
  (checks->>'rpc_grants_ready')::boolean as rpc_grants_ready
from (select public.get_provider_official_result_impact_integrity_v1() as checks) diagnostic;
