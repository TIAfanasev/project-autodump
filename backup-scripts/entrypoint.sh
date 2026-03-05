cat > backup-scripts/entrypoint.sh << 'EOF'
#!/bin/bash

echo "=== Настройка контейнера backuper ==="

# Настройка MinIO клиента
if [ -n "$MINIO_ENDPOINT" ] && [ -n "$MINIO_ROOT_USER" ] && [ -n "$MINIO_ROOT_PASSWORD" ]; then
    echo "Настройка MinIO клиента..."
    mc alias set myminio "http://${MINIO_ENDPOINT}" "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD"
    if [ $? -ne 0 ]; then
        echo "ОШИБКА: не удалось настроить MinIO алиас. Проверьте доступность MinIO."
    fi
else
    echo "ОШИБКА: переменные MinIO не заданы"
    exit 1
fi

# Импорт публичного ключа GPG
if [ -f /keys/public.gpg ]; then
    echo "Импорт публичного ключа GPG..."
    gpg --import /keys/public.gpg
    if [ $? -eq 0 ]; then
        KEY_ID=$(gpg --list-keys --with-colons | grep '^pub' | head -1 | cut -d':' -f5)
        if [ -n "$KEY_ID" ]; then
            echo "Ключ импортирован: $KEY_ID"
            # Устанавливаем доверие без интерактива (ошибки игнорируем, т.к. не критично)
            echo -e "5\ny\n" | gpg --batch --yes --command-fd 0 --edit-key "$KEY_ID" trust 2>/dev/null || echo "Предупреждение: не удалось установить доверие (не критично)"
        fi
    else
        echo "ОШИБКА: не удалось импортировать GPG ключ"
    fi
else
    echo "Предупреждение: публичный ключ GPG не найден в /keys/public.gpg. Шифрование будет недоступно."
fi

# Настройка crontab
CRON_SCHEDULE=${CRON_SCHEDULE:-"*/5 * * * *"}
echo "Установка расписания cron: $CRON_SCHEDULE"
echo "$CRON_SCHEDULE /scripts/backup.sh >> /var/log/cron/backup.log 2>&1" > /etc/crontabs/root

# Запуск crond в фоне (демон)
echo "Запуск crond в фоне..."
crond

# Бесконечное ожидание, чтобы контейнер не завершился
echo "Контейнер готов. Ожидание команд..."
tail -f /dev/null
EOF

chmod +x backup-scripts/entrypoint.sh