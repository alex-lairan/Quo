require "db"

# Quo - A ROM-rb inspired query builder for Crystal
#
# Features:
# - Explicit, unambiguous syntax - all columns are table-qualified
# - Immutable queries - each method returns a new query
# - Relations - schema definition with typed columns and composable scopes
# - Database agnostic - Postgres first, MySQL/SQLite later
#
# Example:
#   class ContractsRelation < Quo::Relation
#     schema :contracts do
#       primary_key :id, UUID
#       column :reference, String
#       column :status, String
#     end
#
#     scope :active do
#       where(contracts: {status: "active"})
#     end
#   end
#
#   relation = ContractsRelation.new(adapter)
#   relation.active.where { contracts[:amount] >= 1000 }.to_sql

module Quo
  VERSION = "0.1.0"
end

require "./quo/exceptions"
require "./quo/column_ref"
require "./quo/expression"
require "./quo/expression_builder"
require "./quo/adapters/adapter"
require "./quo/adapters/postgres"
require "./quo/adapters/sqlite"
require "./quo/adapters/test"
require "./quo/query"
require "./quo/schema"
require "./quo/relation"
