# Schema Introspection

Quo can read database schema information at runtime, including tables, columns, indexes, and foreign keys. This is useful for:

- Schema validation and migration checks
- Generating Crystal code from existing databases
- Database documentation
- Dynamic query building

## Available Introspectors

| Introspector | Database |
|--------------|----------|
| `Quo::Introspection::PostgresIntrospector` | PostgreSQL |
| `Quo::Introspection::MySQLIntrospector` | MySQL |
| `Quo::Introspection::SQLiteIntrospector` | SQLite |

## Basic Setup

```crystal
require "pg"
require "quo"

# Create a connection pool
pool = Quo::ConnectionPool.new("postgres://localhost/mydb", config)

# Create the introspector
introspector = Quo::Introspection::PostgresIntrospector.new(pool)
```

## Listing Tables

```crystal
# Get all table names
tables = introspector.tables

tables.each do |table_name|
  puts table_name
end
# => users
# => orders
# => products
```

## Introspecting a Table

Get complete information about a table:

```crystal
if table = introspector.table("users")
  puts "Table: #{table.name}"
  puts "Primary Key: #{table.primary_key_columns.join(", ")}"
  puts "Columns: #{table.columns.size}"
  puts "Indexes: #{table.indexes.size}"
  puts "Foreign Keys: #{table.foreign_keys.size}"
end
```

### IntrospectedTable Properties

| Property | Type | Description |
|----------|------|-------------|
| `name` | String | Table name |
| `columns` | Array(IntrospectedColumn) | Column definitions |
| `indexes` | Array(IntrospectedIndex) | Index definitions |
| `foreign_keys` | Array(ForeignKey) | Foreign key constraints |
| `primary_key_columns` | Array(String) | Primary key column names |

### Finding a Column

```crystal
if table = introspector.table("users")
  if email_col = table.column("email")
    puts "Email column type: #{email_col.data_type}"
    puts "Nullable: #{email_col.nullable?}"
  end
end
```

## Introspecting Columns

```crystal
columns = introspector.columns("users")

columns.each do |col|
  puts "#{col.name}: #{col.data_type}"
  puts "  Nullable: #{col.nullable?}"
  puts "  Default: #{col.default_value || "none"}"
  puts "  Primary Key: #{col.primary_key?}"
end
```

### IntrospectedColumn Properties

| Property | Type | Description |
|----------|------|-------------|
| `name` | String | Column name |
| `data_type` | String | Database type (e.g., "integer", "varchar") |
| `nullable?` | Bool | Whether column allows NULL |
| `default_value` | String? | Default value expression |
| `ordinal_position` | Int32 | Column order (1-based) |
| `primary_key?` | Bool | Whether column is part of primary key |

## Introspecting Indexes

```crystal
indexes = introspector.indexes("users")

indexes.each do |idx|
  puts "#{idx.name}"
  puts "  Columns: #{idx.columns.join(", ")}"
  puts "  Unique: #{idx.unique?}"
  puts "  Primary: #{idx.primary?}"
  puts "  Type: #{idx.index_type || "btree"}"
end
```

### IntrospectedIndex Properties

| Property | Type | Description |
|----------|------|-------------|
| `name` | String | Index name |
| `table_name` | String | Table the index belongs to |
| `columns` | Array(String) | Indexed column names |
| `unique?` | Bool | Whether index enforces uniqueness |
| `primary?` | Bool | Whether this is the primary key index |
| `index_type` | String? | Index type (btree, hash, gin, etc.) |

## Introspecting Foreign Keys

```crystal
foreign_keys = introspector.foreign_keys("orders")

foreign_keys.each do |fk|
  puts "#{fk.name}"
  puts "  #{fk.table_name}.#{fk.column_name}"
  puts "  -> #{fk.referenced_table}.#{fk.referenced_column}"
  puts "  ON DELETE: #{fk.on_delete || "NO ACTION"}"
  puts "  ON UPDATE: #{fk.on_update || "NO ACTION"}"
end
```

### ForeignKey Properties

| Property | Type | Description |
|----------|------|-------------|
| `name` | String | Constraint name |
| `table_name` | String | Table with the foreign key |
| `column_name` | String | Column with the foreign key |
| `referenced_table` | String | Referenced table |
| `referenced_column` | String | Referenced column |
| `on_delete` | String? | ON DELETE action (CASCADE, SET NULL, etc.) |
| `on_update` | String? | ON UPDATE action |

## Database-Specific Notes

### PostgreSQL

Uses `information_schema` and `pg_*` system catalogs:

```crystal
introspector = Quo::Introspection::PostgresIntrospector.new(pool)

# Reads from:
# - information_schema.tables
# - information_schema.columns
# - pg_index, pg_class, pg_attribute (for indexes)
# - information_schema.table_constraints (for foreign keys)
```

### MySQL

Uses `information_schema`:

```crystal
introspector = Quo::Introspection::MySQLIntrospector.new(pool)

# Reads from:
# - information_schema.tables
# - information_schema.columns
# - information_schema.statistics (for indexes)
# - information_schema.key_column_usage (for foreign keys)
```

### SQLite

Uses PRAGMA commands:

```crystal
introspector = Quo::Introspection::SQLiteIntrospector.new(pool)

# Uses:
# - PRAGMA table_list
# - PRAGMA table_info(table)
# - PRAGMA index_list(table)
# - PRAGMA index_info(index)
# - PRAGMA foreign_key_list(table)
```

## Use Cases

### Schema Validation

Verify your schema matches expectations:

```crystal
def validate_users_table(introspector)
  table = introspector.table("users")
  raise "users table not found" unless table

  # Check required columns exist
  %w[id email name created_at].each do |col_name|
    unless table.column(col_name)
      raise "Missing column: #{col_name}"
    end
  end

  # Check primary key
  unless table.primary_key_columns == ["id"]
    raise "Expected id as primary key"
  end

  puts "users table validated successfully"
end
```

### Generate Crystal Code

Create Quo::Relation definitions from database:

```crystal
def generate_relation(introspector, table_name : String)
  table = introspector.table(table_name)
  return unless table

  class_name = table_name.camelcase + "Relation"

  puts "class #{class_name} < Quo::Relation"
  puts "  schema :#{table_name} do"

  table.columns.each do |col|
    crystal_type = crystal_type_for(col.data_type)

    if col.primary_key?
      puts "    primary_key :#{col.name}, #{crystal_type}"
    else
      puts "    column :#{col.name}, #{crystal_type}"
    end
  end

  puts "  end"
  puts "end"
end

def crystal_type_for(db_type : String) : String
  case db_type.downcase
  when /^(big)?int/, /^(big)?serial/ then "Int64"
  when /^int/, /^serial/             then "Int32"
  when /^bool/                       then "Bool"
  when /^(varchar|text|char)/        then "String"
  when /^timestamp/, /^date/         then "Time"
  when /^numeric/, /^decimal/        then "Float64"
  when /^uuid/                       then "UUID"
  else                                    "String"
  end
end
```

### Database Documentation

Generate schema documentation:

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

Check migrations were applied correctly:

```crystal
def verify_migration(introspector, expected_columns : Hash(String, String))
  table = introspector.table("users")
  raise "Table not found" unless table

  expected_columns.each do |name, expected_type|
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

## Example: Full Introspection Script

See `examples/example_introspection_pg.cr` for a complete example demonstrating all introspection features.

```crystal
# Run with:
crystal run examples/example_introspection_pg.cr
```
