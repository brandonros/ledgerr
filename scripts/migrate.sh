#!/bin/bash

set -euo pipefail

# Check for --reset flag
RESET_DB=false
if [[ "${1:-}" == "--reset" ]]; then
    RESET_DB=true
    echo "Reset flag detected - will drop and recreate database"
fi

# Handle database reset if requested
if [[ "$RESET_DB" == true ]]; then
    echo "Dropping and recreating database 'ledgerr'..."

    # Terminate all connections to the database
    psql -v ON_ERROR_STOP=1 "$BASE_DATABASE_URL" -c "SELECT pg_terminate_backend(pg_stat_activity.pid) FROM pg_stat_activity WHERE pg_stat_activity.datname = 'ledgerr' AND pid <> pg_backend_pid();"
    
    # Drop the database (connecting to postgres)
    psql -v ON_ERROR_STOP=1 "$BASE_DATABASE_URL" -c "DROP DATABASE IF EXISTS ledgerr;"
    
    # Create the database (connecting to postgres)
    psql -v ON_ERROR_STOP=1 "$BASE_DATABASE_URL" -c "CREATE DATABASE ledgerr;"
    
    echo "Database 'ledgerr' has been reset!"
fi

# Define directories in order
DIRECTORIES=(
    "extensions"
    "schemas"
    "tables" 
    "internal_functions"
    "external_functions"
    "triggers"
    "partitions"
)

# Process each directory in order
for dir in "${DIRECTORIES[@]}"; do
    echo "Processing $dir..."
    
    # Find all .sql files in the directory and sort them numerically
    files=$(find "./schema/$dir" -name "*.sql" -type f | sort -V)

    for file in $files; do
        echo "Executing: $file"
        psql -v ON_ERROR_STOP=1 "$DATABASE_URL" < "$file"
    done
done

echo "Database schema setup complete!"
