-- Generic audit trigger function
CREATE OR REPLACE FUNCTION audit_trigger_function()
RETURNS TRIGGER AS $$
BEGIN
    -- For INSERT operations
    IF TG_OP = 'INSERT' THEN
        INSERT INTO audit_log (
            event_type, table_name, record_id, 
            new_values, changed_by, changed_at
        ) VALUES (
            'INSERT', TG_TABLE_NAME, NEW.account_id,
            to_jsonb(NEW), current_user, CURRENT_TIMESTAMP
        );
        RETURN NEW;
    END IF;
    
    -- For UPDATE operations
    IF TG_OP = 'UPDATE' THEN
        INSERT INTO audit_log (
            event_type, table_name, record_id,
            old_values, new_values, changed_by, changed_at
        ) VALUES (
            'UPDATE', TG_TABLE_NAME, NEW.account_id,
            to_jsonb(OLD), to_jsonb(NEW), current_user, CURRENT_TIMESTAMP
        );
        RETURN NEW;
    END IF;
    
    -- For DELETE operations
    IF TG_OP = 'DELETE' THEN
        INSERT INTO audit_log (
            event_type, table_name, record_id,
            old_values, changed_by, changed_at
        ) VALUES (
            'DELETE', TG_TABLE_NAME, OLD.account_id,
            to_jsonb(OLD), current_user, CURRENT_TIMESTAMP
        );
        RETURN OLD;
    END IF;
    
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- Create triggers for key tables
CREATE OR REPLACE TRIGGER audit_payment_accounts
    AFTER INSERT OR UPDATE OR DELETE ON payment_accounts
    FOR EACH ROW EXECUTE FUNCTION audit_trigger_function();

CREATE OR REPLACE TRIGGER audit_account_balances
    AFTER INSERT OR UPDATE OR DELETE ON account_balances
    FOR EACH ROW EXECUTE FUNCTION audit_trigger_function();
