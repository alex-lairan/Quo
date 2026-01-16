# Quo::Value - Union type for all supported database values
#
# This type automatically includes rich types from loaded database shards:
# - PostgreSQL: UUID, PG::Numeric, PG::Geo::*, Arrays, etc.
# - SQLite: Basic DB::Any types
#
# Usage:
#   row = query.first!
#   row["id"]        # => Quo::Value (can be Int64, UUID, etc.)
#   row["id"].as(Int64)  # => Int64
#   row["uuid"].as(UUID) # => UUID (when using PG)

module Quo
  # Build the Value type based on which database shards are loaded
  {% begin %}
    {% pg_loaded = @top_level.has_constant?("PG") %}

    {% if pg_loaded %}
      # PostgreSQL types - includes all PG-specific types
      alias Value = Bool |
                    Char |
                    Int16 |
                    Int32 |
                    Int64 |
                    UInt32 |
                    UInt64 |
                    Float32 |
                    Float64 |
                    String |
                    Slice(UInt8) |
                    Time |
                    PG::Numeric |
                    PG::Interval |
                    UUID |
                    JSON::PullParser |
                    PG::Geo::Point |
                    PG::Geo::Line |
                    PG::Geo::LineSegment |
                    PG::Geo::Box |
                    PG::Geo::Path |
                    PG::Geo::Polygon |
                    PG::Geo::Circle |
                    Array(PG::BoolArray) |
                    Array(PG::CharArray) |
                    Array(PG::Int16Array) |
                    Array(PG::Int32Array) |
                    Array(PG::Int64Array) |
                    Array(PG::Float32Array) |
                    Array(PG::Float64Array) |
                    Array(PG::StringArray) |
                    Array(PG::NumericArray) |
                    Array(PG::TimeArray) |
                    Array(PG::UUIDArray) |
                    Nil
    {% else %}
      # Basic types only (SQLite, or no database shard loaded)
      alias Value = DB::Any
    {% end %}
  {% end %}

  # Result row type
  alias Row = Hash(String, Value)

  # Result set type
  alias ResultSet = Array(Row)
end
