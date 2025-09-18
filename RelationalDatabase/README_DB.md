# RelationalDatabase (PostgreSQL)

This directory contains assets and scripts for the PostgreSQL database used by the application.

## Run the database via Docker Compose

Prerequisites:
- Docker and Docker Compose installed
- Port 5001 on host is free

Steps:
1) From the container root (dashboard-creation-98054-98201):
   docker compose up -d

2) Verify health:
   docker compose ps
   docker compose logs -f relationaldb
   # Or locally:
   psql postgresql://appuser:dbuser123@localhost:5001/myapp -c "SELECT 1;"

The service maps host 5001 -> container 5432.

## Environment

The compose service sets:
- POSTGRES_USER=appuser
- POSTGRES_PASSWORD=dbuser123
- POSTGRES_DB=myapp

Data persists in the `pgdata` volume. Initialization SQL in `RelationalDatabase/init/01-init.sql` runs only on first boot (when the data directory is empty).

## Troubleshooting

- Port already in use:
  If `docker compose up -d` fails or the container is unhealthy because port 5001 is in use:
  - Identify conflict: lsof -i :5001 (on your machine)
  - Stop the conflicting service or change the host port mapping in docker-compose.yml.

- Database not healthy:
  - Check logs: docker compose logs -f relationaldb
  - Ensure environment variables are set as in docker-compose.yml
  - Remove existing volume and reinitialize if needed:
    docker compose down -v
    docker compose up -d

- Connecting from the backend:
  Use the internal Docker network host: `relationaldb:5432`
  Example SQLAlchemy URL:
  postgresql+psycopg2://appuser:dbuser123@relationaldb:5432/myapp

- Connecting from host:
  psql postgresql://appuser:dbuser123@localhost:5001/myapp

## Notes

- The older local scripts in this directory referenced port 5000. The Dockerized setup uses host port 5001 to meet the project requirement. Update any tooling accordingly.
- For restoring an existing dump, you can `docker cp` your SQL file into the container and run:
  docker exec -i relationaldb psql -U appuser -d myapp < /path/to/backup.sql
