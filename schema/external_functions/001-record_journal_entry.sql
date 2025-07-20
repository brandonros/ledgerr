CREATE OR REPLACE FUNCTION ledgerr_api.record_journal_entry(
    p_entry_date DATE,
    p_description TEXT,
    p_credit_line ledgerr_api.journal_line_type,
    p_debit_line ledgerr_api.journal_line_type,
    p_idempotency_key VARCHAR(100),
    p_reference_number VARCHAR(50) DEFAULT NULL,
    p_created_by VARCHAR(50) DEFAULT 'system'
) RETURNS UUID AS $$
DECLARE
    v_entry_id UUID;
    v_existing_entry_id UUID;
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
    
    IF p_credit_line IS NULL OR p_debit_line IS NULL THEN
        RAISE EXCEPTION 'Both credit and debit lines are required';
    END IF;
    
    -- Validate debit line has only debit amount
    IF p_debit_line.debit_amount IS NULL OR p_debit_line.debit_amount <= 0 THEN
        RAISE EXCEPTION 'Debit line must have a positive debit amount';
    END IF;
    
    IF p_debit_line.credit_amount IS NOT NULL AND p_debit_line.credit_amount != 0 THEN
        RAISE EXCEPTION 'Debit line cannot have a credit amount';
    END IF;
    
    -- Validate credit line has only credit amount
    IF p_credit_line.credit_amount IS NULL OR p_credit_line.credit_amount <= 0 THEN
        RAISE EXCEPTION 'Credit line must have a positive credit amount';
    END IF;
    
    IF p_credit_line.debit_amount IS NOT NULL AND p_credit_line.debit_amount != 0 THEN
        RAISE EXCEPTION 'Credit line cannot have a debit amount';
    END IF;
    
    -- Validate amounts balance
    IF p_debit_line.debit_amount != p_credit_line.credit_amount THEN
        RAISE EXCEPTION 'Debit amount (%) must equal credit amount (%) - transaction not balanced', 
                       p_debit_line.debit_amount, p_credit_line.credit_amount;
    END IF;

    -- Validate that both accounts exist and are active
    IF NOT EXISTS (SELECT 1 FROM ledgerr.accounts WHERE account_id = p_debit_line.account_id AND is_active = TRUE) THEN
        RAISE EXCEPTION 'Debit account is invalid or inactive';
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM ledgerr.accounts WHERE account_id = p_credit_line.account_id AND is_active = TRUE) THEN
        RAISE EXCEPTION 'Credit account is invalid or inactive';
    END IF;

    -- IDEMPOTENCY CHECK: Look for existing entry with same key on same date and return it if found
    SELECT entry_id INTO v_existing_entry_id
    FROM ledgerr.journal_entries 
    WHERE idempotency_key = p_idempotency_key 
    AND entry_date = p_entry_date;
    IF v_existing_entry_id IS NOT NULL THEN
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
    
    -- Insert debit journal entry line
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
        p_debit_line.account_id, 
        p_debit_line.debit_amount, 
        0, 
        p_debit_line.description
    );
    
    -- Insert credit journal entry line
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
        p_credit_line.account_id, 
        0, 
        p_credit_line.credit_amount, 
        p_credit_line.description
    );
    
    -- Update account balance cache for debit account
    PERFORM ledgerr.update_account_balance(
        p_account_id := p_debit_line.account_id,
        p_debit_amount := p_debit_line.debit_amount,
        p_credit_amount := 0,
        p_transaction_date := p_entry_date
    );
    
    -- Update account balance cache for credit account
    PERFORM ledgerr.update_account_balance(
        p_account_id := p_credit_line.account_id,
        p_debit_amount := 0,
        p_credit_amount := p_credit_line.credit_amount,
        p_transaction_date := p_entry_date
    );
    
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