module Quo
  # Aggregate function types
  enum AggregateFunction
    Count
    Sum
    Avg
    Min
    Max
  end

  # Represents an aggregate function call in SELECT
  # Example: COUNT(*), SUM(orders.amount), AVG(products.price)
  struct Aggregate
    getter function : AggregateFunction
    getter column : ColumnRef?
    getter alias_name : Symbol?
    getter? distinct : Bool

    def initialize(
      @function : AggregateFunction,
      @column : ColumnRef? = nil,
      @alias_name : Symbol? = nil,
      @distinct : Bool = false
    )
    end

    # COUNT(*) - count all rows
    def self.count(*, as alias_name : Symbol? = nil) : Aggregate
      new(AggregateFunction::Count, nil, alias_name)
    end

    # COUNT(column) - count non-null values
    def self.count(table : Symbol, column : Symbol, *, as alias_name : Symbol? = nil, distinct : Bool = false) : Aggregate
      new(AggregateFunction::Count, ColumnRef.new(table, column), alias_name, distinct)
    end

    # SUM(column)
    def self.sum(table : Symbol, column : Symbol, *, as alias_name : Symbol? = nil) : Aggregate
      new(AggregateFunction::Sum, ColumnRef.new(table, column), alias_name)
    end

    # AVG(column)
    def self.avg(table : Symbol, column : Symbol, *, as alias_name : Symbol? = nil) : Aggregate
      new(AggregateFunction::Avg, ColumnRef.new(table, column), alias_name)
    end

    # MIN(column)
    def self.min(table : Symbol, column : Symbol, *, as alias_name : Symbol? = nil) : Aggregate
      new(AggregateFunction::Min, ColumnRef.new(table, column), alias_name)
    end

    # MAX(column)
    def self.max(table : Symbol, column : Symbol, *, as alias_name : Symbol? = nil) : Aggregate
      new(AggregateFunction::Max, ColumnRef.new(table, column), alias_name)
    end
  end

  # Represents a column in GROUP BY clause
  struct GroupColumn
    getter table : Symbol
    getter column : Symbol

    def initialize(@table, @column)
    end
  end

  # HAVING clause expressions - work on aggregates
  # Example: HAVING COUNT(*) > 5, HAVING SUM(amount) >= 1000

  # Aggregate comparison: aggregate > value
  class AggregateGt
    getter aggregate : Aggregate
    getter value : DB::Any

    def initialize(@aggregate, @value)
    end

    def &(other : HavingExpression) : HavingAnd
      HavingAnd.new(self, other)
    end

    def |(other : HavingExpression) : HavingOr
      HavingOr.new(self, other)
    end
  end

  # Aggregate comparison: aggregate >= value
  class AggregateGte
    getter aggregate : Aggregate
    getter value : DB::Any

    def initialize(@aggregate, @value)
    end

    def &(other : HavingExpression) : HavingAnd
      HavingAnd.new(self, other)
    end

    def |(other : HavingExpression) : HavingOr
      HavingOr.new(self, other)
    end
  end

  # Aggregate comparison: aggregate < value
  class AggregateLt
    getter aggregate : Aggregate
    getter value : DB::Any

    def initialize(@aggregate, @value)
    end

    def &(other : HavingExpression) : HavingAnd
      HavingAnd.new(self, other)
    end

    def |(other : HavingExpression) : HavingOr
      HavingOr.new(self, other)
    end
  end

  # Aggregate comparison: aggregate <= value
  class AggregateLte
    getter aggregate : Aggregate
    getter value : DB::Any

    def initialize(@aggregate, @value)
    end

    def &(other : HavingExpression) : HavingAnd
      HavingAnd.new(self, other)
    end

    def |(other : HavingExpression) : HavingOr
      HavingOr.new(self, other)
    end
  end

  # Aggregate comparison: aggregate = value
  class AggregateEq
    getter aggregate : Aggregate
    getter value : DB::Any

    def initialize(@aggregate, @value)
    end

    def &(other : HavingExpression) : HavingAnd
      HavingAnd.new(self, other)
    end

    def |(other : HavingExpression) : HavingOr
      HavingOr.new(self, other)
    end
  end

  # Aggregate comparison: aggregate != value
  class AggregateNotEq
    getter aggregate : Aggregate
    getter value : DB::Any

    def initialize(@aggregate, @value)
    end

    def &(other : HavingExpression) : HavingAnd
      HavingAnd.new(self, other)
    end

    def |(other : HavingExpression) : HavingOr
      HavingOr.new(self, other)
    end
  end

  # Aggregate range: aggregate BETWEEN min AND max
  class AggregateBetween
    getter aggregate : Aggregate
    getter min : DB::Any
    getter max : DB::Any

    def initialize(@aggregate, @min, @max)
    end

    def &(other : HavingExpression) : HavingAnd
      HavingAnd.new(self, other)
    end

    def |(other : HavingExpression) : HavingOr
      HavingOr.new(self, other)
    end
  end

  # Logical AND for HAVING
  class HavingAnd
    getter left : HavingExpression
    getter right : HavingExpression

    def initialize(@left, @right)
    end

    def &(other : HavingExpression) : HavingAnd
      HavingAnd.new(self, other)
    end

    def |(other : HavingExpression) : HavingOr
      HavingOr.new(self, other)
    end
  end

  # Logical OR for HAVING
  class HavingOr
    getter left : HavingExpression
    getter right : HavingExpression

    def initialize(@left, @right)
    end

    def &(other : HavingExpression) : HavingAnd
      HavingAnd.new(self, other)
    end

    def |(other : HavingExpression) : HavingOr
      HavingOr.new(self, other)
    end
  end

  # Union type for all HAVING expressions
  alias HavingExpression = AggregateGt | AggregateGte | AggregateLt | AggregateLte | AggregateEq | AggregateNotEq | AggregateBetween | HavingAnd | HavingOr
end
