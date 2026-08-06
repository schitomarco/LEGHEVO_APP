-- LEGHEVO · ruoli, permessi e audit della direzione
-- Eseguire nel SQL Editor di Supabase dopo 060.
-- Script idempotente: non modifica rose, crediti, calendario o risultati.

create table if not exists public.league_role_events (
  id uuid primary key default gen_random_uuid(),
  league_id uuid not null references public.leagues(id) on delete cascade,
  actor_id uuid references public.profiles(id),
  target_user_id uuid references public.profiles(id),
  event_type text not null check (
    event_type in (
      'admin_granted',
      'admin_revoked',
      'presidency_transferred'
    )
  ),
  previous_role public.member_role,
  new_role public.member_role,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists league_role_events_league_created_idx
  on public.league_role_events (league_id, created_at desc);

alter table public.league_role_events enable row level security;

drop policy if exists league_role_events_read_members
  on public.league_role_events;
create policy league_role_events_read_members
on public.league_role_events for select to authenticated
using (public.is_league_member(league_id) or public.is_league_admin(league_id));

-- Tutte le modifiche sensibili passano da RPC atomiche. In questo modo un
-- client modificato non può promuoversi, cambiare proprietario o alterare
-- direttamente squadre e partecipanti aggirando l'interfaccia dell'app.
drop policy if exists leagues_update_admin on public.leagues;
drop policy if exists members_add_by_admin on public.league_members;
drop policy if exists members_update_by_admin on public.league_members;
drop policy if exists members_remove_self_or_admin on public.league_members;
drop policy if exists teams_create_member on public.fantasy_teams;
drop policy if exists teams_update_manager_or_admin on public.fantasy_teams;
drop policy if exists teams_delete_admin on public.fantasy_teams;

create or replace function public.is_league_owner(p_league_id uuid)
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
      and league.owner_id = auth.uid()
  );
$$;

create or replace function public.get_league_permission_state(
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
  v_member public.league_members%rowtype;
  v_is_owner boolean := false;
  v_is_admin boolean := false;
  v_has_team boolean := false;
  v_role text;
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

  select member.*
  into v_member
  from public.league_members member
  where member.league_id = p_league_id
    and member.user_id = v_user_id;

  v_is_owner := v_league.owner_id = v_user_id;
  v_is_admin := v_is_owner or coalesce(v_member.role = 'admin', false);

  if not v_is_owner and v_member.user_id is null then
    raise exception 'Non fai parte di questa lega.';
  end if;

  select exists (
    select 1
    from public.fantasy_teams team
    where team.league_id = p_league_id
      and team.manager_id = v_user_id
  ) into v_has_team;

  v_role := case
    when v_is_owner then 'president'
    when v_is_admin then 'admin'
    else 'manager'
  end;

  return jsonb_build_object(
    'role', v_role,
    'isMember', true,
    'isOwner', v_is_owner,
    'isAdmin', v_is_admin,
    'hasTeam', v_has_team,
    'canAccessDirection', v_is_admin,
    'canRunOperations', v_is_admin,
    'canEditRules', v_is_admin,
    'canManageInvites', v_is_owner,
    'canManageMembers', v_is_owner,
    'canManageAdmins', v_is_owner,
    'canTransferPresidency',
      v_is_owner and v_league.competition_started_at is null,
    'canStartCompetition', v_is_owner,
    'canCloseSeason', v_is_owner,
    'canSubmitLineup', v_has_team,
    'canUseMarket', v_has_team
  );
end;
$$;

-- Soltanto il Presidente può nominare o revocare un Admin. Gli Admin
-- restano responsabili delle operazioni sportive, ma non possono modificare
-- la gerarchia della lega.
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
  v_previous_role public.member_role;
  v_event_type text;
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
    raise exception 'Solo il Presidente può gestire gli amministratori.';
  end if;

  if v_league.competition_started_at is not null then
    raise exception 'La competizione è iniziata: i ruoli sono bloccati.';
  end if;

  if p_user_id = v_league.owner_id then
    raise exception 'Il Presidente mantiene sempre i pieni poteri.';
  end if;

  if p_user_id = auth.uid() then
    raise exception 'Non puoi modificare il tuo stesso ruolo.';
  end if;

  select member.role
  into v_previous_role
  from public.league_members member
  join public.profiles profile on profile.id = member.user_id
  where member.league_id = p_league_id
    and member.user_id = p_user_id
    and profile.deleted_at is null
  for update of member;

  if not found then
    raise exception 'Partecipante non trovato.';
  end if;

  if v_previous_role = p_role then
    select member.*
    into v_member
    from public.league_members member
    where member.league_id = p_league_id
      and member.user_id = p_user_id;
    return v_member;
  end if;

  update public.league_members
  set role = p_role
  where league_id = p_league_id
    and user_id = p_user_id
  returning * into v_member;

  v_event_type := case
    when p_role = 'admin' then 'admin_granted'
    else 'admin_revoked'
  end;

  insert into public.league_role_events (
    league_id,
    actor_id,
    target_user_id,
    event_type,
    previous_role,
    new_role
  ) values (
    p_league_id,
    auth.uid(),
    p_user_id,
    v_event_type,
    v_previous_role,
    p_role
  );

  perform public.create_user_notification(
    p_user_id,
    p_league_id,
    'league',
    case when p_role = 'admin' then 'Sei stato nominato Admin'
         else 'Ruolo Admin revocato' end,
    case when p_role = 'admin'
      then 'Ora puoi gestire le operazioni sportive della lega insieme al Presidente.'
      else 'Continui a partecipare alla lega come Mister della tua squadra.' end,
    'league',
    jsonb_build_object(
      'event', v_event_type,
      'previousRole', v_previous_role,
      'newRole', p_role
    ),
    null
  );

  return v_member;
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
  v_previous_role public.member_role;
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

  if v_league.competition_started_at is not null then
    raise exception 'La competizione è iniziata: la presidenza è bloccata.';
  end if;

  if p_new_owner_id = auth.uid() then
    raise exception 'Sei già il Presidente della lega.';
  end if;

  select member.role
  into v_previous_role
  from public.league_members member
  join public.profiles profile on profile.id = member.user_id
  where member.league_id = p_league_id
    and member.user_id = p_new_owner_id
    and profile.deleted_at is null
  for update of member;

  if not found then
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

  insert into public.league_role_events (
    league_id,
    actor_id,
    target_user_id,
    event_type,
    previous_role,
    new_role,
    metadata
  ) values (
    p_league_id,
    auth.uid(),
    p_new_owner_id,
    'presidency_transferred',
    v_previous_role,
    'admin',
    jsonb_build_object('previousOwnerId', auth.uid())
  );

  perform public.create_user_notification(
    p_new_owner_id,
    p_league_id,
    'league',
    'Sei il nuovo Presidente',
    'La presidenza della lega è passata a te. Adesso il VAR è nelle tue mani.',
    'league',
    jsonb_build_object('event', 'presidency_transferred'),
    null
  );

  perform public.create_user_notification(
    auth.uid(),
    p_league_id,
    'league',
    'Presidenza trasferita',
    'Resti nella direzione della lega con il ruolo di Admin.',
    'league',
    jsonb_build_object(
      'event', 'presidency_transferred_out',
      'newOwnerId', p_new_owner_id
    ),
    null
  );

  return true;
end;
$$;

create or replace function public.get_league_management_state_v4(
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
begin
  v_state := public.get_league_management_state_v3(p_league_id);
  return v_state || jsonb_build_object(
    'permissions', public.get_league_permission_state(p_league_id)
  );
end;
$$;

revoke all on function public.is_league_owner(uuid) from public, anon;
revoke all on function public.get_league_permission_state(uuid) from public, anon;
revoke all on function public.get_league_management_state_v4(uuid) from public, anon;
revoke all on function public.set_league_member_role(
  uuid, uuid, public.member_role
) from public, anon;
revoke all on function public.transfer_league_presidency(uuid, uuid)
from public, anon;

grant execute on function public.is_league_owner(uuid) to authenticated;
grant execute on function public.get_league_permission_state(uuid)
  to authenticated;
grant execute on function public.get_league_management_state_v4(uuid)
  to authenticated;
grant execute on function public.set_league_member_role(
  uuid, uuid, public.member_role
) to authenticated;
grant execute on function public.transfer_league_presidency(uuid, uuid)
  to authenticated;

-- Controllo finale: tutti i valori devono risultare true.
select
  to_regclass('public.league_role_events') is not null
    as role_audit_table_ready,
  to_regprocedure('public.is_league_owner(uuid)') is not null
    as owner_check_ready,
  to_regprocedure('public.get_league_permission_state(uuid)') is not null
    as permission_state_ready,
  to_regprocedure('public.get_league_management_state_v4(uuid)') is not null
    as management_v4_ready,
  coalesce(
    pg_get_functiondef(
      to_regprocedure(
        'public.set_league_member_role(uuid,uuid,public.member_role)'
      )
    ) ilike '%v_league.owner_id <> auth.uid()%',
    false
  ) as president_controls_admins_ready,
  coalesce(
    pg_get_functiondef(
      to_regprocedure('public.transfer_league_presidency(uuid,uuid)')
    ) ilike '%competition_started_at is not null%',
    false
  ) as presidency_lock_ready,
  not exists (
    select 1
    from pg_policies policy
    where policy.schemaname = 'public'
      and policy.tablename = 'league_members'
      and policy.cmd in ('INSERT', 'UPDATE', 'DELETE')
  ) as direct_member_writes_blocked,
  not exists (
    select 1
    from pg_policies policy
    where policy.schemaname = 'public'
      and policy.tablename = 'leagues'
      and policy.cmd = 'UPDATE'
  ) as direct_league_updates_blocked,
  has_function_privilege(
    'authenticated',
    'public.get_league_management_state_v4(uuid)',
    'execute'
  ) as authenticated_management_ready,
  not has_function_privilege(
    'anon',
    'public.get_league_management_state_v4(uuid)',
    'execute'
  ) as anonymous_management_blocked;
