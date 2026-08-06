-- LEGHEVO v0.62.18
-- Fotografia autorevole e riconciliazione non distruttiva dei voti partita provider.
-- Eseguire dopo database/121_provider_player_catalog_reconciliation_safety.sql.
-- Pacchetto di reinstallazione verificato dopo diagnostica v0.62.19: gli oggetti v0.62.18 risultavano completamente assenti.
-- La logica funzionale resta v0.62.18; il nome v4 evita l'esecuzione accidentale di file precedenti, usa jsonb_each() e certifica esplicitamente la continuita del wrapper v7 verso v8.

begin;

-- PRE-FLIGHT: ogni dipendenza viene verificata prima di creare oggetti.
do $preflight$
declare
  v_missing text[] := array[]::text[];
  v_checks jsonb;
begin
  if to_regprocedure('public.get_provider_player_catalog_reconciliation_integrity_v1()') is null then
    v_missing := array_append(v_missing,'function public.get_provider_player_catalog_reconciliation_integrity_v1()');
  else
    v_checks := public.get_provider_player_catalog_reconciliation_integrity_v1();
    if (select count(*) from jsonb_each(v_checks)) <> 20
       or exists (
         select 1 from jsonb_each(v_checks) check_row
         where jsonb_typeof(check_row.value) is distinct from 'boolean'
            or check_row.value is distinct from 'true'::jsonb
       ) then
      v_missing := array_append(v_missing,'v0.62.17 integrity: exactly 20 checks must be true');
    end if;
  end if;

  if to_regclass('public.player_match_scores') is null then
    v_missing := array_append(v_missing,'table public.player_match_scores');
  end if;
  if to_regclass('public.athletes') is null then
    v_missing := array_append(v_missing,'table public.athletes');
  end if;
  if to_regclass('public.matchdays') is null then
    v_missing := array_append(v_missing,'table public.matchdays');
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
  if to_regclass('public.provider_sync_stage_athletes') is null then
    v_missing := array_append(v_missing,'table public.provider_sync_stage_athletes');
  end if;
  if to_regclass('public.provider_sync_stage_scores') is null then
    v_missing := array_append(v_missing,'table public.provider_sync_stage_scores');
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
      ('player_match_scores','id'),
      ('player_match_scores','athlete_id'),
      ('player_match_scores','matchday_id'),
      ('player_match_scores','provider_fixture_id'),
      ('player_match_scores','provider_rating'),
      ('player_match_scores','fantasy_score'),
      ('player_match_scores','bonuses'),
      ('player_match_scores','maluses'),
      ('player_match_scores','raw_statistics'),
      ('player_match_scores','provider_payload'),
      ('player_match_scores','is_final'),
      ('player_match_scores','updated_at'),
      ('athletes','id'),
      ('athletes','provider'),
      ('athletes','provider_player_id'),
      ('matchdays','id'),
      ('provider_fixtures','provider'),
      ('provider_fixtures','provider_fixture_id'),
      ('provider_fixtures','matchday_id'),
      ('provider_fixtures','status'),
      ('provider_fixtures','home_team_provider_id'),
      ('provider_fixtures','away_team_provider_id'),
      ('provider_sync_runs','id'),
      ('provider_sync_runs','provider'),
      ('provider_sync_runs','sync_type'),
      ('provider_sync_runs','status'),
      ('provider_sync_runs','started_at'),
      ('provider_sync_publications','id'),
      ('provider_sync_publications','run_id'),
      ('provider_sync_publications','recovery_request_id'),
      ('provider_sync_publications','league_id'),
      ('provider_sync_publications','status'),
      ('provider_sync_publications','staged_primary_record_count'),
      ('provider_sync_scope_certificates','publication_id'),
      ('provider_sync_scope_certificates','status'),
      ('provider_sync_scope_certificates','scope_kind'),
      ('provider_sync_scope_certificates','requested_fixture_id'),
      ('provider_sync_scope_certificates','observed_score_count'),
      ('provider_sync_stage_athletes','publication_id'),
      ('provider_sync_stage_athletes','athlete_id'),
      ('provider_sync_stage_athletes','provider'),
      ('provider_sync_stage_athletes','provider_player_id'),
      ('provider_sync_stage_athletes','provider_team_id'),
      ('provider_sync_stage_scores','publication_id'),
      ('provider_sync_stage_scores','athlete_id'),
      ('provider_sync_stage_scores','matchday_id'),
      ('provider_sync_stage_scores','provider_fixture_id'),
      ('provider_sync_stage_scores','provider_rating'),
      ('provider_sync_stage_scores','fantasy_score'),
      ('provider_sync_stage_scores','bonuses'),
      ('provider_sync_stage_scores','maluses'),
      ('provider_sync_stage_scores','is_final')
    ) required(table_name,column_name)
    where not exists (
      select 1 from information_schema.columns column_row
      where column_row.table_schema='public'
        and column_row.table_name=required.table_name
        and column_row.column_name=required.column_name
    )
  ) then
    v_missing := array_append(v_missing,'required columns for fixture score reconciliation');
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
  if to_regprocedure('public.finish_provider_sync_run_atomic_core_v1(uuid,text,integer,text,bigint,uuid)') is null then
    v_missing := array_append(v_missing,'RPC public.finish_provider_sync_run_atomic_core_v1(uuid,text,integer,text,bigint,uuid)');
  end if;
  if to_regprocedure('public.advance_provider_sync_scope_watermark_v1(uuid,integer,uuid)') is null then
    v_missing := array_append(v_missing,'RPC public.advance_provider_sync_scope_watermark_v1(uuid,integer,uuid)');
  end if;
  if to_regprocedure('public.get_provider_player_catalog_result_v1(uuid)') is null then
    v_missing := array_append(v_missing,'RPC public.get_provider_player_catalog_result_v1(uuid)');
  end if;
  if to_regprocedure('public.get_league_provider_sync_health_v16(uuid)') is null then
    v_missing := array_append(v_missing,'RPC public.get_league_provider_sync_health_v16(uuid)');
  end if;
  if to_regprocedure('public.is_league_admin(uuid)') is null then
    v_missing := array_append(v_missing,'function public.is_league_admin(uuid)');
  end if;

  if to_regclass('public.player_match_scores_athlete_id_matchday_id_key') is null then
    v_missing := array_append(v_missing,'unique constraint public.player_match_scores(athlete_id,matchday_id)');
  end if;
  if to_regclass('public.provider_fixtures_provider_provider_fixture_id_key') is null then
    v_missing := array_append(v_missing,'unique constraint public.provider_fixtures(provider,provider_fixture_id)');
  end if;

  if exists (
    select 1 from public.provider_sync_runs run_row where run_row.status='running'
  ) then
    v_missing := array_append(v_missing,'no provider sync run may be running during installation');
  end if;

  if coalesce(array_length(v_missing,1),0)>0 then
    raise exception 'Preflight v0.62.18 non superato. Dipendenze mancanti: %',array_to_string(v_missing,'; ');
  end if;
end;
$preflight$;

alter table public.player_match_scores
  add column if not exists provider_score_state text not null default 'current',
  add column if not exists provider_score_reconciliation_id uuid,
  add column if not exists provider_score_reconciled_at timestamptz;

alter table public.player_match_scores
  drop constraint if exists player_match_scores_provider_score_state_check;
alter table public.player_match_scores
  add constraint player_match_scores_provider_score_state_check
  check (provider_score_state in ('current','retired'));

comment on column public.player_match_scores.provider_score_state is
  'Stato autorevole del voto provider: current oppure retired senza cancellazione fisica.';
comment on column public.player_match_scores.provider_score_reconciliation_id is
  'Riconciliazione atomica che ha confermato o ritirato logicamente il voto.';

create table if not exists public.provider_fixture_score_heads (
  id uuid primary key default gen_random_uuid(),
  provider text not null,
  provider_fixture_id text not null,
  matchday_id uuid not null references public.matchdays(id) on delete restrict,
  fixture_status text not null,
  is_final boolean not null,
  latest_run_id uuid not null references public.provider_sync_runs(id) on delete restrict,
  latest_publication_id uuid not null references public.provider_sync_publications(id) on delete restrict,
  latest_reconciliation_id uuid,
  current_score_count integer not null default 0,
  generation bigint not null default 1,
  summary text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(provider,provider_fixture_id),
  constraint provider_fixture_score_heads_count_check check (current_score_count between 0 and 10000),
  constraint provider_fixture_score_heads_generation_check check (generation>0),
  constraint provider_fixture_score_heads_provider_check check (length(trim(provider)) between 1 and 100 and provider !~ E'[\r\n]'),
  constraint provider_fixture_score_heads_fixture_check check (length(trim(provider_fixture_id)) between 1 and 100 and provider_fixture_id !~ E'[\r\n]'),
  constraint provider_fixture_score_heads_status_check check (length(trim(fixture_status)) between 1 and 30 and fixture_status !~ E'[\r\n]'),
  constraint provider_fixture_score_heads_summary_check check (length(summary) between 1 and 500 and summary !~ E'[\r\n]')
);

create table if not exists public.provider_fixture_score_reconciliations (
  id uuid primary key default gen_random_uuid(),
  head_id uuid,
  publication_id uuid not null unique references public.provider_sync_publications(id) on delete restrict,
  run_id uuid not null unique references public.provider_sync_runs(id) on delete restrict,
  recovery_request_id uuid references public.provider_recovery_requests(id) on delete set null,
  league_id uuid references public.leagues(id) on delete set null,
  provider text not null,
  provider_fixture_id text not null,
  matchday_id uuid not null references public.matchdays(id) on delete restrict,
  fixture_status text not null,
  candidate_final boolean not null,
  status text not null default 'collecting',
  observed_score_count integer not null default 0,
  home_score_count integer not null default 0,
  away_score_count integer not null default 0,
  retired_score_count integer not null default 0,
  restored_score_count integer not null default 0,
  generation bigint,
  reason_code text not null default 'score.collecting',
  summary text not null default 'Fotografia voti partita provider in riconciliazione.',
  reconciliation_fingerprint text not null,
  revision bigint not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  applied_at timestamptz,
  constraint provider_fixture_score_reconciliations_status_check check (status in ('collecting','applied')),
  constraint provider_fixture_score_reconciliations_count_check check (
    observed_score_count between 0 and 10000 and home_score_count between 0 and 5000
    and away_score_count between 0 and 5000 and retired_score_count between 0 and 10000
    and restored_score_count between 0 and 10000
  ),
  constraint provider_fixture_score_reconciliations_reason_check check (reason_code in ('score.collecting','score.applied')),
  constraint provider_fixture_score_reconciliations_fingerprint_check check (reconciliation_fingerprint ~ '^[0-9a-f]{32}$'),
  constraint provider_fixture_score_reconciliations_revision_check check (revision>0 and (generation is null or generation>0)),
  constraint provider_fixture_score_reconciliations_terminal_check check (
    (status='collecting' and applied_at is null) or (status='applied' and applied_at is not null)
  ),
  constraint provider_fixture_score_reconciliations_summary_check check (length(summary) between 1 and 500 and summary !~ E'[\r\n]')
);

create table if not exists public.provider_fixture_score_members (
  reconciliation_id uuid not null references public.provider_fixture_score_reconciliations(id) on delete restrict,
  player_key_fingerprint text not null,
  team_side text not null,
  has_rating boolean not null,
  member_fingerprint text not null,
  created_at timestamptz not null default now(),
  primary key(reconciliation_id,player_key_fingerprint),
  constraint provider_fixture_score_members_player_check check (player_key_fingerprint ~ '^[0-9a-f]{32}$'),
  constraint provider_fixture_score_members_side_check check (team_side in ('home','away')),
  constraint provider_fixture_score_members_fingerprint_check check (member_fingerprint ~ '^[0-9a-f]{32}$')
);

create table if not exists public.provider_fixture_score_events (
  id uuid primary key default gen_random_uuid(),
  reconciliation_id uuid not null references public.provider_fixture_score_reconciliations(id) on delete restrict,
  head_id uuid references public.provider_fixture_score_heads(id) on delete restrict,
  run_id uuid not null references public.provider_sync_runs(id) on delete restrict,
  publication_id uuid not null references public.provider_sync_publications(id) on delete restrict,
  league_id uuid references public.leagues(id) on delete set null,
  event_type text not null,
  provider_fixture_fingerprint text not null,
  candidate_final boolean not null,
  observed_score_count integer not null,
  retired_score_count integer not null,
  restored_score_count integer not null,
  generation bigint,
  reason_code text not null,
  event_fingerprint text not null,
  created_at timestamptz not null default now(),
  unique(reconciliation_id,event_type),
  constraint provider_fixture_score_events_type_check check (event_type in ('collecting','applied')),
  constraint provider_fixture_score_events_fixture_check check (provider_fixture_fingerprint ~ '^[0-9a-f]{32}$'),
  constraint provider_fixture_score_events_count_check check (
    observed_score_count between 0 and 10000 and retired_score_count between 0 and 10000 and restored_score_count between 0 and 10000
  ),
  constraint provider_fixture_score_events_reason_check check (reason_code in ('score.collecting','score.applied')),
  constraint provider_fixture_score_events_generation_check check (generation is null or generation>0),
  constraint provider_fixture_score_events_fingerprint_check check (event_fingerprint ~ '^[0-9a-f]{32}$')
);

alter table public.provider_fixture_score_reconciliations
  drop constraint if exists provider_fixture_score_reconciliations_head_fk;
alter table public.provider_fixture_score_reconciliations
  add constraint provider_fixture_score_reconciliations_head_fk
  foreign key(head_id) references public.provider_fixture_score_heads(id) on delete restrict;

alter table public.provider_fixture_score_heads
  drop constraint if exists provider_fixture_score_heads_reconciliation_fk;
alter table public.provider_fixture_score_heads
  add constraint provider_fixture_score_heads_reconciliation_fk
  foreign key(latest_reconciliation_id) references public.provider_fixture_score_reconciliations(id) on delete restrict;

alter table public.player_match_scores
  drop constraint if exists player_match_scores_provider_score_reconciliation_fk;
alter table public.player_match_scores
  add constraint player_match_scores_provider_score_reconciliation_fk
  foreign key(provider_score_reconciliation_id)
  references public.provider_fixture_score_reconciliations(id) on delete restrict;

create index if not exists provider_fixture_score_heads_latest_idx
  on public.provider_fixture_score_heads(updated_at desc);
create index if not exists provider_fixture_score_reconciliations_latest_idx
  on public.provider_fixture_score_reconciliations(updated_at desc);
create index if not exists provider_fixture_score_reconciliations_league_idx
  on public.provider_fixture_score_reconciliations(league_id,updated_at desc);
create index if not exists provider_fixture_score_members_player_idx
  on public.provider_fixture_score_members(player_key_fingerprint,reconciliation_id);
create index if not exists provider_fixture_score_events_latest_idx
  on public.provider_fixture_score_events(created_at desc);
create index if not exists player_match_scores_provider_state_idx
  on public.player_match_scores(provider_fixture_id,provider_score_state,updated_at desc)
  where provider_fixture_id is not null;

alter table public.provider_fixture_score_heads enable row level security;
alter table public.provider_fixture_score_heads replica identity full;
alter table public.provider_fixture_score_reconciliations enable row level security;
alter table public.provider_fixture_score_reconciliations replica identity full;
alter table public.provider_fixture_score_members enable row level security;
alter table public.provider_fixture_score_events enable row level security;
alter table public.provider_fixture_score_events replica identity full;

revoke all on table public.provider_fixture_score_heads from public,anon,authenticated,service_role;
revoke all on table public.provider_fixture_score_reconciliations from public,anon,authenticated,service_role;
revoke all on table public.provider_fixture_score_members from public,anon,authenticated,service_role;
revoke all on table public.provider_fixture_score_events from public,anon,authenticated,service_role;
grant select on table public.provider_fixture_score_heads to authenticated,service_role;
grant select on table public.provider_fixture_score_reconciliations to authenticated,service_role;
grant select,insert,update on table public.provider_fixture_score_heads to service_role;
grant select,insert,update on table public.provider_fixture_score_reconciliations to service_role;
grant select,insert on table public.provider_fixture_score_members to service_role;
grant select,insert on table public.provider_fixture_score_events to service_role;

drop policy if exists provider_fixture_score_heads_read_directors on public.provider_fixture_score_heads;
create policy provider_fixture_score_heads_read_directors
on public.provider_fixture_score_heads for select to authenticated
using (exists(select 1 from public.leagues league_row where league_row.owner_id=auth.uid() or public.is_league_admin(league_row.id)));

drop policy if exists provider_fixture_score_reconciliations_read_directors on public.provider_fixture_score_reconciliations;
create policy provider_fixture_score_reconciliations_read_directors
on public.provider_fixture_score_reconciliations for select to authenticated
using (
  (league_id is not null and exists(select 1 from public.leagues league_row where league_row.id=provider_fixture_score_reconciliations.league_id and (league_row.owner_id=auth.uid() or public.is_league_admin(league_row.id))))
  or (league_id is null and exists(select 1 from public.leagues league_row where league_row.owner_id=auth.uid() or public.is_league_admin(league_row.id)))
);

drop policy if exists provider_fixture_score_events_read_directors on public.provider_fixture_score_events;
create policy provider_fixture_score_events_read_directors
on public.provider_fixture_score_events for select to authenticated
using (
  (league_id is not null and exists(select 1 from public.leagues league_row where league_row.id=provider_fixture_score_events.league_id and (league_row.owner_id=auth.uid() or public.is_league_admin(league_row.id))))
  or (league_id is null and exists(select 1 from public.leagues league_row where league_row.owner_id=auth.uid() or public.is_league_admin(league_row.id)))
);

create or replace function public.touch_provider_fixture_score_head_v1()
returns trigger language plpgsql security definer set search_path='' as $function$
begin
  new.updated_at:=now();
  return new;
end;
$function$;
revoke all on function public.touch_provider_fixture_score_head_v1() from public,anon,authenticated;
drop trigger if exists provider_fixture_score_heads_touch on public.provider_fixture_score_heads;
create trigger provider_fixture_score_heads_touch before update on public.provider_fixture_score_heads
for each row execute function public.touch_provider_fixture_score_head_v1();
alter table public.provider_fixture_score_heads enable always trigger provider_fixture_score_heads_touch;

create or replace function public.touch_provider_fixture_score_reconciliation_v1()
returns trigger language plpgsql security definer set search_path='' as $function$
begin
  if tg_op='UPDATE' then
    if row(new.publication_id,new.run_id,new.provider,new.provider_fixture_id,new.matchday_id,new.created_at)
       is distinct from row(old.publication_id,old.run_id,old.provider,old.provider_fixture_id,old.matchday_id,old.created_at) then
      raise exception 'Identità della riconciliazione voti provider non modificabile.';
    end if;
    if old.status='applied' then
      raise exception 'Riconciliazione voti provider terminale non modificabile.';
    end if;
    new.revision:=old.revision+1;
    new.updated_at:=now();
    if new.status='applied' then new.applied_at:=coalesce(new.applied_at,now()); end if;
  end if;
  return new;
end;
$function$;
revoke all on function public.touch_provider_fixture_score_reconciliation_v1() from public,anon,authenticated;
drop trigger if exists provider_fixture_score_reconciliations_touch on public.provider_fixture_score_reconciliations;
create trigger provider_fixture_score_reconciliations_touch before update on public.provider_fixture_score_reconciliations
for each row execute function public.touch_provider_fixture_score_reconciliation_v1();
alter table public.provider_fixture_score_reconciliations enable always trigger provider_fixture_score_reconciliations_touch;

create or replace function public.write_provider_fixture_score_event_v1()
returns trigger language plpgsql security definer set search_path='' as $function$
begin
  if tg_op='UPDATE' and new.status is not distinct from old.status then return new; end if;
  insert into public.provider_fixture_score_events(
    reconciliation_id,head_id,run_id,publication_id,league_id,event_type,
    provider_fixture_fingerprint,candidate_final,observed_score_count,
    retired_score_count,restored_score_count,generation,reason_code,event_fingerprint,created_at
  ) values (
    new.id,new.head_id,new.run_id,new.publication_id,new.league_id,new.status,
    pg_catalog.md5(new.provider||E'\n'||new.provider_fixture_id),new.candidate_final,
    new.observed_score_count,new.retired_score_count,new.restored_score_count,
    new.generation,new.reason_code,
    pg_catalog.md5(new.id::text||E'\n'||new.status||E'\n'||new.revision::text||E'\n'||new.observed_score_count::text||E'\n'||new.retired_score_count::text||E'\n'||new.restored_score_count::text),
    new.updated_at
  ) on conflict(reconciliation_id,event_type) do nothing;
  return new;
end;
$function$;
revoke all on function public.write_provider_fixture_score_event_v1() from public,anon,authenticated;
drop trigger if exists provider_fixture_score_event_writer on public.provider_fixture_score_reconciliations;
create trigger provider_fixture_score_event_writer after insert or update of status on public.provider_fixture_score_reconciliations
for each row execute function public.write_provider_fixture_score_event_v1();
alter table public.provider_fixture_score_reconciliations enable always trigger provider_fixture_score_event_writer;

create or replace function public.prevent_provider_fixture_score_event_mutation_v1()
returns trigger language plpgsql security definer set search_path='' as $function$
begin
  raise exception 'Lo storico delle fotografie voti provider è immutabile.';
end;
$function$;
revoke all on function public.prevent_provider_fixture_score_event_mutation_v1() from public,anon,authenticated;
drop trigger if exists provider_fixture_score_events_immutable on public.provider_fixture_score_events;
create trigger provider_fixture_score_events_immutable before update or delete on public.provider_fixture_score_events
for each row execute function public.prevent_provider_fixture_score_event_mutation_v1();
alter table public.provider_fixture_score_events enable always trigger provider_fixture_score_events_immutable;

create or replace function public.prevent_provider_fixture_score_member_mutation_v1()
returns trigger language plpgsql security definer set search_path='' as $function$
begin
  raise exception 'I membri della fotografia voti provider sono immutabili.';
end;
$function$;
revoke all on function public.prevent_provider_fixture_score_member_mutation_v1() from public,anon,authenticated;
drop trigger if exists provider_fixture_score_members_immutable on public.provider_fixture_score_members;
create trigger provider_fixture_score_members_immutable before update or delete on public.provider_fixture_score_members
for each row execute function public.prevent_provider_fixture_score_member_mutation_v1();
alter table public.provider_fixture_score_members enable always trigger provider_fixture_score_members_immutable;

create or replace function public.provider_fixture_score_snapshot_decision_v1(p_run_id uuid,p_lease_token uuid)
returns jsonb language plpgsql security definer set search_path='' as $function$
declare
  v_run public.provider_sync_runs%rowtype;
  v_publication public.provider_sync_publications%rowtype;
  v_certificate public.provider_sync_scope_certificates%rowtype;
  v_fixture public.provider_fixtures%rowtype;
  v_head public.provider_fixture_score_heads%rowtype;
  v_score_count integer:=0;
  v_home_count integer:=0;
  v_away_count integer:=0;
  v_unknown_team_count integer:=0;
  v_final_count integer:=0;
  v_fixture_final boolean:=false;
begin
  perform public.assert_provider_sync_worker_lease_v1(p_run_id,p_lease_token);
  select run_row.* into v_run from public.provider_sync_runs run_row where run_row.id=p_run_id for update;
  if not found or v_run.status<>'running' then raise exception 'Fotografia voti provider rifiutata [score.run_not_running].'; end if;
  if v_run.sync_type<>'sync-fixture-players' then return jsonb_build_object('applicable',false); end if;

  select publication_row.* into v_publication from public.provider_sync_publications publication_row where publication_row.run_id=p_run_id for update;
  if not found or v_publication.status<>'collecting' then raise exception 'Fotografia voti provider rifiutata [score.publication_not_collecting].'; end if;
  select certificate_row.* into v_certificate from public.provider_sync_scope_certificates certificate_row where certificate_row.publication_id=v_publication.id for update;
  if not found or v_certificate.status<>'certified' or v_certificate.scope_kind<>'fixture' or v_certificate.requested_fixture_id is null then
    raise exception 'Fotografia voti provider rifiutata [score.scope_not_certified].';
  end if;
  select fixture_row.* into v_fixture from public.provider_fixtures fixture_row
  where fixture_row.provider=v_run.provider and fixture_row.provider_fixture_id=v_certificate.requested_fixture_id for update;
  if not found or v_fixture.matchday_id is null then raise exception 'Fotografia voti provider rifiutata [score.fixture_not_ready].'; end if;

  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('provider-fixture-scores:'||v_run.provider||':'||v_certificate.requested_fixture_id)::bigint);

  select
    count(*)::integer,
    count(*) filter(where stage_athlete.provider_team_id=v_fixture.home_team_provider_id)::integer,
    count(*) filter(where stage_athlete.provider_team_id=v_fixture.away_team_provider_id)::integer,
    count(*) filter(where stage_athlete.provider_team_id is null or stage_athlete.provider_team_id not in (v_fixture.home_team_provider_id,v_fixture.away_team_provider_id))::integer,
    count(*) filter(where stage_score.is_final)::integer
  into v_score_count,v_home_count,v_away_count,v_unknown_team_count,v_final_count
  from public.provider_sync_stage_scores stage_score
  join public.provider_sync_stage_athletes stage_athlete
    on stage_athlete.publication_id=stage_score.publication_id and stage_athlete.athlete_id=stage_score.athlete_id
  where stage_score.publication_id=v_publication.id
    and stage_score.provider_fixture_id=v_certificate.requested_fixture_id
    and stage_score.matchday_id=v_fixture.matchday_id;

  v_fixture_final:=upper(trim(v_fixture.status)) in ('FT','AET','PEN');
  if v_score_count<=0 then raise exception 'Voti provider non validi [score.empty_snapshot]: nessun voto ricevuto.'; end if;
  if v_score_count<>v_certificate.observed_score_count or v_score_count<>v_publication.staged_primary_record_count then
    raise exception 'Voti provider non validi [score.count_mismatch]: staging %, certificato %, pubblicazione %.',v_score_count,v_certificate.observed_score_count,v_publication.staged_primary_record_count;
  end if;
  if v_unknown_team_count>0 then raise exception 'Voti provider non validi [score.team_out_of_fixture]: % righe fuori dalle squadre della partita.',v_unknown_team_count; end if;
  if v_fixture_final and (v_home_count=0 or v_away_count=0) then
    raise exception 'Voti provider non validi [score.final_team_coverage]: la fotografia finale deve includere entrambe le squadre.';
  end if;
  if v_fixture_final and v_final_count<>v_score_count then raise exception 'Voti provider non validi [score.final_flag_mismatch].'; end if;
  if not v_fixture_final and v_final_count<>0 then raise exception 'Voti provider non validi [score.provisional_flag_mismatch].'; end if;

  select head_row.* into v_head from public.provider_fixture_score_heads head_row
  where head_row.provider=v_run.provider and head_row.provider_fixture_id=v_certificate.requested_fixture_id for update;
  if found and v_head.is_final and not v_fixture_final then
    raise exception 'Voti provider non validi [score.final_regression]: una fotografia finale non può tornare provvisoria.';
  end if;
  if found and v_head.is_final and v_fixture_final and v_head.current_score_count>0 and v_score_count*2<v_head.current_score_count then
    raise exception 'Voti provider non validi [score.coverage_drop]: ricevuti %, correnti %.',v_score_count,v_head.current_score_count;
  end if;

  return jsonb_build_object(
    'applicable',true,'fixtureId',v_certificate.requested_fixture_id,'matchdayId',v_fixture.matchday_id,
    'fixtureStatus',v_fixture.status,'candidateFinal',v_fixture_final,'scoreCount',v_score_count,
    'homeScoreCount',v_home_count,'awayScoreCount',v_away_count,'headId',v_head.id,
    'headFinal',v_head.is_final,'headScoreCount',v_head.current_score_count,'headGeneration',v_head.generation
  );
end;
$function$;
revoke all on function public.provider_fixture_score_snapshot_decision_v1(uuid,uuid) from public,anon,authenticated,service_role;

create or replace function public.prepare_provider_fixture_score_reconciliation_v1(p_run_id uuid,p_lease_token uuid)
returns jsonb language plpgsql security definer set search_path='' as $function$
declare
  v_decision jsonb;
  v_run public.provider_sync_runs%rowtype;
  v_publication public.provider_sync_publications%rowtype;
  v_fixture public.provider_fixtures%rowtype;
  v_reconciliation public.provider_fixture_score_reconciliations%rowtype;
  v_member_count integer:=0;
begin
  v_decision:=public.provider_fixture_score_snapshot_decision_v1(p_run_id,p_lease_token);
  if not coalesce((v_decision->>'applicable')::boolean,false) then return jsonb_build_object('fixtureScoreReconciliation',false); end if;
  select run_row.* into v_run from public.provider_sync_runs run_row where run_row.id=p_run_id for update;
  select publication_row.* into v_publication from public.provider_sync_publications publication_row where publication_row.run_id=p_run_id for update;
  select fixture_row.* into v_fixture from public.provider_fixtures fixture_row
  where fixture_row.provider=v_run.provider and fixture_row.provider_fixture_id=(v_decision->>'fixtureId') for update;

  insert into public.provider_fixture_score_reconciliations(
    head_id,publication_id,run_id,recovery_request_id,league_id,provider,provider_fixture_id,
    matchday_id,fixture_status,candidate_final,status,observed_score_count,home_score_count,
    away_score_count,reason_code,summary,reconciliation_fingerprint
  ) values (
    nullif(v_decision->>'headId','')::uuid,v_publication.id,v_run.id,v_publication.recovery_request_id,
    v_publication.league_id,v_run.provider,v_decision->>'fixtureId',v_fixture.matchday_id,v_fixture.status,
    (v_decision->>'candidateFinal')::boolean,'collecting',(v_decision->>'scoreCount')::integer,
    (v_decision->>'homeScoreCount')::integer,(v_decision->>'awayScoreCount')::integer,'score.collecting',
    format('Fotografia voti partita %s pronta: %s voti, stato %s.',v_decision->>'fixtureId',v_decision->>'scoreCount',v_fixture.status),
    pg_catalog.md5(v_publication.id::text||E'\n'||v_run.id::text||E'\n'||v_run.provider||E'\n'||(v_decision->>'fixtureId')||E'\n'||(v_decision->>'scoreCount'))
  ) on conflict(publication_id) do nothing;

  select reconciliation_row.* into v_reconciliation from public.provider_fixture_score_reconciliations reconciliation_row
  where reconciliation_row.publication_id=v_publication.id for update;
  if not found then raise exception 'Preparazione voti provider fallita [score.reconciliation_missing].'; end if;
  if v_reconciliation.status='applied' then
    return jsonb_build_object('fixtureScoreReconciliation',true,'fixtureScoreStatus','applied','fixtureScoreReconciliationId',v_reconciliation.id);
  end if;

  insert into public.provider_fixture_score_members(reconciliation_id,player_key_fingerprint,team_side,has_rating,member_fingerprint)
  select
    v_reconciliation.id,
    pg_catalog.md5(stage_athlete.provider||E'\n'||stage_athlete.provider_player_id),
    case when stage_athlete.provider_team_id=v_fixture.home_team_provider_id then 'home' else 'away' end,
    stage_score.provider_rating is not null,
    pg_catalog.md5(
      stage_athlete.provider||E'\n'||stage_athlete.provider_player_id||E'\n'
      ||case when stage_athlete.provider_team_id=v_fixture.home_team_provider_id then 'home' else 'away' end||E'\n'
      ||coalesce(stage_score.provider_rating::text,'null')||E'\n'||coalesce(stage_score.fantasy_score::text,'null')||E'\n'
      ||stage_score.bonuses::text||E'\n'||stage_score.maluses::text||E'\n'||stage_score.is_final::text
    )
  from public.provider_sync_stage_scores stage_score
  join public.provider_sync_stage_athletes stage_athlete
    on stage_athlete.publication_id=stage_score.publication_id and stage_athlete.athlete_id=stage_score.athlete_id
  where stage_score.publication_id=v_publication.id
  on conflict(reconciliation_id,player_key_fingerprint) do nothing;

  select count(*)::integer into v_member_count from public.provider_fixture_score_members member_row
  where member_row.reconciliation_id=v_reconciliation.id;
  if v_member_count<>v_reconciliation.observed_score_count then
    raise exception 'Preparazione voti provider rifiutata [score.member_count_mismatch]: membri %, attesi %.',v_member_count,v_reconciliation.observed_score_count;
  end if;

  return jsonb_build_object(
    'fixtureScoreReconciliation',true,'fixtureScoreStatus','collecting',
    'fixtureScoreReconciliationId',v_reconciliation.id,'fixtureScoreFixtureId',v_reconciliation.provider_fixture_id,
    'fixtureScoreCount',v_reconciliation.observed_score_count,'fixtureScoreFinal',v_reconciliation.candidate_final
  );
end;
$function$;
revoke all on function public.prepare_provider_fixture_score_reconciliation_v1(uuid,uuid) from public,anon,authenticated,service_role;

create or replace function public.enforce_provider_fixture_score_snapshot_v1()
returns trigger language plpgsql security definer set search_path='' as $function$
declare
  v_fixture_old text;
  v_fixture_new text;
  v_provider_old text;
  v_provider_new text;
  v_reconciliation_id uuid;
  v_protected boolean:=false;
  v_allowed boolean:=false;
begin
  if tg_op='INSERT' then
    v_fixture_new:=new.provider_fixture_id;
    select athlete_row.provider into v_provider_new
    from public.athletes athlete_row where athlete_row.id=new.athlete_id;
  elsif tg_op='DELETE' then
    v_fixture_old:=old.provider_fixture_id;
    select athlete_row.provider into v_provider_old
    from public.athletes athlete_row where athlete_row.id=old.athlete_id;
  else
    v_fixture_old:=old.provider_fixture_id;
    v_fixture_new:=new.provider_fixture_id;
    select athlete_row.provider into v_provider_old
    from public.athletes athlete_row where athlete_row.id=old.athlete_id;
    select athlete_row.provider into v_provider_new
    from public.athletes athlete_row where athlete_row.id=new.athlete_id;
  end if;

  select exists(
    select 1 from public.provider_fixtures fixture_row
    where (v_fixture_old is not null and fixture_row.provider=v_provider_old and fixture_row.provider_fixture_id=v_fixture_old)
       or (v_fixture_new is not null and fixture_row.provider=v_provider_new and fixture_row.provider_fixture_id=v_fixture_new)
  ) into v_protected;

  if not v_protected then
    if tg_op='DELETE' then return old; end if;
    return new;
  end if;

  begin
    v_reconciliation_id:=nullif(current_setting('leghevo.provider_fixture_score_reconciliation_id',true),'')::uuid;
  exception when others then
    v_reconciliation_id:=null;
  end;

  if v_reconciliation_id is not null then
    select exists(
      select 1 from public.provider_fixture_score_reconciliations reconciliation_row
      where reconciliation_row.id=v_reconciliation_id
        and reconciliation_row.status='collecting'
        and (v_provider_old is null or reconciliation_row.provider=v_provider_old)
        and (v_provider_new is null or reconciliation_row.provider=v_provider_new)
        and (v_fixture_old is null or reconciliation_row.provider_fixture_id=v_fixture_old)
        and (v_fixture_new is null or reconciliation_row.provider_fixture_id=v_fixture_new)
    ) into v_allowed;
  end if;
  if not v_allowed then
    raise exception 'Scrittura voti provider rifiutata [score.snapshot_required]: usare la riconciliazione atomica della partita.';
  end if;
  if tg_op='DELETE' then return old; end if;
  return new;
end;
$function$;
revoke all on function public.enforce_provider_fixture_score_snapshot_v1() from public,anon,authenticated;
drop trigger if exists provider_fixture_score_snapshot_guard on public.player_match_scores;
create trigger provider_fixture_score_snapshot_guard before insert or update or delete on public.player_match_scores
for each row execute function public.enforce_provider_fixture_score_snapshot_v1();
alter table public.player_match_scores enable always trigger provider_fixture_score_snapshot_guard;

create or replace function public.apply_provider_fixture_score_on_publication_v1()
returns trigger language plpgsql security definer set search_path='' as $function$
declare
  v_reconciliation public.provider_fixture_score_reconciliations%rowtype;
  v_head public.provider_fixture_score_heads%rowtype;
  v_present integer:=0;
  v_current integer:=0;
  v_retired integer:=0;
  v_restored integer:=0;
  v_generation bigint:=1;
begin
  if new.status<>'published' or new.status is not distinct from old.status then return new; end if;
  select reconciliation_row.* into v_reconciliation from public.provider_fixture_score_reconciliations reconciliation_row
  where reconciliation_row.publication_id=new.id and reconciliation_row.status='collecting' for update;
  if not found then return new; end if;

  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('provider-fixture-scores:'||v_reconciliation.provider||':'||v_reconciliation.provider_fixture_id)::bigint);
  perform pg_catalog.set_config('leghevo.provider_fixture_score_reconciliation_id',v_reconciliation.id::text,true);

  select count(*)::integer into v_present
  from public.provider_fixture_score_members member_row
  join public.athletes athlete_row
    on athlete_row.provider=v_reconciliation.provider
   and pg_catalog.md5(athlete_row.provider||E'\n'||athlete_row.provider_player_id)=member_row.player_key_fingerprint
  join public.player_match_scores score_row
    on score_row.athlete_id=athlete_row.id
   and score_row.matchday_id=v_reconciliation.matchday_id
   and score_row.provider_fixture_id=v_reconciliation.provider_fixture_id
  where member_row.reconciliation_id=v_reconciliation.id
    and athlete_row.provider=v_reconciliation.provider;
  if v_present<>v_reconciliation.observed_score_count then
    raise exception 'Riconciliazione voti provider rifiutata [score.live_resolution_mismatch]: risolti %, attesi %.',v_present,v_reconciliation.observed_score_count;
  end if;

  with restored as (
    update public.player_match_scores score_row
    set provider_score_state='current',provider_score_reconciliation_id=v_reconciliation.id,
        provider_score_reconciled_at=now()
    from public.athletes athlete_row,public.provider_fixture_score_members member_row
    where athlete_row.id=score_row.athlete_id
      and athlete_row.provider=v_reconciliation.provider
      and member_row.reconciliation_id=v_reconciliation.id
      and member_row.player_key_fingerprint=pg_catalog.md5(athlete_row.provider||E'\n'||athlete_row.provider_player_id)
      and score_row.matchday_id=v_reconciliation.matchday_id
      and score_row.provider_fixture_id=v_reconciliation.provider_fixture_id
      and score_row.provider_score_state='retired'
    returning score_row.id
  ) select count(*)::integer into v_restored from restored;

  update public.player_match_scores score_row
  set provider_score_state='current',provider_score_reconciliation_id=v_reconciliation.id,
      provider_score_reconciled_at=now()
  from public.athletes athlete_row,public.provider_fixture_score_members member_row
  where athlete_row.id=score_row.athlete_id
    and athlete_row.provider=v_reconciliation.provider
    and member_row.reconciliation_id=v_reconciliation.id
    and member_row.player_key_fingerprint=pg_catalog.md5(athlete_row.provider||E'\n'||athlete_row.provider_player_id)
    and score_row.matchday_id=v_reconciliation.matchday_id
    and score_row.provider_fixture_id=v_reconciliation.provider_fixture_id;

  if v_reconciliation.candidate_final then
    with retired as (
      update public.player_match_scores score_row
      set provider_rating=null,fantasy_score=null,bonuses='{}'::jsonb,maluses='{}'::jsonb,
          is_final=true,provider_score_state='retired',provider_score_reconciliation_id=v_reconciliation.id,
          provider_score_reconciled_at=now(),updated_at=now()
      from public.athletes athlete_row
      where athlete_row.id=score_row.athlete_id
        and athlete_row.provider=v_reconciliation.provider
        and score_row.provider_fixture_id=v_reconciliation.provider_fixture_id
        and score_row.matchday_id=v_reconciliation.matchday_id
        and score_row.provider_score_state='current'
        and not exists(
          select 1 from public.provider_fixture_score_members member_row
          where member_row.reconciliation_id=v_reconciliation.id
            and member_row.player_key_fingerprint=pg_catalog.md5(athlete_row.provider||E'\n'||athlete_row.provider_player_id)
        )
      returning score_row.id
    ) select count(*)::integer into v_retired from retired;
  end if;

  select count(*)::integer into v_current
  from public.player_match_scores score_row
  join public.athletes athlete_row on athlete_row.id=score_row.athlete_id
  where athlete_row.provider=v_reconciliation.provider
    and score_row.provider_fixture_id=v_reconciliation.provider_fixture_id
    and score_row.matchday_id=v_reconciliation.matchday_id
    and score_row.provider_score_state='current';
  if v_reconciliation.candidate_final and v_current<>v_reconciliation.observed_score_count then
    raise exception 'Riconciliazione voti provider rifiutata [score.current_count_mismatch]: correnti %, attesi %.',v_current,v_reconciliation.observed_score_count;
  end if;

  select head_row.* into v_head from public.provider_fixture_score_heads head_row
  where head_row.provider=v_reconciliation.provider and head_row.provider_fixture_id=v_reconciliation.provider_fixture_id for update;
  if found and v_head.is_final and not v_reconciliation.candidate_final then
    raise exception 'Riconciliazione voti provider rifiutata [score.final_regression_after_lock].';
  end if;
  if found then v_generation:=v_head.generation+1; end if;

  insert into public.provider_fixture_score_heads(
    provider,provider_fixture_id,matchday_id,fixture_status,is_final,latest_run_id,
    latest_publication_id,latest_reconciliation_id,current_score_count,generation,summary
  ) values (
    v_reconciliation.provider,v_reconciliation.provider_fixture_id,v_reconciliation.matchday_id,
    v_reconciliation.fixture_status,v_reconciliation.candidate_final,v_reconciliation.run_id,
    v_reconciliation.publication_id,v_reconciliation.id,v_current,v_generation,
    format('Fotografia voti partita %s riconciliata: %s correnti, %s ritirati, stato %s.',v_reconciliation.provider_fixture_id,v_current,v_retired,v_reconciliation.fixture_status)
  ) on conflict(provider,provider_fixture_id) do update set
    matchday_id=excluded.matchday_id,fixture_status=excluded.fixture_status,is_final=excluded.is_final,
    latest_run_id=excluded.latest_run_id,latest_publication_id=excluded.latest_publication_id,
    latest_reconciliation_id=excluded.latest_reconciliation_id,current_score_count=excluded.current_score_count,
    generation=excluded.generation,summary=excluded.summary
  returning * into v_head;

  update public.provider_fixture_score_reconciliations reconciliation_row
  set head_id=v_head.id,status='applied',retired_score_count=v_retired,restored_score_count=v_restored,
      generation=v_head.generation,reason_code='score.applied',
      summary=format('Fotografia voti provider applicata senza cancellazioni: %s presenti, %s ritirati, %s ripristinati.',v_reconciliation.observed_score_count,v_retired,v_restored)
  where reconciliation_row.id=v_reconciliation.id;

  perform pg_catalog.set_config('leghevo.provider_fixture_score_reconciliation_id','',true);
  return new;
end;
$function$;
revoke all on function public.apply_provider_fixture_score_on_publication_v1() from public,anon,authenticated;
drop trigger if exists provider_fixture_score_publication_reconcile on public.provider_sync_publications;
create trigger provider_fixture_score_publication_reconcile after update of status on public.provider_sync_publications
for each row execute function public.apply_provider_fixture_score_on_publication_v1();
alter table public.provider_sync_publications enable always trigger provider_fixture_score_publication_reconcile;



-- Le metriche qualità ignorano le righe ritirate logicamente: restano
-- disponibili per audit ma non rappresentano più un voto corrente.
create or replace function public.build_provider_data_quality_metrics_v1(
  p_run_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_run public.provider_sync_runs%rowtype;
  v_fixture_id text;
  v_fixture_count integer := 0;
  v_linked_fixture_count integer := 0;
  v_final_fixture_count integer := 0;
  v_live_fixture_count integer := 0;
  v_final_without_goals_count integer := 0;
  v_same_team_count integer := 0;
  v_score_count integer := 0;
  v_final_score_count integer := 0;
  v_invalid_score_count integer := 0;
  v_nonfinal_score_on_final_fixture_count integer := 0;
  v_active_athlete_count integer := 0;
  v_missing_role_count integer := 0;
  v_records_mismatch integer := 0;
  v_anomaly_count integer := 0;
  v_latest_fixture_at timestamptz;
  v_latest_score_at timestamptz;
  v_latest_data_at timestamptz;
  v_status text := 'healthy';
begin
  select run_row.*
  into v_run
  from public.provider_sync_runs run_row
  where run_row.id = p_run_id;

  if not found then
    raise exception 'Run provider non trovato.';
  end if;

  if v_run.status <> 'completed' then
    raise exception 'La qualità può essere certificata solo per un run completato.';
  end if;

  if v_run.sync_type = 'sync-fixtures' then
    select
      count(*)::integer,
      count(*) filter (where fixture.matchday_id is not null)::integer,
      count(*) filter (
        where fixture.status in ('FT', 'AET', 'PEN')
      )::integer,
      count(*) filter (
        where fixture.status in ('1H', 'HT', '2H', 'ET', 'BT', 'P', 'LIVE')
      )::integer,
      count(*) filter (
        where fixture.status in ('FT', 'AET', 'PEN')
          and (fixture.home_goals is null or fixture.away_goals is null)
      )::integer,
      count(*) filter (
        where fixture.home_team_provider_id = fixture.away_team_provider_id
      )::integer,
      max(fixture.updated_at)
    into
      v_fixture_count,
      v_linked_fixture_count,
      v_final_fixture_count,
      v_live_fixture_count,
      v_final_without_goals_count,
      v_same_team_count,
      v_latest_fixture_at
    from public.provider_fixtures fixture
    where fixture.provider = v_run.provider
      and fixture.season = coalesce(v_run.requested_for ->> 'season', fixture.season)
      and (
        not (v_run.requested_for ? 'date')
        or (fixture.kickoff_at at time zone 'UTC')::date
          = (v_run.requested_for ->> 'date')::date
      );

    v_records_mismatch := abs(
      coalesce(v_run.records_processed, 0) - coalesce(v_fixture_count, 0)
    );
    v_anomaly_count :=
      greatest(v_fixture_count - v_linked_fixture_count, 0)
      + v_final_without_goals_count
      + v_same_team_count
      + v_records_mismatch;
    v_latest_data_at := v_latest_fixture_at;
  elsif v_run.sync_type = 'sync-fixture-players' then
    v_fixture_id := v_run.requested_for ->> 'fixtureId';

    select
      count(*)::integer,
      count(*) filter (where score.is_final)::integer,
      count(*) filter (
        where (score.provider_rating is not null
          and (score.provider_rating < 0 or score.provider_rating > 10))
          or (score.fantasy_score is not null
          and (score.fantasy_score < -10 or score.fantasy_score > 30))
      )::integer,
      max(score.updated_at)
    into
      v_score_count,
      v_final_score_count,
      v_invalid_score_count,
      v_latest_score_at
    from public.player_match_scores score
    where score.provider_fixture_id = v_fixture_id
      and score.provider_score_state = 'current';

    select count(*)::integer
    into v_nonfinal_score_on_final_fixture_count
    from public.player_match_scores score
    join public.provider_fixtures fixture
      on fixture.provider = v_run.provider
      and fixture.provider_fixture_id = score.provider_fixture_id
    where score.provider_fixture_id = v_fixture_id
      and fixture.status in ('FT', 'AET', 'PEN')
      and score.provider_score_state = 'current'
      and not score.is_final;

    select max(fixture.updated_at)
    into v_latest_fixture_at
    from public.provider_fixtures fixture
    where fixture.provider = v_run.provider
      and fixture.provider_fixture_id = v_fixture_id;

    v_records_mismatch := abs(
      coalesce(v_run.records_processed, 0) - coalesce(v_score_count, 0)
    );
    v_anomaly_count := v_invalid_score_count
      + v_nonfinal_score_on_final_fixture_count
      + v_records_mismatch
      + case when v_latest_fixture_at is null then 1 else 0 end;
    v_latest_data_at := greatest(v_latest_fixture_at, v_latest_score_at);
  elsif v_run.sync_type = 'sync-season-players' then
    select count(*)::integer
    into v_active_athlete_count
    from public.athletes athlete
    where athlete.provider = v_run.provider
      and athlete.active;

    select count(*)::integer
    into v_missing_role_count
    from public.athletes athlete
    where athlete.provider = v_run.provider
      and athlete.active
      and (
        not exists (
          select 1
          from public.athlete_roles role_row
          where role_row.athlete_id = athlete.id
            and role_row.mode::text = 'classic'
        )
        or not exists (
          select 1
          from public.athlete_roles role_row
          where role_row.athlete_id = athlete.id
            and role_row.mode::text = 'mantra'
        )
      );

    select max(athlete.updated_at)
    into v_latest_data_at
    from public.athletes athlete
    where athlete.provider = v_run.provider;

    v_anomaly_count := v_missing_role_count
      + case when coalesce(v_run.records_processed, 0) = 0 then 1 else 0 end;
  else
    v_status := 'idle';
  end if;

  if v_status <> 'idle' and v_anomaly_count > 0 then
    v_status := 'attention';
  end if;

  return jsonb_build_object(
    'provider', v_run.provider,
    'action', v_run.sync_type,
    'status', v_status,
    'anomalyCount', v_anomaly_count,
    'recordsProcessed', coalesce(v_run.records_processed, 0),
    'recordsMismatch', v_records_mismatch,
    'fixtureCount', v_fixture_count,
    'linkedFixtureCount', v_linked_fixture_count,
    'finalFixtureCount', v_final_fixture_count,
    'liveFixtureCount', v_live_fixture_count,
    'finalWithoutGoalsCount', v_final_without_goals_count,
    'sameTeamCount', v_same_team_count,
    'scoreCount', v_score_count,
    'finalScoreCount', v_final_score_count,
    'invalidScoreCount', v_invalid_score_count,
    'nonFinalScoreOnFinalFixtureCount',
      v_nonfinal_score_on_final_fixture_count,
    'activeAthleteCount', v_active_athlete_count,
    'missingRoleCount', v_missing_role_count,
    'latestDataAt', v_latest_data_at
  );
end;
$$;

revoke all on function public.build_provider_data_quality_metrics_v1(uuid)
from public, anon, authenticated;
grant execute on function public.build_provider_data_quality_metrics_v1(uuid)
to service_role;

create or replace function public.get_league_provider_data_quality_v1(
  p_league_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_owner_id uuid;
  v_matchday public.matchdays%rowtype;
  v_fixture_count integer := 0;
  v_final_fixture_count integer := 0;
  v_live_fixture_count integer := 0;
  v_score_count integer := 0;
  v_final_score_count integer := 0;
  v_invalid_score_count integer := 0;
  v_final_fixture_without_score_count integer := 0;
  v_schedule_mismatch_count integer := 0;
  v_latest_fixture_at timestamptz;
  v_latest_score_at timestamptz;
  v_stale boolean := false;
  v_status text := 'idle';
  v_anomaly_count integer := 0;
  v_latest_snapshot jsonb;
  v_latest_completed_run_id uuid;
  v_snapshot_missing_count integer := 0;
begin
  if auth.uid() is null then
    raise exception 'Devi effettuare l''accesso.';
  end if;

  select league.owner_id
  into v_owner_id
  from public.leagues league
  where league.id = p_league_id;

  if not found then
    raise exception 'Lega non trovata.';
  end if;

  if v_owner_id <> auth.uid()
    and not public.is_league_admin(p_league_id) then
    raise exception 'Il monitor qualità provider è riservato alla Direzione.';
  end if;

  select matchday.*
  into v_matchday
  from public.matchdays matchday
  where exists (
    select 1
    from public.fantasy_fixtures fixture
    where fixture.league_id = p_league_id
      and fixture.matchday_id = matchday.id
  )
  order by
    case when exists (
      select 1
      from public.fantasy_fixtures fixture
      where fixture.league_id = p_league_id
        and fixture.matchday_id = matchday.id
        and fixture.finalized_at is null
    ) then 0 else 1 end,
    case when matchday.ends_at is null or matchday.ends_at >= now()
      then 0 else 1 end,
    case when exists (
      select 1
      from public.fantasy_fixtures fixture
      where fixture.league_id = p_league_id
        and fixture.matchday_id = matchday.id
        and fixture.finalized_at is null
    ) then matchday.number end asc,
    matchday.number desc
  limit 1;

  select run_row.id
  into v_latest_completed_run_id
  from public.provider_sync_runs run_row
  where run_row.provider = 'api-football'
    and run_row.status = 'completed'
  order by run_row.finished_at desc nulls last, run_row.started_at desc
  limit 1;

  select jsonb_build_object(
    'runId', snapshot.run_id,
    'action', snapshot.sync_type,
    'status', snapshot.status,
    'anomalyCount', snapshot.anomaly_count,
    'latestSourceAt', snapshot.latest_source_at,
    'createdAt', snapshot.created_at
  )
  into v_latest_snapshot
  from public.provider_data_quality_snapshots snapshot
  where snapshot.provider = 'api-football'
  order by snapshot.created_at desc
  limit 1;

  if v_latest_completed_run_id is not null
    and (v_latest_snapshot is null
      or nullif(v_latest_snapshot ->> 'runId', '')::uuid
        is distinct from v_latest_completed_run_id) then
    v_snapshot_missing_count := 1;
  end if;

  if v_matchday.id is not null then
    select
      count(*)::integer,
      count(*) filter (
        where provider_fixture.status in ('FT', 'AET', 'PEN')
      )::integer,
      count(*) filter (
        where provider_fixture.status in (
          '1H', 'HT', '2H', 'ET', 'BT', 'P', 'LIVE'
        )
      )::integer,
      max(provider_fixture.updated_at)
    into
      v_fixture_count,
      v_final_fixture_count,
      v_live_fixture_count,
      v_latest_fixture_at
    from public.provider_fixtures provider_fixture
    where provider_fixture.provider = 'api-football'
      and provider_fixture.matchday_id = v_matchday.id;

    select
      count(*)::integer,
      count(*) filter (where score.is_final)::integer,
      count(*) filter (
        where (score.provider_rating is not null
          and (score.provider_rating < 0 or score.provider_rating > 10))
          or (score.fantasy_score is not null
          and (score.fantasy_score < -10 or score.fantasy_score > 30))
      )::integer,
      max(score.updated_at)
    into
      v_score_count,
      v_final_score_count,
      v_invalid_score_count,
      v_latest_score_at
    from public.player_match_scores score
    where score.matchday_id = v_matchday.id
      and score.provider_score_state = 'current';

    select count(*)::integer
    into v_final_fixture_without_score_count
    from public.provider_fixtures provider_fixture
    where provider_fixture.provider = 'api-football'
      and provider_fixture.matchday_id = v_matchday.id
      and provider_fixture.status in ('FT', 'AET', 'PEN')
      and not exists (
        select 1
        from public.player_match_scores score
        where score.matchday_id = v_matchday.id
          and score.provider_fixture_id = provider_fixture.provider_fixture_id
          and score.is_final
          and score.provider_score_state = 'current'
      );

    v_schedule_mismatch_count :=
      case when coalesce(v_matchday.provider_fixture_count, 0)
        <> v_fixture_count then 1 else 0 end
      + case when coalesce(v_matchday.provider_final_fixture_count, 0)
        <> v_final_fixture_count then 1 else 0 end;

    v_stale := (
      v_live_fixture_count > 0
      and (
        v_latest_score_at is null
        or v_latest_score_at < now() - interval '3 minutes'
      )
    ) or (
      v_fixture_count > v_final_fixture_count
      and v_latest_fixture_at is not null
      and v_latest_fixture_at < now() - interval '20 minutes'
    );

    v_anomaly_count := v_invalid_score_count
      + v_final_fixture_without_score_count
      + v_schedule_mismatch_count
      + v_snapshot_missing_count
      + case when v_stale then 1 else 0 end;

    if v_fixture_count = 0 and v_matchday.schedule_source <> 'provider' then
      v_status := 'idle';
    elsif v_anomaly_count > 0
      or coalesce(v_latest_snapshot ->> 'status', 'healthy') = 'attention' then
      v_status := 'attention';
    else
      v_status := 'healthy';
    end if;
  elsif v_latest_snapshot is not null then
    v_status := coalesce(v_latest_snapshot ->> 'status', 'idle');
    v_anomaly_count := greatest(
      coalesce((v_latest_snapshot ->> 'anomalyCount')::integer, 0),
      0
    ) + v_snapshot_missing_count;
    if v_snapshot_missing_count > 0 then
      v_status := 'attention';
    end if;
  end if;

  return jsonb_build_object(
    'protected', true,
    'status', v_status,
    'healthy', v_status <> 'attention',
    'stale', v_stale,
    'anomalyCount', v_anomaly_count,
    'matchdayId', v_matchday.id,
    'matchdayNumber', v_matchday.number,
    'scheduleSource', v_matchday.schedule_source,
    'fixtureCount', v_fixture_count,
    'finalFixtureCount', v_final_fixture_count,
    'liveFixtureCount', v_live_fixture_count,
    'scoreCount', v_score_count,
    'finalScoreCount', v_final_score_count,
    'invalidScoreCount', v_invalid_score_count,
    'finalFixtureWithoutScoreCount', v_final_fixture_without_score_count,
    'scheduleMismatchCount', v_schedule_mismatch_count,
    'snapshotMissingCount', v_snapshot_missing_count,
    'latestFixtureAt', v_latest_fixture_at,
    'latestScoreAt', v_latest_score_at,
    'latestSnapshot', v_latest_snapshot
  );
end;
$$;

revoke all on function public.get_league_provider_data_quality_v1(uuid)
from public, anon, authenticated;
grant execute on function public.get_league_provider_data_quality_v1(uuid)
to authenticated;

create or replace function public.get_provider_fixture_score_result_v1(p_run_id uuid)
returns jsonb language sql stable security definer set search_path='' as $function$
  select coalesce((
    select jsonb_build_object(
      'fixtureScoreReconciliation',true,'fixtureScoreStatus',reconciliation_row.status,
      'fixtureScoreReconciliationId',reconciliation_row.id,'fixtureScoreFixtureId',reconciliation_row.provider_fixture_id,
      'fixtureScoreFinal',reconciliation_row.candidate_final,'fixtureScoreCount',reconciliation_row.observed_score_count,
      'fixtureScoreRetiredCount',reconciliation_row.retired_score_count,'fixtureScoreRestoredCount',reconciliation_row.restored_score_count,
      'fixtureScoreGeneration',reconciliation_row.generation
    ) from public.provider_fixture_score_reconciliations reconciliation_row where reconciliation_row.run_id=p_run_id
  ),jsonb_build_object('fixtureScoreReconciliation',false));
$function$;
revoke all on function public.get_provider_fixture_score_result_v1(uuid) from public,anon,authenticated,service_role;

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

create or replace function public.finish_provider_sync_run_guarded_v8(
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
  v_score_prepare jsonb:='{}'::jsonb;
  v_score_result jsonb:='{}'::jsonb;
  v_result jsonb;
  v_watermark jsonb:='{}'::jsonb;
  v_sync_type text;
begin
  if v_status not in ('completed','failed') then raise exception 'Stato finale del run provider non valido.'; end if;
  if v_status='failed' then
    v_result:=public.finish_provider_sync_run_atomic_core_v1(p_run_id,p_status,p_records_processed,p_error_message,p_expected_revision,p_lease_token);
    return v_result||jsonb_build_object('monotonicPublication',true,'publicationSuperseded',false,'catalogReconciliation',false,'catalogSuperseded',false,'fixtureScoreReconciliation',false);
  end if;

  select run_row.sync_type into v_sync_type from public.provider_sync_runs run_row where run_row.id=p_run_id;
  if not found then raise exception 'Run provider non trovato durante la chiusura v8.'; end if;
  v_decision:=public.provider_sync_scope_watermark_decision_v1(p_run_id,p_lease_token);
  if coalesce((v_decision->>'stale')::boolean,false) then
    return public.discard_stale_provider_sync_publication_v1(p_run_id,p_records_processed,p_expected_revision,p_lease_token,v_decision)
      ||jsonb_build_object('catalogReconciliation',false,'catalogSuperseded',false,'fixtureScoreReconciliation',false);
  end if;
  v_scope:=public.certify_provider_sync_publication_scope_v1(p_run_id,p_lease_token);

  if v_sync_type='sync-season-players' then
    v_catalog_decision:=public.provider_player_catalog_decision_v1(p_run_id,p_lease_token);
    if coalesce((v_catalog_decision->>'superseded')::boolean,false) then
      return public.discard_superseded_provider_player_catalog_v1(p_run_id,p_records_processed,p_expected_revision,p_lease_token,v_catalog_decision)
        ||jsonb_build_object('fixtureScoreReconciliation',false);
    end if;
    v_catalog_prepare:=public.prepare_provider_player_catalog_reconciliation_v1(p_run_id,p_lease_token);
    perform pg_catalog.set_config('leghevo.provider_catalog_reconciliation_id',v_catalog_prepare->>'catalogReconciliationId',true);
  elsif v_sync_type='sync-fixture-players' then
    v_score_prepare:=public.prepare_provider_fixture_score_reconciliation_v1(p_run_id,p_lease_token);
    perform pg_catalog.set_config('leghevo.provider_fixture_score_reconciliation_id',v_score_prepare->>'fixtureScoreReconciliationId',true);
  end if;

  v_result:=public.finish_provider_sync_run_atomic_core_v1(p_run_id,p_status,p_records_processed,p_error_message,p_expected_revision,p_lease_token);
  perform pg_catalog.set_config('leghevo.provider_catalog_reconciliation_id','',true);
  perform pg_catalog.set_config('leghevo.provider_fixture_score_reconciliation_id','',true);
  v_watermark:=public.advance_provider_sync_scope_watermark_v1(p_run_id,p_records_processed,p_lease_token);
  v_catalog_result:=public.get_provider_player_catalog_result_v1(p_run_id);
  v_score_result:=public.get_provider_fixture_score_result_v1(p_run_id);
  return v_result||v_scope||v_watermark||v_catalog_prepare||v_catalog_result||v_score_prepare||v_score_result
    ||jsonb_build_object('semanticScopeBinding',true,'monotonicPublication',true,'publicationSuperseded',false);
end;
$function$;
revoke all on function public.finish_provider_sync_run_guarded_v8(uuid,text,integer,text,bigint,uuid) from public,anon,authenticated;
grant execute on function public.finish_provider_sync_run_guarded_v8(uuid,text,integer,text,bigint,uuid) to service_role;

create or replace function public.finish_provider_sync_run_guarded_v7(
  p_run_id uuid,p_status text,p_records_processed integer,p_error_message text default null,
  p_expected_revision bigint default null,p_lease_token uuid default null
)
returns jsonb language plpgsql security definer set search_path='' as $function$
begin
  -- provider_fixture_score_snapshot_decision_v1
  -- prepare_provider_fixture_score_reconciliation_v1
  return public.finish_provider_sync_run_guarded_v8(p_run_id,p_status,p_records_processed,p_error_message,p_expected_revision,p_lease_token);
end;
$function$;
revoke all on function public.finish_provider_sync_run_guarded_v7(uuid,text,integer,text,bigint,uuid) from public,anon,authenticated;
grant execute on function public.finish_provider_sync_run_guarded_v7(uuid,text,integer,text,bigint,uuid) to service_role;

create or replace function public.get_league_provider_fixture_score_center_v1(p_league_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $function$
declare
  v_owner_id uuid;
  v_collecting integer:=0;
  v_applied_24h integer:=0;
  v_final_24h integer:=0;
  v_retired_24h integer:=0;
  v_restored_24h integer:=0;
  v_total integer:=0;
  v_latest_at timestamptz;
  v_latest jsonb;
begin
  select league_row.owner_id into v_owner_id from public.leagues league_row where league_row.id=p_league_id;
  if not found then raise exception 'Lega non trovata per il controllo dei voti provider.'; end if;
  if auth.uid() is null or not(v_owner_id=auth.uid() or public.is_league_admin(p_league_id)) then
    raise exception 'Solo Presidente e Admin possono leggere la riconciliazione voti provider.';
  end if;
  select count(*)::integer,count(*) filter(where status='collecting')::integer,
    count(*) filter(where status='applied' and applied_at>=now()-interval '24 hours')::integer,
    count(*) filter(where status='applied' and candidate_final and applied_at>=now()-interval '24 hours')::integer,
    coalesce(sum(retired_score_count) filter(where applied_at>=now()-interval '24 hours'),0)::integer,
    coalesce(sum(restored_score_count) filter(where applied_at>=now()-interval '24 hours'),0)::integer,
    max(updated_at)
  into v_total,v_collecting,v_applied_24h,v_final_24h,v_retired_24h,v_restored_24h,v_latest_at
  from public.provider_fixture_score_reconciliations reconciliation_row
  where reconciliation_row.league_id=p_league_id or reconciliation_row.league_id is null;

  select jsonb_build_object(
    'id',reconciliation_row.id,'runId',reconciliation_row.run_id,'publicationId',reconciliation_row.publication_id,
    'requestId',reconciliation_row.recovery_request_id,'fixtureIdFingerprint',pg_catalog.md5(reconciliation_row.provider||E'\n'||reconciliation_row.provider_fixture_id),
    'fixtureStatus',reconciliation_row.fixture_status,'isFinal',reconciliation_row.candidate_final,'status',reconciliation_row.status,
    'observedScoreCount',reconciliation_row.observed_score_count,'homeScoreCount',reconciliation_row.home_score_count,
    'awayScoreCount',reconciliation_row.away_score_count,'retiredScoreCount',reconciliation_row.retired_score_count,
    'restoredScoreCount',reconciliation_row.restored_score_count,'generation',reconciliation_row.generation,
    'reasonCode',reconciliation_row.reason_code,'summary',reconciliation_row.summary,'updatedAt',reconciliation_row.updated_at
  ) into v_latest from public.provider_fixture_score_reconciliations reconciliation_row
  where reconciliation_row.league_id=p_league_id or reconciliation_row.league_id is null
  order by reconciliation_row.updated_at desc,reconciliation_row.id desc limit 1;

  return jsonb_build_object(
    'protected',true,'healthy',v_collecting=0,'authoritativeFixtureSnapshotActive',true,
    'finalToProvisionalRegressionBlocked',true,'missingFinalScoresSoftRetired',true,
    'physicalScoreDeletionDisabled',true,'twoTeamFinalCoverageRequired',true,
    'collectingCount',v_collecting,'appliedLast24h',v_applied_24h,'finalAppliedLast24h',v_final_24h,
    'retiredScoresLast24h',v_retired_24h,'restoredScoresLast24h',v_restored_24h,
    'totalReconciliationCount',v_total,'latestReconciliationAt',v_latest_at,'latest',v_latest
  );
end;
$function$;
revoke all on function public.get_league_provider_fixture_score_center_v1(uuid) from public,anon,service_role;
grant execute on function public.get_league_provider_fixture_score_center_v1(uuid) to authenticated;

create or replace function public.get_league_provider_sync_health_v17(p_league_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $function$
declare
  v_base jsonb;
  v_scores jsonb;
  v_healthy boolean;
  v_status text;
begin
  v_base:=public.get_league_provider_sync_health_v16(p_league_id);
  v_scores:=public.get_league_provider_fixture_score_center_v1(p_league_id);
  v_healthy:=coalesce((v_base->>'healthy')::boolean,false) and coalesce((v_scores->>'healthy')::boolean,false);
  v_status:=case when not v_healthy then 'attention' when coalesce(v_base->>'status','idle')='idle' then 'idle' else 'healthy' end;
  return v_base||jsonb_build_object(
    'protected',coalesce((v_base->>'protected')::boolean,false) and coalesce((v_scores->>'protected')::boolean,false),
    'healthy',v_healthy,'status',v_status,'fixtureScoreReconciliation',v_scores
  );
end;
$function$;
revoke all on function public.get_league_provider_sync_health_v17(uuid) from public,anon,service_role;
grant execute on function public.get_league_provider_sync_health_v17(uuid) to authenticated;

do $realtime$
begin
  if exists(select 1 from pg_catalog.pg_publication where pubname='supabase_realtime') then
    if not exists(select 1 from pg_catalog.pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='provider_fixture_score_heads') then
      alter publication supabase_realtime add table public.provider_fixture_score_heads;
    end if;
    if not exists(select 1 from pg_catalog.pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='provider_fixture_score_reconciliations') then
      alter publication supabase_realtime add table public.provider_fixture_score_reconciliations;
    end if;
    if not exists(select 1 from pg_catalog.pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='provider_fixture_score_events') then
      alter publication supabase_realtime add table public.provider_fixture_score_events;
    end if;
  end if;
end;
$realtime$;

create or replace function public.get_provider_fixture_score_reconciliation_integrity_v1()
returns jsonb language plpgsql stable security definer set search_path='' as $function$
declare
  v_predecessor jsonb;
  v_decision text;
  v_prepare text;
  v_apply text;
  v_guard text;
  v_finish_v8 text;
  v_finish_v7 text;
  v_retry text;
  v_quality_metrics text;
  v_quality_center text;
begin
  v_predecessor:=public.get_provider_player_catalog_reconciliation_integrity_v1();
  select pg_catalog.pg_get_functiondef('public.provider_fixture_score_snapshot_decision_v1(uuid,uuid)'::regprocedure) into v_decision;
  select pg_catalog.pg_get_functiondef('public.prepare_provider_fixture_score_reconciliation_v1(uuid,uuid)'::regprocedure) into v_prepare;
  select pg_catalog.pg_get_functiondef('public.apply_provider_fixture_score_on_publication_v1()'::regprocedure) into v_apply;
  select pg_catalog.pg_get_functiondef('public.enforce_provider_fixture_score_snapshot_v1()'::regprocedure) into v_guard;
  select pg_catalog.pg_get_functiondef('public.finish_provider_sync_run_guarded_v8(uuid,text,integer,text,bigint,uuid)'::regprocedure) into v_finish_v8;
  select pg_catalog.pg_get_functiondef('public.finish_provider_sync_run_guarded_v7(uuid,text,integer,text,bigint,uuid)'::regprocedure) into v_finish_v7;
  select pg_catalog.pg_get_functiondef('public.provider_recovery_retry_policy_v1(text,integer,text)'::regprocedure) into v_retry;
  select pg_catalog.pg_get_functiondef('public.build_provider_data_quality_metrics_v1(uuid)'::regprocedure) into v_quality_metrics;
  select pg_catalog.pg_get_functiondef('public.get_league_provider_data_quality_v1(uuid)'::regprocedure) into v_quality_center;
  return jsonb_build_object(
    'predecessor_ready',
      (select count(*) from jsonb_each(v_predecessor)) = 20
      and not exists (
        select 1
        from jsonb_each(v_predecessor) predecessor_check
        where predecessor_check.key <> 'finish_v7_ready'
          and (
            jsonb_typeof(predecessor_check.value) is distinct from 'boolean'
            or predecessor_check.value is distinct from 'true'::jsonb
          )
      )
      and jsonb_typeof(v_predecessor -> 'finish_v7_ready') = 'boolean'
      and (v_predecessor -> 'finish_v7_ready') = 'false'::jsonb
      and position('finish_provider_sync_run_guarded_v8' in lower(v_finish_v7)) > 0
      and position('provider_player_catalog_decision_v1' in lower(v_finish_v8)) > 0
      and position('prepare_provider_player_catalog_reconciliation_v1' in lower(v_finish_v8)) > 0
      and position('advance_provider_sync_scope_watermark_v1' in lower(v_finish_v8)) > 0
      and position('leghevo.provider_catalog_reconciliation_id' in lower(v_finish_v8)) > 0,
    'score_columns_ready',not exists(select 1 from (values('provider_score_state'),('provider_score_reconciliation_id'),('provider_score_reconciled_at')) c(column_name) where not exists(select 1 from information_schema.columns x where x.table_schema='public' and x.table_name='player_match_scores' and x.column_name=c.column_name)),
    'head_table_ready',to_regclass('public.provider_fixture_score_heads') is not null,
    'reconciliation_table_ready',to_regclass('public.provider_fixture_score_reconciliations') is not null,
    'member_table_ready',to_regclass('public.provider_fixture_score_members') is not null,
    'event_table_ready',to_regclass('public.provider_fixture_score_events') is not null,
    'constraints_ready',exists(select 1 from pg_catalog.pg_constraint where conrelid='public.player_match_scores'::regclass and conname='player_match_scores_provider_score_state_check') and exists(select 1 from pg_catalog.pg_constraint where conrelid='public.provider_fixture_score_reconciliations'::regclass and conname='provider_fixture_score_reconciliations_terminal_check'),
    'indexes_ready',to_regclass('public.provider_fixture_score_heads_latest_idx') is not null and to_regclass('public.player_match_scores_provider_state_idx') is not null,
    'rls_ready',(select relrowsecurity from pg_catalog.pg_class where oid='public.provider_fixture_score_heads'::regclass) and (select relrowsecurity from pg_catalog.pg_class where oid='public.provider_fixture_score_reconciliations'::regclass) and (select relrowsecurity from pg_catalog.pg_class where oid='public.provider_fixture_score_members'::regclass) and (select relrowsecurity from pg_catalog.pg_class where oid='public.provider_fixture_score_events'::regclass),
    'authenticated_write_blocked',not has_table_privilege('authenticated','public.provider_fixture_score_heads','INSERT') and not has_table_privilege('authenticated','public.provider_fixture_score_reconciliations','UPDATE') and not has_table_privilege('authenticated','public.provider_fixture_score_members','SELECT') and not has_table_privilege('authenticated','public.provider_fixture_score_events','DELETE'),
    'immutable_history_ready',exists(select 1 from pg_catalog.pg_trigger where tgrelid='public.provider_fixture_score_events'::regclass and tgname='provider_fixture_score_events_immutable' and tgenabled='A' and not tgisinternal) and exists(select 1 from pg_catalog.pg_trigger where tgrelid='public.provider_fixture_score_members'::regclass and tgname='provider_fixture_score_members_immutable' and tgenabled='A' and not tgisinternal),
    'snapshot_decision_ready',position('score.final_team_coverage' in lower(v_decision))>0 and position('score.final_regression' in lower(v_decision))>0 and position('score.coverage_drop' in lower(v_decision))>0,
    'snapshot_members_ready',position('provider_fixture_score_members' in lower(v_prepare))>0 and position('score.member_count_mismatch' in lower(v_prepare))>0,
    'soft_retirement_ready',position('provider_score_state' in lower(v_apply))>0 and position('retired' in lower(v_apply))>0 and position('provider_rating=null' in replace(lower(v_apply),' ',''))>0 and position('delete from public.player_match_scores' in lower(v_apply))=0 and position('provider_score_state' in lower(v_quality_metrics))>0 and position('provider_score_state' in lower(v_quality_center))>0,
    'write_guard_ready',exists(select 1 from pg_catalog.pg_trigger where tgrelid='public.player_match_scores'::regclass and tgname='provider_fixture_score_snapshot_guard' and tgenabled='A' and not tgisinternal) and position('score.snapshot_required' in lower(v_guard))>0 and position('provider_fixtures' in lower(v_guard))>0 and position('reconciliation_row.provider' in lower(v_guard))>0,
    'publication_trigger_ready',exists(select 1 from pg_catalog.pg_trigger where tgrelid='public.provider_sync_publications'::regclass and tgname='provider_fixture_score_publication_reconcile' and tgenabled='A' and not tgisinternal),
    'finish_v8_ready',has_function_privilege('service_role','public.finish_provider_sync_run_guarded_v8(uuid,text,integer,text,bigint,uuid)','EXECUTE') and position('prepare_provider_fixture_score_reconciliation_v1' in lower(v_finish_v8))>0 and position('finish_provider_sync_run_guarded_v8' in lower(v_finish_v7))>0,
    'retry_policy_ready',position('voti provider non validi' in lower(v_retry))>0 and position('score.%' in lower(v_retry))>0,
    'center_health_ready',to_regprocedure('public.get_league_provider_fixture_score_center_v1(uuid)') is not null and to_regprocedure('public.get_league_provider_sync_health_v17(uuid)') is not null and has_function_privilege('authenticated','public.get_league_provider_sync_health_v17(uuid)','EXECUTE'),
    'realtime_ready',exists(select 1 from pg_catalog.pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='provider_fixture_score_heads') and exists(select 1 from pg_catalog.pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='provider_fixture_score_reconciliations') and exists(select 1 from pg_catalog.pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='provider_fixture_score_events') and not exists(select 1 from pg_catalog.pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='provider_fixture_score_members')
  );
end;
$function$;
revoke all on function public.get_provider_fixture_score_reconciliation_integrity_v1() from public,anon,authenticated;
grant execute on function public.get_provider_fixture_score_reconciliation_integrity_v1() to service_role;

do $validation$
declare
  v_checks jsonb;
  v_failed text;
begin
  v_checks:=public.get_provider_fixture_score_reconciliation_integrity_v1();
  if (select count(*) from jsonb_each(v_checks)) <> 20 then
    raise exception 'Validazione v0.62.18 non superata. Numero controlli atteso: 20; numero rilevato: %',
      (select count(*) from jsonb_each(v_checks));
  end if;
  select string_agg(check_row.key,', ' order by check_row.key) into v_failed
  from jsonb_each(v_checks) check_row
  where jsonb_typeof(check_row.value) is distinct from 'boolean' or check_row.value is distinct from 'true'::jsonb;
  if v_failed is not null then raise exception 'Validazione v0.62.18 non superata. Controlli falsi: %',v_failed; end if;
end;
$validation$;

commit;

-- DIAGNOSTICA FINALE: devono comparire esattamente 20 valori true.
select
  (checks->>'predecessor_ready')::boolean as predecessor_ready,
  (checks->>'score_columns_ready')::boolean as score_columns_ready,
  (checks->>'head_table_ready')::boolean as head_table_ready,
  (checks->>'reconciliation_table_ready')::boolean as reconciliation_table_ready,
  (checks->>'member_table_ready')::boolean as member_table_ready,
  (checks->>'event_table_ready')::boolean as event_table_ready,
  (checks->>'constraints_ready')::boolean as constraints_ready,
  (checks->>'indexes_ready')::boolean as indexes_ready,
  (checks->>'rls_ready')::boolean as rls_ready,
  (checks->>'authenticated_write_blocked')::boolean as authenticated_write_blocked,
  (checks->>'immutable_history_ready')::boolean as immutable_history_ready,
  (checks->>'snapshot_decision_ready')::boolean as snapshot_decision_ready,
  (checks->>'snapshot_members_ready')::boolean as snapshot_members_ready,
  (checks->>'soft_retirement_ready')::boolean as soft_retirement_ready,
  (checks->>'write_guard_ready')::boolean as write_guard_ready,
  (checks->>'publication_trigger_ready')::boolean as publication_trigger_ready,
  (checks->>'finish_v8_ready')::boolean as finish_v8_ready,
  (checks->>'retry_policy_ready')::boolean as retry_policy_ready,
  (checks->>'center_health_ready')::boolean as center_health_ready,
  (checks->>'realtime_ready')::boolean as realtime_ready
from (select public.get_provider_fixture_score_reconciliation_integrity_v1() as checks) diagnostic;
