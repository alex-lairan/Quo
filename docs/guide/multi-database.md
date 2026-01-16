# Multi-Database

Quo supports multi-database configurations including primary/replica setups and horizontal sharding.

## Primary/Replica Setup

Route reads to replicas and writes to the primary database.

### Basic Configuration

```crystal
require "pg"
require "quo"

# Create pools for primary and replicas
primary_pool = Quo::ConnectionPool.new("postgres://primary-host/mydb", config)
replica1_pool = Quo::ConnectionPool.new("postgres://replica1-host/mydb", config)
replica2_pool = Quo::ConnectionPool.new("postgres://replica2-host/mydb", config)

# Create database with routing
db = Quo::Database.new(
  primary: primary_pool,
  replicas: [replica1_pool, replica2_pool],
  replica_strategy: Quo::ReplicaStrategy::RoundRobin
)
```

### Replica Selection Strategies

| Strategy | Behavior |
|----------|----------|
| `RoundRobin` | Cycle through replicas in order (default) |
| `Random` | Random replica selection |
| `LeastConnections` | Select replica with fewest active connections |

```crystal
# Round-robin (default)
db = Quo::Database.new(
  primary: primary_pool,
  replicas: [replica1, replica2],
  replica_strategy: Quo::ReplicaStrategy::RoundRobin
)

# Random selection
db = Quo::Database.new(
  primary: primary_pool,
  replicas: [replica1, replica2],
  replica_strategy: Quo::ReplicaStrategy::Random
)

# Least connections
db = Quo::Database.new(
  primary: primary_pool,
  replicas: [replica1, replica2],
  replica_strategy: Quo::ReplicaStrategy::LeastConnections
)
```

### Automatic Read/Write Routing

```crystal
# Get adapters that automatically route
read_adapter = db.read_adapter(:postgres)   # Uses replicas
write_adapter = db.write_adapter(:postgres) # Uses primary

# Reads go to replicas
users = Quo::Query.new(:users, read_adapter)
  .where(users: { active: true })
  .to_a

# Writes go to primary
Quo::InsertQuery.new(:users, write_adapter)
  .values(name: "Alice", email: "alice@example.com")
  .execute
```

### Force Primary for Reads

After a write, you may need to read from the primary to see your changes:

```crystal
db.use_primary do
  # All reads in this block go to primary
  user = Quo::Query.new(:users, db.read_adapter(:postgres))
    .where(users: { id: new_user_id })
    .first!
end
```

### Transactions

Transactions always run on the primary:

```crystal
db.transaction(:postgres) do |tx|
  # All queries here go to primary
  tx.insert(:users).values(name: "Bob").execute
  tx.update(:accounts).set(balance: 100).execute
end
```

## Sharding

Distribute data across multiple databases using a sharding key.

### Basic Sharding Setup

```crystal
# Create database instances for each shard
shard0 = Quo::Database.new(primary: shard0_pool)
shard1 = Quo::Database.new(primary: shard1_pool)
shard2 = Quo::Database.new(primary: shard2_pool)

# Create shard manager
manager = Quo::ShardManager.new(
  shards: [shard0, shard1, shard2],
  strategy: Quo::ModuloSharding.new
)
```

### Sharding Strategies

#### Modulo Sharding

Distributes keys evenly using hash modulo:

```crystal
strategy = Quo::ModuloSharding.new

# key.hash % shard_count
manager = Quo::ShardManager.new(
  shards: shards,
  strategy: strategy
)
```

#### Range Sharding

Maps value ranges to specific shards:

```crystal
# Ranges: (min, max, shard_id)
ranges = [
  {0_i64, 999_999_i64, 0},       # IDs 0-999,999 -> shard 0
  {1_000_000_i64, 1_999_999_i64, 1}, # IDs 1M-2M -> shard 1
  {2_000_000_i64, Int64::MAX, 2},    # IDs 2M+ -> shard 2
]

strategy = Quo::RangeSharding.new(ranges)

manager = Quo::ShardManager.new(
  shards: shards,
  strategy: strategy
)
```

#### Consistent Hash Sharding

More stable than modulo when adding/removing shards:

```crystal
strategy = Quo::ConsistentHashSharding.new(
  shard_count: 3,
  virtual_nodes: 100
)

manager = Quo::ShardManager.new(
  shards: shards,
  strategy: strategy
)
```

### Routing to a Shard

```crystal
# Get database for a specific key
user_id = 12345_i64
db = manager.for_key(user_id)

# Query that shard
adapter = db.read_adapter(:postgres)
user = Quo::Query.new(:users, adapter)
  .where(users: { id: user_id })
  .first!
```

### Query All Shards

```crystal
# Sequential query across all shards
all_active_users = manager.across_all_shards do |db, shard_id|
  adapter = db.read_adapter(:postgres)
  Quo::Query.new(:users, adapter)
    .where(users: { active: true })
    .to_a
end.flatten

# Parallel query across all shards
all_active_users = manager.parallel_across_shards do |db, shard_id|
  adapter = db.read_adapter(:postgres)
  Quo::Query.new(:users, adapter)
    .where(users: { active: true })
    .to_a
end.flatten
```

### Count Across Shards

```crystal
total_users = manager.count_all(:users, :postgres) do |query|
  query.where(users: { active: true })
end
```

## Monitoring

### Database Stats

```crystal
# Get stats for primary and all replicas
stats = db.stats

stats.each do |name, pool_stats|
  puts "#{name}:"
  puts "  Open: #{pool_stats.open_connections}"
  puts "  In use: #{pool_stats.in_use}"
  puts "  Utilization: #{(pool_stats.utilization * 100).round(1)}%"
end
```

### Shard Stats

```crystal
# Get stats for all shards
shard_stats = manager.stats

shard_stats.each do |shard_name, db_stats|
  puts "#{shard_name}:"
  db_stats.each do |pool_name, pool_stats|
    puts "  #{pool_name}: #{pool_stats.in_use}/#{pool_stats.open_connections}"
  end
end
```

### Health Checks

```crystal
# Check if all databases are healthy
if db.healthy?
  puts "Primary and all replicas healthy"
end

# Check if all shards are healthy
if manager.healthy?
  puts "All shards healthy"
end
```

## Graceful Shutdown

```crystal
# Close database (primary + replicas)
db.close(timeout: 30.seconds)

# Close all shards
manager.close(timeout: 30.seconds)
```

## Example: E-commerce Application

```crystal
module MyApp
  # Primary/replica for user data
  class_getter user_db : Quo::Database do
    primary = Quo::ConnectionPool.new(ENV["PRIMARY_URL"], pool_config)
    replicas = ENV["REPLICA_URLS"].split(",").map do |url|
      Quo::ConnectionPool.new(url, pool_config)
    end

    Quo::Database.new(
      primary: primary,
      replicas: replicas,
      replica_strategy: Quo::ReplicaStrategy::LeastConnections
    )
  end

  # Sharded order data
  class_getter order_shards : Quo::ShardManager do
    shards = ENV["SHARD_URLS"].split(",").map do |url|
      pool = Quo::ConnectionPool.new(url, pool_config)
      Quo::Database.new(primary: pool)
    end

    Quo::ShardManager.new(
      shards: shards,
      strategy: Quo::ModuloSharding.new
    )
  end

  def self.close
    user_db.close
    order_shards.close
  end
end

# Read user from replica
user = Quo::Query.new(:users, MyApp.user_db.read_adapter(:postgres))
  .where(users: { id: user_id })
  .first!

# Read orders from correct shard
order_db = MyApp.order_shards.for_key(user_id)
orders = Quo::Query.new(:orders, order_db.read_adapter(:postgres))
  .where(orders: { user_id: user_id })
  .to_a

# Write new order to correct shard
MyApp.user_db.use_primary do
  MyApp.user_db.transaction(:postgres) do |tx|
    # Update user's last_order_at on primary
    tx.update(:users)
      .set(last_order_at: Time.utc)
      .where(users: { id: user_id })
      .execute
  end
end

# Insert order on correct shard
order_db = MyApp.order_shards.for_key(user_id)
Quo::InsertQuery.new(:orders, order_db.write_adapter(:postgres))
  .values(user_id: user_id, total: 9999_i64)
  .execute
```
