-- Test setup function
CREATE OR REPLACE FUNCTION ledgerr.setup_test_data()
RETURNS void AS $$
DECLARE
    v_asset_gl_id UUID;
    v_liability_gl_id UUID;
    v_bank_settlement_gl_id UUID;
    v_partner1_id UUID := '11111111-1111-1111-1111-111111111111';
    v_partner2_id UUID := '22222222-2222-2222-2222-222222222222';
    v_bank_partner_id UUID := '99999999-9999-9999-9999-999999999999';
BEGIN
    -- Clean up any existing test data
    DELETE FROM ledgerr.payment_account_transactions WHERE partner_id IN (v_partner1_id, v_partner2_id, v_bank_partner_id);
    DELETE FROM ledgerr.payment_accounts WHERE partner_id IN (v_partner1_id, v_partner2_id, v_bank_partner_id);
    DELETE FROM ledgerr.journal_entry_lines WHERE entry_date = CURRENT_DATE;
    DELETE FROM ledgerr.journal_entries WHERE entry_date = CURRENT_DATE;
    -- Use shorter account codes that fit in VARCHAR(10)
    DELETE FROM ledgerr.gl_accounts WHERE account_code IN ('TST_ASSET', 'TST_LIAB', 'TST_SETTLE');
    
    -- Create test GL accounts with shorter codes
    INSERT INTO ledgerr.gl_accounts (account_code, account_name, account_type)
    VALUES ('TST_ASSET', 'Test Customer Asset Account', 'ASSET')
    RETURNING gl_account_id INTO v_asset_gl_id;
    
    INSERT INTO ledgerr.gl_accounts (account_code, account_name, account_type)  
    VALUES ('TST_LIAB', 'Test Customer Liability Account', 'LIABILITY')
    RETURNING gl_account_id INTO v_liability_gl_id;
    
    INSERT INTO ledgerr.gl_accounts (account_code, account_name, account_type)
    VALUES ('TST_SETTLE', 'Test Bank Settlement Account', 'ASSET')
    RETURNING gl_account_id INTO v_bank_settlement_gl_id;
    
    -- Create test payment accounts (FIXED: Changed SETTLEMENT to MERCHANT)
    INSERT INTO ledgerr.payment_accounts (
        partner_id, external_account_id, account_holder_name, 
        account_type, gl_account_id, current_balance
    ) VALUES 
    (v_partner1_id, 'EXT_ACC_001', 'Test User 1', 'CHECKING', v_asset_gl_id, 1000.00),
    (v_partner2_id, 'EXT_ACC_002', 'Test User 2', 'SAVINGS', v_liability_gl_id, 500.00),
    (v_bank_partner_id, 'BANK_SETTLEMENT', 'Bank Settlement Account', 'MERCHANT', v_bank_settlement_gl_id, 100000.00);
    
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
    v_balance_record RECORD;
BEGIN
    RAISE NOTICE 'Starting TEST 1: Basic Transfer';
    
    -- Get account IDs
    SELECT payment_account_id INTO v_account1_id 
    FROM ledgerr.payment_accounts WHERE partner_id = v_partner1_id;
    
    SELECT payment_account_id INTO v_account2_id
    FROM ledgerr.payment_accounts WHERE partner_id = v_partner2_id;
    
    -- Execute transfer: $100 from account1 to account2 (REMOVED EXPLICIT TRANSACTION MANAGEMENT)
    v_entry_id := ledgerr.execute_transaction(
        v_partner1_id, v_account1_id,
        v_partner2_id, v_account2_id, 
        100.00,
        'TRANSFER',
        'Test transfer between accounts',
        'TEST_REF_001'
    );
    
    -- Verify balances using the balance function
    SELECT current_balance INTO v_balance1
    FROM ledgerr.get_payment_account_balance(v_partner1_id, v_account1_id);
    
    SELECT current_balance INTO v_balance2
    FROM ledgerr.get_payment_account_balance(v_partner2_id, v_account2_id);
    
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
-- TEST 2: Different Transaction Types
-- ============================================================================
CREATE OR REPLACE FUNCTION ledgerr.test_transaction_types()
RETURNS void AS $$
DECLARE
    v_partner1_id UUID := '11111111-1111-1111-1111-111111111111';
    v_bank_partner_id UUID := '99999999-9999-9999-9999-999999999999';
    v_account1_id UUID;
    v_settlement_account_id UUID;
    v_entry_id UUID;
    v_initial_balance DECIMAL(15,2);
    v_final_balance DECIMAL(15,2);
    v_deposit_count INTEGER;
    v_purchase_count INTEGER;
BEGIN
    RAISE NOTICE 'Starting TEST 2: Different Transaction Types';
    
    -- Get account IDs
    SELECT payment_account_id INTO v_account1_id 
    FROM ledgerr.payment_accounts WHERE partner_id = v_partner1_id;
    
    SELECT payment_account_id INTO v_settlement_account_id
    FROM ledgerr.payment_accounts WHERE partner_id = v_bank_partner_id;
    
    -- Get initial balance
    SELECT current_balance INTO v_initial_balance
    FROM ledgerr.get_payment_account_balance(v_partner1_id, v_account1_id);
    
    -- Test DEPOSIT transaction (REMOVED EXPLICIT TRANSACTION MANAGEMENT)
    v_entry_id := ledgerr.execute_transaction(
        v_bank_partner_id, v_settlement_account_id,
        v_partner1_id, v_account1_id,
        200.00,
        'DEPOSIT',
        'ACH deposit from employer',
        'DEPOSIT_001'
    );
    
    -- Test PURCHASE transaction  
    v_entry_id := ledgerr.execute_transaction(
        v_partner1_id, v_account1_id,
        v_bank_partner_id, v_settlement_account_id,
        50.00,
        'PURCHASE',
        'Coffee shop purchase',
        'PURCHASE_001'
    );
    
    -- Verify final balance (initial + 200 - 50 = initial + 150)
    SELECT current_balance INTO v_final_balance
    FROM ledgerr.get_payment_account_balance(v_partner1_id, v_account1_id);
    
    IF v_final_balance != (v_initial_balance + 150.00) THEN
        RAISE EXCEPTION 'TEST 2 FAILED: Balance should be %, got %', 
                       (v_initial_balance + 150.00), v_final_balance;
    END IF;
    
    -- Verify transaction types were recorded correctly
    SELECT COUNT(*) INTO v_deposit_count
    FROM ledgerr.payment_account_transactions
    WHERE partner_id = v_partner1_id 
      AND transaction_type = 'DEPOSIT'
      AND external_reference = 'DEPOSIT_001';
    
    SELECT COUNT(*) INTO v_purchase_count  
    FROM ledgerr.payment_account_transactions
    WHERE partner_id = v_partner1_id
      AND transaction_type = 'PURCHASE' 
      AND external_reference = 'PURCHASE_001';
    
    IF v_deposit_count != 1 THEN
        RAISE EXCEPTION 'TEST 2 FAILED: Should have 1 DEPOSIT transaction, got %', v_deposit_count;
    END IF;
    
    IF v_purchase_count != 1 THEN
        RAISE EXCEPTION 'TEST 2 FAILED: Should have 1 PURCHASE transaction, got %', v_purchase_count;
    END IF;
    
    RAISE NOTICE 'TEST 2 PASSED: Different transaction types work correctly';
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- TEST 3: Insufficient Funds (Error Case)
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
    RAISE NOTICE 'Starting TEST 3: Insufficient Funds';
    
    -- Get account IDs and initial balance
    SELECT payment_account_id, current_balance INTO v_account1_id, v_balance1_before
    FROM ledgerr.payment_accounts WHERE partner_id = v_partner1_id;
    
    SELECT payment_account_id INTO v_account2_id
    FROM ledgerr.payment_accounts WHERE partner_id = v_partner2_id;
    
    -- Try to transfer more than available balance (REMOVED EXPLICIT TRANSACTION MANAGEMENT)
    BEGIN
        v_entry_id := ledgerr.execute_transaction(
            v_partner1_id, v_account1_id,
            v_partner2_id, v_account2_id,
            5000.00, -- More than available balance
            'TRANSFER',
            'Test insufficient funds',
            'TEST_REF_FAIL'
        );
        
        -- If we get here, the test failed
        RAISE EXCEPTION 'TEST 3 FAILED: Transaction should have been rejected due to insufficient funds';
        
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLERRM LIKE '%Insufficient funds%' THEN
                v_error_occurred := TRUE;
                RAISE NOTICE 'Expected insufficient funds error caught: %', SQLERRM;
            ELSE
                RAISE EXCEPTION 'TEST 3 FAILED: Unexpected error: %', SQLERRM;
            END IF;
    END;
    
    -- Verify balance unchanged
    SELECT current_balance INTO v_balance1_after
    FROM ledgerr.get_payment_account_balance(v_partner1_id, v_account1_id);
    
    IF v_balance1_after != v_balance1_before THEN
        RAISE EXCEPTION 'TEST 3 FAILED: Balance should be unchanged after failed transaction. Before: %, After: %', 
                       v_balance1_before, v_balance1_after;
    END IF;
    
    IF NOT v_error_occurred THEN
        RAISE EXCEPTION 'TEST 3 FAILED: Expected insufficient funds error did not occur';
    END IF;
    
    RAISE NOTICE 'TEST 3 PASSED: Insufficient funds properly rejected';
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- TEST 4: Reversal Functionality
-- ============================================================================
CREATE OR REPLACE FUNCTION ledgerr.test_reversal()
RETURNS void AS $$
DECLARE
    v_partner1_id UUID := '11111111-1111-1111-1111-111111111111';
    v_partner2_id UUID := '22222222-2222-2222-2222-222222222222';
    v_account1_id UUID;
    v_account2_id UUID;
    v_original_entry_id UUID;
    v_reversal_entry_id UUID;
    v_balance1_before DECIMAL(15,2);
    v_balance1_after DECIMAL(15,2);
    v_balance2_before DECIMAL(15,2);
    v_balance2_after DECIMAL(15,2);
BEGIN
    RAISE NOTICE 'Starting TEST 4: Reversal Functionality';
    
    -- Get account IDs and balances before
    SELECT payment_account_id, current_balance INTO v_account1_id, v_balance1_before
    FROM ledgerr.payment_accounts WHERE partner_id = v_partner1_id;
    
    SELECT payment_account_id, current_balance INTO v_account2_id, v_balance2_before
    FROM ledgerr.payment_accounts WHERE partner_id = v_partner2_id;
    
    -- Execute original transaction (REMOVED EXPLICIT TRANSACTION MANAGEMENT)
    v_original_entry_id := ledgerr.execute_transaction(
        v_partner1_id, v_account1_id,
        v_partner2_id, v_account2_id,
        75.00,
        'TRANSFER',
        'Test transaction for reversal',
        'REVERSAL_TEST_001'
    );
    
    -- Create reversal
    v_reversal_entry_id := ledgerr.create_reversal_entry(
        v_original_entry_id,
        CURRENT_DATE,
        'Testing reversal functionality',
        'test_user'
    );
    
    -- Verify balances are back to original
    SELECT current_balance INTO v_balance1_after
    FROM ledgerr.get_payment_account_balance(v_partner1_id, v_account1_id);
    
    SELECT current_balance INTO v_balance2_after  
    FROM ledgerr.get_payment_account_balance(v_partner2_id, v_account2_id);
    
    IF v_balance1_after != v_balance1_before THEN
        RAISE EXCEPTION 'TEST 4 FAILED: Account 1 balance should be restored to %, got %', 
                       v_balance1_before, v_balance1_after;
    END IF;
    
    IF v_balance2_after != v_balance2_before THEN
        RAISE EXCEPTION 'TEST 4 FAILED: Account 2 balance should be restored to %, got %',
                       v_balance2_before, v_balance2_after;
    END IF;
    
    -- Verify original entry is marked as reversed
    IF NOT EXISTS (
        SELECT 1 FROM ledgerr.journal_entries 
        WHERE entry_id = v_original_entry_id 
          AND entry_date = CURRENT_DATE
          AND is_reversed = TRUE
    ) THEN
        RAISE EXCEPTION 'TEST 4 FAILED: Original entry should be marked as reversed';
    END IF;
    
    RAISE NOTICE 'TEST 4 PASSED: Reversal functionality works correctly';
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- TEST 5: GL Account Balance Inquiry
-- ============================================================================
CREATE OR REPLACE FUNCTION ledgerr.test_gl_balance_inquiry()
RETURNS void AS $$
DECLARE
    v_gl_account_id UUID;
    v_balance_record RECORD;
    v_expected_transaction_count BIGINT;
BEGIN
    RAISE NOTICE 'Starting TEST 5: GL Account Balance Inquiry';
    
    -- Get a GL account that should have transactions (updated account code)
    SELECT gl_account_id INTO v_gl_account_id
    FROM ledgerr.gl_accounts 
    WHERE account_code = 'TST_ASSET'
    LIMIT 1;
    
    -- Test GL balance function
    SELECT * INTO v_balance_record
    FROM ledgerr.get_gl_account_balance(v_gl_account_id, CURRENT_DATE);
    
    -- Basic validation that function returns data
    IF v_balance_record.account_balance IS NULL THEN
        RAISE EXCEPTION 'TEST 5 FAILED: GL balance function should return a balance';
    END IF;
    
    IF v_balance_record.transaction_count < 0 THEN
        RAISE EXCEPTION 'TEST 5 FAILED: Transaction count should be non-negative, got %', 
                       v_balance_record.transaction_count;
    END IF;
    
    -- Verify that debits minus credits equals account balance
    IF v_balance_record.account_balance != (v_balance_record.total_debits - v_balance_record.total_credits) THEN
        RAISE EXCEPTION 'TEST 5 FAILED: Account balance should equal debits minus credits';
    END IF;
    
    RAISE NOTICE 'TEST 5 PASSED: GL balance inquiry works correctly. Balance: %, Transactions: %', 
                 v_balance_record.account_balance, v_balance_record.transaction_count;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- TEST RUNNER
-- ============================================================================
CREATE OR REPLACE FUNCTION ledgerr.run_all_tests()
RETURNS void AS $$
DECLARE
    v_error_message TEXT;
    v_error_detail TEXT;
    v_error_hint TEXT;
    v_error_context TEXT;
    v_error_sqlstate TEXT;
    v_test_name TEXT;
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE 'RUNNING LEDGER TESTS WITH FULL DEBUG';
    RAISE NOTICE '========================================';
    
    -- Setup test data
    BEGIN
        v_test_name := 'SETUP';
        RAISE NOTICE 'Running: %', v_test_name;
        PERFORM ledgerr.setup_test_data();
        RAISE NOTICE 'COMPLETED: %', v_test_name;
    EXCEPTION
        WHEN OTHERS THEN
            GET STACKED DIAGNOSTICS
                v_error_message = MESSAGE_TEXT,
                v_error_detail = PG_EXCEPTION_DETAIL,
                v_error_hint = PG_EXCEPTION_HINT,
                v_error_context = PG_EXCEPTION_CONTEXT,
                v_error_sqlstate = RETURNED_SQLSTATE;
            
            RAISE EXCEPTION E'FAILED IN: %\nERROR: %\nDETAIL: %\nHINT: %\nCONTEXT: %\nSQLSTATE: %',
                v_test_name, v_error_message, v_error_detail, v_error_hint, v_error_context, v_error_sqlstate;
    END;
    
    -- Test 1: Basic Transfer
    BEGIN
        v_test_name := 'TEST 1: Basic Transfer';
        RAISE NOTICE 'Running: %', v_test_name;
        PERFORM ledgerr.test_basic_transfer();
        RAISE NOTICE 'COMPLETED: %', v_test_name;
    EXCEPTION
        WHEN OTHERS THEN
            GET STACKED DIAGNOSTICS
                v_error_message = MESSAGE_TEXT,
                v_error_detail = PG_EXCEPTION_DETAIL,
                v_error_hint = PG_EXCEPTION_HINT,
                v_error_context = PG_EXCEPTION_CONTEXT,
                v_error_sqlstate = RETURNED_SQLSTATE;
            
            RAISE EXCEPTION E'FAILED IN: %\nERROR: %\nDETAIL: %\nHINT: %\nCONTEXT: %\nSQLSTATE: %',
                v_test_name, v_error_message, v_error_detail, v_error_hint, v_error_context, v_error_sqlstate;
    END;
    
    -- Test 2: Transaction Types
    BEGIN
        v_test_name := 'TEST 2: Transaction Types';
        RAISE NOTICE 'Running: %', v_test_name;
        PERFORM ledgerr.test_transaction_types();
        RAISE NOTICE 'COMPLETED: %', v_test_name;
    EXCEPTION
        WHEN OTHERS THEN
            GET STACKED DIAGNOSTICS
                v_error_message = MESSAGE_TEXT,
                v_error_detail = PG_EXCEPTION_DETAIL,
                v_error_hint = PG_EXCEPTION_HINT,
                v_error_context = PG_EXCEPTION_CONTEXT,
                v_error_sqlstate = RETURNED_SQLSTATE;
            
            RAISE EXCEPTION E'FAILED IN: %\nERROR: %\nDETAIL: %\nHINT: %\nCONTEXT: %\nSQLSTATE: %',
                v_test_name, v_error_message, v_error_detail, v_error_hint, v_error_context, v_error_sqlstate;
    END;
    
    -- Test 3: Insufficient Funds
    BEGIN
        v_test_name := 'TEST 3: Insufficient Funds';
        RAISE NOTICE 'Running: %', v_test_name;
        PERFORM ledgerr.test_insufficient_funds();
        RAISE NOTICE 'COMPLETED: %', v_test_name;
    EXCEPTION
        WHEN OTHERS THEN
            GET STACKED DIAGNOSTICS
                v_error_message = MESSAGE_TEXT,
                v_error_detail = PG_EXCEPTION_DETAIL,
                v_error_hint = PG_EXCEPTION_HINT,
                v_error_context = PG_EXCEPTION_CONTEXT,
                v_error_sqlstate = RETURNED_SQLSTATE;
            
            RAISE EXCEPTION E'FAILED IN: %\nERROR: %\nDETAIL: %\nHINT: %\nCONTEXT: %\nSQLSTATE: %',
                v_test_name, v_error_message, v_error_detail, v_error_hint, v_error_context, v_error_sqlstate;
    END;
    
    -- Test 4: Reversal
    BEGIN
        v_test_name := 'TEST 4: Reversal';
        RAISE NOTICE 'Running: %', v_test_name;
        PERFORM ledgerr.test_reversal();
        RAISE NOTICE 'COMPLETED: %', v_test_name;
    EXCEPTION
        WHEN OTHERS THEN
            GET STACKED DIAGNOSTICS
                v_error_message = MESSAGE_TEXT,
                v_error_detail = PG_EXCEPTION_DETAIL,
                v_error_hint = PG_EXCEPTION_HINT,
                v_error_context = PG_EXCEPTION_CONTEXT,
                v_error_sqlstate = RETURNED_SQLSTATE;
            
            RAISE EXCEPTION E'FAILED IN: %\nERROR: %\nDETAIL: %\nHINT: %\nCONTEXT: %\nSQLSTATE: %',
                v_test_name, v_error_message, v_error_detail, v_error_hint, v_error_context, v_error_sqlstate;
    END;
    
    -- Test 5: GL Balance
    BEGIN
        v_test_name := 'TEST 5: GL Balance';
        RAISE NOTICE 'Running: %', v_test_name;
        PERFORM ledgerr.test_gl_balance_inquiry();
        RAISE NOTICE 'COMPLETED: %', v_test_name;
    EXCEPTION
        WHEN OTHERS THEN
            GET STACKED DIAGNOSTICS
                v_error_message = MESSAGE_TEXT,
                v_error_detail = PG_EXCEPTION_DETAIL,
                v_error_hint = PG_EXCEPTION_HINT,
                v_error_context = PG_EXCEPTION_CONTEXT,
                v_error_sqlstate = RETURNED_SQLSTATE;
            
            RAISE EXCEPTION E'FAILED IN: %\nERROR: %\nDETAIL: %\nHINT: %\nCONTEXT: %\nSQLSTATE: %',
                v_test_name, v_error_message, v_error_detail, v_error_hint, v_error_context, v_error_sqlstate;
    END;
    
    RAISE NOTICE '========================================';
    RAISE NOTICE 'ALL TESTS PASSED!';
    RAISE NOTICE '========================================';
    
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION ledgerr.test_basic_transfer_debug()
RETURNS void AS $$
DECLARE
    v_partner1_id UUID := '11111111-1111-1111-1111-111111111111';
    v_partner2_id UUID := '22222222-2222-2222-2222-222222222222';
    v_account1_id UUID;
    v_account2_id UUID;
    v_entry_id UUID;
    v_balance1 DECIMAL(15,2);
    v_balance2 DECIMAL(15,2);
BEGIN
    RAISE NOTICE 'Starting DEBUG TEST: Basic Transfer';
    
    -- Get account IDs
    SELECT payment_account_id INTO v_account1_id 
    FROM ledgerr.payment_accounts WHERE partner_id = v_partner1_id;
    
    SELECT payment_account_id INTO v_account2_id
    FROM ledgerr.payment_accounts WHERE partner_id = v_partner2_id;
    
    RAISE NOTICE 'Account 1 ID: %', v_account1_id;
    RAISE NOTICE 'Account 2 ID: %', v_account2_id;
    
    -- Check if accounts exist
    IF v_account1_id IS NULL THEN
        RAISE EXCEPTION 'Account 1 not found for partner %', v_partner1_id;
    END IF;
    
    IF v_account2_id IS NULL THEN
        RAISE EXCEPTION 'Account 2 not found for partner %', v_partner2_id;
    END IF;
    
    -- Execute transfer with debug info
    BEGIN
        RAISE NOTICE 'About to execute transaction...';
        
        v_entry_id := ledgerr.execute_transaction(
            v_partner1_id, v_account1_id,
            v_partner2_id, v_account2_id, 
            100.00,
            'TRANSFER',
            'Test transfer between accounts',
            'TEST_REF_001'
        );
        
        RAISE NOTICE 'Transaction executed. Entry ID: %', v_entry_id;
        
        -- Check if entry_id is NULL
        IF v_entry_id IS NULL THEN
            RAISE EXCEPTION 'execute_transaction returned NULL entry_id';
        END IF;
        
    EXCEPTION
        WHEN OTHERS THEN
            RAISE EXCEPTION 'Transfer failed: %', SQLERRM;
    END;
    
    RAISE NOTICE 'DEBUG TEST completed successfully';
END;
$$ LANGUAGE plpgsql;

-- Run all tests
BEGIN;
    SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
    DO $$
    BEGIN
        PERFORM ledgerr.run_all_tests();
    END;
    $$ LANGUAGE plpgsql;
COMMIT;