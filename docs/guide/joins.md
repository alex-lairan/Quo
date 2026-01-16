# Joins & Associations

Quo supports both explicit join conditions and association-based joins.

## Association-Based Joins

The recommended way to join tables. Define associations once, use them everywhere.

### Defining Associations

```crystal
class ContractsRelation < Quo::Relation
  schema :contracts do
    primary_key :id, Int64
    column :user_id, Int64
    column :company_id, Int64
    column :reference, String

    # belongs_to: this table has the foreign key
    belongs_to :user, :user_id, :users
    belongs_to :company, :company_id, :companies
  end
end

class UsersRelation < Quo::Relation
  schema :users do
    primary_key :id, Int64
    column :name, String

    # has_many: other table has the foreign key
    has_many :contracts, :user_id, :contracts
  end
end
```

### Using Association Joins

```crystal
# INNER JOIN via association name
ContractsRelation.new(adapter)
  .join(:user)      # contracts.user_id = users.id
  .join(:company)   # contracts.company_id = companies.id
  .to_a

# LEFT JOIN via association
ContractsRelation.new(adapter)
  .left_join(:user)
  .to_a
```

### Custom Key Associations

When keys don't follow conventions:

```crystal
class ContractsRelation < Quo::Relation
  schema :contracts do
    column :payment_provider_uuid, String

    # contracts.payment_provider_uuid = stripe_subscriptions.stripe_id
    belongs_to :stripe_subscription, :payment_provider_uuid, :stripe_subscriptions, :stripe_id
  end
end

# Use like any other association
ContractsRelation.new(adapter)
  .join(:stripe_subscription)
  .to_a
```

## Association Types

### belongs_to

The foreign key is on **this** table:

```crystal
# Syntax: belongs_to :name, :foreign_key, :target_table, :target_key (default: :id)

belongs_to :user, :user_id, :users
# => contracts.user_id = users.id

belongs_to :subscription, :provider_uuid, :stripe_subscriptions, :stripe_id
# => contracts.provider_uuid = stripe_subscriptions.stripe_id
```

### has_many

The foreign key is on the **other** table:

```crystal
# Syntax: has_many :name, :foreign_key, :target_table, :source_key (default: :id)

has_many :contracts, :user_id, :contracts
# => users.id = contracts.user_id
```

### has_one

Same as has_many, but semantically indicates a single record:

```crystal
has_one :profile, :user_id, :profiles
# => users.id = profiles.user_id
```

## Explicit Joins

For ad-hoc joins or tables without defined associations:

```crystal
# INNER JOIN
ContractsRelation.new(adapter)
  .join(:users, on: { contracts: :user_id, eq: { users: :id } })
  .to_a

# LEFT JOIN
ContractsRelation.new(adapter)
  .left_join(:audit_logs, on: { contracts: :id, eq: { audit_logs: :contract_id } })
  .to_a

# RIGHT JOIN (PostgreSQL only)
ContractsRelation.new(adapter)
  .right_join(:users, on: { contracts: :user_id, eq: { users: :id } })
  .to_a
```

## Selecting from Joined Tables

After joining, select columns from any table:

```crystal
ContractsRelation.new(adapter)
  .select(
    contracts: [:id, :reference, :status],
    users: [:name, :email],
    companies: [:name]
  )
  .join(:user)
  .join(:company)
  .to_a
```

## Filtering Joined Tables

Use WHERE on any joined table:

```crystal
ContractsRelation.new(adapter)
  .join(:user)
  .join(:company)
  .where(contracts: { status: "active" })
  .where(users: { active: true })
  .where(companies: { country: "France" })
  .to_a
```

Or with expressions:

```crystal
ContractsRelation.new(adapter)
  .join(:user)
  .where { |e|
    (e[:contracts][:status] == "active") &
    (e[:users][:role] == "admin")
  }
  .to_a
```

## Join Types

| Method | SQL | Description |
|--------|-----|-------------|
| `.join(:assoc)` | INNER JOIN | Only matching rows |
| `.left_join(:assoc)` | LEFT JOIN | All from left, matching from right |
| `.right_join(:assoc)` | RIGHT JOIN | All from right, matching from left |
| `.full_join(:assoc)` | FULL JOIN | All from both |

::: warning SQLite Limitations
SQLite does not support `RIGHT JOIN` or `FULL JOIN`. Use `LEFT JOIN` with reversed table order instead.
:::

## Mixing Association and Explicit Joins

```crystal
ContractsRelation.new(adapter)
  .join(:user)  # Association join
  .join(:audit_logs, on: { contracts: :id, eq: { audit_logs: :contract_id } })  # Explicit
  .to_a
```

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

    belongs_to :user, :user_id, :users
    belongs_to :company, :company_id, :companies
  end

  scope :active do
    query.where(contracts: { status: "active" })
  end

  scope :with_user_and_company do
    query.join(:user).join(:company)
  end
end

# Dashboard query
results = ContractsRelation.new(adapter)
  .select(
    contracts: [:reference, :amount_cents],
    users: [:name, :email],
    companies: [:name]
  )
  .with_user_and_company
  .active
  .where(users: { active: true })
  .where(companies: { active: true })
  .order(contracts: { amount_cents: :desc })
  .limit(50)
  .to_a
```
