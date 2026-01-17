# Repositories

Repositories provide a clean abstraction layer between your domain logic and data access. Quo's `Repository` base class helps organize queries by aggregating related relations and providing direct adapter access for write operations.

## Why Use Repositories?

**Without repositories:**
- Query logic scattered across your application
- Adapters passed around everywhere
- Hard to test data access in isolation
- No clear ownership of data operations

**With repositories:**
- Centralized data access logic
- Clean interface for domain layer
- Easy to mock for testing
- Clear separation of concerns

## Basic Setup

### 1. Define Your Relations

First, create relations for your tables:

```crystal
class AccountsRelation < Quo::Relation
  schema :accounts do
    primary_key :id, Int64
    column :email, String
    column :status, Int32
    column :created_at, Time
    column :updated_at, Time
  end

  scope :active do
    query.where(accounts: {status: 1})
  end

  scope :by_email, email : String do
    query.where(accounts: {email: email})
  end
end

class ProfilesRelation < Quo::Relation
  schema :profiles do
    primary_key :id, Int64
    column :account_id, Int64
    column :display_name, String
    column :bio, String?
  end

  scope :by_account_id, account_id : Int64 do
    query.where(profiles: {account_id: account_id})
  end
end
```

### 2. Create Your Repository

Extend `Quo::Repository` and declare your relations:

```crystal
class AccountRepository < Quo::Repository
  # Declare relations this repository uses
  relation :accounts, AccountsRelation
  relation :profiles, ProfilesRelation

  # Implement repository methods
  def find_by_id(id : Int64) : Account?
    accounts
      .where(accounts: {id: id})
      .first
      .try { |row| account_from_row(row) }
  end

  def find_by_email(email : String) : Account?
    accounts
      .active
      .by_email(email)
      .first
      .try { |row| account_from_row(row) }
  end

  def create(email : String) : Account?
    result = Quo::InsertQuery.new(:accounts, adapter)
      .values(
        email: email,
        status: 0,
        created_at: Time.utc,
        updated_at: Time.utc
      )
      .returning(accounts: [:id, :email, :status, :created_at, :updated_at])
      .execute_returning_one

    result.try { |row| account_from_row(row) }
  end

  private def account_from_row(row : Quo::Row) : Account
    Account.new(
      id: row["id"].as(Int64),
      email: row["email"].as(String),
      status: AccountStatus.new(row["status"].as(Int32)),
      created_at: row["created_at"].as(Time),
      updated_at: row["updated_at"].as(Time)
    )
  end
end
```

### 3. Use the Repository

```crystal
# Create repository with adapter
adapter = Quo::Adapters::Postgres.new(db)
repo = AccountRepository.new(adapter)

# Read operations
account = repo.find_by_email("user@example.com")

# Write operations
new_account = repo.create("newuser@example.com")
```

## The `relation` Macro

The `relation` macro creates accessor methods for your relations:

```crystal
class MyRepository < Quo::Repository
  relation :accounts, AccountsRelation
  relation :orders, OrdersRelation
end

# Generates methods equivalent to:
# def accounts : AccountsRelation
#   AccountsRelation.new(@adapter)
# end
#
# def orders : OrdersRelation
#   OrdersRelation.new(@adapter)
# end
```

Each call creates a fresh relation instance, ensuring queries don't leak state:

```crystal
repo.accounts.active          # Adds active scope
repo.accounts                 # Fresh, no scope applied
```

## Read Operations

Use relations for all read operations. They provide:
- Type-safe queries
- Reusable scopes
- Composable conditions

```crystal
class OrderRepository < Quo::Repository
  relation :orders, OrdersRelation
  relation :order_items, OrderItemsRelation

  def find_by_id(id : Int64) : Order?
    orders
      .where(orders: {id: id})
      .first
      .try { |row| order_from_row(row) }
  end

  def recent_for_user(user_id : Int64, limit : Int32 = 10) : Array(Order)
    orders
      .by_user(user_id)
      .recent
      .limit(limit)
      .to_a
      .map { |row| order_from_row(row) }
  end

  def pending_count : Int64
    orders.pending.count
  end

  def exists?(id : Int64) : Bool
    orders.where(orders: {id: id}).exists?
  end
end
```

## Write Operations

Use `Quo::InsertQuery`, `Quo::UpdateQuery`, and `Quo::DeleteQuery` with the adapter:

```crystal
class AccountRepository < Quo::Repository
  relation :accounts, AccountsRelation

  def create(email : String, status : Int32 = 0) : Account?
    now = Time.utc

    result = Quo::InsertQuery.new(:accounts, adapter)
      .values(
        email: email,
        status: status,
        created_at: now,
        updated_at: now
      )
      .returning(accounts: [:id, :email, :status, :created_at, :updated_at])
      .execute_returning_one

    result.try { |row| account_from_row(row) }
  end

  def update_status(id : Int64, status : Int32) : Bool
    affected = Quo::UpdateQuery.new(:accounts, adapter)
      .set(status: status, updated_at: Time.utc)
      .where(accounts: {id: id})
      .execute

    affected > 0
  end

  def delete(id : Int64) : Bool
    affected = Quo::DeleteQuery.new(:accounts, adapter)
      .where(accounts: {id: id})
      .execute

    affected > 0
  end
end
```

## Advanced Patterns

### Joins Across Relations

```crystal
class AccountRepository < Quo::Repository
  relation :accounts, AccountsRelation
  relation :profiles, ProfilesRelation

  def find_with_profile(id : Int64)
    accounts
      .join(:profiles, on: {profiles: :account_id, eq: {accounts: :id}})
      .where(accounts: {id: id})
      .select(
        accounts: [:id, :email],
        profiles: [:display_name, :bio]
      )
      .first
  end
end
```

### Raw SQL for Complex Operations

Use the adapter directly for operations that don't fit the query builders:

```crystal
class LoginFailureRepository < Quo::Repository
  relation :login_failures, LoginFailuresRelation

  def increment(account_id : Int64) : Int32
    # Upsert with RETURNING
    result = adapter.execute(
      "INSERT INTO login_failures (account_id, count) VALUES ($1, 1) " \
      "ON CONFLICT (account_id) DO UPDATE SET count = login_failures.count + 1 " \
      "RETURNING count",
      [account_id] of DB::Any
    ).first?

    result.try { |row| row["count"].as(Int32) } || 1
  end
end
```

### Transactions

Wrap multiple operations in a transaction:

```crystal
class AccountRepository < Quo::Repository
  relation :accounts, AccountsRelation
  relation :profiles, ProfilesRelation

  def create_with_profile(email : String, display_name : String) : Account?
    adapter.transaction do |tx|
      # Create account
      account_row = Quo::InsertQuery.new(:accounts, tx.adapter)
        .values(email: email, status: 0, created_at: Time.utc, updated_at: Time.utc)
        .returning(accounts: [:id, :email, :status, :created_at, :updated_at])
        .execute_returning_one

      return nil unless account_row

      account_id = account_row["id"].as(Int64)

      # Create profile
      Quo::InsertQuery.new(:profiles, tx.adapter)
        .values(account_id: account_id, display_name: display_name)
        .execute

      account_from_row(account_row)
    end
  end
end
```

### Implementing Port Interfaces

Repositories work well with hexagonal architecture:

```crystal
# Domain layer - Port interface
module Domain::Ports
  abstract class AccountRepository
    abstract def find_by_id(id : Int64) : Account?
    abstract def find_by_email(email : String) : Account?
    abstract def create(email : String) : Account?
    abstract def update_status(id : Int64, status : AccountStatus) : Bool
    abstract def email_exists?(email : String) : Bool
  end
end

# Infrastructure layer - Adapter implementation
class QuoAccountRepository < Quo::Repository
  include Domain::Ports::AccountRepository

  relation :accounts, AccountsRelation

  def find_by_id(id : Int64) : Account?
    accounts
      .where(accounts: {id: id})
      .first
      .try { |row| account_from_row(row) }
  end

  def find_by_email(email : String) : Account?
    accounts
      .active
      .by_email(email)
      .first
      .try { |row| account_from_row(row) }
  end

  def create(email : String) : Account?
    # ... implementation
  end

  def update_status(id : Int64, status : AccountStatus) : Bool
    affected = Quo::UpdateQuery.new(:accounts, adapter)
      .set(status: status.value, updated_at: Time.utc)
      .where(accounts: {id: id})
      .execute

    affected > 0
  end

  def email_exists?(email : String) : Bool
    accounts.active.by_email(email).exists?
  end

  private def account_from_row(row : Quo::Row) : Account
    # ... mapping
  end
end
```

### Dependency Injection

With Athena or similar DI frameworks:

```crystal
@[ADI::Register(name: "account_repository", public: true)]
@[ADI::AsAlias(Domain::Ports::AccountRepository)]
class QuoAccountRepository < Quo::Repository
  include Domain::Ports::AccountRepository

  def initialize(adapter : Quo::Adapters::Adapter)
    super(adapter)
  end

  # ... methods
end
```

## Row Mapping

Convert database rows to domain entities:

```crystal
class AccountRepository < Quo::Repository
  relation :accounts, AccountsRelation

  def all_active : Array(Account)
    accounts
      .active
      .to_a
      .map { |row| account_from_row(row) }
  end

  private def account_from_row(row : Quo::Row) : Account
    Account.new(
      id: row["id"].as(Int64),
      email: row["email"].as(String),
      status: AccountStatus.new(row["status"].as(Int32)),
      created_at: row["created_at"].as(Time),
      updated_at: row["updated_at"].as(Time)
    )
  end
end
```

Handle nullable columns:

```crystal
private def profile_from_row(row : Quo::Row) : Profile
  Profile.new(
    id: row["id"].as(Int64),
    display_name: row["display_name"].as(String),
    bio: row["bio"]?.as(String?)  # Nullable
  )
end
```

## Testing Repositories

Use the test adapter for unit tests:

```crystal
describe AccountRepository do
  it "generates correct SQL for find_by_email" do
    adapter = Quo::Adapters::Test.new
    repo = AccountRepository.new(adapter)

    sql, params = repo.accounts.active.by_email("test@example.com").to_sql

    sql.should contain(%("accounts"."status" = $1))
    sql.should contain(%("accounts"."email" = $2))
    params.should eq([1, "test@example.com"])
  end
end
```

For integration tests, use a real database:

```crystal
describe AccountRepository, tags: "integration" do
  it "creates and retrieves accounts" do
    DB.open("postgres://localhost/test_db") do |db|
      adapter = Quo::Adapters::Postgres.new(db)
      repo = AccountRepository.new(adapter)

      # Create
      account = repo.create("test@example.com")
      account.should_not be_nil

      # Retrieve
      found = repo.find_by_email("test@example.com")
      found.should_not be_nil
      found.not_nil!.email.should eq("test@example.com")
    end
  end
end
```

## Best Practices

### 1. One Repository per Aggregate

```crystal
# Good: Repository per aggregate root
class AccountRepository < Quo::Repository
  relation :accounts, AccountsRelation
  relation :profiles, ProfilesRelation        # Belongs to Account
  relation :login_failures, LoginFailuresRelation  # Belongs to Account
end

# Bad: One giant repository
class DatabaseRepository < Quo::Repository
  relation :accounts, AccountsRelation
  relation :orders, OrdersRelation
  relation :products, ProductsRelation
  # Too many unrelated concerns
end
```

### 2. Keep Repositories Focused on Data Access

```crystal
# Good: Repository handles data access only
class AccountRepository < Quo::Repository
  def find_by_email(email : String) : Account?
    # Just data access
  end
end

# Bad: Repository handles business logic
class AccountRepository < Quo::Repository
  def create(email : String) : Account?
    raise "Invalid email" unless email.includes?("@")  # Business logic
    # ...
  end
end
```

### 3. Use Scopes for Reusable Conditions

```crystal
# In relation
scope :active do
  query.where(accounts: {status: 1})
end

scope :verified do
  query.where(accounts: {status: 2})
end

# In repository - compose scopes
def find_verified_by_email(email : String)
  accounts.active.verified.by_email(email).first
end
```

### 4. Return Domain Objects, Not Rows

```crystal
# Good: Returns domain entity
def find_by_id(id : Int64) : Account?
  accounts.where(accounts: {id: id}).first.try { |row| account_from_row(row) }
end

# Bad: Returns raw row
def find_by_id(id : Int64) : Quo::Row?
  accounts.where(accounts: {id: id}).first
end
```
