DO $$
BEGIN
    IF to_regtype('ledgerr_api.account_balance_result') IS NULL THEN
        CREATE TYPE ledgerr_api.account_balance_result AS (
            account_balance DECIMAL(15,2),
            total_debits DECIMAL(15,2),
            total_credits DECIMAL(15,2),
            transaction_count BIGINT,
            last_activity_date DATE
        );
    END IF;
END$$;

CREATE OR REPLACE FUNCTION ledgerr_api.get_account_balance(
    p_account_id UUID,
    p_as_of_date DATE DEFAULT CURRENT_DATE,
    p_force_recalculate BOOLEAN DEFAULT FALSE
) RETURNS ledgerr_api.account_balance_result AS $$
DECLARE
    result ledgerr_api.account_balance_result;
    cache_found BOOLEAN := FALSE;
BEGIN
    -- Try to get balance from cache first (unless forcing recalculation)
    -- Only use cache for current date queries
    IF NOT p_force_recalculate AND p_as_of_date = CURRENT_DATE THEN
        SELECT 
            current_balance,
            total_debits,
            total_credits,
            transaction_count,
            last_transaction_date
        INTO 
            result.account_balance,
            result.total_debits,
            result.total_credits,
            result.transaction_count,
            result.last_activity_date
        FROM ledgerr.account_balances 
        WHERE account_id = p_account_id;
        
        cache_found := FOUND;
        
        -- Enforce 1:1 relationship - cache record must exist for every account
        IF NOT cache_found THEN
            RAISE EXCEPTION 'Account balance cache record not found for account %. This indicates a data integrity issue.', p_account_id;
        END IF;
    END IF;
    
    -- If not using cache (historical query or force recalculate), fall back to expensive calculation
    IF NOT cache_found OR p_force_recalculate THEN
        SELECT 
            COALESCE(SUM(jel.debit_amount - jel.credit_amount), 0),
            COALESCE(SUM(jel.debit_amount), 0),
            COALESCE(SUM(jel.credit_amount), 0),
            COUNT(*),
            MAX(jel.entry_date)
        INTO 
            result.account_balance,
            result.total_debits,
            result.total_credits,
            result.transaction_count,
            result.last_activity_date
        FROM ledgerr.journal_entry_lines jel
        JOIN ledgerr.journal_entries je ON jel.entry_id = je.entry_id AND jel.entry_date = je.entry_date
        WHERE jel.account_id = p_account_id 
          AND jel.entry_date <= p_as_of_date
          AND je.is_posted = true;
    END IF;
    
    RETURN result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE;