CREATE TABLE IF NOT EXISTS journal_entries (
    entry_id SERIAL PRIMARY KEY,
    entry_date DATE NOT NULL,
    description TEXT NOT NULL,
    reference_number VARCHAR(50),
    created_by VARCHAR(50),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    is_posted BOOLEAN DEFAULT FALSE
);

CREATE INDEX IF NOT EXISTS idx_journal_entries_date_posted ON journal_entries(entry_date, is_posted);
CREATE INDEX IF NOT EXISTS idx_journal_entries_posted_date ON journal_entries (entry_date DESC, entry_id) WHERE is_posted = true;
CREATE INDEX IF NOT EXISTS idx_journal_entries_reference ON journal_entries(reference_number);