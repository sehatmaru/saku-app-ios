-- A card added with a starting bill: until this cut-off passes, that amount was not billed yet.
alter table public.accounts add column if not exists opening_unbilled_until date;
