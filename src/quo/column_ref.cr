module Quo
  # Forward declaration for AliasedColumn
  struct AliasedColumn; end

  # Intermediate object for table[:column] syntax
  # Example: t(:profiles)[:id] returns ColumnRef.new(:profiles, :id)
  struct TableRef
    getter table : Symbol

    def initialize(@table)
    end

    # Access a column on this table
    def [](column : Symbol) : ColumnRef
      ColumnRef.new(@table, column)
    end
  end

  # Table-qualified column reference
  # Represents a column in the form table[:column]
  # Example: contracts[:status] creates ColumnRef.new(:contracts, :status)
  struct ColumnRef
    getter table : Symbol
    getter column : Symbol

    def initialize(@table, @column)
    end

    # Create an aliased column: table[:column].aliased(:alias)
    # Example: organizations[:name].aliased(:org_name)
    # Produces: "organizations"."name" AS "org_name"
    def aliased(alias_name : Symbol) : AliasedColumn
      AliasedColumn.new(self, alias_name)
    end

    # Equality comparison: column = value
    def ==(value) : Eq
      Eq.new(self, value.as(Quo::Value))
    end

    # Inequality comparison: column != value
    def !=(value) : NotEq
      NotEq.new(self, value.as(Quo::Value))
    end

    # Greater than: column > value
    def >(value) : Gt
      Gt.new(self, value.as(Quo::Value))
    end

    # Greater than or equal: column >= value
    def >=(value) : Gte
      Gte.new(self, value.as(Quo::Value))
    end

    # Less than: column < value
    def <(value) : Lt
      Lt.new(self, value.as(Quo::Value))
    end

    # Less than or equal: column <= value
    def <=(value) : Lte
      Lte.new(self, value.as(Quo::Value))
    end

    # Pattern matching: column LIKE pattern
    def like(pattern : String) : Like
      Like.new(self, pattern)
    end

    # Case-insensitive pattern matching: column ILIKE pattern
    def ilike(pattern : String) : ILike
      ILike.new(self, pattern)
    end

    # Set membership: column IN (values)
    def in(values : Array) : In
      In.new(self, values.map { |v| v.as(Quo::Value) })
    end

    # Range check: column BETWEEN min AND max
    def between(min, max) : Between
      Between.new(self, min.as(Quo::Value), max.as(Quo::Value))
    end

    # Null check: column IS NULL
    def is_null : IsNull
      IsNull.new(self)
    end

    # Not null check: column IS NOT NULL
    def is_not_null : IsNotNull
      IsNotNull.new(self)
    end

    # Subquery membership: column IN (SELECT ...)
    def in(subquery : Subquery) : InSubquery
      InSubquery.new(self, subquery)
    end

    # Subquery membership from Query
    def in(query : Query) : InSubquery
      InSubquery.new(self, Subquery.new(query))
    end

    # Negated subquery membership: column NOT IN (SELECT ...)
    def not_in(subquery : Subquery) : NotInSubquery
      NotInSubquery.new(self, subquery)
    end

    # Negated subquery membership from Query
    def not_in(query : Query) : NotInSubquery
      NotInSubquery.new(self, Subquery.new(query))
    end

    # Scalar subquery comparison: column = (SELECT ...)
    def eq_subquery(subquery : Subquery) : ScalarEq
      ScalarEq.new(self, subquery)
    end

    def eq_subquery(query : Query) : ScalarEq
      ScalarEq.new(self, Subquery.new(query))
    end

    # Scalar subquery comparison: column > (SELECT ...)
    def gt_subquery(subquery : Subquery) : ScalarGt
      ScalarGt.new(self, subquery)
    end

    def gt_subquery(query : Query) : ScalarGt
      ScalarGt.new(self, Subquery.new(query))
    end

    # Scalar subquery comparison: column >= (SELECT ...)
    def gte_subquery(subquery : Subquery) : ScalarGte
      ScalarGte.new(self, subquery)
    end

    def gte_subquery(query : Query) : ScalarGte
      ScalarGte.new(self, Subquery.new(query))
    end

    # Scalar subquery comparison: column < (SELECT ...)
    def lt_subquery(subquery : Subquery) : ScalarLt
      ScalarLt.new(self, subquery)
    end

    def lt_subquery(query : Query) : ScalarLt
      ScalarLt.new(self, Subquery.new(query))
    end

    # Scalar subquery comparison: column <= (SELECT ...)
    def lte_subquery(subquery : Subquery) : ScalarLte
      ScalarLte.new(self, subquery)
    end

    def lte_subquery(query : Query) : ScalarLte
      ScalarLte.new(self, Subquery.new(query))
    end

    # Logical AND - combines with another expression
    def &(other : Expression) : And
      And.new(self, other)
    end

    # Logical OR - combines with another expression
    def |(other : Expression) : Or
      Or.new(self, other)
    end
  end

  # Aliased column reference
  # Represents a column with an alias: table[:column].as(:alias)
  # Example: organizations[:name].as(:org_name)
  # Produces SQL: "organizations"."name" AS "org_name"
  struct AliasedColumn
    getter column : ColumnRef
    getter alias_name : Symbol

    def initialize(@column, @alias_name)
    end

    # Delegate table/column access for convenience
    def table : Symbol
      @column.table
    end

    def original_column : Symbol
      @column.column
    end
  end

  # Union type for SELECT columns - can be plain or aliased
  alias SelectColumn = ColumnRef | AliasedColumn
end
