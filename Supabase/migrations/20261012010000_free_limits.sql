-- Free-account limits (PRD "Perampingan Kategori Bawaan & Batas Kategori"), enforced on the server so the
-- app cannot be talked around: at most 7 active expense categories, 5 active income categories and 7 budgets.
-- "Active" = built-in (visible to the user's category set) plus own, not hidden. Nothing existing is removed or
-- hidden: the triggers only refuse additions, and only while the count is at or over the limit.
-- Saku Plus (no limits) is not built yet; `is_plus()` is the single place to change when it is.
create or replace function public.is_plus() returns boolean language sql stable as $$ select false $$;

create or replace function public.active_category_count(p_kind text, p_except uuid default null)
returns integer
language sql stable security definer
set search_path to 'public'
as $$
  select count(*)::int
  from categories c
  left join category_preferences p on p.category_id = c.id and p.user_id = public.current_profile_id()
  where c.deleted_at is null
    and c.category_kind = p_kind
    and c.system_key is distinct from 'adjustment'
    and (c.id is distinct from p_except)
    and coalesce(p.is_hidden, false) = false
    and (c.user_id = public.current_profile_id()
         or (c.owner_type = 'system'
             and (c.set_min is null or c.set_min <= public.current_category_set())
             and (c.set_max is null or c.set_max >= public.current_category_set())));
$$;

create or replace function public.category_limit(p_kind text) returns integer
language sql immutable as $$ select case when p_kind = 'income' then 5 else 7 end $$;

-- A new own category.
create or replace function public.enforce_category_limit() returns trigger
language plpgsql security definer set search_path to 'public' as $$
begin
  if new.owner_type = 'user' and new.deleted_at is null and not public.is_plus()
     and public.active_category_count(new.category_kind) >= public.category_limit(new.category_kind) then
    raise exception 'category_limit_%', new.category_kind using errcode = 'check_violation';
  end if;
  return new;
end $$;
drop trigger if exists categories_enforce_limit on public.categories;
create trigger categories_enforce_limit before insert on public.categories
  for each row execute function public.enforce_category_limit();

-- Showing a hidden category again.
create or replace function public.enforce_unhide_limit() returns trigger
language plpgsql security definer set search_path to 'public' as $$
declare v_kind text;
begin
  if old.is_hidden and not new.is_hidden and not public.is_plus() then
    select category_kind into v_kind from categories where id = new.category_id;
    if public.active_category_count(v_kind, new.category_id) >= public.category_limit(v_kind) then
      raise exception 'category_limit_%', v_kind using errcode = 'check_violation';
    end if;
  end if;
  return new;
end $$;
drop trigger if exists category_preferences_enforce_unhide_limit on public.category_preferences;
create trigger category_preferences_enforce_unhide_limit before update on public.category_preferences
  for each row execute function public.enforce_unhide_limit();

-- A new budget.
create or replace function public.enforce_budget_limit() returns trigger
language plpgsql security definer set search_path to 'public' as $$
begin
  if new.deleted_at is null and new.is_active and not public.is_plus()
     and (select count(*) from budgets where user_id = new.user_id and deleted_at is null and is_active) >= 7 then
    raise exception 'budget_limit' using errcode = 'check_violation';
  end if;
  return new;
end $$;
drop trigger if exists budgets_enforce_limit on public.budgets;
create trigger budgets_enforce_limit before insert on public.budgets
  for each row execute function public.enforce_budget_limit();
