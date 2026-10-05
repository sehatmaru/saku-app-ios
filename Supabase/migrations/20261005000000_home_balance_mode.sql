-- What "Total saldo" on Beranda adds up: 'cash' (default) or 'all' (cash + investment assets).
-- Lives on the profile so it follows the user across devices.
alter table public.user_profiles
  add column if not exists home_balance_mode text not null default 'cash'
  check (home_balance_mode in ('cash', 'all'));
