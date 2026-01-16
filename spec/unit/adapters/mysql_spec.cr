require "../../spec_helper"

# Helper to build a query with MySQL adapter
def build_mysql_query(table : Symbol) : Quo::Query
  adapter = Quo::Adapters::MySQL.new
  Quo::Query.new(table, adapter)
end

describe Quo::Adapters::MySQL do
  describe "#quote_identifier" do
    it "quotes with backticks" do
      adapter = Quo::Adapters::MySQL.new
      adapter.quote_identifier(:users).should eq("`users`")
    end
  end

  describe "#placeholder" do
    it "returns ? for all parameters" do
      adapter = Quo::Adapters::MySQL.new
      adapter.placeholder(0).should eq("?")
      adapter.placeholder(1).should eq("?")
      adapter.placeholder(5).should eq("?")
    end
  end

  describe "#compile" do
    it "generates basic SELECT with backtick quotes" do
      query = build_mysql_query(:users)
      sql, params = query.to_sql

      sql.should eq("SELECT `users`.* FROM `users`")
      params.should be_empty
    end

    it "generates SELECT with specific columns" do
      query = build_mysql_query(:users)
        .select(users: [:id, :name])
      sql, params = query.to_sql

      sql.should eq("SELECT `users`.`id`, `users`.`name` FROM `users`")
      params.should be_empty
    end

    it "generates WHERE clause with ? placeholders" do
      query = build_mysql_query(:users)
        .where(users: {id: 1})
      sql, params = query.to_sql

      sql.should eq("SELECT `users`.* FROM `users` WHERE `users`.`id` = ?")
      params.should eq([1.as(DB::Any)])
    end

    it "generates multiple WHERE conditions" do
      query = build_mysql_query(:users)
        .where(users: {active: true, role: "admin"})
      sql, params = query.to_sql

      sql.should contain("WHERE")
      sql.should contain("`users`.`active` = ?")
      sql.should contain("`users`.`role` = ?")
      params.size.should eq(2)
    end

    it "generates INNER JOIN" do
      query = build_mysql_query(:users)
        .join(:posts, on: {users: :id, eq: {posts: :user_id}})
      sql, _ = query.to_sql

      sql.should contain("INNER JOIN `posts` ON `users`.`id` = `posts`.`user_id`")
    end

    it "generates LEFT JOIN" do
      query = build_mysql_query(:users)
        .left_join(:posts, on: {users: :id, eq: {posts: :user_id}})
      sql, _ = query.to_sql

      sql.should contain("LEFT JOIN `posts` ON `users`.`id` = `posts`.`user_id`")
    end

    it "generates RIGHT JOIN" do
      query = build_mysql_query(:users)
        .right_join(:posts, on: {users: :id, eq: {posts: :user_id}})
      sql, _ = query.to_sql

      sql.should contain("RIGHT JOIN `posts` ON `users`.`id` = `posts`.`user_id`")
    end

    it "raises error for FULL JOIN" do
      query = build_mysql_query(:users)
        .full_join(:posts, on: {users: :id, eq: {posts: :user_id}})

      expect_raises(Quo::AdapterError, /FULL OUTER JOIN/) do
        query.to_sql
      end
    end

    it "generates ORDER BY" do
      query = build_mysql_query(:users)
        .order(users: {created_at: :desc, name: :asc})
      sql, _ = query.to_sql

      sql.should contain("ORDER BY `users`.`created_at` DESC, `users`.`name` ASC")
    end

    it "generates LIMIT and OFFSET" do
      query = build_mysql_query(:users)
        .limit(10)
        .offset(20)
      sql, params = query.to_sql

      sql.should contain("LIMIT ? OFFSET ?")
      params.should eq([10.as(DB::Any), 20.as(DB::Any)])
    end

    it "generates DISTINCT" do
      query = build_mysql_query(:users)
        .distinct
      sql, _ = query.to_sql

      sql.should eq("SELECT DISTINCT `users`.* FROM `users`")
    end

    it "generates GROUP BY" do
      query = build_mysql_query(:users)
        .select(users: [:status])
        .select_count(as: :count)
        .group(users: [:status])
      sql, _ = query.to_sql

      sql.should contain("GROUP BY `users`.`status`")
    end

    it "uses LOWER for ILIKE" do
      adapter = Quo::Adapters::MySQL.new
      query = Quo::Query.new(:users, adapter)
        .where { |e| e[:users][:name].ilike("%john%") }
      sql, params = query.to_sql

      sql.should contain("LOWER(`users`.`name`) LIKE LOWER(?)")
      params.should eq(["%john%".as(DB::Any)])
    end
  end

  describe "#compile_insert" do
    it "generates INSERT statement" do
      adapter = Quo::Adapters::MySQL.new
      query = Quo::InsertQuery.new(:users, adapter)
        .values(name: "John", email: "john@example.com")
      sql, params = query.to_sql

      sql.should eq("INSERT INTO `users` (`name`, `email`) VALUES (?, ?)")
      params.size.should eq(2)
    end

    it "handles multiple rows" do
      adapter = Quo::Adapters::MySQL.new
      query = Quo::InsertQuery.new(:users, adapter)
        .values(name: "John")
        .values(name: "Jane")
      sql, params = query.to_sql

      sql.should contain("VALUES (?)") # Single column
      sql.should contain("), (")       # Multiple value groups
      params.size.should eq(2)
    end
  end

  describe "#compile_update" do
    it "generates UPDATE statement" do
      adapter = Quo::Adapters::MySQL.new
      query = Quo::UpdateQuery.new(:users, adapter)
        .set(name: "John Doe")
        .where(users: {id: 1})
      sql, params = query.to_sql

      sql.should eq("UPDATE `users` SET `name` = ? WHERE `users`.`id` = ?")
      params.should eq(["John Doe".as(DB::Any), 1.as(DB::Any)])
    end
  end

  describe "#compile_delete" do
    it "generates DELETE statement" do
      adapter = Quo::Adapters::MySQL.new
      query = Quo::DeleteQuery.new(:users, adapter)
        .where(users: {id: 1})
      sql, params = query.to_sql

      sql.should eq("DELETE FROM `users` WHERE `users`.`id` = ?")
      params.should eq([1.as(DB::Any)])
    end
  end
end
