CREATE OR REPLACE FUNCTION ledgerr.create_reversal_entry(
    p_original_entry_id UUID,
    p_original_entry_date DATE,
    p_reversal_reason TEXT,
    p_created_by VARCHAR(50)
) RETURNS UUID AS $$
DECLARE
    v_reversal_entry_id UUID;
    v_original_entry RECORD;
    v_line RECORD;
BEGIN
    -- Get the original entry
    SELECT * INTO v_original_entry
    FROM ledgerr.journal_entries
    WHERE entry_id = p_original_entry_id AND entry_date = p_original_entry_date;
    
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Original entry not found';
    END IF;
    
    IF v_original_entry.is_reversed THEN
        RAISE EXCEPTION 'Entry has already been reversed';
    END IF;
    
    -- Generate new reversal entry ID
    v_reversal_entry_id := uuid_generate_v4();
    
    -- Create the reversal entry
    INSERT INTO ledgerr.journal_entries (
        entry_id, entry_date, description, reference_number, 
        created_by, entry_type, original_entry_id, original_entry_date, 
        reversal_reason, is_posted
    ) VALUES (
        v_reversal_entry_id,
        CURRENT_DATE,
        'REVERSAL: ' || v_original_entry.description,
        'REV-' || v_original_entry.reference_number,
        p_created_by,
        'REVERSAL',
        p_original_entry_id,
        p_original_entry_date,
        p_reversal_reason,
        false
    );
    
    -- Create reversal lines (flip debits and credits)
    FOR v_line IN 
        SELECT * FROM ledgerr.journal_entry_lines 
        WHERE entry_id = p_original_entry_id AND entry_date = p_original_entry_date
    LOOP
        INSERT INTO ledgerr.journal_entry_lines (
            entry_date, entry_id, gl_account_id, 
            debit_amount, credit_amount, description,
            external_account_id, payment_id, payment_type,
            dempotency_key, payment_network, settlement_date,
            external_reference, processing_fee
        ) VALUES (
            CURRENT_DATE,
            v_reversal_entry_id,
            v_line.gl_account_id,
            v_line.credit_amount,  -- Flip: original credit becomes debit
            v_line.debit_amount,   -- Flip: original debit becomes credit
            'REVERSAL: ' || v_line.description,
            v_line.external_account_id,
            v_line.payment_id,
            v_line.payment_type,
            v_line.dempotency_key,
            v_line.payment_network,
            v_line.settlement_date,
            v_line.external_reference,
            -v_line.processing_fee  -- Reverse the fee
        );
    END LOOP;
    
    -- Mark original entry as reversed
    UPDATE ledgerr.journal_entries 
    SET is_reversed = true,
        reversed_by_entry_id = v_reversal_entry_id,
        reversed_by_entry_date = CURRENT_DATE
    WHERE entry_id = p_original_entry_id AND entry_date = p_original_entry_date;
    
    RETURN v_reversal_entry_id;
END;
$$ LANGUAGE plpgsql;