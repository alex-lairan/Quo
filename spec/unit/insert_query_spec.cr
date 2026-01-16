require "../spec_helper"

describe Quo::InsertQuery do
  adapter = Quo::Adapters::Test.new

  describe "#values" do
    it "generates INSERT with single row" do
      query = Quo::InsertQuery.new(:users, adapter)
        .values(name: "Alice", email: "alice@example.com")

      sql, params = query.to_sql
      sql.should eq("INSERT INTO \"users\" (\"name\", \"email\") VALUES ($1, $2)")
      params.should eq(["Alice", "alice@example.com"])
    end

    it "generates INSERT with hash values" do
      values = {:name => "Bob".as(DB::Any), :email => "bob@example.com".as(DB::Any)}
      query = Quo::InsertQuery.new(:users, adapter)
        .values(values)

      sql, params = query.to_sql
      sql.should contain("INSERT INTO \"users\"")
      sql.should contain("VALUES")
      params.size.should eq(2)
    end
  end

  describe "#values_many" do
    it "generates INSERT with multiple rows" do
      rows = [
        {:name => "Alice".as(DB::Any), :email => "alice@example.com".as(DB::Any)},
        {:name => "Bob".as(DB::Any), :email => "bob@example.com".as(DB::Any)},
      ]
      query = Quo::InsertQuery.new(:users, adapter)
        .values_many(rows)

      sql, params = query.to_sql
      sql.should contain("INSERT INTO \"users\"")
      sql.should contain("VALUES ($1, $2), ($3, $4)")
      params.size.should eq(4)
    end

    it "handles missing columns with DEFAULT" do
      rows = [
        {:name => "Alice".as(DB::Any), :email => "alice@example.com".as(DB::Any)},
        {:name => "Bob".as(DB::Any)},  # Missing email
      ]
      query = Quo::InsertQuery.new(:users, adapter)
        .values_many(rows)

      sql, params = query.to_sql
      sql.should contain("VALUES ($1, $2), ($3, DEFAULT)")
      params.size.should eq(3)
    end
  end

  describe "#returning" do
    it "generates RETURNING clause" do
      query = Quo::InsertQuery.new(:users, adapter)
        .values(name: "Alice")
        .returning(users: [:id, :created_at])

      sql, _ = query.to_sql
      sql.should contain("RETURNING \"id\", \"created_at\"")
    end
  end

  describe "immutability" do
    it "returns new instances" do
      base = Quo::InsertQuery.new(:users, adapter)
      with_values = base.values(name: "Alice")

      base.values_list.should be_empty
      with_values.values_list.size.should eq(1)
    end
  end

  describe "error handling" do
    it "raises error when no values provided" do
      query = Quo::InsertQuery.new(:users, adapter)

      expect_raises(Quo::QueryError, /INSERT requires at least one row/) do
        query.to_sql
      end
    end
  end
end
