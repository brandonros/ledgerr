CREATE OR REPLACE FUNCTION ledgerr.initialize_account_balance(p_account_id INTEGER)
RETURNS VOID AS $$
DECLARE
    v_isolation_level TEXT;
BEGIN
    -- Require SERIALIZABLE isolation
    SELECT current_setting('transaction_isolation') INTO v_isolation_level;
    IF v_isolation_level != 'serializable' THEN
        RAISE EXCEPTION 'Payment processing requires SERIALIZABLE isolation level, current level is: %', v_isolation_level;
    END IF;

    INSERT INTO ledgerr.account_balances (account_id, current_balance, available_balance)
    VALUES (p_account_id, 0.00, 0.00)
    ON CONFLICT (account_id) DO NOTHING;
END;
$$ LANGUAGE plpgsql;
