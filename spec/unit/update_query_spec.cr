require "../spec_helper"

describe Quo::UpdateQuery do
  adapter = Quo::Adapters::Test.new

  describe "#set" do
    it "generates UPDATE with SET clause" do
      query = Quo::UpdateQuery.new(:users, adapter)
        .set(name: "New Name", status: "active")

      sql, params = query.to_sql
      sql.should contain("UPDATE \"users\" SET")
      sql.should contain("\"name\" = $1")
      sql.should contain("\"status\" = $2")
      params.should eq(["New Name", "active"])
    end

    it "accumulates SET values" do
      query = Quo::UpdateQuery.new(:users, adapter)
        .set(name: "New Name")
        .set(status: "active")

      sql, params = query.to_sql
      sql.should contain("\"name\" = $1")
      sql.should contain("\"status\" = $2")
      params.size.should eq(2)
    end
  end

  describe "#where" do
    it "generates UPDATE with WHERE clause" do
      query = Quo::UpdateQuery.new(:users, adapter)
        .set(status: "inactive")
        .where(users: {id: 1})

      sql, params = query.to_sql
      sql.should contain("UPDATE \"users\" SET \"status\" = $1 WHERE \"users\".\"id\" = $2")
      params.should eq(["inactive", 1])
    end

    it "generates UPDATE with expression WHERE" do
      query = Quo::UpdateQuery.new(:users, adapter)
        .set(status: "inactive")
        .where { |e| e[:users][:active] == false }

      sql, params = query.to_sql
      sql.should contain("WHERE \"users\".\"active\" = $2")
      params[1].should eq(false)
    end

    it "combines multiple WHERE clauses with AND" do
      query = Quo::UpdateQuery.new(:users, adapter)
        .set(status: "inactive")
        .where(users: {role: "guest"})
        .where(users: {active: false})

      sql, _ = query.to_sql
      sql.should contain("WHERE \"users\".\"role\" = $2 AND \"users\".\"active\" = $3")
    end
  end

  describe "#returning" do
    it "generates RETURNING clause" do
      query = Quo::UpdateQuery.new(:users, adapter)
        .set(status: "active")
        .where(users: {id: 1})
        .returning(users: [:id, :status, :updated_at])

      sql, _ = query.to_sql
      sql.should contain("RETURNING \"id\", \"status\", \"updated_at\"")
    end
  end

  describe "immutability" do
    it "returns new instances" do
      base = Quo::UpdateQuery.new(:users, adapter)
      with_set = base.set(name: "Test")
      with_where = with_set.where(users: {id: 1})

      base.set_values.should be_empty
      base.where_clauses.should be_empty
      with_set.set_values.size.should eq(1)
      with_set.where_clauses.should be_empty
      with_where.set_values.size.should eq(1)
      with_where.where_clauses.size.should eq(1)
    end
  end

  describe "error handling" do
    it "raises error when no SET values provided" do
      query = Quo::UpdateQuery.new(:users, adapter)

      expect_raises(Quo::QueryError, /UPDATE requires at least one SET value/) do
        query.to_sql
      end
    end
  end
end
