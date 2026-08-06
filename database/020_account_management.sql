-- LEGHEVO · profilo, sicurezza ed eliminazione account
-- Eseguire nel SQL Editor di Supabase dopo 019.

alter table public.profiles
  add column if not exists deleted_at timestamptz;

-- Il profilo pubblico può restare anonimizzato per conservare correttamente
-- risultati e classifiche storiche anche dopo la rimozione dell'account Auth.
alter table public.profiles
  drop constraint if exists profiles_id_fkey;

revoke update on public.profiles from authenticated;

create or replace function public.update_my_profile(
  p_display_name text
)
returns public.profiles
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_profile public.profiles%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Devi effettuare l''accesso.';
  end if;

  if char_length(trim(coalesce(p_display_name, ''))) not between 2 and 40 then
    raise exception 'Il nome deve contenere da 2 a 40 caratteri.';
  end if;

  update public.profiles
  set display_name = trim(p_display_name)
  where id = auth.uid()
    and deleted_at is null
  returning * into v_profile;

  if v_profile.id is null then
    raise exception 'Profilo non trovato.';
  end if;

  return v_profile;
end;
$$;

create or replace function public.delete_my_account()
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_league record;
  v_new_owner_id uuid;
begin
  if v_user_id is null then
    raise exception 'Devi effettuare l''accesso.';
  end if;

  -- Una lega con altri partecipanti viene affidata al primo amministratore
  -- disponibile, oppure al membro più anziano. Se non resta nessuno, la lega
  -- viene eliminata insieme ai suoi dati.
  for v_league in
    select league.id
    from public.leagues league
    where league.owner_id = v_user_id
    for update
  loop
    select member.user_id
    into v_new_owner_id
    from public.league_members member
    where member.league_id = v_league.id
      and member.user_id <> v_user_id
    order by
      case when member.role = 'admin' then 0 else 1 end,
      member.joined_at
    limit 1;

    if v_new_owner_id is null then
      delete from public.leagues
      where id = v_league.id;
    else
      update public.league_members
      set role = 'admin'
      where league_id = v_league.id
        and user_id = v_new_owner_id;

      update public.leagues
      set owner_id = v_new_owner_id
      where id = v_league.id;
    end if;
  end loop;

  delete from public.user_notifications
  where user_id = v_user_id;

  delete from public.league_members
  where user_id = v_user_id;

  update public.profiles
  set
    display_name = 'Account eliminato',
    avatar_url = null,
    subscription = 'free',
    deleted_at = now()
  where id = v_user_id;

  if not found then
    raise exception 'Profilo non trovato.';
  end if;

  delete from auth.users
  where id = v_user_id;

  if not found then
    raise exception 'Account non trovato.';
  end if;

  return true;
end;
$$;

create or replace function public.create_user_notification(
  p_user_id uuid,
  p_league_id uuid,
  p_kind text,
  p_title text,
  p_body text,
  p_action_screen text default null,
  p_metadata jsonb default '{}'::jsonb,
  p_dedupe_key text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_notification_id uuid;
begin
  if p_user_id is null or not exists (
    select 1
    from public.profiles profile
    where profile.id = p_user_id
      and profile.deleted_at is null
  ) then
    return null;
  end if;

  insert into public.user_notifications (
    user_id,
    league_id,
    kind,
    title,
    body,
    action_screen,
    metadata,
    dedupe_key
  )
  values (
    p_user_id,
    p_league_id,
    p_kind,
    left(trim(p_title), 90),
    left(trim(p_body), 280),
    p_action_screen,
    coalesce(p_metadata, '{}'::jsonb),
    nullif(trim(p_dedupe_key), '')
  )
  on conflict (user_id, dedupe_key)
    where dedupe_key is not null
  do nothing
  returning id into v_notification_id;

  return v_notification_id;
end;
$$;

revoke all on function public.update_my_profile(text)
from public, anon;
revoke all on function public.delete_my_account()
from public, anon;

grant execute on function public.update_my_profile(text)
to authenticated;
grant execute on function public.delete_my_account()
to authenticated;

select
  exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'profiles'
      and column_name = 'deleted_at'
  ) as deleted_profile_state_ready,
  not exists (
    select 1
    from information_schema.table_constraints
    where constraint_schema = 'public'
      and table_name = 'profiles'
      and constraint_name = 'profiles_id_fkey'
  ) as profile_history_ready,
  to_regprocedure(
    'public.update_my_profile(text)'
  ) is not null as profile_update_ready,
  to_regprocedure(
    'public.delete_my_account()'
  ) is not null as account_deletion_ready,
  has_function_privilege(
    'authenticated',
    'public.update_my_profile(text)',
    'EXECUTE'
  ) as profile_access_ready,
  has_function_privilege(
    'authenticated',
    'public.delete_my_account()',
    'EXECUTE'
  ) as deletion_access_ready;
