-- LEGHEVO v0.62.20
-- Coerenza causale certificata tra ciclo partita e fotografia voti provider.
-- Eseguire dopo database/123_provider_fixture_lifecycle_monotonic_safety.sql.
-- La migrazione non cancella né neutralizza voti: certifica se la fotografia
-- voti appartiene ancora alla generazione corrente della partita provider.

begin;

-- PRE-FLIGHT: nessuna tabella, colonna, funzione o firma RPC viene presunta.
do $preflight$
declare
  v_missing text[]:=array[]::text[];
  v_checks jsonb;
begin
  if to_regprocedure('public.get_provider_fixture_lifecycle_integrity_v1()') is null then
    v_missing:=array_append(v_missing,'function public.get_provider_fixture_lifecycle_integrity_v1()');
  else
    v_checks:=public.get_provider_fixture_lifecycle_integrity_v1();
    if (select count(*) from jsonb_each(v_checks))<>20
      or exists(
        select 1 from jsonb_each(v_checks) check_row
        where jsonb_typeof(check_row.value) is distinct from 'boolean'
          or check_row.value is distinct from 'true'::jsonb
      ) then
      v_missing:=array_append(v_missing,'v0.62.19 integrity: all 20 checks must be true');
    end if;
  end if;

  if to_regclass('public.provider_fixture_score_heads') is null then v_missing:=array_append(v_missing,'table public.provider_fixture_score_heads'); end if;
  if to_regclass('public.provider_fixture_score_reconciliations') is null then v_missing:=array_append(v_missing,'table public.provider_fixture_score_reconciliations'); end if;
  if to_regclass('public.provider_fixture_lifecycle_heads') is null then v_missing:=array_append(v_missing,'table public.provider_fixture_lifecycle_heads'); end if;
  if to_regclass('public.provider_fixture_lifecycle_reconciliations') is null then v_missing:=array_append(v_missing,'table public.provider_fixture_lifecycle_reconciliations'); end if;
  if to_regclass('public.provider_fixture_lifecycle_members') is null then v_missing:=array_append(v_missing,'table public.provider_fixture_lifecycle_members'); end if;
  if to_regclass('public.provider_fixtures') is null then v_missing:=array_append(v_missing,'table public.provider_fixtures'); end if;
  if to_regclass('public.provider_sync_runs') is null then v_missing:=array_append(v_missing,'table public.provider_sync_runs'); end if;
  if to_regclass('public.provider_sync_publications') is null then v_missing:=array_append(v_missing,'table public.provider_sync_publications'); end if;
  if to_regclass('public.fantasy_fixtures') is null then v_missing:=array_append(v_missing,'table public.fantasy_fixtures'); end if;
  if to_regclass('public.leagues') is null then v_missing:=array_append(v_missing,'table public.leagues'); end if;

  if exists(
    select 1 from (values
      ('provider_fixture_score_heads','id'),('provider_fixture_score_heads','provider'),
      ('provider_fixture_score_heads','provider_fixture_id'),('provider_fixture_score_heads','latest_run_id'),
      ('provider_fixture_score_heads','latest_reconciliation_id'),('provider_fixture_score_heads','generation'),
      ('provider_fixture_score_heads','updated_at'),
      ('provider_fixture_score_reconciliations','id'),('provider_fixture_score_reconciliations','provider'),
      ('provider_fixture_score_reconciliations','provider_fixture_id'),('provider_fixture_score_reconciliations','run_id'),
      ('provider_fixture_score_reconciliations','league_id'),('provider_fixture_score_reconciliations','status'),
      ('provider_fixture_score_reconciliations','updated_at'),
      ('provider_fixture_lifecycle_heads','id'),('provider_fixture_lifecycle_heads','provider'),
      ('provider_fixture_lifecycle_heads','provider_fixture_id'),('provider_fixture_lifecycle_heads','latest_run_id'),
      ('provider_fixture_lifecycle_heads','latest_reconciliation_id'),('provider_fixture_lifecycle_heads','generation'),
      ('provider_fixture_lifecycle_heads','last_transition'),
      ('provider_fixture_lifecycle_heads','current_state'),('provider_fixture_lifecycle_heads','current_status'),
      ('provider_fixture_lifecycle_heads','updated_at'),
      ('provider_fixture_lifecycle_reconciliations','id'),('provider_fixture_lifecycle_reconciliations','provider'),
      ('provider_fixture_lifecycle_members','reconciliation_id'),('provider_fixture_lifecycle_members','fixture_key_fingerprint'),
      ('provider_fixture_lifecycle_members','transition'),
      ('provider_fixtures','provider'),('provider_fixtures','provider_fixture_id'),('provider_fixtures','matchday_id'),
      ('provider_sync_runs','id'),('provider_sync_runs','provider'),('provider_sync_runs','sync_type'),('provider_sync_runs','requested_for'),
      ('provider_sync_runs','status'),('provider_sync_publications','id'),('provider_sync_publications','run_id'),
      ('fantasy_fixtures','league_id'),('fantasy_fixtures','matchday_id'),('leagues','id'),('leagues','owner_id')
    ) required(table_name,column_name)
    where not exists(
      select 1 from information_schema.columns column_row
      where column_row.table_schema='public'
        and column_row.table_name=required.table_name
        and column_row.column_name=required.column_name
    )
  ) then
    v_missing:=array_append(v_missing,'required columns for fixture-score causal coherence');
  end if;

  if to_regprocedure('public.finish_provider_sync_run_guarded_v9(uuid,text,integer,text,bigint,uuid)') is null then
    v_missing:=array_append(v_missing,'RPC public.finish_provider_sync_run_guarded_v9(uuid,text,integer,text,bigint,uuid)');
  end if;
  if to_regprocedure('public.finish_provider_sync_run_guarded_v8(uuid,text,integer,text,bigint,uuid)') is null then
    v_missing:=array_append(v_missing,'RPC public.finish_provider_sync_run_guarded_v8(uuid,text,integer,text,bigint,uuid)');
  end if;
  if to_regprocedure('public.finish_provider_sync_run_atomic_core_v1(uuid,text,integer,text,bigint,uuid)') is null then
    v_missing:=array_append(v_missing,'function public.finish_provider_sync_run_atomic_core_v1(uuid,text,integer,text,bigint,uuid)');
  end if;
  if to_regprocedure('public.provider_sync_scope_watermark_decision_v1(uuid,uuid)') is null then
    v_missing:=array_append(v_missing,'function public.provider_sync_scope_watermark_decision_v1(uuid,uuid)');
  end if;
  if to_regprocedure('public.discard_stale_provider_sync_publication_v1(uuid,integer,bigint,uuid,jsonb)') is null then
    v_missing:=array_append(v_missing,'function public.discard_stale_provider_sync_publication_v1(uuid,integer,bigint,uuid,jsonb)');
  end if;
  if to_regprocedure('public.certify_provider_sync_publication_scope_v1(uuid,uuid)') is null then
    v_missing:=array_append(v_missing,'function public.certify_provider_sync_publication_scope_v1(uuid,uuid)');
  end if;
  if to_regprocedure('public.provider_player_catalog_decision_v1(uuid,uuid)') is null then
    v_missing:=array_append(v_missing,'function public.provider_player_catalog_decision_v1(uuid,uuid)');
  end if;
  if to_regprocedure('public.discard_superseded_provider_player_catalog_v1(uuid,integer,bigint,uuid,jsonb)') is null then
    v_missing:=array_append(v_missing,'function public.discard_superseded_provider_player_catalog_v1(uuid,integer,bigint,uuid,jsonb)');
  end if;
  if to_regprocedure('public.prepare_provider_player_catalog_reconciliation_v1(uuid,uuid)') is null then
    v_missing:=array_append(v_missing,'function public.prepare_provider_player_catalog_reconciliation_v1(uuid,uuid)');
  end if;
  if to_regprocedure('public.advance_provider_sync_scope_watermark_v1(uuid,integer,uuid)') is null then
    v_missing:=array_append(v_missing,'function public.advance_provider_sync_scope_watermark_v1(uuid,integer,uuid)');
  end if;
  if to_regprocedure('public.get_provider_player_catalog_result_v1(uuid)') is null then
    v_missing:=array_append(v_missing,'function public.get_provider_player_catalog_result_v1(uuid)');
  end if;
  if to_regprocedure('public.prepare_provider_fixture_lifecycle_reconciliation_v1(uuid,uuid)') is null then
    v_missing:=array_append(v_missing,'function public.prepare_provider_fixture_lifecycle_reconciliation_v1(uuid,uuid)');
  end if;
  if to_regprocedure('public.get_league_provider_sync_health_v18(uuid)') is null then
    v_missing:=array_append(v_missing,'RPC public.get_league_provider_sync_health_v18(uuid)');
  end if;
  if to_regprocedure('public.provider_recovery_retry_policy_v1(text,integer,text)') is null then
    v_missing:=array_append(v_missing,'function public.provider_recovery_retry_policy_v1(text,integer,text)');
  end if;
  if to_regprocedure('public.is_league_admin(uuid)') is null then
    v_missing:=array_append(v_missing,'function public.is_league_admin(uuid)');
  end if;
  if to_regprocedure('public.prepare_provider_fixture_score_reconciliation_v1(uuid,uuid)') is null then
    v_missing:=array_append(v_missing,'RPC public.prepare_provider_fixture_score_reconciliation_v1(uuid,uuid)');
  end if;
  if to_regprocedure('public.get_provider_fixture_score_result_v1(uuid)') is null then
    v_missing:=array_append(v_missing,'RPC public.get_provider_fixture_score_result_v1(uuid)');
  end if;
  if to_regprocedure('public.get_provider_fixture_lifecycle_result_v1(uuid)') is null then
    v_missing:=array_append(v_missing,'RPC public.get_provider_fixture_lifecycle_result_v1(uuid)');
  end if;
  if to_regprocedure('auth.uid()') is null then
    v_missing:=array_append(v_missing,'function auth.uid()');
  end if;
  if to_regprocedure('gen_random_uuid()') is null then
    v_missing:=array_append(v_missing,'function gen_random_uuid()');
  end if;
  if to_regprocedure('pg_catalog.md5(text)') is null then
    v_missing:=array_append(v_missing,'function pg_catalog.md5(text)');
  end if;
  if to_regprocedure('pg_catalog.jsonb_each(jsonb)') is null then
    v_missing:=array_append(v_missing,'function pg_catalog.jsonb_each(jsonb)');
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
    raise exception 'Preflight v0.62.20 non superato. Dipendenze mancanti: %',array_to_string(v_missing,'; ');
  end if;
end;
$preflight$;

-- La generazione tecnica della partita avanza a ogni fotografia calendario,
-- anche quando il contenuto è soltanto "refreshed". La generazione causale
-- avanza invece esclusivamente per creazione, avanzamento o correzione finale.
alter table public.provider_fixture_lifecycle_heads
  add column if not exists causal_generation bigint not null default 1;

update public.provider_fixture_lifecycle_heads lifecycle_head
set causal_generation=greatest(1,coalesce((
  select count(*)::bigint
  from public.provider_fixture_lifecycle_members member_row
  join public.provider_fixture_lifecycle_reconciliations reconciliation_row
    on reconciliation_row.id=member_row.reconciliation_id
  where reconciliation_row.provider=lifecycle_head.provider
    and member_row.fixture_key_fingerprint=pg_catalog.md5(
      lifecycle_head.provider||E'\n'||lifecycle_head.provider_fixture_id
    )
    and member_row.transition<>'refreshed'
),0));

alter table public.provider_fixture_lifecycle_heads
  drop constraint if exists provider_fixture_lifecycle_heads_causal_generation_check;
alter table public.provider_fixture_lifecycle_heads
  add constraint provider_fixture_lifecycle_heads_causal_generation_check
  check (causal_generation>0);

create or replace function public.maintain_provider_fixture_lifecycle_causal_generation_v1()
returns trigger
language plpgsql
security definer
set search_path=''
as $function$
begin
  if tg_op='INSERT' then
    if new.generation<>1 then
      raise exception 'Coerenza partita/voti provider non valida [coherence.lifecycle_generation_initial].';
    end if;
    new.causal_generation:=1;
    return new;
  end if;

  if new.generation<old.generation or new.generation>old.generation+1 then
    raise exception 'Coerenza partita/voti provider non valida [coherence.lifecycle_generation_non_monotonic].';
  end if;

  if new.generation=old.generation+1 then
    new.causal_generation:=old.causal_generation+
      case when new.last_transition='refreshed' then 0 else 1 end;
  else
    new.causal_generation:=old.causal_generation;
  end if;
  return new;
end;
$function$;
revoke all on function public.maintain_provider_fixture_lifecycle_causal_generation_v1() from public,anon,authenticated;
drop trigger if exists provider_fixture_lifecycle_causal_generation_guard on public.provider_fixture_lifecycle_heads;
create trigger provider_fixture_lifecycle_causal_generation_guard
before insert or update on public.provider_fixture_lifecycle_heads
for each row execute function public.maintain_provider_fixture_lifecycle_causal_generation_v1();
alter table public.provider_fixture_lifecycle_heads
  enable always trigger provider_fixture_lifecycle_causal_generation_guard;

alter table public.provider_fixture_score_reconciliations
  add column if not exists fixture_lifecycle_head_id uuid,
  add column if not exists fixture_lifecycle_reconciliation_id uuid,
  add column if not exists fixture_lifecycle_generation bigint,
  add column if not exists fixture_lifecycle_causal_generation bigint,
  add column if not exists fixture_lifecycle_state text,
  add column if not exists fixture_lifecycle_status text;

alter table public.provider_fixture_score_heads
  add column if not exists fixture_lifecycle_head_id uuid,
  add column if not exists fixture_lifecycle_reconciliation_id uuid,
  add column if not exists fixture_lifecycle_generation bigint,
  add column if not exists fixture_lifecycle_causal_generation bigint,
  add column if not exists coherence_status text not null default 'missing',
  add column if not exists coherence_reason_code text not null default 'coherence.lifecycle_missing',
  add column if not exists coherence_checked_at timestamptz;

alter table public.provider_fixture_score_reconciliations
  drop constraint if exists provider_fixture_score_reconciliations_lifecycle_head_fk;
alter table public.provider_fixture_score_reconciliations
  add constraint provider_fixture_score_reconciliations_lifecycle_head_fk
  foreign key(fixture_lifecycle_head_id)
  references public.provider_fixture_lifecycle_heads(id) on delete restrict;

alter table public.provider_fixture_score_reconciliations
  drop constraint if exists provider_fixture_score_reconciliations_lifecycle_reconciliation_fk;
alter table public.provider_fixture_score_reconciliations
  add constraint provider_fixture_score_reconciliations_lifecycle_reconciliation_fk
  foreign key(fixture_lifecycle_reconciliation_id)
  references public.provider_fixture_lifecycle_reconciliations(id) on delete restrict;

alter table public.provider_fixture_score_heads
  drop constraint if exists provider_fixture_score_heads_lifecycle_head_fk;
alter table public.provider_fixture_score_heads
  add constraint provider_fixture_score_heads_lifecycle_head_fk
  foreign key(fixture_lifecycle_head_id)
  references public.provider_fixture_lifecycle_heads(id) on delete restrict;

alter table public.provider_fixture_score_heads
  drop constraint if exists provider_fixture_score_heads_lifecycle_reconciliation_fk;
alter table public.provider_fixture_score_heads
  add constraint provider_fixture_score_heads_lifecycle_reconciliation_fk
  foreign key(fixture_lifecycle_reconciliation_id)
  references public.provider_fixture_lifecycle_reconciliations(id) on delete restrict;

alter table public.provider_fixture_score_reconciliations
  drop constraint if exists provider_fixture_score_reconciliations_lifecycle_generation_check;
alter table public.provider_fixture_score_reconciliations
  add constraint provider_fixture_score_reconciliations_lifecycle_generation_check
  check (fixture_lifecycle_generation is null or fixture_lifecycle_generation>0);

alter table public.provider_fixture_score_reconciliations
  drop constraint if exists provider_fixture_score_reconciliations_lifecycle_causal_generation_check;
alter table public.provider_fixture_score_reconciliations
  add constraint provider_fixture_score_reconciliations_lifecycle_causal_generation_check
  check (fixture_lifecycle_causal_generation is null or fixture_lifecycle_causal_generation>0);

alter table public.provider_fixture_score_reconciliations
  drop constraint if exists provider_fixture_score_reconciliations_lifecycle_state_check;
alter table public.provider_fixture_score_reconciliations
  add constraint provider_fixture_score_reconciliations_lifecycle_state_check
  check (fixture_lifecycle_state is null or fixture_lifecycle_state in ('scheduled','live','interrupted','cancelled','final'));

alter table public.provider_fixture_score_heads
  drop constraint if exists provider_fixture_score_heads_lifecycle_generation_check;
alter table public.provider_fixture_score_heads
  add constraint provider_fixture_score_heads_lifecycle_generation_check
  check (fixture_lifecycle_generation is null or fixture_lifecycle_generation>0);

alter table public.provider_fixture_score_heads
  drop constraint if exists provider_fixture_score_heads_lifecycle_causal_generation_check;
alter table public.provider_fixture_score_heads
  add constraint provider_fixture_score_heads_lifecycle_causal_generation_check
  check (fixture_lifecycle_causal_generation is null or fixture_lifecycle_causal_generation>0);

alter table public.provider_fixture_score_heads
  drop constraint if exists provider_fixture_score_heads_coherence_status_check;
alter table public.provider_fixture_score_heads
  add constraint provider_fixture_score_heads_coherence_status_check
  check (coherence_status in ('aligned','stale','missing'));

alter table public.provider_fixture_score_heads
  drop constraint if exists provider_fixture_score_heads_coherence_reason_check;
alter table public.provider_fixture_score_heads
  add constraint provider_fixture_score_heads_coherence_reason_check
  check (coherence_reason_code in (
    'coherence.aligned','coherence.lifecycle_advanced','coherence.lifecycle_missing',
    'coherence.concurrent_lifecycle_change','coherence.backfill_uncertain'
  ));

create index if not exists provider_fixture_score_heads_coherence_idx
  on public.provider_fixture_score_heads(coherence_status,coherence_checked_at desc);
create index if not exists provider_fixture_score_reconciliations_lifecycle_idx
  on public.provider_fixture_score_reconciliations(provider,provider_fixture_id,fixture_lifecycle_generation desc);

create table if not exists public.provider_fixture_score_coherence_events (
  id uuid primary key default gen_random_uuid(),
  score_head_id uuid not null references public.provider_fixture_score_heads(id) on delete restrict,
  league_id uuid references public.leagues(id) on delete set null,
  source_run_id uuid references public.provider_sync_runs(id) on delete set null,
  provider text not null,
  provider_fixture_fingerprint text not null,
  event_type text not null,
  score_generation bigint not null,
  fixture_lifecycle_generation bigint,
  fixture_lifecycle_causal_generation bigint,
  coherence_status text not null,
  reason_code text not null,
  event_fingerprint text not null unique,
  created_at timestamptz not null default now(),
  constraint provider_fixture_score_coherence_events_type_check
    check (event_type in ('aligned','stale','missing')),
  constraint provider_fixture_score_coherence_events_status_check
    check (coherence_status in ('aligned','stale','missing')),
  constraint provider_fixture_score_coherence_events_generation_check
    check (score_generation>0
      and (fixture_lifecycle_generation is null or fixture_lifecycle_generation>0)
      and (fixture_lifecycle_causal_generation is null or fixture_lifecycle_causal_generation>0)),
  constraint provider_fixture_score_coherence_events_fixture_check
    check (provider_fixture_fingerprint ~ '^[0-9a-f]{32}$'),
  constraint provider_fixture_score_coherence_events_reason_check
    check (reason_code in (
      'coherence.aligned','coherence.lifecycle_advanced','coherence.lifecycle_missing',
      'coherence.concurrent_lifecycle_change','coherence.backfill_uncertain'
    )),
  constraint provider_fixture_score_coherence_events_fingerprint_check
    check (event_fingerprint ~ '^[0-9a-f]{32}$')
);

create index if not exists provider_fixture_score_coherence_events_latest_idx
  on public.provider_fixture_score_coherence_events(created_at desc);
create index if not exists provider_fixture_score_coherence_events_league_idx
  on public.provider_fixture_score_coherence_events(league_id,created_at desc);

alter table public.provider_fixture_score_coherence_events enable row level security;
alter table public.provider_fixture_score_coherence_events replica identity full;
revoke all on table public.provider_fixture_score_coherence_events from public,anon,authenticated,service_role;
grant select,insert on table public.provider_fixture_score_coherence_events to service_role;

-- Le riconciliazioni v0.62.18 già applicate sono terminali e immutabili.
-- Restano quindi inalterate: le relative teste verranno marcate in modo
-- conservativo come `stale / coherence.backfill_uncertain` fino alla prima
-- nuova fotografia voti che catturerà la generazione causale corrente.

create or replace function public.capture_provider_fixture_score_lifecycle_v1()
returns trigger
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_head public.provider_fixture_lifecycle_heads%rowtype;
begin
  if tg_op='UPDATE' then
    if new.fixture_lifecycle_head_id is distinct from old.fixture_lifecycle_head_id
      or new.fixture_lifecycle_reconciliation_id is distinct from old.fixture_lifecycle_reconciliation_id
      or new.fixture_lifecycle_generation is distinct from old.fixture_lifecycle_generation
      or new.fixture_lifecycle_causal_generation is distinct from old.fixture_lifecycle_causal_generation
      or new.fixture_lifecycle_state is distinct from old.fixture_lifecycle_state
      or new.fixture_lifecycle_status is distinct from old.fixture_lifecycle_status then
      raise exception 'Coerenza partita/voti provider non valida [coherence.capture_immutable].';
    end if;
    return new;
  end if;

  select head_row.* into v_head
  from public.provider_fixture_lifecycle_heads head_row
  where head_row.provider=new.provider
    and head_row.provider_fixture_id=new.provider_fixture_id
  for share;

  if not found then
    raise exception 'Coerenza partita/voti provider non valida [coherence.lifecycle_missing]: sincronizzare prima il calendario della partita.';
  end if;

  new.fixture_lifecycle_head_id:=v_head.id;
  new.fixture_lifecycle_reconciliation_id:=v_head.latest_reconciliation_id;
  new.fixture_lifecycle_generation:=v_head.generation;
  new.fixture_lifecycle_causal_generation:=v_head.causal_generation;
  new.fixture_lifecycle_state:=v_head.current_state;
  new.fixture_lifecycle_status:=v_head.current_status;
  return new;
end;
$function$;
revoke all on function public.capture_provider_fixture_score_lifecycle_v1() from public,anon,authenticated;
drop trigger if exists provider_fixture_score_reconciliation_lifecycle_capture on public.provider_fixture_score_reconciliations;
drop trigger if exists provider_fixture_score_reconciliation_lifecycle_capture_insert on public.provider_fixture_score_reconciliations;
drop trigger if exists provider_fixture_score_reconciliation_lifecycle_capture_update on public.provider_fixture_score_reconciliations;
create trigger provider_fixture_score_reconciliation_lifecycle_capture_insert
before insert on public.provider_fixture_score_reconciliations
for each row execute function public.capture_provider_fixture_score_lifecycle_v1();
create trigger provider_fixture_score_reconciliation_lifecycle_capture_update
before update of fixture_lifecycle_head_id,fixture_lifecycle_reconciliation_id,
  fixture_lifecycle_generation,fixture_lifecycle_causal_generation,fixture_lifecycle_state,fixture_lifecycle_status
on public.provider_fixture_score_reconciliations
for each row execute function public.capture_provider_fixture_score_lifecycle_v1();
alter table public.provider_fixture_score_reconciliations
  enable always trigger provider_fixture_score_reconciliation_lifecycle_capture_insert;
alter table public.provider_fixture_score_reconciliations
  enable always trigger provider_fixture_score_reconciliation_lifecycle_capture_update;

create or replace function public.bind_provider_fixture_score_head_lifecycle_v1()
returns trigger
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_score_reconciliation public.provider_fixture_score_reconciliations%rowtype;
  v_lifecycle_head public.provider_fixture_lifecycle_heads%rowtype;
begin
  if new.latest_reconciliation_id is not null then
    select reconciliation_row.* into v_score_reconciliation
    from public.provider_fixture_score_reconciliations reconciliation_row
    where reconciliation_row.id=new.latest_reconciliation_id;
  end if;

  select head_row.* into v_lifecycle_head
  from public.provider_fixture_lifecycle_heads head_row
  where head_row.provider=new.provider
    and head_row.provider_fixture_id=new.provider_fixture_id;

  if v_score_reconciliation.id is not null then
    new.fixture_lifecycle_head_id:=v_score_reconciliation.fixture_lifecycle_head_id;
    new.fixture_lifecycle_reconciliation_id:=v_score_reconciliation.fixture_lifecycle_reconciliation_id;
    new.fixture_lifecycle_generation:=v_score_reconciliation.fixture_lifecycle_generation;
    new.fixture_lifecycle_causal_generation:=v_score_reconciliation.fixture_lifecycle_causal_generation;
  elsif new.fixture_lifecycle_causal_generation is null and v_lifecycle_head.id is not null then
    new.fixture_lifecycle_head_id:=v_lifecycle_head.id;
    new.fixture_lifecycle_reconciliation_id:=v_lifecycle_head.latest_reconciliation_id;
    new.fixture_lifecycle_generation:=v_lifecycle_head.generation;
    new.fixture_lifecycle_causal_generation:=v_lifecycle_head.causal_generation;
  end if;

  if v_lifecycle_head.id is null then
    new.coherence_status:='missing';
    new.coherence_reason_code:='coherence.lifecycle_missing';
  elsif new.fixture_lifecycle_causal_generation is null then
    new.coherence_status:='stale';
    new.coherence_reason_code:='coherence.backfill_uncertain';
  elsif new.fixture_lifecycle_causal_generation=v_lifecycle_head.causal_generation
    and new.fixture_lifecycle_head_id=v_lifecycle_head.id then
    new.coherence_status:='aligned';
    new.coherence_reason_code:='coherence.aligned';
  elsif new.fixture_lifecycle_causal_generation<v_lifecycle_head.causal_generation then
    new.coherence_status:='stale';
    new.coherence_reason_code:='coherence.lifecycle_advanced';
  else
    new.coherence_status:='stale';
    new.coherence_reason_code:='coherence.concurrent_lifecycle_change';
  end if;

  new.coherence_checked_at:=now();
  return new;
end;
$function$;
revoke all on function public.bind_provider_fixture_score_head_lifecycle_v1() from public,anon,authenticated;
drop trigger if exists provider_fixture_score_head_lifecycle_bind on public.provider_fixture_score_heads;
create trigger provider_fixture_score_head_lifecycle_bind
before insert or update on public.provider_fixture_score_heads
for each row execute function public.bind_provider_fixture_score_head_lifecycle_v1();
alter table public.provider_fixture_score_heads
  enable always trigger provider_fixture_score_head_lifecycle_bind;

create or replace function public.refresh_provider_fixture_score_coherence_from_lifecycle_v1()
returns trigger
language plpgsql
security definer
set search_path=''
as $function$
begin
  update public.provider_fixture_score_heads score_head
  set coherence_checked_at=now()
  where score_head.provider=new.provider
    and score_head.provider_fixture_id=new.provider_fixture_id;
  return new;
end;
$function$;
revoke all on function public.refresh_provider_fixture_score_coherence_from_lifecycle_v1() from public,anon,authenticated;
drop trigger if exists provider_fixture_lifecycle_refresh_score_coherence on public.provider_fixture_lifecycle_heads;
create trigger provider_fixture_lifecycle_refresh_score_coherence
after insert or update of generation,causal_generation,current_state,current_status,latest_reconciliation_id
on public.provider_fixture_lifecycle_heads
for each row execute function public.refresh_provider_fixture_score_coherence_from_lifecycle_v1();
alter table public.provider_fixture_lifecycle_heads
  enable always trigger provider_fixture_lifecycle_refresh_score_coherence;

create or replace function public.write_provider_fixture_score_coherence_event_v1()
returns trigger
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_league_id uuid;
  v_source_run_id uuid;
  v_lifecycle public.provider_fixture_lifecycle_heads%rowtype;
  v_fingerprint text;
begin
  select reconciliation_row.league_id into v_league_id
  from public.provider_fixture_score_reconciliations reconciliation_row
  where reconciliation_row.id=new.latest_reconciliation_id;

  select lifecycle_head.* into v_lifecycle
  from public.provider_fixture_lifecycle_heads lifecycle_head
  where lifecycle_head.provider=new.provider
    and lifecycle_head.provider_fixture_id=new.provider_fixture_id;

  v_source_run_id:=case
    when new.coherence_status='aligned' then new.latest_run_id
    else coalesce(v_lifecycle.latest_run_id,new.latest_run_id)
  end;
  -- Il certificato usa la generazione causale attualmente osservata.
  -- Una semplice revisione tecnica `refreshed` mantiene la stessa impronta,
  -- mentre ogni avanzamento semantico produce un nuovo evento immutabile.
  v_fingerprint:=pg_catalog.md5(
    new.id::text||E'\n'||new.generation::text||E'\n'||
    coalesce(v_lifecycle.causal_generation::text,'')||E'\n'||
    new.coherence_status||E'\n'||new.coherence_reason_code
  );

  insert into public.provider_fixture_score_coherence_events(
    score_head_id,league_id,source_run_id,provider,provider_fixture_fingerprint,
    event_type,score_generation,fixture_lifecycle_generation,fixture_lifecycle_causal_generation,coherence_status,
    reason_code,event_fingerprint
  ) values(
    new.id,v_league_id,v_source_run_id,new.provider,
    pg_catalog.md5(new.provider||E'\n'||new.provider_fixture_id),
    new.coherence_status,new.generation,v_lifecycle.generation,v_lifecycle.causal_generation,
    new.coherence_status,new.coherence_reason_code,v_fingerprint
  ) on conflict(event_fingerprint) do nothing;
  return new;
end;
$function$;
revoke all on function public.write_provider_fixture_score_coherence_event_v1() from public,anon,authenticated;
drop trigger if exists provider_fixture_score_coherence_event_writer on public.provider_fixture_score_heads;
create trigger provider_fixture_score_coherence_event_writer
after insert or update on public.provider_fixture_score_heads
for each row execute function public.write_provider_fixture_score_coherence_event_v1();
alter table public.provider_fixture_score_heads
  enable always trigger provider_fixture_score_coherence_event_writer;

create or replace function public.prevent_provider_fixture_score_coherence_event_mutation_v1()
returns trigger
language plpgsql
security definer
set search_path=''
as $function$
begin
  raise exception 'Evento di coerenza partita/voti certificato: modifica o cancellazione non consentita.';
end;
$function$;
revoke all on function public.prevent_provider_fixture_score_coherence_event_mutation_v1() from public,anon,authenticated;
drop trigger if exists provider_fixture_score_coherence_events_immutable on public.provider_fixture_score_coherence_events;
create trigger provider_fixture_score_coherence_events_immutable
before update or delete on public.provider_fixture_score_coherence_events
for each row execute function public.prevent_provider_fixture_score_coherence_event_mutation_v1();
alter table public.provider_fixture_score_coherence_events
  enable always trigger provider_fixture_score_coherence_events_immutable;

-- Attiva il binding e registra un evento conservativo per le teste preesistenti.
update public.provider_fixture_score_heads score_head
set coherence_checked_at=now();

create or replace function public.get_provider_fixture_score_coherence_result_v1(p_run_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $function$
declare
  v_run public.provider_sync_runs%rowtype;
  v_fixture_id text;
  v_head public.provider_fixture_score_heads%rowtype;
  v_event_count integer:=0;
  v_stale_count integer:=0;
begin
  select run_row.* into v_run from public.provider_sync_runs run_row where run_row.id=p_run_id;
  if not found then return jsonb_build_object('fixtureScoreCoherence',false); end if;

  select count(*)::integer,count(*) filter(where event_row.coherence_status='stale')::integer
  into v_event_count,v_stale_count
  from public.provider_fixture_score_coherence_events event_row
  where event_row.source_run_id=p_run_id;

  if v_run.sync_type='sync-fixture-players' then
    v_fixture_id:=v_run.requested_for->>'fixtureId';
    select head_row.* into v_head
    from public.provider_fixture_score_heads head_row
    where head_row.provider=v_run.provider
      and head_row.provider_fixture_id=v_fixture_id;
  end if;

  return jsonb_build_object(
    'fixtureScoreCoherence',v_run.sync_type in ('sync-fixtures','sync-fixture-players'),
    'fixtureScoreCoherenceStatus',case when v_head.id is not null then v_head.coherence_status
      when v_stale_count>0 then 'stale' else null end,
    'fixtureScoreCoherenceEventCount',v_event_count,
    'fixtureScoreCoherenceStaleCount',v_stale_count,
    'fixtureScoreCoherenceScoreGeneration',v_head.generation,
    'fixtureScoreCoherenceLifecycleGeneration',v_head.fixture_lifecycle_causal_generation,
    'fixtureScoreCoherenceLifecycleRevision',v_head.fixture_lifecycle_generation,
    'fixtureScoreCoherenceReasonCode',v_head.coherence_reason_code
  );
end;
$function$;
revoke all on function public.get_provider_fixture_score_coherence_result_v1(uuid) from public,anon,authenticated,service_role;

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
    or v_message like '%coerenza partita/voti provider non valida%'
    or v_message like '%coherence.%'
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

create or replace function public.finish_provider_sync_run_guarded_v10(
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
  v_coherence_result jsonb:='{}'::jsonb;
  v_result jsonb;
  v_watermark jsonb:='{}'::jsonb;
  v_sync_type text;
begin
  if v_status not in ('completed','failed') then raise exception 'Stato finale del run provider non valido.'; end if;
  if v_status='failed' then
    v_result:=public.finish_provider_sync_run_atomic_core_v1(p_run_id,p_status,p_records_processed,p_error_message,p_expected_revision,p_lease_token);
    return v_result||jsonb_build_object('monotonicPublication',true,'publicationSuperseded',false,'catalogReconciliation',false,'catalogSuperseded',false,'fixtureLifecycleReconciliation',false,'fixtureScoreReconciliation',false,'fixtureScoreCoherence',false);
  end if;

  select run_row.sync_type into v_sync_type from public.provider_sync_runs run_row where run_row.id=p_run_id;
  if not found then raise exception 'Run provider non trovato durante la chiusura v10.'; end if;
  v_decision:=public.provider_sync_scope_watermark_decision_v1(p_run_id,p_lease_token);
  if coalesce((v_decision->>'stale')::boolean,false) then
    return public.discard_stale_provider_sync_publication_v1(p_run_id,p_records_processed,p_expected_revision,p_lease_token,v_decision)
      ||jsonb_build_object('catalogReconciliation',false,'catalogSuperseded',false,'fixtureLifecycleReconciliation',false,'fixtureScoreReconciliation',false,'fixtureScoreCoherence',false);
  end if;
  v_scope:=public.certify_provider_sync_publication_scope_v1(p_run_id,p_lease_token);

  if v_sync_type='sync-season-players' then
    v_catalog_decision:=public.provider_player_catalog_decision_v1(p_run_id,p_lease_token);
    if coalesce((v_catalog_decision->>'superseded')::boolean,false) then
      return public.discard_superseded_provider_player_catalog_v1(p_run_id,p_records_processed,p_expected_revision,p_lease_token,v_catalog_decision)
        ||jsonb_build_object('fixtureLifecycleReconciliation',false,'fixtureScoreReconciliation',false,'fixtureScoreCoherence',false);
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
  v_coherence_result:=public.get_provider_fixture_score_coherence_result_v1(p_run_id);
  return v_result||v_scope||v_watermark||v_catalog_prepare||v_catalog_result||v_fixture_prepare||v_fixture_result||v_score_prepare||v_score_result||v_coherence_result
    ||jsonb_build_object('semanticScopeBinding',true,'monotonicPublication',true,'publicationSuperseded',false,'causalFixtureScoreBinding',true);
end;
$function$;
revoke all on function public.finish_provider_sync_run_guarded_v10(uuid,text,integer,text,bigint,uuid) from public,anon,authenticated;
grant execute on function public.finish_provider_sync_run_guarded_v10(uuid,text,integer,text,bigint,uuid) to service_role;

create or replace function public.finish_provider_sync_run_guarded_v9(
  p_run_id uuid,p_status text,p_records_processed integer,p_error_message text default null,
  p_expected_revision bigint default null,p_lease_token uuid default null
)
returns jsonb language plpgsql security definer set search_path='' as $function$
begin
  return public.finish_provider_sync_run_guarded_v10(p_run_id,p_status,p_records_processed,p_error_message,p_expected_revision,p_lease_token);
end;
$function$;
revoke all on function public.finish_provider_sync_run_guarded_v9(uuid,text,integer,text,bigint,uuid) from public,anon,authenticated;
grant execute on function public.finish_provider_sync_run_guarded_v9(uuid,text,integer,text,bigint,uuid) to service_role;

create or replace function public.get_league_provider_fixture_score_coherence_center_v1(p_league_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $function$
declare
  v_owner_id uuid;
  v_aligned integer:=0;
  v_stale integer:=0;
  v_missing integer:=0;
  v_final_missing integer:=0;
  v_events_24h integer:=0;
  v_latest_event jsonb;
  v_latest_head jsonb;
begin
  if auth.uid() is null then raise exception 'Devi effettuare l''accesso.'; end if;
  select league_row.owner_id into v_owner_id from public.leagues league_row where league_row.id=p_league_id;
  if not found then raise exception 'Lega non trovata per il controllo coerenza partita/voti provider.'; end if;
  if v_owner_id<>auth.uid() and not public.is_league_admin(p_league_id) then
    raise exception 'Solo Presidente e Admin possono leggere la coerenza partita/voti provider.';
  end if;

  select
    count(*) filter(where score_head.coherence_status='aligned')::integer,
    count(*) filter(where score_head.coherence_status='stale')::integer,
    count(*) filter(where score_head.coherence_status='missing')::integer
  into v_aligned,v_stale,v_missing
  from public.provider_fixture_score_heads score_head
  join public.provider_fixtures fixture_row
    on fixture_row.provider=score_head.provider
   and fixture_row.provider_fixture_id=score_head.provider_fixture_id
  where exists(
    select 1 from public.fantasy_fixtures fantasy_fixture
    where fantasy_fixture.league_id=p_league_id
      and fantasy_fixture.matchday_id=fixture_row.matchday_id
  );

  select count(*)::integer into v_final_missing
  from public.provider_fixture_lifecycle_heads lifecycle_head
  join public.provider_fixtures fixture_row
    on fixture_row.provider=lifecycle_head.provider
   and fixture_row.provider_fixture_id=lifecycle_head.provider_fixture_id
  left join public.provider_fixture_score_heads score_head
    on score_head.provider=lifecycle_head.provider
   and score_head.provider_fixture_id=lifecycle_head.provider_fixture_id
  where lifecycle_head.current_state='final'
    and exists(
      select 1 from public.fantasy_fixtures fantasy_fixture
      where fantasy_fixture.league_id=p_league_id
        and fantasy_fixture.matchday_id=fixture_row.matchday_id
    )
    and (score_head.id is null or score_head.coherence_status<>'aligned');

  select count(*)::integer into v_events_24h
  from public.provider_fixture_score_coherence_events event_row
  join public.provider_fixture_score_heads event_head on event_head.id=event_row.score_head_id
  join public.provider_fixtures event_fixture
    on event_fixture.provider=event_head.provider
   and event_fixture.provider_fixture_id=event_head.provider_fixture_id
  where event_row.created_at>=now()-interval '24 hours'
    and exists(
      select 1 from public.fantasy_fixtures fantasy_fixture
      where fantasy_fixture.league_id=p_league_id
        and fantasy_fixture.matchday_id=event_fixture.matchday_id
    );

  select jsonb_build_object(
    'id',event_row.id,'eventType',event_row.event_type,
    'fixtureIdFingerprint',event_row.provider_fixture_fingerprint,
    'scoreGeneration',event_row.score_generation,
    'fixtureLifecycleGeneration',event_row.fixture_lifecycle_causal_generation,
    'fixtureLifecycleRevision',event_row.fixture_lifecycle_generation,
    'coherenceStatus',event_row.coherence_status,'reasonCode',event_row.reason_code,
    'createdAt',event_row.created_at
  ) into v_latest_event
  from public.provider_fixture_score_coherence_events event_row
  join public.provider_fixture_score_heads event_head on event_head.id=event_row.score_head_id
  join public.provider_fixtures event_fixture
    on event_fixture.provider=event_head.provider
   and event_fixture.provider_fixture_id=event_head.provider_fixture_id
  where exists(
    select 1 from public.fantasy_fixtures fantasy_fixture
    where fantasy_fixture.league_id=p_league_id
      and fantasy_fixture.matchday_id=event_fixture.matchday_id
  )
  order by event_row.created_at desc limit 1;

  select jsonb_build_object(
    'id',score_head.id,
    'fixtureIdFingerprint',pg_catalog.md5(score_head.provider||E'\n'||score_head.provider_fixture_id),
    'scoreGeneration',score_head.generation,
    'fixtureLifecycleGeneration',score_head.fixture_lifecycle_causal_generation,
    'fixtureLifecycleRevision',score_head.fixture_lifecycle_generation,
    'coherenceStatus',score_head.coherence_status,
    'reasonCode',score_head.coherence_reason_code,
    'checkedAt',score_head.coherence_checked_at
  ) into v_latest_head
  from public.provider_fixture_score_heads score_head
  join public.provider_fixtures fixture_row
    on fixture_row.provider=score_head.provider
   and fixture_row.provider_fixture_id=score_head.provider_fixture_id
  where exists(
    select 1 from public.fantasy_fixtures fantasy_fixture
    where fantasy_fixture.league_id=p_league_id
      and fantasy_fixture.matchday_id=fixture_row.matchday_id
  )
  order by score_head.coherence_checked_at desc nulls last,score_head.updated_at desc limit 1;

  return jsonb_build_object(
    'protected',true,'healthy',v_stale=0 and v_final_missing=0,
    'causalFixtureScoreBindingActive',true,
    'fixtureGenerationAdvanceInvalidatesScores',true,
    'concurrentLifecycleChangeDetected',true,
    'scoreValuesPreservedWhileStale',true,
    'alignedCount',v_aligned,'staleCount',v_stale,'missingCount',v_missing,
    'finalMissingCount',v_final_missing,'eventsLast24h',v_events_24h,
    'latestHead',v_latest_head,'latestEvent',v_latest_event
  );
end;
$function$;
revoke all on function public.get_league_provider_fixture_score_coherence_center_v1(uuid) from public,anon,service_role;
grant execute on function public.get_league_provider_fixture_score_coherence_center_v1(uuid) to authenticated;

create or replace function public.get_league_provider_sync_health_v19(p_league_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $function$
declare
  v_base jsonb;
  v_coherence jsonb;
  v_healthy boolean;
  v_status text;
begin
  v_base:=public.get_league_provider_sync_health_v18(p_league_id);
  v_coherence:=public.get_league_provider_fixture_score_coherence_center_v1(p_league_id);
  v_healthy:=coalesce((v_base->>'healthy')::boolean,false)
    and coalesce((v_coherence->>'healthy')::boolean,false);
  v_status:=case when not v_healthy then 'attention' else coalesce(v_base->>'status','idle') end;
  return v_base||jsonb_build_object(
    'protected',coalesce((v_base->>'protected')::boolean,false) and coalesce((v_coherence->>'protected')::boolean,false),
    'healthy',v_healthy,'status',v_status,'fixtureScoreCoherence',v_coherence
  );
end;
$function$;
revoke all on function public.get_league_provider_sync_health_v19(uuid) from public,anon,service_role;
grant execute on function public.get_league_provider_sync_health_v19(uuid) to authenticated;

create or replace function public.get_provider_fixture_score_coherence_integrity_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $function$
declare
  v_predecessor jsonb;
  v_causal text;
  v_capture text;
  v_bind text;
  v_refresh text;
  v_event text;
  v_immutable text;
  v_finish_v10 text;
  v_finish_v9 text;
  v_retry text;
begin
  v_predecessor:=public.get_provider_fixture_lifecycle_integrity_v1();
  select pg_catalog.pg_get_functiondef('public.maintain_provider_fixture_lifecycle_causal_generation_v1()'::regprocedure) into v_causal;
  select pg_catalog.pg_get_functiondef('public.capture_provider_fixture_score_lifecycle_v1()'::regprocedure) into v_capture;
  select pg_catalog.pg_get_functiondef('public.bind_provider_fixture_score_head_lifecycle_v1()'::regprocedure) into v_bind;
  select pg_catalog.pg_get_functiondef('public.refresh_provider_fixture_score_coherence_from_lifecycle_v1()'::regprocedure) into v_refresh;
  select pg_catalog.pg_get_functiondef('public.write_provider_fixture_score_coherence_event_v1()'::regprocedure) into v_event;
  select pg_catalog.pg_get_functiondef('public.prevent_provider_fixture_score_coherence_event_mutation_v1()'::regprocedure) into v_immutable;
  select pg_catalog.pg_get_functiondef('public.finish_provider_sync_run_guarded_v10(uuid,text,integer,text,bigint,uuid)'::regprocedure) into v_finish_v10;
  select pg_catalog.pg_get_functiondef('public.finish_provider_sync_run_guarded_v9(uuid,text,integer,text,bigint,uuid)'::regprocedure) into v_finish_v9;
  select pg_catalog.pg_get_functiondef('public.provider_recovery_retry_policy_v1(text,integer,text)'::regprocedure) into v_retry;

  return jsonb_build_object(
    'predecessor_ready',
      (select count(*) from jsonb_each(v_predecessor))=20
      and not exists(
        select 1 from jsonb_each(v_predecessor) predecessor_check
        where predecessor_check.key not in ('predecessor_ready','finish_v9_ready')
          and (jsonb_typeof(predecessor_check.value) is distinct from 'boolean'
            or predecessor_check.value is distinct from 'true'::jsonb)
      )
      and jsonb_typeof(v_predecessor->'predecessor_ready')='boolean'
      and (v_predecessor->'predecessor_ready')='false'::jsonb
      and jsonb_typeof(v_predecessor->'finish_v9_ready')='boolean'
      and (v_predecessor->'finish_v9_ready')='false'::jsonb
      and position('finish_provider_sync_run_guarded_v10' in lower(v_finish_v9))>0
      and position('finish_provider_sync_run_guarded_v9' in lower(pg_catalog.pg_get_functiondef('public.finish_provider_sync_run_guarded_v8(uuid,text,integer,text,bigint,uuid)'::regprocedure)))>0,
    'reconciliation_columns_ready',not exists(select 1 from (values
      ('fixture_lifecycle_head_id'),('fixture_lifecycle_reconciliation_id'),('fixture_lifecycle_generation'),
      ('fixture_lifecycle_causal_generation'),('fixture_lifecycle_state'),('fixture_lifecycle_status')) required(column_name)
      where not exists(select 1 from information_schema.columns column_row
        where column_row.table_schema='public' and column_row.table_name='provider_fixture_score_reconciliations'
          and column_row.column_name=required.column_name)),
    'head_columns_ready',not exists(select 1 from (values
      ('fixture_lifecycle_head_id'),('fixture_lifecycle_reconciliation_id'),('fixture_lifecycle_generation'),
      ('fixture_lifecycle_causal_generation'),('coherence_status'),('coherence_reason_code'),('coherence_checked_at')) required(column_name)
      where not exists(select 1 from information_schema.columns column_row
        where column_row.table_schema='public' and column_row.table_name='provider_fixture_score_heads'
          and column_row.column_name=required.column_name)),
    'event_table_ready',to_regclass('public.provider_fixture_score_coherence_events') is not null
      and exists(select 1 from information_schema.columns column_row
        where column_row.table_schema='public' and column_row.table_name='provider_fixture_score_coherence_events'
          and column_row.column_name='fixture_lifecycle_causal_generation'),
    'constraints_ready',exists(select 1 from pg_catalog.pg_constraint where conrelid='public.provider_fixture_score_heads'::regclass and conname='provider_fixture_score_heads_coherence_status_check')
      and exists(select 1 from pg_catalog.pg_constraint where conrelid='public.provider_fixture_lifecycle_heads'::regclass and conname='provider_fixture_lifecycle_heads_causal_generation_check')
      and exists(select 1 from pg_catalog.pg_constraint where conrelid='public.provider_fixture_score_reconciliations'::regclass and conname='provider_fixture_score_reconciliations_lifecycle_generation_check')
      and exists(select 1 from pg_catalog.pg_constraint where conrelid='public.provider_fixture_score_reconciliations'::regclass and conname='provider_fixture_score_reconciliations_lifecycle_causal_generation_check')
      and exists(select 1 from pg_catalog.pg_constraint where conrelid='public.provider_fixture_score_heads'::regclass and conname='provider_fixture_score_heads_lifecycle_causal_generation_check')
      and exists(select 1 from pg_catalog.pg_constraint where conrelid='public.provider_fixture_score_coherence_events'::regclass and conname='provider_fixture_score_coherence_events_status_check'),
    'indexes_ready',to_regclass('public.provider_fixture_score_heads_coherence_idx') is not null
      and to_regclass('public.provider_fixture_score_reconciliations_lifecycle_idx') is not null
      and to_regclass('public.provider_fixture_score_coherence_events_latest_idx') is not null,
    'rls_ready',(select relrowsecurity from pg_catalog.pg_class where oid='public.provider_fixture_score_coherence_events'::regclass),
    'authenticated_write_blocked',not has_table_privilege('authenticated','public.provider_fixture_score_coherence_events','SELECT')
      and not has_table_privilege('authenticated','public.provider_fixture_score_coherence_events','INSERT')
      and not has_table_privilege('authenticated','public.provider_fixture_score_coherence_events','UPDATE')
      and not has_table_privilege('authenticated','public.provider_fixture_score_coherence_events','DELETE'),
    'immutable_history_ready',exists(select 1 from pg_catalog.pg_trigger trigger_row
      where trigger_row.tgrelid='public.provider_fixture_score_coherence_events'::regclass
        and trigger_row.tgname='provider_fixture_score_coherence_events_immutable'
        and trigger_row.tgenabled='A' and not trigger_row.tgisinternal)
      and position('raise exception' in lower(v_immutable))>0
      and position('modifica o cancellazione non consentita' in lower(v_immutable))>0,
    'capture_trigger_ready',exists(select 1 from pg_catalog.pg_trigger trigger_row
      where trigger_row.tgrelid='public.provider_fixture_score_reconciliations'::regclass
        and trigger_row.tgname='provider_fixture_score_reconciliation_lifecycle_capture_insert'
        and trigger_row.tgenabled='A' and not trigger_row.tgisinternal)
      and exists(select 1 from pg_catalog.pg_trigger trigger_row
      where trigger_row.tgrelid='public.provider_fixture_score_reconciliations'::regclass
        and trigger_row.tgname='provider_fixture_score_reconciliation_lifecycle_capture_update'
        and trigger_row.tgenabled='A' and not trigger_row.tgisinternal)
      and position('coherence.lifecycle_missing' in lower(v_capture))>0
      and position('fixture_lifecycle_generation' in lower(v_capture))>0
      and position('fixture_lifecycle_causal_generation' in lower(v_capture))>0,
    'head_binding_trigger_ready',exists(select 1 from pg_catalog.pg_trigger trigger_row
      where trigger_row.tgrelid='public.provider_fixture_score_heads'::regclass
        and trigger_row.tgname='provider_fixture_score_head_lifecycle_bind'
        and trigger_row.tgenabled='A' and not trigger_row.tgisinternal)
      and position('coherence.lifecycle_advanced' in lower(v_bind))>0
      and position('coherence.concurrent_lifecycle_change' in lower(v_bind))>0,
    'lifecycle_refresh_trigger_ready',exists(select 1 from pg_catalog.pg_trigger trigger_row
      where trigger_row.tgrelid='public.provider_fixture_lifecycle_heads'::regclass
        and trigger_row.tgname='provider_fixture_lifecycle_refresh_score_coherence'
        and trigger_row.tgenabled='A' and not trigger_row.tgisinternal)
      and position('update public.provider_fixture_score_heads' in lower(v_refresh))>0,
    'event_writer_ready',exists(select 1 from pg_catalog.pg_trigger trigger_row
      where trigger_row.tgrelid='public.provider_fixture_score_heads'::regclass
        and trigger_row.tgname='provider_fixture_score_coherence_event_writer'
        and trigger_row.tgenabled='A' and not trigger_row.tgisinternal)
      and position('provider_fixture_score_coherence_events' in lower(v_event))>0,
    'backfill_ready',not exists(select 1 from public.provider_fixture_score_heads head_row
      where head_row.coherence_status not in ('aligned','stale','missing')
        or head_row.coherence_checked_at is null)
      and not exists(select 1 from public.provider_fixture_lifecycle_heads lifecycle_head
        where lifecycle_head.causal_generation is null or lifecycle_head.causal_generation<=0),
    'causal_binding_ready',exists(select 1 from pg_catalog.pg_trigger trigger_row
        where trigger_row.tgrelid='public.provider_fixture_lifecycle_heads'::regclass
          and trigger_row.tgname='provider_fixture_lifecycle_causal_generation_guard'
          and trigger_row.tgenabled='A' and not trigger_row.tgisinternal)
      and position('new.last_transition=''refreshed''' in pg_catalog.regexp_replace(lower(v_causal),'[[:space:]]+','','g'))>0
      and position('coherence.lifecycle_generation_non_monotonic' in lower(v_causal))>0
      and position('new.generation=old.generation+1' in pg_catalog.regexp_replace(lower(v_causal),'[[:space:]]+','','g'))>0
      and position('old.causal_generation' in lower(v_causal))>0
      and position('new.fixture_lifecycle_causal_generation=v_lifecycle_head.causal_generation' in pg_catalog.regexp_replace(lower(v_bind),'[[:space:]]+','','g'))>0
      and position('new.fixture_lifecycle_causal_generation<v_lifecycle_head.causal_generation' in pg_catalog.regexp_replace(lower(v_bind),'[[:space:]]+','','g'))>0,
    'finish_v10_ready',has_function_privilege('service_role','public.finish_provider_sync_run_guarded_v10(uuid,text,integer,text,bigint,uuid)','EXECUTE')
      and position('provider_sync_scope_watermark_decision_v1' in lower(v_finish_v10))>0
      and position('certify_provider_sync_publication_scope_v1' in lower(v_finish_v10))>0
      and position('provider_player_catalog_decision_v1' in lower(v_finish_v10))>0
      and position('prepare_provider_player_catalog_reconciliation_v1' in lower(v_finish_v10))>0
      and position('prepare_provider_fixture_lifecycle_reconciliation_v1' in lower(v_finish_v10))>0
      and position('prepare_provider_fixture_score_reconciliation_v1' in lower(v_finish_v10))>0
      and position('finish_provider_sync_run_atomic_core_v1' in lower(v_finish_v10))>0
      and position('advance_provider_sync_scope_watermark_v1' in lower(v_finish_v10))>0
      and position('get_provider_fixture_score_coherence_result_v1' in lower(v_finish_v10))>0
      and position('leghevo.provider_catalog_reconciliation_id' in lower(v_finish_v10))>0
      and position('leghevo.provider_fixture_lifecycle_reconciliation_id' in lower(v_finish_v10))>0
      and position('leghevo.provider_fixture_score_reconciliation_id' in lower(v_finish_v10))>0,
    'legacy_v9_ready',position('finish_provider_sync_run_guarded_v10' in lower(v_finish_v9))>0,
    'retry_policy_ready',position('coerenza partita/voti provider non valida' in lower(v_retry))>0
      and position('coherence.%' in lower(v_retry))>0,
    'center_health_ready',to_regprocedure('public.get_league_provider_fixture_score_coherence_center_v1(uuid)') is not null
      and to_regprocedure('public.get_league_provider_sync_health_v19(uuid)') is not null
      and has_function_privilege('authenticated','public.get_league_provider_sync_health_v19(uuid)','EXECUTE'),
    'realtime_ready',exists(select 1 from pg_catalog.pg_publication_tables publication_table
      where publication_table.pubname='supabase_realtime' and publication_table.schemaname='public'
        and publication_table.tablename='provider_fixture_score_heads')
      and not exists(select 1 from pg_catalog.pg_publication_tables publication_table
      where publication_table.pubname='supabase_realtime' and publication_table.schemaname='public'
        and publication_table.tablename='provider_fixture_score_coherence_events')
  );
end;
$function$;
revoke all on function public.get_provider_fixture_score_coherence_integrity_v1() from public,anon,authenticated;
grant execute on function public.get_provider_fixture_score_coherence_integrity_v1() to service_role;

do $validation$
declare
  v_checks jsonb;
  v_failed text;
begin
  v_checks:=public.get_provider_fixture_score_coherence_integrity_v1();
  select string_agg(check_row.key,', ' order by check_row.key) into v_failed
  from jsonb_each(v_checks) check_row
  where jsonb_typeof(check_row.value) is distinct from 'boolean'
    or check_row.value is distinct from 'true'::jsonb;
  if (select count(*) from jsonb_each(v_checks))<>20 then
    raise exception 'Validazione v0.62.20 non superata: attesi 20 controlli, trovati %.',
      (select count(*) from jsonb_each(v_checks));
  end if;
  if v_failed is not null then
    raise exception 'Validazione v0.62.20 non superata. Controlli falsi: %',v_failed;
  end if;
end;
$validation$;

commit;

-- DIAGNOSTICA FINALE: devono comparire esattamente 20 valori true.
select
  (checks->>'predecessor_ready')::boolean as predecessor_ready,
  (checks->>'reconciliation_columns_ready')::boolean as reconciliation_columns_ready,
  (checks->>'head_columns_ready')::boolean as head_columns_ready,
  (checks->>'event_table_ready')::boolean as event_table_ready,
  (checks->>'constraints_ready')::boolean as constraints_ready,
  (checks->>'indexes_ready')::boolean as indexes_ready,
  (checks->>'rls_ready')::boolean as rls_ready,
  (checks->>'authenticated_write_blocked')::boolean as authenticated_write_blocked,
  (checks->>'immutable_history_ready')::boolean as immutable_history_ready,
  (checks->>'capture_trigger_ready')::boolean as capture_trigger_ready,
  (checks->>'head_binding_trigger_ready')::boolean as head_binding_trigger_ready,
  (checks->>'lifecycle_refresh_trigger_ready')::boolean as lifecycle_refresh_trigger_ready,
  (checks->>'event_writer_ready')::boolean as event_writer_ready,
  (checks->>'backfill_ready')::boolean as backfill_ready,
  (checks->>'causal_binding_ready')::boolean as causal_binding_ready,
  (checks->>'finish_v10_ready')::boolean as finish_v10_ready,
  (checks->>'legacy_v9_ready')::boolean as legacy_v9_ready,
  (checks->>'retry_policy_ready')::boolean as retry_policy_ready,
  (checks->>'center_health_ready')::boolean as center_health_ready,
  (checks->>'realtime_ready')::boolean as realtime_ready
from (select public.get_provider_fixture_score_coherence_integrity_v1() as checks) diagnostic;
