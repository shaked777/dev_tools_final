#!/bin/bash

# ==========================================
# CONFIGURATION VARIABLES
# ==========================================
DB_TYPE="postgres"             # Database type: "mysql" or "postgres"
DB_CONTAINER="postgres-db"     # Name of the database container
DRUPAL_CONTAINER="drupal-web" # Name of the Drupal container
DB_NAME="drupal_db"           # Name of the database
DB_ROOT_PASSWORD="my-secret-pw" # Root password (Must be my-secret-pw)
DRUPAL_VOLUME="drupal-web-data" # Name of the Drupal volume to backup

echo "=================================================="
echo " Starting Drupal and Database Backup"
echo "=================================================="

# Check if containers are running
if ! docker ps --format '{{.Names}}' | grep -Eq "^${DB_CONTAINER}$"; then
    echo "[!] Error: Database container '$DB_CONTAINER' is not running!"
    exit 1
fi

# 1. Perform Database Backup
if [ "$DB_TYPE" = "mysql" ]; then
    BACKUP_FILE="my-drupal.backup.sql.gz"
    echo "[*] Backing up MySQL database to $BACKUP_FILE..."
    
    # Run the exact backup command as specified in the project PDF instructions
    docker exec "$DB_CONTAINER" sh -c 'exec mysqldump --all-databases -uroot -p$MYSQL_ROOT_PASSWORD' | gzip > "$BACKUP_FILE"
    
    if [ ${PIPESTATUS[0]} -eq 0 ] && [ -f "$BACKUP_FILE" ]; then
        echo "[+] Database backup completed successfully: $BACKUP_FILE"
    else
        echo "[!] Error: Database backup failed!"
        exit 1
    fi
else
    # PostgreSQL
    BACKUP_FILE="drupal_db_backup.sql"
    echo "[*] Backing up PostgreSQL database to $BACKUP_FILE..."
    
    # Run the exact backup command as specified in the project PDF instructions
    docker exec "$DB_CONTAINER" sh -c "exec pg_dump -U root \"$DB_NAME\"" > "$BACKUP_FILE"
    
    if [ $? -eq 0 ] && [ -f "$BACKUP_FILE" ]; then
        echo "[+] Database backup completed successfully: $BACKUP_FILE"
    else
        echo "[!] Error: Database backup failed!"
        exit 1
    fi
fi

# 2. Perform Drupal Files (Volume) Backup
FILES_BACKUP="drupal_files_backup.tar.gz"
echo "[*] Backing up Drupal files volume ($DRUPAL_VOLUME) to $FILES_BACKUP..."

# We stream the directory directly from the container via docker cp to stdout and compress it.
# This works regardless of host path issues (like on Windows/macOS) and works even if container is stopped.
docker cp "$DRUPAL_CONTAINER":/var/www/html/. - | gzip > "$FILES_BACKUP"

if [ ${PIPESTATUS[0]} -eq 0 ] && [ -f "$FILES_BACKUP" ]; then
    echo "[+] Volume backup completed successfully: $FILES_BACKUP"
else
    echo "[!] Warning: Direct docker cp backup failed. Trying helper container fallback..."
    docker run --rm \
        -v "$DRUPAL_VOLUME:/volume_data" \
        -v "$(pwd):/backup_dir" \
        alpine tar -czf "/backup_dir/$FILES_BACKUP" -C /volume_data .
    
    if [ $? -eq 0 ] && [ -f "$FILES_BACKUP" ]; then
        echo "[+] Helper container volume backup completed successfully."
    else
        echo "[!] Error: Drupal files backup failed completely!"
        exit 1
    fi
fi

echo "=================================================="
echo " Backup completed!"
echo " Files created:"
echo " - DB Backup:    $BACKUP_FILE"
echo " - Files Backup: $FILES_BACKUP"
echo "=================================================="
