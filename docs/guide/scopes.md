# Scopes

Scopes are reusable query fragments defined on relations.

## Defining Scopes

### Simple Scopes

```crystal
class PostsRelation < Quo::Relation
  schema :posts do
    primary_key :id, Int64
    column :status, String
    column :published_at, Time
    column :view_count, Int64
  end

  scope :published do
    query.where(posts: { status: "published" })
  end

  scope :draft do
    query.where(posts: { status: "draft" })
  end

  scope :by_recent do
    query.order(posts: { published_at: :desc })
  end

  scope :popular do
    query.order(posts: { view_count: :desc })
  end
end
```

### Scopes with Arguments

```crystal
class PostsRelation < Quo::Relation
  # ...

  scope :by_status, status : String do
    query.where(posts: { status: status })
  end

  scope :with_minimum_views, count : Int64 do
    query.where { |e| e[:posts][:view_count] >= count }
  end

  scope :paginate, page : Int32, per_page : Int32 = 20 do
    query.limit(per_page).offset((page - 1) * per_page)
  end
end
```

### Expression Scopes

```crystal
class UsersRelation < Quo::Relation
  schema :users do
    primary_key :id, Int64
    column :role, String
    column :score, Int64
    column :active, Bool
  end

  scope :admins do
    query.where { |e|
      (e[:users][:role] == "admin") | (e[:users][:role] == "superuser")
    }
  end

  scope :high_scorers do
    query.where { |e| e[:users][:score] >= 1000 }
  end

  scope :active do
    query.where(users: { active: true })
  end
end
```

## Using Scopes

### Single Scope

```crystal
posts = PostsRelation.new(adapter)

published = posts.published.to_a
drafts = posts.draft.to_a
```

### Chaining Scopes

```crystal
# Combine multiple scopes
popular_recent = posts
  .published
  .popular
  .by_recent
  .limit(10)
  .to_a

# With arguments
paginated = posts
  .published
  .with_minimum_views(100_i64)
  .paginate(page: 2, per_page: 20)
  .to_a
```

### Scopes with Additional Conditions

```crystal
# Mix scopes and inline conditions
featured = posts
  .published
  .where(posts: { featured: true })
  .by_recent
  .limit(5)
  .to_a
```

## Scope Composition

Scopes can call other scopes:

```crystal
class PostsRelation < Quo::Relation
  # Base scopes
  scope :published do
    query.where(posts: { status: "published" })
  end

  scope :by_recent do
    query.order(posts: { published_at: :desc })
  end

  scope :with_minimum_views, count : Int64 do
    query.where { |e| e[:posts][:view_count] >= count }
  end

  # Composed scope - calls other scopes
  scope :trending do
    published
      .with_minimum_views(500_i64)
      .by_recent
  end
end

# Use composed scope
trending = PostsRelation.new(adapter).trending.limit(10).to_a
```

## Immutability

Scopes never modify the original relation:

```crystal
base = PostsRelation.new(adapter).published

# These create new relations
recent = base.by_recent
popular = base.popular

# base is unchanged
base_sql, _ = base.to_sql  # Only has published condition
```

## Best Practices

### DO: Small, Focused Scopes

```crystal
scope :active do
  query.where(users: { active: true })
end

scope :verified do
  query.where { |e| e[:users][:verified_at].is_not_null }
end

scope :by_name do
  query.order(users: { name: :asc })
end
```

### DO: Compose Complex Queries from Simple Scopes

```crystal
# In the relation
scope :eligible do
  active  # calls the active scope defined above
end

# In application code
users = UsersRelation.new(adapter)
  .eligible
  .verified
  .by_name
  .to_a
```

### DON'T: Create Giant Monolithic Scopes

```crystal
# Avoid this - hard to reuse parts
scope :complex_report do
  query
    .where(users: { active: true })
    .where { |e| e[:users][:score] >= 100 }
    .join(:orders)
    .where { |e| e[:orders][:total] >= 1000 }
    .order(users: { created_at: :desc })
    .limit(100)
end

# Instead, break into smaller scopes and compose
```

## Class Method Scopes

Scopes are available as both instance and class methods:

```crystal
# Instance method (requires adapter instance)
relation = UsersRelation.new(adapter)
relation.active.to_a

# Class method (pass adapter as first argument)
UsersRelation.active(adapter).to_a
```
