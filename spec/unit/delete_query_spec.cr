require "../spec_helper"

describe Quo::DeleteQuery do
  adapter = Quo::Adapters::Test.new

  describe "basic DELETE" do
    it "generates DELETE FROM table" do
      query = Quo::DeleteQuery.new(:users, adapter)

      sql, params = query.to_sql
      sql.should eq("DELETE FROM \"users\"")
      params.should be_empty
    end
  end

  describe "#where" do
    it "generates DELETE with WHERE clause" do
      query = Quo::DeleteQuery.new(:users, adapter)
        .where(users: {id: 1})

      sql, params = query.to_sql
      sql.should eq("DELETE FROM \"users\" WHERE \"users\".\"id\" = $1")
      params.should eq([1])
    end

    it "generates DELETE with expression WHERE" do
      query = Quo::DeleteQuery.new(:users, adapter)
        .where { |e| e[:users][:status] == "deleted" }

      sql, params = query.to_sql
      sql.should contain("WHERE \"users\".\"status\" = $1")
      params.should eq(["deleted"])
    end

    it "combines multiple WHERE clauses with AND" do
      query = Quo::DeleteQuery.new(:users, adapter)
        .where(users: {status: "inactive"})
        .where(users: {role: "guest"})

      sql, _ = query.to_sql
      sql.should contain("WHERE \"users\".\"status\" = $1 AND \"users\".\"role\" = $2")
    end

    it "supports complex WHERE expressions" do
      query = Quo::DeleteQuery.new(:sessions, adapter)
        .where { |e| (e[:sessions][:expired] == true) | (e[:sessions][:user_id].is_null) }

      sql, params = query.to_sql
      sql.should contain("WHERE (\"sessions\".\"expired\" = $1 OR \"sessions\".\"user_id\" IS NULL)")
      params.should eq([true])
    end
  end

  describe "#returning" do
    it "generates RETURNING clause" do
      query = Quo::DeleteQuery.new(:users, adapter)
        .where(users: {id: 1})
        .returning(users: [:id, :email])

      sql, _ = query.to_sql
      sql.should contain("RETURNING \"id\", \"email\"")
    end
  end

  describe "immutability" do
    it "returns new instances" do
      base = Quo::DeleteQuery.new(:users, adapter)
      with_where = base.where(users: {id: 1})
      with_returning = with_where.returning(users: [:id])

      base.where_clauses.should be_empty
      base.returning_columns.should be_empty
      with_where.where_clauses.size.should eq(1)
      with_where.returning_columns.should be_empty
      with_returning.where_clauses.size.should eq(1)
      with_returning.returning_columns.size.should eq(1)
    end
  end

  describe "safety" do
    it "allows DELETE without WHERE (for truncate scenarios)" do
      query = Quo::DeleteQuery.new(:temp_data, adapter)

      sql, params = query.to_sql
      sql.should eq("DELETE FROM \"temp_data\"")
      params.should be_empty
    end
  end
end
