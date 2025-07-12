#!/bin/bash

# BaaS Happy Path Integration Test Script
# Sets up complete chart of accounts and entities needed for transaction testing

set -e  # Exit on any error

BASE_URL="http://localhost:3000"
CONTENT_TYPE="Content-Type: application/json"

echo "🏦 Setting up Banking as a Service Test Environment..."
echo "=================================================="

# Predictable UUIDs for orchestration
GL_CUSTOMER_DEPOSITS="11111111-1111-1111-1111-111111111111"
GL_BANK_CASH="22222222-2222-2222-2222-222222222222"
GL_FEE_INCOME="33333333-3333-3333-3333-333333333333"
GL_ACME_CUSTOMER_FUNDS="44444444-4444-4444-4444-444444444444"
GL_CAPITAL_EQUITY="99999999-9999-9999-9999-999999999999"

PARTNER_ACME="55555555-5555-5555-5555-555555555555"
PARTNER_BANK="66666666-6666-6666-6666-666666666666"

PAYMENT_ACCT_CUSTOMER="77777777-7777-7777-7777-777777777777"
PAYMENT_ACCT_BANK="88888888-8888-8888-8888-888888888888"
PAYMENT_ACCT_CAPITAL="99999999-9999-9999-9999-999999999998"

echo "📊 Step 1: Creating GL Accounts (Chart of Accounts)"
echo "---------------------------------------------------"

# 1. Customer Deposits (Liability - where customer money shows up on our books)
echo "Creating Customer Deposits GL Account..."
curl -s --request POST \
  --url "$BASE_URL/rpc/create_gl_account" \
  --header "$CONTENT_TYPE" \
  --data "{
    \"p_account_code\": \"2100\",
    \"p_account_name\": \"Customer Deposits\",
    \"p_account_type\": \"LIABILITY\",
    \"p_parent_gl_account_id\": null,
    \"p_gl_account_id\": \"$GL_CUSTOMER_DEPOSITS\"
  }" | jq '.'

# 2. Bank Operating Cash (Asset - where we actually hold the money)
echo "Creating Bank Operating Cash GL Account..."
curl -s --request POST \
  --url "$BASE_URL/rpc/create_gl_account" \
  --header "$CONTENT_TYPE" \
  --data "{
    \"p_account_code\": \"1100\",
    \"p_account_name\": \"Bank Operating Cash\",
    \"p_account_type\": \"ASSET\",
    \"p_parent_gl_account_id\": null,
    \"p_gl_account_id\": \"$GL_BANK_CASH\"
  }" | jq '.'

# 3. Fee Income (Revenue - our transaction fees)
echo "Creating Fee Income GL Account..."
curl -s --request POST \
  --url "$BASE_URL/rpc/create_gl_account" \
  --header "$CONTENT_TYPE" \
  --data "{
    \"p_account_code\": \"4100\",
    \"p_account_name\": \"Transaction Fee Income\",
    \"p_account_type\": \"REVENUE\",
    \"p_parent_gl_account_id\": null,
    \"p_gl_account_id\": \"$GL_FEE_INCOME\"
  }" | jq '.'

# 4. Acme Partner Customer Funds (Sub-liability under Customer Deposits)
echo "Creating Acme Partner Customer Funds GL Account..."
curl -s --request POST \
  --url "$BASE_URL/rpc/create_gl_account" \
  --header "$CONTENT_TYPE" \
  --data "{
    \"p_account_code\": \"2101\",
    \"p_account_name\": \"Acme Partner - Customer Funds\",
    \"p_account_type\": \"LIABILITY\",
    \"p_parent_gl_account_id\": \"$GL_CUSTOMER_DEPOSITS\",
    \"p_gl_account_id\": \"$GL_ACME_CUSTOMER_FUNDS\"
  }" | jq '.'

# 5. Bank Capital/Equity (Source of initial funding)
echo "Creating Bank Capital GL Account..."
curl -s --request POST \
  --url "$BASE_URL/rpc/create_gl_account" \
  --header "$CONTENT_TYPE" \
  --data "{
    \"p_account_code\": \"3100\",
    \"p_account_name\": \"Bank Capital\",
    \"p_account_type\": \"EQUITY\",
    \"p_parent_gl_account_id\": null,
    \"p_gl_account_id\": \"$GL_CAPITAL_EQUITY\"
  }" | jq '.'

echo ""
echo "🤝 Step 2: Creating Partners"
echo "----------------------------"

# 6. Create Acme Partner (our BaaS customer)
echo "Creating Acme Financial Services Partner..."
curl -s --request POST \
  --url "$BASE_URL/rpc/create_partner" \
  --header "$CONTENT_TYPE" \
  --data "{
    \"p_partner_name\": \"Acme Financial Services\",
    \"p_partner_type\": \"BUSINESS\",
    \"p_external_partner_id\": \"ACME-001\",
    \"p_partner_id\": \"$PARTNER_ACME\"
  }" | jq '.'

# 7. Create Bank Partner (ourselves - for bank-side accounts)
echo "Creating Bank Partner..."
curl -s --request POST \
  --url "$BASE_URL/rpc/create_partner" \
  --header "$CONTENT_TYPE" \
  --data "{
    \"p_partner_name\": \"Our Bank\",
    \"p_partner_type\": \"BANK\",
    \"p_external_partner_id\": \"BANK-001\",
    \"p_partner_id\": \"$PARTNER_BANK\"
  }" | jq '.'

echo ""
echo "💳 Step 3: Creating Payment Accounts"
echo "------------------------------------"

# 8. Customer Payment Account (maps to Acme Customer Funds GL account)
echo "Creating Customer Payment Account..."
curl -s --request POST \
  --url "$BASE_URL/rpc/create_payment_account" \
  --header "$CONTENT_TYPE" \
  --data "{
    \"p_external_account_id\": \"CUST-001-CHECKING\",
    \"p_partner_id\": \"$PARTNER_ACME\",
    \"p_account_holder_name\": \"John Smith\",
    \"p_account_type\": \"CHECKING\",
    \"p_gl_account_id\": \"$GL_ACME_CUSTOMER_FUNDS\",
    \"p_daily_limit\": 1000.00,
    \"p_monthly_limit\": 10000.00,
    \"p_risk_level\": \"LOW\",
    \"p_payment_account_id\": \"$PAYMENT_ACCT_CUSTOMER\"
  }" | jq '.'

# 9. Bank Cash Account (maps to Bank Operating Cash GL account)
echo "Creating Bank Cash Payment Account..."
curl -s --request POST \
  --url "$BASE_URL/rpc/create_payment_account" \
  --header "$CONTENT_TYPE" \
  --data "{
    \"p_external_account_id\": \"BANK-CASH-001\",
    \"p_partner_id\": \"$PARTNER_BANK\",
    \"p_account_holder_name\": \"Our Bank\",
    \"p_account_type\": \"CHECKING\",
    \"p_gl_account_id\": \"$GL_BANK_CASH\",
    \"p_daily_limit\": 1000000.00,
    \"p_monthly_limit\": 10000000.00,
    \"p_risk_level\": \"LOW\",
    \"p_payment_account_id\": \"$PAYMENT_ACCT_BANK\"
  }" | jq '.'

# 10. Bank Capital Account (source of initial funding)
echo "Creating Bank Capital Payment Account..."
curl -s --request POST \
  --url "$BASE_URL/rpc/create_payment_account" \
  --header "$CONTENT_TYPE" \
  --data "{
    \"p_external_account_id\": \"BANK-CAPITAL-001\",
    \"p_partner_id\": \"$PARTNER_BANK\",
    \"p_account_holder_name\": \"Bank Capital\",
    \"p_account_type\": \"CAPITAL\",
    \"p_gl_account_id\": \"$GL_CAPITAL_EQUITY\",
    \"p_daily_limit\": 10000000.00,
    \"p_monthly_limit\": 100000000.00,
    \"p_risk_level\": \"LOW\",
    \"p_payment_account_id\": \"$PAYMENT_ACCT_CAPITAL\"
  }" | jq '.'

echo ""
echo "💰 Step 4: Funding Bank Cash Account via Transaction"
echo "----------------------------------------------------"

# 11. Fund the Capital account first (this represents the bank's initial equity injection)
echo "Setting initial capital balance (this would normally come from external funding)..."
curl -s --request POST \
  --url "$BASE_URL/rpc/create_balance_adjustment" \
  --header "$CONTENT_TYPE" \
  --data "{
    \"p_gl_account_id\": \"$GL_CAPITAL_EQUITY\",
    \"p_amount\": 100000.00,
    \"p_description\": \"Initial bank capital injection\",
    \"p_external_reference\": \"CAPITAL-INIT-001\"
  }" | jq '.'

# 12. Now transfer from Capital to Bank Operating Cash using execute_transaction
# This ensures both GL and payment account balances are properly synchronized
echo "Transferring capital to bank operating cash account..."
curl -s --request POST \
  --url "$BASE_URL/rpc/execute_transaction" \
  --header "$CONTENT_TYPE" \
  --data "{
    \"p_from_partner_id\": \"$PARTNER_BANK\",
    \"p_from_payment_account_id\": \"$PAYMENT_ACCT_CAPITAL\",
    \"p_to_partner_id\": \"$PARTNER_BANK\",
    \"p_to_payment_account_id\": \"$PAYMENT_ACCT_BANK\",
    \"p_amount\": 100000.00,
    \"p_transaction_type\": \"TRANSFER\",
    \"p_description\": \"Initial bank operating cash funding from capital\",
    \"p_external_reference\": \"BANK-FUND-001\"
  }" | jq '.'

echo ""
echo "✅ Setup Complete! Here are your test UUIDs:"
echo "============================================="
echo "GL Accounts:"
echo "  Customer Deposits:      $GL_CUSTOMER_DEPOSITS"
echo "  Bank Operating Cash:    $GL_BANK_CASH"
echo "  Fee Income:             $GL_FEE_INCOME"
echo "  Acme Customer Funds:    $GL_ACME_CUSTOMER_FUNDS"
echo "  Bank Capital:           $GL_CAPITAL_EQUITY"
echo ""
echo "Partners:"
echo "  Acme Financial:         $PARTNER_ACME"
echo "  Our Bank:               $PARTNER_BANK"
echo ""
echo "Payment Accounts:"
echo "  Customer Account:       $PAYMENT_ACCT_CUSTOMER"
echo "  Bank Cash Account:      $PAYMENT_ACCT_BANK"
echo "  Bank Capital Account:   $PAYMENT_ACCT_CAPITAL"
echo ""
echo "🚀 Ready for transaction testing!"
echo ""
echo "Sample transaction test:"
echo "# Deposit \$100 into customer account (from bank cash)"
echo "curl --request POST \\"
echo "  --url $BASE_URL/rpc/execute_transaction \\"
echo "  --header '$CONTENT_TYPE' \\"
echo "  --data '{"
echo "    \"p_from_partner_id\": \"$PARTNER_BANK\","
echo "    \"p_from_payment_account_id\": \"$PAYMENT_ACCT_BANK\","
echo "    \"p_to_partner_id\": \"$PARTNER_ACME\","
echo "    \"p_to_payment_account_id\": \"$PAYMENT_ACCT_CUSTOMER\","
echo "    \"p_amount\": 100.00,"
echo "    \"p_transaction_type\": \"DEPOSIT\","
echo "    \"p_description\": \"Initial customer deposit\","
echo "    \"p_external_reference\": \"EXT-DEP-001\""
echo "  }'"
echo ""
echo "🔍 Verify balances:"
echo "# Check GL balances"
echo "curl --request GET --url $BASE_URL/gl_accounts | jq '.[] | select(.account_name | contains(\"Cash\") or contains(\"Capital\")) | {account_name, current_balance}'"
echo ""
echo "# Check payment account balances"
echo "curl --request GET --url $BASE_URL/payment_accounts | jq '.[] | {account_holder_name, current_balance}'"