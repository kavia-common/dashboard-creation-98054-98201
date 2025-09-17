#!/bin/bash
set -euo pipefail

# Minimal PostgreSQL startup script with robust lock handling and Node viewer prep
DB_NAME="${DB_NAME:-myapp}"
DB_USER="${DB_USER:-appuser}"
DB_PASSWORD="${DB_PASSWORD:-dbuser123}"
DB_PORT="${DB_PORT:-5001}"

DATA_DIR="${PGDATA:-/var/lib/postgresql/data}"
LOCK_FILE="${DATA_DIR}/postmaster.pid"

echo "Starting PostgreSQL setup..."

# Find PostgreSQL version and set paths
PG_VERSION=$(ls /usr/lib/postgresql/ | head -1)
PG_BIN="/usr/lib/postgresql/${PG_VERSION}/bin"

echo "Found PostgreSQL version: ${PG_VERSION}"
echo "Using data directory: ${DATA_DIR}"

# Helper: check if PID is alive
is_pid_alive() {
  local pid="$1"
  if [ -z "$pid" ]; then
    return 1
  fi
  if kill -0 "$pid" >/dev/null 2>&1; then
    return 0
  fi
  return 1
}

# Helper: best-effort stop a running postgres for this data dir
stop_postgres_if_running() {
  if [ -S "${DATA_DIR}/.s.PGSQL.${DB_PORT}" ] || [ -f "${LOCK_FILE}" ]; then
    echo "Attempting graceful stop of existing PostgreSQL for ${DATA_DIR}..."
    if sudo -u postgres ${PG_BIN}/pg_ctl -D "${DATA_DIR}" -p "${DB_PORT}" -m fast stop >/dev/null 2>&1; then
      echo "✓ Graceful stop issued."
      sleep 2
    fi
  fi
}

# 1) Early exit if PostgreSQL is already ready on port
if sudo -u postgres ${PG_BIN}/pg_isready -p "${DB_PORT}" >/dev/null 2>&1; then
  echo "PostgreSQL is already running on port ${DB_PORT}!"
  echo "Database: ${DB_NAME}"
  echo "User: ${DB_USER}"
  echo "Port: ${DB_PORT}"
  echo ""
  echo "To connect to the database, use:"
  echo "psql -h localhost -U ${DB_USER} -d ${DB_NAME} -p ${DB_PORT}"
  if [ -f "db_connection.txt" ]; then
    echo "Or use: $(cat db_connection.txt)"
  fi
  exit 0
fi

# 2) If pg_isready failed, double-check a process exists on the port
if pgrep -f "postgres.*-p ${DB_PORT}" >/dev/null 2>&1; then
  echo "Found existing PostgreSQL process bound to port ${DB_PORT}. Verifying connectivity..."
  if sudo -u postgres ${PG_BIN}/psql -p "${DB_PORT}" -d "${DB_NAME}" -c '\q' 2>/dev/null; then
    echo "Database ${DB_NAME} is accessible. Exiting."
    exit 0
  fi
  echo "Process on port ${DB_PORT} is not responding; will attempt controlled stop."
  stop_postgres_if_running
fi

# 3) Handle stale postmaster.pid
if [ -f "${LOCK_FILE}" ]; then
  echo "Detected lock file at ${LOCK_FILE}. Checking for staleness..."
  # postmaster.pid format: line1=pid
  LOCK_PID=$(head -n1 "${LOCK_FILE}" 2>/dev/null || echo "")
  if is_pid_alive "${LOCK_PID}"; then
    echo "Lock file indicates running PID ${LOCK_PID}. Aborting to avoid data corruption."
    echo "If this is unexpected, manually stop the process (kill -TERM ${LOCK_PID}) and re-run."
    exit 1
  else
    echo "Stale lock detected (PID ${LOCK_PID} not running). Removing lock and leftover sockets..."
    rm -f "${LOCK_FILE}"
    rm -f "${DATA_DIR}/.s.PGSQL.${DB_PORT}" "${DATA_DIR}/.s.PGSQL.${DB_PORT}.lock" 2>/dev/null || true
  fi
fi

# 4) Initialize data directory if needed
if [ ! -f "${DATA_DIR}/PG_VERSION" ]; then
  echo "Initializing PostgreSQL data directory..."
  sudo -u postgres ${PG_BIN}/initdb -D "${DATA_DIR}"
fi

# 5) Start PostgreSQL server in background
echo "Starting PostgreSQL server..."
sudo -u postgres ${PG_BIN}/postgres -D "${DATA_DIR}" -p "${DB_PORT}" &
POSTGRES_BG_PID=$!

# 6) Wait for PostgreSQL to start
echo "Waiting for PostgreSQL to start..."
for i in {1..20}; do
  if sudo -u postgres ${PG_BIN}/pg_isready -p "${DB_PORT}" >/dev/null 2>&1; then
    echo "✓ PostgreSQL is ready!"
    break
  fi
  echo "Waiting... ($i/20)"
  sleep 1
done

if ! sudo -u postgres ${PG_BIN}/pg_isready -p "${DB_PORT}" >/dev/null 2>&1; then
  echo "✗ PostgreSQL failed to become ready. Attempting one graceful stop then exit."
  sudo -u postgres ${PG_BIN}/pg_ctl -D "${DATA_DIR}" -p "${DB_PORT}" -m fast stop >/dev/null 2>&1 || true
  exit 1
fi

# 7) Create database and user
echo "Setting up database and user..."
sudo -u postgres ${PG_BIN}/createdb -p "${DB_PORT}" "${DB_NAME}" 2>/dev/null || echo "Database might already exist"

sudo -u postgres ${PG_BIN}/psql -p "${DB_PORT}" -d postgres << EOF
DO \$\$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = '${DB_USER}') THEN
        CREATE ROLE ${DB_USER} WITH LOGIN PASSWORD '${DB_PASSWORD}';
    END IF;
    ALTER ROLE ${DB_USER} WITH PASSWORD '${DB_PASSWORD}';
END
\$\$;

GRANT ALL PRIVILEGES ON DATABASE ${DB_NAME} TO ${DB_USER};
\c ${DB_NAME}
GRANT USAGE ON SCHEMA public TO ${DB_USER};
GRANT CREATE ON SCHEMA public TO ${DB_USER};
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO ${DB_USER};
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO ${DB_USER};
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON FUNCTIONS TO ${DB_USER};
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TYPES TO ${DB_USER};
GRANT ALL ON SCHEMA public TO ${DB_USER};
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO ${DB_USER};
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO ${DB_USER};
GRANT ALL PRIVILEGES ON ALL FUNCTIONS IN SCHEMA public TO ${DB_USER};
EOF

sudo -u postgres ${PG_BIN}/psql -p "${DB_PORT}" -d "${DB_NAME}" << EOF
GRANT ALL ON SCHEMA public TO ${DB_USER};
GRANT CREATE ON SCHEMA public TO ${DB_USER};
\dn+ public
EOF

# 8) Save connection information
echo "psql postgresql://${DB_USER}:${DB_PASSWORD}@localhost:${DB_PORT}/${DB_NAME}" > db_connection.txt
echo "Connection string saved to db_connection.txt"

# 9) Prepare db_visualizer environment and ensure Node dependencies installed
mkdir -p db_visualizer
cat > db_visualizer/postgres.env << EOF
export POSTGRES_URL="postgresql://localhost:${DB_PORT}/${DB_NAME}"
export POSTGRES_USER="${DB_USER}"
export POSTGRES_PASSWORD="${DB_PASSWORD}"
export POSTGRES_DB="${DB_NAME}"
export POSTGRES_PORT="${DB_PORT}"
EOF
echo "Environment variables saved to db_visualizer/postgres.env"

# Ensure Node dependencies are installed for db_visualizer
if command -v npm >/dev/null 2>&1; then
  pushd db_visualizer >/dev/null
  if [ ! -d "node_modules" ]; then
    echo "Installing db_visualizer Node dependencies (npm install)..."
    npm ci >/dev/null 2>&1 || npm install --no-audit --no-fund >/dev/null 2>&1 || true
  else
    # verify express is present
    if [ ! -d "node_modules/express" ]; then
      echo "Express not found, reinstalling dependencies..."
      npm install express >/dev/null 2>&1 || true
    fi
  fi
  popd >/dev/null
else
  echo "npm not found; skipping db_visualizer dependency installation."
fi

echo "PostgreSQL setup complete!"
echo "Database: ${DB_NAME}"
echo "User: ${DB_USER}"
echo "Port: ${DB_PORT}"
echo ""
echo "To use with Node.js viewer, run: source db_visualizer/postgres.env"
echo "To connect to the database:"
echo "psql -h localhost -U ${DB_USER} -d ${DB_NAME} -p ${DB_PORT}"
echo "$(cat db_connection.txt)"
