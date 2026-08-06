-- LEGHEVO · Centro Operativo della giornata e promemoria formazione
-- Eseguire nel SQL Editor di Supabase dopo 048.
-- Lo script aggiunge soltanto letture protette e un'azione manuale:
-- non invia notifiche, non modifica risultati e non tocca la lega di prova.

create or replace function public.get_league_operations_center(
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
  v_is_owner boolean := false;
  v_is_director boolean := false;
  v_focus_matchday jsonb;
  v_next_lineup_matchday jsonb;
  v_team_states jsonb := '[]'::jsonb;
  v_team_count integer := 0;
  v_manual_count integer := 0;
  v_carried_count integer := 0;
  v_draft_count integer := 0;
  v_missing_count integer := 0;
  v_reminder_sent_count integer := 0;
  v_next_matchday_id uuid;
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

  v_is_owner := v_league.owner_id = auth.uid();
  v_is_director := public.is_league_admin(p_league_id);

  if not v_is_director and not v_is_owner then
    raise exception 'Il Centro Operativo è riservato alla Direzione.';
  end if;

  with matchday_stats as (
    select
      matchday.id,
      matchday.number,
      matchday.starts_at,
      matchday.locks_at,
      matchday.ends_at,
      matchday.schedule_source,
      matchday.schedule_synced_at,
      matchday.provider_fixture_count,
      matchday.provider_final_fixture_count,
      count(fixture.id)::integer as fixture_count,
      count(fixture.id) filter (
        where fixture.home_ready and fixture.away_ready
      )::integer as ready_count,
      count(fixture.id) filter (
        where fixture.finalized_at is not null
      )::integer as official_count
    from public.fantasy_fixtures fixture
    join public.matchdays matchday
      on matchday.id = fixture.matchday_id
    where fixture.league_id = p_league_id
    group by
      matchday.id,
      matchday.number,
      matchday.starts_at,
      matchday.locks_at,
      matchday.ends_at,
      matchday.schedule_source,
      matchday.schedule_synced_at,
      matchday.provider_fixture_count,
      matchday.provider_final_fixture_count
  ),
  ranked_matchdays as (
    select
      matchday_state.*,
      case
        when matchday_state.official_count
          < matchday_state.fixture_count
          and now() >= matchday_state.locks_at
          then 0
        when matchday_state.official_count
          < matchday_state.fixture_count
          and now() < matchday_state.locks_at
          then 1
        else 2
      end as priority
    from matchday_stats matchday_state
  )
  select jsonb_build_object(
    'id', selected.id,
    'number', selected.number,
    'startsAt', selected.starts_at,
    'locksAt', selected.locks_at,
    'endsAt', selected.ends_at,
    'scheduleSource', selected.schedule_source,
    'scheduleSyncedAt', selected.schedule_synced_at,
    'providerFixtureCount', selected.provider_fixture_count,
    'providerFinalFixtureCount',
      selected.provider_final_fixture_count,
    'fixtureCount', selected.fixture_count,
    'readyCount', selected.ready_count,
    'officialCount', selected.official_count,
    'status',
      case
        when selected.fixture_count > 0
          and selected.official_count = selected.fixture_count
          then 'official'
        when now() < selected.locks_at then 'upcoming'
        when now() < coalesce(
          selected.ends_at,
          selected.starts_at + interval '4 days'
        ) and (
          selected.provider_fixture_count = 0
          or selected.provider_final_fixture_count
            < selected.provider_fixture_count
        ) then 'live'
        when selected.fixture_count > 0
          and selected.ready_count = selected.fixture_count
          then 'ready'
        else 'pending'
      end,
    'canFinalize',
      v_is_owner
      and selected.fixture_count > 0
      and selected.ready_count = selected.fixture_count
      and selected.official_count < selected.fixture_count
  )
  into v_focus_matchday
  from ranked_matchdays selected
  order by
    selected.priority,
    case
      when selected.priority < 2 then selected.starts_at
    end,
    case
      when selected.priority = 2 then selected.starts_at
    end desc,
    selected.number
  limit 1;

  select selected.id
  into v_next_matchday_id
  from (
    select
      matchday.id,
      matchday.number,
      matchday.starts_at,
      matchday.locks_at,
      count(fixture.id)::integer as fixture_count,
      count(fixture.id) filter (
        where fixture.finalized_at is not null
      )::integer as official_count
    from public.fantasy_fixtures fixture
    join public.matchdays matchday
      on matchday.id = fixture.matchday_id
    where fixture.league_id = p_league_id
    group by
      matchday.id,
      matchday.number,
      matchday.starts_at,
      matchday.locks_at
    having
      matchday.locks_at > now()
      or count(fixture.id) filter (
        where fixture.finalized_at is not null
      ) < count(fixture.id)
    order by
      case when matchday.locks_at > now() then 0 else 1 end,
      case
        when matchday.locks_at > now() then matchday.locks_at
      end,
      case
        when matchday.locks_at <= now() then matchday.starts_at
      end desc,
      matchday.number
    limit 1
  ) selected;

  if v_next_matchday_id is not null then
    with participating_teams as (
      select fixture.home_team_id as team_id
      from public.fantasy_fixtures fixture
      where fixture.league_id = p_league_id
        and fixture.matchday_id = v_next_matchday_id

      union

      select fixture.away_team_id
      from public.fantasy_fixtures fixture
      where fixture.league_id = p_league_id
        and fixture.matchday_id = v_next_matchday_id
    ),
    lineup_states as (
      select
        team.id as team_id,
        team.name as team_name,
        team.manager_id,
        coalesce(profile.display_name, 'Manager') as manager_name,
        lineup.submitted_at,
        case
          when lineup.status in ('submitted', 'locked')
            and lineup.submission_source = 'carried'
            then 'carried'
          when lineup.status in ('submitted', 'locked')
            then 'manual'
          when lineup.id is not null then 'draft'
          else 'missing'
        end as lineup_state,
        exists (
          select 1
          from public.user_notifications notification
          where notification.user_id = team.manager_id
            and notification.dedupe_key =
              'lineup:manual-reminder:'
              || p_league_id::text
              || ':'
              || v_next_matchday_id::text
              || ':'
              || team.id::text
        ) as reminder_sent
      from participating_teams participant
      join public.fantasy_teams team
        on team.id = participant.team_id
      left join public.profiles profile
        on profile.id = team.manager_id
      left join public.lineups lineup
        on lineup.fantasy_team_id = team.id
        and lineup.matchday_id = v_next_matchday_id
    )
    select
      count(*)::integer,
      count(*) filter (
        where lineup_state.lineup_state = 'manual'
      )::integer,
      count(*) filter (
        where lineup_state.lineup_state = 'carried'
      )::integer,
      count(*) filter (
        where lineup_state.lineup_state = 'draft'
      )::integer,
      count(*) filter (
        where lineup_state.lineup_state = 'missing'
      )::integer,
      count(*) filter (
        where lineup_state.reminder_sent
      )::integer,
      coalesce(
        jsonb_agg(
          jsonb_build_object(
            'teamId', lineup_state.team_id,
            'teamName', lineup_state.team_name,
            'managerId', lineup_state.manager_id,
            'managerName', lineup_state.manager_name,
            'status', lineup_state.lineup_state,
            'submittedAt', lineup_state.submitted_at,
            'reminderSent', lineup_state.reminder_sent
          )
          order by
            case lineup_state.lineup_state
              when 'missing' then 0
              when 'draft' then 1
              when 'carried' then 2
              else 3
            end,
            lineup_state.team_name,
            lineup_state.team_id
        ),
        '[]'::jsonb
      )
    into
      v_team_count,
      v_manual_count,
      v_carried_count,
      v_draft_count,
      v_missing_count,
      v_reminder_sent_count,
      v_team_states
    from lineup_states lineup_state;

    select jsonb_build_object(
      'id', matchday.id,
      'number', matchday.number,
      'startsAt', matchday.starts_at,
      'locksAt', matchday.locks_at,
      'endsAt', matchday.ends_at,
      'scheduleSource', matchday.schedule_source,
      'scheduleSyncedAt', matchday.schedule_synced_at,
      'providerFixtureCount', matchday.provider_fixture_count,
      'providerFinalFixtureCount',
        matchday.provider_final_fixture_count,
      'teamCount', v_team_count,
      'manualCount', v_manual_count,
      'carriedCount', v_carried_count,
      'draftCount', v_draft_count,
      'missingCount', v_missing_count,
      'reminderSentCount', v_reminder_sent_count,
      'canRemind',
        v_is_owner
        and v_league.competition_started_at is not null
        and matchday.locks_at > now()
        and v_manual_count + v_carried_count < v_team_count,
      'teams', v_team_states
    )
    into v_next_lineup_matchday
    from public.matchdays matchday
    where matchday.id = v_next_matchday_id;
  end if;

  return jsonb_build_object(
    'leagueId', v_league.id,
    'leagueName', v_league.name,
    'leagueStatus', v_league.status,
    'season', v_league.calendar_season,
    'competitionStartedAt', v_league.competition_started_at,
    'isOwner', v_is_owner,
    'isDirector', v_is_director,
    'generatedAt', now(),
    'focusMatchday', v_focus_matchday,
    'nextLineupMatchday', v_next_lineup_matchday
  );
end;
$$;

revoke all on function public.get_league_operations_center(uuid)
from public, anon;

grant execute on function public.get_league_operations_center(uuid)
to authenticated;

create or replace function public.send_league_lineup_reminders(
  p_league_id uuid,
  p_matchday_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_league public.leagues%rowtype;
  v_matchday public.matchdays%rowtype;
  v_team record;
  v_notification_id uuid;
  v_dedupe_key text;
  v_target_count integer := 0;
  v_sent_count integer := 0;
  v_already_sent_count integer := 0;
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
    raise exception 'Solo il Presidente può inviare i promemoria.';
  end if;

  if v_league.competition_started_at is null then
    raise exception 'La competizione non è ancora iniziata.';
  end if;

  select matchday.*
  into v_matchday
  from public.matchdays matchday
  where matchday.id = p_matchday_id
    and exists (
      select 1
      from public.fantasy_fixtures fixture
      where fixture.league_id = p_league_id
        and fixture.matchday_id = matchday.id
    );

  if not found then
    raise exception 'Giornata non trovata nella lega.';
  end if;

  if now() >= v_matchday.locks_at then
    raise exception 'La scadenza delle formazioni è già trascorsa.';
  end if;

  for v_team in
    with participating_teams as (
      select fixture.home_team_id as team_id
      from public.fantasy_fixtures fixture
      where fixture.league_id = p_league_id
        and fixture.matchday_id = p_matchday_id

      union

      select fixture.away_team_id
      from public.fantasy_fixtures fixture
      where fixture.league_id = p_league_id
        and fixture.matchday_id = p_matchday_id
    )
    select
      team.id,
      team.manager_id,
      team.name
    from participating_teams participant
    join public.fantasy_teams team
      on team.id = participant.team_id
    where not exists (
      select 1
      from public.lineups lineup
      where lineup.fantasy_team_id = team.id
        and lineup.matchday_id = p_matchday_id
        and lineup.status in ('submitted', 'locked')
    )
    order by team.name, team.id
  loop
    v_target_count := v_target_count + 1;
    v_dedupe_key :=
      'lineup:manual-reminder:'
      || p_league_id::text
      || ':'
      || p_matchday_id::text
      || ':'
      || v_team.id::text;

    if exists (
      select 1
      from public.user_notifications notification
      where notification.user_id = v_team.manager_id
        and notification.dedupe_key = v_dedupe_key
    ) then
      v_already_sent_count := v_already_sent_count + 1;
      continue;
    end if;

    select public.create_user_notification(
      v_team.manager_id,
      p_league_id,
      'lineup',
      'Formazione ancora da consegnare',
      'Giornata '
        || v_matchday.number
        || ': la distinta di '
        || v_team.name
        || ' non risulta ancora consegnata.',
      'lineup',
      jsonb_build_object(
        'event', 'manual_lineup_reminder',
        'matchday_id', p_matchday_id,
        'matchday_number', v_matchday.number,
        'fantasy_team_id', v_team.id,
        'locks_at', v_matchday.locks_at
      ),
      v_dedupe_key
    )
    into v_notification_id;

    if v_notification_id is null then
      v_already_sent_count := v_already_sent_count + 1;
    else
      v_sent_count := v_sent_count + 1;
    end if;
  end loop;

  return jsonb_build_object(
    'matchdayId', p_matchday_id,
    'matchdayNumber', v_matchday.number,
    'targetCount', v_target_count,
    'sentCount', v_sent_count,
    'alreadySentCount', v_already_sent_count
  );
end;
$$;

revoke all on function public.send_league_lineup_reminders(uuid, uuid)
from public, anon;

grant execute on function public.send_league_lineup_reminders(uuid, uuid)
to authenticated;

select
  to_regprocedure(
    'public.get_league_operations_center(uuid)'
  ) is not null as operations_center_function_ready,
  exists (
    select 1
    from information_schema.routines routine
    where routine.routine_schema = 'public'
      and routine.routine_name = 'get_league_operations_center'
      and routine.security_type = 'DEFINER'
  ) as operations_center_security_ready,
  exists (
    select 1
    from pg_proc procedure
    join pg_namespace namespace
      on namespace.oid = procedure.pronamespace
    where namespace.nspname = 'public'
      and procedure.proname = 'get_league_operations_center'
      and procedure.provolatile = 's'
  ) as operations_center_stable_ready,
  has_function_privilege(
    'authenticated',
    'public.get_league_operations_center(uuid)',
    'EXECUTE'
  ) as operations_center_director_access_ready,
  not has_function_privilege(
    'anon',
    'public.get_league_operations_center(uuid)',
    'EXECUTE'
  ) as anonymous_operations_center_blocked,
  to_regprocedure(
    'public.send_league_lineup_reminders(uuid,uuid)'
  ) is not null as lineup_reminder_function_ready,
  exists (
    select 1
    from information_schema.routines routine
    where routine.routine_schema = 'public'
      and routine.routine_name = 'send_league_lineup_reminders'
      and routine.security_type = 'DEFINER'
  ) as lineup_reminder_security_ready,
  has_function_privilege(
    'authenticated',
    'public.send_league_lineup_reminders(uuid,uuid)',
    'EXECUTE'
  ) as lineup_reminder_president_access_ready,
  not has_function_privilege(
    'anon',
    'public.send_league_lineup_reminders(uuid,uuid)',
    'EXECUTE'
  ) as anonymous_lineup_reminder_blocked,
  to_regclass('public.user_notifications') is not null
    as lineup_reminder_notifications_ready,
  exists (
    select 1
    from pg_indexes index_info
    where index_info.schemaname = 'public'
      and index_info.indexname = 'user_notifications_dedupe_idx'
  ) as lineup_reminder_deduplication_ready,
  exists (
    select 1
    from information_schema.columns column_info
    where column_info.table_schema = 'public'
      and column_info.table_name = 'lineups'
      and column_info.column_name = 'submission_source'
  ) as lineup_status_source_ready;
