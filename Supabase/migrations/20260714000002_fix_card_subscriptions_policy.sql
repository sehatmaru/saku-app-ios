-- Fix card_subscriptions RLS policy: compare against profile id (current_profile_id),
-- not auth.uid() directly, because accounts.user_id stores the profile id.
-- Previously the policy compared profile id = auth.uid(), which never matched,
-- causing all operations to fail with 42501 (RLS violation).
ALTER POLICY card_subscriptions_policy ON card_subscriptions
  USING (get_account_user_id(account_id) = current_profile_id())
  WITH CHECK (get_account_user_id(account_id) = current_profile_id());
