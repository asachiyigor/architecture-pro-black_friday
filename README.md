# Проектная работа: Онлайн-магазин "Мобильный мир"

Проект демонстрирует эволюцию архитектуры от простого MongoDB инстанса до полноценного высоконагруженного кластера с шардированием, репликацией, кешированием, API Gateway и CDN.

---

## 🎯 Выполненные задания

### Задания 1-6: Реализация и схемы

- ✅ **Задание 1:** 5 схем эволюции архитектуры (`.drawio`)
- ✅ **Задание 2:** MongoDB с шардированием (2 шарда)
- ✅ **Задание 3:** Репликация (3 реплики на шард)
- ✅ **Задание 4:** Redis кеширование
- ✅ **Задание 5:** API Gateway (Nginx) + Service Discovery (Consul)
- ✅ **Задание 6:** CDN в разных регионах

### Задания 7-10: Архитектурная документация

- ✅ **Задание 7:** Проектирование схем коллекций (orders, products, carts)
- ✅ **Задание 8:** Выявление и устранение горячих шардов
- ✅ **Задание 9:** Настройка чтения с реплик и консистентность
- ✅ **Задание 10:** Миграция на Cassandra

📄 **Документация:** `ARCHITECTURAL_DOCUMENT.md` (58 KB)

---

## 🚀 Как запустить (Задание 4: Кеширование)

### Требования

- Docker Desktop (минимум 2 CPU, 4 GB RAM)
- Git Bash (для Windows) или bash (для Linux/Mac)

### Шаг 1: Запуск контейнеров

```bash
cd task4
docker compose up -d
```

### Шаг 2: Инициализация кластера

Выполните скрипт инициализации:

```bash
./scripts/init-cluster.sh
```

Скрипт автоматически:
1. Настроит Config Server Replica Set
2. Настроит Replica Sets для каждого шарда
3. Добавит шарды в кластер
4. Включит шардирование для базы данных
5. Создаст шардированную коллекцию
6. Заполнит данными (1000+ документов)

### Шаг 3: Проверка

Откройте в браузере: http://localhost:8080

Ожидаемый вывод (JSON):
```json
{
  "message": "Hello from pymongo-api",
  "database": "somedb",
  "collection": "helloDoc",
  "total_documents": 1000,
  "sharding_enabled": true,
  "shards": {
    "shard1": 492,
    "shard2": 508
  },
  "replicas": {
    "shard1": 3,
    "shard2": 3
  },
  "cache_enabled": true,
  "redis_url": "redis://redis:6379"
}
```

### Шаг 4: Проверка кеширования

```bash
# Первый запрос (из MongoDB, медленно ~200ms)
curl http://localhost:8080/helloDoc/users

# Повторный запрос (из Redis кеша, быстро <100ms)
curl http://localhost:8080/helloDoc/users
```

---

## 🔍 Проверка компонентов

### MongoDB: Проверка шардирования

```bash
docker compose exec -T mongos_router mongosh --quiet <<EOF
sh.status()
EOF
```

### MongoDB: Проверка репликации

```bash
docker compose exec -T shard1-1 mongosh --port 27018 --quiet <<EOF
rs.status()
EOF
```

### Redis: Проверка кеша

```bash
docker compose exec redis redis-cli KEYS "*"
docker compose exec redis redis-cli GET "helloDoc:users"
```

### Статус всех контейнеров

```bash
docker compose ps
```

Должно быть запущено:
- 1 × mongos_router
- 1 × configSrv
- 6 × MongoDB (shard1-1, shard1-2, shard1-3, shard2-1, shard2-2, shard2-3)
- 1 × redis
- 1 × pymongo-api

**Итого: 10 контейнеров**

---

## 🏗️ Альтернатива: Полная конфигурация (Задание 5)

Если нужно проверить полную конфигурацию с Nginx и Consul:

```bash
cd task5
docker compose up -d
./scripts/init-cluster.sh
```

Доступные эндпоинты:
- **API через Nginx:** http://localhost (порт 80)
- **Consul UI:** http://localhost:8500
- **API напрямую:** http://localhost:8080, 8081, 8082 (3 инстанса)

---

## 📊 Архитектурные схемы

### Как открыть схемы

**Вариант 1: Просмотр PNG (рекомендуется для ревьюера)**

PNG изображения автоматически генерируются через GitHub Actions:
- `task1/schema1_sharding.png`
- `task1/schema2_replication.png`
- `task1/schema3_caching.png`
- `task1/schema4_api_gateway.png`
- `task1/schema5_final_with_cdn.png`

**Вариант 2: Редактирование в draw.io**

1. Установите [draw.io Desktop](https://github.com/jgraph/drawio-desktop/releases)
   или используйте [https://app.diagrams.net/](https://app.diagrams.net/)
2. Откройте файлы `.drawio` в папке `task1/`

### Итоговая схема для ревьюера

📄 **Файл:** `task1/schema5_final_with_cdn.drawio`

**Компоненты:**
- 3 CDN ноды (Европа, Азия, США)
- 1 API Gateway (Nginx)
- 1 Service Discovery (Consul)
- 3 API инстанса (pymongo-api)
- 1 Redis (кеш)
- 1 Mongos Router
- 1 Config Server
- 6 MongoDB нод (2 шарда × 3 реплики)

---

## 📖 Архитектурная документация

### Файл: `tasks7-10/ARCHITECTURAL_DOCUMENT.md`

**Содержание:**

1. **Задание 7:** Проектирование схем коллекций
   - Схемы для `orders`, `products`, `carts`
   - Выбор shard-ключей (hashed vs range)
   - Команды MongoDB для создания

2. **Задание 8:** Выявление горячих шардов
   - Метрики мониторинга (CPU, ops/sec, data imbalance)
   - Скрипты для автоматического обнаружения
   - Механизмы устранения (балансировка, refine key, resharding)

3. **Задание 9:** Чтение с реплик
   - Таблица операций с выбором Read Preference
   - Допустимые задержки репликации
   - Примеры кода (PyMongo)

4. **Задание 10:** Миграция на Cassandra
   - Обоснование выбора данных для миграции
   - Модели данных (partition keys, clustering keys)
   - Стратегии репликации (Hinted Handoff, Read Repair, Anti-Entropy)
   - План миграции (Dual-Write, Backfill, Switchover)

---

## 🛠️ Полезные команды

### Остановка проекта

```bash
docker compose down
```

### Полная очистка (включая volumes)

```bash
docker compose down -v
```

### Просмотр логов

```bash
docker compose logs -f pymongo-api
docker compose logs -f mongos_router
docker compose logs -f redis
```

### Мониторинг ресурсов

```bash
docker stats
```

---

1. **Основная директория для проверки:** `task4/`
   - Включает задания 2, 3, 4
   - Шардирование + Репликация + Redis кеширование

2. **Альтернатива:** `task5/`
   - Включает задания 2, 3, 4, 5
   - + Nginx API Gateway + Consul

3. **Схемы:** Все 5 схем в папке `task1/`
   - Итоговая схема: `task1/schema5_final_with_cdn.drawio`

4. **Документация:** `tasks7-10/ARCHITECTURAL_DOCUMENT.md`
   - Задания 7-10 полностью описаны

---

## 🎓 Технологии

- **MongoDB 7.0** — ShardedCluster с Replica Sets
- **Redis 7.0** — Кеширование с AOF persistence
- **Nginx** — API Gateway и балансировка нагрузки
- **Consul** — Service Discovery
- **Python 3.11** — pymongo-api (FastAPI)
- **Docker Compose** — Оркестрация контейнеров

---

## 📧 Контакты

Если возникли вопросы, проверьте:
- `SCHEMAS_INFO.md` — описание схем и директорий
- `tasks7-10/ARCHITECTURAL_DOCUMENT.md` — полная документация
- `task4/README.md` — детальные инструкции по запуску

---