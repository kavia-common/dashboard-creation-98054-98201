# Database Schema for Dashboard Application

This database stores users, reports, and authentication-related data for the dashboard system. It is intended to be used exclusively by the FastAPI backend via SQLAlchemy.

Tables:
- users: application accounts with email (unique, case-insensitive), hashed_password (bcrypt), role, flags, and timestamps.
- reports: report definitions, including chart_type and either data_query (SQL) or data_config (JSONB) for flexible chart rendering; linked to users via owner_id.
- refresh_tokens: optional table for implementing refresh-token flows; stores token hashes and lifetimes.

Indexes:
- Lowercased email uniqueness (if `citext` is unavailable).
- Common filters on created_at, chart_type, and owner_id.

Materialized View:
- mv_reports_by_type: pre-aggregated counts of reports by chart type with refresh function `refresh_mv_reports_by_type()`.

Migrations:
- schema/001_init_schema.sql: creates tables and functions (idempotent).
- schema/002_seed_admin.sql: inserts an initial admin user if absent. Replace the placeholder hash with a real bcrypt hash.

Environment variables (align with existing scripts):
- DB_NAME (default: myapp)
- DB_USER (default: appuser)
- DB_PASSWORD (default: dbuser123)
- DB_PORT (default: 5000)
- DB_HOST (default: localhost)

Usage:
1. Ensure PostgreSQL is running (startup.sh already provisions DB/user/permissions).
2. Apply migrations:
   ./migrate.sh

3. Replace the placeholder bcrypt hash in `schema/002_seed_admin.sql` before running in any non-dev environment. The backend (FastAPI) should always hash passwords with bcrypt on creation and validation.

SQLAlchemy Mapping Guidance (Backend):
- users.id: UUID -> sqlalchemy.dialects.postgresql.UUID(as_uuid=True)
- reports.data_config: JSONB -> sqlalchemy.dialects.postgresql.JSONB
- reports.owner_id: ForeignKey("users.id")
- Use server_default=sa.text("now()") for created_at/updated_at; handle updates on backend or rely on trigger.

Security Notes:
- Never store plaintext passwords. Only store bcrypt hashes.
- Consider role-based access control using `users.role` and `is_superuser`.
- If enabling `data_query`, whitelist queries or restrict usage to admins to avoid SQL injection risks. Prefer `data_config` JSONB.

```bash
# Example to generate a bcrypt hash in Python (to replace placeholder):
# >>> from passlib.hash import bcrypt
# >>> bcrypt.using(rounds=12).hash("ChangeMe123!")
```
