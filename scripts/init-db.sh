#!/bin/bash
# Creates separate databases for each service within the shared PostgreSQL instance.
# Runs automatically on first container start (postgres entrypoint.d).
set -e

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_USER" <<-EOSQL
    CREATE DATABASE vikunja;
    CREATE DATABASE outline;
EOSQL
