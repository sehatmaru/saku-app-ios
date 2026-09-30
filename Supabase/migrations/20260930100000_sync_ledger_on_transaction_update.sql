-- The app edits and soft-deletes transactions straight on the table, so the ledger
-- (transaction_entries) went stale after a wallet/amount change and installments of a deleted
-- purchase stayed active. Keep both in step from the database, whoever writes.

create or replace function public.rebuild_transaction_entries(p_transaction_id uuid)
returns void
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  t public.transactions;
begin
  select * into t from public.transactions where id = p_transaction_id;
  if t.id is null or t.transaction_type = 'adjustment' then return; end if;

  delete from public.transaction_entries where transaction_id = t.id;

  if t.transaction_type = 'transfer' then
    insert into public.transaction_entries (user_id, transaction_id, account_id, signed_amount, effective_at)
    values (t.user_id, t.id, t.primary_account_id, -t.amount, t.occurred_at),
           (t.user_id, t.id, t.counterparty_account_id, t.amount, t.occurred_at);
  else
    insert into public.transaction_entries (user_id, transaction_id, account_id, signed_amount, effective_at)
    values (t.user_id, t.id, t.primary_account_id,
            case when t.transaction_type = 'income' then t.amount else -t.amount end, t.occurred_at);
  end if;
end;
$$;

create or replace function public.sync_transaction_side_effects()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  if new.deleted_at is not null then
    update public.card_installments set deleted_at = new.deleted_at
    where transaction_id = new.id and deleted_at is null;
  else
    perform public.rebuild_transaction_entries(new.id);
  end if;
  return new;
end;
$$;

drop trigger if exists transactions_sync_side_effects on public.transactions;
create trigger transactions_sync_side_effects
after update of primary_account_id, counterparty_account_id, amount, transaction_type, occurred_at, deleted_at
on public.transactions
for each row execute function public.sync_transaction_side_effects();

-- Repair what already drifted: live transactions whose ledger disagrees, and installments
-- whose purchase was deleted.
select public.rebuild_transaction_entries(t.id)
from public.transactions t
where t.deleted_at is null
  and t.transaction_type <> 'adjustment'
  and (select coalesce(sum(e.signed_amount) filter (where e.account_id = t.primary_account_id), 0) from public.transaction_entries e where e.transaction_id = t.id)
      is distinct from case when t.transaction_type = 'income' then t.amount else -t.amount end;

update public.card_installments ci set deleted_at = t.deleted_at
from public.transactions t
where t.id = ci.transaction_id and t.deleted_at is not null and ci.deleted_at is null;

revoke execute on function public.rebuild_transaction_entries(uuid) from public, anon, authenticated;
