require "../src/quo"
require "sqlite3"

# Example: Custom logger implementation
class MyCustomLogger < Quo::Logger
  def debug(message : String)
    STDOUT.puts "[DEBUG] #{Time.utc} - #{message}"
  end

  def info(message : String)
    STDOUT.puts "[INFO]  #{Time.utc} - #{message}"
  end

  def warn(message : String)
    STDOUT.puts "[WARN]  #{Time.utc} - #{message}"
  end

  def error(message : String)
    STDERR.puts "[ERROR] #{Time.utc} - #{message}"
  end
end

# Configure enhanced logging
Quo::Logging.log_level = Quo::LogLevel::Info
Quo::Logging.slow_query_threshold = 50.milliseconds
Quo::Logging.slow_compile_threshold = 10.milliseconds

# Optional: Use custom logger
# Quo::Logging.logger = MyCustomLogger.new

# Subscribe to all query events
Quo::Logging.subscribe do |event|
  puts "\n=== Query Event ==="
  puts "SQL: #{event.sql}"
  puts "Params: #{event.params}"
  puts "Compile time: #{event.compile_time.total_milliseconds}ms"
  puts "Execute time: #{event.execute_time.total_milliseconds}ms"
  puts "Total time: #{event.duration.total_milliseconds}ms"
  puts "Operation: #{event.operation}"
  puts "Success: #{event.success?}"

  if event.slow_compile?(Quo::Logging.slow_compile_threshold)
    puts "⚠️  SLOW COMPILE detected!"
  end

  if event.slow?(Quo::Logging.slow_query_threshold)
    puts "⚠️  SLOW QUERY detected!"
  end
  puts "==================\n"
end

# Handle slow queries specifically
Quo::Logging.on_slow_query do |event|
  puts "🐌 Slow query alert: #{event.sql} took #{event.duration.total_milliseconds}ms"
end

# Example usage
DB.open "sqlite3::memory:" do |db|
  adapter = Quo::Adapters::SQLite.new(db)

  # Create test table
  db.exec <<-SQL
    CREATE TABLE users (
      id INTEGER PRIMARY KEY,
      name TEXT NOT NULL,
      email TEXT NOT NULL,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    )
  SQL

  puts "=== Example 1: INSERT with timing breakdown ==="
  Quo::InsertQuery.new(:users, adapter)
    .values(name: "Alice", email: "alice@example.com")
    .execute

  puts "\n=== Example 2: Complex SELECT with timing ==="
  query = Quo::Query.new(:users, adapter)
    .select(users: [:id, :name, :email])
    .where(users: {name: "Alice"})
    .order(users: {created_at: :desc})
    .limit(10)

  results = query.to_a
  puts "Found #{results.size} users"

  puts "\n=== Example 3: UPDATE with timing ==="
  Quo::UpdateQuery.new(:users, adapter)
    .set(email: "alice.smith@example.com")
    .where(users: {name: "Alice"})
    .execute

  puts "\n=== Example 4: COUNT query ==="
  count = query.count
  puts "Total users: #{count}"
end

puts "\n✅ Logging example complete!"
