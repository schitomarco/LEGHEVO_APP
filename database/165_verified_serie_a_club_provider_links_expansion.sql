-- LEGHEVO · estensione verificata dei link club Serie A tra provider
-- Le coppie derivano dai cataloghi ufficiali football-data 2025 e
-- API-Football 2024. Nessuna associazione viene dedotta dal solo nome.
begin;

insert into public.verified_club_provider_links (
  club_key,display_name,football_data_id,api_football_id,
  verification_source,evidence,verified_at
) values
  ('atalanta','Atalanta BC','102','499','provider-catalog-cross-check',
    '{"footballDataSeason":2025,"apiFootballSeason":2024}'::jsonb,now()),
  ('bologna','Bologna FC 1909','103','500','provider-catalog-cross-check',
    '{"footballDataSeason":2025,"apiFootballSeason":2024}'::jsonb,now()),
  ('fiorentina','ACF Fiorentina','99','502','provider-catalog-cross-check',
    '{"footballDataSeason":2025,"apiFootballSeason":2024}'::jsonb,now()),
  ('inter','FC Internazionale Milano','108','505','provider-catalog-cross-check',
    '{"footballDataSeason":2025,"apiFootballSeason":2024}'::jsonb,now()),
  ('lazio','SS Lazio','110','487','provider-catalog-cross-check',
    '{"footballDataSeason":2025,"apiFootballSeason":2024}'::jsonb,now())
on conflict (club_key) do update set
  display_name=excluded.display_name,
  football_data_id=excluded.football_data_id,
  api_football_id=excluded.api_football_id,
  verification_source=excluded.verification_source,
  evidence=excluded.evidence;

select public.reconcile_verified_club_provider_links_v1();

commit;
