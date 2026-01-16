module Quo
  module Cache
    # Abstract cache store interface
    # Implementations provide storage backends for the query cache
    abstract class CacheStore
      # Get a value by key
      abstract def get(key : String) : String?

      # Set a value with TTL
      abstract def set(key : String, value : String, ttl : Time::Span) : Nil

      # Delete a key
      abstract def delete(key : String) : Bool

      # Delete multiple keys
      abstract def delete_all(keys : Array(String)) : Int32

      # Find keys matching a pattern (supports * wildcard)
      abstract def keys(pattern : String) : Array(String)

      # Clear all entries
      abstract def clear : Nil

      # Get number of entries
      abstract def size : Int32

      # Add member to a set
      abstract def set_add(key : String, member : String) : Nil

      # Get all members of a set
      abstract def set_members(key : String) : Array(String)

      # Delete a set
      abstract def set_delete(key : String) : Bool
    end

    # In-memory cache store with TTL support and LRU eviction
    class MemoryCacheStore < CacheStore
      @data : Hash(String, CacheEntry)
      @sets : Hash(String, Set(String))
      @mutex : Mutex
      @max_size : Int32

      struct CacheEntry
        getter value : String
        getter expires_at : Time

        def initialize(@value : String, ttl : Time::Span)
          @expires_at = Time.utc + ttl
        end

        def expired? : Bool
          Time.utc > @expires_at
        end
      end

      def initialize(@max_size : Int32 = 10_000)
        @data = {} of String => CacheEntry
        @sets = {} of String => Set(String)
        @mutex = Mutex.new
      end

      def get(key : String) : String?
        @mutex.synchronize do
          entry = @data[key]?
          return nil unless entry

          if entry.expired?
            @data.delete(key)
            return nil
          end

          entry.value
        end
      end

      def set(key : String, value : String, ttl : Time::Span) : Nil
        @mutex.synchronize do
          # Evict if at capacity and adding new key
          if @data.size >= @max_size && !@data.has_key?(key)
            evict_expired_or_oldest
          end

          @data[key] = CacheEntry.new(value, ttl)
        end
      end

      def delete(key : String) : Bool
        @mutex.synchronize do
          !!@data.delete(key)
        end
      end

      def delete_all(keys : Array(String)) : Int32
        count = 0
        @mutex.synchronize do
          keys.each do |key|
            if @data.delete(key)
              count += 1
            end
          end
        end
        count
      end

      def keys(pattern : String) : Array(String)
        # Convert glob pattern to regex
        regex_pattern = pattern
          .gsub("*", ".*")
          .gsub("?", ".")

        regex = Regex.new("^#{regex_pattern}$")

        @mutex.synchronize do
          @data.keys.select { |k| regex.matches?(k) }
        end
      end

      def clear : Nil
        @mutex.synchronize do
          @data.clear
          @sets.clear
        end
      end

      def size : Int32
        @mutex.synchronize do
          # Clean expired entries while counting
          @data.reject! { |_, v| v.expired? }
          @data.size
        end
      end

      def set_add(key : String, member : String) : Nil
        @mutex.synchronize do
          @sets[key] ||= Set(String).new
          @sets[key] << member
        end
      end

      def set_members(key : String) : Array(String)
        @mutex.synchronize do
          @sets[key]?.try(&.to_a) || [] of String
        end
      end

      def set_delete(key : String) : Bool
        @mutex.synchronize do
          !!@sets.delete(key)
        end
      end

      # Manually clean expired entries
      def cleanup : Int32
        count = 0
        @mutex.synchronize do
          @data.reject! do |_, v|
            if v.expired?
              count += 1
              true
            else
              false
            end
          end
        end
        count
      end

      private def evict_expired_or_oldest
        # First try to remove expired entries
        expired_keys = @data.select { |_, v| v.expired? }.keys
        if !expired_keys.empty?
          expired_keys.each { |k| @data.delete(k) }
          return
        end

        # If no expired entries, remove oldest (first inserted - approximation)
        # In a real LRU implementation, we'd track access times
        if oldest_key = @data.keys.first?
          @data.delete(oldest_key)
        end
      end
    end
  end
end
