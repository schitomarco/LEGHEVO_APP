-- LEGHEVO · centro notifiche realtime
-- Eseguire nel SQL Editor di Supabase dopo 017.

create table if not exists public.user_notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  league_id uuid references public.leagues(id) on delete cascade,
  kind text not null check (
    kind in (
      'auction',
      'trade',
      'lineup',
      'result',
      'market',
      'league',
      'system'
    )
  ),
  title text not null check (char_length(title) between 1 and 90),
  body text not null check (char_length(body) between 1 and 280),
  action_screen text check (
    action_screen is null
    or action_screen in (
      'home',
      'league',
      'live',
      'auction',
      'lineup',
      'roster',
      'standings',
      'market'
    )
  ),
  metadata jsonb not null default '{}'::jsonb,
  dedupe_key text,
  read_at timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists user_notifications_inbox_idx
  on public.user_notifications (user_id, created_at desc);

create index if not exists user_notifications_unread_idx
  on public.user_notifications (user_id, created_at desc)
  where read_at is null;

create unique index if not exists user_notifications_dedupe_idx
  on public.user_notifications (user_id, dedupe_key)
  where dedupe_key is not null;

alter table public.user_notifications enable row level security;

drop policy if exists user_notifications_read_own
on public.user_notifications;

create policy user_notifications_read_own
on public.user_notifications for select to authenticated
using (user_id = auth.uid());

drop policy if exists user_notifications_update_own
on public.user_notifications;

create policy user_notifications_update_own
on public.user_notifications for update to authenticated
using (user_id = auth.uid())
with check (user_id = auth.uid());

revoke all on public.user_notifications from anon, authenticated;
grant select on public.user_notifications to authenticated;
grant update (read_at) on public.user_notifications to authenticated;

create or replace function public.create_user_notification(
  p_user_id uuid,
  p_league_id uuid,
  p_kind text,
  p_title text,
  p_body text,
  p_action_screen text default null,
  p_metadata jsonb default '{}'::jsonb,
  p_dedupe_key text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_notification_id uuid;
begin
  if p_user_id is null then
    return null;
  end if;

  insert into public.user_notifications (
    user_id,
    league_id,
    kind,
    title,
    body,
    action_screen,
    metadata,
    dedupe_key
  )
  values (
    p_user_id,
    p_league_id,
    p_kind,
    left(trim(p_title), 90),
    left(trim(p_body), 280),
    p_action_screen,
    coalesce(p_metadata, '{}'::jsonb),
    nullif(trim(p_dedupe_key), '')
  )
  on conflict (user_id, dedupe_key)
    where dedupe_key is not null
  do nothing
  returning id into v_notification_id;

  return v_notification_id;
end;
$$;

revoke all on function public.create_user_notification(
  uuid,
  uuid,
  text,
  text,
  text,
  text,
  jsonb,
  text
) from public, anon, authenticated;

create or replace function public.mark_notification_read(
  p_notification_id uuid
)
returns timestamptz
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_read_at timestamptz;
begin
  if auth.uid() is null then
    raise exception 'Devi effettuare l''accesso.';
  end if;

  update public.user_notifications
  set read_at = coalesce(read_at, now())
  where id = p_notification_id
    and user_id = auth.uid()
  returning read_at into v_read_at;

  if v_read_at is null then
    raise exception 'Notifica non trovata.';
  end if;

  return v_read_at;
end;
$$;

create or replace function public.mark_all_notifications_read()
returns integer
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

  update public.user_notifications
  set read_at = now()
  where user_id = auth.uid()
    and read_at is null;

  get diagnostics v_updated = row_count;
  return v_updated;
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

create or replace function public.notify_trade_offer_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_proposer public.fantasy_teams%rowtype;
  v_recipient public.fantasy_teams%rowtype;
  v_target_user_id uuid;
  v_title text;
  v_body text;
begin
  select team.* into v_proposer
  from public.fantasy_teams team
  where team.id = new.proposer_team_id;

  select team.* into v_recipient
  from public.fantasy_teams team
  where team.id = new.recipient_team_id;

  if tg_op = 'INSERT' then
    perform public.create_user_notification(
      v_recipient.manager_id,
      new.league_id,
      'trade',
      'Nuova proposta di scambio',
      v_proposer.name || ' ha bussato alla porta del tuo procuratore.',
      'market',
      jsonb_build_object('trade_offer_id', new.id),
      'trade:' || new.id::text || ':created'
    );
    return new;
  end if;

  if new.status is not distinct from old.status then
    return new;
  end if;

  if new.status = 'accepted' then
    v_target_user_id := v_proposer.manager_id;
    v_title := 'Scambio accettato';
    v_body := v_recipient.name || ' ha detto sì. Affare fatto.';
  elsif new.status = 'declined' then
    v_target_user_id := v_proposer.manager_id;
    v_title := 'Scambio rifiutato';
    v_body := v_recipient.name || ' ha rimandato indietro il contratto.';
  elsif new.status = 'canceled' then
    v_target_user_id := v_recipient.manager_id;
    v_title := 'Proposta ritirata';
    v_body := v_proposer.name || ' ha tolto l''offerta dal tavolo.';
  elsif new.status = 'expired' then
    v_target_user_id := v_proposer.manager_id;
    v_title := 'Proposta scaduta';
    v_body := 'Nessuna firma: la proposta con ' || v_recipient.name
      || ' è scaduta.';
  else
    return new;
  end if;

  perform public.create_user_notification(
    v_target_user_id,
    new.league_id,
    'trade',
    v_title,
    v_body,
    'market',
    jsonb_build_object(
      'trade_offer_id', new.id,
      'status', new.status
    ),
    'trade:' || new.id::text || ':' || new.status::text
  );

  return new;
end;
$$;

drop trigger if exists trade_offer_notification
on public.trade_offers;

create trigger trade_offer_notification
after insert or update of status on public.trade_offers
for each row execute function public.notify_trade_offer_change();

create or replace function public.notify_outbid_manager()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_previous_team public.fantasy_teams%rowtype;
  v_new_team public.fantasy_teams%rowtype;
  v_league_id uuid;
  v_player_name text;
begin
  select team.*
  into v_previous_team
  from public.bids bid
  join public.fantasy_teams team on team.id = bid.fantasy_team_id
  where bid.auction_item_id = new.auction_item_id
    and bid.id <> new.id
  order by bid.amount desc, bid.created_at desc
  limit 1;

  if not found or v_previous_team.id = new.fantasy_team_id then
    return new;
  end if;

  select team.* into v_new_team
  from public.fantasy_teams team
  where team.id = new.fantasy_team_id;

  select
    auction.league_id,
    trim(coalesce(athlete.first_name || ' ', '') || athlete.last_name)
  into v_league_id, v_player_name
  from public.auction_items item
  join public.auctions auction on auction.id = item.auction_id
  join public.athletes athlete on athlete.id = item.athlete_id
  where item.id = new.auction_item_id;

  perform public.create_user_notification(
    v_previous_team.manager_id,
    v_league_id,
    'auction',
    'Ti hanno superato',
    v_new_team.name || ' offre ' || new.amount || ' per ' || v_player_name
      || '. Vuoi lasciarglielo davvero?',
    'auction',
    jsonb_build_object(
      'auction_item_id', new.auction_item_id,
      'amount', new.amount
    ),
    'outbid:' || new.id::text || ':' || v_previous_team.id::text
  );

  return new;
end;
$$;

drop trigger if exists bid_outbid_notification
on public.bids;

create trigger bid_outbid_notification
after insert on public.bids
for each row execute function public.notify_outbid_manager();

create or replace function public.notify_auction_winner()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_winner public.fantasy_teams%rowtype;
  v_league_id uuid;
  v_player_name text;
begin
  if new.status <> 'sold'
    or old.status = 'sold'
    or new.winning_team_id is null then
    return new;
  end if;

  select team.* into v_winner
  from public.fantasy_teams team
  where team.id = new.winning_team_id;

  select
    auction.league_id,
    trim(coalesce(athlete.first_name || ' ', '') || athlete.last_name)
  into v_league_id, v_player_name
  from public.auctions auction
  join public.athletes athlete on athlete.id = new.athlete_id
  where auction.id = new.auction_id;

  perform public.create_user_notification(
    v_winner.manager_id,
    v_league_id,
    'auction',
    'Aggiudicato',
    v_player_name || ' entra nella tua rosa per '
      || coalesce(new.winning_price, 0) || ' crediti.',
    'roster',
    jsonb_build_object(
      'auction_item_id', new.id,
      'athlete_id', new.athlete_id
    ),
    'auction-sold:' || new.id::text
  );

  return new;
end;
$$;

drop trigger if exists auction_winner_notification
on public.auction_items;

create trigger auction_winner_notification
after update of status on public.auction_items
for each row execute function public.notify_auction_winner();

create or replace function public.notify_final_fantasy_result()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_home public.fantasy_teams%rowtype;
  v_away public.fantasy_teams%rowtype;
  v_result text;
begin
  if new.finalized_at is null or old.finalized_at is not null then
    return new;
  end if;

  select team.* into v_home
  from public.fantasy_teams team
  where team.id = new.home_team_id;

  select team.* into v_away
  from public.fantasy_teams team
  where team.id = new.away_team_id;

  v_result := v_home.name || ' ' || coalesce(new.home_goals, 0)
    || '–' || coalesce(new.away_goals, 0) || ' ' || v_away.name;

  perform public.create_user_notification(
    v_home.manager_id,
    new.league_id,
    'result',
    'Risultato definitivo',
    v_result || '. Il VAR ha chiuso tutto.',
    'live',
    jsonb_build_object('fixture_id', new.id),
    'result:' || new.id::text || ':' || v_home.manager_id::text
  );

  perform public.create_user_notification(
    v_away.manager_id,
    new.league_id,
    'result',
    'Risultato definitivo',
    v_result || '. Il VAR ha chiuso tutto.',
    'live',
    jsonb_build_object('fixture_id', new.id),
    'result:' || new.id::text || ':' || v_away.manager_id::text
  );

  return new;
end;
$$;

drop trigger if exists fantasy_result_notification
on public.fantasy_fixtures;

create trigger fantasy_result_notification
after update of finalized_at on public.fantasy_fixtures
for each row execute function public.notify_final_fantasy_result();

do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'user_notifications'
  ) then
    alter publication supabase_realtime
      add table public.user_notifications;
  end if;
end;
$$;

select
  to_regclass('public.user_notifications') is not null
    as notification_table_ready,
  to_regprocedure('public.mark_notification_read(uuid)') is not null
    as notification_read_ready,
  to_regprocedure('public.mark_all_notifications_read()') is not null
    as notification_read_all_ready,
  exists (
    select 1
    from pg_trigger
    where tgname = 'trade_offer_notification'
      and not tgisinternal
  ) as trade_notifications_ready,
  exists (
    select 1
    from pg_trigger
    where tgname = 'bid_outbid_notification'
      and not tgisinternal
  ) as auction_notifications_ready,
  exists (
    select 1
    from pg_trigger
    where tgname = 'fantasy_result_notification'
      and not tgisinternal
  ) as result_notifications_ready;
