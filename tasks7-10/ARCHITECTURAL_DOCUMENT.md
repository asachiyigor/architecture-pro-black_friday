# Архитектурный документ: Задания 7-10

**Проект:** Онлайн-магазин "Мобильный мир"
**Дата:** 16 октября 2025
**Автор:** Архитектурное решение для масштабирования MongoDB и миграции на Cassandra

---

## Оглавление

1. [Задание 7: Проектирование схем коллекций для шардирования](#задание-7-проектирование-схем-коллекций-для-шардирования)
2. [Задание 8: Выявление и устранение горячих шардов](#задание-8-выявление-и-устранение-горячих-шардов)
3. [Задание 9: Настройка чтения с реплик и консистентность](#задание-9-настройка-чтения-с-реплик-и-консистентность)
4. [Задание 10: Миграция на Cassandra](#задание-10-миграция-на-cassandra)

---

## Задание 7: Проектирование схем коллекций для шардирования

### 7.1. Коллекция `orders` (Заказы)

#### Схема коллекции

```javascript
{
  _id: ObjectId,                    // Уникальный идентификатор заказа
  order_id: String,                 // Человекочитаемый ID заказа (ORD-2025-001234)
  user_id: String,                  // Идентификатор клиента
  created_at: ISODate,              // Дата и время оформления заказа
  items: [                          // Список заказанных товаров
    {
      product_id: String,
      product_name: String,
      quantity: Number,
      price: Decimal128
    }
  ],
  status: String,                   // "pending", "processing", "shipped", "delivered", "cancelled"
  total_amount: Decimal128,         // Общая сумма заказа
  geozone: String                   // Геозона заказа: "moscow", "spb", "ekb", "kgd", etc.
}
```

#### Выбор shard-ключа: `{ user_id: "hashed" }`

**Обоснование:**

1. **Равномерное распределение:** Использование хешированного ключа по `user_id` обеспечивает равномерное распределение заказов между шардами, так как хеш-функция случайным образом распределяет данные.

2. **Высокая кардинальность:** Количество уникальных пользователей велико, что создает достаточное количество различных значений для равномерного распределения.

3. **Соответствие паттернам доступа:** Основные операции включают:
   - Поиск истории заказов конкретного пользователя → эффективен при шардировании по `user_id`
   - Создание нового заказа → распределяется равномерно
   - Отображение статуса заказа → требует указания `user_id`

**Альтернативные варианты (НЕ выбраны):**

- `{ geozone: 1 }` (range-based) — риск создания горячих шардов в популярных геозонах (Москва, СПб)
- `{ created_at: 1 }` — все новые заказы попадают в один шард (монотонно возрастающий ключ)
- `{ order_id: 1 }` — если генерируется последовательно, создаст горячий шард

#### Команда для создания шардирования

```javascript
// 1. Включить шардирование для базы данных
sh.enableSharding("somedb")

// 2. Создать хешированный индекс
db.orders.createIndex({ user_id: "hashed" })

// 3. Включить шардирование коллекции
sh.shardCollection("somedb.orders", { user_id: "hashed" })

// 4. Проверить распределение
db.orders.getShardDistribution()
```

---

### 7.2. Коллекция `products` (Товары)

#### Схема коллекции

```javascript
{
  _id: ObjectId,                    // Уникальный идентификатор товара
  product_id: String,               // SKU или артикул (SMPH-X-BLK-128)
  name: String,                     // Наименование товара
  category: String,                 // "electronics", "audio", "accessories", etc.
  price: Decimal128,                // Цена товара
  stock: [                          // Остатки товара в каждой геозоне
    {
      geozone: String,              // "moscow", "spb", "ekb", etc.
      quantity: Number              // Количество в наличии
    }
  ],
  attributes: {                     // Дополнительные атрибуты
    color: String,
    size: String,
    brand: String,
    model: String
  },
  created_at: ISODate,
  updated_at: ISODate
}
```

#### Выбор shard-ключа: `{ product_id: "hashed" }`

**Обоснование:**

1. **Равномерное распределение:** Хеширование `product_id` обеспечивает случайное распределение товаров между шардами.

2. **Паттерны доступа:**
   - Частые обновления остатков при покупках → требуют прямого доступа по `product_id`
   - Описание товара на странице продукта → доступ по `product_id`
   - Поиск по категориям → scatter-gather запрос (неизбежен при любом ключе)

3. **Избежание горячих шардов:** Популярные категории (например, "electronics") не создадут перегрузку отдельного шарда.

**Важно:** Для эффективного поиска по категориям необходимо создать дополнительный индекс:

```javascript
db.products.createIndex({ category: 1, price: 1 })
```

**Альтернативные варианты:**

- `{ category: 1, product_id: 1 }` (compound range) — риск горячих шардов в популярных категориях (70% запросов на "electronics")
- `{ category: "hashed" }` — низкая кардинальность (мало категорий)

#### Команда для создания шардирования

```javascript
// 1. Создать хешированный индекс
db.products.createIndex({ product_id: "hashed" })

// 2. Создать индекс для поиска по категориям
db.products.createIndex({ category: 1, price: 1 })

// 3. Включить шардирование коллекции
sh.shardCollection("somedb.products", { product_id: "hashed" })

// 4. Проверить распределение
db.products.getShardDistribution()
```

---

### 7.3. Коллекция `carts` (Корзины)

#### Схема коллекции

```javascript
{
  _id: ObjectId,                    // Уникальный идентификатор корзины
  user_id: String,                  // Идентификатор пользователя (null для гостей)
  session_id: String,               // ID сессии для гостевых корзин
  items: [                          // Список товаров в корзине
    {
      product_id: String,
      quantity: Number
    }
  ],
  status: String,                   // "active", "ordered", "abandoned"
  created_at: ISODate,              // Дата и время создания
  updated_at: ISODate,              // Дата последнего обновления
  expires_at: ISODate               // TTL для автоматической очистки
}
```

#### Выбор shard-ключа: `{ _id: "hashed" }`

**Обоснование:**

1. **Уникальность доступа:** Корзины всегда доступны либо по `user_id + status`, либо по `session_id + status`. Использование `_id` как shard-ключа обеспечивает равномерное распределение.

2. **Паттерны доступа:**
   - Получение активной корзины пользователя: `{ user_id: "...", status: "active" }`
   - Получение гостевой корзины: `{ session_id: "...", status: "active" }`
   - Обновление корзины → требует составной индекс

3. **TTL Index:** Для автоматического удаления старых корзин:
   ```javascript
   db.carts.createIndex({ expires_at: 1 }, { expireAfterSeconds: 0 })
   ```

**Проблема:** Scatter-gather запросы при поиске по `user_id` или `session_id`.

**Решение:** Использовать compound shard key с префиксом для локализации запросов:

#### Улучшенный выбор: `{ user_id: "hashed", status: 1 }`

```javascript
// Альтернативная схема с compound key
sh.shardCollection("somedb.carts", { user_id: "hashed", status: 1 })
```

Этот вариант обеспечивает:
- Равномерное распределение по `user_id`
- Локализацию запросов активных корзин на один шард
- Эффективное слияние гостевых и пользовательских корзин

**Для гостевых корзин:** Использовать виртуальный `user_id` на основе `session_id`:
```javascript
user_id = "guest_" + session_id
```

#### Команды для создания шардирования

```javascript
// Вариант 1: Простой хешированный ключ
db.carts.createIndex({ _id: "hashed" })
db.carts.createIndex({ user_id: 1, status: 1 })
db.carts.createIndex({ session_id: 1, status: 1 })
db.carts.createIndex({ expires_at: 1 }, { expireAfterSeconds: 0 })
sh.shardCollection("somedb.carts", { _id: "hashed" })

// Вариант 2: Compound key (РЕКОМЕНДУЕТСЯ)
db.carts.createIndex({ user_id: "hashed", status: 1 })
db.carts.createIndex({ expires_at: 1 }, { expireAfterSeconds: 0 })
sh.shardCollection("somedb.carts", { user_id: "hashed", status: 1 })
```

---

### 7.4. Сводная таблица выбора shard-ключей

| Коллекция | Shard-ключ | Стратегия | Обоснование |
|-----------|-----------|-----------|-------------|
| `orders` | `{ user_id: "hashed" }` | Hashed | Равномерное распределение, совпадение с паттерном "история заказов пользователя" |
| `products` | `{ product_id: "hashed" }` | Hashed | Избежание горячих шардов в популярных категориях |
| `carts` | `{ user_id: "hashed", status: 1 }` | Compound (Hashed + Range) | Локализация запросов активных корзин, равномерное распределение |

---

## Задание 8: Выявление и устранение горячих шардов

### 8.1. Проблема горячих шардов

**Сценарий:** 70% запросов приходится на категорию "Электроника", что приводит к перегрузке одного шарда при использовании range-based sharding по категории.

**Причины возникновения:**
1. Неравномерное распределение данных (data skew)
2. Неравномерная нагрузка на чтение/запись (workload skew)
3. Монотонно возрастающие ключи (timestamp, auto-increment ID)

---

### 8.2. Метрики мониторинга

#### 8.2.1. Распределение данных по шардам

```javascript
// Проверка количества документов в каждом шарде
db.products.getShardDistribution()

// Вывод:
// Shard shard1: 35000 docs (35%)
// Shard shard2: 65000 docs (65%)  ← Горячий шард!
```

**Критерий:** Разница между шардами > 20% указывает на дисбаланс.

---

#### 8.2.2. Нагрузка на чтение/запись

```javascript
// Статистика операций на каждом шарде
db.adminCommand({ serverStatus: 1 }).opcounters

// Мониторинг через mongos
db.adminCommand({
  shardConnPoolStats: 1
})
```

**Метрики:**
- `opcountersRepl.query` — количество запросов на чтение
- `opcountersRepl.insert` — количество вставок
- `opcountersRepl.update` — количество обновлений

**Критерий:** Если один шард получает > 50% всех операций, он является горячим.

---

#### 8.2.3. Использование CPU и памяти

```bash
# Мониторинг через Docker Stats
docker stats shard1-1 shard2-1

# Мониторинг через MongoDB
db.serverStatus().connections
db.serverStatus().network
```

**Критерий:** CPU > 80% на одном шарде при < 50% на других.

---

#### 8.2.4. Latency запросов

```javascript
// Включить профилирование
db.setProfilingLevel(1, { slowms: 100 })

// Анализ медленных запросов
db.system.profile.find().sort({ ts: -1 }).limit(10)
```

**Критерий:** Медианное время ответа на одном шарде > 2x по сравнению с другими.

---

### 8.3. Автоматическое выявление горячих шардов

#### Скрипт мониторинга (JavaScript)

```javascript
// monitor_hot_shards.js
function checkHotShards(db, collectionName) {
  const stats = db[collectionName].stats();
  const shards = stats.shards;

  let maxOps = 0;
  let minOps = Infinity;
  let hotShard = null;

  for (const [shardName, shardStats] of Object.entries(shards)) {
    const ops = shardStats.count;

    if (ops > maxOps) {
      maxOps = ops;
      hotShard = shardName;
    }

    if (ops < minOps) {
      minOps = ops;
    }
  }

  const imbalance = (maxOps - minOps) / maxOps * 100;

  console.log(`Collection: ${collectionName}`);
  console.log(`Hot shard: ${hotShard} with ${maxOps} documents`);
  console.log(`Imbalance: ${imbalance.toFixed(2)}%`);

  if (imbalance > 20) {
    console.log(`⚠️ WARNING: Shard imbalance detected!`);
    return { hotShard, imbalance };
  }

  return null;
}

// Запуск мониторинга
const collections = ["orders", "products", "carts"];
collections.forEach(coll => checkHotShards(db, coll));
```

**Запуск:**
```bash
docker compose exec -T mongos_router mongosh --quiet < monitor_hot_shards.js
```

---

### 8.4. Механизмы устранения горячих шардов

#### 8.4.1. Балансировка существующих данных

MongoDB автоматически балансирует данные через **Balancer**.

**Проверка состояния балансировщика:**
```javascript
sh.getBalancerState()  // true если включен
sh.isBalancerRunning() // true если балансировка идет сейчас
```

**Включение балансировщика:**
```javascript
sh.startBalancer()
sh.setBalancerState(true)
```

**Настройка окна балансировки (чтобы не мешать пользователям):**
```javascript
db.settings.update(
  { _id: "balancer" },
  {
    $set: {
      activeWindow: {
        start: "02:00",  // Начало: 2:00 ночи
        stop: "06:00"    // Конец: 6:00 утра
      }
    }
  },
  { upsert: true }
)
```

---

#### 8.4.2. Refine Shard Key (MongoDB 4.4+)

Если текущий shard-ключ неоптимален, можно добавить к нему суффикс:

```javascript
// Исходный ключ: { category: 1 }
// Улучшенный ключ: { category: 1, product_id: 1 }

db.adminCommand({
  refineCollectionShardKey: "somedb.products",
  key: { category: 1, product_id: 1 }
})
```

**Когда использовать:**
- Когда текущий ключ слишком крупнозернистый (low cardinality)
- Для добавления монотонно возрастающего поля к хешированному ключу

---

#### 8.4.3. Решардирование (Resharding)

**Сценарий:** Полная замена shard-ключа (MongoDB 5.0+).

```javascript
// Изменить shard-ключ с { category: 1 } на { product_id: "hashed" }
db.adminCommand({
  reshardCollection: "somedb.products",
  key: { product_id: "hashed" }
})

// Мониторинг прогресса
db.adminCommand({ currentOp: true, desc: "ReshardingRecipientService" })
```

**⚠️ Предупреждения:**
- Решардирование создает значительную нагрузку на кластер
- Выполнять только в окнах низкой нагрузки
- Может занять несколько часов для больших коллекций

---

#### 8.4.4. Разделение больших чанков (Split Chunks)

Если один чанк слишком велик:

```javascript
// Найти большие чанки
db.chunks.find({ ns: "somedb.products" }).sort({ "max.product_id": -1 })

// Разделить чанк вручную
sh.splitAt("somedb.products", { product_id: "SMPH-X-12345" })

// Или разделить на N частей
sh.splitFind("somedb.products", { product_id: "SMPH-X-12345" })
```

---

#### 8.4.5. Добавление новых шардов

Если дисбаланс вызван нехваткой ресурсов:

```javascript
// Добавить третий шард
sh.addShard("shard3/shard3-1:27018,shard3-2:27018,shard3-3:27018")

// Проверить статус
sh.status()
```

Балансировщик автоматически начнет перемещать чанки на новый шард.

---

### 8.5. Стратегия мониторинга и реагирования

#### Уровни алертов

| Метрика | Желтый уровень (Warning) | Красный уровень (Critical) | Действие |
|---------|-------------------------|---------------------------|----------|
| Дисбаланс данных | > 20% | > 40% | Проверить балансировщик, рассмотреть split chunks |
| CPU на шарде | > 70% | > 85% | Добавить реплики для чтения, рассмотреть новый шард |
| Операции в секунду | > 60% на один шард | > 80% на один шард | Проверить shard-ключ, рассмотреть refine/reshard |
| Latency (p99) | > 200ms | > 500ms | Оптимизировать запросы, добавить индексы |

---

#### Автоматизированный мониторинг с Prometheus

```yaml
# prometheus.yml
scrape_configs:
  - job_name: 'mongodb'
    static_configs:
      - targets: ['mongodb-exporter:9216']

# Алерты в alertmanager.yml
groups:
  - name: mongodb_alerts
    rules:
      - alert: HotShardDetected
        expr: mongodb_shard_imbalance_percent > 30
        for: 15m
        annotations:
          summary: "Hot shard detected in MongoDB cluster"
```

---

### 8.6. Команды для диагностики

```javascript
// 1. Общая информация о кластере
sh.status()

// 2. Распределение данных по шардам для всех коллекций
db.adminCommand({ listShards: 1 })

// 3. Статистика по чанкам
use config
db.chunks.aggregate([
  { $group: { _id: "$shard", count: { $sum: 1 } } }
])

// 4. Топ-5 самых больших чанков
db.chunks.find({}, { ns: 1, min: 1, max: 1, shard: 1 }).sort({ "estimatedDataBytes": -1 }).limit(5)

// 5. История миграций (последние 10)
use config
db.changelog.find({ what: "moveChunk.commit" }).sort({ time: -1 }).limit(10)

// 6. Проверка активных операций
db.currentOp({ active: true })
```

---

## Задание 9: Настройка чтения с реплик и консистентность

### 9.1. Read Preference: Теория

MongoDB поддерживает 5 режимов чтения:

1. **primary** — все операции читают только с PRIMARY ноды (по умолчанию)
2. **primaryPreferred** — читать с PRIMARY, если недоступен — с SECONDARY
3. **secondary** — читать только с SECONDARY нод
4. **secondaryPreferred** — читать с SECONDARY, если недоступны — с PRIMARY
5. **nearest** — читать с ближайшей ноды (минимальная сетевая задержка)

---

### 9.2. Коллекция `orders` (Заказы)

#### Операции чтения

| Операция | Endpoint/Метод | Read Preference | Обоснование |
|----------|---------------|-----------------|-------------|
| **Получить историю заказов пользователя** | `GET /orders?user_id=123` | `secondaryPreferred` | Допустима задержка до 5 секунд. Пользователь просматривает старые заказы, консистентность не критична. |
| **Получить детали заказа** | `GET /orders/{order_id}` | `secondaryPreferred` | Аналогично: допустима задержка. |
| **Проверить статус заказа** | `GET /orders/{order_id}/status` | `primary` | **Критично:** Пользователь должен видеть актуальный статус (особенно для "доставлен", "отменен"). |
| **Создать новый заказ** (чтение для валидации) | `POST /orders` | `primary` | **Критично:** Перед созданием заказа нужно проверить остатки товара. Чтение с SECONDARY может привести к overselling. |
| **Поиск заказов в админ-панели** | `GET /admin/orders` | `secondary` | Административные отчеты не требуют строгой консистентности. Снижение нагрузки на PRIMARY. |

---

#### Допустимая задержка репликации

| Операция | Допустимая задержка | Причина |
|----------|-------------------|---------|
| История заказов | **5 секунд** | Пользователь редко обновляет список заказов чаще |
| Статус заказа | **0 секунд** (PRIMARY) | Критичная информация |
| Отчеты в админке | **30 секунд** | Агрегированные данные, не требуют мгновенного обновления |

---

#### Пример конфигурации (Python PyMongo)

```python
from pymongo import MongoClient, ReadPreference
from pymongo.read_concern import ReadConcern

client = MongoClient("mongodb://mongos_router:27017")
db = client.somedb

# История заказов: чтение с SECONDARY
def get_user_orders(user_id):
    orders = db.orders.with_options(
        read_preference=ReadPreference.SECONDARY_PREFERRED,
        read_concern=ReadConcern("local")  # Не ждать репликации
    )
    return list(orders.find({"user_id": user_id}).limit(50))

# Статус заказа: только PRIMARY
def get_order_status(order_id):
    orders = db.orders.with_options(
        read_preference=ReadPreference.PRIMARY,
        read_concern=ReadConcern("majority")  # Гарантировать подтверждение
    )
    result = orders.find_one({"_id": order_id}, {"status": 1})
    return result["status"] if result else None

# Создание заказа: проверка остатков с PRIMARY
def create_order(user_id, items):
    products = db.products.with_options(
        read_preference=ReadPreference.PRIMARY,
        read_concern=ReadConcern("majority")
    )

    # Проверить остатки товаров
    for item in items:
        product = products.find_one({"product_id": item["product_id"]})
        if not product or product["stock"]["quantity"] < item["quantity"]:
            raise ValueError(f"Недостаточно товара {item['product_id']}")

    # Создать заказ
    order = {
        "user_id": user_id,
        "items": items,
        "status": "pending",
        "created_at": datetime.utcnow()
    }
    db.orders.insert_one(order)
```

---

### 9.3. Коллекция `products` (Товары)

#### Операции чтения

| Операция | Endpoint/Метод | Read Preference | Обоснование |
|----------|---------------|-----------------|-------------|
| **Список товаров (каталог)** | `GET /products?category=electronics` | `secondary` | Каталог обновляется редко, допустима задержка до 10 секунд. |
| **Детали товара** | `GET /products/{product_id}` | `secondaryPreferred` | Описание товара редко меняется, но должно быть доступно даже при отказе SECONDARY. |
| **Проверка остатков при покупке** | `POST /orders` (внутри) | `primary` | **Критично:** Чтение с SECONDARY может привести к продаже несуществующего товара. |
| **Обновление остатков** | `PATCH /products/{product_id}/stock` | `primary` | Запись всегда на PRIMARY. |
| **Поиск товаров по фильтрам** | `GET /products/search?q=iPhone` | `secondary` | Поисковые запросы не требуют строгой консистентности. |

---

#### Допустимая задержка репликации

| Операция | Допустимая задержка | Причина |
|----------|-------------------|---------|
| Каталог товаров | **10 секунд** | Цены и наличие обновляются не мгновенно |
| Проверка остатков | **0 секунд** (PRIMARY) | Риск overselling |
| Поиск | **30 секунд** | Пользователь не заметит небольшую задержку |

---

#### Пример конфигурации

```python
# Каталог: чтение с SECONDARY
def get_products_by_category(category):
    products = db.products.with_options(
        read_preference=ReadPreference.SECONDARY
    )
    return list(products.find({"category": category}).limit(100))

# Проверка остатков: только PRIMARY
def check_stock(product_id, quantity):
    products = db.products.with_options(
        read_preference=ReadPreference.PRIMARY,
        read_concern=ReadConcern("majority")
    )
    product = products.find_one({"product_id": product_id})

    if not product:
        return False

    # Проверить остатки во всех геозонах
    total_stock = sum(item["quantity"] for item in product["stock"])
    return total_stock >= quantity
```

---

### 9.4. Коллекция `carts` (Корзины)

#### Операции чтения

| Операция | Endpoint/Метод | Read Preference | Обоснование |
|----------|---------------|-----------------|-------------|
| **Получить активную корзину** | `GET /carts?user_id=123&status=active` | `primaryPreferred` | Важно показывать актуальные данные, но допустима задержка до 2 секунд. |
| **Добавить товар в корзину** | `POST /carts/{cart_id}/items` | `primary` | Запись всегда на PRIMARY. Чтение для валидации тоже с PRIMARY. |
| **Удалить товар из корзины** | `DELETE /carts/{cart_id}/items/{item_id}` | `primary` | Аналогично: запись + валидация. |
| **Слияние гостевой корзины** | `POST /carts/merge` | `primary` | **Критично:** Транзакция, требующая строгой консистентности. |
| **Оформление заказа** | `POST /orders` (чтение корзины) | `primary` | Перед созданием заказа нужно актуальное состояние корзины. |

---

#### Допустимая задержка репликации

| Операция | Допустимая задержка | Причина |
|----------|-------------------|---------|
| Получить корзину | **2 секунды** | Пользователь ожидает увидеть последние изменения |
| Добавить/удалить товар | **0 секунд** (PRIMARY) | Мгновенная обратная связь |
| Слияние корзин | **0 секунд** (PRIMARY) | Транзакционная операция |

---

#### Пример конфигурации

```python
# Получить корзину: PRIMARY preferred
def get_active_cart(user_id):
    carts = db.carts.with_options(
        read_preference=ReadPreference.PRIMARY_PREFERRED,
        read_concern=ReadConcern("local")
    )
    return carts.find_one({"user_id": user_id, "status": "active"})

# Слияние корзин: строгая консистентность
def merge_carts(session_id, user_id):
    carts = db.carts.with_options(
        read_preference=ReadPreference.PRIMARY,
        read_concern=ReadConcern("majority"),
        write_concern={"w": "majority"}
    )

    # Начать транзакцию
    with client.start_session() as session:
        with session.start_transaction():
            guest_cart = carts.find_one(
                {"session_id": session_id, "status": "active"},
                session=session
            )

            user_cart = carts.find_one(
                {"user_id": user_id, "status": "active"},
                session=session
            )

            # Слить items
            if guest_cart and user_cart:
                carts.update_one(
                    {"_id": user_cart["_id"]},
                    {"$push": {"items": {"$each": guest_cart["items"]}}},
                    session=session
                )

                carts.update_one(
                    {"_id": guest_cart["_id"]},
                    {"$set": {"status": "abandoned"}},
                    session=session
                )
```

---

### 9.5. Сводная таблица: Read Preferences

| Коллекция | Операция | Read Preference | Допустимая задержка | Read Concern |
|-----------|----------|-----------------|-------------------|--------------|
| `orders` | История заказов | `secondaryPreferred` | 5 секунд | `local` |
| `orders` | Статус заказа | `primary` | 0 секунд | `majority` |
| `orders` | Создание заказа (валидация) | `primary` | 0 секунд | `majority` |
| `products` | Каталог | `secondary` | 10 секунд | `local` |
| `products` | Проверка остатков | `primary` | 0 секунд | `majority` |
| `products` | Поиск | `secondary` | 30 секунд | `local` |
| `carts` | Получить корзину | `primaryPreferred` | 2 секунды | `local` |
| `carts` | Добавить товар | `primary` | 0 секунд | `majority` |
| `carts` | Слияние корзин | `primary` | 0 секунд | `majority` |

---

### 9.6. Мониторинг задержки репликации

```javascript
// Проверить задержку репликации на каждом replica set
rs.status().members.forEach(function(member) {
  if (member.state == 2) { // SECONDARY
    const lag = new Date() - member.optimeDate;
    print(`${member.name}: Replication lag = ${lag}ms`);

    if (lag > 5000) {
      print(`⚠️ WARNING: High replication lag!`);
    }
  }
});
```

**Настройка алертов в Prometheus:**
```yaml
- alert: HighReplicationLag
  expr: mongodb_replset_member_oplog_lag_seconds > 5
  for: 5m
  annotations:
    summary: "Replication lag > 5 seconds"
```

---

## Задание 10: Миграция на Cassandra

### 10.1. Обоснование миграции

#### Проблемы MongoDB при "черной пятнице"

1. **Высокая задержка при масштабировании:**
   - MongoDB использует **Range-Based Sharding**, который требует полного перераспределения данных при добавлении шардов
   - Перемещение чанков создает дополнительную нагрузку на I/O

2. **Ограничения балансировщика:**
   - Балансировщик работает последовательно (один чанк за раз)
   - При пиковой нагрузке балансировка может занять часы

3. **Bottleneck на PRIMARY ноде:**
   - Все записи идут через PRIMARY реплику
   - При 50 000 запросов/сек PRIMARY не справляется

---

#### Преимущества Cassandra

1. **Leaderless репликация:**
   - Нет разделения на PRIMARY/SECONDARY
   - Любая нода может принимать записи

2. **Быстрое горизонтальное масштабирование:**
   - Добавление ноды не требует полного перераспределения данных
   - Перемещаются только данные, попадающие в новый диапазон токенов

3. **Равномерное распределение данных:**
   - Consistent Hashing с виртуальными нодами (vnodes)
   - Автоматическая балансировка

4. **Геораспределенность:**
   - Multi-datacenter репликация out-of-the-box
   - NetworkTopologyStrategy для разных регионов

---

### 10.2. Задание 10.1: Выбор данных для миграции

#### Критически важные данные для Cassandra

| Сущность | Миграция | Обоснование |
|----------|----------|-------------|
| **Orders (Заказы)** | ✅ **ДА** | - Высокая частота записи (50K/sec)<br>- Требуется мгновенное масштабирование<br>- Геораспределенность (разные регионы)<br>- Append-only операции (хорошо подходит для Cassandra) |
| **Products (Товары)** | ❌ **НЕТ** | - Частые обновления (stock)<br>- Требуется строгая консистентность для остатков<br>- Сложные транзакции (списание остатков)<br>- MongoDB лучше подходит |
| **Carts (Корзины)** | ❌ **НЕТ** | - TTL для автоматической очистки (есть в обеих БД)<br>- Частые обновления (не оптимально для Cassandra)<br>- Небольшой объем данных<br>- Можно оставить в MongoDB или использовать Redis |
| **Order History (История заказов)** | ✅ **ДА** | - Read-heavy нагрузка<br>- Пользователи просматривают историю<br>- Данные не меняются после создания<br>- Хорошо подходит для wide-column хранилища |
| **User Sessions (Сессии)** | ✅ **ДА** | - Высокая частота записи/чтения<br>- TTL для автоматической очистки<br>- Геораспределенность (пользователи из разных регионов) |

---

### 10.3. Задание 10.2: Модель данных для Cassandra

#### 10.3.1. Таблица `orders_by_user` (История заказов пользователя)

**Use case:** Пользователь просматривает историю своих заказов.

```cql
CREATE TABLE orders_by_user (
    user_id TEXT,
    created_at TIMESTAMP,
    order_id UUID,
    status TEXT,
    total_amount DECIMAL,
    geozone TEXT,
    items LIST<FROZEN<order_item>>,
    PRIMARY KEY ((user_id), created_at, order_id)
) WITH CLUSTERING ORDER BY (created_at DESC, order_id ASC);

-- User-defined type для items
CREATE TYPE order_item (
    product_id TEXT,
    product_name TEXT,
    quantity INT,
    price DECIMAL
);
```

**Обоснование:**

1. **Partition Key: `user_id`**
   - Все заказы одного пользователя хранятся в одной партиции
   - Высокая кардинальность (миллионы пользователей)
   - Локализация запросов: `SELECT * FROM orders_by_user WHERE user_id = ?`

2. **Clustering Keys: `created_at DESC, order_id ASC`**
   - `created_at DESC` — сортировка от новых к старым
   - `order_id` — уникальность для заказов с одинаковым timestamp
   - Эффективные range queries: "последние 10 заказов"

3. **Избежание горячих партиций:**
   - Распределение по `user_id` равномерное
   - Нет пользователей с миллионами заказов (max ~1000)

---

**Примеры запросов:**

```cql
-- Получить последние 10 заказов пользователя
SELECT * FROM orders_by_user
WHERE user_id = 'user123'
LIMIT 10;

-- Получить заказы за последний месяц
SELECT * FROM orders_by_user
WHERE user_id = 'user123'
  AND created_at > '2025-09-16';

-- Получить конкретный заказ
SELECT * FROM orders_by_user
WHERE user_id = 'user123'
  AND order_id = 550e8400-e29b-41d4-a716-446655440000;
```

---

#### 10.3.2. Таблица `orders_by_geozone` (Заказы по геозонам)

**Use case:** Администратор анализирует заказы в конкретном регионе.

```cql
CREATE TABLE orders_by_geozone (
    geozone TEXT,
    created_at TIMESTAMP,
    order_id UUID,
    user_id TEXT,
    status TEXT,
    total_amount DECIMAL,
    PRIMARY KEY ((geozone), created_at, order_id)
) WITH CLUSTERING ORDER BY (created_at DESC, order_id ASC);
```

**Обоснование:**

1. **Partition Key: `geozone`**
   - Запросы от администраторов: "Сколько заказов в Москве?"
   - Средняя кардинальность (~50 геозон)

2. **Риск горячих партиций:**
   - Москва и Санкт-Петербург могут получить 70% заказов
   - **Решение:** Использовать **composite partition key** с bucketing

---

**Улучшенная схема с bucketing:**

```cql
CREATE TABLE orders_by_geozone (
    geozone TEXT,
    bucket INT,               -- 0-99 (100 бакетов)
    created_at TIMESTAMP,
    order_id UUID,
    user_id TEXT,
    status TEXT,
    total_amount DECIMAL,
    PRIMARY KEY ((geozone, bucket), created_at, order_id)
) WITH CLUSTERING ORDER BY (created_at DESC, order_id ASC);
```

**Как работает bucketing:**

```python
import hashlib

def get_bucket(order_id):
    return int(hashlib.md5(order_id.encode()).hexdigest(), 16) % 100

# При вставке
bucket = get_bucket(order_id)
session.execute("""
    INSERT INTO orders_by_geozone (geozone, bucket, created_at, order_id, ...)
    VALUES (?, ?, ?, ?, ...)
""", (geozone, bucket, created_at, order_id, ...))

# При чтении: фанаут по всем бакетам
results = []
for bucket in range(100):
    rows = session.execute("""
        SELECT * FROM orders_by_geozone
        WHERE geozone = ? AND bucket = ?
        LIMIT 10
    """, (geozone, bucket))
    results.extend(rows)

# Сортировка результатов
results = sorted(results, key=lambda x: x.created_at, reverse=True)[:10]
```

---

#### 10.3.3. Таблица `orders_by_status` (Заказы по статусу)

**Use case:** Мониторинг заказов в обработке, отмененных и т.д.

```cql
CREATE TABLE orders_by_status (
    status TEXT,
    created_at TIMESTAMP,
    order_id UUID,
    user_id TEXT,
    geozone TEXT,
    total_amount DECIMAL,
    PRIMARY KEY ((status), created_at, order_id)
) WITH CLUSTERING ORDER BY (created_at DESC, order_id ASC);
```

**Проблема:** Статус заказа может меняться (`pending` → `shipped` → `delivered`).

**Решение:** При изменении статуса:
1. Удалить запись из старой партиции
2. Вставить запись в новую партицию

```cql
-- Изменить статус с "pending" на "shipped"
BEGIN BATCH
    DELETE FROM orders_by_status
    WHERE status = 'pending'
      AND created_at = ?
      AND order_id = ?;

    INSERT INTO orders_by_status (status, created_at, order_id, ...)
    VALUES ('shipped', ?, ?, ...);
APPLY BATCH;
```

---

#### 10.3.4. Таблица `user_sessions` (Сессии пользователей)

**Use case:** Хранение активных сессий для аутентификации.

```cql
CREATE TABLE user_sessions (
    session_id UUID,
    user_id TEXT,
    created_at TIMESTAMP,
    expires_at TIMESTAMP,
    ip_address TEXT,
    user_agent TEXT,
    PRIMARY KEY ((session_id))
) WITH default_time_to_live = 86400;  -- TTL 24 часа
```

**Обоснование:**

1. **Partition Key: `session_id`**
   - Прямой доступ по ключу: `SELECT * WHERE session_id = ?`
   - Высокая кардинальность

2. **TTL:** Автоматическая очистка старых сессий через 24 часа.

---

### 10.4. Сводная таблица моделей данных

| Таблица | Partition Key | Clustering Keys | Use Case | Риск горячих партиций |
|---------|--------------|-----------------|----------|---------------------|
| `orders_by_user` | `user_id` | `created_at DESC, order_id` | История заказов пользователя | ❌ Низкий |
| `orders_by_geozone` | `geozone, bucket` | `created_at DESC, order_id` | Анализ по регионам | ⚠️ Средний (решено bucketing) |
| `orders_by_status` | `status` | `created_at DESC, order_id` | Мониторинг заказов | ⚠️ Средний (мало статусов) |
| `user_sessions` | `session_id` | — | Аутентификация | ❌ Низкий |

---

### 10.5. Задание 10.3: Стратегии репликации и консистентности

#### 10.5.1. Replication Factor (RF)

**Рекомендация:** `RF = 3` для production.

```cql
CREATE KEYSPACE ecommerce
WITH replication = {
    'class': 'NetworkTopologyStrategy',
    'datacenter1': 3,     -- 3 реплики в ЦОД Москвы
    'datacenter2': 3      -- 3 реплики в ЦОД Санкт-Петербурга
};
```

---

#### 10.5.2. Consistency Level (CL)

Cassandra использует tunable consistency: `(W + R) > RF` для строгой консистентности.

| Операция | Consistency Level (Write) | Consistency Level (Read) | Обоснование |
|----------|---------------------------|--------------------------|-------------|
| **Создание заказа** | `QUORUM` (W=2/3) | `QUORUM` (R=2/3) | Гарантировать сохранность заказа при отказе 1 ноды |
| **История заказов** | `ONE` (W=1) | `ONE` (R=1) | Низкая latency, допустима eventual consistency |
| **Сессии пользователей** | `LOCAL_QUORUM` | `LOCAL_QUORUM` | Консистентность в пределах одного ЦОД |
| **Статус заказа** | `QUORUM` | `QUORUM` | Критично для бизнес-логики |

---

**Пример конфигурации (Python Cassandra Driver):**

```python
from cassandra.cluster import Cluster, ExecutionProfile, EXEC_PROFILE_DEFAULT
from cassandra.policies import DCAwareRoundRobinPolicy, TokenAwarePolicy
from cassandra import ConsistencyLevel

# Профили для разных типов запросов
profile_strong = ExecutionProfile(
    load_balancing_policy=TokenAwarePolicy(DCAwareRoundRobinPolicy()),
    consistency_level=ConsistencyLevel.QUORUM
)

profile_weak = ExecutionProfile(
    load_balancing_policy=TokenAwarePolicy(DCAwareRoundRobinPolicy()),
    consistency_level=ConsistencyLevel.ONE
)

cluster = Cluster(
    contact_points=['cassandra1', 'cassandra2', 'cassandra3'],
    execution_profiles={
        EXEC_PROFILE_DEFAULT: profile_strong,
        'weak': profile_weak
    }
)

session = cluster.connect('ecommerce')

# Создание заказа: QUORUM
session.execute("""
    INSERT INTO orders_by_user (user_id, created_at, order_id, ...)
    VALUES (?, ?, ?, ...)
""", (user_id, created_at, order_id, ...))

# История заказов: ONE (низкая latency)
rows = session.execute(
    "SELECT * FROM orders_by_user WHERE user_id = ? LIMIT 10",
    (user_id,),
    execution_profile='weak'
)
```

---

#### 10.5.3. Hinted Handoff

**Назначение:** Временное хранение записей для недоступной ноды.

**Как работает:**
1. Клиент пишет с `CL=QUORUM`, но одна из 3 реплик недоступна
2. Координатор сохраняет hint (подсказку) для недоступной ноды
3. Когда нода восстанавливается, координатор отправляет hint

**Для каких сущностей использовать:**

| Сущность | Hinted Handoff | Обоснование |
|----------|---------------|-------------|
| `orders_by_user` | ✅ **Включить** | Критично сохранить заказ даже при отказе ноды |
| `user_sessions` | ❌ **Отключить** | TTL=24ч, нет смысла хранить hints для временных данных |
| `orders_by_status` | ✅ **Включить** | Административные данные, важно не потерять |

**Настройка:**

```yaml
# cassandra.yaml
hinted_handoff_enabled: true
max_hint_window_in_ms: 10800000  # 3 часа
hinted_handoff_throttle_in_kb: 1024
```

---

#### 10.5.4. Read Repair

**Назначение:** Автоматическое исправление устаревших данных при чтении.

**Как работает:**
1. Клиент читает с `CL=QUORUM` (2 из 3 реплик)
2. Координатор сравнивает timestamps данных
3. Если найдена несогласованность, координатор обновляет устаревшие реплики

**Типы Read Repair:**

1. **Blocking Read Repair** (синхронный):
   - Клиент ждет, пока все реплики будут обновлены
   - Увеличивает latency

2. **Background Read Repair** (асинхронный):
   - Клиент получает ответ немедленно
   - Repair выполняется в фоне

**Для каких сущностей использовать:**

| Сущность | Read Repair | Тип | Обоснование |
|----------|------------|-----|-------------|
| `orders_by_user` | ✅ **Включить** | Background | История заказов редко меняется, асинхронный repair достаточен |
| `user_sessions` | ❌ **Отключить** | — | TTL, данные быстро истекают |
| `orders_by_status` | ✅ **Включить** | Blocking | Критично показывать актуальный статус |

**Настройка:**

```cql
-- Включить read repair для таблицы
ALTER TABLE orders_by_user
WITH read_repair = 'BLOCKING';

-- Или асинхронный
ALTER TABLE orders_by_user
WITH read_repair = 'NONE'
AND dclocal_read_repair = 0.1;  -- 10% запросов с repair
```

---

#### 10.5.5. Anti-Entropy Repair (nodetool repair)

**Назначение:** Периодическая синхронизация всех реплик для устранения расхождений.

**Как работает:**
1. Запускается вручную или по расписанию (cron)
2. Cassandra сравнивает Merkle trees всех реплик
3. Синхронизирует различающиеся данные

**Для каких сущностей использовать:**

| Сущность | Частота Repair | Обоснование |
|----------|---------------|-------------|
| `orders_by_user` | **Раз в неделю** | Данные не меняются после создания, редкий repair достаточен |
| `user_sessions` | **Не нужен** | TTL=24ч, данные автоматически удаляются |
| `orders_by_status` | **Раз в день** | Данные часто обновляются (смена статуса) |

**Команды:**

```bash
# Full repair всех данных (медленно, высокая нагрузка)
nodetool repair ecommerce

# Incremental repair (быстрее, рекомендуется)
nodetool repair -inc ecommerce

# Repair конкретной таблицы
nodetool repair ecommerce orders_by_user

# Repair в окне низкой нагрузки
nodetool repair -pr -seq ecommerce
```

**Автоматизация через cron:**

```bash
# /etc/cron.d/cassandra-repair
0 3 * * 0 cassandra nodetool repair -inc ecommerce orders_by_user
0 2 * * * cassandra nodetool repair -inc ecommerce orders_by_status
```

---

### 10.6. Сводная таблица стратегий восстановления

| Стратегия | orders_by_user | orders_by_status | user_sessions |
|-----------|---------------|------------------|---------------|
| **Hinted Handoff** | ✅ Включить | ✅ Включить | ❌ Отключить |
| **Read Repair** | ✅ Background (10%) | ✅ Blocking | ❌ Отключить |
| **Anti-Entropy Repair** | ✅ Раз в неделю | ✅ Раз в день | ❌ Не нужен |

---

### 10.7. Компромиссы: CAP-теорема

| Конфигурация | Consistency | Availability | Partition Tolerance | Latency |
|--------------|-------------|--------------|---------------------|---------|
| `CL=QUORUM` (W+R) | ⭐⭐⭐ Высокая | ⭐⭐ Средняя | ⭐⭐⭐ Высокая | ~50ms |
| `CL=ONE` | ⭐ Низкая | ⭐⭐⭐ Высокая | ⭐⭐⭐ Высокая | ~10ms |
| `CL=ALL` | ⭐⭐⭐ Максимальная | ⭐ Низкая | ⭐ Низкая | ~100ms |

**Рекомендация для "черной пятницы":**
- **Writes:** `CL=LOCAL_QUORUM` — баланс между консистентностью и latency
- **Reads:** `CL=ONE` для некритичных данных, `CL=QUORUM` для критичных

---

### 10.8. Миграция: Практические шаги

#### Этап 1: Подготовка

```bash
# 1. Создать Cassandra кластер (3 ноды)
docker compose -f cassandra-cluster.yml up -d

# 2. Создать keyspace
cqlsh -e "
CREATE KEYSPACE ecommerce
WITH replication = {'class': 'SimpleStrategy', 'replication_factor': 3};
"

# 3. Создать таблицы
cqlsh -f schema.cql
```

---

#### Этап 2: Dual-Write (параллельная запись)

```python
def create_order(user_id, items):
    # 1. Записать в MongoDB (основная БД)
    mongo_order = {
        "user_id": user_id,
        "items": items,
        "created_at": datetime.utcnow()
    }
    mongo_db.orders.insert_one(mongo_order)

    # 2. Записать в Cassandra (новая БД)
    try:
        cassandra_session.execute("""
            INSERT INTO orders_by_user (user_id, created_at, order_id, ...)
            VALUES (?, ?, ?, ...)
        """, (user_id, mongo_order["created_at"], mongo_order["_id"], ...))
    except Exception as e:
        logger.error(f"Failed to write to Cassandra: {e}")
        # Не падать, если Cassandra недоступна
```

---

#### Этап 3: Backfill (перенос исторических данных)

```python
# Скрипт для переноса данных из MongoDB в Cassandra
from pymongo import MongoClient
from cassandra.cluster import Cluster

mongo_client = MongoClient("mongodb://mongos:27017")
cassandra_cluster = Cluster(['cassandra1', 'cassandra2', 'cassandra3'])
cassandra_session = cassandra_cluster.connect('ecommerce')

# Подготовить statement
insert_stmt = cassandra_session.prepare("""
    INSERT INTO orders_by_user (user_id, created_at, order_id, status, total_amount, geozone, items)
    VALUES (?, ?, ?, ?, ?, ?, ?)
""")

# Перенести данные (batch по 1000)
orders = mongo_client.somedb.orders.find().batch_size(1000)
count = 0

for order in orders:
    cassandra_session.execute(insert_stmt, (
        order["user_id"],
        order["created_at"],
        order["_id"],
        order["status"],
        order["total_amount"],
        order["geozone"],
        order["items"]
    ))

    count += 1
    if count % 10000 == 0:
        print(f"Migrated {count} orders")

print(f"Migration complete: {count} orders")
```

---

#### Этап 4: Переключение трафика

```python
# Feature flag для постепенного переключения
USE_CASSANDRA = os.getenv("USE_CASSANDRA", "false") == "true"

def get_user_orders(user_id):
    if USE_CASSANDRA:
        # Читать из Cassandra
        rows = cassandra_session.execute(
            "SELECT * FROM orders_by_user WHERE user_id = ? LIMIT 10",
            (user_id,)
        )
        return list(rows)
    else:
        # Читать из MongoDB (fallback)
        return list(mongo_db.orders.find({"user_id": user_id}).limit(10))
```

---

#### Этап 5: Мониторинг и откат

```bash
# Мониторинг латентности
SELECT * FROM system.local;
nodetool status

# Если проблемы: откатиться на MongoDB
export USE_CASSANDRA=false
docker compose restart pymongo-api
```

---

## Заключение

Архитектурные решения, описанные в этом документе, обеспечивают:

1. **Масштабируемость:** Шардирование MongoDB с хешированными ключами
2. **Отказоустойчивость:** Репликация с автоматическим failover
3. **Производительность:** Кеширование и оптимизация read preferences
4. **Мониторинг:** Метрики для выявления горячих шардов
5. **Миграция:** План перехода на Cassandra для критичных данных

**Итоговая архитектура готова к нагрузке "черной пятницы" (50 000+ запросов/сек).**

---

Дата создания документа: 16 октября 2025
