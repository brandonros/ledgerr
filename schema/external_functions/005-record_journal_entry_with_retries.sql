CREATE OR REPLACE FUNCTION ledgerr_api.record_journal_entry_with_retries(
    p_entry_date DATE,
    p_description TEXT,
    p_journal_lines ledgerr_api.journal_line_type[],
    p_idempotency_key VARCHAR(100),
    p_reference_number VARCHAR(50) DEFAULT NULL,
    p_created_by VARCHAR(50) DEFAULT 'system'
) RETURNS UUID AS $$
DECLARE
    v_entry_id UUID;
    v_attempt INTEGER := 1;
    v_delay_ms INTEGER;
    v_error_code TEXT;
    v_error_message TEXT;
    v_error_hint TEXT;
    v_max_retries INTEGER := 10;
    v_base_delay_ms INTEGER := 1;
BEGIN
    WHILE v_attempt <= v_max_retries LOOP
        BEGIN
            -- Call the original function
            SELECT ledgerr_api.record_journal_entry(
                p_entry_date,
                p_description,
                p_journal_lines,
                p_idempotency_key,
                p_reference_number,
                p_created_by
            ) INTO v_entry_id;
            
            -- Success! Return the entry ID
            RETURN v_entry_id;
            
        EXCEPTION
            WHEN OTHERS THEN
                -- Capture error details
                GET STACKED DIAGNOSTICS 
                    v_error_code = RETURNED_SQLSTATE,
                    v_error_message = MESSAGE_TEXT,
                    v_error_hint = PG_EXCEPTION_HINT;
                
                -- Only retry on specific transient errors
                IF v_error_message IN (
                    'SERIALIZATION_CONFLICT',
                    'LOCK_TIMEOUT', 
                    'STATEMENT_TIMEOUT',
                    'CONCURRENT_PROCESSING'
                ) THEN
                    -- This is a retryable error
                    IF v_attempt < v_max_retries THEN
                        -- Minimal delay with tiny jitter: 2-5ms
                        v_delay_ms := v_base_delay_ms + (random() * 3)::INTEGER;
                        
                        -- Quick sleep (2-5ms)
                        PERFORM pg_sleep(v_delay_ms / 1000.0);
                        
                        v_attempt := v_attempt + 1;
                        CONTINUE;
                    ELSE
                        -- Max retries exceeded
                        RAISE EXCEPTION 'MAX_RETRIES_EXCEEDED: % (after % attempts)', 
                                      v_error_message, v_max_retries
                              USING HINT = v_error_hint;
                    END IF;
                ELSE
                    -- Non-retryable error - re-raise immediately
                    RAISE EXCEPTION 'NON_RETRYABLE_ERROR: %', v_error_message
                          USING HINT = v_error_hint;
                END IF;
        END;
    END LOOP;
    
    -- Should never reach here
    RAISE EXCEPTION 'UNEXPECTED_ERROR: Retry loop completed without success or failure';
END;
$$ LANGUAGE plpgsql SECURITY DEFINER VOLATILE
SET default_transaction_isolation TO 'serializable';
