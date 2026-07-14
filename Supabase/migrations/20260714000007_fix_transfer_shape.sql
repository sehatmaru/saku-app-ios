ALTER TABLE transactions DROP CONSTRAINT IF EXISTS transactions_transfer_shape;
ALTER TABLE transactions ADD CONSTRAINT transactions_transfer_shape CHECK (
    (transaction_type = 'transfer' AND counterparty_account_id IS NOT NULL AND category_id IS NULL)
    OR
    (transaction_type IN ('income', 'expense', 'adjustment') AND category_id IS NOT NULL AND counterparty_account_id IS NULL)
);
