-- LEGHEVO · continuità formazione, recupero automatico e giornate senza voto
-- Eseguire nel SQL Editor di Supabase dopo 031.

alter table public.lineups
  add column if not exists submission_source text not null default 'manager',
  add column if not exists source_lineup_id uuid
    references public.lineups(id) on delete set null,
  add column if not exists locked_at timestamptz;

alter table public.lineups
  drop constraint if exists lineups_submission_source_check;

alter table public.lineups
  add constraint lineups_submission_source_check
  check (submission_source in ('manager', 'carried'));

comment on column public.lineups.submission_source is
  'manager per una distinta consegnata, carried per il recupero automatico dell''ultima formazione valida.';

comment on column public.lineups.source_lineup_id is
  'Distinta precedente usata come origine dal recupero automatico.';

create or replace function public.mark_carried_lineup_as_manual()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.submission_source = 'carried'
    and new.status = 'submitted'
    and (
      old.status is distinct from new.status
      or old.submitted_at is distinct from new.submitted_at
      or old.formation is distinct from new.formation
    ) then
    new.submission_source := 'manager';
    new.source_lineup_id := null;
    new.locked_at := null;
  end if;

  return new;
end;
$$;

revoke all on function public.mark_carried_lineup_as_manual()
from public, anon, authenticated;

drop trigger if exists lineups_restore_manual_source
on public.lineups;

create trigger lineups_restore_manual_source
before update of status, submitted_at, formation
on public.lineups
for each row execute function public.mark_carried_lineup_as_manual();

create or replace function public.get_reusable_lineup_preview(
  p_fantasy_team_id uuid,
  p_target_matchday_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_target_matchday public.matchdays%rowtype;
  v_source_lineup_id uuid;
  v_source_matchday_id uuid;
  v_source_matchday_number integer;
  v_source_formation text;
  v_starter_ids jsonb;
  v_bench_ids jsonb;
begin
  select matchday.*
  into v_target_matchday
  from public.matchdays matchday
  where matchday.id = p_target_matchday_id;

  if not found then
    return null;
  end if;

  select
    lineup.id,
    lineup.matchday_id,
    source_matchday.number,
    lineup.formation
  into
    v_source_lineup_id,
    v_source_matchday_id,
    v_source_matchday_number,
    v_source_formation
  from public.lineups lineup
  join public.matchdays source_matchday
    on source_matchday.id = lineup.matchday_id
  where lineup.fantasy_team_id = p_fantasy_team_id
    and lineup.matchday_id <> p_target_matchday_id
    and lineup.status in ('submitted', 'locked')
    and source_matchday.starts_at < v_target_matchday.starts_at
    and (
      select count(*)::integer
      from public.lineup_entries entry
      where entry.lineup_id = lineup.id
        and entry.is_starter
    ) = 11
    and not exists (
      select 1
      from public.lineup_entries starter
      where starter.lineup_id = lineup.id
        and starter.is_starter
        and not exists (
          select 1
          from public.roster_entries roster
          where roster.fantasy_team_id = p_fantasy_team_id
            and roster.athlete_id = starter.athlete_id
            and roster.released_at is null
        )
    )
  order by
    source_matchday.starts_at desc,
    source_matchday.number desc,
    lineup.submitted_at desc nulls last
  limit 1;

  if v_source_lineup_id is null then
    return null;
  end if;

  select coalesce(
    jsonb_agg(entry.athlete_id order by entry.slot),
    '[]'::jsonb
  )
  into v_starter_ids
  from public.lineup_entries entry
  where entry.lineup_id = v_source_lineup_id
    and entry.is_starter;

  with active_roster as (
    select
      roster.athlete_id,
      roster.acquired_at
    from public.roster_entries roster
    where roster.fantasy_team_id = p_fantasy_team_id
      and roster.released_at is null
  ),
  source_bench as (
    select
      entry.athlete_id,
      0 as priority,
      entry.slot::bigint as sort_order
    from public.lineup_entries entry
    join active_roster roster
      on roster.athlete_id = entry.athlete_id
    where entry.lineup_id = v_source_lineup_id
      and not entry.is_starter
  ),
  added_players as (
    select
      roster.athlete_id,
      1 as priority,
      row_number() over (
        order by roster.acquired_at, roster.athlete_id
      )::bigint as sort_order
    from active_roster roster
    where not exists (
      select 1
      from public.lineup_entries entry
      where entry.lineup_id = v_source_lineup_id
        and entry.athlete_id = roster.athlete_id
    )
  ),
  ordered_bench as (
    select * from source_bench
    union all
    select * from added_players
  )
  select coalesce(
    jsonb_agg(
      bench.athlete_id
      order by bench.priority, bench.sort_order, bench.athlete_id
    ),
    '[]'::jsonb
  )
  into v_bench_ids
  from ordered_bench bench;

  return jsonb_build_object(
    'sourceLineupId', v_source_lineup_id,
    'sourceMatchdayId', v_source_matchday_id,
    'sourceMatchdayNumber', v_source_matchday_number,
    'formation', v_source_formation,
    'starterIds', v_starter_ids,
    'benchIds', v_bench_ids
  );
end;
$$;

revoke all on function public.get_reusable_lineup_preview(uuid, uuid)
from public, anon, authenticated;

create or replace function public.lock_or_carry_team_lineup(
  p_fantasy_team_id uuid,
  p_matchday_id uuid
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_team public.fantasy_teams%rowtype;
  v_matchday public.matchdays%rowtype;
  v_preview jsonb;
  v_lineup_id uuid;
  v_existing_source text;
begin
  select team.*
  into v_team
  from public.fantasy_teams team
  where team.id = p_fantasy_team_id;

  if not found then
    return 'missing';
  end if;

  select matchday.*
  into v_matchday
  from public.matchdays matchday
  where matchday.id = p_matchday_id;

  if not found then
    return 'missing';
  end if;

  if not exists (
    select 1
    from public.fantasy_fixtures fixture
    where fixture.league_id = v_team.league_id
      and fixture.matchday_id = p_matchday_id
      and (
        fixture.home_team_id = p_fantasy_team_id
        or fixture.away_team_id = p_fantasy_team_id
      )
  ) then
    return 'missing';
  end if;

  if now() < v_matchday.locks_at then
    return 'pending';
  end if;

  update public.lineups lineup
  set
    status = 'locked',
    locked_at = coalesce(lineup.locked_at, v_matchday.locks_at)
  where lineup.fantasy_team_id = p_fantasy_team_id
    and lineup.matchday_id = p_matchday_id
    and lineup.status in ('submitted', 'locked')
  returning lineup.submission_source
  into v_existing_source;

  if found then
    return v_existing_source;
  end if;

  v_preview := public.get_reusable_lineup_preview(
    p_fantasy_team_id,
    p_matchday_id
  );

  if v_preview is null then
    perform public.create_user_notification(
      v_team.manager_id,
      v_team.league_id,
      'lineup',
      'Formazione non consegnata',
      'Non esisteva una distinta precedente valida: la giornata '
        || v_matchday.number
        || ' sarà calcolata con 0 fantapunti.',
      'lineup',
      jsonb_build_object(
        'event', 'lineup_missing',
        'matchday_id', p_matchday_id,
        'matchday_number', v_matchday.number,
        'fantasy_team_id', p_fantasy_team_id
      ),
      'lineup:missing:'
        || p_fantasy_team_id::text
        || ':'
        || p_matchday_id::text
    );
    return 'missing';
  end if;

  insert into public.lineups (
    fantasy_team_id,
    matchday_id,
    formation,
    status,
    submitted_at,
    submission_source,
    source_lineup_id,
    locked_at
  )
  values (
    p_fantasy_team_id,
    p_matchday_id,
    v_preview ->> 'formation',
    'locked',
    now(),
    'carried',
    (v_preview ->> 'sourceLineupId')::uuid,
    v_matchday.locks_at
  )
  on conflict (fantasy_team_id, matchday_id) do nothing
  returning id into v_lineup_id;

  if v_lineup_id is null then
    select
      lineup.id,
      lineup.submission_source
    into
      v_lineup_id,
      v_existing_source
    from public.lineups lineup
    where lineup.fantasy_team_id = p_fantasy_team_id
      and lineup.matchday_id = p_matchday_id;

    return coalesce(v_existing_source, 'missing');
  end if;

  insert into public.lineup_entries (
    lineup_id,
    athlete_id,
    slot,
    is_starter,
    captain
  )
  select
    v_lineup_id,
    item.value::uuid,
    item.ordinality::smallint,
    true,
    false
  from jsonb_array_elements_text(
    v_preview -> 'starterIds'
  ) with ordinality as item(value, ordinality);

  insert into public.lineup_entries (
    lineup_id,
    athlete_id,
    slot,
    is_starter,
    captain
  )
  select
    v_lineup_id,
    item.value::uuid,
    (11 + item.ordinality)::smallint,
    false,
    false
  from jsonb_array_elements_text(
    v_preview -> 'benchIds'
  ) with ordinality as item(value, ordinality);

  perform public.create_user_notification(
    v_team.manager_id,
    v_team.league_id,
    'lineup',
    'Formazione recuperata',
    'Per la giornata '
      || v_matchday.number
      || ' è stata confermata automaticamente la distinta della giornata '
      || (v_preview ->> 'sourceMatchdayNumber')
      || '.',
    'live',
    jsonb_build_object(
      'event', 'lineup_carried',
      'matchday_id', p_matchday_id,
      'matchday_number', v_matchday.number,
      'source_matchday_id', v_preview ->> 'sourceMatchdayId',
      'source_matchday_number',
        (v_preview ->> 'sourceMatchdayNumber')::integer,
      'fantasy_team_id', p_fantasy_team_id
    ),
    'lineup:carried:'
      || p_fantasy_team_id::text
      || ':'
      || p_matchday_id::text
  );

  return 'carried';
end;
$$;

revoke all on function public.lock_or_carry_team_lineup(uuid, uuid)
from public, anon, authenticated;

create or replace function public.ensure_matchday_lineups(
  p_matchday_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_matchday public.matchdays%rowtype;
  v_team_id uuid;
  v_outcome text;
  v_manager_count integer := 0;
  v_carried_count integer := 0;
  v_missing_count integer := 0;
  v_pending_count integer := 0;
begin
  select matchday.*
  into v_matchday
  from public.matchdays matchday
  where matchday.id = p_matchday_id;

  if not found then
    return jsonb_build_object(
      'manager', 0,
      'carried', 0,
      'missing', 0,
      'pending', 0
    );
  end if;

  for v_team_id in
    select fixture.home_team_id
    from public.fantasy_fixtures fixture
    where fixture.matchday_id = p_matchday_id

    union

    select fixture.away_team_id
    from public.fantasy_fixtures fixture
    where fixture.matchday_id = p_matchday_id
  loop
    v_outcome := public.lock_or_carry_team_lineup(
      v_team_id,
      p_matchday_id
    );

    if v_outcome = 'manager' then
      v_manager_count := v_manager_count + 1;
    elsif v_outcome = 'carried' then
      v_carried_count := v_carried_count + 1;
    elsif v_outcome = 'pending' then
      v_pending_count := v_pending_count + 1;
    else
      v_missing_count := v_missing_count + 1;
    end if;
  end loop;

  return jsonb_build_object(
    'manager', v_manager_count,
    'carried', v_carried_count,
    'missing', v_missing_count,
    'pending', v_pending_count
  );
end;
$$;

revoke all on function public.ensure_matchday_lineups(uuid)
from public, anon, authenticated;

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
  v_preview jsonb;
  v_roster_count integer;
  v_starter_ids uuid[] := array[]::uuid[];
  v_bench_ids uuid[] := array[]::uuid[];
  v_has_calendar boolean;
  v_source_matchday_number integer;
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

    if v_lineup.source_lineup_id is not null then
      select matchday.number
      into v_source_matchday_number
      from public.lineups source_lineup
      join public.matchdays matchday
        on matchday.id = source_lineup.matchday_id
      where source_lineup.id = v_lineup.source_lineup_id;
    end if;
  else
    v_preview := public.get_reusable_lineup_preview(
      v_team.id,
      v_fixture.matchday_id
    );

    if v_preview is not null then
      select coalesce(array_agg(value::uuid order by ordinality), array[]::uuid[])
      into v_starter_ids
      from jsonb_array_elements_text(
        v_preview -> 'starterIds'
      ) with ordinality as item(value, ordinality);

      select coalesce(array_agg(value::uuid order by ordinality), array[]::uuid[])
      into v_bench_ids
      from jsonb_array_elements_text(
        v_preview -> 'benchIds'
      ) with ordinality as item(value, ordinality);

      v_source_matchday_number :=
        (v_preview ->> 'sourceMatchdayNumber')::integer;
    end if;
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
    'formation', coalesce(
      v_lineup.formation,
      v_preview ->> 'formation'
    ),
    'starterIds', to_jsonb(v_starter_ids),
    'benchIds', to_jsonb(v_bench_ids),
    'status',
      case
        when v_lineup.id is null then null
        else v_lineup.status::text
      end,
    'submittedAt', v_lineup.submitted_at,
    'lineupOrigin',
      case
        when v_lineup.id is not null
          then v_lineup.submission_source
        when v_preview is not null
          then 'previous_preview'
        else 'empty'
      end,
    'sourceMatchdayNumber', v_source_matchday_number,
    'willAutoCarry',
      v_lineup.id is null
      and v_preview is not null,
    'firstSubmissionRequired',
      v_lineup.id is null
      and v_preview is null,
    'canSubmit',
      v_fixture.locks_at > now()
      and v_team.manager_id = auth.uid()
      and v_roster_count >= 11
  );
end;
$$;

revoke all on function public.get_my_lineup_workspace(uuid)
from public, anon, authenticated;

grant execute on function public.get_my_lineup_workspace(uuid)
to authenticated;

create or replace function public.calculate_team_matchday_points(
  p_fantasy_team_id uuid,
  p_matchday_id uuid
)
returns table (
  total_points numeric,
  is_ready boolean,
  counted_players integer
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_lineup_id uuid;
  v_mode public.league_mode;
  v_scoring_rules jsonb;
  v_matchday_complete boolean;
  v_starter_count integer;
  v_starter record;
  v_score record;
  v_substitute record;
  v_used_bench_ids uuid[] := array[]::uuid[];
begin
  select
    case
      when matchday.provider_fixture_count > 0 then
        matchday.provider_final_fixture_count
          = matchday.provider_fixture_count
      else
        now() >= coalesce(
          matchday.ends_at,
          matchday.starts_at + interval '4 days'
        )
    end
  into v_matchday_complete
  from public.matchdays matchday
  where matchday.id = p_matchday_id;

  v_matchday_complete := coalesce(v_matchday_complete, false);
  total_points := 0;
  is_ready := v_matchday_complete;
  counted_players := 0;

  select lineup.id, league.mode, league.scoring_rules
  into v_lineup_id, v_mode, v_scoring_rules
  from public.lineups lineup
  join public.fantasy_teams team
    on team.id = lineup.fantasy_team_id
  join public.leagues league
    on league.id = team.league_id
  where lineup.fantasy_team_id = p_fantasy_team_id
    and lineup.matchday_id = p_matchday_id
    and lineup.status in ('submitted', 'locked');

  if not found then
    total_points := case
      when v_matchday_complete then 0
      else null
    end;
    is_ready := v_matchday_complete;
    return next;
    return;
  end if;

  select count(*)::integer
  into v_starter_count
  from public.lineup_entries entry
  where entry.lineup_id = v_lineup_id
    and entry.is_starter;

  if v_starter_count <> 11 then
    is_ready := false;
  end if;

  for v_starter in
    select entry.athlete_id, entry.slot
    from public.lineup_entries entry
    where entry.lineup_id = v_lineup_id
      and entry.is_starter
    order by entry.slot
  loop
    select
      score.athlete_id,
      public.calculate_league_fantasy_score(
        score.provider_rating,
        score.fantasy_score,
        score.raw_statistics,
        v_scoring_rules
      ) as fantasy_score,
      score.is_final
    into v_score
    from public.player_match_scores score
    where score.athlete_id = v_starter.athlete_id
      and score.matchday_id = p_matchday_id
      and score.provider_rating is not null;

    if found then
      total_points := total_points + v_score.fantasy_score;
      counted_players := counted_players + 1;
      is_ready := is_ready and v_score.is_final;
      continue;
    end if;

    select
      bench.athlete_id,
      public.calculate_league_fantasy_score(
        score.provider_rating,
        score.fantasy_score,
        score.raw_statistics,
        v_scoring_rules
      ) as fantasy_score,
      score.is_final
    into v_substitute
    from public.lineup_entries bench
    join public.player_match_scores score
      on score.athlete_id = bench.athlete_id
      and score.matchday_id = p_matchday_id
      and score.provider_rating is not null
    where bench.lineup_id = v_lineup_id
      and not bench.is_starter
      and not (bench.athlete_id = any(v_used_bench_ids))
      and exists (
        select 1
        from public.athlete_roles starter_role
        join public.athlete_roles bench_role
          on bench_role.mode = starter_role.mode
          and bench_role.role_code = starter_role.role_code
        where starter_role.athlete_id = v_starter.athlete_id
          and bench_role.athlete_id = bench.athlete_id
          and starter_role.mode = v_mode
      )
    order by bench.slot
    limit 1;

    if found then
      v_used_bench_ids :=
        array_append(v_used_bench_ids, v_substitute.athlete_id);
      total_points := total_points + v_substitute.fantasy_score;
      counted_players := counted_players + 1;
      is_ready := is_ready and v_substitute.is_final;
    end if;
  end loop;

  if counted_players = 0 then
    total_points := case
      when v_matchday_complete then 0
      else null
    end;
  else
    total_points := round(total_points, 2);
  end if;

  return next;
end;
$$;

revoke all on function public.calculate_team_matchday_points(uuid, uuid)
from public, anon, authenticated;

create or replace function public.refresh_matchday_results_internal(
  p_matchday_id uuid
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_fixture record;
  v_home_points numeric;
  v_away_points numeric;
  v_home_ready boolean;
  v_away_ready boolean;
  v_home_counted integer;
  v_away_counted integer;
  v_home_bonus numeric;
  v_updated integer := 0;
begin
  perform public.ensure_matchday_lineups(p_matchday_id);

  for v_fixture in
    select
      fixture.id,
      fixture.home_team_id,
      fixture.away_team_id,
      fixture.finalized_at,
      league.scoring_rules
    from public.fantasy_fixtures fixture
    join public.leagues league on league.id = fixture.league_id
    where fixture.matchday_id = p_matchday_id
    for update of fixture
  loop
    if v_fixture.finalized_at is not null then
      continue;
    end if;

    select
      calculation.total_points,
      calculation.is_ready,
      calculation.counted_players
    into
      v_home_points,
      v_home_ready,
      v_home_counted
    from public.calculate_team_matchday_points(
      v_fixture.home_team_id,
      p_matchday_id
    ) calculation;

    select
      calculation.total_points,
      calculation.is_ready,
      calculation.counted_players
    into
      v_away_points,
      v_away_ready,
      v_away_counted
    from public.calculate_team_matchday_points(
      v_fixture.away_team_id,
      p_matchday_id
    ) calculation;

    v_home_bonus :=
      coalesce((v_fixture.scoring_rules ->> 'home_bonus')::numeric, 0);

    if v_home_points is not null
      and coalesce(v_home_counted, 0) > 0 then
      v_home_points := round(v_home_points + v_home_bonus, 2);
    end if;

    update public.fantasy_fixtures
    set
      home_points = v_home_points,
      away_points = v_away_points,
      home_goals = public.fantasy_goals_from_points(
        v_home_points,
        v_fixture.scoring_rules
      ),
      away_goals = public.fantasy_goals_from_points(
        v_away_points,
        v_fixture.scoring_rules
      ),
      home_counted_players = least(
        greatest(coalesce(v_home_counted, 0), 0),
        11
      ),
      away_counted_players = least(
        greatest(coalesce(v_away_counted, 0), 0),
        11
      ),
      home_ready = coalesce(v_home_ready, false),
      away_ready = coalesce(v_away_ready, false)
    where id = v_fixture.id;

    v_updated := v_updated + 1;
  end loop;

  return v_updated;
end;
$$;

revoke all on function public.refresh_matchday_results_internal(uuid)
from public, anon, authenticated;

create or replace function public.refresh_results_after_lineup_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_lineup_id uuid;
  v_matchday_id uuid;
  v_submission_source text;
begin
  if tg_op = 'DELETE' then
    v_lineup_id := old.lineup_id;
  else
    v_lineup_id := new.lineup_id;
  end if;

  select
    lineup.matchday_id,
    lineup.submission_source
  into
    v_matchday_id,
    v_submission_source
  from public.lineups lineup
  where lineup.id = v_lineup_id;

  -- Il recupero automatico inserisce tutta la distinta in una sola
  -- operazione. Il ricalcolo definitivo viene eseguito dal chiamante:
  -- evitare un ricalcolo intermedio per ogni singolo panchinaro.
  if v_submission_source <> 'carried'
    and v_matchday_id is not null then
    perform public.refresh_matchday_results_internal(v_matchday_id);
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

revoke all on function public.refresh_results_after_lineup_change()
from public, anon, authenticated;

create or replace function public.get_my_live_match(
  p_league_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_league public.leagues%rowtype;
  v_my_team public.fantasy_teams%rowtype;
  v_fixture record;
  v_home_calculation record;
  v_away_calculation record;
  v_home_points numeric;
  v_away_points numeric;
  v_home_goals integer;
  v_away_goals integer;
  v_home_bonus numeric;
  v_match_status text;
  v_lineup_origin text;
  v_source_matchday_number integer;
begin
  if auth.uid() is null then
    raise exception 'Devi effettuare l''accesso.';
  end if;

  if not public.is_league_member(p_league_id)
    and not public.is_league_admin(p_league_id) then
    raise exception 'Non fai parte di questa lega.';
  end if;

  select league.*
  into v_league
  from public.leagues league
  where league.id = p_league_id;

  if not found then
    raise exception 'Lega non trovata.';
  end if;

  select team.*
  into v_my_team
  from public.fantasy_teams team
  where team.league_id = p_league_id
    and team.manager_id = auth.uid();

  if not found then
    raise exception 'Non hai una squadra in questa lega.';
  end if;

  select
    fixture.id,
    fixture.matchday_id,
    fixture.home_team_id,
    fixture.away_team_id,
    fixture.finalized_at,
    matchday.number as matchday_number,
    matchday.starts_at,
    matchday.locks_at,
    matchday.ends_at,
    home_team.name as home_team_name,
    away_team.name as away_team_name
  into v_fixture
  from public.fantasy_fixtures fixture
  join public.matchdays matchday on matchday.id = fixture.matchday_id
  join public.fantasy_teams home_team on home_team.id = fixture.home_team_id
  join public.fantasy_teams away_team on away_team.id = fixture.away_team_id
  where fixture.league_id = p_league_id
    and (
      fixture.home_team_id = v_my_team.id
      or fixture.away_team_id = v_my_team.id
    )
  order by
    case
      when now() >= matchday.starts_at
        and now() <= coalesce(
          matchday.ends_at,
          matchday.starts_at + interval '4 days'
        ) then 0
      when matchday.starts_at <= now()
        and fixture.finalized_at is null then 1
      when matchday.starts_at > now() then 2
      else 3
    end,
    case
      when matchday.starts_at > now() then matchday.starts_at
      else null
    end,
    case
      when matchday.starts_at <= now() then matchday.starts_at
      else null
    end desc
  limit 1;

  if not found then
    return null;
  end if;

  if now() >= v_fixture.locks_at then
    perform public.ensure_matchday_lineups(v_fixture.matchday_id);
  end if;

  select
    lineup.submission_source,
    source_matchday.number
  into
    v_lineup_origin,
    v_source_matchday_number
  from public.lineups lineup
  left join public.lineups source_lineup
    on source_lineup.id = lineup.source_lineup_id
  left join public.matchdays source_matchday
    on source_matchday.id = source_lineup.matchday_id
  where lineup.fantasy_team_id = v_my_team.id
    and lineup.matchday_id = v_fixture.matchday_id
    and lineup.status in ('submitted', 'locked');

  v_lineup_origin := coalesce(v_lineup_origin, 'missing');

  select calculation.*
  into v_home_calculation
  from public.calculate_team_matchday_points(
    v_fixture.home_team_id,
    v_fixture.matchday_id
  ) calculation;

  select calculation.*
  into v_away_calculation
  from public.calculate_team_matchday_points(
    v_fixture.away_team_id,
    v_fixture.matchday_id
  ) calculation;

  v_home_bonus :=
    coalesce((v_league.scoring_rules ->> 'home_bonus')::numeric, 0);
  v_home_points := v_home_calculation.total_points;
  v_away_points := v_away_calculation.total_points;

  if v_home_points is not null
    and coalesce(v_home_calculation.counted_players, 0) > 0 then
    v_home_points := round(v_home_points + v_home_bonus, 2);
  end if;

  v_home_goals := public.fantasy_goals_from_points(
    v_home_points,
    v_league.scoring_rules
  );
  v_away_goals := public.fantasy_goals_from_points(
    v_away_points,
    v_league.scoring_rules
  );

  v_match_status := case
    when v_fixture.finalized_at is not null then 'final'
    when now() < v_fixture.starts_at then 'upcoming'
    when now() <= coalesce(
      v_fixture.ends_at,
      v_fixture.starts_at + interval '4 days'
    ) then 'live'
    else 'pending'
  end;

  return jsonb_build_object(
    'leagueId', v_league.id,
    'leagueName', v_league.name,
    'mode', v_league.mode,
    'status', v_match_status,
    'fixtureId', v_fixture.id,
    'myTeamId', v_my_team.id,
    'lineupOrigin', v_lineup_origin,
    'lineupSourceMatchdayNumber', v_source_matchday_number,
    'matchday', jsonb_build_object(
      'id', v_fixture.matchday_id,
      'number', v_fixture.matchday_number,
      'startsAt', v_fixture.starts_at,
      'locksAt', v_fixture.locks_at,
      'endsAt', v_fixture.ends_at
    ),
    'home', jsonb_build_object(
      'teamId', v_fixture.home_team_id,
      'name', v_fixture.home_team_name,
      'points', v_home_points,
      'goals', v_home_goals,
      'countedPlayers', coalesce(
        v_home_calculation.counted_players,
        0
      ),
      'ready', coalesce(v_home_calculation.is_ready, false)
    ),
    'away', jsonb_build_object(
      'teamId', v_fixture.away_team_id,
      'name', v_fixture.away_team_name,
      'points', v_away_points,
      'goals', v_away_goals,
      'countedPlayers', coalesce(
        v_away_calculation.counted_players,
        0
      ),
      'ready', coalesce(v_away_calculation.is_ready, false)
    ),
    'players', public.get_team_live_players(
      v_my_team.id,
      v_fixture.matchday_id,
      v_league.mode,
      v_league.scoring_rules
    )
  );
end;
$$;

revoke all on function public.get_my_live_match(uuid)
from public, anon, authenticated;

grant execute on function public.get_my_live_match(uuid)
to authenticated;

create or replace function public.refresh_schedule_after_provider_fixture()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    perform public.refresh_matchday_schedule_from_provider(old.matchday_id);
    return old;
  end if;

  if tg_op = 'UPDATE'
    and old.matchday_id is distinct from new.matchday_id then
    perform public.refresh_matchday_schedule_from_provider(old.matchday_id);
  end if;

  perform public.refresh_matchday_schedule_from_provider(new.matchday_id);
  return new;
end;
$$;

revoke all on function public.refresh_schedule_after_provider_fixture()
from public, anon, authenticated;

select
  (
    select count(*) = 3
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'lineups'
      and column_name in (
        'submission_source',
        'source_lineup_id',
        'locked_at'
      )
  ) as lineup_continuity_columns_ready,
  exists (
    select 1
    from pg_constraint
    where conname = 'lineups_submission_source_check'
      and conrelid = 'public.lineups'::regclass
  ) as lineup_source_constraint_ready,
  to_regprocedure(
    'public.get_reusable_lineup_preview(uuid,uuid)'
  ) is not null as previous_lineup_preview_ready,
  to_regprocedure(
    'public.lock_or_carry_team_lineup(uuid,uuid)'
  ) is not null as lineup_carry_engine_ready,
  to_regprocedure(
    'public.ensure_matchday_lineups(uuid)'
  ) is not null as matchday_lineup_guard_ready,
  exists (
    select 1
    from pg_trigger
    where tgname = 'lineups_restore_manual_source'
      and not tgisinternal
  ) as manual_override_trigger_ready,
  pg_get_functiondef(
    'public.get_my_lineup_workspace(uuid)'::regprocedure
  ) ilike '%previous_preview%'
    as lineup_preview_interface_ready,
  pg_get_functiondef(
    'public.calculate_team_matchday_points(uuid,uuid)'::regprocedure
  ) ilike '%provider_final_fixture_count%'
    as final_votes_engine_ready,
  pg_get_functiondef(
    'public.refresh_matchday_results_internal(uuid)'::regprocedure
  ) ilike '%ensure_matchday_lineups%'
    as result_continuity_ready,
  pg_get_functiondef(
    'public.get_my_live_match(uuid)'::regprocedure
  ) ilike '%lineupOrigin%'
    as live_lineup_origin_ready,
  (
    not has_function_privilege(
      'authenticated',
      'public.ensure_matchday_lineups(uuid)',
      'EXECUTE'
    )
    and not has_function_privilege(
      'anon',
      'public.ensure_matchday_lineups(uuid)',
      'EXECUTE'
    )
  ) as internal_lineup_guard_protected,
  (
    has_function_privilege(
      'authenticated',
      'public.get_my_lineup_workspace(uuid)',
      'EXECUTE'
    )
    and has_function_privilege(
      'authenticated',
      'public.get_my_live_match(uuid)',
      'EXECUTE'
    )
  ) as authenticated_interfaces_ready;
