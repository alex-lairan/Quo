require "./expression"
require "./expression_builder"
require "./column_ref"

module Quo
  # Join types supported in SQL
  enum JoinType
    Inner
    Left
    Right
    Full
  end

  # Represents a JOIN condition: left_table.left_column = right_table.right_column
  struct JoinCondition
    getter left_table : Symbol
    getter left_column : Symbol
    getter right_table : Symbol
    getter right_column : Symbol

    def initialize(@left_table, @left_column, @right_table, @right_column)
    end
  end

  # Represents a JOIN clause in a query
  struct Join
    getter table : Symbol
    getter condition : JoinCondition
    getter type : JoinType

    def initialize(@table, @condition, @type = JoinType::Inner)
    end
  end

  # Represents an ORDER BY clause
  struct OrderClause
    getter table : Symbol
    getter column : Symbol
    getter direction : Symbol # :asc or :desc

    def initialize(@table, @column, @direction = :asc)
    end
  end

  # Immutable query builder
  # Each method returns a new Query instance, leaving the original unchanged
  class Query
    getter table : Symbol
    getter select_columns : Array(ColumnRef)
    getter where_clauses : Array(Expression)
    getter joins : Array(Join)
    getter order_clauses : Array(OrderClause)
    getter limit_value : Int32?
    getter offset_value : Int32?
    getter? distinct_enabled : Bool

    # Forward declaration for adapter - will be defined in adapters/
    @adapter : Adapters::Adapter

    def initialize(
      @table : Symbol,
      @adapter : Adapters::Adapter,
      @select_columns : Array(ColumnRef) = [] of ColumnRef,
      @where_clauses : Array(Expression) = [] of Expression,
      @joins : Array(Join) = [] of Join,
      @order_clauses : Array(OrderClause) = [] of OrderClause,
      @limit_value : Int32? = nil,
      @offset_value : Int32? = nil,
      @distinct_enabled : Bool = false
    )
    end

    # SELECT - specify columns with table qualification
    # Example: .select(contracts: [:id, :reference], users: [:name])
    def select(**columns) : Query
      new_columns = [] of ColumnRef
      columns.each do |table, cols|
        cols.each do |col|
          new_columns << ColumnRef.new(table, col)
        end
      end
      copy_with(select_columns: @select_columns + new_columns)
    end

    # WHERE with hash - table-qualified conditions
    # Example: .where(contracts: {status: "active", user_id: id})
    def where(**conditions) : Query
      new_clauses = [] of Expression
      conditions.each do |table, hash|
        hash.each do |column, value|
          col_ref = ColumnRef.new(table, column)
          new_clauses << Eq.new(col_ref, value.as(DB::Any))
        end
      end
      copy_with(where_clauses: @where_clauses + new_clauses)
    end

    # WHERE with expression block
    # Example: .where { contracts[:amount] >= 1000 }
    def where(&block : ExpressionBuilder -> Expression) : Query
      builder = ExpressionBuilder.new
      expr = yield builder
      copy_with(where_clauses: @where_clauses + [expr])
    end

    # JOIN - add a join clause
    # Example: .join(:users, on: {contracts: :user_id, eq: {users: :id}})
    def join(join_table : Symbol, *, on : NamedTuple, type : JoinType = JoinType::Inner) : Query
      condition = parse_join_condition(on)
      new_join = Join.new(join_table, condition, type)
      copy_with(joins: @joins + [new_join])
    end

    # LEFT JOIN shorthand
    def left_join(join_table : Symbol, *, on : NamedTuple) : Query
      join(join_table, on: on, type: JoinType::Left)
    end

    # RIGHT JOIN shorthand
    def right_join(join_table : Symbol, *, on : NamedTuple) : Query
      join(join_table, on: on, type: JoinType::Right)
    end

    # FULL JOIN shorthand
    def full_join(join_table : Symbol, *, on : NamedTuple) : Query
      join(join_table, on: on, type: JoinType::Full)
    end

    # ORDER BY - specify ordering with table qualification
    # Example: .order(contracts: {created_at: :desc, name: :asc})
    def order(**columns) : Query
      new_clauses = [] of OrderClause
      columns.each do |table, hash|
        hash.each do |column, direction|
          new_clauses << OrderClause.new(table, column, direction)
        end
      end
      copy_with(order_clauses: @order_clauses + new_clauses)
    end

    # LIMIT - set maximum rows
    def limit(n : Int32) : Query
      copy_with(limit_value: n)
    end

    # OFFSET - skip rows
    def offset(n : Int32) : Query
      copy_with(offset_value: n)
    end

    # DISTINCT - eliminate duplicate rows
    def distinct : Query
      copy_with(distinct_enabled: true)
    end

    # Merge another query's conditions into this one
    def merge(other : Query) : Query
      copy_with(
        select_columns: @select_columns + other.select_columns,
        where_clauses: @where_clauses + other.where_clauses,
        joins: @joins + other.joins,
        order_clauses: @order_clauses + other.order_clauses,
        limit_value: other.limit_value || @limit_value,
        offset_value: other.offset_value || @offset_value,
        distinct_enabled: @distinct_enabled || other.distinct_enabled?
      )
    end

    # Generate SQL and parameters tuple
    def to_sql : {String, Array(DB::Any)}
      @adapter.compile(self)
    end

    # Generate COUNT SQL
    def count_sql : {String, Array(DB::Any)}
      @adapter.compile_count(self)
    end

    # Execute query and return array of hashes
    def to_a : Array(Hash(String, DB::Any))
      sql, params = to_sql
      @adapter.execute(sql, params)
    end

    # Execute query and map to type T
    def to_a(as type : T.class) : Array(T) forall T
      sql, params = to_sql
      @adapter.execute(sql, params, as: type)
    end

    # Get first result or nil
    def first : Hash(String, DB::Any)?
      limited = limit(1)
      results = limited.to_a
      results.first?
    end

    # Get first result mapped to type T or nil
    def first(as type : T.class) : T? forall T
      limited = limit(1)
      results = limited.to_a(as: type)
      results.first?
    end

    # Get first result or raise RecordNotFound
    def first! : Hash(String, DB::Any)
      first || raise RecordNotFound.new(@table)
    end

    # Get first result mapped to type T or raise RecordNotFound
    def first!(as type : T.class) : T forall T
      first(as: type) || raise RecordNotFound.new(@table)
    end

    # Count matching rows
    def count : Int64
      sql, params = count_sql
      @adapter.execute_scalar(sql, params, as: Int64)
    end

    # Check if any matching rows exist
    def exists? : Bool
      count > 0
    end

    # Debug output
    def inspect(io : IO) : Nil
      io << "#<Quo::Query"
      io << " table=:" << @table
      io << " select=" << @select_columns unless @select_columns.empty?
      io << " where=" << @where_clauses.size << " clauses" unless @where_clauses.empty?
      io << " joins=" << @joins.size unless @joins.empty?
      io << " order=" << @order_clauses unless @order_clauses.empty?
      io << " limit=" << @limit_value if @limit_value
      io << " offset=" << @offset_value if @offset_value
      io << " distinct" if @distinct_enabled
      io << ">"
    end

    # Create a copy of this query with modified fields
    # Used internally and by Relation for association joins
    def copy_with(
      select_columns : Array(ColumnRef) = @select_columns,
      where_clauses : Array(Expression) = @where_clauses,
      joins : Array(Join) = @joins,
      order_clauses : Array(OrderClause) = @order_clauses,
      limit_value : Int32? = @limit_value,
      offset_value : Int32? = @offset_value,
      distinct_enabled : Bool = @distinct_enabled
    ) : Query
      Query.new(
        table: @table,
        adapter: @adapter,
        select_columns: select_columns,
        where_clauses: where_clauses,
        joins: joins,
        order_clauses: order_clauses,
        limit_value: limit_value,
        offset_value: offset_value,
        distinct_enabled: distinct_enabled
      )
    end

    # Parse join condition from NamedTuple
    # Format: {left_table: :left_col, eq: {right_table: :right_col}}
    private def parse_join_condition(on : NamedTuple) : JoinCondition
      left_table = nil
      left_column = nil
      right_table = nil
      right_column = nil

      on.each do |key, value|
        if key == :eq
          # This is the right side: {right_table: :right_col}
          value.as(NamedTuple).each do |rt, rc|
            right_table = rt
            right_column = rc.as(Symbol)
          end
        else
          # This is the left side: left_table: :left_col
          left_table = key
          left_column = value.as(Symbol)
        end
      end

      if left_table && left_column && right_table && right_column
        JoinCondition.new(left_table, left_column, right_table, right_column)
      else
        raise QueryError.new("Invalid join condition format. Expected {table: :column, eq: {other_table: :column}}")
      end
    end
  end
end
