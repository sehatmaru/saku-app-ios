-- Day of the month the user gets paid (1-31, clamped to month length in the app).
-- Budget periods and "bulan ini" run from this day. Null = never set (app uses 1).
alter table public.user_profiles
  add column if not exists payday_day smallint
  check (payday_day between 1 and 31);

-- Per-user view of categories, system ones included: hidden from pickers and custom order.
-- Hiding keeps history: transactions keep pointing at the category.
create table if not exists public.category_preferences (
  user_id uuid not null default public.current_profile_id() references public.user_profiles(id),
  category_id uuid not null references public.categories(id),
  is_hidden boolean not null default false,
  sort_order integer,
  updated_at timestamptz not null default timezone('utc', now()),
  primary key (user_id, category_id)
);

create index if not exists category_preferences_category_id_idx on public.category_preferences(category_id);

alter table public.category_preferences enable row level security;

create policy category_preferences_select_own on public.category_preferences
  for select using (user_id = (select public.current_profile_id()));
create policy category_preferences_insert_own on public.category_preferences
  for insert with check (user_id = (select public.current_profile_id()));
create policy category_preferences_update_own on public.category_preferences
  for update using (user_id = (select public.current_profile_id()))
  with check (user_id = (select public.current_profile_id()));
create policy category_preferences_delete_own on public.category_preferences
  for delete using (user_id = (select public.current_profile_id()));
