-- LEGHEVO · cruscotto personale della squadra
-- Eseguire nel SQL Editor di Supabase dopo 026.

create or replace function public.get_my_team_dashboard(
  p_league_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_league public.leagues%rowtype;
  v_team public.fantasy_teams%rowtype;
  v_standing record;
  v_roster_count integer;
  v_member_count integer;
  v_fixture_count integer;
  v_recent_transactions jsonb;
  v_next_match jsonb;
  v_last_match jsonb;
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

  select count(*)::integer
  into v_member_count
  from public.league_members member
  where member.league_id = p_league_id;

  select count(*)::integer
  into v_fixture_count
  from public.fantasy_fixtures fixture
  where fixture.league_id = p_league_id;

  select standing.*
  into v_standing
  from public.get_league_standings(p_league_id) standing
  where standing.fantasy_team_id = v_team.id;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', transaction_row.id,
        'type', transaction_row.transaction_type,
        'athleteId', transaction_row.athlete_id,
        'athleteName', concat_ws(
          ' ',
          athlete.first_name,
          athlete.last_name
        ),
        'creditDelta', transaction_row.credit_delta,
        'createdAt', transaction_row.created_at
      )
      order by transaction_row.created_at desc
    ),
    '[]'::jsonb
  )
  into v_recent_transactions
  from (
    select transaction_item.*
    from public.team_transactions transaction_item
    where transaction_item.league_id = p_league_id
      and transaction_item.fantasy_team_id = v_team.id
    order by transaction_item.created_at desc
    limit 8
  ) transaction_row
  join public.athletes athlete
    on athlete.id = transaction_row.athlete_id;

  select jsonb_build_object(
    'fixtureId', fixture.id,
    'matchdayId', fixture.matchday_id,
    'matchdayNumber', matchday.number,
    'startsAt', matchday.starts_at,
    'home', fixture.home_team_id = v_team.id,
    'opponentId', opponent.id,
    'opponentName', opponent.name
  )
  into v_next_match
  from public.fantasy_fixtures fixture
  join public.matchdays matchday
    on matchday.id = fixture.matchday_id
  join public.fantasy_teams opponent
    on opponent.id = case
      when fixture.home_team_id = v_team.id then fixture.away_team_id
      else fixture.home_team_id
    end
  where fixture.league_id = p_league_id
    and (
      fixture.home_team_id = v_team.id
      or fixture.away_team_id = v_team.id
    )
    and fixture.finalized_at is null
    and matchday.locks_at > now()
  order by matchday.locks_at
  limit 1;

  select jsonb_build_object(
    'fixtureId', fixture.id,
    'matchdayId', fixture.matchday_id,
    'matchdayNumber', matchday.number,
    'startsAt', matchday.starts_at,
    'home', fixture.home_team_id = v_team.id,
    'opponentId', opponent.id,
    'opponentName', opponent.name,
    'myPoints', case
      when fixture.home_team_id = v_team.id then fixture.home_points
      else fixture.away_points
    end,
    'opponentPoints', case
      when fixture.home_team_id = v_team.id then fixture.away_points
      else fixture.home_points
    end,
    'myGoals', case
      when fixture.home_team_id = v_team.id then fixture.home_goals
      else fixture.away_goals
    end,
    'opponentGoals', case
      when fixture.home_team_id = v_team.id then fixture.away_goals
      else fixture.home_goals
    end
  )
  into v_last_match
  from public.fantasy_fixtures fixture
  join public.matchdays matchday
    on matchday.id = fixture.matchday_id
  join public.fantasy_teams opponent
    on opponent.id = case
      when fixture.home_team_id = v_team.id then fixture.away_team_id
      else fixture.home_team_id
    end
  where fixture.league_id = p_league_id
    and (
      fixture.home_team_id = v_team.id
      or fixture.away_team_id = v_team.id
    )
    and fixture.finalized_at is not null
  order by fixture.finalized_at desc
  limit 1;

  return jsonb_build_object(
    'teamId', v_team.id,
    'teamName', v_team.name,
    'creditsRemaining', v_team.credits_remaining,
    'startingCredits', v_league.starting_credits,
    'creditsSpent', greatest(
      v_league.starting_credits - v_team.credits_remaining,
      0
    ),
    'rosterCount', v_roster_count,
    'rosterSize', v_league.roster_size,
    'memberCount', v_member_count,
    'teamLimit', v_league.team_limit,
    'fixtureCount', v_fixture_count,
    'competitionStartedAt', v_league.competition_started_at,
    'position', coalesce(v_standing.position, 0),
    'played', coalesce(v_standing.played, 0),
    'won', coalesce(v_standing.won, 0),
    'drawn', coalesce(v_standing.drawn, 0),
    'lost', coalesce(v_standing.lost, 0),
    'goalsFor', coalesce(v_standing.goals_for, 0),
    'goalsAgainst', coalesce(v_standing.goals_against, 0),
    'pointsFor', coalesce(v_standing.points_for, 0),
    'leaguePoints', coalesce(v_standing.league_points, 0),
    'nextMatch', v_next_match,
    'lastMatch', v_last_match,
    'recentTransactions', v_recent_transactions
  );
end;
$$;

revoke all on function public.get_my_team_dashboard(uuid)
from public, anon;

grant execute on function public.get_my_team_dashboard(uuid)
to authenticated;

do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'team_transactions'
  ) then
    alter publication supabase_realtime
      add table public.team_transactions;
  end if;
end;
$$;

select
  to_regprocedure(
    'public.get_my_team_dashboard(uuid)'
  ) is not null as team_dashboard_ready,
  has_function_privilege(
    'authenticated',
    'public.get_my_team_dashboard(uuid)',
    'EXECUTE'
  ) as authenticated_allowed,
  not has_function_privilege(
    'anon',
    'public.get_my_team_dashboard(uuid)',
    'EXECUTE'
  ) as anonymous_blocked,
  exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'fantasy_teams'
  ) as teams_realtime_ready,
  exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'roster_entries'
  ) as roster_realtime_ready,
  exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'team_transactions'
  ) as transactions_realtime_ready;
