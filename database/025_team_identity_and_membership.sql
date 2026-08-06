-- LEGHEVO · identità squadra e uscita autonoma dalla lega
-- Eseguire nel SQL Editor di Supabase dopo 024.

create or replace function public.update_my_team_name(
  p_league_id uuid,
  p_team_name text
)
returns public.fantasy_teams
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_league public.leagues%rowtype;
  v_team public.fantasy_teams%rowtype;
  v_name text := trim(coalesce(p_team_name, ''));
begin
  if auth.uid() is null then
    raise exception 'Devi effettuare l''accesso.';
  end if;

  if char_length(v_name) not between 2 and 40 then
    raise exception 'Il nome squadra deve contenere da 2 a 40 caratteri.';
  end if;

  select league.*
  into v_league
  from public.leagues league
  where league.id = p_league_id
  for update;

  if not found then
    raise exception 'Lega non trovata.';
  end if;

  if v_league.competition_started_at is not null then
    raise exception
      'La competizione è iniziata: il nome squadra non può più cambiare.';
  end if;

  if exists (
    select 1
    from public.fantasy_teams other_team
    where other_team.league_id = p_league_id
      and other_team.manager_id <> auth.uid()
      and lower(trim(other_team.name)) = lower(v_name)
  ) then
    raise exception 'Questo nome squadra è già stato preso.';
  end if;

  update public.fantasy_teams
  set name = v_name
  where league_id = p_league_id
    and manager_id = auth.uid()
  returning * into v_team;

  if v_team.id is null then
    raise exception 'Squadra non trovata.';
  end if;

  return v_team;
end;
$$;

create or replace function public.leave_league(
  p_league_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_league public.leagues%rowtype;
  v_team_id uuid;
  v_team_name text;
begin
  if v_user_id is null then
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

  if not exists (
    select 1
    from public.league_members member
    where member.league_id = p_league_id
      and member.user_id = v_user_id
  ) then
    raise exception 'Non fai parte di questa lega.';
  end if;

  if v_league.owner_id = v_user_id then
    raise exception
      'Il Presidente deve trasferire la presidenza prima di lasciare la lega.';
  end if;

  if v_league.competition_started_at is not null then
    raise exception
      'La competizione è iniziata: i partecipanti sono bloccati.';
  end if;

  select team.id, team.name
  into v_team_id, v_team_name
  from public.fantasy_teams team
  where team.league_id = p_league_id
    and team.manager_id = v_user_id
  for update;

  if v_team_id is not null and exists (
    select 1
    from public.auction_items item
    join public.auctions auction on auction.id = item.auction_id
    where auction.league_id = p_league_id
      and item.status = 'bidding'
      and (
        item.nominated_by_team_id = v_team_id
        or exists (
          select 1
          from public.bids bid
          where bid.auction_item_id = item.id
            and bid.fantasy_team_id = v_team_id
        )
      )
  ) then
    raise exception
      'Chiudi o annulla la chiamata d''asta in corso prima di lasciare la lega.';
  end if;

  if v_team_id is not null then
    -- La composizione dello spogliatoio è cambiata: calendario e distinte
    -- pre-campionato non sono più validi per nessuna squadra.
    delete from public.lineups lineup
    using public.fantasy_teams team
    where lineup.fantasy_team_id = team.id
      and team.league_id = p_league_id;

    delete from public.fantasy_fixtures
    where league_id = p_league_id;

    delete from public.trade_offers
    where proposer_team_id = v_team_id
      or recipient_team_id = v_team_id;

    update public.auction_items item
    set
      status = 'unsold',
      winning_team_id = null,
      winning_price = null
    from public.auctions auction
    where auction.id = item.auction_id
      and auction.league_id = p_league_id
      and item.winning_team_id = v_team_id;

    update public.auction_items item
    set nominated_by_team_id = null
    from public.auctions auction
    where auction.id = item.auction_id
      and auction.league_id = p_league_id
      and item.nominated_by_team_id = v_team_id;

    delete from public.bids
    where fantasy_team_id = v_team_id;

    delete from public.team_transactions
    where fantasy_team_id = v_team_id;

    delete from public.roster_entries
    where fantasy_team_id = v_team_id;

    delete from public.fantasy_teams
    where id = v_team_id;
  end if;

  delete from public.user_notifications
  where user_id = v_user_id
    and league_id = p_league_id;

  delete from public.league_members
  where league_id = p_league_id
    and user_id = v_user_id;

  perform public.create_user_notification(
    v_league.owner_id,
    p_league_id,
    'league',
    'Partecipante uscito',
    coalesce(v_team_name, 'Una squadra') ||
      ' ha lasciato la lega. Il posto è di nuovo disponibile.',
    'league',
    jsonb_build_object(
      'event', 'league_member_left',
      'user_id', v_user_id,
      'team_name', v_team_name
    ),
    'member-left:' || p_league_id::text || ':' ||
      v_user_id::text || ':' || pg_catalog.clock_timestamp()::text
  );

  return true;
end;
$$;

revoke all on function public.update_my_team_name(uuid, text)
from public, anon;
grant execute on function public.update_my_team_name(uuid, text)
to authenticated;

revoke all on function public.leave_league(uuid)
from public, anon;
grant execute on function public.leave_league(uuid)
to authenticated;

select
  to_regprocedure(
    'public.update_my_team_name(uuid,text)'
  ) is not null as team_name_ready,
  to_regprocedure(
    'public.leave_league(uuid)'
  ) is not null as leave_league_ready,
  coalesce((select procedure.prosecdef
    from pg_proc procedure
    where procedure.oid =
      to_regprocedure('public.update_my_team_name(uuid,text)')
  ), false) as team_name_security_ready,
  coalesce((select procedure.prosecdef
    from pg_proc procedure
    where procedure.oid =
      to_regprocedure('public.leave_league(uuid)')
  ), false) as leave_security_ready,
  has_function_privilege(
    'authenticated',
    'public.update_my_team_name(uuid,text)',
    'execute'
  ) as authenticated_team_name_ready,
  has_function_privilege(
    'authenticated',
    'public.leave_league(uuid)',
    'execute'
  ) as authenticated_leave_ready,
  not has_function_privilege(
    'anon',
    'public.update_my_team_name(uuid,text)',
    'execute'
  ) as anonymous_team_name_blocked,
  not has_function_privilege(
    'anon',
    'public.leave_league(uuid)',
    'execute'
  ) as anonymous_leave_blocked;
