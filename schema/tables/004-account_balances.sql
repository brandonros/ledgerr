CREATE TABLE IF NOT EXISTS ledgerr.account_balances (
    account_id UUID,
    current_balance DECIMAL(15,2) DEFAULT 0.00,
    available_balance DECIMAL(15,2) DEFAULT 0.00,
    pending_debits DECIMAL(15,2) DEFAULT 0.00,
    pending_credits DECIMAL(15,2) DEFAULT 0.00,
    last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    version INTEGER DEFAULT 1,
    daily_debit_total DECIMAL(15,2) DEFAULT 0.00,
    daily_credit_total DECIMAL(15,2) DEFAULT 0.00,
    last_daily_reset DATE DEFAULT CURRENT_DATE,
    PRIMARY KEY (account_id),
    CONSTRAINT fk_account_balances_accounts FOREIGN KEY (account_id) REFERENCES ledgerr.accounts(account_id)
) PARTITION BY HASH (account_id);

-- Unique constraint to prevent duplicate account balances
CREATE UNIQUE INDEX IF NOT EXISTS idx_account_balances_account_id ON ledgerr.account_balances(account_id);

-- Index for high-frequency balance lookups
CREATE INDEX IF NOT EXISTS idx_account_balances_lookup ON ledgerr.account_balances(account_id, version) WHERE current_balance > 0;
