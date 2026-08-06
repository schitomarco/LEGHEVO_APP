-- LEGHEVO v0.62.28
-- Snapshot ufficiale immutabile della stagione.
-- Migrazione interna: database/132_league_season_official_snapshot_safety.sql
-- Eseguire dopo database/131_provider_season_completion_causal_barrier_safety.sql.
-- La migrazione non riscrive classifiche o campioni già ufficializzati:
-- adotta il riepilogo certificato esistente e separa lo stato corrente
-- dall'artefatto storico immutabile.

begin;

-- PRE-FLIGHT: la barriera causale della v0.62.27 deve essere integra.
do $preflight$
declare
  v_missing text[] := array[]::text[];
  v_checks jsonb;
begin
  if to_regprocedure('public.get_provider_season_completion_gate_integrity_v1()') is null then
    v_missing := array_append(v_missing,
      'function public.get_provider_season_completion_gate_integrity_v1()');
  else
    v_checks := public.get_provider_season_completion_gate_integrity_v1();
    if (select count(*) from jsonb_each(v_checks)) <> 20
      or exists (
        select 1
        from jsonb_each(v_checks) check_row
        where jsonb_typeof(check_row.value) is distinct from 'boolean'
           or check_row.value is distinct from 'true'::jsonb
      ) then
      v_missing := array_append(v_missing,
        'v0.62.27 integrity: all 20 checks must be true');
    end if;
  end if;

  if to_regclass('public.league_season_summaries') is null then
    v_missing := array_append(v_missing,'table public.league_season_summaries');
  end if;
  if to_regclass('public.season_completion_runs') is null then
    v_missing := array_append(v_missing,'table public.season_completion_runs');
  end if;
  if to_regclass('public.provider_season_completion_gate_heads') is null then
    v_missing := array_append(v_missing,
      'table public.provider_season_completion_gate_heads');
  end if;

  if exists (
    select 1
    from (values
      ('leagues','id'),('leagues','owner_id'),('leagues','status'),
      ('leagues','champion_team_id'),('leagues','competition_completed_at'),
      ('league_season_summaries','league_id'),
      ('league_season_summaries','season'),
      ('league_season_summaries','champion_team_id'),
      ('league_season_summaries','champion_team_name'),
      ('league_season_summaries','champion_manager_name'),
      ('league_season_summaries','champion_source'),
      ('league_season_summaries','standings_tiebreaker'),
      ('league_season_summaries','fixture_count'),
      ('league_season_summaries','final_standings'),
      ('league_season_summaries','completed_at'),
      ('league_season_summaries','completed_by'),
      ('season_completion_runs','id'),
      ('season_completion_runs','league_id'),
      ('season_completion_runs','final_progression_run_id'),
      ('season_completion_runs','final_officialization_run_id'),
      ('season_completion_runs','input_hash'),
      ('season_completion_runs','standings_hash'),
      ('season_completion_runs','final_standings'),
      ('season_completion_runs','champion_team_id'),
      ('season_completion_runs','champion_team_name'),
      ('season_completion_runs','champion_manager_name'),
      ('season_completion_runs','champion_source'),
      ('season_completion_runs','season'),
      ('season_completion_runs','fixture_count'),
      ('season_completion_runs','completed_by'),
      ('season_completion_runs','completed_at'),
      ('provider_season_completion_gate_heads','id'),
      ('provider_season_completion_gate_heads','league_id'),
      ('provider_season_completion_gate_heads','current_completion_run_id'),
      ('provider_season_completion_gate_heads','final_progression_run_id'),
      ('provider_season_completion_gate_heads','gate_status'),
      ('provider_season_completion_gate_heads','reason_code'),
      ('provider_season_completion_gate_heads','gate_generation'),
      ('provider_season_completion_gate_heads','gate_fingerprint')
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
      'required columns for immutable season snapshot');
  end if;

  if to_regprocedure('public.complete_league_season_guarded_v2(uuid,uuid)') is null then
    v_missing := array_append(v_missing,
      'RPC public.complete_league_season_guarded_v2(uuid,uuid)');
  end if;
  if to_regprocedure('public.get_league_season_state_v5(uuid)') is null then
    v_missing := array_append(v_missing,
      'RPC public.get_league_season_state_v5(uuid)');
  end if;
  if to_regprocedure('public.get_league_management_state_v15(uuid)') is null then
    v_missing := array_append(v_missing,
      'RPC public.get_league_management_state_v15(uuid)');
  end if;
  if to_regprocedure('public.get_league_provider_sync_health_v26(uuid)') is null then
    v_missing := array_append(v_missing,
      'RPC public.get_league_provider_sync_health_v26(uuid)');
  end if;
  if to_regprocedure('public.reconcile_provider_season_completion_gate_v1(uuid)') is null then
    v_missing := array_append(v_missing,
      'RPC public.reconcile_provider_season_completion_gate_v1(uuid)');
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

  if cardinality(v_missing)>0 then
    raise exception
      'Preflight v0.62.28 non superato. Dipendenze mancanti: %',
      array_to_string(v_missing,'; ');
  end if;
end;
$preflight$;

create table if not exists public.league_season_official_snapshots (
  id bigint generated by default as identity primary key,
  league_id uuid not null unique
    references public.leagues(id) on delete restrict,
  completion_run_id bigint not null unique
    references public.season_completion_runs(id) on delete restrict,
  completion_gate_head_id uuid not null
    references public.provider_season_completion_gate_heads(id)
    on delete restrict,
  completion_gate_generation bigint not null,
  completion_gate_fingerprint text not null,
  final_progression_run_id bigint not null
    references public.matchday_progression_runs(id) on delete restrict,
  final_officialization_run_id bigint not null
    references public.matchday_officialization_runs(id) on delete restrict,
  season text not null,
  champion_team_id uuid not null
    references public.fantasy_teams(id) on delete restrict,
  champion_team_name text not null,
  champion_manager_name text not null,
  champion_source text not null,
  standings_tiebreaker text not null,
  fixture_count integer not null,
  final_standings jsonb not null,
  podium jsonb not null,
  honours_snapshot jsonb not null,
  completion_input_hash text not null,
  standings_hash text not null,
  snapshot_hash text not null,
  officialized_by uuid references public.profiles(id) on delete set null,
  officialized_at timestamptz not null,
  created_at timestamptz not null default now(),
  result_payload jsonb not null default '{}'::jsonb,
  constraint league_season_official_snapshot_generation_check
    check (completion_gate_generation>=1),
  constraint league_season_official_snapshot_gate_hash_check
    check (length(completion_gate_fingerprint)=32),
  constraint league_season_official_snapshot_source_check
    check (champion_source in ('regular_season','playoffs')),
  constraint league_season_official_snapshot_tiebreaker_check
    check (standings_tiebreaker in (
      'goal_difference','fantasy_points','head_to_head'
    )),
  constraint league_season_official_snapshot_fixture_count_check
    check (fixture_count>0),
  constraint league_season_official_snapshot_standings_check
    check (
      jsonb_typeof(final_standings)='array'
      and jsonb_array_length(final_standings)>0
    ),
  constraint league_season_official_snapshot_podium_check
    check (
      jsonb_typeof(podium)='array'
      and jsonb_array_length(podium)>0
      and jsonb_array_length(podium)<=3
    ),
  constraint league_season_official_snapshot_honours_check
    check (jsonb_typeof(honours_snapshot)='object'),
  constraint league_season_official_snapshot_input_hash_check
    check (length(completion_input_hash)=32),
  constraint league_season_official_snapshot_standings_hash_check
    check (length(standings_hash)=32),
  constraint league_season_official_snapshot_hash_check
    check (length(snapshot_hash)=32)
);

create table if not exists public.league_season_official_snapshot_heads (
  league_id uuid primary key
    references public.leagues(id) on delete restrict,
  snapshot_id bigint not null unique
    references public.league_season_official_snapshots(id) on delete restrict,
  snapshot_status text not null,
  reason_code text not null,
  observed_completion_gate_generation bigint not null,
  observed_completion_gate_fingerprint text not null,
  affected_at timestamptz,
  last_assessed_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint league_season_official_snapshot_heads_status_check
    check (snapshot_status in ('official','affected')),
  constraint league_season_official_snapshot_heads_reason_check
    check (char_length(trim(reason_code)) between 3 and 180),
  constraint league_season_official_snapshot_heads_generation_check
    check (observed_completion_gate_generation>=1),
  constraint league_season_official_snapshot_heads_fingerprint_check
    check (length(observed_completion_gate_fingerprint)=32),
  constraint league_season_official_snapshot_heads_affected_check
    check (
      (snapshot_status='official' and affected_at is null)
      or (snapshot_status='affected' and affected_at is not null)
    )
);

create table if not exists public.league_season_official_snapshot_events (
  id bigint generated by default as identity primary key,
  league_id uuid not null
    references public.leagues(id) on delete restrict,
  snapshot_id bigint not null
    references public.league_season_official_snapshots(id) on delete restrict,
  event_type text not null,
  snapshot_status text not null,
  reason_code text not null,
  completion_gate_generation bigint not null,
  completion_gate_fingerprint text not null,
  snapshot_hash text not null,
  event_payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint league_season_official_snapshot_events_type_check
    check (event_type in ('officialized','affected','revalidated')),
  constraint league_season_official_snapshot_events_status_check
    check (snapshot_status in ('official','affected')),
  constraint league_season_official_snapshot_events_reason_check
    check (char_length(trim(reason_code)) between 3 and 180),
  constraint league_season_official_snapshot_events_generation_check
    check (completion_gate_generation>=1),
  constraint league_season_official_snapshot_events_gate_hash_check
    check (length(completion_gate_fingerprint)=32),
  constraint league_season_official_snapshot_events_snapshot_hash_check
    check (length(snapshot_hash)=32),
  constraint league_season_official_snapshot_events_payload_check
    check (jsonb_typeof(event_payload)='object')
);

create index if not exists league_season_official_snapshots_created_idx
  on public.league_season_official_snapshots(league_id,created_at desc);
create index if not exists league_season_official_snapshot_heads_status_idx
  on public.league_season_official_snapshot_heads(snapshot_status,updated_at desc);
create index if not exists league_season_official_snapshot_events_league_idx
  on public.league_season_official_snapshot_events(league_id,created_at desc,id desc);

alter table public.league_season_official_snapshots enable row level security;
alter table public.league_season_official_snapshot_heads enable row level security;
alter table public.league_season_official_snapshot_events enable row level security;
alter table public.league_season_official_snapshot_events replica identity full;

revoke all on table public.league_season_official_snapshots
from public,anon,authenticated,service_role;
revoke all on table public.league_season_official_snapshot_heads
from public,anon,authenticated,service_role;
revoke all on table public.league_season_official_snapshot_events
from public,anon,authenticated,service_role;
grant select on table public.league_season_official_snapshots to authenticated;
grant select on table public.league_season_official_snapshot_heads to authenticated;
grant select on table public.league_season_official_snapshot_events to authenticated;
grant select on table public.league_season_official_snapshots to service_role;
grant select on table public.league_season_official_snapshot_heads to service_role;
grant select on table public.league_season_official_snapshot_events to service_role;

drop policy if exists league_season_official_snapshots_member_select
on public.league_season_official_snapshots;
create policy league_season_official_snapshots_member_select
on public.league_season_official_snapshots
for select to authenticated
using (
  public.is_league_member(league_id)
  or public.is_league_admin(league_id)
);

drop policy if exists league_season_official_snapshot_heads_member_select
on public.league_season_official_snapshot_heads;
create policy league_season_official_snapshot_heads_member_select
on public.league_season_official_snapshot_heads
for select to authenticated
using (
  public.is_league_member(league_id)
  or public.is_league_admin(league_id)
);

drop policy if exists league_season_official_snapshot_events_director_select
on public.league_season_official_snapshot_events;
create policy league_season_official_snapshot_events_director_select
on public.league_season_official_snapshot_events
for select to authenticated
using (
  public.is_league_admin(league_id)
  or exists (
    select 1 from public.leagues league_row
    where league_row.id=public.league_season_official_snapshot_events.league_id
      and league_row.owner_id=auth.uid()
  )
);

create or replace function public.guard_league_season_official_snapshot_v1()
returns trigger
language plpgsql
security definer
set search_path=''
as $function$
begin
  if tg_op='INSERT'
    and coalesce(current_setting(
      'leghevo.league_season_official_snapshot_context',true
    ),'')='on' then
    return new;
  end if;

  raise exception
    'Snapshot ufficiale immutabile: modifica diretta non consentita.';
end;
$function$;
revoke all on function public.guard_league_season_official_snapshot_v1()
from public,anon,authenticated,service_role;

drop trigger if exists league_season_official_snapshots_immutable
on public.league_season_official_snapshots;
create trigger league_season_official_snapshots_immutable
before insert or update or delete on public.league_season_official_snapshots
for each row execute function public.guard_league_season_official_snapshot_v1();
alter table public.league_season_official_snapshots
  enable always trigger league_season_official_snapshots_immutable;

create or replace function public.guard_league_season_official_snapshot_head_v1()
returns trigger
language plpgsql
security definer
set search_path=''
as $function$
begin
  if tg_op<>'DELETE'
    and coalesce(current_setting(
      'leghevo.league_season_official_snapshot_context',true
    ),'')='on' then
    return new;
  end if;

  raise exception
    'Stato snapshot ufficiale: modifica diretta non consentita.';
end;
$function$;
revoke all on function public.guard_league_season_official_snapshot_head_v1()
from public,anon,authenticated,service_role;

drop trigger if exists league_season_official_snapshot_heads_guard
on public.league_season_official_snapshot_heads;
create trigger league_season_official_snapshot_heads_guard
before insert or update or delete on public.league_season_official_snapshot_heads
for each row execute function public.guard_league_season_official_snapshot_head_v1();
alter table public.league_season_official_snapshot_heads
  enable always trigger league_season_official_snapshot_heads_guard;

create or replace function public.guard_league_season_official_snapshot_event_v1()
returns trigger
language plpgsql
security definer
set search_path=''
as $function$
begin
  if tg_op='INSERT'
    and coalesce(current_setting(
      'leghevo.league_season_official_snapshot_context',true
    ),'')='on' then
    return new;
  end if;

  raise exception
    'Storico snapshot ufficiale append-only: modifica non consentita.';
end;
$function$;
revoke all on function public.guard_league_season_official_snapshot_event_v1()
from public,anon,authenticated,service_role;

drop trigger if exists league_season_official_snapshot_events_immutable
on public.league_season_official_snapshot_events;
create trigger league_season_official_snapshot_events_immutable
before insert or update or delete on public.league_season_official_snapshot_events
for each row execute function public.guard_league_season_official_snapshot_event_v1();
alter table public.league_season_official_snapshot_events
  enable always trigger league_season_official_snapshot_events_immutable;

create or replace function public.publish_league_season_official_snapshot_v1(
  p_league_id uuid,
  p_completion_run_id bigint default null,
  p_allow_affected_adoption boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_completion public.season_completion_runs%rowtype;
  v_summary public.league_season_summaries%rowtype;
  v_gate public.provider_season_completion_gate_heads%rowtype;
  v_snapshot public.league_season_official_snapshots%rowtype;
  v_head public.league_season_official_snapshot_heads%rowtype;
  v_podium jsonb := '[]'::jsonb;
  v_champion_standing jsonb := '{}'::jsonb;
  v_honours jsonb := '{}'::jsonb;
  v_snapshot_hash text;
  v_status text;
  v_reason text;
  v_payload jsonb;
begin
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'provider-season-completion-chain:'||p_league_id::text,0
    )
  );
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'league-season-official-snapshot:'||p_league_id::text,0
    )
  );

  select snapshot_row.*
  into v_snapshot
  from public.league_season_official_snapshots snapshot_row
  where snapshot_row.league_id=p_league_id;

  if found then
    if p_completion_run_id is not null
      and v_snapshot.completion_run_id<>p_completion_run_id then
      raise exception
        'Snapshot ufficiale già pubblicato da un altro commit di stagione.';
    end if;

    select head.* into v_head
    from public.league_season_official_snapshot_heads head
    where head.league_id=p_league_id;

    return v_snapshot.result_payload || jsonb_build_object(
      'snapshotId',v_snapshot.id,
      'snapshotStatus',coalesce(v_head.snapshot_status,'official'),
      'snapshotAffected',coalesce(v_head.snapshot_status='affected',false),
      'snapshotReason',v_head.reason_code
    );
  end if;

  select completion.*
  into v_completion
  from public.season_completion_runs completion
  where completion.league_id=p_league_id
    and (p_completion_run_id is null or completion.id=p_completion_run_id)
  for share;

  if not found then
    raise exception 'Commit certificato della stagione non trovato.';
  end if;

  select summary.*
  into v_summary
  from public.league_season_summaries summary
  where summary.league_id=p_league_id
  for share;

  if not found then
    raise exception 'Riepilogo finale della stagione non trovato.';
  end if;

  perform public.reconcile_provider_season_completion_gate_v1(p_league_id);

  select gate.*
  into v_gate
  from public.provider_season_completion_gate_heads gate
  where gate.league_id=p_league_id
  for update;

  if not found then
    raise exception 'Gate provider della chiusura stagione non trovato.';
  end if;

  if v_gate.current_completion_run_id is distinct from v_completion.id
    or v_gate.final_progression_run_id
      is distinct from v_completion.final_progression_run_id then
    raise exception
      'Snapshot rifiutato: il gate provider non coincide con il commit finale.';
  end if;

  if v_gate.gate_status<>'clear' and not p_allow_affected_adoption then
    raise exception
      'Snapshot rifiutato [provider.season_completion_gate]: %',
      v_gate.reason_code;
  end if;

  if v_completion.standings_hash
      <>pg_catalog.md5(v_completion.final_standings::text)
    or v_summary.champion_team_id<>v_completion.champion_team_id
    or v_summary.final_standings is distinct from v_completion.final_standings
    or pg_catalog.md5(v_summary.final_standings::text)
      <>v_completion.standings_hash then
    raise exception
      'Snapshot rifiutato: riepilogo finale e commit non sono coerenti.';
  end if;

  select coalesce(jsonb_agg(entry.value order by entry.ordinality),'[]'::jsonb)
  into v_podium
  from jsonb_array_elements(v_completion.final_standings)
    with ordinality as entry(value,ordinality)
  where entry.ordinality<=3;

  select entry.value
  into v_champion_standing
  from jsonb_array_elements(v_completion.final_standings) entry(value)
  where entry.value->>'teamId'=v_completion.champion_team_id::text
  limit 1;

  if v_champion_standing is null then
    raise exception
      'Snapshot rifiutato: il campione non è presente nella classifica finale.';
  end if;

  v_honours := jsonb_build_object(
    'champion',jsonb_build_object(
      'teamId',v_completion.champion_team_id,
      'teamName',v_completion.champion_team_name,
      'managerName',v_completion.champion_manager_name,
      'source',v_completion.champion_source,
      'leaguePoints',coalesce(
        (v_champion_standing->>'leaguePoints')::numeric,0
      ),
      'pointsFor',coalesce(
        (v_champion_standing->>'pointsFor')::numeric,0
      )
    ),
    'podium',v_podium,
    'season',v_completion.season
  );

  v_snapshot_hash := pg_catalog.md5(jsonb_build_object(
    'leagueId',p_league_id,
    'completionRunId',v_completion.id,
    'completionGateHeadId',v_gate.id,
    'completionGateGeneration',v_gate.gate_generation,
    'completionGateFingerprint',v_gate.gate_fingerprint,
    'finalProgressionRunId',v_completion.final_progression_run_id,
    'finalOfficializationRunId',v_completion.final_officialization_run_id,
    'season',v_completion.season,
    'championTeamId',v_completion.champion_team_id,
    'championTeamName',v_completion.champion_team_name,
    'championManagerName',v_completion.champion_manager_name,
    'championSource',v_completion.champion_source,
    'standingsTiebreaker',v_summary.standings_tiebreaker,
    'fixtureCount',v_completion.fixture_count,
    'completionInputHash',v_completion.input_hash,
    'standingsHash',v_completion.standings_hash,
    'finalStandings',v_completion.final_standings,
    'podium',v_podium,
    'officializedAt',v_completion.completed_at
  )::text);

  v_status := case when v_gate.gate_status='clear'
    then 'official' else 'affected' end;
  v_reason := case when v_gate.gate_status='clear'
    then 'season_snapshot.officially_published'
    else 'season_snapshot.affected_at_adoption' end;

  v_payload := jsonb_build_object(
    'leagueId',p_league_id,
    'snapshotId',null,
    'completionRunId',v_completion.id,
    'snapshotStatus',v_status,
    'snapshotAffected',v_status='affected',
    'snapshotReason',v_reason,
    'snapshotHash',v_snapshot_hash,
    'standingsHash',v_completion.standings_hash,
    'completionGateGeneration',v_gate.gate_generation,
    'completionGateFingerprint',v_gate.gate_fingerprint,
    'championTeamId',v_completion.champion_team_id,
    'championTeamName',v_completion.champion_team_name,
    'championManagerName',v_completion.champion_manager_name,
    'championSource',v_completion.champion_source,
    'championLeaguePoints',coalesce(
      (v_champion_standing->>'leaguePoints')::numeric,0
    ),
    'championPointsFor',coalesce(
      (v_champion_standing->>'pointsFor')::numeric,0
    ),
    'season',v_completion.season,
    'podium',v_podium,
    'officializedAt',v_completion.completed_at
  );

  perform set_config(
    'leghevo.league_season_official_snapshot_context','on',true
  );

  insert into public.league_season_official_snapshots(
    league_id,completion_run_id,completion_gate_head_id,
    completion_gate_generation,completion_gate_fingerprint,
    final_progression_run_id,final_officialization_run_id,season,
    champion_team_id,champion_team_name,champion_manager_name,
    champion_source,standings_tiebreaker,fixture_count,final_standings,
    podium,honours_snapshot,completion_input_hash,standings_hash,
    snapshot_hash,officialized_by,officialized_at,result_payload
  ) values (
    p_league_id,v_completion.id,v_gate.id,v_gate.gate_generation,
    v_gate.gate_fingerprint,v_completion.final_progression_run_id,
    v_completion.final_officialization_run_id,v_completion.season,
    v_completion.champion_team_id,v_completion.champion_team_name,
    v_completion.champion_manager_name,v_completion.champion_source,
    v_summary.standings_tiebreaker,v_completion.fixture_count,
    v_completion.final_standings,v_podium,v_honours,v_completion.input_hash,
    v_completion.standings_hash,v_snapshot_hash,v_completion.completed_by,
    v_completion.completed_at,v_payload
  ) returning * into v_snapshot;

  v_payload := v_payload || jsonb_build_object('snapshotId',v_snapshot.id);

  insert into public.league_season_official_snapshot_heads(
    league_id,snapshot_id,snapshot_status,reason_code,
    observed_completion_gate_generation,
    observed_completion_gate_fingerprint,affected_at,
    last_assessed_at,updated_at
  ) values (
    p_league_id,v_snapshot.id,v_status,v_reason,v_gate.gate_generation,
    v_gate.gate_fingerprint,
    case when v_status='affected' then now() else null end,
    now(),now()
  ) returning * into v_head;

  insert into public.league_season_official_snapshot_events(
    league_id,snapshot_id,event_type,snapshot_status,reason_code,
    completion_gate_generation,completion_gate_fingerprint,
    snapshot_hash,event_payload
  ) values (
    p_league_id,v_snapshot.id,
    case when v_status='official' then 'officialized' else 'affected' end,
    v_status,v_reason,v_gate.gate_generation,v_gate.gate_fingerprint,
    v_snapshot_hash,jsonb_build_object(
      'completionRunId',v_completion.id,
      'providerReasonCode',v_gate.reason_code,
      'adoptedAffected',v_status='affected'
    )
  );

  perform set_config(
    'leghevo.league_season_official_snapshot_context','',true
  );

  return v_payload;
end;
$function$;
revoke all on function public.publish_league_season_official_snapshot_v1(
  uuid,bigint,boolean
) from public,anon,authenticated;
grant execute on function public.publish_league_season_official_snapshot_v1(
  uuid,bigint,boolean
) to service_role;

create or replace function public.reconcile_league_season_official_snapshot_v1(
  p_league_id uuid,
  p_refresh_provider boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_snapshot public.league_season_official_snapshots%rowtype;
  v_head public.league_season_official_snapshot_heads%rowtype;
  v_gate public.provider_season_completion_gate_heads%rowtype;
  v_unsafe boolean := false;
  v_reason text;
  v_event_type text;
  v_changed boolean := false;
begin
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'provider-season-completion-chain:'||p_league_id::text,0
    )
  );
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'league-season-official-snapshot:'||p_league_id::text,0
    )
  );

  if p_refresh_provider then
    -- Il refresh può attivare il trigger provider. Viene eseguito prima di
    -- leggere la testa, così questa invocazione non lavora su dati obsoleti.
    perform public.reconcile_provider_season_completion_gate_v1(p_league_id);
  end if;

  select snapshot_row.*
  into v_snapshot
  from public.league_season_official_snapshots snapshot_row
  where snapshot_row.league_id=p_league_id;

  if not found then
    return jsonb_build_object(
      'available',false,
      'reasonCode','season_snapshot.not_published'
    );
  end if;

  select head.*
  into v_head
  from public.league_season_official_snapshot_heads head
  where head.snapshot_id=v_snapshot.id
  for update;

  if not found then
    raise exception 'Testa dello snapshot ufficiale non trovata.';
  end if;

  select gate.* into v_gate
  from public.provider_season_completion_gate_heads gate
  where gate.league_id=p_league_id
  for update;

  v_unsafe := v_gate.id is null
    or v_gate.gate_status<>'clear'
    or v_gate.current_completion_run_id
      is distinct from v_snapshot.completion_run_id
    or v_gate.final_progression_run_id
      is distinct from v_snapshot.final_progression_run_id
    or v_gate.gate_generation
      is distinct from v_snapshot.completion_gate_generation
    or v_gate.gate_fingerprint
      is distinct from v_snapshot.completion_gate_fingerprint;

  v_reason := case
    when v_gate.id is null then 'season_snapshot.provider_gate_missing'
    when v_gate.gate_status<>'clear' then
      'season_snapshot.provider_gate_'||v_gate.gate_status
    when v_gate.current_completion_run_id
      is distinct from v_snapshot.completion_run_id then
      'season_snapshot.completion_run_changed'
    when v_gate.final_progression_run_id
      is distinct from v_snapshot.final_progression_run_id then
      'season_snapshot.final_progression_changed'
    when v_gate.gate_generation
      is distinct from v_snapshot.completion_gate_generation then
      'season_snapshot.provider_generation_changed'
    when v_gate.gate_fingerprint
      is distinct from v_snapshot.completion_gate_fingerprint then
      'season_snapshot.provider_fingerprint_changed'
    else 'season_snapshot.officially_published'
  end;

  v_changed := v_head.observed_completion_gate_generation
      is distinct from coalesce(
        v_gate.gate_generation,v_head.observed_completion_gate_generation
      )
    or v_head.observed_completion_gate_fingerprint
      is distinct from coalesce(
        v_gate.gate_fingerprint,v_head.observed_completion_gate_fingerprint
      )
    or (v_unsafe and v_head.snapshot_status<>'affected')
    or (v_unsafe and v_head.reason_code is distinct from v_reason)
    or (
      not v_unsafe
      and v_head.snapshot_status='affected'
      and v_head.reason_code is distinct from
        'season_snapshot.revalidated_but_still_affected'
    );

  if v_unsafe and v_changed then
    perform set_config(
      'leghevo.league_season_official_snapshot_context','on',true
    );

    update public.league_season_official_snapshot_heads
    set snapshot_status='affected',
        reason_code=v_reason,
        observed_completion_gate_generation=coalesce(
          v_gate.gate_generation,observed_completion_gate_generation
        ),
        observed_completion_gate_fingerprint=coalesce(
          v_gate.gate_fingerprint,observed_completion_gate_fingerprint
        ),
        affected_at=coalesce(affected_at,now()),
        last_assessed_at=now(),
        updated_at=now()
    where league_id=p_league_id
    returning * into v_head;

    insert into public.league_season_official_snapshot_events(
      league_id,snapshot_id,event_type,snapshot_status,reason_code,
      completion_gate_generation,completion_gate_fingerprint,
      snapshot_hash,event_payload
    ) values (
      p_league_id,v_snapshot.id,'affected','affected',v_reason,
      v_head.observed_completion_gate_generation,
      v_head.observed_completion_gate_fingerprint,
      v_snapshot.snapshot_hash,
      jsonb_build_object(
        'providerGateStatus',v_gate.gate_status,
        'providerReasonCode',v_gate.reason_code,
        'currentCompletionRunId',v_gate.current_completion_run_id,
        'finalProgressionRunId',v_gate.final_progression_run_id
      )
    );

    perform set_config(
      'leghevo.league_season_official_snapshot_context','',true
    );
  elsif not v_unsafe and v_head.snapshot_status='affected'
    and v_changed then
    -- La regressione resta storicamente affected: una successiva coerenza
    -- viene registrata, ma non riscrive né riabilita automaticamente lo snapshot.
    v_event_type := 'revalidated';
    perform set_config(
      'leghevo.league_season_official_snapshot_context','on',true
    );
    update public.league_season_official_snapshot_heads
    set reason_code='season_snapshot.revalidated_but_still_affected',
        observed_completion_gate_generation=v_gate.gate_generation,
        observed_completion_gate_fingerprint=v_gate.gate_fingerprint,
        last_assessed_at=now(),
        updated_at=now()
    where league_id=p_league_id
    returning * into v_head;

    insert into public.league_season_official_snapshot_events(
      league_id,snapshot_id,event_type,snapshot_status,reason_code,
      completion_gate_generation,completion_gate_fingerprint,
      snapshot_hash,event_payload
    ) values (
      p_league_id,v_snapshot.id,v_event_type,'affected',
      'season_snapshot.revalidated_but_still_affected',
      v_gate.gate_generation,v_gate.gate_fingerprint,
      v_snapshot.snapshot_hash,jsonb_build_object(
        'providerGateStatus',v_gate.gate_status,
        'manualReviewRequired',true
      )
    );
    perform set_config(
      'leghevo.league_season_official_snapshot_context','',true
    );
  end if;

  return jsonb_build_object(
    'available',true,
    'snapshotId',v_snapshot.id,
    'snapshotStatus',v_head.snapshot_status,
    'reasonCode',v_head.reason_code,
    'snapshotHash',v_snapshot.snapshot_hash,
    'affected',v_head.snapshot_status='affected',
    'changed',v_changed
  );
end;
$function$;
revoke all on function public.reconcile_league_season_official_snapshot_v1(uuid,boolean)
from public,anon,authenticated;
grant execute on function public.reconcile_league_season_official_snapshot_v1(uuid,boolean)
to service_role;

create or replace function public.publish_league_season_official_snapshot_from_completion_v1()
returns trigger
language plpgsql
security definer
set search_path=''
as $function$
begin
  perform public.publish_league_season_official_snapshot_v1(
    new.league_id,new.id,false
  );
  return new;
end;
$function$;
revoke all on function public.publish_league_season_official_snapshot_from_completion_v1()
from public,anon,authenticated,service_role;

drop trigger if exists zz_league_season_official_snapshot_writer
on public.season_completion_runs;
create trigger zz_league_season_official_snapshot_writer
after insert on public.season_completion_runs
for each row execute function public.publish_league_season_official_snapshot_from_completion_v1();
alter table public.season_completion_runs
  enable always trigger zz_league_season_official_snapshot_writer;

create or replace function public.reconcile_league_season_official_snapshot_from_provider_v1()
returns trigger
language plpgsql
security definer
set search_path=''
as $function$
begin
  perform public.reconcile_league_season_official_snapshot_v1(new.league_id,false);
  return new;
end;
$function$;
revoke all on function public.reconcile_league_season_official_snapshot_from_provider_v1()
from public,anon,authenticated,service_role;

drop trigger if exists league_season_official_snapshot_provider_writer
on public.provider_season_completion_gate_heads;
create trigger league_season_official_snapshot_provider_writer
after insert or update of gate_status,current_completion_run_id,
  final_progression_run_id,gate_generation,gate_fingerprint
on public.provider_season_completion_gate_heads
for each row execute function public.reconcile_league_season_official_snapshot_from_provider_v1();
alter table public.provider_season_completion_gate_heads
  enable always trigger league_season_official_snapshot_provider_writer;

create or replace function public.protect_official_league_season_summary_v1()
returns trigger
language plpgsql
security definer
set search_path=''
as $function$
begin
  if exists (
    select 1
    from public.league_season_official_snapshots snapshot_row
    where snapshot_row.league_id=old.league_id
  ) then
    raise exception
      'Riepilogo ufficiale congelato: usa lo snapshot storico immutabile.';
  end if;
  if tg_op='DELETE' then return old; end if;
  return new;
end;
$function$;
revoke all on function public.protect_official_league_season_summary_v1()
from public,anon,authenticated,service_role;

drop trigger if exists protect_official_league_season_summary
on public.league_season_summaries;
create trigger protect_official_league_season_summary
before update or delete on public.league_season_summaries
for each row execute function public.protect_official_league_season_summary_v1();
alter table public.league_season_summaries
  enable always trigger protect_official_league_season_summary;

create or replace function public.protect_official_league_season_identity_v1()
returns trigger
language plpgsql
security definer
set search_path=''
as $function$
begin
  if exists (
    select 1
    from public.league_season_official_snapshots snapshot_row
    where snapshot_row.league_id=old.id
  ) then
    if new.champion_team_id is distinct from old.champion_team_id
      or new.competition_completed_at
        is distinct from old.competition_completed_at
      or (
        old.status in ('completed','archived')
        and new.status not in ('completed','archived')
      ) then
      raise exception
        'Identità della stagione ufficiale congelata: modifica non consentita.';
    end if;
  end if;
  return new;
end;
$function$;
revoke all on function public.protect_official_league_season_identity_v1()
from public,anon,authenticated,service_role;

drop trigger if exists protect_official_league_season_identity
on public.leagues;
create trigger protect_official_league_season_identity
before update of champion_team_id,competition_completed_at,status
on public.leagues
for each row execute function public.protect_official_league_season_identity_v1();
alter table public.leagues
  enable always trigger protect_official_league_season_identity;

-- Adozione non distruttiva delle chiusure già certificate dalla v0.62.27.
do $backfill$
declare
  v_row record;
begin
  for v_row in
    select completion.league_id,completion.id as completion_run_id
    from public.season_completion_runs completion
    order by completion.league_id
  loop
    perform public.publish_league_season_official_snapshot_v1(
      v_row.league_id,v_row.completion_run_id,true
    );
  end loop;
end;
$backfill$;

create or replace function public.complete_league_season_guarded_v3(
  p_league_id uuid,
  p_request_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_result jsonb;
  v_completion_id bigint;
  v_snapshot jsonb;
begin
  if auth.uid() is null then
    raise exception 'Devi effettuare l''accesso.';
  end if;

  v_result := public.complete_league_season_guarded_v2(
    p_league_id,p_request_id
  );

  select completion.id into v_completion_id
  from public.season_completion_runs completion
  where completion.league_id=p_league_id;

  if not found then
    raise exception
      'La chiusura non ha prodotto il commit certificato della stagione.';
  end if;

  v_snapshot := public.publish_league_season_official_snapshot_v1(
    p_league_id,v_completion_id,false
  );

  return v_result || jsonb_build_object(
    'officialSnapshot',v_snapshot,
    'officialSnapshotId',nullif(v_snapshot->>'snapshotId','')::bigint,
    'officialSnapshotHash',v_snapshot->>'snapshotHash',
    'officialSnapshotStatus',v_snapshot->>'snapshotStatus',
    'officialSnapshotAffected',
      coalesce((v_snapshot->>'snapshotAffected')::boolean,false)
  );
end;
$function$;
revoke all on function public.complete_league_season_guarded_v3(uuid,uuid)
from public,anon,service_role;
grant execute on function public.complete_league_season_guarded_v3(uuid,uuid)
to authenticated;

create or replace function public.get_league_season_official_snapshot_v1(
  p_league_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $function$
declare
  v_snapshot public.league_season_official_snapshots%rowtype;
  v_head public.league_season_official_snapshot_heads%rowtype;
  v_champion_standing jsonb := '{}'::jsonb;
  v_latest jsonb;
begin
  if auth.uid() is null then
    raise exception 'Devi effettuare l''accesso.';
  end if;
  if not public.is_league_member(p_league_id)
    and not public.is_league_admin(p_league_id) then
    raise exception 'Non fai parte di questa lega.';
  end if;

  select snapshot_row.*
  into v_snapshot
  from public.league_season_official_snapshots snapshot_row
  where snapshot_row.league_id=p_league_id;

  if not found then
    return jsonb_build_object(
      'protected',true,
      'published',false,
      'healthy',true,
      'status','pending',
      'reasonCode','season_snapshot.not_published'
    );
  end if;

  select head.*
  into v_head
  from public.league_season_official_snapshot_heads head
  where head.snapshot_id=v_snapshot.id;

  if not found then
    raise exception 'Testa dello snapshot ufficiale non trovata.';
  end if;

  select entry.value
  into v_champion_standing
  from jsonb_array_elements(v_snapshot.final_standings) entry(value)
  where entry.value->>'teamId'=v_snapshot.champion_team_id::text
  limit 1;

  select jsonb_build_object(
    'id',event_row.id,
    'eventType',event_row.event_type,
    'status',event_row.snapshot_status,
    'reasonCode',event_row.reason_code,
    'completionGateGeneration',event_row.completion_gate_generation,
    'createdAt',event_row.created_at
  ) into v_latest
  from public.league_season_official_snapshot_events event_row
  where event_row.snapshot_id=v_snapshot.id
  order by event_row.created_at desc,event_row.id desc
  limit 1;

  return jsonb_build_object(
    'protected',true,
    'published',true,
    'healthy',v_head.snapshot_status='official',
    'status',v_head.snapshot_status,
    'reasonCode',v_head.reason_code,
    'affected',v_head.snapshot_status='affected',
    'snapshotId',v_snapshot.id,
    'snapshotHash',v_snapshot.snapshot_hash,
    'standingsHash',v_snapshot.standings_hash,
    'completionRunId',v_snapshot.completion_run_id,
    'completionGateGeneration',v_snapshot.completion_gate_generation,
    'completionGateFingerprint',v_snapshot.completion_gate_fingerprint,
    'season',v_snapshot.season,
    'champion',jsonb_build_object(
      'teamId',v_snapshot.champion_team_id,
      'teamName',v_snapshot.champion_team_name,
      'managerName',v_snapshot.champion_manager_name,
      'source',v_snapshot.champion_source,
      'leaguePoints',coalesce(
        (v_champion_standing->>'leaguePoints')::numeric,0
      ),
      'pointsFor',coalesce(
        (v_champion_standing->>'pointsFor')::numeric,0
      )
    ),
    'podium',v_snapshot.podium,
    'finalStandings',v_snapshot.final_standings,
    'standingsTiebreaker',v_snapshot.standings_tiebreaker,
    'officializedAt',v_snapshot.officialized_at,
    'affectedAt',v_head.affected_at,
    'latestEvent',v_latest
  );
end;
$function$;
revoke all on function public.get_league_season_official_snapshot_v1(uuid)
from public,anon,service_role;
grant execute on function public.get_league_season_official_snapshot_v1(uuid)
to authenticated;

create or replace function public.get_league_season_state_v6(
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
  v_snapshot jsonb;
begin
  v_state := public.get_league_season_state_v5(p_league_id);
  v_snapshot := public.get_league_season_official_snapshot_v1(p_league_id);

  return v_state || jsonb_build_object(
    'officialSnapshotProtected',true,
    'officialSnapshotPublished',
      coalesce((v_snapshot->>'published')::boolean,false),
    'officialSnapshotHealthy',
      coalesce((v_snapshot->>'healthy')::boolean,true),
    'officialSnapshotStatus',v_snapshot->>'status',
    'officialSnapshotReason',v_snapshot->>'reasonCode',
    'officialSnapshotAffected',
      coalesce((v_snapshot->>'affected')::boolean,false),
    'officialSnapshotId',nullif(v_snapshot->>'snapshotId','')::bigint,
    'officialSnapshotHash',v_snapshot->>'snapshotHash',
    'officialPodium',coalesce(v_snapshot->'podium','[]'::jsonb),
    'officialSnapshot',v_snapshot,
    'finalStandings',case
      when coalesce((v_snapshot->>'published')::boolean,false)
        then v_snapshot->'finalStandings'
      else v_state->'finalStandings'
    end,
    'champion',case
      when coalesce((v_snapshot->>'published')::boolean,false)
        then v_snapshot->'champion'
      else v_state->'champion'
    end
  );
end;
$function$;
revoke all on function public.get_league_season_state_v6(uuid)
from public,anon,service_role;
grant execute on function public.get_league_season_state_v6(uuid)
to authenticated;

create or replace function public.get_league_management_state_v16(
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
  v_state := public.get_league_management_state_v15(p_league_id);
  v_season := public.get_league_season_state_v6(p_league_id);
  v_checks := coalesce(v_state->'checks','{}'::jsonb);

  return v_state || v_season || jsonb_build_object(
    'checks',v_checks || jsonb_build_object(
      'seasonOfficialSnapshotProtected',true,
      'seasonOfficialSnapshotPublished',
        coalesce((v_season->>'officialSnapshotPublished')::boolean,false),
      'seasonOfficialSnapshotHealthy',
        coalesce((v_season->>'officialSnapshotHealthy')::boolean,true)
    )
  );
end;
$function$;
revoke all on function public.get_league_management_state_v16(uuid)
from public,anon,service_role;
grant execute on function public.get_league_management_state_v16(uuid)
to authenticated;

create or replace function public.get_league_provider_sync_health_v27(
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
  v_snapshot jsonb;
  v_healthy boolean;
  v_status text;
begin
  v_base := public.get_league_provider_sync_health_v26(p_league_id);
  v_snapshot := public.get_league_season_official_snapshot_v1(p_league_id);
  v_healthy := coalesce((v_base->>'healthy')::boolean,false)
    and coalesce((v_snapshot->>'healthy')::boolean,true);
  v_status := case
    when not v_healthy then 'attention'
    else coalesce(v_base->>'status','idle')
  end;

  return v_base || jsonb_build_object(
    'protected',coalesce((v_base->>'protected')::boolean,false)
      and coalesce((v_snapshot->>'protected')::boolean,false),
    'healthy',v_healthy,
    'status',v_status,
    'seasonOfficialSnapshot',v_snapshot
  );
end;
$function$;
revoke all on function public.get_league_provider_sync_health_v27(uuid)
from public,anon,service_role;
grant execute on function public.get_league_provider_sync_health_v27(uuid)
to authenticated;

-- Solo lo storico append-only viene pubblicato in Realtime.
do $realtime$
begin
  if exists (
    select 1 from pg_catalog.pg_publication publication
    where publication.pubname='supabase_realtime'
  ) and not exists (
    select 1 from pg_catalog.pg_publication_tables publication_table
    where publication_table.pubname='supabase_realtime'
      and publication_table.schemaname='public'
      and publication_table.tablename=
        'league_season_official_snapshot_events'
  ) then
    alter publication supabase_realtime
      add table public.league_season_official_snapshot_events;
  end if;
end;
$realtime$;

create or replace function public.get_league_season_official_snapshot_integrity_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $function$
declare
  v_publish text := '';
  v_reconcile text := '';
  v_guarded_v3 text := '';
  v_state_v6 text := '';
  v_management_v16 text := '';
  v_health_v27 text := '';
begin
  select lower(pg_catalog.pg_get_functiondef(
    'public.publish_league_season_official_snapshot_v1(uuid,bigint,boolean)'::regprocedure
  )) into v_publish;
  select lower(pg_catalog.pg_get_functiondef(
    'public.reconcile_league_season_official_snapshot_v1(uuid,boolean)'::regprocedure
  )) into v_reconcile;
  select lower(pg_catalog.pg_get_functiondef(
    'public.complete_league_season_guarded_v3(uuid,uuid)'::regprocedure
  )) into v_guarded_v3;
  select lower(pg_catalog.pg_get_functiondef(
    'public.get_league_season_state_v6(uuid)'::regprocedure
  )) into v_state_v6;
  select lower(pg_catalog.pg_get_functiondef(
    'public.get_league_management_state_v16(uuid)'::regprocedure
  )) into v_management_v16;
  select lower(pg_catalog.pg_get_functiondef(
    'public.get_league_provider_sync_health_v27(uuid)'::regprocedure
  )) into v_health_v27;

  return jsonb_build_object(
    'predecessor_ready',
      to_regprocedure(
        'public.get_provider_season_completion_gate_integrity_v1()'
      ) is not null
      and (select count(*) from jsonb_each(
        public.get_provider_season_completion_gate_integrity_v1()
      ))=20
      and not exists (
        select 1 from jsonb_each(
          public.get_provider_season_completion_gate_integrity_v1()
        ) check_row
        where jsonb_typeof(check_row.value) is distinct from 'boolean'
           or check_row.value is distinct from 'true'::jsonb
      ),
    'snapshot_table_ready',
      to_regclass('public.league_season_official_snapshots') is not null,
    'head_table_ready',
      to_regclass('public.league_season_official_snapshot_heads') is not null,
    'event_table_ready',
      to_regclass('public.league_season_official_snapshot_events') is not null,
    'columns_ready',
      not exists (
        select 1
        from (values
          ('league_season_official_snapshots','completion_run_id'),
          ('league_season_official_snapshots','completion_gate_generation'),
          ('league_season_official_snapshots','final_standings'),
          ('league_season_official_snapshots','podium'),
          ('league_season_official_snapshots','snapshot_hash'),
          ('league_season_official_snapshot_heads','snapshot_status'),
          ('league_season_official_snapshot_heads','affected_at'),
          ('league_season_official_snapshot_events','event_type'),
          ('league_season_official_snapshot_events','event_payload')
        ) required(table_name,column_name)
        where not exists (
          select 1 from information_schema.columns column_row
          where column_row.table_schema='public'
            and column_row.table_name=required.table_name
            and column_row.column_name=required.column_name
        )
      ),
    'constraints_ready',
      (select count(*) from pg_catalog.pg_constraint constraint_row
       where constraint_row.conrelid=
         'public.league_season_official_snapshots'::regclass
         and constraint_row.contype in ('p','u','f','c'))>=15
      and (select count(*) from pg_catalog.pg_constraint constraint_row
       where constraint_row.conrelid=
         'public.league_season_official_snapshot_heads'::regclass
         and constraint_row.contype in ('p','u','f','c'))>=7
      and (select count(*) from pg_catalog.pg_constraint constraint_row
       where constraint_row.conrelid=
         'public.league_season_official_snapshot_events'::regclass
         and constraint_row.contype in ('p','f','c'))>=9,
    'indexes_ready',
      to_regclass(
        'public.league_season_official_snapshots_created_idx'
      ) is not null
      and to_regclass(
        'public.league_season_official_snapshot_heads_status_idx'
      ) is not null
      and to_regclass(
        'public.league_season_official_snapshot_events_league_idx'
      ) is not null,
    'rls_ready',
      (select relrowsecurity from pg_catalog.pg_class
       where oid='public.league_season_official_snapshots'::regclass)
      and (select relrowsecurity from pg_catalog.pg_class
       where oid='public.league_season_official_snapshot_heads'::regclass)
      and (select relrowsecurity from pg_catalog.pg_class
       where oid='public.league_season_official_snapshot_events'::regclass)
      and exists (
        select 1 from pg_catalog.pg_policy policy_row
        where policy_row.polrelid=
          'public.league_season_official_snapshots'::regclass
          and policy_row.polname=
            'league_season_official_snapshots_member_select'
      )
      and exists (
        select 1 from pg_catalog.pg_policy policy_row
        where policy_row.polrelid=
          'public.league_season_official_snapshot_heads'::regclass
          and policy_row.polname=
            'league_season_official_snapshot_heads_member_select'
      ),
    'direct_write_blocked',
      not has_table_privilege('authenticated',
        'public.league_season_official_snapshots','INSERT')
      and not has_table_privilege('authenticated',
        'public.league_season_official_snapshot_heads','UPDATE')
      and not has_table_privilege('authenticated',
        'public.league_season_official_snapshot_events','INSERT')
      and not has_table_privilege('service_role',
        'public.league_season_official_snapshots','INSERT')
      and not has_table_privilege('service_role',
        'public.league_season_official_snapshot_heads','UPDATE')
      and not has_table_privilege('service_role',
        'public.league_season_official_snapshot_events','INSERT'),
    'immutable_snapshot_ready',
      exists (
        select 1 from pg_catalog.pg_trigger trigger_row
        where trigger_row.tgrelid=
          'public.league_season_official_snapshots'::regclass
          and trigger_row.tgname=
            'league_season_official_snapshots_immutable'
          and trigger_row.tgenabled='A'
          and not trigger_row.tgisinternal
      ),
    'immutable_events_ready',
      exists (
        select 1 from pg_catalog.pg_trigger trigger_row
        where trigger_row.tgrelid=
          'public.league_season_official_snapshot_events'::regclass
          and trigger_row.tgname=
            'league_season_official_snapshot_events_immutable'
          and trigger_row.tgenabled='A'
          and not trigger_row.tgisinternal
      ),
    'head_guard_ready',
      exists (
        select 1 from pg_catalog.pg_trigger trigger_row
        where trigger_row.tgrelid=
          'public.league_season_official_snapshot_heads'::regclass
          and trigger_row.tgname=
            'league_season_official_snapshot_heads_guard'
          and trigger_row.tgenabled='A'
          and not trigger_row.tgisinternal
      )
      and exists (
        select 1 from pg_catalog.pg_trigger trigger_row
        where trigger_row.tgrelid='public.league_season_summaries'::regclass
          and trigger_row.tgname='protect_official_league_season_summary'
          and trigger_row.tgenabled='A'
          and not trigger_row.tgisinternal
      )
      and exists (
        select 1 from pg_catalog.pg_trigger trigger_row
        where trigger_row.tgrelid='public.leagues'::regclass
          and trigger_row.tgname='protect_official_league_season_identity'
          and trigger_row.tgenabled='A'
          and not trigger_row.tgisinternal
      ),
    'publish_rpc_ready',
      to_regprocedure(
        'public.publish_league_season_official_snapshot_v1(uuid,bigint,boolean)'
      ) is not null
      and has_function_privilege('service_role',
        'public.publish_league_season_official_snapshot_v1(uuid,bigint,boolean)',
        'EXECUTE')
      and position('league-season-official-snapshot:' in v_publish)>0
      and position('snapshot rifiutato' in v_publish)>0,
    'reconcile_rpc_ready',
      to_regprocedure(
        'public.reconcile_league_season_official_snapshot_v1(uuid,boolean)'
      ) is not null
      and has_function_privilege('service_role',
        'public.reconcile_league_season_official_snapshot_v1(uuid,boolean)',
        'EXECUTE')
      and position('provider_generation_changed' in v_reconcile)>0
      and position('revalidated_but_still_affected' in v_reconcile)>0,
    'completion_writer_ready',
      exists (
        select 1 from pg_catalog.pg_trigger trigger_row
        where trigger_row.tgrelid='public.season_completion_runs'::regclass
          and trigger_row.tgname='zz_league_season_official_snapshot_writer'
          and trigger_row.tgenabled='A'
          and not trigger_row.tgisinternal
      ),
    'provider_reconcile_trigger_ready',
      exists (
        select 1 from pg_catalog.pg_trigger trigger_row
        where trigger_row.tgrelid=
          'public.provider_season_completion_gate_heads'::regclass
          and trigger_row.tgname=
            'league_season_official_snapshot_provider_writer'
          and trigger_row.tgenabled='A'
          and not trigger_row.tgisinternal
      ),
    'guarded_v3_ready',
      to_regprocedure(
        'public.complete_league_season_guarded_v3(uuid,uuid)'
      ) is not null
      and has_function_privilege('authenticated',
        'public.complete_league_season_guarded_v3(uuid,uuid)','EXECUTE')
      and position('complete_league_season_guarded_v2' in v_guarded_v3)>0
      and position('officialsnapshothash' in replace(v_guarded_v3,'_',''))>0,
    'season_state_v6_ready',
      to_regprocedure('public.get_league_season_state_v6(uuid)') is not null
      and has_function_privilege('authenticated',
        'public.get_league_season_state_v6(uuid)','EXECUTE')
      and position('officialsnapshotpublished' in
        replace(v_state_v6,'_',''))>0
      and to_regprocedure('public.get_league_management_state_v16(uuid)')
        is not null
      and has_function_privilege('authenticated',
        'public.get_league_management_state_v16(uuid)','EXECUTE')
      and position('seasonofficialsnapshotprotected' in
        replace(v_management_v16,'_',''))>0
      and to_regprocedure(
        'public.get_league_provider_sync_health_v27(uuid)'
      ) is not null
      and has_function_privilege('authenticated',
        'public.get_league_provider_sync_health_v27(uuid)','EXECUTE')
      and position('seasonofficialsnapshot' in
        replace(v_health_v27,'_',''))>0,
    'backfill_integrity_ready',
      not exists (
        select 1
        from public.season_completion_runs completion
        where not exists (
          select 1
          from public.league_season_official_snapshots snapshot_row
          where snapshot_row.completion_run_id=completion.id
            and snapshot_row.league_id=completion.league_id
            and snapshot_row.standings_hash=completion.standings_hash
            and snapshot_row.final_standings=completion.final_standings
        )
      )
      and not exists (
        select 1
        from public.league_season_official_snapshots snapshot_row
        left join public.league_season_official_snapshot_heads head
          on head.snapshot_id=snapshot_row.id
        where head.snapshot_id is null
          or snapshot_row.snapshot_hash
            <>pg_catalog.md5(jsonb_build_object(
              'leagueId',snapshot_row.league_id,
              'completionRunId',snapshot_row.completion_run_id,
              'completionGateHeadId',snapshot_row.completion_gate_head_id,
              'completionGateGeneration',snapshot_row.completion_gate_generation,
              'completionGateFingerprint',snapshot_row.completion_gate_fingerprint,
              'finalProgressionRunId',snapshot_row.final_progression_run_id,
              'finalOfficializationRunId',snapshot_row.final_officialization_run_id,
              'season',snapshot_row.season,
              'championTeamId',snapshot_row.champion_team_id,
              'championTeamName',snapshot_row.champion_team_name,
              'championManagerName',snapshot_row.champion_manager_name,
              'championSource',snapshot_row.champion_source,
              'standingsTiebreaker',snapshot_row.standings_tiebreaker,
              'fixtureCount',snapshot_row.fixture_count,
              'completionInputHash',snapshot_row.completion_input_hash,
              'standingsHash',snapshot_row.standings_hash,
              'finalStandings',snapshot_row.final_standings,
              'podium',snapshot_row.podium,
              'officializedAt',snapshot_row.officialized_at
            )::text)
      ),
    'realtime_events_ready',
      exists (
        select 1 from pg_catalog.pg_publication_tables publication_table
        where publication_table.pubname='supabase_realtime'
          and publication_table.schemaname='public'
          and publication_table.tablename=
            'league_season_official_snapshot_events'
      )
      and not exists (
        select 1 from pg_catalog.pg_publication_tables publication_table
        where publication_table.pubname='supabase_realtime'
          and publication_table.schemaname='public'
          and publication_table.tablename in (
            'league_season_official_snapshots',
            'league_season_official_snapshot_heads'
          )
      )
  );
end;
$function$;
revoke all on function public.get_league_season_official_snapshot_integrity_v1()
from public,anon,authenticated,service_role;
grant execute on function public.get_league_season_official_snapshot_integrity_v1()
to service_role;

-- Validazione transazionale: esattamente 20 controlli booleani true.
do $validation$
declare
  v_checks jsonb;
  v_false text;
  v_count integer;
begin
  v_checks := public.get_league_season_official_snapshot_integrity_v1();
  select count(*) into v_count from jsonb_each(v_checks);
  select string_agg(check_row.key,', ' order by check_row.key)
  into v_false
  from jsonb_each(v_checks) check_row
  where jsonb_typeof(check_row.value) is distinct from 'boolean'
     or check_row.value is distinct from 'true'::jsonb;

  if v_count<>20 then
    raise exception
      'Validazione v0.62.28 non superata. Numero controlli atteso 20, rilevato %.',
      v_count;
  end if;
  if v_false is not null then
    raise exception
      'Validazione v0.62.28 non superata. Controlli falsi: %',
      v_false;
  end if;
end;
$validation$;

commit;

-- Diagnostica finale: devono comparire esattamente 20 valori true.
select
  (checks->>'predecessor_ready')::boolean as predecessor_ready,
  (checks->>'snapshot_table_ready')::boolean as snapshot_table_ready,
  (checks->>'head_table_ready')::boolean as head_table_ready,
  (checks->>'event_table_ready')::boolean as event_table_ready,
  (checks->>'columns_ready')::boolean as columns_ready,
  (checks->>'constraints_ready')::boolean as constraints_ready,
  (checks->>'indexes_ready')::boolean as indexes_ready,
  (checks->>'rls_ready')::boolean as rls_ready,
  (checks->>'direct_write_blocked')::boolean as direct_write_blocked,
  (checks->>'immutable_snapshot_ready')::boolean as immutable_snapshot_ready,
  (checks->>'immutable_events_ready')::boolean as immutable_events_ready,
  (checks->>'head_guard_ready')::boolean as head_guard_ready,
  (checks->>'publish_rpc_ready')::boolean as publish_rpc_ready,
  (checks->>'reconcile_rpc_ready')::boolean as reconcile_rpc_ready,
  (checks->>'completion_writer_ready')::boolean as completion_writer_ready,
  (checks->>'provider_reconcile_trigger_ready')::boolean as provider_reconcile_trigger_ready,
  (checks->>'guarded_v3_ready')::boolean as guarded_v3_ready,
  (checks->>'season_state_v6_ready')::boolean as season_state_v6_ready,
  (checks->>'backfill_integrity_ready')::boolean as backfill_integrity_ready,
  (checks->>'realtime_events_ready')::boolean as realtime_events_ready
from (
  select public.get_league_season_official_snapshot_integrity_v1() as checks
) integrity;
