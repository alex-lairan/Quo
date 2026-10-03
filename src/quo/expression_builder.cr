module Quo
  # Provides DSL for building expressions in blocks
  # Used in .where { contracts[:status] == "active" }
  struct ExpressionBuilder
    # Access a table to get columns via table[:column]
    # Example: contracts[:status] returns ColumnRef.new(:contracts, :status)
    def [](table : Symbol) : TableRef
      TableRef.new(table)
    end

    # Create a raw SQL expression
    # Example: raw("NOW()") or raw("$1::uuid", some_value)
    def raw(sql : String, *params) : Raw
      Raw.new(sql, params.to_a.map { |p| p.as(Quo::Value) })
    end

    # Create a NOT expression
    # Example: not(contracts[:status] == "deleted")
    def not(expr : Expression) : Not
      Not.new(expr)
    end

    # Create an EXISTS expression
    # Example: exists(subquery)
    def exists(subquery : Subquery) : Exists
      Exists.new(subquery)
    end

    def exists(query : Query) : Exists
      Exists.new(Subquery.new(query))
    end

    # Create a NOT EXISTS expression
    # Example: not_exists(subquery)
    def not_exists(subquery : Subquery) : NotExists
      NotExists.new(subquery)
    end

    def not_exists(query : Query) : NotExists
      NotExists.new(Subquery.new(query))
    end
  end

  # Intermediate object for table[:column] syntax
  # Example: contracts[:status] where contracts is TableRef
  struct TableRef
    getter table : Symbol

    def initialize(@table)
    end

    # Access a column on this table
    # Returns a ColumnRef that can be used with comparison operators
    def [](column : Symbol) : ColumnRef
      ColumnRef.new(@table, column)
    end
  end
end
