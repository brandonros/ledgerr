-- Unit test for generate_trial_balance function (happy path)
BEGIN;

-- Set transaction isolation level to SERIALIZABLE for the test
SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;

SAVEPOINT before_test;

DO $$
DECLARE
    v_asset_account_id INTEGER;
    v_liability_account_id INTEGER;
    v_entry_id INTEGER;
    v_trial_balance_count INTEGER;
    v_journal_lines JSONB;
    v_trial_record RECORD;
BEGIN
    RAISE NOTICE 'Starting test: generate_trial_balance happy path';
    
    -- Setup: Create test accounts
    INSERT INTO ledgerr.accounts (account_code, account_name, account_type, is_active)
    VALUES 
        ('TB001', 'Test Asset for Trial', 'ASSET', TRUE),
        ('TB002', 'Test Liability for Trial', 'LIABILITY', TRUE)
    ON CONFLICT (account_code) DO UPDATE SET account_name = EXCLUDED.account_name;
    
    SELECT account_id INTO v_asset_account_id FROM ledgerr.accounts WHERE account_code = 'TB001';
    SELECT account_id INTO v_liability_account_id FROM ledgerr.accounts WHERE account_code = 'TB002';
    
    -- Setup: Create balanced transaction
    v_journal_lines := jsonb_build_array(
        jsonb_build_object('account_id', v_asset_account_id, 'debit_amount', 2000.00, 'description', 'Asset increase'),
        jsonb_build_object('account_id', v_liability_account_id, 'credit_amount', 2000.00, 'description', 'Liability increase')
    );
    
    SELECT ledgerr.record_journal_entry(
        CURRENT_DATE, 'Trial balance test transaction', v_journal_lines, 'TB-TEST-001', 'test_user'
    ) INTO v_entry_id;
    
    -- Test 1: Trial balance should include our test accounts
    SELECT COUNT(*) INTO v_trial_balance_count
    FROM ledgerr.generate_trial_balance() 
    WHERE account_code IN ('TB001', 'TB002');
    
    IF v_trial_balance_count != 2 THEN
        RAISE EXCEPTION 'TEST FAILED: Expected 2 accounts in trial balance, got %', v_trial_balance_count;
    END IF;
    
    -- Test 2: Check asset account balance
    SELECT * INTO v_trial_record
    FROM ledgerr.generate_trial_balance()
    WHERE account_code = 'TB001';
    
    IF v_trial_record.balance != 2000.00 THEN
        RAISE EXCEPTION 'TEST FAILED: Asset balance should be 2000.00, got %', v_trial_record.balance;
    END IF;
    
    IF v_trial_record.account_type != 'ASSET' THEN
        RAISE EXCEPTION 'TEST FAILED: Account type should be ASSET, got %', v_trial_record.account_type;
    END IF;
    
    -- Test 3: Check liability account balance
    SELECT * INTO v_trial_record
    FROM ledgerr.generate_trial_balance()
    WHERE account_code = 'TB002';
    
    IF v_trial_record.balance != 2000.00 THEN
        RAISE EXCEPTION 'TEST FAILED: Liability balance should be 2000.00, got %', v_trial_record.balance;
    END IF;
    
    -- Test 4: Test with historical date
    SELECT COUNT(*) INTO v_trial_balance_count
    FROM ledgerr.generate_trial_balance(CURRENT_DATE - INTERVAL '1 day')
    WHERE account_code IN ('TB001', 'TB002') AND balance != 0;
    
    IF v_trial_balance_count != 0 THEN
        RAISE EXCEPTION 'TEST FAILED: Historical trial balance should show 0 balances, got % non-zero', v_trial_balance_count;
    END IF;
    
    RAISE NOTICE '✓ TEST PASSED: generate_trial_balance happy path';
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE '✗ TEST FAILED: %', SQLERRM;
        RAISE;
END;
$$;

ROLLBACK TO SAVEPOINT before_test;

COMMIT;

