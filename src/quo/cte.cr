module Quo
  # Represents a Common Table Expression (CTE)
  # Example: WITH active_users AS (SELECT * FROM users WHERE active = true)
  struct CTE
    getter name : Symbol
    getter query : Query
    getter? recursive : Bool

    def initialize(@name, @query, @recursive = false)
    end
  end
end
