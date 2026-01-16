# Adapters

Adapters handle database-specific SQL generation and execution.

## Available Adapters

| Adapter | Database | Pooled | Status |
|---------|----------|--------|--------|
| `Quo::Adapters::Postgres` | PostgreSQL | No | Production |
| `Quo::Adapters::PooledPostgres` | PostgreSQL | Yes | Production |
| `Quo::Adapters::MySQL` | MySQL | No | Production |
| `Quo::Adapters::PooledMySQL` | MySQL | Yes | Production |
| `Quo::Adapters::SQLite` | SQLite | No | Production |
| `Quo::Adapters::PooledSQLite` | SQLite | Yes | Production |
| `Quo::Adapters::Test` | None | No | Testing |

## PostgreSQL Adapter

### Setup

```crystal
require "pg"
require "quo"

DB.open "postgres://user:pass@localhost/mydb" do |db|
  adapter = Quo::Adapters::Postgres.new(db)

  results = UsersRelation.new(adapter).active.to_a
end
```

### Features

- Parameterized queries with `$1, $2, ...` placeholders
- Native `ILIKE` support
- All join types supported
- Full feature set

### Generated SQL Example

```crystal
UsersRelation.new(adapter)
  .where(users: { active: true })
  .where { |e| e[:users][:score] >= 100 }
  .order(users: { created_at: :desc })
  .limit(10)
  .to_sql

# SQL: SELECT "users".* FROM "users"
#      WHERE "users"."active" = $1
#      AND "users"."score" >= $2
#      ORDER BY "users"."created_at" DESC
#      LIMIT $3
# Params: [true, 100, 10]
```

## SQLite Adapter

### Setup

```crystal
require "sqlite3"
require "quo"

DB.open "sqlite3:./myapp.db" do |db|
  adapter = Quo::Adapters::SQLite.new(db)

  results = UsersRelation.new(adapter).active.to_a
end
```

### In-Memory Database

Useful for testing:

```crystal
DB.open "sqlite3::memory:" do |db|
  adapter = Quo::Adapters::SQLite.new(db)
  # ...
end
```

### SQLite Differences

| Feature | PostgreSQL | SQLite |
|---------|------------|--------|
| Placeholders | `$1, $2` | `?` |
| ILIKE | Native | `LOWER(col) LIKE LOWER(?)` |
| RIGHT JOIN | Yes | Not supported |
| FULL JOIN | Yes | Not supported |
| Booleans | Native | 0/1 integers |

### Generated SQL Example

```crystal
UsersRelation.new(sqlite_adapter)
  .where(users: { active: true })
  .where { |e| e[:users][:name].ilike("%john%") }
  .limit(10)
  .to_sql

# SQL: SELECT "users".* FROM "users"
#      WHERE "users"."active" = ?
#      AND LOWER("users"."name") LIKE LOWER(?)
#      LIMIT ?
# Params: [true, "%john%", 10]
```

### SQLite Limitations

```crystal
# RIGHT JOIN raises error
UsersRelation.new(sqlite_adapter)
  .right_join(:profiles)
# => Quo::AdapterError: SQLite does not support RIGHT JOIN.
#    Use LEFT JOIN with reversed tables instead.
```

## MySQL Adapter

### Setup

```crystal
require "mysql"
require "quo"

DB.open "mysql://user:pass@localhost/mydb" do |db|
  adapter = Quo::Adapters::MySQL.new(db)

  results = UsersRelation.new(adapter).active.to_a
end
```

### MySQL Differences

| Feature | PostgreSQL | MySQL |
|---------|------------|-------|
| Placeholders | `$1, $2` | `?` |
| Quote style | `"table"` | `` `table` `` |
| ILIKE | Native | `LOWER(col) LIKE LOWER(?)` |
| RIGHT JOIN | Yes | Yes |
| FULL JOIN | Yes | Not supported |

### Generated SQL Example

```crystal
UsersRelation.new(mysql_adapter)
  .where(users: { active: true })
  .where { |e| e[:users][:name].ilike("%john%") }
  .limit(10)
  .to_sql

# SQL: SELECT `users`.* FROM `users`
#      WHERE `users`.`active` = ?
#      AND LOWER(`users`.`name`) LIKE LOWER(?)
#      LIMIT ? OFFSET ?
# Params: [true, "%john%", 10]
```

### MySQL Limitations

```crystal
# FULL JOIN raises error
UsersRelation.new(mysql_adapter)
  .full_join(:profiles)
# => Quo::AdapterError: MySQL does not support FULL OUTER JOIN.
#    Use UNION of LEFT and RIGHT JOINs instead.
```

## Pooled Adapters

For production use with connection pooling, health checks, and statistics.

### Why Use Pooled Adapters?

**Non-pooled adapters** create a new connection for each query or reuse a single connection:
- Simple setup for scripts and development
- No connection management overhead
- Risk of connection exhaustion under load
- No automatic reconnection after failures

**Pooled adapters** maintain a pool of reusable connections:
- **Performance**: Avoid connection establishment overhead (TCP handshake, auth, etc.)
- **Scalability**: Handle many concurrent requests with bounded connections
- **Reliability**: Automatic reconnection and health checks detect stale connections
- **Observability**: Built-in statistics for monitoring (utilization, timeouts, checkouts)
- **Graceful degradation**: Queue requests when pool is exhausted rather than failing immediately

**When to use pooled adapters:**
- Web applications with concurrent requests
- Background job processors
- Any production workload with sustained database traffic

**When non-pooled adapters are fine:**
- One-off scripts
- Development/testing
- Low-traffic applications with infrequent queries

### Setup with PooledPostgres

```crystal
require "pg"
require "quo"

# Configure pool
pool_config = Quo::PoolConfig.new(
  initial_size: 2,
  max_size: 10,
  checkout_timeout: 5.seconds
)

# Create connection pool
pool = Quo::ConnectionPool.new("postgres://localhost/mydb", pool_config)

# Create pooled adapter
adapter = Quo::Adapters::PooledPostgres.new(pool)

# Use like any other adapter
results = UsersRelation.new(adapter).active.to_a

# Check pool stats
stats = pool.stats
puts "Open connections: #{stats.open_connections}"
puts "In use: #{stats.in_use}"

# Close pool gracefully
pool.close(timeout: 30.seconds)
```

### Available Pooled Adapters

- `Quo::Adapters::PooledPostgres` - PostgreSQL with pooling
- `Quo::Adapters::PooledMySQL` - MySQL with pooling
- `Quo::Adapters::PooledSQLite` - SQLite with pooling

### Benefits of Pooled Adapters

- **Connection reuse** - Avoid connection overhead
- **Automatic logging** - All queries logged via `Quo::Logging`
- **Health checks** - Optional connection validation
- **Statistics** - Monitor pool utilization
- **Graceful shutdown** - Wait for in-flight queries

See [Connection Pooling](/guide/connection-pooling) for detailed configuration.

## Test Adapter

For unit testing without a database connection.

### Setup

```crystal
require "quo"

adapter = Quo::Adapters::Test.new
```

### Usage

```crystal
# Get SQL without executing
sql, params = UsersRelation.new(adapter)
  .active
  .order(users: { name: :asc })
  .to_sql

sql.should contain("WHERE")
sql.should contain("ORDER BY")
params.should eq([true])
```

### Execution Raises Error

```crystal
# to_a, first, count, etc. raise errors
UsersRelation.new(adapter).active.to_a
# => Quo::AdapterError: TestAdapter does not support query execution.
#    Use to_sql for SQL generation tests.
```

## Creating a Custom Adapter

Extend `Quo::Adapters::Adapter`:

```crystal
class MyCustomAdapter < Quo::Adapters::Adapter
  def initialize(@connection : DB::Database)
  end

  # Required: Compile query to SQL
  def compile(query : Query) : {String, Array(DB::Any)}
    # Generate SQL and params
  end

  # Required: Compile count query
  def compile_count(query : Query) : {String, Array(DB::Any)}
    # Generate COUNT SQL
  end

  # Required: Quote identifier
  def quote_identifier(name : Symbol) : String
    # e.g., "\"#{name}\"" or "`#{name}`"
  end

  # Required: Parameter placeholder
  def placeholder(index : Int32) : String
    # e.g., "$#{index}" or "?"
  end

  # Required: Execute query
  def execute(sql : String, params : Array(DB::Any)) : Array(Hash(String, DB::Any))
    # Execute and return results
  end
end
```

## Adapter Selection Pattern

```crystal
module MyApp
  def self.adapter : Quo::Adapters::Adapter
    @@adapter ||= begin
      case ENV["DATABASE_URL"]?
      when /^postgres/
        db = DB.open(ENV["DATABASE_URL"])
        Quo::Adapters::Postgres.new(db)
      when /^mysql/
        db = DB.open(ENV["DATABASE_URL"])
        Quo::Adapters::MySQL.new(db)
      when /^sqlite/
        db = DB.open(ENV["DATABASE_URL"])
        Quo::Adapters::SQLite.new(db)
      else
        raise "Unknown database type"
      end
    end
  end
end

# Usage
results = UsersRelation.new(MyApp.adapter).active.to_a
```

## Adapter Comparison

| Feature | Postgres | MySQL | SQLite | Test |
|---------|----------|-------|--------|------|
| Placeholders | `$1` | `?` | `?` | `$1` |
| Quote style | `"col"` | `` `col` `` | `"col"` | `"col"` |
| ILIKE | Native | LOWER() | LOWER() | N/A |
| RIGHT JOIN | Yes | Yes | No | N/A |
| FULL JOIN | Yes | No | No | N/A |
| Pooled version | Yes | Yes | Yes | No |
