CREATE TABLE IF NOT EXISTS payment_status_log (
    log_id SERIAL,
    payment_id VARCHAR(50) NOT NULL,
    status VARCHAR(20) NOT NULL,
    status_reason TEXT,
    external_reference VARCHAR(100),
    network_response JSONB,
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    processing_time_ms INTEGER,
    PRIMARY KEY (log_id, timestamp)
) PARTITION BY RANGE (timestamp);

CREATE INDEX IF NOT EXISTS idx_payment_status_log_payment_id ON payment_status_log(payment_id, timestamp DESC);
