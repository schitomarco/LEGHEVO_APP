-- LEGHEVO v0.61.3 · Preferenze e dispositivi push protetti
-- Migrazione interna: database/097_push_preferences_and_device_safety.sql
--
-- Obiettivi:
-- - salvataggio preferenze idempotente e revisionato;
-- - registrazione e disattivazione dispositivi protette;
-- - blocco del trasferimento silenzioso di token attivi tra account;
-- - registro immutabile delle azioni push dell'utente;
-- - compatibilità con le RPC storiche;
-- - nessuna modifica distruttiva alle preferenze, ai dispositivi o alle consegne.

begin;

-- Preflight dettagliato: interrompe prima di qualsiasi modifica se lo schema 053
-- non è realmente disponibile con le colonne necessarie.
do $preflight$
declare
  v_missing text[] := array[]::text[];
  v_expected record;
begin
  if to_regclass('public.profiles') is null then
    v_missing := array_append(v_missing, 'table public.profiles');
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
  if to_regprocedure(
    'public.push_category_is_enabled(text,public.user_notification_preferences)'
  ) is null then
    v_missing := array_append(
      v_missing,
      'function public.push_category_is_enabled(text,public.user_notification_preferences)'
    );
  end if;

  for v_expected in
    select *
    from (values
      ('profiles', 'id'),
      ('user_notifications', 'id'),
      ('user_notifications', 'user_id'),
      ('user_notifications', 'kind'),
      ('user_notification_preferences', 'user_id'),
      ('user_notification_preferences', 'push_enabled'),
      ('user_notification_preferences', 'auction_trade_enabled'),
      ('user_notification_preferences', 'lineup_enabled'),
      ('user_notification_preferences', 'results_enabled'),
      ('user_notification_preferences', 'league_enabled'),
      ('user_notification_preferences', 'system_enabled'),
      ('user_notification_preferences', 'created_at'),
      ('user_notification_preferences', 'updated_at'),
      ('user_push_devices', 'id'),
      ('user_push_devices', 'user_id'),
      ('user_push_devices', 'expo_push_token'),
      ('user_push_devices', 'platform'),
      ('user_push_devices', 'device_name'),
      ('user_push_devices', 'app_version'),
      ('user_push_devices', 'enabled'),
      ('user_push_devices', 'registered_at'),
      ('user_push_devices', 'last_seen_at'),
      ('user_push_devices', 'disabled_at'),
      ('notification_push_deliveries', 'notification_id'),
      ('notification_push_deliveries', 'device_id'),
      ('notification_push_deliveries', 'user_id'),
      ('notification_push_deliveries', 'status'),
      ('notification_push_deliveries', 'error_code'),
      ('notification_push_deliveries', 'error_message'),
      ('notification_push_deliveries', 'completed_at')
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

  if coalesce(array_length(v_missing, 1), 0) > 0 then
    raise exception
      'Preflight v0.61.3 non superato. Oggetti mancanti: %',
      array_to_string(v_missing, '; ');
  end if;
end;
$preflight$;

alter table public.user_notification_preferences
  add column if not exists revision bigint not null default 1,
  add column if not exists preference_fingerprint text;

alter table public.user_push_devices
  add column if not exists revision bigint not null default 1,
  add column if not exists token_fingerprint text;

create or replace function public.push_preferences_fingerprint_v1(
  p_push_enabled boolean,
  p_auction_trade_enabled boolean,
  p_lineup_enabled boolean,
  p_results_enabled boolean,
  p_league_enabled boolean,
  p_system_enabled boolean
)
returns text
language sql
immutable
set search_path = ''
as $$
  select pg_catalog.md5(
    pg_catalog.concat_ws(
      '|',
      coalesce(p_push_enabled, false)::text,
      coalesce(p_auction_trade_enabled, true)::text,
      coalesce(p_lineup_enabled, true)::text,
      coalesce(p_results_enabled, true)::text,
      coalesce(p_league_enabled, true)::text,
      coalesce(p_system_enabled, true)::text
    )
  );
$$;

create or replace function public.push_device_token_fingerprint_v1(
  p_expo_push_token text
)
returns text
language sql
immutable
set search_path = ''
as $$
  select pg_catalog.md5(trim(coalesce(p_expo_push_token, '')));
$$;

revoke all on function public.push_preferences_fingerprint_v1(
  boolean, boolean, boolean, boolean, boolean, boolean
) from public, anon, authenticated;
revoke all on function public.push_device_token_fingerprint_v1(text)
from public, anon, authenticated;

update public.user_notification_preferences preferences
set preference_fingerprint = public.push_preferences_fingerprint_v1(
  preferences.push_enabled,
  preferences.auction_trade_enabled,
  preferences.lineup_enabled,
  preferences.results_enabled,
  preferences.league_enabled,
  preferences.system_enabled
)
where preferences.preference_fingerprint is null
   or char_length(preferences.preference_fingerprint) <> 32;

update public.user_push_devices device
set token_fingerprint = public.push_device_token_fingerprint_v1(
  device.expo_push_token
)
where device.token_fingerprint is null
   or char_length(device.token_fingerprint) <> 32;

alter table public.user_notification_preferences
  alter column preference_fingerprint set not null;
alter table public.user_push_devices
  alter column token_fingerprint set not null;

alter table public.user_notification_preferences
  drop constraint if exists user_notification_preferences_revision_check;
alter table public.user_notification_preferences
  add constraint user_notification_preferences_revision_check
  check (revision > 0);

alter table public.user_notification_preferences
  drop constraint if exists user_notification_preferences_fingerprint_check;
alter table public.user_notification_preferences
  add constraint user_notification_preferences_fingerprint_check
  check (char_length(preference_fingerprint) = 32);

alter table public.user_push_devices
  drop constraint if exists user_push_devices_revision_check;
alter table public.user_push_devices
  add constraint user_push_devices_revision_check
  check (revision > 0);

alter table public.user_push_devices
  drop constraint if exists user_push_devices_token_fingerprint_check;
alter table public.user_push_devices
  add constraint user_push_devices_token_fingerprint_check
  check (char_length(token_fingerprint) = 32);

create index if not exists user_push_devices_fingerprint_idx
  on public.user_push_devices (token_fingerprint);

create table if not exists public.push_preference_action_runs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null,
  device_id uuid,
  action_type text not null check (
    action_type in (
      'preferences_save',
      'device_register',
      'device_disable',
      'device_release'
    )
  ),
  idempotency_key uuid not null unique,
  expected_revision bigint,
  result_revision bigint not null check (result_revision >= 0),
  token_fingerprint text check (
    token_fingerprint is null or char_length(token_fingerprint) = 32
  ),
  payload_fingerprint text not null check (
    char_length(payload_fingerprint) = 32
  ),
  result_snapshot jsonb not null check (
    jsonb_typeof(result_snapshot) = 'object'
  ),
  created_at timestamptz not null default now()
);

create index if not exists push_preference_action_runs_user_idx
  on public.push_preference_action_runs (user_id, created_at desc);
create index if not exists push_preference_action_runs_device_idx
  on public.push_preference_action_runs (device_id, created_at desc)
  where device_id is not null;

alter table public.push_preference_action_runs enable row level security;
alter table public.push_preference_action_runs replica identity full;
alter table public.user_notification_preferences replica identity full;
alter table public.user_push_devices replica identity full;

drop policy if exists push_preference_action_runs_read_own
on public.push_preference_action_runs;
create policy push_preference_action_runs_read_own
on public.push_preference_action_runs
for select to authenticated
using (user_id = auth.uid());

revoke all on table public.push_preference_action_runs
from public, anon, authenticated;
grant select on table public.push_preference_action_runs
to authenticated;

create or replace function public.prevent_push_preference_action_run_mutation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  raise exception
    'Operazione push certificata: modifica o cancellazione diretta non consentita.';
end;
$$;

revoke all on function public.prevent_push_preference_action_run_mutation()
from public, anon, authenticated;

drop trigger if exists push_preference_action_runs_immutable
on public.push_preference_action_runs;
create trigger push_preference_action_runs_immutable
before update or delete on public.push_preference_action_runs
for each row execute function public.prevent_push_preference_action_run_mutation();

create or replace function public.push_preferences_payload_v2(
  p_user_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_preferences public.user_notification_preferences%rowtype;
begin
  select preferences.*
  into v_preferences
  from public.user_notification_preferences preferences
  where preferences.user_id = p_user_id;

  return jsonb_build_object(
    'pushEnabled', coalesce(v_preferences.push_enabled, false),
    'auctionTradeEnabled', coalesce(v_preferences.auction_trade_enabled, true),
    'lineupEnabled', coalesce(v_preferences.lineup_enabled, true),
    'resultsEnabled', coalesce(v_preferences.results_enabled, true),
    'leagueEnabled', coalesce(v_preferences.league_enabled, true),
    'systemEnabled', coalesce(v_preferences.system_enabled, true),
    'revision', coalesce(v_preferences.revision, 0),
    'protected', true,
    'preferenceFingerprint', v_preferences.preference_fingerprint,
    'activeDeviceCount', (
      select count(*)::integer
      from public.user_push_devices device
      where device.user_id = p_user_id
        and device.enabled
    ),
    'certifiedActionCount', (
      select count(*)::integer
      from public.push_preference_action_runs run
      where run.user_id = p_user_id
    ),
    'lastCertifiedAt', (
      select max(run.created_at)
      from public.push_preference_action_runs run
      where run.user_id = p_user_id
    ),
    'devices', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', device.id,
          'platform', device.platform,
          'deviceName', device.device_name,
          'appVersion', device.app_version,
          'enabled', device.enabled,
          'registeredAt', device.registered_at,
          'lastSeenAt', device.last_seen_at,
          'revision', device.revision,
          'tokenFingerprint', device.token_fingerprint
        )
        order by device.last_seen_at desc, device.id
      )
      from public.user_push_devices device
      where device.user_id = p_user_id
    ), '[]'::jsonb)
  );
end;
$$;

revoke all on function public.push_preferences_payload_v2(uuid)
from public, anon, authenticated;

create or replace function public.get_my_push_notification_preferences_v2()
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

  return public.push_preferences_payload_v2(auth.uid());
end;
$$;

create or replace function public.save_my_push_notification_preferences_guarded_v1(
  p_push_enabled boolean,
  p_auction_trade_enabled boolean,
  p_lineup_enabled boolean,
  p_results_enabled boolean,
  p_league_enabled boolean,
  p_system_enabled boolean,
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
  v_preferences public.user_notification_preferences%rowtype;
  v_run public.push_preference_action_runs%rowtype;
  v_now timestamptz := now();
  v_fingerprint text;
  v_changed boolean := false;
  v_disabled_devices integer := 0;
  v_snapshot jsonb;
begin
  if v_user_id is null then
    raise exception 'Devi effettuare l''accesso.';
  end if;
  if p_idempotency_key is null then
    raise exception 'Identificativo operazione mancante.';
  end if;
  if p_expected_revision is null or p_expected_revision < 0 then
    raise exception 'Revisione preferenze non valida.';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('leghevo:push:user:' || v_user_id::text, 0)
  );

  select run.*
  into v_run
  from public.push_preference_action_runs run
  where run.idempotency_key = p_idempotency_key;

  if found then
    if v_run.user_id <> v_user_id
      or v_run.action_type <> 'preferences_save' then
      raise exception 'Identificativo già usato per un''altra operazione.';
    end if;
    return v_run.result_snapshot || jsonb_build_object(
      'idempotentReplay', true,
      'changed', false
    );
  end if;

  select preferences.*
  into v_preferences
  from public.user_notification_preferences preferences
  where preferences.user_id = v_user_id
  for update;

  if not found then
    if coalesce(p_expected_revision, 0) <> 0 then
      raise exception
        'Le preferenze sono cambiate su un altro dispositivo. Ricarica e riprova.';
    end if;

    v_fingerprint := public.push_preferences_fingerprint_v1(
      p_push_enabled,
      p_auction_trade_enabled,
      p_lineup_enabled,
      p_results_enabled,
      p_league_enabled,
      p_system_enabled
    );

    insert into public.user_notification_preferences (
      user_id,
      push_enabled,
      auction_trade_enabled,
      lineup_enabled,
      results_enabled,
      league_enabled,
      system_enabled,
      revision,
      preference_fingerprint,
      created_at,
      updated_at
    ) values (
      v_user_id,
      coalesce(p_push_enabled, false),
      coalesce(p_auction_trade_enabled, true),
      coalesce(p_lineup_enabled, true),
      coalesce(p_results_enabled, true),
      coalesce(p_league_enabled, true),
      coalesce(p_system_enabled, true),
      1,
      v_fingerprint,
      v_now,
      v_now
    )
    returning * into v_preferences;

    v_changed := true;
  else
    if v_preferences.revision <> p_expected_revision then
      raise exception
        'Le preferenze sono cambiate su un altro dispositivo. Ricarica e riprova.';
    end if;

    v_fingerprint := public.push_preferences_fingerprint_v1(
      p_push_enabled,
      p_auction_trade_enabled,
      p_lineup_enabled,
      p_results_enabled,
      p_league_enabled,
      p_system_enabled
    );

    if v_preferences.preference_fingerprint <> v_fingerprint then
      update public.user_notification_preferences preferences
      set
        push_enabled = coalesce(p_push_enabled, false),
        auction_trade_enabled = coalesce(p_auction_trade_enabled, true),
        lineup_enabled = coalesce(p_lineup_enabled, true),
        results_enabled = coalesce(p_results_enabled, true),
        league_enabled = coalesce(p_league_enabled, true),
        system_enabled = coalesce(p_system_enabled, true),
        revision = preferences.revision + 1,
        preference_fingerprint = v_fingerprint,
        updated_at = v_now
      where preferences.user_id = v_user_id
      returning * into v_preferences;

      v_changed := true;
    end if;
  end if;

  if not v_preferences.push_enabled then
    update public.user_push_devices device
    set
      enabled = false,
      disabled_at = coalesce(device.disabled_at, v_now),
      revision = device.revision + 1
    where device.user_id = v_user_id
      and device.enabled;
    get diagnostics v_disabled_devices = row_count;
  end if;

  update public.notification_push_deliveries delivery
  set
    status = 'skipped',
    error_code = 'UserPreferenceDisabled',
    error_message = 'Invio disattivato nelle preferenze utente.',
    completed_at = v_now
  from public.user_notifications notification
  where delivery.notification_id = notification.id
    and delivery.user_id = v_user_id
    and delivery.status in ('queued', 'processing')
    and (
      not v_preferences.push_enabled
      or not public.push_category_is_enabled(
        notification.kind,
        v_preferences
      )
    );

  v_snapshot := public.push_preferences_payload_v2(v_user_id)
    || jsonb_build_object(
      'changed', v_changed,
      'disabledDeviceCount', v_disabled_devices,
      'certifiedAt', v_now
    );

  insert into public.push_preference_action_runs (
    user_id,
    action_type,
    idempotency_key,
    expected_revision,
    result_revision,
    payload_fingerprint,
    result_snapshot,
    created_at
  ) values (
    v_user_id,
    'preferences_save',
    p_idempotency_key,
    p_expected_revision,
    v_preferences.revision,
    v_fingerprint,
    v_snapshot,
    v_now
  );

  return public.push_preferences_payload_v2(v_user_id)
    || jsonb_build_object(
      'idempotentReplay', false,
      'changed', v_changed,
      'disabledDeviceCount', v_disabled_devices
    );
end;
$$;

create or replace function public.register_my_push_device_guarded_v1(
  p_expo_push_token text,
  p_platform text,
  p_device_name text,
  p_app_version text,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_token text := trim(coalesce(p_expo_push_token, ''));
  v_platform text := lower(trim(coalesce(p_platform, '')));
  v_name text := nullif(trim(coalesce(p_device_name, '')), '');
  v_version text := nullif(trim(coalesce(p_app_version, '')), '');
  v_token_fingerprint text;
  v_device public.user_push_devices%rowtype;
  v_preferences public.user_notification_preferences%rowtype;
  v_run public.push_preference_action_runs%rowtype;
  v_now timestamptz := now();
  v_payload_fingerprint text;
  v_snapshot jsonb;
begin
  if v_user_id is null then
    raise exception 'Devi effettuare l''accesso.';
  end if;
  if p_idempotency_key is null then
    raise exception 'Identificativo operazione mancante.';
  end if;
  if v_token !~ '^Expo(nent)?PushToken\[[A-Za-z0-9_-]+\]$' then
    raise exception 'Token Expo Push non valido.';
  end if;
  if v_platform not in ('ios', 'android') then
    raise exception 'Piattaforma del dispositivo non valida.';
  end if;
  if v_name is not null and char_length(v_name) > 80 then
    raise exception 'Nome dispositivo non valido.';
  end if;
  if v_version is not null and char_length(v_version) > 30 then
    raise exception 'Versione app non valida.';
  end if;

  v_token_fingerprint := public.push_device_token_fingerprint_v1(v_token);
  v_payload_fingerprint := pg_catalog.md5(
    v_token_fingerprint || E'\n' || v_platform || E'\n' ||
    coalesce(v_name, '') || E'\n' || coalesce(v_version, '')
  );

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('leghevo:push:user:' || v_user_id::text, 0)
  );
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('leghevo:push:token:' || v_token_fingerprint, 0)
  );

  select run.*
  into v_run
  from public.push_preference_action_runs run
  where run.idempotency_key = p_idempotency_key;

  if found then
    if v_run.user_id <> v_user_id
      or v_run.action_type <> 'device_register'
      or v_run.token_fingerprint is distinct from v_token_fingerprint then
      raise exception 'Identificativo già usato per un''altra operazione.';
    end if;
    return v_run.result_snapshot || jsonb_build_object(
      'idempotentReplay', true
    );
  end if;

  select device.*
  into v_device
  from public.user_push_devices device
  where device.expo_push_token = v_token
  for update;

  if found then
    if v_device.user_id <> v_user_id and v_device.enabled then
      raise exception
        'Questo dispositivo risulta ancora attivo su un altro account. Disconnetti prima l''account precedente.';
    end if;

    update public.user_push_devices device
    set
      user_id = v_user_id,
      platform = v_platform,
      device_name = v_name,
      app_version = v_version,
      enabled = true,
      last_seen_at = v_now,
      disabled_at = null,
      token_fingerprint = v_token_fingerprint,
      revision = device.revision + 1
    where device.id = v_device.id
    returning * into v_device;
  else
    insert into public.user_push_devices (
      user_id,
      expo_push_token,
      platform,
      device_name,
      app_version,
      enabled,
      registered_at,
      last_seen_at,
      disabled_at,
      revision,
      token_fingerprint
    ) values (
      v_user_id,
      v_token,
      v_platform,
      v_name,
      v_version,
      true,
      v_now,
      v_now,
      null,
      1,
      v_token_fingerprint
    )
    returning * into v_device;
  end if;

  select preferences.*
  into v_preferences
  from public.user_notification_preferences preferences
  where preferences.user_id = v_user_id
  for update;

  if not found then
    insert into public.user_notification_preferences (
      user_id,
      push_enabled,
      auction_trade_enabled,
      lineup_enabled,
      results_enabled,
      league_enabled,
      system_enabled,
      revision,
      preference_fingerprint,
      created_at,
      updated_at
    ) values (
      v_user_id,
      true,
      true,
      true,
      true,
      true,
      true,
      1,
      public.push_preferences_fingerprint_v1(
        true, true, true, true, true, true
      ),
      v_now,
      v_now
    )
    returning * into v_preferences;
  elsif not v_preferences.push_enabled then
    update public.user_notification_preferences preferences
    set
      push_enabled = true,
      revision = preferences.revision + 1,
      preference_fingerprint = public.push_preferences_fingerprint_v1(
        true,
        preferences.auction_trade_enabled,
        preferences.lineup_enabled,
        preferences.results_enabled,
        preferences.league_enabled,
        preferences.system_enabled
      ),
      updated_at = v_now
    where preferences.user_id = v_user_id
    returning * into v_preferences;
  end if;

  v_snapshot := public.push_preferences_payload_v2(v_user_id)
    || jsonb_build_object(
      'deviceId', v_device.id,
      'deviceRevision', v_device.revision,
      'deviceChanged', true,
      'certifiedAt', v_now
    );

  insert into public.push_preference_action_runs (
    user_id,
    device_id,
    action_type,
    idempotency_key,
    result_revision,
    token_fingerprint,
    payload_fingerprint,
    result_snapshot,
    created_at
  ) values (
    v_user_id,
    v_device.id,
    'device_register',
    p_idempotency_key,
    v_device.revision,
    v_token_fingerprint,
    v_payload_fingerprint,
    v_snapshot,
    v_now
  );

  return public.push_preferences_payload_v2(v_user_id)
    || jsonb_build_object(
      'deviceId', v_device.id,
      'deviceRevision', v_device.revision,
      'deviceChanged', true,
      'idempotentReplay', false
    );
end;
$$;

create or replace function public.disable_my_push_device_guarded_v1(
  p_expo_push_token text,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_token text := trim(coalesce(p_expo_push_token, ''));
  v_token_fingerprint text;
  v_device public.user_push_devices%rowtype;
  v_run public.push_preference_action_runs%rowtype;
  v_now timestamptz := now();
  v_changed boolean := false;
  v_snapshot jsonb;
begin
  if v_user_id is null then
    raise exception 'Devi effettuare l''accesso.';
  end if;
  if p_idempotency_key is null then
    raise exception 'Identificativo operazione mancante.';
  end if;
  if v_token = '' then
    raise exception 'Token dispositivo mancante.';
  end if;

  v_token_fingerprint := public.push_device_token_fingerprint_v1(v_token);

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('leghevo:push:user:' || v_user_id::text, 0)
  );
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('leghevo:push:token:' || v_token_fingerprint, 0)
  );

  select run.*
  into v_run
  from public.push_preference_action_runs run
  where run.idempotency_key = p_idempotency_key;

  if found then
    if v_run.user_id <> v_user_id
      or v_run.action_type <> 'device_disable'
      or v_run.token_fingerprint is distinct from v_token_fingerprint then
      raise exception 'Identificativo già usato per un''altra operazione.';
    end if;
    return v_run.result_snapshot || jsonb_build_object(
      'idempotentReplay', true
    );
  end if;

  select device.*
  into v_device
  from public.user_push_devices device
  where device.user_id = v_user_id
    and device.expo_push_token = v_token
  for update;

  if found and v_device.enabled then
    update public.user_push_devices device
    set
      enabled = false,
      disabled_at = coalesce(device.disabled_at, v_now),
      last_seen_at = v_now,
      revision = device.revision + 1
    where device.id = v_device.id
    returning * into v_device;
    v_changed := true;
  end if;

  v_snapshot := public.push_preferences_payload_v2(v_user_id)
    || jsonb_build_object(
      'deviceId', v_device.id,
      'deviceRevision', coalesce(v_device.revision, 0),
      'deviceChanged', v_changed,
      'certifiedAt', v_now
    );

  insert into public.push_preference_action_runs (
    user_id,
    device_id,
    action_type,
    idempotency_key,
    result_revision,
    token_fingerprint,
    payload_fingerprint,
    result_snapshot,
    created_at
  ) values (
    v_user_id,
    v_device.id,
    'device_disable',
    p_idempotency_key,
    coalesce(v_device.revision, 0),
    v_token_fingerprint,
    pg_catalog.md5('device_disable' || E'\n' || v_token_fingerprint),
    v_snapshot,
    v_now
  );

  return public.push_preferences_payload_v2(v_user_id)
    || jsonb_build_object(
      'deviceId', v_device.id,
      'deviceRevision', coalesce(v_device.revision, 0),
      'deviceChanged', v_changed,
      'idempotentReplay', false
    );
end;
$$;

create or replace function public.release_stored_push_device_guarded_v1(
  p_expo_push_token text,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_token text := trim(coalesce(p_expo_push_token, ''));
  v_token_fingerprint text;
  v_device public.user_push_devices%rowtype;
  v_run public.push_preference_action_runs%rowtype;
  v_now timestamptz := now();
  v_changed boolean := false;
  v_snapshot jsonb;
begin
  if v_user_id is null then
    raise exception 'Devi effettuare l''accesso.';
  end if;
  if p_idempotency_key is null then
    raise exception 'Identificativo operazione mancante.';
  end if;
  if v_token = '' then
    raise exception 'Token dispositivo mancante.';
  end if;

  v_token_fingerprint := public.push_device_token_fingerprint_v1(v_token);

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('leghevo:push:user:' || v_user_id::text, 0)
  );
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('leghevo:push:token:' || v_token_fingerprint, 0)
  );

  select run.*
  into v_run
  from public.push_preference_action_runs run
  where run.idempotency_key = p_idempotency_key;

  if found then
    if v_run.user_id <> v_user_id
      or v_run.action_type <> 'device_release'
      or v_run.token_fingerprint is distinct from v_token_fingerprint then
      raise exception 'Identificativo già usato per un''altra operazione.';
    end if;
    return v_run.result_snapshot || jsonb_build_object(
      'idempotentReplay', true
    );
  end if;

  select device.*
  into v_device
  from public.user_push_devices device
  where device.user_id = v_user_id
    and device.expo_push_token = v_token
  for update;

  if found and v_device.enabled then
    update public.user_push_devices device
    set
      enabled = false,
      disabled_at = coalesce(device.disabled_at, v_now),
      last_seen_at = v_now,
      revision = device.revision + 1
    where device.id = v_device.id
    returning * into v_device;
    v_changed := true;
  end if;

  v_snapshot := public.push_preferences_payload_v2(v_user_id)
    || jsonb_build_object(
      'deviceId', v_device.id,
      'deviceRevision', coalesce(v_device.revision, 0),
      'deviceChanged', v_changed,
      'certifiedAt', v_now
    );

  insert into public.push_preference_action_runs (
    user_id,
    device_id,
    action_type,
    idempotency_key,
    result_revision,
    token_fingerprint,
    payload_fingerprint,
    result_snapshot,
    created_at
  ) values (
    v_user_id,
    v_device.id,
    'device_release',
    p_idempotency_key,
    coalesce(v_device.revision, 0),
    v_token_fingerprint,
    pg_catalog.md5('device_release' || E'\n' || v_token_fingerprint),
    v_snapshot,
    v_now
  );

  return public.push_preferences_payload_v2(v_user_id)
    || jsonb_build_object(
      'deviceId', v_device.id,
      'deviceRevision', coalesce(v_device.revision, 0),
      'deviceChanged', v_changed,
      'idempotentReplay', false
    );
end;
$$;

-- Compatibilità: le RPC storiche mantengono firma e risultato atteso,
-- instradando tutte le scritture nel percorso protetto.
create or replace function public.get_my_push_notification_preferences()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select public.get_my_push_notification_preferences_v2();
$$;

create or replace function public.save_my_push_notification_preferences(
  p_push_enabled boolean,
  p_auction_trade_enabled boolean,
  p_lineup_enabled boolean,
  p_results_enabled boolean,
  p_league_enabled boolean,
  p_system_enabled boolean
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_revision bigint;
begin
  select preferences.revision
  into v_revision
  from public.user_notification_preferences preferences
  where preferences.user_id = auth.uid();

  return public.save_my_push_notification_preferences_guarded_v1(
    p_push_enabled,
    p_auction_trade_enabled,
    p_lineup_enabled,
    p_results_enabled,
    p_league_enabled,
    p_system_enabled,
    coalesce(v_revision, 0),
    gen_random_uuid()
  );
end;
$$;

create or replace function public.register_my_push_device(
  p_expo_push_token text,
  p_platform text,
  p_device_name text,
  p_app_version text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_payload jsonb;
begin
  v_payload := public.register_my_push_device_guarded_v1(
    p_expo_push_token,
    p_platform,
    p_device_name,
    p_app_version,
    gen_random_uuid()
  );
  return nullif(v_payload ->> 'deviceId', '')::uuid;
end;
$$;

create or replace function public.disable_my_push_device(
  p_expo_push_token text
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_payload jsonb;
begin
  v_payload := public.disable_my_push_device_guarded_v1(
    p_expo_push_token,
    gen_random_uuid()
  );
  return coalesce((v_payload ->> 'deviceChanged')::boolean, false);
end;
$$;

create or replace function public.release_stored_push_device(
  p_expo_push_token text
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_payload jsonb;
begin
  v_payload := public.release_stored_push_device_guarded_v1(
    p_expo_push_token,
    gen_random_uuid()
  );
  return coalesce((v_payload ->> 'deviceChanged')::boolean, false);
end;
$$;

-- Permessi delle RPC protette e compatibili.
revoke all on function public.get_my_push_notification_preferences_v2()
from public, anon;
revoke all on function public.save_my_push_notification_preferences_guarded_v1(
  boolean, boolean, boolean, boolean, boolean, boolean, bigint, uuid
) from public, anon;
revoke all on function public.register_my_push_device_guarded_v1(
  text, text, text, text, uuid
) from public, anon;
revoke all on function public.disable_my_push_device_guarded_v1(text, uuid)
from public, anon;
revoke all on function public.release_stored_push_device_guarded_v1(text, uuid)
from public, anon;

revoke all on function public.get_my_push_notification_preferences()
from public, anon;
revoke all on function public.save_my_push_notification_preferences(
  boolean, boolean, boolean, boolean, boolean, boolean
) from public, anon;
revoke all on function public.register_my_push_device(text, text, text, text)
from public, anon;
revoke all on function public.disable_my_push_device(text)
from public, anon;
revoke all on function public.release_stored_push_device(text)
from public, anon;

grant execute on function public.get_my_push_notification_preferences_v2()
to authenticated;
grant execute on function public.save_my_push_notification_preferences_guarded_v1(
  boolean, boolean, boolean, boolean, boolean, boolean, bigint, uuid
) to authenticated;
grant execute on function public.register_my_push_device_guarded_v1(
  text, text, text, text, uuid
) to authenticated;
grant execute on function public.disable_my_push_device_guarded_v1(text, uuid)
to authenticated;
grant execute on function public.release_stored_push_device_guarded_v1(text, uuid)
to authenticated;

grant execute on function public.get_my_push_notification_preferences()
to authenticated;
grant execute on function public.save_my_push_notification_preferences(
  boolean, boolean, boolean, boolean, boolean, boolean
) to authenticated;
grant execute on function public.register_my_push_device(text, text, text, text)
to authenticated;
grant execute on function public.disable_my_push_device(text)
to authenticated;
grant execute on function public.release_stored_push_device(text)
to authenticated;

-- Nessuna scrittura diretta alle tabelle operative.
revoke insert, update, delete on public.user_notification_preferences
from authenticated, anon;
revoke insert, update, delete on public.user_push_devices
from authenticated, anon;
revoke insert, update, delete on public.notification_push_deliveries
from authenticated, anon;
revoke insert, update, delete on public.push_preference_action_runs
from authenticated, anon;

-- Il registro azioni è la sorgente Realtime per sincronizzare le preferenze
-- senza esporre token o tabelle operative al client.
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
      and publication_table.tablename = 'push_preference_action_runs'
  ) then
    execute 'alter publication supabase_realtime add table public.push_preference_action_runs';
  end if;
end;
$realtime$;

create or replace function public.get_push_preference_safety_integrity_v1()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'preferencesReady', to_regclass('public.user_notification_preferences') is not null,
    'devicesReady', to_regclass('public.user_push_devices') is not null,
    'deliveriesReady', to_regclass('public.notification_push_deliveries') is not null,
    'actionRunsReady', to_regclass('public.push_preference_action_runs') is not null,
    'preferenceRevisionReady', exists (
      select 1 from information_schema.columns column_row
      where column_row.table_schema = 'public'
        and column_row.table_name = 'user_notification_preferences'
        and column_row.column_name = 'revision'
    ),
    'deviceRevisionReady', exists (
      select 1 from information_schema.columns column_row
      where column_row.table_schema = 'public'
        and column_row.table_name = 'user_push_devices'
        and column_row.column_name = 'revision'
    ),
    'fingerprintsReady', exists (
      select 1 from information_schema.columns column_row
      where column_row.table_schema = 'public'
        and column_row.table_name = 'user_notification_preferences'
        and column_row.column_name = 'preference_fingerprint'
    ) and exists (
      select 1 from information_schema.columns column_row
      where column_row.table_schema = 'public'
        and column_row.table_name = 'user_push_devices'
        and column_row.column_name = 'token_fingerprint'
    ),
    'actionRunsRlsReady', coalesce((
      select class.relrowsecurity
      from pg_class class
      where class.oid = to_regclass('public.push_preference_action_runs')
    ), false),
    'actionRunsImmutable', exists (
      select 1 from pg_trigger trigger_row
      where trigger_row.tgrelid = to_regclass('public.push_preference_action_runs')
        and trigger_row.tgname = 'push_preference_action_runs_immutable'
        and not trigger_row.tgisinternal
    ),
    'guardedSaveReady', to_regprocedure(
      'public.save_my_push_notification_preferences_guarded_v1(boolean,boolean,boolean,boolean,boolean,boolean,bigint,uuid)'
    ) is not null,
    'guardedRegisterReady', to_regprocedure(
      'public.register_my_push_device_guarded_v1(text,text,text,text,uuid)'
    ) is not null,
    'guardedDisableReady', to_regprocedure(
      'public.disable_my_push_device_guarded_v1(text,uuid)'
    ) is not null,
    'guardedReleaseReady', to_regprocedure(
      'public.release_stored_push_device_guarded_v1(text,uuid)'
    ) is not null,
    'centerV2Ready', to_regprocedure(
      'public.get_my_push_notification_preferences_v2()'
    ) is not null,
    'authenticatedSaveReady', has_function_privilege(
      'authenticated',
      'public.save_my_push_notification_preferences_guarded_v1(boolean,boolean,boolean,boolean,boolean,boolean,bigint,uuid)',
      'EXECUTE'
    ),
    'authenticatedRegisterReady', has_function_privilege(
      'authenticated',
      'public.register_my_push_device_guarded_v1(text,text,text,text,uuid)',
      'EXECUTE'
    ),
    'authenticatedDisableReady', has_function_privilege(
      'authenticated',
      'public.disable_my_push_device_guarded_v1(text,uuid)',
      'EXECUTE'
    ),
    'crossAccountTransferProtected', pg_get_functiondef(to_regprocedure(
      'public.register_my_push_device_guarded_v1(text,text,text,text,uuid)'
    )) like '%ancora attivo su un altro account%',
    'directWritesBlocked',
      not has_table_privilege('authenticated', 'public.user_notification_preferences', 'INSERT')
      and not has_table_privilege('authenticated', 'public.user_notification_preferences', 'UPDATE')
      and not has_table_privilege('authenticated', 'public.user_notification_preferences', 'DELETE')
      and not has_table_privilege('authenticated', 'public.user_push_devices', 'INSERT')
      and not has_table_privilege('authenticated', 'public.user_push_devices', 'UPDATE')
      and not has_table_privilege('authenticated', 'public.user_push_devices', 'DELETE')
      and not has_table_privilege('authenticated', 'public.notification_push_deliveries', 'INSERT')
      and not has_table_privilege('authenticated', 'public.notification_push_deliveries', 'UPDATE')
      and not has_table_privilege('authenticated', 'public.notification_push_deliveries', 'DELETE')
      and not has_table_privilege('authenticated', 'public.push_preference_action_runs', 'INSERT')
      and not has_table_privilege('authenticated', 'public.push_preference_action_runs', 'UPDATE')
      and not has_table_privilege('authenticated', 'public.push_preference_action_runs', 'DELETE'),
    'realtimeReady', exists (
      select 1
      from pg_publication_tables publication_table
      where publication_table.pubname = 'supabase_realtime'
        and publication_table.schemaname = 'public'
        and publication_table.tablename = 'push_preference_action_runs'
    )
  );
$$;

revoke all on function public.get_push_preference_safety_integrity_v1()
from public, anon;
grant execute on function public.get_push_preference_safety_integrity_v1()
to authenticated, service_role;

commit;

-- Diagnostica conclusiva: devono comparire esattamente 20 valori true.
select
  to_regclass('public.user_notification_preferences') is not null
    as push_preferences_ready,
  to_regclass('public.user_push_devices') is not null
    as push_devices_ready,
  to_regclass('public.notification_push_deliveries') is not null
    as push_deliveries_ready,
  to_regclass('public.push_preference_action_runs') is not null
    as push_action_runs_ready,
  exists (
    select 1 from information_schema.columns column_row
    where column_row.table_schema = 'public'
      and column_row.table_name = 'user_notification_preferences'
      and column_row.column_name = 'revision'
  ) as push_preference_revision_ready,
  exists (
    select 1 from information_schema.columns column_row
    where column_row.table_schema = 'public'
      and column_row.table_name = 'user_push_devices'
      and column_row.column_name = 'revision'
  ) as push_device_revision_ready,
  exists (
    select 1 from information_schema.columns column_row
    where column_row.table_schema = 'public'
      and column_row.table_name = 'user_notification_preferences'
      and column_row.column_name = 'preference_fingerprint'
  ) and exists (
    select 1 from information_schema.columns column_row
    where column_row.table_schema = 'public'
      and column_row.table_name = 'user_push_devices'
      and column_row.column_name = 'token_fingerprint'
  ) as push_fingerprints_ready,
  coalesce((
    select class.relrowsecurity
    from pg_class class
    where class.oid = to_regclass('public.push_preference_action_runs')
  ), false) as push_action_runs_rls_ready,
  exists (
    select 1 from pg_trigger trigger_row
    where trigger_row.tgrelid = to_regclass('public.push_preference_action_runs')
      and trigger_row.tgname = 'push_preference_action_runs_immutable'
      and not trigger_row.tgisinternal
  ) as push_action_runs_immutable,
  to_regprocedure(
    'public.save_my_push_notification_preferences_guarded_v1(boolean,boolean,boolean,boolean,boolean,boolean,bigint,uuid)'
  ) is not null as push_guarded_save_ready,
  to_regprocedure(
    'public.register_my_push_device_guarded_v1(text,text,text,text,uuid)'
  ) is not null as push_guarded_register_ready,
  to_regprocedure(
    'public.disable_my_push_device_guarded_v1(text,uuid)'
  ) is not null as push_guarded_disable_ready,
  to_regprocedure(
    'public.release_stored_push_device_guarded_v1(text,uuid)'
  ) is not null as push_guarded_release_ready,
  to_regprocedure('public.get_my_push_notification_preferences_v2()') is not null
    as push_center_v2_ready,
  has_function_privilege(
    'authenticated',
    'public.save_my_push_notification_preferences_guarded_v1(boolean,boolean,boolean,boolean,boolean,boolean,bigint,uuid)',
    'EXECUTE'
  ) as push_authenticated_save_ready,
  has_function_privilege(
    'authenticated',
    'public.register_my_push_device_guarded_v1(text,text,text,text,uuid)',
    'EXECUTE'
  ) as push_authenticated_register_ready,
  has_function_privilege(
    'authenticated',
    'public.disable_my_push_device_guarded_v1(text,uuid)',
    'EXECUTE'
  ) as push_authenticated_disable_ready,
  pg_get_functiondef(to_regprocedure(
    'public.register_my_push_device_guarded_v1(text,text,text,text,uuid)'
  )) like '%ancora attivo su un altro account%'
    as push_cross_account_transfer_protected,
  (
    not has_table_privilege('authenticated', 'public.user_notification_preferences', 'INSERT')
    and not has_table_privilege('authenticated', 'public.user_notification_preferences', 'UPDATE')
    and not has_table_privilege('authenticated', 'public.user_notification_preferences', 'DELETE')
    and not has_table_privilege('authenticated', 'public.user_push_devices', 'INSERT')
    and not has_table_privilege('authenticated', 'public.user_push_devices', 'UPDATE')
    and not has_table_privilege('authenticated', 'public.user_push_devices', 'DELETE')
    and not has_table_privilege('authenticated', 'public.notification_push_deliveries', 'INSERT')
    and not has_table_privilege('authenticated', 'public.notification_push_deliveries', 'UPDATE')
    and not has_table_privilege('authenticated', 'public.notification_push_deliveries', 'DELETE')
    and not has_table_privilege('authenticated', 'public.push_preference_action_runs', 'INSERT')
    and not has_table_privilege('authenticated', 'public.push_preference_action_runs', 'UPDATE')
    and not has_table_privilege('authenticated', 'public.push_preference_action_runs', 'DELETE')
  ) as push_direct_writes_blocked,
  exists (
    select 1
    from pg_publication_tables publication_table
    where publication_table.pubname = 'supabase_realtime'
      and publication_table.schemaname = 'public'
      and publication_table.tablename = 'push_preference_action_runs'
  ) as push_realtime_ready;
