-- LEGHEVO · formazione, panchina ordinata e consegna protetta
-- Eseguire nel SQL Editor di Supabase dopo 028.

create or replace function public.mantra_athlete_fits_slot(
  p_athlete_id uuid,
  p_slot text
)
returns boolean
language sql
stable
set search_path = ''
as $$
  select exists (
    select 1
    from public.athlete_roles role
    where role.athlete_id = p_athlete_id
      and role.mode = 'mantra'
      and (
        (upper(trim(p_slot)) = 'POR' and role.role_code = 'Por')
        or (
          upper(trim(p_slot)) = 'DEF'
          and role.role_code in ('Dc', 'Dd', 'Ds')
        )
        or (
          upper(trim(p_slot)) = 'MID'
          and role.role_code in ('E', 'M', 'C')
        )
        or (
          upper(trim(p_slot)) = 'TRE'
          and role.role_code in ('W', 'T')
        )
        or (
          upper(trim(p_slot)) = 'ATT'
          and role.role_code in ('A', 'Pc')
        )
      )
  );
$$;

create or replace function public.mantra_lineup_is_valid(
  p_formation text,
  p_starter_ids uuid[]
)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_slots text[];
  v_slot_count integer;
begin
  v_slots := case trim(coalesce(p_formation, ''))
    when '3-4-1-2' then
      array[
        'POR',
        'DEF', 'DEF', 'DEF',
        'MID', 'MID', 'MID', 'MID',
        'TRE',
        'ATT', 'ATT'
      ]
    when '3-4-2-1' then
      array[
        'POR',
        'DEF', 'DEF', 'DEF',
        'MID', 'MID', 'MID', 'MID',
        'TRE', 'TRE',
        'ATT'
      ]
    when '3-5-2' then
      array[
        'POR',
        'DEF', 'DEF', 'DEF',
        'MID', 'MID', 'MID', 'MID', 'MID',
        'ATT', 'ATT'
      ]
    when '4-3-1-2' then
      array[
        'POR',
        'DEF', 'DEF', 'DEF', 'DEF',
        'MID', 'MID', 'MID',
        'TRE',
        'ATT', 'ATT'
      ]
    when '4-3-2-1' then
      array[
        'POR',
        'DEF', 'DEF', 'DEF', 'DEF',
        'MID', 'MID', 'MID',
        'TRE', 'TRE',
        'ATT'
      ]
    when '4-4-1-1' then
      array[
        'POR',
        'DEF', 'DEF', 'DEF', 'DEF',
        'MID', 'MID', 'MID', 'MID',
        'TRE',
        'ATT'
      ]
    when '4-4-2' then
      array[
        'POR',
        'DEF', 'DEF', 'DEF', 'DEF',
        'MID', 'MID', 'MID', 'MID',
        'ATT', 'ATT'
      ]
    else null
  end;

  v_slot_count := coalesce(array_length(v_slots, 1), 0);
  if v_slot_count <> 11
    or coalesce(array_length(p_starter_ids, 1), 0) <> 11 then
    return false;
  end if;

  return exists (
    with recursive assignments(next_slot, used_ids) as (
      select
        1,
        array[]::uuid[]

      union all

      select
        assignment.next_slot + 1,
        array_append(assignment.used_ids, candidate.athlete_id)
      from assignments assignment
      cross join unnest(p_starter_ids) as candidate(athlete_id)
      where assignment.next_slot <= v_slot_count
        and not (
          candidate.athlete_id = any(assignment.used_ids)
        )
        and public.mantra_athlete_fits_slot(
          candidate.athlete_id,
          v_slots[assignment.next_slot]
        )
    )
    select 1
    from assignments assignment
    where assignment.next_slot = v_slot_count + 1
    limit 1
  );
end;
$$;

create or replace function public.get_my_lineup_workspace(
  p_league_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_league public.leagues%rowtype;
  v_team public.fantasy_teams%rowtype;
  v_fixture record;
  v_lineup public.lineups%rowtype;
  v_roster_count integer;
  v_starter_ids uuid[] := array[]::uuid[];
  v_bench_ids uuid[] := array[]::uuid[];
  v_has_calendar boolean;
begin
  if auth.uid() is null then
    raise exception 'Devi effettuare l''accesso.';
  end if;

  select league.*
  into v_league
  from public.leagues league
  where league.id = p_league_id;

  if not found then
    raise exception 'Lega non trovata.';
  end if;

  if not public.is_league_member(p_league_id) then
    raise exception 'Non fai parte di questa lega.';
  end if;

  select team.*
  into v_team
  from public.fantasy_teams team
  where team.league_id = p_league_id
    and team.manager_id = auth.uid();

  if not found then
    raise exception 'Squadra non trovata.';
  end if;

  select count(*)::integer
  into v_roster_count
  from public.roster_entries roster
  where roster.fantasy_team_id = v_team.id
    and roster.released_at is null;

  select exists (
    select 1
    from public.fantasy_fixtures fixture
    where fixture.league_id = p_league_id
      and (
        fixture.home_team_id = v_team.id
        or fixture.away_team_id = v_team.id
      )
  )
  into v_has_calendar;

  select
    fixture.id as fixture_id,
    fixture.matchday_id,
    matchday.number,
    matchday.starts_at,
    matchday.locks_at,
    fixture.home_team_id = v_team.id as home,
    opponent.name as opponent_name
  into v_fixture
  from public.fantasy_fixtures fixture
  join public.matchdays matchday
    on matchday.id = fixture.matchday_id
  join public.fantasy_teams opponent
    on opponent.id = case
      when fixture.home_team_id = v_team.id
        then fixture.away_team_id
      else fixture.home_team_id
    end
  where fixture.league_id = p_league_id
    and (
      fixture.home_team_id = v_team.id
      or fixture.away_team_id = v_team.id
    )
    and matchday.locks_at > now()
  order by matchday.locks_at, matchday.number
  limit 1;

  if not found then
    return jsonb_build_object(
      'available', false,
      'reason',
        case
          when v_has_calendar then 'no_open_matchday'
          else 'calendar_missing'
        end,
      'teamId', v_team.id,
      'mode', v_league.mode,
      'rosterCount', v_roster_count,
      'rosterSize', v_league.roster_size,
      'benchLimit', greatest(v_roster_count - 11, 0)
    );
  end if;

  select lineup.*
  into v_lineup
  from public.lineups lineup
  where lineup.fantasy_team_id = v_team.id
    and lineup.matchday_id = v_fixture.matchday_id;

  if found then
    select
      coalesce(
        array_agg(entry.athlete_id order by entry.slot)
          filter (where entry.is_starter),
        array[]::uuid[]
      ),
      coalesce(
        array_agg(entry.athlete_id order by entry.slot)
          filter (where not entry.is_starter),
        array[]::uuid[]
      )
    into
      v_starter_ids,
      v_bench_ids
    from public.lineup_entries entry
    where entry.lineup_id = v_lineup.id;
  end if;

  return jsonb_build_object(
    'available', true,
    'teamId', v_team.id,
    'mode', v_league.mode,
    'rosterCount', v_roster_count,
    'rosterSize', v_league.roster_size,
    'benchLimit', greatest(v_roster_count - 11, 0),
    'fixtureId', v_fixture.fixture_id,
    'matchday', jsonb_build_object(
      'id', v_fixture.matchday_id,
      'number', v_fixture.number,
      'startsAt', v_fixture.starts_at,
      'locksAt', v_fixture.locks_at
    ),
    'opponentName', v_fixture.opponent_name,
    'home', v_fixture.home,
    'formation', v_lineup.formation,
    'starterIds', to_jsonb(v_starter_ids),
    'benchIds', to_jsonb(v_bench_ids),
    'status',
      case
        when v_lineup.id is null then null
        else v_lineup.status::text
      end,
    'submittedAt', v_lineup.submitted_at,
    'canSubmit',
      v_fixture.locks_at > now()
      and v_team.manager_id = auth.uid()
      and v_roster_count >= 11
  );
end;
$$;

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
  v_selected_roster_count integer;
  v_active_roster_count integer;
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
  where team.id = p_fantasy_team_id
  for update;

  if not found then
    raise exception 'Squadra non trovata.';
  end if;

  if v_team.manager_id <> auth.uid() then
    raise exception 'Puoi consegnare soltanto la tua formazione.';
  end if;

  select league.*
  into v_league
  from public.leagues league
  where league.id = v_team.league_id;

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

  select count(*)::integer
  into v_active_roster_count
  from public.roster_entries roster
  where roster.fantasy_team_id = v_team.id
    and roster.released_at is null;

  if v_active_roster_count < 11 then
    raise exception 'Servono almeno 11 calciatori in rosa.';
  end if;

  if v_bench_count <> greatest(v_active_roster_count - 11, 0) then
    raise exception
      'La panchina deve contenere tutti i % calciatori non titolari.',
      greatest(v_active_roster_count - 11, 0);
  end if;

  v_all_ids := coalesce(p_starter_ids, array[]::uuid[])
    || coalesce(p_bench_ids, array[]::uuid[]);

  select count(distinct selected.athlete_id)::integer
  into v_unique_count
  from unnest(v_all_ids) as selected(athlete_id);

  if v_unique_count <> v_starter_count + v_bench_count then
    raise exception 'Un calciatore non può essere inserito due volte.';
  end if;

  select count(*)::integer
  into v_selected_roster_count
  from public.roster_entries roster
  where roster.fantasy_team_id = v_team.id
    and roster.released_at is null
    and roster.athlete_id = any(v_all_ids);

  if v_selected_roster_count <> v_active_roster_count then
    raise exception 'La distinta deve contenere tutti i calciatori della rosa.';
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

    if not public.mantra_lineup_is_valid(
      trim(p_formation),
      p_starter_ids
    ) then
      raise exception
        'Gli undici scelti non possono occupare tutti gli slot del modulo Mantra %.',
        trim(p_formation);
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

revoke all on function public.mantra_athlete_fits_slot(uuid, text)
from public, anon;
revoke all on function public.mantra_lineup_is_valid(text, uuid[])
from public, anon;
revoke all on function public.get_my_lineup_workspace(uuid)
from public, anon;
revoke all on function public.save_team_lineup(
  uuid,
  uuid,
  text,
  uuid[],
  uuid[]
) from public, anon;

grant execute on function public.get_my_lineup_workspace(uuid)
to authenticated;
grant execute on function public.save_team_lineup(
  uuid,
  uuid,
  text,
  uuid[],
  uuid[]
) to authenticated;

do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'lineups'
  ) then
    alter publication supabase_realtime add table public.lineups;
  end if;

  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'lineup_entries'
  ) then
    alter publication supabase_realtime add table public.lineup_entries;
  end if;
end;
$$;

select
  to_regprocedure(
    'public.get_my_lineup_workspace(uuid)'
  ) is not null as lineup_workspace_ready,
  to_regprocedure(
    'public.save_team_lineup(uuid,uuid,text,uuid[],uuid[])'
  ) is not null as protected_lineup_save_ready,
  to_regprocedure(
    'public.mantra_athlete_fits_slot(uuid,text)'
  ) is not null as mantra_slot_engine_ready,
  to_regprocedure(
    'public.mantra_lineup_is_valid(text,uuid[])'
  ) is not null as mantra_formation_engine_ready,
  exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'lineups'
  ) as lineups_realtime_ready,
  exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'lineup_entries'
  ) as lineup_entries_realtime_ready,
  not has_function_privilege(
    'anon',
    'public.get_my_lineup_workspace(uuid)',
    'EXECUTE'
  ) as anonymous_workspace_blocked,
  not has_function_privilege(
    'anon',
    'public.save_team_lineup(uuid,uuid,text,uuid[],uuid[])',
    'EXECUTE'
  ) as anonymous_save_blocked,
  (
    pg_get_functiondef(
      'public.save_team_lineup(uuid,uuid,text,uuid[],uuid[])'::regprocedure
    ) ilike '%v_team.manager_id <> auth.uid()%'
    and pg_get_functiondef(
      'public.save_team_lineup(uuid,uuid,text,uuid[],uuid[])'::regprocedure
    ) not ilike '%is_league_admin(v_team.league_id)%'
  ) as only_manager_can_submit,
  (
    pg_get_functiondef(
      'public.save_team_lineup(uuid,uuid,text,uuid[],uuid[])'::regprocedure
    ) ilike '%La panchina deve contenere tutti%'
    and pg_get_functiondef(
      'public.save_team_lineup(uuid,uuid,text,uuid[],uuid[])'::regprocedure
    ) ilike '%mantra_lineup_is_valid%'
  ) as bench_and_roles_protected;
