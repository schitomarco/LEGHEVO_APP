-- LEGHEVO · privacy, consensi e diritti dell'utente
-- Eseguire nel SQL Editor di Supabase dopo 021.
--
-- Le versioni 2026.07-prototype identificano documenti tecnici da sottoporre
-- a revisione legale. Quando i testi definitivi cambiano, aggiornare sia questo
-- file sia src/legalDocuments.ts e richiedere una nuova presa visione.

create table if not exists public.user_privacy_preferences (
  user_id uuid primary key references auth.users(id) on delete cascade,
  privacy_policy_version text not null,
  privacy_acknowledged_at timestamptz not null,
  terms_version text not null,
  terms_accepted_at timestamptz not null,
  marketing_consent boolean not null default false,
  marketing_updated_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.privacy_consent_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  purpose text not null check (
    purpose in ('privacy_notice', 'terms', 'marketing')
  ),
  granted boolean not null,
  document_version text not null,
  source text not null default 'mobile_app',
  occurred_at timestamptz not null default now()
);

create index if not exists privacy_consent_events_user_date_idx
  on public.privacy_consent_events (user_id, occurred_at desc);

alter table public.user_privacy_preferences enable row level security;
alter table public.privacy_consent_events enable row level security;

drop policy if exists privacy_preferences_read_own
on public.user_privacy_preferences;

create policy privacy_preferences_read_own
on public.user_privacy_preferences for select to authenticated
using (user_id = auth.uid());

drop policy if exists privacy_events_read_own
on public.privacy_consent_events;

create policy privacy_events_read_own
on public.privacy_consent_events for select to authenticated
using (user_id = auth.uid());

revoke all on public.user_privacy_preferences from anon, authenticated;
revoke all on public.privacy_consent_events from anon, authenticated;
grant select on public.user_privacy_preferences to authenticated;
grant select on public.privacy_consent_events to authenticated;

create or replace function public.save_my_privacy_preferences(
  p_privacy_policy_version text,
  p_terms_version text,
  p_marketing_consent boolean
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_now timestamptz := now();
  v_previous public.user_privacy_preferences%rowtype;
  v_result public.user_privacy_preferences%rowtype;
begin
  if v_user_id is null then
    raise exception 'Devi effettuare l''accesso.';
  end if;

  if trim(coalesce(p_privacy_policy_version, ''))
      <> '2026.07-prototype'
    or trim(coalesce(p_terms_version, ''))
      <> '2026.07-prototype' then
    raise exception 'Versione dei documenti non valida.';
  end if;

  select preferences.*
  into v_previous
  from public.user_privacy_preferences preferences
  where preferences.user_id = v_user_id
  for update;

  if v_previous.user_id is null
    or v_previous.privacy_policy_version
      is distinct from p_privacy_policy_version then
    insert into public.privacy_consent_events (
      user_id,
      purpose,
      granted,
      document_version,
      source,
      occurred_at
    )
    values (
      v_user_id,
      'privacy_notice',
      true,
      p_privacy_policy_version,
      'privacy_center',
      v_now
    );
  end if;

  if v_previous.user_id is null
    or v_previous.terms_version is distinct from p_terms_version then
    insert into public.privacy_consent_events (
      user_id,
      purpose,
      granted,
      document_version,
      source,
      occurred_at
    )
    values (
      v_user_id,
      'terms',
      true,
      p_terms_version,
      'privacy_center',
      v_now
    );
  end if;

  if v_previous.user_id is null
    or v_previous.marketing_consent
      is distinct from coalesce(p_marketing_consent, false) then
    insert into public.privacy_consent_events (
      user_id,
      purpose,
      granted,
      document_version,
      source,
      occurred_at
    )
    values (
      v_user_id,
      'marketing',
      coalesce(p_marketing_consent, false),
      p_privacy_policy_version,
      'privacy_center',
      v_now
    );
  end if;

  insert into public.user_privacy_preferences (
    user_id,
    privacy_policy_version,
    privacy_acknowledged_at,
    terms_version,
    terms_accepted_at,
    marketing_consent,
    marketing_updated_at,
    created_at,
    updated_at
  )
  values (
    v_user_id,
    p_privacy_policy_version,
    v_now,
    p_terms_version,
    v_now,
    coalesce(p_marketing_consent, false),
    v_now,
    v_now,
    v_now
  )
  on conflict (user_id)
  do update set
    privacy_policy_version = excluded.privacy_policy_version,
    privacy_acknowledged_at = case
      when public.user_privacy_preferences.privacy_policy_version
        is distinct from excluded.privacy_policy_version
      then excluded.privacy_acknowledged_at
      else public.user_privacy_preferences.privacy_acknowledged_at
    end,
    terms_version = excluded.terms_version,
    terms_accepted_at = case
      when public.user_privacy_preferences.terms_version
        is distinct from excluded.terms_version
      then excluded.terms_accepted_at
      else public.user_privacy_preferences.terms_accepted_at
    end,
    marketing_consent = excluded.marketing_consent,
    marketing_updated_at = case
      when public.user_privacy_preferences.marketing_consent
        is distinct from excluded.marketing_consent
      then excluded.marketing_updated_at
      else public.user_privacy_preferences.marketing_updated_at
    end,
    updated_at = excluded.updated_at
  returning * into v_result;

  return jsonb_build_object(
    'privacy_policy_version', v_result.privacy_policy_version,
    'privacy_acknowledged_at', v_result.privacy_acknowledged_at,
    'terms_version', v_result.terms_version,
    'terms_accepted_at', v_result.terms_accepted_at,
    'marketing_consent', v_result.marketing_consent,
    'marketing_updated_at', v_result.marketing_updated_at
  );
end;
$$;

-- Il trigger registra le scelte già presenti nei metadati di una nuova
-- registrazione. Se un client non invia documenti validi, l'account viene
-- creato senza preferenze e l'app blocca l'accesso finché non vengono accettati.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_privacy_version text :=
    new.raw_user_meta_data ->> 'privacy_policy_version';
  v_terms_version text :=
    new.raw_user_meta_data ->> 'terms_version';
  v_privacy_acknowledged boolean :=
    lower(coalesce(
      new.raw_user_meta_data ->> 'privacy_acknowledged',
      'false'
    )) = 'true';
  v_terms_accepted boolean :=
    lower(coalesce(
      new.raw_user_meta_data ->> 'terms_accepted',
      'false'
    )) = 'true';
  v_marketing_consent boolean :=
    lower(coalesce(
      new.raw_user_meta_data ->> 'marketing_consent',
      'false'
    )) = 'true';
  v_now timestamptz := now();
begin
  insert into public.profiles (id, display_name)
  values (
    new.id,
    coalesce(
      nullif(trim(new.raw_user_meta_data ->> 'display_name'), ''),
      split_part(coalesce(new.email, 'mister'), '@', 1)
    )
  )
  on conflict (id) do nothing;

  if v_privacy_acknowledged
    and v_terms_accepted
    and v_privacy_version = '2026.07-prototype'
    and v_terms_version = '2026.07-prototype' then
    insert into public.user_privacy_preferences (
      user_id,
      privacy_policy_version,
      privacy_acknowledged_at,
      terms_version,
      terms_accepted_at,
      marketing_consent,
      marketing_updated_at,
      created_at,
      updated_at
    )
    values (
      new.id,
      v_privacy_version,
      v_now,
      v_terms_version,
      v_now,
      v_marketing_consent,
      v_now,
      v_now,
      v_now
    )
    on conflict (user_id) do nothing;

    insert into public.privacy_consent_events (
      user_id,
      purpose,
      granted,
      document_version,
      source,
      occurred_at
    )
    values
      (
        new.id,
        'privacy_notice',
        true,
        v_privacy_version,
        'registration',
        v_now
      ),
      (
        new.id,
        'terms',
        true,
        v_terms_version,
        'registration',
        v_now
      ),
      (
        new.id,
        'marketing',
        v_marketing_consent,
        v_privacy_version,
        'registration',
        v_now
      );
  end if;

  return new;
end;
$$;

create or replace function public.export_my_personal_data()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_result jsonb;
begin
  if v_user_id is null then
    raise exception 'Devi effettuare l''accesso.';
  end if;

  select jsonb_build_object(
    'export_format', 'LEGHEVO-personal-data-v1',
    'generated_at', now(),
    'account', (
      select jsonb_build_object(
        'id', account.id,
        'email', account.email,
        'created_at', account.created_at,
        'last_sign_in_at', account.last_sign_in_at,
        'email_confirmed_at', account.email_confirmed_at
      )
      from auth.users account
      where account.id = v_user_id
    ),
    'profile', (
      select jsonb_build_object(
        'display_name', profile.display_name,
        'avatar_url', profile.avatar_url,
        'subscription', profile.subscription,
        'created_at', profile.created_at,
        'updated_at', profile.updated_at
      )
      from public.profiles profile
      where profile.id = v_user_id
    ),
    'privacy_preferences', (
      select to_jsonb(preferences) - 'user_id'
      from public.user_privacy_preferences preferences
      where preferences.user_id = v_user_id
    ),
    'consent_history', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'purpose', event.purpose,
          'granted', event.granted,
          'document_version', event.document_version,
          'source', event.source,
          'occurred_at', event.occurred_at
        )
        order by event.occurred_at
      )
      from public.privacy_consent_events event
      where event.user_id = v_user_id
    ), '[]'::jsonb),
    'league_memberships', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'league_id', league.id,
          'league_name', league.name,
          'role', member.role,
          'joined_at', member.joined_at
        )
        order by member.joined_at
      )
      from public.league_members member
      join public.leagues league
        on league.id = member.league_id
      where member.user_id = v_user_id
    ), '[]'::jsonb),
    'fantasy_teams', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', team.id,
          'league_id', team.league_id,
          'name', team.name,
          'credits_remaining', team.credits_remaining,
          'created_at', team.created_at
        )
        order by team.created_at
      )
      from public.fantasy_teams team
      where team.manager_id = v_user_id
    ), '[]'::jsonb),
    'lineups', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', lineup.id,
          'team_id', lineup.fantasy_team_id,
          'matchday_id', lineup.matchday_id,
          'formation', lineup.formation,
          'status', lineup.status,
          'submitted_at', lineup.submitted_at,
          'players', coalesce((
            select jsonb_agg(
              jsonb_build_object(
                'athlete_id', entry.athlete_id,
                'name', concat_ws(
                  ' ',
                  athlete.first_name,
                  athlete.last_name
                ),
                'slot', entry.slot,
                'is_starter', entry.is_starter,
                'captain', entry.captain
              )
              order by entry.slot
            )
            from public.lineup_entries entry
            join public.athletes athlete
              on athlete.id = entry.athlete_id
            where entry.lineup_id = lineup.id
          ), '[]'::jsonb)
        )
        order by lineup.submitted_at nulls last
      )
      from public.lineups lineup
      join public.fantasy_teams team
        on team.id = lineup.fantasy_team_id
      where team.manager_id = v_user_id
    ), '[]'::jsonb),
    'notifications', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', notification.id,
          'league_id', notification.league_id,
          'kind', notification.kind,
          'title', notification.title,
          'body', notification.body,
          'read_at', notification.read_at,
          'created_at', notification.created_at
        )
        order by notification.created_at
      )
      from public.user_notifications notification
      where notification.user_id = v_user_id
    ), '[]'::jsonb)
  )
  into v_result;

  return v_result;
end;
$$;

revoke all on function public.save_my_privacy_preferences(
  text,
  text,
  boolean
) from public, anon;
revoke all on function public.export_my_personal_data()
from public, anon;

grant execute on function public.save_my_privacy_preferences(
  text,
  text,
  boolean
) to authenticated;
grant execute on function public.export_my_personal_data()
to authenticated;

select
  to_regclass(
    'public.user_privacy_preferences'
  ) is not null as privacy_preferences_ready,
  to_regclass(
    'public.privacy_consent_events'
  ) is not null as consent_history_ready,
  to_regprocedure(
    'public.save_my_privacy_preferences(text,text,boolean)'
  ) is not null as privacy_save_ready,
  to_regprocedure(
    'public.export_my_personal_data()'
  ) is not null as data_export_ready,
  has_function_privilege(
    'authenticated',
    'public.save_my_privacy_preferences(text,text,boolean)',
    'EXECUTE'
  ) as privacy_access_ready,
  has_function_privilege(
    'authenticated',
    'public.export_my_personal_data()',
    'EXECUTE'
  ) as export_access_ready,
  has_table_privilege(
    'authenticated',
    'public.user_privacy_preferences',
    'SELECT'
  ) as preferences_read_ready,
  not has_table_privilege(
    'authenticated',
    'public.privacy_consent_events',
    'INSERT'
  ) as consent_history_protected;
