-- LEGHEVO · anteprima invito e ingresso resiliente
-- Eseguire nel SQL Editor di Supabase dopo 059.
-- Lo script è idempotente e non modifica leghe, squadre o rose esistenti.

create or replace function public.preview_league_invite(
  p_invite_code text
)
returns table (
  league_id uuid,
  league_name text,
  league_mode public.league_mode,
  league_status public.league_status,
  team_limit smallint,
  team_count integer,
  available_spots integer,
  starting_credits integer,
  roster_size smallint,
  invites_open boolean,
  already_member boolean,
  already_has_team boolean,
  can_join boolean,
  block_reason text
)
language plpgsql
security definer
stable
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_invite_code text := upper(
    regexp_replace(trim(coalesce(p_invite_code, '')), '[^A-Za-z0-9]', '', 'g')
  );
begin
  if v_user_id is null then
    raise exception 'Devi effettuare l''accesso.';
  end if;

  if char_length(v_invite_code) <> 10 then
    raise exception 'Il codice invito deve contenere 10 caratteri.';
  end if;

  return query
  with selected_league as (
    select league.*
    from public.leagues league
    where league.invite_code = v_invite_code
  ),
  league_counts as (
    select
      selected.id as league_id,
      count(team.id)::integer as team_count
    from selected_league selected
    left join public.fantasy_teams team
      on team.league_id = selected.id
    group by selected.id
  )
  select
    selected.id,
    selected.name,
    selected.mode,
    selected.status,
    selected.team_limit,
    counts.team_count,
    greatest(selected.team_limit::integer - counts.team_count, 0),
    selected.starting_credits,
    selected.roster_size,
    selected.invites_open,
    exists (
      select 1
      from public.league_members member
      where member.league_id = selected.id
        and member.user_id = v_user_id
    ),
    exists (
      select 1
      from public.fantasy_teams team
      where team.league_id = selected.id
        and team.manager_id = v_user_id
    ),
    case
      when exists (
        select 1
        from public.fantasy_teams team
        where team.league_id = selected.id
          and team.manager_id = v_user_id
      ) then false
      when not selected.invites_open then false
      when selected.competition_started_at is not null then false
      when selected.status in ('completed', 'archived') then false
      when counts.team_count >= selected.team_limit then false
      else true
    end,
    case
      when exists (
        select 1
        from public.fantasy_teams team
        where team.league_id = selected.id
          and team.manager_id = v_user_id
      ) then 'Fai già parte di questa lega.'
      when not selected.invites_open then 'Gli inviti di questa lega sono chiusi.'
      when selected.competition_started_at is not null
        or selected.status in ('completed', 'archived')
        then 'Questa lega non accetta più partecipanti.'
      when counts.team_count >= selected.team_limit then 'La lega è al completo.'
      else null
    end
  from selected_league selected
  join league_counts counts on counts.league_id = selected.id;
end;
$$;

-- L'ingresso viene riallineato al numero reale di squadre e recupera in modo
-- sicuro anche un'eventuale iscrizione incompleta (membro senza squadra).
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
  v_team_count integer;
  v_team_name text := regexp_replace(trim(coalesce(p_team_name, '')), '\s+', ' ', 'g');
  v_invite_code text := upper(
    regexp_replace(trim(coalesce(p_invite_code, '')), '[^A-Za-z0-9]', '', 'g')
  );
begin
  if v_user_id is null then
    raise exception 'Devi effettuare l''accesso.';
  end if;

  if char_length(v_invite_code) <> 10 then
    raise exception 'Il codice invito deve contenere 10 caratteri.';
  end if;

  if char_length(v_team_name) not between 2 and 40 then
    raise exception 'Il nome squadra deve contenere da 2 a 40 caratteri.';
  end if;

  select league.*
  into v_league
  from public.leagues league
  where league.invite_code = v_invite_code
  for update;

  if not found then
    raise exception 'Codice invito non valido.';
  end if;

  if exists (
    select 1
    from public.fantasy_teams team
    where team.league_id = v_league.id
      and team.manager_id = v_user_id
  ) then
    raise exception 'Fai già parte di questa lega.';
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
    from public.fantasy_teams team
    where team.league_id = v_league.id
      and lower(btrim(team.name)) = lower(v_team_name)
  ) then
    raise exception 'Questo nome squadra è già stato preso.';
  end if;

  select count(*)::integer
  into v_team_count
  from public.fantasy_teams team
  where team.league_id = v_league.id;

  if v_team_count >= v_league.team_limit then
    raise exception 'La lega è al completo.';
  end if;

  insert into public.league_members (league_id, user_id, role)
  values (v_league.id, v_user_id, 'manager')
  on conflict (league_id, user_id) do nothing;

  insert into public.fantasy_teams (
    league_id,
    manager_id,
    name,
    credits_remaining
  )
  values (
    v_league.id,
    v_user_id,
    v_team_name,
    v_league.starting_credits
  );

  return v_league;
exception
  when unique_violation then
    if exists (
      select 1
      from public.fantasy_teams team
      where team.league_id = v_league.id
        and team.manager_id = v_user_id
    ) then
      raise exception 'Fai già parte di questa lega.';
    end if;
    raise exception 'Questo nome squadra è già stato preso.';
end;
$$;

revoke all on function public.preview_league_invite(text)
from public, anon;
revoke all on function public.join_league_by_code(text, text)
from public, anon;

grant execute on function public.preview_league_invite(text)
to authenticated;
grant execute on function public.join_league_by_code(text, text)
to authenticated;

-- Controllo finale: tutte le colonne devono restituire true.
select
  to_regprocedure(
    'public.preview_league_invite(text)'
  ) is not null as preview_invite_ready,
  to_regprocedure(
    'public.join_league_by_code(text,text)'
  ) is not null as resilient_join_ready,
  has_function_privilege(
    'authenticated',
    'public.preview_league_invite(text)',
    'execute'
  ) as authenticated_preview_ready,
  has_function_privilege(
    'authenticated',
    'public.join_league_by_code(text,text)',
    'execute'
  ) as authenticated_join_ready,
  not has_function_privilege(
    'anon',
    'public.preview_league_invite(text)',
    'execute'
  ) as anonymous_preview_blocked,
  not has_function_privilege(
    'anon',
    'public.join_league_by_code(text,text)',
    'execute'
  ) as anonymous_join_blocked;
