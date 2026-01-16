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
    def initialize(table : Symbol, column : Symbol)
      super("Column '#{column}' does not exist in table '#{table}'")
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
end
