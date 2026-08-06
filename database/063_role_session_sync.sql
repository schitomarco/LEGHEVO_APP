-- LEGHEVO · sincronizzazione sessione e revoca permessi in tempo reale
-- Eseguire nel SQL Editor di Supabase dopo 062.
-- Script idempotente: non modifica rose, crediti, calendario o risultati.

alter table public.leagues
  add column if not exists role_revision bigint not null default 1;

alter table public.league_members
  add column if not exists role_updated_at timestamptz not null default now();

-- Per gli eventi DELETE Realtime deve conservare league_id e user_id.
alter table public.league_members replica identity full;

create or replace function public.touch_league_member_role_timestamp()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.role is distinct from old.role then
    new.role_updated_at := now();
  end if;
  return new;
end;
$$;

drop trigger if exists league_members_role_timestamp on public.league_members;
create trigger league_members_role_timestamp
before update of role on public.league_members
for each row execute function public.touch_league_member_role_timestamp();

create or replace function public.bump_league_role_revision_from_member()
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

  if tg_op = 'UPDATE' and new.role is not distinct from old.role then
    return new;
  end if;

  update public.leagues
  set
    role_revision = role_revision + 1,
    updated_at = now()
  where id = v_league_id;

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

drop trigger if exists league_members_role_revision on public.league_members;
create trigger league_members_role_revision
after insert or delete or update of role on public.league_members
for each row execute function public.bump_league_role_revision_from_member();

create or replace function public.bump_league_role_revision_from_owner()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.owner_id is distinct from old.owner_id then
    new.role_revision := old.role_revision + 1;
    new.updated_at := now();
  end if;
  return new;
end;
$$;

drop trigger if exists leagues_owner_role_revision on public.leagues;
create trigger leagues_owner_role_revision
before update of owner_id on public.leagues
for each row execute function public.bump_league_role_revision_from_owner();

-- Questa RPC resta leggibile anche da un utente appena rimosso: restituisce
-- esclusivamente il suo stato di accesso, così il client può chiudere subito
-- le aree riservate senza conservare privilegi obsoleti in memoria.
create or replace function public.get_league_access_session(
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
  v_member_role public.member_role;
  v_role_updated_at timestamptz;
  v_is_owner boolean := false;
  v_is_member boolean := false;
  v_permissions jsonb;
begin
  if v_user_id is null then
    raise exception 'Devi effettuare l''accesso.';
  end if;

  select league.*
  into v_league
  from public.leagues league
  where league.id = p_league_id;

  if not found then
    return jsonb_build_object(
      'accessValid', false,
      'reason', 'league_missing',
      'revision', 0,
      'roleUpdatedAt', null,
      'permissions', jsonb_build_object(
        'role', 'none',
        'isMember', false,
        'isOwner', false,
        'isAdmin', false,
        'hasTeam', false,
        'canAccessDirection', false,
        'canRunOperations', false,
        'canEditRules', false,
        'canManageInvites', false,
        'canManageMembers', false,
        'canManageAdmins', false,
        'canTransferPresidency', false,
        'canStartCompetition', false,
        'canCloseSeason', false,
        'canSubmitLineup', false,
        'canUseMarket', false
      )
    );
  end if;

  select member.role, member.role_updated_at
  into v_member_role, v_role_updated_at
  from public.league_members member
  join public.profiles profile on profile.id = member.user_id
  where member.league_id = p_league_id
    and member.user_id = v_user_id
    and profile.deleted_at is null;

  v_is_owner := v_league.owner_id = v_user_id;
  v_is_member := v_is_owner or v_member_role is not null;

  if v_is_member then
    v_permissions := public.get_league_permission_state(p_league_id);
  else
    v_permissions := jsonb_build_object(
      'role', 'none',
      'isMember', false,
      'isOwner', false,
      'isAdmin', false,
      'hasTeam', false,
      'canAccessDirection', false,
      'canRunOperations', false,
      'canEditRules', false,
      'canManageInvites', false,
      'canManageMembers', false,
      'canManageAdmins', false,
      'canTransferPresidency', false,
      'canStartCompetition', false,
      'canCloseSeason', false,
      'canSubmitLineup', false,
      'canUseMarket', false
    );
  end if;

  return jsonb_build_object(
    'accessValid', v_is_member,
    'reason', case when v_is_member then null else 'membership_revoked' end,
    'revision', v_league.role_revision,
    'roleUpdatedAt', coalesce(v_role_updated_at, v_league.updated_at),
    'permissions', v_permissions
  );
end;
$$;

create or replace function public.get_league_management_state_v6(
  p_league_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_access jsonb;
  v_state jsonb;
begin
  v_access := public.get_league_access_session(p_league_id);

  if not coalesce((v_access ->> 'accessValid')::boolean, false) then
    raise exception 'Accesso alla lega revocato.';
  end if;

  if not coalesce(
    (v_access -> 'permissions' ->> 'canAccessDirection')::boolean,
    false
  ) then
    raise exception 'Non hai più accesso alla Direzione Lega.';
  end if;

  v_state := public.get_league_management_state_v5(p_league_id);
  return v_state || jsonb_build_object('accessSession', v_access);
end;
$$;

-- Pubblicazione Realtime necessaria per propagare nomine, revoche e
-- trasferimenti di presidenza agli altri dispositivi già aperti.
do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'league_members'
  ) then
    alter publication supabase_realtime add table public.league_members;
  end if;

  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'leagues'
  ) then
    alter publication supabase_realtime add table public.leagues;
  end if;

  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'league_role_events'
  ) then
    alter publication supabase_realtime add table public.league_role_events;
  end if;
end;
$$;

revoke all on function public.get_league_access_session(uuid)
  from public, anon;
revoke all on function public.get_league_management_state_v6(uuid)
  from public, anon;
revoke all on function public.touch_league_member_role_timestamp()
  from public, anon;
revoke all on function public.bump_league_role_revision_from_member()
  from public, anon;
revoke all on function public.bump_league_role_revision_from_owner()
  from public, anon;

grant execute on function public.get_league_access_session(uuid)
  to authenticated;
grant execute on function public.get_league_management_state_v6(uuid)
  to authenticated;

-- Controllo finale: tutti i valori devono risultare true.
select
  exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'leagues'
      and column_name = 'role_revision'
  ) as role_revision_column_ready,
  exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'league_members'
      and column_name = 'role_updated_at'
  ) as role_timestamp_column_ready,
  to_regprocedure('public.get_league_access_session(uuid)') is not null
    as access_session_ready,
  to_regprocedure('public.get_league_management_state_v6(uuid)') is not null
    as management_v6_ready,
  exists (
    select 1 from pg_trigger
    where tgname = 'league_members_role_timestamp'
      and not tgisinternal
  ) as member_timestamp_trigger_ready,
  exists (
    select 1 from pg_trigger
    where tgname = 'league_members_role_revision'
      and not tgisinternal
  ) as member_revision_trigger_ready,
  exists (
    select 1 from pg_trigger
    where tgname = 'leagues_owner_role_revision'
      and not tgisinternal
  ) as owner_revision_trigger_ready,
  exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'league_role_events'
  ) as role_events_realtime_ready,
  exists (
    select 1 from pg_class
    where oid = 'public.league_members'::regclass
      and relreplident = 'f'
  ) as member_delete_payload_ready,
  has_function_privilege(
    'authenticated',
    'public.get_league_access_session(uuid)',
    'execute'
  ) as authenticated_access_ready,
  not has_function_privilege(
    'anon',
    'public.get_league_access_session(uuid)',
    'execute'
  ) as anonymous_access_blocked,
  coalesce(
    pg_get_functiondef(
      to_regprocedure('public.get_league_management_state_v6(uuid)')
    ) ilike '%canAccessDirection%',
    false
  ) as stale_direction_access_blocked;
