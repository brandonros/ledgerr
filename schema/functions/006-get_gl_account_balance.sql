CREATE OR REPLACE FUNCTION ledgerr.get_gl_account_balance(
    p_gl_account_id UUID,
    p_as_of_date DATE DEFAULT CURRENT_DATE
) RETURNS TABLE (
    account_balance DECIMAL(15,2),
    total_debits DECIMAL(15,2),
    total_credits DECIMAL(15,2),
    transaction_count BIGINT,
    last_activity_date DATE
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        COALESCE(SUM(debit_amount - credit_amount), 0) as account_balance,
        COALESCE(SUM(debit_amount), 0) as total_debits,
        COALESCE(SUM(credit_amount), 0) as total_credits,
        COUNT(*) as transaction_count,
        MAX(entry_date) as last_activity_date
    FROM ledgerr.journal_entry_lines jel
    JOIN ledgerr.journal_entries je ON jel.entry_id = je.entry_id AND jel.entry_date = je.entry_date
    WHERE jel.gl_account_id = p_gl_account_id 
      AND jel.entry_date <= p_as_of_date
      AND je.is_posted = true;
END;
$$ LANGUAGE plpgsql;