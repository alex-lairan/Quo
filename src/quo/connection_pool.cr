require "db"
require "uri"
require "http/params"

module Quo
  # Configuration for connection pool
  # Wraps DB::Pool::Options with a Quo-friendly API using Time::Span
  struct PoolConfig
    # Initial number of connections to create
    getter initial_size : Int32

    # Maximum connections in pool (0 = unlimited)
    getter max_size : Int32

    # Maximum idle connections to keep
    getter max_idle : Int32

    # Timeout for checkout operation
    getter checkout_timeout : Time::Span

    # Number of retry attempts on connection failure
    getter retry_attempts : Int32

    # Delay between retry attempts
    getter retry_delay : Time::Span

    # Interval for health checks (nil = disabled)
    getter health_check_interval : Time::Span?

    def initialize(
      @initial_size : Int32 = 1,
      @max_size : Int32 = 10,
      @max_idle : Int32 = 5,
      @checkout_timeout : Time::Span = 5.seconds,
      @retry_attempts : Int32 = 3,
      @retry_delay : Time::Span = 200.milliseconds,
      @health_check_interval : Time::Span? = nil
    )
    end

    # Convert to DB::Pool::Options for the underlying Crystal DB library
    def to_db_pool_options : DB::Pool::Options
      DB::Pool::Options.new(
        initial_pool_size: @initial_size,
        max_pool_size: @max_size,
        max_idle_pool_size: @max_idle,
        checkout_timeout: @checkout_timeout.total_seconds,
        retry_attempts: @retry_attempts,
        retry_delay: @retry_delay.total_seconds
      )
    end
  end

  # Pool statistics
  struct PoolStats
    # Total open connections
    getter open_connections : Int32

    # Idle connections available for checkout
    getter idle_connections : Int32

    # Connections currently in use
    getter in_use : Int32

    # Maximum configured connections
    getter max_connections : Int32

    # Total checkouts performed
    getter total_checkouts : Int64

    # Total checkout timeouts
    getter total_timeouts : Int64

    # Total health check failures
    getter health_check_failures : Int64

    def initialize(
      @open_connections : Int32 = 0,
      @idle_connections : Int32 = 0,
      @in_use : Int32 = 0,
      @max_connections : Int32 = 0,
      @total_checkouts : Int64 = 0_i64,
      @total_timeouts : Int64 = 0_i64,
      @health_check_failures : Int64 = 0_i64
    )
    end

    # Utilization percentage (in_use / open_connections)
    def utilization : Float64
      return 0.0 if @open_connections == 0
      @in_use.to_f64 / @open_connections.to_f64
    end
  end

  # Connection pool wrapping DB::Database with Quo-specific features:
  # - Health checks
  # - Extended statistics
  # - Graceful shutdown
  class ConnectionPool
    @db : DB::Database
    @config : PoolConfig
    @total_checkouts : Atomic(Int64)
    @total_timeouts : Atomic(Int64)
    @health_check_failures : Atomic(Int64)
    @closed : Bool
    @health_check_fiber : Fiber?

    def initialize(uri : String, @config : PoolConfig = PoolConfig.new)
      # Build URI with pool options as query parameters
      @db = DB.open(build_uri_with_pool_options(uri, @config))
      @total_checkouts = Atomic(Int64).new(0_i64)
      @total_timeouts = Atomic(Int64).new(0_i64)
      @health_check_failures = Atomic(Int64).new(0_i64)
      @closed = false

      # Start health check fiber if interval is configured
      if interval = @config.health_check_interval
        start_health_check_fiber(interval)
      end
    end

    private def build_uri_with_pool_options(uri : String, config : PoolConfig) : String
      parsed = URI.parse(uri)

      # Build query params for pool options
      params = HTTP::Params.new
      # Preserve existing query params
      if existing = parsed.query
        HTTP::Params.parse(existing).each { |k, v| params.add(k, v) }
      end

      # Add pool options
      params["initial_pool_size"] = config.initial_size.to_s
      params["max_pool_size"] = config.max_size.to_s
      params["max_idle_pool_size"] = config.max_idle.to_s
      params["checkout_timeout"] = config.checkout_timeout.total_seconds.to_s
      params["retry_attempts"] = config.retry_attempts.to_s
      params["retry_delay"] = config.retry_delay.total_seconds.to_s

      parsed.query = params.to_s
      parsed.to_s
    end

    # Alternative constructor with explicit DB::Database
    def initialize(@db : DB::Database, @config : PoolConfig = PoolConfig.new)
      @total_checkouts = Atomic(Int64).new(0_i64)
      @total_timeouts = Atomic(Int64).new(0_i64)
      @health_check_failures = Atomic(Int64).new(0_i64)
      @closed = false

      if interval = @config.health_check_interval
        start_health_check_fiber(interval)
      end
    end

    # Checkout a connection and execute block
    # Connection is automatically released when block completes
    def checkout(&block : DB::Connection ->)
      raise ConnectionError.new("Pool is closed") if @closed

      @total_checkouts.add(1)

      begin
        @db.using_connection do |conn|
          yield conn
        end
      rescue ex : DB::PoolTimeout
        @total_timeouts.add(1)
        raise PoolTimeoutError.new(@config.checkout_timeout)
      end
    end

    # Checkout a connection with optional health check
    def checkout_with_health_check(&block : DB::Connection ->)
      raise ConnectionError.new("Pool is closed") if @closed

      @total_checkouts.add(1)

      begin
        @db.using_connection do |conn|
          # Perform health check
          begin
            conn.exec("SELECT 1")
          rescue ex
            @health_check_failures.add(1)
            raise ConnectionError.new("Health check failed: #{ex.message}")
          end
          yield conn
        end
      rescue ex : DB::PoolTimeout
        @total_timeouts.add(1)
        raise PoolTimeoutError.new(@config.checkout_timeout)
      end
    end

    # Execute a query directly (uses pool checkout internally)
    def query(sql : String, *args, **kwargs, &block : DB::ResultSet ->)
      checkout do |conn|
        conn.query(sql, *args, **kwargs) do |rs|
          yield rs
        end
      end
    end

    # Execute a statement that doesn't return results
    def exec(sql : String, *args, **kwargs) : DB::ExecResult
      result = nil
      checkout do |conn|
        result = conn.exec(sql, *args, **kwargs)
      end
      result.not_nil!
    end

    # Get current pool statistics
    def stats : PoolStats
      db_stats = @db.pool.stats

      PoolStats.new(
        open_connections: db_stats.open_connections,
        idle_connections: db_stats.idle_connections,
        in_use: db_stats.open_connections - db_stats.idle_connections,
        max_connections: db_stats.max_connections,
        total_checkouts: @total_checkouts.get,
        total_timeouts: @total_timeouts.get,
        health_check_failures: @health_check_failures.get
      )
    end

    # Check if pool is healthy (has available connections)
    def healthy? : Bool
      return false if @closed

      stats = @db.pool.stats
      stats.idle_connections > 0 || stats.open_connections < @config.max_size || @config.max_size == 0
    end

    # Close the pool gracefully
    # Waits for in-use connections to be released up to timeout
    def close(timeout : Time::Span = 30.seconds) : Bool
      return true if @closed

      @closed = true
      @health_check_fiber.try { |f| f.cancel if f.responds_to?(:cancel) }

      deadline = Time.utc + timeout

      # Wait for connections to be released
      loop do
        stats = @db.pool.stats
        break if stats.open_connections == stats.idle_connections
        break if Time.utc > deadline

        sleep 100.milliseconds
      end

      @db.close
      true
    end

    # Check if pool is closed
    def closed? : Bool
      @closed
    end

    # Access underlying database (for advanced use)
    def database : DB::Database
      @db
    end

    # Pool configuration
    def config : PoolConfig
      @config
    end

    private def start_health_check_fiber(interval : Time::Span)
      @health_check_fiber = spawn do
        loop do
          sleep interval
          break if @closed

          # Ping a connection to verify pool health
          begin
            @db.using_connection do |conn|
              conn.exec("SELECT 1")
            end
          rescue
            @health_check_failures.add(1)
          end
        end
      end
    end
  end
end
