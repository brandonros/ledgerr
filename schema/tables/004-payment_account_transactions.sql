CREATE TABLE IF NOT EXISTS ledgerr.payment_account_transactions (
    transaction_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    payment_account_id UUID NOT NULL REFERENCES ledgerr.payment_accounts(payment_account_id),
    journal_entry_id UUID NOT NULL,
    journal_line_id UUID NOT NULL,
    
    -- Transaction details
    amount DECIMAL(15,2) NOT NULL, -- Signed amount (+credit, -debit)
    running_balance DECIMAL(15,2) NOT NULL,
    transaction_type VARCHAR(20) NOT NULL CHECK (transaction_type IN ('TRANSFER', 'DEPOSIT', 'WITHDRAWAL', 'FEE', 'REVERSAL')),
    
    -- References and metadata
    description TEXT,
    external_reference VARCHAR(50),
    payment_network VARCHAR(20),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    -- Fix the foreign key
    CONSTRAINT fk_payment_account_transactions_journal_line 
    FOREIGN KEY (journal_entry_id, journal_line_id) 
    REFERENCES ledgerr.journal_entry_lines(entry_id, line_id)
) PARTITION BY RANGE (created_at);

CREATE INDEX IF NOT EXISTS idx_payment_account_transactions_account_time 
ON ledgerr.payment_account_transactions(payment_account_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_payment_account_transactions_journal 
ON ledgerr.payment_account_transactions(journal_entry_id, journal_line_id);