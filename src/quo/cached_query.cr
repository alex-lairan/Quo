require "./query"
require "./cache/query_cache"

module Quo
  # A query wrapper that adds caching capabilities
  # Wraps a Query and caches results based on TTL and tags
  #
  # Example:
  # ```
  # cache = Quo::Cache::QueryCache.new
  # query = Query.new(:users, adapter)
  #
  # cached = CachedQuery.new(query, cache)
  #   .where(users: {active: true})
  #   .cache(ttl: 10.minutes)
  #   .tag("users", "active_users")
  #
  # results = cached.to_a  # Cached on first call, retrieved from cache on subsequent calls
  # ```
  class CachedQuery
    @query : Query
    @cache : Cache::QueryCache
    @ttl : Time::Span?
    @tags : Array(String)
    @custom_key : String?
    @bypass : Bool

    def initialize(
      @query : Query,
      @cache : Cache::QueryCache,
      @ttl : Time::Span? = nil,
      @tags : Array(String) = [] of String,
      @custom_key : String? = nil,
      @bypass : Bool = false
    )
    end

    # Set cache TTL for this query
    def cache(ttl : Time::Span) : CachedQuery
      CachedQuery.new(@query, @cache, ttl, @tags, @custom_key, @bypass)
    end

    # Set custom cache key
    def cache_key(key : String) : CachedQuery
      CachedQuery.new(@query, @cache, @ttl, @tags, key, @bypass)
    end

    # Add cache tags for invalidation
    def tag(*tags : String) : CachedQuery
      CachedQuery.new(@query, @cache, @ttl, @tags + tags.to_a, @custom_key, @bypass)
    end

    # Bypass cache for this query
    def uncached : CachedQuery
      CachedQuery.new(@query, @cache, @ttl, @tags, @custom_key, true)
    end

    # Forward query building methods - each returns a new CachedQuery

    def select(**columns) : CachedQuery
      CachedQuery.new(@query.select(**columns), @cache, @ttl, @tags, @custom_key, @bypass)
    end

    def where(**conditions) : CachedQuery
      CachedQuery.new(@query.where(**conditions), @cache, @ttl, @tags, @custom_key, @bypass)
    end

    def where(&block : ExpressionBuilder -> Expression) : CachedQuery
      CachedQuery.new(@query.where(&block), @cache, @ttl, @tags, @custom_key, @bypass)
    end

    def join(table : Symbol, on : NamedTuple) : CachedQuery
      CachedQuery.new(@query.join(table, on), @cache, @ttl, @tags, @custom_key, @bypass)
    end

    def left_join(table : Symbol, on : NamedTuple) : CachedQuery
      CachedQuery.new(@query.left_join(table, on), @cache, @ttl, @tags, @custom_key, @bypass)
    end

    def right_join(table : Symbol, on : NamedTuple) : CachedQuery
      CachedQuery.new(@query.right_join(table, on), @cache, @ttl, @tags, @custom_key, @bypass)
    end

    def full_join(table : Symbol, on : NamedTuple) : CachedQuery
      CachedQuery.new(@query.full_join(table, on), @cache, @ttl, @tags, @custom_key, @bypass)
    end

    def order(**columns) : CachedQuery
      CachedQuery.new(@query.order(**columns), @cache, @ttl, @tags, @custom_key, @bypass)
    end

    def limit(n : Int32) : CachedQuery
      CachedQuery.new(@query.limit(n), @cache, @ttl, @tags, @custom_key, @bypass)
    end

    def offset(n : Int32) : CachedQuery
      CachedQuery.new(@query.offset(n), @cache, @ttl, @tags, @custom_key, @bypass)
    end

    def distinct : CachedQuery
      CachedQuery.new(@query.distinct, @cache, @ttl, @tags, @custom_key, @bypass)
    end

    def group(**columns) : CachedQuery
      CachedQuery.new(@query.group(**columns), @cache, @ttl, @tags, @custom_key, @bypass)
    end

    # Execute and return results (with caching)
    def to_a : Quo::ResultSet
      if @bypass
        return @query.to_a
      end

      sql, params = @query.to_sql
      key = @custom_key || @cache.cache_key(sql, params)

      @cache.fetch(key, @ttl, @tags) do
        @query.to_a
      end
    end

    # Get first result (with caching)
    def first : Quo::Row?
      to_a.first?
    end

    # Get first result or raise (with caching)
    def first! : Quo::Row
      first || raise RecordNotFound.new(@query.table)
    end

    # Count (not cached by default - override with explicit caching)
    def count : Int64
      if @bypass
        return @query.count
      end

      sql, params = @query.count_sql
      key = @custom_key ? "#{@custom_key}:count" : @cache.cache_key(sql, params)

      # For count, we need to cache the integer result differently
      # We'll cache the result of to_a and count from that, or skip cache
      @query.count
    end

    # Check if records exist (not cached)
    def exists? : Bool
      @query.exists?
    end

    # Get the underlying SQL (not cached)
    def to_sql : {String, Array(Quo::Value)}
      @query.to_sql
    end

    # Get count SQL (not cached)
    def count_sql : {String, Array(Quo::Value)}
      @query.count_sql
    end

    # Access the underlying query
    def query : Query
      @query
    end

    # Access the cache
    def query_cache : Cache::QueryCache
      @cache
    end

    # Current TTL setting
    def ttl : Time::Span?
      @ttl
    end

    # Current tags
    def tags : Array(String)
      @tags
    end

    # Check if caching is bypassed
    def bypassed? : Bool
      @bypass
    end
  end

  # Extension to Query class to easily create cached queries
  class Query
    # Wrap this query with caching
    def cached(cache : Cache::QueryCache, ttl : Time::Span? = nil, tags : Array(String) = [] of String) : CachedQuery
      CachedQuery.new(self, cache, ttl, tags)
    end
  end
end
