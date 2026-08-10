-- LEGHEVO · scheduler compatibile con il budget API-Football Free
-- La migrazione riduce soltanto cron provider già esistenti. Non crea job in
-- ambienti nei quali la sincronizzazione automatica non era stata attivata.

begin;

do $scheduler$
declare
  v_has_existing_jobs boolean;
  v_job record;
begin
  if to_regclass('cron.job') is null then
    raise notice 'pg_cron non disponibile: nessuno scheduler modificato.';
    return;
  end if;

  select exists (
    select 1
    from cron.job job
    where job.jobname in (
      'leghevo-sync-fixtures',
      'leghevo-sync-live-ratings',
      'leghevo-sync-final-ratings',
      'leghevo-sync-season-players'
    )
  ) into v_has_existing_jobs;

  if not v_has_existing_jobs then
    raise notice 'Cron provider non attivi: nessun job è stato creato.';
    return;
  end if;

  if not exists (
    select 1 from vault.decrypted_secrets
    where name = 'leghevo_project_url'
  ) or not exists (
    select 1 from vault.decrypted_secrets
    where name = 'leghevo_automations_key'
  ) then
    raise exception
      'Cron provider presenti ma segreti automazione mancanti: modifica annullata.';
  end if;

  for v_job in
    select job.jobid
    from cron.job job
    where job.jobname in (
      'leghevo-sync-fixtures',
      'leghevo-sync-live-ratings',
      'leghevo-sync-final-ratings',
      'leghevo-sync-season-players'
    )
  loop
    perform cron.unschedule(v_job.jobid);
  end loop;

  perform cron.schedule(
    'leghevo-sync-fixtures',
    '7 * * * *',
    $job$
    select net.http_post(
      url := (
        select decrypted_secret
        from vault.decrypted_secrets
        where name = 'leghevo_project_url'
      ) || '/functions/v1/sync-football-data',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'apikey', (
          select decrypted_secret
          from vault.decrypted_secrets
          where name = 'leghevo_automations_key'
        )
      ),
      body := jsonb_build_object(
        'action', 'sync-fixtures',
        'season',
          extract(year from current_date)::integer
          - case when extract(month from current_date) < 7 then 1 else 0 end,
        'date', current_date::text
      )
    ) as request_id;
    $job$
  );

  perform cron.schedule(
    'leghevo-sync-final-ratings',
    '*/10 * * * *',
    $job$
    select net.http_post(
      url := (
        select decrypted_secret
        from vault.decrypted_secrets
        where name = 'leghevo_project_url'
      ) || '/functions/v1/sync-football-data',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'apikey', (
          select decrypted_secret
          from vault.decrypted_secrets
          where name = 'leghevo_automations_key'
        )
      ),
      body := jsonb_build_object(
        'action', 'sync-fixture-players',
        'fixtureId', fixture.provider_fixture_id::bigint
      )
    ) as request_id
    from public.provider_fixtures fixture
    where fixture.provider = 'api-football'
      and fixture.kickoff_at > now() - interval '12 hours'
      and fixture.status in ('FT', 'AET', 'PEN')
      and (
        not exists (
          select 1
          from public.player_match_scores score
          where score.provider = fixture.provider
            and score.provider_fixture_id = fixture.provider_fixture_id
        )
        or exists (
          select 1
          from public.player_match_scores score
          where score.provider = fixture.provider
            and score.provider_fixture_id = fixture.provider_fixture_id
            and not score.is_final
        )
      );
    $job$
  );

  perform cron.schedule(
    'leghevo-sync-season-players',
    '10 4 * * 3',
    $job$
    select net.http_post(
      url := (
        select decrypted_secret
        from vault.decrypted_secrets
        where name = 'leghevo_project_url'
      ) || '/functions/v1/sync-football-data',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'apikey', (
          select decrypted_secret
          from vault.decrypted_secrets
          where name = 'leghevo_automations_key'
        )
      ),
      body := jsonb_build_object(
        'action', 'sync-season-players',
        'season',
          extract(year from current_date)::integer
          - case when extract(month from current_date) < 7 then 1 else 0 end
      )
    ) as request_id;
    $job$
  );
end;
$scheduler$;

commit;
