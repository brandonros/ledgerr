CREATE OR REPLACE FUNCTION get_account_balance(
    p_account_id INTEGER, 
    p_as_of_date DATE DEFAULT CURRENT_DATE,
    p_use_cache BOOLEAN DEFAULT TRUE
) RETURNS DECIMAL(15,2) AS $$
DECLARE
    v_balance DECIMAL(15,2);
    v_account_type VARCHAR(20);
    v_last_updated TIMESTAMP;
    v_is_current_date BOOLEAN;
BEGIN
    -- Get account type and validate account exists
    SELECT account_type INTO v_account_type
    FROM accounts 
    WHERE account_id = p_account_id AND is_active = TRUE;
    
    IF v_account_type IS NULL THEN
        RAISE EXCEPTION 'Account ID % does not exist or is inactive', p_account_id;
    END IF;
    
    -- Check if requesting current date balance (for caching logic)
    v_is_current_date := (p_as_of_date = CURRENT_DATE);
    
    -- Try to get cached balance if using cache and requesting current date
    IF p_use_cache AND v_is_current_date THEN
        SELECT current_balance, last_updated 
        INTO v_balance, v_last_updated
        FROM account_balances 
        WHERE account_id = p_account_id;
        
        -- If we have a cached balance, return it
        IF v_balance IS NOT NULL THEN
            RETURN v_balance;
        END IF;
    END IF;
    
    -- Calculate balance based on account type
    SELECT 
        CASE 
            WHEN v_account_type IN ('ASSET', 'EXPENSE') THEN
                COALESCE(SUM(debit_amount - credit_amount), 0)
            WHEN v_account_type IN ('LIABILITY', 'EQUITY', 'REVENUE') THEN
                COALESCE(SUM(credit_amount - debit_amount), 0)
        END
    INTO v_balance
    FROM journal_entry_lines jel
    JOIN journal_entries je ON jel.entry_id = je.entry_id
    WHERE jel.account_id = p_account_id
      AND je.entry_date <= p_as_of_date
      AND je.is_posted = TRUE;
    
    -- Set default if null
    v_balance := COALESCE(v_balance, 0);
    
    -- Cache the balance if using cache and this is for current date
    IF p_use_cache AND v_is_current_date THEN
        INSERT INTO account_balances (account_id, current_balance, available_balance)
        VALUES (p_account_id, v_balance, v_balance)
        ON CONFLICT (account_id) DO UPDATE SET
            current_balance = EXCLUDED.current_balance,
            available_balance = EXCLUDED.available_balance,
            last_updated = CURRENT_TIMESTAMP;
    END IF;
    
    RETURN v_balance;
END;
$$ LANGUAGE plpgsql;