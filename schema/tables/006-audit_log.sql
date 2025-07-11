CREATE TABLE IF NOT EXISTS ledgerr.audit_log (
    log_id SERIAL,
    event_type VARCHAR(50) NOT NULL,
    table_name VARCHAR(50) NOT NULL,
    record_id INTEGER NOT NULL,
    old_values JSONB,
    new_values JSONB,
    changed_by VARCHAR(50) NOT NULL,
    changed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    ip_address INET,
    user_agent TEXT,
    session_id VARCHAR(50),
    PRIMARY KEY (log_id, changed_at)
) PARTITION BY RANGE (changed_at);

CREATE INDEX IF NOT EXISTS idx_audit_log_table_record ON ledgerr.audit_log(table_name, record_id);
CREATE INDEX IF NOT EXISTS idx_audit_log_timestamp ON ledgerr.audit_log(changed_at DESC);
