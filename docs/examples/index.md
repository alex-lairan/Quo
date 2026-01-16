# Examples

Real-world examples demonstrating Quo's features.

## Overview

| Example | Description |
|---------|-------------|
| [Basic Queries](./basic-queries) | Simple SELECT, WHERE, ORDER |
| [Complex Queries](./complex-queries) | Joins, expressions, scopes |
| [Real-World Patterns](./real-world) | Repository pattern, pagination |

## Quick Examples

### Simple Query

```crystal
users = UsersRelation.new(adapter)
  .where(users: { active: true })
  .order(users: { name: :asc })
  .limit(10)
  .to_a
```

### With Joins

```crystal
contracts = ContractsRelation.new(adapter)
  .select(contracts: [:reference], users: [:name], companies: [:name])
  .join(:user)
  .join(:company)
  .where(contracts: { status: "active" })
  .to_a
```

### Using Scopes

```crystal
class ContractsRelation < Quo::Relation
  scope :active { query.where(contracts: { status: "active" }) }
  scope :high_value, min : Int64 { query.where { |e| e[:contracts][:amount] >= min } }
end

results = ContractsRelation.new(adapter)
  .active
  .high_value(50000_i64)
  .to_a
```

### Complex Expressions

```crystal
results = UsersRelation.new(adapter)
  .where { |e|
    (e[:users][:role].in(["admin", "moderator"])) &
    (e[:users][:active] == true) &
    (e[:users][:score] >= 100)
  }
  .to_a
```
