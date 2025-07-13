CREATE TABLE IF NOT EXISTS ledgerr.journal_entry_lines (
    line_id UUID DEFAULT uuid_generate_v4(),
    entry_date DATE NOT NULL,
    entry_id UUID NOT NULL,
    account_id UUID NOT NULL REFERENCES ledgerr.accounts(account_id),
    debit_amount DECIMAL(15,2) DEFAULT 0.00,
    credit_amount DECIMAL(15,2) DEFAULT 0.00,
    description TEXT,
    external_account_id VARCHAR(50),
    payment_id VARCHAR(50),
    payment_type VARCHAR(64) CHECK (payment_type IN ('TRANSFER', 'DEPOSIT', 'WITHDRAWAL', 'FEE')),
    payment_network VARCHAR(64),
    settlement_date DATE,
    external_reference VARCHAR(100),
    processing_fee DECIMAL(15,2) DEFAULT 0.00,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (line_id, entry_date),
    CONSTRAINT valid_amount CHECK (
        (debit_amount > 0 AND credit_amount = 0) OR 
        (credit_amount > 0 AND debit_amount = 0)
    ),
    CONSTRAINT fk_journal_entry_lines_journal_entries FOREIGN KEY (entry_id, entry_date) REFERENCES ledgerr.journal_entries(entry_id, entry_date)
) PARTITION BY RANGE (entry_date);

CREATE INDEX IF NOT EXISTS idx_journal_entry_lines_payment_id ON ledgerr.journal_entry_lines(payment_id);
CREATE INDEX IF NOT EXISTS idx_journal_entry_lines_external_account ON ledgerr.journal_entry_lines(external_account_id);

CREATE INDEX IF NOT EXISTS idx_journal_entry_lines_account_balance
ON ledgerr.journal_entry_lines(account_id, entry_date DESC) 
INCLUDE (debit_amount, credit_amount);

CREATE INDEX IF NOT EXISTS idx_journal_entry_lines_join_optimized
ON ledgerr.journal_entry_lines(entry_id, entry_date, account_id)
INCLUDE (debit_amount, credit_amount);