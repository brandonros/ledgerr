# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## System Overview

This is a high-performance double-entry bookkeeping system built with PostgreSQL and PostgREST. It implements a ledger with strict accounting principles, designed to handle high-volume concurrent transactions with consistency guarantees.

## Core Architecture

### Database Layer
- **PostgreSQL** with custom extensions (uuid-ossp)
- **Two-schema design**: `ledgerr` (internal) and `ledgerr_api` (public API)
- **Monthly partitioning** on `entry_date` for scalability
- **Balance caching** for performance optimization

### API Layer
- **PostgREST** provides REST API over PostgreSQL functions
- **PgBouncer** for connection pooling (configured for high concurrency)
- **Nginx** as reverse proxy

### Key Tables
- `accounts`: Chart of accounts with hierarchical structure
- `journal_entries`: Main transaction records (partitioned)
- `journal_entry_lines`: Individual debit/credit lines (partitioned)
- `account_balances`: Cached balance calculations

## Common Development Commands

### Environment Setup
```bash
# Set database connection
export DATABASE_URL="postgres://user:password@localhost:5432/ledgerr"

# For local development with Docker
export DATABASE_URL="postgres://postgres:Test_Password123!@localhost:5432/ledgerr"
```

### Database Operations
```bash
# Initialize/reset database schema
./scripts/migrate.sh [--reset]

# Run PostgREST API server
./scripts/run.sh

# Run comprehensive test suite
./scripts/sanity-test.sh
```

### Docker Operations
```bash
# Start full stack
docker-compose up -d

# View logs
docker-compose logs -f [service_name]

# Stop services
docker-compose down
```

### Performance Testing
```bash
# Write performance test
k6 run k6/write.js

# Read performance test
k6 run k6/read.js
```

## Key Functions (API Endpoints)

### Account Management
- `POST /rpc/create_account` - Create new GL account
- `POST /rpc/get_account_balance` - Get current account balance
- `POST /rpc/calculate_account_balance` - Force balance recalculation

### Transaction Recording
- `POST /rpc/record_journal_entry` - Record double-entry transaction
- `POST /rpc/create_reversal_entry` - Create reversal entry

## Important Implementation Details

### Double-Entry Validation
- All transactions must balance (total debits = total credits)
- Each journal entry line must have exactly one of debit OR credit > 0
- System enforces accounting equation: Assets = Liabilities + Equity

### Idempotency
- All transaction functions support idempotency keys
- Duplicate requests with same key return original result
- Critical for reliable operation under high load

### Concurrency Handling
- Uses SERIALIZABLE isolation level
- Aggressive timeouts (200ms lock, 500ms statement)
- Designed to handle high-contention scenarios gracefully
- Balance caching reduces lock contention

### Account Types
- ASSET: Positive balances represent value owned
- LIABILITY: Negative balances represent amounts owed
- EQUITY: Negative balances represent owner's equity
- REVENUE: Negative balances represent income
- EXPENSE: Positive balances represent costs

### Balance Calculation
- Balances are calculated as: `SUM(debit_amount) - SUM(credit_amount)`
- Asset/Expense accounts typically have positive balances
- Liability/Equity/Revenue accounts typically have negative balances

## Database Schema Migration

Schema files are organized in execution order:
1. `extensions/` - PostgreSQL extensions
2. `schemas/` - Schema definitions
3. `types/` - Custom types
4. `tables/` - Table definitions
5. `internal_functions/` - Internal functions
6. `external_functions/` - API functions
7. `partitions/` - Partition setup

## Testing

The test suite validates:
- Double-entry accounting principles
- Transaction integrity under concurrency
- Idempotency handling
- Balance consistency
- System performance under load

Test accounts use predictable UUIDs (e.g., `10000000-0000-0000-0000-000000000000` for Cash).

## Performance Considerations

### Connection Pooling
- PgBouncer configured for transaction-level pooling
- Max 5000 client connections, 1500 backend connections
- Optimized for high-throughput scenarios

### Partitioning Strategy
- Monthly partitions on `entry_date`
- Enables efficient data management and query performance
- Automatic partition pruning for date-range queries

### Balance Caching
- `account_balances` table maintains running totals
- Reduces need for expensive aggregation queries
- Updated atomically with journal entry recording

## Security Notes

- Functions use SECURITY DEFINER for controlled access
- All external functions are in `ledgerr_api` schema
- Internal functions are not directly accessible
- Database credentials are configured via environment variables