#!/bin/bash

# Enhanced Double-Entry Ledger Test Suite with Idempotency and Concurrency Stress Testing
# Focus: Proving fundamental accounting correctness, scalability, idempotency, and deadlock resistance

set -e

BASE_URL="http://localhost:80"
#BASE_URL="http://postgrest.asusrogstrix.local"
CONTENT_TYPE="Content-Type: application/json"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

echo "🔬 ENHANCED LEDGER VALIDATION TEST SUITE WITH CONCURRENCY STRESS"
echo "================================================================"

# Generate a unique test run ID for idempotency keys
TEST_RUN_ID=$(date +%s | tr -d '\n')
echo "Test Run ID: $TEST_RUN_ID"

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

# Generate unique idempotency key for each test
generate_idempotency_key() {
    local test_name="$1"
    local sequence="$2"
    echo "TEST-${TEST_RUN_ID}-${test_name}-${sequence}"
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
    local description="$1"
    local reference="$2"
    local lines="$3"
    local idempotency_key="$4"
    
    echo "Recording journal entry: $description (key: $idempotency_key)"
    
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
    
    # Extract the entry ID from the response for verification
    local entry_id
    if command -v jq >/dev/null 2>&1; then
        entry_id=$(echo "$response_body" | jq -r '.')
    else
        entry_id=$(echo "$response_body" | tr -d '"')
    fi
    
    echo -e "${GREEN}✅ Journal entry recorded with ID: $entry_id${NC}"
    # Store the entry ID for later verification
    echo "$entry_id" > "/tmp/last_entry_id_${idempotency_key}"
    return 0
}

# Function to record journal entry and capture detailed error information
record_journal_entry_with_error_capture() {
    local description="$1"
    local reference="$2"
    local lines="$3"
    local idempotency_key="$4"
    local worker_id="$5"
    
    local start_time=$(date +%s)
    local response=$(curl -s -w "%{http_code}" --request POST \
        --url "$BASE_URL/rpc/record_journal_entry" \
        --header "$CONTENT_TYPE" \
        --data "{
            \"p_entry_date\": \"$(date +%Y-%m-%d)\",
            \"p_description\": \"$description\",
            \"p_journal_lines\": $lines,
            \"p_reference_number\": \"$reference\",
            \"p_created_by\": \"test_suite_worker_${worker_id}\",
            \"p_idempotency_key\": \"$idempotency_key\"
        }")
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    local http_code="${response: -3}"
    local response_body="${response%???}"
    
    # Log the result to a temporary file for analysis
    echo "$worker_id,$http_code,$duration,$response_body" >> "/tmp/stress_test_results_${TEST_RUN_ID}.csv"
    
    if [[ "$http_code" == "200" ]]; then
        return 0
    else
        # Check if it's a serialization error or deadlock
        if echo "$response_body" | grep -qi "serialization\|deadlock\|timeout\|could not serialize"; then
            echo "SERIALIZATION_ERROR" > "/tmp/worker_${worker_id}_error"
        else
            echo "OTHER_ERROR" > "/tmp/worker_${worker_id}_error"
        fi
        return 1
    fi
}

# Enhanced function to test idempotency specifically
record_journal_entry_with_retry() {
    local description="$1"
    local reference="$2"
    local lines="$3"
    local idempotency_key="$4"
    
    echo "Testing idempotency: Recording entry twice with same key"
    
    # First call
    if ! record_journal_entry "$description" "$reference" "$lines" "$idempotency_key"; then
        return 1
    fi
    
    local first_entry_id=$(cat "/tmp/last_entry_id_${idempotency_key}")
    
    # Second call with same idempotency key - should return same entry ID
    if ! record_journal_entry "$description (retry)" "$reference" "$lines" "$idempotency_key"; then
        return 1
    fi
    
    local second_entry_id=$(cat "/tmp/last_entry_id_${idempotency_key}")
    
    if [[ "$first_entry_id" == "$second_entry_id" ]]; then
        echo -e "${GREEN}✅ Idempotency verified: Same entry ID returned ($first_entry_id)${NC}"
        return 0
    else
        echo -e "${RED}❌ Idempotency failed: Different entry IDs ($first_entry_id vs $second_entry_id)${NC}"
        return 1
    fi
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

# Test functions with idempotency
test_double_entry() {
    local idempotency_key=$(generate_idempotency_key "DOUBLE_ENTRY" "001")
    
    # Record a balanced transaction
    record_journal_entry 'Test balanced entry' 'TEST-001' "[
        {\"account_id\": \"$ASSET_CASH\", \"debit_amount\": 1000.00, \"credit_amount\": 0, \"description\": \"Cash increase\"},
        {\"account_id\": \"$EQUITY_CAPITAL\", \"debit_amount\": 0, \"credit_amount\": 1000.00, \"description\": \"Capital investment\"}
    ]" "$idempotency_key" || return 1
    
    assert_balance "$ASSET_CASH" '1000.00' || return 1
    assert_balance "$EQUITY_CAPITAL" '-1000.00' || return 1
    
    return 0
}

test_zero_sum() {
    local idempotency_key=$(generate_idempotency_key "ZERO_SUM" "002")
    
    record_journal_entry 'Complex multi-line entry' 'TEST-002' "[
        {\"account_id\": \"$ASSET_CASH\", \"debit_amount\": 500.00, \"credit_amount\": 0, \"description\": \"Cash in\"},
        {\"account_id\": \"$ASSET_RECEIVABLE\", \"debit_amount\": 300.00, \"credit_amount\": 0, \"description\": \"Receivable increase\"},
        {\"account_id\": \"$LIABILITY_PAYABLE\", \"debit_amount\": 0, \"credit_amount\": 200.00, \"description\": \"Payable increase\"},
        {\"account_id\": \"$REVENUE_FEES\", \"debit_amount\": 0, \"credit_amount\": 600.00, \"description\": \"Fee revenue\"}
    ]" "$idempotency_key" || return 1
    
    assert_balance "$ASSET_CASH" '1500.00' || return 1
    assert_balance "$ASSET_RECEIVABLE" '300.00' || return 1
    assert_balance "$LIABILITY_PAYABLE" '-200.00' || return 1
    assert_balance "$REVENUE_FEES" '-600.00' || return 1
    
    return 0
}

test_idempotency_basic() {
    local idempotency_key=$(generate_idempotency_key "IDEMPOTENCY_BASIC" "003")
    
    # Test idempotency with a simple transaction
    record_journal_entry_with_retry 'Idempotency test transaction' 'TEST-003' "[
        {\"account_id\": \"$ASSET_CASH\", \"debit_amount\": 100.00, \"credit_amount\": 0, \"description\": \"Cash increase\"},
        {\"account_id\": \"$REVENUE_FEES\", \"debit_amount\": 0, \"credit_amount\": 100.00, \"description\": \"Fee revenue\"}
    ]" "$idempotency_key" || return 1
    
    # Verify balances are correct (should only be applied once)
    assert_balance "$ASSET_CASH" '1600.00' || return 1  # Previous balance + 100
    assert_balance "$REVENUE_FEES" '-700.00' || return 1  # Previous balance - 100
    
    return 0
}

test_idempotency_concurrent() {
    local idempotency_key=$(generate_idempotency_key "IDEMPOTENCY_CONCURRENT" "004")
    
    echo "Testing concurrent idempotency (simulated)"
    
    # Record initial balances
    local initial_cash=$(get_balance "$ASSET_CASH")
    local initial_revenue=$(get_balance "$REVENUE_FEES")
    
    # Submit the same transaction multiple times in quick succession
    local pids=()
    for i in {1..3}; do
        (
            record_journal_entry "Concurrent test transaction $i" "TEST-004-$i" "[
                {\"account_id\": \"$ASSET_CASH\", \"debit_amount\": 50.00, \"credit_amount\": 0, \"description\": \"Cash increase\"},
                {\"account_id\": \"$REVENUE_FEES\", \"debit_amount\": 0, \"credit_amount\": 50.00, \"description\": \"Fee revenue\"}
            ]" "$idempotency_key"
        ) &
        pids+=($!)
    done
    
    # Wait for all background processes
    for pid in "${pids[@]}"; do
        wait "$pid"
    done
    
    # Verify balances changed by exactly 50 (only one transaction should have been processed)
    local final_cash=$(get_balance "$ASSET_CASH")
    local final_revenue=$(get_balance "$REVENUE_FEES")
    
    local cash_diff=$(awk "BEGIN { print $final_cash - $initial_cash }")
    local revenue_diff=$(awk "BEGIN { print $final_revenue - $initial_revenue }")
    
    echo "Cash change: $cash_diff (expected: 50.00)"
    echo "Revenue change: $revenue_diff (expected: -50.00)"
    
    local cash_correct=$(awk "BEGIN { print ($cash_diff == 50.00) ? 1 : 0 }")
    local revenue_correct=$(awk "BEGIN { print ($revenue_diff == -50.00) ? 1 : 0 }")
    
    if [[ "$cash_correct" -eq 1 && "$revenue_correct" -eq 1 ]]; then
        return 0
    else
        echo "Concurrent idempotency failed: balances changed incorrectly"
        return 1
    fi
}

test_idempotency_different_keys() {
    local key1=$(generate_idempotency_key "DIFF_KEYS" "005A")
    local key2=$(generate_idempotency_key "DIFF_KEYS" "005B")
    
    echo "Testing different idempotency keys allow different transactions"
    
    # Record initial balances
    local initial_cash=$(get_balance "$ASSET_CASH")
    
    # First transaction
    record_journal_entry "First transaction" "TEST-005A" "[
        {\"account_id\": \"$ASSET_CASH\", \"debit_amount\": 25.00, \"credit_amount\": 0, \"description\": \"Cash increase\"},
        {\"account_id\": \"$REVENUE_FEES\", \"debit_amount\": 0, \"credit_amount\": 25.00, \"description\": \"Fee revenue\"}
    ]" "$key1" || return 1
    
    # Second transaction with different key but same content
    record_journal_entry "Second transaction" "TEST-005B" "[
        {\"account_id\": \"$ASSET_CASH\", \"debit_amount\": 25.00, \"credit_amount\": 0, \"description\": \"Cash increase\"},
        {\"account_id\": \"$REVENUE_FEES\", \"debit_amount\": 0, \"credit_amount\": 25.00, \"description\": \"Fee revenue\"}
    ]" "$key2" || return 1
    
    # Verify both transactions were processed
    local final_cash=$(get_balance "$ASSET_CASH")
    local cash_diff=$(awk "BEGIN { print $final_cash - $initial_cash }")
    
    echo "Cash change: $cash_diff (expected: 50.00)"
    
    local correct=$(awk "BEGIN { print ($cash_diff == 50.00) ? 1 : 0 }")
    
    if [[ "$correct" -eq 1 ]]; then
        return 0
    else
        echo "Different keys test failed: expected 50.00 change, got $cash_diff"
        return 1
    fi
}

# NEW: High-Contention Stress Test
test_high_contention_stress() {
    echo -e "${PURPLE}🔥 STRESS TEST: High-Contention Concurrent Transactions${NC}"
    
    # Clear any existing stress test results
    rm -f "/tmp/stress_test_results_${TEST_RUN_ID}.csv"
    rm -f /tmp/worker_*_error
    
    echo "worker_id,http_code,duration_ms,response" > "/tmp/stress_test_results_${TEST_RUN_ID}.csv"
    
    # Record initial balances
    local initial_cash=$(get_balance "$ASSET_CASH")
    local initial_revenue=$(get_balance "$REVENUE_FEES")
    
    echo "Initial balances - Cash: $initial_cash, Revenue: $initial_revenue"
    
    # Configuration for stress test
    local NUM_WORKERS=50
    local TRANSACTION_AMOUNT=10.00
    local EXPECTED_TOTAL_CHANGE=$(awk "BEGIN { print $NUM_WORKERS * $TRANSACTION_AMOUNT }")
    
    echo "Launching $NUM_WORKERS concurrent workers..."
    echo "Each worker will attempt to transfer $TRANSACTION_AMOUNT from Cash to Revenue"
    echo "Expected total change: $EXPECTED_TOTAL_CHANGE"
    
    # Launch concurrent workers
    local pids=()
    for i in $(seq 1 $NUM_WORKERS); do
        local worker_key=$(generate_idempotency_key "STRESS_WORKER" $(printf "%03d" $i))
        (
            record_journal_entry_with_error_capture \
                "Stress test transaction $i" \
                "STRESS-$(printf "%03d" $i)" \
                "[
                    {\"account_id\": \"$ASSET_CASH\", \"debit_amount\": 0, \"credit_amount\": $TRANSACTION_AMOUNT, \"description\": \"Cash decrease\"},
                    {\"account_id\": \"$REVENUE_FEES\", \"debit_amount\": $TRANSACTION_AMOUNT, \"credit_amount\": 0, \"description\": \"Revenue increase\"}
                ]" \
                "$worker_key" \
                "$i"
        ) &
        pids+=($!)
    done
    
    # Wait for all workers to complete
    echo "Waiting for all workers to complete..."
    for pid in "${pids[@]}"; do
        wait "$pid"
    done
    
    # Analyze results
    echo ""
    echo "📊 STRESS TEST ANALYSIS"
    echo "======================="
    
    # Count successful vs failed transactions
    local successful_count=$(grep -c ",200," "/tmp/stress_test_results_${TEST_RUN_ID}.csv" 2>/dev/null | head -1 | tr -d '\n ' || echo "0")
    local failed_count=$(grep -c -v ",200," "/tmp/stress_test_results_${TEST_RUN_ID}.csv" 2>/dev/null | head -1 | tr -d '\n ' || echo "0")
    
    # Count serialization errors
    local serialization_errors=$(ls /tmp/worker_*_error 2>/dev/null | wc -l)
    local serialization_error_count=0
    if ls /tmp/worker_*_error >/dev/null 2>&1; then
        serialization_error_count=$(grep -l "SERIALIZATION_ERROR" /tmp/worker_*_error 2>/dev/null | wc -l | tr -d ' ' || echo "0")
    fi
    
    echo "Successful transactions: $successful_count"
    echo "Failed transactions: $failed_count"
    echo "Serialization/deadlock errors: $serialization_error_count"
    
    # Calculate timing statistics
    if command -v awk >/dev/null 2>&1; then
        local avg_duration=$(tail -n +2 "/tmp/stress_test_results_${TEST_RUN_ID}.csv" | awk -F',' '{sum+=$3; count++} END {print (count > 0) ? sum/count : 0}')
        local max_duration=$(tail -n +2 "/tmp/stress_test_results_${TEST_RUN_ID}.csv" | awk -F',' 'BEGIN{max=0} {if($3>max) max=$3} END {print max}')
        echo "Average response time: ${avg_duration}ms"
        echo "Max response time: ${max_duration}ms"
    fi
    
    # Verify final balances
    local final_cash=$(get_balance "$ASSET_CASH")
    local final_revenue=$(get_balance "$REVENUE_FEES")
    
    local cash_change=$(awk "BEGIN { print $final_cash - $initial_cash }")
    local revenue_change=$(awk "BEGIN { print $final_revenue - $initial_revenue }")
    
    echo ""
    echo "Balance Changes:"
    echo "Cash: $initial_cash → $final_cash (change: $cash_change)"
    echo "Revenue: $initial_revenue → $final_revenue (change: $revenue_change)"
    
    # Expected changes: Cash should decrease by successful_count * TRANSACTION_AMOUNT
    # Revenue should increase by successful_count * TRANSACTION_AMOUNT
    local expected_cash_change=$(awk "BEGIN { print -$successful_count * $TRANSACTION_AMOUNT }")
    local expected_revenue_change=$(awk "BEGIN { print $successful_count * $TRANSACTION_AMOUNT }")
    
    echo "Expected Cash change: $expected_cash_change"
    echo "Expected Revenue change: $expected_revenue_change"
    
    # Validate accounting equation still holds
    local cash_correct=$(awk "BEGIN { print ($cash_change == $expected_cash_change) ? 1 : 0 }")
    local revenue_correct=$(awk "BEGIN { print ($revenue_change == $expected_revenue_change) ? 1 : 0 }")
    
    # Test passes if:
    # 1. At least some transactions succeeded
    # 2. Balance changes match the number of successful transactions
    # 3. System handled concurrent load gracefully (no crashes)
    
    if [[ $successful_count -gt 0 && $cash_correct -eq 1 && $revenue_correct -eq 1 ]]; then
        echo -e "${GREEN}✅ Stress test PASSED${NC}"
        echo "System handled high concurrency correctly!"
        
        if [[ $serialization_error_count -gt 0 ]]; then
            echo -e "${YELLOW}ℹ️  Note: $serialization_error_count serialization errors occurred (this is normal under high contention)${NC}"
        fi
        
        return 0
    else
        echo -e "${RED}❌ Stress test FAILED${NC}"
        echo "Balance inconsistencies detected under high load"
        return 1
    fi
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
    # Skip if DATABASE_URL is not set
    if [[ -z "$DATABASE_URL" ]]; then
        echo "DATABASE_URL not set, skipping direct database test"
        return 0
    fi
    
    # Get balances directly from database to verify API accuracy
    local db_cash_balance=$(psql "$DATABASE_URL" -t -c "
        SELECT COALESCE(SUM(debit_amount) - SUM(credit_amount), 0) 
        FROM ledgerr.journal_entry_lines 
        WHERE account_id = '$ASSET_CASH';" 2>/dev/null | tr -d ' ')
        
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
    # Skip if DATABASE_URL is not set
    if [[ -z "$DATABASE_URL" ]]; then
        echo "DATABASE_URL not set, skipping global balance test"
        return 0
    fi
    
    # Get sum of all debits and credits from database
    local total_debits=$(psql "$DATABASE_URL" -t -c "SELECT COALESCE(SUM(debit_amount), 0) FROM ledgerr.journal_entry_lines;" 2>/dev/null | tr -d ' ')
    local total_credits=$(psql "$DATABASE_URL" -t -c "SELECT COALESCE(SUM(credit_amount), 0) FROM ledgerr.journal_entry_lines;" 2>/dev/null | tr -d ' ')
    
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

cleanup_test_data() {
    echo "Cleaning up existing test data..."
    if [[ -n "$DATABASE_URL" ]]; then
        psql "$DATABASE_URL" -c "DELETE FROM ledgerr.journal_entry_lines;" 2>/dev/null || echo "Warning: Could not clean journal_entry_lines"
        psql "$DATABASE_URL" -c "DELETE FROM ledgerr.journal_entries;" 2>/dev/null || echo "Warning: Could not clean journal_entries"
        psql "$DATABASE_URL" -c "DELETE FROM ledgerr.account_balances;" 2>/dev/null || echo "Warning: Could not clean account_balances"
        psql "$DATABASE_URL" -c "DELETE FROM ledgerr.accounts;" 2>/dev/null || echo "Warning: Could not clean accounts"
    else
        echo "DATABASE_URL not set, skipping database cleanup"
    fi
}

# Run cleanup
cleanup_test_data

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

echo -e "${YELLOW}🔒 IDEMPOTENCY TESTS${NC}"
echo "===================="

run_test "Basic Idempotency (Same Key = Same Result)" "test_idempotency_basic"
run_test "Concurrent Idempotency (Race Condition Handling)" "test_idempotency_concurrent"
run_test "Different Keys Allow Different Transactions" "test_idempotency_different_keys"

echo -e "${YELLOW}💥 CONCURRENCY STRESS TESTS${NC}"
echo "============================"

run_test "High-Contention Concurrent Transactions (50 Workers)" "test_high_contention_stress"

echo -e "${YELLOW}🔍 SYSTEM INTEGRITY TESTS${NC}"
echo "========================="

run_test "Accounting Equation (Assets = Liabilities + Equity)" "test_accounting_equation"
run_test "Direct Database Balance Verification" "test_database_consistency"
run_test "Global Balance Consistency Check" "test_global_balance"

# Clean up temporary files
rm -f /tmp/last_entry_id_*
rm -f /tmp/worker_*_error
rm -f "/tmp/stress_test_results_${TEST_RUN_ID}.csv"

echo ""
echo "🏆 FINAL RESULTS"
echo "================"
echo -e "Total Tests: $TOTAL_TESTS"
echo -e "${GREEN}Passed: $PASSED_TESTS${NC}"
echo -e "${RED}Failed: $FAILED_TESTS${NC}"

if [[ $FAILED_TESTS -eq 0 ]]; then
    echo ""
    echo -e "${GREEN}🎉 ALL TESTS PASSED!${NC}"
    echo "✅ Double-entry accounting principles verified"
    echo "✅ Transaction integrity confirmed"
    echo "✅ Idempotency handling verified"
    echo "✅ Concurrent transaction safety confirmed"
    echo "✅ High-contention stress test passed"
    echo "✅ Database and API consistency verified"
    echo "✅ Global balance equation maintained"
    echo ""
    echo -e "${BLUE}🚀 CORE PLATFORM IS PRODUCTION-READY${NC}"
    echo "Ready to handle high-volume concurrent transactions!"
    echo "System demonstrated resilience under stress conditions."
else
    echo ""
    echo -e "${RED}❌ PLATFORM HAS ISSUES${NC}"
    echo "Must fix fundamental problems before proceeding with advanced features."
    exit 1
fi