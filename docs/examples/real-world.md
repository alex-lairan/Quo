# Real-World Patterns

Production-ready patterns using Quo.

## Repository Pattern

Encapsulate query logic in repositories:

```crystal
class UserRepository
  def initialize(@adapter : Quo::Adapters::Adapter)
  end

  private def relation
    UsersRelation.new(@adapter)
  end

  def find(id : Int64) : Hash(String, DB::Any)?
    relation.where(users: { id: id }).first
  end

  def find!(id : Int64) : Hash(String, DB::Any)
    relation.where(users: { id: id }).first!
  end

  def all_active
    relation.active.order(users: { name: :asc }).to_a
  end

  def admins
    relation.active.admins.to_a
  end

  def search(query : String)
    relation
      .where { |e| e[:users][:name].ilike("%#{query}%") }
      .order(users: { name: :asc })
      .limit(20)
      .to_a
  end

  def count_by_role
    Quo::Query.new(:users, @adapter)
      .select(users: [:role])
      .select_count(as: :count)
      .group(users: [:role])
      .to_a
  end
end

# Usage
repo = UserRepository.new(adapter)
user = repo.find!(123)
admins = repo.admins
results = repo.search("john")
```

## Pagination

### Simple Pagination

```crystal
struct Pagination
  property page : Int32
  property per_page : Int32
  property total : Int64

  def initialize(@page, @per_page, @total)
  end

  def offset
    (@page - 1) * @per_page
  end

  def total_pages
    (total / per_page).ceil.to_i
  end

  def has_next?
    page < total_pages
  end

  def has_prev?
    page > 1
  end
end

class PaginatedResult(T)
  property items : Array(T)
  property pagination : Pagination

  def initialize(@items, @pagination)
  end
end
```

### Paginated Repository

```crystal
class ContractRepository
  def initialize(@adapter : Quo::Adapters::Adapter)
  end

  private def relation
    ContractsRelation.new(@adapter)
  end

  def list_active(page : Int32 = 1, per_page : Int32 = 20)
    base = relation.active

    total = base.count
    pagination = Pagination.new(page, per_page, total)

    items = base
      .order(contracts: { created_at: :desc })
      .limit(per_page)
      .offset(pagination.offset)
      .to_a

    PaginatedResult.new(items, pagination)
  end
end

# Usage
repo = ContractRepository.new(adapter)
result = repo.list_active(page: 2, per_page: 25)

puts "Page #{result.pagination.page} of #{result.pagination.total_pages}"
result.items.each do |contract|
  puts contract["reference"]
end
```

## Service Objects

```crystal
class ContractSearchService
  def initialize(@adapter : Quo::Adapters::Adapter)
  end

  struct SearchParams
    property status : String?
    property min_amount : Int64?
    property company_id : Int64?
    property user_role : String?
    property page : Int32 = 1
    property per_page : Int32 = 20
  end

  def search(params : SearchParams)
    query = ContractsRelation.new(@adapter)
      .select(
        contracts: [:id, :reference, :status, :amount_cents],
        users: [:name],
        companies: [:name]
      )
      .join(:user)
      .join(:company)

    # Apply filters
    if status = params.status
      query = query.where(contracts: { status: status })
    end

    if min = params.min_amount
      query = query.where { |e| e[:contracts][:amount_cents] >= min }
    end

    if company_id = params.company_id
      query = query.where(contracts: { company_id: company_id })
    end

    if role = params.user_role
      query = query.where(users: { role: role })
    end

    # Pagination
    total = query.count
    items = query
      .order(contracts: { created_at: :desc })
      .limit(params.per_page)
      .offset((params.page - 1) * params.per_page)
      .to_a

    {items: items, total: total}
  end
end

# Usage
service = ContractSearchService.new(adapter)
params = ContractSearchService::SearchParams.new(
  status: "active",
  min_amount: 50000_i64,
  page: 1
)
result = service.search(params)
```

## Multi-Tenant Queries

```crystal
class TenantScope
  def initialize(@adapter : Quo::Adapters::Adapter, @tenant_id : Int64)
  end

  def contracts
    ContractsRelation.new(@adapter)
      .where(contracts: { tenant_id: @tenant_id })
  end

  def users
    UsersRelation.new(@adapter)
      .where(users: { tenant_id: @tenant_id })
  end
end

# Usage
tenant = TenantScope.new(adapter, current_tenant_id)
contracts = tenant.contracts.active.to_a
users = tenant.users.admins.to_a
```

## Caching Pattern

```crystal
class CachedUserRepository
  def initialize(@adapter : Quo::Adapters::Adapter, @cache : Cache)
  end

  def find(id : Int64) : Hash(String, DB::Any)?
    cache_key = "user:#{id}"

    @cache.fetch(cache_key, expires_in: 5.minutes) do
      UsersRelation.new(@adapter)
        .where(users: { id: id })
        .first
    end
  end

  def invalidate(id : Int64)
    @cache.delete("user:#{id}")
  end
end
```

## Query Objects

For complex, reusable queries:

```crystal
class ActiveContractsForDashboard
  def initialize(@adapter : Quo::Adapters::Adapter)
  end

  def call(user_id : Int64? = nil, min_amount : Int64 = 0_i64)
    query = ContractsRelation.new(@adapter)
      .select(
        contracts: [:reference, :status, :amount_cents, :created_at],
        users: [:name, :email],
        companies: [:name, :country]
      )
      .join(:user)
      .join(:company)
      .where(contracts: { status: "active" })
      .where(users: { active: true })
      .where(companies: { active: true })

    if uid = user_id
      query = query.where(contracts: { user_id: uid })
    end

    if min_amount > 0
      query = query.where { |e| e[:contracts][:amount_cents] >= min_amount }
    end

    query
      .order(contracts: { amount_cents: :desc })
      .limit(100)
      .to_a
  end
end

# Usage
query = ActiveContractsForDashboard.new(adapter)
results = query.call(user_id: 123, min_amount: 50000_i64)
```

## CRUD Repository

Complete repository with INSERT, UPDATE, DELETE:

```crystal
class UserRepository
  def initialize(@adapter : Quo::Adapters::Adapter)
  end

  private def relation
    UsersRelation.new(@adapter)
  end

  # CREATE
  def create(name : String, email : String) : Hash(String, DB::Any)?
    Quo::InsertQuery.new(:users, @adapter)
      .values(
        name: name,
        email: email,
        status: "pending",
        created_at: Time.utc
      )
      .returning(users: [:id, :name, :email, :created_at])
      .execute_returning_one
  end

  # READ
  def find(id : Int64) : Hash(String, DB::Any)?
    relation.where(users: { id: id }).first
  end

  def find!(id : Int64) : Hash(String, DB::Any)
    relation.where(users: { id: id }).first!
  end

  # UPDATE
  def update(id : Int64, **attrs) : Int64
    Quo::UpdateQuery.new(:users, @adapter)
      .set(attrs)
      .where(users: { id: id })
      .execute
  end

  def activate(id : Int64)
    Quo::UpdateQuery.new(:users, @adapter)
      .set(status: "active", activated_at: Time.utc)
      .where(users: { id: id })
      .execute
  end

  # DELETE
  def delete(id : Int64) : Int64
    Quo::DeleteQuery.new(:users, @adapter)
      .where(users: { id: id })
      .execute
  end

  def soft_delete(id : Int64)
    Quo::UpdateQuery.new(:users, @adapter)
      .set(deleted_at: Time.utc, status: "deleted")
      .where(users: { id: id })
      .execute
  end
end

# Usage
repo = UserRepository.new(adapter)
user = repo.create("Alice", "alice@example.com")
repo.activate(user.not_nil!["id"].as(Int64))
repo.update(1_i64, name: "Alice Smith")
repo.soft_delete(1_i64)
```

## Transactional Operations

```crystal
class OrderService
  def initialize(@adapter : Quo::Adapters::Adapter)
  end

  def place_order(user_id : Int64, items : Array(NamedTuple(product_id: Int64, quantity: Int32)))
    @adapter.transaction do |tx|
      # Create order
      order = tx.insert(:orders)
        .values(user_id: user_id, status: "pending", created_at: Time.utc)
        .returning(orders: [:id])
        .execute_returning_one
        .not_nil!

      order_id = order["id"].as(Int64)
      total = 0_i64

      # Create line items and update inventory
      items.each do |item|
        # Check inventory
        inventory = tx[:inventory]
          .where(inventory: { product_id: item[:product_id] })
          .first!

        available = inventory["quantity"].as(Int64)
        if available < item[:quantity]
          raise "Insufficient inventory for product #{item[:product_id]}"
        end

        # Get price
        product = tx[:products]
          .where(products: { id: item[:product_id] })
          .first!
        price = product["price_cents"].as(Int64)
        line_total = price * item[:quantity]
        total += line_total

        # Create line item
        tx.insert(:order_items)
          .values(
            order_id: order_id,
            product_id: item[:product_id],
            quantity: item[:quantity],
            price_cents: price
          )
          .execute

        # Decrease inventory
        tx.update(:inventory)
          .set(quantity: available - item[:quantity])
          .where(inventory: { product_id: item[:product_id] })
          .execute
      end

      # Update order total
      tx.update(:orders)
        .set(total_cents: total, status: "confirmed")
        .where(orders: { id: order_id })
        .execute

      order_id
    end
  end
end
```

## Query Logging in Production

```crystal
# config/initializers/database.cr
Quo::Logging.log_level = Quo::LogLevel::Info
Quo::Logging.slow_query_threshold = 100.milliseconds

# Metrics
Quo::Logging.subscribe do |event|
  Datadog.timing("db.query", event.duration.total_milliseconds, {
    operation: event.operation.to_s
  })
end

# Slow query alerts
Quo::Logging.on_slow_query do |event|
  Logger.warn("Slow query", {
    sql: event.sql,
    duration_ms: event.duration.total_milliseconds
  })

  if event.duration > 5.seconds
    AlertService.notify("Critical slow query detected")
  end
end
```

## Testing

```crystal
describe ContractRepository do
  it "finds active contracts" do
    adapter = Quo::Adapters::Test.new
    repo = ContractRepository.new(adapter)

    # Test SQL generation
    sql, params = ContractsRelation.new(adapter)
      .active
      .to_sql

    sql.should contain(%(WHERE "contracts"."status" = ?))
    params.should eq(["active"])
  end

  it "generates correct insert SQL" do
    adapter = Quo::Adapters::Test.new

    sql, params = Quo::InsertQuery.new(:users, adapter)
      .values(name: "Test", email: "test@example.com")
      .to_sql

    sql.should contain(%(INSERT INTO "users"))
    params.should eq(["Test", "test@example.com"])
  end
end
```
