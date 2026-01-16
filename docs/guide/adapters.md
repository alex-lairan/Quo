# Adapters

Adapters handle database-specific SQL generation and execution.

## Available Adapters

| Adapter | Database | Status |
|---------|----------|--------|
| `Quo::Adapters::Postgres` | PostgreSQL | Production |
| `Quo::Adapters::SQLite` | SQLite | Production |
| `Quo::Adapters::Test` | None | Testing |

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
