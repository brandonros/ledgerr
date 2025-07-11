CREATE TABLE IF NOT EXISTS journal_entry_lines (
    line_id SERIAL,
    entry_id INTEGER NOT NULL,
    account_id INTEGER NOT NULL,
    debit_amount DECIMAL(15,2) DEFAULT 0.00,
    credit_amount DECIMAL(15,2) DEFAULT 0.00,
    description TEXT,
    external_account_id VARCHAR(50),
    payment_id VARCHAR(50),
    payment_type VARCHAR(20) CHECK (payment_type IN ('TRANSFER', 'DEPOSIT', 'WITHDRAWAL', 'FEE')),
    dempotency_key VARCHAR(50),
    payment_network VARCHAR(20),
    settlement_date DATE,
    external_reference VARCHAR(100),
    processing_fee DECIMAL(15,2) DEFAULT 0.00,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (line_id, created_at),
    CONSTRAINT valid_amount CHECK (
        (debit_amount > 0 AND credit_amount = 0) OR 
        (credit_amount > 0 AND debit_amount = 0)
    )
) PARTITION BY RANGE (created_at);

CREATE INDEX IF NOT EXISTS idx_journal_entry_lines_payment_id ON journal_entry_lines(payment_id);
CREATE INDEX IF NOT EXISTS idx_journal_entry_lines_external_account ON journal_entry_lines(external_account_id);