module Quo
  # Types of SQL set operations
  enum SetOperationType
    Union
    UnionAll
    Intersect
    IntersectAll
    Except
    ExceptAll
  end

  # Represents a set operation (UNION, INTERSECT, EXCEPT) between queries
  struct SetOperation
    getter operation_type : SetOperationType
    getter query : Query

    def initialize(@operation_type, @query)
    end
  end
end
