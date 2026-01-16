# Validation & Type Checking

Quo validates column references and checks types at runtime, catching errors before they hit the database.

## Column Validation

All column references are validated against the schema:

```crystal
class UsersRelation < Quo::Relation
  schema :users do
    primary_key :id, Int64
    column :name, String
    column :email, String
    column :active, Bool
  end
end

# Valid - all columns exist
UsersRelation.new(adapter)
  .select(users: [:id, :name, :email])
  .to_a

# Invalid - raises error immediately
UsersRelation.new(adapter)
  .select(users: [:id, :nonexistent])
  .to_a
# => Quo::InvalidColumnError: Column 'nonexistent' does not exist in table 'users'.
#    Available columns: id, name, email, active
```

### Validation in Different Contexts

Column validation works in:

| Context | Example |
|---------|---------|
| SELECT | `.select(users: [:bad_column])` |
| WHERE (hash) | `.where(users: { bad_column: "x" })` |
| WHERE (expression) | `.where { \|e\| e[:users][:bad_column] == "x" }` |
| ORDER | `.order(users: { bad_column: :desc })` |

### Joined Tables

Validation extends to joined tables:

```crystal
ContractsRelation.new(adapter)
  .join(:user)
  .select(users: [:nonexistent])  # Validates against users schema
# => Quo::InvalidColumnError: Column 'nonexistent' does not exist in table 'users'.
```

## Type Checking

Values are checked against column types:

```crystal
class ContractsRelation < Quo::Relation
  schema :contracts do
    column :status, String
    column :amount_cents, Int64
    column :active, Bool
  end
end

# Valid types
ContractsRelation.new(adapter)
  .where(contracts: { status: "active" })        # String for String
  .where(contracts: { amount_cents: 5000_i64 })  # Int64 for Int64
  .where(contracts: { active: true })            # Bool for Bool
  .to_a

# Type mismatch - raises error
ContractsRelation.new(adapter)
  .where(contracts: { amount_cents: "not a number" })
  .to_a
# => Quo::TypeError: Type mismatch for column 'amount_cents' in table 'contracts':
#    expected Int64, got String
```

### Type Compatibility

| Column Type | Accepts |
|-------------|---------|
| `String` | `String` |
| `Int64` | `Int64`, `Int32` (widening) |
| `Int32` | `Int32`, `Int64` |
| `Float64` | `Float64`, `Float32`, `Int32`, `Int64` |
| `Bool` | `Bool` |
| `Time` | `Time` |

```crystal
# Int32 is accepted for Int64 column (widening)
.where(contracts: { amount_cents: 1000 })  # Int32 -> OK for Int64 column
```

### Expression Type Checking

Types are also checked in expressions:

```crystal
# Valid
.where { |e| e[:contracts][:amount_cents] >= 5000_i64 }

# Invalid - raises TypeError
.where { |e| e[:contracts][:amount_cents] >= "invalid" }
# => Quo::TypeError: Type mismatch for column 'amount_cents': expected Int64, got String

# Also checked in IN, BETWEEN, etc.
.where { |e| e[:contracts][:status].in([1, 2, 3]) }  # TypeError: expected String, got Int
```

## Unregistered Tables

For flexibility, validation is skipped for tables without a registered schema:

```crystal
# This works - external_api table has no schema
ContractsRelation.new(adapter)
  .join(:external_api, on: { contracts: :id, eq: { external_api: :contract_id } })
  .select(external_api: [:any_column])  # No validation - table not registered
  .to_a
```

This allows explicit joins to tables that don't have a Relation defined.

## Error Types

| Error | When |
|-------|------|
| `Quo::InvalidColumnError` | Column doesn't exist in table |
| `Quo::TypeError` | Value type doesn't match column type |
| `Quo::QueryError` | Association not found |
| `Quo::RecordNotFound` | `first!` with no results |

## Handling Errors

```crystal
begin
  UsersRelation.new(adapter)
    .select(users: [:bad_column])
    .to_a
rescue ex : Quo::InvalidColumnError
  puts "Invalid column: #{ex.message}"
rescue ex : Quo::TypeError
  puts "Type error: #{ex.message}"
end
```

## Debugging

When validation fails, the error message includes helpful context:

```
Quo::InvalidColumnError: Column 'statsu' does not exist in table 'contracts'.
Available columns: id, reference, status, amount_cents, user_id, company_id, created_at
```

This makes typos easy to spot and fix.
