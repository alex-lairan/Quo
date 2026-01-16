# DeleteQuery API

`Quo::DeleteQuery` is an immutable DELETE query builder.

## Constructor

```crystal
Quo::DeleteQuery.new(
  table : Symbol,
  adapter : Adapters::Adapter
)
```

## Chainable Methods

All methods return a new `DeleteQuery` instance.

### where (Hash)

```crystal
def where(**conditions) : DeleteQuery
```

Add equality conditions.

```crystal
.where(users: { id: 1 })
.where(users: { status: "deleted", role: "guest" })
```

**Generated SQL:**
```sql
DELETE FROM "users" WHERE "users"."id" = $1
```

---

### where (Block)

```crystal
def where(&block : ExpressionBuilder -> Expression) : DeleteQuery
```

Add expression-based conditions.

```crystal
.where { |e| e[:sessions][:expires_at] < Time.utc }
.where { |e| (e[:logs][:level] == "debug") & (e[:logs][:created_at] < 7.days.ago) }
```

---

### returning

```crystal
def returning(**columns) : DeleteQuery
```

Add RETURNING clause (PostgreSQL).

```crystal
.returning(users: [:id, :email])
```

**Generated SQL:**
```sql
DELETE FROM "users" WHERE ... RETURNING "users"."id", "users"."email"
```

---

## Terminal Methods

### to_sql

```crystal
def to_sql : {String, Array(DB::Any)}
```

Returns generated SQL and parameters without executing.

```crystal
sql, params = delete.to_sql
puts sql     # DELETE FROM "users" WHERE "users"."id" = $1
puts params  # [1]
```

---

### execute

```crystal
def execute : Int64
```

Execute the DELETE and return number of affected rows.

```crystal
rows_affected = delete.execute  # => 3_i64
```

---

### execute_returning

```crystal
def execute_returning : Array(Hash(String, DB::Any))
```

Execute the DELETE and return the deleted rows. Requires RETURNING clause.

```crystal
results = delete
  .returning(users: [:id, :email])
  .execute_returning
# [{"id" => 1, "email" => "deleted@example.com"}]
```

**Raises:** `QueryError` if no RETURNING columns specified.

---

## Complete Example

```crystal
# Clean up expired sessions
Quo::DeleteQuery.new(:sessions, adapter)
  .where { |e| e[:sessions][:expires_at] < Time.utc }
  .execute

# Delete with confirmation
deleted = Quo::DeleteQuery.new(:users, adapter)
  .where(users: { id: 1 })
  .returning(users: [:id, :email])
  .execute_returning

puts "Deleted: #{deleted.first?.try(&.["email"])}"
```

## Safety Note

Always use WHERE clauses with DELETE. Quo allows DELETE without WHERE, but this will delete all rows:

```crystal
# DANGEROUS - deletes all rows!
Quo::DeleteQuery.new(:users, adapter).execute
```
