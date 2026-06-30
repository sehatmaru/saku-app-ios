-- Revoke anon EXECUTE on SECURITY DEFINER functions (should only be callable by authenticated users)
REVOKE EXECUTE ON FUNCTION public.create_budget(p_amount numeric, p_category_id uuid, p_client_operation_id text, p_end_date date, p_name text, p_period_interval integer, p_period_unit text, p_start_date date) FROM anon;
REVOKE EXECUTE ON FUNCTION public.create_transaction(p_amount numeric, p_category_id uuid, p_client_operation_id text, p_description text, p_note text, p_occurred_at timestamp with time zone, p_primary_account_id uuid, p_transaction_type text) FROM anon;
REVOKE EXECUTE ON FUNCTION public.create_transfer(p_amount numeric, p_client_operation_id text, p_counterparty_account_id uuid, p_description text, p_note text, p_occurred_at timestamp with time zone, p_primary_account_id uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION public.current_profile_id() FROM anon;
REVOKE EXECUTE ON FUNCTION public.handle_auth_user_created() FROM anon;
REVOKE EXECUTE ON FUNCTION public.rls_auto_enable() FROM anon;
REVOKE EXECUTE ON FUNCTION public.update_transaction(p_transaction_id uuid, p_amount numeric, p_category_id uuid, p_description text, p_note text, p_occurred_at timestamp with time zone, p_primary_account_id uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION public.void_transaction(p_transaction_id uuid) FROM anon;
