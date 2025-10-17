# MongoDB Sharding Setup

Проект для демонстрации шардирования MongoDB с использованием Docker Compose.

## Архитектура

- **Config Server** (configSrv) - хранит метаданные о шардах и их конфигурации
- **Mongos Router** (mongos_router) - маршрутизатор запросов между шардами
- **Shard 1** (shard1) - первый шард для хранения данных
- **Shard 2** (shard2) - второй шард для хранения данных
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

### 3. Инициализируйте Config Server

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

### 4. Инициализируйте Shard 1

```bash
docker compose exec -T shard1 mongosh --port 27018 --quiet <<EOF
rs.initiate({
  _id: "shard1",
  members: [
    { _id: 0, host: "shard1:27018" }
  ]
});
EOF
```

### 5. Инициализируйте Shard 2

```bash
docker compose exec -T shard2 mongosh --port 27019 --quiet <<EOF
rs.initiate({
  _id: "shard2",
  members: [
    { _id: 0, host: "shard2:27019" }
  ]
});
EOF
```

### 6. Подождите несколько секунд

Дайте время для инициализации реплик (10-15 секунд).

```bash
sleep 15
```

### 7. Добавьте шарды в кластер

```bash
docker compose exec -T mongos_router mongosh --port 27020 --quiet <<EOF
sh.addShard("shard1/shard1:27018");
sh.addShard("shard2/shard2:27019");
EOF
```

### 8. Включите шардирование для базы данных

```bash
docker compose exec -T mongos_router mongosh --port 27020 --quiet <<EOF
sh.enableSharding("somedb");
EOF
```

### 9. Создайте шардированную коллекцию

```bash
docker compose exec -T mongos_router mongosh --port 27020 --quiet <<EOF
sh.shardCollection("somedb.helloDoc", { "name": "hashed" });
EOF
```

### 10. Заполните базу данными

```bash
docker compose exec -T mongos_router mongosh --port 27020 --quiet <<EOF
use somedb
for(var i = 0; i < 1000; i++) {
  db.helloDoc.insertOne({age: i, name: "ly" + i});
}
EOF
```

## Автоматизированная инициализация

Для упрощения процесса можно использовать скрипт:

```bash
./scripts/mongo-init-sharding.sh
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
docker compose exec -T shard1 mongosh --port 27018 --quiet <<EOF
use somedb
db.helloDoc.countDocuments()
EOF
```

**Shard 2:**
```bash
docker compose exec -T shard2 mongosh --port 27019 --quiet <<EOF
use somedb
db.helloDoc.countDocuments()
EOF
```

Сумма документов в обоих шардах должна равняться 1000.

### Проверка через API

Откройте в браузере: http://localhost:8080

Вы должны увидеть JSON с информацией о MongoDB:
- Количество документов в коллекции helloDoc (≥1000)
- Информация о шардах

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
- Минимум 2 CPU и 4 GB RAM

## Порты

- **8080** - API приложение
- **27017** - Config Server
- **27018** - Shard 1
- **27019** - Shard 2
- **27020** - Mongos Router