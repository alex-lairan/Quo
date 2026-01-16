require "../spec_helper"

describe Quo::Cache::MemoryCacheStore do
  describe "#get/#set" do
    it "stores and retrieves values" do
      store = Quo::Cache::MemoryCacheStore.new
      store.set("key1", "value1", 1.hour)

      store.get("key1").should eq("value1")
    end

    it "returns nil for missing keys" do
      store = Quo::Cache::MemoryCacheStore.new

      store.get("nonexistent").should be_nil
    end

    it "expires values after TTL" do
      store = Quo::Cache::MemoryCacheStore.new
      store.set("key1", "value1", 1.millisecond)

      sleep 10.milliseconds

      store.get("key1").should be_nil
    end

    it "overwrites existing values" do
      store = Quo::Cache::MemoryCacheStore.new
      store.set("key1", "value1", 1.hour)
      store.set("key1", "value2", 1.hour)

      store.get("key1").should eq("value2")
    end
  end

  describe "#delete" do
    it "removes a key" do
      store = Quo::Cache::MemoryCacheStore.new
      store.set("key1", "value1", 1.hour)

      store.delete("key1").should be_true
      store.get("key1").should be_nil
    end

    it "returns false for missing key" do
      store = Quo::Cache::MemoryCacheStore.new

      store.delete("nonexistent").should be_false
    end
  end

  describe "#delete_all" do
    it "removes multiple keys" do
      store = Quo::Cache::MemoryCacheStore.new
      store.set("key1", "value1", 1.hour)
      store.set("key2", "value2", 1.hour)
      store.set("key3", "value3", 1.hour)

      count = store.delete_all(["key1", "key2"])

      count.should eq(2)
      store.get("key1").should be_nil
      store.get("key2").should be_nil
      store.get("key3").should eq("value3")
    end
  end

  describe "#keys" do
    it "finds keys matching pattern" do
      store = Quo::Cache::MemoryCacheStore.new
      store.set("users:1", "a", 1.hour)
      store.set("users:2", "b", 1.hour)
      store.set("orders:1", "c", 1.hour)

      keys = store.keys("users:*").sort

      keys.should eq(["users:1", "users:2"])
    end

    it "returns empty array when no matches" do
      store = Quo::Cache::MemoryCacheStore.new
      store.set("key1", "value1", 1.hour)

      store.keys("other:*").should be_empty
    end
  end

  describe "#clear" do
    it "removes all entries" do
      store = Quo::Cache::MemoryCacheStore.new
      store.set("key1", "value1", 1.hour)
      store.set("key2", "value2", 1.hour)

      store.clear

      store.size.should eq(0)
    end
  end

  describe "#size" do
    it "returns number of entries" do
      store = Quo::Cache::MemoryCacheStore.new
      store.set("key1", "value1", 1.hour)
      store.set("key2", "value2", 1.hour)

      store.size.should eq(2)
    end

    it "excludes expired entries" do
      store = Quo::Cache::MemoryCacheStore.new
      store.set("key1", "value1", 1.millisecond)
      store.set("key2", "value2", 1.hour)

      sleep 10.milliseconds

      store.size.should eq(1)
    end
  end

  describe "#set_add/#set_members" do
    it "stores set members" do
      store = Quo::Cache::MemoryCacheStore.new
      store.set_add("myset", "member1")
      store.set_add("myset", "member2")

      members = store.set_members("myset").sort
      members.should eq(["member1", "member2"])
    end

    it "returns empty array for missing set" do
      store = Quo::Cache::MemoryCacheStore.new

      store.set_members("nonexistent").should be_empty
    end

    it "doesn't add duplicates" do
      store = Quo::Cache::MemoryCacheStore.new
      store.set_add("myset", "member1")
      store.set_add("myset", "member1")

      store.set_members("myset").size.should eq(1)
    end
  end

  describe "max_size eviction" do
    it "evicts when at capacity" do
      store = Quo::Cache::MemoryCacheStore.new(max_size: 2)
      store.set("key1", "value1", 1.hour)
      store.set("key2", "value2", 1.hour)
      store.set("key3", "value3", 1.hour)

      store.size.should eq(2)
    end
  end
end

describe Quo::Cache::QueryCache do
  describe "#cache_key" do
    it "generates consistent keys for same sql and params" do
      cache = Quo::Cache::QueryCache.new

      key1 = cache.cache_key("SELECT * FROM users WHERE id = ?", [1.as(DB::Any)])
      key2 = cache.cache_key("SELECT * FROM users WHERE id = ?", [1.as(DB::Any)])

      key1.should eq(key2)
    end

    it "generates different keys for different params" do
      cache = Quo::Cache::QueryCache.new

      key1 = cache.cache_key("SELECT * FROM users WHERE id = ?", [1.as(DB::Any)])
      key2 = cache.cache_key("SELECT * FROM users WHERE id = ?", [2.as(DB::Any)])

      key1.should_not eq(key2)
    end
  end

  describe "#stats" do
    it "tracks hits and misses" do
      cache = Quo::Cache::QueryCache.new

      # First call - miss
      cache.fetch("key1") { [{"id" => 1.as(Quo::Value)}] of Quo::Row }

      # Second call - hit
      cache.fetch("key1") { [{"id" => 2.as(Quo::Value)}] of Quo::Row }

      stats = cache.stats
      stats.hits.should eq(1)
      stats.misses.should eq(1)
      stats.hit_rate.should eq(0.5)
    end
  end

  describe "#bypass" do
    it "skips cache in bypass block" do
      cache = Quo::Cache::QueryCache.new
      call_count = 0

      cache.bypass do
        cache.fetch("key1") { call_count += 1; [] of Quo::Row }
        cache.fetch("key1") { call_count += 1; [] of Quo::Row }
      end

      call_count.should eq(2)
    end
  end

  describe "#invalidate_tag" do
    it "removes entries with tag" do
      cache = Quo::Cache::QueryCache.new

      cache.set("key1", [] of Quo::Row, tags: ["users"])
      cache.set("key2", [] of Quo::Row, tags: ["users"])
      cache.set("key3", [] of Quo::Row, tags: ["orders"])

      count = cache.invalidate_tag("users")

      count.should eq(2)
      cache.get("key1").should be_nil
      cache.get("key2").should be_nil
      cache.get("key3").should_not be_nil
    end
  end

  describe "#enabled" do
    it "can be disabled" do
      cache = Quo::Cache::QueryCache.new
      cache.enabled = false

      call_count = 0
      cache.fetch("key1") { call_count += 1; [] of Quo::Row }
      cache.fetch("key1") { call_count += 1; [] of Quo::Row }

      call_count.should eq(2)
    end
  end
end

describe Quo::Cache::CacheStats do
  describe "#hit_rate" do
    it "returns 0 when no requests" do
      stats = Quo::Cache::CacheStats.new

      stats.hit_rate.should eq(0.0)
    end

    it "calculates correctly" do
      stats = Quo::Cache::CacheStats.new(
        hits: 80_i64,
        misses: 20_i64
      )

      stats.hit_rate.should eq(0.8)
    end
  end

  describe "#total_requests" do
    it "sums hits and misses" do
      stats = Quo::Cache::CacheStats.new(
        hits: 100_i64,
        misses: 50_i64
      )

      stats.total_requests.should eq(150_i64)
    end
  end
end
