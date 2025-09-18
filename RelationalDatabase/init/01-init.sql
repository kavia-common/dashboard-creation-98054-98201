-- Ensure schema permissions for appuser on first run

-- Grant schema usage and create
GRANT USAGE ON SCHEMA public TO appuser;
GRANT CREATE ON SCHEMA public TO appuser;

-- Ensure default privileges for new objects
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO appuser;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO appuser;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON FUNCTIONS TO appuser;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TYPES TO appuser;

-- Ensure appuser has full privileges on the database
GRANT ALL PRIVILEGES ON DATABASE myapp TO appuser;

-- Optional: you can create tables here if needed. Keeping schema empty for ORM migrations.
