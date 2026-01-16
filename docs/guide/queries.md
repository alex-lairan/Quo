# Queries

Quo queries are **immutable**. Every method returns a new query, leaving the original unchanged.

## SELECT

Always table-qualified:

```crystal
# Select specific columns
query.select(users: [:id, :name, :email])

# Select from multiple tables (after join)
query
  .join(:user)
  .select(contracts: [:id, :reference], users: [:name, :email])

# Select all (default when no select specified)
query  # Generates: SELECT "contracts".*
```

## WHERE

### Hash Syntax

Simple equality conditions:

```crystal
# Single condition
query.where(users: { status: "active" })

# Multiple conditions (AND)
query.where(users: { status: "active", role: "admin" })

# Chained (also AND)
query
  .where(users: { status: "active" })
  .where(users: { verified: true })
```

### Expression Syntax

For complex conditions, use the expression DSL:

```crystal
# Comparison operators
query.where { |e| e[:users][:age] >= 18 }
query.where { |e| e[:users][:score] > 100 }

# LIKE
query.where { |e| e[:users][:name].like("%John%") }
query.where { |e| e[:users][:email].ilike("%@gmail.com") }  # case-insensitive

# IN
query.where { |e| e[:users][:role].in(["admin", "moderator"]) }

# NULL checks
query.where { |e| e[:users][:deleted_at].is_null }
query.where { |e| e[:users][:verified_at].is_not_null }

# BETWEEN
query.where { |e| e[:users][:age].between(18, 65) }

# Logical operators
query.where { |e| (e[:users][:status] == "active") & (e[:users][:age] >= 18) }  # AND
query.where { |e| (e[:users][:role] == "admin") | (e[:users][:role] == "mod") } # OR
```

## ORDER

```crystal
# Single column
query.order(users: { created_at: :desc })

# Multiple columns
query.order(users: { status: :asc, created_at: :desc })
```

## LIMIT & OFFSET

```crystal
# Pagination
query.limit(20).offset(40)

# Calculate offset for page
page = 3
per_page = 20
query.limit(per_page).offset((page - 1) * per_page)
```

## DISTINCT

```crystal
query.select(users: [:country]).distinct
```

## Executing Queries

### Get Results

```crystal
# Array of hashes
users = query.to_a
# => [{"id" => 1, "name" => "Alice"}, ...]

# First result
user = query.first        # => Hash? (nil if not found)
user = query.first!       # => Hash (raises RecordNotFound if not found)
```

### Aggregates

```crystal
# Count
count = query.count  # => Int64

# Exists?
exists = query.where(users: { email: "test@example.com" }).exists?  # => Bool
```

### Debugging

```crystal
# Get generated SQL without executing
sql, params = query.to_sql
puts sql
# SELECT "users"."id", "users"."name" FROM "users" WHERE "users"."active" = ?
puts params.inspect
# [true]
```

## Immutability Example

```crystal
base = UsersRelation.new(adapter).where(users: { active: true })

# These create NEW queries, base is unchanged
admins = base.where(users: { role: "admin" })
mods = base.where(users: { role: "moderator" })

# base still has only the active condition
base_sql, _ = base.to_sql
# SELECT "users".* FROM "users" WHERE "users"."active" = ?

admins_sql, _ = admins.to_sql
# SELECT "users".* FROM "users" WHERE "users"."active" = ? AND "users"."role" = ?
```

## Chaining

All query methods can be chained:

```crystal
results = ContractsRelation.new(adapter)
  .select(contracts: [:id, :reference, :amount_cents])
  .where(contracts: { status: "active" })
  .where { |e| e[:contracts][:amount_cents] >= 10000 }
  .order(contracts: { created_at: :desc })
  .limit(50)
  .offset(0)
  .to_a
```
