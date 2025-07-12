#!/bin/bash

# BaaS Happy Path Integration Test Script
# Clean implementation using the 4-function ledger API

set -e  # Exit on any error

BASE_URL="http://localhost:3000"
CONTENT_TYPE="Content-Type: application/json"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "Cleaning up any existing test data..."
echo "====================================="
psql "$DATABASE_URL" -c "DELETE FROM ledgerr.journal_entry_lines;"
psql "$DATABASE_URL" -c "DELETE FROM ledgerr.journal_entries;"
psql "$DATABASE_URL" -c "DELETE FROM ledgerr.accounts;"
echo ""

echo "🏦 Setting up Banking as a Service Test Environment..."
echo "=================================================="

# Predictable UUIDs for orchestration
GL_CUSTOMER_DEPOSITS="11111111-1111-1111-1111-111111111111"
GL_BANK_CASH="22222222-2222-2222-2222-222222222222"
GL_FEE_INCOME="33333333-3333-3333-3333-333333333333"
GL_ACME_CUSTOMER_FUNDS="44444444-4444-4444-4444-444444444444"
GL_CAPITAL_EQUITY="99999999-9999-9999-9999-999999999999"

echo "📊 Step 1: Creating GL Accounts (Chart of Accounts)"
echo "---------------------------------------------------"

# 1. Customer Deposits (Liability - where customer money shows up on our books)
echo "Creating Customer Deposits GL Account..."
curl -s --request POST \
  --url "$BASE_URL/rpc/create_account" \
  --header "$CONTENT_TYPE" \
  --data "{
    \"p_account_code\": \"2100\",
    \"p_account_name\": \"Customer Deposits\",
    \"p_account_type\": \"LIABILITY\",
    \"p_parent_account_id\": null,
    \"p_account_id\": \"$GL_CUSTOMER_DEPOSITS\"
  }" | jq '.'

# 2. Bank Operating Cash (Asset - where we actually hold the money)
echo "Creating Bank Operating Cash GL Account..."
curl -s --request POST \
  --url "$BASE_URL/rpc/create_account" \
  --header "$CONTENT_TYPE" \
  --data "{
    \"p_account_code\": \"1100\",
    \"p_account_name\": \"Bank Operating Cash\",
    \"p_account_type\": \"ASSET\",
    \"p_parent_account_id\": null,
    \"p_account_id\": \"$GL_BANK_CASH\"
  }" | jq '.'

# 3. Fee Income (Revenue - our transaction fees)
echo "Creating Fee Income GL Account..."
curl -s --request POST \
  --url "$BASE_URL/rpc/create_account" \
  --header "$CONTENT_TYPE" \
  --data "{
    \"p_account_code\": \"4100\",
    \"p_account_name\": \"Transaction Fee Income\",
    \"p_account_type\": \"REVENUE\",
    \"p_parent_account_id\": null,
    \"p_account_id\": \"$GL_FEE_INCOME\"
  }" | jq '.'

# 4. Acme Partner Customer Funds (Sub-liability under Customer Deposits)
echo "Creating Acme Partner Customer Funds GL Account..."
curl -s --request POST \
  --url "$BASE_URL/rpc/create_account" \
  --header "$CONTENT_TYPE" \
  --data "{
    \"p_account_code\": \"2101\",
    \"p_account_name\": \"Acme Partner - Customer Funds\",
    \"p_account_type\": \"LIABILITY\",
    \"p_parent_account_id\": \"$GL_CUSTOMER_DEPOSITS\",
    \"p_account_id\": \"$GL_ACME_CUSTOMER_FUNDS\"
  }" | jq '.'

# 5. Bank Capital/Equity (Source of initial funding)
echo "Creating Bank Capital GL Account..."
curl -s --request POST \
  --url "$BASE_URL/rpc/create_account" \
  --header "$CONTENT_TYPE" \
  --data "{
    \"p_account_code\": \"3100\",
    \"p_account_name\": \"Bank Capital\",
    \"p_account_type\": \"EQUITY\",
    \"p_parent_account_id\": null,
    \"p_account_id\": \"$GL_CAPITAL_EQUITY\"
  }" | jq '.'

echo ""
echo "💰 Step 2: Initial Bank Funding Transaction"
echo "--------------------------------------------"

# Fund the bank with initial capital using journal entry
echo "Recording initial bank capitalization..."
curl -s --request POST \
  --url "$BASE_URL/rpc/record_journal_entry" \
  --header "$CONTENT_TYPE" \
  --data "{
    \"p_entry_date\": \"$(date +%Y-%m-%d)\",
    \"p_description\": \"Initial bank capitalization\",
    \"p_journal_lines\": [
      {
        \"account_id\": \"$GL_BANK_CASH\",
        \"debit_amount\": 100000.00,
        \"credit_amount\": 0,
        \"description\": \"Initial cash funding\"
      },
      {
        \"account_id\": \"$GL_CAPITAL_EQUITY\",
        \"debit_amount\": 0,
        \"credit_amount\": 100000.00,
        \"description\": \"Bank capital investment\"
      }
    ],
    \"p_reference_number\": \"BANK-CAP-001\",
    \"p_created_by\": \"setup_script\"
  }" | jq '.'

echo ""
echo "💳 Step 3: Customer Deposit Transaction"
echo "---------------------------------------"

# Customer deposits $500 into their account
echo "Recording customer deposit..."
curl -s --request POST \
  --url "$BASE_URL/rpc/record_journal_entry" \
  --header "$CONTENT_TYPE" \
  --data "{
    \"p_entry_date\": \"$(date +%Y-%m-%d)\",
    \"p_description\": \"Customer deposit via Acme partner\",
    \"p_journal_lines\": [
      {
        \"account_id\": \"$GL_BANK_CASH\",
        \"debit_amount\": 500.00,
        \"credit_amount\": 0,
        \"description\": \"Cash received from customer\"
      },
      {
        \"account_id\": \"$GL_ACME_CUSTOMER_FUNDS\",
        \"debit_amount\": 0,
        \"credit_amount\": 500.00,
        \"description\": \"Customer funds liability\"
      }
    ],
    \"p_reference_number\": \"CUST-DEP-001\",
    \"p_created_by\": \"acme_api\"
  }" | jq '.'

echo ""
echo "💸 Step 4: Transaction Fee Processing"
echo "-------------------------------------"

# Charge a $2.50 transaction fee
echo "Recording transaction fee..."
curl -s --request POST \
  --url "$BASE_URL/rpc/record_journal_entry" \
  --header "$CONTENT_TYPE" \
  --data "{
    \"p_entry_date\": \"$(date +%Y-%m-%d)\",
    \"p_description\": \"Transaction processing fee\",
    \"p_journal_lines\": [
      {
        \"account_id\": \"$GL_ACME_CUSTOMER_FUNDS\",
        \"debit_amount\": 2.50,
        \"credit_amount\": 0,
        \"description\": \"Fee charged to customer\"
      },
      {
        \"account_id\": \"$GL_FEE_INCOME\",
        \"debit_amount\": 0,
        \"credit_amount\": 2.50,
        \"description\": \"Transaction fee revenue\"
      }
    ],
    \"p_reference_number\": \"FEE-001\",
    \"p_created_by\": \"fee_processor\"
  }" | jq '.'

echo ""
echo "💱 Step 5: Customer Transfer Transaction"
echo "---------------------------------------"

# Customer transfers $100 to another account
echo "Recording customer transfer..."
curl -s --request POST \
  --url "$BASE_URL/rpc/record_journal_entry" \
  --header "$CONTENT_TYPE" \
  --data "{
    \"p_entry_date\": \"$(date +%Y-%m-%d)\",
    \"p_description\": \"Customer transfer to external account\",
    \"p_journal_lines\": [
      {
        \"account_id\": \"$GL_ACME_CUSTOMER_FUNDS\",
        \"debit_amount\": 100.00,
        \"credit_amount\": 0,
        \"description\": \"Transfer out from customer account\"
      },
      {
        \"account_id\": \"$GL_BANK_CASH\",
        \"debit_amount\": 0,
        \"credit_amount\": 100.00,
        \"description\": \"Cash sent to external account\"
      }
    ],
    \"p_reference_number\": \"TRANSFER-001\",
    \"p_created_by\": \"transfer_processor\"
  }" | jq '.'

echo ""
echo "🔄 Step 6: Testing Reversal Function"
echo "------------------------------------"

# First, let's get the entry ID from the transfer transaction
echo "Creating a test transaction to reverse..."
REVERSAL_TEST_RESPONSE=$(curl -s --request POST \
  --url "$BASE_URL/rpc/record_journal_entry" \
  --header "$CONTENT_TYPE" \
  --data "{
    \"p_entry_date\": \"$(date +%Y-%m-%d)\",
    \"p_description\": \"Test transaction for reversal\",
    \"p_journal_lines\": [
      {
        \"account_id\": \"$GL_ACME_CUSTOMER_FUNDS\",
        \"debit_amount\": 25.00,
        \"credit_amount\": 0,
        \"description\": \"Test debit\"
      },
      {
        \"account_id\": \"$GL_FEE_INCOME\",
        \"debit_amount\": 0,
        \"credit_amount\": 25.00,
        \"description\": \"Test credit\"
      }
    ],
    \"p_reference_number\": \"TEST-REV-001\",
    \"p_created_by\": \"test_script\"
  }")

# Extract the entry ID (assuming your API returns it)
TEST_ENTRY_ID=$(echo $REVERSAL_TEST_RESPONSE | jq -r '.')
echo "Test transaction created with ID: $TEST_ENTRY_ID"

# Now reverse it
echo "Reversing the test transaction..."
curl -s --request POST \
   --url "$BASE_URL/rpc/create_reversal_entry" \
   --header "$CONTENT_TYPE" \
   --data "{
     \"p_original_entry_id\": \"$TEST_ENTRY_ID\",
     \"p_original_entry_date\": \"$(date +%Y-%m-%d)\",
     \"p_reversal_reason\": \"Test reversal for integration testing\",
     \"p_created_by\": \"test_script\"
   }" | jq '.'

echo ""
echo "📊 Step 7: Checking Account Balances & Assertions"
echo "================================================="

# Function to assert balance
assert_balance() {
    local account_name="$1"
    local account_id="$2"
    local expected_balance="$3"
    local description="$4"
    
    echo "Checking $account_name balance..."
    local balance_response=$(curl -s --request POST \
        --url "$BASE_URL/rpc/get_account_balance" \
        --header "$CONTENT_TYPE" \
        --header "Accept: application/vnd.pgrst.object+json" \
        --data "{\"p_account_id\": \"$account_id\"}")
    
    local actual_balance=$(echo "$balance_response" | jq -r '.account_balance')
    local total_debits=$(echo "$balance_response" | jq -r '.total_debits')
    local total_credits=$(echo "$balance_response" | jq -r '.total_credits')
    local transaction_count=$(echo "$balance_response" | jq -r '.transaction_count')
    
    echo "  Balance: $actual_balance"
    echo "  Debits: $total_debits, Credits: $total_credits"
    echo "  Transaction Count: $transaction_count"
    
    # Check if balance matches expected (using bc for floating point comparison)
    if [[ $(echo "$actual_balance == $expected_balance" | bc -l) -eq 1 ]]; then
        echo -e "  ${GREEN}✅ PASS${NC}: $description"
    else
        echo -e "  ${RED}❌ FAIL${NC}: $description"
        echo -e "  ${RED}Expected: $expected_balance, Got: $actual_balance${NC}"
        return 1
    fi
    echo ""
}

# Calculate expected balances based on transactions
echo "Calculating expected balances..."

# Bank Cash: 100,000 (initial) + 500 (deposit) - 100 (transfer) = 100,400
EXPECTED_BANK_CASH="100400.00"

# Customer Funds: 500 (deposit) - 2.50 (fee) - 100 (transfer) = 397.50
# Note: Liabilities have negative balances in normal accounting
EXPECTED_CUSTOMER_FUNDS="-397.50"

# Fee Income: 2.50 (fee charged)
# Note: Revenue accounts have negative balances (credit balance)
EXPECTED_FEE_INCOME="-2.50"

# Bank Capital: 100,000 (initial capital)
# Note: Equity accounts have negative balances (credit balance)
EXPECTED_BANK_CAPITAL="-100000.00"

echo "Expected balances calculated:"
echo "  Bank Cash: $EXPECTED_BANK_CASH"
echo "  Customer Funds: $EXPECTED_CUSTOMER_FUNDS"
echo "  Fee Income: $EXPECTED_FEE_INCOME"
echo "  Bank Capital: $EXPECTED_BANK_CAPITAL"
echo ""

# Run assertions
FAILED=0

assert_balance "Bank Operating Cash" "$GL_BANK_CASH" "$EXPECTED_BANK_CASH" "Bank cash should reflect initial funding + deposit - transfer" || FAILED=1

assert_balance "Acme Customer Funds" "$GL_ACME_CUSTOMER_FUNDS" "$EXPECTED_CUSTOMER_FUNDS" "Customer funds should reflect deposit - fee - transfer" || FAILED=1

assert_balance "Fee Income" "$GL_FEE_INCOME" "$EXPECTED_FEE_INCOME" "Fee income should reflect transaction fees charged" || FAILED=1

assert_balance "Bank Capital" "$GL_CAPITAL_EQUITY" "$EXPECTED_BANK_CAPITAL" "Bank capital should reflect initial capitalization" || FAILED=1

echo "🧪 Final Results Summary"
echo "========================"

if [[ $FAILED -eq 0 ]]; then
    echo -e "${GREEN}✅ ALL TESTS PASSED!${NC}"
    echo "🚀 Banking system is operational and all balances are correct!"
else
    echo -e "${RED}❌ SOME TESTS FAILED!${NC}"
    echo "🔍 Please review the failed assertions above."
    exit 1
fi

echo ""
echo "🧪 Test UUIDs for further testing:"
echo "================================="
echo "GL Accounts:"
echo "  Customer Deposits:      $GL_CUSTOMER_DEPOSITS"
echo "  Bank Operating Cash:    $GL_BANK_CASH"
echo "  Fee Income:             $GL_FEE_INCOME"
echo "  Acme Customer Funds:    $GL_ACME_CUSTOMER_FUNDS"
echo "  Bank Capital:           $GL_CAPITAL_EQUITY"
echo ""