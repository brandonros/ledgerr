-- Main public function: Simple and reliable
CREATE OR REPLACE FUNCTION ledgerr.get_account_balance(
    p_account_id UUID,
    p_as_of_date DATE DEFAULT CURRENT_DATE,
    p_use_cache BOOLEAN DEFAULT TRUE
) RETURNS DECIMAL(15,2) AS $$
DECLARE
    v_balance DECIMAL(15,2);
    v_cached_balance DECIMAL(15,2);
    v_is_current_date BOOLEAN;
    v_cache_insert_result TEXT;
    v_isolation_level TEXT;
BEGIN
    v_is_current_date := (p_as_of_date = CURRENT_DATE);
    
    RAISE NOTICE 'get_account_balance: START - account_id=%, as_of_date=%, use_cache=%, is_current_date=%', 
        p_account_id, p_as_of_date, p_use_cache, v_is_current_date;

    -- Require SERIALIZABLE isolation if we are using cache
    IF p_use_cache THEN
        SELECT current_setting('transaction_isolation') INTO v_isolation_level;
        IF v_isolation_level != 'serializable' THEN
            RAISE EXCEPTION 'Cached balance operations require SERIALIZABLE isolation level, current level is: %', v_isolation_level;
        END IF;
    END IF;
    
    -- For current date, try cache first if requested
    IF p_use_cache AND v_is_current_date THEN
        RAISE NOTICE 'get_account_balance: Attempting to use cache for current date';
        v_cached_balance := ledgerr.get_cached_balance(p_account_id);
        
        RAISE NOTICE 'get_account_balance: Cache result - cached_balance=%', v_cached_balance;
        
        IF v_cached_balance IS NOT NULL THEN
            RAISE NOTICE 'get_account_balance: END - returning cached balance=%', v_cached_balance;
            RETURN v_cached_balance;
        END IF;
        
        RAISE NOTICE 'get_account_balance: Cache miss or stale, proceeding to calculate';
    END IF;
    
    -- Use snapshot optimization for historical dates, direct calculation for current
    IF v_is_current_date THEN
        RAISE NOTICE 'get_account_balance: Using direct calculation for current date';
        v_balance := ledgerr.calculate_balance_from_journal(p_account_id, p_as_of_date);
    ELSE
        RAISE NOTICE 'get_account_balance: Using snapshot optimization for historical date';
        v_balance := ledgerr.get_balance_with_snapshot_optimization(p_account_id, p_as_of_date);
    END IF;
    
    RAISE NOTICE 'get_account_balance: Calculated balance=%', v_balance;
    
    -- Cache the result if it's for current date
    IF p_use_cache AND v_is_current_date THEN
        RAISE NOTICE 'get_account_balance: Attempting to cache result for current date';
        
        BEGIN
            INSERT INTO ledgerr.account_balances (account_id, current_balance, available_balance)
            VALUES (p_account_id, v_balance, v_balance)
            ON CONFLICT (account_id) DO UPDATE SET
                current_balance = EXCLUDED.current_balance,
                available_balance = EXCLUDED.available_balance,
                last_updated = CURRENT_TIMESTAMP,
                version = account_balances.version + 1;
            
            v_cache_insert_result := 'SUCCESS';
            RAISE NOTICE 'get_account_balance: Cache update successful';
        EXCEPTION
            WHEN OTHERS THEN
                v_cache_insert_result := 'FAILED: ' || SQLERRM;
                RAISE NOTICE 'get_account_balance: Cache update failed - %', SQLERRM;
        END;
        
        RAISE NOTICE 'get_account_balance: Cache operation result - %', v_cache_insert_result;
    END IF;
    
    RAISE NOTICE 'get_account_balance: END - returning final balance=%', v_balance;
    RETURN v_balance;
END;
$$ LANGUAGE plpgsql;

-- Overload function to accept TIMESTAMP and convert to DATE
CREATE OR REPLACE FUNCTION ledgerr.get_account_balance(
    p_account_id INTEGER,
    p_as_of_timestamp TIMESTAMP,
    p_use_cache BOOLEAN DEFAULT TRUE
) RETURNS DECIMAL(15,2) AS $$
BEGIN
    RAISE NOTICE 'get_account_balance (timestamp overload): Converting timestamp % to date', p_as_of_timestamp;
    RETURN ledgerr.get_account_balance(p_account_id, p_as_of_timestamp::DATE, p_use_cache);
END;
$$ LANGUAGE plpgsql;
