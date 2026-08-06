-- LEGHEVO · regolamento condiviso e revisioni tracciate
-- Eseguire nel SQL Editor di Supabase dopo 055.
--
-- Lo script rende il regolamento leggibile a tutti i membri e protegge le
-- modifiche future con autore, motivazione e fotografia prima/dopo. Non cambia
-- alcuna regola esistente e non crea revisioni retroattive.

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
      'market',
      'support',
      'leagueRulebook'
    )
  );

create table if not exists public.league_rule_revisions (
  id uuid primary key default gen_random_uuid(),
  league_id uuid not null
    references public.leagues(id) on delete cascade,
  revision integer not null check (revision > 0),
  changed_by uuid references public.profiles(id) on delete set null,
  reason text not null
    check (char_length(trim(reason)) between 8 and 240),
  before_rules jsonb not null,
  after_rules jsonb not null,
  changed_keys text[] not null
    check (cardinality(changed_keys) > 0),
  changed_at timestamptz not null default now(),
  unique (league_id, revision)
);

create index if not exists league_rule_revisions_timeline_idx
  on public.league_rule_revisions (league_id, revision desc);

alter table public.league_rule_revisions enable row level security;

drop policy if exists league_rule_revisions_read_members
on public.league_rule_revisions;

create policy league_rule_revisions_read_members
on public.league_rule_revisions for select to authenticated
using (
  exists (
    select 1
    from public.league_members member
    where member.league_id = league_rule_revisions.league_id
      and member.user_id = auth.uid()
  )
);

revoke all on public.league_rule_revisions from anon, authenticated;
grant select on public.league_rule_revisions to authenticated;

do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'league_rule_revisions'
  ) then
    alter publication supabase_realtime
      add table public.league_rule_revisions;
  end if;
end;
$$;

create or replace function public.get_league_rulebook(
  p_league_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_league public.leagues%rowtype;
  v_member public.league_members%rowtype;
  v_revision_count integer := 0;
  v_revisions jsonb := '[]'::jsonb;
begin
  if v_user_id is null then
    raise exception 'Devi effettuare l''accesso.';
  end if;

  select league.*
  into v_league
  from public.leagues league
  where league.id = p_league_id;

  if not found then
    raise exception 'Lega non trovata.';
  end if;

  select member.*
  into v_member
  from public.league_members member
  where member.league_id = p_league_id
    and member.user_id = v_user_id;

  if not found then
    raise exception 'Non fai parte di questa lega.';
  end if;

  select count(*)::integer
  into v_revision_count
  from public.league_rule_revisions revision
  where revision.league_id = p_league_id;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', timeline.id,
        'revision', timeline.revision,
        'reason', timeline.reason,
        'changedKeys', to_jsonb(timeline.changed_keys),
        'changedAt', timeline.changed_at,
        'changedBy', coalesce(profile.display_name, 'Account eliminato')
      )
      order by timeline.revision desc
    ),
    '[]'::jsonb
  )
  into v_revisions
  from (
    select revision.*
    from public.league_rule_revisions revision
    where revision.league_id = p_league_id
    order by revision.revision desc
    limit 20
  ) timeline
  left join public.profiles profile
    on profile.id = timeline.changed_by;

  return jsonb_build_object(
    'leagueId', v_league.id,
    'leagueName', v_league.name,
    'mode', v_league.mode,
    'status', v_league.status,
    'season', v_league.calendar_season,
    'teamLimit', v_league.team_limit,
    'startingCredits', v_league.starting_credits,
    'rosterSize', v_league.roster_size,
    'isDirector', v_member.role = 'admin',
    'currentRevision', v_revision_count,
    'updatedAt', v_league.updated_at,
    'rules', coalesce(v_league.scoring_rules, '{}'::jsonb),
    'revisions', v_revisions
  );
end;
$$;

do $$
declare
  v_function record;
begin
  for v_function in
    select
      procedure.proname,
      pg_get_function_identity_arguments(procedure.oid) as arguments
    from pg_proc procedure
    join pg_namespace namespace
      on namespace.oid = procedure.pronamespace
    where namespace.nspname = 'public'
      and (
        procedure.proname = 'update_league_settings'
        or procedure.proname like 'update_league_settings_v%'
      )
  loop
    execute format(
      'revoke execute on function public.%I(%s) from public, anon, authenticated',
      v_function.proname,
      v_function.arguments
    );
  end loop;
end;
$$;

create or replace function public.update_league_settings_v9(
  p_league_id uuid,
  p_market_open boolean,
  p_market_min_price integer,
  p_release_refund_percent integer,
  p_goal_threshold numeric,
  p_goal_step numeric,
  p_home_bonus numeric,
  p_bonus_goal numeric,
  p_bonus_assist numeric,
  p_bonus_penalty_saved numeric,
  p_malus_yellow_card numeric,
  p_malus_red_card numeric,
  p_malus_penalty_missed numeric,
  p_malus_goal_conceded numeric,
  p_roster_goalkeepers integer,
  p_roster_defenders integer,
  p_roster_midfielders integer,
  p_roster_attackers integer,
  p_max_substitutions integer,
  p_defense_modifier_enabled boolean,
  p_defense_modifier_min_defenders integer,
  p_goal_margin_enabled boolean,
  p_goal_margin numeric,
  p_goal_bands_enabled boolean,
  p_goal_bands numeric[],
  p_standings_tiebreaker text,
  p_change_reason text
)
returns public.leagues
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_reason text := trim(coalesce(p_change_reason, ''));
  v_before jsonb;
  v_after public.leagues%rowtype;
  v_changed_keys text[];
  v_revision integer;
  v_revision_id uuid;
  v_member record;
begin
  if v_user_id is null then
    raise exception 'Devi effettuare l''accesso.';
  end if;

  if char_length(v_reason) < 8 or char_length(v_reason) > 240 then
    raise exception
      'La motivazione deve contenere tra 8 e 240 caratteri.';
  end if;

  select coalesce(league.scoring_rules, '{}'::jsonb)
  into v_before
  from public.leagues league
  where league.id = p_league_id
  for update;

  if not found then
    raise exception 'Lega non trovata.';
  end if;

  select updated.*
  into v_after
  from public.update_league_settings_v8(
    p_league_id,
    p_market_open,
    p_market_min_price,
    p_release_refund_percent,
    p_goal_threshold,
    p_goal_step,
    p_home_bonus,
    p_bonus_goal,
    p_bonus_assist,
    p_bonus_penalty_saved,
    p_malus_yellow_card,
    p_malus_red_card,
    p_malus_penalty_missed,
    p_malus_goal_conceded,
    p_roster_goalkeepers,
    p_roster_defenders,
    p_roster_midfielders,
    p_roster_attackers,
    p_max_substitutions,
    p_defense_modifier_enabled,
    p_defense_modifier_min_defenders,
    p_goal_margin_enabled,
    p_goal_margin,
    p_goal_bands_enabled,
    p_goal_bands,
    p_standings_tiebreaker
  ) as updated;

  select coalesce(
    array_agg(keys.key order by keys.key),
    array[]::text[]
  )
  into v_changed_keys
  from (
    select jsonb_object_keys(v_before) as key
    union
    select jsonb_object_keys(v_after.scoring_rules) as key
  ) keys
  where v_before -> keys.key
    is distinct from v_after.scoring_rules -> keys.key;

  if cardinality(v_changed_keys) = 0 then
    raise exception 'Nessuna regola è cambiata.';
  end if;

  select coalesce(max(revision.revision), 0) + 1
  into v_revision
  from public.league_rule_revisions revision
  where revision.league_id = p_league_id;

  insert into public.league_rule_revisions (
    league_id,
    revision,
    changed_by,
    reason,
    before_rules,
    after_rules,
    changed_keys
  )
  values (
    p_league_id,
    v_revision,
    v_user_id,
    v_reason,
    v_before,
    v_after.scoring_rules,
    v_changed_keys
  )
  returning id into v_revision_id;

  for v_member in
    select member.user_id
    from public.league_members member
    where member.league_id = p_league_id
      and member.user_id <> v_user_id
  loop
    perform public.create_user_notification(
      v_member.user_id,
      p_league_id,
      'league',
      'Regolamento aggiornato',
      left(v_reason, 280),
      'leagueRulebook',
      jsonb_build_object(
        'ruleRevisionId', v_revision_id,
        'ruleRevision', v_revision,
        'changedKeys', to_jsonb(v_changed_keys)
      ),
      'rulebook:' || p_league_id::text || ':' || v_revision::text
    );
  end loop;

  return v_after;
end;
$$;

create or replace function public.export_my_personal_data_v5()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_export jsonb;
  v_revisions jsonb;
begin
  if auth.uid() is null then
    raise exception 'Devi effettuare l''accesso.';
  end if;

  v_export := public.export_my_personal_data_v4();

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', revision.id,
        'leagueId', revision.league_id,
        'revision', revision.revision,
        'reason', revision.reason,
        'changedKeys', to_jsonb(revision.changed_keys),
        'changedAt', revision.changed_at
      )
      order by revision.changed_at desc
    ),
    '[]'::jsonb
  )
  into v_revisions
  from public.league_rule_revisions revision
  where revision.changed_by = auth.uid();

  return v_export || jsonb_build_object(
    'exportVersion', 5,
    'leagueRuleRevisionsAuthored', v_revisions
  );
end;
$$;

revoke all on function public.get_league_rulebook(uuid)
from public, anon;
revoke all on function public.update_league_settings_v9(
  uuid,
  boolean,
  integer,
  integer,
  numeric,
  numeric,
  numeric,
  numeric,
  numeric,
  numeric,
  numeric,
  numeric,
  numeric,
  numeric,
  integer,
  integer,
  integer,
  integer,
  integer,
  boolean,
  integer,
  boolean,
  numeric,
  boolean,
  numeric[],
  text,
  text
) from public, anon;
revoke all on function public.export_my_personal_data_v5()
from public, anon;

grant execute on function public.get_league_rulebook(uuid)
to authenticated;
grant execute on function public.update_league_settings_v9(
  uuid,
  boolean,
  integer,
  integer,
  numeric,
  numeric,
  numeric,
  numeric,
  numeric,
  numeric,
  numeric,
  numeric,
  numeric,
  numeric,
  integer,
  integer,
  integer,
  integer,
  integer,
  boolean,
  integer,
  boolean,
  numeric,
  boolean,
  numeric[],
  text,
  text
) to authenticated;
grant execute on function public.export_my_personal_data_v5()
to authenticated;

select
  to_regclass('public.league_rule_revisions') is not null
    as rule_revisions_ready,
  to_regprocedure(
    'public.get_league_rulebook(uuid)'
  ) is not null as shared_rulebook_ready,
  to_regprocedure(
    'public.update_league_settings_v9(uuid,boolean,integer,integer,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,integer,integer,integer,integer,integer,boolean,integer,boolean,numeric,boolean,numeric[],text,text)'
  ) is not null as settings_v9_ready,
  to_regprocedure(
    'public.export_my_personal_data_v5()'
  ) is not null as personal_export_v5_ready,
  has_function_privilege(
    'authenticated',
    'public.get_league_rulebook(uuid)',
    'EXECUTE'
  ) as rulebook_member_access_ready,
  not has_function_privilege(
    'authenticated',
    'public.update_league_settings_v8(uuid,boolean,integer,integer,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,integer,integer,integer,integer,integer,boolean,integer,boolean,numeric,boolean,numeric[],text)',
    'EXECUTE'
  ) as legacy_settings_blocked,
  not has_table_privilege(
    'authenticated',
    'public.league_rule_revisions',
    'INSERT'
  ) as revision_insert_protected,
  exists (
    select 1
    from pg_policies policy
    where policy.schemaname = 'public'
      and policy.tablename = 'league_rule_revisions'
      and policy.policyname = 'league_rule_revisions_read_members'
  ) as revision_membership_policy_ready,
  exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'league_rule_revisions'
  ) as revision_realtime_ready,
  exists (
    select 1
    from pg_constraint constraint_info
    where constraint_info.conrelid = 'public.user_notifications'::regclass
      and constraint_info.conname =
        'user_notifications_action_screen_check'
      and pg_get_constraintdef(constraint_info.oid)
        ilike '%leagueRulebook%'
  ) as rulebook_notification_route_ready,
  pg_get_functiondef(
    'public.update_league_settings_v9(uuid,boolean,integer,integer,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,integer,integer,integer,integer,integer,boolean,integer,boolean,numeric,boolean,numeric[],text,text)'::regprocedure
  ) ilike '%La motivazione deve contenere%'
    as change_reason_validation_ready,
  pg_get_functiondef(
    'public.get_league_rulebook(uuid)'::regprocedure
  ) ilike '%Non fai parte di questa lega%'
    as rulebook_membership_guard_ready;
