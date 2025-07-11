CREATE TABLE IF NOT EXISTS ledgerr.payment_account_transactions (
    transaction_id UUID DEFAULT uuid_generate_v4(),
    partner_id UUID REFERENCES ledgerr.partners(partner_id),
    payment_account_id UUID,
    journal_entry_id UUID NOT NULL,
    journal_line_id UUID NOT NULL,
    entry_date DATE NOT NULL, -- Add this field to match the FK
    
    -- Transaction details
    status VARCHAR(20) DEFAULT 'POSTED' CHECK (status IN ('POSTED', 'PENDING', 'FAILED', 'CANCELLED', 'EXPIRED')),
    amount DECIMAL(15,2) NOT NULL, -- Signed amount (+credit, -debit)
    running_balance DECIMAL(15,2) NOT NULL,
    transaction_type VARCHAR(20) NOT NULL CHECK (transaction_type IN (
        'TRANSFER', 'DEPOSIT', 'WITHDRAWAL', 'FEE', 'REVERSAL',
        'PURCHASE', 'REFUND', 'ADJUSTMENT', 'PAYMENT'
    )),
    
    -- References and metadata
    description TEXT,
    external_reference VARCHAR(50),
    payment_network VARCHAR(20),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    posted_at TIMESTAMP,
    expires_at TIMESTAMP,
    failure_reason TEXT,

    -- primary key
    PRIMARY KEY (partner_id, transaction_id),
    
    -- Foreign keys
    CONSTRAINT fk_payment_account_transactions_journal_line 
    FOREIGN KEY (journal_line_id, entry_date) 
    REFERENCES ledgerr.journal_entry_lines(line_id, entry_date),
    
    CONSTRAINT fk_payment_account_transactions_payment_account 
    FOREIGN KEY (partner_id, payment_account_id) 
    REFERENCES ledgerr.payment_accounts(partner_id, payment_account_id)
) PARTITION BY HASH (partner_id);

CREATE INDEX IF NOT EXISTS idx_payment_account_transactions_account_time 
ON ledgerr.payment_account_transactions(payment_account_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_payment_account_transactions_journal 
ON ledgerr.payment_account_transactions(journal_line_id, entry_date);