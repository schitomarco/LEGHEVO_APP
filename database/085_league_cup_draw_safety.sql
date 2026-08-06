-- LEGHEVO v0.60.1 · Coppa di Lega: sorteggio atomico, deterministico e idempotente
-- Migrazione: database/085_league_cup_draw_safety.sql
-- Non crea automaticamente una Coppa e non modifica tabelloni esistenti.
-- Ripara in modo idempotente soltanto la fondazione dati necessaria al modulo.

begin;

create extension if not exists pgcrypto;

-- Helper SHA-256 indipendente dallo schema in cui Supabase ha installato pgcrypto.
-- Usa esplicitamente la variante bytea di digest per evitare risoluzioni ambigue.
create or replace function public.leghevo_sha256_hex_v1(
  p_payload text
)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_extension_schema text;
  v_hash text;
begin
  select namespace.nspname
  into v_extension_schema
  from pg_catalog.pg_extension extension_record
  join pg_catalog.pg_namespace namespace
    on namespace.oid = extension_record.extnamespace
  where extension_record.extname = 'pgcrypto';

  if v_extension_schema is null then
    raise exception 'Estensione pgcrypto non disponibile.';
  end if;

  execute pg_catalog.format(
    'select pg_catalog.encode(%I.digest(pg_catalog.convert_to($1, ''UTF8''), ''sha256''), ''hex'')',
    v_extension_schema
  )
  into v_hash
  using coalesce(p_payload, '');

  return v_hash;
end;
$function$;

revoke all on function public.leghevo_sha256_hex_v1(text)
from public, anon, authenticated;

do $block$
begin
  if char_length(public.leghevo_sha256_hex_v1('LEGHEVO')) <> 64 then
    raise exception 'Helper SHA-256 LEGHEVO non operativo.';
  end if;
end;
$block$;

alter table public.user_notifications
  drop constraint if exists user_notifications_action_screen_check;

alter table public.user_notifications
  add constraint user_notifications_action_screen_check
  check (
    action_screen is null
    or action_screen in (
      'home', 'league', 'live', 'auction', 'calendar',
      'leagueCup', 'leaguePlayoffs', 'leagueSuperCup',
      'leagueOperations', 'postponements', 'lineup', 'roster',
      'standings', 'market', 'support', 'leagueRulebook'
    )
  );

create or replace function public.leghevo_stable_request_uuid(
  p_value text
)
returns uuid
language sql
immutable
security definer
set search_path = ''
as $$
  select (
    substr(md5(coalesce(p_value, '')), 1, 8)
    || '-'
    || substr(md5(coalesce(p_value, '')), 9, 4)
    || '-4'
    || substr(md5(coalesce(p_value, '')), 14, 3)
    || '-a'
    || substr(md5(coalesce(p_value, '')), 18, 3)
    || '-'
    || substr(md5(coalesce(p_value, '')), 21, 12)
  )::uuid;
$$;

revoke all on function public.leghevo_stable_request_uuid(text)
from public, anon, authenticated;

create table if not exists public.league_cups (
  id uuid primary key default gen_random_uuid(),
  league_id uuid not null unique
    references public.leagues(id) on delete cascade,
  name text not null default 'Coppa di Lega',
  status text not null default 'active',
  draw_seed uuid not null,
  team_count smallint not null,
  bracket_size smallint not null,
  round_count smallint not null,
  current_round smallint not null default 1,
  champion_team_id uuid references public.fantasy_teams(id),
  runner_up_team_id uuid references public.fantasy_teams(id),
  created_by uuid not null references public.profiles(id),
  started_at timestamptz not null default now(),
  completed_at timestamptz,
  updated_at timestamptz not null default now()
);

create table if not exists public.league_cup_entries (
  cup_id uuid not null references public.league_cups(id) on delete cascade,
  fantasy_team_id uuid not null references public.fantasy_teams(id) on delete cascade,
  seed smallint not null,
  eliminated_round smallint,
  final_position smallint,
  primary key (cup_id, fantasy_team_id)
);

create table if not exists public.league_cup_rounds (
  id uuid primary key default gen_random_uuid(),
  cup_id uuid not null references public.league_cups(id) on delete cascade,
  round_number smallint not null,
  name text not null,
  matchday_id uuid not null references public.matchdays(id),
  status text not null default 'scheduled',
  finalized_at timestamptz,
  finalized_by uuid references public.profiles(id)
);

create table if not exists public.league_cup_ties (
  id uuid primary key default gen_random_uuid(),
  round_id uuid not null references public.league_cup_rounds(id) on delete cascade,
  bracket_position smallint not null,
  home_team_id uuid references public.fantasy_teams(id),
  away_team_id uuid references public.fantasy_teams(id),
  home_seed smallint,
  away_seed smallint,
  home_points numeric(7,2),
  away_points numeric(7,2),
  home_goals smallint,
  away_goals smallint,
  home_ready boolean not null default false,
  away_ready boolean not null default false,
  home_counted_players smallint not null default 0,
  away_counted_players smallint not null default 0,
  winner_team_id uuid references public.fantasy_teams(id),
  decided_by text,
  finalized_at timestamptz,
  finalized_by uuid references public.profiles(id)
);

create unique index if not exists league_cups_league_id_uidx
  on public.league_cups (league_id);
create unique index if not exists league_cup_entries_seed_uidx
  on public.league_cup_entries (cup_id, seed);
create unique index if not exists league_cup_rounds_number_uidx
  on public.league_cup_rounds (cup_id, round_number);
create unique index if not exists league_cup_rounds_matchday_uidx
  on public.league_cup_rounds (cup_id, matchday_id);
create unique index if not exists league_cup_ties_position_uidx
  on public.league_cup_ties (round_id, bracket_position);

create table if not exists public.league_cup_draw_runs (
  id uuid primary key default gen_random_uuid(),
  league_id uuid not null references public.leagues(id) on delete cascade,
  cup_id uuid not null references public.league_cups(id) on delete cascade,
  request_id uuid not null,
  requested_by uuid not null references public.profiles(id),
  start_matchday_number smallint not null,
  team_count smallint not null,
  bracket_size smallint not null,
  round_count smallint not null,
  draw_seed uuid not null,
  participants_hash text not null,
  schedule_hash text not null,
  result_hash text not null,
  created_at timestamptz not null default now(),
  constraint league_cup_draw_runs_participants_hash_check
    check (char_length(participants_hash) = 64),
  constraint league_cup_draw_runs_schedule_hash_check
    check (char_length(schedule_hash) = 64),
  constraint league_cup_draw_runs_result_hash_check
    check (char_length(result_hash) = 64)
);

create unique index if not exists league_cup_draw_runs_request_uidx
  on public.league_cup_draw_runs (league_id, request_id);
create unique index if not exists league_cup_draw_runs_cup_uidx
  on public.league_cup_draw_runs (cup_id);
create index if not exists league_cup_draw_runs_league_created_idx
  on public.league_cup_draw_runs (league_id, created_at desc);

alter table public.league_cups enable row level security;
alter table public.league_cup_entries enable row level security;
alter table public.league_cup_rounds enable row level security;
alter table public.league_cup_ties enable row level security;
alter table public.league_cup_draw_runs enable row level security;

drop policy if exists league_cups_read_members on public.league_cups;
create policy league_cups_read_members
on public.league_cups for select to authenticated
using (public.is_league_member(league_id) or public.is_league_admin(league_id));

drop policy if exists league_cup_entries_read_members on public.league_cup_entries;
create policy league_cup_entries_read_members
on public.league_cup_entries for select to authenticated
using (
  exists (
    select 1 from public.league_cups cup
    where cup.id = cup_id
      and (public.is_league_member(cup.league_id)
        or public.is_league_admin(cup.league_id))
  )
);

drop policy if exists league_cup_rounds_read_members on public.league_cup_rounds;
create policy league_cup_rounds_read_members
on public.league_cup_rounds for select to authenticated
using (
  exists (
    select 1 from public.league_cups cup
    where cup.id = cup_id
      and (public.is_league_member(cup.league_id)
        or public.is_league_admin(cup.league_id))
  )
);

drop policy if exists league_cup_ties_read_members on public.league_cup_ties;
create policy league_cup_ties_read_members
on public.league_cup_ties for select to authenticated
using (
  exists (
    select 1
    from public.league_cup_rounds cup_round
    join public.league_cups cup on cup.id = cup_round.cup_id
    where cup_round.id = round_id
      and (public.is_league_member(cup.league_id)
        or public.is_league_admin(cup.league_id))
  )
);

drop policy if exists league_cup_draw_runs_read_members
on public.league_cup_draw_runs;
create policy league_cup_draw_runs_read_members
on public.league_cup_draw_runs for select to authenticated
using (public.is_league_member(league_id) or public.is_league_admin(league_id));

revoke all on table public.league_cups,
  public.league_cup_entries,
  public.league_cup_rounds,
  public.league_cup_ties,
  public.league_cup_draw_runs
from public, anon, authenticated;

grant select on table public.league_cups,
  public.league_cup_entries,
  public.league_cup_rounds,
  public.league_cup_ties,
  public.league_cup_draw_runs
to authenticated;

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

create or replace function public.prevent_league_cup_draw_run_mutation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  raise exception
    'Sorteggio Coppa certificato: modifica o cancellazione diretta non consentita.';
end;
$$;

revoke all on function public.prevent_league_cup_draw_run_mutation()
from public, anon, authenticated;

drop trigger if exists league_cup_draw_runs_immutable
on public.league_cup_draw_runs;
create trigger league_cup_draw_runs_immutable
before update or delete on public.league_cup_draw_runs
for each row execute function public.prevent_league_cup_draw_run_mutation();

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


create or replace function public.get_league_cup_state_v2(
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
  v_run public.league_cup_draw_runs%rowtype;
begin
  v_state := public.get_league_cup_state(p_league_id);

  select run.*
  into v_run
  from public.league_cup_draw_runs run
  where run.league_id = p_league_id
  order by run.created_at desc, run.id desc
  limit 1;

  return v_state || jsonb_build_object(
    'drawPolicy', 'guarded_v1',
    'drawCertified', v_run.id is not null,
    'drawRunId', v_run.id,
    'drawRequestId', v_run.request_id,
    'drawRevision', case when v_run.id is null then 0 else 1 end,
    'drawParticipantsHash', v_run.participants_hash,
    'drawScheduleHash', v_run.schedule_hash,
    'drawResultHash', v_run.result_hash
  );
end;
$$;

revoke all on function public.get_league_cup_state_v2(uuid)
from public, anon, authenticated;
grant execute on function public.get_league_cup_state_v2(uuid)
to authenticated;

create or replace function public.create_league_cup_guarded_v1(
  p_league_id uuid,
  p_start_matchday_number smallint,
  p_request_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_league public.leagues%rowtype;
  v_existing_run public.league_cup_draw_runs%rowtype;
  v_existing_cup_id uuid;
  v_cup_id uuid;
  v_draw_seed uuid;
  v_team_count integer;
  v_bracket_size integer := 2;
  v_round_count integer := 1;
  v_played_ties integer;
  v_round integer;
  v_position integer;
  v_member_user_id uuid;
  v_matchday_ids uuid[];
  v_matchday_numbers smallint[];
  v_participants_hash text;
  v_schedule_hash text;
  v_result_hash text;
  v_state jsonb;
begin
  if auth.uid() is null then
    raise exception 'Devi effettuare l''accesso.';
  end if;

  if p_request_id is null then
    raise exception 'Identificativo richiesta mancante.';
  end if;

  if p_start_matchday_number is null or p_start_matchday_number < 1 then
    raise exception 'Giornata iniziale della Coppa non valida.';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended('leghevo:league-cup-draw:' || p_league_id::text, 0)
  );

  select run.*
  into v_existing_run
  from public.league_cup_draw_runs run
  where run.league_id = p_league_id
    and run.request_id = p_request_id;

  if found then
    return public.get_league_cup_state_v2(p_league_id)
      || jsonb_build_object(
        'idempotentReplay', true,
        'drawRunId', v_existing_run.id
      );
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

  select cup.id
  into v_existing_cup_id
  from public.league_cups cup
  where cup.league_id = p_league_id;

  if found then
    return public.get_league_cup_state_v2(p_league_id)
      || jsonb_build_object(
        'idempotentReplay', true,
        'alreadyExists', true
      );
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

  select
    array_agg(candidate.id order by candidate.number),
    array_agg(candidate.number::smallint order by candidate.number)
  into v_matchday_ids, v_matchday_numbers
  from (
    select distinct matchday.id, matchday.number
    from public.fantasy_fixtures fixture
    join public.matchdays matchday on matchday.id = fixture.matchday_id
    where fixture.league_id = p_league_id
      and matchday.number >= p_start_matchday_number
      and matchday.locks_at > now()
    order by matchday.number
    limit v_round_count
  ) candidate;

  if coalesce(array_length(v_matchday_ids, 1), 0) <> v_round_count then
    raise exception
      'Servono % giornate future consecutive per completare la coppa.',
      v_round_count;
  end if;

  if v_matchday_numbers[1] <> p_start_matchday_number
    or v_matchday_numbers[v_round_count] - v_matchday_numbers[1]
      <> v_round_count - 1 then
    raise exception
      'Le giornate della Coppa devono essere future e consecutive.';
  end if;

  select public.leghevo_sha256_hex_v1(
coalesce(
        string_agg(
          team.id::text || ':' || coalesce(team.manager_id::text, '-') || ':' || trim(team.name),
          '|' order by team.id
        ),
        ''
      )
    )
  into v_participants_hash
  from public.fantasy_teams team
  where team.league_id = p_league_id;

  select public.leghevo_sha256_hex_v1(
string_agg(
        ids.id::text || ':' || numbers.number::text,
        '|' order by ids.ordinality
      )
    )
  into v_schedule_hash
  from unnest(v_matchday_ids) with ordinality as ids(id, ordinality)
  join unnest(v_matchday_numbers) with ordinality as numbers(number, ordinality)
    using (ordinality);

  v_draw_seed := public.leghevo_stable_request_uuid(
    'league-cup-draw:' || p_league_id::text || ':' || p_request_id::text
  );

  insert into public.league_cups (
    league_id, name, status, draw_seed, team_count,
    bracket_size, round_count, current_round, created_by
  ) values (
    p_league_id, 'Coppa di Lega', 'active', v_draw_seed,
    v_team_count, v_bracket_size, v_round_count, 1, auth.uid()
  ) returning id into v_cup_id;

  insert into public.league_cup_entries (
    cup_id, fantasy_team_id, seed
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
    cup_id, round_number, name, matchday_id
  )
  select
    v_cup_id,
    scheduled.ordinality::smallint,
    public.league_cup_round_label(
      scheduled.ordinality::integer,
      v_round_count
    ),
    scheduled.matchday_id
  from unnest(v_matchday_ids) with ordinality as
    scheduled(matchday_id, ordinality);

  for v_round in 1..v_round_count loop
    for v_position in 1..(
      v_bracket_size / power(2, v_round)::integer
    ) loop
      insert into public.league_cup_ties (
        round_id, bracket_position
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
        else v_played_ties * 2
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

  select public.leghevo_sha256_hex_v1(
coalesce(
        (
          select string_agg(
            entry.fantasy_team_id::text || ':' || entry.seed::text,
            '|' order by entry.seed
          )
          from public.league_cup_entries entry
          where entry.cup_id = v_cup_id
        ),
        ''
      ) || '#' || coalesce(
        (
          select string_agg(
            cup_round.round_number::text || ':' || cup_round.matchday_id::text,
            '|' order by cup_round.round_number
          )
          from public.league_cup_rounds cup_round
          where cup_round.cup_id = v_cup_id
        ),
        ''
      ) || '#' || coalesce(
        (
          select string_agg(
            cup_round.round_number::text || ':'
              || tie.bracket_position::text || ':'
              || coalesce(tie.home_team_id::text, '-') || ':'
              || coalesce(tie.away_team_id::text, '-') || ':'
              || coalesce(tie.winner_team_id::text, '-'),
            '|' order by cup_round.round_number, tie.bracket_position
          )
          from public.league_cup_ties tie
          join public.league_cup_rounds cup_round
            on cup_round.id = tie.round_id
          where cup_round.cup_id = v_cup_id
        ),
        ''
      )
    ) into v_result_hash;

  insert into public.league_cup_draw_runs (
    league_id, cup_id, request_id, requested_by,
    start_matchday_number, team_count, bracket_size, round_count,
    draw_seed, participants_hash, schedule_hash, result_hash
  ) values (
    p_league_id, v_cup_id, p_request_id, auth.uid(),
    p_start_matchday_number, v_team_count, v_bracket_size, v_round_count,
    v_draw_seed, v_participants_hash, v_schedule_hash, v_result_hash
  );

  if to_regprocedure(
    'public.create_user_notification(uuid,uuid,text,text,text,text,jsonb,text)'
  ) is not null then
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
          '%s squadre, %s turni: il tabellone protetto è ufficiale.',
          v_team_count,
          v_round_count
        ),
        'leagueCup',
        jsonb_build_object(
          'cupId', v_cup_id,
          'roundCount', v_round_count,
          'drawPolicy', 'guarded_v1'
        ),
        format('league-cup-created:%s', v_cup_id)
      );
    end loop;
  end if;

  v_state := public.get_league_cup_state_v2(p_league_id);
  return v_state || jsonb_build_object(
    'idempotentReplay', false,
    'alreadyExists', false
  );
end;
$$;

revoke all on function public.create_league_cup_guarded_v1(
  uuid, smallint, uuid
) from public, anon, authenticated;
grant execute on function public.create_league_cup_guarded_v1(
  uuid, smallint, uuid
) to authenticated;

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
  v_state jsonb;
begin
  v_state := public.create_league_cup_guarded_v1(
    p_league_id,
    p_start_matchday_number,
    public.leghevo_stable_request_uuid(
      'legacy-league-cup-draw:'
        || coalesce(auth.uid()::text, 'anonymous')
        || ':' || p_league_id::text
        || ':' || p_start_matchday_number::text
    )
  );
  return nullif(v_state ->> 'cupId', '')::uuid;
end;
$$;

revoke all on function public.create_league_cup(uuid, smallint)
from public, anon, authenticated;
grant execute on function public.create_league_cup(uuid, smallint)
to authenticated;

-- Certifica anche eventuali Coppe create con il percorso storico,
-- senza alterare il tabellone o i risultati già presenti.
insert into public.league_cup_draw_runs (
  league_id, cup_id, request_id, requested_by,
  start_matchday_number, team_count, bracket_size, round_count,
  draw_seed, participants_hash, schedule_hash, result_hash, created_at
)
select
  cup.league_id,
  cup.id,
  public.leghevo_stable_request_uuid('league-cup-backfill:' || cup.id::text),
  cup.created_by,
  coalesce(
    (
      select min(matchday.number)::smallint
      from public.league_cup_rounds cup_round
      join public.matchdays matchday on matchday.id = cup_round.matchday_id
      where cup_round.cup_id = cup.id
    ),
    1::smallint
  ),
  cup.team_count,
  cup.bracket_size,
  cup.round_count,
  cup.draw_seed,
  public.leghevo_sha256_hex_v1(
coalesce((
    select string_agg(
      entry.fantasy_team_id::text || ':' || entry.seed::text,
      '|' order by entry.seed
    )
    from public.league_cup_entries entry
    where entry.cup_id = cup.id
  ), '')
    ),
  public.leghevo_sha256_hex_v1(
coalesce((
    select string_agg(
      cup_round.round_number::text || ':' || cup_round.matchday_id::text,
      '|' order by cup_round.round_number
    )
    from public.league_cup_rounds cup_round
    where cup_round.cup_id = cup.id
  ), '')
    ),
  public.leghevo_sha256_hex_v1(
coalesce((
      select string_agg(
        entry.fantasy_team_id::text || ':' || entry.seed::text,
        '|' order by entry.seed
      )
      from public.league_cup_entries entry
      where entry.cup_id = cup.id
    ), '') || '#' || coalesce((
      select string_agg(
        cup_round.round_number::text || ':' || cup_round.matchday_id::text,
        '|' order by cup_round.round_number
      )
      from public.league_cup_rounds cup_round
      where cup_round.cup_id = cup.id
    ), '') || '#' || coalesce((
      select string_agg(
        cup_round.round_number::text || ':'
          || tie.bracket_position::text || ':'
          || coalesce(tie.home_team_id::text, '-') || ':'
          || coalesce(tie.away_team_id::text, '-') || ':'
          || coalesce(tie.winner_team_id::text, '-'),
        '|' order by cup_round.round_number, tie.bracket_position
      )
      from public.league_cup_ties tie
      join public.league_cup_rounds cup_round on cup_round.id = tie.round_id
      where cup_round.cup_id = cup.id
    ), '')
    ),
  cup.started_at
from public.league_cups cup
where not exists (
  select 1
  from public.league_cup_draw_runs run
  where run.cup_id = cup.id
);

create or replace function public.get_league_cup_draw_integrity_v1(
  p_league_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_cup_count integer := 0;
  v_run_count integer := 0;
  v_missing_run_count integer := 0;
  v_duplicate_request_count integer := 0;
  v_duplicate_cup_count integer := 0;
  v_hash_issue_count integer := 0;
  v_entry_count_issue_count integer := 0;
  v_round_count_issue_count integer := 0;
  v_tie_count_issue_count integer := 0;
  v_healthy boolean := false;
begin
  if auth.uid() is null
    or (not public.is_league_member(p_league_id)
      and not public.is_league_admin(p_league_id)) then
    raise exception 'Non fai parte di questa lega.';
  end if;

  select count(*)::integer into v_cup_count
  from public.league_cups cup where cup.league_id = p_league_id;

  select count(*)::integer into v_run_count
  from public.league_cup_draw_runs run where run.league_id = p_league_id;

  select count(*)::integer into v_missing_run_count
  from public.league_cups cup
  where cup.league_id = p_league_id
    and not exists (
      select 1 from public.league_cup_draw_runs run
      where run.cup_id = cup.id
    );

  select count(*)::integer into v_duplicate_request_count
  from (
    select run.request_id
    from public.league_cup_draw_runs run
    where run.league_id = p_league_id
    group by run.request_id having count(*) > 1
  ) duplicate_request;

  select count(*)::integer into v_duplicate_cup_count
  from (
    select run.cup_id
    from public.league_cup_draw_runs run
    where run.league_id = p_league_id
    group by run.cup_id having count(*) > 1
  ) duplicate_cup;

  select count(*)::integer into v_hash_issue_count
  from public.league_cup_draw_runs run
  where run.league_id = p_league_id
    and (
      char_length(run.participants_hash) <> 64
      or char_length(run.schedule_hash) <> 64
      or char_length(run.result_hash) <> 64
    );

  select count(*)::integer into v_entry_count_issue_count
  from public.league_cups cup
  where cup.league_id = p_league_id
    and (
      select count(*) from public.league_cup_entries entry
      where entry.cup_id = cup.id
    ) <> cup.team_count;

  select count(*)::integer into v_round_count_issue_count
  from public.league_cups cup
  where cup.league_id = p_league_id
    and (
      select count(*) from public.league_cup_rounds cup_round
      where cup_round.cup_id = cup.id
    ) <> cup.round_count;

  select count(*)::integer into v_tie_count_issue_count
  from public.league_cups cup
  where cup.league_id = p_league_id
    and exists (
      select 1
      from public.league_cup_rounds cup_round
      where cup_round.cup_id = cup.id
        and (
          select count(*)
          from public.league_cup_ties tie
          where tie.round_id = cup_round.id
        ) <> cup.bracket_size / power(2, cup_round.round_number)::integer
    );

  v_healthy :=
    v_missing_run_count = 0
    and v_duplicate_request_count = 0
    and v_duplicate_cup_count = 0
    and v_hash_issue_count = 0
    and v_entry_count_issue_count = 0
    and v_round_count_issue_count = 0
    and v_tie_count_issue_count = 0;

  return jsonb_build_object(
    'policy', 'guarded_v1',
    'healthy', v_healthy,
    'cupCount', v_cup_count,
    'drawRunCount', v_run_count,
    'missingRunCount', v_missing_run_count,
    'duplicateRequestCount', v_duplicate_request_count,
    'duplicateCupCount', v_duplicate_cup_count,
    'hashIssueCount', v_hash_issue_count,
    'entryCountIssueCount', v_entry_count_issue_count,
    'roundCountIssueCount', v_round_count_issue_count,
    'tieCountIssueCount', v_tie_count_issue_count
  );
end;
$$;

revoke all on function public.get_league_cup_draw_integrity_v1(uuid)
from public, anon, authenticated;
grant execute on function public.get_league_cup_draw_integrity_v1(uuid)
to authenticated;

-- Realtime idempotente per il registro dei sorteggi.
do $$
begin
  if exists (
    select 1 from pg_publication where pubname = 'supabase_realtime'
  ) and not exists (
    select 1
    from pg_publication_tables publication_table
    where publication_table.pubname = 'supabase_realtime'
      and publication_table.schemaname = 'public'
      and publication_table.tablename = 'league_cup_draw_runs'
  ) then
    alter publication supabase_realtime
      add table public.league_cup_draw_runs;
  end if;
end;
$$;

commit;

-- Diagnostica finale: devono risultare esattamente 20 valori true.
select
  to_regclass('public.league_cups') is not null
    as cup_table_ready,
  to_regclass('public.league_cup_entries') is not null
    as cup_entries_table_ready,
  to_regclass('public.league_cup_rounds') is not null
    as cup_rounds_table_ready,
  to_regclass('public.league_cup_ties') is not null
    as cup_ties_table_ready,
  to_regclass('public.league_cup_draw_runs') is not null
    as cup_draw_runs_table_ready,
  exists (
    select 1 from pg_indexes
    where schemaname = 'public'
      and indexname = 'league_cup_draw_runs_request_uidx'
  ) as request_uniqueness_ready,
  exists (
    select 1 from pg_indexes
    where schemaname = 'public'
      and indexname = 'league_cup_draw_runs_cup_uidx'
  ) as cup_uniqueness_ready,
  coalesce((
    select relrowsecurity
    from pg_class
    where oid = 'public.league_cup_draw_runs'::regclass
  ), false) as draw_runs_rls_ready,
  exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'league_cup_draw_runs'
      and policyname = 'league_cup_draw_runs_read_members'
  ) as draw_runs_policy_ready,
  to_regprocedure('public.prevent_league_cup_draw_run_mutation()') is not null
    as immutable_function_ready,
  exists (
    select 1
    from pg_trigger trigger_row
    where trigger_row.tgrelid = 'public.league_cup_draw_runs'::regclass
      and trigger_row.tgname = 'league_cup_draw_runs_immutable'
      and not trigger_row.tgisinternal
  ) as immutable_trigger_ready,
  to_regprocedure('public.get_league_cup_state(uuid)') is not null
    as cup_state_v1_ready,
  to_regprocedure('public.get_league_cup_state_v2(uuid)') is not null
    as cup_state_v2_ready,
  to_regprocedure(
    'public.create_league_cup_guarded_v1(uuid,smallint,uuid)'
  ) is not null as guarded_draw_ready,
  to_regprocedure('public.create_league_cup(uuid,smallint)') is not null
    as legacy_draw_routed,
  to_regprocedure('public.get_league_cup_draw_integrity_v1(uuid)') is not null
    as cup_draw_integrity_ready,
  not exists (
    select 1 from public.league_cups cup
    where not exists (
      select 1 from public.league_cup_draw_runs run
      where run.cup_id = cup.id
    )
    or (
      select count(*) from public.league_cup_entries entry
      where entry.cup_id = cup.id
    ) <> cup.team_count
    or (
      select count(*) from public.league_cup_rounds cup_round
      where cup_round.cup_id = cup.id
    ) <> cup.round_count
    or exists (
      select 1
      from public.league_cup_rounds cup_round
      where cup_round.cup_id = cup.id
        and (
          select count(*) from public.league_cup_ties tie
          where tie.round_id = cup_round.id
        ) <> cup.bracket_size / power(2, cup_round.round_number)::integer
    )
  ) as existing_cups_certified,
  not exists (
    select 1 from public.league_cup_draw_runs run
    where char_length(run.participants_hash) <> 64
      or char_length(run.schedule_hash) <> 64
      or char_length(run.result_hash) <> 64
  ) as draw_hashes_ready,
  coalesce(has_table_privilege(
    'authenticated', to_regclass('public.league_cup_draw_runs'), 'SELECT'
  ), false)
  and not coalesce(has_table_privilege(
    'authenticated', to_regclass('public.league_cup_draw_runs'), 'INSERT'
  ), false)
  and not coalesce(has_table_privilege(
    'authenticated', to_regclass('public.league_cup_draw_runs'), 'UPDATE'
  ), false)
    as draw_permissions_ready,
  coalesce(has_function_privilege(
    'authenticated',
    'public.create_league_cup_guarded_v1(uuid,smallint,uuid)',
    'EXECUTE'
  ), false)
  and not coalesce(has_function_privilege(
    'anon',
    'public.create_league_cup_guarded_v1(uuid,smallint,uuid)',
    'EXECUTE'
  ), false)
  and exists (
    select 1
    from pg_publication_tables publication_table
    where publication_table.pubname = 'supabase_realtime'
      and publication_table.schemaname = 'public'
      and publication_table.tablename = 'league_cup_draw_runs'
  ) as guarded_draw_access_and_realtime_ready;
