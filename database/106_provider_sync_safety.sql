-- LEGHEVO v0.62.2 · Sincronizzazione provider protetta
-- Migrazione interna: database/106_provider_sync_safety.sql
--
-- Obiettivi:
-- - richieste di sincronizzazione normalizzate e idempotenti per finestra;
-- - protezione contro esecuzioni concorrenti dello stesso lavoro;
-- - transizioni running/completed/failed revisionate e certificate;
-- - continuità con la Edge Function storica e con i cron esistenti;
-- - Centro Operativo con stato del pipeline dati;
-- - diagnostica strutturale finale di 20 controlli.

begin;

-- Preflight esclusivamente strutturale: nessuna modifica viene applicata se
-- manca una dipendenza già prevista dalle versioni precedenti.
do $preflight$
declare
  v_missing text[] := array[]::text[];
  v_expected record;
begin
  for v_expected in
    select *
    from (values
      ('provider_sync_runs', 'id'),
      ('provider_sync_runs', 'provider'),
      ('provider_sync_runs', 'sync_type'),
      ('provider_sync_runs', 'requested_for'),
      ('provider_sync_runs', 'status'),
      ('provider_sync_runs', 'records_processed'),
      ('provider_sync_runs', 'error_message'),
      ('provider_sync_runs', 'started_at'),
      ('provider_sync_runs', 'finished_at'),
      ('provider_fixtures', 'id'),
      ('provider_fixtures', 'matchday_id'),
      ('provider_fixtures', 'updated_at'),
      ('player_match_scores', 'id'),
      ('player_match_scores', 'updated_at'),
      ('leagues', 'id'),
      ('leagues', 'owner_id')
    ) as expected(table_name, column_name)
  loop
    if not exists (
      select 1
      from information_schema.columns column_row
      where column_row.table_schema = 'public'
        and column_row.table_name = v_expected.table_name
        and column_row.column_name = v_expected.column_name
    ) then
      v_missing := array_append(
        v_missing,
        format('column public.%I.%I', v_expected.table_name, v_expected.column_name)
      );
    end if;
  end loop;

  if to_regprocedure('public.is_league_admin(uuid)') is null then
    v_missing := array_append(v_missing, 'function public.is_league_admin(uuid)');
  end if;

  if coalesce(array_length(v_missing, 1), 0) > 0 then
    raise exception
      'Preflight v0.62.2 non superato. Oggetti mancanti: %',
      array_to_string(v_missing, '; ');
  end if;
end;
$preflight$;

alter table public.provider_sync_runs
  add column if not exists request_bucket text,
  add column if not exists request_key text,
  add column if not exists request_fingerprint text,
  add column if not exists attempt_no integer not null default 1,
  add column if not exists revision bigint not null default 1,
  add column if not exists last_updated_at timestamptz not null default now(),
  add column if not exists result_fingerprint text;

create or replace function public.normalize_provider_sync_request_v1(
  p_request jsonb
)
returns jsonb
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_action text := lower(trim(coalesce(p_request ->> 'action', '')));
  v_season_text text;
  v_date_text text;
  v_fixture_text text;
begin
  if jsonb_typeof(p_request) is distinct from 'object' then
    raise exception 'La richiesta provider deve essere un oggetto JSON.';
  end if;

  if v_action = 'sync-season-players' then
    v_season_text := trim(coalesce(p_request ->> 'season', ''));
    if v_season_text !~ '^[0-9]{4}$'
      or v_season_text::integer < 2000
      or v_season_text::integer > 2100 then
      raise exception 'Stagione provider non valida.';
    end if;

    return jsonb_build_object(
      'action', v_action,
      'season', v_season_text::integer
    );
  elsif v_action = 'sync-fixtures' then
    v_season_text := trim(coalesce(p_request ->> 'season', ''));
    v_date_text := trim(coalesce(p_request ->> 'date', ''));

    if v_season_text !~ '^[0-9]{4}$'
      or v_season_text::integer < 2000
      or v_season_text::integer > 2100 then
      raise exception 'Stagione provider non valida.';
    end if;
    if v_date_text !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then
      raise exception 'La data provider deve usare il formato YYYY-MM-DD.';
    end if;

    begin
      perform v_date_text::date;
    exception when others then
      raise exception 'Data provider non valida.';
    end;

    return jsonb_build_object(
      'action', v_action,
      'season', v_season_text::integer,
      'date', v_date_text
    );
  elsif v_action = 'sync-fixture-players' then
    v_fixture_text := trim(coalesce(p_request ->> 'fixtureId', ''));
    if v_fixture_text !~ '^[0-9]+$'
      or v_fixture_text::numeric <= 0
      or v_fixture_text::numeric > 9223372036854775807 then
      raise exception 'Identificativo partita provider non valido.';
    end if;

    return jsonb_build_object(
      'action', v_action,
      'fixtureId', v_fixture_text::bigint
    );
  end if;

  raise exception 'Azione di sincronizzazione provider non riconosciuta.';
end;
$$;

revoke all on function public.normalize_provider_sync_request_v1(jsonb)
from public, anon, authenticated;

create or replace function public.provider_sync_request_bucket_v1(
  p_sync_type text,
  p_started_at timestamptz
)
returns text
language sql
stable
set search_path = ''
as $$
  select case lower(trim(coalesce(p_sync_type, '')))
    when 'sync-fixtures' then
      to_char(p_started_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:')
      || lpad(
        ((floor(extract(minute from (p_started_at at time zone 'UTC')) / 5) * 5)::integer)::text,
        2,
        '0'
      )
    when 'sync-fixture-players' then
      to_char(p_started_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI')
    when 'sync-season-players' then
      to_char(p_started_at at time zone 'UTC', 'YYYY-MM-DD')
    else
      to_char(p_started_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI')
  end
$$;

revoke all on function public.provider_sync_request_bucket_v1(text, timestamptz)
from public, anon, authenticated;

-- Backfill non distruttivo dei run storici. Per i record precedenti viene usata
-- una chiave individuale, così nessuna sincronizzazione già registrata viene
-- accorpata o eliminata.
update public.provider_sync_runs run_row
set
  request_bucket = coalesce(
    run_row.request_bucket,
    public.provider_sync_request_bucket_v1(
      run_row.sync_type,
      run_row.started_at
    )
  ),
  request_fingerprint = coalesce(
    run_row.request_fingerprint,
    pg_catalog.md5(
      coalesce(run_row.provider, '') || E'\n'
      || coalesce(run_row.sync_type, '') || E'\n'
      || coalesce(run_row.requested_for::text, '{}')
    )
  ),
  request_key = coalesce(
    run_row.request_key,
    pg_catalog.md5('legacy:' || run_row.id::text)
  ),
  attempt_no = greatest(coalesce(run_row.attempt_no, 1), 1),
  revision = greatest(coalesce(run_row.revision, 1), 1),
  last_updated_at = coalesce(
    run_row.last_updated_at,
    run_row.finished_at,
    run_row.started_at,
    now()
  ),
  result_fingerprint = coalesce(
    run_row.result_fingerprint,
    case
      when run_row.status in ('completed', 'failed') then
        pg_catalog.md5(
          coalesce(run_row.status, '') || E'\n'
          || coalesce(run_row.records_processed, 0)::text || E'\n'
          || coalesce(run_row.error_message, '') || E'\n'
          || coalesce(run_row.finished_at::text, '')
        )
      else null
    end
  );

alter table public.provider_sync_runs
  alter column request_bucket set not null,
  alter column request_key set not null,
  alter column request_fingerprint set not null;

alter table public.provider_sync_runs
  drop constraint if exists provider_sync_runs_attempt_check;
alter table public.provider_sync_runs
  add constraint provider_sync_runs_attempt_check
  check (attempt_no > 0);

alter table public.provider_sync_runs
  drop constraint if exists provider_sync_runs_revision_check;
alter table public.provider_sync_runs
  add constraint provider_sync_runs_revision_check
  check (revision > 0);

alter table public.provider_sync_runs
  drop constraint if exists provider_sync_runs_request_key_check;
alter table public.provider_sync_runs
  add constraint provider_sync_runs_request_key_check
  check (char_length(request_key) = 32);

alter table public.provider_sync_runs
  drop constraint if exists provider_sync_runs_request_fingerprint_check;
alter table public.provider_sync_runs
  add constraint provider_sync_runs_request_fingerprint_check
  check (char_length(request_fingerprint) = 32);

alter table public.provider_sync_runs
  drop constraint if exists provider_sync_runs_result_fingerprint_check;
alter table public.provider_sync_runs
  add constraint provider_sync_runs_result_fingerprint_check
  check (
    result_fingerprint is null
    or char_length(result_fingerprint) = 32
  );

create index if not exists provider_sync_runs_latest_idx
  on public.provider_sync_runs (provider, sync_type, started_at desc);
create index if not exists provider_sync_runs_request_idx
  on public.provider_sync_runs (provider, request_key, attempt_no desc);
create unique index if not exists provider_sync_runs_active_request_uidx
  on public.provider_sync_runs (provider, request_key)
  where status = 'running';

create table if not exists public.provider_sync_run_events (
  id uuid primary key default gen_random_uuid(),
  run_id uuid not null references public.provider_sync_runs(id) on delete cascade,
  provider text not null,
  sync_type text not null,
  event_type text not null check (
    event_type in ('started', 'heartbeat', 'completed', 'failed')
  ),
  revision bigint not null check (revision > 0),
  records_processed integer not null default 0 check (records_processed >= 0),
  event_fingerprint text not null check (char_length(event_fingerprint) = 32),
  created_at timestamptz not null default now(),
  unique (run_id, revision)
);

create index if not exists provider_sync_run_events_latest_idx
  on public.provider_sync_run_events (created_at desc);
create index if not exists provider_sync_run_events_action_idx
  on public.provider_sync_run_events (sync_type, created_at desc);

alter table public.provider_sync_runs enable row level security;
alter table public.provider_sync_runs replica identity full;
alter table public.provider_sync_run_events enable row level security;
alter table public.provider_sync_run_events replica identity full;

revoke all on table public.provider_sync_runs
from public, anon, authenticated;
revoke all on table public.provider_sync_run_events
from public, anon, authenticated;

grant select, insert, update on table public.provider_sync_runs to service_role;
grant select, insert on table public.provider_sync_run_events to service_role;
grant select on table public.provider_sync_run_events to authenticated;

drop policy if exists provider_sync_run_events_read_authenticated
on public.provider_sync_run_events;
create policy provider_sync_run_events_read_authenticated
on public.provider_sync_run_events
for select to authenticated
using (true);

create or replace function public.prepare_provider_sync_run_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_normalized jsonb;
begin
  if tg_op = 'INSERT' then
    v_normalized := public.normalize_provider_sync_request_v1(new.requested_for);
    new.provider := lower(trim(coalesce(new.provider, 'api-football')));
    if new.provider = '' then
      raise exception 'Provider non valido.';
    end if;

    new.requested_for := v_normalized;
    new.sync_type := v_normalized ->> 'action';
    new.started_at := coalesce(new.started_at, now());
    new.request_bucket := public.provider_sync_request_bucket_v1(
      new.sync_type,
      new.started_at
    );
    new.request_fingerprint := pg_catalog.md5(
      new.provider || E'\n'
      || new.sync_type || E'\n'
      || new.requested_for::text
    );
    new.request_key := pg_catalog.md5(
      new.request_fingerprint || E'\n' || new.request_bucket
    );
    new.attempt_no := greatest(coalesce(new.attempt_no, 1), 1);
    new.revision := 1;
    new.last_updated_at := new.started_at;
    new.status := coalesce(new.status, 'running');
    new.records_processed := greatest(coalesce(new.records_processed, 0), 0);

    if new.status <> 'running' then
      raise exception 'Un nuovo run provider deve iniziare nello stato running.';
    end if;

    new.error_message := null;
    new.finished_at := null;
    new.result_fingerprint := null;
    return new;
  end if;

  if row(
    new.provider,
    new.sync_type,
    new.requested_for,
    new.request_bucket,
    new.request_key,
    new.request_fingerprint,
    new.attempt_no,
    new.started_at
  ) is distinct from row(
    old.provider,
    old.sync_type,
    old.requested_for,
    old.request_bucket,
    old.request_key,
    old.request_fingerprint,
    old.attempt_no,
    old.started_at
  ) then
    raise exception 'Identità del run provider non modificabile.';
  end if;

  if old.status in ('completed', 'failed') then
    if row(
      new.status,
      new.records_processed,
      new.error_message,
      new.finished_at
    ) is not distinct from row(
      old.status,
      old.records_processed,
      old.error_message,
      old.finished_at
    ) then
      return old;
    end if;
    raise exception 'Run provider già concluso e immutabile.';
  end if;

  if new.status not in ('running', 'completed', 'failed') then
    raise exception 'Stato del run provider non valido.';
  end if;

  new.records_processed := greatest(coalesce(new.records_processed, 0), 0);
  new.revision := old.revision + 1;
  new.last_updated_at := now();

  if new.status = 'running' then
    new.finished_at := null;
    new.error_message := null;
    new.result_fingerprint := null;
  else
    new.finished_at := coalesce(new.finished_at, now());
    if new.status = 'completed' then
      new.error_message := null;
    else
      new.error_message := left(
        coalesce(nullif(trim(new.error_message), ''), 'Errore provider non specificato.'),
        1200
      );
    end if;
    new.result_fingerprint := pg_catalog.md5(
      new.status || E'\n'
      || new.records_processed::text || E'\n'
      || coalesce(new.error_message, '') || E'\n'
      || new.finished_at::text || E'\n'
      || new.revision::text
    );
  end if;

  return new;
end;
$$;

revoke all on function public.prepare_provider_sync_run_v1()
from public, anon, authenticated;

drop trigger if exists provider_sync_run_revision_guard
on public.provider_sync_runs;
create trigger provider_sync_run_revision_guard
before insert or update on public.provider_sync_runs
for each row execute function public.prepare_provider_sync_run_v1();

create or replace function public.record_provider_sync_run_event_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_event_type text;
begin
  if tg_op = 'INSERT' then
    v_event_type := 'started';
  elsif new.status = 'completed' then
    v_event_type := 'completed';
  elsif new.status = 'failed' then
    v_event_type := 'failed';
  else
    v_event_type := 'heartbeat';
  end if;

  insert into public.provider_sync_run_events (
    run_id,
    provider,
    sync_type,
    event_type,
    revision,
    records_processed,
    event_fingerprint,
    created_at
  ) values (
    new.id,
    new.provider,
    new.sync_type,
    v_event_type,
    new.revision,
    new.records_processed,
    pg_catalog.md5(
      new.id::text || E'\n'
      || v_event_type || E'\n'
      || new.revision::text || E'\n'
      || new.records_processed::text || E'\n'
      || coalesce(new.result_fingerprint, '')
    ),
    new.last_updated_at
  )
  on conflict (run_id, revision) do nothing;

  return new;
end;
$$;

revoke all on function public.record_provider_sync_run_event_v1()
from public, anon, authenticated;

drop trigger if exists provider_sync_run_event_writer
on public.provider_sync_runs;
create trigger provider_sync_run_event_writer
after insert or update on public.provider_sync_runs
for each row execute function public.record_provider_sync_run_event_v1();

create or replace function public.prevent_provider_sync_event_mutation_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  raise exception 'Evento provider certificato: modifica o cancellazione non consentita.';
end;
$$;

revoke all on function public.prevent_provider_sync_event_mutation_v1()
from public, anon, authenticated;

drop trigger if exists provider_sync_run_events_immutable
on public.provider_sync_run_events;
create trigger provider_sync_run_events_immutable
before update or delete on public.provider_sync_run_events
for each row execute function public.prevent_provider_sync_event_mutation_v1();

-- Certifica anche lo stato corrente dei run storici senza alterarne l'esito.
insert into public.provider_sync_run_events (
  run_id,
  provider,
  sync_type,
  event_type,
  revision,
  records_processed,
  event_fingerprint,
  created_at
)
select
  run_row.id,
  run_row.provider,
  run_row.sync_type,
  case
    when run_row.status = 'completed' then 'completed'
    when run_row.status = 'failed' then 'failed'
    else 'started'
  end,
  run_row.revision,
  run_row.records_processed,
  pg_catalog.md5(
    run_row.id::text || E'\n'
    || run_row.status || E'\n'
    || run_row.revision::text || E'\n'
    || run_row.records_processed::text || E'\n'
    || coalesce(run_row.result_fingerprint, '')
  ),
  coalesce(run_row.finished_at, run_row.started_at)
from public.provider_sync_runs run_row
on conflict (run_id, revision) do nothing;

create or replace function public.start_provider_sync_run_guarded_v1(
  p_request jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_provider constant text := 'api-football';
  v_request jsonb;
  v_sync_type text;
  v_started_at timestamptz := now();
  v_bucket text;
  v_request_fingerprint text;
  v_request_key text;
  v_existing public.provider_sync_runs%rowtype;
  v_inserted public.provider_sync_runs%rowtype;
  v_attempt integer := 1;
begin
  v_request := public.normalize_provider_sync_request_v1(p_request);
  v_sync_type := v_request ->> 'action';
  v_bucket := public.provider_sync_request_bucket_v1(v_sync_type, v_started_at);
  v_request_fingerprint := pg_catalog.md5(
    v_provider || E'\n' || v_sync_type || E'\n' || v_request::text
  );
  v_request_key := pg_catalog.md5(v_request_fingerprint || E'\n' || v_bucket);

  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext(v_request_key));

  select run_row.*
  into v_existing
  from public.provider_sync_runs run_row
  where run_row.provider = v_provider
    and run_row.request_key = v_request_key
    and run_row.status in ('running', 'completed')
  order by run_row.attempt_no desc, run_row.started_at desc
  limit 1;

  if found then
    return jsonb_build_object(
      'runId', v_existing.id,
      'status', v_existing.status,
      'revision', v_existing.revision,
      'attempt', v_existing.attempt_no,
      'recordsProcessed', v_existing.records_processed,
      'requestKey', v_existing.request_key,
      'reused', true
    );
  end if;

  select coalesce(max(run_row.attempt_no), 0) + 1
  into v_attempt
  from public.provider_sync_runs run_row
  where run_row.provider = v_provider
    and run_row.request_key = v_request_key;

  insert into public.provider_sync_runs (
    provider,
    sync_type,
    requested_for,
    status,
    records_processed,
    started_at,
    request_bucket,
    request_key,
    request_fingerprint,
    attempt_no
  ) values (
    v_provider,
    v_sync_type,
    v_request,
    'running',
    0,
    v_started_at,
    v_bucket,
    v_request_key,
    v_request_fingerprint,
    greatest(v_attempt, 1)
  )
  returning * into v_inserted;

  return jsonb_build_object(
    'runId', v_inserted.id,
    'status', v_inserted.status,
    'revision', v_inserted.revision,
    'attempt', v_inserted.attempt_no,
    'recordsProcessed', v_inserted.records_processed,
    'requestKey', v_inserted.request_key,
    'reused', false
  );
end;
$$;

revoke all on function public.start_provider_sync_run_guarded_v1(jsonb)
from public, anon, authenticated;
grant execute on function public.start_provider_sync_run_guarded_v1(jsonb)
to service_role;

create or replace function public.finish_provider_sync_run_guarded_v1(
  p_run_id uuid,
  p_status text,
  p_records_processed integer,
  p_error_message text default null,
  p_expected_revision bigint default 1
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_status text := lower(trim(coalesce(p_status, '')));
  v_run public.provider_sync_runs%rowtype;
  v_updated public.provider_sync_runs%rowtype;
begin
  if v_status not in ('completed', 'failed') then
    raise exception 'Stato finale del run provider non valido.';
  end if;
  if coalesce(p_records_processed, 0) < 0 then
    raise exception 'Il numero di record elaborati non può essere negativo.';
  end if;

  select run_row.*
  into v_run
  from public.provider_sync_runs run_row
  where run_row.id = p_run_id
  for update;

  if not found then
    raise exception 'Run provider non trovato.';
  end if;

  if v_run.status in ('completed', 'failed') then
    if v_run.status = v_status
      and v_run.records_processed = coalesce(p_records_processed, 0)
      and (
        v_status = 'completed'
        or coalesce(v_run.error_message, '') = left(
          coalesce(nullif(trim(p_error_message), ''), 'Errore provider non specificato.'),
          1200
        )
      ) then
      return jsonb_build_object(
        'runId', v_run.id,
        'status', v_run.status,
        'revision', v_run.revision,
        'attempt', v_run.attempt_no,
        'recordsProcessed', v_run.records_processed,
        'requestKey', v_run.request_key,
        'reused', true
      );
    end if;
    raise exception 'Run provider già concluso con un esito differente.';
  end if;

  if p_expected_revision is not null
    and v_run.revision <> p_expected_revision then
    raise exception
      'Run provider aggiornato da un''altra esecuzione. Revisione attesa %, revisione corrente %.',
      p_expected_revision,
      v_run.revision;
  end if;

  update public.provider_sync_runs run_row
  set
    status = v_status,
    records_processed = coalesce(p_records_processed, 0),
    error_message = case when v_status = 'failed' then p_error_message else null end,
    finished_at = now()
  where run_row.id = p_run_id
  returning * into v_updated;

  return jsonb_build_object(
    'runId', v_updated.id,
    'status', v_updated.status,
    'revision', v_updated.revision,
    'attempt', v_updated.attempt_no,
    'recordsProcessed', v_updated.records_processed,
    'requestKey', v_updated.request_key,
    'reused', false
  );
end;
$$;

revoke all on function public.finish_provider_sync_run_guarded_v1(
  uuid, text, integer, text, bigint
) from public, anon, authenticated;
grant execute on function public.finish_provider_sync_run_guarded_v1(
  uuid, text, integer, text, bigint
) to service_role;

create or replace function public.get_league_provider_sync_health_v1(
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
  v_failed_count integer := 0;
  v_failed_action_count integer := 0;
  v_stuck_count integer := 0;
  v_last_run_at timestamptz;
  v_last_success_at timestamptz;
  v_latest_data_at timestamptz;
  v_actions jsonb := '[]'::jsonb;
  v_healthy boolean := true;
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
    raise exception 'Il monitor provider è riservato alla Direzione.';
  end if;

  select
    count(*) filter (
      where run_row.status = 'failed'
        and run_row.started_at >= now() - interval '24 hours'
    )::integer,
    count(*) filter (
      where run_row.status = 'running'
        and run_row.started_at < now() - interval '20 minutes'
    )::integer,
    max(run_row.started_at),
    max(run_row.finished_at) filter (where run_row.status = 'completed')
  into
    v_failed_count,
    v_stuck_count,
    v_last_run_at,
    v_last_success_at
  from public.provider_sync_runs run_row
  where run_row.provider = 'api-football';

  select greatest(
    (select max(provider_fixture.updated_at) from public.provider_fixtures provider_fixture),
    (select max(score.updated_at) from public.player_match_scores score)
  )
  into v_latest_data_at;

  select count(*)::integer
  into v_failed_action_count
  from (
    select distinct on (run_row.sync_type)
      run_row.sync_type,
      run_row.status
    from public.provider_sync_runs run_row
    where run_row.provider = 'api-football'
    order by run_row.sync_type, run_row.started_at desc, run_row.attempt_no desc
  ) latest_status
  where latest_status.status = 'failed';

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'action', latest.sync_type,
        'status', latest.status,
        'startedAt', latest.started_at,
        'finishedAt', latest.finished_at,
        'recordsProcessed', latest.records_processed,
        'revision', latest.revision,
        'attempt', latest.attempt_no
      )
      order by latest.sync_type
    ),
    '[]'::jsonb
  )
  into v_actions
  from (
    select distinct on (run_row.sync_type)
      run_row.sync_type,
      run_row.status,
      run_row.started_at,
      run_row.finished_at,
      run_row.records_processed,
      run_row.revision,
      run_row.attempt_no
    from public.provider_sync_runs run_row
    where run_row.provider = 'api-football'
    order by run_row.sync_type, run_row.started_at desc, run_row.attempt_no desc
  ) latest;

  v_healthy := coalesce(v_stuck_count, 0) = 0
    and coalesce(v_failed_action_count, 0) = 0;

  return jsonb_build_object(
    'provider', 'api-football',
    'protected', true,
    'healthy', v_healthy,
    'status', case
      when coalesce(v_stuck_count, 0) > 0
        or coalesce(v_failed_action_count, 0) > 0 then 'attention'
      when v_last_run_at is null then 'idle'
      else 'healthy'
    end,
    'failedLast24h', coalesce(v_failed_count, 0),
    'stuckRunCount', coalesce(v_stuck_count, 0),
    'lastRunAt', v_last_run_at,
    'lastSuccessfulAt', v_last_success_at,
    'latestDataAt', v_latest_data_at,
    'actions', v_actions
  );
end;
$$;

revoke all on function public.get_league_provider_sync_health_v1(uuid)
from public, anon, authenticated;
grant execute on function public.get_league_provider_sync_health_v1(uuid)
to authenticated;

-- Pubblicazione Realtime del solo registro eventi, che non contiene payload,
-- chiavi o messaggi di errore del provider.
do $realtime$
begin
  if not exists (
    select 1
    from pg_publication_tables publication_table
    where publication_table.pubname = 'supabase_realtime'
      and publication_table.schemaname = 'public'
      and publication_table.tablename = 'provider_sync_run_events'
  ) then
    alter publication supabase_realtime
      add table public.provider_sync_run_events;
  end if;
end;
$realtime$;

create or replace function public.get_provider_sync_safety_integrity_v1()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'runs_table_ready',
      to_regclass('public.provider_sync_runs') is not null,
    'runs_columns_ready',
      (
        select count(*) = 7
        from information_schema.columns column_row
        where column_row.table_schema = 'public'
          and column_row.table_name = 'provider_sync_runs'
          and column_row.column_name in (
            'request_bucket',
            'request_key',
            'request_fingerprint',
            'attempt_no',
            'revision',
            'last_updated_at',
            'result_fingerprint'
          )
      ),
    'events_table_ready',
      to_regclass('public.provider_sync_run_events') is not null,
    'normalizer_ready',
      to_regprocedure('public.normalize_provider_sync_request_v1(jsonb)') is not null,
    'bucket_ready',
      to_regprocedure('public.provider_sync_request_bucket_v1(text,timestamptz)') is not null,
    'revision_trigger_ready',
      exists (
        select 1 from pg_trigger trigger_row
        where trigger_row.tgname = 'provider_sync_run_revision_guard'
          and not trigger_row.tgisinternal
      ),
    'event_writer_ready',
      exists (
        select 1 from pg_trigger trigger_row
        where trigger_row.tgname = 'provider_sync_run_event_writer'
          and not trigger_row.tgisinternal
      ),
    'events_immutable_ready',
      exists (
        select 1 from pg_trigger trigger_row
        where trigger_row.tgname = 'provider_sync_run_events_immutable'
          and not trigger_row.tgisinternal
      ),
    'active_request_index_ready',
      to_regclass('public.provider_sync_runs_active_request_uidx') is not null,
    'start_rpc_ready',
      to_regprocedure('public.start_provider_sync_run_guarded_v1(jsonb)') is not null,
    'finish_rpc_ready',
      to_regprocedure('public.finish_provider_sync_run_guarded_v1(uuid,text,integer,text,bigint)') is not null,
    'health_rpc_ready',
      to_regprocedure('public.get_league_provider_sync_health_v1(uuid)') is not null,
    'runs_rls_ready',
      coalesce((
        select class_row.relrowsecurity
        from pg_class class_row
        join pg_namespace namespace_row
          on namespace_row.oid = class_row.relnamespace
        where namespace_row.nspname = 'public'
          and class_row.relname = 'provider_sync_runs'
      ), false),
    'events_rls_ready',
      coalesce((
        select class_row.relrowsecurity
        from pg_class class_row
        join pg_namespace namespace_row
          on namespace_row.oid = class_row.relnamespace
        where namespace_row.nspname = 'public'
          and class_row.relname = 'provider_sync_run_events'
      ), false),
    'anonymous_runs_blocked',
      not has_table_privilege('anon', 'public.provider_sync_runs', 'SELECT')
      and not has_table_privilege('anon', 'public.provider_sync_runs', 'INSERT')
      and not has_table_privilege('anon', 'public.provider_sync_runs', 'UPDATE'),
    'authenticated_runs_blocked',
      not has_table_privilege('authenticated', 'public.provider_sync_runs', 'SELECT')
      and not has_table_privilege('authenticated', 'public.provider_sync_runs', 'INSERT')
      and not has_table_privilege('authenticated', 'public.provider_sync_runs', 'UPDATE'),
    'service_start_ready',
      has_function_privilege(
        'service_role',
        'public.start_provider_sync_run_guarded_v1(jsonb)',
        'EXECUTE'
      ),
    'service_finish_ready',
      has_function_privilege(
        'service_role',
        'public.finish_provider_sync_run_guarded_v1(uuid,text,integer,text,bigint)',
        'EXECUTE'
      ),
    'authenticated_health_ready',
      has_function_privilege(
        'authenticated',
        'public.get_league_provider_sync_health_v1(uuid)',
        'EXECUTE'
      ),
    'events_realtime_ready',
      exists (
        select 1
        from pg_publication_tables publication_table
        where publication_table.pubname = 'supabase_realtime'
          and publication_table.schemaname = 'public'
          and publication_table.tablename = 'provider_sync_run_events'
      )
  )
$$;

revoke all on function public.get_provider_sync_safety_integrity_v1()
from public, anon, authenticated;

-- Validazione transazionale con dettaglio, prima del commit.
do $validate$
declare
  v_checks jsonb;
  v_failed text[];
begin
  v_checks := public.get_provider_sync_safety_integrity_v1();

  select array_agg(check_row.key order by check_row.key)
  into v_failed
  from jsonb_each(v_checks) check_row
  where check_row.value is distinct from 'true'::jsonb;

  if coalesce(array_length(v_failed, 1), 0) > 0 then
    raise exception
      'Validazione v0.62.2 non superata. Controlli falsi: %',
      array_to_string(v_failed, ', ');
  end if;
end;
$validate$;

commit;

-- Diagnostica finale: devono comparire esattamente 20 valori true.
select
  coalesce((public.get_provider_sync_safety_integrity_v1() ->> 'runs_table_ready')::boolean, false)
    as runs_table_ready,
  coalesce((public.get_provider_sync_safety_integrity_v1() ->> 'runs_columns_ready')::boolean, false)
    as runs_columns_ready,
  coalesce((public.get_provider_sync_safety_integrity_v1() ->> 'events_table_ready')::boolean, false)
    as events_table_ready,
  coalesce((public.get_provider_sync_safety_integrity_v1() ->> 'normalizer_ready')::boolean, false)
    as normalizer_ready,
  coalesce((public.get_provider_sync_safety_integrity_v1() ->> 'bucket_ready')::boolean, false)
    as bucket_ready,
  coalesce((public.get_provider_sync_safety_integrity_v1() ->> 'revision_trigger_ready')::boolean, false)
    as revision_trigger_ready,
  coalesce((public.get_provider_sync_safety_integrity_v1() ->> 'event_writer_ready')::boolean, false)
    as event_writer_ready,
  coalesce((public.get_provider_sync_safety_integrity_v1() ->> 'events_immutable_ready')::boolean, false)
    as events_immutable_ready,
  coalesce((public.get_provider_sync_safety_integrity_v1() ->> 'active_request_index_ready')::boolean, false)
    as active_request_index_ready,
  coalesce((public.get_provider_sync_safety_integrity_v1() ->> 'start_rpc_ready')::boolean, false)
    as start_rpc_ready,
  coalesce((public.get_provider_sync_safety_integrity_v1() ->> 'finish_rpc_ready')::boolean, false)
    as finish_rpc_ready,
  coalesce((public.get_provider_sync_safety_integrity_v1() ->> 'health_rpc_ready')::boolean, false)
    as health_rpc_ready,
  coalesce((public.get_provider_sync_safety_integrity_v1() ->> 'runs_rls_ready')::boolean, false)
    as runs_rls_ready,
  coalesce((public.get_provider_sync_safety_integrity_v1() ->> 'events_rls_ready')::boolean, false)
    as events_rls_ready,
  coalesce((public.get_provider_sync_safety_integrity_v1() ->> 'anonymous_runs_blocked')::boolean, false)
    as anonymous_runs_blocked,
  coalesce((public.get_provider_sync_safety_integrity_v1() ->> 'authenticated_runs_blocked')::boolean, false)
    as authenticated_runs_blocked,
  coalesce((public.get_provider_sync_safety_integrity_v1() ->> 'service_start_ready')::boolean, false)
    as service_start_ready,
  coalesce((public.get_provider_sync_safety_integrity_v1() ->> 'service_finish_ready')::boolean, false)
    as service_finish_ready,
  coalesce((public.get_provider_sync_safety_integrity_v1() ->> 'authenticated_health_ready')::boolean, false)
    as authenticated_health_ready,
  coalesce((public.get_provider_sync_safety_integrity_v1() ->> 'events_realtime_ready')::boolean, false)
    as events_realtime_ready;
