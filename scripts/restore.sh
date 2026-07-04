#!/usr/bin/env bash

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/common.sh"

# ==========================================
# CONFIGURATION VARIABLES
# ==========================================
validate_db_type
validate_identifier DB_NAME "$DB_NAME"
validate_identifier POSTGRES_SUPERUSER "$POSTGRES_SUPERUSER"
require_docker
require_command gunzip

echo "=================================================="
echo " Starting Drupal and Database Restore"
echo "=================================================="

# Check if containers are running
if ! container_running "$DB_CONTAINER"; then
    echo "[!] Error: Database container '$DB_CONTAINER' is not running!"
    exit 1
fi
if ! container_running "$DRUPAL_CONTAINER"; then
    echo "[!] Error: Drupal container '$DRUPAL_CONTAINER' is not running!"
    exit 1
fi

# 1. Restore Drupal Files (Volume)
FILES_BACKUP="drupal_files_backup.tar.gz"
if [ -f "$FILES_BACKUP" ]; then
    echo "[*] Restoring Drupal files volume ($DRUPAL_VOLUME) from $FILES_BACKUP..."
    
    docker exec "$DRUPAL_CONTAINER" find /var/www/html -mindepth 1 -maxdepth 1 -exec rm -rf '{}' +
    gunzip < "$FILES_BACKUP" | docker cp - "$DRUPAL_CONTAINER":/var/www/html/
    echo "[+] Volume restore completed successfully."
else
    echo "[!] Warning: Volume backup file '$FILES_BACKUP' not found! Skipping files restore."
fi

# 2. Restore Database
if [ "$DB_TYPE" = "mysql" ]; then
    BACKUP_FILE="my-drupal.backup.sql.gz"
    if [ -f "$BACKUP_FILE" ]; then
        echo "[*] Restoring MySQL database from $BACKUP_FILE..."
        
        # 2a. Recreate database (per PDF instructions)
        echo "[*] Recreating database '$DB_NAME'..."
        # First drop if exists to ensure clean restore, then create
        docker exec "$DB_CONTAINER" mysqladmin -uroot "-p$DB_ROOT_PASSWORD" -f drop "$DB_NAME" >/dev/null 2>&1 || true
        docker exec "$DB_CONTAINER" mysqladmin -uroot "-p$DB_ROOT_PASSWORD" create "$DB_NAME"
        
        # 2b. Import database (per PDF instructions)
        echo "[*] Importing SQL backup..."
        gunzip < "$BACKUP_FILE" |
            docker exec -i "$DB_CONTAINER" mysql -h 127.0.0.1 "-u$DB_USER" "-p$DB_PASSWORD" "$DB_NAME"
        echo "[+] MySQL database restore completed successfully."
    else
        echo "[!] Error: Database backup file '$BACKUP_FILE' not found!"
        exit 1
    fi
else
    # PostgreSQL
    BACKUP_FILE="drupal_db_backup.sql"
    if [ -f "$BACKUP_FILE" ]; then
        echo "[*] Restoring PostgreSQL database from $BACKUP_FILE..."
        
        # Recreate database to ensure clean restore
        echo "[*] Recreating database '$DB_NAME'..."
        docker exec "$DB_CONTAINER" psql \
            -v ON_ERROR_STOP=1 \
            -U "$POSTGRES_SUPERUSER" \
            -d postgres \
            -c "DROP DATABASE IF EXISTS \"$DB_NAME\" WITH (FORCE);" \
            -c "CREATE DATABASE \"$DB_NAME\";"

        echo "[*] Creating database user '$DB_USER'..."
        ensure_postgres_role
        docker exec "$DB_CONTAINER" psql \
            -v ON_ERROR_STOP=1 \
            -U "$POSTGRES_SUPERUSER" \
            -d postgres \
            -c "GRANT ALL PRIVILEGES ON DATABASE \"$DB_NAME\" TO \"$DB_USER\";"

        echo "[*] Importing SQL backup..."
        docker exec -i "$DB_CONTAINER" psql \
            -v ON_ERROR_STOP=1 \
            -U "$POSTGRES_SUPERUSER" \
            -d "$DB_NAME" < "$BACKUP_FILE"
        echo "[+] PostgreSQL database restore completed successfully."
    else
        echo "[!] Error: Database backup file '$BACKUP_FILE' not found!"
        exit 1
    fi
fi

# 3. Restore settings.php configuration
if [ -f "settings.php" ]; then
    echo "[*] Copying settings.php configuration to Drupal container..."
    docker exec "$DRUPAL_CONTAINER" mkdir -p /var/www/html/sites/default
    docker cp settings.php "$DRUPAL_CONTAINER":/var/www/html/sites/default/settings.php
    docker exec "$DRUPAL_CONTAINER" chown www-data:www-data /var/www/html/sites/default/settings.php
    docker exec "$DRUPAL_CONTAINER" chmod 644 /var/www/html/sites/default/settings.php
    echo "[+] settings.php copied and permissions set successfully."
else
    echo "[!] Warning: settings.php not found in workspace root!"
fi

# 4. Restart Drupal service to apply changes
echo "[*] Restarting Drupal container to apply restored data..."
docker restart "$DRUPAL_CONTAINER"

echo "=================================================="
echo " Restore completed successfully!"
echo " Feel free to open http://localhost:$DRUPAL_PORT"
echo "=================================================="
