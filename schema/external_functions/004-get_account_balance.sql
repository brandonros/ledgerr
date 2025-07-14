CREATE OR REPLACE FUNCTION ledgerr_api.get_account_balance(
    p_account_id UUID,
    p_as_of_date DATE DEFAULT CURRENT_DATE,
    p_force_recalculate BOOLEAN DEFAULT FALSE
) RETURNS ledgerr_api.account_balance_result AS $$
DECLARE
    result ledgerr_api.account_balance_result;
BEGIN
    -- Validate input parameters
    IF p_account_id IS NULL THEN
        RAISE EXCEPTION 'Account ID cannot be null';
    END IF;

    IF p_as_of_date IS NULL THEN
        RAISE EXCEPTION 'As of date cannot be null';
    END IF;

    -- If we're forcing recalculation, just do it and return the result
    IF p_force_recalculate THEN
        result := ledgerr_api.calculate_account_balance(p_account_id, p_as_of_date);
        RETURN result;
    END IF;

    -- Lookup the balance
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

    -- If the balance is not found, we have a data integrity issue
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Account balance cache record not found for account %. This indicates a data integrity issue.', p_account_id;
    END IF;

    -- If the as_of_date is before the last activity date, we need to recalculate the balance
    IF result.last_activity_date IS NULL OR p_as_of_date < result.last_activity_date THEN
        result := ledgerr_api.calculate_account_balance(p_account_id, p_as_of_date);
    END IF;
    
    RETURN result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE;