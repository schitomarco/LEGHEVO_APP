-- LEGHEVO · Business Dashboard riservata al proprietario della piattaforma
-- I valori finanziari sono gestionali e stimati. I provider restano la fonte
-- ufficiale per maturato, commissioni e liquidazioni.

begin;

set local statement_timeout = '10min';

create table if not exists public.platform_business_owners (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  granted_at timestamptz not null default now()
);

create table if not exists public.business_financial_entries (
  id uuid primary key default gen_random_uuid(),
  occurred_on date not null,
  entry_type text not null check (entry_type in ('revenue', 'cost')),
  category text not null check (
    category in ('advertising', 'league_pro', 'infrastructure', 'marketing', 'support', 'other')
  ),
  amount_cents bigint not null check (amount_cents >= 0),
  currency text not null default 'EUR' check (currency = 'EUR'),
  status text not null default 'estimated' check (status in ('estimated', 'confirmed')),
  source text not null default 'manual',
  note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists business_financial_entries_period_idx
  on public.business_financial_entries (occurred_on desc, entry_type, category);

alter table public.platform_business_owners enable row level security;
alter table public.business_financial_entries enable row level security;

revoke all on public.platform_business_owners from public, anon, authenticated;
revoke all on public.business_financial_entries from public, anon, authenticated;

create or replace function public.is_leghevo_business_owner_v1()
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select auth.uid() is not null and exists (
    select 1
    from public.platform_business_owners owner_row
    where owner_row.user_id = auth.uid()
  );
$function$;

create or replace function public.get_my_business_dashboard_access_v1()
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select public.is_leghevo_business_owner_v1();
$function$;

create or replace function public.get_leghevo_business_dashboard_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_today date := current_date;
  v_month_start date := date_trunc('month', current_date)::date;
  v_season_start date := make_date(
    case when extract(month from current_date) >= 7
      then extract(year from current_date)::integer
      else extract(year from current_date)::integer - 1
    end,
    7,
    1
  );
  v_result jsonb;
begin
  if not public.is_leghevo_business_owner_v1() then
    raise exception 'Dashboard Ricavi riservata al proprietario LEGHEVO.';
  end if;

  with subscription_revenue as (
    select
      event.occurred_at::date as occurred_on,
      event.store::text as source,
      event.user_id,
      event.event_type,
      case
        when event.product_id in ('leghevo_premium_monthly', 'leghevo_premium:monthly') then 299::bigint
        when event.product_id in ('leghevo_premium_annual', 'leghevo_premium:annual') then 999::bigint
        else 0::bigint
      end as amount_cents
    from public.commercial_subscription_events event
    where event.environment = 'production'
      and event.event_type in ('INITIAL_PURCHASE', 'RENEWAL')
  ),
  manual_entries as (
    select
      entry.occurred_on,
      entry.entry_type,
      entry.category,
      entry.amount_cents
    from public.business_financial_entries entry
  ),
  totals as (
    select
      coalesce((select sum(amount_cents) from subscription_revenue where occurred_on = v_today), 0)
        + coalesce((select sum(amount_cents) from manual_entries where entry_type = 'revenue' and occurred_on = v_today), 0)
        as today_revenue,
      coalesce((select sum(amount_cents) from subscription_revenue where occurred_on >= v_month_start), 0)
        + coalesce((select sum(amount_cents) from manual_entries where entry_type = 'revenue' and occurred_on >= v_month_start), 0)
        as month_revenue,
      coalesce((select sum(amount_cents) from subscription_revenue where occurred_on >= v_season_start), 0)
        + coalesce((select sum(amount_cents) from manual_entries where entry_type = 'revenue' and occurred_on >= v_season_start), 0)
        as season_revenue,
      coalesce((select sum(amount_cents) from subscription_revenue where source = 'apple' and occurred_on >= v_season_start), 0)
        as apple_revenue,
      coalesce((select sum(amount_cents) from subscription_revenue where source = 'google' and occurred_on >= v_season_start), 0)
        as google_revenue,
      coalesce((select sum(amount_cents) from manual_entries where entry_type = 'revenue' and category = 'advertising' and occurred_on >= v_season_start), 0)
        as advertising_revenue,
      coalesce((select sum(amount_cents) from manual_entries where entry_type = 'revenue' and category = 'league_pro' and occurred_on >= v_season_start), 0)
        as league_pro_revenue,
      coalesce((select sum(amount_cents) from manual_entries where entry_type = 'cost' and occurred_on >= v_season_start), 0)
        as manual_costs
  ),
  audience as (
    select
      (select count(*)::integer from auth.users user_row where user_row.deleted_at is null and user_row.last_sign_in_at >= now() - interval '30 days') as active_users,
      (select count(*)::integer from public.commercial_entitlements entitlement where public.has_active_premium_v1(entitlement.user_id)) as premium_users
  ),
  lifecycle as (
    select
      count(*) filter (where event.event_type = 'INITIAL_PURCHASE' and event.occurred_at >= v_month_start)::integer as new_premium,
      count(*) filter (where event.event_type = 'RENEWAL' and event.occurred_at >= v_month_start)::integer as renewals,
      count(*) filter (where event.event_type = 'CANCELLATION' and event.occurred_at >= v_month_start)::integer as cancellations
    from public.commercial_subscription_events event
    where event.environment = 'production'
  ),
  daily_series as (
    select jsonb_agg(
      jsonb_build_object(
        'period', day_value::date,
        'revenueCents',
          coalesce((select sum(amount_cents) from subscription_revenue where occurred_on = day_value::date), 0)
          + coalesce((select sum(amount_cents) from manual_entries where entry_type = 'revenue' and occurred_on = day_value::date), 0),
        'newPremium', coalesce((
          select count(*) from public.commercial_subscription_events event
          where event.environment = 'production'
            and event.event_type = 'INITIAL_PURCHASE'
            and event.occurred_at::date = day_value::date
        ), 0),
        'renewals', coalesce((
          select count(*) from public.commercial_subscription_events event
          where event.environment = 'production'
            and event.event_type = 'RENEWAL'
            and event.occurred_at::date = day_value::date
        ), 0),
        'cancellations', coalesce((
          select count(*) from public.commercial_subscription_events event
          where event.environment = 'production'
            and event.event_type = 'CANCELLATION'
            and event.occurred_at::date = day_value::date
        ), 0)
      ) order by day_value
    ) as value
    from generate_series(v_today - 29, v_today, interval '1 day') day_value
  ),
  monthly_series as (
    select jsonb_agg(
      jsonb_build_object(
        'period', to_char(month_value, 'YYYY-MM'),
        'revenueCents',
          coalesce((select sum(amount_cents) from subscription_revenue where occurred_on >= month_value::date and occurred_on < (month_value + interval '1 month')::date), 0)
          + coalesce((select sum(amount_cents) from manual_entries where entry_type = 'revenue' and occurred_on >= month_value::date and occurred_on < (month_value + interval '1 month')::date), 0),
        'leaguesCreated', coalesce((
          select count(*) from public.leagues league
          where league.created_at >= month_value
            and league.created_at < month_value + interval '1 month'
        ), 0)
      ) order by month_value
    ) as value
    from generate_series(
      date_trunc('month', current_date) - interval '11 months',
      date_trunc('month', current_date),
      interval '1 month'
    ) month_value
  )
  select jsonb_build_object(
    'generatedAt', now(),
    'currency', 'EUR',
    'dataMode', 'management_estimate',
    'officialSourceNotice', 'Importi gestionali stimati. Per maturato e liquidato fanno fede Apple, Google e gli altri provider.',
    'todayRevenueCents', totals.today_revenue,
    'monthRevenueCents', totals.month_revenue,
    'seasonRevenueCents', totals.season_revenue,
    'activeUsers', audience.active_users,
    'premiumUsers', audience.premium_users,
    'conversionRate', case when audience.active_users > 0 then round((audience.premium_users::numeric / audience.active_users) * 100, 2) else 0 end,
    'appleRevenueCents', totals.apple_revenue,
    'googleRevenueCents', totals.google_revenue,
    'advertisingRevenueCents', totals.advertising_revenue,
    'leagueProRevenueCents', totals.league_pro_revenue,
    'totalRevenueCents', totals.season_revenue,
    'estimatedCostsCents', totals.manual_costs + round((totals.apple_revenue + totals.google_revenue) * 0.15)::bigint,
    'operatingMarginCents', totals.season_revenue - totals.manual_costs - round((totals.apple_revenue + totals.google_revenue) * 0.15)::bigint,
    'newPremium', lifecycle.new_premium,
    'renewals', lifecycle.renewals,
    'cancellations', lifecycle.cancellations,
    'arpuCents', case when audience.active_users > 0 then round(totals.month_revenue::numeric / audience.active_users)::bigint else 0 end,
    'activeLeagues', (select count(*)::integer from public.leagues league where league.status = 'active'),
    'daily', coalesce(daily_series.value, '[]'::jsonb),
    'monthly', coalesce(monthly_series.value, '[]'::jsonb)
  )
  into v_result
  from totals, audience, lifecycle, daily_series, monthly_series;

  return v_result;
end;
$function$;

revoke all on function public.is_leghevo_business_owner_v1() from public, anon;
revoke all on function public.get_my_business_dashboard_access_v1() from public, anon;
revoke all on function public.get_leghevo_business_dashboard_v1() from public, anon;

grant execute on function public.is_leghevo_business_owner_v1() to authenticated;
grant execute on function public.get_my_business_dashboard_access_v1() to authenticated;
grant execute on function public.get_leghevo_business_dashboard_v1() to authenticated;

do $postflight$
begin
  if to_regclass('public.platform_business_owners') is null
    or to_regclass('public.business_financial_entries') is null
    or to_regprocedure('public.get_my_business_dashboard_access_v1()') is null
    or to_regprocedure('public.get_leghevo_business_dashboard_v1()') is null
    or has_table_privilege('authenticated', 'public.platform_business_owners', 'select')
    or has_table_privilege('authenticated', 'public.business_financial_entries', 'select') then
    raise exception 'Postflight Business Dashboard LEGHEVO non superato.';
  end if;
end;
$postflight$;

commit;
