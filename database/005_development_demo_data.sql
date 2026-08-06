-- LEGHEVO · dati dimostrativi per sviluppo
-- Eseguire dopo 001, 002 e 003.
-- Non crea utenti o leghe: aggiunge soltanto calciatori, ruoli e voti fittizi.
-- Lo script è idempotente e può essere eseguito più volte.

insert into public.matchdays (
  id,
  competition_code,
  season,
  number,
  starts_at,
  locks_at,
  ends_at
)
values (
  'd0000000-0000-4000-8000-000000000007',
  'LEGHEVO-DEMO',
  'DEMO',
  7,
  now() - interval '2 hours',
  now() - interval '3 hours',
  now() + interval '2 hours'
)
on conflict (id) do update
set
  starts_at = excluded.starts_at,
  locks_at = excluded.locks_at,
  ends_at = excluded.ends_at;

insert into public.athletes (
  id,
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
values
  (
    'd1000000-0000-4000-8000-000000000001',
    'leghevo-demo',
    'demo-001',
    'Andrea',
    'Romano',
    'Torino Granata',
    1,
    true,
    'Goalkeeper',
    '{"demo": true}'::jsonb,
    now()
  ),
  (
    'd1000000-0000-4000-8000-000000000002',
    'leghevo-demo',
    'demo-002',
    'Luca',
    'Conti',
    'Milano Rossonera',
    2,
    true,
    'Defender',
    '{"demo": true}'::jsonb,
    now()
  ),
  (
    'd1000000-0000-4000-8000-000000000003',
    'leghevo-demo',
    'demo-003',
    'Davide',
    'Serra',
    'Roma Giallorossa',
    4,
    true,
    'Defender',
    '{"demo": true}'::jsonb,
    now()
  ),
  (
    'd1000000-0000-4000-8000-000000000004',
    'leghevo-demo',
    'demo-004',
    'Nicolò',
    'Greco',
    'Bergamo Nerazzurra',
    5,
    true,
    'Defender',
    '{"demo": true}'::jsonb,
    now()
  ),
  (
    'd1000000-0000-4000-8000-000000000005',
    'leghevo-demo',
    'demo-005',
    'Marco',
    'Riva',
    'Bologna Rossoblù',
    8,
    true,
    'Midfielder',
    '{"demo": true}'::jsonb,
    now()
  ),
  (
    'd1000000-0000-4000-8000-000000000006',
    'leghevo-demo',
    'demo-006',
    'Tommaso',
    'Leone',
    'Napoli Azzurra',
    10,
    true,
    'Midfielder',
    '{"demo": true}'::jsonb,
    now()
  ),
  (
    'd1000000-0000-4000-8000-000000000007',
    'leghevo-demo',
    'demo-007',
    'Samuele',
    'Fiore',
    'Firenze Viola',
    7,
    true,
    'Midfielder',
    '{"demo": true}'::jsonb,
    now()
  ),
  (
    'd1000000-0000-4000-8000-000000000008',
    'leghevo-demo',
    'demo-008',
    'Riccardo',
    'Silva',
    'Milano Nerazzurra',
    9,
    true,
    'Attacker',
    '{"demo": true}'::jsonb,
    now()
  ),
  (
    'd1000000-0000-4000-8000-000000000009',
    'leghevo-demo',
    'demo-009',
    'Edoardo',
    'Marini',
    'Torino Bianconera',
    11,
    true,
    'Attacker',
    '{"demo": true}'::jsonb,
    now()
  ),
  (
    'd1000000-0000-4000-8000-000000000010',
    'leghevo-demo',
    'demo-010',
    'Pietro',
    'Moretti',
    'Lazio Biancoceleste',
    18,
    true,
    'Attacker',
    '{"demo": true}'::jsonb,
    now()
  ),
  (
    'd1000000-0000-4000-8000-000000000011',
    'leghevo-demo',
    'demo-011',
    'Gabriele',
    'Costa',
    'Lecce Giallorossa',
    6,
    true,
    'Midfielder',
    '{"demo": true}'::jsonb,
    now()
  )
on conflict (provider, provider_player_id) do update
set
  first_name = excluded.first_name,
  last_name = excluded.last_name,
  club_name = excluded.club_name,
  shirt_number = excluded.shirt_number,
  active = excluded.active,
  position_code = excluded.position_code,
  payload = excluded.payload,
  updated_at = excluded.updated_at;

insert into public.athlete_roles (athlete_id, mode, role_code)
values
  ('d1000000-0000-4000-8000-000000000001', 'classic', 'P'),
  ('d1000000-0000-4000-8000-000000000002', 'classic', 'D'),
  ('d1000000-0000-4000-8000-000000000003', 'classic', 'D'),
  ('d1000000-0000-4000-8000-000000000004', 'classic', 'D'),
  ('d1000000-0000-4000-8000-000000000005', 'classic', 'C'),
  ('d1000000-0000-4000-8000-000000000006', 'classic', 'C'),
  ('d1000000-0000-4000-8000-000000000007', 'classic', 'C'),
  ('d1000000-0000-4000-8000-000000000008', 'classic', 'A'),
  ('d1000000-0000-4000-8000-000000000009', 'classic', 'A'),
  ('d1000000-0000-4000-8000-000000000010', 'classic', 'A'),
  ('d1000000-0000-4000-8000-000000000011', 'classic', 'C'),
  ('d1000000-0000-4000-8000-000000000001', 'mantra', 'Por'),
  ('d1000000-0000-4000-8000-000000000002', 'mantra', 'Dd'),
  ('d1000000-0000-4000-8000-000000000003', 'mantra', 'Dc'),
  ('d1000000-0000-4000-8000-000000000004', 'mantra', 'Ds'),
  ('d1000000-0000-4000-8000-000000000005', 'mantra', 'M'),
  ('d1000000-0000-4000-8000-000000000006', 'mantra', 'T'),
  ('d1000000-0000-4000-8000-000000000007', 'mantra', 'W'),
  ('d1000000-0000-4000-8000-000000000008', 'mantra', 'Pc'),
  ('d1000000-0000-4000-8000-000000000009', 'mantra', 'A'),
  ('d1000000-0000-4000-8000-000000000010', 'mantra', 'Pc'),
  ('d1000000-0000-4000-8000-000000000011', 'mantra', 'C')
on conflict do nothing;

insert into public.provider_fixtures (
  id,
  provider,
  provider_fixture_id,
  competition_code,
  season,
  matchday_id,
  kickoff_at,
  status,
  home_team_provider_id,
  home_team_name,
  away_team_provider_id,
  away_team_name,
  home_goals,
  away_goals,
  payload,
  updated_at
)
values (
  'd2000000-0000-4000-8000-000000000007',
  'leghevo-demo',
  'demo-fixture-7',
  'LEGHEVO-DEMO',
  'DEMO',
  'd0000000-0000-4000-8000-000000000007',
  now() - interval '90 minutes',
  '2H',
  'demo-home',
  'Milano Rossonera',
  'demo-away',
  'Roma Giallorossa',
  2,
  1,
  '{"demo": true}'::jsonb,
  now()
)
on conflict (provider, provider_fixture_id) do update
set
  matchday_id = excluded.matchday_id,
  kickoff_at = excluded.kickoff_at,
  status = excluded.status,
  home_goals = excluded.home_goals,
  away_goals = excluded.away_goals,
  payload = excluded.payload,
  updated_at = excluded.updated_at;

insert into public.player_match_scores (
  id,
  athlete_id,
  matchday_id,
  provider_fixture_id,
  provider_rating,
  fantasy_score,
  bonuses,
  maluses,
  is_final,
  raw_statistics,
  provider_payload,
  updated_at
)
values
  (
    'd3000000-0000-4000-8000-000000000001',
    'd1000000-0000-4000-8000-000000000001',
    'd0000000-0000-4000-8000-000000000007',
    'demo-fixture-7',
    6.00,
    6.00,
    '{}'::jsonb,
    '{}'::jsonb,
    true,
    '{"minutes": 90}'::jsonb,
    '{"demo": true}'::jsonb,
    now()
  ),
  (
    'd3000000-0000-4000-8000-000000000002',
    'd1000000-0000-4000-8000-000000000002',
    'd0000000-0000-4000-8000-000000000007',
    'demo-fixture-7',
    6.50,
    9.50,
    '{"goals": 1}'::jsonb,
    '{}'::jsonb,
    false,
    '{"minutes": 71}'::jsonb,
    '{"demo": true}'::jsonb,
    now()
  ),
  (
    'd3000000-0000-4000-8000-000000000003',
    'd1000000-0000-4000-8000-000000000003',
    'd0000000-0000-4000-8000-000000000007',
    'demo-fixture-7',
    6.00,
    5.50,
    '{}'::jsonb,
    '{"yellow_cards": 1}'::jsonb,
    false,
    '{"minutes": 71}'::jsonb,
    '{"demo": true}'::jsonb,
    now()
  ),
  (
    'd3000000-0000-4000-8000-000000000004',
    'd1000000-0000-4000-8000-000000000004',
    'd0000000-0000-4000-8000-000000000007',
    'demo-fixture-7',
    6.50,
    6.50,
    '{}'::jsonb,
    '{}'::jsonb,
    false,
    '{"minutes": 71}'::jsonb,
    '{"demo": true}'::jsonb,
    now()
  ),
  (
    'd3000000-0000-4000-8000-000000000005',
    'd1000000-0000-4000-8000-000000000005',
    'd0000000-0000-4000-8000-000000000007',
    'demo-fixture-7',
    6.50,
    6.50,
    '{}'::jsonb,
    '{}'::jsonb,
    false,
    '{"minutes": 71}'::jsonb,
    '{"demo": true}'::jsonb,
    now()
  ),
  (
    'd3000000-0000-4000-8000-000000000006',
    'd1000000-0000-4000-8000-000000000006',
    'd0000000-0000-4000-8000-000000000007',
    'demo-fixture-7',
    7.00,
    8.00,
    '{"assists": 1}'::jsonb,
    '{}'::jsonb,
    false,
    '{"minutes": 71}'::jsonb,
    '{"demo": true}'::jsonb,
    now()
  ),
  (
    'd3000000-0000-4000-8000-000000000007',
    'd1000000-0000-4000-8000-000000000007',
    'd0000000-0000-4000-8000-000000000007',
    'demo-fixture-7',
    5.50,
    5.50,
    '{}'::jsonb,
    '{}'::jsonb,
    false,
    '{"minutes": 38}'::jsonb,
    '{"demo": true}'::jsonb,
    now()
  ),
  (
    'd3000000-0000-4000-8000-000000000008',
    'd1000000-0000-4000-8000-000000000008',
    'd0000000-0000-4000-8000-000000000007',
    'demo-fixture-7',
    6.50,
    7.50,
    '{"assists": 1}'::jsonb,
    '{}'::jsonb,
    false,
    '{"minutes": 71}'::jsonb,
    '{"demo": true}'::jsonb,
    now()
  ),
  (
    'd3000000-0000-4000-8000-000000000009',
    'd1000000-0000-4000-8000-000000000009',
    'd0000000-0000-4000-8000-000000000007',
    'demo-fixture-7',
    6.00,
    6.00,
    '{}'::jsonb,
    '{}'::jsonb,
    false,
    '{"minutes": 71}'::jsonb,
    '{"demo": true}'::jsonb,
    now()
  ),
  (
    'd3000000-0000-4000-8000-000000000010',
    'd1000000-0000-4000-8000-000000000010',
    'd0000000-0000-4000-8000-000000000007',
    'demo-fixture-7',
    5.00,
    2.00,
    '{}'::jsonb,
    '{"missed_penalties": 1}'::jsonb,
    false,
    '{"minutes": 64}'::jsonb,
    '{"demo": true}'::jsonb,
    now()
  ),
  (
    'd3000000-0000-4000-8000-000000000011',
    'd1000000-0000-4000-8000-000000000011',
    'd0000000-0000-4000-8000-000000000007',
    'demo-fixture-7',
    6.00,
    6.00,
    '{}'::jsonb,
    '{}'::jsonb,
    false,
    '{"minutes": 71}'::jsonb,
    '{"demo": true}'::jsonb,
    now()
  )
on conflict (athlete_id, provider_fixture_id)
where provider_fixture_id is not null
do update
set
  matchday_id = excluded.matchday_id,
  provider_rating = excluded.provider_rating,
  fantasy_score = excluded.fantasy_score,
  bonuses = excluded.bonuses,
  maluses = excluded.maluses,
  is_final = excluded.is_final,
  raw_statistics = excluded.raw_statistics,
  provider_payload = excluded.provider_payload,
  updated_at = excluded.updated_at;

select
  (select count(*) from public.athletes where provider = 'leghevo-demo')
    as demo_athletes,
  (
    select count(*)
    from public.player_match_scores
    where provider_fixture_id = 'demo-fixture-7'
  ) as demo_scores;
