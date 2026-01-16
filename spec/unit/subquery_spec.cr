require "../spec_helper"

describe "Subqueries" do
  adapter = Quo::Adapters::Test.new

  describe "IN subquery" do
    it "generates WHERE column IN (SELECT ...)" do
      subquery = Quo::Query.new(:orders, adapter)
        .select(orders: [:user_id])
        .where(orders: {status: "premium"})

      query = Quo::Query.new(:users, adapter)
        .where { |e| e[:users][:id].in(subquery) }

      sql, params = query.to_sql
      sql.should contain("WHERE \"users\".\"id\" IN (SELECT \"orders\".\"user_id\" FROM \"orders\" WHERE \"orders\".\"status\" = $1)")
      params.should eq(["premium"])
    end

    it "generates WHERE column IN with simple subquery" do
      subquery = Quo::Query.new(:active_users, adapter)
        .select(active_users: [:id])

      query = Quo::Query.new(:posts, adapter)
        .where { |e| e[:posts][:author_id].in(subquery) }

      sql, _ = query.to_sql
      sql.should contain("WHERE \"posts\".\"author_id\" IN (SELECT \"active_users\".\"id\" FROM \"active_users\")")
    end
  end

  describe "NOT IN subquery" do
    it "generates WHERE column NOT IN (SELECT ...)" do
      subquery = Quo::Query.new(:blocked_users, adapter)
        .select(blocked_users: [:user_id])

      query = Quo::Query.new(:users, adapter)
        .where { |e| e[:users][:id].not_in(subquery) }

      sql, _ = query.to_sql
      sql.should contain("WHERE \"users\".\"id\" NOT IN (SELECT \"blocked_users\".\"user_id\" FROM \"blocked_users\")")
    end
  end

  describe "EXISTS subquery" do
    it "generates WHERE EXISTS (SELECT ...)" do
      subquery = Quo::Query.new(:orders, adapter)
        .select(orders: [:id])
        .where(orders: {user_id: 1})

      query = Quo::Query.new(:users, adapter)
        .where { |e| e.exists(subquery) }

      sql, params = query.to_sql
      sql.should contain("WHERE EXISTS (SELECT \"orders\".\"id\" FROM \"orders\" WHERE \"orders\".\"user_id\" = $1)")
      params.should eq([1])
    end

    it "generates correlated EXISTS subquery" do
      # Note: For truly correlated subqueries, users would need to use raw SQL
      # This tests the basic EXISTS functionality
      subquery = Quo::Query.new(:comments, adapter)
        .select(comments: [:id])
        .where(comments: {post_id: 42})

      query = Quo::Query.new(:posts, adapter)
        .where { |e| e.exists(subquery) }

      sql, _ = query.to_sql
      sql.should contain("WHERE EXISTS")
      sql.should contain("SELECT \"comments\".\"id\" FROM \"comments\"")
    end
  end

  describe "NOT EXISTS subquery" do
    it "generates WHERE NOT EXISTS (SELECT ...)" do
      subquery = Quo::Query.new(:orders, adapter)
        .select(orders: [:id])
        .where(orders: {status: "pending"})

      query = Quo::Query.new(:users, adapter)
        .where { |e| e.not_exists(subquery) }

      sql, _ = query.to_sql
      sql.should contain("WHERE NOT EXISTS (SELECT \"orders\".\"id\" FROM \"orders\"")
    end
  end

  describe "scalar subquery comparisons" do
    it "generates column = (SELECT ...)" do
      subquery = Quo::Query.new(:stats, adapter)
        .select_max(:stats, :value)
        .where(stats: {category: "sales"})

      query = Quo::Query.new(:products, adapter)
        .where { |e| e[:products][:score].eq_subquery(subquery) }

      sql, _ = query.to_sql
      sql.should contain("WHERE \"products\".\"score\" = (SELECT MAX(\"stats\".\"value\")")
    end

    it "generates column > (SELECT ...)" do
      subquery = Quo::Query.new(:orders, adapter)
        .select_avg(:orders, :amount)

      query = Quo::Query.new(:orders, adapter)
        .where { |e| e[:orders][:amount].gt_subquery(subquery) }

      sql, _ = query.to_sql
      sql.should contain("WHERE \"orders\".\"amount\" > (SELECT AVG(\"orders\".\"amount\")")
    end

    it "generates column >= (SELECT ...)" do
      subquery = Quo::Query.new(:thresholds, adapter)
        .select_min(:thresholds, :value)

      query = Quo::Query.new(:scores, adapter)
        .where { |e| e[:scores][:value].gte_subquery(subquery) }

      sql, _ = query.to_sql
      sql.should contain("WHERE \"scores\".\"value\" >= (SELECT MIN(\"thresholds\".\"value\")")
    end

    it "generates column < (SELECT ...)" do
      subquery = Quo::Query.new(:limits, adapter)
        .select_max(:limits, :max_value)

      query = Quo::Query.new(:items, adapter)
        .where { |e| e[:items][:quantity].lt_subquery(subquery) }

      sql, _ = query.to_sql
      sql.should contain("WHERE \"items\".\"quantity\" < (SELECT MAX(\"limits\".\"max_value\")")
    end

    it "generates column <= (SELECT ...)" do
      subquery = Quo::Query.new(:budgets, adapter)
        .select(budgets: [:max_amount])
        .where(budgets: {user_id: 1})
        .limit(1)

      query = Quo::Query.new(:expenses, adapter)
        .where { |e| e[:expenses][:amount].lte_subquery(subquery) }

      sql, _ = query.to_sql
      sql.should contain("WHERE \"expenses\".\"amount\" <= (SELECT")
    end
  end

  describe "combined subquery conditions" do
    it "combines IN subquery with other conditions" do
      subquery = Quo::Query.new(:vip_users, adapter)
        .select(vip_users: [:user_id])

      query = Quo::Query.new(:orders, adapter)
        .where(orders: {status: "completed"})
        .where { |e| e[:orders][:user_id].in(subquery) }

      sql, params = query.to_sql
      sql.should contain("WHERE \"orders\".\"status\" = $1 AND \"orders\".\"user_id\" IN")
      params[0].should eq("completed")
    end

    it "combines EXISTS with other conditions using AND" do
      subquery = Quo::Query.new(:premium_features, adapter)
        .select(premium_features: [:user_id])

      query = Quo::Query.new(:users, adapter)
        .where(users: {active: true})
        .where { |e| e.exists(subquery) }

      sql, _ = query.to_sql
      sql.should contain("WHERE \"users\".\"active\" = $1 AND EXISTS")
    end
  end

  describe "nested subqueries" do
    it "supports subquery within subquery" do
      inner_subquery = Quo::Query.new(:categories, adapter)
        .select(categories: [:id])
        .where(categories: {active: true})

      outer_subquery = Quo::Query.new(:products, adapter)
        .select(products: [:vendor_id])
        .where { |e| e[:products][:category_id].in(inner_subquery) }

      query = Quo::Query.new(:vendors, adapter)
        .where { |e| e[:vendors][:id].in(outer_subquery) }

      sql, params = query.to_sql
      sql.should contain("WHERE \"vendors\".\"id\" IN")
      sql.should contain("WHERE \"products\".\"category_id\" IN")
      sql.should contain("WHERE \"categories\".\"active\" = $1")
      params.should eq([true])
    end
  end
end
