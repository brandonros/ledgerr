CREATE OR REPLACE MATERIALIZED VIEW account_balance_summary AS
SELECT 
    account_id,
    SUM(debit_amount - credit_amount) as balance,
    MAX(created_at) as last_transaction_time
FROM journal_entry_lines jel
JOIN journal_entries je ON jel.entry_id = je.entry_id
WHERE je.is_posted = TRUE
GROUP BY account_id;