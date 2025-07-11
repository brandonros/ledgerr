-- Cache management function
CREATE OR REPLACE FUNCTION ledgerr.get_cached_balance(
    p_account_id UUID
) RETURNS DECIMAL(15,2) AS $$
DECLARE
    v_cached_balance DECIMAL(15,2);
    v_cache_timestamp TIMESTAMP;
    v_latest_transaction TIMESTAMP;
    v_cache_exists BOOLEAN := FALSE;
    v_transaction_count INTEGER;
    debug_rec RECORD;
BEGIN
    RAISE NOTICE 'get_cached_balance: START - account_id=%', p_account_id;
    
    -- Get cached balance and timestamp, check if row exists
    SELECT current_balance, last_updated, TRUE
    INTO v_cached_balance, v_cache_timestamp, v_cache_exists
    FROM ledgerr.account_balances 
    WHERE account_id = p_account_id;
    
    RAISE NOTICE 'get_cached_balance: Cache lookup - exists=%, balance=%, timestamp=%', 
        v_cache_exists, v_cached_balance, v_cache_timestamp;
    
    -- If no cache exists, return NULL
    IF NOT v_cache_exists THEN
        RAISE NOTICE 'get_cached_balance: END - no cache exists, returning NULL';
        RETURN NULL;
    END IF;
    
    -- Count transactions at or after cache timestamp
    SELECT COUNT(*) INTO v_transaction_count
    FROM ledgerr.journal_entry_lines jel
    JOIN ledgerr.journal_entries je ON jel.entry_id = je.entry_id
    WHERE jel.account_id = p_account_id
      AND je.is_posted = TRUE
      AND je.created_at >= v_cache_timestamp;
    
    RAISE NOTICE 'get_cached_balance: Found % transactions at/after cache timestamp %', 
        v_transaction_count, v_cache_timestamp;
    
    -- DEBUG: Show all transactions for this account with their timestamps
    FOR debug_rec IN (
        SELECT je.entry_id, je.created_at, je.entry_date, jel.debit_amount, jel.credit_amount,
               (je.created_at >= v_cache_timestamp) as is_after_cache
        FROM ledgerr.journal_entry_lines jel
        JOIN ledgerr.journal_entries je ON jel.entry_id = je.entry_id
        WHERE jel.account_id = p_account_id
          AND je.is_posted = TRUE
        ORDER BY je.created_at
    ) LOOP
        RAISE NOTICE 'get_cached_balance: Transaction - entry_id=%, created_at=%, entry_date=%, debit=%, credit=%, after_cache=%', 
            debug_rec.entry_id, debug_rec.created_at, debug_rec.entry_date, 
            debug_rec.debit_amount, debug_rec.credit_amount, debug_rec.is_after_cache;
    END LOOP;
    
    -- Check if there are transactions at or after cache timestamp
    SELECT MAX(je.created_at) INTO v_latest_transaction
    FROM ledgerr.journal_entry_lines jel
    JOIN ledgerr.journal_entries je ON jel.entry_id = je.entry_id
    WHERE jel.account_id = p_account_id
      AND je.is_posted = TRUE
      AND je.created_at >= v_cache_timestamp;
    
    RAISE NOTICE 'get_cached_balance: Latest transaction at/after cache - timestamp=%', v_latest_transaction;
    
    -- If no new transactions, return cached balance
    IF v_latest_transaction IS NULL THEN
        RAISE NOTICE 'get_cached_balance: END - cache is fresh, returning cached balance=%', v_cached_balance;
        RETURN v_cached_balance;
    END IF;
    
    -- Cache is stale
    RAISE NOTICE 'get_cached_balance: END - cache is stale, returning NULL';
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;