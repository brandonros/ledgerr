CREATE OR REPLACE TRIGGER audit_gl_accounts
    AFTER INSERT OR UPDATE OR DELETE ON ledgerr.gl_accounts
    FOR EACH ROW EXECUTE FUNCTION ledgerr.record_audit_log();

CREATE OR REPLACE TRIGGER audit_journal_entries
    AFTER INSERT OR UPDATE OR DELETE ON ledgerr.journal_entries
    FOR EACH ROW EXECUTE FUNCTION ledgerr.record_audit_log();

CREATE OR REPLACE TRIGGER audit_journal_entry_lines
    AFTER INSERT OR UPDATE OR DELETE ON ledgerr.journal_entry_lines
    FOR EACH ROW EXECUTE FUNCTION ledgerr.record_audit_log();

CREATE OR REPLACE TRIGGER audit_payment_accounts
    AFTER INSERT OR UPDATE OR DELETE ON ledgerr.payment_accounts
    FOR EACH ROW EXECUTE FUNCTION ledgerr.record_audit_log();

CREATE OR REPLACE TRIGGER audit_payment_account_transactions
    AFTER INSERT OR UPDATE OR DELETE ON ledgerr.payment_account_transactions
    FOR EACH ROW EXECUTE FUNCTION ledgerr.record_audit_log();
