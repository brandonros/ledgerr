-- Test setup function
CREATE OR REPLACE FUNCTION ledgerr.setup_test_data()
RETURNS void AS $$
DECLARE
    v_asset_gl_id UUID;
    v_liability_gl_id UUID;
    v_partner1_id UUID := '11111111-1111-1111-1111-111111111111';
    v_partner2_id UUID := '22222222-2222-2222-2222-222222222222';
BEGIN
    -- Clean up any existing test data
    DELETE FROM ledgerr.payment_account_transactions WHERE partner_id IN (v_partner1_id, v_partner2_id);
    DELETE FROM ledgerr.payment_accounts WHERE partner_id IN (v_partner1_id, v_partner2_id);
    DELETE FROM ledgerr.journal_entry_lines WHERE entry_date = CURRENT_DATE;
    DELETE FROM ledgerr.journal_entries WHERE entry_date = CURRENT_DATE;
    DELETE FROM ledgerr.gl_accounts WHERE account_code IN ('TEST_ASSET', 'TEST_LIABILITY');
    
    -- Create test GL accounts
    INSERT INTO ledgerr.gl_accounts (account_code, account_name, account_type)
    VALUES ('TEST_ASSET', 'Test Customer Asset Account', 'ASSET')
    RETURNING gl_account_id INTO v_asset_gl_id;
    
    INSERT INTO ledgerr.gl_accounts (account_code, account_name, account_type)  
    VALUES ('TEST_LIABILITY', 'Test Customer Liability Account', 'LIABILITY')
    RETURNING gl_account_id INTO v_liability_gl_id;
    
    -- Create test payment accounts
    INSERT INTO ledgerr.payment_accounts (
        partner_id, external_account_id, account_holder_name, 
        account_type, gl_account_id, current_balance
    ) VALUES 
    (v_partner1_id, 'EXT_ACC_001', 'Test User 1', 'CHECKING', v_asset_gl_id, 1000.00),
    (v_partner2_id, 'EXT_ACC_002', 'Test User 2', 'SAVINGS', v_liability_gl_id, 500.00);
    
    RAISE NOTICE 'Test data setup complete';
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- TEST 1: Basic Account Transfer (Happy Path)
-- ============================================================================
CREATE OR REPLACE FUNCTION ledgerr.test_basic_transfer()
RETURNS void AS $$
DECLARE
    v_partner1_id UUID := '11111111-1111-1111-1111-111111111111';
    v_partner2_id UUID := '22222222-2222-2222-2222-222222222222';
    v_account1_id UUID;
    v_account2_id UUID;
    v_entry_id UUID;
    v_balance1 DECIMAL(15,2);
    v_balance2 DECIMAL(15,2);
    v_transaction_count INTEGER;
    v_journal_count INTEGER;
BEGIN
    RAISE NOTICE 'Starting TEST 1: Basic Transfer';
    
    -- Get account IDs
    SELECT payment_account_id INTO v_account1_id 
    FROM ledgerr.payment_accounts WHERE partner_id = v_partner1_id;
    
    SELECT payment_account_id INTO v_account2_id
    FROM ledgerr.payment_accounts WHERE partner_id = v_partner2_id;
    
    -- Execute transfer: $100 from account1 to account2
    BEGIN
        SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
        
        v_entry_id := ledgerr.process_payment_transaction(
            v_partner1_id, v_account1_id,
            v_partner2_id, v_account2_id, 
            100.00,
            'Test transfer between accounts',
            'TEST_REF_001'
        );
        
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            RAISE EXCEPTION 'Transfer failed: %', SQLERRM;
    END;
    
    -- Verify balances
    SELECT current_balance INTO v_balance1 
    FROM ledgerr.payment_accounts WHERE partner_id = v_partner1_id;
    
    SELECT current_balance INTO v_balance2
    FROM ledgerr.payment_accounts WHERE partner_id = v_partner2_id;
    
    -- Assertions
    IF v_balance1 != 900.00 THEN
        RAISE EXCEPTION 'TEST 1 FAILED: Account 1 balance should be 900.00, got %', v_balance1;
    END IF;
    
    IF v_balance2 != 600.00 THEN
        RAISE EXCEPTION 'TEST 1 FAILED: Account 2 balance should be 600.00, got %', v_balance2;
    END IF;
    
    -- Verify transaction records
    SELECT COUNT(*) INTO v_transaction_count
    FROM ledgerr.payment_account_transactions
    WHERE partner_id IN (v_partner1_id, v_partner2_id)
      AND external_reference = 'TEST_REF_001';
    
    IF v_transaction_count != 2 THEN
        RAISE EXCEPTION 'TEST 1 FAILED: Should have 2 transaction records, got %', v_transaction_count;
    END IF;
    
    -- Verify journal entries (double-entry)
    SELECT COUNT(*) INTO v_journal_count
    FROM ledgerr.journal_entry_lines
    WHERE entry_id = v_entry_id;
    
    IF v_journal_count != 2 THEN
        RAISE EXCEPTION 'TEST 1 FAILED: Should have 2 journal lines, got %', v_journal_count;
    END IF;
    
    RAISE NOTICE 'TEST 1 PASSED: Basic transfer completed successfully';
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- TEST 2: Insufficient Funds (Error Case)
-- ============================================================================
CREATE OR REPLACE FUNCTION ledgerr.test_insufficient_funds()
RETURNS void AS $$
DECLARE
    v_partner1_id UUID := '11111111-1111-1111-1111-111111111111';
    v_partner2_id UUID := '22222222-2222-2222-2222-222222222222';
    v_account1_id UUID;
    v_account2_id UUID;
    v_entry_id UUID;
    v_balance1_before DECIMAL(15,2);
    v_balance1_after DECIMAL(15,2);
    v_error_occurred BOOLEAN := FALSE;
BEGIN
    RAISE NOTICE 'Starting TEST 2: Insufficient Funds';
    
    -- Get account IDs and initial balance
    SELECT payment_account_id, current_balance INTO v_account1_id, v_balance1_before
    FROM ledgerr.payment_accounts WHERE partner_id = v_partner1_id;
    
    SELECT payment_account_id INTO v_account2_id
    FROM ledgerr.payment_accounts WHERE partner_id = v_partner2_id;
    
    -- Try to transfer more than available balance
    BEGIN
        SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
        
        v_entry_id := ledgerr.process_payment_transaction(
            v_partner1_id, v_account1_id,
            v_partner2_id, v_account2_id,
            2000.00, -- More than the 900.00 balance from previous test
            'Test insufficient funds',
            'TEST_REF_002'
        );
        
        COMMIT;
        
        -- If we get here, the test failed
        RAISE EXCEPTION 'TEST 2 FAILED: Transaction should have been rejected due to insufficient funds';
        
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            IF SQLERRM LIKE '%Insufficient funds%' THEN
                v_error_occurred := TRUE;
                RAISE NOTICE 'Expected insufficient funds error caught: %', SQLERRM;
            ELSE
                RAISE EXCEPTION 'TEST 2 FAILED: Unexpected error: %', SQLERRM;
            END IF;
    END;
    
    -- Verify balance unchanged
    SELECT current_balance INTO v_balance1_after
    FROM ledgerr.payment_accounts WHERE partner_id = v_partner1_id;
    
    IF v_balance1_after != v_balance1_before THEN
        RAISE EXCEPTION 'TEST 2 FAILED: Balance should be unchanged after failed transaction. Before: %, After: %', 
                       v_balance1_before, v_balance1_after;
    END IF;
    
    IF NOT v_error_occurred THEN
        RAISE EXCEPTION 'TEST 2 FAILED: Expected insufficient funds error did not occur';
    END IF;
    
    RAISE NOTICE 'TEST 2 PASSED: Insufficient funds properly rejected';
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- TEST 3: Concurrent Transaction Handling
-- ============================================================================
CREATE OR REPLACE FUNCTION ledgerr.test_concurrent_transactions()
RETURNS void AS $$
DECLARE
    v_partner1_id UUID := '11111111-1111-1111-1111-111111111111';
    v_partner2_id UUID := '22222222-2222-2222-2222-222222222222';
    v_account1_id UUID;
    v_account2_id UUID;
    v_initial_balance DECIMAL(15,2);
    v_final_balance DECIMAL(15,2);
    v_expected_balance DECIMAL(15,2);
    v_transaction_count INTEGER;
BEGIN
    RAISE NOTICE 'Starting TEST 3: Concurrent Transaction Handling';
    
    -- Get account info
    SELECT payment_account_id, current_balance INTO v_account1_id, v_initial_balance
    FROM ledgerr.payment_accounts WHERE partner_id = v_partner1_id;
    
    SELECT payment_account_id INTO v_account2_id
    FROM ledgerr.payment_accounts WHERE partner_id = v_partner2_id;
    
    -- Simulate multiple small transfers (this would normally be done in separate connections)
    -- In production, you'd test this with multiple database connections
    BEGIN
        SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
        
        -- Transfer 1: $50
        PERFORM ledgerr.process_payment_transaction(
            v_partner1_id, v_account1_id,
            v_partner2_id, v_account2_id,
            50.00,
            'Concurrent test transfer 1',
            'CONCURRENT_001'
        );
        
        -- Transfer 2: $25  
        PERFORM ledgerr.process_payment_transaction(
            v_partner1_id, v_account1_id,
            v_partner2_id, v_account2_id,
            25.00,
            'Concurrent test transfer 2', 
            'CONCURRENT_002'
        );
        
        -- Transfer 3: $10
        PERFORM ledgerr.process_payment_transaction(
            v_partner1_id, v_account1_id,
            v_partner2_id, v_account2_id,
            10.00,
            'Concurrent test transfer 3',
            'CONCURRENT_003'
        );
        
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            RAISE EXCEPTION 'TEST 3 FAILED: Concurrent transfers failed: %', SQLERRM;
    END;
    
    -- Verify final balance
    SELECT current_balance INTO v_final_balance
    FROM ledgerr.payment_accounts WHERE partner_id = v_partner1_id;
    
    v_expected_balance := v_initial_balance - 85.00; -- 50 + 25 + 10
    
    IF v_final_balance != v_expected_balance THEN
        RAISE EXCEPTION 'TEST 3 FAILED: Final balance should be %, got %', 
                       v_expected_balance, v_final_balance;
    END IF;
    
    -- Verify all transactions were recorded
    SELECT COUNT(*) INTO v_transaction_count
    FROM ledgerr.payment_account_transactions
    WHERE partner_id = v_partner1_id
      AND external_reference LIKE 'CONCURRENT_%';
    
    IF v_transaction_count != 3 THEN
        RAISE EXCEPTION 'TEST 3 FAILED: Should have 3 transaction records, got %', v_transaction_count;
    END IF;
    
    RAISE NOTICE 'TEST 3 PASSED: Concurrent transactions handled correctly';
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- TEST RUNNER
-- ============================================================================
CREATE OR REPLACE FUNCTION ledgerr.run_all_tests()
RETURNS void AS $$
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE 'RUNNING LEDGER UNIT TESTS';
    RAISE NOTICE '========================================';
    
    -- Setup test data
    PERFORM ledgerr.setup_test_data();
    
    -- Run tests
    PERFORM ledgerr.test_basic_transfer();
    PERFORM ledgerr.test_insufficient_funds();
    PERFORM ledgerr.test_concurrent_transactions();
    
    RAISE NOTICE '========================================';
    RAISE NOTICE 'ALL TESTS PASSED!';
    RAISE NOTICE '========================================';
    
EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'TEST SUITE FAILED: %', SQLERRM;
END;
$$ LANGUAGE plpgsql;