-- LEGHEVO v0.61.6 · Centro Notifiche protetto
-- Migrazione interna: database/100_notification_center_safety.sql
--
-- Obiettivi:
-- - lettura singola e lettura massiva atomiche e idempotenti;
-- - stato revisionato e impronta certificata di ogni notifica;
-- - registro immutabile delle azioni dell'utente;
-- - continuità Realtime e protezione dalle scritture dirette;
-- - compatibilità con le RPC storiche e con la coda push esistente.

begin;

-- Preflight dettagliato: nessuna modifica viene eseguita quando manca una
-- dipendenza necessaria al percorso protetto.
do $preflight$
declare
  v_missing text[] := array[]::text[];
  v_expected record;
begin
  if to_regclass('public.user_notifications') is null then
    v_missing := array_append(v_missing, 'table public.user_notifications');
  end if;
  if to_regclass('public.profiles') is null then
    v_missing := array_append(v_missing, 'table public.profiles');
  end if;
  if to_regprocedure('public.leghevo_sha256_hex_v1(text)') is null then
    v_missing := array_append(v_missing, 'function public.leghevo_sha256_hex_v1(text)');
  end if;
  if to_regprocedure('public.create_user_notification(uuid,uuid,text,text,text,text,jsonb,text)') is null then
    v_missing := array_append(
      v_missing,
      'function public.create_user_notification(uuid,uuid,text,text,text,text,jsonb,text)'
    );
  end if;
  if to_regprocedure('public.mark_notification_read(uuid)') is null then
    v_missing := array_append(v_missing, 'function public.mark_notification_read(uuid)');
  end if;
  if to_regprocedure('public.mark_all_notifications_read()') is null then
    v_missing := array_append(v_missing, 'function public.mark_all_notifications_read()');
  end if;

  for v_expected in
    select *
    from (values
      ('public', 'user_notifications', 'id'),
      ('public', 'user_notifications', 'user_id'),
      ('public', 'user_notifications', 'league_id'),
      ('public', 'user_notifications', 'kind'),
      ('public', 'user_notifications', 'title'),
      ('public', 'user_notifications', 'body'),
      ('public', 'user_notifications', 'action_screen'),
      ('public', 'user_notifications', 'metadata'),
      ('public', 'user_notifications', 'dedupe_key'),
      ('public', 'user_notifications', 'read_at'),
      ('public', 'user_notifications', 'created_at'),
      ('public', 'profiles', 'id')
    ) as expected(table_schema, table_name, column_name)
  loop
    if not exists (
      select 1
      from information_schema.columns column_row
      where column_row.table_schema = v_expected.table_schema
        and column_row.table_name = v_expected.table_name
        and column_row.column_name = v_expected.column_name
    ) then
      v_missing := array_append(
        v_missing,
        format(
          'column %I.%I.%I',
          v_expected.table_schema,
          v_expected.table_name,
          v_expected.column_name
        )
      );
    end if;
  end loop;

  if coalesce(array_length(v_missing, 1), 0) > 0 then
    raise exception
      'Preflight v0.61.6 non superato. Oggetti mancanti: %',
      array_to_string(v_missing, '; ');
  end if;
end;
$preflight$;

alter table public.user_notifications
  add column if not exists revision bigint not null default 1,
  add column if not exists state_fingerprint text,
  add column if not exists last_action_request_id uuid;

alter table public.user_notifications
  drop constraint if exists user_notifications_revision_check;
alter table public.user_notifications
  add constraint user_notifications_revision_check
  check (revision > 0);

create or replace function public.notification_state_fingerprint_v1(
  p_notification_id uuid,
  p_user_id uuid,
  p_read_at timestamptz,
  p_revision bigint
)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select public.leghevo_sha256_hex_v1(
    concat_ws(
      E'\n',
      coalesce(p_notification_id::text, ''),
      coalesce(p_user_id::text, ''),
      coalesce(extract(epoch from p_read_at)::text, 'unread'),
      greatest(coalesce(p_revision, 1), 1)::text
    )
  )
$$;

revoke all on function public.notification_state_fingerprint_v1(
  uuid, uuid, timestamptz, bigint
) from public, anon, authenticated;

update public.user_notifications notification
set
  revision = greatest(notification.revision, 1),
  state_fingerprint = public.notification_state_fingerprint_v1(
    notification.id,
    notification.user_id,
    notification.read_at,
    greatest(notification.revision, 1)
  )
where notification.revision <= 0
   or notification.state_fingerprint is null
   or char_length(notification.state_fingerprint) <> 64;

alter table public.user_notifications
  alter column state_fingerprint set not null;

alter table public.user_notifications
  drop constraint if exists user_notifications_state_fingerprint_check;
alter table public.user_notifications
  add constraint user_notifications_state_fingerprint_check
  check (char_length(state_fingerprint) = 64);

create or replace function public.maintain_user_notification_state_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    new.revision := greatest(coalesce(new.revision, 1), 1);
  else
    if old.read_at is not null and new.read_at is null then
      raise exception 'Una notifica letta non può tornare non letta.';
    end if;

    if new.read_at is distinct from old.read_at
      or new.last_action_request_id is distinct from old.last_action_request_id then
      new.revision := old.revision + 1;
    else
      new.revision := old.revision;
    end if;
  end if;

  new.state_fingerprint := public.notification_state_fingerprint_v1(
    new.id,
    new.user_id,
    new.read_at,
    new.revision
  );

  return new;
end;
$$;

revoke all on function public.maintain_user_notification_state_v1()
from public, anon, authenticated;

drop trigger if exists user_notifications_state_guard
on public.user_notifications;
create trigger user_notifications_state_guard
before insert or update of read_at, last_action_request_id
on public.user_notifications
for each row execute function public.maintain_user_notification_state_v1();

create table if not exists public.notification_action_runs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  notification_id uuid references public.user_notifications(id) on delete cascade,
  action_type text not null check (
    action_type in ('mark_read', 'mark_all_read')
  ),
  idempotency_key uuid not null,
  previous_revision bigint not null check (previous_revision >= 0),
  result_revision bigint not null check (result_revision >= 0),
  affected_count integer not null check (affected_count >= 0),
  request_fingerprint text not null check (char_length(request_fingerprint) = 64),
  result_fingerprint text not null check (char_length(result_fingerprint) = 64),
  result_snapshot jsonb not null check (jsonb_typeof(result_snapshot) = 'object'),
  created_at timestamptz not null default now(),
  unique (user_id, idempotency_key)
);

create index if not exists notification_action_runs_user_idx
  on public.notification_action_runs (user_id, created_at desc);
create index if not exists notification_action_runs_notification_idx
  on public.notification_action_runs (notification_id, created_at desc)
  where notification_id is not null;

alter table public.notification_action_runs enable row level security;
alter table public.notification_action_runs replica identity full;

drop policy if exists notification_action_runs_read_own
on public.notification_action_runs;
create policy notification_action_runs_read_own
on public.notification_action_runs
for select to authenticated
using (user_id = auth.uid());

revoke all on table public.notification_action_runs
from public, anon, authenticated;
grant select on table public.notification_action_runs
to authenticated;

create or replace function public.prevent_notification_action_run_mutation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- La cancellazione a cascata dovuta alla rimozione dell'account deve poter
  -- completare il diritto all'oblio.
  if tg_op = 'DELETE' and pg_trigger_depth() > 1 then
    return old;
  end if;

  raise exception
    'Azione notifiche certificata: modifica o cancellazione diretta non consentita.';
end;
$$;

revoke all on function public.prevent_notification_action_run_mutation()
from public, anon, authenticated;

drop trigger if exists notification_action_runs_immutable
on public.notification_action_runs;
create trigger notification_action_runs_immutable
before update or delete on public.notification_action_runs
for each row execute function public.prevent_notification_action_run_mutation();

create or replace function public.mark_notification_read_guarded_v1(
  p_notification_id uuid,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_existing jsonb;
  v_notification public.user_notifications%rowtype;
  v_previous_revision bigint;
  v_affected integer := 0;
  v_read_at timestamptz;
  v_request_fingerprint text;
  v_result_snapshot jsonb;
begin
  if v_user_id is null then
    raise exception 'Devi effettuare l''accesso.';
  end if;
  if p_notification_id is null then
    raise exception 'Notifica non valida.';
  end if;
  if p_idempotency_key is null then
    raise exception 'Identificativo operazione mancante.';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'leghevo:notification:' || v_user_id::text || ':' || p_notification_id::text,
      0
    )
  );

  select run.result_snapshot
  into v_existing
  from public.notification_action_runs run
  where run.user_id = v_user_id
    and run.idempotency_key = p_idempotency_key;

  if found then
    return v_existing;
  end if;

  select notification.*
  into v_notification
  from public.user_notifications notification
  where notification.id = p_notification_id
    and notification.user_id = v_user_id
  for update;

  if not found then
    raise exception 'Notifica non trovata.';
  end if;

  v_previous_revision := v_notification.revision;
  v_request_fingerprint := public.leghevo_sha256_hex_v1(
    concat_ws(
      E'\n',
      'mark_read',
      v_user_id::text,
      p_notification_id::text,
      p_idempotency_key::text,
      v_notification.state_fingerprint
    )
  );

  if v_notification.read_at is null then
    update public.user_notifications notification
    set
      read_at = clock_timestamp(),
      last_action_request_id = p_idempotency_key
    where notification.id = p_notification_id
      and notification.user_id = v_user_id
    returning notification.* into v_notification;

    v_affected := 1;
  end if;

  v_read_at := v_notification.read_at;
  v_result_snapshot := jsonb_build_object(
    'notificationId', v_notification.id,
    'readAt', v_read_at,
    'revision', v_notification.revision,
    'stateFingerprint', v_notification.state_fingerprint,
    'affectedCount', v_affected,
    'protected', true
  );

  insert into public.notification_action_runs (
    user_id,
    notification_id,
    action_type,
    idempotency_key,
    previous_revision,
    result_revision,
    affected_count,
    request_fingerprint,
    result_fingerprint,
    result_snapshot
  )
  values (
    v_user_id,
    v_notification.id,
    'mark_read',
    p_idempotency_key,
    v_previous_revision,
    v_notification.revision,
    v_affected,
    v_request_fingerprint,
    v_notification.state_fingerprint,
    v_result_snapshot
  );

  return v_result_snapshot;
end;
$$;

revoke all on function public.mark_notification_read_guarded_v1(uuid, uuid)
from public, anon;
grant execute on function public.mark_notification_read_guarded_v1(uuid, uuid)
to authenticated;

create or replace function public.mark_all_notifications_read_guarded_v1(
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_existing jsonb;
  v_previous_revision bigint := 0;
  v_result_revision bigint := 0;
  v_affected integer := 0;
  v_remaining_unread integer := 0;
  v_notification_ids text := '';
  v_state_chain text := '';
  v_read_at timestamptz := clock_timestamp();
  v_request_fingerprint text;
  v_result_fingerprint text;
  v_result_snapshot jsonb;
begin
  if v_user_id is null then
    raise exception 'Devi effettuare l''accesso.';
  end if;
  if p_idempotency_key is null then
    raise exception 'Identificativo operazione mancante.';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'leghevo:notification-inbox:' || v_user_id::text,
      0
    )
  );

  select run.result_snapshot
  into v_existing
  from public.notification_action_runs run
  where run.user_id = v_user_id
    and run.idempotency_key = p_idempotency_key;

  if found then
    return v_existing;
  end if;

  select
    coalesce(max(notification.revision), 0),
    coalesce(string_agg(notification.id::text, ',' order by notification.id), '')
  into v_previous_revision, v_notification_ids
  from public.user_notifications notification
  where notification.user_id = v_user_id
    and notification.read_at is null;

  v_request_fingerprint := public.leghevo_sha256_hex_v1(
    concat_ws(
      E'\n',
      'mark_all_read',
      v_user_id::text,
      p_idempotency_key::text,
      v_notification_ids
    )
  );

  update public.user_notifications notification
  set
    read_at = v_read_at,
    last_action_request_id = p_idempotency_key
  where notification.user_id = v_user_id
    and notification.read_at is null;

  get diagnostics v_affected = row_count;

  select
    coalesce(max(notification.revision), 0),
    (count(*) filter (where notification.read_at is null))::integer,
    coalesce(
      string_agg(notification.state_fingerprint, '' order by notification.id),
      ''
    )
  into v_result_revision, v_remaining_unread, v_state_chain
  from public.user_notifications notification
  where notification.user_id = v_user_id;

  v_result_fingerprint := public.leghevo_sha256_hex_v1(
    concat_ws(
      E'\n',
      v_user_id::text,
      p_idempotency_key::text,
      v_affected::text,
      v_remaining_unread::text,
      v_state_chain
    )
  );

  v_result_snapshot := jsonb_build_object(
    'affectedCount', v_affected,
    'readAt', case when v_affected > 0 then v_read_at else null end,
    'unreadCount', v_remaining_unread,
    'resultRevision', v_result_revision,
    'resultFingerprint', v_result_fingerprint,
    'protected', true
  );

  insert into public.notification_action_runs (
    user_id,
    notification_id,
    action_type,
    idempotency_key,
    previous_revision,
    result_revision,
    affected_count,
    request_fingerprint,
    result_fingerprint,
    result_snapshot
  )
  values (
    v_user_id,
    null,
    'mark_all_read',
    p_idempotency_key,
    v_previous_revision,
    v_result_revision,
    v_affected,
    v_request_fingerprint,
    v_result_fingerprint,
    v_result_snapshot
  );

  return v_result_snapshot;
end;
$$;

revoke all on function public.mark_all_notifications_read_guarded_v1(uuid)
from public, anon;
grant execute on function public.mark_all_notifications_read_guarded_v1(uuid)
to authenticated;

create or replace function public.get_my_notification_center_v2(
  p_limit integer default 60
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_limit integer := least(greatest(coalesce(p_limit, 60), 1), 100);
  v_notifications jsonb := '[]'::jsonb;
  v_unread_count integer := 0;
  v_total_count integer := 0;
  v_action_count integer := 0;
  v_last_certified_at timestamptz;
begin
  if v_user_id is null then
    raise exception 'Devi effettuare l''accesso.';
  end if;

  select coalesce(jsonb_agg(item.payload order by item.created_at desc), '[]'::jsonb)
  into v_notifications
  from (
    select
      notification.created_at,
      jsonb_build_object(
        'id', notification.id,
        'leagueId', notification.league_id,
        'kind', notification.kind,
        'title', notification.title,
        'body', notification.body,
        'actionScreen', notification.action_screen,
        'metadata', notification.metadata,
        'readAt', notification.read_at,
        'createdAt', notification.created_at,
        'revision', notification.revision,
        'stateFingerprint', notification.state_fingerprint,
        'protected', true
      ) as payload
    from public.user_notifications notification
    where notification.user_id = v_user_id
    order by notification.created_at desc, notification.id desc
    limit v_limit
  ) item;

  select
    count(*)::integer,
    (count(*) filter (where notification.read_at is null))::integer
  into v_total_count, v_unread_count
  from public.user_notifications notification
  where notification.user_id = v_user_id;

  select count(*)::integer, max(run.created_at)
  into v_action_count, v_last_certified_at
  from public.notification_action_runs run
  where run.user_id = v_user_id;

  return jsonb_build_object(
    'notifications', v_notifications,
    'unreadCount', v_unread_count,
    'totalCount', v_total_count,
    'protected', true,
    'certifiedActionCount', v_action_count,
    'lastCertifiedAt', v_last_certified_at
  );
end;
$$;

revoke all on function public.get_my_notification_center_v2(integer)
from public, anon;
grant execute on function public.get_my_notification_center_v2(integer)
to authenticated;

-- Compatibilità: le RPC storiche conservano firma e tipo di ritorno, ma
-- instradano ogni azione attraverso il percorso protetto.
create or replace function public.mark_notification_read(
  p_notification_id uuid
)
returns timestamptz
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_result jsonb;
begin
  v_result := public.mark_notification_read_guarded_v1(
    p_notification_id,
    gen_random_uuid()
  );
  return (v_result ->> 'readAt')::timestamptz;
end;
$$;

create or replace function public.mark_all_notifications_read()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_result jsonb;
begin
  v_result := public.mark_all_notifications_read_guarded_v1(
    gen_random_uuid()
  );
  return coalesce((v_result ->> 'affectedCount')::integer, 0);
end;
$$;

revoke all on function public.mark_notification_read(uuid)
from public, anon;
revoke all on function public.mark_all_notifications_read()
from public, anon;
grant execute on function public.mark_notification_read(uuid)
to authenticated;
grant execute on function public.mark_all_notifications_read()
to authenticated;

-- Le letture restano permesse; ogni scrittura dell'utente passa dalle RPC.
drop policy if exists user_notifications_update_own
on public.user_notifications;
revoke insert, update, delete on table public.user_notifications
from authenticated;
revoke update (read_at) on table public.user_notifications
from authenticated;
grant select on table public.user_notifications
to authenticated;

-- Realtime idempotente per inbox e registro certificato.
do $realtime$
declare
  v_table_name text;
begin
  if exists (
    select 1
    from pg_catalog.pg_publication publication
    where publication.pubname = 'supabase_realtime'
  ) then
    foreach v_table_name in array array[
      'user_notifications',
      'notification_action_runs'
    ]
    loop
      if not exists (
        select 1
        from pg_catalog.pg_publication_tables publication_table
        where publication_table.pubname = 'supabase_realtime'
          and publication_table.schemaname = 'public'
          and publication_table.tablename = v_table_name
      ) then
        execute format(
          'alter publication supabase_realtime add table public.%I',
          v_table_name
        );
      end if;
    end loop;
  end if;
end;
$realtime$;

create or replace function public.get_notification_center_safety_integrity_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_realtime_ready boolean;
begin
  select
    not exists (
      select 1
      from pg_catalog.pg_publication publication
      where publication.pubname = 'supabase_realtime'
    )
    or (
      select count(*) = 2
      from (values
        ('user_notifications'),
        ('notification_action_runs')
      ) expected(table_name)
      where exists (
        select 1
        from pg_catalog.pg_publication_tables publication_table
        where publication_table.pubname = 'supabase_realtime'
          and publication_table.schemaname = 'public'
          and publication_table.tablename = expected.table_name
      )
    )
  into v_realtime_ready;

  return jsonb_build_object(
    'notificationRevisionReady', exists (
      select 1 from information_schema.columns column_row
      where column_row.table_schema = 'public'
        and column_row.table_name = 'user_notifications'
        and column_row.column_name = 'revision'
        and column_row.is_nullable = 'NO'
    ),
    'notificationFingerprintReady', exists (
      select 1 from information_schema.columns column_row
      where column_row.table_schema = 'public'
        and column_row.table_name = 'user_notifications'
        and column_row.column_name = 'state_fingerprint'
        and column_row.is_nullable = 'NO'
    ),
    'notificationRequestKeyReady', exists (
      select 1 from information_schema.columns column_row
      where column_row.table_schema = 'public'
        and column_row.table_name = 'user_notifications'
        and column_row.column_name = 'last_action_request_id'
    ),
    'actionRunsReady', to_regclass('public.notification_action_runs') is not null,
    'actionRunsColumnsReady', (
      select count(*) = 12
      from information_schema.columns column_row
      where column_row.table_schema = 'public'
        and column_row.table_name = 'notification_action_runs'
        and column_row.column_name in (
          'id', 'user_id', 'notification_id', 'action_type',
          'idempotency_key', 'previous_revision', 'result_revision',
          'affected_count', 'request_fingerprint', 'result_fingerprint',
          'result_snapshot', 'created_at'
        )
    ),
    'actionRunsRlsReady', coalesce((
      select class.relrowsecurity
      from pg_catalog.pg_class class
      where class.oid = to_regclass('public.notification_action_runs')
    ), false),
    'actionRunsReadPolicyReady', exists (
      select 1 from pg_catalog.pg_policies policy
      where policy.schemaname = 'public'
        and policy.tablename = 'notification_action_runs'
        and policy.policyname = 'notification_action_runs_read_own'
    ),
    'actionRunsImmutable', exists (
      select 1 from pg_catalog.pg_trigger trigger_row
      where trigger_row.tgrelid = to_regclass('public.notification_action_runs')
        and trigger_row.tgname = 'notification_action_runs_immutable'
        and not trigger_row.tgisinternal
    ),
    'notificationStateTriggerReady', exists (
      select 1 from pg_catalog.pg_trigger trigger_row
      where trigger_row.tgrelid = to_regclass('public.user_notifications')
        and trigger_row.tgname = 'user_notifications_state_guard'
        and not trigger_row.tgisinternal
    ),
    'fingerprintHelperReady', to_regprocedure(
      'public.notification_state_fingerprint_v1(uuid,uuid,timestamptz,bigint)'
    ) is not null,
    'guardedSingleReadReady', to_regprocedure(
      'public.mark_notification_read_guarded_v1(uuid,uuid)'
    ) is not null,
    'guardedReadAllReady', to_regprocedure(
      'public.mark_all_notifications_read_guarded_v1(uuid)'
    ) is not null,
    'centerV2Ready', to_regprocedure(
      'public.get_my_notification_center_v2(integer)'
    ) is not null,
    'legacyRoutesGuarded', coalesce(
      pg_get_functiondef(to_regprocedure('public.mark_notification_read(uuid)'))
        ilike '%mark_notification_read_guarded_v1%'
      and pg_get_functiondef(to_regprocedure('public.mark_all_notifications_read()'))
        ilike '%mark_all_notifications_read_guarded_v1%',
      false
    ),
    'notificationRowsConsistent', not exists (
      select 1
      from public.user_notifications notification
      where notification.revision <= 0
         or notification.state_fingerprint is null
         or char_length(notification.state_fingerprint) <> 64
         or notification.state_fingerprint <> public.notification_state_fingerprint_v1(
           notification.id,
           notification.user_id,
           notification.read_at,
           notification.revision
         )
    ),
    'authenticatedAccessReady',
      has_function_privilege(
        'authenticated',
        'public.mark_notification_read_guarded_v1(uuid,uuid)',
        'EXECUTE'
      )
      and has_function_privilege(
        'authenticated',
        'public.mark_all_notifications_read_guarded_v1(uuid)',
        'EXECUTE'
      )
      and has_function_privilege(
        'authenticated',
        'public.get_my_notification_center_v2(integer)',
        'EXECUTE'
      ),
    'anonymousBlocked',
      not has_function_privilege(
        'anon',
        'public.mark_notification_read_guarded_v1(uuid,uuid)',
        'EXECUTE'
      )
      and not has_function_privilege(
        'anon',
        'public.mark_all_notifications_read_guarded_v1(uuid)',
        'EXECUTE'
      )
      and not has_function_privilege(
        'anon',
        'public.get_my_notification_center_v2(integer)',
        'EXECUTE'
      ),
    'directWritesBlocked',
      not has_table_privilege(
        'authenticated', 'public.user_notifications', 'INSERT,UPDATE,DELETE'
      )
      and not has_column_privilege(
        'authenticated', 'public.user_notifications', 'read_at', 'UPDATE'
      )
      and not has_table_privilege(
        'authenticated', 'public.notification_action_runs', 'INSERT,UPDATE,DELETE'
      ),
    'realtimeReady', v_realtime_ready,
    'notificationCreationPreserved', to_regprocedure(
      'public.create_user_notification(uuid,uuid,text,text,text,text,jsonb,text)'
    ) is not null,
    'pushDeliveryContinuityReady',
      to_regclass('public.notification_push_deliveries') is null
      or exists (
        select 1 from pg_catalog.pg_trigger trigger_row
        where trigger_row.tgrelid = to_regclass('public.user_notifications')
          and trigger_row.tgname = 'user_notification_enqueue_push'
          and not trigger_row.tgisinternal
      )
  );
end;
$$;

revoke all on function public.get_notification_center_safety_integrity_v1()
from public, anon;
grant execute on function public.get_notification_center_safety_integrity_v1()
to authenticated, service_role;

-- Validazione transazionale con dettaglio delle condizioni false.
do $validation$
declare
  v_integrity jsonb;
  v_failures jsonb;
begin
  v_integrity := public.get_notification_center_safety_integrity_v1();

  select coalesce(jsonb_object_agg(entry.key, entry.value), '{}'::jsonb)
  into v_failures
  from jsonb_each(v_integrity) entry
  where entry.value <> 'true'::jsonb;

  if v_failures <> '{}'::jsonb then
    raise exception
      'Validazione v0.61.6 non superata. Controlli falsi: %',
      v_failures;
  end if;
end;
$validation$;

commit;

-- Diagnostica finale: devono comparire esattamente 20 valori true.
select
  (integrity ->> 'notificationRevisionReady')::boolean
    as notification_revision_ready,
  (integrity ->> 'notificationFingerprintReady')::boolean
    as notification_fingerprint_ready,
  (integrity ->> 'notificationRequestKeyReady')::boolean
    as notification_request_key_ready,
  (integrity ->> 'actionRunsReady')::boolean
    as notification_action_runs_ready,
  (integrity ->> 'actionRunsColumnsReady')::boolean
    as notification_action_runs_columns_ready,
  (integrity ->> 'actionRunsRlsReady')::boolean
    as notification_action_runs_rls_ready,
  (integrity ->> 'actionRunsReadPolicyReady')::boolean
    as notification_action_runs_read_policy_ready,
  (integrity ->> 'actionRunsImmutable')::boolean
    as notification_action_runs_immutable,
  (integrity ->> 'notificationStateTriggerReady')::boolean
    as notification_state_trigger_ready,
  (integrity ->> 'fingerprintHelperReady')::boolean
    as notification_fingerprint_helper_ready,
  (integrity ->> 'guardedSingleReadReady')::boolean
    as notification_guarded_single_read_ready,
  (integrity ->> 'guardedReadAllReady')::boolean
    as notification_guarded_read_all_ready,
  (integrity ->> 'centerV2Ready')::boolean
    as notification_center_v2_ready,
  (integrity ->> 'legacyRoutesGuarded')::boolean
    as notification_legacy_routes_guarded,
  (integrity ->> 'notificationRowsConsistent')::boolean
    as notification_rows_consistent,
  (integrity ->> 'authenticatedAccessReady')::boolean
    as notification_authenticated_access_ready,
  (integrity ->> 'anonymousBlocked')::boolean
    as notification_anonymous_blocked,
  (integrity ->> 'directWritesBlocked')::boolean
    as notification_direct_writes_blocked,
  (integrity ->> 'realtimeReady')::boolean
    as notification_realtime_ready,
  (
    (integrity ->> 'notificationCreationPreserved')::boolean
    and (integrity ->> 'pushDeliveryContinuityReady')::boolean
  ) as notification_delivery_continuity_ready
from (
  select public.get_notification_center_safety_integrity_v1() as integrity
) diagnostics;
