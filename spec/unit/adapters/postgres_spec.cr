require "../../spec_helper"

describe Quo::Adapters::Postgres do
  describe "#quote_identifier" do
    it "quotes identifier with double quotes" do
      adapter = Quo::Adapters::Test.new
      adapter.quote_identifier(:contracts).should eq(%("contracts"))
      adapter.quote_identifier(:user_id).should eq(%("user_id"))
    end
  end

  describe "#placeholder" do
    it "generates Postgres-style placeholders" do
      adapter = Quo::Adapters::Test.new
      adapter.placeholder(1).should eq("$1")
      adapter.placeholder(5).should eq("$5")
      adapter.placeholder(10).should eq("$10")
    end
  end

  describe "#compile" do
    describe "SELECT clause" do
      it "generates SELECT * by default" do
        query = build_query(:contracts)
        sql, _ = query.to_sql

        sql.should eq(%(SELECT "contracts".* FROM "contracts"))
      end

      it "generates specific columns" do
        query = build_query(:contracts)
          .select(contracts: [:id, :reference])
        sql, _ = query.to_sql

        sql.should eq(%(SELECT "contracts"."id", "contracts"."reference" FROM "contracts"))
      end

      it "generates DISTINCT" do
        query = build_query(:contracts).distinct
        sql, _ = query.to_sql

        sql.should start_with(%(SELECT DISTINCT "contracts".*))
      end
    end

    describe "WHERE clause" do
      it "generates equality condition" do
        query = build_query(:contracts)
          .where(contracts: {status: "active"})
        sql, params = query.to_sql

        sql.should eq(%(SELECT "contracts".* FROM "contracts" WHERE "contracts"."status" = $1))
        params.should eq(["active"])
      end

      it "generates multiple conditions with AND" do
        query = build_query(:contracts)
          .where(contracts: {status: "active"})
          .where(contracts: {type: "standard"})
        sql, params = query.to_sql

        sql.should contain(%("contracts"."status" = $1 AND "contracts"."type" = $2))
        params.should eq(["active", "standard"])
      end

      it "generates >= condition" do
        query = build_query(:contracts)
          .where { |e| e[:contracts][:amount] >= 1000 }
        sql, params = query.to_sql

        sql.should contain(%("contracts"."amount" >= $1))
        params.should eq([1000])
      end

      it "generates LIKE condition" do
        query = build_query(:contracts)
          .where { |e| e[:contracts][:name].like("%Acme%") }
        sql, params = query.to_sql

        sql.should contain(%("contracts"."name" LIKE $1))
        params.should eq(["%Acme%"])
      end

      it "generates ILIKE condition" do
        query = build_query(:contracts)
          .where { |e| e[:contracts][:name].ilike("%acme%") }
        sql, params = query.to_sql

        sql.should contain(%("contracts"."name" ILIKE $1))
        params.should eq(["%acme%"])
      end

      it "generates IN condition" do
        query = build_query(:contracts)
          .where { |e| e[:contracts][:status].in(["active", "pending", "review"]) }
        sql, params = query.to_sql

        sql.should contain(%("contracts"."status" IN ($1, $2, $3)))
        params.should eq(["active", "pending", "review"])
      end

      it "generates IS NULL condition" do
        query = build_query(:contracts)
          .where { |e| e[:contracts][:deleted_at].is_null }
        sql, _ = query.to_sql

        sql.should contain(%("contracts"."deleted_at" IS NULL))
      end

      it "generates IS NOT NULL condition" do
        query = build_query(:contracts)
          .where { |e| e[:contracts][:deleted_at].is_not_null }
        sql, _ = query.to_sql

        sql.should contain(%("contracts"."deleted_at" IS NOT NULL))
      end

      it "generates BETWEEN condition" do
        query = build_query(:contracts)
          .where { |e| e[:contracts][:amount].between(1000, 5000) }
        sql, params = query.to_sql

        sql.should contain(%("contracts"."amount" BETWEEN $1 AND $2))
        params.should eq([1000, 5000])
      end

      it "generates AND expression" do
        query = build_query(:contracts)
          .where { |e| (e[:contracts][:status] == "active") & (e[:contracts][:amount] >= 1000) }
        sql, params = query.to_sql

        sql.should contain(%(("contracts"."status" = $1 AND "contracts"."amount" >= $2)))
        params.should eq(["active", 1000])
      end

      it "generates OR expression" do
        query = build_query(:contracts)
          .where { |e| (e[:contracts][:status] == "active") | (e[:contracts][:status] == "pending") }
        sql, params = query.to_sql

        sql.should contain(%(("contracts"."status" = $1 OR "contracts"."status" = $2)))
        params.should eq(["active", "pending"])
      end

      it "generates NOT expression" do
        query = build_query(:contracts)
          .where { |e| e.not(e[:contracts][:status] == "deleted") }
        sql, params = query.to_sql

        sql.should contain(%(NOT ("contracts"."status" = $1)))
        params.should eq(["deleted"])
      end

      it "generates complex nested expression" do
        query = build_query(:contracts)
          .where { |e|
            ((e[:contracts][:status] == "active") | (e[:contracts][:status] == "pending")) &
              (e[:contracts][:amount] >= 1000)
          }
        sql, params = query.to_sql

        params.should eq(["active", "pending", 1000])
      end
    end

    describe "JOIN clause" do
      it "generates INNER JOIN" do
        query = build_query(:contracts)
          .join(:users, on: {contracts: :user_id, eq: {users: :id}})
        sql, _ = query.to_sql

        sql.should contain(%(INNER JOIN "users" ON "contracts"."user_id" = "users"."id"))
      end

      it "generates LEFT JOIN" do
        query = build_query(:contracts)
          .left_join(:users, on: {contracts: :user_id, eq: {users: :id}})
        sql, _ = query.to_sql

        sql.should contain(%(LEFT JOIN "users" ON "contracts"."user_id" = "users"."id"))
      end

      it "generates RIGHT JOIN" do
        query = build_query(:contracts)
          .right_join(:users, on: {contracts: :user_id, eq: {users: :id}})
        sql, _ = query.to_sql

        sql.should contain(%(RIGHT JOIN "users" ON "contracts"."user_id" = "users"."id"))
      end

      it "generates multiple joins" do
        query = build_query(:contracts)
          .join(:users, on: {contracts: :user_id, eq: {users: :id}})
          .left_join(:invoices, on: {contracts: :id, eq: {invoices: :contract_id}})
        sql, _ = query.to_sql

        sql.should contain(%(INNER JOIN "users"))
        sql.should contain(%(LEFT JOIN "invoices"))
      end
    end

    describe "ORDER BY clause" do
      it "generates ORDER BY ASC" do
        query = build_query(:contracts)
          .order(contracts: {name: :asc})
        sql, _ = query.to_sql

        sql.should contain(%(ORDER BY "contracts"."name" ASC))
      end

      it "generates ORDER BY DESC" do
        query = build_query(:contracts)
          .order(contracts: {created_at: :desc})
        sql, _ = query.to_sql

        sql.should contain(%(ORDER BY "contracts"."created_at" DESC))
      end

      it "generates multiple ORDER BY columns" do
        query = build_query(:contracts)
          .order(contracts: {status: :asc, created_at: :desc})
        sql, _ = query.to_sql

        sql.should contain(%(ORDER BY))
        sql.should contain(%("contracts"."status" ASC))
        sql.should contain(%("contracts"."created_at" DESC))
      end
    end

    describe "LIMIT and OFFSET" do
      it "generates LIMIT" do
        query = build_query(:contracts).limit(10)
        sql, params = query.to_sql

        sql.should end_with(%(LIMIT $1))
        params.should eq([10])
      end

      it "generates OFFSET" do
        query = build_query(:contracts).offset(20)
        sql, params = query.to_sql

        sql.should end_with(%(OFFSET $1))
        params.should eq([20])
      end

      it "generates LIMIT and OFFSET together" do
        query = build_query(:contracts).limit(10).offset(20)
        sql, params = query.to_sql

        sql.should contain(%(LIMIT $1 OFFSET $2))
        params.should eq([10, 20])
      end

      it "places LIMIT/OFFSET after WHERE and ORDER BY" do
        query = build_query(:contracts)
          .where(contracts: {status: "active"})
          .order(contracts: {created_at: :desc})
          .limit(10)
          .offset(20)
        sql, params = query.to_sql

        # Verify order: WHERE, ORDER BY, LIMIT, OFFSET
        where_pos = sql.index("WHERE").not_nil!
        order_pos = sql.index("ORDER BY").not_nil!
        limit_pos = sql.index("LIMIT").not_nil!
        offset_pos = sql.index("OFFSET").not_nil!

        where_pos.should be < order_pos
        order_pos.should be < limit_pos
        limit_pos.should be < offset_pos

        params.should eq(["active", 10, 20])
      end
    end

    describe "complex queries" do
      it "generates full query with all clauses" do
        query = build_query(:contracts)
          .select(contracts: [:id, :reference, :status], users: [:name])
          .join(:users, on: {contracts: :user_id, eq: {users: :id}})
          .where(contracts: {status: "active"})
          .where { |e| e[:contracts][:amount] >= 1000 }
          .order(contracts: {created_at: :desc})
          .limit(20)
          .offset(40)
          .distinct

        sql, params = query.to_sql

        sql.should start_with(%(SELECT DISTINCT))
        sql.should contain(%("contracts"."id"))
        sql.should contain(%("users"."name"))
        sql.should contain(%(FROM "contracts"))
        sql.should contain(%(INNER JOIN "users"))
        sql.should contain(%(WHERE))
        sql.should contain(%("contracts"."status" = $1))
        sql.should contain(%("contracts"."amount" >= $2))
        sql.should contain(%(ORDER BY "contracts"."created_at" DESC))
        sql.should contain(%(LIMIT $3))
        sql.should contain(%(OFFSET $4))

        params.should eq(["active", 1000, 20, 40])
      end
    end
  end

  describe "#compile_count" do
    it "generates COUNT query" do
      query = build_query(:contracts)
      sql, _ = query.count_sql

      sql.should eq(%(SELECT COUNT(*) FROM "contracts"))
    end

    it "includes WHERE clause in COUNT" do
      query = build_query(:contracts)
        .where(contracts: {status: "active"})
      sql, params = query.count_sql

      sql.should eq(%(SELECT COUNT(*) FROM "contracts" WHERE "contracts"."status" = $1))
      params.should eq(["active"])
    end

    it "includes JOINs in COUNT" do
      query = build_query(:contracts)
        .join(:users, on: {contracts: :user_id, eq: {users: :id}})
        .where(contracts: {status: "active"})
      sql, _ = query.count_sql

      sql.should contain(%(SELECT COUNT(*) FROM "contracts"))
      sql.should contain(%(INNER JOIN "users"))
      sql.should contain(%(WHERE))
    end

    it "excludes ORDER BY, LIMIT, OFFSET from COUNT" do
      query = build_query(:contracts)
        .where(contracts: {status: "active"})
        .order(contracts: {created_at: :desc})
        .limit(10)
        .offset(20)
      sql, _ = query.count_sql

      sql.should_not contain(%(ORDER BY))
      sql.should_not contain(%(LIMIT))
      sql.should_not contain(%(OFFSET))
    end
  end
end
