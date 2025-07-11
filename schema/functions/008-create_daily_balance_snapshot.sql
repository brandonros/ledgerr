CREATE OR REPLACE FUNCTION create_daily_balance_snapshot(p_snapshot_date DATE DEFAULT CURRENT_DATE - INTERVAL '1 day')
RETURNS TABLE (
    accounts_processed INTEGER,
    total_time_ms INTEGER
) AS $$
DECLARE
    v_start_time TIMESTAMP := CURRENT_TIMESTAMP;
    v_accounts_processed INTEGER := 0;
    v_account RECORD;
    v_opening_balance DECIMAL(15,2);
    v_closing_balance DECIMAL(15,2);
    v_total_debits DECIMAL(15,2);
    v_total_credits DECIMAL(15,2);
    v_transaction_count INTEGER;
BEGIN
    -- Check if snapshot already exists
    IF EXISTS (SELECT 1 FROM daily_balance_snapshots WHERE snapshot_date = p_snapshot_date LIMIT 1) THEN
        RAISE NOTICE 'Snapshot for % already exists, skipping', p_snapshot_date;
        RETURN QUERY SELECT 0, 0;
        RETURN;
    END IF;
    
    -- Process each active account
    FOR v_account IN 
        SELECT account_id FROM accounts WHERE is_active = TRUE
    LOOP
        -- Get opening balance (previous day's closing)
        SELECT closing_balance INTO v_opening_balance
        FROM daily_balance_snapshots 
        WHERE account_id = v_account.account_id 
          AND snapshot_date = p_snapshot_date - INTERVAL '1 day';
        
        -- If no previous snapshot, calculate from beginning
        IF v_opening_balance IS NULL THEN
            v_opening_balance := get_account_balance(v_account.account_id, p_snapshot_date - INTERVAL '1 day');
        END IF;
        
        -- Get closing balance
        v_closing_balance := get_account_balance(v_account.account_id, p_snapshot_date);
        
        -- Get daily activity
        SELECT 
            COALESCE(SUM(jel.debit_amount), 0),
            COALESCE(SUM(jel.credit_amount), 0),
            COUNT(*)
        INTO v_total_debits, v_total_credits, v_transaction_count
        FROM journal_entry_lines jel
        JOIN journal_entries je ON jel.entry_id = je.entry_id
        WHERE jel.account_id = v_account.account_id
          AND je.entry_date = p_snapshot_date
          AND je.is_posted = TRUE;
        
        -- Insert snapshot
        INSERT INTO daily_balance_snapshots (
            snapshot_date,
            account_id,
            opening_balance,
            closing_balance,
            total_debits,
            total_credits,
            transaction_count
        ) VALUES (
            p_snapshot_date,
            v_account.account_id,
            v_opening_balance,
            v_closing_balance,
            v_total_debits,
            v_total_credits,
            v_transaction_count
        );
        
        v_accounts_processed := v_accounts_processed + 1;
    END LOOP;
    
    RETURN QUERY SELECT 
        v_accounts_processed,
        EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - v_start_time))::INTEGER * 1000;
END;
$$ LANGUAGE plpgsql;