# Query API

`Quo::Query` is the core immutable query builder.

## Constructor

```crystal
Quo::Query.new(
  table : Symbol,
  adapter : Adapters::Adapter
)
```

Typically created via a Relation rather than directly.

## Chainable Methods

All methods return a new `Query` instance.

### select

```crystal
def select(**columns) : Query
```

Specify columns to select. Always table-qualified.

```crystal
.select(users: [:id, :name, :email])
.select(users: [:id], posts: [:title, :body])
```

**Generated SQL:**
```sql
SELECT "users"."id", "users"."name", "users"."email" FROM "users"
```

---

### where (Hash)

```crystal
def where(**conditions) : Query
```

Add equality conditions.

```crystal
.where(users: { status: "active" })
.where(users: { role: "admin", verified: true })
```

**Generated SQL:**
```sql
WHERE "users"."status" = $1 AND "users"."role" = $2 AND "users"."verified" = $3
```

---

### where (Block)

```crystal
def where(&block : ExpressionBuilder -> Expression) : Query
```

Add expression-based conditions.

```crystal
.where { |e| e[:users][:age] >= 18 }
.where { |e| (e[:users][:role] == "admin") | (e[:users][:role] == "mod") }
```

---

### join (Association)

```crystal
def join(association : Symbol, type : JoinType = JoinType::Inner) : Query
```

Join using a defined association.

```crystal
.join(:user)      # Uses belongs_to :user association
.join(:company)   # Uses belongs_to :company association
```

---

### join (Explicit)

```crystal
def join(
  table : Symbol,
  *,
  on : NamedTuple,
  type : JoinType = JoinType::Inner
) : Query
```

Add a JOIN with explicit condition.

```crystal
.join(:profiles, on: { users: :id, eq: { profiles: :user_id } })
```

**Generated SQL:**
```sql
INNER JOIN "profiles" ON "users"."id" = "profiles"."user_id"
```

---

### left_join

```crystal
def left_join(association : Symbol) : Query
def left_join(table : Symbol, *, on : NamedTuple) : Query
```

LEFT JOIN shorthand.

---

### right_join

```crystal
def right_join(association : Symbol) : Query
def right_join(table : Symbol, *, on : NamedTuple) : Query
```

RIGHT JOIN shorthand. (PostgreSQL only)

---

### order

```crystal
def order(**columns) : Query
```

Add ORDER BY clause.

```crystal
.order(users: { created_at: :desc })
.order(users: { name: :asc, created_at: :desc })
```

**Generated SQL:**
```sql
ORDER BY "users"."created_at" DESC
ORDER BY "users"."name" ASC, "users"."created_at" DESC
```

---

### limit

```crystal
def limit(n : Int32) : Query
```

Set LIMIT clause.

---

### offset

```crystal
def offset(n : Int32) : Query
```

Set OFFSET clause.

---

### distinct

```crystal
def distinct : Query
```

Add DISTINCT keyword.

---

## Aggregation Methods

### group

```crystal
def group(**columns) : Query
```

Add GROUP BY clause.

```crystal
.group(orders: [:status])
.group(orders: [:status, :user_id])
```

**Generated SQL:**
```sql
GROUP BY "orders"."status"
GROUP BY "orders"."status", "orders"."user_id"
```

---

### having

```crystal
def having(&block : AggregateExpressionBuilder -> AggregateExpression) : Query
```

Add HAVING clause for aggregate conditions.

```crystal
.having { |h| h.count > 5 }
.having { |h| (h.count >= 3) & (h.sum(:orders, :amount) >= 1000) }
```

---

### select_count

```crystal
def select_count(as : Symbol) : Query
def select_count(table : Symbol, column : Symbol, as : Symbol, distinct : Bool = false) : Query
```

Add COUNT aggregate to SELECT.

```crystal
.select_count(as: :total)                                    # COUNT(*)
.select_count(:orders, :user_id, as: :user_count)           # COUNT(column)
.select_count(:orders, :user_id, as: :unique, distinct: true) # COUNT(DISTINCT column)
```

---

### select_sum

```crystal
def select_sum(table : Symbol, column : Symbol, as : Symbol) : Query
```

Add SUM aggregate to SELECT.

```crystal
.select_sum(:orders, :amount, as: :total_amount)
```

---

### select_avg

```crystal
def select_avg(table : Symbol, column : Symbol, as : Symbol) : Query
```

Add AVG aggregate to SELECT.

```crystal
.select_avg(:products, :price, as: :average_price)
```

---

### select_min

```crystal
def select_min(table : Symbol, column : Symbol, as : Symbol) : Query
```

Add MIN aggregate to SELECT.

```crystal
.select_min(:orders, :created_at, as: :first_order)
```

---

### select_max

```crystal
def select_max(table : Symbol, column : Symbol, as : Symbol) : Query
```

Add MAX aggregate to SELECT.

```crystal
.select_max(:orders, :amount, as: :largest_order)
```

---

## Set Operations

### union

```crystal
def union(other : Query) : Query
```

Combine results, removing duplicates.

```crystal
active_users.union(admin_users)
```

---

### union_all

```crystal
def union_all(other : Query) : Query
```

Combine results, keeping duplicates.

```crystal
query1.union_all(query2)
```

---

### intersect

```crystal
def intersect(other : Query) : Query
```

Return only rows in both queries.

```crystal
active.intersect(premium)  # Active AND premium
```

---

### except

```crystal
def except(other : Query) : Query
```

Return rows in first query not in second.

```crystal
all_users.except(deleted)  # Non-deleted users
```

---

## CTE Methods

### with_cte

```crystal
def with_cte(name : Symbol, query : Query) : Query
```

Add a Common Table Expression (WITH clause).

```crystal
.with_cte(:active_users, active_users_query)
```

**Generated SQL:**
```sql
WITH "active_users" AS (SELECT ...) SELECT ... FROM "active_users"
```

---

### with_recursive_cte

```crystal
def with_recursive_cte(name : Symbol, query : Query) : Query
```

Add a recursive CTE (WITH RECURSIVE clause).

```crystal
.with_recursive_cte(:tree, category_tree_query)
```

---

## Terminal Methods

These execute the query and return results.

### to_sql

```crystal
def to_sql : {String, Array(DB::Any)}
```

Returns generated SQL and parameters without executing.

```crystal
sql, params = query.to_sql
puts sql     # SELECT "users".* FROM "users" WHERE ...
puts params  # [true, "admin"]
```

---

### to_a

```crystal
def to_a : Array(Hash(String, DB::Any))
```

Execute query and return all results as array of hashes.

```crystal
results = query.to_a
# [{"id" => 1, "name" => "Alice"}, {"id" => 2, "name" => "Bob"}]
```

---

### first

```crystal
def first : Hash(String, DB::Any)?
```

Execute query and return first result or nil.

```crystal
user = query.first
if user
  puts user["name"]
end
```

---

### first!

```crystal
def first! : Hash(String, DB::Any)
```

Execute query and return first result. Raises `RecordNotFound` if no results.

```crystal
user = query.first!  # Raises if not found
puts user["name"]
```

---

### count

```crystal
def count : Int64
```

Execute COUNT query.

```crystal
total = query.count  # => 42_i64
```

---

### count_sql

```crystal
def count_sql : {String, Array(DB::Any)}
```

Get COUNT SQL without executing.

```crystal
sql, params = query.count_sql
# SELECT COUNT(*) FROM "users" WHERE ...
```

---

### exists?

```crystal
def exists? : Bool
```

Check if any records match.

```crystal
if query.where(users: { email: "test@example.com" }).exists?
  puts "Email taken"
end
```

---

## Complete Example

```crystal
results = UsersRelation.new(adapter)
  .select(users: [:id, :name, :email])
  .where(users: { active: true })
  .where { |e| e[:users][:score] >= 100 }
  .order(users: { created_at: :desc })
  .limit(20)
  .offset(0)
  .to_a
```
