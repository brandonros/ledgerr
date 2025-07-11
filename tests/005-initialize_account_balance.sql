-- Unit test for initialize_account_balance function (happy path)
BEGIN;

-- Set transaction isolation level to SERIALIZABLE for the test
SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;

SAVEPOINT before_test;

DO $$
DECLARE
    v_test_account_id UUID;
    v_balance_record RECORD;
BEGIN
    RAISE NOTICE 'Starting test: initialize_account_balance happy path';
    
    -- Setup: Create test account
    INSERT INTO ledgerr.accounts (account_code, account_name, account_type, is_active)
    VALUES ('INIT001', 'Test Account for Balance Init', 'ASSET', TRUE)
    ON CONFLICT (account_code) DO UPDATE SET account_name = EXCLUDED.account_name
    RETURNING account_id INTO v_test_account_id;
    
    IF v_test_account_id IS NULL THEN
        SELECT account_id INTO v_test_account_id FROM ledgerr.accounts WHERE account_code = 'INIT001';
    END IF;
    
    -- Test 1: Initialize balance for new account
    PERFORM ledgerr.initialize_account_balance(v_test_account_id);
    
    -- Verify balance record was created
    SELECT * INTO v_balance_record
    FROM ledgerr.account_balances
    WHERE account_id = v_test_account_id;
    
    IF v_balance_record.account_id IS NULL THEN
        RAISE EXCEPTION 'TEST FAILED: Balance record should be created for account %', v_test_account_id;
    END IF;
    
    -- Test 2: Verify initial values
    IF v_balance_record.current_balance != 0.00 THEN
        RAISE EXCEPTION 'TEST FAILED: Initial current_balance should be 0.00, got %', v_balance_record.current_balance;
    END IF;
    
    IF v_balance_record.available_balance != 0.00 THEN
        RAISE EXCEPTION 'TEST FAILED: Initial available_balance should be 0.00, got %', v_balance_record.available_balance;
    END IF;
    
    IF v_balance_record.version != 1 THEN
        RAISE EXCEPTION 'TEST FAILED: Initial version should be 1, got %', v_balance_record.version;
    END IF;
    
    -- Test 3: Test idempotency (calling again should not create duplicate)
    PERFORM ledgerr.initialize_account_balance(v_test_account_id);
    
    -- Should still only be one record
    IF (SELECT COUNT(*) FROM ledgerr.account_balances WHERE account_id = v_test_account_id) != 1 THEN
        RAISE EXCEPTION 'TEST FAILED: Should have exactly one balance record, found %', 
                       (SELECT COUNT(*) FROM ledgerr.account_balances WHERE account_id = v_test_account_id);
    END IF;
    
    -- Test 4: Verify timestamps
    IF v_balance_record.last_updated IS NULL THEN
        RAISE EXCEPTION 'TEST FAILED: last_updated should not be NULL';
    END IF;
    
    IF v_balance_record.last_daily_reset != CURRENT_DATE THEN
        RAISE EXCEPTION 'TEST FAILED: last_daily_reset should be current date, got %', v_balance_record.last_daily_reset;
    END IF;
    
    RAISE NOTICE '✓ TEST PASSED: initialize_account_balance happy path - Account ID: %', v_test_account_id;
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE '✗ TEST FAILED: %', SQLERRM;
        RAISE;
END;
$$;

ROLLBACK TO SAVEPOINT before_test;

COMMIT;

