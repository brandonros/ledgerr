CREATE TABLE IF NOT EXISTS ledgerr.journal_entries (
    entry_id UUID DEFAULT uuid_generate_v4(),
    entry_date DATE NOT NULL,
    description TEXT NOT NULL,
    reference_number VARCHAR(50),
    created_by VARCHAR(50),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    is_posted BOOLEAN DEFAULT FALSE,
    
    -- Reversal tracking fields
    entry_type VARCHAR(20) DEFAULT 'REGULAR' CHECK (entry_type IN ('REGULAR', 'REVERSAL', 'ADJUSTMENT')),
    original_entry_id UUID,
    original_entry_date DATE,
    reversed_by_entry_id UUID,
    reversed_by_entry_date DATE,
    reversal_reason TEXT,
    is_reversed BOOLEAN DEFAULT FALSE,

    PRIMARY KEY (entry_id, entry_date),
    
    -- Self-referential foreign key for original entry
    CONSTRAINT fk_original_entry 
        FOREIGN KEY (original_entry_id, original_entry_date) 
        REFERENCES ledgerr.journal_entries(entry_id, entry_date),
    
    -- Self-referential foreign key for reversing entry
    CONSTRAINT fk_reversing_entry 
        FOREIGN KEY (reversed_by_entry_id, reversed_by_entry_date) 
        REFERENCES ledgerr.journal_entries(entry_id, entry_date)
) PARTITION BY RANGE (entry_date);

CREATE INDEX IF NOT EXISTS idx_journal_entries_date_posted ON ledgerr.journal_entries(entry_date, is_posted);
CREATE INDEX IF NOT EXISTS idx_journal_entries_posted_date ON ledgerr.journal_entries (entry_date DESC, entry_id) WHERE is_posted = true;
CREATE INDEX IF NOT EXISTS idx_journal_entries_date_range ON ledgerr.journal_entries(entry_date) WHERE is_posted = TRUE;
CREATE INDEX IF NOT EXISTS idx_journal_entries_reference ON ledgerr.journal_entries(reference_number);

-- New indexes for reversal tracking
CREATE INDEX IF NOT EXISTS idx_journal_entries_original ON ledgerr.journal_entries(original_entry_id, original_entry_date);
CREATE INDEX IF NOT EXISTS idx_journal_entries_reversed_by ON ledgerr.journal_entries(reversed_by_entry_id, reversed_by_entry_date);
CREATE INDEX IF NOT EXISTS idx_journal_entries_type ON ledgerr.journal_entries(entry_type);
CREATE INDEX IF NOT EXISTS idx_journal_entries_is_reversed ON ledgerr.journal_entries(is_reversed) WHERE is_reversed = true;
