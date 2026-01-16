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
  event.duration       # Time::Span - Execution time
  event.operation      # Symbol - :select, :insert, :update, :delete
  event.rows_affected  # Int64? - For mutations
  event.error          # Exception? - If query failed
  event.success?       # Bool - true if no error
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
# Set threshold (default: 100ms)
Quo::Logging.slow_query_threshold = 50.milliseconds

# Subscribe to slow queries
Quo::Logging.on_slow_query do |event|
  puts "SLOW QUERY (#{event.duration.total_milliseconds}ms): #{event.sql}"

  # Alert your monitoring system
  AlertService.notify("Slow query detected", {
    sql: event.sql,
    duration: event.duration.total_milliseconds
  })
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

## Using with Crystal Log

Quo uses Crystal's standard `Log` facility:

```crystal
# Configure Crystal's Log backend
Log.setup(:debug, Log::IOBackend.new(STDOUT))

# Enable Quo logging
Quo::Logging.log_level = Quo::LogLevel::Debug
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

# Metrics for all queries
Quo::Logging.subscribe do |event|
  # Track timing
  Datadog.timing("quo.query.duration", event.duration.total_milliseconds, {
    operation: event.operation.to_s
  })

  # Track errors
  unless event.success?
    Datadog.increment("quo.query.error", {
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
    PagerDuty.alert("Very slow query: #{event.duration.total_seconds}s")
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

    when "test"
      Quo::Logging.enabled = false

    when "production"
      Quo::Logging.log_level = Quo::LogLevel::Error
      Quo::Logging.slow_query_threshold = 200.milliseconds

      Quo::Logging.subscribe do |event|
        Metrics.observe("db_query_duration_seconds", event.duration.total_seconds)
      end

      Quo::Logging.on_slow_query do |event|
        Logger.warn("Slow query", {
          sql: event.sql,
          duration_ms: event.duration.total_milliseconds
        })
      end
    end
  end
end
```
