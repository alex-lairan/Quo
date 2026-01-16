# API Reference

Complete API documentation for Quo.

## Core Classes

| Class | Description |
|-------|-------------|
| [`Query`](./query) | Immutable SQL query builder |
| [`Relation`](./relation) | Base class for table definitions |
| [`Expression`](./expression) | WHERE clause expression types |
| [`Schema`](./schema) | Table schema definition |
| [`Adapters`](./adapters) | Database adapters |

## Quick Reference

### Query Methods

```crystal
# Building
.select(**columns)          # SELECT columns
.where(**conditions)        # WHERE with hash
.where { |e| expr }         # WHERE with expression
.join(:assoc)               # INNER JOIN via association
.left_join(:assoc)          # LEFT JOIN via association
.order(**columns)           # ORDER BY
.limit(n)                   # LIMIT
.offset(n)                  # OFFSET
.distinct                   # DISTINCT

# Executing
.to_a                       # Array of results
.first                      # First result or nil
.first!                     # First result or raise
.count                      # Row count
.exists?                    # True if any match
.to_sql                     # Get SQL and params
```

### Relation Definition

```crystal
class MyRelation < Quo::Relation
  schema :table_name do
    primary_key :id, Int64
    column :name, String
    column :active, Bool

    belongs_to :other, :foreign_key, :other_table
    has_many :items, :foreign_key, :items_table
  end

  scope :active do
    query.where(table_name: { active: true })
  end

  scope :by_name, name : String do
    query.where(table_name: { name: name })
  end
end
```

### Expression Operators

```crystal
# Comparison
e[:table][:col] == value
e[:table][:col] != value
e[:table][:col] > value
e[:table][:col] >= value
e[:table][:col] < value
e[:table][:col] <= value

# SQL functions
e[:table][:col].like(pattern)
e[:table][:col].ilike(pattern)
e[:table][:col].in([values])
e[:table][:col].between(min, max)
e[:table][:col].is_null
e[:table][:col].is_not_null

# Logical
expr1 & expr2               # AND
expr1 | expr2               # OR
e.not(expr)                 # NOT
```

## Exceptions

| Exception | When Raised |
|-----------|-------------|
| `Quo::Error` | Base exception |
| `Quo::InvalidColumnError` | Column not in schema |
| `Quo::TypeError` | Value type mismatch |
| `Quo::QueryError` | Query building error |
| `Quo::RecordNotFound` | `first!` with no results |
| `Quo::AdapterError` | Adapter operation failed |

## Type Aliases

```crystal
# DB::Any - Union of all supported database types
DB::Any = Bool | Float32 | Float64 | Int32 | Int64 | String | Time | Nil
```
