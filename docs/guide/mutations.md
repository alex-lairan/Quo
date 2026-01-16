# Mutations

Quo provides type-safe, immutable builders for INSERT, UPDATE, and DELETE operations.

## INSERT

### Basic Insert

```crystal
insert = Quo::InsertQuery.new(:users, adapter)
  .values(name: "Alice", email: "alice@example.com", status: "active")

# Generate SQL
sql, params = insert.to_sql
# INSERT INTO "users" ("name", "email", "status") VALUES ($1, $2, $3)
# params: ["Alice", "alice@example.com", "active"]

# Execute and get affected rows
rows_affected = insert.execute  # => 1
```

### Insert from Hash

```crystal
user_data = {
  :name => "Bob",
  :email => "bob@example.com"
} of Symbol => DB::Any

insert = Quo::InsertQuery.new(:users, adapter)
  .values(user_data)
```

### Insert Multiple Rows

```crystal
# Using values_many with hashes
users = [
  {:name => "Alice", :email => "alice@example.com"} of Symbol => DB::Any,
  {:name => "Bob", :email => "bob@example.com"} of Symbol => DB::Any,
  {:name => "Carol", :email => "carol@example.com"} of Symbol => DB::Any
]

insert = Quo::InsertQuery.new(:users, adapter)
  .values_many(users)

# Generates: INSERT INTO "users" ("name", "email") VALUES ($1, $2), ($3, $4), ($5, $6)
```

### RETURNING Clause (PostgreSQL)

Get back the inserted rows:

```crystal
insert = Quo::InsertQuery.new(:users, adapter)
  .values(name: "Alice", email: "alice@example.com")
  .returning(users: [:id, :created_at])

# Execute and get returned data
result = insert.execute_returning_one
# => {"id" => 1, "created_at" => 2024-01-15 10:30:00}

# For multiple rows
results = insert.execute_returning
# => [{"id" => 1, ...}, {"id" => 2, ...}]
```

### Chaining Values

Values can be chained (useful for conditional inserts):

```crystal
insert = Quo::InsertQuery.new(:users, adapter)
  .values(name: "Alice")
  .values(email: "alice@example.com")  # Adds another row
```

## UPDATE

### Basic Update

```crystal
update = Quo::UpdateQuery.new(:users, adapter)
  .set(status: "inactive", updated_at: Time.utc)
  .where(users: {id: 1})

# Generate SQL
sql, params = update.to_sql
# UPDATE "users" SET "status" = $1, "updated_at" = $2 WHERE "users"."id" = $3

# Execute
rows_affected = update.execute  # => 1
```

### Multiple SET Values

```crystal
update = Quo::UpdateQuery.new(:users, adapter)
  .set(
    name: "New Name",
    email: "new@example.com",
    status: "verified",
    updated_at: Time.utc
  )
  .where(users: {id: 1})
```

### SET from Hash

```crystal
updates = {
  :status => "active",
  :verified_at => Time.utc
} of Symbol => DB::Any

update = Quo::UpdateQuery.new(:users, adapter)
  .set(updates)
  .where(users: {id: 1})
```

### WHERE Conditions

#### Hash Syntax

```crystal
# Single condition
update.where(users: {id: 1})

# Multiple conditions (AND)
update.where(users: {status: "pending", role: "user"})
```

#### Expression Syntax

For complex conditions:

```crystal
# Comparison operators
update = Quo::UpdateQuery.new(:users, adapter)
  .set(tier: "premium")
  .where { |e| e[:users][:points] >= 1000 }

# Multiple conditions
update = Quo::UpdateQuery.new(:orders, adapter)
  .set(status: "expired")
  .where { |e| (e[:orders][:status] == "pending") & (e[:orders][:created_at] < 30.days.ago) }
```

### RETURNING Clause (PostgreSQL)

```crystal
update = Quo::UpdateQuery.new(:users, adapter)
  .set(status: "active")
  .where(users: {id: 1})
  .returning(users: [:id, :status, :updated_at])

result = update.execute_returning
# => [{"id" => 1, "status" => "active", "updated_at" => ...}]
```

## DELETE

### Basic Delete

```crystal
delete = Quo::DeleteQuery.new(:users, adapter)
  .where(users: {id: 1})

# Generate SQL
sql, params = delete.to_sql
# DELETE FROM "users" WHERE "users"."id" = $1

# Execute
rows_affected = delete.execute  # => 1
```

### WHERE Conditions

#### Hash Syntax

```crystal
# Single condition
delete.where(users: {status: "deleted"})

# Multiple conditions
delete.where(users: {status: "inactive", role: "guest"})
```

#### Expression Syntax

```crystal
# Delete old records
delete = Quo::DeleteQuery.new(:sessions, adapter)
  .where { |e| e[:sessions][:expires_at] < Time.utc }

# Complex conditions
delete = Quo::DeleteQuery.new(:logs, adapter)
  .where { |e| (e[:logs][:level] == "debug") & (e[:logs][:created_at] < 7.days.ago) }
```

### RETURNING Clause (PostgreSQL)

```crystal
delete = Quo::DeleteQuery.new(:users, adapter)
  .where(users: {id: 1})
  .returning(users: [:id, :email])

result = delete.execute_returning
# => [{"id" => 1, "email" => "deleted@example.com"}]
```

### Safety: No Unrestricted Deletes

While Quo allows DELETE without WHERE, you should always add conditions:

```crystal
# Dangerous - deletes ALL rows
delete = Quo::DeleteQuery.new(:users, adapter)
delete.execute  # Deletes everything!

# Safe - always use WHERE
delete = Quo::DeleteQuery.new(:users, adapter)
  .where(users: {status: "deleted"})
delete.execute
```

## Immutability

Like queries, all mutation builders are **immutable**:

```crystal
base_insert = Quo::InsertQuery.new(:users, adapter)
  .values(role: "user")

# These create NEW builders, base_insert is unchanged
admin_insert = base_insert.values(role: "admin", name: "Admin")
user_insert = base_insert.values(name: "Regular User")

# base_insert still has only role: "user"
```

## Using with Relations

While Relations provide a convenient `query` method, for mutations you typically use the query builders directly with the adapter:

```crystal
class UsersRelation < Quo::Relation
  schema :users do
    primary_key :id, Int64
    column :name, String
    column :email, String
    column :status, String
  end
end

# Get adapter from relation context
adapter = Quo::Adapters::Postgres.new(db)

# Mutations use the builders directly
Quo::InsertQuery.new(:users, adapter)
  .values(name: "Alice", email: "alice@example.com", status: "active")
  .execute

Quo::UpdateQuery.new(:users, adapter)
  .set(status: "inactive")
  .where(users: {email: "alice@example.com"})
  .execute

Quo::DeleteQuery.new(:users, adapter)
  .where(users: {status: "deleted"})
  .execute
```

## Error Handling

```crystal
begin
  insert = Quo::InsertQuery.new(:users, adapter)
    .values(name: "Alice", email: "duplicate@example.com")
    .execute
rescue ex : DB::Error
  # Handle database errors (unique constraint, etc.)
  puts "Insert failed: #{ex.message}"
end
```

## Complete Example

```crystal
# Create a user
user = Quo::InsertQuery.new(:users, adapter)
  .values(
    name: "Alice",
    email: "alice@example.com",
    status: "pending",
    created_at: Time.utc
  )
  .returning(users: [:id])
  .execute_returning_one

user_id = user.not_nil!["id"]

# Update the user
Quo::UpdateQuery.new(:users, adapter)
  .set(status: "active", verified_at: Time.utc)
  .where(users: {id: user_id})
  .execute

# Later, soft delete
Quo::UpdateQuery.new(:users, adapter)
  .set(status: "deleted", deleted_at: Time.utc)
  .where(users: {id: user_id})
  .execute

# Or hard delete
Quo::DeleteQuery.new(:users, adapter)
  .where(users: {id: user_id})
  .execute
```
