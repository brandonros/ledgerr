CREATE OR REPLACE FUNCTION ledgerr.get_payment_account_balance(
    p_partner_id UUID,
    p_payment_account_id UUID
) RETURNS TABLE (
    current_balance DECIMAL(15,2),
    available_balance DECIMAL(15,2),
    pending_balance DECIMAL(15,2),
    last_transaction_at TIMESTAMP,
    balance_version BIGINT,
    is_active BOOLEAN
) AS $$
DECLARE
    v_account_record RECORD;
    v_pending_amount DECIMAL(15,2) := 0;
BEGIN
    -- Get account details
    SELECT 
        pa.current_balance,
        pa.last_transaction_at,
        pa.balance_version,
        pa.is_active
    INTO v_account_record
    FROM ledgerr.payment_accounts pa
    WHERE pa.partner_id = p_partner_id 
      AND pa.payment_account_id = p_payment_account_id;
    
    -- Check if account exists
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Payment account not found: partner_id=%, account_id=%', 
                       p_partner_id, p_payment_account_id;
    END IF;
    
    -- Calculate pending transactions (if you have pending status)
    -- This is a placeholder - adjust based on your pending transaction logic
    SELECT COALESCE(SUM(amount), 0)
    INTO v_pending_amount
    FROM ledgerr.payment_account_transactions pat
    WHERE pat.partner_id = p_partner_id 
      AND pat.payment_account_id = p_payment_account_id
      AND pat.status = 'PENDING'; -- Assumes you have a status column
    
    -- Return balance information
    RETURN QUERY SELECT
        v_account_record.current_balance,
        v_account_record.current_balance - v_pending_amount, -- available = current - pending
        v_pending_amount,
        v_account_record.last_transaction_at,
        v_account_record.balance_version,
        v_account_record.is_active;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;