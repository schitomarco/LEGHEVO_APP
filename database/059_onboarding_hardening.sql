-- LEGHEVO · irrobustimento creazione e ingresso nelle leghe
-- Eseguire nel SQL Editor di Supabase dopo 058.
-- Lo script è idempotente e non modifica leghe, squadre o rose esistenti.

-- I nomi squadra devono essere univoci nella lega anche ignorando maiuscole,
-- minuscole e spazi esterni. L'indice evita doppioni anche in accessi simultanei.
create unique index if not exists fantasy_teams_league_name_ci_uidx
  on public.fantasy_teams (league_id, lower(btrim(name)));

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
  v_league_name text := regexp_replace(trim(coalesce(p_name, '')), '\s+', ' ', 'g');
  v_team_name text := regexp_replace(trim(coalesce(p_team_name, '')), '\s+', ' ', 'g');
  v_invite_code text;
  v_attempt integer := 0;
begin
  if v_user_id is null then
    raise exception 'Devi effettuare l''accesso.';
  end if;

  if char_length(v_league_name) not between 3 and 50 then
    raise exception 'Il nome della lega deve contenere da 3 a 50 caratteri.';
  end if;

  if char_length(v_team_name) not between 2 and 40 then
    raise exception 'Il nome squadra deve contenere da 2 a 40 caratteri.';
  end if;

  if p_team_limit < 2 or p_team_limit > 20 then
    raise exception 'Il numero di partecipanti deve essere tra 2 e 20.';
  end if;

  if p_starting_credits < 100 or p_starting_credits > 100000 then
    raise exception 'I crediti iniziali devono essere compresi tra 100 e 100000.';
  end if;

  if p_roster_size < 11 or p_roster_size > 50 then
    raise exception 'La rosa deve contenere tra 11 e 50 calciatori.';
  end if;

  -- Generazione protetta da collisioni, anche se estremamente improbabili.
  loop
    v_attempt := v_attempt + 1;
    v_invite_code := upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 10));

    exit when not exists (
      select 1
      from public.leagues league
      where league.invite_code = v_invite_code
    );

    if v_attempt >= 10 then
      raise exception 'Impossibile generare il codice invito. Riprova.';
    end if;
  end loop;

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
    v_league_name,
    v_invite_code,
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
    v_team_name,
    v_league.starting_credits
  );

  return v_league;
exception
  when unique_violation then
    raise exception 'Questo nome squadra è già stato preso.';
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
  v_team_name text := regexp_replace(trim(coalesce(p_team_name, '')), '\s+', ' ', 'g');
  v_invite_code text := upper(regexp_replace(trim(coalesce(p_invite_code, '')), '[^A-Za-z0-9]', '', 'g'));
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

  -- Una chiamata ripetuta non deve creare doppie iscrizioni o doppie squadre.
  if exists (
    select 1
    from public.league_members member
    where member.league_id = v_league.id
      and member.user_id = v_user_id
  ) then
    if exists (
      select 1
      from public.fantasy_teams team
      where team.league_id = v_league.id
        and team.manager_id = v_user_id
    ) then
      raise exception 'Fai già parte di questa lega.';
    end if;
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
  into v_member_count
  from public.league_members member
  where member.league_id = v_league.id;

  if v_member_count >= v_league.team_limit then
    raise exception 'La lega è al completo.';
  end if;

  if not exists (
    select 1
    from public.league_members member
    where member.league_id = v_league.id
      and member.user_id = v_user_id
  ) then
    insert into public.league_members (league_id, user_id, role)
    values (v_league.id, v_user_id, 'manager');
  end if;

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
    raise exception 'Questo nome squadra è già stato preso.';
end;
$$;

revoke all on function public.create_league_with_team(
  text,
  text,
  public.league_mode,
  smallint,
  integer,
  smallint
) from public, anon;

revoke all on function public.join_league_by_code(text, text)
from public, anon;

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

-- Controllo finale: tutte le colonne devono restituire true.
select
  to_regprocedure(
    'public.create_league_with_team(text,text,public.league_mode,smallint,integer,smallint)'
  ) is not null as create_league_ready,
  to_regprocedure(
    'public.join_league_by_code(text,text)'
  ) is not null as join_league_ready,
  to_regclass(
    'public.fantasy_teams_league_name_ci_uidx'
  ) is not null as unique_team_name_ready,
  has_function_privilege(
    'authenticated',
    'public.create_league_with_team(text,text,public.league_mode,smallint,integer,smallint)',
    'execute'
  ) as authenticated_create_ready,
  has_function_privilege(
    'authenticated',
    'public.join_league_by_code(text,text)',
    'execute'
  ) as authenticated_join_ready,
  not has_function_privilege(
    'anon',
    'public.create_league_with_team(text,text,public.league_mode,smallint,integer,smallint)',
    'execute'
  ) as anonymous_create_blocked,
  not has_function_privilege(
    'anon',
    'public.join_league_by_code(text,text)',
    'execute'
  ) as anonymous_join_blocked;
