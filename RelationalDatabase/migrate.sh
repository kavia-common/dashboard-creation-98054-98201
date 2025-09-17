#!/usr/bin/env bash
# Simple idempotent migration runner for local PostgreSQL within this container context.

set -euo pipefail

DB_NAME="${DB_NAME:-myapp}"
DB_USER="${DB_USER:-appuser}"
DB_PASSWORD="${DB_PASSWORD:-dbuser123}"
DB_PORT="${DB_PORT:-5000}"
DB_HOST="${DB_HOST:-localhost}"

PG_VERSION=$(ls /usr/lib/postgresql/ 2>/dev/null | head -1)
PG_BIN="/usr/lib/postgresql/${PG_VERSION}/bin"

echo "Running migrations against postgresql://${DB_USER}:******@${DB_HOST}:${DB_PORT}/${DB_NAME}"

run_sql() {
  local sql_file="$1"
  echo "Applying: ${sql_file}"
  PGPASSWORD="${DB_PASSWORD}" "${PG_BIN}/psql" \
    -h "${DB_HOST}" -p "${DB_PORT}" -U "${DB_USER}" -d "${DB_NAME}" -v ON_ERROR_STOP=1 \
    -f "${sql_file}" >/dev/null
  echo "✓ Applied ${sql_file}"
}

# Ensure DB exists
echo "Ensuring database exists..."
PGPASSWORD="${DB_PASSWORD}" "${PG_BIN}/psql" \
  -h "${DB_HOST}" -p "${DB_PORT}" -U "${DB_USER}" -d postgres \
  -v ON_ERROR_STOP=1 -c "SELECT 1;" >/dev/null || {
    echo "Cannot connect with provided credentials. Check user, password, and permissions."
    exit 1
  }

# Apply all SQL files in numeric order
for f in $(ls -1 schema/*.sql | sort); do
  run_sql "$f"
done

echo "All migrations applied."
