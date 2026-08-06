-- LEGHEVO v0.62.12 · Contratti runtime e quarantena dei payload provider
-- Migrazione interna: database/116_provider_payload_contract_quarantine_safety.sql
--
-- Obiettivi:
-- - validare a runtime i payload API-Football prima di ogni scrittura;
-- - applicare lo stesso contratto nel database insieme al fencing worker;
-- - respingere e certificare i payload fuori contratto senza conservarne il contenuto grezzo;
-- - classificare gli errori di schema come non recuperabili, evitando retry inutili;
-- - esporre lo stato dei contratti nel Centro Operativo;
-- - terminare con una diagnostica strutturale di esattamente 20 controlli.

begin;

-- Preflight esplicito delle sole dipendenze realmente utilizzate.
do $preflight$
declare
  v_missing text[] := array[]::text[];
  v_expected record;
begin
  for v_expected in
    select *
    from (values
      ('leagues', 'id'),
      ('leagues', 'owner_id'),
      ('provider_sync_runs', 'id'),
      ('provider_sync_runs', 'provider'),
      ('provider_sync_runs', 'sync_type'),
      ('provider_sync_runs', 'status'),
      ('provider_sync_runs', 'revision'),
      ('provider_sync_runs', 'error_message'),
      ('provider_recovery_requests', 'id'),
      ('provider_recovery_requests', 'league_id'),
      ('provider_recovery_requests', 'recovery_run_id'),
      ('provider_sync_worker_leases', 'run_id'),
      ('provider_sync_worker_leases', 'recovery_request_id'),
      ('provider_sync_worker_leases', 'league_id'),
      ('provider_sync_worker_leases', 'lease_token'),
      ('provider_sync_worker_leases', 'lease_epoch'),
      ('provider_sync_worker_leases', 'status')
    ) as expected(table_name, column_name)
  loop
    if not exists (
      select 1
      from information_schema.columns column_row
      where column_row.table_schema = 'public'
        and column_row.table_name = v_expected.table_name
        and column_row.column_name = v_expected.column_name
    ) then
      v_missing := array_append(
        v_missing,
        format('column public.%I.%I', v_expected.table_name, v_expected.column_name)
      );
    end if;
  end loop;

  if to_regprocedure('auth.uid()') is null then
    v_missing := array_append(v_missing, 'function auth.uid()');
  end if;
  if to_regprocedure('gen_random_uuid()') is null then
    v_missing := array_append(v_missing, 'function gen_random_uuid()');
  end if;
  if to_regprocedure('public.is_league_admin(uuid)') is null then
    v_missing := array_append(v_missing, 'function public.is_league_admin(uuid)');
  end if;
  if to_regprocedure(
    'public.assert_provider_sync_worker_lease_v1(uuid,uuid)'
  ) is null then
    v_missing := array_append(
      v_missing,
      'function public.assert_provider_sync_worker_lease_v1(uuid,uuid)'
    );
  end if;
  if to_regprocedure(
    'public.apply_provider_sync_write_guarded_v1(uuid,uuid,text,jsonb)'
  ) is null then
    v_missing := array_append(
      v_missing,
      'function public.apply_provider_sync_write_guarded_v1(uuid,uuid,text,jsonb)'
    );
  end if;
  if to_regprocedure(
    'public.provider_recovery_retry_policy_v1(text,integer,text)'
  ) is null then
    v_missing := array_append(
      v_missing,
      'function public.provider_recovery_retry_policy_v1(text,integer,text)'
    );
  end if;
  if to_regprocedure(
    'public.get_league_provider_sync_health_v10(uuid)'
  ) is null then
    v_missing := array_append(
      v_missing,
      'function public.get_league_provider_sync_health_v10(uuid)'
    );
  end if;
  if to_regprocedure(
    'public.get_provider_worker_lease_fencing_integrity_v1()'
  ) is null then
    v_missing := array_append(
      v_missing,
      'function public.get_provider_worker_lease_fencing_integrity_v1()'
    );
  end if;

  if not exists (
    select 1 from pg_catalog.pg_roles role_row where role_row.rolname = 'anon'
  ) then
    v_missing := array_append(v_missing, 'role anon');
  end if;
  if not exists (
    select 1 from pg_catalog.pg_roles role_row where role_row.rolname = 'authenticated'
  ) then
    v_missing := array_append(v_missing, 'role authenticated');
  end if;
  if not exists (
    select 1 from pg_catalog.pg_roles role_row where role_row.rolname = 'service_role'
  ) then
    v_missing := array_append(v_missing, 'role service_role');
  end if;

  if coalesce(array_length(v_missing, 1), 0) > 0 then
    raise exception
      'Preflight v0.62.12 non superato. Oggetti mancanti: %',
      array_to_string(v_missing, '; ');
  end if;
end;
$preflight$;

create table if not exists public.provider_payload_contract_violations (
  id uuid primary key default gen_random_uuid(),
  run_id uuid not null,
  recovery_request_id uuid,
  league_id uuid,
  provider text not null,
  sync_type text not null,
  contract_scope text not null,
  contract_version text not null,
  violation_code text not null,
  item_index integer,
  summary text not null,
  payload_fingerprint text not null,
  payload_size integer not null,
  run_revision bigint not null,
  lease_epoch bigint not null,
  detected_at timestamptz not null default now(),
  constraint provider_payload_contract_violations_run_fk
    foreign key (run_id)
    references public.provider_sync_runs(id)
    on delete restrict,
  constraint provider_payload_contract_violations_request_fk
    foreign key (recovery_request_id)
    references public.provider_recovery_requests(id)
    on delete set null,
  constraint provider_payload_contract_violations_league_fk
    foreign key (league_id)
    references public.leagues(id)
    on delete set null,
  constraint provider_payload_contract_violations_run_uidx
    unique (run_id),
  constraint provider_payload_contract_violations_provider_check
    check (provider = lower(trim(provider)) and length(provider) between 1 and 60),
  constraint provider_payload_contract_violations_sync_type_check
    check (
      sync_type in (
        'sync-season-players',
        'sync-fixtures',
        'sync-fixture-players'
      )
    ),
  constraint provider_payload_contract_violations_scope_check
    check (
      length(contract_scope) between 1 and 120
      and contract_scope ~ '^[a-z0-9:/._-]+$'
    ),
  constraint provider_payload_contract_violations_version_check
    check (
      length(contract_version) between 1 and 120
      and contract_version ~ '^[a-z0-9:/._-]+$'
    ),
  constraint provider_payload_contract_violations_code_check
    check (
      length(violation_code) between 1 and 80
      and violation_code ~ '^[a-z0-9._-]+$'
    ),
  constraint provider_payload_contract_violations_item_check
    check (item_index is null or item_index >= 0),
  constraint provider_payload_contract_violations_summary_check
    check (
      length(summary) between 1 and 500
      and summary !~ E'[\\r\\n]'
    ),
  constraint provider_payload_contract_violations_fingerprint_check
    check (payload_fingerprint ~ '^[0-9a-f]{64}$'),
  constraint provider_payload_contract_violations_size_check
    check (payload_size between 0 and 50000000),
  constraint provider_payload_contract_violations_revision_check
    check (run_revision > 0 and lease_epoch > 0)
);

create index if not exists provider_payload_contract_violations_detected_idx
  on public.provider_payload_contract_violations (detected_at desc);
create index if not exists provider_payload_contract_violations_league_idx
  on public.provider_payload_contract_violations (league_id, detected_at desc);
create index if not exists provider_payload_contract_violations_scope_idx
  on public.provider_payload_contract_violations (contract_scope, detected_at desc);

alter table public.provider_payload_contract_violations enable row level security;
alter table public.provider_payload_contract_violations replica identity full;

revoke all on table public.provider_payload_contract_violations
from public, anon, authenticated;
grant select on table public.provider_payload_contract_violations
to authenticated;
grant all on table public.provider_payload_contract_violations
to service_role;

-- Le violazioni non contengono il payload originale. I Direttori possono leggere
-- soltanto il registro certificato della propria lega e gli eventi globali del
-- provider se amministrano almeno una lega.
drop policy if exists provider_payload_contract_violations_read_directors
on public.provider_payload_contract_violations;
create policy provider_payload_contract_violations_read_directors
on public.provider_payload_contract_violations
for select
to authenticated
using (
  (
    league_id is not null
    and exists (
      select 1
      from public.leagues league_row
      where league_row.id = provider_payload_contract_violations.league_id
        and (
          league_row.owner_id = auth.uid()
          or public.is_league_admin(league_row.id)
        )
    )
  )
  or (
    league_id is null
    and exists (
      select 1
      from public.leagues league_row
      where league_row.owner_id = auth.uid()
        or public.is_league_admin(league_row.id)
    )
  )
);

create or replace function public.prevent_provider_payload_contract_violation_mutation_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  raise exception 'Il registro delle violazioni dei contratti provider è immutabile.';
end;
$$;

revoke all on function public.prevent_provider_payload_contract_violation_mutation_v1()
from public, anon, authenticated;

drop trigger if exists provider_payload_contract_violations_immutable
on public.provider_payload_contract_violations;
create trigger provider_payload_contract_violations_immutable
before update or delete on public.provider_payload_contract_violations
for each row execute function public.prevent_provider_payload_contract_violation_mutation_v1();

create or replace function public.provider_payload_contract_version_v1()
returns text
language sql
immutable
set search_path = ''
as $$
  select 'api-football-v3/leghevo-contract-v1'::text
$$;

revoke all on function public.provider_payload_contract_version_v1()
from public, anon, authenticated;
grant execute on function public.provider_payload_contract_version_v1()
to service_role;

create or replace function public.provider_contract_uuid_text_v1(p_value text)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select coalesce(trim(p_value), '') ~*
    '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
$$;

revoke all on function public.provider_contract_uuid_text_v1(text)
from public, anon, authenticated;

create or replace function public.provider_contract_positive_id_v1(p_value text)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select coalesce(trim(p_value), '') ~ '^[1-9][0-9]*$'
$$;

revoke all on function public.provider_contract_positive_id_v1(text)
from public, anon, authenticated;

-- Contratto database indipendente dalla Edge Function: anche un worker alternativo
-- non può aggirare i campi minimi richiesti dalle scritture provider.
create or replace function public.validate_provider_sync_write_contract_v1(
  p_operation text,
  p_payload jsonb
)
returns jsonb
language plpgsql
immutable
security definer
set search_path = ''
as $$
declare
  v_operation text := lower(trim(coalesce(p_operation, '')));
  v_item jsonb;
  v_index integer;
  v_count integer := 0;
begin
  if v_operation not in (
    'upsert-athletes',
    'upsert-athlete-roles',
    'upsert-matchday',
    'upsert-provider-fixtures',
    'upsert-player-scores'
  ) then
    raise exception
      'Payload provider non valido [operation.unsupported]: operazione % non riconosciuta.',
      coalesce(nullif(v_operation, ''), '<vuota>');
  end if;

  if v_operation = 'upsert-matchday' then
    if jsonb_typeof(coalesce(p_payload, 'null'::jsonb)) <> 'object' then
      raise exception 'Payload provider non valido [matchday.object]: è richiesto un oggetto.';
    end if;

    if trim(coalesce(p_payload ->> 'competition_code', '')) <> 'IT-SA' then
      raise exception 'Payload provider non valido [matchday.competition_code].';
    end if;
    if coalesce(p_payload ->> 'season', '') !~ '^[0-9]{4}$' then
      raise exception 'Payload provider non valido [matchday.season].';
    end if;
    if coalesce(p_payload ->> 'number', '') !~ '^[1-9][0-9]*$' then
      raise exception 'Payload provider non valido [matchday.number].';
    end if;
    if coalesce(jsonb_typeof(p_payload -> 'starts_at'), 'missing') <> 'string'
      or coalesce(jsonb_typeof(p_payload -> 'locks_at'), 'missing') <> 'string'
      or coalesce(jsonb_typeof(p_payload -> 'ends_at'), 'missing') <> 'string' then
      raise exception 'Payload provider non valido [matchday.timestamps].';
    end if;

    begin
      if (p_payload ->> 'starts_at')::timestamptz
        > (p_payload ->> 'ends_at')::timestamptz then
        raise exception 'Payload provider non valido [matchday.interval].';
      end if;
      perform (p_payload ->> 'locks_at')::timestamptz;
    exception
      when invalid_datetime_format or datetime_field_overflow then
        raise exception 'Payload provider non valido [matchday.timestamps].';
    end;

    return jsonb_build_object(
      'valid', true,
      'contractVersion', public.provider_payload_contract_version_v1(),
      'operation', v_operation,
      'itemCount', 1
    );
  end if;

  if jsonb_typeof(coalesce(p_payload, 'null'::jsonb)) <> 'array' then
    raise exception
      'Payload provider non valido [array.required]: % richiede un array.',
      v_operation;
  end if;

  for v_item, v_index in
    select element.value, (element.ordinality - 1)::integer
    from jsonb_array_elements(p_payload) with ordinality as element(value, ordinality)
  loop
    v_count := v_count + 1;

    if jsonb_typeof(v_item) <> 'object' then
      raise exception
        'Payload provider non valido [item.object] all''indice %.',
        v_index;
    end if;

    if v_operation = 'upsert-athletes' then
      if trim(coalesce(v_item ->> 'provider', '')) <> 'api-football' then
        raise exception
          'Payload provider non valido [athlete.provider] all''indice %.',
          v_index;
      end if;
      if not public.provider_contract_positive_id_v1(
        v_item ->> 'provider_player_id'
      ) then
        raise exception
          'Payload provider non valido [athlete.provider_player_id] all''indice %.',
          v_index;
      end if;
      if coalesce(jsonb_typeof(v_item -> 'last_name'), 'missing') <> 'string'
        or length(trim(coalesce(v_item ->> 'last_name', ''))) = 0 then
        raise exception
          'Payload provider non valido [athlete.last_name] all''indice %.',
          v_index;
      end if;
      if coalesce(jsonb_typeof(v_item -> 'club_name'), 'missing') <> 'string'
        or length(trim(coalesce(v_item ->> 'club_name', ''))) = 0 then
        raise exception
          'Payload provider non valido [athlete.club_name] all''indice %.',
          v_index;
      end if;
      if v_item ? 'provider_team_id'
        and jsonb_typeof(v_item -> 'provider_team_id') not in ('string', 'null') then
        raise exception
          'Payload provider non valido [athlete.provider_team_id] all''indice %.',
          v_index;
      end if;
      if v_item ? 'position_code'
        and jsonb_typeof(v_item -> 'position_code') not in ('string', 'null') then
        raise exception
          'Payload provider non valido [athlete.position_code] all''indice %.',
          v_index;
      end if;
      if coalesce(jsonb_typeof(v_item -> 'active'), 'missing') <> 'boolean' then
        raise exception
          'Payload provider non valido [athlete.active] all''indice %.',
          v_index;
      end if;
      if coalesce(jsonb_typeof(v_item -> 'payload'), 'missing') <> 'object' then
        raise exception
          'Payload provider non valido [athlete.payload] all''indice %.',
          v_index;
      end if;
      if coalesce(jsonb_typeof(v_item -> 'updated_at'), 'missing') <> 'string' then
        raise exception
          'Payload provider non valido [athlete.updated_at] all''indice %.',
          v_index;
      end if;

    elsif v_operation = 'upsert-athlete-roles' then
      if not public.provider_contract_uuid_text_v1(v_item ->> 'athlete_id') then
        raise exception
          'Payload provider non valido [role.athlete_id] all''indice %.',
          v_index;
      end if;
      if coalesce(v_item ->> 'mode', '') not in ('classic', 'mantra') then
        raise exception
          'Payload provider non valido [role.mode] all''indice %.',
          v_index;
      end if;
      if coalesce(jsonb_typeof(v_item -> 'role_code'), 'missing') <> 'string'
        or length(trim(coalesce(v_item ->> 'role_code', ''))) = 0 then
        raise exception
          'Payload provider non valido [role.role_code] all''indice %.',
          v_index;
      end if;

    elsif v_operation = 'upsert-provider-fixtures' then
      if trim(coalesce(v_item ->> 'provider', '')) <> 'api-football' then
        raise exception
          'Payload provider non valido [fixture.provider] all''indice %.',
          v_index;
      end if;
      if not public.provider_contract_positive_id_v1(
        v_item ->> 'provider_fixture_id'
      ) then
        raise exception
          'Payload provider non valido [fixture.provider_fixture_id] all''indice %.',
          v_index;
      end if;
      if trim(coalesce(v_item ->> 'competition_code', '')) <> 'IT-SA'
        or coalesce(v_item ->> 'season', '') !~ '^[0-9]{4}$' then
        raise exception
          'Payload provider non valido [fixture.competition] all''indice %.',
          v_index;
      end if;
      if not public.provider_contract_uuid_text_v1(v_item ->> 'matchday_id') then
        raise exception
          'Payload provider non valido [fixture.matchday_id] all''indice %.',
          v_index;
      end if;
      if coalesce(jsonb_typeof(v_item -> 'kickoff_at'), 'missing') <> 'string'
        or coalesce(jsonb_typeof(v_item -> 'status'), 'missing') <> 'string'
        or length(trim(coalesce(v_item ->> 'status', ''))) = 0 then
        raise exception
          'Payload provider non valido [fixture.status_time] all''indice %.',
          v_index;
      end if;
      if not public.provider_contract_positive_id_v1(
        v_item ->> 'home_team_provider_id'
      ) or not public.provider_contract_positive_id_v1(
        v_item ->> 'away_team_provider_id'
      ) then
        raise exception
          'Payload provider non valido [fixture.team_ids] all''indice %.',
          v_index;
      end if;
      if coalesce(jsonb_typeof(v_item -> 'home_team_name'), 'missing') <> 'string'
        or length(trim(coalesce(v_item ->> 'home_team_name', ''))) = 0
        or coalesce(jsonb_typeof(v_item -> 'away_team_name'), 'missing') <> 'string'
        or length(trim(coalesce(v_item ->> 'away_team_name', ''))) = 0 then
        raise exception
          'Payload provider non valido [fixture.team_names] all''indice %.',
          v_index;
      end if;
      if coalesce(jsonb_typeof(v_item -> 'payload'), 'missing') <> 'object'
        or coalesce(jsonb_typeof(v_item -> 'updated_at'), 'missing') <> 'string' then
        raise exception
          'Payload provider non valido [fixture.metadata] all''indice %.',
          v_index;
      end if;

    elsif v_operation = 'upsert-player-scores' then
      if not public.provider_contract_uuid_text_v1(v_item ->> 'athlete_id')
        or not public.provider_contract_uuid_text_v1(v_item ->> 'matchday_id') then
        raise exception
          'Payload provider non valido [score.identifiers] all''indice %.',
          v_index;
      end if;
      if not public.provider_contract_positive_id_v1(
        v_item ->> 'provider_fixture_id'
      ) then
        raise exception
          'Payload provider non valido [score.provider_fixture_id] all''indice %.',
          v_index;
      end if;
      if coalesce(jsonb_typeof(v_item -> 'provider_rating'), 'missing') not in ('number', 'null')
        or coalesce(jsonb_typeof(v_item -> 'fantasy_score'), 'missing') not in ('number', 'null') then
        raise exception
          'Payload provider non valido [score.values] all''indice %.',
          v_index;
      end if;
      if coalesce(jsonb_typeof(v_item -> 'bonuses'), 'missing') <> 'object'
        or coalesce(jsonb_typeof(v_item -> 'maluses'), 'missing') <> 'object'
        or coalesce(jsonb_typeof(v_item -> 'raw_statistics'), 'missing') <> 'object'
        or coalesce(jsonb_typeof(v_item -> 'provider_payload'), 'missing') <> 'object' then
        raise exception
          'Payload provider non valido [score.statistics] all''indice %.',
          v_index;
      end if;
      if coalesce(jsonb_typeof(v_item -> 'is_final'), 'missing') <> 'boolean'
        or coalesce(jsonb_typeof(v_item -> 'updated_at'), 'missing') <> 'string' then
        raise exception
          'Payload provider non valido [score.state] all''indice %.',
          v_index;
      end if;
    end if;
  end loop;

  return jsonb_build_object(
    'valid', true,
    'contractVersion', public.provider_payload_contract_version_v1(),
    'operation', v_operation,
    'itemCount', v_count
  );
end;
$$;

revoke all on function public.validate_provider_sync_write_contract_v1(text,jsonb)
from public, anon, authenticated;
grant execute on function public.validate_provider_sync_write_contract_v1(text,jsonb)
to service_role;

-- Fencing e validazione vengono mantenuti nella stessa transazione della
-- scrittura già certificata dalla v0.62.11.
create or replace function public.apply_provider_sync_write_guarded_v2(
  p_run_id uuid,
  p_lease_token uuid,
  p_operation text,
  p_payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_contract jsonb;
  v_result jsonb;
begin
  perform public.assert_provider_sync_worker_lease_v1(
    p_run_id,
    p_lease_token
  );

  v_contract := public.validate_provider_sync_write_contract_v1(
    p_operation,
    p_payload
  );

  v_result := public.apply_provider_sync_write_guarded_v1(
    p_run_id,
    p_lease_token,
    p_operation,
    p_payload
  );

  return coalesce(v_result, '{}'::jsonb) || jsonb_build_object(
    'payloadContract', true,
    'contractVersion', v_contract ->> 'contractVersion',
    'validatedItemCount', coalesce((v_contract ->> 'itemCount')::integer, 0)
  );
end;
$$;

revoke all on function public.apply_provider_sync_write_guarded_v2(
  uuid,uuid,text,jsonb
)
from public, anon, authenticated;
grant execute on function public.apply_provider_sync_write_guarded_v2(
  uuid,uuid,text,jsonb
)
to service_role;

create or replace function public.record_provider_payload_contract_violation_v1(
  p_run_id uuid,
  p_lease_token uuid,
  p_contract_scope text,
  p_contract_version text,
  p_violation_code text,
  p_item_index integer,
  p_summary text,
  p_payload_fingerprint text,
  p_payload_size integer
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_run public.provider_sync_runs%rowtype;
  v_lease public.provider_sync_worker_leases%rowtype;
  v_existing public.provider_payload_contract_violations%rowtype;
  v_inserted public.provider_payload_contract_violations%rowtype;
  v_scope text := lower(trim(coalesce(p_contract_scope, '')));
  v_version text := lower(trim(coalesce(p_contract_version, '')));
  v_code text := lower(trim(coalesce(p_violation_code, '')));
  v_summary text := left(
    regexp_replace(
      coalesce(nullif(trim(p_summary), ''), 'Violazione del contratto provider.'),
      E'[\\r\\n]+',
      ' ',
      'g'
    ),
    500
  );
  v_fingerprint text := lower(trim(coalesce(p_payload_fingerprint, '')));
begin
  perform public.assert_provider_sync_worker_lease_v1(
    p_run_id,
    p_lease_token
  );

  if v_scope !~ '^[a-z0-9:/._-]{1,120}$' then
    raise exception 'Ambito della violazione provider non valido.';
  end if;
  if v_version <> public.provider_payload_contract_version_v1() then
    raise exception 'Versione del contratto provider non riconosciuta.';
  end if;
  if v_code !~ '^[a-z0-9._-]{1,80}$' then
    raise exception 'Codice della violazione provider non valido.';
  end if;
  if p_item_index is not null and p_item_index < 0 then
    raise exception 'Indice della violazione provider non valido.';
  end if;
  if v_fingerprint !~ '^[0-9a-f]{64}$' then
    raise exception 'Impronta del payload provider non valida.';
  end if;
  if p_payload_size is null or p_payload_size < 0 or p_payload_size > 50000000 then
    raise exception 'Dimensione del payload provider non valida.';
  end if;

  select run_row.*
  into v_run
  from public.provider_sync_runs run_row
  where run_row.id = p_run_id
  for update;

  if not found then
    raise exception 'Run provider non trovato durante la quarantena del payload.';
  end if;
  if v_run.status <> 'running' then
    raise exception
      'Quarantena provider rifiutata: run già nello stato %.',
      v_run.status;
  end if;

  select lease_row.*
  into v_lease
  from public.provider_sync_worker_leases lease_row
  where lease_row.run_id = v_run.id
    and lease_row.lease_token = p_lease_token
  for update;

  if not found or v_lease.status <> 'active' then
    raise exception 'Quarantena provider rifiutata: lease worker non attiva.';
  end if;

  insert into public.provider_payload_contract_violations (
    run_id,
    recovery_request_id,
    league_id,
    provider,
    sync_type,
    contract_scope,
    contract_version,
    violation_code,
    item_index,
    summary,
    payload_fingerprint,
    payload_size,
    run_revision,
    lease_epoch
  ) values (
    v_run.id,
    v_lease.recovery_request_id,
    v_lease.league_id,
    v_run.provider,
    v_run.sync_type,
    v_scope,
    v_version,
    v_code,
    p_item_index,
    v_summary,
    v_fingerprint,
    p_payload_size,
    v_run.revision,
    v_lease.lease_epoch
  )
  on conflict (run_id) do nothing
  returning * into v_inserted;

  if v_inserted.id is null then
    select violation_row.*
    into v_existing
    from public.provider_payload_contract_violations violation_row
    where violation_row.run_id = v_run.id;

    return jsonb_build_object(
      'violationId', v_existing.id,
      'runId', v_existing.run_id,
      'contractScope', v_existing.contract_scope,
      'contractVersion', v_existing.contract_version,
      'violationCode', v_existing.violation_code,
      'detectedAt', v_existing.detected_at,
      'reused', true,
      'payloadStored', false
    );
  end if;

  return jsonb_build_object(
    'violationId', v_inserted.id,
    'runId', v_inserted.run_id,
    'contractScope', v_inserted.contract_scope,
    'contractVersion', v_inserted.contract_version,
    'violationCode', v_inserted.violation_code,
    'detectedAt', v_inserted.detected_at,
    'reused', false,
    'payloadStored', false
  );
end;
$$;

revoke all on function public.record_provider_payload_contract_violation_v1(
  uuid,uuid,text,text,text,integer,text,text,integer
)
from public, anon, authenticated;
grant execute on function public.record_provider_payload_contract_violation_v1(
  uuid,uuid,text,text,text,integer,text,text,integer
)
to service_role;
create or replace function public.get_league_provider_payload_contract_center_v1(
  p_league_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_owner_id uuid;
  v_total_count integer := 0;
  v_last_24h integer := 0;
  v_latest_at timestamptz;
  v_latest jsonb;
begin
  select league_row.owner_id
  into v_owner_id
  from public.leagues league_row
  where league_row.id = p_league_id;

  if not found then
    raise exception 'Lega non trovata per il controllo dei contratti provider.';
  end if;
  if auth.uid() is null
    or not (
      v_owner_id = auth.uid()
      or public.is_league_admin(p_league_id)
    ) then
    raise exception 'Solo Presidente e Admin possono leggere i contratti provider.';
  end if;

  select
    count(*)::integer,
    count(*) filter (
      where violation_row.detected_at >= now() - interval '24 hours'
    )::integer,
    max(violation_row.detected_at)
  into v_total_count, v_last_24h, v_latest_at
  from public.provider_payload_contract_violations violation_row
  where violation_row.league_id = p_league_id
    or violation_row.league_id is null;

  select jsonb_build_object(
    'id', violation_row.id,
    'runId', violation_row.run_id,
    'requestId', violation_row.recovery_request_id,
    'syncType', violation_row.sync_type,
    'scope', violation_row.contract_scope,
    'code', violation_row.violation_code,
    'itemIndex', violation_row.item_index,
    'summary', violation_row.summary,
    'payloadSize', violation_row.payload_size,
    'detectedAt', violation_row.detected_at
  )
  into v_latest
  from public.provider_payload_contract_violations violation_row
  where violation_row.league_id = p_league_id
    or violation_row.league_id is null
  order by violation_row.detected_at desc, violation_row.id desc
  limit 1;

  return jsonb_build_object(
    'protected', true,
    'healthy', coalesce(v_last_24h, 0) = 0,
    'runtimeValidationActive', true,
    'databaseValidationActive', true,
    'payloadStorageDisabled', true,
    'contractVersion', public.provider_payload_contract_version_v1(),
    'violationsLast24h', coalesce(v_last_24h, 0),
    'totalViolationCount', coalesce(v_total_count, 0),
    'latestViolationAt', v_latest_at,
    'latest', v_latest
  );
end;
$$;

revoke all on function public.get_league_provider_payload_contract_center_v1(uuid)
from public, anon, authenticated;
grant execute on function public.get_league_provider_payload_contract_center_v1(uuid)
to authenticated;

create or replace function public.get_league_provider_sync_health_v11(
  p_league_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_health jsonb;
  v_contracts jsonb;
  v_healthy boolean;
  v_status text;
begin
  v_health := public.get_league_provider_sync_health_v10(p_league_id);
  v_contracts := public.get_league_provider_payload_contract_center_v1(p_league_id);
  v_healthy := coalesce((v_health ->> 'healthy')::boolean, false)
    and coalesce((v_contracts ->> 'healthy')::boolean, false);
  v_status := case
    when not v_healthy then 'attention'
    else coalesce(v_health ->> 'status', 'idle')
  end;

  return v_health || jsonb_build_object(
    'protected',
      coalesce((v_health ->> 'protected')::boolean, false)
      and coalesce((v_contracts ->> 'protected')::boolean, false),
    'healthy', v_healthy,
    'status', v_status,
    'payloadContracts', v_contracts
  );
end;
$$;

revoke all on function public.get_league_provider_sync_health_v11(uuid)
from public, anon, authenticated;
grant execute on function public.get_league_provider_sync_health_v11(uuid)
to authenticated;

-- Il registro pubblicato non contiene payload grezzi, token o credenziali.
do $realtime$
begin
  if exists (
    select 1
    from pg_catalog.pg_publication publication_row
    where publication_row.pubname = 'supabase_realtime'
  ) and not exists (
    select 1
    from pg_catalog.pg_publication_tables publication_table
    where publication_table.pubname = 'supabase_realtime'
      and publication_table.schemaname = 'public'
      and publication_table.tablename = 'provider_payload_contract_violations'
  ) then
    alter publication supabase_realtime
      add table public.provider_payload_contract_violations;
  end if;
end;
$realtime$;

create or replace function public.get_provider_payload_contract_quarantine_integrity_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_previous jsonb;
  v_previous_ready boolean := false;
  v_retry_policy jsonb;
begin
  v_previous := public.get_provider_worker_lease_fencing_integrity_v1();
  select not exists (
    select 1
    from jsonb_each(v_previous) check_row
    where check_row.value is distinct from 'true'::jsonb
  ) into v_previous_ready;

  v_retry_policy := public.provider_recovery_retry_policy_v1(
    'Payload provider non valido [schema.changed].',
    1,
    'sync-fixtures'
  );

  return jsonb_build_object(
    'predecessor_ready', v_previous_ready,
    'violation_table_ready',
      to_regclass('public.provider_payload_contract_violations') is not null,
    'violation_columns_ready',
      (
        select count(*) = 16
        from information_schema.columns column_row
        where column_row.table_schema = 'public'
          and column_row.table_name = 'provider_payload_contract_violations'
          and column_row.column_name in (
            'id', 'run_id', 'recovery_request_id', 'league_id', 'provider',
            'sync_type', 'contract_scope', 'contract_version',
            'violation_code', 'item_index', 'summary', 'payload_fingerprint',
            'payload_size', 'run_revision', 'lease_epoch', 'detected_at'
          )
      ),
    'violation_constraints_ready',
      exists (
        select 1
        from pg_catalog.pg_constraint constraint_row
        where constraint_row.conname =
          'provider_payload_contract_violations_run_fk'
          and constraint_row.conrelid =
            'public.provider_payload_contract_violations'::regclass
      )
      and exists (
        select 1
        from pg_catalog.pg_constraint constraint_row
        where constraint_row.conname =
          'provider_payload_contract_violations_run_uidx'
          and constraint_row.conrelid =
            'public.provider_payload_contract_violations'::regclass
      )
      and exists (
        select 1
        from pg_catalog.pg_constraint constraint_row
        where constraint_row.conname =
          'provider_payload_contract_violations_fingerprint_check'
          and constraint_row.conrelid =
            'public.provider_payload_contract_violations'::regclass
      ),
    'violation_indexes_ready',
      to_regclass(
        'public.provider_payload_contract_violations_detected_idx'
      ) is not null
      and to_regclass(
        'public.provider_payload_contract_violations_league_idx'
      ) is not null
      and to_regclass(
        'public.provider_payload_contract_violations_scope_idx'
      ) is not null,
    'violation_rls_ready',
      coalesce((
        select class_row.relrowsecurity
        from pg_catalog.pg_class class_row
        join pg_catalog.pg_namespace namespace_row
          on namespace_row.oid = class_row.relnamespace
        where namespace_row.nspname = 'public'
          and class_row.relname = 'provider_payload_contract_violations'
      ), false)
      and exists (
        select 1
        from pg_catalog.pg_policies policy_row
        where policy_row.schemaname = 'public'
          and policy_row.tablename = 'provider_payload_contract_violations'
          and policy_row.policyname =
            'provider_payload_contract_violations_read_directors'
          and policy_row.cmd = 'SELECT'
      ),
    'violation_privileges_ready',
      has_table_privilege(
        'authenticated',
        'public.provider_payload_contract_violations',
        'SELECT'
      )
      and not has_table_privilege(
        'authenticated',
        'public.provider_payload_contract_violations',
        'INSERT'
      )
      and not has_table_privilege(
        'authenticated',
        'public.provider_payload_contract_violations',
        'UPDATE'
      )
      and has_table_privilege(
        'service_role',
        'public.provider_payload_contract_violations',
        'INSERT'
      ),
    'violation_immutable_ready',
      to_regprocedure(
        'public.prevent_provider_payload_contract_violation_mutation_v1()'
      ) is not null
      and exists (
        select 1
        from pg_catalog.pg_trigger trigger_row
        where trigger_row.tgname =
          'provider_payload_contract_violations_immutable'
          and trigger_row.tgrelid =
            'public.provider_payload_contract_violations'::regclass
          and not trigger_row.tgisinternal
      ),
    'contract_version_ready',
      to_regprocedure(
        'public.provider_payload_contract_version_v1()'
      ) is not null
      and public.provider_payload_contract_version_v1() =
        'api-football-v3/leghevo-contract-v1',
    'contract_helpers_ready',
      to_regprocedure(
        'public.provider_contract_uuid_text_v1(text)'
      ) is not null
      and to_regprocedure(
        'public.provider_contract_positive_id_v1(text)'
      ) is not null
      and public.provider_contract_positive_id_v1('135')
      and not public.provider_contract_positive_id_v1('0'),
    'write_validator_ready',
      to_regprocedure(
        'public.validate_provider_sync_write_contract_v1(text,jsonb)'
      ) is not null
      and has_function_privilege(
        'service_role',
        'public.validate_provider_sync_write_contract_v1(text,jsonb)',
        'EXECUTE'
      )
      and not has_function_privilege(
        'authenticated',
        'public.validate_provider_sync_write_contract_v1(text,jsonb)',
        'EXECUTE'
      ),
    'guarded_write_v2_ready',
      to_regprocedure(
        'public.apply_provider_sync_write_guarded_v2(uuid,uuid,text,jsonb)'
      ) is not null
      and has_function_privilege(
        'service_role',
        'public.apply_provider_sync_write_guarded_v2(uuid,uuid,text,jsonb)',
        'EXECUTE'
      )
      and not has_function_privilege(
        'authenticated',
        'public.apply_provider_sync_write_guarded_v2(uuid,uuid,text,jsonb)',
        'EXECUTE'
      ),
    'violation_recorder_ready',
      to_regprocedure(
        'public.record_provider_payload_contract_violation_v1(uuid,uuid,text,text,text,integer,text,text,integer)'
      ) is not null
      and has_function_privilege(
        'service_role',
        'public.record_provider_payload_contract_violation_v1(uuid,uuid,text,text,text,integer,text,text,integer)',
        'EXECUTE'
      )
      and not has_function_privilege(
        'authenticated',
        'public.record_provider_payload_contract_violation_v1(uuid,uuid,text,text,text,integer,text,text,integer)',
        'EXECUTE'
      ),
    'contract_center_ready',
      to_regprocedure(
        'public.get_league_provider_payload_contract_center_v1(uuid)'
      ) is not null
      and has_function_privilege(
        'authenticated',
        'public.get_league_provider_payload_contract_center_v1(uuid)',
        'EXECUTE'
      ),
    'sync_health_v11_ready',
      to_regprocedure(
        'public.get_league_provider_sync_health_v11(uuid)'
      ) is not null
      and has_function_privilege(
        'authenticated',
        'public.get_league_provider_sync_health_v11(uuid)',
        'EXECUTE'
      ),
    'retry_policy_compatibility_ready',
      coalesce((v_retry_policy ->> 'retryable')::boolean, true) = false
      and coalesce(v_retry_policy ->> 'failureClass', '') = 'request',
    'lease_dependency_ready',
      to_regprocedure(
        'public.assert_provider_sync_worker_lease_v1(uuid,uuid)'
      ) is not null
      and to_regprocedure(
        'public.apply_provider_sync_write_guarded_v1(uuid,uuid,text,jsonb)'
      ) is not null,
    'realtime_ready',
      exists (
        select 1
        from pg_catalog.pg_publication_tables publication_table
        where publication_table.pubname = 'supabase_realtime'
          and publication_table.schemaname = 'public'
          and publication_table.tablename =
            'provider_payload_contract_violations'
      ),
    'no_raw_payload_ready',
      not exists (
        select 1
        from information_schema.columns column_row
        where column_row.table_schema = 'public'
          and column_row.table_name = 'provider_payload_contract_violations'
          and column_row.column_name in (
            'payload', 'raw_payload', 'response_payload', 'provider_payload',
            'lease_token', 'api_key', 'access_token'
          )
      ),
    'runtime_consistency_ready',
      not exists (
        select 1
        from public.provider_payload_contract_violations violation_row
        left join public.provider_sync_runs run_row
          on run_row.id = violation_row.run_id
        left join public.provider_recovery_requests request_row
          on request_row.id = violation_row.recovery_request_id
        where run_row.id is null
          or violation_row.provider is distinct from run_row.provider
          or violation_row.sync_type is distinct from run_row.sync_type
          or run_row.status = 'completed'
          or violation_row.contract_version <>
            public.provider_payload_contract_version_v1()
          or violation_row.payload_fingerprint <>
            lower(violation_row.payload_fingerprint)
          or violation_row.payload_size < 0
          or violation_row.run_revision <= 0
          or violation_row.lease_epoch <= 0
          or (
            violation_row.recovery_request_id is not null
            and (
              request_row.id is null
              or request_row.recovery_run_id is distinct from violation_row.run_id
              or request_row.league_id is distinct from violation_row.league_id
            )
          )
      )
  );
end;
$$;

revoke all on function public.get_provider_payload_contract_quarantine_integrity_v1()
from public, anon, authenticated;
grant execute on function public.get_provider_payload_contract_quarantine_integrity_v1()
to authenticated, service_role;

-- Arresta la transazione indicando i nomi esatti degli eventuali controlli falsi.
do $validation$
declare
  v_checks jsonb;
  v_failed text[];
begin
  v_checks := public.get_provider_payload_contract_quarantine_integrity_v1();

  select array_agg(check_row.key order by check_row.key)
  into v_failed
  from jsonb_each(v_checks) check_row
  where check_row.value is distinct from 'true'::jsonb;

  if coalesce(array_length(v_failed, 1), 0) > 0 then
    raise exception
      'Validazione v0.62.12 non superata. Controlli falsi: %',
      array_to_string(v_failed, '; ');
  end if;
end;
$validation$;

commit;

-- Diagnostica finale: devono comparire esattamente 20 valori true.
select
  (checks ->> 'predecessor_ready')::boolean as predecessor_ready,
  (checks ->> 'violation_table_ready')::boolean as violation_table_ready,
  (checks ->> 'violation_columns_ready')::boolean as violation_columns_ready,
  (checks ->> 'violation_constraints_ready')::boolean as violation_constraints_ready,
  (checks ->> 'violation_indexes_ready')::boolean as violation_indexes_ready,
  (checks ->> 'violation_rls_ready')::boolean as violation_rls_ready,
  (checks ->> 'violation_privileges_ready')::boolean as violation_privileges_ready,
  (checks ->> 'violation_immutable_ready')::boolean as violation_immutable_ready,
  (checks ->> 'contract_version_ready')::boolean as contract_version_ready,
  (checks ->> 'contract_helpers_ready')::boolean as contract_helpers_ready,
  (checks ->> 'write_validator_ready')::boolean as write_validator_ready,
  (checks ->> 'guarded_write_v2_ready')::boolean as guarded_write_v2_ready,
  (checks ->> 'violation_recorder_ready')::boolean as violation_recorder_ready,
  (checks ->> 'contract_center_ready')::boolean as contract_center_ready,
  (checks ->> 'sync_health_v11_ready')::boolean as sync_health_v11_ready,
  (checks ->> 'retry_policy_compatibility_ready')::boolean as retry_policy_compatibility_ready,
  (checks ->> 'lease_dependency_ready')::boolean as lease_dependency_ready,
  (checks ->> 'realtime_ready')::boolean as realtime_ready,
  (checks ->> 'no_raw_payload_ready')::boolean as no_raw_payload_ready,
  (checks ->> 'runtime_consistency_ready')::boolean as runtime_consistency_ready
from (
  select public.get_provider_payload_contract_quarantine_integrity_v1() as checks
) diagnostic;
