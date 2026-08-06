-- LEGHEVO v0.62.27
-- Barriera causale certificata della chiusura stagione provider.
-- Migrazione interna: database/131_provider_season_completion_causal_barrier_safety.sql
-- Eseguire dopo database/130_provider_matchday_progression_causal_barrier_safety.sql.
-- La migrazione non riapre, annulla o modifica automaticamente stagioni già concluse.

begin;

-- PRE-FLIGHT: dipendenze reali e firme complete.
do $preflight$
declare
  v_missing text[] := array[]::text[];
  v_checks jsonb;
begin
  if to_regprocedure('public.get_provider_matchday_progression_gate_integrity_v1()') is null then
    v_missing := array_append(v_missing,
      'function public.get_provider_matchday_progression_gate_integrity_v1()');
  else
    v_checks := public.get_provider_matchday_progression_gate_integrity_v1();
    if (select count(*) from jsonb_each(v_checks)) <> 20
      or exists (
        select 1
        from jsonb_each(v_checks) check_row
        where jsonb_typeof(check_row.value) is distinct from 'boolean'
           or check_row.value is distinct from 'true'::jsonb
      ) then
      v_missing := array_append(v_missing,
        'v0.62.26 integrity: all 20 checks must be true');
    end if;
  end if;

  if to_regclass('public.season_completion_runs') is null then
    v_missing := array_append(v_missing,'table public.season_completion_runs');
  end if;
  if to_regclass('public.matchday_progression_runs') is null then
    v_missing := array_append(v_missing,'table public.matchday_progression_runs');
  end if;
  if to_regclass('public.provider_matchday_progression_gate_heads') is null then
    v_missing := array_append(v_missing,
      'table public.provider_matchday_progression_gate_heads');
  end if;

  if exists (
    select 1
    from (values
      ('leagues','id'),('leagues','owner_id'),('leagues','status'),
      ('matchdays','id'),('matchdays','number'),
      ('fantasy_fixtures','id'),('fantasy_fixtures','league_id'),
      ('fantasy_fixtures','matchday_id'),
      ('matchday_progression_runs','id'),
      ('matchday_progression_runs','league_id'),
      ('matchday_progression_runs','matchday_id'),
      ('matchday_progression_runs','officialization_run_id'),
      ('matchday_progression_runs','progression_revision'),
      ('matchday_progression_runs','progressed_at'),
      ('matchday_progression_runs','season_ready_to_complete'),
      ('matchday_progression_runs','standings_hash'),
      ('matchday_progression_runs','standings_snapshot'),
      ('matchday_progression_runs','superseded_at'),
      ('provider_matchday_progression_gate_heads','id'),
      ('provider_matchday_progression_gate_heads','league_id'),
      ('provider_matchday_progression_gate_heads','matchday_id'),
      ('provider_matchday_progression_gate_heads','gate_status'),
      ('provider_matchday_progression_gate_heads','current_officialization_run_id'),
      ('provider_matchday_progression_gate_heads','current_progression_run_id'),
      ('provider_matchday_progression_gate_heads','gate_fingerprint'),
      ('season_completion_runs','id'),
      ('season_completion_runs','league_id'),
      ('season_completion_runs','request_id'),
      ('season_completion_runs','final_matchday_id'),
      ('season_completion_runs','final_progression_run_id'),
      ('season_completion_runs','final_officialization_run_id'),
      ('season_completion_runs','result_payload')
    ) required(table_name,column_name)
    where not exists (
      select 1
      from information_schema.columns column_row
      where column_row.table_schema='public'
        and column_row.table_name=required.table_name
        and column_row.column_name=required.column_name
    )
  ) then
    v_missing := array_append(v_missing,
      'required columns for provider season completion barrier');
  end if;

  if to_regprocedure('public.complete_league_season_guarded_v1(uuid,uuid)') is null then
    v_missing := array_append(v_missing,
      'RPC public.complete_league_season_guarded_v1(uuid,uuid)');
  end if;
  if to_regprocedure('public.get_league_season_state_v4(uuid)') is null then
    v_missing := array_append(v_missing,
      'RPC public.get_league_season_state_v4(uuid)');
  end if;
  if to_regprocedure('public.get_league_management_state_v14(uuid)') is null then
    v_missing := array_append(v_missing,
      'RPC public.get_league_management_state_v14(uuid)');
  end if;
  if to_regprocedure('public.get_league_provider_sync_health_v25(uuid)') is null then
    v_missing := array_append(v_missing,
      'RPC public.get_league_provider_sync_health_v25(uuid)');
  end if;
  if to_regprocedure('auth.uid()') is null then
    v_missing := array_append(v_missing,'function auth.uid()');
  end if;
  if to_regprocedure('public.is_league_member(uuid)') is null then
    v_missing := array_append(v_missing,'function public.is_league_member(uuid)');
  end if;
  if to_regprocedure('public.is_league_admin(uuid)') is null then
    v_missing := array_append(v_missing,'function public.is_league_admin(uuid)');
  end if;
  if to_regprocedure('pg_catalog.md5(text)') is null then
    v_missing := array_append(v_missing,'function pg_catalog.md5(text)');
  end if;
  if to_regprocedure('pg_catalog.hashtextextended(text,bigint)') is null then
    v_missing := array_append(v_missing,
      'function pg_catalog.hashtextextended(text,bigint)');
  end if;
  if to_regprocedure('pg_catalog.pg_advisory_xact_lock(bigint)') is null then
    v_missing := array_append(v_missing,
      'function pg_catalog.pg_advisory_xact_lock(bigint)');
  end if;
  if to_regprocedure('pg_catalog.gen_random_uuid()') is null then
    v_missing := array_append(v_missing,
      'function pg_catalog.gen_random_uuid()');
  end if;

  if cardinality(v_missing) > 0 then
    raise exception
      'Preflight v0.62.27 non superato. Dipendenze mancanti: %',
      array_to_string(v_missing,'; ');
  end if;
end;
$preflight$;

create table if not exists public.provider_season_completion_gate_heads (
  id uuid primary key default gen_random_uuid(),
  league_id uuid not null unique
    references public.leagues(id) on delete cascade,
  current_completion_run_id bigint
    references public.season_completion_runs(id) on delete set null,
  final_matchday_id uuid
    references public.matchdays(id) on delete set null,
  final_progression_run_id bigint
    references public.matchday_progression_runs(id) on delete set null,
  gate_status text not null,
  reason_code text not null,
  matchday_count integer not null default 0,
  clear_matchday_count integer not null default 0,
  unsafe_matchday_count integer not null default 0,
  missing_gate_count integer not null default 0,
  mismatched_progression_count integer not null default 0,
  gate_generation bigint not null default 1,
  gate_fingerprint text not null,
  first_unsafe_at timestamptz,
  last_assessed_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint provider_season_completion_gate_heads_status_check
    check (gate_status in ('clear','blocked','affected')),
  constraint provider_season_completion_gate_heads_reason_check
    check (char_length(trim(reason_code)) between 3 and 180),
  constraint provider_season_completion_gate_heads_counts_check
    check (
      matchday_count >= 0
      and clear_matchday_count >= 0
      and unsafe_matchday_count >= 0
      and missing_gate_count >= 0
      and mismatched_progression_count >= 0
      and clear_matchday_count + unsafe_matchday_count = matchday_count
      and missing_gate_count <= unsafe_matchday_count
      and mismatched_progression_count <= unsafe_matchday_count
    ),
  constraint provider_season_completion_gate_heads_generation_check
    check (gate_generation >= 1),
  constraint provider_season_completion_gate_heads_fingerprint_check
    check (length(gate_fingerprint) = 32)
);

create table if not exists public.provider_season_completion_gate_events (
  id bigint generated by default as identity primary key,
  head_id uuid not null
    references public.provider_season_completion_gate_heads(id) on delete restrict,
  league_id uuid not null
    references public.leagues(id) on delete cascade,
  event_type text not null,
  gate_status text not null,
  reason_code text not null,
  gate_generation bigint not null,
  current_completion_run_id bigint
    references public.season_completion_runs(id) on delete set null,
  final_matchday_id uuid
    references public.matchdays(id) on delete set null,
  final_progression_run_id bigint
    references public.matchday_progression_runs(id) on delete set null,
  matchday_count integer not null,
  clear_matchday_count integer not null,
  unsafe_matchday_count integer not null,
  missing_gate_count integer not null,
  mismatched_progression_count integer not null,
  gate_fingerprint text not null,
  created_at timestamptz not null default now(),
  constraint provider_season_completion_gate_events_type_check
    check (event_type in ('clear','blocked','affected','revalidated')),
  constraint provider_season_completion_gate_events_status_check
    check (gate_status in ('clear','blocked','affected')),
  constraint provider_season_completion_gate_events_reason_check
    check (char_length(trim(reason_code)) between 3 and 180),
  constraint provider_season_completion_gate_events_generation_check
    check (gate_generation >= 1),
  constraint provider_season_completion_gate_events_counts_check
    check (
      matchday_count >= 0
      and clear_matchday_count >= 0
      and unsafe_matchday_count >= 0
      and missing_gate_count >= 0
      and mismatched_progression_count >= 0
      and clear_matchday_count + unsafe_matchday_count = matchday_count
      and missing_gate_count <= unsafe_matchday_count
      and mismatched_progression_count <= unsafe_matchday_count
    ),
  constraint provider_season_completion_gate_events_fingerprint_check
    check (length(gate_fingerprint) = 32)
);

create index if not exists provider_season_completion_gate_heads_status_idx
  on public.provider_season_completion_gate_heads(gate_status,updated_at desc);
create index if not exists provider_season_completion_gate_heads_completion_idx
  on public.provider_season_completion_gate_heads(current_completion_run_id)
  where current_completion_run_id is not null;
create index if not exists provider_season_completion_gate_events_league_idx
  on public.provider_season_completion_gate_events(league_id,created_at desc);

alter table public.provider_season_completion_gate_heads enable row level security;
alter table public.provider_season_completion_gate_events enable row level security;
alter table public.provider_season_completion_gate_events replica identity full;

revoke all on table public.provider_season_completion_gate_heads
from public,anon,authenticated,service_role;
revoke all on table public.provider_season_completion_gate_events
from public,anon,authenticated,service_role;
grant select on table public.provider_season_completion_gate_heads to authenticated;
grant select on table public.provider_season_completion_gate_events to authenticated;
grant select,insert,update on table public.provider_season_completion_gate_heads to service_role;
grant select,insert on table public.provider_season_completion_gate_events to service_role;

drop policy if exists provider_season_completion_gate_heads_director_select
on public.provider_season_completion_gate_heads;
create policy provider_season_completion_gate_heads_director_select
on public.provider_season_completion_gate_heads
for select to authenticated
using (
  public.is_league_member(league_id)
  or public.is_league_admin(league_id)
);

drop policy if exists provider_season_completion_gate_events_director_select
on public.provider_season_completion_gate_events;
create policy provider_season_completion_gate_events_director_select
on public.provider_season_completion_gate_events
for select to authenticated
using (
  public.is_league_member(league_id)
  or public.is_league_admin(league_id)
);

create or replace function public.prevent_provider_season_completion_gate_head_mutation_v1()
returns trigger
language plpgsql
security definer
set search_path=''
as $function$
begin
  if current_setting('leghevo.provider_season_completion_gate_context',true)
    is distinct from 'on' then
    raise exception
      'Barriera chiusura stagione provider: modifica diretta non consentita.';
  end if;
  if tg_op='DELETE' then return old; end if;
  return new;
end;
$function$;
revoke all on function public.prevent_provider_season_completion_gate_head_mutation_v1()
from public,anon,authenticated;

drop trigger if exists provider_season_completion_gate_heads_guard
on public.provider_season_completion_gate_heads;
create trigger provider_season_completion_gate_heads_guard
before insert or update or delete on public.provider_season_completion_gate_heads
for each row execute function public.prevent_provider_season_completion_gate_head_mutation_v1();
alter table public.provider_season_completion_gate_heads
  enable always trigger provider_season_completion_gate_heads_guard;

create or replace function public.prevent_provider_season_completion_gate_event_mutation_v1()
returns trigger
language plpgsql
security definer
set search_path=''
as $function$
begin
  raise exception
    'Storico barriera chiusura stagione provider: modifica non consentita.';
end;
$function$;
revoke all on function public.prevent_provider_season_completion_gate_event_mutation_v1()
from public,anon,authenticated;

drop trigger if exists provider_season_completion_gate_events_immutable
on public.provider_season_completion_gate_events;
create trigger provider_season_completion_gate_events_immutable
before update or delete on public.provider_season_completion_gate_events
for each row execute function public.prevent_provider_season_completion_gate_event_mutation_v1();
alter table public.provider_season_completion_gate_events
  enable always trigger provider_season_completion_gate_events_immutable;

create or replace function public.compute_provider_season_completion_gate_v1(
  p_league_id uuid,
  p_expected_final_progression_run_id bigint default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $function$
declare
  v_league_status text;
  v_completion_run_id bigint;
  v_completion_final_matchday_id uuid;
  v_completion_final_progression_run_id bigint;
  v_matchday_count integer := 0;
  v_progression_count integer := 0;
  v_clear_matchday_count integer := 0;
  v_unsafe_matchday_count integer := 0;
  v_missing_gate_count integer := 0;
  v_mismatched_progression_count integer := 0;
  v_final_matchday_id uuid;
  v_final_matchday_number smallint;
  v_final_progression_run_id bigint;
  v_final_progression_ready boolean := false;
  v_final_progression_hash_valid boolean := false;
  v_status text := 'blocked';
  v_reason text := 'season_completion.calendar_unavailable';
  v_chain_material text := '';
  v_chain_hash text;
  v_fingerprint text;
  v_row record;
begin
  select league_row.status
  into v_league_status
  from public.leagues league_row
  where league_row.id=p_league_id;

  if not found then
    return jsonb_build_object(
      'available',false,
      'reasonCode','season_completion.league_not_found'
    );
  end if;

  select
    completion.id,
    completion.final_matchday_id,
    completion.final_progression_run_id
  into
    v_completion_run_id,
    v_completion_final_matchday_id,
    v_completion_final_progression_run_id
  from public.season_completion_runs completion
  where completion.league_id=p_league_id;

  for v_row in
    select
      matchday.id as matchday_id,
      matchday.number as matchday_number,
      progression.id as progression_run_id,
      progression.officialization_run_id,
      progression.season_ready_to_complete,
      progression.standings_hash,
      progression.standings_snapshot,
      gate.id as gate_head_id,
      gate.gate_status,
      gate.current_officialization_run_id as gate_officialization_run_id,
      gate.current_progression_run_id as gate_progression_run_id,
      gate.gate_fingerprint
    from (
      select distinct fixture.matchday_id
      from public.fantasy_fixtures fixture
      where fixture.league_id=p_league_id
    ) fixture_matchday
    join public.matchdays matchday
      on matchday.id=fixture_matchday.matchday_id
    left join lateral (
      select progression_row.*
      from public.matchday_progression_runs progression_row
      where progression_row.league_id=p_league_id
        and progression_row.matchday_id=matchday.id
        and progression_row.superseded_at is null
      order by progression_row.progressed_at desc,
        progression_row.progression_revision desc,
        progression_row.id desc
      limit 1
    ) progression on true
    left join public.provider_matchday_progression_gate_heads gate
      on gate.league_id=p_league_id
      and gate.matchday_id=matchday.id
    order by matchday.number,matchday.id
  loop
    v_matchday_count := v_matchday_count + 1;
    if v_row.progression_run_id is not null then
      v_progression_count := v_progression_count + 1;
    end if;

    if v_row.gate_head_id is null then
      v_missing_gate_count := v_missing_gate_count + 1;
      v_unsafe_matchday_count := v_unsafe_matchday_count + 1;
    elsif v_row.progression_run_id is null then
      v_mismatched_progression_count := v_mismatched_progression_count + 1;
      v_unsafe_matchday_count := v_unsafe_matchday_count + 1;
    elsif v_row.gate_status <> 'clear' then
      v_unsafe_matchday_count := v_unsafe_matchday_count + 1;
    elsif v_row.gate_progression_run_id is distinct from v_row.progression_run_id
      or v_row.gate_officialization_run_id
        is distinct from v_row.officialization_run_id then
      v_mismatched_progression_count := v_mismatched_progression_count + 1;
      v_unsafe_matchday_count := v_unsafe_matchday_count + 1;
    else
      v_clear_matchday_count := v_clear_matchday_count + 1;
    end if;

    v_chain_material := v_chain_material || concat_ws(':',
      v_row.matchday_id::text,
      v_row.matchday_number::text,
      coalesce(v_row.progression_run_id::text,'-'),
      coalesce(v_row.officialization_run_id::text,'-'),
      coalesce(v_row.gate_progression_run_id::text,'-'),
      coalesce(v_row.gate_officialization_run_id::text,'-'),
      coalesce(v_row.gate_status,'missing'),
      coalesce(v_row.gate_fingerprint,'-')
    ) || '|';

    v_final_matchday_id := v_row.matchday_id;
    v_final_matchday_number := v_row.matchday_number;
    v_final_progression_run_id := v_row.progression_run_id;
    v_final_progression_ready :=
      coalesce(v_row.season_ready_to_complete,false);
    v_final_progression_hash_valid :=
      v_row.progression_run_id is not null
      and v_row.standings_hash
        = pg_catalog.md5(v_row.standings_snapshot::text);
  end loop;

  if v_matchday_count=0 then
    v_status := case when v_completion_run_id is null
      then 'blocked' else 'affected' end;
    v_reason := 'season_completion.no_matchdays';
  elsif v_progression_count<>v_matchday_count then
    v_status := case when v_completion_run_id is null
      then 'blocked' else 'affected' end;
    v_reason := 'season_completion.progression_chain_incomplete';
  elsif v_missing_gate_count>0 then
    v_status := case when v_completion_run_id is null
      then 'blocked' else 'affected' end;
    v_reason := 'season_completion.progression_gate_missing';
  elsif v_mismatched_progression_count>0 then
    v_status := case when v_completion_run_id is null
      then 'blocked' else 'affected' end;
    v_reason := 'season_completion.progression_generation_mismatch';
  elsif v_unsafe_matchday_count>0 then
    v_status := case when v_completion_run_id is null
      then 'blocked' else 'affected' end;
    v_reason := 'season_completion.progression_chain_unsafe';
  elsif v_final_progression_run_id is null then
    v_status := case when v_completion_run_id is null
      then 'blocked' else 'affected' end;
    v_reason := 'season_completion.final_progression_missing';
  elsif p_expected_final_progression_run_id is not null
    and v_final_progression_run_id
      <> p_expected_final_progression_run_id then
    v_status := 'blocked';
    v_reason := 'season_completion.final_progression_changed_before_commit';
  elsif not v_final_progression_ready then
    v_status := case when v_completion_run_id is null
      then 'blocked' else 'affected' end;
    v_reason := 'season_completion.final_progression_not_ready';
  elsif not v_final_progression_hash_valid then
    v_status := case when v_completion_run_id is null
      then 'blocked' else 'affected' end;
    v_reason := 'season_completion.final_standings_integrity_failed';
  elsif v_completion_run_id is not null
    and v_completion_final_matchday_id
      is distinct from v_final_matchday_id then
    v_status := 'affected';
    v_reason := 'season_completion.final_matchday_superseded';
  elsif v_completion_run_id is not null
    and v_completion_final_progression_run_id
      is distinct from v_final_progression_run_id then
    v_status := 'affected';
    v_reason := 'season_completion.final_progression_superseded';
  else
    v_status := 'clear';
    v_reason := 'season_completion.causal_chain_certified';
  end if;

  v_chain_hash := pg_catalog.md5(v_chain_material);
  v_fingerprint := pg_catalog.md5(jsonb_build_object(
    'leagueId',p_league_id,
    'leagueStatus',v_league_status,
    'completionRunId',v_completion_run_id,
    'completionFinalMatchdayId',v_completion_final_matchday_id,
    'completionFinalProgressionRunId',v_completion_final_progression_run_id,
    'finalMatchdayId',v_final_matchday_id,
    'finalMatchdayNumber',v_final_matchday_number,
    'finalProgressionRunId',v_final_progression_run_id,
    'expectedFinalProgressionRunId',p_expected_final_progression_run_id,
    'gateStatus',v_status,
    'reasonCode',v_reason,
    'matchdayCount',v_matchday_count,
    'clearMatchdayCount',v_clear_matchday_count,
    'unsafeMatchdayCount',v_unsafe_matchday_count,
    'missingGateCount',v_missing_gate_count,
    'mismatchedProgressionCount',v_mismatched_progression_count,
    'chainHash',v_chain_hash
  )::text);

  return jsonb_build_object(
    'available',true,
    'leagueId',p_league_id,
    'leagueStatus',v_league_status,
    'gateStatus',v_status,
    'reasonCode',v_reason,
    'currentCompletionRunId',v_completion_run_id,
    'finalMatchdayId',v_final_matchday_id,
    'finalMatchdayNumber',v_final_matchday_number,
    'finalProgressionRunId',v_final_progression_run_id,
    'matchdayCount',v_matchday_count,
    'clearMatchdayCount',v_clear_matchday_count,
    'unsafeMatchdayCount',v_unsafe_matchday_count,
    'missingGateCount',v_missing_gate_count,
    'mismatchedProgressionCount',v_mismatched_progression_count,
    'finalProgressionReady',v_final_progression_ready,
    'finalProgressionHashValid',v_final_progression_hash_valid,
    'gateFingerprint',v_fingerprint
  );
end;
$function$;
revoke all on function public.compute_provider_season_completion_gate_v1(uuid,bigint)
from public,anon,authenticated;
grant execute on function public.compute_provider_season_completion_gate_v1(uuid,bigint)
to service_role;

create or replace function public.reconcile_provider_season_completion_gate_v1(
  p_league_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_assessment jsonb;
  v_existing public.provider_season_completion_gate_heads%rowtype;
  v_head public.provider_season_completion_gate_heads%rowtype;
  v_changed boolean := false;
  v_generation bigint := 1;
  v_event_type text;
begin
  -- Il lock causale comune viene acquisito prima della fotografia del gate:
  -- nessuna progressione o testa provider può cambiare durante il calcolo.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'provider-season-completion-chain:'||p_league_id::text,0
    )
  );
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'provider-season-completion-gate:'||p_league_id::text,0
    )
  );

  v_assessment := public.compute_provider_season_completion_gate_v1(
    p_league_id,null
  );
  if not coalesce((v_assessment->>'available')::boolean,false) then
    return v_assessment;
  end if;

  select head.*
  into v_existing
  from public.provider_season_completion_gate_heads head
  where head.league_id=p_league_id
  for update;

  v_changed := v_existing.id is null
    or v_existing.gate_fingerprint
      is distinct from v_assessment->>'gateFingerprint'
    or v_existing.gate_status
      is distinct from v_assessment->>'gateStatus'
    or v_existing.reason_code
      is distinct from v_assessment->>'reasonCode'
    or v_existing.current_completion_run_id is distinct from
      nullif(v_assessment->>'currentCompletionRunId','')::bigint
    or v_existing.final_matchday_id is distinct from
      nullif(v_assessment->>'finalMatchdayId','')::uuid
    or v_existing.final_progression_run_id is distinct from
      nullif(v_assessment->>'finalProgressionRunId','')::bigint;

  v_generation := case
    when v_existing.id is null then 1
    when v_changed then v_existing.gate_generation+1
    else v_existing.gate_generation
  end;

  perform set_config(
    'leghevo.provider_season_completion_gate_context','on',true
  );

  insert into public.provider_season_completion_gate_heads(
    league_id,current_completion_run_id,final_matchday_id,
    final_progression_run_id,gate_status,reason_code,matchday_count,
    clear_matchday_count,unsafe_matchday_count,missing_gate_count,
    mismatched_progression_count,gate_generation,gate_fingerprint,
    first_unsafe_at,last_assessed_at,updated_at
  ) values (
    p_league_id,
    nullif(v_assessment->>'currentCompletionRunId','')::bigint,
    nullif(v_assessment->>'finalMatchdayId','')::uuid,
    nullif(v_assessment->>'finalProgressionRunId','')::bigint,
    v_assessment->>'gateStatus',
    v_assessment->>'reasonCode',
    (v_assessment->>'matchdayCount')::integer,
    (v_assessment->>'clearMatchdayCount')::integer,
    (v_assessment->>'unsafeMatchdayCount')::integer,
    (v_assessment->>'missingGateCount')::integer,
    (v_assessment->>'mismatchedProgressionCount')::integer,
    v_generation,
    v_assessment->>'gateFingerprint',
    case when v_assessment->>'gateStatus'='clear' then null else now() end,
    now(),now()
  )
  on conflict(league_id) do update set
    current_completion_run_id=excluded.current_completion_run_id,
    final_matchday_id=excluded.final_matchday_id,
    final_progression_run_id=excluded.final_progression_run_id,
    gate_status=excluded.gate_status,
    reason_code=excluded.reason_code,
    matchday_count=excluded.matchday_count,
    clear_matchday_count=excluded.clear_matchday_count,
    unsafe_matchday_count=excluded.unsafe_matchday_count,
    missing_gate_count=excluded.missing_gate_count,
    mismatched_progression_count=excluded.mismatched_progression_count,
    gate_generation=excluded.gate_generation,
    gate_fingerprint=excluded.gate_fingerprint,
    first_unsafe_at=case
      when public.provider_season_completion_gate_heads.first_unsafe_at
        is not null
        then public.provider_season_completion_gate_heads.first_unsafe_at
      when excluded.gate_status<>'clear' then now()
      else null
    end,
    last_assessed_at=now(),
    updated_at=case when v_changed then now()
      else public.provider_season_completion_gate_heads.updated_at end
  returning * into v_head;

  if v_changed then
    v_event_type := case
      when v_head.gate_status='clear' and v_existing.id is not null
        then 'revalidated'
      else v_head.gate_status
    end;

    insert into public.provider_season_completion_gate_events(
      head_id,league_id,event_type,gate_status,reason_code,
      gate_generation,current_completion_run_id,final_matchday_id,
      final_progression_run_id,matchday_count,clear_matchday_count,
      unsafe_matchday_count,missing_gate_count,
      mismatched_progression_count,gate_fingerprint
    ) values (
      v_head.id,v_head.league_id,v_event_type,v_head.gate_status,
      v_head.reason_code,v_head.gate_generation,
      v_head.current_completion_run_id,v_head.final_matchday_id,
      v_head.final_progression_run_id,v_head.matchday_count,
      v_head.clear_matchday_count,v_head.unsafe_matchday_count,
      v_head.missing_gate_count,v_head.mismatched_progression_count,
      v_head.gate_fingerprint
    );
  end if;

  perform set_config(
    'leghevo.provider_season_completion_gate_context','',true
  );

  return v_assessment || jsonb_build_object(
    'gateGeneration',v_head.gate_generation,
    'changed',v_changed
  );
end;
$function$;
revoke all on function public.reconcile_provider_season_completion_gate_v1(uuid)
from public,anon,authenticated;
grant execute on function public.reconcile_provider_season_completion_gate_v1(uuid)
to service_role;

-- Lock comune tra progressione e chiusura: impedisce un commit su una catena
-- che cambia nello stesso intervallo transazionale.
create or replace function public.lock_provider_season_completion_chain_v1()
returns trigger
language plpgsql
security definer
set search_path=''
as $function$
begin
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'provider-season-completion-chain:'||new.league_id::text,0
    )
  );
  return new;
end;
$function$;
revoke all on function public.lock_provider_season_completion_chain_v1()
from public,anon,authenticated;

drop trigger if exists provider_season_completion_progression_chain_lock
on public.matchday_progression_runs;
create trigger provider_season_completion_progression_chain_lock
before insert or update on public.matchday_progression_runs
for each row execute function public.lock_provider_season_completion_chain_v1();
alter table public.matchday_progression_runs
  enable always trigger provider_season_completion_progression_chain_lock;

drop trigger if exists provider_season_completion_progression_head_chain_lock
on public.provider_matchday_progression_gate_heads;
create trigger provider_season_completion_progression_head_chain_lock
before insert or update on public.provider_matchday_progression_gate_heads
for each row execute function public.lock_provider_season_completion_chain_v1();
alter table public.provider_matchday_progression_gate_heads
  enable always trigger provider_season_completion_progression_head_chain_lock;

create or replace function public.enforce_provider_season_completion_gate_v1()
returns trigger
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_gate jsonb;
begin
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'provider-season-completion-chain:'||new.league_id::text,0
    )
  );

  v_gate := public.compute_provider_season_completion_gate_v1(
    new.league_id,new.final_progression_run_id
  );

  if not coalesce((v_gate->>'available')::boolean,false)
    or coalesce(v_gate->>'gateStatus','blocked')<>'clear'
    or nullif(v_gate->>'finalMatchdayId','')::uuid
      is distinct from new.final_matchday_id
    or nullif(v_gate->>'finalProgressionRunId','')::bigint
      is distinct from new.final_progression_run_id then
    raise exception
      'Chiusura stagione rifiutata [provider.season_completion_gate]: %',
      coalesce(v_gate->>'reasonCode','season_completion.unknown');
  end if;

  return new;
end;
$function$;
revoke all on function public.enforce_provider_season_completion_gate_v1()
from public,anon,authenticated;

drop trigger if exists provider_season_completion_insert_guard
on public.season_completion_runs;
create trigger provider_season_completion_insert_guard
before insert on public.season_completion_runs
for each row execute function public.enforce_provider_season_completion_gate_v1();
alter table public.season_completion_runs
  enable always trigger provider_season_completion_insert_guard;

create or replace function public.complete_league_season_guarded_v2(
  p_league_id uuid,
  p_request_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_gate jsonb;
  v_existing bigint;
begin
  if auth.uid() is null then
    raise exception 'Devi effettuare l''accesso.';
  end if;

  select completion.id
  into v_existing
  from public.season_completion_runs completion
  where completion.league_id=p_league_id
     or completion.request_id=p_request_id
  order by (completion.league_id=p_league_id) desc
  limit 1;

  if found then
    return public.complete_league_season_guarded_v1(
      p_league_id,p_request_id
    );
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'season-completion:'||p_league_id::text,0
    )
  );
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'provider-season-completion-chain:'||p_league_id::text,0
    )
  );

  v_gate := public.compute_provider_season_completion_gate_v1(
    p_league_id,null
  );

  if not coalesce((v_gate->>'available')::boolean,false)
    or coalesce(v_gate->>'gateStatus','blocked')<>'clear' then
    raise exception
      'Chiusura stagione rifiutata [provider.season_completion_gate]: %',
      coalesce(v_gate->>'reasonCode','season_completion.unknown');
  end if;

  return public.complete_league_season_guarded_v1(
    p_league_id,p_request_id
  );
end;
$function$;
revoke all on function public.complete_league_season_guarded_v2(uuid,uuid)
from public,anon,service_role;
grant execute on function public.complete_league_season_guarded_v2(uuid,uuid)
to authenticated;

create or replace function public.reconcile_provider_season_completion_from_progression_v1()
returns trigger
language plpgsql
security definer
set search_path=''
as $function$
begin
  perform public.reconcile_provider_season_completion_gate_v1(new.league_id);
  return new;
end;
$function$;
revoke all on function public.reconcile_provider_season_completion_from_progression_v1()
from public,anon,authenticated;

drop trigger if exists provider_season_completion_progression_writer
on public.provider_matchday_progression_gate_heads;
create trigger provider_season_completion_progression_writer
after insert or update of gate_status,gate_generation,current_progression_run_id,
  current_officialization_run_id,gate_fingerprint
on public.provider_matchday_progression_gate_heads
for each row execute function public.reconcile_provider_season_completion_from_progression_v1();
alter table public.provider_matchday_progression_gate_heads
  enable always trigger provider_season_completion_progression_writer;

create or replace function public.reconcile_provider_season_completion_from_run_v1()
returns trigger
language plpgsql
security definer
set search_path=''
as $function$
begin
  perform public.reconcile_provider_season_completion_gate_v1(new.league_id);
  return new;
end;
$function$;
revoke all on function public.reconcile_provider_season_completion_from_run_v1()
from public,anon,authenticated;

drop trigger if exists provider_season_completion_run_writer
on public.season_completion_runs;
create trigger provider_season_completion_run_writer
after insert on public.season_completion_runs
for each row execute function public.reconcile_provider_season_completion_from_run_v1();
alter table public.season_completion_runs
  enable always trigger provider_season_completion_run_writer;

-- Backfill non distruttivo: crea soltanto certificati; non cambia stagioni,
-- classifiche, risultati o progressioni.
do $backfill$
declare
  v_row record;
begin
  for v_row in
    select distinct league_row.id as league_id
    from public.leagues league_row
    where exists (
      select 1
      from public.fantasy_fixtures fixture
      where fixture.league_id=league_row.id
    )
       or exists (
      select 1
      from public.season_completion_runs completion
      where completion.league_id=league_row.id
    )
    order by league_row.id
  loop
    perform public.reconcile_provider_season_completion_gate_v1(
      v_row.league_id
    );
  end loop;
end;
$backfill$;

create or replace function public.get_league_season_state_v5(
  p_league_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $function$
declare
  v_state jsonb;
  v_gate jsonb;
  v_gate_status text;
  v_completion_run_id bigint;
begin
  v_state := public.get_league_season_state_v4(p_league_id);
  v_gate := public.compute_provider_season_completion_gate_v1(
    p_league_id,null
  );
  v_gate_status := coalesce(v_gate->>'gateStatus','blocked');
  v_completion_run_id :=
    nullif(v_gate->>'currentCompletionRunId','')::bigint;

  return v_state || jsonb_build_object(
    'canComplete',
      coalesce((v_state->>'canComplete')::boolean,false)
      and v_gate_status='clear',
    'seasonCompletionCausalStatus',v_gate_status,
    'seasonCompletionCausalReason',v_gate->>'reasonCode',
    'seasonCompletionCausallyCertified',v_gate_status='clear',
    'seasonCompletionAffected',
      v_completion_run_id is not null and v_gate_status='affected',
    'seasonCompletionGate',v_gate
  );
end;
$function$;
revoke all on function public.get_league_season_state_v5(uuid)
from public,anon,service_role;
grant execute on function public.get_league_season_state_v5(uuid)
to authenticated;

create or replace function public.get_league_management_state_v15(
  p_league_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $function$
declare
  v_state jsonb;
  v_season jsonb;
  v_checks jsonb;
begin
  v_state := public.get_league_management_state_v14(p_league_id);
  v_season := public.get_league_season_state_v5(p_league_id);
  v_checks := coalesce(v_state->'checks','{}'::jsonb);

  return v_state || v_season || jsonb_build_object(
    'checks',v_checks || jsonb_build_object(
      'seasonCompletionCausalReady',
        coalesce(
          (v_season->>'seasonCompletionCausallyCertified')::boolean,
          false
        )
    )
  );
end;
$function$;
revoke all on function public.get_league_management_state_v15(uuid)
from public,anon,service_role;
grant execute on function public.get_league_management_state_v15(uuid)
to authenticated;

create or replace function public.get_league_provider_season_completion_gate_v1(
  p_league_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $function$
declare
  v_owner_id uuid;
  v_head public.provider_season_completion_gate_heads%rowtype;
  v_assessment jsonb;
  v_events_24h integer := 0;
  v_latest jsonb;
  v_completion_affected boolean := false;
  v_healthy boolean := true;
begin
  if auth.uid() is null then
    raise exception 'Devi effettuare l''accesso.';
  end if;

  select league_row.owner_id
  into v_owner_id
  from public.leagues league_row
  where league_row.id=p_league_id;

  if not found then
    raise exception
      'Lega non trovata per la barriera di chiusura stagione provider.';
  end if;

  if v_owner_id<>auth.uid() and not public.is_league_admin(p_league_id) then
    raise exception
      'Solo Presidente e Admin possono leggere la barriera di chiusura stagione provider.';
  end if;

  select head.*
  into v_head
  from public.provider_season_completion_gate_heads head
  where head.league_id=p_league_id;

  if not found then
    v_assessment := public.compute_provider_season_completion_gate_v1(
      p_league_id,null
    );
  else
    v_assessment := jsonb_build_object(
      'gateStatus',v_head.gate_status,
      'reasonCode',v_head.reason_code,
      'currentCompletionRunId',v_head.current_completion_run_id,
      'finalMatchdayId',v_head.final_matchday_id,
      'finalProgressionRunId',v_head.final_progression_run_id,
      'matchdayCount',v_head.matchday_count,
      'clearMatchdayCount',v_head.clear_matchday_count,
      'unsafeMatchdayCount',v_head.unsafe_matchday_count,
      'missingGateCount',v_head.missing_gate_count,
      'mismatchedProgressionCount',v_head.mismatched_progression_count,
      'gateGeneration',v_head.gate_generation
    );
  end if;

  select count(*)::integer
  into v_events_24h
  from public.provider_season_completion_gate_events event_row
  where event_row.league_id=p_league_id
    and event_row.created_at>=now()-interval '24 hours';

  select jsonb_build_object(
    'id',event_row.id,
    'eventType',event_row.event_type,
    'gateStatus',event_row.gate_status,
    'reasonCode',event_row.reason_code,
    'gateGeneration',event_row.gate_generation,
    'currentCompletionRunId',event_row.current_completion_run_id,
    'finalMatchdayId',event_row.final_matchday_id,
    'finalProgressionRunId',event_row.final_progression_run_id,
    'unsafeMatchdayCount',event_row.unsafe_matchday_count,
    'missingGateCount',event_row.missing_gate_count,
    'mismatchedProgressionCount',event_row.mismatched_progression_count,
    'createdAt',event_row.created_at
  )
  into v_latest
  from public.provider_season_completion_gate_events event_row
  where event_row.league_id=p_league_id
  order by event_row.created_at desc,event_row.id desc
  limit 1;

  v_completion_affected :=
    nullif(v_assessment->>'currentCompletionRunId','')::bigint is not null
    and coalesce(v_assessment->>'gateStatus','blocked')='affected';
  v_healthy := not v_completion_affected;

  return jsonb_build_object(
    'protected',true,
    'healthy',v_healthy,
    'causalSeasonCompletionBarrierActive',true,
    'legacySeasonCompletionBypassBlocked',true,
    'progressionChainLocked',true,
    'gateStatus',coalesce(v_assessment->>'gateStatus','blocked'),
    'reasonCode',v_assessment->>'reasonCode',
    'completionRunId',nullif(v_assessment->>'currentCompletionRunId','')::bigint,
    'finalMatchdayId',nullif(v_assessment->>'finalMatchdayId','')::uuid,
    'finalProgressionRunId',
      nullif(v_assessment->>'finalProgressionRunId','')::bigint,
    'matchdayCount',coalesce((v_assessment->>'matchdayCount')::integer,0),
    'clearMatchdayCount',
      coalesce((v_assessment->>'clearMatchdayCount')::integer,0),
    'unsafeMatchdayCount',
      coalesce((v_assessment->>'unsafeMatchdayCount')::integer,0),
    'missingGateCount',
      coalesce((v_assessment->>'missingGateCount')::integer,0),
    'mismatchedProgressionCount',
      coalesce((v_assessment->>'mismatchedProgressionCount')::integer,0),
    'completionAffected',v_completion_affected,
    'eventsLast24h',v_events_24h,
    'latestEvent',v_latest
  );
end;
$function$;
revoke all on function public.get_league_provider_season_completion_gate_v1(uuid)
from public,anon,service_role;
grant execute on function public.get_league_provider_season_completion_gate_v1(uuid)
to authenticated;

create or replace function public.get_league_provider_sync_health_v26(
  p_league_id uuid
)
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
  v_base := public.get_league_provider_sync_health_v25(p_league_id);
  v_gate := public.get_league_provider_season_completion_gate_v1(p_league_id);
  v_healthy := coalesce((v_base->>'healthy')::boolean,false)
    and coalesce((v_gate->>'healthy')::boolean,false);
  v_status := case
    when not v_healthy then 'attention'
    else coalesce(v_base->>'status','idle')
  end;

  return v_base || jsonb_build_object(
    'protected',coalesce((v_base->>'protected')::boolean,false)
      and coalesce((v_gate->>'protected')::boolean,false),
    'healthy',v_healthy,
    'status',v_status,
    'seasonCompletionGate',v_gate
  );
end;
$function$;
revoke all on function public.get_league_provider_sync_health_v26(uuid)
from public,anon,service_role;
grant execute on function public.get_league_provider_sync_health_v26(uuid)
to authenticated;

-- Solo gli eventi immutabili vengono pubblicati in Realtime.
do $realtime$
begin
  if exists (
    select 1
    from pg_catalog.pg_publication publication
    where publication.pubname='supabase_realtime'
  ) and not exists (
    select 1
    from pg_catalog.pg_publication_tables publication_table
    where publication_table.pubname='supabase_realtime'
      and publication_table.schemaname='public'
      and publication_table.tablename='provider_season_completion_gate_events'
  ) then
    alter publication supabase_realtime
      add table public.provider_season_completion_gate_events;
  end if;
end;
$realtime$;

create or replace function public.get_provider_season_completion_gate_integrity_v1()
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
  v_guarded_v2 text;
  v_state_v5 text;
  v_management_v15 text;
  v_center text;
  v_health text;
begin
  v_predecessor := public.get_provider_matchday_progression_gate_integrity_v1();
  v_compute := lower(pg_catalog.pg_get_functiondef(
    'public.compute_provider_season_completion_gate_v1(uuid,bigint)'::regprocedure
  ));
  v_reconcile := lower(pg_catalog.pg_get_functiondef(
    'public.reconcile_provider_season_completion_gate_v1(uuid)'::regprocedure
  ));
  v_guard := lower(pg_catalog.pg_get_functiondef(
    'public.enforce_provider_season_completion_gate_v1()'::regprocedure
  ));
  v_guarded_v2 := lower(pg_catalog.pg_get_functiondef(
    'public.complete_league_season_guarded_v2(uuid,uuid)'::regprocedure
  ));
  v_state_v5 := lower(pg_catalog.pg_get_functiondef(
    'public.get_league_season_state_v5(uuid)'::regprocedure
  ));
  v_management_v15 := lower(pg_catalog.pg_get_functiondef(
    'public.get_league_management_state_v15(uuid)'::regprocedure
  ));
  v_center := lower(pg_catalog.pg_get_functiondef(
    'public.get_league_provider_season_completion_gate_v1(uuid)'::regprocedure
  ));
  v_health := lower(pg_catalog.pg_get_functiondef(
    'public.get_league_provider_sync_health_v26(uuid)'::regprocedure
  ));

  return jsonb_build_object(
    'predecessor_ready',
      (select count(*) from jsonb_each(v_predecessor))=20
      and not exists (
        select 1
        from jsonb_each(v_predecessor) check_row
        where check_row.value is distinct from 'true'::jsonb
      ),
    'head_table_ready',
      to_regclass('public.provider_season_completion_gate_heads') is not null,
    'event_table_ready',
      to_regclass('public.provider_season_completion_gate_events') is not null,
    'columns_ready',
      (select count(*)=17
       from information_schema.columns
       where table_schema='public'
         and table_name='provider_season_completion_gate_heads')
      and
      (select count(*)=17
       from information_schema.columns
       where table_schema='public'
         and table_name='provider_season_completion_gate_events'),
    'constraints_ready',
      (select count(*)>=7
       from pg_catalog.pg_constraint
       where conrelid='public.provider_season_completion_gate_heads'::regclass)
      and
      (select count(*)>=8
       from pg_catalog.pg_constraint
       where conrelid='public.provider_season_completion_gate_events'::regclass),
    'indexes_ready',
      to_regclass('public.provider_season_completion_gate_heads_status_idx')
        is not null
      and to_regclass('public.provider_season_completion_gate_heads_completion_idx')
        is not null
      and to_regclass('public.provider_season_completion_gate_events_league_idx')
        is not null,
    'rls_ready',
      (select relrowsecurity
       from pg_catalog.pg_class
       where oid='public.provider_season_completion_gate_heads'::regclass)
      and
      (select relrowsecurity
       from pg_catalog.pg_class
       where oid='public.provider_season_completion_gate_events'::regclass)
      and exists (
        select 1 from pg_catalog.pg_policy policy_row
        where policy_row.polrelid=
          'public.provider_season_completion_gate_heads'::regclass
          and policy_row.polname=
            'provider_season_completion_gate_heads_director_select'
      )
      and exists (
        select 1 from pg_catalog.pg_policy policy_row
        where policy_row.polrelid=
          'public.provider_season_completion_gate_events'::regclass
          and policy_row.polname=
            'provider_season_completion_gate_events_director_select'
      ),
    'authenticated_write_blocked',
      not has_table_privilege('authenticated',
        'public.provider_season_completion_gate_heads','INSERT')
      and not has_table_privilege('authenticated',
        'public.provider_season_completion_gate_heads','UPDATE')
      and not has_table_privilege('authenticated',
        'public.provider_season_completion_gate_heads','DELETE')
      and not has_table_privilege('authenticated',
        'public.provider_season_completion_gate_events','INSERT')
      and not has_table_privilege('authenticated',
        'public.provider_season_completion_gate_events','UPDATE')
      and not has_table_privilege('authenticated',
        'public.provider_season_completion_gate_events','DELETE'),
    'service_role_ready',
      has_table_privilege('service_role',
        'public.provider_season_completion_gate_heads','SELECT')
      and has_table_privilege('service_role',
        'public.provider_season_completion_gate_heads','INSERT')
      and has_table_privilege('service_role',
        'public.provider_season_completion_gate_heads','UPDATE')
      and has_table_privilege('service_role',
        'public.provider_season_completion_gate_events','SELECT')
      and has_table_privilege('service_role',
        'public.provider_season_completion_gate_events','INSERT'),
    'immutable_events_ready',
      exists (
        select 1
        from pg_catalog.pg_trigger trigger_row
        where trigger_row.tgrelid=
          'public.provider_season_completion_gate_events'::regclass
          and trigger_row.tgname=
            'provider_season_completion_gate_events_immutable'
          and trigger_row.tgenabled='A'
          and not trigger_row.tgisinternal
      ),
    'head_guard_ready',
      exists (
        select 1
        from pg_catalog.pg_trigger trigger_row
        where trigger_row.tgrelid=
          'public.provider_season_completion_gate_heads'::regclass
          and trigger_row.tgname=
            'provider_season_completion_gate_heads_guard'
          and trigger_row.tgenabled='A'
          and not trigger_row.tgisinternal
      ),
    'compute_rpc_ready',
      to_regprocedure(
        'public.compute_provider_season_completion_gate_v1(uuid,bigint)'
      ) is not null
      and has_function_privilege('service_role',
        'public.compute_provider_season_completion_gate_v1(uuid,bigint)',
        'EXECUTE')
      and position('season_completion.progression_chain_unsafe' in v_compute)>0
      and position('season_completion.final_progression_superseded' in v_compute)>0,
    'reconcile_rpc_ready',
      to_regprocedure(
        'public.reconcile_provider_season_completion_gate_v1(uuid)'
      ) is not null
      and has_function_privilege('service_role',
        'public.reconcile_provider_season_completion_gate_v1(uuid)',
        'EXECUTE')
      and position('gate_fingerprint' in v_reconcile)>0
      and position('provider-season-completion-chain:' in v_reconcile)>0,
    'completion_insert_guard_ready',
      exists (
        select 1
        from pg_catalog.pg_trigger trigger_row
        where trigger_row.tgrelid='public.season_completion_runs'::regclass
          and trigger_row.tgname='provider_season_completion_insert_guard'
          and trigger_row.tgenabled='A'
          and not trigger_row.tgisinternal
      )
      and exists (
        select 1
        from pg_catalog.pg_trigger trigger_row
        where trigger_row.tgrelid='public.matchday_progression_runs'::regclass
          and trigger_row.tgname=
            'provider_season_completion_progression_chain_lock'
          and trigger_row.tgenabled='A'
          and not trigger_row.tgisinternal
          and (trigger_row.tgtype & 4)=4
          and (trigger_row.tgtype & 16)=16
      )
      and exists (
        select 1
        from pg_catalog.pg_trigger trigger_row
        where trigger_row.tgrelid=
          'public.provider_matchday_progression_gate_heads'::regclass
          and trigger_row.tgname=
            'provider_season_completion_progression_head_chain_lock'
          and trigger_row.tgenabled='A'
          and not trigger_row.tgisinternal
      )
      and position('provider-season-completion-chain:' in v_guard)>0,
    'progression_completion_triggers_ready',
      exists (
        select 1
        from pg_catalog.pg_trigger trigger_row
        where trigger_row.tgrelid=
          'public.provider_matchday_progression_gate_heads'::regclass
          and trigger_row.tgname=
            'provider_season_completion_progression_writer'
          and trigger_row.tgenabled='A'
          and not trigger_row.tgisinternal
      )
      and exists (
        select 1
        from pg_catalog.pg_trigger trigger_row
        where trigger_row.tgrelid='public.season_completion_runs'::regclass
          and trigger_row.tgname='provider_season_completion_run_writer'
          and trigger_row.tgenabled='A'
          and not trigger_row.tgisinternal
      ),
    'guarded_v2_ready',
      to_regprocedure(
        'public.complete_league_season_guarded_v2(uuid,uuid)'
      ) is not null
      and has_function_privilege('authenticated',
        'public.complete_league_season_guarded_v2(uuid,uuid)','EXECUTE')
      and position('provider.season_completion_gate' in v_guarded_v2)>0
      and position('complete_league_season_guarded_v1' in v_guarded_v2)>0,
    'season_state_v5_ready',
      to_regprocedure('public.get_league_season_state_v5(uuid)') is not null
      and has_function_privilege('authenticated',
        'public.get_league_season_state_v5(uuid)','EXECUTE')
      and position('seasoncompletioncausallycertified' in
        replace(v_state_v5,'_',''))>0
      and to_regprocedure('public.get_league_management_state_v15(uuid)')
        is not null
      and has_function_privilege('authenticated',
        'public.get_league_management_state_v15(uuid)','EXECUTE')
      and position('seasoncompletioncausalready' in
        replace(v_management_v15,'_',''))>0,
    'backfill_ready',
      not exists (
        select 1
        from public.leagues league_row
        where (
          exists (
            select 1 from public.fantasy_fixtures fixture
            where fixture.league_id=league_row.id
          )
          or exists (
            select 1 from public.season_completion_runs completion
            where completion.league_id=league_row.id
          )
        )
        and not exists (
          select 1
          from public.provider_season_completion_gate_heads head
          where head.league_id=league_row.id
        )
      ),
    'center_health_ready',
      to_regprocedure(
        'public.get_league_provider_season_completion_gate_v1(uuid)'
      ) is not null
      and has_function_privilege('authenticated',
        'public.get_league_provider_season_completion_gate_v1(uuid)',
        'EXECUTE')
      and position('completionaffected' in replace(v_center,'_',''))>0
      and to_regprocedure('public.get_league_provider_sync_health_v26(uuid)')
        is not null
      and has_function_privilege('authenticated',
        'public.get_league_provider_sync_health_v26(uuid)','EXECUTE')
      and position('seasoncompletiongate' in replace(v_health,'_',''))>0,
    'realtime_events_ready',
      exists (
        select 1
        from pg_catalog.pg_publication_tables publication_table
        where publication_table.pubname='supabase_realtime'
          and publication_table.schemaname='public'
          and publication_table.tablename=
            'provider_season_completion_gate_events'
      )
      and not exists (
        select 1
        from pg_catalog.pg_publication_tables publication_table
        where publication_table.pubname='supabase_realtime'
          and publication_table.schemaname='public'
          and publication_table.tablename=
            'provider_season_completion_gate_heads'
      )
  );
end;
$function$;
revoke all on function public.get_provider_season_completion_gate_integrity_v1()
from public,anon,authenticated,service_role;
grant execute on function public.get_provider_season_completion_gate_integrity_v1()
to service_role;

-- Validazione transazionale: esattamente 20 controlli booleani true.
do $validation$
declare
  v_checks jsonb;
  v_false text;
  v_count integer;
begin
  v_checks := public.get_provider_season_completion_gate_integrity_v1();
  select count(*) into v_count from jsonb_each(v_checks);
  select string_agg(check_row.key,', ' order by check_row.key)
  into v_false
  from jsonb_each(v_checks) check_row
  where jsonb_typeof(check_row.value) is distinct from 'boolean'
     or check_row.value is distinct from 'true'::jsonb;

  if v_count<>20 then
    raise exception
      'Validazione v0.62.27 non superata. Numero controlli atteso 20, rilevato %.',
      v_count;
  end if;
  if v_false is not null then
    raise exception
      'Validazione v0.62.27 non superata. Controlli falsi: %',
      v_false;
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
  (checks->>'completion_insert_guard_ready')::boolean as completion_insert_guard_ready,
  (checks->>'progression_completion_triggers_ready')::boolean as progression_completion_triggers_ready,
  (checks->>'guarded_v2_ready')::boolean as guarded_v2_ready,
  (checks->>'season_state_v5_ready')::boolean as season_state_v5_ready,
  (checks->>'backfill_ready')::boolean as backfill_ready,
  (checks->>'center_health_ready')::boolean as center_health_ready,
  (checks->>'realtime_events_ready')::boolean as realtime_events_ready
from (
  select public.get_provider_season_completion_gate_integrity_v1() as checks
) diagnostic;
