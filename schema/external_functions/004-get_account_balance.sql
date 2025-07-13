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
        result := ledgerr_api.calculate_account_balance(p_account_id, p_as_of_date);
    END IF;
    
    RETURN result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE;