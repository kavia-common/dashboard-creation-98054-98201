# Database Schema for Dashboard Platform

This folder contains:
- schema.sql: PostgreSQL DDL for users, reports, charts, data sources, caching, tokens, and auditing.
- sqlalchemy_models.py: SQLAlchemy ORM mirror for BackendAPIService consumption.

How to apply the schema:
1) Ensure PostgreSQL is running (use startup.sh provided in this container).
2) Apply schema:
   psql postgresql://appuser:dbuser123@localhost:5001/myapp -f schema.sql

Troubleshooting database startup:
- If you encounter postmaster.pid lock or socket errors when starting PostgreSQL, see README-DB-RECOVERY.md in this folder for recovery steps. The startup.sh script now auto-detects and removes stale locks safely.

Integration notes:
- Backend should load DATABASE_URL from environment (.env) and create SQLAlchemy engine with echo disabled in production.
- Use Alembic or the provided schema.sql to initialize database. If using Alembic, copy sqlalchemy_models.py into the backend (or import as shared module) and generate migrations.
- Do NOT store secrets (API keys, DB passwords) in the DB. The chart_data_sources table stores only non-secret configuration; secrets should be injected at runtime by the backend.

Auth:
- Users.password_hash contains a bcrypt hash managed by the backend (never store plaintext).
- Optional auth_tokens table can be used to implement logout/blacklist if needed.

Chart data:
- chart_data_sources.source_type selects one of: static (JSON payload), sql (sql_query), api (api_endpoint/method/headers).
- charts.visualization holds frontend options (labels, axes, color palettes, mappings).
- chart_data_cache can be used to improve performance.

Soft deletes:
- is_deleted + deleted_at exist on main entities to enable soft deletion from the backend.

Indices:
- Several indices are created for frequent queries (by owner, visibility, report positions, etc.).

Environment variables required by backend (example names):
- DATABASE_URL=postgresql+psycopg2://appuser:${DB_PASSWORD}@db:5432/myapp

Security:
- Always access the DB from the backend. The frontend never connects directly.
- Keep HTTPS and JWT best practices in the backend and never log sensitive data.

```bash
# Quick verification
psql postgresql://appuser:dbuser123@localhost:5001/myapp -c "\dt"
```
