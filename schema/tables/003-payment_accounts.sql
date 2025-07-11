CREATE TABLE IF NOT EXISTS ledgerr.payment_accounts (
    payment_account_id SERIAL PRIMARY KEY,
    external_account_id VARCHAR(50) UNIQUE NOT NULL,
    account_holder_name VARCHAR(100) NOT NULL,
    account_type VARCHAR(20) NOT NULL CHECK (account_type IN ('CHECKING', 'SAVINGS', 'PREPAID', 'MERCHANT')),
    daily_limit DECIMAL(15,2) DEFAULT 5000.00,
    monthly_limit DECIMAL(15,2) DEFAULT 50000.00,
    is_active BOOLEAN DEFAULT TRUE,
    risk_level VARCHAR(10) DEFAULT 'LOW' CHECK (risk_level IN ('LOW', 'MEDIUM', 'HIGH')),
    last_transaction_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    version INTEGER DEFAULT 1
) PARTITION BY HASH (payment_account_id);

CREATE INDEX IF NOT EXISTS idx_payment_accounts_external_active ON ledgerr.payment_accounts (external_account_id) WHERE is_active = true;

-- TODO: gl_asset_account_id BIGINT NOT NULL REFERENCES ledgerr.accounts(account_id),
-- TODO: gl_liability_account_id BIGINT NOT NULL REFERENCES ledgerr.accounts(account_id),
    