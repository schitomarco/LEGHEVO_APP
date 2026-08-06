-- LEGHEVO · correzione puntuale dei risultati e storico revisioni
-- Eseguire nel SQL Editor di Supabase dopo 037.

alter table public.fantasy_fixtures
  add column if not exists result_revision integer not null default 0,
  add column if not exists correction_reason text,
  add column if not exists corrected_at timestamptz,
  add column if not exists corrected_by uuid;

alter table public.fantasy_fixtures
  drop constraint if exists fantasy_fixtures_result_revision_check;

alter table public.fantasy_fixtures
  add constraint fantasy_fixtures_result_revision_check
  check (result_revision >= 0);

alter table public.fantasy_fixtures
  drop constraint if exists fantasy_fixtures_correction_reason_check;

alter table public.fantasy_fixtures
  add constraint fantasy_fixtures_correction_reason_check
  check (
    correction_reason is null
    or char_length(trim(correction_reason)) between 10 and 240
  );

create table if not exists public.fantasy_fixture_result_revisions (
  id uuid primary key default gen_random_uuid(),
  league_id uuid not null
    references public.leagues(id) on delete cascade,
  matchday_id uuid not null
    references public.matchdays(id) on delete cascade,
  fixture_id uuid not null
    references public.fantasy_fixtures(id) on delete cascade,
  revision integer not null check (revision >= 0),
  action text not null check (action in ('officialized', 'reopened')),
  reason text,
  changed_by uuid references public.profiles(id) on delete set null,
  home_points numeric(7,2),
  away_points numeric(7,2),
  home_base_points numeric(7,2),
  away_base_points numeric(7,2),
  home_defense_modifier numeric(5,2) not null default 0,
  away_defense_modifier numeric(5,2) not null default 0,
  home_bonus_applied numeric(5,2) not null default 0,
  home_goal_margin_bonus smallint not null default 0,
  away_goal_margin_bonus smallint not null default 0,
  home_goals smallint,
  away_goals smallint,
  recorded_at timestamptz not null default now(),
  unique (fixture_id, revision, action)
);

create index if not exists fantasy_fixture_result_revisions_league_idx
  on public.fantasy_fixture_result_revisions (
    league_id,
    matchday_id,
    recorded_at desc
  );

alter table public.fantasy_fixture_result_revisions
  enable row level security;

drop policy if exists fantasy_fixture_result_revisions_read_members
on public.fantasy_fixture_result_revisions;

create policy fantasy_fixture_result_revisions_read_members
on public.fantasy_fixture_result_revisions
for select to authenticated
using (
  public.is_league_member(league_id)
  or public.is_league_admin(league_id)
);

revoke all on public.fantasy_fixture_result_revisions
from public, anon, authenticated;

grant select on public.fantasy_fixture_result_revisions
to authenticated;

create or replace function public.prepare_fantasy_result_revision()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.finalized_at is null
    and new.finalized_at is not null then
    new.result_revision := greatest(old.result_revision, 0) + 1;
  end if;

  return new;
end;
$$;

revoke all on function public.prepare_fantasy_result_revision()
from public, anon, authenticated;

drop trigger if exists prepare_fantasy_result_revision
on public.fantasy_fixtures;

create trigger prepare_fantasy_result_revision
before update of finalized_at on public.fantasy_fixtures
for each row
execute function public.prepare_fantasy_result_revision();

create or replace function public.record_fantasy_result_revision()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_action text;
  v_revision integer;
  v_reason text;
  v_changed_by uuid;
  v_snapshot public.fantasy_fixtures%rowtype;
begin
  if old.finalized_at is null
    and new.finalized_at is not null then
    v_action := 'officialized';
    v_revision := new.result_revision;
    v_reason := new.correction_reason;
    v_changed_by := coalesce(new.finalized_by, auth.uid());
    v_snapshot := new;
  elsif old.finalized_at is not null
    and new.finalized_at is null then
    v_action := 'reopened';
    v_revision := old.result_revision;
    v_reason := new.correction_reason;
    v_changed_by := coalesce(new.corrected_by, new.reopened_by, auth.uid());
    v_snapshot := old;
  else
    return new;
  end if;

  insert into public.fantasy_fixture_result_revisions (
    league_id,
    matchday_id,
    fixture_id,
    revision,
    action,
    reason,
    changed_by,
    home_points,
    away_points,
    home_base_points,
    away_base_points,
    home_defense_modifier,
    away_defense_modifier,
    home_bonus_applied,
    home_goal_margin_bonus,
    away_goal_margin_bonus,
    home_goals,
    away_goals
  )
  values (
    v_snapshot.league_id,
    v_snapshot.matchday_id,
    v_snapshot.id,
    v_revision,
    v_action,
    nullif(trim(v_reason), ''),
    v_changed_by,
    v_snapshot.home_points,
    v_snapshot.away_points,
    v_snapshot.home_base_points,
    v_snapshot.away_base_points,
    v_snapshot.home_defense_modifier,
    v_snapshot.away_defense_modifier,
    v_snapshot.home_bonus_applied,
    v_snapshot.home_goal_margin_bonus,
    v_snapshot.away_goal_margin_bonus,
    v_snapshot.home_goals,
    v_snapshot.away_goals
  )
  on conflict (fixture_id, revision, action) do nothing;

  return new;
end;
$$;

revoke all on function public.record_fantasy_result_revision()
from public, anon, authenticated;

drop trigger if exists record_fantasy_result_revision
on public.fantasy_fixtures;

create trigger record_fantasy_result_revision
after update of finalized_at on public.fantasy_fixtures
for each row
execute function public.record_fantasy_result_revision();

create or replace function public.reopen_league_fixture(
  p_league_id uuid,
  p_fixture_id uuid,
  p_reason text
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_league public.leagues%rowtype;
  v_fixture public.fantasy_fixtures%rowtype;
  v_matchday_number integer;
  v_home_team_name text;
  v_away_team_name text;
  v_member_user_id uuid;
  v_reason text := trim(coalesce(p_reason, ''));
  v_reopen_token uuid := gen_random_uuid();
begin
  if auth.uid() is null then
    raise exception 'Devi effettuare l''accesso.';
  end if;

  if char_length(v_reason) < 10
    or char_length(v_reason) > 240 then
    raise exception
      'La motivazione deve contenere da 10 a 240 caratteri.';
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
    raise exception 'Solo il Presidente può correggere un risultato.';
  end if;

  select fixture.*
  into v_fixture
  from public.fantasy_fixtures fixture
  where fixture.id = p_fixture_id
    and fixture.league_id = p_league_id
  for update;

  if not found then
    raise exception 'Partita non trovata nel calendario della lega.';
  end if;

  if v_fixture.finalized_at is null then
    raise exception 'Il risultato selezionato non è ufficiale.';
  end if;

  select
    matchday.number,
    home_team.name,
    away_team.name
  into
    v_matchday_number,
    v_home_team_name,
    v_away_team_name
  from public.matchdays matchday
  join public.fantasy_teams home_team
    on home_team.id = v_fixture.home_team_id
  join public.fantasy_teams away_team
    on away_team.id = v_fixture.away_team_id
  where matchday.id = v_fixture.matchday_id;

  update public.fantasy_fixtures
  set
    finalized_at = null,
    finalized_by = null,
    reopened_at = now(),
    reopened_by = auth.uid(),
    correction_reason = v_reason,
    corrected_at = now(),
    corrected_by = auth.uid()
  where id = p_fixture_id;

  perform public.refresh_matchday_results_internal(v_fixture.matchday_id);

  for v_member_user_id in
    select member.user_id
    from public.league_members member
    where member.league_id = p_league_id
  loop
    perform public.create_user_notification(
      v_member_user_id,
      p_league_id,
      'result',
      'Risultato in correzione · Giornata ' || v_matchday_number,
      v_home_team_name
        || '–'
        || v_away_team_name
        || ' è stato riaperto. Motivo: '
        || v_reason,
      'standings',
      jsonb_build_object(
        'event', 'fixture_reopened',
        'fixture_id', p_fixture_id,
        'matchday_id', v_fixture.matchday_id,
        'matchday_number', v_matchday_number,
        'reason', v_reason
      ),
      'result:fixture-reopened:'
        || p_fixture_id::text
        || ':'
        || v_reopen_token::text
        || ':'
        || v_member_user_id::text
    );
  end loop;

  return 1;
end;
$$;

revoke all on function public.reopen_league_fixture(
  uuid,
  uuid,
  text
) from public, anon, authenticated;

grant execute on function public.reopen_league_fixture(
  uuid,
  uuid,
  text
) to authenticated;

create or replace function public.notify_final_fantasy_result()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_home public.fantasy_teams%rowtype;
  v_away public.fantasy_teams%rowtype;
  v_matchday_number integer;
  v_result text;
begin
  if new.finalized_at is null or old.finalized_at is not null then
    return new;
  end if;

  select team.* into v_home
  from public.fantasy_teams team
  where team.id = new.home_team_id;

  select team.* into v_away
  from public.fantasy_teams team
  where team.id = new.away_team_id;

  select matchday.number
  into v_matchday_number
  from public.matchdays matchday
  where matchday.id = new.matchday_id;

  v_result := v_home.name || ' ' || coalesce(new.home_goals, 0)
    || '–' || coalesce(new.away_goals, 0) || ' ' || v_away.name;

  perform public.create_user_notification(
    v_home.manager_id,
    new.league_id,
    'result',
    'Risultato ufficiale · Giornata ' || v_matchday_number,
    v_result || '. Classifica aggiornata.',
    'standings',
    jsonb_build_object(
      'fixture_id', new.id,
      'matchday_id', new.matchday_id,
      'revision', new.result_revision
    ),
    'result:'
      || new.id::text
      || ':r'
      || new.result_revision::text
      || ':'
      || v_home.manager_id::text
  );

  perform public.create_user_notification(
    v_away.manager_id,
    new.league_id,
    'result',
    'Risultato ufficiale · Giornata ' || v_matchday_number,
    v_result || '. Classifica aggiornata.',
    'standings',
    jsonb_build_object(
      'fixture_id', new.id,
      'matchday_id', new.matchday_id,
      'revision', new.result_revision
    ),
    'result:'
      || new.id::text
      || ':r'
      || new.result_revision::text
      || ':'
      || v_away.manager_id::text
  );

  return new;
end;
$$;

revoke all on function public.notify_final_fantasy_result()
from public, anon, authenticated;

create or replace function public.get_league_results_center_v5(
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
  v_is_owner boolean := false;
  v_competition_started_at timestamptz;
begin
  v_center := public.get_league_results_center_v4(p_league_id);

  select
    league.owner_id = auth.uid(),
    league.competition_started_at
  into
    v_is_owner,
    v_competition_started_at
  from public.leagues league
  where league.id = p_league_id;

  select coalesce(
    jsonb_agg(
      matchday.item
        || jsonb_build_object(
          'canFinalize',
            v_is_owner
            and v_competition_started_at is not null
            and now() >= coalesce(
              real_matchday.ends_at,
              real_matchday.starts_at + interval '4 days'
            )
            and (matchday.item ->> 'readyCount')::integer
              = (matchday.item ->> 'fixtureCount')::integer
            and (matchday.item ->> 'officialCount')::integer
              < (matchday.item ->> 'fixtureCount')::integer,
          'canReopen',
            false,
          'fixtures',
            coalesce(
              (
                select jsonb_agg(
                  fixture.item
                    || jsonb_build_object(
                      'canCorrect',
                        v_is_owner
                        and real_fixture.finalized_at is not null,
                      'revision',
                        real_fixture.result_revision,
                      'correctionReason',
                        real_fixture.correction_reason,
                      'correctedAt',
                        real_fixture.corrected_at
                    )
                  order by fixture.position
                )
                from jsonb_array_elements(
                  matchday.item -> 'fixtures'
                ) with ordinality as fixture(item, position)
                join public.fantasy_fixtures real_fixture
                  on real_fixture.id =
                    (fixture.item ->> 'id')::uuid
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
  ) with ordinality as matchday(item, position)
  join public.matchdays real_matchday
    on real_matchday.id = (matchday.item ->> 'id')::uuid;

  return jsonb_set(
    v_center,
    '{matchdays}',
    v_matchdays,
    true
  );
end;
$$;

revoke all on function public.get_league_results_center_v5(uuid)
from public, anon, authenticated;

grant execute on function public.get_league_results_center_v5(uuid)
to authenticated;

select
  (
    select count(*) = 4
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'fantasy_fixtures'
      and column_name in (
        'result_revision',
        'correction_reason',
        'corrected_at',
        'corrected_by'
      )
  ) as correction_columns_ready,
  to_regclass(
    'public.fantasy_fixture_result_revisions'
  ) is not null as revision_history_ready,
  (
    select relrowsecurity
    from pg_class
    where oid =
      'public.fantasy_fixture_result_revisions'::regclass
  ) as revision_history_rls_ready,
  has_table_privilege(
    'authenticated',
    'public.fantasy_fixture_result_revisions',
    'SELECT'
  ) as revision_history_read_ready,
  not has_table_privilege(
    'authenticated',
    'public.fantasy_fixture_result_revisions',
    'INSERT'
  ) as revision_history_write_blocked,
  exists (
    select 1
    from pg_trigger
    where tgrelid = 'public.fantasy_fixtures'::regclass
      and tgname = 'record_fantasy_result_revision'
      and not tgisinternal
  ) as revision_trigger_ready,
  to_regprocedure(
    'public.reopen_league_fixture(uuid,uuid,text)'
  ) is not null as fixture_reopen_ready,
  has_function_privilege(
    'authenticated',
    'public.reopen_league_fixture(uuid,uuid,text)',
    'EXECUTE'
  ) as fixture_reopen_access_ready,
  not has_function_privilege(
    'anon',
    'public.reopen_league_fixture(uuid,uuid,text)',
    'EXECUTE'
  ) as anonymous_reopen_blocked,
  to_regprocedure(
    'public.get_league_results_center_v5(uuid)'
  ) is not null as results_center_v5_ready,
  has_function_privilege(
    'authenticated',
    'public.get_league_results_center_v5(uuid)',
    'EXECUTE'
  ) as results_center_v5_access_ready,
  pg_get_functiondef(
    'public.reopen_league_fixture(uuid,uuid,text)'::regprocedure
  ) ilike '%La motivazione deve contenere da 10 a 240 caratteri%'
    as correction_reason_validation_ready;
