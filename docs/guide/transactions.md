# Transactions

Quo provides transaction support with isolation levels and savepoints.

## Basic Transactions

Use the adapter's `transaction` method to wrap operations in a transaction:

```crystal
adapter.transaction do |tx|
  # All operations here run in a single transaction
  tx.insert(:users)
    .values(name: "Alice", email: "alice@example.com")
    .execute

  tx.update(:accounts)
    .set(balance: 100)
    .where(accounts: {user_id: 1})
    .execute
end
# Transaction automatically commits on success
```

## Automatic Rollback

If an exception is raised, the transaction rolls back:

```crystal
begin
  adapter.transaction do |tx|
    tx.insert(:users)
      .values(name: "Alice")
      .execute

    # This error causes rollback
    raise "Something went wrong!"

    tx.insert(:users)
      .values(name: "Bob")
      .execute  # Never reached
  end
rescue ex
  # Transaction was rolled back
  # Neither Alice nor Bob was inserted
end
```

## Transaction Object

The block receives a `Transaction` object with methods for queries and mutations:

```crystal
adapter.transaction do |tx|
  # SELECT queries
  users = tx.query(:users)
    .where(users: {status: "active"})
    .to_a

  # Shorthand with []
  orders = tx[:orders]
    .where(orders: {user_id: 1})
    .to_a

  # INSERT
  tx.insert(:logs)
    .values(message: "Processed #{users.size} users")
    .execute

  # UPDATE
  tx.update(:users)
    .set(last_active: Time.utc)
    .where(users: {status: "active"})
    .execute

  # DELETE
  tx.delete(:sessions)
    .where { |e| e[:sessions][:expires_at] < Time.utc }
    .execute
end
```

## Isolation Levels

Specify an isolation level when starting the transaction:

```crystal
# PostgreSQL isolation levels
adapter.transaction(isolation: Quo::IsolationLevel::Serializable) do |tx|
  # Strongest isolation - full serializable transactions
  tx.query(:inventory)
    .where(inventory: {product_id: 1})
    .first!

  tx.update(:inventory)
    .set(quantity: 99)
    .where(inventory: {product_id: 1})
    .execute
end
```

### Available Isolation Levels

| Level | Description | Use Case |
|-------|-------------|----------|
| `ReadUncommitted` | Allows dirty reads | Rarely used, fastest |
| `ReadCommitted` | Sees only committed data | Default for most databases |
| `RepeatableRead` | Consistent reads within transaction | Reports, analytics |
| `Serializable` | Full isolation, as if sequential | Financial transactions |

### PostgreSQL Mapping

```crystal
Quo::IsolationLevel::ReadUncommitted  # -> READ UNCOMMITTED
Quo::IsolationLevel::ReadCommitted    # -> READ COMMITTED
Quo::IsolationLevel::RepeatableRead   # -> REPEATABLE READ
Quo::IsolationLevel::Serializable     # -> SERIALIZABLE
```

### SQLite Mapping

SQLite uses transaction modes instead of isolation levels:

```crystal
Quo::IsolationLevel::ReadUncommitted  # -> BEGIN DEFERRED
Quo::IsolationLevel::ReadCommitted    # -> BEGIN DEFERRED
Quo::IsolationLevel::RepeatableRead   # -> BEGIN IMMEDIATE
Quo::IsolationLevel::Serializable     # -> BEGIN EXCLUSIVE
```

## Savepoints

Savepoints allow partial rollback within a transaction:

```crystal
adapter.transaction do |tx|
  tx.insert(:users)
    .values(name: "Alice")
    .execute

  begin
    tx.savepoint do
      # Try something that might fail
      tx.insert(:users)
        .values(name: "Bob", email: "duplicate@example.com")  # unique violation
        .execute
    end
  rescue ex
    # Savepoint rolled back, but main transaction continues
    puts "Bob insert failed: #{ex.message}"
  end

  tx.insert(:users)
    .values(name: "Carol")
    .execute

  # Alice and Carol are inserted, Bob is not
end
```

### Named Savepoints

```crystal
adapter.transaction do |tx|
  tx.insert(:orders).values(status: "pending").execute

  tx.savepoint(:inventory_check) do
    # Check and update inventory
    inventory = tx.query(:inventory)
      .where(inventory: {product_id: 1})
      .first!

    if inventory["quantity"].as(Int64) < 1
      raise "Out of stock"
    end

    tx.update(:inventory)
      .set(quantity: inventory["quantity"].as(Int64) - 1)
      .where(inventory: {product_id: 1})
      .execute
  end

  tx.update(:orders)
    .set(status: "confirmed")
    .where(orders: {id: 1})
    .execute
end
```

### Nested Savepoints

Savepoints can be nested:

```crystal
adapter.transaction do |tx|
  tx.insert(:logs).values(level: "info", message: "Start").execute

  tx.savepoint(:outer) do
    tx.insert(:logs).values(level: "info", message: "Outer").execute

    tx.savepoint(:inner) do
      tx.insert(:logs).values(level: "debug", message: "Inner").execute
      # If this fails, only inner savepoint rolls back
    end
  end

  tx.insert(:logs).values(level: "info", message: "End").execute
end
```

## Returning Values

Transactions return the value of the block:

```crystal
user_id = adapter.transaction do |tx|
  result = tx.insert(:users)
    .values(name: "Alice", email: "alice@example.com")
    .returning(users: [:id])
    .execute_returning_one

  result.not_nil!["id"]
end

puts user_id  # => 1
```

## Error Handling

### Database Errors

```crystal
begin
  adapter.transaction do |tx|
    tx.insert(:users)
      .values(email: "duplicate@example.com")  # unique constraint
      .execute
  end
rescue ex : DB::Error
  puts "Transaction failed: #{ex.message}"
  # Transaction was rolled back
end
```

### Custom Rollback

To manually trigger a rollback, raise an exception:

```crystal
adapter.transaction do |tx|
  user = tx.query(:users)
    .where(users: {id: 1})
    .first

  if user.nil?
    raise Quo::RecordNotFound.new("User 1 not found")
  end

  # Continue with user...
end
```

## Best Practices

### Keep Transactions Short

```crystal
# Good: Transaction only wraps database operations
data = process_complex_data(input)  # Outside transaction

adapter.transaction do |tx|
  tx.insert(:results).values(data).execute
end

# Bad: Long-running operations inside transaction
adapter.transaction do |tx|
  data = process_complex_data(input)  # Holds lock
  tx.insert(:results).values(data).execute
end
```

### Use Appropriate Isolation

```crystal
# For read-heavy analytics, use RepeatableRead
adapter.transaction(isolation: Quo::IsolationLevel::RepeatableRead) do |tx|
  report_data = tx.query(:orders)
    .select_sum(:orders, :amount, as: :total)
    .group(orders: [:status])
    .to_a
end

# For financial operations, use Serializable
adapter.transaction(isolation: Quo::IsolationLevel::Serializable) do |tx|
  balance = tx.query(:accounts)
    .where(accounts: {id: 1})
    .first!["balance"].as(Int64)

  if balance >= amount
    tx.update(:accounts)
      .set(balance: balance - amount)
      .where(accounts: {id: 1})
      .execute
  end
end
```

### Handle Serialization Failures

Serializable transactions may fail due to conflicts:

```crystal
max_retries = 3
retries = 0

loop do
  begin
    adapter.transaction(isolation: Quo::IsolationLevel::Serializable) do |tx|
      # Your transaction logic
    end
    break  # Success
  rescue ex : DB::Error
    retries += 1
    if retries >= max_retries
      raise ex
    end
    sleep(0.1 * retries)  # Exponential backoff
  end
end
```

## Complete Example

```crystal
# Transfer funds between accounts
def transfer(adapter, from_id : Int64, to_id : Int64, amount : Int64)
  adapter.transaction(isolation: Quo::IsolationLevel::Serializable) do |tx|
    # Lock and read source account
    source = tx.query(:accounts)
      .where(accounts: {id: from_id})
      .first!

    source_balance = source["balance"].as(Int64)

    if source_balance < amount
      raise "Insufficient funds"
    end

    # Debit source
    tx.update(:accounts)
      .set(balance: source_balance - amount)
      .where(accounts: {id: from_id})
      .execute

    # Credit destination
    tx.update(:accounts)
      .set { |s| s[:balance] = s[:balance] + amount }
      .where(accounts: {id: to_id})
      .execute

    # Log the transfer
    tx.insert(:transfers)
      .values(
        from_account: from_id,
        to_account: to_id,
        amount: amount,
        created_at: Time.utc
      )
      .execute

    {from: from_id, to: to_id, amount: amount}
  end
end
```
