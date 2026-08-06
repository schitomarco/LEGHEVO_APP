-- LEGHEVO · calendario automatico a scontri diretti
-- Eseguire nel SQL Editor di Supabase dopo 006.

create or replace function public.generate_head_to_head_calendar(
  p_league_id uuid,
  p_season text,
  p_start_matchday smallint default 1,
  p_first_kickoff timestamptz default (now() + interval '7 days'),
  p_return_leg boolean default true
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_league public.leagues%rowtype;
  v_teams uuid[];
  v_rotation uuid[];
  v_next_rotation uuid[];
  v_team_count integer;
  v_slot_count integer;
  v_single_rounds integer;
  v_leg_count integer;
  v_total_rounds integer;
  v_leg integer;
  v_round integer;
  v_pair integer;
  v_position integer;
  v_round_offset integer;
  v_matchday_number integer;
  v_matchday_id uuid;
  v_home_team_id uuid;
  v_away_team_id uuid;
  v_swap_team_id uuid;
  v_created integer := 0;
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

  if not public.is_league_admin(p_league_id) then
    raise exception 'Solo il presidente può generare il calendario.';
  end if;

  if nullif(trim(p_season), '') is null then
    raise exception 'La stagione è obbligatoria.';
  end if;

  if p_start_matchday < 1 or p_start_matchday > 38 then
    raise exception 'La giornata iniziale deve essere compresa tra 1 e 38.';
  end if;

  select
    coalesce(
      array_agg(team.id order by team.created_at, team.id),
      array[]::uuid[]
    ),
    count(*)::integer
  into v_teams, v_team_count
  from public.fantasy_teams team
  where team.league_id = p_league_id;

  if v_team_count < 2 then
    raise exception 'Servono almeno due squadre per generare il calendario.';
  end if;

  if v_team_count <> v_league.team_limit then
    raise exception
      'Lo spogliatoio non è completo: % squadre su %.',
      v_team_count,
      v_league.team_limit;
  end if;

  if exists (
    select 1
    from public.fantasy_fixtures fixture
    where fixture.league_id = p_league_id
  ) then
    raise exception 'Il calendario di questa lega è già stato generato.';
  end if;

  if mod(v_team_count, 2) = 1 then
    v_teams := array_append(v_teams, null::uuid);
  end if;

  v_slot_count := array_length(v_teams, 1);
  v_single_rounds := v_slot_count - 1;
  v_leg_count := case when p_return_leg then 2 else 1 end;
  v_total_rounds := v_single_rounds * v_leg_count;

  if p_start_matchday + v_total_rounds - 1 > 38 then
    raise exception
      'Il calendario richiede % giornate: scegli una giornata iniziale precedente.',
      v_total_rounds;
  end if;

  for v_leg in 1..v_leg_count loop
    v_rotation := v_teams;

    for v_round in 1..v_single_rounds loop
      v_round_offset :=
        ((v_leg - 1) * v_single_rounds) + (v_round - 1);
      v_matchday_number := p_start_matchday + v_round_offset;

      insert into public.matchdays (
        competition_code,
        season,
        number,
        starts_at,
        locks_at,
        ends_at
      )
      values (
        'IT-SA',
        trim(p_season),
        v_matchday_number,
        p_first_kickoff + make_interval(days => v_round_offset * 7),
        p_first_kickoff + make_interval(days => v_round_offset * 7),
        p_first_kickoff + make_interval(days => (v_round_offset * 7) + 4)
      )
      on conflict (competition_code, season, number) do nothing;

      select matchday.id
      into v_matchday_id
      from public.matchdays matchday
      where matchday.competition_code = 'IT-SA'
        and matchday.season = trim(p_season)
        and matchday.number = v_matchday_number;

      for v_pair in 1..(v_slot_count / 2) loop
        v_home_team_id := v_rotation[v_pair];
        v_away_team_id := v_rotation[v_slot_count - v_pair + 1];

        if v_home_team_id is not null and v_away_team_id is not null then
          if mod(v_round + v_pair, 2) = 0 then
            v_swap_team_id := v_home_team_id;
            v_home_team_id := v_away_team_id;
            v_away_team_id := v_swap_team_id;
          end if;

          if v_leg = 2 then
            v_swap_team_id := v_home_team_id;
            v_home_team_id := v_away_team_id;
            v_away_team_id := v_swap_team_id;
          end if;

          insert into public.fantasy_fixtures (
            league_id,
            matchday_id,
            home_team_id,
            away_team_id
          )
          values (
            p_league_id,
            v_matchday_id,
            v_home_team_id,
            v_away_team_id
          );

          v_created := v_created + 1;
        end if;
      end loop;

      v_next_rotation := array_fill(null::uuid, array[v_slot_count]);
      v_next_rotation[1] := v_rotation[1];
      v_next_rotation[2] := v_rotation[v_slot_count];

      if v_slot_count > 2 then
        for v_position in 3..v_slot_count loop
          v_next_rotation[v_position] := v_rotation[v_position - 1];
        end loop;
      end if;

      v_rotation := v_next_rotation;
    end loop;
  end loop;

  return v_created;
end;
$$;

revoke all on function public.generate_head_to_head_calendar(
  uuid,
  text,
  smallint,
  timestamptz,
  boolean
) from public;

grant execute on function public.generate_head_to_head_calendar(
  uuid,
  text,
  smallint,
  timestamptz,
  boolean
) to authenticated;

select
  to_regprocedure(
    'public.generate_head_to_head_calendar(uuid,text,smallint,timestamptz,boolean)'
  ) is not null as calendar_engine_ready;
