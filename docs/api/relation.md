# Relation API

`Quo::Relation` is the base class for defining table schemas and scopes.

## Definition

```crystal
class MyRelation < Quo::Relation
  schema :table_name do
    # Schema definition
  end

  # Scopes
end
```

## Schema Macro

```crystal
schema(table_name : Symbol, &block)
```

Defines the table schema. Registers the schema globally for validation.

### primary_key

```crystal
primary_key(name : Symbol, type : T.class)
```

Define the primary key column.

```crystal
schema :users do
  primary_key :id, Int64
  primary_key :id, String  # For UUID/string IDs
end
```

### column

```crystal
column(name : Symbol, type : T.class)
```

Define a regular column.

```crystal
schema :users do
  column :name, String
  column :age, Int32
  column :balance, Float64
  column :active, Bool
  column :created_at, Time
end
```

### belongs_to

```crystal
belongs_to(name : Symbol, foreign_key : Symbol, table : Symbol, key : Symbol = :id)
```

Define a belongs_to association. The foreign key is on **this** table.

```crystal
schema :posts do
  belongs_to :user, :user_id, :users
  # posts.user_id -> users.id

  belongs_to :category, :cat_id, :categories, :uuid
  # posts.cat_id -> categories.uuid
end
```

### has_many

```crystal
has_many(name : Symbol, foreign_key : Symbol, table : Symbol, source_key : Symbol = :id)
```

Define a has_many association. The foreign key is on the **other** table.

```crystal
schema :users do
  has_many :posts, :user_id, :posts
  # users.id <- posts.user_id
end
```

### has_one

```crystal
has_one(name : Symbol, foreign_key : Symbol, table : Symbol, source_key : Symbol = :id)
```

Like has_many but semantically indicates single record.

```crystal
schema :users do
  has_one :profile, :user_id, :profiles
end
```

---

## Scope Macro

### scope (no arguments)

```crystal
scope(name : Symbol, &block)
```

Define a scope without arguments.

```crystal
scope :active do
  query.where(users: { active: true })
end

scope :by_recent do
  query.order(users: { created_at: :desc })
end
```

### scope (with arguments)

```crystal
scope(name : Symbol, *args, &block)
```

Define a scope with arguments.

```crystal
scope :by_role, role : String do
  query.where(users: { role: role })
end

scope :paginate, page : Int32, per_page : Int32 = 20 do
  query.limit(per_page).offset((page - 1) * per_page)
end
```

---

## Instance Methods

### initialize

```crystal
def initialize(adapter : Adapters::Adapter)
```

Create a new relation instance.

```crystal
relation = UsersRelation.new(adapter)
```

### table_name

```crystal
def table_name : Symbol
```

Returns the table name.

```crystal
UsersRelation.new(adapter).table_name  # => :users
```

### schema

```crystal
def schema : Schema
```

Returns the schema definition.

```crystal
schema = UsersRelation.new(adapter).schema
schema.columns      # Column definitions
schema.associations # Association definitions
```

---

## Query Methods

Relation delegates all query methods to an internal Query:

| Method | Description |
|--------|-------------|
| `select(**columns)` | SELECT columns |
| `where(**conditions)` | WHERE hash |
| `where { \|e\| ... }` | WHERE expression |
| `join(:assoc)` | JOIN via association |
| `left_join(:assoc)` | LEFT JOIN |
| `order(**columns)` | ORDER BY |
| `limit(n)` | LIMIT |
| `offset(n)` | OFFSET |
| `distinct` | DISTINCT |

---

## Terminal Methods

| Method | Returns |
|--------|---------|
| `to_a` | `Array(Hash(String, DB::Any))` |
| `first` | `Hash(String, DB::Any)?` |
| `first!` | `Hash(String, DB::Any)` |
| `count` | `Int64` |
| `exists?` | `Bool` |
| `to_sql` | `{String, Array(DB::Any)}` |
| `count_sql` | `{String, Array(DB::Any)}` |

---

## Class Methods

Scopes are available as class methods:

```crystal
# These are equivalent:
UsersRelation.new(adapter).active
UsersRelation.active(adapter)

# With arguments:
UsersRelation.new(adapter).by_role("admin")
UsersRelation.by_role(adapter, "admin")
```

---

## Complete Example

```crystal
class ContractsRelation < Quo::Relation
  schema :contracts do
    primary_key :id, Int64
    column :reference, String
    column :status, String
    column :amount_cents, Int64
    column :user_id, Int64
    column :company_id, Int64
    column :created_at, Time

    belongs_to :user, :user_id, :users
    belongs_to :company, :company_id, :companies
  end

  scope :active do
    query.where(contracts: { status: "active" })
  end

  scope :pending do
    query.where(contracts: { status: "pending" })
  end

  scope :high_value, min : Int64 do
    query.where { |e| e[:contracts][:amount_cents] >= min }
  end

  scope :for_user, user_id : Int64 do
    query.where(contracts: { user_id: user_id })
  end

  scope :with_user do
    query.join(:user)
  end

  scope :recent do
    query.order(contracts: { created_at: :desc })
  end
end

# Usage
results = ContractsRelation.new(adapter)
  .active
  .high_value(50000_i64)
  .with_user
  .recent
  .limit(20)
  .to_a
```
