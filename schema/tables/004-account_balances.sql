CREATE TABLE ledgerr.account_balances (
    account_id UUID NOT NULL REFERENCES ledgerr.accounts(account_id),
    current_balance DECIMAL(15,2) DEFAULT 0.00,
    total_debits DECIMAL(15,2) DEFAULT 0.00,
    total_credits DECIMAL(15,2) DEFAULT 0.00,
    transaction_count BIGINT DEFAULT 0,
    last_transaction_date DATE,
    last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    PRIMARY KEY (account_id)
);

