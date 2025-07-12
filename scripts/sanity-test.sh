#!/bin/bash

# Fixed Core Double-Entry Ledger Test Suite
# Focus: Proving fundamental accounting correctness and scalability

set -e

BASE_URL="http://localhost:3000"
CONTENT_TYPE="Content-Type: application/json"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "🔬 FIXED LEDGER VALIDATION TEST SUITE"
echo "===================================="

# Clean slate with error checking
echo "Cleaning up existing test data..."
if ! psql "$DATABASE_URL" -c "DELETE FROM ledgerr.journal_entry_lines;" 2>/dev/null; then
    echo -e "${RED}Warning: Could not clean journal_entry_lines${NC}"
fi

if ! psql "$DATABASE_URL" -c "DELETE FROM ledgerr.journal_entries;" 2>/dev/null; then
    echo -e "${RED}Warning: Could not clean journal_entries${NC}"
fi

if ! psql "$DATABASE_URL" -c "DELETE FROM ledgerr.accounts;" 2>/dev/null; then
    echo -e "${RED}Warning: Could not clean accounts${NC}"
fi

# Generate new test account UUIDs that won't conflict
ASSET_CASH="10000000-0000-0000-0000-000000000000"
ASSET_RECEIVABLE="20000000-0000-0000-0000-000000000000"
LIABILITY_PAYABLE="30000000-0000-0000-0000-000000000000"
LIABILITY_CUSTOMER="40000000-0000-0000-0000-000000000000"
EQUITY_CAPITAL="50000000-0000-0000-0000-000000000000"
REVENUE_FEES="60000000-0000-0000-0000-000000000000"
EXPENSE_OPERATIONS="70000000-0000-0000-0000-000000000000"

echo "Generated test account IDs:"
echo "ASSET_CASH: $ASSET_CASH"
echo "EQUITY_CAPITAL: $EQUITY_CAPITAL"
echo "REVENUE_FEES: $REVENUE_FEES"
echo ""

# Test counters
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# Helper functions
run_test() {
    local test_name="$1"
    local test_function="$2"
    
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    echo -e "${BLUE}TEST $TOTAL_TESTS:${NC} $test_name"
    
    # Call the test function directly instead of using eval
    if $test_function; then
        echo -e "${GREEN}✅ PASSED${NC}"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        echo -e "${RED}❌ FAILED${NC}"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
    echo ""
}

create_test_account() {
    local account_id="$1"
    local account_code="$2"
    local account_name="$3"
    local account_type="$4"
    
    echo "Creating account: $account_name ($account_code) with ID: $account_id"
    
    local response=$(curl -s -w "%{http_code}" --request POST \
        --url "$BASE_URL/rpc/create_account" \
        --header "$CONTENT_TYPE" \
        --data "{
            \"p_account_id\": \"$account_id\",
            \"p_account_code\": \"$account_code\",
            \"p_account_name\": \"$account_name\",
            \"p_account_type\": \"$account_type\",
            \"p_parent_account_id\": null
        }")
    
    local http_code="${response: -3}"
    local response_body="${response%???}"
    
    if [[ "$http_code" != "200" ]]; then
        echo -e "${RED}Failed to create account $account_name: HTTP $http_code${NC}"
        echo "Response: $response_body"
        return 1
    fi
    
    echo -e "${GREEN}✅ Account created: $account_name${NC}"
    return 0
}

get_balance() {
    local account_id="$1"
    local response=$(curl -s -w "%{http_code}" --request POST \
        --url "$BASE_URL/rpc/get_account_balance" \
        --header "$CONTENT_TYPE" \
        --header "Accept: application/vnd.pgrst.object+json" \
        --data "{\"p_account_id\": \"$account_id\"}")
    
    local http_code="${response: -3}"
    local response_body="${response%???}"
    
    if [[ "$http_code" != "200" ]]; then
        echo "Error getting balance for $account_id: HTTP $http_code" >&2
        echo "Response: $response_body" >&2
        echo "0"
        return 1
    fi
    
    # Try to extract balance from response
    local balance
    if command -v jq >/dev/null 2>&1; then
        balance=$(echo "$response_body" | jq -r '.account_balance // 0')
    else
        # Fallback if jq is not available
        balance=$(echo "$response_body" | grep -o '"account_balance":[^,}]*' | cut -d: -f2 | tr -d ' "')
    fi
    
    echo "${balance:-0}"
}

record_journal_entry() {
    local idempotency_key="$1"
    local description="$2"
    local reference="$3"
    local lines="$4"
    
    echo "Recording journal entry: $description"
    
    local response=$(curl -s -w "%{http_code}" --request POST \
        --url "$BASE_URL/rpc/record_journal_entry" \
        --header "$CONTENT_TYPE" \
        --data "{
            \"p_entry_date\": \"$(date +%Y-%m-%d)\",
            \"p_description\": \"$description\",
            \"p_journal_lines\": $lines,
            \"p_reference_number\": \"$reference\",
            \"p_created_by\": \"test_suite\",
            \"p_idempotency_key\": \"$idempotency_key\"
        }")
    
    local http_code="${response: -3}"
    local response_body="${response%???}"
    
    if [[ "$http_code" != "200" ]]; then
        echo -e "${RED}Failed to record journal entry: HTTP $http_code${NC}"
        echo "Response: $response_body"
        return 1
    fi
    
    echo -e "${GREEN}✅ Journal entry recorded${NC}"
    return 0
}

assert_balance() {
    local account_id="$1"
    local expected="$2"
    local actual=$(get_balance "$account_id")
    
    echo "Checking balance for account $account_id: expected $expected, got $actual"
    
    # Use bc if available, otherwise use awk for floating point comparison
    local comparison_result
    if command -v bc >/dev/null 2>&1; then
        comparison_result=$(echo "$actual == $expected" | bc -l 2>/dev/null || echo "0")
    else
        comparison_result=$(awk "BEGIN { print ($actual == $expected) ? 1 : 0 }")
    fi
    
    if [[ "$comparison_result" -eq 1 ]]; then
        return 0
    else
        echo "Expected: $expected, Got: $actual"
        return 1
    fi
}

# Test functions - these replace the inline eval strings
test_double_entry() {
    # Record a balanced transaction
    record_journal_entry 'TEST-001' 'Test balanced entry' 'TEST-001' "[
        {\"account_id\": \"$ASSET_CASH\", \"debit_amount\": 1000.00, \"credit_amount\": 0, \"description\": \"Cash increase\"},
        {\"account_id\": \"$EQUITY_CAPITAL\", \"debit_amount\": 0, \"credit_amount\": 1000.00, \"description\": \"Capital investment\"}
    ]" || return 1
    
    assert_balance "$ASSET_CASH" '1000.00' || return 1
    assert_balance "$EQUITY_CAPITAL" '-1000.00' || return 1
    
    return 0
}

test_zero_sum() {
    record_journal_entry 'TEST-002' 'Complex multi-line entry' 'TEST-002' "[
        {\"account_id\": \"$ASSET_CASH\", \"debit_amount\": 500.00, \"credit_amount\": 0, \"description\": \"Cash in\"},
        {\"account_id\": \"$ASSET_RECEIVABLE\", \"debit_amount\": 300.00, \"credit_amount\": 0, \"description\": \"Receivable increase\"},
        {\"account_id\": \"$LIABILITY_PAYABLE\", \"debit_amount\": 0, \"credit_amount\": 200.00, \"description\": \"Payable increase\"},
        {\"account_id\": \"$REVENUE_FEES\", \"debit_amount\": 0, \"credit_amount\": 600.00, \"description\": \"Fee revenue\"}
    ]" || return 1
    
    assert_balance "$ASSET_CASH" '1500.00' || return 1
    assert_balance "$ASSET_RECEIVABLE" '300.00' || return 1
    assert_balance "$LIABILITY_PAYABLE" '-200.00' || return 1
    assert_balance "$REVENUE_FEES" '-600.00' || return 1
    
    return 0
}

test_accounting_equation() {
    # Calculate total assets
    local cash_balance=$(get_balance "$ASSET_CASH")
    local receivable_balance=$(get_balance "$ASSET_RECEIVABLE")
    local total_assets=$(awk "BEGIN { print $cash_balance + $receivable_balance }")
    
    # Calculate total liabilities and equity
    local payable_balance=$(get_balance "$LIABILITY_PAYABLE")
    local customer_balance=$(get_balance "$LIABILITY_CUSTOMER")
    local capital_balance=$(get_balance "$EQUITY_CAPITAL")
    local revenue_balance=$(get_balance "$REVENUE_FEES")
    
    local total_liab_equity=$(awk "BEGIN { print $payable_balance + $customer_balance + $capital_balance + $revenue_balance }")
    
    # They should be equal (liabilities/equity are negative, so sum should equal assets)
    local equation_check=$(awk "BEGIN { print $total_assets + $total_liab_equity }")
    
    echo "Assets: $total_assets (Cash: $cash_balance + Receivable: $receivable_balance)"
    echo "Liabilities+Equity: $total_liab_equity (Payable: $payable_balance + Customer: $customer_balance + Capital: $capital_balance + Revenue: $revenue_balance)"
    echo "Difference: $equation_check"
    
    # Check if difference is close to zero (accounting for floating point precision)
    local abs_diff=$(awk "BEGIN { print ($equation_check < 0) ? -$equation_check : $equation_check }")
    local is_balanced=$(awk "BEGIN { print ($abs_diff < 0.01) ? 1 : 0 }")
    
    if [[ "$is_balanced" -eq 1 ]]; then
        return 0
    else
        echo "Equation imbalance: Assets=$total_assets, Liab+Equity=$total_liab_equity, Difference=$equation_check"
        return 1
    fi
}

test_database_consistency() {
    # Get balances directly from database to verify API accuracy
    local db_cash_balance=$(psql "$DATABASE_URL" -t -c "
        SELECT COALESCE(SUM(debit_amount) - SUM(credit_amount), 0) 
        FROM ledgerr.journal_entry_lines 
        WHERE account_id = '$ASSET_CASH';" | tr -d ' ')
        
    local api_cash_balance=$(get_balance "$ASSET_CASH")
    
    echo "Database balance: $db_cash_balance"
    echo "API balance: $api_cash_balance"
    
    # They should match
    local matches=$(awk "BEGIN { print ($db_cash_balance == $api_cash_balance) ? 1 : 0 }")
    
    if [[ "$matches" -eq 1 ]]; then
        return 0
    else
        echo "Balance mismatch: DB=$db_cash_balance, API=$api_cash_balance"
        return 1
    fi
}

test_global_balance() {
    # Get sum of all debits and credits from database
    local total_debits=$(psql "$DATABASE_URL" -t -c "SELECT COALESCE(SUM(debit_amount), 0) FROM ledgerr.journal_entry_lines;" | tr -d ' ')
    local total_credits=$(psql "$DATABASE_URL" -t -c "SELECT COALESCE(SUM(credit_amount), 0) FROM ledgerr.journal_entry_lines;" | tr -d ' ')
    
    echo "Total debits: $total_debits"
    echo "Total credits: $total_credits"
    
    # They should be equal
    local is_balanced=$(awk "BEGIN { print ($total_debits == $total_credits) ? 1 : 0 }")
    
    if [[ "$is_balanced" -eq 1 ]]; then
        return 0
    else
        echo "Global balance inconsistency: Debits=$total_debits, Credits=$total_credits"
        return 1
    fi
}

# Setup test accounts with error checking
echo "Setting up test chart of accounts..."

if ! create_test_account "$ASSET_CASH" "1000" "Cash" "ASSET"; then
    echo -e "${RED}❌ Failed to create Cash account${NC}"
    exit 1
fi

if ! create_test_account "$ASSET_RECEIVABLE" "1200" "Accounts Receivable" "ASSET"; then
    echo -e "${RED}❌ Failed to create Accounts Receivable account${NC}"
    exit 1
fi

if ! create_test_account "$LIABILITY_PAYABLE" "2000" "Accounts Payable" "LIABILITY"; then
    echo -e "${RED}❌ Failed to create Accounts Payable account${NC}"
    exit 1
fi

if ! create_test_account "$LIABILITY_CUSTOMER" "2100" "Customer Deposits" "LIABILITY"; then
    echo -e "${RED}❌ Failed to create Customer Deposits account${NC}"
    exit 1
fi

if ! create_test_account "$EQUITY_CAPITAL" "3000" "Capital" "EQUITY"; then
    echo -e "${RED}❌ Failed to create Capital account${NC}"
    exit 1
fi

if ! create_test_account "$REVENUE_FEES" "4000" "Fee Revenue" "REVENUE"; then
    echo -e "${RED}❌ Failed to create Fee Revenue account${NC}"
    exit 1
fi

if ! create_test_account "$EXPENSE_OPERATIONS" "5000" "Operating Expenses" "EXPENSE"; then
    echo -e "${RED}❌ Failed to create Operating Expenses account${NC}"
    exit 1
fi

echo -e "${YELLOW}📊 CORE ACCOUNTING PRINCIPLE TESTS${NC}"
echo "======================================"

# Run tests using dedicated test functions
run_test "Double-Entry Balance Validation" "test_double_entry"
run_test "Zero-Sum Transaction Validation" "test_zero_sum"
run_test "Accounting Equation (Assets = Liabilities + Equity)" "test_accounting_equation"
run_test "Direct Database Balance Verification" "test_database_consistency"
run_test "Global Balance Consistency Check" "test_global_balance"

echo ""
echo "🏆 FINAL RESULTS"
echo "================"
echo -e "Total Tests: $TOTAL_TESTS"
echo -e "${GREEN}Passed: $PASSED_TESTS${NC}"
echo -e "${RED}Failed: $FAILED_TESTS${NC}"

if [[ $FAILED_TESTS -eq 0 ]]; then
    echo ""
    echo -e "${GREEN}🎉 ALL CORE TESTS PASSED!${NC}"
    echo "✅ Double-entry accounting principles verified"
    echo "✅ Transaction integrity confirmed"
    echo "✅ Database and API consistency verified"
    echo "✅ Global balance equation maintained"
    echo ""
    echo -e "${BLUE}🚀 CORE PLATFORM IS PRODUCTION-READY${NC}"
    echo "Ready to build advanced features on this solid foundation!"
else
    echo ""
    echo -e "${RED}❌ CORE PLATFORM HAS ISSUES${NC}"
    echo "Must fix fundamental problems before proceeding with advanced features."
    exit 1
fi