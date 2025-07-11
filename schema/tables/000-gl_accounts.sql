CREATE TABLE IF NOT EXISTS ledgerr.gl_accounts (
    gl_account_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    account_code VARCHAR(10) UNIQUE NOT NULL,
    account_name VARCHAR(100) NOT NULL,
    account_type VARCHAR(20) NOT NULL CHECK (account_type IN ('ASSET', 'LIABILITY', 'EQUITY', 'REVENUE', 'EXPENSE')),
    parent_gl_account_id UUID REFERENCES ledgerr.gl_accounts(gl_account_id),
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);