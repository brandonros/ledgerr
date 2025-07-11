-- Unit test for get_account_balance function (happy path)
BEGIN;

-- Set transaction isolation level to SERIALIZABLE for the test
SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;

SAVEPOINT before_test;

DO $$
DECLARE
    v_asset_account_id INTEGER;
    v_cash_account_id INTEGER;
    v_entry_id INTEGER;
    v_balance DECIMAL(15,2);
    v_journal_lines JSONB;
    debug_rec RECORD;
BEGIN    
    RAISE NOTICE 'Starting test: get_account_balance happy path';
    
    -- Setup: Create test accounts separately
    INSERT INTO ledgerr.accounts (account_code, account_name, account_type, is_active)
    VALUES ('TEST001', 'Test Asset Account', 'ASSET', TRUE)
    ON CONFLICT (account_code) DO UPDATE SET account_name = EXCLUDED.account_name
    RETURNING account_id INTO v_asset_account_id;
    
    INSERT INTO ledgerr.accounts (account_code, account_name, account_type, is_active)
    VALUES ('TEST002', 'Test Cash Account', 'ASSET', TRUE)
    ON CONFLICT (account_code) DO UPDATE SET account_name = EXCLUDED.account_name
    RETURNING account_id INTO v_cash_account_id;
    
    RAISE NOTICE 'Asset account ID: %, Cash account ID: %', v_asset_account_id, v_cash_account_id;
    
    -- Test 1: Balance should be 0 for new account
    v_balance := ledgerr.get_account_balance(v_asset_account_id);
    RAISE NOTICE 'Initial balance: %', v_balance;
    IF v_balance != 0.00 THEN
        RAISE EXCEPTION 'TEST FAILED: New account balance should be 0, got %', v_balance;
    END IF;
    
    -- Setup: Add some transactions
    v_journal_lines := jsonb_build_array(
        jsonb_build_object('account_id', v_asset_account_id, 'debit_amount', 1000.00, 'description', 'Initial deposit'),
        jsonb_build_object('account_id', v_cash_account_id, 'credit_amount', 1000.00, 'description', 'Cash source')
    );
    
    RAISE NOTICE 'Journal lines: %', v_journal_lines;
    
    SELECT ledgerr.record_journal_entry(
        CURRENT_DATE, 'Test transaction', v_journal_lines, 'TEST-BAL-001', 'test_user'
    ) INTO v_entry_id;
    
    RAISE NOTICE 'Created entry_id: %', v_entry_id;
    
    -- DEBUG: Check what journal lines were actually created
    FOR debug_rec IN 
        SELECT jel.account_id, jel.debit_amount, jel.credit_amount, jel.description,
               je.entry_date, je.is_posted
        FROM ledgerr.journal_entry_lines jel
        JOIN ledgerr.journal_entries je ON jel.entry_id = je.entry_id
        WHERE jel.entry_id = v_entry_id
    LOOP
        RAISE NOTICE 'Line: account_id=%, debit=%, credit=%, desc=%, date=%, posted=%', 
                     debug_rec.account_id, debug_rec.debit_amount, debug_rec.credit_amount, 
                     debug_rec.description, debug_rec.entry_date, debug_rec.is_posted;
    END LOOP;
    
    -- DEBUG: Check account type
    SELECT account_type INTO debug_rec 
    FROM ledgerr.accounts 
    WHERE account_id = v_asset_account_id;
    RAISE NOTICE 'Asset account type: %', debug_rec.account_type;
    
    -- Test 2: Balance should reflect transaction
    v_balance := ledgerr.get_account_balance(v_asset_account_id);
    RAISE NOTICE 'Balance after transaction: %', v_balance;
    
    -- DEBUG: Manual balance calculation
    SELECT 
        COALESCE(SUM(debit_amount - credit_amount), 0) as manual_balance
    INTO debug_rec
    FROM ledgerr.journal_entry_lines jel
    JOIN ledgerr.journal_entries je ON jel.entry_id = je.entry_id
    WHERE jel.account_id = v_asset_account_id
      AND je.entry_date <= CURRENT_DATE
      AND je.is_posted = TRUE;
    
    RAISE NOTICE 'Manual balance calculation: %', debug_rec.manual_balance;
    
    IF v_balance != 1000.00 THEN
        RAISE EXCEPTION 'TEST FAILED: Asset balance should be 1000.00, got %', v_balance;
    END IF;
    
    -- Test 3: Test with historical date (should be 0 before transaction)
    v_balance := ledgerr.get_account_balance(v_asset_account_id, CURRENT_DATE - INTERVAL '1 day');
    IF v_balance != 0.00 THEN
        RAISE EXCEPTION 'TEST FAILED: Historical balance should be 0, got %', v_balance;
    END IF;
    
    -- Test 4: Test caching (call twice, should return same result)
    v_balance := ledgerr.get_account_balance(v_asset_account_id, CURRENT_DATE, TRUE);
    IF v_balance != 1000.00 THEN
        RAISE EXCEPTION 'TEST FAILED: Cached balance should be 1000.00, got %', v_balance;
    END IF;
    
    RAISE NOTICE '✓ TEST PASSED: get_account_balance happy path';    
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE '✗ TEST FAILED: %', SQLERRM;
        RAISE;
END;
$$;

ROLLBACK TO SAVEPOINT before_test;

COMMIT;