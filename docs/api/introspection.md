# Introspection API

Schema introspection for reading database metadata at runtime.

## IntrospectedColumn

Represents a database column.

```crystal
struct Quo::Introspection::IntrospectedColumn
  getter name : String              # Column name
  getter data_type : String         # Database type (e.g., "varchar(255)")
  getter nullable : Bool            # Whether NULL is allowed
  getter default_value : String?    # Default value expression
  getter primary_key : Bool         # Whether part of primary key
  getter ordinal_position : Int32   # Column position (1-based)
end
```

### Constructor

```crystal
IntrospectedColumn.new(
  name : String,
  data_type : String,
  nullable : Bool = true,
  default_value : String? = nil,
  primary_key : Bool = false,
  ordinal_position : Int32 = 0
)
```

### Methods

| Method | Return | Description |
|--------|--------|-------------|
| `nullable?` | `Bool` | Check if column allows NULL |
| `primary_key?` | `Bool` | Check if column is primary key |
| `has_default?` | `Bool` | Check if column has default value |
| `crystal_type` | `String` | Map database type to Crystal type |

### crystal_type Mapping

| Database Type | Crystal Type |
|---------------|--------------|
| `tinyint`, `smallint` | `Int32` |
| `int`, `integer`, `bigint` | `Int64` |
| `decimal`, `numeric`, `money` | `Float64` |
| `float`, `real`, `double` | `Float64` |
| `bool`, `boolean` | `Bool` |
| `char`, `varchar`, `text` | `String` |
| `uuid` | `UUID` |
| `date`, `time`, `timestamp`, `datetime` | `Time` |
| `json`, `jsonb` | `JSON::Any` |
| `bytea`, `blob`, `binary` | `Bytes` |
| Other | `DB::Any` |

---

## IntrospectedIndex

Represents a database index.

```crystal
struct Quo::Introspection::IntrospectedIndex
  getter name : String           # Index name
  getter table_name : String     # Table the index belongs to
  getter columns : Array(String) # Indexed columns (in order)
  getter unique : Bool           # Whether index enforces uniqueness
  getter primary : Bool          # Whether this is the primary key index
  getter index_type : String?    # Index type (btree, hash, gin, etc.)
end
```

### Constructor

```crystal
IntrospectedIndex.new(
  name : String,
  table_name : String,
  columns : Array(String),
  unique : Bool = false,
  primary : Bool = false,
  index_type : String? = nil
)
```

### Methods

| Method | Return | Description |
|--------|--------|-------------|
| `unique?` | `Bool` | Check if index enforces uniqueness |
| `primary?` | `Bool` | Check if this is primary key index |
| `single_column?` | `Bool` | Check if index has one column |
| `composite?` | `Bool` | Check if index has multiple columns |

---

## ForeignKey

Represents a foreign key constraint.

```crystal
struct Quo::Introspection::ForeignKey
  getter name : String             # Constraint name
  getter table_name : String       # Source table
  getter column_name : String      # Source column
  getter referenced_table : String # Referenced table
  getter referenced_column : String # Referenced column
  getter on_delete : String?       # ON DELETE action
  getter on_update : String?       # ON UPDATE action
end
```

### Constructor

```crystal
ForeignKey.new(
  name : String,
  table_name : String,
  column_name : String,
  referenced_table : String,
  referenced_column : String,
  on_delete : String? = nil,
  on_update : String? = nil
)
```

### Methods

| Method | Return | Description |
|--------|--------|-------------|
| `cascades_delete?` | `Bool` | Check if ON DELETE CASCADE |
| `nullifies_on_delete?` | `Bool` | Check if ON DELETE SET NULL |

---

## IntrospectedTable

Complete table information.

```crystal
struct Quo::Introspection::IntrospectedTable
  getter name : String                            # Table name
  getter columns : Array(IntrospectedColumn)      # All columns
  getter indexes : Array(IntrospectedIndex)       # All indexes
  getter foreign_keys : Array(ForeignKey)         # All foreign keys
  getter primary_key_columns : Array(String)      # Primary key column names
end
```

### Constructor

```crystal
IntrospectedTable.new(
  name : String,
  columns : Array(IntrospectedColumn) = [] of IntrospectedColumn,
  indexes : Array(IntrospectedIndex) = [] of IntrospectedIndex,
  foreign_keys : Array(ForeignKey) = [] of ForeignKey,
  primary_key_columns : Array(String) = [] of String
)
```

### Methods

| Method | Return | Description |
|--------|--------|-------------|
| `column(name)` | `IntrospectedColumn?` | Get column by name |
| `has_column?(name)` | `Bool` | Check if column exists |
| `index(name)` | `IntrospectedIndex?` | Get index by name |
| `foreign_key(name)` | `ForeignKey?` | Get foreign key by name |
| `foreign_keys_for(column)` | `Array(ForeignKey)` | Get FKs for a column |
| `has_primary_key?` | `Bool` | Check if table has primary key |
| `composite_primary_key?` | `Bool` | Check if PK has multiple columns |
| `column_names` | `Array(String)` | Get all column names |

---

## Introspector

Abstract interface for database introspection.

```crystal
abstract class Quo::Introspection::Introspector
  # List all table names
  abstract def tables : Array(String)

  # Get full table information
  abstract def table(name : String) : IntrospectedTable?

  # Get columns for a table
  abstract def columns(table_name : String) : Array(IntrospectedColumn)

  # Get indexes for a table
  abstract def indexes(table_name : String) : Array(IntrospectedIndex)

  # Get foreign keys for a table
  abstract def foreign_keys(table_name : String) : Array(ForeignKey)
end
```

### Built-in Methods

| Method | Return | Description |
|--------|--------|-------------|
| `table_exists?(name)` | `Bool` | Check if table exists |
| `column_exists?(table, column)` | `Bool` | Check if column exists |

---

## PostgresIntrospector

PostgreSQL schema introspector.

```crystal
class Quo::Introspection::PostgresIntrospector < Introspector
  def initialize(pool : ConnectionPool)
end
```

Uses `information_schema` and `pg_*` system catalogs.

---

## MySQLIntrospector

MySQL schema introspector.

```crystal
class Quo::Introspection::MySQLIntrospector < Introspector
  def initialize(pool : ConnectionPool)
end
```

Uses `information_schema` tables.

---

## SQLiteIntrospector

SQLite schema introspector.

```crystal
class Quo::Introspection::SQLiteIntrospector < Introspector
  def initialize(pool : ConnectionPool)
end
```

Uses PRAGMA commands:
- `PRAGMA table_list`
- `PRAGMA table_info(table)`
- `PRAGMA index_list(table)`
- `PRAGMA index_info(index)`
- `PRAGMA foreign_key_list(table)`

---

## Example Usage

### Basic Introspection

```crystal
require "pg"
require "quo"

pool = Quo::ConnectionPool.new("postgres://localhost/mydb")
introspector = Quo::Introspection::PostgresIntrospector.new(pool)

# List all tables
tables = introspector.tables
puts "Tables: #{tables.join(", ")}"

# Check if table exists
if introspector.table_exists?("users")
  puts "users table exists"
end
```

### Table Details

```crystal
if table = introspector.table("users")
  puts "Table: #{table.name}"
  puts "Primary Key: #{table.primary_key_columns.join(", ")}"
  puts "Columns: #{table.columns.size}"
  puts "Indexes: #{table.indexes.size}"
  puts "Foreign Keys: #{table.foreign_keys.size}"
end
```

### Column Inspection

```crystal
columns = introspector.columns("users")

columns.each do |col|
  puts "#{col.name}: #{col.data_type}"
  puts "  Nullable: #{col.nullable?}"
  puts "  Default: #{col.default_value || "none"}"
  puts "  Primary Key: #{col.primary_key?}"
  puts "  Crystal Type: #{col.crystal_type}"
end
```

### Index Inspection

```crystal
indexes = introspector.indexes("users")

indexes.each do |idx|
  type = idx.unique? ? "UNIQUE " : ""
  puts "#{type}INDEX #{idx.name}"
  puts "  Columns: #{idx.columns.join(", ")}"
  puts "  Type: #{idx.index_type || "btree"}"
end
```

### Foreign Key Inspection

```crystal
foreign_keys = introspector.foreign_keys("orders")

foreign_keys.each do |fk|
  puts "#{fk.name}"
  puts "  #{fk.table_name}.#{fk.column_name}"
  puts "  -> #{fk.referenced_table}.#{fk.referenced_column}"
  puts "  ON DELETE: #{fk.on_delete || "NO ACTION"}"
end
```

### Schema Validation

```crystal
def validate_schema(introspector)
  table = introspector.table("users")
  raise "users table not found" unless table

  # Verify required columns
  %w[id email name created_at].each do |col_name|
    unless table.column(col_name)
      raise "Missing column: #{col_name}"
    end
  end

  # Verify primary key
  unless table.primary_key_columns == ["id"]
    raise "Expected id as primary key"
  end

  # Verify indexes
  unless table.indexes.any? { |i| i.columns == ["email"] && i.unique? }
    raise "Missing unique index on email"
  end

  puts "Schema validation passed"
end
```

### Code Generation

```crystal
def generate_relation(introspector, table_name : String)
  table = introspector.table(table_name)
  return unless table

  class_name = table_name.camelcase + "Relation"

  puts "class #{class_name} < Quo::Relation"
  puts "  schema :#{table_name} do"

  table.columns.each do |col|
    crystal_type = col.crystal_type
    if col.nullable? && !col.primary_key?
      crystal_type += "?"
    end

    if col.primary_key?
      puts "    primary_key :#{col.name}, #{crystal_type}"
    else
      puts "    column :#{col.name}, #{crystal_type}"
    end
  end

  puts "  end"
  puts "end"
end

# Usage
generate_relation(introspector, "users")
# Output:
# class UsersRelation < Quo::Relation
#   schema :users do
#     primary_key :id, Int64
#     column :email, String
#     column :name, String?
#     column :created_at, Time
#   end
# end
```

### Database Documentation

```crystal
def document_database(introspector)
  puts "# Database Schema\n"

  introspector.tables.sort.each do |table_name|
    table = introspector.table(table_name)
    next unless table

    puts "## #{table_name}\n"
    puts "Primary Key: #{table.primary_key_columns.join(", ")}\n"

    puts "\n### Columns\n"
    puts "| Name | Type | Nullable | Default |"
    puts "|------|------|----------|---------|"
    table.columns.each do |col|
      nullable = col.nullable? ? "Yes" : "No"
      default = col.default_value || "-"
      puts "| #{col.name} | #{col.data_type} | #{nullable} | #{default} |"
    end

    unless table.indexes.empty?
      puts "\n### Indexes\n"
      table.indexes.each do |idx|
        unique = idx.unique? ? "UNIQUE " : ""
        puts "- #{unique}#{idx.name}: (#{idx.columns.join(", ")})"
      end
    end

    unless table.foreign_keys.empty?
      puts "\n### Foreign Keys\n"
      table.foreign_keys.each do |fk|
        puts "- #{fk.column_name} -> #{fk.referenced_table}.#{fk.referenced_column}"
      end
    end

    puts ""
  end
end
```

### Migration Verification

```crystal
def verify_migration(introspector, expected : Hash(String, String))
  table = introspector.table("users")
  raise "Table not found" unless table

  expected.each do |name, expected_type|
    col = table.column(name)
    unless col
      puts "MISSING: #{name}"
      next
    end

    if col.data_type.downcase.includes?(expected_type.downcase)
      puts "OK: #{name} (#{col.data_type})"
    else
      puts "MISMATCH: #{name} - expected #{expected_type}, got #{col.data_type}"
    end
  end
end

# Usage
verify_migration(introspector, {
  "id"         => "bigint",
  "email"      => "varchar",
  "active"     => "boolean",
  "created_at" => "timestamp",
})
```

---

## Database-Specific Notes

### PostgreSQL

- Reads from `information_schema` and `pg_*` catalogs
- Full support for all column types
- Index types: btree, hash, gin, gist, etc.

### MySQL

- Reads from `information_schema`
- Uses current database by default

### SQLite

- Uses PRAGMA commands
- Limited type information (SQLite is dynamically typed)
- No index type information
