CREATE OR REPLACE FUNCTION ledgerr.record_audit_log()
RETURNS TRIGGER AS $$
DECLARE
    v_record_id TEXT;
    v_old_record JSONB;
    v_new_record JSONB;
    v_base_table_name TEXT;
BEGIN
    -- Extract base table name from partition name
    -- This handles cases like 'journal_entries_2025_07' -> 'journal_entries'
    v_base_table_name := CASE 
        WHEN TG_TABLE_NAME LIKE 'accounts_%' THEN 'accounts'
        WHEN TG_TABLE_NAME LIKE 'journal_entries_%' THEN 'journal_entries'
        WHEN TG_TABLE_NAME LIKE 'journal_entry_lines_%' THEN 'journal_entry_lines'
        ELSE TG_TABLE_NAME
    END;
    
    -- Determine the primary key value dynamically based on base table name
    CASE v_base_table_name
        WHEN 'accounts' THEN v_record_id := COALESCE(NEW.account_id, OLD.account_id)::TEXT;
        WHEN 'journal_entries' THEN v_record_id := COALESCE(NEW.entry_id, OLD.entry_id)::TEXT;
        WHEN 'journal_entry_lines' THEN v_record_id := COALESCE(NEW.line_id, OLD.line_id)::TEXT;
        ELSE 
            RAISE EXCEPTION 'Audit trigger not configured for table: % (base: %)', TG_TABLE_NAME, v_base_table_name;
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
    INSERT INTO ledgerr.audit_log (
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
        TG_TABLE_NAME, -- Keep the actual partition name for traceability
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