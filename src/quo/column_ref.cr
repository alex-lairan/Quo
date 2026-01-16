module Quo
  # Table-qualified column reference
  # Represents a column in the form table[:column]
  # Example: contracts[:status] creates ColumnRef.new(:contracts, :status)
  struct ColumnRef
    getter table : Symbol
    getter column : Symbol

    def initialize(@table, @column)
    end

    # Equality comparison: column = value
    def ==(value) : Eq
      Eq.new(self, value.as(DB::Any))
    end

    # Inequality comparison: column != value
    def !=(value) : NotEq
      NotEq.new(self, value.as(DB::Any))
    end

    # Greater than: column > value
    def >(value) : Gt
      Gt.new(self, value.as(DB::Any))
    end

    # Greater than or equal: column >= value
    def >=(value) : Gte
      Gte.new(self, value.as(DB::Any))
    end

    # Less than: column < value
    def <(value) : Lt
      Lt.new(self, value.as(DB::Any))
    end

    # Less than or equal: column <= value
    def <=(value) : Lte
      Lte.new(self, value.as(DB::Any))
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
      In.new(self, values.map { |v| v.as(DB::Any) })
    end

    # Range check: column BETWEEN min AND max
    def between(min, max) : Between
      Between.new(self, min.as(DB::Any), max.as(DB::Any))
    end

    # Null check: column IS NULL
    def is_null : IsNull
      IsNull.new(self)
    end

    # Not null check: column IS NOT NULL
    def is_not_null : IsNotNull
      IsNotNull.new(self)
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
end
