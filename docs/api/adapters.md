# Adapters API

Adapters handle SQL generation and database execution.

## Adapter Base Class

```crystal
abstract class Quo::Adapters::Adapter
  # Compile query to SQL
  abstract def compile(query : Query) : {String, Array(DB::Any)}

  # Compile COUNT query
  abstract def compile_count(query : Query) : {String, Array(DB::Any)}

  # Quote identifier (table/column name)
  abstract def quote_identifier(name : Symbol) : String

  # Parameter placeholder
  abstract def placeholder(index : Int32) : String

  # Execute query
  abstract def execute(sql : String, params : Array(DB::Any)) : Array(Hash(String, DB::Any))

  # Execute scalar query
  def execute_scalar(sql : String, params : Array(DB::Any), as type : T.class) : T

  # Execute and map to type
  def execute(sql : String, params : Array(DB::Any), as type : T.class) : Array(T)
end
```

---

## Postgres Adapter

### Constructor

```crystal
Quo::Adapters::Postgres.new(connection : DB::Database?)
```

### Properties

```crystal
adapter.connection : DB::Database?
adapter.connection = conn  # Set after initialization
```

### SQL Generation

| Feature | Output |
|---------|--------|
| Quote | `"table"."column"` |
| Placeholder | `$1, $2, $3` |
| ILIKE | `ILIKE` (native) |
| All joins | Supported |

### Example

```crystal
require "pg"

DB.open "postgres://localhost/mydb" do |db|
  adapter = Quo::Adapters::Postgres.new(db)

  results = UsersRelation.new(adapter)
    .where(users: { active: true })
    .to_a
end
```

---

## SQLite Adapter

### Constructor

```crystal
Quo::Adapters::SQLite.new(connection : DB::Database?)
```

### SQL Generation

| Feature | Output |
|---------|--------|
| Quote | `"table"."column"` |
| Placeholder | `?` |
| ILIKE | `LOWER(col) LIKE LOWER(?)` |
| RIGHT JOIN | Error |
| FULL JOIN | Error |

### Example

```crystal
require "sqlite3"

DB.open "sqlite3:./app.db" do |db|
  adapter = Quo::Adapters::SQLite.new(db)

  results = UsersRelation.new(adapter)
    .where(users: { active: true })
    .to_a
end

# In-memory database
DB.open "sqlite3::memory:" do |db|
  adapter = Quo::Adapters::SQLite.new(db)
  # ...
end
```

### Limitations

```crystal
# These raise AdapterError on SQLite:
adapter.right_join(:assoc)
adapter.full_join(:assoc)
# => AdapterError: SQLite does not support RIGHT JOIN
```

---

## Test Adapter

For testing without a database.

### Constructor

```crystal
Quo::Adapters::Test.new
```

### Usage

```crystal
adapter = Quo::Adapters::Test.new

# Get SQL without executing
sql, params = UsersRelation.new(adapter)
  .active
  .to_sql

sql.should contain("active")
params.should eq([true])
```

### Execution

All execution methods raise errors:

```crystal
adapter.to_a       # => AdapterError
adapter.first      # => AdapterError
adapter.count      # => AdapterError
adapter.exists?    # => AdapterError
```

Use `to_sql` for testing SQL generation.

---

## Creating Custom Adapters

Extend `Quo::Adapters::Adapter`:

```crystal
class MyAdapter < Quo::Adapters::Adapter
  def initialize(@connection : DB::Database)
  end

  def compile(query : Query) : {String, Array(DB::Any)}
    params = [] of DB::Any

    sql = String.build do |str|
      str << "SELECT "
      str << compile_select(query)
      str << " FROM "
      str << quote_identifier(query.table)
      # ... compile WHERE, ORDER, etc.
    end

    {sql, params}
  end

  def compile_count(query : Query) : {String, Array(DB::Any)}
    # Similar to compile but SELECT COUNT(*)
  end

  def quote_identifier(name : Symbol) : String
    "`#{name}`"  # MySQL style
  end

  def placeholder(index : Int32) : String
    "?"  # MySQL/SQLite style
  end

  def execute(sql : String, params : Array(DB::Any)) : Array(Hash(String, DB::Any))
    results = [] of Hash(String, DB::Any)
    @connection.query(sql, args: params) do |rs|
      rs.each do
        row = {} of String => DB::Any
        rs.column_count.times do |i|
          row[rs.column_name(i)] = rs.read
        end
        results << row
      end
    end
    results
  end

  def execute_scalar(sql : String, params : Array(DB::Any), as type : T.class) : T forall T
    @connection.query_one(sql, args: params, as: type)
  end
end
```

---

## Adapter Comparison

| Feature | Postgres | SQLite | Test |
|---------|----------|--------|------|
| Connection | Required | Required | None |
| Execution | Yes | Yes | No |
| Placeholders | `$1` | `?` | `$1` |
| ILIKE | Native | LOWER() | N/A |
| RIGHT JOIN | Yes | No | N/A |
| FULL JOIN | Yes | No | N/A |
