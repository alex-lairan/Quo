# API Reference

Complete API documentation for Quo.

## Core Classes

| Class | Description |
|-------|-------------|
| [`Query`](./query) | Immutable SQL query builder |
| [`InsertQuery`](./insert-query) | Immutable INSERT builder |
| [`UpdateQuery`](./update-query) | Immutable UPDATE builder |
| [`DeleteQuery`](./delete-query) | Immutable DELETE builder |
| [`Relation`](./relation) | Base class for table definitions |
| [`Expression`](./expression) | WHERE clause expression types |
| [`Schema`](./schema) | Table schema definition |
| [`Transaction`](./transaction) | Database transaction wrapper |
| [`Logging`](./logging) | Query logging and instrumentation |
| [`Adapters`](./adapters) | Database adapters |

## Helper Modules

| Module | Description |
|--------|-------------|
| `Quo::ColumnHelpers` | Provides `t()` helper for creating column references. Include in your code to access `t(:table)[:column]` syntax. Automatically included in `Relation`. |

## Quick Reference

### Column Helpers

```crystal
# Include in your code for t() helper
include Quo::ColumnHelpers

# Create column references
t(:users)[:name]                    # ColumnRef
t(:users)[:name].aliased(:user_name) # AliasedColumn
```

### Query Methods

```crystal
# Building
.select(**columns)          # SELECT columns (hash syntax)
.select(*columns)           # SELECT columns (with column refs)
.where(**conditions)        # WHERE with hash
.where { |e| expr }         # WHERE with expression
.join(:assoc)               # INNER JOIN via association
.left_join(:assoc)          # LEFT JOIN via association
.order(**columns)           # ORDER BY
.limit(n)                   # LIMIT
.offset(n)                  # OFFSET
.distinct                   # DISTINCT

# Aggregations
.group(**columns)           # GROUP BY
.having { |h| expr }        # HAVING
.select_count(as: :name)    # COUNT(*)
.select_sum(:t, :c, as: :n) # SUM(column)
.select_avg(:t, :c, as: :n) # AVG(column)
.select_min(:t, :c, as: :n) # MIN(column)
.select_max(:t, :c, as: :n) # MAX(column)

# Set Operations
.union(other)               # UNION
.union_all(other)           # UNION ALL
.intersect(other)           # INTERSECT
.except(other)              # EXCEPT

# CTEs
.with_cte(:name, query)     # WITH clause
.with_recursive_cte(...)    # WITH RECURSIVE

# Executing
.to_a                       # Array of results
.first                      # First result or nil
.first!                     # First result or raise
.count                      # Row count
.exists?                    # True if any match
.to_sql                     # Get SQL and params
```

### Mutation Methods

```crystal
# INSERT
InsertQuery.new(:table, adapter)
  .values(col: value)       # Set values
  .values_many([...])       # Multiple rows
  .returning(t: [:col])     # RETURNING clause
  .execute                  # Execute, return rows affected
  .execute_returning        # Execute, return rows

# UPDATE
UpdateQuery.new(:table, adapter)
  .set(col: value)          # SET values
  .where(t: {col: val})     # WHERE clause
  .returning(t: [:col])     # RETURNING clause
  .execute                  # Execute

# DELETE
DeleteQuery.new(:table, adapter)
  .where(t: {col: val})     # WHERE clause
  .returning(t: [:col])     # RETURNING clause
  .execute                  # Execute
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
