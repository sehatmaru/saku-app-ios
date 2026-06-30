-- Create subcategories table (referenced by Transaction.subcategoryId)
CREATE TABLE IF NOT EXISTS subcategories (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  category_id UUID NOT NULL REFERENCES categories(id) ON DELETE CASCADE,
  user_id UUID REFERENCES user_profiles(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  icon TEXT,
  color TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now()),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now()),
  deleted_at TIMESTAMPTZ
);

-- Enable RLS
ALTER TABLE subcategories ENABLE ROW LEVEL SECURITY;

-- RLS: users can see system subcategories or their own
CREATE POLICY subcategories_select_own ON subcategories
  FOR SELECT
  TO authenticated
  USING (user_id IS NULL OR user_id = current_profile_id());

-- RLS: users can insert their own subcategories
CREATE POLICY subcategories_insert_own ON subcategories
  FOR INSERT
  TO authenticated
  WITH CHECK (user_id = current_profile_id());

-- RLS: users can update their own subcategories
CREATE POLICY subcategories_update_own ON subcategories
  FOR UPDATE
  TO authenticated
  USING (user_id = current_profile_id())
  WITH CHECK (user_id = current_profile_id());

-- RLS: users can delete their own subcategories
CREATE POLICY subcategories_delete_own ON subcategories
  FOR DELETE
  TO authenticated
  USING (user_id = current_profile_id());

-- Trigger for updated_at
CREATE TRIGGER subcategories_set_updated_at
  BEFORE UPDATE ON subcategories
  FOR EACH ROW
  EXECUTE FUNCTION set_updated_at();

-- Index for fast lookups
CREATE INDEX IF NOT EXISTS idx_subcategories_category_id ON subcategories(category_id);
CREATE INDEX IF NOT EXISTS idx_subcategories_user_id ON subcategories(user_id);
