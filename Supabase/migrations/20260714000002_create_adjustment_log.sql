CREATE OR REPLACE FUNCTION create_adjustment_log(
    p_primary_account_id UUID,
    p_amount DECIMAL,
    p_note TEXT,
    p_occurred_at TIMESTAMPTZ
) RETURNS UUID AS $$
DECLARE
    v_id UUID;
BEGIN
    INSERT INTO transactions (
        primary_account_id, amount, transaction_type,
        description, note, occurred_at
    ) VALUES (
        p_primary_account_id, abs(p_amount),
        CASE WHEN p_amount >= 0 THEN 'income' ELSE 'expense' END,
        'Penyesuaian Saldo', p_note, p_occurred_at
    ) RETURNING id INTO v_id;
    RETURN v_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
