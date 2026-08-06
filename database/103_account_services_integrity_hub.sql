-- LEGHEVO v0.61.9
-- Account & Release Services Integrity Hub
-- Unifica e certifica lo stato operativo dei servizi account introdotti
-- dalla v0.61.1 alla v0.61.8 senza modificare i contenuti utente.

begin;

-- ---------------------------------------------------------------------------
-- Preflight esplicito: nessuna scrittura viene eseguita se una dipendenza
-- validata nelle versioni precedenti non è realmente presente.
-- ---------------------------------------------------------------------------
do $preflight$
declare
  v_missing text[] := array[]::text[];
  v_table text;
  v_function text;
begin
  foreach v_table in array array[
    'public.profiles',
    'public.data_rights_request_action_runs',
    'public.support_request_action_runs',
    'public.push_preference_action_runs',
    'public.account_action_runs',
    'public.legal_acceptance_action_runs',
    'public.notification_action_runs',
    'public.account_security_events',
    'public.personal_data_export_runs'
  ]
  loop
    if to_regclass(v_table) is null then
      v_missing := array_append(v_missing, 'table ' || v_table);
    end if;
  end loop;

  foreach v_function in array array[
    'public.leghevo_sha256_hex_v1(text)',
    'public.get_my_data_rights_center_v2()',
    'public.get_my_support_center_v2()',
    'public.get_my_push_notification_preferences_v2()',
    'public.get_my_account_center_v3()',
    'public.get_my_privacy_center_v4()',
    'public.get_my_notification_center_v2(integer)'
  ]
  loop
    if to_regprocedure(v_function) is null then
      v_missing := array_append(v_missing, 'function ' || v_function);
    end if;
  end loop;

  if cardinality(v_missing) > 0 then
    raise exception 'LEGHEVO v0.61.9 preflight fallito: %',
      array_to_string(v_missing, ', ');
  end if;
end;
$preflight$;

-- ---------------------------------------------------------------------------
-- Stato unificato e registro immutabile degli eventi dei servizi account.
-- ---------------------------------------------------------------------------
create table if not exists public.account_service_states (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  revision bigint not null default 0 check (revision >= 0),
  protected_service_count integer not null default 8
    check (protected_service_count between 0 and 8),
  last_source_table text,
  last_action_type text,
  last_activity_at timestamptz,
  state_fingerprint text not null check (char_length(state_fingerprint) = 64),
  updated_at timestamptz not null default now()
);

create table if not exists public.account_service_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  source_table text not null check (
    source_table in (
      'data_rights_request_action_runs',
      'support_request_action_runs',
      'push_preference_action_runs',
      'account_action_runs',
      'legal_acceptance_action_runs',
      'notification_action_runs',
      'account_security_events',
      'personal_data_export_runs'
    )
  ),
  source_run_id uuid not null,
  action_type text not null,
  source_revision bigint,
  event_fingerprint text not null check (char_length(event_fingerprint) = 64),
  occurred_at timestamptz not null,
  created_at timestamptz not null default now(),
  unique (source_table, source_run_id)
);

create index if not exists account_service_events_user_idx
  on public.account_service_events (user_id, occurred_at desc);

alter table public.account_service_states enable row level security;
alter table public.account_service_events enable row level security;
alter table public.account_service_states replica identity full;
alter table public.account_service_events replica identity full;

drop policy if exists account_service_states_read_own
on public.account_service_states;
create policy account_service_states_read_own
on public.account_service_states
for select to authenticated
using (user_id = auth.uid());

drop policy if exists account_service_events_read_own
on public.account_service_events;
create policy account_service_events_read_own
on public.account_service_events
for select to authenticated
using (user_id = auth.uid());

revoke all on table public.account_service_states
from public, anon, authenticated;
revoke all on table public.account_service_events
from public, anon, authenticated;
grant select on table public.account_service_states to authenticated;
grant select on table public.account_service_events to authenticated;

create or replace function public.prevent_account_service_event_mutation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  raise exception 'Il registro unificato dei servizi account è immutabile.';
end;
$$;

revoke all on function public.prevent_account_service_event_mutation()
from public, anon, authenticated;

drop trigger if exists account_service_events_immutable
on public.account_service_events;
create trigger account_service_events_immutable
before update or delete on public.account_service_events
for each row execute function public.prevent_account_service_event_mutation();

create or replace function public.account_service_event_fingerprint_v1(
  p_user_id uuid,
  p_source_table text,
  p_source_run_id uuid,
  p_action_type text,
  p_source_revision bigint,
  p_occurred_at timestamptz
)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select public.leghevo_sha256_hex_v1(
    concat_ws(
      '|',
      'account-service-event-v1',
      coalesce(p_user_id::text, ''),
      coalesce(p_source_table, ''),
      coalesce(p_source_run_id::text, ''),
      coalesce(p_action_type, ''),
      coalesce(p_source_revision::text, ''),
      coalesce(p_occurred_at::text, '')
    )
  );
$$;

revoke all on function public.account_service_event_fingerprint_v1(
  uuid, text, uuid, text, bigint, timestamptz
) from public, anon, authenticated;

create or replace function public.capture_account_service_activity_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_payload jsonb := to_jsonb(new);
  v_user_id uuid;
  v_source_run_id uuid;
  v_action_type text;
  v_source_revision bigint;
  v_occurred_at timestamptz;
  v_event_id uuid;
  v_next_revision bigint;
begin
  v_user_id := nullif(v_payload ->> 'user_id', '')::uuid;
  v_source_run_id := nullif(v_payload ->> 'id', '')::uuid;
  v_action_type := coalesce(
    nullif(v_payload ->> 'action_type', ''),
    nullif(v_payload ->> 'event_type', ''),
    case when tg_table_name = 'personal_data_export_runs'
      then 'personal_data_export'
      else 'service_action'
    end
  );
  v_source_revision := nullif(
    coalesce(
      v_payload ->> 'result_revision',
      v_payload ->> 'security_revision',
      v_payload ->> 'export_revision'
    ),
    ''
  )::bigint;
  v_occurred_at := coalesce(
    nullif(v_payload ->> 'occurred_at', '')::timestamptz,
    nullif(v_payload ->> 'created_at', '')::timestamptz,
    now()
  );

  if v_user_id is null or v_source_run_id is null then
    return new;
  end if;

  if not exists (
    select 1
    from public.profiles profile
    where profile.id = v_user_id
  ) then
    return new;
  end if;

  insert into public.account_service_events (
    user_id,
    source_table,
    source_run_id,
    action_type,
    source_revision,
    event_fingerprint,
    occurred_at
  )
  values (
    v_user_id,
    tg_table_name,
    v_source_run_id,
    v_action_type,
    v_source_revision,
    public.account_service_event_fingerprint_v1(
      v_user_id,
      tg_table_name,
      v_source_run_id,
      v_action_type,
      v_source_revision,
      v_occurred_at
    ),
    v_occurred_at
  )
  on conflict (source_table, source_run_id) do nothing
  returning id into v_event_id;

  if v_event_id is null then
    return new;
  end if;

  insert into public.account_service_states (
    user_id,
    revision,
    protected_service_count,
    last_source_table,
    last_action_type,
    last_activity_at,
    state_fingerprint,
    updated_at
  )
  values (
    v_user_id,
    0,
    8,
    null,
    null,
    null,
    public.leghevo_sha256_hex_v1(
      concat_ws('|', 'account-service-state-v1', v_user_id::text, '0', '8')
    ),
    now()
  )
  on conflict (user_id) do nothing;

  select state.revision + 1
  into v_next_revision
  from public.account_service_states state
  where state.user_id = v_user_id
  for update;

  update public.account_service_states state
  set
    revision = v_next_revision,
    protected_service_count = 8,
    last_source_table = tg_table_name,
    last_action_type = v_action_type,
    last_activity_at = v_occurred_at,
    state_fingerprint = public.leghevo_sha256_hex_v1(
      concat_ws(
        '|',
        'account-service-state-v1',
        v_user_id::text,
        v_next_revision::text,
        '8',
        tg_table_name,
        v_action_type,
        v_source_run_id::text,
        v_occurred_at::text
      )
    ),
    updated_at = now()
  where state.user_id = v_user_id;

  return new;
end;
$$;

revoke all on function public.capture_account_service_activity_v1()
from public, anon, authenticated;

-- Un trigger uniforme per ciascun registro certificato dello Sviluppo 7.
do $source_triggers$
declare
  v_table text;
  v_trigger text;
begin
  foreach v_table in array array[
    'data_rights_request_action_runs',
    'support_request_action_runs',
    'push_preference_action_runs',
    'account_action_runs',
    'legal_acceptance_action_runs',
    'notification_action_runs',
    'account_security_events',
    'personal_data_export_runs'
  ]
  loop
    v_trigger := 'zz_account_service_hub_' || v_table;
    execute format('drop trigger if exists %I on public.%I', v_trigger, v_table);
    execute format(
      'create trigger %I after insert on public.%I for each row execute function public.capture_account_service_activity_v1()',
      v_trigger,
      v_table
    );
  end loop;
end;
$source_triggers$;

-- ---------------------------------------------------------------------------
-- Backfill non distruttivo: ogni azione già certificata viene collegata al
-- nuovo hub, senza riscrivere i registri sorgente.
-- ---------------------------------------------------------------------------
do $backfill_events$
declare
  v_table text;
begin
  foreach v_table in array array[
    'data_rights_request_action_runs',
    'support_request_action_runs',
    'push_preference_action_runs',
    'account_action_runs',
    'legal_acceptance_action_runs',
    'notification_action_runs',
    'account_security_events',
    'personal_data_export_runs'
  ]
  loop
    execute format($sql$
      insert into public.account_service_events (
        user_id,
        source_table,
        source_run_id,
        action_type,
        source_revision,
        event_fingerprint,
        occurred_at
      )
      select
        (to_jsonb(source_row) ->> 'user_id')::uuid,
        %L,
        (to_jsonb(source_row) ->> 'id')::uuid,
        coalesce(
          nullif(to_jsonb(source_row) ->> 'action_type', ''),
          nullif(to_jsonb(source_row) ->> 'event_type', ''),
          case when %L = 'personal_data_export_runs'
            then 'personal_data_export'
            else 'service_action'
          end
        ),
        nullif(
          coalesce(
            to_jsonb(source_row) ->> 'result_revision',
            to_jsonb(source_row) ->> 'security_revision',
            to_jsonb(source_row) ->> 'export_revision'
          ),
          ''
        )::bigint,
        public.account_service_event_fingerprint_v1(
          (to_jsonb(source_row) ->> 'user_id')::uuid,
          %L,
          (to_jsonb(source_row) ->> 'id')::uuid,
          coalesce(
            nullif(to_jsonb(source_row) ->> 'action_type', ''),
            nullif(to_jsonb(source_row) ->> 'event_type', ''),
            case when %L = 'personal_data_export_runs'
              then 'personal_data_export'
              else 'service_action'
            end
          ),
          nullif(
            coalesce(
              to_jsonb(source_row) ->> 'result_revision',
              to_jsonb(source_row) ->> 'security_revision',
              to_jsonb(source_row) ->> 'export_revision'
            ),
            ''
          )::bigint,
          coalesce(
            nullif(to_jsonb(source_row) ->> 'occurred_at', '')::timestamptz,
            nullif(to_jsonb(source_row) ->> 'created_at', '')::timestamptz,
            now()
          )
        ),
        coalesce(
          nullif(to_jsonb(source_row) ->> 'occurred_at', '')::timestamptz,
          nullif(to_jsonb(source_row) ->> 'created_at', '')::timestamptz,
          now()
        )
      from public.%I source_row
      where nullif(to_jsonb(source_row) ->> 'user_id', '') is not null
        and nullif(to_jsonb(source_row) ->> 'id', '') is not null
        and exists (
          select 1
          from public.profiles profile
          where profile.id = (to_jsonb(source_row) ->> 'user_id')::uuid
        )
      on conflict (source_table, source_run_id) do nothing
    $sql$, v_table, v_table, v_table, v_table, v_table);
  end loop;
end;
$backfill_events$;

-- Lo stato viene ricostruito in modo deterministico dagli eventi unificati.
insert into public.account_service_states (
  user_id,
  revision,
  protected_service_count,
  last_source_table,
  last_action_type,
  last_activity_at,
  state_fingerprint,
  updated_at
)
select
  profile.id,
  coalesce(summary.event_count, 0),
  8,
  latest.source_table,
  latest.action_type,
  latest.occurred_at,
  public.leghevo_sha256_hex_v1(
    concat_ws(
      '|',
      'account-service-state-v1',
      profile.id::text,
      coalesce(summary.event_count, 0)::text,
      '8',
      coalesce(latest.source_table, ''),
      coalesce(latest.action_type, ''),
      coalesce(latest.source_run_id::text, ''),
      coalesce(latest.occurred_at::text, '')
    )
  ),
  now()
from public.profiles profile
left join lateral (
  select count(*)::bigint as event_count
  from public.account_service_events event
  where event.user_id = profile.id
) summary on true
left join lateral (
  select
    event.source_table,
    event.action_type,
    event.source_run_id,
    event.occurred_at
  from public.account_service_events event
  where event.user_id = profile.id
  order by event.occurred_at desc, event.id desc
  limit 1
) latest on true
on conflict (user_id) do update
set
  revision = excluded.revision,
  protected_service_count = excluded.protected_service_count,
  last_source_table = excluded.last_source_table,
  last_action_type = excluded.last_action_type,
  last_activity_at = excluded.last_activity_at,
  state_fingerprint = excluded.state_fingerprint,
  updated_at = excluded.updated_at;

-- ---------------------------------------------------------------------------
-- Centro unificato utente e Centro Account v4.
-- ---------------------------------------------------------------------------
create or replace function public.get_my_account_service_hub_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_account jsonb;
  v_privacy jsonb;
  v_rights jsonb;
  v_support jsonb;
  v_push jsonb;
  v_notifications jsonb;
  v_state public.account_service_states%rowtype;
  v_profile_ready boolean;
  v_credentials_ready boolean;
  v_legal_ready boolean;
  v_export_ready boolean;
  v_rights_ready boolean;
  v_support_ready boolean;
  v_push_ready boolean;
  v_notifications_ready boolean;
  v_protected_count integer;
begin
  if v_user_id is null then
    raise exception 'Devi effettuare l''accesso.';
  end if;

  v_account := public.get_my_account_center_v3();
  v_privacy := public.get_my_privacy_center_v4();
  v_rights := public.get_my_data_rights_center_v2();
  v_support := public.get_my_support_center_v2();
  v_push := public.get_my_push_notification_preferences_v2();
  v_notifications := public.get_my_notification_center_v2(1);

  select state.*
  into v_state
  from public.account_service_states state
  where state.user_id = v_user_id;

  v_profile_ready := coalesce((v_account ->> 'protected')::boolean, false);
  v_credentials_ready := coalesce(
    (v_account ->> 'securityProtected')::boolean,
    false
  );
  v_legal_ready := coalesce(
    (v_privacy #>> '{protection,guardedActionsReady}')::boolean,
    (v_privacy ->> 'protected')::boolean,
    true
  );
  v_export_ready := coalesce((v_privacy ->> 'exportProtected')::boolean, false);
  v_rights_ready := coalesce(
    (v_rights #>> '{protection,guardedActionsReady}')::boolean,
    false
  );
  v_support_ready := coalesce(
    (v_support #>> '{protection,guardedActionsReady}')::boolean,
    false
  );
  v_push_ready := coalesce(
    (v_push #>> '{protection,guardedActionsReady}')::boolean,
    (v_push ->> 'protected')::boolean,
    true
  );
  v_notifications_ready := coalesce(
    (v_notifications ->> 'protected')::boolean,
    false
  );

  v_protected_count :=
    v_profile_ready::integer
    + v_credentials_ready::integer
    + v_legal_ready::integer
    + v_export_ready::integer
    + v_rights_ready::integer
    + v_support_ready::integer
    + v_push_ready::integer
    + v_notifications_ready::integer;

  return jsonb_build_object(
    'generatedAt', now(),
    'revision', coalesce(v_state.revision, 0),
    'stateFingerprint', v_state.state_fingerprint,
    'lastActivityAt', v_state.last_activity_at,
    'lastSourceTable', v_state.last_source_table,
    'lastActionType', v_state.last_action_type,
    'totalServiceCount', 8,
    'protectedServiceCount', v_protected_count,
    'allProtected', v_protected_count = 8,
    'services', jsonb_build_object(
      'profile', jsonb_build_object('protected', v_profile_ready),
      'credentials', jsonb_build_object('protected', v_credentials_ready),
      'legalAcceptance', jsonb_build_object('protected', v_legal_ready),
      'personalDataExport', jsonb_build_object(
        'protected', v_export_ready,
        'revision', coalesce((v_privacy ->> 'exportRevision')::bigint, 0)
      ),
      'dataRights', jsonb_build_object(
        'protected', v_rights_ready,
        'openCount', coalesce((v_rights ->> 'openCount')::integer, 0)
      ),
      'support', jsonb_build_object(
        'protected', v_support_ready,
        'openCount', coalesce((v_support ->> 'openCount')::integer, 0)
      ),
      'push', jsonb_build_object('protected', v_push_ready),
      'notifications', jsonb_build_object(
        'protected', v_notifications_ready,
        'unreadCount', coalesce((v_notifications ->> 'unreadCount')::integer, 0)
      )
    )
  );
end;
$$;

create or replace function public.get_my_account_center_v4()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'Devi effettuare l''accesso.';
  end if;

  return public.get_my_account_center_v3()
    || jsonb_build_object(
      'serviceHub', public.get_my_account_service_hub_v1(),
      'generatedAt', now()
    );
end;
$$;

revoke all on function public.get_my_account_service_hub_v1()
from public, anon, authenticated;
revoke all on function public.get_my_account_center_v4()
from public, anon, authenticated;
grant execute on function public.get_my_account_service_hub_v1()
to authenticated;
grant execute on function public.get_my_account_center_v4()
to authenticated;

-- Realtime idempotente per stato e registro unificati.
do $realtime$
declare
  v_table text;
begin
  foreach v_table in array array[
    'account_service_states',
    'account_service_events'
  ]
  loop
    if not exists (
      select 1
      from pg_catalog.pg_publication_tables publication_table
      where publication_table.pubname = 'supabase_realtime'
        and publication_table.schemaname = 'public'
        and publication_table.tablename = v_table
    ) then
      execute format(
        'alter publication supabase_realtime add table public.%I',
        v_table
      );
    end if;
  end loop;
end;
$realtime$;

-- ---------------------------------------------------------------------------
-- Diagnostica strutturale v0.61.9: esattamente 20 valori booleani.
-- ---------------------------------------------------------------------------
create or replace function public.get_account_services_integrity_hub_v1()
returns table (
  account_service_states_ready boolean,
  account_service_events_ready boolean,
  states_rls_ready boolean,
  events_rls_ready boolean,
  states_policy_ready boolean,
  events_policy_ready boolean,
  immutable_trigger_ready boolean,
  source_triggers_ready boolean,
  capture_function_ready boolean,
  fingerprint_function_ready boolean,
  service_hub_rpc_ready boolean,
  account_center_v4_ready boolean,
  authenticated_hub_execute_ready boolean,
  authenticated_center_execute_ready boolean,
  anonymous_hub_blocked boolean,
  direct_state_write_blocked boolean,
  direct_event_write_blocked boolean,
  states_realtime_ready boolean,
  events_realtime_ready boolean,
  data_continuity_ready boolean
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    to_regclass('public.account_service_states') is not null,
    to_regclass('public.account_service_events') is not null,
    coalesce((
      select table_row.relrowsecurity
      from pg_catalog.pg_class table_row
      where table_row.oid = to_regclass('public.account_service_states')
    ), false),
    coalesce((
      select table_row.relrowsecurity
      from pg_catalog.pg_class table_row
      where table_row.oid = to_regclass('public.account_service_events')
    ), false),
    exists (
      select 1
      from pg_catalog.pg_policies policy_row
      where policy_row.schemaname = 'public'
        and policy_row.tablename = 'account_service_states'
        and policy_row.policyname = 'account_service_states_read_own'
    ),
    exists (
      select 1
      from pg_catalog.pg_policies policy_row
      where policy_row.schemaname = 'public'
        and policy_row.tablename = 'account_service_events'
        and policy_row.policyname = 'account_service_events_read_own'
    ),
    exists (
      select 1
      from pg_catalog.pg_trigger trigger_row
      where trigger_row.tgrelid = to_regclass('public.account_service_events')
        and trigger_row.tgname = 'account_service_events_immutable'
        and not trigger_row.tgisinternal
    ),
    (
      select count(*) = 8
      from pg_catalog.pg_trigger trigger_row
      join pg_catalog.pg_class table_row
        on table_row.oid = trigger_row.tgrelid
      join pg_catalog.pg_namespace namespace_row
        on namespace_row.oid = table_row.relnamespace
      where namespace_row.nspname = 'public'
        and trigger_row.tgname like 'zz_account_service_hub_%'
        and not trigger_row.tgisinternal
    ),
    to_regprocedure('public.capture_account_service_activity_v1()') is not null,
    to_regprocedure(
      'public.account_service_event_fingerprint_v1(uuid,text,uuid,text,bigint,timestamp with time zone)'
    ) is not null,
    to_regprocedure('public.get_my_account_service_hub_v1()') is not null,
    to_regprocedure('public.get_my_account_center_v4()') is not null,
    has_function_privilege(
      'authenticated',
      'public.get_my_account_service_hub_v1()',
      'EXECUTE'
    ),
    has_function_privilege(
      'authenticated',
      'public.get_my_account_center_v4()',
      'EXECUTE'
    ),
    not has_function_privilege(
      'anon',
      'public.get_my_account_service_hub_v1()',
      'EXECUTE'
    ),
    not has_table_privilege(
      'authenticated',
      'public.account_service_states',
      'INSERT'
    )
    and not has_table_privilege(
      'authenticated',
      'public.account_service_states',
      'UPDATE'
    )
    and not has_table_privilege(
      'authenticated',
      'public.account_service_states',
      'DELETE'
    ),
    not has_table_privilege(
      'authenticated',
      'public.account_service_events',
      'INSERT'
    )
    and not has_table_privilege(
      'authenticated',
      'public.account_service_events',
      'UPDATE'
    )
    and not has_table_privilege(
      'authenticated',
      'public.account_service_events',
      'DELETE'
    ),
    exists (
      select 1
      from pg_catalog.pg_publication_tables publication_table
      where publication_table.pubname = 'supabase_realtime'
        and publication_table.schemaname = 'public'
        and publication_table.tablename = 'account_service_states'
    ),
    exists (
      select 1
      from pg_catalog.pg_publication_tables publication_table
      where publication_table.pubname = 'supabase_realtime'
        and publication_table.schemaname = 'public'
        and publication_table.tablename = 'account_service_events'
    ),
    not exists (
      select 1
      from public.account_service_states state
      where char_length(state.state_fingerprint) <> 64
        or state.protected_service_count <> 8
    )
    and not exists (
      select 1
      from public.account_service_events event
      where char_length(event.event_fingerprint) <> 64
    )
    and not exists (
      select 1
      from public.profiles profile
      left join public.account_service_states state
        on state.user_id = profile.id
      where state.user_id is null
    );
$$;

revoke all on function public.get_account_services_integrity_hub_v1()
from public, anon, authenticated;
grant execute on function public.get_account_services_integrity_hub_v1()
to authenticated, service_role;

-- Controllo transazionale: in caso di futuro errore indica i nomi precisi.
do $validate$
declare
  v_row record;
  v_false text[] := array[]::text[];
begin
  select * into v_row
  from public.get_account_services_integrity_hub_v1();

  if not v_row.account_service_states_ready then v_false := array_append(v_false, 'account_service_states_ready'); end if;
  if not v_row.account_service_events_ready then v_false := array_append(v_false, 'account_service_events_ready'); end if;
  if not v_row.states_rls_ready then v_false := array_append(v_false, 'states_rls_ready'); end if;
  if not v_row.events_rls_ready then v_false := array_append(v_false, 'events_rls_ready'); end if;
  if not v_row.states_policy_ready then v_false := array_append(v_false, 'states_policy_ready'); end if;
  if not v_row.events_policy_ready then v_false := array_append(v_false, 'events_policy_ready'); end if;
  if not v_row.immutable_trigger_ready then v_false := array_append(v_false, 'immutable_trigger_ready'); end if;
  if not v_row.source_triggers_ready then v_false := array_append(v_false, 'source_triggers_ready'); end if;
  if not v_row.capture_function_ready then v_false := array_append(v_false, 'capture_function_ready'); end if;
  if not v_row.fingerprint_function_ready then v_false := array_append(v_false, 'fingerprint_function_ready'); end if;
  if not v_row.service_hub_rpc_ready then v_false := array_append(v_false, 'service_hub_rpc_ready'); end if;
  if not v_row.account_center_v4_ready then v_false := array_append(v_false, 'account_center_v4_ready'); end if;
  if not v_row.authenticated_hub_execute_ready then v_false := array_append(v_false, 'authenticated_hub_execute_ready'); end if;
  if not v_row.authenticated_center_execute_ready then v_false := array_append(v_false, 'authenticated_center_execute_ready'); end if;
  if not v_row.anonymous_hub_blocked then v_false := array_append(v_false, 'anonymous_hub_blocked'); end if;
  if not v_row.direct_state_write_blocked then v_false := array_append(v_false, 'direct_state_write_blocked'); end if;
  if not v_row.direct_event_write_blocked then v_false := array_append(v_false, 'direct_event_write_blocked'); end if;
  if not v_row.states_realtime_ready then v_false := array_append(v_false, 'states_realtime_ready'); end if;
  if not v_row.events_realtime_ready then v_false := array_append(v_false, 'events_realtime_ready'); end if;
  if not v_row.data_continuity_ready then v_false := array_append(v_false, 'data_continuity_ready'); end if;

  if cardinality(v_false) > 0 then
    raise exception 'LEGHEVO v0.61.9 controlli falliti: %',
      array_to_string(v_false, ', ');
  end if;
end;
$validate$;

commit;

select * from public.get_account_services_integrity_hub_v1();
