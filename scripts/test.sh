#!/bin/bash

set -euo pipefail

files=$(find "./tests" -name "*.sql" -type f | sort -V)

for file in $files; do
    echo "Executing: $file"
    psql -v ON_ERROR_STOP=1 "$DATABASE_URL" < "$file"
done
