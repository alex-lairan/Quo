module Quo
  # Alias for database value types - using classes instead of structs to allow recursion
  alias Expression = ColumnRef | Eq | NotEq | Gt | Gte | Lt | Lte | Like | ILike | In | Between | IsNull | IsNotNull | And | Or | Not | Raw

  # Comparison expression: column = value
  class Eq
    getter column : ColumnRef
    getter value : DB::Any

    def initialize(@column, @value)
    end

    # Logical AND - combines two expressions
    def &(other : Expression) : And
      And.new(self, other)
    end

    # Logical OR - combines two expressions
    def |(other : Expression) : Or
      Or.new(self, other)
    end
  end

  # Comparison expression: column != value
  class NotEq
    getter column : ColumnRef
    getter value : DB::Any

    def initialize(@column, @value)
    end

    def &(other : Expression) : And
      And.new(self, other)
    end

    def |(other : Expression) : Or
      Or.new(self, other)
    end
  end

  # Comparison expression: column > value
  class Gt
    getter column : ColumnRef
    getter value : DB::Any

    def initialize(@column, @value)
    end

    def &(other : Expression) : And
      And.new(self, other)
    end

    def |(other : Expression) : Or
      Or.new(self, other)
    end
  end

  # Comparison expression: column >= value
  class Gte
    getter column : ColumnRef
    getter value : DB::Any

    def initialize(@column, @value)
    end

    def &(other : Expression) : And
      And.new(self, other)
    end

    def |(other : Expression) : Or
      Or.new(self, other)
    end
  end

  # Comparison expression: column < value
  class Lt
    getter column : ColumnRef
    getter value : DB::Any

    def initialize(@column, @value)
    end

    def &(other : Expression) : And
      And.new(self, other)
    end

    def |(other : Expression) : Or
      Or.new(self, other)
    end
  end

  # Comparison expression: column <= value
  class Lte
    getter column : ColumnRef
    getter value : DB::Any

    def initialize(@column, @value)
    end

    def &(other : Expression) : And
      And.new(self, other)
    end

    def |(other : Expression) : Or
      Or.new(self, other)
    end
  end

  # Pattern matching: column LIKE pattern
  class Like
    getter column : ColumnRef
    getter pattern : String

    def initialize(@column, @pattern)
    end

    def &(other : Expression) : And
      And.new(self, other)
    end

    def |(other : Expression) : Or
      Or.new(self, other)
    end
  end

  # Case-insensitive pattern matching: column ILIKE pattern (Postgres)
  class ILike
    getter column : ColumnRef
    getter pattern : String

    def initialize(@column, @pattern)
    end

    def &(other : Expression) : And
      And.new(self, other)
    end

    def |(other : Expression) : Or
      Or.new(self, other)
    end
  end

  # Set membership: column IN (values)
  class In
    getter column : ColumnRef
    getter values : Array(DB::Any)

    def initialize(@column, @values)
    end

    def &(other : Expression) : And
      And.new(self, other)
    end

    def |(other : Expression) : Or
      Or.new(self, other)
    end
  end

  # Range check: column BETWEEN min AND max
  class Between
    getter column : ColumnRef
    getter min : DB::Any
    getter max : DB::Any

    def initialize(@column, @min, @max)
    end

    def &(other : Expression) : And
      And.new(self, other)
    end

    def |(other : Expression) : Or
      Or.new(self, other)
    end
  end

  # Null check: column IS NULL
  class IsNull
    getter column : ColumnRef

    def initialize(@column)
    end

    def &(other : Expression) : And
      And.new(self, other)
    end

    def |(other : Expression) : Or
      Or.new(self, other)
    end
  end

  # Not null check: column IS NOT NULL
  class IsNotNull
    getter column : ColumnRef

    def initialize(@column)
    end

    def &(other : Expression) : And
      And.new(self, other)
    end

    def |(other : Expression) : Or
      Or.new(self, other)
    end
  end

  # Logical AND: left AND right
  class And
    getter left : Expression
    getter right : Expression

    def initialize(@left, @right)
    end

    def &(other : Expression) : And
      And.new(self, other)
    end

    def |(other : Expression) : Or
      Or.new(self, other)
    end
  end

  # Logical OR: left OR right
  class Or
    getter left : Expression
    getter right : Expression

    def initialize(@left, @right)
    end

    def &(other : Expression) : And
      And.new(self, other)
    end

    def |(other : Expression) : Or
      Or.new(self, other)
    end
  end

  # Logical NOT: NOT expression
  class Not
    getter expression : Expression

    def initialize(@expression)
    end

    def &(other : Expression) : And
      And.new(self, other)
    end

    def |(other : Expression) : Or
      Or.new(self, other)
    end
  end

  # Raw SQL escape hatch
  class Raw
    getter sql : String
    getter params : Array(DB::Any)

    def initialize(@sql, @params = [] of DB::Any)
    end

    def &(other : Expression) : And
      And.new(self, other)
    end

    def |(other : Expression) : Or
      Or.new(self, other)
    end
  end

  # Helper to create NOT expression
  def self.not(expr : Expression) : Not
    Not.new(expr)
  end
end
