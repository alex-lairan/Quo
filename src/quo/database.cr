require "./connection_pool"
require "./adapters/adapter"

module Quo
  # Role enum for connection routing
  enum ConnectionRole
    Primary
    Replica
  end

  # Routing strategy for read queries to replicas
  enum ReplicaStrategy
    # Round-robin selection across replicas
    RoundRobin
    # Random selection
    Random
    # Select replica with fewest in-use connections
    LeastConnections
  end

  # Manages primary and replica connections with automatic routing
  #
  # Example:
  # ```
  # db = Quo::Database.new(
  #   primary: Quo::ConnectionPool.new("postgres://primary/myapp"),
  #   replicas: [
  #     Quo::ConnectionPool.new("postgres://replica1/myapp"),
  #     Quo::ConnectionPool.new("postgres://replica2/myapp"),
  #   ],
  #   replica_strategy: Quo::ReplicaStrategy::RoundRobin
  # )
  #
  # # Reads automatically go to replicas
  # db.for_read.checkout { |conn| ... }
  #
  # # Writes always go to primary
  # db.for_write.checkout { |conn| ... }
  #
  # # Force all queries to primary (e.g., after a write)
  # db.use_primary do
  #   # All reads here go to primary
  # end
  # ```
  class Database
    @primary : ConnectionPool
    @replicas : Array(ConnectionPool)
    @replica_strategy : ReplicaStrategy
    @replica_index : Atomic(Int32)
    @force_primary : Bool

    def initialize(
      @primary : ConnectionPool,
      @replicas : Array(ConnectionPool) = [] of ConnectionPool,
      @replica_strategy : ReplicaStrategy = ReplicaStrategy::RoundRobin
    )
      @replica_index = Atomic(Int32).new(0)
      @force_primary = false
    end

    # Get pool for a specific role
    def pool_for(role : ConnectionRole) : ConnectionPool
      case role
      when ConnectionRole::Primary
        @primary
      when ConnectionRole::Replica
        select_replica
      else
        @primary
      end
    end

    # Get pool for read operations
    # Routes to replicas unless forced to primary
    def for_read : ConnectionPool
      return @primary if @replicas.empty? || @force_primary
      select_replica
    end

    # Get pool for write operations
    # Always returns primary
    def for_write : ConnectionPool
      @primary
    end

    # Force all queries to primary within block
    # Use after a write when you need to read your own writes
    def use_primary(&block)
      old_force = @force_primary
      @force_primary = true
      begin
        yield
      ensure
        @force_primary = old_force
      end
    end

    # Create an adapter for the given role
    def adapter_for(role : ConnectionRole, adapter_type : Symbol = :postgres) : Adapters::Adapter
      pool = pool_for(role)
      create_adapter(pool, adapter_type)
    end

    # Create a read adapter (uses replicas)
    def read_adapter(adapter_type : Symbol = :postgres) : Adapters::Adapter
      create_adapter(for_read, adapter_type)
    end

    # Create a write adapter (uses primary)
    def write_adapter(adapter_type : Symbol = :postgres) : Adapters::Adapter
      create_adapter(for_write, adapter_type)
    end

    # Execute a transaction (always on primary)
    def transaction(isolation : IsolationLevel? = nil, adapter_type : Symbol = :postgres, &block)
      use_primary do
        adapter = create_adapter(@primary, adapter_type)
        adapter.transaction(isolation) do |tx|
          yield tx
        end
      end
    end

    # Get statistics for all pools
    def stats : Hash(String, PoolStats)
      result = {"primary" => @primary.stats}
      @replicas.each_with_index do |replica, i|
        result["replica_#{i}"] = replica.stats
      end
      result
    end

    # Check if all pools are healthy
    def healthy? : Bool
      return false unless @primary.healthy?
      @replicas.all?(&.healthy?)
    end

    # Close all pools gracefully
    def close(timeout : Time::Span = 30.seconds) : Nil
      @primary.close(timeout)
      @replicas.each(&.close(timeout))
    end

    # Primary pool
    def primary : ConnectionPool
      @primary
    end

    # Replica pools
    def replicas : Array(ConnectionPool)
      @replicas
    end

    # Check if replicas are configured
    def has_replicas? : Bool
      !@replicas.empty?
    end

    private def select_replica : ConnectionPool
      return @primary if @replicas.empty?

      case @replica_strategy
      when ReplicaStrategy::RoundRobin
        idx = @replica_index.add(1) % @replicas.size
        @replicas[idx]
      when ReplicaStrategy::Random
        @replicas.sample
      when ReplicaStrategy::LeastConnections
        @replicas.min_by { |r| r.stats.in_use }
      else
        @replicas.first
      end
    end

    private def create_adapter(pool : ConnectionPool, adapter_type : Symbol) : Adapters::Adapter
      case adapter_type
      when :postgres
        Adapters::PooledPostgres.new(pool)
      when :sqlite
        Adapters::PooledSQLite.new(pool)
      when :mysql
        Adapters::PooledMySQL.new(pool)
      else
        raise AdapterError.new("Unknown adapter type: #{adapter_type}")
      end
    end
  end
end
