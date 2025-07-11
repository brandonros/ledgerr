-- Unit test for get_account_balance function (happy path)
DO $$
DECLARE
    v_asset_account_id INTEGER;
    v_cash_account_id INTEGER;
    v_entry_id INTEGER;
    v_balance DECIMAL(15,2);
    v_journal_lines JSONB;
BEGIN
    -- Setup savepoint for cleanup
    SAVEPOINT test_start;
    
    RAISE NOTICE 'Starting test: get_account_balance happy path';
    
    -- Setup: Create test accounts
    INSERT INTO ledgerr.accounts (account_code, account_name, account_type, is_active)
    VALUES 
        ('TEST001', 'Test Asset Account', 'ASSET', TRUE),
        ('TEST002', 'Test Cash Account', 'ASSET', TRUE)
    ON CONFLICT (account_code) DO UPDATE SET account_name = EXCLUDED.account_name
    RETURNING account_id INTO v_asset_account_id;
    
    SELECT account_id INTO v_cash_account_id FROM ledgerr.accounts WHERE account_code = 'TEST002';
    IF v_asset_account_id IS NULL THEN
        SELECT account_id INTO v_asset_account_id FROM ledgerr.accounts WHERE account_code = 'TEST001';
    END IF;
    
    -- Test 1: Balance should be 0 for new account
    v_balance := ledgerr.get_account_balance(v_asset_account_id);
    IF v_balance != 0.00 THEN
        RAISE EXCEPTION 'TEST FAILED: New account balance should be 0, got %', v_balance;
    END IF;
    
    -- Setup: Add some transactions
    v_journal_lines := jsonb_build_array(
        jsonb_build_object('account_id', v_asset_account_id, 'debit_amount', 1000.00, 'description', 'Initial deposit'),
        jsonb_build_object('account_id', v_cash_account_id, 'credit_amount', 1000.00, 'description', 'Cash source')
    );
    
    SELECT ledgerr.record_journal_entry(
        CURRENT_DATE, 'Test transaction', v_journal_lines, 'TEST-BAL-001', 'test_user'
    ) INTO v_entry_id;
    
    -- Test 2: Balance should reflect transaction
    v_balance := ledgerr.get_account_balance(v_asset_account_id);
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
    
    -- Cleanup
    ROLLBACK TO SAVEPOINT test_start;
    
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE '✗ TEST FAILED: %', SQLERRM;
        ROLLBACK TO SAVEPOINT test_start;
        RAISE;
END;
$$;