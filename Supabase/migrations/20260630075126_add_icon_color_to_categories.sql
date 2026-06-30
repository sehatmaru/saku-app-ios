-- Add icon and color columns to categories (needed by Swift Category model)
ALTER TABLE categories ADD COLUMN IF NOT EXISTS icon TEXT;
ALTER TABLE categories ADD COLUMN IF NOT EXISTS color TEXT;

-- Seed icon/color for existing system categories
UPDATE categories SET icon = 'fork.knife', color = '#FF6B6B' WHERE system_key = 'expense_food_drink';
UPDATE categories SET icon = 'cup.and.saucer', color = '#45B7D1' WHERE system_key = 'expense_entertainment';
UPDATE categories SET icon = 'cart', color = '#FFEAA7' WHERE system_key = 'expense_shopping';
UPDATE categories SET icon = 'car', color = '#4ECDC4' WHERE system_key = 'expense_transportation';
UPDATE categories SET icon = 'heart', color = '#F7DC6F' WHERE system_key = 'expense_health';
UPDATE categories SET icon = 'house', color = '#96CEB4' WHERE system_key = 'expense_housing';
UPDATE categories SET icon = 'book', color = '#98D8C8' WHERE system_key = 'expense_education';
UPDATE categories SET icon = 'hand.raised', color = '#6BCB77' WHERE system_key = 'expense_donation';
UPDATE categories SET icon = 'chart.pie', color = '#FF8C42' WHERE system_key = 'expense_investment';
UPDATE categories SET icon = 'dollarsign', color = '#A0A0A0' WHERE system_key = 'expense_financial';
UPDATE categories SET icon = 'person.2', color = '#DDA0DD' WHERE system_key = 'expense_family';
UPDATE categories SET icon = 'dollarsign.circle', color = '#4ECDC4' WHERE system_key = 'income_salary';
UPDATE categories SET icon = 'briefcase', color = '#45B7D1' WHERE system_key = 'income_business';
UPDATE categories SET icon = 'chart.line.uptrend.xyaxis', color = '#96CEB4' WHERE system_key = 'income_investment';
UPDATE categories SET icon = 'ellipsis', color = '#A0A0A0' WHERE system_key = 'income_other';
