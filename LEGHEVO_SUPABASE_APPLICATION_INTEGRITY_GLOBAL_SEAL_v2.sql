-- LEGHEVO v0.62.33
-- Sigillo globale di integrità applicativa.
-- Primo blocco dello Sviluppo 9: certifica con un'unica impronta la coerenza
-- tra ruoli, mercato, competizione, giornata, competizioni speciali,
-- servizi account e affidabilità provider.
-- Migrazione idempotente e non distruttiva.

begin;

-- Preflight: la chiusura provider v0.62.32 deve essere installata e integra.
do $preflight$
declare
  v_missing text[] := array[]::text[];
  v_signature text;
  v_predecessor jsonb;
begin
  if to_regclass('public.leghevo_model_certifications') is null then
    v_missing := array_append(v_missing,
      'tabella public.leghevo_model_certifications');
  end if;

  foreach v_signature in array array[
    'public.get_provider_reliability_model_closure_integrity_v1()',
    'public.get_provider_reliability_schema_readiness_v1()',
    'public.compute_provider_reliability_schema_fingerprint_v1()',
    'public.get_league_role_security_state(uuid)',
    'public.get_league_market_integrity_v4(uuid)',
    'public.get_league_competition_integrity_v1(uuid)',
    'public.compute_matchday_model_schema_fingerprint_v1()',
    'public.compute_special_competitions_schema_fingerprint_v1()',
    'public.compute_account_services_schema_fingerprint_v1()',
    'public.get_league_provider_sync_health_v31(uuid)',
    'public.get_league_season_state_v10(uuid)',
    'public.get_league_management_state_v20(uuid)'
  ] loop
    if to_regprocedure(v_signature) is null then
      v_missing := array_append(v_missing, 'funzione ' || v_signature);
    end if;
  end loop;

  if cardinality(v_missing) > 0 then
    raise exception
      'Preflight v0.62.33 non superato. Oggetti mancanti: %',
      array_to_string(v_missing, '; ');
  end if;

  v_predecessor := public.get_provider_reliability_model_closure_integrity_v1();
  if (select count(*) from jsonb_each(v_predecessor)) <> 20
    or exists(
      select 1 from jsonb_each(v_predecessor) item
      where jsonb_typeof(item.value) is distinct from 'boolean'
         or item.value is distinct from 'true'::jsonb
    ) then
    raise exception
      'Preflight v0.62.33 non superato: la v0.62.32 non risulta integra [%].',
      v_predecessor;
  end if;
end;
$preflight$;

-- Helper interno per verificare una certificazione già esistente contro la
-- fingerprint corrente. Nessuna certificazione precedente viene aggiornata.
create or replace function public.leghevo_model_certification_matches_v1(
  p_model_key text,
  p_model_version integer,
  p_schema_fingerprint text
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select exists(
    select 1
    from public.leghevo_model_certifications certification
    where certification.model_key = p_model_key
      and certification.model_version = p_model_version
      and certification.schema_fingerprint = p_schema_fingerprint
      and length(certification.schema_fingerprint) = 32
  );
$function$;

revoke all on function public.leghevo_model_certification_matches_v1(
  text, integer, text
) from public, anon, authenticated;
grant execute on function public.leghevo_model_certification_matches_v1(
  text, integer, text
) to service_role;

-- Le sette aree funzionali e i tredici contratti trasversali vengono
-- riassunti in esattamente venti capacità strutturali.
create or replace function public.get_leghevo_application_schema_readiness_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_role_model boolean := false;
  v_market_model boolean := false;
  v_competition_model boolean := false;
  v_matchday_model boolean := false;
  v_special_competitions boolean := false;
  v_account_services boolean := false;
  v_provider_reliability boolean := false;
  v_membership_authorization boolean := false;
  v_market_competition_boundary boolean := false;
  v_competition_matchday_boundary boolean := false;
  v_matchday_season_boundary boolean := false;
  v_season_rollover_boundary boolean := false;
  v_provider_market_boundary boolean := false;
  v_provider_result_boundary boolean := false;
  v_privacy_legal_boundary boolean := false;
  v_notification_support_boundary boolean := false;
  v_immutable_audit boolean := false;
  v_rls_write_boundary boolean := false;
  v_realtime_surface boolean := false;
  v_endpoint_chain boolean := false;
  v_table_name text;
  v_passed integer := 0;
begin
  v_role_model :=
    to_regprocedure('public.get_league_role_security_state(uuid)') is not null
    and to_regprocedure(
      'public.get_league_role_control_state_v2(uuid,integer)') is not null
    and to_regprocedure(
      'public.set_league_member_role_guarded(uuid,uuid,public.member_role,bigint)')
      is not null
    and to_regprocedure(
      'public.transfer_league_presidency_guarded(uuid,uuid,bigint)')
      is not null
    and to_regprocedure(
      'public.remove_league_member_guarded(uuid,uuid,bigint)') is not null
    and not has_function_privilege(
      'authenticated',
      'public.set_league_member_role(uuid,uuid,public.member_role)',
      'EXECUTE')
    and not has_function_privilege(
      'authenticated', 'public.transfer_league_presidency(uuid,uuid)',
      'EXECUTE')
    and not has_function_privilege(
      'authenticated', 'public.remove_league_member(uuid,uuid)', 'EXECUTE');

  v_market_model :=
    to_regprocedure('public.get_league_market_integrity_v4(uuid)') is not null
    and to_regprocedure('public.sign_free_agent(uuid,uuid)') is not null
    and to_regprocedure('public.release_roster_player(uuid,uuid)') is not null
    and to_regprocedure('public.respond_trade_offer(uuid,boolean)') is not null
    and to_regprocedure('public.place_bid(uuid,integer)') is not null
    and to_regprocedure('public.finalize_auction_item(uuid)') is not null;

  foreach v_table_name in array array[
    'fantasy_teams','roster_entries','team_transactions','trade_offers',
    'trade_offer_players','trade_player_reservations',
    'trade_credit_reservations','auctions','auction_items','bids'
  ] loop
    v_market_model := v_market_model
      and not has_table_privilege(
        'authenticated', 'public.' || v_table_name, 'INSERT')
      and not has_table_privilege(
        'authenticated', 'public.' || v_table_name, 'UPDATE')
      and not has_table_privilege(
        'authenticated', 'public.' || v_table_name, 'DELETE')
      and not has_table_privilege(
        'authenticated', 'public.' || v_table_name, 'TRUNCATE');
  end loop;

  v_competition_model :=
    to_regprocedure('public.get_league_competition_integrity_v1(uuid)')
      is not null
    and to_regprocedure('public.compute_league_calendar_fingerprint(uuid)')
      is not null
    and to_regprocedure(
      'public.generate_head_to_head_calendar_guarded_v2(uuid,text,smallint,timestamp with time zone,boolean)')
      is not null
    and to_regprocedure('public.start_league_competition_guarded_v4(uuid)')
      is not null
    and exists(
      select 1 from pg_catalog.pg_trigger trigger_row
      where trigger_row.tgrelid = 'public.leagues'::regclass
        and trigger_row.tgname = 'provider_competition_start_activation_guard'
        and trigger_row.tgenabled = 'A'
        and not trigger_row.tgisinternal
    );

  v_matchday_model :=
    public.leghevo_model_certification_matches_v1(
      'matchday_lifecycle_v1', 1,
      public.compute_matchday_model_schema_fingerprint_v1())
    and to_regprocedure(
      'public.get_league_matchday_model_closure_integrity_v1(uuid)')
      is not null;

  v_special_competitions :=
    public.leghevo_model_certification_matches_v1(
      'special_competitions_v1', 1,
      public.compute_special_competitions_schema_fingerprint_v1())
    and to_regprocedure(
      'public.get_league_special_competitions_model_closure_integrity_v1(uuid)')
      is not null;

  v_account_services :=
    public.leghevo_model_certification_matches_v1(
      'account_services_v1', 1,
      public.compute_account_services_schema_fingerprint_v1())
    and to_regprocedure(
      'public.get_my_account_services_model_closure_integrity_v1()')
      is not null;

  v_provider_reliability :=
    public.leghevo_model_certification_matches_v1(
      'provider_reliability_v1', 1,
      public.compute_provider_reliability_schema_fingerprint_v1())
    and public.provider_reliability_diagnostic_all_true_v1(
      public.get_provider_reliability_model_closure_integrity_v1());

  v_membership_authorization :=
    coalesce((select relation_row.relrowsecurity
      from pg_catalog.pg_class relation_row
      where relation_row.oid = 'public.league_members'::regclass), false)
    and coalesce((select relation_row.relrowsecurity
      from pg_catalog.pg_class relation_row
      where relation_row.oid = 'public.league_role_events'::regclass), false)
    and to_regprocedure('public.get_league_access_session(uuid)') is not null
    and to_regprocedure(
      'public.get_league_role_control_state_v2(uuid,integer)') is not null;

  v_market_competition_boundary :=
    to_regprocedure(
      'public.assert_provider_season_bootstrap_ready_v1(uuid,text)') is not null
    and exists(
      select 1 from pg_catalog.pg_trigger trigger_row
      where trigger_row.tgname = 'provider_season_bootstrap_roster_guard'
        and trigger_row.tgenabled = 'A'
        and not trigger_row.tgisinternal
    )
    and exists(
      select 1 from pg_catalog.pg_trigger trigger_row
      where trigger_row.tgname = 'provider_season_bootstrap_auction_item_guard'
        and trigger_row.tgenabled = 'A'
        and not trigger_row.tgisinternal
    );

  v_competition_matchday_boundary :=
    to_regprocedure('public.start_league_competition_guarded_v4(uuid)')
      is not null
    and to_regprocedure(
      'public.save_team_lineup_guarded_v1(uuid,uuid,text,uuid[],uuid[],integer,uuid)') is not null
    and exists(
      select 1 from pg_catalog.pg_trigger trigger_row
      where trigger_row.tgname = 'provider_competition_start_activation_guard'
        and trigger_row.tgenabled = 'A'
        and not trigger_row.tgisinternal
    );

  v_matchday_season_boundary :=
    to_regprocedure('public.complete_league_season_guarded_v3(uuid,uuid)')
      is not null
    and to_regprocedure(
      'public.reconcile_provider_season_completion_gate_v1(uuid)')
      is not null
    and exists(
      select 1 from pg_catalog.pg_trigger trigger_row
      where trigger_row.tgname = 'zz_league_season_official_snapshot_writer'
        and trigger_row.tgenabled = 'A'
        and not trigger_row.tgisinternal
    );

  v_season_rollover_boundary :=
    to_regprocedure(
      'public.renew_league_season_guarded_v3(uuid,text,uuid)') is not null
    and exists(
      select 1 from pg_catalog.pg_trigger trigger_row
      where trigger_row.tgname = 'league_season_rollovers_certified_guard'
        and trigger_row.tgenabled = 'A'
        and not trigger_row.tgisinternal
    )
    and exists(
      select 1 from pg_catalog.pg_trigger trigger_row
      where trigger_row.tgname = 'leagues_season_lineage_link_guard'
        and trigger_row.tgenabled = 'A'
        and not trigger_row.tgisinternal
    );

  v_provider_market_boundary :=
    to_regclass('public.provider_season_bootstrap_certificates') is not null
    and to_regclass('public.provider_player_catalog_heads') is not null
    and exists(
      select 1 from pg_catalog.pg_trigger trigger_row
      where trigger_row.tgname = 'provider_season_bootstrap_catalog_reconcile'
        and trigger_row.tgenabled = 'A'
        and not trigger_row.tgisinternal
    );

  v_provider_result_boundary :=
    to_regprocedure(
      'public.get_provider_score_consumption_state_v1(uuid)') is not null
    and to_regprocedure(
      'public.compute_provider_official_result_impact_v1(uuid)') is not null
    and to_regprocedure(
      'public.reconcile_provider_official_result_lineage_v1(uuid)')
      is not null
    and to_regprocedure(
      'public.compute_provider_matchday_progression_gate_v1(uuid,uuid,bigint)') is not null;

  v_privacy_legal_boundary :=
    to_regclass('public.legal_document_releases') is not null
    and to_regclass('public.privacy_consent_events') is not null
    and to_regclass('public.data_rights_requests') is not null
    and to_regprocedure('public.get_my_privacy_center_v4()') is not null
    and to_regprocedure('public.get_legal_acceptance_safety_integrity_v1()') is not null
    and to_regprocedure('public.export_my_personal_data_guarded_v1(uuid)') is not null;

  v_notification_support_boundary :=
    to_regclass('public.user_notifications') is not null
    and to_regclass('public.user_push_devices') is not null
    and to_regclass('public.support_requests') is not null
    and to_regclass('public.support_request_messages') is not null
    and to_regprocedure('public.get_my_notification_center_v2(integer)')
      is not null
    and to_regprocedure('public.get_my_support_center_v2()') is not null;

  v_immutable_audit := not exists(
    select 1
    from (values
      ('account_service_events','account_service_events_immutable'),
      ('provider_season_bootstrap_events','provider_season_bootstrap_events_immutable'),
      ('provider_competition_start_events','provider_competition_start_events_immutable'),
      ('league_season_official_snapshot_events','league_season_official_snapshot_events_immutable'),
      ('league_season_rollover_events','league_season_rollover_events_immutable')
    ) required(table_name, trigger_name)
    where to_regclass('public.' || required.table_name) is null
       or not exists(
         select 1 from pg_catalog.pg_trigger trigger_row
         where trigger_row.tgrelid = to_regclass('public.' || required.table_name)
           and trigger_row.tgname = required.trigger_name
           and trigger_row.tgenabled in ('O','A')
           and not trigger_row.tgisinternal
       )
  );

  v_rls_write_boundary := not exists(
    select 1
    from (values
      ('league_members'),('fantasy_teams'),('roster_entries'),
      ('trade_offers'),('fantasy_fixtures'),('lineups'),
      ('user_notifications'),('support_requests'),
      ('provider_operational_incidents'),('leghevo_model_certifications')
    ) required(table_name)
    where to_regclass('public.' || required.table_name) is null
       or not coalesce((select relation_row.relrowsecurity
         from pg_catalog.pg_class relation_row
         where relation_row.oid = to_regclass('public.' || required.table_name)),
         false)
  );

  v_realtime_surface := exists(
    select 1 from pg_catalog.pg_publication publication
    where publication.pubname = 'supabase_realtime'
  ) and not exists(
    select 1
    from (values
      ('league_role_events'),('trade_offers'),
      ('user_notifications'),('provider_operational_incident_events'),
      ('provider_season_bootstrap_events'),
      ('provider_competition_start_events')
    ) required(table_name)
    where not exists(
      select 1 from pg_catalog.pg_publication_tables publication_table
      where publication_table.pubname = 'supabase_realtime'
        and publication_table.schemaname = 'public'
        and publication_table.tablename = required.table_name
    )
  );

  v_endpoint_chain :=
    to_regprocedure('public.get_league_provider_sync_health_v32(uuid)')
      is not null
    and to_regprocedure('public.get_league_season_state_v11(uuid)') is not null
    and to_regprocedure('public.get_league_management_state_v21(uuid)')
      is not null
    and to_regprocedure('public.get_leghevo_application_integrity_model_v1()')
      is not null;

  select count(*)::integer into v_passed
  from jsonb_each(jsonb_build_object(
    'roleModelReady', v_role_model,
    'marketModelReady', v_market_model,
    'competitionModelReady', v_competition_model,
    'matchdayModelReady', v_matchday_model,
    'specialCompetitionsReady', v_special_competitions,
    'accountServicesReady', v_account_services,
    'providerReliabilityReady', v_provider_reliability,
    'membershipAuthorizationReady', v_membership_authorization,
    'marketCompetitionBoundaryReady', v_market_competition_boundary,
    'competitionMatchdayBoundaryReady', v_competition_matchday_boundary,
    'matchdaySeasonBoundaryReady', v_matchday_season_boundary,
    'seasonRolloverBoundaryReady', v_season_rollover_boundary,
    'providerMarketBoundaryReady', v_provider_market_boundary,
    'providerResultBoundaryReady', v_provider_result_boundary,
    'privacyLegalBoundaryReady', v_privacy_legal_boundary,
    'notificationSupportBoundaryReady', v_notification_support_boundary,
    'immutableAuditReady', v_immutable_audit,
    'rlsWriteBoundaryReady', v_rls_write_boundary,
    'realtimeSurfaceReady', v_realtime_surface,
    'endpointChainReady', v_endpoint_chain
  )) item
  where item.value = 'true'::jsonb;

  return jsonb_build_object(
    'healthy', v_passed = 20,
    'checkCount', 20,
    'passedCount', v_passed,
    'checks', jsonb_build_object(
      'roleModelReady', v_role_model,
      'marketModelReady', v_market_model,
      'competitionModelReady', v_competition_model,
      'matchdayModelReady', v_matchday_model,
      'specialCompetitionsReady', v_special_competitions,
      'accountServicesReady', v_account_services,
      'providerReliabilityReady', v_provider_reliability,
      'membershipAuthorizationReady', v_membership_authorization,
      'marketCompetitionBoundaryReady', v_market_competition_boundary,
      'competitionMatchdayBoundaryReady', v_competition_matchday_boundary,
      'matchdaySeasonBoundaryReady', v_matchday_season_boundary,
      'seasonRolloverBoundaryReady', v_season_rollover_boundary,
      'providerMarketBoundaryReady', v_provider_market_boundary,
      'providerResultBoundaryReady', v_provider_result_boundary,
      'privacyLegalBoundaryReady', v_privacy_legal_boundary,
      'notificationSupportBoundaryReady', v_notification_support_boundary,
      'immutableAuditReady', v_immutable_audit,
      'rlsWriteBoundaryReady', v_rls_write_boundary,
      'realtimeSurfaceReady', v_realtime_surface,
      'endpointChainReady', v_endpoint_chain
    )
  );
end;
$function$;

revoke all on function public.get_leghevo_application_schema_readiness_v1()
from public, anon, authenticated;
grant execute on function public.get_leghevo_application_schema_readiness_v1()
to service_role;

-- Fingerprint globale: include le certificazioni già emesse e le definizioni
-- delle funzioni, trigger, policy e ACL che collegano i modelli tra loro.
create or replace function public.compute_leghevo_application_schema_fingerprint_v1()
returns text
language sql
stable
security definer
set search_path = ''
as $function$
  with certification_parts as (
    select
      'certification|' || certification.model_key || '|' ||
      certification.model_version::text || '|' ||
      certification.application_version || '|' ||
      certification.schema_fingerprint as part
    from public.leghevo_model_certifications certification
    where certification.model_key = any(array[
      'matchday_lifecycle_v1','special_competitions_v1',
      'account_services_v1','provider_reliability_v1'
    ])
  ), function_parts as (
    select
      'function|' || procedure_row.oid::regprocedure::text || '|' ||
      pg_catalog.pg_get_functiondef(procedure_row.oid) as part
    from (values
      ('public.get_league_role_security_state(uuid)'),
      ('public.get_league_market_integrity_v4(uuid)'),
      ('public.get_league_competition_integrity_v1(uuid)'),
      ('public.get_league_matchday_model_closure_integrity_v1(uuid)'),
      ('public.get_league_special_competitions_model_closure_integrity_v1(uuid)'),
      ('public.get_my_account_services_model_closure_integrity_v1()'),
      ('public.get_league_provider_reliability_model_v1(uuid)'),
      ('public.get_leghevo_application_schema_readiness_v1()'),
      ('public.get_leghevo_application_integrity_model_v1()'),
      ('public.get_league_provider_sync_health_v32(uuid)'),
      ('public.get_league_season_state_v11(uuid)'),
      ('public.get_league_management_state_v21(uuid)'),
      ('public.start_league_competition_guarded_v4(uuid)'),
      ('public.complete_league_season_guarded_v3(uuid,uuid)'),
      ('public.renew_league_season_guarded_v3(uuid,text,uuid)')
    ) required(signature)
    join pg_catalog.pg_proc procedure_row
      on procedure_row.oid = to_regprocedure(required.signature)
  ), trigger_parts as (
    select
      'trigger|' || trigger_row.tgrelid::regclass::text || '|' ||
      trigger_row.tgname::text || '|' ||
      trigger_row.tgenabled::text || '|' ||
      pg_catalog.pg_get_triggerdef(trigger_row.oid, true) as part
    from pg_catalog.pg_trigger trigger_row
    where not trigger_row.tgisinternal
      and trigger_row.tgname = any(array[
        'provider_season_bootstrap_roster_guard',
        'provider_season_bootstrap_auction_item_guard',
        'provider_season_bootstrap_calendar_guard',
        'provider_competition_start_activation_guard',
        'zz_league_season_official_snapshot_writer',
        'league_season_rollovers_certified_guard',
        'leagues_season_lineage_link_guard',
        'leghevo_model_certifications_immutable'
      ])
  ), policy_parts as (
    select
      'policy|' || policy_row.schemaname || '.' || policy_row.tablename || '|' ||
      policy_row.policyname || '|' || policy_row.cmd || '|' ||
      coalesce(policy_row.qual, '') || '|' ||
      coalesce(policy_row.with_check, '') as part
    from pg_catalog.pg_policies policy_row
    where policy_row.schemaname = 'public'
      and policy_row.tablename = any(array[
        'league_members','fantasy_teams','roster_entries','trade_offers',
        'fantasy_fixtures','lineups','user_notifications','support_requests',
        'provider_operational_incidents','leghevo_model_certifications'
      ])
  ), acl_parts as (
    select
      'acl|' || relation_row.oid::regclass::text || '|' ||
      coalesce(relation_row.relacl::text, '') as part
    from (values
      ('public.league_members'),
      ('public.fantasy_teams'),
      ('public.roster_entries'),
      ('public.trade_offers'),
      ('public.fantasy_fixtures'),
      ('public.lineups'),
      ('public.user_notifications'),
      ('public.support_requests'),
      ('public.provider_operational_incidents'),
      ('public.leghevo_model_certifications')
    ) required(relation_name)
    join pg_catalog.pg_class relation_row
      on relation_row.oid = to_regclass(required.relation_name)
  ), all_parts as (
    select part from certification_parts
    union all select part from function_parts
    union all select part from trigger_parts
    union all select part from policy_parts
    union all select part from acl_parts
  )
  select pg_catalog.md5(pg_catalog.string_agg(part, E'\n' order by part))
  from all_parts;
$function$;

revoke all on function public.compute_leghevo_application_schema_fingerprint_v1()
from public, anon, authenticated;
grant execute on function public.compute_leghevo_application_schema_fingerprint_v1()
to service_role;

-- Stato pubblico del sigillo globale. Nessun dato della singola lega viene
-- modificato: il risultato descrive esclusivamente lo schema installato.
create or replace function public.get_leghevo_application_integrity_model_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_readiness jsonb;
  v_fingerprint text;
  v_certification public.leghevo_model_certifications%rowtype;
  v_certified boolean := false;
  v_certification_found boolean := false;
begin
  v_readiness := public.get_leghevo_application_schema_readiness_v1();
  v_fingerprint := public.compute_leghevo_application_schema_fingerprint_v1();

  select certification.* into v_certification
  from public.leghevo_model_certifications certification
  where certification.model_key = 'application_integrity_v1';

  v_certification_found := found;
  v_certified := v_certification_found
    and v_certification.model_version = 1
    and v_certification.application_version = '0.62.33'
    and v_certification.schema_fingerprint = v_fingerprint
    and coalesce((v_readiness ->> 'healthy')::boolean, false)
    and coalesce((v_readiness ->> 'checkCount')::integer, 0) = 20
    and coalesce((v_readiness ->> 'passedCount')::integer, 0) = 20;

  return jsonb_build_object(
    'protected', v_certified,
    'modelClosed', v_certified,
    'healthy', v_certified,
    'schemaCertified', v_certified,
    'status', case when v_certified then 'certified' else 'affected' end,
    'reasonCode', case
      when v_certified then 'application_integrity.certified'
      when not v_certification_found then 'application_integrity.certification_missing'
      else 'application_integrity.schema_fingerprint_changed'
    end,
    'modelKey', 'application_integrity_v1',
    'modelVersion', 1,
    'applicationVersion', '0.62.33',
    'certifiedAt', v_certification.certified_at,
    'schemaFingerprint', v_fingerprint,
    'storedSchemaFingerprint', v_certification.schema_fingerprint,
    'fingerprintStable',
      v_certification.schema_fingerprint is not distinct from v_fingerprint,
    'checkCount', coalesce((v_readiness ->> 'checkCount')::integer, 0),
    'passedCount', coalesce((v_readiness ->> 'passedCount')::integer, 0),
    'checks', coalesce(v_readiness -> 'checks', '{}'::jsonb)
  );
end;
$function$;

revoke all on function public.get_leghevo_application_integrity_model_v1()
from public, anon;
grant execute on function public.get_leghevo_application_integrity_model_v1()
to authenticated, service_role;

-- Endpoint terminali: mantengono i fallback precedenti ma aggiungono il
-- sigillo applicativo globale a Centro Operativo, stagione e Direzione.
create or replace function public.get_league_provider_sync_health_v32(
  p_league_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_base jsonb;
  v_application jsonb;
begin
  v_base := public.get_league_provider_sync_health_v31(p_league_id);
  v_application := public.get_leghevo_application_integrity_model_v1();

  return v_base || jsonb_build_object(
    'protected', coalesce((v_base ->> 'protected')::boolean, false)
      and coalesce((v_application ->> 'protected')::boolean, false),
    'healthy', coalesce((v_base ->> 'healthy')::boolean, false)
      and coalesce((v_application ->> 'healthy')::boolean, false),
    'applicationIntegrityModel', v_application
  );
end;
$function$;

revoke all on function public.get_league_provider_sync_health_v32(uuid)
from public, anon, service_role;
grant execute on function public.get_league_provider_sync_health_v32(uuid)
to authenticated;

create or replace function public.get_league_season_state_v11(p_league_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_base jsonb;
  v_application jsonb;
begin
  v_base := public.get_league_season_state_v10(p_league_id);
  v_application := public.get_leghevo_application_integrity_model_v1();

  return v_base || jsonb_build_object(
    'applicationIntegrityModelProtected',
      coalesce((v_application ->> 'protected')::boolean, false),
    'applicationIntegrityModelClosed',
      coalesce((v_application ->> 'modelClosed')::boolean, false),
    'applicationIntegrityModelStatus', v_application ->> 'status',
    'applicationIntegrityModelReason', v_application ->> 'reasonCode'
  );
end;
$function$;

revoke all on function public.get_league_season_state_v11(uuid)
from public, anon;
grant execute on function public.get_league_season_state_v11(uuid)
to authenticated;

create or replace function public.get_league_management_state_v21(
  p_league_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_base jsonb;
  v_application jsonb;
  v_checks jsonb;
begin
  v_base := public.get_league_management_state_v20(p_league_id);
  v_application := public.get_leghevo_application_integrity_model_v1();
  v_checks := coalesce(v_base -> 'checks', '{}'::jsonb)
    || jsonb_build_object(
      'applicationIntegrityModelProtected',
        coalesce((v_application ->> 'protected')::boolean, false),
      'applicationIntegrityModelClosed',
        coalesce((v_application ->> 'modelClosed')::boolean, false)
    );

  return v_base || jsonb_build_object(
    'applicationIntegrityModelProtected',
      coalesce((v_application ->> 'protected')::boolean, false),
    'applicationIntegrityModelClosed',
      coalesce((v_application ->> 'modelClosed')::boolean, false),
    'applicationIntegrityModelStatus', v_application ->> 'status',
    'applicationIntegrityModelReason', v_application ->> 'reasonCode',
    'applicationIntegrityModelCertifiedAt', v_application -> 'certifiedAt',
    'checks', v_checks
  );
end;
$function$;

revoke all on function public.get_league_management_state_v21(uuid)
from public, anon;
grant execute on function public.get_league_management_state_v21(uuid)
to authenticated;

-- Registra il sigillo soltanto dopo il superamento delle venti capacità.
do $certification$
declare
  v_readiness jsonb;
  v_fingerprint text;
  v_existing public.leghevo_model_certifications%rowtype;
  v_false text[];
begin
  v_readiness := public.get_leghevo_application_schema_readiness_v1();

  select array_agg(item.key order by item.key)
  into v_false
  from jsonb_each(v_readiness -> 'checks') item
  where item.value is distinct from 'true'::jsonb;

  if not coalesce((v_readiness ->> 'healthy')::boolean, false)
    or coalesce((v_readiness ->> 'checkCount')::integer, 0) <> 20
    or coalesce((v_readiness ->> 'passedCount')::integer, 0) <> 20 then
    raise exception
      'LEGHEVO v0.62.33 controlli falliti: %. Dettaglio: %',
      coalesce(array_to_string(v_false, ', '), 'diagnostica non valida'),
      coalesce(v_readiness -> 'checks', '{}'::jsonb)::text;
  end if;

  v_fingerprint := public.compute_leghevo_application_schema_fingerprint_v1();

  select certification.* into v_existing
  from public.leghevo_model_certifications certification
  where certification.model_key = 'application_integrity_v1';

  if found then
    if v_existing.model_version <> 1
      or v_existing.application_version <> '0.62.33'
      or v_existing.schema_fingerprint <> v_fingerprint then
      raise exception
        'La certificazione esistente non coincide con application integrity v1.';
    end if;
  else
    insert into public.leghevo_model_certifications(
      model_key, model_version, application_version,
      schema_fingerprint, readiness
    ) values (
      'application_integrity_v1', 1, '0.62.33',
      v_fingerprint, v_readiness
    );
  end if;
end;
$certification$;

-- Diagnostica finale della v0.62.33: esattamente venti booleani.
create or replace function public.get_leghevo_application_integrity_seal_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_predecessor jsonb;
  v_readiness jsonb;
  v_fingerprint text;
  v_certification public.leghevo_model_certifications%rowtype;
  v_application_def text := coalesce(pg_catalog.pg_get_functiondef(
    to_regprocedure('public.get_leghevo_application_integrity_model_v1()')), '');
  v_health_def text := coalesce(pg_catalog.pg_get_functiondef(
    to_regprocedure('public.get_league_provider_sync_health_v32(uuid)')), '');
  v_season_def text := coalesce(pg_catalog.pg_get_functiondef(
    to_regprocedure('public.get_league_season_state_v11(uuid)')), '');
  v_management_def text := coalesce(pg_catalog.pg_get_functiondef(
    to_regprocedure('public.get_league_management_state_v21(uuid)')), '');
  v_certification_found boolean := false;
begin
  v_predecessor := public.get_provider_reliability_model_closure_integrity_v1();
  v_readiness := public.get_leghevo_application_schema_readiness_v1();
  v_fingerprint := public.compute_leghevo_application_schema_fingerprint_v1();

  select certification.* into v_certification
  from public.leghevo_model_certifications certification
  where certification.model_key = 'application_integrity_v1';
  v_certification_found := found;

  return jsonb_build_object(
    'predecessor_ready',
      public.provider_reliability_diagnostic_all_true_v1(v_predecessor),
    'certification_table_ready',
      to_regclass('public.leghevo_model_certifications') is not null,
    'certification_row_ready', v_certification_found,
    'certification_version_ready',
      v_certification.model_version = 1
      and v_certification.application_version = '0.62.33',
    'certification_fingerprint_ready',
      v_certification.schema_fingerprint = v_fingerprint
      and length(v_fingerprint) = 32,
    'readiness_contract_ready',
      coalesce((v_readiness ->> 'checkCount')::integer, 0) = 20
      and coalesce((v_readiness ->> 'passedCount')::integer, 0) = 20
      and coalesce((v_readiness ->> 'healthy')::boolean, false),
    'role_model_ready',
      coalesce((v_readiness -> 'checks' ->> 'roleModelReady')::boolean, false),
    'market_model_ready',
      coalesce((v_readiness -> 'checks' ->> 'marketModelReady')::boolean, false),
    'competition_model_ready',
      coalesce((v_readiness -> 'checks' ->> 'competitionModelReady')::boolean, false),
    'matchday_model_ready',
      coalesce((v_readiness -> 'checks' ->> 'matchdayModelReady')::boolean, false),
    'special_competitions_ready',
      coalesce((v_readiness -> 'checks' ->> 'specialCompetitionsReady')::boolean, false),
    'account_services_ready',
      coalesce((v_readiness -> 'checks' ->> 'accountServicesReady')::boolean, false),
    'provider_reliability_ready',
      coalesce((v_readiness -> 'checks' ->> 'providerReliabilityReady')::boolean, false),
    'cross_module_boundaries_ready',
      coalesce((v_readiness -> 'checks' ->> 'membershipAuthorizationReady')::boolean, false)
      and coalesce((v_readiness -> 'checks' ->> 'marketCompetitionBoundaryReady')::boolean, false)
      and coalesce((v_readiness -> 'checks' ->> 'competitionMatchdayBoundaryReady')::boolean, false)
      and coalesce((v_readiness -> 'checks' ->> 'matchdaySeasonBoundaryReady')::boolean, false)
      and coalesce((v_readiness -> 'checks' ->> 'seasonRolloverBoundaryReady')::boolean, false)
      and coalesce((v_readiness -> 'checks' ->> 'providerMarketBoundaryReady')::boolean, false)
      and coalesce((v_readiness -> 'checks' ->> 'providerResultBoundaryReady')::boolean, false),
    'immutable_audit_ready',
      coalesce((v_readiness -> 'checks' ->> 'immutableAuditReady')::boolean, false),
    'rls_boundary_ready',
      coalesce((v_readiness -> 'checks' ->> 'rlsWriteBoundaryReady')::boolean, false),
    'realtime_surface_ready',
      coalesce((v_readiness -> 'checks' ->> 'realtimeSurfaceReady')::boolean, false),
    'application_model_rpc_ready',
      to_regprocedure('public.get_leghevo_application_integrity_model_v1()')
        is not null
      and position('application_integrity_v1' in v_application_def) > 0,
    'endpoint_chain_ready',
      to_regprocedure('public.get_league_provider_sync_health_v32(uuid)')
        is not null
      and to_regprocedure('public.get_league_season_state_v11(uuid)')
        is not null
      and to_regprocedure('public.get_league_management_state_v21(uuid)')
        is not null
      and position('get_league_provider_sync_health_v31' in v_health_def) > 0
      and position('get_league_season_state_v10' in v_season_def) > 0
      and position('get_league_management_state_v20' in v_management_def) > 0,
    'authenticated_read_ready',
      has_function_privilege('authenticated',
        'public.get_leghevo_application_integrity_model_v1()','EXECUTE')
      and has_function_privilege('authenticated',
        'public.get_league_provider_sync_health_v32(uuid)','EXECUTE')
      and has_function_privilege('authenticated',
        'public.get_league_season_state_v11(uuid)','EXECUTE')
      and has_function_privilege('authenticated',
        'public.get_league_management_state_v21(uuid)','EXECUTE')
      and has_table_privilege('authenticated',
        'public.leghevo_model_certifications','SELECT')
  );
end;
$function$;

revoke all on function public.get_leghevo_application_integrity_seal_v1()
from public, anon, authenticated;
grant execute on function public.get_leghevo_application_integrity_seal_v1()
to service_role;

-- L'esecuzione deve essere atomica: un singolo false annulla tutta la migrazione.
do $validation$
declare
  v_integrity jsonb;
  v_false text[];
begin
  v_integrity := public.get_leghevo_application_integrity_seal_v1();

  select array_agg(item.key order by item.key)
  into v_false
  from jsonb_each(v_integrity) item
  where jsonb_typeof(item.value) is distinct from 'boolean'
     or item.value is distinct from 'true'::jsonb;

  if (select count(*) from jsonb_each(v_integrity)) <> 20
    or cardinality(v_false) > 0 then
    raise exception
      'Validazione v0.62.33 non superata: %. Dettaglio: %',
      coalesce(array_to_string(v_false, ', '),
        'numero di controlli diverso da 20'),
      v_integrity;
  end if;
end;
$validation$;

commit;

select
  (public.get_leghevo_application_integrity_seal_v1()
    ->> 'predecessor_ready')::boolean as predecessor_ready,
  (public.get_leghevo_application_integrity_seal_v1()
    ->> 'certification_table_ready')::boolean as certification_table_ready,
  (public.get_leghevo_application_integrity_seal_v1()
    ->> 'certification_row_ready')::boolean as certification_row_ready,
  (public.get_leghevo_application_integrity_seal_v1()
    ->> 'certification_version_ready')::boolean as certification_version_ready,
  (public.get_leghevo_application_integrity_seal_v1()
    ->> 'certification_fingerprint_ready')::boolean as certification_fingerprint_ready,
  (public.get_leghevo_application_integrity_seal_v1()
    ->> 'readiness_contract_ready')::boolean as readiness_contract_ready,
  (public.get_leghevo_application_integrity_seal_v1()
    ->> 'role_model_ready')::boolean as role_model_ready,
  (public.get_leghevo_application_integrity_seal_v1()
    ->> 'market_model_ready')::boolean as market_model_ready,
  (public.get_leghevo_application_integrity_seal_v1()
    ->> 'competition_model_ready')::boolean as competition_model_ready,
  (public.get_leghevo_application_integrity_seal_v1()
    ->> 'matchday_model_ready')::boolean as matchday_model_ready,
  (public.get_leghevo_application_integrity_seal_v1()
    ->> 'special_competitions_ready')::boolean as special_competitions_ready,
  (public.get_leghevo_application_integrity_seal_v1()
    ->> 'account_services_ready')::boolean as account_services_ready,
  (public.get_leghevo_application_integrity_seal_v1()
    ->> 'provider_reliability_ready')::boolean as provider_reliability_ready,
  (public.get_leghevo_application_integrity_seal_v1()
    ->> 'cross_module_boundaries_ready')::boolean as cross_module_boundaries_ready,
  (public.get_leghevo_application_integrity_seal_v1()
    ->> 'immutable_audit_ready')::boolean as immutable_audit_ready,
  (public.get_leghevo_application_integrity_seal_v1()
    ->> 'rls_boundary_ready')::boolean as rls_boundary_ready,
  (public.get_leghevo_application_integrity_seal_v1()
    ->> 'realtime_surface_ready')::boolean as realtime_surface_ready,
  (public.get_leghevo_application_integrity_seal_v1()
    ->> 'application_model_rpc_ready')::boolean as application_model_rpc_ready,
  (public.get_leghevo_application_integrity_seal_v1()
    ->> 'endpoint_chain_ready')::boolean as endpoint_chain_ready,
  (public.get_leghevo_application_integrity_seal_v1()
    ->> 'authenticated_read_ready')::boolean as authenticated_read_ready;
