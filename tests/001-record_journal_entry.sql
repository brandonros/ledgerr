-- Unit test for record_journal_entry function (happy path)
DO $$
DECLARE
    v_entry_id INTEGER;
    v_journal_lines JSONB;
    v_total_entries INTEGER;
    v_total_lines INTEGER;
    v_entry_record RECORD;
    v_line_record RECORD;
    v_asset_account_id INTEGER;
    v_cash_account_id INTEGER;
BEGIN
    -- Setup savepoint
    SAVEPOINT test_start;

    -- Setup: Create test accounts if they don't exist
    INSERT INTO ledgerr.accounts (account_code, account_name, account_type, is_active)
    VALUES 
        ('1001', 'Test Equipment Asset', 'ASSET', TRUE),
        ('1000', 'Test Cash Account', 'ASSET', TRUE)
    ON CONFLICT (account_code) DO NOTHING;
    
    -- Get account IDs
    SELECT account_id INTO v_asset_account_id FROM ledgerr.accounts WHERE account_code = '1001';
    SELECT account_id INTO v_cash_account_id FROM ledgerr.accounts WHERE account_code = '1000';
    
    -- Count existing entries before test
    SELECT COUNT(*) INTO v_total_entries FROM ledgerr.journal_entries;
    SELECT COUNT(*) INTO v_total_lines FROM ledgerr.journal_entry_lines;
    
    RAISE NOTICE 'Starting test: record_journal_entry happy path';
    RAISE NOTICE 'Initial state: % entries, % lines', v_total_entries, v_total_lines;
    
    -- Test Case: Record a simple equipment purchase with cash
    -- Debit Equipment (Asset increases) $5000, Credit Cash (Asset decreases) $5000
    v_journal_lines := jsonb_build_array(
        jsonb_build_object(
            'account_id', v_asset_account_id,
            'debit_amount', 5000.00,
            'description', 'Equipment purchase - office computer'
        ),
        jsonb_build_object(
            'account_id', v_cash_account_id,
            'credit_amount', 5000.00,
            'description', 'Cash payment for equipment'
        )
    );
    
    -- Execute the function
    SELECT ledgerr.record_journal_entry(
        p_entry_date := CURRENT_DATE,
        p_description := 'Purchase of office equipment',
        p_journal_lines := v_journal_lines,
        p_reference_number := 'TEST-001',
        p_created_by := 'unit_test'
    ) INTO v_entry_id;
    
    -- Assertions
    RAISE NOTICE 'Function returned entry_id: %', v_entry_id;
    
    -- Test 1: Verify entry was created
    IF v_entry_id IS NULL THEN
        RAISE EXCEPTION 'TEST FAILED: Function returned NULL entry_id';
    END IF;
    
    -- Test 2: Verify journal entry header
    SELECT * INTO v_entry_record
    FROM ledgerr.journal_entries 
    WHERE entry_id = v_entry_id;
    
    IF v_entry_record.entry_id IS NULL THEN
        RAISE EXCEPTION 'TEST FAILED: Journal entry % not found', v_entry_id;
    END IF;
    
    IF v_entry_record.description != 'Purchase of office equipment' THEN
        RAISE EXCEPTION 'TEST FAILED: Description mismatch. Expected: "Purchase of office equipment", Got: "%"', v_entry_record.description;
    END IF;
    
    IF v_entry_record.reference_number != 'TEST-001' THEN
        RAISE EXCEPTION 'TEST FAILED: Reference number mismatch. Expected: "TEST-001", Got: "%"', v_entry_record.reference_number;
    END IF;
    
    IF v_entry_record.created_by != 'unit_test' THEN
        RAISE EXCEPTION 'TEST FAILED: Created by mismatch. Expected: "unit_test", Got: "%"', v_entry_record.created_by;
    END IF;
    
    IF v_entry_record.is_posted != TRUE THEN
        RAISE EXCEPTION 'TEST FAILED: Entry should be posted. Got: %', v_entry_record.is_posted;
    END IF;
    
    IF v_entry_record.entry_date != CURRENT_DATE THEN
        RAISE EXCEPTION 'TEST FAILED: Entry date mismatch. Expected: %, Got: %', CURRENT_DATE, v_entry_record.entry_date;
    END IF;
    
    -- Test 3: Verify exactly 2 journal entry lines were created
    SELECT COUNT(*) INTO v_total_lines
    FROM ledgerr.journal_entry_lines 
    WHERE entry_id = v_entry_id;
    
    IF v_total_lines != 2 THEN
        RAISE EXCEPTION 'TEST FAILED: Expected 2 journal lines, found %', v_total_lines;
    END IF;
    
    -- Test 4: Verify debit line (Equipment)
    SELECT * INTO v_line_record
    FROM ledgerr.journal_entry_lines 
    WHERE entry_id = v_entry_id 
      AND account_id = v_asset_account_id;
    
    IF v_line_record.debit_amount != 5000.00 THEN
        RAISE EXCEPTION 'TEST FAILED: Equipment debit amount mismatch. Expected: 5000.00, Got: %', v_line_record.debit_amount;
    END IF;
    
    IF v_line_record.credit_amount != 0.00 THEN
        RAISE EXCEPTION 'TEST FAILED: Equipment credit should be 0. Got: %', v_line_record.credit_amount;
    END IF;
    
    IF v_line_record.description != 'Equipment purchase - office computer' THEN
        RAISE EXCEPTION 'TEST FAILED: Equipment line description mismatch';
    END IF;
    
    -- Test 5: Verify credit line (Cash)
    SELECT * INTO v_line_record
    FROM ledgerr.journal_entry_lines 
    WHERE entry_id = v_entry_id 
      AND account_id = v_cash_account_id;
    
    IF v_line_record.credit_amount != 5000.00 THEN
        RAISE EXCEPTION 'TEST FAILED: Cash credit amount mismatch. Expected: 5000.00, Got: %', v_line_record.credit_amount;
    END IF;
    
    IF v_line_record.debit_amount != 0.00 THEN
        RAISE EXCEPTION 'TEST FAILED: Cash debit should be 0. Got: %', v_line_record.debit_amount;
    END IF;
    
    IF v_line_record.description != 'Cash payment for equipment' THEN
        RAISE EXCEPTION 'TEST FAILED: Cash line description mismatch';
    END IF;
    
    -- Test 6: Verify balancing (this should have been enforced by the function)
    SELECT 
        SUM(debit_amount) as total_debits,
        SUM(credit_amount) as total_credits
    INTO v_line_record
    FROM ledgerr.journal_entry_lines 
    WHERE entry_id = v_entry_id;
    
    IF v_line_record.total_debits != v_line_record.total_credits THEN
        RAISE EXCEPTION 'TEST FAILED: Entry not balanced. Debits: %, Credits: %', 
                       v_line_record.total_debits, v_line_record.total_credits;
    END IF;
    
    -- Test 7: Verify account balance calculation works
    DECLARE
        v_equipment_balance DECIMAL(15,2);
        v_cash_balance DECIMAL(15,2);
    BEGIN
        v_equipment_balance := ledgerr.get_account_balance(v_asset_account_id);
        v_cash_balance := ledgerr.get_account_balance(v_cash_account_id);
        
        RAISE NOTICE 'Equipment balance: %, Cash balance: %', v_equipment_balance, v_cash_balance;
        
        -- Equipment should have increased (positive for assets)
        IF v_equipment_balance < 5000.00 THEN
            RAISE EXCEPTION 'TEST FAILED: Equipment balance should be at least 5000.00, got %', v_equipment_balance;
        END IF;
    END;
    
    RAISE NOTICE '✓ TEST PASSED: record_journal_entry happy path - Entry ID: %', v_entry_id;

    -- Rollback to the savepoint
    ROLLBACK TO SAVEPOINT test_start;
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE '✗ TEST FAILED: %', SQLERRM;
        RAISE;
END;
$$;