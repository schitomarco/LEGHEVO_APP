-- LEGHEVO v0.62.43 management-state hotfix
-- Allinea la volatilita dichiarata al comportamento della diagnostica mercato,
-- che chiude atomicamente le offerte scadute durante il preflight.

begin;

do $preflight$
begin
  if to_regprocedure('public.get_league_market_integrity_v4(uuid)') is null
    or to_regprocedure('public.get_league_competition_readiness_v1(uuid)') is null
    or to_regprocedure('public.get_league_competition_readiness_v2(uuid)') is null
    or to_regprocedure('public.get_league_management_state_v31(uuid)') is null then
    raise exception 'Preflight stato gestionale non superato: catena RPC incompleta.';
  end if;
end;
$preflight$;

-- Questi endpoint possono raggiungere get_league_market_integrity_v1(), che
-- esegue la manutenzione delle offerte scadute. Dichiararli STABLE induce
-- PostgREST ad aprire una transazione read-only e produce SQLSTATE 25006.
alter function public.get_league_market_integrity_v4(uuid) volatile;
alter function public.get_league_competition_readiness_v1(uuid) volatile;
alter function public.get_league_competition_readiness_v2(uuid) volatile;

do $alter_management_chain$
declare
  v_function regprocedure;
begin
  for v_function in
    select procedure_row.oid::regprocedure
    from pg_catalog.pg_proc procedure_row
    join pg_catalog.pg_namespace namespace_row
      on namespace_row.oid = procedure_row.pronamespace
    where namespace_row.nspname = 'public'
      and procedure_row.proname ~ '^get_league_management_state_v([8-9]|[12][0-9]|3[01])$'
      and pg_catalog.pg_get_function_identity_arguments(procedure_row.oid) = 'p_league_id uuid'
  loop
    execute format('alter function %s volatile', v_function);
  end loop;
end;
$alter_management_chain$;

do $validate$
declare
  v_invalid text[];
begin
  select array_agg(procedure_row.proname order by procedure_row.proname)
  into v_invalid
  from pg_catalog.pg_proc procedure_row
  join pg_catalog.pg_namespace namespace_row
    on namespace_row.oid = procedure_row.pronamespace
  where namespace_row.nspname = 'public'
    and (
      procedure_row.proname in (
        'get_league_market_integrity_v4',
        'get_league_competition_readiness_v1',
        'get_league_competition_readiness_v2'
      )
      or procedure_row.proname ~ '^get_league_management_state_v([8-9]|[12][0-9]|3[01])$'
    )
    and pg_catalog.pg_get_function_identity_arguments(procedure_row.oid) = 'p_league_id uuid'
    and procedure_row.provolatile <> 'v';

  if cardinality(v_invalid) > 0 then
    raise exception 'Validazione stato gestionale non superata: %',
      array_to_string(v_invalid, ', ');
  end if;
end;
$validate$;

commit;
