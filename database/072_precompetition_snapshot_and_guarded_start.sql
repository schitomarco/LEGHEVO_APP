-- LEGHEVO · congelamento pre-campionato e avvio protetto
-- Versione applicativa: 0.58.2
-- Eseguire dopo 071_competition_readiness_and_guarded_calendar.sql.
-- Script idempotente: può essere eseguito più volte.

begin;

alter table public.leagues
  add column if not exists calendar_snapshot_locked_at timestamptz,
  add column if not exists competition_started_by uuid,
  add column if not exists competition_start_fingerprint text,
  add column if not exists competition_integrity_verified_at timestamptz,
  add column if not exists competition_start_version smallint;

alter table public.leagues
  drop constraint if exists leagues_competition_start_version_check;
alter table public.leagues
  add constraint leagues_competition_start_version_check
  check (
    competition_start_version is null
    or competition_start_version >= 1
  );

-- La fotografia della competizione deve rappresentare soltanto gli elementi
-- strutturali e sportivi. Le promozioni Admin non devono invalidare il sorteggio.
create or replace function public.compute_league_competition_fingerprint(
  p_league_id uuid
)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_fingerprint text;
begin
  select md5(
    jsonb_build_object(
      'league', jsonb_build_object(
        'id', league.id,
        'teamLimit', league.team_limit,
        'rosterSize', league.roster_size,
        'startingCredits', league.starting_credits,
        'mode', league.mode
      ),
      'members', coalesce((
        select jsonb_agg(member.user_id order by member.user_id)
        from public.league_members member
        where member.league_id = league.id
      ), '[]'::jsonb),
      'teams', coalesce((
        select jsonb_agg(
          jsonb_build_object(
            'teamId', team.id,
            'managerId', team.manager_id,
            'credits', team.credits_remaining,
            'roster', coalesce((
              select jsonb_agg(
                jsonb_build_object(
                  'athleteId', roster.athlete_id,
                  'price', roster.purchase_price
                )
                order by roster.athlete_id
              )
              from public.roster_entries roster
              where roster.fantasy_team_id = team.id
                and roster.released_at is null
            ), '[]'::jsonb)
          )
          order by team.id
        )
        from public.fantasy_teams team
        where team.league_id = league.id
      ), '[]'::jsonb)
    )::text
  )
  into v_fingerprint
  from public.leagues league
  where league.id = p_league_id;

  if v_fingerprint is null then
    raise exception 'Lega non trovata.';
  end if;

  return v_fingerprint;
end;
$$;

create or replace function public.is_league_precompetition_snapshot_locked(
  p_league_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.leagues league
    where league.id = p_league_id
      and league.competition_started_at is null
      and league.calendar_roster_fingerprint is not null
      and exists (
        select 1
        from public.fantasy_fixtures fixture
        where fixture.league_id = league.id
      )
  );
$$;

create or replace function public.raise_precompetition_snapshot_locked()
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  raise exception
    'Il calendario è già stato sorteggiato. Annullalo prima di modificare rose, crediti, squadre, partecipanti, scambi o asta.';
end;
$$;

create or replace function public.guard_roster_precompetition_snapshot()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_league_id uuid;
begin
  if tg_op = 'DELETE' then
    v_league_id := old.league_id;
  else
    v_league_id := new.league_id;
  end if;
  if public.is_league_precompetition_snapshot_locked(v_league_id) then
    perform public.raise_precompetition_snapshot_locked();
  end if;
  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

create or replace function public.guard_team_precompetition_snapshot()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_league_id uuid;
  v_structural_change boolean := true;
begin
  if tg_op = 'DELETE' then
    v_league_id := old.league_id;
  else
    v_league_id := new.league_id;
  end if;
  if tg_op = 'UPDATE' then
    v_structural_change :=
      new.league_id is distinct from old.league_id
      or new.manager_id is distinct from old.manager_id
      or new.credits_remaining is distinct from old.credits_remaining;
  end if;

  if v_structural_change
    and public.is_league_precompetition_snapshot_locked(v_league_id) then
    perform public.raise_precompetition_snapshot_locked();
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

create or replace function public.guard_member_precompetition_snapshot()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_league_id uuid;
  v_structural_change boolean := true;
begin
  if tg_op = 'DELETE' then
    v_league_id := old.league_id;
  else
    v_league_id := new.league_id;
  end if;
  if tg_op = 'UPDATE' then
    -- Il ruolo può cambiare senza alterare squadre, rose o calendario.
    v_structural_change :=
      new.league_id is distinct from old.league_id
      or new.user_id is distinct from old.user_id;
  end if;

  if v_structural_change
    and public.is_league_precompetition_snapshot_locked(v_league_id) then
    perform public.raise_precompetition_snapshot_locked();
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

create or replace function public.guard_transaction_precompetition_snapshot()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_league_id uuid;
begin
  if tg_op = 'DELETE' then
    v_league_id := old.league_id;
  else
    v_league_id := new.league_id;
  end if;
  if public.is_league_precompetition_snapshot_locked(v_league_id) then
    perform public.raise_precompetition_snapshot_locked();
  end if;
  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

create or replace function public.guard_trade_precompetition_snapshot()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_league_id uuid;
begin
  if tg_op = 'DELETE' then
    v_league_id := old.league_id;
  else
    v_league_id := new.league_id;
  end if;
  if public.is_league_precompetition_snapshot_locked(v_league_id) then
    perform public.raise_precompetition_snapshot_locked();
  end if;
  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

create or replace function public.guard_trade_player_precompetition_snapshot()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_offer_id uuid;
  v_league_id uuid;
begin
  if tg_op = 'DELETE' then
    v_offer_id := old.trade_offer_id;
  else
    v_offer_id := new.trade_offer_id;
  end if;
  select offer.league_id
  into v_league_id
  from public.trade_offers offer
  where offer.id = v_offer_id;

  if v_league_id is not null
    and public.is_league_precompetition_snapshot_locked(v_league_id) then
    perform public.raise_precompetition_snapshot_locked();
  end if;
  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

create or replace function public.guard_auction_precompetition_snapshot()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_league_id uuid;
begin
  if tg_op = 'DELETE' then
    v_league_id := old.league_id;
  else
    v_league_id := new.league_id;
  end if;
  if public.is_league_precompetition_snapshot_locked(v_league_id) then
    perform public.raise_precompetition_snapshot_locked();
  end if;
  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

create or replace function public.guard_auction_item_precompetition_snapshot()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_auction_id uuid;
  v_league_id uuid;
begin
  if tg_op = 'DELETE' then
    v_auction_id := old.auction_id;
  else
    v_auction_id := new.auction_id;
  end if;
  select auction.league_id
  into v_league_id
  from public.auctions auction
  where auction.id = v_auction_id;

  if v_league_id is not null
    and public.is_league_precompetition_snapshot_locked(v_league_id) then
    perform public.raise_precompetition_snapshot_locked();
  end if;
  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

create or replace function public.guard_bid_precompetition_snapshot()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_item_id uuid;
  v_league_id uuid;
begin
  if tg_op = 'DELETE' then
    v_item_id := old.auction_item_id;
  else
    v_item_id := new.auction_item_id;
  end if;
  select auction.league_id
  into v_league_id
  from public.auction_items item
  join public.auctions auction on auction.id = item.auction_id
  where item.id = v_item_id;

  if v_league_id is not null
    and public.is_league_precompetition_snapshot_locked(v_league_id) then
    perform public.raise_precompetition_snapshot_locked();
  end if;
  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

drop trigger if exists roster_precompetition_snapshot_guard
on public.roster_entries;
create trigger roster_precompetition_snapshot_guard
before insert or update or delete on public.roster_entries
for each row execute function public.guard_roster_precompetition_snapshot();

drop trigger if exists team_precompetition_snapshot_guard
on public.fantasy_teams;
create trigger team_precompetition_snapshot_guard
before insert or update or delete on public.fantasy_teams
for each row execute function public.guard_team_precompetition_snapshot();

drop trigger if exists member_precompetition_snapshot_guard
on public.league_members;
create trigger member_precompetition_snapshot_guard
before insert or update or delete on public.league_members
for each row execute function public.guard_member_precompetition_snapshot();

drop trigger if exists transaction_precompetition_snapshot_guard
on public.team_transactions;
create trigger transaction_precompetition_snapshot_guard
before insert or update or delete on public.team_transactions
for each row execute function public.guard_transaction_precompetition_snapshot();

drop trigger if exists trade_precompetition_snapshot_guard
on public.trade_offers;
create trigger trade_precompetition_snapshot_guard
before insert or update or delete on public.trade_offers
for each row execute function public.guard_trade_precompetition_snapshot();

drop trigger if exists trade_player_precompetition_snapshot_guard
on public.trade_offer_players;
create trigger trade_player_precompetition_snapshot_guard
before insert or update or delete on public.trade_offer_players
for each row execute function public.guard_trade_player_precompetition_snapshot();

drop trigger if exists auction_precompetition_snapshot_guard
on public.auctions;
create trigger auction_precompetition_snapshot_guard
before insert or update or delete on public.auctions
for each row execute function public.guard_auction_precompetition_snapshot();

drop trigger if exists auction_item_precompetition_snapshot_guard
on public.auction_items;
create trigger auction_item_precompetition_snapshot_guard
before insert or update or delete on public.auction_items
for each row execute function public.guard_auction_item_precompetition_snapshot();

drop trigger if exists bid_precompetition_snapshot_guard
on public.bids;
create trigger bid_precompetition_snapshot_guard
before insert or update or delete on public.bids
for each row execute function public.guard_bid_precompetition_snapshot();

-- Wrapper v2: dopo il sorteggio congela esplicitamente l'assetto iniziale.
create or replace function public.generate_head_to_head_calendar_guarded_v2(
  p_league_id uuid,
  p_season text,
  p_start_matchday smallint default 1,
  p_first_kickoff timestamptz default (now() + interval '7 days'),
  p_return_leg boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_result jsonb;
  v_locked_at timestamptz := now();
begin
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('competition:' || p_league_id::text, 0)
  );

  v_result := public.generate_head_to_head_calendar_guarded(
    p_league_id,
    p_season,
    p_start_matchday,
    p_first_kickoff,
    p_return_leg
  );

  update public.leagues
  set
    calendar_snapshot_locked_at = v_locked_at,
    updated_at = now()
  where id = p_league_id;

  return v_result || jsonb_build_object(
    'snapshotLockedAt', v_locked_at,
    'snapshotMutationGuardVersion', 1
  );
end;
$$;

create or replace function public.get_league_competition_readiness_v2(
  p_league_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_base jsonb;
  v_checks jsonb;
  v_locked boolean;
  v_guard_count integer;
  v_guard_ready boolean;
begin
  v_base := public.get_league_competition_readiness_v1(p_league_id);
  v_checks := coalesce(v_base -> 'checks', '{}'::jsonb);
  v_locked := public.is_league_precompetition_snapshot_locked(p_league_id);

  select count(*)::integer
  into v_guard_count
  from pg_catalog.pg_trigger trigger_row
  join pg_catalog.pg_class table_row
    on table_row.oid = trigger_row.tgrelid
  join pg_catalog.pg_namespace namespace_row
    on namespace_row.oid = table_row.relnamespace
  where not trigger_row.tgisinternal
    and namespace_row.nspname = 'public'
    and trigger_row.tgname in (
      'roster_precompetition_snapshot_guard',
      'team_precompetition_snapshot_guard',
      'member_precompetition_snapshot_guard',
      'transaction_precompetition_snapshot_guard',
      'trade_precompetition_snapshot_guard',
      'trade_player_precompetition_snapshot_guard',
      'auction_precompetition_snapshot_guard',
      'auction_item_precompetition_snapshot_guard',
      'bid_precompetition_snapshot_guard'
    );

  v_guard_ready := v_guard_count = 9;

  return v_base || jsonb_build_object(
    'version', 2,
    'precompetitionSnapshotLocked', v_locked,
    'snapshotMutationGuardReady', v_guard_ready,
    'snapshotMutationGuardCount', v_guard_count,
    'checks', v_checks || jsonb_build_object(
      'precompetitionSnapshotLocked', v_locked,
      'snapshotMutationGuardReady', v_guard_ready
    ),
    'canStartCompetition',
      coalesce((v_base ->> 'canStartCompetition')::boolean, false)
      and v_locked
      and v_guard_ready
  );
end;
$$;

create or replace function public.get_league_calendar_state_v3(
  p_league_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_base jsonb;
  v_preflight jsonb;
  v_checks jsonb;
begin
  v_base := public.get_league_calendar_state_v2(p_league_id);
  v_preflight := public.get_league_competition_readiness_v2(p_league_id);
  v_checks := coalesce(v_base -> 'checks', '{}'::jsonb);

  return v_base || jsonb_build_object(
    'preflight', v_preflight,
    'checks', v_checks || jsonb_build_object(
      'precompetitionSnapshotLocked',
        v_preflight -> 'checks' -> 'precompetitionSnapshotLocked',
      'snapshotMutationGuardReady',
        v_preflight -> 'checks' -> 'snapshotMutationGuardReady'
    )
  );
end;
$$;

create or replace function public.start_league_competition_guarded(
  p_league_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_league public.leagues%rowtype;
  v_readiness jsonb;
  v_checks jsonb;
  v_fingerprint text;
  v_started_at timestamptz;
  v_member_user_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Devi effettuare l''accesso.';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('competition:' || p_league_id::text, 0)
  );

  select league.*
  into v_league
  from public.leagues league
  where league.id = p_league_id
  for update;

  if not found then
    raise exception 'Lega non trovata.';
  end if;

  if v_league.owner_id <> auth.uid() then
    raise exception 'Solo il Presidente può avviare la competizione.';
  end if;

  if v_league.competition_started_at is not null then
    return jsonb_build_object(
      'startedAt', v_league.competition_started_at,
      'startedBy', v_league.competition_started_by,
      'fingerprint', v_league.competition_start_fingerprint,
      'integrityVerifiedAt', v_league.competition_integrity_verified_at,
      'startVersion', v_league.competition_start_version,
      'alreadyStarted', true
    );
  end if;

  v_readiness := public.get_league_competition_readiness_v2(p_league_id);
  v_checks := v_readiness -> 'checks';

  if not coalesce((v_checks ->> 'membersReady')::boolean, false) then
    raise exception 'Lo spogliatoio non è ancora completo.';
  end if;
  if not coalesce((v_checks ->> 'teamsReady')::boolean, false) then
    raise exception 'Ogni partecipante deve avere una squadra.';
  end if;
  if not coalesce((v_checks ->> 'rostersReady')::boolean, false) then
    raise exception 'Tutte le rose devono essere complete.';
  end if;
  if not coalesce((v_checks ->> 'marketReady')::boolean, false) then
    raise exception 'Il Mercato segnala anomalie da risolvere.';
  end if;
  if not coalesce((v_checks ->> 'tradesSettled')::boolean, false) then
    raise exception 'Chiudi o annulla tutte le trattative in attesa.';
  end if;
  if not coalesce((v_checks ->> 'auctionIntegrityReady')::boolean, false)
    or not coalesce((v_checks ->> 'auctionClosed')::boolean, false) then
    raise exception 'Termina e verifica l''Asta Live prima dell''avvio.';
  end if;
  if not coalesce((v_checks ->> 'calendarIntegrityReady')::boolean, false) then
    raise exception 'Il calendario non ha superato i controlli di integrità.';
  end if;
  if not coalesce((v_checks ->> 'calendarSnapshotStable')::boolean, false) then
    raise exception 'Rose o crediti non coincidono con il sorteggio pubblicato.';
  end if;
  if not coalesce((v_checks ->> 'precompetitionSnapshotLocked')::boolean, false)
    or not coalesce((v_checks ->> 'snapshotMutationGuardReady')::boolean, false) then
    raise exception 'La fotografia pre-campionato non è ancora protetta.';
  end if;

  v_fingerprint := public.compute_league_competition_fingerprint(p_league_id);
  if v_fingerprint is distinct from v_league.calendar_roster_fingerprint then
    raise exception 'L''assetto della lega è cambiato dopo il sorteggio.';
  end if;

  v_started_at := now();

  update public.leagues
  set
    status = 'active',
    invites_open = false,
    competition_started_at = v_started_at,
    competition_started_by = auth.uid(),
    competition_start_fingerprint = v_fingerprint,
    competition_integrity_verified_at = v_started_at,
    competition_start_version = 2,
    updated_at = v_started_at
  where id = p_league_id;

  for v_member_user_id in
    select member.user_id
    from public.league_members member
    where member.league_id = p_league_id
  loop
    perform public.create_user_notification(
      v_member_user_id,
      p_league_id,
      'league',
      'La competizione è iniziata',
      'Calendario e assetto iniziale sono stati verificati. Da qui si gioca sul serio.',
      'league',
      jsonb_build_object(
        'event', 'competition_started',
        'startedAt', v_started_at,
        'startVersion', 2
      ),
      'competition-start:' || p_league_id::text
    );
  end loop;

  return jsonb_build_object(
    'startedAt', v_started_at,
    'startedBy', auth.uid(),
    'fingerprint', v_fingerprint,
    'integrityVerifiedAt', v_started_at,
    'startVersion', 2,
    'alreadyStarted', false
  );
end;
$$;

create or replace function public.get_league_management_state_v8(
  p_league_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_state jsonb;
  v_readiness jsonb;
  v_checks jsonb;
begin
  v_state := public.get_league_management_state_v7(p_league_id);
  v_readiness := public.get_league_competition_readiness_v2(p_league_id);
  v_checks := coalesce(v_state -> 'checks', '{}'::jsonb);

  return v_state || jsonb_build_object(
    'canStart', coalesce(
      (v_readiness ->> 'canStartCompetition')::boolean,
      false
    ),
    'competitionPreflight', v_readiness,
    'checks', v_checks || jsonb_build_object(
      'marketReady', v_readiness -> 'checks' -> 'marketReady',
      'tradesSettled', v_readiness -> 'checks' -> 'tradesSettled',
      'auctionIntegrityReady',
        v_readiness -> 'checks' -> 'auctionIntegrityReady',
      'auctionClosed', v_readiness -> 'checks' -> 'auctionClosed',
      'calendarIntegrityReady',
        v_readiness -> 'checks' -> 'calendarIntegrityReady',
      'calendarSnapshotStable',
        v_readiness -> 'checks' -> 'calendarSnapshotStable',
      'precompetitionSnapshotLocked',
        v_readiness -> 'checks' -> 'precompetitionSnapshotLocked',
      'snapshotMutationGuardReady',
        v_readiness -> 'checks' -> 'snapshotMutationGuardReady'
    )
  );
end;
$$;

-- Il reset del calendario deve riaprire l'assetto pre-campionato.
create or replace function public.clear_calendar_metadata_if_empty()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1
    from public.fantasy_fixtures fixture
    where fixture.league_id = old.league_id
  ) then
    update public.leagues
    set
      calendar_season = null,
      calendar_start_matchday = null,
      calendar_return_leg = null,
      calendar_generated_at = null,
      calendar_draw_seed = null,
      calendar_roster_fingerprint = null,
      calendar_expected_fixture_count = null,
      calendar_expected_matchday_count = null,
      calendar_integrity_verified_at = null,
      calendar_preflight_version = null,
      calendar_snapshot_locked_at = null,
      updated_at = now()
    where id = old.league_id;
  end if;

  return old;
end;
$$;

revoke all on function public.is_league_precompetition_snapshot_locked(uuid)
from public, anon, authenticated;
revoke all on function public.raise_precompetition_snapshot_locked()
from public, anon, authenticated;
revoke all on function public.generate_head_to_head_calendar_guarded_v2(
  uuid, text, smallint, timestamptz, boolean
) from public, anon;
revoke all on function public.get_league_competition_readiness_v2(uuid)
from public, anon;
revoke all on function public.get_league_calendar_state_v3(uuid)
from public, anon;
revoke all on function public.start_league_competition_guarded(uuid)
from public, anon;
revoke all on function public.get_league_management_state_v8(uuid)
from public, anon;
revoke all on function public.start_league_competition(uuid)
from public, anon, authenticated;
revoke all on function public.generate_head_to_head_calendar_guarded(
  uuid, text, smallint, timestamptz, boolean
) from public, anon, authenticated;

revoke all on function public.guard_roster_precompetition_snapshot()
from public, anon, authenticated;
revoke all on function public.guard_team_precompetition_snapshot()
from public, anon, authenticated;
revoke all on function public.guard_member_precompetition_snapshot()
from public, anon, authenticated;
revoke all on function public.guard_transaction_precompetition_snapshot()
from public, anon, authenticated;
revoke all on function public.guard_trade_precompetition_snapshot()
from public, anon, authenticated;
revoke all on function public.guard_trade_player_precompetition_snapshot()
from public, anon, authenticated;
revoke all on function public.guard_auction_precompetition_snapshot()
from public, anon, authenticated;
revoke all on function public.guard_auction_item_precompetition_snapshot()
from public, anon, authenticated;
revoke all on function public.guard_bid_precompetition_snapshot()
from public, anon, authenticated;
revoke all on function public.clear_calendar_metadata_if_empty()
from public, anon, authenticated;

grant execute on function public.generate_head_to_head_calendar_guarded_v2(
  uuid, text, smallint, timestamptz, boolean
) to authenticated;
grant execute on function public.get_league_competition_readiness_v2(uuid)
to authenticated;
grant execute on function public.get_league_calendar_state_v3(uuid)
to authenticated;
grant execute on function public.start_league_competition_guarded(uuid)
to authenticated;
grant execute on function public.get_league_management_state_v8(uuid)
to authenticated;

commit;

-- Controllo finale: attesi 20 valori true.
select
  (
    select count(*) = 5
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'leagues'
      and column_name in (
        'calendar_snapshot_locked_at',
        'competition_started_by',
        'competition_start_fingerprint',
        'competition_integrity_verified_at',
        'competition_start_version'
      )
  ) as competition_activation_columns_ready,
  to_regprocedure(
    'public.is_league_precompetition_snapshot_locked(uuid)'
  ) is not null as snapshot_lock_state_ready,
  to_regprocedure(
    'public.generate_head_to_head_calendar_guarded_v2(uuid,text,smallint,timestamptz,boolean)'
  ) is not null as guarded_calendar_v2_ready,
  to_regprocedure(
    'public.get_league_competition_readiness_v2(uuid)'
  ) is not null as competition_readiness_v2_ready,
  to_regprocedure(
    'public.get_league_calendar_state_v3(uuid)'
  ) is not null as calendar_state_v3_ready,
  to_regprocedure(
    'public.start_league_competition_guarded(uuid)'
  ) is not null as guarded_competition_start_ready,
  to_regprocedure(
    'public.get_league_management_state_v8(uuid)'
  ) is not null as management_state_v8_ready,
  has_function_privilege(
    'authenticated',
    'public.generate_head_to_head_calendar_guarded_v2(uuid,text,smallint,timestamptz,boolean)',
    'EXECUTE'
  ) as authenticated_calendar_v2_access_ready,
  has_function_privilege(
    'authenticated',
    'public.start_league_competition_guarded(uuid)',
    'EXECUTE'
  ) as authenticated_guarded_start_access_ready,
  has_function_privilege(
    'authenticated',
    'public.get_league_management_state_v8(uuid)',
    'EXECUTE'
  ) as authenticated_management_v8_access_ready,
  not has_function_privilege(
    'authenticated',
    'public.start_league_competition(uuid)',
    'EXECUTE'
  ) as legacy_competition_start_blocked,
  not has_function_privilege(
    'authenticated',
    'public.generate_head_to_head_calendar_guarded(uuid,text,smallint,timestamptz,boolean)',
    'EXECUTE'
  ) as legacy_guarded_calendar_blocked,
  (
    select count(*) = 9
    from pg_catalog.pg_trigger trigger_row
    where not trigger_row.tgisinternal
      and trigger_row.tgname in (
        'roster_precompetition_snapshot_guard',
        'team_precompetition_snapshot_guard',
        'member_precompetition_snapshot_guard',
        'transaction_precompetition_snapshot_guard',
        'trade_precompetition_snapshot_guard',
        'trade_player_precompetition_snapshot_guard',
        'auction_precompetition_snapshot_guard',
        'auction_item_precompetition_snapshot_guard',
        'bid_precompetition_snapshot_guard'
      )
  ) as nine_snapshot_guards_ready,
  coalesce(
    pg_get_functiondef(
      to_regprocedure('public.compute_league_competition_fingerprint(uuid)')
    ) not ilike '%member.role%',
    false
  ) as role_changes_do_not_invalidate_snapshot,
  coalesce(
    pg_get_functiondef(
      to_regprocedure('public.start_league_competition_guarded(uuid)')
    ) ilike '%calendarSnapshotStable%',
    false
  ) as start_rechecks_snapshot_ready,
  coalesce(
    pg_get_functiondef(
      to_regprocedure('public.start_league_competition_guarded(uuid)')
    ) ilike '%competition_start_fingerprint%',
    false
  ) as start_fingerprint_audit_ready,
  coalesce(
    pg_get_functiondef(
      to_regprocedure('public.start_league_competition_guarded(uuid)')
    ) ilike '%competition-start:%',
    false
  ) as competition_start_notification_ready,
  coalesce(
    pg_get_functiondef(
      to_regprocedure('public.clear_calendar_metadata_if_empty()')
    ) ilike '%calendar_snapshot_locked_at = null%',
    false
  ) as reset_reopens_precompetition_ready,
  coalesce(
    pg_get_functiondef(
      to_regprocedure('public.get_league_management_state_v8(uuid)')
    ) ilike '%precompetitionSnapshotLocked%',
    false
  ) as management_preflight_ready,
  coalesce(
    pg_get_functiondef(
      to_regprocedure('public.get_league_competition_readiness_v2(uuid)')
    ) ilike '%snapshotMutationGuardReady%',
    false
  ) as snapshot_guard_diagnostic_ready;
