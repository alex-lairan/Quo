# Cache API

Query caching with TTL and tag-based invalidation.

## CacheStats

Statistics about cache usage.

```crystal
struct Quo::Cache::CacheStats
  getter hits : Int64       # Cache hits
  getter misses : Int64     # Cache misses
  getter size : Int32       # Current number of entries
  getter evictions : Int64  # Total evictions
end
```

### Methods

| Method | Return | Description |
|--------|--------|-------------|
| `hit_rate` | `Float64` | Hit rate (0.0 - 1.0) |
| `total_requests` | `Int64` | Total hits + misses |

### Example

```crystal
stats = cache.stats

puts "Hit rate: #{(stats.hit_rate * 100).round(1)}%"
puts "Cache size: #{stats.size} entries"
puts "Total requests: #{stats.total_requests}"
puts "Evictions: #{stats.evictions}"
```

---

## CacheStore

Abstract interface for cache storage backends.

```crystal
abstract class Quo::Cache::CacheStore
  # Get value by key
  abstract def get(key : String) : String?

  # Set value with TTL
  abstract def set(key : String, value : String, ttl : Time::Span) : Nil

  # Delete a key
  abstract def delete(key : String) : Bool

  # Delete multiple keys
  abstract def delete_all(keys : Array(String)) : Int32

  # Find keys matching pattern (supports * wildcard)
  abstract def keys(pattern : String) : Array(String)

  # Clear all entries
  abstract def clear : Nil

  # Get number of entries
  abstract def size : Int32

  # Set operations for tag support
  abstract def set_add(key : String, member : String) : Nil
  abstract def set_members(key : String) : Array(String)
  abstract def set_delete(key : String) : Bool
end
```

---

## MemoryCacheStore

In-memory cache store with TTL and LRU eviction.

```crystal
class Quo::Cache::MemoryCacheStore < CacheStore
  def initialize(max_size : Int32 = 10_000)
end
```

### Constructor

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `max_size` | `Int32` | `10_000` | Maximum entries before eviction |

### Additional Methods

| Method | Return | Description |
|--------|--------|-------------|
| `cleanup` | `Int32` | Manually remove expired entries, returns count |

### Eviction Behavior

When cache reaches `max_size`:
1. First tries to evict expired entries
2. If no expired entries, evicts oldest entry (FIFO approximation)

### Example

```crystal
store = Quo::Cache::MemoryCacheStore.new(max_size: 50_000)

# Use with QueryCache
cache = Quo::Cache::QueryCache.new(store: store)

# Manual cleanup
expired_count = store.cleanup
puts "Cleaned up #{expired_count} expired entries"
```

---

## QueryCache

Query result cache with TTL and tag-based invalidation.

```crystal
class Quo::Cache::QueryCache
  def initialize(
    store : CacheStore = MemoryCacheStore.new,
    default_ttl : Time::Span = 5.minutes,
    enabled : Bool = true
  )
end
```

### Constructor

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `store` | `CacheStore` | `MemoryCacheStore.new` | Storage backend |
| `default_ttl` | `Time::Span` | `5.minutes` | Default TTL for entries |
| `enabled` | `Bool` | `true` | Whether cache is enabled |

### Methods

| Method | Return | Description |
|--------|--------|-------------|
| `cache_key(sql, params)` | `String` | Generate cache key from SQL and params |
| `fetch(key, ttl, tags, &block)` | `ResultSet` | Fetch from cache or execute block |
| `fetch_query(sql, params, ttl, tags, &block)` | `ResultSet` | Fetch using SQL as key |
| `get(key)` | `ResultSet?` | Get cached value by key |
| `set(key, value, ttl, tags)` | `Nil` | Store value in cache |
| `invalidate(key)` | `Bool` | Invalidate a specific key |
| `invalidate_pattern(pattern)` | `Int32` | Invalidate keys matching pattern |
| `invalidate_tag(tag)` | `Int32` | Invalidate all keys with tag |
| `invalidate_tags(*tags)` | `Int32` | Invalidate multiple tags |
| `clear` | `Nil` | Clear entire cache |
| `bypass(&block)` | `T` | Execute block bypassing cache |
| `bypassed?` | `Bool` | Check if cache is currently bypassed |
| `stats` | `CacheStats` | Cache statistics |
| `enabled=` | `Nil` | Enable/disable cache |
| `enabled?` | `Bool` | Check if cache is enabled |
| `store` | `CacheStore` | Access underlying store |
| `default_ttl` | `Time::Span` | Current default TTL |
| `default_ttl=` | `Nil` | Set default TTL |

### cache_key

```crystal
def cache_key(sql : String, params : Array(DB::Any)) : String
```

Generate a deterministic cache key from SQL and parameters.

### fetch

```crystal
def fetch(
  key : String,
  ttl : Time::Span? = nil,
  tags : Array(String) = [] of String,
  &block : -> Quo::ResultSet
) : Quo::ResultSet
```

Fetch from cache or execute block if not cached.

| Parameter | Type | Description |
|-----------|------|-------------|
| `key` | `String` | Cache key |
| `ttl` | `Time::Span?` | TTL (uses default if nil) |
| `tags` | `Array(String)` | Tags for invalidation |
| `&block` | Block | Executed if cache miss |

### fetch_query

```crystal
def fetch_query(
  sql : String,
  params : Array(DB::Any),
  ttl : Time::Span? = nil,
  tags : Array(String) = [] of String,
  &block : -> Quo::ResultSet
) : Quo::ResultSet
```

Same as `fetch` but generates key from SQL and params.

### invalidate

```crystal
def invalidate(key : String) : Bool
```

Invalidate a specific cache key. Returns true if key existed.

### invalidate_pattern

```crystal
def invalidate_pattern(pattern : String) : Int32
```

Invalidate all keys matching glob pattern. Returns count invalidated.

```crystal
cache.invalidate_pattern("users:*")  # All user queries
cache.invalidate_pattern("*:active") # All active queries
```

### invalidate_tag

```crystal
def invalidate_tag(tag : String) : Int32
```

Invalidate all entries associated with a tag. Returns count invalidated.

### invalidate_tags

```crystal
def invalidate_tags(*tags : String) : Int32
```

Invalidate multiple tags at once.

### bypass

```crystal
def bypass(&block)
```

Execute block with cache bypassed. Useful for ensuring fresh data.

---

## Example Usage

### Basic Caching

```crystal
require "quo"

# Create cache
cache = Quo::Cache::QueryCache.new(
  default_ttl: 10.minutes
)

# Cache query results
results = cache.fetch("active_users", tags: ["users"]) do
  UsersRelation.new(adapter).active.to_a
end

# Subsequent calls return cached data
results = cache.fetch("active_users", tags: ["users"]) do
  UsersRelation.new(adapter).active.to_a  # Not executed
end
```

### With SQL Key Generation

```crystal
sql, params = UsersRelation.new(adapter)
  .where(users: { active: true })
  .to_sql

results = cache.fetch_query(sql, params, tags: ["users"]) do
  adapter.execute(sql, params)
end
```

### Tag-Based Invalidation

```crystal
# Cache with tags
cache.fetch("user:123", tags: ["users", "user:123"]) do
  # ...
end

cache.fetch("user:456", tags: ["users", "user:456"]) do
  # ...
end

# Invalidate single user
cache.invalidate_tag("user:123")

# Invalidate all users
cache.invalidate_tag("users")

# Invalidate multiple tags
cache.invalidate_tags("users", "orders", "products")
```

### Custom TTL

```crystal
# Short TTL for frequently changing data
cache.fetch("dashboard_stats", ttl: 30.seconds, tags: ["stats"]) do
  # ...
end

# Longer TTL for stable data
cache.fetch("static_config", ttl: 1.hour, tags: ["config"]) do
  # ...
end
```

### Bypassing Cache

```crystal
# Force fresh data
cache.bypass do
  fresh_results = cache.fetch("reports") do
    # Always executes, result not cached
    generate_reports
  end
end

# Check bypass status
if cache.bypassed?
  puts "Cache is bypassed"
end
```

### Monitoring

```crystal
stats = cache.stats

# Hit rate monitoring
if stats.hit_rate < 0.5
  puts "Warning: Low cache hit rate (#{(stats.hit_rate * 100).round(1)}%)"
end

# Size monitoring
if stats.size > 8000  # Approaching 10k default max
  puts "Cache nearing capacity: #{stats.size} entries"
end

# Log stats periodically
puts "Cache: #{stats.hits} hits, #{stats.misses} misses, #{stats.size} entries"
```

### Disabling Cache

```crystal
# Disable globally
cache.enabled = false

# All fetches now execute blocks
cache.fetch("key") do
  # Always executes
end

# Re-enable
cache.enabled = true
```

### Custom Store

```crystal
# Implement custom backend (e.g., Redis)
class RedisCacheStore < Quo::Cache::CacheStore
  def initialize(@redis : Redis::Client)
  end

  def get(key : String) : String?
    @redis.get(key)
  end

  def set(key : String, value : String, ttl : Time::Span) : Nil
    @redis.set(key, value, ex: ttl.total_seconds.to_i)
  end

  # ... implement other methods
end

# Use custom store
cache = Quo::Cache::QueryCache.new(
  store: RedisCacheStore.new(redis)
)
```

---

## Best Practices

### Key Naming

```crystal
# Good: Descriptive, hierarchical keys
cache.fetch("users:active:page:1", tags: ["users"])
cache.fetch("orders:user:123:recent", tags: ["orders", "user:123"])

# Bad: Generic or collision-prone
cache.fetch("data")
cache.fetch("result")
```

### Tag Strategy

```crystal
# Tag by entity type
tags: ["users"]

# Tag by specific entity
tags: ["users", "user:123"]

# Tag by feature area
tags: ["dashboard", "users"]
```

### TTL Guidelines

| Data Type | Suggested TTL |
|-----------|---------------|
| Static configuration | 1 hour+ |
| User profiles | 5-15 minutes |
| Dashboard stats | 30 seconds - 2 minutes |
| Search results | 1-5 minutes |
| Frequently updated | 10-30 seconds |

---

## Exceptions

### CacheError

```crystal
class Quo::CacheError < Exception
```

Raised when cache operations fail.
