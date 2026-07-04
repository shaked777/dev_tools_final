#!/usr/bin/env bash

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/common.sh"

# ==========================================
# CONFIGURATION VARIABLES
# ==========================================
validate_db_type
require_docker
require_command gzip

TEMP_BACKUP=""
TEMP_FILES_BACKUP=""
remove_partial_backups() {
    [ -z "$TEMP_BACKUP" ] || rm -f "$TEMP_BACKUP"
    [ -z "$TEMP_FILES_BACKUP" ] || rm -f "$TEMP_FILES_BACKUP"
}
trap remove_partial_backups EXIT

echo "=================================================="
echo " Starting Drupal and Database Backup"
echo "=================================================="

# Check if containers are running
if ! container_running "$DB_CONTAINER"; then
    echo "[!] Error: Database container '$DB_CONTAINER' is not running!"
    exit 1
fi

# 1. Perform Database Backup
if [ "$DB_TYPE" = "mysql" ]; then
    BACKUP_FILE="my-drupal.backup.sql.gz"
    TEMP_BACKUP="${BACKUP_FILE}.tmp"
    echo "[*] Backing up MySQL database to $BACKUP_FILE..."

    rm -f "$TEMP_BACKUP"
    docker exec "$DB_CONTAINER" mysqldump --all-databases -uroot "-p$DB_ROOT_PASSWORD" |
        gzip > "$TEMP_BACKUP"
    test -s "$TEMP_BACKUP"
    mv -f "$TEMP_BACKUP" "$BACKUP_FILE"
    echo "[+] Database backup completed successfully: $BACKUP_FILE"
else
    # PostgreSQL
    BACKUP_FILE="drupal_db_backup.sql"
    echo "[*] Backing up PostgreSQL database to $BACKUP_FILE..."
    
    TEMP_BACKUP="${BACKUP_FILE}.tmp"
    rm -f "$TEMP_BACKUP"
    docker exec "$DB_CONTAINER" pg_dump -U "$POSTGRES_SUPERUSER" "$DB_NAME" > "$TEMP_BACKUP"
    test -s "$TEMP_BACKUP"
    mv -f "$TEMP_BACKUP" "$BACKUP_FILE"
    echo "[+] Database backup completed successfully: $BACKUP_FILE"
fi

# 2. Perform Drupal Files (Volume) Backup
FILES_BACKUP="drupal_files_backup.tar.gz"
TEMP_FILES_BACKUP="${FILES_BACKUP}.tmp"
echo "[*] Backing up Drupal files volume ($DRUPAL_VOLUME) to $FILES_BACKUP..."

if ! container_exists "$DRUPAL_CONTAINER"; then
    echo "[!] Error: Drupal container '$DRUPAL_CONTAINER' does not exist!" >&2
    exit 1
fi

rm -f "$TEMP_FILES_BACKUP"
docker cp "$DRUPAL_CONTAINER":/var/www/html/. - | gzip > "$TEMP_FILES_BACKUP"
test -s "$TEMP_FILES_BACKUP"
mv -f "$TEMP_FILES_BACKUP" "$FILES_BACKUP"
echo "[+] Volume backup completed successfully: $FILES_BACKUP"
trap - EXIT

echo "=================================================="
echo " Backup completed!"
echo " Files created:"
echo " - DB Backup:    $BACKUP_FILE"
echo " - Files Backup: $FILES_BACKUP"
echo "=================================================="
