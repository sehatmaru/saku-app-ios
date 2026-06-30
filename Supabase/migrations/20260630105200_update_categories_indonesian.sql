-- Update default expense categories to the new list with Indonesian translations and custom icons/colors
UPDATE categories SET 
  name = 'Makan Harian', 
  normalized_name = 'makan harian', 
  system_key = 'expense_daily_meals', 
  icon = 'fork.knife', 
  color = '#FF6B6B' 
WHERE system_key = 'expense_food_drink';

UPDATE categories SET 
  name = 'Jajan & Kopi', 
  normalized_name = 'jajan & kopi', 
  system_key = 'expense_snack_coffee', 
  icon = 'cup.and.saucer', 
  color = '#45B7D1' 
WHERE system_key = 'expense_education';

UPDATE categories SET 
  name = 'Restoran & Mall', 
  normalized_name = 'restoran & mall', 
  system_key = 'expense_restaurant_mall', 
  icon = 'wineglass', 
  color = '#FFEAA7' 
WHERE system_key = 'expense_financial';

UPDATE categories SET 
  name = 'Pengeluaran Pribadi', 
  normalized_name = 'pengeluaran pribadi', 
  system_key = 'expense_personal_spending', 
  icon = 'bag', 
  color = '#4ECDC4' 
WHERE system_key = 'expense_shopping';

UPDATE categories SET 
  name = 'Hiburan', 
  normalized_name = 'hiburan', 
  system_key = 'expense_entertainment', 
  icon = 'gamecontroller', 
  color = '#F7DC6F' 
WHERE system_key = 'expense_entertainment';

UPDATE categories SET 
  name = 'Belanja & Rumah Tangga', 
  normalized_name = 'belanja & rumah tangga', 
  system_key = 'expense_groceries_household', 
  icon = 'cart', 
  color = '#96CEB4' 
WHERE system_key = 'expense_housing';

UPDATE categories SET 
  name = 'Transportasi', 
  normalized_name = 'transportasi', 
  system_key = 'expense_transport', 
  icon = 'car', 
  color = '#98D8C8' 
WHERE system_key = 'expense_transportation';

UPDATE categories SET 
  name = 'Perawatan & Kesehatan', 
  normalized_name = 'perawatan & kesehatan', 
  system_key = 'expense_care_health', 
  icon = 'heart', 
  color = '#6BCB77' 
WHERE system_key = 'expense_health';

UPDATE categories SET 
  name = 'Sosial & Donasi', 
  normalized_name = 'sosial & donasi', 
  system_key = 'expense_social_donation', 
  icon = 'hand.raised', 
  color = '#FF8C42' 
WHERE system_key = 'expense_donation';

UPDATE categories SET 
  name = 'Olahraga & Kebugaran', 
  normalized_name = 'olahraga & kebugaran', 
  system_key = 'expense_sport_fitness', 
  icon = 'dumbbell', 
  color = '#A0A0A0' 
WHERE system_key = 'expense_investment';

UPDATE categories SET 
  name = 'Lain-lain', 
  normalized_name = 'lain-lain', 
  system_key = 'expense_etc', 
  icon = 'ellipsis', 
  color = '#DDA0DD' 
WHERE system_key = 'expense_family';

-- Translate income categories to Indonesian
UPDATE categories SET 
  name = 'Gaji', 
  normalized_name = 'gaji', 
  icon = 'dollarsign.circle', 
  color = '#4ECDC4' 
WHERE system_key = 'income_salary';

UPDATE categories SET 
  name = 'Bisnis', 
  normalized_name = 'bisnis', 
  icon = 'briefcase', 
  color = '#45B7D1' 
WHERE system_key = 'income_business';

UPDATE categories SET 
  name = 'Investasi', 
  normalized_name = 'investasi', 
  icon = 'chart.line.uptrend.xyaxis', 
  color = '#96CEB4' 
WHERE system_key = 'income_investment';

UPDATE categories SET 
  name = 'Lainnya', 
  normalized_name = 'lainnya', 
  icon = 'ellipsis', 
  color = '#A0A0A0' 
WHERE system_key = 'income_other';
