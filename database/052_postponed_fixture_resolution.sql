-- LEGHEVO · partite rinviate, sospese e voto d'ufficio
-- Eseguire nel SQL Editor di Supabase dopo 051.

alter table public.athletes
  add column if not exists provider_team_id text;

create index if not exists athletes_provider_team_idx
  on public.athletes (provider, provider_team_id)
  where provider_team_id is not null;

update public.athletes athlete
set provider_team_id = coalesce(
  nullif(athlete.payload #>> '{statistics,0,team,id}', ''),
  nullif(athlete.payload #>> '{team,id}', '')
)
where athlete.provider_team_id is null
  and coalesce(
    nullif(athlete.payload #>> '{statistics,0,team,id}', ''),
    nullif(athlete.payload #>> '{team,id}', '')
  ) is not null;

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
      'leagueOperations',
      'postponements',
      'lineup',
      'roster',
      'standings',
      'market'
    )
  );

create table if not exists public.league_fixture_resolutions (
  id uuid primary key default gen_random_uuid(),
  league_id uuid not null
    references public.leagues(id) on delete cascade,
  provider_fixture_id uuid not null
    references public.provider_fixtures(id) on delete cascade,
  decision text not null default 'political_score'
    check (decision = 'political_score'),
  political_score numeric(4,2) not null
    check (political_score between 0 and 10),
  reason text not null
    check (char_length(trim(reason)) between 10 and 280),
  decided_by uuid not null references public.profiles(id),
  decided_at timestamptz not null default now(),
  revoked_by uuid references public.profiles(id),
  revoked_at timestamptz,
  revocation_reason text
    check (
      revocation_reason is null
      or char_length(trim(revocation_reason)) between 3 and 280
    ),
  check (
    (revoked_at is null and revoked_by is null and revocation_reason is null)
    or (revoked_at is not null and revocation_reason is not null)
  )
);

create unique index if not exists league_fixture_active_resolution_idx
  on public.league_fixture_resolutions (league_id, provider_fixture_id)
  where revoked_at is null;

create index if not exists league_fixture_resolution_history_idx
  on public.league_fixture_resolutions (
    league_id,
    provider_fixture_id,
    decided_at desc
  );

create table if not exists public.league_fixture_resolution_events (
  id uuid primary key default gen_random_uuid(),
  resolution_id uuid not null
    references public.league_fixture_resolutions(id) on delete cascade,
  league_id uuid not null
    references public.leagues(id) on delete cascade,
  provider_fixture_id uuid not null
    references public.provider_fixtures(id) on delete cascade,
  event_type text not null
    check (event_type in ('applied', 'revoked', 'provider_final')),
  actor_id uuid references public.profiles(id),
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists league_fixture_resolution_events_idx
  on public.league_fixture_resolution_events (
    league_id,
    provider_fixture_id,
    created_at desc
  );

alter table public.league_fixture_resolutions enable row level security;
alter table public.league_fixture_resolution_events enable row level security;

drop policy if exists league_fixture_resolutions_read_members
on public.league_fixture_resolutions;

create policy league_fixture_resolutions_read_members
on public.league_fixture_resolutions for select to authenticated
using (
  public.is_league_member(league_id)
  or public.is_league_admin(league_id)
);

drop policy if exists league_fixture_resolution_events_read_members
on public.league_fixture_resolution_events;

create policy league_fixture_resolution_events_read_members
on public.league_fixture_resolution_events for select to authenticated
using (
  public.is_league_member(league_id)
  or public.is_league_admin(league_id)
);

revoke all on public.league_fixture_resolutions
from anon, authenticated;
revoke all on public.league_fixture_resolution_events
from anon, authenticated;

grant select on public.league_fixture_resolutions to authenticated;
grant select on public.league_fixture_resolution_events to authenticated;

do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'league_fixture_resolutions'
  ) then
    alter publication supabase_realtime
      add table public.league_fixture_resolutions;
  end if;
end;
$$;

create or replace function public.normalize_provider_club_name(
  p_name text
)
returns text
language sql
immutable
set search_path = ''
as $$
  select regexp_replace(
    lower(trim(coalesce(p_name, ''))),
    '[^a-z0-9]+',
    '',
    'g'
  )
$$;

revoke all on function public.normalize_provider_club_name(text)
from public, anon, authenticated;

create or replace function public.league_matchday_results_are_locked(
  p_league_id uuid,
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
      from public.fantasy_fixtures fixture
      where fixture.league_id = p_league_id
        and fixture.matchday_id = p_matchday_id
        and fixture.finalized_at is not null
    )
    or exists (
      select 1
      from public.league_cup_rounds cup_round
      join public.league_cups cup on cup.id = cup_round.cup_id
      where cup.league_id = p_league_id
        and cup_round.matchday_id = p_matchday_id
        and cup_round.finalized_at is not null
    )
    or exists (
      select 1
      from public.league_playoff_rounds playoff_round
      join public.league_playoffs playoff
        on playoff.id = playoff_round.playoff_id
      where playoff.league_id = p_league_id
        and playoff_round.matchday_id = p_matchday_id
        and playoff_round.finalized_at is not null
    )
    or exists (
      select 1
      from public.league_super_cups super_cup
      where super_cup.league_id = p_league_id
        and super_cup.matchday_id = p_matchday_id
        and super_cup.completed_at is not null
    )
$$;

revoke all on function public.league_matchday_results_are_locked(uuid, uuid)
from public, anon, authenticated;

create or replace function public.league_matchday_is_resolved(
  p_league_id uuid,
  p_matchday_id uuid
)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_provider_count integer := 0;
  v_fallback_complete boolean := false;
begin
  select
    count(provider_fixture.id)::integer,
    now() >= coalesce(
      matchday.ends_at,
      matchday.starts_at + interval '4 days'
    )
  into v_provider_count, v_fallback_complete
  from public.matchdays matchday
  left join public.provider_fixtures provider_fixture
    on provider_fixture.matchday_id = matchday.id
  where matchday.id = p_matchday_id
  group by matchday.ends_at, matchday.starts_at;

  if v_provider_count = 0 then
    return coalesce(v_fallback_complete, false);
  end if;

  return not exists (
    select 1
    from public.provider_fixtures provider_fixture
    where provider_fixture.matchday_id = p_matchday_id
      and provider_fixture.status not in ('FT', 'AET', 'PEN')
      and not exists (
        select 1
        from public.league_fixture_resolutions resolution
        where resolution.league_id = p_league_id
          and resolution.provider_fixture_id = provider_fixture.id
          and resolution.revoked_at is null
      )
  );
end;
$$;

revoke all on function public.league_matchday_is_resolved(uuid, uuid)
from public, anon, authenticated;

create or replace function public.get_league_effective_player_score(
  p_league_id uuid,
  p_athlete_id uuid,
  p_matchday_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_athlete public.athletes%rowtype;
  v_resolution record;
  v_score public.player_match_scores%rowtype;
begin
  select athlete.*
  into v_athlete
  from public.athletes athlete
  where athlete.id = p_athlete_id;

  if not found then
    return null;
  end if;

  select
    resolution.id,
    resolution.political_score,
    provider_fixture.provider_fixture_id
  into v_resolution
  from public.league_fixture_resolutions resolution
  join public.provider_fixtures provider_fixture
    on provider_fixture.id = resolution.provider_fixture_id
  where resolution.league_id = p_league_id
    and resolution.revoked_at is null
    and provider_fixture.matchday_id = p_matchday_id
    and provider_fixture.status not in ('FT', 'AET', 'PEN')
    and (
      (
        nullif(v_athlete.provider_team_id, '') is not null
        and v_athlete.provider_team_id in (
          provider_fixture.home_team_provider_id,
          provider_fixture.away_team_provider_id
        )
      )
      or public.normalize_provider_club_name(v_athlete.club_name) in (
        public.normalize_provider_club_name(
          provider_fixture.home_team_name
        ),
        public.normalize_provider_club_name(
          provider_fixture.away_team_name
        )
      )
    )
  order by resolution.decided_at desc
  limit 1;

  if found then
    return jsonb_build_object(
      'providerRating', v_resolution.political_score,
      'fantasyScore', v_resolution.political_score,
      'bonuses', '{}'::jsonb,
      'maluses', '{}'::jsonb,
      'rawStatistics',
        jsonb_build_object(
          'leghevoPoliticalScore', true,
          'resolutionId', v_resolution.id,
          'providerFixtureId', v_resolution.provider_fixture_id
        ),
      'isFinal', true,
      'scoreOrigin', 'political'
    );
  end if;

  select score.*
  into v_score
  from public.player_match_scores score
  where score.athlete_id = p_athlete_id
    and score.matchday_id = p_matchday_id
    and score.provider_rating is not null;

  if not found then
    return null;
  end if;

  return jsonb_build_object(
    'providerRating', v_score.provider_rating,
    'fantasyScore', v_score.fantasy_score,
    'bonuses', coalesce(v_score.bonuses, '{}'::jsonb),
    'maluses', coalesce(v_score.maluses, '{}'::jsonb),
    'rawStatistics', coalesce(v_score.raw_statistics, '{}'::jsonb),
    'isFinal', v_score.is_final,
    'scoreOrigin', 'provider'
  );
end;
$$;

revoke all on function public.get_league_effective_player_score(
  uuid,
  uuid,
  uuid
) from public, anon, authenticated;

create or replace function public.resolve_team_matchday_lineup(
  p_fantasy_team_id uuid,
  p_matchday_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_lineup record;
  v_matchday_complete boolean := false;
  v_max_substitutions integer := 5;
  v_substitutions_used integer := 0;
  v_counted_players integer := 0;
  v_unavailable_starters integer := 0;
  v_total_points numeric := 0;
  v_is_ready boolean := false;
  v_starter record;
  v_candidate record;
  v_score jsonb;
  v_effective_athlete_id uuid;
  v_effective_name text;
  v_effective_role text;
  v_provider_rating numeric;
  v_fantasy_score numeric;
  v_bonuses jsonb;
  v_maluses jsonb;
  v_raw_statistics jsonb;
  v_is_final boolean;
  v_score_origin text;
  v_is_substitute boolean;
  v_replaced_player_name text;
  v_blocked_reason text;
  v_used_bench_ids uuid[] := array[]::uuid[];
  v_players jsonb := '[]'::jsonb;
begin
  select
    lineup.id,
    lineup.formation,
    team.league_id,
    league.mode,
    league.scoring_rules
  into v_lineup
  from public.fantasy_teams team
  join public.leagues league
    on league.id = team.league_id
  left join public.lineups lineup
    on lineup.fantasy_team_id = team.id
    and lineup.matchday_id = p_matchday_id
    and lineup.status in ('submitted', 'locked')
  where team.id = p_fantasy_team_id;

  if not found then
    return jsonb_build_object(
      'available', false,
      'matchdayComplete', false,
      'totalPoints', null,
      'isReady', false,
      'countedPlayers', 0,
      'maxSubstitutions', v_max_substitutions,
      'substitutionsUsed', 0,
      'unavailableStarters', 0,
      'players', v_players
    );
  end if;

  v_matchday_complete := public.league_matchday_is_resolved(
    v_lineup.league_id,
    p_matchday_id
  );
  v_matchday_complete := coalesce(v_matchday_complete, false);
  v_is_ready := v_matchday_complete;

  if coalesce(v_lineup.scoring_rules ->> 'max_substitutions', '')
      ~ '^[0-9]+$' then
    v_max_substitutions := least(
      greatest(
        (v_lineup.scoring_rules ->> 'max_substitutions')::integer,
        0
      ),
      11
    );
  end if;

  if v_lineup.id is null then
    return jsonb_build_object(
      'available', false,
      'matchdayComplete', v_matchday_complete,
      'totalPoints',
        case when v_matchday_complete then 0 else null end,
      'isReady', v_matchday_complete,
      'countedPlayers', 0,
      'maxSubstitutions', v_max_substitutions,
      'substitutionsUsed', 0,
      'unavailableStarters', 0,
      'players', v_players
    );
  end if;

  for v_starter in
    select
      entry.athlete_id,
      entry.slot,
      concat_ws(
        ' ',
        nullif(trim(athlete.first_name), ''),
        athlete.last_name
      ) as player_name,
      coalesce(
        (
          select string_agg(
            role.role_code,
            '/' order by role.role_code
          )
          from public.athlete_roles role
          where role.athlete_id = athlete.id
            and role.mode = v_lineup.mode
        ),
        '—'
      ) as player_role
    from public.lineup_entries entry
    join public.athletes athlete
      on athlete.id = entry.athlete_id
    where entry.lineup_id = v_lineup.id
      and entry.is_starter
    order by entry.slot
  loop
    v_effective_athlete_id := v_starter.athlete_id;
    v_effective_name := v_starter.player_name;
    v_effective_role := v_starter.player_role;
    v_provider_rating := null;
    v_fantasy_score := null;
    v_bonuses := '{}'::jsonb;
    v_maluses := '{}'::jsonb;
    v_raw_statistics := '{}'::jsonb;
    v_is_final := false;
    v_score_origin := null;
    v_is_substitute := false;
    v_replaced_player_name := null;
    v_blocked_reason := null;

    v_score := public.get_league_effective_player_score(
      v_lineup.league_id,
      v_starter.athlete_id,
      p_matchday_id
    );

    if v_score is not null then
      v_provider_rating :=
        nullif(v_score ->> 'providerRating', '')::numeric;
      v_score_origin := coalesce(v_score ->> 'scoreOrigin', 'provider');
      v_fantasy_score := case
        when v_score_origin = 'political'
          then nullif(v_score ->> 'fantasyScore', '')::numeric
        else public.calculate_league_fantasy_score(
          nullif(v_score ->> 'providerRating', '')::numeric,
          nullif(v_score ->> 'fantasyScore', '')::numeric,
          coalesce(v_score -> 'rawStatistics', '{}'::jsonb),
          v_lineup.scoring_rules
        )
      end;
      v_bonuses := coalesce(v_score -> 'bonuses', '{}'::jsonb);
      v_maluses := coalesce(v_score -> 'maluses', '{}'::jsonb);
      v_raw_statistics :=
        coalesce(v_score -> 'rawStatistics', '{}'::jsonb);
      v_is_final :=
        coalesce((v_score ->> 'isFinal')::boolean, false);
    else
      if not v_matchday_complete then
        v_blocked_reason := 'awaiting_score';
      elsif v_substitutions_used >= v_max_substitutions then
        v_blocked_reason := 'limit_reached';
      else
        select
          bench.athlete_id,
          concat_ws(
            ' ',
            nullif(trim(athlete.first_name), ''),
            athlete.last_name
          ) as player_name,
          coalesce(
            (
              select string_agg(
                role.role_code,
                '/' order by role.role_code
              )
              from public.athlete_roles role
              where role.athlete_id = athlete.id
                and role.mode = v_lineup.mode
            ),
            '—'
          ) as player_role,
          nullif(effective.item ->> 'providerRating', '')::numeric
            as provider_rating,
          case
            when effective.item ->> 'scoreOrigin' = 'political'
              then nullif(
                effective.item ->> 'fantasyScore',
                ''
              )::numeric
            else public.calculate_league_fantasy_score(
              nullif(
                effective.item ->> 'providerRating',
                ''
              )::numeric,
              nullif(
                effective.item ->> 'fantasyScore',
                ''
              )::numeric,
              coalesce(
                effective.item -> 'rawStatistics',
                '{}'::jsonb
              ),
              v_lineup.scoring_rules
            )
          end as fantasy_score,
          coalesce(effective.item -> 'bonuses', '{}'::jsonb)
            as bonuses,
          coalesce(effective.item -> 'maluses', '{}'::jsonb)
            as maluses,
          coalesce(
            effective.item -> 'rawStatistics',
            '{}'::jsonb
          ) as raw_statistics,
          coalesce(
            (effective.item ->> 'isFinal')::boolean,
            false
          ) as is_final,
          coalesce(
            effective.item ->> 'scoreOrigin',
            'provider'
          ) as score_origin
        into v_candidate
        from public.lineup_entries bench
        join public.athletes athlete
          on athlete.id = bench.athlete_id
        cross join lateral (
          select public.get_league_effective_player_score(
            v_lineup.league_id,
            bench.athlete_id,
            p_matchday_id
          ) as item
        ) effective
        where bench.lineup_id = v_lineup.id
          and not bench.is_starter
          and not (bench.athlete_id = any(v_used_bench_ids))
          and effective.item is not null
          and nullif(
            effective.item ->> 'providerRating',
            ''
          ) is not null
          and public.lineup_players_are_substitution_compatible(
            v_starter.athlete_id,
            bench.athlete_id,
            v_lineup.mode
          )
        order by bench.slot
        limit 1;

        if found then
          v_effective_athlete_id := v_candidate.athlete_id;
          v_effective_name := v_candidate.player_name;
          v_effective_role := v_candidate.player_role;
          v_provider_rating := v_candidate.provider_rating;
          v_fantasy_score := v_candidate.fantasy_score;
          v_bonuses := v_candidate.bonuses;
          v_maluses := v_candidate.maluses;
          v_raw_statistics := v_candidate.raw_statistics;
          v_is_final := v_candidate.is_final;
          v_score_origin := v_candidate.score_origin;
          v_is_substitute := true;
          v_replaced_player_name := v_starter.player_name;
          v_used_bench_ids := array_append(
            v_used_bench_ids,
            v_candidate.athlete_id
          );
          v_substitutions_used := v_substitutions_used + 1;
        else
          v_blocked_reason := 'no_compatible_bench';
        end if;
      end if;
    end if;

    if v_provider_rating is not null then
      v_total_points := v_total_points + v_fantasy_score;
      v_counted_players := v_counted_players + 1;
      v_is_ready := v_is_ready and coalesce(v_is_final, false);
    elsif v_matchday_complete then
      v_unavailable_starters := v_unavailable_starters + 1;
    end if;

    v_players := v_players || jsonb_build_array(
      jsonb_build_object(
        'athleteId', v_effective_athlete_id,
        'name', v_effective_name,
        'role', v_effective_role,
        'slot', v_starter.slot,
        'providerRating', v_provider_rating,
        'fantasyScore', v_fantasy_score,
        'bonuses', coalesce(v_bonuses, '{}'::jsonb),
        'maluses', coalesce(v_maluses, '{}'::jsonb),
        'rawStatistics', coalesce(v_raw_statistics, '{}'::jsonb),
        'isFinal', coalesce(v_is_final, false),
        'scoreOrigin', v_score_origin,
        'isSubstitute', v_is_substitute,
        'replacedPlayerName', v_replaced_player_name,
        'blockedReason', v_blocked_reason
      )
    );
  end loop;

  if v_counted_players = 0 then
    v_total_points := case
      when v_matchday_complete then 0
      else null
    end;
  else
    v_total_points := round(v_total_points, 2);
  end if;

  return jsonb_build_object(
    'available', true,
    'matchdayComplete', v_matchday_complete,
    'totalPoints', v_total_points,
    'isReady', v_is_ready,
    'countedPlayers', v_counted_players,
    'maxSubstitutions', v_max_substitutions,
    'substitutionsUsed', v_substitutions_used,
    'unavailableStarters', v_unavailable_starters,
    'players', v_players
  );
end;
$$;

revoke all on function public.resolve_team_matchday_lineup(uuid, uuid)
from public, anon, authenticated;

create or replace function public.refresh_league_after_fixture_resolution(
  p_league_id uuid,
  p_matchday_id uuid
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_updated integer := 0;
  v_cup record;
  v_playoff record;
  v_super_cup_id uuid;
begin
  v_updated := public.refresh_matchday_results_internal(p_matchday_id);

  select cup.id, cup.current_round
  into v_cup
  from public.league_cups cup
  where cup.league_id = p_league_id
    and cup.status <> 'completed';

  if found and exists (
    select 1
    from public.league_cup_rounds cup_round
    where cup_round.cup_id = v_cup.id
      and cup_round.round_number = v_cup.current_round
      and cup_round.matchday_id = p_matchday_id
      and cup_round.finalized_at is null
  ) then
    v_updated := v_updated
      + public.refresh_league_cup_round_internal(
        v_cup.id,
        v_cup.current_round
      );
  end if;

  select playoff.id, playoff.current_round
  into v_playoff
  from public.league_playoffs playoff
  where playoff.league_id = p_league_id
    and playoff.status = 'active';

  if found and exists (
    select 1
    from public.league_playoff_rounds playoff_round
    where playoff_round.playoff_id = v_playoff.id
      and playoff_round.round_number = v_playoff.current_round
      and playoff_round.matchday_id = p_matchday_id
      and playoff_round.finalized_at is null
  ) then
    v_updated := v_updated
      + public.refresh_league_playoff_round_internal(
        v_playoff.id,
        v_playoff.current_round
      );
  end if;

  select super_cup.id
  into v_super_cup_id
  from public.league_super_cups super_cup
  where super_cup.league_id = p_league_id
    and super_cup.matchday_id = p_matchday_id
    and super_cup.status = 'active';

  if found then
    v_updated := v_updated
      + public.refresh_league_super_cup_internal(v_super_cup_id);
  end if;

  return v_updated;
end;
$$;

revoke all on function public.refresh_league_after_fixture_resolution(
  uuid,
  uuid
) from public, anon, authenticated;

create or replace function public.get_league_postponement_center(
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
  v_issues jsonb := '[]'::jsonb;
  v_issue_count integer := 0;
  v_resolved_count integer := 0;
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
    coalesce(jsonb_agg(issue.item order by issue.kickoff_at), '[]'::jsonb),
    count(*)::integer,
    count(*) filter (where issue.resolution_id is not null)::integer
  into v_issues, v_issue_count, v_resolved_count
  from (
    select
      provider_fixture.kickoff_at,
      resolution.id as resolution_id,
      jsonb_build_object(
        'providerFixtureId', provider_fixture.id,
        'externalFixtureId', provider_fixture.provider_fixture_id,
        'matchdayId', provider_fixture.matchday_id,
        'matchdayNumber', matchday.number,
        'kickoffAt', provider_fixture.kickoff_at,
        'status', provider_fixture.status,
        'homeTeam', provider_fixture.home_team_name,
        'awayTeam', provider_fixture.away_team_name,
        'locked',
          public.league_matchday_results_are_locked(
            p_league_id,
            provider_fixture.matchday_id
          ),
        'resolution',
          case
            when resolution.id is null then null
            else jsonb_build_object(
              'id', resolution.id,
              'decision', resolution.decision,
              'politicalScore', resolution.political_score,
              'reason', resolution.reason,
              'decidedAt', resolution.decided_at,
              'decidedBy',
                coalesce(profile.display_name, 'Presidente')
            )
          end
      ) as item
    from public.provider_fixtures provider_fixture
    join public.matchdays matchday
      on matchday.id = provider_fixture.matchday_id
    left join public.league_fixture_resolutions resolution
      on resolution.league_id = p_league_id
      and resolution.provider_fixture_id = provider_fixture.id
      and resolution.revoked_at is null
    left join public.profiles profile
      on profile.id = resolution.decided_by
    where (
      provider_fixture.status in (
        'PST',
        'SUSP',
        'INT',
        'CANC',
        'ABD',
        'TBD'
      )
      or resolution.id is not null
    )
      and (
        exists (
          select 1
          from public.fantasy_fixtures fixture
          where fixture.league_id = p_league_id
            and fixture.matchday_id = provider_fixture.matchday_id
        )
        or exists (
          select 1
          from public.league_cup_rounds cup_round
          join public.league_cups cup on cup.id = cup_round.cup_id
          where cup.league_id = p_league_id
            and cup_round.matchday_id = provider_fixture.matchday_id
        )
        or exists (
          select 1
          from public.league_playoff_rounds playoff_round
          join public.league_playoffs playoff
            on playoff.id = playoff_round.playoff_id
          where playoff.league_id = p_league_id
            and playoff_round.matchday_id = provider_fixture.matchday_id
        )
        or exists (
          select 1
          from public.league_super_cups super_cup
          where super_cup.league_id = p_league_id
            and super_cup.matchday_id = provider_fixture.matchday_id
        )
      )
  ) issue;

  return jsonb_build_object(
    'leagueId', v_league.id,
    'leagueName', v_league.name,
    'isOwner', v_league.owner_id = auth.uid(),
    'issueCount', coalesce(v_issue_count, 0),
    'resolvedCount', coalesce(v_resolved_count, 0),
    'unresolvedCount',
      greatest(
        coalesce(v_issue_count, 0) - coalesce(v_resolved_count, 0),
        0
      ),
    'issues', coalesce(v_issues, '[]'::jsonb)
  );
end;
$$;

revoke all on function public.get_league_postponement_center(uuid)
from public, anon, authenticated;

grant execute on function public.get_league_postponement_center(uuid)
to authenticated;

create or replace function public.apply_league_fixture_political_score(
  p_league_id uuid,
  p_provider_fixture_id uuid,
  p_political_score numeric,
  p_reason text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_league public.leagues%rowtype;
  v_provider_fixture public.provider_fixtures%rowtype;
  v_resolution_id uuid;
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
    raise exception 'Solo il Presidente può assegnare il voto d''ufficio.';
  end if;

  if v_league.status in ('completed', 'archived') then
    raise exception 'La stagione è già conclusa.';
  end if;

  if p_political_score is null
    or p_political_score < 0
    or p_political_score > 10 then
    raise exception 'Il voto d''ufficio deve essere compreso tra 0 e 10.';
  end if;

  if char_length(trim(coalesce(p_reason, ''))) < 10
    or char_length(trim(coalesce(p_reason, ''))) > 280 then
    raise exception 'Inserisci una motivazione da 10 a 280 caratteri.';
  end if;

  select provider_fixture.*
  into v_provider_fixture
  from public.provider_fixtures provider_fixture
  where provider_fixture.id = p_provider_fixture_id
  for update;

  if not found then
    raise exception 'Partita del provider non trovata.';
  end if;

  if v_provider_fixture.status not in (
    'PST',
    'SUSP',
    'INT',
    'CANC',
    'ABD',
    'TBD'
  ) then
    raise exception 'La partita non risulta rinviata o sospesa.';
  end if;

  if not exists (
    select 1
    from public.fantasy_fixtures fixture
    where fixture.league_id = p_league_id
      and fixture.matchday_id = v_provider_fixture.matchday_id
    union all
    select 1
    from public.league_cup_rounds cup_round
    join public.league_cups cup on cup.id = cup_round.cup_id
    where cup.league_id = p_league_id
      and cup_round.matchday_id = v_provider_fixture.matchday_id
    union all
    select 1
    from public.league_playoff_rounds playoff_round
    join public.league_playoffs playoff
      on playoff.id = playoff_round.playoff_id
    where playoff.league_id = p_league_id
      and playoff_round.matchday_id = v_provider_fixture.matchday_id
    union all
    select 1
    from public.league_super_cups super_cup
    where super_cup.league_id = p_league_id
      and super_cup.matchday_id = v_provider_fixture.matchday_id
  ) then
    raise exception 'La partita non appartiene al calendario della lega.';
  end if;

  if public.league_matchday_results_are_locked(
    p_league_id,
    v_provider_fixture.matchday_id
  ) then
    raise exception
      'Riapri prima i risultati ufficiali della giornata interessata.';
  end if;

  if exists (
    select 1
    from public.league_fixture_resolutions resolution
    where resolution.league_id = p_league_id
      and resolution.provider_fixture_id = p_provider_fixture_id
      and resolution.revoked_at is null
  ) then
    raise exception 'Un voto d''ufficio è già attivo per questa partita.';
  end if;

  insert into public.league_fixture_resolutions (
    league_id,
    provider_fixture_id,
    political_score,
    reason,
    decided_by
  )
  values (
    p_league_id,
    p_provider_fixture_id,
    round(p_political_score, 2),
    trim(p_reason),
    auth.uid()
  )
  returning id into v_resolution_id;

  insert into public.league_fixture_resolution_events (
    resolution_id,
    league_id,
    provider_fixture_id,
    event_type,
    actor_id,
    details
  )
  values (
    v_resolution_id,
    p_league_id,
    p_provider_fixture_id,
    'applied',
    auth.uid(),
    jsonb_build_object(
      'politicalScore', round(p_political_score, 2),
      'reason', trim(p_reason),
      'providerStatus', v_provider_fixture.status
    )
  );

  perform public.refresh_league_after_fixture_resolution(
    p_league_id,
    v_provider_fixture.matchday_id
  );

  for v_member_user_id in
    select member.user_id
    from public.league_members member
    where member.league_id = p_league_id
  loop
    perform public.create_user_notification(
      v_member_user_id,
      p_league_id,
      'result',
      'Voto d''ufficio assegnato',
      v_provider_fixture.home_team_name
        || '–'
        || v_provider_fixture.away_team_name
        || ': voto '
        || trim(to_char(round(p_political_score, 2), 'FM990D00'))
        || ' per i calciatori coinvolti.',
      'postponements',
      jsonb_build_object(
        'event', 'political_score_applied',
        'provider_fixture_id', p_provider_fixture_id,
        'matchday_id', v_provider_fixture.matchday_id,
        'score', round(p_political_score, 2)
      ),
      'political-score:applied:'
        || v_resolution_id::text
        || ':'
        || v_member_user_id::text
    );
  end loop;

  return v_resolution_id;
end;
$$;

revoke all on function public.apply_league_fixture_political_score(
  uuid,
  uuid,
  numeric,
  text
) from public, anon;

grant execute on function public.apply_league_fixture_political_score(
  uuid,
  uuid,
  numeric,
  text
) to authenticated;

create or replace function public.revoke_league_fixture_political_score(
  p_league_id uuid,
  p_resolution_id uuid,
  p_reason text
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_league public.leagues%rowtype;
  v_resolution public.league_fixture_resolutions%rowtype;
  v_provider_fixture public.provider_fixtures%rowtype;
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
    raise exception 'Solo il Presidente può revocare il voto d''ufficio.';
  end if;

  if char_length(trim(coalesce(p_reason, ''))) < 3
    or char_length(trim(coalesce(p_reason, ''))) > 280 then
    raise exception 'Inserisci una motivazione da 3 a 280 caratteri.';
  end if;

  select resolution.*
  into v_resolution
  from public.league_fixture_resolutions resolution
  where resolution.id = p_resolution_id
    and resolution.league_id = p_league_id
    and resolution.revoked_at is null
  for update;

  if not found then
    raise exception 'Voto d''ufficio attivo non trovato.';
  end if;

  select provider_fixture.*
  into v_provider_fixture
  from public.provider_fixtures provider_fixture
  where provider_fixture.id = v_resolution.provider_fixture_id;

  if public.league_matchday_results_are_locked(
    p_league_id,
    v_provider_fixture.matchday_id
  ) then
    raise exception
      'Riapri prima i risultati ufficiali della giornata interessata.';
  end if;

  update public.league_fixture_resolutions
  set
    revoked_by = auth.uid(),
    revoked_at = now(),
    revocation_reason = trim(p_reason)
  where id = v_resolution.id;

  insert into public.league_fixture_resolution_events (
    resolution_id,
    league_id,
    provider_fixture_id,
    event_type,
    actor_id,
    details
  )
  values (
    v_resolution.id,
    p_league_id,
    v_resolution.provider_fixture_id,
    'revoked',
    auth.uid(),
    jsonb_build_object('reason', trim(p_reason))
  );

  perform public.refresh_league_after_fixture_resolution(
    p_league_id,
    v_provider_fixture.matchday_id
  );

  for v_member_user_id in
    select member.user_id
    from public.league_members member
    where member.league_id = p_league_id
  loop
    perform public.create_user_notification(
      v_member_user_id,
      p_league_id,
      'result',
      'Voto d''ufficio revocato',
      v_provider_fixture.home_team_name
        || '–'
        || v_provider_fixture.away_team_name
        || ': LEGHEVO torna ad attendere il recupero.',
      'postponements',
      jsonb_build_object(
        'event', 'political_score_revoked',
        'provider_fixture_id', v_resolution.provider_fixture_id,
        'matchday_id', v_provider_fixture.matchday_id
      ),
      'political-score:revoked:'
        || v_resolution.id::text
        || ':'
        || v_member_user_id::text
    );
  end loop;

  return true;
end;
$$;

revoke all on function public.revoke_league_fixture_political_score(
  uuid,
  uuid,
  text
) from public, anon;

grant execute on function public.revoke_league_fixture_political_score(
  uuid,
  uuid,
  text
) to authenticated;

create or replace function public.close_fixture_resolutions_after_final()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_resolution record;
begin
  if new.status not in ('FT', 'AET', 'PEN')
    or old.status in ('FT', 'AET', 'PEN') then
    return new;
  end if;

  for v_resolution in
    select resolution.*
    from public.league_fixture_resolutions resolution
    where resolution.provider_fixture_id = new.id
      and resolution.revoked_at is null
    for update
  loop
    update public.league_fixture_resolutions
    set
      revoked_at = now(),
      revocation_reason = 'Risultato ufficiale ricevuto dal provider.'
    where id = v_resolution.id;

    insert into public.league_fixture_resolution_events (
      resolution_id,
      league_id,
      provider_fixture_id,
      event_type,
      actor_id,
      details
    )
    values (
      v_resolution.id,
      v_resolution.league_id,
      new.id,
      'provider_final',
      null,
      jsonb_build_object(
        'providerStatus', new.status,
        'reason', 'Risultato ufficiale ricevuto dal provider.'
      )
    );

    perform public.refresh_league_after_fixture_resolution(
      v_resolution.league_id,
      new.matchday_id
    );
  end loop;

  return new;
end;
$$;

revoke all on function public.close_fixture_resolutions_after_final()
from public, anon, authenticated;

drop trigger if exists provider_fixture_close_political_scores
on public.provider_fixtures;

create trigger provider_fixture_close_political_scores
after update of status on public.provider_fixtures
for each row execute function
  public.close_fixture_resolutions_after_final();

select
  exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'athletes'
      and column_name = 'provider_team_id'
  ) as provider_team_ready,
  to_regclass(
    'public.league_fixture_resolutions'
  ) is not null as resolutions_ready,
  to_regclass(
    'public.league_fixture_resolution_events'
  ) is not null as resolution_audit_ready,
  to_regprocedure(
    'public.get_league_postponement_center(uuid)'
  ) is not null as postponement_center_ready,
  to_regprocedure(
    'public.apply_league_fixture_political_score(uuid,uuid,numeric,text)'
  ) is not null as political_score_ready,
  to_regprocedure(
    'public.revoke_league_fixture_political_score(uuid,uuid,text)'
  ) is not null as political_score_revocation_ready,
  pg_get_functiondef(
    'public.resolve_team_matchday_lineup(uuid,uuid)'::regprocedure
  ) ilike '%get_league_effective_player_score%'
    as lineup_engine_connected,
  pg_get_functiondef(
    'public.league_matchday_is_resolved(uuid,uuid)'::regprocedure
  ) ilike '%league_fixture_resolutions%'
    as matchday_resolution_ready,
  exists (
    select 1
    from pg_trigger
    where tgname = 'provider_fixture_close_political_scores'
      and not tgisinternal
  ) as provider_final_cleanup_ready,
  has_function_privilege(
    'authenticated',
    'public.get_league_postponement_center(uuid)',
    'EXECUTE'
  ) as member_read_access_ready,
  has_function_privilege(
    'authenticated',
    'public.apply_league_fixture_political_score(uuid,uuid,numeric,text)',
    'EXECUTE'
  ) as president_action_access_ready,
  not has_function_privilege(
    'anon',
    'public.apply_league_fixture_political_score(uuid,uuid,numeric,text)',
    'EXECUTE'
  ) as anonymous_action_blocked;
