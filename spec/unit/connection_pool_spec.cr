require "../spec_helper"

describe Quo::PoolConfig do
  describe "#initialize" do
    it "has sensible defaults" do
      config = Quo::PoolConfig.new

      config.initial_size.should eq(1)
      config.max_size.should eq(10)
      config.max_idle.should eq(5)
      config.checkout_timeout.should eq(5.seconds)
      config.retry_attempts.should eq(3)
      config.retry_delay.should eq(200.milliseconds)
      config.health_check_interval.should be_nil
    end

    it "accepts custom values" do
      config = Quo::PoolConfig.new(
        initial_size: 5,
        max_size: 25,
        max_idle: 10,
        checkout_timeout: 10.seconds,
        retry_attempts: 5,
        retry_delay: 500.milliseconds,
        health_check_interval: 30.seconds
      )

      config.initial_size.should eq(5)
      config.max_size.should eq(25)
      config.max_idle.should eq(10)
      config.checkout_timeout.should eq(10.seconds)
      config.retry_attempts.should eq(5)
      config.retry_delay.should eq(500.milliseconds)
      config.health_check_interval.should eq(30.seconds)
    end
  end

  describe "#to_db_pool_options" do
    it "converts to DB::Pool::Options" do
      config = Quo::PoolConfig.new(
        initial_size: 2,
        max_size: 20,
        max_idle: 5,
        checkout_timeout: 10.seconds,
        retry_attempts: 3,
        retry_delay: 100.milliseconds
      )

      opts = config.to_db_pool_options

      opts.initial_pool_size.should eq(2)
      opts.max_pool_size.should eq(20)
      opts.max_idle_pool_size.should eq(5)
      opts.checkout_timeout.should eq(10.0)
      opts.retry_attempts.should eq(3)
      opts.retry_delay.should be_close(0.1, 0.01)
    end
  end
end

describe Quo::PoolStats do
  describe "#initialize" do
    it "has zero defaults" do
      stats = Quo::PoolStats.new

      stats.open_connections.should eq(0)
      stats.idle_connections.should eq(0)
      stats.in_use.should eq(0)
      stats.max_connections.should eq(0)
      stats.total_checkouts.should eq(0_i64)
      stats.total_timeouts.should eq(0_i64)
      stats.health_check_failures.should eq(0_i64)
    end

    it "accepts values" do
      stats = Quo::PoolStats.new(
        open_connections: 10,
        idle_connections: 7,
        in_use: 3,
        max_connections: 25,
        total_checkouts: 1000_i64,
        total_timeouts: 5_i64,
        health_check_failures: 2_i64
      )

      stats.open_connections.should eq(10)
      stats.idle_connections.should eq(7)
      stats.in_use.should eq(3)
      stats.max_connections.should eq(25)
      stats.total_checkouts.should eq(1000_i64)
      stats.total_timeouts.should eq(5_i64)
      stats.health_check_failures.should eq(2_i64)
    end
  end

  describe "#utilization" do
    it "returns 0 when no connections" do
      stats = Quo::PoolStats.new(open_connections: 0)
      stats.utilization.should eq(0.0)
    end

    it "calculates utilization correctly" do
      stats = Quo::PoolStats.new(
        open_connections: 10,
        in_use: 5
      )
      stats.utilization.should eq(0.5)
    end

    it "returns 1.0 when all connections in use" do
      stats = Quo::PoolStats.new(
        open_connections: 10,
        in_use: 10
      )
      stats.utilization.should eq(1.0)
    end
  end
end
