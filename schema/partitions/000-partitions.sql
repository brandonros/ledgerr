-- Audit Log Partitions (by month)
CREATE TABLE IF NOT EXISTS ledgerr.audit_log_2025_07 PARTITION OF ledgerr.audit_log FOR VALUES FROM ('2025-07-01') TO ('2025-08-01');

-- Journal Entries Partitions (by month)
CREATE TABLE IF NOT EXISTS ledgerr.journal_entries_2025_07 PARTITION OF ledgerr.journal_entries FOR VALUES FROM ('2025-07-01') TO ('2025-08-01');

-- Journal Entry Lines Partitions (by month)
CREATE TABLE IF NOT EXISTS ledgerr.journal_entry_lines_2025_07 PARTITION OF ledgerr.journal_entry_lines FOR VALUES FROM ('2025-07-01') TO ('2025-08-01');

-- Payment Requests Partitions (by month)
CREATE TABLE IF NOT EXISTS ledgerr.payment_requests_2025_07 PARTITION OF ledgerr.payment_requests FOR VALUES FROM ('2025-07-01') TO ('2025-08-01');

-- Payment Status Log Partitions (by month)
CREATE TABLE IF NOT EXISTS ledgerr.payment_status_log_2025_07 PARTITION OF ledgerr.payment_status_log FOR VALUES FROM ('2025-07-01') TO ('2025-08-01');

-- Daily Balance Snapshots Partitions (by month)
CREATE TABLE IF NOT EXISTS ledgerr.daily_balance_snapshots_2025_07 PARTITION OF ledgerr.daily_balance_snapshots FOR VALUES FROM ('2025-07-01') TO ('2025-08-01');

-- Account Balances Hash Partitions (0-15 for better distribution)
SELECT create_hash_partitions('ledgerr.account_balances', 16);

-- Payment Accounts Hash Partitions (0-15 for better distribution)
SELECT create_hash_partitions('ledgerr.payment_accounts', 16);

