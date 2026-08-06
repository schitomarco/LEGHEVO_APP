-- LEGHEVO · calendario, giornate e accoppiamenti protetti
-- Eseguire nel SQL Editor di Supabase dopo 027.

alter table public.leagues
  add column if not exists calendar_season text,
  add column if not exists calendar_start_matchday smallint,
  add column if not exists calendar_return_leg boolean,
  add column if not exists calendar_generated_at timestamptz,
  add column if not exists calendar_draw_seed uuid;

alter table public.user_notifications
  drop constraint if exists user_notifications_action_screen_check;

alter table public.user_notifications
  add constraint user_notifications_action_screen_check
  check (
    action_screen is null
    or action_screen in (
      'home',
      'league',
      'live',
      'auction',
      'calendar',
      'lineup',
      'roster',
      'standings',
      'market'
    )
  );

create or replace function public.get_league_calendar_state(
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
  v_member_count integer;
  v_team_count integer;
  v_full_roster_count integer;
  v_fixture_count integer;
  v_matchday_count integer;
  v_first_matchday integer;
  v_last_matchday integer;
  v_detected_season text;
  v_detected_return_leg boolean;
  v_team_readiness jsonb;
  v_members_ready boolean;
  v_teams_ready boolean;
  v_rosters_ready boolean;
  v_calendar_empty boolean;
  v_competition_not_started boolean;
begin
  if auth.uid() is null then
    raise exception 'Devi effettuare l''accesso.';
  end if;

  if not public.is_league_member(p_league_id)
    and not exists (
      select 1
      from public.leagues league
      where league.id = p_league_id
        and league.owner_id = auth.uid()
    ) then
    raise exception 'Non fai parte di questa lega.';
  end if;

  select league.*
  into v_league
  from public.leagues league
  where league.id = p_league_id;

  if not found then
    raise exception 'Lega non trovata.';
  end if;

  select count(*)::integer
  into v_member_count
  from public.league_members member
  where member.league_id = p_league_id;

  select
    count(*)::integer,
    count(*) filter (
      where team_state.roster_count = v_league.roster_size
    )::integer,
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'teamId', team_state.id,
          'teamName', team_state.name,
          'managerId', team_state.manager_id,
          'rosterCount', team_state.roster_count,
          'rosterSize', v_league.roster_size,
          'complete', team_state.roster_count = v_league.roster_size
        )
        order by team_state.created_at, team_state.id
      ),
      '[]'::jsonb
    )
  into
    v_team_count,
    v_full_roster_count,
    v_team_readiness
  from (
    select
      team.id,
      team.name,
      team.manager_id,
      team.created_at,
      count(roster.id) filter (
        where roster.released_at is null
      )::integer as roster_count
    from public.fantasy_teams team
    left join public.roster_entries roster
      on roster.fantasy_team_id = team.id
    where team.league_id = p_league_id
    group by
      team.id,
      team.name,
      team.manager_id,
      team.created_at
  ) team_state;

  select
    count(*)::integer,
    count(distinct fixture.matchday_id)::integer,
    min(matchday.number)::integer,
    max(matchday.number)::integer,
    min(matchday.season)
  into
    v_fixture_count,
    v_matchday_count,
    v_first_matchday,
    v_last_matchday,
    v_detected_season
  from public.fantasy_fixtures fixture
  join public.matchdays matchday
    on matchday.id = fixture.matchday_id
  where fixture.league_id = p_league_id;

  v_members_ready := v_member_count = v_league.team_limit;
  v_teams_ready :=
    v_team_count = v_league.team_limit
    and v_team_count = v_member_count;
  v_rosters_ready :=
    v_team_count = v_league.team_limit
    and v_full_roster_count = v_league.team_limit;
  v_calendar_empty := v_fixture_count = 0;
  v_competition_not_started :=
    v_league.competition_started_at is null;
  v_detected_return_leg := coalesce(
    v_league.calendar_return_leg,
    v_fixture_count > (v_team_count * greatest(v_team_count - 1, 0)) / 2
  );

  return jsonb_build_object(
    'memberCount', v_member_count,
    'teamCount', v_team_count,
    'teamLimit', v_league.team_limit,
    'fullRosterCount', v_full_roster_count,
    'rosterSize', v_league.roster_size,
    'fixtureCount', v_fixture_count,
    'matchdayCount', v_matchday_count,
    'firstMatchday', v_first_matchday,
    'lastMatchday', v_last_matchday,
    'season', coalesce(v_league.calendar_season, v_detected_season),
    'returnLeg', v_detected_return_leg,
    'generatedAt', v_league.calendar_generated_at,
    'competitionStartedAt', v_league.competition_started_at,
    'calendarExists', not v_calendar_empty,
    'isOwner', v_league.owner_id = auth.uid(),
    'isDirector', public.is_league_admin(p_league_id),
    'canGenerate',
      v_league.owner_id = auth.uid()
      and v_members_ready
      and v_teams_ready
      and v_rosters_ready
      and v_calendar_empty
      and v_competition_not_started,
    'canReset',
      v_league.owner_id = auth.uid()
      and not v_calendar_empty
      and v_competition_not_started,
    'checks', jsonb_build_object(
      'membersReady', v_members_ready,
      'teamsReady', v_teams_ready,
      'rostersReady', v_rosters_ready,
      'calendarEmpty', v_calendar_empty,
      'competitionNotStarted', v_competition_not_started
    ),
    'teams', v_team_readiness
  );
end;
$$;

create or replace function public.clear_calendar_metadata_if_empty()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1
    from public.fantasy_fixtures fixture
    where fixture.league_id = old.league_id
  ) then
    update public.leagues
    set
      calendar_season = null,
      calendar_start_matchday = null,
      calendar_return_leg = null,
      calendar_generated_at = null,
      calendar_draw_seed = null,
      updated_at = now()
    where id = old.league_id;
  end if;

  return old;
end;
$$;

drop trigger if exists fantasy_fixtures_clear_calendar_metadata
on public.fantasy_fixtures;

create trigger fantasy_fixtures_clear_calendar_metadata
after delete on public.fantasy_fixtures
for each row execute function public.clear_calendar_metadata_if_empty();

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
  v_draw_seed uuid := gen_random_uuid();
  v_member_count integer;
  v_team_count integer;
  v_full_roster_count integer;
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
  v_team_id uuid;
  v_home_team_id uuid;
  v_away_team_id uuid;
  v_swap_team_id uuid;
  v_member_user_id uuid;
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

  if v_league.owner_id <> auth.uid() then
    raise exception 'Solo il Presidente può generare il calendario.';
  end if;

  if v_league.competition_started_at is not null then
    raise exception 'La competizione è già iniziata: il calendario è bloccato.';
  end if;

  if trim(coalesce(p_season, '')) !~ '^[0-9]{4}$' then
    raise exception 'La stagione deve avere quattro cifre.';
  end if;

  if p_start_matchday is null
    or p_start_matchday < 1
    or p_start_matchday > 38 then
    raise exception 'La giornata iniziale deve essere compresa tra 1 e 38.';
  end if;

  if p_first_kickoff is null then
    raise exception 'La data della prima giornata è obbligatoria.';
  end if;

  if exists (
    select 1
    from public.fantasy_fixtures fixture
    where fixture.league_id = p_league_id
  ) then
    raise exception 'Il calendario di questa lega è già stato generato.';
  end if;

  select count(*)::integer
  into v_member_count
  from public.league_members member
  where member.league_id = p_league_id;

  select count(*)::integer
  into v_team_count
  from public.fantasy_teams team
  where team.league_id = p_league_id;

  if v_member_count <> v_league.team_limit
    or v_team_count <> v_league.team_limit
    or v_team_count <> v_member_count then
    raise exception
      'Lo spogliatoio non è completo: % squadre su %.',
      v_team_count,
      v_league.team_limit;
  end if;

  select count(*)::integer
  into v_full_roster_count
  from public.fantasy_teams team
  where team.league_id = p_league_id
    and (
      select count(*)
      from public.roster_entries roster
      where roster.fantasy_team_id = team.id
        and roster.released_at is null
    ) = v_league.roster_size;

  if v_full_roster_count <> v_league.team_limit then
    raise exception
      'Tutte le rose devono essere complete: % su %.',
      v_full_roster_count,
      v_league.team_limit;
  end if;

  for v_team_id in
    select team.id
    from public.fantasy_teams team
    where team.league_id = p_league_id
  loop
    perform public.assert_team_roster_quotas(v_team_id);
  end loop;

  select coalesce(
    array_agg(
      team.id
      order by md5(team.id::text || v_draw_seed::text)
    ),
    array[]::uuid[]
  )
  into v_teams
  from public.fantasy_teams team
  where team.league_id = p_league_id;

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

  update public.leagues
  set
    calendar_season = trim(p_season),
    calendar_start_matchday = p_start_matchday,
    calendar_return_leg = p_return_leg,
    calendar_generated_at = now(),
    calendar_draw_seed = v_draw_seed,
    updated_at = now()
  where id = p_league_id;

  for v_member_user_id in
    select member.user_id
    from public.league_members member
    where member.league_id = p_league_id
  loop
    perform public.create_user_notification(
      v_member_user_id,
      p_league_id,
      'league',
      'Calendario pubblicato',
      'Il sorteggio è concluso. Giornate e accoppiamenti sono ora disponibili.',
      'calendar',
      jsonb_build_object(
        'event', 'calendar_generated',
        'season', trim(p_season),
        'fixtures', v_created
      ),
      'calendar:generated:' || p_league_id::text || ':' || v_draw_seed::text
    );
  end loop;

  return v_created;
end;
$$;

create or replace function public.reset_league_calendar(
  p_league_id uuid
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_league public.leagues%rowtype;
  v_matchday_ids uuid[];
  v_draw_seed uuid;
  v_member_user_id uuid;
  v_deleted integer := 0;
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

  if v_league.owner_id <> auth.uid() then
    raise exception 'Solo il Presidente può annullare il calendario.';
  end if;

  if v_league.competition_started_at is not null then
    raise exception 'La competizione è iniziata: il calendario è definitivo.';
  end if;

  select
    coalesce(
      array_agg(distinct fixture.matchday_id),
      array[]::uuid[]
    )
  into v_matchday_ids
  from public.fantasy_fixtures fixture
  where fixture.league_id = p_league_id;

  if coalesce(array_length(v_matchday_ids, 1), 0) = 0 then
    return 0;
  end if;

  v_draw_seed := v_league.calendar_draw_seed;

  delete from public.lineups lineup
  where lineup.fantasy_team_id in (
      select team.id
      from public.fantasy_teams team
      where team.league_id = p_league_id
    )
    and lineup.matchday_id = any(v_matchday_ids);

  delete from public.fantasy_fixtures fixture
  where fixture.league_id = p_league_id;

  get diagnostics v_deleted = row_count;

  update public.leagues
  set
    calendar_season = null,
    calendar_start_matchday = null,
    calendar_return_leg = null,
    calendar_generated_at = null,
    calendar_draw_seed = null,
    updated_at = now()
  where id = p_league_id;

  for v_member_user_id in
    select member.user_id
    from public.league_members member
    where member.league_id = p_league_id
  loop
    perform public.create_user_notification(
      v_member_user_id,
      p_league_id,
      'league',
      'Calendario annullato',
      'Il Presidente ha annullato il sorteggio. Un nuovo calendario verrà pubblicato.',
      'calendar',
      jsonb_build_object(
        'event', 'calendar_reset',
        'deletedFixtures', v_deleted
      ),
      'calendar:reset:' || p_league_id::text || ':' ||
        coalesce(v_draw_seed::text, now()::text)
    );
  end loop;

  return v_deleted;
end;
$$;

revoke all on function public.get_league_calendar_state(uuid)
from public, anon;
revoke all on function public.clear_calendar_metadata_if_empty()
from public, anon, authenticated;
revoke all on function public.generate_head_to_head_calendar(
  uuid,
  text,
  smallint,
  timestamptz,
  boolean
) from public, anon;
revoke all on function public.reset_league_calendar(uuid)
from public, anon;

grant execute on function public.get_league_calendar_state(uuid)
to authenticated;
grant execute on function public.generate_head_to_head_calendar(
  uuid,
  text,
  smallint,
  timestamptz,
  boolean
) to authenticated;
grant execute on function public.reset_league_calendar(uuid)
to authenticated;

do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'fantasy_fixtures'
  ) then
    alter publication supabase_realtime
      add table public.fantasy_fixtures;
  end if;
end;
$$;

select
  (
    select count(*) = 5
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'leagues'
      and column_name in (
        'calendar_season',
        'calendar_start_matchday',
        'calendar_return_leg',
        'calendar_generated_at',
        'calendar_draw_seed'
      )
  ) and exists (
    select 1
    from pg_trigger trigger_row
    where trigger_row.tgrelid = 'public.fantasy_fixtures'::regclass
      and trigger_row.tgname =
        'fantasy_fixtures_clear_calendar_metadata'
      and not trigger_row.tgisinternal
  ) as calendar_metadata_ready,
  to_regprocedure(
    'public.get_league_calendar_state(uuid)'
  ) is not null as calendar_state_ready,
  to_regprocedure(
    'public.generate_head_to_head_calendar(uuid,text,smallint,timestamptz,boolean)'
  ) is not null as protected_generator_ready,
  to_regprocedure(
    'public.reset_league_calendar(uuid)'
  ) is not null as protected_reset_ready,
  exists (
    select 1
    from pg_constraint constraint_row
    where constraint_row.conrelid = 'public.user_notifications'::regclass
      and constraint_row.conname =
        'user_notifications_action_screen_check'
      and pg_get_constraintdef(constraint_row.oid) ilike '%calendar%'
  ) as calendar_notifications_ready,
  exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'fantasy_fixtures'
  ) as calendar_realtime_ready,
  not has_function_privilege(
    'anon',
    'public.get_league_calendar_state(uuid)',
    'EXECUTE'
  ) as anonymous_state_blocked,
  not has_function_privilege(
    'anon',
    'public.generate_head_to_head_calendar(uuid,text,smallint,timestamptz,boolean)',
    'EXECUTE'
  ) as anonymous_generator_blocked,
  not has_function_privilege(
    'anon',
    'public.reset_league_calendar(uuid)',
    'EXECUTE'
  ) as anonymous_reset_blocked,
  (
    pg_get_functiondef(
      'public.generate_head_to_head_calendar(uuid,text,smallint,timestamptz,boolean)'::regprocedure
    ) ilike '%v_league.owner_id <> auth.uid()%'
    and pg_get_functiondef(
      'public.generate_head_to_head_calendar(uuid,text,smallint,timestamptz,boolean)'::regprocedure
    ) ilike '%Tutte le rose devono essere complete%'
    and pg_get_functiondef(
      'public.reset_league_calendar(uuid)'::regprocedure
    ) ilike '%v_league.owner_id <> auth.uid()%'
  ) as president_and_rosters_protected;
