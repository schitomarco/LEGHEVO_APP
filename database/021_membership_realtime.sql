-- LEGHEVO · partecipanti e squadre aggiornati in tempo reale
-- Eseguire nel SQL Editor di Supabase dopo 020.

do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'league_members'
  ) then
    alter publication supabase_realtime
      add table public.league_members;
  end if;

  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'fantasy_teams'
  ) then
    alter publication supabase_realtime
      add table public.fantasy_teams;
  end if;

  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'leagues'
  ) then
    alter publication supabase_realtime
      add table public.leagues;
  end if;
end;
$$;

select
  exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'league_members'
  ) as league_members_realtime_ready,
  exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'fantasy_teams'
  ) as fantasy_teams_realtime_ready,
  exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'leagues'
  ) as leagues_realtime_ready;
