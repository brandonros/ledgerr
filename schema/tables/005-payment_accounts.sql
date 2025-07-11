CREATE TABLE IF NOT EXISTS ledgerr.payment_accounts (
    payment_account_id UUID DEFAULT uuid_generate_v4(),
    external_account_id VARCHAR(50) NOT NULL,
    partner_id UUID NOT NULL REFERENCES ledgerr.partners(partner_id),
    
    -- Account details
    account_holder_name VARCHAR(100) NOT NULL,
    account_type VARCHAR(20) NOT NULL CHECK (account_type IN ('CHECKING', 'SAVINGS', 'PREPAID', 'MERCHANT')),
    gl_account_id UUID NOT NULL REFERENCES ledgerr.gl_accounts(gl_account_id),
    
    -- Embedded balances
    current_balance DECIMAL(15,2) DEFAULT 0.00,
    available_balance DECIMAL(15,2) DEFAULT 0.00,
    pending_debits DECIMAL(15,2) DEFAULT 0.00,
    pending_credits DECIMAL(15,2) DEFAULT 0.00,
    
    -- Daily tracking
    daily_limit DECIMAL(15,2) DEFAULT 5000.00,
    monthly_limit DECIMAL(15,2) DEFAULT 50000.00,
    daily_debit_total DECIMAL(15,2) DEFAULT 0.00,
    daily_credit_total DECIMAL(15,2) DEFAULT 0.00,
    last_daily_reset DATE DEFAULT CURRENT_DATE,
    
    -- Operational
    is_active BOOLEAN DEFAULT TRUE,
    risk_level VARCHAR(10) DEFAULT 'LOW' CHECK (risk_level IN ('LOW', 'MEDIUM', 'HIGH')),
    last_transaction_at TIMESTAMP,
    balance_version BIGINT DEFAULT 1,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    -- Composite PK required for partitioning
    PRIMARY KEY (partner_id, payment_account_id),
    
    -- All unique constraints must include partition key
    UNIQUE (partner_id, external_account_id)
    
) PARTITION BY HASH (partner_id);

CREATE INDEX IF NOT EXISTS idx_payment_accounts_external_active 
ON ledgerr.payment_accounts (external_account_id) WHERE is_active = true;

CREATE INDEX IF NOT EXISTS idx_payment_accounts_partner_active 
ON ledgerr.payment_accounts (partner_id) WHERE is_active = true;