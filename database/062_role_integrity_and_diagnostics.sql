-- LEGHEVO · integrità dei ruoli e diagnostica multi-account
-- Eseguire nel SQL Editor di Supabase dopo 061.
-- Script idempotente: non modifica rose, crediti, calendario o risultati.

create or replace function public.get_league_role_integrity(
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
  v_admin_count integer := 0;
  v_team_count integer := 0;
  v_orphan_team_count integer := 0;
  v_duplicate_team_manager_count integer := 0;
  v_owner_member_exists boolean := false;
  v_owner_profile_active boolean := false;
  v_healthy boolean := false;
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

  select count(*)::integer,
         count(*) filter (where member.role = 'admin')::integer
  into v_member_count, v_admin_count
  from public.league_members member
  join public.profiles profile on profile.id = member.user_id
  where member.league_id = p_league_id
    and profile.deleted_at is null;

  select exists (
    select 1
    from public.league_members member
    where member.league_id = p_league_id
      and member.user_id = v_league.owner_id
  ) into v_owner_member_exists;

  select exists (
    select 1
    from public.profiles profile
    where profile.id = v_league.owner_id
      and profile.deleted_at is null
  ) into v_owner_profile_active;

  select count(*)::integer
  into v_team_count
  from public.fantasy_teams team
  where team.league_id = p_league_id;

  select count(*)::integer
  into v_orphan_team_count
  from public.fantasy_teams team
  left join public.league_members member
    on member.league_id = team.league_id
   and member.user_id = team.manager_id
  where team.league_id = p_league_id
    and member.user_id is null;

  select count(*)::integer
  into v_duplicate_team_manager_count
  from (
    select team.manager_id
    from public.fantasy_teams team
    where team.league_id = p_league_id
    group by team.manager_id
    having count(*) > 1
  ) duplicates;

  v_healthy :=
    v_owner_member_exists
    and v_owner_profile_active
    and v_orphan_team_count = 0
    and v_duplicate_team_manager_count = 0;

  return jsonb_build_object(
    'healthy', v_healthy,
    'ownerMemberExists', v_owner_member_exists,
    'ownerProfileActive', v_owner_profile_active,
    'teamManagersAreMembers', v_orphan_team_count = 0,
    'oneTeamPerManager', v_duplicate_team_manager_count = 0,
    'memberCount', v_member_count,
    'adminCount', v_admin_count,
    'teamCount', v_team_count,
    'orphanTeamCount', v_orphan_team_count,
    'duplicateTeamManagerCount', v_duplicate_team_manager_count
  );
end;
$$;

create or replace function public.get_league_role_control_state(
  p_league_id uuid,
  p_event_limit integer default 10
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
  v_limit integer := greatest(1, least(coalesce(p_event_limit, 10), 30));
  v_events jsonb := '[]'::jsonb;
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

  select coalesce(jsonb_agg(event_row.payload order by event_row.created_at desc), '[]'::jsonb)
  into v_events
  from (
    select
      event.created_at,
      jsonb_build_object(
        'id', event.id,
        'type', event.event_type,
        'actorId', event.actor_id,
        'actorName', coalesce(actor.display_name, 'Account non disponibile'),
        'targetUserId', event.target_user_id,
        'targetName', coalesce(target.display_name, 'Account non disponibile'),
        'previousRole', event.previous_role,
        'newRole', event.new_role,
        'createdAt', event.created_at
      ) as payload
    from public.league_role_events event
    left join public.profiles actor on actor.id = event.actor_id
    left join public.profiles target on target.id = event.target_user_id
    where event.league_id = p_league_id
    order by event.created_at desc
    limit v_limit
  ) event_row;

  return jsonb_build_object(
    'integrity', public.get_league_role_integrity(p_league_id),
    'events', v_events
  );
end;
$$;

-- Il nuovo Presidente deve già essere un partecipante attivo della lega.
create or replace function public.enforce_league_owner_membership()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.owner_id is distinct from old.owner_id then
    if not exists (
      select 1
      from public.league_members member
      join public.profiles profile on profile.id = member.user_id
      where member.league_id = new.id
        and member.user_id = new.owner_id
        and profile.deleted_at is null
    ) then
      raise exception 'Il nuovo Presidente deve essere un partecipante attivo.';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists leagues_owner_membership_guard on public.leagues;
create trigger leagues_owner_membership_guard
before update of owner_id on public.leagues
for each row execute function public.enforce_league_owner_membership();

-- Nessuna scrittura, nemmeno privilegiata, può cancellare per errore il
-- Presidente dai partecipanti mentre la lega esiste.
create or replace function public.protect_current_league_owner_member()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if exists (
    select 1
    from public.leagues league
    where league.id = old.league_id
      and league.owner_id = old.user_id
  ) then
    raise exception 'Trasferisci prima la presidenza: il Presidente non può uscire dalla lega.';
  end if;
  return old;
end;
$$;

drop trigger if exists league_members_owner_delete_guard on public.league_members;
create trigger league_members_owner_delete_guard
before delete on public.league_members
for each row execute function public.protect_current_league_owner_member();

create or replace function public.get_league_management_state_v5(
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
  v_state := public.get_league_management_state_v4(p_league_id);
  return v_state || jsonb_build_object(
    'roleControl', public.get_league_role_control_state(p_league_id, 10)
  );
end;
$$;

revoke all on function public.get_league_role_integrity(uuid) from public, anon;
revoke all on function public.get_league_role_control_state(uuid, integer) from public, anon;
revoke all on function public.get_league_management_state_v5(uuid) from public, anon;
revoke all on function public.enforce_league_owner_membership() from public, anon;
revoke all on function public.protect_current_league_owner_member() from public, anon;

grant execute on function public.get_league_role_integrity(uuid) to authenticated;
grant execute on function public.get_league_role_control_state(uuid, integer) to authenticated;
grant execute on function public.get_league_management_state_v5(uuid) to authenticated;

-- Controllo finale: tutti i valori devono risultare true.
select
  to_regprocedure('public.get_league_role_integrity(uuid)') is not null
    as role_integrity_ready,
  to_regprocedure('public.get_league_role_control_state(uuid,integer)') is not null
    as role_control_state_ready,
  to_regprocedure('public.get_league_management_state_v5(uuid)') is not null
    as management_v5_ready,
  to_regprocedure('public.enforce_league_owner_membership()') is not null
    as owner_membership_guard_function_ready,
  to_regprocedure('public.protect_current_league_owner_member()') is not null
    as owner_delete_guard_function_ready,
  exists (
    select 1 from pg_trigger
    where tgname = 'leagues_owner_membership_guard'
      and not tgisinternal
  ) as owner_membership_trigger_ready,
  exists (
    select 1 from pg_trigger
    where tgname = 'league_members_owner_delete_guard'
      and not tgisinternal
  ) as owner_delete_trigger_ready,
  has_function_privilege(
    'authenticated',
    'public.get_league_management_state_v5(uuid)',
    'execute'
  ) as authenticated_management_ready,
  not has_function_privilege(
    'anon',
    'public.get_league_management_state_v5(uuid)',
    'execute'
  ) as anonymous_management_blocked,
  coalesce(
    pg_get_functiondef(
      to_regprocedure('public.get_league_role_integrity(uuid)')
    ) ilike '%teamManagersAreMembers%',
    false
  ) as orphan_team_check_ready,
  coalesce(
    pg_get_functiondef(
      to_regprocedure('public.get_league_role_integrity(uuid)')
    ) ilike '%oneTeamPerManager%',
    false
  ) as duplicate_team_check_ready,
  coalesce(
    pg_get_functiondef(
      to_regprocedure('public.get_league_role_control_state(uuid,integer)')
    ) ilike '%league_role_events%',
    false
  ) as role_audit_feed_ready;
