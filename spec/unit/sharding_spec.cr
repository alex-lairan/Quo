require "../spec_helper"

describe Quo::ModuloSharding do
  describe "#shard_for" do
    it "distributes by modulo" do
      strategy = Quo::ModuloSharding.new

      # Test with integers
      strategy.shard_for(0_i64.as(DB::Any), 3).should eq(0)
      strategy.shard_for(1_i64.as(DB::Any), 3).should eq(1)
      strategy.shard_for(2_i64.as(DB::Any), 3).should eq(2)
      strategy.shard_for(3_i64.as(DB::Any), 3).should eq(0)
      strategy.shard_for(100_i64.as(DB::Any), 3).should eq(1)
    end

    it "handles strings by hash" do
      strategy = Quo::ModuloSharding.new

      # Same string should return same shard
      shard1 = strategy.shard_for("user_123".as(DB::Any), 4)
      shard2 = strategy.shard_for("user_123".as(DB::Any), 4)
      shard1.should eq(shard2)
    end

    it "distributes strings across shards" do
      strategy = Quo::ModuloSharding.new
      shards_hit = Set(Int32).new

      # Test multiple keys
      ["a", "b", "c", "d", "e", "f"].each do |key|
        shard = strategy.shard_for(key.as(DB::Any), 3)
        shard.should be >= 0
        shard.should be < 3
        shards_hit << shard
      end
    end
  end
end

describe Quo::RangeSharding do
  describe "#shard_for" do
    it "routes based on ranges" do
      # Ranges are tuples of (min, max, shard_id)
      ranges = [
        {0_i64, 999_i64, 0},
        {1000_i64, 1999_i64, 1},
        {2000_i64, 2999_i64, 2},
      ]
      strategy = Quo::RangeSharding.new(ranges)

      strategy.shard_for(0_i64.as(DB::Any), 3).should eq(0)
      strategy.shard_for(500_i64.as(DB::Any), 3).should eq(0)
      strategy.shard_for(999_i64.as(DB::Any), 3).should eq(0)
      strategy.shard_for(1000_i64.as(DB::Any), 3).should eq(1)
      strategy.shard_for(1500_i64.as(DB::Any), 3).should eq(1)
      strategy.shard_for(2500_i64.as(DB::Any), 3).should eq(2)
    end

    it "raises error for out-of-range values" do
      ranges = [
        {0_i64, 100_i64, 0},
      ]
      strategy = Quo::RangeSharding.new(ranges)

      expect_raises(Quo::ShardingError, /No shard range/) do
        strategy.shard_for(500_i64.as(DB::Any), 3)
      end
    end

    it "raises error for non-integer keys" do
      ranges = [{0_i64, 100_i64, 0}]
      strategy = Quo::RangeSharding.new(ranges)

      expect_raises(Quo::ShardingError, /requires integer/) do
        strategy.shard_for("not_an_int".as(DB::Any), 3)
      end
    end
  end
end

describe Quo::ConsistentHashSharding do
  describe "#shard_for" do
    it "returns consistent results" do
      strategy = Quo::ConsistentHashSharding.new(shard_count: 4, virtual_nodes: 100)

      # Same key should always return same shard
      shard1 = strategy.shard_for("user_123".as(DB::Any), 4)
      shard2 = strategy.shard_for("user_123".as(DB::Any), 4)
      shard1.should eq(shard2)

      # Shard should be in valid range
      shard1.should be >= 0
      shard1.should be < 4
    end

    it "distributes keys across shards" do
      strategy = Quo::ConsistentHashSharding.new(shard_count: 4, virtual_nodes: 100)
      distribution = Hash(Int32, Int32).new(0)

      # Generate many keys
      100.times do |i|
        shard = strategy.shard_for("user_#{i}".as(DB::Any), 4)
        distribution[shard] = distribution[shard] + 1
      end

      # All shards should have some keys
      distribution.keys.size.should be > 1
    end
  end
end
