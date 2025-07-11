-- Unit test for process_payment function (happy path)
BEGIN;

-- Set transaction isolation level to SERIALIZABLE for the test
SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;

SAVEPOINT before_test;

DO $$
DECLARE
    v_from_payment_account_id INTEGER;
    v_to_payment_account_id INTEGER;
    v_from_asset_account_id INTEGER;
    v_from_liability_account_id INTEGER;
    v_to_asset_account_id INTEGER;
    v_to_liability_account_id INTEGER;
    v_payment_result RECORD;
    v_journal_lines JSONB;
    v_entry_id INTEGER;
BEGIN
    RAISE NOTICE 'Starting test: process_payment happy path';

    -- Create ledger accounts
    INSERT INTO ledgerr.accounts (account_code, account_name, account_type, is_active)
    VALUES 
        ('ASSET001', 'Customer Asset - Sender', 'ASSET', TRUE),
        ('LIAB001', 'Customer Liability - Sender', 'LIABILITY', TRUE),
        ('ASSET002', 'Customer Asset - Receiver', 'ASSET', TRUE),
        ('LIAB002', 'Customer Liability - Receiver', 'LIABILITY', TRUE)
    ON CONFLICT (account_code) DO UPDATE SET account_name = EXCLUDED.account_name;

    SELECT account_id INTO v_from_asset_account_id FROM ledgerr.accounts WHERE account_code = 'ASSET001';
    SELECT account_id INTO v_from_liability_account_id FROM ledgerr.accounts WHERE account_code = 'LIAB001';
    SELECT account_id INTO v_to_asset_account_id FROM ledgerr.accounts WHERE account_code = 'ASSET002';
    SELECT account_id INTO v_to_liability_account_id FROM ledgerr.accounts WHERE account_code = 'LIAB002';

    -- Create payment accounts with GL references
    INSERT INTO ledgerr.payment_accounts (
        external_account_id, account_holder_name, account_type,
        daily_limit, is_active,
        gl_asset_account_id, gl_liability_account_id
    ) VALUES 
    (
        'EXT-PAY-001', 'Test Sender', 'CHECKING',
        10000.00, TRUE,
        v_from_asset_account_id, v_from_liability_account_id
    )
    ON CONFLICT (external_account_id) DO UPDATE 
        SET account_holder_name = EXCLUDED.account_holder_name
    RETURNING payment_account_id INTO v_from_payment_account_id;

    INSERT INTO ledgerr.payment_accounts (
        external_account_id, account_holder_name, account_type,
        daily_limit, is_active,
        gl_asset_account_id, gl_liability_account_id
    ) VALUES 
    (
        'EXT-PAY-002', 'Test Receiver', 'CHECKING',
        10000.00, TRUE,
        v_to_asset_account_id, v_to_liability_account_id
    )
    ON CONFLICT (external_account_id) DO UPDATE 
        SET account_holder_name = EXCLUDED.account_holder_name
    RETURNING payment_account_id INTO v_to_payment_account_id;

    -- Initial funding for sender (simulate a deposit into sender's GL asset account)
    v_journal_lines := jsonb_build_array(
        jsonb_build_object('account_id', v_from_asset_account_id, 'debit_amount', 5000.00, 'description', 'Initial funding'),
        jsonb_build_object('account_id', v_from_liability_account_id, 'credit_amount', 5000.00, 'description', 'Funding source')
    );

    SELECT ledgerr.record_journal_entry(
        CURRENT_DATE, 'Initial funding for payment test', v_journal_lines, 'FUND-001', 'test_setup'
    ) INTO v_entry_id;
    
    -- Test 1: Process a successful payment
    SELECT * INTO v_payment_result
    FROM ledgerr.process_payment(
        'TEST-PAY-001',           -- idempotency_key
        'PAY-12345',              -- payment_id
        'EXT-PAY-001',            -- from_external_account_id
        'EXT-PAY-002',            -- to_external_account_id
        1000.00,                  -- amount
        'Test payment transfer',   -- description
        'TRANSFER',               -- payment_type
        'INTERNAL'                -- payment_network
    );
    
    IF v_payment_result.status != 'SUCCESS' THEN
        RAISE EXCEPTION 'TEST FAILED: Payment should succeed, got status: %, error: %', 
                       v_payment_result.status, v_payment_result.error_message;
    END IF;
    
    IF v_payment_result.transaction_id IS NULL THEN
        RAISE EXCEPTION 'TEST FAILED: Should return transaction_id for successful payment';
    END IF;
    
    -- Test 2: Verify balances updated correctly
    IF v_payment_result.from_balance != 4000.00 THEN
        RAISE EXCEPTION 'TEST FAILED: From balance should be 4000.00, got %', v_payment_result.from_balance;
    END IF;
    
    IF v_payment_result.to_balance != 1000.00 THEN
        RAISE EXCEPTION 'TEST FAILED: To balance should be 1000.00, got %', v_payment_result.to_balance;
    END IF;
    
    -- Test 3: Test idempotency (same request should return same result)
    SELECT * INTO v_payment_result
    FROM ledgerr.process_payment(
        'TEST-PAY-001',           -- same idempotency_key
        'PAY-12345',              
        'EXT-PAY-001',            
        'EXT-PAY-002',            
        1000.00,                  
        'Test payment transfer',   
        'TRANSFER',               
        'INTERNAL'                
    );
    
    IF v_payment_result.status != 'SUCCESS' THEN
        RAISE EXCEPTION 'TEST FAILED: Idempotent call should return SUCCESS, got %', v_payment_result.status;
    END IF;
    
    -- Test 4: Verify payment request was logged
    IF NOT EXISTS (
        SELECT 1 FROM ledgerr.payment_requests 
        WHERE idempotency_key = 'TEST-PAY-001' 
          AND payment_id = 'PAY-12345'
          AND status = 'SUCCESS'
    ) THEN
        RAISE EXCEPTION 'TEST FAILED: Payment request should be logged with SUCCESS status';
    END IF;
    
    RAISE NOTICE '✓ TEST PASSED: process_payment happy path';
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE '✗ TEST FAILED: %', SQLERRM;
        RAISE;
END;
$$;

ROLLBACK TO SAVEPOINT before_test;

COMMIT;