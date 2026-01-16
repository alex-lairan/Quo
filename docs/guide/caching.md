# Query Caching

Quo provides query result caching with TTL expiration, tag-based invalidation, and cache statistics.

## Basic Setup

```crystal
require "quo"

# Create cache with defaults
cache = Quo::Cache::QueryCache.new

# Or configure
cache = Quo::Cache::QueryCache.new(
  store: Quo::Cache::MemoryCacheStore.new(max_size: 10_000),
  default_ttl: 5.minutes,
  enabled: true
)
```

## Caching Query Results

### Using fetch

```crystal
# Cache key is generated from SQL and params
key = cache.cache_key(sql, params)

# Fetch from cache or execute
results = cache.fetch(key, ttl: 10.minutes) do
  adapter.execute(sql, params)
end
```

### Using fetch_query

```crystal
# Automatically generates key from SQL and params
results = cache.fetch_query(sql, params, ttl: 10.minutes) do
  adapter.execute(sql, params)
end
```

### With CachedQuery Wrapper

```crystal
# Wrap a query for caching
cached_query = Quo::CachedQuery.new(
  query: Quo::Query.new(:users, adapter),
  cache: cache
)

# Enable caching with TTL
results = cached_query
  .where(users: { active: true })
  .cache(ttl: 5.minutes)
  .to_a

# Second call hits cache
results = cached_query
  .where(users: { active: true })
  .cache(ttl: 5.minutes)
  .to_a  # Returns cached result
```

## Cache Invalidation

### Invalidate by Key

```crystal
# Invalidate specific key
cache.invalidate("users:active")
```

### Invalidate by Pattern

```crystal
# Invalidate all keys matching pattern
count = cache.invalidate_pattern("users:*")
puts "Invalidated #{count} entries"
```

### Tag-Based Invalidation

Tags allow grouping related cache entries for bulk invalidation:

```crystal
# Cache with tags
cache.set("users:123", results, ttl: 10.minutes, tags: ["users", "user:123"])
cache.set("users:456", results, ttl: 10.minutes, tags: ["users", "user:456"])

# Invalidate all entries with "users" tag
count = cache.invalidate_tag("users")
puts "Invalidated #{count} entries"

# Invalidate specific user
cache.invalidate_tag("user:123")
```

### With CachedQuery

```crystal
# Tag the query
results = Quo::CachedQuery.new(query, cache)
  .cache(ttl: 5.minutes)
  .tag("users", "active_users")
  .to_a

# Later, invalidate
cache.invalidate_tag("users")
```

## Cache Bypass

Skip the cache temporarily:

```crystal
# Bypass cache for a block
cache.bypass do
  # These queries skip the cache
  results1 = cache.fetch("key1") { execute_query1 }
  results2 = cache.fetch("key2") { execute_query2 }
end

# With CachedQuery
results = Quo::CachedQuery.new(query, cache)
  .uncached
  .to_a  # Always executes query
```

## Cache Statistics

Monitor cache performance:

```crystal
stats = cache.stats

puts "Hits: #{stats.hits}"
puts "Misses: #{stats.misses}"
puts "Hit rate: #{(stats.hit_rate * 100).round(1)}%"
puts "Size: #{stats.size} entries"
puts "Evictions: #{stats.evictions}"
puts "Total requests: #{stats.total_requests}"
```

## Enable/Disable Cache

```crystal
# Disable caching globally
cache.enabled = false

# Check if enabled
if cache.enabled?
  puts "Cache is active"
end

# Re-enable
cache.enabled = true
```

## Memory Cache Store

The default in-memory cache store with LRU eviction:

```crystal
store = Quo::Cache::MemoryCacheStore.new(
  max_size: 10_000  # Maximum entries before eviction
)

# Basic operations
store.set("key", "value", ttl: 5.minutes)
value = store.get("key")
store.delete("key")

# Find keys by pattern
keys = store.keys("users:*")

# Clear all
store.clear

# Get current size
puts store.size
```

### Set Operations

For tag tracking:

```crystal
# Add member to set
store.set_add("tag:users", "cache_key_1")
store.set_add("tag:users", "cache_key_2")

# Get all members
members = store.set_members("tag:users")

# Delete set
store.set_delete("tag:users")
```

## Custom Cache Stores

Implement the `CacheStore` abstract class:

```crystal
class RedisCacheStore < Quo::Cache::CacheStore
  def initialize(@redis : Redis::Client)
  end

  def get(key : String) : String?
    @redis.get(key)
  end

  def set(key : String, value : String, ttl : Time::Span) : Nil
    @redis.setex(key, ttl.total_seconds.to_i, value)
  end

  def delete(key : String) : Bool
    @redis.del(key) > 0
  end

  def delete_all(keys : Array(String)) : Int32
    return 0 if keys.empty?
    @redis.del(keys).to_i32
  end

  def keys(pattern : String) : Array(String)
    @redis.keys(pattern)
  end

  def clear : Nil
    @redis.flushdb
  end

  def size : Int32
    @redis.dbsize.to_i32
  end

  def set_add(key : String, member : String) : Nil
    @redis.sadd(key, member)
  end

  def set_members(key : String) : Array(String)
    @redis.smembers(key)
  end

  def set_delete(key : String) : Bool
    @redis.del(key) > 0
  end
end

# Usage
redis_store = RedisCacheStore.new(Redis::Client.new)
cache = Quo::Cache::QueryCache.new(store: redis_store)
```

## Best Practices

### 1. Choose appropriate TTLs

- Frequently changing data: 30 seconds - 1 minute
- Moderately stable: 5 - 15 minutes
- Rarely changing: 1 hour or more

### 2. Use tags for related data

```crystal
# Tag by entity type and ID
cache.set(key, data, tags: ["posts", "post:#{post_id}", "user:#{author_id}"])

# When user updates, invalidate their posts
cache.invalidate_tag("user:#{user_id}")
```

### 3. Invalidate on writes

```crystal
def create_user(attrs)
  user = insert_user(attrs)
  cache.invalidate_tag("users")
  user
end

def update_user(id, attrs)
  user = update_user_record(id, attrs)
  cache.invalidate_tag("user:#{id}")
  cache.invalidate_tag("users")  # If lists are cached
  user
end
```

### 4. Monitor hit rates

- Target 80%+ hit rate for effective caching
- Low hit rates may indicate poor key design or short TTLs

### 5. Set appropriate max_size

- Consider your memory budget
- Monitor evictions - high evictions may indicate too small cache

## Example: Repository with Caching

```crystal
class UserRepository
  def initialize(@adapter : Quo::Adapters::Adapter, @cache : Quo::Cache::QueryCache)
  end

  def find(id : Int64) : User?
    key = "user:#{id}"
    results = @cache.fetch(key, ttl: 10.minutes, tags: ["users", key]) do
      Quo::Query.new(:users, @adapter)
        .where(users: { id: id })
        .to_a
    end
    results.first?.try { |row| User.from_row(row) }
  end

  def active_users : Array(User)
    results = @cache.fetch("users:active", ttl: 5.minutes, tags: ["users"]) do
      Quo::Query.new(:users, @adapter)
        .where(users: { active: true })
        .order(users: { name: :asc })
        .to_a
    end
    results.map { |row| User.from_row(row) }
  end

  def create(attrs) : User
    user = Quo::InsertQuery.new(:users, @adapter)
      .values(**attrs)
      .returning(users: [:id, :name, :email])
      .execute_returning_one!

    # Invalidate list caches
    @cache.invalidate_tag("users")

    User.from_row(user)
  end

  def update(id : Int64, attrs) : User
    user = Quo::UpdateQuery.new(:users, @adapter)
      .set(**attrs)
      .where(users: { id: id })
      .returning(users: [:id, :name, :email])
      .execute_returning.first!

    # Invalidate this user and lists
    @cache.invalidate_tag("user:#{id}")
    @cache.invalidate_tag("users")

    User.from_row(user)
  end

  def delete(id : Int64) : Nil
    Quo::DeleteQuery.new(:users, @adapter)
      .where(users: { id: id })
      .execute

    @cache.invalidate_tag("user:#{id}")
    @cache.invalidate_tag("users")
  end
end
```
