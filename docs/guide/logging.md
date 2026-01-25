# Logging & Instrumentation

Quo provides built-in query logging and instrumentation for debugging and monitoring.

## Quick Start

Enable basic logging:

```crystal
Quo::Logging.log_level = Quo::LogLevel::Info
```

This outputs queries to Crystal's standard Log:

```
[QUO] SELECT "users".* FROM "users" WHERE "users"."id" = $1 ["1"] (0.45ms)
```

## Log Levels

| Level | Description |
|-------|-------------|
| `Debug` | All queries with full details |
| `Info` | All queries |
| `Warn` | Only warnings |
| `Error` | Only errors |
| `None` | Disabled (default) |

```crystal
# Development
Quo::Logging.log_level = Quo::LogLevel::Debug

# Production
Quo::Logging.log_level = Quo::LogLevel::Error

# Disable
Quo::Logging.log_level = Quo::LogLevel::None
```

## Manual Enable/Disable

```crystal
# Enable without changing level
Quo::Logging.enabled = true

# Disable temporarily
Quo::Logging.enabled = false

# Check status
if Quo::Logging.enabled?
  puts "Logging is on"
end
```

## Query Subscribers

Subscribe to receive events for every query:

```crystal
Quo::Logging.subscribe do |event|
  puts "SQL: #{event.sql}"
  puts "Params: #{event.params}"
  puts "Duration: #{event.duration.total_milliseconds}ms"
  puts "Operation: #{event.operation}"  # :select, :insert, :update, :delete
end
```

### Query Event Properties

```crystal
Quo::Logging.subscribe do |event|
  event.sql            # String - The SQL query
  event.params         # Array(DB::Any) - Query parameters
  event.duration       # Time::Span - Total execution time
  event.compile_time   # Time::Span - Time to compile/build SQL
  event.execute_time   # Time::Span - Time to execute at database
  event.operation      # Symbol - :select, :insert, :update, :delete
  event.rows_affected  # Int64? - For mutations
  event.error          # Exception? - If query failed
  event.success?       # Bool - true if no error
  event.slow?(threshold)         # Bool - Check if total time exceeds threshold
  event.slow_compile?(threshold) # Bool - Check if compile time exceeds threshold
  event.slow_execute?(threshold) # Bool - Check if execute time exceeds threshold
end
```

**Timing Breakdown:**

Every query event now includes three timing measurements:

- **compile_time**: Time spent building/compiling the SQL query
- **execute_time**: Time spent executing the query at the database
- **duration**: Total time (compile_time + execute_time)

```crystal
Quo::Logging.subscribe do |event|
  puts "Compile: #{event.compile_time.total_milliseconds}ms"
  puts "Execute: #{event.execute_time.total_milliseconds}ms"
  puts "Total:   #{event.duration.total_milliseconds}ms"
end
```

### Multiple Subscribers

```crystal
# Log to file
Quo::Logging.subscribe do |event|
  File.open("queries.log", "a") do |f|
    f.puts "[#{Time.utc}] #{event.sql} (#{event.duration.total_milliseconds}ms)"
  end
end

# Send metrics
Quo::Logging.subscribe do |event|
  StatsD.timing("database.query", event.duration.total_milliseconds)
  StatsD.increment("database.operations.#{event.operation}")
end
```

## Slow Query Detection

Get notified when queries exceed a threshold:

```crystal
# Set threshold for total query time (default: 100ms)
Quo::Logging.slow_query_threshold = 50.milliseconds

# Set threshold for compile time (default: 50ms)
Quo::Logging.slow_compile_threshold = 10.milliseconds

# Subscribe to slow queries
Quo::Logging.on_slow_query do |event|
  puts "SLOW QUERY (#{event.duration.total_milliseconds}ms): #{event.sql}"
  puts "  Compile: #{event.compile_time.total_milliseconds}ms"
  puts "  Execute: #{event.execute_time.total_milliseconds}ms"

  # Alert your monitoring system
  AlertService.notify("Slow query detected", {
    sql: event.sql,
    duration: event.duration.total_milliseconds,
    compile_time: event.compile_time.total_milliseconds,
    execute_time: event.execute_time.total_milliseconds
  })
end
```

### Detecting Slow Compilation

Slow SQL compilation can indicate complex queries or inefficient query building:

```crystal
Quo::Logging.subscribe do |event|
  if event.slow_compile?(10.milliseconds)
    puts "⚠️  Slow compile (#{event.compile_time.total_milliseconds}ms): #{event.sql}"
  end

  if event.slow_execute?(100.milliseconds)
    puts "⚠️  Slow execute (#{event.execute_time.total_milliseconds}ms): #{event.sql}"
  end
end
```

### Checking in Event

You can also check in a regular subscriber:

```crystal
Quo::Logging.subscribe do |event|
  if event.slow?(100.milliseconds)
    # Handle slow query
  end
end
```

## Error Tracking

Track query failures:

```crystal
Quo::Logging.subscribe do |event|
  unless event.success?
    error = event.error.not_nil!
    ErrorTracker.capture(error, {
      sql: event.sql,
      params: event.params
    })
  end
end
```

## Clearing Subscribers

Remove all subscribers (useful in tests):

```crystal
Quo::Logging.clear_subscribers
```

## Custom Loggers

By default, Quo uses a simple STDERR logger with colored output. You can inject your own logger:

```crystal
# Implement Quo::Logger interface
class MyCustomLogger < Quo::Logger
  def debug(message : String)
    MyApp.log.debug(message)
  end

  def info(message : String)
    MyApp.log.info(message)
  end

  def warn(message : String)
    MyApp.log.warn(message)
  end

  def error(message : String)
    MyApp.log.error(message)
  end
end

# Use your custom logger
Quo::Logging.logger = MyCustomLogger.new
Quo::Logging.log_level = Quo::LogLevel::Info
```

### Crystal Log Integration

Use Crystal's standard Log facility:

```crystal
class CrystalLogAdapter < Quo::Logger
  Log = ::Log.for("quo")

  def debug(message : String)
    Log.debug { message }
  end

  def info(message : String)
    Log.info { message }
  end

  def warn(message : String)
    Log.warn { message }
  end

  def error(message : String)
    Log.error { message }
  end
end

# Configure Crystal's Log backend
Log.setup(:debug, Log::IOBackend.new(STDOUT))

# Use Crystal Log adapter
Quo::Logging.logger = CrystalLogAdapter.new
Quo::Logging.log_level = Quo::LogLevel::Debug
```

### JSON Logger Example

```crystal
class JSONLogger < Quo::Logger
  def debug(message : String)
    log("DEBUG", message)
  end

  def info(message : String)
    log("INFO", message)
  end

  def warn(message : String)
    log("WARN", message)
  end

  def error(message : String)
    log("ERROR", message)
  end

  private def log(level : String, message : String)
    STDOUT.puts({
      timestamp: Time.utc.to_rfc3339,
      level: level,
      message: message,
      source: "quo"
    }.to_json)
  end
end

Quo::Logging.logger = JSONLogger.new
```

### Custom Log Backend

```crystal
# JSON logging for production
backend = Log::IOBackend.new(
  io: File.open("queries.json.log", "a"),
  formatter: Log::Formatter.new { |entry, io|
    io << {
      timestamp: entry.timestamp,
      severity: entry.severity,
      message: entry.message,
      source: entry.source
    }.to_json
  }
)

Log.setup do |c|
  c.bind("quo", :info, backend)
end
```

## Performance Considerations

Logging has minimal overhead when disabled:

```crystal
# Zero overhead when disabled
Quo::Logging.enabled = false

# Subscribers still receive events even when logging is disabled
# This allows metrics collection without log output
Quo::Logging.enabled = false
Quo::Logging.subscribe { |e| StatsD.timing("db", e.duration) }
```

## Example: Development Logger

```crystal
# config/development.cr
Quo::Logging.log_level = Quo::LogLevel::Debug
Quo::Logging.slow_query_threshold = 100.milliseconds

Quo::Logging.on_slow_query do |event|
  puts "\e[33m[SLOW] #{event.sql}\e[0m"  # Yellow highlight
end
```

## Example: Production Monitoring

```crystal
# config/production.cr
Quo::Logging.log_level = Quo::LogLevel::Error  # Only log errors
Quo::Logging.slow_query_threshold = 200.milliseconds
Quo::Logging.slow_compile_threshold = 50.milliseconds

# Metrics for all queries with timing breakdown
Quo::Logging.subscribe do |event|
  # Track compile time separately
  Datadog.timing("quo.query.compile_time", event.compile_time.total_milliseconds, {
    operation: event.operation.to_s
  })

  # Track execute time separately
  Datadog.timing("quo.query.execute_time", event.execute_time.total_milliseconds, {
    operation: event.operation.to_s
  })

  # Track total duration
  Datadog.timing("quo.query.duration", event.duration.total_milliseconds, {
    operation: event.operation.to_s
  })

  # Track errors
  unless event.success?
    Datadog.increment("quo.query.error", {
      operation: event.operation.to_s
    })
  end

  # Alert on slow compilation
  if event.slow_compile?(Quo::Logging.slow_compile_threshold)
    Datadog.increment("quo.query.slow_compile", {
      operation: event.operation.to_s
    })
  end
end

# Alert on slow queries
Quo::Logging.on_slow_query do |event|
  Datadog.increment("quo.query.slow", {
    operation: event.operation.to_s
  })

  if event.duration > 1.second
    PagerDuty.alert("Very slow query: #{event.duration.total_seconds}s", {
      sql: event.sql,
      compile_ms: event.compile_time.total_milliseconds,
      execute_ms: event.execute_time.total_milliseconds
    })
  end
end
```

## Example: Test Helper

```crystal
# spec/support/query_counter.cr
class QueryCounter
  property count : Int32 = 0
  property queries : Array(String) = [] of String

  def initialize
    Quo::Logging.enabled = true
    Quo::Logging.subscribe do |event|
      @count += 1
      @queries << event.sql
    end
  end

  def reset
    @count = 0
    @queries.clear
  end
end

# Usage in specs
describe "User queries" do
  it "executes only 2 queries" do
    counter = QueryCounter.new
    counter.reset

    # Your code that runs queries
    UserService.list_with_orders

    counter.count.should eq(2)
  end
end
```

## Complete Configuration Example

```crystal
module App
  def self.setup_database_logging
    case ENV["CRYSTAL_ENV"]?
    when "development"
      Quo::Logging.log_level = Quo::LogLevel::Debug
      Quo::Logging.slow_query_threshold = 50.milliseconds
      Quo::Logging.slow_compile_threshold = 10.milliseconds

      # Show timing breakdown in development
      Quo::Logging.subscribe do |event|
        if event.slow_compile?(Quo::Logging.slow_compile_threshold)
          puts "⚠️  Slow compile: #{event.sql}"
          puts "   Compile: #{event.compile_time.total_milliseconds}ms"
        end
      end

    when "test"
      Quo::Logging.enabled = false

    when "production"
      Quo::Logging.log_level = Quo::LogLevel::Error
      Quo::Logging.slow_query_threshold = 200.milliseconds
      Quo::Logging.slow_compile_threshold = 50.milliseconds

      Quo::Logging.subscribe do |event|
        # Track all timing metrics
        Metrics.observe("db_query_compile_seconds", event.compile_time.total_seconds)
        Metrics.observe("db_query_execute_seconds", event.execute_time.total_seconds)
        Metrics.observe("db_query_duration_seconds", event.duration.total_seconds)
      end

      Quo::Logging.on_slow_query do |event|
        Logger.warn("Slow query", {
          sql: event.sql,
          compile_ms: event.compile_time.total_milliseconds,
          execute_ms: event.execute_time.total_milliseconds,
          duration_ms: event.duration.total_milliseconds
        })
      end
    end
  end
end
```
