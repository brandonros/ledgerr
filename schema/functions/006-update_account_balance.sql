CREATE OR REPLACE FUNCTION ledgerr.update_account_balance(
    p_account_id INTEGER,
    p_debit_amount DECIMAL(15,2) DEFAULT 0.00,
    p_credit_amount DECIMAL(15,2) DEFAULT 0.00,
    p_expected_version INTEGER DEFAULT NULL
) RETURNS TABLE (
    success BOOLEAN,
    new_balance DECIMAL(15,2),
    new_version INTEGER,
    error_message TEXT
) AS $$
DECLARE
    v_current_version INTEGER;
    v_new_balance DECIMAL(15,2);
    v_new_version INTEGER;
    v_daily_reset_needed BOOLEAN := FALSE;
BEGIN
    -- Initialize balance if it doesn't exist
    PERFORM initialize_account_balance(p_account_id);
    
    -- Lock the row and get current state
    SELECT version, current_balance, 
           (last_daily_reset < CURRENT_DATE) as daily_reset_needed
    INTO v_current_version, v_new_balance, v_daily_reset_needed
    FROM ledgerr.account_balances 
    WHERE account_id = p_account_id 
    FOR UPDATE;
    
    -- Check optimistic lock if version provided
    IF p_expected_version IS NOT NULL AND v_current_version != p_expected_version THEN
        RETURN QUERY SELECT FALSE, NULL::DECIMAL(15,2), NULL::INTEGER, 
                           'Version mismatch - concurrent update detected'::TEXT;
        RETURN;
    END IF;
    
    -- Calculate new balance
    v_new_balance := v_new_balance + p_credit_amount - p_debit_amount;
    v_new_version := v_current_version + 1;
    
    -- Update with optimistic locking
    UPDATE account_balances SET
        current_balance = v_new_balance,
        available_balance = v_new_balance - pending_debits,
        version = v_new_version,
        last_updated = CURRENT_TIMESTAMP,
        daily_debit_total = CASE 
            WHEN v_daily_reset_needed THEN p_debit_amount
            ELSE daily_debit_total + p_debit_amount
        END,
        daily_credit_total = CASE 
            WHEN v_daily_reset_needed THEN p_credit_amount
            ELSE daily_credit_total + p_credit_amount
        END,
        last_daily_reset = CURRENT_DATE
    WHERE account_id = p_account_id 
      AND version = v_current_version;
    
    -- Verify update succeeded
    IF NOT FOUND THEN
        RETURN QUERY SELECT FALSE, NULL::DECIMAL(15,2), NULL::INTEGER, 
                           'Update failed - concurrent modification'::TEXT;
        RETURN;
    END IF;
    
    RETURN QUERY SELECT TRUE, v_new_balance, v_new_version, NULL::TEXT;
END;
$$ LANGUAGE plpgsql;