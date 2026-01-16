module Quo
  # Represents a subquery that can be used in WHERE IN, WHERE EXISTS, or FROM
  class Subquery
    getter query : Query
    getter alias_name : Symbol?

    def initialize(@query : Query, @alias_name : Symbol? = nil)
    end

    # Create a subquery with an alias (for use in FROM or JOIN)
    def aliased(name : Symbol) : Subquery
      Subquery.new(@query, name)
    end
  end

  # Expression for WHERE column IN (subquery)
  class InSubquery
    getter column : ColumnRef
    getter subquery : Subquery

    def initialize(@column, @subquery)
    end

    def &(other : Expression) : And
      And.new(self, other)
    end

    def |(other : Expression) : Or
      Or.new(self, other)
    end
  end

  # Expression for WHERE NOT column IN (subquery)
  class NotInSubquery
    getter column : ColumnRef
    getter subquery : Subquery

    def initialize(@column, @subquery)
    end

    def &(other : Expression) : And
      And.new(self, other)
    end

    def |(other : Expression) : Or
      Or.new(self, other)
    end
  end

  # Expression for WHERE EXISTS (subquery)
  class Exists
    getter subquery : Subquery

    def initialize(@subquery)
    end

    def &(other : Expression) : And
      And.new(self, other)
    end

    def |(other : Expression) : Or
      Or.new(self, other)
    end
  end

  # Expression for WHERE NOT EXISTS (subquery)
  class NotExists
    getter subquery : Subquery

    def initialize(@subquery)
    end

    def &(other : Expression) : And
      And.new(self, other)
    end

    def |(other : Expression) : Or
      Or.new(self, other)
    end
  end

  # Scalar subquery for comparisons: WHERE column = (SELECT ...)
  class ScalarSubquery
    getter subquery : Subquery

    def initialize(@subquery)
    end

    # Column = (subquery)
    def ==(column : ColumnRef) : ScalarEq
      ScalarEq.new(column, @subquery)
    end
  end

  # Comparison: column = (scalar subquery)
  class ScalarEq
    getter column : ColumnRef
    getter subquery : Subquery

    def initialize(@column, @subquery)
    end

    def &(other : Expression) : And
      And.new(self, other)
    end

    def |(other : Expression) : Or
      Or.new(self, other)
    end
  end

  # Comparison: column > (scalar subquery)
  class ScalarGt
    getter column : ColumnRef
    getter subquery : Subquery

    def initialize(@column, @subquery)
    end

    def &(other : Expression) : And
      And.new(self, other)
    end

    def |(other : Expression) : Or
      Or.new(self, other)
    end
  end

  # Comparison: column >= (scalar subquery)
  class ScalarGte
    getter column : ColumnRef
    getter subquery : Subquery

    def initialize(@column, @subquery)
    end

    def &(other : Expression) : And
      And.new(self, other)
    end

    def |(other : Expression) : Or
      Or.new(self, other)
    end
  end

  # Comparison: column < (scalar subquery)
  class ScalarLt
    getter column : ColumnRef
    getter subquery : Subquery

    def initialize(@column, @subquery)
    end

    def &(other : Expression) : And
      And.new(self, other)
    end

    def |(other : Expression) : Or
      Or.new(self, other)
    end
  end

  # Comparison: column <= (scalar subquery)
  class ScalarLte
    getter column : ColumnRef
    getter subquery : Subquery

    def initialize(@column, @subquery)
    end

    def &(other : Expression) : And
      And.new(self, other)
    end

    def |(other : Expression) : Or
      Or.new(self, other)
    end
  end
end
