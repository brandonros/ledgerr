CREATE OR REPLACE FUNCTION track_table_changes()
RETURNS TRIGGER AS $$
DECLARE
    v_record_id TEXT;
    v_old_record JSONB;
    v_new_record JSONB;
BEGIN
    -- Determine the primary key value dynamically
    CASE TG_TABLE_NAME
        WHEN 'accounts' THEN v_record_id := COALESCE(NEW.account_id, OLD.account_id)::TEXT;
        WHEN 'payment_accounts' THEN v_record_id := COALESCE(NEW.account_id, OLD.account_id)::TEXT;
        WHEN 'account_balances' THEN v_record_id := COALESCE(NEW.account_id, OLD.account_id)::TEXT;
        WHEN 'journal_entries' THEN v_record_id := COALESCE(NEW.entry_id, OLD.entry_id)::TEXT;
        WHEN 'journal_entry_lines' THEN v_record_id := COALESCE(NEW.line_id, OLD.line_id)::TEXT;
        WHEN 'payment_requests' THEN v_record_id := COALESCE(NEW.idempotency_key, OLD.idempotency_key)::TEXT;
        WHEN 'payment_status_log' THEN v_record_id := COALESCE(NEW.log_id, OLD.log_id)::TEXT;
        ELSE v_record_id := 'unknown';
    END CASE;
    
    -- Handle different operation types
    CASE TG_OP
        WHEN 'INSERT' THEN
            v_new_record := to_jsonb(NEW);
            v_old_record := NULL;
        WHEN 'UPDATE' THEN
            v_new_record := to_jsonb(NEW);
            v_old_record := to_jsonb(OLD);
        WHEN 'DELETE' THEN
            v_new_record := NULL;
            v_old_record := to_jsonb(OLD);
    END CASE;
    
    -- Insert audit record
    INSERT INTO audit_log (
        event_type, 
        table_name, 
        record_id, 
        old_values, 
        new_values, 
        changed_by, 
        changed_at,
        ip_address,
        session_id
    ) VALUES (
        TG_OP, 
        TG_TABLE_NAME, 
        v_record_id,
        v_old_record,
        v_new_record,
        current_user, 
        CURRENT_TIMESTAMP,
        inet_client_addr(),
        current_setting('application_name', true)
    );
    
    -- Return appropriate record
    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    ELSE
        RETURN NEW;
    END IF;
END;
$$ LANGUAGE plpgsql;