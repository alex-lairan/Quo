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

## Custom Repository Implementation

If you need a different repository pattern than the one provided by `Quo::Repository`, you can easily build your own. Here's an example of a custom implementation:

### Pattern 1: Direct Query Access

Instead of using relations, directly use `Quo::Query`:

```crystal
class CustomAccountRepository
  getter adapter : Quo::Adapters::Adapter

  def initialize(@adapter)
  end

  def find_by_id(id : Int64) : Account?
    query = Quo::Query.new(:accounts, adapter)
      .select(accounts: [:id, :email, :status, :created_at, :updated_at])
      .where(accounts: {id: id})

    query.first.try { |row| map_to_account(row) }
  end

  def all_active : Array(Account)
    query = Quo::Query.new(:accounts, adapter)
      .select(accounts: [:id, :email, :status, :created_at, :updated_at])
      .where(accounts: {status: 1})
      .order(accounts: {created_at: :desc})

    query.to_a.map { |row| map_to_account(row) }
  end

  def create(email : String, status : Int32) : Account
    insert = Quo::InsertQuery.new(:accounts, adapter)
      .values(email: email, status: status)
      .returning(accounts: [:id, :email, :status, :created_at, :updated_at])

    row = insert.execute_returning.first
    map_to_account(row)
  end

  def update_status(id : Int64, status : Int32) : Bool
    update = Quo::UpdateQuery.new(:accounts, adapter)
      .set(status: status, updated_at: Time.utc)
      .where(accounts: {id: id})

    update.execute > 0
  end

  private def map_to_account(row : Quo::Row) : Account
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

**Usage:**

```crystal
DB.open("postgres://localhost/mydb") do |db|
  adapter = Quo::Adapters::Postgres.new(db)
  repo = CustomAccountRepository.new(adapter)

  # Use your repository
  account = repo.find_by_id(123_i64)
  accounts = repo.all_active
end
```

### Pattern 2: Query Builder Helper

Create a helper method to avoid repeating query setup:

```crystal
class CustomAccountRepository
  getter adapter : Quo::Adapters::Adapter

  def initialize(@adapter)
  end

  def find_by_email(email : String) : Account?
    accounts_query
      .where(accounts: {email: email})
      .first
      .try { |row| map_to_account(row) }
  end

  def search_by_domain(domain : String) : Array(Account)
    include Quo::ColumnHelpers  # Use t() helper

    accounts_query
      .where { |e| e[:accounts][:email].like("%@#{domain}") }
      .to_a
      .map { |row| map_to_account(row) }
  end

  # Helper to create base query
  private def accounts_query : Quo::Query
    Quo::Query.new(:accounts, adapter)
      .select(accounts: [:id, :email, :status, :created_at, :updated_at])
  end

  private def map_to_account(row : Quo::Row) : Account
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

### Pattern 3: Minimal Wrapper with ColumnHelpers

Use `Quo::ColumnHelpers` to access the `t()` helper for cleaner column references:

```crystal
class AccountRepository
  include Quo::ColumnHelpers  # Gives access to t() helper

  getter adapter : Quo::Adapters::Adapter

  def initialize(@adapter)
  end

  def find_with_profile(id : Int64) : AccountWithProfile?
    query = Quo::Query.new(:accounts, adapter)
      .join(:profiles, on: {accounts: :id, eq: {profiles: :account_id}})
      .select(
        t(:accounts)[:id],
        t(:accounts)[:email].aliased(:account_email),
        t(:profiles)[:display_name].aliased(:profile_name),
        t(:profiles)[:bio]
      )
      .where(accounts: {id: id})

    query.first.try { |row| map_to_account_with_profile(row) }
  end

  def search_active_with_filters(name_query : String? = nil) : Array(Account)
    query = Quo::Query.new(:accounts, adapter)
      .select(t(:accounts)[:id], t(:accounts)[:email], t(:accounts)[:status])
      .where(accounts: {status: 1})

    # Conditionally add filters
    if name_query
      query = query.where { |e| e[:accounts][:email].like("%#{name_query}%") }
    end

    query.to_a.map { |row| map_to_account(row) }
  end

  private def map_to_account_with_profile(row : Quo::Row) : AccountWithProfile
    AccountWithProfile.new(
      id: row["id"].as(Int64),
      email: row["account_email"].as(String),
      profile_name: row["profile_name"].as(String),
      bio: row["bio"]?.as(String?)
    )
  end

  private def map_to_account(row : Quo::Row) : Account
    Account.new(
      id: row["id"].as(Int64),
      email: row["email"].as(String),
      status: AccountStatus.new(row["status"].as(Int32))
    )
  end
end
```

### When to Use Custom Implementation

Choose a custom repository implementation when:

1. **You need a different abstraction** - The built-in `Repository` pattern doesn't fit your domain
2. **You want more control** - Direct query building gives you full control over SQL generation
3. **You prefer simplicity** - You don't need relations and scopes, just queries
4. **You're migrating** - Easier to migrate from another ORM by matching your existing patterns

### Combining with Built-in Repository

You can also extend `Quo::Repository` and add custom behavior:

```crystal
class AccountRepository < Quo::Repository
  relation :accounts, AccountsRelation

  # Use the relation (built-in pattern)
  def find_by_email(email : String) : Account?
    accounts.by_email(email).first.try { |row| map_to_account(row) }
  end

  # Or use direct queries (custom pattern)
  def complex_join_query : Array(Result)
    include Quo::ColumnHelpers

    query = Quo::Query.new(:accounts, adapter)
      .join(:profiles, on: {accounts: :id, eq: {profiles: :account_id}})
      .join(:subscriptions, on: {accounts: :id, eq: {subscriptions: :account_id}})
      .select(
        t(:accounts)[:email].aliased(:email),
        t(:profiles)[:display_name].aliased(:name),
        t(:subscriptions)[:tier].aliased(:tier)
      )
      .where { |e| (e[:accounts][:status] == 1) & (e[:subscriptions][:active] == true) }

    query.to_a.map { |row| map_to_result(row) }
  end

  private def map_to_result(row : Quo::Row) : Result
    # Custom mapping
  end

  private def map_to_account(row : Quo::Row) : Account
    # Standard mapping
  end
end
```

The key principle: **Use what works best for your use case**. Quo's flexibility allows you to choose the right level of abstraction for each repository.
