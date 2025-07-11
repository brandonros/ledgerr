CREATE OR REPLACE FUNCTION ledgerr.record_journal_entry(
    p_entry_date DATE,
    p_description TEXT,
    p_journal_lines JSONB,
    p_reference_number VARCHAR(50) DEFAULT NULL,
    p_created_by VARCHAR(50) DEFAULT 'system'
) RETURNS INTEGER AS $$
DECLARE
    v_entry_id INTEGER;
    v_total_debits DECIMAL(15,2) := 0;
    v_total_credits DECIMAL(15,2) := 0;
    v_line JSONB;
    v_account_id INTEGER;
    v_debit_amount DECIMAL(15,2);
    v_credit_amount DECIMAL(15,2);
    v_line_description TEXT;
BEGIN
    -- Validate input parameters
    IF p_entry_date IS NULL THEN
        RAISE EXCEPTION 'Entry date cannot be null';
    END IF;
    
    IF p_description IS NULL OR trim(p_description) = '' THEN
        RAISE EXCEPTION 'Description cannot be empty';
    END IF;
    
    IF jsonb_array_length(p_journal_lines) < 2 THEN
        RAISE EXCEPTION 'At least two journal lines are required for double-entry';
    END IF;
    
    -- Create the journal entry header
    INSERT INTO ledgerr.journal_entries (entry_date, description, reference_number, created_by)
    VALUES (p_entry_date, p_description, p_reference_number, p_created_by)
    RETURNING entry_id INTO v_entry_id;
    
    -- Process each journal line
    FOR v_line IN SELECT * FROM jsonb_array_elements(p_journal_lines)
    LOOP
        -- Extract values from JSON
        v_account_id := (v_line->>'account_id')::INTEGER;
        v_debit_amount := COALESCE((v_line->>'debit_amount')::DECIMAL(15,2), 0);
        v_credit_amount := COALESCE((v_line->>'credit_amount')::DECIMAL(15,2), 0);
        v_line_description := v_line->>'description';
        
        -- Validate account exists
        IF NOT EXISTS (SELECT 1 FROM ledgerr.accounts WHERE account_id = v_account_id AND is_active = TRUE) THEN
            RAISE EXCEPTION 'Account ID % does not exist or is inactive', v_account_id;
        END IF;
        
        -- Validate that exactly one of debit or credit is provided
        IF (v_debit_amount > 0 AND v_credit_amount > 0) OR (v_debit_amount = 0 AND v_credit_amount = 0) THEN
            RAISE EXCEPTION 'Each line must have either a debit amount or credit amount, but not both';
        END IF;
        
        -- Insert journal entry line
        INSERT INTO ledgerr.journal_entry_lines (entry_id, account_id, debit_amount, credit_amount, description)
        VALUES (v_entry_id, v_account_id, v_debit_amount, v_credit_amount, v_line_description);
        
        -- Add to totals
        v_total_debits := v_total_debits + v_debit_amount;
        v_total_credits := v_total_credits + v_credit_amount;
    END LOOP;
    
    -- Validate that debits equal credits (fundamental accounting equation)
    IF v_total_debits != v_total_credits THEN
        RAISE EXCEPTION 'Total debits (%) must equal total credits (%) - transaction not balanced', 
                       v_total_debits, v_total_credits;
    END IF;
    
    -- Mark the entry as posted
    UPDATE ledgerr.journal_entries 
    SET is_posted = TRUE 
    WHERE entry_id = v_entry_id;
    
    RETURN v_entry_id;
END;
$$ LANGUAGE plpgsql;