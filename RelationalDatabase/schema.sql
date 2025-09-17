-- Dashboard Platform PostgreSQL Schema
-- Purpose: Persistent storage for users, authentication, reports, charts and data sources
-- Notes:
--  - All timestamps are in UTC with default now()
--  - Soft-delete fields are provided (is_deleted, deleted_at) to allow safer deletes
--  - Unique and FK constraints with sensible ON DELETE behavior are defined
--  - This schema is designed to be used via SQLAlchemy ORM from the BackendAPIService

BEGIN;

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Enumerations
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'user_role') THEN
        CREATE TYPE user_role AS ENUM ('admin', 'user');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'chart_type') THEN
        CREATE TYPE chart_type AS ENUM ('line', 'bar', 'pie');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'data_source_type') THEN
        CREATE TYPE data_source_type AS ENUM ('static', 'sql', 'api');
    END IF;
END$$;

-- Users table
CREATE TABLE IF NOT EXISTS users (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    email           CITEXT UNIQUE NOT NULL,
    password_hash   TEXT NOT NULL,
    full_name       VARCHAR(255),
    role            user_role NOT NULL DEFAULT 'user',
    is_active       BOOLEAN NOT NULL DEFAULT TRUE,
    last_login_at   TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    is_deleted      BOOLEAN NOT NULL DEFAULT FALSE,
    deleted_at      TIMESTAMPTZ
);

COMMENT ON TABLE users IS 'Application users with credentials and roles';
CREATE INDEX IF NOT EXISTS idx_users_email ON users (email);
CREATE INDEX IF NOT EXISTS idx_users_active ON users (is_active) WHERE is_active = TRUE;

-- Reports table (a report is an entity owned by a user and containing multiple charts)
CREATE TABLE IF NOT EXISTS reports (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    title           VARCHAR(255) NOT NULL,
    description     TEXT,
    owner_id        UUID NOT NULL REFERENCES users(id) ON UPDATE CASCADE ON DELETE RESTRICT,
    is_public       BOOLEAN NOT NULL DEFAULT FALSE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    is_deleted      BOOLEAN NOT NULL DEFAULT FALSE,
    deleted_at      TIMESTAMPTZ
);
COMMENT ON TABLE reports IS 'Logical grouping of charts, owned by a user';
CREATE INDEX IF NOT EXISTS idx_reports_owner_id ON reports (owner_id);
CREATE INDEX IF NOT EXISTS idx_reports_public ON reports (is_public);

-- Chart data sources define where data originates (static JSON, SQL query, or external API)
CREATE TABLE IF NOT EXISTS chart_data_sources (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name            VARCHAR(255) NOT NULL,
    source_type     data_source_type NOT NULL,
    -- For 'static' store JSON payload
    static_payload  JSONB,
    -- For 'sql' store query text and optional connection key (the connection is managed server-side and not stored here)
    sql_query       TEXT,
    -- For 'api' store endpoint and optional method/headers (secrets/keys should be provided by backend and not stored here)
    api_endpoint    TEXT,
    api_method      VARCHAR(10) DEFAULT 'GET',
    api_headers     JSONB,
    -- Common optional parameters for all types
    filters_schema  JSONB, -- defines available filters for frontend
    created_by      UUID NOT NULL REFERENCES users(id) ON UPDATE CASCADE ON DELETE RESTRICT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    is_deleted      BOOLEAN NOT NULL DEFAULT FALSE,
    deleted_at      TIMESTAMPTZ,
    CONSTRAINT chk_src_payload CHECK (
        (source_type = 'static' AND static_payload IS NOT NULL)
        OR (source_type = 'sql' AND sql_query IS NOT NULL)
        OR (source_type = 'api' AND api_endpoint IS NOT NULL)
    )
);
COMMENT ON TABLE chart_data_sources IS 'Defines how chart data is retrieved (static JSON, SQL query, or external API)';
CREATE INDEX IF NOT EXISTS idx_chart_data_sources_type ON chart_data_sources (source_type);
CREATE INDEX IF NOT EXISTS idx_chart_data_sources_creator ON chart_data_sources (created_by);

-- Charts table (each chart belongs to a report and references a data source)
CREATE TABLE IF NOT EXISTS charts (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    report_id       UUID NOT NULL REFERENCES reports(id) ON UPDATE CASCADE ON DELETE CASCADE,
    title           VARCHAR(255) NOT NULL,
    chart_kind      chart_type NOT NULL,
    data_source_id  UUID NOT NULL REFERENCES chart_data_sources(id) ON UPDATE CASCADE ON DELETE RESTRICT,
    -- Visualization config for frontend (labels, colors, axes, mappings)
    visualization   JSONB,
    -- Optional default parameters for data fetching (e.g., date ranges)
    default_params  JSONB,
    position        INT NOT NULL DEFAULT 0, -- order inside report
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    is_deleted      BOOLEAN NOT NULL DEFAULT FALSE,
    deleted_at      TIMESTAMPTZ
);
COMMENT ON TABLE charts IS 'A single chart in a report with configuration and link to its data source';
CREATE INDEX IF NOT EXISTS idx_charts_report_id ON charts (report_id);
CREATE INDEX IF NOT EXISTS idx_charts_data_source_id ON charts (data_source_id);
CREATE INDEX IF NOT EXISTS idx_charts_position ON charts (report_id, position);

-- Many-to-many: users who can access a private report (in addition to owner)
CREATE TABLE IF NOT EXISTS report_collaborators (
    report_id   UUID NOT NULL REFERENCES reports(id) ON UPDATE CASCADE ON DELETE CASCADE,
    user_id     UUID NOT NULL REFERENCES users(id) ON UPDATE CASCADE ON DELETE CASCADE,
    can_edit    BOOLEAN NOT NULL DEFAULT FALSE,
    added_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (report_id, user_id)
);
COMMENT ON TABLE report_collaborators IS 'Additional per-user access control for private reports';

-- Refresh cache table (optional: stores computed data for charts to speed up responses)
CREATE TABLE IF NOT EXISTS chart_data_cache (
    id              BIGSERIAL PRIMARY KEY,
    chart_id        UUID NOT NULL REFERENCES charts(id) ON UPDATE CASCADE ON DELETE CASCADE,
    params_hash     TEXT NOT NULL,
    payload         JSONB NOT NULL,
    computed_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at      TIMESTAMPTZ,
    UNIQUE (chart_id, params_hash)
);
COMMENT ON TABLE chart_data_cache IS 'Cache of chart results for parameterized queries';
CREATE INDEX IF NOT EXISTS idx_chart_data_cache_chart_expires ON chart_data_cache (chart_id, expires_at);

-- Authentication token blacklist/metadata for logout/rotation (optional, used if needed by backend)
CREATE TABLE IF NOT EXISTS auth_tokens (
    id              BIGSERIAL PRIMARY KEY,
    user_id         UUID NOT NULL REFERENCES users(id) ON UPDATE CASCADE ON DELETE CASCADE,
    jti             TEXT NOT NULL, -- JWT ID
    issued_at       TIMESTAMPTZ NOT NULL,
    expires_at      TIMESTAMPTZ NOT NULL,
    revoked         BOOLEAN NOT NULL DEFAULT FALSE,
    revoked_at      TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (jti)
);
COMMENT ON TABLE auth_tokens IS 'Optional JWT tracking/blacklist table for improved security';
CREATE INDEX IF NOT EXISTS idx_auth_tokens_user ON auth_tokens (user_id);
CREATE INDEX IF NOT EXISTS idx_auth_tokens_valid ON auth_tokens (revoked, expires_at);

-- Audit log (basic)
CREATE TABLE IF NOT EXISTS audit_logs (
    id              BIGSERIAL PRIMARY KEY,
    actor_id        UUID REFERENCES users(id) ON UPDATE CASCADE ON DELETE SET NULL,
    action          VARCHAR(64) NOT NULL, -- e.g., 'login', 'create_user', 'update_report'
    entity_type     VARCHAR(64),          -- e.g., 'user', 'report', 'chart'
    entity_id       UUID,
    details         JSONB,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_audit_logs_actor ON audit_logs (actor_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_logs_entity ON audit_logs (entity_type, entity_id);

-- Triggers to maintain updated_at
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_users_updated_at') THEN
        CREATE TRIGGER trg_users_updated_at BEFORE UPDATE ON users
        FOR EACH ROW EXECUTE FUNCTION set_updated_at();
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_reports_updated_at') THEN
        CREATE TRIGGER trg_reports_updated_at BEFORE UPDATE ON reports
        FOR EACH ROW EXECUTE FUNCTION set_updated_at();
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_charts_updated_at') THEN
        CREATE TRIGGER trg_charts_updated_at BEFORE UPDATE ON charts
        FOR EACH ROW EXECUTE FUNCTION set_updated_at();
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_chart_data_sources_updated_at') THEN
        CREATE TRIGGER trg_chart_data_sources_updated_at BEFORE UPDATE ON chart_data_sources
        FOR EACH ROW EXECUTE FUNCTION set_updated_at();
    END IF;
END$$;

COMMIT;

-- Seed: ensure an admin user placeholder (password hash should be set by backend provisioning)
-- Note: Replace the hash with a real bcrypt hash during backend initialization/migrations.
-- INSERT INTO users (email, password_hash, full_name, role, is_active)
-- VALUES ('admin@example.com', '$2b$12$replace_me', 'Administrator', 'admin', TRUE)
-- ON CONFLICT (email) DO NOTHING;
