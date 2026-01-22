# Queries

Quo queries are **immutable**. Every method returns a new query, leaving the original unchanged.

## SELECT

### Basic SELECT

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

### SELECT with Column References

When working with Relations, you can use the `t()` helper to create column references. The `t()` helper is available in Relations automatically, or you can include `Quo::ColumnHelpers` in your own code:

```crystal
# In Relation (t() is automatically available)
relation
  .select(
    t(:users)[:id],
    t(:users)[:name],
    t(:users)[:email]
  )

# In your own code, include the helper module
include Quo::ColumnHelpers

query.select(t(:users)[:name].aliased(:user_name))
```

### Aliased Columns

Alias columns using the `.aliased()` method:

```crystal
# Single aliased column
relation.select(t(:users)[:name].aliased(:user_name))
# Generates: SELECT "users"."name" AS "user_name"

# Multiple aliased columns
relation.select(
  t(:users)[:name].aliased(:full_name),
  t(:users)[:email].aliased(:email_address)
)

# Mix regular and aliased columns
relation.select(
  t(:users)[:id],                          # No alias
  t(:users)[:name].aliased(:user_name),    # Aliased
  t(:users)[:email].aliased(:contact)      # Aliased
)

# Alias columns from joined tables
relation
  .join(:organizations, on: {users: :org_id, eq: {organizations: :id}})
  .select(
    t(:users)[:name].aliased(:user_name),
    t(:organizations)[:name].aliased(:org_name)
  )
```

You can also combine hash-based select with aliased columns:

```crystal
relation
  .select(users: [:id])                    # Hash-based
  .select(t(:users)[:name].aliased(:username))  # Aliased
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

## GROUP BY & Aggregations

### Basic GROUP BY

```crystal
# Group by single column
query = Quo::Query.new(:orders, adapter)
  .select(orders: [:status])
  .select_count(as: :count)
  .group(orders: [:status])

# Group by multiple columns
query = Quo::Query.new(:orders, adapter)
  .select(orders: [:status, :user_id])
  .select_count(as: :count)
  .group(orders: [:status, :user_id])
```

### Aggregate Functions

```crystal
# COUNT(*)
query.select_count(as: :total)

# COUNT(column)
query.select_count(:orders, :user_id, as: :user_count)

# COUNT(DISTINCT column)
query.select_count(:orders, :user_id, as: :unique_users, distinct: true)

# SUM
query.select_sum(:orders, :amount, as: :total_amount)

# AVG
query.select_avg(:products, :price, as: :average_price)

# MIN
query.select_min(:orders, :created_at, as: :first_order)

# MAX
query.select_max(:orders, :amount, as: :largest_order)
```

### HAVING

Filter grouped results with aggregate conditions:

```crystal
# Orders per user, only users with more than 5 orders
query = Quo::Query.new(:orders, adapter)
  .select(orders: [:user_id])
  .select_count(as: :order_count)
  .group(orders: [:user_id])
  .having { |h| h.count > 5 }

# Complex HAVING with multiple conditions
query = Quo::Query.new(:orders, adapter)
  .select(orders: [:user_id])
  .select_count(as: :order_count)
  .select_sum(:orders, :amount, as: :total_spent)
  .group(orders: [:user_id])
  .having { |h| (h.count >= 3) & (h.sum(:orders, :amount) >= 1000) }
```

## Subqueries

### IN Subquery

```crystal
# Find users who have placed orders
premium_orders = Quo::Query.new(:orders, adapter)
  .select(orders: [:user_id])
  .where(orders: { tier: "premium" })

users = Quo::Query.new(:users, adapter)
  .where { |e| e[:users][:id].in(premium_orders) }
```

### NOT IN Subquery

```crystal
# Find users who have NOT been blocked
blocked = Quo::Query.new(:blocked_users, adapter)
  .select(blocked_users: [:user_id])

active_users = Quo::Query.new(:users, adapter)
  .where { |e| e[:users][:id].not_in(blocked) }
```

### EXISTS / NOT EXISTS

```crystal
# Users with at least one order
orders_subquery = Quo::Query.new(:orders, adapter)
  .select(orders: [:id])
  .where(orders: { user_id: 1 })

users = Quo::Query.new(:users, adapter)
  .where { |e| e.exists(orders_subquery) }

# Users with no orders
users_without_orders = Quo::Query.new(:users, adapter)
  .where { |e| e.not_exists(orders_subquery) }
```

### Scalar Subqueries

Compare a column to a single value from a subquery:

```crystal
# Orders with amount above average
avg_amount = Quo::Query.new(:orders, adapter)
  .select_avg(:orders, :amount)

above_average = Quo::Query.new(:orders, adapter)
  .where { |e| e[:orders][:amount].gt_subquery(avg_amount) }
```

Available scalar comparisons: `eq_subquery`, `gt_subquery`, `gte_subquery`, `lt_subquery`, `lte_subquery`

## Set Operations

### UNION

Combine results from multiple queries, removing duplicates:

```crystal
active_users = Quo::Query.new(:users, adapter)
  .select(users: [:id, :name])
  .where(users: { active: true })

admin_users = Quo::Query.new(:users, adapter)
  .select(users: [:id, :name])
  .where(users: { role: "admin" })

# UNION (removes duplicates)
combined = active_users.union(admin_users)

# UNION ALL (keeps duplicates)
combined_all = active_users.union_all(admin_users)
```

### INTERSECT

Return only rows present in both queries:

```crystal
active = Quo::Query.new(:users, adapter).select(users: [:id]).where(users: { active: true })
premium = Quo::Query.new(:users, adapter).select(users: [:id]).where(users: { tier: "premium" })

# Active AND premium users
both = active.intersect(premium)
```

### EXCEPT

Return rows in first query that are not in second:

```crystal
all_users = Quo::Query.new(:users, adapter).select(users: [:id])
deleted = Quo::Query.new(:users, adapter).select(users: [:id]).where(users: { deleted: true })

# Non-deleted users
active = all_users.except(deleted)
```

### Chaining Set Operations

```crystal
pending = query.where(orders: { status: "pending" })
processing = query.where(orders: { status: "processing" })
shipped = query.where(orders: { status: "shipped" })

# All non-delivered orders
combined = pending.union(processing).union(shipped)
```

## Common Table Expressions (CTEs)

CTEs let you define named temporary result sets for use in your query.

### Basic CTE

```crystal
# Define a CTE
active_users_query = Quo::Query.new(:users, adapter)
  .select(users: [:id, :name, :email])
  .where(users: { active: true })

# Use the CTE
query = Quo::Query.new(:active_users, adapter)
  .with_cte(:active_users, active_users_query)
  .select(active_users: [:id, :name])
  .where(active_users: { email: "test@example.com" })
```

### Multiple CTEs

```crystal
vip_users = Quo::Query.new(:users, adapter)
  .select(users: [:id])
  .where(users: { tier: "vip" })

recent_orders = Quo::Query.new(:orders, adapter)
  .select(orders: [:id, :user_id, :amount])
  .where(orders: { status: "completed" })

query = Quo::Query.new(:vip_users, adapter)
  .with_cte(:vip_users, vip_users)
  .with_cte(:recent_orders, recent_orders)
  .select(vip_users: [:id])
```

### Recursive CTEs

For hierarchical data like trees or graphs:

```crystal
# Get all categories and their children
category_tree = Quo::Query.new(:categories, adapter)
  .select(categories: [:id, :name, :parent_id])
  .where(categories: { parent_id: 1 })

query = Quo::Query.new(:tree, adapter)
  .with_recursive_cte(:tree, category_tree)
  .select(tree: [:id, :name])
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
