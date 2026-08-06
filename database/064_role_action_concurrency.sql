-- LEGHEVO · protezione concorrenza per ruoli e partecipanti
-- Eseguire nel SQL Editor di Supabase dopo 063.
-- Script idempotente: non modifica rose, crediti, calendario o risultati.

-- Le azioni di gerarchia ricevono la revisione vista dal dispositivo.
-- Se un altro dispositivo ha già modificato ruoli, presidenza o membri,
-- l'operazione viene fermata prima di applicare una decisione obsoleta.
create or replace function public.assert_league_role_revision(
  p_league_id uuid,
  p_expected_revision bigint
)
returns public.leagues
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

  if p_expected_revision is null then
    raise exception 'Revisione dei permessi mancante. Aggiorna la Direzione Lega.';
  end if;

  if v_league.role_revision <> p_expected_revision then
    raise exception
      'La direzione è cambiata su un altro dispositivo. Aggiorna e riprova.';
  end if;

  return v_league;
end;
$$;

create or replace function public.set_league_member_role_guarded(
  p_league_id uuid,
  p_user_id uuid,
  p_role public.member_role,
  p_expected_revision bigint
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_member public.league_members%rowtype;
  v_revision bigint;
begin
  perform public.assert_league_role_revision(
    p_league_id,
    p_expected_revision
  );

  v_member := public.set_league_member_role(
    p_league_id,
    p_user_id,
    p_role
  );

  select league.role_revision
  into v_revision
  from public.leagues league
  where league.id = p_league_id;

  return jsonb_build_object(
    'revision', v_revision,
    'member', to_jsonb(v_member),
    'accessSession', public.get_league_access_session(p_league_id)
  );
end;
$$;

create or replace function public.transfer_league_presidency_guarded(
  p_league_id uuid,
  p_new_owner_id uuid,
  p_expected_revision bigint
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_revision bigint;
begin
  perform public.assert_league_role_revision(
    p_league_id,
    p_expected_revision
  );

  perform public.transfer_league_presidency(
    p_league_id,
    p_new_owner_id
  );

  select league.role_revision
  into v_revision
  from public.leagues league
  where league.id = p_league_id;

  return jsonb_build_object(
    'revision', v_revision,
    'accessSession', public.get_league_access_session(p_league_id)
  );
end;
$$;

create or replace function public.remove_league_member_guarded(
  p_league_id uuid,
  p_user_id uuid,
  p_expected_revision bigint
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_revision bigint;
begin
  perform public.assert_league_role_revision(
    p_league_id,
    p_expected_revision
  );

  perform public.remove_league_member(
    p_league_id,
    p_user_id
  );

  select league.role_revision
  into v_revision
  from public.leagues league
  where league.id = p_league_id;

  return jsonb_build_object(
    'revision', v_revision,
    'accessSession', public.get_league_access_session(p_league_id)
  );
end;
$$;

revoke all on function public.assert_league_role_revision(uuid, bigint)
  from public, anon;
revoke all on function public.set_league_member_role_guarded(
  uuid, uuid, public.member_role, bigint
) from public, anon;
revoke all on function public.transfer_league_presidency_guarded(
  uuid, uuid, bigint
) from public, anon;
revoke all on function public.remove_league_member_guarded(
  uuid, uuid, bigint
) from public, anon;

grant execute on function public.set_league_member_role_guarded(
  uuid, uuid, public.member_role, bigint
) to authenticated;
grant execute on function public.transfer_league_presidency_guarded(
  uuid, uuid, bigint
) to authenticated;
grant execute on function public.remove_league_member_guarded(
  uuid, uuid, bigint
) to authenticated;

-- Controllo finale: tutti i valori devono risultare true.
select
  to_regprocedure(
    'public.assert_league_role_revision(uuid,bigint)'
  ) is not null as revision_guard_ready,
  to_regprocedure(
    'public.set_league_member_role_guarded(uuid,uuid,public.member_role,bigint)'
  ) is not null as guarded_role_change_ready,
  to_regprocedure(
    'public.transfer_league_presidency_guarded(uuid,uuid,bigint)'
  ) is not null as guarded_presidency_ready,
  to_regprocedure(
    'public.remove_league_member_guarded(uuid,uuid,bigint)'
  ) is not null as guarded_member_removal_ready,
  has_function_privilege(
    'authenticated',
    'public.set_league_member_role_guarded(uuid,uuid,public.member_role,bigint)',
    'execute'
  ) as authenticated_role_change_ready,
  has_function_privilege(
    'authenticated',
    'public.transfer_league_presidency_guarded(uuid,uuid,bigint)',
    'execute'
  ) as authenticated_presidency_ready,
  has_function_privilege(
    'authenticated',
    'public.remove_league_member_guarded(uuid,uuid,bigint)',
    'execute'
  ) as authenticated_removal_ready,
  not has_function_privilege(
    'anon',
    'public.set_league_member_role_guarded(uuid,uuid,public.member_role,bigint)',
    'execute'
  ) as anonymous_role_change_blocked,
  not has_function_privilege(
    'anon',
    'public.transfer_league_presidency_guarded(uuid,uuid,bigint)',
    'execute'
  ) as anonymous_presidency_blocked,
  not has_function_privilege(
    'anon',
    'public.remove_league_member_guarded(uuid,uuid,bigint)',
    'execute'
  ) as anonymous_removal_blocked,
  coalesce(
    pg_get_functiondef(
      to_regprocedure('public.assert_league_role_revision(uuid,bigint)')
    ) ilike '%for update%',
    false
  ) as revision_row_lock_ready,
  coalesce(
    pg_get_functiondef(
      to_regprocedure('public.assert_league_role_revision(uuid,bigint)')
    ) ilike '%altro dispositivo%',
    false
  ) as stale_session_message_ready;
