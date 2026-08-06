-- LEGHEVO · sicurezza atomica degli scambi
-- Versione applicativa: 0.57.2
-- Eseguire dopo 066_market_roster_integrity.sql.
-- Script idempotente: può essere eseguito più volte.

begin;

-- 1) Prenotazioni esplicite dei calciatori offerti e dei crediti promessi.
--    Le tabelle non sono scrivibili dal client: vengono mantenute da trigger.
create table if not exists public.trade_player_reservations (
  trade_offer_id uuid not null
    references public.trade_offers(id) on delete cascade,
  league_id uuid not null
    references public.leagues(id) on delete cascade,
  fantasy_team_id uuid not null
    references public.fantasy_teams(id) on delete cascade,
  athlete_id uuid not null
    references public.athletes(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (trade_offer_id, athlete_id),
  unique (fantasy_team_id, athlete_id)
);

create table if not exists public.trade_credit_reservations (
  trade_offer_id uuid primary key
    references public.trade_offers(id) on delete cascade,
  league_id uuid not null
    references public.leagues(id) on delete cascade,
  fantasy_team_id uuid not null
    references public.fantasy_teams(id) on delete cascade,
  amount integer not null check (amount >= 0),
  created_at timestamptz not null default now()
);

create index if not exists trade_player_reservations_league_idx
  on public.trade_player_reservations (league_id, fantasy_team_id);

create index if not exists trade_credit_reservations_team_idx
  on public.trade_credit_reservations (fantasy_team_id, trade_offer_id);

alter table public.trade_player_reservations enable row level security;
alter table public.trade_credit_reservations enable row level security;

revoke all on table public.trade_player_reservations from public;
revoke all on table public.trade_credit_reservations from public;
revoke all on table public.trade_player_reservations from authenticated;
revoke all on table public.trade_credit_reservations from authenticated;

-- 2) Prima del backfill manteniamo una sola proposta pendente per ogni
--    calciatore realmente offerto dalla stessa squadra.
with ranked_commitments as (
  select
    offer.id,
    row_number() over (
      partition by player.fantasy_team_id, player.athlete_id
      order by offer.created_at asc, offer.id asc
    ) as commitment_rank
  from public.trade_offers offer
  join public.trade_offer_players player
    on player.trade_offer_id = offer.id
   and player.fantasy_team_id = offer.proposer_team_id
  where offer.status = 'pending'
    and offer.expires_at > now()
)
update public.trade_offers offer
set
  status = 'canceled',
  responded_at = coalesce(offer.responded_at, now())
where offer.id in (
  select commitment.id
  from ranked_commitments commitment
  where commitment.commitment_rank > 1
);

-- Chiude anche le proposte già scadute, così non prenotano risorse.
update public.trade_offers offer
set
  status = 'expired',
  responded_at = coalesce(offer.responded_at, now())
where offer.status = 'pending'
  and offer.expires_at <= now();

-- 3) Sincronizzazione automatica delle prenotazioni.
create or replace function public.sync_trade_offer_reservations()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_offer public.trade_offers%rowtype;
begin
  if tg_op = 'DELETE' then
    v_offer := old;
  else
    v_offer := new;
  end if;

  delete from public.trade_player_reservations reservation
  where reservation.trade_offer_id = v_offer.id;

  delete from public.trade_credit_reservations reservation
  where reservation.trade_offer_id = v_offer.id;

  if tg_op <> 'DELETE' and new.status = 'pending' then
    insert into public.trade_credit_reservations (
      trade_offer_id,
      league_id,
      fantasy_team_id,
      amount
    )
    values (
      new.id,
      new.league_id,
      new.proposer_team_id,
      new.proposer_credits
    );

    insert into public.trade_player_reservations (
      trade_offer_id,
      league_id,
      fantasy_team_id,
      athlete_id
    )
    select
      new.id,
      new.league_id,
      new.proposer_team_id,
      player.athlete_id
    from public.trade_offer_players player
    where player.trade_offer_id = new.id
      and player.fantasy_team_id = new.proposer_team_id;
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

create or replace function public.sync_trade_player_reservation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_offer public.trade_offers%rowtype;
begin
  if tg_op in ('UPDATE', 'DELETE') then
    delete from public.trade_player_reservations reservation
    where reservation.trade_offer_id = old.trade_offer_id
      and reservation.athlete_id = old.athlete_id;
  end if;

  if tg_op <> 'DELETE' then
    select offer.*
    into v_offer
    from public.trade_offers offer
    where offer.id = new.trade_offer_id;

    if found
      and v_offer.status = 'pending'
      and new.fantasy_team_id = v_offer.proposer_team_id
    then
      begin
        insert into public.trade_player_reservations (
          trade_offer_id,
          league_id,
          fantasy_team_id,
          athlete_id
        )
        values (
          v_offer.id,
          v_offer.league_id,
          v_offer.proposer_team_id,
          new.athlete_id
        );
      exception
        when unique_violation then
          raise exception
            'Il calciatore è già impegnato in un''altra proposta pendente.';
      end;
    end if;
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

revoke all on function public.sync_trade_offer_reservations() from public;
revoke all on function public.sync_trade_player_reservation() from public;

-- Ricostruzione deterministica delle prenotazioni esistenti.
delete from public.trade_player_reservations;
delete from public.trade_credit_reservations;

insert into public.trade_credit_reservations (
  trade_offer_id,
  league_id,
  fantasy_team_id,
  amount,
  created_at
)
select
  offer.id,
  offer.league_id,
  offer.proposer_team_id,
  offer.proposer_credits,
  offer.created_at
from public.trade_offers offer
where offer.status = 'pending'
  and offer.expires_at > now();

insert into public.trade_player_reservations (
  trade_offer_id,
  league_id,
  fantasy_team_id,
  athlete_id,
  created_at
)
select
  offer.id,
  offer.league_id,
  offer.proposer_team_id,
  player.athlete_id,
  offer.created_at
from public.trade_offers offer
join public.trade_offer_players player
  on player.trade_offer_id = offer.id
 and player.fantasy_team_id = offer.proposer_team_id
where offer.status = 'pending'
  and offer.expires_at > now();

-- Il trigger sull'offerta viene creato dopo il backfill per non duplicare righe.
drop trigger if exists trade_offer_reservations_sync
on public.trade_offers;

create trigger trade_offer_reservations_sync
after insert or delete or update of status, proposer_credits, proposer_team_id, league_id
on public.trade_offers
for each row execute function public.sync_trade_offer_reservations();

drop trigger if exists trade_player_reservation_sync
on public.trade_offer_players;

create trigger trade_player_reservation_sync
after insert or delete or update of trade_offer_id, fantasy_team_id, athlete_id
on public.trade_offer_players
for each row execute function public.sync_trade_player_reservation();

-- 4) Protezione dei crediti già promessi in altre trattative.
create or replace function public.guard_trade_credit_reservation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_team public.fantasy_teams%rowtype;
  v_other_reserved integer;
begin
  select team.*
  into v_team
  from public.fantasy_teams team
  where team.id = new.fantasy_team_id
  for update;

  if not found then
    raise exception 'Squadra non trovata.';
  end if;

  if new.league_id is distinct from v_team.league_id then
    raise exception 'La prenotazione crediti appartiene a una lega diversa.';
  end if;

  select coalesce(sum(reservation.amount), 0)::integer
  into v_other_reserved
  from public.trade_credit_reservations reservation
  where reservation.fantasy_team_id = new.fantasy_team_id
    and reservation.trade_offer_id <> new.trade_offer_id;

  if v_other_reserved + new.amount > v_team.credits_remaining then
    raise exception
      'Crediti già impegnati: annulla una proposta o riduci l''offerta.';
  end if;

  return new;
end;
$$;

revoke all on function public.guard_trade_credit_reservation() from public;

drop trigger if exists trade_credit_reservation_guard
on public.trade_credit_reservations;

create trigger trade_credit_reservation_guard
before insert or update of league_id, fantasy_team_id, amount
on public.trade_credit_reservations
for each row execute function public.guard_trade_credit_reservation();

-- 5) Valida in anticipo il risultato completo di una proposta.
create or replace function public.assert_trade_offer_safe(
  p_trade_offer_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_offer public.trade_offers%rowtype;
  v_proposer public.fantasy_teams%rowtype;
  v_recipient public.fantasy_teams%rowtype;
  v_league public.leagues%rowtype;
  v_group text;
  v_group_label text;
  v_quota integer;
  v_proposer_current integer;
  v_recipient_current integer;
  v_proposer_out integer;
  v_proposer_in integer;
  v_recipient_out integer;
  v_recipient_in integer;
  v_offered_count integer;
  v_requested_count integer;
  v_proposer_count integer;
  v_recipient_count integer;
  v_proposer_final_credits integer;
  v_recipient_final_credits integer;
  v_proposer_other_reserved integer;
  v_recipient_reserved integer;
  v_minimum_price integer;
  v_proposer_required_reserve integer;
  v_recipient_required_reserve integer;
begin
  select offer.*
  into v_offer
  from public.trade_offers offer
  where offer.id = p_trade_offer_id;

  if not found then
    raise exception 'Proposta di scambio non trovata.';
  end if;

  if v_offer.status <> 'pending' then
    return;
  end if;

  if v_offer.expires_at <= now() then
    raise exception 'La proposta è scaduta.';
  end if;

  select team.*
  into v_proposer
  from public.fantasy_teams team
  where team.id = v_offer.proposer_team_id;

  select team.*
  into v_recipient
  from public.fantasy_teams team
  where team.id = v_offer.recipient_team_id;

  if not found or v_proposer.id is null then
    raise exception 'Una delle squadre della proposta non esiste più.';
  end if;

  if v_proposer.league_id is distinct from v_offer.league_id
    or v_recipient.league_id is distinct from v_offer.league_id then
    raise exception 'Le squadre della proposta non appartengono alla stessa lega.';
  end if;

  select league.*
  into v_league
  from public.leagues league
  where league.id = v_offer.league_id;

  if not found then
    raise exception 'Lega non trovata.';
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

  if v_offered_count + v_requested_count = 0 then
    raise exception 'Lo scambio deve contenere almeno un calciatore.';
  end if;

  if exists (
    select 1
    from public.trade_offer_players player
    where player.trade_offer_id = v_offer.id
      and player.fantasy_team_id not in (
        v_proposer.id,
        v_recipient.id
      )
  ) then
    raise exception 'La proposta contiene una squadra non valida.';
  end if;

  if (
    select count(*)::integer
    from public.roster_entries roster
    join public.trade_offer_players player
      on player.fantasy_team_id = roster.fantasy_team_id
     and player.athlete_id = roster.athlete_id
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

  foreach v_group in array array[
    'goalkeepers',
    'defenders',
    'midfielders',
    'attackers'
  ]
  loop
    select count(*)::integer
    into v_proposer_current
    from public.roster_entries roster
    where roster.fantasy_team_id = v_proposer.id
      and roster.released_at is null
      and public.athlete_roster_group(
        roster.athlete_id,
        v_league.mode
      ) = v_group;

    select count(*)::integer
    into v_recipient_current
    from public.roster_entries roster
    where roster.fantasy_team_id = v_recipient.id
      and roster.released_at is null
      and public.athlete_roster_group(
        roster.athlete_id,
        v_league.mode
      ) = v_group;

    select count(*) filter (
      where player.fantasy_team_id = v_proposer.id
        and public.athlete_roster_group(
          player.athlete_id,
          v_league.mode
        ) = v_group
    )::integer,
    count(*) filter (
      where player.fantasy_team_id = v_recipient.id
        and public.athlete_roster_group(
          player.athlete_id,
          v_league.mode
        ) = v_group
    )::integer
    into v_proposer_out, v_recipient_out
    from public.trade_offer_players player
    where player.trade_offer_id = v_offer.id;

    v_proposer_in := v_recipient_out;
    v_recipient_in := v_proposer_out;
    v_quota := public.league_roster_quota(v_league.id, v_group);
    v_group_label := case v_group
      when 'goalkeepers' then 'portieri'
      when 'defenders' then 'difensori'
      when 'midfielders' then 'centrocampisti'
      when 'attackers' then 'attaccanti'
      else 'calciatori'
    end;

    if v_proposer_current - v_proposer_out + v_proposer_in > v_quota
      or v_recipient_current - v_recipient_out + v_recipient_in > v_quota
    then
      raise exception
        'Lo scambio supererebbe il limite dei %.',
        v_group_label;
    end if;
  end loop;

  v_proposer_final_credits :=
    v_proposer.credits_remaining
    - v_offer.proposer_credits
    + v_offer.recipient_credits;

  v_recipient_final_credits :=
    v_recipient.credits_remaining
    - v_offer.recipient_credits
    + v_offer.proposer_credits;

  if v_proposer_final_credits < 0 or v_recipient_final_credits < 0 then
    raise exception 'Una delle squadre non ha più i crediti promessi.';
  end if;

  select coalesce(sum(reservation.amount), 0)::integer
  into v_proposer_other_reserved
  from public.trade_credit_reservations reservation
  where reservation.fantasy_team_id = v_proposer.id
    and reservation.trade_offer_id <> v_offer.id
    and not exists (
      select 1
      from public.trade_offer_players current_player
      join public.trade_offer_players reserved_player
        on reserved_player.athlete_id = current_player.athlete_id
      where current_player.trade_offer_id = v_offer.id
        and reserved_player.trade_offer_id = reservation.trade_offer_id
    );

  select coalesce(sum(reservation.amount), 0)::integer
  into v_recipient_reserved
  from public.trade_credit_reservations reservation
  where reservation.fantasy_team_id = v_recipient.id
    and reservation.trade_offer_id <> v_offer.id
    and not exists (
      select 1
      from public.trade_offer_players current_player
      join public.trade_offer_players reserved_player
        on reserved_player.athlete_id = current_player.athlete_id
      where current_player.trade_offer_id = v_offer.id
        and reserved_player.trade_offer_id = reservation.trade_offer_id
    );

  v_minimum_price := greatest(
    coalesce((v_league.scoring_rules ->> 'market_min_price')::integer, 1),
    1
  );

  v_proposer_required_reserve := greatest(
    v_league.roster_size
      - (v_proposer_count - v_offered_count + v_requested_count),
    0
  ) * v_minimum_price;

  v_recipient_required_reserve := greatest(
    v_league.roster_size
      - (v_recipient_count - v_requested_count + v_offered_count),
    0
  ) * v_minimum_price;

  if v_proposer_final_credits
      < v_proposer_required_reserve + v_proposer_other_reserved then
    raise exception
      'La squadra proponente non conserverebbe abbastanza crediti.';
  end if;

  if v_recipient_final_credits
      < v_recipient_required_reserve + v_recipient_reserved then
    raise exception
      'La squadra destinataria non conserverebbe abbastanza crediti.';
  end if;
end;
$$;

revoke all on function public.assert_trade_offer_safe(uuid) from public;

create or replace function public.guard_trade_offer_projection()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_offer_id uuid;
begin
  v_offer_id := case
    when tg_op = 'DELETE' then old.trade_offer_id
    else new.trade_offer_id
  end;

  if not exists (
    select 1
    from public.trade_offers offer
    where offer.id = v_offer_id
  ) then
    return null;
  end if;

  perform public.assert_trade_offer_safe(v_offer_id);
  return null;
end;
$$;

revoke all on function public.guard_trade_offer_projection() from public;

drop trigger if exists trade_offer_projection_guard
on public.trade_offer_players;

create constraint trigger trade_offer_projection_guard
after insert or update or delete on public.trade_offer_players
deferrable initially deferred
for each row execute function public.guard_trade_offer_projection();

-- 6) Il trigger che annulla le offerte obsolete ignora la trattativa che
--    sta venendo eseguita nella stessa transazione.
create or replace function public.cancel_stale_trade_offers_on_roster_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_active_offer_id uuid;
begin
  begin
    v_active_offer_id := nullif(
      current_setting('leghevo.trade_offer_in_progress', true),
      ''
    )::uuid;
  exception
    when invalid_text_representation then
      v_active_offer_id := null;
  end;

  if old.released_at is null and new.released_at is not null then
    update public.trade_offers offer
    set
      status = 'canceled',
      responded_at = coalesce(offer.responded_at, now())
    where offer.status = 'pending'
      and offer.id is distinct from v_active_offer_id
      and exists (
        select 1
        from public.trade_offer_players offered_player
        where offered_player.trade_offer_id = offer.id
          and offered_player.fantasy_team_id = old.fantasy_team_id
          and offered_player.athlete_id = old.athlete_id
      );
  end if;

  return new;
end;
$$;

revoke all on function public.cancel_stale_trade_offers_on_roster_change()
from public;

-- 7) Operazioni di scambio serializzate per lega, così due dispositivi non
--    possono creare deadlock tra squadra, offerta e rosa.
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
  v_league_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Devi effettuare l''accesso.';
  end if;

  select team.league_id
  into v_league_id
  from public.fantasy_teams team
  where team.id = p_proposer_team_id;

  if not found then
    raise exception 'Squadra proponente non trovata.';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('market:' || v_league_id::text, 0)
  );

  perform team.id
  from public.fantasy_teams team
  where team.id in (p_proposer_team_id, p_recipient_team_id)
  order by team.id
  for update;

  select team.*
  into v_proposer
  from public.fantasy_teams team
  where team.id = p_proposer_team_id;

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

  update public.trade_offers offer
  set
    status = 'expired',
    responded_at = coalesce(offer.responded_at, now())
  where offer.league_id = v_league.id
    and offer.status = 'pending'
    and offer.expires_at <= now();

  if p_proposer_credits < 0 or p_recipient_credits < 0 then
    raise exception 'I crediti inseriti non possono essere negativi.';
  end if;

  if length(coalesce(p_message, '')) > 180 then
    raise exception 'Il messaggio può contenere al massimo 180 caratteri.';
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

  if exists (
    select 1
    from public.trade_player_reservations reservation
    where reservation.fantasy_team_id = v_proposer.id
      and reservation.athlete_id = any(
        coalesce(p_offered_player_ids, array[]::uuid[])
      )
  ) then
    raise exception
      'Uno dei calciatori offerti è già impegnato in un''altra proposta.';
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

  perform public.assert_trade_offer_safe(v_offer.id);

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
  v_league_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Devi effettuare l''accesso.';
  end if;

  select offer.league_id
  into v_league_id
  from public.trade_offers offer
  where offer.id = p_trade_offer_id;

  if not found then
    raise exception 'Proposta di scambio non trovata.';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('market:' || v_league_id::text, 0)
  );

  select offer.*
  into v_offer
  from public.trade_offers offer
  where offer.id = p_trade_offer_id
  for update;

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
  v_offered_count integer;
  v_requested_count integer;
  v_audit_athlete_id uuid;
  v_league_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Devi effettuare l''accesso.';
  end if;

  select offer.league_id
  into v_league_id
  from public.trade_offers offer
  where offer.id = p_trade_offer_id;

  if not found then
    raise exception 'Proposta di scambio non trovata.';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('market:' || v_league_id::text, 0)
  );

  select offer.*
  into v_offer
  from public.trade_offers offer
  where offer.id = p_trade_offer_id
  for update;

  if v_offer.status <> 'pending' then
    raise exception 'Questa proposta non è più disponibile.';
  end if;

  if v_offer.expires_at <= now() then
    update public.trade_offers
    set status = 'expired', responded_at = now()
    where id = v_offer.id
    returning * into v_offer;
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

  perform public.assert_trade_offer_safe(v_offer.id);

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

  -- Le proposte concorrenti vengono chiuse prima di muovere le rose.
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

  perform set_config(
    'leghevo.trade_offer_in_progress',
    v_offer.id::text,
    true
  );

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

  perform public.assert_team_roster_quotas(v_proposer.id);
  perform public.assert_team_roster_quotas(v_recipient.id);

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
      jsonb_build_object(
        'trade_offer_id', v_offer.id,
        'integrity_version', 2,
        'offered_players', v_offered_count,
        'requested_players', v_requested_count
      )
    ),
    (
      v_offer.league_id,
      v_recipient.id,
      v_audit_athlete_id,
      'trade',
      v_offer.proposer_credits - v_offer.recipient_credits,
      jsonb_build_object(
        'trade_offer_id', v_offer.id,
        'integrity_version', 2,
        'offered_players', v_requested_count,
        'requested_players', v_offered_count
      )
    );

  update public.trade_offers
  set status = 'accepted', responded_at = now()
  where id = v_offer.id
  returning * into v_offer;

  perform set_config('leghevo.trade_offer_in_progress', '', true);

  return v_offer;
end;
$$;

-- Svincolo serializzato con le trattative della stessa lega.
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
  v_league_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Devi effettuare l''accesso.';
  end if;

  select team.league_id
  into v_league_id
  from public.fantasy_teams team
  where team.id = p_fantasy_team_id;

  if not found then
    raise exception 'Squadra non trovata.';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('market:' || v_league_id::text, 0)
  );

  select team.*
  into v_team
  from public.fantasy_teams team
  where team.id = p_fantasy_team_id
  for update;

  if v_team.manager_id <> auth.uid()
    and not public.is_league_admin(v_team.league_id) then
    raise exception 'Puoi svincolare soltanto dalla tua squadra.';
  end if;

  select league.*
  into v_league
  from public.leagues league
  where league.id = v_team.league_id;

  if v_league.status in ('completed', 'archived')
    or coalesce(v_league.scoring_rules ->> 'market_open', 'true') = 'false'
  then
    raise exception 'Il mercato di questa lega è chiuso.';
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
      'refund_percent', v_refund_percent,
      'integrity_version', 2
    )
  );

  return v_refund;
end;
$$;

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
revoke all on function public.release_roster_player(uuid, uuid) from public;

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
grant execute on function public.release_roster_player(uuid, uuid)
to authenticated;

-- 8) Diagnostica estesa per prenotazioni, crediti e proiezioni.
create or replace function public.get_league_market_integrity_v2(
  p_league_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_base jsonb;
  v_orphan_player_reservations integer;
  v_orphan_credit_reservations integer;
  v_overcommitted_teams integer;
  v_invalid_projected_trades integer := 0;
  v_reserved_credits integer;
  v_pending_offers integer;
  v_offer record;
  v_additional_issues integer;
begin
  if auth.uid() is null then
    raise exception 'Devi effettuare l''accesso.';
  end if;

  if not public.is_league_member(p_league_id) then
    raise exception 'Non fai parte di questa lega.';
  end if;

  v_base := public.get_league_market_integrity_v1(p_league_id);

  select count(*)::integer
  into v_orphan_player_reservations
  from public.trade_player_reservations reservation
  left join public.trade_offers offer
    on offer.id = reservation.trade_offer_id
  left join public.trade_offer_players player
    on player.trade_offer_id = reservation.trade_offer_id
   and player.athlete_id = reservation.athlete_id
   and player.fantasy_team_id = reservation.fantasy_team_id
  where reservation.league_id = p_league_id
    and (
      offer.id is null
      or offer.status <> 'pending'
      or player.trade_offer_id is null
      or reservation.fantasy_team_id <> offer.proposer_team_id
    );

  select count(*)::integer
  into v_orphan_credit_reservations
  from public.trade_credit_reservations reservation
  left join public.trade_offers offer
    on offer.id = reservation.trade_offer_id
  where reservation.league_id = p_league_id
    and (
      offer.id is null
      or offer.status <> 'pending'
      or reservation.fantasy_team_id <> offer.proposer_team_id
      or reservation.amount <> offer.proposer_credits
    );

  select count(*)::integer
  into v_overcommitted_teams
  from public.fantasy_teams team
  where team.league_id = p_league_id
    and team.credits_remaining < coalesce((
      select sum(reservation.amount)
      from public.trade_credit_reservations reservation
      where reservation.fantasy_team_id = team.id
    ), 0);

  for v_offer in
    select offer.id
    from public.trade_offers offer
    where offer.league_id = p_league_id
      and offer.status = 'pending'
      and offer.expires_at > now()
  loop
    begin
      perform public.assert_trade_offer_safe(v_offer.id);
    exception
      when others then
        v_invalid_projected_trades := v_invalid_projected_trades + 1;
    end;
  end loop;

  select
    coalesce(sum(reservation.amount), 0)::integer,
    count(distinct reservation.trade_offer_id)::integer
  into v_reserved_credits, v_pending_offers
  from public.trade_credit_reservations reservation
  where reservation.league_id = p_league_id;

  v_additional_issues :=
    v_orphan_player_reservations
    + v_orphan_credit_reservations
    + v_overcommitted_teams
    + v_invalid_projected_trades;

  return v_base || jsonb_build_object(
    'version', 2,
    'ok', coalesce((v_base ->> 'ok')::boolean, false)
      and v_additional_issues = 0,
    'issueCount', coalesce((v_base ->> 'issueCount')::integer, 0)
      + v_additional_issues,
    'tradeSafetyEnabled', true,
    'pendingReservedOffers', v_pending_offers,
    'reservedTradeCredits', v_reserved_credits,
    'orphanPlayerReservations', v_orphan_player_reservations,
    'orphanCreditReservations', v_orphan_credit_reservations,
    'overcommittedTradeTeams', v_overcommitted_teams,
    'invalidProjectedTrades', v_invalid_projected_trades
  );
end;
$$;

revoke all on function public.get_league_market_integrity_v2(uuid)
from public;
grant execute on function public.get_league_market_integrity_v2(uuid)
to authenticated;

commit;

-- Controllo finale: attesi 16 valori true.
select
  to_regclass(
    'public.trade_player_reservations'
  ) is not null as player_reservations_ready,
  to_regclass(
    'public.trade_credit_reservations'
  ) is not null as credit_reservations_ready,
  exists (
    select 1
    from pg_trigger trigger_row
    where trigger_row.tgrelid = 'public.trade_offers'::regclass
      and trigger_row.tgname = 'trade_offer_reservations_sync'
      and not trigger_row.tgisinternal
  ) as offer_reservation_trigger_ready,
  exists (
    select 1
    from pg_trigger trigger_row
    where trigger_row.tgrelid = 'public.trade_offer_players'::regclass
      and trigger_row.tgname = 'trade_player_reservation_sync'
      and not trigger_row.tgisinternal
  ) as player_reservation_trigger_ready,
  exists (
    select 1
    from pg_trigger trigger_row
    where trigger_row.tgrelid = 'public.trade_credit_reservations'::regclass
      and trigger_row.tgname = 'trade_credit_reservation_guard'
      and not trigger_row.tgisinternal
  ) as credit_reservation_guard_ready,
  exists (
    select 1
    from pg_trigger trigger_row
    where trigger_row.tgrelid = 'public.trade_offer_players'::regclass
      and trigger_row.tgname = 'trade_offer_projection_guard'
      and not trigger_row.tgisinternal
  ) as projection_guard_ready,
  to_regprocedure(
    'public.assert_trade_offer_safe(uuid)'
  ) is not null as trade_projection_ready,
  to_regprocedure(
    'public.create_trade_offer(uuid,uuid,uuid[],uuid[],integer,integer,text)'
  ) is not null as protected_trade_creation_ready,
  to_regprocedure(
    'public.respond_trade_offer(uuid,boolean)'
  ) is not null as protected_trade_response_ready,
  to_regprocedure(
    'public.cancel_trade_offer(uuid)'
  ) is not null as protected_trade_cancel_ready,
  to_regprocedure(
    'public.release_roster_player(uuid,uuid)'
  ) is not null as serialized_release_ready,
  to_regprocedure(
    'public.get_league_market_integrity_v2(uuid)'
  ) is not null as trade_diagnostics_v2_ready,
  not exists (
    select 1
    from public.trade_player_reservations reservation
    group by reservation.fantasy_team_id, reservation.athlete_id
    having count(*) > 1
  ) as no_duplicate_player_commitments,
  not exists (
    select 1
    from public.trade_player_reservations reservation
    left join public.trade_offers offer
      on offer.id = reservation.trade_offer_id
    where offer.id is null or offer.status <> 'pending'
  ) as no_orphan_player_reservations,
  not exists (
    select 1
    from public.trade_credit_reservations reservation
    left join public.trade_offers offer
      on offer.id = reservation.trade_offer_id
    where offer.id is null
      or offer.status <> 'pending'
      or reservation.amount <> offer.proposer_credits
  ) as no_orphan_credit_reservations,
  not exists (
    select 1
    from public.fantasy_teams team
    where team.credits_remaining < coalesce((
      select sum(reservation.amount)
      from public.trade_credit_reservations reservation
      where reservation.fantasy_team_id = team.id
    ), 0)
  ) as no_overcommitted_trade_credits;
