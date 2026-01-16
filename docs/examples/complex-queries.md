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

## Aggregation with Subqueries

```crystal
# Users with above-average post count (conceptual)
# Note: Subqueries require raw SQL in current version

avg_posts = PostsRelation.new(adapter).count / UsersRelation.new(adapter).count

prolific_authors = UsersRelation.new(adapter)
  .left_join(:posts, on: { users: :id, eq: { posts: :user_id } })
  .where { |e| e[:posts][:id].is_not_null }
  .to_a
```
