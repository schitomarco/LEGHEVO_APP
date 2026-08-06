-- LEGHEVO · pannello del Presidente e regole configurabili
-- Eseguire nel SQL Editor di Supabase dopo 011.

create or replace function public.update_league_settings(
  p_league_id uuid,
  p_market_open boolean,
  p_market_min_price integer,
  p_release_refund_percent integer,
  p_goal_threshold numeric,
  p_goal_step numeric,
  p_home_bonus numeric
)
returns public.leagues
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_league public.leagues%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Devi effettuare l''accesso.';
  end if;

  if not public.is_league_admin(p_league_id) then
    raise exception 'Solo il Presidente può cambiare le regole della lega.';
  end if;

  if p_market_open is null then
    raise exception 'Lo stato del mercato è obbligatorio.';
  end if;

  if p_market_min_price is null
    or p_market_min_price < 1
    or p_market_min_price > 1000 then
    raise exception 'Il prezzo minimo deve essere tra 1 e 1000 crediti.';
  end if;

  if p_release_refund_percent is null
    or p_release_refund_percent < 0
    or p_release_refund_percent > 100 then
    raise exception 'Il rimborso deve essere una percentuale tra 0 e 100.';
  end if;

  if p_goal_threshold is null
    or p_goal_threshold < 50
    or p_goal_threshold > 100 then
    raise exception 'La soglia del primo gol deve essere tra 50 e 100.';
  end if;

  if p_goal_step is null
    or p_goal_step < 1
    or p_goal_step > 20 then
    raise exception 'La fascia gol deve essere tra 1 e 20 punti.';
  end if;

  if p_home_bonus is null
    or p_home_bonus < 0
    or p_home_bonus > 10 then
    raise exception 'Il bonus casa deve essere tra 0 e 10 punti.';
  end if;

  update public.leagues
  set
    scoring_rules = coalesce(scoring_rules, '{}'::jsonb)
      || jsonb_build_object(
        'market_open', p_market_open,
        'market_min_price', p_market_min_price,
        'release_refund_percent', p_release_refund_percent,
        'goal_threshold', p_goal_threshold,
        'goal_step', p_goal_step,
        'home_bonus', p_home_bonus
      ),
    updated_at = now()
  where id = p_league_id
  returning * into v_league;

  if not found then
    raise exception 'Lega non trovata.';
  end if;

  return v_league;
end;
$$;

revoke all on function public.update_league_settings(
  uuid,
  boolean,
  integer,
  integer,
  numeric,
  numeric,
  numeric
) from public;

grant execute on function public.update_league_settings(
  uuid,
  boolean,
  integer,
  integer,
  numeric,
  numeric,
  numeric
) to authenticated;

select
  to_regprocedure(
    'public.update_league_settings(uuid,boolean,integer,integer,numeric,numeric,numeric)'
  ) is not null as president_settings_ready,
  has_function_privilege(
    'authenticated',
    'public.update_league_settings(uuid,boolean,integer,integer,numeric,numeric,numeric)',
    'EXECUTE'
  ) as authenticated_access_ready;
