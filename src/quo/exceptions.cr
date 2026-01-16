module Quo
  # Base exception for all Quo errors
  class Error < Exception
  end

  # Raised when a record is not found
  class RecordNotFound < Error
    def initialize(table : Symbol)
      super("Record not found in #{table}")
    end
  end

  # Raised when schema validation fails
  class SchemaError < Error
  end

  # Raised when an invalid column is referenced
  class InvalidColumnError < SchemaError
    def initialize(message : String)
      super(message)
    end

    def initialize(table : Symbol, column : Symbol)
      super("Column '#{column}' does not exist in table '#{table}'")
    end
  end

  # Raised when a value type doesn't match the column type
  class TypeError < SchemaError
    def initialize(message : String)
      super(message)
    end
  end

  # Raised when query building fails
  class QueryError < Error
  end

  # Raised when an unsupported expression type is encountered
  class UnsupportedExpressionError < Error
    def initialize(expression_class : String)
      super("Unsupported expression type: #{expression_class}")
    end
  end

  # Raised when adapter operations fail
  class AdapterError < Error
  end

  # Raised when a database connection fails
  class ConnectionError < Error
    def initialize(message : String = "Database connection failed")
      super(message)
    end
  end

  # Raised when connection pool checkout times out
  class PoolTimeoutError < Error
    def initialize(timeout : Time::Span)
      super("Connection checkout timed out after #{timeout}")
    end

    def initialize(message : String)
      super(message)
    end
  end

  # Raised when database routing fails (primary/replica)
  class RoutingError < Error
    def initialize(message : String = "Database routing failed")
      super(message)
    end
  end

  # Raised when sharding operations fail
  class ShardingError < Error
    def initialize(message : String = "Sharding operation failed")
      super(message)
    end

    def initialize(shard_name : Symbol)
      super("Shard '#{shard_name}' not found")
    end
  end

  # Raised when cache operations fail
  class CacheError < Error
    def initialize(message : String = "Cache operation failed")
      super(message)
    end
  end
end
