-- A card bill paid from outside Saku (another bank account, or before the user started using
-- the app). It lowers the card's debt without touching any wallet, so it is neither income nor
-- a transfer: primary account = the card, no category, no counterparty.

alter table public.transactions drop constraint if exists transactions_transaction_type_check;
alter table public.transactions add constraint transactions_transaction_type_check
  check (transaction_type = any (array['income', 'expense', 'transfer', 'adjustment', 'card_payment']));

alter table public.transactions drop constraint if exists category_id_null_for_transfer;
alter table public.transactions add constraint category_id_null_for_transfer
  check (
    (transaction_type in ('transfer', 'card_payment') and category_id is null)
    or (transaction_type not in ('transfer', 'card_payment') and category_id is not null)
  );

alter table public.transactions drop constraint if exists transactions_transfer_shape;
alter table public.transactions add constraint transactions_transfer_shape
  check (
    (transaction_type = 'transfer' and counterparty_account_id is not null and category_id is null)
    or (transaction_type in ('income', 'expense', 'adjustment') and category_id is not null and counterparty_account_id is null)
    or (transaction_type = 'card_payment' and category_id is null and counterparty_account_id is null)
  );

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
            case when t.transaction_type in ('income', 'card_payment') then t.amount else -t.amount end, t.occurred_at);
  end if;
end;
$$;

create or replace function public.create_card_payment(
  p_card_id uuid,
  p_amount numeric,
  p_client_operation_id text,
  p_note text default null,
  p_occurred_at timestamptz default timezone('utc', now())
) returns uuid
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_user_id uuid;
  v_transaction_id uuid;
  v_existing uuid;
begin
  v_user_id := public.current_profile_id();
  if v_user_id is null then raise exception 'User profile not found'; end if;

  select entity_id into v_existing from public.sync_operations
  where user_id = v_user_id and client_operation_id = p_client_operation_id;
  if v_existing is not null then return v_existing; end if;

  if not exists (
    select 1 from public.accounts
    where id = p_card_id and user_id = v_user_id and deleted_at is null and account_type = 'Credit Card'
  ) then
    raise exception 'Credit card not found or not owned by user';
  end if;

  insert into public.sync_operations (user_id, client_operation_id, entity_type, operation_type, payload, status)
  values (v_user_id, p_client_operation_id, 'transaction', 'create_card_payment',
          jsonb_build_object('card_id', p_card_id, 'amount', p_amount, 'note', p_note, 'occurred_at', p_occurred_at),
          'received');

  insert into public.transactions (user_id, transaction_type, status, occurred_at, description, note, primary_account_id, amount, currency_code, client_reference_id)
  values (v_user_id, 'card_payment', 'posted', p_occurred_at, 'Bayar tagihan', p_note, p_card_id, p_amount, 'IDR', p_client_operation_id)
  returning id into v_transaction_id;

  perform public.rebuild_transaction_entries(v_transaction_id);

  update public.sync_operations
  set entity_id = v_transaction_id, status = 'applied', applied_at = timezone('utc', now())
  where user_id = v_user_id and client_operation_id = p_client_operation_id;

  return v_transaction_id;
end;
$$;

revoke execute on function public.create_card_payment(uuid, numeric, text, text, timestamptz) from public, anon;
grant execute on function public.create_card_payment(uuid, numeric, text, text, timestamptz) to authenticated;
revoke execute on function public.rebuild_transaction_entries(uuid) from public, anon, authenticated;
