#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

DB_TYPE="${DB_TYPE:-postgres}"
DB_CONTAINER="${DB_CONTAINER:-postgres-db}"
DRUPAL_CONTAINER="${DRUPAL_CONTAINER:-drupal-web}"
NETWORK_NAME="${NETWORK_NAME:-drupal-net}"
DB_VOLUME="${DB_VOLUME:-drupal-db-data}"
DRUPAL_VOLUME="${DRUPAL_VOLUME:-drupal-web-data}"
DB_NAME="${DB_NAME:-drupal_db}"
DB_USER="${DB_USER:-drupal_user}"
DB_PASSWORD="${DB_PASSWORD:-my-secret-pw}"
DB_ROOT_PASSWORD="${DB_ROOT_PASSWORD:-my-secret-pw}"
POSTGRES_SUPERUSER="${POSTGRES_SUPERUSER:-root}"
POSTGRES_IMAGE="${POSTGRES_IMAGE:-postgres:18}"
MYSQL_IMAGE="${MYSQL_IMAGE:-mysql:8.4}"
DRUPAL_IMAGE="${DRUPAL_IMAGE:-drupal:11-apache}"
DRUPAL_PORT="${DRUPAL_PORT:-8080}"
if [ "$DB_TYPE" = "mysql" ]; then
    DB_PORT="${DB_PORT:-3306}"
else
    DB_PORT="${DB_PORT:-5432}"
fi

require_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "[!] Error: Required command '$1' was not found." >&2
        exit 1
    fi
}

require_docker() {
    require_command docker
    if ! docker info >/dev/null 2>&1; then
        echo "[!] Error: Docker is installed, but the Docker engine is not running." >&2
        exit 1
    fi
}

container_exists() {
    docker container inspect "$1" >/dev/null 2>&1
}

container_running() {
    [ "$(docker inspect -f '{{.State.Running}}' "$1" 2>/dev/null || true)" = "true" ]
}

wait_for_postgres() {
    local attempts="${1:-60}"
    local count

    echo "[*] Waiting for PostgreSQL to accept connections..."
    for ((count = 1; count <= attempts; count++)); do
        if docker exec "$DB_CONTAINER" pg_isready -U "$POSTGRES_SUPERUSER" -d postgres >/dev/null 2>&1; then
            echo "[+] PostgreSQL is ready."
            return 0
        fi
        sleep 2
    done

    echo "[!] Error: PostgreSQL did not become ready in time." >&2
    docker logs "$DB_CONTAINER" >&2 || true
    return 1
}

wait_for_mysql() {
    local attempts="${1:-60}"
    local count

    echo "[*] Waiting for MySQL to accept connections..."
    for ((count = 1; count <= attempts; count++)); do
        if docker exec "$DB_CONTAINER" mysqladmin ping -uroot "-p$DB_ROOT_PASSWORD" --silent >/dev/null 2>&1; then
            echo "[+] MySQL is ready."
            return 0
        fi
        sleep 2
    done

    echo "[!] Error: MySQL did not become ready in time." >&2
    docker logs "$DB_CONTAINER" >&2 || true
    return 1
}

validate_db_type() {
    case "$DB_TYPE" in
        postgres|mysql) ;;
        *)
            echo "[!] Error: DB_TYPE must be 'postgres' or 'mysql', not '$DB_TYPE'." >&2
            exit 1
            ;;
    esac
}

validate_identifier() {
    local name="$1"
    local value="$2"

    if [[ ! "$value" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then
        echo "[!] Error: $name must be a valid SQL identifier, not '$value'." >&2
        exit 1
    fi
}

ensure_postgres_role() {
    local escaped_password="${DB_PASSWORD//\'/\'\'}"

    validate_identifier DB_USER "$DB_USER"
    docker exec "$DB_CONTAINER" psql \
        -v ON_ERROR_STOP=1 \
        -U "$POSTGRES_SUPERUSER" \
        -d postgres \
        -c "DO \$\$ BEGIN
                IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '$DB_USER') THEN
                    CREATE ROLE \"$DB_USER\" LOGIN PASSWORD '$escaped_password';
                ELSE
                    ALTER ROLE \"$DB_USER\" WITH LOGIN PASSWORD '$escaped_password';
                END IF;
            END \$\$;"
}
