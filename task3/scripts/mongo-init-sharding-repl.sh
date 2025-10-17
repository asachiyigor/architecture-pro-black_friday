#!/bin/bash

echo "=== Инициализация MongoDB Sharding с репликацией ==="
echo ""

echo "Шаг 1: Инициализация Config Server..."
docker compose exec -T configSrv mongosh --port 27017 --quiet <<EOF
rs.initiate({
  _id: "config_server",
  configsvr: true,
  members: [
    { _id: 0, host: "configSrv:27017" }
  ]
});
EOF
echo "✓ Config Server инициализирован"
echo ""

echo "Шаг 2: Инициализация Shard 1 с 3 репликами..."
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
echo "✓ Shard 1 инициализирован с 3 репликами"
echo ""

echo "Шаг 3: Инициализация Shard 2 с 3 репликами..."
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
echo "✓ Shard 2 инициализирован с 3 репликами"
echo ""

echo "Шаг 4: Ожидание выбора PRIMARY в replica sets (20 секунд)..."
sleep 20
echo "✓ Ожидание завершено"
echo ""

echo "Шаг 5: Добавление шардов в кластер..."
docker compose exec -T mongos_router mongosh --port 27020 --quiet <<EOF
sh.addShard("shard1/shard1-1:27018,shard1-2:27021,shard1-3:27022");
sh.addShard("shard2/shard2-1:27019,shard2-2:27023,shard2-3:27024");
EOF
echo "✓ Шарды добавлены в кластер"
echo ""

echo "Шаг 6: Включение шардирования для базы данных..."
docker compose exec -T mongos_router mongosh --port 27020 --quiet <<EOF
sh.enableSharding("somedb");
EOF
echo "✓ Шардирование включено для somedb"
echo ""

echo "Шаг 7: Создание шардированной коллекции..."
docker compose exec -T mongos_router mongosh --port 27020 --quiet <<EOF
sh.shardCollection("somedb.helloDoc", { "name": "hashed" });
EOF
echo "✓ Коллекция helloDoc создана с hashed шардированием"
echo ""

echo "Шаг 8: Заполнение базы данными..."
docker compose exec -T mongos_router mongosh --port 27020 --quiet <<EOF
use somedb
for(var i = 0; i < 1000; i++) {
  db.helloDoc.insertOne({age: i, name: "ly" + i});
}
EOF
echo "✓ Вставлено 1000 документов"
echo ""

echo "=== Проверка распределения данных ==="
echo "Общее количество документов:"
docker compose exec -T mongos_router mongosh --port 27020 --quiet <<EOF
use somedb
db.helloDoc.countDocuments()
EOF

echo ""
echo "Документов в Shard 1 (проверка на PRIMARY):"
docker compose exec -T shard1-1 mongosh --port 27018 --quiet <<EOF
use somedb
db.helloDoc.countDocuments()
EOF

echo ""
echo "Документов в Shard 2 (проверка на PRIMARY):"
docker compose exec -T shard2-1 mongosh --port 27019 --quiet <<EOF
use somedb
db.helloDoc.countDocuments()
EOF

echo ""
echo "=== Проверка статуса replica sets ==="
echo ""
echo "Shard 1 Replica Set Status:"
docker compose exec -T shard1-1 mongosh --port 27018 --quiet <<EOF
rs.status().members.forEach(function(member) {
  print(member.name + " - " + member.stateStr);
});
EOF

echo ""
echo "Shard 2 Replica Set Status:"
docker compose exec -T shard2-1 mongosh --port 27019 --quiet <<EOF
rs.status().members.forEach(function(member) {
  print(member.name + " - " + member.stateStr);
});
EOF

echo ""
echo "=== Инициализация завершена! ==="
echo "API доступен на http://localhost:8080"
echo ""
echo "Порты:"
echo "  - 27017: Config Server"
echo "  - 27018: Shard 1 - Replica 1"
echo "  - 27021: Shard 1 - Replica 2"
echo "  - 27022: Shard 1 - Replica 3"
echo "  - 27019: Shard 2 - Replica 1"
echo "  - 27023: Shard 2 - Replica 2"
echo "  - 27024: Shard 2 - Replica 3"
echo "  - 27020: Mongos Router"
echo "  - 8080:  API Application"
