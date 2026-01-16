module Quo
  # Global registry of all schemas, indexed by table name
  # Allows validation of columns across tables (including joined tables)
  module SchemaRegistry
    @@schemas = {} of Symbol => Schema

    # Register a schema for a table
    def self.register(schema : Schema) : Nil
      @@schemas[schema.table_name] = schema
    end

    # Get a schema by table name
    def self.get(table_name : Symbol) : Schema?
      @@schemas[table_name]?
    end

    # Get a schema by table name, raising if not found
    def self.get!(table_name : Symbol) : Schema
      @@schemas[table_name]? || raise SchemaError.new("No schema registered for table '#{table_name}'")
    end

    # Check if a schema is registered for a table
    def self.registered?(table_name : Symbol) : Bool
      @@schemas.has_key?(table_name)
    end

    # Validate that a column exists in a table's schema
    def self.validate_column!(table_name : Symbol, column_name : Symbol) : Nil
      schema = get(table_name)
      return unless schema # Skip validation if schema not registered (allows explicit joins to unregistered tables)

      unless schema.has_column?(column_name)
        available = schema.column_names.map(&.to_s).join(", ")
        raise InvalidColumnError.new(
          "Column '#{column_name}' does not exist in table '#{table_name}'. " \
          "Available columns: #{available}"
        )
      end
    end

    # Validate column and check type compatibility
    def self.validate_column_value!(table_name : Symbol, column_name : Symbol, value : DB::Any) : Nil
      schema = get(table_name)
      return unless schema # Skip validation if schema not registered

      column = schema.column(column_name)
      unless column
        available = schema.column_names.map(&.to_s).join(", ")
        raise InvalidColumnError.new(
          "Column '#{column_name}' does not exist in table '#{table_name}'. " \
          "Available columns: #{available}"
        )
      end

      # Type check the value against the column type
      validate_type!(table_name, column, value)
    end

    # Validate that a value is compatible with a column's type
    private def self.validate_type!(table_name : Symbol, column : Column, value : DB::Any) : Nil
      return if value.nil? && column.nullable?

      expected_type = column.type_name
      actual_type = value.class.name

      compatible = case expected_type
                   when "String"
                     value.is_a?(String)
                   when "Int32"
                     value.is_a?(Int32) || value.is_a?(Int64)
                   when "Int64"
                     value.is_a?(Int32) || value.is_a?(Int64)
                   when "Float64"
                     value.is_a?(Float64) || value.is_a?(Float32) || value.is_a?(Int32) || value.is_a?(Int64)
                   when "Bool"
                     value.is_a?(Bool)
                   when "Time"
                     value.is_a?(Time)
                   when "UUID"
                     value.is_a?(String) # UUIDs are typically passed as strings
                   else
                     true # Unknown types pass validation
                   end

      unless compatible
        raise TypeError.new(
          "Type mismatch for column '#{column.name}' in table '#{table_name}': " \
          "expected #{expected_type}, got #{actual_type}"
        )
      end
    end

    # Clear all registered schemas (useful for testing)
    def self.clear! : Nil
      @@schemas.clear
    end

    # List all registered table names (for debugging)
    def self.tables : Array(Symbol)
      @@schemas.keys
    end
  end
end
