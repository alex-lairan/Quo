require "../spec_helper"

describe Quo::Query do
  describe "aggregations" do
    adapter = Quo::Adapters::Test.new

    describe "#group" do
      it "generates GROUP BY clause" do
        query = Quo::Query.new(:orders, adapter)
          .select(orders: [:status])
          .select_count(as: :count)
          .group(orders: [:status])

        sql, _ = query.to_sql
        sql.should contain("GROUP BY \"orders\".\"status\"")
      end

      it "supports multiple GROUP BY columns" do
        query = Quo::Query.new(:orders, adapter)
          .select(orders: [:status, :user_id])
          .select_count(as: :count)
          .group(orders: [:status, :user_id])

        sql, _ = query.to_sql
        sql.should contain("GROUP BY \"orders\".\"status\", \"orders\".\"user_id\"")
      end

      it "supports GROUP BY from multiple tables" do
        query = Quo::Query.new(:orders, adapter)
          .select(orders: [:status], users: [:country])
          .select_count(as: :count)
          .group(orders: [:status], users: [:country])

        sql, _ = query.to_sql
        sql.should contain("GROUP BY \"orders\".\"status\", \"users\".\"country\"")
      end
    end

    describe "#having" do
      it "generates HAVING with COUNT > value" do
        query = Quo::Query.new(:orders, adapter)
          .select(orders: [:user_id])
          .select_count(as: :order_count)
          .group(orders: [:user_id])
          .having { |b| b.count > 5 }

        sql, params = query.to_sql
        sql.should contain("HAVING COUNT(*) > $1")
        params.should eq([5])
      end

      it "generates HAVING with COUNT >= value" do
        query = Quo::Query.new(:orders, adapter)
          .group(orders: [:user_id])
          .having { |b| b.count >= 10 }

        sql, params = query.to_sql
        sql.should contain("HAVING COUNT(*) >= $1")
        params.should eq([10])
      end

      it "generates HAVING with SUM" do
        query = Quo::Query.new(:orders, adapter)
          .group(orders: [:user_id])
          .having { |b| b.sum(:orders, :amount) >= 1000 }

        sql, params = query.to_sql
        sql.should contain("HAVING SUM(\"orders\".\"amount\") >= $1")
        params.should eq([1000])
      end

      it "generates HAVING with AVG" do
        query = Quo::Query.new(:products, adapter)
          .group(products: [:category])
          .having { |b| b.avg(:products, :price) < 50 }

        sql, params = query.to_sql
        sql.should contain("HAVING AVG(\"products\".\"price\") < $1")
        params.should eq([50])
      end

      it "generates HAVING with combined conditions (AND)" do
        query = Quo::Query.new(:orders, adapter)
          .group(orders: [:user_id])
          .having { |b| (b.count > 5) & (b.sum(:orders, :amount) >= 1000) }

        sql, params = query.to_sql
        sql.should contain("HAVING (COUNT(*) > $1 AND SUM(\"orders\".\"amount\") >= $2)")
        params.should eq([5, 1000])
      end

      it "generates HAVING with combined conditions (OR)" do
        query = Quo::Query.new(:orders, adapter)
          .group(orders: [:user_id])
          .having { |b| (b.count > 10) | (b.sum(:orders, :amount) >= 5000) }

        sql, params = query.to_sql
        sql.should contain("HAVING (COUNT(*) > $1 OR SUM(\"orders\".\"amount\") >= $2)")
        params.should eq([10, 5000])
      end

      it "generates HAVING with BETWEEN" do
        query = Quo::Query.new(:orders, adapter)
          .group(orders: [:user_id])
          .having { |b| b.count.between(5, 10) }

        sql, params = query.to_sql
        sql.should contain("HAVING COUNT(*) BETWEEN $1 AND $2")
        params.should eq([5, 10])
      end
    end

    describe "#select_count" do
      it "generates COUNT(*)" do
        query = Quo::Query.new(:orders, adapter)
          .select_count

        sql, _ = query.to_sql
        sql.should contain("SELECT COUNT(*)")
      end

      it "generates COUNT(*) with alias" do
        query = Quo::Query.new(:orders, adapter)
          .select_count(as: :total)

        sql, _ = query.to_sql
        sql.should contain("SELECT COUNT(*) AS \"total\"")
      end

      it "generates COUNT(column)" do
        query = Quo::Query.new(:orders, adapter)
          .select_count(:orders, :user_id, as: :user_count)

        sql, _ = query.to_sql
        sql.should contain("SELECT COUNT(\"orders\".\"user_id\") AS \"user_count\"")
      end

      it "generates COUNT(DISTINCT column)" do
        query = Quo::Query.new(:orders, adapter)
          .select_count(:orders, :user_id, as: :unique_users, distinct: true)

        sql, _ = query.to_sql
        sql.should contain("SELECT COUNT(DISTINCT \"orders\".\"user_id\") AS \"unique_users\"")
      end
    end

    describe "#select_sum" do
      it "generates SUM(column)" do
        query = Quo::Query.new(:orders, adapter)
          .select_sum(:orders, :amount, as: :total_amount)

        sql, _ = query.to_sql
        sql.should contain("SELECT SUM(\"orders\".\"amount\") AS \"total_amount\"")
      end
    end

    describe "#select_avg" do
      it "generates AVG(column)" do
        query = Quo::Query.new(:products, adapter)
          .select_avg(:products, :price, as: :average_price)

        sql, _ = query.to_sql
        sql.should contain("SELECT AVG(\"products\".\"price\") AS \"average_price\"")
      end
    end

    describe "#select_min" do
      it "generates MIN(column)" do
        query = Quo::Query.new(:orders, adapter)
          .select_min(:orders, :created_at, as: :first_order)

        sql, _ = query.to_sql
        sql.should contain("SELECT MIN(\"orders\".\"created_at\") AS \"first_order\"")
      end
    end

    describe "#select_max" do
      it "generates MAX(column)" do
        query = Quo::Query.new(:orders, adapter)
          .select_max(:orders, :amount, as: :largest_order)

        sql, _ = query.to_sql
        sql.should contain("SELECT MAX(\"orders\".\"amount\") AS \"largest_order\"")
      end
    end

    describe "combined aggregations" do
      it "generates query with columns and multiple aggregates" do
        query = Quo::Query.new(:orders, adapter)
          .select(orders: [:status])
          .select_count(as: :order_count)
          .select_sum(:orders, :amount, as: :total_amount)
          .select_avg(:orders, :amount, as: :avg_amount)
          .group(orders: [:status])

        sql, _ = query.to_sql
        sql.should contain("\"orders\".\"status\"")
        sql.should contain("COUNT(*) AS \"order_count\"")
        sql.should contain("SUM(\"orders\".\"amount\") AS \"total_amount\"")
        sql.should contain("AVG(\"orders\".\"amount\") AS \"avg_amount\"")
        sql.should contain("GROUP BY \"orders\".\"status\"")
      end

      it "generates complete analytics query" do
        query = Quo::Query.new(:orders, adapter)
          .select(orders: [:user_id])
          .select_count(as: :order_count)
          .select_sum(:orders, :amount, as: :total_spent)
          .join(:users, on: {orders: :user_id, eq: {users: :id}})
          .where(users: {active: true})
          .group(orders: [:user_id])
          .having { |b| b.count >= 3 }
          .order(orders: {user_id: :asc})
          .limit(10)

        sql, params = query.to_sql
        sql.should contain("SELECT \"orders\".\"user_id\", COUNT(*) AS \"order_count\", SUM(\"orders\".\"amount\") AS \"total_spent\"")
        sql.should contain("FROM \"orders\"")
        sql.should contain("INNER JOIN \"users\"")
        sql.should contain("WHERE \"users\".\"active\" = $1")
        sql.should contain("GROUP BY \"orders\".\"user_id\"")
        sql.should contain("HAVING COUNT(*) >= $2")
        sql.should contain("ORDER BY \"orders\".\"user_id\" ASC")
        sql.should contain("LIMIT $3")
        params[0].should eq(true)
        params[1].should eq(3)
        params[2].should eq(10)
      end
    end

    describe "immutability" do
      it "returns new query instances" do
        base = Quo::Query.new(:orders, adapter)
        with_group = base.group(orders: [:status])
        with_having = with_group.having { |b| b.count > 5 }

        base.group_columns.should be_empty
        base.having_clauses.should be_empty
        with_group.group_columns.size.should eq(1)
        with_group.having_clauses.should be_empty
        with_having.group_columns.size.should eq(1)
        with_having.having_clauses.size.should eq(1)
      end
    end
  end
end
