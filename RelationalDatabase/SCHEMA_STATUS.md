# Schema Status (Applied via psql)

This file documents the manual DDL/DML operations executed directly against PostgreSQL to provision the database for the Dashboard application.

Connection used:
- Command: psql postgresql://appuser:dbuser123@localhost:5000/myapp
- Source: db_connection.txt

Applied operations (one statement per invocation):
1) Extensions
   - CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
   - CREATE EXTENSION IF NOT EXISTS "pgcrypto";
   - CREATE EXTENSION IF NOT EXISTS citext;

2) Tables
   - public.users
     - Columns: id UUID PK (uuid_generate_v4()), email CITEXT UNIQUE NOT NULL, hashed_password TEXT NOT NULL, full_name TEXT, role TEXT DEFAULT 'user', is_active BOOLEAN DEFAULT TRUE, is_superuser BOOLEAN DEFAULT FALSE, last_login_at TIMESTAMPTZ, created_at TIMESTAMPTZ DEFAULT now(), updated_at TIMESTAMPTZ DEFAULT now()
   - public.reports
     - Columns: id UUID PK, title TEXT NOT NULL, description TEXT, chart_type TEXT NOT NULL, data_query TEXT, data_config JSONB, owner_id UUID FK -> users.id ON DELETE SET NULL, is_published BOOLEAN DEFAULT FALSE, created_at/updated_at TIMESTAMPTZ
   - public.refresh_tokens
     - Columns: id UUID PK, user_id UUID NOT NULL FK -> users.id ON DELETE CASCADE, token_hash TEXT NOT NULL, created_at TIMESTAMPTZ DEFAULT now(), expires_at TIMESTAMPTZ NOT NULL, revoked_at TIMESTAMPTZ
     - Constraint: UNIQUE (user_id, token_hash)

3) Trigger function and triggers
   - CREATE OR REPLACE FUNCTION set_updated_at() RETURNS TRIGGER AS E'BEGIN
       NEW.updated_at = NOW(); RETURN NEW; END;' LANGUAGE plpgsql;
   - Users trigger: BEFORE UPDATE ON public.users FOR EACH ROW EXECUTE FUNCTION set_updated_at();
   - Reports trigger: BEFORE UPDATE ON public.reports FOR EACH ROW EXECUTE FUNCTION set_updated_at();

4) Indexes
   - ix_users_created_at (users.created_at DESC)
   - ix_reports_owner_id (reports.owner_id)
   - ix_reports_created_at (reports.created_at DESC)
   - ix_reports_chart_type (reports.chart_type)
   - ix_refresh_tokens_user_id (refresh_tokens.user_id)

5) Materialized view and refresh function
   - CREATE MATERIALIZED VIEW IF NOT EXISTS public.mv_reports_by_type AS
     SELECT chart_type, COUNT(*) AS report_count FROM public.reports GROUP BY chart_type;
   - CREATE OR REPLACE FUNCTION refresh_mv_reports_by_type() RETURNS VOID AS E'BEGIN
       REFRESH MATERIALIZED VIEW CONCURRENTLY public.mv_reports_by_type;
     EXCEPTION WHEN feature_not_supported THEN
       REFRESH MATERIALIZED VIEW public.mv_reports_by_type;
     END;' LANGUAGE plpgsql;

6) Seed data (development placeholder)
   - Insert admin user if not exists:
     - email: admin@example.com
     - hashed_password: $2b$12$PLACEHOLDER_HASH_REPLACE_ME
     - role: admin, is_active: TRUE, is_superuser: TRUE
   - NOTE: Replace placeholder hash with a real bcrypt hash in non-dev environments.

Notes:
- Backend should map:
  - users.id and related FKs as UUID(as_uuid=True)
  - reports.data_config as JSONB
- The citext extension is installed to enforce case-insensitive unique emails.
- Consider adding RBAC tables in the future if role granularity increases.

Operational tips:
- Refresh MV: SELECT refresh_mv_reports_by_type();
- Common reports filter examples:
  - SELECT * FROM public.reports WHERE owner_id = :user_id ORDER BY created_at DESC LIMIT 50;
  - SELECT chart_type, COUNT(*) FROM public.reports GROUP BY chart_type;
