# UpdateQuery API

`Quo::UpdateQuery` is an immutable UPDATE query builder.

## Constructor

```crystal
Quo::UpdateQuery.new(
  table : Symbol,
  adapter : Adapters::Adapter
)
```

## Chainable Methods

All methods return a new `UpdateQuery` instance.

### set

```crystal
def set(**columns) : UpdateQuery
def set(columns : Hash(Symbol, DB::Any)) : UpdateQuery
```

Specify column values to update.

```crystal
.set(name: "New Name", status: "active")
.set({:status => "inactive"} of Symbol => DB::Any)
```

**Generated SQL:**
```sql
UPDATE "users" SET "name" = $1, "status" = $2
```

---

### where (Hash)

```crystal
def where(**conditions) : UpdateQuery
```

Add equality conditions.

```crystal
.where(users: { id: 1 })
.where(users: { status: "active", role: "admin" })
```

**Generated SQL:**
```sql
UPDATE "users" SET ... WHERE "users"."id" = $1
```

---

### where (Block)

```crystal
def where(&block : ExpressionBuilder -> Expression) : UpdateQuery
```

Add expression-based conditions.

```crystal
.where { |e| e[:users][:age] >= 18 }
.where { |e| (e[:users][:role] == "admin") | (e[:users][:role] == "mod") }
```

---

### returning

```crystal
def returning(**columns) : UpdateQuery
```

Add RETURNING clause (PostgreSQL).

```crystal
.returning(users: [:id, :updated_at])
```

**Generated SQL:**
```sql
UPDATE "users" SET ... WHERE ... RETURNING "users"."id", "users"."updated_at"
```

---

## Terminal Methods

### to_sql

```crystal
def to_sql : {String, Array(DB::Any)}
```

Returns generated SQL and parameters without executing.

```crystal
sql, params = update.to_sql
puts sql     # UPDATE "users" SET "status" = $1 WHERE "users"."id" = $2
puts params  # ["active", 1]
```

---

### execute

```crystal
def execute : Int64
```

Execute the UPDATE and return number of affected rows.

```crystal
rows_affected = update.execute  # => 5_i64
```

---

### execute_returning

```crystal
def execute_returning : Array(Hash(String, DB::Any))
```

Execute the UPDATE and return the updated rows. Requires RETURNING clause.

```crystal
results = update
  .returning(users: [:id, :status])
  .execute_returning
# [{"id" => 1, "status" => "active"}]
```

**Raises:** `QueryError` if no RETURNING columns specified.

---

## Complete Example

```crystal
Quo::UpdateQuery.new(:users, adapter)
  .set(
    status: "inactive",
    deactivated_at: Time.utc
  )
  .where(users: { status: "pending" })
  .where { |e| e[:users][:created_at] < 30.days.ago }
  .execute
```
