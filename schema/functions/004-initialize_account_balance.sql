CREATE OR REPLACE FUNCTION initialize_account_balance(p_account_id INTEGER)
RETURNS VOID AS $$
BEGIN
    INSERT INTO account_balances (account_id, current_balance, available_balance)
    VALUES (p_account_id, 0.00, 0.00)
    ON CONFLICT (account_id) DO NOTHING;
END;
$$ LANGUAGE plpgsql;
