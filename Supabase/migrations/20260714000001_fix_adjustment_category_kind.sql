-- Fix "Penyesuaian Saldo" category: category_kind back to 'expense'
-- because create_transaction only accepts income/expense categories
UPDATE categories SET category_kind = 'expense' WHERE system_key = 'adjustment';

-- Revert check constraint to original (only income/expense)
ALTER TABLE categories DROP CONSTRAINT IF EXISTS categories_category_kind_check;
ALTER TABLE categories ADD CONSTRAINT categories_category_kind_check
  CHECK (category_kind IN ('income', 'expense'));
