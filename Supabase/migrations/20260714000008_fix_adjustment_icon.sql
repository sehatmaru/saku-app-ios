UPDATE categories SET icon = 'arrow.2.circlepath' WHERE system_key = 'adjustment';

CREATE OR REPLACE FUNCTION create_adjustment_log(
    p_primary_account_id UUID,
    p_amount DECIMAL,
    p_note TEXT,
    p_occurred_at TIMESTAMPTZ
) RETURNS UUID AS $$
DECLARE
    v_user_id UUID;
    v_category_id UUID;
    v_id UUID;
BEGIN
    SELECT user_id INTO v_user_id FROM accounts WHERE id = p_primary_account_id;
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Account not found';
    END IF;

    SELECT id INTO v_category_id FROM categories WHERE system_key = 'adjustment' AND deleted_at IS NULL;

    INSERT INTO transactions (
        primary_account_id, user_id, category_id,
        amount, transaction_type, description, note, occurred_at,
        delta
    ) VALUES (
        p_primary_account_id, v_user_id, v_category_id,
        abs(p_amount), 'adjustment',
        p_note, NULL, p_occurred_at,
        p_amount
    ) RETURNING id INTO v_id;

    RETURN v_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

REVOKE EXECUTE ON FUNCTION public.create_adjustment_log(UUID, DECIMAL, TEXT, TIMESTAMPTZ) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.create_adjustment_log(UUID, DECIMAL, TEXT, TIMESTAMPTZ) FROM anon;
GRANT EXECUTE ON FUNCTION public.create_adjustment_log(UUID, DECIMAL, TEXT, TIMESTAMPTZ) TO authenticated;
