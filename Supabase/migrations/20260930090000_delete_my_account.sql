-- Development/testing tool: the signed-in user (guests included) deletes their own account
-- and everything under it. Remove this function before public release, or keep the app-side
-- switch (DevTools.isAccountResetEnabled) off.
create or replace function public.delete_my_account()
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  uid uuid := auth.uid();
  pid uuid;
begin
  if uid is null then
    raise exception 'not authenticated';
  end if;
  select id into pid from public.user_profiles where auth_user_id = uid;
  if pid is not null then
    -- These reference accounts/transactions/profiles without cascading, so they go first.
    delete from public.card_installments where user_id = pid;
    delete from public.category_preferences where user_id = pid;
    delete from public.card_subscriptions where account_id in (select id from public.accounts where user_id = pid);
  end if;
  -- Cascades to the profile and, from there, wallets, transactions, budgets and own categories.
  delete from auth.users where id = uid;
end;
$$;

revoke all on function public.delete_my_account() from public, anon;
grant execute on function public.delete_my_account() to authenticated;
