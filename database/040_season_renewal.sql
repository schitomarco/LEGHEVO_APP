-- LEGHEVO · rinnovo della lega e continuità tra stagioni
-- Eseguire nel SQL Editor di Supabase dopo 039.

alter table public.leagues
  add column if not exists previous_league_id uuid;

alter table public.leagues
  drop constraint if exists leagues_previous_league_id_fkey;

alter table public.leagues
  add constraint leagues_previous_league_id_fkey
  foreign key (previous_league_id)
  references public.leagues(id)
  on delete set null;

create unique index if not exists leagues_previous_league_unique_idx
  on public.leagues (previous_league_id)
  where previous_league_id is not null;

create table if not exists public.league_season_rollovers (
  source_league_id uuid primary key
    references public.leagues(id) on delete cascade,
  renewed_league_id uuid not null unique
    references public.leagues(id) on delete restrict,
  source_season text not null check (source_season ~ '^[0-9]{4}$'),
  renewed_season text not null check (renewed_season ~ '^[0-9]{4}$'),
  copied_member_count integer not null check (copied_member_count > 0),
  copied_team_count integer not null check (copied_team_count > 0),
  renewed_at timestamptz not null default now(),
  renewed_by uuid references public.profiles(id) on delete set null,
  check (source_league_id <> renewed_league_id),
  check (renewed_season::integer > source_season::integer)
);

alter table public.league_season_rollovers
  enable row level security;

drop policy if exists league_season_rollovers_read_members
on public.league_season_rollovers;

create policy league_season_rollovers_read_members
on public.league_season_rollovers
for select to authenticated
using (
  public.is_league_member(source_league_id)
  or public.is_league_admin(source_league_id)
  or public.is_league_member(renewed_league_id)
  or public.is_league_admin(renewed_league_id)
);

revoke all on public.league_season_rollovers
from public, anon, authenticated;

grant select on public.league_season_rollovers
to authenticated;

create or replace function public.renew_league_season(
  p_league_id uuid,
  p_next_season text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_league public.leagues%rowtype;
  v_existing public.league_season_rollovers%rowtype;
  v_summary public.league_season_summaries%rowtype;
  v_new_league_id uuid;
  v_invite_code text;
  v_next_season text := trim(coalesce(p_next_season, ''));
  v_member_count integer := 0;
  v_team_count integer := 0;
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
    raise exception 'Solo il Presidente può preparare la nuova stagione.';
  end if;

  select rollover.*
  into v_existing
  from public.league_season_rollovers rollover
  where rollover.source_league_id = p_league_id;

  if found then
    if v_existing.renewed_season <> v_next_season then
      raise exception
        'La nuova stagione è già stata preparata per il %.',
        v_existing.renewed_season;
    end if;

    return v_existing.renewed_league_id;
  end if;

  if v_league.status <> 'completed'
    or v_league.competition_completed_at is null then
    raise exception
      'Prima devi chiudere e ufficializzare la stagione corrente.';
  end if;

  select summary.*
  into v_summary
  from public.league_season_summaries summary
  where summary.league_id = p_league_id;

  if not found then
    raise exception 'L''albo della stagione corrente non è disponibile.';
  end if;

  if v_next_season !~ '^[0-9]{4}$'
    or v_next_season::integer < 2000
    or v_next_season::integer > 2100 then
    raise exception
      'La nuova stagione deve avere quattro cifre tra 2000 e 2100.';
  end if;

  if v_summary.season !~ '^[0-9]{4}$'
    or v_next_season::integer <= v_summary.season::integer then
    raise exception
      'La nuova stagione deve essere successiva al %.',
      v_summary.season;
  end if;

  select count(*)::integer
  into v_member_count
  from public.league_members member
  where member.league_id = p_league_id;

  select count(*)::integer
  into v_team_count
  from public.fantasy_teams team
  where team.league_id = p_league_id;

  if v_member_count = 0 or v_team_count <> v_member_count then
    raise exception
      'Partecipanti e squadre della stagione conclusa non sono allineati.';
  end if;

  loop
    v_invite_code :=
      upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 10));

    exit when not exists (
      select 1
      from public.leagues league
      where league.invite_code = v_invite_code
    );
  end loop;

  insert into public.leagues (
    owner_id,
    name,
    invite_code,
    mode,
    status,
    team_limit,
    starting_credits,
    roster_size,
    scoring_rules,
    invites_open,
    calendar_season,
    previous_league_id
  )
  values (
    v_league.owner_id,
    v_league.name,
    v_invite_code,
    v_league.mode,
    'draft',
    v_league.team_limit,
    v_league.starting_credits,
    v_league.roster_size,
    (
      coalesce(v_league.scoring_rules, '{}'::jsonb)
        - 'market_open'
    ) || jsonb_build_object('market_open', false),
    false,
    v_next_season,
    p_league_id
  )
  returning id into v_new_league_id;

  insert into public.league_members (
    league_id,
    user_id,
    role,
    joined_at
  )
  select
    v_new_league_id,
    member.user_id,
    member.role,
    now()
  from public.league_members member
  where member.league_id = p_league_id;

  insert into public.fantasy_teams (
    league_id,
    manager_id,
    name,
    crest_url,
    credits_remaining
  )
  select
    v_new_league_id,
    team.manager_id,
    team.name,
    team.crest_url,
    v_league.starting_credits
  from public.fantasy_teams team
  where team.league_id = p_league_id;

  insert into public.league_season_rollovers (
    source_league_id,
    renewed_league_id,
    source_season,
    renewed_season,
    copied_member_count,
    copied_team_count,
    renewed_at,
    renewed_by
  )
  values (
    p_league_id,
    v_new_league_id,
    v_summary.season,
    v_next_season,
    v_member_count,
    v_team_count,
    now(),
    auth.uid()
  );

  update public.leagues
  set
    status = 'archived',
    updated_at = now()
  where id = p_league_id;

  for v_member_user_id in
    select member.user_id
    from public.league_members member
    where member.league_id = v_new_league_id
  loop
    perform public.create_user_notification(
      v_member_user_id,
      v_new_league_id,
      'league',
      'Nuova stagione pronta',
      v_league.name
        || ' riparte nel '
        || v_next_season
        || '. Squadra e regolamento sono già nello spogliatoio.',
      'league',
      jsonb_build_object(
        'event', 'season_renewed',
        'source_league_id', p_league_id,
        'renewed_league_id', v_new_league_id,
        'source_season', v_summary.season,
        'renewed_season', v_next_season
      ),
      'season:renewed:'
        || p_league_id::text
        || ':'
        || v_member_user_id::text
    );
  end loop;

  return v_new_league_id;
end;
$$;

create or replace function public.get_league_season_state_v2(
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
  v_league public.leagues%rowtype;
  v_rollover public.league_season_rollovers%rowtype;
  v_previous_rollover public.league_season_rollovers%rowtype;
  v_inferred_next_season text;
begin
  v_state := public.get_league_season_state(p_league_id);

  select league.*
  into v_league
  from public.leagues league
  where league.id = p_league_id;

  if not found then
    raise exception 'Lega non trovata.';
  end if;

  select rollover.*
  into v_rollover
  from public.league_season_rollovers rollover
  where rollover.source_league_id = p_league_id;

  select rollover.*
  into v_previous_rollover
  from public.league_season_rollovers rollover
  where rollover.renewed_league_id = p_league_id;

  if v_rollover.source_league_id is null
    and v_league.status = 'completed'
    and (v_state ->> 'season') ~ '^[0-9]{4}$' then
    v_inferred_next_season :=
      ((v_state ->> 'season')::integer + 1)::text;
  end if;

  return v_state || jsonb_build_object(
    'previousLeagueId', v_league.previous_league_id,
    'previousSeason', v_previous_rollover.source_season,
    'nextLeagueId', v_rollover.renewed_league_id,
    'nextSeason',
      coalesce(v_rollover.renewed_season, v_inferred_next_season),
    'renewedAt', v_rollover.renewed_at,
    'renewalCopiedMemberCount', v_rollover.copied_member_count,
    'canRenew',
      v_league.owner_id = auth.uid()
      and v_league.status = 'completed'
      and v_league.competition_completed_at is not null
      and v_rollover.source_league_id is null
  );
end;
$$;

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
      || public.get_league_season_state_v2(p_league_id)
$$;

revoke all on function public.renew_league_season(uuid, text)
from public, anon, authenticated;

revoke all on function public.get_league_season_state_v2(uuid)
from public, anon, authenticated;

revoke all on function public.get_league_management_state_v3(uuid)
from public, anon, authenticated;

grant execute on function public.renew_league_season(uuid, text)
to authenticated;

grant execute on function public.get_league_season_state_v2(uuid)
to authenticated;

grant execute on function public.get_league_management_state_v3(uuid)
to authenticated;

do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'league_season_rollovers'
  ) then
    alter publication supabase_realtime
      add table public.league_season_rollovers;
  end if;
end;
$$;

select
  exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'leagues'
      and column_name = 'previous_league_id'
  ) as previous_league_column_ready,
  to_regclass(
    'public.leagues_previous_league_unique_idx'
  ) is not null as renewal_uniqueness_ready,
  to_regclass(
    'public.league_season_rollovers'
  ) is not null as season_rollover_ready,
  (
    select relrowsecurity
    from pg_class
    where oid = 'public.league_season_rollovers'::regclass
  ) as season_rollover_rls_ready,
  has_table_privilege(
    'authenticated',
    'public.league_season_rollovers',
    'SELECT'
  ) as season_rollover_read_ready,
  not has_table_privilege(
    'authenticated',
    'public.league_season_rollovers',
    'INSERT'
  ) as season_rollover_write_blocked,
  to_regprocedure(
    'public.renew_league_season(uuid,text)'
  ) is not null as season_renewal_ready,
  has_function_privilege(
    'authenticated',
    'public.renew_league_season(uuid,text)',
    'EXECUTE'
  ) as season_renewal_access_ready,
  not has_function_privilege(
    'anon',
    'public.renew_league_season(uuid,text)',
    'EXECUTE'
  ) as anonymous_renewal_blocked,
  to_regprocedure(
    'public.get_league_season_state_v2(uuid)'
  ) is not null as season_state_v2_ready,
  to_regprocedure(
    'public.get_league_management_state_v3(uuid)'
  ) is not null as management_v3_ready,
  has_function_privilege(
    'authenticated',
    'public.get_league_management_state_v3(uuid)',
    'EXECUTE'
  ) as management_v3_access_ready;
