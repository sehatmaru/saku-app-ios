-- Two lists of built-in categories (PRD "Perampingan Kategori Bawaan"): accounts that existed before
-- this migration keep the list they have (set 1, nothing changes); accounts created after it get the
-- slimmer list (set 2). Built-in categories are shared rows, so the list a user sees is decided by
-- `set_min` / `set_max` on the category and `category_set` on the profile, enforced in RLS.
alter table public.user_profiles add column if not exists category_set smallint not null default 1;
-- every row that exists now keeps 1; rows created from here on start on the new list
alter table public.user_profiles alter column category_set set default 2;

alter table public.categories
  add column if not exists set_min smallint,
  add column if not exists set_max smallint;

-- Only in the old list: merged into the new categories for new accounts.
update public.categories set set_max = 1
where owner_type = 'system' and system_key in (
  'expense_restaurant_mall', 'expense_personal_spending', 'expense_entertainment',
  'expense_social_donation', 'expense_sport_fitness', 'expense_care_health');

-- Only in the new list.
insert into public.categories (owner_type, system_key, name, normalized_name, category_kind, icon, color, set_min)
select 'system', v.system_key, v.name, lower(v.name), 'expense', v.icon, v.color, 2
from (values
  ('expense_bills_subscriptions', 'Tagihan & Langganan', 'doc.text', '#5B8DEF'),
  ('expense_health_sport', 'Kesehatan & Olahraga', 'heart', '#6BCB77')
) as v(system_key, name, icon, color)
where not exists (select 1 from public.categories c where c.system_key = v.system_key);

create or replace function public.current_category_set()
returns smallint
language sql stable security definer
set search_path to 'public'
as $$
  select coalesce((select category_set from user_profiles where id = public.current_profile_id()), 1)::smallint;
$$;
revoke execute on function public.current_category_set() from public, anon;
grant execute on function public.current_category_set() to authenticated;

drop policy if exists categories_select_system_or_own on public.categories;
create policy categories_select_system_or_own on public.categories
  for select using (
    user_id = (select public.current_profile_id())
    or (owner_type = 'system'
        and (set_min is null or set_min <= (select public.current_category_set()))
        and (set_max is null or set_max >= (select public.current_category_set())))
  );
