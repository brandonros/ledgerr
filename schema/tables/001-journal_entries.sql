CREATE TABLE IF NOT EXISTS ledgerr.journal_entries (
    entry_id SERIAL PRIMARY KEY,
    entry_date DATE NOT NULL,
    description TEXT NOT NULL,
    reference_number VARCHAR(50),
    created_by VARCHAR(50),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    is_posted BOOLEAN DEFAULT FALSE
) PARTITION BY RANGE (entry_date);

CREATE INDEX IF NOT EXISTS idx_journal_entries_date_posted ON ledgerr.journal_entries(entry_date, is_posted);
CREATE INDEX IF NOT EXISTS idx_journal_entries_posted_date ON ledgerr.journal_entries (entry_date DESC, entry_id) WHERE is_posted = true;
CREATE INDEX IF NOT EXISTS idx_journal_entries_date_range ON ledgerr.journal_entries(entry_date) WHERE is_posted = TRUE;
CREATE INDEX IF NOT EXISTS idx_journal_entries_reference ON ledgerr.journal_entries(reference_number);