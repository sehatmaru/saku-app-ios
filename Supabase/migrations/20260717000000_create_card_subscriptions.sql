CREATE TABLE IF NOT EXISTS card_subscriptions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    account_id UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    amount DECIMAL(15,2) NOT NULL,
    frequency TEXT NOT NULL CHECK (frequency IN ('monthly', 'yearly')),
    next_billing_date DATE,
    is_active BOOLEAN DEFAULT true,
    category_id UUID REFERENCES categories(id),
    note TEXT,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE card_subscriptions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can manage their own card subscriptions"
    ON card_subscriptions
    FOR ALL
    USING (
        EXISTS (
            SELECT 1 FROM accounts
            WHERE accounts.id = card_subscriptions.account_id
            AND accounts.user_id = auth.uid()
        )
    )
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM accounts
            WHERE accounts.id = card_subscriptions.account_id
            AND accounts.user_id = auth.uid()
        )
    );
