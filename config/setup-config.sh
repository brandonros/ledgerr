#!/bin/bash

set -e

# Copy custom postgresql.conf to the data directory
if [ -f /docker-entrypoint-initdb.d/postgresql.conf ]; then
    echo "Copying custom postgresql.conf..."
    cp /docker-entrypoint-initdb.d/postgresql.conf "$PGDATA/postgresql.conf"
    chown postgres:postgres "$PGDATA/postgresql.conf"
    chmod 600 "$PGDATA/postgresql.conf"
    echo "Custom postgresql.conf applied successfully"
fi
