require "./database"

module Quo
  # Abstract sharding strategy
  # Determines which shard a key should be routed to
  abstract class ShardingStrategy
    abstract def shard_for(key_value : DB::Any, shard_count : Int32) : Int32
  end

  # Modulo-based sharding (hash % shard_count)
  # Distributes keys evenly across shards
  class ModuloSharding < ShardingStrategy
    def shard_for(key_value : DB::Any, shard_count : Int32) : Int32
      hash = case key_value
             when Int32, Int64
               key_value.to_i64.abs
             when String
               key_value.hash.abs
             else
               key_value.hash.abs
             end
      (hash % shard_count).to_i32
    end
  end

  # Range-based sharding
  # Maps value ranges to specific shards
  class RangeSharding < ShardingStrategy
    # Each range is (min, max, shard_id)
    @ranges : Array({Int64, Int64, Int32})

    def initialize(@ranges : Array({Int64, Int64, Int32}))
    end

    def shard_for(key_value : DB::Any, shard_count : Int32) : Int32
      value = case key_value
              when Int32 then key_value.to_i64
              when Int64 then key_value
              else
                raise ShardingError.new("RangeSharding requires integer keys, got #{key_value.class}")
              end

      @ranges.each do |(min, max, shard_id)|
        if value >= min && value <= max
          return shard_id
        end
      end

      raise ShardingError.new("No shard range found for value: #{value}")
    end
  end

  # Hash-based sharding with consistent hashing
  # More stable than modulo when adding/removing shards
  class ConsistentHashSharding < ShardingStrategy
    @virtual_nodes : Int32
    @ring : Array({UInt64, Int32}) # hash -> shard_id

    def initialize(shard_count : Int32, @virtual_nodes : Int32 = 100)
      @ring = [] of {UInt64, Int32}

      # Create virtual nodes for each shard
      shard_count.times do |shard_id|
        @virtual_nodes.times do |i|
          key = "shard_#{shard_id}_vnode_#{i}"
          hash = hash_key(key)
          @ring << {hash, shard_id}
        end
      end

      # Sort ring by hash value
      @ring.sort_by! { |h, _| h }
    end

    def shard_for(key_value : DB::Any, shard_count : Int32) : Int32
      hash = hash_key(key_value.to_s)

      # Binary search for the first node with hash >= key hash
      idx = @ring.bsearch_index { |entry| entry[0] >= hash }

      if idx.nil?
        # Wrap around to first node
        @ring.first[1]
      else
        @ring[idx][1]
      end
    end

    private def hash_key(key : String) : UInt64
      # Simple hash function (FNV-1a)
      hash = 14695981039346656037_u64
      key.each_byte do |byte|
        hash ^= byte.to_u64
        hash &*= 1099511628211_u64
      end
      hash
    end
  end

  # Manages sharded databases
  #
  # Example:
  # ```
  # shards = [
  #   Quo::Database.new(primary: pool_shard_0),
  #   Quo::Database.new(primary: pool_shard_1),
  #   Quo::Database.new(primary: pool_shard_2),
  # ]
  #
  # manager = Quo::ShardManager.new(
  #   shards: shards,
  #   strategy: Quo::ModuloSharding.new
  # )
  #
  # # Route to specific shard by key
  # manager.for_key(user_id) do |db|
  #   db.read_adapter.execute(...)
  # end
  #
  # # Query across all shards
  # results = manager.across_all_shards do |db, shard_id|
  #   Query.new(:users, db.read_adapter).where(...).to_a
  # end
  # ```
  class ShardManager
    @shards : Array(Database)
    @strategy : ShardingStrategy

    def initialize(
      @shards : Array(Database),
      @strategy : ShardingStrategy = ModuloSharding.new
    )
      raise ShardingError.new("At least one shard is required") if @shards.empty?
    end

    # Get database for a specific shard key value
    def for_key(key_value : DB::Any) : Database
      shard_id = @strategy.shard_for(key_value, @shards.size)
      @shards[shard_id]
    end

    # Execute block on the shard for the given key
    def on_shard(key_value : DB::Any, &block : Database ->)
      db = for_key(key_value)
      yield db
    end

    # Get database for a specific shard by index
    def shard(index : Int32) : Database
      raise ShardingError.new("Shard index #{index} out of range (0..#{@shards.size - 1})") if index < 0 || index >= @shards.size
      @shards[index]
    end

    # Execute block on a specific shard by index
    def on_shard_index(index : Int32, &block : Database ->)
      yield shard(index)
    end

    # Execute block on each shard sequentially
    def each_shard(&block : Database, Int32 ->)
      @shards.each_with_index do |db, idx|
        yield db, idx
      end
    end

    # Execute block on all shards and collect results
    def across_all_shards(&block : Database, Int32 -> T) : Array(T) forall T
      results = [] of T
      @shards.each_with_index do |db, idx|
        results << yield(db, idx)
      end
      results
    end

    # Execute block on all shards in parallel and collect results
    def parallel_across_shards(&block : Database, Int32 -> T) : Array(T) forall T
      channel = Channel(Tuple(Int32, T)).new(@shards.size)

      @shards.each_with_index do |db, idx|
        spawn do
          result = yield(db, idx)
          channel.send({idx, result})
        end
      end

      # Collect results in order
      results = Array(T?).new(@shards.size, nil)
      @shards.size.times do
        idx, result = channel.receive
        results[idx] = result
      end

      results.map(&.not_nil!)
    end

    # Execute a query across all shards and merge results
    def query_all(table : Symbol, adapter_type : Symbol = :postgres, &block : Query -> Query) : Quo::ResultSet
      results = [] of Quo::Row

      each_shard do |db, _|
        adapter = db.read_adapter(adapter_type)
        query = Query.new(table, adapter)
        modified_query = yield query
        results.concat(modified_query.to_a)
      end

      results
    end

    # Execute a query across all shards in parallel and merge results
    def parallel_query_all(table : Symbol, adapter_type : Symbol = :postgres, &block : Query -> Query) : Quo::ResultSet
      shard_results = parallel_across_shards do |db, _|
        adapter = db.read_adapter(adapter_type)
        query = Query.new(table, adapter)
        modified_query = yield query
        modified_query.to_a
      end

      # Flatten results
      results = [] of Quo::Row
      shard_results.each { |r| results.concat(r) }
      results
    end

    # Count across all shards
    def count_all(table : Symbol, adapter_type : Symbol = :postgres, &block : Query -> Query) : Int64
      total = 0_i64

      each_shard do |db, _|
        adapter = db.read_adapter(adapter_type)
        query = Query.new(table, adapter)
        modified_query = yield query
        total += modified_query.count
      end

      total
    end

    # Get statistics for all shards
    def stats : Hash(String, Hash(String, PoolStats))
      result = {} of String => Hash(String, PoolStats)
      @shards.each_with_index do |db, idx|
        result["shard_#{idx}"] = db.stats
      end
      result
    end

    # Check if all shards are healthy
    def healthy? : Bool
      @shards.all?(&.healthy?)
    end

    # Close all shards
    def close(timeout : Time::Span = 30.seconds) : Nil
      @shards.each(&.close(timeout))
    end

    # Number of shards
    def shard_count : Int32
      @shards.size
    end

    # Access sharding strategy
    def strategy : ShardingStrategy
      @strategy
    end
  end
end
