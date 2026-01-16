# Database API

Multi-database management with automatic read/write routing.

## ConnectionRole

Enum for connection routing.

```crystal
enum Quo::ConnectionRole
  Primary   # Write operations
  Replica   # Read operations
end
```

---

## ReplicaStrategy

Routing strategy for selecting replicas.

```crystal
enum Quo::ReplicaStrategy
  RoundRobin       # Cycle through replicas sequentially
  Random           # Select replica randomly
  LeastConnections # Select replica with fewest in-use connections
end
```

---

## Database

Manages primary and replica connections with automatic routing.

```crystal
class Quo::Database
  def initialize(
    primary : ConnectionPool,
    replicas : Array(ConnectionPool) = [] of ConnectionPool,
    replica_strategy : ReplicaStrategy = ReplicaStrategy::RoundRobin
  )
end
```

### Constructor

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `primary` | `ConnectionPool` | required | Primary database pool |
| `replicas` | `Array(ConnectionPool)` | `[]` | Replica database pools |
| `replica_strategy` | `ReplicaStrategy` | `RoundRobin` | Replica selection strategy |

### Methods

| Method | Return | Description |
|--------|--------|-------------|
| `pool_for(role)` | `ConnectionPool` | Get pool for a specific role |
| `for_read` | `ConnectionPool` | Get pool for read operations |
| `for_write` | `ConnectionPool` | Get pool for write operations |
| `use_primary(&block)` | `T` | Force all queries to primary within block |
| `adapter_for(role, type)` | `Adapter` | Create adapter for role |
| `read_adapter(type)` | `Adapter` | Create read adapter |
| `write_adapter(type)` | `Adapter` | Create write adapter |
| `transaction(isolation, type, &block)` | `T` | Execute transaction on primary |
| `stats` | `Hash(String, PoolStats)` | Statistics for all pools |
| `healthy?` | `Bool` | Check if all pools are healthy |
| `close(timeout)` | `Nil` | Close all pools gracefully |
| `primary` | `ConnectionPool` | Primary pool |
| `replicas` | `Array(ConnectionPool)` | Replica pools |
| `has_replicas?` | `Bool` | Check if replicas are configured |

### pool_for

```crystal
def pool_for(role : ConnectionRole) : ConnectionPool
```

Get the connection pool for a specific role.

### for_read

```crystal
def for_read : ConnectionPool
```

Get pool for read operations. Routes to replicas unless:
- No replicas configured
- `use_primary` block is active

### for_write

```crystal
def for_write : ConnectionPool
```

Get pool for write operations. Always returns primary.

### use_primary

```crystal
def use_primary(&block)
```

Force all queries to primary within the block. Use after a write when you need to read your own writes.

### adapter_for

```crystal
def adapter_for(role : ConnectionRole, adapter_type : Symbol = :postgres) : Adapters::Adapter
```

Create a pooled adapter for the given role.

**Adapter types:** `:postgres`, `:mysql`, `:sqlite`

### read_adapter / write_adapter

```crystal
def read_adapter(adapter_type : Symbol = :postgres) : Adapters::Adapter
def write_adapter(adapter_type : Symbol = :postgres) : Adapters::Adapter
```

Convenience methods for creating read/write adapters.

### transaction

```crystal
def transaction(isolation : IsolationLevel? = nil, adapter_type : Symbol = :postgres, &block)
```

Execute a transaction on primary. Forces all reads within the block to use primary.

### stats

```crystal
def stats : Hash(String, PoolStats)
```

Get statistics for all pools. Returns hash with keys `"primary"`, `"replica_0"`, `"replica_1"`, etc.

### healthy?

```crystal
def healthy? : Bool
```

Check if primary and all replicas are healthy.

### close

```crystal
def close(timeout : Time::Span = 30.seconds) : Nil
```

Close primary and all replica pools gracefully.

---

## Example Usage

### Basic Setup

```crystal
require "pg"
require "quo"

# Create pools
primary = Quo::ConnectionPool.new("postgres://primary.db/myapp")
replica1 = Quo::ConnectionPool.new("postgres://replica1.db/myapp")
replica2 = Quo::ConnectionPool.new("postgres://replica2.db/myapp")

# Create database with replicas
db = Quo::Database.new(
  primary: primary,
  replicas: [replica1, replica2],
  replica_strategy: Quo::ReplicaStrategy::RoundRobin
)
```

### Automatic Routing

```crystal
# Reads go to replicas (round-robin)
read_adapter = db.read_adapter(:postgres)
users = UsersRelation.new(read_adapter).active.to_a

# Writes always go to primary
write_adapter = db.write_adapter(:postgres)
Quo::InsertQuery.new(:users, write_adapter)
  .values(name: "New User", email: "user@example.com")
  .execute
```

### Read Your Own Writes

```crystal
# After a write, use_primary ensures reads see the new data
db.use_primary do
  # Insert goes to primary
  Quo::InsertQuery.new(:users, db.write_adapter)
    .values(name: "Jane")
    .execute

  # Read also goes to primary (not replicas)
  user = UsersRelation.new(db.read_adapter)
    .where(users: { name: "Jane" })
    .first
end
```

### Transactions

```crystal
# Transactions always run on primary
db.transaction do |tx|
  Quo::InsertQuery.new(:orders, tx.adapter)
    .values(user_id: 1, total: 100.0)
    .execute

  Quo::UpdateQuery.new(:inventory, tx.adapter)
    .set(stock: Quo.expr(:stock) - 1)
    .execute
end
```

### Monitoring

```crystal
# Check health
if db.healthy?
  puts "All pools healthy"
else
  puts "Database issues detected"
end

# Get detailed stats
db.stats.each do |name, stats|
  puts "#{name}: #{stats.in_use}/#{stats.open_connections} connections"
end
```

### Strategy Selection

```crystal
# Round-robin: even distribution
db = Quo::Database.new(
  primary: primary,
  replicas: replicas,
  replica_strategy: Quo::ReplicaStrategy::RoundRobin
)

# Random: for stateless load balancing
db = Quo::Database.new(
  primary: primary,
  replicas: replicas,
  replica_strategy: Quo::ReplicaStrategy::Random
)

# Least connections: route to least busy replica
db = Quo::Database.new(
  primary: primary,
  replicas: replicas,
  replica_strategy: Quo::ReplicaStrategy::LeastConnections
)
```

---

## Exceptions

### RoutingError

```crystal
class Quo::RoutingError < Exception
```

Raised when routing fails (e.g., no healthy replicas available).
