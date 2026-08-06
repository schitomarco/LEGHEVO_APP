-- LEGHEVO · rosa e consegna formazione
-- Eseguire nel SQL Editor di Supabase dopo 008.

create or replace function public.save_team_lineup(
  p_fantasy_team_id uuid,
  p_matchday_id uuid,
  p_formation text,
  p_starter_ids uuid[],
  p_bench_ids uuid[] default array[]::uuid[]
)
returns public.lineups
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_team public.fantasy_teams%rowtype;
  v_league public.leagues%rowtype;
  v_matchday public.matchdays%rowtype;
  v_lineup public.lineups%rowtype;
  v_all_ids uuid[];
  v_starter_count integer;
  v_bench_count integer;
  v_unique_count integer;
  v_roster_count integer;
  v_goalkeepers integer;
  v_defenders integer;
  v_midfielders integer;
  v_attackers integer;
  v_expected_defenders integer;
  v_expected_midfielders integer;
  v_expected_attackers integer;
begin
  if auth.uid() is null then
    raise exception 'Devi effettuare l''accesso.';
  end if;

  select team.*
  into v_team
  from public.fantasy_teams team
  where team.id = p_fantasy_team_id;

  if not found then
    raise exception 'Squadra non trovata.';
  end if;

  select league.*
  into v_league
  from public.leagues league
  where league.id = v_team.league_id;

  if v_team.manager_id <> auth.uid()
    and not public.is_league_admin(v_team.league_id) then
    raise exception 'Puoi consegnare soltanto la tua formazione.';
  end if;

  select matchday.*
  into v_matchday
  from public.matchdays matchday
  where matchday.id = p_matchday_id;

  if not found then
    raise exception 'Giornata non trovata.';
  end if;

  if not exists (
    select 1
    from public.fantasy_fixtures fixture
    where fixture.league_id = v_team.league_id
      and fixture.matchday_id = v_matchday.id
      and (
        fixture.home_team_id = v_team.id
        or fixture.away_team_id = v_team.id
      )
  ) then
    raise exception 'Questa giornata non appartiene al calendario della squadra.';
  end if;

  if v_matchday.locks_at <= now() then
    raise exception 'Formazioni bloccate. Fischio già arrivato.';
  end if;

  if nullif(trim(p_formation), '') is null then
    raise exception 'Scegli un modulo prima di consegnare.';
  end if;

  v_starter_count := coalesce(array_length(p_starter_ids, 1), 0);
  v_bench_count := coalesce(array_length(p_bench_ids, 1), 0);

  if v_starter_count <> 11 then
    raise exception 'La formazione titolare deve contenere 11 calciatori.';
  end if;

  if v_bench_count > greatest(v_league.roster_size - 11, 0) then
    raise exception 'Hai inserito troppi calciatori in panchina.';
  end if;

  v_all_ids := coalesce(p_starter_ids, array[]::uuid[])
    || coalesce(p_bench_ids, array[]::uuid[]);

  select count(distinct selected.athlete_id)::integer
  into v_unique_count
  from unnest(v_all_ids) as selected(athlete_id);

  if v_unique_count <> v_starter_count + v_bench_count then
    raise exception 'Un calciatore non può sedersi anche in panchina.';
  end if;

  select count(*)::integer
  into v_roster_count
  from public.roster_entries roster
  where roster.fantasy_team_id = v_team.id
    and roster.released_at is null
    and roster.athlete_id = any(v_all_ids);

  if v_roster_count <> v_starter_count + v_bench_count then
    raise exception 'La formazione contiene calciatori non presenti in rosa.';
  end if;

  if v_league.mode = 'classic' then
    if trim(p_formation) not in (
      '3-4-3',
      '3-5-2',
      '4-3-3',
      '4-4-2',
      '4-5-1',
      '5-3-2',
      '5-4-1'
    ) then
      raise exception 'Modulo classico non valido.';
    end if;

    v_expected_defenders := split_part(trim(p_formation), '-', 1)::integer;
    v_expected_midfielders := split_part(trim(p_formation), '-', 2)::integer;
    v_expected_attackers := split_part(trim(p_formation), '-', 3)::integer;

    select
      count(*) filter (where role.role_code = 'P')::integer,
      count(*) filter (where role.role_code = 'D')::integer,
      count(*) filter (where role.role_code = 'C')::integer,
      count(*) filter (where role.role_code = 'A')::integer
    into
      v_goalkeepers,
      v_defenders,
      v_midfielders,
      v_attackers
    from unnest(p_starter_ids) as selected(athlete_id)
    join public.athlete_roles role
      on role.athlete_id = selected.athlete_id
      and role.mode = 'classic';

    if v_goalkeepers <> 1
      or v_defenders <> v_expected_defenders
      or v_midfielders <> v_expected_midfielders
      or v_attackers <> v_expected_attackers then
      raise exception
        'Il modulo % richiede 1P, %D, %C e %A.',
        trim(p_formation),
        v_expected_defenders,
        v_expected_midfielders,
        v_expected_attackers;
    end if;
  else
    if trim(p_formation) not in (
      '3-4-1-2',
      '3-4-2-1',
      '3-5-2',
      '4-3-1-2',
      '4-3-2-1',
      '4-4-1-1',
      '4-4-2'
    ) then
      raise exception 'Modulo Mantra non valido.';
    end if;
  end if;

  insert into public.lineups (
    fantasy_team_id,
    matchday_id,
    formation,
    status,
    submitted_at
  )
  values (
    v_team.id,
    v_matchday.id,
    trim(p_formation),
    'submitted',
    now()
  )
  on conflict (fantasy_team_id, matchday_id) do update
  set
    formation = excluded.formation,
    status = 'submitted',
    submitted_at = excluded.submitted_at
  returning * into v_lineup;

  delete from public.lineup_entries
  where lineup_id = v_lineup.id;

  insert into public.lineup_entries (
    lineup_id,
    athlete_id,
    slot,
    is_starter,
    captain
  )
  select
    v_lineup.id,
    starter.athlete_id,
    starter.position::smallint,
    true,
    false
  from unnest(p_starter_ids)
    with ordinality as starter(athlete_id, position);

  insert into public.lineup_entries (
    lineup_id,
    athlete_id,
    slot,
    is_starter,
    captain
  )
  select
    v_lineup.id,
    bench.athlete_id,
    (11 + bench.position)::smallint,
    false,
    false
  from unnest(coalesce(p_bench_ids, array[]::uuid[]))
    with ordinality as bench(athlete_id, position);

  return v_lineup;
end;
$$;

revoke all on function public.save_team_lineup(
  uuid,
  uuid,
  text,
  uuid[],
  uuid[]
) from public;

grant execute on function public.save_team_lineup(
  uuid,
  uuid,
  text,
  uuid[],
  uuid[]
) to authenticated;

select
  to_regprocedure(
    'public.save_team_lineup(uuid,uuid,text,uuid[],uuid[])'
  ) is not null as lineup_engine_ready;
