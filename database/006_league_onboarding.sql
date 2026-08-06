-- LEGHEVO · creazione lega e ingresso tramite codice
-- Eseguire nel SQL Editor di Supabase dopo 001 e 002.

create or replace function public.create_league_with_team(
  p_name text,
  p_team_name text,
  p_mode public.league_mode,
  p_team_limit smallint default 8,
  p_starting_credits integer default 500,
  p_roster_size smallint default 25
)
returns public.leagues
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_league public.leagues%rowtype;
begin
  if v_user_id is null then
    raise exception 'Devi effettuare l''accesso.';
  end if;

  if nullif(trim(p_name), '') is null then
    raise exception 'Il nome della lega è obbligatorio.';
  end if;

  if nullif(trim(p_team_name), '') is null then
    raise exception 'Il nome della squadra è obbligatorio.';
  end if;

  if p_team_limit < 2 or p_team_limit > 20 then
    raise exception 'Il numero di partecipanti deve essere tra 2 e 20.';
  end if;

  if p_starting_credits < 100 then
    raise exception 'I crediti iniziali devono essere almeno 100.';
  end if;

  if p_roster_size < 11 or p_roster_size > 50 then
    raise exception 'La rosa deve contenere tra 11 e 50 calciatori.';
  end if;

  insert into public.leagues (
    owner_id,
    name,
    invite_code,
    mode,
    team_limit,
    starting_credits,
    roster_size
  )
  values (
    v_user_id,
    trim(p_name),
    upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 10)),
    p_mode,
    p_team_limit,
    p_starting_credits,
    p_roster_size
  )
  returning * into v_league;

  insert into public.league_members (league_id, user_id, role)
  values (v_league.id, v_user_id, 'admin');

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

  if v_league.status in ('completed', 'archived') then
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

revoke all on function public.create_league_with_team(
  text,
  text,
  public.league_mode,
  smallint,
  integer,
  smallint
) from public;

revoke all on function public.join_league_by_code(text, text) from public;

grant execute on function public.create_league_with_team(
  text,
  text,
  public.league_mode,
  smallint,
  integer,
  smallint
) to authenticated;

grant execute on function public.join_league_by_code(text, text)
to authenticated;

select
  to_regprocedure(
    'public.create_league_with_team(text,text,public.league_mode,smallint,integer,smallint)'
  ) is not null as create_league_ready,
  to_regprocedure(
    'public.join_league_by_code(text,text)'
  ) is not null as join_league_ready;
