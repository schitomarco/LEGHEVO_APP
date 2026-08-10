-- LEGHEVO · identità provider preservata nei run e nei recuperi
begin;

do $preflight$
begin
  if to_regprocedure('public.normalize_provider_sync_request_v2(jsonb)') is null
    or to_regprocedure('public.provider_sync_request_bucket_v1(text,timestamptz)') is null
    or to_regclass('public.provider_sync_runs') is null
    or to_regclass('public.provider_recovery_requests') is null then
    raise exception 'Preflight 163 non superato: fondazione recovery provider mancante.';
  end if;
end;
$preflight$;

create or replace function public.prepare_provider_sync_run_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_normalized jsonb;
begin
  if tg_op = 'INSERT' then
    new.provider := lower(trim(coalesce(new.provider, 'api-football')));
    if new.provider not in ('api-football', 'football-data') then
      raise exception 'Provider non valido.';
    end if;
    v_normalized := case
      when new.provider = 'football-data' then
        public.normalize_provider_sync_request_v2(
          new.requested_for || jsonb_build_object('provider', new.provider)
        )
      else public.normalize_provider_sync_request_v1(new.requested_for)
    end;
    new.requested_for := v_normalized;
    new.sync_type := v_normalized ->> 'action';
    new.started_at := coalesce(new.started_at, now());
    new.request_bucket := public.provider_sync_request_bucket_v1(new.sync_type,new.started_at);
    new.request_fingerprint := pg_catalog.md5(
      new.provider || E'\n' || new.sync_type || E'\n' || new.requested_for::text
    );
    new.request_key := pg_catalog.md5(
      new.request_fingerprint || E'\n' || new.request_bucket
    );
    new.attempt_no := greatest(coalesce(new.attempt_no, 1), 1);
    new.revision := 1;
    new.last_updated_at := new.started_at;
    new.status := coalesce(new.status, 'running');
    new.records_processed := greatest(coalesce(new.records_processed, 0), 0);
    if new.status <> 'running' then
      raise exception 'Un nuovo run provider deve iniziare nello stato running.';
    end if;
    new.error_message := null;
    new.finished_at := null;
    new.result_fingerprint := null;
    return new;
  end if;

  if row(new.provider,new.sync_type,new.requested_for,new.request_bucket,
    new.request_key,new.request_fingerprint,new.attempt_no,new.started_at)
    is distinct from
    row(old.provider,old.sync_type,old.requested_for,old.request_bucket,
    old.request_key,old.request_fingerprint,old.attempt_no,old.started_at) then
    raise exception 'Identità del run provider non modificabile.';
  end if;
  if old.status in ('completed', 'failed') then
    if row(new.status,new.records_processed,new.error_message,new.finished_at)
      is not distinct from
      row(old.status,old.records_processed,old.error_message,old.finished_at) then
      return old;
    end if;
    raise exception 'Run provider già concluso e immutabile.';
  end if;
  if new.status not in ('running', 'completed', 'failed') then
    raise exception 'Stato del run provider non valido.';
  end if;
  new.records_processed := greatest(coalesce(new.records_processed, 0), 0);
  new.revision := old.revision + 1;
  new.last_updated_at := now();
  if new.status = 'running' then
    new.finished_at := null;
    new.error_message := null;
    new.result_fingerprint := null;
  else
    new.finished_at := coalesce(new.finished_at, now());
    if new.status = 'completed' then
      new.error_message := null;
    else
      new.error_message := left(
        coalesce(nullif(trim(new.error_message), ''), 'Errore provider non specificato.'),1200
      );
    end if;
    new.result_fingerprint := pg_catalog.md5(
      new.status || E'\n' || new.records_processed::text || E'\n'
      || coalesce(new.error_message, '') || E'\n' || new.finished_at::text
      || E'\n' || new.revision::text
    );
  end if;
  return new;
end;
$$;

revoke all on function public.prepare_provider_sync_run_v1()
from public, anon, authenticated;

create or replace function public.start_provider_recovery_sync_run_v1(p_request_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_request public.provider_recovery_requests%rowtype;
  v_normalized jsonb;
  v_provider text;
  v_sync_type text;
  v_started_at timestamptz := now();
  v_bucket text;
  v_request_fingerprint text;
  v_request_key text;
  v_existing public.provider_sync_runs%rowtype;
  v_inserted public.provider_sync_runs%rowtype;
  v_attempt integer := 1;
begin
  select request_row.* into v_request
  from public.provider_recovery_requests request_row
  where request_row.id = p_request_id for update;
  if not found or v_request.status <> 'pending' then
    raise exception 'Richiesta di recupero provider non disponibile.';
  end if;
  v_provider := lower(trim(v_request.provider));
  if v_provider not in ('api-football','football-data') then
    raise exception 'Provider recupero non valido.';
  end if;
  v_normalized := case
    when v_provider = 'football-data' then
      public.normalize_provider_sync_request_v2(
        v_request.requested_for || jsonb_build_object('provider',v_provider)
      )
    else public.normalize_provider_sync_request_v1(v_request.requested_for)
  end;
  v_sync_type := v_normalized ->> 'action';
  v_bucket := public.provider_sync_request_bucket_v1(v_sync_type,v_started_at);
  v_request_fingerprint := pg_catalog.md5(
    v_provider || E'\n' || v_sync_type || E'\n' || v_normalized::text
  );
  v_request_key := pg_catalog.md5(v_request_fingerprint || E'\n' || v_bucket);
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext(v_request_key));

  select run_row.* into v_existing
  from public.provider_sync_runs run_row
  where run_row.provider = v_provider and run_row.request_key = v_request_key
    and run_row.status = 'running'
  order by run_row.attempt_no desc,run_row.started_at desc limit 1 for update;
  if found then
    return jsonb_build_object(
      'runId',v_existing.id,'provider',v_existing.provider,
      'status',v_existing.status,'revision',v_existing.revision,
      'attempt',v_existing.attempt_no,'recordsProcessed',v_existing.records_processed,
      'requestKey',v_existing.request_key,'reused',true
    );
  end if;
  select coalesce(max(run_row.attempt_no),0)+1 into v_attempt
  from public.provider_sync_runs run_row
  where run_row.provider=v_provider and run_row.request_key=v_request_key;
  insert into public.provider_sync_runs (
    provider,sync_type,requested_for,status,records_processed,started_at,
    request_bucket,request_key,request_fingerprint,attempt_no
  ) values (
    v_provider,v_sync_type,v_normalized,'running',0,v_started_at,v_bucket,
    v_request_key,v_request_fingerprint,greatest(v_attempt,1)
  ) returning * into v_inserted;
  return jsonb_build_object(
    'runId',v_inserted.id,'provider',v_inserted.provider,
    'status',v_inserted.status,'revision',v_inserted.revision,
    'attempt',v_inserted.attempt_no,'recordsProcessed',v_inserted.records_processed,
    'requestKey',v_inserted.request_key,'reused',false
  );
end;
$$;

revoke all on function public.start_provider_recovery_sync_run_v1(uuid)
from public, anon, authenticated;
grant execute on function public.start_provider_recovery_sync_run_v1(uuid)
to service_role;

commit;
