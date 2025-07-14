CREATE OR REPLACE FUNCTION ledgerr_api.record_journal_entry(
    p_entry_date DATE,
    p_description TEXT,
    p_journal_lines ledgerr_api.journal_line_type[],
    p_idempotency_key VARCHAR(100),
    p_reference_number VARCHAR(50) DEFAULT NULL,
    p_created_by VARCHAR(50) DEFAULT 'system'
) RETURNS UUID AS $$
DECLARE
    v_entry_id UUID;
    v_existing_entry_id UUID;
    v_total_debits DECIMAL(15,2) := 0;
    v_total_credits DECIMAL(15,2) := 0;
    v_line ledgerr_api.journal_line_type;
    v_account_debits HSTORE := ''::hstore;
    v_account_credits HSTORE := ''::hstore;
    v_current_account_text TEXT;
    v_current_debit DECIMAL(15,2);
    v_current_credit DECIMAL(15,2);
BEGIN
    -- Validate required idempotency key
    IF p_idempotency_key IS NULL OR trim(p_idempotency_key) = '' THEN
        RAISE EXCEPTION 'Idempotency key is required';
    END IF;

    -- Validate input parameters
    IF p_entry_date IS NULL THEN
        RAISE EXCEPTION 'Entry date cannot be null';
    END IF;
    
    IF p_description IS NULL OR trim(p_description) = '' THEN
        RAISE EXCEPTION 'Description cannot be empty';
    END IF;
    
    IF array_length(p_journal_lines, 1) < 2 THEN
        RAISE EXCEPTION 'At least two journal lines are required for double-entry';
    END IF;

    -- IDEMPOTENCY CHECK: Look for existing entry with same key on same date
    -- Use NOWAIT to fail fast if this row is locked
    BEGIN
        SELECT entry_id INTO v_existing_entry_id
        FROM ledgerr.journal_entries 
        WHERE idempotency_key = p_idempotency_key 
        AND entry_date = p_entry_date
        FOR UPDATE NOWAIT;
    EXCEPTION
        WHEN lock_not_available THEN
            -- Another transaction is processing this same idempotency key
            RAISE EXCEPTION 'CONCURRENT_PROCESSING' 
                USING HINT = 'Another transaction is processing this idempotency key. Please retry.';
    END;
    
    IF v_existing_entry_id IS NOT NULL THEN
        -- Return existing entry ID (idempotent behavior)
        RETURN v_existing_entry_id;
    END IF;
    
    -- Create the journal entry header
    INSERT INTO ledgerr.journal_entries (
        entry_date, 
        description, 
        reference_number, 
        created_by,
        idempotency_key,
        is_posted
    )
    VALUES (
        p_entry_date, 
        p_description, 
        p_reference_number, 
        p_created_by,
        p_idempotency_key,
        TRUE
    )
    RETURNING entry_id INTO v_entry_id;
    
    -- Process each journal line
    FOR v_line IN SELECT * FROM unnest(p_journal_lines)
    LOOP
        -- Access typed fields directly (no JSON extraction needed)
        v_current_account_text := v_line.account_id::TEXT;
        
        -- Validate account exists with NOWAIT to fail fast
        BEGIN
            IF NOT EXISTS (
                SELECT 1 FROM ledgerr.accounts 
                WHERE account_id = v_line.account_id 
                AND is_active = TRUE
                FOR SHARE NOWAIT
            ) THEN
                RAISE EXCEPTION 'Account ID % does not exist or is inactive', v_line.account_id;
            END IF;
        EXCEPTION
            WHEN lock_not_available THEN
                RAISE EXCEPTION 'ACCOUNT_LOCKED: Account % is locked by another transaction. Please retry.', v_line.account_id;
        END;
        
        -- Validate that exactly one of debit or credit is provided
        IF (COALESCE(v_line.debit_amount, 0) > 0 AND COALESCE(v_line.credit_amount, 0) > 0) OR 
           (COALESCE(v_line.debit_amount, 0) = 0 AND COALESCE(v_line.credit_amount, 0) = 0) THEN
            RAISE EXCEPTION 'Each line must have either a debit amount or credit amount, but not both';
        END IF;
        
        -- Insert journal entry line
        INSERT INTO ledgerr.journal_entry_lines (
            entry_id, 
            entry_date, 
            account_id, 
            debit_amount, 
            credit_amount, 
            description
        )
        VALUES (
            v_entry_id, 
            p_entry_date, 
            v_line.account_id, 
            COALESCE(v_line.debit_amount, 0), 
            COALESCE(v_line.credit_amount, 0), 
            v_line.description
        );
        
        -- Add to totals
        v_total_debits := v_total_debits + COALESCE(v_line.debit_amount, 0);
        v_total_credits := v_total_credits + COALESCE(v_line.credit_amount, 0);
        
        -- Accumulate account balances using hstore for O(1) lookups
        v_account_debits := v_account_debits || 
            hstore(v_current_account_text, (COALESCE((v_account_debits -> v_current_account_text)::DECIMAL(15,2), 0) + COALESCE(v_line.debit_amount, 0))::TEXT);
        v_account_credits := v_account_credits || 
            hstore(v_current_account_text, (COALESCE((v_account_credits -> v_current_account_text)::DECIMAL(15,2), 0) + COALESCE(v_line.credit_amount, 0))::TEXT);
    END LOOP;
    
    -- Validate that debits equal credits
    IF v_total_debits != v_total_credits THEN
        RAISE EXCEPTION 'Total debits (%) must equal total credits (%) - transaction not balanced', 
                       v_total_debits, v_total_credits;
    END IF;
    
    -- Update account balance cache using accumulated data
    FOR v_current_account_text IN SELECT unnest(akeys(v_account_debits))
    LOOP
        v_current_debit := COALESCE((v_account_debits -> v_current_account_text)::DECIMAL(15,2), 0);
        v_current_credit := COALESCE((v_account_credits -> v_current_account_text)::DECIMAL(15,2), 0);
        
        -- The balance update function will respect our timeout settings
        PERFORM ledgerr.update_account_balance(
            p_account_id := v_current_account_text::UUID,
            p_debit_amount := v_current_debit,
            p_credit_amount := v_current_credit,
            p_transaction_date := p_entry_date
        );
    END LOOP;
    
    RETURN v_entry_id;
    
EXCEPTION
    WHEN lock_not_available THEN
        RAISE EXCEPTION 'LOCK_TIMEOUT' 
            USING HINT = 'Could not acquire necessary locks within timeout period. Please retry.';
    WHEN query_canceled THEN
        RAISE EXCEPTION 'STATEMENT_TIMEOUT' 
            USING HINT = 'Transaction timed out. Please retry with smaller batch or contact support.';
    WHEN serialization_failure THEN
        RAISE EXCEPTION 'SERIALIZATION_CONFLICT' 
            USING HINT = 'Transaction conflicts with concurrent activity. Please retry.';
END;
$$ LANGUAGE plpgsql SECURITY DEFINER VOLATILE
SET default_transaction_isolation TO 'serializable'
SET lock_timeout TO '200ms'
SET statement_timeout TO '500ms'
SET idle_in_transaction_session_timeout TO '1000ms';