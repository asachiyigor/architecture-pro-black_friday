# MongoDB Sharding Setup с Репликацией

Проект для демонстрации шардирования MongoDB с репликацией для каждого шарда с использованием Docker Compose.

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
- **API Application** (pymongo_api) - приложение для работы с MongoDB

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

Все сервисы должны быть в статусе "running".

### 3. Автоматическая инициализация

Используйте скрипт для автоматической настройки:

```bash
./scripts/mongo-init-sharding-repl.sh
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

## Ручная инициализация (опционально)

Если вы хотите выполнить настройку вручную, следуйте инструкциям ниже.

### 1. Инициализация Config Server

```bash
docker compose exec -T configSrv mongosh --port 27017 --quiet <<EOF
rs.initiate({
  _id: "config_server",
  configsvr: true,
  members: [
    { _id: 0, host: "configSrv:27017" }
  ]
});
EOF
```

### 2. Инициализация Shard 1 с репликами

```bash
docker compose exec -T shard1-1 mongosh --port 27018 --quiet <<EOF
rs.initiate({
  _id: "shard1",
  members: [
    { _id: 0, host: "shard1-1:27018" },
    { _id: 1, host: "shard1-2:27021" },
    { _id: 2, host: "shard1-3:27022" }
  ]
});
EOF
```

### 3. Инициализация Shard 2 с репликами

```bash
docker compose exec -T shard2-1 mongosh --port 27019 --quiet <<EOF
rs.initiate({
  _id: "shard2",
  members: [
    { _id: 0, host: "shard2-1:27019" },
    { _id: 1, host: "shard2-2:27023" },
    { _id: 2, host: "shard2-3:27024" }
  ]
});
EOF
```

### 4. Подождите для выбора PRIMARY

```bash
sleep 20
```

### 5. Добавьте шарды в кластер

```bash
docker compose exec -T mongos_router mongosh --port 27020 --quiet <<EOF
sh.addShard("shard1/shard1-1:27018,shard1-2:27021,shard1-3:27022");
sh.addShard("shard2/shard2-1:27019,shard2-2:27023,shard2-3:27024");
EOF
```

### 6. Включите шардирование для базы данных

```bash
docker compose exec -T mongos_router mongosh --port 27020 --quiet <<EOF
sh.enableSharding("somedb");
EOF
```

### 7. Создайте шардированную коллекцию

```bash
docker compose exec -T mongos_router mongosh --port 27020 --quiet <<EOF
sh.shardCollection("somedb.helloDoc", { "name": "hashed" });
EOF
```

### 8. Заполните базу данными

```bash
docker compose exec -T mongos_router mongosh --port 27020 --quiet <<EOF
use somedb
for(var i = 0; i < 1000; i++) {
  db.helloDoc.insertOne({age: i, name: "ly" + i});
}
EOF
```

## Проверка работы

### Проверка общего количества документов

```bash
docker compose exec -T mongos_router mongosh --port 27020 --quiet <<EOF
use somedb
db.helloDoc.countDocuments()
EOF
```

Должно вывести: **1000**

### Проверка распределения по шардам

**Shard 1:**
```bash
docker compose exec -T shard1-1 mongosh --port 27018 --quiet <<EOF
use somedb
db.helloDoc.countDocuments()
EOF
```

**Shard 2:**
```bash
docker compose exec -T shard2-1 mongosh --port 27019 --quiet <<EOF
use somedb
db.helloDoc.countDocuments()
EOF
```

Сумма документов в обоих шардах должна равняться 1000.

### Проверка статуса Replica Set

**Shard 1:**
```bash
docker compose exec -T shard1-1 mongosh --port 27018 --quiet <<EOF
rs.status()
EOF
```

**Shard 2:**
```bash
docker compose exec -T shard2-1 mongosh --port 27019 --quiet <<EOF
rs.status()
EOF
```

### Проверка через API

Откройте в браузере: http://localhost:8080

Вы должны увидеть JSON с информацией о MongoDB:
- Количество документов в коллекции helloDoc (≥1000)
- Информация о шардах
- Информация о replica sets

## Тестирование отказоустойчивости

### Остановка одной реплики

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
- **27017** - Config Server
- **27018** - Shard 1 - Replica 1 (PRIMARY)
- **27021** - Shard 1 - Replica 2 (SECONDARY)
- **27022** - Shard 1 - Replica 3 (SECONDARY)
- **27019** - Shard 2 - Replica 1 (PRIMARY)
- **27023** - Shard 2 - Replica 2 (SECONDARY)
- **27024** - Shard 2 - Replica 3 (SECONDARY)
- **27020** - Mongos Router

## Преимущества этой конфигурации

1. **Высокая доступность**: Каждый шард имеет 3 реплики, система продолжит работу даже при отказе 1 реплики
2. **Автоматический failover**: При отказе PRIMARY MongoDB автоматически выберет новый PRIMARY
3. **Балансировка нагрузки**: Чтения могут выполняться с SECONDARY репликами
4. **Горизонтальное масштабирование**: Данные распределены между 2 шардами

## Особенности конфигурации

- **Стратегия шардирования**: Hashed на поле "name" для равномерного распределения
- **Replica Set**: По 3 реплики на каждый шард (1 PRIMARY + 2 SECONDARY)
- **Write Concern**: По умолчанию MongoDB будет ждать подтверждения записи от большинства (majority)
- **Read Preference**: По умолчанию чтение с PRIMARY, можно настроить чтение с SECONDARY
