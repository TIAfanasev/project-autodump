#!/bin/bash
set -e

LOG_FILE="/var/log/cron/restore.log"
ERROR_LOG_FILE="/var/log/cron/restore_error.log"

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

error_log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1" | tee -a "$ERROR_LOG_FILE" >&2
}

usage() {
    echo "Использование: $0 [имя_файла_бэкапа]"
    exit 1
}

# Проверка наличия приватного ключа GPG
if [ ! -f /keys/private.gpg ]; then
    error_log "Приватный ключ GPG не найден в /keys/private.gpg. Расшифровка невозможна."
    exit 1
fi

# Импорт приватного ключа (если ещё не импортирован)
if ! gpg --list-secret-keys | grep -q 'sec'; then
    log "Импорт приватного ключа GPG..."
    gpg --import /keys/private.gpg
fi

# Проверка переменных
required_vars=(
    "POSTGRES_DB" "POSTGRES_USER" "POSTGRES_PASSWORD" "POSTGRES_HOST"
    "MINIO_BUCKET" "MINIO_ENDPOINT" "MINIO_ROOT_USER" "MINIO_ROOT_PASSWORD"
)
for var in "${required_vars[@]}"; do
    if [ -z "${!var}" ]; then
        error_log "Переменная окружения $var не установлена."
        exit 1
    fi
done

# Настройка MinIO алиаса
if ! mc alias list myminio &>/dev/null; then
    mc alias set myminio "http://${MINIO_ENDPOINT}" "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD" 2>> "$ERROR_LOG_FILE"
fi

# Функция получения списка бэкапов
list_backups() {
    mc ls myminio/$MINIO_BUCKET/ 2>/dev/null | awk '{print $6}' | grep '\.gpg$' || true
}

# Выбор файла для восстановления
if [ $# -eq 0 ]; then
    echo "Доступные резервные копии (GPG):"
    BACKUP_LIST=$(list_backups)
    if [ -z "$BACKUP_LIST" ]; then
        error_log "Нет .gpg файлов в бакете."
        exit 1
    fi
    echo "$BACKUP_LIST" | nl -w2 -s'. '
    echo ""
    read -p "Введите номер или имя файла: " CHOICE
    if [[ "$CHOICE" =~ ^[0-9]+$ ]]; then
        BACKUP_FILE=$(echo "$BACKUP_LIST" | sed -n "${CHOICE}p")
    else
        BACKUP_FILE="$CHOICE"
    fi
else
    BACKUP_FILE="$1"
fi

log "Выбран файл: $BACKUP_FILE"

# Проверка наличия файла в MinIO
if ! mc ls "myminio/$MINIO_BUCKET/$BACKUP_FILE" &>/dev/null; then
    error_log "Файл не найден."
    exit 1
fi

TEMP_DIR="/data/restore/$$"
mkdir -p "$TEMP_DIR"

# Скачивание
log "Скачивание файла..."
mc cp "myminio/$MINIO_BUCKET/$BACKUP_FILE" "$TEMP_DIR/" 2>> "$ERROR_LOG_FILE"

ENCRYPTED_FILE="$TEMP_DIR/$BACKUP_FILE"
DECRYPTED_FILE="${ENCRYPTED_FILE%.gpg}.sql"

# Расшифровка GPG
log "Расшифровка GPG..."
gpg --decrypt --output "$DECRYPTED_FILE" "$ENCRYPTED_FILE" 2>> "$ERROR_LOG_FILE"
if [ $? -ne 0 ]; then
    error_log "Не удалось расшифровать."
    rm -rf "$TEMP_DIR"
    exit 1
fi

# Восстановление
log "Удаление старой базы (если есть)..."
PGPASSWORD="$POSTGRES_PASSWORD" dropdb -h "$POSTGRES_HOST" -U "$POSTGRES_USER" --if-exists "$POSTGRES_DB" 2>> "$ERROR_LOG_FILE"

log "Создание новой базы..."
PGPASSWORD="$POSTGRES_PASSWORD" createdb -h "$POSTGRES_HOST" -U "$POSTGRES_USER" "$POSTGRES_DB" 2>> "$ERROR_LOG_FILE"

log "Импорт данных..."
PGPASSWORD="$POSTGRES_PASSWORD" psql -h "$POSTGRES_HOST" -U "$POSTGRES_USER" -d "$POSTGRES_DB" -f "$DECRYPTED_FILE" 2>> "$ERROR_LOG_FILE"

log "Восстановление успешно завершено."
rm -rf "$TEMP_DIR"
