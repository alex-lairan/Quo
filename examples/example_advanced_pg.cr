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
  total = row["total_spent"].as(Int64 | PG::Numeric)
  avg = row["avg_order"].as(PG::Numeric)
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
puts "  Avg views: #{post_stats["avg_views"].as(PG::Numeric).to_f.round(2)}"
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
  spent = row["total_spent"].as(Int64 | PG::Numeric).to_f / 100
  puts "  User #{row["user_id"]}: $#{spent}"
end

# Multiple CTEs: High-value customers with their order details
puts "\n--- High-Value Customer Analysis (Multiple CTEs) ---"

# CTE: Calculate lifetime value and order count per user
customer_totals_query = Quo::Query.new(:orders, adapter)
  .select(orders: [:user_id])
  .select_sum(:orders, :total_cents, as: :lifetime_value)
  .select_count(as: :order_count)
  .group(orders: [:user_id])

# Main query: Join CTE with users, filter high-value customers
high_value_customers = Quo::Query.new(:customer_totals, adapter)
  .with_cte(:customer_totals, customer_totals_query)
  .select(users: [:name])
  .select(customer_totals: [:lifetime_value, :order_count])
  .join(:users, on: {users: :id, eq: {customer_totals: :user_id}})
  .where { |e| e[:customer_totals][:lifetime_value] >= 100000 }
  .order(customer_totals: {lifetime_value: :desc})
  .to_a

high_value_customers.each do |row|
  value = row["lifetime_value"].as(Int64 | PG::Numeric).to_f / 100
  puts "  #{row["name"]}: $#{value} (#{row["order_count"]} orders)"
end

# Recursive CTE: Category hierarchy using the builder
puts "\n--- Category Hierarchy (Recursive CTE with Builder) ---"

# Base case: top-level categories (parent_id IS NULL)
base_query = Quo::Query.new(:categories, adapter)
  .select(categories: [:id, :name, :parent_id])
  .where { |e| e[:categories][:parent_id].is_null }

# Recursive case: child categories joined to the CTE
# Note: We reference :category_tree as the table since it's the CTE name
recursive_query = Quo::Query.new(:categories, adapter)
  .select(categories: [:id, :name, :parent_id])
  .join(:category_tree, on: {categories: :parent_id, eq: {category_tree: :id}})

# Main query: select from the CTE, ordered by name for hierarchy display
category_hierarchy = Quo::Query.new(:category_tree, adapter)
  .with_recursive_cte(:category_tree, base: base_query, recursive: recursive_query)
  .select(category_tree: [:id, :name, :parent_id])
  .to_a

# Build a tree structure for display
def print_category_tree(categories : Quo::ResultSet, parent_id : Int64?, depth : Int32 = 0)
  categories.each do |cat|
    cat_parent = cat["parent_id"]
    cat_parent_id = cat_parent.nil? ? nil : cat_parent.as(Int64)

    if cat_parent_id == parent_id
      indent = "  " * (depth + 1)
      puts "#{indent}#{cat["name"]}"
      print_category_tree(categories, cat["id"].as(Int64), depth + 1)
    end
  end
end

print_category_tree(category_hierarchy, nil)

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

# CTE 1: Aggregate orders per user
user_orders_query = Quo::Query.new(:orders, adapter)
  .select(orders: [:user_id])
  .select_count(as: :order_count)
  .select_sum(:orders, :total_cents, as: :total_spent)
  .select_max(:orders, :created_at, as: :last_order)
  .where { |e| e[:orders][:status] == "completed" }
  .group(orders: [:user_id])

# CTE 2: Aggregate posts per user
user_posts_query = Quo::Query.new(:posts, adapter)
  .select(posts: [:user_id])
  .select_count(as: :post_count)
  .select_sum(:posts, :view_count, as: :total_views)
  .where { |e| e[:posts][:status] == "published" }
  .group(posts: [:user_id])

# Main query: Join users with both CTEs
dashboard = Quo::Query.new(:users, adapter)
  .with_cte(:user_orders, user_orders_query)
  .with_cte(:user_posts, user_posts_query)
  .select(users: [:id, :name, :email, :role, :tier])
  .select(user_orders: [:order_count, :total_spent])
  .select(user_posts: [:post_count, :total_views])
  .left_join(:user_orders, on: {user_orders: :user_id, eq: {users: :id}})
  .left_join(:user_posts, on: {user_posts: :user_id, eq: {users: :id}})
  .where { |e| e[:users][:active] == true }
  .where { |e| e[:users][:tier] == "premium" }
  .order(user_orders: {total_spent: :desc})
  .to_a

puts "  " + "-" * 70
puts "  | %-20s | %-8s | %6s | %10s | %5s | %6s |" % ["Name", "Role", "Orders", "Spent", "Posts", "Views"]
puts "  " + "-" * 70

# Sort by total_spent descending, treating nil as 0 (like NULLS LAST)
dashboard.sort_by! { |row|
  val = row["total_spent"]
  case val
  when PG::Numeric then -val.to_f
  when Int64       then -val.to_f
  else             0.0
  end
}

dashboard.each do |row|
  # Handle NULL values from LEFT JOIN (like COALESCE)
  orders = row["order_count"]? || 0
  spent_val = row["total_spent"]
  spent = case spent_val
          when PG::Numeric then spent_val.to_f / 100
          when Int64       then spent_val.to_f / 100
          else             0.0
          end
  posts = row["post_count"]? || 0
  views = row["total_views"]? || 0

  puts "  | %-20s | %-8s | %6s | $%9.2f | %5s | %6s |" % [
    row["name"],
    row["role"],
    orders,
    spent,
    posts,
    views
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
