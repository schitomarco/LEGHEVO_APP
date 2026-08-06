-- LEGHEVO v0.60.2 CORRETTA · Coppa di Lega: ufficializzazione protetta dei turni
-- Migrazione: database/086_league_cup_round_finalization_safety.sql
-- Eseguire dopo database/085_league_cup_draw_safety.sql.
-- Script idempotente: ripara il motore hash, non crea Coppe, non altera sorteggi e non cancella risultati.

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


-- Ripristino difensivo del sorteggio v0.60.1: la prima versione usava digest()
-- non qualificata dentro una funzione con search_path vuoto. La funzione viene
-- ricreata con il nuovo helper senza alterare Coppe o sorteggi esistenti.
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


create table if not exists public.league_cup_round_finalization_runs (
  id bigint generated by default as identity primary key,
  league_id uuid not null references public.leagues(id) on delete cascade,
  cup_id uuid not null references public.league_cups(id) on delete cascade,
  round_id uuid not null references public.league_cup_rounds(id) on delete cascade,
  matchday_id uuid not null references public.matchdays(id) on delete restrict,
  officialization_run_id bigint not null
    references public.matchday_officialization_runs(id) on delete restrict,
  request_id uuid not null,
  requested_by uuid references public.profiles(id) on delete set null,
  round_number smallint not null check (round_number between 1 and 5),
  input_hash text not null check (char_length(input_hash) = 64),
  result_hash text not null check (char_length(result_hash) = 64),
  tie_count smallint not null check (tie_count between 1 and 16),
  finalized_tie_count smallint not null
    check (finalized_tie_count between 1 and 16),
  next_round_id uuid references public.league_cup_rounds(id) on delete restrict,
  champion_team_id uuid references public.fantasy_teams(id) on delete restrict,
  cup_completed boolean not null default false,
  result_payload jsonb not null default '{}'::jsonb,
  finalized_at timestamptz not null default now(),
  constraint league_cup_round_finalization_count_check
    check (finalized_tie_count <= tie_count),
  constraint league_cup_round_finalization_completion_check
    check (
      (cup_completed and champion_team_id is not null and next_round_id is null)
      or (not cup_completed and champion_team_id is null)
    )
);

create unique index if not exists league_cup_round_finalization_request_uidx
  on public.league_cup_round_finalization_runs (league_id, request_id);
create unique index if not exists league_cup_round_finalization_round_uidx
  on public.league_cup_round_finalization_runs (round_id);
create index if not exists league_cup_round_finalization_lookup_idx
  on public.league_cup_round_finalization_runs
    (league_id, cup_id, round_number, finalized_at desc);
create index if not exists league_cup_round_finalization_officialization_idx
  on public.league_cup_round_finalization_runs (officialization_run_id);

alter table public.league_cup_round_finalization_runs enable row level security;

drop policy if exists league_cup_round_finalization_read_members
on public.league_cup_round_finalization_runs;
create policy league_cup_round_finalization_read_members
on public.league_cup_round_finalization_runs
for select to authenticated
using (
  public.is_league_member(league_id)
  or public.is_league_admin(league_id)
);

revoke all on table public.league_cup_round_finalization_runs
from public, anon, authenticated;
grant select on table public.league_cup_round_finalization_runs
to authenticated;

create or replace function public.prevent_league_cup_round_finalization_mutation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  raise exception
    'Turno di Coppa certificato: modifica o cancellazione diretta non consentita.';
end;
$$;

revoke all on function public.prevent_league_cup_round_finalization_mutation()
from public, anon, authenticated;

drop trigger if exists league_cup_round_finalization_runs_immutable
on public.league_cup_round_finalization_runs;
create trigger league_cup_round_finalization_runs_immutable
before update or delete on public.league_cup_round_finalization_runs
for each row
execute function public.prevent_league_cup_round_finalization_mutation();

-- Ripristino difensivo del calcolo del turno: usa il motore formazione e
-- sostituzioni certificato già installato nello Sviluppo 5.
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
      cup_round.matchday_id,
      league.scoring_rules
    from public.league_cup_ties tie
    join public.league_cup_rounds cup_round
      on cup_round.id = tie.round_id
    join public.league_cups cup
      on cup.id = cup_round.cup_id
    join public.leagues league
      on league.id = cup.league_id
    where cup.id = p_cup_id
      and cup_round.round_number = p_round_number
      and tie.home_team_id is not null
      and tie.away_team_id is not null
      and tie.winner_team_id is null
    order by tie.bracket_position
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
      home_points = nullif(v_home_breakdown ->> 'totalPoints', '')::numeric,
      away_points = nullif(v_away_breakdown ->> 'totalPoints', '')::numeric,
      home_goals = nullif(v_goal_resolution ->> 'homeGoals', '')::smallint,
      away_goals = nullif(v_goal_resolution ->> 'awayGoals', '')::smallint,
      home_ready = coalesce((v_home_breakdown ->> 'isReady')::boolean, false),
      away_ready = coalesce((v_away_breakdown ->> 'isReady')::boolean, false),
      home_counted_players = least(
        greatest(coalesce((v_home_breakdown ->> 'countedPlayers')::integer, 0), 0),
        11
      ),
      away_counted_players = least(
        greatest(coalesce((v_away_breakdown ->> 'countedPlayers')::integer, 0), 0),
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

create or replace function public.league_cup_round_input_hash_v1(
  p_cup_id uuid,
  p_round_number integer
)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  with selected_round as (
    select
      cup.id as cup_id,
      cup.league_id,
      cup_round.id as round_id,
      cup_round.round_number,
      cup_round.matchday_id,
      officialization.id as officialization_id,
      officialization.result_hash as officialization_hash
    from public.league_cups cup
    join public.league_cup_rounds cup_round
      on cup_round.cup_id = cup.id
      and cup_round.round_number = p_round_number
    left join public.matchday_officialization_runs officialization
      on officialization.league_id = cup.league_id
      and officialization.matchday_id = cup_round.matchday_id
      and officialization.superseded_at is null
    where cup.id = p_cup_id
  ), tie_snapshot as (
    select coalesce(
      string_agg(
        tie.bracket_position::text || ':'
        || coalesce(tie.home_team_id::text, '-') || ':'
        || coalesce(tie.away_team_id::text, '-') || ':'
        || coalesce(tie.home_seed::text, '-') || ':'
        || coalesce(tie.away_seed::text, '-') || ':'
        || coalesce(tie.home_points::text, '-') || ':'
        || coalesce(tie.away_points::text, '-') || ':'
        || coalesce(tie.home_goals::text, '-') || ':'
        || coalesce(tie.away_goals::text, '-') || ':'
        || tie.home_ready::text || ':'
        || tie.away_ready::text || ':'
        || tie.home_counted_players::text || ':'
        || tie.away_counted_players::text || ':'
        || coalesce(home_resolution.result_hash, '-') || ':'
        || coalesce(away_resolution.result_hash, '-'),
        '|' order by tie.bracket_position
      ),
      ''
    ) as payload
    from selected_round selected
    join public.league_cup_ties tie
      on tie.round_id = selected.round_id
    left join public.lineup_resolution_runs home_resolution
      on home_resolution.fantasy_team_id = tie.home_team_id
      and home_resolution.matchday_id = selected.matchday_id
      and home_resolution.superseded_at is null
    left join public.lineup_resolution_runs away_resolution
      on away_resolution.fantasy_team_id = tie.away_team_id
      and away_resolution.matchday_id = selected.matchday_id
      and away_resolution.superseded_at is null
  )
  select case
    when selected.officialization_id is null then null
    else public.leghevo_sha256_hex_v1(
selected.cup_id::text || '#'
        || selected.league_id::text || '#'
        || selected.round_id::text || '#'
        || selected.round_number::text || '#'
        || selected.matchday_id::text || '#'
        || selected.officialization_id::text || '#'
        || selected.officialization_hash || '#'
        || tie_snapshot.payload
    )
  end
  from selected_round selected
  cross join tie_snapshot;
$$;

revoke all on function public.league_cup_round_input_hash_v1(uuid, integer)
from public, anon, authenticated;

create or replace function public.league_cup_round_result_hash_v1(
  p_cup_id uuid,
  p_round_number integer
)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  with selected_round as (
    select
      cup.id as cup_id,
      cup.round_count,
      cup.champion_team_id,
      cup.runner_up_team_id,
      cup_round.id as round_id,
      cup_round.status as round_status,
      cup_round.finalized_at
    from public.league_cups cup
    join public.league_cup_rounds cup_round
      on cup_round.cup_id = cup.id
      and cup_round.round_number = p_round_number
    where cup.id = p_cup_id
  ), result_snapshot as (
    select coalesce(
      string_agg(
        tie.bracket_position::text || ':'
        || coalesce(tie.home_team_id::text, '-') || ':'
        || coalesce(tie.away_team_id::text, '-') || ':'
        || coalesce(tie.home_points::text, '-') || ':'
        || coalesce(tie.away_points::text, '-') || ':'
        || coalesce(tie.home_goals::text, '-') || ':'
        || coalesce(tie.away_goals::text, '-') || ':'
        || coalesce(tie.winner_team_id::text, '-') || ':'
        || coalesce(tie.decided_by, '-'),
        '|' order by tie.bracket_position
      ),
      ''
    ) as payload
    from selected_round selected
    join public.league_cup_ties tie
      on tie.round_id = selected.round_id
  ), next_round_snapshot as (
    select coalesce(
      string_agg(
        next_tie.bracket_position::text || ':'
        || coalesce(next_tie.home_team_id::text, '-') || ':'
        || coalesce(next_tie.away_team_id::text, '-'),
        '|' order by next_tie.bracket_position
      ),
      ''
    ) as payload
    from selected_round selected
    left join public.league_cup_rounds next_round
      on next_round.cup_id = selected.cup_id
      and next_round.round_number = p_round_number + 1
    left join public.league_cup_ties next_tie
      on next_tie.round_id = next_round.id
  )
  select public.leghevo_sha256_hex_v1(
selected.cup_id::text || '#'
      || selected.round_id::text || '#'
      || selected.round_count::text || '#'
      || selected.round_status || '#'
      || coalesce(selected.finalized_at::text, '-') || '#'
      || coalesce(
        case when p_round_number = selected.round_count
          then selected.champion_team_id::text end,
        '-'
      ) || '#'
      || coalesce(
        case when p_round_number = selected.round_count
          then selected.runner_up_team_id::text end,
        '-'
      ) || '#'
      || result_snapshot.payload || '#'
      || next_round_snapshot.payload
    )
  from selected_round selected
  cross join result_snapshot
  cross join next_round_snapshot;
$$;

revoke all on function public.league_cup_round_result_hash_v1(uuid, integer)
from public, anon, authenticated;

create or replace function public.get_league_cup_state_v3(
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
  v_cup_id uuid;
  v_official_round_count integer := 0;
  v_certified_round_count integer := 0;
  v_latest_run public.league_cup_round_finalization_runs%rowtype;
  v_rounds_certified boolean := true;
  v_current_officialization_ready boolean := false;
begin
  v_state := public.get_league_cup_state_v2(p_league_id);
  v_cup_id := nullif(v_state ->> 'cupId', '')::uuid;

  if v_cup_id is not null then
    select count(*)::integer
    into v_official_round_count
    from public.league_cup_rounds cup_round
    where cup_round.cup_id = v_cup_id
      and cup_round.status = 'official';

    select count(*)::integer
    into v_certified_round_count
    from public.league_cup_round_finalization_runs run
    where run.cup_id = v_cup_id;

    v_rounds_certified := v_certified_round_count = v_official_round_count;

    select run.*
    into v_latest_run
    from public.league_cup_round_finalization_runs run
    where run.cup_id = v_cup_id
    order by run.round_number desc, run.finalized_at desc
    limit 1;

    select exists (
      select 1
      from public.league_cup_rounds cup_round
      join public.league_cups cup on cup.id = cup_round.cup_id
      join public.matchday_officialization_runs officialization
        on officialization.league_id = cup.league_id
        and officialization.matchday_id = cup_round.matchday_id
        and officialization.superseded_at is null
      where cup.id = v_cup_id
        and cup_round.round_number = cup.current_round
    ) into v_current_officialization_ready;
  end if;

  return v_state || jsonb_build_object(
    'roundFinalizationPolicy', 'guarded_v1',
    'officialRoundCount', v_official_round_count,
    'certifiedRoundCount', v_certified_round_count,
    'roundsCertified', v_rounds_certified,
    'currentRoundOfficializationReady', v_current_officialization_ready,
    'canFinalizeCurrent',
      coalesce((v_state ->> 'canFinalizeCurrent')::boolean, false)
      and v_current_officialization_ready,
    'lastRoundRunId', v_latest_run.id,
    'lastCertifiedRound', v_latest_run.round_number,
    'lastRoundFinalizedAt', v_latest_run.finalized_at
  );
end;
$$;

revoke all on function public.get_league_cup_state_v3(uuid)
from public, anon, authenticated;
grant execute on function public.get_league_cup_state_v3(uuid)
to authenticated;

create or replace function public.finalize_league_cup_round_guarded_v1(
  p_league_id uuid,
  p_round_number smallint,
  p_request_id uuid
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
  v_officialization public.matchday_officialization_runs%rowtype;
  v_existing_run public.league_cup_round_finalization_runs%rowtype;
  v_tie public.league_cup_ties%rowtype;
  v_next_round_id uuid;
  v_next_position integer;
  v_winner_id uuid;
  v_loser_id uuid;
  v_winner_seed smallint;
  v_decided_by text;
  v_unready_count integer := 0;
  v_tie_count integer := 0;
  v_finalized_tie_count integer := 0;
  v_final_tie public.league_cup_ties%rowtype;
  v_champion_name text;
  v_member_user_id uuid;
  v_input_hash text;
  v_result_hash text;
  v_payload jsonb;
  v_run_id bigint;
  v_completed boolean := false;
begin
  if auth.uid() is null then
    raise exception 'Devi effettuare l''accesso.';
  end if;

  if p_request_id is null then
    raise exception 'Identificativo richiesta mancante.';
  end if;

  if p_round_number is null or p_round_number < 1 then
    raise exception 'Turno di Coppa non valido.';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(
      'leghevo:league-cup-round-finalization:' || p_league_id::text,
      0
    )
  );

  select run.*
  into v_existing_run
  from public.league_cup_round_finalization_runs run
  where run.league_id = p_league_id
    and run.request_id = p_request_id;

  if found then
    return public.get_league_cup_state_v3(p_league_id)
      || jsonb_build_object(
        'idempotentReplay', true,
        'roundFinalizationRunId', v_existing_run.id
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

  select cup_round.*
  into v_round
  from public.league_cup_rounds cup_round
  where cup_round.cup_id = v_cup.id
    and cup_round.round_number = p_round_number
  for update;

  if not found then
    raise exception 'Turno corrente della Coppa non trovato.';
  end if;

  select run.*
  into v_existing_run
  from public.league_cup_round_finalization_runs run
  where run.round_id = v_round.id;

  if found then
    return public.get_league_cup_state_v3(p_league_id)
      || jsonb_build_object(
        'idempotentReplay', true,
        'roundFinalizationRunId', v_existing_run.id
      );
  end if;

  if v_cup.status = 'completed' then
    raise exception 'La Coppa di Lega è già conclusa.';
  end if;

  if p_round_number <> v_cup.current_round then
    raise exception 'Il turno richiesto non è quello corrente della Coppa.';
  end if;

  select matchday.*
  into v_matchday
  from public.matchdays matchday
  where matchday.id = v_round.matchday_id;

  if not found then
    raise exception 'Giornata associata al turno non trovata.';
  end if;

  if now() < coalesce(v_matchday.ends_at, v_matchday.starts_at + interval '4 days') then
    raise exception 'La giornata reale del turno non è ancora terminata.';
  end if;

  select officialization.*
  into v_officialization
  from public.matchday_officialization_runs officialization
  where officialization.league_id = p_league_id
    and officialization.matchday_id = v_round.matchday_id
    and officialization.superseded_at is null;

  if not found then
    raise exception
      'Prima di ufficializzare la Coppa devi ufficializzare la giornata di campionato.';
  end if;

  perform public.refresh_league_cup_round_internal(
    v_cup.id,
    v_round.round_number
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
    raise exception 'Mancano ancora voti definitivi per % sfide.', v_unready_count;
  end if;

  v_input_hash := public.league_cup_round_input_hash_v1(
    v_cup.id,
    v_round.round_number
  );

  if v_input_hash is null then
    raise exception 'Impossibile certificare la sorgente del turno di Coppa.';
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
    set eliminated_round = v_round.round_number
    where cup_id = v_cup.id
      and fantasy_team_id = v_loser_id;
  end loop;

  update public.league_cup_rounds
  set
    status = 'official',
    finalized_at = now(),
    finalized_by = auth.uid()
  where id = v_round.id;

  if v_round.round_number = v_cup.round_count then
    select tie.*
    into v_final_tie
    from public.league_cup_ties tie
    where tie.round_id = v_round.id
    order by tie.bracket_position
    limit 1;

    v_winner_id := v_final_tie.winner_team_id;
    v_loser_id := case
      when v_final_tie.home_team_id = v_winner_id then v_final_tie.away_team_id
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

    v_completed := true;

    select team.name
    into v_champion_name
    from public.fantasy_teams team
    where team.id = v_winner_id;
  else
    select cup_round.id
    into v_next_round_id
    from public.league_cup_rounds cup_round
    where cup_round.cup_id = v_cup.id
      and cup_round.round_number = v_round.round_number + 1;

    if v_next_round_id is null then
      raise exception 'Turno successivo della Coppa non trovato.';
    end if;

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
        set home_team_id = v_tie.winner_team_id,
            home_seed = v_winner_seed
        where round_id = v_next_round_id
          and bracket_position = v_next_position;
      else
        update public.league_cup_ties
        set away_team_id = v_tie.winner_team_id,
            away_seed = v_winner_seed
        where round_id = v_next_round_id
          and bracket_position = v_next_position;
      end if;
    end loop;

    update public.league_cups
    set current_round = current_round + 1
    where id = v_cup.id;
  end if;

  select
    count(*)::integer,
    count(*) filter (where tie.winner_team_id is not null)::integer
  into v_tie_count, v_finalized_tie_count
  from public.league_cup_ties tie
  where tie.round_id = v_round.id;

  v_result_hash := public.league_cup_round_result_hash_v1(
    v_cup.id,
    v_round.round_number
  );

  v_payload := jsonb_build_object(
    'cupId', v_cup.id,
    'roundId', v_round.id,
    'roundNumber', v_round.round_number,
    'matchdayId', v_round.matchday_id,
    'officializationId', v_officialization.id,
    'officializationHash', v_officialization.result_hash,
    'inputHash', v_input_hash,
    'resultHash', v_result_hash,
    'tieCount', v_tie_count,
    'finalizedTieCount', v_finalized_tie_count,
    'nextRoundId', v_next_round_id,
    'cupCompleted', v_completed,
    'championTeamId', case when v_completed then v_winner_id else null end
  );

  insert into public.league_cup_round_finalization_runs (
    league_id,
    cup_id,
    round_id,
    matchday_id,
    officialization_run_id,
    request_id,
    requested_by,
    round_number,
    input_hash,
    result_hash,
    tie_count,
    finalized_tie_count,
    next_round_id,
    champion_team_id,
    cup_completed,
    result_payload
  ) values (
    p_league_id,
    v_cup.id,
    v_round.id,
    v_round.matchday_id,
    v_officialization.id,
    p_request_id,
    auth.uid(),
    v_round.round_number,
    v_input_hash,
    v_result_hash,
    v_tie_count,
    v_finalized_tie_count,
    v_next_round_id,
    case when v_completed then v_winner_id else null end,
    v_completed,
    v_payload
  )
  returning id into v_run_id;

  if to_regprocedure(
    'public.create_user_notification(uuid,uuid,text,text,text,text,jsonb,text)'
  ) is not null then
    for v_member_user_id in
      select member.user_id
      from public.league_members member
      where member.league_id = p_league_id
    loop
      if v_completed then
        perform public.create_user_notification(
          v_member_user_id,
          p_league_id,
          'league',
          'La Coppa di Lega ha un campione',
          format('%s alza la coppa. Il tabellone è definitivo.', v_champion_name),
          'leagueCup',
          jsonb_build_object(
            'cupId', v_cup.id,
            'championTeamId', v_winner_id,
            'roundFinalizationRunId', v_run_id
          ),
          format('league-cup-completed:%s', v_cup.id)
        );
      else
        perform public.create_user_notification(
          v_member_user_id,
          p_league_id,
          'league',
          format('%s ufficiali', v_round.name),
          'Il tabellone certificato è aggiornato: il prossimo turno vi aspetta.',
          'leagueCup',
          jsonb_build_object(
            'cupId', v_cup.id,
            'roundNumber', v_round.round_number,
            'roundFinalizationRunId', v_run_id
          ),
          format('league-cup-round:%s:%s', v_cup.id, v_round.round_number)
        );
      end if;
    end loop;
  end if;

  return public.get_league_cup_state_v3(p_league_id)
    || jsonb_build_object(
      'idempotentReplay', false,
      'roundFinalizationRunId', v_run_id
    );
end;
$$;

revoke all on function public.finalize_league_cup_round_guarded_v1(uuid, smallint, uuid)
from public, anon, authenticated;
grant execute on function public.finalize_league_cup_round_guarded_v1(uuid, smallint, uuid)
to authenticated;

-- Compatibilità: il vecchio endpoint confluisce nel percorso protetto.
create or replace function public.finalize_league_cup_round(
  p_league_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_cup_id uuid;
  v_round_number integer;
  v_request_id uuid;
begin
  select cup.id, cup.current_round
  into v_cup_id, v_round_number
  from public.league_cups cup
  where cup.league_id = p_league_id;

  v_request_id := public.leghevo_stable_request_uuid(
    'league-cup-round-finalization:'
      || p_league_id::text || ':'
      || coalesce(v_cup_id::text, 'missing') || ':'
      || coalesce(v_round_number::text, 'missing')
  );

  return public.finalize_league_cup_round_guarded_v1(
    p_league_id,
    v_round_number::smallint,
    v_request_id
  );
end;
$$;

revoke all on function public.finalize_league_cup_round(uuid)
from public, anon, authenticated;
grant execute on function public.finalize_league_cup_round(uuid)
to authenticated;

create or replace function public.get_league_cup_round_integrity_v1(
  p_league_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_official_round_count integer := 0;
  v_run_count integer := 0;
  v_missing_run_count integer := 0;
  v_duplicate_request_count integer := 0;
  v_hash_issue_count integer := 0;
  v_source_drift_count integer := 0;
  v_result_drift_count integer := 0;
  v_tie_count_issue_count integer := 0;
  v_officialization_issue_count integer := 0;
  v_progression_issue_count integer := 0;
  v_healthy boolean := false;
begin
  if auth.uid() is null
    or (not public.is_league_member(p_league_id)
      and not public.is_league_admin(p_league_id)) then
    raise exception 'Non fai parte di questa lega.';
  end if;

  select count(*)::integer
  into v_official_round_count
  from public.league_cup_rounds cup_round
  join public.league_cups cup on cup.id = cup_round.cup_id
  where cup.league_id = p_league_id
    and cup_round.status = 'official';

  select count(*)::integer
  into v_run_count
  from public.league_cup_round_finalization_runs run
  where run.league_id = p_league_id;

  select count(*)::integer
  into v_missing_run_count
  from public.league_cup_rounds cup_round
  join public.league_cups cup on cup.id = cup_round.cup_id
  where cup.league_id = p_league_id
    and cup_round.status = 'official'
    and not exists (
      select 1
      from public.league_cup_round_finalization_runs run
      where run.round_id = cup_round.id
    );

  select count(*)::integer
  into v_duplicate_request_count
  from (
    select run.request_id
    from public.league_cup_round_finalization_runs run
    where run.league_id = p_league_id
    group by run.request_id
    having count(*) > 1
  ) duplicates;

  select count(*)::integer
  into v_hash_issue_count
  from public.league_cup_round_finalization_runs run
  where run.league_id = p_league_id
    and (char_length(run.input_hash) <> 64 or char_length(run.result_hash) <> 64);

  select count(*)::integer
  into v_source_drift_count
  from public.league_cup_round_finalization_runs run
  where run.league_id = p_league_id
    and run.input_hash is distinct from public.league_cup_round_input_hash_v1(
      run.cup_id,
      run.round_number
    );

  select count(*)::integer
  into v_result_drift_count
  from public.league_cup_round_finalization_runs run
  where run.league_id = p_league_id
    and run.result_hash is distinct from public.league_cup_round_result_hash_v1(
      run.cup_id,
      run.round_number
    );

  select count(*)::integer
  into v_tie_count_issue_count
  from public.league_cup_round_finalization_runs run
  where run.league_id = p_league_id
    and (
      run.tie_count <> (
        select count(*) from public.league_cup_ties tie
        where tie.round_id = run.round_id
      )
      or run.finalized_tie_count <> (
        select count(*) from public.league_cup_ties tie
        where tie.round_id = run.round_id
          and tie.winner_team_id is not null
      )
    );

  select count(*)::integer
  into v_officialization_issue_count
  from public.league_cup_round_finalization_runs run
  left join public.matchday_officialization_runs officialization
    on officialization.id = run.officialization_run_id
  where run.league_id = p_league_id
    and (
      officialization.id is null
      or officialization.league_id <> run.league_id
      or officialization.matchday_id <> run.matchday_id
    );

  select count(*)::integer
  into v_progression_issue_count
  from public.league_cup_round_finalization_runs run
  where run.league_id = p_league_id
    and not run.cup_completed
    and (
      run.next_round_id is null
      or not exists (
        select 1
        from public.league_cup_ties next_tie
        where next_tie.round_id = run.next_round_id
          and (next_tie.home_team_id is not null or next_tie.away_team_id is not null)
      )
    );

  v_healthy :=
    v_missing_run_count = 0
    and v_duplicate_request_count = 0
    and v_hash_issue_count = 0
    and v_source_drift_count = 0
    and v_result_drift_count = 0
    and v_tie_count_issue_count = 0
    and v_officialization_issue_count = 0
    and v_progression_issue_count = 0;

  return jsonb_build_object(
    'policy', 'guarded_v1',
    'healthy', v_healthy,
    'officialRoundCount', v_official_round_count,
    'finalizationRunCount', v_run_count,
    'missingRunCount', v_missing_run_count,
    'duplicateRequestCount', v_duplicate_request_count,
    'hashIssueCount', v_hash_issue_count,
    'sourceDriftCount', v_source_drift_count,
    'resultDriftCount', v_result_drift_count,
    'tieCountIssueCount', v_tie_count_issue_count,
    'officializationIssueCount', v_officialization_issue_count,
    'progressionIssueCount', v_progression_issue_count
  );
end;
$$;

revoke all on function public.get_league_cup_round_integrity_v1(uuid)
from public, anon, authenticated;
grant execute on function public.get_league_cup_round_integrity_v1(uuid)
to authenticated;

-- Certifica in modo non distruttivo eventuali turni storici già ufficiali.
insert into public.league_cup_round_finalization_runs (
  league_id,
  cup_id,
  round_id,
  matchday_id,
  officialization_run_id,
  request_id,
  requested_by,
  round_number,
  input_hash,
  result_hash,
  tie_count,
  finalized_tie_count,
  next_round_id,
  champion_team_id,
  cup_completed,
  result_payload,
  finalized_at
)
select
  cup.league_id,
  cup.id,
  cup_round.id,
  cup_round.matchday_id,
  officialization.id,
  public.leghevo_stable_request_uuid(
    'league-cup-round-backfill:' || cup_round.id::text
  ),
  cup_round.finalized_by,
  cup_round.round_number,
  public.league_cup_round_input_hash_v1(cup.id, cup_round.round_number),
  public.league_cup_round_result_hash_v1(cup.id, cup_round.round_number),
  (select count(*) from public.league_cup_ties tie where tie.round_id = cup_round.id),
  (select count(*) from public.league_cup_ties tie where tie.round_id = cup_round.id and tie.winner_team_id is not null),
  next_round.id,
  case when cup_round.round_number = cup.round_count then cup.champion_team_id else null end,
  cup_round.round_number = cup.round_count and cup.status = 'completed',
  jsonb_build_object(
    'backfilled', true,
    'cupId', cup.id,
    'roundId', cup_round.id,
    'roundNumber', cup_round.round_number,
    'officializationId', officialization.id
  ),
  coalesce(cup_round.finalized_at, now())
from public.league_cup_rounds cup_round
join public.league_cups cup on cup.id = cup_round.cup_id
join public.matchday_officialization_runs officialization
  on officialization.league_id = cup.league_id
  and officialization.matchday_id = cup_round.matchday_id
  and officialization.superseded_at is null
left join public.league_cup_rounds next_round
  on next_round.cup_id = cup.id
  and next_round.round_number = cup_round.round_number + 1
where cup_round.status = 'official'
  and exists (
    select 1 from public.league_cup_ties tie
    where tie.round_id = cup_round.id
  )
  and not exists (
    select 1 from public.league_cup_ties tie
    where tie.round_id = cup_round.id
      and tie.winner_team_id is null
  )
  and (
    cup_round.round_number <> cup.round_count
    or cup.status <> 'completed'
    or cup.champion_team_id is not null
  )
  and public.league_cup_round_input_hash_v1(cup.id, cup_round.round_number) is not null
  and public.league_cup_round_result_hash_v1(cup.id, cup_round.round_number) is not null
  and not exists (
    select 1
    from public.league_cup_round_finalization_runs run
    where run.round_id = cup_round.id
  );

do $$
begin
  if exists (
    select 1 from pg_publication where pubname = 'supabase_realtime'
  ) and not exists (
    select 1
    from pg_publication_tables publication_table
    where publication_table.pubname = 'supabase_realtime'
      and publication_table.schemaname = 'public'
      and publication_table.tablename = 'league_cup_round_finalization_runs'
  ) then
    alter publication supabase_realtime
      add table public.league_cup_round_finalization_runs;
  end if;
end;
$$;

commit;

-- Diagnostica finale: devono risultare esattamente 20 valori true.
select
  to_regclass('public.league_cup_round_finalization_runs') is not null
    as round_finalization_table_ready,
  exists (
    select 1 from pg_indexes
    where schemaname = 'public'
      and indexname = 'league_cup_round_finalization_request_uidx'
  ) as request_idempotency_index_ready,
  exists (
    select 1 from pg_indexes
    where schemaname = 'public'
      and indexname = 'league_cup_round_finalization_round_uidx'
  ) as single_round_run_index_ready,
  exists (
    select 1 from pg_indexes
    where schemaname = 'public'
      and indexname = 'league_cup_round_finalization_lookup_idx'
  ) as finalization_lookup_index_ready,
  exists (
    select 1 from pg_indexes
    where schemaname = 'public'
      and indexname = 'league_cup_round_finalization_officialization_idx'
  ) as officialization_link_index_ready,
  coalesce((
    select relrowsecurity
    from pg_class
    where oid = 'public.league_cup_round_finalization_runs'::regclass
  ), false) as round_finalization_rls_ready,
  exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'league_cup_round_finalization_runs'
      and policyname = 'league_cup_round_finalization_read_members'
  ) as member_read_policy_ready,
  has_table_privilege(
    'authenticated',
    'public.league_cup_round_finalization_runs',
    'SELECT'
  ) as authenticated_read_ready,
  not has_table_privilege(
    'authenticated',
    'public.league_cup_round_finalization_runs',
    'INSERT'
  ) as direct_insert_blocked,
  to_regprocedure(
    'public.prevent_league_cup_round_finalization_mutation()'
  ) is not null as mutation_guard_ready,
  exists (
    select 1
    from pg_trigger trigger_row
    where trigger_row.tgrelid =
      'public.league_cup_round_finalization_runs'::regclass
      and not trigger_row.tgisinternal
      and trigger_row.tgname =
        'league_cup_round_finalization_runs_immutable'
  ) as immutable_trigger_ready,
  to_regprocedure(
    'public.refresh_league_cup_round_internal(uuid,integer)'
  ) is not null as certified_round_refresh_ready,
  to_regprocedure(
    'public.leghevo_sha256_hex_v1(text)'
  ) is not null
  and to_regprocedure(
    'public.league_cup_round_input_hash_v1(uuid,integer)'
  ) is not null
  and pg_get_functiondef(
    'public.create_league_cup_guarded_v1(uuid,smallint,uuid)'::regprocedure
  ) ilike '%leghevo_sha256_hex_v1%'
    as cup_hash_pipeline_ready,
  to_regprocedure(
    'public.league_cup_round_result_hash_v1(uuid,integer)'
  ) is not null as round_result_hash_ready,
  to_regprocedure(
    'public.finalize_league_cup_round_guarded_v1(uuid,smallint,uuid)'
  ) is not null as guarded_round_finalization_ready,
  has_function_privilege(
    'authenticated',
    'public.finalize_league_cup_round_guarded_v1(uuid,smallint,uuid)',
    'EXECUTE'
  ) as guarded_round_finalization_access_ready,
  to_regprocedure(
    'public.get_league_cup_state_v3(uuid)'
  ) is not null as cup_state_v3_ready,
  to_regprocedure(
    'public.get_league_cup_round_integrity_v1(uuid)'
  ) is not null as round_diagnostics_ready,
  pg_get_functiondef(
    'public.finalize_league_cup_round(uuid)'::regprocedure
  ) ilike '%finalize_league_cup_round_guarded_v1%'
    as legacy_endpoint_guarded,
  exists (
    select 1
    from pg_publication_tables publication_table
    where publication_table.pubname = 'supabase_realtime'
      and publication_table.schemaname = 'public'
      and publication_table.tablename =
        'league_cup_round_finalization_runs'
  ) as round_finalization_realtime_ready;
