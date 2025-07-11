CREATE OR REPLACE TRIGGER audit_accounts
    AFTER INSERT OR UPDATE OR DELETE ON accounts
    FOR EACH ROW EXECUTE FUNCTION track_table_changes();

CREATE OR REPLACE TRIGGER audit_journal_entries
    AFTER INSERT OR UPDATE OR DELETE ON journal_entries
    FOR EACH ROW EXECUTE FUNCTION track_table_changes();

CREATE OR REPLACE TRIGGER audit_journal_entry_lines
    AFTER INSERT OR UPDATE OR DELETE ON journal_entry_lines
    FOR EACH ROW EXECUTE FUNCTION track_table_changes();

CREATE OR REPLACE TRIGGER audit_payment_accounts
    AFTER INSERT OR UPDATE OR DELETE ON payment_accounts
    FOR EACH ROW EXECUTE FUNCTION track_table_changes();

CREATE OR REPLACE TRIGGER audit_account_balances
    AFTER INSERT OR UPDATE OR DELETE ON account_balances
    FOR EACH ROW EXECUTE FUNCTION track_table_changes();

CREATE OR REPLACE TRIGGER audit_payment_requests
    AFTER INSERT OR UPDATE OR DELETE ON payment_requests
    FOR EACH ROW EXECUTE FUNCTION track_table_changes();
