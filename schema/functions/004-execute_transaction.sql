CREATE OR REPLACE FUNCTION ledgerr.execute_transaction(
    p_from_partner_id UUID,
    p_from_payment_account_id UUID,
    p_to_partner_id UUID,
    p_to_payment_account_id UUID,
    p_amount DECIMAL(15,2),
    p_transaction_type VARCHAR(20), -- NEW: Required parameter
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
    v_from_description TEXT;
    v_to_description TEXT;
BEGIN
    -- Require SERIALIZABLE isolation
    SELECT current_setting('transaction_isolation') INTO v_isolation_level;
    IF v_isolation_level != 'serializable' THEN
        RAISE EXCEPTION 'Payment processing requires SERIALIZABLE isolation level, current level is: %', v_isolation_level;
    END IF;

    -- Validate transaction type
    IF p_transaction_type NOT IN ('DEPOSIT', 'WITHDRAWAL', 'TRANSFER', 'PURCHASE', 'REFUND', 'FEE', 'ADJUSTMENT', 'PAYMENT') THEN
        RAISE EXCEPTION 'Invalid transaction type: %', p_transaction_type;
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
    
    -- Build contextual descriptions based on transaction type
    CASE p_transaction_type
        WHEN 'DEPOSIT' THEN
            v_from_description := 'Funding source: ' || p_description;
            v_to_description := 'Deposit: ' || p_description;
        WHEN 'WITHDRAWAL' THEN
            v_from_description := 'Withdrawal: ' || p_description;
            v_to_description := 'Withdrawal destination: ' || p_description;
        WHEN 'PURCHASE' THEN
            v_from_description := 'Purchase: ' || p_description;
            v_to_description := 'Purchase settlement: ' || p_description;
        WHEN 'REFUND' THEN
            v_from_description := 'Refund source: ' || p_description;
            v_to_description := 'Refund: ' || p_description;
        WHEN 'FEE' THEN
            v_from_description := 'Fee charged: ' || p_description;
            v_to_description := 'Fee income: ' || p_description;
        WHEN 'PAYMENT' THEN
            v_from_description := 'Payment: ' || p_description;
            v_to_description := 'Payment received: ' || p_description;
        WHEN 'ADJUSTMENT' THEN
            v_from_description := 'Adjustment out: ' || p_description;
            v_to_description := 'Adjustment in: ' || p_description;
        ELSE -- TRANSFER and any other
            v_from_description := 'Transfer out: ' || p_description;
            v_to_description := 'Transfer in: ' || p_description;
    END CASE;
    
    -- Build journal entry (double-entry: debit destination, credit source)
    v_journal_lines := jsonb_build_array(
        jsonb_build_object(
            'gl_account_id', v_to_gl_account,
            'debit_amount', p_amount,
            'credit_amount', 0,
            'description', v_to_description
        ),
        jsonb_build_object(
            'gl_account_id', v_from_gl_account,
            'debit_amount', 0,
            'credit_amount', p_amount,
            'description', v_from_description
        )
    );
    
    -- Record the journal entry
    v_entry_id := ledgerr.record_journal_entry(
        v_entry_date,
        p_transaction_type || ': ' || p_description, -- Include transaction type in journal description
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
    
    -- Update balances atomically with the actual transaction type
    PERFORM ledgerr.create_payment_account_transaction(
        p_from_partner_id, p_from_payment_account_id, -p_amount, p_transaction_type,
        v_entry_id, v_from_line_id, v_entry_date, p_description, p_external_reference
    );
    
    PERFORM ledgerr.create_payment_account_transaction(
        p_to_partner_id, p_to_payment_account_id, p_amount, p_transaction_type, 
        v_entry_id, v_to_line_id, v_entry_date, p_description, p_external_reference
    );
    
    RETURN v_entry_id;
END;
$$ LANGUAGE plpgsql;