# PostgreSQL Schema Introspection Example
# Demonstrates: Reading database schema, tables, columns, indexes, and foreign keys
#
# Setup:
#   createdb quo_demo
#   psql -d quo_demo -f examples/setup_pg.sql
#
# Run:
#   crystal run examples/example_introspection_pg.cr

require "pg"
require "../src/quo"

# Connect to PostgreSQL
DB_URL = ENV["DATABASE_URL"]? || "postgres://localhost/quo_demo"
db = DB.open(DB_URL)

# Create a connection pool for introspection
pool_config = Quo::PoolConfig.new(
  initial_size: 1,
  max_size: 5
)
pool = Quo::ConnectionPool.new(DB_URL, pool_config)

# Create the introspector
introspector = Quo::Introspection::PostgresIntrospector.new(pool)

puts "=" * 70
puts "Quo Schema Introspection - PostgreSQL"
puts "=" * 70

# =============================================================================
# 1. LIST ALL TABLES
# =============================================================================

puts "\n" + "=" * 70
puts "1. LIST ALL TABLES"
puts "=" * 70

tables = introspector.tables
puts "\nFound #{tables.size} tables:"
tables.each do |table|
  puts "  - #{table}"
end

# =============================================================================
# 2. INTROSPECT A SPECIFIC TABLE
# =============================================================================

puts "\n" + "=" * 70
puts "2. INTROSPECT USERS TABLE"
puts "=" * 70

if users_table = introspector.table("users")
  puts "\nTable: #{users_table.name}"
  puts "Primary Key: #{users_table.primary_key_columns.join(", ")}"

  puts "\nColumns (#{users_table.columns.size}):"
  puts "  " + "-" * 66
  puts "  | %-20s | %-15s | %-8s | %-15s |" % ["Name", "Type", "Nullable", "Default"]
  puts "  " + "-" * 66

  users_table.columns.each do |col|
    nullable = col.nullable? ? "YES" : "NO"
    default = col.default_value || "-"
    default = default[0..14] if default.size > 15
    puts "  | %-20s | %-15s | %-8s | %-15s |" % [col.name, col.data_type, nullable, default]
  end
  puts "  " + "-" * 66

  if !users_table.indexes.empty?
    puts "\nIndexes (#{users_table.indexes.size}):"
    users_table.indexes.each do |idx|
      flags = [] of String
      flags << "UNIQUE" if idx.unique?
      flags << "PRIMARY" if idx.primary?
      flag_str = flags.empty? ? "" : " (#{flags.join(", ")})"
      puts "  - #{idx.name}: (#{idx.columns.join(", ")})#{flag_str}"
    end
  end

  if !users_table.foreign_keys.empty?
    puts "\nForeign Keys (#{users_table.foreign_keys.size}):"
    users_table.foreign_keys.each do |fk|
      puts "  - #{fk.name}: #{fk.column_name} -> #{fk.referenced_table}.#{fk.referenced_column}"
      puts "    ON DELETE: #{fk.on_delete || "NO ACTION"}, ON UPDATE: #{fk.on_update || "NO ACTION"}"
    end
  end
else
  puts "\nTable 'users' not found"
end

# =============================================================================
# 3. INTROSPECT ORDERS TABLE (WITH FOREIGN KEYS)
# =============================================================================

puts "\n" + "=" * 70
puts "3. INTROSPECT ORDERS TABLE"
puts "=" * 70

if orders_table = introspector.table("orders")
  puts "\nTable: #{orders_table.name}"
  puts "Primary Key: #{orders_table.primary_key_columns.join(", ")}"

  puts "\nColumns (#{orders_table.columns.size}):"
  orders_table.columns.each do |col|
    pk_marker = col.primary_key? ? " [PK]" : ""
    null_marker = col.nullable? ? " NULL" : " NOT NULL"
    puts "  - #{col.name}: #{col.data_type}#{null_marker}#{pk_marker}"
  end

  if !orders_table.foreign_keys.empty?
    puts "\nForeign Keys (#{orders_table.foreign_keys.size}):"
    orders_table.foreign_keys.each do |fk|
      puts "  - #{fk.name}"
      puts "    #{orders_table.name}.#{fk.column_name} -> #{fk.referenced_table}.#{fk.referenced_column}"
      actions = [] of String
      actions << "ON DELETE #{fk.on_delete}" if fk.on_delete
      actions << "ON UPDATE #{fk.on_update}" if fk.on_update
      puts "    #{actions.join(", ")}" unless actions.empty?
    end
  end

  if !orders_table.indexes.empty?
    puts "\nIndexes (#{orders_table.indexes.size}):"
    orders_table.indexes.each do |idx|
      type_str = idx.index_type ? " [#{idx.index_type}]" : ""
      puts "  - #{idx.name}: (#{idx.columns.join(", ")})#{type_str}"
    end
  end
else
  puts "\nTable 'orders' not found"
end

# =============================================================================
# 4. INTROSPECT ALL COLUMNS FOR A TABLE
# =============================================================================

puts "\n" + "=" * 70
puts "4. DETAILED COLUMN INFO FOR POSTS TABLE"
puts "=" * 70

columns = introspector.columns("posts")
if columns.empty?
  puts "\nTable 'posts' not found or has no columns"
else
  puts "\nColumns in 'posts' table:"
  columns.each_with_index do |col, idx|
    puts "\n  [#{idx + 1}] #{col.name}"
    puts "      Type: #{col.data_type}"
    puts "      Nullable: #{col.nullable?}"
    puts "      Default: #{col.default_value || "none"}"
    puts "      Primary Key: #{col.primary_key?}"
    puts "      Position: #{col.ordinal_position}"
  end
end

# =============================================================================
# 5. LIST ALL INDEXES FOR A TABLE
# =============================================================================

puts "\n" + "=" * 70
puts "5. ALL INDEXES FOR POSTS TABLE"
puts "=" * 70

indexes = introspector.indexes("posts")
if indexes.empty?
  puts "\nNo indexes found for 'posts' table"
else
  puts "\nIndexes on 'posts' table:"
  indexes.each do |idx|
    puts "\n  #{idx.name}"
    puts "    Columns: #{idx.columns.join(", ")}"
    puts "    Unique: #{idx.unique?}"
    puts "    Primary: #{idx.primary?}"
    puts "    Type: #{idx.index_type || "btree (default)"}"
  end
end

# =============================================================================
# 6. LIST ALL FOREIGN KEYS FOR A TABLE
# =============================================================================

puts "\n" + "=" * 70
puts "6. ALL FOREIGN KEYS IN DATABASE"
puts "=" * 70

puts "\nForeign Key relationships:"

tables.each do |table_name|
  fks = introspector.foreign_keys(table_name)
  next if fks.empty?

  puts "\n  #{table_name}:"
  fks.each do |fk|
    puts "    #{fk.column_name} -> #{fk.referenced_table}.#{fk.referenced_column}"
  end
end

# =============================================================================
# 7. SCHEMA COMPARISON EXAMPLE
# =============================================================================

puts "\n" + "=" * 70
puts "7. SCHEMA VALIDATION EXAMPLE"
puts "=" * 70

puts "\nValidating expected schema..."

# Define expected columns for users table
expected_users_columns = {
  "id"         => "bigint",
  "name"       => "character varying",
  "email"      => "character varying",
  "role"       => "character varying",
  "tier"       => "character varying",
  "active"     => "boolean",
  "created_at" => "timestamp without time zone",
}

if users_table = introspector.table("users")
  puts "\nUsers table validation:"

  expected_users_columns.each do |name, expected_type|
    if col = users_table.column(name)
      actual_type = col.data_type
      if actual_type.starts_with?(expected_type) || expected_type.starts_with?(actual_type)
        puts "  [OK] #{name}: #{actual_type}"
      else
        puts "  [MISMATCH] #{name}: expected #{expected_type}, got #{actual_type}"
      end
    else
      puts "  [MISSING] #{name}: column not found"
    end
  end

  # Check for unexpected columns
  existing_names = users_table.columns.map(&.name)
  unexpected = existing_names - expected_users_columns.keys
  unless unexpected.empty?
    puts "\n  Additional columns found: #{unexpected.join(", ")}"
  end
else
  puts "  [ERROR] users table not found"
end

# =============================================================================
# 8. GENERATE CRYSTAL SCHEMA FROM DATABASE
# =============================================================================

puts "\n" + "=" * 70
puts "8. GENERATE CRYSTAL RELATION FROM DATABASE"
puts "=" * 70

def crystal_type_for(data_type : String) : String
  case data_type.downcase
  when /^(big)?int/, /^(big)?serial/
    "Int64"
  when /^int/, /^serial/, /^smallint/
    "Int32"
  when /^bool/
    "Bool"
  when /^(character varying|varchar|text|char)/
    "String"
  when /^timestamp/, /^date/, /^time/
    "Time"
  when /^numeric/, /^decimal/, /^real/, /^double/
    "Float64"
  when /^uuid/
    "UUID"
  when /^json/
    "JSON::Any"
  else
    "String"
  end
end

if users_table = introspector.table("users")
  puts "\n# Generated from database schema"
  puts "class UsersRelation < Quo::Relation"
  puts "  schema :users do"

  users_table.columns.each do |col|
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

# =============================================================================
# 9. DATABASE STATISTICS
# =============================================================================

puts "\n" + "=" * 70
puts "9. DATABASE SCHEMA SUMMARY"
puts "=" * 70

total_columns = 0
total_indexes = 0
total_fks = 0

puts "\n  %-20s | %7s | %7s | %7s" % ["Table", "Columns", "Indexes", "FKs"]
puts "  " + "-" * 50

tables.each do |table_name|
  if table = introspector.table(table_name)
    total_columns += table.columns.size
    total_indexes += table.indexes.size
    total_fks += table.foreign_keys.size
    puts "  %-20s | %7d | %7d | %7d" % [
      table_name,
      table.columns.size,
      table.indexes.size,
      table.foreign_keys.size,
    ]
  end
end

puts "  " + "-" * 50
puts "  %-20s | %7d | %7d | %7d" % ["TOTAL", total_columns, total_indexes, total_fks]

# =============================================================================
# CLEANUP
# =============================================================================

puts "\n" + "=" * 70
puts "INTROSPECTION COMPLETE"
puts "=" * 70

pool.close
db.close
puts "\nConnections closed."
