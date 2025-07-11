-- Unit test for create_daily_balance_snapshot function
BEGIN;

-- Set transaction isolation level to SERIALIZABLE for the test
SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;

SAVEPOINT before_test;

DO $$
DECLARE
    v_account_id_1 INTEGER;
    v_account_id_2 INTEGER;
    v_test_date DATE := '2025-07-08'::DATE;
    v_previous_date DATE := '2025-07-07'::DATE;
    v_result RECORD;
    v_snapshot_count INTEGER;
    v_journal_lines JSONB;
    v_entry_id INTEGER;
BEGIN
    RAISE NOTICE 'Starting test: create_daily_balance_snapshot';
    
    -- Setup: Create test accounts
    INSERT INTO ledgerr.accounts (account_code, account_name, account_type, is_active)
    VALUES ('SNAP001', 'Test Account 1', 'ASSET', TRUE)
    ON CONFLICT (account_code) DO UPDATE SET account_name = EXCLUDED.account_name
    RETURNING account_id INTO v_account_id_1;
    
    INSERT INTO ledgerr.accounts (account_code, account_name, account_type, is_active)
    VALUES ('SNAP002', 'Test Account 2', 'LIABILITY', TRUE)
    ON CONFLICT (account_code) DO UPDATE SET account_name = EXCLUDED.account_name
    RETURNING account_id INTO v_account_id_2;
    
    -- Setup: Create previous day's snapshot to test opening balance calculation
    INSERT INTO ledgerr.daily_balance_snapshots (
        snapshot_date,
        account_id,
        opening_balance,
        closing_balance,
        total_debits,
        total_credits,
        transaction_count
    ) VALUES (
        v_previous_date,
        v_account_id_1,
        0.00,
        1500.00,
        2000.00,
        500.00,
        5
    );
    
    -- Setup: Create some journal entries for the test date
    v_journal_lines := jsonb_build_array(
        jsonb_build_object('account_id', v_account_id_1, 'debit_amount', 1000.00, 'description', 'Test debit 1'),
        jsonb_build_object('account_id', v_account_id_2, 'credit_amount', 1000.00, 'description', 'Test credit 1')
    );
    
    SELECT ledgerr.record_journal_entry(
        v_test_date, 'Test entry 1', v_journal_lines, 'SNAP-001', 'test_setup'
    ) INTO v_entry_id;
    
    v_journal_lines := jsonb_build_array(
        jsonb_build_object('account_id', v_account_id_1, 'credit_amount', 300.00, 'description', 'Test credit 2'),
        jsonb_build_object('account_id', v_account_id_2, 'debit_amount', 300.00, 'description', 'Test debit 2')
    );
    
    SELECT ledgerr.record_journal_entry(
        v_test_date, 'Test entry 2', v_journal_lines, 'SNAP-002', 'test_setup'
    ) INTO v_entry_id;
    
    -- Test 1: Create snapshot for test date
    SELECT * INTO v_result
    FROM ledgerr.create_daily_balance_snapshot(v_test_date);
    
    IF v_result.accounts_processed < 2 THEN
        RAISE EXCEPTION 'TEST FAILED: Should process at least 2 accounts, got %', v_result.accounts_processed;
    END IF;
    
    IF v_result.total_time_ms IS NULL OR v_result.total_time_ms < 0 THEN
        RAISE EXCEPTION 'TEST FAILED: Should return valid execution time, got %', v_result.total_time_ms;
    END IF;
    
    -- Test 2: Verify snapshots were created
    SELECT COUNT(*) INTO v_snapshot_count
    FROM ledgerr.daily_balance_snapshots
    WHERE snapshot_date = v_test_date;
    
    IF v_snapshot_count < 2 THEN
        RAISE EXCEPTION 'TEST FAILED: Should create at least 2 snapshots, got %', v_snapshot_count;
    END IF;
    
    -- Test 3: Verify snapshot data for account 1
    IF NOT EXISTS (
        SELECT 1 FROM ledgerr.daily_balance_snapshots
        WHERE snapshot_date = v_test_date
          AND account_id = v_account_id_1
          AND opening_balance = 1500.00  -- Previous day's closing balance
          AND total_debits = 1000.00     -- From our test entries
          AND total_credits = 300.00     -- From our test entries
          AND transaction_count = 2      -- Two journal entries
    ) THEN
        RAISE EXCEPTION 'TEST FAILED: Account 1 snapshot data is incorrect';
    END IF;
    
    -- Test 4: Verify snapshot data for account 2
    IF NOT EXISTS (
        SELECT 1 FROM ledgerr.daily_balance_snapshots
        WHERE snapshot_date = v_test_date
          AND account_id = v_account_id_2
          AND opening_balance = 0.00     -- No previous snapshot
          AND total_debits = 300.00      -- From our test entries
          AND total_credits = 1000.00    -- From our test entries
          AND transaction_count = 2      -- Two journal entries
    ) THEN
        RAISE EXCEPTION 'TEST FAILED: Account 2 snapshot data is incorrect';
    END IF;
    
    -- Test 5: Test idempotency (running again should return 0 processed)
    SELECT * INTO v_result
    FROM ledgerr.create_daily_balance_snapshot(v_test_date);
    
    IF v_result.accounts_processed != 0 THEN
        RAISE EXCEPTION 'TEST FAILED: Second run should process 0 accounts (idempotent), got %', v_result.accounts_processed;
    END IF;
    
    IF v_result.total_time_ms != 0 THEN
        RAISE EXCEPTION 'TEST FAILED: Second run should return 0 time (idempotent), got %', v_result.total_time_ms;
    END IF;
    
    -- Test 6: Test with default parameter (yesterday)
    DELETE FROM ledgerr.daily_balance_snapshots WHERE snapshot_date = CURRENT_DATE - INTERVAL '1 day';
    
    SELECT * INTO v_result
    FROM ledgerr.create_daily_balance_snapshot(); -- No parameter = yesterday
    
    IF v_result.accounts_processed IS NULL THEN
        RAISE EXCEPTION 'TEST FAILED: Default parameter test should return valid result';
    END IF;
    
    -- Test 7: Test with inactive account
    UPDATE ledgerr.accounts SET is_active = FALSE WHERE account_id = v_account_id_2;
    
    -- Clean up snapshots and test again
    DELETE FROM ledgerr.daily_balance_snapshots WHERE snapshot_date = v_test_date;
    
    SELECT * INTO v_result
    FROM ledgerr.create_daily_balance_snapshot(v_test_date);
    
    -- Should only process active accounts
    IF NOT EXISTS (
        SELECT 1 FROM ledgerr.daily_balance_snapshots
        WHERE snapshot_date = v_test_date AND account_id = v_account_id_1
    ) THEN
        RAISE EXCEPTION 'TEST FAILED: Should create snapshot for active account';
    END IF;
    
    IF EXISTS (
        SELECT 1 FROM ledgerr.daily_balance_snapshots
        WHERE snapshot_date = v_test_date AND account_id = v_account_id_2
    ) THEN
        RAISE EXCEPTION 'TEST FAILED: Should not create snapshot for inactive account';
    END IF;
    
    RAISE NOTICE '✓ TEST PASSED: create_daily_balance_snapshot all tests';
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE '✗ TEST FAILED: %', SQLERRM;
        RAISE;
END;
$$;

ROLLBACK TO SAVEPOINT before_test;

COMMIT;