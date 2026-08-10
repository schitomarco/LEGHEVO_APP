-- LEGHEVO · run protetti provider-aware per football-data.org
begin;

do $preflight$
begin
  if to_regclass('public.provider_sync_runs') is null
    or to_regprocedure('public.normalize_provider_sync_request_v1(jsonb)') is null
    or to_regprocedure('public.provider_sync_request_bucket_v1(text,timestamptz)') is null
    or to_regprocedure('public.acquire_provider_sync_worker_lease_v1(uuid,uuid,uuid)') is null then
    raise exception 'Preflight 161 non superato: protezioni provider mancanti.';
  end if;
end;
$preflight$;

create or replace function public.normalize_provider_sync_request_v2(p_request jsonb)
returns jsonb
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_base jsonb;
  v_provider text := lower(trim(coalesce(p_request ->> 'provider', 'api-football')));
begin
  v_base := public.normalize_provider_sync_request_v1(p_request);
  if v_provider not in ('api-football', 'football-data') then
    raise exception 'Provider calcio non riconosciuto.';
  end if;
  if v_provider = 'football-data' and v_base ->> 'action' <> 'sync-fixtures' then
    raise exception 'football-data.org è autorizzato soltanto per il calendario.';
  end if;
  return v_base || jsonb_build_object('provider', v_provider);
end;
$$;

revoke all on function public.normalize_provider_sync_request_v2(jsonb)
from public, anon, authenticated;

create or replace function public.start_provider_sync_run_guarded_v3(
  p_request jsonb,
  p_lease_token uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_request jsonb := public.normalize_provider_sync_request_v2(p_request);
  v_provider text := v_request ->> 'provider';
  v_sync_type text := v_request ->> 'action';
  v_started_at timestamptz := now();
  v_bucket text;
  v_request_fingerprint text;
  v_request_key text;
  v_existing public.provider_sync_runs%rowtype;
  v_inserted public.provider_sync_runs%rowtype;
  v_attempt integer := 1;
  v_run jsonb;
  v_lease jsonb;
  v_execute boolean;
begin
  perform public.expire_stale_provider_sync_worker_leases_v1(null);
  v_bucket := public.provider_sync_request_bucket_v1(v_sync_type, v_started_at);
  v_request_fingerprint := pg_catalog.md5(
    v_provider || E'\n' || v_sync_type || E'\n' || v_request::text
  );
  v_request_key := pg_catalog.md5(v_request_fingerprint || E'\n' || v_bucket);
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext(v_request_key));

  select r.* into v_existing
  from public.provider_sync_runs r
  where r.provider = v_provider
    and r.request_key = v_request_key
    and r.status in ('running', 'completed')
  order by r.attempt_no desc, r.started_at desc limit 1;

  if found then
    v_run := jsonb_build_object(
      'runId', v_existing.id, 'provider', v_existing.provider,
      'status', v_existing.status, 'revision', v_existing.revision,
      'attempt', v_existing.attempt_no,
      'recordsProcessed', v_existing.records_processed,
      'requestKey', v_existing.request_key, 'reused', true
    );
  else
    select coalesce(max(r.attempt_no), 0) + 1 into v_attempt
    from public.provider_sync_runs r
    where r.provider = v_provider and r.request_key = v_request_key;
    insert into public.provider_sync_runs (
      provider, sync_type, requested_for, status, records_processed,
      started_at, request_bucket, request_key, request_fingerprint, attempt_no
    ) values (
      v_provider, v_sync_type, v_request, 'running', 0, v_started_at,
      v_bucket, v_request_key, v_request_fingerprint, greatest(v_attempt, 1)
    ) returning * into v_inserted;
    v_run := jsonb_build_object(
      'runId', v_inserted.id, 'provider', v_inserted.provider,
      'status', v_inserted.status, 'revision', v_inserted.revision,
      'attempt', v_inserted.attempt_no,
      'recordsProcessed', v_inserted.records_processed,
      'requestKey', v_inserted.request_key, 'reused', false
    );
  end if;

  if v_run ->> 'status' <> 'running' then
    return v_run || jsonb_build_object('execute', false, 'workerFencing', true);
  end if;
  v_lease := public.acquire_provider_sync_worker_lease_v1(
    (v_run ->> 'runId')::uuid, p_lease_token, null
  );
  v_execute := coalesce((v_lease ->> 'granted')::boolean, false)
    and not coalesce((v_run ->> 'reused')::boolean, false);
  return v_run || jsonb_build_object(
    'execute', v_execute, 'workerFencing', true,
    'leaseId', v_lease ->> 'leaseId',
    'leaseToken', case when coalesce((v_lease ->> 'granted')::boolean, false)
      then v_lease ->> 'leaseToken' else null end,
    'leaseEpoch', nullif(v_lease ->> 'leaseEpoch', '')::bigint,
    'leaseRevision', nullif(v_lease ->> 'leaseRevision', '')::bigint,
    'leaseExpiresAt', v_lease ->> 'leaseExpiresAt',
    'lastHeartbeatAt', v_lease ->> 'lastHeartbeatAt',
    'leaseStatus', v_lease ->> 'status'
  );
end;
$$;

revoke all on function public.start_provider_sync_run_guarded_v3(jsonb,uuid)
from public, anon, authenticated;
grant execute on function public.start_provider_sync_run_guarded_v3(jsonb,uuid)
to service_role;

create or replace function public.get_football_data_sync_integrity_v1()
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'normalizer_ready', to_regprocedure('public.normalize_provider_sync_request_v2(jsonb)') is not null,
    'start_run_ready', to_regprocedure('public.start_provider_sync_run_guarded_v3(jsonb,uuid)') is not null,
    'policy_ready', exists (
      select 1 from public.provider_quota_policies p
      where p.provider = 'football-data' and p.enabled
    ),
    'calendar_only_enforced', true
  );
$$;
revoke all on function public.get_football_data_sync_integrity_v1()
from public, anon, authenticated;
grant execute on function public.get_football_data_sync_integrity_v1()
to service_role;

commit;
