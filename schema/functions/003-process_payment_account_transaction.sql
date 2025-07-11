CREATE OR REPLACE FUNCTION ledgerr.process_payment_account_transaction(
    p_from_partner_id UUID,
    p_from_payment_account_id UUID,
    p_to_partner_id UUID,
    p_to_payment_account_id UUID,
    p_amount DECIMAL(15,2),
    p_description TEXT,
    p_external_reference VARCHAR(50) DEFAULT NULL
) RETURNS UUID AS $$
DECLARE
    v_entry_id UUID;
    v_entry_date DATE := CURRENT_DATE;
    v_journal_lines JSONB;
    v_from_gl_account UUID;
    v_to_gl_account UUID;
    v_from_line_id UUID;
    v_to_line_id UUID;
    v_isolation_level TEXT;
BEGIN
    -- Require SERIALIZABLE isolation
    SELECT current_setting('transaction_isolation') INTO v_isolation_level;
    IF v_isolation_level != 'serializable' THEN
        RAISE EXCEPTION 'Payment processing requires SERIALIZABLE isolation level, current level is: %', v_isolation_level;
    END IF;

    -- Get GL accounts for both payment accounts
    SELECT gl_account_id INTO v_from_gl_account
    FROM ledgerr.payment_accounts
    WHERE partner_id = p_from_partner_id AND payment_account_id = p_from_payment_account_id;
    
    SELECT gl_account_id INTO v_to_gl_account  
    FROM ledgerr.payment_accounts
    WHERE partner_id = p_to_partner_id AND payment_account_id = p_to_payment_account_id;
    
    IF v_from_gl_account IS NULL OR v_to_gl_account IS NULL THEN
        RAISE EXCEPTION 'One or both payment accounts not found';
    END IF;
    
    -- Build journal entry (double-entry: debit destination, credit source)
    v_journal_lines := jsonb_build_array(
        jsonb_build_object(
            'gl_account_id', v_to_gl_account,
            'debit_amount', p_amount,
            'credit_amount', 0,
            'description', 'Transfer in: ' || p_description
        ),
        jsonb_build_object(
            'gl_account_id', v_from_gl_account,
            'debit_amount', 0,
            'credit_amount', p_amount,
            'description', 'Transfer out: ' || p_description
        )
    );
    
    -- Record the journal entry
    v_entry_id := ledgerr.record_journal_entry(
        v_entry_date,
        p_description,
        v_journal_lines,
        p_external_reference,
        'system'
    );
    
    -- Get the line IDs for the transaction records
    SELECT line_id INTO v_from_line_id
    FROM ledgerr.journal_entry_lines
    WHERE entry_id = v_entry_id AND gl_account_id = v_from_gl_account;
    
    SELECT line_id INTO v_to_line_id
    FROM ledgerr.journal_entry_lines  
    WHERE entry_id = v_entry_id AND gl_account_id = v_to_gl_account;
    
    -- Update balances atomically
    PERFORM ledgerr.update_payment_account_balance(
        p_from_partner_id, p_from_payment_account_id, -p_amount, 'TRANSFER',
        v_from_line_id, v_entry_date, p_description, p_external_reference
    );
    
    PERFORM ledgerr.update_payment_account_balance(
        p_to_partner_id, p_to_payment_account_id, p_amount, 'TRANSFER', 
        v_to_line_id, v_entry_date, p_description, p_external_reference
    );
    
    RETURN v_entry_id;
END;
$$ LANGUAGE plpgsql;