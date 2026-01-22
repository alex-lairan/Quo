# Expression API

Expressions build type-safe WHERE conditions.

## Expression Builder

Inside a `where` block, you receive an `ExpressionBuilder`:

```crystal
.where { |e|
  # e is an ExpressionBuilder
  e[:table][:column] == value
}
```

## Column References

### Creating a Column Reference

```crystal
e[:table][:column]
```

Returns a `ColumnRef` that can be used with operators.

```crystal
.where { |e| e[:users][:name] == "Alice" }
.where { |e| e[:contracts][:amount] >= 1000 }
```

### ColumnRef Struct

Direct construction of column references:

```crystal
ColumnRef.new(:users, :name)
```

**Properties:**
- `table : Symbol` - The table name
- `column : Symbol` - The column name

### Aliased Columns

Create an aliased column reference using `.aliased()`:

```crystal
# In Relation (using t() helper)
t(:users)[:name].aliased(:user_name)

# Direct ColumnRef construction
ColumnRef.new(:users, :name).aliased(:user_name)
```

**Generated SQL:**
```sql
"users"."name" AS "user_name"
```

### AliasedColumn Struct

Represents a column with an alias.

**Properties:**
- `column : ColumnRef` - The original column reference
- `alias_name : Symbol` - The alias for the column
- `table : Symbol` - Delegates to `column.table`
- `original_column : Symbol` - Returns `column.column`

### TableRef Helper

The `t()` method is available through the `Quo::ColumnHelpers` module:

```crystal
# In Relation (automatically included)
t(:users)        # Returns TableRef.new(:users)
t(:users)[:name] # Returns ColumnRef.new(:users, :name)

# In your own code, include the module
include Quo::ColumnHelpers

t(:users)[:email].aliased(:contact_email)
```

**Usage in SELECT:**
```crystal
relation.select(
  t(:users)[:id],
  t(:users)[:name].aliased(:full_name)
)
```

**Usage in specs or helpers:**
```crystal
require "quo"

include Quo::ColumnHelpers

# Now you can use t() directly
column = t(:users)[:name].aliased(:user_name)
```

---

## Comparison Operators

### == (Equal)

```crystal
e[:table][:column] == value
```

**SQL:** `"table"."column" = $1`

### != (Not Equal)

```crystal
e[:table][:column] != value
```

**SQL:** `"table"."column" != $1`

### > (Greater Than)

```crystal
e[:table][:column] > value
```

**SQL:** `"table"."column" > $1`

### >= (Greater Than or Equal)

```crystal
e[:table][:column] >= value
```

**SQL:** `"table"."column" >= $1`

### < (Less Than)

```crystal
e[:table][:column] < value
```

**SQL:** `"table"."column" < $1`

### <= (Less Than or Equal)

```crystal
e[:table][:column] <= value
```

**SQL:** `"table"."column" <= $1`

---

## String Methods

### like

```crystal
e[:table][:column].like(pattern : String)
```

Case-sensitive pattern matching.

```crystal
e[:users][:name].like("John%")    # Starts with
e[:users][:name].like("%Smith")   # Ends with
e[:users][:name].like("%John%")   # Contains
```

**SQL:** `"users"."name" LIKE $1`

### ilike

```crystal
e[:table][:column].ilike(pattern : String)
```

Case-insensitive pattern matching.

```crystal
e[:users][:email].ilike("%@gmail.com")
```

**SQL (PostgreSQL):** `"users"."email" ILIKE $1`
**SQL (SQLite):** `LOWER("users"."email") LIKE LOWER($1)`

---

## Collection Methods

### in

```crystal
e[:table][:column].in(values : Array)
```

Check if value is in array.

```crystal
e[:users][:role].in(["admin", "moderator"])
e[:orders][:status].in(["pending", "processing"])
```

**SQL:** `"users"."role" IN ($1, $2)`

### between

```crystal
e[:table][:column].between(min, max)
```

Check if value is between min and max (inclusive).

```crystal
e[:users][:age].between(18, 65)
e[:orders][:total].between(100_i64, 1000_i64)
```

**SQL:** `"users"."age" BETWEEN $1 AND $2`

---

## NULL Methods

### is_null

```crystal
e[:table][:column].is_null
```

Check if value is NULL.

```crystal
e[:users][:deleted_at].is_null
```

**SQL:** `"users"."deleted_at" IS NULL`

### is_not_null

```crystal
e[:table][:column].is_not_null
```

Check if value is not NULL.

```crystal
e[:users][:verified_at].is_not_null
```

**SQL:** `"users"."verified_at" IS NOT NULL`

---

## Logical Operators

### & (AND)

```crystal
expr1 & expr2
```

Combine expressions with AND.

```crystal
.where { |e|
  (e[:users][:active] == true) & (e[:users][:verified] == true)
}
```

**SQL:** `("users"."active" = $1 AND "users"."verified" = $2)`

### | (OR)

```crystal
expr1 | expr2
```

Combine expressions with OR.

```crystal
.where { |e|
  (e[:users][:role] == "admin") | (e[:users][:role] == "superuser")
}
```

**SQL:** `("users"."role" = $1 OR "users"."role" = $2)`

### not

```crystal
e.not(expression)
```

Negate an expression.

```crystal
.where { |e| e.not(e[:users][:status] == "banned") }
```

**SQL:** `NOT ("users"."status" = $1)`

---

## Raw SQL

### raw

```crystal
e.raw(sql : String, *params)
```

Insert raw SQL. Use sparingly.

```crystal
.where { |e| e.raw("users.score > (SELECT AVG(score) FROM users)") }
```

::: warning
Raw SQL bypasses validation. Be careful with user input.
:::

---

## Expression Types

| Type | Description |
|------|-------------|
| `ColumnRef` | Table + column reference |
| `Eq` | Equality comparison |
| `NotEq` | Inequality comparison |
| `Gt` | Greater than |
| `Gte` | Greater than or equal |
| `Lt` | Less than |
| `Lte` | Less than or equal |
| `Like` | LIKE pattern |
| `ILike` | Case-insensitive LIKE |
| `In` | IN array |
| `Between` | BETWEEN range |
| `IsNull` | IS NULL |
| `IsNotNull` | IS NOT NULL |
| `And` | AND combination |
| `Or` | OR combination |
| `Not` | NOT negation |
| `Raw` | Raw SQL |

---

## Complex Example

```crystal
.where { |e|
  (
    (e[:orders][:status] == "completed") |
    (e[:orders][:status] == "shipped")
  ) &
  (e[:orders][:total] >= 100_i64) &
  (e[:orders][:created_at].is_not_null) &
  e.not(e[:orders][:cancelled] == true)
}
```

**Generated SQL:**
```sql
WHERE (
  ("orders"."status" = $1 OR "orders"."status" = $2)
  AND "orders"."total" >= $3
  AND "orders"."created_at" IS NOT NULL
  AND NOT ("orders"."cancelled" = $4)
)
```
