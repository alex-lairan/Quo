# Getting Started

## Installation

Add Quo to your `shard.yml`:

```yaml
dependencies:
  quo:
    github: alex-lairan/Quo
    version: ~> 0.1.0
```

Then run:

```bash
shards install
```

## Database Driver

Install the appropriate database driver:

::: code-group

```yaml [PostgreSQL]
dependencies:
  pg:
    github: will/crystal-pg
    version: ~> 0.28.0
```

```yaml [SQLite]
dependencies:
  sqlite3:
    github: crystal-lang/crystal-sqlite3
    version: ~> 0.21.0
```

:::

## Basic Setup

### 1. Require Quo and Database Driver

```crystal
require "quo"
require "sqlite3"  # or "pg" for PostgreSQL
```

### 2. Create Database Connection

::: code-group

```crystal [SQLite]
DB.open "sqlite3:./myapp.db" do |db|
  adapter = Quo::Adapters::SQLite.new(db)
  # Use adapter...
end
```

```crystal [PostgreSQL]
DB.open "postgres://localhost/myapp_dev" do |db|
  adapter = Quo::Adapters::Postgres.new(db)
  # Use adapter...
end
```

:::

### 3. Define a Relation

```crystal
class UsersRelation < Quo::Relation
  schema :users do
    primary_key :id, Int64
    column :email, String
    column :name, String
    column :active, Bool
    column :created_at, Time
  end

  scope :active do
    query.where(users: { active: true })
  end

  scope :by_email, email : String do
    query.where(users: { email: email })
  end
end
```

### 4. Execute Queries

```crystal
# Get all active users
users = UsersRelation.new(adapter)
  .active
  .order(users: { created_at: :desc })
  .to_a

# Find by email
user = UsersRelation.new(adapter)
  .by_email("alice@example.com")
  .first

# Count
count = UsersRelation.new(adapter).active.count
```

## Complete Example

```crystal
require "sqlite3"
require "quo"

# Define relations
class UsersRelation < Quo::Relation
  schema :users do
    primary_key :id, Int64
    column :name, String
    column :email, String
    column :role, String
    column :active, Bool

    has_many :posts, :user_id, :posts
  end

  scope :active do
    query.where(users: { active: true })
  end

  scope :admins do
    query.where(users: { role: "admin" })
  end
end

class PostsRelation < Quo::Relation
  schema :posts do
    primary_key :id, Int64
    column :user_id, Int64
    column :title, String
    column :status, String

    belongs_to :user, :user_id, :users
  end

  scope :published do
    query.where(posts: { status: "published" })
  end
end

# Use in application
DB.open "sqlite3::memory:" do |db|
  adapter = Quo::Adapters::SQLite.new(db)

  # Create tables (in real app, use migrations)
  db.exec "CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT, email TEXT, role TEXT, active INTEGER)"
  db.exec "CREATE TABLE posts (id INTEGER PRIMARY KEY, user_id INTEGER, title TEXT, status TEXT)"

  # Insert data
  db.exec "INSERT INTO users (name, email, role, active) VALUES (?, ?, ?, ?)", "Alice", "alice@example.com", "admin", 1
  db.exec "INSERT INTO posts (user_id, title, status) VALUES (?, ?, ?)", 1, "Hello World", "published"

  # Query with Quo
  users = UsersRelation.new(adapter).active.admins.to_a
  puts users.inspect

  # Join query
  posts_with_authors = PostsRelation.new(adapter)
    .select(posts: [:title], users: [:name])
    .join(:user)
    .published
    .to_a
  puts posts_with_authors.inspect
end
```

## Terminal Methods

| Method | Returns | Description |
|--------|---------|-------------|
| `.to_a` | `Array(Hash)` | All results |
| `.first` | `Hash?` | First result or nil |
| `.first!` | `Hash` | First result or raises |
| `.count` | `Int64` | Row count |
| `.exists?` | `Bool` | True if any rows match |
| `.to_sql` | `{String, Array}` | SQL and params (debug) |

## Next Steps

- [Queries](/guide/queries) - Deep dive into query building
- [Expressions](/guide/expressions) - Complex WHERE clauses
- [Relations](/guide/relations) - Schema and scope patterns
- [Joins](/guide/joins) - Association-based joins
