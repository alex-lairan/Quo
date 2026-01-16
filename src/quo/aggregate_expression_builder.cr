module Quo
  # Builder for aggregate expressions (used in HAVING)
  # Allows fluent DSL: having { count > 5 }
  class AggregateExpressionBuilder
    # COUNT(*) - count all rows
    def count : AggregateRef
      AggregateRef.new(Aggregate.count)
    end

    # COUNT(table.column) - count non-null values in column
    def count(table : Symbol, column : Symbol, *, distinct : Bool = false) : AggregateRef
      AggregateRef.new(Aggregate.count(table, column, distinct: distinct))
    end

    # SUM(table.column)
    def sum(table : Symbol, column : Symbol) : AggregateRef
      AggregateRef.new(Aggregate.sum(table, column))
    end

    # AVG(table.column)
    def avg(table : Symbol, column : Symbol) : AggregateRef
      AggregateRef.new(Aggregate.avg(table, column))
    end

    # MIN(table.column)
    def min(table : Symbol, column : Symbol) : AggregateRef
      AggregateRef.new(Aggregate.min(table, column))
    end

    # MAX(table.column)
    def max(table : Symbol, column : Symbol) : AggregateRef
      AggregateRef.new(Aggregate.max(table, column))
    end
  end

  # Reference to an aggregate that can be compared
  # Allows: count > 5, sum(:orders, :amount) >= 1000
  struct AggregateRef
    getter aggregate : Aggregate

    def initialize(@aggregate)
    end

    # Greater than: COUNT(*) > 5
    def >(value) : AggregateGt
      AggregateGt.new(@aggregate, value.as(DB::Any))
    end

    # Greater than or equal: SUM(amount) >= 1000
    def >=(value) : AggregateGte
      AggregateGte.new(@aggregate, value.as(DB::Any))
    end

    # Less than: AVG(price) < 50
    def <(value) : AggregateLt
      AggregateLt.new(@aggregate, value.as(DB::Any))
    end

    # Less than or equal: MAX(age) <= 65
    def <=(value) : AggregateLte
      AggregateLte.new(@aggregate, value.as(DB::Any))
    end

    # Equal: COUNT(*) = 10
    def ==(value) : AggregateEq
      AggregateEq.new(@aggregate, value.as(DB::Any))
    end

    # Not equal: COUNT(*) != 0
    def !=(value) : AggregateNotEq
      AggregateNotEq.new(@aggregate, value.as(DB::Any))
    end

    # Between: SUM(amount) BETWEEN 100 AND 1000
    def between(min, max) : AggregateBetween
      AggregateBetween.new(@aggregate, min.as(DB::Any), max.as(DB::Any))
    end
  end
end
