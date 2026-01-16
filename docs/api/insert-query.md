# InsertQuery API

`Quo::InsertQuery` is an immutable INSERT query builder.

## Constructor

```crystal
Quo::InsertQuery.new(
  table : Symbol,
  adapter : Adapters::Adapter
)
```

## Chainable Methods

All methods return a new `InsertQuery` instance.

### values

```crystal
def values(**columns) : InsertQuery
def values(columns : Hash(Symbol, DB::Any)) : InsertQuery
def values(columns : NamedTuple) : InsertQuery
```

Add a row of values to insert.

```crystal
.values(name: "Alice", email: "alice@example.com")
.values({:name => "Bob", :email => "bob@example.com"} of Symbol => DB::Any)
```

**Generated SQL:**
```sql
INSERT INTO "users" ("name", "email") VALUES ($1, $2)
```

---

### values_many

```crystal
def values_many(rows : Array(Hash(Symbol, DB::Any))) : InsertQuery
def values_many(rows : Array(NamedTuple)) : InsertQuery
```

Insert multiple rows at once.

```crystal
rows = [
  {:name => "Alice", :email => "alice@example.com"} of Symbol => DB::Any,
  {:name => "Bob", :email => "bob@example.com"} of Symbol => DB::Any
]
.values_many(rows)
```

**Generated SQL:**
```sql
INSERT INTO "users" ("name", "email") VALUES ($1, $2), ($3, $4)
```

---

### returning

```crystal
def returning(**columns) : InsertQuery
```

Add RETURNING clause (PostgreSQL).

```crystal
.returning(users: [:id, :created_at])
```

**Generated SQL:**
```sql
INSERT INTO "users" (...) VALUES (...) RETURNING "users"."id", "users"."created_at"
```

---

## Terminal Methods

### to_sql

```crystal
def to_sql : {String, Array(DB::Any)}
```

Returns generated SQL and parameters without executing.

```crystal
sql, params = insert.to_sql
puts sql     # INSERT INTO "users" ("name") VALUES ($1)
puts params  # ["Alice"]
```

---

### execute

```crystal
def execute : Int64
```

Execute the INSERT and return number of affected rows.

```crystal
rows_affected = insert.execute  # => 1_i64
```

---

### execute_returning

```crystal
def execute_returning : Array(Hash(String, DB::Any))
```

Execute the INSERT and return the inserted rows. Requires RETURNING clause.

```crystal
results = insert
  .returning(users: [:id, :created_at])
  .execute_returning
# [{"id" => 1, "created_at" => 2024-01-15...}]
```

**Raises:** `QueryError` if no RETURNING columns specified.

---

### execute_returning_one

```crystal
def execute_returning_one : Hash(String, DB::Any)?
```

Execute and return first inserted row.

```crystal
user = insert
  .returning(users: [:id])
  .execute_returning_one
# {"id" => 1}
```

---

## Complete Example

```crystal
user = Quo::InsertQuery.new(:users, adapter)
  .values(
    name: "Alice",
    email: "alice@example.com",
    status: "pending",
    created_at: Time.utc
  )
  .returning(users: [:id, :created_at])
  .execute_returning_one

puts user.not_nil!["id"]  # => 1
```
