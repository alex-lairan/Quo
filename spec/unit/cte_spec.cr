require "../spec_helper"

describe "CTEs (Common Table Expressions)" do
  adapter = Quo::Adapters::Test.new

  describe "#with_cte" do
    it "generates WITH clause for single CTE" do
      active_users = Quo::Query.new(:users, adapter)
        .select(users: [:id, :name])
        .where(users: {active: true})

      query = Quo::Query.new(:active_users, adapter)
        .with_cte(:active_users, active_users)
        .select(active_users: [:id, :name])

      sql, params = query.to_sql
      sql.should contain("WITH \"active_users\" AS (SELECT \"users\".\"id\", \"users\".\"name\" FROM \"users\" WHERE \"users\".\"active\" = $1)")
      sql.should contain("SELECT \"active_users\".\"id\", \"active_users\".\"name\" FROM \"active_users\"")
      params.should eq([true])
    end

    it "generates WITH clause for multiple CTEs" do
      vip_users = Quo::Query.new(:users, adapter)
        .select(users: [:id])
        .where(users: {tier: "vip"})

      recent_orders = Quo::Query.new(:orders, adapter)
        .select(orders: [:id, :user_id])
        .where(orders: {status: "completed"})

      query = Quo::Query.new(:vip_users, adapter)
        .with_cte(:vip_users, vip_users)
        .with_cte(:recent_orders, recent_orders)
        .select(vip_users: [:id])

      sql, params = query.to_sql
      sql.should contain("WITH ")
      sql.should contain("\"vip_users\" AS")
      sql.should contain("\"recent_orders\" AS")
      params.should eq(["vip", "completed"])
    end
  end

  describe "#with_recursive_cte" do
    it "generates WITH RECURSIVE clause" do
      # Recursive CTE for tree structure
      tree_query = Quo::Query.new(:categories, adapter)
        .select(categories: [:id, :name, :parent_id])
        .where(categories: {parent_id: 1})

      query = Quo::Query.new(:tree, adapter)
        .with_recursive_cte(:tree, tree_query)
        .select(tree: [:id, :name])

      sql, params = query.to_sql
      sql.should contain("WITH RECURSIVE \"tree\" AS")
      params.should eq([1])
    end

    it "marks recursive when at least one CTE is recursive" do
      non_recursive = Quo::Query.new(:users, adapter)
        .select(users: [:id])

      recursive = Quo::Query.new(:tree, adapter)
        .select(tree: [:id])

      query = Quo::Query.new(:result, adapter)
        .with_cte(:users_cte, non_recursive)
        .with_recursive_cte(:tree, recursive)

      sql, _ = query.to_sql
      sql.should contain("WITH RECURSIVE")
    end
  end

  describe "CTE with complex queries" do
    it "supports CTE with aggregations" do
      user_stats = Quo::Query.new(:orders, adapter)
        .select(orders: [:user_id])
        .select_count(as: :order_count)
        .select_sum(:orders, :amount, as: :total_spent)
        .group(orders: [:user_id])

      query = Quo::Query.new(:user_stats, adapter)
        .with_cte(:user_stats, user_stats)
        .select(user_stats: [:user_id, :order_count, :total_spent])

      sql, _ = query.to_sql
      sql.should contain("WITH \"user_stats\" AS")
      sql.should contain("COUNT(*) AS \"order_count\"")
      sql.should contain("SUM(\"orders\".\"amount\") AS \"total_spent\"")
      sql.should contain("GROUP BY")
    end

    it "supports CTE with joins" do
      orders_with_users = Quo::Query.new(:orders, adapter)
        .select(orders: [:id], users: [:name])
        .join(:users, on: {orders: :user_id, eq: {users: :id}})

      query = Quo::Query.new(:enriched_orders, adapter)
        .with_cte(:enriched_orders, orders_with_users)
        .select(enriched_orders: [:id, :name])

      sql, _ = query.to_sql
      sql.should contain("WITH \"enriched_orders\" AS")
      sql.should contain("INNER JOIN")
    end

    it "supports CTE with subquery in WHERE" do
      high_value = Quo::Query.new(:orders, adapter)
        .select(orders: [:user_id])
        .where(orders: {amount: 1000})

      cte_query = Quo::Query.new(:users, adapter)
        .select(users: [:id, :name])
        .where { |e| e[:users][:id].in(high_value) }

      query = Quo::Query.new(:vip_users, adapter)
        .with_cte(:vip_users, cte_query)
        .select(vip_users: [:id])

      sql, _ = query.to_sql
      sql.should contain("WITH \"vip_users\" AS")
      sql.should contain("IN (SELECT")
    end
  end

  describe "CTE used in main query" do
    it "allows referencing CTE in FROM clause" do
      cte_def = Quo::Query.new(:products, adapter)
        .select(products: [:id, :name, :price])
        .where(products: {active: true})

      query = Quo::Query.new(:active_products, adapter)
        .with_cte(:active_products, cte_def)
        .select(active_products: [:id, :name])
        .where(active_products: {price: 100})

      sql, params = query.to_sql
      sql.should contain("WITH \"active_products\" AS")
      sql.should contain("FROM \"active_products\"")
      sql.should contain("WHERE \"active_products\".\"price\" = $2")
      params.should eq([true, 100])
    end
  end

  describe "immutability" do
    it "returns new query instances" do
      cte_query = Quo::Query.new(:users, adapter).select(users: [:id])
      base = Quo::Query.new(:active, adapter)

      with_cte = base.with_cte(:active, cte_query)

      base.cte_clauses.should be_empty
      with_cte.cte_clauses.size.should eq(1)
    end
  end
end
