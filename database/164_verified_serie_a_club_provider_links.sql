-- LEGHEVO · registro esplicito dei club Serie A verificati tra provider
begin;

create table if not exists public.verified_club_provider_links (
  club_key text primary key,
  display_name text not null,
  football_data_id text not null unique,
  api_football_id text not null unique,
  verification_source text not null,
  evidence jsonb not null default '{}'::jsonb,
  status text not null default 'pending' check (status in ('pending','confirmed','conflict')),
  canonical_entity_id uuid references public.canonical_football_entities(id) on delete restrict,
  verified_at timestamptz not null,
  reconciled_at timestamptz,
  check (club_key = lower(trim(club_key))),
  check (football_data_id ~ '^[0-9]+$' and api_football_id ~ '^[0-9]+$')
);

insert into public.verified_club_provider_links (
  club_key,display_name,football_data_id,api_football_id,
  verification_source,evidence,verified_at
) values
  ('ac-milan','AC Milan','98','489','provider-catalog-cross-check',
    '{"footballDataSeason":2025,"apiFootballSeason":2024}'::jsonb,now()),
  ('as-roma','AS Roma','100','497','provider-catalog-cross-check',
    '{"footballDataSeason":2025,"apiFootballSeason":2024}'::jsonb,now()),
  ('cagliari','Cagliari Calcio','104','490','provider-catalog-cross-check',
    '{"footballDataSeason":2025,"apiFootballSeason":2024}'::jsonb,now()),
  ('genoa','Genoa CFC','107','495','provider-catalog-cross-check',
    '{"footballDataSeason":2025,"apiFootballSeason":2024}'::jsonb,now()),
  ('juventus','Juventus FC','109','496','provider-catalog-cross-check',
    '{"footballDataSeason":2025,"apiFootballSeason":2024}'::jsonb,now()),
  ('parma','Parma Calcio 1913','112','523','provider-catalog-cross-check',
    '{"footballDataSeason":2025,"apiFootballSeason":2024}'::jsonb,now()),
  ('napoli','SSC Napoli','113','492','provider-catalog-cross-check',
    '{"footballDataSeason":2025,"apiFootballSeason":2024}'::jsonb,now()),
  ('udinese','Udinese Calcio','115','494','provider-catalog-cross-check',
    '{"footballDataSeason":2025,"apiFootballSeason":2024}'::jsonb,now()),
  ('hellas-verona','Hellas Verona FC','450','504','provider-catalog-cross-check',
    '{"footballDataSeason":2025,"apiFootballSeason":2024}'::jsonb,now()),
  ('torino','Torino FC','586','503','provider-catalog-cross-check',
    '{"footballDataSeason":2025,"apiFootballSeason":2024}'::jsonb,now()),
  ('lecce','US Lecce','5890','867','provider-catalog-cross-check',
    '{"footballDataSeason":2025,"apiFootballSeason":2024}'::jsonb,now()),
  ('como','Como 1907','7397','895','provider-catalog-cross-check',
    '{"footballDataSeason":2025,"apiFootballSeason":2024}'::jsonb,now())
on conflict (club_key) do update set
  display_name=excluded.display_name,
  football_data_id=excluded.football_data_id,
  api_football_id=excluded.api_football_id,
  verification_source=excluded.verification_source,
  evidence=excluded.evidence;

create or replace function public.reconcile_verified_club_provider_links_v1()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_link public.verified_club_provider_links%rowtype;
  v_fd_mapping public.provider_entity_mappings%rowtype;
  v_api_mapping public.provider_entity_mappings%rowtype;
  v_confirmed integer := 0;
  v_pending integer := 0;
  v_conflicts integer := 0;
begin
  for v_link in
    select link.* from public.verified_club_provider_links link
    order by link.club_key for update
  loop
    select mapping.* into v_fd_mapping
    from public.provider_entity_mappings mapping
    where mapping.provider='football-data' and mapping.entity_type='club'
      and mapping.external_id=v_link.football_data_id;
    if not found then
      update public.verified_club_provider_links link set
        status='pending',canonical_entity_id=null,reconciled_at=now()
      where link.club_key=v_link.club_key;
      v_pending := v_pending + 1;
      continue;
    end if;

    select mapping.* into v_api_mapping
    from public.provider_entity_mappings mapping
    where mapping.provider='api-football' and mapping.entity_type='club'
      and mapping.external_id=v_link.api_football_id;
    if not found then
      insert into public.provider_entity_mappings (
        canonical_entity_id,provider,entity_type,external_id,mapping_status,
        confidence,evidence,verified_at
      ) values (
        v_fd_mapping.canonical_entity_id,'api-football','club',
        v_link.api_football_id,'confirmed',1,
        jsonb_build_object(
          'source',v_link.verification_source,'clubKey',v_link.club_key,
          'footballDataId',v_link.football_data_id
        ) || v_link.evidence,v_link.verified_at
      );
    elsif v_api_mapping.canonical_entity_id is distinct from v_fd_mapping.canonical_entity_id then
      update public.provider_entity_mappings mapping set
        mapping_status='quarantined',updated_at=now()
      where mapping.id=v_api_mapping.id;
      insert into public.provider_identity_conflicts (
        entity_type,provider,external_id,candidate_canonical_ids,
        reason_code,evidence,status
      ) values (
        'club','api-football',v_link.api_football_id,
        array[v_api_mapping.canonical_entity_id,v_fd_mapping.canonical_entity_id],
        'verified_registry_existing_mapping_mismatch',
        jsonb_build_object('clubKey',v_link.club_key), 'open'
      ) on conflict (provider,entity_type,external_id) where status='open'
      do update set
        candidate_canonical_ids=excluded.candidate_canonical_ids,
        reason_code=excluded.reason_code,evidence=excluded.evidence;
      update public.verified_club_provider_links link set
        status='conflict',canonical_entity_id=null,reconciled_at=now()
      where link.club_key=v_link.club_key;
      v_conflicts := v_conflicts + 1;
      continue;
    else
      update public.provider_entity_mappings mapping set
        mapping_status='confirmed',confidence=1,
        evidence=mapping.evidence || jsonb_build_object(
          'verifiedRegistry',true,'clubKey',v_link.club_key
        ),verified_at=v_link.verified_at,updated_at=now()
      where mapping.id=v_api_mapping.id;
    end if;

    update public.verified_club_provider_links link set
      status='confirmed',canonical_entity_id=v_fd_mapping.canonical_entity_id,
      reconciled_at=now()
    where link.club_key=v_link.club_key;
    v_confirmed := v_confirmed + 1;
  end loop;
  return jsonb_build_object(
    'protected',true,'total',v_confirmed+v_pending+v_conflicts,
    'confirmed',v_confirmed,'pending',v_pending,'conflicts',v_conflicts
  );
end;
$$;

revoke all on function public.reconcile_verified_club_provider_links_v1()
from public, anon, authenticated;
grant execute on function public.reconcile_verified_club_provider_links_v1()
to service_role;

alter table public.verified_club_provider_links enable row level security;
revoke all on public.verified_club_provider_links from public,anon,authenticated;
grant select,insert,update on public.verified_club_provider_links to service_role;

select public.reconcile_verified_club_provider_links_v1();

commit;
