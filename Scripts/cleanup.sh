#!/bin/bash

# ==========================================
# CONFIGURATION VARIABLES
# ==========================================
DB_TYPE="mysql"               # Database type: "mysql" or "postgres"
DB_CONTAINER="drupal-db"      # Name of the database container
DRUPAL_CONTAINER="drupal-web" # Name of the Drupal container
NETWORK_NAME="drupal-net"     # Name of the Docker network
DB_VOLUME="drupal-db-data"    # Name of the DB volume
DRUPAL_VOLUME="drupal-web-data" # Name of the Drupal volume

echo "=================================================="
echo " Starting Drupal and Database Cleanup"
echo "=================================================="

# 1. Stop and remove containers
for container in "$DRUPAL_CONTAINER" "$DB_CONTAINER"; do
    if docker ps -a --format '{{.Names}}' | grep -Eq "^${container}$"; then
        echo "[*] Stopping container '$container'..."
        docker stop "$container" >/dev/null 2>&1
        echo "[*] Removing container '$container'..."
        docker rm "$container" >/dev/null 2>&1
        echo "[+] Container '$container' removed."
    else
        echo "[+] Container '$container' is already gone."
    fi
done

# 2. Remove Docker network
if docker network inspect "$NETWORK_NAME" >/dev/null 2>&1; then
    echo "[*] Removing network '$NETWORK_NAME'..."
    docker network rm "$NETWORK_NAME" >/dev/null 2>&1
    echo "[+] Network '$NETWORK_NAME' removed."
else
    echo "[+] Network '$NETWORK_NAME' is already gone."
fi

# 3. Remove Docker volumes
for vol in "$DRUPAL_VOLUME" "$DB_VOLUME"; do
    if docker volume inspect "$vol" >/dev/null 2>&1; then
        echo "[*] Removing volume '$vol'..."
        docker volume rm "$vol" >/dev/null 2>&1
        echo "[+] Volume '$vol' removed."
    else
        echo "[+] Volume '$vol' is already gone."
    fi
done

# 4. Remove Docker images
DB_IMAGE="mysql:latest"
if [ "$DB_TYPE" != "mysql" ]; then
    DB_IMAGE="postgres:latest"
fi

for img in "drupal:latest" "$DB_IMAGE"; do
    if docker image inspect "$img" >/dev/null 2>&1; then
        echo "[*] Removing Docker image '$img'..."
        docker rmi "$img" >/dev/null 2>&1
        echo "[+] Image '$img' removed."
    else
        echo "[+] Image '$img' is not present."
    fi
done

# 5. Remove generated backup files
echo "[*] Removing backup files..."
rm -f my-drupal.backup.sql.gz drupal_db_backup.sql drupal_files_backup.tar.gz
echo "[+] Backup files deleted."

echo "=================================================="
echo " Cleanup completed!"
echo " Workspace and Docker environment are clean."
echo "=================================================="
