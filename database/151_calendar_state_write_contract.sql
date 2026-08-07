-- LEGHEVO v0.62.43 calendar-state hotfix
-- Allinea la volatilita dichiarata al preflight calendario, che aggiorna
-- atomicamente lo stato diagnostico prima di restituire la proiezione.

begin;

do $preflight$
begin
  if to_regprocedure('public.get_league_calendar_state_v2(uuid)') is null
    or to_regprocedure('public.get_league_calendar_state_v3(uuid)') is null then
    raise exception 'Preflight stato calendario non superato: catena RPC incompleta.';
  end if;
end;
$preflight$;

-- Le due versioni raggiungono una routine VOLATILE di preflight. Se restano
-- STABLE, PostgREST apre una transazione read-only e PostgreSQL restituisce
-- SQLSTATE 25006 al client mobile.
alter function public.get_league_calendar_state_v2(uuid) volatile;
alter function public.get_league_calendar_state_v3(uuid) volatile;

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
    and procedure_row.proname in (
      'get_league_calendar_state_v2',
      'get_league_calendar_state_v3'
    )
    and pg_catalog.pg_get_function_identity_arguments(procedure_row.oid) = 'p_league_id uuid'
    and procedure_row.provolatile <> 'v';

  if cardinality(v_invalid) > 0 then
    raise exception 'Validazione stato calendario non superata: %',
      array_to_string(v_invalid, ', ');
  end if;
end;
$validate$;

commit;
