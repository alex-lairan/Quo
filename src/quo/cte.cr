module Quo
  # Represents a Common Table Expression (CTE)
  # Example: WITH active_users AS (SELECT * FROM users WHERE active = true)
  #
  # For recursive CTEs, use base_query and recursive_query:
  # Example: WITH RECURSIVE tree AS (
  #            SELECT ... FROM table WHERE parent_id IS NULL  -- base case
  #            UNION ALL
  #            SELECT ... FROM table JOIN tree ON ...         -- recursive case
  #          )
  struct CTE
    getter name : Symbol
    getter query : Query?
    getter base_query : Query?
    getter recursive_query : Query?
    getter? recursive : Bool

    # Standard CTE
    def initialize(@name, @query : Query, @recursive = false)
      @base_query = nil
      @recursive_query = nil
    end

    # Recursive CTE with base and recursive parts
    def initialize(@name, *, base @base_query : Query, recursive @recursive_query : Query)
      @query = nil
      @recursive = true
    end

    # Check if this is a two-part recursive CTE
    def two_part_recursive?
      @base_query && @recursive_query
    end
  end
end
