# MongoDB Sharding с Репликацией и Redis Кешированием

Проект для демонстрации шардирования MongoDB с репликацией и Redis кешированием с использованием Docker Compose.

## Архитектура

- **Config Server** (configSrv) - хранит метаданные о шардах и их конфигурации
- **Mongos Router** (mongos_router) - маршрутизатор запросов между шардами
- **Shard 1** - первый шард с 3 репликами:
  - shard1-1 (PRIMARY) - порт 27018
  - shard1-2 (SECONDARY) - порт 27021
  - shard1-3 (SECONDARY) - порт 27022
- **Shard 2** - второй шард с 3 репликами:
  - shard2-1 (PRIMARY) - порт 27019
  - shard2-2 (SECONDARY) - порт 27023
  - shard2-3 (SECONDARY) - порт 27024
- **Redis Cache** (redis) - кеширование запросов к MongoDB
- **API Application** (pymongo_api) - приложение для работы с MongoDB и Redis

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

Все 10 сервисов должны быть в статусе "running".

### 3. Автоматическая инициализация

Используйте скрипт для автоматической настройки:

```bash
./scripts/mongo-init-sharding-repl-cache.sh
```

Скрипт выполнит:
1. Инициализацию Config Server
2. Инициализацию Shard 1 с 3 репликами
3. Инициализацию Shard 2 с 3 репликами
4. Добавление шардов в кластер
5. Включение шардирования
6. Создание шардированной коллекции
7. Заполнение базы тестовыми данными
8. Проверку распределения данных
9. Проверку статуса replica sets

## Проверка работы

### Проверка через API

Откройте в браузере: http://localhost:8080

Вы должны увидеть JSON с информацией:
- `cache_enabled: true` - кеширование включено
- Количество документов в коллекции helloDoc (≥1000)
- Информация о шардах с репликами
- Статус Redis

### Проверка кеширования

Выполните несколько запросов подряд и сравните время ответа:

```bash
# Первый запрос (без кеша)
time curl http://localhost:8080

# Второй запрос (с кешем) - должен быть быстрее
time curl http://localhost:8080
```

### Проверка Redis

Подключитесь к Redis и посмотрите кешированные данные:

```bash
docker compose exec redis redis-cli
> KEYS *
> GET <key_name>
```

### Очистка кеша

```bash
docker compose exec redis redis-cli FLUSHALL
```

## Тестирование отказоустойчивости

### Тест 1: Остановка Redis

```bash
docker compose stop redis
```

Проверьте, что API продолжает работать (без кеша):
```bash
curl http://localhost:8080
```

Запустите Redis обратно:
```bash
docker compose start redis
```

### Тест 2: Остановка реплики MongoDB

```bash
docker compose stop shard1-2
```

Проверьте, что система продолжает работать:
```bash
curl http://localhost:8080
```

Запустите реплику обратно:
```bash
docker compose start shard1-2
```

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
- Минимум 4 CPU и 8 GB RAM

## Порты

- **8080** - API приложение
- **6379** - Redis Cache
- **27017** - Config Server
- **27018** - Shard 1 - Replica 1 (PRIMARY)
- **27021** - Shard 1 - Replica 2 (SECONDARY)
- **27022** - Shard 1 - Replica 3 (SECONDARY)
- **27019** - Shard 2 - Replica 1 (PRIMARY)
- **27023** - Shard 2 - Replica 2 (SECONDARY)
- **27024** - Shard 2 - Replica 3 (SECONDARY)
- **27020** - Mongos Router

## Преимущества этой конфигурации

1. **Высокая доступность**: Каждый шард имеет 3 реплики
2. **Автоматический failover**: При отказе PRIMARY выбирается новый PRIMARY
3. **Кеширование**: Redis ускоряет повторяющиеся запросы
4. **Горизонтальное масштабирование**: Данные распределены между 2 шардами
5. **Персистентность кеша**: Redis настроен с AOF (Append Only File)

## Особенности конфигурации

### MongoDB
- **Стратегия шардирования**: Hashed на поле "name"
- **Replica Set**: 3 реплики на каждый шард (1 PRIMARY + 2 SECONDARY)
- **Write Concern**: Majority (большинство реплик)
- **Read Preference**: Primary

### Redis
- **Режим**: Standalone с AOF persistence
- **Порт**: 6379
- **Персистентность**: Append Only File для надежности данных
- **Использование**: Кеширование результатов запросов к MongoDB

## Как работает кеширование

1. API получает запрос
2. Проверяет наличие данных в Redis
3. Если данные есть в кеше - возвращает их (быстро)
4. Если данных нет - запрашивает из MongoDB
5. Сохраняет результат в Redis для будущих запросов
6. Возвращает данные клиенту

## Мониторинг

### Проверка статуса Redis

```bash
docker compose exec redis redis-cli INFO stats
```

### Проверка использования памяти Redis

```bash
docker compose exec redis redis-cli INFO memory
```

### Проверка статуса MongoDB Replica Sets

```bash
# Shard 1
docker compose exec shard1-1 mongosh --port 27018 --quiet --eval "rs.status()"

# Shard 2
docker compose exec shard2-1 mongosh --port 27019 --quiet --eval "rs.status()"
```

## Troubleshooting

### Redis не подключается

```bash
# Проверьте логи Redis
docker compose logs redis

# Проверьте доступность
docker compose exec redis redis-cli ping
```

### Кеш не работает

```bash
# Проверьте переменные окружения API
docker compose exec pymongo_api env | grep REDIS
```

### MongoDB реплика не синхронизируется

```bash
# Проверьте статус репликации
docker compose exec shard1-1 mongosh --port 27018 --quiet --eval "rs.printReplicationInfo()"
```
