-- LEGHEVO · notifiche push, dispositivi e preferenze personali
-- Eseguire nel SQL Editor di Supabase dopo 052.
-- Lo script non richiede permessi al dispositivo, non registra token e non
-- invia notifiche durante l'installazione.

create table if not exists public.user_notification_preferences (
  user_id uuid primary key
    references public.profiles(id) on delete cascade,
  push_enabled boolean not null default false,
  auction_trade_enabled boolean not null default true,
  lineup_enabled boolean not null default true,
  results_enabled boolean not null default true,
  league_enabled boolean not null default true,
  system_enabled boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.user_push_devices (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null
    references public.profiles(id) on delete cascade,
  expo_push_token text not null unique
    check (
      expo_push_token ~ '^Expo(nent)?PushToken\[[A-Za-z0-9_-]+\]$'
    ),
  platform text not null check (platform in ('ios', 'android')),
  device_name text
    check (
      device_name is null
      or char_length(trim(device_name)) between 1 and 80
    ),
  app_version text
    check (
      app_version is null
      or char_length(trim(app_version)) between 1 and 30
    ),
  enabled boolean not null default true,
  registered_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  disabled_at timestamptz
);

create index if not exists user_push_devices_owner_idx
  on public.user_push_devices (user_id, enabled, last_seen_at desc);

create table if not exists public.notification_push_deliveries (
  id uuid primary key default gen_random_uuid(),
  notification_id uuid not null
    references public.user_notifications(id) on delete cascade,
  device_id uuid not null
    references public.user_push_devices(id) on delete cascade,
  user_id uuid not null
    references public.profiles(id) on delete cascade,
  status text not null default 'queued'
    check (
      status in (
        'queued',
        'processing',
        'sent',
        'failed',
        'skipped'
      )
    ),
  attempts smallint not null default 0
    check (attempts between 0 and 3),
  next_attempt_at timestamptz not null default now(),
  expo_ticket_id text,
  error_code text,
  error_message text,
  created_at timestamptz not null default now(),
  claimed_at timestamptz,
  completed_at timestamptz,
  unique (notification_id, device_id)
);

create index if not exists notification_push_queue_idx
  on public.notification_push_deliveries (
    status,
    next_attempt_at,
    created_at
  )
  where status = 'queued';

create index if not exists notification_push_owner_idx
  on public.notification_push_deliveries (user_id, created_at desc);

alter table public.user_notification_preferences enable row level security;
alter table public.user_push_devices enable row level security;
alter table public.notification_push_deliveries enable row level security;

revoke all on public.user_notification_preferences
from anon, authenticated;
revoke all on public.user_push_devices
from anon, authenticated;
revoke all on public.notification_push_deliveries
from anon, authenticated;

create or replace function public.push_category_is_enabled(
  p_kind text,
  p_preferences public.user_notification_preferences
)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select case
    when p_kind in ('auction', 'trade', 'market')
      then p_preferences.auction_trade_enabled
    when p_kind = 'lineup'
      then p_preferences.lineup_enabled
    when p_kind = 'result'
      then p_preferences.results_enabled
    when p_kind = 'league'
      then p_preferences.league_enabled
    when p_kind = 'system'
      then p_preferences.system_enabled
    else false
  end
$$;

revoke all on function public.push_category_is_enabled(
  text,
  public.user_notification_preferences
) from public, anon, authenticated;

create or replace function public.get_my_push_notification_preferences()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_preferences public.user_notification_preferences%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Devi effettuare l''accesso.';
  end if;

  select preferences.*
  into v_preferences
  from public.user_notification_preferences preferences
  where preferences.user_id = auth.uid();

  return jsonb_build_object(
    'pushEnabled', coalesce(v_preferences.push_enabled, false),
    'auctionTradeEnabled',
      coalesce(v_preferences.auction_trade_enabled, true),
    'lineupEnabled', coalesce(v_preferences.lineup_enabled, true),
    'resultsEnabled', coalesce(v_preferences.results_enabled, true),
    'leagueEnabled', coalesce(v_preferences.league_enabled, true),
    'systemEnabled', coalesce(v_preferences.system_enabled, true),
    'activeDeviceCount',
      (
        select count(*)::integer
        from public.user_push_devices device
        where device.user_id = auth.uid()
          and device.enabled
      ),
    'devices',
      coalesce(
        (
          select jsonb_agg(
            jsonb_build_object(
              'id', device.id,
              'platform', device.platform,
              'deviceName', device.device_name,
              'appVersion', device.app_version,
              'enabled', device.enabled,
              'registeredAt', device.registered_at,
              'lastSeenAt', device.last_seen_at
            )
            order by device.last_seen_at desc, device.id
          )
          from public.user_push_devices device
          where device.user_id = auth.uid()
        ),
        '[]'::jsonb
      )
  );
end;
$$;

revoke all on function public.get_my_push_notification_preferences()
from public, anon;
grant execute on function public.get_my_push_notification_preferences()
to authenticated;

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
  v_preferences public.user_notification_preferences%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Devi effettuare l''accesso.';
  end if;

  insert into public.user_notification_preferences (
    user_id,
    push_enabled,
    auction_trade_enabled,
    lineup_enabled,
    results_enabled,
    league_enabled,
    system_enabled,
    updated_at
  )
  values (
    auth.uid(),
    coalesce(p_push_enabled, false),
    coalesce(p_auction_trade_enabled, true),
    coalesce(p_lineup_enabled, true),
    coalesce(p_results_enabled, true),
    coalesce(p_league_enabled, true),
    coalesce(p_system_enabled, true),
    now()
  )
  on conflict (user_id) do update
  set
    push_enabled = excluded.push_enabled,
    auction_trade_enabled = excluded.auction_trade_enabled,
    lineup_enabled = excluded.lineup_enabled,
    results_enabled = excluded.results_enabled,
    league_enabled = excluded.league_enabled,
    system_enabled = excluded.system_enabled,
    updated_at = now()
  returning * into v_preferences;

  if not v_preferences.push_enabled then
    update public.user_push_devices
    set
      enabled = false,
      disabled_at = coalesce(disabled_at, now())
    where user_id = auth.uid()
      and enabled;
  end if;

  update public.notification_push_deliveries delivery
  set
    status = 'skipped',
    error_code = 'UserPreferenceDisabled',
    error_message = 'Invio disattivato nelle preferenze utente.',
    completed_at = now()
  from public.user_notifications notification
  where delivery.notification_id = notification.id
    and delivery.user_id = auth.uid()
    and delivery.status in ('queued', 'processing')
    and (
      not v_preferences.push_enabled
      or not public.push_category_is_enabled(
        notification.kind,
        v_preferences
      )
    );

  return public.get_my_push_notification_preferences();
end;
$$;

revoke all on function public.save_my_push_notification_preferences(
  boolean,
  boolean,
  boolean,
  boolean,
  boolean,
  boolean
) from public, anon;
grant execute on function public.save_my_push_notification_preferences(
  boolean,
  boolean,
  boolean,
  boolean,
  boolean,
  boolean
) to authenticated;

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
  v_device_id uuid;
  v_token text := trim(coalesce(p_expo_push_token, ''));
  v_platform text := lower(trim(coalesce(p_platform, '')));
begin
  if auth.uid() is null then
    raise exception 'Devi effettuare l''accesso.';
  end if;

  if v_token !~ '^Expo(nent)?PushToken\[[A-Za-z0-9_-]+\]$' then
    raise exception 'Token Expo Push non valido.';
  end if;

  if v_platform not in ('ios', 'android') then
    raise exception 'Piattaforma del dispositivo non valida.';
  end if;

  if p_device_name is not null
    and char_length(trim(p_device_name)) not between 1 and 80 then
    raise exception 'Nome dispositivo non valido.';
  end if;

  if p_app_version is not null
    and char_length(trim(p_app_version)) not between 1 and 30 then
    raise exception 'Versione app non valida.';
  end if;

  insert into public.user_push_devices (
    user_id,
    expo_push_token,
    platform,
    device_name,
    app_version,
    enabled,
    last_seen_at,
    disabled_at
  )
  values (
    auth.uid(),
    v_token,
    v_platform,
    nullif(trim(p_device_name), ''),
    nullif(trim(p_app_version), ''),
    true,
    now(),
    null
  )
  on conflict (expo_push_token) do update
  set
    user_id = excluded.user_id,
    platform = excluded.platform,
    device_name = excluded.device_name,
    app_version = excluded.app_version,
    enabled = true,
    last_seen_at = now(),
    disabled_at = null
  returning id into v_device_id;

  insert into public.user_notification_preferences (
    user_id,
    push_enabled
  )
  values (auth.uid(), true)
  on conflict (user_id) do update
  set
    push_enabled = true,
    updated_at = now();

  return v_device_id;
end;
$$;

revoke all on function public.register_my_push_device(
  text,
  text,
  text,
  text
) from public, anon;
grant execute on function public.register_my_push_device(
  text,
  text,
  text,
  text
) to authenticated;

create or replace function public.disable_my_push_device(
  p_expo_push_token text
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_updated integer;
begin
  if auth.uid() is null then
    raise exception 'Devi effettuare l''accesso.';
  end if;

  update public.user_push_devices
  set
    enabled = false,
    disabled_at = coalesce(disabled_at, now())
  where user_id = auth.uid()
    and expo_push_token = trim(coalesce(p_expo_push_token, ''))
    and enabled;

  get diagnostics v_updated = row_count;
  return v_updated > 0;
end;
$$;

revoke all on function public.disable_my_push_device(text)
from public, anon;
grant execute on function public.disable_my_push_device(text)
to authenticated;

create or replace function public.release_stored_push_device(
  p_expo_push_token text
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_updated integer;
begin
  if auth.uid() is null then
    raise exception 'Devi effettuare l''accesso.';
  end if;

  update public.user_push_devices
  set
    user_id = auth.uid(),
    enabled = false,
    disabled_at = coalesce(disabled_at, now()),
    last_seen_at = now()
  where expo_push_token = trim(coalesce(p_expo_push_token, ''));

  get diagnostics v_updated = row_count;
  return v_updated > 0;
end;
$$;

revoke all on function public.release_stored_push_device(text)
from public, anon;
grant execute on function public.release_stored_push_device(text)
to authenticated;

create or replace function public.enqueue_user_notification_push()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_preferences public.user_notification_preferences%rowtype;
begin
  select preferences.*
  into v_preferences
  from public.user_notification_preferences preferences
  where preferences.user_id = new.user_id
    and preferences.push_enabled;

  if not found
    or not public.push_category_is_enabled(new.kind, v_preferences) then
    return new;
  end if;

  insert into public.notification_push_deliveries (
    notification_id,
    device_id,
    user_id
  )
  select
    new.id,
    device.id,
    new.user_id
  from public.user_push_devices device
  where device.user_id = new.user_id
    and device.enabled
  on conflict (notification_id, device_id) do nothing;

  return new;
end;
$$;

revoke all on function public.enqueue_user_notification_push()
from public, anon, authenticated;

drop trigger if exists user_notification_enqueue_push
on public.user_notifications;

create trigger user_notification_enqueue_push
after insert on public.user_notifications
for each row execute function public.enqueue_user_notification_push();

create or replace function public.claim_notification_push_batch(
  p_limit integer default 50
)
returns table (
  delivery_id uuid,
  notification_id uuid,
  expo_push_token text,
  title text,
  body text,
  action_screen text,
  league_id uuid,
  notification_kind text,
  metadata jsonb
)
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.notification_push_deliveries delivery
  set
    status = 'queued',
    claimed_at = null,
    next_attempt_at = now()
  where delivery.status = 'processing'
    and delivery.claimed_at < now() - interval '5 minutes'
    and delivery.attempts < 3;

  update public.notification_push_deliveries delivery
  set
    status = 'skipped',
    error_code = 'DeviceOrPreferenceDisabled',
    error_message = 'Dispositivo o categoria non più abilitati.',
    completed_at = now()
  from
    public.user_push_devices device,
    public.user_notifications notification
  left join public.user_notification_preferences preferences
    on preferences.user_id = notification.user_id
  where delivery.device_id = device.id
    and delivery.notification_id = notification.id
    and delivery.status = 'queued'
    and (
      not device.enabled
      or not coalesce(preferences.push_enabled, false)
      or not public.push_category_is_enabled(
        notification.kind,
        preferences
      )
    );

  return query
  with candidates as (
    select queued.id
    from public.notification_push_deliveries queued
    where queued.status = 'queued'
      and queued.next_attempt_at <= now()
      and queued.attempts < 3
    order by queued.created_at, queued.id
    for update skip locked
    limit greatest(1, least(coalesce(p_limit, 50), 100))
  ),
  claimed as (
    update public.notification_push_deliveries delivery
    set
      status = 'processing',
      attempts = delivery.attempts + 1,
      claimed_at = now()
    from candidates
    where delivery.id = candidates.id
    returning delivery.*
  )
  select
    claimed.id,
    notification.id,
    device.expo_push_token,
    notification.title,
    notification.body,
    notification.action_screen,
    notification.league_id,
    notification.kind,
    notification.metadata
  from claimed
  join public.user_notifications notification
    on notification.id = claimed.notification_id
  join public.user_push_devices device
    on device.id = claimed.device_id
  order by claimed.created_at, claimed.id;
end;
$$;

revoke all on function public.claim_notification_push_batch(integer)
from public, anon, authenticated;
grant execute on function public.claim_notification_push_batch(integer)
to service_role;

create or replace function public.complete_notification_push_delivery(
  p_delivery_id uuid,
  p_status text,
  p_expo_ticket_id text default null,
  p_error_code text default null,
  p_error_message text default null
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_delivery public.notification_push_deliveries%rowtype;
begin
  if p_status not in ('sent', 'failed', 'retry', 'skipped') then
    raise exception 'Stato consegna non valido.';
  end if;

  select delivery.*
  into v_delivery
  from public.notification_push_deliveries delivery
  where delivery.id = p_delivery_id
  for update;

  if not found or v_delivery.status <> 'processing' then
    return false;
  end if;

  if p_status = 'retry' and v_delivery.attempts < 3 then
    update public.notification_push_deliveries
    set
      status = 'queued',
      next_attempt_at =
        now() + (interval '5 minutes' * v_delivery.attempts),
      expo_ticket_id = nullif(trim(p_expo_ticket_id), ''),
      error_code = nullif(trim(p_error_code), ''),
      error_message = left(nullif(trim(p_error_message), ''), 500),
      claimed_at = null
    where id = p_delivery_id;
  else
    update public.notification_push_deliveries
    set
      status = case
        when p_status = 'retry' then 'failed'
        else p_status
      end,
      expo_ticket_id = nullif(trim(p_expo_ticket_id), ''),
      error_code = nullif(trim(p_error_code), ''),
      error_message = left(nullif(trim(p_error_message), ''), 500),
      completed_at = now()
    where id = p_delivery_id;
  end if;

  if p_error_code = 'DeviceNotRegistered' then
    update public.user_push_devices
    set
      enabled = false,
      disabled_at = coalesce(disabled_at, now())
    where id = v_delivery.device_id;
  end if;

  return true;
end;
$$;

revoke all on function public.complete_notification_push_delivery(
  uuid,
  text,
  text,
  text,
  text
) from public, anon, authenticated;
grant execute on function public.complete_notification_push_delivery(
  uuid,
  text,
  text,
  text,
  text
) to service_role;

create or replace function public.export_my_personal_data_v3()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_export jsonb;
begin
  if auth.uid() is null then
    raise exception 'Devi effettuare l''accesso.';
  end if;

  v_export := public.export_my_personal_data_v2();

  return v_export || jsonb_build_object(
    'exportVersion', 3,
    'pushNotifications',
      jsonb_build_object(
        'preferences',
          public.get_my_push_notification_preferences(),
        'deliveries',
          coalesce(
            (
              select jsonb_agg(
                jsonb_build_object(
                  'notificationId', delivery.notification_id,
                  'status', delivery.status,
                  'attempts', delivery.attempts,
                  'errorCode', delivery.error_code,
                  'createdAt', delivery.created_at,
                  'completedAt', delivery.completed_at
                )
                order by delivery.created_at, delivery.id
              )
              from public.notification_push_deliveries delivery
              where delivery.user_id = auth.uid()
            ),
            '[]'::jsonb
          )
      )
  );
end;
$$;

revoke all on function public.export_my_personal_data_v3()
from public, anon;
grant execute on function public.export_my_personal_data_v3()
to authenticated;

select
  to_regclass(
    'public.user_notification_preferences'
  ) is not null as preferences_ready,
  to_regclass(
    'public.user_push_devices'
  ) is not null as devices_ready,
  to_regclass(
    'public.notification_push_deliveries'
  ) is not null as delivery_queue_ready,
  to_regprocedure(
    'public.get_my_push_notification_preferences()'
  ) is not null as preferences_read_ready,
  to_regprocedure(
    'public.save_my_push_notification_preferences(boolean,boolean,boolean,boolean,boolean,boolean)'
  ) is not null as preferences_write_ready,
  to_regprocedure(
    'public.register_my_push_device(text,text,text,text)'
  ) is not null as device_registration_ready,
  to_regprocedure(
    'public.disable_my_push_device(text)'
  ) is not null
    and to_regprocedure(
      'public.release_stored_push_device(text)'
    ) is not null as device_revocation_ready,
  to_regprocedure(
    'public.claim_notification_push_batch(integer)'
  ) is not null as delivery_claim_ready,
  to_regprocedure(
    'public.complete_notification_push_delivery(uuid,text,text,text,text)'
  ) is not null as delivery_completion_ready,
  exists (
    select 1
    from pg_trigger
    where tgname = 'user_notification_enqueue_push'
      and not tgisinternal
  ) as enqueue_trigger_ready,
  (
    has_function_privilege(
      'authenticated',
      'public.register_my_push_device(text,text,text,text)',
      'EXECUTE'
    )
    and not has_table_privilege(
      'authenticated',
      'public.user_push_devices',
      'SELECT'
    )
  ) as protected_device_access_ready,
  (
    has_function_privilege(
      'service_role',
      'public.claim_notification_push_batch(integer)',
      'EXECUTE'
    )
    and not has_function_privilege(
      'authenticated',
      'public.claim_notification_push_batch(integer)',
      'EXECUTE'
    )
    and not has_function_privilege(
      'anon',
      'public.register_my_push_device(text,text,text,text)',
      'EXECUTE'
    )
  ) as worker_security_ready;
