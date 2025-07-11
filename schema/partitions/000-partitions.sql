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
CREATE TABLE IF NOT EXISTS ledgerr.account_balances_p0 PARTITION OF ledgerr.account_balances FOR VALUES WITH (MODULUS 16, REMAINDER 0);
CREATE TABLE IF NOT EXISTS ledgerr.account_balances_p1 PARTITION OF ledgerr.account_balances FOR VALUES WITH (MODULUS 16, REMAINDER 1);
CREATE TABLE IF NOT EXISTS ledgerr.account_balances_p2 PARTITION OF ledgerr.account_balances FOR VALUES WITH (MODULUS 16, REMAINDER 2);
CREATE TABLE IF NOT EXISTS ledgerr.account_balances_p3 PARTITION OF ledgerr.account_balances FOR VALUES WITH (MODULUS 16, REMAINDER 3);
CREATE TABLE IF NOT EXISTS ledgerr.account_balances_p4 PARTITION OF ledgerr.account_balances FOR VALUES WITH (MODULUS 16, REMAINDER 4);
CREATE TABLE IF NOT EXISTS ledgerr.account_balances_p5 PARTITION OF ledgerr.account_balances FOR VALUES WITH (MODULUS 16, REMAINDER 5);
CREATE TABLE IF NOT EXISTS ledgerr.account_balances_p6 PARTITION OF ledgerr.account_balances FOR VALUES WITH (MODULUS 16, REMAINDER 6);
CREATE TABLE IF NOT EXISTS ledgerr.account_balances_p7 PARTITION OF ledgerr.account_balances FOR VALUES WITH (MODULUS 16, REMAINDER 7);
CREATE TABLE IF NOT EXISTS ledgerr.account_balances_p8 PARTITION OF ledgerr.account_balances FOR VALUES WITH (MODULUS 16, REMAINDER 8);
CREATE TABLE IF NOT EXISTS ledgerr.account_balances_p9 PARTITION OF ledgerr.account_balances FOR VALUES WITH (MODULUS 16, REMAINDER 9);
CREATE TABLE IF NOT EXISTS ledgerr.account_balances_p10 PARTITION OF ledgerr.account_balances FOR VALUES WITH (MODULUS 16, REMAINDER 10);
CREATE TABLE IF NOT EXISTS ledgerr.account_balances_p11 PARTITION OF ledgerr.account_balances FOR VALUES WITH (MODULUS 16, REMAINDER 11);
CREATE TABLE IF NOT EXISTS ledgerr.account_balances_p12 PARTITION OF ledgerr.account_balances FOR VALUES WITH (MODULUS 16, REMAINDER 12);
CREATE TABLE IF NOT EXISTS ledgerr.account_balances_p13 PARTITION OF ledgerr.account_balances FOR VALUES WITH (MODULUS 16, REMAINDER 13);
CREATE TABLE IF NOT EXISTS ledgerr.account_balances_p14 PARTITION OF ledgerr.account_balances FOR VALUES WITH (MODULUS 16, REMAINDER 14);
CREATE TABLE IF NOT EXISTS ledgerr.account_balances_p15 PARTITION OF ledgerr.account_balances FOR VALUES WITH (MODULUS 16, REMAINDER 15);