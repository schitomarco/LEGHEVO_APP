-- LEGHEVO · gestione partecipanti, amministratori e codice invito
-- Eseguire nel SQL Editor di Supabase dopo 012.

create or replace function public.set_league_member_role(
  p_league_id uuid,
  p_user_id uuid,
  p_role public.member_role
)
returns public.league_members
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_league public.leagues%rowtype;
  v_member public.league_members%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Devi effettuare l''accesso.';
  end if;

  if not public.is_league_admin(p_league_id) then
    raise exception 'Solo il Presidente può gestire i ruoli.';
  end if;

  select league.*
  into v_league
  from public.leagues league
  where league.id = p_league_id;

  if not found then
    raise exception 'Lega non trovata.';
  end if;

  if p_user_id = v_league.owner_id then
    raise exception 'Il fondatore della lega deve restare Presidente.';
  end if;

  if p_user_id = auth.uid() then
    raise exception 'Non puoi modificare il tuo stesso ruolo.';
  end if;

  update public.league_members
  set role = p_role
  where league_id = p_league_id
    and user_id = p_user_id
  returning * into v_member;

  if not found then
    raise exception 'Partecipante non trovato.';
  end if;

  return v_member;
end;
$$;

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

  if not public.is_league_admin(p_league_id) then
    raise exception 'Solo il Presidente può rimuovere un partecipante.';
  end if;

  select league.*
  into v_league
  from public.leagues league
  where league.id = p_league_id
  for update;

  if not found then
    raise exception 'Lega non trovata.';
  end if;

  if p_user_id = v_league.owner_id then
    raise exception 'Il fondatore della lega non può essere rimosso.';
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
    and team.manager_id = p_user_id;

  if v_team_id is not null and (
    exists (
      select 1
      from public.roster_entries roster
      where roster.fantasy_team_id = v_team_id
    )
    or exists (
      select 1
      from public.bids bid
      where bid.fantasy_team_id = v_team_id
    )
    or exists (
      select 1
      from public.lineups lineup
      where lineup.fantasy_team_id = v_team_id
    )
    or exists (
      select 1
      from public.fantasy_fixtures fixture
      where fixture.home_team_id = v_team_id
        or fixture.away_team_id = v_team_id
    )
    or exists (
      select 1
      from public.team_transactions transaction_row
      where transaction_row.fantasy_team_id = v_team_id
    )
    or exists (
      select 1
      from public.auction_items item
      where item.nominated_by_team_id = v_team_id
        or item.winning_team_id = v_team_id
    )
    or exists (
      select 1
      from public.trade_offers offer
      where offer.proposer_team_id = v_team_id
        or offer.recipient_team_id = v_team_id
    )
  ) then
    raise exception
      'Questo partecipante ha già attività nella lega e non può essere rimosso.';
  end if;

  if v_team_id is not null then
    delete from public.fantasy_teams
    where id = v_team_id;
  end if;

  delete from public.league_members
  where league_id = p_league_id
    and user_id = p_user_id;

  return true;
end;
$$;

create or replace function public.regenerate_league_invite_code(
  p_league_id uuid
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_invite_code text;
begin
  if auth.uid() is null then
    raise exception 'Devi effettuare l''accesso.';
  end if;

  if not public.is_league_admin(p_league_id) then
    raise exception 'Solo il Presidente può cambiare il codice invito.';
  end if;

  loop
    v_invite_code :=
      upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 10));

    exit when not exists (
      select 1
      from public.leagues league
      where league.invite_code = v_invite_code
    );
  end loop;

  update public.leagues
  set
    invite_code = v_invite_code,
    updated_at = now()
  where id = p_league_id;

  if not found then
    raise exception 'Lega non trovata.';
  end if;

  return v_invite_code;
end;
$$;

revoke all on function public.set_league_member_role(
  uuid,
  uuid,
  public.member_role
) from public;
revoke all on function public.remove_league_member(uuid, uuid)
from public;
revoke all on function public.regenerate_league_invite_code(uuid)
from public;

grant execute on function public.set_league_member_role(
  uuid,
  uuid,
  public.member_role
) to authenticated;
grant execute on function public.remove_league_member(uuid, uuid)
to authenticated;
grant execute on function public.regenerate_league_invite_code(uuid)
to authenticated;

select
  to_regprocedure(
    'public.set_league_member_role(uuid,uuid,public.member_role)'
  ) is not null as member_roles_ready,
  to_regprocedure(
    'public.remove_league_member(uuid,uuid)'
  ) is not null as member_removal_ready,
  to_regprocedure(
    'public.regenerate_league_invite_code(uuid)'
  ) is not null as invite_rotation_ready;
