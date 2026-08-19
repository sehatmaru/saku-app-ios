CREATE OR REPLACE FUNCTION get_account_user_id(pid UUID)
RETURNS UUID
LANGUAGE SQL
STABLE
SECURITY DEFINER
SET row_security = off
AS $$ SELECT user_id FROM public.accounts WHERE id = pid; $$;

DROP POLICY IF EXISTS "Users can manage their own card subscriptions" ON card_subscriptions;

CREATE POLICY "card_subscriptions_policy"
    ON card_subscriptions
    FOR ALL
    USING (get_account_user_id(account_id) = auth.uid())
    WITH CHECK (get_account_user_id(account_id) = auth.uid());
