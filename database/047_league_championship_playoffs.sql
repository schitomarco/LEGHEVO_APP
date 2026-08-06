-- LEGHEVO · Playoff Scudetto opzionali
-- Eseguire nel SQL Editor di Supabase dopo 046.
-- Lo script aggiunge struttura e funzioni ma non configura, avvia o modifica
-- alcun playoff nelle leghe esistenti.

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
      'leaguePlayoffs',
      'leagueSuperCup',
      'lineup',
      'roster',
      'standings',
      'market'
    )
  );

alter table public.league_season_summaries
  add column if not exists champion_source text not null
    default 'regular_season'
    check (champion_source in ('regular_season', 'playoffs'));

create table if not exists public.league_playoffs (
  id uuid primary key default gen_random_uuid(),
  league_id uuid not null unique
    references public.leagues(id) on delete cascade,
  status text not null default 'configured'
    check (status in ('configured', 'active', 'completed')),
  participant_count smallint not null
    check (participant_count in (4, 8)),
  round_count smallint not null
    check (round_count in (2, 3)),
  current_round smallint not null default 0
    check (current_round between 0 and 3),
  champion_team_id uuid references public.fantasy_teams(id),
  runner_up_team_id uuid references public.fantasy_teams(id),
  configured_by uuid not null references public.profiles(id),
  configured_at timestamptz not null default now(),
  started_at timestamptz,
  completed_at timestamptz,
  updated_at timestamptz not null default now(),
  check (
    (participant_count = 4 and round_count = 2)
    or (participant_count = 8 and round_count = 3)
  ),
  check (champion_team_id is null or champion_team_id <> runner_up_team_id)
);

create table if not exists public.league_playoff_entries (
  playoff_id uuid not null
    references public.league_playoffs(id) on delete cascade,
  fantasy_team_id uuid not null
    references public.fantasy_teams(id) on delete cascade,
  seed smallint not null check (seed between 1 and 8),
  regular_season_position smallint not null
    check (regular_season_position between 1 and 20),
  eliminated_round smallint check (eliminated_round between 1 and 3),
  final_position smallint check (final_position in (1, 2)),
  primary key (playoff_id, fantasy_team_id),
  unique (playoff_id, seed)
);

create table if not exists public.league_playoff_rounds (
  id uuid primary key default gen_random_uuid(),
  playoff_id uuid not null
    references public.league_playoffs(id) on delete cascade,
  round_number smallint not null check (round_number between 1 and 3),
  name text not null check (char_length(trim(name)) between 1 and 40),
  matchday_id uuid not null references public.matchdays(id),
  status text not null default 'scheduled'
    check (status in ('scheduled', 'official')),
  finalized_at timestamptz,
  finalized_by uuid references public.profiles(id),
  unique (playoff_id, round_number),
  unique (playoff_id, matchday_id)
);

create table if not exists public.league_playoff_ties (
  id uuid primary key default gen_random_uuid(),
  round_id uuid not null
    references public.league_playoff_rounds(id) on delete cascade,
  bracket_position smallint not null check (bracket_position between 1 and 4),
  home_team_id uuid references public.fantasy_teams(id),
  away_team_id uuid references public.fantasy_teams(id),
  home_seed smallint check (home_seed between 1 and 8),
  away_seed smallint check (away_seed between 1 and 8),
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
    or decided_by in ('goals', 'fantasy_points', 'seed')
  ),
  finalized_at timestamptz,
  finalized_by uuid references public.profiles(id),
  unique (round_id, bracket_position),
  check (home_team_id is null or home_team_id <> away_team_id)
);

create index if not exists league_playoff_entries_team_idx
  on public.league_playoff_entries (fantasy_team_id, playoff_id);

create index if not exists league_playoff_rounds_matchday_idx
  on public.league_playoff_rounds (matchday_id, playoff_id);

create index if not exists league_playoff_ties_round_idx
  on public.league_playoff_ties (round_id, bracket_position);

drop trigger if exists league_playoffs_set_updated_at
on public.league_playoffs;

create trigger league_playoffs_set_updated_at
before update on public.league_playoffs
for each row execute function public.set_updated_at();

alter table public.league_playoffs enable row level security;
alter table public.league_playoff_entries enable row level security;
alter table public.league_playoff_rounds enable row level security;
alter table public.league_playoff_ties enable row level security;

drop policy if exists league_playoffs_read_members
on public.league_playoffs;

create policy league_playoffs_read_members
on public.league_playoffs for select to authenticated
using (
  public.is_league_member(league_id)
  or public.is_league_admin(league_id)
);

drop policy if exists league_playoff_entries_read_members
on public.league_playoff_entries;

create policy league_playoff_entries_read_members
on public.league_playoff_entries for select to authenticated
using (
  exists (
    select 1
    from public.league_playoffs playoff
    where playoff.id = playoff_id
      and (
        public.is_league_member(playoff.league_id)
        or public.is_league_admin(playoff.league_id)
      )
  )
);

drop policy if exists league_playoff_rounds_read_members
on public.league_playoff_rounds;

create policy league_playoff_rounds_read_members
on public.league_playoff_rounds for select to authenticated
using (
  exists (
    select 1
    from public.league_playoffs playoff
    where playoff.id = playoff_id
      and (
        public.is_league_member(playoff.league_id)
        or public.is_league_admin(playoff.league_id)
      )
  )
);

drop policy if exists league_playoff_ties_read_members
on public.league_playoff_ties;

create policy league_playoff_ties_read_members
on public.league_playoff_ties for select to authenticated
using (
  exists (
    select 1
    from public.league_playoff_rounds playoff_round
    join public.league_playoffs playoff
      on playoff.id = playoff_round.playoff_id
    where playoff_round.id = round_id
      and (
        public.is_league_member(playoff.league_id)
        or public.is_league_admin(playoff.league_id)
      )
  )
);

revoke all on public.league_playoffs
from public, anon, authenticated;
revoke all on public.league_playoff_entries
from public, anon, authenticated;
revoke all on public.league_playoff_rounds
from public, anon, authenticated;
revoke all on public.league_playoff_ties
from public, anon, authenticated;

grant select on public.league_playoffs to authenticated;
grant select on public.league_playoff_entries to authenticated;
grant select on public.league_playoff_rounds to authenticated;
grant select on public.league_playoff_ties to authenticated;

create or replace function public.league_playoff_round_label(
  p_round_number integer,
  p_round_count integer
)
returns text
language sql
immutable
set search_path = ''
as $$
  select case p_round_count - p_round_number
    when 0 then 'Finale Scudetto'
    when 1 then 'Semifinali'
    when 2 then 'Quarti di finale'
    else format('Turno %s', p_round_number)
  end
$$;

revoke all on function public.league_playoff_round_label(integer, integer)
from public, anon, authenticated;

create or replace function public.team_competes_on_matchday(
  p_fantasy_team_id uuid,
  p_matchday_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select
    exists (
      select 1
      from public.fantasy_teams team
      join public.fantasy_fixtures fixture
        on fixture.league_id = team.league_id
        and fixture.matchday_id = p_matchday_id
        and (
          fixture.home_team_id = team.id
          or fixture.away_team_id = team.id
        )
      where team.id = p_fantasy_team_id
    )
    or exists (
      select 1
      from public.league_playoff_ties tie
      join public.league_playoff_rounds playoff_round
        on playoff_round.id = tie.round_id
        and playoff_round.matchday_id = p_matchday_id
      join public.league_playoffs playoff
        on playoff.id = playoff_round.playoff_id
        and playoff.status = 'active'
      where p_fantasy_team_id in (
        tie.home_team_id,
        tie.away_team_id
      )
    )
$$;

revoke all on function public.team_competes_on_matchday(uuid, uuid)
from public, anon, authenticated;

create or replace function public.get_league_playoff_state(
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
  v_playoff public.league_playoffs%rowtype;
  v_team_count integer := 0;
  v_fixture_count integer := 0;
  v_official_fixture_count integer := 0;
  v_is_owner boolean := false;
  v_regular_ready boolean := false;
  v_start_matchdays jsonb := '[]'::jsonb;
  v_rounds jsonb := '[]'::jsonb;
  v_champion jsonb;
  v_runner_up jsonb;
  v_can_finalize boolean := false;
  v_action_reason text;
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

  v_regular_ready :=
    v_fixture_count > 0
    and v_fixture_count = v_official_fixture_count;

  select playoff.*
  into v_playoff
  from public.league_playoffs playoff
  where playoff.league_id = p_league_id;

  if not found then
    v_action_reason := case
      when not v_is_owner
        then 'Solo il Presidente può configurare i playoff.'
      when v_league.status <> 'draft'
        or v_league.competition_started_at is not null
        then 'Il formato playoff si decide prima dell''avvio del campionato.'
      when v_league.team_limit < 4
        then 'Servono almeno quattro squadre previste nella lega.'
      else null
    end;

    return jsonb_build_object(
      'exists', false,
      'leagueId', p_league_id,
      'status', 'not_configured',
      'isOwner', v_is_owner,
      'canConfigure', v_action_reason is null,
      'canStart', false,
      'actionReason', v_action_reason,
      'participantCount',
        case when v_league.team_limit >= 8 then 8 else 4 end,
      'roundCount',
        case when v_league.team_limit >= 8 then 3 else 2 end,
      'currentRound', 0,
      'regularSeasonReady', v_regular_ready,
      'startMatchdays', '[]'::jsonb,
      'rounds', '[]'::jsonb,
      'champion', null,
      'runnerUp', null,
      'canFinalizeCurrent', false
    );
  end if;

  if v_playoff.status = 'configured' and v_regular_ready then
    with candidates as (
      select
        matchday.id,
        matchday.number,
        matchday.starts_at,
        matchday.locks_at,
        count(*) over (
          order by matchday.number
          rows between current row and unbounded following
        ) as remaining_matchdays
      from public.matchdays matchday
      where matchday.locks_at > now()
        and (
          v_league.calendar_season is null
          or matchday.season = v_league.calendar_season
        )
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
      where candidate.remaining_matchdays >= v_playoff.round_count
      order by candidate.number
      limit 12
    ) candidate;
  end if;

  if v_playoff.status = 'configured' then
    v_action_reason := case
      when not v_is_owner
        then 'Solo il Presidente può creare il tabellone.'
      when not v_regular_ready
        then 'La stagione regolare deve avere tutti i risultati ufficiali.'
      when v_team_count < v_playoff.participant_count
        then format(
          'Servono almeno %s squadre per il formato scelto.',
          v_playoff.participant_count
        )
      when jsonb_array_length(v_start_matchdays) = 0
        then 'Non ci sono abbastanza giornate future per completare i playoff.'
      else null
    end;
  end if;

  select jsonb_build_object(
    'teamId', team.id,
    'teamName', team.name,
    'managerName', coalesce(profile.display_name, 'Manager')
  )
  into v_champion
  from public.fantasy_teams team
  left join public.profiles profile on profile.id = team.manager_id
  where team.id = v_playoff.champion_team_id;

  select jsonb_build_object(
    'teamId', team.id,
    'teamName', team.name,
    'managerName', coalesce(profile.display_name, 'Manager')
  )
  into v_runner_up
  from public.fantasy_teams team
  left join public.profiles profile on profile.id = team.manager_id
  where team.id = v_playoff.runner_up_team_id;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', playoff_round.id,
        'number', playoff_round.round_number,
        'name', playoff_round.name,
        'matchdayId', playoff_round.matchday_id,
        'matchdayNumber', matchday.number,
        'startsAt', matchday.starts_at,
        'locksAt', matchday.locks_at,
        'endsAt', matchday.ends_at,
        'status',
          case
            when playoff_round.finalized_at is not null then 'official'
            when now() >= coalesce(
              matchday.ends_at,
              matchday.starts_at + interval '4 days'
            )
              and not exists (
                select 1
                from public.league_playoff_ties pending_tie
                where pending_tie.round_id = playoff_round.id
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
        'finalizedAt', playoff_round.finalized_at,
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
                      when tie.finalized_at is not null then 'official'
                      when tie.home_ready and tie.away_ready then 'ready'
                      when tie.home_points is not null
                        or tie.away_points is not null then 'live'
                      else 'waiting'
                    end
                )
                order by tie.bracket_position
              )
              from public.league_playoff_ties tie
              left join public.fantasy_teams home_team
                on home_team.id = tie.home_team_id
              left join public.profiles home_profile
                on home_profile.id = home_team.manager_id
              left join public.fantasy_teams away_team
                on away_team.id = tie.away_team_id
              left join public.profiles away_profile
                on away_profile.id = away_team.manager_id
              where tie.round_id = playoff_round.id
            ),
            '[]'::jsonb
          )
      )
      order by playoff_round.round_number
    ),
    '[]'::jsonb
  )
  into v_rounds
  from public.league_playoff_rounds playoff_round
  join public.matchdays matchday on matchday.id = playoff_round.matchday_id
  where playoff_round.playoff_id = v_playoff.id;

  if v_playoff.status = 'active' then
    select
      v_is_owner
      and now() >= coalesce(
        matchday.ends_at,
        matchday.starts_at + interval '4 days'
      )
      and not exists (
        select 1
        from public.league_playoff_ties tie
        where tie.round_id = playoff_round.id
          and (
            tie.home_team_id is null
            or tie.away_team_id is null
            or not tie.home_ready
            or not tie.away_ready
          )
      )
    into v_can_finalize
    from public.league_playoff_rounds playoff_round
    join public.matchdays matchday
      on matchday.id = playoff_round.matchday_id
    where playoff_round.playoff_id = v_playoff.id
      and playoff_round.round_number = v_playoff.current_round;
  end if;

  return jsonb_build_object(
    'exists', true,
    'leagueId', p_league_id,
    'playoffId', v_playoff.id,
    'status', v_playoff.status,
    'isOwner', v_is_owner,
    'canConfigure', false,
    'canStart',
      v_playoff.status = 'configured'
      and v_action_reason is null,
    'actionReason', v_action_reason,
    'participantCount', v_playoff.participant_count,
    'roundCount', v_playoff.round_count,
    'currentRound', v_playoff.current_round,
    'regularSeasonReady', v_regular_ready,
    'configuredAt', v_playoff.configured_at,
    'startedAt', v_playoff.started_at,
    'completedAt', v_playoff.completed_at,
    'startMatchdays', v_start_matchdays,
    'rounds', v_rounds,
    'champion', v_champion,
    'runnerUp', v_runner_up,
    'canFinalizeCurrent', coalesce(v_can_finalize, false)
  );
end;
$$;

revoke all on function public.get_league_playoff_state(uuid)
from public, anon, authenticated;

grant execute on function public.get_league_playoff_state(uuid)
to authenticated;

create or replace function public.configure_league_playoffs(
  p_league_id uuid,
  p_participant_count smallint
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_league public.leagues%rowtype;
  v_playoff_id uuid;
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
    raise exception 'Solo il Presidente può configurare i playoff.';
  end if;

  if v_league.status <> 'draft'
    or v_league.competition_started_at is not null then
    raise exception
      'Il formato playoff si decide prima dell''avvio del campionato.';
  end if;

  if p_participant_count not in (4, 8) then
    raise exception 'I playoff possono includere quattro o otto squadre.';
  end if;

  if v_league.team_limit < p_participant_count then
    raise exception
      'Il formato scelto supera il numero di squadre della lega.';
  end if;

  insert into public.league_playoffs (
    league_id,
    status,
    participant_count,
    round_count,
    current_round,
    configured_by
  )
  values (
    p_league_id,
    'configured',
    p_participant_count,
    case when p_participant_count = 8 then 3 else 2 end,
    0,
    auth.uid()
  )
  returning id into v_playoff_id;

  return v_playoff_id;
end;
$$;

revoke all on function public.configure_league_playoffs(uuid, smallint)
from public, anon, authenticated;

grant execute on function public.configure_league_playoffs(uuid, smallint)
to authenticated;

create or replace function public.start_league_playoffs(
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
  v_playoff public.league_playoffs%rowtype;
  v_fixture_count integer := 0;
  v_official_fixture_count integer := 0;
  v_team_count integer := 0;
  v_matchday_count integer := 0;
  v_round integer;
  v_position integer;
  v_home_seed integer;
  v_away_seed integer;
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
    raise exception 'Solo il Presidente può avviare i playoff.';
  end if;

  if v_league.status <> 'active'
    or v_league.competition_started_at is null then
    raise exception 'La stagione regolare non è attiva.';
  end if;

  select playoff.*
  into v_playoff
  from public.league_playoffs playoff
  where playoff.league_id = p_league_id
  for update;

  if not found then
    raise exception 'I playoff non sono stati configurati.';
  end if;

  if v_playoff.status = 'active'
    or v_playoff.status = 'completed' then
    return v_playoff.id;
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

  if v_fixture_count = 0
    or v_fixture_count <> v_official_fixture_count then
    raise exception
      'La stagione regolare deve avere tutti i risultati ufficiali.';
  end if;

  select count(*)::integer
  into v_team_count
  from public.fantasy_teams team
  where team.league_id = p_league_id;

  if v_team_count < v_playoff.participant_count then
    raise exception
      'Servono almeno % squadre per avviare i playoff.',
      v_playoff.participant_count;
  end if;

  select count(*)::integer
  into v_matchday_count
  from (
    select matchday.id
    from public.matchdays matchday
    where matchday.number >= p_start_matchday_number
      and matchday.locks_at > now()
      and (
        v_league.calendar_season is null
        or matchday.season = v_league.calendar_season
      )
    order by matchday.number
    limit v_playoff.round_count
  ) available;

  if v_matchday_count < v_playoff.round_count then
    raise exception
      'Servono % giornate future per completare i playoff.',
      v_playoff.round_count;
  end if;

  insert into public.league_playoff_entries (
    playoff_id,
    fantasy_team_id,
    seed,
    regular_season_position
  )
  select
    v_playoff.id,
    standing.fantasy_team_id,
    standing.position::smallint,
    standing.position::smallint
  from public.get_league_standings_v2(p_league_id) standing
  where standing.position <= v_playoff.participant_count
  order by standing.position;

  if (
    select count(*)
    from public.league_playoff_entries entry
    where entry.playoff_id = v_playoff.id
  ) <> v_playoff.participant_count then
    raise exception
      'La classifica non contiene tutte le qualificate ai playoff.';
  end if;

  insert into public.league_playoff_rounds (
    playoff_id,
    round_number,
    name,
    matchday_id
  )
  select
    v_playoff.id,
    scheduled.position,
    public.league_playoff_round_label(
      scheduled.position,
      v_playoff.round_count
    ),
    scheduled.matchday_id
  from (
    select
      available.id as matchday_id,
      row_number() over (
        order by available.number
      )::smallint as position
    from (
      select matchday.id, matchday.number
      from public.matchdays matchday
      where matchday.number >= p_start_matchday_number
        and matchday.locks_at > now()
        and (
          v_league.calendar_season is null
          or matchday.season = v_league.calendar_season
        )
      order by matchday.number
      limit v_playoff.round_count
    ) available
  ) scheduled
  order by scheduled.position;

  for v_round in 1..v_playoff.round_count loop
    for v_position in 1..(
      v_playoff.participant_count / power(2, v_round)::integer
    ) loop
      insert into public.league_playoff_ties (
        round_id,
        bracket_position
      )
      select playoff_round.id, v_position
      from public.league_playoff_rounds playoff_round
      where playoff_round.playoff_id = v_playoff.id
        and playoff_round.round_number = v_round;
    end loop;
  end loop;

  for v_position in 1..(v_playoff.participant_count / 2) loop
    if v_playoff.participant_count = 4 then
      v_home_seed := case v_position when 1 then 1 else 2 end;
      v_away_seed := case v_position when 1 then 4 else 3 end;
    else
      v_home_seed := case v_position
        when 1 then 1
        when 2 then 4
        when 3 then 2
        else 3
      end;
      v_away_seed := case v_position
        when 1 then 8
        when 2 then 5
        when 3 then 7
        else 6
      end;
    end if;

    update public.league_playoff_ties tie
    set
      home_team_id = home_entry.fantasy_team_id,
      home_seed = home_entry.seed,
      away_team_id = away_entry.fantasy_team_id,
      away_seed = away_entry.seed
    from public.league_playoff_rounds playoff_round,
      public.league_playoff_entries home_entry,
      public.league_playoff_entries away_entry
    where tie.round_id = playoff_round.id
      and playoff_round.playoff_id = v_playoff.id
      and playoff_round.round_number = 1
      and tie.bracket_position = v_position
      and home_entry.playoff_id = v_playoff.id
      and home_entry.seed = v_home_seed
      and away_entry.playoff_id = v_playoff.id
      and away_entry.seed = v_away_seed;
  end loop;

  update public.league_playoffs
  set
    status = 'active',
    current_round = 1,
    started_at = now()
  where id = v_playoff.id;

  for v_member_user_id in
    select member.user_id
    from public.league_members member
    where member.league_id = p_league_id
  loop
    perform public.create_user_notification(
      v_member_user_id,
      p_league_id,
      'league',
      'Playoff Scudetto iniziati',
      format(
        'Le prime %s della stagione regolare entrano nel tabellone.',
        v_playoff.participant_count
      ),
      'leaguePlayoffs',
      jsonb_build_object(
        'playoffId', v_playoff.id,
        'participantCount', v_playoff.participant_count
      ),
      format('league-playoffs-started:%s', v_playoff.id)
    );
  end loop;

  return v_playoff.id;
end;
$$;

revoke all on function public.start_league_playoffs(uuid, smallint)
from public, anon, authenticated;

grant execute on function public.start_league_playoffs(uuid, smallint)
to authenticated;

create or replace function public.refresh_league_playoff_round_internal(
  p_playoff_id uuid,
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
      playoff_round.matchday_id,
      matchday.locks_at,
      league.scoring_rules
    from public.league_playoff_ties tie
    join public.league_playoff_rounds playoff_round
      on playoff_round.id = tie.round_id
    join public.matchdays matchday
      on matchday.id = playoff_round.matchday_id
    join public.league_playoffs playoff
      on playoff.id = playoff_round.playoff_id
    join public.leagues league on league.id = playoff.league_id
    where playoff.id = p_playoff_id
      and playoff_round.round_number = p_round_number
      and tie.home_team_id is not null
      and tie.away_team_id is not null
      and tie.finalized_at is null
    for update of tie
  loop
    if now() >= v_tie.locks_at then
      perform public.lock_or_carry_team_lineup(
        v_tie.home_team_id,
        v_tie.matchday_id
      );
      perform public.lock_or_carry_team_lineup(
        v_tie.away_team_id,
        v_tie.matchday_id
      );
    end if;

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

    update public.league_playoff_ties
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

revoke all on function public.refresh_league_playoff_round_internal(
  uuid,
  integer
) from public, anon, authenticated;

create or replace function public.recalculate_league_playoffs(
  p_league_id uuid
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_playoff public.league_playoffs%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Devi effettuare l''accesso.';
  end if;

  if not public.is_league_member(p_league_id)
    and not public.is_league_admin(p_league_id) then
    raise exception 'Non fai parte di questa lega.';
  end if;

  select playoff.*
  into v_playoff
  from public.league_playoffs playoff
  where playoff.league_id = p_league_id;

  if not found or v_playoff.status <> 'active' then
    return 0;
  end if;

  return public.refresh_league_playoff_round_internal(
    v_playoff.id,
    v_playoff.current_round
  );
end;
$$;

revoke all on function public.recalculate_league_playoffs(uuid)
from public, anon, authenticated;

grant execute on function public.recalculate_league_playoffs(uuid)
to authenticated;

create or replace function public.finalize_league_playoff_round(
  p_league_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_league public.leagues%rowtype;
  v_playoff public.league_playoffs%rowtype;
  v_round public.league_playoff_rounds%rowtype;
  v_matchday public.matchdays%rowtype;
  v_tie public.league_playoff_ties%rowtype;
  v_next_round_id uuid;
  v_next_position integer;
  v_winner_id uuid;
  v_loser_id uuid;
  v_winner_seed smallint;
  v_decided_by text;
  v_unready_count integer;
  v_final_tie public.league_playoff_ties%rowtype;
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
    raise exception 'Solo il Presidente può ufficializzare i playoff.';
  end if;

  select playoff.*
  into v_playoff
  from public.league_playoffs playoff
  where playoff.league_id = p_league_id
  for update;

  if not found or v_playoff.status = 'configured' then
    raise exception 'I playoff non sono ancora iniziati.';
  end if;

  if v_playoff.status = 'completed' then
    return public.get_league_playoff_state(p_league_id);
  end if;

  select playoff_round.*
  into v_round
  from public.league_playoff_rounds playoff_round
  where playoff_round.playoff_id = v_playoff.id
    and playoff_round.round_number = v_playoff.current_round
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

  perform public.refresh_league_playoff_round_internal(
    v_playoff.id,
    v_playoff.current_round
  );

  select count(*)::integer
  into v_unready_count
  from public.league_playoff_ties tie
  where tie.round_id = v_round.id
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
    from public.league_playoff_ties tie
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

    update public.league_playoff_ties
    set
      winner_team_id = v_winner_id,
      decided_by = v_decided_by,
      finalized_at = now(),
      finalized_by = auth.uid()
    where id = v_tie.id;

    update public.league_playoff_entries
    set eliminated_round = v_playoff.current_round
    where playoff_id = v_playoff.id
      and fantasy_team_id = v_loser_id;
  end loop;

  update public.league_playoff_rounds
  set
    status = 'official',
    finalized_at = now(),
    finalized_by = auth.uid()
  where id = v_round.id;

  if v_playoff.current_round = v_playoff.round_count then
    select tie.*
    into v_final_tie
    from public.league_playoff_ties tie
    where tie.round_id = v_round.id
    order by tie.bracket_position
    limit 1;

    v_winner_id := v_final_tie.winner_team_id;
    v_loser_id := case
      when v_final_tie.home_team_id = v_winner_id
        then v_final_tie.away_team_id
      else v_final_tie.home_team_id
    end;

    update public.league_playoffs
    set
      status = 'completed',
      champion_team_id = v_winner_id,
      runner_up_team_id = v_loser_id,
      completed_at = now()
    where id = v_playoff.id;

    update public.league_playoff_entries
    set final_position = case
      when fantasy_team_id = v_winner_id then 1
      when fantasy_team_id = v_loser_id then 2
      else final_position
    end
    where playoff_id = v_playoff.id
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
        'LEGHEVO ha il suo Campione',
        format(
          '%s vince i Playoff Scudetto. Ora la stagione può essere chiusa.',
          v_champion_name
        ),
        'leaguePlayoffs',
        jsonb_build_object(
          'playoffId', v_playoff.id,
          'championTeamId', v_winner_id
        ),
        format('league-playoffs-completed:%s', v_playoff.id)
      );
    end loop;
  else
    select playoff_round.id
    into v_next_round_id
    from public.league_playoff_rounds playoff_round
    where playoff_round.playoff_id = v_playoff.id
      and playoff_round.round_number = v_playoff.current_round + 1;

    for v_tie in
      select tie.*
      from public.league_playoff_ties tie
      where tie.round_id = v_round.id
      order by tie.bracket_position
    loop
      v_next_position := ceil(v_tie.bracket_position / 2.0)::integer;

      select entry.seed
      into v_winner_seed
      from public.league_playoff_entries entry
      where entry.playoff_id = v_playoff.id
        and entry.fantasy_team_id = v_tie.winner_team_id;

      if mod(v_tie.bracket_position, 2) = 1 then
        update public.league_playoff_ties
        set
          home_team_id = v_tie.winner_team_id,
          home_seed = v_winner_seed
        where round_id = v_next_round_id
          and bracket_position = v_next_position;
      else
        update public.league_playoff_ties
        set
          away_team_id = v_tie.winner_team_id,
          away_seed = v_winner_seed
        where round_id = v_next_round_id
          and bracket_position = v_next_position;
      end if;
    end loop;

    update public.league_playoffs
    set current_round = current_round + 1
    where id = v_playoff.id;

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
        'Il tabellone Playoff è aggiornato.',
        'leaguePlayoffs',
        jsonb_build_object(
          'playoffId', v_playoff.id,
          'roundNumber', v_playoff.current_round + 1
        ),
        format(
          'league-playoffs-round:%s:%s',
          v_playoff.id,
          v_playoff.current_round
        )
      );
    end loop;
  end if;

  return public.get_league_playoff_state(p_league_id);
end;
$$;

revoke all on function public.finalize_league_playoff_round(uuid)
from public, anon, authenticated;

grant execute on function public.finalize_league_playoff_round(uuid)
to authenticated;

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

  if not public.team_competes_on_matchday(
    p_fantasy_team_id,
    p_matchday_id
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

  select
    exists (
      select 1
      from public.fantasy_fixtures fixture
      where fixture.league_id = p_league_id
        and v_team.id in (
          fixture.home_team_id,
          fixture.away_team_id
        )
    )
    or exists (
      select 1
      from public.league_playoff_ties tie
      join public.league_playoff_rounds playoff_round
        on playoff_round.id = tie.round_id
      join public.league_playoffs playoff
        on playoff.id = playoff_round.playoff_id
      where playoff.league_id = p_league_id
        and v_team.id in (
          tie.home_team_id,
          tie.away_team_id
        )
    )
  into v_has_calendar;

  with candidates as (
    select
      fixture.id as fixture_id,
      fixture.matchday_id,
      matchday.number,
      matchday.starts_at,
      matchday.locks_at,
      fixture.home_team_id = v_team.id as home,
      opponent.name as opponent_name,
      1 as priority
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
      and v_team.id in (
        fixture.home_team_id,
        fixture.away_team_id
      )
      and matchday.locks_at > now()

    union all

    select
      tie.id as fixture_id,
      playoff_round.matchday_id,
      matchday.number,
      matchday.starts_at,
      matchday.locks_at,
      tie.home_team_id = v_team.id as home,
      opponent.name as opponent_name,
      2 as priority
    from public.league_playoff_ties tie
    join public.league_playoff_rounds playoff_round
      on playoff_round.id = tie.round_id
    join public.matchdays matchday
      on matchday.id = playoff_round.matchday_id
    join public.league_playoffs playoff
      on playoff.id = playoff_round.playoff_id
      and playoff.league_id = p_league_id
      and playoff.status = 'active'
    join public.fantasy_teams opponent
      on opponent.id = case
        when tie.home_team_id = v_team.id
          then tie.away_team_id
        else tie.home_team_id
      end
    where v_team.id in (
        tie.home_team_id,
        tie.away_team_id
      )
      and matchday.locks_at > now()
  )
  select candidate.*
  into v_fixture
  from candidates candidate
  order by
    candidate.locks_at,
    candidate.priority,
    candidate.number
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
      select coalesce(
        array_agg(value::uuid order by ordinality),
        array[]::uuid[]
      )
      into v_starter_ids
      from jsonb_array_elements_text(
        v_preview -> 'starterIds'
      ) with ordinality as item(value, ordinality);

      select coalesce(
        array_agg(value::uuid order by ordinality),
        array[]::uuid[]
      )
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

  if not public.team_competes_on_matchday(
    v_team.id,
    v_matchday.id
  ) then
    raise exception
      'Questa giornata non appartiene al calendario della squadra.';
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

    v_expected_defenders := split_part(
      trim(p_formation),
      '-',
      1
    )::integer;
    v_expected_midfielders := split_part(
      trim(p_formation),
      '-',
      2
    )::integer;
    v_expected_attackers := split_part(
      trim(p_formation),
      '-',
      3
    )::integer;

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

revoke all on function public.save_team_lineup(
  uuid,
  uuid,
  text,
  uuid[],
  uuid[]
) from public, anon, authenticated;

grant execute on function public.save_team_lineup(
  uuid,
  uuid,
  text,
  uuid[],
  uuid[]
) to authenticated;

create or replace function public.get_league_season_state_v3(
  p_league_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_state jsonb;
  v_playoff_status text;
  v_champion_source text := 'regular_season';
  v_playoff_ready boolean := true;
begin
  v_state := public.get_league_season_state(p_league_id);

  select
    playoff.status,
    case
      when playoff.status = 'completed' then 'playoffs'
      else 'regular_season'
    end
  into
    v_playoff_status,
    v_champion_source
  from public.league_playoffs playoff
  where playoff.league_id = p_league_id;

  if found then
    v_playoff_ready := v_playoff_status = 'completed';
  end if;

  select coalesce(
    summary.champion_source,
    v_champion_source
  )
  into v_champion_source
  from public.league_season_summaries summary
  where summary.league_id = p_league_id;

  return v_state || jsonb_build_object(
    'canComplete',
      coalesce((v_state ->> 'canComplete')::boolean, false)
      and v_playoff_ready,
    'playoffStatus', v_playoff_status,
    'playoffRequired', v_playoff_status is not null,
    'championSource', v_champion_source
  );
end;
$$;

revoke all on function public.get_league_season_state_v3(uuid)
from public, anon, authenticated;

grant execute on function public.get_league_season_state_v3(uuid)
to authenticated;

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
      || public.get_league_season_state_v3(p_league_id)
$$;

revoke all on function public.get_league_management_state_v2(uuid)
from public, anon, authenticated;

grant execute on function public.get_league_management_state_v2(uuid)
to authenticated;

create or replace function public.get_league_management_state_v3(
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
      || public.get_league_season_state_v3(p_league_id)
$$;

revoke all on function public.get_league_management_state_v3(uuid)
from public, anon, authenticated;

grant execute on function public.get_league_management_state_v3(uuid)
to authenticated;

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
  v_playoff public.league_playoffs%rowtype;
  v_fixture_count integer := 0;
  v_official_fixture_count integer := 0;
  v_team_count integer := 0;
  v_final_standings jsonb := '[]'::jsonb;
  v_champion_team_id uuid;
  v_champion_team_name text;
  v_champion_manager_name text;
  v_tiebreaker text := 'goal_difference';
  v_champion_source text := 'regular_season';
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

  select playoff.*
  into v_playoff
  from public.league_playoffs playoff
  where playoff.league_id = p_league_id;

  if found and v_playoff.status <> 'completed' then
    raise exception
      'Prima di chiudere la stagione devi completare i Playoff Scudetto.';
  end if;

  select count(*)::integer
  into v_team_count
  from public.fantasy_teams team
  where team.league_id = p_league_id;

  if v_playoff.id is not null then
    v_champion_team_id := v_playoff.champion_team_id;
    v_champion_source := 'playoffs';
  end if;

  with regular_standings as (
    select
      standing.position as regular_position,
      standing.fantasy_team_id,
      standing.team_name,
      profile.display_name as manager_name,
      standing.played,
      standing.won,
      standing.drawn,
      standing.lost,
      standing.goals_for,
      standing.goals_against,
      standing.goal_difference,
      standing.points_for,
      standing.league_points,
      case
        when v_playoff.id is null then standing.position
        when standing.fantasy_team_id = v_playoff.champion_team_id then 0
        when standing.fantasy_team_id = v_playoff.runner_up_team_id then 1
        else standing.position + 2
      end as final_order
    from public.get_league_standings_v2(p_league_id) standing
    join public.fantasy_teams team
      on team.id = standing.fantasy_team_id
    join public.profiles profile
      on profile.id = team.manager_id
  ),
  final_ranked as (
    select
      row_number() over (
        order by regular.final_order, regular.regular_position
      )::integer as final_position,
      regular.*
    from regular_standings regular
  )
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'position', ranked.final_position,
        'regularSeasonPosition', ranked.regular_position,
        'teamId', ranked.fantasy_team_id,
        'teamName', ranked.team_name,
        'managerName', ranked.manager_name,
        'played', ranked.played,
        'won', ranked.won,
        'drawn', ranked.drawn,
        'lost', ranked.lost,
        'goalsFor', ranked.goals_for,
        'goalsAgainst', ranked.goals_against,
        'goalDifference', ranked.goal_difference,
        'pointsFor', ranked.points_for,
        'leaguePoints', ranked.league_points
      )
      order by ranked.final_position
    ),
    '[]'::jsonb
  )
  into v_final_standings
  from final_ranked ranked;

  if jsonb_array_length(v_final_standings) <> v_team_count
    or v_team_count = 0 then
    raise exception
      'La classifica finale non contiene tutte le squadre.';
  end if;

  if v_champion_team_id is null then
    v_champion_team_id :=
      (v_final_standings -> 0 ->> 'teamId')::uuid;
  end if;

  select
    team.name,
    coalesce(profile.display_name, 'Manager')
  into
    v_champion_team_name,
    v_champion_manager_name
  from public.fantasy_teams team
  left join public.profiles profile on profile.id = team.manager_id
  where team.id = v_champion_team_id;

  if v_champion_team_name is null then
    raise exception 'Il campione non appartiene alla lega.';
  end if;

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
    champion_source,
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
    v_champion_source,
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
        'champion_source', v_champion_source,
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

revoke all on function public.complete_league_season(uuid)
from public, anon, authenticated;

grant execute on function public.complete_league_season(uuid)
to authenticated;

create or replace function public.block_season_close_with_open_playoffs()
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
      from public.league_playoffs playoff
      where playoff.league_id = new.id
        and playoff.status <> 'completed'
    ) then
    raise exception
      'Prima di chiudere la stagione devi completare i Playoff Scudetto.';
  end if;

  return new;
end;
$$;

revoke all on function public.block_season_close_with_open_playoffs()
from public, anon, authenticated;

drop trigger if exists leagues_block_open_playoffs_on_completion
on public.leagues;

create trigger leagues_block_open_playoffs_on_completion
before update of status on public.leagues
for each row
execute function public.block_season_close_with_open_playoffs();

create or replace function public.copy_playoff_format_on_renewal()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.league_playoffs (
    league_id,
    status,
    participant_count,
    round_count,
    current_round,
    configured_by,
    configured_at
  )
  select
    new.renewed_league_id,
    'configured',
    source_playoff.participant_count,
    source_playoff.round_count,
    0,
    coalesce(new.renewed_by, renewed_league.owner_id),
    now()
  from public.league_playoffs source_playoff
  join public.leagues renewed_league
    on renewed_league.id = new.renewed_league_id
  where source_playoff.league_id = new.source_league_id
  on conflict (league_id) do nothing;

  return new;
end;
$$;

revoke all on function public.copy_playoff_format_on_renewal()
from public, anon, authenticated;

drop trigger if exists copy_playoff_format_on_renewal
on public.league_season_rollovers;

create trigger copy_playoff_format_on_renewal
after insert on public.league_season_rollovers
for each row
execute function public.copy_playoff_format_on_renewal();

do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'league_playoffs'
  ) then
    alter publication supabase_realtime
      add table public.league_playoffs;
  end if;

  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'league_playoff_rounds'
  ) then
    alter publication supabase_realtime
      add table public.league_playoff_rounds;
  end if;

  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'league_playoff_ties'
  ) then
    alter publication supabase_realtime
      add table public.league_playoff_ties;
  end if;
end;
$$;

select
  to_regclass('public.league_playoffs') is not null
    as league_playoffs_ready,
  to_regclass('public.league_playoff_entries') is not null
    as league_playoff_entries_ready,
  to_regclass('public.league_playoff_rounds') is not null
    as league_playoff_rounds_ready,
  to_regclass('public.league_playoff_ties') is not null
    as league_playoff_ties_ready,
  to_regprocedure(
    'public.get_league_playoff_state(uuid)'
  ) is not null as playoff_state_ready,
  to_regprocedure(
    'public.configure_league_playoffs(uuid,smallint)'
  ) is not null as playoff_configuration_ready,
  to_regprocedure(
    'public.start_league_playoffs(uuid,smallint)'
  ) is not null as playoff_start_ready,
  to_regprocedure(
    'public.finalize_league_playoff_round(uuid)'
  ) is not null as playoff_finalization_ready,
  to_regprocedure(
    'public.get_league_season_state_v3(uuid)'
  ) is not null
  and to_regprocedure(
    'public.get_league_management_state_v3(uuid)'
  ) is not null
  and exists (
    select 1
    from information_schema.triggers
    where event_object_schema = 'public'
      and event_object_table = 'league_season_rollovers'
      and trigger_name = 'copy_playoff_format_on_renewal'
  ) as playoff_season_state_ready,
  has_function_privilege(
    'authenticated',
    'public.get_league_playoff_state(uuid)',
    'EXECUTE'
  ) as playoff_read_access_ready,
  not has_function_privilege(
    'anon',
    'public.configure_league_playoffs(uuid,smallint)',
    'EXECUTE'
  ) as anonymous_playoff_configuration_blocked,
  exists (
    select 1
    from information_schema.triggers
    where event_object_schema = 'public'
      and event_object_table = 'leagues'
      and trigger_name =
        'leagues_block_open_playoffs_on_completion'
  ) as playoff_season_guard_ready;
