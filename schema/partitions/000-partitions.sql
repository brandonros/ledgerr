-- Audit Log Partitions (by month)
CREATE TABLE IF NOT EXISTS ledgerr.audit_log_2025_07 PARTITION OF ledgerr.audit_log FOR VALUES FROM ('2025-07-01') TO ('2025-08-01');

-- Journal Entries Partitions (by month)
CREATE TABLE IF NOT EXISTS ledgerr.journal_entries_2025_07 PARTITION OF ledgerr.journal_entries FOR VALUES FROM ('2025-07-01') TO ('2025-08-01');

-- Journal Entry Lines Partitions (by month)
CREATE TABLE IF NOT EXISTS ledgerr.journal_entry_lines_2025_07 PARTITION OF ledgerr.journal_entry_lines FOR VALUES FROM ('2025-07-01') TO ('2025-08-01');

-- Payment Accounts + Transactions Partitions (by hash)
DO $$
BEGIN
    PERFORM create_hash_partitions('ledgerr.payment_accounts', 16);
    PERFORM create_hash_partitions('ledgerr.payment_account_transactions', 16);
END;
$$ LANGUAGE plpgsql;