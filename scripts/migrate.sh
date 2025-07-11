#!/bin/bash

set -euo pipefail

# Define directories in order
DIRECTORIES=(
    "schemas"
    "tables" 
    "functions"
    "utilities"
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
