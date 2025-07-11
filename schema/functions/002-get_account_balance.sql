CREATE OR REPLACE FUNCTION ledgerr.calculate_balance_from_journal(
    p_account_id INTEGER,
    p_as_of_date DATE DEFAULT CURRENT_DATE
) RETURNS DECIMAL(15,2) AS $$
DECLARE
    v_balance DECIMAL(15,2);
    v_account_type VARCHAR(20);
    v_journal_count INTEGER;
    v_debit_total DECIMAL(15,2);
    v_credit_total DECIMAL(15,2);
BEGIN
    RAISE NOTICE 'calculate_balance_from_journal: START - account_id=%, as_of_date=%', p_account_id, p_as_of_date;
    
    -- Get account type (with validation)
    SELECT account_type INTO v_account_type
    FROM ledgerr.accounts 
    WHERE account_id = p_account_id AND is_active = TRUE;
    
    RAISE NOTICE 'calculate_balance_from_journal: Account lookup - account_type=%, found=%', 
        v_account_type, (v_account_type IS NOT NULL);
    
    IF v_account_type IS NULL THEN
        RAISE EXCEPTION 'Account ID % does not exist or is inactive', p_account_id;
    END IF;
    
    -- Count journal entries for debugging
    SELECT COUNT(*) INTO v_journal_count
    FROM ledgerr.journal_entry_lines jel
    JOIN ledgerr.journal_entries je ON jel.entry_id = je.entry_id
    WHERE jel.account_id = p_account_id
      AND je.entry_date <= p_as_of_date
      AND je.is_posted = TRUE;
    
    RAISE NOTICE 'calculate_balance_from_journal: Found % journal entries for account % up to date %', 
        v_journal_count, p_account_id, p_as_of_date;
    
    -- Get debit and credit totals separately for debugging
    SELECT 
        COALESCE(SUM(jel.debit_amount), 0),
        COALESCE(SUM(jel.credit_amount), 0)
    INTO v_debit_total, v_credit_total
    FROM ledgerr.journal_entry_lines jel
    JOIN ledgerr.journal_entries je ON jel.entry_id = je.entry_id
    WHERE jel.account_id = p_account_id
      AND je.entry_date <= p_as_of_date
      AND je.is_posted = TRUE;
    
    RAISE NOTICE 'calculate_balance_from_journal: Totals - debit_total=%, credit_total=%', 
        v_debit_total, v_credit_total;
    
    -- Calculate balance based on account type
    SELECT 
        CASE 
            WHEN v_account_type IN ('ASSET', 'EXPENSE') THEN
                COALESCE(SUM(jel.debit_amount - jel.credit_amount), 0)
            ELSE
                COALESCE(SUM(jel.credit_amount - jel.debit_amount), 0)
        END
    INTO v_balance
    FROM ledgerr.journal_entry_lines jel
    JOIN ledgerr.journal_entries je ON jel.entry_id = je.entry_id
    WHERE jel.account_id = p_account_id
      AND je.entry_date <= p_as_of_date
      AND je.is_posted = TRUE;
    
    RAISE NOTICE 'calculate_balance_from_journal: Balance calculation - account_type=%, raw_balance=%, final_balance=%', 
        v_account_type, v_balance, COALESCE(v_balance, 0);
    
    RAISE NOTICE 'calculate_balance_from_journal: END - returning balance=%', COALESCE(v_balance, 0);
    
    RETURN COALESCE(v_balance, 0);
END;
$$ LANGUAGE plpgsql;

-- Optimized function: Try snapshot first, fall back to calculation
CREATE OR REPLACE FUNCTION ledgerr.get_balance_with_snapshot_optimization(
    p_account_id INTEGER,
    p_as_of_date DATE DEFAULT CURRENT_DATE
) RETURNS DECIMAL(15,2) AS $$
DECLARE
    v_balance DECIMAL(15,2);
    v_snapshot_balance DECIMAL(15,2);
    v_snapshot_date DATE;
    v_account_type VARCHAR(20);
    v_snapshot_count INTEGER;
    v_incremental_count INTEGER;
    v_days_diff INTEGER;
BEGIN
    RAISE NOTICE 'get_balance_with_snapshot_optimization: START - account_id=%, as_of_date=%', p_account_id, p_as_of_date;
    
    -- Validate account exists
    SELECT account_type INTO v_account_type
    FROM ledgerr.accounts 
    WHERE account_id = p_account_id AND is_active = TRUE;
    
    RAISE NOTICE 'get_balance_with_snapshot_optimization: Account validation - account_type=%, valid=%', 
        v_account_type, (v_account_type IS NOT NULL);
    
    IF v_account_type IS NULL THEN
        RAISE EXCEPTION 'Account ID % does not exist or is inactive', p_account_id;
    END IF;
    
    -- For current date, skip snapshot optimization
    IF p_as_of_date = CURRENT_DATE THEN
        RAISE NOTICE 'get_balance_with_snapshot_optimization: Current date detected, delegating to calculate_balance_from_journal';
        RETURN ledgerr.calculate_balance_from_journal(p_account_id, p_as_of_date);
    END IF;
    
    -- Count available snapshots for debugging
    SELECT COUNT(*) INTO v_snapshot_count
    FROM ledgerr.daily_balance_snapshots 
    WHERE account_id = p_account_id;
    
    RAISE NOTICE 'get_balance_with_snapshot_optimization: Found % total snapshots for account %', 
        v_snapshot_count, p_account_id;
    
    -- Try exact snapshot match first
    SELECT closing_balance INTO v_snapshot_balance
    FROM ledgerr.daily_balance_snapshots 
    WHERE account_id = p_account_id 
      AND snapshot_date = p_as_of_date;
    
    RAISE NOTICE 'get_balance_with_snapshot_optimization: Exact snapshot match - found=%, balance=%', 
        (v_snapshot_balance IS NOT NULL), v_snapshot_balance;
    
    IF v_snapshot_balance IS NOT NULL THEN
        RAISE NOTICE 'get_balance_with_snapshot_optimization: END - returning exact snapshot balance=%', v_snapshot_balance;
        RETURN v_snapshot_balance;
    END IF;
    
    -- Find most recent snapshot before requested date
    SELECT snapshot_date, closing_balance 
    INTO v_snapshot_date, v_snapshot_balance
    FROM ledgerr.daily_balance_snapshots 
    WHERE account_id = p_account_id 
      AND snapshot_date < p_as_of_date
    ORDER BY snapshot_date DESC 
    LIMIT 1;
    
    v_days_diff := CASE WHEN v_snapshot_date IS NOT NULL THEN p_as_of_date - v_snapshot_date ELSE NULL END;
    
    RAISE NOTICE 'get_balance_with_snapshot_optimization: Recent snapshot search - snapshot_date=%, snapshot_balance=%, days_diff=%', 
        v_snapshot_date, v_snapshot_balance, v_days_diff;
    
    -- If we have a recent snapshot, calculate incrementally
    IF v_snapshot_date IS NOT NULL AND (p_as_of_date - v_snapshot_date) <= 7 THEN
        RAISE NOTICE 'get_balance_with_snapshot_optimization: Using incremental calculation from snapshot';
        
        -- Count incremental transactions
        SELECT COUNT(*) INTO v_incremental_count
        FROM ledgerr.journal_entry_lines jel
        JOIN ledgerr.journal_entries je ON jel.entry_id = je.entry_id
        WHERE jel.account_id = p_account_id
          AND je.entry_date > v_snapshot_date
          AND je.entry_date <= p_as_of_date
          AND je.is_posted = TRUE;
        
        RAISE NOTICE 'get_balance_with_snapshot_optimization: Found % incremental transactions between % and %', 
            v_incremental_count, v_snapshot_date, p_as_of_date;
        
        SELECT 
            v_snapshot_balance + 
            CASE 
                WHEN v_account_type IN ('ASSET', 'EXPENSE') THEN
                    COALESCE(SUM(jel.debit_amount - jel.credit_amount), 0)
                ELSE
                    COALESCE(SUM(jel.credit_amount - jel.debit_amount), 0)
            END
        INTO v_balance
        FROM ledgerr.journal_entry_lines jel
        JOIN ledgerr.journal_entries je ON jel.entry_id = je.entry_id
        WHERE jel.account_id = p_account_id
          AND je.entry_date > v_snapshot_date
          AND je.entry_date <= p_as_of_date
          AND je.is_posted = TRUE;
        
        RAISE NOTICE 'get_balance_with_snapshot_optimization: Incremental calculation - starting_balance=%, final_balance=%', 
            v_snapshot_balance, COALESCE(v_balance, v_snapshot_balance);
        
        RAISE NOTICE 'get_balance_with_snapshot_optimization: END - returning incremental balance=%', COALESCE(v_balance, v_snapshot_balance);
        RETURN COALESCE(v_balance, v_snapshot_balance);
    END IF;
    
    -- Fall back to full calculation
    RAISE NOTICE 'get_balance_with_snapshot_optimization: No suitable snapshot found, falling back to full calculation';
    RAISE NOTICE 'get_balance_with_snapshot_optimization: END - delegating to calculate_balance_from_journal';
    RETURN ledgerr.calculate_balance_from_journal(p_account_id, p_as_of_date);
END;
$$ LANGUAGE plpgsql;

-- Cache management function
CREATE OR REPLACE FUNCTION ledgerr.get_cached_balance(
    p_account_id INTEGER
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

-- Main public function: Simple and reliable
CREATE OR REPLACE FUNCTION ledgerr.get_account_balance(
    p_account_id INTEGER,
    p_as_of_date DATE DEFAULT CURRENT_DATE,
    p_use_cache BOOLEAN DEFAULT TRUE
) RETURNS DECIMAL(15,2) AS $$
DECLARE
    v_balance DECIMAL(15,2);
    v_cached_balance DECIMAL(15,2);
    v_is_current_date BOOLEAN;
    v_cache_insert_result TEXT;
BEGIN
    v_is_current_date := (p_as_of_date = CURRENT_DATE);
    
    RAISE NOTICE 'get_account_balance: START - account_id=%, as_of_date=%, use_cache=%, is_current_date=%', 
        p_account_id, p_as_of_date, p_use_cache, v_is_current_date;
    
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
