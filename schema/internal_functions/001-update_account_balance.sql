-- Reusable function to update account balances
CREATE OR REPLACE FUNCTION ledgerr.update_account_balance(
    p_account_id UUID,
    p_debit_amount DECIMAL(15,2) DEFAULT 0,
    p_credit_amount DECIMAL(15,2) DEFAULT 0,
    p_transaction_date DATE DEFAULT CURRENT_DATE
) RETURNS VOID AS $$
DECLARE
    v_net_change DECIMAL(15,2);
BEGIN
    v_net_change := p_debit_amount - p_credit_amount;
    
    -- Update the cached balance (must exist due to 1:1 relationship)
    UPDATE ledgerr.account_balances 
    SET 
        current_balance = current_balance + v_net_change,
        total_debits = total_debits + p_debit_amount,
        total_credits = total_credits + p_credit_amount,
        transaction_count = transaction_count + 1,
        last_transaction_date = GREATEST(COALESCE(last_transaction_date, p_transaction_date), p_transaction_date),
        last_updated = CURRENT_TIMESTAMP
    WHERE account_id = p_account_id;
    
    -- Ensure exactly one row was updated
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Account balance cache record not found for account %. This should never happen.', p_account_id;
    END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER VOLATILE
SET default_transaction_isolation TO 'serializable';