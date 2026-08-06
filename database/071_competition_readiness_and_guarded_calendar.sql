-- LEGHEVO · preflight competizione e calendario protetto
-- Versione applicativa: 0.58.1
-- Eseguire dopo 070_market_model_closure.sql.
-- Script idempotente: può essere eseguito più volte.

begin;

alter table public.leagues
  add column if not exists calendar_roster_fingerprint text,
  add column if not exists calendar_expected_fixture_count integer,
  add column if not exists calendar_expected_matchday_count integer,
  add column if not exists calendar_integrity_verified_at timestamptz,
  add column if not exists calendar_preflight_version smallint;

alter table public.leagues
  drop constraint if exists leagues_calendar_expected_fixture_count_check;
alter table public.leagues
  add constraint leagues_calendar_expected_fixture_count_check
  check (
    calendar_expected_fixture_count is null
    or calendar_expected_fixture_count >= 0
  );

alter table public.leagues
  drop constraint if exists leagues_calendar_expected_matchday_count_check;
alter table public.leagues
  add constraint leagues_calendar_expected_matchday_count_check
  check (
    calendar_expected_matchday_count is null
    or calendar_expected_matchday_count >= 0
  );

alter table public.leagues
  drop constraint if exists leagues_calendar_preflight_version_check;
alter table public.leagues
  add constraint leagues_calendar_preflight_version_check
  check (
    calendar_preflight_version is null
    or calendar_preflight_version >= 1
  );

-- Impronta deterministica di partecipanti, squadre, crediti e rose attive.
-- Viene salvata al sorteggio e ricontrollata prima del fischio d'inizio.
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
        select jsonb_agg(
          jsonb_build_object(
            'userId', member.user_id,
            'role', member.role
          )
          order by member.user_id
        )
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

create or replace function public.get_league_competition_readiness_v1(
  p_league_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_league public.leagues%rowtype;
  v_member_count integer := 0;
  v_team_count integer := 0;
  v_full_roster_count integer := 0;
  v_fixture_count integer := 0;
  v_matchday_count integer := 0;
  v_pending_trade_count integer := 0;
  v_unfinished_auction_count integer := 0;
  v_bidding_item_count integer := 0;
  v_pair_issue_count integer := 0;
  v_team_matchday_issue_count integer := 0;
  v_expected_fixture_count integer := 0;
  v_expected_matchday_count integer := 0;
  v_leg_count integer := 1;
  v_market jsonb := '{}'::jsonb;
  v_auction jsonb := '{}'::jsonb;
  v_current_fingerprint text;
  v_members_ready boolean;
  v_teams_ready boolean;
  v_rosters_ready boolean;
  v_market_ready boolean;
  v_trades_settled boolean;
  v_auction_integrity_ready boolean;
  v_auction_closed boolean;
  v_calendar_exists boolean;
  v_calendar_count_ready boolean;
  v_calendar_pairs_ready boolean;
  v_calendar_team_rounds_ready boolean;
  v_calendar_integrity_ready boolean;
  v_snapshot_present boolean;
  v_snapshot_stable boolean;
  v_competition_not_started boolean;
  v_team_readiness jsonb := '[]'::jsonb;
begin
  if v_user_id is null then
    raise exception 'Devi effettuare l''accesso.';
  end if;

  select league.*
  into v_league
  from public.leagues league
  where league.id = p_league_id;

  if not found then
    raise exception 'Lega non trovata.';
  end if;

  if not public.is_league_member(p_league_id)
    and v_league.owner_id <> v_user_id then
    raise exception 'Non fai parte di questa lega.';
  end if;

  select count(*)::integer
  into v_member_count
  from public.league_members member
  join public.profiles profile on profile.id = member.user_id
  where member.league_id = p_league_id
    and profile.deleted_at is null;

  select
    count(*)::integer,
    count(*) filter (
      where team_state.roster_count = v_league.roster_size
    )::integer,
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'teamId', team_state.id,
          'teamName', team_state.name,
          'managerId', team_state.manager_id,
          'creditsRemaining', team_state.credits_remaining,
          'rosterCount', team_state.roster_count,
          'rosterSize', v_league.roster_size,
          'complete', team_state.roster_count = v_league.roster_size
        )
        order by team_state.created_at, team_state.id
      ),
      '[]'::jsonb
    )
  into v_team_count, v_full_roster_count, v_team_readiness
  from (
    select
      team.id,
      team.name,
      team.manager_id,
      team.credits_remaining,
      team.created_at,
      count(roster.id) filter (
        where roster.released_at is null
      )::integer as roster_count
    from public.fantasy_teams team
    left join public.roster_entries roster
      on roster.fantasy_team_id = team.id
    where team.league_id = p_league_id
    group by
      team.id,
      team.name,
      team.manager_id,
      team.credits_remaining,
      team.created_at
  ) team_state;

  select
    count(*)::integer,
    count(distinct fixture.matchday_id)::integer
  into v_fixture_count, v_matchday_count
  from public.fantasy_fixtures fixture
  where fixture.league_id = p_league_id;

  select count(*)::integer
  into v_pending_trade_count
  from public.trade_offers offer
  where offer.league_id = p_league_id
    and offer.status = 'pending'
    and offer.expires_at > now();

  select count(*)::integer
  into v_unfinished_auction_count
  from public.auctions auction
  where auction.league_id = p_league_id
    and auction.status <> 'completed';

  select count(*)::integer
  into v_bidding_item_count
  from public.auction_items item
  join public.auctions auction on auction.id = item.auction_id
  where auction.league_id = p_league_id
    and item.status = 'bidding';

  v_market := public.get_league_market_integrity_v4(p_league_id);
  v_auction := public.get_league_auction_integrity_v1(p_league_id);
  v_current_fingerprint :=
    public.compute_league_competition_fingerprint(p_league_id);

  v_leg_count := case
    when coalesce(v_league.calendar_return_leg, true) then 2
    else 1
  end;
  v_expected_fixture_count :=
    (v_team_count * greatest(v_team_count - 1, 0) / 2) * v_leg_count;
  v_expected_matchday_count :=
    case
      when v_team_count < 2 then 0
      when mod(v_team_count, 2) = 0 then (v_team_count - 1) * v_leg_count
      else v_team_count * v_leg_count
    end;

  if v_fixture_count > 0 then
    select count(*)::integer
    into v_pair_issue_count
    from (
      select
        least(fixture.home_team_id, fixture.away_team_id) as first_team_id,
        greatest(fixture.home_team_id, fixture.away_team_id) as second_team_id
      from public.fantasy_fixtures fixture
      where fixture.league_id = p_league_id
      group by
        least(fixture.home_team_id, fixture.away_team_id),
        greatest(fixture.home_team_id, fixture.away_team_id)
      having count(*) <> v_leg_count
    ) invalid_pair;

    select count(*)::integer
    into v_team_matchday_issue_count
    from (
      select participation.matchday_id, participation.team_id
      from (
        select fixture.matchday_id, fixture.home_team_id as team_id
        from public.fantasy_fixtures fixture
        where fixture.league_id = p_league_id
        union all
        select fixture.matchday_id, fixture.away_team_id
        from public.fantasy_fixtures fixture
        where fixture.league_id = p_league_id
      ) participation
      group by participation.matchday_id, participation.team_id
      having count(*) <> 1
    ) invalid_team_round;
  end if;

  v_members_ready := v_member_count = v_league.team_limit;
  v_teams_ready :=
    v_team_count = v_league.team_limit
    and v_team_count = v_member_count;
  v_rosters_ready :=
    v_full_roster_count = v_league.team_limit
    and v_team_count = v_league.team_limit;
  v_market_ready := coalesce((v_market ->> 'ok')::boolean, false);
  v_trades_settled := v_pending_trade_count = 0;
  v_auction_integrity_ready :=
    coalesce((v_auction ->> 'ok')::boolean, false);
  v_auction_closed :=
    v_unfinished_auction_count = 0
    and v_bidding_item_count = 0;
  v_calendar_exists := v_fixture_count > 0;
  v_calendar_count_ready :=
    v_calendar_exists
    and v_fixture_count = coalesce(
      v_league.calendar_expected_fixture_count,
      v_expected_fixture_count
    )
    and v_matchday_count = coalesce(
      v_league.calendar_expected_matchday_count,
      v_expected_matchday_count
    );
  v_calendar_pairs_ready :=
    v_calendar_exists and v_pair_issue_count = 0;
  v_calendar_team_rounds_ready :=
    v_calendar_exists and v_team_matchday_issue_count = 0;
  v_calendar_integrity_ready :=
    v_calendar_count_ready
    and v_calendar_pairs_ready
    and v_calendar_team_rounds_ready;
  v_snapshot_present :=
    v_league.calendar_roster_fingerprint is not null;
  v_snapshot_stable :=
    v_snapshot_present
    and v_league.calendar_roster_fingerprint = v_current_fingerprint;
  v_competition_not_started :=
    v_league.competition_started_at is null;

  return jsonb_build_object(
    'version', 1,
    'checkedAt', now(),
    'leagueId', p_league_id,
    'memberCount', v_member_count,
    'teamCount', v_team_count,
    'teamLimit', v_league.team_limit,
    'fullRosterCount', v_full_roster_count,
    'rosterSize', v_league.roster_size,
    'pendingTradeCount', v_pending_trade_count,
    'unfinishedAuctionCount', v_unfinished_auction_count,
    'biddingItemCount', v_bidding_item_count,
    'fixtureCount', v_fixture_count,
    'matchdayCount', v_matchday_count,
    'expectedFixtureCount', v_expected_fixture_count,
    'expectedMatchdayCount', v_expected_matchday_count,
    'pairIssueCount', v_pair_issue_count,
    'teamMatchdayIssueCount', v_team_matchday_issue_count,
    'calendarSnapshotPresent', v_snapshot_present,
    'calendarSnapshotStable', v_snapshot_stable,
    'calendarIntegrityVerifiedAt',
      v_league.calendar_integrity_verified_at,
    'marketIntegrity', v_market,
    'auctionIntegrity', v_auction,
    'teams', v_team_readiness,
    'checks', jsonb_build_object(
      'membersReady', v_members_ready,
      'teamsReady', v_teams_ready,
      'rostersReady', v_rosters_ready,
      'marketReady', v_market_ready,
      'tradesSettled', v_trades_settled,
      'auctionIntegrityReady', v_auction_integrity_ready,
      'auctionClosed', v_auction_closed,
      'calendarEmpty', not v_calendar_exists,
      'calendarExists', v_calendar_exists,
      'calendarCountReady', v_calendar_count_ready,
      'calendarPairsReady', v_calendar_pairs_ready,
      'calendarTeamRoundsReady', v_calendar_team_rounds_ready,
      'calendarIntegrityReady', v_calendar_integrity_ready,
      'calendarSnapshotPresent', v_snapshot_present,
      'calendarSnapshotStable', v_snapshot_stable,
      'competitionNotStarted', v_competition_not_started
    ),
    'canGenerateCalendar',
      v_league.owner_id = v_user_id
      and v_members_ready
      and v_teams_ready
      and v_rosters_ready
      and v_market_ready
      and v_trades_settled
      and v_auction_integrity_ready
      and v_auction_closed
      and not v_calendar_exists
      and v_competition_not_started,
    'canStartCompetition',
      v_league.owner_id = v_user_id
      and v_members_ready
      and v_teams_ready
      and v_rosters_ready
      and v_market_ready
      and v_trades_settled
      and v_auction_integrity_ready
      and v_auction_closed
      and v_calendar_integrity_ready
      and v_snapshot_stable
      and v_competition_not_started
  );
end;
$$;

-- Wrapper transazionale: il vecchio motore continua a generare il round-robin,
-- ma soltanto dopo il preflight e con una verifica completa a fine sorteggio.
create or replace function public.generate_head_to_head_calendar_guarded(
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
  v_league public.leagues%rowtype;
  v_readiness jsonb;
  v_checks jsonb;
  v_fingerprint_before text;
  v_fingerprint_after text;
  v_team_count integer;
  v_leg_count integer;
  v_expected_fixture_count integer;
  v_expected_matchday_count integer;
  v_created integer;
  v_actual_fixture_count integer;
  v_actual_matchday_count integer;
  v_pair_issue_count integer;
  v_team_matchday_issue_count integer;
begin
  if auth.uid() is null then
    raise exception 'Devi effettuare l''accesso.';
  end if;

  select league.*
  into v_league
  from public.leagues league
  where league.id = p_league_id
  for update;

  if not found then
    raise exception 'Lega non trovata.';
  end if;

  if v_league.owner_id <> auth.uid() then
    raise exception 'Solo il Presidente può generare il calendario.';
  end if;

  v_readiness := public.get_league_competition_readiness_v1(p_league_id);
  v_checks := v_readiness -> 'checks';

  if not coalesce((v_checks ->> 'membersReady')::boolean, false) then
    raise exception 'Prima devono entrare tutti i partecipanti previsti.';
  end if;
  if not coalesce((v_checks ->> 'teamsReady')::boolean, false) then
    raise exception 'Ogni partecipante deve avere una squadra.';
  end if;
  if not coalesce((v_checks ->> 'rostersReady')::boolean, false) then
    raise exception 'Tutte le rose devono essere complete.';
  end if;
  if not coalesce((v_checks ->> 'marketReady')::boolean, false) then
    raise exception 'Il Mercato segnala anomalie: correggile prima del sorteggio.';
  end if;
  if not coalesce((v_checks ->> 'tradesSettled')::boolean, false) then
    raise exception 'Chiudi o annulla tutte le trattative ancora in attesa.';
  end if;
  if not coalesce((v_checks ->> 'auctionIntegrityReady')::boolean, false) then
    raise exception 'L''Asta Live segnala anomalie da risolvere.';
  end if;
  if not coalesce((v_checks ->> 'auctionClosed')::boolean, false) then
    raise exception 'Termina l''Asta Live prima di generare il calendario.';
  end if;
  if not coalesce((v_checks ->> 'calendarEmpty')::boolean, false) then
    raise exception 'Il calendario di questa lega esiste già.';
  end if;
  if not coalesce((v_checks ->> 'competitionNotStarted')::boolean, false) then
    raise exception 'La competizione è già iniziata.';
  end if;

  v_team_count := (v_readiness ->> 'teamCount')::integer;
  v_leg_count := case when p_return_leg then 2 else 1 end;
  v_expected_fixture_count :=
    (v_team_count * greatest(v_team_count - 1, 0) / 2) * v_leg_count;
  v_expected_matchday_count :=
    case
      when mod(v_team_count, 2) = 0 then (v_team_count - 1) * v_leg_count
      else v_team_count * v_leg_count
    end;
  v_fingerprint_before :=
    public.compute_league_competition_fingerprint(p_league_id);

  v_created := public.generate_head_to_head_calendar(
    p_league_id,
    p_season,
    p_start_matchday,
    p_first_kickoff,
    p_return_leg
  );

  v_fingerprint_after :=
    public.compute_league_competition_fingerprint(p_league_id);
  if v_fingerprint_after <> v_fingerprint_before then
    raise exception 'Rose o squadre sono cambiate durante il sorteggio. Riprova.';
  end if;

  select
    count(*)::integer,
    count(distinct fixture.matchday_id)::integer
  into v_actual_fixture_count, v_actual_matchday_count
  from public.fantasy_fixtures fixture
  where fixture.league_id = p_league_id;

  select count(*)::integer
  into v_pair_issue_count
  from (
    select
      least(fixture.home_team_id, fixture.away_team_id),
      greatest(fixture.home_team_id, fixture.away_team_id)
    from public.fantasy_fixtures fixture
    where fixture.league_id = p_league_id
    group by
      least(fixture.home_team_id, fixture.away_team_id),
      greatest(fixture.home_team_id, fixture.away_team_id)
    having count(*) <> v_leg_count
  ) invalid_pair;

  select count(*)::integer
  into v_team_matchday_issue_count
  from (
    select participation.matchday_id, participation.team_id
    from (
      select fixture.matchday_id, fixture.home_team_id as team_id
      from public.fantasy_fixtures fixture
      where fixture.league_id = p_league_id
      union all
      select fixture.matchday_id, fixture.away_team_id
      from public.fantasy_fixtures fixture
      where fixture.league_id = p_league_id
    ) participation
    group by participation.matchday_id, participation.team_id
    having count(*) <> 1
  ) invalid_team_round;

  if v_created <> v_expected_fixture_count
    or v_actual_fixture_count <> v_expected_fixture_count
    or v_actual_matchday_count <> v_expected_matchday_count
    or v_pair_issue_count <> 0
    or v_team_matchday_issue_count <> 0 then
    raise exception
      'Verifica calendario non superata: il sorteggio è stato annullato.';
  end if;

  update public.leagues
  set
    calendar_roster_fingerprint = v_fingerprint_before,
    calendar_expected_fixture_count = v_expected_fixture_count,
    calendar_expected_matchday_count = v_expected_matchday_count,
    calendar_integrity_verified_at = now(),
    calendar_preflight_version = 1,
    updated_at = now()
  where id = p_league_id;

  return jsonb_build_object(
    'affected', v_created,
    'fixtureCount', v_actual_fixture_count,
    'matchdayCount', v_actual_matchday_count,
    'expectedFixtureCount', v_expected_fixture_count,
    'expectedMatchdayCount', v_expected_matchday_count,
    'fingerprint', v_fingerprint_before,
    'verifiedAt', now(),
    'preflightVersion', 1
  );
end;
$$;

create or replace function public.get_league_calendar_state_v2(
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
  v_base_checks jsonb;
begin
  v_base := public.get_league_calendar_state(p_league_id);
  v_preflight := public.get_league_competition_readiness_v1(p_league_id);
  v_base_checks := coalesce(v_base -> 'checks', '{}'::jsonb);

  return v_base || jsonb_build_object(
    'canGenerate', coalesce(
      (v_preflight ->> 'canGenerateCalendar')::boolean,
      false
    ),
    'preflight', v_preflight,
    'checks', v_base_checks || jsonb_build_object(
      'marketReady', v_preflight -> 'checks' -> 'marketReady',
      'tradesSettled', v_preflight -> 'checks' -> 'tradesSettled',
      'auctionIntegrityReady',
        v_preflight -> 'checks' -> 'auctionIntegrityReady',
      'auctionClosed', v_preflight -> 'checks' -> 'auctionClosed',
      'calendarIntegrityReady',
        v_preflight -> 'checks' -> 'calendarIntegrityReady',
      'calendarSnapshotStable',
        v_preflight -> 'checks' -> 'calendarSnapshotStable'
    )
  );
end;
$$;

-- Quando l'ultimo accoppiamento viene eliminato, anche la nuova fotografia
-- del pre-campionato deve essere azzerata.
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
      updated_at = now()
    where id = old.league_id;
  end if;

  return old;
end;
$$;

-- Il client aggiornato usa esclusivamente il wrapper verificato.
revoke all on function public.generate_head_to_head_calendar(
  uuid, text, smallint, timestamptz, boolean
) from public, anon, authenticated;
revoke all on function public.compute_league_competition_fingerprint(uuid)
from public, anon, authenticated;
revoke all on function public.get_league_competition_readiness_v1(uuid)
from public, anon;
revoke all on function public.generate_head_to_head_calendar_guarded(
  uuid, text, smallint, timestamptz, boolean
) from public, anon;
revoke all on function public.get_league_calendar_state_v2(uuid)
from public, anon;
revoke all on function public.clear_calendar_metadata_if_empty()
from public, anon, authenticated;

grant execute on function public.get_league_competition_readiness_v1(uuid)
to authenticated;
grant execute on function public.generate_head_to_head_calendar_guarded(
  uuid, text, smallint, timestamptz, boolean
) to authenticated;
grant execute on function public.get_league_calendar_state_v2(uuid)
to authenticated;

commit;

-- Controllo finale: attesi 18 valori true.
select
  (
    select count(*) = 5
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'leagues'
      and column_name in (
        'calendar_roster_fingerprint',
        'calendar_expected_fixture_count',
        'calendar_expected_matchday_count',
        'calendar_integrity_verified_at',
        'calendar_preflight_version'
      )
  ) as calendar_preflight_columns_ready,
  to_regprocedure(
    'public.compute_league_competition_fingerprint(uuid)'
  ) is not null as competition_fingerprint_ready,
  to_regprocedure(
    'public.get_league_competition_readiness_v1(uuid)'
  ) is not null as competition_readiness_ready,
  to_regprocedure(
    'public.generate_head_to_head_calendar_guarded(uuid,text,smallint,timestamptz,boolean)'
  ) is not null as guarded_calendar_generator_ready,
  to_regprocedure(
    'public.get_league_calendar_state_v2(uuid)'
  ) is not null as calendar_state_v2_ready,
  has_function_privilege(
    'authenticated',
    'public.get_league_competition_readiness_v1(uuid)',
    'EXECUTE'
  ) as authenticated_readiness_access_ready,
  has_function_privilege(
    'authenticated',
    'public.generate_head_to_head_calendar_guarded(uuid,text,smallint,timestamptz,boolean)',
    'EXECUTE'
  ) as authenticated_guarded_generator_ready,
  has_function_privilege(
    'authenticated',
    'public.get_league_calendar_state_v2(uuid)',
    'EXECUTE'
  ) as authenticated_calendar_state_v2_ready,
  not has_function_privilege(
    'authenticated',
    'public.generate_head_to_head_calendar(uuid,text,smallint,timestamptz,boolean)',
    'EXECUTE'
  ) as legacy_calendar_generator_blocked,
  not has_function_privilege(
    'anon',
    'public.get_league_competition_readiness_v1(uuid)',
    'EXECUTE'
  ) as anonymous_readiness_blocked,
  coalesce(
    pg_get_functiondef(
      to_regprocedure('public.get_league_competition_readiness_v1(uuid)')
    ) ilike '%pendingTradeCount%',
    false
  ) as pending_trade_preflight_ready,
  coalesce(
    pg_get_functiondef(
      to_regprocedure('public.get_league_competition_readiness_v1(uuid)')
    ) ilike '%auctionClosed%',
    false
  ) as auction_closure_preflight_ready,
  coalesce(
    pg_get_functiondef(
      to_regprocedure('public.get_league_competition_readiness_v1(uuid)')
    ) ilike '%calendarSnapshotStable%',
    false
  ) as roster_snapshot_preflight_ready,
  coalesce(
    pg_get_functiondef(
      to_regprocedure(
        'public.generate_head_to_head_calendar_guarded(uuid,text,smallint,timestamptz,boolean)'
      )
    ) ilike '%v_expected_fixture_count%',
    false
  ) as expected_fixture_verification_ready,
  coalesce(
    pg_get_functiondef(
      to_regprocedure(
        'public.generate_head_to_head_calendar_guarded(uuid,text,smallint,timestamptz,boolean)'
      )
    ) ilike '%v_pair_issue_count%',
    false
  ) as pair_uniqueness_verification_ready,
  coalesce(
    pg_get_functiondef(
      to_regprocedure(
        'public.generate_head_to_head_calendar_guarded(uuid,text,smallint,timestamptz,boolean)'
      )
    ) ilike '%v_team_matchday_issue_count%',
    false
  ) as one_match_per_round_verification_ready,
  coalesce(
    pg_get_functiondef(
      to_regprocedure('public.clear_calendar_metadata_if_empty()')
    ) ilike '%calendar_roster_fingerprint = null%',
    false
  ) as preflight_reset_ready,
  to_regprocedure('public.get_league_market_integrity_v4(uuid)') is not null
    and to_regprocedure('public.get_league_auction_integrity_v1(uuid)') is not null
    as market_and_auction_dependencies_ready;
