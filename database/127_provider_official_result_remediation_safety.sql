-- LEGHEVO v0.62.23
-- Remediation causale e riapertura race-safe dei risultati ufficiali provider.
-- Eseguire dopo database/126_provider_official_result_impact_safety.sql.
-- La migrazione non modifica automaticamente risultati o classifiche: crea una
-- coda causale e collega la riapertura alla generazione d'impatto ancora corrente.

begin;

-- PRE-FLIGHT: dipendenze reali e firme complete.
do $preflight$
declare
  v_missing text[] := array[]::text[];
  v_checks jsonb;
begin
  if to_regprocedure('public.get_provider_official_result_impact_integrity_v1()') is null then
    v_missing := array_append(v_missing,'function public.get_provider_official_result_impact_integrity_v1()');
  else
    v_checks := public.get_provider_official_result_impact_integrity_v1();
    if (select count(*) from jsonb_each(v_checks)) <> 20
      or exists(
        select 1 from jsonb_each(v_checks) check_row
        where jsonb_typeof(check_row.value) is distinct from 'boolean'
           or check_row.value is distinct from 'true'::jsonb
      ) then
      v_missing := array_append(v_missing,'v0.62.22 integrity: all 20 checks must be true');
    end if;
  end if;

  if to_regclass('public.leagues') is null then v_missing:=array_append(v_missing,'table public.leagues'); end if;
  if to_regclass('public.matchdays') is null then v_missing:=array_append(v_missing,'table public.matchdays'); end if;
  if to_regclass('public.fantasy_fixtures') is null then v_missing:=array_append(v_missing,'table public.fantasy_fixtures'); end if;
  if to_regclass('public.fantasy_teams') is null then v_missing:=array_append(v_missing,'table public.fantasy_teams'); end if;
  if to_regclass('public.profiles') is null then v_missing:=array_append(v_missing,'table public.profiles'); end if;
  if to_regclass('public.result_correction_runs') is null then v_missing:=array_append(v_missing,'table public.result_correction_runs'); end if;
  if to_regclass('public.provider_official_result_impact_heads') is null then v_missing:=array_append(v_missing,'table public.provider_official_result_impact_heads'); end if;
  if to_regclass('public.provider_official_result_impact_events') is null then v_missing:=array_append(v_missing,'table public.provider_official_result_impact_events'); end if;
  if to_regclass('public.provider_sync_runs') is null then v_missing:=array_append(v_missing,'table public.provider_sync_runs'); end if;

  if exists(
    select 1
    from (values
      ('leagues','id'),('leagues','owner_id'),('leagues','status'),
      ('matchdays','id'),('matchdays','number'),
      ('fantasy_fixtures','id'),('fantasy_fixtures','league_id'),('fantasy_fixtures','matchday_id'),
      ('fantasy_fixtures','home_team_id'),('fantasy_fixtures','away_team_id'),
      ('fantasy_fixtures','finalized_at'),('fantasy_fixtures','correction_run_id'),
      ('fantasy_teams','id'),('fantasy_teams','name'),
      ('profiles','id'),
      ('result_correction_runs','id'),('result_correction_runs','request_id'),
      ('result_correction_runs','fixture_id'),('result_correction_runs','requested_by'),
      ('result_correction_runs','reason'),
      ('provider_official_result_impact_heads','id'),('provider_official_result_impact_heads','league_id'),
      ('provider_official_result_impact_heads','matchday_id'),('provider_official_result_impact_heads','fixture_id'),
      ('provider_official_result_impact_heads','impact_status'),
      ('provider_official_result_impact_heads','assessment_generation'),
      ('provider_official_result_impact_heads','risk_fingerprint'),
      ('provider_official_result_impact_heads','reason_code'),
      ('provider_official_result_impact_events','head_id'),
      ('provider_official_result_impact_events','impact_status'),
      ('provider_official_result_impact_events','assessment_generation'),
      ('provider_official_result_impact_events','risk_fingerprint'),
      ('provider_sync_runs','status')
    ) required(table_name,column_name)
    where not exists(
      select 1 from information_schema.columns column_row
      where column_row.table_schema='public'
        and column_row.table_name=required.table_name
        and column_row.column_name=required.column_name
    )
  ) then
    v_missing:=array_append(v_missing,'required columns for provider official result remediation');
  end if;

  if to_regprocedure('public.reopen_league_fixture_guarded_v1(uuid,uuid,text,uuid)') is null then
    v_missing:=array_append(v_missing,'RPC public.reopen_league_fixture_guarded_v1(uuid,uuid,text,uuid)');
  end if;
  if to_regprocedure('public.get_league_provider_sync_health_v21(uuid)') is null then
    v_missing:=array_append(v_missing,'RPC public.get_league_provider_sync_health_v21(uuid)');
  end if;
  if to_regprocedure('public.is_league_admin(uuid)') is null then
    v_missing:=array_append(v_missing,'function public.is_league_admin(uuid)');
  end if;
  if to_regprocedure('gen_random_uuid()') is null then
    v_missing:=array_append(v_missing,'function gen_random_uuid()');
  end if;
  if to_regprocedure('pg_catalog.md5(text)') is null then
    v_missing:=array_append(v_missing,'function pg_catalog.md5(text)');
  end if;
  if to_regprocedure('pg_catalog.hashtextextended(text,bigint)') is null then
    v_missing:=array_append(v_missing,'function pg_catalog.hashtextextended(text,bigint)');
  end if;
  if to_regprocedure('pg_catalog.pg_advisory_xact_lock(bigint)') is null then
    v_missing:=array_append(v_missing,'function pg_catalog.pg_advisory_xact_lock(bigint)');
  end if;
  if to_regprocedure('pg_catalog.set_config(text,text,boolean)') is null then
    v_missing:=array_append(v_missing,'function pg_catalog.set_config(text,text,boolean)');
  end if;
  if to_regprocedure('pg_catalog.regexp_replace(text,text,text,text)') is null then
    v_missing:=array_append(v_missing,'function pg_catalog.regexp_replace(text,text,text,text)');
  end if;

  if exists(select 1 from public.provider_sync_runs run_row where run_row.status='running') then
    v_missing:=array_append(v_missing,'no provider sync run may be running during installation');
  end if;

  if coalesce(array_length(v_missing,1),0)>0 then
    raise exception 'Preflight v0.62.23 non superato. Dipendenze mancanti: %',array_to_string(v_missing,'; ');
  end if;
end;
$preflight$;

create table if not exists public.provider_official_result_remediation_heads (
  id uuid primary key default gen_random_uuid(),
  league_id uuid not null references public.leagues(id) on delete cascade,
  matchday_id uuid not null references public.matchdays(id) on delete cascade,
  fixture_id uuid not null unique references public.fantasy_fixtures(id) on delete cascade,
  impact_head_id uuid not null unique references public.provider_official_result_impact_heads(id) on delete cascade,
  impact_assessment_generation bigint not null,
  impact_risk_fingerprint text not null,
  remediation_status text not null,
  remediation_generation bigint not null default 1,
  causal_start_certified boolean not null default false,
  correction_run_id bigint references public.result_correction_runs(id) on delete set null,
  correction_request_id uuid,
  opened_at timestamptz not null default now(),
  started_at timestamptz,
  resolved_at timestamptz,
  last_transition_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint provider_official_result_remediation_heads_status_check
    check(remediation_status in ('open','in_correction','resolved','superseded')),
  constraint provider_official_result_remediation_heads_impact_generation_check
    check(impact_assessment_generation>=1),
  constraint provider_official_result_remediation_heads_generation_check
    check(remediation_generation>=1),
  constraint provider_official_result_remediation_heads_fingerprint_check
    check(length(impact_risk_fingerprint)=32),
  constraint provider_official_result_remediation_heads_started_check
    check(remediation_status<>'in_correction' or started_at is not null),
  constraint provider_official_result_remediation_heads_resolved_check
    check(remediation_status<>'resolved' or resolved_at is not null),
  constraint provider_official_result_remediation_heads_correction_check
    check(
      (correction_run_id is null and correction_request_id is null)
      or (correction_run_id is not null and correction_request_id is not null)
    ),
  constraint provider_official_result_remediation_heads_in_correction_link_check
    check(remediation_status<>'in_correction' or correction_run_id is not null)
);

create index if not exists provider_official_result_remediation_heads_league_idx
  on public.provider_official_result_remediation_heads(
    league_id,remediation_status,last_transition_at desc
  );
create index if not exists provider_official_result_remediation_heads_matchday_idx
  on public.provider_official_result_remediation_heads(
    matchday_id,remediation_status
  );
create unique index if not exists provider_official_result_remediation_heads_request_uidx
  on public.provider_official_result_remediation_heads(correction_request_id)
  where correction_request_id is not null;

create table if not exists public.provider_official_result_remediation_events (
  id uuid primary key default gen_random_uuid(),
  head_id uuid not null references public.provider_official_result_remediation_heads(id) on delete restrict,
  league_id uuid not null references public.leagues(id) on delete cascade,
  matchday_id uuid not null references public.matchdays(id) on delete cascade,
  fixture_id uuid not null references public.fantasy_fixtures(id) on delete cascade,
  impact_assessment_generation bigint not null,
  remediation_generation bigint not null,
  event_type text not null,
  remediation_status text not null,
  causal_start_certified boolean not null default false,
  correction_run_id bigint references public.result_correction_runs(id) on delete set null,
  correction_request_id uuid,
  actor_id uuid references public.profiles(id) on delete set null,
  impact_risk_fingerprint text not null,
  event_fingerprint text not null unique,
  created_at timestamptz not null default now(),
  constraint provider_official_result_remediation_events_type_check
    check(event_type in ('opened','correction_started','resolved','superseded')),
  constraint provider_official_result_remediation_events_status_check
    check(remediation_status in ('open','in_correction','resolved','superseded')),
  constraint provider_official_result_remediation_events_impact_generation_check
    check(impact_assessment_generation>=1),
  constraint provider_official_result_remediation_events_generation_check
    check(remediation_generation>=1),
  constraint provider_official_result_remediation_events_fingerprints_check
    check(length(impact_risk_fingerprint)=32 and length(event_fingerprint)=32),
  constraint provider_official_result_remediation_events_correction_link_check
    check(
      event_type<>'correction_started'
      or (correction_run_id is not null and correction_request_id is not null)
    ),
  unique(head_id,remediation_generation,event_type)
);

create index if not exists provider_official_result_remediation_events_league_idx
  on public.provider_official_result_remediation_events(league_id,created_at desc);
create index if not exists provider_official_result_remediation_events_fixture_idx
  on public.provider_official_result_remediation_events(fixture_id,created_at desc);
create unique index if not exists provider_official_result_remediation_events_request_uidx
  on public.provider_official_result_remediation_events(correction_request_id)
  where correction_request_id is not null and event_type='correction_started';

alter table public.provider_official_result_remediation_heads enable row level security;
alter table public.provider_official_result_remediation_events enable row level security;
alter table public.provider_official_result_remediation_events replica identity full;

revoke all on table public.provider_official_result_remediation_heads from public,anon,authenticated,service_role;
revoke all on table public.provider_official_result_remediation_events from public,anon,authenticated,service_role;
grant select on table public.provider_official_result_remediation_heads to authenticated;
grant select on table public.provider_official_result_remediation_events to authenticated;
grant select,insert,update on table public.provider_official_result_remediation_heads to service_role;
grant select,insert on table public.provider_official_result_remediation_events to service_role;

drop policy if exists provider_official_result_remediation_heads_read_members
on public.provider_official_result_remediation_heads;
create policy provider_official_result_remediation_heads_read_members
on public.provider_official_result_remediation_heads
for select to authenticated
using(
  exists(
    select 1
    from public.leagues league_row
    where league_row.id=league_id
      and (league_row.owner_id=auth.uid() or public.is_league_admin(league_id))
  )
);

drop policy if exists provider_official_result_remediation_events_read_members
on public.provider_official_result_remediation_events;
create policy provider_official_result_remediation_events_read_members
on public.provider_official_result_remediation_events
for select to authenticated
using(
  exists(
    select 1
    from public.leagues league_row
    where league_row.id=league_id
      and (league_row.owner_id=auth.uid() or public.is_league_admin(league_id))
  )
);

create or replace function public.prevent_provider_official_result_remediation_head_mutation_v1()
returns trigger
language plpgsql
security definer
set search_path=''
as $function$
begin
  if current_setting('leghevo.provider_official_result_remediation_context',true) is distinct from 'on' then
    raise exception 'Le teste di remediation provider sono gestite esclusivamente dal flusso certificato.';
  end if;
  if tg_op='DELETE' then return old; end if;
  return new;
end;
$function$;
revoke all on function public.prevent_provider_official_result_remediation_head_mutation_v1() from public,anon,authenticated;

drop trigger if exists provider_official_result_remediation_heads_guard
on public.provider_official_result_remediation_heads;
create trigger provider_official_result_remediation_heads_guard
before insert or update or delete on public.provider_official_result_remediation_heads
for each row execute function public.prevent_provider_official_result_remediation_head_mutation_v1();
alter table public.provider_official_result_remediation_heads enable always trigger provider_official_result_remediation_heads_guard;

create or replace function public.prevent_provider_official_result_remediation_event_mutation_v1()
returns trigger
language plpgsql
security definer
set search_path=''
as $function$
begin
  raise exception 'Gli eventi di remediation provider sono immutabili.';
end;
$function$;
revoke all on function public.prevent_provider_official_result_remediation_event_mutation_v1() from public,anon,authenticated;

drop trigger if exists provider_official_result_remediation_events_immutable
on public.provider_official_result_remediation_events;
create trigger provider_official_result_remediation_events_immutable
before update or delete on public.provider_official_result_remediation_events
for each row execute function public.prevent_provider_official_result_remediation_event_mutation_v1();
alter table public.provider_official_result_remediation_events enable always trigger provider_official_result_remediation_events_immutable;

create or replace function public.enforce_provider_official_result_remediation_start_v1()
returns trigger
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_impact public.provider_official_result_impact_heads%rowtype;
  v_context text:=coalesce(current_setting('leghevo.provider_official_result_remediation_start',true),'');
  v_context_head text;
  v_context_generation bigint;
  v_context_request uuid;
  v_correction_request uuid;
begin
  if old.finalized_at is null or new.finalized_at is not null then
    return new;
  end if;

  select impact.* into v_impact
  from public.provider_official_result_impact_heads impact
  where impact.fixture_id=old.id
  for update;

  if not found or v_impact.impact_status<>'affected' then
    return new;
  end if;

  if v_context<>'' then
    begin
      v_context_head:=split_part(v_context,'|',1);
      v_context_generation:=nullif(split_part(v_context,'|',2),'')::bigint;
      v_context_request:=nullif(split_part(v_context,'|',3),'')::uuid;
    exception when others then
      v_context_head:=null;
      v_context_generation:=null;
      v_context_request:=null;
    end;
  end if;

  if new.correction_run_id is not null then
    select correction.request_id into v_correction_request
    from public.result_correction_runs correction
    where correction.id=new.correction_run_id;
  end if;

  if v_context_head is distinct from v_impact.id::text
    or v_context_generation is distinct from v_impact.assessment_generation
    or v_context_request is null
    or v_context_request is distinct from v_correction_request then
    raise exception 'Il risultato è esposto a un impatto provider: usa la correzione provider protetta e aggiorna la valutazione prima di procedere.';
  end if;

  return new;
end;
$function$;
revoke all on function public.enforce_provider_official_result_remediation_start_v1() from public,anon,authenticated;

-- Il guard rende obbligatoria la presa in carico causale anche per client meno recenti
-- che tentassero di chiamare direttamente la RPC generica di riapertura.
drop trigger if exists provider_official_result_remediation_start_guard
on public.fantasy_fixtures;
create trigger provider_official_result_remediation_start_guard
before update of finalized_at,correction_run_id on public.fantasy_fixtures
for each row execute function public.enforce_provider_official_result_remediation_start_v1();
alter table public.fantasy_fixtures enable always trigger provider_official_result_remediation_start_guard;

create or replace function public.reconcile_provider_official_result_remediation_v1(p_fixture_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_impact public.provider_official_result_impact_heads%rowtype;
  v_existing public.provider_official_result_remediation_heads%rowtype;
  v_head public.provider_official_result_remediation_heads%rowtype;
  v_fixture public.fantasy_fixtures%rowtype;
  v_correction public.result_correction_runs%rowtype;
  v_event_type text;
  v_next_generation bigint;
  v_source_impact_generation bigint;
  v_source_impact_fingerprint text;
  v_transition boolean:=false;
  v_supersede boolean:=false;
  v_context text:=coalesce(current_setting('leghevo.provider_official_result_remediation_start',true),'');
  v_context_head text;
  v_context_generation bigint;
  v_context_request uuid;
  v_certified boolean:=false;
  v_effective_certified boolean:=false;
  v_previous_impact_status text;
  v_previous_impact_generation bigint;
  v_previous_impact_fingerprint text;
  v_event_fingerprint text;
begin
  if p_fixture_id is null then
    return jsonb_build_object('available',false,'reasonCode','remediation.fixture_missing');
  end if;

  select impact.* into v_impact
  from public.provider_official_result_impact_heads impact
  where impact.fixture_id=p_fixture_id
  for update;

  if not found then
    return jsonb_build_object('available',false,'reasonCode','remediation.impact_missing');
  end if;

  select fixture.* into v_fixture
  from public.fantasy_fixtures fixture
  where fixture.id=p_fixture_id;

  if not found then
    return jsonb_build_object('available',false,'reasonCode','remediation.fixture_not_found');
  end if;

  if v_fixture.correction_run_id is not null then
    select correction.* into v_correction
    from public.result_correction_runs correction
    where correction.id=v_fixture.correction_run_id;
  end if;

  if v_context<>'' then
    begin
      v_context_head:=split_part(v_context,'|',1);
      v_context_generation:=nullif(split_part(v_context,'|',2),'')::bigint;
      v_context_request:=nullif(split_part(v_context,'|',3),'')::uuid;
    exception when others then
      v_context_head:=null;
      v_context_generation:=null;
      v_context_request:=null;
    end;
  end if;

  perform set_config('leghevo.provider_official_result_remediation_context','on',true);

  select remediation.* into v_existing
  from public.provider_official_result_remediation_heads remediation
  where remediation.fixture_id=p_fixture_id
  for update;

  select event_row.impact_status,event_row.assessment_generation,event_row.risk_fingerprint
  into v_previous_impact_status,v_previous_impact_generation,v_previous_impact_fingerprint
  from public.provider_official_result_impact_events event_row
  where event_row.head_id=v_impact.id
    and event_row.assessment_generation<v_impact.assessment_generation
  order by event_row.assessment_generation desc
  limit 1;

  -- La certificazione si lega alla generazione "affected" mostrata prima
  -- della riapertura. Il trigger d'impatto ha già creato una nuova generazione
  -- "in_correction", quindi il confronto corretto è con la testa remediation
  -- aperta e bloccata, non con la generazione corrente dell'impact head.
  v_certified:=v_impact.impact_status='in_correction'
    and v_existing.id is not null
    and v_existing.remediation_status='open'
    and v_existing.impact_head_id=v_impact.id
    and v_context_head=v_impact.id::text
    and v_context_generation=v_existing.impact_assessment_generation
    and v_correction.id is not null
    and v_context_request=v_correction.request_id;

  if v_impact.impact_status='affected' then
    v_supersede:=v_existing.id is not null
      and v_existing.remediation_status in ('open','in_correction')
      and (
        v_existing.impact_assessment_generation<>v_impact.assessment_generation
        or v_existing.impact_risk_fingerprint<>v_impact.risk_fingerprint
      );

    if v_supersede then
      v_event_fingerprint:=md5(
        v_existing.id::text||E'\n'||v_existing.remediation_generation::text||E'\n'||
        'superseded'||E'\n'||v_existing.impact_assessment_generation::text||E'\n'||
        coalesce(v_existing.correction_request_id::text,'-')||E'\n'||
        v_existing.impact_risk_fingerprint
      );
      insert into public.provider_official_result_remediation_events(
        head_id,league_id,matchday_id,fixture_id,impact_assessment_generation,
        remediation_generation,event_type,remediation_status,causal_start_certified,
        correction_run_id,correction_request_id,actor_id,impact_risk_fingerprint,
        event_fingerprint,created_at
      ) values(
        v_existing.id,v_existing.league_id,v_existing.matchday_id,v_existing.fixture_id,
        v_existing.impact_assessment_generation,v_existing.remediation_generation,
        'superseded','superseded',v_existing.causal_start_certified,
        v_existing.correction_run_id,v_existing.correction_request_id,
        coalesce(v_correction.requested_by,auth.uid()),
        v_existing.impact_risk_fingerprint,v_event_fingerprint,now()
      ) on conflict(event_fingerprint) do nothing;
    end if;

    if v_existing.id is null then
      v_next_generation:=1;
    elsif v_supersede or v_existing.remediation_status in ('resolved','superseded') then
      v_next_generation:=v_existing.remediation_generation+1;
    else
      v_next_generation:=v_existing.remediation_generation;
    end if;
    v_event_type:='opened';
    v_transition:=v_existing.id is null
      or v_supersede
      or v_existing.remediation_status<>'open';

    insert into public.provider_official_result_remediation_heads(
      league_id,matchday_id,fixture_id,impact_head_id,
      impact_assessment_generation,impact_risk_fingerprint,
      remediation_status,remediation_generation,causal_start_certified,
      correction_run_id,correction_request_id,opened_at,started_at,resolved_at,
      last_transition_at,updated_at
    ) values(
      v_impact.league_id,v_impact.matchday_id,v_impact.fixture_id,v_impact.id,
      v_impact.assessment_generation,v_impact.risk_fingerprint,
      'open',v_next_generation,false,null,null,now(),null,null,now(),now()
    )
    on conflict(fixture_id) do update set
      league_id=excluded.league_id,matchday_id=excluded.matchday_id,
      impact_head_id=excluded.impact_head_id,
      impact_assessment_generation=excluded.impact_assessment_generation,
      impact_risk_fingerprint=excluded.impact_risk_fingerprint,
      remediation_status='open',remediation_generation=excluded.remediation_generation,
      causal_start_certified=false,correction_run_id=null,correction_request_id=null,
      opened_at=case when v_transition then now() else public.provider_official_result_remediation_heads.opened_at end,
      started_at=null,resolved_at=null,
      last_transition_at=case when v_transition then now() else public.provider_official_result_remediation_heads.last_transition_at end,
      updated_at=now()
    returning * into v_head;

  elsif v_impact.impact_status='in_correction' then
    -- Una normale correzione manuale di un risultato prima coerente non è una
    -- remediation provider. La coda nasce solo da una valutazione affected
    -- immediatamente precedente o dalla presa in carico protetta corrente.
    if not v_certified
      and (v_existing.id is null or v_existing.remediation_status in ('resolved','superseded'))
      and v_previous_impact_status is distinct from 'affected' then
      perform set_config('leghevo.provider_official_result_remediation_context','',true);
      return jsonb_build_object(
        'available',false,'fixtureId',p_fixture_id,
        'reasonCode','remediation.not_provider_causal','changed',false
      );
    end if;

    if v_existing.id is not null
      and v_existing.remediation_status in ('open','in_correction') then
      v_source_impact_generation:=v_existing.impact_assessment_generation;
      v_source_impact_fingerprint:=v_existing.impact_risk_fingerprint;
    elsif v_previous_impact_status='affected' then
      v_source_impact_generation:=v_previous_impact_generation;
      v_source_impact_fingerprint:=v_previous_impact_fingerprint;
    else
      v_source_impact_generation:=v_impact.assessment_generation;
      v_source_impact_fingerprint:=v_impact.risk_fingerprint;
    end if;

    if v_existing.id is null then
      v_next_generation:=1;
    elsif v_existing.remediation_status in ('resolved','superseded') then
      v_next_generation:=v_existing.remediation_generation+1;
    else
      v_next_generation:=v_existing.remediation_generation;
    end if;

    v_effective_certified:=coalesce(v_existing.causal_start_certified,false) or v_certified;
    v_event_type:='correction_started';
    v_transition:=v_existing.id is null
      or v_existing.remediation_status<>'in_correction'
      or v_existing.correction_run_id is distinct from v_correction.id
      or (not coalesce(v_existing.causal_start_certified,false) and v_certified);

    insert into public.provider_official_result_remediation_heads(
      league_id,matchday_id,fixture_id,impact_head_id,
      impact_assessment_generation,impact_risk_fingerprint,
      remediation_status,remediation_generation,causal_start_certified,
      correction_run_id,correction_request_id,opened_at,started_at,resolved_at,
      last_transition_at,updated_at
    ) values(
      v_impact.league_id,v_impact.matchday_id,v_impact.fixture_id,v_impact.id,
      v_source_impact_generation,v_source_impact_fingerprint,
      'in_correction',v_next_generation,v_effective_certified,
      v_correction.id,v_correction.request_id,now(),now(),null,now(),now()
    )
    on conflict(fixture_id) do update set
      league_id=excluded.league_id,matchday_id=excluded.matchday_id,
      impact_head_id=excluded.impact_head_id,
      impact_assessment_generation=excluded.impact_assessment_generation,
      impact_risk_fingerprint=excluded.impact_risk_fingerprint,
      remediation_status='in_correction',
      remediation_generation=excluded.remediation_generation,
      causal_start_certified=excluded.causal_start_certified,
      correction_run_id=coalesce(excluded.correction_run_id,public.provider_official_result_remediation_heads.correction_run_id),
      correction_request_id=coalesce(excluded.correction_request_id,public.provider_official_result_remediation_heads.correction_request_id),
      started_at=case
        when public.provider_official_result_remediation_heads.correction_run_id is distinct from excluded.correction_run_id
          then now()
        else coalesce(public.provider_official_result_remediation_heads.started_at,now())
      end,
      resolved_at=null,
      last_transition_at=case when v_transition then now() else public.provider_official_result_remediation_heads.last_transition_at end,
      updated_at=now()
    returning * into v_head;

  else
    if v_existing.id is null then
      perform set_config('leghevo.provider_official_result_remediation_context','',true);
      return jsonb_build_object(
        'available',true,'fixtureId',p_fixture_id,'remediationStatus','resolved',
        'created',false,'changed',false
      );
    end if;

    v_next_generation:=v_existing.remediation_generation;
    v_event_type:='resolved';
    -- Una testa già risolta può aggiornare la fotografia tecnica clear senza
    -- generare un secondo evento resolved per la stessa remediation.
    v_transition:=v_existing.remediation_status<>'resolved';

    update public.provider_official_result_remediation_heads remediation
    set impact_head_id=v_impact.id,
      impact_assessment_generation=v_impact.assessment_generation,
      impact_risk_fingerprint=v_impact.risk_fingerprint,
      remediation_status='resolved',resolved_at=coalesce(remediation.resolved_at,now()),
      last_transition_at=case when v_transition then now() else remediation.last_transition_at end,
      updated_at=now()
    where remediation.id=v_existing.id
    returning * into v_head;
  end if;

  if v_transition and v_head.id is not null then
    v_event_fingerprint:=md5(
      v_head.id::text||E'\n'||v_head.remediation_generation::text||E'\n'||
      v_event_type||E'\n'||v_head.impact_assessment_generation::text||E'\n'||
      coalesce(v_head.correction_request_id::text,'-')||E'\n'||v_head.impact_risk_fingerprint
    );
    insert into public.provider_official_result_remediation_events(
      head_id,league_id,matchday_id,fixture_id,impact_assessment_generation,
      remediation_generation,event_type,remediation_status,causal_start_certified,
      correction_run_id,correction_request_id,actor_id,impact_risk_fingerprint,
      event_fingerprint,created_at
    ) values(
      v_head.id,v_head.league_id,v_head.matchday_id,v_head.fixture_id,
      v_head.impact_assessment_generation,v_head.remediation_generation,
      v_event_type,v_head.remediation_status,v_head.causal_start_certified,
      v_head.correction_run_id,v_head.correction_request_id,
      coalesce(v_correction.requested_by,auth.uid()),v_head.impact_risk_fingerprint,
      v_event_fingerprint,now()
    ) on conflict(event_fingerprint) do nothing;
  end if;

  perform set_config('leghevo.provider_official_result_remediation_context','',true);
  return jsonb_build_object(
    'available',true,'headId',v_head.id,'fixtureId',v_head.fixture_id,
    'impactAssessmentGeneration',v_head.impact_assessment_generation,
    'remediationGeneration',v_head.remediation_generation,
    'remediationStatus',v_head.remediation_status,
    'causalStartCertified',v_head.causal_start_certified,
    'correctionRunId',v_head.correction_run_id,
    'changed',v_transition
  );
exception when others then
  perform set_config('leghevo.provider_official_result_remediation_context','',true);
  raise;
end;
$function$;
revoke all on function public.reconcile_provider_official_result_remediation_v1(uuid) from public,anon,authenticated;
grant execute on function public.reconcile_provider_official_result_remediation_v1(uuid) to service_role;

create or replace function public.reconcile_provider_official_result_remediation_from_impact_v1()
returns trigger
language plpgsql
security definer
set search_path=''
as $function$
begin
  perform public.reconcile_provider_official_result_remediation_v1(new.fixture_id);
  return new;
end;
$function$;
revoke all on function public.reconcile_provider_official_result_remediation_from_impact_v1() from public,anon,authenticated;

drop trigger if exists provider_official_result_remediation_impact_writer
on public.provider_official_result_impact_heads;
create trigger provider_official_result_remediation_impact_writer
after insert or update of impact_status,assessment_generation,risk_fingerprint
on public.provider_official_result_impact_heads
for each row execute function public.reconcile_provider_official_result_remediation_from_impact_v1();
alter table public.provider_official_result_impact_heads enable always trigger provider_official_result_remediation_impact_writer;

create or replace function public.start_provider_official_result_remediation_v1(
  p_league_id uuid,
  p_fixture_id uuid,
  p_expected_assessment_generation bigint,
  p_reason text,
  p_request_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_league public.leagues%rowtype;
  v_impact public.provider_official_result_impact_heads%rowtype;
  v_existing_event public.provider_official_result_remediation_events%rowtype;
  v_existing_reason text;
  v_lock_matchday_id uuid;
  v_result jsonb;
  v_remediation jsonb;
  v_reason text:=trim(coalesce(p_reason,''));
begin
  if auth.uid() is null then raise exception 'Devi effettuare l''accesso.'; end if;
  if p_request_id is null then raise exception 'Identificativo di remediation mancante.'; end if;
  if p_expected_assessment_generation is null or p_expected_assessment_generation<1 then
    raise exception 'Generazione d''impatto attesa non valida.';
  end if;
  if char_length(v_reason)<10 or char_length(v_reason)>240 then
    raise exception 'La motivazione deve contenere da 10 a 240 caratteri.';
  end if;

  select league.* into v_league
  from public.leagues league
  where league.id=p_league_id;
  if not found then raise exception 'Lega non trovata.'; end if;
  if v_league.owner_id<>auth.uid() then
    raise exception 'Solo il Presidente può avviare la correzione provider protetta.';
  end if;

  select event_row.* into v_existing_event
  from public.provider_official_result_remediation_events event_row
  where event_row.correction_request_id=p_request_id
    and event_row.event_type='correction_started';
  if found then
    select correction.reason into v_existing_reason
    from public.result_correction_runs correction
    where correction.id=v_existing_event.correction_run_id;
    if v_existing_event.league_id<>p_league_id
      or v_existing_event.fixture_id<>p_fixture_id
      or v_existing_event.impact_assessment_generation<>p_expected_assessment_generation
      or v_existing_reason is distinct from v_reason then
      raise exception 'La chiave di remediation è già stata utilizzata con parametri differenti.';
    end if;
    return jsonb_build_object(
      'fixtureId',v_existing_event.fixture_id,
      'impactAssessmentGeneration',v_existing_event.impact_assessment_generation,
      'remediationGeneration',v_existing_event.remediation_generation,
      'remediationStatus',v_existing_event.remediation_status,
      'correctionRunId',v_existing_event.correction_run_id,
      'causalStartCertified',v_existing_event.causal_start_certified,
      'idempotentReplay',true,'affectedFixtureCount',1
    );
  end if;

  if v_league.status in ('completed','archived') then
    raise exception 'La stagione è conclusa: i risultati sono congelati.';
  end if;

  -- Lettura preliminare per acquisire prima lo stesso lock di giornata usato
  -- dal motore di ufficializzazione/correzione. Il dato viene ricontrollato
  -- sotto lock prima di qualsiasi modifica.
  select impact.* into v_impact
  from public.provider_official_result_impact_heads impact
  where impact.fixture_id=p_fixture_id
    and impact.league_id=p_league_id;
  if not found then
    raise exception 'Impatto provider non trovato per il risultato selezionato.';
  end if;
  v_lock_matchday_id:=v_impact.matchday_id;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'matchday-officialization:'||p_league_id::text||':'||v_lock_matchday_id::text,
      0
    )
  );
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('provider-official-result-remediation:'||p_fixture_id::text,0)
  );

  select league.* into v_league
  from public.leagues league
  where league.id=p_league_id
  for update;
  if not found then raise exception 'Lega non trovata.'; end if;
  if v_league.owner_id<>auth.uid() then
    raise exception 'Solo il Presidente può avviare la correzione provider protetta.';
  end if;
  if v_league.status in ('completed','archived') then
    raise exception 'La stagione è conclusa: i risultati sono congelati.';
  end if;

  select impact.* into v_impact
  from public.provider_official_result_impact_heads impact
  where impact.fixture_id=p_fixture_id
    and impact.league_id=p_league_id
  for update;
  if not found then
    raise exception 'Impatto provider non trovato per il risultato selezionato.';
  end if;
  if v_impact.matchday_id is distinct from v_lock_matchday_id then
    raise exception 'La giornata dell’impatto provider è cambiata: aggiorna i risultati e riprova.';
  end if;
  if v_impact.impact_status<>'affected' then
    raise exception 'Il risultato non richiede più una correzione provider.';
  end if;
  if v_impact.assessment_generation<>p_expected_assessment_generation then
    raise exception 'La valutazione provider è cambiata: aggiorna i risultati prima di correggere.';
  end if;

  -- Materializza e blocca la presa in carico della generazione mostrata.
  perform public.reconcile_provider_official_result_remediation_v1(p_fixture_id);
  perform set_config(
    'leghevo.provider_official_result_remediation_start',
    v_impact.id::text||'|'||v_impact.assessment_generation::text||'|'||p_request_id::text,
    true
  );

  v_result:=public.reopen_league_fixture_guarded_v1(
    p_league_id,p_fixture_id,v_reason,p_request_id
  );
  v_remediation:=public.reconcile_provider_official_result_remediation_v1(p_fixture_id);
  perform set_config('leghevo.provider_official_result_remediation_start','',true);

  if coalesce((v_remediation->>'causalStartCertified')::boolean,false)=false
    or (v_remediation->>'impactAssessmentGeneration')::bigint<>p_expected_assessment_generation then
    raise exception 'La riapertura non è stata collegata alla generazione provider corrente.';
  end if;

  return v_result||v_remediation||jsonb_build_object(
    'impactAssessmentGeneration',p_expected_assessment_generation,
    'idempotentReplay',false
  );
exception when others then
  perform set_config('leghevo.provider_official_result_remediation_start','',true);
  raise;
end;
$function$;
revoke all on function public.start_provider_official_result_remediation_v1(uuid,uuid,bigint,text,uuid) from public,anon,service_role;
grant execute on function public.start_provider_official_result_remediation_v1(uuid,uuid,bigint,text,uuid) to authenticated;

create or replace function public.get_league_provider_official_result_remediation_v1(p_league_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $function$
declare
  v_owner_id uuid;
  v_open integer:=0;
  v_in_correction integer:=0;
  v_resolved integer:=0;
  v_uncertified integer:=0;
  v_events_24h integer:=0;
  v_items jsonb:='[]'::jsonb;
begin
  if auth.uid() is null then raise exception 'Devi effettuare l''accesso.'; end if;
  select league.owner_id into v_owner_id from public.leagues league where league.id=p_league_id;
  if not found then raise exception 'Lega non trovata per la remediation provider.'; end if;
  if v_owner_id<>auth.uid() and not public.is_league_admin(p_league_id) then
    raise exception 'Solo Presidente e Admin possono leggere la remediation provider.';
  end if;

  select
    count(*) filter(where head.remediation_status='open')::integer,
    count(*) filter(where head.remediation_status='in_correction')::integer,
    count(*) filter(where head.remediation_status='resolved')::integer,
    count(*) filter(where head.remediation_status='in_correction' and not head.causal_start_certified)::integer
  into v_open,v_in_correction,v_resolved,v_uncertified
  from public.provider_official_result_remediation_heads head
  where head.league_id=p_league_id;

  select count(*)::integer into v_events_24h
  from public.provider_official_result_remediation_events event_row
  where event_row.league_id=p_league_id and event_row.created_at>=now()-interval '24 hours';

  select coalesce(jsonb_agg(item order by item->>'openedAt',item->>'fixtureId'),'[]'::jsonb)
  into v_items
  from (
    select jsonb_build_object(
      'headId',head.id,'fixtureId',head.fixture_id,'matchdayId',head.matchday_id,
      'matchdayNumber',matchday.number,
      'homeTeamName',home_team.name,'awayTeamName',away_team.name,
      'impactAssessmentGeneration',head.impact_assessment_generation,
      'remediationGeneration',head.remediation_generation,
      'remediationStatus',head.remediation_status,
      'causalStartCertified',head.causal_start_certified,
      'correctionRunId',head.correction_run_id,
      'openedAt',head.opened_at,'startedAt',head.started_at,
      'impactReasonCode',impact.reason_code
    ) as item
    from public.provider_official_result_remediation_heads head
    join public.provider_official_result_impact_heads impact on impact.id=head.impact_head_id
    join public.matchdays matchday on matchday.id=head.matchday_id
    join public.fantasy_fixtures fixture on fixture.id=head.fixture_id
    join public.fantasy_teams home_team on home_team.id=fixture.home_team_id
    join public.fantasy_teams away_team on away_team.id=fixture.away_team_id
    where head.league_id=p_league_id
      and head.remediation_status in ('open','in_correction')
    order by head.last_transition_at desc,head.fixture_id
  ) queue_rows;

  return jsonb_build_object(
    'protected',true,
    'healthy',v_open=0 and v_uncertified=0,
    'raceSafeRemediationActive',true,
    'staleAssessmentRejected',true,
    'resultsNeverMutatedAutomatically',true,
    'openCount',v_open,'inCorrectionCount',v_in_correction,
    'resolvedCount',v_resolved,'uncertifiedCorrectionCount',v_uncertified,
    'eventsLast24h',v_events_24h,'items',v_items
  );
end;
$function$;
revoke all on function public.get_league_provider_official_result_remediation_v1(uuid) from public,anon,service_role;
grant execute on function public.get_league_provider_official_result_remediation_v1(uuid) to authenticated;

create or replace function public.get_league_provider_sync_health_v22(p_league_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $function$
declare
  v_base jsonb;
  v_remediation jsonb;
  v_healthy boolean;
  v_status text;
begin
  v_base:=public.get_league_provider_sync_health_v21(p_league_id);
  v_remediation:=public.get_league_provider_official_result_remediation_v1(p_league_id);
  v_healthy:=coalesce((v_base->>'healthy')::boolean,false)
    and coalesce((v_remediation->>'healthy')::boolean,false);
  v_status:=case when not v_healthy then 'attention' else coalesce(v_base->>'status','idle') end;
  return v_base||jsonb_build_object(
    'protected',coalesce((v_base->>'protected')::boolean,false)
      and coalesce((v_remediation->>'protected')::boolean,false),
    'healthy',v_healthy,'status',v_status,
    'officialResultRemediation',v_remediation
  );
end;
$function$;
revoke all on function public.get_league_provider_sync_health_v22(uuid) from public,anon,service_role;
grant execute on function public.get_league_provider_sync_health_v22(uuid) to authenticated;

-- Backfill non distruttivo delle valutazioni già presenti.
do $backfill$
declare
  v_fixture_id uuid;
begin
  for v_fixture_id in
    select impact.fixture_id
    from public.provider_official_result_impact_heads impact
    where impact.impact_status in ('affected','in_correction')
    order by impact.fixture_id
  loop
    perform public.reconcile_provider_official_result_remediation_v1(v_fixture_id);
  end loop;
end;
$backfill$;

create or replace function public.get_provider_official_result_remediation_integrity_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $function$
declare
  v_predecessor jsonb;
  v_start text;
  v_reconcile text;
  v_health text;
  v_start_compact text;
  v_reconcile_compact text;
  v_health_compact text;
begin
  v_predecessor:=public.get_provider_official_result_impact_integrity_v1();
  v_start:=lower(pg_catalog.pg_get_functiondef('public.start_provider_official_result_remediation_v1(uuid,uuid,bigint,text,uuid)'::regprocedure));
  v_reconcile:=lower(pg_catalog.pg_get_functiondef('public.reconcile_provider_official_result_remediation_v1(uuid)'::regprocedure));
  v_health:=lower(pg_catalog.pg_get_functiondef('public.get_league_provider_sync_health_v22(uuid)'::regprocedure));
  v_start_compact:=pg_catalog.regexp_replace(v_start,'[[:space:]]+','','g');
  v_reconcile_compact:=pg_catalog.regexp_replace(v_reconcile,'[[:space:]]+','','g');
  v_health_compact:=pg_catalog.regexp_replace(v_health,'[[:space:]]+','','g');

  return jsonb_build_object(
    'predecessor_ready',(select count(*) from jsonb_each(v_predecessor))=20
      and not exists(select 1 from jsonb_each(v_predecessor) row where row.value is distinct from 'true'::jsonb),
    'head_table_ready',to_regclass('public.provider_official_result_remediation_heads') is not null,
    'event_table_ready',to_regclass('public.provider_official_result_remediation_events') is not null,
    'constraints_ready',(select count(*)>=7 from pg_catalog.pg_constraint where conrelid='public.provider_official_result_remediation_heads'::regclass)
      and (select count(*)>=8 from pg_catalog.pg_constraint where conrelid='public.provider_official_result_remediation_events'::regclass),
    'indexes_ready',to_regclass('public.provider_official_result_remediation_heads_league_idx') is not null
      and to_regclass('public.provider_official_result_remediation_events_league_idx') is not null
      and to_regclass('public.provider_official_result_remediation_events_request_uidx') is not null,
    'rls_ready',(select relrowsecurity from pg_catalog.pg_class where oid='public.provider_official_result_remediation_heads'::regclass)
      and (select relrowsecurity from pg_catalog.pg_class where oid='public.provider_official_result_remediation_events'::regclass)
      and exists(select 1 from pg_catalog.pg_policy policy_row
        where policy_row.polrelid='public.provider_official_result_remediation_heads'::regclass
          and policy_row.polname='provider_official_result_remediation_heads_read_members')
      and exists(select 1 from pg_catalog.pg_policy policy_row
        where policy_row.polrelid='public.provider_official_result_remediation_events'::regclass
          and policy_row.polname='provider_official_result_remediation_events_read_members'),
    'authenticated_write_blocked',not has_table_privilege('authenticated','public.provider_official_result_remediation_heads','INSERT')
      and not has_table_privilege('authenticated','public.provider_official_result_remediation_heads','UPDATE')
      and not has_table_privilege('authenticated','public.provider_official_result_remediation_events','INSERT'),
    'service_role_ready',has_table_privilege('service_role','public.provider_official_result_remediation_heads','SELECT')
      and has_table_privilege('service_role','public.provider_official_result_remediation_heads','INSERT')
      and has_table_privilege('service_role','public.provider_official_result_remediation_heads','UPDATE')
      and has_table_privilege('service_role','public.provider_official_result_remediation_events','SELECT')
      and has_table_privilege('service_role','public.provider_official_result_remediation_events','INSERT'),
    'immutable_events_ready',exists(select 1 from pg_catalog.pg_trigger trigger_row
      where trigger_row.tgrelid='public.provider_official_result_remediation_events'::regclass
        and trigger_row.tgname='provider_official_result_remediation_events_immutable'
        and trigger_row.tgenabled='A' and not trigger_row.tgisinternal),
    'head_guard_ready',exists(select 1 from pg_catalog.pg_trigger trigger_row
      where trigger_row.tgrelid='public.provider_official_result_remediation_heads'::regclass
        and trigger_row.tgname='provider_official_result_remediation_heads_guard'
        and trigger_row.tgenabled='A' and not trigger_row.tgisinternal)
      and exists(select 1 from pg_catalog.pg_trigger trigger_row
        where trigger_row.tgrelid='public.fantasy_fixtures'::regclass
          and trigger_row.tgname='provider_official_result_remediation_start_guard'
          and trigger_row.tgenabled='A' and not trigger_row.tgisinternal),
    'reconcile_rpc_ready',to_regprocedure('public.reconcile_provider_official_result_remediation_v1(uuid)') is not null,
    'start_rpc_ready',to_regprocedure('public.start_provider_official_result_remediation_v1(uuid,uuid,bigint,text,uuid)') is not null,
    'center_rpc_ready',to_regprocedure('public.get_league_provider_official_result_remediation_v1(uuid)') is not null,
    'impact_trigger_ready',exists(select 1 from pg_catalog.pg_trigger trigger_row
      where trigger_row.tgrelid='public.provider_official_result_impact_heads'::regclass
        and trigger_row.tgname='provider_official_result_remediation_impact_writer'
        and trigger_row.tgenabled='A' and not trigger_row.tgisinternal),
    'backfill_ready',not exists(
      select 1
      from public.provider_official_result_impact_heads impact
      where (
          impact.impact_status='affected'
          or (
            impact.impact_status='in_correction'
            and exists(
              select 1
              from public.provider_official_result_impact_events previous_event
              where previous_event.head_id=impact.id
                and previous_event.assessment_generation=impact.assessment_generation-1
                and previous_event.impact_status='affected'
            )
          )
        )
        and not exists(
          select 1
          from public.provider_official_result_remediation_heads remediation
          where remediation.fixture_id=impact.fixture_id
            and remediation.impact_head_id=impact.id
            and (
              (impact.impact_status='affected'
                and remediation.remediation_status='open'
                and remediation.impact_assessment_generation=impact.assessment_generation)
              or
              (impact.impact_status='in_correction'
                and remediation.remediation_status='in_correction'
                and remediation.correction_run_id is not null)
            )
        )
    ),
    'race_safe_start_ready',position('forupdate' in v_start_compact)>0
      and position('assessment_generation<>p_expected_assessment_generation' in v_start_compact)>0
      and position('matchday-officialization:' in v_start_compact)>0
      and position('provider-official-result-remediation:' in v_start_compact)>0
      and position('reopen_league_fixture_guarded_v1' in v_start_compact)>0
      and position('v_existing_reasonisdistinctfromv_reason' in v_start_compact)>0
      and to_regprocedure('public.enforce_provider_official_result_remediation_start_v1()') is not null,
    'correction_linkage_ready',position('v_context_generation=v_existing.impact_assessment_generation' in v_reconcile_compact)>0
      and position('v_existing.remediation_status=''open''' in v_reconcile_compact)>0
      and position('v_effective_certified:=coalesce(v_existing.causal_start_certified,false)orv_certified' in v_reconcile_compact)>0
      and position('provider_official_result_remediation_start' in v_reconcile)>0,
    'health_v22_ready',to_regprocedure('public.get_league_provider_sync_health_v22(uuid)') is not null
      and position('officialresultremediation' in v_health_compact)>0,
    'realtime_events_ready',exists(select 1 from pg_catalog.pg_publication_tables publication_row
      where publication_row.pubname='supabase_realtime' and publication_row.schemaname='public'
        and publication_row.tablename='provider_official_result_remediation_events')
      or not exists(select 1 from pg_catalog.pg_publication publication_row where publication_row.pubname='supabase_realtime'),
    'rpc_grants_ready',has_function_privilege('authenticated','public.start_provider_official_result_remediation_v1(uuid,uuid,bigint,text,uuid)','EXECUTE')
      and has_function_privilege('authenticated','public.get_league_provider_official_result_remediation_v1(uuid)','EXECUTE')
      and has_function_privilege('authenticated','public.get_league_provider_sync_health_v22(uuid)','EXECUTE')
      and not has_function_privilege('authenticated','public.reconcile_provider_official_result_remediation_v1(uuid)','EXECUTE')
  );
end;
$function$;
revoke all on function public.get_provider_official_result_remediation_integrity_v1() from public,anon,authenticated;
grant execute on function public.get_provider_official_result_remediation_integrity_v1() to service_role;

do $realtime$
begin
  if exists(select 1 from pg_catalog.pg_publication where pubname='supabase_realtime') then
    if not exists(select 1 from pg_catalog.pg_publication_tables
      where pubname='supabase_realtime' and schemaname='public'
        and tablename='provider_official_result_remediation_events') then
      execute 'alter publication supabase_realtime add table public.provider_official_result_remediation_events';
    end if;
  end if;
end;
$realtime$;

do $validation$
declare
  v_checks jsonb;
  v_failed text;
begin
  v_checks:=public.get_provider_official_result_remediation_integrity_v1();
  select string_agg(check_row.key,', ' order by check_row.key) into v_failed
  from jsonb_each(v_checks) check_row
  where jsonb_typeof(check_row.value) is distinct from 'boolean'
     or check_row.value is distinct from 'true'::jsonb;
  if (select count(*) from jsonb_each(v_checks))<>20 or v_failed is not null then
    raise exception 'Validazione v0.62.23 non superata. Controlli falsi: %',coalesce(v_failed,'numero_controlli_non_valido');
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
  (checks->>'reconcile_rpc_ready')::boolean as reconcile_rpc_ready,
  (checks->>'start_rpc_ready')::boolean as start_rpc_ready,
  (checks->>'center_rpc_ready')::boolean as center_rpc_ready,
  (checks->>'impact_trigger_ready')::boolean as impact_trigger_ready,
  (checks->>'backfill_ready')::boolean as backfill_ready,
  (checks->>'race_safe_start_ready')::boolean as race_safe_start_ready,
  (checks->>'correction_linkage_ready')::boolean as correction_linkage_ready,
  (checks->>'health_v22_ready')::boolean as health_v22_ready,
  (checks->>'realtime_events_ready')::boolean as realtime_events_ready,
  (checks->>'rpc_grants_ready')::boolean as rpc_grants_ready
from (select public.get_provider_official_result_remediation_integrity_v1() as checks) diagnostic;
