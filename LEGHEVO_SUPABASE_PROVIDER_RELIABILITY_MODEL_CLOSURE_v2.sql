-- LEGHEVO v0.62.32
-- Chiusura certificata dello Sviluppo 8: rinvii, sincronizzazione provider,
-- recuperi operativi, pubblicazione autorevole, causalità dei risultati,
-- progressione, chiusura stagione, rinnovo e avvio della nuova competizione.
-- Migrazione idempotente e non distruttiva.

begin;

-- Preflight: la barriera di avvio v0.62.31 e tutti i contratti diagnostici
-- dello Sviluppo 8 devono essere presenti prima del sigillo conclusivo.
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
    'public.leghevo_safe_table_privilege_v1(name,text,text)',
    'public.leghevo_safe_function_privilege_v1(name,text,text)',
    'public.get_provider_sync_safety_integrity_v1()',
    'public.get_provider_data_freshness_integrity_v1()',
    'public.get_provider_operational_incident_integrity_v1()',
    'public.get_provider_recovery_queue_integrity_v1()',
    'public.get_provider_recovery_watchdog_integrity_v1()',
    'public.get_provider_worker_heartbeat_integrity_v1()',
    'public.get_provider_recovery_retry_backoff_integrity_v1()',
    'public.get_provider_recovery_circuit_breaker_integrity_v1()',
    'public.get_provider_recovery_outcome_verification_integrity_v1()',
    'public.get_provider_worker_lease_fencing_integrity_v1()',
    'public.get_provider_payload_contract_quarantine_integrity_v1()',
    'public.get_provider_delivery_completeness_integrity_v1()',
    'public.get_provider_atomic_publication_integrity_v1()',
    'public.get_provider_semantic_scope_integrity_v1()',
    'public.get_provider_monotonic_publication_integrity_v1()',
    'public.get_provider_player_catalog_reconciliation_integrity_v1()',
    'public.get_provider_fixture_score_reconciliation_integrity_v1()',
    'public.get_provider_fixture_lifecycle_integrity_v1()',
    'public.get_provider_fixture_score_coherence_integrity_v1()',
    'public.get_provider_score_consumption_gate_integrity_v1()',
    'public.get_provider_official_result_impact_integrity_v1()',
    'public.get_provider_official_result_remediation_integrity_v1()',
    'public.get_provider_official_result_lineage_integrity_v1()',
    'public.get_provider_official_result_remediation_completion_integrity_v1()',
    'public.get_provider_matchday_progression_gate_integrity_v1()',
    'public.get_provider_season_completion_gate_integrity_v1()',
    'public.get_league_season_official_snapshot_integrity_v1()',
    'public.get_league_season_rollover_integrity_v1()',
    'public.get_provider_season_bootstrap_integrity_v1()',
    'public.get_provider_competition_start_integrity_v1()',
    'public.get_league_provider_sync_health_v30(uuid)',
    'public.get_league_season_state_v9(uuid)',
    'public.get_league_management_state_v19(uuid)'
  ] loop
    if to_regprocedure(v_signature) is null then
      v_missing := array_append(v_missing, 'funzione ' || v_signature);
    end if;
  end loop;

  if cardinality(v_missing) > 0 then
    raise exception
      'Preflight v0.62.32 non superato. Oggetti mancanti: %',
      array_to_string(v_missing, '; ');
  end if;

  v_predecessor := public.get_provider_competition_start_integrity_v1();
  if (select count(*) from jsonb_each(v_predecessor)) <> 20
    or exists(
      select 1 from jsonb_each(v_predecessor) item
      where jsonb_typeof(item.value) is distinct from 'boolean'
         or item.value is distinct from 'true'::jsonb
    ) then
    raise exception
      'Preflight v0.62.32 non superato: la v0.62.31 non risulta integra [%].',
      v_predecessor;
  end if;
end;
$preflight$;

-- Contratto comune: una diagnostica di modulo corrente è valida soltanto
-- se contiene esattamente venti booleani e tutti risultano true.
create or replace function public.provider_reliability_diagnostic_all_true_v1(
  p_diagnostic jsonb
)
returns boolean
language sql
immutable
security definer
set search_path = ''
as $function$
  select
    (select count(*) from pg_catalog.jsonb_each(
      coalesce(p_diagnostic, '{}'::jsonb))) = 20
    and not exists(
      select 1
      from pg_catalog.jsonb_each(coalesce(p_diagnostic, '{}'::jsonb)) item
      where pg_catalog.jsonb_typeof(item.value) is distinct from 'boolean'
         or item.value is distinct from 'true'::jsonb
    );
$function$;

revoke all on function public.provider_reliability_diagnostic_all_true_v1(jsonb)
from public, anon, authenticated;
grant execute on function public.provider_reliability_diagnostic_all_true_v1(jsonb)
to service_role;

-- Le diagnostiche storiche restano deliberatamente sensibili alla sostituzione
-- delle vecchie RPC. Quando una versione successiva installa un wrapper più
-- nuovo, alcuni controlli legacy devono risultare false. Questa funzione
-- certifica esattamente quello stato atteso, senza ignorare altri falsi.
create or replace function public.provider_reliability_diagnostic_matches_v1(
  p_diagnostic jsonb,
  p_expected_false_keys text[] default '{}'::text[]
)
returns boolean
language sql
immutable
security definer
set search_path = ''
as $function$
  select
    pg_catalog.jsonb_typeof(coalesce(p_diagnostic, '{}'::jsonb)) = 'object'
    and (select count(*) from pg_catalog.jsonb_each(
      coalesce(p_diagnostic, '{}'::jsonb))) = 20
    and not exists(
      select 1
      from pg_catalog.jsonb_each(coalesce(p_diagnostic, '{}'::jsonb)) item
      where pg_catalog.jsonb_typeof(item.value) is distinct from 'boolean'
         or (
           item.key = any(coalesce(p_expected_false_keys, '{}'::text[]))
           and item.value is distinct from 'false'::jsonb
         )
         or (
           not (item.key = any(coalesce(
             p_expected_false_keys, '{}'::text[])))
           and item.value is distinct from 'true'::jsonb
         )
    )
    and not exists(
      select 1
      from unnest(coalesce(p_expected_false_keys, '{}'::text[])) expected(key)
      where not coalesce(p_diagnostic, '{}'::jsonb) ? expected.key
    );
$function$;

revoke all on function public.provider_reliability_diagnostic_matches_v1(
  jsonb, text[]
) from public, anon, authenticated;
grant execute on function public.provider_reliability_diagnostic_matches_v1(
  jsonb, text[]
) to service_role;

-- Le trenta diagnostiche delle versioni 0.62.2-0.62.31 vengono riassunte in
-- venti capacità indipendenti. Il blocco rinvii v0.62.1 è verificato tramite
-- le sue strutture protette perché la sua diagnostica è intenzionalmente
-- per singola lega.
create or replace function public.get_provider_reliability_schema_readiness_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_postponements boolean := false;
  v_sync boolean := false;
  v_freshness boolean := false;
  v_incidents_queue boolean := false;
  v_watchdog_heartbeat boolean := false;
  v_retry_circuit_verification boolean := false;
  v_lease_fencing boolean := false;
  v_payload_contracts boolean := false;
  v_delivery boolean := false;
  v_atomic_publication boolean := false;
  v_semantic_scope boolean := false;
  v_watermark boolean := false;
  v_catalog boolean := false;
  v_fixture_scores boolean := false;
  v_fixture_lifecycle_coherence boolean := false;
  v_score_consumption_impact boolean := false;
  v_remediation_lineage boolean := false;
  v_matchday_season_closure boolean := false;
  v_rollover_bootstrap_start boolean := false;
  v_operational_endpoints boolean := false;
  v_passed integer := 0;
begin
  v_postponements :=
    to_regclass('public.league_fixture_resolutions') is not null
    and to_regclass('public.fixture_resolution_action_runs') is not null
    and to_regprocedure(
      'public.get_league_postponement_resolution_integrity_v1(uuid)')
      is not null
    and exists(
      select 1 from pg_catalog.pg_trigger trigger_row
      where trigger_row.tgname = 'provider_fixture_close_political_scores'
        and not trigger_row.tgisinternal
    );

  v_sync := public.provider_reliability_diagnostic_all_true_v1(
    public.get_provider_sync_safety_integrity_v1());
  v_freshness := public.provider_reliability_diagnostic_all_true_v1(
    public.get_provider_data_freshness_integrity_v1());
  v_incidents_queue :=
    public.provider_reliability_diagnostic_all_true_v1(
      public.get_provider_operational_incident_integrity_v1())
    and public.provider_reliability_diagnostic_all_true_v1(
      public.get_provider_recovery_queue_integrity_v1());
  v_watchdog_heartbeat :=
    public.provider_reliability_diagnostic_all_true_v1(
      public.get_provider_recovery_watchdog_integrity_v1())
    and public.provider_reliability_diagnostic_all_true_v1(
      public.get_provider_worker_heartbeat_integrity_v1());
  v_retry_circuit_verification :=
    public.provider_reliability_diagnostic_all_true_v1(
      public.get_provider_recovery_retry_backoff_integrity_v1())
    and public.provider_reliability_diagnostic_all_true_v1(
      public.get_provider_recovery_circuit_breaker_integrity_v1())
    and public.provider_reliability_diagnostic_all_true_v1(
      public.get_provider_recovery_outcome_verification_integrity_v1());
  v_lease_fencing := public.provider_reliability_diagnostic_all_true_v1(
    public.get_provider_worker_lease_fencing_integrity_v1());
  v_payload_contracts := public.provider_reliability_diagnostic_all_true_v1(
    public.get_provider_payload_contract_quarantine_integrity_v1());
  v_delivery := public.provider_reliability_diagnostic_all_true_v1(
    public.get_provider_delivery_completeness_integrity_v1());
  v_atomic_publication := public.provider_reliability_diagnostic_all_true_v1(
    public.get_provider_atomic_publication_integrity_v1());
  v_semantic_scope := public.provider_reliability_diagnostic_all_true_v1(
    public.get_provider_semantic_scope_integrity_v1());
  v_watermark := public.provider_reliability_diagnostic_all_true_v1(
    public.get_provider_monotonic_publication_integrity_v1());
  -- Le versioni 0.62.17-0.62.20 formano una catena di wrapper monotoni.
  -- Le diagnostiche più vecchie devono quindi mostrare soltanto i falsi
  -- legacy previsti, mentre la diagnostica terminale v0.62.20 resta 20/20.
  v_catalog :=
    public.provider_reliability_diagnostic_matches_v1(
      public.get_provider_player_catalog_reconciliation_integrity_v1(),
      array['finish_v7_ready']::text[])
    and public.provider_reliability_diagnostic_all_true_v1(
      public.get_provider_fixture_score_coherence_integrity_v1());
  v_fixture_scores :=
    public.provider_reliability_diagnostic_matches_v1(
      public.get_provider_fixture_score_reconciliation_integrity_v1(),
      array['predecessor_ready','finish_v8_ready']::text[])
    and public.provider_reliability_diagnostic_all_true_v1(
      public.get_provider_fixture_score_coherence_integrity_v1());
  v_fixture_lifecycle_coherence :=
    public.provider_reliability_diagnostic_matches_v1(
      public.get_provider_fixture_lifecycle_integrity_v1(),
      array['predecessor_ready','finish_v9_ready']::text[])
    and public.provider_reliability_diagnostic_all_true_v1(
      public.get_provider_fixture_score_coherence_integrity_v1());
  v_score_consumption_impact :=
    public.provider_reliability_diagnostic_all_true_v1(
      public.get_provider_score_consumption_gate_integrity_v1())
    and public.provider_reliability_diagnostic_all_true_v1(
      public.get_provider_official_result_impact_integrity_v1());
  v_remediation_lineage :=
    public.provider_reliability_diagnostic_all_true_v1(
      public.get_provider_official_result_remediation_integrity_v1())
    and public.provider_reliability_diagnostic_all_true_v1(
      public.get_provider_official_result_lineage_integrity_v1())
    and public.provider_reliability_diagnostic_all_true_v1(
      public.get_provider_official_result_remediation_completion_integrity_v1());
  v_matchday_season_closure :=
    public.provider_reliability_diagnostic_all_true_v1(
      public.get_provider_matchday_progression_gate_integrity_v1())
    and public.provider_reliability_diagnostic_all_true_v1(
      public.get_provider_season_completion_gate_integrity_v1())
    and public.provider_reliability_diagnostic_all_true_v1(
      public.get_league_season_official_snapshot_integrity_v1());
  -- La v0.62.30 sostituisce intenzionalmente il wrapper legacy della
  -- v0.62.29 con renew_league_season_guarded_v3. L'unico falso storico
  -- ammesso è quindi legacy_rpc_protected; bootstrap e avvio restano 20/20.
  v_rollover_bootstrap_start :=
    public.provider_reliability_diagnostic_matches_v1(
      public.get_league_season_rollover_integrity_v1(),
      array['legacy_rpc_protected']::text[])
    and public.provider_reliability_diagnostic_all_true_v1(
      public.get_provider_season_bootstrap_integrity_v1())
    and public.provider_reliability_diagnostic_all_true_v1(
      public.get_provider_competition_start_integrity_v1());
  v_operational_endpoints :=
    to_regprocedure('public.get_league_provider_sync_health_v30(uuid)')
      is not null
    and to_regprocedure('public.get_league_season_state_v9(uuid)') is not null
    and to_regprocedure('public.get_league_management_state_v19(uuid)')
      is not null
    and exists(
      select 1 from pg_catalog.pg_trigger trigger_row
      where trigger_row.tgname = 'provider_competition_start_activation_guard'
        and trigger_row.tgenabled = 'A'
    );

  v_passed :=
      v_postponements::integer
    + v_sync::integer
    + v_freshness::integer
    + v_incidents_queue::integer
    + v_watchdog_heartbeat::integer
    + v_retry_circuit_verification::integer
    + v_lease_fencing::integer
    + v_payload_contracts::integer
    + v_delivery::integer
    + v_atomic_publication::integer
    + v_semantic_scope::integer
    + v_watermark::integer
    + v_catalog::integer
    + v_fixture_scores::integer
    + v_fixture_lifecycle_coherence::integer
    + v_score_consumption_impact::integer
    + v_remediation_lineage::integer
    + v_matchday_season_closure::integer
    + v_rollover_bootstrap_start::integer
    + v_operational_endpoints::integer;

  return jsonb_build_object(
    'healthy', v_passed = 20,
    'checkCount', 20,
    'passedCount', v_passed,
    'checks', jsonb_build_object(
      'postponementSafetyReady', v_postponements,
      'providerSyncReady', v_sync,
      'freshnessCoverageReady', v_freshness,
      'incidentRecoveryQueueReady', v_incidents_queue,
      'watchdogHeartbeatReady', v_watchdog_heartbeat,
      'retryCircuitVerificationReady', v_retry_circuit_verification,
      'workerLeaseFencingReady', v_lease_fencing,
      'payloadContractsReady', v_payload_contracts,
      'deliveryCompletenessReady', v_delivery,
      'atomicPublicationReady', v_atomic_publication,
      'semanticScopeReady', v_semantic_scope,
      'monotonicWatermarkReady', v_watermark,
      'authoritativeCatalogReady', v_catalog,
      'authoritativeFixtureScoresReady', v_fixture_scores,
      'fixtureLifecycleCoherenceReady', v_fixture_lifecycle_coherence,
      'scoreConsumptionImpactReady', v_score_consumption_impact,
      'remediationLineageClosureReady', v_remediation_lineage,
      'matchdaySeasonClosureReady', v_matchday_season_closure,
      'rolloverBootstrapStartReady', v_rollover_bootstrap_start,
      'operationalEndpointsReady', v_operational_endpoints
    )
  );
end;
$function$;

revoke all on function public.get_provider_reliability_schema_readiness_v1()
from public, anon, authenticated;
grant execute on function public.get_provider_reliability_schema_readiness_v1()
to service_role;

-- Impronta stabile delle strutture e delle funzioni critiche dello Sviluppo 8.
-- Non include dati operativi: fotografa esclusivamente contratti, trigger,
-- policy e schema installato.
create or replace function public.compute_provider_reliability_schema_fingerprint_v1()
returns text
language sql
stable
security definer
set search_path = ''
as $function$
  with function_signatures(signature) as (
    values
      ('public.provider_reliability_diagnostic_all_true_v1(jsonb)'),
      ('public.provider_reliability_diagnostic_matches_v1(jsonb,text[])'),
      ('public.get_provider_sync_safety_integrity_v1()'),
      ('public.get_provider_data_freshness_integrity_v1()'),
      ('public.get_provider_operational_incident_integrity_v1()'),
      ('public.get_provider_recovery_queue_integrity_v1()'),
      ('public.get_provider_recovery_watchdog_integrity_v1()'),
      ('public.get_provider_worker_heartbeat_integrity_v1()'),
      ('public.get_provider_recovery_retry_backoff_integrity_v1()'),
      ('public.get_provider_recovery_circuit_breaker_integrity_v1()'),
      ('public.get_provider_recovery_outcome_verification_integrity_v1()'),
      ('public.get_provider_worker_lease_fencing_integrity_v1()'),
      ('public.get_provider_payload_contract_quarantine_integrity_v1()'),
      ('public.get_provider_delivery_completeness_integrity_v1()'),
      ('public.get_provider_atomic_publication_integrity_v1()'),
      ('public.get_provider_semantic_scope_integrity_v1()'),
      ('public.get_provider_monotonic_publication_integrity_v1()'),
      ('public.get_provider_player_catalog_reconciliation_integrity_v1()'),
      ('public.get_provider_fixture_score_reconciliation_integrity_v1()'),
      ('public.get_provider_fixture_lifecycle_integrity_v1()'),
      ('public.get_provider_fixture_score_coherence_integrity_v1()'),
      ('public.get_provider_score_consumption_gate_integrity_v1()'),
      ('public.get_provider_official_result_impact_integrity_v1()'),
      ('public.get_provider_official_result_remediation_integrity_v1()'),
      ('public.get_provider_official_result_lineage_integrity_v1()'),
      ('public.get_provider_official_result_remediation_completion_integrity_v1()'),
      ('public.get_provider_matchday_progression_gate_integrity_v1()'),
      ('public.get_provider_season_completion_gate_integrity_v1()'),
      ('public.get_league_season_official_snapshot_integrity_v1()'),
      ('public.get_league_season_rollover_integrity_v1()'),
      ('public.get_provider_season_bootstrap_integrity_v1()'),
      ('public.get_provider_competition_start_integrity_v1()'),
      ('public.get_league_provider_sync_health_v30(uuid)'),
      ('public.get_league_season_state_v9(uuid)'),
      ('public.get_league_management_state_v19(uuid)'),
      ('public.start_league_competition_guarded_v4(uuid)'),
      ('public.renew_league_season_guarded_v3(uuid,text,uuid)'),
      ('public.complete_league_season_guarded_v3(uuid,uuid)'),
      ('public.reconcile_provider_competition_start_v1(uuid,boolean)')
  ),
  provider_relations as (
    select relation_row.oid, relation_row.relname, relation_row.relrowsecurity
    from pg_catalog.pg_class relation_row
    join pg_catalog.pg_namespace namespace_row
      on namespace_row.oid = relation_row.relnamespace
    where namespace_row.nspname = 'public'
      and relation_row.relkind in ('r','p')
      and (
        relation_row.relname like E'provider\\_%' escape E'\\'
        or relation_row.relname in (
          'league_fixture_resolutions',
          'fixture_resolution_action_runs',
          'matchday_progression_runs',
          'league_season_official_snapshots',
          'leghevo_model_certifications'
        )
      )
  )
  select pg_catalog.md5(
    pg_catalog.jsonb_build_object(
      'relations', (
        select pg_catalog.jsonb_agg(
          pg_catalog.jsonb_build_object(
            'name', relation.relname,
            'rls', relation.relrowsecurity,
            'columns', (
              select pg_catalog.jsonb_agg(
                pg_catalog.jsonb_build_object(
                  'name', attribute_row.attname,
                  'type', pg_catalog.format_type(
                    attribute_row.atttypid, attribute_row.atttypmod),
                  'notNull', attribute_row.attnotnull
                ) order by attribute_row.attnum
              )
              from pg_catalog.pg_attribute attribute_row
              where attribute_row.attrelid = relation.oid
                and attribute_row.attnum > 0
                and not attribute_row.attisdropped
            ),
            'constraints', (
              select pg_catalog.jsonb_agg(
                pg_catalog.pg_get_constraintdef(constraint_row.oid, true)
                order by constraint_row.conname
              )
              from pg_catalog.pg_constraint constraint_row
              where constraint_row.conrelid = relation.oid
            )
          ) order by relation.relname
        ) from provider_relations relation
      ),
      'functions', (
        select pg_catalog.jsonb_object_agg(
          function_row.signature,
          pg_catalog.md5(pg_catalog.pg_get_functiondef(
            to_regprocedure(function_row.signature)))
          order by function_row.signature
        )
        from function_signatures function_row
      ),
      'triggers', (
        select pg_catalog.jsonb_agg(
          pg_catalog.jsonb_build_object(
            'table', table_row.relname,
            'name', trigger_row.tgname,
            'enabled', trigger_row.tgenabled,
            'definition', pg_catalog.pg_get_triggerdef(trigger_row.oid, true)
          ) order by table_row.relname, trigger_row.tgname
        )
        from pg_catalog.pg_trigger trigger_row
        join provider_relations table_row on table_row.oid = trigger_row.tgrelid
        where not trigger_row.tgisinternal
      ),
      'policies', (
        select pg_catalog.jsonb_agg(
          pg_catalog.jsonb_build_object(
            'table', policy_row.tablename,
            'name', policy_row.policyname,
            'command', policy_row.cmd,
            'roles', policy_row.roles,
            'qual', policy_row.qual,
            'withCheck', policy_row.with_check
          ) order by policy_row.tablename, policy_row.policyname
        )
        from pg_catalog.pg_policies policy_row
        where policy_row.schemaname = 'public'
          and exists(
            select 1 from provider_relations relation
            where relation.relname = policy_row.tablename
          )
      )
    )::text
  );
$function$;

revoke all on function public.compute_provider_reliability_schema_fingerprint_v1()
from public, anon, authenticated;
grant execute on function public.compute_provider_reliability_schema_fingerprint_v1()
to service_role;

-- Registra il sigillo soltanto dopo il superamento delle venti capacità.
-- Una riesecuzione accetta esclusivamente la stessa impronta.
do $certification$
declare
  v_readiness jsonb;
  v_fingerprint text;
  v_existing public.leghevo_model_certifications%rowtype;
  v_false text[];
begin
  v_readiness := public.get_provider_reliability_schema_readiness_v1();

  select array_agg(item.key order by item.key)
  into v_false
  from jsonb_each(v_readiness -> 'checks') item
  where item.value is distinct from 'true'::jsonb;

  if not coalesce((v_readiness ->> 'healthy')::boolean, false)
    or coalesce((v_readiness ->> 'checkCount')::integer, 0) <> 20
    or coalesce((v_readiness ->> 'passedCount')::integer, 0) <> 20 then
    raise exception
      'LEGHEVO v0.62.32 controlli falliti: %. Dettaglio: %',
      coalesce(array_to_string(v_false, ', '), 'diagnostica non valida'),
      coalesce(v_readiness -> 'checks', '{}'::jsonb)::text;
  end if;

  v_fingerprint := public.compute_provider_reliability_schema_fingerprint_v1();

  select certification.* into v_existing
  from public.leghevo_model_certifications certification
  where certification.model_key = 'provider_reliability_v1';

  if found then
    if v_existing.model_version <> 1
      or v_existing.application_version <> '0.62.32'
      or v_existing.schema_fingerprint <> v_fingerprint then
      raise exception
        'La certificazione esistente non coincide con provider reliability v1.';
    end if;
  else
    insert into public.leghevo_model_certifications(
      model_key, model_version, application_version,
      schema_fingerprint, readiness
    ) values (
      'provider_reliability_v1', 1, '0.62.32',
      v_fingerprint, v_readiness
    );
  end if;
end;
$certification$;

-- Stato del sigillo per una lega: la certificazione dello schema resta
-- separata dalla salute operativa corrente, così una regressione dei dati non
-- riscrive o cancella il certificato conclusivo.
create or replace function public.get_league_provider_reliability_model_v1(
  p_league_id uuid
)
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
  v_base jsonb;
  v_schema_certified boolean := false;
  v_operational_healthy boolean := false;
  v_certification_found boolean := false;
  v_member boolean := false;
begin
  if auth.uid() is null then
    raise exception 'Devi effettuare l''accesso.';
  end if;

  v_member := public.is_league_member(p_league_id)
    or public.is_league_admin(p_league_id)
    or exists(
      select 1 from public.leagues league
      where league.id = p_league_id and league.owner_id = auth.uid()
    );
  if not v_member then
    raise exception 'Non fai parte di questa lega.';
  end if;

  v_readiness := public.get_provider_reliability_schema_readiness_v1();
  v_fingerprint := public.compute_provider_reliability_schema_fingerprint_v1();
  v_base := public.get_league_provider_sync_health_v30(p_league_id);

  select certification.* into v_certification
  from public.leghevo_model_certifications certification
  where certification.model_key = 'provider_reliability_v1';
  v_certification_found := found;

  v_schema_certified :=
    v_certification_found
    and v_certification.model_version = 1
    and v_certification.application_version = '0.62.32'
    and v_certification.schema_fingerprint = v_fingerprint
    and coalesce((v_readiness ->> 'healthy')::boolean, false)
    and coalesce((v_readiness ->> 'checkCount')::integer, 0) = 20
    and coalesce((v_readiness ->> 'passedCount')::integer, 0) = 20;

  v_operational_healthy :=
    coalesce((v_base ->> 'protected')::boolean, false)
    and coalesce((v_base ->> 'healthy')::boolean, false);

  return jsonb_build_object(
    'protected', v_schema_certified,
    'modelClosed', v_schema_certified,
    'healthy', v_schema_certified and v_operational_healthy,
    'schemaCertified', v_schema_certified,
    'operationalHealthy', v_operational_healthy,
    'status', case
      when not v_schema_certified then 'affected'
      when v_operational_healthy then 'certified'
      else 'attention'
    end,
    'reasonCode', case
      when not v_schema_certified
        then 'provider_reliability.schema_fingerprint_changed'
      when not v_operational_healthy
        then 'provider_reliability.operational_attention'
      else 'provider_reliability.certified'
    end,
    'modelKey', 'provider_reliability_v1',
    'modelVersion', 1,
    'applicationVersion', '0.62.32',
    'certifiedAt', v_certification.certified_at,
    'schemaFingerprint', v_fingerprint,
    'storedSchemaFingerprint', v_certification.schema_fingerprint,
    'fingerprintStable',
      v_certification.schema_fingerprint is not distinct from v_fingerprint,
    'checkCount', coalesce((v_readiness ->> 'checkCount')::integer, 0),
    'passedCount', coalesce((v_readiness ->> 'passedCount')::integer, 0)
  );
end;
$function$;

revoke all on function public.get_league_provider_reliability_model_v1(uuid)
from public, anon;
grant execute on function public.get_league_provider_reliability_model_v1(uuid)
to authenticated;

create or replace function public.get_league_provider_sync_health_v31(
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
  v_closure jsonb;
  v_healthy boolean;
begin
  v_base := public.get_league_provider_sync_health_v30(p_league_id);
  v_closure := public.get_league_provider_reliability_model_v1(p_league_id);
  v_healthy := coalesce((v_base ->> 'healthy')::boolean, false)
    and coalesce((v_closure ->> 'healthy')::boolean, false);

  return v_base || jsonb_build_object(
    'protected', coalesce((v_base ->> 'protected')::boolean, false)
      and coalesce((v_closure ->> 'protected')::boolean, false),
    'healthy', v_healthy,
    'status', case when v_healthy then coalesce(v_base ->> 'status', 'idle')
      else 'attention' end,
    'providerReliabilityModel', v_closure
  );
end;
$function$;

revoke all on function public.get_league_provider_sync_health_v31(uuid)
from public, anon, service_role;
grant execute on function public.get_league_provider_sync_health_v31(uuid)
to authenticated;

create or replace function public.get_league_season_state_v10(p_league_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_base jsonb;
  v_closure jsonb;
begin
  v_base := public.get_league_season_state_v9(p_league_id);
  v_closure := public.get_league_provider_reliability_model_v1(p_league_id);
  return v_base || jsonb_build_object(
    'providerReliabilityModelProtected',
      coalesce((v_closure ->> 'protected')::boolean, false),
    'providerReliabilityModelClosed',
      coalesce((v_closure ->> 'modelClosed')::boolean, false),
    'providerReliabilityModelHealthy',
      coalesce((v_closure ->> 'healthy')::boolean, false),
    'providerReliabilityModelStatus', v_closure ->> 'status',
    'providerReliabilityModelReason', v_closure ->> 'reasonCode'
  );
end;
$function$;

revoke all on function public.get_league_season_state_v10(uuid)
from public, anon;
grant execute on function public.get_league_season_state_v10(uuid)
to authenticated;

create or replace function public.get_league_management_state_v20(p_league_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_base jsonb;
  v_closure jsonb;
  v_checks jsonb;
begin
  v_base := public.get_league_management_state_v19(p_league_id);
  v_closure := public.get_league_provider_reliability_model_v1(p_league_id);
  v_checks := coalesce(v_base -> 'checks', '{}'::jsonb)
    || jsonb_build_object(
      'providerReliabilityModelProtected',
        coalesce((v_closure ->> 'protected')::boolean, false),
      'providerReliabilityModelClosed',
        coalesce((v_closure ->> 'modelClosed')::boolean, false),
      'providerReliabilityModelHealthy',
        coalesce((v_closure ->> 'healthy')::boolean, false)
    );

  return v_base || jsonb_build_object(
    'providerReliabilityModelProtected',
      coalesce((v_closure ->> 'protected')::boolean, false),
    'providerReliabilityModelClosed',
      coalesce((v_closure ->> 'modelClosed')::boolean, false),
    'providerReliabilityModelHealthy',
      coalesce((v_closure ->> 'healthy')::boolean, false),
    'providerReliabilityModelStatus', v_closure ->> 'status',
    'providerReliabilityModelReason', v_closure ->> 'reasonCode',
    'providerReliabilityModelCertifiedAt', v_closure -> 'certifiedAt',
    'checks', v_checks
  );
end;
$function$;

revoke all on function public.get_league_management_state_v20(uuid)
from public, anon;
grant execute on function public.get_league_management_state_v20(uuid)
to authenticated;

-- Diagnostica strutturale conclusiva della v0.62.32.
create or replace function public.get_provider_reliability_model_closure_integrity_v1()
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
  v_closure_def text := coalesce(pg_catalog.pg_get_functiondef(
    to_regprocedure('public.get_league_provider_reliability_model_v1(uuid)')), '');
  v_health_def text := coalesce(pg_catalog.pg_get_functiondef(
    to_regprocedure('public.get_league_provider_sync_health_v31(uuid)')), '');
  v_season_def text := coalesce(pg_catalog.pg_get_functiondef(
    to_regprocedure('public.get_league_season_state_v10(uuid)')), '');
  v_management_def text := coalesce(pg_catalog.pg_get_functiondef(
    to_regprocedure('public.get_league_management_state_v20(uuid)')), '');
  v_certification_found boolean := false;
begin
  v_readiness := public.get_provider_reliability_schema_readiness_v1();
  v_fingerprint := public.compute_provider_reliability_schema_fingerprint_v1();
  select certification.* into v_certification
  from public.leghevo_model_certifications certification
  where certification.model_key = 'provider_reliability_v1';
  v_certification_found := found;

  return jsonb_build_object(
    'predecessor_ready',
      public.provider_reliability_diagnostic_all_true_v1(
        public.get_provider_competition_start_integrity_v1()),
    'diagnostics_contract_ready',
      coalesce((v_readiness ->> 'checkCount')::integer, 0) = 20
      and coalesce((v_readiness ->> 'passedCount')::integer, 0) = 20,
    'certification_table_ready',
      to_regclass('public.leghevo_model_certifications') is not null,
    'certification_row_ready', v_certification_found,
    'certification_version_ready',
      v_certification.model_version = 1
      and v_certification.application_version = '0.62.32',
    'certification_fingerprint_ready',
      v_certification.schema_fingerprint = v_fingerprint
      and length(v_fingerprint) = 32,
    'helper_ready',
      to_regprocedure(
        'public.provider_reliability_diagnostic_all_true_v1(jsonb)')
        is not null
      and to_regprocedure(
        'public.provider_reliability_diagnostic_matches_v1(jsonb,text[])')
        is not null,
    'schema_readiness_ready',
      to_regprocedure('public.get_provider_reliability_schema_readiness_v1()')
        is not null
      and coalesce((v_readiness ->> 'healthy')::boolean, false),
    'schema_fingerprint_ready',
      to_regprocedure(
        'public.compute_provider_reliability_schema_fingerprint_v1()')
        is not null,
    'closure_rpc_ready',
      to_regprocedure(
        'public.get_league_provider_reliability_model_v1(uuid)') is not null
      and position('provider_reliability_v1' in v_closure_def) > 0,
    'health_v31_ready',
      to_regprocedure('public.get_league_provider_sync_health_v31(uuid)')
        is not null
      and position('providerReliabilityModel' in v_health_def) > 0
      and position('get_league_provider_sync_health_v30' in v_health_def) > 0,
    'season_state_v10_ready',
      to_regprocedure('public.get_league_season_state_v10(uuid)') is not null
      and position('providerReliabilityModelClosed' in v_season_def) > 0,
    'management_state_v20_ready',
      to_regprocedure('public.get_league_management_state_v20(uuid)') is not null
      and position('providerReliabilityModelClosed' in v_management_def) > 0,
    'certification_immutable_ready',
      exists(
        select 1 from pg_catalog.pg_trigger trigger_row
        where trigger_row.tgrelid =
          'public.leghevo_model_certifications'::regclass
          and trigger_row.tgname = 'leghevo_model_certifications_immutable'
          and trigger_row.tgenabled in ('O','A')
      ),
    'certification_rls_ready',
      coalesce((select relation_row.relrowsecurity
        from pg_catalog.pg_class relation_row
        where relation_row.oid =
          'public.leghevo_model_certifications'::regclass), false),
    'authenticated_read_ready',
      has_table_privilege('authenticated',
        'public.leghevo_model_certifications','SELECT')
      and has_function_privilege('authenticated',
        'public.get_league_provider_reliability_model_v1(uuid)','EXECUTE')
      and has_function_privilege('authenticated',
        'public.get_league_provider_sync_health_v31(uuid)','EXECUTE'),
    'direct_write_blocked',
      not has_table_privilege('authenticated',
        'public.leghevo_model_certifications','INSERT')
      and not has_table_privilege('authenticated',
        'public.leghevo_model_certifications','UPDATE')
      and not has_table_privilege('authenticated',
        'public.leghevo_model_certifications','DELETE'),
    'internal_functions_protected',
      not has_function_privilege('authenticated',
        'public.provider_reliability_diagnostic_all_true_v1(jsonb)','EXECUTE')
      and not has_function_privilege('authenticated',
        'public.provider_reliability_diagnostic_matches_v1(jsonb,text[])',
        'EXECUTE')
      and not has_function_privilege('authenticated',
        'public.get_provider_reliability_schema_readiness_v1()','EXECUTE')
      and not has_function_privilege('authenticated',
        'public.compute_provider_reliability_schema_fingerprint_v1()','EXECUTE')
      and has_function_privilege('service_role',
        'public.provider_reliability_diagnostic_all_true_v1(jsonb)','EXECUTE')
      and has_function_privilege('service_role',
        'public.provider_reliability_diagnostic_matches_v1(jsonb,text[])',
        'EXECUTE')
      and has_function_privilege('service_role',
        'public.get_provider_reliability_schema_readiness_v1()','EXECUTE'),
    'schema_certified',
      v_certification_found
      and v_certification.readiness = v_readiness
      and v_certification.schema_fingerprint = v_fingerprint,
    'endpoint_chain_ready',
      position('get_league_provider_reliability_model_v1' in v_health_def) > 0
      and position('get_league_season_state_v9' in v_season_def) > 0
      and position('get_league_management_state_v19' in v_management_def) > 0
  );
end;
$function$;

revoke all on function public.get_provider_reliability_model_closure_integrity_v1()
from public, anon, authenticated;
grant execute on function public.get_provider_reliability_model_closure_integrity_v1()
to service_role;

-- Validazione finale: esattamente 20 booleani true.
do $validation$
declare
  v_checks jsonb;
begin
  v_checks := public.get_provider_reliability_model_closure_integrity_v1();
  if (select count(*) from jsonb_each(v_checks)) <> 20
    or exists(
      select 1 from jsonb_each(v_checks) item
      where jsonb_typeof(item.value) is distinct from 'boolean'
         or item.value is distinct from 'true'::jsonb
    ) then
    raise exception 'Validazione v0.62.32 non superata: %', v_checks;
  end if;
end;
$validation$;

commit;

select
  (public.get_provider_reliability_model_closure_integrity_v1()->>'predecessor_ready')::boolean as predecessor_ready,
  (public.get_provider_reliability_model_closure_integrity_v1()->>'diagnostics_contract_ready')::boolean as diagnostics_contract_ready,
  (public.get_provider_reliability_model_closure_integrity_v1()->>'certification_table_ready')::boolean as certification_table_ready,
  (public.get_provider_reliability_model_closure_integrity_v1()->>'certification_row_ready')::boolean as certification_row_ready,
  (public.get_provider_reliability_model_closure_integrity_v1()->>'certification_version_ready')::boolean as certification_version_ready,
  (public.get_provider_reliability_model_closure_integrity_v1()->>'certification_fingerprint_ready')::boolean as certification_fingerprint_ready,
  (public.get_provider_reliability_model_closure_integrity_v1()->>'helper_ready')::boolean as helper_ready,
  (public.get_provider_reliability_model_closure_integrity_v1()->>'schema_readiness_ready')::boolean as schema_readiness_ready,
  (public.get_provider_reliability_model_closure_integrity_v1()->>'schema_fingerprint_ready')::boolean as schema_fingerprint_ready,
  (public.get_provider_reliability_model_closure_integrity_v1()->>'closure_rpc_ready')::boolean as closure_rpc_ready,
  (public.get_provider_reliability_model_closure_integrity_v1()->>'health_v31_ready')::boolean as health_v31_ready,
  (public.get_provider_reliability_model_closure_integrity_v1()->>'season_state_v10_ready')::boolean as season_state_v10_ready,
  (public.get_provider_reliability_model_closure_integrity_v1()->>'management_state_v20_ready')::boolean as management_state_v20_ready,
  (public.get_provider_reliability_model_closure_integrity_v1()->>'certification_immutable_ready')::boolean as certification_immutable_ready,
  (public.get_provider_reliability_model_closure_integrity_v1()->>'certification_rls_ready')::boolean as certification_rls_ready,
  (public.get_provider_reliability_model_closure_integrity_v1()->>'authenticated_read_ready')::boolean as authenticated_read_ready,
  (public.get_provider_reliability_model_closure_integrity_v1()->>'direct_write_blocked')::boolean as direct_write_blocked,
  (public.get_provider_reliability_model_closure_integrity_v1()->>'internal_functions_protected')::boolean as internal_functions_protected,
  (public.get_provider_reliability_model_closure_integrity_v1()->>'schema_certified')::boolean as schema_certified,
  (public.get_provider_reliability_model_closure_integrity_v1()->>'endpoint_chain_ready')::boolean as endpoint_chain_ready;
