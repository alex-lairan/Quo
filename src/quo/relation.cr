require "./query"
require "./schema"
require "./column_helpers"

module Quo
  # Base class for defining relations with schemas and scopes
  # Each subclass represents a database table with typed columns
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
  abstract class Relation
    include ColumnHelpers

    # Macro to define the schema for this relation
    macro schema(table_name, &block)
      @@table : Symbol = {{table_name}}
      @@schema_definition : Quo::Schema = Quo::Schema.build({{table_name}}) do
        {{block.body}}
      end

      # Register schema in the global registry for cross-table validation
      Quo::SchemaRegistry.register(@@schema_definition)

      def self.table_name : Symbol
        {{table_name}}
      end

      def self.schema_definition : Quo::Schema
        @@schema_definition
      end
    end

    # Macro to define a scope (no arguments)
    macro scope(name, &block)
      def {{name.id}} : self
        query = @query
        new_query = {{block.body}}
        with_query(new_query)
      end

      def self.{{name.id}}(adapter : Quo::Adapters::Adapter) : self
        new(adapter).{{name.id}}
      end
    end

    # Macro to define a scope with arguments
    macro scope(name, *args, &block)
      def {{name.id}}({{args.splat}}) : self
        query = @query
        new_query = {{block.body}}
        with_query(new_query)
      end

      def self.{{name.id}}(adapter : Quo::Adapters::Adapter, {{args.splat}}) : self
        new(adapter).{{name.id}}({{args.map(&.var).splat}})
      end
    end

    # Instance query state
    @query : Query
    @adapter : Adapters::Adapter

    def initialize(@adapter : Adapters::Adapter)
      @query = Query.new(
        self.class.table_name,
        @adapter
      )
    end

    protected def initialize(@adapter : Adapters::Adapter, @query : Query)
    end

    # Get the table name
    def table_name : Symbol
      self.class.table_name
    end

    # Get the schema
    def schema : Schema
      self.class.schema_definition
    end

    # SELECT with column references (supports aliasing)
    # Example: .select(t(:profiles)[:id], t(:organizations)[:name].aliased(:org_name))
    def select(*columns : SelectColumn) : self
      with_query(@query.select(*columns))
    end

    # SELECT - specify columns (with validation)
    def select(**columns) : self
      # Validate all columns exist in their respective tables
      columns.each do |table, cols|
        cols.each do |col|
          SchemaRegistry.validate_column!(table, col)
        end
      end
      with_query(@query.select(**columns))
    end

    # WHERE with hash conditions (with validation and type checking)
    def where(**conditions) : self
      # Validate columns and type check values
      conditions.each do |table, hash|
        hash.each do |column, value|
          SchemaRegistry.validate_column_value!(table, column, value.as(DB::Any))
        end
      end
      with_query(@query.where(**conditions))
    end

    # WHERE with expression block (with validation)
    def where(&block : ExpressionBuilder -> Expression) : self
      builder = ExpressionBuilder.new
      expr = yield builder
      validate_expression!(expr)
      with_query(@query.copy_with(where_clauses: @query.where_clauses + [expr]))
    end

    # JOIN with explicit condition
    # Example: .join(:users, on: {contracts: :user_id, eq: {users: :id}})
    def join(table : Symbol, *, on : NamedTuple, type : JoinType = JoinType::Inner) : self
      with_query(@query.join(table, on: on, type: type))
    end

    # JOIN using association name
    # Example: .join(:user) where :user is defined as belongs_to in schema
    def join(association : Symbol, type : JoinType = JoinType::Inner) : self
      assoc = schema.association(association)
      raise QueryError.new("Unknown association '#{association}' on #{table_name}") unless assoc

      left_table, left_col, right_table, right_col = assoc.join_condition(table_name)
      condition = JoinCondition.new(left_table, left_col, right_table, right_col)
      new_join = Join.new(right_table, condition, type)
      with_query(@query.copy_with(joins: @query.joins + [new_join]))
    end

    # LEFT JOIN with explicit condition
    def left_join(table : Symbol, *, on : NamedTuple) : self
      with_query(@query.left_join(table, on: on))
    end

    # LEFT JOIN using association name
    def left_join(association : Symbol) : self
      join(association, type: JoinType::Left)
    end

    # RIGHT JOIN with explicit condition
    def right_join(table : Symbol, *, on : NamedTuple) : self
      with_query(@query.right_join(table, on: on))
    end

    # RIGHT JOIN using association name
    def right_join(association : Symbol) : self
      join(association, type: JoinType::Right)
    end

    # FULL JOIN with explicit condition
    def full_join(table : Symbol, *, on : NamedTuple) : self
      with_query(@query.full_join(table, on: on))
    end

    # FULL JOIN using association name
    def full_join(association : Symbol) : self
      join(association, type: JoinType::Full)
    end

    # ORDER BY (with validation)
    def order(**columns) : self
      # Validate all columns exist in their respective tables
      columns.each do |table, hash|
        hash.each do |column, _direction|
          SchemaRegistry.validate_column!(table, column)
        end
      end
      with_query(@query.order(**columns))
    end

    # LIMIT
    def limit(n : Int32) : self
      with_query(@query.limit(n))
    end

    # OFFSET
    def offset(n : Int32) : self
      with_query(@query.offset(n))
    end

    # DISTINCT
    def distinct : self
      with_query(@query.distinct)
    end

    # Terminal: get SQL and params
    def to_sql : {String, Array(DB::Any)}
      @query.to_sql
    end

    # Terminal: get COUNT SQL and params
    def count_sql : {String, Array(DB::Any)}
      @query.count_sql
    end

    # Terminal: execute and return hash array
    def to_a : Array(Quo::Row)
      @query.to_a
    end

    # Terminal: execute and map to type
    def to_a(as type : T.class) : Array(T) forall T
      @query.to_a(as: type)
    end

    # Terminal: get first result
    def first : Quo::Row?
      @query.first
    end

    # Terminal: get first result mapped to type
    def first(as type : T.class) : T? forall T
      @query.first(as: type)
    end

    # Terminal: get first result or raise
    def first! : Quo::Row
      @query.first!
    end

    # Terminal: get first result mapped to type or raise
    def first!(as type : T.class) : T forall T
      @query.first!(as: type)
    end

    # Terminal: count rows
    def count : Int64
      @query.count
    end

    # Terminal: check if any rows exist
    def exists? : Bool
      @query.exists?
    end

    # Create a new instance with modified query
    protected def with_query(new_query : Query) : self
      self.class.new(@adapter, new_query)
    end

    # Validate an expression tree, checking all column references
    private def validate_expression!(expr : Expression) : Nil
      case expr
      when ColumnRef
        SchemaRegistry.validate_column!(expr.table, expr.column)
      when Eq, NotEq, Gt, Gte, Lt, Lte
        SchemaRegistry.validate_column_value!(expr.column.table, expr.column.column, expr.value)
      when Like, ILike
        SchemaRegistry.validate_column!(expr.column.table, expr.column.column)
      when In
        SchemaRegistry.validate_column!(expr.column.table, expr.column.column)
        # Type check each value in the IN clause
        expr.values.each do |val|
          SchemaRegistry.validate_column_value!(expr.column.table, expr.column.column, val)
        end
      when Between
        SchemaRegistry.validate_column!(expr.column.table, expr.column.column)
        SchemaRegistry.validate_column_value!(expr.column.table, expr.column.column, expr.min)
        SchemaRegistry.validate_column_value!(expr.column.table, expr.column.column, expr.max)
      when IsNull, IsNotNull
        SchemaRegistry.validate_column!(expr.column.table, expr.column.column)
      when And, Or
        validate_expression!(expr.left)
        validate_expression!(expr.right)
      when Not
        validate_expression!(expr.expression)
      when Raw
        # Raw SQL is not validated
      end
    end
  end
end
