-- LEGHEVO · pianificazione automatica API-Football
-- Eseguire solo dopo aver creato in Supabase Vault:
--   leghevo_project_url  = https://PROJECT_REF.supabase.co
--   leghevo_automations_key = secret API key Supabase chiamata "automations"
--   leghevo_provider_plan = pro
--
-- Il controllo "pro" evita di consumare il piano gratuito con i cron.

create extension if not exists pg_cron with schema pg_catalog;
create extension if not exists pg_net with schema extensions;

do $$
begin
  if not exists (
    select 1 from vault.decrypted_secrets
    where name = 'leghevo_project_url'
  ) or not exists (
    select 1 from vault.decrypted_secrets
    where name = 'leghevo_automations_key'
  ) then
    raise exception
      'Configura leghevo_project_url e leghevo_automations_key in Supabase Vault.';
  end if;
end;
$$;

do $$
declare
  provider_plan text;
begin
  select lower(trim(decrypted_secret))
  into provider_plan
  from vault.decrypted_secrets
  where name = 'leghevo_provider_plan';

  if provider_plan is distinct from 'pro' then
    raise exception
      'Cron non attivati: crea leghevo_provider_plan=pro nel Vault solo dopo il passaggio al piano API-Football Pro.';
  end if;
end;
$$;

select cron.unschedule(jobid)
from cron.job
where jobname in (
  'leghevo-sync-fixtures',
  'leghevo-sync-live-ratings',
  'leghevo-sync-season-players'
);

select cron.schedule(
  'leghevo-sync-fixtures',
  '*/5 * * * *',
  $$
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
  $$
);

select cron.schedule(
  'leghevo-sync-live-ratings',
  '* * * * *',
  $$
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
    and fixture.kickoff_at > now() - interval '8 hours'
    and (
      fixture.status in ('1H', 'HT', '2H', 'ET', 'BT', 'P', 'LIVE')
      or (
        fixture.status in ('FT', 'AET', 'PEN')
        and (
          not exists (
            select 1
            from public.player_match_scores score
            where score.provider_fixture_id = fixture.provider_fixture_id
          )
          or exists (
            select 1
            from public.player_match_scores score
            where score.provider_fixture_id = fixture.provider_fixture_id
              and not score.is_final
          )
        )
      )
    );
  $$
);

select cron.schedule(
  'leghevo-sync-season-players',
  '10 4 * * *',
  $$
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
  $$
);
