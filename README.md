# Quo

A ROM-inspired query builder for Crystal with explicit, unambiguous syntax, immutable queries, and composable relations.

## Features

- **Explicit Syntax**: All columns are table-qualified (e.g., `contracts[:status]`), eliminating ambiguity in complex queries
- **Immutable Queries**: Every method returns a new query instance, enabling safe composition and branching
- **Type-Safe**: Runtime column validation and type checking catch errors before they reach the database
- **ROM-Inspired Architecture**: Relations, scopes, and repositories for clean data access patterns
- **Multiple Database Support**: PostgreSQL, MySQL, and SQLite adapters with connection pooling
- **Rich Query Building**: Complex WHERE expressions, joins, subqueries, aggregations, and more
- **Repository Pattern**: Clean data access layer with entity mapping and CRUD shortcuts
- **Comprehensive Logging**: Query instrumentation with timing breakdowns and slow query detection
- **Query Caching**: TTL-based caching with tag-based invalidation
- **Transaction Support**: ACID transactions with savepoints and isolation levels

## Installation

Add this to your application's `shard.yml`:

```yaml
dependencies:
  quo:
    github: alexandrelairan/quo
    version: ~> 0.1.0

  # Choose your database driver
  pg:
    github: will/crystal-pg
    version: ~> 0.28.0
  # OR
  sqlite3:
    github: crystal-lang/crystal-sqlite3
    version: ~> 0.21.0
  # OR
  mysql:
    github: crystal-lang/crystal-mysql
```

## Quick Start

### Define a Relation

```crystal
require "quo"
require "pg"

class UsersRelation < Quo::Relation
  schema :users do
    primary_key :id, Int64
    column :email, String
    column :name, String
    column :active, Bool
    column :created_at, Time

    has_many :posts, :user_id, :posts
  end

  scope :active do
    query.where(users: {active: true})
  end

  scope :created_after do |date|
    query.where { |e| e[:users][:created_at] > date }
  end
end
```

### Query with Explicit Syntax

```crystal
# Create an adapter
adapter = Quo::Adapters::Postgres.new("postgres://localhost/mydb")

# Build and execute queries
users = UsersRelation.new(adapter)
  .active
  .created_after(1.year.ago)
  .order(users: {name: :asc})
  .limit(10)
  .to_a

users.each do |row|
  puts "#{row["name"]} - #{row["email"]}"
end
```

### Complex Queries with Joins

```crystal
class PostsRelation < Quo::Relation
  schema :posts do
    primary_key :id, Int64
    column :title, String
    column :user_id, Int64

    belongs_to :user, :user_id, :users
  end
end

# Join using defined associations
posts = PostsRelation.new(adapter)
  .select(posts: [:id, :title], users: [:name])
  .join(:user)
  .where { |e| e[:users][:active] == true }
  .to_a
```

### Repository Pattern

```crystal
class UserRepository < Quo::Repository
  relation :users, UsersRelation

  entity :user, User do
    map :id, Int64
    map :email, String
    map :name, String
  end

  def find_by_email(email : String) : User?
    users
      .where(users: {email: email})
      .first
      .try { |row| user_from_row(row) }
  end

  def create(email : String, name : String) : User?
    insert_returning(:users, [:id, :email, :name],
      email: email,
      name: name,
      active: true
    ).try { |row| user_from_row(row) }
  end
end

repo = UserRepository.new(adapter)
user = repo.find_by_email("user@example.com")
```

### Mutations

```crystal
# INSERT
relation
  .insert(users: {email: "new@example.com", name: "John"})
  .execute

# INSERT with RETURNING (PostgreSQL)
row = relation
  .insert(users: {email: "new@example.com", name: "John"})
  .returning(users: [:id, :email])
  .execute

# UPDATE
relation
  .update(users: {active: false})
  .where(users: {email: "old@example.com"})
  .execute

# DELETE
relation
  .delete
  .where { |e| e[:users][:created_at] < 1.year.ago }
  .execute
```

### Expression Building

```crystal
relation.where { |e|
  (e[:users][:active] == true) &
  (
    (e[:users][:email].like("%@example.com")) |
    (e[:users][:name].in(["Alice", "Bob"]))
  )
}
```

### Logging and Instrumentation

```crystal
Quo::Logging.log_level = Quo::LogLevel::Info
Quo::Logging.slow_query_threshold = 50.milliseconds

Quo::Logging.subscribe do |event|
  puts "SQL: #{event.sql}"
  puts "Params: #{event.params.inspect}"
  puts "Duration: #{event.duration.total_milliseconds}ms"
  puts "  - Compile: #{event.compile_time.total_milliseconds}ms"
  puts "  - Execute: #{event.execute_time.total_milliseconds}ms"
end
```

### Connection Pooling

```crystal
# Use pooled adapters for multi-threaded applications
adapter = Quo::Adapters::PooledPostgres.new(
  "postgres://localhost/mydb",
  pool_size: 10,
  pool_timeout: 5.seconds
)
```

## Why Quo?

### Explicit Over Implicit

Many query builders allow bare column names, leading to ambiguity:

```crystal
# Ambiguous - which table's 'name' column?
query.where(name: "John")
```

Quo requires table qualification:

```crystal
# Clear and unambiguous
query.where(users: {name: "John"})
```

### Immutable Queries Enable Safe Composition

```crystal
base = UsersRelation.new(adapter).active

# Branch without affecting the original
admins = base.where(users: {role: "admin"})
moderators = base.where(users: {role: "moderator"})

# base remains unchanged
```

### Type Safety Catches Errors Early

```crystal
# Typo in column name caught at runtime validation
relation.where(users: {emal: "test@example.com"})
# => Quo::ColumnNotFoundError: Column 'emal' not found in table 'users'

# Type mismatch caught before query execution
relation.where(users: {active: "yes"})
# => Quo::TypeMismatchError: Expected Bool for column 'active', got String
```

## Documentation

- [Getting Started](docs/guide/getting-started.md)
- [Queries](docs/guide/queries.md)
- [Expressions](docs/guide/expressions.md)
- [Joins](docs/guide/joins.md)
- [Relations & Schemas](docs/guide/relations.md)
- [Scopes](docs/guide/scopes.md)
- [Repositories](docs/guide/repositories.md)
- [Mutations (INSERT/UPDATE/DELETE)](docs/guide/mutations.md)
- [Transactions](docs/guide/transactions.md)
- [Connection Pooling](docs/guide/connection-pooling.md)
- [Logging & Instrumentation](docs/guide/logging.md)
- [Query Caching](docs/guide/caching.md)
- [Database Adapters](docs/guide/adapters.md)
- [Introspection](docs/guide/introspection.md)

## Examples

Check out the [examples](examples/) directory for complete working examples:

- [demo.cr](examples/demo.cr) - Basic usage with relations and scopes
- [logging_example.cr](examples/logging_example.cr) - Query logging and instrumentation
- [repository_example.cr](examples/repository_example.cr) - Repository pattern with entity mapping

## Requirements

- Crystal >= 1.10.0
- Database driver (pg, sqlite3, or mysql)

## Contributing

1. Fork it (https://github.com/alexandrelairan/quo/fork)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## License

MIT License. See [LICENSE](LICENSE) for details.

## Author

Alexandre Lairan

## Acknowledgments

Quo is inspired by [ROM-rb](https://rom-rb.org/), the Ruby data mapping and persistence toolkit.
