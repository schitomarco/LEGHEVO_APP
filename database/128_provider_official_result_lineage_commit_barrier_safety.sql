-- LEGHEVO · barriera di commit della lineage ufficiale provider
-- Versione applicativa: 0.62.24
-- Migrazione prevista: database/128_provider_official_result_lineage_commit_barrier_safety.sql
-- Eseguire dopo database/127_provider_official_result_remediation_safety.sql.
-- La migrazione evita valutazioni transitorie tra la scrittura del risultato ufficiale
-- e il successivo collegamento alla relativa officialization run.
-- Correzione diagnostica v2: source_links_ready verifica le chiavi camelCase reali e i collegamenti sorgente effettivi.

begin;

do $preflight$
declare
  v_missing text[]:=array[]::text[];
  v_checks jsonb;
  v_failed text;
begin
  if to_regprocedure('public.get_provider_official_result_remediation_integrity_v1()') is null then
    v_missing:=array_append(v_missing,'function public.get_provider_official_result_remediation_integrity_v1()');
  else
    v_checks:=public.get_provider_official_result_remediation_integrity_v1();
    select string_agg(check_row.key,', ' order by check_row.key) into v_failed
    from jsonb_each(v_checks) check_row
    where jsonb_typeof(check_row.value) is distinct from 'boolean'
       or check_row.value is distinct from 'true'::jsonb;
    if (select count(*) from jsonb_each(v_checks))<>20 or v_failed is not null then
      v_missing:=array_append(v_missing,'v0.62.23 non certificata: '||coalesce(v_failed,'numero_controlli_non_valido'));
    end if;
  end if;

  if to_regclass('public.fantasy_fixtures') is null then v_missing:=array_append(v_missing,'table public.fantasy_fixtures'); end if;
  if to_regclass('public.matchday_officialization_runs') is null then v_missing:=array_append(v_missing,'table public.matchday_officialization_runs'); end if;
  if to_regclass('public.live_fixture_projection_runs') is null then v_missing:=array_append(v_missing,'table public.live_fixture_projection_runs'); end if;
  if to_regclass('public.result_correction_runs') is null then v_missing:=array_append(v_missing,'table public.result_correction_runs'); end if;
  if to_regclass('public.provider_sync_runs') is null then v_missing:=array_append(v_missing,'table public.provider_sync_runs'); end if;
  if to_regclass('public.provider_official_result_impact_heads') is null then v_missing:=array_append(v_missing,'table public.provider_official_result_impact_heads'); end if;
  if to_regclass('public.provider_official_result_remediation_heads') is null then v_missing:=array_append(v_missing,'table public.provider_official_result_remediation_heads'); end if;

  if exists(
    select 1
    from (values
      ('fantasy_fixtures','id'),('fantasy_fixtures','league_id'),('fantasy_fixtures','matchday_id'),
      ('fantasy_fixtures','finalized_at'),('fantasy_fixtures','official_projection_id'),
      ('fantasy_fixtures','officialization_run_id'),('fantasy_fixtures','correction_run_id'),
      ('fantasy_fixtures','result_revision'),
      ('matchday_officialization_runs','id'),('matchday_officialization_runs','league_id'),
      ('matchday_officialization_runs','matchday_id'),('matchday_officialization_runs','source_projection_ids'),
      ('matchday_officialization_runs','source_correction_run_ids'),('matchday_officialization_runs','superseded_at'),
      ('matchday_officialization_runs','finalized_at'),('matchday_officialization_runs','finalization_revision'),
      ('live_fixture_projection_runs','id'),('live_fixture_projection_runs','fixture_id'),
      ('provider_official_result_impact_heads','fixture_id'),
      ('provider_official_result_remediation_heads','fixture_id')
    ) required(table_name,column_name)
    where not exists(
      select 1 from information_schema.columns column_row
      where column_row.table_schema='public'
        and column_row.table_name=required.table_name
        and column_row.column_name=required.column_name
    )
  ) then
    v_missing:=array_append(v_missing,'required columns for official result lineage commit barrier');
  end if;

  if to_regprocedure('public.compute_provider_official_result_impact_v1(uuid)') is null then
    v_missing:=array_append(v_missing,'RPC public.compute_provider_official_result_impact_v1(uuid)');
  end if;
  if to_regprocedure('public.reconcile_provider_official_result_impact_v1(uuid)') is null then
    v_missing:=array_append(v_missing,'RPC public.reconcile_provider_official_result_impact_v1(uuid)');
  end if;
  if to_regprocedure('public.get_league_provider_sync_health_v22(uuid)') is null then
    v_missing:=array_append(v_missing,'RPC public.get_league_provider_sync_health_v22(uuid)');
  end if;
  if to_regprocedure('public.is_league_admin(uuid)') is null then
    v_missing:=array_append(v_missing,'RPC public.is_league_admin(uuid)');
  end if;

  if exists(select 1 from public.provider_sync_runs run_row where run_row.status='running') then
    v_missing:=array_append(v_missing,'no provider sync run may be running during installation');
  end if;

  if coalesce(array_length(v_missing,1),0)>0 then
    raise exception 'Preflight v0.62.24 non superato. Dipendenze mancanti: %',array_to_string(v_missing,'; ');
  end if;
end;
$preflight$;

create table if not exists public.provider_official_result_lineage_heads (
  id uuid primary key default gen_random_uuid(),
  league_id uuid not null references public.leagues(id) on delete cascade,
  matchday_id uuid not null references public.matchdays(id) on delete cascade,
  fixture_id uuid not null unique references public.fantasy_fixtures(id) on delete cascade,
  lineage_status text not null,
  reason_code text not null,
  lineage_generation bigint not null default 1,
  official_projection_id bigint references public.live_fixture_projection_runs(id) on delete set null,
  officialization_run_id bigint references public.matchday_officialization_runs(id) on delete set null,
  correction_run_id bigint references public.result_correction_runs(id) on delete set null,
  fixture_result_revision integer not null default 0,
  projection_link_certified boolean not null default false,
  officialization_scope_certified boolean not null default false,
  correction_link_certified boolean not null default false,
  lineage_fingerprint text not null,
  first_certified_at timestamptz,
  last_assessed_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint provider_official_result_lineage_heads_status_check
    check(lineage_status in ('reopened','assembling','certified','invalid')),
  constraint provider_official_result_lineage_heads_generation_check
    check(lineage_generation>=1),
  constraint provider_official_result_lineage_heads_revision_check
    check(fixture_result_revision>=0),
  constraint provider_official_result_lineage_heads_fingerprint_check
    check(length(lineage_fingerprint)=32),
  constraint provider_official_result_lineage_heads_certified_check
    check(
      lineage_status<>'certified'
      or (
        official_projection_id is not null
        and officialization_run_id is not null
        and projection_link_certified
        and officialization_scope_certified
        and correction_link_certified
        and first_certified_at is not null
      )
    )
);

create index if not exists provider_official_result_lineage_heads_league_idx
  on public.provider_official_result_lineage_heads(league_id,lineage_status,last_assessed_at desc);
create index if not exists provider_official_result_lineage_heads_matchday_idx
  on public.provider_official_result_lineage_heads(matchday_id,lineage_status);

create table if not exists public.provider_official_result_lineage_events (
  id uuid primary key default gen_random_uuid(),
  head_id uuid not null references public.provider_official_result_lineage_heads(id) on delete restrict,
  league_id uuid not null references public.leagues(id) on delete cascade,
  matchday_id uuid not null references public.matchdays(id) on delete cascade,
  fixture_id uuid not null references public.fantasy_fixtures(id) on delete cascade,
  lineage_status text not null,
  reason_code text not null,
  lineage_generation bigint not null,
  official_projection_id bigint references public.live_fixture_projection_runs(id) on delete set null,
  officialization_run_id bigint references public.matchday_officialization_runs(id) on delete set null,
  correction_run_id bigint references public.result_correction_runs(id) on delete set null,
  fixture_result_revision integer not null,
  projection_link_certified boolean not null,
  officialization_scope_certified boolean not null,
  correction_link_certified boolean not null,
  lineage_fingerprint text not null,
  event_fingerprint text not null unique,
  created_at timestamptz not null default now(),
  constraint provider_official_result_lineage_events_status_check
    check(lineage_status in ('reopened','assembling','certified','invalid')),
  constraint provider_official_result_lineage_events_generation_check
    check(lineage_generation>=1),
  constraint provider_official_result_lineage_events_revision_check
    check(fixture_result_revision>=0),
  constraint provider_official_result_lineage_events_fingerprint_check
    check(length(lineage_fingerprint)=32 and length(event_fingerprint)=32),
  unique(head_id,lineage_generation)
);

create index if not exists provider_official_result_lineage_events_league_idx
  on public.provider_official_result_lineage_events(league_id,created_at desc);
create index if not exists provider_official_result_lineage_events_fixture_idx
  on public.provider_official_result_lineage_events(fixture_id,created_at desc);

alter table public.provider_official_result_lineage_heads enable row level security;
alter table public.provider_official_result_lineage_events enable row level security;
alter table public.provider_official_result_lineage_events replica identity full;

revoke all on table public.provider_official_result_lineage_heads from public,anon,authenticated,service_role;
revoke all on table public.provider_official_result_lineage_events from public,anon,authenticated,service_role;
grant select on table public.provider_official_result_lineage_heads to authenticated;
grant select on table public.provider_official_result_lineage_events to authenticated;
grant select,insert,update on table public.provider_official_result_lineage_heads to service_role;
grant select,insert on table public.provider_official_result_lineage_events to service_role;

drop policy if exists provider_official_result_lineage_heads_read_directors
on public.provider_official_result_lineage_heads;
create policy provider_official_result_lineage_heads_read_directors
on public.provider_official_result_lineage_heads
for select to authenticated
using(
  exists(
    select 1 from public.leagues league_row
    where league_row.id=league_id
      and (league_row.owner_id=auth.uid() or public.is_league_admin(league_id))
  )
);

drop policy if exists provider_official_result_lineage_events_read_directors
on public.provider_official_result_lineage_events;
create policy provider_official_result_lineage_events_read_directors
on public.provider_official_result_lineage_events
for select to authenticated
using(
  exists(
    select 1 from public.leagues league_row
    where league_row.id=league_id
      and (league_row.owner_id=auth.uid() or public.is_league_admin(league_id))
  )
);

create or replace function public.prevent_provider_official_result_lineage_head_mutation_v1()
returns trigger
language plpgsql
security definer
set search_path=''
as $function$
begin
  if current_setting('leghevo.provider_official_result_lineage_context',true) is distinct from 'on' then
    raise exception 'La lineage ufficiale provider è gestita esclusivamente dal flusso certificato.';
  end if;
  if tg_op='DELETE' then return old; end if;
  return new;
end;
$function$;
revoke all on function public.prevent_provider_official_result_lineage_head_mutation_v1() from public,anon,authenticated;

drop trigger if exists provider_official_result_lineage_heads_guard
on public.provider_official_result_lineage_heads;
create trigger provider_official_result_lineage_heads_guard
before insert or update or delete on public.provider_official_result_lineage_heads
for each row execute function public.prevent_provider_official_result_lineage_head_mutation_v1();
alter table public.provider_official_result_lineage_heads enable always trigger provider_official_result_lineage_heads_guard;

create or replace function public.prevent_provider_official_result_lineage_event_mutation_v1()
returns trigger
language plpgsql
security definer
set search_path=''
as $function$
begin
  raise exception 'Gli eventi della lineage ufficiale provider sono immutabili.';
end;
$function$;
revoke all on function public.prevent_provider_official_result_lineage_event_mutation_v1() from public,anon,authenticated;

drop trigger if exists provider_official_result_lineage_events_immutable
on public.provider_official_result_lineage_events;
create trigger provider_official_result_lineage_events_immutable
before update or delete on public.provider_official_result_lineage_events
for each row execute function public.prevent_provider_official_result_lineage_event_mutation_v1();
alter table public.provider_official_result_lineage_events enable always trigger provider_official_result_lineage_events_immutable;

create or replace function public.compute_provider_official_result_lineage_v1(p_fixture_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $function$
declare
  v_fixture record;
  v_officialization record;
  v_projection record;
  v_status text;
  v_reason text;
  v_projection_link boolean:=false;
  v_scope_link boolean:=false;
  v_correction_link boolean:=false;
  v_fingerprint text;
begin
  select
    fixture.id,fixture.league_id,fixture.matchday_id,fixture.finalized_at,
    fixture.official_projection_id,fixture.officialization_run_id,
    fixture.correction_run_id,fixture.result_revision
  into v_fixture
  from public.fantasy_fixtures fixture
  where fixture.id=p_fixture_id;

  if not found then
    return jsonb_build_object('available',false,'reasonCode','lineage.fixture_not_found');
  end if;

  if v_fixture.official_projection_id is not null then
    select projection.id,projection.fixture_id
    into v_projection
    from public.live_fixture_projection_runs projection
    where projection.id=v_fixture.official_projection_id;
  end if;

  if v_fixture.officialization_run_id is not null then
    select
      run.id,run.league_id,run.matchday_id,run.source_projection_ids,
      run.source_correction_run_ids,run.superseded_at,run.finalized_at,
      run.finalization_revision
    into v_officialization
    from public.matchday_officialization_runs run
    where run.id=v_fixture.officialization_run_id;
  end if;

  if v_fixture.finalized_at is null then
    v_status:='reopened';
    v_reason:='lineage.fixture_reopened';
    v_projection_link:=v_fixture.official_projection_id is null;
    v_scope_link:=v_fixture.officialization_run_id is null;
    v_correction_link:=true;
  elsif v_fixture.official_projection_id is null
     or v_fixture.officialization_run_id is null then
    v_status:='assembling';
    v_reason:='lineage.commit_link_pending';
    v_projection_link:=v_fixture.official_projection_id is not null;
    v_scope_link:=v_fixture.officialization_run_id is not null;
    v_correction_link:=v_fixture.correction_run_id is null;
  else
    v_projection_link:=v_projection.id is not null
      and v_projection.fixture_id=v_fixture.id
      and coalesce(v_officialization.source_projection_ids,'[]'::jsonb)
        @> jsonb_build_array(v_fixture.official_projection_id);

    v_scope_link:=v_officialization.id is not null
      and v_officialization.league_id=v_fixture.league_id
      and v_officialization.matchday_id=v_fixture.matchday_id
      and v_officialization.superseded_at is null;

    v_correction_link:=v_fixture.correction_run_id is null
      or coalesce(v_officialization.source_correction_run_ids,'[]'::jsonb)
        @> jsonb_build_array(v_fixture.correction_run_id);

    if not v_projection_link then
      v_status:='invalid';
      v_reason:='lineage.projection_link_invalid';
    elsif not v_scope_link then
      v_status:='invalid';
      v_reason:='lineage.officialization_scope_invalid';
    elsif not v_correction_link then
      v_status:='invalid';
      v_reason:='lineage.correction_link_missing';
    else
      v_status:='certified';
      v_reason:='lineage.commit_certified';
    end if;
  end if;

  v_fingerprint:=md5(jsonb_build_object(
    'fixtureId',v_fixture.id,'leagueId',v_fixture.league_id,
    'matchdayId',v_fixture.matchday_id,'status',v_status,'reason',v_reason,
    'officialProjectionId',v_fixture.official_projection_id,
    'officializationRunId',v_fixture.officialization_run_id,
    'correctionRunId',v_fixture.correction_run_id,
    'fixtureResultRevision',v_fixture.result_revision,
    'projectionLinkCertified',v_projection_link,
    'officializationScopeCertified',v_scope_link,
    'correctionLinkCertified',v_correction_link
  )::text);

  return jsonb_build_object(
    'available',true,'fixtureId',v_fixture.id,'leagueId',v_fixture.league_id,
    'matchdayId',v_fixture.matchday_id,'lineageStatus',v_status,
    'reasonCode',v_reason,'lineageReadyForImpact',v_status<>'assembling',
    'officialProjectionId',v_fixture.official_projection_id,
    'officializationRunId',v_fixture.officialization_run_id,
    'correctionRunId',v_fixture.correction_run_id,
    'fixtureResultRevision',v_fixture.result_revision,
    'projectionLinkCertified',v_projection_link,
    'officializationScopeCertified',v_scope_link,
    'correctionLinkCertified',v_correction_link,
    'lineageFingerprint',v_fingerprint
  );
end;
$function$;
revoke all on function public.compute_provider_official_result_lineage_v1(uuid) from public,anon,authenticated;
grant execute on function public.compute_provider_official_result_lineage_v1(uuid) to service_role;

create or replace function public.reconcile_provider_official_result_lineage_v1(p_fixture_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_assessment jsonb;
  v_existing public.provider_official_result_lineage_heads%rowtype;
  v_head public.provider_official_result_lineage_heads%rowtype;
  v_generation bigint;
  v_changed boolean;
  v_event_fingerprint text;
  v_status text;
  v_matchday_id uuid;
begin
  if p_fixture_id is null then
    return jsonb_build_object('available',false,'reasonCode','lineage.fixture_missing');
  end if;

  v_assessment:=public.compute_provider_official_result_lineage_v1(p_fixture_id);
  if coalesce((v_assessment->>'available')::boolean,false)=false then
    return v_assessment;
  end if;

  v_status:=v_assessment->>'lineageStatus';
  v_matchday_id:=(v_assessment->>'matchdayId')::uuid;

  perform set_config('leghevo.provider_official_result_lineage_context','on',true);

  select head.* into v_existing
  from public.provider_official_result_lineage_heads head
  where head.fixture_id=p_fixture_id
  for update;

  v_changed:=not found
    or v_existing.lineage_fingerprint is distinct from v_assessment->>'lineageFingerprint';
  v_generation:=case
    when v_existing.id is null then 1
    when v_changed then v_existing.lineage_generation+1
    else v_existing.lineage_generation
  end;

  insert into public.provider_official_result_lineage_heads(
    league_id,matchday_id,fixture_id,lineage_status,reason_code,lineage_generation,
    official_projection_id,officialization_run_id,correction_run_id,
    fixture_result_revision,projection_link_certified,
    officialization_scope_certified,correction_link_certified,
    lineage_fingerprint,first_certified_at,last_assessed_at,updated_at
  ) values(
    (v_assessment->>'leagueId')::uuid,(v_assessment->>'matchdayId')::uuid,p_fixture_id,
    v_status,v_assessment->>'reasonCode',v_generation,
    nullif(v_assessment->>'officialProjectionId','')::bigint,
    nullif(v_assessment->>'officializationRunId','')::bigint,
    nullif(v_assessment->>'correctionRunId','')::bigint,
    coalesce((v_assessment->>'fixtureResultRevision')::integer,0),
    coalesce((v_assessment->>'projectionLinkCertified')::boolean,false),
    coalesce((v_assessment->>'officializationScopeCertified')::boolean,false),
    coalesce((v_assessment->>'correctionLinkCertified')::boolean,false),
    v_assessment->>'lineageFingerprint',
    case when v_status='certified' then now() else null end,
    now(),now()
  )
  on conflict(fixture_id) do update set
    league_id=excluded.league_id,matchday_id=excluded.matchday_id,
    lineage_status=excluded.lineage_status,reason_code=excluded.reason_code,
    lineage_generation=excluded.lineage_generation,
    official_projection_id=excluded.official_projection_id,
    officialization_run_id=excluded.officialization_run_id,
    correction_run_id=excluded.correction_run_id,
    fixture_result_revision=excluded.fixture_result_revision,
    projection_link_certified=excluded.projection_link_certified,
    officialization_scope_certified=excluded.officialization_scope_certified,
    correction_link_certified=excluded.correction_link_certified,
    lineage_fingerprint=excluded.lineage_fingerprint,
    first_certified_at=case
      when public.provider_official_result_lineage_heads.first_certified_at is not null
        then public.provider_official_result_lineage_heads.first_certified_at
      when excluded.lineage_status='certified' then now() else null end,
    last_assessed_at=now(),
    updated_at=case when v_changed then now() else public.provider_official_result_lineage_heads.updated_at end
  returning * into v_head;

  if v_changed then
    v_event_fingerprint:=md5(
      v_head.id::text||E'\n'||v_head.lineage_generation::text||E'\n'||
      v_head.lineage_fingerprint
    );
    insert into public.provider_official_result_lineage_events(
      head_id,league_id,matchday_id,fixture_id,lineage_status,reason_code,
      lineage_generation,official_projection_id,officialization_run_id,
      correction_run_id,fixture_result_revision,projection_link_certified,
      officialization_scope_certified,correction_link_certified,
      lineage_fingerprint,event_fingerprint,created_at
    ) values(
      v_head.id,v_head.league_id,v_head.matchday_id,v_head.fixture_id,
      v_head.lineage_status,v_head.reason_code,v_head.lineage_generation,
      v_head.official_projection_id,v_head.officialization_run_id,
      v_head.correction_run_id,v_head.fixture_result_revision,
      v_head.projection_link_certified,v_head.officialization_scope_certified,
      v_head.correction_link_certified,v_head.lineage_fingerprint,
      v_event_fingerprint,now()
    ) on conflict(event_fingerprint) do nothing;
  end if;

  perform set_config('leghevo.provider_official_result_lineage_context','',true);

  -- Durante il primo UPDATE dell'ufficializzazione manca ancora officialization_run_id.
  -- In quello stato non deve nascere un falso impatto provider. Il secondo UPDATE
  -- ricontatta questo flusso e avvia la valutazione soltanto a lineage completa.
  if v_status<>'assembling' then
    perform public.reconcile_provider_official_result_impact_v1(v_matchday_id);
  end if;

  return v_assessment||jsonb_build_object(
    'headId',v_head.id,'lineageGeneration',v_head.lineage_generation,
    'changed',v_changed
  );
exception when others then
  perform set_config('leghevo.provider_official_result_lineage_context','',true);
  raise;
end;
$function$;
revoke all on function public.reconcile_provider_official_result_lineage_v1(uuid) from public,anon,authenticated;
grant execute on function public.reconcile_provider_official_result_lineage_v1(uuid) to service_role;

-- Evoluzione della valutazione d'impatto: una lineage ancora in assemblaggio non
-- produce più un falso stato affected; una lineage completa ma incoerente viene
-- invece trattata come impatto reale e resta disponibile per la remediation.
create or replace function public.compute_provider_official_result_impact_v1(p_fixture_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $function$
declare
  v_fixture record;
  v_lineage jsonb;
  v_lineage_status text;
  v_lineage_fingerprint text;
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

  v_lineage:=public.compute_provider_official_result_lineage_v1(p_fixture_id);
  if coalesce((v_lineage->>'available')::boolean,false)=false then
    return jsonb_build_object('available',false,'reasonCode','impact.lineage_unavailable');
  end if;
  v_lineage_status:=v_lineage->>'lineageStatus';
  v_lineage_fingerprint:=v_lineage->>'lineageFingerprint';

  if v_lineage_status='assembling' then
    return jsonb_build_object(
      'available',false,'fixtureId',v_fixture.id,'leagueId',v_fixture.league_id,
      'matchdayId',v_fixture.matchday_id,'reasonCode','impact.lineage_commit_pending',
      'lineageStatus',v_lineage_status,'lineageFingerprint',v_lineage_fingerprint
    );
  elsif v_fixture.finalized_at is null then
    v_status:='in_correction';
    v_reason:='impact.fixture_reopened';
  elsif v_lineage_status='invalid' then
    v_status:='affected';
    v_reason:='impact.official_lineage_invalid';
    v_sides:=2;
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
    'lineageStatus',v_lineage_status,'lineageFingerprint',v_lineage_fingerprint,
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
    'lineageStatus',v_lineage_status,'lineageFingerprint',v_lineage_fingerprint,
    'officialHomeInputHash',v_fixture.official_home_input_hash,
    'officialAwayInputHash',v_fixture.official_away_input_hash,
    'currentHomeInputHash',v_current_home_hash,'currentAwayInputHash',v_current_away_hash,
    'riskFingerprint',v_risk
  );
end;
$function$;
revoke all on function public.compute_provider_official_result_impact_v1(uuid) from public,anon,authenticated;
grant execute on function public.compute_provider_official_result_impact_v1(uuid) to service_role;

create or replace function public.reconcile_provider_official_result_lineage_from_fixture_v1()
returns trigger
language plpgsql
security definer
set search_path=''
as $function$
begin
  -- Le partite non ancora giocate non appartengono alla lineage ufficiale.
  if new.finalized_at is null
    and new.correction_run_id is null
    and not exists(select 1 from public.provider_official_result_lineage_heads head where head.fixture_id=new.id)
    and not exists(select 1 from public.provider_official_result_impact_heads impact where impact.fixture_id=new.id)
    and not exists(select 1 from public.provider_official_result_remediation_heads remediation where remediation.fixture_id=new.id) then
    return new;
  end if;

  perform public.reconcile_provider_official_result_lineage_v1(new.id);
  return new;
end;
$function$;
revoke all on function public.reconcile_provider_official_result_lineage_from_fixture_v1() from public,anon,authenticated;

-- Sostituisce il trigger della v0.62.22: ora viene ascoltato anche il secondo
-- UPDATE che collega officialization_run_id, senza registrare un falso impatto
-- durante la fase intermedia della stessa transazione.
drop trigger if exists provider_official_result_impact_fixture_writer
on public.fantasy_fixtures;
create trigger provider_official_result_impact_fixture_writer
after insert or update of finalized_at,official_projection_id,officialization_run_id,correction_run_id,result_revision
on public.fantasy_fixtures
for each row execute function public.reconcile_provider_official_result_lineage_from_fixture_v1();
alter table public.fantasy_fixtures enable always trigger provider_official_result_impact_fixture_writer;

-- Backfill non distruttivo. Gli eventuali record invalidi vengono soltanto
-- certificati e segnalati; nessun risultato o collegamento esistente è mutato.
do $backfill$
declare
  v_fixture_id uuid;
begin
  for v_fixture_id in
    select fixture.id
    from public.fantasy_fixtures fixture
    where fixture.finalized_at is not null
       or fixture.correction_run_id is not null
       or exists(select 1 from public.provider_official_result_impact_heads impact where impact.fixture_id=fixture.id)
       or exists(select 1 from public.provider_official_result_remediation_heads remediation where remediation.fixture_id=fixture.id)
    order by fixture.id
  loop
    perform public.reconcile_provider_official_result_lineage_v1(v_fixture_id);
  end loop;
end;
$backfill$;

create or replace function public.get_league_provider_official_result_lineage_v1(p_league_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $function$
declare
  v_owner_id uuid;
  v_certified integer:=0;
  v_assembling integer:=0;
  v_invalid integer:=0;
  v_reopened integer:=0;
  v_events_24h integer:=0;
  v_latest jsonb;
begin
  if auth.uid() is null then raise exception 'Devi effettuare l''accesso.'; end if;
  select league_row.owner_id into v_owner_id
  from public.leagues league_row where league_row.id=p_league_id;
  if not found then raise exception 'Lega non trovata per la lineage ufficiale provider.'; end if;
  if v_owner_id<>auth.uid() and not public.is_league_admin(p_league_id) then
    raise exception 'Solo Presidente e Admin possono leggere la lineage ufficiale provider.';
  end if;

  select
    count(*) filter(where head.lineage_status='certified')::integer,
    count(*) filter(where head.lineage_status='assembling')::integer,
    count(*) filter(where head.lineage_status='invalid')::integer,
    count(*) filter(where head.lineage_status='reopened')::integer
  into v_certified,v_assembling,v_invalid,v_reopened
  from public.provider_official_result_lineage_heads head
  where head.league_id=p_league_id;

  select count(*)::integer into v_events_24h
  from public.provider_official_result_lineage_events event_row
  where event_row.league_id=p_league_id and event_row.created_at>=now()-interval '24 hours';

  select jsonb_build_object(
    'id',event_row.id,'fixtureId',event_row.fixture_id,'matchdayId',event_row.matchday_id,
    'lineageStatus',event_row.lineage_status,'reasonCode',event_row.reason_code,
    'lineageGeneration',event_row.lineage_generation,
    'fixtureResultRevision',event_row.fixture_result_revision,
    'createdAt',event_row.created_at
  ) into v_latest
  from public.provider_official_result_lineage_events event_row
  where event_row.league_id=p_league_id
  order by event_row.created_at desc limit 1;

  return jsonb_build_object(
    'protected',true,'healthy',v_assembling=0 and v_invalid=0,
    'officializationCommitBarrierActive',true,
    'transientMissingLineageSuppressed',true,
    'correctionSourceLinkCertified',true,
    'certifiedFixtureCount',v_certified,'assemblingFixtureCount',v_assembling,
    'invalidFixtureCount',v_invalid,'reopenedFixtureCount',v_reopened,
    'eventsLast24h',v_events_24h,'latestEvent',v_latest
  );
end;
$function$;
revoke all on function public.get_league_provider_official_result_lineage_v1(uuid) from public,anon,service_role;
grant execute on function public.get_league_provider_official_result_lineage_v1(uuid) to authenticated;

create or replace function public.get_league_provider_sync_health_v23(p_league_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $function$
declare
  v_base jsonb;
  v_lineage jsonb;
  v_healthy boolean;
  v_status text;
begin
  v_base:=public.get_league_provider_sync_health_v22(p_league_id);
  v_lineage:=public.get_league_provider_official_result_lineage_v1(p_league_id);
  v_healthy:=coalesce((v_base->>'healthy')::boolean,false)
    and coalesce((v_lineage->>'healthy')::boolean,false);
  v_status:=case when not v_healthy then 'attention' else coalesce(v_base->>'status','idle') end;
  return v_base||jsonb_build_object(
    'protected',coalesce((v_base->>'protected')::boolean,false)
      and coalesce((v_lineage->>'protected')::boolean,false),
    'healthy',v_healthy,'status',v_status,'officialResultLineage',v_lineage
  );
end;
$function$;
revoke all on function public.get_league_provider_sync_health_v23(uuid) from public,anon,service_role;
grant execute on function public.get_league_provider_sync_health_v23(uuid) to authenticated;

create or replace function public.get_provider_official_result_lineage_integrity_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $function$
declare
  v_predecessor jsonb;
  v_compute_lineage text;
  v_reconcile_lineage text;
  v_compute_impact text;
  v_trigger text;
  v_center text;
  v_health text;
begin
  v_predecessor:=public.get_provider_official_result_remediation_integrity_v1();
  v_compute_lineage:=lower(pg_catalog.pg_get_functiondef('public.compute_provider_official_result_lineage_v1(uuid)'::regprocedure));
  v_reconcile_lineage:=lower(pg_catalog.pg_get_functiondef('public.reconcile_provider_official_result_lineage_v1(uuid)'::regprocedure));
  v_compute_impact:=lower(pg_catalog.pg_get_functiondef('public.compute_provider_official_result_impact_v1(uuid)'::regprocedure));
  select lower(pg_catalog.pg_get_triggerdef(trigger_row.oid,true)) into v_trigger
  from pg_catalog.pg_trigger trigger_row
  where trigger_row.tgrelid='public.fantasy_fixtures'::regclass
    and trigger_row.tgname='provider_official_result_impact_fixture_writer'
    and not trigger_row.tgisinternal;
  v_center:=lower(pg_catalog.pg_get_functiondef('public.get_league_provider_official_result_lineage_v1(uuid)'::regprocedure));
  v_health:=lower(pg_catalog.pg_get_functiondef('public.get_league_provider_sync_health_v23(uuid)'::regprocedure));

  return jsonb_build_object(
    'predecessor_ready',(select count(*) from jsonb_each(v_predecessor))=20
      and not exists(select 1 from jsonb_each(v_predecessor) check_row where check_row.value is distinct from 'true'::jsonb),
    'head_table_ready',to_regclass('public.provider_official_result_lineage_heads') is not null,
    'event_table_ready',to_regclass('public.provider_official_result_lineage_events') is not null,
    'constraints_ready',(select count(*)>=5 from pg_catalog.pg_constraint where conrelid='public.provider_official_result_lineage_heads'::regclass)
      and (select count(*)>=5 from pg_catalog.pg_constraint where conrelid='public.provider_official_result_lineage_events'::regclass),
    'indexes_ready',to_regclass('public.provider_official_result_lineage_heads_league_idx') is not null
      and to_regclass('public.provider_official_result_lineage_events_league_idx') is not null,
    'rls_ready',(select relrowsecurity from pg_catalog.pg_class where oid='public.provider_official_result_lineage_heads'::regclass)
      and (select relrowsecurity from pg_catalog.pg_class where oid='public.provider_official_result_lineage_events'::regclass)
      and exists(select 1 from pg_catalog.pg_policy policy_row
        where policy_row.polrelid='public.provider_official_result_lineage_heads'::regclass
          and policy_row.polname='provider_official_result_lineage_heads_read_directors')
      and exists(select 1 from pg_catalog.pg_policy policy_row
        where policy_row.polrelid='public.provider_official_result_lineage_events'::regclass
          and policy_row.polname='provider_official_result_lineage_events_read_directors'),
    'authenticated_write_blocked',not has_table_privilege('authenticated','public.provider_official_result_lineage_heads','INSERT')
      and not has_table_privilege('authenticated','public.provider_official_result_lineage_heads','UPDATE')
      and not has_table_privilege('authenticated','public.provider_official_result_lineage_events','INSERT'),
    'service_role_ready',has_table_privilege('service_role','public.provider_official_result_lineage_heads','SELECT')
      and has_table_privilege('service_role','public.provider_official_result_lineage_heads','INSERT')
      and has_table_privilege('service_role','public.provider_official_result_lineage_heads','UPDATE')
      and has_table_privilege('service_role','public.provider_official_result_lineage_events','SELECT')
      and has_table_privilege('service_role','public.provider_official_result_lineage_events','INSERT'),
    'immutable_events_ready',exists(select 1 from pg_catalog.pg_trigger trigger_row
      where trigger_row.tgrelid='public.provider_official_result_lineage_events'::regclass
        and trigger_row.tgname='provider_official_result_lineage_events_immutable'
        and trigger_row.tgenabled='A' and not trigger_row.tgisinternal),
    'head_guard_ready',exists(select 1 from pg_catalog.pg_trigger trigger_row
      where trigger_row.tgrelid='public.provider_official_result_lineage_heads'::regclass
        and trigger_row.tgname='provider_official_result_lineage_heads_guard'
        and trigger_row.tgenabled='A' and not trigger_row.tgisinternal),
    'compute_lineage_rpc_ready',to_regprocedure('public.compute_provider_official_result_lineage_v1(uuid)') is not null
      and position('lineage.commit_link_pending' in v_compute_lineage)>0
      and position('source_projection_ids' in v_compute_lineage)>0
      and position('source_correction_run_ids' in v_compute_lineage)>0,
    'reconcile_lineage_rpc_ready',to_regprocedure('public.reconcile_provider_official_result_lineage_v1(uuid)') is not null
      and position('v_status<>''assembling''' in replace(v_reconcile_lineage,' ',''))>0
      and position('reconcile_provider_official_result_impact_v1' in v_reconcile_lineage)>0,
    'impact_barrier_ready',position('impact.lineage_commit_pending' in v_compute_impact)>0
      and position('impact.official_lineage_invalid' in v_compute_impact)>0
      and position('compute_provider_official_result_lineage_v1' in v_compute_impact)>0,
    'fixture_trigger_ready',coalesce(position('officialization_run_id' in v_trigger)>0,false)
      and coalesce(position('correction_run_id' in v_trigger)>0,false)
      and coalesce(position('reconcile_provider_official_result_lineage_from_fixture_v1' in v_trigger)>0,false),
    'backfill_ready',not exists(
      select 1 from public.fantasy_fixtures fixture
      where (fixture.finalized_at is not null
          or fixture.correction_run_id is not null
          or exists(select 1 from public.provider_official_result_impact_heads impact where impact.fixture_id=fixture.id)
          or exists(select 1 from public.provider_official_result_remediation_heads remediation where remediation.fixture_id=fixture.id))
        and not exists(select 1 from public.provider_official_result_lineage_heads head where head.fixture_id=fixture.id)
    ),
    'source_links_ready',position('source_projection_ids' in v_compute_lineage)>0
      and position('source_correction_run_ids' in v_compute_lineage)>0
      and position('v_projection.fixture_id=v_fixture.id' in replace(v_compute_lineage,' ',''))>0
      and position('v_officialization.league_id=v_fixture.league_id' in replace(v_compute_lineage,' ',''))>0
      and position('v_officialization.matchday_id=v_fixture.matchday_id' in replace(v_compute_lineage,' ',''))>0
      and position('projectionlinkcertified' in replace(v_compute_lineage,'_',''))>0
      and position('officializationscopecertified' in replace(v_compute_lineage,'_',''))>0
      and position('correctionlinkcertified' in replace(v_compute_lineage,'_',''))>0,
    'center_rpc_ready',to_regprocedure('public.get_league_provider_official_result_lineage_v1(uuid)') is not null
      and position('officializationcommitbarrieractive' in replace(v_center,'_',''))>0,
    'health_v23_ready',to_regprocedure('public.get_league_provider_sync_health_v23(uuid)') is not null
      and position('officialresultlineage' in replace(v_health,'_',''))>0,
    'realtime_events_ready',exists(select 1 from pg_catalog.pg_publication_tables publication_row
      where publication_row.pubname='supabase_realtime' and publication_row.schemaname='public'
        and publication_row.tablename='provider_official_result_lineage_events')
      or not exists(select 1 from pg_catalog.pg_publication publication_row where publication_row.pubname='supabase_realtime'),
    'rpc_grants_ready',has_function_privilege('authenticated','public.get_league_provider_official_result_lineage_v1(uuid)','EXECUTE')
      and has_function_privilege('authenticated','public.get_league_provider_sync_health_v23(uuid)','EXECUTE')
      and not has_function_privilege('authenticated','public.reconcile_provider_official_result_lineage_v1(uuid)','EXECUTE')
  );
end;
$function$;
revoke all on function public.get_provider_official_result_lineage_integrity_v1() from public,anon,authenticated;
grant execute on function public.get_provider_official_result_lineage_integrity_v1() to service_role;

do $realtime$
begin
  if exists(select 1 from pg_catalog.pg_publication where pubname='supabase_realtime') then
    if not exists(select 1 from pg_catalog.pg_publication_tables
      where pubname='supabase_realtime' and schemaname='public'
        and tablename='provider_official_result_lineage_events') then
      execute 'alter publication supabase_realtime add table public.provider_official_result_lineage_events';
    end if;
  end if;
end;
$realtime$;

do $validation$
declare
  v_checks jsonb;
  v_failed text;
begin
  v_checks:=public.get_provider_official_result_lineage_integrity_v1();
  select string_agg(check_row.key,', ' order by check_row.key) into v_failed
  from jsonb_each(v_checks) check_row
  where jsonb_typeof(check_row.value) is distinct from 'boolean'
     or check_row.value is distinct from 'true'::jsonb;
  if (select count(*) from jsonb_each(v_checks))<>20 or v_failed is not null then
    raise exception 'Validazione v0.62.24 non superata. Controlli falsi: %',coalesce(v_failed,'numero_controlli_non_valido');
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
  (checks->>'compute_lineage_rpc_ready')::boolean as compute_lineage_rpc_ready,
  (checks->>'reconcile_lineage_rpc_ready')::boolean as reconcile_lineage_rpc_ready,
  (checks->>'impact_barrier_ready')::boolean as impact_barrier_ready,
  (checks->>'fixture_trigger_ready')::boolean as fixture_trigger_ready,
  (checks->>'backfill_ready')::boolean as backfill_ready,
  (checks->>'source_links_ready')::boolean as source_links_ready,
  (checks->>'center_rpc_ready')::boolean as center_rpc_ready,
  (checks->>'health_v23_ready')::boolean as health_v23_ready,
  (checks->>'realtime_events_ready')::boolean as realtime_events_ready,
  (checks->>'rpc_grants_ready')::boolean as rpc_grants_ready
from (select public.get_provider_official_result_lineage_integrity_v1() as checks) diagnostic;
