-- LEGHEVO v0.61.0
-- Chiusura certificata dello Sviluppo 6: Coppa, Supercoppa e Playoff.
-- Migrazione idempotente e non distruttiva.

begin;

-- Preflight in sola lettura. Interrompe prima di qualsiasi modifica se una
-- dipendenza già validata nelle versioni 0.60.1-0.60.9 non è disponibile.
do $preflight$
declare
  v_missing text[] := array[]::text[];
  v_relation text;
  v_signature text;
begin
  foreach v_relation in array array[
    'public.leghevo_model_certifications',
    'public.league_cups',
    'public.league_cup_entries',
    'public.league_cup_rounds',
    'public.league_cup_ties',
    'public.league_cup_draw_runs',
    'public.league_cup_round_finalization_runs',
    'public.league_cup_completion_certificates',
    'public.league_super_cups',
    'public.league_super_cup_schedule_runs',
    'public.league_super_cup_finalization_runs',
    'public.league_playoffs',
    'public.league_playoff_entries',
    'public.league_playoff_rounds',
    'public.league_playoff_ties',
    'public.league_playoff_configuration_runs',
    'public.league_playoff_start_runs',
    'public.league_playoff_round_finalization_runs',
    'public.league_playoff_completion_certificates'
  ] loop
    if to_regclass(v_relation) is null then
      v_missing := array_append(v_missing, 'tabella ' || v_relation);
    end if;
  end loop;

  foreach v_signature in array array[
    'public.leghevo_safe_table_privilege_v1(name,text,text)',
    'public.leghevo_safe_function_privilege_v1(name,text,text)',
    'public.leghevo_sha256_hex_v1(text)',
    'public.get_league_management_state_v13(uuid)',
    'public.create_league_cup_guarded_v1(uuid,smallint,uuid)',
    'public.finalize_league_cup_round_guarded_v1(uuid,smallint,uuid)',
    'public.get_league_cup_state_v4(uuid)',
    'public.get_league_cup_draw_integrity_v1(uuid)',
    'public.get_league_cup_round_integrity_v1(uuid)',
    'public.get_league_cup_completion_integrity_v1(uuid)',
    'public.create_league_super_cup_guarded_v1(uuid,smallint,uuid)',
    'public.finalize_league_super_cup_guarded_v1(uuid,uuid)',
    'public.get_league_super_cup_state_v3(uuid)',
    'public.get_league_super_cup_schedule_integrity_v1(uuid)',
    'public.get_league_super_cup_finalization_integrity_v1(uuid)',
    'public.configure_league_playoffs_guarded_v1(uuid,smallint,uuid)',
    'public.start_league_playoffs_guarded_v1(uuid,smallint,uuid)',
    'public.finalize_league_playoff_round_guarded_v1(uuid,smallint,uuid)',
    'public.get_league_playoff_state_v5(uuid)',
    'public.get_league_playoff_configuration_integrity_v1(uuid)',
    'public.get_league_playoff_start_integrity_v1(uuid)',
    'public.get_league_playoff_round_integrity_v1(uuid)',
    'public.get_league_playoff_completion_integrity_v1(uuid)'
  ] loop
    if to_regprocedure(v_signature) is null then
      v_missing := array_append(v_missing, 'funzione ' || v_signature);
    end if;
  end loop;

  if cardinality(v_missing) > 0 then
    raise exception
      'Preflight v0.61.0 non superato. Oggetti mancanti: %',
      array_to_string(v_missing, '; ');
  end if;
end;
$preflight$;

-- Tutti i registri dello Sviluppo 6 vengono resi esplicitamente adatti alla
-- sincronizzazione Realtime. Le tabelle già pubblicate vengono ignorate.
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
      'league_cup_draw_runs',
      'league_cup_round_finalization_runs',
      'league_cup_completion_certificates',
      'league_super_cup_schedule_runs',
      'league_super_cup_finalization_runs',
      'league_playoff_configuration_runs',
      'league_playoff_start_runs',
      'league_playoff_round_finalization_runs',
      'league_playoff_completion_certificates'
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

-- Verifica strutturale unica, composta da esattamente venti capacità.
create or replace function public.get_special_competitions_schema_readiness_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_foundation_ready boolean := false;
  v_cup_draw_ready boolean := false;
  v_cup_round_ready boolean := false;
  v_cup_completion_ready boolean := false;
  v_super_schedule_ready boolean := false;
  v_super_finalization_ready boolean := false;
  v_playoff_configuration_ready boolean := false;
  v_playoff_start_ready boolean := false;
  v_playoff_round_ready boolean := false;
  v_playoff_completion_ready boolean := false;
  v_immutable_triggers_ready boolean := false;
  v_automatic_completion_triggers_ready boolean := false;
  v_rls_ready boolean := false;
  v_realtime_ready boolean := false;
  v_authenticated_read_ready boolean := false;
  v_registry_writes_blocked boolean := false;
  v_guarded_endpoints_ready boolean := false;
  v_diagnostic_endpoints_ready boolean := false;
  v_internal_endpoints_private boolean := false;
  v_anonymous_blocked boolean := false;
  v_passed_count integer := 0;
  v_healthy boolean := false;
begin
  v_foundation_ready :=
    to_regclass('public.leghevo_model_certifications') is not null
    and to_regprocedure(
      'public.leghevo_safe_table_privilege_v1(name,text,text)'
    ) is not null
    and to_regprocedure(
      'public.leghevo_safe_function_privilege_v1(name,text,text)'
    ) is not null
    and to_regprocedure('public.leghevo_sha256_hex_v1(text)') is not null
    and to_regprocedure('public.get_league_management_state_v13(uuid)')
      is not null;

  v_cup_draw_ready :=
    to_regclass('public.league_cups') is not null
    and to_regclass('public.league_cup_entries') is not null
    and to_regclass('public.league_cup_rounds') is not null
    and to_regclass('public.league_cup_ties') is not null
    and to_regclass('public.league_cup_draw_runs') is not null
    and to_regprocedure(
      'public.create_league_cup_guarded_v1(uuid,smallint,uuid)'
    ) is not null
    and to_regprocedure('public.get_league_cup_draw_integrity_v1(uuid)')
      is not null;

  v_cup_round_ready :=
    to_regclass('public.league_cup_round_finalization_runs') is not null
    and to_regprocedure(
      'public.finalize_league_cup_round_guarded_v1(uuid,smallint,uuid)'
    ) is not null
    and to_regprocedure('public.get_league_cup_round_integrity_v1(uuid)')
      is not null;

  v_cup_completion_ready :=
    to_regclass('public.league_cup_completion_certificates') is not null
    and to_regprocedure('public.get_league_cup_state_v4(uuid)') is not null
    and to_regprocedure(
      'public.get_league_cup_completion_integrity_v1(uuid)'
    ) is not null
    and to_regprocedure(
      'public.certify_league_cup_completion_internal_v1(uuid,bigint)'
    ) is not null;

  v_super_schedule_ready :=
    to_regclass('public.league_super_cups') is not null
    and to_regclass('public.league_super_cup_schedule_runs') is not null
    and to_regprocedure(
      'public.create_league_super_cup_guarded_v1(uuid,smallint,uuid)'
    ) is not null
    and to_regprocedure(
      'public.get_league_super_cup_schedule_integrity_v1(uuid)'
    ) is not null;

  v_super_finalization_ready :=
    to_regclass('public.league_super_cup_finalization_runs') is not null
    and to_regprocedure(
      'public.finalize_league_super_cup_guarded_v1(uuid,uuid)'
    ) is not null
    and to_regprocedure('public.get_league_super_cup_state_v3(uuid)')
      is not null
    and to_regprocedure(
      'public.get_league_super_cup_finalization_integrity_v1(uuid)'
    ) is not null;

  v_playoff_configuration_ready :=
    to_regclass('public.league_playoffs') is not null
    and to_regclass('public.league_playoff_entries') is not null
    and to_regclass('public.league_playoff_rounds') is not null
    and to_regclass('public.league_playoff_ties') is not null
    and to_regclass('public.league_playoff_configuration_runs') is not null
    and to_regprocedure(
      'public.configure_league_playoffs_guarded_v1(uuid,smallint,uuid)'
    ) is not null
    and to_regprocedure(
      'public.get_league_playoff_configuration_integrity_v1(uuid)'
    ) is not null;

  v_playoff_start_ready :=
    to_regclass('public.league_playoff_start_runs') is not null
    and to_regprocedure(
      'public.start_league_playoffs_guarded_v1(uuid,smallint,uuid)'
    ) is not null
    and to_regprocedure('public.get_league_playoff_start_integrity_v1(uuid)')
      is not null;

  v_playoff_round_ready :=
    to_regclass('public.league_playoff_round_finalization_runs') is not null
    and to_regprocedure(
      'public.finalize_league_playoff_round_guarded_v1(uuid,smallint,uuid)'
    ) is not null
    and to_regprocedure('public.get_league_playoff_round_integrity_v1(uuid)')
      is not null;

  v_playoff_completion_ready :=
    to_regclass('public.league_playoff_completion_certificates') is not null
    and to_regprocedure('public.get_league_playoff_state_v5(uuid)') is not null
    and to_regprocedure(
      'public.get_league_playoff_completion_integrity_v1(uuid)'
    ) is not null
    and to_regprocedure(
      'public.certify_league_playoff_completion_internal_v1(uuid,bigint)'
    ) is not null;

  select count(*) = 9
  into v_immutable_triggers_ready
  from (
    values
      ('public.league_cup_draw_runs', 'league_cup_draw_runs_immutable'),
      ('public.league_cup_round_finalization_runs', 'league_cup_round_finalization_runs_immutable'),
      ('public.league_cup_completion_certificates', 'league_cup_completion_certificates_immutable'),
      ('public.league_super_cup_schedule_runs', 'league_super_cup_schedule_runs_immutable'),
      ('public.league_super_cup_finalization_runs', 'league_super_cup_finalization_runs_immutable'),
      ('public.league_playoff_configuration_runs', 'league_playoff_configuration_runs_immutable'),
      ('public.league_playoff_start_runs', 'league_playoff_start_runs_immutable'),
      ('public.league_playoff_round_finalization_runs', 'league_playoff_round_runs_immutable'),
      ('public.league_playoff_completion_certificates', 'league_playoff_completion_certificates_immutable')
  ) expected(relation_name, trigger_name)
  where exists (
    select 1
    from pg_catalog.pg_trigger trigger_row
    where not trigger_row.tgisinternal
      and trigger_row.tgrelid = to_regclass(expected.relation_name)
      and trigger_row.tgname = expected.trigger_name
  );

  select count(*) = 2
  into v_automatic_completion_triggers_ready
  from (
    values
      ('public.league_cup_round_finalization_runs', 'league_cup_completion_after_finalization'),
      ('public.league_playoff_round_finalization_runs', 'league_playoff_completion_after_finalization')
  ) expected(relation_name, trigger_name)
  where exists (
    select 1
    from pg_catalog.pg_trigger trigger_row
    where not trigger_row.tgisinternal
      and trigger_row.tgrelid = to_regclass(expected.relation_name)
      and trigger_row.tgname = expected.trigger_name
  );

  select count(*) = 9
  into v_rls_ready
  from (
    values
      ('public.league_cup_draw_runs'),
      ('public.league_cup_round_finalization_runs'),
      ('public.league_cup_completion_certificates'),
      ('public.league_super_cup_schedule_runs'),
      ('public.league_super_cup_finalization_runs'),
      ('public.league_playoff_configuration_runs'),
      ('public.league_playoff_start_runs'),
      ('public.league_playoff_round_finalization_runs'),
      ('public.league_playoff_completion_certificates')
  ) expected(relation_name)
  where exists (
    select 1
    from pg_catalog.pg_class relation_row
    where relation_row.oid = to_regclass(expected.relation_name)
      and relation_row.relrowsecurity
  );

  select count(*) = 9
  into v_realtime_ready
  from (
    values
      ('league_cup_draw_runs'),
      ('league_cup_round_finalization_runs'),
      ('league_cup_completion_certificates'),
      ('league_super_cup_schedule_runs'),
      ('league_super_cup_finalization_runs'),
      ('league_playoff_configuration_runs'),
      ('league_playoff_start_runs'),
      ('league_playoff_round_finalization_runs'),
      ('league_playoff_completion_certificates')
  ) expected(table_name)
  where exists (
    select 1
    from pg_catalog.pg_publication_tables publication_table
    where publication_table.pubname = 'supabase_realtime'
      and publication_table.schemaname = 'public'
      and publication_table.tablename = expected.table_name
  );

  select count(*) = 9
  into v_authenticated_read_ready
  from (
    values
      ('public.league_cup_draw_runs'),
      ('public.league_cup_round_finalization_runs'),
      ('public.league_cup_completion_certificates'),
      ('public.league_super_cup_schedule_runs'),
      ('public.league_super_cup_finalization_runs'),
      ('public.league_playoff_configuration_runs'),
      ('public.league_playoff_start_runs'),
      ('public.league_playoff_round_finalization_runs'),
      ('public.league_playoff_completion_certificates')
  ) expected(relation_name)
  where public.leghevo_safe_table_privilege_v1(
    'authenticated', expected.relation_name, 'SELECT'
  );

  select count(*) = 9
  into v_registry_writes_blocked
  from (
    values
      ('public.league_cup_draw_runs'),
      ('public.league_cup_round_finalization_runs'),
      ('public.league_cup_completion_certificates'),
      ('public.league_super_cup_schedule_runs'),
      ('public.league_super_cup_finalization_runs'),
      ('public.league_playoff_configuration_runs'),
      ('public.league_playoff_start_runs'),
      ('public.league_playoff_round_finalization_runs'),
      ('public.league_playoff_completion_certificates')
  ) expected(relation_name)
  where not public.leghevo_safe_table_privilege_v1(
      'authenticated', expected.relation_name, 'INSERT'
    )
    and not public.leghevo_safe_table_privilege_v1(
      'authenticated', expected.relation_name, 'UPDATE'
    )
    and not public.leghevo_safe_table_privilege_v1(
      'authenticated', expected.relation_name, 'DELETE'
    );

  select count(*) = 7
  into v_guarded_endpoints_ready
  from (
    values
      ('public.create_league_cup_guarded_v1(uuid,smallint,uuid)'),
      ('public.finalize_league_cup_round_guarded_v1(uuid,smallint,uuid)'),
      ('public.create_league_super_cup_guarded_v1(uuid,smallint,uuid)'),
      ('public.finalize_league_super_cup_guarded_v1(uuid,uuid)'),
      ('public.configure_league_playoffs_guarded_v1(uuid,smallint,uuid)'),
      ('public.start_league_playoffs_guarded_v1(uuid,smallint,uuid)'),
      ('public.finalize_league_playoff_round_guarded_v1(uuid,smallint,uuid)')
  ) expected(signature)
  where public.leghevo_safe_function_privilege_v1(
    'authenticated', expected.signature, 'EXECUTE'
  );

  select count(*) = 12
  into v_diagnostic_endpoints_ready
  from (
    values
      ('public.get_league_cup_state_v4(uuid)'),
      ('public.get_league_super_cup_state_v3(uuid)'),
      ('public.get_league_playoff_state_v5(uuid)'),
      ('public.get_league_cup_draw_integrity_v1(uuid)'),
      ('public.get_league_cup_round_integrity_v1(uuid)'),
      ('public.get_league_cup_completion_integrity_v1(uuid)'),
      ('public.get_league_super_cup_schedule_integrity_v1(uuid)'),
      ('public.get_league_super_cup_finalization_integrity_v1(uuid)'),
      ('public.get_league_playoff_configuration_integrity_v1(uuid)'),
      ('public.get_league_playoff_start_integrity_v1(uuid)'),
      ('public.get_league_playoff_round_integrity_v1(uuid)'),
      ('public.get_league_playoff_completion_integrity_v1(uuid)')
  ) expected(signature)
  where public.leghevo_safe_function_privilege_v1(
    'authenticated', expected.signature, 'EXECUTE'
  );

  select count(*) = 3
  into v_internal_endpoints_private
  from (
    values
      ('public.refresh_league_cup_round_internal(uuid,integer)'),
      ('public.certify_league_cup_completion_internal_v1(uuid,bigint)'),
      ('public.certify_league_playoff_completion_internal_v1(uuid,bigint)')
  ) expected(signature)
  where to_regprocedure(expected.signature) is not null
    and not public.leghevo_safe_function_privilege_v1(
      'authenticated', expected.signature, 'EXECUTE'
    );

  select count(*) = 19
  into v_anonymous_blocked
  from (
    values
      ('public.create_league_cup_guarded_v1(uuid,smallint,uuid)'),
      ('public.finalize_league_cup_round_guarded_v1(uuid,smallint,uuid)'),
      ('public.get_league_cup_state_v4(uuid)'),
      ('public.create_league_super_cup_guarded_v1(uuid,smallint,uuid)'),
      ('public.finalize_league_super_cup_guarded_v1(uuid,uuid)'),
      ('public.get_league_super_cup_state_v3(uuid)'),
      ('public.configure_league_playoffs_guarded_v1(uuid,smallint,uuid)'),
      ('public.start_league_playoffs_guarded_v1(uuid,smallint,uuid)'),
      ('public.finalize_league_playoff_round_guarded_v1(uuid,smallint,uuid)'),
      ('public.get_league_playoff_state_v5(uuid)'),
      ('public.get_league_cup_draw_integrity_v1(uuid)'),
      ('public.get_league_cup_round_integrity_v1(uuid)'),
      ('public.get_league_cup_completion_integrity_v1(uuid)'),
      ('public.get_league_super_cup_schedule_integrity_v1(uuid)'),
      ('public.get_league_super_cup_finalization_integrity_v1(uuid)'),
      ('public.get_league_playoff_configuration_integrity_v1(uuid)'),
      ('public.get_league_playoff_start_integrity_v1(uuid)'),
      ('public.get_league_playoff_round_integrity_v1(uuid)'),
      ('public.get_league_playoff_completion_integrity_v1(uuid)')
  ) expected(signature)
  where not public.leghevo_safe_function_privilege_v1(
    'anon', expected.signature, 'EXECUTE'
  );

  select count(*)::integer
  into v_passed_count
  from unnest(array[
    v_foundation_ready,
    v_cup_draw_ready,
    v_cup_round_ready,
    v_cup_completion_ready,
    v_super_schedule_ready,
    v_super_finalization_ready,
    v_playoff_configuration_ready,
    v_playoff_start_ready,
    v_playoff_round_ready,
    v_playoff_completion_ready,
    v_immutable_triggers_ready,
    v_automatic_completion_triggers_ready,
    v_rls_ready,
    v_realtime_ready,
    v_authenticated_read_ready,
    v_registry_writes_blocked,
    v_guarded_endpoints_ready,
    v_diagnostic_endpoints_ready,
    v_internal_endpoints_private,
    v_anonymous_blocked
  ]) as readiness_checks(check_value)
  where check_value is true;

  v_healthy := v_passed_count = 20;

  return jsonb_build_object(
    'healthy', v_healthy,
    'policy', 'special_competitions_schema_closed_v1',
    'checkCount', 20,
    'passedCount', v_passed_count,
    'checks', jsonb_build_object(
      'foundationReady', v_foundation_ready,
      'cupDrawReady', v_cup_draw_ready,
      'cupRoundReady', v_cup_round_ready,
      'cupCompletionReady', v_cup_completion_ready,
      'superCupScheduleReady', v_super_schedule_ready,
      'superCupFinalizationReady', v_super_finalization_ready,
      'playoffConfigurationReady', v_playoff_configuration_ready,
      'playoffStartReady', v_playoff_start_ready,
      'playoffRoundReady', v_playoff_round_ready,
      'playoffCompletionReady', v_playoff_completion_ready,
      'immutableTriggersReady', v_immutable_triggers_ready,
      'automaticCompletionTriggersReady',
        v_automatic_completion_triggers_ready,
      'rlsReady', v_rls_ready,
      'realtimeReady', v_realtime_ready,
      'authenticatedReadReady', v_authenticated_read_ready,
      'registryWritesBlocked', v_registry_writes_blocked,
      'guardedEndpointsReady', v_guarded_endpoints_ready,
      'diagnosticEndpointsReady', v_diagnostic_endpoints_ready,
      'internalEndpointsPrivate', v_internal_endpoints_private,
      'anonymousBlocked', v_anonymous_blocked
    )
  );
end;
$$;

-- Impronta strutturale delle sole dipendenze funzionali dello Sviluppo 6.
-- Le funzioni di chiusura create da questa migrazione non sono incluse, così
-- la riesecuzione produce la stessa impronta della prima installazione.
create or replace function public.compute_special_competitions_schema_fingerprint_v1()
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select md5(
    jsonb_build_object(
      'relations', (
        select jsonb_object_agg(
          relation_name,
          jsonb_build_object(
            'oidReady', to_regclass(relation_name) is not null,
            'rls', coalesce((
              select relation_row.relrowsecurity
              from pg_catalog.pg_class relation_row
              where relation_row.oid = to_regclass(relation_name)
            ), false),
            'columns', coalesce((
              select jsonb_agg(
                jsonb_build_object(
                  'name', attribute_row.attname,
                  'type', pg_catalog.format_type(
                    attribute_row.atttypid,
                    attribute_row.atttypmod
                  ),
                  'notNull', attribute_row.attnotnull
                )
                order by attribute_row.attnum
              )
              from pg_catalog.pg_attribute attribute_row
              where attribute_row.attrelid = to_regclass(relation_name)
                and attribute_row.attnum > 0
                and not attribute_row.attisdropped
            ), '[]'::jsonb)
          )
          order by relation_name
        )
        from unnest(array[
          'public.league_cups',
          'public.league_cup_entries',
          'public.league_cup_rounds',
          'public.league_cup_ties',
          'public.league_cup_draw_runs',
          'public.league_cup_round_finalization_runs',
          'public.league_cup_completion_certificates',
          'public.league_super_cups',
          'public.league_super_cup_schedule_runs',
          'public.league_super_cup_finalization_runs',
          'public.league_playoffs',
          'public.league_playoff_entries',
          'public.league_playoff_rounds',
          'public.league_playoff_ties',
          'public.league_playoff_configuration_runs',
          'public.league_playoff_start_runs',
          'public.league_playoff_round_finalization_runs',
          'public.league_playoff_completion_certificates'
        ]) expected_relation(relation_name)
      ),
      'functions', (
        select jsonb_object_agg(
          signature,
          coalesce(
            md5(pg_catalog.pg_get_functiondef(to_regprocedure(signature)::oid)),
            'missing'
          )
          order by signature
        )
        from unnest(array[
          'public.create_league_cup_guarded_v1(uuid,smallint,uuid)',
          'public.finalize_league_cup_round_guarded_v1(uuid,smallint,uuid)',
          'public.get_league_cup_state_v4(uuid)',
          'public.get_league_cup_draw_integrity_v1(uuid)',
          'public.get_league_cup_round_integrity_v1(uuid)',
          'public.get_league_cup_completion_integrity_v1(uuid)',
          'public.create_league_super_cup_guarded_v1(uuid,smallint,uuid)',
          'public.finalize_league_super_cup_guarded_v1(uuid,uuid)',
          'public.get_league_super_cup_state_v3(uuid)',
          'public.get_league_super_cup_schedule_integrity_v1(uuid)',
          'public.get_league_super_cup_finalization_integrity_v1(uuid)',
          'public.configure_league_playoffs_guarded_v1(uuid,smallint,uuid)',
          'public.start_league_playoffs_guarded_v1(uuid,smallint,uuid)',
          'public.finalize_league_playoff_round_guarded_v1(uuid,smallint,uuid)',
          'public.get_league_playoff_state_v5(uuid)',
          'public.get_league_playoff_configuration_integrity_v1(uuid)',
          'public.get_league_playoff_start_integrity_v1(uuid)',
          'public.get_league_playoff_round_integrity_v1(uuid)',
          'public.get_league_playoff_completion_integrity_v1(uuid)'
        ]) expected_function(signature)
      ),
      'triggers', (
        select coalesce(
          jsonb_agg(
            pg_catalog.pg_get_triggerdef(trigger_row.oid, true)
            order by relation_row.relname, trigger_row.tgname
          ),
          '[]'::jsonb
        )
        from pg_catalog.pg_trigger trigger_row
        join pg_catalog.pg_class relation_row
          on relation_row.oid = trigger_row.tgrelid
        join pg_catalog.pg_namespace namespace_row
          on namespace_row.oid = relation_row.relnamespace
        where not trigger_row.tgisinternal
          and namespace_row.nspname = 'public'
          and trigger_row.tgname in (
            'league_cup_draw_runs_immutable',
            'league_cup_round_finalization_runs_immutable',
            'league_cup_completion_certificates_immutable',
            'league_cup_completion_after_finalization',
            'league_super_cup_schedule_runs_immutable',
            'league_super_cup_finalization_runs_immutable',
            'league_playoff_configuration_runs_immutable',
            'league_playoff_start_runs_immutable',
            'league_playoff_round_runs_immutable',
            'league_playoff_completion_certificates_immutable',
            'league_playoff_completion_after_finalization'
          )
      )
    )::text
  );
$$;

-- Certificazione immutabile del modello. Una deriva futura non viene
-- ricertificata silenziosamente.
do $certification$
declare
  v_readiness jsonb;
  v_fingerprint text;
  v_existing public.leghevo_model_certifications%rowtype;
begin
  v_readiness := public.get_special_competitions_schema_readiness_v1();

  if coalesce((v_readiness ->> 'healthy')::boolean, false) is not true
    or coalesce((v_readiness ->> 'checkCount')::integer, 0) <> 20
    or coalesce((v_readiness ->> 'passedCount')::integer, 0) <> 20 then
    raise exception
      'Il modello competizioni speciali non supera le 20 verifiche. Dettaglio: %',
      coalesce(v_readiness -> 'checks', '{}'::jsonb)::text;
  end if;

  v_fingerprint :=
    public.compute_special_competitions_schema_fingerprint_v1();

  select certification.*
  into v_existing
  from public.leghevo_model_certifications certification
  where certification.model_key = 'special_competitions_v1';

  if found then
    if v_existing.model_version <> 1
      or v_existing.application_version <> '0.61.0'
      or v_existing.schema_fingerprint <> v_fingerprint then
      raise exception
        'La certificazione esistente non coincide con il modello competizioni speciali v1.';
    end if;
  else
    insert into public.leghevo_model_certifications (
      model_key,
      model_version,
      application_version,
      schema_fingerprint,
      readiness
    ) values (
      'special_competitions_v1',
      1,
      '0.61.0',
      v_fingerprint,
      v_readiness
    );
  end if;
end;
$certification$;

-- Stato unificato dello schema certificato e dei dati operativi della lega.
create or replace function public.get_league_special_competitions_model_closure_integrity_v1(
  p_league_id uuid
)
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
  v_cup_draw jsonb;
  v_cup_round jsonb;
  v_cup_completion jsonb;
  v_super_schedule jsonb;
  v_super_finalization jsonb;
  v_playoff_configuration jsonb;
  v_playoff_start jsonb;
  v_playoff_round jsonb;
  v_playoff_completion jsonb;
  v_schema_certified boolean := false;
  v_operational_healthy boolean := false;
begin
  if auth.uid() is null then
    raise exception 'Devi effettuare l''accesso.';
  end if;

  if not public.is_league_member(p_league_id)
    and not public.is_league_admin(p_league_id) then
    raise exception 'Non fai parte di questa lega.';
  end if;

  v_readiness := public.get_special_competitions_schema_readiness_v1();
  v_fingerprint :=
    public.compute_special_competitions_schema_fingerprint_v1();

  select certification.*
  into v_certification
  from public.leghevo_model_certifications certification
  where certification.model_key = 'special_competitions_v1';

  v_schema_certified :=
    found
    and v_certification.model_version = 1
    and v_certification.application_version = '0.61.0'
    and v_certification.schema_fingerprint = v_fingerprint
    and coalesce((v_readiness ->> 'healthy')::boolean, false)
    and coalesce((v_readiness ->> 'checkCount')::integer, 0) = 20
    and coalesce((v_readiness ->> 'passedCount')::integer, 0) = 20;

  v_cup_draw := public.get_league_cup_draw_integrity_v1(p_league_id);
  v_cup_round := public.get_league_cup_round_integrity_v1(p_league_id);
  v_cup_completion :=
    public.get_league_cup_completion_integrity_v1(p_league_id);
  v_super_schedule :=
    public.get_league_super_cup_schedule_integrity_v1(p_league_id);
  v_super_finalization :=
    public.get_league_super_cup_finalization_integrity_v1(p_league_id);
  v_playoff_configuration :=
    public.get_league_playoff_configuration_integrity_v1(p_league_id);
  v_playoff_start :=
    public.get_league_playoff_start_integrity_v1(p_league_id);
  v_playoff_round :=
    public.get_league_playoff_round_integrity_v1(p_league_id);
  v_playoff_completion :=
    public.get_league_playoff_completion_integrity_v1(p_league_id);

  v_operational_healthy :=
    coalesce(
      (v_cup_draw ->> 'healthy')::boolean,
      (v_cup_draw ->> 'ready')::boolean,
      false
    )
    and coalesce(
      (v_cup_round ->> 'healthy')::boolean,
      (v_cup_round ->> 'ready')::boolean,
      false
    )
    and coalesce(
      (v_cup_completion ->> 'healthy')::boolean,
      (v_cup_completion ->> 'ready')::boolean,
      false
    )
    and coalesce(
      (v_super_schedule ->> 'healthy')::boolean,
      (v_super_schedule ->> 'ready')::boolean,
      false
    )
    and coalesce(
      (v_super_finalization ->> 'healthy')::boolean,
      (v_super_finalization ->> 'ready')::boolean,
      false
    )
    and coalesce(
      (v_playoff_configuration ->> 'healthy')::boolean,
      (v_playoff_configuration ->> 'ready')::boolean,
      false
    )
    and coalesce(
      (v_playoff_start ->> 'healthy')::boolean,
      (v_playoff_start ->> 'ready')::boolean,
      false
    )
    and coalesce(
      (v_playoff_round ->> 'healthy')::boolean,
      (v_playoff_round ->> 'ready')::boolean,
      false
    )
    and coalesce(
      (v_playoff_completion ->> 'healthy')::boolean,
      (v_playoff_completion ->> 'ready')::boolean,
      false
    );

  return jsonb_build_object(
    'healthy', v_schema_certified and v_operational_healthy,
    'schemaCertified', v_schema_certified,
    'operationalHealthy', v_operational_healthy,
    'policy', 'special_competitions_model_closed_v1',
    'modelKey', 'special_competitions_v1',
    'modelVersion', 1,
    'applicationVersion', '0.61.0',
    'certifiedAt', v_certification.certified_at,
    'schemaFingerprint', v_fingerprint,
    'storedSchemaFingerprint', v_certification.schema_fingerprint,
    'fingerprintStable',
      v_certification.schema_fingerprint = v_fingerprint,
    'schemaReadiness', v_readiness,
    'cup', jsonb_build_object(
      'draw', v_cup_draw,
      'rounds', v_cup_round,
      'completion', v_cup_completion
    ),
    'superCup', jsonb_build_object(
      'schedule', v_super_schedule,
      'finalization', v_super_finalization
    ),
    'playoffs', jsonb_build_object(
      'configuration', v_playoff_configuration,
      'start', v_playoff_start,
      'rounds', v_playoff_round,
      'completion', v_playoff_completion
    )
  );
end;
$$;

create or replace function public.get_league_management_state_v14(
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
  v_closure jsonb;
  v_checks jsonb;
begin
  v_state := public.get_league_management_state_v13(p_league_id);
  v_closure :=
    public.get_league_special_competitions_model_closure_integrity_v1(
      p_league_id
    );
  v_checks := coalesce(v_state -> 'checks', '{}'::jsonb);

  return v_state || jsonb_build_object(
    'specialCompetitionsModelClosure', v_closure,
    'checks', v_checks || jsonb_build_object(
      'specialCompetitionsModelClosed',
        coalesce((v_closure ->> 'healthy')::boolean, false)
    )
  );
end;
$$;

revoke all on function public.get_special_competitions_schema_readiness_v1()
from public, anon, authenticated;
revoke all on function public.compute_special_competitions_schema_fingerprint_v1()
from public, anon, authenticated;
revoke all on function public.get_league_special_competitions_model_closure_integrity_v1(uuid)
from public, anon;
revoke all on function public.get_league_management_state_v14(uuid)
from public, anon;

grant execute on function public.get_league_special_competitions_model_closure_integrity_v1(uuid)
to authenticated;
grant execute on function public.get_league_management_state_v14(uuid)
to authenticated;

commit;

-- Diagnostica finale: devono risultare esattamente 20 valori true.
select
  to_regclass('public.leghevo_model_certifications') is not null
    as certification_table_ready,
  exists (
    select 1
    from public.leghevo_model_certifications certification
    where certification.model_key = 'special_competitions_v1'
  ) as certification_row_ready,
  exists (
    select 1
    from public.leghevo_model_certifications certification
    where certification.model_key = 'special_competitions_v1'
      and certification.model_version = 1
      and certification.application_version = '0.61.0'
  ) as certification_version_ready,
  exists (
    select 1
    from public.leghevo_model_certifications certification
    where certification.model_key = 'special_competitions_v1'
      and length(certification.schema_fingerprint) = 32
  ) as certification_fingerprint_ready,
  to_regprocedure(
    'public.get_special_competitions_schema_readiness_v1()'
  ) is not null as schema_readiness_ready,
  to_regprocedure(
    'public.compute_special_competitions_schema_fingerprint_v1()'
  ) is not null as schema_fingerprint_function_ready,
  to_regprocedure(
    'public.get_league_special_competitions_model_closure_integrity_v1(uuid)'
  ) is not null as model_closure_integrity_ready,
  to_regprocedure('public.get_league_management_state_v14(uuid)')
    is not null as management_v14_ready,
  exists (
    select 1
    from pg_catalog.pg_trigger trigger_row
    where not trigger_row.tgisinternal
      and trigger_row.tgrelid =
        to_regclass('public.leghevo_model_certifications')
      and trigger_row.tgname = 'leghevo_model_certifications_immutable'
  ) as certification_immutable_ready,
  exists (
    select 1
    from pg_catalog.pg_class relation_row
    where relation_row.oid =
      to_regclass('public.leghevo_model_certifications')
      and relation_row.relrowsecurity
  ) as certification_rls_ready,
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
    'public.get_league_special_competitions_model_closure_integrity_v1(uuid)',
    'EXECUTE'
  ) as authenticated_model_closure_ready,
  public.leghevo_safe_function_privilege_v1(
    'authenticated',
    'public.get_league_management_state_v14(uuid)',
    'EXECUTE'
  ) as authenticated_management_v14_ready,
  not public.leghevo_safe_function_privilege_v1(
    'anon',
    'public.get_league_special_competitions_model_closure_integrity_v1(uuid)',
    'EXECUTE'
  ) as anonymous_model_closure_blocked,
  not public.leghevo_safe_function_privilege_v1(
    'anon',
    'public.get_league_management_state_v14(uuid)',
    'EXECUTE'
  ) as anonymous_management_v14_blocked,
  coalesce(
    (
      public.get_special_competitions_schema_readiness_v1()
      ->> 'checkCount'
    )::integer,
    0
  ) = 20
  and coalesce(
    (
      public.get_special_competitions_schema_readiness_v1()
      ->> 'passedCount'
    )::integer,
    0
  ) = 20 as schema_twenty_checks_ready,
  (
    coalesce(
      (
        public.get_special_competitions_schema_readiness_v1()
        ->> 'healthy'
      )::boolean,
      false
    )
    and exists (
      select 1
      from public.leghevo_model_certifications certification
      where certification.model_key = 'special_competitions_v1'
        and certification.schema_fingerprint =
          public.compute_special_competitions_schema_fingerprint_v1()
    )
  ) as special_competitions_model_closed;
