CREATE TABLE IF NOT EXISTS ledgerr.partners (
    partner_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    partner_name VARCHAR(100) NOT NULL,
    partner_type VARCHAR(20) NOT NULL CHECK (partner_type IN ('INDIVIDUAL', 'BUSINESS', 'FINTECH', 'BANK')),
    external_partner_id VARCHAR(50) UNIQUE,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_partners_external_id ON ledgerr.partners(external_partner_id);
CREATE INDEX IF NOT EXISTS idx_partners_active ON ledgerr.partners(is_active) WHERE is_active = true;