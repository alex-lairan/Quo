# Transaction API

`Quo::Transaction` wraps database operations in a transactional context.

## Starting a Transaction

Transactions are started via the adapter:

```crystal
adapter.transaction do |tx|
  # Operations here
end
```

With isolation level:

```crystal
adapter.transaction(isolation: Quo::IsolationLevel::Serializable) do |tx|
  # Operations here
end
```

## IsolationLevel Enum

```crystal
enum Quo::IsolationLevel
  ReadUncommitted
  ReadCommitted
  RepeatableRead
  Serializable
end
```

| Level | PostgreSQL | SQLite |
|-------|------------|--------|
| `ReadUncommitted` | `READ UNCOMMITTED` | `DEFERRED` |
| `ReadCommitted` | `READ COMMITTED` | `DEFERRED` |
| `RepeatableRead` | `REPEATABLE READ` | `IMMEDIATE` |
| `Serializable` | `SERIALIZABLE` | `EXCLUSIVE` |

## Transaction Methods

### query

```crystal
def query(table : Symbol) : Query
```

Create a new Query within the transaction.

```crystal
adapter.transaction do |tx|
  users = tx.query(:users)
    .where(users: { active: true })
    .to_a
end
```

---

### [] (alias for query)

```crystal
def [](table : Symbol) : Query
```

Shorthand for `query`.

```crystal
adapter.transaction do |tx|
  users = tx[:users].where(users: { active: true }).to_a
end
```

---

### insert

```crystal
def insert(table : Symbol) : InsertQuery
```

Create a new InsertQuery within the transaction.

```crystal
adapter.transaction do |tx|
  tx.insert(:users)
    .values(name: "Alice")
    .execute
end
```

---

### update

```crystal
def update(table : Symbol) : UpdateQuery
```

Create a new UpdateQuery within the transaction.

```crystal
adapter.transaction do |tx|
  tx.update(:users)
    .set(status: "active")
    .where(users: { id: 1 })
    .execute
end
```

---

### delete

```crystal
def delete(table : Symbol) : DeleteQuery
```

Create a new DeleteQuery within the transaction.

```crystal
adapter.transaction do |tx|
  tx.delete(:sessions)
    .where { |e| e[:sessions][:expires_at] < Time.utc }
    .execute
end
```

---

### execute

```crystal
def execute(sql : String, params : Array(DB::Any) = [] of DB::Any) : Array(Hash(String, DB::Any))
```

Execute raw SQL within the transaction.

```crystal
adapter.transaction do |tx|
  tx.execute("SELECT NOW()")
end
```

---

### execute_scalar

```crystal
def execute_scalar(sql : String, params : Array(DB::Any), as type : T.class) : T forall T
```

Execute raw SQL and return a scalar value.

```crystal
adapter.transaction do |tx|
  count = tx.execute_scalar("SELECT COUNT(*) FROM users", [] of DB::Any, as: Int64)
end
```

---

### savepoint

```crystal
def savepoint(name : Symbol? = nil, &block)
```

Create a savepoint for partial rollback.

```crystal
adapter.transaction do |tx|
  tx.insert(:orders).values(status: "pending").execute

  begin
    tx.savepoint(:inventory) do
      # This might fail
      tx.update(:inventory)
        .set(quantity: -1)
        .where(inventory: { product_id: 1 })
        .execute
    end
  rescue ex
    # Savepoint rolled back, transaction continues
    puts "Inventory update failed"
  end

  tx.update(:orders).set(status: "partial").where(orders: { id: 1 }).execute
end
```

---

## Automatic Commit/Rollback

Transactions automatically:
- **Commit** when the block returns normally
- **Rollback** when an exception is raised

```crystal
# Commits
adapter.transaction do |tx|
  tx.insert(:logs).values(message: "Success").execute
end

# Rolls back
begin
  adapter.transaction do |tx|
    tx.insert(:logs).values(message: "Will be rolled back").execute
    raise "Error!"
  end
rescue
  # Transaction rolled back
end
```

## Return Values

Transactions return the block's return value:

```crystal
user_id = adapter.transaction do |tx|
  result = tx.insert(:users)
    .values(name: "Alice")
    .returning(users: [:id])
    .execute_returning_one

  result.not_nil!["id"]
end

puts user_id  # => 1
```

## Complete Example

```crystal
def transfer(adapter, from_id, to_id, amount)
  adapter.transaction(isolation: Quo::IsolationLevel::Serializable) do |tx|
    # Read source balance
    source = tx[:accounts].where(accounts: { id: from_id }).first!
    balance = source["balance"].as(Int64)

    raise "Insufficient funds" if balance < amount

    # Debit source
    tx.update(:accounts)
      .set(balance: balance - amount)
      .where(accounts: { id: from_id })
      .execute

    # Credit destination
    dest = tx[:accounts].where(accounts: { id: to_id }).first!
    tx.update(:accounts)
      .set(balance: dest["balance"].as(Int64) + amount)
      .where(accounts: { id: to_id })
      .execute

    # Log transfer
    tx.insert(:transfers)
      .values(from_account: from_id, to_account: to_id, amount: amount)
      .execute

    {from: from_id, to: to_id, amount: amount}
  end
end
```
