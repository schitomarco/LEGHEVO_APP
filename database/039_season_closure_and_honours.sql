-- LEGHEVO · chiusura stagione, classifica finale e albo d'oro
-- Eseguire nel SQL Editor di Supabase dopo 038.

alter table public.leagues
  add column if not exists competition_completed_at timestamptz,
  add column if not exists champion_team_id uuid;

alter table public.leagues
  drop constraint if exists leagues_champion_team_id_fkey;

alter table public.leagues
  add constraint leagues_champion_team_id_fkey
  foreign key (champion_team_id)
  references public.fantasy_teams(id)
  on delete set null;

create table if not exists public.league_season_summaries (
  league_id uuid primary key
    references public.leagues(id) on delete cascade,
  season text not null,
  champion_team_id uuid not null
    references public.fantasy_teams(id),
  champion_team_name text not null,
  champion_manager_name text not null,
  standings_tiebreaker text not null check (
    standings_tiebreaker in (
      'goal_difference',
      'fantasy_points',
      'head_to_head'
    )
  ),
  fixture_count integer not null check (fixture_count > 0),
  final_standings jsonb not null check (
    jsonb_typeof(final_standings) = 'array'
    and jsonb_array_length(final_standings) > 0
  ),
  completed_at timestamptz not null default now(),
  completed_by uuid references public.profiles(id) on delete set null
);

alter table public.league_season_summaries
  enable row level security;

drop policy if exists league_season_summaries_read_members
on public.league_season_summaries;

create policy league_season_summaries_read_members
on public.league_season_summaries
for select to authenticated
using (
  public.is_league_member(league_id)
  or public.is_league_admin(league_id)
);

revoke all on public.league_season_summaries
from public, anon, authenticated;

grant select on public.league_season_summaries
to authenticated;

create or replace function public.protect_completed_league_fixture()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if exists (
    select 1
    from public.leagues league
    where league.id = old.league_id
      and league.status in ('completed', 'archived')
  ) then
    raise exception
      'La stagione è conclusa: risultati e revisioni sono congelati.';
  end if;

  return new;
end;
$$;

revoke all on function public.protect_completed_league_fixture()
from public, anon, authenticated;

drop trigger if exists protect_completed_league_fixture
on public.fantasy_fixtures;

create trigger protect_completed_league_fixture
before update on public.fantasy_fixtures
for each row
execute function public.protect_completed_league_fixture();

create or replace function public.protect_completed_league_settings()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.status in ('completed', 'archived')
    and new.scoring_rules is distinct from old.scoring_rules then
    raise exception
      'La stagione è conclusa: il regolamento è congelato.';
  end if;

  return new;
end;
$$;

revoke all on function public.protect_completed_league_settings()
from public, anon, authenticated;

drop trigger if exists protect_completed_league_settings
on public.leagues;

create trigger protect_completed_league_settings
before update of scoring_rules on public.leagues
for each row
execute function public.protect_completed_league_settings();

create or replace function public.get_league_season_state(
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
  v_summary public.league_season_summaries%rowtype;
  v_fixture_count integer := 0;
  v_official_fixture_count integer := 0;
  v_champion jsonb := null;
  v_final_standings jsonb := '[]'::jsonb;
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

  select
    count(*)::integer,
    count(*) filter (
      where fixture.finalized_at is not null
    )::integer
  into
    v_fixture_count,
    v_official_fixture_count
  from public.fantasy_fixtures fixture
  where fixture.league_id = p_league_id;

  select summary.*
  into v_summary
  from public.league_season_summaries summary
  where summary.league_id = p_league_id;

  if found then
    v_final_standings := v_summary.final_standings;
    v_champion := jsonb_build_object(
      'teamId', v_summary.champion_team_id,
      'teamName', v_summary.champion_team_name,
      'managerName', v_summary.champion_manager_name,
      'leaguePoints',
        coalesce(
          (v_summary.final_standings -> 0 ->> 'leaguePoints')::integer,
          0
        ),
      'pointsFor',
        coalesce(
          (v_summary.final_standings -> 0 ->> 'pointsFor')::numeric,
          0
        )
    );
  end if;

  return jsonb_build_object(
    'leagueStatus', v_league.status,
    'season',
      coalesce(
        v_summary.season,
        v_league.calendar_season,
        (
          select min(matchday.season)
          from public.matchdays matchday
          join public.fantasy_fixtures fixture
            on fixture.matchday_id = matchday.id
          where fixture.league_id = p_league_id
        )
      ),
    'competitionStartedAt', v_league.competition_started_at,
    'completedAt',
      coalesce(
        v_summary.completed_at,
        v_league.competition_completed_at
      ),
    'isOwner', v_league.owner_id = auth.uid(),
    'fixtureCount', v_fixture_count,
    'officialFixtureCount', v_official_fixture_count,
    'remainingFixtureCount',
      greatest(v_fixture_count - v_official_fixture_count, 0),
    'canComplete',
      v_league.owner_id = auth.uid()
      and v_league.status = 'active'
      and v_league.competition_started_at is not null
      and v_fixture_count > 0
      and v_official_fixture_count = v_fixture_count,
    'champion', v_champion,
    'standingsTiebreaker',
      coalesce(
        v_summary.standings_tiebreaker,
        case
          when lower(
            coalesce(
              v_league.scoring_rules ->> 'standings_tiebreaker',
              'goal_difference'
            )
          ) in (
            'goal_difference',
            'fantasy_points',
            'head_to_head'
          )
            then lower(
              coalesce(
                v_league.scoring_rules ->> 'standings_tiebreaker',
                'goal_difference'
              )
            )
          else 'goal_difference'
        end
      ),
    'finalStandings', v_final_standings
  );
end;
$$;

create or replace function public.get_league_management_state_v2(
  p_league_id uuid
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select
    public.get_league_management_state(p_league_id)
      || public.get_league_season_state(p_league_id)
$$;

create or replace function public.complete_league_season(
  p_league_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_league public.leagues%rowtype;
  v_fixture_count integer := 0;
  v_official_fixture_count integer := 0;
  v_team_count integer := 0;
  v_final_standings jsonb := '[]'::jsonb;
  v_champion_team_id uuid;
  v_champion_team_name text;
  v_champion_manager_name text;
  v_tiebreaker text := 'goal_difference';
  v_season text;
  v_completed_at timestamptz := now();
  v_member_user_id uuid;
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
    raise exception 'Solo il Presidente può chiudere la stagione.';
  end if;

  if v_league.status = 'archived' then
    raise exception 'La lega è già archiviata.';
  end if;

  if v_league.status = 'completed' then
    select summary.champion_team_id
    into v_champion_team_id
    from public.league_season_summaries summary
    where summary.league_id = p_league_id;

    return coalesce(v_champion_team_id, v_league.champion_team_id);
  end if;

  if v_league.status <> 'active'
    or v_league.competition_started_at is null then
    raise exception 'La competizione non è ancora iniziata.';
  end if;

  select
    count(*)::integer,
    count(*) filter (
      where fixture.finalized_at is not null
    )::integer
  into
    v_fixture_count,
    v_official_fixture_count
  from public.fantasy_fixtures fixture
  where fixture.league_id = p_league_id;

  if v_fixture_count = 0 then
    raise exception 'Il calendario non contiene partite.';
  end if;

  if v_official_fixture_count <> v_fixture_count then
    raise exception
      'Tutti i risultati devono essere ufficiali prima della chiusura.';
  end if;

  select count(*)::integer
  into v_team_count
  from public.fantasy_teams team
  where team.league_id = p_league_id;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'position', standing.position,
        'teamId', standing.fantasy_team_id,
        'teamName', standing.team_name,
        'managerName', profile.display_name,
        'played', standing.played,
        'won', standing.won,
        'drawn', standing.drawn,
        'lost', standing.lost,
        'goalsFor', standing.goals_for,
        'goalsAgainst', standing.goals_against,
        'goalDifference', standing.goal_difference,
        'pointsFor', standing.points_for,
        'leaguePoints', standing.league_points
      )
      order by standing.position
    ),
    '[]'::jsonb
  )
  into v_final_standings
  from public.get_league_standings_v2(p_league_id) standing
  join public.fantasy_teams team
    on team.id = standing.fantasy_team_id
  join public.profiles profile
    on profile.id = team.manager_id;

  if jsonb_array_length(v_final_standings) <> v_team_count
    or v_team_count = 0 then
    raise exception
      'La classifica finale non contiene tutte le squadre.';
  end if;

  v_champion_team_id :=
    (v_final_standings -> 0 ->> 'teamId')::uuid;
  v_champion_team_name :=
    v_final_standings -> 0 ->> 'teamName';
  v_champion_manager_name :=
    v_final_standings -> 0 ->> 'managerName';

  v_tiebreaker := case
    when lower(
      coalesce(
        v_league.scoring_rules ->> 'standings_tiebreaker',
        'goal_difference'
      )
    ) in (
      'goal_difference',
      'fantasy_points',
      'head_to_head'
    )
      then lower(
        coalesce(
          v_league.scoring_rules ->> 'standings_tiebreaker',
          'goal_difference'
        )
      )
    else 'goal_difference'
  end;

  select coalesce(
    v_league.calendar_season,
    min(matchday.season),
    extract(year from v_completed_at)::integer::text
  )
  into v_season
  from public.matchdays matchday
  join public.fantasy_fixtures fixture
    on fixture.matchday_id = matchday.id
  where fixture.league_id = p_league_id;

  insert into public.league_season_summaries (
    league_id,
    season,
    champion_team_id,
    champion_team_name,
    champion_manager_name,
    standings_tiebreaker,
    fixture_count,
    final_standings,
    completed_at,
    completed_by
  )
  values (
    p_league_id,
    v_season,
    v_champion_team_id,
    v_champion_team_name,
    v_champion_manager_name,
    v_tiebreaker,
    v_fixture_count,
    v_final_standings,
    v_completed_at,
    auth.uid()
  );

  update public.leagues
  set
    status = 'completed',
    invites_open = false,
    champion_team_id = v_champion_team_id,
    competition_completed_at = v_completed_at,
    scoring_rules = coalesce(scoring_rules, '{}'::jsonb)
      || jsonb_build_object('market_open', false),
    updated_at = v_completed_at
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
      'Campionato concluso',
      v_champion_team_name
        || ' è Campione di '
        || v_league.name
        || '. La classifica finale è ora nell''albo della lega.',
      'standings',
      jsonb_build_object(
        'event', 'season_completed',
        'champion_team_id', v_champion_team_id,
        'season', v_season
      ),
      'season:completed:'
        || p_league_id::text
        || ':'
        || v_member_user_id::text
    );
  end loop;

  return v_champion_team_id;
end;
$$;

create or replace function public.get_league_results_center_v6(
  p_league_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_center jsonb;
  v_matchdays jsonb;
  v_locked boolean := false;
begin
  v_center := public.get_league_results_center_v5(p_league_id);

  select league.status in ('completed', 'archived')
  into v_locked
  from public.leagues league
  where league.id = p_league_id;

  if not coalesce(v_locked, false) then
    return v_center;
  end if;

  select coalesce(
    jsonb_agg(
      matchday.item
        || jsonb_build_object(
          'canFinalize', false,
          'canReopen', false,
          'fixtures',
            coalesce(
              (
                select jsonb_agg(
                  fixture.item
                    || jsonb_build_object('canCorrect', false)
                  order by fixture.position
                )
                from jsonb_array_elements(
                  coalesce(matchday.item -> 'fixtures', '[]'::jsonb)
                ) with ordinality as fixture(item, position)
              ),
              '[]'::jsonb
            )
        )
      order by matchday.position
    ),
    '[]'::jsonb
  )
  into v_matchdays
  from jsonb_array_elements(
    coalesce(v_center -> 'matchdays', '[]'::jsonb)
  ) with ordinality as matchday(item, position);

  return jsonb_set(
    v_center,
    '{matchdays}',
    v_matchdays,
    true
  );
end;
$$;

revoke all on function public.get_league_season_state(uuid)
from public, anon, authenticated;

revoke all on function public.get_league_management_state_v2(uuid)
from public, anon, authenticated;

revoke all on function public.complete_league_season(uuid)
from public, anon, authenticated;

revoke all on function public.get_league_results_center_v6(uuid)
from public, anon, authenticated;

grant execute on function public.get_league_season_state(uuid)
to authenticated;

grant execute on function public.get_league_management_state_v2(uuid)
to authenticated;

grant execute on function public.complete_league_season(uuid)
to authenticated;

grant execute on function public.get_league_results_center_v6(uuid)
to authenticated;

do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'league_season_summaries'
  ) then
    alter publication supabase_realtime
      add table public.league_season_summaries;
  end if;
end;
$$;

select
  (
    select count(*) = 2
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'leagues'
      and column_name in (
        'competition_completed_at',
        'champion_team_id'
      )
  ) as league_closure_columns_ready,
  to_regclass(
    'public.league_season_summaries'
  ) is not null as season_summary_ready,
  (
    select relrowsecurity
    from pg_class
    where oid = 'public.league_season_summaries'::regclass
  ) as season_summary_rls_ready,
  has_table_privilege(
    'authenticated',
    'public.league_season_summaries',
    'SELECT'
  ) as season_summary_read_ready,
  not has_table_privilege(
    'authenticated',
    'public.league_season_summaries',
    'INSERT'
  ) as season_summary_write_blocked,
  to_regprocedure(
    'public.complete_league_season(uuid)'
  ) is not null as season_completion_ready,
  has_function_privilege(
    'authenticated',
    'public.complete_league_season(uuid)',
    'EXECUTE'
  ) as season_completion_access_ready,
  not has_function_privilege(
    'anon',
    'public.complete_league_season(uuid)',
    'EXECUTE'
  ) as anonymous_completion_blocked,
  to_regprocedure(
    'public.get_league_season_state(uuid)'
  ) is not null as season_state_ready,
  to_regprocedure(
    'public.get_league_management_state_v2(uuid)'
  ) is not null as management_v2_ready,
  to_regprocedure(
    'public.get_league_results_center_v6(uuid)'
  ) is not null as results_center_v6_ready,
  exists (
    select 1
    from pg_trigger
    where tgrelid = 'public.fantasy_fixtures'::regclass
      and tgname = 'protect_completed_league_fixture'
      and not tgisinternal
  )
  and exists (
    select 1
    from pg_trigger
    where tgrelid = 'public.leagues'::regclass
      and tgname = 'protect_completed_league_settings'
      and not tgisinternal
  ) as completed_season_guards_ready;
