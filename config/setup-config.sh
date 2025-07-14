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

# Copy custom pg_hba.conf to the data directory
if [ -f /docker-entrypoint-initdb.d/pg_hba.conf ]; then
    echo "Copying custom pg_hba.conf..."
    cp /docker-entrypoint-initdb.d/pg_hba.conf "$PGDATA/pg_hba.conf"
    chown postgres:postgres "$PGDATA/pg_hba.conf"
    chmod 600 "$PGDATA/pg_hba.conf"
    echo "Custom pg_hba.conf applied successfully"
fi
