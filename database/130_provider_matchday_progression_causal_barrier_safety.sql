-- LEGHEVO v0.62.26
-- Barriera causale certificata della progressione giornata provider.
-- Migrazione interna: database/130_provider_matchday_progression_causal_barrier_safety.sql
-- Eseguire dopo database/129_provider_official_result_remediation_completion_safety.sql.
-- La migrazione non arretra automaticamente calendario, classifica o risultati.

begin;

-- PRE-FLIGHT: dipendenze reali e firme complete.
do $preflight$
declare
  v_missing text[] := array[]::text[];
  v_checks jsonb;
begin
  if to_regprocedure('public.get_provider_official_result_remediation_completion_integrity_v1()') is null then
    v_missing:=array_append(v_missing,'function public.get_provider_official_result_remediation_completion_integrity_v1()');
  else
    v_checks:=public.get_provider_official_result_remediation_completion_integrity_v1();
    if (select count(*) from jsonb_each(v_checks))<>20
      or exists(
        select 1 from jsonb_each(v_checks) check_row
        where jsonb_typeof(check_row.value) is distinct from 'boolean'
           or check_row.value is distinct from 'true'::jsonb
      ) then
      v_missing:=array_append(v_missing,'v0.62.25 integrity: all 20 checks must be true');
    end if;
  end if;

  if to_regclass('public.matchday_progression_runs') is null then
    v_missing:=array_append(v_missing,'table public.matchday_progression_runs');
  end if;
  if to_regclass('public.provider_official_result_impact_heads') is null then
    v_missing:=array_append(v_missing,'table public.provider_official_result_impact_heads');
  end if;
  if to_regclass('public.provider_official_result_lineage_heads') is null then
    v_missing:=array_append(v_missing,'table public.provider_official_result_lineage_heads');
  end if;
  if to_regclass('public.provider_official_result_remediation_heads') is null then
    v_missing:=array_append(v_missing,'table public.provider_official_result_remediation_heads');
  end if;
  if to_regclass('public.provider_official_result_remediation_completion_heads') is null then
    v_missing:=array_append(v_missing,'table public.provider_official_result_remediation_completion_heads');
  end if;

  if exists(
    select 1
    from (values
      ('fantasy_fixtures','id'),('fantasy_fixtures','league_id'),
      ('fantasy_fixtures','matchday_id'),('fantasy_fixtures','finalized_at'),
      ('fantasy_fixtures','officialization_run_id'),('matchdays','id'),
      ('matchdays','number'),('matchday_progression_runs','id'),
      ('matchday_progression_runs','league_id'),('matchday_progression_runs','matchday_id'),
      ('matchday_progression_runs','officialization_run_id'),
      ('matchday_progression_runs','superseded_at'),
      ('provider_official_result_impact_heads','fixture_id'),
      ('provider_official_result_impact_heads','matchday_id'),
      ('provider_official_result_impact_heads','impact_status'),
      ('provider_official_result_lineage_heads','fixture_id'),
      ('provider_official_result_lineage_heads','lineage_status'),
      ('provider_official_result_remediation_heads','id'),
      ('provider_official_result_remediation_heads','fixture_id'),
      ('provider_official_result_remediation_heads','remediation_status'),
      ('provider_official_result_remediation_completion_heads','remediation_head_id'),
      ('provider_official_result_remediation_completion_heads','completion_status')
    ) required(table_name,column_name)
    where not exists(
      select 1 from information_schema.columns column_row
      where column_row.table_schema='public'
        and column_row.table_name=required.table_name
        and column_row.column_name=required.column_name
    )
  ) then
    v_missing:=array_append(v_missing,'required columns for provider matchday progression barrier');
  end if;

  if to_regprocedure('public.get_league_provider_sync_health_v24(uuid)') is null then
    v_missing:=array_append(v_missing,'RPC public.get_league_provider_sync_health_v24(uuid)');
  end if;
  if to_regprocedure('public.is_league_member(uuid)') is null then
    v_missing:=array_append(v_missing,'function public.is_league_member(uuid)');
  end if;
  if to_regprocedure('public.is_league_admin(uuid)') is null then
    v_missing:=array_append(v_missing,'function public.is_league_admin(uuid)');
  end if;
  if to_regprocedure('pg_catalog.md5(text)') is null then
    v_missing:=array_append(v_missing,'function pg_catalog.md5(text)');
  end if;

  if cardinality(v_missing)>0 then
    raise exception 'Preflight v0.62.26 non superato. Dipendenze mancanti: %',array_to_string(v_missing,'; ');
  end if;
end;
$preflight$;

create table if not exists public.provider_matchday_progression_gate_heads (
  id uuid primary key default gen_random_uuid(),
  league_id uuid not null references public.leagues(id) on delete cascade,
  matchday_id uuid not null unique references public.matchdays(id) on delete cascade,
  matchday_number smallint not null,
  current_officialization_run_id bigint references public.matchday_officialization_runs(id) on delete set null,
  current_progression_run_id bigint references public.matchday_progression_runs(id) on delete set null,
  gate_status text not null,
  reason_code text not null,
  fixture_count integer not null default 0,
  safe_fixture_count integer not null default 0,
  unsafe_fixture_count integer not null default 0,
  prior_unsafe_progression_count integer not null default 0,
  gate_generation bigint not null default 1,
  gate_fingerprint text not null,
  first_unsafe_at timestamptz,
  last_assessed_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint provider_matchday_progression_gate_heads_status_check
    check(gate_status in ('clear','blocked','affected')),
  constraint provider_matchday_progression_gate_heads_reason_check
    check(char_length(trim(reason_code)) between 3 and 160),
  constraint provider_matchday_progression_gate_heads_counts_check
    check(fixture_count>=0 and safe_fixture_count>=0 and unsafe_fixture_count>=0
      and prior_unsafe_progression_count>=0
      and safe_fixture_count+unsafe_fixture_count=fixture_count),
  constraint provider_matchday_progression_gate_heads_generation_check
    check(gate_generation>=1),
  constraint provider_matchday_progression_gate_heads_fingerprint_check
    check(length(gate_fingerprint)=32),
  constraint provider_matchday_progression_gate_heads_number_check
    check(matchday_number>0)
);

create table if not exists public.provider_matchday_progression_gate_events (
  id bigint generated by default as identity primary key,
  head_id uuid not null references public.provider_matchday_progression_gate_heads(id) on delete restrict,
  league_id uuid not null references public.leagues(id) on delete cascade,
  matchday_id uuid not null references public.matchdays(id) on delete cascade,
  matchday_number smallint not null,
  event_type text not null,
  gate_status text not null,
  reason_code text not null,
  gate_generation bigint not null,
  current_officialization_run_id bigint references public.matchday_officialization_runs(id) on delete set null,
  current_progression_run_id bigint references public.matchday_progression_runs(id) on delete set null,
  fixture_count integer not null,
  safe_fixture_count integer not null,
  unsafe_fixture_count integer not null,
  prior_unsafe_progression_count integer not null,
  gate_fingerprint text not null,
  created_at timestamptz not null default now(),
  constraint provider_matchday_progression_gate_events_type_check
    check(event_type in ('clear','blocked','affected','revalidated')),
  constraint provider_matchday_progression_gate_events_status_check
    check(gate_status in ('clear','blocked','affected')),
  constraint provider_matchday_progression_gate_events_reason_check
    check(char_length(trim(reason_code)) between 3 and 160),
  constraint provider_matchday_progression_gate_events_generation_check
    check(gate_generation>=1),
  constraint provider_matchday_progression_gate_events_counts_check
    check(fixture_count>=0 and safe_fixture_count>=0 and unsafe_fixture_count>=0
      and prior_unsafe_progression_count>=0
      and safe_fixture_count+unsafe_fixture_count=fixture_count),
  constraint provider_matchday_progression_gate_events_fingerprint_check
    check(length(gate_fingerprint)=32),
  constraint provider_matchday_progression_gate_events_number_check
    check(matchday_number>0)
);

create index if not exists provider_matchday_progression_gate_heads_league_idx
  on public.provider_matchday_progression_gate_heads(league_id,gate_status,matchday_number);
create index if not exists provider_matchday_progression_gate_heads_progression_idx
  on public.provider_matchday_progression_gate_heads(current_progression_run_id)
  where current_progression_run_id is not null;
create index if not exists provider_matchday_progression_gate_events_league_idx
  on public.provider_matchday_progression_gate_events(league_id,created_at desc);
create index if not exists provider_matchday_progression_gate_events_matchday_idx
  on public.provider_matchday_progression_gate_events(matchday_id,created_at desc);

alter table public.provider_matchday_progression_gate_heads enable row level security;
alter table public.provider_matchday_progression_gate_events enable row level security;
alter table public.provider_matchday_progression_gate_events replica identity full;

revoke all on table public.provider_matchday_progression_gate_heads from public,anon,authenticated,service_role;
revoke all on table public.provider_matchday_progression_gate_events from public,anon,authenticated,service_role;
grant select on table public.provider_matchday_progression_gate_heads to authenticated;
grant select on table public.provider_matchday_progression_gate_events to authenticated;
grant select,insert,update on table public.provider_matchday_progression_gate_heads to service_role;
grant select,insert on table public.provider_matchday_progression_gate_events to service_role;

drop policy if exists provider_matchday_progression_gate_heads_director_select
on public.provider_matchday_progression_gate_heads;
create policy provider_matchday_progression_gate_heads_director_select
on public.provider_matchday_progression_gate_heads
for select to authenticated
using(
  exists(select 1 from public.leagues league_row
    where league_row.id=league_id
      and (league_row.owner_id=auth.uid() or public.is_league_admin(league_id)))
);

drop policy if exists provider_matchday_progression_gate_events_director_select
on public.provider_matchday_progression_gate_events;
create policy provider_matchday_progression_gate_events_director_select
on public.provider_matchday_progression_gate_events
for select to authenticated
using(
  exists(select 1 from public.leagues league_row
    where league_row.id=league_id
      and (league_row.owner_id=auth.uid() or public.is_league_admin(league_id)))
);

create or replace function public.prevent_provider_matchday_progression_gate_head_mutation_v1()
returns trigger
language plpgsql
security definer
set search_path=''
as $function$
begin
  if current_setting('leghevo.provider_matchday_progression_gate_context',true) is distinct from 'on' then
    raise exception 'Testa barriera progressione provider protetta: modifica diretta non consentita.';
  end if;
  if tg_op='DELETE' then return old; end if;
  return new;
end;
$function$;
revoke all on function public.prevent_provider_matchday_progression_gate_head_mutation_v1() from public,anon,authenticated;

drop trigger if exists provider_matchday_progression_gate_heads_guard
on public.provider_matchday_progression_gate_heads;
create trigger provider_matchday_progression_gate_heads_guard
before insert or update or delete on public.provider_matchday_progression_gate_heads
for each row execute function public.prevent_provider_matchday_progression_gate_head_mutation_v1();
alter table public.provider_matchday_progression_gate_heads enable always trigger provider_matchday_progression_gate_heads_guard;

create or replace function public.prevent_provider_matchday_progression_gate_event_mutation_v1()
returns trigger
language plpgsql
security definer
set search_path=''
as $function$
begin
  raise exception 'Storico barriera progressione provider immutabile: UPDATE e DELETE non consentiti.';
end;
$function$;
revoke all on function public.prevent_provider_matchday_progression_gate_event_mutation_v1() from public,anon,authenticated;

drop trigger if exists provider_matchday_progression_gate_events_immutable
on public.provider_matchday_progression_gate_events;
create trigger provider_matchday_progression_gate_events_immutable
before update or delete on public.provider_matchday_progression_gate_events
for each row execute function public.prevent_provider_matchday_progression_gate_event_mutation_v1();
alter table public.provider_matchday_progression_gate_events enable always trigger provider_matchday_progression_gate_events_immutable;

create or replace function public.compute_provider_matchday_progression_gate_v1(
  p_league_id uuid,
  p_matchday_id uuid,
  p_expected_officialization_run_id bigint default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $function$
declare
  v_matchday_number smallint;
  v_fixture_count integer:=0;
  v_finalized_count integer:=0;
  v_officialization_count integer:=0;
  v_current_officialization_run_id bigint;
  v_current_progression_run_id bigint;
  v_progression_officialization_run_id bigint;
  v_safe_fixture_count integer:=0;
  v_unsafe_fixture_count integer:=0;
  v_missing_impact_count integer:=0;
  v_impact_unsafe_count integer:=0;
  v_lineage_unsafe_count integer:=0;
  v_remediation_unsafe_count integer:=0;
  v_prior_unsafe_count integer:=0;
  v_status text:='blocked';
  v_reason text:='progression.matchday_unavailable';
  v_fingerprint text;
begin
  select matchday.number
  into v_matchday_number
  from public.matchdays matchday
  where matchday.id=p_matchday_id
    and exists(
      select 1 from public.fantasy_fixtures fixture
      where fixture.league_id=p_league_id and fixture.matchday_id=matchday.id
    );

  if not found then
    return jsonb_build_object('available',false,'reasonCode','progression.matchday_not_found');
  end if;

  select
    count(*)::integer,
    count(*) filter(where fixture.finalized_at is not null)::integer,
    count(distinct fixture.officialization_run_id) filter(where fixture.officialization_run_id is not null)::integer,
    min(fixture.officialization_run_id) filter(where fixture.officialization_run_id is not null)
  into v_fixture_count,v_finalized_count,v_officialization_count,v_current_officialization_run_id
  from public.fantasy_fixtures fixture
  where fixture.league_id=p_league_id and fixture.matchday_id=p_matchday_id;

  select progression.id,progression.officialization_run_id
  into v_current_progression_run_id,v_progression_officialization_run_id
  from public.matchday_progression_runs progression
  where progression.league_id=p_league_id
    and progression.matchday_id=p_matchday_id
    and progression.superseded_at is null
  order by progression.progressed_at desc,progression.id desc
  limit 1;

  select
    count(*) filter(where
      impact.id is not null and impact.impact_status='clear'
      and lineage.id is not null and lineage.lineage_status='certified'
      and (
        remediation.id is null
        or (
          remediation.remediation_status='resolved'
          and completion.id is not null
          and completion.completion_status='certified'
        )
      )
    )::integer,
    count(*) filter(where impact.id is null)::integer,
    count(*) filter(where impact.id is not null and impact.impact_status<>'clear')::integer,
    count(*) filter(where lineage.id is null or lineage.lineage_status<>'certified')::integer,
    count(*) filter(where remediation.id is not null and (
      remediation.remediation_status<>'resolved'
      or completion.id is null
      or completion.completion_status<>'certified'
    ))::integer
  into v_safe_fixture_count,v_missing_impact_count,v_impact_unsafe_count,
    v_lineage_unsafe_count,v_remediation_unsafe_count
  from public.fantasy_fixtures fixture
  left join public.provider_official_result_impact_heads impact
    on impact.fixture_id=fixture.id
  left join public.provider_official_result_lineage_heads lineage
    on lineage.fixture_id=fixture.id
  left join public.provider_official_result_remediation_heads remediation
    on remediation.fixture_id=fixture.id
  left join public.provider_official_result_remediation_completion_heads completion
    on completion.remediation_head_id=remediation.id
  where fixture.league_id=p_league_id and fixture.matchday_id=p_matchday_id;

  v_unsafe_fixture_count:=greatest(v_fixture_count-v_safe_fixture_count,0);

  select count(*)::integer
  into v_prior_unsafe_count
  from public.provider_matchday_progression_gate_heads prior_head
  join public.matchdays prior_matchday on prior_matchday.id=prior_head.matchday_id
  where prior_head.league_id=p_league_id
    and prior_matchday.number<v_matchday_number
    and prior_head.current_progression_run_id is not null
    and prior_head.gate_status<>'clear';

  if v_fixture_count=0 then
    v_status:='blocked'; v_reason:='progression.no_fixtures';
  elsif v_finalized_count<>v_fixture_count or v_officialization_count<>1
    or v_current_officialization_run_id is null then
    v_status:=case when v_current_progression_run_id is null then 'blocked' else 'affected' end;
    v_reason:='progression.officialization_incomplete';
  elsif p_expected_officialization_run_id is not null
    and v_current_officialization_run_id<>p_expected_officialization_run_id then
    v_status:='blocked'; v_reason:='progression.officialization_changed_before_commit';
  elsif v_current_progression_run_id is not null
    and v_progression_officialization_run_id<>v_current_officialization_run_id then
    v_status:='affected'; v_reason:='progression.officialization_superseded';
  elsif v_missing_impact_count>0 then
    v_status:=case when v_current_progression_run_id is null then 'blocked' else 'affected' end;
    v_reason:='progression.impact_certificate_missing';
  elsif v_impact_unsafe_count>0 then
    v_status:=case when v_current_progression_run_id is null then 'blocked' else 'affected' end;
    v_reason:='progression.official_result_affected';
  elsif v_lineage_unsafe_count>0 then
    v_status:=case when v_current_progression_run_id is null then 'blocked' else 'affected' end;
    v_reason:='progression.official_lineage_not_certified';
  elsif v_remediation_unsafe_count>0 then
    v_status:=case when v_current_progression_run_id is null then 'blocked' else 'affected' end;
    v_reason:='progression.remediation_not_certified';
  elsif v_unsafe_fixture_count>0 then
    v_status:=case when v_current_progression_run_id is null then 'blocked' else 'affected' end;
    v_reason:='progression.fixture_not_trusted';
  elsif v_prior_unsafe_count>0 then
    v_status:='blocked'; v_reason:='progression.prior_matchday_chain_unsafe';
  else
    v_status:='clear'; v_reason:='progression.causal_chain_certified';
  end if;

  v_fingerprint:=pg_catalog.md5(jsonb_build_object(
    'leagueId',p_league_id,'matchdayId',p_matchday_id,
    'matchdayNumber',v_matchday_number,
    'officializationRunId',v_current_officialization_run_id,
    'progressionRunId',v_current_progression_run_id,
    'progressionOfficializationRunId',v_progression_officialization_run_id,
    'status',v_status,'reasonCode',v_reason,
    'fixtureCount',v_fixture_count,'safeFixtureCount',v_safe_fixture_count,
    'unsafeFixtureCount',v_unsafe_fixture_count,
    'priorUnsafeProgressionCount',v_prior_unsafe_count
  )::text);

  return jsonb_build_object(
    'available',true,'leagueId',p_league_id,'matchdayId',p_matchday_id,
    'matchdayNumber',v_matchday_number,
    'gateStatus',v_status,'reasonCode',v_reason,
    'currentOfficializationRunId',v_current_officialization_run_id,
    'currentProgressionRunId',v_current_progression_run_id,
    'fixtureCount',v_fixture_count,'safeFixtureCount',v_safe_fixture_count,
    'unsafeFixtureCount',v_unsafe_fixture_count,
    'priorUnsafeProgressionCount',v_prior_unsafe_count,
    'gateFingerprint',v_fingerprint
  );
end;
$function$;
revoke all on function public.compute_provider_matchday_progression_gate_v1(uuid,uuid,bigint) from public,anon,authenticated;
grant execute on function public.compute_provider_matchday_progression_gate_v1(uuid,uuid,bigint) to service_role;

create or replace function public.reconcile_provider_matchday_progression_gate_v1(
  p_league_id uuid,
  p_matchday_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_assessment jsonb;
  v_existing public.provider_matchday_progression_gate_heads%rowtype;
  v_head public.provider_matchday_progression_gate_heads%rowtype;
  v_changed boolean:=false;
  v_generation bigint:=1;
  v_event_type text;
begin
  v_assessment:=public.compute_provider_matchday_progression_gate_v1(p_league_id,p_matchday_id,null);
  if not coalesce((v_assessment->>'available')::boolean,false) then return v_assessment; end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('provider-matchday-progression-gate:'||p_matchday_id::text,0)
  );

  select head.* into v_existing
  from public.provider_matchday_progression_gate_heads head
  where head.matchday_id=p_matchday_id
  for update;

  v_changed:=v_existing.id is null
    or v_existing.gate_fingerprint is distinct from v_assessment->>'gateFingerprint'
    or v_existing.gate_status is distinct from v_assessment->>'gateStatus'
    or v_existing.reason_code is distinct from v_assessment->>'reasonCode'
    or v_existing.current_officialization_run_id is distinct from nullif(v_assessment->>'currentOfficializationRunId','')::bigint
    or v_existing.current_progression_run_id is distinct from nullif(v_assessment->>'currentProgressionRunId','')::bigint;
  v_generation:=case when v_existing.id is null then 1
    when v_changed then v_existing.gate_generation+1 else v_existing.gate_generation end;

  perform set_config('leghevo.provider_matchday_progression_gate_context','on',true);

  insert into public.provider_matchday_progression_gate_heads(
    league_id,matchday_id,matchday_number,current_officialization_run_id,
    current_progression_run_id,gate_status,reason_code,fixture_count,
    safe_fixture_count,unsafe_fixture_count,prior_unsafe_progression_count,
    gate_generation,gate_fingerprint,first_unsafe_at,last_assessed_at,updated_at
  ) values (
    p_league_id,p_matchday_id,(v_assessment->>'matchdayNumber')::smallint,
    nullif(v_assessment->>'currentOfficializationRunId','')::bigint,
    nullif(v_assessment->>'currentProgressionRunId','')::bigint,
    v_assessment->>'gateStatus',v_assessment->>'reasonCode',
    (v_assessment->>'fixtureCount')::integer,(v_assessment->>'safeFixtureCount')::integer,
    (v_assessment->>'unsafeFixtureCount')::integer,
    (v_assessment->>'priorUnsafeProgressionCount')::integer,
    v_generation,v_assessment->>'gateFingerprint',
    case when v_assessment->>'gateStatus'<>'clear' then now() else null end,
    now(),now()
  ) on conflict(matchday_id) do update set
    league_id=excluded.league_id,matchday_number=excluded.matchday_number,
    current_officialization_run_id=excluded.current_officialization_run_id,
    current_progression_run_id=excluded.current_progression_run_id,
    gate_status=excluded.gate_status,reason_code=excluded.reason_code,
    fixture_count=excluded.fixture_count,safe_fixture_count=excluded.safe_fixture_count,
    unsafe_fixture_count=excluded.unsafe_fixture_count,
    prior_unsafe_progression_count=excluded.prior_unsafe_progression_count,
    gate_generation=excluded.gate_generation,gate_fingerprint=excluded.gate_fingerprint,
    first_unsafe_at=case
      when public.provider_matchday_progression_gate_heads.first_unsafe_at is not null
        then public.provider_matchday_progression_gate_heads.first_unsafe_at
      when excluded.gate_status<>'clear' then now() else null end,
    last_assessed_at=now(),
    updated_at=case when v_changed then now() else public.provider_matchday_progression_gate_heads.updated_at end
  returning * into v_head;

  if v_changed then
    v_event_type:=case
      when v_head.gate_status='clear' and v_existing.id is not null and v_existing.gate_status<>'clear'
        then 'revalidated'
      else v_head.gate_status end;
    insert into public.provider_matchday_progression_gate_events(
      head_id,league_id,matchday_id,matchday_number,event_type,gate_status,
      reason_code,gate_generation,current_officialization_run_id,
      current_progression_run_id,fixture_count,safe_fixture_count,
      unsafe_fixture_count,prior_unsafe_progression_count,gate_fingerprint
    ) values (
      v_head.id,v_head.league_id,v_head.matchday_id,v_head.matchday_number,
      v_event_type,v_head.gate_status,v_head.reason_code,v_head.gate_generation,
      v_head.current_officialization_run_id,v_head.current_progression_run_id,
      v_head.fixture_count,v_head.safe_fixture_count,v_head.unsafe_fixture_count,
      v_head.prior_unsafe_progression_count,v_head.gate_fingerprint
    );
  end if;

  perform set_config('leghevo.provider_matchday_progression_gate_context','',true);
  return v_assessment||jsonb_build_object('changed',v_changed,'gateGeneration',v_head.gate_generation);
end;
$function$;
revoke all on function public.reconcile_provider_matchday_progression_gate_v1(uuid,uuid) from public,anon,authenticated;
grant execute on function public.reconcile_provider_matchday_progression_gate_v1(uuid,uuid) to service_role;

create or replace function public.enforce_provider_matchday_progression_gate_v1()
returns trigger
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_gate jsonb;
begin
  v_gate:=public.compute_provider_matchday_progression_gate_v1(
    new.league_id,new.matchday_id,new.officialization_run_id
  );
  if not coalesce((v_gate->>'available')::boolean,false)
    or coalesce(v_gate->>'gateStatus','blocked')<>'clear' then
    raise exception 'Progressione giornata rifiutata [provider.progression_gate]: %',
      coalesce(v_gate->>'reasonCode','progression.unknown');
  end if;
  return new;
end;
$function$;
revoke all on function public.enforce_provider_matchday_progression_gate_v1() from public,anon,authenticated;

drop trigger if exists provider_matchday_progression_gate_insert_guard
on public.matchday_progression_runs;
create trigger provider_matchday_progression_gate_insert_guard
before insert on public.matchday_progression_runs
for each row execute function public.enforce_provider_matchday_progression_gate_v1();
alter table public.matchday_progression_runs enable always trigger provider_matchday_progression_gate_insert_guard;

create or replace function public.reconcile_provider_matchday_progression_gate_from_impact_v1()
returns trigger language plpgsql security definer set search_path='' as $function$
begin
  perform public.reconcile_provider_matchday_progression_gate_v1(new.league_id,new.matchday_id);
  return new;
end;
$function$;
revoke all on function public.reconcile_provider_matchday_progression_gate_from_impact_v1() from public,anon,authenticated;

drop trigger if exists provider_matchday_progression_gate_impact_writer
on public.provider_official_result_impact_heads;
create trigger provider_matchday_progression_gate_impact_writer
after insert or update of impact_status,assessment_generation,officialization_run_id
on public.provider_official_result_impact_heads
for each row execute function public.reconcile_provider_matchday_progression_gate_from_impact_v1();
alter table public.provider_official_result_impact_heads enable always trigger provider_matchday_progression_gate_impact_writer;

create or replace function public.reconcile_provider_matchday_progression_gate_from_lineage_v1()
returns trigger language plpgsql security definer set search_path='' as $function$
begin
  perform public.reconcile_provider_matchday_progression_gate_v1(new.league_id,new.matchday_id);
  return new;
end;
$function$;
revoke all on function public.reconcile_provider_matchday_progression_gate_from_lineage_v1() from public,anon,authenticated;

drop trigger if exists provider_matchday_progression_gate_lineage_writer
on public.provider_official_result_lineage_heads;
create trigger provider_matchday_progression_gate_lineage_writer
after insert or update of lineage_status,lineage_generation,officialization_run_id,correction_run_id
on public.provider_official_result_lineage_heads
for each row execute function public.reconcile_provider_matchday_progression_gate_from_lineage_v1();
alter table public.provider_official_result_lineage_heads enable always trigger provider_matchday_progression_gate_lineage_writer;

create or replace function public.reconcile_provider_matchday_progression_gate_from_remediation_v1()
returns trigger language plpgsql security definer set search_path='' as $function$
begin
  perform public.reconcile_provider_matchday_progression_gate_v1(new.league_id,new.matchday_id);
  return new;
end;
$function$;
revoke all on function public.reconcile_provider_matchday_progression_gate_from_remediation_v1() from public,anon,authenticated;

drop trigger if exists provider_matchday_progression_gate_remediation_writer
on public.provider_official_result_remediation_heads;
create trigger provider_matchday_progression_gate_remediation_writer
after insert or update of remediation_status,remediation_generation,correction_run_id
on public.provider_official_result_remediation_heads
for each row execute function public.reconcile_provider_matchday_progression_gate_from_remediation_v1();
alter table public.provider_official_result_remediation_heads enable always trigger provider_matchday_progression_gate_remediation_writer;

create or replace function public.reconcile_provider_matchday_progression_gate_from_completion_v1()
returns trigger language plpgsql security definer set search_path='' as $function$
begin
  perform public.reconcile_provider_matchday_progression_gate_v1(new.league_id,new.matchday_id);
  return new;
end;
$function$;
revoke all on function public.reconcile_provider_matchday_progression_gate_from_completion_v1() from public,anon,authenticated;

drop trigger if exists provider_matchday_progression_gate_completion_writer
on public.provider_official_result_remediation_completion_heads;
create trigger provider_matchday_progression_gate_completion_writer
after insert or update of completion_status,completion_generation,officialization_run_id
on public.provider_official_result_remediation_completion_heads
for each row execute function public.reconcile_provider_matchday_progression_gate_from_completion_v1();
alter table public.provider_official_result_remediation_completion_heads enable always trigger provider_matchday_progression_gate_completion_writer;

create or replace function public.reconcile_provider_matchday_progression_gate_from_fixture_v1()
returns trigger language plpgsql security definer set search_path='' as $function$
begin
  perform public.reconcile_provider_matchday_progression_gate_v1(new.league_id,new.matchday_id);
  return new;
end;
$function$;
revoke all on function public.reconcile_provider_matchday_progression_gate_from_fixture_v1() from public,anon,authenticated;

drop trigger if exists provider_matchday_progression_gate_fixture_writer
on public.fantasy_fixtures;
create trigger provider_matchday_progression_gate_fixture_writer
after update of finalized_at,officialization_run_id,correction_run_id,official_projection_id
on public.fantasy_fixtures
for each row execute function public.reconcile_provider_matchday_progression_gate_from_fixture_v1();
alter table public.fantasy_fixtures enable always trigger provider_matchday_progression_gate_fixture_writer;

create or replace function public.reconcile_provider_matchday_progression_gate_from_progression_v1()
returns trigger language plpgsql security definer set search_path='' as $function$
begin
  perform public.reconcile_provider_matchday_progression_gate_v1(new.league_id,new.matchday_id);
  return new;
end;
$function$;
revoke all on function public.reconcile_provider_matchday_progression_gate_from_progression_v1() from public,anon,authenticated;

drop trigger if exists provider_matchday_progression_gate_progression_writer
on public.matchday_progression_runs;
create trigger provider_matchday_progression_gate_progression_writer
after insert on public.matchday_progression_runs
for each row execute function public.reconcile_provider_matchday_progression_gate_from_progression_v1();
alter table public.matchday_progression_runs enable always trigger provider_matchday_progression_gate_progression_writer;

-- Backfill non distruttivo: certifica solo giornate già interamente ufficializzate
-- oppure già dotate di una progressione storica.
do $backfill$
declare
  v_row record;
begin
  for v_row in
    select fixture.league_id,fixture.matchday_id
    from public.fantasy_fixtures fixture
    group by fixture.league_id,fixture.matchday_id
    having count(*) filter(where fixture.finalized_at is not null)=count(*)
      or exists(
        select 1 from public.matchday_progression_runs progression
        where progression.league_id=fixture.league_id
          and progression.matchday_id=fixture.matchday_id
      )
    order by fixture.league_id,fixture.matchday_id
  loop
    perform public.reconcile_provider_matchday_progression_gate_v1(v_row.league_id,v_row.matchday_id);
  end loop;
end;
$backfill$;

create or replace function public.get_league_provider_matchday_progression_gate_v1(p_league_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $function$
declare
  v_owner_id uuid;
  v_clear integer:=0;
  v_blocked integer:=0;
  v_affected integer:=0;
  v_unsafe_progressions integer:=0;
  v_events_24h integer:=0;
  v_latest jsonb;
begin
  if auth.uid() is null then raise exception 'Devi effettuare l''accesso.'; end if;
  select league_row.owner_id into v_owner_id from public.leagues league_row where league_row.id=p_league_id;
  if not found then raise exception 'Lega non trovata per la barriera di progressione provider.'; end if;
  if v_owner_id<>auth.uid() and not public.is_league_admin(p_league_id) then
    raise exception 'Solo Presidente e Admin possono leggere la barriera di progressione provider.';
  end if;

  select
    count(*) filter(where head.gate_status='clear')::integer,
    count(*) filter(where head.gate_status='blocked')::integer,
    count(*) filter(where head.gate_status='affected')::integer,
    count(*) filter(where head.current_progression_run_id is not null and head.gate_status<>'clear')::integer
  into v_clear,v_blocked,v_affected,v_unsafe_progressions
  from public.provider_matchday_progression_gate_heads head
  where head.league_id=p_league_id;

  select count(*)::integer into v_events_24h
  from public.provider_matchday_progression_gate_events event_row
  where event_row.league_id=p_league_id and event_row.created_at>=now()-interval '24 hours';

  select jsonb_build_object(
    'id',event_row.id,'matchdayId',event_row.matchday_id,
    'matchdayNumber',event_row.matchday_number,'eventType',event_row.event_type,
    'gateStatus',event_row.gate_status,'reasonCode',event_row.reason_code,
    'gateGeneration',event_row.gate_generation,
    'currentOfficializationRunId',event_row.current_officialization_run_id,
    'currentProgressionRunId',event_row.current_progression_run_id,
    'unsafeFixtureCount',event_row.unsafe_fixture_count,
    'priorUnsafeProgressionCount',event_row.prior_unsafe_progression_count,
    'createdAt',event_row.created_at
  ) into v_latest
  from public.provider_matchday_progression_gate_events event_row
  where event_row.league_id=p_league_id
  order by event_row.created_at desc,event_row.id desc limit 1;

  return jsonb_build_object(
    'protected',true,'healthy',v_unsafe_progressions=0 and v_affected=0,
    'causalProgressionBarrierActive',true,
    'legacyProgressionBypassBlocked',true,
    'priorMatchdayChainProtected',true,
    'clearMatchdayCount',v_clear,'blockedMatchdayCount',v_blocked,
    'affectedMatchdayCount',v_affected,
    'unsafeProgressionCount',v_unsafe_progressions,
    'eventsLast24h',v_events_24h,'latestEvent',v_latest
  );
end;
$function$;
revoke all on function public.get_league_provider_matchday_progression_gate_v1(uuid) from public,anon,service_role;
grant execute on function public.get_league_provider_matchday_progression_gate_v1(uuid) to authenticated;

create or replace function public.get_league_provider_sync_health_v25(p_league_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $function$
declare
  v_base jsonb;
  v_gate jsonb;
  v_healthy boolean;
  v_status text;
begin
  v_base:=public.get_league_provider_sync_health_v24(p_league_id);
  v_gate:=public.get_league_provider_matchday_progression_gate_v1(p_league_id);
  v_healthy:=coalesce((v_base->>'healthy')::boolean,false)
    and coalesce((v_gate->>'healthy')::boolean,false);
  v_status:=case when not v_healthy then 'attention' else coalesce(v_base->>'status','idle') end;
  return v_base||jsonb_build_object(
    'protected',coalesce((v_base->>'protected')::boolean,false)
      and coalesce((v_gate->>'protected')::boolean,false),
    'healthy',v_healthy,'status',v_status,
    'matchdayProgressionGate',v_gate
  );
end;
$function$;
revoke all on function public.get_league_provider_sync_health_v25(uuid) from public,anon,service_role;
grant execute on function public.get_league_provider_sync_health_v25(uuid) to authenticated;

-- Solo lo storico immutabile viene pubblicato in Realtime.
do $realtime$
begin
  if exists(select 1 from pg_catalog.pg_publication where pubname='supabase_realtime')
    and not exists(
      select 1 from pg_catalog.pg_publication_tables
      where pubname='supabase_realtime' and schemaname='public'
        and tablename='provider_matchday_progression_gate_events'
    ) then
    alter publication supabase_realtime add table public.provider_matchday_progression_gate_events;
  end if;
end;
$realtime$;

create or replace function public.get_provider_matchday_progression_gate_integrity_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $function$
declare
  v_predecessor jsonb;
  v_compute text;
  v_reconcile text;
  v_guard text;
  v_center text;
  v_health text;
begin
  v_predecessor:=public.get_provider_official_result_remediation_completion_integrity_v1();
  v_compute:=lower(pg_catalog.pg_get_functiondef('public.compute_provider_matchday_progression_gate_v1(uuid,uuid,bigint)'::regprocedure));
  v_reconcile:=lower(pg_catalog.pg_get_functiondef('public.reconcile_provider_matchday_progression_gate_v1(uuid,uuid)'::regprocedure));
  v_guard:=lower(pg_catalog.pg_get_functiondef('public.enforce_provider_matchday_progression_gate_v1()'::regprocedure));
  v_center:=lower(pg_catalog.pg_get_functiondef('public.get_league_provider_matchday_progression_gate_v1(uuid)'::regprocedure));
  v_health:=lower(pg_catalog.pg_get_functiondef('public.get_league_provider_sync_health_v25(uuid)'::regprocedure));

  return jsonb_build_object(
    'predecessor_ready',(select count(*) from jsonb_each(v_predecessor))=20
      and not exists(select 1 from jsonb_each(v_predecessor) check_row where check_row.value is distinct from 'true'::jsonb),
    'head_table_ready',to_regclass('public.provider_matchday_progression_gate_heads') is not null,
    'event_table_ready',to_regclass('public.provider_matchday_progression_gate_events') is not null,
    'columns_ready',(select count(*)=17 from information_schema.columns
      where table_schema='public' and table_name='provider_matchday_progression_gate_heads'),
    'constraints_ready',(select count(*)>=8 from pg_catalog.pg_constraint
      where conrelid='public.provider_matchday_progression_gate_heads'::regclass)
      and (select count(*)>=8 from pg_catalog.pg_constraint
      where conrelid='public.provider_matchday_progression_gate_events'::regclass),
    'indexes_ready',to_regclass('public.provider_matchday_progression_gate_heads_league_idx') is not null
      and to_regclass('public.provider_matchday_progression_gate_heads_progression_idx') is not null
      and to_regclass('public.provider_matchday_progression_gate_events_league_idx') is not null,
    'rls_ready',(select relrowsecurity from pg_catalog.pg_class where oid='public.provider_matchday_progression_gate_heads'::regclass)
      and (select relrowsecurity from pg_catalog.pg_class where oid='public.provider_matchday_progression_gate_events'::regclass)
      and exists(select 1 from pg_catalog.pg_policy p where p.polrelid='public.provider_matchday_progression_gate_heads'::regclass
        and p.polname='provider_matchday_progression_gate_heads_director_select')
      and exists(select 1 from pg_catalog.pg_policy p where p.polrelid='public.provider_matchday_progression_gate_events'::regclass
        and p.polname='provider_matchday_progression_gate_events_director_select'),
    'authenticated_write_blocked',not has_table_privilege('authenticated','public.provider_matchday_progression_gate_heads','INSERT')
      and not has_table_privilege('authenticated','public.provider_matchday_progression_gate_heads','UPDATE')
      and not has_table_privilege('authenticated','public.provider_matchday_progression_gate_heads','DELETE')
      and not has_table_privilege('authenticated','public.provider_matchday_progression_gate_events','INSERT')
      and not has_table_privilege('authenticated','public.provider_matchday_progression_gate_events','UPDATE')
      and not has_table_privilege('authenticated','public.provider_matchday_progression_gate_events','DELETE'),
    'service_role_ready',has_table_privilege('service_role','public.provider_matchday_progression_gate_heads','SELECT')
      and has_table_privilege('service_role','public.provider_matchday_progression_gate_heads','INSERT')
      and has_table_privilege('service_role','public.provider_matchday_progression_gate_heads','UPDATE')
      and has_table_privilege('service_role','public.provider_matchday_progression_gate_events','SELECT')
      and has_table_privilege('service_role','public.provider_matchday_progression_gate_events','INSERT'),
    'immutable_events_ready',exists(select 1 from pg_catalog.pg_trigger t
      where t.tgrelid='public.provider_matchday_progression_gate_events'::regclass
        and t.tgname='provider_matchday_progression_gate_events_immutable' and t.tgenabled='A' and not t.tgisinternal),
    'head_guard_ready',exists(select 1 from pg_catalog.pg_trigger t
      where t.tgrelid='public.provider_matchday_progression_gate_heads'::regclass
        and t.tgname='provider_matchday_progression_gate_heads_guard' and t.tgenabled='A' and not t.tgisinternal),
    'compute_rpc_ready',to_regprocedure('public.compute_provider_matchday_progression_gate_v1(uuid,uuid,bigint)') is not null
      and has_function_privilege('service_role','public.compute_provider_matchday_progression_gate_v1(uuid,uuid,bigint)','EXECUTE')
      and position('progression.prior_matchday_chain_unsafe' in v_compute)>0
      and position('progression.officialization_superseded' in v_compute)>0
      and position('completion.completion_status' in v_compute)>0,
    'reconcile_rpc_ready',to_regprocedure('public.reconcile_provider_matchday_progression_gate_v1(uuid,uuid)') is not null
      and has_function_privilege('service_role','public.reconcile_provider_matchday_progression_gate_v1(uuid,uuid)','EXECUTE')
      and position('gate_fingerprint' in v_reconcile)>0,
    'progression_insert_guard_ready',exists(select 1 from pg_catalog.pg_trigger t
      where t.tgrelid='public.matchday_progression_runs'::regclass
        and t.tgname='provider_matchday_progression_gate_insert_guard' and t.tgenabled='A' and not t.tgisinternal)
      and position('provider.progression_gate' in v_guard)>0,
    'impact_lineage_triggers_ready',exists(select 1 from pg_catalog.pg_trigger t
      where t.tgrelid='public.provider_official_result_impact_heads'::regclass
        and t.tgname='provider_matchday_progression_gate_impact_writer' and t.tgenabled='A' and not t.tgisinternal)
      and exists(select 1 from pg_catalog.pg_trigger t
      where t.tgrelid='public.provider_official_result_lineage_heads'::regclass
        and t.tgname='provider_matchday_progression_gate_lineage_writer' and t.tgenabled='A' and not t.tgisinternal),
    'remediation_triggers_ready',exists(select 1 from pg_catalog.pg_trigger t
      where t.tgrelid='public.provider_official_result_remediation_heads'::regclass
        and t.tgname='provider_matchday_progression_gate_remediation_writer' and t.tgenabled='A' and not t.tgisinternal)
      and exists(select 1 from pg_catalog.pg_trigger t
      where t.tgrelid='public.provider_official_result_remediation_completion_heads'::regclass
        and t.tgname='provider_matchday_progression_gate_completion_writer' and t.tgenabled='A' and not t.tgisinternal),
    'fixture_progression_triggers_ready',exists(select 1 from pg_catalog.pg_trigger t
      where t.tgrelid='public.fantasy_fixtures'::regclass
        and t.tgname='provider_matchday_progression_gate_fixture_writer' and t.tgenabled='A' and not t.tgisinternal)
      and exists(select 1 from pg_catalog.pg_trigger t
      where t.tgrelid='public.matchday_progression_runs'::regclass
        and t.tgname='provider_matchday_progression_gate_progression_writer' and t.tgenabled='A' and not t.tgisinternal),
    'backfill_ready',not exists(
      select 1 from (
        select fixture.league_id,fixture.matchday_id
        from public.fantasy_fixtures fixture
        group by fixture.league_id,fixture.matchday_id
        having count(*) filter(where fixture.finalized_at is not null)=count(*)
          or exists(select 1 from public.matchday_progression_runs progression
            where progression.league_id=fixture.league_id and progression.matchday_id=fixture.matchday_id)
      ) eligible
      left join public.provider_matchday_progression_gate_heads head
        on head.league_id=eligible.league_id and head.matchday_id=eligible.matchday_id
      where head.id is null
    ),
    'center_health_ready',to_regprocedure('public.get_league_provider_matchday_progression_gate_v1(uuid)') is not null
      and has_function_privilege('authenticated','public.get_league_provider_matchday_progression_gate_v1(uuid)','EXECUTE')
      and position('unsafeprogressioncount' in replace(v_center,'_',''))>0
      and to_regprocedure('public.get_league_provider_sync_health_v25(uuid)') is not null
      and has_function_privilege('authenticated','public.get_league_provider_sync_health_v25(uuid)','EXECUTE')
      and position('matchdayprogressiongate' in replace(v_health,'_',''))>0,
    'realtime_events_ready',exists(select 1 from pg_catalog.pg_publication_tables
      where pubname='supabase_realtime' and schemaname='public'
        and tablename='provider_matchday_progression_gate_events')
      and not exists(select 1 from pg_catalog.pg_publication_tables
      where pubname='supabase_realtime' and schemaname='public'
        and tablename='provider_matchday_progression_gate_heads')
  );
end;
$function$;
revoke all on function public.get_provider_matchday_progression_gate_integrity_v1() from public,anon,authenticated,service_role;
grant execute on function public.get_provider_matchday_progression_gate_integrity_v1() to service_role;

-- Validazione transazionale: esattamente 20 controlli booleani true.
do $validation$
declare
  v_checks jsonb;
  v_false text;
  v_count integer;
begin
  v_checks:=public.get_provider_matchday_progression_gate_integrity_v1();
  select count(*) into v_count from jsonb_each(v_checks);
  select string_agg(check_row.key,', ' order by check_row.key) into v_false
  from jsonb_each(v_checks) check_row
  where jsonb_typeof(check_row.value) is distinct from 'boolean'
     or check_row.value is distinct from 'true'::jsonb;
  if v_count<>20 then
    raise exception 'Validazione v0.62.26 non superata. Numero controlli atteso 20, rilevato %.',v_count;
  end if;
  if v_false is not null then
    raise exception 'Validazione v0.62.26 non superata. Controlli falsi: %',v_false;
  end if;
end;
$validation$;

commit;

-- Diagnostica finale: devono comparire esattamente 20 valori true.
select
  (checks->>'predecessor_ready')::boolean as predecessor_ready,
  (checks->>'head_table_ready')::boolean as head_table_ready,
  (checks->>'event_table_ready')::boolean as event_table_ready,
  (checks->>'columns_ready')::boolean as columns_ready,
  (checks->>'constraints_ready')::boolean as constraints_ready,
  (checks->>'indexes_ready')::boolean as indexes_ready,
  (checks->>'rls_ready')::boolean as rls_ready,
  (checks->>'authenticated_write_blocked')::boolean as authenticated_write_blocked,
  (checks->>'service_role_ready')::boolean as service_role_ready,
  (checks->>'immutable_events_ready')::boolean as immutable_events_ready,
  (checks->>'head_guard_ready')::boolean as head_guard_ready,
  (checks->>'compute_rpc_ready')::boolean as compute_rpc_ready,
  (checks->>'reconcile_rpc_ready')::boolean as reconcile_rpc_ready,
  (checks->>'progression_insert_guard_ready')::boolean as progression_insert_guard_ready,
  (checks->>'impact_lineage_triggers_ready')::boolean as impact_lineage_triggers_ready,
  (checks->>'remediation_triggers_ready')::boolean as remediation_triggers_ready,
  (checks->>'fixture_progression_triggers_ready')::boolean as fixture_progression_triggers_ready,
  (checks->>'backfill_ready')::boolean as backfill_ready,
  (checks->>'center_health_ready')::boolean as center_health_ready,
  (checks->>'realtime_events_ready')::boolean as realtime_events_ready
from (select public.get_provider_matchday_progression_gate_integrity_v1() as checks) diagnostic;
