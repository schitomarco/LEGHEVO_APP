-- LEGHEVO v0.62.43 authentication hotfix
-- Ripristina la creazione atomica del profilo per i nuovi utenti Auth.
-- Dipendenza: 098 rende profiles.profile_fingerprint obbligatorio; 099 definisce
-- il trigger corrente con la certificazione delle accettazioni legali.

begin;

do $preflight$
begin
  if to_regclass('public.profiles') is null
    or to_regclass('public.legal_document_releases') is null
    or to_regclass('public.user_privacy_preferences') is null
    or to_regclass('public.legal_acceptance_action_runs') is null then
    raise exception 'Preflight registrazione Auth non superato: schema incompleto.';
  end if;

  if not exists (
    select 1
    from information_schema.columns column_row
    where column_row.table_schema = 'public'
      and column_row.table_name = 'profiles'
      and column_row.column_name = 'profile_fingerprint'
      and column_row.is_nullable = 'NO'
  ) then
    raise exception 'Preflight registrazione Auth non superato: fingerprint profilo non protetta.';
  end if;

  if to_regprocedure('public.handle_new_user()') is null then
    raise exception 'Preflight registrazione Auth non superato: trigger function assente.';
  end if;
end;
$preflight$;

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_display_name text := coalesce(
    nullif(trim(new.raw_user_meta_data ->> 'display_name'), ''),
    split_part(coalesce(new.email, 'mister'), '@', 1)
  );
  v_privacy_version text := new.raw_user_meta_data ->> 'privacy_policy_version';
  v_terms_version text := new.raw_user_meta_data ->> 'terms_version';
  v_age_version text := new.raw_user_meta_data ->> 'minimum_age_version';
  v_privacy_acknowledged boolean :=
    lower(coalesce(new.raw_user_meta_data ->> 'privacy_acknowledged', 'false')) = 'true';
  v_terms_accepted boolean :=
    lower(coalesce(new.raw_user_meta_data ->> 'terms_accepted', 'false')) = 'true';
  v_age_confirmed boolean :=
    lower(coalesce(new.raw_user_meta_data ->> 'minimum_age_confirmed', 'false')) = 'true';
  v_now timestamptz := now();
  v_release public.legal_document_releases%rowtype;
  v_request_id uuid := gen_random_uuid();
  v_fingerprint text;
  v_snapshot jsonb;
begin
  insert into public.profiles (id, display_name, profile_fingerprint)
  values (
    new.id,
    v_display_name,
    pg_catalog.md5(v_display_name || E'\n\nfree\nactive')
  )
  on conflict (id) do nothing;

  if v_privacy_acknowledged and v_terms_accepted and v_age_confirmed then
    select release.*
    into v_release
    from public.legal_document_releases release
    where release.status = 'published'
      and release.market = 'IT'
      and release.privacy_policy_version = v_privacy_version
      and release.terms_version = v_terms_version
      and release.minimum_age_version = v_age_version
    order by release.published_at desc, release.release_key desc
    limit 1;
  end if;

  if v_release.release_key is not null then
    v_fingerprint := public.legal_acceptance_fingerprint_v1(
      new.id,
      v_release.release_key,
      v_release.privacy_policy_version,
      v_release.terms_version,
      v_release.minimum_age_version,
      false,
      1
    );

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
      updated_at,
      revision,
      acceptance_fingerprint,
      last_acceptance_request_id,
      release_key
    ) values (
      new.id,
      v_release.privacy_policy_version,
      v_now,
      v_release.terms_version,
      v_now,
      false,
      v_now,
      v_release.minimum_age_version,
      v_now,
      v_now,
      v_now,
      1,
      v_fingerprint,
      v_request_id,
      v_release.release_key
    )
    on conflict (user_id) do nothing;

    insert into public.privacy_consent_events (
      user_id, purpose, granted, document_version, source, occurred_at
    ) values
      (new.id, 'privacy_notice', true, v_release.privacy_policy_version, 'registration_guarded', v_now),
      (new.id, 'terms', true, v_release.terms_version, 'registration_guarded', v_now),
      (new.id, 'age_requirement', true, v_release.minimum_age_version, 'registration_guarded', v_now),
      (new.id, 'marketing', false, v_release.privacy_policy_version, 'registration_guarded', v_now);

    v_snapshot := public.legal_acceptance_payload_v1(new.id)
      || jsonb_build_object(
        'generatedAt', v_now,
        'certifiedActionCount', 1,
        'lastCertifiedAt', v_now
      );

    insert into public.legal_acceptance_action_runs (
      user_id,
      action_type,
      idempotency_key,
      previous_revision,
      result_revision,
      release_key,
      privacy_policy_version,
      terms_version,
      minimum_age_version,
      request_fingerprint,
      result_fingerprint,
      result_snapshot,
      created_at
    ) values (
      new.id,
      'registration',
      v_request_id,
      0,
      1,
      v_release.release_key,
      v_release.privacy_policy_version,
      v_release.terms_version,
      v_release.minimum_age_version,
      public.leghevo_sha256_hex_v1(
        concat_ws(E'\n', new.id::text, v_release.release_key, 'registration', v_request_id::text)
      ),
      v_fingerprint,
      v_snapshot,
      v_now
    )
    on conflict (user_id, idempotency_key) do nothing;
  end if;

  return new;
end;
$$;

do $validate$
declare
  v_definition text;
begin
  select pg_catalog.pg_get_functiondef(procedure_row.oid)
  into v_definition
  from pg_catalog.pg_proc procedure_row
  where procedure_row.oid = to_regprocedure('public.handle_new_user()');

  if position('profile_fingerprint' in coalesce(v_definition, '')) = 0
    or position('pg_catalog.md5' in coalesce(v_definition, '')) = 0
    or not exists (
      select 1
      from pg_catalog.pg_trigger trigger_row
      where trigger_row.tgrelid = 'auth.users'::regclass
        and trigger_row.tgname = 'on_auth_user_created'
        and not trigger_row.tgisinternal
    ) then
    raise exception 'Validazione registrazione Auth non superata.';
  end if;
end;
$validate$;

commit;
