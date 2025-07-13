#!/bin/bash

# Define colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

cleanup_test_data() {
    echo "Cleaning up existing test data..."
    if ! psql "$DATABASE_URL" -c "DELETE FROM ledgerr.journal_entry_lines;" 2>/dev/null; then
        echo -e "${RED}Warning: Could not clean journal_entry_lines${NC}"
    fi

    if ! psql "$DATABASE_URL" -c "DELETE FROM ledgerr.journal_entries;" 2>/dev/null; then
        echo -e "${RED}Warning: Could not clean journal_entries${NC}"
    fi

    if ! psql "$DATABASE_URL" -c "DELETE FROM ledgerr.account_balances;" 2>/dev/null; then
        echo -e "${RED}Warning: Could not clean account_balances${NC}"
    fi

    if ! psql "$DATABASE_URL" -c "DELETE FROM ledgerr.accounts;" 2>/dev/null; then
        echo -e "${RED}Warning: Could not clean accounts${NC}"
    fi

    if ! psql "$DATABASE_URL" -c "DELETE FROM ledgerr.audit_log;" 2>/dev/null; then
        echo -e "${RED}Warning: Could not clean audit_log${NC}"
    fi
}

cleanup_test_data
