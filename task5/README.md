# MongoDB Full Stack: Sharding + Replication + Redis + API Gateway + Consul

Полный стек для демонстрации масштабируемой архитектуры с MongoDB шардированием, репликацией, Redis кешированием, API Gateway (Nginx) и Service Discovery (Consul).

## Архитектура

### База данных (MongoDB)
- **Config Server** (configSrv) - хранит метаданные о шардах
- **Mongos Router** (mongos_router) - маршрутизатор запросов
- **Shard 1** с 3 репликами:
  - shard1-1 (PRIMARY) - порт 27018
  - shard1-2 (SECONDARY) - порт 27021
  - shard1-3 (SECONDARY) - порт 27022
- **Shard 2** с 3 репликами:
  - shard2-1 (PRIMARY) - порт 27019
  - shard2-2 (SECONDARY) - порт 27023
  - shard2-3 (SECONDARY) - порт 27024

### Кеширование
- **Redis Cache** (redis) - кеширование запросов к MongoDB

### Service Discovery
- **Consul** (consul) - реестр сервисов и health checks

### API Layer
- **API Application** (pymongo_api) - FastAPI приложение
- **Nginx API Gateway** (nginx_gateway) - точка входа для всех запросов

## Запуск проекта

### 1. Запустите контейнеры

```bash
docker compose up -d
```

### 2. Дождитесь запуска всех сервисов

Проверьте статус сервисов:

```bash
docker compose ps
```

Все 12 сервисов должны быть в статусе "running".

### 3. Автоматическая инициализация MongoDB

```bash
./scripts/mongo-init-full-stack.sh
```

## Доступ к сервисам

### API через Nginx Gateway
- **http://localhost** - доступ к API через Nginx (порт 80)
- **http://localhost:8080** - альтернативный порт Nginx

### Consul UI
- **http://localhost:8500** - веб-интерфейс Consul

### Прямой доступ к API (минуя Nginx)
- **http://pymongo_api:8080** - только внутри Docker сети

## Проверка работы

### Проверка через API Gateway

```bash
curl http://localhost
```

Должно вернуть JSON с:
- `cache_enabled: true` - кеширование включено
- Информация о шардах с репликами
- Статус MongoDB и Redis

### Проверка Consul

Откройте http://localhost:8500 в браузере для доступа к Consul UI.

### Проверка Nginx Health

```bash
curl http://localhost/health
```

## Тестирование

### Тест 1: Балансировка нагрузки через API Gateway

```bash
for i in {1..10}; do
  curl -s http://localhost | jq '.mongo_address'
done
```

### Тест 2: Остановка Redis (проверка отказоустойчивости)

```bash
docker compose stop redis
curl http://localhost
docker compose start redis
```

### Тест 3: Остановка реплики MongoDB

```bash
docker compose stop shard1-2
curl http://localhost
docker compose start shard1-2
```

### Тест 4: Проверка времени ответа с кешем

```bash
# Первый запрос (без кеша)
time curl http://localhost

# Последующие запросы (с кешем) - должны быть быстрее
time curl http://localhost
```

## Мониторинг

### Проверка здоровья сервисов в Consul

```bash
curl http://localhost:8500/v1/health/service/pymongo_api
```

### Логи Nginx

```bash
docker compose logs -f nginx
```

### Статус MongoDB Replica Sets

```bash
docker compose exec shard1-1 mongosh --port 27018 --quiet --eval "rs.status()"
```

### Статистика Redis

```bash
docker compose exec redis redis-cli INFO stats
```

## Архитектурные преимущества

1. **Высокая доступность**
   - 3 реплики на каждый шард
   - Автоматический failover при отказе PRIMARY

2. **Масштабируемость**
   - Горизонтальное масштабирование через шардирование
   - Легко добавить новые шарды

3. **Производительность**
   - Redis кеширование для повторяющихся запросов
   - Чтение с SECONDARY реплик (опционально)

4. **Service Discovery**
   - Consul автоматически отслеживает здоровье сервисов
   - Динамическое обнаружение сервисов

5. **API Gateway**
   - Единая точка входа
   - Балансировка нагрузки
   - Централизованное логирование

## Порты

### Внешние порты
- **80** - Nginx API Gateway (HTTP)
- **8080** - Nginx API Gateway (альтернативный порт)
- **8500** - Consul UI
- **6379** - Redis
- **27017** - MongoDB Config Server
- **27018** - Shard 1 - Replica 1
- **27021** - Shard 1 - Replica 2
- **27022** - Shard 1 - Replica 3
- **27019** - Shard 2 - Replica 1
- **27023** - Shard 2 - Replica 2
- **27024** - Shard 2 - Replica 3
- **27020** - Mongos Router

## Конфигурация

### Nginx (nginx.conf)
- Проксирует запросы к pymongo_api
- Health check endpoint: `/health`
- Заголовки для корректной работы с API

### Consul
- Server mode с UI
- Порты: 8500 (HTTP), 8600 (DNS)
- Хранилище данных в volume

### MongoDB
- Хеш-шардирование по полю "name"
- Write Concern: majority
- Read Preference: primary

### Redis
- AOF persistence
- Автоматическое переподключение

## Остановка проекта

```bash
docker compose down
```

## Полная очистка (включая volumes)

```bash
docker compose down -v
```

## Требования

- Docker и Docker Compose
- Минимум 4 CPU и 8 GB RAM (рекомендуется 8 GB RAM)

## Troubleshooting

### Nginx не запускается

```bash
# Проверьте конфигурацию
docker compose exec nginx nginx -t

# Проверьте логи
docker compose logs nginx
```

### Consul не доступен

```bash
# Проверьте логи
docker compose logs consul

# Проверьте members
docker compose exec consul consul members
```

### API не отвечает

```bash
# Проверьте, запущен ли контейнер
docker compose ps pymongo_api

# Проверьте логи
docker compose logs pymongo_api
```

## Дополнительная настройка

### Регистрация сервисов в Consul

Для автоматической регистрации сервисов можно использовать Consul agent в каждом контейнере или использовать Registrator:

```yaml
registrator:
  image: gliderlabs/registrator
  command: -internal consul://consul:8500
  volumes:
    - /var/run/docker.sock:/tmp/docker.sock
  depends_on:
    - consul
```

### Добавление метрик

Можно добавить Prometheus и Grafana для мониторинга:
- Метрики Nginx
- Метрики MongoDB
- Метрики Redis
- Метрики Consul

## Следующие шаги

1. Добавить CDN (Задание 6)
2. Настроить автоматическую регистрацию сервисов в Consul
3. Добавить метрики и мониторинг
4. Настроить логирование в ELK stack
5. Добавить rate limiting в Nginx
6. Настроить SSL/TLS
