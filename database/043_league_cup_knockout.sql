-- LEGHEVO · Coppa di Lega a eliminazione diretta
-- Eseguire nel SQL Editor di Supabase dopo 042.
-- Lo script aggiunge struttura e funzioni, ma non crea né avvia alcuna coppa.

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
      'leagueCup',
      'lineup',
      'roster',
      'standings',
      'market'
    )
  );

create table if not exists public.league_cups (
  id uuid primary key default gen_random_uuid(),
  league_id uuid not null unique
    references public.leagues(id) on delete cascade,
  name text not null default 'Coppa di Lega'
    check (char_length(trim(name)) between 1 and 80),
  status text not null default 'active'
    check (status in ('active', 'completed')),
  draw_seed uuid not null,
  team_count smallint not null
    check (team_count between 2 and 20),
  bracket_size smallint not null
    check (bracket_size in (2, 4, 8, 16, 32)),
  round_count smallint not null
    check (round_count between 1 and 5),
  current_round smallint not null default 1
    check (current_round between 1 and 5),
  champion_team_id uuid references public.fantasy_teams(id),
  runner_up_team_id uuid references public.fantasy_teams(id),
  created_by uuid not null references public.profiles(id),
  started_at timestamptz not null default now(),
  completed_at timestamptz,
  updated_at timestamptz not null default now(),
  check (champion_team_id is null or champion_team_id <> runner_up_team_id)
);

create table if not exists public.league_cup_entries (
  cup_id uuid not null
    references public.league_cups(id) on delete cascade,
  fantasy_team_id uuid not null
    references public.fantasy_teams(id) on delete cascade,
  seed smallint not null check (seed between 1 and 32),
  eliminated_round smallint check (eliminated_round between 1 and 5),
  final_position smallint check (final_position in (1, 2)),
  primary key (cup_id, fantasy_team_id),
  unique (cup_id, seed)
);

create table if not exists public.league_cup_rounds (
  id uuid primary key default gen_random_uuid(),
  cup_id uuid not null
    references public.league_cups(id) on delete cascade,
  round_number smallint not null check (round_number between 1 and 5),
  name text not null check (char_length(trim(name)) between 1 and 40),
  matchday_id uuid not null references public.matchdays(id),
  status text not null default 'scheduled'
    check (status in ('scheduled', 'official')),
  finalized_at timestamptz,
  finalized_by uuid references public.profiles(id),
  unique (cup_id, round_number),
  unique (cup_id, matchday_id)
);

create table if not exists public.league_cup_ties (
  id uuid primary key default gen_random_uuid(),
  round_id uuid not null
    references public.league_cup_rounds(id) on delete cascade,
  bracket_position smallint not null check (bracket_position between 1 and 16),
  home_team_id uuid references public.fantasy_teams(id),
  away_team_id uuid references public.fantasy_teams(id),
  home_seed smallint check (home_seed between 1 and 32),
  away_seed smallint check (away_seed between 1 and 32),
  home_points numeric(7,2),
  away_points numeric(7,2),
  home_goals smallint,
  away_goals smallint,
  home_ready boolean not null default false,
  away_ready boolean not null default false,
  home_counted_players smallint not null default 0
    check (home_counted_players between 0 and 11),
  away_counted_players smallint not null default 0
    check (away_counted_players between 0 and 11),
  winner_team_id uuid references public.fantasy_teams(id),
  decided_by text check (
    decided_by is null
    or decided_by in ('goals', 'fantasy_points', 'seed', 'bye')
  ),
  finalized_at timestamptz,
  finalized_by uuid references public.profiles(id),
  unique (round_id, bracket_position),
  check (home_team_id is null or home_team_id <> away_team_id)
);

create index if not exists league_cup_entries_team_idx
  on public.league_cup_entries (fantasy_team_id, cup_id);

create index if not exists league_cup_rounds_matchday_idx
  on public.league_cup_rounds (matchday_id, cup_id);

create index if not exists league_cup_ties_round_idx
  on public.league_cup_ties (round_id, bracket_position);

drop trigger if exists league_cups_set_updated_at
on public.league_cups;

create trigger league_cups_set_updated_at
before update on public.league_cups
for each row execute function public.set_updated_at();

alter table public.league_cups enable row level security;
alter table public.league_cup_entries enable row level security;
alter table public.league_cup_rounds enable row level security;
alter table public.league_cup_ties enable row level security;

drop policy if exists league_cups_read_members
on public.league_cups;

create policy league_cups_read_members
on public.league_cups for select to authenticated
using (
  public.is_league_member(league_id)
  or public.is_league_admin(league_id)
);

drop policy if exists league_cup_entries_read_members
on public.league_cup_entries;

create policy league_cup_entries_read_members
on public.league_cup_entries for select to authenticated
using (
  exists (
    select 1
    from public.league_cups cup
    where cup.id = cup_id
      and (
        public.is_league_member(cup.league_id)
        or public.is_league_admin(cup.league_id)
      )
  )
);

drop policy if exists league_cup_rounds_read_members
on public.league_cup_rounds;

create policy league_cup_rounds_read_members
on public.league_cup_rounds for select to authenticated
using (
  exists (
    select 1
    from public.league_cups cup
    where cup.id = cup_id
      and (
        public.is_league_member(cup.league_id)
        or public.is_league_admin(cup.league_id)
      )
  )
);

drop policy if exists league_cup_ties_read_members
on public.league_cup_ties;

create policy league_cup_ties_read_members
on public.league_cup_ties for select to authenticated
using (
  exists (
    select 1
    from public.league_cup_rounds cup_round
    join public.league_cups cup on cup.id = cup_round.cup_id
    where cup_round.id = round_id
      and (
        public.is_league_member(cup.league_id)
        or public.is_league_admin(cup.league_id)
      )
  )
);

revoke all on public.league_cups
from public, anon, authenticated;
revoke all on public.league_cup_entries
from public, anon, authenticated;
revoke all on public.league_cup_rounds
from public, anon, authenticated;
revoke all on public.league_cup_ties
from public, anon, authenticated;

grant select on public.league_cups to authenticated;
grant select on public.league_cup_entries to authenticated;
grant select on public.league_cup_rounds to authenticated;
grant select on public.league_cup_ties to authenticated;

create or replace function public.league_cup_round_label(
  p_round_number integer,
  p_round_count integer
)
returns text
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_rounds_from_final integer;
begin
  v_rounds_from_final := p_round_count - p_round_number;

  return case v_rounds_from_final
    when 0 then 'Finale'
    when 1 then 'Semifinali'
    when 2 then 'Quarti di finale'
    when 3 then 'Ottavi di finale'
    when 4 then 'Sedicesimi di finale'
    else format('Turno %s', p_round_number)
  end;
end;
$$;

revoke all on function public.league_cup_round_label(integer, integer)
from public, anon, authenticated;

create or replace function public.refresh_league_cup_round_internal(
  p_cup_id uuid,
  p_round_number integer
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tie record;
  v_home_breakdown jsonb;
  v_away_breakdown jsonb;
  v_goal_resolution jsonb;
  v_updated integer := 0;
begin
  for v_tie in
    select
      tie.id,
      tie.home_team_id,
      tie.away_team_id,
      tie.finalized_at,
      cup_round.matchday_id,
      league.scoring_rules
    from public.league_cup_ties tie
    join public.league_cup_rounds cup_round
      on cup_round.id = tie.round_id
    join public.league_cups cup on cup.id = cup_round.cup_id
    join public.leagues league on league.id = cup.league_id
    where cup.id = p_cup_id
      and cup_round.round_number = p_round_number
      and tie.home_team_id is not null
      and tie.away_team_id is not null
      and tie.finalized_at is null
    for update of tie
  loop
    v_home_breakdown := public.get_team_matchday_breakdown(
      v_tie.home_team_id,
      v_tie.matchday_id
    );
    v_away_breakdown := public.get_team_matchday_breakdown(
      v_tie.away_team_id,
      v_tie.matchday_id
    );

    v_goal_resolution := public.resolve_fantasy_fixture_goals(
      nullif(v_home_breakdown ->> 'totalPoints', '')::numeric,
      nullif(v_away_breakdown ->> 'totalPoints', '')::numeric,
      v_tie.scoring_rules
    );

    update public.league_cup_ties
    set
      home_points =
        nullif(v_home_breakdown ->> 'totalPoints', '')::numeric,
      away_points =
        nullif(v_away_breakdown ->> 'totalPoints', '')::numeric,
      home_goals =
        nullif(v_goal_resolution ->> 'homeGoals', '')::smallint,
      away_goals =
        nullif(v_goal_resolution ->> 'awayGoals', '')::smallint,
      home_ready =
        coalesce((v_home_breakdown ->> 'isReady')::boolean, false),
      away_ready =
        coalesce((v_away_breakdown ->> 'isReady')::boolean, false),
      home_counted_players = least(
        greatest(
          coalesce(
            (v_home_breakdown ->> 'countedPlayers')::integer,
            0
          ),
          0
        ),
        11
      ),
      away_counted_players = least(
        greatest(
          coalesce(
            (v_away_breakdown ->> 'countedPlayers')::integer,
            0
          ),
          0
        ),
        11
      )
    where id = v_tie.id;

    v_updated := v_updated + 1;
  end loop;

  return v_updated;
end;
$$;

revoke all on function public.refresh_league_cup_round_internal(uuid, integer)
from public, anon, authenticated;

create or replace function public.get_league_cup_state(
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
  v_cup public.league_cups%rowtype;
  v_team_count integer := 0;
  v_bracket_size integer := 2;
  v_round_count integer := 1;
  v_is_owner boolean := false;
  v_start_matchdays jsonb := '[]'::jsonb;
  v_rounds jsonb := '[]'::jsonb;
  v_champion jsonb;
  v_runner_up jsonb;
  v_can_finalize boolean := false;
  v_creation_reason text;
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

  v_is_owner := v_league.owner_id = auth.uid();

  select count(*)::integer
  into v_team_count
  from public.fantasy_teams team
  where team.league_id = p_league_id;

  while v_bracket_size < greatest(v_team_count, 2) loop
    v_bracket_size := v_bracket_size * 2;
    v_round_count := v_round_count + 1;
  end loop;

  with league_matchdays as (
    select distinct
      matchday.id,
      matchday.number,
      matchday.starts_at,
      matchday.locks_at
    from public.fantasy_fixtures fixture
    join public.matchdays matchday on matchday.id = fixture.matchday_id
    where fixture.league_id = p_league_id
      and matchday.locks_at > now()
  ),
  candidates as (
    select
      league_matchday.*,
      count(*) over (
        order by league_matchday.number
        rows between current row and unbounded following
      ) as remaining_matchdays
    from league_matchdays league_matchday
  )
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', candidate.id,
        'number', candidate.number,
        'startsAt', candidate.starts_at,
        'locksAt', candidate.locks_at
      )
      order by candidate.number
    ),
    '[]'::jsonb
  )
  into v_start_matchdays
  from (
    select candidate.*
    from candidates candidate
    where candidate.remaining_matchdays >= v_round_count
    order by candidate.number
    limit 12
  ) candidate;

  select cup.*
  into v_cup
  from public.league_cups cup
  where cup.league_id = p_league_id;

  if not found then
    v_creation_reason := case
      when not v_is_owner
        then 'Solo il Presidente può creare la Coppa di Lega.'
      when v_league.status <> 'active'
        then 'La coppa si crea durante una stagione attiva.'
      when v_team_count < 2
        then 'Servono almeno due squadre.'
      when jsonb_array_length(v_start_matchdays) = 0
        then 'Non ci sono abbastanza giornate future per completare la coppa.'
      else null
    end;

    return jsonb_build_object(
      'exists', false,
      'leagueId', p_league_id,
      'isOwner', v_is_owner,
      'canCreate', v_creation_reason is null,
      'creationReason', v_creation_reason,
      'teamCount', v_team_count,
      'bracketSize', v_bracket_size,
      'roundCount', v_round_count,
      'startMatchdays', v_start_matchdays,
      'rounds', '[]'::jsonb,
      'champion', null,
      'runnerUp', null,
      'canFinalizeCurrent', false
    );
  end if;

  select jsonb_build_object(
    'teamId', team.id,
    'teamName', team.name,
    'managerName', coalesce(profile.display_name, 'Manager')
  )
  into v_champion
  from public.fantasy_teams team
  left join public.profiles profile on profile.id = team.manager_id
  where team.id = v_cup.champion_team_id;

  select jsonb_build_object(
    'teamId', team.id,
    'teamName', team.name,
    'managerName', coalesce(profile.display_name, 'Manager')
  )
  into v_runner_up
  from public.fantasy_teams team
  left join public.profiles profile on profile.id = team.manager_id
  where team.id = v_cup.runner_up_team_id;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', cup_round.id,
        'number', cup_round.round_number,
        'name', cup_round.name,
        'matchdayId', cup_round.matchday_id,
        'matchdayNumber', matchday.number,
        'startsAt', matchday.starts_at,
        'locksAt', matchday.locks_at,
        'endsAt', matchday.ends_at,
        'status',
          case
            when cup_round.finalized_at is not null then 'official'
            when now() >= coalesce(
              matchday.ends_at,
              matchday.starts_at + interval '4 days'
            )
              and not exists (
                select 1
                from public.league_cup_ties pending_tie
                where pending_tie.round_id = cup_round.id
                  and pending_tie.winner_team_id is null
                  and (
                    pending_tie.home_team_id is null
                    or pending_tie.away_team_id is null
                    or not pending_tie.home_ready
                    or not pending_tie.away_ready
                  )
              )
              then 'ready'
            when now() >= matchday.starts_at then 'live'
            else 'scheduled'
          end,
        'finalizedAt', cup_round.finalized_at,
        'ties',
          coalesce(
            (
              select jsonb_agg(
                jsonb_build_object(
                  'id', tie.id,
                  'position', tie.bracket_position,
                  'homeTeam',
                    case
                      when tie.home_team_id is null then null
                      else jsonb_build_object(
                        'id', home_team.id,
                        'name', home_team.name,
                        'managerName',
                          coalesce(home_profile.display_name, 'Manager'),
                        'seed', tie.home_seed
                      )
                    end,
                  'awayTeam',
                    case
                      when tie.away_team_id is null then null
                      else jsonb_build_object(
                        'id', away_team.id,
                        'name', away_team.name,
                        'managerName',
                          coalesce(away_profile.display_name, 'Manager'),
                        'seed', tie.away_seed
                      )
                    end,
                  'homePoints', tie.home_points,
                  'awayPoints', tie.away_points,
                  'homeGoals', tie.home_goals,
                  'awayGoals', tie.away_goals,
                  'homeReady', tie.home_ready,
                  'awayReady', tie.away_ready,
                  'homeCountedPlayers', tie.home_counted_players,
                  'awayCountedPlayers', tie.away_counted_players,
                  'winnerTeamId', tie.winner_team_id,
                  'decidedBy', tie.decided_by,
                  'finalizedAt', tie.finalized_at,
                  'status',
                    case
                      when tie.decided_by = 'bye' then 'bye'
                      when tie.finalized_at is not null then 'official'
                      when tie.home_ready and tie.away_ready then 'ready'
                      when tie.home_points is not null
                        or tie.away_points is not null then 'live'
                      else 'waiting'
                    end
                )
                order by tie.bracket_position
              )
              from public.league_cup_ties tie
              left join public.fantasy_teams home_team
                on home_team.id = tie.home_team_id
              left join public.profiles home_profile
                on home_profile.id = home_team.manager_id
              left join public.fantasy_teams away_team
                on away_team.id = tie.away_team_id
              left join public.profiles away_profile
                on away_profile.id = away_team.manager_id
              where tie.round_id = cup_round.id
            ),
            '[]'::jsonb
          )
      )
      order by cup_round.round_number
    ),
    '[]'::jsonb
  )
  into v_rounds
  from public.league_cup_rounds cup_round
  join public.matchdays matchday on matchday.id = cup_round.matchday_id
  where cup_round.cup_id = v_cup.id;

  select
    v_cup.status = 'active'
    and v_is_owner
    and now() >= coalesce(
      matchday.ends_at,
      matchday.starts_at + interval '4 days'
    )
    and not exists (
      select 1
      from public.league_cup_ties tie
      where tie.round_id = cup_round.id
        and tie.winner_team_id is null
        and (
          tie.home_team_id is null
          or tie.away_team_id is null
          or not tie.home_ready
          or not tie.away_ready
        )
    )
  into v_can_finalize
  from public.league_cup_rounds cup_round
  join public.matchdays matchday on matchday.id = cup_round.matchday_id
  where cup_round.cup_id = v_cup.id
    and cup_round.round_number = v_cup.current_round;

  return jsonb_build_object(
    'exists', true,
    'leagueId', p_league_id,
    'cupId', v_cup.id,
    'name', v_cup.name,
    'status', v_cup.status,
    'isOwner', v_is_owner,
    'canCreate', false,
    'creationReason', null,
    'teamCount', v_cup.team_count,
    'bracketSize', v_cup.bracket_size,
    'roundCount', v_cup.round_count,
    'currentRound', v_cup.current_round,
    'startedAt', v_cup.started_at,
    'completedAt', v_cup.completed_at,
    'drawSeed', v_cup.draw_seed,
    'startMatchdays', '[]'::jsonb,
    'rounds', v_rounds,
    'champion', v_champion,
    'runnerUp', v_runner_up,
    'canFinalizeCurrent', coalesce(v_can_finalize, false)
  );
end;
$$;

revoke all on function public.get_league_cup_state(uuid)
from public, anon, authenticated;

grant execute on function public.get_league_cup_state(uuid)
to authenticated;

create or replace function public.create_league_cup(
  p_league_id uuid,
  p_start_matchday_number smallint
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_league public.leagues%rowtype;
  v_cup_id uuid;
  v_draw_seed uuid := gen_random_uuid();
  v_team_count integer;
  v_bracket_size integer := 2;
  v_round_count integer := 1;
  v_played_ties integer;
  v_round integer;
  v_position integer;
  v_matchday_count integer;
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
    raise exception 'Solo il Presidente può creare la Coppa di Lega.';
  end if;

  if v_league.status <> 'active'
    or v_league.competition_started_at is null then
    raise exception 'La coppa si crea durante una stagione attiva.';
  end if;

  if exists (
    select 1
    from public.league_cups cup
    where cup.league_id = p_league_id
  ) then
    raise exception 'La Coppa di Lega esiste già.';
  end if;

  select count(*)::integer
  into v_team_count
  from public.fantasy_teams team
  where team.league_id = p_league_id;

  if v_team_count < 2 then
    raise exception 'Servono almeno due squadre.';
  end if;

  while v_bracket_size < v_team_count loop
    v_bracket_size := v_bracket_size * 2;
    v_round_count := v_round_count + 1;
  end loop;

  select count(*)::integer
  into v_matchday_count
  from (
    select distinct matchday.id
    from public.fantasy_fixtures fixture
    join public.matchdays matchday on matchday.id = fixture.matchday_id
    where fixture.league_id = p_league_id
      and matchday.number >= p_start_matchday_number
      and matchday.locks_at > now()
  ) available_matchday;

  if v_matchday_count < v_round_count then
    raise exception
      'Servono % giornate future consecutive per completare la coppa.',
      v_round_count;
  end if;

  insert into public.league_cups (
    league_id,
    name,
    status,
    draw_seed,
    team_count,
    bracket_size,
    round_count,
    current_round,
    created_by
  )
  values (
    p_league_id,
    'Coppa di Lega',
    'active',
    v_draw_seed,
    v_team_count,
    v_bracket_size,
    v_round_count,
    1,
    auth.uid()
  )
  returning id into v_cup_id;

  insert into public.league_cup_entries (
    cup_id,
    fantasy_team_id,
    seed
  )
  select
    v_cup_id,
    shuffled.id,
    shuffled.seed
  from (
    select
      team.id,
      row_number() over (
        order by md5(team.id::text || v_draw_seed::text)
      )::smallint as seed
    from public.fantasy_teams team
    where team.league_id = p_league_id
  ) shuffled;

  insert into public.league_cup_rounds (
    cup_id,
    round_number,
    name,
    matchday_id
  )
  select
    v_cup_id,
    scheduled.position,
    public.league_cup_round_label(
      scheduled.position,
      v_round_count
    ),
    scheduled.matchday_id
  from (
    select
      available.id as matchday_id,
      row_number() over (
        order by available.number
      )::smallint as position
    from (
      select distinct
        matchday.id,
        matchday.number
      from public.fantasy_fixtures fixture
      join public.matchdays matchday on matchday.id = fixture.matchday_id
      where fixture.league_id = p_league_id
        and matchday.number >= p_start_matchday_number
        and matchday.locks_at > now()
    ) available
  ) scheduled
  where scheduled.position <= v_round_count
  order by scheduled.position;

  for v_round in 1..v_round_count loop
    for v_position in 1..(
      v_bracket_size / power(2, v_round)::integer
    ) loop
      insert into public.league_cup_ties (
        round_id,
        bracket_position
      )
      select cup_round.id, v_position
      from public.league_cup_rounds cup_round
      where cup_round.cup_id = v_cup_id
        and cup_round.round_number = v_round;
    end loop;
  end loop;

  v_played_ties := v_team_count - (v_bracket_size / 2);

  with first_round_slots as (
    select
      tie.id as tie_id,
      case
        when tie.bracket_position <= v_played_ties
          then tie.bracket_position * 2 - 1
        else
          v_played_ties * 2
          + (tie.bracket_position - v_played_ties)
      end as home_seed,
      case
        when tie.bracket_position <= v_played_ties
          then tie.bracket_position * 2
        else null
      end as away_seed
    from public.league_cup_ties tie
    join public.league_cup_rounds cup_round
      on cup_round.id = tie.round_id
    where cup_round.cup_id = v_cup_id
      and cup_round.round_number = 1
  ),
  assignments as (
    select
      slot.tie_id,
      home_entry.fantasy_team_id as home_team_id,
      home_entry.seed as home_seed,
      away_entry.fantasy_team_id as away_team_id,
      away_entry.seed as away_seed
    from first_round_slots slot
    join public.league_cup_entries home_entry
      on home_entry.cup_id = v_cup_id
      and home_entry.seed = slot.home_seed
    left join public.league_cup_entries away_entry
      on away_entry.cup_id = v_cup_id
      and away_entry.seed = slot.away_seed
  )
  update public.league_cup_ties tie
  set
    home_team_id = assignment.home_team_id,
    home_seed = assignment.home_seed,
    away_team_id = assignment.away_team_id,
    away_seed = assignment.away_seed
  from assignments assignment
  where tie.id = assignment.tie_id;

  update public.league_cup_ties tie
  set
    winner_team_id = tie.home_team_id,
    decided_by = 'bye',
    finalized_at = now(),
    finalized_by = auth.uid()
  from public.league_cup_rounds cup_round
  where tie.round_id = cup_round.id
    and cup_round.cup_id = v_cup_id
    and cup_round.round_number = 1
    and tie.home_team_id is not null
    and tie.away_team_id is null;

  for v_member_user_id in
    select member.user_id
    from public.league_members member
    where member.league_id = p_league_id
  loop
    perform public.create_user_notification(
      v_member_user_id,
      p_league_id,
      'league',
      'Coppa di Lega sorteggiata',
      format(
        '%s squadre, %s turni: il tabellone è ufficiale.',
        v_team_count,
        v_round_count
      ),
      'leagueCup',
      jsonb_build_object(
        'cupId', v_cup_id,
        'roundCount', v_round_count
      ),
      format('league-cup-created:%s', v_cup_id)
    );
  end loop;

  return v_cup_id;
end;
$$;

revoke all on function public.create_league_cup(uuid, smallint)
from public, anon, authenticated;

grant execute on function public.create_league_cup(uuid, smallint)
to authenticated;

create or replace function public.recalculate_league_cup(
  p_league_id uuid
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_cup public.league_cups%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Devi effettuare l''accesso.';
  end if;

  if not public.is_league_member(p_league_id)
    and not public.is_league_admin(p_league_id) then
    raise exception 'Non fai parte di questa lega.';
  end if;

  select cup.*
  into v_cup
  from public.league_cups cup
  where cup.league_id = p_league_id;

  if not found or v_cup.status = 'completed' then
    return 0;
  end if;

  return public.refresh_league_cup_round_internal(
    v_cup.id,
    v_cup.current_round
  );
end;
$$;

revoke all on function public.recalculate_league_cup(uuid)
from public, anon, authenticated;

grant execute on function public.recalculate_league_cup(uuid)
to authenticated;

create or replace function public.finalize_league_cup_round(
  p_league_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_league public.leagues%rowtype;
  v_cup public.league_cups%rowtype;
  v_round public.league_cup_rounds%rowtype;
  v_matchday public.matchdays%rowtype;
  v_tie public.league_cup_ties%rowtype;
  v_next_round_id uuid;
  v_next_position integer;
  v_winner_id uuid;
  v_loser_id uuid;
  v_winner_seed smallint;
  v_decided_by text;
  v_unready_count integer;
  v_final_tie public.league_cup_ties%rowtype;
  v_champion_name text;
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
    raise exception 'Solo il Presidente può ufficializzare la coppa.';
  end if;

  select cup.*
  into v_cup
  from public.league_cups cup
  where cup.league_id = p_league_id
  for update;

  if not found then
    raise exception 'La Coppa di Lega non è stata creata.';
  end if;

  if v_cup.status = 'completed' then
    return public.get_league_cup_state(p_league_id);
  end if;

  select cup_round.*
  into v_round
  from public.league_cup_rounds cup_round
  where cup_round.cup_id = v_cup.id
    and cup_round.round_number = v_cup.current_round
  for update;

  select matchday.*
  into v_matchday
  from public.matchdays matchday
  where matchday.id = v_round.matchday_id;

  if now() < coalesce(
    v_matchday.ends_at,
    v_matchday.starts_at + interval '4 days'
  ) then
    raise exception 'La giornata reale del turno non è ancora terminata.';
  end if;

  perform public.refresh_league_cup_round_internal(
    v_cup.id,
    v_cup.current_round
  );

  select count(*)::integer
  into v_unready_count
  from public.league_cup_ties tie
  where tie.round_id = v_round.id
    and tie.winner_team_id is null
    and (
      tie.home_team_id is null
      or tie.away_team_id is null
      or not tie.home_ready
      or not tie.away_ready
      or tie.home_points is null
      or tie.away_points is null
      or tie.home_goals is null
      or tie.away_goals is null
    );

  if v_unready_count > 0 then
    raise exception
      'Mancano ancora voti definitivi per % sfide.',
      v_unready_count;
  end if;

  for v_tie in
    select tie.*
    from public.league_cup_ties tie
    where tie.round_id = v_round.id
      and tie.winner_team_id is null
    order by tie.bracket_position
    for update
  loop
    if v_tie.home_goals > v_tie.away_goals then
      v_winner_id := v_tie.home_team_id;
      v_loser_id := v_tie.away_team_id;
      v_winner_seed := v_tie.home_seed;
      v_decided_by := 'goals';
    elsif v_tie.away_goals > v_tie.home_goals then
      v_winner_id := v_tie.away_team_id;
      v_loser_id := v_tie.home_team_id;
      v_winner_seed := v_tie.away_seed;
      v_decided_by := 'goals';
    elsif v_tie.home_points > v_tie.away_points then
      v_winner_id := v_tie.home_team_id;
      v_loser_id := v_tie.away_team_id;
      v_winner_seed := v_tie.home_seed;
      v_decided_by := 'fantasy_points';
    elsif v_tie.away_points > v_tie.home_points then
      v_winner_id := v_tie.away_team_id;
      v_loser_id := v_tie.home_team_id;
      v_winner_seed := v_tie.away_seed;
      v_decided_by := 'fantasy_points';
    elsif v_tie.home_seed < v_tie.away_seed then
      v_winner_id := v_tie.home_team_id;
      v_loser_id := v_tie.away_team_id;
      v_winner_seed := v_tie.home_seed;
      v_decided_by := 'seed';
    else
      v_winner_id := v_tie.away_team_id;
      v_loser_id := v_tie.home_team_id;
      v_winner_seed := v_tie.away_seed;
      v_decided_by := 'seed';
    end if;

    update public.league_cup_ties
    set
      winner_team_id = v_winner_id,
      decided_by = v_decided_by,
      finalized_at = now(),
      finalized_by = auth.uid()
    where id = v_tie.id;

    update public.league_cup_entries
    set eliminated_round = v_cup.current_round
    where cup_id = v_cup.id
      and fantasy_team_id = v_loser_id;
  end loop;

  update public.league_cup_rounds
  set
    status = 'official',
    finalized_at = now(),
    finalized_by = auth.uid()
  where id = v_round.id;

  if v_cup.current_round = v_cup.round_count then
    select tie.*
    into v_final_tie
    from public.league_cup_ties tie
    where tie.round_id = v_round.id
    order by tie.bracket_position
    limit 1;

    v_winner_id := v_final_tie.winner_team_id;
    v_loser_id := case
      when v_final_tie.home_team_id = v_winner_id
        then v_final_tie.away_team_id
      else v_final_tie.home_team_id
    end;

    update public.league_cups
    set
      status = 'completed',
      champion_team_id = v_winner_id,
      runner_up_team_id = v_loser_id,
      completed_at = now()
    where id = v_cup.id;

    update public.league_cup_entries
    set final_position = case
      when fantasy_team_id = v_winner_id then 1
      when fantasy_team_id = v_loser_id then 2
      else final_position
    end
    where cup_id = v_cup.id
      and fantasy_team_id in (v_winner_id, v_loser_id);

    select team.name
    into v_champion_name
    from public.fantasy_teams team
    where team.id = v_winner_id;

    for v_member_user_id in
      select member.user_id
      from public.league_members member
      where member.league_id = p_league_id
    loop
      perform public.create_user_notification(
        v_member_user_id,
        p_league_id,
        'league',
        'La Coppa di Lega ha un campione',
        format('%s alza la coppa. Il tabellone è definitivo.', v_champion_name),
        'leagueCup',
        jsonb_build_object(
          'cupId', v_cup.id,
          'championTeamId', v_winner_id
        ),
        format('league-cup-completed:%s', v_cup.id)
      );
    end loop;
  else
    select cup_round.id
    into v_next_round_id
    from public.league_cup_rounds cup_round
    where cup_round.cup_id = v_cup.id
      and cup_round.round_number = v_cup.current_round + 1;

    for v_tie in
      select tie.*
      from public.league_cup_ties tie
      where tie.round_id = v_round.id
      order by tie.bracket_position
    loop
      v_next_position := ceil(v_tie.bracket_position / 2.0)::integer;

      select entry.seed
      into v_winner_seed
      from public.league_cup_entries entry
      where entry.cup_id = v_cup.id
        and entry.fantasy_team_id = v_tie.winner_team_id;

      if mod(v_tie.bracket_position, 2) = 1 then
        update public.league_cup_ties
        set
          home_team_id = v_tie.winner_team_id,
          home_seed = v_winner_seed
        where round_id = v_next_round_id
          and bracket_position = v_next_position;
      else
        update public.league_cup_ties
        set
          away_team_id = v_tie.winner_team_id,
          away_seed = v_winner_seed
        where round_id = v_next_round_id
          and bracket_position = v_next_position;
      end if;
    end loop;

    update public.league_cups
    set current_round = current_round + 1
    where id = v_cup.id;

    for v_member_user_id in
      select member.user_id
      from public.league_members member
      where member.league_id = p_league_id
    loop
      perform public.create_user_notification(
        v_member_user_id,
        p_league_id,
        'league',
        format('%s ufficiali', v_round.name),
        'Il tabellone è aggiornato: il prossimo turno vi aspetta.',
        'leagueCup',
        jsonb_build_object(
          'cupId', v_cup.id,
          'roundNumber', v_cup.current_round
        ),
        format(
          'league-cup-round:%s:%s',
          v_cup.id,
          v_cup.current_round
        )
      );
    end loop;
  end if;

  return public.get_league_cup_state(p_league_id);
end;
$$;

revoke all on function public.finalize_league_cup_round(uuid)
from public, anon, authenticated;

grant execute on function public.finalize_league_cup_round(uuid)
to authenticated;

create or replace function public.block_season_close_with_open_cup()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.status = 'completed'
    and old.status is distinct from new.status
    and exists (
      select 1
      from public.league_cups cup
      where cup.league_id = new.id
        and cup.status <> 'completed'
    ) then
    raise exception
      'Prima di chiudere la stagione devi completare la Coppa di Lega.';
  end if;

  return new;
end;
$$;

revoke all on function public.block_season_close_with_open_cup()
from public, anon, authenticated;

drop trigger if exists leagues_block_open_cup_on_completion
on public.leagues;

create trigger leagues_block_open_cup_on_completion
before update of status on public.leagues
for each row execute function public.block_season_close_with_open_cup();

do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'league_cups'
  ) then
    alter publication supabase_realtime
      add table public.league_cups;
  end if;

  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'league_cup_rounds'
  ) then
    alter publication supabase_realtime
      add table public.league_cup_rounds;
  end if;

  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'league_cup_ties'
  ) then
    alter publication supabase_realtime
      add table public.league_cup_ties;
  end if;
end;
$$;

select
  to_regclass('public.league_cups') is not null
    as league_cups_ready,
  to_regclass('public.league_cup_entries') is not null
    as league_cup_entries_ready,
  to_regclass('public.league_cup_rounds') is not null
    as league_cup_rounds_ready,
  to_regclass('public.league_cup_ties') is not null
    as league_cup_ties_ready,
  to_regprocedure(
    'public.get_league_cup_state(uuid)'
  ) is not null as cup_state_ready,
  to_regprocedure(
    'public.create_league_cup(uuid,smallint)'
  ) is not null as cup_creation_ready,
  to_regprocedure(
    'public.recalculate_league_cup(uuid)'
  ) is not null as cup_recalculation_ready,
  to_regprocedure(
    'public.finalize_league_cup_round(uuid)'
  ) is not null as cup_finalization_ready,
  has_function_privilege(
    'authenticated',
    'public.get_league_cup_state(uuid)',
    'EXECUTE'
  ) as cup_read_access_ready,
  not has_function_privilege(
    'anon',
    'public.create_league_cup(uuid,smallint)',
    'EXECUTE'
  ) as anonymous_cup_creation_blocked,
  exists (
    select 1
    from information_schema.triggers
    where event_object_schema = 'public'
      and event_object_table = 'leagues'
      and trigger_name = 'leagues_block_open_cup_on_completion'
  ) as season_close_guard_ready,
  exists (
    select 1
    from information_schema.check_constraints constraint_info
    where constraint_info.constraint_schema = 'public'
      and constraint_info.constraint_name =
        'user_notifications_action_screen_check'
      and constraint_info.check_clause like '%leagueCup%'
  ) as cup_notifications_ready;
