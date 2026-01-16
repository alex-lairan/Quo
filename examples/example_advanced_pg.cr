# Advanced PostgreSQL Example
# Demonstrates: Transactions, CTEs, Aggregations, Subqueries, Set Operations
#
# Setup:
#   createdb quo_demo
#   psql -d quo_demo -f examples/setup_pg.sql
#
# Run:
#   crystal run examples/example_advanced_pg.cr

require "pg"
require "../src/quo"

# Connect to PostgreSQL
DB_URL = ENV["DATABASE_URL"]? || "postgres://localhost/quo_demo"
db = DB.open(DB_URL)
adapter = Quo::Adapters::Postgres.new(db)

# Enable logging
Quo::Logging.log_level = Quo::LogLevel::Info
Quo::Logging.slow_query_threshold = 50.milliseconds

puts "=" * 60
puts "Quo Advanced PostgreSQL Examples"
puts "=" * 60

# =============================================================================
# 1. AGGREGATIONS - GROUP BY, HAVING, COUNT, SUM, AVG
# =============================================================================

puts "\n" + "=" * 60
puts "1. AGGREGATIONS"
puts "=" * 60

# Count users by role
puts "\n--- Users by Role ---"
users_by_role = Quo::Query.new(:users, adapter)
  .select(users: [:role])
  .select_count(as: :count)
  .group(users: [:role])
  .order(users: { role: :asc })
  .to_a

users_by_role.each do |row|
  puts "  #{row["role"]}: #{row["count"]} users"
end

# Orders stats by user
puts "\n--- Order Stats by User (min 1 order) ---"
order_stats = Quo::Query.new(:orders, adapter)
  .select(orders: [:user_id])
  .select_count(as: :order_count)
  .select_sum(:orders, :total_cents, as: :total_spent)
  .select_avg(:orders, :total_cents, as: :avg_order)
  .group(orders: [:user_id])
  .having { |h| h.count >= 1 }
  .to_a

order_stats.each do |row|
  total = row["total_spent"].as(Int64 | Float64)
  avg = row["avg_order"].as(Float64)
  puts "  User #{row["user_id"]}: #{row["order_count"]} orders, " \
       "total: $#{total.to_f / 100}, avg: $#{avg.to_f / 100}"
end

# Posts stats
puts "\n--- Post Stats ---"
post_stats = Quo::Query.new(:posts, adapter)
  .select_count(as: :total_posts)
  .select_sum(:posts, :view_count, as: :total_views)
  .select_avg(:posts, :view_count, as: :avg_views)
  .select_max(:posts, :view_count, as: :max_views)
  .first!

puts "  Total posts: #{post_stats["total_posts"]}"
puts "  Total views: #{post_stats["total_views"]}"
puts "  Avg views: #{post_stats["avg_views"].as(Float64).round(2)}"
puts "  Max views: #{post_stats["max_views"]}"

# =============================================================================
# 2. SUBQUERIES - IN, NOT IN, EXISTS, Scalar
# =============================================================================

puts "\n" + "=" * 60
puts "2. SUBQUERIES"
puts "=" * 60

# Users who have placed orders (IN subquery)
puts "\n--- Users with Orders (IN subquery) ---"
users_with_orders_subquery = Quo::Query.new(:orders, adapter)
  .select(orders: [:user_id])
  .distinct

customers = Quo::Query.new(:users, adapter)
  .select(users: [:id, :name, :email])
  .where { |e| e[:users][:id].in(users_with_orders_subquery) }
  .to_a

customers.each do |user|
  puts "  #{user["name"]} (#{user["email"]})"
end

# Users who have NOT placed orders (NOT IN subquery)
puts "\n--- Users without Orders (NOT IN subquery) ---"
non_customers = Quo::Query.new(:users, adapter)
  .select(users: [:id, :name, :email])
  .where { |e| e[:users][:id].not_in(users_with_orders_subquery) }
  .to_a

non_customers.each do |user|
  puts "  #{user["name"]} (#{user["email"]})"
end

# Users with published posts (EXISTS subquery)
puts "\n--- Authors with Published Posts (EXISTS) ---"
published_posts = Quo::Query.new(:posts, adapter)
  .select(posts: [:id])
  .where(posts: { status: "published" })

# Note: EXISTS needs correlation, using IN for this demo
authors_subquery = Quo::Query.new(:posts, adapter)
  .select(posts: [:user_id])
  .where(posts: { status: "published" })
  .distinct

authors = Quo::Query.new(:users, adapter)
  .select(users: [:id, :name])
  .where { |e| e[:users][:id].in(authors_subquery) }
  .to_a

authors.each do |user|
  puts "  #{user["name"]}"
end

# =============================================================================
# 3. SET OPERATIONS - UNION, INTERSECT, EXCEPT
# =============================================================================

puts "\n" + "=" * 60
puts "3. SET OPERATIONS"
puts "=" * 60

# UNION: Admins OR Premium users
puts "\n--- Admins OR Premium Users (UNION) ---"
admins = Quo::Query.new(:users, adapter)
  .select(users: [:id, :name, :role, :tier])
  .where(users: { role: "admin" })

premium = Quo::Query.new(:users, adapter)
  .select(users: [:id, :name, :role, :tier])
  .where(users: { tier: "premium" })

special_users = admins.union(premium).to_a
special_users.each do |user|
  puts "  #{user["name"]} (role: #{user["role"]}, tier: #{user["tier"]})"
end

# INTERSECT: Active AND Premium users
puts "\n--- Active AND Premium Users (INTERSECT) ---"
active_users = Quo::Query.new(:users, adapter)
  .select(users: [:id, :name])
  .where(users: { active: true })

premium_users = Quo::Query.new(:users, adapter)
  .select(users: [:id, :name])
  .where(users: { tier: "premium" })

active_premium = active_users.intersect(premium_users).to_a
active_premium.each do |user|
  puts "  #{user["name"]}"
end

# EXCEPT: Active users who are NOT free tier
puts "\n--- Active Non-Free Users (EXCEPT) ---"
all_active = Quo::Query.new(:users, adapter)
  .select(users: [:id, :name])
  .where(users: { active: true })

free_users = Quo::Query.new(:users, adapter)
  .select(users: [:id, :name])
  .where(users: { tier: "free" })

paying_active = all_active.except(free_users).to_a
paying_active.each do |user|
  puts "  #{user["name"]}"
end

# =============================================================================
# 4. COMMON TABLE EXPRESSIONS (CTEs)
# =============================================================================

puts "\n" + "=" * 60
puts "4. COMMON TABLE EXPRESSIONS (CTEs)"
puts "=" * 60

# Basic CTE: Top spenders
puts "\n--- Top Spenders (CTE) ---"
top_spenders_query = Quo::Query.new(:orders, adapter)
  .select(orders: [:user_id])
  .select_sum(:orders, :total_cents, as: :total_spent)
  .group(orders: [:user_id])
  .having { |h| h.sum(:orders, :total_cents) >= 100000 }

top_spenders = Quo::Query.new(:top_spenders, adapter)
  .with_cte(:top_spenders, top_spenders_query)
  .select(top_spenders: [:user_id, :total_spent])
  .to_a

top_spenders.each do |row|
  spent = row["total_spent"].as(Int64 | Float64).to_f / 100
  puts "  User #{row["user_id"]}: $#{spent}"
end

# Multiple CTEs: High-value customers with their order details
puts "\n--- High-Value Customer Analysis (Multiple CTEs) ---"
customer_totals = Quo::Query.new(:orders, adapter)
  .select(orders: [:user_id])
  .select_sum(:orders, :total_cents, as: :lifetime_value)
  .select_count(as: :order_count)
  .group(orders: [:user_id])

high_value_ids = Quo::Query.new(:customer_totals, adapter)
  .select(customer_totals: [:user_id])
  .where { |e| e[:customer_totals][:lifetime_value] >= 100000 }

# Execute as separate queries for demo (CTEs work best with single query)
sql = <<-SQL
  WITH customer_totals AS (
    SELECT "orders"."user_id", SUM("orders"."total_cents") AS lifetime_value, COUNT(*) AS order_count
    FROM "orders"
    GROUP BY "orders"."user_id"
  )
  SELECT u.name, ct.lifetime_value, ct.order_count
  FROM customer_totals ct
  JOIN users u ON u.id = ct.user_id
  WHERE ct.lifetime_value >= 100000
  ORDER BY ct.lifetime_value DESC
SQL

results = adapter.execute(sql, [] of DB::Any)
results.each do |row|
  value = row["lifetime_value"].as(Int64 | Float64).to_f / 100
  puts "  #{row["name"]}: $#{value} (#{row["order_count"]} orders)"
end

# Recursive CTE: Category hierarchy
puts "\n--- Category Hierarchy (Recursive CTE) ---"
recursive_sql = <<-SQL
  WITH RECURSIVE category_tree AS (
    -- Base case: top-level categories
    SELECT id, name, parent_id, 0 AS depth, name::text AS path
    FROM categories
    WHERE parent_id IS NULL

    UNION ALL

    -- Recursive case: child categories
    SELECT c.id, c.name, c.parent_id, ct.depth + 1, ct.path || ' > ' || c.name
    FROM categories c
    JOIN category_tree ct ON c.parent_id = ct.id
  )
  SELECT * FROM category_tree ORDER BY path
SQL

categories = adapter.execute(recursive_sql, [] of DB::Any)
categories.each do |cat|
  indent = "  " * (cat["depth"].as(Int32 | Int64).to_i + 1)
  puts "#{indent}#{cat["name"]}"
end

# =============================================================================
# 5. TRANSACTIONS
# =============================================================================

puts "\n" + "=" * 60
puts "5. TRANSACTIONS"
puts "=" * 60

# Simple transaction: Transfer funds between accounts
puts "\n--- Fund Transfer Transaction ---"

def transfer_funds(adapter, from_id : Int64, to_id : Int64, amount : Int64)
  adapter.transaction(isolation: Quo::IsolationLevel::Serializable) do |tx|
    # Get source account
    source = tx[:accounts].where(accounts: { id: from_id }).first!
    source_balance = source["balance"].as(Int64)
    source_name = source["name"].as(String)

    puts "  Source: #{source_name}, Balance: $#{source_balance / 100}"

    if source_balance < amount
      raise "Insufficient funds in #{source_name}"
    end

    # Get destination account
    dest = tx[:accounts].where(accounts: { id: to_id }).first!
    dest_balance = dest["balance"].as(Int64)
    dest_name = dest["name"].as(String)

    puts "  Destination: #{dest_name}, Balance: $#{dest_balance / 100}"
    puts "  Transferring: $#{amount / 100}"

    # Debit source
    tx.update(:accounts)
      .set(balance: source_balance - amount)
      .where(accounts: { id: from_id })
      .execute

    # Credit destination
    tx.update(:accounts)
      .set(balance: dest_balance + amount)
      .where(accounts: { id: to_id })
      .execute

    # Log the transfer
    tx.insert(:transfers)
      .values(from_account: from_id, to_account: to_id, amount: amount, created_at: Time.utc)
      .execute

    # Verify
    new_source = tx[:accounts].where(accounts: { id: from_id }).first!
    new_dest = tx[:accounts].where(accounts: { id: to_id }).first!

    puts "  After transfer:"
    puts "    #{source_name}: $#{new_source["balance"].as(Int64) / 100}"
    puts "    #{dest_name}: $#{new_dest["balance"].as(Int64) / 100}"

    {from: from_id, to: to_id, amount: amount}
  end
end

# Execute transfer from Alice Checking to Bob Checking
result = transfer_funds(adapter, 1_i64, 3_i64, 5000_i64)
puts "  Transfer completed: #{result}"

# Transaction with savepoint
puts "\n--- Transaction with Savepoint ---"

adapter.transaction do |tx|
  # Create a new user
  user = tx.insert(:users)
    .values(name: "Test User", email: "test_#{Time.utc.to_unix}@example.com", role: "user")
    .returning(users: [:id, :name])
    .execute_returning_one
    .not_nil!

  puts "  Created user: #{user["name"]} (ID: #{user["id"]})"

  begin
    tx.savepoint(:risky_operation) do
      # Try to create duplicate email (will fail)
      tx.insert(:users)
        .values(name: "Duplicate", email: "alice@example.com", role: "user")
        .execute
    end
  rescue ex
    puts "  Savepoint rolled back: #{ex.message}"
  end

  # This still works because savepoint contained the error
  tx.update(:users)
    .set(status: "active")
    .where(users: { id: user["id"] })
    .execute

  puts "  User activated despite savepoint rollback"
end

# =============================================================================
# 6. INSERT, UPDATE, DELETE with RETURNING
# =============================================================================

puts "\n" + "=" * 60
puts "6. MUTATIONS with RETURNING"
puts "=" * 60

# INSERT with RETURNING
puts "\n--- INSERT with RETURNING ---"
new_post = Quo::InsertQuery.new(:posts, adapter)
  .values(
    user_id: 1_i64,
    title: "New Post from Quo",
    body: "This post was created using Quo's InsertQuery",
    status: "draft",
    created_at: Time.utc
  )
  .returning(posts: [:id, :title, :created_at])
  .execute_returning_one
  .not_nil!

puts "  Created post: #{new_post["title"]} (ID: #{new_post["id"]})"

# UPDATE with RETURNING
puts "\n--- UPDATE with RETURNING ---"
updated = Quo::UpdateQuery.new(:posts, adapter)
  .set(status: "published", published_at: Time.utc, view_count: 1_i64)
  .where(posts: { id: new_post["id"] })
  .returning(posts: [:id, :title, :status, :published_at])
  .execute_returning

updated.each do |post|
  puts "  Published: #{post["title"]} at #{post["published_at"]}"
end

# DELETE with RETURNING
puts "\n--- DELETE with RETURNING ---"
deleted = Quo::DeleteQuery.new(:posts, adapter)
  .where(posts: { id: new_post["id"] })
  .returning(posts: [:id, :title])
  .execute_returning

deleted.each do |post|
  puts "  Deleted: #{post["title"]} (ID: #{post["id"]})"
end

# =============================================================================
# 7. COMPLEX REAL-WORLD QUERY
# =============================================================================

puts "\n" + "=" * 60
puts "7. COMPLEX REAL-WORLD QUERY"
puts "=" * 60

puts "\n--- Dashboard: Active Premium Users with Order Summary ---"

# This combines joins, aggregations, and conditions
dashboard_sql = <<-SQL
  WITH user_orders AS (
    SELECT
      user_id,
      COUNT(*) AS order_count,
      SUM(total_cents) AS total_spent,
      MAX(created_at) AS last_order
    FROM orders
    WHERE status = 'completed'
    GROUP BY user_id
  ),
  user_posts AS (
    SELECT
      user_id,
      COUNT(*) AS post_count,
      SUM(view_count) AS total_views
    FROM posts
    WHERE status = 'published'
    GROUP BY user_id
  )
  SELECT
    u.id,
    u.name,
    u.email,
    u.role,
    u.tier,
    COALESCE(uo.order_count, 0) AS orders,
    COALESCE(uo.total_spent, 0) AS spent,
    COALESCE(up.post_count, 0) AS posts,
    COALESCE(up.total_views, 0) AS views
  FROM users u
  LEFT JOIN user_orders uo ON uo.user_id = u.id
  LEFT JOIN user_posts up ON up.user_id = u.id
  WHERE u.active = true AND u.tier = 'premium'
  ORDER BY uo.total_spent DESC NULLS LAST
SQL

dashboard = adapter.execute(dashboard_sql, [] of DB::Any)
puts "  " + "-" * 70
puts "  | %-20s | %-8s | %6s | %10s | %5s | %6s |" % ["Name", "Role", "Orders", "Spent", "Posts", "Views"]
puts "  " + "-" * 70

dashboard.each do |row|
  spent = (row["spent"].as(Int64 | Float64 | Nil) || 0).to_f / 100
  puts "  | %-20s | %-8s | %6s | $%9.2f | %5s | %6s |" % [
    row["name"],
    row["role"],
    row["orders"],
    spent,
    row["posts"],
    row["views"]
  ]
end
puts "  " + "-" * 70

# =============================================================================
# CLEANUP & SUMMARY
# =============================================================================

puts "\n" + "=" * 60
puts "EXAMPLES COMPLETED"
puts "=" * 60

# Show final counts
puts "\nFinal database state:"
[:users, :accounts, :transfers, :posts, :orders].each do |table|
  count = Quo::Query.new(table, adapter).count
  puts "  #{table}: #{count} rows"
end

db.close
puts "\nConnection closed."
