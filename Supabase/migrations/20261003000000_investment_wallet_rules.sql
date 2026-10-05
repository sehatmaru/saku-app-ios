-- Investment wallets hold value, not spending money: no income, expense or card payment on them,
-- and no transfer between two investment wallets. Value updates (adjustments) are allowed.
create or replace function public.enforce_investment_wallet_rules()
returns trigger
language plpgsql
set search_path to 'public'
as $$
declare
  v_primary text;
  v_counter text;
begin
  select account_type into v_primary from public.accounts where id = new.primary_account_id;
  if new.transaction_type in ('income', 'expense', 'card_payment') and v_primary = 'Investment' then
    raise exception 'Investment wallets cannot be used for %', new.transaction_type using errcode = 'check_violation';
  end if;
  if new.transaction_type = 'transfer' and new.counterparty_account_id is not null then
    select account_type into v_counter from public.accounts where id = new.counterparty_account_id;
    if v_primary = 'Investment' and v_counter = 'Investment' then
      raise exception 'Transfers between investment wallets are not supported' using errcode = 'check_violation';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists transactions_investment_rules on public.transactions;
create trigger transactions_investment_rules
  before insert or update of primary_account_id, counterparty_account_id, transaction_type on public.transactions
  for each row execute function public.enforce_investment_wallet_rules();
