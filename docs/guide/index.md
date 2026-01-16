# What is Quo?

Quo is a **query builder and relations library** for Crystal, inspired by [ROM-rb](https://rom-rb.org/).

## Key Principles

### 1. Explicit Over Implicit

Every column reference includes its table name:

```crystal
# Always explicit
.where(contracts: { status: "active" })
.select(users: [:id, :name], contracts: [:reference])

# Never ambiguous
# .where(status: "active")  # Which table? We don't do this.
```

### 2. Immutable Queries

Every query method returns a **new** query instance:

```crystal
base = relation.active

# These are different queries
recent = base.order(contracts: { created_at: :desc })
expensive = base.where { |e| e[:contracts][:amount] >= 10000 }

# base is unchanged - safe to reuse
```

### 3. Composable by Design

Build complex queries from simple, reusable parts:

```crystal
class ContractsRelation < Quo::Relation
  scope :active do
    query.where(contracts: { status: "active" })
  end

  scope :for_user, user_id : String do
    query.where(contracts: { user_id: user_id })
  end

  scope :high_value, min : Int64 do
    query.where { |e| e[:contracts][:amount_cents] >= min }
  end
end

# Compose scopes
relation.active.for_user("123").high_value(50000_i64)
```

### 4. Database Agnostic

Same API, different backends:

```crystal
# PostgreSQL
pg_adapter = Quo::Adapters::Postgres.new(pg_connection)

# SQLite
sqlite_adapter = Quo::Adapters::SQLite.new(sqlite_connection)

# Same relation works with both
ContractsRelation.new(pg_adapter).active.to_a
ContractsRelation.new(sqlite_adapter).active.to_a
```

## Core Components

| Component | Purpose |
|-----------|---------|
| **Query** | Immutable SQL query builder |
| **Relation** | Schema + scopes for a table |
| **Schema** | Column definitions and associations |
| **Expression** | Type-safe WHERE clause DSL |
| **Adapter** | Database-specific SQL generation |

## Comparison with Other Libraries

| Feature | Quo | Active Record style | Raw SQL |
|---------|-----|---------------------|---------|
| Explicit table qualification | Yes | No | Manual |
| Immutable queries | Yes | Usually no | N/A |
| Schema validation | Yes | Sometimes | No |
| Composable scopes | Yes | Yes | No |
| Type checking | Runtime | Compile-time | No |
| Learning curve | Medium | Low | High |

## When to Use Quo

**Good fit:**
- Applications with complex queries across multiple tables
- Teams that value explicit, readable SQL generation
- Projects needing runtime column/type validation
- Hexagonal architecture with repository pattern

**Consider alternatives:**
- Simple CRUD apps (consider full ORM)
- Performance-critical code (consider raw SQL)
- Teams unfamiliar with query builder patterns

## Next Steps

- [Getting Started](/guide/getting-started) - Install and configure Quo
- [Queries](/guide/queries) - Learn the query API
- [Relations](/guide/relations) - Define schemas and scopes
