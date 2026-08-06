-- LEGHEVO · parco calciatori fittizi per sviluppo e collaudo
-- Versione: 1
--
-- Scopo:
--   - porta l'archivio di sviluppo a 150 calciatori fittizi;
--   - assegna ruoli Classico e Mantra;
--   - non crea utenti, squadre, rose o acquisti;
--   - non modifica i calciatori provenienti da provider reali;
--   - corregge soltanto il refuso esatto "Seria A da Divano".
--
-- Prerequisiti: 001_initial_schema.sql, 003_api_football_ingestion.sql.
-- Lo script è idempotente e può essere eseguito più volte.

begin;

with generated_players as (
  select
    gs,
    format('pool-2026-%s', lpad(gs::text, 3, '0')) as provider_player_id,
    (array[
      'Alessandro','Andrea','Antonio','Christian','Daniele','Davide','Diego',
      'Edoardo','Elia','Emanuele','Fabio','Federico','Filippo','Francesco',
      'Gabriele','Giacomo','Giorgio','Giovanni','Giulio','Jacopo','Leonardo',
      'Lorenzo','Luca','Manuel','Marco','Matteo','Mattia','Michele','Mirko',
      'Nicolò','Paolo','Pietro','Raffaele','Riccardo','Roberto','Samuele',
      'Simone','Stefano','Thomas','Tommaso','Valerio','Vincenzo','Alberto',
      'Alessio','Cristian','Dario','Enrico','Ivan','Massimo','Salvatore'
    ])[1 + ((gs - 1) % 50)] as first_name,
    (array[
      'Amato','Arena','Barbieri','Basile','Bellini','Benedetti','Bernardi',
      'Bianco','Bruno','Caruso','Cattaneo','Colombo','Conti','Costa','De Angelis',
      'De Luca','De Santis','Esposito','Fabbri','Ferrara','Ferrari','Fiore',
      'Fontana','Galli','Gallo','Gentile','Giordano','Greco','Leone','Lombardi',
      'Longo','Mancini','Marchetti','Marini','Martini','Mazza','Messina',
      'Moretti','Neri','Orlando','Palmieri','Parisi','Pellegrini','Rinaldi',
      'Riva','Romano','Rossetti','Russo','Santoro','Serra','Silvestri','Testa',
      'Valentini','Villa','Vitale','Bianchi','Caputo','D''Amico','Farina','Ferri',
      'Grassi','Marino','Monti','Piras','Ricci','Rizzi','Sanna','Sarti','Sala',
      'Sorrentino','Vitali','Zanetti','Zappa','Zito','Pagano'
    ])[1 + (((gs - 1) * 7) % 75)] as last_name,
    (array[
      'Milano Rossonera','Milano Nerazzurra','Torino Bianconera',
      'Torino Granata','Roma Giallorossa','Roma Biancoceleste','Napoli Azzurra',
      'Bergamo Nerazzurra','Bologna Rossoblù','Firenze Viola','Lecce Giallorossa',
      'Genova Blucerchiata','Genova Rossoblù','Verona Gialloblù','Udine Bianconera',
      'Parma Crociata','Como Lariani','Pisa Nerazzurra','Cagliari Rossoblù',
      'Sassuolo Neroverde'
    ])[1 + (((gs - 1) * 3) % 20)] as club_name,
    case
      when gs between 1 and 18 then 'P'
      when gs between 19 and 66 then 'D'
      when gs between 67 and 114 then 'C'
      else 'A'
    end as classic_role,
    case
      when gs between 1 and 18 then 'Goalkeeper'
      when gs between 19 and 66 then 'Defender'
      when gs between 67 and 114 then 'Midfielder'
      else 'Attacker'
    end as position_code,
    1 + ((gs * 5) % 99) as shirt_number
  from generate_series(1, 150) as gs
)
insert into public.athletes (
  provider,
  provider_player_id,
  first_name,
  last_name,
  club_name,
  shirt_number,
  active,
  position_code,
  payload,
  updated_at
)
select
  'leghevo-development-pool',
  player.provider_player_id,
  player.first_name,
  player.last_name,
  player.club_name,
  player.shirt_number,
  true,
  player.position_code,
  jsonb_build_object(
    'demo', true,
    'dataset', 'development-player-pool-v1',
    'sequence', player.gs
  ),
  now()
from generated_players player
on conflict (provider, provider_player_id) do update
set
  first_name = excluded.first_name,
  last_name = excluded.last_name,
  club_name = excluded.club_name,
  shirt_number = excluded.shirt_number,
  active = true,
  position_code = excluded.position_code,
  payload = excluded.payload,
  updated_at = excluded.updated_at;

with pool as (
  select
    athlete.id,
    (athlete.payload ->> 'sequence')::integer as gs,
    case
      when athlete.position_code = 'Goalkeeper' then 'P'
      when athlete.position_code = 'Defender' then 'D'
      when athlete.position_code = 'Midfielder' then 'C'
      else 'A'
    end as classic_role
  from public.athletes athlete
  where athlete.provider = 'leghevo-development-pool'
)
insert into public.athlete_roles (athlete_id, mode, role_code)
select pool.id, 'classic'::public.league_mode, pool.classic_role
from pool
on conflict do nothing;

with pool as (
  select
    athlete.id,
    (athlete.payload ->> 'sequence')::integer as gs,
    athlete.position_code
  from public.athletes athlete
  where athlete.provider = 'leghevo-development-pool'
), mantra_roles as (
  select
    pool.id,
    case
      when pool.position_code = 'Goalkeeper' then 'Por'
      when pool.position_code = 'Defender' then
        (array['Dd','Dc','Ds','E'])[1 + ((pool.gs - 19) % 4)]
      when pool.position_code = 'Midfielder' then
        (array['M','C','W','T'])[1 + ((pool.gs - 67) % 4)]
      else
        (array['A','Pc'])[1 + ((pool.gs - 115) % 2)]
    end as role_code
  from pool
)
insert into public.athlete_roles (athlete_id, mode, role_code)
select mantra_roles.id, 'mantra'::public.league_mode, mantra_roles.role_code
from mantra_roles
on conflict do nothing;

-- Correzione mirata del refuso già rilevato durante il collaudo.
update public.leagues
set
  name = 'Serie A da Divano',
  updated_at = now()
where name = 'Seria A da Divano';

commit;

-- Controllo finale: attesi 150 calciatori (18 P, 48 D, 48 C, 36 A).
select
  count(*)::integer as totale_calciatori,
  count(*) filter (where role.role_code = 'P')::integer as portieri,
  count(*) filter (where role.role_code = 'D')::integer as difensori,
  count(*) filter (where role.role_code = 'C')::integer as centrocampisti,
  count(*) filter (where role.role_code = 'A')::integer as attaccanti
from public.athletes athlete
join public.athlete_roles role
  on role.athlete_id = athlete.id
 and role.mode = 'classic'
where athlete.provider = 'leghevo-development-pool';
