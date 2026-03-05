#!/bin/bash
set -e

# Цвета для вывода
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== Развёртывание демонстрационного стенда бэкапов PostgreSQL ===${NC}"

# Проверка наличия необходимых команд
for cmd in docker docker-compose gpg; do
    if ! command -v $cmd &> /dev/null; then
        echo -e "${YELLOW}Ошибка: $cmd не установлен. Установите его и повторите.${NC}"
        exit 1
    fi
done

# Создание необходимых каталогов, если их нет
echo "Создание структуры каталогов data/ и keys/ (если отсутствуют)..."
mkdir -p data/temp data/logs keys

# Генерация ключей GPG, если они ещё не существуют
if [ ! -f keys/public.gpg ] || [ ! -f keys/private.gpg ]; then
    echo "Генерация ключей GPG (неинтерактивно)..."
    # Создаём временный каталог для GPG
    export GNUPGHOME=$(mktemp -d)
    
    # Генерируем ключ в batch-режиме
    cat >gen-key-script <<EOF
%echo Generating backup key
Key-Type: RSA
Key-Length: 4096
Subkey-Type: RSA
Subkey-Length: 4096
Name-Real: Backup User
Name-Email: backup@local
Expire-Date: 0
%no-protection
%commit
%echo Done
EOF

    gpg --batch --generate-key gen-key-script
    rm -f gen-key-script

    # Экспортируем ключи
    gpg --export --armor backup@local > keys/public.gpg
    gpg --export-secret-key --armor backup@local > keys/private.gpg

    # Удаляем временный каталог GPG
    rm -rf "$GNUPGHOME"
    unset GNUPGHOME
    echo "Ключи сохранены в папку keys/"
else
    echo "Ключи GPG уже существуют, пропускаем генерацию."
fi

# Создание .env файла из .env.example, если его нет
if [ ! -f .env ]; then
    if [ -f .env.example ]; then
        echo "Создание .env файла из .env.example..."
        cp .env.example .env
        echo ".env создан. При необходимости отредактируйте его."
    else
        echo -e "${YELLOW}Предупреждение: .env.example не найден. Создаём .env с настройками по умолчанию.${NC}"
        cat > .env <<EOF
POSTGRES_DB=mydb
POSTGRES_USER=myuser
POSTGRES_PASSWORD=strongpassword
POSTGRES_HOST=db

MINIO_ROOT_USER=minioadmin
MINIO_ROOT_PASSWORD=minioadmin
MINIO_BUCKET=backups
MINIO_ENDPOINT=minio:9000
EOF
    fi
else
    echo ".env уже существует, используем его."
fi

# Запуск контейнеров
echo "Запуск контейнеров..."
docker compose up -d --build

# Ожидание готовности
echo "Ожидание готовности сервисов..."
sleep 10

# Добавление тестовых данных
echo "Добавление тестовых данных в PostgreSQL..."
docker exec -i backup-db psql -U myuser -d mydb <<EOF 2>/dev/null || true
CREATE TABLE IF NOT EXISTS test_users (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
INSERT INTO test_users (name) VALUES ('Alice'), ('Bob'), ('Charlie') ON CONFLICT DO NOTHING;
EOF

echo -e "${GREEN}=== Развёртывание завершено ===${NC}"
echo -e "${YELLOW}MinIO UI: http://localhost:9001 (логин/пароль: minioadmin/minioadmin)${NC}"
echo -e "${YELLOW}Логи бэкапов: tail -f data/logs/backup.log${NC}"
echo -e "${YELLOW}Ручной запуск бэкапа: docker exec backup-backuper /scripts/backup.sh${NC}"
echo -e "${YELLOW}Восстановление: docker exec -it backup-backuper /scripts/restore.sh${NC}"
