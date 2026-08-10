-- LEGHEVO · staging atomico dedicato alle sole partite football-data.org
begin;

do $preflight$
begin
  if to_regprocedure('public.assert_provider_sync_worker_lease_v1(uuid,uuid)') is null
    or to_regprocedure('public.validate_provider_sync_write_contract_v1(text,jsonb)') is null
    or to_regprocedure('public.ensure_provider_sync_publication_v1(uuid,uuid)') is null
    or to_regprocedure('public.refresh_provider_sync_publication_counts_v1(uuid)') is null
    or to_regclass('public.provider_sync_stage_fixtures') is null then
    raise exception 'Preflight 162 non superato: staging atomico provider mancante.';
  end if;
end;
$preflight$;

create or replace function public.stage_football_data_fixture_write_guarded_v1(
  p_run_id uuid,
  p_lease_token uuid,
  p_payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_run public.provider_sync_runs%rowtype;
  v_validation_payload jsonb;
  v_contract jsonb;
  v_publication_id uuid;
  v_count integer := 0;
  v_counts jsonb;
begin
  perform public.assert_provider_sync_worker_lease_v1(p_run_id, p_lease_token);
  select run_row.* into v_run
  from public.provider_sync_runs run_row
  where run_row.id = p_run_id;
  if not found or v_run.provider <> 'football-data'
    or v_run.sync_type <> 'sync-fixtures' or v_run.status <> 'running' then
    raise exception 'Run football-data calendario non valido.';
  end if;
  if jsonb_typeof(coalesce(p_payload, 'null'::jsonb)) <> 'array' then
    raise exception 'Payload football-data calendario non valido.';
  end if;
  if exists (
    select 1 from jsonb_array_elements(p_payload) item
    where item ->> 'provider' <> 'football-data'
  ) then
    raise exception 'Il percorso dedicato accetta soltanto fixture football-data.';
  end if;

  select coalesce(jsonb_agg(item || jsonb_build_object('provider','api-football')), '[]'::jsonb)
  into v_validation_payload
  from jsonb_array_elements(p_payload) item;
  v_contract := public.validate_provider_sync_write_contract_v1(
    'upsert-provider-fixtures', v_validation_payload
  );
  v_publication_id := public.ensure_provider_sync_publication_v1(
    p_run_id, p_lease_token
  );

  with upserted as (
    insert into public.provider_sync_stage_fixtures (
      publication_id, provider, provider_fixture_id, competition_code,
      season, matchday_id, kickoff_at, status, home_team_provider_id,
      home_team_name, away_team_provider_id, away_team_name, home_goals,
      away_goals, payload, source_updated_at
    )
    select
      v_publication_id, item.provider, item.provider_fixture_id,
      item.competition_code, item.season, item.matchday_id,
      item.kickoff_at, item.status, item.home_team_provider_id,
      item.home_team_name, item.away_team_provider_id, item.away_team_name,
      item.home_goals, item.away_goals, coalesce(item.payload, '{}'::jsonb),
      coalesce(item.updated_at, now())
    from jsonb_to_recordset(p_payload) as item(
      provider text, provider_fixture_id text, competition_code text,
      season text, matchday_id uuid, kickoff_at timestamptz, status text,
      home_team_provider_id text, home_team_name text,
      away_team_provider_id text, away_team_name text,
      home_goals smallint, away_goals smallint, payload jsonb,
      updated_at timestamptz
    )
    on conflict (publication_id, provider, provider_fixture_id) do update set
      competition_code = excluded.competition_code,
      season = excluded.season,
      matchday_id = excluded.matchday_id,
      kickoff_at = excluded.kickoff_at,
      status = excluded.status,
      home_team_provider_id = excluded.home_team_provider_id,
      home_team_name = excluded.home_team_name,
      away_team_provider_id = excluded.away_team_provider_id,
      away_team_name = excluded.away_team_name,
      home_goals = excluded.home_goals,
      away_goals = excluded.away_goals,
      payload = excluded.payload,
      source_updated_at = excluded.source_updated_at
    returning 1
  ) select count(*)::integer into v_count from upserted;

  v_counts := public.refresh_provider_sync_publication_counts_v1(v_publication_id);
  return jsonb_build_object(
    'count', v_count,
    'atomicStaging', true,
    'footballDataCalendarOnly', true,
    'publicationId', v_publication_id,
    'contractVersion', v_contract ->> 'contractVersion',
    'stagedRowCount', (v_counts ->> 'stagedRowCount')::integer,
    'stagedPrimaryRecordCount',
      (v_counts ->> 'stagedPrimaryRecordCount')::integer
  );
end;
$$;

revoke all on function public.stage_football_data_fixture_write_guarded_v1(
  uuid,uuid,jsonb
) from public, anon, authenticated;
grant execute on function public.stage_football_data_fixture_write_guarded_v1(
  uuid,uuid,jsonb
) to service_role;

commit;
