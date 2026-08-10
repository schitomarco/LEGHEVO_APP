-- LEGHEVO · fondazione commerciale successiva alla v0.62.49
-- Fondazione commerciale Free/Premium, sincronizzazione store-side e limiti
-- applicati dal database. Non attiva acquisti o pubblicita reali.

begin;

set local statement_timeout = '10min';

do $types$
begin
  if not exists (
    select 1
    from pg_catalog.pg_type type_info
    join pg_catalog.pg_namespace namespace_info
      on namespace_info.oid = type_info.typnamespace
    where namespace_info.nspname = 'public'
      and type_info.typname = 'commercial_subscription_store'
  ) then
    create type public.commercial_subscription_store as enum (
      'apple',
      'google',
      'manual',
      'test'
    );
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_type type_info
    join pg_catalog.pg_namespace namespace_info
      on namespace_info.oid = type_info.typnamespace
    where namespace_info.nspname = 'public'
      and type_info.typname = 'commercial_subscription_status'
  ) then
    create type public.commercial_subscription_status as enum (
      'inactive',
      'trialing',
      'active',
      'grace_period',
      'billing_retry',
      'expired',
      'revoked'
    );
  end if;
end;
$types$;

create table if not exists public.commercial_subscription_events (
  event_id text primary key,
  user_id uuid not null references public.profiles(id) on delete cascade,
  store public.commercial_subscription_store not null,
  environment text not null check (environment in ('sandbox', 'production')),
  event_type text not null,
  product_id text,
  original_transaction_id text,
  occurred_at timestamptz not null,
  effective_expires_at timestamptz,
  payload_fingerprint text not null check (char_length(payload_fingerprint) = 64),
  received_at timestamptz not null default now()
);

create index if not exists commercial_subscription_events_user_timeline_idx
  on public.commercial_subscription_events (user_id, occurred_at desc);

create unique index if not exists commercial_subscription_events_store_transaction_uidx
  on public.commercial_subscription_events (store, original_transaction_id, event_id)
  where original_transaction_id is not null;

create table if not exists public.commercial_entitlements (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  tier public.subscription_tier not null default 'free',
  status public.commercial_subscription_status not null default 'inactive',
  store public.commercial_subscription_store,
  product_id text,
  original_transaction_id text,
  environment text not null default 'sandbox'
    check (environment in ('sandbox', 'production')),
  current_period_started_at timestamptz,
  current_period_ends_at timestamptz,
  grace_period_ends_at timestamptz,
  will_renew boolean not null default false,
  last_event_id text references public.commercial_subscription_events(event_id),
  last_event_at timestamptz,
  last_verified_at timestamptz,
  revision bigint not null default 1 check (revision > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint commercial_entitlements_store_fields_check check (
    (tier = 'free' and status in ('inactive', 'expired', 'revoked', 'billing_retry'))
    or
    (tier = 'premium' and store is not null and product_id is not null)
  ),
  constraint commercial_entitlements_period_check check (
    current_period_started_at is null
    or current_period_ends_at is null
    or current_period_ends_at >= current_period_started_at
  )
);

insert into public.commercial_entitlements (user_id)
select profile.id
from public.profiles profile
on conflict (user_id) do nothing;

alter table public.commercial_subscription_events enable row level security;
alter table public.commercial_entitlements enable row level security;

drop policy if exists commercial_entitlements_read_own
  on public.commercial_entitlements;
create policy commercial_entitlements_read_own
on public.commercial_entitlements for select to authenticated
using (user_id = auth.uid());

revoke all on public.commercial_subscription_events
from public, anon, authenticated;
revoke all on public.commercial_entitlements
from public, anon, authenticated;

create or replace function public.has_active_premium_v1(
  p_user_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select coalesce((
    select
      entitlement.tier = 'premium'
      and (
        (
          entitlement.status in ('trialing', 'active')
          and (
            entitlement.current_period_ends_at is null
            or entitlement.current_period_ends_at > now()
          )
        )
        or (
          entitlement.status in ('grace_period', 'billing_retry')
          and entitlement.grace_period_ends_at is not null
          and entitlement.grace_period_ends_at > now()
        )
      )
    from public.commercial_entitlements entitlement
    where entitlement.user_id = p_user_id
  ), false);
$function$;

create or replace function public.get_my_commercial_entitlement_v1()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_user_id uuid := auth.uid();
  v_entitlement public.commercial_entitlements%rowtype;
  v_is_premium boolean;
  v_owned_league_count integer;
begin
  if v_user_id is null then
    raise exception 'Devi effettuare l''accesso.';
  end if;

  select entitlement.*
  into v_entitlement
  from public.commercial_entitlements entitlement
  where entitlement.user_id = v_user_id;

  if not found then
    insert into public.commercial_entitlements (user_id)
    values (v_user_id)
    on conflict (user_id) do nothing
    returning * into v_entitlement;

    if v_entitlement.user_id is null then
      select entitlement.*
      into v_entitlement
      from public.commercial_entitlements entitlement
      where entitlement.user_id = v_user_id;
    end if;
  end if;

  v_is_premium := public.has_active_premium_v1(v_user_id);

  select count(*)::integer
  into v_owned_league_count
  from public.leagues league
  where league.owner_id = v_user_id
    and league.previous_league_id is null;

  return jsonb_build_object(
    'tier', case when v_is_premium then 'premium' else 'free' end,
    'status', coalesce(v_entitlement.status::text, 'inactive'),
    'isPremium', v_is_premium,
    'store', v_entitlement.store::text,
    'productId', v_entitlement.product_id,
    'environment', coalesce(v_entitlement.environment, 'sandbox'),
    'currentPeriodEndsAt', v_entitlement.current_period_ends_at,
    'gracePeriodEndsAt', v_entitlement.grace_period_ends_at,
    'willRenew', coalesce(v_entitlement.will_renew, false),
    'ownedLeagueCount', v_owned_league_count,
    'maxOwnedLeagues', case when v_is_premium then null else 1 end,
    'maxParticipantsPerLeague', case when v_is_premium then 20 else 6 end,
    'adsEnabled', not v_is_premium,
    'purchasesEnabled', false,
    'monthlyPriceLabel', '9,99 euro/mese'
  );
end;
$function$;

create or replace function public.record_commercial_subscription_event_v1(
  p_event_id text,
  p_user_id uuid,
  p_store public.commercial_subscription_store,
  p_environment text,
  p_event_type text,
  p_product_id text,
  p_original_transaction_id text,
  p_status public.commercial_subscription_status,
  p_occurred_at timestamptz,
  p_current_period_started_at timestamptz,
  p_current_period_ends_at timestamptz,
  p_grace_period_ends_at timestamptz,
  p_will_renew boolean,
  p_payload_fingerprint text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_existing public.commercial_subscription_events%rowtype;
  v_tier public.subscription_tier;
  v_entitlement public.commercial_entitlements%rowtype;
begin
  if nullif(btrim(p_event_id), '') is null
    or nullif(btrim(p_event_type), '') is null
    or p_user_id is null
    or p_occurred_at is null then
    raise exception 'Evento commerciale incompleto.';
  end if;

  if p_environment not in ('sandbox', 'production') then
    raise exception 'Ambiente commerciale non valido.';
  end if;

  if p_payload_fingerprint !~ '^[0-9a-f]{64}$' then
    raise exception 'Impronta evento commerciale non valida.';
  end if;

  select event.*
  into v_existing
  from public.commercial_subscription_events event
  where event.event_id = p_event_id;

  if found then
    if v_existing.payload_fingerprint <> p_payload_fingerprint
      or v_existing.user_id <> p_user_id
      or v_existing.store <> p_store then
      raise exception 'Conflitto idempotenza evento commerciale.';
    end if;

    select entitlement.*
    into v_entitlement
    from public.commercial_entitlements entitlement
    where entitlement.user_id = p_user_id;

    return jsonb_build_object(
      'applied', false,
      'idempotent', true,
      'userId', p_user_id,
      'revision', coalesce(v_entitlement.revision, 0)
    );
  end if;

  insert into public.commercial_subscription_events (
    event_id,
    user_id,
    store,
    environment,
    event_type,
    product_id,
    original_transaction_id,
    occurred_at,
    effective_expires_at,
    payload_fingerprint
  ) values (
    btrim(p_event_id),
    p_user_id,
    p_store,
    p_environment,
    btrim(p_event_type),
    nullif(btrim(p_product_id), ''),
    nullif(btrim(p_original_transaction_id), ''),
    p_occurred_at,
    p_current_period_ends_at,
    p_payload_fingerprint
  );

  v_tier := case
    when p_status in ('trialing', 'active', 'grace_period', 'billing_retry')
      then 'premium'::public.subscription_tier
    else 'free'::public.subscription_tier
  end;

  insert into public.commercial_entitlements (
    user_id,
    tier,
    status,
    store,
    product_id,
    original_transaction_id,
    environment,
    current_period_started_at,
    current_period_ends_at,
    grace_period_ends_at,
    will_renew,
    last_event_id,
    last_event_at,
    last_verified_at
  ) values (
    p_user_id,
    v_tier,
    p_status,
    p_store,
    nullif(btrim(p_product_id), ''),
    nullif(btrim(p_original_transaction_id), ''),
    p_environment,
    p_current_period_started_at,
    p_current_period_ends_at,
    p_grace_period_ends_at,
    coalesce(p_will_renew, false),
    btrim(p_event_id),
    p_occurred_at,
    now()
  )
  on conflict (user_id) do update
  set
    tier = excluded.tier,
    status = excluded.status,
    store = excluded.store,
    product_id = excluded.product_id,
    original_transaction_id = excluded.original_transaction_id,
    environment = excluded.environment,
    current_period_started_at = excluded.current_period_started_at,
    current_period_ends_at = excluded.current_period_ends_at,
    grace_period_ends_at = excluded.grace_period_ends_at,
    will_renew = excluded.will_renew,
    last_event_id = excluded.last_event_id,
    last_event_at = excluded.last_event_at,
    last_verified_at = excluded.last_verified_at,
    revision = public.commercial_entitlements.revision + 1,
    updated_at = now()
  where public.commercial_entitlements.last_event_at is null
     or excluded.last_event_at >= public.commercial_entitlements.last_event_at
  returning * into v_entitlement;

  if v_entitlement.user_id is null then
    select entitlement.*
    into v_entitlement
    from public.commercial_entitlements entitlement
    where entitlement.user_id = p_user_id;
  end if;

  update public.profiles profile
  set subscription = case
    when public.has_active_premium_v1(p_user_id)
      then 'premium'::public.subscription_tier
    else 'free'::public.subscription_tier
  end
  where profile.id = p_user_id;

  return jsonb_build_object(
    'applied', v_entitlement.last_event_id = p_event_id,
    'idempotent', false,
    'userId', p_user_id,
    'tier', v_entitlement.tier,
    'status', v_entitlement.status,
    'revision', v_entitlement.revision
  );
end;
$function$;

create or replace function public.create_league_with_team(
  p_name text,
  p_team_name text,
  p_mode public.league_mode,
  p_team_limit smallint default 8,
  p_starting_credits integer default 500,
  p_roster_size smallint default 25
)
returns public.leagues
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_user_id uuid := auth.uid();
  v_league public.leagues%rowtype;
  v_league_name text := regexp_replace(trim(coalesce(p_name, '')), '\s+', ' ', 'g');
  v_team_name text := regexp_replace(trim(coalesce(p_team_name, '')), '\s+', ' ', 'g');
  v_invite_code text;
  v_attempt integer := 0;
  v_is_premium boolean;
  v_owned_league_count integer;
begin
  if v_user_id is null then
    raise exception 'Devi effettuare l''accesso.';
  end if;

  if char_length(v_league_name) not between 3 and 50 then
    raise exception 'Il nome della lega deve contenere da 3 a 50 caratteri.';
  end if;

  if char_length(v_team_name) not between 2 and 40 then
    raise exception 'Il nome squadra deve contenere da 2 a 40 caratteri.';
  end if;

  if p_team_limit < 2 or p_team_limit > 20 then
    raise exception 'Il numero di partecipanti deve essere tra 2 e 20.';
  end if;

  if p_starting_credits < 100 or p_starting_credits > 100000 then
    raise exception 'I crediti iniziali devono essere compresi tra 100 e 100000.';
  end if;

  if p_roster_size < 11 or p_roster_size > 50 then
    raise exception 'La rosa deve contenere tra 11 e 50 calciatori.';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('leghevo-commercial:' || v_user_id::text, 0)
  );

  insert into public.commercial_entitlements (user_id)
  values (v_user_id)
  on conflict (user_id) do nothing;

  v_is_premium := public.has_active_premium_v1(v_user_id);

  select count(*)::integer
  into v_owned_league_count
  from public.leagues league
  where league.owner_id = v_user_id
    and league.previous_league_id is null;

  if not v_is_premium and v_owned_league_count >= 1 then
    raise exception 'Il piano Free consente una sola lega. Attiva LEGHEVO Premium per crearne altre.';
  end if;

  if not v_is_premium and p_team_limit > 6 then
    raise exception 'Il piano Free consente fino a 6 partecipanti per lega. Attiva LEGHEVO Premium per arrivare a 20.';
  end if;

  loop
    v_attempt := v_attempt + 1;
    v_invite_code := upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 10));

    exit when not exists (
      select 1
      from public.leagues league
      where league.invite_code = v_invite_code
    );

    if v_attempt >= 10 then
      raise exception 'Impossibile generare il codice invito. Riprova.';
    end if;
  end loop;

  insert into public.leagues (
    owner_id,
    name,
    invite_code,
    mode,
    team_limit,
    starting_credits,
    roster_size
  ) values (
    v_user_id,
    v_league_name,
    v_invite_code,
    p_mode,
    p_team_limit,
    p_starting_credits,
    p_roster_size
  )
  returning * into v_league;

  insert into public.league_members (league_id, user_id, role)
  values (v_league.id, v_user_id, 'admin');

  insert into public.fantasy_teams (
    league_id,
    manager_id,
    name,
    credits_remaining
  ) values (
    v_league.id,
    v_user_id,
    v_team_name,
    v_league.starting_credits
  );

  return v_league;
exception
  when unique_violation then
    raise exception 'Questo nome squadra e gia stato preso.';
end;
$function$;

revoke all on function public.has_active_premium_v1(uuid)
from public, anon, authenticated;
revoke all on function public.get_my_commercial_entitlement_v1()
from public, anon;
revoke all on function public.record_commercial_subscription_event_v1(
  text, uuid, public.commercial_subscription_store, text, text, text, text,
  public.commercial_subscription_status, timestamptz, timestamptz, timestamptz,
  timestamptz, boolean, text
) from public, anon, authenticated;
revoke all on function public.create_league_with_team(
  text, text, public.league_mode, smallint, integer, smallint
) from public, anon;

grant execute on function public.get_my_commercial_entitlement_v1()
to authenticated;
grant execute on function public.record_commercial_subscription_event_v1(
  text, uuid, public.commercial_subscription_store, text, text, text, text,
  public.commercial_subscription_status, timestamptz, timestamptz, timestamptz,
  timestamptz, boolean, text
) to service_role;
grant execute on function public.create_league_with_team(
  text, text, public.league_mode, smallint, integer, smallint
) to authenticated;

do $postflight$
begin
  if to_regclass('public.commercial_entitlements') is null
    or to_regclass('public.commercial_subscription_events') is null
    or to_regprocedure('public.get_my_commercial_entitlement_v1()') is null
    or to_regprocedure('public.has_active_premium_v1(uuid)') is null
    or to_regprocedure(
      'public.record_commercial_subscription_event_v1(text,uuid,public.commercial_subscription_store,text,text,text,text,public.commercial_subscription_status,timestamptz,timestamptz,timestamptz,timestamptz,boolean,text)'
    ) is null
    or not has_function_privilege(
      'authenticated',
      'public.get_my_commercial_entitlement_v1()',
      'execute'
    )
    or has_function_privilege(
      'authenticated',
      'public.record_commercial_subscription_event_v1(text,uuid,public.commercial_subscription_store,text,text,text,text,public.commercial_subscription_status,timestamptz,timestamptz,timestamptz,timestamptz,boolean,text)',
      'execute'
    ) then
    raise exception 'Postflight monetizzazione LEGHEVO non superato.';
  end if;
end;
$postflight$;

commit;
