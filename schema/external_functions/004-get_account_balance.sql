DO $$
BEGIN
    IF to_regtype('ledgerr_api.account_balance_result') IS NULL THEN
        CREATE TYPE ledgerr_api.account_balance_result AS (
            account_balance DECIMAL(15,2),
            total_debits DECIMAL(15,2),
            total_credits DECIMAL(15,2),
            transaction_count BIGINT,
            last_activity_date DATE
        );
    END IF;
END$$;

CREATE OR REPLACE FUNCTION ledgerr_api.get_account_balance(
    p_account_id UUID,
    p_as_of_date DATE DEFAULT CURRENT_DATE
) RETURNS ledgerr_api.account_balance_result AS $$
DECLARE
    result ledgerr_api.account_balance_result;
BEGIN
    SELECT 
        COALESCE(SUM(jel.debit_amount - jel.credit_amount), 0),
        COALESCE(SUM(jel.debit_amount), 0),
        COALESCE(SUM(jel.credit_amount), 0),
        COUNT(*),
        MAX(jel.entry_date)
    INTO result
    FROM ledgerr.journal_entry_lines jel
    JOIN ledgerr.journal_entries je ON jel.entry_id = je.entry_id AND jel.entry_date = je.entry_date
    WHERE jel.account_id = p_account_id 
      AND jel.entry_date <= p_as_of_date
      AND je.is_posted = true;
    
    RETURN result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE;
