-- LEGHEVO · chiusura del modello Mercato, Scambi e Asta Live
-- Versione applicativa: 0.58.0
-- Eseguire dopo 069_market_auction_coordination.sql.
-- Script idempotente: può essere eseguito più volte.

begin;

-- Le tabelle operative restano leggibili dai membri tramite RLS, ma nessun
-- client autenticato può più modificarle direttamente. Ogni mutazione passa
-- esclusivamente dalle RPC security definer che applicano blocchi, crediti,
-- quote ruolo, riserve e registro movimenti.
do $$
declare
  v_policy record;
begin
  for v_policy in
    select schemaname, tablename, policyname
    from pg_catalog.pg_policies
    where schemaname = 'public'
      and tablename = any (array[
        'fantasy_teams',
        'roster_entries',
        'team_transactions',
        'trade_offers',
        'trade_offer_players',
        'trade_player_reservations',
        'trade_credit_reservations',
        'auctions',
        'auction_items',
        'bids'
      ])
      and cmd in ('ALL', 'INSERT', 'UPDATE', 'DELETE')
  loop
    execute format(
      'drop policy if exists %I on %I.%I',
      v_policy.policyname,
      v_policy.schemaname,
      v_policy.tablename
    );
  end loop;
end;
$$;

revoke insert, update, delete, truncate
on table
  public.fantasy_teams,
  public.roster_entries,
  public.team_transactions,
  public.trade_offers,
  public.trade_offer_players,
  public.trade_player_reservations,
  public.trade_credit_reservations,
  public.auctions,
  public.auction_items,
  public.bids
from authenticated, anon;

grant select
on table
  public.fantasy_teams,
  public.roster_entries,
  public.team_transactions,
  public.trade_offers,
  public.trade_offer_players,
  public.trade_player_reservations,
  public.trade_credit_reservations,
  public.auctions,
  public.auction_items,
  public.bids
to authenticated;

-- Diagnostica unificata finale del blocco mercato.
create or replace function public.get_league_market_integrity_v4(
  p_league_id uuid
)
returns jsonb
language plpgsql
security definer
stable
set search_path = ''
as $$
declare
  v_base jsonb;
  v_unsafe_policies integer;
  v_unsafe_grants integer;
  v_base_issue_count integer;
  v_base_ok boolean;
  v_sensitive_tables text[] := array[
    'public.fantasy_teams',
    'public.roster_entries',
    'public.team_transactions',
    'public.trade_offers',
    'public.trade_offer_players',
    'public.trade_player_reservations',
    'public.trade_credit_reservations',
    'public.auctions',
    'public.auction_items',
    'public.bids'
  ];
  v_table_name text;
begin
  if auth.uid() is null then
    raise exception 'Devi effettuare l''accesso.';
  end if;

  if not public.is_league_member(p_league_id) then
    raise exception 'Non fai parte di questa lega.';
  end if;

  v_base := public.get_league_market_integrity_v3(p_league_id);

  select count(*)::integer
  into v_unsafe_policies
  from pg_catalog.pg_policies policy_row
  where policy_row.schemaname = 'public'
    and policy_row.tablename = any (array[
      'fantasy_teams',
      'roster_entries',
      'team_transactions',
      'trade_offers',
      'trade_offer_players',
      'trade_player_reservations',
      'trade_credit_reservations',
      'auctions',
      'auction_items',
      'bids'
    ])
    and policy_row.cmd in ('ALL', 'INSERT', 'UPDATE', 'DELETE');

  v_unsafe_grants := 0;
  foreach v_table_name in array v_sensitive_tables
  loop
    if pg_catalog.has_table_privilege(
      'authenticated',
      v_table_name,
      'INSERT'
    ) or pg_catalog.has_table_privilege(
      'authenticated',
      v_table_name,
      'UPDATE'
    ) or pg_catalog.has_table_privilege(
      'authenticated',
      v_table_name,
      'DELETE'
    ) or pg_catalog.has_table_privilege(
      'authenticated',
      v_table_name,
      'TRUNCATE'
    ) then
      v_unsafe_grants := v_unsafe_grants + 1;
    end if;
  end loop;

  v_base_issue_count := coalesce((v_base ->> 'issueCount')::integer, 0);
  v_base_ok := coalesce((v_base ->> 'ok')::boolean, false);

  return v_base || jsonb_build_object(
    'version', 4,
    'ok', v_base_ok and v_unsafe_policies = 0 and v_unsafe_grants = 0,
    'issueCount',
      v_base_issue_count + v_unsafe_policies + v_unsafe_grants,
    'marketModelClosed', true,
    'protectedMutationTables', cardinality(v_sensitive_tables),
    'unsafeDirectPolicies', v_unsafe_policies,
    'unsafeAuthenticatedDmlGrants', v_unsafe_grants,
    'rpcOnlyMutations', v_unsafe_policies = 0 and v_unsafe_grants = 0
  );
end;
$$;

revoke all on function public.get_league_market_integrity_v4(uuid)
from public, anon;
grant execute on function public.get_league_market_integrity_v4(uuid)
to authenticated;

commit;

-- Controllo finale: attesi 18 valori true.
select
  to_regprocedure('public.get_league_market_integrity_v4(uuid)') is not null
    as unified_market_diagnostics_ready,
  has_function_privilege(
    'authenticated',
    'public.get_league_market_integrity_v4(uuid)',
    'EXECUTE'
  ) as authenticated_diagnostics_execute_ready,
  to_regprocedure('public.get_league_market_integrity_v3(uuid)') is not null
    as coordination_diagnostics_dependency_ready,
  to_regprocedure('public.sign_free_agent(uuid,uuid)') is not null
    as protected_free_agent_purchase_ready,
  to_regprocedure('public.release_roster_player(uuid,uuid)') is not null
    as protected_release_ready,
  to_regprocedure(
    'public.create_trade_offer(uuid,uuid,uuid[],uuid[],integer,integer,text)'
  ) is not null as protected_trade_creation_ready,
  to_regprocedure('public.respond_trade_offer(uuid,boolean)') is not null
    as protected_trade_response_ready,
  to_regprocedure('public.cancel_trade_offer(uuid)') is not null
    as protected_trade_cancel_ready,
  to_regprocedure('public.nominate_auction_player(uuid,uuid,integer)') is not null
    as protected_nomination_ready,
  to_regprocedure('public.place_bid(uuid,integer)') is not null
    as protected_bid_ready,
  to_regprocedure('public.finalize_auction_item(uuid)') is not null
    as protected_assignment_ready,
  not exists (
    select 1
    from pg_catalog.pg_policies policy_row
    where policy_row.schemaname = 'public'
      and policy_row.tablename = any (array[
        'fantasy_teams',
        'roster_entries',
        'team_transactions',
        'trade_offers',
        'trade_offer_players',
        'trade_player_reservations',
        'trade_credit_reservations',
        'auctions',
        'auction_items',
        'bids'
      ])
      and policy_row.cmd in ('ALL', 'INSERT', 'UPDATE', 'DELETE')
  ) as no_direct_write_policies,
  not pg_catalog.has_table_privilege(
    'authenticated', 'public.fantasy_teams', 'UPDATE'
  ) as team_credit_direct_update_blocked,
  not pg_catalog.has_table_privilege(
    'authenticated', 'public.roster_entries', 'INSERT'
  ) as roster_direct_insert_blocked,
  not pg_catalog.has_table_privilege(
    'authenticated', 'public.team_transactions', 'INSERT'
  ) as ledger_direct_insert_blocked,
  not pg_catalog.has_table_privilege(
    'authenticated', 'public.trade_offers', 'UPDATE'
  ) as trade_direct_update_blocked,
  not pg_catalog.has_table_privilege(
    'authenticated', 'public.auctions', 'UPDATE'
  ) as auction_direct_update_blocked,
  not pg_catalog.has_table_privilege(
    'authenticated', 'public.bids', 'INSERT'
  ) as bid_direct_insert_blocked;
