CREATE TABLE IF NOT EXISTS payment_requests (
    idempotency_key VARCHAR(50) PRIMARY KEY,
    payment_id VARCHAR(50) UNIQUE,
    from_account_id VARCHAR(50) REFERENCES payment_accounts(account_id),
    to_account_id VARCHAR(50) REFERENCES payment_accounts(account_id),
    amount DECIMAL(15,2),
    payment_type VARCHAR(20),
    status VARCHAR(20) DEFAULT 'PENDING',
    response_data JSONB,
    journal_entry_id INTEGER REFERENCES journal_entries(entry_id),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    processed_at TIMESTAMP,
    expires_at TIMESTAMP DEFAULT (CURRENT_TIMESTAMP + INTERVAL '24 hours')
);

CREATE INDEX IF NOT EXISTS idx_payment_requests_payment_id ON payment_requests(payment_id);
CREATE INDEX IF NOT EXISTS idx_payment_requests_status ON payment_requests(status, created_at);
CREATE INDEX IF NOT EXISTS idx_payment_requests_expires ON payment_requests(expires_at) WHERE status = 'PENDING';
