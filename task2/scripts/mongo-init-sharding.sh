#!/bin/bash

echo "=== Инициализация MongoDB Sharding ==="

echo "Шаг 1: Инициализация Config Server..."
docker compose exec -T configSrv mongosh --port 27017 --quiet <<MONGO
rs.initiate({
  _id: "config_server",
  configsvr: true,
  members: [
    { _id: 0, host: "configSrv:27017" }
  ]
});
MONGO

echo "Шаг 2: Инициализация Shard 1..."
docker compose exec -T shard1 mongosh --port 27018 --quiet <<MONGO
rs.initiate({
  _id: "shard1",
  members: [
    { _id: 0, host: "shard1:27018" }
  ]
});
MONGO

echo "Шаг 3: Инициализация Shard 2..."
docker compose exec -T shard2 mongosh --port 27019 --quiet <<MONGO
rs.initiate({
  _id: "shard2",
  members: [
    { _id: 0, host: "shard2:27019" }
  ]
});
MONGO

echo "Ожидание инициализации реплик (15 секунд)..."
sleep 15

echo "Шаг 4: Добавление шардов в кластер..."
docker compose exec -T mongos_router mongosh --port 27020 --quiet <<MONGO
sh.addShard("shard1/shard1:27018");
sh.addShard("shard2/shard2:27019");
MONGO

echo "Шаг 5: Включение шардирования для базы данных..."
docker compose exec -T mongos_router mongosh --port 27020 --quiet <<MONGO
sh.enableSharding("somedb");
MONGO

echo "Шаг 6: Создание шардированной коллекции..."
docker compose exec -T mongos_router mongosh --port 27020 --quiet <<MONGO
sh.shardCollection("somedb.helloDoc", { "name": "hashed" });
MONGO

echo "Шаг 7: Заполнение базы данными..."
docker compose exec -T mongos_router mongosh --port 27020 --quiet <<MONGO
use somedb
for(var i = 0; i < 1000; i++) {
  db.helloDoc.insertOne({age: i, name: "ly" + i});
}
MONGO

echo ""
echo "=== Проверка распределения данных ==="

echo "Общее количество документов:"
docker compose exec -T mongos_router mongosh --port 27020 --quiet <<MONGO
use somedb
db.helloDoc.countDocuments()
MONGO

echo "Документов в Shard 1:"
docker compose exec -T shard1 mongosh --port 27018 --quiet <<MONGO
use somedb
db.helloDoc.countDocuments()
MONGO

echo "Документов в Shard 2:"
docker compose exec -T shard2 mongosh --port 27019 --quiet <<MONGO
use somedb
db.helloDoc.countDocuments()
MONGO

echo ""
echo "=== Инициализация завершена! ==="
echo "API доступен на http://localhost:8080"
