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