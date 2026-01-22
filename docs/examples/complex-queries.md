# Complex Queries

Advanced examples with joins, expressions, and scopes.

## Multi-Table Setup

```crystal
class UsersRelation < Quo::Relation
  schema :users do
    primary_key :id, Int64
    column :name, String
    column :email, String
    column :role, String
    column :active, Bool

    has_many :posts, :user_id, :posts
    has_many :contracts, :user_id, :contracts
  end

  scope :active { query.where(users: { active: true }) }
  scope :admins { query.where(users: { role: "admin" }) }
end

class PostsRelation < Quo::Relation
  schema :posts do
    primary_key :id, Int64
    column :user_id, Int64
    column :title, String
    column :status, String
    column :view_count, Int64
    column :published_at, Time

    belongs_to :user, :user_id, :users
  end

  scope :published { query.where(posts: { status: "published" }) }
  scope :popular { query.where { |e| e[:posts][:view_count] >= 1000 } }
end

class ContractsRelation < Quo::Relation
  schema :contracts do
    primary_key :id, Int64
    column :user_id, Int64
    column :company_id, Int64
    column :reference, String
    column :status, String
    column :amount_cents, Int64

    belongs_to :user, :user_id, :users
    belongs_to :company, :company_id, :companies
  end

  scope :active { query.where(contracts: { status: "active" }) }
  scope :high_value, min : Int64 { query.where { |e| e[:contracts][:amount_cents] >= min } }
end

class CompaniesRelation < Quo::Relation
  schema :companies do
    primary_key :id, Int64
    column :name, String
    column :country, String
    column :active, Bool
  end

  scope :active { query.where(companies: { active: true }) }
end
```

## Join Queries

### Simple Join

```crystal
# Posts with author info
posts_with_authors = PostsRelation.new(adapter)
  .select(posts: [:title, :status], users: [:name, :email])
  .join(:user)
  .published
  .to_a
```

### Multiple Joins

```crystal
# Contracts with user and company
contracts = ContractsRelation.new(adapter)
  .select(
    contracts: [:reference, :amount_cents],
    users: [:name],
    companies: [:name, :country]
  )
  .join(:user)
  .join(:company)
  .active
  .to_a
```

### Joins with Aliased Columns

When joining tables with overlapping column names, use aliases for clarity:

```crystal
# Disambiguate 'name' from users and companies
contracts = ContractsRelation.new(adapter)
  .join(:user)
  .join(:company)
  .select(
    t(:contracts)[:reference],
    t(:users)[:name].aliased(:user_name),
    t(:companies)[:name].aliased(:company_name),
    t(:companies)[:country]
  )
  .to_a
# Returns: [
#   {
#     "reference" => "CT-001",
#     "user_name" => "Alice",
#     "company_name" => "Acme Corp",
#     "country" => "USA"
#   }
# ]
```

### LEFT JOIN

```crystal
# All users with their posts (including users without posts)
users_with_posts = UsersRelation.new(adapter)
  .select(users: [:name], posts: [:title])
  .left_join(:posts, on: { users: :id, eq: { posts: :user_id } })
  .active
  .to_a
```

### Filtering on Joined Tables

```crystal
# Contracts where user is active and company is in France
contracts = ContractsRelation.new(adapter)
  .join(:user)
  .join(:company)
  .where(contracts: { status: "active" })
  .where(users: { active: true })
  .where(companies: { country: "France" })
  .to_a
```

## Complex Expressions

### OR Conditions

```crystal
# Users who are admin OR moderator
staff = UsersRelation.new(adapter)
  .where { |e|
    (e[:users][:role] == "admin") | (e[:users][:role] == "moderator")
  }
  .to_a
```

### Combined AND/OR

```crystal
# Active users who are (admin OR have high score)
power_users = UsersRelation.new(adapter)
  .where { |e|
    (e[:users][:active] == true) &
    (
      (e[:users][:role] == "admin") |
      (e[:users][:score] >= 1000)
    )
  }
  .to_a
```

### BETWEEN

```crystal
# Posts published this week
this_week = PostsRelation.new(adapter)
  .where { |e|
    e[:posts][:published_at].between(7.days.ago, Time.utc)
  }
  .to_a

# Contracts in price range
mid_range = ContractsRelation.new(adapter)
  .where { |e|
    e[:contracts][:amount_cents].between(10000_i64, 50000_i64)
  }
  .to_a
```

### IN with Multiple Values

```crystal
# Users in specific countries
users = UsersRelation.new(adapter)
  .where { |e| e[:users][:country].in(["US", "CA", "UK", "FR", "DE"]) }
  .to_a

# Posts with certain statuses
posts = PostsRelation.new(adapter)
  .where { |e| e[:posts][:status].in(["published", "featured"]) }
  .to_a
```

## Dashboard Query

Complex real-world example:

```crystal
# Admin dashboard: Active high-value contracts with details
dashboard_data = ContractsRelation.new(adapter)
  .select(
    contracts: [:reference, :amount_cents, :status],
    users: [:name, :email, :role],
    companies: [:name, :country]
  )
  .join(:user)
  .join(:company)
  .active
  .high_value(50000_i64)
  .where(users: { active: true })
  .where(companies: { active: true })
  .where { |e|
    (e[:users][:role].in(["admin", "manager"])) |
    (e[:contracts][:amount_cents] >= 100000_i64)
  }
  .order(contracts: { amount_cents: :desc })
  .limit(50)
  .to_a
```

## Scope Composition

```crystal
class ContractsRelation < Quo::Relation
  # Base scopes
  scope :active { query.where(contracts: { status: "active" }) }
  scope :high_value, min : Int64 { query.where { |e| e[:contracts][:amount_cents] >= min } }
  scope :with_user { query.join(:user) }
  scope :with_company { query.join(:company) }
  scope :recent { query.order(contracts: { created_at: :desc }) }

  # Composed scopes
  scope :with_details do
    with_user.with_company
  end

  scope :premium do
    active.high_value(100000_i64)
  end

  scope :dashboard_ready do
    premium.with_details.recent
  end
end

# Clean, readable queries
results = ContractsRelation.new(adapter)
  .dashboard_ready
  .limit(20)
  .to_a
```

## Aggregations

### Basic GROUP BY

```crystal
# Count contracts by status
contract_counts = Quo::Query.new(:contracts, adapter)
  .select(contracts: [:status])
  .select_count(as: :count)
  .group(contracts: [:status])
  .to_a
# [{"status" => "active", "count" => 42}, {"status" => "pending", "count" => 10}]
```

### GROUP BY with Multiple Columns

```crystal
# Sales by user and month
sales_report = Quo::Query.new(:orders, adapter)
  .select(orders: [:user_id])
  .select_sum(:orders, :amount_cents, as: :total_sales)
  .select_count(as: :order_count)
  .group(orders: [:user_id])
  .having { |h| h.count >= 5 }
  .to_a
```

### HAVING with Aggregate Conditions

```crystal
# High-volume users with significant spending
premium_users = Quo::Query.new(:orders, adapter)
  .select(orders: [:user_id])
  .select_count(as: :order_count)
  .select_sum(:orders, :amount_cents, as: :total_spent)
  .group(orders: [:user_id])
  .having { |h| (h.count >= 10) & (h.sum(:orders, :amount_cents) >= 100000) }
  .to_a
```

## Subqueries

### IN Subquery

```crystal
# Users who have placed orders
users_with_orders = Quo::Query.new(:orders, adapter)
  .select(orders: [:user_id])
  .distinct

active_customers = UsersRelation.new(adapter)
  .where { |e| e[:users][:id].in(users_with_orders) }
  .to_a
```

### NOT IN Subquery

```crystal
# Users who have never placed an order
ordered_user_ids = Quo::Query.new(:orders, adapter)
  .select(orders: [:user_id])

inactive_users = UsersRelation.new(adapter)
  .where { |e| e[:users][:id].not_in(ordered_user_ids) }
  .to_a
```

### EXISTS Subquery

```crystal
# Users with at least one published post
has_published = Quo::Query.new(:posts, adapter)
  .select(posts: [:id])
  .where(posts: { status: "published" })

authors = UsersRelation.new(adapter)
  .where { |e| e.exists(has_published) }
  .to_a
```

### Scalar Subquery

```crystal
# Orders above average amount
avg_amount = Quo::Query.new(:orders, adapter)
  .select_avg(:orders, :amount_cents)

above_average = Quo::Query.new(:orders, adapter)
  .where { |e| e[:orders][:amount_cents].gt_subquery(avg_amount) }
  .to_a
```

## Set Operations

### UNION

```crystal
# All users who are either admins OR have premium accounts
admins = UsersRelation.new(adapter)
  .select(users: [:id, :name, :email])
  .where(users: { role: "admin" })

premium = UsersRelation.new(adapter)
  .select(users: [:id, :name, :email])
  .where(users: { tier: "premium" })

special_users = admins.union(premium).to_a
```

### INTERSECT

```crystal
# Users who are both active AND verified
active = UsersRelation.new(adapter)
  .select(users: [:id])
  .where(users: { active: true })

verified = UsersRelation.new(adapter)
  .select(users: [:id])
  .where(users: { verified: true })

active_verified = active.intersect(verified).to_a
```

### EXCEPT

```crystal
# Active users who are NOT suspended
all_active = UsersRelation.new(adapter)
  .select(users: [:id, :name])
  .where(users: { active: true })

suspended = UsersRelation.new(adapter)
  .select(users: [:id, :name])
  .where(users: { suspended: true })

good_standing = all_active.except(suspended).to_a
```

## Common Table Expressions (CTEs)

### Basic CTE

```crystal
# Define top spenders as a CTE
top_spenders_query = Quo::Query.new(:orders, adapter)
  .select(orders: [:user_id])
  .select_sum(:orders, :amount_cents, as: :total_spent)
  .group(orders: [:user_id])
  .having { |h| h.sum(:orders, :amount_cents) >= 100000 }

# Use the CTE
vip_users = Quo::Query.new(:top_spenders, adapter)
  .with_cte(:top_spenders, top_spenders_query)
  .select(top_spenders: [:user_id, :total_spent])
  .to_a
```

### Multiple CTEs

```crystal
# CTE 1: Aggregate orders per user
user_orders_query = Quo::Query.new(:orders, adapter)
  .select(orders: [:user_id])
  .select_count(as: :order_count)
  .select_sum(:orders, :total_cents, as: :total_spent)
  .group(orders: [:user_id])

# CTE 2: Aggregate posts per user
user_posts_query = Quo::Query.new(:posts, adapter)
  .select(posts: [:user_id])
  .select_count(as: :post_count)
  .select_sum(:posts, :view_count, as: :total_views)
  .group(posts: [:user_id])

# Main query: Join users with both CTEs
dashboard = Quo::Query.new(:users, adapter)
  .with_cte(:user_orders, user_orders_query)
  .with_cte(:user_posts, user_posts_query)
  .select(users: [:id, :name])
  .select(user_orders: [:order_count, :total_spent])
  .select(user_posts: [:post_count, :total_views])
  .left_join(:user_orders, on: {user_orders: :user_id, eq: {users: :id}})
  .left_join(:user_posts, on: {user_posts: :user_id, eq: {users: :id}})
  .where(users: { active: true })
  .to_a
```

### Recursive CTE

For hierarchical data like category trees or org charts:

```crystal
# Base case: top-level categories (no parent)
base_query = Quo::Query.new(:categories, adapter)
  .select(categories: [:id, :name, :parent_id])
  .where { |e| e[:categories][:parent_id].is_null }

# Recursive case: children joined to the CTE
recursive_query = Quo::Query.new(:categories, adapter)
  .select(categories: [:id, :name, :parent_id])
  .join(:category_tree, on: {categories: :parent_id, eq: {category_tree: :id}})

# Main query using the recursive CTE
category_hierarchy = Quo::Query.new(:category_tree, adapter)
  .with_recursive_cte(:category_tree, base: base_query, recursive: recursive_query)
  .select(category_tree: [:id, :name, :parent_id])
  .to_a
```

**Generated SQL:**
```sql
WITH RECURSIVE "category_tree" AS (
  SELECT "categories"."id", "categories"."name", "categories"."parent_id"
  FROM "categories"
  WHERE "categories"."parent_id" IS NULL
  UNION ALL
  SELECT "categories"."id", "categories"."name", "categories"."parent_id"
  FROM "categories"
  INNER JOIN "category_tree" ON "categories"."parent_id" = "category_tree"."id"
)
SELECT "category_tree"."id", "category_tree"."name", "category_tree"."parent_id"
FROM "category_tree"
```

## Transactions

```crystal
# Transfer funds atomically
adapter.transaction do |tx|
  # Check source balance
  source = tx[:accounts].where(accounts: { id: from_id }).first!
  balance = source["balance"].as(Int64)

  raise "Insufficient funds" if balance < amount

  # Debit source
  tx.update(:accounts)
    .set(balance: balance - amount)
    .where(accounts: { id: from_id })
    .execute

  # Credit destination
  dest = tx[:accounts].where(accounts: { id: to_id }).first!
  tx.update(:accounts)
    .set(balance: dest["balance"].as(Int64) + amount)
    .where(accounts: { id: to_id })
    .execute

  # Log the transfer
  tx.insert(:transfers)
    .values(from_id: from_id, to_id: to_id, amount: amount)
    .execute
end
```
