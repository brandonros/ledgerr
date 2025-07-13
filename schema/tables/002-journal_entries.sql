CREATE TABLE IF NOT EXISTS ledgerr.journal_entries (
    entry_id UUID DEFAULT uuid_generate_v4(),
    entry_date DATE NOT NULL,
    description TEXT NOT NULL,
    reference_number VARCHAR(50),
    created_by VARCHAR(50),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    is_posted BOOLEAN DEFAULT FALSE,
    idempotency_key VARCHAR(100) NOT NULL,
    
    -- Reversal tracking fields
    entry_type VARCHAR(64) DEFAULT 'REGULAR' CHECK (entry_type IN ('REGULAR', 'REVERSAL', 'ADJUSTMENT')),
    original_entry_id UUID,
    original_entry_date DATE,
    reversed_by_entry_id UUID,
    reversed_by_entry_date DATE,
    reversal_reason TEXT,
    is_reversed BOOLEAN DEFAULT FALSE,

    PRIMARY KEY (entry_id, entry_date),

    -- Unique constraint must include partition key (entry_date)
    CONSTRAINT uk_journal_entries_idempotency UNIQUE (idempotency_key, entry_date),
    
    -- Self-referential foreign key for original entry
    CONSTRAINT fk_original_entry 
        FOREIGN KEY (original_entry_id, original_entry_date) 
        REFERENCES ledgerr.journal_entries(entry_id, entry_date),
    
    -- Self-referential foreign key for reversing entry
    CONSTRAINT fk_reversing_entry 
        FOREIGN KEY (reversed_by_entry_id, reversed_by_entry_date) 
        REFERENCES ledgerr.journal_entries(entry_id, entry_date)
) PARTITION BY RANGE (entry_date);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_journal_entries_date_posted
ON ledgerr.journal_entries(entry_date, is_posted, entry_id)
WHERE is_posted = true OR is_posted = false;

CREATE INDEX IF NOT EXISTS idx_journal_entries_reference_partial
ON ledgerr.journal_entries(reference_number, entry_date) 
WHERE reference_number IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_journal_entries_idempotency 
ON ledgerr.journal_entries USING hash(idempotency_key);

CREATE INDEX IF NOT EXISTS idx_journal_entries_idempotency_covering
ON ledgerr.journal_entries(idempotency_key, entry_date) 
INCLUDE (entry_id, is_posted, description);

CREATE INDEX IF NOT EXISTS idx_accounts_active_lookup
ON ledgerr.accounts(account_id, is_active) 
WHERE is_active = true;

CREATE INDEX IF NOT EXISTS idx_journal_entries_posting_update
ON ledgerr.journal_entries(entry_id, entry_date, is_posted);

CREATE INDEX IF NOT EXISTS idx_journal_entries_posted_optimized
ON ledgerr.journal_entries(is_posted, entry_date DESC, entry_id) 
WHERE is_posted = true;
