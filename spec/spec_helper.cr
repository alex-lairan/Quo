require "spec"
require "../src/quo"

# Helper to build a query without database connection
def build_query(table : Symbol) : Quo::Query
  adapter = Quo::Adapters::Test.new
  Quo::Query.new(table, adapter)
end

# Helper to get a test adapter
def test_adapter : Quo::Adapters::Test
  Quo::Adapters::Test.new
end
