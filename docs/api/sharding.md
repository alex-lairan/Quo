# Sharding API

Horizontal partitioning support for distributing data across multiple databases.

## ShardingStrategy

Abstract base class for sharding algorithms.

```crystal
abstract class Quo::ShardingStrategy
  # Determine which shard a key should route to
  abstract def shard_for(key_value : DB::Any, shard_count : Int32) : Int32
end
```

---

## ModuloSharding

Distributes keys evenly using modulo operation.

```crystal
class Quo::ModuloSharding < ShardingStrategy
  def shard_for(key_value : DB::Any, shard_count : Int32) : Int32
end
```

**Algorithm:** `hash(key) % shard_count`

Good for:
- Even distribution
- Simple setup
- Integer or string keys

**Note:** Adding or removing shards requires data migration since the modulo changes.

### Example

```crystal
strategy = Quo::ModuloSharding.new

# Integer keys
strategy.shard_for(1, 3)   # => 1
strategy.shard_for(100, 3) # => 1
strategy.shard_for(101, 3) # => 2

# String keys (uses hash)
strategy.shard_for("user_abc", 3) # => 0-2
```

---

## RangeSharding

Maps value ranges to specific shards.

```crystal
class Quo::RangeSharding < ShardingStrategy
  def initialize(ranges : Array({Int64, Int64, Int32}))
  def shard_for(key_value : DB::Any, shard_count : Int32) : Int32
end
```

**Constructor:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `ranges` | `Array({Int64, Int64, Int32})` | Array of (min, max, shard_id) tuples |

**Note:** Only works with integer keys.

### Example

```crystal
# Shard 0: IDs 1-1000000
# Shard 1: IDs 1000001-2000000
# Shard 2: IDs 2000001-3000000
strategy = Quo::RangeSharding.new([
  {1_i64, 1_000_000_i64, 0},
  {1_000_001_i64, 2_000_000_i64, 1},
  {2_000_001_i64, 3_000_000_i64, 2},
])

strategy.shard_for(500_000, 3)   # => 0
strategy.shard_for(1_500_000, 3) # => 1
strategy.shard_for(2_500_000, 3) # => 2
```

**Raises:** `ShardingError` if value doesn't fall in any range.

---

## ConsistentHashSharding

Uses consistent hashing for stable key distribution when adding/removing shards.

```crystal
class Quo::ConsistentHashSharding < ShardingStrategy
  def initialize(shard_count : Int32, virtual_nodes : Int32 = 100)
  def shard_for(key_value : DB::Any, shard_count : Int32) : Int32
end
```

**Constructor:**

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `shard_count` | `Int32` | required | Number of shards |
| `virtual_nodes` | `Int32` | `100` | Virtual nodes per shard (more = better distribution) |

**Algorithm:** Creates a hash ring with virtual nodes. Keys are hashed and routed to the nearest node.

Good for:
- Dynamic shard count (adding/removing shards)
- Minimizing data movement during rebalancing
- String or UUID keys

### Example

```crystal
# Initialize with 3 shards
strategy = Quo::ConsistentHashSharding.new(shard_count: 3, virtual_nodes: 150)

# Routes to consistent shard
strategy.shard_for("user_123", 3) # => 0-2 (deterministic)
strategy.shard_for("user_456", 3) # => 0-2

# Adding a 4th shard only moves ~25% of keys
```

---

## ShardManager

Manages multiple sharded databases and provides routing/querying utilities.

```crystal
class Quo::ShardManager
  def initialize(
    shards : Array(Database),
    strategy : ShardingStrategy = ModuloSharding.new
  )
end
```

### Constructor

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `shards` | `Array(Database)` | required | Shard databases |
| `strategy` | `ShardingStrategy` | `ModuloSharding.new` | Routing strategy |

**Raises:** `ShardingError` if shards array is empty.

### Methods

| Method | Return | Description |
|--------|--------|-------------|
| `for_key(value)` | `Database` | Get database for shard key |
| `on_shard(value, &block)` | `T` | Execute block on shard for key |
| `shard(index)` | `Database` | Get database by shard index |
| `on_shard_index(index, &block)` | `T` | Execute block on shard by index |
| `each_shard(&block)` | `Nil` | Iterate all shards sequentially |
| `across_all_shards(&block)` | `Array(T)` | Execute on all shards, collect results |
| `parallel_across_shards(&block)` | `Array(T)` | Execute on all shards in parallel |
| `query_all(table, type, &block)` | `ResultSet` | Query all shards, merge results |
| `parallel_query_all(table, type, &block)` | `ResultSet` | Query all shards in parallel |
| `count_all(table, type, &block)` | `Int64` | Count across all shards |
| `stats` | `Hash(String, Hash(String, PoolStats))` | Statistics for all shards |
| `healthy?` | `Bool` | Check if all shards are healthy |
| `close(timeout)` | `Nil` | Close all shards |
| `shard_count` | `Int32` | Number of shards |
| `strategy` | `ShardingStrategy` | Current sharding strategy |

### for_key

```crystal
def for_key(key_value : DB::Any) : Database
```

Get the database for a specific shard key value.

### on_shard

```crystal
def on_shard(key_value : DB::Any, &block : Database ->)
```

Execute a block on the shard for the given key.

### shard / on_shard_index

```crystal
def shard(index : Int32) : Database
def on_shard_index(index : Int32, &block : Database ->)
```

Access a specific shard by index (0-based).

**Raises:** `ShardingError` if index out of range.

### each_shard

```crystal
def each_shard(&block : Database, Int32 ->)
```

Iterate over all shards sequentially with their index.

### across_all_shards

```crystal
def across_all_shards(&block : Database, Int32 -> T) : Array(T) forall T
```

Execute block on each shard and collect results.

### parallel_across_shards

```crystal
def parallel_across_shards(&block : Database, Int32 -> T) : Array(T) forall T
```

Execute block on all shards concurrently using fibers.

### query_all / parallel_query_all

```crystal
def query_all(table : Symbol, adapter_type : Symbol = :postgres, &block : Query -> Query) : Quo::ResultSet
def parallel_query_all(table : Symbol, adapter_type : Symbol = :postgres, &block : Query -> Query) : Quo::ResultSet
```

Execute a query across all shards and merge results.

### count_all

```crystal
def count_all(table : Symbol, adapter_type : Symbol = :postgres, &block : Query -> Query) : Int64
```

Count records across all shards.

---

## Example Usage

### Basic Setup

```crystal
require "pg"
require "quo"

# Create shard databases
shard0 = Quo::Database.new(
  primary: Quo::ConnectionPool.new("postgres://shard0.db/myapp")
)
shard1 = Quo::Database.new(
  primary: Quo::ConnectionPool.new("postgres://shard1.db/myapp")
)
shard2 = Quo::Database.new(
  primary: Quo::ConnectionPool.new("postgres://shard2.db/myapp")
)

# Create shard manager
manager = Quo::ShardManager.new(
  shards: [shard0, shard1, shard2],
  strategy: Quo::ModuloSharding.new
)
```

### Route by Key

```crystal
# Insert user to correct shard
user_id = 12345

manager.on_shard(user_id) do |db|
  Quo::InsertQuery.new(:users, db.write_adapter)
    .values(id: user_id, name: "Alice")
    .execute
end

# Query user from correct shard
manager.on_shard(user_id) do |db|
  UsersRelation.new(db.read_adapter)
    .where(users: { id: user_id })
    .first
end
```

### Query All Shards

```crystal
# Find all active users across all shards
all_active = manager.query_all(:users) do |query|
  query.where(users: { active: true })
end

puts "Total active users: #{all_active.size}"

# Count across all shards
total = manager.count_all(:users) do |query|
  query.where(users: { active: true })
end

puts "Total: #{total}"
```

### Parallel Queries

```crystal
# Execute queries on all shards concurrently
results = manager.parallel_query_all(:orders) do |query|
  query
    .where { |e| e[:orders][:created_at] >= 1.week.ago }
    .order(orders: { created_at: :desc })
    .limit(100)
end

# Aggregate results from all shards
total_revenue = manager.parallel_across_shards do |db, shard_id|
  adapter = db.read_adapter
  sql, params = Quo::Query.new(:orders, adapter)
    .where { |e| e[:orders][:status] == "completed" }
    .select("SUM(total) as revenue")
    .to_sql

  adapter.execute_scalar(sql, params, as: Float64?)
end

puts "Revenue per shard: #{total_revenue}"
puts "Total: #{total_revenue.compact.sum}"
```

### Range Sharding

```crystal
# Shards by ID ranges
strategy = Quo::RangeSharding.new([
  {1_i64, 10_000_000_i64, 0},       # Old users
  {10_000_001_i64, 50_000_000_i64, 1}, # Growing segment
  {50_000_001_i64, Int64::MAX, 2},    # New users
])

manager = Quo::ShardManager.new(shards: shards, strategy: strategy)
```

### Consistent Hash Sharding

```crystal
# For UUID-based keys or when shards may be added/removed
strategy = Quo::ConsistentHashSharding.new(
  shard_count: 3,
  virtual_nodes: 200
)

manager = Quo::ShardManager.new(shards: shards, strategy: strategy)

# Route by UUID
manager.on_shard("550e8400-e29b-41d4-a716-446655440000") do |db|
  # ...
end
```

### Monitoring

```crystal
# Check health
if manager.healthy?
  puts "All #{manager.shard_count} shards healthy"
else
  puts "Shard issues detected"
end

# Detailed stats
manager.stats.each do |shard_name, pool_stats|
  pool_stats.each do |pool_name, stats|
    puts "#{shard_name}/#{pool_name}: #{stats.utilization * 100}% utilization"
  end
end
```

---

## Exceptions

### ShardingError

```crystal
class Quo::ShardingError < Exception
```

Raised when:
- No shards provided to ShardManager
- Shard index out of range
- RangeSharding can't find range for value
- RangeSharding receives non-integer key
