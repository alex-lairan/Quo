# Logging API

`Quo::Logging` provides query logging and instrumentation.

## Module Methods

### enabled=

```crystal
def self.enabled=(value : Bool)
```

Enable or disable logging.

```crystal
Quo::Logging.enabled = true
Quo::Logging.enabled = false
```

---

### enabled?

```crystal
def self.enabled? : Bool
```

Check if logging is enabled.

```crystal
if Quo::Logging.enabled?
  puts "Logging is on"
end
```

---

### log_level=

```crystal
def self.log_level=(level : LogLevel)
```

Set the log level. Also enables logging if level is not `None`.

```crystal
Quo::Logging.log_level = Quo::LogLevel::Debug
Quo::Logging.log_level = Quo::LogLevel::Info
Quo::Logging.log_level = Quo::LogLevel::None  # Disables
```

---

### log_level

```crystal
def self.log_level : LogLevel
```

Get current log level.

---

### slow_query_threshold=

```crystal
def self.slow_query_threshold=(threshold : Time::Span)
```

Set the threshold for slow query detection.

```crystal
Quo::Logging.slow_query_threshold = 100.milliseconds
Quo::Logging.slow_query_threshold = 1.second
```

---

### slow_query_threshold

```crystal
def self.slow_query_threshold : Time::Span
```

Get current slow query threshold. Default: 100ms.

---

### subscribe

```crystal
def self.subscribe(&block : QuerySubscriber)
```

Subscribe to receive all query events.

```crystal
Quo::Logging.subscribe do |event|
  puts "SQL: #{event.sql}"
  puts "Duration: #{event.duration.total_milliseconds}ms"
end
```

---

### on_slow_query

```crystal
def self.on_slow_query(&block : QuerySubscriber)
```

Subscribe to receive only slow query events.

```crystal
Quo::Logging.on_slow_query do |event|
  AlertService.notify("Slow query: #{event.sql}")
end
```

---

### clear_subscribers

```crystal
def self.clear_subscribers
```

Remove all subscribers (regular and slow query).

```crystal
Quo::Logging.clear_subscribers
```

---

### log

```crystal
def self.log(event : QueryEvent)
```

Manually log a query event. Called internally by the adapter.

---

### instrument

```crystal
def self.instrument(sql : String, params : Array(DB::Any), operation : Symbol, &block)
```

Wrap a block and log its execution. Returns the block's return value.

```crystal
result = Quo::Logging.instrument("SELECT 1", [] of DB::Any, :select) do
  # Execute query
  42
end
```

---

## LogLevel Enum

```crystal
enum Quo::LogLevel
  Debug   # All queries with full details
  Info    # All queries
  Warn    # Only warnings
  Error   # Only errors
  None    # Disabled (default)
end
```

## QueryEvent Struct

Query events contain information about executed queries.

### Properties

```crystal
struct Quo::QueryEvent
  getter sql : String              # The SQL query
  getter params : Array(DB::Any)   # Query parameters
  getter duration : Time::Span     # Execution time
  getter operation : Symbol        # :select, :insert, :update, :delete
  getter rows_affected : Int64?    # For mutations
  getter error : Exception?        # If query failed
end
```

### Methods

#### success?

```crystal
def success? : Bool
```

Returns `true` if query completed without error.

```crystal
Quo::Logging.subscribe do |event|
  unless event.success?
    ErrorTracker.capture(event.error.not_nil!)
  end
end
```

---

#### slow?

```crystal
def slow?(threshold : Time::Span) : Bool
```

Returns `true` if query duration exceeds threshold.

```crystal
Quo::Logging.subscribe do |event|
  if event.slow?(50.milliseconds)
    puts "Slow: #{event.sql}"
  end
end
```

---

## Type Aliases

```crystal
# Subscriber callback type
alias Quo::QuerySubscriber = QueryEvent ->
```

## Complete Example

```crystal
# Configure logging
Quo::Logging.log_level = Quo::LogLevel::Info
Quo::Logging.slow_query_threshold = 100.milliseconds

# Metrics collection
Quo::Logging.subscribe do |event|
  StatsD.timing("database.query", event.duration.total_milliseconds)
  StatsD.increment("database.#{event.operation}")

  unless event.success?
    StatsD.increment("database.error")
  end
end

# Slow query alerting
Quo::Logging.on_slow_query do |event|
  Logger.warn("Slow query", {
    sql: event.sql,
    duration_ms: event.duration.total_milliseconds
  })

  if event.duration > 5.seconds
    PagerDuty.alert("Critical slow query detected")
  end
end
```
