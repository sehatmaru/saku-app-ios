-- Statement cut-off day for credit cards (1-31; clamped to month length in the app).
alter table public.accounts
  add column if not exists statement_day smallint
  check (statement_day between 1 and 31);

-- Last price before an edit, so the app can flag subscription price increases.
alter table public.card_subscriptions
  add column if not exists previous_amount numeric;

-- 0% installments: a card purchase billed in equal parts over N statements.
create table if not exists public.card_installments (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default public.current_profile_id() references public.user_profiles(id),
  account_id uuid not null references public.accounts(id),
  transaction_id uuid not null unique references public.transactions(id),
  months smallint not null check (months between 2 and 36),
  created_at timestamptz not null default timezone('utc', now()),
  deleted_at timestamptz
);

create index if not exists card_installments_account_id_idx on public.card_installments(account_id);
create index if not exists card_installments_user_id_idx on public.card_installments(user_id);

alter table public.card_installments enable row level security;

create policy card_installments_select_own on public.card_installments
  for select using (user_id = (select public.current_profile_id()));
create policy card_installments_insert_own on public.card_installments
  for insert with check (user_id = (select public.current_profile_id()));
create policy card_installments_update_own on public.card_installments
  for update using (user_id = (select public.current_profile_id()))
  with check (user_id = (select public.current_profile_id()));
create policy card_installments_delete_own on public.card_installments
  for delete using (user_id = (select public.current_profile_id()));
