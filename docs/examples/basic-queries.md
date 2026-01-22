# Basic Queries

Simple examples to get started with Quo.

## Setup

```crystal
require "sqlite3"
require "quo"

# Define a relation
class UsersRelation < Quo::Relation
  schema :users do
    primary_key :id, Int64
    column :name, String
    column :email, String
    column :role, String
    column :active, Bool
    column :created_at, Time
  end

  scope :active do
    query.where(users: { active: true })
  end
end

# Create adapter
DB.open "sqlite3:./app.db" do |db|
  adapter = Quo::Adapters::SQLite.new(db)

  # Examples below use this adapter
end
```

## SELECT All

```crystal
# All columns
users = UsersRelation.new(adapter).to_a

# Specific columns
users = UsersRelation.new(adapter)
  .select(users: [:id, :name, :email])
  .to_a
```

## SELECT with Aliases

```crystal
# Alias a single column
users = UsersRelation.new(adapter)
  .select(
    t(:users)[:id],
    t(:users)[:name].aliased(:full_name)
  )
  .to_a
# Returns: [{"id" => 1, "full_name" => "Alice"}, ...]

# Multiple aliased columns
users = UsersRelation.new(adapter)
  .select(
    t(:users)[:name].aliased(:user_name),
    t(:users)[:email].aliased(:contact_email)
  )
  .to_a

# Mix hash-based and aliased columns
users = UsersRelation.new(adapter)
  .select(users: [:id])
  .select(t(:users)[:name].aliased(:full_name))
  .to_a
```

## WHERE Conditions

### Hash Syntax

```crystal
# Single condition
active_users = UsersRelation.new(adapter)
  .where(users: { active: true })
  .to_a

# Multiple conditions (AND)
admin_users = UsersRelation.new(adapter)
  .where(users: { role: "admin", active: true })
  .to_a

# Chained conditions (also AND)
verified_admins = UsersRelation.new(adapter)
  .where(users: { role: "admin" })
  .where(users: { active: true })
  .to_a
```

### Expression Syntax

```crystal
# Comparison
high_scorers = UsersRelation.new(adapter)
  .where { |e| e[:users][:score] >= 100 }
  .to_a

# LIKE
johns = UsersRelation.new(adapter)
  .where { |e| e[:users][:name].like("John%") }
  .to_a

# IN
staff = UsersRelation.new(adapter)
  .where { |e| e[:users][:role].in(["admin", "moderator"]) }
  .to_a

# NULL check
unverified = UsersRelation.new(adapter)
  .where { |e| e[:users][:verified_at].is_null }
  .to_a
```

## ORDER BY

```crystal
# Ascending
users_asc = UsersRelation.new(adapter)
  .order(users: { name: :asc })
  .to_a

# Descending
users_desc = UsersRelation.new(adapter)
  .order(users: { created_at: :desc })
  .to_a

# Multiple columns
sorted = UsersRelation.new(adapter)
  .order(users: { role: :asc, name: :asc })
  .to_a
```

## LIMIT & OFFSET

```crystal
# First 10
first_ten = UsersRelation.new(adapter)
  .limit(10)
  .to_a

# Pagination
page = 2
per_page = 20

paginated = UsersRelation.new(adapter)
  .order(users: { id: :asc })
  .limit(per_page)
  .offset((page - 1) * per_page)
  .to_a
```

## Terminal Methods

### Get All Results

```crystal
users = UsersRelation.new(adapter).active.to_a
# => [{"id" => 1, "name" => "Alice", ...}, ...]
```

### Get First Result

```crystal
# Returns nil if not found
user = UsersRelation.new(adapter)
  .where(users: { email: "alice@example.com" })
  .first

if user
  puts user["name"]
end

# Raises if not found
user = UsersRelation.new(adapter)
  .where(users: { email: "alice@example.com" })
  .first!

puts user["name"]  # Safe - will raise if not found
```

### Count

```crystal
total = UsersRelation.new(adapter).active.count
puts "Active users: #{total}"
```

### Exists?

```crystal
email = "test@example.com"

if UsersRelation.new(adapter).where(users: { email: email }).exists?
  puts "Email already taken"
end
```

## Using Scopes

```crystal
class UsersRelation < Quo::Relation
  scope :active do
    query.where(users: { active: true })
  end

  scope :admins do
    query.where(users: { role: "admin" })
  end

  scope :recent do
    query.order(users: { created_at: :desc })
  end
end

# Chain scopes
active_admins = UsersRelation.new(adapter)
  .active
  .admins
  .recent
  .limit(5)
  .to_a
```

## Debug SQL

```crystal
sql, params = UsersRelation.new(adapter)
  .active
  .where(users: { role: "admin" })
  .order(users: { name: :asc })
  .to_sql

puts sql
# SELECT "users".* FROM "users"
# WHERE "users"."active" = ?
# AND "users"."role" = ?
# ORDER BY "users"."name" ASC

puts params.inspect
# [true, "admin"]
```
