# Repository API

Base class for organizing data access logic with relation aggregation.

## Repository

Abstract base class for repositories.

```crystal
abstract class Quo::Repository
  getter adapter : Adapters::Adapter

  def initialize(@adapter : Adapters::Adapter)
end
```

### Constructor

| Parameter | Type | Description |
|-----------|------|-------------|
| `adapter` | `Adapters::Adapter` | Database adapter for queries |

### Properties

| Property | Type | Description |
|----------|------|-------------|
| `adapter` | `Adapters::Adapter` | The adapter instance (read-only) |

---

## relation Macro

Declares a relation accessor method on the repository.

```crystal
macro relation(name, klass)
```

| Parameter | Type | Description |
|-----------|------|-------------|
| `name` | `Symbol` | Method name for the accessor |
| `klass` | `Type` | Relation class to instantiate |

### Generated Method

For each `relation` declaration, a method is generated:

```crystal
relation :accounts, AccountsRelation

# Generates:
def accounts : AccountsRelation
  AccountsRelation.new(@adapter)
end
```

### Behavior

- Creates a new relation instance on each call
- Passes the repository's adapter to the relation
- Relation instances are isolated (no shared state)

---

## Example Implementation

### Basic Repository

```crystal
class UserRepository < Quo::Repository
  relation :users, UsersRelation
  relation :profiles, ProfilesRelation

  def find_by_id(id : Int64) : User?
    users
      .where(users: {id: id})
      .first
      .try { |row| user_from_row(row) }
  end

  def find_by_email(email : String) : User?
    users
      .active
      .by_email(email)
      .first
      .try { |row| user_from_row(row) }
  end

  def create(email : String, name : String) : User?
    result = Quo::InsertQuery.new(:users, adapter)
      .values(email: email, name: name, created_at: Time.utc)
      .returning(users: [:id, :email, :name, :created_at])
      .execute_returning_one

    result.try { |row| user_from_row(row) }
  end

  def update(id : Int64, name : String) : Bool
    affected = Quo::UpdateQuery.new(:users, adapter)
      .set(name: name, updated_at: Time.utc)
      .where(users: {id: id})
      .execute

    affected > 0
  end

  def delete(id : Int64) : Bool
    affected = Quo::DeleteQuery.new(:users, adapter)
      .where(users: {id: id})
      .execute

    affected > 0
  end

  def email_exists?(email : String) : Bool
    users.active.by_email(email).exists?
  end

  def count_active : Int64
    users.active.count
  end

  private def user_from_row(row : Quo::Row) : User
    User.new(
      id: row["id"].as(Int64),
      email: row["email"].as(String),
      name: row["name"].as(String),
      created_at: row["created_at"].as(Time)
    )
  end
end
```

### Usage

```crystal
# Initialize with adapter
adapter = Quo::Adapters::Postgres.new(db)
repo = UserRepository.new(adapter)

# Read operations via relations
user = repo.find_by_email("user@example.com")
exists = repo.email_exists?("test@example.com")
count = repo.count_active

# Write operations
new_user = repo.create("new@example.com", "New User")
updated = repo.update(123_i64, "Updated Name")
deleted = repo.delete(456_i64)
```

---

## Relation Access

### Fresh Instance Each Call

Each relation accessor returns a new instance:

```crystal
repo.users          # New UsersRelation instance
repo.users.active   # Adds scope
repo.users          # Fresh instance, no scope
```

### Chaining Scopes

```crystal
# All these work independently
repo.users.active.to_a
repo.users.by_email("test@test.com").first
repo.users.active.recent.limit(10).to_a
```

---

## Write Operations

### Insert

```crystal
def create(data) : Entity?
  result = Quo::InsertQuery.new(:table, adapter)
    .values(field: data.field)
    .returning(table: [:id, :field])
    .execute_returning_one

  result.try { |row| entity_from_row(row) }
end
```

### Update

```crystal
def update(id, changes) : Bool
  affected = Quo::UpdateQuery.new(:table, adapter)
    .set(field: changes.field, updated_at: Time.utc)
    .where(table: {id: id})
    .execute

  affected > 0
end
```

### Delete

```crystal
def delete(id) : Bool
  affected = Quo::DeleteQuery.new(:table, adapter)
    .where(table: {id: id})
    .execute

  affected > 0
end
```

### Upsert (Raw SQL)

```crystal
def upsert(id, value) : Int32
  result = adapter.execute(
    "INSERT INTO counters (id, count) VALUES ($1, 1) " \
    "ON CONFLICT (id) DO UPDATE SET count = counters.count + 1 " \
    "RETURNING count",
    [id] of DB::Any
  ).first?

  result.try { |row| row["count"].as(Int32) } || 1
end
```

---

## Transactions

Use the adapter's transaction method:

```crystal
def create_with_related(data) : Entity?
  adapter.transaction do |tx|
    # Insert main entity
    main_row = Quo::InsertQuery.new(:main, tx.adapter)
      .values(name: data.name)
      .returning(main: [:id, :name])
      .execute_returning_one

    return nil unless main_row

    main_id = main_row["id"].as(Int64)

    # Insert related entity
    Quo::InsertQuery.new(:related, tx.adapter)
      .values(main_id: main_id, value: data.value)
      .execute

    entity_from_row(main_row)
  end
end
```

---

## Row Mapping

### Basic Mapping

```crystal
private def user_from_row(row : Quo::Row) : User
  User.new(
    id: row["id"].as(Int64),
    email: row["email"].as(String),
    name: row["name"].as(String)
  )
end
```

### Nullable Fields

```crystal
private def profile_from_row(row : Quo::Row) : Profile
  Profile.new(
    id: row["id"].as(Int64),
    bio: row["bio"]?.as(String?),           # Nullable
    avatar_url: row["avatar_url"]?.as(String?)
  )
end
```

### Enum Fields

```crystal
private def account_from_row(row : Quo::Row) : Account
  Account.new(
    id: row["id"].as(Int64),
    status: AccountStatus.new(row["status"].as(Int32))
  )
end
```

### Joined Data

```crystal
def find_with_profile(id : Int64) : UserWithProfile?
  row = users
    .join(:profiles, on: {profiles: :user_id, eq: {users: :id}})
    .where(users: {id: id})
    .select(users: [:id, :email], profiles: [:display_name])
    .first

  return nil unless row

  UserWithProfile.new(
    id: row["id"].as(Int64),
    email: row["email"].as(String),
    display_name: row["display_name"].as(String)
  )
end
```

---

## Interface Implementation

Implement abstract repository interfaces:

```crystal
# Port interface (domain layer)
abstract class UserRepositoryPort
  abstract def find_by_id(id : Int64) : User?
  abstract def find_by_email(email : String) : User?
  abstract def create(email : String, name : String) : User?
  abstract def update(id : Int64, name : String) : Bool
  abstract def delete(id : Int64) : Bool
end

# Concrete implementation (infrastructure layer)
class QuoUserRepository < Quo::Repository
  include UserRepositoryPort

  relation :users, UsersRelation

  def find_by_id(id : Int64) : User?
    # Implementation
  end

  # ... other methods
end
```

---

## Multiple Relations

```crystal
class OrderRepository < Quo::Repository
  relation :orders, OrdersRelation
  relation :order_items, OrderItemsRelation
  relation :products, ProductsRelation

  def find_with_items(id : Int64)
    order_row = orders.where(orders: {id: id}).first
    return nil unless order_row

    items = order_items
      .by_order_id(id)
      .join(:products, on: {products: :id, eq: {order_items: :product_id}})
      .to_a

    order_with_items_from_rows(order_row, items)
  end
end
```

---

## Testing

### Unit Tests with Test Adapter

```crystal
describe UserRepository do
  it "generates correct SQL for find_by_email" do
    adapter = Quo::Adapters::Test.new
    repo = UserRepository.new(adapter)

    sql, params = repo.users.active.by_email("test@test.com").to_sql

    sql.should contain(%("users"."status" = $1))
    sql.should contain(%("users"."email" = $2))
    params.should eq([1, "test@test.com"])
  end

  it "generates correct insert SQL" do
    adapter = Quo::Adapters::Test.new
    repo = UserRepository.new(adapter)

    sql, params = Quo::InsertQuery.new(:users, adapter)
      .values(email: "new@test.com", name: "Test")
      .to_sql

    sql.should contain("INSERT INTO")
    params.should contain("new@test.com")
  end
end
```

### Integration Tests

```crystal
describe UserRepository, tags: "integration" do
  it "creates and retrieves users" do
    DB.open("postgres://localhost/test") do |db|
      adapter = Quo::Adapters::Postgres.new(db)
      repo = UserRepository.new(adapter)

      user = repo.create("test@test.com", "Test User")
      user.should_not be_nil

      found = repo.find_by_email("test@test.com")
      found.should_not be_nil
      found.not_nil!.name.should eq("Test User")
    end
  end
end
```

---

## Best Practices

| Practice | Description |
|----------|-------------|
| One per aggregate | Create one repository per aggregate root |
| Data access only | Keep business logic out of repositories |
| Return domain objects | Map rows to entities, don't expose raw rows |
| Use scopes | Define reusable conditions in relations |
| Isolate queries | Each method should be independent |
