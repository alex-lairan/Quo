# Connection Pooling

Quo provides connection pooling through the `ConnectionPool` class, which wraps Crystal's built-in `DB::Pool` with additional features like health checks, statistics, and graceful shutdown.

## Basic Setup

```crystal
require "pg"
require "quo"

# Configure the pool
config = Quo::PoolConfig.new(
  initial_size: 2,      # Start with 2 connections
  max_size: 10,         # Allow up to 10 connections
  checkout_timeout: 5.seconds
)

# Create the pool
pool = Quo::ConnectionPool.new("postgres://localhost/mydb", config)

# Create a pooled adapter
adapter = Quo::Adapters::PooledPostgres.new(pool)

# Use the adapter
results = UsersRelation.new(adapter).active.to_a

# Close when done
pool.close
```

## Pool Configuration

### PoolConfig Options

```crystal
Quo::PoolConfig.new(
  initial_size: 1,              # Initial connections (default: 1)
  max_size: 10,                 # Maximum connections (default: 10)
  max_idle: 5,                  # Maximum idle connections (default: 5)
  checkout_timeout: 5.seconds,  # Timeout waiting for connection (default: 5s)
  retry_attempts: 3,            # Retry attempts on failure (default: 3)
  retry_delay: 200.milliseconds, # Delay between retries (default: 200ms)
  health_check_interval: nil    # Optional health check interval
)
```

### Configuration Examples

**Development** - Minimal connections:

```crystal
dev_config = Quo::PoolConfig.new(
  initial_size: 1,
  max_size: 5
)
```

**Production** - More connections, health checks:

```crystal
prod_config = Quo::PoolConfig.new(
  initial_size: 5,
  max_size: 25,
  max_idle: 10,
  checkout_timeout: 10.seconds,
  health_check_interval: 30.seconds
)
```

**High-throughput** - Many connections, fast checkout:

```crystal
high_throughput_config = Quo::PoolConfig.new(
  initial_size: 10,
  max_size: 50,
  max_idle: 20,
  checkout_timeout: 2.seconds,
  retry_attempts: 5
)
```

## Pool Statistics

Monitor pool health and utilization:

```crystal
stats = pool.stats

puts "Open connections: #{stats.open_connections}"
puts "Idle connections: #{stats.idle_connections}"
puts "In use: #{stats.in_use}"
puts "Max connections: #{stats.max_connections}"
puts "Total checkouts: #{stats.total_checkouts}"
puts "Total timeouts: #{stats.total_timeouts}"
puts "Utilization: #{(stats.utilization * 100).round(1)}%"
```

### PoolStats Properties

| Property | Type | Description |
|----------|------|-------------|
| `open_connections` | Int32 | Currently open connections |
| `idle_connections` | Int32 | Connections available for checkout |
| `in_use` | Int32 | Connections currently in use |
| `max_connections` | Int32 | Maximum pool size |
| `total_checkouts` | Int64 | Total successful checkouts |
| `total_timeouts` | Int64 | Total checkout timeouts |
| `health_check_failures` | Int64 | Failed health checks |
| `utilization` | Float64 | in_use / open_connections (0.0 to 1.0) |

## Direct Pool Usage

For advanced use cases, use the pool directly:

```crystal
pool = Quo::ConnectionPool.new(url, config)

# Checkout a connection (automatically returned after block)
pool.checkout do |conn|
  conn.query("SELECT * FROM users") do |rs|
    rs.each { |row| puts row }
  end
end
```

## Health Checks

Enable periodic health checks to detect and remove stale connections:

```crystal
config = Quo::PoolConfig.new(
  health_check_interval: 30.seconds
)

pool = Quo::ConnectionPool.new(url, config)

# Check if pool is healthy
if pool.healthy?
  puts "Pool is healthy"
else
  puts "Pool has issues"
end
```

## Graceful Shutdown

Close the pool gracefully, waiting for in-flight queries:

```crystal
# Wait up to 30 seconds for queries to complete
success = pool.close(timeout: 30.seconds)

if success
  puts "Pool closed gracefully"
else
  puts "Some connections were forcefully closed"
end
```

## Error Handling

### Connection Timeout

```crystal
begin
  results = UsersRelation.new(adapter).active.to_a
rescue Quo::PoolTimeoutError
  puts "Could not get a connection from the pool"
end
```

### Connection Errors

```crystal
begin
  pool = Quo::ConnectionPool.new("postgres://invalid-host/db", config)
rescue Quo::ConnectionError => e
  puts "Failed to connect: #{e.message}"
end
```

## Database-Specific Pools

### PostgreSQL

```crystal
require "pg"

pool = Quo::ConnectionPool.new("postgres://localhost/mydb", config)
adapter = Quo::Adapters::PooledPostgres.new(pool)
```

### MySQL

```crystal
require "mysql"

pool = Quo::ConnectionPool.new("mysql://localhost/mydb", config)
adapter = Quo::Adapters::PooledMySQL.new(pool)
```

### SQLite

```crystal
require "sqlite3"

pool = Quo::ConnectionPool.new("sqlite3:./mydb.db", config)
adapter = Quo::Adapters::PooledSQLite.new(pool)
```

## Integration with Multi-Database

For primary/replica setups, see [Multi-Database](/guide/multi-database):

```crystal
primary_pool = Quo::ConnectionPool.new(primary_url, config)
replica_pool = Quo::ConnectionPool.new(replica_url, config)

db = Quo::Database.new(
  primary: primary_pool,
  replicas: [replica_pool]
)
```

## Best Practices

### 1. Size your pool appropriately

- Start with `max_size` = number of application threads/fibers that make DB calls
- Monitor utilization and adjust

### 2. Set reasonable timeouts

- `checkout_timeout` should be shorter than your request timeout
- Fail fast rather than hang

### 3. Use health checks in production

- Detect dead connections before they cause errors
- Set interval based on connection timeout settings

### 4. Close pools on shutdown

- Always call `pool.close` when your application exits
- Use signal handlers for graceful shutdown

### 5. Monitor pool statistics

- Track utilization over time
- Alert on high timeout rates

## Example: Web Application

```crystal
# config/database.cr
module MyApp
  class_getter pool : Quo::ConnectionPool do
    config = Quo::PoolConfig.new(
      initial_size: ENV["DB_POOL_MIN"]?.try(&.to_i) || 5,
      max_size: ENV["DB_POOL_MAX"]?.try(&.to_i) || 25,
      checkout_timeout: 5.seconds,
      health_check_interval: 30.seconds
    )

    Quo::ConnectionPool.new(ENV["DATABASE_URL"], config)
  end

  class_getter adapter : Quo::Adapters::PooledPostgres do
    Quo::Adapters::PooledPostgres.new(pool)
  end

  def self.close
    pool.close(timeout: 30.seconds)
  end
end

# Graceful shutdown
Signal::INT.trap { MyApp.close; exit }
Signal::TERM.trap { MyApp.close; exit }

# Usage in handlers
get "/users" do
  UsersRelation.new(MyApp.adapter).active.to_a.to_json
end
```
