-- 001_init_schema.sql
-- Purpose: Create initial PostgreSQL schema for dashboard application
-- Includes: users, reports, refresh_tokens, and helpful indexes/constraints
-- This script is idempotent (uses IF NOT EXISTS where possible)

-- Enable useful extensions (safe to run multiple times)
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Users table
CREATE TABLE IF NOT EXISTS public.users (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    email           CITEXT UNIQUE NOT NULL,
    hashed_password TEXT NOT NULL,
    full_name       TEXT,
    role            TEXT NOT NULL DEFAULT 'user', -- future RBAC expansion
    is_active       BOOLEAN NOT NULL DEFAULT TRUE,
    is_superuser    BOOLEAN NOT NULL DEFAULT FALSE,
    last_login_at   TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Ensure citext extension (case-insensitive email) is present; fall back if missing
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'citext') THEN
        CREATE EXTENSION IF NOT EXISTS citext;
    END IF;
EXCEPTION WHEN others THEN
    -- If citext cannot be created (permissions), keep email as TEXT with unique index lower(email)
    RAISE NOTICE 'citext extension not available; a functional unique index will be used on lower(email).';
END $$;

-- If citext was not created (or email column is not citext), ensure functional unique index
DO $$
BEGIN
    IF (SELECT atttypid::regtype::text FROM pg_attribute 
        WHERE attrelid = 'public.users'::regclass AND attname = 'email' AND NOT attisdropped) <> 'citext' THEN
        -- create unique index on lower(email)
        IF NOT EXISTS (
            SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND indexname = 'ux_users_email_lower'
        ) THEN
            CREATE UNIQUE INDEX ux_users_email_lower ON public.users (LOWER(email));
        END IF;
    END IF;
END $$;

-- Auto-update timestamp trigger
CREATE OR REPLACE FUNCTION set_updated_at() RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_users_updated_at ON public.users;
CREATE TRIGGER trg_users_updated_at
BEFORE UPDATE ON public.users
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- Reports table: stores report definitions and optional data configuration for charting
CREATE TABLE IF NOT EXISTS public.reports (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    title           TEXT NOT NULL,
    description     TEXT,
    chart_type      TEXT NOT NULL, -- e.g., 'line', 'bar', 'pie'
    -- data_query or data_config supports flexibility; backend may use SQL snippets or JSON config
    data_query      TEXT,          -- optional raw SQL (use carefully; backend should sanitize/whitelist)
    data_config     JSONB,         -- preferred structured configuration for charting
    owner_id        UUID REFERENCES public.users(id) ON DELETE SET NULL,
    is_published    BOOLEAN NOT NULL DEFAULT FALSE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

DROP TRIGGER IF EXISTS trg_reports_updated_at ON public.reports;
CREATE TRIGGER trg_reports_updated_at
BEFORE UPDATE ON public.reports
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- Refresh tokens table (optional; enables refresh token rotation if implemented)
CREATE TABLE IF NOT EXISTS public.refresh_tokens (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id         UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    token_hash      TEXT NOT NULL, -- store hash of token (never plain text)
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at      TIMESTAMPTZ NOT NULL,
    revoked_at      TIMESTAMPTZ,
    CONSTRAINT uq_refresh_token UNIQUE (user_id, token_hash)
);

-- Helpful indexes
CREATE INDEX IF NOT EXISTS ix_users_created_at ON public.users (created_at DESC);
CREATE INDEX IF NOT EXISTS ix_reports_owner_id ON public.reports (owner_id);
CREATE INDEX IF NOT EXISTS ix_reports_created_at ON public.reports (created_at DESC);
CREATE INDEX IF NOT EXISTS ix_reports_chart_type ON public.reports (chart_type);
CREATE INDEX IF NOT EXISTS ix_refresh_tokens_user_id ON public.refresh_tokens (user_id);

-- Sample materialized view for fast charting (optional for future use)
-- Stores aggregated counts of reports by chart_type
CREATE MATERIALIZED VIEW IF NOT EXISTS public.mv_reports_by_type AS
SELECT chart_type, COUNT(*) AS report_count
FROM public.reports
GROUP BY chart_type;

-- Refresh helper function (safe to call from backend when needed)
CREATE OR REPLACE FUNCTION refresh_mv_reports_by_type() RETURNS VOID AS $$
BEGIN
    REFRESH MATERIALIZED VIEW CONCURRENTLY public.mv_reports_by_type;
EXCEPTION WHEN feature_not_supported THEN
    -- If CONCURRENTLY is not supported (no unique index), fall back
    REFRESH MATERIALIZED VIEW public.mv_reports_by_type;
END;
$$ LANGUAGE plpgsql;

-- Grant privileges to app user if present (script safe even if role missing)
DO $$
DECLARE
    app_role TEXT := 'appuser';
    role_exists BOOLEAN;
BEGIN
    SELECT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = app_role) INTO role_exists;
    IF role_exists THEN
        GRANT USAGE ON SCHEMA public TO appuser;
        GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO appuser;
        GRANT USAGE, SELECT, UPDATE ON ALL SEQUENCES IN SCHEMA public TO appuser;
        ALTER DEFAULT PRIVILEGES IN SCHEMA public
            GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO appuser;
        ALTER DEFAULT PRIVILEGES IN SCHEMA public
            GRANT USAGE, SELECT, UPDATE ON SEQUENCES TO appuser;
    END IF;
END $$;
