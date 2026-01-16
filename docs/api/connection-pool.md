# Connection Pool API

Connection pooling infrastructure for database connections.

## PoolConfig

Configuration for connection pool behavior.

```crystal
struct Quo::PoolConfig
  # Initial number of connections to create
  getter initial_size : Int32

  # Maximum connections in pool (0 = unlimited)
  getter max_size : Int32

  # Maximum idle connections to keep
  getter max_idle : Int32

  # Timeout for checkout operation
  getter checkout_timeout : Time::Span

  # Number of retry attempts on connection failure
  getter retry_attempts : Int32

  # Delay between retry attempts
  getter retry_delay : Time::Span

  # Interval for health checks (nil = disabled)
  getter health_check_interval : Time::Span?
end
```

### Constructor

```crystal
Quo::PoolConfig.new(
  initial_size : Int32 = 1,
  max_size : Int32 = 10,
  max_idle : Int32 = 5,
  checkout_timeout : Time::Span = 5.seconds,
  retry_attempts : Int32 = 3,
  retry_delay : Time::Span = 200.milliseconds,
  health_check_interval : Time::Span? = nil
)
```

### Methods

| Method | Return | Description |
|--------|--------|-------------|
| `to_db_pool_options` | `DB::Pool::Options` | Convert to Crystal DB pool options |

### Example

```crystal
config = Quo::PoolConfig.new(
  initial_size: 2,
  max_size: 20,
  max_idle: 10,
  checkout_timeout: 10.seconds,
  retry_attempts: 5,
  health_check_interval: 30.seconds
)
```

---

## PoolStats

Statistics about pool state and usage.

```crystal
struct Quo::PoolStats
  # Total open connections
  getter open_connections : Int32

  # Idle connections available for checkout
  getter idle_connections : Int32

  # Connections currently in use
  getter in_use : Int32

  # Maximum configured connections
  getter max_connections : Int32

  # Total checkouts performed
  getter total_checkouts : Int64

  # Total checkout timeouts
  getter total_timeouts : Int64

  # Total health check failures
  getter health_check_failures : Int64
end
```

### Methods

| Method | Return | Description |
|--------|--------|-------------|
| `utilization` | `Float64` | Utilization percentage (in_use / open_connections) |

### Example

```crystal
stats = pool.stats

puts "Open: #{stats.open_connections}"
puts "In use: #{stats.in_use}"
puts "Utilization: #{(stats.utilization * 100).round(1)}%"
puts "Total checkouts: #{stats.total_checkouts}"
puts "Timeouts: #{stats.total_timeouts}"
```

---

## ConnectionPool

Connection pool wrapping `DB::Database` with health checks and statistics.

```crystal
class Quo::ConnectionPool
  def initialize(uri : String, config : PoolConfig = PoolConfig.new)
  def initialize(db : DB::Database, config : PoolConfig = PoolConfig.new)
end
```

### Constructor

| Parameter | Type | Description |
|-----------|------|-------------|
| `uri` | `String` | Database connection URI |
| `db` | `DB::Database` | Existing database connection |
| `config` | `PoolConfig` | Pool configuration |

### Methods

| Method | Return | Description |
|--------|--------|-------------|
| `checkout(&block)` | `Nil` | Checkout connection and execute block |
| `checkout_with_health_check(&block)` | `Nil` | Checkout with health check before use |
| `query(sql, *args, &block)` | `Nil` | Execute query with block |
| `exec(sql, *args)` | `DB::ExecResult` | Execute statement |
| `stats` | `PoolStats` | Current pool statistics |
| `healthy?` | `Bool` | Check if pool has available connections |
| `close(timeout)` | `Bool` | Close pool gracefully |
| `closed?` | `Bool` | Check if pool is closed |
| `database` | `DB::Database` | Access underlying database |
| `config` | `PoolConfig` | Pool configuration |

### checkout

```crystal
def checkout(&block : DB::Connection ->) : Nil
```

Checkout a connection and execute block. Connection is automatically released when block completes.

**Raises:**
- `ConnectionError` if pool is closed
- `PoolTimeoutError` if checkout times out

### checkout_with_health_check

```crystal
def checkout_with_health_check(&block : DB::Connection ->) : Nil
```

Same as `checkout` but performs health check (`SELECT 1`) before yielding connection.

**Raises:**
- `ConnectionError` if health check fails

### query

```crystal
def query(sql : String, *args, **kwargs, &block : DB::ResultSet ->) : Nil
```

Execute a query and process results with block.

### exec

```crystal
def exec(sql : String, *args, **kwargs) : DB::ExecResult
```

Execute a statement that doesn't return results.

### stats

```crystal
def stats : PoolStats
```

Get current pool statistics including connection counts, checkouts, and failures.

### healthy?

```crystal
def healthy? : Bool
```

Check if pool is healthy (has available connections or room to grow).

### close

```crystal
def close(timeout : Time::Span = 30.seconds) : Bool
```

Close the pool gracefully. Waits for in-use connections to be released up to timeout.

---

## Example Usage

### Basic Pool

```crystal
require "pg"
require "quo"

# Create pool with default config
pool = Quo::ConnectionPool.new("postgres://localhost/mydb")

# Execute query
pool.query("SELECT * FROM users WHERE active = $1", true) do |rs|
  rs.each do
    puts rs.read(String)
  end
end

# Check stats
puts pool.stats.open_connections

# Close gracefully
pool.close
```

### Custom Configuration

```crystal
config = Quo::PoolConfig.new(
  initial_size: 5,
  max_size: 50,
  max_idle: 25,
  checkout_timeout: 10.seconds,
  health_check_interval: 1.minute
)

pool = Quo::ConnectionPool.new("postgres://localhost/mydb", config)
```

### With Pooled Adapter

```crystal
pool = Quo::ConnectionPool.new("postgres://localhost/mydb", config)
adapter = Quo::Adapters::PooledPostgres.new(pool)

# Use adapter normally
results = UsersRelation.new(adapter).active.to_a
```

### Health Monitoring

```crystal
# Check pool health
unless pool.healthy?
  puts "Pool is unhealthy!"
end

# Monitor statistics
stats = pool.stats
if stats.utilization > 0.9
  puts "Pool utilization high: #{(stats.utilization * 100).round(1)}%"
end

if stats.total_timeouts > 0
  puts "Warning: #{stats.total_timeouts} checkout timeouts"
end
```

---

## Exceptions

### ConnectionError

```crystal
class Quo::ConnectionError < Exception
```

Raised when a connection operation fails.

### PoolTimeoutError

```crystal
class Quo::PoolTimeoutError < Exception
  getter timeout : Time::Span
end
```

Raised when checkout operation times out.

```crystal
begin
  pool.checkout do |conn|
    # ...
  end
rescue ex : Quo::PoolTimeoutError
  puts "Checkout timed out after #{ex.timeout}"
end
```
