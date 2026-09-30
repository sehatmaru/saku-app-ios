-- A user's own name for a category, built-in ones included. Null = the shared name.
alter table public.category_preferences add column if not exists custom_name text;
