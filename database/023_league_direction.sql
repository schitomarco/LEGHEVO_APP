-- LEGHEVO · direzione completa della lega
-- Eseguire nel SQL Editor di Supabase dopo 022.

alter table public.leagues
  add column if not exists invites_open boolean not null default true,
  add column if not exists competition_started_at timestamptz;

create or replace function public.join_league_by_code(
  p_invite_code text,
  p_team_name text
)
returns public.leagues
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_league public.leagues%rowtype;
  v_member_count integer;
begin
  if v_user_id is null then
    raise exception 'Devi effettuare l''accesso.';
  end if;

  if nullif(trim(p_invite_code), '') is null then
    raise exception 'Il codice invito è obbligatorio.';
  end if;

  if nullif(trim(p_team_name), '') is null then
    raise exception 'Il nome della squadra è obbligatorio.';
  end if;

  select league.*
  into v_league
  from public.leagues league
  where league.invite_code = upper(trim(p_invite_code))
  for update;

  if not found then
    raise exception 'Codice invito non valido.';
  end if;

  if not v_league.invites_open then
    raise exception 'Gli inviti di questa lega sono chiusi.';
  end if;

  if v_league.competition_started_at is not null
    or v_league.status in ('completed', 'archived') then
    raise exception 'Questa lega non accetta più partecipanti.';
  end if;

  if exists (
    select 1
    from public.league_members member
    where member.league_id = v_league.id
      and member.user_id = v_user_id
  ) then
    if not exists (
      select 1
      from public.fantasy_teams team
      where team.league_id = v_league.id
        and team.manager_id = v_user_id
    ) then
      insert into public.fantasy_teams (
        league_id,
        manager_id,
        name,
        credits_remaining
      )
      values (
        v_league.id,
        v_user_id,
        trim(p_team_name),
        v_league.starting_credits
      );
    end if;

    return v_league;
  end if;

  select count(*)
  into v_member_count
  from public.league_members member
  where member.league_id = v_league.id;

  if v_member_count >= v_league.team_limit then
    raise exception 'La lega è al completo.';
  end if;

  insert into public.league_members (league_id, user_id, role)
  values (v_league.id, v_user_id, 'manager');

  insert into public.fantasy_teams (
    league_id,
    manager_id,
    name,
    credits_remaining
  )
  values (
    v_league.id,
    v_user_id,
    trim(p_team_name),
    v_league.starting_credits
  );

  return v_league;
end;
$$;

create or replace function public.get_league_management_state(
  p_league_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_league public.leagues%rowtype;
  v_member_count integer;
  v_team_count integer;
  v_full_roster_count integer;
  v_fixture_count integer;
  v_members_ready boolean;
  v_teams_ready boolean;
  v_rosters_ready boolean;
  v_calendar_ready boolean;
begin
  if auth.uid() is null then
    raise exception 'Devi effettuare l''accesso.';
  end if;

  if not public.is_league_admin(p_league_id) then
    raise exception 'Solo la direzione della lega può vedere questi controlli.';
  end if;

  select league.*
  into v_league
  from public.leagues league
  where league.id = p_league_id;

  if not found then
    raise exception 'Lega non trovata.';
  end if;

  select count(*)::integer
  into v_member_count
  from public.league_members member
  where member.league_id = p_league_id;

  select count(*)::integer
  into v_team_count
  from public.fantasy_teams team
  where team.league_id = p_league_id;

  select count(*)::integer
  into v_full_roster_count
  from public.fantasy_teams team
  where team.league_id = p_league_id
    and (
      select count(*)
      from public.roster_entries roster
      where roster.fantasy_team_id = team.id
        and roster.released_at is null
    ) = v_league.roster_size;

  select count(*)::integer
  into v_fixture_count
  from public.fantasy_fixtures fixture
  where fixture.league_id = p_league_id;

  v_members_ready := v_member_count = v_league.team_limit;
  v_teams_ready :=
    v_team_count = v_league.team_limit
    and v_team_count = v_member_count;
  v_rosters_ready := v_full_roster_count = v_league.team_limit;
  v_calendar_ready := v_fixture_count > 0;

  return jsonb_build_object(
    'memberCount', v_member_count,
    'teamLimit', v_league.team_limit,
    'teamCount', v_team_count,
    'fullRosterCount', v_full_roster_count,
    'rosterSize', v_league.roster_size,
    'fixtureCount', v_fixture_count,
    'invitesOpen', v_league.invites_open,
    'competitionStartedAt', v_league.competition_started_at,
    'isOwner', v_league.owner_id = auth.uid(),
    'checks', jsonb_build_object(
      'membersReady', v_members_ready,
      'teamsReady', v_teams_ready,
      'rostersReady', v_rosters_ready,
      'calendarReady', v_calendar_ready
    ),
    'canStart',
      v_league.competition_started_at is null
      and v_members_ready
      and v_teams_ready
      and v_rosters_ready
      and v_calendar_ready
  );
end;
$$;

create or replace function public.set_league_invites_open(
  p_league_id uuid,
  p_open boolean
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_league public.leagues%rowtype;
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
    raise exception 'Solo il Presidente può aprire o chiudere gli inviti.';
  end if;

  if v_league.competition_started_at is not null and p_open then
    raise exception 'La competizione è già iniziata: gli inviti restano chiusi.';
  end if;

  update public.leagues
  set
    invites_open = p_open,
    updated_at = now()
  where id = p_league_id;

  return p_open;
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
  v_league public.leagues%rowtype;
  v_invite_code text;
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
    raise exception 'Solo il Presidente può cambiare il codice invito.';
  end if;

  if v_league.competition_started_at is not null then
    raise exception 'La competizione è iniziata: il codice invito è bloccato.';
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

  return v_invite_code;
end;
$$;

create or replace function public.transfer_league_presidency(
  p_league_id uuid,
  p_new_owner_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_league public.leagues%rowtype;
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
    raise exception 'Solo il Presidente attuale può trasferire la presidenza.';
  end if;

  if p_new_owner_id = auth.uid() then
    raise exception 'Sei già il Presidente della lega.';
  end if;

  if not exists (
    select 1
    from public.league_members member
    join public.profiles profile on profile.id = member.user_id
    where member.league_id = p_league_id
      and member.user_id = p_new_owner_id
      and profile.deleted_at is null
  ) then
    raise exception 'Il nuovo Presidente deve essere un partecipante attivo.';
  end if;

  update public.league_members
  set role = 'admin'
  where league_id = p_league_id
    and user_id in (auth.uid(), p_new_owner_id);

  update public.leagues
  set
    owner_id = p_new_owner_id,
    updated_at = now()
  where id = p_league_id;

  perform public.create_user_notification(
    p_new_owner_id,
    p_league_id,
    'league',
    'Sei il nuovo Presidente',
    'La presidenza della lega è passata a te. Adesso il VAR è nelle tue mani.',
    'league',
    jsonb_build_object('event', 'presidency_transferred'),
    'presidency:' || p_league_id::text || ':' || p_new_owner_id::text
  );

  return true;
end;
$$;

create or replace function public.start_league_competition(
  p_league_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_league public.leagues%rowtype;
  v_state jsonb;
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
    raise exception 'Solo il Presidente può avviare la competizione.';
  end if;

  if v_league.competition_started_at is not null then
    return true;
  end if;

  v_state := public.get_league_management_state(p_league_id);

  if not (v_state -> 'checks' ->> 'membersReady')::boolean then
    raise exception 'Lo spogliatoio non è ancora completo.';
  end if;

  if not (v_state -> 'checks' ->> 'teamsReady')::boolean then
    raise exception 'Ogni partecipante deve avere una squadra.';
  end if;

  if not (v_state -> 'checks' ->> 'rostersReady')::boolean then
    raise exception 'Tutte le rose devono essere complete.';
  end if;

  if not (v_state -> 'checks' ->> 'calendarReady')::boolean then
    raise exception 'Genera il calendario prima di iniziare.';
  end if;

  update public.leagues
  set
    status = 'active',
    invites_open = false,
    competition_started_at = now(),
    updated_at = now()
  where id = p_league_id;

  return true;
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

revoke all on function public.join_league_by_code(text, text) from public;
revoke all on function public.get_league_management_state(uuid) from public;
revoke all on function public.set_league_invites_open(uuid, boolean) from public;
revoke all on function public.regenerate_league_invite_code(uuid) from public;
revoke all on function public.transfer_league_presidency(uuid, uuid) from public;
revoke all on function public.start_league_competition(uuid) from public;
revoke all on function public.remove_league_member(uuid, uuid) from public;

grant execute on function public.join_league_by_code(text, text)
to authenticated;
grant execute on function public.get_league_management_state(uuid)
to authenticated;
grant execute on function public.set_league_invites_open(uuid, boolean)
to authenticated;
grant execute on function public.regenerate_league_invite_code(uuid)
to authenticated;
grant execute on function public.transfer_league_presidency(uuid, uuid)
to authenticated;
grant execute on function public.start_league_competition(uuid)
to authenticated;
grant execute on function public.remove_league_member(uuid, uuid)
to authenticated;

select
  exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'leagues'
      and column_name = 'invites_open'
  ) as invites_control_ready,
  exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'leagues'
      and column_name = 'competition_started_at'
  ) as competition_marker_ready,
  to_regprocedure(
    'public.get_league_management_state(uuid)'
  ) is not null as readiness_checks_ready,
  to_regprocedure(
    'public.set_league_invites_open(uuid,boolean)'
  ) is not null as invite_switch_ready,
  to_regprocedure(
    'public.transfer_league_presidency(uuid,uuid)'
  ) is not null as presidency_transfer_ready,
  to_regprocedure(
    'public.start_league_competition(uuid)'
  ) is not null as competition_start_ready,
  to_regprocedure(
    'public.join_league_by_code(text,text)'
  ) is not null as protected_join_ready,
  to_regprocedure(
    'public.remove_league_member(uuid,uuid)'
  ) is not null as protected_removal_ready;
