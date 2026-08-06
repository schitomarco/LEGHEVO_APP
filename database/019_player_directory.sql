-- LEGHEVO · archivio calciatori e statistiche
-- Eseguire nel SQL Editor di Supabase dopo 018.

create or replace function public.get_league_player_directory(
  p_league_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_league public.leagues%rowtype;
  v_result jsonb;
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

  if not public.is_league_member(v_league.id) then
    raise exception 'Non fai parte di questa lega.';
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', athlete.id,
        'name', trim(
          coalesce(athlete.first_name || ' ', '') || athlete.last_name
        ),
        'clubName', athlete.club_name,
        'shirtNumber', athlete.shirt_number,
        'role', coalesce(role_data.role_codes, '—'),
        'teamId', ownership.team_id,
        'teamName', ownership.team_name,
        'purchasePrice', ownership.purchase_price,
        'appearances', coalesce(stat_data.appearances, 0),
        'averageRating', stat_data.average_rating,
        'averageFantasyScore', stat_data.average_fantasy_score,
        'goals', coalesce(stat_data.goals, 0),
        'assists', coalesce(stat_data.assists, 0),
        'yellowCards', coalesce(stat_data.yellow_cards, 0),
        'redCards', coalesce(stat_data.red_cards, 0),
        'lastScores', coalesce(recent_data.last_scores, '[]'::jsonb)
      )
      order by athlete.last_name, athlete.first_name
    ),
    '[]'::jsonb
  )
  into v_result
  from public.athletes athlete
  left join lateral (
    select string_agg(role.role_code, '/' order by role.role_code)
      as role_codes
    from public.athlete_roles role
    where role.athlete_id = athlete.id
      and role.mode = v_league.mode
  ) role_data on true
  left join lateral (
    select
      team.id as team_id,
      team.name as team_name,
      roster.purchase_price
    from public.roster_entries roster
    join public.fantasy_teams team
      on team.id = roster.fantasy_team_id
    where roster.league_id = v_league.id
      and roster.athlete_id = athlete.id
      and roster.released_at is null
    limit 1
  ) ownership on true
  left join lateral (
    select
      count(*) filter (
        where score.provider_rating is not null
      )::integer as appearances,
      round(avg(score.provider_rating), 2) as average_rating,
      round(
        avg(
          public.calculate_league_fantasy_score(
            score.provider_rating,
            score.fantasy_score,
            score.raw_statistics,
            v_league.scoring_rules
          )
        ),
        2
      ) as average_fantasy_score,
      coalesce(
        sum(
          coalesce(
            (score.raw_statistics #>> '{goals,total}')::integer,
            (score.bonuses ->> 'goals')::integer,
            0
          )
        ),
        0
      )::integer as goals,
      coalesce(
        sum(
          coalesce(
            (score.raw_statistics #>> '{goals,assists}')::integer,
            (score.bonuses ->> 'assists')::integer,
            0
          )
        ),
        0
      )::integer as assists,
      coalesce(
        sum(
          coalesce(
            (score.raw_statistics #>> '{cards,yellow}')::integer,
            (score.maluses ->> 'yellow_cards')::integer,
            0
          )
        ),
        0
      )::integer as yellow_cards,
      coalesce(
        sum(
          coalesce(
            (score.raw_statistics #>> '{cards,red}')::integer,
            (score.maluses ->> 'red_cards')::integer,
            0
          )
        ),
        0
      )::integer as red_cards
    from public.player_match_scores score
    where score.athlete_id = athlete.id
  ) stat_data on true
  left join lateral (
    select jsonb_agg(
      recent.fantasy_score order by recent.updated_at desc
    ) as last_scores
    from (
      select
        round(
          public.calculate_league_fantasy_score(
            score.provider_rating,
            score.fantasy_score,
            score.raw_statistics,
            v_league.scoring_rules
          ),
          2
        ) as fantasy_score,
        score.updated_at
      from public.player_match_scores score
      where score.athlete_id = athlete.id
        and score.provider_rating is not null
      order by score.updated_at desc
      limit 5
    ) recent
  ) recent_data on true
  where athlete.active;

  return v_result;
end;
$$;

revoke all on function public.get_league_player_directory(uuid)
from public, anon;

grant execute on function public.get_league_player_directory(uuid)
to authenticated;

select
  to_regprocedure(
    'public.get_league_player_directory(uuid)'
  ) is not null as player_directory_ready,
  has_function_privilege(
    'authenticated',
    'public.get_league_player_directory(uuid)',
    'EXECUTE'
  ) as player_directory_access_ready;
