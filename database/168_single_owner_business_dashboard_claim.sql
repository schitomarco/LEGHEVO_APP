-- LEGHEVO · assegnazione one-shot del proprietario Business Dashboard
-- Nel repository resta solo l'impronta SHA-256 normalizzata dell'identità.

begin;

alter table public.platform_business_owners
  add column if not exists singleton boolean not null default true
    check (singleton = true);

create unique index if not exists platform_business_owners_singleton_uidx
  on public.platform_business_owners (singleton);

create or replace function public.claim_my_leghevo_business_owner_v1()
returns boolean
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_user_id uuid := auth.uid();
  v_email_hash text := encode(
    extensions.digest(
      lower(btrim(coalesce(auth.jwt() ->> 'email', ''))),
      'sha256'
    ),
    'hex'
  );
  v_expected_hash constant text :=
    '01d19ea4712b7529254a50c111908baff131095b400bec00f12151334060a9f6';
begin
  if v_user_id is null or v_email_hash <> v_expected_hash then
    return false;
  end if;

  if not exists (
    select 1
    from public.profiles profile
    where profile.id = v_user_id
      and profile.deleted_at is null
  ) then
    return false;
  end if;

  insert into public.platform_business_owners (user_id)
  values (v_user_id)
  on conflict (user_id) do nothing;

  return public.is_leghevo_business_owner_v1();
exception
  when unique_violation then
    return public.is_leghevo_business_owner_v1();
end;
$function$;

revoke all on function public.claim_my_leghevo_business_owner_v1()
from public, anon;
grant execute on function public.claim_my_leghevo_business_owner_v1()
to authenticated;

do $postflight$
begin
  if to_regprocedure('public.claim_my_leghevo_business_owner_v1()') is null
    or not has_function_privilege(
      'authenticated',
      'public.claim_my_leghevo_business_owner_v1()',
      'execute'
    ) then
    raise exception 'Postflight assegnazione proprietario Business Dashboard non superato.';
  end if;
end;
$postflight$;

commit;
