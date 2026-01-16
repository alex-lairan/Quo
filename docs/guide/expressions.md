# Expressions

Expressions build complex WHERE conditions with a type-safe DSL.

## Column References

Always use `e[:table][:column]` syntax inside expression blocks:

```crystal
.where { |e| e[:users][:status] == "active" }
#            ^  ^^^^^ ^^^^^^
#            |  table column
#            expression builder
```

This ensures no ambiguity when joining tables.

## Comparison Operators

| Operator | SQL | Example |
|----------|-----|---------|
| `==` | `=` | `e[:users][:status] == "active"` |
| `!=` | `!=` | `e[:users][:status] != "deleted"` |
| `>` | `>` | `e[:users][:age] > 18` |
| `>=` | `>=` | `e[:users][:score] >= 100` |
| `<` | `<` | `e[:users][:age] < 65` |
| `<=` | `<=` | `e[:users][:score] <= 1000` |

```crystal
# Examples
.where { |e| e[:contracts][:amount_cents] >= 50000_i64 }
.where { |e| e[:users][:age] > 21 }
.where { |e| e[:products][:price] <= 99.99 }
```

## String Operators

### LIKE

```crystal
# Case-sensitive pattern matching
.where { |e| e[:users][:name].like("John%") }      # Starts with
.where { |e| e[:users][:name].like("%Smith") }     # Ends with
.where { |e| e[:users][:name].like("%John%") }     # Contains
```

### ILIKE (Case-Insensitive)

```crystal
# PostgreSQL native ILIKE
.where { |e| e[:users][:email].ilike("%@GMAIL.COM") }

# SQLite: automatically converted to LOWER(col) LIKE LOWER(?)
```

## Collection Operators

### IN

```crystal
# Array of values
.where { |e| e[:users][:role].in(["admin", "moderator", "editor"]) }
.where { |e| e[:orders][:status].in(["pending", "processing"]) }
```

### BETWEEN

```crystal
.where { |e| e[:users][:age].between(18, 65) }
.where { |e| e[:orders][:total].between(100_i64, 500_i64) }
```

## NULL Checks

```crystal
# IS NULL
.where { |e| e[:users][:deleted_at].is_null }

# IS NOT NULL
.where { |e| e[:users][:verified_at].is_not_null }
```

## Logical Operators

### AND (`&`)

```crystal
.where { |e|
  (e[:users][:active] == true) & (e[:users][:verified] == true)
}

# Generates:
# WHERE ("users"."active" = ? AND "users"."verified" = ?)
```

### OR (`|`)

```crystal
.where { |e|
  (e[:users][:role] == "admin") | (e[:users][:role] == "superuser")
}

# Generates:
# WHERE ("users"."role" = ? OR "users"."role" = ?)
```

### NOT

Use the `not` method on the expression builder:

```crystal
.where { |e| e.not(e[:users][:status] == "banned") }

# Generates:
# WHERE NOT ("users"."status" = ?)
```

## Complex Expressions

Combine operators for complex conditions:

```crystal
.where { |e|
  (
    (e[:users][:role] == "admin") | (e[:users][:role] == "moderator")
  ) & (
    e[:users][:active] == true
  ) & (
    e[:users][:score] >= 100
  )
}

# Generates:
# WHERE (
#   ("users"."role" = ? OR "users"."role" = ?)
#   AND "users"."active" = ?
#   AND "users"."score" >= ?
# )
```

## Multiple WHERE Clauses

Chained `.where` calls are joined with AND:

```crystal
query
  .where { |e| e[:users][:active] == true }
  .where { |e| e[:users][:age] >= 18 }
  .where { |e| e[:users][:country].in(["US", "CA", "UK"]) }

# Generates:
# WHERE "users"."active" = ?
#   AND "users"."age" >= ?
#   AND "users"."country" IN (?, ?, ?)
```

## Type Checking

Quo validates types at runtime:

```crystal
# This will raise Quo::TypeError
.where(contracts: { amount_cents: "not a number" })
# => TypeError: Type mismatch for column 'amount_cents': expected Int64, got String

# Correct usage
.where(contracts: { amount_cents: 50000_i64 })
```

## Expression Builder Methods

The expression builder `e` provides these methods:

| Method | Description |
|--------|-------------|
| `e[:table][:column]` | Create column reference |
| `e.not(expr)` | Negate an expression |
| `e.raw(sql, *params)` | Raw SQL (escape hatch) |

## Raw SQL Escape Hatch

When you need raw SQL:

```crystal
.where { |e| e.raw("users.score > (SELECT AVG(score) FROM users)") }
```

::: warning
Use `raw` sparingly. It bypasses validation and may introduce SQL injection if misused.
:::
