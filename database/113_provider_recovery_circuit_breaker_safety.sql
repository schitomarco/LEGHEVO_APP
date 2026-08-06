-- LEGHEVO v0.62.9 · Circuit breaker protetto dei recuperi provider
-- Migrazione interna: database/113_provider_recovery_circuit_breaker_safety.sql
--
-- Obiettivi:
-- - interrompere i cicli manuali illimitati dopo l'esaurimento dei retry automatici;
-- - aprire un circuit breaker idempotente per lega e incidente provider;
-- - bloccare nuove richieste finché la Direzione non autorizza la riapertura;
-- - certificare apertura, rilascio e risoluzione in uno storico immutabile;
-- - preservare coda, watchdog, heartbeat, retry e dati sportivi esistenti;
-- - terminare con una diagnostica strutturale di esattamente 20 controlli.

begin;

-- Preflight esclusivamente strutturale. La migrazione non applica modifiche
-- quando manca una dipendenza validata nelle versioni v0.62.4-v0.62.8.
do $preflight$
declare
  v_missing text[] := array[]::text[];
  v_expected record;
begin
  for v_expected in
    select *
    from (values
      ('leagues', 'id'),
      ('leagues', 'owner_id'),
      ('provider_operational_incidents', 'id'),
      ('provider_operational_incidents', 'provider'),
      ('provider_operational_incidents', 'sync_type'),
      ('provider_operational_incidents', 'status'),
      ('provider_operational_incidents', 'revision'),
      ('provider_operational_incidents', 'resolved_at'),
      ('provider_recovery_requests', 'id'),
      ('provider_recovery_requests', 'league_id'),
      ('provider_recovery_requests', 'incident_id'),
      ('provider_recovery_requests', 'idempotency_key'),
      ('provider_recovery_requests', 'status'),
      ('provider_recovery_requests', 'revision'),
      ('provider_recovery_requests', 'requested_at'),
      ('provider_recovery_retry_schedules', 'id'),
      ('provider_recovery_retry_schedules', 'league_id'),
      ('provider_recovery_retry_schedules', 'incident_id'),
      ('provider_recovery_retry_schedules', 'source_request_id'),
      ('provider_recovery_retry_schedules', 'provider'),
      ('provider_recovery_retry_schedules', 'sync_type'),
      ('provider_recovery_retry_schedules', 'failure_class'),
      ('provider_recovery_retry_schedules', 'retry_no'),
      ('provider_recovery_retry_schedules', 'max_retries'),
      ('provider_recovery_retry_schedules', 'status'),
      ('provider_recovery_retry_schedules', 'revision'),
      ('provider_recovery_retry_schedules', 'failure_summary'),
      ('provider_recovery_retry_schedules', 'available_at'),
      ('provider_recovery_retry_schedules', 'dispatched_at'),
      ('provider_recovery_retry_schedules', 'finished_at'),
      ('provider_recovery_retry_schedules', 'updated_at')
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

  if to_regprocedure('auth.uid()') is null then
    v_missing := array_append(v_missing, 'function auth.uid()');
  end if;
  if to_regprocedure('gen_random_uuid()') is null then
    v_missing := array_append(v_missing, 'function gen_random_uuid()');
  end if;
  if to_regprocedure('pg_catalog.md5(text)') is null then
    v_missing := array_append(v_missing, 'function pg_catalog.md5(text)');
  end if;
  if to_regprocedure('pg_catalog.hashtext(text)') is null then
    v_missing := array_append(v_missing, 'function pg_catalog.hashtext(text)');
  end if;
  if to_regprocedure('pg_catalog.pg_advisory_xact_lock(bigint)') is null then
    v_missing := array_append(
      v_missing,
      'function pg_catalog.pg_advisory_xact_lock(bigint)'
    );
  end if;
  if not exists (
    select 1
    from pg_catalog.pg_roles role_row
    where role_row.rolname = 'anon'
  ) then
    v_missing := array_append(v_missing, 'role anon');
  end if;
  if not exists (
    select 1
    from pg_catalog.pg_roles role_row
    where role_row.rolname = 'authenticated'
  ) then
    v_missing := array_append(v_missing, 'role authenticated');
  end if;
  if not exists (
    select 1
    from pg_catalog.pg_roles role_row
    where role_row.rolname = 'service_role'
  ) then
    v_missing := array_append(v_missing, 'role service_role');
  end if;
  if not exists (
    select 1
    from pg_catalog.pg_publication publication_row
    where publication_row.pubname = 'supabase_realtime'
  ) then
    v_missing := array_append(v_missing, 'publication supabase_realtime');
  end if;
  if to_regprocedure('public.is_league_admin(uuid)') is null then
    v_missing := array_append(v_missing, 'function public.is_league_admin(uuid)');
  end if;
  if to_regprocedure('public.get_league_provider_recovery_center_v3(uuid)') is null then
    v_missing := array_append(
      v_missing,
      'function public.get_league_provider_recovery_center_v3(uuid)'
    );
  end if;
  if to_regprocedure('public.get_league_provider_sync_health_v6(uuid)') is null then
    v_missing := array_append(
      v_missing,
      'function public.get_league_provider_sync_health_v6(uuid)'
    );
  end if;
  if to_regprocedure('public.claim_next_provider_recovery_request_v3()') is null then
    v_missing := array_append(
      v_missing,
      'function public.claim_next_provider_recovery_request_v3()'
    );
  end if;
  if to_regprocedure(
    'public.request_provider_recovery_guarded_v1(uuid,uuid,bigint,uuid)'
  ) is null then
    v_missing := array_append(
      v_missing,
      'function public.request_provider_recovery_guarded_v1(uuid,uuid,bigint,uuid)'
    );
  end if;
  if to_regprocedure(
    'public.get_provider_recovery_retry_backoff_integrity_v1()'
  ) is null then
    v_missing := array_append(
      v_missing,
      'function public.get_provider_recovery_retry_backoff_integrity_v1()'
    );
  end if;

  if coalesce(array_length(v_missing, 1), 0) > 0 then
    raise exception
      'Preflight v0.62.9 non superato. Oggetti mancanti: %',
      array_to_string(v_missing, '; ');
  end if;
end;
$preflight$;

create table if not exists public.provider_recovery_circuit_breakers (
  id uuid primary key default gen_random_uuid(),
  league_id uuid not null references public.leagues(id) on delete cascade,
  incident_id uuid not null
    references public.provider_operational_incidents(id) on delete cascade,
  source_schedule_id uuid not null unique
    references public.provider_recovery_retry_schedules(id) on delete cascade,
  source_request_id uuid not null,
  provider text not null,
  sync_type text not null,
  failure_class text not null check (
    failure_class in (
      'rate_limit', 'timeout', 'network', 'provider',
      'configuration', 'request', 'unknown'
    )
  ),
  retry_no integer not null check (retry_no > 0),
  max_retries integer not null check (max_retries between 1 and 5),
  status text not null default 'open' check (
    status in ('open', 'released', 'resolved')
  ),
  revision bigint not null default 1 check (revision > 0),
  source_schedule_revision bigint not null check (source_schedule_revision > 0),
  failure_summary text not null,
  state_fingerprint text not null check (char_length(state_fingerprint) = 32),
  result_fingerprint text check (
    result_fingerprint is null or char_length(result_fingerprint) = 32
  ),
  opened_at timestamptz not null default now(),
  released_at timestamptz,
  released_by uuid,
  release_reason text,
  release_idempotency_key uuid,
  resolved_at timestamptz,
  updated_at timestamptz not null default now(),
  check (
    (status = 'open'
      and released_at is null
      and released_by is null
      and release_reason is null
      and release_idempotency_key is null
      and resolved_at is null)
    or (status = 'released'
      and released_at is not null
      and released_by is not null
      and release_reason is not null
      and release_idempotency_key is not null
      and resolved_at is null)
    or (status = 'resolved'
      and resolved_at is not null
      and released_at is null
      and released_by is null
      and release_reason is null
      and release_idempotency_key is null)
  )
);

create unique index if not exists provider_recovery_circuit_breakers_open_uidx
  on public.provider_recovery_circuit_breakers (league_id, incident_id)
  where status = 'open';
create index if not exists provider_recovery_circuit_breakers_league_latest_idx
  on public.provider_recovery_circuit_breakers (league_id, opened_at desc);
create index if not exists provider_recovery_circuit_breakers_incident_idx
  on public.provider_recovery_circuit_breakers (incident_id, opened_at desc);

create table if not exists public.provider_recovery_circuit_breaker_events (
  id uuid primary key default gen_random_uuid(),
  breaker_id uuid not null
    references public.provider_recovery_circuit_breakers(id) on delete cascade,
  -- league_id e incident_id sono fotografie storiche. La cancellazione
  -- transita soltanto da breaker_id, evitando percorsi cascade concorrenti
  -- contro il trigger di immutabilità.
  league_id uuid not null,
  incident_id uuid not null,
  event_type text not null check (
    event_type in ('opened', 'released', 'resolved')
  ),
  revision bigint not null check (revision > 0),
  actor_id uuid,
  event_fingerprint text not null check (char_length(event_fingerprint) = 32),
  created_at timestamptz not null default now(),
  unique (breaker_id, revision)
);

create index if not exists provider_recovery_circuit_breaker_events_latest_idx
  on public.provider_recovery_circuit_breaker_events (league_id, created_at desc);
create index if not exists provider_recovery_circuit_breaker_events_incident_idx
  on public.provider_recovery_circuit_breaker_events (incident_id, created_at desc);

alter table public.provider_recovery_circuit_breakers enable row level security;
alter table public.provider_recovery_circuit_breakers replica identity full;
alter table public.provider_recovery_circuit_breaker_events enable row level security;
alter table public.provider_recovery_circuit_breaker_events replica identity full;

revoke all on table public.provider_recovery_circuit_breakers
from public, anon, authenticated;
revoke all on table public.provider_recovery_circuit_breaker_events
from public, anon, authenticated;

grant select on table public.provider_recovery_circuit_breakers to authenticated;
grant select on table public.provider_recovery_circuit_breaker_events to authenticated;
grant select, insert, update on table public.provider_recovery_circuit_breakers
  to service_role;
grant select, insert on table public.provider_recovery_circuit_breaker_events
  to service_role;

drop policy if exists provider_recovery_circuit_breakers_read_directors
on public.provider_recovery_circuit_breakers;
create policy provider_recovery_circuit_breakers_read_directors
on public.provider_recovery_circuit_breakers
for select to authenticated
using (
  exists (
    select 1
    from public.leagues league_row
    where league_row.id = provider_recovery_circuit_breakers.league_id
      and (
        league_row.owner_id = auth.uid()
        or public.is_league_admin(league_row.id)
      )
  )
);

drop policy if exists provider_recovery_circuit_breaker_events_read_directors
on public.provider_recovery_circuit_breaker_events;
create policy provider_recovery_circuit_breaker_events_read_directors
on public.provider_recovery_circuit_breaker_events
for select to authenticated
using (
  exists (
    select 1
    from public.leagues league_row
    where league_row.id = provider_recovery_circuit_breaker_events.league_id
      and (
        league_row.owner_id = auth.uid()
        or public.is_league_admin(league_row.id)
      )
  )
);

create or replace function public.prepare_provider_recovery_circuit_breaker_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    new.provider := lower(trim(coalesce(new.provider, '')));
    new.sync_type := lower(trim(coalesce(new.sync_type, '')));
    new.failure_summary := left(
      coalesce(nullif(trim(new.failure_summary), ''), 'Retry provider esauriti.'),
      500
    );
    new.status := 'open';
    new.revision := 1;
    new.opened_at := coalesce(new.opened_at, now());
    new.updated_at := new.opened_at;
    new.released_at := null;
    new.released_by := null;
    new.release_reason := null;
    new.release_idempotency_key := null;
    new.resolved_at := null;
    new.result_fingerprint := null;
    new.state_fingerprint := pg_catalog.md5(
      new.league_id::text || E'\n'
      || new.incident_id::text || E'\n'
      || new.source_schedule_id::text || E'\n'
      || new.source_request_id::text || E'\n'
      || new.provider || E'\n'
      || new.sync_type || E'\n'
      || new.failure_class || E'\n'
      || new.retry_no::text || E'\n'
      || new.max_retries::text || E'\n'
      || new.source_schedule_revision::text || E'\n'
      || new.failure_summary
    );
    return new;
  end if;

  if row(
    new.league_id,
    new.incident_id,
    new.source_schedule_id,
    new.source_request_id,
    new.provider,
    new.sync_type,
    new.failure_class,
    new.retry_no,
    new.max_retries,
    new.source_schedule_revision,
    new.failure_summary,
    new.state_fingerprint,
    new.opened_at
  ) is distinct from row(
    old.league_id,
    old.incident_id,
    old.source_schedule_id,
    old.source_request_id,
    old.provider,
    old.sync_type,
    old.failure_class,
    old.retry_no,
    old.max_retries,
    old.source_schedule_revision,
    old.failure_summary,
    old.state_fingerprint,
    old.opened_at
  ) then
    raise exception 'Identità del circuit breaker provider non modificabile.';
  end if;

  if old.status <> 'open' then
    if row(
      new.status,
      new.released_at,
      new.released_by,
      new.release_reason,
      new.release_idempotency_key,
      new.resolved_at
    ) is not distinct from row(
      old.status,
      old.released_at,
      old.released_by,
      old.release_reason,
      old.release_idempotency_key,
      old.resolved_at
    ) then
      return old;
    end if;
    raise exception 'Circuit breaker provider già concluso e immutabile.';
  end if;

  if new.status not in ('open', 'released', 'resolved') then
    raise exception 'Transizione del circuit breaker provider non valida.';
  end if;

  if row(
    new.status,
    new.released_at,
    new.released_by,
    new.release_reason,
    new.release_idempotency_key,
    new.resolved_at
  ) is not distinct from row(
    old.status,
    old.released_at,
    old.released_by,
    old.release_reason,
    old.release_idempotency_key,
    old.resolved_at
  ) then
    return old;
  end if;

  new.revision := old.revision + 1;
  new.updated_at := now();

  if new.status = 'released' then
    if new.released_by is null
      or new.release_idempotency_key is null
      or char_length(trim(coalesce(new.release_reason, ''))) < 10 then
      raise exception 'Rilascio del circuit breaker privo di autorizzazione completa.';
    end if;
    new.release_reason := left(trim(new.release_reason), 500);
    new.released_at := coalesce(new.released_at, now());
    new.resolved_at := null;
  elsif new.status = 'resolved' then
    new.released_at := null;
    new.released_by := null;
    new.release_reason := null;
    new.release_idempotency_key := null;
    new.resolved_at := coalesce(new.resolved_at, now());
  end if;

  new.result_fingerprint := pg_catalog.md5(
    new.id::text || E'\n'
    || new.status || E'\n'
    || new.revision::text || E'\n'
    || coalesce(new.released_at::text, '') || E'\n'
    || coalesce(new.released_by::text, '') || E'\n'
    || coalesce(new.release_reason, '') || E'\n'
    || coalesce(new.release_idempotency_key::text, '') || E'\n'
    || coalesce(new.resolved_at::text, '')
  );

  return new;
end;
$$;

revoke all on function public.prepare_provider_recovery_circuit_breaker_v1()
from public, anon, authenticated;

drop trigger if exists provider_recovery_circuit_breaker_revision_guard
on public.provider_recovery_circuit_breakers;
create trigger provider_recovery_circuit_breaker_revision_guard
before insert or update on public.provider_recovery_circuit_breakers
for each row execute function public.prepare_provider_recovery_circuit_breaker_v1();

create or replace function public.record_provider_recovery_circuit_breaker_event_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.provider_recovery_circuit_breaker_events (
    breaker_id,
    league_id,
    incident_id,
    event_type,
    revision,
    actor_id,
    event_fingerprint,
    created_at
  ) values (
    new.id,
    new.league_id,
    new.incident_id,
    case new.status
      when 'open' then 'opened'
      when 'released' then 'released'
      else 'resolved'
    end,
    new.revision,
    case when new.status = 'released' then new.released_by else null end,
    pg_catalog.md5(
      new.id::text || E'\n'
      || new.status || E'\n'
      || new.revision::text || E'\n'
      || coalesce(new.result_fingerprint, new.state_fingerprint)
    ),
    new.updated_at
  )
  on conflict (breaker_id, revision) do nothing;

  return new;
end;
$$;

revoke all on function public.record_provider_recovery_circuit_breaker_event_v1()
from public, anon, authenticated;

drop trigger if exists provider_recovery_circuit_breaker_event_writer
on public.provider_recovery_circuit_breakers;
create trigger provider_recovery_circuit_breaker_event_writer
after insert or update on public.provider_recovery_circuit_breakers
for each row execute function public.record_provider_recovery_circuit_breaker_event_v1();

create or replace function public.prevent_provider_recovery_circuit_breaker_event_mutation_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'DELETE'
    and not exists (
      select 1
      from public.provider_recovery_circuit_breakers breaker_row
      where breaker_row.id = old.breaker_id
    ) then
    return old;
  end if;

  raise exception
    'Evento circuit breaker provider certificato: modifica o cancellazione non consentita.';
end;
$$;

revoke all on function public.prevent_provider_recovery_circuit_breaker_event_mutation_v1()
from public, anon, authenticated;

drop trigger if exists provider_recovery_circuit_breaker_events_immutable
on public.provider_recovery_circuit_breaker_events;
create trigger provider_recovery_circuit_breaker_events_immutable
before update or delete on public.provider_recovery_circuit_breaker_events
for each row execute function public.prevent_provider_recovery_circuit_breaker_event_mutation_v1();

-- Un retry esaurito apre al massimo un blocco attivo per lega e incidente.
create or replace function public.open_provider_recovery_circuit_breaker_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.status <> 'exhausted'
    or (tg_op = 'UPDATE' and old.status is not distinct from new.status) then
    return new;
  end if;

  insert into public.provider_recovery_circuit_breakers (
    league_id,
    incident_id,
    source_schedule_id,
    source_request_id,
    provider,
    sync_type,
    failure_class,
    retry_no,
    max_retries,
    source_schedule_revision,
    failure_summary
  ) values (
    new.league_id,
    new.incident_id,
    new.id,
    new.source_request_id,
    new.provider,
    new.sync_type,
    new.failure_class,
    new.retry_no,
    new.max_retries,
    new.revision,
    coalesce(new.failure_summary, 'Retry provider esauriti.')
  )
  on conflict do nothing;

  return new;
end;
$$;

revoke all on function public.open_provider_recovery_circuit_breaker_v1()
from public, anon, authenticated;

drop trigger if exists provider_recovery_circuit_breaker_opener
on public.provider_recovery_retry_schedules;
create trigger provider_recovery_circuit_breaker_opener
after insert or update of status on public.provider_recovery_retry_schedules
for each row execute function public.open_provider_recovery_circuit_breaker_v1();

-- Recupera in modo idempotente eventuali retry esauriti tra v0.62.8 e questa
-- migrazione. Non modifica richieste, incidenti o dati sportivi.
insert into public.provider_recovery_circuit_breakers (
  league_id,
  incident_id,
  source_schedule_id,
  source_request_id,
  provider,
  sync_type,
  failure_class,
  retry_no,
  max_retries,
  source_schedule_revision,
  failure_summary,
  opened_at
)
select distinct on (schedule_row.league_id, schedule_row.incident_id)
  schedule_row.league_id,
  schedule_row.incident_id,
  schedule_row.id,
  schedule_row.source_request_id,
  schedule_row.provider,
  schedule_row.sync_type,
  schedule_row.failure_class,
  schedule_row.retry_no,
  schedule_row.max_retries,
  schedule_row.revision,
  coalesce(schedule_row.failure_summary, 'Retry provider esauriti.'),
  coalesce(schedule_row.finished_at, schedule_row.updated_at, now())
from public.provider_recovery_retry_schedules schedule_row
join public.provider_operational_incidents incident_row
  on incident_row.id = schedule_row.incident_id
where schedule_row.status = 'exhausted'
  and incident_row.status = 'open'
order by
  schedule_row.league_id,
  schedule_row.incident_id,
  coalesce(schedule_row.finished_at, schedule_row.updated_at) desc,
  schedule_row.id
on conflict do nothing;

-- Qualsiasi nuova richiesta viene respinta quando il blocco è aperto. Il
-- rilascio esplicito riabilita la RPC storica senza cambiarne la firma.
create or replace function public.guard_provider_recovery_request_circuit_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_breaker public.provider_recovery_circuit_breakers%rowtype;
begin
  select breaker_row.*
  into v_breaker
  from public.provider_recovery_circuit_breakers breaker_row
  where breaker_row.league_id = new.league_id
    and breaker_row.incident_id = new.incident_id
    and breaker_row.status = 'open'
  order by breaker_row.opened_at desc
  limit 1;

  if found then
    raise exception
      'Circuit breaker provider aperto. Blocco %, revisione %. La Direzione deve autorizzare la riapertura prima di accodare un nuovo recupero.',
      v_breaker.id,
      v_breaker.revision;
  end if;

  return new;
end;
$$;

revoke all on function public.guard_provider_recovery_request_circuit_v1()
from public, anon, authenticated;

drop trigger if exists provider_recovery_request_circuit_guard
on public.provider_recovery_requests;
create trigger provider_recovery_request_circuit_guard
before insert on public.provider_recovery_requests
for each row execute function public.guard_provider_recovery_request_circuit_v1();

-- Se il provider risolve l'incidente mentre il blocco è aperto, il circuit
-- breaker si chiude automaticamente come risolto, senza intervento manuale.
create or replace function public.resolve_provider_recovery_circuit_breaker_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.status = 'resolved'
    and old.status is distinct from new.status then
    update public.provider_recovery_circuit_breakers breaker_row
    set
      status = 'resolved',
      resolved_at = coalesce(new.resolved_at, now())
    where breaker_row.incident_id = new.id
      and breaker_row.status = 'open';
  end if;

  return new;
end;
$$;

revoke all on function public.resolve_provider_recovery_circuit_breaker_v1()
from public, anon, authenticated;

drop trigger if exists provider_recovery_circuit_breaker_incident_resolver
on public.provider_operational_incidents;
create trigger provider_recovery_circuit_breaker_incident_resolver
after update of status on public.provider_operational_incidents
for each row execute function public.resolve_provider_recovery_circuit_breaker_v1();

create or replace function public.release_provider_recovery_circuit_breaker_guarded_v1(
  p_league_id uuid,
  p_breaker_id uuid,
  p_expected_revision bigint,
  p_release_reason text,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_owner_id uuid;
  v_breaker public.provider_recovery_circuit_breakers%rowtype;
  v_reason text := trim(coalesce(p_release_reason, ''));
  v_incident_status text;
  v_active_request_id uuid;
begin
  if v_user_id is null then
    raise exception 'Sessione non valida.';
  end if;
  if p_league_id is null or p_breaker_id is null then
    raise exception 'Lega e circuit breaker sono obbligatori.';
  end if;
  if p_expected_revision is null or p_expected_revision < 1 then
    raise exception 'Revisione attesa del circuit breaker non valida.';
  end if;
  if p_idempotency_key is null then
    raise exception 'Chiave di idempotenza obbligatoria.';
  end if;
  if char_length(v_reason) < 10 or char_length(v_reason) > 500 then
    raise exception 'La motivazione della riapertura deve contenere da 10 a 500 caratteri.';
  end if;

  select league_row.owner_id
  into v_owner_id
  from public.leagues league_row
  where league_row.id = p_league_id;

  if not found then
    raise exception 'Lega non trovata.';
  end if;
  if v_owner_id <> v_user_id and not public.is_league_admin(p_league_id) then
    raise exception 'Solo Presidente e Admin possono rilasciare il circuit breaker provider.';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext('provider-recovery-circuit:' || p_breaker_id::text)
  );

  select breaker_row.*
  into v_breaker
  from public.provider_recovery_circuit_breakers breaker_row
  where breaker_row.id = p_breaker_id
    and breaker_row.league_id = p_league_id
  for update;

  if not found then
    raise exception 'Circuit breaker provider non trovato.';
  end if;

  if v_breaker.status = 'released'
    and v_breaker.released_by = v_user_id
    and v_breaker.release_idempotency_key = p_idempotency_key then
    return jsonb_build_object(
      'breakerId', v_breaker.id,
      'incidentId', v_breaker.incident_id,
      'status', v_breaker.status,
      'revision', v_breaker.revision,
      'releasedAt', v_breaker.released_at,
      'reused', true
    );
  end if;

  if v_breaker.status = 'resolved' then
    raise exception 'Il circuit breaker risulta già risolto dal provider.';
  end if;
  if v_breaker.status <> 'open' then
    raise exception 'Il circuit breaker provider non è più aperto.';
  end if;
  if v_breaker.revision <> p_expected_revision then
    raise exception
      'Circuit breaker aggiornato da un altro dispositivo. Revisione attesa %, revisione corrente %.',
      p_expected_revision,
      v_breaker.revision;
  end if;

  select incident_row.status
  into v_incident_status
  from public.provider_operational_incidents incident_row
  where incident_row.id = v_breaker.incident_id
  for update;

  if not found then
    raise exception 'Incidente provider collegato non trovato.';
  end if;
  if v_incident_status <> 'open' then
    raise exception 'L’incidente provider non è più aperto.';
  end if;

  select request_row.id
  into v_active_request_id
  from public.provider_recovery_requests request_row
  where request_row.league_id = p_league_id
    and request_row.incident_id = v_breaker.incident_id
    and request_row.status in ('pending', 'running')
  order by request_row.requested_at asc
  limit 1;

  if v_active_request_id is not null then
    raise exception
      'Esiste già un recupero provider attivo: %.',
      v_active_request_id;
  end if;

  update public.provider_recovery_circuit_breakers breaker_row
  set
    status = 'released',
    released_at = now(),
    released_by = v_user_id,
    release_reason = v_reason,
    release_idempotency_key = p_idempotency_key
  where breaker_row.id = v_breaker.id
  returning * into v_breaker;

  return jsonb_build_object(
    'breakerId', v_breaker.id,
    'incidentId', v_breaker.incident_id,
    'status', v_breaker.status,
    'revision', v_breaker.revision,
    'releasedAt', v_breaker.released_at,
    'reused', false
  );
end;
$$;

revoke all on function public.release_provider_recovery_circuit_breaker_guarded_v1(
  uuid, uuid, bigint, text, uuid
) from public, anon, authenticated;
grant execute on function public.release_provider_recovery_circuit_breaker_guarded_v1(
  uuid, uuid, bigint, text, uuid
) to authenticated;

create or replace function public.get_league_provider_circuit_breaker_center_v1(
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
  v_open_count integer := 0;
  v_released_last_24h integer := 0;
  v_resolved_last_24h integer := 0;
  v_latest jsonb;
begin
  select league_row.owner_id
  into v_owner_id
  from public.leagues league_row
  where league_row.id = p_league_id;

  if not found then
    raise exception 'Lega non trovata.';
  end if;
  if auth.uid() is null
    or (v_owner_id <> auth.uid() and not public.is_league_admin(p_league_id)) then
    raise exception 'Il circuit breaker provider è riservato alla Direzione.';
  end if;

  select
    count(*) filter (where breaker_row.status = 'open')::integer,
    count(*) filter (
      where breaker_row.status = 'released'
        and breaker_row.released_at >= now() - interval '24 hours'
    )::integer,
    count(*) filter (
      where breaker_row.status = 'resolved'
        and breaker_row.resolved_at >= now() - interval '24 hours'
    )::integer
  into
    v_open_count,
    v_released_last_24h,
    v_resolved_last_24h
  from public.provider_recovery_circuit_breakers breaker_row
  where breaker_row.league_id = p_league_id;

  select jsonb_build_object(
    'id', breaker_row.id,
    'incidentId', breaker_row.incident_id,
    'revision', breaker_row.revision,
    'syncType', breaker_row.sync_type,
    'failureClass', breaker_row.failure_class,
    'retryNo', breaker_row.retry_no,
    'maxRetries', breaker_row.max_retries,
    'summary', breaker_row.failure_summary,
    'openedAt', breaker_row.opened_at
  )
  into v_latest
  from public.provider_recovery_circuit_breakers breaker_row
  where breaker_row.league_id = p_league_id
    and breaker_row.status = 'open'
  order by breaker_row.opened_at desc
  limit 1;

  return jsonb_build_object(
    'protected', true,
    'healthy', coalesce(v_open_count, 0) = 0,
    'blocked', coalesce(v_open_count, 0) > 0,
    'openCount', coalesce(v_open_count, 0),
    'releasedLast24h', coalesce(v_released_last_24h, 0),
    'resolvedLast24h', coalesce(v_resolved_last_24h, 0),
    'latestOpen', v_latest
  );
end;
$$;

revoke all on function public.get_league_provider_circuit_breaker_center_v1(uuid)
from public, anon, authenticated;
grant execute on function public.get_league_provider_circuit_breaker_center_v1(uuid)
to authenticated;

-- La metrica "esauriti" rappresenta ora soltanto blocchi ancora aperti.
create or replace function public.get_league_provider_retry_center_v2(
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
  v_scheduled_count integer := 0;
  v_due_count integer := 0;
  v_dispatched_count integer := 0;
  v_succeeded_last_24h integer := 0;
  v_failed_last_24h integer := 0;
  v_exhausted_open_count integer := 0;
  v_next_retry_at timestamptz;
begin
  select league_row.owner_id
  into v_owner_id
  from public.leagues league_row
  where league_row.id = p_league_id;

  if not found then
    raise exception 'Lega non trovata.';
  end if;
  if auth.uid() is null
    or (v_owner_id <> auth.uid() and not public.is_league_admin(p_league_id)) then
    raise exception 'Solo Presidente e Admin possono leggere i retry provider.';
  end if;

  select
    count(*) filter (where schedule_row.status = 'scheduled')::integer,
    count(*) filter (
      where schedule_row.status = 'scheduled'
        and schedule_row.available_at <= now()
    )::integer,
    count(*) filter (where schedule_row.status = 'dispatched')::integer,
    count(*) filter (
      where schedule_row.status = 'succeeded'
        and schedule_row.finished_at >= now() - interval '24 hours'
    )::integer,
    count(*) filter (
      where schedule_row.status = 'failed'
        and schedule_row.finished_at >= now() - interval '24 hours'
    )::integer,
    count(*) filter (
      where schedule_row.status = 'exhausted'
        and exists (
          select 1
          from public.provider_recovery_circuit_breakers breaker_row
          where breaker_row.source_schedule_id = schedule_row.id
            and breaker_row.status = 'open'
        )
    )::integer,
    min(schedule_row.available_at) filter (
      where schedule_row.status = 'scheduled'
    )
  into
    v_scheduled_count,
    v_due_count,
    v_dispatched_count,
    v_succeeded_last_24h,
    v_failed_last_24h,
    v_exhausted_open_count,
    v_next_retry_at
  from public.provider_recovery_retry_schedules schedule_row
  where schedule_row.league_id = p_league_id;

  return jsonb_build_object(
    'protected', true,
    'healthy', coalesce(v_exhausted_open_count, 0) = 0,
    'automaticRetryActive', true,
    'scheduledCount', coalesce(v_scheduled_count, 0),
    'dueCount', coalesce(v_due_count, 0),
    'dispatchedCount', coalesce(v_dispatched_count, 0),
    'succeededLast24h', coalesce(v_succeeded_last_24h, 0),
    'failedLast24h', coalesce(v_failed_last_24h, 0),
    'exhaustedOpenCount', coalesce(v_exhausted_open_count, 0),
    'nextRetryAt', v_next_retry_at,
    'maxRetries', 3
  );
end;
$$;

revoke all on function public.get_league_provider_retry_center_v2(uuid)
from public, anon, authenticated;
grant execute on function public.get_league_provider_retry_center_v2(uuid)
to authenticated;

create or replace function public.get_league_provider_recovery_center_v5(
  p_league_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_center jsonb;
  v_retry jsonb;
  v_breaker jsonb;
  v_healthy boolean;
  v_can_request boolean;
begin
  v_center := public.get_league_provider_recovery_center_v3(p_league_id);
  v_retry := public.get_league_provider_retry_center_v2(p_league_id);
  v_breaker := public.get_league_provider_circuit_breaker_center_v1(p_league_id);
  v_healthy := coalesce((v_center ->> 'healthy')::boolean, false)
    and coalesce((v_retry ->> 'healthy')::boolean, false)
    and coalesce((v_breaker ->> 'healthy')::boolean, false);
  v_can_request := coalesce((v_center ->> 'canRequest')::boolean, false)
    and coalesce((v_retry ->> 'scheduledCount')::integer, 0) = 0
    and coalesce((v_retry ->> 'dispatchedCount')::integer, 0) = 0
    and not coalesce((v_breaker ->> 'blocked')::boolean, false);

  return v_center || jsonb_build_object(
    'healthy', v_healthy,
    'canRequest', v_can_request,
    'retryCenter', v_retry,
    'circuitBreaker', v_breaker
  );
end;
$$;

revoke all on function public.get_league_provider_recovery_center_v5(uuid)
from public, anon, authenticated;
grant execute on function public.get_league_provider_recovery_center_v5(uuid)
to authenticated;

create or replace function public.get_league_provider_sync_health_v8(
  p_league_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_health jsonb;
  v_recovery jsonb;
  v_healthy boolean;
  v_status text;
begin
  v_health := public.get_league_provider_sync_health_v6(p_league_id);
  v_recovery := public.get_league_provider_recovery_center_v5(p_league_id);
  v_healthy := coalesce((v_health ->> 'healthy')::boolean, false)
    and coalesce((v_recovery ->> 'healthy')::boolean, false);
  v_status := case
    when not v_healthy then 'attention'
    else coalesce(v_health ->> 'status', 'idle')
  end;

  return v_health || jsonb_build_object(
    'healthy', v_healthy,
    'status', v_status,
    'recoveryCenter', v_recovery
  );
end;
$$;

revoke all on function public.get_league_provider_sync_health_v8(uuid)
from public, anon, authenticated;
grant execute on function public.get_league_provider_sync_health_v8(uuid)
to authenticated;

-- Realtime espone soltanto eventi tecnici privi della motivazione di rilascio.
do $realtime$
begin
  if exists (
    select 1
    from pg_catalog.pg_publication publication_row
    where publication_row.pubname = 'supabase_realtime'
  ) and not exists (
    select 1
    from pg_catalog.pg_publication_tables publication_table
    where publication_table.pubname = 'supabase_realtime'
      and publication_table.schemaname = 'public'
      and publication_table.tablename = 'provider_recovery_circuit_breaker_events'
  ) then
    alter publication supabase_realtime
      add table public.provider_recovery_circuit_breaker_events;
  end if;
end;
$realtime$;

create or replace function public.get_provider_recovery_circuit_breaker_integrity_v1()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'circuit_breaker_tables_ready',
      to_regclass('public.provider_recovery_circuit_breakers') is not null
      and to_regclass('public.provider_recovery_circuit_breaker_events') is not null,
    'circuit_breaker_columns_ready',
      (
        select count(*) = 23
        from information_schema.columns column_row
        where column_row.table_schema = 'public'
          and column_row.table_name = 'provider_recovery_circuit_breakers'
          and column_row.column_name in (
            'id', 'league_id', 'incident_id', 'source_schedule_id',
            'source_request_id', 'provider', 'sync_type', 'failure_class',
            'retry_no', 'max_retries', 'status', 'revision',
            'source_schedule_revision', 'failure_summary', 'state_fingerprint',
            'result_fingerprint', 'opened_at', 'released_at', 'released_by',
            'release_reason', 'release_idempotency_key', 'resolved_at', 'updated_at'
          )
      ),
    'circuit_breaker_event_columns_ready',
      (
        select count(*) = 9
        from information_schema.columns column_row
        where column_row.table_schema = 'public'
          and column_row.table_name = 'provider_recovery_circuit_breaker_events'
          and column_row.column_name in (
            'id', 'breaker_id', 'league_id', 'incident_id', 'event_type',
            'revision', 'actor_id', 'event_fingerprint', 'created_at'
          )
      ),
    'circuit_breaker_indexes_ready',
      to_regclass('public.provider_recovery_circuit_breakers_open_uidx') is not null
      and to_regclass(
        'public.provider_recovery_circuit_breakers_league_latest_idx'
      ) is not null
      and to_regclass(
        'public.provider_recovery_circuit_breakers_incident_idx'
      ) is not null
      and to_regclass(
        'public.provider_recovery_circuit_breaker_events_latest_idx'
      ) is not null
      and to_regclass(
        'public.provider_recovery_circuit_breaker_events_incident_idx'
      ) is not null,
    'circuit_breaker_rls_and_read_ready',
      coalesce((
        select class_row.relrowsecurity
        from pg_catalog.pg_class class_row
        where class_row.oid = 'public.provider_recovery_circuit_breakers'::regclass
      ), false)
      and coalesce((
        select class_row.relrowsecurity
        from pg_catalog.pg_class class_row
        where class_row.oid = 'public.provider_recovery_circuit_breaker_events'::regclass
      ), false)
      and has_table_privilege(
        'authenticated', 'public.provider_recovery_circuit_breakers', 'SELECT'
      )
      and has_table_privilege(
        'authenticated', 'public.provider_recovery_circuit_breaker_events', 'SELECT'
      )
      and exists (
        select 1
        from pg_catalog.pg_policies policy_row
        where policy_row.schemaname = 'public'
          and policy_row.tablename = 'provider_recovery_circuit_breakers'
          and policy_row.policyname =
            'provider_recovery_circuit_breakers_read_directors'
          and policy_row.cmd = 'SELECT'
      )
      and exists (
        select 1
        from pg_catalog.pg_policies policy_row
        where policy_row.schemaname = 'public'
          and policy_row.tablename = 'provider_recovery_circuit_breaker_events'
          and policy_row.policyname =
            'provider_recovery_circuit_breaker_events_read_directors'
          and policy_row.cmd = 'SELECT'
      ),
    'authenticated_circuit_writes_blocked',
      not has_table_privilege(
        'authenticated', 'public.provider_recovery_circuit_breakers', 'INSERT'
      )
      and not has_table_privilege(
        'authenticated', 'public.provider_recovery_circuit_breakers', 'UPDATE'
      )
      and not has_table_privilege(
        'authenticated', 'public.provider_recovery_circuit_breaker_events', 'INSERT'
      ),
    'service_role_circuit_write_ready',
      has_table_privilege(
        'service_role', 'public.provider_recovery_circuit_breakers', 'INSERT'
      )
      and has_table_privilege(
        'service_role', 'public.provider_recovery_circuit_breakers', 'UPDATE'
      )
      and has_table_privilege(
        'service_role', 'public.provider_recovery_circuit_breaker_events', 'INSERT'
      ),
    'circuit_revision_guard_ready',
      to_regprocedure(
        'public.prepare_provider_recovery_circuit_breaker_v1()'
      ) is not null
      and exists (
        select 1
        from pg_catalog.pg_trigger trigger_row
        where trigger_row.tgname = 'provider_recovery_circuit_breaker_revision_guard'
          and trigger_row.tgrelid =
            'public.provider_recovery_circuit_breakers'::regclass
          and not trigger_row.tgisinternal
      ),
    'circuit_event_writer_ready',
      to_regprocedure(
        'public.record_provider_recovery_circuit_breaker_event_v1()'
      ) is not null
      and exists (
        select 1
        from pg_catalog.pg_trigger trigger_row
        where trigger_row.tgname = 'provider_recovery_circuit_breaker_event_writer'
          and trigger_row.tgrelid =
            'public.provider_recovery_circuit_breakers'::regclass
          and not trigger_row.tgisinternal
      ),
    'circuit_event_immutability_ready',
      to_regprocedure(
        'public.prevent_provider_recovery_circuit_breaker_event_mutation_v1()'
      ) is not null
      and exists (
        select 1
        from pg_catalog.pg_trigger trigger_row
        where trigger_row.tgname = 'provider_recovery_circuit_breaker_events_immutable'
          and trigger_row.tgrelid =
            'public.provider_recovery_circuit_breaker_events'::regclass
          and not trigger_row.tgisinternal
      ),
    'circuit_opener_ready',
      to_regprocedure('public.open_provider_recovery_circuit_breaker_v1()')
        is not null
      and exists (
        select 1
        from pg_catalog.pg_trigger trigger_row
        where trigger_row.tgname = 'provider_recovery_circuit_breaker_opener'
          and trigger_row.tgrelid =
            'public.provider_recovery_retry_schedules'::regclass
          and not trigger_row.tgisinternal
      ),
    'recovery_request_circuit_guard_ready',
      to_regprocedure('public.guard_provider_recovery_request_circuit_v1()')
        is not null
      and exists (
        select 1
        from pg_catalog.pg_trigger trigger_row
        where trigger_row.tgname = 'provider_recovery_request_circuit_guard'
          and trigger_row.tgrelid = 'public.provider_recovery_requests'::regclass
          and not trigger_row.tgisinternal
      ),
    'incident_circuit_resolver_ready',
      to_regprocedure('public.resolve_provider_recovery_circuit_breaker_v1()')
        is not null
      and exists (
        select 1
        from pg_catalog.pg_trigger trigger_row
        where trigger_row.tgname =
          'provider_recovery_circuit_breaker_incident_resolver'
          and trigger_row.tgrelid =
            'public.provider_operational_incidents'::regclass
          and not trigger_row.tgisinternal
      ),
    'circuit_release_rpc_ready',
      to_regprocedure(
        'public.release_provider_recovery_circuit_breaker_guarded_v1(uuid,uuid,bigint,text,uuid)'
      ) is not null
      and has_function_privilege(
        'authenticated',
        'public.release_provider_recovery_circuit_breaker_guarded_v1(uuid,uuid,bigint,text,uuid)',
        'EXECUTE'
      )
      and not has_function_privilege(
        'anon',
        'public.release_provider_recovery_circuit_breaker_guarded_v1(uuid,uuid,bigint,text,uuid)',
        'EXECUTE'
      ),
    'circuit_center_ready',
      to_regprocedure(
        'public.get_league_provider_circuit_breaker_center_v1(uuid)'
      ) is not null
      and has_function_privilege(
        'authenticated',
        'public.get_league_provider_circuit_breaker_center_v1(uuid)',
        'EXECUTE'
      ),
    'retry_center_v2_ready',
      to_regprocedure('public.get_league_provider_retry_center_v2(uuid)')
        is not null
      and has_function_privilege(
        'authenticated',
        'public.get_league_provider_retry_center_v2(uuid)',
        'EXECUTE'
      ),
    'recovery_center_v5_ready',
      to_regprocedure('public.get_league_provider_recovery_center_v5(uuid)')
        is not null
      and has_function_privilege(
        'authenticated',
        'public.get_league_provider_recovery_center_v5(uuid)',
        'EXECUTE'
      ),
    'provider_health_v8_ready',
      to_regprocedure('public.get_league_provider_sync_health_v8(uuid)')
        is not null
      and has_function_privilege(
        'authenticated',
        'public.get_league_provider_sync_health_v8(uuid)',
        'EXECUTE'
      ),
    'circuit_realtime_ready',
      exists (
        select 1
        from pg_catalog.pg_publication_tables publication_table
        where publication_table.pubname = 'supabase_realtime'
          and publication_table.schemaname = 'public'
          and publication_table.tablename =
            'provider_recovery_circuit_breaker_events'
      ),
    'provider_recovery_continuity_ready',
      to_regprocedure('public.claim_next_provider_recovery_request_v3()')
        is not null
      and to_regprocedure(
        'public.request_provider_recovery_guarded_v1(uuid,uuid,bigint,uuid)'
      ) is not null
      and to_regprocedure(
        'public.get_provider_recovery_retry_backoff_integrity_v1()'
      ) is not null
  );
$$;

revoke all on function public.get_provider_recovery_circuit_breaker_integrity_v1()
from public, anon, authenticated;
grant execute on function public.get_provider_recovery_circuit_breaker_integrity_v1()
to authenticated, service_role;

-- Arresta la transazione indicando i nomi esatti degli eventuali controlli falsi.
do $validation$
declare
  v_checks jsonb := public.get_provider_recovery_circuit_breaker_integrity_v1();
  v_failed text[];
begin
  select array_agg(check_row.key order by check_row.key)
  into v_failed
  from jsonb_each(v_checks) check_row
  where jsonb_typeof(check_row.value) is distinct from 'boolean'
    or check_row.value is distinct from 'true'::jsonb;

  if coalesce(array_length(v_failed, 1), 0) > 0 then
    raise exception
      'Validazione v0.62.9 non superata. Controlli falsi: %',
      array_to_string(v_failed, '; ');
  end if;
end;
$validation$;

commit;

-- Diagnostica finale: devono comparire esattamente 20 valori true.
select
  (checks ->> 'circuit_breaker_tables_ready')::boolean
    as circuit_breaker_tables_ready,
  (checks ->> 'circuit_breaker_columns_ready')::boolean
    as circuit_breaker_columns_ready,
  (checks ->> 'circuit_breaker_event_columns_ready')::boolean
    as circuit_breaker_event_columns_ready,
  (checks ->> 'circuit_breaker_indexes_ready')::boolean
    as circuit_breaker_indexes_ready,
  (checks ->> 'circuit_breaker_rls_and_read_ready')::boolean
    as circuit_breaker_rls_and_read_ready,
  (checks ->> 'authenticated_circuit_writes_blocked')::boolean
    as authenticated_circuit_writes_blocked,
  (checks ->> 'service_role_circuit_write_ready')::boolean
    as service_role_circuit_write_ready,
  (checks ->> 'circuit_revision_guard_ready')::boolean
    as circuit_revision_guard_ready,
  (checks ->> 'circuit_event_writer_ready')::boolean
    as circuit_event_writer_ready,
  (checks ->> 'circuit_event_immutability_ready')::boolean
    as circuit_event_immutability_ready,
  (checks ->> 'circuit_opener_ready')::boolean
    as circuit_opener_ready,
  (checks ->> 'recovery_request_circuit_guard_ready')::boolean
    as recovery_request_circuit_guard_ready,
  (checks ->> 'incident_circuit_resolver_ready')::boolean
    as incident_circuit_resolver_ready,
  (checks ->> 'circuit_release_rpc_ready')::boolean
    as circuit_release_rpc_ready,
  (checks ->> 'circuit_center_ready')::boolean
    as circuit_center_ready,
  (checks ->> 'retry_center_v2_ready')::boolean
    as retry_center_v2_ready,
  (checks ->> 'recovery_center_v5_ready')::boolean
    as recovery_center_v5_ready,
  (checks ->> 'provider_health_v8_ready')::boolean
    as provider_health_v8_ready,
  (checks ->> 'circuit_realtime_ready')::boolean
    as circuit_realtime_ready,
  (checks ->> 'provider_recovery_continuity_ready')::boolean
    as provider_recovery_continuity_ready
from (
  select public.get_provider_recovery_circuit_breaker_integrity_v1() as checks
) diagnostic;
