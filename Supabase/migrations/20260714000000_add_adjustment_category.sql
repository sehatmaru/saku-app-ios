-- Add "Penyesuaian Saldo" (Balance Adjustment) system category
-- Used by rebalanceAccount() when adjusting wallet nominal

-- Allow 'adjustment' as a valid category_kind
ALTER TABLE categories DROP CONSTRAINT IF EXISTS categories_category_kind_check;
ALTER TABLE categories ADD CONSTRAINT categories_category_kind_check
  CHECK (category_kind IN ('income', 'expense', 'adjustment'));

INSERT INTO categories (name, normalized_name, system_key, category_kind, icon, color, owner_type)
SELECT 'Penyesuaian Saldo', 'penyesuaian saldo', 'adjustment', 'adjustment', 'arrow.left.arrow.right', '#8E8E93', 'system'
WHERE NOT EXISTS (SELECT 1 FROM categories WHERE system_key = 'adjustment');
