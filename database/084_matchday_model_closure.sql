-- LEGHEVO · chiusura certificata del modello giornata
-- Versione applicativa: 0.60.0
-- Migrazione prevista: database/084_matchday_model_closure.sql
-- Eseguire dopo database/083_matchday_lifecycle_integrity_hub.sql.
-- Script idempotente: può essere eseguito più volte senza duplicare dati.
-- Revisione correttiva basata sulla diagnostica reale: ripristino RPC correzioni
-- e completamento della pubblicazione Realtime prima della certificazione.

begin;

-- Riparazione verificata della continuità correzioni.
-- La diagnostica pre-v0.60.0 ha rilevato esclusivamente:
--   1) RPC v0.59.6 mancanti;
--   2) tre registri non ancora pubblicati in Supabase Realtime.
-- Le definizioni seguenti ripristinano le RPC originali della migrazione 080
-- senza cancellare dati e senza retrocedere le funzioni di ufficializzazione v3.

create or replace function public.result_correction_input_hash_v1(
  p_league_id uuid,
  p_matchday_id uuid,
  p_fixture_id uuid,
  p_scope text,
  p_reason text
)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_hash text;
begin
  select md5(
    jsonb_build_object(
      'leagueId', league.id,
      'leagueStatus', league.status,
      'competitionStartedAt', league.competition_started_at,
      'matchdayId', matchday.id,
      'matchdayNumber', matchday.number,
      'scope', p_scope,
      'fixtureId', p_fixture_id,
      'reason', trim(coalesce(p_reason, '')),
      'activeOfficializationId', (
        select run.id
        from public.matchday_officialization_runs run
        where run.matchday_id = p_matchday_id
          and run.superseded_at is null
        order by run.id desc
        limit 1
      ),
      'fixtures', coalesce(
        (
          select jsonb_agg(
            jsonb_build_object(
              'fixtureId', fixture.id,
              'finalizedAt', fixture.finalized_at,
              'resultRevision', fixture.result_revision,
              'officializationRunId', fixture.officialization_run_id,
              'officialProjectionId', fixture.official_projection_id,
              'homePoints', fixture.home_points,
              'awayPoints', fixture.away_points,
              'homeGoals', fixture.home_goals,
              'awayGoals', fixture.away_goals,
              'homeCountedPlayers', fixture.home_counted_players,
              'awayCountedPlayers', fixture.away_counted_players
            )
            order by fixture.id
          )
          from public.fantasy_fixtures fixture
          where fixture.league_id = p_league_id
            and fixture.matchday_id = p_matchday_id
            and fixture.finalized_at is not null
            and (
              p_scope = 'matchday'
              or fixture.id = p_fixture_id
            )
        ),
        '[]'::jsonb
      )
    )::text
  )
  into v_hash
  from public.leagues league
  join public.matchdays matchday
    on matchday.id = p_matchday_id
  where league.id = p_league_id
    and exists (
      select 1
      from public.fantasy_fixtures fixture
      where fixture.league_id = p_league_id
        and fixture.matchday_id = p_matchday_id
    );

  return v_hash;
end;
$$;

create or replace function public.reopen_league_fixture_guarded_v1(
  p_league_id uuid,
  p_fixture_id uuid,
  p_reason text,
  p_request_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_league public.leagues%rowtype;
  v_fixture public.fantasy_fixtures%rowtype;
  v_existing public.result_correction_runs%rowtype;
  v_run public.result_correction_runs%rowtype;
  v_reason text := trim(coalesce(p_reason, ''));
  v_input_hash text;
  v_previous_officialization_id bigint;
  v_previous_official_count integer := 0;
  v_revision integer := 1;
  v_matchday_number integer;
  v_home_team_name text;
  v_away_team_name text;
  v_member_user_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Devi effettuare l''accesso.';
  end if;

  if p_request_id is null then
    raise exception 'Identificativo di correzione mancante.';
  end if;

  if char_length(v_reason) < 10
    or char_length(v_reason) > 240 then
    raise exception
      'La motivazione deve contenere da 10 a 240 caratteri.';
  end if;

  select run.*
  into v_existing
  from public.result_correction_runs run
  where run.request_id = p_request_id;

  if found then
    if v_existing.league_id <> p_league_id
      or v_existing.fixture_id is distinct from p_fixture_id
      or v_existing.scope <> 'fixture'
      or v_existing.reason <> v_reason then
      raise exception 'La chiave di correzione è già stata utilizzata.';
    end if;

    return v_existing.result_payload || jsonb_build_object(
      'correctionId', v_existing.id,
      'correctionRevision', v_existing.correction_revision,
      'reopenedAt', v_existing.reopened_at,
      'affectedFixtureCount', v_existing.affected_fixture_count,
      'idempotentReplay', true
    );
  end if;

  select fixture.*
  into v_fixture
  from public.fantasy_fixtures fixture
  where fixture.id = p_fixture_id
    and fixture.league_id = p_league_id;

  if not found then
    raise exception 'Partita non trovata nel calendario della lega.';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'matchday-officialization:'
        || p_league_id::text
        || ':'
        || v_fixture.matchday_id::text,
      0
    )
  );

  select run.*
  into v_existing
  from public.result_correction_runs run
  where run.request_id = p_request_id;

  if found then
    if v_existing.league_id <> p_league_id
      or v_existing.fixture_id is distinct from p_fixture_id
      or v_existing.scope <> 'fixture'
      or v_existing.reason <> v_reason then
      raise exception 'La chiave di correzione è già stata utilizzata.';
    end if;

    return v_existing.result_payload || jsonb_build_object(
      'correctionId', v_existing.id,
      'correctionRevision', v_existing.correction_revision,
      'reopenedAt', v_existing.reopened_at,
      'affectedFixtureCount', v_existing.affected_fixture_count,
      'idempotentReplay', true
    );
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
    raise exception 'Solo il Presidente può correggere un risultato.';
  end if;

  if v_league.status in ('completed', 'archived') then
    raise exception 'La stagione è conclusa: i risultati sono congelati.';
  end if;

  select fixture.*
  into v_fixture
  from public.fantasy_fixtures fixture
  where fixture.id = p_fixture_id
    and fixture.league_id = p_league_id
  for update;

  if v_fixture.finalized_at is null then
    raise exception 'Il risultato selezionato non è ufficiale.';
  end if;

  select count(*) filter (where fixture.finalized_at is not null)::integer
  into v_previous_official_count
  from public.fantasy_fixtures fixture
  where fixture.league_id = p_league_id
    and fixture.matchday_id = v_fixture.matchday_id;

  select run.id
  into v_previous_officialization_id
  from public.matchday_officialization_runs run
  where run.matchday_id = v_fixture.matchday_id
    and run.superseded_at is null
  order by run.id desc
  limit 1;

  v_input_hash := public.result_correction_input_hash_v1(
    p_league_id,
    v_fixture.matchday_id,
    p_fixture_id,
    'fixture',
    v_reason
  );

  if v_input_hash is null then
    raise exception 'Impossibile calcolare l''impronta della correzione.';
  end if;

  select coalesce(max(run.correction_revision), 0) + 1
  into v_revision
  from public.result_correction_runs run
  where run.matchday_id = v_fixture.matchday_id;

  select
    matchday.number,
    home_team.name,
    away_team.name
  into
    v_matchday_number,
    v_home_team_name,
    v_away_team_name
  from public.matchdays matchday
  join public.fantasy_teams home_team
    on home_team.id = v_fixture.home_team_id
  join public.fantasy_teams away_team
    on away_team.id = v_fixture.away_team_id
  where matchday.id = v_fixture.matchday_id;

  insert into public.result_correction_runs (
    league_id,
    matchday_id,
    fixture_id,
    request_id,
    scope,
    correction_revision,
    input_hash,
    reason,
    previous_officialization_id,
    affected_fixture_count,
    previous_official_fixture_count,
    result_payload,
    requested_by
  )
  values (
    p_league_id,
    v_fixture.matchday_id,
    p_fixture_id,
    p_request_id,
    'fixture',
    v_revision,
    v_input_hash,
    v_reason,
    v_previous_officialization_id,
    1,
    v_previous_official_count,
    jsonb_build_object(
      'leagueId', p_league_id,
      'matchdayId', v_fixture.matchday_id,
      'matchdayNumber', v_matchday_number,
      'fixtureId', p_fixture_id,
      'scope', 'fixture',
      'reason', v_reason,
      'previousOfficializationId', v_previous_officialization_id
    ),
    auth.uid()
  )
  returning * into v_run;

  perform set_config(
    'leghevo.matchday_officialization_context',
    'on',
    true
  );

  update public.matchday_officialization_runs run
  set superseded_at = now()
  where run.matchday_id = v_fixture.matchday_id
    and run.superseded_at is null;

  update public.fantasy_fixtures fixture
  set
    finalized_at = null,
    finalized_by = null,
    reopened_at = now(),
    reopened_by = auth.uid(),
    correction_reason = v_reason,
    corrected_at = now(),
    corrected_by = auth.uid(),
    correction_run_id = v_run.id,
    officialization_run_id = null,
    official_projection_id = null
  where fixture.id = p_fixture_id;

  perform public.refresh_matchday_results_internal(v_fixture.matchday_id);

  for v_member_user_id in
    select member.user_id
    from public.league_members member
    where member.league_id = p_league_id
  loop
    perform public.create_user_notification(
      v_member_user_id,
      p_league_id,
      'result',
      'Risultato in correzione · Giornata ' || v_matchday_number,
      v_home_team_name
        || '–'
        || v_away_team_name
        || ' è stato riaperto. Motivo: '
        || v_reason,
      'standings',
      jsonb_build_object(
        'event', 'fixture_reopened_guarded',
        'fixture_id', p_fixture_id,
        'matchday_id', v_fixture.matchday_id,
        'matchday_number', v_matchday_number,
        'correction_id', v_run.id,
        'correction_revision', v_run.correction_revision,
        'reason', v_reason
      ),
      'result:fixture-reopened-guarded:'
        || v_run.id::text
        || ':'
        || v_member_user_id::text
    );
  end loop;

  return v_run.result_payload || jsonb_build_object(
    'correctionId', v_run.id,
    'correctionRevision', v_run.correction_revision,
    'correctionInputHash', v_run.input_hash,
    'reopenedAt', v_run.reopened_at,
    'affectedFixtureCount', 1,
    'idempotentReplay', false
  );
end;
$$;

create or replace function public.reopen_league_matchday_guarded_v1(
  p_league_id uuid,
  p_matchday_id uuid,
  p_reason text,
  p_request_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_league public.leagues%rowtype;
  v_existing public.result_correction_runs%rowtype;
  v_run public.result_correction_runs%rowtype;
  v_reason text := trim(coalesce(p_reason, ''));
  v_input_hash text;
  v_previous_officialization_id bigint;
  v_previous_official_count integer := 0;
  v_revision integer := 1;
  v_matchday_number integer;
  v_member_user_id uuid;
  v_updated integer := 0;
begin
  if auth.uid() is null then
    raise exception 'Devi effettuare l''accesso.';
  end if;

  if p_request_id is null then
    raise exception 'Identificativo di correzione mancante.';
  end if;

  if char_length(v_reason) < 10
    or char_length(v_reason) > 240 then
    raise exception
      'La motivazione deve contenere da 10 a 240 caratteri.';
  end if;

  select run.*
  into v_existing
  from public.result_correction_runs run
  where run.request_id = p_request_id;

  if found then
    if v_existing.league_id <> p_league_id
      or v_existing.matchday_id <> p_matchday_id
      or v_existing.scope <> 'matchday'
      or v_existing.reason <> v_reason then
      raise exception 'La chiave di correzione è già stata utilizzata.';
    end if;

    return v_existing.result_payload || jsonb_build_object(
      'correctionId', v_existing.id,
      'correctionRevision', v_existing.correction_revision,
      'reopenedAt', v_existing.reopened_at,
      'affectedFixtureCount', v_existing.affected_fixture_count,
      'idempotentReplay', true
    );
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'matchday-officialization:'
        || p_league_id::text
        || ':'
        || p_matchday_id::text,
      0
    )
  );

  select run.*
  into v_existing
  from public.result_correction_runs run
  where run.request_id = p_request_id;

  if found then
    if v_existing.league_id <> p_league_id
      or v_existing.matchday_id <> p_matchday_id
      or v_existing.scope <> 'matchday'
      or v_existing.reason <> v_reason then
      raise exception 'La chiave di correzione è già stata utilizzata.';
    end if;

    return v_existing.result_payload || jsonb_build_object(
      'correctionId', v_existing.id,
      'correctionRevision', v_existing.correction_revision,
      'reopenedAt', v_existing.reopened_at,
      'affectedFixtureCount', v_existing.affected_fixture_count,
      'idempotentReplay', true
    );
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
    raise exception 'Solo il Presidente può riaprire la giornata.';
  end if;

  if v_league.status in ('completed', 'archived') then
    raise exception 'La stagione è conclusa: i risultati sono congelati.';
  end if;

  select matchday.number
  into v_matchday_number
  from public.matchdays matchday
  where matchday.id = p_matchday_id
    and exists (
      select 1
      from public.fantasy_fixtures fixture
      where fixture.league_id = p_league_id
        and fixture.matchday_id = p_matchday_id
    )
  for update;

  if not found then
    raise exception 'Giornata non trovata nel calendario della lega.';
  end if;

  select count(*) filter (where fixture.finalized_at is not null)::integer
  into v_previous_official_count
  from public.fantasy_fixtures fixture
  where fixture.league_id = p_league_id
    and fixture.matchday_id = p_matchday_id;

  if v_previous_official_count = 0 then
    raise exception 'La giornata non contiene risultati ufficiali.';
  end if;

  select run.id
  into v_previous_officialization_id
  from public.matchday_officialization_runs run
  where run.matchday_id = p_matchday_id
    and run.superseded_at is null
  order by run.id desc
  limit 1;

  v_input_hash := public.result_correction_input_hash_v1(
    p_league_id,
    p_matchday_id,
    null,
    'matchday',
    v_reason
  );

  if v_input_hash is null then
    raise exception 'Impossibile calcolare l''impronta della correzione.';
  end if;

  select coalesce(max(run.correction_revision), 0) + 1
  into v_revision
  from public.result_correction_runs run
  where run.matchday_id = p_matchday_id;

  insert into public.result_correction_runs (
    league_id,
    matchday_id,
    fixture_id,
    request_id,
    scope,
    correction_revision,
    input_hash,
    reason,
    previous_officialization_id,
    affected_fixture_count,
    previous_official_fixture_count,
    result_payload,
    requested_by
  )
  values (
    p_league_id,
    p_matchday_id,
    null,
    p_request_id,
    'matchday',
    v_revision,
    v_input_hash,
    v_reason,
    v_previous_officialization_id,
    v_previous_official_count,
    v_previous_official_count,
    jsonb_build_object(
      'leagueId', p_league_id,
      'matchdayId', p_matchday_id,
      'matchdayNumber', v_matchday_number,
      'scope', 'matchday',
      'reason', v_reason,
      'previousOfficializationId', v_previous_officialization_id
    ),
    auth.uid()
  )
  returning * into v_run;

  perform set_config(
    'leghevo.matchday_officialization_context',
    'on',
    true
  );

  update public.matchday_officialization_runs run
  set superseded_at = now()
  where run.matchday_id = p_matchday_id
    and run.superseded_at is null;

  update public.fantasy_fixtures fixture
  set
    finalized_at = null,
    finalized_by = null,
    reopened_at = now(),
    reopened_by = auth.uid(),
    correction_reason = v_reason,
    corrected_at = now(),
    corrected_by = auth.uid(),
    correction_run_id = v_run.id,
    officialization_run_id = null,
    official_projection_id = null
  where fixture.league_id = p_league_id
    and fixture.matchday_id = p_matchday_id
    and fixture.finalized_at is not null;

  get diagnostics v_updated = row_count;

  if v_updated <> v_previous_official_count then
    raise exception
      'Riapertura incompleta: % partite riaperte su %.',
      v_updated,
      v_previous_official_count;
  end if;

  perform public.refresh_matchday_results_internal(p_matchday_id);

  for v_member_user_id in
    select member.user_id
    from public.league_members member
    where member.league_id = p_league_id
  loop
    perform public.create_user_notification(
      v_member_user_id,
      p_league_id,
      'result',
      'Giornata riaperta',
      'I risultati della giornata '
        || v_matchday_number
        || ' sono nuovamente in verifica. Motivo: '
        || v_reason,
      'standings',
      jsonb_build_object(
        'event', 'matchday_reopened_guarded',
        'matchday_id', p_matchday_id,
        'matchday_number', v_matchday_number,
        'correction_id', v_run.id,
        'correction_revision', v_run.correction_revision,
        'reason', v_reason
      ),
      'results:matchday-reopened-guarded:'
        || v_run.id::text
        || ':'
        || v_member_user_id::text
    );
  end loop;

  return v_run.result_payload || jsonb_build_object(
    'correctionId', v_run.id,
    'correctionRevision', v_run.correction_revision,
    'correctionInputHash', v_run.input_hash,
    'reopenedAt', v_run.reopened_at,
    'affectedFixtureCount', v_updated,
    'idempotentReplay', false
  );
end;
$$;

create or replace function public.reopen_league_fixture(
  p_league_id uuid,
  p_fixture_id uuid,
  p_reason text
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_result jsonb;
begin
  v_result := public.reopen_league_fixture_guarded_v1(
    p_league_id,
    p_fixture_id,
    p_reason,
    gen_random_uuid()
  );

  return coalesce(
    (v_result ->> 'affectedFixtureCount')::integer,
    0
  );
end;
$$;

create or replace function public.reopen_league_matchday(
  p_league_id uuid,
  p_matchday_id uuid
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_result jsonb;
begin
  v_result := public.reopen_league_matchday_guarded_v1(
    p_league_id,
    p_matchday_id,
    'Riapertura completa della giornata richiesta dal Presidente.',
    gen_random_uuid()
  );

  return coalesce(
    (v_result ->> 'affectedFixtureCount')::integer,
    0
  );
end;
$$;

create or replace function public.get_league_result_correction_integrity_v1(
  p_league_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_hash_issue_count integer := 0;
  v_fixture_link_issue_count integer := 0;
  v_revision_issue_count integer := 0;
  v_active_run_issue_count integer := 0;
  v_full_matchday_link_issue_count integer := 0;
  v_projection_issue_count integer := 0;
  v_trigger_ready boolean := false;
  v_realtime_ready boolean := false;
  v_healthy boolean := false;
begin
  if auth.uid() is null then
    raise exception 'Devi effettuare l''accesso.';
  end if;

  if not public.is_league_member(p_league_id) then
    raise exception 'Non fai parte della lega selezionata.';
  end if;

  select count(*)::integer
  into v_hash_issue_count
  from public.result_correction_runs run
  where run.league_id = p_league_id
    and length(run.input_hash) <> 32;

  select count(*)::integer
  into v_fixture_link_issue_count
  from public.fantasy_fixtures fixture
  left join public.result_correction_runs correction
    on correction.id = fixture.correction_run_id
  where fixture.league_id = p_league_id
    and fixture.correction_run_id is not null
    and (
      correction.id is null
      or correction.league_id <> fixture.league_id
      or correction.matchday_id <> fixture.matchday_id
      or (
        correction.scope = 'fixture'
        and correction.fixture_id <> fixture.id
      )
    );

  select count(*)::integer
  into v_revision_issue_count
  from (
    select
      run.matchday_id,
      min(run.correction_revision) as minimum_revision,
      max(run.correction_revision) as maximum_revision,
      count(*)::integer as revision_count,
      count(distinct run.correction_revision)::integer
        as distinct_revision_count
    from public.result_correction_runs run
    where run.league_id = p_league_id
    group by run.matchday_id
    having min(run.correction_revision) <> 1
      or max(run.correction_revision) <> count(*)
      or count(distinct run.correction_revision) <> count(*)
  ) revision_issues;

  select count(*)::integer
  into v_active_run_issue_count
  from public.matchday_officialization_runs run
  where run.league_id = p_league_id
    and run.superseded_at is null
    and exists (
      select 1
      from public.fantasy_fixtures fixture
      where fixture.matchday_id = run.matchday_id
        and fixture.finalized_at is null
    );

  select count(*)::integer
  into v_full_matchday_link_issue_count
  from (
    select
      fixture.matchday_id,
      count(*) as fixture_count,
      count(*) filter (where fixture.finalized_at is not null) as official_count,
      count(distinct fixture.officialization_run_id) filter (
        where fixture.officialization_run_id is not null
      ) as linked_run_count,
      count(*) filter (
        where fixture.officialization_run_id is null
      ) as missing_link_count
    from public.fantasy_fixtures fixture
    where fixture.league_id = p_league_id
    group by fixture.matchday_id
    having count(*) filter (where fixture.finalized_at is not null) = count(*)
      and (
        count(distinct fixture.officialization_run_id) filter (
          where fixture.officialization_run_id is not null
        ) <> 1
        or count(*) filter (
          where fixture.officialization_run_id is null
        ) > 0
      )
  ) link_issues;

  select count(*)::integer
  into v_projection_issue_count
  from public.fantasy_fixtures fixture
  left join public.live_fixture_projection_runs projection
    on projection.id = fixture.official_projection_id
  where fixture.league_id = p_league_id
    and fixture.finalized_at is not null
    and (
      fixture.official_projection_id is null
      or projection.id is null
      or projection.fixture_id <> fixture.id
      or fixture.home_points is distinct from projection.home_points
      or fixture.away_points is distinct from projection.away_points
      or fixture.home_goals is distinct from projection.home_goals
      or fixture.away_goals is distinct from projection.away_goals
    );

  select exists (
    select 1
    from pg_catalog.pg_trigger trigger_row
    where not trigger_row.tgisinternal
      and trigger_row.tgname = 'result_correction_immutable'
  )
  into v_trigger_ready;

  select exists (
    select 1
    from pg_catalog.pg_publication_tables publication_table
    where publication_table.pubname = 'supabase_realtime'
      and publication_table.schemaname = 'public'
      and publication_table.tablename = 'result_correction_runs'
  )
  into v_realtime_ready;

  v_healthy :=
    v_hash_issue_count = 0
    and v_fixture_link_issue_count = 0
    and v_revision_issue_count = 0
    and v_active_run_issue_count = 0
    and v_full_matchday_link_issue_count = 0
    and v_projection_issue_count = 0
    and v_trigger_ready
    and v_realtime_ready;

  return jsonb_build_object(
    'version', 1,
    'correctionPolicy', 'continuity_v1',
    'hashIssueCount', v_hash_issue_count,
    'fixtureLinkIssueCount', v_fixture_link_issue_count,
    'revisionIssueCount', v_revision_issue_count,
    'activeRunIssueCount', v_active_run_issue_count,
    'fullMatchdayLinkIssueCount', v_full_matchday_link_issue_count,
    'projectionIssueCount', v_projection_issue_count,
    'triggerReady', v_trigger_ready,
    'realtimeReady', v_realtime_ready,
    'healthy', v_healthy
  );
end;
$$;

revoke all on function public.prevent_result_correction_mutation()
from public, anon, authenticated;

-- ACL esplicite: le RPC pubbliche sono riservate agli utenti autenticati;
-- l'helper di impronta resta interno.
revoke all on function public.result_correction_input_hash_v1(
  uuid, uuid, uuid, text, text
) from public, anon, authenticated;

revoke all on function public.reopen_league_fixture_guarded_v1(
  uuid, uuid, text, uuid
) from public, anon, authenticated;
revoke all on function public.reopen_league_matchday_guarded_v1(
  uuid, uuid, text, uuid
) from public, anon, authenticated;
revoke all on function public.reopen_league_fixture(uuid, uuid, text)
from public, anon, authenticated;
revoke all on function public.reopen_league_matchday(uuid, uuid)
from public, anon, authenticated;
revoke all on function public.get_league_result_correction_integrity_v1(uuid)
from public, anon, authenticated;

grant execute on function public.reopen_league_fixture_guarded_v1(
  uuid, uuid, text, uuid
) to authenticated;
grant execute on function public.reopen_league_matchday_guarded_v1(
  uuid, uuid, text, uuid
) to authenticated;
grant execute on function public.reopen_league_fixture(uuid, uuid, text)
to authenticated;
grant execute on function public.reopen_league_matchday(uuid, uuid)
to authenticated;
grant execute on function public.get_league_result_correction_integrity_v1(uuid)
to authenticated;

-- Registro globale delle chiusure di modello. La riga della v1 conserva
-- l'impronta dello schema validato alla chiusura dello Sviluppo 5.
create table if not exists public.leghevo_model_certifications (
  model_key text primary key,
  model_version integer not null,
  application_version text not null,
  schema_fingerprint text not null,
  readiness jsonb not null default '{}'::jsonb,
  certified_at timestamptz not null default now(),
  constraint leghevo_model_certifications_key_check
    check (char_length(trim(model_key)) between 3 and 80),
  constraint leghevo_model_certifications_version_check
    check (model_version >= 1),
  constraint leghevo_model_certifications_app_version_check
    check (char_length(trim(application_version)) between 3 and 24),
  constraint leghevo_model_certifications_fingerprint_check
    check (length(schema_fingerprint) = 32)
);

alter table public.leghevo_model_certifications enable row level security;

drop policy if exists leghevo_model_certifications_read_authenticated
on public.leghevo_model_certifications;
create policy leghevo_model_certifications_read_authenticated
on public.leghevo_model_certifications
for select to authenticated
using (true);

revoke all on table public.leghevo_model_certifications
from public, anon, authenticated;
grant select on table public.leghevo_model_certifications
to authenticated;

-- Rende esplicita la pubblicazione Realtime di tutti i registri dello
-- Sviluppo 5. Le tabelle già pubblicate vengono ignorate.
do $$
declare
  v_table_name text;
begin
  if exists (
    select 1
    from pg_catalog.pg_publication publication
    where publication.pubname = 'supabase_realtime'
  ) then
    foreach v_table_name in array array[
      'lineup_submission_events',
      'lineup_deadline_events',
      'lineup_resolution_runs',
      'lineup_substitution_events',
      'live_fixture_projection_runs',
      'matchday_officialization_runs',
      'result_correction_runs',
      'matchday_progression_runs',
      'season_completion_runs'
    ] loop
      if to_regclass('public.' || v_table_name) is not null
        and not exists (
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
$$;

create or replace function public.prevent_leghevo_model_certification_mutation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if coalesce(
    current_setting('leghevo.model_certification_context', true),
    ''
  ) = 'allowed' then
    if tg_op = 'DELETE' then
      return old;
    end if;
    return new;
  end if;

  raise exception
    'Certificazione del modello protetta: modifica diretta non consentita.';
end;
$$;

drop trigger if exists leghevo_model_certifications_immutable
on public.leghevo_model_certifications;
create trigger leghevo_model_certifications_immutable
before update or delete on public.leghevo_model_certifications
for each row
execute function public.prevent_leghevo_model_certification_mutation();

-- Helper interni: evitano errori quando una diagnostica incontra una relazione
-- o una firma mancante e restituiscono semplicemente false.
create or replace function public.leghevo_safe_table_privilege_v1(
  p_role name,
  p_relation text,
  p_privilege text
)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_relation regclass;
begin
  v_relation := to_regclass(p_relation);
  if v_relation is null then
    return false;
  end if;

  return has_table_privilege(p_role, v_relation, p_privilege);
end;
$$;

create or replace function public.leghevo_safe_function_privilege_v1(
  p_role name,
  p_signature text,
  p_privilege text
)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_function regprocedure;
begin
  v_function := to_regprocedure(p_signature);
  if v_function is null then
    return false;
  end if;

  return has_function_privilege(p_role, v_function, p_privilege);
end;
$$;

-- Verifica strutturale composta da esattamente venti capacità. Non richiede
-- una lega specifica e può essere usata dalla migrazione prima di certificare.
create or replace function public.get_matchday_model_schema_readiness_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_foundation_ready boolean := false;
  v_lineup_submission_ready boolean := false;
  v_deadline_ready boolean := false;
  v_substitution_ready boolean := false;
  v_live_ready boolean := false;
  v_officialization_ready boolean := false;
  v_correction_ready boolean := false;
  v_progression_ready boolean := false;
  v_completion_ready boolean := false;
  v_lifecycle_hub_ready boolean := false;
  v_management_ready boolean := false;
  v_immutable_triggers_ready boolean := false;
  v_rls_ready boolean := false;
  v_realtime_ready boolean := false;
  v_read_access_ready boolean := false;
  v_operational_writes_blocked boolean := false;
  v_registry_writes_blocked boolean := false;
  v_guarded_endpoints_ready boolean := false;
  v_internal_endpoints_private boolean := false;
  v_anonymous_blocked boolean := false;
  v_healthy boolean := false;
begin
  v_foundation_ready :=
    to_regclass('public.leagues') is not null
    and to_regclass('public.matchdays') is not null
    and to_regclass('public.fantasy_fixtures') is not null
    and to_regclass('public.lineups') is not null
    and to_regclass('public.lineup_entries') is not null
    and to_regprocedure('public.is_league_member(uuid)') is not null
    and to_regprocedure('public.is_league_admin(uuid)') is not null;

  v_lineup_submission_ready :=
    to_regclass('public.lineup_submission_events') is not null
    and to_regprocedure(
      'public.save_team_lineup_guarded_v1(uuid,uuid,text,uuid[],uuid[],integer,uuid)'
    ) is not null
    and to_regprocedure('public.get_league_lineup_integrity_v2(uuid)')
      is not null;

  v_deadline_ready :=
    to_regclass('public.lineup_deadline_events') is not null
    and to_regprocedure(
      'public.ensure_matchday_lineups_guarded_v1(uuid,uuid)'
    ) is not null
    and to_regprocedure('public.get_my_lineup_workspace_v3(uuid)') is not null;

  v_substitution_ready :=
    to_regclass('public.lineup_resolution_runs') is not null
    and to_regclass('public.lineup_substitution_events') is not null
    and to_regprocedure(
      'public.certify_team_matchday_substitutions_guarded_v1(uuid,uuid,uuid)'
    ) is not null
    and to_regprocedure('public.get_league_substitution_integrity_v1(uuid)')
      is not null;

  v_live_ready :=
    to_regclass('public.live_fixture_projection_runs') is not null
    and to_regprocedure(
      'public.refresh_live_fixture_projection_guarded_v1(uuid,uuid)'
    ) is not null
    and to_regprocedure('public.get_my_live_match_v6(uuid)') is not null
    and to_regprocedure('public.get_league_live_projection_integrity_v1(uuid)')
      is not null;

  v_officialization_ready :=
    to_regclass('public.matchday_officialization_runs') is not null
    and to_regprocedure(
      'public.finalize_league_matchday_guarded_v3(uuid,uuid,uuid)'
    ) is not null
    and to_regprocedure(
      'public.get_league_matchday_officialization_integrity_v1(uuid)'
    ) is not null;

  v_correction_ready :=
    to_regclass('public.result_correction_runs') is not null
    and to_regprocedure(
      'public.reopen_league_fixture_guarded_v1(uuid,uuid,text,uuid)'
    ) is not null
    and to_regprocedure(
      'public.reopen_league_matchday_guarded_v1(uuid,uuid,text,uuid)'
    ) is not null
    and to_regprocedure('public.get_league_result_correction_integrity_v1(uuid)')
      is not null;

  v_progression_ready :=
    to_regclass('public.matchday_progression_runs') is not null
    and to_regprocedure(
      'public.settle_matchday_progression_guarded_v1(uuid,uuid,uuid)'
    ) is not null
    and to_regprocedure(
      'public.get_league_matchday_progression_integrity_v1(uuid)'
    ) is not null;

  v_completion_ready :=
    to_regclass('public.season_completion_runs') is not null
    and to_regprocedure(
      'public.complete_league_season_guarded_v1(uuid,uuid)'
    ) is not null
    and to_regprocedure(
      'public.get_league_season_completion_integrity_v1(uuid)'
    ) is not null;

  v_lifecycle_hub_ready :=
    to_regprocedure('public.get_league_matchday_lifecycle_state_v1(uuid)')
      is not null
    and to_regprocedure('public.get_league_matchday_lifecycle_integrity_v1(uuid)')
      is not null;

  v_management_ready :=
    to_regprocedure('public.get_league_management_state_v12(uuid)') is not null;

  select count(*) = 8
  into v_immutable_triggers_ready
  from (
    values
      ('public.lineup_resolution_runs', 'lineup_resolution_runs_immutable'),
      ('public.lineup_substitution_events', 'lineup_substitution_events_immutable'),
      ('public.live_fixture_projection_runs', 'live_fixture_projection_immutable'),
      ('public.matchday_officialization_runs', 'matchday_officialization_immutable'),
      ('public.result_correction_runs', 'result_correction_immutable'),
      ('public.matchday_progression_runs', 'matchday_progression_immutable'),
      ('public.season_completion_runs', 'season_completion_immutable'),
      ('public.leghevo_model_certifications', 'leghevo_model_certifications_immutable')
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
      ('public.lineup_submission_events'),
      ('public.lineup_deadline_events'),
      ('public.lineup_resolution_runs'),
      ('public.lineup_substitution_events'),
      ('public.live_fixture_projection_runs'),
      ('public.matchday_officialization_runs'),
      ('public.result_correction_runs'),
      ('public.matchday_progression_runs'),
      ('public.season_completion_runs')
  ) expected(relation_name)
  join pg_catalog.pg_class relation_row
    on relation_row.oid = to_regclass(expected.relation_name)
  where relation_row.relrowsecurity;

  select count(*) = 9
  into v_realtime_ready
  from (
    values
      ('lineup_submission_events'),
      ('lineup_deadline_events'),
      ('lineup_resolution_runs'),
      ('lineup_substitution_events'),
      ('live_fixture_projection_runs'),
      ('matchday_officialization_runs'),
      ('result_correction_runs'),
      ('matchday_progression_runs'),
      ('season_completion_runs')
  ) expected(table_name)
  where exists (
    select 1
    from pg_catalog.pg_publication_tables publication_table
    where publication_table.pubname = 'supabase_realtime'
      and publication_table.schemaname = 'public'
      and publication_table.tablename = expected.table_name
  );

  v_read_access_ready :=
    public.leghevo_safe_table_privilege_v1(
      'authenticated', 'public.lineup_submission_events', 'SELECT'
    )
    and public.leghevo_safe_table_privilege_v1(
      'authenticated', 'public.lineup_deadline_events', 'SELECT'
    )
    and public.leghevo_safe_table_privilege_v1(
      'authenticated', 'public.lineup_resolution_runs', 'SELECT'
    )
    and public.leghevo_safe_table_privilege_v1(
      'authenticated', 'public.lineup_substitution_events', 'SELECT'
    )
    and public.leghevo_safe_table_privilege_v1(
      'authenticated', 'public.live_fixture_projection_runs', 'SELECT'
    )
    and public.leghevo_safe_table_privilege_v1(
      'authenticated', 'public.matchday_officialization_runs', 'SELECT'
    )
    and public.leghevo_safe_table_privilege_v1(
      'authenticated', 'public.result_correction_runs', 'SELECT'
    )
    and public.leghevo_safe_table_privilege_v1(
      'authenticated', 'public.matchday_progression_runs', 'SELECT'
    )
    and public.leghevo_safe_table_privilege_v1(
      'authenticated', 'public.season_completion_runs', 'SELECT'
    );

  v_operational_writes_blocked :=
    not public.leghevo_safe_table_privilege_v1(
      'authenticated', 'public.matchdays', 'UPDATE'
    )
    and not public.leghevo_safe_table_privilege_v1(
      'authenticated', 'public.fantasy_fixtures', 'UPDATE'
    )
    and not public.leghevo_safe_table_privilege_v1(
      'authenticated', 'public.player_match_scores', 'INSERT'
    )
    and not public.leghevo_safe_table_privilege_v1(
      'authenticated', 'public.lineups', 'UPDATE'
    )
    and not public.leghevo_safe_table_privilege_v1(
      'authenticated', 'public.lineup_entries', 'INSERT'
    );

  v_registry_writes_blocked :=
    not public.leghevo_safe_table_privilege_v1(
      'authenticated', 'public.lineup_submission_events', 'INSERT'
    )
    and not public.leghevo_safe_table_privilege_v1(
      'authenticated', 'public.lineup_deadline_events', 'UPDATE'
    )
    and not public.leghevo_safe_table_privilege_v1(
      'authenticated', 'public.lineup_resolution_runs', 'INSERT'
    )
    and not public.leghevo_safe_table_privilege_v1(
      'authenticated', 'public.lineup_substitution_events', 'DELETE'
    )
    and not public.leghevo_safe_table_privilege_v1(
      'authenticated', 'public.live_fixture_projection_runs', 'UPDATE'
    )
    and not public.leghevo_safe_table_privilege_v1(
      'authenticated', 'public.matchday_officialization_runs', 'INSERT'
    )
    and not public.leghevo_safe_table_privilege_v1(
      'authenticated', 'public.result_correction_runs', 'UPDATE'
    )
    and not public.leghevo_safe_table_privilege_v1(
      'authenticated', 'public.matchday_progression_runs', 'INSERT'
    )
    and not public.leghevo_safe_table_privilege_v1(
      'authenticated', 'public.season_completion_runs', 'UPDATE'
    );

  v_guarded_endpoints_ready :=
    public.leghevo_safe_function_privilege_v1(
      'authenticated',
      'public.save_team_lineup_guarded_v1(uuid,uuid,text,uuid[],uuid[],integer,uuid)',
      'EXECUTE'
    )
    and public.leghevo_safe_function_privilege_v1(
      'authenticated', 'public.get_my_lineup_workspace_v3(uuid)', 'EXECUTE'
    )
    and public.leghevo_safe_function_privilege_v1(
      'authenticated', 'public.get_my_live_match_v6(uuid)', 'EXECUTE'
    )
    and public.leghevo_safe_function_privilege_v1(
      'authenticated',
      'public.finalize_league_matchday_guarded_v3(uuid,uuid,uuid)',
      'EXECUTE'
    )
    and public.leghevo_safe_function_privilege_v1(
      'authenticated',
      'public.reopen_league_fixture_guarded_v1(uuid,uuid,text,uuid)',
      'EXECUTE'
    )
    and public.leghevo_safe_function_privilege_v1(
      'authenticated',
      'public.complete_league_season_guarded_v1(uuid,uuid)',
      'EXECUTE'
    );

  v_internal_endpoints_private :=
    not public.leghevo_safe_function_privilege_v1(
      'authenticated',
      'public.ensure_matchday_lineups_guarded_v1(uuid,uuid)',
      'EXECUTE'
    )
    and not public.leghevo_safe_function_privilege_v1(
      'authenticated',
      'public.certify_team_matchday_substitutions_guarded_v1(uuid,uuid,uuid)',
      'EXECUTE'
    )
    and not public.leghevo_safe_function_privilege_v1(
      'authenticated',
      'public.refresh_live_fixture_projection_guarded_v1(uuid,uuid)',
      'EXECUTE'
    )
    and not public.leghevo_safe_function_privilege_v1(
      'authenticated',
      'public.settle_matchday_progression_guarded_v1(uuid,uuid,uuid)',
      'EXECUTE'
    );

  v_anonymous_blocked :=
    not public.leghevo_safe_function_privilege_v1(
      'anon',
      'public.save_team_lineup_guarded_v1(uuid,uuid,text,uuid[],uuid[],integer,uuid)',
      'EXECUTE'
    )
    and not public.leghevo_safe_function_privilege_v1(
      'anon', 'public.get_my_live_match_v6(uuid)', 'EXECUTE'
    )
    and not public.leghevo_safe_function_privilege_v1(
      'anon',
      'public.finalize_league_matchday_guarded_v3(uuid,uuid,uuid)',
      'EXECUTE'
    )
    and not public.leghevo_safe_function_privilege_v1(
      'anon',
      'public.complete_league_season_guarded_v1(uuid,uuid)',
      'EXECUTE'
    );

  v_healthy :=
    v_foundation_ready
    and v_lineup_submission_ready
    and v_deadline_ready
    and v_substitution_ready
    and v_live_ready
    and v_officialization_ready
    and v_correction_ready
    and v_progression_ready
    and v_completion_ready
    and v_lifecycle_hub_ready
    and v_management_ready
    and v_immutable_triggers_ready
    and v_rls_ready
    and v_realtime_ready
    and v_read_access_ready
    and v_operational_writes_blocked
    and v_registry_writes_blocked
    and v_guarded_endpoints_ready
    and v_internal_endpoints_private
    and v_anonymous_blocked;

  return jsonb_build_object(
    'healthy', v_healthy,
    'policy', 'matchday_model_closure_v1',
    'checkCount', 20,
    'checks', jsonb_build_object(
      'foundationReady', v_foundation_ready,
      'lineupSubmissionReady', v_lineup_submission_ready,
      'deadlineReady', v_deadline_ready,
      'substitutionReady', v_substitution_ready,
      'liveReady', v_live_ready,
      'officializationReady', v_officialization_ready,
      'correctionReady', v_correction_ready,
      'progressionReady', v_progression_ready,
      'completionReady', v_completion_ready,
      'lifecycleHubReady', v_lifecycle_hub_ready,
      'managementReady', v_management_ready,
      'immutableTriggersReady', v_immutable_triggers_ready,
      'rlsReady', v_rls_ready,
      'realtimeReady', v_realtime_ready,
      'readAccessReady', v_read_access_ready,
      'operationalWritesBlocked', v_operational_writes_blocked,
      'registryWritesBlocked', v_registry_writes_blocked,
      'guardedEndpointsReady', v_guarded_endpoints_ready,
      'internalEndpointsPrivate', v_internal_endpoints_private,
      'anonymousBlocked', v_anonymous_blocked
    )
  );
end;
$$;

-- Impronta deterministica delle capacità, delle strutture e delle funzioni
-- critiche. Una deriva successiva rende la certificazione non più valida.
create or replace function public.compute_matchday_model_schema_fingerprint_v1()
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select md5(
    jsonb_build_object(
      'modelVersion', 1,
      'readiness', public.get_matchday_model_schema_readiness_v1() -> 'checks',
      'relations', (
        select jsonb_agg(
          jsonb_build_object(
            'name', relation_name,
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
          'public.lineups',
          'public.lineup_entries',
          'public.lineup_submission_events',
          'public.lineup_deadline_events',
          'public.lineup_resolution_runs',
          'public.lineup_substitution_events',
          'public.live_fixture_projection_runs',
          'public.matchday_officialization_runs',
          'public.result_correction_runs',
          'public.matchday_progression_runs',
          'public.season_completion_runs'
        ]) as expected_relation(relation_name)
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
          'public.save_team_lineup_guarded_v1(uuid,uuid,text,uuid[],uuid[],integer,uuid)',
          'public.ensure_matchday_lineups_guarded_v1(uuid,uuid)',
          'public.certify_team_matchday_substitutions_guarded_v1(uuid,uuid,uuid)',
          'public.get_my_live_match_v6(uuid)',
          'public.finalize_league_matchday_guarded_v3(uuid,uuid,uuid)',
          'public.reopen_league_fixture_guarded_v1(uuid,uuid,text,uuid)',
          'public.settle_matchday_progression_guarded_v1(uuid,uuid,uuid)',
          'public.complete_league_season_guarded_v1(uuid,uuid)',
          'public.get_league_matchday_lifecycle_integrity_v1(uuid)',
          'public.get_league_management_state_v12(uuid)'
        ]) as expected_function(signature)
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
            'lineup_resolution_runs_immutable',
            'lineup_substitution_events_immutable',
            'live_fixture_projection_immutable',
            'matchday_officialization_immutable',
            'result_correction_immutable',
            'matchday_progression_immutable',
            'season_completion_immutable'
          )
      )
    )::text
  );
$$;

-- La prima esecuzione crea il certificato. Le riesecuzioni sono ammesse solo
-- se l'impronta coincide: una deriva non viene mai ricertificata in silenzio.
do $$
declare
  v_readiness jsonb;
  v_fingerprint text;
  v_existing public.leghevo_model_certifications%rowtype;
begin
  v_readiness := public.get_matchday_model_schema_readiness_v1();

  if coalesce((v_readiness ->> 'healthy')::boolean, false) is not true
    or coalesce((v_readiness ->> 'checkCount')::integer, 0) <> 20 then
    raise exception
      'Il modello giornata non supera le 20 verifiche. Dettaglio: %',
      coalesce(v_readiness -> 'checks', '{}'::jsonb)::text;
  end if;

  v_fingerprint := public.compute_matchday_model_schema_fingerprint_v1();

  select certification.*
  into v_existing
  from public.leghevo_model_certifications certification
  where certification.model_key = 'matchday_lifecycle_v1';

  if found then
    if v_existing.model_version <> 1
      or v_existing.application_version <> '0.60.0'
      or v_existing.schema_fingerprint <> v_fingerprint then
      raise exception
        'La certificazione esistente non coincide con il modello giornata v1.';
    end if;
  else
    insert into public.leghevo_model_certifications (
      model_key,
      model_version,
      application_version,
      schema_fingerprint,
      readiness
    ) values (
      'matchday_lifecycle_v1',
      1,
      '0.60.0',
      v_fingerprint,
      v_readiness
    );
  end if;
end;
$$;

-- Stato pubblico del modello certificato per una lega. La salute dello schema
-- e quella operativa della lega restano distinte.
create or replace function public.get_league_matchday_model_closure_integrity_v1(
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
  v_lifecycle jsonb;
  v_fingerprint text;
  v_certification public.leghevo_model_certifications%rowtype;
  v_certified boolean := false;
  v_lifecycle_healthy boolean := false;
begin
  if auth.uid() is null then
    raise exception 'Devi effettuare l''accesso.';
  end if;

  if not public.is_league_member(p_league_id)
    and not public.is_league_admin(p_league_id) then
    raise exception 'Non fai parte di questa lega.';
  end if;

  v_readiness := public.get_matchday_model_schema_readiness_v1();
  v_fingerprint := public.compute_matchday_model_schema_fingerprint_v1();
  v_lifecycle :=
    public.get_league_matchday_lifecycle_integrity_v1(p_league_id);

  select certification.*
  into v_certification
  from public.leghevo_model_certifications certification
  where certification.model_key = 'matchday_lifecycle_v1';

  v_certified :=
    found
    and v_certification.model_version = 1
    and v_certification.application_version = '0.60.0'
    and v_certification.schema_fingerprint = v_fingerprint
    and coalesce((v_readiness ->> 'healthy')::boolean, false)
    and coalesce((v_readiness ->> 'checkCount')::integer, 0) = 20;

  v_lifecycle_healthy :=
    coalesce((v_lifecycle ->> 'healthy')::boolean, false);

  return jsonb_build_object(
    'healthy', v_certified,
    'policy', 'matchday_model_closed_v1',
    'modelKey', 'matchday_lifecycle_v1',
    'modelVersion', 1,
    'applicationVersion', '0.60.0',
    'certifiedAt', v_certification.certified_at,
    'schemaFingerprint', v_fingerprint,
    'storedSchemaFingerprint', v_certification.schema_fingerprint,
    'fingerprintStable',
      v_certification.schema_fingerprint = v_fingerprint,
    'schemaReadiness', v_readiness,
    'leagueLifecycleHealthy', v_lifecycle_healthy,
    'leagueLifecycle', v_lifecycle
  );
end;
$$;

create or replace function public.get_league_management_state_v13(
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
  v_state := public.get_league_management_state_v12(p_league_id);
  v_closure :=
    public.get_league_matchday_model_closure_integrity_v1(p_league_id);
  v_checks := coalesce(v_state -> 'checks', '{}'::jsonb);

  return v_state || jsonb_build_object(
    'matchdayModelClosure', v_closure,
    'checks', v_checks || jsonb_build_object(
      'matchdayModelClosed',
        coalesce((v_closure ->> 'healthy')::boolean, false)
    )
  );
end;
$$;

revoke all on function public.prevent_leghevo_model_certification_mutation()
from public, anon, authenticated;
revoke all on function public.leghevo_safe_table_privilege_v1(name, text, text)
from public, anon, authenticated;
revoke all on function public.leghevo_safe_function_privilege_v1(name, text, text)
from public, anon, authenticated;
revoke all on function public.get_matchday_model_schema_readiness_v1()
from public, anon, authenticated;
revoke all on function public.compute_matchday_model_schema_fingerprint_v1()
from public, anon, authenticated;
revoke all on function public.get_league_matchday_model_closure_integrity_v1(uuid)
from public, anon;
revoke all on function public.get_league_management_state_v13(uuid)
from public, anon;

grant execute on function public.get_league_matchday_model_closure_integrity_v1(uuid)
to authenticated;
grant execute on function public.get_league_management_state_v13(uuid)
to authenticated;

commit;

-- Controllo finale: devono risultare esattamente 20 valori true.
select
  to_regclass('public.leghevo_model_certifications') is not null
    as certification_table_ready,
  exists (
    select 1
    from public.leghevo_model_certifications certification
    where certification.model_key = 'matchday_lifecycle_v1'
  ) as certification_row_ready,
  exists (
    select 1
    from public.leghevo_model_certifications certification
    where certification.model_key = 'matchday_lifecycle_v1'
      and certification.model_version = 1
      and certification.application_version = '0.60.0'
  ) as certification_version_ready,
  exists (
    select 1
    from public.leghevo_model_certifications certification
    where certification.model_key = 'matchday_lifecycle_v1'
      and length(certification.schema_fingerprint) = 32
  ) as certification_fingerprint_ready,
  to_regprocedure('public.get_matchday_model_schema_readiness_v1()')
    is not null as schema_readiness_ready,
  to_regprocedure('public.compute_matchday_model_schema_fingerprint_v1()')
    is not null as schema_fingerprint_function_ready,
  to_regprocedure(
    'public.get_league_matchday_model_closure_integrity_v1(uuid)'
  ) is not null as model_closure_integrity_ready,
  to_regprocedure('public.get_league_management_state_v13(uuid)')
    is not null as management_v13_ready,
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
    'public.get_league_matchday_model_closure_integrity_v1(uuid)',
    'EXECUTE'
  ) as authenticated_model_closure_ready,
  public.leghevo_safe_function_privilege_v1(
    'authenticated',
    'public.get_league_management_state_v13(uuid)',
    'EXECUTE'
  ) as authenticated_management_v13_ready,
  not public.leghevo_safe_function_privilege_v1(
    'anon',
    'public.get_league_matchday_model_closure_integrity_v1(uuid)',
    'EXECUTE'
  ) as anonymous_model_closure_blocked,
  not public.leghevo_safe_function_privilege_v1(
    'anon',
    'public.get_league_management_state_v13(uuid)',
    'EXECUTE'
  ) as anonymous_management_v13_blocked,
  coalesce(
    (public.get_matchday_model_schema_readiness_v1() ->> 'checkCount')::integer,
    0
  ) = 20 as schema_twenty_checks_ready,
  (
    coalesce(
      (public.get_matchday_model_schema_readiness_v1() ->> 'healthy')::boolean,
      false
    )
    and exists (
      select 1
      from public.leghevo_model_certifications certification
      where certification.model_key = 'matchday_lifecycle_v1'
        and certification.schema_fingerprint =
          public.compute_matchday_model_schema_fingerprint_v1()
    )
  ) as matchday_model_closed;
