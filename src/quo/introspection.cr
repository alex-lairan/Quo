module Quo
  module Introspection
    # Represents a database column from introspection
    struct IntrospectedColumn
      # Column name
      getter name : String

      # Database data type (e.g., "varchar(255)", "integer", "timestamp")
      getter data_type : String

      # Whether the column allows NULL values
      getter nullable : Bool

      # Default value expression (if any)
      getter default_value : String?

      # Whether this column is part of the primary key
      getter primary_key : Bool

      # Column position in the table (1-based)
      getter ordinal_position : Int32

      def initialize(
        @name : String,
        @data_type : String,
        @nullable : Bool = true,
        @default_value : String? = nil,
        @primary_key : Bool = false,
        @ordinal_position : Int32 = 0
      )
      end

      # Check if column is nullable
      def nullable? : Bool
        @nullable
      end

      # Check if column is primary key
      def primary_key? : Bool
        @primary_key
      end

      # Check if column has a default value
      def has_default? : Bool
        !@default_value.nil?
      end

      # Map database type to Crystal type (best effort)
      def crystal_type : String
        case @data_type.downcase
        when /^(tiny)?int/, /^smallint/
          "Int32"
        when /^(big)?int/, /^integer/
          "Int64"
        when /^decimal/, /^numeric/, /^money/
          "Float64"
        when /^float/, /^real/, /^double/
          "Float64"
        when /^bool/
          "Bool"
        when /^(var)?char/, /^text/, /^string/
          "String"
        when /^uuid/
          "UUID"
        when /^date$/
          "Time"
        when /^time$/
          "Time"
        when /^timestamp/, /^datetime/
          "Time"
        when /^json/, /^jsonb/
          "JSON::Any"
        when /^bytea/, /^blob/, /^binary/
          "Bytes"
        else
          "DB::Any"
        end
      end
    end

    # Represents a database index
    struct IntrospectedIndex
      # Index name
      getter name : String

      # Table the index belongs to
      getter table_name : String

      # Columns in the index (in order)
      getter columns : Array(String)

      # Whether the index enforces uniqueness
      getter unique : Bool

      # Whether this is the primary key index
      getter primary : Bool

      # Index type (btree, hash, gin, etc.)
      getter index_type : String?

      def initialize(
        @name : String,
        @table_name : String,
        @columns : Array(String),
        @unique : Bool = false,
        @primary : Bool = false,
        @index_type : String? = nil
      )
      end

      def unique? : Bool
        @unique
      end

      def primary? : Bool
        @primary
      end

      # Check if this is a single-column index
      def single_column? : Bool
        @columns.size == 1
      end

      # Check if this is a composite index
      def composite? : Bool
        @columns.size > 1
      end
    end

    # Represents a foreign key constraint
    struct ForeignKey
      # Constraint name
      getter name : String

      # Source table
      getter table_name : String

      # Source column
      getter column_name : String

      # Referenced table
      getter referenced_table : String

      # Referenced column
      getter referenced_column : String

      # ON DELETE action
      getter on_delete : String?

      # ON UPDATE action
      getter on_update : String?

      def initialize(
        @name : String,
        @table_name : String,
        @column_name : String,
        @referenced_table : String,
        @referenced_column : String,
        @on_delete : String? = nil,
        @on_update : String? = nil
      )
      end

      # Check if ON DELETE CASCADE
      def cascades_delete? : Bool
        @on_delete.try(&.upcase) == "CASCADE"
      end

      # Check if ON DELETE SET NULL
      def nullifies_on_delete? : Bool
        @on_delete.try(&.upcase) == "SET NULL"
      end
    end

    # Represents complete table information
    struct IntrospectedTable
      # Table name
      getter name : String

      # All columns
      getter columns : Array(IntrospectedColumn)

      # All indexes
      getter indexes : Array(IntrospectedIndex)

      # All foreign keys
      getter foreign_keys : Array(ForeignKey)

      # Primary key column names
      getter primary_key_columns : Array(String)

      def initialize(
        @name : String,
        @columns : Array(IntrospectedColumn) = [] of IntrospectedColumn,
        @indexes : Array(IntrospectedIndex) = [] of IntrospectedIndex,
        @foreign_keys : Array(ForeignKey) = [] of ForeignKey,
        @primary_key_columns : Array(String) = [] of String
      )
      end

      # Get column by name
      def column(name : String) : IntrospectedColumn?
        @columns.find { |c| c.name == name }
      end

      # Check if table has a column
      def has_column?(name : String) : Bool
        @columns.any? { |c| c.name == name }
      end

      # Get index by name
      def index(name : String) : IntrospectedIndex?
        @indexes.find { |i| i.name == name }
      end

      # Get foreign key by name
      def foreign_key(name : String) : ForeignKey?
        @foreign_keys.find { |fk| fk.name == name }
      end

      # Get foreign keys for a specific column
      def foreign_keys_for(column : String) : Array(ForeignKey)
        @foreign_keys.select { |fk| fk.column_name == column }
      end

      # Check if table has a primary key
      def has_primary_key? : Bool
        !@primary_key_columns.empty?
      end

      # Check if primary key is composite
      def composite_primary_key? : Bool
        @primary_key_columns.size > 1
      end

      # Get column names
      def column_names : Array(String)
        @columns.map(&.name)
      end
    end

    # Abstract introspector interface
    # Implementations query database metadata
    abstract class Introspector
      # List all table names
      abstract def tables : Array(String)

      # Get full table information
      abstract def table(name : String) : IntrospectedTable?

      # Get columns for a table
      abstract def columns(table_name : String) : Array(IntrospectedColumn)

      # Get indexes for a table
      abstract def indexes(table_name : String) : Array(IntrospectedIndex)

      # Get foreign keys for a table
      abstract def foreign_keys(table_name : String) : Array(ForeignKey)

      # Check if a table exists
      def table_exists?(name : String) : Bool
        tables.includes?(name)
      end

      # Check if a column exists
      def column_exists?(table_name : String, column_name : String) : Bool
        columns(table_name).any? { |c| c.name == column_name }
      end
    end
  end
end
