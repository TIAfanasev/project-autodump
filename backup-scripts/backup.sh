#!/bin/bash
set -e

LOG_FILE="/var/log/cron/backup.log"
ERROR_LOG_FILE="/var/log/cron/backup_error.log"

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

error_log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1" | tee -a "$ERROR_LOG_FILE" >&2
}

main() {
    log "=== Запуск резервного копирования (GPG) ==="

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

    # Проверка наличия GPG ключа
    KEY_ID=$(gpg --list-keys --with-colons 2>/dev/null | grep '^pub' | head -1 | cut -d':' -f5)
    if [ -z "$KEY_ID" ]; then
        error_log "Не найден GPG публичный ключ. Импортируйте ключ в /keys/public.gpg"
        exit 1
    fi
    log "Используется GPG ключ: $KEY_ID"

    # Настройка MinIO алиаса
    if ! mc alias list myminio &>/dev/null; then
        mc alias set myminio "http://${MINIO_ENDPOINT}" "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD" 2>> "$ERROR_LOG_FILE"
    fi

    mkdir -p /data
    TIMESTAMP=$(date +'%Y%m%d_%H%M%S')
    DUMP_FILE="/data/${POSTGRES_DB}_${TIMESTAMP}.sql"
    ENCRYPTED_FILE="${DUMP_FILE}.gpg"

    # Дамп
    log "Создание дампа базы данных..."
    PGPASSWORD="$POSTGRES_PASSWORD" pg_dump -h "$POSTGRES_HOST" -U "$POSTGRES_USER" "$POSTGRES_DB" > "$DUMP_FILE" 2>> "$ERROR_LOG_FILE"
    if [ $? -ne 0 ] || [ ! -s "$DUMP_FILE" ]; then
        error_log "Не удалось создать дамп."
        exit 1
    fi
    log "Дамп создан (размер: $(du -h "$DUMP_FILE" | cut -f1))"

    # Шифрование GPG
    log "Шифрование дампа GPG..."
    gpg --trust-model always --encrypt --recipient "$KEY_ID" --output "$ENCRYPTED_FILE" "$DUMP_FILE" 2>> "$ERROR_LOG_FILE"
    if [ $? -ne 0 ] || [ ! -s "$ENCRYPTED_FILE" ]; then
        error_log "Не удалось зашифровать дамп."
        exit 1
    fi
    log "Зашифрованный файл создан (размер: $(du -h "$ENCRYPTED_FILE" | cut -f1))"

    # Загрузка в MinIO
    log "Загрузка в MinIO..."
    mc cp "$ENCRYPTED_FILE" "myminio/$MINIO_BUCKET/" 2>> "$ERROR_LOG_FILE"
    if [ $? -ne 0 ]; then
        error_log "Не удалось загрузить файл."
        exit 1
    fi
    log "Файл успешно загружен: $ENCRYPTED_FILE"

    # Очистка
    rm -f "$DUMP_FILE" "$ENCRYPTED_FILE"
    log "Временные файлы удалены."
    log "=== Резервное копирование завершено ==="
}

main
