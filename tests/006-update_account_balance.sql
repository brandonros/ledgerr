-- Unit test for update_account_balance function (happy path)
BEGIN;

-- Set transaction isolation level to SERIALIZABLE for the test
SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;

SAVEPOINT before_test;

DO $$
DECLARE
    v_test_account_id UUID;
    v_update_result RECORD;
    v_balance_record RECORD;
BEGIN
    RAISE NOTICE 'Starting test: update_account_balance happy path';
    
    -- Setup: Create test account
    INSERT INTO ledgerr.accounts (account_code, account_name, account_type, is_active)
    VALUES ('UPD001', 'Test Account for Balance Update', 'ASSET', TRUE)
    ON CONFLICT (account_code) DO UPDATE SET account_name = EXCLUDED.account_name
    RETURNING account_id INTO v_test_account_id;
    
    IF v_test_account_id IS NULL THEN
        SELECT account_id INTO v_test_account_id FROM ledgerr.accounts WHERE account_code = 'UPD001';
    END IF;
    
    -- Setup: Initialize the account balance
    PERFORM ledgerr.initialize_account_balance(v_test_account_id);
    
    -- Test 1: Credit update (increase balance)
    SELECT * INTO v_update_result
    FROM ledgerr.update_account_balance(v_test_account_id, 0.00, 1000.00);
    
    IF NOT v_update_result.success THEN
        RAISE EXCEPTION 'TEST FAILED: Credit update should succeed, error: %', v_update_result.error_message;
    END IF;
    
    IF v_update_result.new_balance != 1000.00 THEN
        RAISE EXCEPTION 'TEST FAILED: Balance should be 1000.00 after credit, got %', v_update_result.new_balance;
    END IF;
    
    IF v_update_result.new_version != 2 THEN
        RAISE EXCEPTION 'TEST FAILED: Version should be 2 after first update, got %', v_update_result.new_version;
    END IF;
    
    -- Test 2: Debit update (decrease balance)
    SELECT * INTO v_update_result
    FROM ledgerr.update_account_balance(v_test_account_id, 300.00, 0.00, 2);
    
    IF NOT v_update_result.success THEN
        RAISE EXCEPTION 'TEST FAILED: Debit update should succeed, error: %', v_update_result.error_message;
    END IF;
    
    IF v_update_result.new_balance != 700.00 THEN
        RAISE EXCEPTION 'TEST FAILED: Balance should be 700.00 after debit, got %', v_update_result.new_balance;
    END IF;
    
    -- Test 3: Verify optimistic locking works
    SELECT * INTO v_update_result
    FROM ledgerr.update_account_balance(v_test_account_id, 0.00, 100.00, 2); -- Wrong version
    
    IF v_update_result.success THEN
        RAISE EXCEPTION 'TEST FAILED: Update with wrong version should fail';
    END IF;
    
    IF v_update_result.error_message NOT LIKE '%Version mismatch%' THEN
        RAISE EXCEPTION 'TEST FAILED: Should get version mismatch error, got: %', v_update_result.error_message;
    END IF;
    
    -- Test 4: Update without version check
    SELECT * INTO v_update_result
    FROM ledgerr.update_account_balance(v_test_account_id, 0.00, 200.00);
    
    IF NOT v_update_result.success THEN
        RAISE EXCEPTION 'TEST FAILED: Update without version should succeed, error: %', v_update_result.error_message;
    END IF;
    
    IF v_update_result.new_balance != 900.00 THEN
        RAISE EXCEPTION 'TEST FAILED: Balance should be 900.00, got %', v_update_result.new_balance;
    END IF;
    
    -- Test 5: Verify daily totals are tracked
    SELECT * INTO v_balance_record
    FROM ledgerr.account_balances
    WHERE account_id = v_test_account_id;
    
    IF v_balance_record.daily_credit_total < 1200.00 THEN -- 1000 + 200
        RAISE EXCEPTION 'TEST FAILED: Daily credit total should be at least 1200.00, got %', v_balance_record.daily_credit_total;
    END IF;
    
    IF v_balance_record.daily_debit_total < 300.00 THEN
        RAISE EXCEPTION 'TEST FAILED: Daily debit total should be at least 300.00, got %', v_balance_record.daily_debit_total;
    END IF;
    
    -- Test 6: Verify available balance is calculated
    IF v_balance_record.available_balance != (v_balance_record.current_balance - v_balance_record.pending_debits) THEN
        RAISE EXCEPTION 'TEST FAILED: Available balance calculation incorrect';
    END IF;
    
    RAISE NOTICE '✓ TEST PASSED: update_account_balance happy path - Final balance: %', v_update_result.new_balance;
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE '✗ TEST FAILED: %', SQLERRM;
        RAISE;
END;
$$;

ROLLBACK TO SAVEPOINT before_test;

COMMIT;
