CREATE TABLE IF NOT EXISTS ledgerr.daily_balance_snapshots (
    snapshot_date DATE NOT NULL,
    account_id UUID NOT NULL REFERENCES ledgerr.accounts(account_id),
    opening_balance DECIMAL(15,2) NOT NULL,
    closing_balance DECIMAL(15,2) NOT NULL,
    total_debits DECIMAL(15,2) DEFAULT 0.00,
    total_credits DECIMAL(15,2) DEFAULT 0.00,
    transaction_count INTEGER DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (snapshot_date, account_id)
) PARTITION BY RANGE (snapshot_date);

CREATE INDEX IF NOT EXISTS idx_daily_balance_snapshots_account_date 
ON ledgerr.daily_balance_snapshots(account_id, snapshot_date DESC);