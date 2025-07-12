-- Function to create balance adjustments (opening balances, corrections, adjustments)
CREATE OR REPLACE FUNCTION ledgerr_api.create_balance_adjustment(
    p_gl_account_id UUID,
    p_amount DECIMAL(15,2),
    p_description TEXT DEFAULT 'Balance adjustment',
    p_external_reference VARCHAR(50) DEFAULT NULL
) RETURNS UUID AS $$
DECLARE
    v_entry_id UUID;
    v_entry_date DATE := CURRENT_DATE;
    v_journal_lines JSONB;
    v_account_type VARCHAR(20);
    v_contra_account_id UUID;
BEGIN
    -- Get the account type to determine debit/credit logic
    SELECT account_type INTO v_account_type 
    FROM ledgerr.gl_accounts 
    WHERE gl_account_id = p_gl_account_id;
    
    IF v_account_type IS NULL THEN
        RAISE EXCEPTION 'GL Account not found: %', p_gl_account_id;
    END IF;
    
    -- Find or create "Balance Adjustments Equity" contra account
    SELECT gl_account_id INTO v_contra_account_id
    FROM ledgerr.gl_accounts 
    WHERE account_code = '3900' AND account_type = 'EQUITY';
    
    IF v_contra_account_id IS NULL THEN
        -- Create the balance adjustments equity account
        INSERT INTO ledgerr.gl_accounts (
            gl_account_id,
            account_code,
            account_name,
            account_type,
            parent_gl_account_id,
            is_active,
            created_at
        ) VALUES (
            gen_random_uuid(),
            '3900',
            'Balance Adjustments Equity',
            'EQUITY',
            NULL,
            TRUE,
            CURRENT_TIMESTAMP
        ) RETURNING gl_account_id INTO v_contra_account_id;
    END IF;
    
    -- Build journal entry based on account type
    -- For ASSET and EXPENSE accounts: Debit the account, Credit Balance Adjustments
    -- For LIABILITY, EQUITY, REVENUE accounts: Credit the account, Debit Balance Adjustments
    IF v_account_type IN ('ASSET', 'EXPENSE') THEN
        v_journal_lines := jsonb_build_array(
            jsonb_build_object(
                'gl_account_id', p_gl_account_id,
                'debit_amount', p_amount,
                'credit_amount', 0,
                'description', p_description
            ),
            jsonb_build_object(
                'gl_account_id', v_contra_account_id,
                'debit_amount', 0,
                'credit_amount', p_amount,
                'description', 'Balance adjustment contra'
            )
        );
    ELSE
        -- LIABILITY, EQUITY, REVENUE
        v_journal_lines := jsonb_build_array(
            jsonb_build_object(
                'gl_account_id', v_contra_account_id,
                'debit_amount', p_amount,
                'credit_amount', 0,
                'description', 'Balance adjustment contra'
            ),
            jsonb_build_object(
                'gl_account_id', p_gl_account_id,
                'debit_amount', 0,
                'credit_amount', p_amount,
                'description', p_description
            )
        );
    END IF;
    
    -- Record the journal entry
    v_entry_id := ledgerr.record_journal_entry(
        v_entry_date,
        'BALANCE ADJUSTMENT: ' || p_description,
        v_journal_lines,
        p_external_reference,
        'system'
    );
    
    RETURN v_entry_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER VOLATILE
SET default_transaction_isolation TO 'serializable';