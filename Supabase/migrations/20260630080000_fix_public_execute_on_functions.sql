-- Fix: functions were granted to PUBLIC (anon + authenticated) instead of just authenticated
-- Revoke PUBLIC access and grant EXECUTE only to authenticated role

-- create_budget
REVOKE EXECUTE ON FUNCTION public.create_budget(p_amount numeric, p_category_id uuid, p_client_operation_id text, p_end_date date, p_name text, p_period_interval integer, p_period_unit text, p_start_date date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_budget(p_amount numeric, p_category_id uuid, p_client_operation_id text, p_end_date date, p_name text, p_period_interval integer, p_period_unit text, p_start_date date) TO authenticated;

-- create_transaction
REVOKE EXECUTE ON FUNCTION public.create_transaction(p_amount numeric, p_category_id uuid, p_client_operation_id text, p_description text, p_note text, p_occurred_at timestamp with time zone, p_primary_account_id uuid, p_transaction_type text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_transaction(p_amount numeric, p_category_id uuid, p_client_operation_id text, p_description text, p_note text, p_occurred_at timestamp with time zone, p_primary_account_id uuid, p_transaction_type text) TO authenticated;

-- create_transfer
REVOKE EXECUTE ON FUNCTION public.create_transfer(p_amount numeric, p_client_operation_id text, p_counterparty_account_id uuid, p_description text, p_note text, p_occurred_at timestamp with time zone, p_primary_account_id uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_transfer(p_amount numeric, p_client_operation_id text, p_counterparty_account_id uuid, p_description text, p_note text, p_occurred_at timestamp with time zone, p_primary_account_id uuid) TO authenticated;

-- current_profile_id (needed by RLS policies)
REVOKE EXECUTE ON FUNCTION public.current_profile_id() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.current_profile_id() TO authenticated;

-- handle_auth_user_created (trigger function only)
REVOKE EXECUTE ON FUNCTION public.handle_auth_user_created() FROM PUBLIC;

-- rls_auto_enable (migration helper)
REVOKE EXECUTE ON FUNCTION public.rls_auto_enable() FROM PUBLIC;

-- update_transaction
REVOKE EXECUTE ON FUNCTION public.update_transaction(p_transaction_id uuid, p_amount numeric, p_category_id uuid, p_description text, p_note text, p_occurred_at timestamp with time zone, p_primary_account_id uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.update_transaction(p_transaction_id uuid, p_amount numeric, p_category_id uuid, p_description text, p_note text, p_occurred_at timestamp with time zone, p_primary_account_id uuid) TO authenticated;

-- void_transaction
REVOKE EXECUTE ON FUNCTION public.void_transaction(p_transaction_id uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.void_transaction(p_transaction_id uuid) TO authenticated;
