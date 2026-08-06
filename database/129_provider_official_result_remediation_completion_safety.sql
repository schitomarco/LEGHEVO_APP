-- LEGHEVO v0.62.25
-- Chiusura causale certificata della remediation dei risultati ufficiali provider.
-- Migrazione prevista: database/129_provider_official_result_remediation_completion_safety.sql
-- Eseguire dopo database/128_provider_official_result_lineage_commit_barrier_safety.sql.
-- La migrazione non modifica risultati, classifiche, voti o storico sportivo.

begin;

-- PRE-FLIGHT: verifica puntuale delle dipendenze reali utilizzate.
do $preflight$
declare
  v_missing text[]:=array[]::text[];
  v_checks jsonb;
  v_required_count integer;
begin
  if to_regprocedure('public.get_provider_official_result_lineage_integrity_v1()') is null then
    v_missing:=array_append(v_missing,'function public.get_provider_official_result_lineage_integrity_v1()');
  else
    v_checks:=public.get_provider_official_result_lineage_integrity_v1();
    select count(*) into v_required_count from jsonb_each(v_checks);
    if v_required_count<>20 or exists(
      select 1 from jsonb_each(v_checks) check_row
      where jsonb_typeof(check_row.value) is distinct from 'boolean'
         or check_row.value is distinct from 'true'::jsonb
    ) then
      v_missing:=array_append(v_missing,'v0.62.24 integrity: all 20 checks must be true');
    end if;
  end if;

  if to_regclass('public.provider_official_result_remediation_heads') is null then
    v_missing:=array_append(v_missing,'table public.provider_official_result_remediation_heads');
  end if;
  if to_regclass('public.provider_official_result_impact_heads') is null then
    v_missing:=array_append(v_missing,'table public.provider_official_result_impact_heads');
  end if;
  if to_regclass('public.provider_official_result_lineage_heads') is null then
    v_missing:=array_append(v_missing,'table public.provider_official_result_lineage_heads');
  end if;
  if to_regclass('public.fantasy_fixtures') is null then
    v_missing:=array_append(v_missing,'table public.fantasy_fixtures');
  end if;
  if to_regclass('public.matchday_officialization_runs') is null then
    v_missing:=array_append(v_missing,'table public.matchday_officialization_runs');
  end if;
  if to_regclass('public.result_correction_runs') is null then
    v_missing:=array_append(v_missing,'table public.result_correction_runs');
  end if;
  if to_regclass('public.live_fixture_projection_runs') is null then
    v_missing:=array_append(v_missing,'table public.live_fixture_projection_runs');
  end if;
  if to_regclass('public.leagues') is null then
    v_missing:=array_append(v_missing,'table public.leagues');
  end if;
  if to_regclass('public.matchdays') is null then
    v_missing:=array_append(v_missing,'table public.matchdays');
  end if;

  if exists(
    select 1
    from (values
      ('provider_official_result_remediation_heads','id'),
      ('provider_official_result_remediation_heads','league_id'),
      ('provider_official_result_remediation_heads','matchday_id'),
      ('provider_official_result_remediation_heads','fixture_id'),
      ('provider_official_result_remediation_heads','impact_assessment_generation'),
      ('provider_official_result_remediation_heads','remediation_generation'),
      ('provider_official_result_remediation_heads','remediation_status'),
      ('provider_official_result_remediation_heads','causal_start_certified'),
      ('provider_official_result_remediation_heads','correction_run_id'),
      ('provider_official_result_remediation_heads','started_at'),
      ('provider_official_result_remediation_heads','resolved_at'),
      ('provider_official_result_impact_heads','fixture_id'),
      ('provider_official_result_impact_heads','impact_status'),
      ('provider_official_result_impact_heads','assessment_generation'),
      ('provider_official_result_lineage_heads','id'),
      ('provider_official_result_lineage_heads','fixture_id'),
      ('provider_official_result_lineage_heads','lineage_status'),
      ('provider_official_result_lineage_heads','lineage_generation'),
      ('provider_official_result_lineage_heads','official_projection_id'),
      ('provider_official_result_lineage_heads','officialization_run_id'),
      ('provider_official_result_lineage_heads','correction_run_id'),
      ('fantasy_fixtures','id'),
      ('fantasy_fixtures','finalized_at'),
      ('fantasy_fixtures','official_projection_id'),
      ('fantasy_fixtures','officialization_run_id'),
      ('fantasy_fixtures','correction_run_id'),
      ('matchday_officialization_runs','id'),
      ('matchday_officialization_runs','source_correction_run_ids'),
      ('matchday_officialization_runs','finalized_at'),
      ('result_correction_runs','id'),
      ('result_correction_runs','reopened_at')
    ) required(table_name,column_name)
    where not exists(
      select 1 from information_schema.columns column_row
      where column_row.table_schema='public'
        and column_row.table_name=required.table_name
        and column_row.column_name=required.column_name
    )
  ) then
    v_missing:=array_append(v_missing,'required columns for remediation completion certificate');
  end if;

  if to_regprocedure('public.get_league_provider_sync_health_v23(uuid)') is null then
    v_missing:=array_append(v_missing,'RPC public.get_league_provider_sync_health_v23(uuid)');
  end if;
  if to_regprocedure('public.get_league_provider_official_result_remediation_v1(uuid)') is null then
    v_missing:=array_append(v_missing,'RPC public.get_league_provider_official_result_remediation_v1(uuid)');
  end if;
  if to_regprocedure('public.is_league_admin(uuid)') is null then
    v_missing:=array_append(v_missing,'function public.is_league_admin(uuid)');
  end if;
  if to_regprocedure('pg_catalog.md5(text)') is null then
    v_missing:=array_append(v_missing,'function pg_catalog.md5(text)');
  end if;

  if cardinality(v_missing)>0 then
    raise exception 'Preflight v0.62.25 non superato. Dipendenze mancanti: %',array_to_string(v_missing,'; ');
  end if;
end;
$preflight$;

create table if not exists public.provider_official_result_remediation_completion_heads (
  id bigint generated by default as identity primary key,
  remediation_head_id uuid not null unique
    references public.provider_official_result_remediation_heads(id) on delete cascade,
  league_id uuid not null references public.leagues(id) on delete cascade,
  matchday_id uuid not null references public.matchdays(id) on delete cascade,
  fixture_id uuid not null unique references public.fantasy_fixtures(id) on delete cascade,
  remediation_generation bigint not null,
  impact_assessment_generation bigint not null,
  completion_status text not null,
  resolution_mode text not null,
  reason_code text not null,
  correction_run_id bigint references public.result_correction_runs(id) on delete set null,
  officialization_run_id bigint references public.matchday_officialization_runs(id) on delete set null,
  official_projection_id bigint references public.live_fixture_projection_runs(id) on delete set null,
  lineage_head_id uuid references public.provider_official_result_lineage_heads(id) on delete set null,
  lineage_generation bigint,
  causal_start_certified boolean not null default false,
  source_correction_certified boolean not null default false,
  official_lineage_certified boolean not null default false,
  completion_generation bigint not null default 1,
  completion_fingerprint text not null,
  first_certified_at timestamptz,
  last_assessed_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint provider_official_result_remediation_completion_heads_status_check
    check(completion_status in ('pending','certified','invalid','superseded')),
  constraint provider_official_result_remediation_completion_heads_mode_check
    check(resolution_mode in ('none','auto_recovered','correction_certified')),
  constraint provider_official_result_remediation_completion_heads_generations_check
    check(remediation_generation>=1 and impact_assessment_generation>=1 and completion_generation>=1),
  constraint provider_official_result_remediation_completion_heads_lineage_generation_check
    check(lineage_generation is null or lineage_generation>=1),
  constraint provider_official_result_remediation_completion_heads_fingerprint_check
    check(length(completion_fingerprint)=32),
  constraint provider_official_result_remediation_completion_heads_certified_check
    check(
      completion_status<>'certified'
      or (
        resolution_mode in ('auto_recovered','correction_certified')
        and official_lineage_certified
        and officialization_run_id is not null
        and official_projection_id is not null
        and lineage_head_id is not null
        and lineage_generation is not null
        and first_certified_at is not null
      )
    ),
  constraint provider_official_result_remediation_completion_heads_correction_check
    check(
      resolution_mode<>'correction_certified'
      or (
        correction_run_id is not null
        and causal_start_certified
        and source_correction_certified
      )
    ),
  constraint provider_official_result_remediation_completion_heads_auto_check
    check(
      resolution_mode<>'auto_recovered'
      or (correction_run_id is null and not causal_start_certified)
    )
);

create index if not exists provider_official_result_remediation_completion_heads_league_idx
  on public.provider_official_result_remediation_completion_heads(
    league_id,completion_status,last_assessed_at desc
  );
create index if not exists provider_official_result_remediation_completion_heads_matchday_idx
  on public.provider_official_result_remediation_completion_heads(
    matchday_id,completion_status
  );

create table if not exists public.provider_official_result_remediation_completion_events (
  id bigint generated by default as identity primary key,
  completion_head_id bigint not null
    references public.provider_official_result_remediation_completion_heads(id) on delete restrict,
  remediation_head_id uuid not null
    references public.provider_official_result_remediation_heads(id) on delete restrict,
  league_id uuid not null references public.leagues(id) on delete cascade,
  matchday_id uuid not null references public.matchdays(id) on delete cascade,
  fixture_id uuid not null references public.fantasy_fixtures(id) on delete cascade,
  remediation_generation bigint not null,
  completion_generation bigint not null,
  event_type text not null,
  completion_status text not null,
  resolution_mode text not null,
  reason_code text not null,
  correction_run_id bigint references public.result_correction_runs(id) on delete set null,
  officialization_run_id bigint references public.matchday_officialization_runs(id) on delete set null,
  official_projection_id bigint references public.live_fixture_projection_runs(id) on delete set null,
  lineage_generation bigint,
  causal_start_certified boolean not null,
  source_correction_certified boolean not null,
  official_lineage_certified boolean not null,
  completion_fingerprint text not null,
  event_fingerprint text not null unique,
  created_at timestamptz not null default now(),
  constraint provider_official_result_remediation_completion_events_type_check
    check(event_type in ('pending','certified','invalid','superseded','revalidated')),
  constraint provider_official_result_remediation_completion_events_status_check
    check(completion_status in ('pending','certified','invalid','superseded')),
  constraint provider_official_result_remediation_completion_events_mode_check
    check(resolution_mode in ('none','auto_recovered','correction_certified')),
  constraint provider_official_result_remediation_completion_events_generations_check
    check(remediation_generation>=1 and completion_generation>=1),
  constraint provider_official_result_remediation_completion_events_fingerprints_check
    check(length(completion_fingerprint)=32 and length(event_fingerprint)=32)
);

create index if not exists provider_official_result_remediation_completion_events_league_idx
  on public.provider_official_result_remediation_completion_events(league_id,created_at desc);
create index if not exists provider_official_result_remediation_completion_events_fixture_idx
  on public.provider_official_result_remediation_completion_events(fixture_id,created_at desc);

alter table public.provider_official_result_remediation_completion_heads enable row level security;
alter table public.provider_official_result_remediation_completion_events enable row level security;
alter table public.provider_official_result_remediation_completion_events replica identity full;

revoke all on table public.provider_official_result_remediation_completion_heads from public,anon,authenticated,service_role;
revoke all on table public.provider_official_result_remediation_completion_events from public,anon,authenticated,service_role;
grant select on table public.provider_official_result_remediation_completion_heads to authenticated;
grant select on table public.provider_official_result_remediation_completion_events to authenticated;
grant select,insert,update on table public.provider_official_result_remediation_completion_heads to service_role;
grant select,insert on table public.provider_official_result_remediation_completion_events to service_role;

drop policy if exists provider_official_result_remediation_completion_heads_director_select
on public.provider_official_result_remediation_completion_heads;
create policy provider_official_result_remediation_completion_heads_director_select
on public.provider_official_result_remediation_completion_heads
for select to authenticated
using(
  exists(
    select 1 from public.leagues league_row
    where league_row.id=league_id
      and (league_row.owner_id=auth.uid() or public.is_league_admin(league_id))
  )
);

drop policy if exists provider_official_result_remediation_completion_events_director_select
on public.provider_official_result_remediation_completion_events;
create policy provider_official_result_remediation_completion_events_director_select
on public.provider_official_result_remediation_completion_events
for select to authenticated
using(
  exists(
    select 1 from public.leagues league_row
    where league_row.id=league_id
      and (league_row.owner_id=auth.uid() or public.is_league_admin(league_id))
  )
);

create or replace function public.prevent_provider_official_result_remediation_completion_head_mutation_v1()
returns trigger
language plpgsql
security definer
set search_path=''
as $function$
begin
  if coalesce(current_setting('leghevo.provider_official_result_remediation_completion_context',true),'')='on' then
    if tg_op='DELETE' then return old; end if;
    return new;
  end if;
  raise exception 'Certificato di chiusura remediation provider: modifica diretta non consentita.';
end;
$function$;
revoke all on function public.prevent_provider_official_result_remediation_completion_head_mutation_v1() from public,anon,authenticated;

drop trigger if exists provider_official_result_remediation_completion_heads_guard
on public.provider_official_result_remediation_completion_heads;
create trigger provider_official_result_remediation_completion_heads_guard
before update or delete on public.provider_official_result_remediation_completion_heads
for each row execute function public.prevent_provider_official_result_remediation_completion_head_mutation_v1();
alter table public.provider_official_result_remediation_completion_heads enable always trigger provider_official_result_remediation_completion_heads_guard;

create or replace function public.prevent_provider_official_result_remediation_completion_event_mutation_v1()
returns trigger
language plpgsql
security definer
set search_path=''
as $function$
begin
  raise exception 'Storico chiusura remediation provider immutabile: UPDATE e DELETE non consentiti.';
end;
$function$;
revoke all on function public.prevent_provider_official_result_remediation_completion_event_mutation_v1() from public,anon,authenticated;

drop trigger if exists provider_official_result_remediation_completion_events_immutable
on public.provider_official_result_remediation_completion_events;
create trigger provider_official_result_remediation_completion_events_immutable
before update or delete on public.provider_official_result_remediation_completion_events
for each row execute function public.prevent_provider_official_result_remediation_completion_event_mutation_v1();
alter table public.provider_official_result_remediation_completion_events enable always trigger provider_official_result_remediation_completion_events_immutable;

create or replace function public.compute_provider_official_result_remediation_completion_v1(
  p_fixture_id uuid,
  p_assume_resolved boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_remediation public.provider_official_result_remediation_heads%rowtype;
  v_impact public.provider_official_result_impact_heads%rowtype;
  v_lineage public.provider_official_result_lineage_heads%rowtype;
  v_fixture public.fantasy_fixtures%rowtype;
  v_officialization public.matchday_officialization_runs%rowtype;
  v_correction public.result_correction_runs%rowtype;
  v_effective_status text;
  v_completion_status text:='pending';
  v_mode text:='none';
  v_reason text:='completion.pending';
  v_source_certified boolean:=false;
  v_lineage_certified boolean:=false;
  v_completion_certified boolean:=false;
  v_fingerprint text;
begin
  if p_fixture_id is null then
    return jsonb_build_object('available',false,'reasonCode','completion.fixture_missing');
  end if;

  select remediation.* into v_remediation
  from public.provider_official_result_remediation_heads remediation
  where remediation.fixture_id=p_fixture_id;
  if not found then
    return jsonb_build_object('available',false,'reasonCode','completion.remediation_missing');
  end if;

  select impact.* into v_impact
  from public.provider_official_result_impact_heads impact
  where impact.fixture_id=p_fixture_id;

  select fixture.* into v_fixture
  from public.fantasy_fixtures fixture
  where fixture.id=p_fixture_id;
  if not found then
    return jsonb_build_object('available',false,'reasonCode','completion.fixture_not_found');
  end if;

  select lineage.* into v_lineage
  from public.provider_official_result_lineage_heads lineage
  where lineage.fixture_id=p_fixture_id;

  if v_fixture.officialization_run_id is not null then
    select run.* into v_officialization
    from public.matchday_officialization_runs run
    where run.id=v_fixture.officialization_run_id;
  end if;

  if v_remediation.correction_run_id is not null then
    select correction.* into v_correction
    from public.result_correction_runs correction
    where correction.id=v_remediation.correction_run_id;
  end if;

  v_effective_status:=case when p_assume_resolved then 'resolved' else v_remediation.remediation_status end;
  v_lineage_certified:=v_lineage.id is not null
    and v_lineage.lineage_status='certified'
    and v_fixture.finalized_at is not null
    and v_fixture.official_projection_id is not null
    and v_fixture.officialization_run_id is not null
    and v_lineage.official_projection_id=v_fixture.official_projection_id
    and v_lineage.officialization_run_id=v_fixture.officialization_run_id;

  if v_effective_status='superseded' then
    v_completion_status:='superseded';
    v_reason:='completion.remediation_superseded';
  elsif v_effective_status in ('open','in_correction') then
    v_completion_status:='pending';
    v_reason:=case when v_effective_status='open'
      then 'completion.awaiting_correction_start'
      else 'completion.awaiting_reofficialization' end;
  elsif v_effective_status<>'resolved' then
    v_completion_status:='invalid';
    v_reason:='completion.remediation_status_invalid';
  elsif v_impact.id is null or v_impact.impact_status<>'clear' then
    v_completion_status:='invalid';
    v_reason:='completion.impact_not_clear';
  elsif not v_lineage_certified then
    v_completion_status:='invalid';
    v_reason:='completion.official_lineage_not_certified';
  elsif v_remediation.correction_run_id is null
    and v_remediation.causal_start_certified then
    v_completion_status:='invalid';
    v_reason:='completion.certified_start_without_correction';
  elsif v_remediation.correction_run_id is null then
    v_completion_status:='certified';
    v_mode:='auto_recovered';
    v_reason:='completion.auto_recovery_certified';
    v_completion_certified:=true;
  else
    v_source_certified:=v_correction.id is not null
      and v_remediation.causal_start_certified
      and v_remediation.started_at is not null
      and v_fixture.correction_run_id=v_remediation.correction_run_id
      and v_lineage.correction_run_id=v_remediation.correction_run_id
      and v_officialization.id=v_fixture.officialization_run_id
      and coalesce(v_officialization.source_correction_run_ids,'[]'::jsonb)
        @> jsonb_build_array(v_remediation.correction_run_id)
      and v_officialization.finalized_at>=v_correction.reopened_at
      and v_officialization.finalized_at>=v_remediation.started_at;

    if v_source_certified then
      v_completion_status:='certified';
      v_mode:='correction_certified';
      v_reason:='completion.correction_lineage_certified';
      v_completion_certified:=true;
    else
      v_completion_status:='invalid';
      v_reason:='completion.correction_source_not_certified';
    end if;
  end if;

  v_fingerprint:=pg_catalog.md5(jsonb_build_object(
    'remediationHeadId',v_remediation.id,
    'remediationGeneration',v_remediation.remediation_generation,
    'impactGeneration',coalesce(v_impact.assessment_generation,v_remediation.impact_assessment_generation),
    'completionStatus',v_completion_status,'resolutionMode',v_mode,'reasonCode',v_reason,
    'correctionRunId',v_remediation.correction_run_id,
    'officializationRunId',v_fixture.officialization_run_id,
    'officialProjectionId',v_fixture.official_projection_id,
    'lineageHeadId',v_lineage.id,'lineageGeneration',v_lineage.lineage_generation,
    'causalStartCertified',v_remediation.causal_start_certified,
    'sourceCorrectionCertified',v_source_certified,
    'officialLineageCertified',v_lineage_certified
  )::text);

  return jsonb_build_object(
    'available',true,'fixtureId',p_fixture_id,'leagueId',v_remediation.league_id,
    'matchdayId',v_remediation.matchday_id,'remediationHeadId',v_remediation.id,
    'remediationGeneration',v_remediation.remediation_generation,
    'impactAssessmentGeneration',coalesce(v_impact.assessment_generation,v_remediation.impact_assessment_generation),
    'completionStatus',v_completion_status,'resolutionMode',v_mode,'reasonCode',v_reason,
    'completionCertified',v_completion_certified,
    'correctionRunId',v_remediation.correction_run_id,
    'officializationRunId',v_fixture.officialization_run_id,
    'officialProjectionId',v_fixture.official_projection_id,
    'lineageHeadId',v_lineage.id,'lineageGeneration',v_lineage.lineage_generation,
    'causalStartCertified',v_remediation.causal_start_certified,
    'sourceCorrectionCertified',v_source_certified,
    'officialLineageCertified',v_lineage_certified,
    'completionFingerprint',v_fingerprint
  );
end;
$function$;
revoke all on function public.compute_provider_official_result_remediation_completion_v1(uuid,boolean) from public,anon,authenticated;
grant execute on function public.compute_provider_official_result_remediation_completion_v1(uuid,boolean) to service_role;

create or replace function public.enforce_provider_official_result_remediation_completion_v1()
returns trigger
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_completion jsonb;
begin
  if tg_op='INSERT' then
    if new.remediation_status='resolved' then
      raise exception 'Chiusura remediation provider rifiutata [completion.direct_resolved_insert]: creare prima la remediation causale.';
    end if;
    return new;
  end if;

  if new.remediation_status='resolved'
    and (
      old.remediation_status is distinct from new.remediation_status
      or old.correction_run_id is distinct from new.correction_run_id
      or old.causal_start_certified is distinct from new.causal_start_certified
    ) then
    v_completion:=public.compute_provider_official_result_remediation_completion_v1(new.fixture_id,true);
    if coalesce((v_completion->>'completionCertified')::boolean,false)=false then
      raise exception 'Chiusura remediation provider rifiutata [completion.not_certified]: %',coalesce(v_completion->>'reasonCode','completion.unknown');
    end if;
  end if;
  return new;
end;
$function$;
revoke all on function public.enforce_provider_official_result_remediation_completion_v1() from public,anon,authenticated;

drop trigger if exists provider_official_result_remediation_completion_guard
on public.provider_official_result_remediation_heads;
create trigger provider_official_result_remediation_completion_guard
before insert or update of remediation_status,correction_run_id,causal_start_certified
on public.provider_official_result_remediation_heads
for each row execute function public.enforce_provider_official_result_remediation_completion_v1();
alter table public.provider_official_result_remediation_heads enable always trigger provider_official_result_remediation_completion_guard;

create or replace function public.reconcile_provider_official_result_remediation_completion_v1(p_fixture_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_completion jsonb;
  v_remediation public.provider_official_result_remediation_heads%rowtype;
  v_existing public.provider_official_result_remediation_completion_heads%rowtype;
  v_head public.provider_official_result_remediation_completion_heads%rowtype;
  v_status text;
  v_mode text;
  v_reason text;
  v_fingerprint text;
  v_event_type text;
  v_next_generation bigint;
  v_changed boolean:=false;
  v_event_fingerprint text;
begin
  v_completion:=public.compute_provider_official_result_remediation_completion_v1(p_fixture_id,false);
  if coalesce((v_completion->>'available')::boolean,false)=false then
    return v_completion||jsonb_build_object('changed',false);
  end if;

  select remediation.* into v_remediation
  from public.provider_official_result_remediation_heads remediation
  where remediation.fixture_id=p_fixture_id
  for update;
  if not found then
    return jsonb_build_object('available',false,'reasonCode','completion.remediation_missing','changed',false);
  end if;

  perform set_config('leghevo.provider_official_result_remediation_completion_context','on',true);

  select head.* into v_existing
  from public.provider_official_result_remediation_completion_heads head
  where head.fixture_id=p_fixture_id
  for update;

  v_status:=v_completion->>'completionStatus';
  v_mode:=v_completion->>'resolutionMode';
  v_reason:=v_completion->>'reasonCode';
  v_fingerprint:=v_completion->>'completionFingerprint';

  if v_existing.id is null then
    v_next_generation:=1;
    v_changed:=true;
  elsif v_existing.completion_fingerprint is distinct from v_fingerprint
     or v_existing.completion_status is distinct from v_status
     or v_existing.resolution_mode is distinct from v_mode then
    v_next_generation:=v_existing.completion_generation+1;
    v_changed:=true;
  else
    v_next_generation:=v_existing.completion_generation;
  end if;

  insert into public.provider_official_result_remediation_completion_heads(
    remediation_head_id,league_id,matchday_id,fixture_id,
    remediation_generation,impact_assessment_generation,
    completion_status,resolution_mode,reason_code,
    correction_run_id,officialization_run_id,official_projection_id,
    lineage_head_id,lineage_generation,causal_start_certified,
    source_correction_certified,official_lineage_certified,
    completion_generation,completion_fingerprint,first_certified_at,
    last_assessed_at,updated_at
  ) values(
    v_remediation.id,v_remediation.league_id,v_remediation.matchday_id,v_remediation.fixture_id,
    v_remediation.remediation_generation,
    (v_completion->>'impactAssessmentGeneration')::bigint,
    v_status,v_mode,v_reason,
    nullif(v_completion->>'correctionRunId','')::bigint,
    nullif(v_completion->>'officializationRunId','')::bigint,
    nullif(v_completion->>'officialProjectionId','')::bigint,
    nullif(v_completion->>'lineageHeadId','')::uuid,
    nullif(v_completion->>'lineageGeneration','')::bigint,
    coalesce((v_completion->>'causalStartCertified')::boolean,false),
    coalesce((v_completion->>'sourceCorrectionCertified')::boolean,false),
    coalesce((v_completion->>'officialLineageCertified')::boolean,false),
    v_next_generation,v_fingerprint,
    case when v_status='certified' then now() else null end,
    now(),now()
  )
  on conflict(fixture_id) do update set
    remediation_head_id=excluded.remediation_head_id,
    league_id=excluded.league_id,matchday_id=excluded.matchday_id,
    remediation_generation=excluded.remediation_generation,
    impact_assessment_generation=excluded.impact_assessment_generation,
    completion_status=excluded.completion_status,
    resolution_mode=excluded.resolution_mode,reason_code=excluded.reason_code,
    correction_run_id=excluded.correction_run_id,
    officialization_run_id=excluded.officialization_run_id,
    official_projection_id=excluded.official_projection_id,
    lineage_head_id=excluded.lineage_head_id,lineage_generation=excluded.lineage_generation,
    causal_start_certified=excluded.causal_start_certified,
    source_correction_certified=excluded.source_correction_certified,
    official_lineage_certified=excluded.official_lineage_certified,
    completion_generation=excluded.completion_generation,
    completion_fingerprint=excluded.completion_fingerprint,
    first_certified_at=case
      when public.provider_official_result_remediation_completion_heads.first_certified_at is not null
        then public.provider_official_result_remediation_completion_heads.first_certified_at
      when excluded.completion_status='certified' then now() else null end,
    last_assessed_at=now(),updated_at=now()
  returning * into v_head;

  if v_changed then
    v_event_type:=case
      when v_status='certified' and v_existing.id is not null and v_existing.completion_status='certified' then 'revalidated'
      when v_status='certified' then 'certified'
      when v_status='invalid' then 'invalid'
      when v_status='superseded' then 'superseded'
      else 'pending' end;
    v_event_fingerprint:=pg_catalog.md5(
      v_head.id::text||E'\n'||v_head.completion_generation::text||E'\n'||
      v_event_type||E'\n'||v_head.completion_fingerprint
    );
    insert into public.provider_official_result_remediation_completion_events(
      completion_head_id,remediation_head_id,league_id,matchday_id,fixture_id,
      remediation_generation,completion_generation,event_type,completion_status,
      resolution_mode,reason_code,correction_run_id,officialization_run_id,
      official_projection_id,lineage_generation,causal_start_certified,
      source_correction_certified,official_lineage_certified,
      completion_fingerprint,event_fingerprint,created_at
    ) values(
      v_head.id,v_head.remediation_head_id,v_head.league_id,v_head.matchday_id,v_head.fixture_id,
      v_head.remediation_generation,v_head.completion_generation,v_event_type,v_head.completion_status,
      v_head.resolution_mode,v_head.reason_code,v_head.correction_run_id,v_head.officialization_run_id,
      v_head.official_projection_id,v_head.lineage_generation,v_head.causal_start_certified,
      v_head.source_correction_certified,v_head.official_lineage_certified,
      v_head.completion_fingerprint,v_event_fingerprint,now()
    ) on conflict(event_fingerprint) do nothing;
  end if;

  perform set_config('leghevo.provider_official_result_remediation_completion_context','',true);
  return jsonb_build_object(
    'available',true,'headId',v_head.id,'fixtureId',v_head.fixture_id,
    'completionStatus',v_head.completion_status,'resolutionMode',v_head.resolution_mode,
    'completionGeneration',v_head.completion_generation,
    'completionCertified',v_head.completion_status='certified',
    'changed',v_changed
  );
exception when others then
  perform set_config('leghevo.provider_official_result_remediation_completion_context','',true);
  raise;
end;
$function$;
revoke all on function public.reconcile_provider_official_result_remediation_completion_v1(uuid) from public,anon,authenticated;
grant execute on function public.reconcile_provider_official_result_remediation_completion_v1(uuid) to service_role;

create or replace function public.reconcile_provider_official_result_remediation_completion_from_remediation_v1()
returns trigger
language plpgsql
security definer
set search_path=''
as $function$
begin
  perform public.reconcile_provider_official_result_remediation_completion_v1(new.fixture_id);
  return new;
end;
$function$;
revoke all on function public.reconcile_provider_official_result_remediation_completion_from_remediation_v1() from public,anon,authenticated;

drop trigger if exists provider_official_result_remediation_completion_writer
on public.provider_official_result_remediation_heads;
create trigger provider_official_result_remediation_completion_writer
after insert or update of remediation_status,remediation_generation,impact_assessment_generation,
  causal_start_certified,correction_run_id,resolved_at
on public.provider_official_result_remediation_heads
for each row execute function public.reconcile_provider_official_result_remediation_completion_from_remediation_v1();

create or replace function public.reconcile_provider_official_result_remediation_completion_from_lineage_v1()
returns trigger
language plpgsql
security definer
set search_path=''
as $function$
begin
  if exists(
    select 1 from public.provider_official_result_remediation_heads remediation
    where remediation.fixture_id=new.fixture_id
  ) then
    perform public.reconcile_provider_official_result_remediation_completion_v1(new.fixture_id);
  end if;
  return new;
end;
$function$;
revoke all on function public.reconcile_provider_official_result_remediation_completion_from_lineage_v1() from public,anon,authenticated;

drop trigger if exists provider_official_result_remediation_completion_lineage_writer
on public.provider_official_result_lineage_heads;
create trigger provider_official_result_remediation_completion_lineage_writer
after insert or update of lineage_status,lineage_generation,official_projection_id,
  officialization_run_id,correction_run_id
on public.provider_official_result_lineage_heads
for each row execute function public.reconcile_provider_official_result_remediation_completion_from_lineage_v1();

-- Backfill non distruttivo: crea soltanto il certificato sintetico delle remediation esistenti.
do $backfill$
declare
  v_fixture_id uuid;
begin
  for v_fixture_id in
    select remediation.fixture_id
    from public.provider_official_result_remediation_heads remediation
    order by remediation.fixture_id
  loop
    perform public.reconcile_provider_official_result_remediation_completion_v1(v_fixture_id);
  end loop;
end;
$backfill$;

create or replace function public.get_league_provider_official_result_remediation_completion_v1(p_league_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $function$
declare
  v_owner_id uuid;
  v_pending integer:=0;
  v_certified integer:=0;
  v_invalid integer:=0;
  v_superseded integer:=0;
  v_auto_recovered integer:=0;
  v_correction_certified integer:=0;
  v_uncertified_resolved integer:=0;
  v_events_24h integer:=0;
  v_latest jsonb;
begin
  if auth.uid() is null then raise exception 'Devi effettuare l''accesso.'; end if;
  select league_row.owner_id into v_owner_id
  from public.leagues league_row where league_row.id=p_league_id;
  if not found then raise exception 'Lega non trovata per la chiusura remediation provider.'; end if;
  if v_owner_id<>auth.uid() and not public.is_league_admin(p_league_id) then
    raise exception 'Solo Presidente e Admin possono leggere la chiusura remediation provider.';
  end if;

  select
    count(*) filter(where head.completion_status='pending')::integer,
    count(*) filter(where head.completion_status='certified')::integer,
    count(*) filter(where head.completion_status='invalid')::integer,
    count(*) filter(where head.completion_status='superseded')::integer,
    count(*) filter(where head.resolution_mode='auto_recovered' and head.completion_status='certified')::integer,
    count(*) filter(where head.resolution_mode='correction_certified' and head.completion_status='certified')::integer
  into v_pending,v_certified,v_invalid,v_superseded,v_auto_recovered,v_correction_certified
  from public.provider_official_result_remediation_completion_heads head
  where head.league_id=p_league_id;

  select count(*)::integer into v_uncertified_resolved
  from public.provider_official_result_remediation_heads remediation
  left join public.provider_official_result_remediation_completion_heads completion
    on completion.remediation_head_id=remediation.id
  where remediation.league_id=p_league_id
    and remediation.remediation_status='resolved'
    and coalesce(completion.completion_status,'missing')<>'certified';

  select count(*)::integer into v_events_24h
  from public.provider_official_result_remediation_completion_events event_row
  where event_row.league_id=p_league_id and event_row.created_at>=now()-interval '24 hours';

  select jsonb_build_object(
    'id',event_row.id,'fixtureId',event_row.fixture_id,'matchdayId',event_row.matchday_id,
    'eventType',event_row.event_type,'completionStatus',event_row.completion_status,
    'resolutionMode',event_row.resolution_mode,'reasonCode',event_row.reason_code,
    'remediationGeneration',event_row.remediation_generation,
    'completionGeneration',event_row.completion_generation,
    'createdAt',event_row.created_at
  ) into v_latest
  from public.provider_official_result_remediation_completion_events event_row
  where event_row.league_id=p_league_id
  order by event_row.created_at desc,event_row.id desc limit 1;

  return jsonb_build_object(
    'protected',true,
    'healthy',v_invalid=0 and v_uncertified_resolved=0,
    'causalCompletionCertificateActive',true,
    'resolvedOnlyAfterCertifiedEvidence',true,
    'automaticRecoveryDistinguished',true,
    'pendingCount',v_pending,'certifiedCount',v_certified,
    'invalidCount',v_invalid,'supersededCount',v_superseded,
    'autoRecoveredCount',v_auto_recovered,
    'correctionCertifiedCount',v_correction_certified,
    'uncertifiedResolvedCount',v_uncertified_resolved,
    'eventsLast24h',v_events_24h,'latestEvent',v_latest
  );
end;
$function$;
revoke all on function public.get_league_provider_official_result_remediation_completion_v1(uuid) from public,anon,service_role;
grant execute on function public.get_league_provider_official_result_remediation_completion_v1(uuid) to authenticated;

create or replace function public.get_league_provider_sync_health_v24(p_league_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $function$
declare
  v_base jsonb;
  v_completion jsonb;
  v_healthy boolean;
  v_status text;
begin
  v_base:=public.get_league_provider_sync_health_v23(p_league_id);
  v_completion:=public.get_league_provider_official_result_remediation_completion_v1(p_league_id);
  v_healthy:=coalesce((v_base->>'healthy')::boolean,false)
    and coalesce((v_completion->>'healthy')::boolean,false);
  v_status:=case when not v_healthy then 'attention' else coalesce(v_base->>'status','idle') end;
  return v_base||jsonb_build_object(
    'protected',coalesce((v_base->>'protected')::boolean,false)
      and coalesce((v_completion->>'protected')::boolean,false),
    'healthy',v_healthy,'status',v_status,
    'officialResultRemediationCompletion',v_completion
  );
end;
$function$;
revoke all on function public.get_league_provider_sync_health_v24(uuid) from public,anon,service_role;
grant execute on function public.get_league_provider_sync_health_v24(uuid) to authenticated;

-- Solo lo storico immutabile viene pubblicato in Realtime.
do $realtime$
begin
  if exists(select 1 from pg_catalog.pg_publication where pubname='supabase_realtime')
    and not exists(
      select 1 from pg_catalog.pg_publication_tables
      where pubname='supabase_realtime' and schemaname='public'
        and tablename='provider_official_result_remediation_completion_events'
    ) then
    alter publication supabase_realtime
      add table public.provider_official_result_remediation_completion_events;
  end if;
end;
$realtime$;

create or replace function public.get_provider_official_result_remediation_completion_integrity_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $function$
declare
  v_predecessor jsonb;
  v_compute text;
  v_guard text;
  v_reconcile text;
  v_center text;
  v_health text;
begin
  v_predecessor:=public.get_provider_official_result_lineage_integrity_v1();
  v_compute:=lower(pg_catalog.pg_get_functiondef('public.compute_provider_official_result_remediation_completion_v1(uuid,boolean)'::regprocedure));
  v_guard:=lower(pg_catalog.pg_get_functiondef('public.enforce_provider_official_result_remediation_completion_v1()'::regprocedure));
  v_reconcile:=lower(pg_catalog.pg_get_functiondef('public.reconcile_provider_official_result_remediation_completion_v1(uuid)'::regprocedure));
  v_center:=lower(pg_catalog.pg_get_functiondef('public.get_league_provider_official_result_remediation_completion_v1(uuid)'::regprocedure));
  v_health:=lower(pg_catalog.pg_get_functiondef('public.get_league_provider_sync_health_v24(uuid)'::regprocedure));

  return jsonb_build_object(
    'predecessor_ready',(select count(*) from jsonb_each(v_predecessor))=20
      and not exists(select 1 from jsonb_each(v_predecessor) check_row where check_row.value is distinct from 'true'::jsonb),
    'completion_head_table_ready',to_regclass('public.provider_official_result_remediation_completion_heads') is not null,
    'completion_event_table_ready',to_regclass('public.provider_official_result_remediation_completion_events') is not null,
    'columns_ready',(select count(*)=23 from information_schema.columns
      where table_schema='public' and table_name='provider_official_result_remediation_completion_heads'),
    'constraints_ready',(select count(*)>=8 from pg_catalog.pg_constraint where conrelid='public.provider_official_result_remediation_completion_heads'::regclass)
      and (select count(*)>=6 from pg_catalog.pg_constraint where conrelid='public.provider_official_result_remediation_completion_events'::regclass),
    'indexes_ready',to_regclass('public.provider_official_result_remediation_completion_heads_league_idx') is not null
      and to_regclass('public.provider_official_result_remediation_completion_events_league_idx') is not null,
    'rls_ready',(select relrowsecurity from pg_catalog.pg_class where oid='public.provider_official_result_remediation_completion_heads'::regclass)
      and (select relrowsecurity from pg_catalog.pg_class where oid='public.provider_official_result_remediation_completion_events'::regclass)
      and exists(select 1 from pg_catalog.pg_policy policy_row
        where policy_row.polrelid='public.provider_official_result_remediation_completion_heads'::regclass
          and policy_row.polname='provider_official_result_remediation_completion_heads_director_select')
      and exists(select 1 from pg_catalog.pg_policy policy_row
        where policy_row.polrelid='public.provider_official_result_remediation_completion_events'::regclass
          and policy_row.polname='provider_official_result_remediation_completion_events_director_select'),
    'authenticated_write_blocked',not has_table_privilege('authenticated','public.provider_official_result_remediation_completion_heads','INSERT')
      and not has_table_privilege('authenticated','public.provider_official_result_remediation_completion_heads','UPDATE')
      and not has_table_privilege('authenticated','public.provider_official_result_remediation_completion_heads','DELETE')
      and not has_table_privilege('authenticated','public.provider_official_result_remediation_completion_events','INSERT')
      and not has_table_privilege('authenticated','public.provider_official_result_remediation_completion_events','UPDATE')
      and not has_table_privilege('authenticated','public.provider_official_result_remediation_completion_events','DELETE'),
    'service_role_ready',has_table_privilege('service_role','public.provider_official_result_remediation_completion_heads','SELECT')
      and has_table_privilege('service_role','public.provider_official_result_remediation_completion_heads','INSERT')
      and has_table_privilege('service_role','public.provider_official_result_remediation_completion_heads','UPDATE')
      and has_table_privilege('service_role','public.provider_official_result_remediation_completion_events','SELECT')
      and has_table_privilege('service_role','public.provider_official_result_remediation_completion_events','INSERT'),
    'immutable_events_ready',exists(
      select 1 from pg_catalog.pg_trigger trigger_row
      where trigger_row.tgrelid='public.provider_official_result_remediation_completion_events'::regclass
        and trigger_row.tgname='provider_official_result_remediation_completion_events_immutable'
        and trigger_row.tgenabled='A' and not trigger_row.tgisinternal
    ),
    'head_guard_ready',exists(
      select 1 from pg_catalog.pg_trigger trigger_row
      where trigger_row.tgrelid='public.provider_official_result_remediation_completion_heads'::regclass
        and trigger_row.tgname='provider_official_result_remediation_completion_heads_guard'
        and trigger_row.tgenabled='A' and not trigger_row.tgisinternal
    ),
    'compute_rpc_ready',to_regprocedure('public.compute_provider_official_result_remediation_completion_v1(uuid,boolean)') is not null
      and has_function_privilege('service_role','public.compute_provider_official_result_remediation_completion_v1(uuid,boolean)','EXECUTE')
      and position('completion.correction_lineage_certified' in v_compute)>0
      and position('completion.auto_recovery_certified' in v_compute)>0
      and position('source_correction_run_ids' in v_compute)>0,
    'resolve_guard_ready',exists(
      select 1 from pg_catalog.pg_trigger trigger_row
      where trigger_row.tgrelid='public.provider_official_result_remediation_heads'::regclass
        and trigger_row.tgname='provider_official_result_remediation_completion_guard'
        and trigger_row.tgenabled='A' and not trigger_row.tgisinternal
    ) and position('completion.not_certified' in v_guard)>0,
    'reconcile_rpc_ready',to_regprocedure('public.reconcile_provider_official_result_remediation_completion_v1(uuid)') is not null
      and has_function_privilege('service_role','public.reconcile_provider_official_result_remediation_completion_v1(uuid)','EXECUTE')
      and position('completion_fingerprint' in v_reconcile)>0,
    'remediation_trigger_ready',exists(
      select 1 from pg_catalog.pg_trigger trigger_row
      where trigger_row.tgrelid='public.provider_official_result_remediation_heads'::regclass
        and trigger_row.tgname='provider_official_result_remediation_completion_writer'
        and not trigger_row.tgisinternal
    ),
    'lineage_trigger_ready',exists(
      select 1 from pg_catalog.pg_trigger trigger_row
      where trigger_row.tgrelid='public.provider_official_result_lineage_heads'::regclass
        and trigger_row.tgname='provider_official_result_remediation_completion_lineage_writer'
        and not trigger_row.tgisinternal
    ),
    'backfill_ready',not exists(
      select 1 from public.provider_official_result_remediation_heads remediation
      left join public.provider_official_result_remediation_completion_heads completion
        on completion.remediation_head_id=remediation.id
      where completion.id is null
    ),
    'center_rpc_ready',to_regprocedure('public.get_league_provider_official_result_remediation_completion_v1(uuid)') is not null
      and has_function_privilege('authenticated','public.get_league_provider_official_result_remediation_completion_v1(uuid)','EXECUTE')
      and position('uncertifiedresolvedcount' in replace(v_center,'_',''))>0,
    'health_v24_ready',to_regprocedure('public.get_league_provider_sync_health_v24(uuid)') is not null
      and has_function_privilege('authenticated','public.get_league_provider_sync_health_v24(uuid)','EXECUTE')
      and position('officialresultremediationcompletion' in replace(v_health,'_',''))>0,
    'realtime_events_ready',exists(
      select 1 from pg_catalog.pg_publication_tables
      where pubname='supabase_realtime' and schemaname='public'
        and tablename='provider_official_result_remediation_completion_events'
    ) and not exists(
      select 1 from pg_catalog.pg_publication_tables
      where pubname='supabase_realtime' and schemaname='public'
        and tablename='provider_official_result_remediation_completion_heads'
    )
  );
end;
$function$;
revoke all on function public.get_provider_official_result_remediation_completion_integrity_v1() from public,anon,authenticated,service_role;
grant execute on function public.get_provider_official_result_remediation_completion_integrity_v1() to service_role;

-- Validazione transazionale: esattamente 20 controlli, tutti booleani true.
do $validation$
declare
  v_checks jsonb;
  v_false text;
  v_count integer;
begin
  v_checks:=public.get_provider_official_result_remediation_completion_integrity_v1();
  select count(*) into v_count from jsonb_each(v_checks);
  select string_agg(check_row.key,', ' order by check_row.key) into v_false
  from jsonb_each(v_checks) check_row
  where jsonb_typeof(check_row.value) is distinct from 'boolean'
     or check_row.value is distinct from 'true'::jsonb;
  if v_count<>20 then
    raise exception 'Validazione v0.62.25 non superata. Numero controlli atteso 20, rilevato %.',v_count;
  end if;
  if v_false is not null then
    raise exception 'Validazione v0.62.25 non superata. Controlli falsi: %',v_false;
  end if;
end;
$validation$;

commit;

select
  (checks->>'predecessor_ready')::boolean as predecessor_ready,
  (checks->>'completion_head_table_ready')::boolean as completion_head_table_ready,
  (checks->>'completion_event_table_ready')::boolean as completion_event_table_ready,
  (checks->>'columns_ready')::boolean as columns_ready,
  (checks->>'constraints_ready')::boolean as constraints_ready,
  (checks->>'indexes_ready')::boolean as indexes_ready,
  (checks->>'rls_ready')::boolean as rls_ready,
  (checks->>'authenticated_write_blocked')::boolean as authenticated_write_blocked,
  (checks->>'service_role_ready')::boolean as service_role_ready,
  (checks->>'immutable_events_ready')::boolean as immutable_events_ready,
  (checks->>'head_guard_ready')::boolean as head_guard_ready,
  (checks->>'compute_rpc_ready')::boolean as compute_rpc_ready,
  (checks->>'resolve_guard_ready')::boolean as resolve_guard_ready,
  (checks->>'reconcile_rpc_ready')::boolean as reconcile_rpc_ready,
  (checks->>'remediation_trigger_ready')::boolean as remediation_trigger_ready,
  (checks->>'lineage_trigger_ready')::boolean as lineage_trigger_ready,
  (checks->>'backfill_ready')::boolean as backfill_ready,
  (checks->>'center_rpc_ready')::boolean as center_rpc_ready,
  (checks->>'health_v24_ready')::boolean as health_v24_ready,
  (checks->>'realtime_events_ready')::boolean as realtime_events_ready
from (
  select public.get_provider_official_result_remediation_completion_integrity_v1() as checks
) diagnostic;
