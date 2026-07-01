#!/bin/bash

# ==========================================
# CONFIGURATION VARIABLES
# ==========================================
DB_TYPE="postgres"             # Database type: "mysql" or "postgres"
DB_CONTAINER="postgres-db"     # Name of the database container
DRUPAL_CONTAINER="drupal-web" # Name of the Drupal container
NETWORK_NAME="drupal-net"     # Name of the Docker network
DB_PORT="5432"                # Port exposed on host (3306 for MySQL, 5432 for Postgres)
DRUPAL_PORT="8080"            # Port exposed on host for Drupal (Must be 8080)
DB_NAME="drupal_db"           # Name of the database
DB_USER="drupal_user"          # Database username
DB_PASSWORD="my-secret-pw"     # Database user password
DB_ROOT_PASSWORD="my-secret-pw" # Root password (Must be my-secret-pw)

# Volumes
DB_VOLUME="drupal-db-data"
DRUPAL_VOLUME="drupal-web-data"

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
echo "[*] Pulling latest Drupal image..."
docker pull drupal:latest

if [ "$DB_TYPE" = "mysql" ]; then
    echo "[*] Pulling latest MySQL image..."
    docker pull mysql:latest
else
    echo "[*] Pulling latest PostgreSQL image..."
    docker pull postgres:latest
fi

# 3. Start Database Container
echo "[*] Starting Database Container ($DB_TYPE)..."
if [ "$DB_TYPE" = "mysql" ]; then
    # Check if container already exists
    if docker ps -a --format '{{.Names}}' | grep -Eq "^${DB_CONTAINER}$"; then
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
        mysql:latest
else
    # PostgreSQL
    if docker ps -a --format '{{.Names}}' | grep -Eq "^${DB_CONTAINER}$"; then
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
        -e POSTGRES_USER="root" \
        -v "$DB_VOLUME:/var/lib/postgresql/data" \
        postgres:latest
fi

# 4. Start Drupal Container
echo "[*] Starting Drupal Container..."
if docker ps -a --format '{{.Names}}' | grep -Eq "^${DRUPAL_CONTAINER}$"; then
    echo "[!] Container '$DRUPAL_CONTAINER' already exists. Removing it..."
    docker rm -f "$DRUPAL_CONTAINER"
fi

docker run -d \
    --name "$DRUPAL_CONTAINER" \
    --network "$NETWORK_NAME" \
    -p "${DRUPAL_PORT}:80" \
    -v "$DRUPAL_VOLUME:/var/www/html" \
    drupal:latest

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
echo " - Database User: ${DB_USER} (or root for MySQL)"
echo " - Database Password: ${DB_PASSWORD} (or ${DB_ROOT_PASSWORD} for root)"
echo " - Database Host: $DB_CONTAINER (not localhost)"
echo " - Database Port: (3306 for MySQL, 5432 for Postgres)"
echo "=================================================="
