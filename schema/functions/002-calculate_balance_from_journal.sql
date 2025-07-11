CREATE OR REPLACE FUNCTION ledgerr.calculate_balance_from_journal(
    p_account_id UUID,
    p_as_of_date DATE DEFAULT CURRENT_DATE
) RETURNS DECIMAL(15,2) AS $$
DECLARE
    v_balance DECIMAL(15,2);
    v_account_type VARCHAR(20);
    v_journal_count INTEGER;
    v_debit_total DECIMAL(15,2);
    v_credit_total DECIMAL(15,2);
BEGIN
    RAISE NOTICE 'calculate_balance_from_journal: START - account_id=%, as_of_date=%', p_account_id, p_as_of_date;

    -- Get account type (with validation)
    SELECT account_type INTO v_account_type
    FROM ledgerr.accounts 
    WHERE account_id = p_account_id AND is_active = TRUE;
    
    RAISE NOTICE 'calculate_balance_from_journal: Account lookup - account_type=%, found=%', 
        v_account_type, (v_account_type IS NOT NULL);
    
    IF v_account_type IS NULL THEN
        RAISE EXCEPTION 'Account ID % does not exist or is inactive', p_account_id;
    END IF;
    
    -- Count journal entries for debugging
    SELECT COUNT(*) INTO v_journal_count
    FROM ledgerr.journal_entry_lines jel
    JOIN ledgerr.journal_entries je ON jel.entry_id = je.entry_id
    WHERE jel.account_id = p_account_id
      AND je.entry_date <= p_as_of_date
      AND je.is_posted = TRUE;
    
    RAISE NOTICE 'calculate_balance_from_journal: Found % journal entries for account % up to date %', 
        v_journal_count, p_account_id, p_as_of_date;
    
    -- Get debit and credit totals separately for debugging
    SELECT 
        COALESCE(SUM(jel.debit_amount), 0),
        COALESCE(SUM(jel.credit_amount), 0)
    INTO v_debit_total, v_credit_total
    FROM ledgerr.journal_entry_lines jel
    JOIN ledgerr.journal_entries je ON jel.entry_id = je.entry_id
    WHERE jel.account_id = p_account_id
      AND je.entry_date <= p_as_of_date
      AND je.is_posted = TRUE;
    
    RAISE NOTICE 'calculate_balance_from_journal: Totals - debit_total=%, credit_total=%', 
        v_debit_total, v_credit_total;
    
    -- Calculate balance based on account type
    SELECT 
        CASE 
            WHEN v_account_type IN ('ASSET', 'EXPENSE') THEN
                COALESCE(SUM(jel.debit_amount - jel.credit_amount), 0)
            ELSE
                COALESCE(SUM(jel.credit_amount - jel.debit_amount), 0)
        END
    INTO v_balance
    FROM ledgerr.journal_entry_lines jel
    JOIN ledgerr.journal_entries je ON jel.entry_id = je.entry_id
    WHERE jel.account_id = p_account_id
      AND je.entry_date <= p_as_of_date
      AND je.is_posted = TRUE;
    
    RAISE NOTICE 'calculate_balance_from_journal: Balance calculation - account_type=%, raw_balance=%, final_balance=%', 
        v_account_type, v_balance, COALESCE(v_balance, 0);
    
    RAISE NOTICE 'calculate_balance_from_journal: END - returning balance=%', COALESCE(v_balance, 0);
    
    RETURN COALESCE(v_balance, 0);
END;
$$ LANGUAGE plpgsql;
