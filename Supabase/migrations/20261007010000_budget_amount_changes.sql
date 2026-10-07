-- Amount history per budget. `budgets.amount` stays the current base amount; this table says what
-- applied in each period, so changing a budget never rewrites past periods and a temporary change
-- (e.g. a holiday) ends by itself at a fixed date.
--   base      : from effective_from on, the budget is `amount` (until a later base row).
--   temporary : between effective_from and effective_to (exclusive), the budget is `amount`;
--               the newest non-canceled one wins. At most one is active per budget.
-- is_estimate rows come from budgets that existed before this table: periods that started before
-- the row was written use today's amount and are shown as "Perkiraan".
create table if not exists public.budget_amount_changes (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default public.current_profile_id() references public.user_profiles(id),
  budget_id uuid not null references public.budgets(id),
  kind text not null check (kind in ('base', 'temporary')),
  amount numeric not null check (amount >= 0),
  effective_from date not null,
  effective_to date,
  is_estimate boolean not null default false,
  canceled_at timestamptz,
  created_at timestamptz not null default timezone('utc', now()),
  check ((kind = 'temporary') = (effective_to is not null))
);
create unique index if not exists budget_amount_changes_base_uq
  on public.budget_amount_changes (budget_id, effective_from) where kind = 'base';
create index if not exists budget_amount_changes_user_idx on public.budget_amount_changes (user_id);
create index if not exists budget_amount_changes_budget_idx on public.budget_amount_changes (budget_id);

alter table public.budget_amount_changes enable row level security;
create policy budget_amount_changes_select_own on public.budget_amount_changes
  for select using (user_id = (select public.current_profile_id()));
-- Writes go through set_budget_amount / cancel_budget_temporary.

insert into public.budget_amount_changes (user_id, budget_id, kind, amount, effective_from, is_estimate)
select user_id, id, 'base', amount, date '1970-01-01', true from public.budgets
on conflict do nothing;

-- Every new budget starts its own history.
create or replace function public.budget_initial_amount()
returns trigger language plpgsql security definer set search_path to 'public' as $$
begin
  insert into budget_amount_changes (user_id, budget_id, kind, amount, effective_from)
  values (new.user_id, new.id, 'base', new.amount, date '1970-01-01')
  on conflict do nothing;
  return new;
end;
$$;
drop trigger if exists budgets_initial_amount on public.budgets;
create trigger budgets_initial_amount after insert on public.budgets
  for each row execute function public.budget_initial_amount();

-- p_kind 'base': the budget becomes p_amount from p_from (the running period's start); past
-- periods keep their old amount. p_kind 'temporary': p_amount applies from p_from up to p_to
-- (exclusive), replacing any active temporary change; the base amount is untouched.
create or replace function public.set_budget_amount(
  p_budget_id uuid, p_amount numeric, p_kind text, p_from date, p_to date default null)
returns void language plpgsql security definer set search_path to 'public' as $$
declare v_uid uuid := public.current_profile_id();
begin
  if not exists (select 1 from budgets where id = p_budget_id and user_id = v_uid and deleted_at is null) then
    raise exception 'budget not found' using errcode = 'no_data_found';
  end if;
  if p_amount is null or p_amount < 0 then
    raise exception 'amount must be >= 0' using errcode = 'check_violation';
  end if;
  if p_kind = 'base' then
    insert into budget_amount_changes (user_id, budget_id, kind, amount, effective_from)
    values (v_uid, p_budget_id, 'base', p_amount, p_from)
    on conflict (budget_id, effective_from) where kind = 'base' do update set amount = excluded.amount;
    update budgets set amount = p_amount, updated_at = now() where id = p_budget_id;
  elsif p_kind = 'temporary' then
    if p_to is null or p_to <= p_from then
      raise exception 'temporary change needs an end date after its start' using errcode = 'check_violation';
    end if;
    -- the old one stops where the new one starts, so periods it already covered keep its amount
    update budget_amount_changes set effective_to = p_from
      where budget_id = p_budget_id and kind = 'temporary' and canceled_at is null and effective_from < p_from;
    update budget_amount_changes set canceled_at = now()
      where budget_id = p_budget_id and kind = 'temporary' and canceled_at is null and effective_from >= p_from;
    insert into budget_amount_changes (user_id, budget_id, kind, amount, effective_from, effective_to)
    values (v_uid, p_budget_id, 'temporary', p_amount, p_from, p_to);
  else
    raise exception 'unknown kind %', p_kind using errcode = 'check_violation';
  end if;
end;
$$;

-- Back to the base amount from the running period on; past periods keep what they had.
-- A window that began earlier is cut at the period start; one that began now is dropped.
create or replace function public.cancel_budget_temporary(p_budget_id uuid, p_period_start date)
returns void language plpgsql security definer set search_path to 'public' as $$
declare v_uid uuid := public.current_profile_id();
begin
  update budget_amount_changes set effective_to = p_period_start
    where budget_id = p_budget_id and user_id = v_uid and kind = 'temporary' and canceled_at is null
      and effective_from < p_period_start and effective_to > p_period_start;
  update budget_amount_changes set canceled_at = now()
    where budget_id = p_budget_id and user_id = v_uid and kind = 'temporary' and canceled_at is null
      and effective_from >= p_period_start;
end;
$$;

revoke execute on function public.set_budget_amount(uuid, numeric, text, date, date) from public, anon;
revoke execute on function public.cancel_budget_temporary(uuid, date) from public, anon;
revoke execute on function public.budget_initial_amount() from public, anon, authenticated;
grant execute on function public.set_budget_amount(uuid, numeric, text, date, date) to authenticated;
grant execute on function public.cancel_budget_temporary(uuid, date) to authenticated;
