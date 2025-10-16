# Структура проекта по задачам

## 📁 Организация проекта

Все задания организованы в отдельные папки для удобства проверки:

```
architecture-pro-black_friday/
│
├── 📁 task1/                    ✅ Задание 1: Планирование (5 схем)
│   ├── schema1_sharding.drawio
│   ├── schema2_replication.drawio
│   ├── schema3_caching.drawio
│   ├── schema4_api_gateway.drawio
│   ├── schema5_final_with_cdn.drawio    ← ИТОГОВАЯ СХЕМА
│   ├── task1_template.drawio
│   └── README.md
│
├── 📁 task2/                    ✅ Задание 2: Шардирование MongoDB
│   ├── compose.yaml
│   ├── api_app/
│   ├── scripts/
│   └── README.md
│
├── 📁 task3/                    ✅ Задание 3: Репликация
│   ├── compose.yaml
│   ├── scripts/
│   └── README.md
│
├── 📁 task4/                    ✅ Задание 4: Кеширование Redis
│   ├── compose.yaml                      ← ОСНОВНАЯ ПАПКА ДЛЯ ПРОВЕРКИ
│   ├── scripts/
│   └── README.md
│
├── 📁 task5/                    ✅ Задание 5: API Gateway + Consul
│   ├── compose.yaml
│   ├── nginx.conf
│   ├── scripts/
│   └── README.md
│
├── 📁 task6/                    ✅ Задание 6: CDN
│   └── README.md                         (схема в task1/schema5)
│
├── 📁 tasks7-10/                ✅ Задания 7-10: Архитектурная документация
│   ├── ARCHITECTURAL_DOCUMENT.md         ← 58 KB документация
│   └── README.md
│
├── 📄 README.md                           Главная инструкция
├── 📄 SCHEMAS_INFO.md                     Описание схем
├── 📄 SUBMISSION_CHECKLIST.md             Чеклист готовности
└── 📄 PROJECT_STRUCTURE.md                Этот файл
```

---

## 🎯 Краткое описание каждой задачи

### Task 1: Планирование (Схемы)

**Содержит:** 5 схем эволюции архитектуры в формате draw.io

**Ключевые файлы:**
- `schema5_final_with_cdn.drawio` — итоговая схема для ревьюера

**Как проверить:**
1. Открыть в [draw.io](https://app.diagrams.net/)
2. Просмотреть эволюцию от schema1 до schema5

---

### Task 2: Шардирование

**Содержит:** Docker Compose конфигурация с базовым шардированием

**Компоненты:**
- 1 × mongos_router
- 1 × configSrv
- 2 × shards (shard1, shard2)
- 1 × pymongo-api

**Как запустить:**
```bash
cd task2
docker compose up -d
./scripts/init-cluster.sh
curl http://localhost:8080
```

---

### Task 3: Репликация

**Содержит:** Шардирование + репликация (3 реплики на каждый шард)

**Компоненты:**
- 1 × mongos_router
- 1 × configSrv (replica set)
- 6 × MongoDB (shard1: 3 реплики, shard2: 3 реплики)
- 1 × pymongo-api

**Как запустить:**
```bash
cd task3
docker compose up -d
./scripts/init-cluster.sh
curl http://localhost:8080
```

---

### Task 4: Кеширование ⭐ ОСНОВНАЯ ПАПКА ДЛЯ ПРОВЕРКИ

**Содержит:** Шардирование + Репликация + Redis кеширование

**Компоненты:**
- 1 × mongos_router
- 1 × configSrv (replica set)
- 6 × MongoDB (2 шарда × 3 реплики)
- 1 × redis
- 1 × pymongo-api

**Как запустить:**
```bash
cd task4
docker compose up -d
./scripts/init-cluster.sh
curl http://localhost:8080
```

**Проверка кеша:**
```bash
# Первый запрос (~200ms из MongoDB)
time curl http://localhost:8080/helloDoc/users

# Повторный запрос (<100ms из Redis)
time curl http://localhost:8080/helloDoc/users
```

**Ожидаемый результат:**
```json
{
  "total_documents": 1000,
  "sharding_enabled": true,
  "replicas": { "shard1": 3, "shard2": 3 },
  "cache_enabled": true
}
```

---

### Task 5: API Gateway + Consul

**Содержит:** Полная конфигурация с горизонтальным масштабированием

**Компоненты:**
- 1 × nginx (API Gateway)
- 1 × consul (Service Discovery)
- 3 × pymongo-api (масштабирование)
- 1 × mongos_router
- 1 × configSrv
- 6 × MongoDB
- 1 × redis

**Как запустить:**
```bash
cd task5
docker compose up -d
./scripts/init-cluster.sh
```

**Эндпоинты:**
- API через Nginx: http://localhost (порт 80)
- Consul UI: http://localhost:8500

---

### Task 6: CDN

**Содержит:** Теоретическое описание CDN

**Схема:** См. `task1/schema5_final_with_cdn.drawio`

**Компоненты на схеме:**
- 3 CDN ноды (Европа, Азия, США)
- Пользователи из разных регионов
- Статический контент

**Как проверить:**
1. Открыть `task1/schema5_final_with_cdn.drawio`
2. Прочитать `task6/README.md`

---

### Tasks 7-10: Архитектурная документация

**Содержит:** Единый документ на 58 KB с решениями заданий 7-10

**Файл:** `ARCHITECTURAL_DOCUMENT.md`

**Разделы:**

#### Задание 7: Схемы коллекций
- Коллекция orders: `{ user_id: "hashed" }`
- Коллекция products: `{ product_id: "hashed" }`
- Коллекция carts: `{ user_id: "hashed", status: 1 }`

#### Задание 8: Горячие шарды
- Метрики мониторинга
- Скрипты выявления дисбаланса
- Механизмы устранения (балансировка, resharding)

#### Задание 9: Read Preferences
- Таблицы операций для orders, products, carts
- Выбор primary/secondary для каждой операции
- Допустимые задержки репликации

#### Задание 10: Миграция на Cassandra
- Модели данных (partition keys, clustering keys)
- Стратегии репликации (Hinted Handoff, Read Repair)
- План миграции

**Как проверить:**
```bash
# Открыть в редакторе
code tasks7-10/ARCHITECTURAL_DOCUMENT.md

# Или прочитать описание
cat tasks7-10/README.md
```

---

## 📋 Быстрая проверка для ревьюера

### 1️⃣ Проверить схемы (Task 1)
```bash
cd task1
# Открыть schema5_final_with_cdn.drawio в draw.io
```

### 2️⃣ Запустить реализацию (Task 4)
```bash
cd task4
docker compose up -d
./scripts/init-cluster.sh
curl http://localhost:8080
```

### 3️⃣ Проверить кеширование
```bash
curl http://localhost:8080/helloDoc/users  # Первый запрос (~200ms)
curl http://localhost:8080/helloDoc/users  # Повторный (<100ms)
```

### 4️⃣ Прочитать документацию (Tasks 7-10)
```bash
cat tasks7-10/README.md
# Или открыть tasks7-10/ARCHITECTURAL_DOCUMENT.md
```

---

---

## ✅ Чеклист выполнения

- [x] Task 1: 5 схем созданы в папке task1/
- [x] Task 2: Шардирование реализовано в task2/
- [x] Task 3: Репликация реализована в task3/
- [x] Task 4: Кеширование реализовано в task4/ ← **ДЛЯ ПРОВЕРКИ**
- [x] Task 5: API Gateway + Consul в task5/
- [x] Task 6: CDN описан в task6/README.md
- [x] Tasks 7-10: Документация в tasks7-10/ARCHITECTURAL_DOCUMENT.md

---

## 📞 Навигация по документации

| Файл | Описание |
|------|----------|
| `README.md` | Главная инструкция с командами запуска |
| `PROJECT_STRUCTURE.md` | Этот файл — структура проекта |
| `SCHEMAS_INFO.md` | Детальное описание схем |
| `SUBMISSION_CHECKLIST.md` | Чеклист готовности к отправке |
| `task1/README.md` | Описание схем архитектуры |
| `task4/README.md` | Инструкции по запуску основной реализации |
| `task6/README.md` | Описание CDN |
| `tasks7-10/README.md` | Описание архитектурной документации |

---

**Все задания 1-10 выполнены и организованы по папкам!** 🎉

Дата создания: 16 октября 2025
