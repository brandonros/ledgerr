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