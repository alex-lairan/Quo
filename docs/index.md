---
layout: home

hero:
  name: Quo
  text: Crystal Query Builder
  tagline: Explicit, composable, ROM-inspired query builder for Crystal
  image:
    src: /logo.svg
    alt: Quo
  actions:
    - theme: brand
      text: Get Started
      link: /guide/getting-started
    - theme: alt
      text: View on GitHub
      link: https://github.com/alex-lairan/Quo

features:
  - icon:
      src: /logo.svg
    title: Explicit by Design
    details: All columns are table-qualified. No ambiguity, no magic. contracts[:status] not just status.
  - icon:
      src: /logo.svg
    title: Fully Composable
    details: Immutable queries that branch and combine. Build complex queries from simple, reusable parts.
  - icon:
      src: /logo.svg
    title: Relations & Scopes
    details: ROM-rb inspired architecture. Define schemas, create reusable scopes, associations for joins.
  - icon:
      src: /logo.svg
    title: Type Safe
    details: Column validation and type checking at runtime. Catch typos before they hit the database.
  - icon:
      src: /logo.svg
    title: Database Agnostic
    details: PostgreSQL and SQLite adapters. Same API, different backends. Easy to add more.
  - icon:
      src: /logo.svg
    title: Test Friendly
    details: Immutable design makes testing easy. Test adapter for unit tests without database.
---

## Quick Example

```crystal
require "quo"

# Define a relation with schema and scopes
class ContractsRelation < Quo::Relation
  schema :contracts do
    primary_key :id, String
    column :reference, String
    column :status, String
    column :amount_cents, Int64
    column :user_id, String

    belongs_to :user, :user_id, :users
  end

  scope :active do
    query.where(contracts: { status: "active" })
  end

  scope :high_value, min : Int64 do
    query.where { |e| e[:contracts][:amount_cents] >= min }
  end
end

# Use with SQLite
DB.open "sqlite3:./myapp.db" do |db|
  adapter = Quo::Adapters::SQLite.new(db)

  # Compose queries fluently
  results = ContractsRelation.new(adapter)
    .select(contracts: [:reference, :amount_cents], users: [:name])
    .join(:user)
    .active
    .high_value(100_000_i64)
    .order(contracts: { amount_cents: :desc })
    .limit(20)
    .to_a
end
```

## Why Quo?

### Explicit Table Qualification

Every column reference includes its table name. No guessing, no conflicts:

```crystal
# Quo - always explicit
.where(contracts: { status: "active" })
.where { |e| e[:contracts][:amount_cents] >= 1000 }

# Not ambiguous like:
# .where(status: "active")  # Which table?
```

### Immutable Queries

Every method returns a new query. Safe to branch and reuse:

```crystal
base = ContractsRelation.new(adapter).active

# Create different queries from the same base
pending = base.where(contracts: { status: "pending" })
high_value = base.high_value(50000_i64)

# base is unchanged
```

### Association Joins

Define associations once, use them everywhere:

```crystal
class ContractsRelation < Quo::Relation
  schema :contracts do
    # ...
    belongs_to :user, :user_id, :users
    belongs_to :company, :company_id, :companies
  end
end

# Join by association name - no need to remember columns
ContractsRelation.new(adapter)
  .join(:user)      # contracts.user_id = users.id
  .join(:company)   # contracts.company_id = companies.id
```

### Runtime Validation

Catch column typos and type mismatches before they hit the database:

```crystal
# Typo in column name
.select(contracts: [:statsu])  # InvalidColumnError!

# Wrong type for column
.where(contracts: { amount_cents: "not a number" })  # TypeError!
```
