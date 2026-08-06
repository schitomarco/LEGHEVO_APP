-- LEGHEVO · mercato, svincoli e scambi
-- Eseguire nel SQL Editor di Supabase dopo 010.

do $$
begin
  create type public.trade_offer_status as enum (
    'pending',
    'accepted',
    'declined',
    'canceled',
    'expired'
  );
exception
  when duplicate_object then null;
end;
$$;

create table if not exists public.trade_offers (
  id uuid primary key default gen_random_uuid(),
  league_id uuid not null references public.leagues(id) on delete cascade,
  proposer_team_id uuid not null
    references public.fantasy_teams(id) on delete cascade,
  recipient_team_id uuid not null
    references public.fantasy_teams(id) on delete cascade,
  status public.trade_offer_status not null default 'pending',
  proposer_credits integer not null default 0
    check (proposer_credits >= 0),
  recipient_credits integer not null default 0
    check (recipient_credits >= 0),
  message text,
  expires_at timestamptz not null default (now() + interval '7 days'),
  created_at timestamptz not null default now(),
  responded_at timestamptz,
  check (proposer_team_id <> recipient_team_id)
);

create table if not exists public.trade_offer_players (
  trade_offer_id uuid not null
    references public.trade_offers(id) on delete cascade,
  fantasy_team_id uuid not null
    references public.fantasy_teams(id) on delete cascade,
  athlete_id uuid not null references public.athletes(id),
  primary key (trade_offer_id, athlete_id)
);

create index if not exists trade_offers_league_status_idx
  on public.trade_offers (league_id, status, created_at desc);

create index if not exists trade_offer_players_team_idx
  on public.trade_offer_players (fantasy_team_id, trade_offer_id);

alter table public.trade_offers enable row level security;
alter table public.trade_offer_players enable row level security;

drop policy if exists trade_offers_read_members
on public.trade_offers;

create policy trade_offers_read_members
on public.trade_offers for select to authenticated
using (public.is_league_member(league_id));

drop policy if exists trade_offer_players_read_members
on public.trade_offer_players;

create policy trade_offer_players_read_members
on public.trade_offer_players for select to authenticated
using (
  exists (
    select 1
    from public.trade_offers offer
    where offer.id = trade_offer_id
      and public.is_league_member(offer.league_id)
  )
);

grant select on public.trade_offers to authenticated;
grant select on public.trade_offer_players to authenticated;

create or replace function public.sign_free_agent(
  p_fantasy_team_id uuid,
  p_athlete_id uuid
)
returns public.roster_entries
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_team public.fantasy_teams%rowtype;
  v_league public.leagues%rowtype;
  v_roster_count integer;
  v_price integer;
  v_result public.roster_entries%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Devi effettuare l''accesso.';
  end if;

  select team.*
  into v_team
  from public.fantasy_teams team
  where team.id = p_fantasy_team_id
  for update;

  if not found then
    raise exception 'Squadra non trovata.';
  end if;

  if v_team.manager_id <> auth.uid()
    and not public.is_league_admin(v_team.league_id) then
    raise exception 'Puoi acquistare soltanto per la tua squadra.';
  end if;

  select league.*
  into v_league
  from public.leagues league
  where league.id = v_team.league_id;

  if v_league.status in ('completed', 'archived') then
    raise exception 'Il mercato di questa lega è chiuso.';
  end if;

  if coalesce(v_league.scoring_rules ->> 'market_open', 'true') = 'false' then
    raise exception 'Il presidente ha chiuso il mercato.';
  end if;

  if not exists (
    select 1
    from public.athletes athlete
    where athlete.id = p_athlete_id
      and athlete.active
  ) then
    raise exception 'Calciatore non disponibile.';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      v_team.league_id::text || ':' || p_athlete_id::text,
      0
    )
  );

  if exists (
    select 1
    from public.roster_entries roster
    where roster.league_id = v_team.league_id
      and roster.athlete_id = p_athlete_id
      and roster.released_at is null
  ) then
    raise exception 'Questo calciatore appartiene già a una squadra.';
  end if;

  select count(*)::integer
  into v_roster_count
  from public.roster_entries roster
  where roster.fantasy_team_id = v_team.id
    and roster.released_at is null;

  if v_roster_count >= v_league.roster_size then
    raise exception 'Rosa completa: prima devi svincolare un calciatore.';
  end if;

  v_price := greatest(
    coalesce((v_league.scoring_rules ->> 'market_min_price')::integer, 1),
    1
  );

  if v_team.credits_remaining < v_price then
    raise exception 'Crediti insufficienti per completare l''acquisto.';
  end if;

  update public.fantasy_teams
  set credits_remaining = credits_remaining - v_price
  where id = v_team.id;

  insert into public.roster_entries (
    league_id,
    fantasy_team_id,
    athlete_id,
    purchase_price
  )
  values (
    v_team.league_id,
    v_team.id,
    p_athlete_id,
    v_price
  )
  returning * into v_result;

  insert into public.team_transactions (
    league_id,
    fantasy_team_id,
    athlete_id,
    transaction_type,
    credit_delta,
    metadata
  )
  values (
    v_team.league_id,
    v_team.id,
    p_athlete_id,
    'market_purchase',
    -v_price,
    jsonb_build_object('source', 'free_agent_market')
  );

  return v_result;
end;
$$;

create or replace function public.release_roster_player(
  p_fantasy_team_id uuid,
  p_athlete_id uuid
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_team public.fantasy_teams%rowtype;
  v_league public.leagues%rowtype;
  v_roster public.roster_entries%rowtype;
  v_refund_percent integer;
  v_refund integer;
begin
  if auth.uid() is null then
    raise exception 'Devi effettuare l''accesso.';
  end if;

  select team.*
  into v_team
  from public.fantasy_teams team
  where team.id = p_fantasy_team_id
  for update;

  if not found then
    raise exception 'Squadra non trovata.';
  end if;

  if v_team.manager_id <> auth.uid()
    and not public.is_league_admin(v_team.league_id) then
    raise exception 'Puoi svincolare soltanto dalla tua squadra.';
  end if;

  select league.*
  into v_league
  from public.leagues league
  where league.id = v_team.league_id;

  if v_league.status in ('completed', 'archived') then
    raise exception 'Il mercato di questa lega è chiuso.';
  end if;

  if coalesce(v_league.scoring_rules ->> 'market_open', 'true') = 'false' then
    raise exception 'Il presidente ha chiuso il mercato.';
  end if;

  select roster.*
  into v_roster
  from public.roster_entries roster
  where roster.fantasy_team_id = v_team.id
    and roster.athlete_id = p_athlete_id
    and roster.released_at is null
  for update;

  if not found then
    raise exception 'Il calciatore non è presente nella tua rosa.';
  end if;

  if exists (
    select 1
    from public.lineups lineup
    join public.lineup_entries entry on entry.lineup_id = lineup.id
    join public.matchdays matchday on matchday.id = lineup.matchday_id
    where lineup.fantasy_team_id = v_team.id
      and entry.athlete_id = p_athlete_id
      and matchday.locks_at > now()
  ) then
    raise exception 'Rimuovi prima il calciatore dalla formazione consegnata.';
  end if;

  v_refund_percent := least(
    greatest(
      coalesce(
        (v_league.scoring_rules ->> 'release_refund_percent')::integer,
        50
      ),
      0
    ),
    100
  );
  v_refund := floor(
    v_roster.purchase_price * v_refund_percent / 100.0
  )::integer;

  update public.roster_entries
  set released_at = now()
  where id = v_roster.id;

  update public.fantasy_teams
  set credits_remaining = credits_remaining + v_refund
  where id = v_team.id;

  insert into public.team_transactions (
    league_id,
    fantasy_team_id,
    athlete_id,
    transaction_type,
    credit_delta,
    metadata
  )
  values (
    v_team.league_id,
    v_team.id,
    p_athlete_id,
    'release',
    v_refund,
    jsonb_build_object(
      'purchase_price', v_roster.purchase_price,
      'refund_percent', v_refund_percent
    )
  );

  update public.trade_offers offer
  set
    status = 'canceled',
    responded_at = now()
  where offer.status = 'pending'
    and exists (
      select 1
      from public.trade_offer_players offered_player
      where offered_player.trade_offer_id = offer.id
        and offered_player.athlete_id = p_athlete_id
    );

  return v_refund;
end;
$$;

create or replace function public.create_trade_offer(
  p_proposer_team_id uuid,
  p_recipient_team_id uuid,
  p_offered_player_ids uuid[] default array[]::uuid[],
  p_requested_player_ids uuid[] default array[]::uuid[],
  p_proposer_credits integer default 0,
  p_recipient_credits integer default 0,
  p_message text default null
)
returns public.trade_offers
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_proposer public.fantasy_teams%rowtype;
  v_recipient public.fantasy_teams%rowtype;
  v_league public.leagues%rowtype;
  v_offer public.trade_offers%rowtype;
  v_offered_count integer;
  v_requested_count integer;
begin
  if auth.uid() is null then
    raise exception 'Devi effettuare l''accesso.';
  end if;

  select team.*
  into v_proposer
  from public.fantasy_teams team
  where team.id = p_proposer_team_id;

  if not found then
    raise exception 'Squadra proponente non trovata.';
  end if;

  if v_proposer.manager_id <> auth.uid()
    and not public.is_league_admin(v_proposer.league_id) then
    raise exception 'Puoi proporre scambi soltanto dalla tua squadra.';
  end if;

  select team.*
  into v_recipient
  from public.fantasy_teams team
  where team.id = p_recipient_team_id;

  if not found or v_recipient.league_id <> v_proposer.league_id then
    raise exception 'La squadra destinataria non appartiene alla lega.';
  end if;

  if v_proposer.id = v_recipient.id then
    raise exception 'Non puoi fare uno scambio con te stesso.';
  end if;

  select league.*
  into v_league
  from public.leagues league
  where league.id = v_proposer.league_id;

  if v_league.status in ('completed', 'archived')
    or coalesce(v_league.scoring_rules ->> 'market_open', 'true') = 'false'
  then
    raise exception 'Il mercato di questa lega è chiuso.';
  end if;

  if p_proposer_credits < 0 or p_recipient_credits < 0 then
    raise exception 'I crediti inseriti non possono essere negativi.';
  end if;

  v_offered_count := coalesce(cardinality(p_offered_player_ids), 0);
  v_requested_count := coalesce(cardinality(p_requested_player_ids), 0);

  if v_offered_count + v_requested_count = 0 then
    raise exception 'Lo scambio deve contenere almeno un calciatore.';
  end if;

  if (
    select count(distinct athlete_id)
    from unnest(coalesce(p_offered_player_ids, array[]::uuid[]))
      as offered(athlete_id)
  ) <> v_offered_count then
    raise exception 'Hai inserito due volte lo stesso calciatore offerto.';
  end if;

  if (
    select count(distinct athlete_id)
    from unnest(coalesce(p_requested_player_ids, array[]::uuid[]))
      as requested(athlete_id)
  ) <> v_requested_count then
    raise exception 'Hai inserito due volte lo stesso calciatore richiesto.';
  end if;

  if coalesce(p_offered_player_ids, array[]::uuid[])
    && coalesce(p_requested_player_ids, array[]::uuid[]) then
    raise exception 'Lo stesso calciatore non può essere su entrambi i lati.';
  end if;

  if (
    select count(*)::integer
    from public.roster_entries roster
    where roster.fantasy_team_id = v_proposer.id
      and roster.released_at is null
      and roster.athlete_id = any(
        coalesce(p_offered_player_ids, array[]::uuid[])
      )
  ) <> v_offered_count then
    raise exception 'Uno dei calciatori offerti non è più nella tua rosa.';
  end if;

  if (
    select count(*)::integer
    from public.roster_entries roster
    where roster.fantasy_team_id = v_recipient.id
      and roster.released_at is null
      and roster.athlete_id = any(
        coalesce(p_requested_player_ids, array[]::uuid[])
      )
  ) <> v_requested_count then
    raise exception 'Uno dei calciatori richiesti non è disponibile.';
  end if;

  if v_proposer.credits_remaining < p_proposer_credits then
    raise exception 'Non hai abbastanza crediti per questa proposta.';
  end if;

  insert into public.trade_offers (
    league_id,
    proposer_team_id,
    recipient_team_id,
    proposer_credits,
    recipient_credits,
    message
  )
  values (
    v_proposer.league_id,
    v_proposer.id,
    v_recipient.id,
    p_proposer_credits,
    p_recipient_credits,
    nullif(trim(p_message), '')
  )
  returning * into v_offer;

  insert into public.trade_offer_players (
    trade_offer_id,
    fantasy_team_id,
    athlete_id
  )
  select
    v_offer.id,
    v_proposer.id,
    offered.athlete_id
  from unnest(
    coalesce(p_offered_player_ids, array[]::uuid[])
  ) as offered(athlete_id);

  insert into public.trade_offer_players (
    trade_offer_id,
    fantasy_team_id,
    athlete_id
  )
  select
    v_offer.id,
    v_recipient.id,
    requested.athlete_id
  from unnest(
    coalesce(p_requested_player_ids, array[]::uuid[])
  ) as requested(athlete_id);

  return v_offer;
end;
$$;

create or replace function public.respond_trade_offer(
  p_trade_offer_id uuid,
  p_accept boolean
)
returns public.trade_offers
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_offer public.trade_offers%rowtype;
  v_proposer public.fantasy_teams%rowtype;
  v_recipient public.fantasy_teams%rowtype;
  v_league public.leagues%rowtype;
  v_player record;
  v_purchase_price integer;
  v_proposer_count integer;
  v_recipient_count integer;
  v_offered_count integer;
  v_requested_count integer;
  v_audit_athlete_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Devi effettuare l''accesso.';
  end if;

  select offer.*
  into v_offer
  from public.trade_offers offer
  where offer.id = p_trade_offer_id
  for update;

  if not found then
    raise exception 'Proposta di scambio non trovata.';
  end if;

  if v_offer.status <> 'pending' then
    raise exception 'Questa proposta non è più disponibile.';
  end if;

  if v_offer.expires_at <= now() then
    update public.trade_offers
    set status = 'expired', responded_at = now()
    where id = v_offer.id;
    select expired_offer.*
    into v_offer
    from public.trade_offers expired_offer
    where expired_offer.id = v_offer.id;
    return v_offer;
  end if;

  select team.*
  into v_recipient
  from public.fantasy_teams team
  where team.id = v_offer.recipient_team_id;

  if v_recipient.manager_id <> auth.uid()
    and not public.is_league_admin(v_offer.league_id) then
    raise exception 'Solo la squadra destinataria può rispondere.';
  end if;

  if not p_accept then
    update public.trade_offers
    set status = 'declined', responded_at = now()
    where id = v_offer.id
    returning * into v_offer;
    return v_offer;
  end if;

  perform team.id
  from public.fantasy_teams team
  where team.id in (
    v_offer.proposer_team_id,
    v_offer.recipient_team_id
  )
  order by team.id
  for update;

  select team.*
  into v_proposer
  from public.fantasy_teams team
  where team.id = v_offer.proposer_team_id;

  select team.*
  into v_recipient
  from public.fantasy_teams team
  where team.id = v_offer.recipient_team_id;

  select league.*
  into v_league
  from public.leagues league
  where league.id = v_offer.league_id;

  if v_league.status in ('completed', 'archived')
    or coalesce(v_league.scoring_rules ->> 'market_open', 'true') = 'false'
  then
    raise exception 'Il mercato di questa lega è chiuso.';
  end if;

  if v_proposer.credits_remaining < v_offer.proposer_credits
    or v_recipient.credits_remaining < v_offer.recipient_credits then
    raise exception 'Una delle squadre non ha più i crediti promessi.';
  end if;

  select
    count(*) filter (
      where player.fantasy_team_id = v_proposer.id
    )::integer,
    count(*) filter (
      where player.fantasy_team_id = v_recipient.id
    )::integer
  into v_offered_count, v_requested_count
  from public.trade_offer_players player
  where player.trade_offer_id = v_offer.id;

  if (
    select count(*)::integer
    from public.roster_entries roster
    join public.trade_offer_players player
      on player.athlete_id = roster.athlete_id
      and player.fantasy_team_id = roster.fantasy_team_id
    where player.trade_offer_id = v_offer.id
      and roster.released_at is null
  ) <> v_offered_count + v_requested_count then
    raise exception 'Le rose sono cambiate: la proposta deve essere rifatta.';
  end if;

  select count(*)::integer
  into v_proposer_count
  from public.roster_entries roster
  where roster.fantasy_team_id = v_proposer.id
    and roster.released_at is null;

  select count(*)::integer
  into v_recipient_count
  from public.roster_entries roster
  where roster.fantasy_team_id = v_recipient.id
    and roster.released_at is null;

  if v_proposer_count - v_offered_count + v_requested_count
      > v_league.roster_size
    or v_recipient_count - v_requested_count + v_offered_count
      > v_league.roster_size then
    raise exception 'Lo scambio supererebbe il limite della rosa.';
  end if;

  if exists (
    select 1
    from public.trade_offer_players player
    join public.lineups lineup
      on lineup.fantasy_team_id = player.fantasy_team_id
    join public.lineup_entries entry
      on entry.lineup_id = lineup.id
      and entry.athlete_id = player.athlete_id
    join public.matchdays matchday on matchday.id = lineup.matchday_id
    where player.trade_offer_id = v_offer.id
      and matchday.locks_at > now()
  ) then
    raise exception 'Un calciatore è in una formazione già consegnata.';
  end if;

  for v_player in
    select player.fantasy_team_id, player.athlete_id
    from public.trade_offer_players player
    where player.trade_offer_id = v_offer.id
      and player.fantasy_team_id = v_proposer.id
  loop
    select roster.purchase_price
    into v_purchase_price
    from public.roster_entries roster
    where roster.fantasy_team_id = v_proposer.id
      and roster.athlete_id = v_player.athlete_id
      and roster.released_at is null
    for update;

    update public.roster_entries
    set released_at = now()
    where fantasy_team_id = v_proposer.id
      and athlete_id = v_player.athlete_id
      and released_at is null;

    insert into public.roster_entries (
      league_id,
      fantasy_team_id,
      athlete_id,
      purchase_price
    )
    values (
      v_offer.league_id,
      v_recipient.id,
      v_player.athlete_id,
      v_purchase_price
    );
  end loop;

  for v_player in
    select player.fantasy_team_id, player.athlete_id
    from public.trade_offer_players player
    where player.trade_offer_id = v_offer.id
      and player.fantasy_team_id = v_recipient.id
  loop
    select roster.purchase_price
    into v_purchase_price
    from public.roster_entries roster
    where roster.fantasy_team_id = v_recipient.id
      and roster.athlete_id = v_player.athlete_id
      and roster.released_at is null
    for update;

    update public.roster_entries
    set released_at = now()
    where fantasy_team_id = v_recipient.id
      and athlete_id = v_player.athlete_id
      and released_at is null;

    insert into public.roster_entries (
      league_id,
      fantasy_team_id,
      athlete_id,
      purchase_price
    )
    values (
      v_offer.league_id,
      v_proposer.id,
      v_player.athlete_id,
      v_purchase_price
    );
  end loop;

  update public.fantasy_teams
  set credits_remaining =
    credits_remaining
    - v_offer.proposer_credits
    + v_offer.recipient_credits
  where id = v_proposer.id;

  update public.fantasy_teams
  set credits_remaining =
    credits_remaining
    - v_offer.recipient_credits
    + v_offer.proposer_credits
  where id = v_recipient.id;

  select player.athlete_id
  into v_audit_athlete_id
  from public.trade_offer_players player
  where player.trade_offer_id = v_offer.id
  order by player.athlete_id
  limit 1;

  insert into public.team_transactions (
    league_id,
    fantasy_team_id,
    athlete_id,
    transaction_type,
    credit_delta,
    metadata
  )
  values
    (
      v_offer.league_id,
      v_proposer.id,
      v_audit_athlete_id,
      'trade',
      v_offer.recipient_credits - v_offer.proposer_credits,
      jsonb_build_object('trade_offer_id', v_offer.id)
    ),
    (
      v_offer.league_id,
      v_recipient.id,
      v_audit_athlete_id,
      'trade',
      v_offer.proposer_credits - v_offer.recipient_credits,
      jsonb_build_object('trade_offer_id', v_offer.id)
    );

  update public.trade_offers other_offer
  set status = 'canceled', responded_at = now()
  where other_offer.status = 'pending'
    and other_offer.id <> v_offer.id
    and exists (
      select 1
      from public.trade_offer_players current_player
      join public.trade_offer_players other_player
        on other_player.athlete_id = current_player.athlete_id
      where current_player.trade_offer_id = v_offer.id
        and other_player.trade_offer_id = other_offer.id
    );

  update public.trade_offers
  set status = 'accepted', responded_at = now()
  where id = v_offer.id
  returning * into v_offer;

  return v_offer;
end;
$$;

create or replace function public.cancel_trade_offer(
  p_trade_offer_id uuid
)
returns public.trade_offers
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_offer public.trade_offers%rowtype;
  v_proposer public.fantasy_teams%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Devi effettuare l''accesso.';
  end if;

  select offer.*
  into v_offer
  from public.trade_offers offer
  where offer.id = p_trade_offer_id
  for update;

  if not found then
    raise exception 'Proposta di scambio non trovata.';
  end if;

  select team.*
  into v_proposer
  from public.fantasy_teams team
  where team.id = v_offer.proposer_team_id;

  if v_proposer.manager_id <> auth.uid()
    and not public.is_league_admin(v_offer.league_id) then
    raise exception 'Solo chi ha proposto lo scambio può annullarlo.';
  end if;

  if v_offer.status <> 'pending' then
    raise exception 'Questa proposta non può più essere annullata.';
  end if;

  update public.trade_offers
  set status = 'canceled', responded_at = now()
  where id = v_offer.id
  returning * into v_offer;

  return v_offer;
end;
$$;

revoke all on function public.sign_free_agent(uuid, uuid) from public;
revoke all on function public.release_roster_player(uuid, uuid) from public;
revoke all on function public.create_trade_offer(
  uuid,
  uuid,
  uuid[],
  uuid[],
  integer,
  integer,
  text
) from public;
revoke all on function public.respond_trade_offer(uuid, boolean) from public;
revoke all on function public.cancel_trade_offer(uuid) from public;

grant execute on function public.sign_free_agent(uuid, uuid)
to authenticated;
grant execute on function public.release_roster_player(uuid, uuid)
to authenticated;
grant execute on function public.create_trade_offer(
  uuid,
  uuid,
  uuid[],
  uuid[],
  integer,
  integer,
  text
) to authenticated;
grant execute on function public.respond_trade_offer(uuid, boolean)
to authenticated;
grant execute on function public.cancel_trade_offer(uuid)
to authenticated;

do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'trade_offers'
  ) then
    alter publication supabase_realtime
      add table public.trade_offers;
  end if;

  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'trade_offer_players'
  ) then
    alter publication supabase_realtime
      add table public.trade_offer_players;
  end if;

  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'roster_entries'
  ) then
    alter publication supabase_realtime
      add table public.roster_entries;
  end if;

  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'fantasy_teams'
  ) then
    alter publication supabase_realtime
      add table public.fantasy_teams;
  end if;
end;
$$;

select
  to_regprocedure(
    'public.sign_free_agent(uuid,uuid)'
  ) is not null as free_agents_ready,
  to_regprocedure(
    'public.release_roster_player(uuid,uuid)'
  ) is not null as releases_ready,
  to_regprocedure(
    'public.create_trade_offer(uuid,uuid,uuid[],uuid[],integer,integer,text)'
  ) is not null as trade_offers_ready,
  to_regprocedure(
    'public.respond_trade_offer(uuid,boolean)'
  ) is not null as trade_responses_ready,
  to_regprocedure(
    'public.cancel_trade_offer(uuid)'
  ) is not null as trade_cancellations_ready;
