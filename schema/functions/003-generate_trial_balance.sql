CREATE OR REPLACE FUNCTION ledgerr.generate_trial_balance(p_as_of_date DATE DEFAULT CURRENT_DATE)
RETURNS TABLE (
    account_code VARCHAR(10),
    account_name VARCHAR(100),
    account_type VARCHAR(20),
    balance DECIMAL(15,2)
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        a.account_code,
        a.account_name,
        a.account_type,
        get_account_balance(a.account_id, p_as_of_date) as balance
    FROM ledgerr.accounts a
    WHERE a.is_active = TRUE
    ORDER BY a.account_code;
END;
$$ LANGUAGE plpgsql;