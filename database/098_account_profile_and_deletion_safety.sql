-- LEGHEVO v0.61.4 · Profilo e cancellazione account protetti
-- Migrazione interna: database/098_account_profile_and_deletion_safety.sql
--
-- Obiettivi:
-- - aggiornamento profilo atomico, idempotente e revisionato;
-- - allineamento transazionale tra public.profiles e auth.users metadata;
-- - cancellazione account protetta contro richieste concorrenti;
-- - disattivazione definitiva di notifiche e dispositivi push;
-- - registro immutabile delle operazioni account;
-- - compatibilità con le RPC storiche.

begin;

-- Preflight dettagliato: nessuna scrittura viene eseguita se manca una
-- dipendenza necessaria al percorso protetto.
do $preflight$
declare
  v_missing text[] := array[]::text[];
  v_expected record;
begin
  if to_regclass('public.profiles') is null then
    v_missing := array_append(v_missing, 'table public.profiles');
  end if;
  if to_regclass('public.leagues') is null then
    v_missing := array_append(v_missing, 'table public.leagues');
  end if;
  if to_regclass('public.league_members') is null then
    v_missing := array_append(v_missing, 'table public.league_members');
  end if;
  if to_regclass('public.user_notifications') is null then
    v_missing := array_append(v_missing, 'table public.user_notifications');
  end if;
  if to_regclass('public.user_notification_preferences') is null then
    v_missing := array_append(v_missing, 'table public.user_notification_preferences');
  end if;
  if to_regclass('public.user_push_devices') is null then
    v_missing := array_append(v_missing, 'table public.user_push_devices');
  end if;
  if to_regclass('public.notification_push_deliveries') is null then
    v_missing := array_append(v_missing, 'table public.notification_push_deliveries');
  end if;
  if to_regclass('auth.users') is null then
    v_missing := array_append(v_missing, 'table auth.users');
  end if;

  for v_expected in
    select *
    from (values
      ('public', 'profiles', 'id'),
      ('public', 'profiles', 'display_name'),
      ('public', 'profiles', 'avatar_url'),
      ('public', 'profiles', 'subscription'),
      ('public', 'profiles', 'created_at'),
      ('public', 'profiles', 'updated_at'),
      ('public', 'profiles', 'deleted_at'),
      ('public', 'leagues', 'id'),
      ('public', 'leagues', 'owner_id'),
      ('public', 'league_members', 'league_id'),
      ('public', 'league_members', 'user_id'),
      ('public', 'league_members', 'role'),
      ('public', 'league_members', 'joined_at'),
      ('public', 'user_notifications', 'user_id'),
      ('public', 'user_notification_preferences', 'user_id'),
      ('public', 'user_push_devices', 'user_id'),
      ('public', 'notification_push_deliveries', 'user_id'),
      ('auth', 'users', 'id'),
      ('auth', 'users', 'email'),
      ('auth', 'users', 'email_confirmed_at'),
      ('auth', 'users', 'raw_user_meta_data')
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
      'Preflight v0.61.4 non superato. Oggetti mancanti: %',
      array_to_string(v_missing, '; ');
  end if;
end;
$preflight$;

alter table public.profiles
  add column if not exists revision bigint not null default 1,
  add column if not exists profile_fingerprint text,
  add column if not exists last_profile_request_id uuid,
  add column if not exists deletion_request_id uuid;

update public.profiles profile
set profile_fingerprint = pg_catalog.md5(
  profile.display_name || E'\n' ||
  coalesce(profile.avatar_url, '') || E'\n' ||
  profile.subscription::text || E'\n' ||
  case when profile.deleted_at is null then 'active' else 'deleted' end
)
where profile.profile_fingerprint is null
   or char_length(profile.profile_fingerprint) <> 32;

alter table public.profiles
  alter column profile_fingerprint set not null;

alter table public.profiles
  drop constraint if exists profiles_revision_check;
alter table public.profiles
  add constraint profiles_revision_check check (revision > 0);

alter table public.profiles
  drop constraint if exists profiles_profile_fingerprint_check;
alter table public.profiles
  add constraint profiles_profile_fingerprint_check
  check (char_length(profile_fingerprint) = 32);

create table if not exists public.account_action_runs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete restrict,
  action_type text not null check (
    action_type in ('profile_update', 'account_delete')
  ),
  idempotency_key uuid not null,
  previous_revision bigint not null check (previous_revision > 0),
  result_revision bigint not null check (result_revision > 0),
  payload_fingerprint text not null check (
    char_length(payload_fingerprint) = 32
  ),
  result_snapshot jsonb not null check (
    jsonb_typeof(result_snapshot) = 'object'
  ),
  created_at timestamptz not null default now(),
  unique (user_id, idempotency_key)
);

create index if not exists account_action_runs_user_idx
  on public.account_action_runs (user_id, created_at desc);

alter table public.account_action_runs enable row level security;
alter table public.account_action_runs replica identity full;

drop policy if exists account_action_runs_read_own
on public.account_action_runs;
create policy account_action_runs_read_own
on public.account_action_runs
for select to authenticated
using (user_id = auth.uid());

revoke all on table public.account_action_runs
from public, anon, authenticated;
grant select on table public.account_action_runs
to authenticated;

create or replace function public.prevent_account_action_run_mutation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  raise exception
    'Operazione account certificata: modifica o cancellazione diretta non consentita.';
end;
$$;

revoke all on function public.prevent_account_action_run_mutation()
from public, anon, authenticated;

drop trigger if exists account_action_runs_immutable
on public.account_action_runs;
create trigger account_action_runs_immutable
before update or delete on public.account_action_runs
for each row execute function public.prevent_account_action_run_mutation();

create or replace function public.account_profile_payload_v1(
  p_user_id uuid
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'userId', profile.id,
    'displayName', profile.display_name,
    'email', auth_user.email,
    'emailVerified', auth_user.email_confirmed_at is not null,
    'revision', profile.revision,
    'profileFingerprint', profile.profile_fingerprint,
    'deletedAt', profile.deleted_at,
    'protected', true,
    'certifiedActionCount', (
      select count(*)::integer
      from public.account_action_runs action_run
      where action_run.user_id = profile.id
    ),
    'lastCertifiedAt', (
      select max(action_run.created_at)
      from public.account_action_runs action_run
      where action_run.user_id = profile.id
    )
  )
  from public.profiles profile
  left join auth.users auth_user on auth_user.id = profile.id
  where profile.id = p_user_id
$$;

revoke all on function public.account_profile_payload_v1(uuid)
from public, anon, authenticated;

create or replace function public.get_my_account_center_v2()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_payload jsonb;
begin
  if v_user_id is null then
    raise exception 'Devi effettuare l''accesso.';
  end if;

  select public.account_profile_payload_v1(v_user_id)
  into v_payload;

  if v_payload is null then
    raise exception 'Profilo non trovato.';
  end if;

  return v_payload || jsonb_build_object(
    'generatedAt', now(),
    'protection', jsonb_build_object(
      'guardedActionsReady', true,
      'revisionControlReady', true,
      'idempotencyReady', true,
      'authMetadataSyncReady', true
    )
  );
end;
$$;

create or replace function public.update_my_profile_guarded_v1(
  p_display_name text,
  p_expected_revision bigint,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_name text := trim(coalesce(p_display_name, ''));
  v_payload_fingerprint text;
  v_profile public.profiles%rowtype;
  v_existing public.account_action_runs%rowtype;
  v_result jsonb;
begin
  if v_user_id is null then
    raise exception 'Devi effettuare l''accesso.';
  end if;
  if p_idempotency_key is null then
    raise exception 'Identificativo operazione mancante.';
  end if;
  if char_length(v_name) not between 2 and 40 then
    raise exception 'Il nome deve contenere da 2 a 40 caratteri.';
  end if;
  if coalesce(p_expected_revision, 0) <= 0 then
    raise exception 'Revisione profilo non valida.';
  end if;

  v_payload_fingerprint := pg_catalog.md5(v_name);

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('leghevo:account:' || v_user_id::text, 0)
  );

  select action_run.*
  into v_existing
  from public.account_action_runs action_run
  where action_run.user_id = v_user_id
    and action_run.idempotency_key = p_idempotency_key;

  if v_existing.id is not null then
    if v_existing.action_type <> 'profile_update'
      or v_existing.payload_fingerprint <> v_payload_fingerprint then
      raise exception 'Identificativo operazione già utilizzato con dati differenti.';
    end if;
    return v_existing.result_snapshot;
  end if;

  select profile.*
  into v_profile
  from public.profiles profile
  where profile.id = v_user_id
  for update;

  if v_profile.id is null or v_profile.deleted_at is not null then
    raise exception 'Profilo non trovato.';
  end if;
  if v_profile.revision <> p_expected_revision then
    raise exception
      'Il profilo è stato aggiornato su un altro dispositivo. Ricarica e riprova.';
  end if;

  update public.profiles profile
  set
    display_name = v_name,
    revision = profile.revision + 1,
    profile_fingerprint = pg_catalog.md5(
      v_name || E'\n' ||
      coalesce(profile.avatar_url, '') || E'\n' ||
      profile.subscription::text || E'\nactive'
    ),
    last_profile_request_id = p_idempotency_key,
    updated_at = now()
  where profile.id = v_user_id
  returning * into v_profile;

  update auth.users auth_user
  set raw_user_meta_data =
    coalesce(auth_user.raw_user_meta_data, '{}'::jsonb)
    || jsonb_build_object('display_name', v_name)
  where auth_user.id = v_user_id;

  if not found then
    raise exception 'Account Auth non trovato.';
  end if;

  v_result := public.account_profile_payload_v1(v_user_id)
    || jsonb_build_object('changed', true);

  insert into public.account_action_runs (
    user_id,
    action_type,
    idempotency_key,
    previous_revision,
    result_revision,
    payload_fingerprint,
    result_snapshot
  )
  values (
    v_user_id,
    'profile_update',
    p_idempotency_key,
    p_expected_revision,
    v_profile.revision,
    v_payload_fingerprint,
    v_result
  );

  return v_result;
end;
$$;

create or replace function public.delete_my_account_guarded_v1(
  p_expected_revision bigint,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_payload_fingerprint text := pg_catalog.md5('account_delete');
  v_profile public.profiles%rowtype;
  v_existing public.account_action_runs%rowtype;
  v_league record;
  v_new_owner_id uuid;
  v_transferred_count integer := 0;
  v_deleted_league_count integer := 0;
  v_result jsonb;
begin
  if v_user_id is null then
    raise exception 'Devi effettuare l''accesso.';
  end if;
  if p_idempotency_key is null then
    raise exception 'Identificativo operazione mancante.';
  end if;
  if coalesce(p_expected_revision, 0) <= 0 then
    raise exception 'Revisione profilo non valida.';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('leghevo:account:' || v_user_id::text, 0)
  );

  select action_run.*
  into v_existing
  from public.account_action_runs action_run
  where action_run.user_id = v_user_id
    and action_run.idempotency_key = p_idempotency_key;

  if v_existing.id is not null then
    if v_existing.action_type <> 'account_delete'
      or v_existing.payload_fingerprint <> v_payload_fingerprint then
      raise exception 'Identificativo operazione già utilizzato con dati differenti.';
    end if;
    return v_existing.result_snapshot;
  end if;

  select profile.*
  into v_profile
  from public.profiles profile
  where profile.id = v_user_id
  for update;

  if v_profile.id is null or v_profile.deleted_at is not null then
    raise exception 'Profilo non trovato o già eliminato.';
  end if;
  if v_profile.revision <> p_expected_revision then
    raise exception
      'Il profilo è stato aggiornato su un altro dispositivo. Ricarica e riprova.';
  end if;

  for v_league in
    select league.id
    from public.leagues league
    where league.owner_id = v_user_id
    for update
  loop
    v_new_owner_id := null;

    select member.user_id
    into v_new_owner_id
    from public.league_members member
    where member.league_id = v_league.id
      and member.user_id <> v_user_id
    order by
      case when member.role = 'admin' then 0 else 1 end,
      member.joined_at,
      member.user_id
    limit 1;

    if v_new_owner_id is null then
      delete from public.leagues league
      where league.id = v_league.id;
      v_deleted_league_count := v_deleted_league_count + 1;
    else
      update public.league_members member
      set role = 'admin'
      where member.league_id = v_league.id
        and member.user_id = v_new_owner_id;

      update public.leagues league
      set owner_id = v_new_owner_id
      where league.id = v_league.id;

      v_transferred_count := v_transferred_count + 1;
    end if;
  end loop;

  delete from public.notification_push_deliveries delivery
  where delivery.user_id = v_user_id;

  delete from public.user_push_devices device
  where device.user_id = v_user_id;

  delete from public.user_notification_preferences preferences
  where preferences.user_id = v_user_id;

  delete from public.user_notifications notification
  where notification.user_id = v_user_id;

  delete from public.league_members member
  where member.user_id = v_user_id;

  update public.profiles profile
  set
    display_name = 'Account eliminato',
    avatar_url = null,
    subscription = 'free',
    deleted_at = now(),
    revision = profile.revision + 1,
    profile_fingerprint = pg_catalog.md5(
      'Account eliminato' || E'\n\nfree\ndeleted'
    ),
    deletion_request_id = p_idempotency_key,
    updated_at = now()
  where profile.id = v_user_id
  returning * into v_profile;

  v_result := jsonb_build_object(
    'userId', v_user_id,
    'deleted', true,
    'revision', v_profile.revision,
    'profileFingerprint', v_profile.profile_fingerprint,
    'transferredLeagueCount', v_transferred_count,
    'deletedLeagueCount', v_deleted_league_count,
    'completedAt', now(),
    'protected', true
  );

  insert into public.account_action_runs (
    user_id,
    action_type,
    idempotency_key,
    previous_revision,
    result_revision,
    payload_fingerprint,
    result_snapshot
  )
  values (
    v_user_id,
    'account_delete',
    p_idempotency_key,
    p_expected_revision,
    v_profile.revision,
    v_payload_fingerprint,
    v_result
  );

  delete from auth.users auth_user
  where auth_user.id = v_user_id;

  if not found then
    raise exception 'Account Auth non trovato.';
  end if;

  return v_result;
end;
$$;

-- Compatibilità: le RPC storiche confluiscono nel percorso protetto.
create or replace function public.update_my_profile(
  p_display_name text
)
returns public.profiles
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_revision bigint;
  v_profile public.profiles%rowtype;
begin
  if v_user_id is null then
    raise exception 'Devi effettuare l''accesso.';
  end if;

  select profile.revision
  into v_revision
  from public.profiles profile
  where profile.id = v_user_id
    and profile.deleted_at is null;

  if v_revision is null then
    raise exception 'Profilo non trovato.';
  end if;

  perform public.update_my_profile_guarded_v1(
    p_display_name,
    v_revision,
    gen_random_uuid()
  );

  select profile.*
  into v_profile
  from public.profiles profile
  where profile.id = v_user_id;

  return v_profile;
end;
$$;

create or replace function public.delete_my_account()
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_revision bigint;
begin
  if v_user_id is null then
    raise exception 'Devi effettuare l''accesso.';
  end if;

  select profile.revision
  into v_revision
  from public.profiles profile
  where profile.id = v_user_id
    and profile.deleted_at is null;

  if v_revision is null then
    raise exception 'Profilo non trovato.';
  end if;

  perform public.delete_my_account_guarded_v1(
    v_revision,
    gen_random_uuid()
  );

  return true;
end;
$$;

revoke all on function public.account_profile_payload_v1(uuid)
from public, anon, authenticated;
revoke all on function public.get_my_account_center_v2()
from public, anon;
revoke all on function public.update_my_profile_guarded_v1(text,bigint,uuid)
from public, anon;
revoke all on function public.delete_my_account_guarded_v1(bigint,uuid)
from public, anon;
revoke all on function public.update_my_profile(text)
from public, anon;
revoke all on function public.delete_my_account()
from public, anon;

grant execute on function public.get_my_account_center_v2()
to authenticated;
grant execute on function public.update_my_profile_guarded_v1(text,bigint,uuid)
to authenticated;
grant execute on function public.delete_my_account_guarded_v1(bigint,uuid)
to authenticated;
grant execute on function public.update_my_profile(text)
to authenticated;
grant execute on function public.delete_my_account()
to authenticated;

-- Nessuna scrittura diretta sul profilo o sul registro certificato.
revoke insert, update, delete on public.profiles
from authenticated, anon;
revoke insert, update, delete on public.account_action_runs
from authenticated, anon;

-- Realtime usa soltanto il registro certificato, senza esporre auth.users.
do $realtime$
begin
  if exists (
    select 1
    from pg_publication publication
    where publication.pubname = 'supabase_realtime'
  ) and not exists (
    select 1
    from pg_publication_tables publication_table
    where publication_table.pubname = 'supabase_realtime'
      and publication_table.schemaname = 'public'
      and publication_table.tablename = 'account_action_runs'
  ) then
    execute 'alter publication supabase_realtime add table public.account_action_runs';
  end if;
end;
$realtime$;

create or replace function public.get_account_profile_safety_integrity_v1()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'profilesReady', to_regclass('public.profiles') is not null,
    'revisionReady', exists (
      select 1 from information_schema.columns column_row
      where column_row.table_schema = 'public'
        and column_row.table_name = 'profiles'
        and column_row.column_name = 'revision'
    ),
    'fingerprintReady', exists (
      select 1 from information_schema.columns column_row
      where column_row.table_schema = 'public'
        and column_row.table_name = 'profiles'
        and column_row.column_name = 'profile_fingerprint'
    ),
    'actionRunsReady', to_regclass('public.account_action_runs') is not null,
    'actionRunsRlsReady', coalesce((
      select class.relrowsecurity
      from pg_class class
      where class.oid = to_regclass('public.account_action_runs')
    ), false),
    'actionRunsImmutable', exists (
      select 1 from pg_trigger trigger_row
      where trigger_row.tgrelid = to_regclass('public.account_action_runs')
        and trigger_row.tgname = 'account_action_runs_immutable'
        and not trigger_row.tgisinternal
    ),
    'guardedUpdateReady', to_regprocedure(
      'public.update_my_profile_guarded_v1(text,bigint,uuid)'
    ) is not null,
    'guardedDeleteReady', to_regprocedure(
      'public.delete_my_account_guarded_v1(bigint,uuid)'
    ) is not null,
    'centerV2Ready', to_regprocedure('public.get_my_account_center_v2()') is not null,
    'legacyUpdateReady', to_regprocedure('public.update_my_profile(text)') is not null,
    'legacyDeleteReady', to_regprocedure('public.delete_my_account()') is not null,
    'authMetadataSyncReady', pg_get_functiondef(to_regprocedure(
      'public.update_my_profile_guarded_v1(text,bigint,uuid)'
    )) like '%update auth.users%',
    'pushCleanupReady', pg_get_functiondef(to_regprocedure(
      'public.delete_my_account_guarded_v1(bigint,uuid)'
    )) like '%delete from public.user_push_devices%',
    'authenticatedUpdateReady', has_function_privilege(
      'authenticated',
      'public.update_my_profile_guarded_v1(text,bigint,uuid)',
      'EXECUTE'
    ),
    'authenticatedDeleteReady', has_function_privilege(
      'authenticated',
      'public.delete_my_account_guarded_v1(bigint,uuid)',
      'EXECUTE'
    ),
    'authenticatedCenterReady', has_function_privilege(
      'authenticated',
      'public.get_my_account_center_v2()',
      'EXECUTE'
    ),
    'anonymousBlocked',
      not has_function_privilege(
        'anon',
        'public.update_my_profile_guarded_v1(text,bigint,uuid)',
        'EXECUTE'
      )
      and not has_function_privilege(
        'anon',
        'public.delete_my_account_guarded_v1(bigint,uuid)',
        'EXECUTE'
      ),
    'directWritesBlocked',
      not has_table_privilege('authenticated', 'public.profiles', 'INSERT')
      and not has_table_privilege('authenticated', 'public.profiles', 'UPDATE')
      and not has_table_privilege('authenticated', 'public.profiles', 'DELETE')
      and not has_table_privilege('authenticated', 'public.account_action_runs', 'INSERT')
      and not has_table_privilege('authenticated', 'public.account_action_runs', 'UPDATE')
      and not has_table_privilege('authenticated', 'public.account_action_runs', 'DELETE'),
    'realtimeReady', exists (
      select 1
      from pg_publication_tables publication_table
      where publication_table.pubname = 'supabase_realtime'
        and publication_table.schemaname = 'public'
        and publication_table.tablename = 'account_action_runs'
    ),
    'fingerprintsValid', not exists (
      select 1
      from public.profiles profile
      where profile.profile_fingerprint is null
         or char_length(profile.profile_fingerprint) <> 32
         or profile.revision <= 0
    )
  );
$$;

revoke all on function public.get_account_profile_safety_integrity_v1()
from public, anon;
grant execute on function public.get_account_profile_safety_integrity_v1()
to authenticated, service_role;

commit;

-- Diagnostica conclusiva: devono comparire esattamente 20 valori true.
select
  to_regclass('public.profiles') is not null
    as account_profiles_ready,
  exists (
    select 1 from information_schema.columns column_row
    where column_row.table_schema = 'public'
      and column_row.table_name = 'profiles'
      and column_row.column_name = 'revision'
  ) as account_revision_ready,
  exists (
    select 1 from information_schema.columns column_row
    where column_row.table_schema = 'public'
      and column_row.table_name = 'profiles'
      and column_row.column_name = 'profile_fingerprint'
  ) as account_fingerprint_ready,
  to_regclass('public.account_action_runs') is not null
    as account_action_runs_ready,
  coalesce((
    select class.relrowsecurity
    from pg_class class
    where class.oid = to_regclass('public.account_action_runs')
  ), false) as account_action_runs_rls_ready,
  exists (
    select 1 from pg_trigger trigger_row
    where trigger_row.tgrelid = to_regclass('public.account_action_runs')
      and trigger_row.tgname = 'account_action_runs_immutable'
      and not trigger_row.tgisinternal
  ) as account_action_runs_immutable,
  to_regprocedure(
    'public.update_my_profile_guarded_v1(text,bigint,uuid)'
  ) is not null as account_guarded_update_ready,
  to_regprocedure(
    'public.delete_my_account_guarded_v1(bigint,uuid)'
  ) is not null as account_guarded_delete_ready,
  to_regprocedure('public.get_my_account_center_v2()') is not null
    as account_center_v2_ready,
  to_regprocedure('public.update_my_profile(text)') is not null
    as account_legacy_update_ready,
  to_regprocedure('public.delete_my_account()') is not null
    as account_legacy_delete_ready,
  pg_get_functiondef(to_regprocedure(
    'public.update_my_profile_guarded_v1(text,bigint,uuid)'
  )) like '%update auth.users%'
    as account_auth_metadata_sync_ready,
  pg_get_functiondef(to_regprocedure(
    'public.delete_my_account_guarded_v1(bigint,uuid)'
  )) like '%delete from public.user_push_devices%'
    as account_push_cleanup_ready,
  has_function_privilege(
    'authenticated',
    'public.update_my_profile_guarded_v1(text,bigint,uuid)',
    'EXECUTE'
  ) as account_authenticated_update_ready,
  has_function_privilege(
    'authenticated',
    'public.delete_my_account_guarded_v1(bigint,uuid)',
    'EXECUTE'
  ) as account_authenticated_delete_ready,
  has_function_privilege(
    'authenticated',
    'public.get_my_account_center_v2()',
    'EXECUTE'
  ) as account_authenticated_center_ready,
  (
    not has_function_privilege(
      'anon',
      'public.update_my_profile_guarded_v1(text,bigint,uuid)',
      'EXECUTE'
    )
    and not has_function_privilege(
      'anon',
      'public.delete_my_account_guarded_v1(bigint,uuid)',
      'EXECUTE'
    )
  ) as account_anonymous_blocked,
  (
    not has_table_privilege('authenticated', 'public.profiles', 'INSERT')
    and not has_table_privilege('authenticated', 'public.profiles', 'UPDATE')
    and not has_table_privilege('authenticated', 'public.profiles', 'DELETE')
    and not has_table_privilege('authenticated', 'public.account_action_runs', 'INSERT')
    and not has_table_privilege('authenticated', 'public.account_action_runs', 'UPDATE')
    and not has_table_privilege('authenticated', 'public.account_action_runs', 'DELETE')
  ) as account_direct_writes_blocked,
  exists (
    select 1
    from pg_publication_tables publication_table
    where publication_table.pubname = 'supabase_realtime'
      and publication_table.schemaname = 'public'
      and publication_table.tablename = 'account_action_runs'
  ) as account_realtime_ready,
  not exists (
    select 1
    from public.profiles profile
    where profile.profile_fingerprint is null
       or char_length(profile.profile_fingerprint) <> 32
       or profile.revision <= 0
  ) as account_fingerprints_valid;
