-- LEGHEVO · documenti legali pubblicati, titolare e requisito di età
-- Eseguire nel SQL Editor di Supabase dopo 050.
--
-- Lo script pubblica le versioni 2026.07.29, aggiunge la dichiarazione
-- relativa all'età minima e conserva la presa visione. Non crea account,
-- non cambia preferenze esistenti e non modifica leghe o dati sportivi.

create table if not exists public.legal_document_releases (
  release_key text primary key,
  privacy_policy_version text not null unique,
  terms_version text not null unique,
  minimum_age_version text not null unique,
  minimum_age smallint not null check (minimum_age between 13 and 18),
  market text not null,
  published_at timestamptz not null,
  status text not null check (status in ('published', 'retired')),
  created_at timestamptz not null default now()
);

insert into public.legal_document_releases (
  release_key,
  privacy_policy_version,
  terms_version,
  minimum_age_version,
  minimum_age,
  market,
  published_at,
  status
)
values (
  'italy-2026.07.29',
  '2026.07.29',
  '2026.07.29',
  '14-2026.07.29',
  14,
  'IT',
  '2026-07-29 00:00:00+02',
  'published'
)
on conflict (release_key)
do update set
  privacy_policy_version = excluded.privacy_policy_version,
  terms_version = excluded.terms_version,
  minimum_age_version = excluded.minimum_age_version,
  minimum_age = excluded.minimum_age,
  market = excluded.market,
  published_at = excluded.published_at,
  status = excluded.status;

alter table public.legal_document_releases enable row level security;
revoke all on public.legal_document_releases from anon, authenticated;

alter table public.user_privacy_preferences
  add column if not exists minimum_age_version text,
  add column if not exists minimum_age_confirmed_at timestamptz;

alter table public.privacy_consent_events
  drop constraint if exists privacy_consent_events_purpose_check;

alter table public.privacy_consent_events
  add constraint privacy_consent_events_purpose_check
  check (
    purpose in (
      'privacy_notice',
      'terms',
      'marketing',
      'age_requirement'
    )
  );

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
  v_age_version text := '14-2026.07.29';
  v_previous public.user_privacy_preferences%rowtype;
  v_result public.user_privacy_preferences%rowtype;
begin
  if v_user_id is null then
    raise exception 'Devi effettuare l''accesso.';
  end if;

  if not exists (
    select 1
    from public.legal_document_releases release
    where release.status = 'published'
      and release.market = 'IT'
      and release.privacy_policy_version =
        trim(coalesce(p_privacy_policy_version, ''))
      and release.terms_version =
        trim(coalesce(p_terms_version, ''))
      and release.minimum_age_version = v_age_version
  ) then
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
    or v_previous.minimum_age_version is distinct from v_age_version
    or v_previous.minimum_age_confirmed_at is null then
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
      'age_requirement',
      true,
      v_age_version,
      'privacy_center',
      v_now
    );
  end if;

  if v_previous.user_id is null
    or v_previous.marketing_consent is distinct from false then
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
      false,
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
    minimum_age_version,
    minimum_age_confirmed_at,
    created_at,
    updated_at
  )
  values (
    v_user_id,
    p_privacy_policy_version,
    v_now,
    p_terms_version,
    v_now,
    false,
    v_now,
    v_age_version,
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
    marketing_consent = false,
    marketing_updated_at = case
      when public.user_privacy_preferences.marketing_consent
        is distinct from false
      then excluded.marketing_updated_at
      else public.user_privacy_preferences.marketing_updated_at
    end,
    minimum_age_version = excluded.minimum_age_version,
    minimum_age_confirmed_at = case
      when public.user_privacy_preferences.minimum_age_version
        is distinct from excluded.minimum_age_version
        or public.user_privacy_preferences.minimum_age_confirmed_at is null
      then excluded.minimum_age_confirmed_at
      else public.user_privacy_preferences.minimum_age_confirmed_at
    end,
    updated_at = excluded.updated_at
  returning * into v_result;

  return jsonb_build_object(
    'privacy_policy_version', v_result.privacy_policy_version,
    'privacy_acknowledged_at', v_result.privacy_acknowledged_at,
    'terms_version', v_result.terms_version,
    'terms_accepted_at', v_result.terms_accepted_at,
    'marketing_consent', v_result.marketing_consent,
    'marketing_updated_at', v_result.marketing_updated_at,
    'minimum_age_version', v_result.minimum_age_version,
    'minimum_age_confirmed_at', v_result.minimum_age_confirmed_at
  );
end;
$$;

-- Il trigger accetta una registrazione diretta soltanto quando il client
-- invia documenti pubblicati e la dichiarazione relativa al requisito di età.
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
  v_age_version text :=
    new.raw_user_meta_data ->> 'minimum_age_version';
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
  v_age_confirmed boolean :=
    lower(coalesce(
      new.raw_user_meta_data ->> 'minimum_age_confirmed',
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
    and v_age_confirmed
    and exists (
      select 1
      from public.legal_document_releases release
      where release.status = 'published'
        and release.market = 'IT'
        and release.privacy_policy_version = v_privacy_version
        and release.terms_version = v_terms_version
        and release.minimum_age_version = v_age_version
    ) then
    insert into public.user_privacy_preferences (
      user_id,
      privacy_policy_version,
      privacy_acknowledged_at,
      terms_version,
      terms_accepted_at,
      marketing_consent,
      marketing_updated_at,
      minimum_age_version,
      minimum_age_confirmed_at,
      created_at,
      updated_at
    )
    values (
      new.id,
      v_privacy_version,
      v_now,
      v_terms_version,
      v_now,
      false,
      v_now,
      v_age_version,
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
        'age_requirement',
        true,
        v_age_version,
        'registration',
        v_now
      ),
      (
        new.id,
        'marketing',
        false,
        v_privacy_version,
        'registration',
        v_now
      );
  end if;

  return new;
end;
$$;

revoke all on function public.save_my_privacy_preferences(
  text,
  text,
  boolean
) from public, anon;

grant execute on function public.save_my_privacy_preferences(
  text,
  text,
  boolean
) to authenticated;

select
  to_regclass('public.legal_document_releases') is not null
    as legal_releases_ready,
  exists (
    select 1
    from public.legal_document_releases release
    where release.release_key = 'italy-2026.07.29'
      and release.status = 'published'
      and release.minimum_age = 14
  ) as published_release_ready,
  exists (
    select 1
    from information_schema.columns column_info
    where column_info.table_schema = 'public'
      and column_info.table_name = 'user_privacy_preferences'
      and column_info.column_name = 'minimum_age_version'
  ) as age_version_ready,
  exists (
    select 1
    from information_schema.columns column_info
    where column_info.table_schema = 'public'
      and column_info.table_name = 'user_privacy_preferences'
      and column_info.column_name = 'minimum_age_confirmed_at'
  ) as age_confirmation_ready,
  exists (
    select 1
    from pg_constraint constraint_info
    where constraint_info.conrelid =
      'public.privacy_consent_events'::regclass
      and constraint_info.conname =
        'privacy_consent_events_purpose_check'
      and pg_get_constraintdef(constraint_info.oid)
        like '%age_requirement%'
  ) as age_event_ready,
  to_regprocedure(
    'public.save_my_privacy_preferences(text,text,boolean)'
  ) is not null as legal_acceptance_ready,
  to_regprocedure('public.handle_new_user()') is not null
    as registration_gate_ready,
  has_function_privilege(
    'authenticated',
    'public.save_my_privacy_preferences(text,text,boolean)',
    'EXECUTE'
  ) as legal_acceptance_access_ready,
  not has_table_privilege(
    'authenticated',
    'public.privacy_consent_events',
    'INSERT'
  ) as acceptance_history_protected,
  not has_table_privilege(
    'authenticated',
    'public.legal_document_releases',
    'SELECT'
  ) as legal_release_registry_protected,
  to_regprocedure(
    'public.export_my_personal_data_v2()'
  ) is not null as personal_export_still_ready,
  (
    select count(*) = 1
    from public.legal_document_releases release
    where release.status = 'published'
      and release.market = 'IT'
  ) as single_italian_release_ready;
