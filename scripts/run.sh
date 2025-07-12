#!/bin/bash

# Set PostgREST configuration via environment variables
export PGRST_DB_URI="$DATABASE_URL"
export PGRST_DB_SCHEMAS="ledgerr_api"
export PGRST_DB_ANON_ROLE="brandon"
export PGRST_SERVER_PORT="3000"

# Start PostgREST
postgrest
