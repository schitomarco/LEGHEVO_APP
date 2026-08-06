-- LEGHEVO v0.62.21
-- Gate certificato di consumo dei voti provider.
-- Eseguire dopo database/124_provider_fixture_score_causal_coherence_safety.sql.
-- I valori provider non vengono cancellati o alterati: soltanto le fotografie
-- correnti e causalmente allineate possono entrare in sostituzioni, proiezioni
-- e ufficializzazione dei risultati.

begin;

-- PRE-FLIGHT: verifica esplicita di tutte le dipendenze realmente utilizzate.
do $preflight$
declare
  v_missing text[] := array[]::text[];
  v_checks jsonb;
begin
  if to_regprocedure('public.get_provider_fixture_score_coherence_integrity_v1()') is null then
    v_missing := array_append(v_missing,'function public.get_provider_fixture_score_coherence_integrity_v1()');
  else
    v_checks := public.get_provider_fixture_score_coherence_integrity_v1();
    if (select count(*) from jsonb_each(v_checks)) <> 20
      or exists(
        select 1 from jsonb_each(v_checks) check_row
        where jsonb_typeof(check_row.value) is distinct from 'boolean'
           or check_row.value is distinct from 'true'::jsonb
      ) then
      v_missing := array_append(v_missing,'v0.62.20 integrity: all 20 checks must be true');
    end if;
  end if;

  if to_regclass('public.player_match_scores') is null then
    v_missing := array_append(v_missing,'table public.player_match_scores');
  end if;
  if to_regclass('public.athletes') is null then
    v_missing := array_append(v_missing,'table public.athletes');
  end if;
  if to_regclass('public.provider_fixture_score_heads') is null then
    v_missing := array_append(v_missing,'table public.provider_fixture_score_heads');
  end if;
  if to_regclass('public.provider_fixtures') is null then
    v_missing := array_append(v_missing,'table public.provider_fixtures');
  end if;
  if to_regclass('public.fantasy_fixtures') is null then
    v_missing := array_append(v_missing,'table public.fantasy_fixtures');
  end if;
  if to_regclass('public.matchdays') is null then
    v_missing := array_append(v_missing,'table public.matchdays');
  end if;
  if to_regclass('public.league_fixture_resolutions') is null then
    v_missing := array_append(v_missing,'table public.league_fixture_resolutions');
  end if;
  if to_regclass('public.leagues') is null then
    v_missing := array_append(v_missing,'table public.leagues');
  end if;
  if to_regclass('public.provider_sync_runs') is null then
    v_missing := array_append(v_missing,'table public.provider_sync_runs');
  end if;

  if exists (
    select 1
    from (values
      ('player_match_scores','id'),
      ('player_match_scores','athlete_id'),
      ('player_match_scores','matchday_id'),
      ('player_match_scores','provider_fixture_id'),
      ('player_match_scores','provider_rating'),
      ('player_match_scores','fantasy_score'),
      ('player_match_scores','bonuses'),
      ('player_match_scores','maluses'),
      ('player_match_scores','raw_statistics'),
      ('player_match_scores','is_final'),
      ('player_match_scores','provider_score_state'),
      ('player_match_scores','provider_score_reconciliation_id'),
      ('player_match_scores','updated_at'),
      ('athletes','id'),
      ('athletes','provider'),
      ('athletes','provider_team_id'),
      ('athletes','club_name'),
      ('provider_fixture_score_heads','id'),
      ('provider_fixture_score_heads','provider'),
      ('provider_fixture_score_heads','provider_fixture_id'),
      ('provider_fixture_score_heads','matchday_id'),
      ('provider_fixture_score_heads','is_final'),
      ('provider_fixture_score_heads','latest_reconciliation_id'),
      ('provider_fixture_score_heads','generation'),
      ('provider_fixture_score_heads','fixture_lifecycle_causal_generation'),
      ('provider_fixture_score_heads','coherence_status'),
      ('provider_fixture_score_heads','coherence_reason_code'),
      ('provider_fixtures','id'),
      ('provider_fixtures','provider'),
      ('provider_fixtures','provider_fixture_id'),
      ('provider_fixtures','matchday_id'),
      ('provider_fixtures','status'),
      ('provider_fixtures','home_team_provider_id'),
      ('provider_fixtures','away_team_provider_id'),
      ('provider_fixtures','home_team_name'),
      ('provider_fixtures','away_team_name'),
      ('fantasy_fixtures','id'),
      ('fantasy_fixtures','league_id'),
      ('fantasy_fixtures','matchday_id'),
      ('fantasy_fixtures','finalized_at'),
      ('matchdays','id'),
      ('matchdays','starts_at'),
      ('matchdays','ends_at'),
      ('league_fixture_resolutions','id'),
      ('league_fixture_resolutions','league_id'),
      ('league_fixture_resolutions','provider_fixture_id'),
      ('league_fixture_resolutions','political_score'),
      ('league_fixture_resolutions','revoked_at'),
      ('league_fixture_resolutions','decided_at'),
      ('leagues','id'),
      ('leagues','owner_id'),
      ('provider_sync_runs','status')
    ) required(table_name,column_name)
    where not exists (
      select 1 from information_schema.columns column_row
      where column_row.table_schema='public'
        and column_row.table_name=required.table_name
        and column_row.column_name=required.column_name
    )
  ) then
    v_missing := array_append(v_missing,'required columns for provider score consumption gate');
  end if;

  if to_regprocedure('public.league_matchday_is_resolved(uuid,uuid)') is null then
    v_missing := array_append(v_missing,'RPC public.league_matchday_is_resolved(uuid,uuid)');
  end if;
  if to_regprocedure('public.get_league_effective_player_score(uuid,uuid,uuid)') is null then
    v_missing := array_append(v_missing,'RPC public.get_league_effective_player_score(uuid,uuid,uuid)');
  end if;
  if to_regprocedure('public.refresh_matchday_results_internal(uuid)') is null then
    v_missing := array_append(v_missing,'function public.refresh_matchday_results_internal(uuid)');
  end if;
  if to_regprocedure('public.get_league_provider_sync_health_v19(uuid)') is null then
    v_missing := array_append(v_missing,'RPC public.get_league_provider_sync_health_v19(uuid)');
  end if;
  if to_regprocedure('public.is_league_admin(uuid)') is null then
    v_missing := array_append(v_missing,'function public.is_league_admin(uuid)');
  end if;
  if to_regprocedure('public.normalize_provider_club_name(text)') is null then
    v_missing := array_append(v_missing,'function public.normalize_provider_club_name(text)');
  end if;

  if exists(select 1 from public.provider_sync_runs run_row where run_row.status='running') then
    v_missing := array_append(v_missing,'no provider sync run may be running during installation');
  end if;

  if coalesce(array_length(v_missing,1),0)>0 then
    raise exception 'Preflight v0.62.21 non superato. Dipendenze mancanti: %',array_to_string(v_missing,'; ');
  end if;
end;
$preflight$;

-- Vista server-side: conserva tutti i valori ma certifica se possono essere
-- consumati dal motore sportivo.
create or replace view public.provider_match_score_consumption_v1 as
select
  classified.*,
  classified.consumption_status in ('legacy_trusted','trusted') as is_consumable,
  classified.consumption_status in (
    'missing_provider','missing_head','missing_reconciliation',
    'superseded','stale','missing_coherence'
  ) and classified.provider_rating is not null as is_blocking
from (
  select
    score_row.*,
    athlete_row.provider as athlete_provider,
    score_head.id as score_head_id,
    score_head.latest_reconciliation_id as head_latest_reconciliation_id,
    score_head.generation as score_head_generation,
    score_head.fixture_lifecycle_causal_generation,
    score_head.coherence_status,
    score_head.coherence_reason_code,
    case
      when score_row.provider_fixture_id is null
        and score_row.provider_score_state='current' then 'legacy_trusted'
      when score_row.provider_score_state='retired' then 'retired'
      when score_row.provider_fixture_id is not null
        and athlete_row.provider is null then 'missing_provider'
      when score_row.provider_fixture_id is not null
        and score_head.id is null then 'missing_head'
      when score_row.provider_fixture_id is not null
        and score_row.provider_score_reconciliation_id is null then 'missing_reconciliation'
      when score_row.provider_fixture_id is not null
        and score_row.provider_score_reconciliation_id is distinct from score_head.latest_reconciliation_id then 'superseded'
      when score_row.provider_fixture_id is not null
        and score_head.coherence_status='aligned' then 'trusted'
      when score_row.provider_fixture_id is not null
        and score_head.coherence_status='stale' then 'stale'
      else 'missing_coherence'
    end as consumption_status,
    case
      when score_row.provider_fixture_id is null then 'consumption.legacy_trusted'
      when score_row.provider_score_state='retired' then 'consumption.retired'
      when athlete_row.provider is null then 'consumption.provider_missing'
      when score_head.id is null then 'consumption.head_missing'
      when score_row.provider_score_reconciliation_id is null then 'consumption.reconciliation_missing'
      when score_row.provider_score_reconciliation_id is distinct from score_head.latest_reconciliation_id then 'consumption.reconciliation_superseded'
      when score_head.coherence_status='aligned' then 'consumption.aligned'
      when score_head.coherence_status='stale' then coalesce(score_head.coherence_reason_code,'coherence.lifecycle_advanced')
      else coalesce(score_head.coherence_reason_code,'coherence.lifecycle_missing')
    end as consumption_reason_code
  from public.player_match_scores score_row
  join public.athletes athlete_row on athlete_row.id=score_row.athlete_id
  left join public.provider_fixture_score_heads score_head
    on score_head.provider=athlete_row.provider
   and score_head.provider_fixture_id=score_row.provider_fixture_id
) classified;

revoke all on table public.provider_match_score_consumption_v1 from public,anon,authenticated,service_role;
grant select on table public.provider_match_score_consumption_v1 to service_role;

create index if not exists player_match_scores_provider_consumption_lookup_idx
  on public.player_match_scores(matchday_id,provider_fixture_id,provider_score_state,provider_score_reconciliation_id);
create index if not exists provider_fixture_score_heads_consumption_lookup_idx
  on public.provider_fixture_score_heads(provider,provider_fixture_id,coherence_status,latest_reconciliation_id);

create table if not exists public.provider_score_consumption_gate_events (
  id uuid primary key default gen_random_uuid(),
  score_head_id uuid not null references public.provider_fixture_score_heads(id) on delete restrict,
  matchday_id uuid not null references public.matchdays(id) on delete restrict,
  provider text not null,
  provider_fixture_fingerprint text not null,
  gate_status text not null,
  reason_code text not null,
  score_generation bigint not null,
  fixture_lifecycle_causal_generation bigint,
  event_fingerprint text not null unique,
  created_at timestamptz not null default now(),
  constraint provider_score_consumption_gate_events_status_check
    check(gate_status in ('trusted','blocked')),
  constraint provider_score_consumption_gate_events_generation_check
    check(score_generation>0 and (fixture_lifecycle_causal_generation is null or fixture_lifecycle_causal_generation>0)),
  constraint provider_score_consumption_gate_events_fixture_check
    check(provider_fixture_fingerprint ~ '^[0-9a-f]{32}$'),
  constraint provider_score_consumption_gate_events_event_check
    check(event_fingerprint ~ '^[0-9a-f]{32}$'),
  constraint provider_score_consumption_gate_events_provider_check
    check(length(trim(provider)) between 1 and 100 and provider !~ E'[\r\n]'),
  constraint provider_score_consumption_gate_events_reason_check
    check(length(trim(reason_code)) between 1 and 120 and reason_code !~ E'[\r\n]')
);

create index if not exists provider_score_consumption_gate_events_matchday_idx
  on public.provider_score_consumption_gate_events(matchday_id,created_at desc);
create index if not exists provider_score_consumption_gate_events_status_idx
  on public.provider_score_consumption_gate_events(gate_status,created_at desc);

alter table public.provider_score_consumption_gate_events enable row level security;
alter table public.provider_score_consumption_gate_events replica identity full;
revoke all on table public.provider_score_consumption_gate_events from public,anon,authenticated,service_role;
grant select on table public.provider_score_consumption_gate_events to authenticated;
grant select,insert on table public.provider_score_consumption_gate_events to service_role;

drop policy if exists provider_score_consumption_gate_events_director_select
on public.provider_score_consumption_gate_events;
create policy provider_score_consumption_gate_events_director_select
on public.provider_score_consumption_gate_events
for select to authenticated
using (
  exists(
    select 1
    from public.fantasy_fixtures fantasy_fixture
    join public.leagues league_row on league_row.id=fantasy_fixture.league_id
    where fantasy_fixture.matchday_id=provider_score_consumption_gate_events.matchday_id
      and (league_row.owner_id=auth.uid() or public.is_league_admin(league_row.id))
  )
);

create or replace function public.prevent_provider_score_consumption_gate_event_mutation_v1()
returns trigger
language plpgsql
security definer
set search_path=''
as $function$
begin
  raise exception 'Storico gate consumo voti provider immutabile [consumption.event_immutable].';
end;
$function$;
revoke all on function public.prevent_provider_score_consumption_gate_event_mutation_v1() from public,anon,authenticated,service_role;

drop trigger if exists provider_score_consumption_gate_events_immutable on public.provider_score_consumption_gate_events;
create trigger provider_score_consumption_gate_events_immutable
before update or delete on public.provider_score_consumption_gate_events
for each row execute function public.prevent_provider_score_consumption_gate_event_mutation_v1();
alter table public.provider_score_consumption_gate_events
  enable always trigger provider_score_consumption_gate_events_immutable;

create or replace function public.get_provider_score_consumption_state_v1(p_score_id uuid)
returns jsonb
language sql
stable
security definer
set search_path=''
as $function$
  select jsonb_build_object(
    'scoreId',consumption.id,
    'consumable',consumption.is_consumable,
    'blocking',consumption.is_blocking,
    'status',consumption.consumption_status,
    'reasonCode',consumption.consumption_reason_code,
    'scoreHeadId',consumption.score_head_id,
    'scoreHeadGeneration',consumption.score_head_generation,
    'fixtureLifecycleGeneration',consumption.fixture_lifecycle_causal_generation
  )
  from public.provider_match_score_consumption_v1 consumption
  where consumption.id=p_score_id
$function$;
revoke all on function public.get_provider_score_consumption_state_v1(uuid) from public,anon,authenticated;
grant execute on function public.get_provider_score_consumption_state_v1(uuid) to service_role;

-- Il giorno reale è risolto solo se ogni partita finale possiede una fotografia
-- voti corrente e causalmente allineata. Le risoluzioni politiche continuano a
-- coprire esclusivamente rinvii/sospensioni non finali.
create or replace function public.league_matchday_is_resolved(
  p_league_id uuid,
  p_matchday_id uuid
)
returns boolean
language plpgsql
stable
security definer
set search_path=''
as $function$
declare
  v_provider_count integer:=0;
  v_fallback_complete boolean:=false;
begin
  select
    count(provider_fixture.id)::integer,
    now()>=coalesce(matchday.ends_at,matchday.starts_at+interval '4 days')
  into v_provider_count,v_fallback_complete
  from public.matchdays matchday
  left join public.provider_fixtures provider_fixture
    on provider_fixture.matchday_id=matchday.id
  where matchday.id=p_matchday_id
  group by matchday.ends_at,matchday.starts_at;

  if v_provider_count=0 then
    return coalesce(v_fallback_complete,false);
  end if;

  if exists(
    select 1
    from public.provider_fixtures provider_fixture
    where provider_fixture.matchday_id=p_matchday_id
      and provider_fixture.status not in ('FT','AET','PEN')
      and not exists(
        select 1 from public.league_fixture_resolutions resolution
        where resolution.league_id=p_league_id
          and resolution.provider_fixture_id=provider_fixture.id
          and resolution.revoked_at is null
      )
  ) then
    return false;
  end if;

  if exists(
    select 1
    from public.provider_fixtures provider_fixture
    left join public.provider_fixture_score_heads score_head
      on score_head.provider=provider_fixture.provider
     and score_head.provider_fixture_id=provider_fixture.provider_fixture_id
    where provider_fixture.matchday_id=p_matchday_id
      and provider_fixture.status in ('FT','AET','PEN')
      and (
        score_head.id is null
        or not score_head.is_final
        or score_head.coherence_status<>'aligned'
        or score_head.latest_reconciliation_id is null
      )
  ) then
    return false;
  end if;

  return true;
end;
$function$;
revoke all on function public.league_matchday_is_resolved(uuid,uuid) from public,anon,authenticated;

-- Un voto non affidabile resta consultabile nello storico, ma la RPC restituisce
-- un esito bloccato senza rating: il motore non può conteggiarlo né usarlo per
-- scegliere una sostituzione.
create or replace function public.get_league_effective_player_score(
  p_league_id uuid,
  p_athlete_id uuid,
  p_matchday_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $function$
declare
  v_athlete public.athletes%rowtype;
  v_resolution record;
  v_score record;
begin
  select athlete.* into v_athlete
  from public.athletes athlete where athlete.id=p_athlete_id;
  if not found then return null; end if;

  select resolution.id,resolution.political_score,provider_fixture.provider_fixture_id
  into v_resolution
  from public.league_fixture_resolutions resolution
  join public.provider_fixtures provider_fixture on provider_fixture.id=resolution.provider_fixture_id
  where resolution.league_id=p_league_id
    and resolution.revoked_at is null
    and provider_fixture.matchday_id=p_matchday_id
    and provider_fixture.status not in ('FT','AET','PEN')
    and (
      (nullif(v_athlete.provider_team_id,'') is not null and v_athlete.provider_team_id in (
        provider_fixture.home_team_provider_id,provider_fixture.away_team_provider_id
      ))
      or public.normalize_provider_club_name(v_athlete.club_name) in (
        public.normalize_provider_club_name(provider_fixture.home_team_name),
        public.normalize_provider_club_name(provider_fixture.away_team_name)
      )
    )
  order by resolution.decided_at desc limit 1;

  if found then
    return jsonb_build_object(
      'providerRating',v_resolution.political_score,
      'fantasyScore',v_resolution.political_score,
      'bonuses','{}'::jsonb,'maluses','{}'::jsonb,
      'rawStatistics',jsonb_build_object(
        'leghevoPoliticalScore',true,'resolutionId',v_resolution.id,
        'providerFixtureId',v_resolution.provider_fixture_id
      ),
      'isFinal',true,'scoreOrigin','political',
      'scoreTrusted',true,'providerTrustStatus','political',
      'providerTrustReason','consumption.political_resolution'
    );
  end if;

  select consumption.* into v_score
  from public.provider_match_score_consumption_v1 consumption
  where consumption.athlete_id=p_athlete_id
    and consumption.matchday_id=p_matchday_id;

  if not found then return null; end if;

  if v_score.is_consumable and v_score.provider_rating is not null then
    return jsonb_build_object(
      'providerRating',v_score.provider_rating,
      'fantasyScore',v_score.fantasy_score,
      'bonuses',coalesce(v_score.bonuses,'{}'::jsonb),
      'maluses',coalesce(v_score.maluses,'{}'::jsonb),
      'rawStatistics',coalesce(v_score.raw_statistics,'{}'::jsonb),
      'isFinal',v_score.is_final,'scoreOrigin','provider',
      'scoreTrusted',true,'providerTrustStatus',v_score.consumption_status,
      'providerTrustReason',v_score.consumption_reason_code
    );
  end if;

  if v_score.is_blocking then
    return jsonb_build_object(
      'providerRating',null,'fantasyScore',null,
      'bonuses','{}'::jsonb,'maluses','{}'::jsonb,'rawStatistics','{}'::jsonb,
      'isFinal',false,'scoreOrigin','provider_blocked',
      'scoreBlocked',true,'scoreTrusted',false,
      'providerTrustStatus',v_score.consumption_status,
      'providerTrustReason',v_score.consumption_reason_code
    );
  end if;

  return null;
end;
$function$;
revoke all on function public.get_league_effective_player_score(uuid,uuid,uuid) from public,anon,authenticated;

create or replace function public.write_provider_score_consumption_gate_event_v1()
returns trigger
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_gate_status text;
  v_event_fingerprint text;
begin
  if tg_op='UPDATE'
    and new.generation is not distinct from old.generation
    and new.latest_reconciliation_id is not distinct from old.latest_reconciliation_id
    and new.coherence_status is not distinct from old.coherence_status
    and new.coherence_reason_code is not distinct from old.coherence_reason_code
    and new.is_final is not distinct from old.is_final then
    return new;
  end if;

  v_gate_status:=case when new.coherence_status='aligned' and new.latest_reconciliation_id is not null
    then 'trusted' else 'blocked' end;
  v_event_fingerprint:=pg_catalog.md5(
    new.id::text||E'\n'||new.generation::text||E'\n'||
    coalesce(new.latest_reconciliation_id::text,'')||E'\n'||v_gate_status||E'\n'||
    coalesce(new.coherence_reason_code,'')||E'\n'||
    coalesce(new.fixture_lifecycle_causal_generation::text,'')
  );

  insert into public.provider_score_consumption_gate_events(
    score_head_id,matchday_id,provider,provider_fixture_fingerprint,
    gate_status,reason_code,score_generation,fixture_lifecycle_causal_generation,
    event_fingerprint
  ) values(
    new.id,new.matchday_id,new.provider,
    pg_catalog.md5(new.provider||E'\n'||new.provider_fixture_id),
    v_gate_status,
    case when v_gate_status='trusted' then 'consumption.aligned'
      else coalesce(new.coherence_reason_code,'coherence.lifecycle_missing') end,
    new.generation,new.fixture_lifecycle_causal_generation,v_event_fingerprint
  ) on conflict(event_fingerprint) do nothing;

  perform public.refresh_matchday_results_internal(new.matchday_id);
  return new;
end;
$function$;
revoke all on function public.write_provider_score_consumption_gate_event_v1() from public,anon,authenticated;

drop trigger if exists provider_score_consumption_gate_event_writer on public.provider_fixture_score_heads;
create trigger provider_score_consumption_gate_event_writer
after insert or update of generation,latest_reconciliation_id,coherence_status,coherence_reason_code,is_final
on public.provider_fixture_score_heads
for each row execute function public.write_provider_score_consumption_gate_event_v1();
alter table public.provider_fixture_score_heads
  enable always trigger provider_score_consumption_gate_event_writer;

-- Certificati iniziali senza alterare voti o storico.
insert into public.provider_score_consumption_gate_events(
  score_head_id,matchday_id,provider,provider_fixture_fingerprint,
  gate_status,reason_code,score_generation,fixture_lifecycle_causal_generation,
  event_fingerprint,created_at
)
select
  score_head.id,score_head.matchday_id,score_head.provider,
  pg_catalog.md5(score_head.provider||E'\n'||score_head.provider_fixture_id),
  case when score_head.coherence_status='aligned' and score_head.latest_reconciliation_id is not null
    then 'trusted' else 'blocked' end,
  case when score_head.coherence_status='aligned' and score_head.latest_reconciliation_id is not null
    then 'consumption.aligned' else coalesce(score_head.coherence_reason_code,'coherence.lifecycle_missing') end,
  score_head.generation,score_head.fixture_lifecycle_causal_generation,
  pg_catalog.md5(
    score_head.id::text||E'\n'||score_head.generation::text||E'\n'||
    coalesce(score_head.latest_reconciliation_id::text,'')||E'\n'||
    case when score_head.coherence_status='aligned' and score_head.latest_reconciliation_id is not null
      then 'trusted' else 'blocked' end||E'\n'||
    coalesce(score_head.coherence_reason_code,'')||E'\n'||
    coalesce(score_head.fixture_lifecycle_causal_generation::text,'')
  ),now()
from public.provider_fixture_score_heads score_head
on conflict(event_fingerprint) do nothing;

-- Allinea immediatamente le proiezioni non ufficializzate dei giorni che
-- contengono una fotografia bloccata.
do $refresh_existing$
declare
  v_matchday_id uuid;
begin
  for v_matchday_id in
    select distinct score_head.matchday_id
    from public.provider_fixture_score_heads score_head
    where score_head.coherence_status<>'aligned'
       or score_head.latest_reconciliation_id is null
  loop
    perform public.refresh_matchday_results_internal(v_matchday_id);
  end loop;
end;
$refresh_existing$;

create or replace function public.get_league_provider_score_consumption_gate_v1(p_league_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $function$
declare
  v_owner_id uuid;
  v_trusted_heads integer:=0;
  v_blocked_heads integer:=0;
  v_stale_heads integer:=0;
  v_missing_heads integer:=0;
  v_blocked_scores integer:=0;
  v_blocked_matchdays integer:=0;
  v_official_risk integer:=0;
  v_events_24h integer:=0;
  v_latest_event jsonb;
begin
  if auth.uid() is null then raise exception 'Devi effettuare l''accesso.'; end if;
  select league_row.owner_id into v_owner_id from public.leagues league_row where league_row.id=p_league_id;
  if not found then raise exception 'Lega non trovata per il gate consumo voti provider.'; end if;
  if v_owner_id<>auth.uid() and not public.is_league_admin(p_league_id) then
    raise exception 'Solo Presidente e Admin possono leggere il gate consumo voti provider.';
  end if;

  select
    count(distinct score_head.id) filter(
      where score_head.coherence_status='aligned'
        and score_head.latest_reconciliation_id is not null
    )::integer,
    count(distinct score_head.id) filter(
      where score_head.coherence_status='stale'
    )::integer
  into v_trusted_heads,v_stale_heads
  from public.provider_fixture_score_heads score_head
  where exists(
    select 1 from public.fantasy_fixtures fantasy_fixture
    where fantasy_fixture.league_id=p_league_id
      and fantasy_fixture.matchday_id=score_head.matchday_id
  );

  select count(distinct provider_fixture.id)::integer
  into v_missing_heads
  from public.provider_fixtures provider_fixture
  left join public.provider_fixture_score_heads score_head
    on score_head.provider=provider_fixture.provider
   and score_head.provider_fixture_id=provider_fixture.provider_fixture_id
  where provider_fixture.status in ('FT','AET','PEN')
    and exists(
      select 1 from public.fantasy_fixtures fantasy_fixture
      where fantasy_fixture.league_id=p_league_id
        and fantasy_fixture.matchday_id=provider_fixture.matchday_id
    )
    and (
      score_head.id is null
      or score_head.coherence_status='missing'
      or score_head.latest_reconciliation_id is null
    );

  v_blocked_heads:=v_stale_heads+v_missing_heads;

  select count(*)::integer into v_blocked_scores
  from public.provider_match_score_consumption_v1 consumption
  where consumption.is_blocking
    and exists(
      select 1 from public.fantasy_fixtures fantasy_fixture
      where fantasy_fixture.league_id=p_league_id
        and fantasy_fixture.matchday_id=consumption.matchday_id
    );

  select count(distinct provider_fixture.matchday_id)::integer
  into v_blocked_matchdays
  from public.provider_fixtures provider_fixture
  left join public.provider_fixture_score_heads score_head
    on score_head.provider=provider_fixture.provider
   and score_head.provider_fixture_id=provider_fixture.provider_fixture_id
  where provider_fixture.status in ('FT','AET','PEN')
    and exists(
      select 1 from public.fantasy_fixtures fantasy_fixture
      where fantasy_fixture.league_id=p_league_id
        and fantasy_fixture.matchday_id=provider_fixture.matchday_id
    )
    and (
      score_head.id is null
      or score_head.coherence_status<>'aligned'
      or score_head.latest_reconciliation_id is null
    );

  select count(distinct fantasy_fixture.id)::integer into v_official_risk
  from public.fantasy_fixtures fantasy_fixture
  where fantasy_fixture.league_id=p_league_id
    and fantasy_fixture.finalized_at is not null
    and exists(
      select 1
      from public.provider_fixtures provider_fixture
      left join public.provider_fixture_score_heads score_head
        on score_head.provider=provider_fixture.provider
       and score_head.provider_fixture_id=provider_fixture.provider_fixture_id
      where provider_fixture.matchday_id=fantasy_fixture.matchday_id
        and provider_fixture.status in ('FT','AET','PEN')
        and (
          score_head.id is null
          or score_head.coherence_status<>'aligned'
          or score_head.latest_reconciliation_id is null
        )
    );

  select count(*)::integer into v_events_24h
  from public.provider_score_consumption_gate_events event_row
  where event_row.created_at>=now()-interval '24 hours'
    and exists(
      select 1 from public.fantasy_fixtures fantasy_fixture
      where fantasy_fixture.league_id=p_league_id
        and fantasy_fixture.matchday_id=event_row.matchday_id
    );

  select jsonb_build_object(
    'id',event_row.id,'fixtureIdFingerprint',event_row.provider_fixture_fingerprint,
    'gateStatus',event_row.gate_status,'reasonCode',event_row.reason_code,
    'scoreGeneration',event_row.score_generation,
    'fixtureLifecycleGeneration',event_row.fixture_lifecycle_causal_generation,
    'createdAt',event_row.created_at
  ) into v_latest_event
  from public.provider_score_consumption_gate_events event_row
  where exists(
    select 1 from public.fantasy_fixtures fantasy_fixture
    where fantasy_fixture.league_id=p_league_id
      and fantasy_fixture.matchday_id=event_row.matchday_id
  )
  order by event_row.created_at desc limit 1;

  return jsonb_build_object(
    'protected',true,
    'healthy',v_blocked_heads=0 and v_official_risk=0,
    'officialResultConsumptionGateActive',true,
    'staleScoresExcludedFromCalculations',true,
    'blockedScoresCannotTriggerSubstitutions',true,
    'scoreValuesPreservedWhileBlocked',true,
    'trustedHeadCount',v_trusted_heads,
    'blockedHeadCount',v_blocked_heads,
    'staleHeadCount',v_stale_heads,
    'missingHeadCount',v_missing_heads,
    'blockedScoreCount',v_blocked_scores,
    'blockedMatchdayCount',v_blocked_matchdays,
    'officialFixtureRiskCount',v_official_risk,
    'eventsLast24h',v_events_24h,
    'latestEvent',v_latest_event
  );
end;
$function$;
revoke all on function public.get_league_provider_score_consumption_gate_v1(uuid) from public,anon,service_role;
grant execute on function public.get_league_provider_score_consumption_gate_v1(uuid) to authenticated;

create or replace function public.get_league_provider_sync_health_v20(p_league_id uuid)
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
  v_base:=public.get_league_provider_sync_health_v19(p_league_id);
  v_gate:=public.get_league_provider_score_consumption_gate_v1(p_league_id);
  v_healthy:=coalesce((v_base->>'healthy')::boolean,false)
    and coalesce((v_gate->>'healthy')::boolean,false);
  v_status:=case when not v_healthy then 'attention' else coalesce(v_base->>'status','idle') end;
  return v_base||jsonb_build_object(
    'protected',coalesce((v_base->>'protected')::boolean,false) and coalesce((v_gate->>'protected')::boolean,false),
    'healthy',v_healthy,'status',v_status,'scoreConsumptionGate',v_gate
  );
end;
$function$;
revoke all on function public.get_league_provider_sync_health_v20(uuid) from public,anon,service_role;
grant execute on function public.get_league_provider_sync_health_v20(uuid) to authenticated;

create or replace function public.get_provider_score_consumption_gate_integrity_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $function$
declare
  v_predecessor jsonb;
  v_matchday_definition text;
  v_effective_definition text;
  v_event_writer_definition text;
  v_center_definition text;
  v_health_definition text;
begin
  v_predecessor:=public.get_provider_fixture_score_coherence_integrity_v1();
  v_matchday_definition:=lower(pg_catalog.pg_get_functiondef('public.league_matchday_is_resolved(uuid,uuid)'::regprocedure));
  v_effective_definition:=lower(pg_catalog.pg_get_functiondef('public.get_league_effective_player_score(uuid,uuid,uuid)'::regprocedure));
  v_event_writer_definition:=lower(pg_catalog.pg_get_functiondef('public.write_provider_score_consumption_gate_event_v1()'::regprocedure));
  v_center_definition:=lower(pg_catalog.pg_get_functiondef('public.get_league_provider_score_consumption_gate_v1(uuid)'::regprocedure));
  v_health_definition:=lower(pg_catalog.pg_get_functiondef('public.get_league_provider_sync_health_v20(uuid)'::regprocedure));

  return jsonb_build_object(
    'predecessor_ready',
      (select count(*) from jsonb_each(v_predecessor))=20
      and not exists(select 1 from jsonb_each(v_predecessor) c where c.value is distinct from 'true'::jsonb),
    'consumption_view_ready',to_regclass('public.provider_match_score_consumption_v1') is not null,
    'event_table_ready',to_regclass('public.provider_score_consumption_gate_events') is not null,
    'constraints_ready',
      (select count(*)>=6 from pg_catalog.pg_constraint where conrelid='public.provider_score_consumption_gate_events'::regclass),
    'indexes_ready',to_regclass('public.player_match_scores_provider_consumption_lookup_idx') is not null
      and to_regclass('public.provider_fixture_score_heads_consumption_lookup_idx') is not null
      and to_regclass('public.provider_score_consumption_gate_events_matchday_idx') is not null,
    'rls_ready',(select relrowsecurity from pg_catalog.pg_class where oid='public.provider_score_consumption_gate_events'::regclass)
      and exists(select 1 from pg_catalog.pg_policy where polrelid='public.provider_score_consumption_gate_events'::regclass and polname='provider_score_consumption_gate_events_director_select'),
    'authenticated_write_blocked',not has_table_privilege('authenticated','public.provider_score_consumption_gate_events','INSERT')
      and not has_table_privilege('authenticated','public.provider_score_consumption_gate_events','UPDATE')
      and not has_table_privilege('authenticated','public.provider_score_consumption_gate_events','DELETE'),
    'service_role_event_ready',has_table_privilege('service_role','public.provider_score_consumption_gate_events','SELECT')
      and has_table_privilege('service_role','public.provider_score_consumption_gate_events','INSERT'),
    'immutable_history_ready',exists(
      select 1 from pg_catalog.pg_trigger trigger_row
      where trigger_row.tgrelid='public.provider_score_consumption_gate_events'::regclass
        and trigger_row.tgname='provider_score_consumption_gate_events_immutable'
        and trigger_row.tgenabled='A' and not trigger_row.tgisinternal
    ),
    'consumption_state_rpc_ready',to_regprocedure('public.get_provider_score_consumption_state_v1(uuid)') is not null,
    'matchday_gate_ready',position('provider_fixture_score_heads' in v_matchday_definition)>0
      and position('coherence_status' in v_matchday_definition)>0
      and position('latest_reconciliation_id' in v_matchday_definition)>0,
    'effective_score_gate_ready',position('provider_match_score_consumption_v1' in v_effective_definition)>0
      and position('provider_blocked' in v_effective_definition)>0
      and position('scoreblocked' in replace(v_effective_definition,'_',''))>0,
    'head_event_writer_ready',exists(
      select 1 from pg_catalog.pg_trigger trigger_row
      where trigger_row.tgrelid='public.provider_fixture_score_heads'::regclass
        and trigger_row.tgname='provider_score_consumption_gate_event_writer'
        and trigger_row.tgenabled='A' and not trigger_row.tgisinternal
    ),
    'result_refresh_ready',position('refresh_matchday_results_internal' in v_event_writer_definition)>0,
    'current_score_filter_ready',position('provider_score_state' in lower(pg_catalog.pg_get_viewdef('public.provider_match_score_consumption_v1'::regclass,true)))>0
      and position('latest_reconciliation_id' in lower(pg_catalog.pg_get_viewdef('public.provider_match_score_consumption_v1'::regclass,true)))>0,
    'blocked_score_preservation_ready',position('provider_rating' in lower(pg_catalog.pg_get_viewdef('public.provider_match_score_consumption_v1'::regclass,true)))>0
      and position('is_blocking' in lower(pg_catalog.pg_get_viewdef('public.provider_match_score_consumption_v1'::regclass,true)))>0,
    'official_risk_center_ready',position('officialfixtureriskcount' in replace(v_center_definition,'_',''))>0
      and position('finalized_at' in v_center_definition)>0,
    'health_v20_ready',to_regprocedure('public.get_league_provider_sync_health_v20(uuid)') is not null
      and position('scoreconsumptiongate' in replace(v_health_definition,'_',''))>0,
    'realtime_events_only_ready',exists(
      select 1 from pg_catalog.pg_publication_tables publication_row
      where publication_row.pubname='supabase_realtime'
        and publication_row.schemaname='public'
        and publication_row.tablename='provider_score_consumption_gate_events'
    ) or not exists(
      select 1 from pg_catalog.pg_publication_tables publication_row
      where publication_row.pubname='supabase_realtime'
        and publication_row.schemaname='public'
        and publication_row.tablename in ('provider_fixture_score_heads','player_match_scores')
    ),
    'rpc_grants_ready',has_function_privilege('authenticated','public.get_league_provider_score_consumption_gate_v1(uuid)','EXECUTE')
      and has_function_privilege('authenticated','public.get_league_provider_sync_health_v20(uuid)','EXECUTE')
      and not has_function_privilege('authenticated','public.get_provider_score_consumption_state_v1(uuid)','EXECUTE')
  );
end;
$function$;
revoke all on function public.get_provider_score_consumption_gate_integrity_v1() from public,anon,authenticated;
grant execute on function public.get_provider_score_consumption_gate_integrity_v1() to service_role;

-- Pubblica esclusivamente lo storico sintetico; mai la vista di consumo o le teste interne.
do $realtime$
begin
  if exists(select 1 from pg_catalog.pg_publication where pubname='supabase_realtime') then
    if not exists(
      select 1 from pg_catalog.pg_publication_tables
      where pubname='supabase_realtime' and schemaname='public'
        and tablename='provider_score_consumption_gate_events'
    ) then
      execute 'alter publication supabase_realtime add table public.provider_score_consumption_gate_events';
    end if;
  end if;
end;
$realtime$;

-- Validazione transazionale: se un controllo fallisce, tutta la migrazione viene annullata.
do $validation$
declare
  v_checks jsonb;
  v_failed text;
begin
  v_checks:=public.get_provider_score_consumption_gate_integrity_v1();
  select string_agg(check_row.key,', ' order by check_row.key) into v_failed
  from jsonb_each(v_checks) check_row
  where jsonb_typeof(check_row.value) is distinct from 'boolean'
     or check_row.value is distinct from 'true'::jsonb;
  if (select count(*) from jsonb_each(v_checks))<>20 or v_failed is not null then
    raise exception 'Validazione v0.62.21 non superata. Controlli falsi: %',coalesce(v_failed,'numero_controlli_non_valido');
  end if;
end;
$validation$;

commit;

-- DIAGNOSTICA FINALE: devono comparire esattamente 20 valori true.
select
  (checks->>'predecessor_ready')::boolean as predecessor_ready,
  (checks->>'consumption_view_ready')::boolean as consumption_view_ready,
  (checks->>'event_table_ready')::boolean as event_table_ready,
  (checks->>'constraints_ready')::boolean as constraints_ready,
  (checks->>'indexes_ready')::boolean as indexes_ready,
  (checks->>'rls_ready')::boolean as rls_ready,
  (checks->>'authenticated_write_blocked')::boolean as authenticated_write_blocked,
  (checks->>'service_role_event_ready')::boolean as service_role_event_ready,
  (checks->>'immutable_history_ready')::boolean as immutable_history_ready,
  (checks->>'consumption_state_rpc_ready')::boolean as consumption_state_rpc_ready,
  (checks->>'matchday_gate_ready')::boolean as matchday_gate_ready,
  (checks->>'effective_score_gate_ready')::boolean as effective_score_gate_ready,
  (checks->>'head_event_writer_ready')::boolean as head_event_writer_ready,
  (checks->>'result_refresh_ready')::boolean as result_refresh_ready,
  (checks->>'current_score_filter_ready')::boolean as current_score_filter_ready,
  (checks->>'blocked_score_preservation_ready')::boolean as blocked_score_preservation_ready,
  (checks->>'official_risk_center_ready')::boolean as official_risk_center_ready,
  (checks->>'health_v20_ready')::boolean as health_v20_ready,
  (checks->>'realtime_events_only_ready')::boolean as realtime_events_only_ready,
  (checks->>'rpc_grants_ready')::boolean as rpc_grants_ready
from (select public.get_provider_score_consumption_gate_integrity_v1() as checks) diagnostic;
