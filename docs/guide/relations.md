# Relations

Relations define the structure of your database tables and provide reusable query scopes.

## Defining a Relation

```crystal
class UsersRelation < Quo::Relation
  schema :users do
    primary_key :id, Int64

    column :email, String
    column :name, String
    column :role, String
    column :active, Bool
    column :score, Int32
    column :created_at, Time
  end
end
```

## Schema Definition

### Primary Key

```crystal
schema :users do
  primary_key :id, String      # String/UUID primary key
  primary_key :id, Int64       # Auto-increment integer
end
```

### Columns

Supported types:

| Crystal Type | SQL Type | Notes |
|--------------|----------|-------|
| `String` | TEXT/VARCHAR | |
| `Int32` | INTEGER | |
| `Int64` | BIGINT | |
| `Float64` | DOUBLE/REAL | |
| `Bool` | BOOLEAN/INTEGER | SQLite uses 0/1 |
| `Time` | TIMESTAMP | SQLite uses TEXT |

```crystal
schema :users do
  column :name, String
  column :age, Int32
  column :balance, Float64
  column :active, Bool
  column :created_at, Time
end
```

### Associations

Define relationships for joins:

```crystal
class UsersRelation < Quo::Relation
  schema :users do
    primary_key :id, Int64
    column :name, String

    # User has many posts (posts.user_id -> users.id)
    has_many :posts, :user_id, :posts

    # User has one profile (profiles.user_id -> users.id)
    has_one :profile, :user_id, :profiles
  end
end

class PostsRelation < Quo::Relation
  schema :posts do
    primary_key :id, Int64
    column :user_id, Int64
    column :title, String

    # Post belongs to user (posts.user_id -> users.id)
    belongs_to :user, :user_id, :users
  end
end
```

### Association with Custom Keys

When foreign/primary keys don't follow conventions:

```crystal
class ContractsRelation < Quo::Relation
  schema :contracts do
    primary_key :id, String
    column :payment_provider_uuid, String

    # Custom key: contracts.payment_provider_uuid -> stripe_subscriptions.stripe_id
    belongs_to :stripe_subscription, :payment_provider_uuid, :stripe_subscriptions, :stripe_id
  end
end
```

## Using Relations

### Basic Queries

```crystal
users = UsersRelation.new(adapter)

# All users
all = users.to_a

# With conditions
active = users
  .where(users: { active: true })
  .to_a

# With ordering and limit
recent = users
  .order(users: { created_at: :desc })
  .limit(10)
  .to_a
```

### With Scopes

```crystal
class UsersRelation < Quo::Relation
  schema :users do
    # ...
  end

  scope :active do
    query.where(users: { active: true })
  end

  scope :admins do
    query.where(users: { role: "admin" })
  end
end

# Use scopes
admins = UsersRelation.new(adapter).active.admins.to_a
```

## Accessing Schema Info

```crystal
relation = UsersRelation.new(adapter)

# Table name
relation.table_name  # => :users

# Schema
schema = relation.schema
schema.columns       # => Hash of column definitions
schema.primary_key   # => :id
schema.associations  # => Hash of associations
```

## Schema Registry

All schemas are automatically registered and available for validation:

```crystal
# Check if a schema is registered
Quo::SchemaRegistry.registered?(:users)  # => true

# Get a schema
schema = Quo::SchemaRegistry.get(:users)

# Validation happens automatically
relation.select(users: [:nonexistent])  # => InvalidColumnError!
```
