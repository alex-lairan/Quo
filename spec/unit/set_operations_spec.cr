require "../spec_helper"

describe "Set Operations" do
  adapter = Quo::Adapters::Test.new

  describe "#union" do
    it "generates UNION between two queries" do
      active = Quo::Query.new(:users, adapter)
        .select(users: [:id, :name])
        .where(users: {active: true})

      admins = Quo::Query.new(:users, adapter)
        .select(users: [:id, :name])
        .where(users: {role: "admin"})

      combined = active.union(admins)

      sql, params = combined.to_sql
      sql.should contain("SELECT \"users\".\"id\", \"users\".\"name\" FROM \"users\" WHERE \"users\".\"active\" = $1")
      sql.should contain("UNION")
      sql.should contain("SELECT \"users\".\"id\", \"users\".\"name\" FROM \"users\" WHERE \"users\".\"role\" = $2")
      params.should eq([true, "admin"])
    end
  end

  describe "#union_all" do
    it "generates UNION ALL between two queries" do
      query1 = Quo::Query.new(:orders, adapter)
        .select(orders: [:id])
        .where(orders: {status: "pending"})

      query2 = Quo::Query.new(:orders, adapter)
        .select(orders: [:id])
        .where(orders: {status: "processing"})

      combined = query1.union_all(query2)

      sql, _ = combined.to_sql
      sql.should contain("UNION ALL")
    end
  end

  describe "#intersect" do
    it "generates INTERSECT between two queries" do
      active = Quo::Query.new(:users, adapter)
        .select(users: [:id])
        .where(users: {active: true})

      premium = Quo::Query.new(:users, adapter)
        .select(users: [:id])
        .where(users: {tier: "premium"})

      result = active.intersect(premium)

      sql, params = result.to_sql
      sql.should contain("INTERSECT")
      sql.should contain("WHERE \"users\".\"active\" = $1")
      sql.should contain("WHERE \"users\".\"tier\" = $2")
      params.should eq([true, "premium"])
    end
  end

  describe "#intersect_all" do
    it "generates INTERSECT ALL between two queries" do
      query1 = Quo::Query.new(:items, adapter)
        .select(items: [:sku])

      query2 = Quo::Query.new(:items, adapter)
        .select(items: [:sku])

      result = query1.intersect_all(query2)

      sql, _ = result.to_sql
      sql.should contain("INTERSECT ALL")
    end
  end

  describe "#except" do
    it "generates EXCEPT between two queries" do
      all_users = Quo::Query.new(:users, adapter)
        .select(users: [:id])

      deleted = Quo::Query.new(:users, adapter)
        .select(users: [:id])
        .where(users: {deleted: true})

      result = all_users.except(deleted)

      sql, params = result.to_sql
      sql.should contain("EXCEPT")
      sql.should contain("WHERE \"users\".\"deleted\" = $1")
      params.should eq([true])
    end
  end

  describe "#except_all" do
    it "generates EXCEPT ALL between two queries" do
      query1 = Quo::Query.new(:log_entries, adapter)
        .select(log_entries: [:id])

      query2 = Quo::Query.new(:log_entries, adapter)
        .select(log_entries: [:id])
        .where(log_entries: {archived: true})

      result = query1.except_all(query2)

      sql, _ = result.to_sql
      sql.should contain("EXCEPT ALL")
    end
  end

  describe "chaining multiple set operations" do
    it "supports chaining multiple UNION operations" do
      pending_orders = Quo::Query.new(:orders, adapter)
        .select(orders: [:id])
        .where(orders: {status: "pending"})

      processing_orders = Quo::Query.new(:orders, adapter)
        .select(orders: [:id])
        .where(orders: {status: "processing"})

      shipped_orders = Quo::Query.new(:orders, adapter)
        .select(orders: [:id])
        .where(orders: {status: "shipped"})

      combined = pending_orders
        .union(processing_orders)
        .union(shipped_orders)

      sql, params = combined.to_sql
      sql.scan("UNION").size.should eq(2)
      params.should eq(["pending", "processing", "shipped"])
    end
  end

  describe "set operations with complex queries" do
    it "supports set operation with grouped queries" do
      summary1 = Quo::Query.new(:orders, adapter)
        .select(orders: [:user_id])
        .select_count(as: :order_count)
        .group(orders: [:user_id])
        .having { |b| b.count >= 5 }

      summary2 = Quo::Query.new(:orders, adapter)
        .select(orders: [:user_id])
        .select_count(as: :order_count)
        .where(orders: {vip: true})
        .group(orders: [:user_id])

      result = summary1.union(summary2)

      sql, params = result.to_sql
      sql.should contain("GROUP BY")
      sql.should contain("HAVING")
      sql.should contain("UNION")
      params[0].should eq(5)
      params[1].should eq(true)
    end
  end

  describe "immutability" do
    it "returns new query instances" do
      base = Quo::Query.new(:users, adapter).select(users: [:id])
      other = Quo::Query.new(:users, adapter).select(users: [:id]).where(users: {admin: true})

      with_union = base.union(other)

      base.set_operations.should be_empty
      with_union.set_operations.size.should eq(1)
    end
  end
end
