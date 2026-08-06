-- LEGHEVO · rimozione sicura dei partecipanti prima del campionato
-- Eseguire nel SQL Editor di Supabase dopo 023.

create or replace function public.remove_league_member(
  p_league_id uuid,
  p_user_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_league public.leagues%rowtype;
  v_team_id uuid;
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
    raise exception 'Solo il Presidente può rimuovere un partecipante.';
  end if;

  if v_league.competition_started_at is not null then
    raise exception 'La competizione è iniziata: i partecipanti sono bloccati.';
  end if;

  if p_user_id = v_league.owner_id then
    raise exception 'Il Presidente non può essere rimosso.';
  end if;

  if p_user_id = auth.uid() then
    raise exception 'Non puoi espellere te stesso.';
  end if;

  if not exists (
    select 1
    from public.league_members member
    where member.league_id = p_league_id
      and member.user_id = p_user_id
  ) then
    raise exception 'Partecipante non trovato.';
  end if;

  select team.id
  into v_team_id
  from public.fantasy_teams team
  where team.league_id = p_league_id
    and team.manager_id = p_user_id
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
      'Chiudi o annulla la chiamata d''asta in corso prima di rimuovere il partecipante.';
  end if;

  if v_team_id is not null then
    -- Un calendario costruito con una squadra in uscita non è più valido.
    delete from public.lineups lineup
    using public.fantasy_teams team
    where lineup.fantasy_team_id = team.id
      and team.league_id = p_league_id;

    delete from public.fantasy_fixtures
    where league_id = p_league_id;

    -- Annulla eventuali scambi ancora collegati alla squadra.
    delete from public.trade_offers
    where proposer_team_id = v_team_id
      or recipient_team_id = v_team_id;

    -- Un acquisto della squadra espulsa torna disponibile per l'asta.
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
  where user_id = p_user_id
    and league_id = p_league_id;

  delete from public.league_members
  where league_id = p_league_id
    and user_id = p_user_id;

  perform public.create_user_notification(
    p_user_id,
    p_league_id,
    'league',
    'Uscita dalla lega',
    'Il Presidente ti ha rimosso dalla lega. Puoi rientrare finché gli inviti restano aperti.',
    'home',
    jsonb_build_object('event', 'league_member_removed'),
    'member-removed:' || p_league_id::text || ':' || p_user_id::text
  );

  return true;
end;
$$;

revoke all on function public.remove_league_member(uuid, uuid)
from public, anon;
grant execute on function public.remove_league_member(uuid, uuid)
to authenticated;

select
  to_regprocedure(
    'public.remove_league_member(uuid,uuid)'
  ) is not null as member_removal_ready,
  coalesce((
    select procedure.prosecdef
    from pg_proc procedure
    where procedure.oid =
      to_regprocedure('public.remove_league_member(uuid,uuid)')
  ), false) as security_definer_ready,
  coalesce(
    pg_get_functiondef(
      to_regprocedure('public.remove_league_member(uuid,uuid)')
    ) ilike '%v_league.owner_id <> auth.uid()%',
    false
  ) as president_only_ready,
  coalesce(
    pg_get_functiondef(
      to_regprocedure('public.remove_league_member(uuid,uuid)')
    ) ilike '%delete from public.bids%',
    false
  ) as preseason_cleanup_ready,
  has_function_privilege(
    'authenticated',
    'public.remove_league_member(uuid,uuid)',
    'execute'
  ) as authenticated_execute_ready,
  not has_function_privilege(
    'anon',
    'public.remove_league_member(uuid,uuid)',
    'execute'
  ) as anonymous_blocked;
