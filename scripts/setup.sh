#!/usr/bin/env bash

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/common.sh"

# ==========================================
# CONFIGURATION VARIABLES
# ==========================================
validate_db_type
validate_identifier DB_NAME "$DB_NAME"
validate_identifier POSTGRES_SUPERUSER "$POSTGRES_SUPERUSER"
require_docker

echo "=================================================="
echo " Starting Drupal & Database Infrastructure Setup"
echo "=================================================="

# 1. Create Docker network if it doesn't exist
if ! docker network inspect "$NETWORK_NAME" >/dev/null 2>&1; then
    echo "[*] Creating network: $NETWORK_NAME..."
    docker network create "$NETWORK_NAME"
else
    echo "[+] Network '$NETWORK_NAME' already exists."
fi

# Create volumes if they don't exist
for vol in "$DB_VOLUME" "$DRUPAL_VOLUME"; do
    if ! docker volume inspect "$vol" >/dev/null 2>&1; then
        echo "[*] Creating volume: $vol..."
        docker volume create "$vol"
    else
        echo "[+] Volume '$vol' already exists."
    fi
done

# 2. Pulling Docker images
echo "[*] Pulling Drupal image '$DRUPAL_IMAGE'..."
docker pull "$DRUPAL_IMAGE"

if [ "$DB_TYPE" = "mysql" ]; then
    echo "[*] Pulling MySQL image '$MYSQL_IMAGE'..."
    docker pull "$MYSQL_IMAGE"
else
    echo "[*] Pulling PostgreSQL image '$POSTGRES_IMAGE'..."
    docker pull "$POSTGRES_IMAGE"
fi

# 3. Start Database Container
echo "[*] Starting Database Container ($DB_TYPE)..."
if [ "$DB_TYPE" = "mysql" ]; then
    # Check if container already exists
    if container_exists "$DB_CONTAINER"; then
        echo "[!] Container '$DB_CONTAINER' already exists. Removing it..."
        docker rm -f "$DB_CONTAINER"
    fi
    docker run -d \
        --name "$DB_CONTAINER" \
        --network "$NETWORK_NAME" \
        -p "${DB_PORT}:3306" \
        -e MYSQL_ROOT_PASSWORD="$DB_ROOT_PASSWORD" \
        -e MYSQL_DATABASE="$DB_NAME" \
        -e MYSQL_USER="$DB_USER" \
        -e MYSQL_PASSWORD="$DB_PASSWORD" \
        -v "$DB_VOLUME:/var/lib/mysql" \
        "$MYSQL_IMAGE"
    wait_for_mysql
else
    # PostgreSQL
    if container_exists "$DB_CONTAINER"; then
        echo "[!] Container '$DB_CONTAINER' already exists. Removing it..."
        docker rm -f "$DB_CONTAINER"
    fi
    # Postgres uses POSTGRES_PASSWORD for superuser (default is postgres, or we can use root)
    docker run -d \
        --name "$DB_CONTAINER" \
        --network "$NETWORK_NAME" \
        -p "${DB_PORT}:5432" \
        -e POSTGRES_PASSWORD="$DB_ROOT_PASSWORD" \
        -e POSTGRES_DB="$DB_NAME" \
        -e POSTGRES_USER="$POSTGRES_SUPERUSER" \
        -v "$DB_VOLUME:/var/lib/postgresql" \
        "$POSTGRES_IMAGE"
    wait_for_postgres

    echo "[*] Creating PostgreSQL application user '$DB_USER'..."
    ensure_postgres_role
    docker exec "$DB_CONTAINER" psql \
        -v ON_ERROR_STOP=1 \
        -U "$POSTGRES_SUPERUSER" \
        -d "$DB_NAME" \
        -c "GRANT ALL ON SCHEMA public TO \"$DB_USER\";"
    docker exec "$DB_CONTAINER" psql \
        -v ON_ERROR_STOP=1 \
        -U "$POSTGRES_SUPERUSER" \
        -d postgres \
        -c "GRANT ALL PRIVILEGES ON DATABASE \"$DB_NAME\" TO \"$DB_USER\";"
fi

# 4. Start Drupal Container
echo "[*] Starting Drupal Container..."
if container_exists "$DRUPAL_CONTAINER"; then
    echo "[!] Container '$DRUPAL_CONTAINER' already exists. Removing it..."
    docker rm -f "$DRUPAL_CONTAINER"
fi

docker run -d \
    --name "$DRUPAL_CONTAINER" \
    --network "$NETWORK_NAME" \
    -p "${DRUPAL_PORT}:80" \
    -v "$DRUPAL_VOLUME:/var/www/html" \
    "$DRUPAL_IMAGE"

if ! container_running "$DB_CONTAINER" || ! container_running "$DRUPAL_CONTAINER"; then
    echo "[!] Error: One or more containers failed to start." >&2
    exit 1
fi

echo "=================================================="
echo " Setup Completed Successfully!"
echo "=================================================="
echo "Database Container: $DB_CONTAINER (Port: $DB_PORT)"
echo "Drupal Container:   $DRUPAL_CONTAINER (Port: $DRUPAL_PORT)"
echo "Docker Network:     $NETWORK_NAME"
echo ""
echo "You can now configure Drupal at: http://localhost:$DRUPAL_PORT"
echo "During DB setup in Drupal UI, use:"
echo " - Database Type: $DB_TYPE"
echo " - Database Name: $DB_NAME"
echo " - Database User: $DB_USER"
echo " - Database Password: $DB_PASSWORD"
echo " - Database Host: $DB_CONTAINER (not localhost)"
echo " - Database Port: $DB_PORT"
echo "=================================================="
