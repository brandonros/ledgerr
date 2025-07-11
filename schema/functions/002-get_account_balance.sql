CREATE OR REPLACE FUNCTION ledgerr.calculate_balance_from_journal(
    p_account_id INTEGER,
    p_as_of_date DATE DEFAULT CURRENT_DATE
) RETURNS DECIMAL(15,2) AS $$
DECLARE
    v_balance DECIMAL(15,2);
    v_account_type VARCHAR(20);
BEGIN
    -- Get account type (with validation)
    SELECT account_type INTO v_account_type
    FROM ledgerr.accounts 
    WHERE account_id = p_account_id AND is_active = TRUE;
    
    IF v_account_type IS NULL THEN
        RAISE EXCEPTION 'Account ID % does not exist or is inactive', p_account_id;
    END IF;
    
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
BEGIN
    -- Validate account exists
    SELECT account_type INTO v_account_type
    FROM ledgerr.accounts 
    WHERE account_id = p_account_id AND is_active = TRUE;
    
    IF v_account_type IS NULL THEN
        RAISE EXCEPTION 'Account ID % does not exist or is inactive', p_account_id;
    END IF;
    
    -- For current date, skip snapshot optimization
    IF p_as_of_date = CURRENT_DATE THEN
        RETURN ledgerr.calculate_balance_from_journal(p_account_id, p_as_of_date);
    END IF;
    
    -- Try exact snapshot match first
    SELECT closing_balance INTO v_snapshot_balance
    FROM ledgerr.daily_balance_snapshots 
    WHERE account_id = p_account_id 
      AND snapshot_date = p_as_of_date;
    
    IF v_snapshot_balance IS NOT NULL THEN
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
    
    -- If we have a recent snapshot, calculate incrementally
    IF v_snapshot_date IS NOT NULL AND (p_as_of_date - v_snapshot_date) <= 7 THEN
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
        
        RETURN COALESCE(v_balance, v_snapshot_balance);
    END IF;
    
    -- Fall back to full calculation
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
BEGIN
    -- Get cached balance and timestamp
    SELECT current_balance, last_updated 
    INTO v_cached_balance, v_cache_timestamp
    FROM ledgerr.account_balances 
    WHERE account_id = p_account_id;
    
    -- If no cache exists, return NULL
    IF v_cached_balance IS NULL THEN
        RETURN NULL;
    END IF;
    
    -- Check if there are transactions after cache timestamp
    SELECT MAX(je.created_at) INTO v_latest_transaction
    FROM ledgerr.journal_entry_lines jel
    JOIN ledgerr.journal_entries je ON jel.entry_id = je.entry_id
    WHERE jel.account_id = p_account_id
      AND je.is_posted = TRUE
      AND je.created_at > v_cache_timestamp;
    
    -- If no new transactions, return cached balance
    IF v_latest_transaction IS NULL THEN
        RETURN v_cached_balance;
    END IF;
    
    -- Cache is stale
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
BEGIN
    -- For current date, try cache first if requested
    IF p_use_cache AND p_as_of_date = CURRENT_DATE THEN
        v_balance := ledgerr.get_cached_balance(p_account_id);
        
        IF v_balance IS NOT NULL THEN
            RETURN v_balance;
        END IF;
    END IF;
    
    -- Use snapshot optimization for historical dates, direct calculation for current
    IF p_as_of_date = CURRENT_DATE THEN
        v_balance := ledgerr.calculate_balance_from_journal(p_account_id, p_as_of_date);
    ELSE
        v_balance := ledgerr.get_balance_with_snapshot_optimization(p_account_id, p_as_of_date);
    END IF;
    
    -- Cache the result if it's for current date
    IF p_use_cache AND p_as_of_date = CURRENT_DATE THEN
        INSERT INTO ledgerr.account_balances (account_id, current_balance, available_balance)
        VALUES (p_account_id, v_balance, v_balance)
        ON CONFLICT (account_id) DO UPDATE SET
            current_balance = EXCLUDED.current_balance,
            available_balance = EXCLUDED.available_balance,
            last_updated = CURRENT_TIMESTAMP,
            version = account_balances.version + 1;
    END IF;
    
    RETURN v_balance;
END;
$$ LANGUAGE plpgsql;
