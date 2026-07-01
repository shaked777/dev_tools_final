#!/bin/bash

# ==========================================
# CONFIGURATION VARIABLES
# ==========================================
DB_TYPE="mysql"               # Database type: "mysql" or "postgres"
DB_CONTAINER="drupal-db"      # Name of the database container
DRUPAL_CONTAINER="drupal-web" # Name of the Drupal container
DB_NAME="drupal_db"           # Name of the database
DB_USER="drupal"              # Database username
DB_PASSWORD="drupal_password" # Database user password
DB_ROOT_PASSWORD="my-secret-pw" # Root password
DRUPAL_VOLUME="drupal-web-data" # Name of the Drupal volume

echo "=================================================="
echo " Starting Drupal and Database Restore"
echo "=================================================="

# Check if containers are running
if ! docker ps --format '{{.Names}}' | grep -Eq "^${DB_CONTAINER}$"; then
    echo "[!] Error: Database container '$DB_CONTAINER' is not running!"
    exit 1
fi
if ! docker ps --format '{{.Names}}' | grep -Eq "^${DRUPAL_CONTAINER}$"; then
    echo "[!] Error: Drupal container '$DRUPAL_CONTAINER' is not running!"
    exit 1
fi

# 1. Restore Drupal Files (Volume)
FILES_BACKUP="drupal_files_backup.tar.gz"
if [ -f "$FILES_BACKUP" ]; then
    echo "[*] Restoring Drupal files volume ($DRUPAL_VOLUME) from $FILES_BACKUP..."
    
    # We clear the container directory first to ensure a clean restore,
    # then pipe the compressed archive directly into docker cp.
    docker exec "$DRUPAL_CONTAINER" sh -c "rm -rf /var/www/html/*" && \
    gunzip < "$FILES_BACKUP" | docker cp - "$DRUPAL_CONTAINER":/var/www/html/
        
    if [ $? -eq 0 ]; then
        echo "[+] Volume restore completed successfully."
    else
        echo "[!] Warning: Direct docker cp restore failed. Trying helper container fallback..."
        docker run --rm \
            -v "$DRUPAL_VOLUME:/volume_data" \
            -v "$(pwd):/backup_dir" \
            alpine sh -c "rm -rf /volume_data/* && tar -xzf /backup_dir/$FILES_BACKUP -C /volume_data"
            
        if [ $? -eq 0 ]; then
            echo "[+] Helper container volume restore completed successfully."
        else
            echo "[!] Error: Volume restore failed!"
            exit 1
        fi
    fi
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
        docker exec "$DB_CONTAINER" sh -c "exec mysqladmin -uroot -p'$DB_ROOT_PASSWORD' -f drop $DB_NAME" >/dev/null 2>&1
        docker exec "$DB_CONTAINER" sh -c "exec mysqladmin -uroot -p'$DB_ROOT_PASSWORD' create $DB_NAME"
        
        # 2b. Import database (per PDF instructions)
        echo "[*] Importing SQL backup..."
        gunzip < "$BACKUP_FILE" | docker exec -i "$DB_CONTAINER" sh -c "exec mysql -h 127.0.0.1 -u$DB_USER -p$DB_PASSWORD --force $DB_NAME"
        
        if [ $? -eq 0 ]; then
            echo "[+] MySQL database restore completed successfully."
        else
            echo "[!] Error: MySQL database restore failed!"
            exit 1
        fi
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
        docker exec "$DB_CONTAINER" sh -c "psql -U root -c 'DROP DATABASE IF EXISTS \"$DB_NAME\";'"
        docker exec "$DB_CONTAINER" sh -c "psql -U root -c 'CREATE DATABASE \"$DB_NAME\";'"
        
        # Import data (per PDF instructions)
        docker exec -i "$DB_CONTAINER" psql -U root "$DB_NAME" < "$BACKUP_FILE"
        
        if [ $? -eq 0 ]; then
            echo "[+] PostgreSQL database restore completed successfully."
        else
            echo "[!] Error: PostgreSQL database restore failed!"
            exit 1
        fi
    else
        echo "[!] Error: Database backup file '$BACKUP_FILE' not found!"
        exit 1
    fi
fi

# 3. Restart Drupal service to apply changes
echo "[*] Restarting Drupal container to apply restored data..."
docker restart "$DRUPAL_CONTAINER"

echo "=================================================="
echo " Restore completed successfully!"
echo " Feel free to open http://localhost:8080"
echo "=================================================="
