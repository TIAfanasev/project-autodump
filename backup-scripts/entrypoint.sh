#!/bin/bash
set -e

echo "=== Настройка контейнера backuper ==="

# Настройка MinIO алиаса
if [ -n "$MINIO_ENDPOINT" ] && [ -n "$MINIO_ROOT_USER" ] && [ -n "$MINIO_ROOT_PASSWORD" ]; then
    echo "Настройка MinIO клиента..."
    mc alias set myminio "http://${MINIO_ENDPOINT}" "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD"
else
    echo "Ошибка: переменные MinIO не заданы"
    exit 1
fi

# Импорт публичного ключа GPG (если есть)
if [ -f /keys/public.gpg ]; then
    echo "Импорт публичного ключа GPG..."
    gpg --import /keys/public.gpg
    # Устанавливаем доверие (для автоматического шифрования)
    KEY_ID=$(gpg --list-keys --with-colons | grep '^pub' | cut -d':' -f5)
    if [ -n "$KEY_ID" ]; then
        echo "Ключ импортирован: $KEY_ID"
        # Доверие ключу (5 = ultimate) для неинтерактивного режима
        echo -e "5\ny\n" | gpg --command-fd 0 --edit-key "$KEY_ID" trust
    fi
else
    echo "Предупреждение: публичный ключ GPG не найден в /keys/public.gpg. Шифрование будет недоступно."
fi

# Настройка crontab
CRON_SCHEDULE=${CRON_SCHEDULE:-"*/5 * * * *"}
echo "Установка расписания cron: $CRON_SCHEDULE"
echo "$CRON_SCHEDULE /scripts/backup.sh >> /var/log/cron/backup.log 2>&1" > /etc/crontabs/root

echo "Запуск crond..."
crond -f -l 2
