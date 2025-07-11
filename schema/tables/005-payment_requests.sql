CREATE TABLE IF NOT EXISTS ledgerr.payment_requests (
    idempotency_key UUID DEFAULT uuid_generate_v4(),
    payment_id VARCHAR(50),
    external_account_id VARCHAR(50),
    entry_date DATE NOT NULL,
    from_payment_account_id UUID,
    to_payment_account_id UUID,
    amount DECIMAL(15,2),
    payment_type VARCHAR(20),
    status VARCHAR(20) DEFAULT 'PENDING',
    response_data JSONB,
    journal_entry_id UUID,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    processed_at TIMESTAMP,
    expires_at TIMESTAMP DEFAULT (CURRENT_TIMESTAMP + INTERVAL '24 hours'),

    PRIMARY KEY (idempotency_key, created_at),
    UNIQUE (payment_id, created_at),
    
    CONSTRAINT fk_payment_requests_journal_entries FOREIGN KEY (journal_entry_id, entry_date) REFERENCES ledgerr.journal_entries(entry_id, entry_date),
    CONSTRAINT fk_payment_requests_from_payment_accounts FOREIGN KEY (external_account_id, from_payment_account_id) REFERENCES ledgerr.payment_accounts(external_account_id, payment_account_id),
    CONSTRAINT fk_payment_requests_to_payment_accounts FOREIGN KEY (external_account_id, to_payment_account_id) REFERENCES ledgerr.payment_accounts(external_account_id, payment_account_id)
) PARTITION BY RANGE (created_at);

CREATE INDEX IF NOT EXISTS idx_payment_requests_payment_id ON ledgerr.payment_requests(payment_id);
CREATE INDEX IF NOT EXISTS idx_payment_requests_status ON ledgerr.payment_requests(status, created_at);
CREATE INDEX IF NOT EXISTS idx_payment_requests_expires ON ledgerr.payment_requests(expires_at) WHERE status = 'PENDING';
CREATE INDEX IF NOT EXISTS idx_payment_requests_payment_accounts ON ledgerr.payment_requests(from_payment_account_id, to_payment_account_id);