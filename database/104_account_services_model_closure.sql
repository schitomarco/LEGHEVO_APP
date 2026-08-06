-- LEGHEVO v0.62.0
-- Chiusura certificata dello Sviluppo 7: account, privacy, assistenza,
-- notifiche, push, credenziali ed esportazione dati.
-- Migrazione idempotente e non distruttiva.

begin;

-- Preflight in sola lettura. Verifica gli oggetti già validati nelle
-- versioni 0.61.1-0.61.9 prima di creare la certificazione conclusiva.
do $preflight$
declare
  v_missing text[] := array[]::text[];
  v_relation text;
  v_signature text;
begin
  foreach v_relation in array array[
    'public.leghevo_model_certifications',
    'public.profiles',
    'public.data_rights_request_action_runs',
    'public.support_request_action_runs',
    'public.push_preference_action_runs',
    'public.account_action_runs',
    'public.legal_acceptance_action_runs',
    'public.notification_action_runs',
    'public.account_security_states',
    'public.account_security_events',
    'public.personal_data_export_runs',
    'public.account_service_states',
    'public.account_service_events'
  ] loop
    if to_regclass(v_relation) is null then
      v_missing := array_append(v_missing, 'tabella ' || v_relation);
    end if;
  end loop;

  foreach v_signature in array array[
    'public.leghevo_safe_table_privilege_v1(name,text,text)',
    'public.leghevo_safe_function_privilege_v1(name,text,text)',
    'public.get_data_rights_request_safety_integrity_v1()',
    'public.get_support_request_safety_integrity_v1()',
    'public.get_push_preference_safety_integrity_v1()',
    'public.get_account_profile_safety_integrity_v1()',
    'public.get_legal_acceptance_safety_integrity_v1()',
    'public.get_notification_center_safety_integrity_v1()',
    'public.get_account_credential_security_integrity_v1()',
    'public.get_personal_data_export_safety_integrity_v1()',
    'public.get_account_services_integrity_hub_v1()',
    'public.get_my_account_service_hub_v1()',
    'public.get_my_account_center_v4()'
  ] loop
    if to_regprocedure(v_signature) is null then
      v_missing := array_append(v_missing, 'funzione ' || v_signature);
    end if;
  end loop;

  if cardinality(v_missing) > 0 then
    raise exception
      'Preflight v0.62.0 non superato. Oggetti mancanti: %',
      array_to_string(v_missing, '; ');
  end if;
end;
$preflight$;

-- Rende esplicita e idempotente la pubblicazione Realtime dei registri
-- operativi dello Sviluppo 7.
do $realtime$
declare
  v_table_name text;
begin
  if exists (
    select 1
    from pg_catalog.pg_publication publication
    where publication.pubname = 'supabase_realtime'
  ) then
    foreach v_table_name in array array[
      'data_rights_request_action_runs',
      'support_request_action_runs',
      'push_preference_action_runs',
      'account_action_runs',
      'legal_acceptance_action_runs',
      'notification_action_runs',
      'account_security_states',
      'account_security_events',
      'personal_data_export_runs',
      'account_service_states',
      'account_service_events'
    ] loop
      execute format(
        'alter table public.%I replica identity full',
        v_table_name
      );

      if not exists (
        select 1
        from pg_catalog.pg_publication_tables publication_table
        where publication_table.pubname = 'supabase_realtime'
          and publication_table.schemaname = 'public'
          and publication_table.tablename = v_table_name
      ) then
        execute format(
          'alter publication supabase_realtime add table public.%I',
          v_table_name
        );
      end if;
    end loop;
  end if;
end;
$realtime$;

-- Riassume in modo sicuro una diagnostica restituita come oggetto JSON.
-- PostgreSQL non espone jsonb_object_length(): il conteggio viene quindi
-- ricavato dalle coppie chiave/valore restituite da jsonb_each().
create or replace function public.leghevo_boolean_diagnostic_summary_v1(
  p_diagnostic jsonb
)
returns jsonb
language sql
immutable
security definer
set search_path = ''
as $$
  with diagnostic_items as (
    select item.key, item.value
    from pg_catalog.jsonb_each(
      coalesce(p_diagnostic, '{}'::jsonb)
    ) as item
  ),
  diagnostic_stats as (
    select
      count(*)::integer as total_count,
      count(*) filter (where value = 'true'::jsonb)::integer
        as passed_count,
      coalesce(
        bool_and(pg_catalog.jsonb_typeof(value) = 'boolean'),
        true
      ) as all_boolean,
      count(*) > 0
        and coalesce(
          bool_and(
            pg_catalog.jsonb_typeof(value) = 'boolean'
            and value = 'true'::jsonb
          ),
          false
        ) as healthy
    from diagnostic_items
  )
  select pg_catalog.jsonb_build_object(
    'totalCount', total_count,
    'passedCount', passed_count,
    'allBoolean', all_boolean,
    'healthy', healthy
  )
  from diagnostic_stats;
$$;

revoke all on function public.leghevo_boolean_diagnostic_summary_v1(jsonb)
from public, anon, authenticated;
grant execute on function public.leghevo_boolean_diagnostic_summary_v1(jsonb)
to service_role;

-- Verifica strutturale unica dello Sviluppo 7, composta da esattamente
-- venti capacità indipendenti.
create or replace function public.get_account_services_schema_readiness_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_data_rights jsonb;
  v_support jsonb;
  v_push jsonb;
  v_profile jsonb;
  v_legal jsonb;
  v_notifications jsonb;
  v_credentials jsonb;
  v_export jsonb;
  v_hub jsonb;

  v_data_rights_summary jsonb;
  v_support_summary jsonb;
  v_push_summary jsonb;
  v_profile_summary jsonb;
  v_legal_summary jsonb;
  v_notifications_summary jsonb;
  v_credentials_summary jsonb;
  v_export_summary jsonb;
  v_hub_summary jsonb;

  v_foundation_ready boolean := false;
  v_diagnostic_contracts_ready boolean := false;
  v_data_rights_ready boolean := false;
  v_support_ready boolean := false;
  v_push_ready boolean := false;
  v_profile_ready boolean := false;
  v_legal_ready boolean := false;
  v_notifications_ready boolean := false;
  v_credentials_ready boolean := false;
  v_export_ready boolean := false;
  v_service_hub_ready boolean := false;
  v_registries_ready boolean := false;
  v_immutable_triggers_ready boolean := false;
  v_source_triggers_ready boolean := false;
  v_rls_ready boolean := false;
  v_realtime_ready boolean := false;
  v_authenticated_endpoints_ready boolean := false;
  v_anonymous_blocked boolean := false;
  v_direct_writes_blocked boolean := false;
  v_data_continuity_ready boolean := false;
  v_passed_count integer := 0;
  v_signature text;
  v_relation text;
begin
  v_data_rights :=
    public.get_data_rights_request_safety_integrity_v1();
  v_support := public.get_support_request_safety_integrity_v1();
  v_push := public.get_push_preference_safety_integrity_v1();
  v_profile := public.get_account_profile_safety_integrity_v1();
  v_legal := public.get_legal_acceptance_safety_integrity_v1();
  v_notifications :=
    public.get_notification_center_safety_integrity_v1();
  v_credentials :=
    public.get_account_credential_security_integrity_v1();
  v_export := public.get_personal_data_export_safety_integrity_v1();
  select to_jsonb(diagnostic) into v_hub
  from public.get_account_services_integrity_hub_v1() diagnostic;

  v_data_rights_summary :=
    public.leghevo_boolean_diagnostic_summary_v1(v_data_rights);
  v_support_summary :=
    public.leghevo_boolean_diagnostic_summary_v1(v_support);
  v_push_summary := public.leghevo_boolean_diagnostic_summary_v1(v_push);
  v_profile_summary :=
    public.leghevo_boolean_diagnostic_summary_v1(v_profile);
  v_legal_summary := public.leghevo_boolean_diagnostic_summary_v1(v_legal);
  v_notifications_summary :=
    public.leghevo_boolean_diagnostic_summary_v1(v_notifications);
  v_credentials_summary :=
    public.leghevo_boolean_diagnostic_summary_v1(v_credentials);
  v_export_summary := public.leghevo_boolean_diagnostic_summary_v1(v_export);
  v_hub_summary := public.leghevo_boolean_diagnostic_summary_v1(v_hub);

  v_foundation_ready :=
    to_regclass('public.leghevo_model_certifications') is not null
    and to_regprocedure(
      'public.leghevo_safe_table_privilege_v1(name,text,text)'
    ) is not null
    and to_regprocedure(
      'public.leghevo_safe_function_privilege_v1(name,text,text)'
    ) is not null
    and to_regprocedure(
      'public.leghevo_boolean_diagnostic_summary_v1(jsonb)'
    ) is not null
    and to_regprocedure('public.get_my_account_center_v4()') is not null;

  v_diagnostic_contracts_ready :=
    (v_data_rights_summary ->> 'totalCount')::integer = 20
    and (v_support_summary ->> 'totalCount')::integer = 20
    and (v_push_summary ->> 'totalCount')::integer = 20
    and (v_profile_summary ->> 'totalCount')::integer = 20
    and (v_legal_summary ->> 'totalCount')::integer = 20
    and (v_notifications_summary ->> 'totalCount')::integer = 21
    and (v_credentials_summary ->> 'totalCount')::integer = 21
    and (v_export_summary ->> 'totalCount')::integer = 20
    and (v_hub_summary ->> 'totalCount')::integer = 20
    and (v_data_rights_summary ->> 'allBoolean')::boolean
    and (v_support_summary ->> 'allBoolean')::boolean
    and (v_push_summary ->> 'allBoolean')::boolean
    and (v_profile_summary ->> 'allBoolean')::boolean
    and (v_legal_summary ->> 'allBoolean')::boolean
    and (v_notifications_summary ->> 'allBoolean')::boolean
    and (v_credentials_summary ->> 'allBoolean')::boolean
    and (v_export_summary ->> 'allBoolean')::boolean
    and (v_hub_summary ->> 'allBoolean')::boolean;

  v_data_rights_ready := (v_data_rights_summary ->> 'healthy')::boolean;
  v_support_ready := (v_support_summary ->> 'healthy')::boolean;
  v_push_ready := (v_push_summary ->> 'healthy')::boolean;
  v_profile_ready := (v_profile_summary ->> 'healthy')::boolean;
  v_legal_ready := (v_legal_summary ->> 'healthy')::boolean;
  v_notifications_ready := (v_notifications_summary ->> 'healthy')::boolean;
  v_credentials_ready := (v_credentials_summary ->> 'healthy')::boolean;
  v_export_ready := (v_export_summary ->> 'healthy')::boolean;
  v_service_hub_ready := (v_hub_summary ->> 'healthy')::boolean;

  v_registries_ready := true;
  foreach v_relation in array array[
    'public.data_rights_request_action_runs',
    'public.support_request_action_runs',
    'public.push_preference_action_runs',
    'public.account_action_runs',
    'public.legal_acceptance_action_runs',
    'public.notification_action_runs',
    'public.account_security_states',
    'public.account_security_events',
    'public.personal_data_export_runs',
    'public.account_service_states',
    'public.account_service_events'
  ] loop
    v_registries_ready := v_registries_ready
      and to_regclass(v_relation) is not null;
  end loop;

  v_immutable_triggers_ready :=
    exists (
      select 1 from pg_catalog.pg_trigger trigger_row
      where trigger_row.tgrelid =
        to_regclass('public.data_rights_request_action_runs')
        and trigger_row.tgname = 'data_rights_action_runs_immutable'
        and not trigger_row.tgisinternal
    )
    and exists (
      select 1 from pg_catalog.pg_trigger trigger_row
      where trigger_row.tgrelid =
        to_regclass('public.support_request_action_runs')
        and trigger_row.tgname = 'support_action_runs_immutable'
        and not trigger_row.tgisinternal
    )
    and exists (
      select 1 from pg_catalog.pg_trigger trigger_row
      where trigger_row.tgrelid =
        to_regclass('public.push_preference_action_runs')
        and trigger_row.tgname = 'push_preference_action_runs_immutable'
        and not trigger_row.tgisinternal
    )
    and exists (
      select 1 from pg_catalog.pg_trigger trigger_row
      where trigger_row.tgrelid = to_regclass('public.account_action_runs')
        and trigger_row.tgname = 'account_action_runs_immutable'
        and not trigger_row.tgisinternal
    )
    and exists (
      select 1 from pg_catalog.pg_trigger trigger_row
      where trigger_row.tgrelid =
        to_regclass('public.legal_acceptance_action_runs')
        and trigger_row.tgname = 'legal_acceptance_action_runs_immutable'
        and not trigger_row.tgisinternal
    )
    and exists (
      select 1 from pg_catalog.pg_trigger trigger_row
      where trigger_row.tgrelid =
        to_regclass('public.notification_action_runs')
        and trigger_row.tgname = 'notification_action_runs_immutable'
        and not trigger_row.tgisinternal
    )
    and exists (
      select 1 from pg_catalog.pg_trigger trigger_row
      where trigger_row.tgrelid =
        to_regclass('public.account_security_events')
        and trigger_row.tgname = 'account_security_events_immutable'
        and not trigger_row.tgisinternal
    )
    and exists (
      select 1 from pg_catalog.pg_trigger trigger_row
      where trigger_row.tgrelid =
        to_regclass('public.personal_data_export_runs')
        and trigger_row.tgname = 'personal_data_export_runs_immutable'
        and not trigger_row.tgisinternal
    )
    and exists (
      select 1 from pg_catalog.pg_trigger trigger_row
      where trigger_row.tgrelid =
        to_regclass('public.account_service_events')
        and trigger_row.tgname = 'account_service_events_immutable'
        and not trigger_row.tgisinternal
    );

  select count(*) = 8
  into v_source_triggers_ready
  from pg_catalog.pg_trigger trigger_row
  join pg_catalog.pg_class table_row
    on table_row.oid = trigger_row.tgrelid
  join pg_catalog.pg_namespace namespace_row
    on namespace_row.oid = table_row.relnamespace
  where namespace_row.nspname = 'public'
    and trigger_row.tgname like 'zz_account_service_hub_%'
    and not trigger_row.tgisinternal;

  v_rls_ready := true;
  foreach v_relation in array array[
    'public.data_rights_request_action_runs',
    'public.support_request_action_runs',
    'public.push_preference_action_runs',
    'public.account_action_runs',
    'public.legal_acceptance_action_runs',
    'public.notification_action_runs',
    'public.account_security_states',
    'public.account_security_events',
    'public.personal_data_export_runs',
    'public.account_service_states',
    'public.account_service_events'
  ] loop
    v_rls_ready := v_rls_ready and coalesce((
      select relation_row.relrowsecurity
      from pg_catalog.pg_class relation_row
      where relation_row.oid = to_regclass(v_relation)
    ), false);
  end loop;

  v_realtime_ready := true;
  foreach v_relation in array array[
    'data_rights_request_action_runs',
    'support_request_action_runs',
    'push_preference_action_runs',
    'account_action_runs',
    'legal_acceptance_action_runs',
    'notification_action_runs',
    'account_security_states',
    'account_security_events',
    'personal_data_export_runs',
    'account_service_states',
    'account_service_events'
  ] loop
    v_realtime_ready := v_realtime_ready and exists (
      select 1
      from pg_catalog.pg_publication_tables publication_table
      where publication_table.pubname = 'supabase_realtime'
        and publication_table.schemaname = 'public'
        and publication_table.tablename = v_relation
    );
  end loop;

  v_authenticated_endpoints_ready := true;
  foreach v_signature in array array[
    'public.get_my_data_rights_center_v2()',
    'public.submit_my_data_rights_request_guarded_v1(text,text,uuid)',
    'public.cancel_my_data_rights_request_guarded_v1(uuid,bigint,uuid)',
    'public.get_my_support_center_v2()',
    'public.create_my_support_request_guarded_v1(text,text,text,uuid,uuid)',
    'public.reply_to_my_support_request_guarded_v1(uuid,text,bigint,uuid)',
    'public.close_my_support_request_guarded_v1(uuid,bigint,uuid)',
    'public.get_my_push_notification_preferences_v2()',
    'public.save_my_push_notification_preferences_guarded_v1(boolean,boolean,boolean,boolean,boolean,boolean,bigint,uuid)',
    'public.register_my_push_device_guarded_v1(text,text,text,text,uuid)',
    'public.disable_my_push_device_guarded_v1(text,uuid)',
    'public.release_stored_push_device_guarded_v1(text,uuid)',
    'public.update_my_profile_guarded_v1(text,bigint,uuid)',
    'public.delete_my_account_guarded_v1(bigint,uuid)',
    'public.get_my_privacy_center_v4()',
    'public.save_my_privacy_preferences_guarded_v1(text,text,text,bigint,uuid)',
    'public.get_my_notification_center_v2(integer)',
    'public.mark_notification_read_guarded_v1(uuid,uuid)',
    'public.mark_all_notifications_read_guarded_v1(uuid)',
    'public.export_my_personal_data_guarded_v1(uuid)',
    'public.get_my_account_service_hub_v1()',
    'public.get_my_account_center_v4()'
  ] loop
    v_authenticated_endpoints_ready := v_authenticated_endpoints_ready
      and public.leghevo_safe_function_privilege_v1(
        'authenticated', v_signature, 'EXECUTE'
      );
  end loop;

  v_anonymous_blocked := true;
  foreach v_signature in array array[
    'public.get_my_data_rights_center_v2()',
    'public.get_my_support_center_v2()',
    'public.get_my_push_notification_preferences_v2()',
    'public.get_my_privacy_center_v4()',
    'public.get_my_notification_center_v2(integer)',
    'public.get_my_account_service_hub_v1()',
    'public.get_my_account_center_v4()',
    'public.export_my_personal_data_guarded_v1(uuid)'
  ] loop
    v_anonymous_blocked := v_anonymous_blocked
      and not public.leghevo_safe_function_privilege_v1(
        'anon', v_signature, 'EXECUTE'
      );
  end loop;

  v_direct_writes_blocked := true;
  foreach v_relation in array array[
    'public.data_rights_request_action_runs',
    'public.support_request_action_runs',
    'public.push_preference_action_runs',
    'public.account_action_runs',
    'public.legal_acceptance_action_runs',
    'public.notification_action_runs',
    'public.account_security_states',
    'public.account_security_events',
    'public.personal_data_export_runs',
    'public.account_service_states',
    'public.account_service_events'
  ] loop
    v_direct_writes_blocked := v_direct_writes_blocked
      and not public.leghevo_safe_table_privilege_v1(
        'authenticated', v_relation, 'INSERT'
      )
      and not public.leghevo_safe_table_privilege_v1(
        'authenticated', v_relation, 'UPDATE'
      )
      and not public.leghevo_safe_table_privilege_v1(
        'authenticated', v_relation, 'DELETE'
      );
  end loop;

  v_data_continuity_ready :=
    not exists (
      select 1
      from public.account_service_states state
      where state.protected_service_count <> 8
        or char_length(state.state_fingerprint) <> 64
    )
    and not exists (
      select 1
      from public.account_service_events event
      where char_length(event.event_fingerprint) <> 64
    )
    and not exists (
      select 1
      from public.profiles profile
      left join public.account_service_states state
        on state.user_id = profile.id
      where state.user_id is null
    );

  v_passed_count :=
    v_foundation_ready::integer
    + v_diagnostic_contracts_ready::integer
    + v_data_rights_ready::integer
    + v_support_ready::integer
    + v_push_ready::integer
    + v_profile_ready::integer
    + v_legal_ready::integer
    + v_notifications_ready::integer
    + v_credentials_ready::integer
    + v_export_ready::integer
    + v_service_hub_ready::integer
    + v_registries_ready::integer
    + v_immutable_triggers_ready::integer
    + v_source_triggers_ready::integer
    + v_rls_ready::integer
    + v_realtime_ready::integer
    + v_authenticated_endpoints_ready::integer
    + v_anonymous_blocked::integer
    + v_direct_writes_blocked::integer
    + v_data_continuity_ready::integer;

  return jsonb_build_object(
    'healthy', v_passed_count = 20,
    'checkCount', 20,
    'passedCount', v_passed_count,
    'checks', jsonb_build_object(
      'foundationReady', v_foundation_ready,
      'diagnosticContractsReady', v_diagnostic_contracts_ready,
      'dataRightsReady', v_data_rights_ready,
      'supportReady', v_support_ready,
      'pushReady', v_push_ready,
      'profileReady', v_profile_ready,
      'legalReady', v_legal_ready,
      'notificationsReady', v_notifications_ready,
      'credentialsReady', v_credentials_ready,
      'personalDataExportReady', v_export_ready,
      'serviceHubReady', v_service_hub_ready,
      'registriesReady', v_registries_ready,
      'immutableTriggersReady', v_immutable_triggers_ready,
      'sourceTriggersReady', v_source_triggers_ready,
      'rlsReady', v_rls_ready,
      'realtimeReady', v_realtime_ready,
      'authenticatedEndpointsReady', v_authenticated_endpoints_ready,
      'anonymousBlocked', v_anonymous_blocked,
      'directWritesBlocked', v_direct_writes_blocked,
      'dataContinuityReady', v_data_continuity_ready
    ),
    'modules', jsonb_build_object(
      'dataRights', v_data_rights_summary,
      'support', v_support_summary,
      'push', v_push_summary,
      'profile', v_profile_summary,
      'legalAcceptance', v_legal_summary,
      'notifications', v_notifications_summary,
      'credentials', v_credentials_summary,
      'personalDataExport', v_export_summary,
      'serviceHub', v_hub_summary
    )
  );
end;
$$;

-- Impronta stabile delle strutture e delle funzioni dello Sviluppo 7.
create or replace function public.compute_account_services_schema_fingerprint_v1()
returns text
language sql
stable
security definer
set search_path = ''
as $$
  with relation_names(name) as (
    values
      ('account_action_runs'),
      ('account_security_events'),
      ('account_security_states'),
      ('account_service_events'),
      ('account_service_states'),
      ('data_rights_request_action_runs'),
      ('legal_acceptance_action_runs'),
      ('notification_action_runs'),
      ('personal_data_export_runs'),
      ('push_preference_action_runs'),
      ('support_request_action_runs')
  ),
  function_signatures(signature) as (
    values
      ('public.get_data_rights_request_safety_integrity_v1()'),
      ('public.get_support_request_safety_integrity_v1()'),
      ('public.get_push_preference_safety_integrity_v1()'),
      ('public.get_account_profile_safety_integrity_v1()'),
      ('public.get_legal_acceptance_safety_integrity_v1()'),
      ('public.get_notification_center_safety_integrity_v1()'),
      ('public.get_account_credential_security_integrity_v1()'),
      ('public.get_personal_data_export_safety_integrity_v1()'),
      ('public.get_account_services_integrity_hub_v1()'),
      ('public.get_my_account_service_hub_v1()'),
      ('public.get_my_account_center_v4()'),
      ('public.submit_my_data_rights_request_guarded_v1(text,text,uuid)'),
      ('public.create_my_support_request_guarded_v1(text,text,text,uuid,uuid)'),
      ('public.save_my_push_notification_preferences_guarded_v1(boolean,boolean,boolean,boolean,boolean,boolean,bigint,uuid)'),
      ('public.update_my_profile_guarded_v1(text,bigint,uuid)'),
      ('public.save_my_privacy_preferences_guarded_v1(text,text,text,bigint,uuid)'),
      ('public.mark_notification_read_guarded_v1(uuid,uuid)'),
      ('public.export_my_personal_data_guarded_v1(uuid)')
  )
  select pg_catalog.md5(
    jsonb_build_object(
      'relations', (
        select jsonb_object_agg(
          relation_name.name,
          jsonb_build_object(
            'rls', relation_row.relrowsecurity,
            'columns', (
              select jsonb_agg(
                jsonb_build_object(
                  'name', attribute_row.attname,
                  'type', pg_catalog.format_type(
                    attribute_row.atttypid,
                    attribute_row.atttypmod
                  ),
                  'notNull', attribute_row.attnotnull
                ) order by attribute_row.attnum
              )
              from pg_catalog.pg_attribute attribute_row
              where attribute_row.attrelid = relation_row.oid
                and attribute_row.attnum > 0
                and not attribute_row.attisdropped
            )
          ) order by relation_name.name
        )
        from relation_names relation_name
        join pg_catalog.pg_class relation_row
          on relation_row.oid = to_regclass('public.' || relation_name.name)
      ),
      'functions', (
        select jsonb_object_agg(
          function_signature.signature,
          pg_catalog.md5(pg_catalog.pg_get_functiondef(
            to_regprocedure(function_signature.signature)
          )) order by function_signature.signature
        )
        from function_signatures function_signature
      ),
      'triggers', (
        select jsonb_agg(
          pg_catalog.pg_get_triggerdef(trigger_row.oid, true)
          order by table_row.relname, trigger_row.tgname
        )
        from pg_catalog.pg_trigger trigger_row
        join pg_catalog.pg_class table_row
          on table_row.oid = trigger_row.tgrelid
        join relation_names relation_name
          on relation_name.name = table_row.relname
        join pg_catalog.pg_namespace namespace_row
          on namespace_row.oid = table_row.relnamespace
        where namespace_row.nspname = 'public'
          and not trigger_row.tgisinternal
      ),
      'policies', (
        select jsonb_agg(
          jsonb_build_object(
            'table', policy_row.tablename,
            'name', policy_row.policyname,
            'command', policy_row.cmd,
            'roles', policy_row.roles,
            'qual', policy_row.qual,
            'withCheck', policy_row.with_check
          ) order by policy_row.tablename, policy_row.policyname
        )
        from pg_catalog.pg_policies policy_row
        join relation_names relation_name
          on relation_name.name = policy_row.tablename
        where policy_row.schemaname = 'public'
      )
    )::text
  );
$$;

-- La certificazione viene registrata solo dopo il superamento delle venti
-- verifiche. Una riesecuzione accetta esclusivamente la stessa impronta.
do $certification$
declare
  v_readiness jsonb;
  v_fingerprint text;
  v_existing public.leghevo_model_certifications%rowtype;
  v_false text[];
begin
  v_readiness := public.get_account_services_schema_readiness_v1();

  select array_agg(item.key order by item.key)
  into v_false
  from jsonb_each(v_readiness -> 'checks') item
  where item.value <> 'true'::jsonb;

  if coalesce((v_readiness ->> 'healthy')::boolean, false) is not true
    or coalesce((v_readiness ->> 'checkCount')::integer, 0) <> 20
    or coalesce((v_readiness ->> 'passedCount')::integer, 0) <> 20 then
    raise exception
      'LEGHEVO v0.62.0 controlli falliti: %. Dettaglio: %',
      coalesce(array_to_string(v_false, ', '), 'diagnostica non valida'),
      coalesce(v_readiness -> 'checks', '{}'::jsonb)::text;
  end if;

  v_fingerprint := public.compute_account_services_schema_fingerprint_v1();

  select certification.*
  into v_existing
  from public.leghevo_model_certifications certification
  where certification.model_key = 'account_services_v1';

  if found then
    if v_existing.model_version <> 1
      or v_existing.application_version <> '0.62.0'
      or v_existing.schema_fingerprint <> v_fingerprint then
      raise exception
        'La certificazione esistente non coincide con il modello account services v1.';
    end if;
  else
    insert into public.leghevo_model_certifications (
      model_key,
      model_version,
      application_version,
      schema_fingerprint,
      readiness
    ) values (
      'account_services_v1',
      1,
      '0.62.0',
      v_fingerprint,
      v_readiness
    );
  end if;
end;
$certification$;

-- Stato certificato personale del modello account services.
create or replace function public.get_my_account_services_model_closure_integrity_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_readiness jsonb;
  v_fingerprint text;
  v_certification public.leghevo_model_certifications%rowtype;
  v_hub jsonb;
  v_schema_certified boolean := false;
  v_operational_healthy boolean := false;
begin
  if auth.uid() is null then
    raise exception 'Devi effettuare l''accesso.';
  end if;

  v_readiness := public.get_account_services_schema_readiness_v1();
  v_fingerprint := public.compute_account_services_schema_fingerprint_v1();
  v_hub := public.get_my_account_service_hub_v1();

  select certification.*
  into v_certification
  from public.leghevo_model_certifications certification
  where certification.model_key = 'account_services_v1';

  v_schema_certified :=
    found
    and v_certification.model_version = 1
    and v_certification.application_version = '0.62.0'
    and v_certification.schema_fingerprint = v_fingerprint
    and coalesce((v_readiness ->> 'healthy')::boolean, false)
    and coalesce((v_readiness ->> 'checkCount')::integer, 0) = 20
    and coalesce((v_readiness ->> 'passedCount')::integer, 0) = 20;

  v_operational_healthy :=
    coalesce((v_hub ->> 'allProtected')::boolean, false)
    and coalesce((v_hub ->> 'protectedServiceCount')::integer, 0) = 8
    and coalesce((v_hub ->> 'totalServiceCount')::integer, 0) = 8;

  return jsonb_build_object(
    'healthy', v_schema_certified and v_operational_healthy,
    'schemaCertified', v_schema_certified,
    'operationalHealthy', v_operational_healthy,
    'policy', 'account_services_model_closed_v1',
    'modelKey', 'account_services_v1',
    'modelVersion', 1,
    'applicationVersion', '0.62.0',
    'certifiedAt', v_certification.certified_at,
    'schemaFingerprint', v_fingerprint,
    'storedSchemaFingerprint', v_certification.schema_fingerprint,
    'fingerprintStable',
      v_certification.schema_fingerprint = v_fingerprint,
    'schemaReadiness', v_readiness,
    'serviceHub', v_hub
  );
end;
$$;

create or replace function public.get_my_account_center_v5()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'Devi effettuare l''accesso.';
  end if;

  return public.get_my_account_center_v4()
    || jsonb_build_object(
      'accountServicesModelClosure',
        public.get_my_account_services_model_closure_integrity_v1(),
      'generatedAt', now()
    );
end;
$$;

revoke all on function public.get_account_services_schema_readiness_v1()
from public, anon, authenticated;
revoke all on function public.compute_account_services_schema_fingerprint_v1()
from public, anon, authenticated;
revoke all on function public.get_my_account_services_model_closure_integrity_v1()
from public, anon;
revoke all on function public.get_my_account_center_v5()
from public, anon;

grant execute on function public.get_my_account_services_model_closure_integrity_v1()
to authenticated;
grant execute on function public.get_my_account_center_v5()
to authenticated;

commit;

-- Diagnostica finale: devono risultare esattamente 20 valori true.
select
  to_regclass('public.leghevo_model_certifications') is not null
    as certification_table_ready,
  exists (
    select 1
    from public.leghevo_model_certifications certification
    where certification.model_key = 'account_services_v1'
  ) as certification_row_ready,
  exists (
    select 1
    from public.leghevo_model_certifications certification
    where certification.model_key = 'account_services_v1'
      and certification.model_version = 1
      and certification.application_version = '0.62.0'
  ) as certification_version_ready,
  exists (
    select 1
    from public.leghevo_model_certifications certification
    where certification.model_key = 'account_services_v1'
      and length(certification.schema_fingerprint) = 32
  ) as certification_fingerprint_ready,
  to_regprocedure('public.get_account_services_schema_readiness_v1()')
    is not null as schema_readiness_ready,
  to_regprocedure(
    'public.compute_account_services_schema_fingerprint_v1()'
  ) is not null as schema_fingerprint_function_ready,
  to_regprocedure(
    'public.get_my_account_services_model_closure_integrity_v1()'
  ) is not null as model_closure_integrity_ready,
  to_regprocedure('public.get_my_account_center_v5()')
    is not null as account_center_v5_ready,
  exists (
    select 1
    from pg_catalog.pg_trigger trigger_row
    where not trigger_row.tgisinternal
      and trigger_row.tgrelid =
        to_regclass('public.leghevo_model_certifications')
      and trigger_row.tgname = 'leghevo_model_certifications_immutable'
  ) as certification_immutable_ready,
  coalesce((
    select relation_row.relrowsecurity
    from pg_catalog.pg_class relation_row
    where relation_row.oid =
      to_regclass('public.leghevo_model_certifications')
  ), false) as certification_rls_ready,
  public.leghevo_safe_table_privilege_v1(
    'authenticated', 'public.leghevo_model_certifications', 'SELECT'
  ) as authenticated_certification_read_ready,
  not public.leghevo_safe_table_privilege_v1(
    'authenticated', 'public.leghevo_model_certifications', 'INSERT'
  ) as certification_direct_insert_blocked,
  not public.leghevo_safe_table_privilege_v1(
    'authenticated', 'public.leghevo_model_certifications', 'UPDATE'
  ) as certification_direct_update_blocked,
  not public.leghevo_safe_table_privilege_v1(
    'authenticated', 'public.leghevo_model_certifications', 'DELETE'
  ) as certification_direct_delete_blocked,
  public.leghevo_safe_function_privilege_v1(
    'authenticated',
    'public.get_my_account_services_model_closure_integrity_v1()',
    'EXECUTE'
  ) as authenticated_model_closure_ready,
  public.leghevo_safe_function_privilege_v1(
    'authenticated',
    'public.get_my_account_center_v5()',
    'EXECUTE'
  ) as authenticated_account_center_v5_ready,
  not public.leghevo_safe_function_privilege_v1(
    'anon',
    'public.get_my_account_services_model_closure_integrity_v1()',
    'EXECUTE'
  ) as anonymous_model_closure_blocked,
  not public.leghevo_safe_function_privilege_v1(
    'anon',
    'public.get_my_account_center_v5()',
    'EXECUTE'
  ) as anonymous_account_center_v5_blocked,
  coalesce((
    public.get_account_services_schema_readiness_v1()
    ->> 'checkCount'
  )::integer, 0) = 20
  and coalesce((
    public.get_account_services_schema_readiness_v1()
    ->> 'passedCount'
  )::integer, 0) = 20 as schema_twenty_checks_ready,
  coalesce((
    public.get_account_services_schema_readiness_v1()
    ->> 'healthy'
  )::boolean, false)
  and exists (
    select 1
    from public.leghevo_model_certifications certification
    where certification.model_key = 'account_services_v1'
      and certification.schema_fingerprint =
        public.compute_account_services_schema_fingerprint_v1()
  ) as account_services_model_closed;
