-- LEGHEVO · completamento verificato dei link club Serie A corrente
-- ID recuperati con ricerche ufficiali API-Football univoche per paese,
-- codice e prima squadra; nessuna associazione è dedotta dal solo nome.
begin;

insert into public.verified_club_provider_links (
  club_key,display_name,football_data_id,api_football_id,
  verification_source,evidence,verified_at
) values
  ('pisa','AC Pisa 1909','487','801','provider-live-team-search',
    '{"footballDataSeason":2025,"apiFootballCountry":"Italy","apiFootballCode":"PIS"}'::jsonb,now()),
  ('cremonese','US Cremonese','457','520','provider-live-team-search',
    '{"footballDataSeason":2025,"apiFootballCountry":"Italy","apiFootballCode":"CRE"}'::jsonb,now()),
  ('sassuolo','US Sassuolo Calcio','471','488','provider-live-team-search',
    '{"footballDataSeason":2025,"apiFootballCountry":"Italy","apiFootballCode":"SAS"}'::jsonb,now())
on conflict (club_key) do update set
  display_name=excluded.display_name,
  football_data_id=excluded.football_data_id,
  api_football_id=excluded.api_football_id,
  verification_source=excluded.verification_source,
  evidence=excluded.evidence;

select public.reconcile_verified_club_provider_links_v1();

commit;
