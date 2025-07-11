#!/bin/bash

set -e

find "./tests" -name "*.sql" -type f | sort -V | while read -r file; do
    echo "Executing: $file"
    cat "$file" | psql "$DATABASE_URL"
done
