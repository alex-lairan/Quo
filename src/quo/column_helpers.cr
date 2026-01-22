module Quo
  # Helper methods for creating column references
  # Include this module to get access to the t() helper
  #
  # Example:
  #   include Quo::ColumnHelpers
  #   t(:users)[:name].aliased(:user_name)
  module ColumnHelpers
    # Helper to create TableRef for column references
    # Example: t(:profiles)[:id] creates ColumnRef.new(:profiles, :id)
    def t(table_name : Symbol) : TableRef
      TableRef.new(table_name)
    end
  end
end
