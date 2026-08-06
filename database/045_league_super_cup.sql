-- LEGHEVO · Supercoppa di Lega tra stagioni collegate
-- Eseguire nel SQL Editor di Supabase dopo 044.
-- Lo script aggiunge struttura e funzioni, ma non crea né disputa alcuna
-- Supercoppa e non modifica risultati, rose o classifiche esistenti.

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
      'leagueSuperCup',
      'lineup',
      'roster',
      'standings',
      'market'
    )
  );

create table if not exists public.league_super_cups (
  id uuid primary key default gen_random_uuid(),
  league_id uuid not null unique
    references public.leagues(id) on delete cascade,
  source_league_id uuid not null unique
    references public.leagues(id) on delete restrict,
  matchday_id uuid not null references public.matchdays(id),
  status text not null default 'active'
    check (status in ('active', 'completed')),
  league_champion_team_id uuid not null
    references public.fantasy_teams(id),
  challenger_team_id uuid not null
    references public.fantasy_teams(id),
  challenger_qualification text not null
    check (challenger_qualification in ('cup_champion', 'cup_runner_up')),
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
  runner_up_team_id uuid references public.fantasy_teams(id),
  decided_by text check (
    decided_by is null
    or decided_by in ('goals', 'fantasy_points', 'league_champion')
  ),
  created_by uuid not null references public.profiles(id),
  finalized_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  completed_at timestamptz,
  updated_at timestamptz not null default now(),
  check (league_id <> source_league_id),
  check (league_champion_team_id <> challenger_team_id),
  check (winner_team_id is null or winner_team_id <> runner_up_team_id)
);

create index if not exists league_super_cups_matchday_idx
  on public.league_super_cups (matchday_id, league_id);

drop trigger if exists league_super_cups_set_updated_at
on public.league_super_cups;

create trigger league_super_cups_set_updated_at
before update on public.league_super_cups
for each row execute function public.set_updated_at();

alter table public.league_super_cups enable row level security;

drop policy if exists league_super_cups_read_members
on public.league_super_cups;

create policy league_super_cups_read_members
on public.league_super_cups for select to authenticated
using (
  public.is_league_member(league_id)
  or public.is_league_admin(league_id)
);

revoke all on public.league_super_cups
from public, anon, authenticated;

grant select on public.league_super_cups to authenticated;

create or replace function public.resolve_league_super_cup_qualifiers(
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
  v_source_summary public.league_season_summaries%rowtype;
  v_source_cup public.league_cups%rowtype;
  v_home_manager_id uuid;
  v_away_manager_id uuid;
  v_home_team public.fantasy_teams%rowtype;
  v_away_team public.fantasy_teams%rowtype;
  v_challenger_qualification text := 'cup_champion';
  v_reason text;
begin
  select league.*
  into v_league
  from public.leagues league
  where league.id = p_league_id;

  if not found then
    return jsonb_build_object(
      'eligible', false,
      'reason', 'Lega non trovata.'
    );
  end if;

  if v_league.previous_league_id is null then
    return jsonb_build_object(
      'eligible', false,
      'reason', 'La prima stagione non ha ancora una Supercoppa da disputare.'
    );
  end if;

  select summary.*
  into v_source_summary
  from public.league_season_summaries summary
  where summary.league_id = v_league.previous_league_id;

  if not found then
    return jsonb_build_object(
      'eligible', false,
      'reason', 'La classifica finale della stagione precedente non è disponibile.'
    );
  end if;

  select cup.*
  into v_source_cup
  from public.league_cups cup
  where cup.league_id = v_league.previous_league_id
    and cup.status = 'completed';

  if not found then
    return jsonb_build_object(
      'eligible', false,
      'reason', 'La stagione precedente non ha una Coppa di Lega conclusa.'
    );
  end if;

  select team.manager_id
  into v_home_manager_id
  from public.fantasy_teams team
  where team.id = v_source_summary.champion_team_id;

  select team.manager_id
  into v_away_manager_id
  from public.fantasy_teams team
  where team.id = v_source_cup.champion_team_id;

  if v_home_manager_id is null or v_away_manager_id is null then
    return jsonb_build_object(
      'eligible', false,
      'reason', 'I vincitori della stagione precedente non sono più identificabili.'
    );
  end if;

  if v_home_manager_id = v_away_manager_id then
    select team.manager_id
    into v_away_manager_id
    from public.fantasy_teams team
    where team.id = v_source_cup.runner_up_team_id;

    v_challenger_qualification := 'cup_runner_up';
  end if;

  if v_away_manager_id is null or v_home_manager_id = v_away_manager_id then
    return jsonb_build_object(
      'eligible', false,
      'reason', 'Non è disponibile un avversario distinto per la Supercoppa.'
    );
  end if;

  select team.*
  into v_home_team
  from public.fantasy_teams team
  where team.league_id = p_league_id
    and team.manager_id = v_home_manager_id;

  select team.*
  into v_away_team
  from public.fantasy_teams team
  where team.league_id = p_league_id
    and team.manager_id = v_away_manager_id;

  if v_home_team.id is null or v_away_team.id is null then
    v_reason :=
      'I finalisti della Supercoppa devono partecipare alla nuova stagione.';

    return jsonb_build_object(
      'eligible', false,
      'reason', v_reason
    );
  end if;

  return jsonb_build_object(
    'eligible', true,
    'reason', null,
    'sourceLeagueId', v_league.previous_league_id,
    'sourceSeason', v_source_summary.season,
    'challengerQualification', v_challenger_qualification,
    'leagueChampion', jsonb_build_object(
      'teamId', v_home_team.id,
      'teamName', v_home_team.name,
      'managerId', v_home_team.manager_id,
      'managerName', coalesce(
        (
          select profile.display_name
          from public.profiles profile
          where profile.id = v_home_team.manager_id
        ),
        'Manager'
      ),
      'qualification', 'league_champion'
    ),
    'challenger', jsonb_build_object(
      'teamId', v_away_team.id,
      'teamName', v_away_team.name,
      'managerId', v_away_team.manager_id,
      'managerName', coalesce(
        (
          select profile.display_name
          from public.profiles profile
          where profile.id = v_away_team.manager_id
        ),
        'Manager'
      ),
      'qualification', v_challenger_qualification
    )
  );
end;
$$;

revoke all on function public.resolve_league_super_cup_qualifiers(uuid)
from public, anon, authenticated;

create or replace function public.refresh_league_super_cup_internal(
  p_super_cup_id uuid
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_super_cup public.league_super_cups%rowtype;
  v_scoring_rules jsonb;
  v_home_breakdown jsonb;
  v_away_breakdown jsonb;
  v_goal_resolution jsonb;
begin
  select super_cup.*
  into v_super_cup
  from public.league_super_cups super_cup
  where super_cup.id = p_super_cup_id
  for update;

  if not found or v_super_cup.status = 'completed' then
    return 0;
  end if;

  select league.scoring_rules
  into v_scoring_rules
  from public.leagues league
  where league.id = v_super_cup.league_id;

  v_home_breakdown := public.get_team_matchday_breakdown(
    v_super_cup.league_champion_team_id,
    v_super_cup.matchday_id
  );
  v_away_breakdown := public.get_team_matchday_breakdown(
    v_super_cup.challenger_team_id,
    v_super_cup.matchday_id
  );

  v_goal_resolution := public.resolve_fantasy_fixture_goals(
    nullif(v_home_breakdown ->> 'totalPoints', '')::numeric,
    nullif(v_away_breakdown ->> 'totalPoints', '')::numeric,
    v_scoring_rules
  );

  update public.league_super_cups
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
  where id = p_super_cup_id;

  return 1;
end;
$$;

revoke all on function public.refresh_league_super_cup_internal(uuid)
from public, anon, authenticated;

create or replace function public.get_league_super_cup_state(
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
  v_super_cup public.league_super_cups%rowtype;
  v_matchday public.matchdays%rowtype;
  v_qualifiers jsonb;
  v_start_matchdays jsonb := '[]'::jsonb;
  v_is_owner boolean := false;
  v_creation_reason text;
  v_can_finalize boolean := false;
  v_winner jsonb;
  v_runner_up jsonb;
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
  v_qualifiers := public.resolve_league_super_cup_qualifiers(p_league_id);

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', candidate.id,
        'number', candidate.number,
        'startsAt', candidate.starts_at,
        'locksAt', candidate.locks_at,
        'endsAt', candidate.ends_at
      )
      order by candidate.number
    ),
    '[]'::jsonb
  )
  into v_start_matchdays
  from (
    select distinct
      matchday.id,
      matchday.number,
      matchday.starts_at,
      matchday.locks_at,
      matchday.ends_at
    from public.fantasy_fixtures fixture
    join public.matchdays matchday on matchday.id = fixture.matchday_id
    where fixture.league_id = p_league_id
      and matchday.locks_at > now()
    order by matchday.number
    limit 12
  ) candidate;

  select super_cup.*
  into v_super_cup
  from public.league_super_cups super_cup
  where super_cup.league_id = p_league_id;

  if not found then
    v_creation_reason := case
      when coalesce((v_qualifiers ->> 'eligible')::boolean, false) is false
        then v_qualifiers ->> 'reason'
      when not v_is_owner
        then 'Solo il Presidente può programmare la Supercoppa.'
      when v_league.status <> 'active'
        then 'La Supercoppa si programma durante una stagione attiva.'
      when jsonb_array_length(v_start_matchdays) = 0
        then 'Non ci sono giornate future disponibili.'
      else null
    end;

    return jsonb_build_object(
      'exists', false,
      'leagueId', p_league_id,
      'status', 'not_created',
      'isOwner', v_is_owner,
      'eligible',
        coalesce((v_qualifiers ->> 'eligible')::boolean, false),
      'canCreate', v_creation_reason is null,
      'creationReason', v_creation_reason,
      'sourceLeagueId', v_qualifiers ->> 'sourceLeagueId',
      'sourceSeason', v_qualifiers ->> 'sourceSeason',
      'leagueChampion', v_qualifiers -> 'leagueChampion',
      'challenger', v_qualifiers -> 'challenger',
      'challengerQualification',
        v_qualifiers ->> 'challengerQualification',
      'startMatchdays', v_start_matchdays,
      'canFinalize', false,
      'winner', null,
      'runnerUp', null
    );
  end if;

  select matchday.*
  into v_matchday
  from public.matchdays matchday
  where matchday.id = v_super_cup.matchday_id;

  select jsonb_build_object(
    'teamId', team.id,
    'teamName', team.name,
    'managerId', team.manager_id,
    'managerName', coalesce(profile.display_name, 'Manager')
  )
  into v_winner
  from public.fantasy_teams team
  left join public.profiles profile on profile.id = team.manager_id
  where team.id = v_super_cup.winner_team_id;

  select jsonb_build_object(
    'teamId', team.id,
    'teamName', team.name,
    'managerId', team.manager_id,
    'managerName', coalesce(profile.display_name, 'Manager')
  )
  into v_runner_up
  from public.fantasy_teams team
  left join public.profiles profile on profile.id = team.manager_id
  where team.id = v_super_cup.runner_up_team_id;

  v_can_finalize :=
    v_super_cup.status = 'active'
    and v_is_owner
    and now() >= coalesce(
      v_matchday.ends_at,
      v_matchday.starts_at + interval '4 days'
    )
    and v_super_cup.home_ready
    and v_super_cup.away_ready
    and v_super_cup.home_points is not null
    and v_super_cup.away_points is not null;

  return jsonb_build_object(
    'exists', true,
    'leagueId', p_league_id,
    'superCupId', v_super_cup.id,
    'status', v_super_cup.status,
    'isOwner', v_is_owner,
    'eligible', true,
    'canCreate', false,
    'creationReason', null,
    'sourceLeagueId', v_super_cup.source_league_id,
    'sourceSeason', v_qualifiers ->> 'sourceSeason',
    'leagueChampion', v_qualifiers -> 'leagueChampion',
    'challenger', v_qualifiers -> 'challenger',
    'challengerQualification',
      v_super_cup.challenger_qualification,
    'matchday', jsonb_build_object(
      'id', v_matchday.id,
      'number', v_matchday.number,
      'startsAt', v_matchday.starts_at,
      'locksAt', v_matchday.locks_at,
      'endsAt', v_matchday.ends_at
    ),
    'homePoints', v_super_cup.home_points,
    'awayPoints', v_super_cup.away_points,
    'homeGoals', v_super_cup.home_goals,
    'awayGoals', v_super_cup.away_goals,
    'homeReady', v_super_cup.home_ready,
    'awayReady', v_super_cup.away_ready,
    'homeCountedPlayers', v_super_cup.home_counted_players,
    'awayCountedPlayers', v_super_cup.away_counted_players,
    'decidedBy', v_super_cup.decided_by,
    'createdAt', v_super_cup.created_at,
    'completedAt', v_super_cup.completed_at,
    'canFinalize', v_can_finalize,
    'winner', v_winner,
    'runnerUp', v_runner_up,
    'startMatchdays', v_start_matchdays
  );
end;
$$;

revoke all on function public.get_league_super_cup_state(uuid)
from public, anon, authenticated;

grant execute on function public.get_league_super_cup_state(uuid)
to authenticated;

create or replace function public.create_league_super_cup(
  p_league_id uuid,
  p_matchday_number smallint
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_league public.leagues%rowtype;
  v_existing_id uuid;
  v_qualifiers jsonb;
  v_matchday_id uuid;
  v_super_cup_id uuid;
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
    raise exception 'Solo il Presidente può programmare la Supercoppa.';
  end if;

  select super_cup.id
  into v_existing_id
  from public.league_super_cups super_cup
  where super_cup.league_id = p_league_id;

  if found then
    return v_existing_id;
  end if;

  if v_league.status <> 'active' then
    raise exception
      'La Supercoppa si programma durante una stagione attiva.';
  end if;

  v_qualifiers := public.resolve_league_super_cup_qualifiers(p_league_id);

  if coalesce((v_qualifiers ->> 'eligible')::boolean, false) is false then
    raise exception '%', coalesce(
      v_qualifiers ->> 'reason',
      'La Supercoppa non è disponibile.'
    );
  end if;

  select matchday.id
  into v_matchday_id
  from public.matchdays matchday
  where matchday.number = p_matchday_number
    and matchday.locks_at > now()
    and exists (
      select 1
      from public.fantasy_fixtures fixture
      where fixture.league_id = p_league_id
        and fixture.matchday_id = matchday.id
    )
  order by matchday.starts_at
  limit 1;

  if v_matchday_id is null then
    raise exception 'La giornata scelta non è disponibile.';
  end if;

  insert into public.league_super_cups (
    league_id,
    source_league_id,
    matchday_id,
    league_champion_team_id,
    challenger_team_id,
    challenger_qualification,
    created_by
  )
  values (
    p_league_id,
    (v_qualifiers ->> 'sourceLeagueId')::uuid,
    v_matchday_id,
    (v_qualifiers -> 'leagueChampion' ->> 'teamId')::uuid,
    (v_qualifiers -> 'challenger' ->> 'teamId')::uuid,
    v_qualifiers ->> 'challengerQualification',
    auth.uid()
  )
  returning id into v_super_cup_id;

  for v_member_user_id in
    select member.user_id
    from public.league_members member
    where member.league_id = p_league_id
  loop
    perform public.create_user_notification(
      v_member_user_id,
      p_league_id,
      'league',
      'Supercoppa programmata',
      format(
        '%s contro %s alla giornata %s.',
        v_qualifiers -> 'leagueChampion' ->> 'teamName',
        v_qualifiers -> 'challenger' ->> 'teamName',
        p_matchday_number
      ),
      'leagueSuperCup',
      jsonb_build_object(
        'superCupId', v_super_cup_id,
        'matchdayNumber', p_matchday_number
      ),
      format('league-super-cup-created:%s', v_super_cup_id)
    );
  end loop;

  return v_super_cup_id;
end;
$$;

revoke all on function public.create_league_super_cup(uuid, smallint)
from public, anon, authenticated;

grant execute on function public.create_league_super_cup(uuid, smallint)
to authenticated;

create or replace function public.recalculate_league_super_cup(
  p_league_id uuid
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_super_cup public.league_super_cups%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Devi effettuare l''accesso.';
  end if;

  if not public.is_league_member(p_league_id)
    and not public.is_league_admin(p_league_id) then
    raise exception 'Non fai parte di questa lega.';
  end if;

  select super_cup.*
  into v_super_cup
  from public.league_super_cups super_cup
  where super_cup.league_id = p_league_id;

  if not found or v_super_cup.status = 'completed' then
    return 0;
  end if;

  return public.refresh_league_super_cup_internal(v_super_cup.id);
end;
$$;

revoke all on function public.recalculate_league_super_cup(uuid)
from public, anon, authenticated;

grant execute on function public.recalculate_league_super_cup(uuid)
to authenticated;

create or replace function public.finalize_league_super_cup(
  p_league_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_league public.leagues%rowtype;
  v_super_cup public.league_super_cups%rowtype;
  v_matchday public.matchdays%rowtype;
  v_winner_id uuid;
  v_loser_id uuid;
  v_decided_by text;
  v_winner_name text;
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
    raise exception 'Solo il Presidente può ufficializzare la Supercoppa.';
  end if;

  select super_cup.*
  into v_super_cup
  from public.league_super_cups super_cup
  where super_cup.league_id = p_league_id
  for update;

  if not found then
    raise exception 'La Supercoppa non è stata programmata.';
  end if;

  if v_super_cup.status = 'completed' then
    return public.get_league_super_cup_state(p_league_id);
  end if;

  select matchday.*
  into v_matchday
  from public.matchdays matchday
  where matchday.id = v_super_cup.matchday_id;

  if now() < coalesce(
    v_matchday.ends_at,
    v_matchday.starts_at + interval '4 days'
  ) then
    raise exception 'La giornata reale della Supercoppa non è ancora terminata.';
  end if;

  perform public.refresh_league_super_cup_internal(v_super_cup.id);

  select super_cup.*
  into v_super_cup
  from public.league_super_cups super_cup
  where super_cup.league_id = p_league_id
  for update;

  if not v_super_cup.home_ready
    or not v_super_cup.away_ready
    or v_super_cup.home_points is null
    or v_super_cup.away_points is null
    or v_super_cup.home_goals is null
    or v_super_cup.away_goals is null then
    raise exception 'Mancano ancora voti definitivi per la Supercoppa.';
  end if;

  if v_super_cup.home_goals > v_super_cup.away_goals then
    v_winner_id := v_super_cup.league_champion_team_id;
    v_loser_id := v_super_cup.challenger_team_id;
    v_decided_by := 'goals';
  elsif v_super_cup.away_goals > v_super_cup.home_goals then
    v_winner_id := v_super_cup.challenger_team_id;
    v_loser_id := v_super_cup.league_champion_team_id;
    v_decided_by := 'goals';
  elsif v_super_cup.home_points > v_super_cup.away_points then
    v_winner_id := v_super_cup.league_champion_team_id;
    v_loser_id := v_super_cup.challenger_team_id;
    v_decided_by := 'fantasy_points';
  elsif v_super_cup.away_points > v_super_cup.home_points then
    v_winner_id := v_super_cup.challenger_team_id;
    v_loser_id := v_super_cup.league_champion_team_id;
    v_decided_by := 'fantasy_points';
  else
    v_winner_id := v_super_cup.league_champion_team_id;
    v_loser_id := v_super_cup.challenger_team_id;
    v_decided_by := 'league_champion';
  end if;

  update public.league_super_cups
  set
    status = 'completed',
    winner_team_id = v_winner_id,
    runner_up_team_id = v_loser_id,
    decided_by = v_decided_by,
    finalized_by = auth.uid(),
    completed_at = now()
  where id = v_super_cup.id;

  select team.name
  into v_winner_name
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
      'result',
      'Supercoppa assegnata',
      v_winner_name
        || ' ha vinto la Supercoppa di '
        || v_league.name
        || '.',
      'leagueSuperCup',
      jsonb_build_object(
        'superCupId', v_super_cup.id,
        'winnerTeamId', v_winner_id,
        'decidedBy', v_decided_by
      ),
      format('league-super-cup-completed:%s', v_super_cup.id)
    );
  end loop;

  return public.get_league_super_cup_state(p_league_id);
end;
$$;

revoke all on function public.finalize_league_super_cup(uuid)
from public, anon, authenticated;

grant execute on function public.finalize_league_super_cup(uuid)
to authenticated;

create or replace function public.get_league_super_cup_history(
  p_league_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_root_league_id uuid;
  v_latest_league_id uuid;
  v_league_name text;
  v_completed_count integer := 0;
  v_active_count integer := 0;
  v_seasons jsonb := '[]'::jsonb;
  v_title_leaders jsonb := '[]'::jsonb;
begin
  if auth.uid() is null then
    raise exception 'Devi effettuare l''accesso.';
  end if;

  if not public.is_league_member(p_league_id)
    and not public.is_league_admin(p_league_id) then
    raise exception 'Non fai parte di questa lega.';
  end if;

  select league.name
  into v_league_name
  from public.leagues league
  where league.id = p_league_id;

  if not found then
    raise exception 'Lega non trovata.';
  end if;

  with recursive ancestors as (
    select league.id, league.previous_league_id
    from public.leagues league
    where league.id = p_league_id

    union

    select previous.id, previous.previous_league_id
    from ancestors current_season
    join public.leagues previous
      on previous.id = current_season.previous_league_id
  )
  select ancestor.id
  into v_root_league_id
  from ancestors ancestor
  where ancestor.previous_league_id is null
  limit 1;

  with recursive season_chain as (
    select league.id, league.previous_league_id, 1 as sequence
    from public.leagues league
    where league.id = v_root_league_id

    union all

    select
      renewed.id,
      renewed.previous_league_id,
      current_season.sequence + 1
    from season_chain current_season
    join public.leagues renewed
      on renewed.previous_league_id = current_season.id
  )
  select chain.id
  into v_latest_league_id
  from season_chain chain
  order by chain.sequence desc
  limit 1;

  with recursive season_chain as (
    select league.id, league.previous_league_id, 1 as sequence
    from public.leagues league
    where league.id = v_root_league_id

    union all

    select
      renewed.id,
      renewed.previous_league_id,
      current_season.sequence + 1
    from season_chain current_season
    join public.leagues renewed
      on renewed.previous_league_id = current_season.id
  ),
  history_rows as (
    select
      chain.sequence,
      league.id as league_id,
      league.calendar_season as season,
      league.status as league_status,
      source_summary.season as source_season,
      super_cup.id as super_cup_id,
      super_cup.status as super_cup_status,
      super_cup.challenger_qualification,
      super_cup.home_points,
      super_cup.away_points,
      super_cup.home_goals,
      super_cup.away_goals,
      super_cup.decided_by,
      super_cup.created_at,
      super_cup.completed_at,
      matchday.number as matchday_number,
      home_team.id as home_team_id,
      home_team.name as home_team_name,
      home_team.manager_id as home_manager_id,
      coalesce(home_profile.display_name, 'Manager') as home_manager_name,
      away_team.id as away_team_id,
      away_team.name as away_team_name,
      away_team.manager_id as away_manager_id,
      coalesce(away_profile.display_name, 'Manager') as away_manager_name,
      winner.id as winner_team_id,
      winner.name as winner_team_name,
      winner.manager_id as winner_manager_id,
      coalesce(winner_profile.display_name, 'Manager') as winner_manager_name,
      runner_up.id as runner_up_team_id,
      runner_up.name as runner_up_team_name,
      runner_up.manager_id as runner_up_manager_id,
      coalesce(runner_up_profile.display_name, 'Manager')
        as runner_up_manager_name
    from season_chain chain
    join public.leagues league on league.id = chain.id
    left join public.league_super_cups super_cup
      on super_cup.league_id = league.id
    left join public.league_season_summaries source_summary
      on source_summary.league_id = super_cup.source_league_id
    left join public.matchdays matchday
      on matchday.id = super_cup.matchday_id
    left join public.fantasy_teams home_team
      on home_team.id = super_cup.league_champion_team_id
    left join public.profiles home_profile
      on home_profile.id = home_team.manager_id
    left join public.fantasy_teams away_team
      on away_team.id = super_cup.challenger_team_id
    left join public.profiles away_profile
      on away_profile.id = away_team.manager_id
    left join public.fantasy_teams winner
      on winner.id = super_cup.winner_team_id
    left join public.profiles winner_profile
      on winner_profile.id = winner.manager_id
    left join public.fantasy_teams runner_up
      on runner_up.id = super_cup.runner_up_team_id
    left join public.profiles runner_up_profile
      on runner_up_profile.id = runner_up.manager_id
  )
  select
    count(*) filter (
      where row.super_cup_status = 'completed'
    )::integer,
    count(*) filter (
      where row.super_cup_status = 'active'
    )::integer,
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'leagueId', row.league_id,
          'season', row.season,
          'leagueStatus', row.league_status,
          'superCupExists', row.super_cup_id is not null,
          'superCupId', row.super_cup_id,
          'superCupStatus',
            coalesce(row.super_cup_status, 'not_created'),
          'sourceSeason', row.source_season,
          'matchdayNumber', row.matchday_number,
          'challengerQualification', row.challenger_qualification,
          'leagueChampion',
            case
              when row.home_team_id is null then null
              else jsonb_build_object(
                'teamId', row.home_team_id,
                'teamName', row.home_team_name,
                'managerId', row.home_manager_id,
                'managerName', row.home_manager_name
              )
            end,
          'challenger',
            case
              when row.away_team_id is null then null
              else jsonb_build_object(
                'teamId', row.away_team_id,
                'teamName', row.away_team_name,
                'managerId', row.away_manager_id,
                'managerName', row.away_manager_name
              )
            end,
          'homePoints', row.home_points,
          'awayPoints', row.away_points,
          'homeGoals', row.home_goals,
          'awayGoals', row.away_goals,
          'decidedBy', row.decided_by,
          'createdAt', row.created_at,
          'completedAt', row.completed_at,
          'winner',
            case
              when row.winner_team_id is null then null
              else jsonb_build_object(
                'teamId', row.winner_team_id,
                'teamName', row.winner_team_name,
                'managerId', row.winner_manager_id,
                'managerName', row.winner_manager_name
              )
            end,
          'runnerUp',
            case
              when row.runner_up_team_id is null then null
              else jsonb_build_object(
                'teamId', row.runner_up_team_id,
                'teamName', row.runner_up_team_name,
                'managerId', row.runner_up_manager_id,
                'managerName', row.runner_up_manager_name
              )
            end,
          'isSelected', row.league_id = p_league_id,
          'isLatest', row.league_id = v_latest_league_id
        )
        order by row.sequence desc
      ),
      '[]'::jsonb
    )
  into v_completed_count, v_active_count, v_seasons
  from history_rows row;

  with recursive season_chain as (
    select league.id
    from public.leagues league
    where league.id = v_root_league_id

    union all

    select renewed.id
    from season_chain current_season
    join public.leagues renewed
      on renewed.previous_league_id = current_season.id
  ),
  winners as (
    select
      team.manager_id,
      coalesce(profile.display_name, 'Manager') as manager_name,
      team.name as team_name,
      league.calendar_season as season
    from season_chain chain
    join public.leagues league on league.id = chain.id
    join public.league_super_cups super_cup
      on super_cup.league_id = league.id
      and super_cup.status = 'completed'
    join public.fantasy_teams team
      on team.id = super_cup.winner_team_id
    left join public.profiles profile on profile.id = team.manager_id
  )
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'rank', leader.rank,
        'managerId', leader.manager_id,
        'managerName', leader.manager_name,
        'titles', leader.titles,
        'teamNames', leader.team_names,
        'seasons', leader.seasons
      )
      order by leader.rank, leader.manager_name
    ),
    '[]'::jsonb
  )
  into v_title_leaders
  from (
    select
      winner.manager_id,
      max(winner.manager_name) as manager_name,
      count(*)::integer as titles,
      array_agg(distinct winner.team_name order by winner.team_name)
        as team_names,
      array_agg(winner.season order by winner.season) as seasons,
      dense_rank() over (
        order by count(*) desc, max(winner.manager_name), winner.manager_id
      )::integer as rank
    from winners winner
    group by winner.manager_id
  ) leader;

  return jsonb_build_object(
    'leagueName', v_league_name,
    'selectedLeagueId', p_league_id,
    'latestLeagueId', v_latest_league_id,
    'completedSuperCups', v_completed_count,
    'activeSuperCups', v_active_count,
    'seasons', v_seasons,
    'titleLeaders', v_title_leaders
  );
end;
$$;

revoke all on function public.get_league_super_cup_history(uuid)
from public, anon, authenticated;

grant execute on function public.get_league_super_cup_history(uuid)
to authenticated;

create or replace function public.block_season_close_with_open_super_cup()
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
      from public.league_super_cups super_cup
      where super_cup.league_id = new.id
        and super_cup.status <> 'completed'
    ) then
    raise exception
      'Prima devi ufficializzare la Supercoppa di Lega.';
  end if;

  return new;
end;
$$;

revoke all on function public.block_season_close_with_open_super_cup()
from public, anon, authenticated;

drop trigger if exists leagues_block_open_super_cup_on_completion
on public.leagues;

create trigger leagues_block_open_super_cup_on_completion
before update of status on public.leagues
for each row execute function public.block_season_close_with_open_super_cup();

select
  to_regclass('public.league_super_cups') is not null
    as super_cup_table_ready,
  exists (
    select 1
    from pg_class relation
    join pg_namespace namespace on namespace.oid = relation.relnamespace
    where namespace.nspname = 'public'
      and relation.relname = 'league_super_cups'
      and relation.relrowsecurity
  ) as super_cup_rls_ready,
  to_regprocedure(
    'public.get_league_super_cup_state(uuid)'
  ) is not null as super_cup_state_ready,
  to_regprocedure(
    'public.create_league_super_cup(uuid,smallint)'
  ) is not null as super_cup_creation_ready,
  to_regprocedure(
    'public.recalculate_league_super_cup(uuid)'
  ) is not null as super_cup_recalculation_ready,
  to_regprocedure(
    'public.finalize_league_super_cup(uuid)'
  ) is not null as super_cup_finalization_ready,
  to_regprocedure(
    'public.get_league_super_cup_history(uuid)'
  ) is not null as super_cup_history_ready,
  has_function_privilege(
    'authenticated',
    'public.get_league_super_cup_state(uuid)',
    'EXECUTE'
  ) as super_cup_read_access_ready,
  not has_function_privilege(
    'anon',
    'public.create_league_super_cup(uuid,smallint)',
    'EXECUTE'
  ) as anonymous_super_cup_creation_blocked,
  exists (
    select 1
    from information_schema.triggers
    where event_object_schema = 'public'
      and event_object_table = 'leagues'
      and trigger_name =
        'leagues_block_open_super_cup_on_completion'
  ) as season_close_guard_ready,
  exists (
    select 1
    from information_schema.check_constraints constraint_info
    where constraint_info.constraint_schema = 'public'
      and constraint_info.constraint_name =
        'user_notifications_action_screen_check'
      and constraint_info.check_clause like '%leagueSuperCup%'
  ) as super_cup_notifications_ready,
  exists (
    select 1
    from information_schema.table_constraints constraint_info
    where constraint_info.table_schema = 'public'
      and constraint_info.table_name = 'league_super_cups'
      and constraint_info.constraint_type = 'UNIQUE'
  ) as one_super_cup_per_season_ready;
