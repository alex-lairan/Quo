require "../spec_helper"

describe Quo::Query do
  describe "#select" do
    it "sets columns with table qualification" do
      query = build_query(:contracts)
        .select(contracts: [:id, :reference])

      sql, _ = query.to_sql
      sql.should contain(%("contracts"."id"))
      sql.should contain(%("contracts"."reference"))
    end

    it "allows multiple tables in select" do
      query = build_query(:contracts)
        .join(:users, on: {contracts: :user_id, eq: {users: :id}})
        .select(contracts: [:id], users: [:name, :email])

      sql, _ = query.to_sql
      sql.should contain(%("contracts"."id"))
      sql.should contain(%("users"."name"))
      sql.should contain(%("users"."email"))
    end

    it "selects all columns by default" do
      query = build_query(:contracts)

      sql, _ = query.to_sql
      sql.should contain(%("contracts".*))
    end
  end

  describe "#where with hash" do
    it "adds table-qualified where clause" do
      query = build_query(:contracts)
        .where(contracts: {status: "active"})

      sql, params = query.to_sql
      sql.should contain(%("contracts"."status" = $1))
      params.should eq(["active"])
    end

    it "chains multiple where clauses with AND" do
      query = build_query(:contracts)
        .where(contracts: {status: "active"})
        .where(contracts: {user_id: "123"})

      sql, params = query.to_sql
      sql.should contain(%("contracts"."status" = $1))
      sql.should contain(%(AND))
      sql.should contain(%("contracts"."user_id" = $2))
      params.should eq(["active", "123"])
    end

    it "handles multiple conditions in same hash" do
      query = build_query(:contracts)
        .where(contracts: {status: "active", type: "standard"})

      sql, params = query.to_sql
      sql.should contain(%("contracts"."status"))
      sql.should contain(%("contracts"."type"))
      params.size.should eq(2)
    end
  end

  describe "#where with expression block" do
    it "builds equality expression" do
      query = build_query(:contracts)
        .where { |e| e[:contracts][:status] == "active" }

      sql, params = query.to_sql
      sql.should contain(%("contracts"."status" = $1))
      params.should eq(["active"])
    end

    it "builds greater than or equal expression" do
      query = build_query(:contracts)
        .where { |e| e[:contracts][:amount] >= 1000 }

      sql, params = query.to_sql
      sql.should contain(%("contracts"."amount" >= $1))
      params.should eq([1000])
    end

    it "builds LIKE expression" do
      query = build_query(:contracts)
        .where { |e| e[:contracts][:name].like("%Acme%") }

      sql, params = query.to_sql
      sql.should contain(%("contracts"."name" LIKE $1))
      params.should eq(["%Acme%"])
    end

    it "builds IN expression" do
      query = build_query(:contracts)
        .where { |e| e[:contracts][:status].in(["active", "pending"]) }

      sql, params = query.to_sql
      sql.should contain(%("contracts"."status" IN ($1, $2)))
      params.should eq(["active", "pending"])
    end

    it "builds IS NULL expression" do
      query = build_query(:contracts)
        .where { |e| e[:contracts][:deleted_at].is_null }

      sql, _ = query.to_sql
      sql.should contain(%("contracts"."deleted_at" IS NULL))
    end

    it "builds AND expression" do
      query = build_query(:contracts)
        .where { |e| (e[:contracts][:status] == "active") & (e[:contracts][:amount] >= 1000) }

      sql, params = query.to_sql
      sql.should contain("AND")
      params.should eq(["active", 1000])
    end

    it "builds OR expression" do
      query = build_query(:contracts)
        .where { |e| (e[:contracts][:status] == "active") | (e[:contracts][:status] == "pending") }

      sql, params = query.to_sql
      sql.should contain("OR")
      params.should eq(["active", "pending"])
    end

    it "builds BETWEEN expression" do
      query = build_query(:contracts)
        .where { |e| e[:contracts][:amount].between(1000, 5000) }

      sql, params = query.to_sql
      sql.should contain(%("contracts"."amount" BETWEEN $1 AND $2))
      params.should eq([1000, 5000])
    end
  end

  describe "#join" do
    it "adds INNER JOIN by default" do
      query = build_query(:contracts)
        .join(:users, on: {contracts: :user_id, eq: {users: :id}})

      sql, _ = query.to_sql
      sql.should contain(%(INNER JOIN "users"))
      sql.should contain(%("contracts"."user_id" = "users"."id"))
    end

    it "adds LEFT JOIN" do
      query = build_query(:contracts)
        .left_join(:users, on: {contracts: :user_id, eq: {users: :id}})

      sql, _ = query.to_sql
      sql.should contain(%(LEFT JOIN "users"))
    end

    it "adds RIGHT JOIN" do
      query = build_query(:contracts)
        .right_join(:users, on: {contracts: :user_id, eq: {users: :id}})

      sql, _ = query.to_sql
      sql.should contain(%(RIGHT JOIN "users"))
    end

    it "supports multiple joins" do
      query = build_query(:contracts)
        .join(:users, on: {contracts: :user_id, eq: {users: :id}})
        .join(:invoices, on: {contracts: :id, eq: {invoices: :contract_id}})

      sql, _ = query.to_sql
      sql.should contain(%(INNER JOIN "users"))
      sql.should contain(%(INNER JOIN "invoices"))
    end
  end

  describe "#order" do
    it "adds ORDER BY with table qualification" do
      query = build_query(:contracts)
        .order(contracts: {created_at: :desc})

      sql, _ = query.to_sql
      sql.should contain(%(ORDER BY "contracts"."created_at" DESC))
    end

    it "supports multiple order columns" do
      query = build_query(:contracts)
        .order(contracts: {status: :asc, created_at: :desc})

      sql, _ = query.to_sql
      sql.should contain(%(ORDER BY))
      sql.should contain(%("contracts"."status" ASC))
      sql.should contain(%("contracts"."created_at" DESC))
    end

    it "supports ordering by multiple tables" do
      query = build_query(:contracts)
        .join(:users, on: {contracts: :user_id, eq: {users: :id}})
        .order(users: {name: :asc})
        .order(contracts: {created_at: :desc})

      sql, _ = query.to_sql
      sql.should contain(%("users"."name" ASC))
      sql.should contain(%("contracts"."created_at" DESC))
    end
  end

  describe "#limit and #offset" do
    it "adds LIMIT clause" do
      query = build_query(:contracts).limit(20)

      sql, params = query.to_sql
      sql.should contain(%(LIMIT $1))
      params.should eq([20])
    end

    it "adds OFFSET clause" do
      query = build_query(:contracts).offset(40)

      sql, params = query.to_sql
      sql.should contain(%(OFFSET $1))
      params.should eq([40])
    end

    it "adds both LIMIT and OFFSET" do
      query = build_query(:contracts).limit(20).offset(40)

      sql, params = query.to_sql
      sql.should contain(%(LIMIT))
      sql.should contain(%(OFFSET))
      params.should eq([20, 40])
    end
  end

  describe "#distinct" do
    it "adds DISTINCT keyword" do
      query = build_query(:contracts).distinct

      sql, _ = query.to_sql
      sql.should start_with(%(SELECT DISTINCT))
    end
  end

  describe "immutability" do
    it "returns new query on each method call" do
      original = build_query(:contracts)
      with_where = original.where(contracts: {status: "active"})

      original.object_id.should_not eq(with_where.object_id)
    end

    it "does not mutate original query" do
      original = build_query(:contracts)
      original.where(contracts: {status: "active"})

      sql, params = original.to_sql
      sql.should_not contain(%(WHERE))
      params.should be_empty
    end

    it "allows branching from same base query" do
      base = build_query(:contracts).where(contracts: {status: "active"})

      page1 = base.limit(20).offset(0)
      page2 = base.limit(20).offset(20)

      sql1, params1 = page1.to_sql
      sql2, params2 = page2.to_sql

      params1.should eq(["active", 20, 0])
      params2.should eq(["active", 20, 20])
    end
  end

  describe "#count_sql" do
    it "generates COUNT query" do
      query = build_query(:contracts)
        .where(contracts: {status: "active"})

      sql, _ = query.count_sql
      sql.should contain(%(SELECT COUNT(*)))
      sql.should contain(%(FROM "contracts"))
      sql.should contain(%(WHERE))
    end
  end
end
