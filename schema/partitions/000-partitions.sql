-- Journal Entries Partitions (by month)
CREATE TABLE IF NOT EXISTS ledgerr.journal_entries_2025_07 PARTITION OF ledgerr.journal_entries FOR VALUES FROM ('2025-07-01') TO ('2025-08-01');

-- Journal Entry Lines Partitions (by month)
CREATE TABLE IF NOT EXISTS ledgerr.journal_entry_lines_2025_07 PARTITION OF ledgerr.journal_entry_lines FOR VALUES FROM ('2025-07-01') TO ('2025-08-01');
