#!/bin/bash

set -e

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
    find "./schema/$dir" -name "*.sql" -type f | sort -V | while read -r file; do
        echo "Executing: $file"
        cat "$file" | psql "$DATABASE_URL"
    done
done

echo "Database schema setup complete!"
