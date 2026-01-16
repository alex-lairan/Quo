require "../spec_helper"

describe Quo::ConnectionRole do
  it "has Primary and Replica variants" do
    Quo::ConnectionRole::Primary.should be_a(Quo::ConnectionRole)
    Quo::ConnectionRole::Replica.should be_a(Quo::ConnectionRole)
  end
end

describe Quo::ReplicaStrategy do
  it "has RoundRobin, Random, and LeastConnections variants" do
    Quo::ReplicaStrategy::RoundRobin.should be_a(Quo::ReplicaStrategy)
    Quo::ReplicaStrategy::Random.should be_a(Quo::ReplicaStrategy)
    Quo::ReplicaStrategy::LeastConnections.should be_a(Quo::ReplicaStrategy)
  end
end

describe Quo::PoolConfig do
  describe "#initialize" do
    it "has default values" do
      config = Quo::PoolConfig.new

      config.initial_size.should eq(1)
      config.max_size.should eq(10)
      config.max_idle.should eq(5)
      config.checkout_timeout.should eq(5.seconds)
      config.retry_attempts.should eq(3)
    end

    it "accepts custom values" do
      config = Quo::PoolConfig.new(
        initial_size: 5,
        max_size: 25,
        max_idle: 10,
        checkout_timeout: 10.seconds,
        retry_attempts: 5,
        retry_delay: 500.milliseconds
      )

      config.initial_size.should eq(5)
      config.max_size.should eq(25)
      config.max_idle.should eq(10)
      config.checkout_timeout.should eq(10.seconds)
      config.retry_attempts.should eq(5)
      config.retry_delay.should eq(500.milliseconds)
    end
  end
end
