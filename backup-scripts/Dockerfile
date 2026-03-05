FROM alpine:latest

# Установка необходимых пакетов
RUN apk add --no-cache \
    postgresql-client \
    gnupg \
    bash \
    dcron \
    curl \
    && rm -rf /var/cache/apk/*

# Установка MinIO Client (mc)
RUN curl -o /usr/local/bin/mc https://dl.min.io/client/mc/release/linux-amd64/mc \
    && chmod +x /usr/local/bin/mc

# Создание директорий
RUN mkdir -p /scripts /data /var/log/cron

# Копирование скриптов (будут перезаписаны томом, но для образа нужны)
COPY backup.sh restore.sh /scripts/
RUN chmod +x /scripts/*.sh

# Копирование entrypoint-скрипта
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Настройка cron задачи (будет создана динамически в entrypoint)
# Поэтому здесь не добавляем crontab

WORKDIR /scripts

ENTRYPOINT ["/entrypoint.sh"]
