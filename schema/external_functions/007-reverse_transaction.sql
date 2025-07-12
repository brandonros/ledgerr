CREATE OR REPLACE FUNCTION ledgerr_api.reverse_transaction(
    p_original_journal_entry_id UUID,
    p_reversal_reason TEXT,
    p_created_by VARCHAR(50) DEFAULT 'api_user'
) RETURNS JSONB AS $$
DECLARE
    v_original_entry RECORD;
    v_reversal_entry_id UUID;
    v_affected_accounts JSONB;
BEGIN
    -- Find the original entry and its date
    SELECT entry_id, entry_date, description, is_reversed, is_posted
    INTO v_original_entry
    FROM ledgerr.journal_entries 
    WHERE entry_id = p_original_journal_entry_id
    ORDER BY entry_date DESC  -- Get the most recent if multiple dates exist
    LIMIT 1;
    
    -- Validate the original entry exists
    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'Transaction not found',
            'error_code', 'TRANSACTION_NOT_FOUND'
        );
    END IF;
    
    -- Check if already reversed
    IF v_original_entry.is_reversed THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'Transaction has already been reversed',
            'error_code', 'ALREADY_REVERSED'
        );
    END IF;
    
    -- Check if entry is posted (can't reverse unposted entries)
    IF NOT v_original_entry.is_posted THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'Cannot reverse unposted transaction',
            'error_code', 'NOT_POSTED'
        );
    END IF;
    
    -- Validate reversal reason
    IF p_reversal_reason IS NULL OR trim(p_reversal_reason) = '' THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'Reversal reason is required',
            'error_code', 'MISSING_REASON'
        );
    END IF;
    
    -- Get affected payment accounts for the response
    SELECT jsonb_agg(
        jsonb_build_object(
            'partner_id', pat.partner_id,
            'payment_account_id', pat.payment_account_id,
            'original_amount', pat.amount
        )
    ) INTO v_affected_accounts
    FROM ledgerr.payment_account_transactions pat
    WHERE pat.journal_entry_id = p_original_journal_entry_id
      AND pat.entry_date = v_original_entry.entry_date;
    
    -- Execute the reversal using the internal function
    BEGIN
        v_reversal_entry_id := ledgerr.create_reversal_entry(
            v_original_entry.entry_id,
            v_original_entry.entry_date,
            p_reversal_reason,
            p_created_by
        );
        
        -- Return success response with details
        RETURN jsonb_build_object(
            'success', true,
            'reversal_entry_id', v_reversal_entry_id,
            'original_entry_id', v_original_entry.entry_id,
            'original_description', v_original_entry.description,
            'reversal_reason', p_reversal_reason,
            'affected_accounts', v_affected_accounts,
            'reversed_at', CURRENT_TIMESTAMP,
            'reversed_by', p_created_by
        );
        
    EXCEPTION 
        WHEN OTHERS THEN
            -- Handle any errors from the internal function
            RETURN jsonb_build_object(
                'success', false,
                'error', 'Reversal failed: ' || SQLERRM,
                'error_code', 'REVERSAL_FAILED'
            );
    END;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER VOLATILE;
