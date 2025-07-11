CREATE OR REPLACE FUNCTION ledgerr.process_payment(
    p_idempotency_key UUID,
    p_payment_id VARCHAR(50),
    p_from_external_account_id VARCHAR(50),
    p_to_external_account_id VARCHAR(50),
    p_amount DECIMAL(15,2),
    p_description TEXT,
    p_payment_type VARCHAR(20) DEFAULT 'TRANSFER',
    p_payment_network VARCHAR(20) DEFAULT 'INTERNAL'
) RETURNS TABLE (
    status VARCHAR(20),
    transaction_id UUID,
    error_message TEXT,
    from_balance DECIMAL(15,2),
    to_balance DECIMAL(15,2),
    processing_time_ms INTEGER
) AS $$
DECLARE
    v_start_time TIMESTAMP := CURRENT_TIMESTAMP;
    v_isolation_level TEXT;
    v_entry_id UUID;
    v_from_payment_account ledgerr.payment_accounts%ROWTYPE;
    v_to_payment_account ledgerr.payment_accounts%ROWTYPE;
    v_from_balance_result RECORD;
    v_to_balance_result RECORD;
    v_daily_total DECIMAL(15,2);
    v_journal_lines JSONB;
    v_processing_time_ms INTEGER;
BEGIN
    -- Require SERIALIZABLE isolation
    SELECT current_setting('transaction_isolation') INTO v_isolation_level;
    IF v_isolation_level != 'serializable' THEN
        RAISE EXCEPTION 'Payment processing requires SERIALIZABLE isolation level, current level is: %', v_isolation_level;
    END IF;

    -- Check for existing request (idempotency)
    IF EXISTS (SELECT 1 FROM ledgerr.payment_requests WHERE idempotency_key = p_idempotency_key) THEN
        -- Return existing result
        RETURN QUERY 
        SELECT pr.status, pr.journal_entry_id, pr.response_data->>'error_message', 
               (pr.response_data->>'from_balance')::DECIMAL(15,2), 
               (pr.response_data->>'to_balance')::DECIMAL(15,2), 
               (pr.response_data->>'processing_time_ms')::INTEGER
        FROM ledgerr.payment_requests pr
        WHERE pr.idempotency_key = p_idempotency_key;
        RETURN;
    END IF;
    
    -- Get and lock payment accounts by external_account_id
    SELECT * INTO v_from_payment_account
    FROM ledgerr.payment_accounts 
    WHERE external_account_id = p_from_external_account_id AND is_active = TRUE
    FOR UPDATE;
    
    IF v_from_payment_account.payment_account_id IS NULL THEN
        INSERT INTO ledgerr.payment_requests (
            idempotency_key, payment_id, from_payment_account_id, to_payment_account_id, 
            amount, payment_type, status, response_data, entry_date, processed_at
        ) VALUES (
            p_idempotency_key, p_payment_id, NULL, NULL,
            p_amount, p_payment_type, 'FAILED', 
            jsonb_build_object('error_message', 'Source account not found'),
            CURRENT_DATE,
            CURRENT_TIMESTAMP
        );
        
        RETURN QUERY SELECT 'FAILED'::VARCHAR(20), NULL::INTEGER, 
                           'Source account not found'::TEXT, NULL::DECIMAL(15,2), NULL::DECIMAL(15,2), 0;
        RETURN;
    END IF;
    
    SELECT * INTO v_to_payment_account
    FROM ledgerr.payment_accounts 
    WHERE external_account_id = p_to_external_account_id AND is_active = TRUE
    FOR UPDATE;
    
    IF v_to_payment_account.payment_account_id IS NULL THEN
        INSERT INTO ledgerr.payment_requests (
            idempotency_key, payment_id, from_payment_account_id, to_payment_account_id, 
            amount, payment_type, status, response_data, entry_date, processed_at
        ) VALUES (
            p_idempotency_key, p_payment_id, v_from_payment_account.payment_account_id, NULL,
            p_amount, p_payment_type, 'FAILED', 
            jsonb_build_object('error_message', 'Destination account not found'),
            CURRENT_DATE,
            CURRENT_TIMESTAMP
        );
        
        RETURN QUERY SELECT 'FAILED'::VARCHAR(20), NULL::INTEGER, 
                           'Destination account not found'::TEXT, NULL::DECIMAL(15,2), NULL::DECIMAL(15,2), 0;
        RETURN;
    END IF;
    
    -- Insert payment request for tracking with proper account_ids
    INSERT INTO ledgerr.payment_requests (
        idempotency_key, payment_id, from_payment_account_id, to_payment_account_id, 
        amount, payment_type, status, entry_date
    ) VALUES (
        p_idempotency_key, p_payment_id, v_from_payment_account.payment_account_id, v_to_payment_account.payment_account_id,
        p_amount, p_payment_type, 'PROCESSING', CURRENT_DATE
    );
    
    -- Validation checks
    IF p_amount <= 0 THEN
        UPDATE ledgerr.payment_requests 
        SET status = 'FAILED', 
            response_data = jsonb_build_object('error_message', 'Amount must be positive'),
            entry_date = CURRENT_DATE,
            processed_at = CURRENT_TIMESTAMP
        WHERE idempotency_key = p_idempotency_key;
        
        RETURN QUERY SELECT 'FAILED'::VARCHAR(20), NULL::INTEGER, 
                           'Amount must be positive'::TEXT, NULL::DECIMAL(15,2), NULL::DECIMAL(15,2), 0;
        RETURN;
    END IF;
    
    -- Check available balance
    IF ledgerr.get_account_balance(v_from_payment_account.gl_liability_account_id, CURRENT_DATE, TRUE) < p_amount THEN
        UPDATE ledgerr.payment_requests 
        SET status = 'FAILED', 
            response_data = jsonb_build_object('error_message', 'Insufficient funds'),
            entry_date = CURRENT_DATE,
            processed_at = CURRENT_TIMESTAMP
        WHERE idempotency_key = p_idempotency_key;
        
        RETURN QUERY SELECT 'FAILED'::VARCHAR(20), NULL::INTEGER, 
                           'Insufficient funds'::TEXT, NULL::DECIMAL(15,2), NULL::DECIMAL(15,2), 0;
        RETURN;
    END IF;
    
    -- Check daily limits
    SELECT COALESCE(daily_debit_total, 0) INTO v_daily_total
    FROM ledgerr.account_balances 
    WHERE account_id = v_from_payment_account.gl_liability_account_id;
    
    IF (v_daily_total + p_amount) > v_from_payment_account.daily_limit THEN
        UPDATE ledgerr.payment_requests 
        SET status = 'FAILED', 
            response_data = jsonb_build_object('error_message', 'Daily limit exceeded'),
            entry_date = CURRENT_DATE,
            processed_at = CURRENT_TIMESTAMP
        WHERE idempotency_key = p_idempotency_key;
        
        RETURN QUERY SELECT 'FAILED'::VARCHAR(20), NULL::INTEGER, 
                           'Daily limit exceeded'::TEXT, NULL::DECIMAL(15,2), NULL::DECIMAL(15,2), 0;
        RETURN;
    END IF;
    
    -- Build journal entry
    v_journal_lines := jsonb_build_array(
        jsonb_build_object(
            'account_id', v_from_payment_account.gl_liability_account_id,
            'credit_amount', p_amount,
            'description', format('Payment to %s', p_to_external_account_id),
            'external_account_id', p_from_external_account_id,
            'payment_id', p_payment_id,
            'payment_type', p_payment_type
        ),
        jsonb_build_object(
            'account_id', v_to_payment_account.gl_asset_account_id,
            'debit_amount', p_amount,
            'description', format('Payment from %s', p_from_external_account_id),
            'external_account_id', p_to_external_account_id,
            'payment_id', p_payment_id,
            'payment_type', p_payment_type
        )
    );
    
    -- Record journal entry
    SELECT ledgerr.record_journal_entry(
        CURRENT_DATE,
        p_description,
        v_journal_lines,
        p_payment_id,
        'payment_system'
    ) INTO v_entry_id;
    
    -- Update balances atomically 
    SELECT * INTO v_from_balance_result
    FROM ledgerr.update_account_balance(
        v_from_payment_account.gl_liability_account_id,
        p_amount,  -- debit amount
        0.00       -- credit amount
    );
    
    SELECT * INTO v_to_balance_result
    FROM ledgerr.update_account_balance(
        v_to_payment_account.gl_asset_account_id,
        0.00,      -- debit amount
        p_amount   -- credit amount
    );
    
    -- Check if balance updates succeeded
    IF NOT v_from_balance_result.success OR NOT v_to_balance_result.success THEN
        -- Rollback will happen automatically
        RAISE EXCEPTION 'Balance update failed: %, %', 
                       v_from_balance_result.error_message, 
                       v_to_balance_result.error_message;
    END IF;
    
    -- Calculate processing time
    v_processing_time_ms := EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - v_start_time))::INTEGER * 1000;
    
    -- Update payment request status
    UPDATE ledgerr.payment_requests 
    SET status = 'SUCCESS',
        journal_entry_id = v_entry_id,
        response_data = jsonb_build_object(
            'from_balance', v_from_balance_result.new_balance,
            'to_balance', v_to_balance_result.new_balance,
            'processing_time_ms', v_processing_time_ms
        ),
        entry_date = CURRENT_DATE,
        processed_at = CURRENT_TIMESTAMP
    WHERE idempotency_key = p_idempotency_key;
    
    -- Log payment status
    INSERT INTO ledgerr.payment_status_log (
        payment_id, status, status_reason, processing_time_ms
    ) VALUES (
        p_payment_id, 'SUCCESS', 'Payment processed successfully', v_processing_time_ms
    );
    
    -- Return success result
    RETURN QUERY SELECT 'SUCCESS'::VARCHAR(20), v_entry_id, NULL::TEXT, 
                       v_from_balance_result.new_balance, v_to_balance_result.new_balance, 
                       v_processing_time_ms;
        
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'Exception: %', SQLERRM;

        -- Update payment request with error
        UPDATE ledgerr.payment_requests 
        SET status = 'FAILED', 
            response_data = jsonb_build_object('error_message', SQLERRM),
            entry_date = CURRENT_DATE,
            processed_at = CURRENT_TIMESTAMP
        WHERE idempotency_key = p_idempotency_key;
        
        -- Log error
        INSERT INTO ledgerr.payment_status_log (
            payment_id, status, status_reason, processing_time_ms
        ) VALUES (
            p_payment_id, 'FAILED', SQLERRM, 
            EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - v_start_time))::INTEGER * 1000
        );
        
        -- Return error
        RETURN QUERY SELECT 'FAILED'::VARCHAR(20), NULL::INTEGER, SQLERRM::TEXT, 
                           NULL::DECIMAL(15,2), NULL::DECIMAL(15,2), 0;
END;
$$ LANGUAGE plpgsql;