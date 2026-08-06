-- LEGHEVO · chiusura modello ruoli e matrice accessi
-- Eseguire nel SQL Editor di Supabase dopo 064.
-- Script idempotente: non modifica rose, crediti, calendario o risultati.

-- Le funzioni interne non devono essere richiamabili direttamente dal client.
-- Restano utilizzate esclusivamente dalle RPC protette con revisione.
revoke all on function public.set_league_member_role(
  uuid, uuid, public.member_role
) from public, anon, authenticated;
revoke all on function public.transfer_league_presidency(uuid, uuid)
  from public, anon, authenticated;
revoke all on function public.remove_league_member(uuid, uuid)
  from public, anon, authenticated;

create or replace function public.get_league_role_security_state(
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
  v_president_count integer := 0;
  v_admin_count integer := 0;
  v_manager_count integer := 0;
  v_matrix jsonb := '[]'::jsonb;
  v_direct_role_locked boolean;
  v_direct_presidency_locked boolean;
  v_direct_removal_locked boolean;
  v_guarded_actions_ready boolean;
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

  select
    count(*) filter (where member.user_id = v_league.owner_id)::integer,
    count(*) filter (
      where member.user_id <> v_league.owner_id
        and member.role = 'admin'
    )::integer,
    count(*) filter (
      where member.user_id <> v_league.owner_id
        and member.role = 'manager'
    )::integer
  into v_president_count, v_admin_count, v_manager_count
  from public.league_members member
  join public.profiles profile on profile.id = member.user_id
  where member.league_id = p_league_id
    and profile.deleted_at is null;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'userId', member.user_id,
        'displayName', coalesce(profile.display_name, 'Account'),
        'teamName', team.name,
        'role', case
          when member.user_id = v_league.owner_id then 'president'
          when member.role = 'admin' then 'admin'
          else 'manager'
        end,
        'canAccessDirection',
          member.user_id = v_league.owner_id or member.role = 'admin',
        'canManageHierarchy', member.user_id = v_league.owner_id,
        'canRunOperations',
          member.user_id = v_league.owner_id or member.role = 'admin',
        'canManageTeam', team.id is not null
      )
      order by
        case
          when member.user_id = v_league.owner_id then 0
          when member.role = 'admin' then 1
          else 2
        end,
        profile.display_name
    ),
    '[]'::jsonb
  )
  into v_matrix
  from public.league_members member
  join public.profiles profile on profile.id = member.user_id
  left join public.fantasy_teams team
    on team.league_id = member.league_id
   and team.manager_id = member.user_id
  where member.league_id = p_league_id
    and profile.deleted_at is null;

  v_direct_role_locked := not has_function_privilege(
    'authenticated',
    'public.set_league_member_role(uuid,uuid,public.member_role)',
    'execute'
  );
  v_direct_presidency_locked := not has_function_privilege(
    'authenticated',
    'public.transfer_league_presidency(uuid,uuid)',
    'execute'
  );
  v_direct_removal_locked := not has_function_privilege(
    'authenticated',
    'public.remove_league_member(uuid,uuid)',
    'execute'
  );
  v_guarded_actions_ready :=
    has_function_privilege(
      'authenticated',
      'public.set_league_member_role_guarded(uuid,uuid,public.member_role,bigint)',
      'execute'
    )
    and has_function_privilege(
      'authenticated',
      'public.transfer_league_presidency_guarded(uuid,uuid,bigint)',
      'execute'
    )
    and has_function_privilege(
      'authenticated',
      'public.remove_league_member_guarded(uuid,uuid,bigint)',
      'execute'
    );

  return jsonb_build_object(
    'hardened',
      v_president_count = 1
      and v_direct_role_locked
      and v_direct_presidency_locked
      and v_direct_removal_locked
      and v_guarded_actions_ready,
    'presidentCount', v_president_count,
    'adminCount', v_admin_count,
    'managerCount', v_manager_count,
    'directRoleMutationBlocked', v_direct_role_locked,
    'directPresidencyMutationBlocked', v_direct_presidency_locked,
    'directRemovalBlocked', v_direct_removal_locked,
    'guardedActionsReady', v_guarded_actions_ready,
    'members', v_matrix
  );
end;
$$;

create or replace function public.get_league_role_control_state_v2(
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
  v_control jsonb;
begin
  v_control := public.get_league_role_control_state(
    p_league_id,
    p_event_limit
  );

  return v_control || jsonb_build_object(
    'security', public.get_league_role_security_state(p_league_id)
  );
end;
$$;

create or replace function public.get_league_management_state_v7(
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
  v_state := public.get_league_management_state_v6(p_league_id);
  return v_state || jsonb_build_object(
    'roleControl', public.get_league_role_control_state_v2(p_league_id, 10)
  );
end;
$$;

revoke all on function public.get_league_role_security_state(uuid)
  from public, anon;
revoke all on function public.get_league_role_control_state_v2(uuid, integer)
  from public, anon;
revoke all on function public.get_league_management_state_v7(uuid)
  from public, anon;

grant execute on function public.get_league_role_security_state(uuid)
  to authenticated;
grant execute on function public.get_league_role_control_state_v2(uuid, integer)
  to authenticated;
grant execute on function public.get_league_management_state_v7(uuid)
  to authenticated;

-- Controllo finale: tutti i valori devono risultare true.
select
  not has_function_privilege(
    'authenticated',
    'public.set_league_member_role(uuid,uuid,public.member_role)',
    'execute'
  ) as direct_role_mutation_blocked,
  not has_function_privilege(
    'authenticated',
    'public.transfer_league_presidency(uuid,uuid)',
    'execute'
  ) as direct_presidency_mutation_blocked,
  not has_function_privilege(
    'authenticated',
    'public.remove_league_member(uuid,uuid)',
    'execute'
  ) as direct_member_removal_blocked,
  has_function_privilege(
    'authenticated',
    'public.set_league_member_role_guarded(uuid,uuid,public.member_role,bigint)',
    'execute'
  ) as guarded_role_change_ready,
  has_function_privilege(
    'authenticated',
    'public.transfer_league_presidency_guarded(uuid,uuid,bigint)',
    'execute'
  ) as guarded_presidency_ready,
  has_function_privilege(
    'authenticated',
    'public.remove_league_member_guarded(uuid,uuid,bigint)',
    'execute'
  ) as guarded_removal_ready,
  to_regprocedure('public.get_league_role_security_state(uuid)') is not null
    as role_security_state_ready,
  to_regprocedure(
    'public.get_league_role_control_state_v2(uuid,integer)'
  ) is not null as role_control_v2_ready,
  to_regprocedure('public.get_league_management_state_v7(uuid)') is not null
    as management_v7_ready,
  has_function_privilege(
    'authenticated',
    'public.get_league_management_state_v7(uuid)',
    'execute'
  ) as authenticated_management_v7_ready,
  not has_function_privilege(
    'anon',
    'public.get_league_management_state_v7(uuid)',
    'execute'
  ) as anonymous_management_v7_blocked,
  coalesce(
    pg_get_functiondef(
      to_regprocedure('public.get_league_role_security_state(uuid)')
    ) ilike '%directRoleMutationBlocked%',
    false
  ) as security_diagnostics_ready,
  coalesce(
    pg_get_functiondef(
      to_regprocedure('public.get_league_role_security_state(uuid)')
    ) ilike '%canManageHierarchy%',
    false
  ) as permission_matrix_ready,
  coalesce(
    pg_get_functiondef(
      to_regprocedure('public.get_league_management_state_v7(uuid)')
    ) ilike '%roleControl%',
    false
  ) as management_role_control_ready;
