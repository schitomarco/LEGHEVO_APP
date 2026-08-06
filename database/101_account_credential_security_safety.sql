-- LEGHEVO v0.61.7 · Sicurezza credenziali e cambio password certificato
-- Migrazione interna: database/101_account_credential_security_safety.sql
--
-- Obiettivi:
-- - certificare ogni cambio reale della password senza salvare password o hash;
-- - registrare variazioni e conferme dell'indirizzo email;
-- - mantenere uno stato revisionato della sicurezza account;
-- - sincronizzare il Centro Account tra dispositivi tramite Realtime;
-- - preservare il flusso Supabase Auth esistente.

begin;

-- Preflight dettagliato. Nessuna scrittura viene eseguita se manca una
-- dipendenza del modello account già validato.
do $preflight$
declare
  v_missing text[] := array[]::text[];
  v_expected record;
begin
  if to_regclass('public.profiles') is null then
    v_missing := array_append(v_missing, 'table public.profiles');
  end if;
  if to_regclass('public.account_action_runs') is null then
    v_missing := array_append(v_missing, 'table public.account_action_runs');
  end if;
  if to_regclass('auth.users') is null then
    v_missing := array_append(v_missing, 'table auth.users');
  end if;
  if to_regprocedure('public.get_my_account_center_v2()') is null then
    v_missing := array_append(v_missing, 'function public.get_my_account_center_v2()');
  end if;
  if to_regprocedure('public.leghevo_sha256_hex_v1(text)') is null then
    v_missing := array_append(v_missing, 'function public.leghevo_sha256_hex_v1(text)');
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_trigger trigger_row
    where trigger_row.tgrelid = to_regclass('auth.users')
      and trigger_row.tgname = 'on_auth_user_created'
      and not trigger_row.tgisinternal
  ) then
    v_missing := array_append(
      v_missing,
      'trigger auth.users.on_auth_user_created'
    );
  end if;

  for v_expected in
    select *
    from (values
      ('public', 'profiles', 'id'),
      ('public', 'profiles', 'deleted_at'),
      ('auth', 'users', 'id'),
      ('auth', 'users', 'email'),
      ('auth', 'users', 'email_confirmed_at'),
      ('auth', 'users', 'encrypted_password'),
      ('auth', 'users', 'created_at')
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
      'Preflight v0.61.7 non superato. Oggetti mancanti: %',
      array_to_string(v_missing, '; ');
  end if;
end;
$preflight$;

create table if not exists public.account_security_states (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  revision bigint not null default 1 check (revision > 0),
  monitored_since timestamptz not null default now(),
  last_password_changed_at timestamptz,
  last_email_changed_at timestamptz,
  last_email_verified_at timestamptz,
  state_fingerprint text not null check (char_length(state_fingerprint) = 64),
  updated_at timestamptz not null default now()
);

create table if not exists public.account_security_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  event_type text not null check (
    event_type in (
      'monitoring_started',
      'password_changed',
      'email_changed',
      'email_verified',
      'email_verification_changed'
    )
  ),
  security_revision bigint not null check (security_revision > 0),
  source text not null check (source in ('migration', 'auth_trigger')),
  event_fingerprint text not null check (char_length(event_fingerprint) = 64),
  event_snapshot jsonb not null check (jsonb_typeof(event_snapshot) = 'object'),
  occurred_at timestamptz not null default now(),
  unique (user_id, event_type, security_revision)
);

create index if not exists account_security_events_user_idx
  on public.account_security_events (user_id, occurred_at desc);

alter table public.account_security_states enable row level security;
alter table public.account_security_events enable row level security;
alter table public.account_security_states replica identity full;
alter table public.account_security_events replica identity full;

drop policy if exists account_security_states_read_own
on public.account_security_states;
create policy account_security_states_read_own
on public.account_security_states
for select to authenticated
using (user_id = auth.uid());

drop policy if exists account_security_events_read_own
on public.account_security_events;
create policy account_security_events_read_own
on public.account_security_events
for select to authenticated
using (user_id = auth.uid());

revoke all on table public.account_security_states
from public, anon, authenticated;
revoke all on table public.account_security_events
from public, anon, authenticated;
grant select on table public.account_security_states to authenticated;
grant select on table public.account_security_events to authenticated;

create or replace function public.prevent_account_security_event_mutation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  raise exception
    'Evento di sicurezza certificato: modifica o cancellazione diretta non consentita.';
end;
$$;

revoke all on function public.prevent_account_security_event_mutation()
from public, anon, authenticated;

drop trigger if exists account_security_events_immutable
on public.account_security_events;
create trigger account_security_events_immutable
before update or delete on public.account_security_events
for each row execute function public.prevent_account_security_event_mutation();

create or replace function public.account_security_state_fingerprint_v1(
  p_user_id uuid,
  p_revision bigint,
  p_email text,
  p_email_verified boolean,
  p_monitored_since timestamptz,
  p_last_password_changed_at timestamptz,
  p_last_email_changed_at timestamptz,
  p_last_email_verified_at timestamptz
)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select public.leghevo_sha256_hex_v1(
    coalesce(p_user_id::text, '') || E'\n' ||
    coalesce(p_revision::text, '') || E'\n' ||
    lower(coalesce(p_email, '')) || E'\n' ||
    coalesce(p_email_verified::text, 'false') || E'\n' ||
    coalesce(p_monitored_since::text, '') || E'\n' ||
    coalesce(p_last_password_changed_at::text, '') || E'\n' ||
    coalesce(p_last_email_changed_at::text, '') || E'\n' ||
    coalesce(p_last_email_verified_at::text, '')
  )
$$;

revoke all on function public.account_security_state_fingerprint_v1(
  uuid,bigint,text,boolean,timestamptz,timestamptz,timestamptz,timestamptz
)
from public, anon, authenticated;

create or replace function public.account_security_event_fingerprint_v1(
  p_user_id uuid,
  p_event_type text,
  p_security_revision bigint,
  p_state_fingerprint text,
  p_occurred_at timestamptz
)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select public.leghevo_sha256_hex_v1(
    coalesce(p_user_id::text, '') || E'\n' ||
    coalesce(p_event_type, '') || E'\n' ||
    coalesce(p_security_revision::text, '') || E'\n' ||
    coalesce(p_state_fingerprint, '') || E'\n' ||
    coalesce(p_occurred_at::text, '')
  )
$$;

revoke all on function public.account_security_event_fingerprint_v1(
  uuid,text,bigint,text,timestamptz
)
from public, anon, authenticated;

-- Inizializzazione non distruttiva per gli account già esistenti.
insert into public.account_security_states (
  user_id,
  revision,
  monitored_since,
  last_password_changed_at,
  last_email_changed_at,
  last_email_verified_at,
  state_fingerprint,
  updated_at
)
select
  auth_user.id,
  1,
  now(),
  null,
  null,
  auth_user.email_confirmed_at,
  public.account_security_state_fingerprint_v1(
    auth_user.id,
    1,
    auth_user.email,
    auth_user.email_confirmed_at is not null,
    now(),
    null,
    null,
    auth_user.email_confirmed_at
  ),
  now()
from auth.users auth_user
join public.profiles profile on profile.id = auth_user.id
where profile.deleted_at is null
on conflict (user_id) do nothing;

insert into public.account_security_events (
  user_id,
  event_type,
  security_revision,
  source,
  event_fingerprint,
  event_snapshot,
  occurred_at
)
select
  state.user_id,
  'monitoring_started',
  state.revision,
  'migration',
  public.account_security_event_fingerprint_v1(
    state.user_id,
    'monitoring_started',
    state.revision,
    state.state_fingerprint,
    state.monitored_since
  ),
  jsonb_build_object(
    'eventType', 'monitoring_started',
    'securityRevision', state.revision,
    'monitoredSince', state.monitored_since,
    'stateFingerprint', state.state_fingerprint,
    'passwordOrHashStored', false
  ),
  state.monitored_since
from public.account_security_states state
where not exists (
  select 1
  from public.account_security_events event
  where event.user_id = state.user_id
    and event.event_type = 'monitoring_started'
);

-- Trigger separato dalla creazione profilo. Il nome alfabeticamente successivo
-- a on_auth_user_created assicura che il profilo esista già.
create or replace function public.initialize_auth_user_security_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_now timestamptz := coalesce(new.created_at, now());
  v_state public.account_security_states%rowtype;
begin
  insert into public.account_security_states (
    user_id,
    revision,
    monitored_since,
    last_password_changed_at,
    last_email_changed_at,
    last_email_verified_at,
    state_fingerprint,
    updated_at
  )
  select
    new.id,
    1,
    v_now,
    null,
    null,
    new.email_confirmed_at,
    public.account_security_state_fingerprint_v1(
      new.id,
      1,
      new.email,
      new.email_confirmed_at is not null,
      v_now,
      null,
      null,
      new.email_confirmed_at
    ),
    v_now
  from public.profiles profile
  where profile.id = new.id
  on conflict (user_id) do nothing
  returning * into v_state;

  if v_state.user_id is not null then
    insert into public.account_security_events (
      user_id,
      event_type,
      security_revision,
      source,
      event_fingerprint,
      event_snapshot,
      occurred_at
    )
    values (
      v_state.user_id,
      'monitoring_started',
      v_state.revision,
      'auth_trigger',
      public.account_security_event_fingerprint_v1(
        v_state.user_id,
        'monitoring_started',
        v_state.revision,
        v_state.state_fingerprint,
        v_state.monitored_since
      ),
      jsonb_build_object(
        'eventType', 'monitoring_started',
        'securityRevision', v_state.revision,
        'monitoredSince', v_state.monitored_since,
        'stateFingerprint', v_state.state_fingerprint,
        'passwordOrHashStored', false
      ),
      v_state.monitored_since
    )
    on conflict (user_id, event_type, security_revision) do nothing;
  end if;

  return new;
end;
$$;

revoke all on function public.initialize_auth_user_security_v1()
from public, anon, authenticated;

drop trigger if exists zz_leghevo_auth_security_initialized
on auth.users;
create trigger zz_leghevo_auth_security_initialized
after insert on auth.users
for each row execute function public.initialize_auth_user_security_v1();

create or replace function public.capture_auth_user_security_change_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_password_changed boolean :=
    new.encrypted_password is distinct from old.encrypted_password;
  v_email_changed boolean :=
    lower(coalesce(new.email, '')) is distinct from lower(coalesce(old.email, ''));
  v_email_verification_changed boolean :=
    new.email_confirmed_at is distinct from old.email_confirmed_at;
  v_now timestamptz := now();
  v_state public.account_security_states%rowtype;
  v_revision bigint;
  v_last_password_changed_at timestamptz;
  v_last_email_changed_at timestamptz;
  v_last_email_verified_at timestamptz;
  v_state_fingerprint text;
  v_event_type text;
begin
  if not (
    v_password_changed
    or v_email_changed
    or v_email_verification_changed
  ) then
    return new;
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'leghevo:account-security:' || new.id::text,
      0
    )
  );

  insert into public.account_security_states (
    user_id,
    revision,
    monitored_since,
    last_password_changed_at,
    last_email_changed_at,
    last_email_verified_at,
    state_fingerprint,
    updated_at
  )
  select
    new.id,
    1,
    v_now,
    null,
    null,
    new.email_confirmed_at,
    public.account_security_state_fingerprint_v1(
      new.id,
      1,
      new.email,
      new.email_confirmed_at is not null,
      v_now,
      null,
      null,
      new.email_confirmed_at
    ),
    v_now
  from public.profiles profile
  where profile.id = new.id
  on conflict (user_id) do nothing;

  select state.*
  into v_state
  from public.account_security_states state
  where state.user_id = new.id
  for update;

  if v_state.user_id is null then
    raise exception 'Stato sicurezza account non disponibile per l''utente %.', new.id;
  end if;

  v_revision := v_state.revision + 1;
  v_last_password_changed_at := case
    when v_password_changed then v_now
    else v_state.last_password_changed_at
  end;
  v_last_email_changed_at := case
    when v_email_changed then v_now
    else v_state.last_email_changed_at
  end;
  v_last_email_verified_at := case
    when v_email_changed then new.email_confirmed_at
    when v_email_verification_changed then new.email_confirmed_at
    else v_state.last_email_verified_at
  end;

  v_state_fingerprint := public.account_security_state_fingerprint_v1(
    new.id,
    v_revision,
    new.email,
    new.email_confirmed_at is not null,
    v_state.monitored_since,
    v_last_password_changed_at,
    v_last_email_changed_at,
    v_last_email_verified_at
  );

  update public.account_security_states state
  set
    revision = v_revision,
    last_password_changed_at = v_last_password_changed_at,
    last_email_changed_at = v_last_email_changed_at,
    last_email_verified_at = v_last_email_verified_at,
    state_fingerprint = v_state_fingerprint,
    updated_at = v_now
  where state.user_id = new.id;

  foreach v_event_type in array array[
    case when v_password_changed then 'password_changed' end,
    case when v_email_changed then 'email_changed' end,
    case
      when v_email_verification_changed and new.email_confirmed_at is not null
        then 'email_verified'
      when v_email_verification_changed
        then 'email_verification_changed'
    end
  ]
  loop
    if v_event_type is null then
      continue;
    end if;

    insert into public.account_security_events (
      user_id,
      event_type,
      security_revision,
      source,
      event_fingerprint,
      event_snapshot,
      occurred_at
    )
    values (
      new.id,
      v_event_type,
      v_revision,
      'auth_trigger',
      public.account_security_event_fingerprint_v1(
        new.id,
        v_event_type,
        v_revision,
        v_state_fingerprint,
        v_now
      ),
      jsonb_build_object(
        'eventType', v_event_type,
        'securityRevision', v_revision,
        'emailVerified', new.email_confirmed_at is not null,
        'emailFingerprint', public.leghevo_sha256_hex_v1(
          lower(coalesce(new.email, ''))
        ),
        'occurredAt', v_now,
        'stateFingerprint', v_state_fingerprint,
        'passwordOrHashStored', false
      ),
      v_now
    )
    on conflict (user_id, event_type, security_revision) do nothing;
  end loop;

  return new;
end;
$$;

revoke all on function public.capture_auth_user_security_change_v1()
from public, anon, authenticated;

drop trigger if exists on_auth_user_security_changed
on auth.users;
create trigger on_auth_user_security_changed
after update of encrypted_password, email, email_confirmed_at on auth.users
for each row execute function public.capture_auth_user_security_change_v1();

create or replace function public.get_my_account_center_v3()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_base jsonb;
  v_state public.account_security_states%rowtype;
  v_event_count integer := 0;
  v_last_event_at timestamptz;
begin
  if v_user_id is null then
    raise exception 'Devi effettuare l''accesso.';
  end if;

  v_base := public.get_my_account_center_v2();

  select state.*
  into v_state
  from public.account_security_states state
  where state.user_id = v_user_id;

  select count(*)::integer, max(event.occurred_at)
  into v_event_count, v_last_event_at
  from public.account_security_events event
  where event.user_id = v_user_id;

  return v_base || jsonb_build_object(
    'securityRevision', coalesce(v_state.revision, 0),
    'securityFingerprint', v_state.state_fingerprint,
    'securityMonitoredSince', v_state.monitored_since,
    'lastPasswordChangedAt', v_state.last_password_changed_at,
    'lastEmailChangedAt', v_state.last_email_changed_at,
    'lastEmailVerifiedAt', v_state.last_email_verified_at,
    'securityProtected', v_state.user_id is not null,
    'certifiedSecurityEventCount', v_event_count,
    'lastSecurityEventAt', v_last_event_at
  );
end;
$$;

revoke all on function public.get_my_account_center_v3()
from public, anon;
grant execute on function public.get_my_account_center_v3()
to authenticated;

-- Nessuna password, hash o segreto viene esposto o salvato nelle tabelle public.
revoke insert, update, delete on table public.account_security_states
from authenticated, anon;
revoke insert, update, delete on table public.account_security_events
from authenticated, anon;

-- Realtime espone solo stato ed eventi certificati, mai auth.users.
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
      'account_security_states',
      'account_security_events'
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

create or replace function public.get_account_credential_security_integrity_v1()
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
        ('account_security_states'),
        ('account_security_events')
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
    'securityStatesReady', to_regclass('public.account_security_states') is not null,
    'securityStatesColumnsReady', (
      select count(*) = 8
      from information_schema.columns column_row
      where column_row.table_schema = 'public'
        and column_row.table_name = 'account_security_states'
        and column_row.column_name in (
          'user_id', 'revision', 'monitored_since',
          'last_password_changed_at', 'last_email_changed_at',
          'last_email_verified_at', 'state_fingerprint', 'updated_at'
        )
    ),
    'securityEventsReady', to_regclass('public.account_security_events') is not null,
    'securityEventsColumnsReady', (
      select count(*) = 8
      from information_schema.columns column_row
      where column_row.table_schema = 'public'
        and column_row.table_name = 'account_security_events'
        and column_row.column_name in (
          'id', 'user_id', 'event_type', 'security_revision', 'source',
          'event_fingerprint', 'event_snapshot', 'occurred_at'
        )
    ),
    'statesRlsReady', coalesce((
      select class.relrowsecurity
      from pg_catalog.pg_class class
      where class.oid = to_regclass('public.account_security_states')
    ), false),
    'eventsRlsReady', coalesce((
      select class.relrowsecurity
      from pg_catalog.pg_class class
      where class.oid = to_regclass('public.account_security_events')
    ), false),
    'readPoliciesReady', (
      select count(*) = 2
      from (values
        ('account_security_states', 'account_security_states_read_own'),
        ('account_security_events', 'account_security_events_read_own')
      ) expected(table_name, policy_name)
      where exists (
        select 1
        from pg_catalog.pg_policies policy
        where policy.schemaname = 'public'
          and policy.tablename = expected.table_name
          and policy.policyname = expected.policy_name
      )
    ),
    'eventsImmutable', exists (
      select 1
      from pg_catalog.pg_trigger trigger_row
      where trigger_row.tgrelid = to_regclass('public.account_security_events')
        and trigger_row.tgname = 'account_security_events_immutable'
        and not trigger_row.tgisinternal
    ),
    'stateFingerprintHelperReady', to_regprocedure(
      'public.account_security_state_fingerprint_v1(uuid,bigint,text,boolean,timestamptz,timestamptz,timestamptz,timestamptz)'
    ) is not null,
    'eventFingerprintHelperReady', to_regprocedure(
      'public.account_security_event_fingerprint_v1(uuid,text,bigint,text,timestamptz)'
    ) is not null,
    'initializationTriggerReady',
      exists (
        select 1
        from pg_catalog.pg_trigger trigger_row
        where trigger_row.tgrelid = to_regclass('auth.users')
          and trigger_row.tgname = 'on_auth_user_created'
          and not trigger_row.tgisinternal
      )
      and exists (
        select 1
        from pg_catalog.pg_trigger trigger_row
        where trigger_row.tgrelid = to_regclass('auth.users')
          and trigger_row.tgname = 'zz_leghevo_auth_security_initialized'
          and not trigger_row.tgisinternal
      ),
    'changeTriggerReady', exists (
      select 1
      from pg_catalog.pg_trigger trigger_row
      where trigger_row.tgrelid = to_regclass('auth.users')
        and trigger_row.tgname = 'on_auth_user_security_changed'
        and not trigger_row.tgisinternal
    ),
    'centerV3Ready', to_regprocedure(
      'public.get_my_account_center_v3()'
    ) is not null,
    'existingAccountsCovered', not exists (
      select 1
      from auth.users auth_user
      join public.profiles profile on profile.id = auth_user.id
      left join public.account_security_states state
        on state.user_id = auth_user.id
      where profile.deleted_at is null
        and state.user_id is null
    ),
    'stateRowsConsistent', not exists (
      select 1
      from public.account_security_states state
      join auth.users auth_user on auth_user.id = state.user_id
      where state.revision <= 0
         or char_length(state.state_fingerprint) <> 64
         or state.state_fingerprint <>
           public.account_security_state_fingerprint_v1(
             state.user_id,
             state.revision,
             auth_user.email,
             auth_user.email_confirmed_at is not null,
             state.monitored_since,
             state.last_password_changed_at,
             state.last_email_changed_at,
             state.last_email_verified_at
           )
    ),
    'eventsContainNoCredentialMaterial', not exists (
      select 1
      from public.account_security_events event
      where lower(event.event_snapshot::text) like '%encrypted_password%'
         or lower(event.event_snapshot::text) like '%password_hash%'
         or lower(event.event_snapshot::text) like '%access_token%'
         or lower(event.event_snapshot::text) like '%refresh_token%'
    ),
    'authenticatedAccessReady',
      has_function_privilege(
        'authenticated',
        'public.get_my_account_center_v3()',
        'EXECUTE'
      )
      and has_table_privilege(
        'authenticated',
        'public.account_security_states',
        'SELECT'
      )
      and has_table_privilege(
        'authenticated',
        'public.account_security_events',
        'SELECT'
      ),
    'anonymousBlocked',
      not has_function_privilege(
        'anon',
        'public.get_my_account_center_v3()',
        'EXECUTE'
      )
      and not has_table_privilege(
        'anon',
        'public.account_security_states',
        'SELECT'
      )
      and not has_table_privilege(
        'anon',
        'public.account_security_events',
        'SELECT'
      ),
    'directWritesBlocked',
      not has_table_privilege(
        'authenticated',
        'public.account_security_states',
        'INSERT,UPDATE,DELETE'
      )
      and not has_table_privilege(
        'authenticated',
        'public.account_security_events',
        'INSERT,UPDATE,DELETE'
      ),
    'realtimeReady', v_realtime_ready,
    'legacyAccountCenterPreserved', to_regprocedure(
      'public.get_my_account_center_v2()'
    ) is not null
  );
end;
$$;

revoke all on function public.get_account_credential_security_integrity_v1()
from public, anon;
grant execute on function public.get_account_credential_security_integrity_v1()
to authenticated, service_role;

-- Validazione transazionale con indicazione puntuale dei controlli falsi.
do $validation$
declare
  v_integrity jsonb;
  v_failures jsonb;
begin
  v_integrity := public.get_account_credential_security_integrity_v1();

  select coalesce(jsonb_object_agg(entry.key, entry.value), '{}'::jsonb)
  into v_failures
  from jsonb_each(v_integrity) entry
  where entry.value <> 'true'::jsonb;

  if v_failures <> '{}'::jsonb then
    raise exception
      'Validazione v0.61.7 non superata. Controlli falsi: %',
      v_failures;
  end if;
end;
$validation$;

commit;

-- Diagnostica finale: devono comparire esattamente 20 valori true.
select
  (integrity ->> 'securityStatesReady')::boolean
    as account_security_states_ready,
  (integrity ->> 'securityStatesColumnsReady')::boolean
    as account_security_states_columns_ready,
  (integrity ->> 'securityEventsReady')::boolean
    as account_security_events_ready,
  (integrity ->> 'securityEventsColumnsReady')::boolean
    as account_security_events_columns_ready,
  (integrity ->> 'statesRlsReady')::boolean
    as account_security_states_rls_ready,
  (integrity ->> 'eventsRlsReady')::boolean
    as account_security_events_rls_ready,
  (integrity ->> 'readPoliciesReady')::boolean
    as account_security_read_policies_ready,
  (integrity ->> 'eventsImmutable')::boolean
    as account_security_events_immutable,
  (integrity ->> 'stateFingerprintHelperReady')::boolean
    as account_security_state_fingerprint_ready,
  (integrity ->> 'eventFingerprintHelperReady')::boolean
    as account_security_event_fingerprint_ready,
  (integrity ->> 'initializationTriggerReady')::boolean
    as account_security_initialization_trigger_ready,
  (integrity ->> 'changeTriggerReady')::boolean
    as account_security_change_trigger_ready,
  (integrity ->> 'centerV3Ready')::boolean
    as account_center_v3_ready,
  (integrity ->> 'existingAccountsCovered')::boolean
    as account_security_existing_accounts_covered,
  (integrity ->> 'stateRowsConsistent')::boolean
    as account_security_state_rows_consistent,
  (integrity ->> 'eventsContainNoCredentialMaterial')::boolean
    as account_security_no_credential_material,
  (integrity ->> 'authenticatedAccessReady')::boolean
    as account_security_authenticated_access_ready,
  (integrity ->> 'anonymousBlocked')::boolean
    as account_security_anonymous_blocked,
  (integrity ->> 'directWritesBlocked')::boolean
    as account_security_direct_writes_blocked,
  (
    (integrity ->> 'realtimeReady')::boolean
    and (integrity ->> 'legacyAccountCenterPreserved')::boolean
  ) as account_security_realtime_and_legacy_ready
from (
  select public.get_account_credential_security_integrity_v1() as integrity
) diagnostics;
