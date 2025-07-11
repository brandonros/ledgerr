CREATE MATERIALIZED VIEW account_balance_summary AS
SELECT 
    jel.account_id,
    a.account_code,
    a.account_name,
    a.account_type,
    CASE 
        WHEN a.account_type IN ('ASSET', 'EXPENSE') THEN
            SUM(jel.debit_amount - jel.credit_amount)
        ELSE
            SUM(jel.credit_amount - jel.debit_amount)
    END as balance,
    COUNT(*) as transaction_count,
    MAX(jel.created_at) as last_transaction_time
FROM journal_entry_lines jel
JOIN journal_entries je ON jel.entry_id = je.entry_id
JOIN accounts a ON jel.account_id = a.account_id
WHERE je.is_posted = TRUE
GROUP BY jel.account_id, a.account_code, a.account_name, a.account_type;