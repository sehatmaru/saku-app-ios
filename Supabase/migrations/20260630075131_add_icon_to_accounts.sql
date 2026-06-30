-- Add icon column to accounts (needed by Swift Account model)
ALTER TABLE accounts ADD COLUMN IF NOT EXISTS icon TEXT;
