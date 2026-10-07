-- Payday history: period boundaries are computed from the payday in force on each date, never
-- from one global number, so changing the payday cannot rewrite past or running periods.
-- A row means "from effective_from on, the payday is payday_day". The first row is dated 1970-01-01.
create table if not exists public.payday_changes (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default public.current_profile_id() references public.user_profiles(id),
  payday_day smallint not null check (payday_day between 1 and 31),
  effective_from date not null,
  created_at timestamptz not null default timezone('utc', now()),
  unique (user_id, effective_from)
);

alter table public.payday_changes enable row level security;
create policy payday_changes_select_own on public.payday_changes
  for select using (user_id = (select public.current_profile_id()));
-- No insert/update/delete policies: writes go through set_payday / cancel_pending_payday.

-- Existing users: one entry from the earliest date. Periods before this release stay estimates in the app.
insert into public.payday_changes (user_id, payday_day, effective_from)
select id, payday_day, date '1970-01-01' from public.user_profiles where payday_day is not null
on conflict do nothing;

-- Start of the period that contains `d` for a payday (day past month end lands on its last day).
create or replace function public.payday_period_start(d date, p_day int)
returns date language sql immutable as $$
  select case
    when (date_trunc('month', d)::date + least(p_day, extract(day from (date_trunc('month', d) + interval '1 month - 1 day'))::int) - 1) <= d
      then (date_trunc('month', d)::date + least(p_day, extract(day from (date_trunc('month', d) + interval '1 month - 1 day'))::int) - 1)
    else (date_trunc('month', d - interval '1 month')::date
          + least(p_day, extract(day from (date_trunc('month', d - interval '1 month') + interval '1 month - 1 day'))::int) - 1)
  end;
$$;

-- Start of the period after the one starting at `s`.
create or replace function public.payday_period_end(s date, p_day int)
returns date language sql immutable as $$
  select date_trunc('month', s + interval '1 month')::date
    + least(p_day, extract(day from (date_trunc('month', s + interval '1 month') + interval '1 month - 1 day'))::int) - 1;
$$;

-- Saves a new payday and returns the date it takes effect (server date, not the device clock):
--  * first time, or within 7 days of signing up, or before any transaction: immediately (correction);
--  * otherwise: at the end of the running period, which finishes under the old payday.
-- A pending change that has not taken effect yet is replaced.
create or replace function public.set_payday(p_day int)
returns date
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_uid uuid := public.current_profile_id();
  v_tz text;
  v_created timestamptz;
  v_today date;
  v_current int;
  v_effective date;
begin
  if p_day is null or p_day < 1 or p_day > 31 then
    raise exception 'payday must be between 1 and 31' using errcode = 'check_violation';
  end if;
  select coalesce(timezone, 'Asia/Jakarta'), created_at into v_tz, v_created from user_profiles where id = v_uid;
  v_today := (now() at time zone v_tz)::date;

  delete from payday_changes where user_id = v_uid and effective_from > v_today;
  select payday_day into v_current from payday_changes
    where user_id = v_uid and effective_from <= v_today order by effective_from desc limit 1;

  if v_current is null
     or v_created > now() - interval '7 days'
     or not exists (select 1 from transactions where user_id = v_uid and deleted_at is null) then
    delete from payday_changes where user_id = v_uid;
    insert into payday_changes (user_id, payday_day, effective_from) values (v_uid, p_day, date '1970-01-01');
    v_effective := v_today;
  elsif p_day = v_current then
    v_effective := v_today;
  else
    v_effective := payday_period_end(payday_period_start(v_today, v_current), v_current);
    insert into payday_changes (user_id, payday_day, effective_from) values (v_uid, p_day, v_effective);
  end if;

  update user_profiles set payday_day = p_day where id = v_uid;
  return v_effective;
end;
$$;

-- Drops a pending change; the profile payday goes back to the one in force.
create or replace function public.cancel_pending_payday()
returns void
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_uid uuid := public.current_profile_id();
  v_tz text;
  v_today date;
begin
  select coalesce(timezone, 'Asia/Jakarta') into v_tz from user_profiles where id = v_uid;
  v_today := (now() at time zone v_tz)::date;
  delete from payday_changes where user_id = v_uid and effective_from > v_today;
  update user_profiles set payday_day = (select payday_day from payday_changes
    where user_id = v_uid order by effective_from desc limit 1) where id = v_uid;
end;
$$;

revoke execute on function public.set_payday(int) from public, anon;
revoke execute on function public.cancel_pending_payday() from public, anon;
grant execute on function public.set_payday(int) to authenticated;
grant execute on function public.cancel_pending_payday() to authenticated;
