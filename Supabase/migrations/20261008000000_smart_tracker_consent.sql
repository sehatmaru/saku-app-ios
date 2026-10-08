-- When the user agreed to Smart Tracker ("Catat cepat") reading their sentences, notifications and shared text.
-- Per account, so it follows the user across devices. Null = not agreed yet.
alter table public.user_profiles
  add column if not exists smart_tracker_consent_at timestamptz;
