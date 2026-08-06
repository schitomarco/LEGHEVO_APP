-- LEGHEVO · integrità rosa, crediti e mercato
-- Versione applicativa: 0.57.1
-- Eseguire dopo 065_role_model_closure.sql.
-- Script idempotente: può essere eseguito più volte senza duplicare oggetti.

begin;

-- 1) Indici utili per i controlli e per le operazioni atomiche.
create index if not exists roster_entries_team_active_idx
  on public.roster_entries (fantasy_team_id, acquired_at)
  where released_at is null;

create index if not exists team_transactions_team_created_idx
  on public.team_transactions (fantasy_team_id, created_at, id);

create index if not exists trade_offer_players_athlete_offer_idx
  on public.trade_offer_players (athlete_id, trade_offer_id);

-- 2) I crediti di una squadra non possono mai diventare negativi.
do $$
begin
  if exists (
    select 1
    from public.fantasy_teams team
    where team.credits_remaining < 0
  ) then
    raise exception
      'Sono presenti squadre con crediti negativi. Correggere i dati prima di applicare la protezione.';
  end if;

  if not exists (
    select 1
    from pg_constraint constraint_row
    where constraint_row.conrelid = 'public.fantasy_teams'::regclass
      and constraint_row.conname = 'fantasy_teams_credits_nonnegative'
  ) then
    alter table public.fantasy_teams
      add constraint fantasy_teams_credits_nonnegative
      check (credits_remaining >= 0) not valid;
  end if;

  alter table public.fantasy_teams
    validate constraint fantasy_teams_credits_nonnegative;
end;
$$;

-- 3) Coerenza tra lega, squadra e movimenti.
create or replace function public.guard_roster_row_consistency()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_team public.fantasy_teams%rowtype;
  v_league public.leagues%rowtype;
  v_active_count integer;
begin
  select team.*
  into v_team
  from public.fantasy_teams team
  where team.id = new.fantasy_team_id
  for key share;

  if not found then
    raise exception 'Squadra non trovata.';
  end if;

  if new.league_id is distinct from v_team.league_id then
    raise exception
      'La squadra e il calciatore appartengono a leghe diverse.';
  end if;

  if new.released_at is null then
    select league.*
    into v_league
    from public.leagues league
    where league.id = v_team.league_id;

    -- Serializza anche eventuali inserimenti diretti non passati dalle RPC.
    perform pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtextextended('roster:' || v_team.id::text, 0)
    );

    select count(*)::integer
    into v_active_count
    from public.roster_entries roster
    where roster.fantasy_team_id = v_team.id
      and roster.released_at is null
      and roster.id <> new.id;

    if v_active_count >= v_league.roster_size then
      raise exception
        'Rosa completa: massimo % calciatori.',
        v_league.roster_size;
    end if;
  end if;

  return new;
end;
$$;

create or replace function public.guard_transaction_row_consistency()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_team public.fantasy_teams%rowtype;
begin
  select team.*
  into v_team
  from public.fantasy_teams team
  where team.id = new.fantasy_team_id
  for key share;

  if not found then
    raise exception 'Squadra non trovata.';
  end if;

  if new.league_id is distinct from v_team.league_id then
    raise exception
      'La squadra e il movimento crediti appartengono a leghe diverse.';
  end if;

  return new;
end;
$$;

revoke all on function public.guard_roster_row_consistency() from public;
revoke all on function public.guard_transaction_row_consistency() from public;

drop trigger if exists roster_market_consistency_guard
on public.roster_entries;

create trigger roster_market_consistency_guard
before insert or update of league_id, fantasy_team_id, released_at
on public.roster_entries
for each row execute function public.guard_roster_row_consistency();

drop trigger if exists transaction_market_consistency_guard
on public.team_transactions;

create trigger transaction_market_consistency_guard
before insert or update of league_id, fantasy_team_id
on public.team_transactions
for each row execute function public.guard_transaction_row_consistency();

-- 4) Qualunque uscita di un calciatore dalla rosa annulla automaticamente
--    le proposte ancora pendenti che lo contengono.
create or replace function public.cancel_stale_trade_offers_on_roster_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.released_at is null and new.released_at is not null then
    update public.trade_offers offer
    set
      status = 'canceled',
      responded_at = coalesce(offer.responded_at, now())
    where offer.status = 'pending'
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

drop trigger if exists roster_cancel_stale_trade_offers
on public.roster_entries;

create trigger roster_cancel_stale_trade_offers
after update of released_at on public.roster_entries
for each row execute function public.cancel_stale_trade_offers_on_roster_change();

-- 5) Crediti minimi necessari per completare la rosa con il prezzo minimo
--    del mercato. Serve per impedire squadre tecnicamente non completabili.
create or replace function public.team_minimum_roster_reserve(
  p_fantasy_team_id uuid,
  p_roster_delta integer default 0
)
returns integer
language plpgsql
security definer
stable
set search_path = ''
as $$
declare
  v_team public.fantasy_teams%rowtype;
  v_league public.leagues%rowtype;
  v_roster_count integer;
  v_minimum_price integer;
begin
  select team.*
  into v_team
  from public.fantasy_teams team
  where team.id = p_fantasy_team_id;

  if not found then
    raise exception 'Squadra non trovata.';
  end if;

  select league.*
  into v_league
  from public.leagues league
  where league.id = v_team.league_id;

  select count(*)::integer
  into v_roster_count
  from public.roster_entries roster
  where roster.fantasy_team_id = v_team.id
    and roster.released_at is null;

  v_minimum_price := greatest(
    coalesce((v_league.scoring_rules ->> 'market_min_price')::integer, 1),
    1
  );

  return greatest(
    v_league.roster_size - (v_roster_count + p_roster_delta),
    0
  ) * v_minimum_price;
end;
$$;

revoke all on function public.team_minimum_roster_reserve(uuid, integer)
from public;
grant execute on function public.team_minimum_roster_reserve(uuid, integer)
to authenticated;

-- 6) Acquisto libero irrobustito: oltre a disponibilità, quota ruolo e
--    capienza, protegge i crediti necessari per completare la rosa.
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
  v_required_reserve integer;
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
    raise exception 'Il Presidente ha chiuso il mercato.';
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

  perform public.assert_team_can_add_athlete(v_team.id, p_athlete_id);

  v_price := greatest(
    coalesce((v_league.scoring_rules ->> 'market_min_price')::integer, 1),
    1
  );
  v_required_reserve := public.team_minimum_roster_reserve(v_team.id, 1);

  if v_team.credits_remaining < v_price then
    raise exception 'Crediti insufficienti per completare l''acquisto.';
  end if;

  if v_team.credits_remaining - v_price < v_required_reserve then
    raise exception
      'Devi conservare almeno % crediti per completare i posti liberi della rosa.',
      v_required_reserve;
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
    jsonb_build_object(
      'source', 'free_agent_market',
      'integrity_version', 1
    )
  );

  return v_result;
end;
$$;

revoke all on function public.sign_free_agent(uuid, uuid) from public;
grant execute on function public.sign_free_agent(uuid, uuid) to authenticated;

-- 7) Diagnostica unica per crediti, rose e proposte di scambio.
create or replace function public.get_league_market_integrity_v1(
  p_league_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_league public.leagues%rowtype;
  v_duplicate_players integer;
  v_roster_mismatches integer;
  v_transaction_mismatches integer;
  v_invalid_pending_trades integer;
  v_expired_offers integer;
  v_teams jsonb;
  v_issue_count integer;
begin
  if auth.uid() is null then
    raise exception 'Devi effettuare l''accesso.';
  end if;

  if not public.is_league_member(p_league_id) then
    raise exception 'Non fai parte di questa lega.';
  end if;

  select league.*
  into v_league
  from public.leagues league
  where league.id = p_league_id;

  if not found then
    raise exception 'Lega non trovata.';
  end if;

  update public.trade_offers offer
  set
    status = 'expired',
    responded_at = coalesce(offer.responded_at, now())
  where offer.league_id = p_league_id
    and offer.status = 'pending'
    and offer.expires_at <= now();

  get diagnostics v_expired_offers = row_count;

  select count(*)::integer
  into v_duplicate_players
  from (
    select roster.athlete_id
    from public.roster_entries roster
    where roster.league_id = p_league_id
      and roster.released_at is null
    group by roster.athlete_id
    having count(*) > 1
  ) duplicate_player;

  select count(*)::integer
  into v_roster_mismatches
  from public.roster_entries roster
  join public.fantasy_teams team on team.id = roster.fantasy_team_id
  where roster.league_id = p_league_id
    and roster.league_id is distinct from team.league_id;

  select count(*)::integer
  into v_transaction_mismatches
  from public.team_transactions transaction_row
  join public.fantasy_teams team
    on team.id = transaction_row.fantasy_team_id
  where transaction_row.league_id = p_league_id
    and transaction_row.league_id is distinct from team.league_id;

  select count(*)::integer
  into v_invalid_pending_trades
  from public.trade_offers offer
  where offer.league_id = p_league_id
    and offer.status = 'pending'
    and (
      not exists (
        select 1
        from public.fantasy_teams proposer
        where proposer.id = offer.proposer_team_id
          and proposer.league_id = offer.league_id
      )
      or not exists (
        select 1
        from public.fantasy_teams recipient
        where recipient.id = offer.recipient_team_id
          and recipient.league_id = offer.league_id
      )
      or exists (
        select 1
        from public.trade_offer_players offer_player
        where offer_player.trade_offer_id = offer.id
          and not exists (
            select 1
            from public.roster_entries roster
            where roster.fantasy_team_id = offer_player.fantasy_team_id
              and roster.athlete_id = offer_player.athlete_id
              and roster.released_at is null
          )
      )
    );

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'teamId', team_state.team_id,
        'teamName', team_state.team_name,
        'creditsRemaining', team_state.credits_remaining,
        'expectedCredits', team_state.expected_credits,
        'creditDifference',
          team_state.credits_remaining - team_state.expected_credits,
        'creditOk',
          team_state.credits_remaining = team_state.expected_credits
          and team_state.credits_remaining >= 0,
        'rosterCount', team_state.roster_count,
        'rosterSize', v_league.roster_size,
        'rosterOk', team_state.roster_count <= v_league.roster_size,
        'minimumReserve', team_state.minimum_reserve,
        'reserveOk',
          team_state.credits_remaining >= team_state.minimum_reserve,
        'transactionCount', team_state.transaction_count
      )
      order by team_state.team_name
    ),
    '[]'::jsonb
  )
  into v_teams
  from (
    select
      team.id as team_id,
      team.name as team_name,
      team.credits_remaining,
      (
        v_league.starting_credits
        + coalesce(transaction_state.credit_delta, 0)
      )::integer as expected_credits,
      coalesce(roster_state.roster_count, 0)::integer as roster_count,
      public.team_minimum_roster_reserve(team.id, 0) as minimum_reserve,
      coalesce(transaction_state.transaction_count, 0)::integer
        as transaction_count
    from public.fantasy_teams team
    left join lateral (
      select count(*)::integer as roster_count
      from public.roster_entries roster
      where roster.fantasy_team_id = team.id
        and roster.released_at is null
    ) roster_state on true
    left join lateral (
      select
        coalesce(sum(transaction_row.credit_delta), 0)::integer
          as credit_delta,
        count(*)::integer as transaction_count
      from public.team_transactions transaction_row
      where transaction_row.fantasy_team_id = team.id
    ) transaction_state on true
    where team.league_id = p_league_id
  ) team_state;

  select
    v_duplicate_players
    + v_roster_mismatches
    + v_transaction_mismatches
    + v_invalid_pending_trades
    + coalesce(sum(
        case
          when (team_item ->> 'creditOk')::boolean
            and (team_item ->> 'rosterOk')::boolean
            and (team_item ->> 'reserveOk')::boolean
          then 0
          else 1
        end
      ), 0)::integer
  into v_issue_count
  from jsonb_array_elements(v_teams) team_item;

  return jsonb_build_object(
    'version', 1,
    'leagueId', p_league_id,
    'checkedAt', now(),
    'ok', v_issue_count = 0,
    'issueCount', v_issue_count,
    'expiredOffersClosed', v_expired_offers,
    'duplicateActivePlayers', v_duplicate_players,
    'rosterLeagueMismatches', v_roster_mismatches,
    'transactionLeagueMismatches', v_transaction_mismatches,
    'invalidPendingTrades', v_invalid_pending_trades,
    'teams', v_teams
  );
end;
$$;

revoke all on function public.get_league_market_integrity_v1(uuid)
from public;
grant execute on function public.get_league_market_integrity_v1(uuid)
to authenticated;

commit;

-- Controllo finale: attesi 14 valori true.
select
  exists (
    select 1
    from pg_constraint constraint_row
    where constraint_row.conrelid = 'public.fantasy_teams'::regclass
      and constraint_row.conname = 'fantasy_teams_credits_nonnegative'
      and constraint_row.convalidated
  ) as credits_constraint_ready,
  (
    to_regprocedure(
      'public.guard_roster_row_consistency()'
    ) is not null
    and to_regprocedure(
      'public.guard_transaction_row_consistency()'
    ) is not null
  ) as consistency_guards_ready,
  exists (
    select 1
    from pg_trigger trigger_row
    where trigger_row.tgrelid = 'public.roster_entries'::regclass
      and trigger_row.tgname = 'roster_market_consistency_guard'
      and not trigger_row.tgisinternal
  ) as roster_guard_ready,
  exists (
    select 1
    from pg_trigger trigger_row
    where trigger_row.tgrelid = 'public.team_transactions'::regclass
      and trigger_row.tgname = 'transaction_market_consistency_guard'
      and not trigger_row.tgisinternal
  ) as transaction_guard_ready,
  exists (
    select 1
    from pg_trigger trigger_row
    where trigger_row.tgrelid = 'public.roster_entries'::regclass
      and trigger_row.tgname = 'roster_cancel_stale_trade_offers'
      and not trigger_row.tgisinternal
  ) as stale_trade_guard_ready,
  to_regprocedure(
    'public.team_minimum_roster_reserve(uuid,integer)'
  ) is not null as reserve_engine_ready,
  to_regprocedure(
    'public.sign_free_agent(uuid,uuid)'
  ) is not null as protected_market_purchase_ready,
  to_regprocedure(
    'public.get_league_market_integrity_v1(uuid)'
  ) is not null as market_diagnostics_ready,
  to_regclass(
    'public.roster_entries_team_active_idx'
  ) is not null as roster_index_ready,
  to_regclass(
    'public.team_transactions_team_created_idx'
  ) is not null as transaction_index_ready,
  not exists (
    select 1
    from public.fantasy_teams team
    where team.credits_remaining < 0
  ) as no_negative_credits,
  not exists (
    select 1
    from public.roster_entries roster
    join public.fantasy_teams team on team.id = roster.fantasy_team_id
    where roster.league_id is distinct from team.league_id
  ) as roster_league_consistent,
  not exists (
    select 1
    from public.team_transactions transaction_row
    join public.fantasy_teams team
      on team.id = transaction_row.fantasy_team_id
    where transaction_row.league_id is distinct from team.league_id
  ) as transaction_league_consistent,
  not exists (
    select 1
    from public.roster_entries roster
    join public.fantasy_teams team on team.id = roster.fantasy_team_id
    join public.leagues league on league.id = team.league_id
    where roster.released_at is null
    group by team.id, league.roster_size
    having count(*) > league.roster_size
  ) as roster_limits_respected;
