DO $$
BEGIN
    IF to_regtype('ledgerr_api.journal_line_type') IS NULL THEN
        CREATE TYPE ledgerr_api.journal_line_type AS (
            account_id UUID,
            debit_amount DECIMAL(15,2),
            credit_amount DECIMAL(15,2),
            description TEXT
        );
    END IF;
END$$;