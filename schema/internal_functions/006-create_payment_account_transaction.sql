CREATE OR REPLACE FUNCTION ledgerr.create_payment_account_transaction(
    p_partner_id UUID,
    p_payment_account_id UUID,
    p_amount DECIMAL(15,2),
    p_transaction_type VARCHAR(20),
    p_journal_entry_id UUID,
    p_journal_line_id UUID,
    p_entry_date DATE,
    p_description TEXT DEFAULT NULL,
    p_external_reference VARCHAR(50) DEFAULT NULL
) RETURNS UUID AS $$
DECLARE
    v_transaction_id UUID;
    v_current_balance DECIMAL(15,2);
    v_new_balance DECIMAL(15,2);
    v_account_record RECORD;
    v_isolation_level TEXT;
BEGIN
    -- Require SERIALIZABLE isolation
    SELECT current_setting('transaction_isolation') INTO v_isolation_level;
    IF v_isolation_level != 'serializable' THEN
        RAISE EXCEPTION 'Payment processing requires SERIALIZABLE isolation level, current level is: %', v_isolation_level;
    END IF;

    -- CRITICAL: Lock the account row for atomic balance updates
    -- This prevents race conditions in high-concurrency scenarios
    SELECT current_balance, balance_version, is_active
    INTO v_account_record
    FROM ledgerr.payment_accounts 
    WHERE partner_id = p_partner_id 
      AND payment_account_id = p_payment_account_id
      AND is_active = TRUE
    FOR UPDATE; -- This is the critical lock
    
    -- Validate account exists and is active
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Payment account not found or inactive: partner_id=%, account_id=%', 
                       p_partner_id, p_payment_account_id;
    END IF;
    
    -- Calculate new balance
    v_current_balance := v_account_record.current_balance;
    v_new_balance := v_current_balance + p_amount;
    
    -- Business rule: prevent negative balances for most account types
    IF v_new_balance < 0 THEN
        RAISE EXCEPTION 'Insufficient funds: current_balance=%, attempted_amount=%, would_result=%.', 
                       v_current_balance, p_amount, v_new_balance;
    END IF;
    
    -- Insert transaction record first (for audit trail)
    INSERT INTO ledgerr.payment_account_transactions (
        partner_id,
        payment_account_id,
        journal_entry_id,
        journal_line_id,
        entry_date,
        amount,
        running_balance,
        transaction_type,
        description,
        external_reference
    ) VALUES (
        p_partner_id,
        p_payment_account_id,
        p_journal_entry_id,
        p_journal_line_id,
        p_entry_date,
        p_amount,
        v_new_balance,
        p_transaction_type,
        p_description,
        p_external_reference
    ) RETURNING transaction_id INTO v_transaction_id;
    
    -- Update account balance atomically with version check
    UPDATE ledgerr.payment_accounts 
    SET 
        current_balance = v_new_balance,
        balance_version = balance_version + 1,
        last_transaction_at = CURRENT_TIMESTAMP
    WHERE partner_id = p_partner_id 
      AND payment_account_id = p_payment_account_id
      AND balance_version = v_account_record.balance_version; -- Optimistic locking
    
    -- Verify the update succeeded (optimistic lock check)
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Balance update failed due to concurrent modification. Please retry.';
    END IF;
    
    RETURN v_transaction_id;
END;
$$ LANGUAGE plpgsql;