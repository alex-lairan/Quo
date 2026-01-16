require "json"
require "base64"
require "./cache_store"

module Quo
  module Cache
    # Cache statistics
    struct CacheStats
      getter hits : Int64
      getter misses : Int64
      getter size : Int32
      getter evictions : Int64

      def initialize(
        @hits : Int64 = 0_i64,
        @misses : Int64 = 0_i64,
        @size : Int32 = 0,
        @evictions : Int64 = 0_i64
      )
      end

      def hit_rate : Float64
        total = @hits + @misses
        return 0.0 if total == 0
        @hits.to_f64 / total.to_f64
      end

      def total_requests : Int64
        @hits + @misses
      end
    end

    # Query cache manager
    # Caches query results with TTL and tag-based invalidation
    #
    # Example:
    # ```
    # cache = Quo::Cache::QueryCache.new(
    #   store: Quo::Cache::MemoryCacheStore.new,
    #   default_ttl: 5.minutes
    # )
    #
    # # Cache a query result
    # result = cache.fetch("users:active", ttl: 10.minutes, tags: ["users"]) do
    #   adapter.execute(sql, params)
    # end
    #
    # # Invalidate by tag
    # cache.invalidate_tag("users")
    #
    # # Bypass cache
    # cache.bypass do
    #   # Queries here skip the cache
    # end
    # ```
    class QueryCache
      @store : CacheStore
      @default_ttl : Time::Span
      @enabled : Bool
      @hits : Atomic(Int64)
      @misses : Atomic(Int64)
      @evictions : Atomic(Int64)

      # Fiber-local bypass flag
      @@bypass_fiber_local : Bool = false

      def initialize(
        @store : CacheStore = MemoryCacheStore.new,
        @default_ttl : Time::Span = 5.minutes,
        @enabled : Bool = true
      )
        @hits = Atomic(Int64).new(0_i64)
        @misses = Atomic(Int64).new(0_i64)
        @evictions = Atomic(Int64).new(0_i64)
      end

      # Generate cache key from SQL and parameters
      def cache_key(sql : String, params : Array(DB::Any)) : String
        content = "#{sql}:#{params.map(&.to_s).join(",")}"
        "quo:query:#{content.hash}"
      end

      # Fetch from cache or execute block
      def fetch(
        key : String,
        ttl : Time::Span? = nil,
        tags : Array(String) = [] of String,
        &block : -> Quo::ResultSet
      ) : Quo::ResultSet
        return yield unless @enabled && !bypassed?

        full_key = normalize_key(key)

        # Try to get from cache
        if cached = @store.get(full_key)
          @hits.add(1)
          return deserialize_result(cached)
        end

        @misses.add(1)

        # Execute and cache
        result = yield

        # Store in cache
        @store.set(full_key, serialize_result(result), ttl || @default_ttl)

        # Associate with tags
        tags.each do |tag|
          @store.set_add(tag_key(tag), full_key)
        end

        result
      end

      # Fetch using SQL and params as key
      def fetch_query(
        sql : String,
        params : Array(DB::Any),
        ttl : Time::Span? = nil,
        tags : Array(String) = [] of String,
        &block : -> Quo::ResultSet
      ) : Quo::ResultSet
        key = cache_key(sql, params)
        fetch(key, ttl, tags, &block)
      end

      # Get a cached value by key
      def get(key : String) : Quo::ResultSet?
        full_key = normalize_key(key)
        if cached = @store.get(full_key)
          @hits.add(1)
          deserialize_result(cached)
        else
          @misses.add(1)
          nil
        end
      end

      # Set a value in cache
      def set(key : String, value : Quo::ResultSet, ttl : Time::Span? = nil, tags : Array(String) = [] of String) : Nil
        full_key = normalize_key(key)
        @store.set(full_key, serialize_result(value), ttl || @default_ttl)

        tags.each do |tag|
          @store.set_add(tag_key(tag), full_key)
        end
      end

      # Invalidate a specific key
      def invalidate(key : String) : Bool
        full_key = normalize_key(key)
        if @store.delete(full_key)
          @evictions.add(1)
          true
        else
          false
        end
      end

      # Invalidate keys matching a pattern
      def invalidate_pattern(pattern : String) : Int32
        full_pattern = normalize_key(pattern)
        keys = @store.keys(full_pattern)
        return 0 if keys.empty?

        count = @store.delete_all(keys)
        @evictions.add(count.to_i64)
        count
      end

      # Invalidate all keys associated with a tag
      def invalidate_tag(tag : String) : Int32
        keys = @store.set_members(tag_key(tag))
        return 0 if keys.empty?

        count = @store.delete_all(keys)
        @store.set_delete(tag_key(tag))
        @evictions.add(count.to_i64)
        count
      end

      # Invalidate multiple tags
      def invalidate_tags(*tags : String) : Int32
        total = 0
        tags.each { |tag| total += invalidate_tag(tag) }
        total
      end

      # Clear the entire cache
      def clear : Nil
        size = @store.size
        @store.clear
        @evictions.add(size.to_i64)
      end

      # Bypass cache for a block
      def bypass(&block)
        old_bypass = @@bypass_fiber_local
        @@bypass_fiber_local = true
        begin
          yield
        ensure
          @@bypass_fiber_local = old_bypass
        end
      end

      # Check if cache is currently bypassed
      def bypassed? : Bool
        @@bypass_fiber_local
      end

      # Get cache statistics
      def stats : CacheStats
        CacheStats.new(
          hits: @hits.get,
          misses: @misses.get,
          size: @store.size,
          evictions: @evictions.get
        )
      end

      # Enable or disable cache
      def enabled=(value : Bool)
        @enabled = value
      end

      def enabled? : Bool
        @enabled
      end

      # Access underlying store
      def store : CacheStore
        @store
      end

      # Default TTL
      def default_ttl : Time::Span
        @default_ttl
      end

      def default_ttl=(value : Time::Span)
        @default_ttl = value
      end

      private def normalize_key(key : String) : String
        key.starts_with?("quo:") ? key : "quo:query:#{key}"
      end

      private def tag_key(tag : String) : String
        "quo:tag:#{tag}"
      end

      private def serialize_result(result : Quo::ResultSet) : String
        # Serialize to JSON for storage
        # We need to manually handle types that don't serialize well
        JSON.build do |json|
          json.array do
            result.each do |row|
              json.object do
                row.each do |key, value|
                  json.field key do
                    value_to_json(value, json)
                  end
                end
              end
            end
          end
        end
      end

      private def value_to_json(value : Quo::Value, json : JSON::Builder) : Nil
        case value
        when Nil
          json.null
        when Bool
          json.bool(value)
        when Int8, Int16, Int32, Int64, UInt8, UInt16, UInt32, UInt64
          json.number(value.to_i64)
        when Float32, Float64
          json.number(value.to_f64)
        when String
          json.string(value)
        when Time
          json.string(value.to_rfc3339)
        when Slice(UInt8)
          # Encode bytes as base64
          json.string("base64:#{Base64.strict_encode(value)}")
        when Char
          json.string(value.to_s)
        else
          # For complex types (PG types, etc.), convert to string
          json.string(value.to_s)
        end
      end

      private def deserialize_result(data : String) : Quo::ResultSet
        # Deserialize from JSON
        # Note: This requires Quo::Row to be JSON serializable
        Array(Hash(String, JSON::Any)).from_json(data).map do |hash|
          row = {} of String => Quo::Value
          hash.each do |key, value|
            row[key] = json_any_to_value(value)
          end
          row
        end
      end

      private def json_any_to_value(json : JSON::Any) : Quo::Value
        case json.raw
        when Nil then nil
        when Bool then json.as_bool
        when Int64 then json.as_i64
        when Float64 then json.as_f
        when String
          str = json.as_s
          # Check for base64-encoded bytes
          if str.starts_with?("base64:")
            Base64.decode(str[7..])
          else
            str
          end
        else
          # For complex types, store as string
          json.to_s
        end
      end
    end
  end
end
